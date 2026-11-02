# HP-M0 — 셋째 파티션 `tars-home`을 ext4로 만들고 `/home`에 붙인다

> 구현 파일은 Claude(또는 서브에이전트)가 넣고, lead가 diff를 실제 파일과 대조한 뒤 게이트 · commit한다. 줄 번호는 2026-11-02
> `f782974` 기준이라 낡을 수 있다 — 고치기 전에 `rg`로 다시 찾는다. 셸은 여전히 root다(계정은 M1).

Goal: design 결정 1 · 2 · 3 · 4 · 10 · 11을 넣는다. 끝나면 `tars-install`이 p1 768MiB · p2 256MiB · p3 나머지(ext4
`tars-home`)를 만들고 4GiB 미만 디스크를 YES 전에 거절하며, 설치된 디스크로 뜬 init이 `/config`(ext2 · sync) 옆에 `/home`(ext4 ·
async)을 붙인다. 남의 ext4는 라벨로 거른다. 커널에 ext4가 들어가고 그 값(bzImage · 부팅 시간)이 실측으로 남는다. 체인
스물다섯째 `home/check.sh`가 design 판정 1 · 2 · 3 · 5 · 6 · 7을 본다.

Architecture: 순수한 층(`disk.zig`의 배치 상수와 계획 문구, `storage.zig`의 라벨 판정과 후보 목록)에 단위 검사를 먼저 붙이고,
그 다음 시스템 콜 층(`install.zig`의 포맷, `main.zig`의 마운트)을 고친다. 설치기는 ESP · 설정 파티션을 만들던 길에 셋째를
한 줄씩 더할 뿐이고, init은 `mountConfig`의 모양을 그대로 복사해 `mountHome`을 둔다 — 후보 목록 · 기다림 · 로그 줄의 규칙이
같아야 "설치했는데 못 찾는다"의 원인이 두 갈래로 안 늘어난다. 게이트는 `install/check.sh`의 모양(시리얼 FIFO · `tars-install
--yes` · NVMe로 다시 부팅)을 따른다.

## 무엇을 재나 (design "실측 (M0)"에 적는다)

| 측정 | 무엇 | design의 자리 |
|---|---|---|
| 1 | `CONFIG_EXT4_FS=y`가 끈 심볼(`olddefconfig` 뒤 `.config`의 diff)과 bzImage 바이트 차이, BF 체인의 부팅 시간 차이 | 결정 4 |
| 2 | 설치 뒤 768MiB ESP의 빈 자리(바이트, `mdir`), 한 벌의 크기 | 위험 1 |
| 3 | `mke2fs -t ext4`가 p3(약 4GiB)를 굽는 시간(TCG), `mke2fs.conf` 없이 켜진 feature 목록(`dumpe2fs -h`의 `Filesystem features`) | 위험 6 |
| 4 | 설치된 부팅의 `/proc/mounts` `/home` 줄과 `/proc/fs/ext4/<dev>/options`의 `errors=` · `data=` | 결정 1 |
| 5 | `/home` 탐색이 더한 후보 수(56)와 init 로그 줄의 모양. ISO 부팅(디스크 없음)에서 `tars-home` 줄이 부팅을 몇 ms 늦추는가(DC 결정 1대로 기다림은 0이어야 한다) | 결정 3 |

## Task 0: 기준값

고치기 전에 셋을 적어 둔다 — 측정 1 · 2 · 3의 "전"이다.

```
ls -l kernel/build/arch/x86/boot/bzImage            # 바이트
rg -n 'EXT4|JBD2|MBCACHE|CRC16' kernel/build/.config # 지금은 EXT4가 not set
./install/check.sh 2>&1 | tee /tmp/install-before.log   # 판정 수와 시간, mke2fs 줄의 간격
```

컨테이너 안이다(`make shell` 또는 `docs/guides/lessons.md` "게이트 운영"의 명령). `install/check.sh`는 부팅 일곱이라 5분쯤이다.

## Task 1: 커널 — ext4를 켠다

`kernel/.config:4074`의 `# CONFIG_EXT4_FS is not set`을 `CONFIG_EXT4_FS=y`로. `CONFIG_EXT2_FS=y`는 그대로(design 결정 4).
`CONFIG_EXT4_USE_FOR_EXT2`는 EXT2_FS가 켜져 있으면 메뉴에 안 나오므로 손댈 것이 없다. `olddefconfig`가 `JBD2` · `FS_MBCACHE` ·
`CRC16`을 스스로 켠다 — 빌드 뒤 `kernel/build/.config`와 `kernel/.config`의 diff를 측정 1에 적는다. `EXT4_FS_POSIX_ACL` ·
`EXT4_FS_SECURITY`는 안 켠다(기본값 n, 쓰는 데가 없다).

```
(cd kernel && ./build.sh)      # .config가 바뀌었으니 통째로 다시 만든다. KU-M1 때의 시간을 본다
ls -l kernel/build/arch/x86/boot/bzImage
```

여기서 한 번 `./boot/check.sh`를 돌려 부팅 시간을 적는다(측정 1의 "후"). 빌드 산출물은 `.gitignore`가 거른다 — 커밋되는 것은
`kernel/.config` 한 줄이다.

## Task 2: 순수한 층 — `disk.zig` · `storage.zig`와 단위 검사

### `disk.zig`

- `SFDISK_SCRIPT`(238~243): 세 줄로. 셋째는 size 없이 `type=linux, name=TARS-HOME` — sfdisk는 size가 없으면 나머지 전부다.

  ```
  label: gpt
  size=768MiB, type=uefi, name=TARS-BOOT
  size=256MiB, type=linux, name=TARS-CONFIG
  type=linux, name=TARS-HOME
  ```

- `MIN_DISK_BYTES`(248): `(4 << 30) + (2 << 20)`. 주석의 "KU-M0 plan 확정 값"을 "HP design 결정 2(사용자, 4GiB 보장)"로.
  `MIN_DISK_WORDS`(252): `"more than 4 GiB"`.
- `HOME_LABEL`: `ESP_LABEL` · `CONFIG_LABEL`(258~259) 옆에 `pub const HOME_LABEL: [:0]const u8 = "tars-home";`.
- 계획 문구(486~489): 세 줄과 갱신 줄 하나.

  ```
    p1  768 MiB  EFI System  FAT32  TARS-BOOT   <- bzImage, initrd.cpio, limine
    p2  256 MiB  Linux       ext2   tars-config <- your settings, empty at first
    p3     rest  Linux       ext4   tars-home   <- your home, empty at first
  ```

  `rest unallocated` 줄은 지운다(이제 남는 자리가 없다). `p2_settings` 줄은 그대로. 갱신 쪽(481)의 `p2 (tars-config) <- not opened`
  아래에 `p3 (tars-home) <- not opened`를 더하고, `--wipe erases both` 문구(482)는 `erases all three, your home too`로(design 결정 10).
- `disk_test.zig:438 · 454~455`의 기대 문자열을 위 모양으로. 500의 `MIN_DISK_BYTES` 경계 검사는 상수를 따라가므로 그대로 돈다.
  `408`의 "2097152 sectors are not 1 GiB" 검사는 formatSize의 것이라 그대로다.

### `storage.zig`

- `PARTITIONS`(79~88): 디스크마다 셋째를 더한다(`/dev/vda3` · `/dev/nvme0n1p3` · `/dev/sda3` · `/dev/mmcblk0p3` …). 주석 "첫 두
  파티션"을 "첫 세 파티션 — p3가 `/home`이다(HP design 결정 2)"로. `CANDIDATES`는 14 + 42 = 56이 된다. `main.zig:138`의 주석
  "마흔둘"도 "쉰여섯"으로.
- `homeLabel(head)`: `ext2Label`의 라벨이 `HOME_LABEL`과 전체 일치할 때만 돌려준다. `tarsLabel`(189~193)은 라벨이 `HOME_LABEL`과
  같으면 null — 설정 탐색이 `tars-home`을 잡지 않게(design 위험 5). `disk.zig`를 import하지 말고 `storage.zig`에 `HOME_LABEL`을 두고
  `disk.zig`가 그것을 가리킨다(`disk.zig`가 이미 `storage`를 쓴다).
- `findConfigDisk`(234) · `findConfigDiskWaiting`(282)을 matcher 인자로 일반화한다: `pub fn findDisk(out, list, match: *const fn ([]const u8) ?[]const u8) bool`과
  `findDiskWaiting(out, list, max_ms, match)`. 옛 이름 둘은 `tarsLabel`을 넣어 부르는 한 줄짜리로 남긴다 — `install.zig`와
  `main.zig`의 호출이 안 바뀐다.
- `storage_test.zig:229~250`: `disks * 3` → `disks * 4`, `disks + i * 2 + (n - 1)` → `disks + i * 3 + (n - 1)`, n은 1~3. 라벨 검사에
  넷을 더한다 — `tars-home`은 `tarsLabel`에서 null이고 `homeLabel`에서 그 자체, `tars-config`는 반대, `debian-home`은 둘 다 null,
  `tars-homex`는 `tarsLabel`에만 걸린다(접두사 규칙 그대로라는 것을 적어 둔다).

```
(cd init && zig build test)     # 컨테이너에서. macOS에서는 안 끝난다(HANDOFF)
```

## Task 3: `install.zig` — 셋째 파티션을 만들고 굽는다

- 619~620 옆에 `const p3 = storage.partitionName(&p3_buf, path, 3).?;`. `waitForNode`(679)에 p3를 더하고 complain 문구에 셋을 적는다.
- 포맷(689~691) 뒤에:

  ```zig
  say("tars-install: formatting {s} (ext4, {s})\n", .{ p3, storage.HOME_LABEL });
  const mkext4 = [_:null]?[*:0]const u8{ "/usr/bin/mke2fs", "-q", "-t", "ext4", "-e", "remount-ro", "-L", storage.HOME_LABEL, p3 };
  if (!runTool(&mkext4, null, WORK_DIR ++ "/mke2fs-home.log", envp)) return 1;
  ```

  `-e remount-ro`는 superblock의 오류 동작이라 마운트 옵션 문자열이 필요 없다(design 결정 1의 `errors=remount-ro`를 여기서 채운다).
  `mountFs`는 data 인자가 없고, 이 길이면 안 고쳐도 된다.
- `mke2fs.conf`가 initrd에 없다(`guest_tools.sh` · `make_initrd.sh`에 그 이름이 없다 — 위험 6이 실제로 걸린다). `-t ext4`는
  `/etc/mke2fs.conf`의 `[fs_types] ext4` 절에서 `has_journal` · `extent` · `huge_file` · `flex_bg` · `metadata_csum` · `64bit` ·
  `dir_nlink` · `extra_isize`를 읽는데, 파일이 없으면 e2fsprogs의 내장 기본값으로 간다. 그 기본값에 `has_journal`과 `extent`가 드는지를
  측정 3이 `dumpe2fs -h`로 본다(호스트 컨테이너의 e2fsprogs가 `파일?offset=바이트`를 받는다 — p3의 시작은 1MiB + 768MiB + 256MiB =
  1025MiB). 안 들면 `-O has_journal,extent,dir_index,filetype,sparse_super,large_file,flex_bg,64bit,metadata_csum`을 명시한다.
  어느 쪽이든 결과를 design 위험 6 자리에 적는다.
- 갱신 경로(666~670)는 손대지 않는다. `--wipe`는 `--wipe-partitions always`가 p3 자리의 옛 서명도 지우므로 그대로다.

## Task 4: `main.zig` — `/home`을 붙인다

`mountConfig`(167~196) 아래에 `mountHome`을 같은 모양으로 둔다.

- 후보는 `storage.candidates(installed)` 그대로(ISO 부팅은 디스크 열넷, 설치된 부팅은 쉰여섯). 기다림도 같다 — 설치된 부팅만
  `CONFIG_WAIT_MS`. 그래서 ISO 부팅에서 비용은 open 열넷의 ENOENT뿐이다(측정 5).
- 못 찾으면 `tars-init: no disk labelled tars-home among {d} candidates` 한 줄. 기다린 부팅은 `waited {d}ms for home storage`가
  앞에 더 붙는다. design 결정 3의 "shell runs as root" 문구는 M1이 계정과 함께 넣는다.
- 찾으면 `tars-init: home storage {s} (label {s})`, 그리고 `mountFs(found.path, "/home", "ext4", linux.MS.NOSUID | linux.MS.NODEV)`.
  `SYNCHRONOUS`가 없는 것이 이 함수의 핵심이고, 주석에 결정 1의 두 층을 적는다. 성공 줄은 `mountFs`가 찍는 `tars-init: mounted
  ext4 at /home`이다.
- `/home` 디렉터리: `make_initrd.sh:621`의 `mkdir -p` 목록에 `"$WORKDIR/home"`을 더한다(`/config`가 어디서 생기는지 `rg -n
  'WORKDIR/config' kernel/make_initrd.sh`로 먼저 보고 같은 자리에).
- 호출 자리는 `mountConfig` 바로 뒤다. 실패해도 부팅은 계속된다(`feedback_boot_never_blocks`).

## Task 5: `install/check.sh`를 새 배치에 맞춘다

- `truncate -s 3G`(51) → `5G`. 4GiB + 2MiB는 4G에 안 들어간다. 주석(48~50)의 "배치(1GiB + 1GiB, KU-M0)"를 "배치(768 + 256MiB와
  p3, HP-M0)"로, "2GiB에는 안 들어간다"를 "4GiB에는"으로.
- 판정 4d(285~295)의 주석 "배치(1GiB + 1GiB)"를 고친다. 64MiB 디스크는 여전히 거절이고 문구만 `more than 4 GiB`다 — grep이 그
  문구를 보면 같이 고친다.
- 판정 3a(401~435)의 ESP 채우기: `esp_free`가 `mdir`로 읽은 빈 자리만큼 `mcopy`하므로 768MiB에서도 그대로 돈다. 걸리는 시간이
  줄어든 것을 측정 2 옆에 적는다.
- 갱신 계획의 grep(466 "keeps p2")이 새 문구 `all three`에 걸리는지 본다. 걸리면 그 판정의 기대 문자열을 고친다.
- 부팅 2 · 4 · 7의 로그에 `mounted ext4 at /home`과 `home storage /dev/nvme0n1p3`이 새로 생긴다. 이 체인은 그것을 판정하지 않는다
  (홈 체인의 몫) — 다만 `no disk labelled` 실패 힌트(334 · 446 …)에 `tars-home` 줄이 같이 잡혀 읽기 쉬워진다.

```
./install/check.sh      # 혼자 먼저. 판정 수가 Task 0과 같고 PASS
```

## Task 6: 체인 스물다섯째 `home/check.sh`

`install/check.sh`의 `boot_guest` · `stop_guest` · `send` · `wait_log` · `fail` · `clean`을 그대로 가져온다(복사다 — 체인은 서로
독립이라는 규칙, `project_gate_chain_composition`). 머리 주석에 design의 판정 번호와 포트(monitor 45497 · QMP 45498, 이 체인은
시리얼 FIFO만 써서 둘 다 안 연다 — 예약만 적는다)를 쓴다. 디스크는 `truncate -s 5G`의 NVMe(`serial=tarshome`)다.

부팅 1 — ISO + 빈 NVMe + 3GiB NVMe(`nvme1n1`, `serial=tarssmall`):

- 판정 7. `tars-install /dev/nvme1n1` → `more than 4 GiB`를 담은 거절 줄이 나오고 `type YES`가 안 나온다. 3GiB는 HP 전에는
  들어가던 크기라 이 판정이 새 최소값을 증명한다.
- 설치. `tars-install /dev/nvme0n1 --yes` → `tars-install: formatting /dev/nvme0n1p3 (ext4, tars-home)`와 `done.`. `formatting`
  줄 셋 사이의 시간을 시리얼 로그의 순서로는 못 재므로 체인이 `date +%s%N`을 앞뒤로 쳐서 측정 3에 쓴다.
- 판정 1. `cat /sys/block/nvme0n1/nvme0n1p1/size`가 1572864(768MiB), `…p2/size`가 524288, `…p3/start`가 2099200(1025MiB).
  `sfdisk -l`의 글자 폭보다 sysfs의 숫자가 낫다.

부팅 2 — NVMe 혼자:

- 판정 2. 로그에 `tars-init: config storage /dev/nvme0n1p2 (label tars-config)` · `mounted ext2 at /config` · `tars-init: home
  storage /dev/nvme0n1p3 (label tars-home)` · `mounted ext4 at /home` 넷.
- 판정 3. `grep ' /home ' /proc/mounts`가 `/dev/nvme0n1p3 /home ext4 rw,nosuid,nodev,relatime`로 시작하고 `sync`가 없다.
  `cat /proc/fs/ext4/nvme0n1p3/options`에 `errors=remount-ro`와 `data=ordered`가 있다(측정 4).
- 씨앗. `echo hp-m0 > /home/hp-marker; sync` — ext4는 async라 `sync`가 있어야 다음 부팅에 있다. 이것이 결정 1의 다른 면이다.

부팅 3 — NVMe + 남의 ext4(`nvme1n1`, 호스트에서 `truncate -s 64M` 뒤 `mkfs.ext4 -q -L debian-home`):

- 판정 5. `cat /home/hp-marker`가 `hp-m0`. 재부팅을 넘었다.
- 판정 6. `home storage /dev/nvme0n1p3` 그대로이고 로그에 `/dev/nvme1n1`이 home storage로 안 나온다. 후보 순서가 디스크 전체 →
  파티션이라 `nvme1n1`이 p3보다 먼저 읽히는데 라벨이 거른 것이다. 같은 부팅에서 `config storage`도 `nvme0n1p2` 그대로 — `tars-home`이
  설정으로 잡히지 않았다(위험 5).

마지막에 `PASS`. `check.sh:523` 뒤에 `"HP-M0:./home/check.sh"`. `docs/guides/key-files.md`의 체인 표에 한 줄,
`docs/guides/running-tars.md:216~218`의 p1 · p2 · 2GiB 문구를 새 배치와 4GiB로.

## Task 7: 실측 · 문서 · 게이트 · 커밋

- design에 "실측 (M0, 2026-11-02)" 절을 만들고 측정 1~5를 번호대로 적는다. 위험 1(ESP 빈 자리) · 위험 6(feature 목록)은 그 자리에
  "닫혔다/남았다"를 한 줄 더한다.
- 루트 게이트 `./check.sh`(25체인, 12분쯤 + 처음의 커널 빌드). 빨간 체인이 있으면 `out/gate-logs/`의 그 회차부터.
- `git status`로 산출물(`kernel/build/` · `out/`)이 안 섞였는지 본 뒤 좁혀서 add: `kernel/.config` · `kernel/make_initrd.sh` ·
  `init/src/{disk,disk_test,storage,storage_test,install,main}.zig` · `install/check.sh` · `home/check.sh` · `check.sh` · design ·
  이 plan · `docs/guides/{key-files,running-tars}.md`.
- HANDOFF: 열린 서브프로젝트 HP, M0 끝남, 다음 M1(계정)과 그 plan을 게이트 도는 동안 쓴다는 것.

## 시간

- Task 0 · 1: 커널 빌드가 대부분이다. KU-M1의 빌드 시간을 따른다(통째로 다시 만든다).
- Task 2 · 3 · 4: 편집과 `zig build test`. 30분.
- Task 5 · 6: 체인 둘. `install/check.sh` 5분, `home/check.sh`는 부팅 셋에 `mke2fs -t ext4`가 더해져 4분쯤일 것이다 — 측정 3이 답이다.
- Task 7: 루트 게이트 12분 남짓.
