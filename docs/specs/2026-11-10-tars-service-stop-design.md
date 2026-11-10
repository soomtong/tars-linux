# TARS Service Stop — Design

접두사: SS

Date: 2026-11-10
Status: 착수(2026-11-10). M0 plan은 `docs/plans/2026-11-10-tars-service-stop-ss-m0.md`.

계기: TP-M11 plan 결과 절의 "남은 것" 둘 — "부팅 때의 CA 한 번이 5초를 넘는 길은 검사가 없다. SV의 stop 3초(SIGKILL)를
서비스마다 늘리는 일" — 을 사용자가 다음 일로 골랐다(2026-11-10, "go with 2"). 두 가지를 사용자가 정했다(같은 날):
서비스마다의 값은 서비스 스크립트의 주석 한 줄에 적는다, 전원 끄기도 범위에 넣는다.

관련 문서: SV design(서비스 감독) · CT design(결정 4, stop의 SIGTERM → 유예 → 그룹 SIGKILL) · SL design(전원 끄기의 TERM · HUP,
유예 3초) · TP-M11 plan(서버 템플릿 다섯, `trust.zig`).

## 한 줄 요약

서비스를 멈추는 두 길(사람의 `tars-service stop` 등, 전원 끄기)이 서비스 스크립트가 적은 신호와 유예를 따르게 하고, 전원 끄기는
서비스를 먼저 끈 뒤 나머지를 지금처럼 끈다. `trust.zig`의 시한 넘김은 명령의 그룹 전체를 죽이고 그 길을 검사한다.

## 확인 (2026-11-10, HEAD `269b045`)

1. 멈추는 길 하나: `control.zig`가 stop · disable · reload에서 빠진 이름에 SIGTERM 한 번, `kill_at = now + GRACE_SECONDS(3)`.
   감독 루프(`main.zig:990`)가 `overdue`면 서비스 그룹(`-pid`)에 SIGKILL. `tars-service`는 `SETTLE_MS` 8초까지 상태를 묻는다
   (`service_cli.zig:33`, 주석은 "최악 5초").
2. 멈추는 길 둘: `power.shutdown`(`power.zig:239`)이 `kill(-1, TERM)` · `kill(-1, HUP)`를 한꺼번에, `reapAll`이 3초(`GRACE_SECONDS`,
   `:182` — "우리 자식은 터미널과 셸뿐"이던 SL 때의 근거), 남으면 `kill(-1, KILL)`. 서비스도 셸과 같은 순간에 같은 두 신호를 받는다.
3. 서버 템플릿 다섯(`devlayer/files/server/etc/tars/services/`)은 끝에서 `tars_exec`로 서버가 된다 — 신호를 받는 것은 서버 자신이다.
   서버별로 알려진 동작(공식 문서, 우리 기계에서 아직 안 쟀다):
   - postgres: SIGTERM = smart shutdown(클라이언트가 다 끊길 때까지 기다린다), SIGINT = fast, SIGQUIT = immediate(다음 기동이 복구). SIGHUP = 설정 다시 읽기.
   - mysqld: SIGTERM = 정상 종료(InnoDB를 비운다 — 데이터 크기에 따라 길다). SIGHUP = 로그 · 캐시 비우기.
   - redis: SIGTERM = 정상 종료(save 설정이 있으면 RDB, `appendonly yes`면 fsync).
   - nginx: TERM · INT = 빠른 종료, QUIT = 점잖은 종료, HUP = 설정 다시 읽기(일꾼을 새로 띄운다).
   - caddy: INT · TERM = 점잖은 종료(`grace_period`).
   그래서 전원 끄기에서 지금은 postgres · nginx가 종료 신호 바로 뒤에 "설정 다시 읽기"를 받는다.
4. TP-M11 체인은 SIGTERM 끄기를 한 번도 보지 않았다 — 부팅 2가 QEMU 죽이기로 끝난다(TP-M11 plan 결과). 부팅 3의 postgres crash
   recovery는 그 때문이다.
5. `trust.refresh`(`trust.zig`): `update-ca-certificates`(셸 스크립트)를 fork · exec, 5초 넘으면 그 pid에만 SIGKILL. 스크립트 아래의
   자식(`run-parts` · `openssl` 등)은 그대로 남아 PID 1의 자식이 된다(감독 루프가 나중에 거둔다). 시한 넘김 길은 어느 검사도 안 밟는다
   — `trust_test`는 이름 · 디렉터리만 본다.

## 결정

### 결정 1 — 서비스마다의 값은 스크립트의 주석 한 줄이다 (사용자 결정)

`# tars-stop: SIG SECONDS` — 예 `# tars-stop: INT 30`. init이 `services.discover`에서 그 파일(링크를 따라)의 앞부분을 읽어 찾는다.
줄이 없으면 지금과 같은 `TERM 3`. 서비스는 계속 파일 하나라 `enable` · `disable`과 링크 모양이 안 바뀌고, 사람이 손으로 만든 서비스도
같은 줄로 고른다. 받는 신호 이름과 초의 범위는 좁게 둔다(신호는 TERM · INT · QUIT · HUP의 넷 정도, 초는 상한이 있다 — 전원 끄기가
기다리는 시간이 이 값으로 정해지므로). 모르는 값은 한 줄 로그 뒤 기본값.

### 결정 2 — 전원 끄기는 서비스를 먼저 끈다 (사용자 결정)

`shutdown`의 순서가 둘로 나뉜다. ① 감독 중인 서비스마다 그 서비스의 신호를 그룹에 보내고, 가장 긴 유예까지(다 죽으면 그 전에)
기다린 뒤 남은 그룹에 SIGKILL. ② 지금의 `TERM` · `HUP` → 3초 → `KILL`을 나머지에. 서비스가 없는 기계(대부분의 게이트 체인)는
①이 빈 단계라 종료 시간이 지금과 같다. 확인 3의 "종료 중의 설정 다시 읽기"도 ①이 없앤다.

### 결정 3 — 값은 재서 정한다

다섯 템플릿의 줄은 M0에서 잰 숫자로 정한다 — SIGTERM과 후보 신호로 끄기까지 걸린 시간, 연결이 열린 경우(postgres의 `psql`)와 아닌 경우.
위 확인 3은 문서에서 온 것이라 그대로 믿고 쓰지 않는다.

### 결정 4 — `trust.zig`는 그룹을 죽인다

자식이 `setpgid(0, 0)` 뒤 exec하고, 시한 넘김은 `kill(-pid, KILL)`. 시한 넘김 길은 명령 경로를 인자로 받는 함수로 떼어
컨테이너 검사(`trust_test`)가 `sleep`과 그 손자를 띄우는 가짜 명령으로 밟는다 — 죽였는가, 손자까지 죽었는가, 한 줄이 남는가.

## milestone

- SS-M0: 측정. 다섯 서버가 신호별로 끄기까지 걸리는 시간(QEMU, 서버 묶음 설치 디스크). 결과로 결정 1의 범위와 템플릿 줄을 정한다.
- SS-M1: 결정 1 · 2 — `services.zig`의 줄 읽기, `control`의 유예가 서비스마다, `power.shutdown`의 두 단계, `tars-service`의 기다림,
  템플릿 다섯의 줄, 체인 판정(서비스 끄기를 실제로 본다).
- SS-M2: 결정 4.

## 비목표

1. 끄는 명령을 따로 두는 길(systemd의 `ExecStop` — 예: `pg_ctl stop`). 신호 하나로 모자라다는 것이 M0에서 보이면 그때 다시 본다.
2. 내장 데몬 다섯(dhcpcd · chronyd · wpa_supplicant · dbus · bluetoothd)의 값 바꾸기 — 그들은 `services.d` 밖이고 기본값 그대로다.
3. 서비스 사이의 끄기 순서(의존). 모두 동시에 신호를 받는다.
