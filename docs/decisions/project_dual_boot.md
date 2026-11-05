---
name: project_dual_boot
description: "macOS 옆 설치(DB-M0 · M1, 2026-11-05) — tars-install --beside가 가장 큰 빈 공간에, tars-install /dev/sda3이 디스크 유틸리티가 만든 FAT · exFAT 파티션 자리에 TARS 셋을 놓는다, TARS 파티션은 GPT 이름으로, 쓰기 뒤 GPT 재확인 · 커널 노드 위치 대조가 포맷 전 문, init 후보 126. 맥은 Option 키로 고른다"
metadata:
  type: project
---

design은 `docs/specs/2026-11-04-tars-dual-boot-design.md`, plan은 `docs/plans/2026-11-04-tars-dual-boot-db-m0.md` · `…-db-m1.md`, 사용자 절차는
`docs/guides/running-tars.md`의 macOS 절.

## 무엇이 섰나

- `disk.zig`의 순수 GPT 층: 헤더 · 엔트리 CRC 확인, 타입 GUID(EFI · APFS · HFS+), 이름(UTF-16) 일치, 1MiB 정렬 빈 구간, `--append` 스크립트
  (세 줄 모두 `start=` · `size=` 섹터). `disk_test`는 실제 sfdisk 2.41.5가 쓴 바이트로 본다.
- `install.zig`: 설치 여부 · 갱신 · 새 설치 모두 이름으로 번호를 찾는다(통째 설치는 이름이 p1~p3에 있을 뿐). `--beside`는 GPT가 아니면 ·
  빈 구간이 4GiB보다 작으면 · TARS가 이미 반쯤 있으면 YES 전에 거절한다. 쓴 뒤 GPT를 다시 읽어 계획과 대조하고, 커널의
  `/sys/block/<disk>/<part>/start`가 GPT와 같아야 포맷한다.
- init `storage.PARTITIONS`가 디스크마다 여덟 → 후보 126(Boot Camp가 있는 HFS+ 맥이 p7까지 쓴다).
- DB-M1(사용자 요청 — 디스크 유틸리티로 나누면 새 자리가 포맷된 파티션이 된다): `tars-install /dev/sda3`이 그 파티션과 앞뒤의 빈 구간에
  셋을 놓는다(`sfdisk --delete` 뒤 `--append`, `--beside --wipe`의 길). 받는 것은 Basic Data의 FAT · exFAT과 빈 파티션뿐, EFI · APFS ·
  HFS+ · Recovery · NTFS는 YES 전에 거절. 목록이 GPT 디스크 밑에 파티션 줄을 단다. 체인 `dualboot`의 GUI 맥(부팅 1 · 5).

## 배운 것

1. `sfdisk --wipe always`는 표의 서명만 지우고 sfdisk가 곧 다시 쓴다 — 남의 파티션 바이트는 안 바뀐다(mutation a1이 초록). 그래도 `--wipe never`.
2. 남의 디스크를 쓰는 판정은 "바이트가 같다"를 부팅마다 본다. 실패 줄에 "맥 파티션이 바뀌었는가"를 늘 붙인다(어느 판정에서 멈췄든).
3. 컨테이너에 sfdisk가 없다 — 가짜 맥 GPT는 `dualboot/mac_gpt.pl`(perl)이 쓴다.
4. Apple 펌웨어는 두 번째 EFI System 파티션(TARS-BOOT)을 Option 화면에 "EFI Boot"로 보인다 — 2026-11-05 MacBook Air 11" 2011 실기에서
   `tars-install /dev/sda3`으로 깔고 그것으로 TARS 터미널까지 떴다(design 위험 3이 풀렸다, 타입은 EFI System 그대로).
5. `diskutil apfs resizeContainer <disk> <size>`는 triple 없이 쓰면 빈 자리를 남긴다(usage 글이 "free space gap"이라 말한다). 포맷되는 것은
   triple을 붙였거나 디스크 유틸리티의 "파티션"이다. `diskutil eraseVolume free free <id>`가 파티션을 빈 자리로 되돌린다(DB-M1 착수 전).
6. 한 부팅에서 설치를 두 번 하는 체인은 끝 줄(`done.`)을 기다리면 안 된다 — 첫 설치가 이미 찍었다. 명령 뒤에 고유 표지를 찍어 기다린다
   (DB-M1 첫 판, 둘째 설치 도중에 QEMU를 꺼 ESP가 비었다).
7. 첫 실기(2026-11-05, APPLE SSD SM256C, HFS+): `EFI · macOS (HFS+) · exFAT 125GB`, p2와 p3 사이 134MB(128MiB) 틈 — 디스크 유틸리티가
   파티션 사이에 128MiB를 둔다는 DB-M1 위험 2가 맞았다. Recovery HD는 없었다(사용자가 준비 중 지웠다). 확인 칸은 대문자 `YES`만 받는다 —
   실기에서 `yes`를 쳤다.

관련: [[project_disk_install]] · [[project_kernel_upgrade]] · [[project_home_partition]] · [[project_macbook_hardware]]
