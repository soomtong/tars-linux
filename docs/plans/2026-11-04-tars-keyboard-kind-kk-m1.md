# KK-M1 — `keyboard=auto`를 넣고 기본값으로, 키보드마다 맞바꿈을 고른다

> 구현 파일은 Claude(또는 서브에이전트)가 넣고, lead가 diff를 실제 파일과 대조한 뒤 체인 · commit한다. 줄 번호는 2026-11-04
> `c70e4d2` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다.

Goal: KK design 결정 1 ~ 6을 코드에 넣는다. M0이 붙박은 `input` 체인 판정 12가 초록이 되고, 판정 13 · 2차 · 3차와 다른 26체인이
그대로 초록이다. mutation 셋이 잡힌다. 서브프로젝트를 닫는다.

Architecture: 값의 이름(`auto`)과 기본값은 `shared/screen_args.zig`와 init이, 고르는 규칙은 `input.zig`의 순수 함수가, 장치의 id와 칸별
값은 `main.zig`의 키보드 칸이 든다. `handleKey`는 안 바뀐다 — `readKeyboard`가 칸의 값을 `Context.swap_alt_meta`에 실을 뿐이다.

## 착수 전에 확인한 것 (2026-11-04)

- 기본값이 두 자리에 있다 — `shared/screen_args.zig`의 `default_keyboard`(init 없이 띄운 terminal)와 init `config.zig`의
  `Config.keyboard`. 주석이 "같아야 한다"고 적고, `screen_args_test`가 decode의 기본값을 본다.
- 키보드는 `tryOpenInput` → `takeKeyboard`에서 열린다. 위로 `scanInputs` · `drainUevents`가 부르고, 그 둘을 `App`이 두 자리
  (`openPointers` 쪽 첫 훑기, poll 회차의 uevent)에서 부른다. 이 넷은 `App` 밖의 함수라 설정값이 닿지 않는다 — 인자로 넘긴다
  (`pointer_drawn` 같은 전역은 안 늘린다).
- `EVIOCGID`는 `_IOR('E', 0x02, struct input_id)` = `0x80084502`. `pointer.zig`는 번역된 매크로를 감싼 함수(`eviocgname` 등)를 두고
  `pointer_test`가 C 헤더로 잰 수와 대조한다.
- 기본값의 글자를 보는 곳: init `reload_test`(`screen keyboard=apple`, `keyboard: apple -> pc` 둘) · `config_edit_test`(`keyboard=apple
  timezone=UTC`, `#keyboard=apple` 둘), `config` 체인(`TC_LIST_WANT`의 `keyboard=apple`, `keyboard: apple -> pc` 셋, `keeps
  keyboard=apple`).
- `keyboard> open … name=`을 글자로 보는 곳: `keyboard/check.sh`의 `open ${K1_PATH} name=QEMU QEMU USB Keyboard`, `device/check.sh` ·
  `terminal/check.sh`의 `open /dev/input/event[0-9]* name=`. `open /dev/input/event`까지만 보는 표지(`input` · `device` · `terminal`의
  `report_failure` 목록, `machine`)는 그대로 맞는다. `keyboard/check.sh`의 `open_path`는 넷째 낱말(경로)을 꺼내므로 그대로다.
- `keyboard` 체인의 디스크에는 `keyboard=` 줄이 없다 → M1 뒤 k1 · k2(QEMU `usb-kbd`)는 `pc`다. 그 체인의 판정은 Shift · Ctrl ·
  글자만 치고(`stop_repeat`은 오른쪽 Ctrl), Alt · Meta를 안 친다 — 맞바꿈과 상관없다.
- `site/capture.sh`는 호스트(macOS)에서 돌고 `mkfs.ext2`가 없다(`command -v` 빈칸). 게이트가 아니므로 디스크 대신 키 이름을 바꾼다
  (design 결정 8의 B안, 6곳).

## Task 1: `shared/screen_args.zig`

- `Keyboard`에 `auto`를 더한다. 주석: `apple` · `pc`는 모든 키보드에 강제, `auto`는 terminal이 키보드마다 vendor로 고른다(KK design
  결정 1 · 2).
- `default_keyboard = .auto`.

`screen_args_test`의 enum 왕복은 저절로 `auto`를 덮는다. 기본값 대조도 그대로다.

## Task 2: init

- `config.zig`: `Config.keyboard = .auto`, 그 위 주석("기본값이 apple인 이유는 …")을 KK design 결정 4로 바꾼다(일반 노트북의 내장
  키보드는 PC 배열이고 거기에 Apple 키보드를 꽂는 것이 이 기계의 보통 모습 — `auto`가 둘 다 맞춘다). `hangul_layout` 주석의
  "`keyboard`가 `apple`인 것과 같은 근거"는 "이 기계를 쓰는 사람이 쓰는 것"으로 고친다.
- 견본 주석 `# keyboard: apple | pc` → `# keyboard: auto | apple | pc`.
- 단위 검사의 글자: `reload_test` · `config_edit_test`의 기본값 `apple` → `auto`(위 다섯 자리). 테스트가 "기본값"을 뜻하는 자리만
  바꾸고, 사용자가 적은 값(`keyboard=pc`)은 그대로다.

init의 `zig build test`는 컨테이너에서 돈다(macOS에서 안 끝난다).

## Task 3: terminal — 고르는 규칙(`input.zig`)

```zig
pub const Keyboard = screen_args.Keyboard;

/// 키보드 하나가 쓰는 종류(KK design 결정 2). `apple` · `pc`면 그 값 그대로, `auto`면 vendor로 고른다.
pub fn kindOf(setting: Keyboard, bus: u16, vendor: u16) enum { apple, pc } { ... }
```

- `auto`: vendor `0x05ac`(bus 상관없이) 또는 `0x004c`이면서 bus가 `BUS_BLUETOOTH`(0x05)면 `apple`, 나머지 `pc`.
- `Context.swap_alt_meta`의 주석 "부팅 내내 상수"(그리고 `handleKey` 머리 주석의 같은 말)를 "칸이 열려 있는 동안 상수"로.

## Task 4: terminal — 칸별 값(`main.zig`, `pointer.zig`)

- `pointer.zig`: `pub fn eviocgid() c_ulong`(번역된 `c.EVIOCGID`). 매크로가 안 풀리면 design 위험 3대로 상수를 손으로 둔다.
- `KeyboardDev`에 `swap_alt_meta: bool`. `takeKeyboard(kbds, fd, path, dev_name, setting)`가 `EVIOCGID`로 `input_id`(u16 넷)를 읽어
  `input.kindOf`로 고른다. 실패하면 bus · vendor를 0으로 보고(`auto`면 `pc`), `terminal: keyboard> id {path} error={errno}` 한 줄.
- `open` 줄: `terminal: keyboard> open {path} kind={apple|pc} bus={x:0>4} vendor={x:0>4} name={name}`(design 결정 5).
- `tryOpenInput` · `scanInputs` · `drainUevents`에 `setting: input.Keyboard` 인자를 더해 `takeKeyboard`까지 넘긴다. `App`의 두
  호출 자리가 `self.keyboard`를 준다.
- `App.swap_alt_meta: bool` → `App.keyboard: input.Keyboard`(argv의 값). `readKeyboard`는 `self.keyboard_devs[slot].?.swap_alt_meta`를
  `Context`에 싣는다.
- 시작 줄: `apple` · `pc`면 지금 글자 그대로(`keyboard=pc (swap_alt_meta=true)`), `auto`면 `terminal: keyboard=auto (swap_alt_meta=per
  keyboard)`.

`rg -n 'swap_alt_meta' terminal/src/main.zig`가 편집 뒤에 칸(`KeyboardDev`) · `Context` 조립 · 시작 줄 · `takeKeyboard`에만 남는지
본다.

## Task 5: 단위 검사

- `input_test`: `kindOf` 표 — design 확인 2의 다섯 행(Apple USB · Magic BT 0x004c · 옛 BT 0x05ac · i8042 0x0001 · QEMU 0x0627),
  `0x004c`의 USB는 `pc`, `apple` · `pc` 강제는 vendor를 무시한다. 그리고 칸을 건너는 맞바꿈: 같은 `State`에서 칸 0(`swap_alt_meta =
  true`, `device = 0`)의 `KEY_LEFTALT` 누름은 칸 0의 `meta_left`, 칸 1(`swap_alt_meta = false`, `device = 1`)의 `KEY_LEFTALT` 누름은
  칸 1의 `alt_left`가 되고, 두 Alt를 다 떼면 둘 다 거짓이다(맞바꿈 뒤의 코드로 뗀다).
- `pointer_test`: `EVIOCGID` = `0x80084502`.

## Task 6: 체인의 글자

- `input/check.sh`: 판정 12 앞에 `keyboard> open … kind=pc bus=0011 vendor=0001 name=AT Translated Set 2 keyboard`, 판정 13의 open
  기다림을 `kind=apple bus=0003 vendor=05ac name=TARS KK Keyboard`로(design 실측 1). 3차에 `kind=apple`, 2차에 `kind=pc` 한 줄씩 —
  강제한 값도 `kind=`를 찍는다(결정 5).
- `keyboard/check.sh`: `open ${K1_PATH} name=QEMU …` → `open ${K1_PATH} kind=pc bus=0003 vendor=0627 name=QEMU …`.
- `device/check.sh` · `terminal/check.sh`: `open /dev/input/event[0-9]* name=` → `-E 'open /dev/input/event[0-9]+ kind=(apple|pc)
  bus=[0-9a-f]{4} vendor=[0-9a-f]{4} name='`. 그 자리의 grep 모양(`-q` · `-a`)은 그대로 둔다.
- `config/check.sh`: 기본값 글자 `apple` → `auto`(위 다섯 자리).
- `site/capture.sh`: `meta_l-` → `alt-`(6곳), 주석 한 줄 — 기본값 `auto`에서 이 PS/2 키보드는 `pc`라 Cmd 자리가 물리 Alt다.

## Task 7: 정적 검사 · 체인

1. `make quick`. `git diff --stat` · `git diff | rg '^-'`로 지운 줄을 읽는다.
2. 컨테이너에서 init `zig build test`, terminal `zig build test`(`input_test` · `pointer_test`).
3. 체인: `input`(판정 12 · 13 · 2차 · 3차 초록), `keyboard` · `device` · `terminal` · `config`(글자를 고친 것). 넷은 동시에 돌린다.

## Task 8: mutation 셋 (design 결정 7)

한 번에 하나씩 넣고 `input` 체인만 돌린 뒤 되돌린다(`git diff`가 비는지 본다).

| | 망가뜨린 것 | 잡아야 할 판정 |
|---|---|---|
| a | `kindOf`의 `auto`가 vendor를 무시하고 늘 `pc` | 13(`Xecho: command not found`) |
| b | `readKeyboard`가 칸 대신 칸 0의 `swap_alt_meta`를 싣는다 | 13(kk-apple은 칸 1이다) |
| c | `Config.keyboard`를 `.apple`로 되돌린다 | 12, 그리고 1차 끝 `keyboard=auto` 줄 |

## Task 9: 루트 게이트

`RUNS=1`, 약 15분(실행 전에 알린다). 기대 27/27. `BT-M2`가 btvirt 간헐(`carryover.md`)로 빨가면 그 체인만 다시 돌려 초록을 확인한다.

## Task 10: 문서 닫기

- KK design: Status를 "끝났다"로, "실측 (M1)" 절(단위 검사 · 체인 · mutation · 게이트).
- KH design 비목표 1 · DM design 비목표 1에 "→ KK(2026-11-04)가 했다", `carryover.md` KH 넷째 항목 `[x]`.
- `docs/guides/completed.md` 표 끝 한 행.
- `docs/decisions/project_keyboard_kind.md` + `MEMORY.md` 한 줄 — 결정(auto 기본 · vendor 둘 · A안)과 함정(PS/2인 `input` 체인 키보드,
  도구는 `&`, 기본값 apple 동안 `loaded` 줄로만 디스크가 증명된다).
- 소개 페이지(`gh-pages`의 `data.js`) — `site/README.md`의 순서대로. 로컬 커밋만 하고 push는 사용자에게 남긴다.
- HANDOFF.
- "사용자가 확인할 것"에 실기 항목: 일반 노트북 내장 + Apple 키보드에서 Option · Cmd가 각자 맞는지, `keyboard> open` 줄의 bus ·
  vendor(특히 BT Magic Keyboard가 `0x004c`인지, 서드파티 Mac 배열 키보드의 vendor — design 위험 1).

## Task 11: 커밋

add 대상을 좁힌다: `shared/screen_args.zig` · `init/src/config.zig` · init 테스트 둘 · `terminal/src/{input,main,pointer}.zig` · 테스트
둘 · 체인 다섯(`input` · `keyboard` · `device` · `terminal` · `config`) · `site/capture.sh` · 문서들. `git status`에 산출물이 없는지 먼저 본다.

## 시간

코드 약 120줄, 테스트 약 80줄, 셸 약 20줄. 단위 검사 2분, 체인 넷 약 4분, mutation 셋 약 6분, 루트 게이트 약 15분.
