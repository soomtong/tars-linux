---
name: project_password_feedback
description: "비밀번호 칸의 `*`(PW-M0, 2026-11-05) — init/src/secret.zig가 tty에서 ICANON · ISIG까지 끄고 글자마다 `*`, 파이프 길은 부르는 쪽 그대로, Ctrl+C는 바이트로 받아 복원 자리를 지난다, sudoers pwfeedback"
metadata:
  type: project
---

design `docs/specs/2026-11-05-tars-password-feedback-design.md`, plan `docs/plans/2026-11-05-tars-password-feedback-pw-m0.md`.

## 무엇이 섰나

- `init/src/secret.zig` — `Editor`(순수, `secret_test`)와 `readMasked`(termios · read · write). `tars-config`의 `readSecret` · `readSecretLine`과
  `tars-install`의 `readSecretAnswer`가 tty일 때만 부른다. "공용 모듈을 만들지 않는다"(devices.zig)의 예외다(사용자 결정).
- sudoers `Defaults pwfeedback`.

## 배운 것

1. `ECHO`만 끄면 canonical 모드라 줄 편집을 커널이 하고 프로그램은 Enter 뒤에야 받는다 — `*`를 찍으려면 `ICANON`을 끄고 Backspace ·
   Ctrl+U를 우리가 맡아야 한다. `ISIG`도 끄면 Ctrl+C가 바이트(0x03)로 와서 시그널 없이 termios 복원 자리를 지난다.
2. tars-config의 null은 "너무 길다"로 읽힌다 — 취소를 null로 넘기면 틀린 말, 빈 값으로 넘기면 빈 passphrase다. 취소는 그 자리에서
   `cancelled; nothing was changed`와 130으로 끝낸다(무엇을 쓰기 전이다).
3. Zig 0.17에는 배열 반복 연산자(`**`)가 없다 — comptime 함수로 잇는다.
4. 게이트의 판정은 시리얼 설치기 칸에 `hp-secret-1X` + 0x7f를 치고 `*` 열둘과 `\b \b`를 센 뒤, 8b의 sudo가 `hp-secret-1`로 통하는지로
   "버퍼에서도 뺐다"를 본다.
