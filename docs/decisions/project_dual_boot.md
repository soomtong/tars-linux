---
name: project_dual_boot
description: "macOS 옆 설치(DB-M0, 2026-11-05) — tars-install --beside가 가장 큰 빈 공간에 TARS 셋을 덧붙인다, TARS 파티션은 GPT 이름으로, 쓰기 뒤 GPT 재확인 · 커널 노드 위치 대조가 포맷 전 문, init 후보 126. 맥은 Option 키로 고른다"
metadata:
  type: project
---

design은 `docs/specs/2026-11-04-tars-dual-boot-design.md`, plan은 `docs/plans/2026-11-04-tars-dual-boot-db-m0.md`, 사용자 절차는
`docs/guides/running-tars.md`의 macOS 절.

## 무엇이 섰나

- `disk.zig`의 순수 GPT 층: 헤더 · 엔트리 CRC 확인, 타입 GUID(EFI · APFS · HFS+), 이름(UTF-16) 일치, 1MiB 정렬 빈 구간, `--append` 스크립트
  (세 줄 모두 `start=` · `size=` 섹터). `disk_test`는 실제 sfdisk 2.41.5가 쓴 바이트로 본다.
- `install.zig`: 설치 여부 · 갱신 · 새 설치 모두 이름으로 번호를 찾는다(통째 설치는 이름이 p1~p3에 있을 뿐). `--beside`는 GPT가 아니면 ·
  빈 구간이 4GiB보다 작으면 · TARS가 이미 반쯤 있으면 YES 전에 거절한다. 쓴 뒤 GPT를 다시 읽어 계획과 대조하고, 커널의
  `/sys/block/<disk>/<part>/start`가 GPT와 같아야 포맷한다.
- init `storage.PARTITIONS`가 디스크마다 여덟 → 후보 126(Boot Camp가 있는 HFS+ 맥이 p7까지 쓴다).

## 배운 것

1. `sfdisk --wipe always`는 표의 서명만 지우고 sfdisk가 곧 다시 쓴다 — 남의 파티션 바이트는 안 바뀐다(mutation a1이 초록). 그래도 `--wipe never`.
2. 남의 디스크를 쓰는 판정은 "바이트가 같다"를 부팅마다 본다. 실패 줄에 "맥 파티션이 바뀌었는가"를 늘 붙인다(어느 판정에서 멈췄든).
3. 컨테이너에 sfdisk가 없다 — 가짜 맥 GPT는 `dualboot/mac_gpt.pl`(perl)이 쓴다.
4. 실기만 아는 것: Apple 펌웨어가 두 번째 EFI System 파티션을 "EFI Boot"로 보이는지(design 위험 3). 안 보이면 타입을 Basic data로.

관련: [[project_disk_install]] · [[project_kernel_upgrade]] · [[project_home_partition]] · [[project_macbook_hardware]]
