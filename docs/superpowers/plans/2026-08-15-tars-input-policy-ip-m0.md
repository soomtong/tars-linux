# TARS Input Policy IP-M0 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 파일 작성과
> 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을 제시하고
> 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는 이 저장소에 적용하지 않는다.

**Goal:** 키보드 경로의 **바닥을 바꾼다.** `handleKey`가 바이트 하나가 아니라
**바이트열**을 돌려주게 하고, 그 위에 첫 손님으로 **Ctrl 제어 문자**를
올린다. 이 milestone이 끝나면 게스트 셸에서 **Ctrl+C가 실제로 프로세스를
죽인다.** 방향키는 아직 없다(IP-M1).

**Design doc:** `docs/superpowers/specs/2026-08-15-tars-input-policy-design.md`

**Tech Stack:** Zig 0.16.0(`@cImport(linux/input.h)`, 크로스/네이티브 타깃
분리), bash, QEMU monitor `sendkey`, Docker(`tars-devcontainer`, arm64)

---

## 왜 이 순서인가

이 milestone은 **저울을 먼저 놓고** 시작한다.

```
Task 1   input_test가 컨테이너에서 실제로 돈다        ← 저울 설치
  ↓      (지금은 빌드만 되고 아무도 실행하지 않는다)
Task 2   handleKey: ?u8 → []const u8                  ← 구조 전환
  ↓      (동작은 그대로. 표현할 수 있는 것만 넓어진다)
Task 3   Ctrl 제어 문자                                ← 첫 손님
  ↓
Task 4   readKeys/main.zig 연결 + initrd에 sleep       ← 게스트에 닿게
  ↓
Task 5   input/check.sh — 네 번째 체인                 ← 게이트
  ↓
Task 6   루트 게이트 등록 + 4체인 전체 통과
```

Task 1이 먼저인 이유는 design doc 결정 10이다. IP는 이 저장소에서 가장 표가
큰 작업이고(keymap, Ctrl 마스크 예외, 특수키 시퀀스, dispatch), 오타 하나가
조용히 지나갈 자리가 많다. **부팅 게이트만으로 덮으려면 시간이 감당되지
않는다.** 그런데 `terminal/build.zig`가 만드는 `input_test`는 x86_64
바이너리라 ZM-M3 이후 arm64 컨테이너에서 실행 자체가 불가능하다. 새 기능을
얹기 전에 얹을 자리에 저울부터 놓는다.

## design doc과 달라지는 것 하나 (미리 밝혀둠)

design doc 결정 4는 modifier **여덟 개**(Shift/Ctrl/Alt/Meta 각 좌우)를
추적한다고 적었고, 그것이 이 서브프로젝트의 최종 모습이다. **IP-M0는 그중
넷(Shift 둘 + Ctrl 둘)만 넣는다.**

이유는 관측 가능성이다. Alt(56/100)와 Meta(125/126)를 지금 추가해도
**동작이 하나도 달라지지 않는다** — 56/100은 keymap에서 `.{ 0, 0 }`이라 이미
아무것도 안 보내고, 125/126은 `code >= keymap.len`에 걸려 이미 무시된다.
검증할 수 없는 코드를 미리 넣지 않는다. 넷은 IP-M2에서 dispatch 표와 함께,
그때 처음으로 관측 가능해지면서 들어온다.

`Context` 구조체(결정 6)도 같은 이유로 IP-M1에서 도착한다 — M0에는 채울
내용이 없다(DECCKM은 M1, swap은 M2).

## 사전 준비

모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서 실행한다.
`main` 브랜치, working tree 깨끗한 상태에서 시작한다.

**`docker run`/`docker build`에 `--platform`을 붙이지 않는다.** 붙이면 ZM-M3에서
없앤 에뮬레이션 층이 그대로 돌아온다
(`docs/decisions/project_build_host_arch.md`).

**100줄이 넘는 파일은 Claude가 `/tmp`에 원본을 만들고 `diff`로 대조한 뒤
사용자가 `cp`로 제자리에 넣는다**(CP-M2에서 48줄이 잘려 나간 뒤 정한 방식).
`terminal/src/input.zig`가 여기 해당한다.

---

## Task 1: 저울을 먼저 놓는다

`input_test`를 **호스트 아키텍처(arm64)** 로 빌드하고, `zig build test`로
실행할 수 있게 하고, `terminal/check.sh`가 그것을 실제로 부르게 한다. 이
Task에서는 `input.zig`를 **한 줄도 고치지 않는다** — 지금 코드가 지금
테스트를 통과한다는 baseline을 확인하는 것이 목적이다.

**Files:**
- Modify: `terminal/build.zig:61-71` (+ 뒤에 step 추가)
- Modify: `terminal/check.sh:19-22`

- [ ] **Step 1: `terminal/build.zig`의 `input_test` 블록을 교체**

`terminal/build.zig:61-71`의 다음 부분을

```zig
    const input_test_mod = b.createModule(.{
        .root_source_file = b.path("src/input_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    input_test_mod.link_libc = true;
    const input_test = b.addExecutable(.{
        .name = "input_test",
        .root_module = input_test_mod,
    });
    b.installArtifact(input_test);
```

이것으로 바꾼다.

```zig
    // ── 여기서부터는 게스트가 아니라 **빌드 호스트**가 실행한다 ──────────
    //
    // project_build_host_arch의 4번 규칙: "이 산출물은 누가 실행하는가"를
    // 먼저 묻는다. input_test는 QEMU 게스트가 아니라 컨테이너가 직접
    // 실행하므로 컨테이너의 아키텍처(arm64)로 빌드해야 한다. 위의 `target`
    // (x86_64 고정)을 그대로 쓰면 빌드는 되지만 실행이 안 된다 — 실제로
    // ZM-M3에서 컨테이너를 arm64로 바꾼 뒤 이 바이너리는 아무도 실행하지
    // 못하는 상태로 남아 있었다.
    //
    // 빈 쿼리 `.{}`가 네이티브다.
    const host_target = b.resolveTargetQuery(.{});

    const input_test_mod = b.createModule(.{
        .root_source_file = b.path("src/input_test.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    input_test_mod.link_libc = true;
    const input_test = b.addExecutable(.{
        .name = "input_test",
        .root_module = input_test_mod,
    });
    b.installArtifact(input_test);

    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
    //
    // 기본 `zig build`와 분리하는 이유는 속도다. 기본 빌드는 x86_64
    // terminal 본체까지 만드느라 vendor 트리(stb_truetype, libghostty-vt)가
    // 준비돼 있어야 하지만, 이 step은 input_test 하나만 필요하다.
    const test_step = b.step("test", "호스트 아키텍처로 도는 검사를 실행한다");
    test_step.dependOn(&b.addRunArtifact(input_test).step);

    // pty_test와 vt_test는 x86_64로 남겨둔다. 호스트로 옮길 수 없어서다:
    //   pty_test  — /usr/bin/fish를 exec한다. 그 fish는 게스트용 x86_64다.
    //   vt_test   — libghostty-vt를 arm64로 빌드해야 하는데 검증된 적이 없다
    //               (src/simd/ 아래에 벡터 코드가 있다).
    // 둘 다 지금은 빌드만 되고 아무도 실행하지 않는다는 사실을 여기 적어둔다.
```

- [ ] **Step 2: 지금 코드가 지금 테스트를 통과하는지 확인 (baseline)**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test"
```

기대 출력:

```
input_event size = 24 (expected 24)
PASS
```

`24`가 나오는 것 자체가 확인 하나다 — `@cImport`가 **arm64 컨테이너의**
`linux/input.h`에서 읽은 `struct input_event`가 x86_64와 같은 24바이트라는
뜻이다(`timeval` 16 + type 2 + code 2 + value 4). 두 아키텍처 모두 64비트라
같다.

**여기서 실패하면 멈추고 알린다.** 예상되는 실패 둘:
- `error: 'linux/input.h' file not found` — 컨테이너에 arm64용
  `linux-libc-dev`가 없다는 뜻. Dockerfile **위쪽**(컨테이너가 쓰는 도구)에
  추가해야 한다.
- `b.resolveTargetQuery` 관련 컴파일 에러 — Zig 0.16의 API가 다르다는 뜻.
  `b.graph.host`가 대안이다.

- [ ] **Step 3: `terminal/check.sh`가 이 검사를 실제로 부르게 한다**

`terminal/check.sh:19-22`의

```bash
if ! ./prepare.sh; then
  echo "FAIL: terminal build failed"
  exit 1
fi
```

바로 **뒤에** 다음을 넣는다.

```bash
# 호스트에서 도는 순수 로직 검사. 부팅보다 먼저 돌린다 — keymap이나 Ctrl
# 마스크의 오타는 QEMU를 띄우지 않고도 잡히고, 여기서 걸리면 아래 4초
# 부팅을 아낀다. IP-M0 전에는 이 바이너리가 빌드만 되고 아무도 실행하지
# 않았다(design doc 결정 10).
if ! zig build test; then
  echo "FAIL: input_test failed"
  exit 1
fi
```

- [ ] **Step 4: TF 체인이 여전히 통과하는지 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/check.sh
```

기대: 맨 끝에 `PASS`. 중간에 `input_event size = 24` / `PASS` 줄이 QEMU
부팅보다 **먼저** 보여야 한다.

- [ ] **Step 5: Commit**

Claude가 수행한다. 커밋 메시지: `Run the input test on the build host`

---

## Task 2: `handleKey`가 바이트열을 돌려주게 한다

이 Task는 **동작을 하나도 바꾸지 않는다.** 표현할 수 있는 것만 넓힌다.
테스트를 먼저 새 시그니처로 바꿔서 컴파일이 깨지는 것을 확인한 뒤 구현을
따라가게 한다.

**Files:**
- Modify: `terminal/src/input_test.zig` (전체 교체)
- Modify: `terminal/src/input.zig:80-142`

- [ ] **Step 1: 테스트를 새 시그니처로 먼저 바꾼다**

`terminal/src/input_test.zig`를 통째로 이 내용으로 바꾼다.

```zig
const std = @import("std");
const input = @import("input.zig");

/// IP-M0부터 handleKey는 바이트 **하나**가 아니라 바이트 **열**을 돌려준다.
/// "보낼 것 없음"은 null이 아니라 빈 슬라이스다.
fn expect(state: *input.State, code: u16, value: i32, want: []const u8) !void {
    const got = state.handleKey(code, value);
    if (std.mem.eql(u8, got, want)) return;
    std.debug.print(
        "FAIL: code={d} value={d} -> got={any}, want={any}\n",
        .{ code, value, got, want },
    );
    return error.UnexpectedBytes;
}

pub fn main() !void {
    // struct input_event가 @cImport로 제대로 넘어왔는지부터 확인한다.
    std.debug.print("input_event size = {d} (expected 24)\n", .{input.eventSize()});
    if (input.eventSize() != 24) {
        std.debug.print("FAIL: unexpected struct input_event size\n", .{});
        return error.UnexpectedEventSize;
    }

    var state: input.State = .{};

    // "hi" 타이핑: 누를 때만 문자가 나오고, 뗄 때는 안 나온다.
    try expect(&state, 35, 1, "h"); // KEY_H press
    try expect(&state, 35, 0, ""); // KEY_H release
    try expect(&state, 23, 1, "i"); // KEY_I press
    try expect(&state, 23, 0, ""); // KEY_I release

    // Enter는 CR을 보낸다.
    try expect(&state, 28, 1, "\r"); // KEY_ENTER press

    // Shift를 누르면 그 자체는 문자가 없고, 이어지는 키가 대문자가 된다.
    try expect(&state, 42, 1, ""); // KEY_LEFTSHIFT press
    try expect(&state, 35, 1, "H"); // KEY_H press (shifted)
    try expect(&state, 42, 0, ""); // KEY_LEFTSHIFT release
    try expect(&state, 35, 1, "h"); // KEY_H press (unshifted 복귀)

    // 좌우 Shift는 각자 추적된다. 왼쪽을 누른 채 오른쪽을 눌렀다 떼도
    // Shift는 풀리지 않아야 한다 — 손은 아직 왼쪽을 누르고 있다.
    try expect(&state, 42, 1, ""); // LEFTSHIFT press
    try expect(&state, 54, 1, ""); // RIGHTSHIFT press
    try expect(&state, 54, 0, ""); // RIGHTSHIFT release
    try expect(&state, 35, 1, "H"); // 여전히 대문자
    try expect(&state, 42, 0, ""); // LEFTSHIFT release
    try expect(&state, 35, 1, "h"); // 이제 소문자

    // Shift + 숫자 = 기호.
    try expect(&state, 54, 1, ""); // KEY_RIGHTSHIFT press
    try expect(&state, 2, 1, "!"); // KEY_1 press (shifted)
    try expect(&state, 54, 0, ""); // KEY_RIGHTSHIFT release

    // 자동 반복(value=2)도 문자를 만든다. 방향키를 누르고 있으면 계속
    // 움직여야 하므로 이 성질은 오히려 필요하다.
    try expect(&state, 30, 2, "a"); // KEY_A autorepeat

    // 표에 없는 키코드는 조용히 무시한다.
    try expect(&state, 200, 1, "");

    std.debug.print("PASS\n", .{});
}
```

- [ ] **Step 2: 실패하는 것을 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test"
```

기대: **컴파일 에러.** `handleKey`가 `?u8`을 돌려주는데 `std.mem.eql(u8, ...)`에
넘기고 있으므로 타입이 맞지 않는다. 대략 이런 메시지다.

```
error: expected type '[]const u8', found '?u8'
```

- [ ] **Step 3: `input.zig`의 `State`를 바이트열 반환으로 바꾼다**

`terminal/src/input.zig:80-112`의 `State` 정의를 이것으로 바꾼다.

```zig
/// "보낼 것이 없다"를 뜻하는 빈 슬라이스. IP-M0 전에는 `null`이 이 자리였다.
const none: []const u8 = &[_]u8{};

/// modifier 상태를 들고 있는 작은 상태 머신.
/// design doc 결정 2의 세 단계 중 1번(modifier 갱신)과 3번(기본 번역)에
/// 해당한다. 2번(조합 dispatch)은 IP-M2에서 들어온다.
pub const State = struct {
    shift_left: bool = false,
    shift_right: bool = false,

    /// 반환 슬라이스의 저장소. 힙을 쓰지 않는다.
    ///
    /// 호출자(readKeys)가 반환값을 즉시 out으로 복사하므로, 같은 read
    /// 배치의 다음 키가 이 배열을 덮어써도 안전하다. 8바이트인 이유는 이
    /// 서브프로젝트에서 가장 긴 시퀀스가 6바이트이기 때문이다
    /// (`ESC [ 1 ; 5 D` 형태, IP-M1).
    seq: [8]u8 = undefined,

    fn shifted(self: State) bool {
        return self.shift_left or self.shift_right;
    }

    /// 바이트 하나를 seq에 담아 슬라이스로 돌려준다.
    fn one(self: *State, byte: u8) []const u8 {
        self.seq[0] = byte;
        return self.seq[0..1];
    }

    /// EV_KEY 이벤트 하나를 처리한다.
    /// value: 0=뗌, 1=누름, 2=자동 반복.
    /// PTY로 보낼 바이트열을 반환한다. 보낼 것이 없으면 빈 슬라이스다.
    pub fn handleKey(self: *State, code: u16, value: i32) []const u8 {
        switch (code) {
            c.KEY_LEFTSHIFT => {
                self.shift_left = value != 0;
                return none;
            },
            c.KEY_RIGHTSHIFT => {
                self.shift_right = value != 0;
                return none;
            },
            else => {},
        }
        // 뗄 때는 아무것도 보내지 않는다. 누름(1)과 자동 반복(2)만 문자를 만든다.
        if (value == 0) return none;
        if (code >= keymap.len) return none;

        const ch = keymap[code][if (self.shifted()) 1 else 0];
        return if (ch == 0) none else self.one(ch);
    }
};
```

- [ ] **Step 4: `readKeys`를 새 반환 타입에 맞춘다**

`terminal/src/input.zig:132-140`의 while 루프 본문을 바꾼다. 기존

```zig
        if (self.handleKey(ev.code, ev.value)) |ch| {
            out[written] = ch;
            written += 1;
        }
```

을 이것으로.

```zig
        // 키 하나가 여러 바이트가 될 수 있으므로(IP-M1의 이스케이프 시퀀스)
        // 슬라이스를 통째로 옮긴다. out이 모자라면 거기서 멈춘다 — 다음
        // poll에서 이어지지 않고 버려지지만, out은 64바이트이고 한 번의
        // read에 그만큼의 키가 들어오는 일은 사람 손으로는 일어나지 않는다.
        for (self.handleKey(ev.code, ev.value)) |byte| {
            if (written >= out.len) break;
            out[written] = byte;
            written += 1;
        }
```

- [ ] **Step 5: 통과하는 것을 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test"
```

기대:

```
input_event size = 24 (expected 24)
PASS
```

- [ ] **Step 6: Commit**

Claude가 수행한다. 커밋 메시지: `Return a byte sequence from each key event`

---

## Task 3: Ctrl 제어 문자

바닥이 넓어졌으니 첫 손님을 올린다. Ctrl+C가 프로세스를 죽이는 것은
**우리가 시그널을 보내서가 아니다** — `0x03` 한 바이트를 PTY master에 쓰면,
커널의 line discipline이 `ISIG`와 `VINTR == 0x03`을 보고 foreground process
group에 SIGINT를 직접 보낸다(design doc 결정 3). 우리가 할 일은 그 바이트를
만드는 것뿐이다.

**Files:**
- Modify: `terminal/src/input_test.zig` (테스트 추가)
- Modify: `terminal/src/input.zig` (`State`)

- [ ] **Step 1: 실패하는 테스트를 먼저 추가**

`terminal/src/input_test.zig`의 `try expect(&state, 200, 1, "");` **바로
뒤에**, `std.debug.print("PASS\n", .{});` **앞에** 다음을 넣는다.

```zig
    // ── Ctrl 제어 문자 (IP-M0) ──────────────────────────────────────────
    //
    // 규칙은 한 줄이다: Shift를 먼저 적용해 문자를 정한 뒤 `& 0x1F`.
    // ASCII에서 제어 문자 0x00~0x1F는 `@ABC…Z[\]^_`(0x40~0x5F)에서 상위 두
    // 비트를 뗀 것이므로, 마스크가 곧 정의다.

    try expect(&state, 29, 1, ""); // KEY_LEFTCTRL press — 그 자체는 문자 없음
    try expect(&state, 46, 1, "\x03"); // Ctrl+C → SIGINT를 부르는 바이트
    try expect(&state, 32, 1, "\x04"); // Ctrl+D → EOF
    try expect(&state, 44, 1, "\x1a"); // Ctrl+Z → SIGTSTP
    try expect(&state, 43, 1, "\x1c"); // Ctrl+\ → SIGQUIT
    try expect(&state, 26, 1, "\x1b"); // Ctrl+[ → ESC
    try expect(&state, 57, 1, "\x00"); // Ctrl+Space → NUL

    // 마스크가 의미 있는 것은 문자가 0x40~0x7F일 때뿐이다. Ctrl+1에
    // 적용하면 0x31 & 0x1F = 0x11(XON)이 나오는데 아무도 그런 뜻으로 쓰지
    // 않는다. 대상이 아닌 문자는 Ctrl을 무시하고 원래 문자를 보낸다.
    try expect(&state, 2, 1, "1"); // Ctrl+1 → 그냥 '1'

    // Shift가 함께 눌려도 제어 문자는 같다.
    try expect(&state, 42, 1, ""); // LEFTSHIFT press
    try expect(&state, 46, 1, "\x03"); // Ctrl+Shift+C → 여전히 0x03
    // Shift+2는 '@'이고 '@' & 0x1F = 0x00이다.
    try expect(&state, 3, 1, "\x00"); // Ctrl+Shift+2 → NUL
    try expect(&state, 42, 0, ""); // LEFTSHIFT release

    try expect(&state, 29, 0, ""); // KEY_LEFTCTRL release
    try expect(&state, 46, 1, "c"); // Ctrl을 떼면 다시 평문

    // 오른쪽 Ctrl도 같다.
    try expect(&state, 97, 1, ""); // KEY_RIGHTCTRL press
    try expect(&state, 46, 1, "\x03");
    try expect(&state, 97, 0, "");

    // 좌우 Ctrl 각자 추적. 왼쪽을 누른 채 오른쪽을 눌렀다 떼도 안 풀린다.
    try expect(&state, 29, 1, ""); // LEFTCTRL press
    try expect(&state, 97, 1, ""); // RIGHTCTRL press
    try expect(&state, 97, 0, ""); // RIGHTCTRL release
    try expect(&state, 46, 1, "\x03"); // 여전히 Ctrl
    try expect(&state, 29, 0, ""); // LEFTCTRL release
    try expect(&state, 46, 1, "c");
```

- [ ] **Step 2: 실패하는 것을 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test"
```

기대: 컴파일은 되고 **실행이 실패**한다. 첫 실패는 `code=46 value=1`이며,
`got={ 99 }`(`'c'`), `want={ 3 }`이다. `KEY_LEFTCTRL`(29)이 아직 modifier로
인식되지 않아 keymap의 `.{ 0, 0 }`에 걸려 빈 슬라이스가 나오고, Ctrl 상태가
없으니 `c`가 그대로 나온다.

- [ ] **Step 3: `State`에 Ctrl을 추가**

`terminal/src/input.zig`의 `State`를 이렇게 고친다. 세 곳이다.

먼저 필드 둘을 추가한다.

```zig
pub const State = struct {
    shift_left: bool = false,
    shift_right: bool = false,
    // Ctrl 둘을 좌우로 나눠 두는 이유는 Shift와 같다 — 하나를 누른 채
    // 다른 하나를 눌렀다 떼도 풀리면 안 된다.
    ctrl_left: bool = false,
    ctrl_right: bool = false,

    seq: [8]u8 = undefined,
```

다음으로 `shifted()` 옆에 `ctrl()`과 `control()`을 추가한다.

```zig
    fn shifted(self: State) bool {
        return self.shift_left or self.shift_right;
    }

    fn ctrled(self: State) bool {
        return self.ctrl_left or self.ctrl_right;
    }

    /// Ctrl과 조합됐을 때 보낼 제어 문자. 대상이 아니면 null.
    ///
    /// 마스크(& 0x1F)는 문자가 0x40~0x7F일 때만 의미가 있다. Ctrl+1에
    /// 적용하면 0x11(XON)이 나오는데 아무도 그런 뜻으로 쓰지 않으므로,
    /// 대상을 여기 적힌 것으로 명시적으로 한정한다. xterm이 하는 것과 같다.
    fn control(ch: u8) ?u8 {
        return switch (ch) {
            'a'...'z', 'A'...'Z' => ch & 0x1f,
            '@', '[', '\\', ']', '^', '_' => ch & 0x1f,
            ' ' => 0x00,
            '?' => 0x7f,
            else => null,
        };
    }
```

마지막으로 `handleKey`의 switch에 Ctrl 두 갈래를 넣고, 반환 직전에 Ctrl
번역을 끼운다.

```zig
    pub fn handleKey(self: *State, code: u16, value: i32) []const u8 {
        switch (code) {
            c.KEY_LEFTSHIFT => {
                self.shift_left = value != 0;
                return none;
            },
            c.KEY_RIGHTSHIFT => {
                self.shift_right = value != 0;
                return none;
            },
            c.KEY_LEFTCTRL => {
                self.ctrl_left = value != 0;
                return none;
            },
            c.KEY_RIGHTCTRL => {
                self.ctrl_right = value != 0;
                return none;
            },
            else => {},
        }
        if (value == 0) return none;
        if (code >= keymap.len) return none;

        const ch = keymap[code][if (self.shifted()) 1 else 0];
        if (ch == 0) return none;

        // Ctrl이 눌려 있고 이 문자가 마스크 대상이면 제어 문자로 바꾼다.
        // 대상이 아니면(숫자 등) Ctrl을 무시하고 원래 문자를 보낸다.
        if (self.ctrled()) {
            if (control(ch)) |ctl| return self.one(ctl);
        }
        return self.one(ch);
    }
```

- [ ] **Step 4: keymap 주석 두 줄을 갱신**

`terminal/src/input.zig`의 29번과 42/54번 줄 주석이 이제 사실과 다르다.

```zig
    .{ 0, 0 }, // 29: KEY_LEFTCTRL (이번 범위 밖)
```

를

```zig
    .{ 0, 0 }, // 29: KEY_LEFTCTRL — modifier로 처리한다(아래 handleKey)
```

로 바꾼다. 56번(`KEY_LEFTALT`)의 주석은 **그대로 둔다** — Alt는 아직 정말로
범위 밖이다(IP-M2).

- [ ] **Step 5: 통과하는 것을 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build test"
```

기대:

```
input_event size = 24 (expected 24)
PASS
```

- [ ] **Step 6: Commit**

Claude가 수행한다. 커밋 메시지: `Turn Ctrl combinations into control characters`

---

## Task 4: 게스트에 닿게 한다

여기까지는 컨테이너 안의 순수 로직이다. 이제 실제 부팅에서 확인할 준비를
한다. `main.zig`는 고칠 것이 없고(`readKeys`의 시그니처가 그대로다),
**게이트가 쓸 `sleep`을 initrd에 넣는 것**이 이 Task의 실질이다.

`sleep`이 필요한 이유는 design doc 결정 3을 **제대로** 검사하기 위해서다.
프롬프트에서 Ctrl+C를 눌러 줄이 취소되는 것만 보면 "셸이 그 바이트를
받았다"까지만 증명된다. **커널이 자식 프로세스 그룹에 SIGINT를 보냈다**는
주장을 검사하려면 죽일 자식이 하나 있어야 한다.

`sleep`은 `cat`/`uname`/`mkdir`과 같은 coreutils 패키지에 들어 있고, 그
패키지는 이미 sysroot에 구워져 있다. **`devcontainer/Dockerfile`은 고치지
않는다.**

**Files:**
- Modify: `kernel/make_initrd.sh:107-120`

- [ ] **Step 1: `sleep`을 initrd에 넣는다**

`kernel/make_initrd.sh:107-110`의

```bash
cp "$SYSROOT/usr/bin/cat" "$WORKDIR/usr/bin/cat"
cp "$SYSROOT/usr/bin/uname" "$WORKDIR/usr/bin/uname"
cp "$SYSROOT/usr/bin/mkdir" "$WORKDIR/usr/bin/mkdir"
chmod 0755 "$WORKDIR/usr/bin/cat" "$WORKDIR/usr/bin/uname" "$WORKDIR/usr/bin/mkdir"
```

를 이것으로 바꾼다.

```bash
cp "$SYSROOT/usr/bin/cat" "$WORKDIR/usr/bin/cat"
cp "$SYSROOT/usr/bin/uname" "$WORKDIR/usr/bin/uname"
cp "$SYSROOT/usr/bin/mkdir" "$WORKDIR/usr/bin/mkdir"
# IP-M0: 게이트가 Ctrl+C로 죽일 자식이 필요하다. 프롬프트에서 줄이
# 취소되는 것만 보면 "셸이 바이트를 받았다"까지만 증명된다 — 커널이
# foreground process group에 SIGINT를 보낸다는 것(design doc 결정 3)을
# 검사하려면 셸이 아닌 프로세스가 하나 떠 있어야 한다. coreutils는 이미
# sysroot에 있으므로 Dockerfile은 건드리지 않는다.
cp "$SYSROOT/usr/bin/sleep" "$WORKDIR/usr/bin/sleep"
chmod 0755 "$WORKDIR/usr/bin/cat" "$WORKDIR/usr/bin/uname" \
           "$WORKDIR/usr/bin/mkdir" "$WORKDIR/usr/bin/sleep"
```

그리고 `kernel/make_initrd.sh:120`의 `copy_lib_deps` 줄 뒤에 한 줄 추가.

```bash
copy_lib_deps "$WORKDIR/usr/bin/mkdir"
copy_lib_deps "$WORKDIR/usr/bin/sleep"
```

- [ ] **Step 2: initrd가 만들어지고 `sleep`이 들어갔는지 확인**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c \
  "cd init && zig build && cd ../terminal && ./prepare.sh && cd ../kernel && ./make_initrd.sh && zcat initrd.cpio | cpio -t 2>/dev/null | grep -E 'usr/bin/(sleep|cat)$'"
```

기대 출력:

```
./usr/bin/cat
./usr/bin/sleep
```

`make_initrd.sh`가 소네임을 찍고 죽으면 sysroot에 없는 라이브러리를
요구한다는 뜻이지만, `sleep`은 `cat`과 같은 패키지·같은 의존이라 그럴
가능성은 낮다.

- [ ] **Step 3: Commit**

Claude가 수행한다. 커밋 메시지: `Put sleep into the initrd for the input gate`

---

## Task 5: 네 번째 체인 `input/check.sh`

부팅 **한 번**. 디스크는 물리지 않는다 — `/config` mount가 실패하면 CP가
만든 폴백이 fish로 떨어뜨려 주므로, 이 게이트는 그 폴백 경로도 덤으로
밟는다(design doc 결정 11).

**Files:**
- Create: `input/check.sh`

- [ ] **Step 1: 디렉터리를 만든다**

```bash
mkdir -p input
```

- [ ] **Step 2: `input/check.sh` 작성**

100줄이 넘으므로 Claude가 `/tmp/ip_check.sh`에 원본을 만들고, `diff`로
대조한 뒤 `cp`로 옮긴다. 내용은 다음과 같다.

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# IP 체인 — 키보드 입력 정책.
#
# CP 체인과 달리 부팅은 **한 번**이다. 증명할 것이 전부 한 세션 안에 있다.
# 디스크도 물리지 않는다: /config mount가 실패하면 init이 fish로 폴백하므로
# (CP design doc "설정 하나로 부팅이 막히지 않게 하는 네 장치"), 이 체인은
# 그 폴백 경로를 덤으로 한 번 더 밟는다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

# 호스트에서 도는 순수 로직 검사를 부팅보다 먼저 돌린다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: input_test failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# BF/TF는 45455, CP는 45456. 죽다 만 QEMU에 엉뚱한 키를 보내지 않으려고
# 체인마다 포트를 나눈다.
MONITOR_PORT=45457

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# sendkey가 보내는 것은 문자가 아니라 **키**다. modifier는 `-`로 붙인다
# (ctrl-c는 Ctrl을 누른 채 c를 누르는 것). 게스트 쪽에서 evdev 이벤트를
# 다시 바이트로 바꾸는 것은 우리 코드(terminal/src/input.zig)이므로, 이
# 게이트는 QEMU의 스캔코드 변환과 우리 keymap 두 겹을 함께 검사한다.
type_keys() {
  local k
  for k in "$@"; do
    echo "sendkey $k" >&3
    sleep 0.3
  done
}

report_failure() {
  local msg="$1"
  echo "FAIL: ${msg}"
  echo "--- markers ---"
  local marker
  for marker in \
    "tars-init: started terminal" \
    "terminal: opened /dev/input/event0" \
    "terminal: spawned child pid" \
    "terminal: screen>" \
    "terminal: key>"; do
    if grep -q "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- last screen dumps ---"
  grep "terminal: screen>" "$LOG" | tail -n 5
  echo "--- tail ---"
  tail -n 60 "$LOG"
  exit 1
}

qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

# "terminal: screen>" 첫 줄이 곧 DRM 열기 + 폰트 래스터라이즈 + evdev 열기 +
# 셸 spawn + 첫 렌더가 전부 끝났다는 신호다. TF/CP 체인과 같은 신호를 쓴다.
READY=0
for _ in $(seq 1 120); do
  if grep -q "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
if [ "$READY" != "1" ]; then
  report_failure "terminal never rendered a prompt; there was nothing to type into"
fi
sleep 1

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
if [ "$CONNECTED" != "1" ]; then
  report_failure "could not connect to QEMU monitor on port ${MONITOR_PORT}"
fi

# ── 1) 죽일 자식을 하나 띄운다 ─────────────────────────────────────────
# sleep 100 &  이 아니라 foreground로 띄운다. SIGINT는 **foreground process
# group**에만 가기 때문이다 — 그게 이 검사의 요점이다.
echo "=== typing 'sleep 100' ==="
type_keys s l e e p spc 1 0 0 ret

# 셸이 정말 sleep을 실행했는지 눈으로 확인할 방법이 화면에는 없다(출력이
# 없는 명령이다). 대신 프롬프트가 돌아오지 않는다는 것으로 안다. 여기서는
# 그냥 실행될 시간을 준다.
sleep 2

# ── 2) Ctrl+C ─────────────────────────────────────────────────────────
# 이 한 줄이 IP-M0가 증명하려는 것 전부다:
#   sendkey ctrl-c → QEMU 스캔코드 → 커널 atkbd → evdev(KEY_LEFTCTRL, KEY_C)
#   → 우리 input.zig가 0x03을 만든다 → pty.write → 커널 line discipline이
#   ISIG/VINTR을 보고 foreground process group에 SIGINT → sleep이 죽는다
echo "=== sending ctrl-c ==="
echo "sendkey ctrl-c" >&3
sleep 1

# ── 3) 셸이 살아 돌아왔는지 확인 ──────────────────────────────────────
# sleep이 죽었으면 프롬프트가 돌아왔고, 이 명령이 실행되어 출력이 나온다.
# 죽지 않았으면 타이핑한 글자는 화면에 에코만 되고(line discipline이 에코를
# 한다) 명령은 영영 실행되지 않는다 — 그래서 아래 행이 나타나지 않는다.
echo "=== typing 'echo ctrlcok' ==="
type_keys e c h o spc c t r l c o k ret

# dumpScreen은 화면 전체를 한 줄에 찍고 행을 " | "로 나눈다. 그래서 **행의
# 첫머리가 ctrlcok인 것**이 명령의 출력이다 — 방금 타이핑한 명령줄에도
# ctrlcok가 들어 있지만 그 행은 프롬프트와 echo로 시작한다.
FOUND=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*| ctrlcok" "$LOG"; then FOUND=1; break; fi
  sleep 1
done

exec 3<&-
exec 3>&-

kill "$QEMU_PID" 2>/dev/null
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""

if [ "$FOUND" != "1" ]; then
  report_failure "ctrl-c did not return the shell to a prompt (sleep survived, or the byte never arrived)"
fi
echo "ctrl-c killed the foreground child and the shell came back"

# 키가 아예 도달하지 않은 경우와 도달했지만 뜻이 틀린 경우를 구분한다.
# main.zig가 키를 PTY로 보낼 때마다 이 줄을 찍는다.
if ! grep -q "terminal: key>" "$LOG"; then
  report_failure "the terminal never forwarded a key to the PTY"
fi

if grep -q "Attempted to kill init" "$LOG"; then
  report_failure "kernel panicked because PID 1 exited"
fi

echo "--- init log ---"
grep 'tars-init:' "$LOG" || true

echo "PASS"
exit 0
```

- [ ] **Step 3: 실행 권한을 주고 단독으로 돌려본다**

```bash
chmod +x input/check.sh
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash input/check.sh
```

기대: 맨 끝에 `PASS`, 그 앞에
`ctrl-c killed the foreground child and the shell came back`.

**여기서 실패하면 `report_failure`가 찍는 마커 목록과 마지막 화면 덤프
다섯 줄을 그대로 붙여 달라.** 구분해야 할 실패가 셋이다.

- `terminal: key>`가 없다 → `sendkey`가 게스트에 아예 안 닿았다. QEMU
  monitor 연결이나 키 이름 문제다.
- `terminal: key>`는 있는데 `ctrlcok` 행이 없다 → 바이트는 갔지만 뜻이
  틀렸다. `sendkey ctrl-c`가 KEY_LEFTCTRL을 안 보냈거나, 우리 마스크가
  틀렸다.
- 화면 덤프에 `sleep 100`이 안 보인다 → 타이핑 자체가 실패했다.

- [ ] **Step 4: Commit**

Claude가 수행한다. 커밋 메시지: `Add the input chain that proves Ctrl+C works`

---

## Task 6: 루트 게이트에 등록

**Files:**
- Modify: `check.sh:35-52`

- [ ] **Step 1: 네 번째 체인을 추가**

`check.sh:52`의 `run_chain "CP-M2" ./config/check.sh` **뒤에** 한 줄을 넣고,
그 위 주석 블록 끝에 설명을 덧붙인다.

```bash
# IP 체인은 키보드 입력 정책을 본다. CP처럼 monitor sendkey로 게스트에
# 타이핑하지만 디스크는 물지 않고 부팅도 한 번뿐이다 — 증명할 것이 한 세션
# 안에 있기 때문이다. 그래서 루트 게이트의 총 부팅 횟수는 12회에서 15회가
# 된다.
run_chain "BF-M4" ./boot/check.sh
run_chain "TF-M4" ./terminal/check.sh
run_chain "CP-M2" ./config/check.sh
run_chain "IP-M0" ./input/check.sh
```

- [ ] **Step 2: 전체 게이트 (오래 걸린다 — 20분 안팎)**

```bash
time docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash check.sh
```

기대: 마지막 줄이
`TARS check PASS: all chains 3/3 consecutive runs succeeded`.

**측정값을 기록해 달라** — 실제 소요 시간과, IP 체인 3회가 각각 얼마나
걸렸는지. design doc의 "+4~6분" 예상이 맞는지 여기서 확인된다.

- [ ] **Step 3: Commit**

Claude가 수행한다. 커밋 메시지: `Point the aggregate gate at the input chain`

---

## 완료 조건

- [ ] `zig build test`가 컨테이너에서 돌고 `input_test`가 PASS한다
- [ ] `terminal/check.sh`가 부팅 전에 그 검사를 부른다
- [ ] `handleKey`가 `[]const u8`을 돌려준다
- [ ] Ctrl+letter, `Ctrl+[`, `Ctrl+\`, `Ctrl+Space`가 제어 문자가 되고
      `Ctrl+1`은 그냥 `1`이다
- [ ] 좌우 Shift와 좌우 Ctrl이 각자 추적된다
- [ ] `input/check.sh`가 게스트에서 `sleep 100`을 Ctrl+C로 죽인다
- [ ] 루트 게이트가 4체인 3/3으로 PASS한다

## 이 milestone이 남기는 것 (IP-M1이 이어받는다)

- `State.seq`는 8바이트인데 M0에서는 항상 1바이트만 쓴다. 이스케이프
  시퀀스가 M1의 첫 손님이다.
- `Context` 구조체가 아직 없다. M1이 DECCKM과 함께 들여온다.
- keymap 테이블은 여전히 코드 57에서 끝난다. 방향키는 M1이다.
- Alt/Meta 넷은 여전히 추적되지 않는다. M2다.
- `TERM`은 여전히 `linux`다(거짓말 중). M1이 `xterm`으로 고친다.
