# HANDOFF: Daemon Supervision(DS) — M1까지 끝났다, 다음은 M2

## 지금 어디인가

DS는 dhcpcd와 chronyd를 PID 1의 감독 목록에 넣는 서브프로젝트다(SV 비목표 5를 목표로
옮겼다). 2026-09-27에 M0(실측)과 M1(코드)이 끝났다. design은
`docs/superpowers/specs/2026-09-27-tars-daemon-supervision-design.md`(결정 7 · 위험 5 ·
실측 1~10)이고, plan은 `plans/2026-09-27-tars-daemon-supervision-ds-m0.md` · `-ds-m1.md`다.

| 커밋 | 무엇 |
|---|---|
| `66d4515` · `9f122bd` | design · M0 실측(코드 0줄) |
| `5ecad6c` · `ffa1d2e` · `3f56ff9` · `738d3b2` | M1 — 예약 이름 · 버튼 fd `CLOEXEC` · 본체 · 닫기 |

사용자가 정한 둘 — 이 서브프로젝트를 다음으로 · chronyd의 기다림은 chrony `sourcedir`로
없앤다(design 결정 3).

지금 선 것. dhcpcd는 `-B`로 배경으로 안 가서 PID 1이 쥔 pid가 곧 dhcpcd다. chronyd
설정은 `init`이 부팅 때 곧바로 쓰고, `ntp=dhcp`면 hook이
`/run/tars/chrony.sources/dhcp.sources`를 쓰고 `chronyc reload sources`를 부른다. 두
데몬은 `Kind.service`로 `children`의 2 · 3번 칸이고 label은 `service dhcpcd` ·
`service chronyd`다. 이웃 체인 넷(net · nic · firewall · service)이 초록이다. 루트
게이트는 아직 안 돌렸다.

⚠ 다음 사람이 먼저 볼 것 셋.
- 로그 줄이 바뀌었다. `started dhcpcd (pid N), it picks the interface`는 없고
  `started service dhcpcd (pid N, /usr/bin/dhcpcd)`다.
- 그룹 SIGTERM은 돌고 있던 dhcpcd hook도 죽인다(design 위험 5, M0 실측 4).
- 게이트의 SLIRP는 option 42를 안 주므로 hook의 `chronyc reload` 경로는 게스트 안에서
  한 번도 안 돈다. M0 실측 5가 손으로 잰 것이 그 경로의 유일한 증거다.

## 바로 다음에 할 것 — DS-M2 plan

design의 "M1이 M2에 넘기는 것"이 목록이다 — 죽이면 다시 뜬다 · `tars-service restart
chronyd` 뒤 시계 · `ntp=dhcp`에서 재시작 없음을 판정으로 · 버튼 fd가 안 샌다 · 반사실
둘(`-B` · `CLOEXEC`) · 가이드(`docs/guides/`) · 루트 게이트 · design `Status:` ·
`CLAUDE.md` 완료 표 · `docs/decisions/`의 기억 한 파일.

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
| 서브프로젝트의 실제 상태 | `check.sh`의 `CHAINS` 배열(열여섯) |

새 세션은 `CLAUDE.md`와 `MEMORY.md`의 feedback 다섯, 그리고 이 파일의 위 절을
읽고 시작한다. 새 서브프로젝트가 닫히면 이 파일은 맨 위 절만 갈아 끼운다 — 옛
머리를 아래로 쌓지 않는다. 서브프로젝트를 넘어 유효한 것이 나오면
`docs/guides/lessons.md`에 더한다.
