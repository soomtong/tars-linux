# WL-M0 — 무선을 켜기 전에 아홉을 잰다

> 이 milestone은 커밋되는 코드를 한 줄도 안 고친다. `kernel/.config`는 작업 트리에서만
> 바뀌었고 M1이 그 해소된 모양을 커밋한다. 하네스는 `/tmp/wl/` 아래에 있고 저장소에
> 들어가는 것은 design의 실측 절과 이 plan이다. 사용자가 2026-09-28에 결정을 전부
> 위임해서 plan을 먼저 쓰지 않고 실행한 기록으로 쓴다.

Goal: design의 위험 1~3과 firmware 목록, netns · hostapd 게이트가 서는지를 부팅 다섯으로
답해서 M1이 결정 1~4를 그대로 쓸지 고칠지를 정한다.

Architecture: `scripts/config`로 작업 트리의 `kernel/.config`에 심볼을 켜고 `kernel/build.sh`로
빌드한다. 게스트에 넣을 것(firmware · 측정 hook)은 cpio로 만들어 `kernel/initrd.cpio` 뒤에
이어 붙인다. 탐침은 설정 디스크의 `services.d/probe`다 — `init`이 부팅 때 띄우므로 타이핑이
없다. 부팅은 `-kernel`/`-initrd` · `-nic none` · `-m 512`.

---

## 무엇을 쟀나

| 측정 | 무엇 | design의 자리 | 어디서 |
|---|---|---|---|
| 1 | `olddefconfig`가 끌고 온 것 · bzImage 크기 | 결정 1 | `/tmp/wl/config.diff` |
| 2 | 내장 cmdline과 부트로더 cmdline의 순서, 뒤의 `radios=`가 이기는가 | 결정 2 · 위험 3 | 부팅 A · C |
| 3 | 드라이버가 찾는 firmware 이름, iwlwifi 요청 순서, 크기 | 결정 3 | `modules.builtin.modinfo` · tarball |
| 4 | 새 라이브러리 | 결정 5 | 재귀 `DT_NEEDED` |
| 5 | Debian wpa_supplicant에 `-M`이 있나 | 결정 4 · 위험 2 | 도움말 문자열 |
| 6 | hwsim · netns · hostapd · udhcpd 위에서 연결 → lease → TCP | 결정 7 | 부팅 D |
| 7 | 인터페이스 0개 wpa_supplicant에 hook이 `interface_add`로 넣는가 | 결정 4 | 부팅 E |
| 8 | `regulatory.db`가 서명 검증을 지나는가 | 결정 3 | 부팅 E |
| 9 | firmware가 부팅에 더하는 시간 | 위험 1 | 부팅 A · B |

결과는 design의 "실측 (M0)" 절에 번호 그대로 있다.

## 하네스

- `/tmp/wl/boot.sh` — 부팅 A(지금 initrd) · B(+firmware cpio) · C(B + `radios=2`).
- `/tmp/wl/mkseed2.sh` · `seed2.probe` · `boot2.sh` — 부팅 D. apt로 받은
  wpasupplicant · iw · hostapd · busybox와 라이브러리를 설정 디스크 `/config/wl/`에 넣고
  `LD_LIBRARY_PATH`로 돌린다. `tars.conf`는 `net=dhcp` · `ntp=off`.
- `/tmp/wl/seed3.probe` · `hookroot/` · `boot3.sh` — 부팅 E. 측정 hook `10-wlm0`을 cpio로
  이어 붙인다.

탐침의 shebang은 `#!/usr/bin/bash` 또는 `#!/bin/sh`다. 게스트에 `/bin/bash`는 없다 —
첫 부팅 D가 `execve … failed (errno 2)`로 그것을 알려 주었다.

## M1에 넘기는 것

- 해소된 `kernel/.config`(작업 트리에 있다).
- firmware 목록: iwlwifi 39개(`/tmp/wl/iwl.chosen`) · ath11k `QCA6390/hw2.0` ·
  `WCN6855/hw2.0`(+ `hw2.1`로 한 번 더) · ath12k `WCN7850/hw2.0`(각 `amss.bin` · `board-2.bin` ·
  `m3.bin`, WCN6855은 `regdb.bin`도) · MediaTek 8 · rtw88 5 · rtw89 6 · `regulatory.db` · `.p7s`.
- 결정 4의 새 모양(wrapper `tars-wifi` + hook `10-tars-wifi`).
- 위험 5(firmware가 RAM에 남는다)의 `MemAvailable` 측정.
