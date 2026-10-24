# SA-M0 — init과 terminal이 같은 `screen_args.zig`를 컴파일한다

Date: 2026-10-24
Design: `docs/specs/2026-10-24-tars-screen-args-design.md`
Status: 진행 중. 값은 맨 아래 "SA-M0이 실측한 것".

## 누가 무엇을 하나

새 파일 둘, 편집 아홉이다. 편집 하나하나는 작고 서로 묶여 있어(한쪽 enum을 지우면 다른 쪽이 그 자리에서 컴파일을 막는다) lead가
직접 넣는다. 매 편집 뒤 `git diff --stat`, 지우는 편집은 `git diff | rg '^-'`로 본다. 빌드는 컨테이너에서 한다 — init은 `zig build`
와 `zig build test`, terminal은 `prepare.sh`가 부르는 `zig build`와 `zig build test`.

| 파일 | 무엇을 |
|---|---|
| `shared/screen_args.zig` | 새 파일 — 값의 종류 다섯 · `Toggles.parse` · `Toggles.arg` · `TOGGLE_ARG_MAX` · `Slot` · `ARGC` · 기본값 |
| `shared/screen_args_test.zig` | 새 파일 — 왕복 검사(design 결정 6) |
| `init/build.zig` | `screen_args` 모듈 하나를 만들어 exe 둘과 test들에 붙이고, `screen_args_test`를 `test` step에 더한다 |
| `terminal/build.zig` | 같은 모듈을 `exe_mod`와 test들에 붙인다 |
| `init/src/config.zig` | enum 다섯 · `Toggles` · `TOGGLE_ARG_MAX`를 지우고 공유 이름을 재export. `hangul_toggle` 파싱은 `Toggles.parse(.file, …)` |
| `init/src/main.zig` | `TERM_*_SLOT` 일곱을 지우고 `Slot`으로. `Child.argv`의 길이는 `ARGC`. `arg()` 호출 여덟은 그대로다(공유 enum에도 `arg()`가 있다) |
| `init/src/net.zig` · `clock.zig` · `wifi.zig` | `[9:null]` → `[screen_args.ARGC:null]` |
| `init/src/config_test.zig` | `arg()` == `@tagName` 반복문 둘을 지운다. `Toggles.parse` 호출 셋에 `.file`과 sink를 준다 |
| `terminal/src/hangul.zig` | `Layout`이 별명이 되고 `lookup` · `nonSyllable` · `carriesFinal` · `tenseByRepeat`가 자유 함수가 된다 |
| `terminal/src/input.zig` | `LatinLayout` · `Toggles` · `TOGGLE_ARG_MAX`가 별명. `ToggleKey` · `parseToggles` · `togglesArg` · `appendToggleName`을 지운다. 메서드 호출 두 줄 |
| `terminal/src/clipboard.zig` | `Scope`가 별명 |
| `terminal/src/main.zig` | `args[n]` 여덟을 `Slot`으로. 키보드가 enum이 된다. `togglesArg` → `toggles.arg` |
| `terminal/src/hangul_test.zig` | `layout.lookup(ch)` → `hangul.lookup(layout, ch)` |

## 착수 전에 확정한 것

1. 공유 파일의 API. 이름은 init 쪽 호출자에 맞춘다 — `arg()`가 열 곳에서 불리고 terminal의 `togglesArg`는 한 곳이다.

   ```zig
   pub const Keyboard = enum { apple, pc, pub fn arg(self) [:0]const u8 };      // arg는 @tagName(self)
   pub const HangulLayout = enum { dubeol, sebeol_3p3, shin_p2, shin_pcs, … };
   pub const LatinLayout = enum { qwerty, dvorak, … };
   pub const ClipboardScope = enum { shared, pane, … };
   pub const ToggleKey = enum { hangul_key, shift_space, capslock_tap, lctrl_tap, esc_latin };
   pub const TOGGLE_ARG_MAX = 64;
   pub const Toggles = struct {
       hangul_key … esc_latin: bool = false,
       pub const Source = enum { file, argv };
       pub fn parse(comptime source: Source, text: []const u8, sink: anytype) Toggles;  // sink.unknown(name)
       pub fn arg(self: Toggles, buf: []u8) [:0]const u8;
   };
   pub const ignore_unknown = …;   // unknown()이 아무것도 안 하는 sink. terminal이 쓴다
   pub const Slot = enum(u8) { shell = 1, flag = 2, keyboard = 3, device = 4, hangul = 5, latin = 6, toggles = 7, clipboard = 8 };
   pub const ARGC = 9;
   pub const default_keyboard = .apple … default_toggles_arg = "hangul_key,…,esc_latin";
   ```

   `parse(.file, …)`는 `esc_latin`을 모르는 이름으로 sink에 넘긴다(EL design 결정 1 그대로). `parse(.argv, …)`는 다섯을 다 받는다.
   `none`과 빈 항목은 둘 다 조용히 건너뛴다.
2. sink는 `anytype`이다. init의 `config.zig`는 `unknown(name)`이 `log("unknown hangul_toggle '{s}', ignored", …)`를 부르는 빈
   struct를 넘긴다 — 지금 로그 글자와 같다. terminal과 검사는 `ignore_unknown`을 넘긴다.
3. 모듈은 build.zig마다 `b.createModule(.{ .root_source_file = b.path("../shared/screen_args.zig") })` 하나이고 target · optimize를
   주지 않는다(design 확인 4). test 파일은 같은 디렉터리의 `screen_args.zig`를 파일로 import한다 — 검사 모듈의 뿌리가 `shared/`라
   된다. 다른 test처럼 `addExecutable` + `addRunArtifact`이고 `main`이 에러를 돌려준다(`version_test`의 모양).
4. `Rescue.slot`은 M0에서 `usize` 그대로다. terminal의 값은 `@intFromEnum(Slot.flag)`, 콘솔 셸의 `CONSOLE_FLAG_SLOT`(1)은 그대로다.
5. terminal의 `keyboard=` 로그 줄은 `@tagName(keyboard)`를 찍는다. init이 거른 값만 오므로 글자는 같다. 손으로 띄워 엉뚱한 값을 주면
   전에는 그 글자가 그대로 찍히고 `swap_alt_meta=false`였는데, 이제 `apple`로 찍힌다 — 기본값으로 떨어진 것이 로그에 보이는 쪽이 맞다.
6. 게이트 체인 스크립트는 한 줄도 안 고친다(design 결정 8).

## Task 1: `shared/screen_args.zig` · `shared/screen_args_test.zig`

검사가 보는 것(design 결정 6) — 다섯 종류마다 모든 값의 `arg()` → `stringToEnum` 왕복, `Toggles` 서른두 조합의 `arg` → `parse(.argv)`
왕복(`none` 포함), `parse(.file)`이 `esc_latin`을 sink에 넘기고 켜지 않는 것, `parse(.argv)`가 켜는 것, 순서 정규화, 공백 떼기,
`Slot`의 값이 전부 `ARGC` 안이고 겹치지 않는 것(`comptime`), `TOGGLE_ARG_MAX`가 가장 긴 목록보다 큰 것(`comptime`).

## Task 2: 두 build.zig

init — 모듈을 만들고 `exe_mod` · `config_cli_mod`와 `config.zig`를 트리에 둔 test 모듈들에 `addImport("screen_args", …)`. 빠진 곳은
컴파일러가 말한다. `screen_args_test`를 만들어 `test_step`에 더한다. terminal — `exe_mod`와 test 다섯(`clipboard_test` · `hangul_test` ·
`input_test` · `status_test` · `vt_test`)에 붙인다. 역시 빠진 곳은 컴파일러가 말한다.

## Task 3: init 쪽

`config.zig` — enum 다섯과 `Toggles` · `ToggleKey` · `TOGGLE_ARG_MAX` · `appendToggleName`을 지우고 재export 줄 일곱.
`parse`의 `hangul_toggle` 갈래가 `Toggles.parse(.file, value, LogUnknown{})`. 문서 주석 가운데 "짝이어야 한다 … 컴파일러가 못
잡는다"는 문장은 사실이 아니게 되므로 지운다. `main.zig` — 상수 일곱 삭제, `Slot`, `ARGC`. 서비스 셋의 `*_ARGV`. `config_test` — 확정 1.

## Task 4: terminal 쪽

`hangul.zig` — `pub const Layout = screen_args.HangulLayout;`와 자유 함수 넷. `input.zig` — 별명 셋, 삭제 넷, `hangul.lookup` ·
`hangul.nonSyllable` 호출 둘. `clipboard.zig` — 별명. `main.zig` — `args[n]`을 `argAt(args, .slot)`으로 읽고 키보드를 enum으로,
`toggles.arg(&toggle_buf)`. `hangul_test` 한 줄. `clipboard_test`의 검사 5(`stringToEnum` 이름 둘)는 남긴다 — 이제 공유 enum을 보는
검사라 거짓이 될 수 없지만 `workspace`가 없다는 것(CB 비목표 1)은 여전히 말한다.

## Task 5: 검사와 게이트

1. 컨테이너에서 `cd init && zig build && zig build test`, `cd terminal && ./prepare.sh && zig build test`.
2. design 위험 1 — `shared/screen_args.zig`에 공백 한 줄을 넣고 두 `zig build`를 다시 돌려 바이너리의 mtime이 바뀌는지 본다. 되돌린다.
3. 호스트 0.17 `zig fmt --check`와 `ast-check`를 `shared/` · 고친 파일에.
4. 루트 게이트(`run_in_background`, 약 10분). 22/22면 닫는다.
5. 닫을 때 — design `Status:`, `docs/guides/completed.md` 한 행, `docs/decisions/project_screen_args.md` · `MEMORY.md` 한 줄,
   `HANDOFF.md`, lessons "핵심 파일"의 세 줄, 소개 페이지는 M1 뒤에 한 번.

## SA-M0이 실측한 것

(끝나면 적는다)
