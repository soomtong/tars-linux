---
name: project_power_commands
description: "reboot · poweroff · shutdown · suspend(RB-M0 · LP-M1, 2026-11-05) — /usr/bin/shutdown 스크립트 하나와 링크 셋이 PID 1에 INT · TERM · USR1, 인자 검사(64)가 권한(77, try: sudo)보다 먼저, 내장 suspend 함정"
metadata:
  type: project
---

design `docs/specs/2026-11-05-tars-power-commands-design.md`(RB), `…-laptop-power-design.md` 결정 4(suspend).

## 무엇이 섰나

- `kernel/power/shutdown` → `/usr/bin/shutdown`, 링크 `reboot`(INT) · `poweroff`(TERM) · `suspend`(USR1, LP-M1). 종료 · 잠의 일은 PID 1이다.
- power 체인이 `poweroff`로 끄고 둘째 부팅에서 `reboot`로 셋째 부팅을, home 체인이 사용자의 77을, sleep 체인이 `suspend`를 본다.

## 배운 것

1. 인자 검사가 권한 검사보다 먼저다 — 틀린 명령에 `try: sudo`를 말하면 sudo로 다시 쳐도 틀린다. 모르는 인자를 무시하면
   `poweroff --help`가 기계를 끈다.
2. 인자를 검사한 뒤 `set --`로 비우면 거절 문구의 `try: sudo shutdown -r`이 `-r`을 잃는다 — 처음 받은 인자를 따로 둔다.
3. bash · zsh · fish에 내장 `suspend`가 있다. 사람은 언제나 `sudo suspend`, 체인은 전체 경로.
4. power · device 체인이 `signal handlers installed (TERM, INT)`를 글자 그대로 grep한다 — 시그널을 더할 때 그 줄을 고치지 않고 따로 찍는다.
