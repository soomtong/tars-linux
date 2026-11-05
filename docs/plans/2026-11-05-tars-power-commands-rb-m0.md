# RB-M0 — reboot · poweroff · shutdown

> 구현은 lead가 직접 넣었다(2026-11-05, 사용자 "continue from handoff"). 줄 번호는 `1c62755` 기준이라 낡을 수 있다 — 고치기 전에
> `rg`로 다시 찾는다. 결과는 끝의 "결과" 절.

Goal: RB design 결정 1~5. 사람이 `sudo reboot` · `sudo poweroff`로 끄고 켠다.

## 할 일

1. `kernel/power/shutdown` — `${0##*/}`로 갈린다. 인자 검사(64) → `id -u`(77, `try: sudo <이름> <인자>`) → 한 줄 → `exec kill -s INT|TERM 1`.
2. `kernel/make_initrd.sh` — `/usr/bin/shutdown`(0755)과 상대 링크 `reboot` · `poweroff`.
3. power 체인 — 부팅 1이 `kill -TERM 1` 대신 `poweroff`를 친다. 부팅 2는 Ctrl+Alt+Del 뒤 둘째 부팅에서 `reboot`를 쳐 셋째 부팅과 둘째
   `action restart` · `calling reboot(RESTART)`를 본다. 고리 감시는 셋을 넘는지.
4. home 체인 — 8d 뒤 사용자로 `reboot` · `poweroff` · `shutdown -r now`가 77과 `try: sudo …`, `shutdown +5`가 64, `tars-init: shutdown
   requested`가 없다.
5. `docs/guides/running-tars.md` — 설치 뒤 `reboot`, sudo 문단에 `sudo reboot` · `sudo poweroff`. 옛 ISO 문단(405행 부근)의
   `kill -INT 1`은 그대로 — 그 ISO에는 이 명령이 없다. 옛 seed 별칭 절(그 안의 `kill -INT 1`)은 같은 날의 별칭 정리가 통째로 지웠다.

## 판정

- 호스트에서 스크립트의 인자 · 권한 여덟 경우(사용자 권한이라 시그널까지 안 간다): 64 셋, 77 다섯, 문구가 명령을 그대로 되풀이.
- power 체인 · home 체인, 그다음 루트 게이트(PW-M0과 함께).

## 결과

- 호스트 여덟 경우는 첫 판에 하나가 틀렸다 — `shutdown`이 인자 검사 뒤 `set --`로 비워 `try: sudo shutdown -r`이 `-r`을 잃었다.
  처음 받은 인자를 `given`에 두었다.
- power 체인 PASS. 부팅 1은 `poweroff`로 기존 검사 그대로, 부팅 2는 `calling reboot(RESTART)` 두 번(Ctrl+Alt+Del · `reboot`)과 셋째 부팅.
- home 체인 PASS. 사용자로 셋이 77과 `try: sudo …`, `shutdown +5`가 64, `tars-init: shutdown requested` 없음.
- 루트 게이트 29/29(PW-M0과 같은 판).
