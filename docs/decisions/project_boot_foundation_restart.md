---
name: project_boot_foundation_restart
description: "TARS를 이전 저장소(tars.git, V1 M12)를 버리고 이 저장소에서 처음부터 다시 시작한 결정(2026-08-01). 목표는 속도가 아니라 이해. 첫 서브프로젝트 Boot Foundation(BF-M0~M4)의 범위. 당시 PID 1은 Rust였고 ZM이 Zig로 다시 썼다"
metadata:
  type: project
---

TARS(macOS 의미론의 터미널 중심 Linux 유저랜드)를 이전 저장소
`git@github.com:soomtong/tars.git`(V1 M12까지 갔지만 fbdev capture race · ptmx mknod ·
devpts 마운트 같은 이해 없는 수정 RC6~RC21이 쌓였다)를 버리고 이 저장소
`git@github.com:soomtong/tars-linux.git`에서 처음부터 다시 시작했다. 사용자의
판단 — 옛 프로젝트는 "vibe coded and ruined", 어떻게 · 왜 도는지 모르는 코드를
만들었다. 재시작의 목표는 속도가 아니라 이해다(`CLAUDE.md`의 "왜 이런 규칙이
필요한가", [[user_learning_goal]]).

첫 서브프로젝트 Boot Foundation의 범위와 milestone 다섯(BF-M0 toolchain →
BF-M1 init 없는 커널 패닉 → BF-M2 PID 1이 proc/sys/devtmpfs를 붙이고 셸 →
BF-M3 Limine + hybrid ISO → BF-M4 재현성 게이트)은
`docs/specs/2026-08-01-tars-boot-foundation-design.md`에 있고, 최종 비전(macOS
Cmd/Ctrl/Opt 의미론 · ghostty 기반 터미널 · 패키지 매니저 · CJK 입력기)이 왜 각각
뒤의 서브프로젝트로 미뤄졌는지도 그 design의 "배경" 절이다.

당시 값, 지금은 다르다 — PID 1은 Rust로 시작했고 ZM(2026-08-13)이 Zig로 통째로
다시 썼다([[project_zig_rewrite_intent]]). 협업 방식은 당시
[[feedback_commit_delegation]](파일 · 명령은 사용자, commit은 Claude)이었고
2026-09-12부터 [[feedback_execution_scope]](구현 파일 편집과 명령 실행도 Claude)다.

지금 상태는 `HANDOFF.md`, 끝난 서브프로젝트는 `docs/guides/completed.md`.
