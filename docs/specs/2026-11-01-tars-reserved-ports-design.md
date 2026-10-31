# TARS Reserved Ports — Design

Date: 2026-11-01
Status: 끝났다 — RP-M0(2026-11-01, 플래그 없이 · 옛 범위로 띄우면 0.4초에 `check FAIL`, `make gate` 22/22 10분 22초(prebuild 321 + lanes 299초), verify 8126줄). plan은 `docs/plans/2026-11-01-tars-reserved-ports-rp-m0.md`

UB-M2가 남긴 작은 후보(`docs/guides/carryover.md` "미룬 것"의 첫 항목). 사용자가 골랐다(2026-11-01).

## 한 줄 요약

게이트 체인이 쓰는 포트 45455~45599를 컨테이너의 ephemeral 범위에서 빼서, 다른 lane이 밖으로 연결할 때 그 번호를 출발 포트로
받는 일을 없앤다. `docker run --sysctl net.ipv4.ip_local_reserved_ports=45455-45599`를 Makefile의 두 자리(`gate` · `IN_CONTAINER`)와
lessons의 `docker run` 세 줄에 넣는다. 루트 `check.sh`는 시작할 때 예약이 걸렸는지 읽고, 안 걸렸으면 빌드 전에 멈춘다. 코드(Zig) 0줄.

## 배경

- UB-M2 루트 게이트 2회차(2026-10-31)에서 VD-M0이 `openssl s_server died at startup`으로 빨갰다. 45492를 쓰는 체인은 dictation
  하나뿐이고, 단독으로 다시 돌리면 PASS였다(로그 `out/gate-logs/20261031-141844/VD-M0-1/`). 컨테이너의 `ip_local_port_range`는
  32768~60999이고 체인 포트 45455~45494가 전부 그 안에 있다. 다른 lane의 curl · SLIRP 연결이 45492를 출발 포트로 받은 순간에는
  `s_server`의 `bind()`가 `Address already in use`로 실패한다.
- 이 충돌은 GP-M2(2026-10-10)가 체인을 동시에 돌리기 시작하면서 생길 수 있게 됐다. 그 전에는 한 번에 한 체인만 돌아서 부딪칠
  다른 연결이 없었다. 확률은 낮다(출발 포트 28,232개 가운데 40개). 하지만 게이트가 빨개지면 원인을 가르는 데 매번 단독 재실행
  한 번(수 분)이 든다.

## 착수 전에 확인한 것

2026-11-01, HEAD `de0c984`.

1. 체인이 쓰는 포트. 셸 스크립트 전체에서 4xxxx 숫자를 셌다. 45455~45494가 체인 몫이고 빈 번호는 없다. 새 체인은 45495부터 쓴다는
   관례가 lessons(92줄) · `project_gate_parallel.md` · `probe/run.sh` 주석에 있다. 체인 밖에서는 `probe/run.sh`가 45590,
   `site/capture.sh`가 45600을 쓴다. 40000 · 48000은 포트가 아니다(audio의 음량 문턱과 샘플레이트).
2. 예약은 출발 포트 배정만 막는다. 실험에서 `ip_local_port_range`를 45450~45460으로 좁히고 perl로 연결을 열둘 열었다.
   - 예약이 없을 때: 출발 포트가 45450~45460 열한 개를 다 받았다. 45455~45460도 들어 있었다. 12번째 연결은
     `Cannot assign requested address`.
   - 45455~45499를 예약했을 때: 45450~45454 다섯 개만 받았고 6번째에서 바닥났다.
   - 예약한 채로 45492에 직접 `bind()`하면 성공했다. 체인이 자기 포트를 여는 데는 영향이 없다.
3. 예약은 밖에서만 걸 수 있다. 컨테이너 안에서 `/proc/sys/net/ipv4/ip_local_reserved_ports`에 쓰면 `Read-only file system`이다
   (docker는 `/proc/sys`를 읽기 전용으로 붙인다). `docker run --sysctl …`은 추가 권한 없이 먹힌다. 네트워크 네임스페이스마다 따로인
   sysctl이기 때문이다. 플래그가 없으면 그 파일은 빈 줄이다. 그래서 `check.sh`는 예약을 걸 수는 없지만 걸렸는지 읽을 수는 있다.
4. 플래그를 넣을 자리. carryover에는 "Makefile `IN_CONTAINER`"라고 적었는데 그것만으로는 모자란다. 루트 게이트를 도는 `make gate`는
   `IN_CONTAINER`를 쓰지 않고 자기 `docker run` 줄을 갖고 있다(`Makefile` `gate:`). `IN_CONTAINER`를 쓰는 것은 `make check`(체인
   하나)와 빌드 타깃들이다. 사람이 직접 치는 줄은 lessons "게이트를 돌리고 읽는 법"의 `docker run` 셋(루트 · RUNS · 체인 하나)이다.
   CI(`checks.yml`)의 `docker run` 넷은 게이트를 안 돌린다(sanity · Zig 빌드 · test).

## 결정

### 결정 1. 포트를 옮기지 않고 예약한다

다른 길은 체인 포트를 32768 아래로 옮기는 것이다. 그러면 플래그 없이 어떻게 띄우든 안전하다. 하지만 스크립트 22개에 있는 포트 숫자
122곳과 그것을 인용한 문서 · 기억을 다 바꿔야 하고, 번호를 잘못 옮기면 그 자체가 새 충돌이 된다. 예약은 줄 다섯을 고치면 되고,
"플래그 없이 띄우는 경우"는 결정 3의 검사가 막는다.

### 결정 2. 범위는 45455~45599

지금 체인 몫(45455~45494)만 막으면 새 체인이 45495부터 포트를 쓸 때마다 범위도 같이 늘려야 한다. 그 일을 빠뜨리면 아무도
모른다. 45599까지 잡으면 새 체인 105개 몫이 들어가고 `probe/run.sh`의 45590도 들어간다. 예약에 드는 비용은 없다. ephemeral
28,232개 가운데 145개가 빠질 뿐이다. 45600(`site/capture.sh`)은 호스트에서 도는 것이라 뺐다.

### 결정 3. 루트 `check.sh`가 예약을 읽고, 없으면 빌드 전에 멈춘다

플래그를 넣는 자리가 다섯이고 사람이 직접 `docker run`을 칠 수도 있다. 조용히 빠지면 게이트는 예전처럼 돌고 가끔만 빨개진다.
그래서 `check.sh`가 `clean` 전에 `/proc/sys/net/ipv4/ip_local_reserved_ports`를 읽는다. 그 값이 기대하는 `45455-45599`와 정확히
같지 않으면 `check FAIL`과 넣어야 할 플래그를 찍고 exit 1로 끝낸다. 기대값은 `check.sh`에 상수로 한 번 적는다. Makefile의 값과
따로 적힌 두 곳이지만, 둘이 어긋나면 이 검사가 바로 빨개지므로 어긋난 채로 남지 않는다.

정확히 같은지를 본다(포함 관계가 아니다). 범위를 넓힐 때 두 자리를 함께 고치게 하려는 것이다.

체인 `check.sh`(체인 하나를 단독으로 돌릴 때)에는 검사를 넣지 않는다. 충돌은 lane이 동시에 돌 때 생기고, 체인 하나만 돌면
부딪칠 다른 연결이 거의 없다. 그래도 `make check`는 `IN_CONTAINER`를 통해 플래그를 받는다.

### 결정 4. Makefile은 변수 하나로

`RESERVED_PORTS = --sysctl net.ipv4.ip_local_reserved_ports=45455-45599`를 두고 `IN_CONTAINER`와 `gate:` 줄이 그것을 쓴다.
`shell:` 줄에도 넣는다. 사람이 그 안에서 체인을 돌리기도 하기 때문이다. 빌드 타깃들도 `IN_CONTAINER`로 플래그를 받게 되지만
해는 없다.

## 안 하는 것

1. 체인 포트를 옮기는 것(결정 1).
2. CI의 `docker run`. 게이트를 안 돌린다.
3. 체인별 검사(결정 3).
4. `probe/run.sh` · `site/capture.sh`의 주석이나 줄. probe는 혼자 돌고, site는 호스트에서 돈다.

## 위험

1. 다른 Docker 런타임에서 `--sysctl`이 거부될 수 있다. OrbStack에서는 확인했다. 거부되면 `docker run`이 바로 실패하므로 조용히
   지나가지는 않는다.
2. 결정 3의 검사가 게이트를 이유 없이 막을 수 있다. 커널이 값을 다른 모양(예: `45455-45599` 대신 쉼표가 붙은 목록)으로 돌려주면
   그렇게 된다. 실측에서는 넣은 문자열 그대로(`45455-45499`) 읽혔다. RP-M0에서 바뀐 범위로 한 번 더 본다.

## 게이트

RP-M0의 plan에 적는다. 요지는 다음 셋이다.
(a) 플래그 없이 루트 `check.sh`를 띄우면 빌드 전에 `check FAIL`로 멈춘다(변이).
(b) 범위를 다르게 넣어도 멈춘다(변이).
(c) `make gate`로 루트 게이트 1회가 22/22다.
