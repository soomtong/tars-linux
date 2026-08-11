# TF-M3 (evdev 키보드 입력) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **이 저장소(tars-linux)는 예외:** `CLAUDE.md`에 명시된 대로 파일 작성과 명령
> 실행은 **사용자가 직접** 하고, Claude는 설명 + 승인된 내용의 git commit만
> 수행하는 pairing 방식을 쓴다. 위 서브스킬들이 기본으로 제안하는
> subagent-driven/inline 자동 실행은 이 저장소에 적용하지 않는다
> (`docs/decisions/feedback_commit_delegation.md`,
> `docs/decisions/feedback_execution_scope.md` 참고 — 색인은 `MEMORY.md`).

**Goal:** 커널에 evdev + i8042(PS/2) 키보드 경로를 켜고, Terminal Foundation
앱이 `/dev/input/event0`에서 키 이벤트를 읽어 PTY master로 써 넣고, 그
결과로 돌아온 출력을 다시 파싱해 프레임버퍼를 갱신하는 **이벤트 루프**를
만든다. 최종적으로 QEMU monitor `sendkey`로 주입한 타이핑이 대화형 `fish`를
움직이고 그 결과가 화면에 나타나는 것을 자동 검증한다. (Terminal Foundation
MVP 종료점)

**Architecture:** `main.zig`를 "한 번 읽고 한 번 그리는 직선 파이프라인"에서
`poll(2)`로 두 fd(evdev, PTY master)를 동시에 기다리는 루프로 바꾼다. 이를
위해 세 모듈이 바뀐다 — 신규 `input.zig`(evdev 파싱 + US QWERTY 키맵 +
Shift 상태), `pty.zig`(임의 프로그램 실행 + winsize 전달 + 1회 read),
`vt.zig`(호출마다 버려지던 `Terminal`을 **상태를 유지하는 `Screen`**으로
승격). 화면 크기는 프레임버퍼 해상도에서 한 번 계산해 렌더러·`Terminal`·
`forkpty` winsize 세 곳에 같은 값을 넘긴다. 자식 프로세스는 먼저 `cat`
(에코만 하므로 화면 기대값이 완전히 예측 가능)으로 루프를 검증한 뒤
대화형 `fish`로 교체한다.

**Tech Stack:** Zig 0.16.0, Linux 6.18.42 (`CONFIG_INPUT_EVDEV` /
`CONFIG_KEYBOARD_ATKBD` / `CONFIG_SERIO_I8042` 신규 활성화),
libc `poll()`/`forkpty()`, `libghostty-vt`(vendored), QEMU monitor
`sendkey` + `screendump`.

---

## 이 milestone이 답하는 질문 (HANDOFF의 숙제)

`HANDOFF.md`가 "TF-M3에서 함께 검증할 것"으로 남긴 Zig ↔ C 상호운용 질문에
대해, 이 plan은 **미리 예측을 적어두고** 실행으로 확인한다.

**가설 1 — `struct input_event`는 translate-c로 잘 넘어온다.**
근거: 이 구조체는 `struct timeval time; __u16 type; __u16 code; __s32 value;`
로, **비트필드가 없다.** translate-c가 구조체를 opaque로 강등시키는 알려진
한계(ziglang/zig#1499, #4001)는 비트필드가 있을 때 발동하므로 여기엔
해당하지 않을 것이다.

**가설 2 — `EVIOCGBIT` 같은 ioctl 매크로는 여전히 못 가져온다.**
근거: `_IOR(...)` 매크로 확장이라 `drm.zig:108-110`이 `_IOWR`을 손으로 비트
연산으로 재구현해야 했던 것과 같은 상황이다.

이번 milestone은 장치가 키보드 하나뿐인 QEMU 환경이라 `/dev/input/event0`을
하드코딩하고 ioctl 열거를 아예 하지 않는다(YAGNI). 따라서 실제로 확인되는
것은 **가설 1**이고, 가설 2는 "이번엔 필요조차 없었다"로 남는다. 결론이
"UAPI 구조체는 되지만 ioctl 매크로는 안 된다"로 나오면, 앞으로 커널 UAPI를
쓸 때마다 "구조체는 `@cImport`, 매크로는 손으로"라는 규칙을 갖고 가면 된다.

가설 1이 **틀리면**(컴파일 에러 또는 `@sizeOf`가 24가 아님) Task 2 Step 3의
대안 코드(`extern struct` 손 정의)로 바로 전환한다.

---

## 이번 범위에서 뺀 것 (YAGNI)

- **커서 그리기** — 어디에 타이핑 중인지 눈으로 보기엔 좋지만 `RenderState`의
  커서 API를 새로 조사해야 하고, 검증 게이트에는 불필요하다.
- **장치 열거(`EVIOCGBIT`)** — QEMU에 입력 장치가 하나뿐이라 `event0`
  하드코딩으로 충분하다.
- **`EVIOCGRAB`(독점 grab)** — 커널 VT도 같은 키를 받지만 `console=ttyS0` +
  `-vga none`이라 화면에 간섭하지 않는다.
- **Meta(Cmd) 조합 dispatch, 탭 전환, 마우스** — design doc이 명시한 MVP 비목표.
- **부분 갱신(dirty rect)** — 매 갱신마다 화면 전체를 다시 그린다. 키 입력
  빈도에서 성능 문제가 될 수 없다.

---

## 사전 확인 (Task 0)

- [ ] **Step 1: 현재 상태 확인**

```bash
git log --oneline -3
git status
```

Expected: 최신 커밋이 `17079b0`(HANDOFF 갱신)이고 working tree가 깨끗함.

- [ ] **Step 2: Zig가 `linux/input.h`를 제공하는지 확인**

Zig 툴체인은 자체 배포판에 리눅스 UAPI 헤더를 포함한다. 이 Task 전체가 그
헤더에 의존하므로 먼저 존재를 확인한다.

```bash
docker run --rm --platform linux/amd64 tars-devcontainer \
  bash -c 'find "$(dirname "$(readlink -f "$(which zig)")")" -name input.h -path "*linux*" | head'
```

Expected: `.../lib/libc/include/any-linux-any/linux/input.h` 같은 경로가
최소 하나 출력됨.

**만약 아무것도 안 나오면:** 컨테이너의 시스템 헤더를 대신 쓴다.

```bash
docker run --rm --platform linux/amd64 tars-devcontainer ls -la /usr/include/linux/input.h
```

이것도 없으면 `linux-libc-dev` 패키지가 필요하다는 뜻이므로, Task 2 Step 3의
**대안 경로(손으로 `extern struct` 정의)**로 바로 간다.

---

## Task 1: 커널에 evdev + i8042(PS/2) 키보드 경로 켜기

**목적:** 지금 `kernel/.config`는 입력 코어(`CONFIG_INPUT=y`)만 켜져 있고
키보드 드라이버도, `/dev/input/event*`를 만드는 evdev도 없다. 즉 QEMU 안에서
`/dev/input/` 디렉터리가 비어 있다. 코드를 한 줄도 쓰기 전에 **커널이 키보드를
인식하는지부터** 확인한다.

**Files:**
- Modify: `kernel/.config`

- [ ] **Step 1: `kernel/.config` 수정**

아래 세 줄을 찾아서(각각 957~983번째 줄 근처) 바꾼다.

```
# CONFIG_INPUT_EVDEV is not set
```
→
```
CONFIG_INPUT_EVDEV=y
```

```
# CONFIG_INPUT_KEYBOARD is not set
```
→
```
CONFIG_INPUT_KEYBOARD=y
CONFIG_KEYBOARD_ATKBD=y
```

```
# CONFIG_SERIO is not set
```
→
```
CONFIG_SERIO=y
CONFIG_SERIO_I8042=y
CONFIG_SERIO_LIBPS2=y
```

각각이 무슨 일을 하는지:

| 옵션 | 역할 |
|---|---|
| `CONFIG_SERIO` / `CONFIG_SERIO_I8042` | 메인보드의 PS/2 컨트롤러(i8042 칩) 드라이버. QEMU의 `pc`/`q35` 머신에 기본 내장돼 있어 실행 인자를 바꿀 필요가 없다. |
| `CONFIG_SERIO_LIBPS2` | PS/2 프로토콜 공용 헬퍼. `KEYBOARD_ATKBD`가 `select`하므로 사실 자동으로 켜지지만, 명시해두면 `.config`만 읽어도 의도가 보인다. |
| `CONFIG_KEYBOARD_ATKBD` | AT/PS-2 키보드 드라이버. 스캔코드를 받아 **input 코어에 keycode로 올린다**. |
| `CONFIG_INPUT_EVDEV` | input 코어의 이벤트를 `/dev/input/eventN` 캐릭터 장치로 **사용자 공간에 노출**한다. 우리가 실제로 읽을 파일이 여기서 생긴다. |

`kernel/build.sh`가 빌드 전에 `make olddefconfig`을 돌리므로, 의존성이 빠진
게 있어도 kconfig가 기본값으로 채워준다.

- [ ] **Step 2: 커널 재빌드 + 부팅 로그에서 키보드 인식 확인**

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c '
set -e
(cd kernel && ./build.sh)
(cd init && cargo build --release)
(cd terminal && zig build)
(cd kernel && ./make_initrd.sh)
timeout 30 qemu-system-x86_64 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none -device virtio-gpu-pci -display none \
  -serial file:/tmp/boot.log -no-reboot || true
echo "===== input-related dmesg ====="
grep -iE "i8042|serio|^input:" /tmp/boot.log || echo "(none found)"
'
```

Expected: 마지막 블록에 아래와 **비슷한** 줄들이 나온다.

```
i8042: PNP: PS/2 Controller [PNP0303:KBD,PNP0f13:MOU] at 0x60,0x64 irq 1,12
serio: i8042 KBD port at 0x60,0x64 irq 1
input: AT Translated Set 2 keyboard as /devices/platform/i8042/serio0/input/input0
```

`input: AT Translated Set 2 keyboard as ...` 줄이 **핵심**이다 — 커널이
키보드를 input 장치로 등록했다는 뜻이고, `CONFIG_INPUT_EVDEV=y`이므로 이
장치에 대해 devtmpfs가 `/dev/input/event0`을 자동으로 만든다. `init`은 이미
`/dev`에 devtmpfs를 마운트하므로(`init/src/main.rs:100`) **init 수정은
필요 없다** — TF-M2의 devpts와 달리 devtmpfs가 알아서 해준다.

**만약 `(none found)`이 나오면:** `.config` 수정이 `olddefconfig`에 의해
되돌려졌을 수 있다. 실제 빌드에 쓰인 설정을 확인한다.

```bash
grep -E "CONFIG_(INPUT_EVDEV|KEYBOARD_ATKBD|SERIO_I8042)" kernel/build/.config
```

세 줄 모두 `=y`여야 한다. `is not set`이 있으면 의존성이 빠진 것이므로 그
옵션의 `depends on`을 커널 소스(`src/linux-6.18.42/drivers/input/Kconfig`,
`drivers/input/keyboard/Kconfig`, `drivers/input/serio/Kconfig`)에서 확인한다.

- [ ] **Step 3: Commit**

승인 후 Claude가 커밋한다.

```bash
git add kernel/.config
git commit -m "Enable evdev and i8042 PS/2 keyboard in kernel config"
```

---

## Task 2: `input.zig` — evdev 이벤트 파싱 + US QWERTY 키맵

**목적:** `/dev/input/event0`에서 `struct input_event`를 읽어 "PTY로 보낼
바이트"로 바꾸는 모듈. **변환 로직을 순수 함수로 분리**해서 QEMU도 커널도
없이 devcontainer 네이티브 테스트로 먼저 검증한다 — TF-M2에서 `vt_test`가
컴파일 에러 0회를 만들어준 것과 같은 전략이다.

**Files:**
- Create: `terminal/src/input.zig`
- Create: `terminal/src/input_test.zig`
- Modify: `terminal/build.zig`

- [ ] **Step 1: `terminal/src/input.zig` 작성**

```zig
const std = @import("std");

const c = @cImport({
    @cInclude("linux/input.h");
});

/// libc의 open을 직접 선언한다. glibc의 `open`은 가변 인자
/// (`int open(const char *, int, ...)`)라 translate-c가 만든 래퍼를 그대로
/// 쓰기 번거롭다 — `pty.zig`가 `execv`를 직접 선언한 것과 같은 이유다.
extern "c" fn open(path: [*:0]const u8, flags: c_int) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize;

const O_RDONLY: c_int = 0;

/// evdev keycode → (Shift 안 누름, Shift 누름) 문자.
/// 0은 "이 키는 문자를 만들지 않는다"는 뜻이다(modifier 키 등).
/// 값은 리눅스 `input-event-codes.h`의 KEY_* 상수 순서 그대로이며,
/// US QWERTY 레이아웃 하나만 하드코딩한다(design doc 6번 결정).
const keymap = [_][2]u8{
    .{ 0, 0 }, //  0: (없음)
    .{ 0x1b, 0x1b }, //  1: KEY_ESC
    .{ '1', '!' }, //  2
    .{ '2', '@' }, //  3
    .{ '3', '#' }, //  4
    .{ '4', '$' }, //  5
    .{ '5', '%' }, //  6
    .{ '6', '^' }, //  7
    .{ '7', '&' }, //  8
    .{ '8', '*' }, //  9
    .{ '9', '(' }, // 10
    .{ '0', ')' }, // 11
    .{ '-', '_' }, // 12
    .{ '=', '+' }, // 13
    .{ 0x7f, 0x7f }, // 14: KEY_BACKSPACE — 터미널 관례상 BS(0x08)가 아니라 DEL
    .{ '\t', '\t' }, // 15: KEY_TAB
    .{ 'q', 'Q' }, // 16
    .{ 'w', 'W' }, // 17
    .{ 'e', 'E' }, // 18
    .{ 'r', 'R' }, // 19
    .{ 't', 'T' }, // 20
    .{ 'y', 'Y' }, // 21
    .{ 'u', 'U' }, // 22
    .{ 'i', 'I' }, // 23
    .{ 'o', 'O' }, // 24
    .{ 'p', 'P' }, // 25
    .{ '[', '{' }, // 26
    .{ ']', '}' }, // 27
    .{ '\r', '\r' }, // 28: KEY_ENTER — 실제 터미널은 CR을 보낸다
    .{ 0, 0 }, // 29: KEY_LEFTCTRL (이번 범위 밖)
    .{ 'a', 'A' }, // 30
    .{ 's', 'S' }, // 31
    .{ 'd', 'D' }, // 32
    .{ 'f', 'F' }, // 33
    .{ 'g', 'G' }, // 34
    .{ 'h', 'H' }, // 35
    .{ 'j', 'J' }, // 36
    .{ 'k', 'K' }, // 37
    .{ 'l', 'L' }, // 38
    .{ ';', ':' }, // 39
    .{ '\'', '"' }, // 40
    .{ '`', '~' }, // 41
    .{ 0, 0 }, // 42: KEY_LEFTSHIFT
    .{ '\\', '|' }, // 43
    .{ 'z', 'Z' }, // 44
    .{ 'x', 'X' }, // 45
    .{ 'c', 'C' }, // 46
    .{ 'v', 'V' }, // 47
    .{ 'b', 'B' }, // 48
    .{ 'n', 'N' }, // 49
    .{ 'm', 'M' }, // 50
    .{ ',', '<' }, // 51
    .{ '.', '>' }, // 52
    .{ '/', '?' }, // 53
    .{ 0, 0 }, // 54: KEY_RIGHTSHIFT
    .{ '*', '*' }, // 55: KEY_KPASTERISK
    .{ 0, 0 }, // 56: KEY_LEFTALT
    .{ ' ', ' ' }, // 57: KEY_SPACE
};

/// modifier 상태를 들고 있는 작은 상태 머신.
/// design doc 6번의 세 조각 중 1번(modifier bitmask)에 해당한다.
pub const State = struct {
    shift_left: bool = false,
    shift_right: bool = false,

    fn shifted(self: State) bool {
        return self.shift_left or self.shift_right;
    }

    /// EV_KEY 이벤트 하나를 처리한다.
    /// value: 0=뗌, 1=누름, 2=자동 반복.
    /// 문자를 만들면 그 바이트를, 아니면 null을 반환한다.
    pub fn handleKey(self: *State, code: u16, value: i32) ?u8 {
        switch (code) {
            c.KEY_LEFTSHIFT => {
                self.shift_left = value != 0;
                return null;
            },
            c.KEY_RIGHTSHIFT => {
                self.shift_right = value != 0;
                return null;
            },
            else => {},
        }
        // 뗄 때는 아무것도 보내지 않는다. 누름(1)과 자동 반복(2)만 문자를 만든다.
        if (value == 0) return null;
        if (code >= keymap.len) return null;

        const ch = keymap[code][if (self.shifted()) 1 else 0];
        return if (ch == 0) null else ch;
    }
};

pub fn openDevice(path: [*:0]const u8) !c_int {
    const fd = open(path, O_RDONLY);
    if (fd < 0) return error.OpenInputDeviceFailed;
    return fd;
}

/// fd에서 한 번 read하고(poll이 읽을 게 있다고 알려준 뒤에만 호출한다),
/// 그 안의 EV_KEY 이벤트들을 문자 바이트로 바꿔 out에 채운다.
pub fn readKeys(self: *State, fd: c_int, out: []u8) []const u8 {
    const ev_size = @sizeOf(c.struct_input_event);
    var raw: [ev_size * 64]u8 = undefined;

    const n = read(fd, &raw, raw.len);
    if (n <= 0) return out[0..0];

    const count = @as(usize, @intCast(n)) / ev_size;
    var written: usize = 0;
    var i: usize = 0;
    while (i < count and written < out.len) : (i += 1) {
        const ev: *align(1) const c.struct_input_event =
            @ptrCast(&raw[i * ev_size]);
        if (ev.@"type" != c.EV_KEY) continue;
        if (self.handleKey(ev.code, ev.value)) |ch| {
            out[written] = ch;
            written += 1;
        }
    }
    return out[0..written];
}
```

`ev.@"type"`으로 쓴 이유: `type`은 Zig에서 기본 타입 이름이라 그냥
`ev.type`으로 쓰면 파서가 헷갈릴 수 있다. `@"..."` 문법은 어떤 이름이든
식별자로 강제하므로 **항상 안전하다**(`ev.type`이 컴파일된다면 둘은 완전히
같은 식별자다).

`*align(1)`을 붙인 이유: `raw`는 그냥 `u8` 배열이라 정렬 보장이 없는데,
`struct_input_event`는 8바이트 정렬을 요구한다. 실제로는 24바이트 배수라
항상 정렬이 맞지만, 컴파일러에게 "정렬을 가정하지 말라"고 알려주는 쪽이
안전하다.

- [ ] **Step 2: `terminal/src/input_test.zig` 작성 (네이티브 테스트)**

fd도 커널도 필요 없다 — 상태 머신만 검증한다.

```zig
const std = @import("std");
const input = @import("input.zig");

fn expectByte(state: *input.State, code: u16, value: i32, want: ?u8) !void {
    const got = state.handleKey(code, value);
    if (got == null and want == null) return;
    if (got != null and want != null and got.? == want.?) return;
    std.debug.print(
        "FAIL: code={d} value={d} -> got={?d}, want={?d}\n",
        .{ code, value, got, want },
    );
    return error.UnexpectedByte;
}

pub fn main() !void {
    // struct input_event가 translate-c로 제대로 넘어왔는지부터 확인한다
    // (이 plan의 "가설 1").
    std.debug.print("input_event size = {d} (expected 24)\n", .{input.eventSize()});
    if (input.eventSize() != 24) {
        std.debug.print("FAIL: unexpected struct input_event size\n", .{});
        return error.UnexpectedEventSize;
    }

    var state: input.State = .{};

    // "hi" 타이핑: 누를 때만 문자가 나오고, 뗄 때는 안 나온다.
    try expectByte(&state, 35, 1, 'h'); // KEY_H press
    try expectByte(&state, 35, 0, null); // KEY_H release
    try expectByte(&state, 23, 1, 'i'); // KEY_I press
    try expectByte(&state, 23, 0, null); // KEY_I release

    // Enter는 CR을 보낸다.
    try expectByte(&state, 28, 1, '\r'); // KEY_ENTER press

    // Shift를 누르면 그 자체는 문자가 없고, 이어지는 키가 대문자가 된다.
    try expectByte(&state, 42, 1, null); // KEY_LEFTSHIFT press
    try expectByte(&state, 35, 1, 'H'); // KEY_H press (shifted)
    try expectByte(&state, 42, 0, null); // KEY_LEFTSHIFT release
    try expectByte(&state, 35, 1, 'h'); // KEY_H press (unshifted 복귀)

    // Shift + 숫자 = 기호.
    try expectByte(&state, 54, 1, null); // KEY_RIGHTSHIFT press
    try expectByte(&state, 2, 1, '!'); // KEY_1 press (shifted)
    try expectByte(&state, 54, 0, null); // KEY_RIGHTSHIFT release

    // 자동 반복(value=2)도 문자를 만든다.
    try expectByte(&state, 30, 2, 'a'); // KEY_A autorepeat

    // 표에 없는 키코드는 조용히 무시한다.
    try expectByte(&state, 200, 1, null);

    std.debug.print("PASS\n", .{});
}
```

이 테스트가 참조하는 `input.eventSize()`를 `input.zig` 끝에 추가한다:

```zig
/// translate-c가 struct input_event를 제대로 가져왔는지 확인하기 위한 헬퍼.
/// x86_64에서 24바이트(timeval 16 + type 2 + code 2 + value 4)여야 한다.
pub fn eventSize() usize {
    return @sizeOf(c.struct_input_event);
}
```

- [ ] **Step 3: `terminal/build.zig`에 `input_test` 실행 파일 추가**

`vt_test` 블록 다음에 추가한다.

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

- [ ] **Step 4: 네이티브 실행으로 검증 (QEMU 불필요)**

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build && ./zig-out/bin/input_test"
```

Expected:

```
input_event size = 24 (expected 24)
PASS
```

**만약 `error: 'struct_input_event' is opaque` 또는 비슷한 에러가 나면
(= 가설 1이 틀림):** `@cImport` 대신 손으로 정의한다. `input.zig`의
`const c = @cImport(...)` 블록을 아래로 교체하고, `c.struct_input_event` →
`InputEvent`, `c.EV_KEY` → `EV_KEY`, `c.KEY_LEFTSHIFT` → `KEY_LEFTSHIFT`,
`c.KEY_RIGHTSHIFT` → `KEY_RIGHTSHIFT`로 바꾼다. `drm.zig`가 DRM UAPI에 대해
이미 하고 있는 것과 똑같은 처리다.

```zig
/// linux/input.h의 struct input_event를 손으로 옮긴 것.
/// x86_64에서 struct timeval은 { long tv_sec; long tv_usec; } = 16바이트다.
const InputEvent = extern struct {
    tv_sec: c_long,
    tv_usec: c_long,
    ev_type: u16,
    code: u16,
    value: i32,
};

const EV_KEY: u16 = 0x01;
const KEY_LEFTSHIFT: u16 = 42;
const KEY_RIGHTSHIFT: u16 = 54;
```

(이 경우 `ev.@"type"`은 `ev.ev_type`이 된다.)

- [ ] **Step 5: Commit**

```bash
git add terminal/src/input.zig terminal/src/input_test.zig terminal/build.zig
git commit -m "Add evdev input module with US QWERTY keymap and shift state"
```

---

## Task 3: `pty.zig` 일반화 + `vt.zig`를 상태 유지형으로 승격

**목적:** 두 가지 구조적 제약을 푼다.

1. `pty.zig`는 `fish -c`만 실행할 수 있고 winsize를 `null`로 넘긴다 —
   PTY가 **0열 × 0행**이라 대화형 셸이 화면 폭을 알 수 없다.
2. `vt.parseToCells()`는 호출할 때마다 `Terminal`을 새로 만들고 버린다 —
   출력이 조각조각 도착하는 이벤트 루프에서는 앞 내용이 매번 사라진다.

**Files:**
- Modify: `terminal/src/pty.zig`
- Modify: `terminal/src/vt.zig`
- Modify: `terminal/src/vt_test.zig`

- [ ] **Step 1: `terminal/src/pty.zig` 교체**

```zig
const std = @import("std");

const c = @cImport({
    @cInclude("pty.h");
    @cInclude("sys/ioctl.h");
    @cInclude("unistd.h");
});

/// libc의 execv를 직접 선언한다. @cImport가 만들어주는 `c.execv`는
/// `char *const argv[]`를 `[*c]const [*c]u8`(비-const u8 포인터의 배열)로
/// 옮기기 때문에 Zig의 `?[*:0]const u8` 배열을 그대로 넘길 수 없다.
/// const를 벗기는 캐스팅을 하느니 처음부터 맞는 시그니처로 선언한다.
extern "c" fn execv(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) c_int;

pub const Session = struct {
    master_fd: c_int,
    child_pid: c.pid_t,
};

/// PTY를 만들고 그 안에서 임의의 프로그램을 실행한다.
/// cols/rows를 winsize로 넘기는 것이 핵심이다 — 이 값이 0이면 대화형 셸이
/// 화면 폭을 모르는 상태로 프롬프트를 그려서 줄바꿈이 엉킨다.
pub fn spawn(
    path: [*:0]const u8,
    argv: [*:null]const ?[*:0]const u8,
    cols: u16,
    rows: u16,
) !Session {
    var ws: c.struct_winsize = .{
        .ws_row = rows,
        .ws_col = cols,
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };

    var master_fd: c_int = undefined;
    const pid = c.forkpty(&master_fd, null, null, &ws);
    if (pid < 0) return error.ForkptyFailed;

    if (pid == 0) {
        _ = execv(path, argv);
        // execv가 돌아왔다는 건 실패했다는 뜻이다.
        c._exit(127);
    }

    return Session{ .master_fd = master_fd, .child_pid = pid };
}

/// fish를 `-c <command>`로 비대화형 실행한다(프롬프트/설정 파일 없음).
/// TF-M2부터 있던 함수를 `spawn` 위에 다시 얹은 것 — `pty_test`가 그대로
/// 동작하도록 시그니처를 유지한다.
pub fn spawnFish(command: [:0]const u8) !Session {
    const argv = [_:null]?[*:0]const u8{
        "fish",
        "--no-config",
        "-c",
        command.ptr,
    };
    return spawn("/usr/bin/fish", &argv, 80, 25);
}

/// master fd에서 자식이 끝날 때까지(EOF) 나오는 모든 바이트를 읽는다.
/// 호출자가 미리 충분히 큰 buf를 넘긴다(fixed buffer, 동적 할당 없음).
pub fn readAll(fd: c_int, buf: []u8) []const u8 {
    var total: usize = 0;
    while (total < buf.len) {
        const n = c.read(fd, buf.ptr + total, buf.len - total);
        if (n <= 0) break;
        total += @intCast(n);
    }
    return buf[0..total];
}

/// master fd에서 딱 한 번 read한다. poll이 "읽을 게 있다"고 알려준 뒤에만
/// 호출하므로 여기서 멈추지 않는다. 0 이하(EOF 또는 에러)면 빈 슬라이스.
pub fn readSome(fd: c_int, buf: []u8) []const u8 {
    const n = c.read(fd, buf.ptr, buf.len);
    if (n <= 0) return buf[0..0];
    return buf[0..@intCast(n)];
}

/// master fd에 바이트를 써 넣는다. 자식 프로세스 입장에서는 사용자가
/// 키보드로 친 것과 구분되지 않는다.
pub fn write(fd: c_int, bytes: []const u8) void {
    var sent: usize = 0;
    while (sent < bytes.len) {
        const n = c.write(fd, bytes.ptr + sent, bytes.len - sent);
        if (n <= 0) return;
        sent += @intCast(n);
    }
}
```

**만약 `struct_winsize` 필드 이름 관련 에러가 나면:** glibc의
`struct winsize`는 `ws_row`/`ws_col`/`ws_xpixel`/`ws_ypixel` 네 필드이며
`<termios.h>`나 `<sys/ioctl.h>`에 있다. 에러가 "unknown field"라면
`@cInclude("termios.h")`를 추가한다.

- [ ] **Step 2: `terminal/src/vt.zig` 교체**

```zig
const std = @import("std");
const ghostty_vt = @import("ghostty-vt");

pub const CellGlyph = struct {
    codepoint: u32,
    col: u16,
    row: u16,
};

/// 터미널 상태를 **계속 들고 있는** 화면.
///
/// TF-M2의 `parseToCells`는 호출할 때마다 Terminal을 새로 만들고 버렸다.
/// 입력이 생기면 PTY 출력이 여러 조각으로 나눠 도착하므로, 조각마다 새
/// Terminal을 만들면 앞 내용이 사라질 뿐 아니라 이스케이프 시퀀스가 조각
/// 경계에서 잘렸을 때 파서 상태도 잃는다. 그래서 Terminal과 Stream을
/// 프로그램 수명 내내 유지한다.
///
/// **반드시 힙에 두고 포인터로 다뤄야 한다.** `Terminal.vtStream()`이
/// 돌려주는 Stream은 내부에 `&terminal` 포인터를 담고 있어서
/// (`Terminal.zig:374-377`), Screen 값이 복사·이동되면 그 포인터가 옛 주소를
/// 가리키게 된다. `init`이 `*Screen`을 돌려주는 이유가 이것이다.
pub const Screen = struct {
    alloc: std.mem.Allocator,
    term: ghostty_vt.Terminal,
    stream: ghostty_vt.Stream,
    state: ghostty_vt.RenderState,

    pub fn init(
        io: std.Io,
        alloc: std.mem.Allocator,
        cols: u16,
        rows: u16,
    ) !*Screen {
        const self = try alloc.create(Screen);
        self.* = .{
            .alloc = alloc,
            .term = try .init(io, alloc, .{ .cols = cols, .rows = rows }),
            .stream = undefined,
            .state = .empty,
        };
        // term이 최종 주소에 자리잡은 **뒤에** stream을 만든다.
        self.stream = self.term.vtStream();
        return self;
    }

    pub fn deinit(self: *Screen) void {
        const alloc = self.alloc;
        self.state.deinit(alloc);
        self.stream.deinit();
        self.term.deinit(alloc);
        alloc.destroy(self);
    }

    /// PTY에서 읽은 바이트를 ANSI 파서에 먹인다. 화면 상태가 갱신된다.
    pub fn feed(self: *Screen, bytes: []const u8) void {
        self.stream.nextSlice(bytes);
    }

    /// 현재 화면에서 빈 칸이 아닌 셀만 out에 채워 반환한다.
    /// out은 최소 cols*rows 크기여야 안전하다.
    pub fn cells(self: *Screen, out: []CellGlyph) ![]CellGlyph {
        try self.state.update(self.alloc, &self.term);

        var n: usize = 0;
        const row_data = self.state.row_data.slice();
        const row_cells = row_data.items(.cells);
        for (0..self.state.rows) |y| {
            const cells_slice = row_cells[y].slice();
            const raws = cells_slice.items(.raw);
            for (0..self.state.cols) |x| {
                if (n >= out.len) return out[0..n];
                const cp = raws[x].codepoint();
                if (cp == 0) continue;
                out[n] = .{
                    .codepoint = @intCast(cp),
                    .col = @intCast(x),
                    .row = @intCast(y),
                };
                n += 1;
            }
        }
        return out[0..n];
    }
};
```

`RenderState.update`는 반복 호출을 전제로 만들어진 API다 —
`render.zig:354-355`에 "This will reset the terminal dirty state since it is
consumed by this render state update"라고 적혀 있다. 즉 매번 전체를 다시
만드는 게 아니라 **변경된 행만 갱신**하고 나머지는 이전 내용을 유지한다.

- [ ] **Step 3: `terminal/src/vt_test.zig`를 새 API + 상태 유지 검증으로 교체**

```zig
const std = @import("std");
const vt = @import("vt.zig");

pub fn main(init: std.process.Init) !void {
    const screen = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer screen.deinit();

    var buf: [100]vt.CellGlyph = undefined;

    // 1차: "TARS 하이" — TF-M2와 동일한 검증.
    screen.feed("TARS \xed\x95\x98\xec\x9d\xb4\r\n");
    const first = try screen.cells(&buf);
    std.debug.print("after 1st feed: {d} cells\n", .{first.len});
    if (first.len == 0) return error.NoCells;
    if (first[0].codepoint != 'T' or first[0].row != 0 or first[0].col != 0) {
        std.debug.print("FAIL: expected first cell 'T' at (0,0)\n", .{});
        return error.UnexpectedFirstCell;
    }

    // 2차: 두 번째 조각을 먹인다. **1차 내용이 살아 있어야 한다** —
    // 이게 TF-M3에서 새로 필요해진 성질이다.
    screen.feed("OK\r\n");
    const second = try screen.cells(&buf);
    std.debug.print("after 2nd feed: {d} cells\n", .{second.len});
    for (second) |cell| {
        std.debug.print("  row={d} col={d} codepoint=U+{X}\n", .{ cell.row, cell.col, cell.codepoint });
    }
    if (second.len <= first.len) {
        std.debug.print("FAIL: 2nd feed should ADD cells, not replace them\n", .{});
        return error.StateNotRetained;
    }
    if (second[0].codepoint != 'T') {
        std.debug.print("FAIL: 1st feed content was lost\n", .{});
        return error.StateNotRetained;
    }

    // 이스케이프 시퀀스가 조각 경계에서 잘려도 파서 상태가 이어지는지 확인.
    // "\x1b[" + "2J"는 합쳐야 화면 지우기(ED)가 된다.
    screen.feed("\x1b[");
    screen.feed("2J");
    const third = try screen.cells(&buf);
    std.debug.print("after split escape (clear): {d} cells\n", .{third.len});
    if (third.len != 0) {
        std.debug.print("FAIL: expected screen to be cleared\n", .{});
        return error.SplitEscapeNotHandled;
    }

    std.debug.print("PASS\n", .{});
}
```

- [ ] **Step 4: 네이티브 테스트 두 개 모두 통과 확인**

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build && ./zig-out/bin/pty_test && ./zig-out/bin/vt_test && ./zig-out/bin/input_test"
```

Expected: 세 번 모두 `PASS`. `vt_test`의 `after 2nd feed`가 `after 1st feed`
보다 셀 수가 많아야 하고, `after split escape (clear): 0 cells`가 나와야 한다.

**주의:** 이 Step에서 `zig build`가 `main.zig` 컴파일 에러로 실패한다.
`main.zig`가 아직 `vt.parseToCells`(방금 없앤 함수)를 부르고 있기 때문이다.
Task 4에서 `main.zig`를 고칠 때까지는 정상이다 — 임시로 넘어가려면
`main.zig:57`의 `vt.parseToCells(...)` 줄을 Task 4의 코드로 먼저 바꿔도 되고,
아니면 Task 4까지 한 번에 진행해도 된다. **Task 3과 Task 4를 연달아
진행하는 것을 권장한다.**

- [ ] **Step 5: Commit** (Task 4의 `main.zig` 수정까지 끝난 뒤)

```bash
git add terminal/src/pty.zig terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Make PTY spawn generic with winsize and keep VT state across feeds"
```

---

## Task 4: `main.zig` 이벤트 루프 + `cat` 자식으로 왕복 확인

**목적:** 드디어 입력이 화면까지 도달하는 경로를 만든다. 자식은 **`cat`**으로
둔다 — PTY 회선 규율(line discipline)이 입력한 문자를 그대로 master로
에코해주므로, 화면에 나타날 내용이 100% 예측 가능하다. 여기서 통과하면
"evdev 읽기 → PTY write → 에코 → vt 파싱 → 재렌더" 루프 자체는 검증된
것이고, 남은 변수는 fish 하나뿐이 된다.

**Files:**
- Modify: `kernel/make_initrd.sh`
- Modify: `terminal/src/main.zig`

- [ ] **Step 1: `kernel/make_initrd.sh`에 `cat` 추가**

`cp /usr/bin/fish "$WORKDIR/usr/bin/fish"` 줄 다음에 추가한다.

```bash
cp /usr/bin/cat "$WORKDIR/usr/bin/cat"
chmod 0755 "$WORKDIR/usr/bin/cat"
```

그리고 `copy_lib_deps "$WORKDIR/usr/bin/fish"` 줄 다음에 추가한다.

```bash
copy_lib_deps "$WORKDIR/usr/bin/cat"
```

- [ ] **Step 2: `terminal/src/main.zig` 전면 교체**

```zig
const std = @import("std");
const drm = @import("drm.zig");
const font = @import("font.zig");
const input = @import("input.zig");
const pty = @import("pty.zig");
const vt = @import("vt.zig");

const c = @cImport({
    @cInclude("poll.h");
});

const BACKGROUND: u32 = 0x00102030;
const TEXT_COLOR: u32 = 0x00FFFFFF;
const GRID_X: u32 = 20;
const GRID_Y: u32 = 20;
const CELL_W: u32 = 8; // 8x4x4-fonts의 라틴 글리프 폭(font.zig:19-22 참고)
const ROW_HEIGHT: u32 = 16;

const INPUT_DEVICE = "/dev/input/event0";

fn drawGlyph(fb: drm.Framebuffer, glyph: font.Glyph, x: u32, y: u32) void {
    const bitmap = glyph.bitmap orelse return;
    var row: u32 = 0;
    while (row < glyph.height) : (row += 1) {
        var col: u32 = 0;
        while (col < glyph.width) : (col += 1) {
            const coverage = bitmap[row * glyph.width + col];
            if (coverage > 127) {
                fb.setPixel(x + col, y + row, TEXT_COLOR);
            }
        }
    }
}

/// 화면 전체를 지우고 셀 목록을 다시 그린다. 키 입력 빈도에서 부분 갱신은
/// 불필요한 복잡도다(YAGNI).
fn render(fb: drm.Framebuffer, cache: font.GlyphCache, cells: []const vt.CellGlyph) !void {
    fb.fill(BACKGROUND);
    for (cells) |cell| {
        // x를 글리프 폭으로 누적하지 않고 col로 계산하는 것이 중요하다.
        // libghostty-vt는 한글 같은 폭 2칸 문자 뒤에 spacer 셀을 넣어 col을
        // 이미 맞춰두기 때문에(TF-M2에서 '이'의 col이 6이 아니라 7이었던
        // 그 성질), col*CELL_W가 곧 정확한 픽셀 위치다.
        const x = GRID_X + @as(u32, cell.col) * CELL_W;
        const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
        if (font.find(cache, cell.codepoint)) |glyph| {
            drawGlyph(fb, glyph, x, y);
        }
    }
    try fb.present();
}

/// 검증용으로 화면 내용을 serial 콘솔에 한 줄로 덤프한다.
/// check.sh가 이 줄을 grep해서 "입력이 실제로 셸을 움직였는가"를 판단한다.
fn dumpScreen(cells: []const vt.CellGlyph) void {
    std.debug.print("terminal: screen> ", .{});
    var last_row: u16 = 0;
    for (cells) |cell| {
        if (cell.row != last_row) {
            std.debug.print(" | ", .{});
            last_row = cell.row;
        }
        var utf8: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(cell.codepoint), &utf8) catch continue;
        std.debug.print("{s}", .{utf8[0..len]});
    }
    std.debug.print("\n", .{});
}

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    const fb = try drm.open(allocator, "/dev/dri/card0");
    fb.fill(BACKGROUND);
    try fb.present();

    // 화면 크기를 여기서 **한 번만** 계산해 렌더러·Terminal·PTY winsize
    // 세 곳에 같은 값을 넘긴다. 이 셋이 어긋나면 셸이 생각하는 폭과 우리가
    // 그리는 폭이 달라져 줄바꿈이 엉킨다.
    const cols: u16 = @intCast((fb.width - 2 * GRID_X) / CELL_W);
    const rows: u16 = @intCast((fb.height - 2 * GRID_Y) / ROW_HEIGHT);
    std.debug.print("terminal: grid {d}x{d} (fb {d}x{d})\n", .{ cols, rows, fb.width, fb.height });

    const font_data = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "vendor/fonts/Hanme_8x4x4.ttf",
        allocator,
        .unlimited,
    );

    // 사용자가 아무 키나 칠 수 있으므로 출력 가능한 ASCII 전체를 미리
    // 래스터라이징한다(0x20 ' ' ~ 0x7E '~', 95자).
    var codepoints: [95]u32 = undefined;
    for (&codepoints, 0..) |*cp, i| cp.* = @intCast(0x20 + i);
    const cache = try font.build(allocator, font_data, &codepoints);
    std.debug.print("terminal: rasterized {d} glyphs\n", .{codepoints.len});

    const keyboard_fd = input.openDevice(INPUT_DEVICE) catch |err| {
        std.debug.print("terminal: FATAL cannot open {s}: {any}\n", .{ INPUT_DEVICE, err });
        return err;
    };
    std.debug.print("terminal: opened {s}\n", .{INPUT_DEVICE});

    const argv = [_:null]?[*:0]const u8{"cat"};
    const session = try pty.spawn("/usr/bin/cat", &argv, cols, rows);
    std.debug.print("terminal: spawned child pid {d}\n", .{session.child_pid});

    const screen = try vt.Screen.init(init.io, allocator, cols, rows);
    defer screen.deinit();

    const cell_buf = try allocator.alloc(vt.CellGlyph, @as(usize, cols) * rows);
    defer allocator.free(cell_buf);

    var key_state: input.State = .{};
    var key_buf: [64]u8 = undefined;
    var pty_buf: [4096]u8 = undefined;

    var fds = [_]c.struct_pollfd{
        .{ .fd = keyboard_fd, .events = c.POLLIN, .revents = 0 },
        .{ .fd = session.master_fd, .events = c.POLLIN, .revents = 0 },
    };

    while (true) {
        // -1 = 무한 대기. 이벤트가 없으면 CPU를 전혀 쓰지 않는다.
        const ready = c.poll(&fds, fds.len, -1);
        if (ready < 0) continue; // EINTR 등은 그냥 다시 기다린다

        if (fds[0].revents & c.POLLIN != 0) {
            const bytes = input.readKeys(&key_state, keyboard_fd, &key_buf);
            if (bytes.len > 0) {
                std.debug.print("terminal: key> {d} byte(s)\n", .{bytes.len});
                pty.write(session.master_fd, bytes);
            }
        }

        if (fds[1].revents & c.POLLIN != 0) {
            const out = pty.readSome(session.master_fd, &pty_buf);
            if (out.len == 0) {
                std.debug.print("terminal: child exited (pty EOF)\n", .{});
                break;
            }
            screen.feed(out);
            const cells = try screen.cells(cell_buf);
            try render(fb, cache, cells);
            dumpScreen(cells);
        }
    }

    // 자식이 죽어도 패닉하지 않고 화면을 유지한 채 남는다.
    // nfds=0인 poll은 "아무 fd도 안 보고 timeout만 기다린다" = sleep이다.
    while (true) {
        _ = c.poll(&fds, 0, 1000);
    }
}
```

**만약 `c.poll`/`c.struct_pollfd` 관련 에러가 나면:** `poll.h`의
`struct pollfd`는 `{ int fd; short events; short revents; }`다. translate-c가
못 가져오면 `input.zig`가 `open`을 직접 선언한 것과 같은 방식으로 쓴다.

```zig
const PollFd = extern struct { fd: c_int, events: i16, revents: i16 };
const POLLIN: i16 = 0x001;
extern "c" fn poll(fds: [*]PollFd, nfds: c_ulong, timeout: c_int) c_int;
```

**만약 `fds.len`을 `poll`의 두 번째 인자로 못 넘긴다는 타입 에러가 나면:**
`nfds_t`는 `c_ulong`이므로 `@as(c.nfds_t, fds.len)`로 감싼다.

- [ ] **Step 3: 컴파일 확인**

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer zig build
```

Expected: 에러 없이 `zig-out/bin/terminal` 생성.

- [ ] **Step 4: QEMU에서 `cat` 왕복 수동 확인**

`check.sh`를 아직 고치지 않았으므로 이번엔 monitor에 직접 명령을 보낸다.

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c '
set -e
(cd kernel && ./build.sh)
(cd init && cargo build --release)
(cd terminal && zig build)
(cd kernel && ./make_initrd.sh)
qemu-system-x86_64 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none -device virtio-gpu-pci -display none \
  -serial file:/tmp/boot.log \
  -monitor tcp:127.0.0.1:45455,server,nowait \
  -no-reboot &
QPID=$!
sleep 30
exec 3<>/dev/tcp/127.0.0.1/45455
for k in t a r s ret; do echo "sendkey $k" >&3; sleep 0.3; done
sleep 2
echo "screendump /workspace/tf-m3-cat.ppm" >&3
sleep 1
exec 3<&-; exec 3>&-
kill $QPID 2>/dev/null || true
echo "===== serial log ====="
tail -n 40 /tmp/boot.log
'
```

Expected: serial 로그에 아래 흐름이 보인다.

```
terminal: grid NNNxNN (fb WWWWxHHH)
terminal: rasterized 95 glyphs
terminal: opened /dev/input/event0
terminal: spawned child pid N
terminal: key> 1 byte(s)          ← 't' 누름
terminal: screen> t               ← 회선 규율이 에코한 't'가 파싱됨
terminal: key> 1 byte(s)
terminal: screen> ta
...
terminal: screen> tars | tars     ← Enter 후 cat이 한 줄을 다시 출력
```

키를 누를 때마다 `key>`와 `screen>`이 **번갈아** 나오는 것이 핵심이다 —
입력이 PTY를 한 바퀴 돌아 화면 상태까지 도달했다는 뜻이다. 마지막에
`tars`가 두 번 보이는 이유는 한 번은 회선 규율의 에코, 한 번은 `cat`이
개행을 받고 내보낸 출력이기 때문이다.

- [ ] **Step 5: screendump 육안 확인**

```bash
sips -s format png tf-m3-cat.ppm --out tf-m3-cat.png
open tf-m3-cat.png
```

화면 (20,20) 근처에 `tars`가 두 줄로 보이면 성공이다.

**만약 `terminal: key>`가 한 번도 안 나오면:** 세 가지를 순서대로 확인한다.
1. `terminal: opened /dev/input/event0`이 나왔는가 → 안 나오면 Task 1의
   커널 config가 실제로 적용되지 않은 것이다.
2. `sendkey`가 QEMU monitor에 도달했는가 → monitor 포트 연결 실패면
   `sleep 30`을 늘린다.
3. 커널이 키를 다른 곳으로 보냈는가 → `/tmp/boot.log`에 커널 VT 관련
   메시지가 있는지 본다.

- [ ] **Step 6: Commit** (Task 3 Step 5와 함께)

```bash
git add terminal/src/main.zig kernel/make_initrd.sh
git commit -m "Add poll event loop feeding evdev keystrokes into PTY"
```

---

## Task 5: 대화형 `fish`로 교체 + `check.sh` 자동 검증 게이트

**목적:** MVP 종료점. 자식을 대화형 `fish`로 바꾸고, `check.sh`가
"입력 전/후 화면이 달라졌는가"(렌더링 경로)와 "셸이 실제로 명령을
실행했는가"(파싱 경로)를 각각 확인하도록 만든다.

**Files:**
- Modify: `terminal/src/main.zig`
- Modify: `terminal/check.sh`

- [ ] **Step 1: `main.zig`의 자식을 대화형 fish로 교체**

`main.zig`의 아래 두 줄을:

```zig
    const argv = [_:null]?[*:0]const u8{"cat"};
    const session = try pty.spawn("/usr/bin/cat", &argv, cols, rows);
```

이렇게 바꾼다.

```zig
    // `-c` 없이 실행하면 대화형 모드다 — 프롬프트를 그리고 입력을 기다린다.
    // `--no-config`는 유지한다(사용자 설정 파일이 initrd에 없기도 하고,
    // 프롬프트가 예측 가능해야 검증이 쉽다).
    const argv = [_:null]?[*:0]const u8{ "fish", "--no-config" };
    const session = try pty.spawn("/usr/bin/fish", &argv, cols, rows);
```

- [ ] **Step 2: `terminal/check.sh`의 검증 블록 교체**

먼저 스크립트 위쪽의 아래 줄을 지운다(더 이상 안 쓴다 — 아래에서 `BEFORE`/
`AFTER` 두 장을 따로 만든다).

```bash
SCREENSHOT="$(mktemp /workspace/tf-m1-XXXXXX.ppm)"
```

그리고 `sleep 30` 이후 부분(`echo "screendump ${SCREENSHOT}" >&3`부터 파일
끝까지)을 아래로 교체한다.

```bash
BEFORE="$(mktemp /workspace/tf-m3-before-XXXXXX.ppm)"
AFTER="$(mktemp /workspace/tf-m3-after-XXXXXX.ppm)"

# 1) 키를 넣기 전 화면
echo "screendump ${BEFORE}" >&3
sleep 1

# 2) "math 6 x 7" + Enter 를 한 글자씩 주입.
#    fish 내장 math가 42를 출력하므로, 화면에 42가 나타나면 셸이 실제로
#    명령을 "실행"한 것이다 — 단순 에코와 구분된다.
for k in m a t h spc 6 spc x spc 7 ret; do
  echo "sendkey $k" >&3
  sleep 0.3
done
sleep 3

# 3) 키를 넣은 뒤 화면
echo "screendump ${AFTER}" >&3
sleep 1

exec 3<&-
exec 3>&-

kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

if [ ! -s "$BEFORE" ] || [ ! -s "$AFTER" ]; then
  echo "FAIL: screendump did not produce both files"
  tail -n 60 "$LOG"
  exit 1
fi

if command -v magick >/dev/null 2>&1; then
  IDENTIFY=(magick identify)
  COMPARE=(magick compare)
else
  IDENTIFY=(identify)
  COMPARE=(compare)
fi

DIMENSIONS=$("${IDENTIFY[@]}" -format "%wx%h" "$AFTER" 2>&1) || {
  echo "FAIL: ImageMagick could not read ${AFTER}: ${DIMENSIONS}"
  exit 1
}
echo "Captured screendumps: ${BEFORE} / ${AFTER} (${DIMENSIONS})"

# 렌더링 경로 검증: 키 주입 전후로 화면이 실제로 달라졌는가.
DIFF_PIXELS=$("${COMPARE[@]}" -metric AE "$BEFORE" "$AFTER" null: 2>&1) || true
DIFF_PIXELS="${DIFF_PIXELS%%[!0-9]*}"
echo "Pixels changed after typing: ${DIFF_PIXELS:-0}"

if [ -z "$DIFF_PIXELS" ] || [ "$DIFF_PIXELS" -lt 100 ]; then
  echo "FAIL: screen did not change after key injection (${DIFF_PIXELS:-0} pixels)"
  tail -n 60 "$LOG"
  exit 1
fi

# 파싱 경로 검증: 셸이 명령을 실행해 42를 내놓았는가.
if ! grep -q "terminal: screen>.*42" "$LOG"; then
  echo "FAIL: expected '42' in the parsed screen dump (shell did not run the command)"
  tail -n 60 "$LOG"
  exit 1
fi
echo "Found '42' in parsed screen dump"

echo "PASS"
exit 0
```

기존 픽셀 검사(배경색 `#102030` 확인, glyph 영역 unique color 개수)를 없앤
이유: **전후 비교가 그보다 강한 검사**이기 때문이다. 배경색 확인은 "DRM
프레임버퍼가 우리 것"임을, unique color 검사는 "뭔가 그려졌음"을 보였는데,
전후 비교는 "**입력 때문에** 화면이 바뀌었음"을 보인다.

- [ ] **Step 3: 전체 파이프라인 검증**

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/check.sh
```

Expected: `PASS`. 중간에 `Pixels changed after typing: N`(N ≥ 100)과
`Found '42' in parsed screen dump`가 보여야 한다.

**만약 화면이 안 바뀌면(`DIFF_PIXELS` 0):** 로그의 `terminal: screen>` 줄을
본다. 파싱은 되는데 화면이 그대로면 `render()`의 `fb.present()` 문제이고,
`screen>` 줄 자체가 없으면 fish가 아직 안 떴거나 입력을 못 받은 것이다 —
`sleep 30`을 늘려본다.

**만약 `42`가 안 나오면:** `terminal: screen>` 줄에 무엇이 찍혔는지 본다.
- `math`가 fish 내장이 아닌 옛 버전이면 `Unknown command`가 보인다. 이때는
  검증 명령을 `echo tars`로 바꾸고 grep 대상도 `tars`로 바꾼다(단, 이 경우
  에코와 출력을 구분하지 못하므로 "화면이 바뀌었다"까지만 보증된다).
- 프롬프트가 화면을 가득 채우거나 줄바꿈이 엉키면 winsize(Task 3)가 제대로
  전달되지 않은 것이다 — 로그의 `terminal: grid NNNxNN`이 프레임버퍼 크기와
  맞는지 확인한다.
- fish가 터미널 능력 질의(`\x1b[6n` 커서 위치 보고 등)에 대한 응답을
  기다리며 멈춰 있을 수 있다. 이 경우 로그에 프롬프트가 아예 안 나온다.
  `libghostty-vt`가 이런 질의에 대한 응답 바이트를 만들어주는지
  (`terminal/ghostty-src/src/terminal/`의 `device_status` 관련 코드)를
  확인해서, 있으면 그 바이트를 PTY master에 써 보내는 처리를 `main.zig`에
  추가한다.

- [ ] **Step 4: screendump 육안 확인**

```bash
sips -s format png tf-m3-after-XXXXXX.ppm --out tf-m3-after.png
open tf-m3-after.png
```

fish 프롬프트, 타이핑한 `math 6 x 7`, 그리고 결과 `42`가 보이면 성공이다.

- [ ] **Step 5: Commit**

```bash
git add terminal/src/main.zig terminal/check.sh
git commit -m "Run interactive fish and verify typed input reaches the shell"
```

---

## TF-M3 완료 확인 체크리스트

- [ ] 커널 부팅 로그에 `input: AT Translated Set 2 keyboard as ...`가 보임
- [ ] `input_test`가 네이티브로 통과하고 `input_event size = 24`를 출력
      (= 가설 1 확인)
- [ ] `vt_test`가 두 번째 feed 후에도 첫 내용이 남아 있음을 확인
      (= 상태 유지 성공)
- [ ] `cat` 자식으로 `key>` ↔ `screen>` 왕복이 로그에 보임
- [ ] `terminal/check.sh`가 `PASS` — 전후 픽셀 차이 + 로그의 `42`
- [ ] screendump 육안 확인 완료
- [ ] `HANDOFF.md` 갱신 + TF-M4(종료 게이트: 3회 연속 검증)로 이어갈 준비

---

## 실제 실행에서 plan과 달라진 점

(완료 시점에 채운다 — TF-M2 plan 말미와 같은 형식으로, 다음 milestone이
같은 함정을 반복하지 않도록 이유까지 기록한다.)
