# HANDOFF: Boot Services(SV)가 M2로 닫혔다 — `services.d`와 첫 세입자 sshd

## 지금 어디인가

SV가 2026-09-27 하루에 M0~M2로 닫혔다(design `Status: 끝났다`). 다음 할 일은 새
서브프로젝트를 고르는 것이다(아래).

design은 `docs/superpowers/specs/2026-09-27-tars-boot-services-design.md`(결정 9 · 위험 5 ·
실측 1~19), plan은 `plans/2026-09-27-tars-boot-services-sv-m0.md` ~ `-sv-m2.md`, 기억은
`docs/decisions/project_boot_services.md`다.

| 커밋 | 무엇 |
|---|---|
| `887507a` · `1505d47` · `cbc65b7` | design · M0 plan · M0 실측(코드 0줄) |
| `14a3af8` · `4505f22` · `f1bff34` · `6d0bda0` | M1 — `services.zig` · `Kind.service` · `Child.label` · 체인 `service/check.sh` |
| `45735c7` · `45540f7` | 결정 8 · 9(사용자)와 그 방법의 실측 · M2 plan |
| `806010b` · `fc6a5cf` · `70adb49` · `c89157d` · `a7a6cf2` | M2 — `login.zig` · execve errno · Dockerfile 층 11 · initrd의 sshd · 부팅 B · C · 가이드 |

루트 게이트 16체인 3/3(49분 25초, `FAIL` 0줄, 2026-09-27). 반사실 여덟 — M1 셋(정렬 ·
사전 확인 · 세션/stdin), M2 다섯(login.apply · 키 다시 굽기 둘 · B의 ssh.nft · terminfo).

사용자가 정한 다섯 — 범용 메커니즘과 sshd를 함께 · 서비스 하나는 실행 스크립트 하나 ·
우리 감독자를 넓힌다 · terminfo 몇 개를 게스트에 · ssh 세션은 `tars.conf`의 셸을 따른다.

⚠ 다음 사람이 먼저 볼 것 넷.
- 게스트의 `/bin`에는 `sh`만 있다. 서비스 스크립트는 `#!/bin/sh`(M1 실측 9).
- 서비스의 stdin은 `/dev/null`이다. 대화형 질문은 EOF로 "아니오"가 된다 — `ssh-keygen`이
  있는 키를 안 덮는 것이 그 덕이다(M2 실측 18).
- ssh 세션의 env는 `init`이 쓰는 `SetEnv`에서만 온다. env 블록에 항목을 더하면
  `main.zig`의 `ssh_env`(크기 `3 + 4`)도 본다.
- lastlog 소음 두 줄(`/var/log/lastlog` 없음)이 sshd 세션마다 콘솔에 찍힌다. 해는 없고
  그대로 뒀다(M0 실측 5).

## 바로 다음에 할 것 — 새 서브프로젝트를 고른다

남은 후보 — 패키지 매니저(DI가 비워 둔 p3) · IPv6(FW design 위험 6이 첫 확인). SV가
남긴 작은 것 — 서비스를 멈추고 다시 띄우는 명령(SV 비목표 4) · dhcpcd · chronyd를 감독
목록에 넣는 것(비목표 5).


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
