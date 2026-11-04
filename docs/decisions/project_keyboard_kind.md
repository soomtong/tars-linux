---
name: project_keyboard_kind
description: "Keyboard Kind(KK-M0~M1, 2026-11-04 끝남) — keyboard=auto를 더해 기본값으로, terminal이 키보드를 열 때 EVIOCGID의 vendor로 Alt · Meta 맞바꿈을 칸마다 고른다(Apple 0x05ac · BT 0x004c면 apple). Cmd를 치는 체인은 디스크에 keyboard=apple을 적는다. 함정 — input 체인의 키보드는 PS/2, uinput 키보드 도구는 &로 띄운다, 기본값이 apple이던 동안은 loaded 줄만 디스크를 증명했다"
metadata:
  node_type: memory
  type: project
---

# Keyboard Kind (KK)

design은 `docs/specs/2026-11-04-tars-keyboard-kind-design.md`, plan은 `docs/plans/2026-11-04-tars-keyboard-kind-kk-m0.md` ·
`-kk-m1.md`. `carryover.md` KH 절의 넷째 항목(KH 비목표 1, 시나리오 S13)이었다. DM이 칸 번호를 `Context.device`에 실어 둔 자리를
썼다.

## 사용자가 정한 것 (2026-11-04)

- 방식은 새 값 `auto` + vendor 판정. `apple` · `pc`는 지금처럼 모든 키보드에 강제한다.
- 기본값을 `auto`로 바꾼다(design 초안의 추천은 `apple` 유지였다). 일반 노트북의 내장 키보드는 PC 배열이고, 거기에 Apple
  키보드를 꽂는 것이 이 기계의 보통 모습이라서다.
- 게이트는 `input` 체인의 부팅 셋(1차 기본값 + Apple 대역 도구 · 2차 pc · 3차 apple).
- Cmd · Option을 치는 체인(`copy` · `pane` · `pointer` · `dictation` · `hangul`)은 디스크에 `keyboard=apple`을 적는다(A안). 키 이름을
  PC 키로 바꾸는 B안은 주석의 "Cmd"와 누르는 물리 키가 어긋나 읽기 어렵다. 디스크가 없던 부팅은 `gate_lib.sh`의 `apple_disk`.
- KK-M0부터 주요 결정은 Claude에게 위임했다.

## 결정

- 판정은 `input.kindOf(setting, bus, vendor)`(순수 함수). `0x05ac`(bus 무관) 또는 `0x004c`이면서 Bluetooth면 apple. 이름은 안 본다.
- 값은 `main.zig`의 `KeyboardDev.swap_alt_meta`. `takeKeyboard`가 `EVIOCGID`로 정하고 `readKeyboard`가 칸의 값을
  `Context.swap_alt_meta`에 싣는다. `handleKey`는 안 바뀌었다. 칸이 비면 값도 사라지고 다음 키보드가 새로 고른다.
- 설정값은 `tryOpenInput` · `scanInputs` · `drainUevents` · `takeKeyboard`에 인자로 넘긴다(전역을 안 늘렸다).
- 로그: `keyboard> open {path} kind={apple|pc} bus={hex4} vendor={hex4} name={name}`. 강제값에서도 `kind=`를 찍는다. 시작 줄은 `auto`일
  때만 `keyboard=auto (swap_alt_meta=per keyboard)`이고 `apple` · `pc`는 IP-M2 글자 그대로.
- `site/capture.sh`는 호스트에 `mkfs.ext2`가 없어 디스크 대신 `meta_l-` → `alt-`(B안, 게이트가 아니다).

## 함정

1. `input` 체인의 키보드는 QEMU `usb-kbd`가 아니라 PS/2다(`-machine` 없는 기본 `pc` 기계의 i8042, bus 0x11 · vendor 0x0001).
   design의 예시 줄은 `keyboard` 체인의 것이었다. 체인마다 어느 키보드인지 먼저 본다.
2. QEMU `usb-kbd`는 vendor를 못 바꾼다. Apple 키보드의 대역은 uinput 도구(`input/kk/kk-apple`, `tp-replay`의 모양)다. 도구가 친 키는
   terminal을 거쳐 패널의 전경 프로세스에 가므로, 도구는 `&`로 띄우고 정해진 키를 스스로 친다(stdin 명령 없음). 장치를 만든 뒤
   1초 쉬어야 terminal이 uevent로 연다.
3. 새 판정이 "고치기 전 코드에서도 우연히 초록"일 수 있다 — 판정 13은 M0에서 초록이었다(맞바꿈이 전역 거짓). 값은 mutation이
   붙박는다. 마찬가지로 기본값이 apple이던 M0 동안 `config … keyboard=apple` 판정은 디스크가 안 붙어도 초록이었다 —
   `tars-init: loaded /config/tars.conf`가 디스크의 증거다.
4. 기본값을 바꾸면 기본값의 글자를 보는 단위 검사(`reload_test` · `config_edit_test`)와 `config` 체인이 함께 바뀐다. 기본값은
   `shared/screen_args.zig`(`default_keyboard`)와 init `Config.keyboard` 두 자리다.
5. 루트 게이트의 `bluetooth` 체인 btvirt crash 간헐이 M0에서 두 번째로 났다(`carryover.md`). 체인만 다시 돌리면 초록이다.
