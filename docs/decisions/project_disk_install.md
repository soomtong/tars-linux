# 설치된 디스크 — ESP와 설정 파티션, init은 파티션도 본다

DI-M1(2026-09-23)에서 섰다.

설치된 디스크는 ISO와 같은 모양이다. GPT에 p1(ESP, FAT32 `TARS-BOOT`, 부트 파일 넷)과
p2(ext2 `tars-config`, 설정)를 두고 나머지는 비운다. 시스템은 여전히 initramfs에서 돈다.

Why: `init`·`terminal`·게이트 체인 전부가 initramfs 위에 서 있어서, 디스크에는
"initramfs를 어디서 읽어 오는가"만 더했다(DI design 결정 1). 빈 곳은 나중에 p3으로
root 파일시스템이나 패키지 창고가 들어올 자리다.

How to apply:
- `init`의 설정 디스크 후보는 이제 디스크 열넷 다음에 각각의 첫 두 파티션이다
  (`storage.zig`의 `CANDIDATES = DISKS ++ PARTITIONS`, 마흔둘). 디스크 전체가 먼저라
  게이트의 whole-disk ext2 디스크는 판정이 안 바뀐다. 남의 파티션을 잡지 않는 것은
  라벨 접두사 `tars-`가 지킨다 — RM 결정 12의 "파티션은 안 본다"는 이것으로 대체됐다.
- `tars-install`은 `init` 옆의 정적 실행 파일이다(`init/src/install.zig`, 순수 규칙은
  `disk.zig`). 매체는 이름이 아니라 `boot/limine/limine.conf`의 존재로 알아본다.
- 판정은 `install/check.sh`이고, 게이트에서 유일하게 콘솔 셸에 시리얼 FIFO로 친다.
  판정 대상이 terminal 화면이 아니라 `tars-install`의 출력 줄이기 때문이다.
- 설치된 기계에서는 `init`이 p2를 `/config`에 붙여 두므로 그 디스크를 다시
  파티션하면 `sfdisk`가 "in use"로 거부한다. 갱신은 p1만 써야 한다(DI-M2).

관련: `project_seeding_a_config_disk.md` · `project_gate_screen_echo.md` · design `docs/superpowers/specs/2026-09-19-tars-disk-install-design.md`
