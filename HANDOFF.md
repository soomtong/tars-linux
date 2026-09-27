# HANDOFF: Daemon Supervision(DS)이 M2로 닫혔다 — dhcpcd와 chronyd가 감독 목록 안이다

## 지금 어디인가

DS가 2026-09-27 하루에 M0~M2로 닫혔다(design `Status: 끝났다`). SV 비목표 5를 목표로
옮긴 것이다. 다음 할 일은 새 서브프로젝트를 고르는 것이다(아래).

design은 `docs/superpowers/specs/2026-09-27-tars-daemon-supervision-design.md`(결정 7 ·
위험 5 · 실측 1~13), plan은 `plans/2026-09-27-tars-daemon-supervision-ds-m0.md` ~
`-ds-m2.md`, 기억은 `docs/decisions/project_daemon_supervision.md`다.

| 커밋 | 무엇 |
|---|---|
| `66d4515` · `9f122bd` | design · M0 실측(코드 0줄) |
| `5ecad6c` · `ffa1d2e` · `3f56ff9` · `738d3b2` | M1 — 예약 이름 · 버튼 fd `CLOEXEC` · 본체 · 닫기 |
| `924a036` · `e64d60e` | M2 — 체인 판정 다섯 · 닫기(가이드 · 기억 · 표) |

루트 게이트 16체인 3/3(52분 42초, `FAIL` 0줄, 2026-09-27). 반사실 둘(`-B` · `CLOEXEC`)이
예측한 검사(net 29 · service 26)에서 잡혔다.

사용자가 정한 둘 — 이 서브프로젝트를 다음으로 · chronyd의 기다림은 chrony `sourcedir`로
없앤다.

⚠ 다음 사람이 먼저 볼 것 넷.
- 로그 줄 `started dhcpcd (pid N), it picks the interface`는 없다. 감독자의
  `started service dhcpcd (pid N, /usr/bin/dhcpcd)`다.
- `-B`를 빼도 "주소가 붙었다"를 보는 검사는 전부 초록이다 — 갈라진 손자가 일을 한다.
  판정은 쥔 pid로 한다(lessons 61).
- 게이트의 SLIRP는 option 42를 안 주므로 hook의 `chronyc reload` 경로는 게이트 안에서 안
  돈다. 증거는 DS-M0 실측 5 하나다.
- 그룹 SIGTERM은 돌고 있던 dhcpcd hook도 죽인다(design 위험 5).

## 바로 다음에 할 것 — 새 서브프로젝트를 고른다

남은 후보 — 패키지 매니저(DI가 비워 둔 p3) · IPv6(커널에 아직 없다. 켜는 사이클이 방화벽
표를 `inet`으로 바꿔야 한다 — FW design 위험 6. sshd가 떠 있으니 그 조건이 무겁다).
이월 숙제의 작은 것은 `docs/guides/lessons.md`의 "이월 숙제"에 있다.

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
