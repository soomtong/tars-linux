---
name: project_disk_install
description: "설치된 디스크는 ESP(p1)와 설정 파티션(p2)이고 표지(`tars.installed`)가 있을 때만 init이 파티션을 본다(DI-M1 · M2, 2026-09-23). 설치된 부팅은 설정 파티션을 최대 5초 기다린다 — 게이트에서 그 틈을 덮던 것은 TCG의 느린 initramfs 풀기였다(DC-M0~M2, 2026-09-26). disk.describe는 앞의 구조(ext2 → GPT → iso9660 → MBR)를 먼저 믿는다"
metadata:
  type: project
---

# 설치된 디스크 — ESP와 설정 파티션, 표지가 있을 때만 init이 파티션을 본다

DI-M1에서 섰고 DI-M2에서 갱신과 `--wipe`가 더해졌다(둘 다 2026-09-23, design
`docs/specs/2026-09-19-tars-disk-install-design.md`). DI가 남긴 이월 여섯은 DC-M0~M2(2026-09-25~26, design
`docs/specs/2026-09-25-tars-disk-carryover-design.md`, 실측 1~10)가 받았다.

설치된 디스크는 ISO와 같은 모양이다. GPT에 p1(ESP, FAT32 `TARS-BOOT`, 부트 파일 넷)과 p2(ext2 `tars-config`,
설정)를 두고 나머지는 비운다. 시스템은 여전히 initramfs에서 돈다.

Why: `init` · `terminal` · 게이트 체인 전부가 initramfs 위에 서 있어서, 디스크에는 "initramfs를 어디서 읽어
오는가"만 더했다(DI design 결정 1). 빈 곳은 나중에 p3으로 root 파일시스템이나 패키지 창고가 들어올 자리다.

## How to apply (DI)

- `init`의 설정 디스크 후보는 디스크 열넷 다음에 각각의 첫 두 파티션이다(`storage.zig`의 `CANDIDATES = DISKS ++
  PARTITIONS`). 디스크 전체가 먼저라 게이트의 whole-disk ext2 디스크는 판정이 안 바뀐다. 남의 파티션을 잡지 않는
  것은 라벨 접두사 `tars-`가 지킨다 — RM 결정 12의 "파티션은 안 본다"는 이것으로 대체됐다. DI-M2부터는 cmdline에
  `tars.installed`가 있을 때만이다 — 설치기가 ESP의 `limine.conf`에 붙이는 표지다. ISO로 뜬 부팅은 디스크 열넷만
  본다(measurements 55).
- `tars-install`은 `init` 옆의 정적 실행 파일이다(`init/src/install.zig`, 순수 규칙은 `disk.zig` — HC-M2가 더
  내렸다, [[project_host_checks]]). 매체는 이름이 아니라 `boot/limine.conf`의 존재로 알아본다.
- 판정은 `install/check.sh`이고, 게이트에서 유일하게 콘솔 셸에 시리얼 FIFO로 친다(measurements 21). 판정 대상이
  terminal 화면이 아니라 `tars-install`의 출력 줄이기 때문이다.
- 설치 여부는 셋으로 본다 — GPT · p1이 FAT32이고 붙여 보면 `boot/bzImage`가 있다 · p2가 `tars-` 라벨. 갱신은
  p1만 쓰고 p2를 안 연다. `--wipe`는 ISO로 뜬 부팅에서만 되고, 그 부팅이 p2를 안 붙이는 것이 표지의 이유다(DI-M2
  mutation: 붙이면 `sfdisk`가 "in use"로 거부한다).
- 매체의 `limine.conf`에 표지를 붙일 수 있는지는 YES를 묻기 전에 본다(`prepareConf`). 디스크를 지운 뒤에 알면 늦다.

## 설치된 부팅의 기다림과 DI의 작은 것들 (DC)

무엇이 섰나.

- `storage.findConfigDiskWaiting(out, list, max_ms)` — 먼저 훑고, 없으면 100ms 자고 다시 훑기를 상한까지.
  `mountConfig`는 `tars.installed`일 때만 `CONFIG_WAIT_MS`(5000)를, 아니면 0을 넘긴다(사용자가 골랐다 — 표지 없는
  부팅은 원래 디스크가 없을 수 있다).
- `disk.describe`의 순서가 ext2 → GPT(512 · 4096) → iso9660 → MBR. 앞의 구조를 먼저 믿는다 — 남의 도구로 다시 만든
  스틱에 32KiB의 옛 PVD가 남기 때문이다. 우리 ISO에는 GPT가 없어서(`--protective-msdos-label`) 진짜 매체는 그대로
  `iso9660 TARS`다.
- `disk.clip` — 넘치는 줄은 앞부분 + `...\n`. `bufPrint`가 넘칠 때 buf를 채워 둔다는 것에 기대고 `disk_test` 11이
  그것을 지킨다(`docs/guides/dead-ends.md`의 `bufPrint` 항목은 "얼마나 썼는지"가 필요한 자리의 말이다 — 여기는 그
  값이 필요 없다).
- `install.readLine` — YES를 개행까지 한 바이트씩.

Why: 이월 1번은 HANDOFF가 "실기에서 설정을 못 찾으면 먼저 의심할 자리"라 적어 둔 것이었고, M0이 게이트에서
재현했다(`usb-storage.delay_use=3`에서 `sda2`가 `init`이 훑은 1.72초 뒤). 커널은 PID 1 전에 디스크를 기다려 주지
않고, 게이트에서 그 틈을 덮던 것은 TCG의 느린 initramfs 풀기였다.

How to apply:

- 커널이 만드는 장치를 PID 1이 찾는 자리는 전부 한정된 기다림이 필요하다고 본다(키보드 HD-M2 · 설치기의 파티션
  노드 DI · 설정 디스크 DC). 게이트가 초록이어도 TCG의 느림이 틈을 덮고 있을 수 있다 — 틈을 일부러 벌리는
  수단(`delay_use`)을 찾는다. 커널 코드 배치가 그 틈을 움직이는 것은 measurements 76, 간헐의 현재 상태는
  `docs/guides/carryover.md`의 PD 항목.
- 이월 목록의 "어느 쪽으로 틀리는가" 설명은 검증 전까지 가설이다. YES는 "거절하는 쪽"이라 적혀 있었는데
  mutation b가 `writing the partition table`까지 갔다.
- mutation이 초록이면 판정보다 바이너리를 먼저 의심한다([[project_zig_out_staleness]] 일곱번째가 M1에서 났다).

관련: [[project_real_machine]] · [[project_seeding_a_config_disk]] · [[project_gate_screen_echo]] ·
[[project_zig_out_staleness]]
