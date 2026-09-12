# SD-M1 Implementation Plan — 그 한 줄이 씨앗에 선다

> 완료: 2026-09-12. Task 다섯 전부. 호스트 검사 `PASS`, 되돌림 넷이 각각
> 다른 줄에서 죽었고, config 체인 단독이 1분 26.01초에 `FAIL` 없이 끝났다.
>
> plan이 한 군데에서 틀렸고 지우지 않고 남긴다. Task 3의 절차를 "저장소
> 파일을 고쳤다가 `cp`로 되돌린다"로 적었는데, 실제로는 고친 사본을 `/tmp`에
> 만들어 `-v`로 `init/src/config.zig` 자리에 마운트했다. 저장소 파일이 한
> 번도 안 바뀌므로 되돌리는 것을 잊는 경로가 아예 없다. 되돌림을 쓰는 다음
> plan은 이쪽을 기본으로 적을 것.
>
> 그리고 plan에 없던 사고가 하나 있었다. Task 1 Step 4에서 씨앗 끝의 빈
> 줄(`\\`)이 함께 지워졌다. plan이 "지우면 안 된다"고 적어 두었는데도
> 일어났고, 잡은 것은 `git diff | grep '^-'`로 지운 줄을 직접 읽은
> 것이었다 — `git diff --stat`의 숫자만 봤으면 못 봤다.

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan
> task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Goal: 씨앗 rc의 zsh 갈래가 `setopt INC_APPEND_HISTORY` 한 줄을 담는다. 그
줄이 있으면 zsh가 명령을 칠 때마다 그 자리에서 `HISTFILE`에 쓰므로, 쓰는
시점이 종료 경로에서 떨어져 나온다(design 실측 6). 그리고 호스트 검사가
그 줄을 지우는 것도, 오타를 내는 것도, 목록과 씨앗에서 함께 지우는 것도
0.1초에 빨갛게 만든다.

Architecture: 새 파일이 하나도 없다. 고치는 파일이 둘이다.

| 파일 | 이 milestone에서 하는 일 |
|---|---|
| `init/src/config.zig` | `Shell.histOptionLines()`가 새로 서고, 씨앗의 zsh 갈래가 그 글자를 따로 한 벌 더 적는다 |
| `init/src/config_test.zig` | `expectQuietSeed`의 허용 목록을 양방향으로 넓히고, 새 검사 `expectHistOptions`가 개수를 못 박는다 |
| `config/check.sh` | 안 고친다. 그것이 SD-M2다(`fc -W`를 빼는 일과 음성·양성 대조군) |
| `kernel/` · `terminal/` · `init/src/main.zig` · `environ.zig` | 안 고친다 |

Tech Stack: Zig 0.16(init) · `zig build && zig build test`(호스트) ·
bash(config 체인 단독 실행 한 번)

읽고 시작할 것:
`docs/superpowers/specs/2026-09-12-tars-shell-history-durability-design.md` —
특히 확인 1(zsh에 옵션을 나르는 env가 없다) · 확인 4(`shell_config=off`는
zsh에 `-f`를 준다) · 확인 5(씨앗은 파일이 없을 때만 깔린다) · 확인 6(허용
목록의 구조) · 결정 2·3·4·6·7 · 실측 9(그 줄은 0바이트, 오타는 65바이트).

그리고 고칠 자리의 소스 넷. `config.zig`의 `histEntries()` 머리 주석 ·
`hookLines()` 머리 주석 · `rcSeed()` 머리 주석, 그리고
`config_test.zig`의 `expectQuietSeed` 머리 주석. 넷이 서로를 가리키고 있고,
이 milestone은 그 넷을 함께 넓힌다.

---

## 이 milestone을 지배하는 사실 셋

### 1. 오타 한 글자가 다섯 체인의 화면 좌표를 민다

실측 9가 쟀다. `setopt INC_APPEND_HISTORY`는 stdout·stderr 둘 다 0바이트이고,
`INC_APPEND_HISTORYY`는 stderr 65바이트다.

```
/tmp/q_typo/.zshrc:setopt:1: no such option: INC_APPEND_HISTORYY
```

씨앗은 설정 디스크를 붙이는 다섯 체인 전부에서 읽히고 그중 셋이 화면의 셀
좌표로 판정한다. 그래서 이 milestone의 가장 큰 위험은 "옵션이 안 먹는다"가
아니라 "옵션 이름을 잘못 적어서 엉뚱한 체인이 20초 뒤에 깨진다"다. 그 사고를
게이트가 아니라 호스트 검사가 먼저 잡아야 하고, 그것을 하는 것이 Task 2의
`KNOWN_HIST_OPTIONS`다.

### 2. 두 벌을 잇는 것은 컴파일러가 아니라 검사다

`rcSeed()`의 zsh 갈래에 적는 글자와 `histOptionLines()`가 주는 글자는 두
벌이다. 조립하지 않는다 — `rcSeed()`를 목록에서 `++`로 만들면 역방향 검사가
tautology가 된다(SM 결정 10, SD 결정 3). 이 파일은 같은 종류의 이음매를 이미
셋 갖고 있다(`hookLines()` ↔ 씨앗 · `HangulLayout` ↔ `hangul.Layout` ·
`rcPath()` ↔ `make_initrd.sh`).

두 벌이면 구멍이 하나 생긴다 — 두 벌을 함께 고치면 검사가 통과한다. SM-M1이
그 구멍을 `HOOKED_TOOLS`로 막았고, 이 milestone은 `KNOWN_HIST_OPTIONS`로
막는다. 그래서 사실상 세 벌이고, 셋째 벌의 목적은 손이 한 번 멈추는 자리를
만드는 것이다.

### 3. M1은 게이트를 안 고치는데 게이트가 그 줄을 이미 읽는다

씨앗이 다시 깔리는 자리가 `config/check.sh`의 6차 부팅이고(그 체인 주석
129~132줄), 7차가 그 rc를 읽은 zsh다. 그러니 M2 전에도 그 줄은 게이트에서
실제로 동작한다.

깨지지 않는다고 보는 근거를 적어 둔다. 7차의 판정은 `wc -l`이 만드는 숫자
(`\| [1-9][0-9]* /config/zsh_history`)이고, 8차의 판정은 `history` 출력에
`whence -w fzf-history-widget`이 있는가다. 옵션이 켜지면 파일이 더 일찍
자랄 뿐이고 `fc -W`는 같은 세션의 목록으로 덮어쓰므로(실측 10 — 지워지는
것은 다른 세션의 줄이고 7차는 한 세션이다) 두 판정의 기대값이 안 바뀐다.
`fc -W`가 이제 불필요해진 것은 맞고, 그것을 빼는 것이 M2다.

그래도 확인은 한다. Task 4가 config 체인을 단독으로 한 번 돌린다(약 1분
26초). 근거가 추론이면 재는 것이 이 저장소의 규율이고, 씨앗의 바이트가
커진 것은 사실이기 때문이다.

---

## Task 1: `config.zig` — `histOptionLines()`와 씨앗의 한 줄

Files:
- Modify: `init/src/config.zig`

편집이 넷이다. 셋이 주석을 고치는 것이고 하나가 코드를 더하는 것이다.
주석 셋을 함께 고치는 이유는 그 셋이 지금 "씨앗에는 히스토리 줄이 한 줄도
없다"를 말하고 있어서, 코드만 고치면 저장소 안에 답과 틀린 문장이 같이
남기 때문이다 — 이 서브프로젝트가 열린 이유가 정확히 그것이었다.

- [x] Step 1: `histEntries()` 머리 주석의 마지막 문단을 고친다

지울 것 (`init/src/config.zig`, `const HIST_BASH` 바로 위):

```zig
    /// 씨앗 rc에는 히스토리 줄이 한 줄도 없다(결정 3). 실측 9·10이
    /// 근거다 — 셋 다 env에서 먹는다. 그래서 이 milestone은
    /// `rcSeed()`도 `expectQuietSeed`도 한 글자 안 건드린다.
```

넣을 것:

```zig
    /// 히스토리 env는 씨앗 rc를 한 글자도 안 건드린다(SM 결정 3). 실측
    /// 9·10이 근거다 — 셋 다 env에서 먹는다.
    ///
    /// 그 문장을 옵션까지 덮는 것으로 읽으면 안 된다. `setopt`를 zsh에
    /// 나르는 환경 변수는 없어서 옵션은 파일로만 줄 수 있다(SD 확인 1).
    /// 그래서 SD-M1이 씨앗의 zsh 갈래에 한 줄을 더했고, 그 줄의 목록이
    /// 아래 `histOptionLines()`다. env로 되는 것과 파일로만 되는 것이
    /// 갈리는 자리가 여기다.
```

- [x] Step 2: `hookLines()` 아래에 옵션 목록과 함수를 세운다

`pub fn hookLines(...)`의 닫는 중괄호와 `rcSeed()`의 머리 주석 사이에 넣을 것:

```zig

    /// 씨앗 rc가 담는 히스토리 옵션 줄(SD design 결정 1·3). zsh만 하나이고
    /// bash와 fish는 빈 목록이다.
    ///
    /// 이 한 줄이 하는 일은 쓰는 시점을 옮기는 것이다. 이 줄이 없으면 zsh는
    /// 셸이 죽으면서 한 번에 쓰는데, 그 기회가 두 셸에게 다르게 온다 —
    /// 화면 셸은 `terminal`이 먼저 죽어 PTY가 닫히면서 SIGHUP을 받고, 콘솔
    /// 셸은 받을 데가 없어 SIGTERM을 무시한 채 3초를 버틴 뒤 SIGKILL에
    /// 죽는다. 그래서 전원 버튼을 누르면 콘솔 셸에 친 명령이 통째로
    /// 사라진다(SD 실측 4·14 — 게스트에서 콘솔 0, 화면 1을 쟀다).
    ///
    /// 이 줄이 있으면 명령마다 그 자리에서 파일에 쓰므로 SIGKILL에도
    /// 남는다(실측 3·6).
    ///
    /// bash가 0인 것은 빠뜨린 것이 아니다. bash에는 `setopt` 한 줄에
    /// 대응하는 것이 없어서 `PROMPT_COMMAND='history -a'` 같은 프롬프트 훅이
    /// 필요하고, 그것은 허용 목록을 한 범주 더 넓히는 일이다(비목표 1).
    /// fish는 `exit`·SIGTERM·SIGHUP 셋 다에서 쓰므로 고칠 것이 애초에
    /// 없다(실측 8).
    ///
    /// `rcSeed()`가 담는 글자와 여기 글자가 두 벌인 이유는 `hookLines()`의
    /// 머리 주석과 같다 — 조립하면 역방향 검사가 tautology가 된다.
    const HIST_OPTIONS_ZSH = [_][]const u8{
        "setopt INC_APPEND_HISTORY",
    };

    /// 이 셸의 히스토리 옵션 줄들.
    pub fn histOptionLines(self: Shell) []const []const u8 {
        return switch (self) {
            .fish => &[_][]const u8{},
            .bash => &[_][]const u8{},
            .zsh => &HIST_OPTIONS_ZSH,
        };
    }
```

- [x] Step 3: `rcSeed()` 머리 주석의 허용 목록 문장을 넓힌다

지울 것:

```zig
    /// 주석 · alias · 위 `hookLines()`에 글자 그대로 있는 줄 셋뿐이고,
```

넣을 것:

```zig
    /// 주석 · alias · 위 `hookLines()`와 `histOptionLines()`에 글자 그대로
    /// 있는 줄뿐이고,
```

그리고 SM-M1 문단(`/// SM-M1이 그 문을 두 줄만큼 넓혔다.`로 시작하는 문단)
바로 아래에 한 문단 더 넣을 것:

```zig
    ///
    /// SD-M1이 zsh 갈래에서 한 줄 더 넓혔다. 같은 방식이다 — 범주
    /// (`setopt `로 시작하면 통과)가 아니라 정확 허용 목록이고, 그 줄을
    /// 허용하는 근거는 취향이 아니라 재 본 값이다(SD 실측 9 — 0바이트,
    /// 오타는 stderr 65바이트).
```

- [x] Step 4: 씨앗의 zsh 갈래에 그 글자를 한 벌 더 적는다

`.zsh =>` 갈래의 마지막 훅 줄(`command -v fzf ... fzf --zsh ...`) 다음에
넣을 것:

```zig
            \\#
            \\# 아래 한 줄이 히스토리를 명령마다 그 자리에서 파일에 쓴다.
            \\# 이 줄이 없으면 zsh는 셸이 죽으면서 한 번에 쓰는데, 전원 버튼을
            \\# 눌러도 콘솔 셸에는 그 기회가 안 온다 — 대화형 셸은 SIGTERM을
            \\# 무시하고 3초 뒤 SIGKILL에 죽으므로, 그 세션에 친 명령이 통째로
            \\# 사라진다. 지우면 그 동작으로 돌아간다.
            \\setopt INC_APPEND_HISTORY
```

넣은 뒤 그 갈래의 끝이 이 모양이어야 한다.

```zig
            \\command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
            \\command -v fzf >/dev/null && eval "$(fzf --zsh)"
            \\#
            \\# 아래 한 줄이 히스토리를 명령마다 그 자리에서 파일에 쓴다.
            ...
            \\setopt INC_APPEND_HISTORY
            \\
            ,
        };
    }
```

마지막 `\\`(빈 줄)를 지우면 안 된다. 씨앗이 개행으로 끝나는 것을
`expectQuietSeed`의 첫 검사가 본다.

- [x] Step 5: 컴파일만 먼저 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init && zig build'
```

기대: 아무 말 없이 끝난다. 이 단계에서 `zig build test`는 빨간 것이 정상이다
— `expectQuietSeed`가 아직 `setopt` 줄을 모르므로 정방향이 그 줄을 잡는다.
그 빨강이 Task 2의 red다.

- [x] Step 6: 그 빨강을 실제로 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build test' 2>&1 | tail -20
```

기대: `FAIL: the zsh seed has a line that is not a comment, not an alias,`와
그 아래 `setopt INC_APPEND_HISTORY`.

이 Step을 건너뛰지 않는다. 이것이 이 milestone에서 유일하게 "검사가 이 줄을
정말로 보고 있다"를 공짜로 얻는 자리다 — 뒤의 되돌림 넷과 달리 파일을
되돌릴 필요가 없다.

---

## Task 2: `config_test.zig` — 허용 목록 양방향과 `expectHistOptions`

Files:
- Modify: `init/src/config_test.zig`

- [x] Step 1: 파일 머리에 상수 둘을 더한다

`const HOOKED_TOOLS = ...` 바로 아래에 넣을 것:

```zig

/// `expectQuietSeed`가 히스토리 옵션 줄을 몇 개까지 셀 수 있는가.
/// `MAX_HOOK_LINES`와 같은 이유로 상한이 필요하다 — 힙이 없다.
const MAX_HIST_OPTION_LINES = 4;

/// 씨앗에 들어와도 좋다고 우리가 직접 재 본 옵션 줄(SD design 결정 4).
///
/// `HOOKED_TOOLS`와 같은 자리다 — 손이 한 번 멈추는 자리를 만드는 것이
/// 전부다. `histOptionLines()`와 씨앗은 두 벌이라 함께 고치면 검사가
/// 통과하는데, 그 구멍을 이 셋째 벌이 막는다.
///
/// 새 `setopt` 줄을 씨앗에 넣으려면 먼저 SD 실측 9와 같은 방법으로 그
/// 줄의 stdout·stderr가 0바이트인 것을 재고 여기 적어야 한다. 없는 옵션
/// 이름은 stderr 65바이트이고, 그 65바이트가 설정 디스크를 붙이는 다섯
/// 체인의 화면 좌표를 민다.
const KNOWN_HIST_OPTIONS = [_][]const u8{"setopt INC_APPEND_HISTORY"};
```

- [x] Step 2: `expectQuietSeed`를 통째로 갈아 끼운다

지울 것: `fn expectQuietSeed(sh: config.Shell) !void {`부터 그 함수의 닫는
중괄호까지, 그리고 그 위의 머리 주석 전부.

넣을 것:

```zig
/// 씨앗 rc가 쓸 수 있는 줄만 담고 있는지 확인한다(SC-M1이 세우고 SM-M1과
/// SD-M1이 한 줄씩 넓혔다).
///
/// 셋 다 문법이 다른 셸의 파일이라 우리가 파싱할 수는 없다. 대신 우리가
/// 쓸 수 있는 줄의 종류를 제한한다.
///
/// | | 종류 | 왜 조용한가 |
/// |---|---|---|
/// | SC-M1 | 주석 | 셸이 안 읽는다 |
/// | SC-M1 | `alias …` | 정의만 하고 실행하지 않는다 |
/// | SM-M1 | `hookLines()`의 한 줄과 글자 그대로 같은 줄 | SM 실측 23이 셋 다 0바이트를 쟀다 |
/// | SD-M1 | `histOptionLines()`의 한 줄과 글자 그대로 같은 줄 | SD 실측 9가 0바이트를 쟀다 |
///
/// SM-M1이 문법 범주가 아니라 정확 허용 목록으로 넓힌 이유(SM design 결정 6):
/// "주석 · alias · `eval` 세 범주"로 넓히면 `eval` 뒤에 아무 문장이나 올 수
/// 있고, 그러면 이 규칙이 막으려던 것이 정확히 그것이다.
///
/// SD-M1의 넷째 줄도 같은 이유로 범주가 아니다(SD 결정 4). `setopt `를
/// 접두사로 열면 뒤에 아무 이름이나 올 수 있고, 없는 이름은 stderr
/// 65바이트다(SD 실측 9).
///
/// 역방향도 본다. 정방향만으로는 훅이나 옵션 줄을 지우는 것이 통과한다 —
/// 아무 줄도 안 남으면 위반할 줄도 없기 때문이다.
///
/// 위험 3의 반쪽이 여기 있다. SC design이 "우리가 까는 것은 절대로 셸을
/// 죽이지 않아야 한다"고 적었고, 그 "절대로"를 지키는 장치가 이 함수다.
fn expectQuietSeed(sh: config.Shell) !void {
    const text = sh.rcSeed();
    if (text.len == 0 or text[text.len - 1] != '\n') {
        std.debug.print("FAIL: the {s} seed does not end with a newline\n", .{@tagName(sh)});
        return error.BadSeed;
    }
    const hooks = sh.hookLines();
    const opts = sh.histOptionLines();
    // 훅과 옵션 줄이 씨앗에서 보였는가. 힙이 없으므로 상한이 둘 다
    // 필요하고, 넘치면 조용히 덜 검사하지 말고 여기서 죽는다.
    var seen = [_]bool{false} ** MAX_HOOK_LINES;
    var seen_opt = [_]bool{false} ** MAX_HIST_OPTION_LINES;
    if (hooks.len > seen.len) {
        std.debug.print("FAIL: the {s} shell has {d} hook lines; raise MAX_HOOK_LINES\n", .{
            @tagName(sh), hooks.len,
        });
        return error.BadSeed;
    }
    if (opts.len > seen_opt.len) {
        std.debug.print(
            "FAIL: the {s} shell has {d} history option lines; raise MAX_HIST_OPTION_LINES\n",
            .{ @tagName(sh), opts.len },
        );
        return error.BadSeed;
    }
    var lines = std.mem.splitScalar(u8, text, '\n');
    var aliases: usize = 0;
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;
        if (std.mem.startsWith(u8, line, "alias ")) {
            aliases += 1;
            continue;
        }
        // `startsWith`가 아니라 `eql`이다. 접두사로 보면
        // `command -v zoxide >/dev/null && rm -rf /`가 통과한다.
        var allowed = false;
        for (hooks, 0..) |hook, i| {
            if (!std.mem.eql(u8, line, hook)) continue;
            seen[i] = true;
            allowed = true;
            break;
        }
        if (!allowed) {
            for (opts, 0..) |opt, i| {
                if (!std.mem.eql(u8, line, opt)) continue;
                seen_opt[i] = true;
                allowed = true;
                break;
            }
        }
        if (allowed) continue;
        std.debug.print(
            "FAIL: the {s} seed has a line that is not a comment, not an alias,\n" ++
                "      and not one of its hook or history option lines:\n  {s}\n" ++
                "      the allowed lines are:\n",
            .{ @tagName(sh), line },
        );
        for (hooks) |hook| std.debug.print("        {s}\n", .{hook});
        for (opts) |opt| std.debug.print("        {s}\n", .{opt});
        return error.BadSeed;
    }
    // ── 역방향 — 훅이나 옵션 줄을 지우는 것이 통과하지 않게 한다 ────────
    for (hooks, 0..) |hook, i| {
        if (seen[i]) continue;
        std.debug.print(
            "FAIL: the {s} seed does not carry its hook line:\n  {s}\n",
            .{ @tagName(sh), hook },
        );
        return error.BadSeed;
    }
    for (opts, 0..) |opt, i| {
        if (seen_opt[i]) continue;
        std.debug.print(
            "FAIL: the {s} seed does not carry its history option line:\n  {s}\n",
            .{ @tagName(sh), opt },
        );
        return error.BadSeed;
    }
    // alias가 하나도 없으면 1차 부팅의 `tars-config`가 무의미해진다.
    // 게이트는 그 alias가 있다는 것으로 "셸이 이 파일을 읽었다"를 판정한다.
    if (aliases == 0) {
        std.debug.print("FAIL: the {s} seed defines no alias for the gate to find\n", .{@tagName(sh)});
        return error.BadSeed;
    }
    // 씨앗은 자기 파일의 이름을 자기 안에 적는다. 그 이름이 틀리면 사용자가
    // `tars-rc`를 쳤을 때 없는 파일을 cat한다 — 문서가 아니라 실행되는
    // 문장이라 틀린 것이 드러난다.
    if (std.mem.indexOf(u8, text, sh.rcPath()) == null) {
        std.debug.print("FAIL: the {s} seed never names its own path {s}\n", .{
            @tagName(sh), sh.rcPath(),
        });
        return error.BadSeed;
    }
}
```

- [x] Step 3: `expectHistEntries` 머리 주석의 둘째 문단을 고친다

지울 것:

```zig
/// `expectQuietSeed`와 짝이 아니다 — 이 milestone은 씨앗을 안 건드린다.
/// 히스토리는 rc가 아니라 env로 세우고(실측 9·10·11), 그 결정이 옳은지는
/// `config/check.sh`의 8차 부팅이 본다. 여기가 보는 것은 우리가 셸마다
/// 무엇을 주려고 했는가까지다.
```

넣을 것:

```zig
/// 이 함수는 env만 본다. 히스토리를 rc가 아니라 env로 세운 것이 SM의
/// 결정이고(SM 실측 9·10·11), 그 결정이 옳은지는 `config/check.sh`의 8차
/// 부팅이 본다. 여기가 보는 것은 우리가 셸마다 무엇을 주려고 했는가까지다.
///
/// 씨앗 쪽의 짝은 아래 `expectHistOptions`다. SD-M1이 그것을 더했다 —
/// env로 되는 것(`HISTFILE`·`HISTSIZE`·`SAVEHIST`)과 파일로만 되는 것
/// (`setopt`)이 갈리므로 검사도 둘이다.
```

- [x] Step 4: `expectHistOptions`를 `expectHistEntries` 아래에 더한다

`expectHistEntries`의 닫는 중괄호 다음에 넣을 것:

```zig

/// 히스토리 옵션 줄이 셸의 성질과 맞는가(SD design 결정 4).
///
/// `expectHistEntries`가 `SAVEHIST`를 zsh에만 못 박은 것과 같은 모양이고,
/// 개수가 본체다 — zsh 1 · bash 0 · fish 0.
///
/// 그 0 둘이 빠뜨린 것이 아니라 정한 것이라는 데 이 함수의 값이 있다.
/// fish는 `exit`·SIGTERM·SIGHUP 셋 다에서 쓰므로 고칠 것이 없고(SD 실측 8),
/// bash는 `setopt` 한 줄에 대응하는 것이 없어 프롬프트 훅이 필요하다
/// (SD 실측 7, 비목표 1). 누가 bash를 여는 날에는 이 숫자를 먼저 고쳐야
/// 하고, 그 자리가 이 함수다.
///
/// 보는 것이 둘이다.
///   1. 개수가 셸의 성질과 맞다
///   2. 모든 줄이 `KNOWN_HIST_OPTIONS`에 있다 — 우리가 직접 재 본 글자다
///
/// 둘째가 없으면 `INC_APPEND_HISTORYY`로 오타를 낸 것이 호스트를 통과한다.
/// 개수는 여전히 1이고, 씨앗과 `histOptionLines()`를 함께 틀리게 고치면
/// `expectQuietSeed`의 양방향도 만족되기 때문이다. 그 오타의 대가는
/// stderr 65바이트이고 다섯 체인의 화면 좌표다(SD 실측 9).
fn expectHistOptions(sh: config.Shell) !void {
    const want_len: usize = switch (sh) {
        .fish => 0,
        .bash => 0,
        .zsh => 1,
    };
    const lines = sh.histOptionLines();
    if (lines.len != want_len) {
        std.debug.print("FAIL: the {s} shell carries {d} history option lines, want {d}\n", .{
            @tagName(sh), lines.len, want_len,
        });
        return error.BadHistOption;
    }
    for (lines) |line| {
        var known = false;
        for (KNOWN_HIST_OPTIONS) |k| {
            if (!std.mem.eql(u8, line, k)) continue;
            known = true;
            break;
        }
        if (known) continue;
        std.debug.print(
            "FAIL: the {s} shell wants an option line nobody measured:\n  {s}\n" ++
                "      measure its stdout and stderr first, then add it to KNOWN_HIST_OPTIONS\n",
            .{ @tagName(sh), line },
        );
        return error.BadHistOption;
    }
}
```

- [x] Step 5: `main()`에서 새 검사를 부른다

`for (std.enums.values(config.Shell)) |sh| try expectHooksCoverTheTools(sh);`
다음 줄에 넣을 것:

```zig

    // ── SD-M1: 히스토리 옵션 줄 ─────────────────────────────────────────
    //
    // 검사가 셋인 구조가 SM-M1과 같다. 정방향과 역방향은 위
    // `expectQuietSeed`가 함께 보고, 셋째(씨앗과 `histOptionLines()`에서
    // 함께 지우는 것)를 이 줄이 막는다 — zsh의 개수를 1로 못 박으므로
    // 목록이 비면 그 자리에서 빨개진다.
    for (std.enums.values(config.Shell)) |sh| try expectHistOptions(sh);
```

- [x] Step 6: 호스트에서 돌린다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init && zig build && zig build test'
```

기대: 마지막 줄이 `PASS`.

캐시 삭제를 컨테이너 안에서 하는 이유는 `project_zig_out_staleness`와
HANDOFF의 경고다 — 호스트(macOS)에서 지우면 바로 뒤의 `zig build`가
`error: FileNotFound` 한 줄로 죽는다(9회 중 2회).

---

## Task 3: 호스트 음성 확인 넷

Files:
- Modify(임시): `init/src/config.zig` — 넷 다 되돌린다

검사가 정말로 보고 있는지를 넷으로 나눠 본다. 넷이 서로 다른 실수를 막는다.

| | 되돌림 | 누가 잡아야 하나 |
|---|---|---|
| A | 씨앗의 `setopt` 줄을 `echo hi`로 바꾼다 | `expectQuietSeed` 정방향 |
| B | 씨앗에서 그 줄만 지운다 | `expectQuietSeed` 역방향 |
| C | 씨앗과 `HIST_OPTIONS_ZSH`에서 함께 지운다 | `expectHistOptions`의 개수 |
| D | 씨앗과 `HIST_OPTIONS_ZSH`를 함께 `INC_APPEND_HISTORYY`로 | `KNOWN_HIST_OPTIONS` |

C와 D가 이 표의 요점이다. 두 벌만 있으면 둘 다 통과하고, 그 둘을 막는 것이
셋째 벌(`KNOWN_HIST_OPTIONS`)과 개수를 못 박는 `switch`다.

넷 다 절차가 같다.

- [x] 되돌림 A

```bash
cp init/src/config.zig /tmp/config.zig.orig
# 씨앗의 `setopt INC_APPEND_HISTORY` 줄을 `echo hi`로 고친 뒤
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init && zig build test' 2>&1 | tail -12
cp /tmp/config.zig.orig init/src/config.zig
```

기대: `FAIL: the zsh seed has a line that is not a comment, not an alias,` ·
종료 코드가 0이 아니다.

- [x] 되돌림 B — 씨앗에서 그 줄만 지운다

기대: `FAIL: the zsh seed does not carry its history option line:` 와
그 아래 `setopt INC_APPEND_HISTORY`.

- [x] 되돌림 C — 씨앗과 `HIST_OPTIONS_ZSH`에서 함께 지운다

`HIST_OPTIONS_ZSH`를 빈 배열(`[_][]const u8{}`)로 만들고 씨앗의 그 줄도
지운다.

기대: `FAIL: the zsh shell carries 0 history option lines, want 1`.

- [x] 되돌림 D — 둘을 함께 오타로 고친다

씨앗과 `HIST_OPTIONS_ZSH` 둘 다 `setopt INC_APPEND_HISTORYY`로 고친다
(양방향 검사는 통과하는 상태다).

기대: `FAIL: the zsh shell wants an option line nobody measured:` 와
그 아래 `setopt INC_APPEND_HISTORYY`.

- [x] 넷이 끝나면 원본이 돌아온 것을 확인한다

```bash
git diff --stat init/src/config.zig
rg -n 'INC_APPEND_HISTORY' init/src/config.zig
```

기대: `rg`가 두 줄을 준다(씨앗 한 줄 · `HIST_OPTIONS_ZSH` 한 줄). 둘째
숫자가 아니라 정확히 둘인 것이 "두 벌"의 증명이다.

---

## Task 4: config 체인 단독 (약 1분 26초)

Files: 없음. 확인만 한다.

호스트 검사가 보는 것은 "우리가 그 줄을 씨앗에 넣으려고 했고 그 줄이 조용한
종류다"까지다. 씨앗의 바이트가 실제로 커졌으므로, 그 커진 파일을 읽은
게스트가 화면을 안 밀었다는 것은 부팅으로만 볼 수 있다.

SD-M2가 이 체인을 고칠 것이므로 여기서 판정을 더하지는 않는다. 이 Task가
보는 것은 회귀가 없다는 것 하나다.

- [x] Step 1: 돌린다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash config/check.sh 2>&1 | tail -50
```

기대: 부팅 여덟이 전부 통과하고 `FAIL`이 없다. 특히 볼 것 둘이다.

- `boot 7: the shell wrote its history to the config disk before the power was cut`
- `boot 8: the history list carries a command only the seventh boot typed`

- [x] Step 2: 빨갛다면 원인을 먼저 가른다

빨개지는 경우의 원인이 둘뿐이고 증상이 다르다.

| 증상 | 원인 |
|---|---|
| 화면 좌표를 보는 검사가 밀렸다 | 씨앗이 무언가를 찍었다. `setopt` 줄의 철자를 먼저 본다 |
| 7차나 8차의 히스토리 판정이 깨졌다 | 옵션이 `fc -W`와 섞인 것이다. 그러면 SD-M2를 앞당겨 `fc -W`를 뺀다 |

둘째가 나오면 plan보다 실측이 답이다 — M2의 첫 일을 여기서 한다.

---

## Task 5: 문서와 commit

Files:
- Modify: `docs/superpowers/specs/2026-09-12-tars-shell-history-durability-design.md`
- Modify: `docs/superpowers/plans/2026-09-12-tars-shell-history-durability-sd-m1.md`(이 파일)
- Modify: `HANDOFF.md`

- [x] Step 1: design의 `Status:` 줄을 SD-M1 완료로 고치고, 결정 3·4에
      실제로 들어간 모양(셋째 벌 `KNOWN_HIST_OPTIONS`)을 한 문단 적는다.
      그 상수는 design이 예고하지 않은 것이라 적어야 한다.
- [x] Step 2: 이 plan의 체크박스를 채우고, 틀린 곳이 있으면 지우지 말고
      머리에 정정으로 남긴다(SM-M1 plan이 그 모양이다).
- [x] Step 3: `HANDOFF.md`의 "바로 다음에 할 것"을 SD-M2로 바꾼다.
- [x] Step 4: commit. `git status`로 `M`과 신규를 가른 뒤 Claude가 만든다.

```bash
git add init/src/config.zig init/src/config_test.zig \
  docs/superpowers/plans/2026-09-12-tars-shell-history-durability-sd-m1.md \
  docs/superpowers/specs/2026-09-12-tars-shell-history-durability-design.md \
  HANDOFF.md
```

기억(`docs/decisions/`)은 SD-M2가 끝난 뒤에 한 파일로 쓴다. 지금 쓰면
"게이트가 무엇을 보는가"가 빈 채로 남는다.

---

## 이 milestone이 안 하는 것

- `config/check.sh`의 `fc -W`를 빼는 것과 음성·양성 대조군(SD-M2, 실측 10·11).
- 루트 게이트 3/3(SD-M2). Task 4의 config 체인 단독은 회귀 확인이지 판정이
  아니다.
- bash·fish(결정 7) · `SHARE_HISTORY`(비목표 3) · 취향 옵션들(비목표 4) ·
  마이그레이션(결정 6) · PID 1의 시그널 경로(결정 8).
