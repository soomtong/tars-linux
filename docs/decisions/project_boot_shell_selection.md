---
name: project_boot_shell_selection
description: 2026-08-11 사용자 요청 기록 — 부팅 셸을 고른다. 구현 완료(fish · bash · zsh를 tars.conf의 `shell=`로 고른다, 재부팅 반영). nushell은 미구현.
metadata: 
  node_type: memory
  type: project
  originSessionId: 0b4b9b0c-8171-4506-bd85-91c52dd6c603
  modified: 2026-08-11T01:09:00.798Z
---

상태: 구현 완료. `init/src/config.zig`의 `Shell` enum이 fish · bash · zsh를 받고
`shell=` 키로 고른다(기본값 fish). 셸 설정 파일은 SC(`shell_config`)가, `shell=bash`
부팅은 BB가 맡았다. 미구현: nushell, 마지막 선택을 자동으로 기억하는 것.

아래는 요청 당시의 기록이다.

2026-08-11 사용자 요청(“지금은 아니고 나중에”). TARS가 부팅할 때 사용할
셸을 bash / zsh / fish / nushell 중에서 고를 수 있게 하고, 마지막에
사용한 셸을 다음 부팅의 기본값으로 쓴다. 실시간 전환은 필요 없고
재부팅해야 반영되는 수준으로 충분하다고 명시했다.

선행 조건(설계 시 반드시 먼저 짚을 것): 현재 루트 파일시스템은
`kernel/initrd.cpio` = initramfs(tmpfs)라서 재부팅을 넘어 살아남는
저장소가 없다. `/etc/...`에 선택을 저장해도 전원이 꺼지면 사라진다.
따라서 이 기능은 단독 기능이 아니라 “설정 영속화”(virtio-blk 디스크 이미지
+ 파일시스템 + `init`이 읽는 경로) 서브프로젝트의 첫 사용 사례로 묶어
brainstorming하는 것이 맞다. 폰트 크기·색상·키바인딩 등 이후 설정도 전부
같은 저장소를 쓰게 된다.

구현 측 준비 상태: TF-M3에서 `terminal/src/pty.zig`의 `spawn(path,
argv, cols, rows)`가 임의 프로그램을 받도록 일반화됐다 — 셸 경로/argv를
바꿔 끼우는 것 자체는 이미 가능하다. 남은 건 “무엇을 고를지 어디서 읽어
오는가”뿐이다. 각 셸 바이너리를 `kernel/make_initrd.sh`가 initrd에 복사해야
한다는 점도 잊지 말 것(현재는 `fish`만 복사한다).

관련: [[project_zig_rewrite_intent]], [[user_learning_goal]]
