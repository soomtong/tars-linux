---
name: project_pointer_devices
description: 마우스와 터치패드가 화면의 화살표 하나를 움직이고, 끌어 뗀 글자가 클립보드에 들어가며, 자식이 원하면 마우스를 보고하는 층(PD-M0~M4, 2026-10-05). 탐색은 terminal이 uevent로 하고, 커서는 save-under, 선택은 copy mode의 기계 그대로다. inotify를 켰다가 install 체인이 깨진 일과 그 진짜 원인(TCG의 코드 배치)이 여기 있다.
metadata:
  node_type: memory
  type: project
---

2026-10-05 사용자의 요청 "마우스 장치 지원: 마우스 포인터 및 인터렉션(드래그 선택).
터치패드 역시 지원"으로 열어 같은 날 닫았다. 사용자는 결정권을 lead(Fable)에게
위임했고, design과 plan 넷은 Opus 서브에이전트가, 구현은 M0 · M2 · M3을 Opus,
M1을 Sonnet 서브에이전트가 plan만 보고 했다. lead는 실측 · 대조 · 게이트 · commit을
맡았다. design은 `docs/specs/2026-10-05-tars-pointer-devices-design.md`.

무엇이 섰나.

- 탐색(M0). 키보드는 여전히 init이 찾아 `argv[4]`로 넘기지만, 포인터 장치는
  terminal이 스스로 찾는다 — `/dev/input`을 훑고 연 fd에 `EVIOCGBIT` · `EVIOCGPROP` ·
  `EVIOCGNAME`으로 성질을 묻고(`pointer.classify`: mouse · touchpad · none), 부팅
  뒤에 꽂힌 것은 커널의 uevent netlink 소켓(`NETLINK_KOBJECT_UEVENT`, 그룹 1)으로
  안다. 빠진 장치는 그 fd의 `POLLHUP` · `ENODEV`로 안다. HD 결정 3("하드웨어는 PID 1이
  찾는다")을 포인터에 한해 바꾼 것이다 — 포인터는 terminal만 쓰므로 탐색기가 두 벌이
  되지 않고, 핫플러그를 볼 수 있는 프로세스는 계속 살아 있는 terminal이다.
- 커서(M1). 12 × 19 화살표를 전용 색 둘로 그리고(`ink` 118), 움직임만 있는 회차는
  화면을 다시 그리지 않고 save-under(저장한 픽셀 되돌리기 → 새 자리 저장 → 그리기 →
  `present`)만 한다. 셀이 바뀐 프레임은 `present` 직전에 새로 그린다. 보이는 조건 셋 —
  장치가 있다 · 열린 뒤 움직였다 · 그 뒤로 `keys.bytes`가 PTY에 나가지 않았다. 휠 한
  눈금은 포인터 아래 패널을 세 줄(`REL_WHEEL_HI_RES`는 버린다).
- 상호작용(M2). 누름은 패널 포커스를 옮기고 위치를 기억한다. 처음으로 다른 칸에 닿을 때
  copy mode에 들어가(`copyEnterAt`) 끄는 동안 `copyPointTo`로 선택을 늘리고, 뗌이
  `copyYank`(클립보드 + 모드 종료 — `Cmd+C`와 같은 바이트)다. 입력 모드의 두 사본
  (`input.State.mode` · `vt.Screen.copy_cursor`)을 `pointerMode`가 함께 옮긴다 —
  한쪽만 바꾸면 끈 뒤 친 키가 셸로 새거나 삼켜진다. 끄는 칸은 누른 패널 사각형으로
  clamp하고, 누른 채 휠이 가장자리 자동 스크롤의 대신이다.
- 터치패드(M3). `touchpad.zig`가 MT 프로토콜 B를 `pointer.Frame`으로 번역한다 — 한
  손가락 이동(패드 가로 = 화면 가로, resolution으로 세로 보정) · 탭(180ms · 2%) · 두
  손가락 세로 → 휠(48px마다 한 눈금) · 물리 `BTN_LEFT` 통과. 커널은 PS/2(psmouse ·
  synaptics · elantech · alps) · SMBus(RMI4 · elan_i2c · I2C_I801) · I2C-HID
  (hid-multitouch · DesignWare · LPSS · pinctrl · THC QuickI2C) 세 경로와 uinput을
  켰다. QEMU에 터치패드가 없어 게이트는 게스트 uinput으로 가짜 패드를 만드는
  `tp-replay`(설정 디스크, 부팅 B)로 끝까지 본다.

배운 것 — 다시 조사하지 말 것.

1. `CONFIG_INOTIFY_USER=y`를 켜면 `FSNOTIFY`가 따라 켜지고, 그 커널은 TCG에서 initramfs
   풀기가 2.6초 → 3.8초로 늦어져 `install` 체인 부팅 7(`usb-storage.delay_use=3`)의
   창이 닫혔다. 루트 게이트가 두 번 빨갰고 단독 재현이 결정적이었다. M3이 같은 증상을
   다시 겪으며 진짜 원인을 찾았다 — 드라이버가 아니라 코드 배치다. gzip `inflate_fast`가
   커널 이미지 안에서 페이지 경계를 넘게 밀리면 QEMU TCG가 그 번역 블록을 직접 잇지 못해
   풀기가 0.8초 늦어진다(HEAD 설정에 `X86_INTEL_LPSS` 하나만 켠 커널로 확인). M0의
   FSNOTIFY도 같은 것이었을 가능성이 크지만 그때 System.map을 안 봐서 재지 않았다.
   실기와 무관한 게이트의 비용이고, 어느 커널 변경이든 다시 움직일 수 있다. M3이 부팅 7의
   `delay_use`를 4로 올려 여유를 1.1초로 되돌렸다.
2. ioctl 매크로(`EVIOCGBIT` 등)는 ZU-M1의 translate-c 패키지가 inline fn으로 넘긴다.
   HD 조사 6("매크로라 안 넘어온다")은 `@cImport` 시절의 사실이다.
3. OrbStack VM(4GB)에서 cold `zig build`(약 3GB)와 다른 컨테이너의 QEMU가 겹치면 OOM
   (exit 137)이나 VM 재시작이 난다. docker 작업은 한 번에 하나만 돌린다.
4. QEMU HMP `mouse_move` · `mouse_button`은 `-display none`에서도 usb-mouse로 가고,
   `device_add usb-mouse,id=…` · `device_del`이 핫플러그를 만든다. 127을 넘는 이동은
   보고 셋으로 쪼개지고 합은 보존된다. 휠 한 눈금에 `REL_WHEEL_HI_RES` ±120이 함께 온다.
5. 게스트에 `od` · `xxd` · `timeout`이 없다 — 바이트는 `head -c N | cat -v`. `sendkey
   colon`은 없는 이름이고 `:`는 `shift-semicolon`이다.
6. 루트 게이트 반복을 3에서 2로 줄였다(`feedback_gate_runs`). 3회 1시간 8분이 2회 47분
   46초가 됐다.
7. 자식이 받는 이스케이프 바이트를 게이트가 보는 법 — 설정 디스크에 bash 스크립트를 싣고
   `read -N`으로 받아 `cat -v` 모양으로 화면에 찍게 한 뒤, 우리 로그 줄과 같은 글자로 맞춘다
   (PD-M4 검사 26~32). Shift는 HMP `sendkey shift 3000`으로 누른 채 두고 그 사이에 마우스를
   움직인다 — 마우스 사건은 키 큐를 안 거친다.

- 마우스 보고(M4, 같은 날 사용자의 결정 "같은 맥락이라 새 마일스톤으로 빼는 것이 합리적이지
  않다"로 비목표 1을 열었다 — design 결정 12). 누른 패널의 자식이 모드 9 · 1000 · 1002 · 1003을
  켰고 copy mode가 아니고 Shift가 없으면 그 누름은 자식의 것이다 — 첫 누름이 주인(`Grab`)을
  정해 마지막 뗌까지 간다. 바이트는 ghostty의 `encodeMouse`가 짠다(형식 다섯이 공짜). 포커스가
  아닌 패널이면 포커스를 먼저 옮기고 그 패널에 보고한다(tmux 순서). 휠은 copy mode면 무시 ·
  Shift면 우리 스크롤 · 자식이 원하면 버튼 4 · 5 · 대체 화면에 1007이면 화살표 키 세 번 · 그 밖은
  우리 스크롤. 게스트 vimrc가 `mouse=a ttymouse=sgr`이 됐고 GE 원칙 3("우리가 안 하는 것을
  켜지 않는다")의 전제가 바뀌었다. 게이트는 설정 디스크의 bash `read -N` 프로브가 받은 바이트와
  우리 `pointer> report` 줄을 같은 글자로 맞춘다.

열지 않은 것(design 비목표): 더블클릭 단어 선택 · 가장자리 자동 스크롤 · 절대 좌표 장치
(usb-tablet · 터치스크린) · 뗀 뒤 반전 남기기 · 포인터 가속과 터치패드의 나머지(손바닥
거부 · 세 손가락 · 관성) · `tars.conf` 항목(휠 방향이 첫 후보) · 왼손잡이 · 키보드 핫플러그 ·
Apple 트랙패드 · 패널 비율 드래그 · 시간 기반 숨김 · THC QuickSPI.

관련: [[project_device_discovery]] · [[project_copy_mode]] · [[project_workspace_panes]] ·
[[project_kernel_config]] · [[feedback_gate_runs]].
