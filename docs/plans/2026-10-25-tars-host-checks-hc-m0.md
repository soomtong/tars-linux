# HC-M0 — `tars-config`의 뼈대를 `config_edit`로 내린다

Date: 2026-10-25
Design: `docs/specs/2026-10-25-tars-host-checks-design.md` 결정 2 · 4 · 6 · 7 · 9 ~ 12
Status: 완료 (2026-10-26) — 루트 게이트 22/22.

## 누가 무엇을 하나

고치는 파일은 셋이다 — `init/src/config_edit.zig`(더한다) · `init/src/config_edit_test.zig`(더한다) · `init/src/config_cli.zig`(뺀다).
`build.zig`는 건드리지 않는다(design 결정 3). lead가 직접 넣는다 — 옮기는 코드가 150줄 안이고, 검사의 want를 옛 코드에서 베끼는
일(결정 9)은 옛 코드와 새 코드를 한 화면에 놓고 하는 것이라 한 사람이 이어서 하는 편이 낫다. Task마다 commit 하나다.

| Task | 무엇을 | 검사 |
|---|---|---|
| 1 | `config_edit`에 순수 함수 여덟과 `Command`, `config_edit_test`에 검사 7 ~ 11. `config_cli`는 그대로 | `zig build test` · (a)는 더한 줄만 |
| 2 | `config_cli`가 그 함수를 부른다 — `main`은 `switch` 하나, `show` · `change` · `check` · `keyTable`의 조각 | 빌드 · (a) 빈 diff · `--color-moved` · config 체인 |
| 3 | 호스트 `fmt` · `ast-check`, mutation 둘, 루트 게이트, 실측 | 22/22 |

## 착수 전에 확정한 것

1. 검사 명령. (a)는 design 결정 2(a)의 서식 문자열 집합이고, `say` · `complain`뿐 아니라 `print` · `bufPrint`도 잡는다 — 옮긴 문장은
   `sink.print(…)`와 `std.fmt.bufPrint(buf, …)`가 되기 때문이다. 기준선은 HEAD `5e3955a`에서 151줄(`config_cli` 61 · `config_edit` 3 ·
   `config_front` 81 · `config_front_edit` 6).

   ```bash
   P='\b(say|complain|print|bufPrint)\(\s*(?:[&\w\[\]\.]+,\s*)?"(?:[^"\\]|\\.)*"'
   F='init/src/config_cli.zig init/src/config_edit.zig init/src/config_front.zig init/src/config_front_edit.zig'
   rg -o --multiline "$P" $F | sed 's/^[^:]*://' | sed 's/^[^"]*//' | sort > /tmp/hc-tc-before.txt          # 151줄, Task 전에 한 번
   rg -o --multiline "$P" $F | sed 's/^[^:]*://' | sed 's/^[^"]*//' | sort | diff /tmp/hc-tc-before.txt -    # Task 1 뒤: `>`만, Task 2 뒤: 빈 출력
   docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c 'zig build && zig build test'
   git diff --stat; git diff --color-moved=dimmed-zebra init/src/
   make check CHAIN=config > /tmp/config.out 2>&1; echo "exit=$?"
   ```

   둘째 `sed`는 Task 1에서 더했다 — `rg -o`는 호출 접두사(`say(` · `bufPrint(&pair_buf, `)까지 뽑는데, 문장을 옮기면
   `say("…"`가 `sink.print("…"` · `bufPrint(buf, "…"`가 되어 글자가 같아도 diff가 남는다. 리터럴만 견준다. 그리고 `$F`는 zsh에서
   단어로 쪼개지지 않으므로 bash로 돈다(`/tmp/hc-fmt.sh`로 묶었다).

   Task 1 뒤의 diff에 `>`만 있는 것은 옛 문장이 아직 `config_cli`에 있고 새 사본이 `config_edit`에 더해졌기 때문이다 — 그 `>` 줄
   하나하나가 `<`로 짝을 지어 Task 2에서 사라져야 한다. 둘 다 끝나면 빈 출력이다. 파일 단위가 아니라 네 파일 합이라 글자가 조금만
   달라도 `<` · `>` 한 쌍으로 드러난다.

   config 체인이 이 milestone의 글자를 보는 자리 — `nothing was written`(521) · `init would say "unknown shell 'fsh', …"`(526) ·
   `shared -> pane`(535) · `get`의 값(541) · `init reads every line without a complaint`(548) · `list`의 열두 행(560, `TC_LIST_WANT`) ·
   `keyboard: apple -> pc`(598) · `# the screen keeps keyboard=apple clipboard=shared until tars-config reload terminal`(613).
   여덟 가운데 `show`의 키 줄 · `change`의 결과 줄 · `check`의 마무리 · `list`의 표가 Task 2에서 옮긴 함수의 출력이다.

2. `Command`의 모양(design 결정 4). `disk.Command`와 같은 union(enum)이고 거절도 칸이다. 슬라이스는 argv를 가리킨다.

   ```zig
   pub const PAIRS_MAX = 16;
   pub const Rest = []const [*:0]const u8;

   pub const Command = union(enum) {
       show,
       help,
       version,
       list,
       /// "언세팅"은 reset이다. unset은 "줄을 지운다"로 읽히는데 reset은 기본값을 적는다 — 그 차이를 말하고 usage(TC 결정 1의 덧붙임).
       unset,
       /// `reload` · `reload terminal`. true가 terminal.
       reload: bool,
       check,
       wifi: Rest,
       ssh: Rest,
       ssh_key: Rest,
       firewall: Rest,
       dictation: Rest,
       /// 공백을 벗긴 키. 아는 키인지는 `get`이 `isKey`로 본다(지금과 같다).
       get: []const u8,
       /// `set K=V…` · `reset K…`가 같은 칸이다 — `change`는 쌍만 받는다.
       change: []const Pair,
       usage,
       /// `set`의 인자에 `=`가 없다. 그 인자다.
       no_equals: []const u8,
       /// `reset`의 모르는 키.
       unknown_key: []const u8,
   };

   /// argv[1..]을 가른다. `set`의 쌍은 pairs에, `reset`의 기본값 글자는 default_bufs에 짓는다 — 둘 다 호출자의 스택이다.
   pub fn parseCommand(args: Rest, pairs: *[PAIRS_MAX]Pair, default_bufs: *[PAIRS_MAX][VALUE_MAX]u8) Command
   ```

   가르는 규칙은 지금 `main`의 것 그대로다 — `help` · `-h` · `--help`와 `version` · `--version` · `-V`는 뒤에 인자가 있으면 `usage`,
   `list` · `check`도 같다, `reload`는 인자 0이면 false · `terminal` 하나면 true · 그 밖은 `usage`, `get`은 인자 하나가 아니면 `usage`
   (키는 `trim`), `set` · `reset`은 인자 0이거나 `PAIRS_MAX`를 넘으면 `usage`, `set`의 첫 `=` 없는 인자는 `no_equals`, `reset`의
   `valueText`가 null인 키는 `unknown_key`. 모르는 동사는 `usage`. 앞문 다섯은 `argv[2..]`를 그대로 담는다.

3. 여러 줄을 찍는 함수의 sink(design 결정 6에서 달라진 자리). design은 "여러 줄을 한 버퍼에 이어 짓고 `writeAll` 한 번"이라 했는데
   `check`의 줄마다 `parse` 출력은 파일의 줄 수에 비례해 상한이 100KB를 넘을 수 있다(4096바이트 안의 2천 줄 × 60바이트). 버퍼를
   그만큼 잡거나 넘치면 자르는 것은 둘 다 지금 동작(줄마다 `say`, 자르지 않음)과 다르다. 그래서 여러 줄 함수 셋은 `sink: anytype`을
   받고 `sink.print(fmt, args)`를 줄마다 부른다 — `control.zig`의 anytype과 `Toggles.parse`의 sink가 선례다. 시스템 콜 쪽의 sink는
   `say`를 부르는 빈 struct, 검사의 sink는 `control.Out`(`print`의 서명이 같다 — reload_test가 그 `bytes()`를 이미 비교한다).

   ```zig
   // config_cli.zig
   const Say = struct {
       pub fn print(_: Say, comptime fmt: []const u8, args: anytype) void {
           say(fmt, args);
       }
   };
   ```

   `write` 횟수도 그대로다(한 줄에 한 번). 한 줄짜리 `changeLine`만 버퍼 모양이다(결정 6의 한 줄 모양).

4. 내려가는 함수 여덟과 서명. 모두 `config_edit.zig`의 `pub`이다.

   | 함수 | 지금 자리 | 서명 |
   |---|---|---|
   | `parseCommand` | `main` 550~622 | 확정 2 |
   | `nowValue` | 229~236 | `fn nowValue(reply: []const u8, key: []const u8) ?[]const u8` |
   | `screenLine` | 238~242 | `fn screenLine(reply: []const u8) ?[]const u8` |
   | `changeLine` | `change` 440~446의 `say` 둘 | `fn changeLine(buf: *[LINE_MAX]u8, key: []const u8, old: []const u8, old_default: bool, new: []const u8) []const u8` |
   | `keyTable` | 122~130 | `fn keyTable(sink: anytype) void` |
   | `showKeyLines` | `show` 293~300의 `for` | `fn showKeyLines(sink: anytype, text: []const u8, c: *const config.Config, now: ?[]const u8) void` |
   | `checkLines` | `check` 494~516의 `while`과 `for` | `fn checkLines(sink: anytype, text: []const u8) usize` |

   `changeLine`의 글자 — `{key}: {new} (unchanged)\n`(old와 new가 같을 때) · `{key}: {old}{ (default)} -> {new}\n`. 키 13 + 값 64 × 2 +
   글자 20이 `LINE_MAX` 256 안이라 `bufPrint`는 `catch unreachable`이다(PID 1 코드가 아니다 — `unreachable` 금지는 `reload.zig`의 규칙).
   `showKeyLines`는 `text`를 `MAX_FILE`로 자르는 것(`setByFile`에 주는 조각)을 안에서 한다 — 지금 `show`가 그렇게 한다.
   `checkLines`는 `heard`를 줄마다 비우고 `config.parse(raw)`를 부른다 — 전역을 만지는 자리가 `judge` 옆으로 간다(design 위험 3).
   `check`의 길이 줄(`is {d} bytes or more`)은 `CONF_PATH`를 찍어 `config_cli`에 남는다 — 조건 하나의 한 줄이고 그 경로는 시스템 콜
   쪽의 것이다.

5. Task 2 뒤의 `main`.

   ```zig
   pub fn main(init: std.process.Init.Minimal) u8 {
       const argv = init.args.vector;
       var pairs: [edit.PAIRS_MAX]edit.Pair = undefined;
       var default_bufs: [edit.PAIRS_MAX][edit.VALUE_MAX]u8 = undefined;
       return switch (edit.parseCommand(if (argv.len > 1) argv[1..] else argv[0..0], &pairs, &default_bufs)) {
           .show => show(),
           .help => help(),
           .version => blk: {
               say("TARS {s}\n", .{build_info.version});
               break :blk EXIT_OK;
           },
           .list => list(),
           .unset => blk: {
               complain("there is no unset; reset KEY writes the default value into that key's line (the line stays)", .{});
               break :blk usage();
           },
           .reload => |terminal| reloadInit(terminal),
           .check => check(),
           .wifi => |rest| front.wifi(rest),
           .ssh => |rest| front.ssh(rest),
           .ssh_key => |rest| front.sshKey(rest),
           .firewall => |rest| front.firewall(rest),
           .dictation => |rest| front.dictation(rest),
           .get => |key| get(key),
           .change => |p| change(p),
           .usage => usage(),
           .no_equals => |arg| blk: {
               complain("'{s}' has no '='; set takes KEY=VALUE", .{arg});
               break :blk EXIT_USAGE;
           },
           .unknown_key => |key| unknownKey(key),
       };
   }
   ```

   `main`의 주석 셋(`BV-M0` · `unset` · `앞문 넷`)은 `Command` 칸의 문서 주석으로 간다(design 결정 12). `version`의 글자와 `unset`의
   한 줄은 시스템 콜 쪽에 남는다 — 조건 없이 한 줄이다(결정 6의 기준).

6. 검사 7 ~ 11의 want는 Task 1에서 지금의 `config_cli.zig`에서 베낀다(design 결정 9). 베끼는 서식 문자열은 아래다 — 검사가 이 글자를
   `expectText`로 그대로 비교한다.

   | 검사 | 베끼는 줄 | 서식 |
   |---|---|---|
   | 9 `changeLine` | 441 · 443 | `"{s}: {s} (unchanged)\n"` · `"{s}: {s}{s} -> {s}\n"`(셋째가 `" (default)"` 또는 `""`) |
   | 10 `keyTable` | 127 · 128 | `"{s}={s}"` · `"  {s:<26} {s}\n"` |
   | 10 `showKeyLines` | 297 · 299 | `"{s}{s}={s}\n"`(첫째가 `"#"` 또는 `""`) · `"#   init uses {s}={s} now; tars-config reload applies the line above\n"` |
   | 11 `checkLines` | 503 · 512 ~ 514 | `"line {d}: {s}\n"` · `"{s} is on {d} lines ("` · `"{s}{d}"` · `"); the last one wins\n"` |

   검사 8(`nowValue` · `screenLine`)은 `reload.configReply(&out, live, screen)`가 지은 답을 그대로 읽는다(design 결정 7) — `live`는
   `OTHER`의 값 열둘, `screen`은 기본값. `nowValue(reply, "shell")`이 `"zsh"`, `screenLine(reply)`가 `" keyboard=apple timezone=UTC …"`
   꼴(대기 중인 키마다 ` key=value`), `screen`과 `live`가 같으면 `screenLine`이 null. `config_edit_test.zig`가 `reload.zig`를 import한다
   — `config_edit.zig`는 안 한다.

7. mutation 둘(Task 3, design 결정 10). 사본을 `-v …:ro`로 덮어 `zig build test`만 돈다 — 게이트까지 안 간다.

   | mutation | 비틀 것 | 잡아야 할 검사 |
   |---|---|---|
   | m1 가르기 | `parseCommand`의 `reload`가 `terminal`이 아닌 한 단어도 true로 받는다(`eql`을 뺀다) | 7 — `reload x`가 `usage`여야 한다 |
   | m2 문장 | `changeLine`의 `" (default)"`를 `""`로 | 9 — `shell: fish (default) -> zsh`를 기대 |

## Task 1: `config_edit`에 여덟, `config_edit_test`에 7 ~ 11

`config_cli.zig`는 한 줄도 안 고친다. 순서 — (1) `/tmp/hc-tc-before.txt`를 만든다(확정 1). (2) `config_edit.zig` 끝에 "── 명령 ──"
절을 더해 확정 2의 `Command` · `parseCommand`와 확정 4의 일곱을 쓴다. 문장은 `config_cli`에서 글자 그대로 옮겨 적고, 주석도 함께
간다(`main`의 셋 · `nowValue` · `screenLine`의 둘 · `keyTable`의 하나 · `show`의 TC-M2 주석 · `check`의 "줄마다 init의 파서에"와
"같은 키가 둘 이상이면"). (3) `config_edit_test.zig`에 검사 7 ~ 11을 더한다 — want는 확정 6의 글자다.

검사 7 `parseCommand` — 동사 열넷이 각자의 칸으로(인자 없음 → `show`, `help` · `-h` · `--help` → `help`, `version` · `--version` ·
`-V` → `version`, `list` · `check` · `unset`, `reload` → `.reload = false` · `reload terminal` → true, `wifi a b` → `.wifi`의 길이 2,
`get shell` → `"shell"`(공백 포함 ` shell `도), `set shell=zsh net=dhcp` → 쌍 둘(값 `trim`), `reset shell` → 쌍 하나에 값 `"fish"`).
거절 — `help x` · `version x` · `list x` · `check x` · `reload x` · `get` · `get a b` · `set` · `reset` · `frobnicate` · 쌍 열일곱 → `usage`,
`set shell` → `.no_equals = "shell"`, `reset nope` → `.unknown_key = "nope"`.

검사 8 · 9 · 10 · 11은 확정 6이다. 검사 11은 세 파일로 본다 — 깨끗한 파일(0, 출력 없음), `shell=fsh` 한 줄(1, `line 1: ` + `heard.first()`
— 그 말은 `config.parse("shell=fsh")`를 따로 불러 `heard.first()`에서 받는다), `shell=zsh\n#x\nshell=fish\n`(0, `shell is on 2 lines
(1, 3); the last one wins\n` — 중복은 문제로 세지 않는다, 지금 코드가 그렇다).

검사 — `zig build test`(컨테이너)가 PASS, (a) diff가 `>`만. `git diff --stat`으로 두 파일에 더한 줄만 있고 지운 줄이 0인지 본다.
commit: `HC-M0: Add the tars-config command parser and sentence functions to config_edit`.

## Task 2: `config_cli`가 부른다

(1) `main`을 확정 5로 바꾼다. `PAIRS_MAX` 상수는 지운다(`edit.PAIRS_MAX`). (2) `nowValue` · `screenLine`을 지우고 부르는 자리 셋
(`show` 둘 · `reloadInit` 하나)을 `edit.`로. (3) `keyTable`을 지우고 `help` · `list`가 `edit.keyTable(Say{})`. (4) `show`의 `for`를
`edit.showKeyLines(Say{}, cur.text, &c, now)`로 — 그 앞의 `line_buf` 선언도 간다. (5) `change`의 마지막 `for` 안 `say` 둘을
`changeLine` 한 줄로 — `_ = writeAll(1, edit.changeLine(&line_buf, p.key, old_text[i], old_default[i], canon[i]))`. (6) `check`의
`while`과 `for`를 `problems += edit.checkLines(Say{}, text)`로.

지우는 편집이라 `git diff | rg '^-'`로 지운 줄을 읽는다 — 옮긴 함수 넷의 본문과 `main`의 사다리, `PAIRS_MAX`, 주석이어야 하고 그
밖의 `-`가 있으면 멈춘다. `--color-moved`에서 진한 줄은 `switch`의 갈래 · `Say` · `edit.` 호출 여섯 안이어야 한다.

검사 — 빌드, (a) 빈 diff, config 체인(확정 1의 여덟 자리). commit: `HC-M0: Route tars-config through parseCommand and the moved sentences`.

## Task 3: 호스트 검사 · mutation · 루트 게이트 · 닫기

1. 호스트 0.17 — `zig fmt --check init/src` · `ast-check`(lessons "범용 명령").
2. mutation 둘(확정 7). 둘 다 `FAIL:` 한 줄과 0이 아닌 코드여야 한다. 되돌리지 않는다 — 사본이라 저장소는 그대로다.
3. 루트 게이트(`run_in_background`, 10분쯤). 도는 동안 HC-M1 plan을 쓴다 — 게이트 결과를 못 본 채 쓴 것이므로 끝나면 대조한다.
4. 22/22면 design `Status:`의 M0 자리와 이 plan의 `Status:` · "실측한 것"을 채운다. decisions · completed · HANDOFF는 M2 뒤다.

## HC-M0가 실측한 것

2026-10-26. commit은 Task 1 `c17e1a5` · Task 2 `770b3e8`.

1. (a) 서식 문자열 — 기준선 151줄(`config_cli` 61 · `config_edit` 3 · `config_front` 81 · `config_front_edit` 6). Task 1 뒤 `>` 열
   줄(`keyTable` 2 · `checkLines` 4 · `changeLine` 2 · `showKeyLines` 2), Task 2 뒤 빈 출력.
2. `git diff --stat` — Task 1은 `config_edit.zig` +186 · `config_edit_test.zig` +211, 지운 줄 0. Task 2는 `config_cli.zig` +51 −151
   (622 → 522줄). `config_edit.zig`는 299 → 485줄 — design 위험 6의 "450줄쯤"을 조금 넘었고 500 안이다.
3. `--color-moved=dimmed-zebra`(`HEAD~1` 대비, Task 1 + 2)에서 `config_cli`의 진한 줄은 `Say` · `edit.` 호출 여섯 · 배열 다섯의
   `edit.PAIRS_MAX` · `switch`의 갈래뿐이다. `config_edit` 쪽의 진한 줄은 `say(` → `sink.print(`, `edit.`을 뗀 것처럼 한 글자라도
   바뀐 줄이다 — 글자 그대로인지는 (a)가 본다.
4. `zig build && zig build test`(컨테이너, 첫 회 1분 17초). `config_edit_test`가 새 다섯 줄과 `PASS`.
5. mutation 둘 — 사본을 `-v …:ro`로 덮어 `zig build test`만. 둘 다 exit 1, 저장소는 깨끗하다.
   - m1(`reload`의 `eql`을 뺀다): `FAIL: parseCommand reload… gave reload, want usage`
   - m2(`" (default)"` → `""`): `FAIL: changeLine from the default:`
6. config 체인(`make check CHAIN=config`, Task 2 뒤): PASS, 5분 20초.
7. 호스트 0.17 `zig fmt --check` · `ast-check`: 깨끗하다.
8. 루트 게이트 — 첫 회 21/22(10분 18초). install 체인(DC-M2) 부팅 7의 판정 17이 빨갰다: 22 lane이 함께 도는 부하에서
   initramfs 풀기가 5.5초(0.74 → 6.25초)라 4초 늦게 붙는 USB 디스크(`sda2` 6.30초)가 `/init`(6.35초)보다 먼저 섰고, init이 기다릴
   틈이 없었다. 이 milestone은 커널도 init의 기다림도 안 건드렸고 initrd 크기도 같다(`96932K` 둘 다). install 체인 단독 재실행은 PASS
   (풀기 3.1초, `appeared after 1300ms`, 4분 2초). 둘째 회 22/22(11분 27초 — prebuild 361초 + lanes 325초, 부팅 7은 1500ms).
   로그 `out/gate-logs/20261025-154845/`.

plan과 달랐던 것 셋.

- 확정 1의 (a) 명령 — 위 확정 1의 덧붙임.
- Zig 0.17에서 배열 반복 `**`가 문법 에러다(`binary operator '*' has whitespace on one side`). 검사 7의 쌍 열일곱과 검사 9의 가장
  긴 값은 `@splat`으로 짓는다 — 저장소의 다른 검사(`environ_test` · `screen_args_test`)가 이미 그렇게 한다.
- 검사 11의 `shell=fsh`는 주석 한 줄 뒤에 두어 `line 2:`로 본다(줄 번호를 함께 본다). 기대 말은 `heard.first()`가 아니라 검사 2가
  이미 박은 글자 그대로다.
