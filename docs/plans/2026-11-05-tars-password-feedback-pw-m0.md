# PW-M0 — 비밀번호 칸의 `*`

> 구현은 lead가 직접 넣었다(2026-11-05, 사용자 "continue from handoff" · "공용 helper 추가해"). 줄 번호는 `fb40a4b` 기준이라
> 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다. 결과는 끝의 "결과" 절.

Goal: PW design 결정 1~9. 비밀을 묻는 세 칸이 tty에서 글자마다 `*`를 찍고, sudo의 칸도 같게.

## 할 일

1. `init/src/secret.zig` — `Editor`(순수) · `readMasked`(termios · read · write). `Result = line | eof | cancel | too_long`.
2. `init/src/secret_test.zig` + `init/build.zig`의 `secret_test`(host_target, `zig build test`).
3. `config_front.readSecret` · `readSecretLine`: tty면 `readMasked(2, …)`. 취소 · EOF는 `ttySecret`이 `cancelled; nothing was changed`와
   130으로 끝낸다 — 부르는 쪽의 null은 "너무 길다"이고 빈 값은 빈 passphrase라서다. 파이프 길은 그대로.
4. `install.readSecretAnswer`: tty면 `readMasked(1, …)`(`say`의 fd). 취소는 `.eof`(아무것도 안 바꾸고 끝).
5. `kernel/make_initrd.sh` sudoers에 `Defaults pwfeedback`.
6. home 체인: 설치 비밀번호를 `hp-secret-1X` + `0x7f`로 치고 `*` 열둘 + `\b \b`, 8a 뒤 sudoers의 `pwfeedback` 한 줄.

## 판정

- `make quick`, 컨테이너의 `zig build test`(secret_test 18경우).
- home 체인(새 검사 둘 + 8b가 `hp-secret-1`로 통한다 = Backspace가 버퍼에서도 뺐다), install 체인(기본값 Enter 길의 회귀).
- 루트 게이트.

## 결과

(게이트 뒤에 채운다)
