# TARS Password Feedback — Design

접두사: PW

Status: 진행 중(2026-11-05) — PW-M0.

사용자의 요청(2026-11-05): "wifi 패스워드 입력할 때 ****** 이런 표시 나오게". 배경은 MacBook Air 실기 — 아무것도 안 찍히는 칸에서
Wi-Fi 비밀번호와 sudo 비밀번호를 헷갈렸다(`needRoot`로 순서는 HP 때 고쳤다).

관련 문서: HP design(설치 때 계정 비밀번호 · `tars-config passwd`), TC design(`tars-config wifi`), VD design 결정 4(비밀을 인자로 안 받는 이유).

## 한 줄 요약

비밀을 묻는 세 칸이 tty에서 한 글자마다 `*`를 찍는다. 줄 편집을 커널의 canonical 모드에서 우리 코드로 옮기고, 그 코드를 공용 helper
하나(`init/src/secret.zig`)에 둔다. sudo의 칸은 sudoers의 `pwfeedback`으로 같은 모양을 맞춘다.

## 확인 (2026-11-05, `fb40a4b`)

1. 비밀을 읽는 함수가 셋이다. `config_front.readSecret`(wifi passphrase · ssh 공개 키 · Groq 키), `config_front.readSecretLine`
   (`tars-config passwd`의 두 줄), `install.readSecretAnswer`(설치 때 계정 비밀번호). 셋 다 termios의 `ECHO`만 끄고 `ICANON`은 그대로다 —
   Backspace와 줄 모으기를 커널의 line discipline이 하고 프로그램은 Enter 뒤에 한 줄을 통째로 받는다. 글자마다 끼어들 자리가 없다.
2. tty가 아닐 때(파이프)는 셋이 다르다. `readSecret`은 끝까지(여러 줄 키), `readSecretLine`은 한 줄씩(passwd가 두 줄을 같은 stdin에서),
   `readSecretAnswer`는 `readAnswer`의 한 줄. 게이트의 `passwd` · `ssh` · `groq` 판정은 이 길(`printf … | sudo -S`)이다.
3. 지금은 시그널에서 termios를 되돌리는 코드가 없다. Ctrl+C면 프로세스가 echo를 끈 채 죽는다.
4. 설치기는 시리얼 콘솔에서 돌고(home · install 체인의 `send`가 fd 4 = 시리얼) 그 출력이 체인의 `$LOG`에 남는다. 찍힌 `*`를 셀 수 있다.
5. sudo의 비밀번호 칸은 sudo 몫이다. sudoers의 `Defaults pwfeedback`이 같은 `*`를 찍는다(sudo 1.9.x).

## 결정

1. 공용 helper `init/src/secret.zig`. tty 길 하나만 맡고 tty가 아닌 길은 지금처럼 부르는 쪽에 남긴다(확인 2 — 셋이 일부러 다르다).
   `install.zig` 머리의 "공용 모듈을 만들지 않는다"는 이번에 예외다(사용자 결정, 2026-11-05) — termios raw 처리는 세 벌로 복사하기에는
   틀리기 쉽다. 예외라는 것을 그 주석에 적는다.
2. 둘로 나눈다. 순수한 `Editor`(바이트 하나 → 할 일)는 시스템 콜이 없어 `secret_test`가 호스트에서 본다(storage · environ과 같은 선).
   `readMasked`가 termios · read · write를 한다.
3. termios: `ECHO` · `ICANON` · `ISIG`를 끄고 `VMIN=1` · `VTIME=0`. `iflag`는 건드리지 않는다(`ICRNL`이 그대로라 Enter가 `\n`으로 온다 —
   `\r`도 Enter로 받는다). 끌 때 `.FLUSH`(prompt 전에 미리 친 것은 버린다), 되돌릴 때 `.NOW`(다음 답 — YES — 를 버리지 않는다). 순서는 지금
   그대로 "끄고 나서 prompt"(HP-M1 · M2의 교훈).
4. `ISIG`를 끄므로 Ctrl+C는 시그널이 아니라 바이트 `0x03`으로 온다 — 취소. 취소도 정상 끝과 같은 복원 자리를 지난다(확인 3이 풀린다).
5. 키:
   - 보통 바이트(≥ `0x20`, `0x7f` 아님)는 버퍼에. UTF-8 이어지는 바이트(`10xxxxxx`)가 아니면 `*` 하나 — 글자마다 하나다.
   - Backspace(`0x7f` · `0x08`): 버퍼에서 UTF-8 한 글자를 빼고 `\b \b`. 빈 버퍼면 아무것도 안 한다.
   - Ctrl+U(`0x15`): 다 지운다(찍힌 `*`마다 `\b \b`).
   - Enter(`\n` · `\r`): 끝. Ctrl+C: 취소. Ctrl+D: 빈 버퍼면 EOF(지금 canonical의 뜻과 같다), 아니면 무시.
   - ESC 시퀀스(화살표 등): `ESC [`/`ESC O` 뒤 끝 바이트(`0x40`~`0x7e`)까지 삼킨다. 그 밖의 제어 바이트는 무시.
6. 버퍼보다 길면 Enter까지 읽어 버리고 `too_long`(`*`도 계속 찍는다 — 몇 개를 쳤는지는 사람이 본다). 부르는 쪽이 지금처럼 거절한다.
7. `*`는 prompt가 나간 fd로 쓴다 — tars-config는 stderr, 설치기는 `say`의 fd.
8. 붙여 넣는 긴 값(ssh 공개 키 · Groq 키)도 `*`를 찍는다(사용자 결정, 2026-11-05). 수백 개가 줄바꿈하며 지나가는 것이 붙여 넣기가
   들어갔다는 표시가 된다.
9. sudoers에 `Defaults pwfeedback`(사용자 결정, 2026-11-05). `kernel/make_initrd.sh`의 sudoers 한 줄.

## 판정

- `secret_test`: 글자 · UTF-8(한글 한 글자 = `*` 하나) · Backspace가 UTF-8 한 글자를 빼는지 · Ctrl+U · Ctrl+C/D · ESC 시퀀스 · 넘침.
- home 체인: 설치 때 비밀번호 칸에 `hp-secret-1X` + Backspace + Enter를 친다. 로그에 `password [tars-linux]: ` 뒤 `*` 열둘과 `\b \b`가
  나오고, 비밀번호 자체는 로그에 없고(지금 검사), 그 뒤 8b의 `sudo`가 `hp-secret-1`로 통한다 — Backspace가 버퍼에서도 뺐다는 증거다.
- home 체인: `/etc/sudoers`에 `pwfeedback`. sudo의 칸은 게이트가 파이프(`-S`)로만 주므로 모양은 실기가 본다.
- 파이프 길은 기존 판정(8c · 8d의 passwd, ssh · groq)이 그대로 지킨다 — 바뀌면 안 된다.

## 비목표

1. 바깥에서 온 SIGTERM · SIGHUP에서 termios 되돌리기. 지금과 같다(사람이 치는 Ctrl+C는 결정 4로 풀린다).
2. 커서 이동 · 가운데 고치기. 비밀번호 칸에서 보이지 않는 글자를 옮겨 다니는 편집은 하지 않는다.
3. "보이기" 토글.

## 위험

1. 시리얼 콘솔의 erase 문자가 `0x08`인 터미널이 있다 — 둘 다 받는다(결정 5).
2. 터미널 너비를 넘는 `*` 줄에서 `\b`는 앞 줄로 못 올라간다(대부분의 VT). 긴 키를 붙여 넣은 뒤 Backspace의 화면이 어긋날 수 있다 —
   버퍼는 맞다. 비밀번호 길이에서는 안 일어난다.

## Milestone

- PW-M0 — 위 결정 아홉. lead가 직접.
