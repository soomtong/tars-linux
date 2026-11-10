# SS-M0 — 서버 다섯이 꺼지는 시간 재기

Date: 2026-11-10
Design: `docs/specs/2026-11-10-tars-service-stop-design.md`(결정 3)
Status: 착수(2026-11-10).

## 착수 전에 확정한 것

1. 기계: 루트 게이트가 지은 `out/tars-dev.iso`(`7c853e6` 판, 묶음 열 개)를 devtools 체인과 같은 QEMU(`-cpu SandyBridge -m 2048`,
   16GiB NVMe, OVMF, `-nic none`)로 설치하고 NVMe로 다시 부팅한다. 컨테이너 안에서 돈다(게이트와 같은 이미지).
2. 서버를 켜는 길은 체인과 같다 — root가 `tars-service enable` 다섯(`devtools/check.sh:631`).
3. 재는 길 둘.
   - 진짜 길: 부하(행 · 키 20만) 뒤 `tars-service stop NAME`의 걸린 시간과, init 로그에 `outlived SIGTERM`(3초 넘김 → SIGKILL)이 찍히는가.
   - 신호별: 서비스를 멈춘 뒤 같은 argv(`/proc/PID/cmdline`)를 사용자로 직접 띄우고, 준비되면 부하 → 신호(TERM · INT · QUIT) →
     그 pid가 사라질 때까지(상한 60초, 넘으면 KILL). postgres는 TERM과 INT를 `psql` 세션이 열린 채로도 한 번 더.
4. 전원 끄기: 다섯이 켜진 채 `poweroff` — `shutdown requested`에서 `every child is gone` 또는 `grace period expired`까지를 호스트가 잰다.
   다음 부팅에서 postgres · mysql이 복구를 돌았는지 로그로 본다.
5. 프로브는 `out/ss-m0/probe.sh`(호스트 쪽, devtools 체인의 `boot_guest` · `as_root`를 본뜸)와 `out/ss-m0/guest.sh`(게스트에서 root로 도는
   측정, base64 조각으로 콘솔에 넣는다). 저장소에는 안 넣는다 — 결과 숫자만 이 plan에 남긴다.

## 결과

(측정 뒤에 적는다)
