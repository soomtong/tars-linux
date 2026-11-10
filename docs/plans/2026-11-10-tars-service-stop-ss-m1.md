# SS-M1 — 서비스마다의 멈춤 신호 · 유예, 전원 끄기는 서비스 먼저

Date: 2026-11-10
Design: `docs/specs/2026-11-10-tars-service-stop-design.md`(결정 1 · 2)
Status: 끝났다(2026-11-10). 값은 사용자 승인("Ok", SS-M0 결과 뒤), plan 승인 "ok".

## 착수 전에 확정한 것

plan을 쓰며 읽은 것(HEAD `083f178`).

1. 값(SS-M0 결과 · 사용자 승인): postgres `INT 10`, mysql `TERM 30`, redis `TERM 10`, nginx · caddy는 줄 없음(`TERM 3`). 유예 상한 60초.
2. 줄의 모양: `# tars-stop: SIG SECONDS`. 신호는 `TERM` · `INT` · `QUIT` · `HUP` 넷, 초는 1~60. 파일의 앞 1,024바이트 안의
   줄만 본다(셸 스크립트의 머리 주석 자리). 줄이 없으면 기본(`TERM 3`)이고 로그도 없다. 줄이 있고 옳으면
   `tars-init: service NAME stops with SIGINT, grace 10s`, 틀리면 `tars-init: service NAME: bad tars-stop line, using SIGTERM 3s`.
3. 칸의 길: `services.Entry`에 `stop: Stop`(`sig` · `grace`), `discover`가 `check` 뒤에 읽는다(링크를 따라 `open`). `main.Child`에
   `stop_sig: linux.SIG = .TERM` · `stop_grace: isize = control.GRACE_SECONDS`. `placeService`(`main.zig:775`)가 Entry의 값을 옮긴다.
   내장 데몬 다섯 · terminal · 셸은 기본값 그대로다(design 비목표 2).
4. 신호를 보내는 자리: 서비스 그룹에 SIGTERM을 보내는 `main.zig`의 세 곳(`:600` · `:757` · `:761`)이 `c.stop_sig`로. terminal의
   `:733`은 그대로 TERM. `control.apply`의 `kill_at = now + GRACE_SECONDS` 둘이 `c.stop_grace`로(규칙은 필드 이름으로만 만지므로
   `control_test`의 가짜 구조체에 필드 하나를 더한다). `outlived` 로그(`:999`)의 초도 `c.stop_grace`.
5. 전원 끄기(`power.shutdown`, `main.zig:976`에서 부른다): 인자로 `services.d` 서비스 중 살아 있는 것의 `{pid, sig, grace, label}`
   목록을 받는다. ① 목록이 비지 않았으면 각 그룹에 그 신호 → 가장 긴 유예까지 그 pid들이 다 거둬지길 기다린다(100ms마다
   `waitpid(-1, WNOHANG)` — 다른 자식이 거둬져도 해가 없다) → 남은 그룹에 SIGKILL. 줄 둘:
   `tars-init: stopping N services first (up to Ms)`, 그리고 `tars-init: services stopped in Xms` 또는
   `tars-init: service NAME outlived SIGxxx by Ms, sent SIGKILL to group P`. ② 지금의 TERM · HUP → 3초 → KILL 그대로.
   목록이 비면 ①의 줄이 없다 — 서비스 없는 체인의 로그는 지금과 같다. 끄기 줄을 보는 체인 다섯(power · device · net · home · sleep)은
   줄이 있는지만 보고 순서는 안 본다(`power/check.sh:190`의 for 등).
6. `tars-service`: 멈춤을 기다리는 `settle`(stop · restart)과 `gone`(disable)의 시한이 `SETTLE_MS` 8초다. 유예 30초인 mysql이 SIGTERM을
   무시하면 8초에 "did not stop"이 먼저 나온다. 멈춤 쪽은 `STOP_SETTLE_MS = (60 + 5)초`(상한 + 거두는 몫), 띄움 쪽은 8초 그대로.

## Task 1 — `services.zig` · `services_test`

- `pub const Stop = struct { sig: linux.SIG = .TERM, grace: isize = 3 }`, `GRACE_MAX = 60`, `pub fn parseStop(line) ?Stop`(순수),
  `pub fn findStop(head: []const u8) StopLine`(`none` · `ok: Stop` · `bad`, 순수 — 앞 1,024바이트의 줄을 돈다).
- `discover`가 `check` 다음에 파일을 열어 앞 1,024바이트를 읽고 `findStop`. 로그는 확정 2.
- 검사: 옳은 줄 넷(신호마다), 틀린 줄(모르는 신호 · 0 · 61 · 숫자 아님 · 칸 셋), 1,024바이트 밖의 줄은 못 본다, 줄 없음.
  `discover`를 /tmp 디렉터리로 — 줄 있는 스크립트 · 없는 스크립트의 Entry 값.

## Task 2 — 감독 루프 · `control`

확정 3 · 4. `control_test`의 가짜 구조체에 `stop_grace`, `apply(.stop)`의 `kill_at`이 그 값을 따르는 검사 하나.

## Task 3 — `power.shutdown`

확정 5. `main.zig`가 목록을 짓는 함수 하나(서비스 칸 `SLOT_SERVICES..`에서 `pid >= 0`인 것). `power_test`는 신호 순서 배열을 보므로
그대로 둔다 — 새 단계는 체인이 본다(Task 6).

## Task 4 — `tars-service`

확정 6. 주석의 "최악 5초"도 고친다.

## Task 5 — 템플릿 셋 · 안내

- `devlayer/files/server/etc/tars/services/{postgres,mysql,redis}`의 둘째 줄 뒤에 `# tars-stop: …` 한 줄과 까닭 한 줄(SS-M0 결과).
- `docs/help/services.md`: 손으로 만든 서비스도 같은 줄을 쓸 수 있다는 짧은 절(신호 넷 · 초 1~60 · 기본 TERM 3).

## Task 6 — 체인 devtools(TP-M1)

부팅 2(다섯이 켜진 뒤):
1. `tars-init: service postgres stops with SIGINT, grace 10s` · mysql `SIGTERM, grace 30s` · redis `SIGTERM, grace 10s`가 있다
   (enable의 reload가 `discover`를 부른다).
2. 사용자로 `psql -c "select pg_sleep(60)"`을 백그라운드에 둔 채 root가 `tars-service stop postgres` → `stopped`가 3초 안,
   `service postgres outlived`가 없다. 그 뒤 `tars-service start postgres`로 되돌린다.
3. 부팅 2의 끝을 QEMU 죽이기에서 `poweroff`로 — `stopping 5 services first` · `services stopped in`이 있고 `outlived` · `grace period expired`가
   없다. 부팅 3의 `PG_RECOVERY` · `MY_RECOVERY`가 `no`여야 한다(지금은 찍기만 한다 → 판정).

## Task 7 — 게이트

컨테이너 init `zig build test` · `make quick` · 체인 devtools 단독 · 루트 게이트.

## 결과

구현 `24485da`(12파일, +363 −20). plan과 다른 자리 · Claude가 정한 것(체인 도중 사용자가 "나머지 결정을 위임합니다"):

1. `servicesFirst`는 `config_off`인데 아직 살아 있는 칸도 넣는다 — reload가 끄는 중인 서비스도 전원 끄기가 기다려 준다(plan 확정 5는
   "살아 있는 것"만 말했다).
2. 템플릿의 줄 아래에 까닭 한 줄씩(영어, 머리 주석과 같은 말)을 두었다 — SS-M0의 숫자를 함께 적었다.
3. 체인의 세션 판정은 `pgrep`이 아니라 `ps -u 1000 -o comm=`으로 센다 — 게스트에 pgrep이 있는지 확인하지 않았고, ps는 SS-M0 프로브에서 돌았다.
4. 검사의 빨강 확인: `findStop`의 잘린 줄 판정을 지우면 `services_test`가 경계 검사에서 빨갛다(되돌림, diff 같음).

게이트:
- 컨테이너 init `zig build test` 47/47 단계, `make quick` PASS.
- 체인 devtools 단독 PASS(빌드 포함 18분 5초): 줄 셋을 읽었다, `psql` 세션이 열린 채 `tars-service stop postgres`가 442ms(SIGKILL 없음 —
  SS-M0에서 같은 조건의 SIGTERM은 60초 넘김), poweroff가 다섯을 먼저 1,335ms에, 부팅 3 복구 postgres no · mysql no.
- 루트 게이트(SS-M2와 함께) 33/33 첫 판(33분 41초 — prebuild 352초 + lanes 1,537초, 잘린 줄 0, `out/gate-logs/20261110-144913`).
  서비스가 있는 다른 체인의 첫 단계: CT-M2(1~3개) · VD-M0 · AU-M3(sshd 1개) 모두 0.1초 안팎. CT의 `stubborn`(SIGTERM을 무시하게
  만든 검사용 서비스)은 기본값 그대로 `outlived SIGTERM by 3s` — 체인의 글자가 안 바뀌었다.
