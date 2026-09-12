# SM-M2 Implementation Plan — 배운 것이 부팅을 넘어 남는다

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan
> task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기계가 배운 것 둘(자주 간 디렉터리 · 쳤던 명령)이 **전원을 끊어도
남는다.** 게이트의 **8차 부팅**이 그것을 본다 — 그 부팅은 `cd`를 한 번도 안
치는데 `z`가 7차에서 배운 자리로 걸어 들어가고, `history`가 7차만 친 명령을
갖고 있다.

**Architecture:** 새 파일이 하나도 없다. 고치는 파일이 다섯이고, **씨앗 rc와
`expectQuietSeed`는 한 글자도 안 건드린다**(design 결정 3 — 히스토리 줄이 rc에
한 줄도 필요 없다).

| 파일 | 이 milestone에서 하는 일 |
|---|---|
| `init/src/environ.zig` | `withPath` → **`withTarsEnv`**. `XDG_DATA_HOME`과 히스토리 항목들을 커널 블록 뒤에 붙인다 |
| `init/src/config.zig` | `Shell.histEntries()` — 셸마다 다른 `HISTFILE`·`HISTSIZE`·`SAVEHIST` |
| `init/src/main.zig` | env 블록을 **셸이 정해진 뒤에** 짓고, `/config/xdg`를 `seedRcFiles` 옆에서 만든다 |
| `init/src/environ_test.zig` · `config_test.zig` | 위 둘의 호스트 검사 |
| `config/check.sh` | 7차가 `fc -W`를 더 치고, **8차 부팅**이 선다 |
| `tools/check.sh` | **주석 한 자리만** — DB가 이제 `/config/xdg`에 산다 |
| `kernel/` · `terminal/` · `devcontainer/` | **안 고친다** |

**Tech Stack:** Zig 0.16(init) · bash(게이트 체인) · QEMU monitor `sendkey`

**협업 규칙:** 이 세션은 **기본 규칙**이다 — 구현 파일은 Claude가 "넣을 것"을
제시하고 **사용자가 직접 넣는다.** 빌드·부팅·게이트 실행과 조사성 명령은
Claude가 돌린다. 커밋도 Claude가 만든다.

**읽고 시작할 것:**
`docs/superpowers/specs/2026-09-11-tars-shell-memory-design.md` — 특히
**실측 3(zoxide는 `XDG_DATA_HOME`을 본다) · 4(없는 경로는 만들고 댕글링 링크는
에러다) · 9·10·11(히스토리 env) · 결정 2·3·4·9**. 그리고 이 plan의 Task 1이
그 위에 실측 **34~41**을 얹었다 — **셋이 design을 고쳤다.**

그리고 `docs/decisions/project_zig_out_staleness.md`. **음성 확인을 하기 전에
`rm -rf init/.zig-cache init/zig-out`을 친다.** 안 치면 5회 중 1회가 거짓
초록이고, 어느 회차인지 알려 주는 신호가 없다.

---

## 이 milestone을 지배하는 사실 셋

### 1. **게이트는 전원을 뽑는다** — 그래서 7차가 히스토리를 직접 써야 한다

`boot_once`는 마커를 보면 `kill "$QEMU_PID"`로 기계를 끝낸다. 게스트 입장에서
그것은 전원이 끊긴 것이고, **셸이 나갈 때 하는 일이 하나도 안 일어난다.**

실측 34가 그 경계를 정확히 그었다.

| 셸이 어떻게 끝나나 | `HISTFILE`이 써지나 |
|---|---|
| `exit` | **써진다** |
| SIGTERM | **써진다** |
| SIGHUP | **써진다** |
| SIGKILL(=전원) | **안 써진다** |

**이것은 나쁜 소식이 아니라 좋은 소식 반이다.** 실기에서 전원 버튼을 누르면
PID 1이 자식에게 SIGTERM을 보내므로(`power.zig`) **히스토리는 저장된다.**
저장이 안 되는 것은 "코드를 뽑는 것"뿐이고, **게이트가 하는 일이 정확히
그것이다.**

그래서 7차 부팅이 `fc -W` 한 줄을 더 친다. **그것은 편법이 아니라 게이트가
못 하는 것(정상 종료)을 대신하는 한 줄이다** — 그리고 그 한 줄이 없었으면
8차가 왜 빨간지 영영 안 갈렸을 것이다.

### 2. zoxide의 DB는 **`cd` 그 순간에** 디스크로 간다

히스토리와 달리 `db.zo`는 셸이 나갈 때가 아니라 `zoxide add`마다 쓰인다.
실측 42(예행)에서 `kill -9`로 끝낸 세션의 DB가 그대로 남았다. `/config`가
`MS_SYNCHRONOUS`로 붙어 있어(`main.zig:93`) 쓴 시점에 이미 디스크에 있다.

**그래서 판정 둘이 서로 다른 실패를 본다** — `z`는 "자리를 옮겼나"를,
`history`는 "나갈 때 쓰는 것을 누가 대신 썼나"를 본다.

### 3. env 넷은 **아무것도 안 찍는다**

실측 39c가 셸 셋을 `env -i` 위에서 전/후로 쟀고 **바이트가 같았다**.

| 셸 | 전 | 후 |
|---|---|---|
| zsh | 371 | **371** |
| bash | 127 | **127** |
| fish | 863 | **863** |

위험 1(씨앗이 한 글자라도 찍으면 다섯 체인의 화면 좌표가 밀린다)이 이번에도
같은 자리에 있고, 이 표가 착수 전 근거다. **그래도 게이트의 첫 회차가 진짜
검사다.**

---

## Task 1: 컨테이너에서 먼저 잰다 (완료 — 실측 34~42)

**Files:** 없음(측정만)

**측정 환경:** devcontainer가 arm64라 arm64 바이너리로 쟀다 — zsh 5.9 ·
fish 4.0.2 · zoxide 0.9.7 · fzf 0.60, 게스트의 amd64와 같은 Debian trixie
스냅샷이다. **pty를 줬다**(`script -qfc` + fifo) — 게스트의 셸은 PTY 위에
살고, 히스토리를 언제 쓰는지는 그 차이에 갈릴 수 있는 종류의 질문이다.

```bash
docker run -d --name tars-measure tars-devcontainer sleep 3600
docker exec tars-measure bash -c 'apt-get update -qq && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zsh fish zoxide fzf'
```

- [x] **Step 1: 실측 34 — 셸이 어떻게 끝나야 `HISTFILE`이 써지나**

```
exit      file=yes  content=[echo marker_exit/exit/]
TERM      file=yes  content=[echo marker_TERM/]
HUP       file=yes  content=[echo marker_HUP/]
KILL      file=NO   content=[-]
```

**design 결정 3은 "남는다"를 적으면서 게이트가 전원을 뽑는다는 것을 안
봤다.** 위의 "지배하는 사실 1"이 이 표에서 나왔다.

- [x] **Step 2: 실측 35 — `fc -W`가 쓰고, `wc -l`은 공백 없이 숫자를 찍는다**

```
$ (7차와 같은 순서로 치고) fc -W ; wc -l $HISTFILE
6 /tmp/rehearse/config/zsh_history      ← 행의 첫머리가 숫자다
```

파일은 평문 한 줄에 명령 하나다(`EXTENDED_HISTORY`가 꺼져 있다 — 실측 9와
같다). **GNU `wc`는 파일이 하나면 앞에 공백을 안 넣는다** — 그래서 게이트가
`\| [0-9]` 하나로 이 출력을 타이핑한 줄과 가를 수 있다.

- [x] **Step 3: 실측 36 — 새 셸이 그 파일을 읽고 `history`가 찍는 모양**

```
    1  cd /usr/bin/../share/terminfo/x
    2  cd /
    3  whence -w fzf-history-widget
    4  fc -W
```

**네 칸 들여쓰고 번호, 공백 둘, 명령이다.** design 결정 8이 그랬듯 이 결정도
명령만 적혀 있었고 출력은 안 적혀 있었다.

- [x] **Step 4: 실측 37 — bash는 `HISTSIZE`만으로 파일까지 자른다**

```
HISTSIZE=5로 열두 개를 치고 나간 뒤:  파일 5줄  [echo cmd_9/…/exit/]
```

`HISTFILESIZE`를 안 줘도 잘린다. **결정 4의 5,000줄 상한이 bash에서도 선다**는
뜻이고, env 항목을 하나 안 늘려도 된다.

- [x] **Step 5: 실측 38 — `XDG_DATA_HOME` 하나가 DB를 옮긴다**

```
XDG_DATA_HOME=…/config/xdg zoxide add /usr/bin/../share/terminfo/x
  → …/config/xdg/zoxide/db.zo     ← 없는 경로 둘을 스스로 만들었다
  → 홈에는 아무것도 없다
  → ls $XDG_DATA_HOME/zoxide  →  db.zo
```

실측 3·4의 재확인이고, **`ls`의 출력이 `db.zo` 한 단어라는 것**이 8차 부팅의
둘째 판정이 된다.

- [x] **Step 6: 실측 39 — env 넷의 비용은 0바이트다**

위 "지배하는 사실 3"의 표. **`env -i` 위에서 재야 한다** — 처음에는 앞
측정의 `export`가 새서 fish가 남의 히스토리를 읽는 것을 보고 한 번 놀랐다
(그것이 실측 41이 됐다).

- [x] **Step 7: 실측 40 — fish 히스토리는 `XDG_DATA_HOME` 아래로 자동으로 간다**

```
…/xdg/fish/fish_history
- cmd: echo marker
  when: 1789172042
```

실측 11이 맞았다. **fish에게는 env를 하나도 안 준다** — `XDG_DATA_HOME`
하나가 히스토리까지 옮긴다.

- [x] **Step 8: 실측 41 — fish는 첫 대화형 기동에 `$HISTFILE`을 가져온다**

```
HISTFILE=…/borrowed_bash_history 를 주고 fish를 처음 띄우면
  fish_history:  - cmd: echo bash_line_one
                 - cmd: echo bash_line_two
```

**우연히 발견한 것이고, 우리 설계에서는 안 일어난다** — `histEntries()`가
fish에 빈 목록을 주므로 `shell=fish`인 기계에는 `HISTFILE`이 아예 없다.
**`shell`을 bash에서 fish로 바꾼 사람에게는 이것이 기능이 된다**(쳤던 명령이
따라온다). 문서에 적어 두고 코드로는 아무것도 안 한다.

- [x] **Step 9: 실측 42 — 7차→8차를 컨테이너에서 통째로 예행했다**

씨앗과 같은 훅이 든 `.zshrc`를 놓고, 7차를 `kill -9`로 끝내고(전원), 새
세션을 띄워 **`cd`를 한 번도 안 치고** 판정 셋을 확인했다.

```
=== 7차 (전원을 뽑는다)
/usr/share/terminfo/x                     ← z가 돈다(M1의 판정)
fzf-history-widget: function              ← 위젯이 있다(M1의 판정)
6 /tmp/rehearse/config/zsh_history        ← fc -W가 썼다(M2의 새 판정)

=== 디스크에 남은 것
…/config/xdg/zoxide/db.zo
…/config/zsh_history

=== 8차 — 아무도 cd를 안 친다
/usr/share/terminfo/x                     ← z가 이전 부팅의 자리로 갔다
db.zo                                     ← 그 기억이 설정 디스크에 있다
    5  whence -w fzf-history-widget       ← 7차만 친 명령이 목록에 있다
```

**이 세 줄이 Task 7이 쓸 판정 셋 그대로다.** 게이트를 짜기 전에 판정이 실제로
나오는 것을 봤다는 뜻이고, M0·M1이 각각 한 번씩 "판정 글자가 안 나온다"로
되돌아간 자리를 이번에는 앞에서 막았다.

---

## Task 2: `config.zig` — `Shell.histEntries()`

**Files:**
- Modify: `init/src/config.zig` (`Shell` enum 안, `rcPath()`와 `hookLines()`
  사이)

- [ ] **Step 1: 상수 둘과 함수 하나를 넣는다**

`rcPath()`의 닫는 `}` 바로 뒤, `HOOKS_FISH` 주석 앞에 **넣을 것**:

```zig
    /// 이 기계가 기억하는 것 둘 중 **쳤던 명령**의 자리(SM design 결정 3).
    ///
    /// **셸마다 다른 파일인 이유는 형식이다** — zsh는 `: <ts>:<dur>;<cmd>`,
    /// bash는 평문이라 한 파일에 섞으면 서로의 것을 못 읽는다. init이
    /// `cfg.shell`을 이미 알고 있으므로 그 자리에서 정한다.
    ///
    /// **fish는 빈 목록이다.** fish의 히스토리는 `XDG_DATA_HOME` 아래로 통째로
    /// 따라오고(실측 11·40), 줄 수를 정하는 변수가 아예 없다(비목표 4).
    ///
    /// **씨앗 rc에는 히스토리 줄이 한 줄도 없다**(결정 3). 실측 9·10이
    /// 근거다 — 셋 다 env에서 먹는다. 그래서 이 milestone은
    /// `rcSeed()`도 `expectQuietSeed`도 한 글자 안 건드린다.
    const HIST_BASH = [_][:0]const u8{
        "HISTFILE=/config/bash_history",
        // bash는 `HISTFILESIZE`를 안 줘도 이 수로 **파일까지** 자른다
        // (실측 37). 5,000줄 = 약 250KB = 16MiB 디스크의 1.5%(결정 4).
        "HISTSIZE=5000",
    };
    const HIST_ZSH = [_][:0]const u8{
        "HISTFILE=/config/zsh_history",
        "HISTSIZE=5000",
        // **zsh는 이것이 없으면 한 줄도 안 쓴다**(실측 9). `HISTFILE`만 주고
        // 끝내는 것이 이 자리에서 가장 흔한 실수이고, 증상은 "히스토리가
        // 그냥 안 남는다"라 원인에서 멀다.
        "SAVEHIST=5000",
    };

    /// 이 셸에게 줄 히스토리 env. `environ.zig`가 커널 블록 뒤에 그대로 붙인다.
    pub fn histEntries(self: Shell) []const [:0]const u8 {
        return switch (self) {
            .fish => &[_][:0]const u8{},
            .bash => &HIST_BASH,
            .zsh => &HIST_ZSH,
        };
    }
```

- [ ] **Step 2: 컴파일한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build'
```

기대: 조용히 끝난다(경고 없음).

---

## Task 3: `environ.zig` — `withPath`가 `withTarsEnv`가 된다

**Files:**
- Modify: `init/src/environ.zig`

- [ ] **Step 1: 상수 둘을 더한다**

`PATH_ENTRY` 선언 바로 뒤에 **넣을 것**:

```zig
/// `XDG_DATA_HOME`이 가리키는 자리(SM design 결정 2). **이 한 경로가 둘을
/// 옮긴다** — `zoxide`의 `db.zo`와 fish의 `fish_history`(실측 3·11·38·40).
///
/// **`_ZO_DATA_DIR`을 안 쓴 이유**는 fish에 경로 변수가 없기 때문이다.
/// `XDG_DATA_HOME`이 유일한 지렛대이고, 그것을 쓰면 zoxide가 공짜로 따라온다.
///
/// **링크가 아니라 환경 변수인 이유**(SC 결정 1과 갈린 자리)는 실측 4다 —
/// 설정 디스크가 없는 여섯 체인에서 `/config/…`를 가리키는 링크는 댕글링이고,
/// 그때 zoxide는 `cd`마다 에러 두 줄을 찍는다. 없는 경로를 env로 주면
/// **`mkdir -p`하고 조용히 성공한다.**
///
/// 두 줄이 한 글자를 공유하는 것에 뜻이 있다 — `main.zig`가 만드는
/// 디렉터리와 셸이 받는 값이 어긋나면 증상은 "기억이 가끔 안 남는다"이고
/// 원인에서 아주 멀다. **여기서는 `++`로 컴파일러가 잇는다**(훅 두 벌과
/// 반대다 — 저쪽은 검사가 tautology가 되므로 일부러 안 이었다).
pub const XDG_DATA_DIR = "/config/xdg";
pub const XDG_ENTRY: [:0]const u8 = "XDG_DATA_HOME=" ++ XDG_DATA_DIR;
```

- [ ] **Step 2: `withPath`를 통째로 `withTarsEnv`로 바꾼다**

**지울 것** — `withPath`의 머리 주석부터 함수 끝까지(`init/src/environ.zig:37`
~ `:56`).

**넣을 것**:

```zig
/// 커널이 준 블록을 buf에 복사하고 **우리 것을 뒤에 붙인 뒤** buf를 돌려준다.
///
/// 붙이는 것이 셋이다.
///
///   PATH             자식마다 갈릴 이유가 없다(UT-M0)
///   XDG_DATA_HOME    같다. 배운 것 둘이 여기로 간다(SM-M2 결정 2)
///   hist             **셸마다 갈린다** — `config.Shell.histEntries()`가 준다
///
/// **셋째가 인자인 것이 이 함수의 전부다.** 이 파일은 `config.zig`를 모른 채
/// 있어야 하고(그래야 호스트 검사가 순수 계산으로 남는다), 그래서 "어느 셸인가"
/// 대신 "무엇을 붙일까"를 받는다. 부르는 쪽은 `main.zig` 하나다.
///
/// **자리가 모자라면 커널 블록을 그대로 돌려준다.** PATH가 없는 게스트는
/// 불편하지만 살아 있고, 버퍼를 넘겨 쓴 PID 1은 기계를 아예 못 켠다.
/// HD 결정 6("못 찾아도 부팅을 막지 않는다")과 같은 종류의 선택이다.
pub fn withTarsEnv(
    kernel: [*:null]const ?[*:0]const u8,
    buf: *Block,
    hist: []const [:0]const u8,
) [*:null]const ?[*:0]const u8 {
    var n: usize = 0;
    while (kernel[n] != null) n += 1;

    // 우리가 더하는 수. 셸마다 2(fish) · 4(bash) · 5(zsh)다.
    const added = 2 + hist.len;
    // 마지막으로 쓰는 자리가 buf[n + added](닫는 null)이고, 그 자리가 배열의
    // sentinel 자리(MAX_ENTRIES)를 넘으면 안 된다.
    if (n + added >= MAX_ENTRIES) return kernel;

    var i: usize = 0;
    while (i < n) : (i += 1) buf[i] = kernel[i];
    buf[n] = PATH_ENTRY.ptr;
    buf[n + 1] = XDG_ENTRY.ptr;
    for (hist, 0..) |entry, j| buf[n + 2 + j] = entry.ptr;
    buf[n + added] = null;
    return buf;
}
```

- [ ] **Step 3: 컴파일은 아직 깨진다**

`main.zig`가 아직 `withPath`를 부르므로 Task 5까지는 `zig build`가 빨갛다.
**정상이다** — 이름을 바꾼 것이 부르는 자리를 반드시 지나가게 만드는 것이
이 편집의 값이다.

---

## Task 4: 호스트 검사 둘

**Files:**
- Modify: `init/src/environ_test.zig`
- Modify: `init/src/config_test.zig`

- [ ] **Step 1: `environ_test.zig`를 새 계약으로 고친다**

머리의 `const environ = @import("environ.zig");` 아래에 **넣을 것**:

```zig
const config = @import("config.zig");
```

그리고 `pub fn main()` 안의 블록 1~3을 **지우고** 아래로 **바꾼다**(블록 4는
그대로 두고 그 앞에 온다).

```zig
    // ── 1. 정상 경로(zsh): 커널의 둘 뒤에 우리 것 다섯이 순서대로 붙는다 ──
    //
    // 이것이 이 파일의 심장이다. **순서까지 보는 이유**는 덮어쓰는 구현
    // (buf[0]에 PATH를 넣고 나머지를 미는 것)도 개수 검사만으로는 통과하기
    // 때문이다.
    {
        const kernel = kernelBlock(&.{ "HOME=/", "TERM=linux" });
        const got = environ.withTarsEnv(kernel, &buf, config.Shell.zsh.histEntries());

        if (count(got) != 7) {
            std.debug.print("FAIL: want 7 entries for zsh, got {d}\n", .{count(got)});
            return error.WrongCount;
        }
        if (!entryIs(got, 0, "HOME=/") or !entryIs(got, 1, "TERM=linux")) {
            std.debug.print("FAIL: the kernel's own entries did not survive in order\n", .{});
            return error.LostKernelEntries;
        }
        if (!entryIs(got, 2, "PATH=/usr/bin:/bin") or
            !entryIs(got, 3, "XDG_DATA_HOME=/config/xdg"))
        {
            std.debug.print("FAIL: PATH and XDG_DATA_HOME are not the first two we add\n", .{});
            return error.NoPath;
        }
        // **히스토리 셋이 그 뒤에 순서대로 온다.** zsh만 SAVEHIST를 받고,
        // 그것이 없으면 zsh는 HISTFILE이 있어도 한 줄도 안 쓴다(실측 9).
        if (!entryIs(got, 4, "HISTFILE=/config/zsh_history") or
            !entryIs(got, 5, "HISTSIZE=5000") or
            !entryIs(got, 6, "SAVEHIST=5000"))
        {
            std.debug.print("FAIL: the zsh history entries are not appended in order\n", .{});
            return error.NoHistory;
        }
    }

    // ── 2. fish: 히스토리 env가 **하나도 없다** ─────────────────────────
    //
    // 대조군이자 결정 3의 절반이다. fish의 히스토리는 XDG_DATA_HOME 아래로
    // 통째로 따라오므로(실측 11·40) 줄 하나도 필요 없고, 줄 수를 정하는
    // 변수도 없다(비목표 4).
    {
        const kernel = kernelBlock(&.{ "HOME=/", "TERM=linux" });
        const got = environ.withTarsEnv(kernel, &buf, config.Shell.fish.histEntries());
        if (count(got) != 4 or !entryIs(got, 3, "XDG_DATA_HOME=/config/xdg")) {
            std.debug.print("FAIL: fish should get exactly PATH and XDG_DATA_HOME, got {d} entries\n", .{count(got)});
            return error.FishBlockWrong;
        }
    }

    // ── 3. 대조군: 커널이 아무것도 안 줬다 ─────────────────────────────
    //
    // 커널은 늘 둘을 주지만, 그 사실에 기대는 구현(예: 무조건 buf[2]에 쓰는
    // 것)을 여기서 잡는다.
    {
        const kernel = kernelBlock(&.{});
        const got = environ.withTarsEnv(kernel, &buf, config.Shell.fish.histEntries());
        if (count(got) != 2 or !entryIs(got, 0, "PATH=/usr/bin:/bin")) {
            std.debug.print("FAIL: an empty kernel block did not yield exactly our two\n", .{});
            return error.EmptyBlockWrong;
        }
    }

    // ── 4. 넘침 — **경계 양쪽을 본다** ─────────────────────────────────
    //
    // **PATH가 없는 것이 부팅이 안 되는 것보다 낫다.** 버퍼를 넘겨 쓰면 PID 1이
    // 스택을 밟고 기계가 아예 안 켜진다 — 증상이 원인에서 가장 먼 종류다.
    //
    // **경계가 M2에서 움직였다**(하나 붙이던 것이 다섯까지 붙는다). 그래서
    // "넘치면 통과시킨다"만 보지 않고 **바로 아래는 여전히 붙는다**도 본다 —
    // 한쪽만 보면 `return kernel`을 맨 위로 올린 구현도 초록이다.
    {
        var many: [environ.MAX_ENTRIES]([:0]const u8) = undefined;
        for (&many) |*m| m.* = "X=1";
        const hist = config.Shell.zsh.histEntries(); // 셋 → added = 5

        // n + 5 == MAX_ENTRIES → 닫는 null 자리가 없다. 그대로 돌려준다.
        const over = kernelBlock(many[0 .. environ.MAX_ENTRIES - 5]);
        if (environ.withTarsEnv(over, &buf, hist) != over) {
            std.debug.print("FAIL: an oversized block should have been passed through untouched\n", .{});
            return error.OverflowNotPassedThrough;
        }

        // 한 칸 적으면 딱 들어간다.
        const fits = kernelBlock(many[0 .. environ.MAX_ENTRIES - 6]);
        const got = environ.withTarsEnv(fits, &buf, hist);
        if (got == fits or count(got) != environ.MAX_ENTRIES - 1) {
            std.debug.print("FAIL: a block that fits was passed through instead of extended\n", .{});
            return error.FitNotExtended;
        }
    }
```

블록 4(기존 `PATH 값이 design 결정 1과 같다`) 뒤에 **넣을 것**:

```zig
    // ── 6. XDG 항목의 값과 경로가 한 글자를 공유한다 ────────────────────
    //
    // `main.zig`가 만드는 디렉터리와 셸이 받는 값이 어긋나면 증상은 "기억이
    // 가끔 안 남는다"이고 원인에서 아주 멀다. `++`가 컴파일 타임에 잇고,
    // 이 두 줄은 **그 이음매가 실제로 우리가 뜻한 글자인지**를 본다.
    if (!std.mem.eql(u8, environ.XDG_DATA_DIR, "/config/xdg")) {
        std.debug.print("FAIL: XDG_DATA_DIR is '{s}'\n", .{environ.XDG_DATA_DIR});
        return error.WrongXdgDir;
    }
    if (!std.mem.eql(u8, environ.XDG_ENTRY, "XDG_DATA_HOME=/config/xdg")) {
        std.debug.print("FAIL: XDG_ENTRY is '{s}'\n", .{environ.XDG_ENTRY});
        return error.WrongXdgEntry;
    }
```

마지막 줄의 문구도 넓힌다 — **지울 것**:

```zig
    std.debug.print("environ_test: PATH is appended to the kernel's block ({d} slots)\n", .{environ.MAX_ENTRIES});
```

**넣을 것**:

```zig
    std.debug.print("environ_test: PATH, XDG_DATA_HOME and the shell's history env are appended to the kernel's block ({d} slots)\n", .{environ.MAX_ENTRIES});
```

- [ ] **Step 2: `config_test.zig`에 히스토리 검사를 더한다**

`expectHooksCoverTheTools`의 닫는 `}` 뒤에 **넣을 것**:

```zig
/// 히스토리 env가 셸의 성질과 맞는가(SM-M2 design 결정 3).
///
/// **`expectQuietSeed`와 짝이 아니다** — 이 milestone은 씨앗을 안 건드린다.
/// 히스토리는 rc가 아니라 env로 세우고(실측 9·10·11), 그 결정이 옳은지는
/// `config/check.sh`의 8차 부팅이 본다. 여기가 보는 것은 **우리가 셸마다
/// 무엇을 주려고 했는가**까지다.
///
/// 보는 것 셋:
///   1. 개수가 셸의 성질과 맞다 — fish 0 · bash 2 · **zsh 3**
///   2. 모든 항목이 `NAME=VALUE`이고 이름이 셋 중 하나다
///   3. **`SAVEHIST`는 zsh만 받는다** — 실측 9를 코드 모양으로 못 박는 줄이다
fn expectHistEntries(sh: config.Shell) !void {
    const want_len: usize = switch (sh) {
        .fish => 0,
        .bash => 2,
        .zsh => 3,
    };
    const entries = sh.histEntries();
    if (entries.len != want_len) {
        std.debug.print("FAIL: the {s} shell carries {d} history env entries, want {d}\n", .{
            @tagName(sh), entries.len, want_len,
        });
        return error.BadHistEnv;
    }

    var saw_savehist = false;
    for (entries) |e| {
        const eq = std.mem.indexOfScalar(u8, e, '=') orelse {
            std.debug.print("FAIL: history env \"{s}\" is not NAME=VALUE\n", .{e});
            return error.BadHistEnv;
        };
        const name = e[0..eq];
        if (std.mem.eql(u8, name, "SAVEHIST")) saw_savehist = true;
        if (!std.mem.eql(u8, name, "HISTFILE") and
            !std.mem.eql(u8, name, "HISTSIZE") and
            !std.mem.eql(u8, name, "SAVEHIST"))
        {
            std.debug.print("FAIL: the {s} shell wants an unexpected env {s}\n", .{
                @tagName(sh), name,
            });
            return error.BadHistEnv;
        }
    }
    if ((sh == .zsh) != saw_savehist) {
        std.debug.print("FAIL: SAVEHIST belongs to zsh alone; the {s} shell has it: {}\n", .{
            @tagName(sh), saw_savehist,
        });
        return error.BadHistEnv;
    }
}
```

`main()`의 `expectHooksCoverTheTools` 줄 바로 뒤에 **넣을 것**:

```zig
    // ── SM-M2: 히스토리 env ─────────────────────────────────────────────
    for (std.enums.values(config.Shell)) |sh| try expectHistEntries(sh);
    // **bash와 zsh가 같은 파일을 보면 안 된다.** 형식이 다르다 — zsh는
    // `: <ts>:<dur>;<cmd>`, bash는 평문이라 섞이면 서로의 것을 못 읽는다.
    // 위 함수는 항목을 하나씩만 보므로 이 한 줄이 따로 필요하다.
    if (std.mem.eql(u8, config.Shell.bash.histEntries()[0], config.Shell.zsh.histEntries()[0])) {
        std.debug.print("FAIL: bash and zsh point HISTFILE at the same file\n", .{});
        return error.BadHistEnv;
    }
```

- [ ] **Step 3: 호스트 검사를 돌린다** (Task 5 뒤에 함께 돈다 — 지금은
      `main.zig`가 아직 안 고쳐져 빌드가 빨갛다)

---

## Task 5: `main.zig` — env 블록이 **셸이 정해진 뒤로** 내려간다

**Files:**
- Modify: `init/src/main.zig`

- [ ] **Step 1: `mountDevpts` 옆에 `/config/xdg`를 만드는 함수를 넣는다**

`mountDevpts()`의 닫는 `}` 뒤에 **넣을 것**:

```zig
/// `XDG_DATA_HOME`이 가리키는 디렉터리를 만든다(SM design 결정 9).
/// **설정 디스크가 붙었을 때만** 부른다 — 안 붙은 기계에서는 `/config`가
/// tmpfs의 빈 디렉터리이고, 거기에 도구가 자기 자리를 만드는 것이 정상
/// 경로다(실측 4).
///
/// **도구 둘이 없는 경로를 스스로 만든다는 것을 알고도 만드는 이유**는
/// 실패의 자리를 정하기 위해서다. 디스크가 붙었는데 여기에 못 쓰면 그것은
/// 이상한 일이고, 그때 로그 한 줄이 남는 편이 "기억이 안 남는다"를 나중에
/// 셸에서 조사하는 것보다 낫다. `mountDevpts`가 `/dev/pts`에 대해 하는 것과
/// 같은 모양이다.
fn makeXdgDir() void {
    const rc = linux.mkdir(environ.XDG_DATA_DIR, 0o755);
    if (failed(rc)) |e| {
        // 이미 있다 = 두 번째 부팅부터의 정상 경로다. 조용히 둔다.
        if (e == .EXIST) return;
        std.debug.print("tars-init: could not create {s} (errno {d})\n", .{
            environ.XDG_DATA_DIR, @intFromEnum(e),
        });
    }
}
```

- [ ] **Step 2: `main()` 머리의 env 블록을 지운다**

**지울 것** — `main.zig:467`의 `pub fn main(...) {` 바로 아래, 주석 포함
`var env_buf` 선언부터 `tars-init: env unchanged` 블록의 닫는 `}`까지
(`:468` ~ `:491`). **`std.debug.print("tars-init: starting as PID 1\n", .{});`
한 줄은 남기고 맨 위로 올린다.**

즉 `main()`의 시작이 이렇게 된다.

```zig
pub fn main(init: std.process.Init.Minimal) void {
    std.debug.print("tars-init: starting as PID 1\n", .{});

    // mount보다 먼저 켠다. 핸들러가 하는 일은 플래그를 세우는 것뿐이라 이
```

- [ ] **Step 3: `seedRcFiles` 옆에서 `/config/xdg`를 만든다**

**지울 것**(`main.zig:540`):

```zig
    if (storage_mounted) config.seedRcFiles();
```

**넣을 것**:

```zig
    if (storage_mounted) {
        config.seedRcFiles();
        // SM-M2 결정 9. **씨앗 rc와 같은 조건이다** — 디스크가 붙은 기계에만
        // 우리가 만든다. 값(`XDG_DATA_HOME`)은 조건 없이 주고 디렉터리만
        // 여기서 만드는 것이 비대칭으로 보이지만, 그 비대칭이 결정 9 그
        // 자체다: **에러가 안 나는 것이 화면 좌표를 지키는 것이다.**
        makeXdgDir();
    }
```

- [ ] **Step 4: `resolveShell` 뒤에서 env 블록을 짓는다**

`const shell_path = shell.path();` 바로 뒤에 **넣을 것**:

```zig
    // ── env 블록은 여기서 짓는다(SM-M2) ──────────────────────────────────
    //
    // **UT-M0에서는 `main()`의 첫 줄이었다.** 내려온 이유는 `HISTFILE`이
    // 셸마다 다른 파일이어야 하기 때문이다(결정 3) — 그 값을 알려면 설정을
    // 읽고 `resolveShell`이 끝나 있어야 한다.
    //
    // **`cfg.shell`이 아니라 `shell`을 보는 것이 중요하다.** `tars.conf`가
    // zsh라고 적어도 initrd에 zsh가 없으면 실제로 도는 것은 fish이고, 그때
    // `HISTFILE=/config/zsh_history`를 주면 **아무도 안 읽는 파일 이름을 env에
    // 심는 것**이 된다. 폴백 뒤의 값을 쓰면 로그의 `config shell=`과 여기가
    // 언제나 같은 셸을 말한다.
    //
    // **이 버퍼가 `main()`의 스택에 있는 것이 중요하다.** `supervise()`가 영영
    // 반환하지 않으므로 프로세스 수명 내내 유효하다 — `keyboard_path`·argv와
    // 같은 근거다. 자식은 fork 뒤 execve로 이 포인터를 읽는다.
    var env_buf: environ.Block = undefined;
    const envp = environ.withTarsEnv(
        init.environ.block.slice.ptr,
        &env_buf,
        shell.histEntries(),
    );

    // UT-M0: 게이트가 "블록을 제대로 지었는가"를 보는 자리. 자식 둘이 같은
    // 블록을 받는다는 것은 `supervise()`가 `start(c, envp)`를 한 루프에서
    // 부르는 코드 구조가 보장한다.
    //
    // withTarsEnv가 자리 부족으로 폴백했으면 이 줄들이 안 나온다. 그 침묵이
    // 곧 판정이다.
    //
    // **`tools/check.sh:233`이 `tars-init: env PATH=/usr/bin:/bin`을 그대로
    // grep한다** — 그래서 PATH가 이 줄의 맨 앞에 남아 있어야 한다.
    if (envp != init.environ.block.slice.ptr) {
        std.debug.print("tars-init: env {s} {s}\n", .{
            environ.PATH_ENTRY, environ.XDG_ENTRY,
        });
        // 셸마다 갈리는 것은 줄을 따로 낸다. `shell=fish`면 한 줄도 안 나오고,
        // **그 침묵이 결정 3의 절반**(fish는 XDG 하나로 끝난다)을 로그에서
        // 읽는 법이다.
        for (shell.histEntries()) |entry| {
            std.debug.print("tars-init: env {s}\n", .{entry});
        }
    } else {
        std.debug.print("tars-init: env unchanged (no room for PATH)\n", .{});
    }
```

- [ ] **Step 5: 빌드와 호스트 검사**

```bash
rm -rf init/.zig-cache init/zig-out
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build && zig build test'
```

기대: `config_test`의 `PASS` · `environ_test`의 새 문구가 나온다.

---

## Task 6: 호스트 음성 확인 셋 — **캐시를 비우고 한 번씩**

**Files:** 없음(되돌렸다 복구)

**절차는 매번 같다.** 고치고 → `rm -rf init/.zig-cache init/zig-out` →
`zig build test` 한 번 → 빨간 것을 확인 → 되돌린다.
(`docs/decisions/project_zig_out_staleness.md` — 안 지우면 5회 중 1회가
거짓 초록이고 어느 회차인지 알려 주는 신호가 없다.)

- [ ] **되돌림 A: `HIST_ZSH`에서 `SAVEHIST` 줄을 지운다**

기대: `FAIL: the zsh shell carries 2 history env entries, want 3`.
**실측 9를 지키는 그물이 도는지 보는 것이다.**

- [ ] **되돌림 B: `HIST_BASH`의 `HISTFILE`을 zsh와 같은 파일로 바꾼다**

기대: `FAIL: bash and zsh point HISTFILE at the same file`.
(개수 검사만으로는 안 잡힌다 — 그래서 그 한 줄이 따로 있다.)

- [ ] **되돌림 C: `withTarsEnv`에서 `buf[n + 1] = XDG_ENTRY.ptr;`를 지우고
      `added`를 `1 + hist.len`으로 바꾼다**

기대: `FAIL: PATH and XDG_DATA_HOME are not the first two we add`.
**이 되돌림이 "블록을 제대로 지었는가"의 유일한 호스트 그물이다.**

---

## Task 7: `config/check.sh` — 7차가 한 줄 더 치고, **8차가 선다**

**Files:**
- Modify: `config/check.sh`
- Modify: `tools/check.sh` (주석 한 자리)

- [ ] **Step 1: 머리글 `/7` → `/8` — 일곱 자리**

`=== boot 1/7:` … `=== boot 7/7:` 일곱 줄을 전부 `/8`로 바꾼다.

- [ ] **Step 2: 키 배열 넷을 더한다**

`HOOK_WIDGET_KEYS` 선언 뒤에 **넣을 것**:

```bash
# ── SM-M2 ───────────────────────────────────────────────────────────────
#
# **게이트는 전원을 뽑는다.** boot_once가 마커를 보면 `kill "$QEMU_PID"`로
# 기계를 끝내므로 셸이 나갈 때 하는 일이 하나도 안 일어난다. zsh는
# SIGTERM·SIGHUP을 받으면 HISTFILE을 쓰지만(실측 34) QEMU가 죽으면 그 신호도
# 안 온다 — **실기의 전원 버튼에서는 저장되고, 여기서만 안 된다.**
#
# 그래서 7차가 직접 쓴다. `fc -W`는 히스토리 목록을 그 자리에서 파일에 쓴다.
#
# ⚠ **이 저장소가 대문자를 처음 친다.** `sendkey`에 대문자 키 이름은 없지만
# `shift-w`는 있고, 게스트의 keymap이 `.{ 'w', 'W' }`를 갖고 있다
# (`terminal/src/input.zig:47`). 안 먹으면 화면에 `fc: bad option`이 뜨고 바로
# 아래 되읽기가 빨개진다 — **실패가 그 자리에서 보인다.**
HIST_WRITE_KEYS=(f c spc minus shift-w ret)
# wc -l /config/zsh_history — 되읽기. **판정 글자는 wc가 만드는 숫자다.**
# GNU wc는 파일이 하나면 앞에 공백을 안 넣으므로(실측 35) 행의 첫머리가
# 숫자인 줄은 이 출력뿐이고, 방금 타이핑한 줄은 프롬프트로 시작한다.
# 밑줄은 shift-minus다(OFF_KEYS가 쓰고 있는 그 키다).
HIST_COUNT_KEYS=(w c spc minus l spc slash c o n f i g slash
                 z s h shift-minus h i s t o r y ret)

# ── 8차 부팅이 치는 셋 ──────────────────────────────────────────────────
#
# **`z`와 `pwd`는 7차의 것을 그대로 다시 쓴다**(HOOK_Z_KEYS · HOOK_PWD_KEYS).
# 같은 두 명령이 두 부팅에서 다른 것을 증명한다 — 7차에서는 "훅이 걸렸다"를,
# 8차에서는 **"그 기억이 전원을 넘었다"**를. **8차는 `cd`를 한 번도 안 친다.**
#
# ls /config/xdg/zoxide — 그 기억이 **tmpfs의 홈이 아니라 설정 디스크에**
# 있다는 것을 보는 한 줄. 판정 글자 `db.zo`는 타이핑한 줄에 없다(실측 38).
XDG_LS_KEYS=(l s spc slash c o n f i g slash x d g slash z o x i d e ret)
# history — zsh는 인자 없이 부르면 최근 16개를 번호와 함께 찍는다(실측 36).
HISTORY_KEYS=(h i s t o r y ret)
```

- [ ] **Step 3: 7차의 훅에 `fc -W`와 되읽기를 붙인다**

`probe_shell_hooks`의 마지막 `echo "boot 7: the fzf integration …"` **앞**에
**넣을 것**(위젯 판정의 `if` 블록 뒤, `return 0` 앞):

```bash
  # ── SM-M2: 8차가 읽을 것을 여기서 디스크에 쓴다 ──────────────────────
  #
  # **게이트가 전원을 뽑기 때문에 필요한 두 줄이다**(실측 34). 실기에서
  # 전원 버튼을 누르면 PID 1의 SIGTERM이 셸에게 가고 zsh가 스스로 쓴다 —
  # 여기서만 그 신호가 없다.
  #
  # `fc -W`는 아무것도 안 찍으므로 되읽기가 따로 필요하다. 그 되읽기가
  # 없으면 이 줄이 실패했을 때 **8차가 빨간 이유가 "안 썼다"인지 "안
  # 읽었다"인지 안 갈린다** — M1이 부팅을 둘로 나눈 것과 같은 이유다.
  type_keys "${HIST_WRITE_KEYS[@]}"
  type_keys "${HIST_COUNT_KEYS[@]}"
  ok=0
  if wait_for_screen '\| [1-9][0-9]* /config/zsh_history'; then ok=1; fi

  exec 3<&-
  exec 3>&-

  if [ "$ok" != "1" ]; then
    echo "FAIL(boot 7): 'fc -W' left no history file for the eighth boot to read"
    echo "  둘 중 하나다 — HISTFILE/SAVEHIST가 셸에 안 갔거나(init의 env),"
    echo "  대문자 W가 게스트에 안 닿았다. 아래 마지막 화면에 'bad option'이"
    echo "  있으면 후자다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 7: the shell wrote its history to the config disk before the power was cut"
```

그리고 위젯 판정 블록의 `exec 3<&-` / `exec 3>&-` 두 줄은 **지운다** —
monitor를 여기서 닫으면 위의 타이핑이 못 간다.

- [ ] **Step 4: 8차의 훅 함수를 더한다**

`probe_shell_hooks`의 닫는 `}` 뒤, `boot_once` 앞에 **넣을 것**:

```bash
# 8차 부팅의 훅. **이 milestone이 증명하려는 것 전부가 여기 있다**(SM-M2).
#
# 이 부팅이 7차와 다른 점은 **아무것도 안 심는다**는 것이다. 디스크는 그대로고
# cmdline도 기본값이다 — 달라진 것은 **기계가 한 번 꺼졌다 켜졌다**는 것뿐이고,
# 그것이 이 서브프로젝트의 제목이다.
#
# 판정 셋이 서로 다른 실패를 본다.
#
#   1. z가 돈다        → zoxide DB가 /config/xdg에 남았다(쓰는 시점이 cd다)
#   2. db.zo가 보인다  → 그 DB가 tmpfs의 홈이 아니라 설정 디스크에 있다
#   3. history에 있다  → 나갈 때 쓰는 파일을 7차가 fc -W로 대신 썼다
probe_persisted_memory() {
  local log="$1"
  LOG="$log"

  local ready=0
  for _ in $(seq 1 120); do
    if grep -q "terminal: screen>" "$log"; then ready=1; break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1
  done
  if [ "$ready" != "1" ]; then
    echo "FAIL(boot 8): terminal never rendered a prompt; there was nothing to type into"
    return 1
  fi

  local connected=0
  for _ in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
    sleep 0.5
  done
  if [ "$connected" != "1" ]; then
    echo "FAIL(boot 8): could not connect to QEMU monitor on port ${MONITOR_PORT}"
    return 1
  fi

  # ── 1. 자주 간 디렉터리 ────────────────────────────────────────────────
  #
  # **이 부팅은 `cd`를 한 번도 안 친다.** 7차가 배운 것이 디스크에 없으면
  # `z`는 아무 데도 못 가고 `pwd`는 `/`를 찍는다. 판정 글자를 만들 수 있는
  # 것은 DB 하나뿐이다 — 7차와 같은 이유이고(실측 15의 `..`), 여기서는
  # `..`가 든 줄조차 화면에 없다.
  type_keys "${HOOK_Z_KEYS[@]}"
  type_keys "${HOOK_PWD_KEYS[@]}"
  if ! wait_for_screen '\| /usr/share/terminfo/x'; then
    exec 3<&-
    exec 3>&-
    echo "FAIL(boot 8): the machine forgot the directory the seventh boot learned"
    echo "  셋 중 하나다 — XDG_DATA_HOME이 셸에 안 갔거나, DB가 tmpfs에"
    echo "  쓰였거나(그러면 전원과 함께 사라진다), 훅이 안 걸렸다. 7차가"
    echo "  초록이었으면 셋째는 아니다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 8: z walked into a directory this boot never visited"

  # ── 2. 그 기억이 사는 자리 ─────────────────────────────────────────────
  #
  # 위의 판정만으로는 "어딘가에 남았다"까지다. 이 한 줄이 **설정 디스크**라는
  # 것을 말한다 — 홈(/)은 tmpfs라 거기 있었으면 위가 이미 빨갰겠지만,
  # 그 추론과 **보는 것**은 다르다.
  type_keys "${XDG_LS_KEYS[@]}"
  if ! wait_for_screen '\| db\.zo'; then
    exec 3<&-
    exec 3>&-
    echo "FAIL(boot 8): /config/xdg/zoxide holds no db.zo; the memory is not on the disk"
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 8: that memory lives on the config disk, not in the tmpfs home"

  # ── 3. 쳤던 명령 ───────────────────────────────────────────────────────
  #
  # **판정 글자가 행의 첫머리가 아니다.** `history`의 출력은 네 칸 들여쓴
  # 번호로 시작하기 때문이다(실측 36). 그래도 이 검사가 진짜인 이유는 같다 —
  # **`whence -w fzf-history-widget`은 이 부팅에서 아무도 안 친다.** 8차가
  # 치는 것은 `z`·`pwd`·`ls`·`history` 넷뿐이고, 그 글자를 화면에 만들 수
  # 있는 것은 7차가 쓰고 간 파일 하나다.
  type_keys "${HISTORY_KEYS[@]}"
  local ok=0
  if wait_for_screen 'whence -w fzf-history-widget'; then ok=1; fi

  exec 3<&-
  exec 3>&-

  if [ "$ok" != "1" ]; then
    echo "FAIL(boot 8): the history list has nothing the seventh boot typed"
    echo "  둘 중 하나다 — 7차의 fc -W가 못 썼거나(그러면 7차가 빨갰다),"
    echo "  이 부팅의 셸이 HISTFILE을 안 읽었다."
    grep -a "terminal: screen>" "$log" | tail -1
    return 1
  fi
  echo "boot 8: the history list carries a command only the seventh boot typed"
  return 0
}
```

- [ ] **Step 5: 1차·7차에 env 검사를 더한다**

1차 부팅의 `echo "boot 1: init seeded all three rc files on the empty disk"`
뒤에 **넣을 것**:

```bash
# SM-M2. **이 부팅의 셸은 fish다**(씨앗이 기본값이다). fish의 히스토리는
# XDG_DATA_HOME 아래로 통째로 따라오므로(실측 11·40) HISTFILE이 한 줄도
# 안 나와야 한다 — **그 침묵이 결정 3의 절반이고, 값이 폴백 뒤의 셸을
# 따른다는 증거이기도 하다.**
if ! grep -q "tars-init: env PATH=/usr/bin:/bin XDG_DATA_HOME=/config/xdg" "$LOG1"; then
  report_failure "$LOG1" "first boot did not put XDG_DATA_HOME in the env block"
fi
if grep -q "tars-init: env HISTFILE" "$LOG1"; then
  report_failure "$LOG1" "first boot gave fish a HISTFILE; fish carries its history under XDG_DATA_HOME"
fi
echo "boot 1: the env block carries XDG_DATA_HOME, and fish asked for no HISTFILE"
```

7차 부팅의 `if ! grep -q "tars-init: config shell=zsh.*shell_config=on" "$LOG7"`
블록 뒤에 **넣을 것**:

```bash
# SM-M2. 이 부팅의 셸은 zsh다 — 셋이 다 나와야 한다. **SAVEHIST가 없으면
# zsh는 HISTFILE이 있어도 한 줄도 안 쓴다**(실측 9). 아래 화면 판정이
# 그것을 실제로 보지만, 로그의 이 셋이 **왜** 그런지를 말해 준다.
for want in \
  "tars-init: env HISTFILE=/config/zsh_history" \
  "tars-init: env HISTSIZE=5000" \
  "tars-init: env SAVEHIST=5000"; do
  if ! grep -q "$want" "$LOG7"; then
    report_failure "$LOG7" "seventh boot did not put '${want#tars-init: env }' in the env block"
  fi
done
```

- [ ] **Step 6: 8차 부팅 블록을 더한다**

7차 블록의 마지막 `echo "boot 7: the machine learned a directory …"` 뒤,
`# 정보성. ext2가 …` 앞에 **넣을 것**:

```bash
# ---------------------------------------------------------------- 8차 부팅
# 같은 이미지, 기본 cmdline, **아무것도 안 심는다.** 7차와 이 부팅 사이에
# 달라진 것은 **기계가 한 번 꺼졌다 켜졌다**는 것뿐이다.
#
# ★ **SM-M2가 증명하려는 것이 여기 있다.** 7차가 8차를 진짜로 만든다 —
#   7차가 DB에 넣은 것은 `/usr/share/terminfo/x` 하나이고, 그 하나가
#   `XDG_DATA_HOME` 덕분에 여기까지 살아남는다.
LOG8="$(mktemp)"
echo "=== boot 8/8: nothing is planted — the machine must remember the seventh boot ==="
if ! boot_once "$LOG8" "tars-init: started console shell" probe_persisted_memory; then
  report_failure "$LOG8" "the eighth boot did not find what the seventh boot learned"
fi

# 기계가 같은 디스크를 봤다는 것부터. 아래 부정 검사들이 공허해지는 길을 막는다.
if ! grep -q "tars-init: loaded /config/tars.conf" "$LOG8"; then
  report_failure "$LOG8" "eighth boot did not load /config/tars.conf"
fi
if ! grep -q "tars-init: config shell=zsh.*shell_config=on" "$LOG8"; then
  report_failure "$LOG8" "eighth boot did not read back shell_config=on"
fi

# **씨앗은 다시 안 깔린다.** 7차가 zshrc를 되깔았으므로 셋이 다 있다 —
# 여기서 seeded가 하나라도 나오면 디스크가 아니라 tmpfs를 보고 있는 것이다.
if grep -q "tars-init: seeded /config/" "$LOG8"; then
  report_failure "$LOG8" "eighth boot re-seeded an rc file; it was not looking at the same disk"
fi

# 7차와 같은 rc다 — 사람이 손댄 줄이 없고, 셸을 안 죽인다.
if grep -q "tars-rc-alive" "$LOG8"; then
  report_failure "$LOG8" "the eighth boot's rc carries a line a human typed; it is not the seed"
fi
if grep -q "times fast" "$LOG8"; then
  report_failure "$LOG8" "a shell died on the eighth boot"
fi
if grep -q "tars-init: giving up on" "$LOG8"; then
  report_failure "$LOG8" "the supervisor gave up on a child on the eighth boot"
fi
for want in "console shell" "terminal"; do
  STARTS="$(grep -c "tars-init: started ${want}" "$LOG8" || true)"
  if [ "$STARTS" != "1" ]; then
    report_failure "$LOG8" "init started the ${want} ${STARTS} times on the eighth boot, want exactly 1"
  fi
done
if grep -q "Attempted to kill init" "$LOG8"; then
  report_failure "$LOG8" "kernel panicked because PID 1 exited on the eighth boot"
fi
echo "boot 8: the machine remembered a directory and a command across a power cut"
```

그리고 맨 끝의 init 로그 덤프에 한 벌 **더한다**:

```bash
echo "--- init log (boot 8) ---"
grep 'tars-init:' "$LOG8" || true
```

- [ ] **Step 7: `tools/check.sh`의 낡은 주석 한 자리**

`tools/check.sh:634` 근처의 **지울 것**:

```
# DB는 `$HOME/.local/share/zoxide/db.zo`에 생긴다. 홈(/)은 tmpfs라 이 부팅과
# 함께 사라지고 **M0에서는 그것이 맞다** — 부팅을 넘어 남게 하는 것은 SM-M2이고
# 그때 XDG_DATA_HOME이 이 자리를 /config로 옮긴다. **이 검사의 판정 글자는
# 그때도 안 바뀐다.**
```

**넣을 것**:

```
# DB는 **`$XDG_DATA_HOME/zoxide/db.zo`**에 생긴다(SM-M2가 옮겼다). 이 체인에는
# 설정 디스크가 없으므로 `/config`는 tmpfs의 빈 디렉터리이고, zoxide가 거기에
# 조용히 자기 자리를 만든다(실측 4·38) — **이 부팅과 함께 사라지고, 그것이
# 여기서는 맞다.** 부팅을 넘어 남는 것을 보는 것은 `config/check.sh`의 8차이고,
# **이 검사의 판정 글자는 그때도 안 바뀌었다.**
```

---

## Task 8: config 체인 단독 실행

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash config/check.sh 2>&1 | tail -50
```

- [ ] **Step 1: 통과할 때까지 돌린다**(부팅 여덟, 약 1분 50초)

기대하는 새 줄 넷:

```
boot 1: the env block carries XDG_DATA_HOME, and fish asked for no HISTFILE
boot 7: the shell wrote its history to the config disk before the power was cut
boot 8: z walked into a directory this boot never visited
boot 8: that memory lives on the config disk, not in the tmpfs home
boot 8: the history list carries a command only the seventh boot typed
boot 8: the machine remembered a directory and a command across a power cut
```

⚠ **첫 실행에서 가장 그럴듯한 실패는 `shift-w`다.** 화면에 `fc: bad option`이
보이면 대문자가 게스트에 안 닿은 것이고, 그때는 `terminal/src/input.zig`의
shift 경로를 보기 전에 **monitor에 직접 `sendkey shift-w`를 쳐서** 어느 겹이
문제인지 먼저 가른다(QEMU가 안 보낸 것과 우리 keymap이 안 받은 것은 다른
병이다).

- [ ] **Step 2: 걸린 시간을 적어 둔다** (SM-M1은 부팅 일곱에 약 1분 40초였다)

---

## Task 9: 게스트 음성 확인 둘 + 측정 하나

**Files:** 없음(되돌렸다 복구)

**매번 앞에 `rm -rf init/.zig-cache init/zig-out`을 친다.**

- [ ] **되돌림 D: `XDG_DATA_DIR`을 `/tmp/xdg`로 바꾼다**

(`environ.zig` 한 줄. `environ_test`의 값 검사 둘도 함께 고쳐야 호스트를
지난다 — **그 두 줄을 고쳐야 한다는 것 자체가 그물이 산다는 증거다.**)

기대: **7차는 초록이고 8차의 첫 판정이 빨갛다.**

```
boot 7: nobody typed 'zoxide add' — the cd hook learned the directory …
boot 7: the shell wrote its history to the config disk before the power was cut
FAIL(boot 8): the machine forgot the directory the seventh boot learned
```

**이 비대칭이 이 milestone이 증명하는 것의 정확한 모양이다** — 한 부팅
안에서는 되고, 부팅을 넘으면 안 된다. M1의 7차는 이 되돌림을 **못 잡는다.**

- [ ] **되돌림 E: `HIST_ZSH`에서 `SAVEHIST` 줄을 지운다**

(`config_test.zig`의 `want_len`도 함께 고쳐야 호스트를 지난다.)

기대: **7차의 새 판정이 빨갛다** — 파일이 아예 안 만들어져 `wc`가
`No such file`을 찍는다.

```
FAIL(boot 7): 'fc -W' left no history file for the eighth boot to read
```

**실측 9의 재현이고, 그 실측이 없었으면 `HISTFILE`만 주고 끝냈을 자리다.**

- [ ] **측정 F(음성 확인이 아니다): `makeXdgDir()` 호출을 지운다**

기대: **초록일 것이다.** zoxide가 없는 경로를 스스로 만든다(실측 4·38).

**초록이면 그것을 그대로 적는다** — 그 `mkdir`은 기능이 아니라 **실패의
자리를 정하는 것**이고, SM-M0이 관문에 대해 *"고친 것이 아니라 보장한
것이다"*라고 적은 것과 같은 종류다. 빨갛다면 실측 4가 게스트에서 안 맞는
것이니 그쪽이 훨씬 중요한 발견이다.

---

## Task 10: 루트 게이트 (약 27~28분)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/gate.log 2> /tmp/gate.time
```

- [ ] **Step 1: 3/3, 18 PASS / 0 FAIL**

기준선은 SM-M1의 **27분 05.06초**다. 부팅이 하나 늘어 회차마다 세 번 더
켜지므로 **부팅당 약 6초 × 3 = +20초 안쪽**으로 본다.

- [ ] **Step 2: 세는 것**

```bash
for s in 'command not found' 'Unknown command' 'Welcome to fish' \
         'boot 8: the machine remembered' 'all 67 tools'; do
  printf '%-40s %s\n' "$s" "$(grep -c "$s" /tmp/gate.log)"
done
```

| 세는 것 | 기대 | 뜻 |
|---|---|---|
| `command not found` | **0** | env 넷이 열한 체인 어디서도 한 글자도 안 찍었다 |
| `Unknown command` | 0 | fish 쪽도 같다 |
| `Welcome to fish` | **6** | SC-M0~SM-M1과 같다 — **회귀 없음** |
| `boot 8: the machine remembered` | 3 | 새 부팅 × 세 회차 |
| `all 67 tools` | 3 | `tools` 체인은 안 건드렸다 |

⚠ **설정 디스크를 붙이는 다섯 체인이 전부 새 env를 받는다**(조건이 없다 —
결정 9). 그중 셋이 화면의 **셀 좌표**로 판정하므로, 실측 39c가 예측하는
"안 깨진다"를 확인하는 것이 이 게이트에서 가장 중요한 일이다.

---

## Task 11: 문서 — **서브프로젝트가 닫힌다**

- [ ] **Step 1: design** — 실측 34~42 · 결정 3에 **정정 블록**(게이트는 전원을
      뽑으므로 7차가 `fc -W`를 친다) · **`Status:` 줄을 "완료"로**
- [ ] **Step 2: `docs/decisions/project_shell_memory.md`** — M2가 배운 것
- [ ] **Step 3: `MEMORY.md` · `CLAUDE.md`**(완료 목록에 SM을 넣는다) ·
      `HANDOFF.md`
- [ ] **Step 4: 이 plan의 체크박스와 `⚠ plan이 틀렸다` 블록**(틀린 자리가
      있었다면 지우지 않고 남긴다)
- [ ] **Step 5: 커밋** — Claude가 만든다

---

## 이 milestone이 안 하는 것

| | 왜 |
|---|---|
| 위험 3(zsh 두 세션이 같은 `HISTFILE`을 겹쳐 쓴다) | **알고 둔다.** `setopt APPEND_HISTORY`는 씨앗 허용 목록을 한 줄 더 넓히는 일이고, 이 서브프로젝트가 먼저 증명할 것은 "남는다"다 |
| `Ctrl+R`을 게이트가 치는 것 | 비목표 2. TUI라 체인이 매달린다 — 보는 것은 **위젯이 정의됐다는 것**까지다 |
| `/config`가 찼을 때의 정책 | 비목표 3. 상한 5,000줄(=1.5%)까지가 이 서브프로젝트다 |
| fish 히스토리의 줄 수 상한 | 비목표 4. fish에 그 변수가 없다 |
| `git-delta` | 비목표 1 |
| `grep -q` 다섯 자리 | SM-M0이 남긴 숙제. `config/check.sh:552`가 다음 후보 |
| 실측 41(fish가 `$HISTFILE`을 가져온다)을 쓰는 것 | 우리 설계에서는 안 일어난다(fish에 `HISTFILE`을 안 준다). **문서에만 적는다** |

---

## Self-review — spec을 다시 읽고 이 plan과 맞춰 본 것

| design이 요구한 것 | 어느 Task가 하나 |
|---|---|
| 결정 2 — `XDG_DATA_HOME` 하나로 둘을 옮긴다 | Task 3(상수) · Task 7(8차의 판정 1·2) |
| 결정 3 — env 넷, `HISTFILE`은 셸마다 | Task 2 · Task 5(폴백 뒤의 셸) · Task 4(호스트 검사) |
| 결정 4 — 상한 5,000줄 | Task 2(두 셸 다) · 실측 37이 bash에서도 서는 것을 확인 |
| 결정 9 — 조건이 없다 / `/config/xdg`는 init이 만든다 | Task 5 Step 3 · 측정 F |
| Milestone 표 — "8차가 이전 부팅에서 배운 디렉터리와 명령을 찾는다" | Task 7 Step 4·6 |
| 위험 1 — 한 글자도 찍으면 안 된다 | 실측 39c(0바이트) · Task 10 |
| 위험 5 — 게이트가 늘어난다 | Task 10(+20초 안쪽) |

**design이 안 적었고 이 plan이 더한 것 하나:** 게이트가 전원을 뽑는다는 사실
(실측 34)과 그 처방(`fc -W` + `wc` 되읽기). **결정 3은 "부팅 사이에 남는다"를
적으면서 게이트가 기계를 어떻게 끝내는지를 안 봤다** — M1에서 design이
"앞 부팅이 남긴 디스크 상태를 안 봤다"와 같은 종류의 빈 자리이고, 이번에는
착수 전에 걸렸다.
