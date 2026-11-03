---
name: project_init_keyboard
description: "Init Keyboard(IK-M0, 2026-11-03 끝남) — KH 뒤로 아무도 안 쓰던 PID 1의 키보드 고르기 · 3초 기다림 · terminal argv의 장치 칸을 걷었다. ARGC 10→9(칸은 null로 비울 수 없어 뺐다), 체인 넷은 terminal의 keyboard> open과 init 줄의 부재로 판정. 키보드 없는 부팅의 Run /init → started terminal이 3.39초에서 0.06초로. 함정 — ARGC 길이 배열 리터럴은 이름 붙은 상수 다섯 말고도 main.zig에 둘 더 있었다(컴파일러가 짚었다)"
metadata:
  node_type: memory
  type: project
---

# Init Keyboard (IK)

design은 `docs/specs/2026-11-03-tars-init-keyboard-design.md`, plan은 `docs/plans/2026-11-03-tars-init-keyboard-ik-m0.md`.
`carryover.md` KH 절의 첫 항목이었다. KH(Keyboard Hotplug)가 키보드 고르기를 terminal로 옮긴 뒤 init의 탐색기는 결과를 아무도
안 여는 코드였고, 키보드 없는 부팅만 3초 늦게 만들었다.

## 사용자가 정한 것 (2026-11-03)

1. argv의 `Slot.device` 칸은 빼고 `ARGC` 10→9. 자리표 글자를 두지 않는다 — execve의 argv는 첫 null에서 끝나 null로 비우면 뒤
   칸(자판 · 클립보드 · 사용자)이 잘린다.
2. 체인 넷(`device` · `terminal` · `machine` · `keyboard`)의 판정을 terminal의 `keyboard> open /dev/input/eventN name=…`으로
   옮기고, init 키보드 줄(`keyboard device` · `no keyboard found`)의 부재를 음성 검사로 더한다.

## 결정

- init의 `devices.zig`에 남은 것은 전원 버튼의 길뿐이다. `looksLikeKeyboard`는 남는다 — 전원 버튼 판정이 "키보드는 후보가
  아니다"를 가르는 데 쓴다(AT 키보드도 KEY_POWER를 갖는다).
- 전원 버튼 탐색은 PID 1의 것으로 남는다(design 비목표 2) — 기계를 끄는 것이 PID 1이다.
- terminal 줄의 내용을 보는 판정은 `tlog |`를 거친다(GF-M2 — 커널 printk가 terminal 줄을 자른다).
- 3초가 사라진 것은 게이트에 넣지 않고 일회용 측정으로 한 번 적었다(design 결정 4) — `-serial file:` 체인은 콘솔에 명령을 못
  넣고 init 줄에는 시각이 없다.

## 함정

1. `ARGC` 길이 배열 리터럴은 이름 붙은 상수 다섯(`clock` · `net` · `wifi` · `bluetooth` 둘) 말고도 `main.zig`에 둘 더 있다 —
   `placeService`의 서비스 argv와 콘솔 셸의 argv. `ARGC`를 바꾸면 컴파일러가 짚어 주므로 목록을 미리 셀 필요는 없다.
2. 칸을 빼면 뒤 칸 번호를 숫자로 적은 주석이 낡는다("7번 칸" 같은 것, `screen_args.zig`의 `encode` · `main.zig`의
   `terminal_toggle_buf`). `rg '[0-9]번 칸'`으로 찾는다.

숫자는 design의 실측 0~3(3이 루트 게이트). 관련: [[project_keyboard_hotplug]] · [[project_screen_args]].
