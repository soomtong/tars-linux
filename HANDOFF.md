# HANDOFF: Service Control(CT)이 M2로 닫혔다 — `tars-service`와 PID 1의 셋째 입력

## 지금 어디인가

CT가 2026-09-27 하루에 M0~M2로 닫혔다(design `Status: 끝났다`). SV 비목표 4를 목표로
옮긴 것이다. 다음 할 일은 새 서브프로젝트를 고르는 것이다(아래).

design은 `docs/superpowers/specs/2026-09-27-tars-service-control-design.md`(결정 8 · 위험 4 ·
실측 1~13), plan은 `plans/2026-09-27-tars-service-control-ct-m0.md` ~ `-ct-m2.md`, 기억은
`docs/decisions/project_service_control.md`다.

| 커밋 | 무엇 |
|---|---|
| `18ed929` · `321da7a` | design · M0 plan과 실측(코드 0줄) |
| `d2456f0` · `7df2d86` · `b63791d` · `5e3596e` | M1 — `control.zig`와 검사 · `main.zig` · `tars-service` · 닫기 |
| `ce1a4a3` · `601b65d` · `ddb86c7` | M2 — 부팅 D · 가이드 · 진입 검사가 잡은 `grep -q` |

루트 게이트 16체인 3/3(50분 32초, `FAIL` 0줄, 2026-09-27). 반사실 넷(규칙 2 · 규칙 1 · 그룹 · `CLOEXEC`) — 앞의 둘은
호스트 검사가 먼저 잡아서, 호스트 검사를 건너뛴 사본으로 부팅 D가 잡는 것도 봤다.

사용자가 정한 셋 — 서비스 제어를 다음으로 · 동사 넷 · 통로는 소켓.

⚠ 다음 사람이 먼저 볼 것 넷.
- 서비스에 시그널을 보낼 때는 그룹(`kill(-pid)`)이다. 리더에게만 보내면 `exec` 없는
  스크립트의 자식이 고아로 남는다(실측 5).
- 체인에 `… | grep -q`를 쓰면 진입 검사가 게이트를 0.4초에 세운다. `grep … >/dev/null`.
- `zig build test`의 끝줄은 판정이 아니다 — 병렬이라 다른 검사의 `PASS`가 끝에 온다.
- PID 1의 전원 버튼 fd가 자식에게 샌다(`CLOEXEC` 없음, 실측 7). 이월 숙제에 적었다.

## 바로 다음에 할 것 — 새 서브프로젝트를 고른다

남은 후보 — 패키지 매니저(DI가 비워 둔 p3) · IPv6(FW design 위험 6이 첫 확인 — sshd가 떠
있으니 v6 구멍의 값이 크다) · dhcpcd · chronyd를 감독 목록에 넣는 것(SV 비목표 5 — 이제
`tars-service`로 다룰 수 있게 되는 덤이 있다). 작은 것 — 버튼 fd의 `CLOEXEC`.


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
