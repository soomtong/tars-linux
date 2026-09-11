# SC-M2 Implementation Plan — 탈출로 둘, 그리고 rc를 일부러 깨뜨려 본다

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 사용자가 쓴 rc가 셸을 죽여도 기계가 돌아오게 한다. 감독자가
포기하기 **직전에** rc 없이 한 번 더 띄우고(결정 8), 커널 cmdline의
`tars.noconfig`가 `tars.conf`를 이긴다(결정 9). `config/check.sh`의 부팅을
**다섯으로** 늘려 **일부러 죽는 rc를 깔고** 둘을 각각 증명한다.

**Architecture:** 새 파일이 하나도 없다. 결정 9는 `config.zig`에 순수 함수
하나(`cmdlineWantsNoConfig`)와 그것을 `/proc/cmdline`에 묻는 껍데기 하나를
더하고 `main.zig`가 `loadConfig` 뒤에서 그 답으로 `cfg.shell_config`를 덮는
일이다. 결정 8은 `Child`에 필드 하나(`rescue`)를 더하고 감독 루프의
`given_up` 갈래 **앞에** 분기 하나를 놓는 일이다 — `resolveShell()`이 없는
셸에 대해 하는 폴백과 같은 모양이다.

**Tech Stack:** Zig(init) · bash(게이트 체인) · QEMU monitor `sendkey`

**읽고 시작할 것:** `docs/superpowers/specs/2026-09-11-tars-shell-config-design.md`
— 특히 **결정 8·9 · 실측 11(감독자는 빨리 죽는 것이 3회면 포기한다) ·
실측 12(실기는 limine을 지나므로 cmdline을 고칠 수 있다) · 실측 13(`/proc`은
설정을 읽기 전에 이미 붙어 있다) · 위험 3(rc가 깨지면 고칠 셸이 없다)**.

---

## 이 milestone을 지배하는 사실 하나

> **감독자는 자식이 **왜** 죽었는지 모른다.**

`fast_restarts >= 3`이라는 사실만으로는 "사용자의 rc가 셸을 죽였다"와 "GPU가
없어서 terminal이 못 뜬다"를 가를 수 없다. 그런데 **둘째 경우에 탈출로가
발동하면 BF 체인이 깨진다** — `boot/check.sh:112`가 이렇게 세고 있다:

```bash
STARTS="$(grep -c "tars-init: started terminal" "$LOG" || true)"
if [ "$STARTS" != "3" ]; then
  echo "FAIL: init started the terminal ${STARTS} times, want exactly 3"
```

BF 체인은 `-vga none`이라 terminal이 매번 죽고, 그 셋이 곧 `MAX_FAST_RESTARTS`
**정책 그 자체**다(그 파일의 주석이 그렇게 적고 있다). 탈출로를 조건 없이
주면 이 수가 **여섯**이 된다.

**그래서 탈출로를 주는 조건에 `storage_mounted`를 함께 건다.** 설정 디스크가
안 붙은 부팅에는 rc **실체가 아예 없다** — 홈의 링크는 끊어져 있고 셸은
아무것도 안 읽는다(SC-M0이 여섯 체인에서 확인한 정상 경로다). 거기서 자식이
죽는 이유는 rc가 아니고, **고칠 수 있는 것이 없는데 다시 띄우는 것은 탈출이
아니라 소음이다.**

| 체인 | 디스크 | 탈출로 | BF의 수 |
|---|---|---|---|
| `boot`(BF) · `device` · `render` · `copy` · `terminal` · `tools` | 없음 | **없다** | 3 그대로 |
| `config` · `hangul` · `input` · `machine` · `power` | 있음 | 있다(기본값 `on`일 때) | — |

**Task 7의 음성 확인이 이 조건을 실제로 깨뜨려 본다** — 조건을 떼고
`boot/check.sh`를 돌려서 그 수가 정말 6이 되는지를 본다. SC-M0이 배운 것
(*"검사를 넣었으면 그것이 죽는 경우를 직접 만들어 봐야 한다"*)의 이번 판이고,
이번에는 **우리 코드가 깨뜨릴 남의 검사**를 미리 찾아 두었다는 점이 다르다.

---

## 게이트가 무엇을 어떻게 보는가 — 부팅 다섯

M1의 셋에 둘이 붙는다. **새 체인을 안 만든다**(design 결정 10 — 열두번째
체인은 +2분이다).

| 부팅 | cmdline | `tars.conf` | `/config/zshrc` | 치는 것 | 증명하는 것 |
|---|---|---|---|---|---|
| **1차** | 기본 | 없음 → 씨앗 | 없음 → 씨앗 | `tars-config` · `shell=zsh` · 마커 한 줄 | M1 그대로 |
| **2차** | 기본 | `shell=zsh` | 씨앗+마커 | `shell_config=off` | M1 그대로 |
| **3차** | 기본 | `+shell_config=off` | 씨앗+마커 | **`exit`를 rc에 심고** `shell_config=on`을 되돌린다 | M1의 부정 검사 그대로 **+ 4차가 쓸 함정을 판다** |
| **4차** | 기본 | `+shell_config=on` | 씨앗+마커+**`exit`** | 없음 | **결정 8** — 셋 죽고 나서 rc 없이 살아난다 |
| **5차** | **`tars.noconfig`** | 같음(`on`) | 같음(**`exit`**) | 없음 | **결정 9** — cmdline이 `on`을 이겨서 함정을 아예 안 밟는다 |

**4차와 5차가 같은 디스크를 보는 것이 이 설계의 핵심이다.** 4차는 그 디스크로
셸이 **죽는다**는 것을 보였고, 5차는 **같은 디스크에서 한 단어 때문에 안
죽는다**는 것을 본다 — 5차의 부정 검사(`tars-rc-alive`가 없다)가
tautology가 아니라는 증거를 4차가 만들어 준다. M1의 3차가 2차에 기대던 것과
같은 구조다.

**3차에서 타이핑을 하는 것이 M1과 달라지는 점이다.** M1은 *"이 부팅은
아무것도 안 친다 — 판정 글자가 우연히 화면에 생기는 길이 하나 늘어난다"*고
적었고 그 이유는 그대로 산다. 그래서 **3차가 치는 두 줄에 `tars-rc-alive`가
한 글자도 안 들어간다**: 되읽기를 `cat /config/zshrc`가 아니라
`grep exit /config/zshrc`로 하는 것이 그래서다(씨앗에도 그 줄에도 `exit`는
우리가 방금 심은 한 줄뿐이다).

---

## File Structure

| 파일 | 무엇을 맡나 | 이 milestone이 하는 일 |
|---|---|---|
| `init/src/config_test.zig` | 시스템 콜 없는 부분을 호스트에서 검증 | **cmdline 토큰 검사 아홉** |
| `init/src/config.zig` | 설정 파일의 문법·기본값·쓰기 | `NO_CONFIG_TOKEN` · `cmdlineWantsNoConfig()` · `cmdlineNoConfig()` · `CMDLINE_PATH` |
| `init/src/main.zig` | PID 1 | 결정 9의 덮어쓰기 한 갈래 · `Rescue` · `Child.rescue` · 감독 루프의 탈출 분기 |
| `config/check.sh` | CP 체인 | **부팅 다섯** · 3차의 타이핑 넷 · 검사 열둘 |

`kernel/make_initrd.sh`·`terminal/`은 **한 글자도 안 고친다.**

---

## Task 1: cmdline 토큰의 문법을 먼저 못 박는다 — **실패를 본다**

**Files:** Modify `init/src/config_test.zig`

**왜 이것이 먼저인가.** M1이 두 번 값을 낸 순서 그대로다(design 실측 17,
기억의 "3") — 호스트 검사가 먼저 서면 부팅 20초 대신 0.1초가 답을 준다.
그리고 이 토큰은 **부분 문자열로 찾으면 조용히 틀린다**: `indexOf`로 짜면
`tars.noconfigured` 같은 것에 걸리고 증상은 "부팅했더니 rc가 안 읽힌다"뿐이다.

- [ ] **Step 1: `config_test.zig`의 `for (std.enums.values(config.Shell))` 줄 앞에 넣는다**

```zig
    // ── SC-M2: cmdline 토큰 ─────────────────────────────────────────────
    //
    // **탈출로 2의 전부가 이 함수 하나다**(design 결정 9). rc가 셸을 죽이면
    // `tars.conf`를 고칠 자리가 사라지므로, 그때 사람이 쥘 수 있는 것은
    // 부팅 순간의 cmdline 한 단어뿐이다(실측 12 — 실기는 limine 메뉴를
    // 지난다).
    //
    // **토큰으로 본다.** 부분 문자열로 찾으면 아래 넷째·다섯째 줄이
    // 참이 되고, 그 실수는 "부팅했더니 rc가 안 읽힌다"로만 드러난다.
    try expectCmdline("console=ttyS0", false);
    try expectCmdline("console=ttyS0 tars.noconfig", true);
    try expectCmdline("tars.noconfig console=ttyS0", true);
    try expectCmdline("console=ttyS0 tars.noconfigured", false);
    try expectCmdline("console=ttyS0 nottars.noconfig", false);
    // 실제 cmdline은 줄바꿈으로 끝난다(`/proc/cmdline`이 그렇다).
    try expectCmdline("console=ttyS0 tars.noconfig\n", true);
    // 빈 cmdline도 정상 입력이다.
    try expectCmdline("", false);
    // **값이 붙어도 받는다.** 이 토큰은 있고 없음이 전부이고 값은 뜻이
    // 없다 — 끄는 방법은 `tars.noconfig=0`이 아니라 안 적는 것이다.
    // 받아 주지 않으면 `=1`을 적은 사람이 아무 일도 안 일어나는 것을 보고
    // 탈출로가 없다고 믿는다.
    try expectCmdline("tars.noconfig=1", true);
    try expectCmdline("tars.noconfig=0", true);
```

- [ ] **Step 2: 그 헬퍼를 `expectQuietSeed` 아래에 넣는다**

```zig
/// cmdline 한 줄이 rc를 끄는가(SC-M2 결정 9).
///
/// **`expect`와 같은 자리에 있는 함수다** — `config.zig`에서 시스템 콜이
/// 없는 부분이 이제 둘이고, 둘 다 게스트를 안 띄우고 검증할 수 있다.
fn expectCmdline(text: []const u8, want: bool) !void {
    const got = config.cmdlineWantsNoConfig(text);
    if (got == want) return;
    std.debug.print("FAIL: cmdline \"{s}\" gave {}, want {}\n", .{ text, got, want });
    return error.UnexpectedCmdline;
}
```

- [ ] **Step 3: 실패를 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test'
```

Expected: 컴파일 실패 — `no member named 'cmdlineWantsNoConfig' in struct 'config'`.
**이것이 이 Task의 산출물이다.**

---

## Task 2: `config.zig`에 토큰과 그 독자를 만든다

**Files:** Modify `init/src/config.zig`

- [ ] **Step 1: `ShellConfig` enum **아래**에 상수 둘과 순수 함수를 넣는다**

```zig
/// 커널 cmdline이 rc를 끄는 토큰(SC design 결정 9). **`tars.conf`를 이기는
/// 것은 이 키 하나뿐이다** — 우선순위는 **cmdline > tars.conf > 기본값**이고,
/// 다른 다섯 키는 cmdline을 안 본다. 그 예외의 근거는 하나다: *"`tars.conf`를
/// 고칠 셸이 없을 때 쓰는 것"*.
pub const NO_CONFIG_TOKEN = "tars.noconfig";

/// 커널 cmdline이 사는 자리. `/proc`은 설정을 읽기 전에 이미 붙어 있다
/// (design 실측 13 — `main.zig`가 `:454`에서 붙이고 `:459`가 `/config`다).
pub const CMDLINE_PATH: [:0]const u8 = "/proc/cmdline";

/// cmdline 문자열에 위 토큰이 있는가. **시스템 콜이 없는 순수 함수라서
/// `parse`와 같은 성질이다** — 게스트를 안 띄우고 검증할 수 있고,
/// `config_test.zig`가 실제로 그렇게 한다.
///
/// **부분 문자열이 아니라 토큰으로 본다.** `indexOf` 한 줄로 짜면
/// `tars.noconfigured`나 `nottars.noconfig`에도 걸리고, 그 실수의 증상은
/// "부팅했더니 rc가 안 읽힌다" 하나뿐이라 원인에서 아주 멀다.
///
/// **값이 붙어 있어도 받는다**(`tars.noconfig=1`). 이 토큰은 있고 없음이
/// 전부이고 값은 뜻이 없다 — 그래서 값을 본 것을 로그로 알린다. 끄는 방법은
/// `tars.noconfig=0`이 아니라 그 단어를 안 적는 것이다.
pub fn cmdlineWantsNoConfig(text: []const u8) bool {
    var it = std.mem.tokenizeAny(u8, text, " \t\r\n");
    while (it.next()) |token| {
        const eq = std.mem.indexOfScalar(u8, token, '=') orelse token.len;
        if (!std.mem.eql(u8, token[0..eq], NO_CONFIG_TOKEN)) continue;
        if (eq != token.len) {
            std.debug.print("tars-init: {s} takes no value, '{s}' means the same thing\n", .{
                NO_CONFIG_TOKEN, token,
            });
        }
        return true;
    }
    return false;
}
```

- [ ] **Step 2: 파일 끝(`seedRcFile` 아래)에 그 독자를 넣는다**

```zig
/// `/proc/cmdline`을 읽어 위 토큰이 있는지 본다.
///
/// **못 읽으면 false다.** 이 함수의 답은 "사용자의 설정을 덮어쓸까"이고,
/// 못 읽었을 때 덮는 쪽으로 기울면 `/proc`이 안 붙은 부팅에서 rc가 조용히
/// 꺼진다 — `load`가 "읽기에 실패한 파일은 덮어쓰지 않는다"고 정한 것과
/// 같은 방향이다.
///
/// **`load`의 읽기 루프를 공유하지 않는다.** 저쪽은 optional로 ENOENT
/// 하나를 구분해야 해서 계약이 다르다(그 구분이 seeding을 부르는 조건이다).
/// 세 줄을 아끼려고 그 구분을 흐리는 것보다 각자 갖는 편이 읽기 쉽다 —
/// 이 파일 머리의 `failed`가 `main.zig`와 겹치는 것과 같은 판단이다.
pub fn cmdlineNoConfig(path: [:0]const u8) bool {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: cannot read {s} (errno {d}), assuming no {s}\n", .{
            path, @intFromEnum(e), NO_CONFIG_TOKEN,
        });
        return false;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    // x86의 COMMAND_LINE_SIZE가 2048이라 MAX_FILE 안에 넉넉히 들어간다.
    var buf: [MAX_FILE]u8 = undefined;
    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            std.debug.print("tars-init: failed to read {s} (errno {d})\n", .{
                path, @intFromEnum(e),
            });
            return false;
        }
        if (n == 0) break;
        len += n;
    }
    return cmdlineWantsNoConfig(buf[0..len]);
}
```

- [ ] **Step 3: 호스트 검사가 통과하는 것을 본다 — 두 번 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test'
```

Expected: `PASS`. **두 번 돌리는 이유는 design 실측 26이다**(`zig build test`가
두 번, 직전 내용의 결과를 냈다. 원인 미상).

- [ ] **Step 4: 커밋**

```bash
git add init/src/config.zig init/src/config_test.zig
git commit -m "Let one word on the command line outrank the config file"
```

---

## Task 3: PID 1이 cmdline을 설정보다 위에 둔다 (결정 9)

**Files:** Modify `init/src/main.zig`

- [ ] **Step 1: `const cfg = loadConfig(storage_mounted);` 한 줄을 바꾼다**

**지울 것:**

```zig
    const cfg = loadConfig(storage_mounted);
```

**넣을 것:**

```zig
    var cfg = loadConfig(storage_mounted);
    // SC-M2 결정 9 — 탈출로 2. **cmdline > tars.conf > 기본값.**
    //
    // 이 키 하나만 이 예외를 갖는다. 근거는 *"`tars.conf`를 고칠 셸이 없을
    // 때 쓰는 것"*이다 — 사용자의 rc가 셸을 죽이거나 매달리게 만들면 설정을
    // 고칠 자리가 통째로 사라진다(design 위험 3). 실기는 limine 메뉴를
    // 지나므로 사람이 부팅 순간에 이 단어를 적어 넣을 수 있다(실측 12).
    //
    // **`loadConfig` 바로 뒤인 것이 중요하다.** 아래의 `config shell=` 로그
    // 줄과 argv 배선이 전부 `cfg`를 보므로, 여기서 덮으면 그 뒤는 아무것도
    // 안 고쳐도 된다 — 게이트도 그 한 줄에서 **실효값**을 읽는다.
    //
    // **매달리는 rc까지 덮는 것이 탈출로 1과 다른 점이다**(결정 8은 자식이
    // 죽어야 발동한다). 대가는 사람이 부팅 순간에 개입해야 한다는 것이고,
    // 그래서 둘이 서로를 대체하지 않는다.
    if (config.cmdlineNoConfig(config.CMDLINE_PATH)) {
        // **크게 찍는다.** 이 줄이 없으면 "설정 파일에는 on이라고 적혀 있는데
        // 왜 rc가 안 읽히지"가 영영 안 풀린다.
        std.debug.print("tars-init: {s} on the kernel command line beats {s}, shell_config=off\n", .{
            config.NO_CONFIG_TOKEN, CONFIG_PATH,
        });
        cfg.shell_config = .off;
    }
```

- [ ] **Step 2: 빌드만 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build && zig build test'
```

Expected: `PASS`(호스트 검사는 이 갈래를 안 지난다 — 지나는 것은 4차·5차
부팅이다).

- [ ] **Step 3: 커밋**

```bash
git add init/src/main.zig
git commit -m "Read the command line before trusting the disk"
```

---

## Task 4: 감독자가 포기하기 직전에 rc 없이 한 번 더 띄운다 (결정 8)

**Files:** Modify `init/src/main.zig`

- [ ] **Step 1: `Kind` enum **아래**, `TERMINAL_PATH` **위**에 `Rescue`와 슬롯 둘을 넣는다**

```zig
/// 탈출로 1(SC design 결정 8). 감독자가 포기하기 **직전에** argv의 이 자리를
/// 이 값으로 바꾸고 딱 한 번 다시 띄운다.
///
/// **자리가 자식마다 다르다.** terminal은 argv[2]가 "셸에 넘길 플래그"이고
/// (argv[1]은 셸 경로다), 콘솔 셸은 argv[1]이 그 플래그 자체다 — argv를 짓는
/// 쪽과 쓰는 쪽이 갈리느냐 아니냐의 차이가 여기서도 한 번 더 나온다
/// (`config.zig`의 `configFlag` 주석이 같은 비대칭을 적고 있다). 그래서
/// 슬롯 번호를 값으로 들고 다닌다.
const Rescue = struct {
    slot: usize,
    flag: [:0]const u8,
};

/// 위 슬롯 둘. **`children` 배열의 argv 리터럴과 짝이고, 어긋나면 탈출로가
/// 엉뚱한 인자를 덮어쓴다** — terminal이면 키보드 종류 자리다.
const TERMINAL_FLAG_SLOT: usize = 2;
const CONSOLE_FLAG_SLOT: usize = 1;
```

- [ ] **Step 2: `Child`에 필드 하나를 더한다. `given_up` 아래에 넣는다**

```zig
    /// 남아 있는 탈출로. **한 번 쓰면 null이 된다** — 결정 8의 "한 번만"이
    /// 상태 하나로 표현되는 자리다. 처음부터 null이면 이 자식에게는 탈출로가
    /// 없다(설정 디스크가 없거나 이미 `shell_config=off`다).
    rescue: ?Rescue = null,
```

- [ ] **Step 3: `supervise`의 포기 갈래 **앞**에 탈출 분기를 넣는다**

`if (c.fast_restarts >= MAX_FAST_RESTARTS) {` 바로 **다음 줄**에 **넣을 것**:

```zig
                // ── 탈출로 1(SC-M2 결정 8) ──────────────────────────────
                //
                // 포기하기 **직전에** rc 없이 한 번 더 띄운다. 빨리 죽는
                // 이유 중 우리가 고칠 수 있는 것은 사용자의 rc 하나뿐이고,
                // 그것을 뺀 셸은 SC 이전의 셸과 같다 — 이 저장소가 오래
                // 돌려 온 상태다. `resolveShell()`이 없는 셸에 대해 하는
                // 폴백과 **같은 모양**이다: 설정이 가리키는 것이 실제로 안
                // 되면 되는 것으로 떨어지고, 부팅은 계속된다.
                //
                // **덮는 것은 "죽는 rc"까지다.** 매달리는 rc(`read` 한 줄,
                // 무한 루프)는 자식이 안 죽으니 이 길로 안 온다 — 그것이
                // 탈출로 2가 따로 있는 이유다(결정 9).
                if (c.rescue) |r| {
                    c.argv[r.slot] = r.flag.ptr;
                    c.rescue = null; // 한 번만
                    // 이 줄 둘이 이 기능의 사용자 인터페이스 전부다.
                    // "왜 내 rc가 안 먹지"가 로그 한 줄로 답이 되어야 한다.
                    std.debug.print("tars-init: {s} died {d} times fast, the rc files are the suspect; restarting it with {s}\n", .{
                        c.kind.name(), c.fast_restarts, r.flag,
                    });
                    std.debug.print("tars-init: to keep it that way put shell_config=off in {s}, or {s} on the kernel command line\n", .{
                        CONFIG_PATH, config.NO_CONFIG_TOKEN,
                    });
                    c.fast_restarts = 0;
                    continue;
                }
```

`c.fast_restarts = 0`이 로그 **뒤**인 것에 뜻이 있다 — 찍는 수가 "몇 번 죽고
나서 이 결정을 했는가"여야 한다.

- [ ] **Step 4: `main`에서 탈출로를 만든다. `const console_flag ...` 블록 **아래**에 넣는다**

```zig
    // SC-M2 결정 8 — 탈출로 1. **자식 둘 다에게 준다**(결정 4가 두 셸을 같은
    // 설정으로 묶은 것의 연장이다).
    //
    // **`storage_mounted`를 함께 보는 것이 이 조건의 핵심이다.** 디스크가 안
    // 붙은 부팅에는 rc 실체가 아예 없다 — 홈의 링크는 끊어져 있고 셸은
    // 아무것도 안 읽는다(SC-M0이 여섯 체인에서 확인한 정상 경로다). 그런
    // 기계에서 자식이 죽는 이유는 rc가 아니고, **고칠 수 있는 것이 없는데
    // 다시 띄우는 것은 탈출이 아니라 소음이다.**
    //
    // 그리고 그 소음은 남의 검사를 깬다: BF 체인은 `-vga none`이라 terminal이
    // 매번 죽고, `boot/check.sh:112`가 그 재시작 횟수를 **정확히 3**으로 세고
    // 있다(그 수가 곧 `MAX_FAST_RESTARTS` 정책이다). 조건 없이 주면 6이 된다.
    //
    // `off`일 때 안 주는 이유는 단순하다 — 이미 rc를 안 읽는 셸에서 뺄
    // 것이 없다.
    const rescue_flag: ?[:0]const u8 = if (storage_mounted and cfg.shell_config == .on)
        shell.noConfigFlag()
    else
        null;
```

- [ ] **Step 5: `children` 리터럴의 자식 둘에 `.rescue`를 더한다**

terminal 쪽 `.argv = .{ ... },` **아래**:

```zig
            .rescue = if (rescue_flag) |f| .{ .slot = TERMINAL_FLAG_SLOT, .flag = f } else null,
```

콘솔 셸 쪽 `.argv = .{ ... },` **아래**:

```zig
            .rescue = if (rescue_flag) |f| .{ .slot = CONSOLE_FLAG_SLOT, .flag = f } else null,
```

- [ ] **Step 6: 빌드와 호스트 검사**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build && zig build test'
```

Expected: `PASS`.

- [ ] **Step 7: 커밋**

```bash
git add init/src/main.zig
git commit -m "Give a dying shell one last life without its rc"
```

---

## Task 5: 게이트의 부팅을 다섯으로 늘린다

**Files:** Modify `config/check.sh`

- [ ] **Step 1: `boot_once`가 cmdline을 받게 한다**

**지울 것:**

```bash
# 부팅 한 번. $1 = 시리얼 로그 파일, $2 = 기다릴 마커, $3 = (선택) 마커를 본 뒤
# QEMU를 죽이기 전에 부를 함수.
boot_once() {
  local log="$1"
  local marker="$2"
  local hook="${3:-}"
```

**넣을 것:**

```bash
# 부팅 한 번. $1 = 시리얼 로그 파일, $2 = 기다릴 마커, $3 = (선택) 마커를 본 뒤
# QEMU를 죽이기 전에 부를 함수, $4 = (선택) 커널 cmdline.
#
# **넷째 인자는 SC-M2가 더했다.** 5차 부팅만 다른 cmdline으로 뜬다 —
# 탈출로 2가 보는 것이 `/proc/cmdline`이라 그것 말고 심을 자리가 없다
# (실기에서는 limine 메뉴가 이 자리다).
boot_once() {
  local log="$1"
  local marker="$2"
  local hook="${3:-}"
  local cmdline="${4:-console=ttyS0}"
```

그리고 같은 함수 안의 `-append "console=ttyS0" \`를 **지우고** `-append "$cmdline" \`를 **넣는다.**

- [ ] **Step 2: 3차 부팅의 훅을 "심는 훅"으로 바꾼다**

**지울 것:**

```bash
# 3차 부팅의 훅. **타이핑을 안 하므로 관측 창만 있다.** 2차가 쓰는 함수를
# 그대로 쓸 수 없는 이유는 그쪽이 설정을 고치기 때문이다 — 3차가 그것을
# 부르면 tars.conf에 off가 한 줄 더 붙는다(해롭진 않지만 거짓말이 된다).
watch_console_shell_quiet() {
  sleep 5
  return 0
}
```

**넣을 것:**

```bash
# 3차 부팅의 훅. **관측 창 + 4차가 밟을 함정을 판다**(SC-M2).
#
# M1까지 이 부팅은 아무것도 안 쳤다. 이유는 *"타이핑을 하면 그 글자가 화면에
# 남고, 판정 글자가 우연히 화면에 생기는 길이 하나 늘어난다"*였고 **그 이유는
# 그대로 산다.** 그래서 여기서 치는 두 명령과 그 되읽기에 `tars-rc-alive`가
# 한 글자도 안 들어간다 — 되읽기를 `cat /config/zshrc`가 아니라
# `grep exit /config/zshrc`로 하는 것이 그래서다.
#
# 심는 것 둘:
#   1. `/config/zshrc` 끝에 `exit` — **일부러 죽는 rc다.** 이 한 줄이 셸을
#      rc 처리 도중에 끝내므로 셸은 프롬프트를 그리기 전에 죽는다.
#   2. `tars.conf`에 `shell_config=on` — 3차가 쓴 `off`를 되돌린다. **마지막
#      줄이 이긴다**(config_test.zig가 그 규칙을 못 박고 있다).
#
# **순서가 중요하다.** 이 부팅의 셸은 `off`라 rc를 안 읽으므로, 여기서 함정을
# 파도 이 부팅은 안 다친다. 4차부터 밟는다.
plant_broken_rc() {
  local log="$1"
  LOG="$log"

  sleep 5

  local ready=0
  for _ in $(seq 1 120); do
    if grep -q "terminal: screen>" "$log"; then ready=1; break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  if [ "$ready" != "1" ]; then
    echo "FAIL(boot 3): terminal never rendered a prompt; there was nothing to type into"
    return 1
  fi

  local connected=0
  for _ in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
    sleep 0.5
  done
  if [ "$connected" != "1" ]; then
    echo "FAIL(boot 3): could not connect to QEMU monitor on port ${MONITOR_PORT}"
    return 1
  fi

  type_keys "${BREAK_KEYS[@]}"
  type_keys "${BREAK_READBACK_KEYS[@]}"
  local ok=0
  if wait_for_screen '\| exit'; then ok=1; fi
  if [ "$ok" != "1" ]; then
    exec 3<&-
    exec 3>&-
    echo "FAIL(boot 3): the exit line never landed in /config/zshrc; boot 4 would have no trap to spring"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 3: planted a shell-killing 'exit' in /config/zshrc for the fourth boot"

  type_keys "${ON_KEYS[@]}"
  type_keys "${READBACK_KEYS[@]}"
  ok=0
  if wait_for_screen '\| shell_config=on'; then ok=1; fi

  exec 3<&-
  exec 3>&-

  if [ "$ok" != "1" ]; then
    echo "FAIL(boot 3): typed shell_config=on but /config/tars.conf never read it back"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 3: turned shell_config back on so the fourth boot walks into that trap"
  return 0
}

# 4차 부팅의 훅. **타이핑은 없고 기다리는 것이 둘이다.**
#
#   1. terminal의 탈출로는 콘솔 셸의 것보다 **늦게** 온다 — 콘솔 셸은 죽는 데
#      0초가 걸리고 terminal은 DRM을 열고 폰트를 굽고 나서 셸을 띄우므로 한
#      바퀴가 몇 초다. 부팅의 마커는 빠른 쪽(콘솔 셸)이라 느린 쪽을 여기서
#      기다린다.
#   2. **되살아난 둘이 그대로 사는지** 본다. 확인할 것이 "없어야 할 것"
#      (더 이상의 재시작·포기)이라 부재를 폴링으로 증명할 수 없다 — 2차
#      부팅의 5초와 같은 이유의 고정 대기이고, 재시작 backoff 1초에 terminal의
#      기동 몇 초를 더해 넉넉히 잡았다.
watch_rescue() {
  local log="$1"

  local seen=0
  for _ in $(seq 1 60); do
    if grep -q "tars-init: terminal died" "$log"; then seen=1; break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  if [ "$seen" != "1" ]; then
    echo "FAIL(boot 4): the console shell was rescued but the terminal never was"
    return 1
  fi

  sleep 8
  return 0
}

# 5차 부팅의 훅. **여기가 M1의 3차와 같은 자리다** — 볼 것이 전부 "없어야 할
# 것"이라 타이핑을 안 하고 관측 창만 둔다.
watch_quiet() {
  sleep 8
  return 0
}
```

- [ ] **Step 3: 타이핑 키 배열 둘을 `OFF_KEYS` 아래에 더한다**

```bash
# ── SC-M2 ───────────────────────────────────────────────────────────────
# echo exit >> /config/zshrc — 3차 부팅에서 친다. **일부러 죽는 rc다.**
BREAK_KEYS=(e c h o spc e x i t spc shift-dot shift-dot spc
            slash c o n f i g slash z s h r c ret)
# grep exit /config/zshrc — 되읽기.
#
# **cat이 아니라 grep인 이유가 둘이다.** 하나는 M1의 이유 그대로(씨앗이
# 열몇 줄이라 첫 줄이 프레임에 안 남는다), 다른 하나는 이 부팅이 **부정
# 검사를 갖고 있다는 것**이다 — cat하면 `echo tars-rc-alive`가 화면에 뜨고
# 그것을 3차의 판정이 보게 된다. 화면에 안 띄우는 것이 요점이다.
BREAK_READBACK_KEYS=(g r e p spc e x i t spc slash c o n f i g slash z s h r c ret)
# echo shell_config=on >> /config/tars.conf — 3차가 쓴 off를 되돌린다.
ON_KEYS=(e c h o spc s h e l l shift-minus c o n f i g equal o n spc
         shift-dot shift-dot spc slash c o n f i g slash t a r s dot c o n f ret)
```

- [ ] **Step 4: 3차 부팅의 훅 이름과 제목을 바꾼다**

**지울 것:**

```bash
if ! boot_once "$LOG3" "tars-init: started console shell" watch_console_shell_quiet; then
```

**넣을 것:**

```bash
if ! boot_once "$LOG3" "tars-init: started console shell" plant_broken_rc; then
```

- [ ] **Step 5: 3차 부팅의 마지막 줄 뒤에 4차·5차를 통째로 더한다**

`echo "boot 3: shell_config=off kept both shells out of the rc that boot 2 ran"` 아래의 두 검사
(`giving up on console shell` · `Attempted to kill init`) 다음, `# 정보성. ext2가 ...` **앞**에
**넣을 것**:

```bash
# ---------------------------------------------------------------- 4차 부팅
# 또 같은 이미지다. 3차가 `/config/zshrc`에 `exit` 한 줄을 심고
# `shell_config=on`을 되돌려 두었다 — **이 부팅의 두 셸은 뜨자마자 죽는다.**
#
# design 위험 3이 말하는 상태가 정확히 이것이다: *"rc가 깨지면 그것을 고칠
# 셸이 없다."* M1까지 이 기계의 탈출로는 호스트에서 ext2 이미지를 직접 고치는
# 것뿐이었다.
LOG4="$(mktemp)"
echo "=== boot 4/5: the rc kills both shells; the supervisor must bring them back without it ==="
if ! boot_once "$LOG4" "tars-init: console shell died" watch_rescue; then
  report_failure "$LOG4" "the supervisor never rescued a shell from the rc that kills it"
fi

# 먼저 **이 부팅이 함정을 실제로 밟았는지** 확인한다. 아래 검사들은 "되살아
# 났다"를 보는데, 애초에 안 죽었으면 전부 공허해진다.
if ! grep -q "tars-init: config shell=zsh.*shell_config=on" "$LOG4"; then
  report_failure "$LOG4" "fourth boot did not read back the shell_config=on the third boot restored"
fi

# 콘솔 셸이 rc를 **읽었다**는 증거. 그 rc의 마지막 줄이 exit이므로 읽었다는
# 것과 죽었다는 것이 같은 사실이다. **세 번인 것이 정책 그 자체다** —
# 처음 뜨고, 두 번 재시작하고, 세 번째 빠른 종료에서 탈출로가 발동한다
# (main.zig의 MAX_FAST_RESTARTS = 3). boot/check.sh:112가 같은 모양으로
# 센다.
ALIVE="$(grep "tars-rc-alive" "$LOG4" | grep -cv "terminal: screen>" || true)"
if [ "$ALIVE" != "3" ]; then
  report_failure "$LOG4" "the console shell ran the broken rc ${ALIVE} times, want exactly 3 (then the rescue must stop it)"
fi

# ★ SC-M2가 증명하려는 것의 절반. **자식 둘 다 탈출로를 받는다**(결정 4의
#   "두 셸이 같은 설정을 따른다"가 여기까지 온다).
if ! grep -q "tars-init: console shell died .* times fast" "$LOG4"; then
  report_failure "$LOG4" "the supervisor never offered the console shell a life without the rc"
fi
if ! grep -q "tars-init: terminal died .* times fast" "$LOG4"; then
  report_failure "$LOG4" "the supervisor never offered the terminal a life without the rc"
fi

# 그리고 **그 탈출이 성공했다.** 포기 줄이 하나도 없다는 것이 그 뜻이다 —
# 탈출로가 없던 M1이었다면 이 부팅은 자식 둘을 다 포기한 기계로 끝난다.
if grep -q "tars-init: giving up on" "$LOG4"; then
  report_failure "$LOG4" "the supervisor gave up anyway; the rescue did not save the shell"
fi

# 개수가 정책이다. 처음 셋은 rc를 읽고 죽었고 넷째가 rc 없이 살아남았다.
# 다섯이면 되살린 것도 죽은 것이고, 셋이면 탈출로가 안 돌았다는 뜻이다.
for want in "console shell" "terminal"; do
  STARTS="$(grep -c "tars-init: started ${want}" "$LOG4" || true)"
  if [ "$STARTS" != "4" ]; then
    report_failure "$LOG4" "init started the ${want} ${STARTS} times, want exactly 4 (three with the rc, one without)"
  fi
done

# 되살아난 화면 셸이 실제로 프롬프트를 그렸다. 죽는 동안에는 이 줄이 안
# 나온다 — 셸이 rc 처리 중에 죽어서 PTY에 아무것도 안 오기 때문이다.
if ! grep -q "terminal: screen>" "$LOG4"; then
  report_failure "$LOG4" "the rescued terminal never rendered; the machine came back unusable"
fi

if grep -q "Attempted to kill init" "$LOG4"; then
  report_failure "$LOG4" "kernel panicked because PID 1 exited on the fourth boot"
fi
echo "boot 4: the rc killed both shells three times, then the supervisor brought them back without it"

# ---------------------------------------------------------------- 5차 부팅
# 같은 이미지, 같은 함정. **다른 것은 커널 cmdline의 한 단어뿐이다.**
#
# **4차가 이 부팅의 부정 검사를 진짜로 만든다** — 같은 디스크로 방금 셸이
# 여섯 번 죽는 것을 봤으므로, 여기서 아무도 안 죽으면 그것은 tars.noconfig가
# 한 일이다. M1의 3차가 2차에 기대던 구조와 같다.
LOG5="$(mktemp)"
echo "=== boot 5/5: same disk, same trap, but tars.noconfig on the command line ==="
if ! boot_once "$LOG5" "tars-init: started console shell" watch_quiet "console=ttyS0 tars.noconfig"; then
  report_failure "$LOG5" "fifth boot never started a console shell"
fi

# 기계가 2·3·4차와 같은 디스크를 봤다는 것부터.
if ! grep -q "tars-init: loaded /config/tars.conf" "$LOG5"; then
  report_failure "$LOG5" "fifth boot did not load /config/tars.conf"
fi

# ★ SC-M2가 증명하려는 나머지 절반. **파일에는 on이라고 적혀 있다**(4차가
#   같은 파일에서 on을 읽었다). 그런데 실효값이 off다 — cmdline이 이긴 것이다.
if ! grep -q "tars-init: tars.noconfig on the kernel command line beats /config/tars.conf" "$LOG5"; then
  report_failure "$LOG5" "init never reported that the command line token outranked the config file"
fi
if ! grep -q "tars-init: config shell=zsh.*shell_config=off" "$LOG5"; then
  report_failure "$LOG5" "the command line token did not turn shell_config off"
fi

# 그리고 **아무도 rc를 안 읽었다.** 같은 디스크에서 4차는 여섯 번 죽었다.
if grep -q "tars-rc-alive" "$LOG5"; then
  report_failure "$LOG5" "tars.noconfig did not keep the shells out of the rc"
fi
if grep -q "tars-init: died\|tars-init: .* times fast" "$LOG5"; then
  report_failure "$LOG5" "a shell still died on the fifth boot; the token did not reach the rc decision"
fi
if grep -q "tars-init: giving up on" "$LOG5"; then
  report_failure "$LOG5" "the supervisor gave up on a child that had no reason to die"
fi

# 한 번 뜨고 그대로 산다. 4차의 넷과 나란히 놓으면 이 수가 이야기 전부다.
for want in "console shell" "terminal"; do
  STARTS="$(grep -c "tars-init: started ${want}" "$LOG5" || true)"
  if [ "$STARTS" != "1" ]; then
    report_failure "$LOG5" "init started the ${want} ${STARTS} times on the fifth boot, want exactly 1"
  fi
done

if ! grep -q "terminal: screen>" "$LOG5"; then
  report_failure "$LOG5" "the terminal never rendered on the fifth boot"
fi
if grep -q "Attempted to kill init" "$LOG5"; then
  report_failure "$LOG5" "kernel panicked because PID 1 exited on the fifth boot"
fi
echo "boot 5: one word on the kernel command line beat the config file, and nothing died"
```

- [ ] **Step 6: 로그 파일 선언과 마지막 덤프를 다섯으로 맞춘다**

`LOG3="$(mktemp)"` 아래는 그대로 두고(4차·5차는 위에서 선언한다), 파일 끝의
덤프 셋 아래에 **넣을 것**:

```bash
echo "--- init log (boot 4) ---"
grep 'tars-init:' "$LOG4" || true
echo "--- init log (boot 5) ---"
grep 'tars-init:' "$LOG5" || true
```

그리고 부팅 제목 셋의 `1/3`·`2/3`·`3/3`을 `1/5`·`2/5`·`3/5`로 고친다.

- [ ] **Step 7: 체인을 단독으로 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash config/check.sh
```

Expected: `PASS`. 부팅 다섯이라 약 2분.

- [ ] **Step 8: 커밋**

```bash
git add config/check.sh
git commit -m "Break the rc on purpose and watch the machine come back"
```

---

## Task 6: 음성 확인 — **넷을 각각 두 번씩**

**Files:** 없음(고쳤다가 `git checkout`으로 되돌린다)

design 실측 26 때문에 **전부 두 번씩 돌린다**(`zig build test`가 두 번, 직전
내용의 결과를 냈다. 원인 미상). 그리고 Zig를 되돌린 뒤에는
`rm -rf init/zig-out terminal/zig-out`을 한 번 한다(UT design 실측 18).

- [ ] **Step 1: 탈출로 1을 끈다 — 4차가 죽어야 한다**

`main.zig`의 `rescue_flag`를 조건 없이 `null`로 둔다. 기대: 4차 부팅에서
`the supervisor never offered the console shell a life without the rc`.
**1·2·3차와 5차는 통과해야 한다** — 5차는 탈출로 1을 안 쓰기 때문이다.

- [ ] **Step 2: `storage_mounted` 조건을 뗀다 — `boot/check.sh`가 죽어야 한다**

`if (storage_mounted and cfg.shell_config == .on)`에서 `storage_mounted and`를
지우고 **`boot/check.sh`를 돌린다.** 기대:
`FAIL: init started the terminal 6 times, want exactly 3`.

**이 확인이 이 milestone에서 가장 값지다** — 우리 코드가 **남의 검사**를
깨뜨릴 수 있다는 것을 실행으로 보는 자리이고, 그 조건이 왜 있는지가 로그 한
줄이 된다.

- [ ] **Step 3: 결정 9의 덮어쓰기를 지운다 — 5차가 죽어야 한다**

`main.zig`의 `if (config.cmdlineNoConfig(...))` 블록을 통째로 지운다. 기대:
5차 부팅에서 `init never reported that the command line token outranked the
config file`. **4차까지는 전부 통과한다.**

- [ ] **Step 4: 토큰 매칭을 느슨하게 한다 — 호스트 검사가 죽어야 한다**

`cmdlineWantsNoConfig`의 본문을
`return std.mem.indexOf(u8, text, NO_CONFIG_TOKEN) != null;`로 바꾼다.
기대: **부팅 전에** `FAIL: cmdline "console=ttyS0 tars.noconfigured" gave true, want false`.

- [ ] **Step 5: 전부 되돌리고 깨끗한지 확인한다**

```bash
git checkout init/src/main.zig init/src/config.zig
rm -rf init/zig-out terminal/zig-out
git status --short     # 비어 있어야 한다
```

---

## Task 7: 루트 게이트

- [ ] **Step 1: 백그라운드로 돌린다 (약 25분)**

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

Expected: 열한 체인 3/3. **기준선은 SC-M1의 24분 36.55초**이고, 부팅 둘이
늘었으니 **+1분 안쪽**이면 예상대로다(M1의 부팅 하나가 +27.76초였다).

- [ ] **Step 2: 씨앗·탈출로가 다른 체인을 안 건드렸다는 것을 따로 본다**

```bash
grep -c "tars-init: giving up on" /tmp/gate.log        # BF 3회 + ... 세어 본다
grep -c "times fast" /tmp/gate.log                     # config 체인의 4차뿐이어야 한다(3회 = 회차마다 2)
grep -ac "Welcome to fish" /tmp/gate.log               # 6이어야 한다(M0·M1과 같다)
```

---

## Task 8: 문서

- [ ] **Step 1: design의 `Status:`와 milestone 표, 위험 3을 닫는다**
- [ ] **Step 2: design에 "SC-M2가 실행으로 증명한 것"(실측 29~)을 더한다**
- [ ] **Step 3: `docs/decisions/project_shell_config.md`에 SC-M2 절을 더한다**
- [ ] **Step 4: `MEMORY.md`·`CLAUDE.md`의 한 줄을 고친다**
- [ ] **Step 5: `HANDOFF.md`를 SC-M2로 새로 쓴다**
- [ ] **Step 6: 커밋**

---

## Self-Review

**spec 커버리지.** 결정 8 → Task 4·5(4차 부팅) · 결정 9 → Task 2·3·5(5차
부팅) · 위험 3의 나머지 절반 → 둘 다. design의 milestone 표에서 SC-M2가
적은 검증 둘(*"일부러 죽는 rc를 깔면 감독자가 되살린다"* · *"`tars.noconfig`가
`tars.conf`를 이긴다"*)이 각각 4차·5차다.

**이 plan이 design보다 더 정한 것 셋.**

1. **탈출로에 `storage_mounted` 조건을 건다** — design은 "`given_up`을 세우기
   전에 한 번만"까지만 적었다. BF 체인의 `want exactly 3`을 안 깨려면 필요하고,
   근거는 "디스크가 없으면 탓할 rc도 없다"이다.
2. **`tars.noconfig=값`도 받는다** — design은 "그 토큰이 있으면"까지만 적었다.
3. **함정을 3차에서 판다** — design은 4차·5차를 따로 적지 않았다(게이트는
   결정 10의 부팅 셋까지다). 부팅을 둘만 늘리려면 3차가 타이핑을 해야 한다.

**타입 일관성.** `Rescue{ slot, flag }` · `Child.rescue: ?Rescue` ·
`rescue_flag: ?[:0]const u8` · `cmdlineWantsNoConfig([]const u8) bool` ·
`cmdlineNoConfig([:0]const u8) bool` — Task 1의 검사가 부르는 이름과 Task 2가
정의하는 이름이 같다.
