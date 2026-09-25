---
name: project_disk_carryover
description: "DI가 남긴 이월 여섯을 받은 서브프로젝트(DC-M0~M2, 2026-09-25~26 종료). 설치된 부팅(`tars.installed`)은 설정 파티션을 최대 5초 기다린다 — 커널은 PID 1 전에 디스크를 기다려 주지 않고, 게이트에서 그 틈을 덮던 것은 TCG의 느린 initramfs 풀기(1.7초)였다. 판정은 `usb-storage.delay_use=3`으로 틈을 벌린다. M2는 4Kn GPT · 옛 ISO 서명(앞의 구조 먼저) · 넘치는 줄 · YES를 줄로 · PVD 음성 둘. YES의 버그는 '거절하는 쪽'이 아니라 '확인하는 쪽'으로도 틀렸다"
metadata:
  node_type: memory
  type: project
---

# 설치된 부팅의 기다림과 DI의 작은 것들 (DC)

design은 `docs/superpowers/specs/2026-09-25-tars-disk-carryover-design.md`(실측 1~10).

무엇이 섰나.

- `storage.findConfigDiskWaiting(out, list, max_ms)` — 먼저 훑고, 없으면 100ms 자고
  다시 훑기를 상한까지. `mountConfig`는 `tars.installed`일 때만 `CONFIG_WAIT_MS`(5000)를,
  아니면 0을 넘긴다(사용자가 골랐다 — 표지 없는 부팅은 원래 디스크가 없을 수 있다).
- `disk.describe`의 순서가 ext2 → GPT(512 · 4096) → iso9660 → MBR. 앞의 구조를 먼저
  믿는다 — 남의 도구로 다시 만든 스틱에 32KiB의 옛 PVD가 남기 때문이다. 우리 ISO에는
  GPT가 없어서(`--protective-msdos-label`) 진짜 매체는 그대로 `iso9660 TARS`다.
- `disk.clip` — 넘치는 줄은 앞부분 + `...\n`. Zig 0.16의 `bufPrint`가 넘칠 때 buf를
  채워 둔다는 것에 기대고 `disk_test` 11이 그것을 지킨다.
- `install.readLine` — YES를 개행까지 한 바이트씩.

Why: 이월 1번은 HANDOFF가 "실기에서 설정을 못 찾으면 먼저 의심할 자리"라 적어 둔
것이었고, M0이 게이트에서 재현했다(`delay_use=3`에서 `sda2`가 `init`이 훑은 1.72초 뒤).

How to apply:

- 커널이 만드는 장치를 PID 1이 찾는 자리는 전부 한정된 기다림이 필요하다고 본다
  (키보드 HD-M2 · 설치기의 파티션 노드 DI · 설정 디스크 DC). 게이트가 초록이어도
  TCG의 느림이 틈을 덮고 있을 수 있다 — 틈을 일부러 벌리는 수단(`delay_use`)을 찾는다.
- 이월 목록의 "어느 쪽으로 틀리는가" 설명은 검증 전까지 가설이다. YES는 "거절하는
  쪽"이라 적혀 있었는데 반사실 b가 `writing the partition table`까지 갔다.
- 반사실이 초록이면 판정보다 바이너리를 먼저 의심한다([[project_zig_out_staleness]]
  일곱번째가 M1에서 났다).

관련: [[project_disk_install]] · [[project_real_machine]] · [[project_zig_out_staleness]]
