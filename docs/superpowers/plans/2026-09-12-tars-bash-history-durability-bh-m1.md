# BH-M1 — 씨앗 한 줄과 호스트 검사

Design: `docs/superpowers/specs/2026-09-12-tars-bash-history-durability-design.md`

M0이 잰 것 위에 선다. bash는 SIGTERM을 무시하고 3초 뒤 SIGKILL에 죽으므로
콘솔 셸에 친 명령을 통째로 잃는다(실측 8·10). 고치는 것은 씨앗 rc의 bash
갈래에 넣는 한 줄이고, 그 줄이 쓰는 시점을 종료 경로에서 떼어 낸다.

zsh와 다른 것이 둘이다. 하나는 그 줄이 훅 두 줄보다 먼저 와야 한다는 것
(실측 6·9 — zoxide가 같은 변수를 쓴다), 다른 하나는 새 줄을 들이는 검증
절차가 비대화형으로는 무력하다는 것이다(실측 5).

## 고칠 자리 넷

| 파일 | 무엇 |
|---|---|
| `init/src/config.zig` | `HIST_OPTIONS_BASH`와 `histOptionLines()`의 bash 갈래 |
| `init/src/config.zig` | `rcSeed()`의 bash 갈래 — 훅보다 앞에 한 줄과 주석 |
| `init/src/config_test.zig` | `KNOWN_HIST_OPTIONS`의 원소와 머리 주석, `expectHistOptions`의 개수 |
| `init/src/config_test.zig` | 새 검사 `expectPromptCommandBeforeHooks`와 `main`의 호출 |

## Task 1: `config.zig`에 옵션 줄을 세운다

Files: `init/src/config.zig`

- [x] Step 1: `HIST_OPTIONS_ZSH`의 머리 주석에서 bash 문단을 고친다

지금 이렇게 적혀 있다.

```
/// bash가 0인 것은 빠뜨린 것이 아니다. bash에는 `setopt` 한 줄에
/// 대응하는 것이 없어서 `PROMPT_COMMAND='history -a'` 같은 프롬프트 훅이
/// 필요하고, 그것은 허용 목록을 한 범주 더 넓히는 일이다(비목표 1).
```

이 문단이 이제 낡았다. BH가 그 훅을 넣었고, "한 범주 더 넓히는 일"도 사실이
아니었다(BH 확인 2 — 넓힌 것은 범주가 아니라 목록의 원소 하나다). 이렇게
바꾼다.

```zig
    /// bash는 BH-M1이 채웠다. `setopt` 한 줄에 대응하는 것이 없어서
    /// 프롬프트 훅(`PROMPT_COMMAND='history -a'`)을 쓰고, 그래서 순서가
    /// 생긴다 — 아래 `HIST_OPTIONS_BASH`의 주석에 있다.
    /// fish는 `exit`·SIGTERM·SIGHUP 셋 다에서 쓰므로 고칠 것이 애초에
    /// 없다(SD 실측 8).
```

- [x] Step 2: `HIST_OPTIONS_BASH`를 `HIST_OPTIONS_ZSH` 아래에 둔다

```zig
    /// bash의 히스토리 옵션 줄(BH design 결정 1·3).
    ///
    /// zsh의 `setopt`와 하는 일은 같고 생긴 것이 다르다. bash에는 쓰는
    /// 시점을 옮기는 옵션이 없어서 프롬프트 훅을 쓴다 — `PROMPT_COMMAND`는
    /// 명령이 끝나고 다음 프롬프트를 그리기 직전에 도는 자리다.
    ///
    /// 그래서 zsh와 타이밍이 한 칸 다르다. zsh는 명령을 읽자마자 쓰므로
    /// 실행 중인 명령이 이미 파일에 있는데(SD 실측 24), bash는 직전 명령까지만
    /// 있다(BH 실측 4). 게이트가 이 파일을 세는 자리에서 이 차이가 값을
    /// 바꾼다.
    ///
    /// `shopt -s histappend`는 안 쓴다. 그 옵션이 정하는 것은 셸이 끝날 때
    /// 덮어쓸 것인가 이어 쓸 것인가이고, 우리가 지는 싸움은 "끝날 때가 아예
    /// 안 온다"이다(BH 실측 10 — SIGKILL 칸). `history -a`는 언제나 append라
    /// 함께 켤 이유도 없다.
    const HIST_OPTIONS_BASH = [_][]const u8{
        "PROMPT_COMMAND='history -a'",
    };
```

- [x] Step 3: `histOptionLines()`의 bash 갈래를 바꾼다

```zig
    pub fn histOptionLines(self: Shell) []const []const u8 {
        return switch (self) {
            .fish => &[_][]const u8{},
            .bash => &HIST_OPTIONS_BASH,
            .zsh => &HIST_OPTIONS_ZSH,
        };
    }
```

- [x] Step 4: 넣은 것을 `rg`로 확인한다

```bash
rg -n 'HIST_OPTIONS_BASH|PROMPT_COMMAND' init/src/config.zig
```

## Task 2: 씨앗 rc의 bash 갈래에 그 줄을 넣는다

Files: `init/src/config.zig`

줄의 자리가 이 Task의 본체다. 훅 두 줄보다 앞이어야 한다(결정 3).

- [x] Step 1: `rcSeed()`의 bash 갈래에서 훅 두 줄 앞에 넣는다

지금 이 모양이다.

```
\\# command -v 관문을 지우지 말 것. …
\\command -v zoxide >/dev/null && eval "$(zoxide init bash)"
\\command -v fzf >/dev/null && eval "$(fzf --bash)"
\\
```

앞에 이것을 끼운다. 주석이 긴 이유는 위험 3이다 — 다음 사람이 줄을 옮기거나
`PROMPT_COMMAND`를 하나 더 쓰는 것을 코드로는 못 막는다.

```
\\#
\\# 아래 한 줄이 히스토리를 명령마다 그 자리에서 파일에 쓴다. 이 줄이
\\# 없으면 bash는 셸이 끝날 때 한 번에 쓰는데, 전원 버튼을 눌러도 콘솔
\\# 셸에는 그 기회가 안 온다 — 대화형 셸은 SIGTERM을 무시하고 3초 뒤
\\# SIGKILL에 죽으므로 그 세션에 친 명령이 통째로 사라진다.
\\#
\\# 이 줄은 아래 훅보다 먼저 있어야 한다. PROMPT_COMMAND는 변수가
\\# 하나뿐이라 마지막 대입이 이기는데, zoxide의 훅이 같은 변수를 쓴다.
\\# 순서가 이대로면 zoxide가 우리 값을 보존하며 앞에 붙여
\\# __zoxide_hook;history -a가 되고 둘 다 돈다. 뒤집으면 우리 대입이
\\# zoxide를 지우고, 증상은 히스토리는 남는데 z가 아무 디렉터리도 안
\\# 배우는 것이다.
\\PROMPT_COMMAND='history -a'
\\#
\\# command -v 관문을 지우지 말 것. …
```

- [x] Step 2: 씨앗이 늘어난 줄 수를 센다

```bash
git diff --stat init/src/config.zig
git diff init/src/config.zig | grep '^-' | grep -v '^---'
```

지우는 줄은 `histOptionLines()`의 bash 갈래 한 줄과 Step 1에서 고친 주석
문단뿐이어야 한다. 씨앗 쪽은 순수 추가다.

- [x] Step 3: 순서를 눈으로 확인한다

```bash
rg -n -A2 -B2 "PROMPT_COMMAND='history -a'" init/src/config.zig
```

`PROMPT_COMMAND` 줄의 줄 번호가 `command -v zoxide` 줄보다 작아야 한다.

## Task 3: 호스트 검사를 넓힌다

Files: `init/src/config_test.zig`

- [x] Step 1: `KNOWN_HIST_OPTIONS`에 원소를 더하고 머리 주석을 고친다

머리 주석의 마지막 문단이 지금 이렇다.

```
/// 새 `setopt` 줄을 씨앗에 넣으려면 먼저 SD 실측 9와 같은 방법으로 그
/// 줄의 stdout·stderr가 0바이트인 것을 재고 여기 적어야 한다. 없는 옵션
/// 이름은 stderr 65바이트이고, 그 65바이트가 설정 디스크를 붙이는 다섯
/// 체인의 화면 좌표를 민다.
```

BH 실측 5가 이 절차를 무력화했다(결정 5). 이렇게 바꾼다.

```zig
/// 새 줄을 씨앗에 넣으려면 먼저 그 줄이 조용한 것을 재고 여기 적어야
/// 한다. 재는 방법이 셸마다 다르다는 것이 BH-M1이 배운 것이다.
///
/// zsh의 `setopt`는 rc를 읽는 그 자리에서 돌므로 `zsh -c '<줄>'`로 잰다.
/// 없는 옵션 이름은 stderr 65바이트다(SD 실측 9).
///
/// bash의 `PROMPT_COMMAND`는 다르다. 비대화형 bash는 그 변수를 아예 실행하지
/// 않아서 `bash -c '<줄>'`은 오타가 나도 0바이트를 돌려준다(BH 실측 5).
/// 대화형 세션을 띄워 화면 전체의 바이트를 재야 한다 — 오타는 프롬프트가
/// 그려질 때마다 `bash: <이름>: command not found`를 찍는다. zsh의 오타가
/// 기동할 때 한 번인 것과 달리 이쪽은 계속 찍힌다.
///
/// 재지 않고 여기에 줄을 더하면 그 대가는 설정 디스크를 붙이는 다섯 체인의
/// 화면 좌표다.
const KNOWN_HIST_OPTIONS = [_][]const u8{
    "setopt INC_APPEND_HISTORY",
    "PROMPT_COMMAND='history -a'",
};
```

- [x] Step 2: `expectHistOptions`의 개수와 머리 주석을 고친다

`want_len`의 bash를 0에서 1로 바꾼다.

```zig
    const want_len: usize = switch (sh) {
        .fish => 0,
        .bash => 1,
        .zsh => 1,
    };
```

머리 주석에서 "개수가 본체다 — zsh 1 · bash 0 · fish 0"과 그 뒤 문단이
낡는다. 이렇게 바꾼다.

```
/// 개수가 본체다 — zsh 1 · bash 1 · fish 0.
///
/// fish의 0이 빠뜨린 것이 아니라 정한 것이라는 데 이 함수의 값이 있다.
/// fish는 `exit`·SIGTERM·SIGHUP 셋 다에서 쓰므로 고칠 것이 없다(SD 실측 8).
/// bash의 1은 BH-M1이 채웠고, zsh와 글자가 아주 다르다 — `setopt`가 아니라
/// `PROMPT_COMMAND` 대입이다.
```

- [x] Step 3: 순서 검사를 새로 쓴다

`expectHistOptions` 아래에 둔다. 위험 1의 처방(본 것이 0이면 그 사실을
적는다)이 함수 안에 있다.

```zig
/// 씨앗에서 `PROMPT_COMMAND`를 건드리는 줄이 훅 줄보다 앞에 있는가
/// (BH design 결정 4).
///
/// `PROMPT_COMMAND`는 변수가 하나뿐이라 마지막 대입이 이긴다. zoxide의 bash
/// 훅이 같은 변수를 쓰는데, 그 훅은 기존 값을 보존하며 앞에 붙인다
/// (BH 실측 6·9 — `PROMPT_COMMAND="__zoxide_hook;${PROMPT_COMMAND#;}"`).
/// 그래서 우리 줄이 먼저면 둘 다 돌고, 나중이면 zoxide가 통째로 지워진다.
///
/// 증상이 조용해서 이 검사가 필요하다. 히스토리는 멀쩡히 남고 `z`만 아무
/// 디렉터리도 안 배운다 — 게이트가 그것을 보는 자리는 8차 부팅 하나뿐이다.
///
/// 보는 대상이 `histOptionLines()` 전체가 아니라 `PROMPT_COMMAND`를 건드리는
/// 줄인 이유가 있다. zsh 씨앗의 `setopt INC_APPEND_HISTORY`는 훅 두 줄보다
/// 뒤에 있고 그것이 맞다 — `setopt`는 다른 줄과 안 부딪치므로 순서를 요구할
/// 근거가 없다. 규칙과 근거를 맞춰 둔다.
fn expectPromptCommandBeforeHooks(sh: config.Shell) !void {
    const text = sh.rcSeed();
    const hooks = sh.hookLines();

    var last_prompt: ?usize = null;
    var first_hook: ?usize = null;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var idx: usize = 0;
    while (lines.next()) |raw| : (idx += 1) {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (std.mem.startsWith(u8, line, "PROMPT_COMMAND")) last_prompt = idx;
        for (hooks) |h| {
            if (!std.mem.eql(u8, line, h)) continue;
            if (first_hook == null) first_hook = idx;
        }
    }

    // 볼 것이 없으면 그 사실을 적는다. 조용한 초록은 통과와 구분이 안 된다
    // (위험 1, SP-M0 실측 4).
    if (last_prompt == null) {
        std.debug.print(
            "note: the {s} seed touches PROMPT_COMMAND on no line; nothing to order\n",
            .{@tagName(sh)},
        );
        return;
    }
    if (first_hook == null) {
        std.debug.print("FAIL: the {s} seed carries no hook line to order against\n", .{@tagName(sh)});
        return error.BadSeedOrder;
    }
    if (last_prompt.? < first_hook.?) return;
    std.debug.print(
        "FAIL: the {s} seed assigns PROMPT_COMMAND on line {d}, after its first hook on line {d}\n" ++
            "      that assignment wipes the zoxide hook; move it above the hooks\n",
        .{ @tagName(sh), last_prompt.?, first_hook.? },
    );
    return error.BadSeedOrder;
}
```

- [x] Step 4: `main`에서 부른다

SD-M1의 `expectHistOptions` 줄 아래에 둔다.

```zig
    for (std.enums.values(config.Shell)) |sh| try expectHistOptions(sh);

    // ── BH-M1: PROMPT_COMMAND의 순서 ────────────────────────────────────
    //
    // 위 셋(정방향·역방향·개수)이 "그 줄이 있는가"를 보고, 이 줄이 "어디에
    // 있는가"를 본다. bash에서만 볼 것이 생기는 검사이고, 볼 것이 없는 셸에
    // 대해서는 그 사실을 화면에 적는다.
    for (std.enums.values(config.Shell)) |sh| try expectPromptCommandBeforeHooks(sh);
```

- [x] Step 5: 빌드하고 검사를 돌린다

캐시 삭제는 컨테이너 안에서 한다(HANDOFF의 ⚠).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init && zig build && zig build test'
```

`note:` 두 줄(zsh · fish)이 찍히고 `FAIL`이 없어야 한다.

## Task 4: 되돌림 다섯으로 검사가 일하는 것을 본다

Files: 없음(전부 `/tmp` 사본을 `-v`로 마운트한다. 저장소 파일은 한 번도
안 바뀌므로 되돌리는 것을 잊는 경로가 없다)

- [x] Step 1: 다섯을 각각 만들어 돌린다

| | 무엇을 망가뜨리나 | 어느 검사가 죽여야 하나 |
|---|---|---|
| 1 | 씨앗의 그 줄을 `PROMPT_COMMAND='histori -a'`로 | `expectQuietSeed` 정방향 |
| 2 | 씨앗에서만 그 줄을 지우기 | `expectQuietSeed` 역방향 |
| 3 | 씨앗과 `HIST_OPTIONS_BASH`에서 함께 지우기 | `expectHistOptions` 개수 |
| 4 | 둘을 함께 오타로 고치기 | `KNOWN_HIST_OPTIONS` |
| 5 | 씨앗에서 그 줄을 훅 두 줄 아래로 옮기기 | `expectPromptCommandBeforeHooks` |

다섯이 각각 다른 줄에서 죽어야 한다. 같은 줄에서 죽으면 그 검사 중 하나가
값을 안 하고 있다는 뜻이다.

5번이 이 milestone의 새 검사다. 1~4는 SD-M1이 zsh에 대해 한 것과 같은
모양이고, 여기서 다시 하는 이유는 bash 갈래가 zsh 갈래와 다른 코드를
타기 때문이다.

- [x] Step 2: 돌리는 방법

```bash
cp init/src/config.zig /tmp/rev1_config.zig
# /tmp/rev1_config.zig를 고친 뒤
docker run --rm -v "$PWD":/workspace \
  -v /tmp/rev1_config.zig:/workspace/init/src/config.zig:ro \
  -w /workspace tars-devcontainer bash -c '
  cd init && zig build test' 2>&1 | tail -20
```

3·4번은 `config_test.zig` 사본도 함께 마운트해야 한다.

## Task 5: config 체인으로 회귀를 본다

씨앗이 열 줄 남짓 커진다. 설정 디스크를 붙이는 체인이 화면 좌표로 판정하는
자리가 셋이므로, 씨앗이 커진 것이 그 좌표를 밀지 않는지 본다.

씨앗은 파일이지 화면이 아니므로 밀 이유가 없다 — SD-M1에서도 여섯 줄이
커졌는데 하나도 안 밀렸다. 그래도 확인한다.

- [x] Step 1: config 체인 단독으로 돌린다 (부팅 여덟, 약 1분 36초)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash config/check.sh 2>&1 | tail -50
```

`FAIL` 없이 끝나야 한다. 시간이 SD-M2의 1분 36.42초와 비슷해야 한다 —
M1은 타이핑을 안 더하므로 안 늘어야 맞다.

이 초록이 "그 줄이 게스트에서 일한다"를 뜻하지 않는다. 게이트가 bash로 뜨는
자리가 아직 없기 때문이고, 그것을 세우는 것이 BH-M2다.

## Task 6: design을 갱신하고 커밋한다

- [x] Step 1: design의 `Status:`를 "M1까지 했다"로 고친다

- [x] Step 2: BH-M1이 넣은 것을 design에 한 절로 적는다

되돌림 다섯이 각각 어느 줄에서 죽었는지를 적는다. 그것이 검사가 값을 한다는
증거다.

- [x] Step 3: 커밋한다

`git status`로 `M`과 신규를 가른 뒤 add 대상을 좁혀서 지정한다.
