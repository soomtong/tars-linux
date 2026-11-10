# SS-M0 — 서버 다섯이 꺼지는 시간 재기

Date: 2026-11-10
Design: `docs/specs/2026-11-10-tars-service-stop-design.md`(결정 3)
Status: 끝났다(2026-11-10).

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

두 판을 돌렸다. 첫 판(1,259초)의 신호별 숫자는 버리고 진짜 길만 남겼다 — 프로브 버그 둘: 함수로 백그라운드에 띄워 `$!`가 서버가 아니라
서브셸이었고(신호가 서버에 안 갔다, 고아 서버가 남아 postgres 서비스가 세 번 못 떴다), redis · nginx는 제 프로세스 제목을 고쳐 써서
`/proc/PID/cmdline`으로 argv를 되살릴 수 없었다. 둘째 판(399초)은 템플릿의 argv를 `( exec setpriv … )`로 띄우고(`$!` = 서버),
`set -m`으로 백그라운드의 INT · QUIT 무시를 껐고(init이 띄운 서비스와 같은 조건), 좀비를 `/proc/PID/stat` 상태로 가렸다.
매 측정 뒤 남은 서버 0. 부하는 행 · 키 20만(postgres · mysql · redis), 숫자는 0.1초 눈금.

1. 진짜 길 `tars-service stop`(SIGTERM): postgres 846ms · mysql 1,440ms · redis 837ms · nginx 434ms · caddy 438ms. 두 판 모두
   `outlived SIGTERM` 0 — 3초 안이다(`tars-service`가 상태를 200ms마다 묻는 몫이 들어 있다).
2. 신호별(서버가 신호를 받은 때부터 사라질 때까지):

   | 서버 | TERM | INT | QUIT |
   |---|---|---|---|
   | postgres | 311ms | 311ms | 168ms(immediate — 다음 기동이 복구) |
   | postgres, `psql` 세션 열림 | 60초 넘김(smart shutdown이 세션을 기다린다) | 315ms | — |
   | mysqld | 1,449ms | 60초 넘김(INT를 안 받는다) | 1,458ms |
   | redis | 150ms | 38ms | 38ms, rc 131(기본 동작 — 코어 덤프) |
   | nginx | 148ms | 30ms | 32ms(점잖은 종료) |
   | caddy | 32ms | 26ms | 27ms, rc 2(Go의 기본 — 스택 덤프) |

3. 전원 끄기(다섯 켜짐, 부하 뒤): `shutdown requested` → `every child is gone` 1,720ms, SIGKILL 없음. 다음 부팅에서 postgres · mysql 모두
   복구 문구 없음. 첫 판은 고아 서버 때문에 `grace period expired` → SIGKILL이었다(측정 오염, 숫자 버림).
4. caddy는 끌 때마다 `servers shutting down with eternal grace period`를 찍는다 — 진행 중인 요청이 있으면 끝없이 기다린다. 열린
   요청으로 끄는 경우는 안 쟀다.

읽은 것: 3초가 모자란 경우는 이 크기의 데이터에서는 없다. 신호가 틀린 경우가 하나다 — postgres의 SIGTERM은 세션이 열려 있으면 안
끝나고(사람이 패널에 `psql`을 띄워 둔 채 `tars-service stop postgres`면 3초 뒤 SIGKILL, 다음 기동이 복구), SIGINT는 세션이 있어도
0.3초다. mysqld는 INT를 무시하므로 신호를 서비스마다 고르는 일(결정 1)이 실제로 필요하다 — 하나의 신호로 다섯을 다 맞출 수 없다.
