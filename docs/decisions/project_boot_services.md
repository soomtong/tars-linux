---
name: project_boot_services
description: "사람이 /config/services.d에 둔 실행 파일을 init이 부팅 때 한 번 읽어 terminal · 콘솔 셸과 같은 규칙으로 감독하는 서브프로젝트(SV-M0~M2, 2026-09-27 종료). 첫 세입자 sshd는 initrd의 템플릿을 링크로 켜고, 호스트 키는 /config/ssh에 남는다. ssh 세션은 init이 부팅 때 쓰는 passwd의 셸 자리와 sshd SetEnv로 콘솔과 같은 셸 · env다. 열여섯번째 체인 service/check.sh"
metadata:
  node_type: memory
  type: project
---

# Boot Services (SV)

design은 `docs/specs/2026-09-27-tars-boot-services-design.md`(결정 9 · 실측 1~18).
사용자가 후보 셋(패키지 매니저 · 부팅 서비스 · IPv6) 중 이것을 골랐고, 다섯을 정했다 —
범용 메커니즘과 sshd를 함께 · 서비스 하나는 실행 스크립트 하나 · 감독은 우리 감독자를
넓혀서(runit 아님) · 터미널 이름은 흔한 것 몇 개를 게스트에 · ssh 세션은 `tars.conf`의
셸을 따른다.

무엇이 섰나.

- `init/src/services.zig` — `getdents64`로 읽고 이름순 정렬, `statx`(링크를 따라간다)로
  "일반 파일 + 실행 비트", 여덟까지. `main.zig`의 `children`이 `2 + services.MAX`
  크기이고 `Child.label`이 로그 이름이다(terminal · 콘솔 셸은 SV 전 글자 그대로).
  서비스 자식은 `setsid`와 stdin `/dev/null`.
- `init/src/login.zig` — 부팅 때 `/etc/passwd`의 root 셸 자리와
  `/etc/ssh/sshd_config.d/tars-env.conf`의 `SetEnv` 한 줄(env 블록의 우리 몫 전부).
- initrd — sshd · `sshd-session` · `sshd-auth` · `ssh-keygen`과 라이브러리 일곱(2.1MB, 74%가
  sqlite), `sshd_config`, 템플릿 `/etc/tars/services/sshd`, `passwd` · `group`의 privsep 줄,
  `/run/sshd`, terminfo 일곱(`xterm-ghostty` · `xterm-kitty`는 `tic`으로 이름을 더해 굽는다).
- 체인 `service/check.sh` — 부팅 A(메커니즘, 검사 여덟) · B(방화벽이 22를 막고 첫 키를
  굽는다) · C(키가 그대로 · 키 로그인 · 세션이 콘솔과 같다 · `xterm-ghostty`의 less).

Why: LB와 FW가 받는 길을 깔았는데 받을 쪽을 사람이 정하는 길이 없었다. `init`이
띄우는 것이 전부 코드에 박혀 있었다.

How to apply:

- 게스트에 심는 스크립트는 `#!/bin/sh`다. `/bin`에는 `sh`뿐이라 `#!/bin/bash`는
  `ENOENT`(execve 줄의 `errno 2`)다.
- 서비스의 stdin이 `/dev/null`이라 대화형 질문은 EOF로 "아니오"가 된다.
  `ssh-keygen`이 있는 키를 덮지 않는 것이 그 결과다(실측 18).
- sshd는 `init`의 env를 세션에 안 넘긴다. 세션의 env는 `SetEnv`에서만 온다 —
  env 블록에 새 항목을 더하는 사람은 `main.zig`의 `ssh_env`(크기 `3 + 4`)도 본다.
- Debian openssh는 root 그룹 쓰기를 StrictModes에서 봐준다(실측 5, 원인은 패치 이름으로
  추정했고 소스는 안 읽었다).
- 체인이 서비스를 심을 때는 역순으로 쓴다 — ext2는 만든 순서를 돌려준다.

관련: [[project_init_supervisor]] · [[project_firewall]] · [[project_loopback]] ·
[[project_measuring_tool_cost]] · [[project_seeding_a_config_disk]] ·
[[feedback_boot_never_blocks]] · [[project_write_or_reuse]]
