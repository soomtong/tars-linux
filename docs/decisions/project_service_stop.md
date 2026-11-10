---
name: project_service_stop
description: "서비스 멈춤 신호 · 유예는 스크립트 머리의 `# tars-stop: SIG SECONDS` 한 줄(SS, 2026-11-10). 전원 끄기는 services.d 서비스를 먼저 각자의 신호로 끈다. postgres는 SIGINT(SIGTERM은 열린 세션을 기다려 안 끝난다), mysqld는 SIGINT를 무시한다. CA 갱신 시한 넘김은 그룹째 죽인다. 측정 프로브의 함정 셋"
metadata:
  node_type: memory
  type: project
---

SS(Service Stop, 2026-11-10)가 세웠다. design `docs/specs/2026-11-10-tars-service-stop-design.md`, plan `-ss-m0` · `-ss-m1` · `-ss-m2`.

## 무엇이 섰나

- services.d 스크립트의 앞 1,024바이트에 `# tars-stop: INT 10` — 신호는 TERM · INT · QUIT · HUP, 초는 1~60. 줄이 없으면 TERM 3(옛 동작),
  틀리면 한 줄 로그 뒤 기본. init이 `services.discover`에서 읽어 `Child.stop_sig` · `stop_grace`로 옮긴다. 사용자 결정: 설정은
  스크립트 주석 줄(옆 파일 · 전역 값보다), 전원 끄기도 범위.
- 전원 끄기(`power.shutdown`)는 ① services.d 서비스에 각자의 신호, 가장 긴 유예까지(다 거둬지면 그 전에) → 남으면 그룹 SIGKILL,
  ② 나머지에 TERM · HUP → 3초 → KILL(SL 그대로). 서비스가 없으면 ①의 줄도 없다. 내장 데몬 다섯은 ②에 남는다.
- `tars-service`의 멈춤 기다림은 65초(상한 60 + 5), 띄움은 8초 그대로.
- 템플릿: postgres `INT 10`, mysql `TERM 30`, redis `TERM 10`, nginx · caddy 줄 없음.
- CA 갱신(`trust.runWithin`)은 명령에 프로세스 그룹을 주고 시한 넘김에 그룹째 KILL — 셸 스크립트의 손자(run-parts · openssl)가 남지 않는다.

## 잰 것 (SS-M0, QEMU SandyBridge · 2GiB, 행 · 키 20만)

진짜 길 `tars-service stop`은 다섯 모두 1.5초 안. 신호별: postgres TERM 0.3초지만 `psql` 세션이 열리면 60초 넘김(smart shutdown),
INT는 세션이 있어도 0.3초. mysqld TERM 1.4초, INT는 무시(60초 넘김). redis · caddy의 QUIT은 정상 종료가 아니라 덤프. 하나의 신호로
다섯을 다 맞출 수 없다 — 그래서 서비스마다다. 3초가 모자란 경우는 이 크기에서는 없었다. caddy는 끌 때마다
`eternal grace period`를 찍는다(진행 중 요청이 있으면 끝없이 기다린다 — 안 쟀다, 유예 뒤 SIGKILL이 받친다).

## 측정 프로브의 함정 (다시 재면 피할 것)

1. bash 함수를 `&`로 띄우면 `$!`는 서브셸이다 — 신호가 서버에 안 가고 고아 서버가 남는다. `( exec setpriv … 서버 ) &`로 띄운다.
2. 비대화형 bash는 백그라운드 작업의 INT · QUIT를 SIG_IGN으로 두고 그것이 exec를 넘는다 — `set -m`을 켜야 init이 띄운 것과 같은 조건이다.
3. 내 자식은 죽어도 wait 전까지 좀비라 `kill -0`이 성공한다 — `/proc/PID/stat`의 상태 Z로 본다. 그리고 redis · nginx는 프로세스 제목을
   고쳐 써서 `/proc/PID/cmdline`으로 argv를 되살릴 수 없다.

관련: [[project_dev_layer]](TP-M11 서버 템플릿) · [[project_zig_upgrade]]
