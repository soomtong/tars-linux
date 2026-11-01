---
name: project_boot_shell_selection
description: 2026-08-11 사용자 요청 — 부팅 셸을 고른다. 구현 완료(fish · bash · zsh를 tars.conf의 `shell=`로 고른다, 재부팅 반영). nushell과 "마지막 선택 자동 기억"은 미구현
metadata:
  type: project
---

상태: 구현 완료. `init/src/config.zig`의 `Shell` enum이 fish · bash · zsh를 받고 `shell=` 키로 고른다(기본값
fish). 저장소와 파서는 [[project_config_persistence]], 셸 설정 파일은 SC(`shell_config`,
[[project_shell_config]]), `shell=bash` 부팅은 BB([[project_bash_boot]])가 맡았다.

2026-08-11 사용자 요청("지금은 아니고 나중에")의 원문 범위는 bash / zsh / fish / nushell 가운데 고르고 마지막에
쓴 셸을 다음 부팅의 기본값으로 쓰는 것, 실시간 전환 없이 재부팅 반영이면 충분하다는 것이었다. 미구현으로
남은 둘 — nushell, 마지막 선택을 자동으로 기억하는 것 — 은 사용자가 다시 꺼낼 때 본다. 이 요청이 "설정
영속화"(CP) 서브프로젝트의 첫 사용 사례가 된 경위는 `docs/specs/2026-08-14-tars-config-persistence-design.md`.

관련: [[project_config_persistence]] · [[user_learning_goal]]
