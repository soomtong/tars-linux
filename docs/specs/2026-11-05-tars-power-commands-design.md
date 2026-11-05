# TARS Power Commands — Design

접두사: RB

Status: 닫힘(2026-11-05) — RB-M0 `/usr/bin/shutdown` + 링크 둘, power 체인의 `poweroff` · `reboot`(셋째 부팅), home 체인의 77.

사용자의 요청(2026-11-05): `reboot` · `poweroff`(또는 `shutdown`) 명령. 지금 사람의 길은 `sudo kill -INT 1`뿐이고 가이드도 그렇게 적었다.

관련 문서: PM design(PID 1의 시그널 갈래), HP design(사용자 · sudo · `try: sudo`의 말), BT 실기 수정(`/usr/bin/bluetoothctl` 감싸개의 모양).

## 한 줄 요약

`/usr/bin/shutdown` 셸 스크립트 하나와 그것을 가리키는 `reboot` · `poweroff` 링크 둘. 이름을 보고 PID 1에 `SIGINT`(재부팅) 또는
`SIGTERM`(전원 끄기)를 보낸다. root가 아니면 `try: sudo`로 끝난다.

## 확인 (2026-11-05, `fb40a4b`)

1. PID 1은 이미 갈래를 갖고 있다 — `.TERM => .power_off`, `.INT => .restart`(`init/src/power.zig`). Ctrl+Alt+Del도 SIGINT로 온다(PM-M1).
   그 뒤의 정리(자식에게 SIGTERM · SIGHUP, 유예, sync, `reboot(2)`)는 PID 1이 한다 — 명령이 할 일은 시그널 하나다.
2. 게스트의 `/bin/sh`는 bash이고 `kill` · `id`가 있다(procps · coreutils, `guest_tools.sh`).
3. 사람이 치는 감싸개는 이미 셸 스크립트로 둔 선례가 있다(`kernel/bluetooth/bluetoothctl`).
4. `tars-config`의 거절은 `tars-config: permission denied; try: sudo tars-config …`와 77이다(`config_cli.denied`, `EXIT_DENIED`).
5. power 체인이 부팅 1에서 `kill -TERM 1`을 치고 전원이 꺼지는 것을, 부팅 2에서 Ctrl+Alt+Del로 재부팅되는 것을 본다.

## 결정

1. 셸 스크립트 하나(`kernel/power/shutdown` → `/usr/bin/shutdown`)와 링크 둘(`/usr/bin/reboot` · `/usr/bin/poweroff` → `shutdown`). 할 일이
   시그널 하나라 Zig 실행 파일 · init 소켓은 실익이 없다. `${0##*/}`로 갈린다.
2. root가 아니면 `<이름>: permission denied; try: sudo <이름> <인자>`와 77(확인 4와 같은 말 · 같은 값). 시그널을 보내 보기 전에 `id -u`로
   본다 — `kill`의 `Operation not permitted`는 무엇을 해야 하는지 말하지 않는다.
3. 인자: `reboot` · `poweroff`는 인자를 받지 않는다. `shutdown`은 `-r`(재부팅) · `-h` · `-P`(전원 끄기, 기본) · `now`를 받는다. 그 밖의 것
   (`+5`, `--help`, 시각)은 `usage:` 한 줄과 64로 거절한다. 모르는 인자를 무시하면 `poweroff --help`가 기계를 끈다.
4. 시그널을 보낸 뒤 한 줄(`reboot: restarting` · `poweroff: switching off`)을 찍고 0으로 끝난다. 그 뒤는 PID 1의 일이다(확인 1).
5. 가이드의 `kill -INT 1`은 `sudo reboot`로 바꾼다(`running-tars.md`). 화면에서 root인 경우(사용자 없는 ISO)는 `reboot` 그대로다.

## 판정

- power 체인 부팅 1: `kill -TERM 1` 대신 `poweroff`를 친다. 그 뒤의 검사(전원이 꺼진다, `action power_off`, `calling reboot(POWER_OFF)`)는
  그대로다 — 스크립트가 같은 시그널을 보냈다는 증거다.
- power 체인 부팅 2: Ctrl+Alt+Del 재부팅(이 체인의 심장)은 그대로 두고, 그 뒤 zsh가 뜨면 `reboot`를 친다. 셋째 부팅과 둘째
  `action restart`를 본다. 재부팅 고리 감시는 셋을 넘는지로.
- home 체인: 사용자로 `reboot` · `poweroff` · `shutdown -r`이 77과 `try: sudo …`. 기계는 안 꺼진다(다음 검사가 이어진다).
  사용자로 `shutdown +5`는 77이 아니라 64다 — 인자 검사가 권한 검사보다 먼저다. 틀린 명령에 `try: sudo`를 말하면 sudo로 다시 쳐도
  틀린다.

## 비목표

1. 예약 종료(`shutdown +5` · 시각), `wall` 알림, `-c` 취소.
2. `halt`(멈추고 전원은 그대로). PID 1에 그 갈래가 없다.
3. `systemctl reboot` 같은 이름.

## 위험

1. 사람이 `sudo reboot`의 비밀번호를 묻는 사이 다른 패널의 작업이 있다 — PID 1의 정리는 셸 히스토리 · sync를 이미 한다(SL · SD · BH).

## Milestone

- RB-M0 — 위 결정 다섯. lead가 직접.
