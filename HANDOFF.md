# HANDOFF: Firewall(FW)이 M2로 닫혔다 — `firewall=on`이 들어오는 것을 가른다

## 지금 어디인가

FW가 2026-09-27 하루에 M0~M2로 닫혔다(design `Status: 끝났다`). 다음 할 일은 새
서브프로젝트를 고르는 것이다(아래).

design은 `docs/superpowers/specs/2026-09-27-tars-firewall-design.md`(확인 6 · 결정 6 ·
위험 6 · 실측 1~19), plan은 `plans/2026-09-27-tars-firewall-fw-m0.md` ~ `-fw-m2.md`,
기억은 `docs/decisions/project_firewall.md`다.

| 커밋 | 무엇 |
|---|---|
| `82de63e` · `690f841` · `c26f7f3` | design · M0 plan(+ `table inet` → `table ip`) · M0 실측(코드 0줄) |
| `ca0025d` · `c92d681` | M1 — 커널 다섯 · Dockerfile 층 10 · `nft` · `/etc/tars/firewall{,-base}.nft` · `firewall` 키 · `init/src/firewall.zig` · 체인 `firewall/check.sh` |
| `660efcf` · `76c668e` | M2 — 체인이 부팅 둘 · 검사 열일곱(UDP · 파일 둘에 나뉜 포트 · 틀린 파일의 부팅) · 가이드의 방화벽 절 |

루트 게이트 15체인 3/3(46분 26초, `FAIL` 0줄, 2026-09-27). 반사실 다섯 — `policy
accept` · `allow.nft` 없음 · `firewall=off`(M1), UDP 줄 없음 · 갈래 2 막기(M2)가 각각
겨냥한 검사에서 빨갛다.

사용자가 정한 셋 — 중심은 방화벽(UDP와 포트 여럿은 판정의 재료) · 기본 꺼짐이고 켜면
닫힘 · 포트는 `/config/nftables.d/*.nft`에 nftables 문법으로.

⚠ 다음 사람이 먼저 볼 것 넷.
- 표가 `table ip`다. `NF_TABLES_INET`이 `depends on IPV6`라서다. IPv6를 켜면 표를
  `inet`으로 바꾸고 v6 음성 검사를 더해야 한다(design 위험 6).
- `nft -f`는 원자적이다. 틀린 파일 하나에 사람의 파일 전부가 빠지고 기본 규칙만 선다.
  갈래 2를 없애면 기계가 열린 채로 뜬다(실측 16).
- 막힌 TCP를 SLIRP은 안 끊는다. 음성 판정 하나가 읽기 타임아웃(2초)을 꽉 쓴다.
- `/proc/net/tcp` · `udp`의 포트 16진수는 손으로 옮기지 말 것 — `printf '%04X'`(실측 10).

## 바로 다음에 할 것 — 새 서브프로젝트를 고른다

남은 후보 — 패키지 매니저(DI가 비워 둔 p3) · 부팅 때 뜨는 서비스(LB가 `lo`를, FW가
여는 길을 깔았다) · IPv6(design 위험 6이 첫 확인). 가이드의 "무엇을 기대하고 무엇을
기대하지 않는가" 표의 "네트워크 — 실기 NIC 드라이버가 없다" 줄이 WN 이후 낡았다(FW 범위
밖이라 안 고쳤다).


## 어디를 보면 되는가

2026-09-27에 이 파일을 193KB에서 줄였다. 서브프로젝트마다 쌓이던 "그 앞" 절들
(SD부터 LB까지)은 지웠다 — 각 서브프로젝트의 경과는 그 design의 실측 절과
`docs/decisions/`의 기억에 있고, 지운 원문은 `git show 76c668e:HANDOFF.md`로 본다.

| 무엇 | 어디 |
|---|---|
| 협업 규칙 · 끝난 서브프로젝트 표 | `CLAUDE.md` |
| 세션을 넘는 기억(색인) | `MEMORY.md` → `docs/decisions/` |
| 게이트를 돌리고 읽는 법 · 범용 명령 · 다시 조사하지 말 실측 · 안 되는 접근 · 이월 숙제 · 핵심 파일 지도 | `docs/guides/lessons.md` |
| 사람이 TARS를 띄우는 법 | `docs/guides/running-tars.md` |
| 서브프로젝트의 실제 상태 | `check.sh`의 `CHAINS` 배열(열다섯) |

새 세션은 `CLAUDE.md`와 `MEMORY.md`의 feedback 다섯, 그리고 이 파일의 위 절을
읽고 시작한다. 새 서브프로젝트가 닫히면 이 파일은 맨 위 절만 갈아 끼운다 — 옛
머리를 아래로 쌓지 않는다. 서브프로젝트를 넘어 유효한 것이 나오면
`docs/guides/lessons.md`에 더한다.
