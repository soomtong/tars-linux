# PS-M0 — 설정 넷의 길과 휠 방향

> 구현 파일은 Claude(또는 서브에이전트)가 넣고, lead가 diff를 실제 파일과 대조한 뒤 체인 · commit한다. 줄 번호는 2026-11-04
> `ef28451` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다.

Goal: PS design 결정 1 · 2 · 5 · 6 · 7과 결정 8의 판정 가~라를 넣는다. `tars.conf`의 네 키가 init → argv → terminal의 장치 칸까지
가고, 휠 부호가 칸마다 적용된다. 가속 값은 읽어 나르고 `open` 줄에 찍기만 한다 — 곱하는 것은 M1이다. 기본값이 지금 동작이라
다른 26체인과 `pointer` 체인의 기존 판정이 그대로 초록이다.

Architecture: 이름과 기본값은 `shared/screen_args.zig`(두 프로그램이 함께 컴파일), 파일 읽기 · 견본 · reload는 init, 종류와 설정으로
부호를 고르는 규칙은 `pointer.zig`의 순수 함수, 칸의 값은 `main.zig`의 `PointerDev`가 든다. 디코더 둘(`pointer.Mouse` ·
`touchpad.Touchpad`)은 안 바뀐다.

## 착수 전에 확인한 것 (2026-11-04)

1. `reload.Keys`가 `bits: u16`이고 `count > 16`이면 `@compileError`다. 필드가 14 → 18이 된다.
2. init이 필드 타입으로 갈래를 고르는 함수가 넷이다 — `reload.same` · `reload.text` · `config_edit.fieldText` · `config_edit.hintFor`.
   모르는 타입이면 컴파일 에러를 내므로 빠뜨릴 수 없다. 넷 다 enum은 저절로 받고, `Accel`만 한 줄씩 더한다(확정 2).
3. `reload.groupOf`가 모르는 키는 컴파일 에러다. 네 키는 `term`(화면 대기) 갈래다 — terminal argv에 든다.
4. `config_edit.KEYS`는 `Config`의 필드 이름에서 지어진다. `tars-config set`이 따로 고칠 것 없이 새 키를 받는다. 값 검사는
   `judge`가 `config.parse`에 한 줄을 넣어 "말을 했는가"로 본다 — 결정 6의 경고 줄이 곧 `set`의 거절이다.
5. 키를 다 늘어놓는 글자가 다섯 자리에 있다(필드 순서대로).
   - `init/src/config_test.zig`의 `expect`(필드 비교와 FAIL 글자)
   - `init/src/config_edit_test.zig`의 `OTHER` · `KEYS.len != 14` · `keys_end`
   - `init/src/reload_test.zig`의 `OTHER` · 갈래 수 `4/3/6/1` · `configReply` 글자 · 출력 문장의 "fourteen"
   - `config/check.sh`의 `TC_LIST_WANT`와 "열세 키" 주석 둘
   - 새 필드는 `clipboard` 뒤 · `user` 앞에 둔다(`user`는 설치기만 쓰는 마지막 키로 남는다). 그래서 위 글자들에서 새 줄은
     `clipboard=` 뒤 · `user=` 앞에 들어간다.
6. `gate_lib.sh`의 `cut_log_lines`가 `tars-init: reload terminal:` 줄을 `… clipboard=\S+\r?\n?\z`로 끝까지 맞춘다. 그 줄에 값을
   더하면 정규식과 `check.sh`의 `require_cut_lines_found` 견본(`legit`) 줄을 함께 고친다. 안 고치면 온전한 reload 줄이 B(잘린 줄)로
   세어진다.
7. `pointer> open` 줄을 글자로 보는 곳은 `pointer/check.sh` 넷 — 566(`kind=mouse shown=0 name=QEMU …`), 693(`kind=mouse shown=1
   name=QEMU …`), 1579(`kind=mouse shown=0 name=${PS2_NAME}`), 1612(`kind=touchpad slots=2 … shown=0 name=TARS Replay Touchpad`).
   1609의 `kind=touchpad.* name=`과 158의 표지 목록은 그대로 맞는다. 다른 체인에는 없다.
8. `pane/check.sh` 307 · 809가 `tars-init: config shell=.* clipboard=…`를 본다. 끝을 못 박지 않았으므로 뒤에 값이 붙어도 맞는다
   (그 실패 글자의 "does not end with"는 그대로 둔다 — 판정이 안 바뀐다).
9. `pointer.zig`는 지금 `screen_args`를 import하지 않는다. 더하면 `terminal/build.zig`의 `pointer_test_mod` · `touchpad_test_mod`에도
   `addImport("screen_args", screen_args)`가 필요하다(`touchpad.zig`가 `pointer.zig`를 import한다).
10. `tp-replay`의 `scroll DY`는 음수를 받는다(`abs`로 걸음 수를 세고 `dy * i / steps`로 민다). 체인의 `replay` 도우미가 `-`를
    `minus` 키로 친다.
11. 부팅 B의 `tars.conf`는 `shell=fish` · `keyboard=apple` 두 줄이다(PD-M4가 Cmd를 친다). 포트는 `pointer` 체인이 45488 · 45489, 예약
    범위의 다음 빈 자리는 45501이다(HANDOFF).
12. 기본 `tars.conf` 견본은 들여쓰기를 빼면 약 2.8KB, `MAX_FILE`은 4096이다. 넷과 짧은 주석(약 0.45KB)에 `user` 꼬리를 더해도
    한도 안이다. `config_test`의 `SavedFileTooBig`이 지킨다.

## 확정 (design을 코드로 옮기며 정한 것)

1. 이름: `screen_args.WheelDirection = enum { normal, natural }`. `pointer.Scroll`(끄는 중 휠)과 겹쳐 design의 `Scroll`을 바꿨다.
2. `screen_args.Accel = struct { level: u4 = 0 }` — `MAX = 10`, `parse(text) ?Accel`(10진, 0~10, 앞뒤 공백 없음, 부호 없음), `arg()
   [:0]const u8`(comptime 표 `"0"`~`"10"`), `eql`. 맨 `u4`가 아닌 이유는 확인 2의 네 함수가 `T == config.Accel`로 고르게 하려는 것이다.
   design 결정 5에 같은 말을 덧붙였다.
3. 기본값: `default_mouse_scroll = .normal` · `default_touchpad_scroll = .natural` · `default_mouse_accel` ·
   `default_touchpad_accel = .{}`(0). init `Config`의 기본값과 같아야 한다(파일 머리 주석의 규칙).
4. 부호 규칙은 `pointer.wheelSign(kind: Kind, mouse: WheelDirection, touchpad: WheelDirection) i32`이다. `kind`가 `none`이면 1(그
   칸은 열리지 않으므로 안 쓰인다).
5. 부호는 `PointerDev.feed`가 아니라 `drainPointer`의 `for (frames.slice())` 안에서 `apply` 전에 곱한다 — `frame.wheel *= dev.wheel_sign`.
   M1의 가속이 같은 자리에 붙는다.
6. 설정 넷은 terminal 안에서 `pointer.Prefs = struct { mouse_scroll, touchpad_scroll, mouse_accel, touchpad_accel }` 하나로 나른다.
   `scanInputs` · `drainUevents` · `tryOpenInput` · `takePointer`가 `prefs: pointer.Prefs`를 하나 더 받는다(KK가 `setting`을 넘긴 것과
   같은 모양, 전역을 안 늘린다).
7. 로그 줄 셋에 붙이는 순서는 필드 순서다 — `mouse_scroll= touchpad_scroll= mouse_accel= touchpad_accel=`.

## Task 1: `shared/screen_args.zig`

- `WheelDirection` · `Accel`(확정 1 · 2), 위 주석에 PS design 결정 1 · 3 · 5.
- `Slot`에 `mouse_scroll = 9` · `touchpad_scroll = 10` · `mouse_accel = 11` · `touchpad_accel = 12`, `ARGC = 13`. `Slot` 머리 주석에 PS 한 줄.
- `Args`에 같은 이름 넷(기본값 없이), `encode`에 넷, `decode`에 넷 — 방향은 `enumAt`, 가속은 `Accel.parse` 실패 시 기본값.
- 기본값 넷(확정 3).

`screen_args_test`: enum 왕복은 저절로 덮인다. 더할 것은 `Accel` — `parse`가 `"0"` · `"10"`을 받고 `"11"` · `"-1"` · `"+3"` · `" 3"` ·
`"3x"` · `""`을 거절, `arg`가 0~10을 왕복, 그리고 `decode`가 숫자 칸의 `"11"`을 기본값으로 떨어뜨리는지.

## Task 2: init

- `config.zig`: `WheelDirection` · `Accel` 다시 내보내기, `Config`에 넷(`clipboard` 뒤 · `user` 앞), 각 주석 한 줄(PS design 결정 2 · 3,
  사용자 결정 2026-11-04). `parse`에 갈래 넷 — 방향은 `clipboard`와 같은 모양, 가속은
  `Accel.parse(value) orelse { log("unknown mouse_accel '{s}', falling back to {d}", …); continue; }`.
- 견본(`save`): `clipboard` 뒤에 아래 열 줄. 주석은 영어로 짧게(확인 12).
  ```
  # mouse_scroll: normal | natural
  #   normal = wheel forward shows what is above, natural = content follows the wheel
  mouse_scroll=normal
  # touchpad_scroll: natural | normal
  #   natural = content follows two fingers (macOS), normal = the reverse
  touchpad_scroll=natural
  # mouse_accel: 0..10
  #   0 = off. Higher goes farther on a fast flick; slow moves stay one to one
  mouse_accel=0
  # touchpad_accel: 0..10, same as mouse_accel
  touchpad_accel=0
  ```
- `main.zig`: 부팅 `encode`에 넷, `doReloadTerminal`의 `a.* = new.*` 넷, 로그 줄 둘(`tars-init: config …`와 `reload terminal: …`)의
  끝에 넷(확정 7).
- `reload.zig`: `Keys.bits`를 `u32`로, 상한 검사를 `count > 32`로, `groupOf`의 `term`에 넷, `same` · `text`에 `Accel` 한 줄씩, 주석의
  "열네 키" → "열여덟 키", `configReply` 주석의 "열세 줄".
- `config_edit.zig`: `fieldText` · `hintFor`에 `Accel`(힌트 `"0..10 (0 = off)"`), `LINE_MAX` 주석의 가장 긴 키를 `touchpad_scroll`
  열다섯 글자로.

단위 검사(컨테이너):
- `config_test`: 네 키의 받음 · 거절 — `mouse_scroll=natural` · `touchpad_scroll=normal` · `mouse_accel=0` · `=10` · `=7`, 거절 `=11` ·
  `=-1` · `=fast` · `=`(값 없음) · `mouse_scroll=up`. `expect`의 비교와 FAIL 글자에 넷. 견본 왕복이 기본값 그대로인지는 기존 검사가 본다.
- `config_edit_test`: `OTHER`에 넷(`natural` · `normal` · `5` · `5`), `KEYS.len` 18, 그 문장의 수, `keys_end`에 넷.
- `reload_test`: `OTHER`에 넷, 갈래 `4/3/10/1`, `configReply` 글자에 넷, 문장의 수.

## Task 3: terminal — 규칙과 칸(`pointer.zig`, `main.zig`)

- `pointer.zig`: `const screen_args = @import("screen_args")`, `pub const WheelDirection` · `Accel` 다시 내보내기, `Prefs`(확정 6),
  `wheelSign`(확정 4). 머리 주석의 "import 없음" 목록은 그대로 맞다(`vt` · `layout`만 막는다) — 순수함은 안 바뀐다.
- `terminal/build.zig`: `pointer_test_mod` · `touchpad_test_mod`에 `screen_args` import(확인 9).
- `main.zig`:
  - `PointerDev`에 `wheel_sign: i32`와 `accel: pointer.Accel`(M0에서는 들기만 한다 — `open` 줄과 M1의 자리).
  - `takePointer(…, prefs)`가 `wheelSign(kind, …)`와 종류에 맞는 가속 값을 칸에 넣는다.
  - `open` 줄: `kind=mouse scroll={s} accel={d} shown=…`, `kind=touchpad scroll={s} accel={d} slots=…`(design 결정 7).
  - `drainPointer`: 확정 5의 곱하기 한 줄과 주석(PS design 결정 2 — 합치기 전에 칸의 부호).
  - `App`에 `pointer_prefs: pointer.Prefs`. `spawnFirst`가 `a`에서 채우고, `scanInputs` · `drainUevents`의 두 호출 자리가 넘긴다.
  - 시작 로그 한 줄: `terminal: pointer prefs mouse_scroll=… touchpad_scroll=… mouse_accel=… touchpad_accel=…`(KK의 `keyboard=` 줄
    옆). argv가 도착했는가를 장치 없이 보는 자리다.

`rg -n 'wheel_sign' terminal/src/main.zig`가 칸 · `takePointer` · `drainPointer` 셋에만 있는지 본다.

단위 검사(`pointer_test`): `wheelSign`의 네 행(design 결정 2의 표)과 `none`. `Prefs` 기본값이 `screen_args`의 기본값과 같은지.

## Task 4: 체인의 글자

- `pointer/check.sh` 확인 7의 넷: `kind=mouse scroll=normal accel=0 shown=…`, `kind=touchpad scroll=natural accel=0 slots=2 …`. 실패
  글자도 같이.
- `gate_lib.sh` `cut_log_lines`의 reload 정규식 끝에 ` mouse_scroll=\S+ touchpad_scroll=\S+ mouse_accel=\S+ touchpad_accel=\S+`,
  `check.sh`의 `legit` 견본 줄에 ` mouse_scroll=normal touchpad_scroll=natural mouse_accel=0 touchpad_accel=0`(확인 6).
- `config/check.sh`: `TC_LIST_WANT` 끝에 넷, "열세 키" 주석 둘 → "열일곱 키"(seed에 드는 수 — `user`는 seed에 없다).

## Task 5: 부팅 C (design 결정 8의 판정 가~라)

`pointer/check.sh`의 부팅 B 끝(`echo "boot B pointer> lines:"` 뒤, `echo "PD-M4 check PASS"` 앞)에 둔다. 마지막 줄은
`echo "PS-M0 check PASS"`를 더하고 PD-M4 줄은 그대로 둔다(CHAINS의 이름은 안 바꾼다).

- 포트 `MONITOR_PORT_C=45501`, 머리 주석에 한 줄. HANDOFF의 "새 체인은 45501부터"는 45502로.
- 디스크 `out/pd-settings.img`: `tars.conf` = `shell=fish` · `mouse_scroll=natural` · `touchpad_scroll=normal`, `pd/tp-replay`. 부팅 B와
  같은 `mkfs.ext2 … -L tars-pd …`.
- QEMU 줄은 부팅 B 그대로(PS/2 마우스, 디스크 하나), 포트만 C. 부팅 B를 끄는 세 줄(`exec 3<&-` · `kill` · `wait`)을 앞에 둔다.

| 판정 | 무엇 | 기대 |
|---|---|---|
| 가 | `tars-init: loaded /config/tars.conf`, 그리고 `tars-init: config … mouse_scroll=natural touchpad_scroll=normal mouse_accel=0 touchpad_accel=0` | 디스크가 실제로 읽혔다(KK-M0 실패한 접근 둘째 — `loaded` 줄을 함께 본다) |
| 나 | PS/2 마우스 `open … kind=mouse scroll=natural accel=0 shown=0 name=${PS2_NAME}`, `tp-replay`의 `open … kind=touchpad scroll=normal accel=0 slots=2 …` | 한 부팅에서 두 칸이 다른 값 |
| 다 | `seq 200` 뒤 `hmp "mouse_move 0 0 -1"`(휠 뒤로) | `scroll>`의 offset이 3 준다, 마지막 `at` 줄 `wheel=1`. `mouse_move 0 0 1`이면 되돌아온다(`wheel=-1`) |
| 라 | `replay "scroll -90"`(두 손가락 위로) | offset이 6 준다(검사 24의 반대 손으로 같은 결과), `at` 줄의 wheel 합 2, 포인터 자리 그대로 |

판정 다의 `at` 줄 `wheel=`은 부호를 곱한 뒤의 값이다(`round.wheel`이 곱한 값을 모은다) — 손은 뒤로 굴렸고 줄은 `wheel=1`이다. 그
차이가 이 판정의 뜻이라 주석에 적는다. 끝에 `quit`으로 도구를 닫고 NUL 검사(부팅 B와 같은 꼴)와 `boot C pointer> lines:`.

도우미(`wait_for_at` · `scroll_field` · `replay` · `pointer_count`)는 부팅 B의 것을 그대로 쓴다. `replay`가 부팅 B 구간 안에서
정의되어 있으면 그대로 보인다(같은 셸).

## Task 6: 정적 검사 · 단위 검사 · 체인

1. `make quick`. `git diff --stat` · `git diff | rg '^-'`로 지운 줄을 읽는다 — 지워질 줄은 확인 5 · 6 · 7의 글자, 로그 줄 둘의 끝,
   `Keys.bits`의 타입, `drainPointer`의 한 줄 주변뿐이어야 한다.
2. 컨테이너에서 init `zig build test`, `shared`의 `screen_args_test`, terminal `zig build test`(`pointer_test` · `touchpad_test`).
3. 체인: `pointer`(부팅 A · B 기존 판정 + 부팅 C 가~라), `config`(목록 · reload 글자), `pane`(config 줄), 그리고 `check.sh`의 자체 검사
   (`require_cut_lines_found`). 넷을 동시에 돌린다. `pointer` 체인이 얼마나 늘었는지 적는다(design 위험 4).

## Task 7: mutation 둘

한 번에 하나씩 넣고 `pointer` 체인만 돌린 뒤 되돌린다(`git diff`가 비는지 본다).

| | 망가뜨린 것 | 잡아야 할 판정 |
|---|---|---|
| a | `drainPointer`가 부호를 안 곱한다 | 부팅 C 다 · 라 |
| b | `takePointer`가 종류를 안 보고 `prefs.mouse_scroll`로만 부호를 고른다 | 부팅 C 라(터치패드가 natural로 남는다), 그리고 부팅 B 검사 24 |

## Task 8: 루트 게이트

`RUNS=1`, 약 16분(실행 전에 알린다). 기대 27/27. `BT-M2`가 btvirt 간헐(`carryover.md`)로 빨가면 그 체인만 다시 돌려 초록을 확인한다.

## Task 9: 문서

- PS design: "실측 (M0)" 절 — 단위 검사 · 체인(부팅 C의 시간) · mutation · 게이트. Status 줄은 "M0 끝, M1 남음".
- HANDOFF: 진행 중 서브프로젝트 PS, 다음은 M1 plan. 포트 45501.

## Task 10: 커밋

add 대상을 좁힌다: `shared/screen_args.zig` · `shared/screen_args_test.zig` · `init/src/{config,config_edit,reload,main}.zig` · init
테스트 셋 · `terminal/src/{pointer,main}.zig` · `terminal/src/pointer_test.zig` · `terminal/build.zig` · `pointer/check.sh` ·
`config/check.sh` · `gate_lib.sh` · `check.sh` · 문서들. `git status`에 산출물(`out/pd-settings.img` 등)이 없는지 먼저 본다.

## 시간

코드 약 150줄(init 70 · shared 50 · terminal 30), 테스트 약 90줄, 셸 약 90줄. 단위 검사 3분, 체인 넷 약 6분(`pointer`가 약 1분 는다),
mutation 둘 약 6분, 루트 게이트 약 16분.
