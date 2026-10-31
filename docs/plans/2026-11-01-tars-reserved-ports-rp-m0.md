# RP-M0 — 게이트 포트를 ephemeral 범위에서 뺀다

Date: 2026-11-01
Design: `docs/specs/2026-11-01-tars-reserved-ports-design.md`
구현: lead가 직접 한다(줄 다섯과 검사 함수 하나).

## 고칠 것

1. `Makefile`
   - `IN_CONTAINER` 위에 `RESERVED_PORTS = --sysctl net.ipv4.ip_local_reserved_ports=45455-45599`를 두고, 왜 있는지 주석을 단다.
   - `IN_CONTAINER`의 `$(DOCKER) run --rm` 뒤에 `$(RESERVED_PORTS)`를 넣는다.
   - `gate:`와 `shell:`의 `docker run` 줄에도 같은 것을 넣는다.
2. `check.sh`
   - `require_reserved_ports` 함수와 상수 `RESERVED_PORTS_WANT=45455-45599`를 둔다. 함수는
     `/proc/sys/net/ipv4/ip_local_reserved_ports`를 읽는다. 그 값이 상수와 다르면 `check FAIL`, 지금 값, 넣어야 할 플래그를
     찍고 1을 돌려준다.
   - `clean` 바로 앞에서 부르고, 실패하면 exit 1로 끝낸다. 빌드보다 먼저 멈춰야 10분을 기다린 뒤에야 아는 일이 없다.
3. `docs/guides/lessons.md` "게이트를 돌리고 읽는 법"의 `docker run` 세 줄에 플래그를 넣고, 왜 넣는지 주석 한 줄을 단다.
4. 새 체인이 포트를 고르는 관례(lessons 92줄 "새 체인은 45495부터")에 "45599를 넘기면 `RESERVED_PORTS` 두 자리를 함께 넓힌다"를
   덧붙인다.

## 게이트

(a) 플래그 없이 띄운다 — 멈춰야 한다.
`docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh`
기대: 몇 초 안에 `check FAIL: … ip_local_reserved_ports …`이 나오고 exit 1. `kernel/build` 등 빌드 로그 줄은 하나도 없어야 한다.

(b) 범위를 다르게 넣는다(옛 범위 45455-45499) — 멈춰야 한다.
기대: (a)와 같고, 지금 값으로 `45455-45499`가 찍힌다.

(c) `make gate` 1회. 기대: 22/22 PASS. 시간은 최근 10분 3초 ~ 10분 23초와 비슷해야 한다. 예약 자체로 느려질 이유는 없다.

(d) `make quick`(shellcheck가 `check.sh`의 새 함수를 본다).

## 끝낼 때

design `Status:` · `docs/guides/completed.md` 한 행 · carryover 항목 체크 · `docs/decisions/` 기억 한 파일 + `MEMORY.md` 한 줄 ·
`HANDOFF.md`. 소개 페이지에는 안 넣는다. 사용자가 보는 기능이 아니다.
