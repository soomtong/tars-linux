# TARS Screen Args — Design

Date: 2026-10-24
Status: SA-M0 끝났다(2026-10-24, 루트 게이트 22/22 — prebuild 339초 + lanes 294초). plan은 `docs/plans/2026-10-24-tars-screen-args-sa-m0.md`,
기억은 `docs/decisions/project_screen_args.md`. 구현 중 design과 달라진 자리 — 결정 4의 `arg()`는 지우지 않고 `@tagName` 한 줄로
남겼다(init 호출자 열 곳이 그대로다). 0.17 `zig fmt`가 `@intFromEnum`을 `@backingInt`로 바꾼다. SA-M1은 `-sa-m1.md`(초안).

HANDOFF "다음 후보"의 첫 항목에서 시작한다(2026-10-24 프로젝트 점검이 남긴 다섯 가운데 추천 1순위).

> init → terminal 인터페이스가 위치 기반 argv 9칸이고 자판 enum 이름을 문자열로 넘겨 컴파일러가 짝을 못 잡는다 —
> `key=value` 인자나 두 쪽이 import하는 공유 모듈 하나.

## 한 줄 요약

init이 terminal에 넘기는 값의 종류(자판 · 키보드 · 전환 키 · 클립보드 범위)와 argv의 자리 번호를 파일 하나
`shared/screen_args.zig`에 두고, init과 terminal이 같은 파일을 named module로 import한다. 지금 네 쌍의 enum이 두 프로그램에
한 벌씩 있고 둘을 잇는 것이 문자열과 주석뿐인데, 그 뒤로는 한 벌이라 어긋날 자리가 없고 "쓰는 쪽 → 읽는 쪽" 왕복을 호스트
검사 하나가 본다.

## 배경

terminal은 설정 파일을 읽지 않는다. `/config/tars.conf`의 파서는 PID 1 한 벌이고(CP, `project_config_persistence`), terminal이
알아야 할 값은 init이 fork · execve의 argv에 실어 보낸다. 칸은 IP-M2의 넷에서 CB-M0의 아홉까지 기능이 붙을 때마다 하나씩 늘었다.

| 자리 | 값 | init이 쓰는 곳 | terminal이 읽는 곳 |
|---|---|---|---|
| 0 | `/terminal` | `TERMINAL_PATH` | — |
| 1 | 셸 경로 | `shell_path` | `args[1]` |
| 2 | 셸에 넘길 플래그(`--no-config` · `none`) | `shell_flag`, 탈출로가 덮는 자리 | `args[2]` |
| 3 | 키보드 종류 | `config.Keyboard.arg()` | `args[3]`을 `"pc"`와 문자열 비교 |
| 4 | 키보드 장치 경로 | `devices.resolveKeyboard` | `args[4]` |
| 5 | 한글 자판 | `config.HangulLayout.arg()` | `stringToEnum(hangul.Layout, args[5])` |
| 6 | 영문 자판 | `config.LatinLayout.arg()` | `stringToEnum(input.LatinLayout, args[6])` |
| 7 | 한/영 전환 키 목록 | `Config.terminalToggles` → `config.Toggles.arg()` | `input.parseToggles(args[7])` |
| 8 | 클립보드 범위 | `config.ClipboardScope.arg()` | `stringToEnum(clipboard.Scope, args[8])` |

같은 enum이 두 벌이다 — `config.HangulLayout` ↔ `hangul.Layout`, `config.LatinLayout` ↔ `input.LatinLayout`,
`config.ToggleKey` · `Toggles` ↔ `input.ToggleKey` · `Toggles`, `config.ClipboardScope` ↔ `clipboard.Scope`. 키보드는 terminal 쪽에
enum이 없고 문자열 하나를 비교한다. 두 벌이 짝이어야 한다는 사실은 양쪽 문서 주석에 네 번 넘게 적혀 있고, 모두 같은 말로 끝난다 —
"둘을 잇는 것은 argv의 문자열 하나뿐이라 컴파일러가 못 잡는다". 자리 번호도 같은 처지다. init의 `TERM_*_SLOT` 상수 일곱과 부팅의
argv 리터럴과 `doReloadTerminal`의 대입 일곱 줄과 terminal의 `args[n]` 여덟 줄이 주석으로만 묶여 있고, 어긋나면 "탈출로가 키보드
종류 자리를 덮어쓴다".

### 지금 모양을 한 줄로

init이 terminal을 띄울 때 execve에 넘기는 argv는 실제로 이렇게 생겼다(설정 디스크가 있고 기본값 그대로일 때).

```
/terminal /usr/bin/fish none apple /dev/input/event2 shin_pcs qwerty hangul_key,shift_space,capslock_tap,lctrl_tap,esc_latin shared
   [0]        [1]       [2]  [3]        [4]            [5]     [6]                    [7]                             [8]
```

여기서 `shin_pcs`라는 글자는 init 쪽 `config.HangulLayout` enum의 이름을 `arg()`가 문자열로 바꾼 것이고, terminal은 그 글자를
받아 자기 쪽 `hangul.Layout` enum으로 `stringToEnum`을 해서 되돌린다. 두 enum은 서로 다른 프로그램 안에 따로 선언되어 있다. 컴파일은
init과 terminal이 각자 하므로, 한쪽 enum의 이름을 바꾸거나 하나를 더해도 다른 쪽은 아무 에러 없이 컴파일된다. 어긋남은 부팅해서
로그를 봐야 드러나고, 그때 증상은 "설정을 적었는데 기본 자판으로 뜬다"다 — terminal의 `stringToEnum`이 null을 주면 `orelse`가
기본값으로 떨어지기 때문이다.

자리 번호도 같은 방식으로만 묶여 있다. init이 "5번 칸이 한글 자판"이라고 상수에 적고, terminal이 "`args[5]`가 한글 자판"이라고
코드에 적는다. 둘을 잇는 것은 주석이다.

이 모양이 지금까지 사고를 낸 적은 없다. 그래도 지금 고치는 이유는 둘이다. 다음 기능(부분 갱신 · WP-M3)이 이 자리에 칸을 더할
것이고, 칸을 더할 때마다 네 파일의 숫자와 주석을 손으로 맞추는 일이 반복된다. 그리고 "init이 쓴 것을 terminal이 그대로 읽는다"를
증명하는 검사가 지금은 존재할 수 없다 — 두 반쪽이 다른 프로그램에 있어서, `config_test`는 `arg()`가 `@tagName`과 같은지만 보고
`clipboard_test`는 이름 둘이 `stringToEnum`을 통과하는지만 본다. 공유 모듈이 생기면 그 검사가 한 프로세스 안에 들어온다.

## 착수 전에 확인한 것

2026-10-24, HEAD `c3e1f2e`.

1. init의 `Child.argv`는 `[9:null]?[*:0]const u8`이고 terminal의 칸을 쓰는 자리는 둘이다 — `main()`의 `children[0]` 리터럴과
   `doReloadTerminal`의 대입 일곱 줄(TC-M3). 자리 번호는 `TERMINAL_FLAG_SLOT`(2)과 `TERM_SHELL_SLOT`(1) · `TERM_KEYBOARD_SLOT`(3) ·
   `TERM_HANGUL_SLOT`(5) · `TERM_LATIN_SLOT`(6) · `TERM_TOGGLES_SLOT`(7) · `TERM_CLIPBOARD_SLOT`(8)이다. 4번(장치 경로)은 reload가
   안 건드린다. 같은 배열 타입을 쓰는 상수가 셋 더 있다 — `net.DHCPCD_ARGV` · `clock.CHRONYD_ARGV` · `wifi.WIFI_ARGV`.
2. terminal은 `init.minimal.args.vector`를 `args[1]`부터 `args[8]`까지 자리로 읽고, 칸이 없으면(손으로 띄웠을 때) 기본값을 쓴다.
   기본값 다섯이 terminal 쪽에도 글자로 한 벌 있다(`shin_pcs` · `qwerty` · `shared` · `apple` · 전환 키 다섯의 목록).
3. 0.17의 `@tagName`은 `*const [N:0]u8`, 즉 sentinel이 있는 문자열을 준다(호스트 0.17로 확인). `config.zig`의 `arg()` 넷은
   "@tagName은 sentinel이 없는 슬라이스를 준다"는 전제로 switch를 손으로 썼는데, 그 전제가 지금은 틀리다. 넷 다 `@tagName`으로
   바꿔도 된다.
4. Zig는 모듈 뿌리 밖의 파일을 `@import`하지 못한다. 그러나 `b.createModule(.{ .root_source_file = b.path("../shared/x.zig") })`는
   0.17에서 된다 — 호스트 0.17로 형제 디렉터리의 파일을 named module로 붙여 빌드 · 실행했다. `.target`을 주지 않은 모듈 하나를
   x86_64 musl 게스트 exe와 호스트 test 양쪽에 `addImport`해도 된다(같은 실험에서 둘 다 통과). 모듈 하나를 만들어 두 곳에 붙이면 된다.
5. named module은 그것을 쓰는 모듈마다 `addImport`해야 한다. 붙일 곳 — init은 `exe_mod` · `config_cli_mod`(둘 다 `config.zig`를
   import한다)와 `config.zig`를 트리에 둔 test 모듈들(`config_test` · `config_edit_test` · `environ_test` · `reload_test`와
   `clock` · `net` · `wifi` · `firewall`을 거치는 것들), terminal은 `exe_mod`와 `input` · `hangul` · `clipboard`를 트리에 둔 test
   다섯(`clipboard_test` · `hangul_test` · `input_test` · `status_test` · `vt_test`). 빠뜨리면 컴파일러가 "no module named
   'screen_args' available within module …"으로 어느 모듈인지 말한다. init은 test 모듈이 열여섯, terminal은 열다섯이다.
6. terminal의 `hangul.Layout`은 enum 위에 메서드 둘을 얹었다 — `lookup(self, ch)` · `nonSyllable(self, ch)`. 부르는 곳은
   `input.zig`의 두 줄(`self.hangul_layout.nonSyllable(ch)` · `.lookup(ch)`)이고, `status.zig`는 switch로만 쓴다. Zig의 enum은
   밖에서 메서드를 더할 수 없으므로, enum이 공유 파일로 가면 이 둘은 `hangul.zig`의 자유 함수가 된다.
7. 전환 키 목록의 파서 둘은 일부러 다르다. 파일(`hangul_toggle=`)은 이름 넷만 받고 `esc_latin`은 모르는 이름으로 로그에 남기며
   (EL design 결정 1), argv는 다섯을 받는다. init은 모르는 이름을 로그에 찍고 terminal은 조용히 버린다. `none`은 둘 다 받는다.
   `TOGGLE_ARG_MAX`(64)도 두 벌이다.
8. 게이트는 argv를 직접 보지 않는다. 보는 것은 로그 줄이다 — `terminal: keyboard=pc (swap_alt_meta=true)` ·
   `terminal: hangul layout=… latin=… toggles=…` · `terminal: clipboard scope=…`(config · hangul · pane 체인),
   `tars-init: reload terminal: pid …, shell … keyboard=pc`(config). 이 줄들의 글자를 바꾸지 않으면 체인의 기대는 그대로다.
9. 호스트 검사를 돌리는 체인 — init `zig build test`는 tools · config · device · input · hangul, terminal `zig build test`는
   terminal · hangul · device · battery · input · dictation. 호스트 0.17의 `ast-check` · `fmt --check`는 사람이 돌리는
   검사다(`project_zig_upgrade`).

## 목표

1. init과 terminal이 argv로 주고받는 값의 종류가 한 파일에 한 벌이다. enum에 이름을 더하면 두 프로그램의 switch가 함께 컴파일
   에러를 낸다.
2. argv의 자리 번호가 한 벌이다. 쓰는 쪽 셋(부팅 · reload · 탈출로)과 읽는 쪽이 같은 이름으로 칸을 가리킨다.
3. "init이 쓴 글자를 terminal이 같은 값으로 되돌린다"를 호스트 검사 하나가 한 프로세스 안에서 본다.
4. 로그 줄과 게이트의 기대는 바뀌지 않는다. 루트 게이트 22/22.

## 결정

### 결정 1. 공유 파일은 `shared/screen_args.zig` 하나이고, 두 build.zig가 `screen_args`라는 이름의 모듈로 붙인다

새 디렉터리 `shared/`를 저장소 뿌리에 둔다. init 아래에 두고 terminal이 `../init/src/…`를 가리키게 할 수도 있지만, 이 파일은 두
프로그램 사이의 계약이라 어느 한쪽의 소유가 아니다 — 둘 가운데 하나가 사라져도 남아야 할 파일이면 둘 밖에 둔다.

파일은 순수하다. 시스템 콜도 libc도 로그도 없다. init이 libc를 링크하지 않으므로(`project_zig_c_uapi_rule`) 공유 파일이 libc를
끌어오면 init이 깨진다. `std.mem` · `std.meta`만 쓴다.

모듈은 build.zig마다 `b.createModule(.{ .root_source_file = b.path("../shared/screen_args.zig") })` 하나이고 target을 주지
않는다(확인 4). 게스트 exe와 호스트 test가 같은 모듈 객체를 받는다.

### 결정 2. 파일에 드는 것은 값의 종류 · 자리 · 기본값이고, 의미는 들지 않는다

| 공유 파일에 둔다 | 각자 남는다 |
|---|---|
| `Keyboard` · `HangulLayout` · `LatinLayout` · `ToggleKey` · `Toggles` · `ClipboardScope` | 그 값이 무엇을 하는가 — hangul.zig의 자판 표, input.zig의 키 번역, clipboard.zig의 `pick` |
| `Toggles.parse` · `Toggles.format` · `TOGGLE_ARG_MAX` 한 벌 | 설정 파일의 다른 키들(`shell` · `net` · `ntp` …)은 `config.zig` 그대로 |
| `Slot`(argv 자리의 enum)과 `ARGC`(9) | 셸 경로 · 플래그 · 장치 경로를 누가 정하는가(init) |
| 손으로 띄웠을 때의 기본값 다섯 | — |

`Toggles.parse`는 모르는 이름을 호출자가 준 sink에 알린다 — init은 로그를 찍고 terminal은 버린다(확인 7). 파일 파서가 넷만 받고
argv 파서가 다섯을 받는 차이는 `comptime` 인자 하나(`.file` · `.argv`)로 같은 함수 안에 둔다. 왕복이 한 함수 쌍이 되므로
`config_test`의 "`arg()` → `parse()` 왕복"과 `input_test`의 `togglesArg` 검사는 공유 파일의 검사 하나로 합쳐진다.

### 결정 3. argv의 모양은 그대로 위치 기반 아홉 칸이고, 자리를 `Slot`으로 가리킨다

HANDOFF가 든 다른 길 `key=value`를 고르지 않는다. 깨질 자리는 "칸의 위치"가 아니라 "정의가 두 벌"이었고, 그것은 공유 파일이 닫는다.
`Slot`을 양쪽이 쓰면 위치도 한 벌이다 — `argv[@intFromEnum(Slot.flag)]`를 쓰는 쪽과 `args[@intFromEnum(Slot.flag)]`를 읽는 쪽이
같은 이름을 본다.

`key=value`가 주는 것은 `ps`에서 읽기 쉽다는 것과 칸의 순서를 안 지켜도 된다는 것이다. 받는 대가는 terminal에 파서 하나와 init에
접두사 붙은 문자열 버퍼다 — init은 힙이 없어 `keyboard=pc` 같은 글자를 enum마다 `comptime` 리터럴로 두거나 버퍼를 따로 들어야
하고, 탈출로와 `reload terminal`이 지금 하는 "포인터 하나 바꿔 끼우기"가 그대로 안 된다. terminal을 띄우는 것은 init 하나라 읽기
쉬움의 값이 작다. 나중에 모양을 바꾸고 싶으면 그때는 파일 하나 안의 일이다.

### 결정 4. `arg()` 넷은 `@tagName`으로 바뀐다

확인 3. `Keyboard` · `HangulLayout` · `LatinLayout` · `ClipboardScope`의 `arg()`는 switch 없이 `@tagName(self)`를 돌려준다.
`config_test`의 "`arg()`가 `@tagName`과 같은가" 반복문 둘은 검사할 것이 없어져 지운다.

### 결정 5. 양쪽은 이름을 재export해서 바깥의 호출자를 안 건드린다

init `config.zig`는 `pub const Keyboard = screen_args.Keyboard;`처럼 다섯 이름을 재export한다. `tars-config` · `reload.zig` ·
test들이 `config.Keyboard`로 부르는 자리(열한 곳)는 그대로다. terminal도 같다 — `hangul.Layout` · `input.LatinLayout` ·
`input.Toggles` · `clipboard.Scope`가 공유 타입의 별명이 되고 부르는 열네 곳은 그대로다.

바뀌는 호출은 `hangul.Layout`의 메서드 둘뿐이다(확인 6) — `layout.lookup(ch)`가 `hangul.lookup(layout, ch)`로,
`layout.nonSyllable(ch)`가 `hangul.nonSyllable(layout, ch)`로. 부르는 곳은 `input.zig` 두 줄이다.

### 결정 6. 호스트 검사 `shared/screen_args_test.zig`는 init의 `zig build test`에 든다

검사 파일은 공유 파일 옆에 두고 init의 build.zig가 test 모듈로 등록한다 — init의 `zig build test`는 체인 다섯과 tools가 돌린다
(확인 9). terminal 쪽에도 등록하지 않는다. 같은 검사를 두 번 돌릴 이유가 없고, 한 곳이면 빠뜨릴 곳도 한 곳이다.

보는 것 — 다섯 종류의 값마다 `@tagName` → `stringToEnum` 왕복, `Toggles`의 서른두 조합 전부 `format` → `parse` 왕복(`none`
포함), `Slot`의 값이 전부 `ARGC` 안이고 겹치지 않는 것(`comptime`), 파일 파서가 `esc_latin`을 거절하고 argv 파서가 받는 것.

### 결정 7. (M1) argv를 짓고 읽는 함수도 공유 파일로 간다

M0이 끝나면 `Args` 구조체(셸 경로 · 플래그 · 키보드 · 장치 경로 · 자판 둘 · 전환 키 · 클립보드)와 `encode(args, *argv)` ·
`decode(argv) Args`를 더한다. init의 쓰는 자리 둘(부팅 · reload)과 terminal의 읽는 자리가 이 둘을 거치면 `Slot`을 밖에서 쓸 일이
탈출로 하나로 준다. 왕복 검사가 "encode한 것을 decode하면 같다"가 된다. 탈출로의 `Rescue.slot`을 `Slot`으로 바꿀지는 M0의 코드를
보고 정한다 — 콘솔 셸의 자리(1)와 terminal의 자리(2)가 다른 것이 그 구조체가 있는 이유라 단순하지 않다.

### 결정 8. 로그 줄은 글자 하나 안 바뀐다

확인 8의 줄 넷은 그대로다. terminal의 `keyboard=pc (swap_alt_meta=true)` 줄은 `stringToEnum`을 거친 값을 `@tagName`으로 찍게
바뀌지만 글자는 같다. 체인 스크립트는 편집하지 않는다.

### 결정 9. 루트 게이트로 닫고, 호스트 `ast-check` · `fmt --check`의 목록에 `shared/`를 더한다

init과 terminal이 함께 바뀌고 모든 체인이 둘 다 부팅하므로 체인 하나로 끝내지 않는다. `docs/guides/lessons.md`의 호스트 검사
명령에 `shared/*.zig`를 더한다 — 사람이 돌리는 검사라 목록에 없으면 영영 안 돈다.

## Milestone

- SA-M0 — 결정 1 ~ 6 · 8 · 9. `shared/screen_args.zig` · `screen_args_test.zig`, 두 build.zig, `config.zig`의 재export와 `arg()`
  넷, `hangul.zig` · `input.zig` · `clipboard.zig`의 별명과 자유 함수 둘, init `main.zig`의 `TERM_*_SLOT` 일곱 → `Slot`,
  terminal `main.zig`의 `args[n]` 여덟 → `Slot`. 루트 게이트.
- SA-M1 — 결정 7. plan은 M0의 게이트가 끝난 뒤 쓴다.

## 위험

1. `..`를 가리키는 모듈의 캐시. `zig build`는 파일 내용의 해시로 다시 짓는지를 정하므로 `shared/`를 고치면 두 빌드가 다시 돈다 —
   M0에서 공유 파일만 고치고 `zig build`를 다시 돌려 바이너리가 바뀌는지 확인한다(`project_zig_out_staleness`의 병이 여기서
   새로 나면 안 된다).
2. `addImport`를 빠뜨린 test 모듈. 컴파일러가 이름을 말하므로 숨지는 않지만, 두 build.zig에 열한 줄쯤 늘어난다.
3. `terminal/build.zig.zon`의 `.paths`에 `../shared`가 없다. 이 목록은 terminal을 남의 패키지로 가져갈 때의 포장 목록이고 그런 쓰임이
   없으므로 상관없다. 적어 두는 것은 누가 나중에 "왜 목록에 없나"를 물을 때를 위해서다.
4. 공유 파일이 순수하다는 약속은 컴파일러가 안 지켜 준다. init이 깨지는 것으로 드러난다(libc 심볼이 링크에서 빠진다). 검사는 M0의
   init 빌드 자체다.
5. `docs/guides/lessons.md` "핵심 파일"의 `hangul.zig` · `input.zig` · `config.zig` 줄이 메서드 이름과 enum의 자리를 적고 있다.
   닫을 때 고친다.

## 비목표

1. 점검의 (2) `main` 쪼개기 · (3) 큰 파일 셋의 호스트 검사 — 각자 서브프로젝트다.
2. `key=value` argv(결정 3).
3. 설정 키를 더하거나 뜻을 바꾸는 것. 이 서브프로젝트는 글자가 오가는 길만 고친다.
4. 서비스 셋의 `*_ARGV` 상수의 모양. 타입이 `[ARGC:null]`을 따르게는 하되 내용은 그대로다.
5. 로그 줄 · 체인 스크립트 · 소개 페이지의 기능 목록(사용자에게 보이는 기능이 없다).

## 닫을 때(lead의 몫)

- 이 design의 `Status:`, `docs/guides/completed.md`의 한 행, 소개 페이지 `data.js`의 기준일 · 타임라인(`site/README.md` 순서).
- `docs/decisions/project_screen_args.md`와 `MEMORY.md` 한 줄, `HANDOFF.md`의 후보 (1) 지우기, lessons "핵심 파일"의 세 줄과
  호스트 검사 명령.

## 관련

- `docs/decisions/project_config_persistence.md` — 파서는 PID 1 한 벌, terminal은 argv로 받는다(CP).
- `docs/decisions/project_zig_c_uapi_rule.md` — init은 libc를 링크하지 않는다. 공유 파일이 순수해야 하는 이유.
- `docs/specs/2026-10-07-tars-config-reload-design.md` M3 절 — `reload terminal`이 argv를 다시 짓는 자리.
- `docs/decisions/project_zig_upgrade.md` — 0.17의 std와 호스트 검사.
