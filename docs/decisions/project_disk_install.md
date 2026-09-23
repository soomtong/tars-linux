# 설치된 디스크 — ESP와 설정 파티션, 표지가 있을 때만 init이 파티션을 본다

DI-M1에서 섰고 DI-M2에서 갱신과 `--wipe`가 더해졌다(둘 다 2026-09-23).

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
  DI-M2부터는 cmdline에 `tars.installed`가 있을 때만이다 — 설치기가 ESP의 `limine.conf`에
  붙이는 표지다. ISO로 뜬 부팅은 디스크 열넷만 본다.
- `tars-install`은 `init` 옆의 정적 실행 파일이다(`init/src/install.zig`, 순수 규칙은
  `disk.zig`). 매체는 이름이 아니라 `boot/limine/limine.conf`의 존재로 알아본다.
- 판정은 `install/check.sh`이고, 게이트에서 유일하게 콘솔 셸에 시리얼 FIFO로 친다.
  판정 대상이 terminal 화면이 아니라 `tars-install`의 출력 줄이기 때문이다.
- 설치 여부는 셋으로 본다 — GPT · p1이 FAT32이고 붙여 보면 `boot/bzImage`가 있다 ·
  p2가 `tars-` 라벨. 갱신은 p1만 쓰고 p2를 안 연다. `--wipe`는 ISO로 뜬 부팅에서만
  되고, 그 부팅이 p2를 안 붙이는 것이 표지의 이유다(DI-M2 반사실: 붙이면 `sfdisk`가
  "in use"로 거부한다).
- 매체의 `limine.conf`에 표지를 붙일 수 있는지는 YES를 묻기 전에 본다
  (`prepareConf`). 디스크를 지운 뒤에 알면 늦다.

관련: `project_seeding_a_config_disk.md` · `project_gate_screen_echo.md` · design `docs/superpowers/specs/2026-09-19-tars-disk-install-design.md`
