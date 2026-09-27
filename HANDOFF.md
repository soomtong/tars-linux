# HANDOFF: Boot Services(SV)가 M1까지 왔다 — `init`이 `/config/services.d`를 감독한다

## 지금 어디인가

SV가 2026-09-27에 시작해 M0 · M1이 닫혔다. 다음은 M2(sshd)이고, 그 plan을 쓰기 전에
사용자와 정할 것이 둘 있다(아래).

design은 `docs/superpowers/specs/2026-09-27-tars-boot-services-design.md`(확인 6 · 결정 7 ·
위험 5 · 실측 1~12), plan은 `plans/2026-09-27-tars-boot-services-sv-m0.md` · `-sv-m1.md`다.
기억(`docs/decisions/project_boot_services.md`)은 SV가 닫힐 때 쓴다.

| 커밋 | 무엇 |
|---|---|
| `b541515` | 가이드의 낡은 네트워크 줄 둘(WN · TD 이후) |
| `887507a` · `1505d47` · `cbc65b7` | design · M0 plan · M0 실측(코드 0줄) — sshd 비용 5.46MB, `/config`에서 직접 실행, sshd가 요구하는 셋 |
| `14a3af8` · `4505f22` · `f1bff34` · `6d0bda0` | M1 — `init/src/services.zig` · `main.zig`의 `Kind.service` · `Child.label` · 체인 `service/check.sh`(열여섯번째, 검사 여덟) |

M1은 체인 · 반사실 셋 · 이웃 다섯(boot · device · machine · config · firewall)까지
초록이다. 루트 게이트(16체인)는 아직 안 돌았다 — M2가 끝날 때 돈다.

사용자가 정한 셋 — 범용 메커니즘과 sshd를 함께 · 서비스 하나는 실행 스크립트 하나 ·
감독은 우리 감독자를 넓혀서(runit 아님).

⚠ 다음 사람이 먼저 볼 것 셋.
- 게스트의 `/bin`에는 `sh`만 있다. 서비스 스크립트의 shebang이 `#!/bin/bash`면 execve가
  `ENOENT`로 127이고, 로그에 errno가 없다(실측 9).
- ext2의 `getdents64`는 만든 순서를 돌려준다. 시작 순서는 `init`의 정렬이 정한다(실측 11).
- Debian openssh는 root 그룹 쓰기를 StrictModes에서 봐준다(실측 5, 원인은 패치 이름으로
  추정).

## 바로 다음에 할 것 — M2 전에 사용자와 둘을 정한다

1. terminfo(실측 7). ssh 클라이언트의 `TERM`이 `xterm-256color`가 아니면(예: Ghostty의
   `xterm-ghostty`) `less`가 경고를 찍고 RETURN을 기다린다. 게스트에 terminfo를 더
   넣을지, 가이드로 풀지.
2. ssh 세션의 셸 · env(실측 6). 지금은 `passwd`의 `/bin/sh`(bash)와 sshd의 기본 `PATH`이고
   `init`의 env(`TZ` · 히스토리)가 없다. `tars.conf`의 `shell`을 따르게 할지.

정한 뒤 M2 plan — sshd 넷과 라이브러리 일곱을 initrd에, `sshd_config` · 템플릿
`/etc/tars/services/sshd` · `passwd`/`group` 두 줄 · `/run/sshd`, devcontainer에
`openssh-client`, 체인에 부팅 B(로그인) · C(호스트 키 영속), `firewall=on` 조합, 가이드 절,
execve 실패 줄의 errno. 끝에 루트 게이트.


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
