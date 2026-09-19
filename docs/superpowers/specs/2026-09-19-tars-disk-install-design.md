# TARS Disk Install — Design

접두사: DI

Status: 열렸다(2026-09-19). M0이 끝났다(2026-09-19) — 실측 절에 있다. M1은 plan부터.

관련 문서: `2026-09-09-tars-real-machine-design.md`(RM. 하이브리드 ISO와
`init`의 설정 디스크 훑기를 세운 문서. 아래에서 "RM 결정 N"은 그 문서의
것이다) · `2026-08-15-tars-config-persistence-design.md`(CP. ext2 위의
`tars.conf` 계약) · `2026-09-10-tars-userland-tools-design.md`(UT. Debian
패키지를 게스트에 싣는 길).

## 한 줄 요약

USB로 부팅한 기계에서 `tars-install`을 치면 내장 디스크에 ISO와 같은 모양이
들어가고, USB를 뽑아도 뜬다. 시스템은 지금처럼 initramfs에서 돌고, 디스크는
부트 파일과 설정만 담는다.

## 왜 지금인가

RM이 2026-09-10에 "일반 x86_64 노트북에서 뜬다"까지 세웠고 그 판정은 전부
QEMU였다. 실기에 꽂는 것은 다음 사람 몫으로 남겼는데, 2026-09-19에 사용자가
그 다음을 물었다 — "ISO로 부팅한 뒤 내장 디스크에 설치해서 USB 없이 뜨게
할 수 있는가". 지금은 못 한다. 게스트에 파티션·포맷 도구가 없고 커널에
FAT가 없고 `init`이 파티션을 안 본다.

이 서브프로젝트가 답하는 질문은 "USB 없이 뜨게 할 수 있는가" 하나다. 그
답이 서면 실기가 생겼을 때 할 일이 "꽂고 한 줄 치기"가 된다.

사용자가 같은 날 정한 것 둘이 이 문서의 테두리다. 패키지 매니저는 이번에
안 고른다. 실기 노트북은 아직 없다 — 그래서 이 서브프로젝트도 RM처럼 판정을
QEMU 안에서 닫는다. 그것이 가능한 후보라는 것이 이것을 고른 이유이기도 하다.

## 착수 전에 읽거나 잰 것 — 부팅은 한 번도 안 했다

### 확인 1 — ISO 트리는 파일 여섯이다

`boot/make_iso.sh`가 `mktemp` 스테이지에 넣는 것 전부다.

```
boot/bzImage                       4.5MB   (kernel/build/arch/x86/boot/bzImage)
boot/initrd.cpio                   41MB    (kernel/initrd.cpio)
boot/limine/limine.conf
boot/limine/limine-bios.sys        \
boot/limine/limine-bios-cd.bin      | BIOS 경로. 이 문서의 비목표다
boot/limine/limine-uefi-cd.bin     /  El Torito용 FAT 이미지
EFI/BOOT/BOOTX64.EFI               UEFI가 "이동식 매체 기본 경로"로 찾는 파일
```

ISO가 49MB이고 그 중 41MB가 initrd다. 디스크에 갈 것은 이 중 넷 —
`bzImage` · `initrd.cpio` · `limine.conf` · `BOOTX64.EFI`. 나머지 셋은 BIOS와
El Torito의 것이라 ESP에서 아무도 안 읽는다.

### 확인 2 — `limine.conf`의 경로는 ESP에서도 그대로 맞는다

```
/TARS
    protocol: linux
    kernel_path: boot():/boot/bzImage
    module_path: boot():/boot/initrd.cpio
    cmdline: console=ttyS0
```

`boot():`는 limine이 "자기가 실린 볼륨"을 가리키는 이름이다. ISO에서는
ISO9660이고 ESP에서는 FAT32인데 같은 줄이 둘 다 맞는다. 그래서 설치기는
`limine.conf`를 바이트 그대로 복사하고 한 글자도 안 고친다. `serial: yes`와
`console=ttyS0`도 그대로 간다 — 실기에서 시리얼이 없으면 커널이 조용히
무시하고, 화면은 어차피 `terminal`이 프레임버퍼에 그린다(RM 실측).

### 확인 3 — 커널에 FAT도 ISO9660도 없다

```
# CONFIG_ISO9660_FS is not set
# CONFIG_MSDOS_FS is not set
# CONFIG_VFAT_FS is not set
# CONFIG_NLS_CODEPAGE_437 is not set
# CONFIG_NLS_ISO8859_1 is not set
CONFIG_NLS=y
CONFIG_MSDOS_PARTITION=y
CONFIG_EFI_PARTITION=y
CONFIG_EXT2_FS=y
CONFIG_EFIVAR_FS=y
CONFIG_BLK_DEV_NVME=y  CONFIG_SATA_AHCI=y  CONFIG_USB_STORAGE=y
```

파티션 테이블 인식(GPT · MBR)과 블록 장치 드라이버는 RM이 다 켰다. 없는
것은 파일시스템 둘이다.

- FAT가 없으면 ESP를 마운트할 수 없어 파일을 쓸 수 없다. `VFAT_FS`는
  `FAT_FS`를 끌고 오고, FAT의 기본 코드페이지 437과 기본 iocharset
  iso8859-1은 각각 `NLS_CODEPAGE_437` · `NLS_ISO8859_1`이 있어야 마운트가
  된다(없으면 `mount`가 `Invalid argument`로 죽고 dmesg에 "codepage cp437 not
  found"가 찍힌다 — 증상이 원인에서 멀다).
- ISO9660이 없으면 부팅한 USB의 파일을 읽을 수 없다. initrd 안에서 initrd
  자신을 파일로 읽을 길이 없으므로(커널이 풀어서 tmpfs에 놓았고 원본은
  버렸다) 복사 원본은 부팅 매체뿐이다. `boot/make_iso.sh`가 `-R`(Rock
  Ridge)을 주므로 `ISO9660_FS` 하나면 긴 이름과 퍼미션이 온다. `JOLIET`는
  안 켠다 — Windows용 이름표다.

⚠ DI-M0이 고쳤다(실측 1 · 3). 파일시스템 둘만으로는 안 된다 — `-cdrom`이
`/dev/sr0`로 보이려면 `BLK_DEV_SR`도 있어야 하고 이것도 꺼져 있었다.

### 확인 4 — 게스트에 파티션·포맷 도구가 없고, sysroot에도 없다

amd64 sysroot(`/usr/local/amd64-sysroot`)에서 찾은 것.

```
sfdisk     (없음)   ← trixie에서 util-linux가 아니라 fdisk 패키지
mke2fs     (없음)   ← e2fsprogs
mkfs.vfat  (없음)   ← dosfstools
blkid      usr/sbin/blkid   \
lsblk      usr/bin/lsblk     | util-linux:amd64가 이미 있다
wipefs     usr/sbin/wipefs  /
mount      (없음)   ← mount 패키지. 안 싣는다(아래 결정 5)
cp         usr/bin/cp
```

셋의 Debian 의존을 컨테이너 `apt-cache`로 읽었다.

| 패키지 | 설치 크기 | Depends |
|---|---|---|
| `fdisk` 2.41.5 | 529KB | libfdisk1 · libmount1 · libsmartcols1 · libncursesw6 · libreadline8t64 · libtinfo6 |
| `dosfstools` 4.2 | 310KB | libc6뿐 |
| `e2fsprogs` 1.47.2 | 1,537KB | logsave(같은 소스). 실행 파일은 libext2fs2 · libcom-err2 · libe2p2 · libblkid1 · libuuid1을 부른다 |

initrd에 지금 있는 것은 `libcom_err.so.2` 하나다(git의 krb5 사슬이 데려왔다).
`libtinfo6`·`libncursesw6`는 셸과 htop이 이미 데려왔을 가능성이 높고
나머지는 M0에서 UT 방식(`ldd`로 세고 `guest_tools.sh`에 한 줄씩)으로 센다.
`e2fsprogs`는 `mke2fs` 하나만 싣는다 — `fsck`·`debugfs`·`resize2fs`는 이번
범위에 없다.

⚠ DI-M0이 고쳤다(실측 2 · 4 · 5). 위 표의 "있다" 셋은 바이너리만 있었다 —
`blkid`·`lsblk`가 부르는 `libblkid1`·`libmount1`·`libsmartcols1`·`libuuid1`이
sysroot에 없어 게스트에서 돌 수 없는 상태였고, `lsblk`는 그 넷을 채워도
`libudev1`이 또 없다. 그리고 trixie에 `libe2p2`라는 패키지는 없다 —
`libext2fs2t64` 하나가 `libext2fs.so.2`와 `libe2p.so.2`를 둘 다 싣는다.

### 확인 5 — `init`은 디스크 전체만 훑는다 (RM 결정 12)

`init/src/storage.zig`의 `CANDIDATES`가 열넷이고 전부 디스크 이름이다.

```
/dev/vda .. vdd · /dev/nvme0n1 .. nvme3n1 · /dev/sda .. sdd · /dev/mmcblk0 .. 1
```

판정은 오프셋 1080의 ext2 매직 `53 ef`와 1144의 라벨 접두 `tars-`다. RM
결정 12가 파티션을 뺀 근거는 둘이었다 — 그때 설정 디스크가 파티션 없는
ext2였다는 것과, 내장 디스크는 GPT라 디스크 전체를 읽으면 매직이 안 맞아
남의 root를 잡을 길이 없다는 안전 효과.

이 서브프로젝트는 설정을 GPT 안의 파티션에 두므로 이 규칙을 바꿔야 한다.
안전 효과는 라벨 필터가 따로 지키고 있었다는 것이 결정 6의 근거다.

### 확인 6 — `init`은 `mount` 시스콜을 직접 부른다

`init/src/main.zig`의 `mountFs()`가 `proc`·`devpts`·`ext2`를 시스콜로 붙인다.
게스트에 `mount` 명령이 없어도 `init`이 곤란한 적이 없었던 이유이고,
`tars-install`이 같은 길을 가면 된다. `devtmpfs`는 커널이
`CONFIG_DEVTMPFS_MOUNT`로 스스로 붙이고, 드라이버가 등록한 장치 노드만
담는다 — 파티션 노드(`nvme0n1p1`)는 커널이 파티션 테이블을 다시 읽을 때
생긴다.

### 확인 7 — `machine/check.sh`가 이 체인의 뼈대다

OVMF · `q35,i8042=off` · `-cdrom ../out/tars.iso` · NVMe 설정 디스크
(`-device nvme,drive=cfg,serial=tarscfg`) · USB 키보드. 판정은
`tars-init: config storage /dev/nvme0n1 (label tars-machine)`. 부팅 하나다.

이 서브프로젝트의 체인은 여기서 `-cdrom`을 떼는 부팅이 하나 더 있다는
것만 다르다. OVMF의 펌웨어 초기화가 느려 이 체인은 고정 timeout을 안
쓰고 시리얼의 진행을 본다 — 새 체인도 같은 방식이다.

### 확인 8 — 게이트의 나머지 여덟 체인은 `-kernel`로 뜬다

`-kernel bzImage -initrd initrd.cpio`라 부팅 매체라는 것이 없다.
`tars-install`은 그 환경에서 "설치할 파일이 없다"로 멈춰야 한다(결정 4의
매체 탐색이 그 경우를 다룬다). 그 체인들에는 아무 영향이 없다.

### 확인 9 — ISO의 볼륨 ID를 우리가 안 정했다

`boot/make_iso.sh`의 `xorriso -as mkisofs`에 `-V`가 없다. 기본값이 무엇인지
호스트에서는 못 본다(`xorriso`·`isoinfo`가 컨테이너에만 있다). M0에서 읽고
적는다. 매체를 이름으로 알아보려면 `-V TARS`를 주는 것이 맞고, 다만 이
설계의 매체 탐색은 이름이 아니라 파일 존재로 판정하므로(결정 4) `-V`는
사람이 `blkid`로 알아보기 위한 것이다.

⚠ DI-M0이 읽었다(실측 6). 기본값은 `ISOIMAGE`다.

## 결정

### 결정 1 — 디스크의 모양은 ISO와 같다. root 파일시스템은 없다 — 사용자가 골랐다

셋 중에서 골랐다.

- ISO와 같은 모양을 디스크에. ESP에 부트 파일 넷, 옆에 설정 파티션. 시스템은
  initramfs에서 돈다. ← 이것
- 위와 같은데 legacy BIOS도. `limine bios-install`을 게스트에서 돌려야 하고
  `limine` 실행 파일과 MBR 경로가 하나 더 들어온다. 요즘 노트북은 전부
  UEFI라 값이 낮다.
- 디스크 위의 진짜 root 파일시스템. initramfs를 버리고 `switch_root`. 부팅
  구조 전체가 바뀌고, 그것은 패키지 매니저의 전제에 가까운 별 서브프로젝트다.

첫째를 고른 근거는 지금 구조를 안 바꾼다는 것이다. `init`·`terminal`·
게이트 열두 체인이 initramfs 위에 서 있고, 이 서브프로젝트는 그 위에
"initramfs를 어디서 읽어 오는가"만 하나 더한다.

### 결정 2 — 파티션은 둘이고 나머지는 비운다 — Claude가 정했다

| 파티션 | 크기 | 종류 · 파일시스템 | 이름 · 라벨 |
|---|---|---|---|
| p1 | 256MiB | EFI System · FAT32 | GPT 이름 `TARS-BOOT`, FAT 라벨 `TARS-BOOT` |
| p2 | 1GiB | Linux filesystem · ext2 | GPT 이름 `TARS-CONFIG`, ext2 라벨 `tars-config` |

256MiB는 49MB의 다섯 배다. initrd가 커지는 속도(UT가 65개 도구로 41MB)를
보면 한동안 넉넉하고, FAT32의 최소 크기(32MiB 근처)를 여유 있게 넘긴다.
1GiB는 설정에 필요한 것보다 훨씬 크지만(`tars.conf` · rc 셋 · 히스토리 ·
zoxide DB — 다 합쳐 MB 아래) 디스크 전체를 ext2로 잡는 것보다 낫다 —
500GB를 `mke2fs`하면 수십 초가 걸리고 inode 테이블이 GB를 먹는다.
나머지를 비워 두는 것이 다음 사람을 위한 자리다. root 파일시스템이든
패키지 매니저의 창고든 그 빈 곳에 p3으로 들어오면 되고, 이 설계는 그것을
안 정한다.

ext2 라벨이 `tars-config`인 것은 CP·RM의 계약(`tars-` 접두)이다. GPT 이름은
`sfdisk`의 `name=`이고 펌웨어 메뉴와 `lsblk`에 보이는 것이라 대문자로 둔다.

### 결정 3 — 만드는 것은 외부 도구 셋이다 — 사용자가 골랐다

`sfdisk`(GPT) · `mkfs.vfat`(FAT32) · `mke2fs`(ext2). 셋 중 GPT는 우리 코드로
쓸 수도 있었다 — 파티션 둘짜리 고정 배치는 헤더 둘과 항목 둘과 CRC32로
끝나고, TS가 chrony 대신 우리 SNTP를 고른 논리("어려운 부분을 뺐으니 남은
일은 같다")가 여기에도 선다. FAT32에는 안 선다 — BPB · FSInfo · FAT 둘 ·
root 클러스터를 우리가 쓰고 틀리면 펌웨어가 조용히 무시한다. 셋을 같은
편에 두는 것이 코드와 문서를 단순하게 하고, 이 서브프로젝트가 묻는 것은
"USB 없이 뜨는가"이지 "GPT를 우리가 쓸 수 있는가"가 아니다.

`sfdisk`는 스크립트 입력을 받는다. 설치기가 stdin으로 넘길 것은 이 세 줄이다.

```
label: gpt
size=256MiB, type=uefi, name=TARS-BOOT
size=1GiB,   type=linux, name=TARS-CONFIG
```

(`type=uefi`·`type=linux`는 `sfdisk`가 GPT GUID의 별칭으로 받는 이름이다.
`--wipe always`로 옛 서명을 지운다.) `sfdisk`는 쓰고 나서 `BLKRRPART`로
커널에 파티션 테이블을 다시 읽히므로 `nvme0n1p1`·`p2` 노드는 그 뒤에
devtmpfs에 나타난다. 나타나기까지 짧은 기다림이 필요할 수 있다 — 위험 2.

### 결정 4 — 복사 원본은 부팅 매체이고, 파일 존재로 알아본다 — Claude가 정했다

`tars-install`은 `storage.zig`의 후보 열넷(결정 6 뒤에는 파티션까지)을
순서대로 ISO9660 읽기 전용으로 마운트해 보고 `boot/limine/limine.conf`가
있는 첫 것을 매체로 잡는다. QEMU의 `-cdrom`은 `/dev/sr0`이라 후보에
`/dev/sr0`를 이 목적으로만 더한다(설정 디스크 후보에는 안 넣는다 — ISO는
ext2가 아니다). USB 스틱은 `/dev/sdX`다.

이름(`-V`)이 아니라 파일로 판정하는 것은 판정이 곧 쓰임이기 때문이다 —
찾는 것이 그 파일들이고, 이름이 맞는데 파일이 없는 매체는 어차피 못 쓴다.

매체를 못 찾으면 목록은 보여 주되 설치는 거부한다. `-kernel`로 뜬 여덟
체인과, 설치된 디스크로 뜬 기계(ISO 없이 ESP에서 떴다 — ESP는 FAT라
ISO9660 마운트가 실패한다)가 이 경우다. 후자는 "설치된 기계에서 다시
설치"인데 그때는 원본이 ESP 자신이라 뜻이 없다. 갱신은 늘 새 ISO로
부팅해서 한다(결정 8).

### 결정 5 — `tars-install`은 `init`과 같은 자리의 Zig 실행 파일이다 — Claude가 정했다

`init/src/install.zig`에 두고 `init/build.zig`에 `addExecutable` 하나 더.
`make_initrd.sh`가 `usr/bin/tars-install`로 싣는다. `init`이 아닌 별도 실행
파일인 이유는 확인 8이다 — 부팅 경로에 안 들어가야 열두 체인에 닿지
않는다. `init` 옆에 두는 이유는 `storage.zig`의 후보 목록과 라벨 판정을 그대로
쓰기 위해서다 — 목록에 보이는 것과 부팅 때 찾는 것이 같은 코드여야 "설치했는데
못 찾는다"가 안 생긴다.

셸 스크립트로 안 쓰는 이유는 둘이다. 게스트에 `mount` 명령이 없고(확인 6)
싣지 않는다 — `init`처럼 시스콜로 붙이는 것이 한 겹 적다. 그리고 크기·모델·
착탈식은 `/sys/block/<dev>/{size,device/model,removable}`을 읽는 것이라
Zig가 셸보다 짧고 실패가 분명하다.

외부 도구 셋은 `fork`+`execve`로 부르고 종료 코드를 본다. 0이 아니면 그
자리에서 멈추고 무엇이 몇으로 죽었는지 찍는다 — 디스크를 반쯤 지운 채 멈출
수 있다는 것을 위험 4에 적는다.

### 결정 6 — `init`의 후보에 파티션을 더한다. 안전은 라벨이 지킨다 — Claude가 정했다

RM 결정 12를 바꾼다. `CANDIDATES`에 각 디스크의 첫 두 파티션을 더한다 —
`nvme0n1p1`·`p2`, `sda1`·`sda2`, `vda1`·`vda2`, `mmcblk0p1`·`p2` 식으로. 순서는
디스크 전체 먼저, 그 다음 파티션이다. 게이트 열두 체인의 디스크는 전부
파티션 없는 ext2라 그 순서에서 먼저 잡히고, 판정이 안 바뀐다.

RM 결정 12의 안전 효과("남의 root를 잡을 길이 없다")는 그때도 라벨 필터가
지키고 있었다 — 매직이 맞아도 라벨이 `tars-`로 시작해야 잡는다. 파티션을
보게 되면 남의 ext2 root 파티션의 매직은 맞지만 라벨은 안 맞는다. 라벨이
우연히 `tars-`로 시작하는 남의 파티션은 이 설계가 다루지 않는다.

둘씩만 보는 것은 `MAX_EVENT = 32`와 같은 종류의 상한이다. 우리가 만드는
배치가 p2까지이고, 없는 노드를 여는 비용은 ENOENT 하나다.

### 결정 7 — UX는 목록 · 계획 · 확인의 셋이다 — 사용자가 요구를 적었고 Claude가 모양을 정했다

사용자의 요구는 "어느 `/dev/nvme몇`인지 즉시 알기 어렵다. 인자 없이
치면 쓸 수 있는 디스크 목록이 나와야 한다. 상호작용은 없어도 되지만
사용자가 알고 설치할 수 있는 정보는 반드시 나와야 한다"였다.

인자 없이 `tars-install`:

```
tars-install: boot medium /dev/sr0 (TARS iso, 49 MB)

  /dev/nvme0n1   512 GB   Samsung SSD 980       internal   blank
  /dev/sda        32 GB   SanDisk Ultra         removable  boot medium
  /dev/sdb        16 GB   Kingston DataTraveler removable  foreign (ext2 tars-config)

tars-install <disk>       install onto <disk>; everything on it is erased
tars-install <disk> --yes same, without asking
tars-install <disk> --wipe erase an installed disk instead of updating it
```

상태는 셋이다. `boot medium`은 결정 4가 잡은 것이고 대상에서 뺀다.
`TARS installed`는 p1이 FAT이고 `boot/bzImage`가 있고 p2가 ext2 라벨
`tars-`인 것 — 갱신 경로(결정 8)로 간다. 나머지는 전부 `blank` 또는
`foreign (<무엇이 보이는지>)`이고 새 설치는 그것을 통째로 지운다. 지울
내용을 한 단어라도 보여 주는 것이 "알고 설치한다"의 최소다.

`tars-install /dev/nvme0n1`은 계획을 찍고 `YES`를 받는다.

```
tars-install: /dev/nvme0n1 (512 GB, Samsung SSD 980) will be erased.
  p1  256 MiB  EFI System  FAT32  TARS-BOOT   <- bzImage, initrd.cpio, limine
  p2    1 GiB  Linux       ext2   tars-config <- your settings, empty at first
  rest unallocated
type YES to continue:
```

`--yes`가 그 줄을 건너뛴다. 게이트가 시리얼로 `YES`를 칠 수도 있지만 플래그가
한 글자도 안 흔들린다. 끝나면 `sync`를 부르고 이 줄로 끝난다.

```
tars-install: done. remove the boot medium and reboot.
```

재부팅은 안 한다 — PM이 세운 종료 경로는 `init`의 것이고 설치기가 그것을
흉내 낼 이유가 없다. 사용자가 전원 버튼을 누르면 된다.

### 결정 8 — 설치된 디스크에는 부트 파일만 갈고 설정은 남긴다 — 사용자가 골랐다

`TARS installed`로 판정된 대상에 `tars-install <disk>`를 치면 p1을 마운트해
넷을 덮어쓰고 p2는 열지도 않는다. 계획 문구가 `update`로 바뀐다.

```
tars-install: /dev/nvme0n1 already has TARS. p1 will be updated, p2 (your settings) is kept.
```

이것이 실제로 가장 자주 밟는 경로다 — ISO를 새로 구울 때마다 내장 디스크의
커널과 initrd를 갈아야 하고, 그때마다 설정을 잃으면 설치가 아니라 매번
새 기계다. 통째로 다시 하고 싶으면 `--wipe`를 준다. 셋 중 "항상 지운다"와
"거부하고 `--wipe`를 요구한다"를 사용자가 안 골랐다.

### 결정 9 — 판정은 열세번째 체인 `install/check.sh`이고 부팅 셋이다 — Claude가 정했다

`machine/check.sh`를 본뜬다. OVMF · q35 · NVMe 빈 디스크(`truncate` 2GiB) ·
USB 키보드. 디스크는 매 회 새로 만든다.

1. ISO + 빈 NVMe. 시리얼로 `tars-install`을 쳐서 목록에 `/dev/nvme0n1 … blank`와
   `boot medium`이 보이는지, 그 다음 `tars-install /dev/nvme0n1 --yes`가
   `done` 줄로 끝나는지 본다.
2. `-cdrom` 없이 같은 NVMe만. `tars-init: config storage /dev/nvme0n1p2 (label
   tars-config)`와 셸 프롬프트. 여기서 `/config/di-marker`에 한 줄을 쓴다.
   이것이 "USB 없이 뜬다"의 증명이다.
3. 다시 ISO + 그 NVMe. `tars-install`이 `TARS installed`로 보이는지,
   `tars-install /dev/nvme0n1 --yes`가 `update` 문구로 끝나는지. 그리고
   `-cdrom` 없이 한 번 더 떠서 `di-marker`가 살아 있는지. 이것이 "설정을
   남긴다"의 증명이다.

부팅 넷(3의 둘째 포함)이고 OVMF라 한 회에 2~3분이 든다 — 위험 5. 판정은
전부 시리얼의 부분 문자열이고 화면 덤프는 안 쓴다.

`check.sh`의 `CHAINS`에 `"DI-M2:./install/check.sh"`로 들어간다. M1이 끝나면
`DI-M1`로 넣고 M2가 이름을 올린다.

### 결정 10 — 커널 옵션 여섯을 켠다 — Claude가 정했다

`BLK_DEV_SR` · `ISO9660_FS` · `FAT_FS` · `VFAT_FS` · `NLS_CODEPAGE_437` ·
`NLS_ISO8859_1`. `BLK_DEV_SR`은 M0의 plan을 쓰다가 찾은 것이다 — ATAPI
CD-ROM을 블록 장치로 만드는 드라이버이고 이것이 없으면 파일시스템이 있어도
붙일 노드가 없다(실측 1). 손으로 적는 줄은 다섯이고 `FAT_FS`는 프롬프트가
없어 `VFAT_FS`의 `select`가 켠다(실측 3).
`project_kernel_config`의 규율대로 켜는 이유를 각각 `.config`의 커밋 메시지에
적고, bzImage 증가를 M0에서 잰다. `JOLIET`·`ZISOFS`·`MSDOS_FS`·`EXFAT_FS`는
안 켠다 — 우리 ISO는 Rock Ridge이고 ESP는 FAT32다.

## 비목표

- legacy BIOS. `limine bios-install`과 MBR 경로. 결정 1. 2026-09-19에 사용자가
  비용을 묻고 나서 "그대로 비목표"로 정했다. 잰 비용을 적어 둔다 — 나중에
  집는 사람이 다시 재지 않도록.
  - GPT 디스크에서 `bios-install`은 stage 2를 놓을 BIOS boot 파티션(GUID
    `21686148-6449-6E6F-744E-656564454649`)을 요구한다(`limine.c`의
    "no BIOS boot partition specified"). 이 설계의 배치(결정 2)에는 그것이
    없으므로, 나중에 넣으려면 설치된 디스크를 다시 파티션해야 하고 그때
    갱신 경로(결정 8)로는 안 된다 — 새 설치가 된다. 1MiB면 된다.
  - `limine-bios.sys`를 ESP의 `boot/limine/`에 함께 복사해야 한다(stage 2가
    거기서 찾는다). 복사 목록 넷이 다섯이 된다.
  - 게스트에 `limine` 실행 파일이 필요하다. vendor된 것은 arm64 컨테이너용이다.
    `limine.c`(1,472줄, libc만 쓴다)를 컨테이너의 `x86_64-linux-gnu-gcc`로
    `-static` 컴파일하면 되고 딸려 오는 라이브러리는 0이다.
  - 설치기는 `limine bios-install <disk> <p번호> --no-gpt-to-mbr-isohybrid-conversion`을
    한 번 더 부른다. 플래그는 ISOHYBRID 감지 시 GPT를 MBR로 바꾸는 동작을
    끄는 것이다 — 우리 디스크에는 ISO9660 서명이 없어 안 걸리지만 늘 준다.
  - 게이트에 SeaBIOS로 그 디스크만 붙여 뜨는 부팅이 하나 더 든다(30~40초).
    체인 하나에 펌웨어 둘이 들어오는 것이 코드보다 비싼 부분이다.
- NVRAM 부트 항목(`efibootmgr` · efivarfs 쓰기). `\EFI\BOOT\BOOTX64.EFI`는
  펌웨어가 항목 없이 찾는 기본 경로라 필요 없다. 다른 OS가 옆에 있어 부트
  순서를 다투는 상황은 이 설계 밖이다(아래 "기존 파티션" 항목).
- Secure Boot. RM 비목표 그대로. 실기에서는 끈다.
- 디스크 위의 root 파일시스템 · `switch_root`. 결정 1의 셋째.
- 기존 파티션을 줄여 옆에 넣기(dual boot). 새 설치는 늘 디스크 전체를 지운다.
- USB 스틱을 대상으로 삼기. 코드로는 되겠지만 안 잰다.
- 실기에서 꽂아 보기. 실기가 없다. README에 순서만 적는다.
- 설치기가 재부팅하는 것. 결정 7.
- `fsck` · `resize2fs` · 설정 파티션 복구. 게스트에 `mke2fs`만 싣는다.

## 위험

### 위험 1 — OVMF가 `-cdrom`과 NVMe 중 무엇을 먼저 고르는지 모른다

부팅 1과 3에서 둘 다 붙어 있고 둘 다 부팅 가능하다(3에서는 NVMe에 ESP가
있다). OVMF가 NVMe를 먼저 고르면 부팅 3이 ISO가 아니라 설치된 디스크로 뜨고
`tars-install`이 매체를 못 찾아(결정 4) 체인이 죽는다. 처방 후보는
`-boot order=d`(SeaBIOS 문법이라 OVMF가 무시할 수 있다) 또는 OVMF_VARS에
부트 순서를 심는 것, 또는 부팅 3에서 NVMe의 ESP를 잠시 다른 컨트롤러 뒤에
두는 것. 실기에서는 사용자가 USB를 뽑거나 펌웨어 메뉴에서 고르므로 문제가
아니다.

DI-M0이 닫았다(실측 10). ISO와 설치된 NVMe를 둘 다 물린 부팅에서 OVMF는
ISO를 골랐다 — 처방이 필요 없고 `bootindex`는 재지 않았다.

### 위험 2 — `sfdisk` 뒤 파티션 노드가 늦게 나타날 수 있다

`BLKRRPART` 뒤 devtmpfs에 `nvme0n1p1`이 생기는 것은 커널의 일이고 보통
즉시지만, 설치기가 바로 `mkfs.vfat /dev/nvme0n1p1`을 부르면 ENOENT를 볼 수
있다. 처방은 HD-M2가 키보드에 쓴 것과 같은 한정된 기다림 — 최대 3초, 100ms
간격으로 `stat`. 그래도 없으면 멈춘다.

DI-M0이 닫았다(실측 8). `sfdisk`가 돌아온 직후 첫 확인에서 둘 다 있었다 —
기다림 0회. 한정된 기다림은 그래도 둔다. 비용이 없고 실기의 답은 아직
모른다.

### 위험 3 — FAT에 쓴 41MB가 `sync` 전에는 캐시에만 있다

`cp`가 돌아와도 디스크에는 안 갔을 수 있고, 사용자가 전원 버튼을 누르면
`init`의 종료 경로가 `sync`를 부르는지에 달린다. 설치기가 `umount`
전에 `sync`를 직접 부르고 `umount`까지 하고 나서야 `done`을 찍는다. 부팅
2가 그것을 증명한다 — 캐시에만 있었으면 커널이 `bzImage`를 못 읽는다.

DI-M0이 닫았다(실측 9). 손으로 복사한 ESP에서 `-cdrom` 없이 셸까지 4초에
왔다. `cp`가 866ms, `sync`가 29ms, `umount`가 94ms였다 — `cp`가 이미 대부분을
디스크에 보냈고 `sync`는 나머지를 치른다.

### 위험 4 — 도구가 중간에 죽으면 디스크가 반쯤 지워진 채 남는다

`sfdisk`가 성공하고 `mkfs.vfat`이 실패하면 GPT는 새것이고 p1은 빈 것이다.
되돌리지 않는다 — 원래 내용은 `--wipe always`가 이미 지웠고 되돌릴 것이
없다. 대신 그 상태의 디스크가 다음 `tars-install` 목록에 `foreign (gpt,
no filesystem)`으로 보이고 새 설치가 다시 되게 한다. 즉 판정이 "설치
됐음"을 p1의 `boot/bzImage` 존재로 하는 것(결정 7)이 이 위험의 처방이다.

### 위험 5 — 부팅 넷이 게이트에 2~3분을 더한다

OVMF 부팅이 SeaBIOS보다 느리고(`machine/check.sh`가 고정 timeout을 안 쓰는
이유) 넷이다. GL이 루트 게이트를 16분대로 만들었고 TS가 부팅 셋을 더했다.
받아들인다 — 이 체인이 증명하는 것이 다른 방법으로는 증명이 안 된다.
M2가 끝나면 루트 게이트 시각을 HANDOFF의 게이트 현황에 적는다.

### 위험 6 — 이미지 재빌드가 필요하다

Dockerfile의 amd64 다운로드 목록에 셋이 들어가므로 `docker build`가 다시
돈다(TS-M3의 tzdata와 같은 종류). HANDOFF에 같은 경고를 남긴다.

⚠ 현실이 됐다(실측 4). 1분 09.74초. 이 저장소를 새로 받은 사람은
`docker build`부터다.

### 위험 7 — `fdisk` 패키지가 라이브러리 여섯을 끌고 온다

`libfdisk1`·`libmount1`·`libsmartcols1`·`libncursesw6`·`libreadline8t64`·`libtinfo6`.
초기 initrd 증가가 몇 MB일 수 있다. M0이 세고, 크면 `sgdisk`(gdisk 패키지 —
libstdc++·libuuid·libpopt)와 비교한다. 결정 3은 "외부 도구"까지이고 어느
도구인지는 M0의 숫자가 정한다.

DI-M0이 닫았다(실측 5). 새 라이브러리는 일곱이고 푼 크기 합이 2,129,864
바이트, initrd 증가가 1,100,550바이트다. `sgdisk`는 재지 않았다 — 합이
plan이 둔 문턱 3,000,000을 안 넘는다. 도구는 `sfdisk`다.

## DI-M0이 실행으로 증명한 것

plan은 `docs/superpowers/plans/2026-09-19-tars-disk-install-di-m0.md`이고
하네스 전문이 그 Task 5에 글자 그대로 있다. 커밋 넷 — `kernel/.config`
(`3c0121f`) · `devcontainer/Dockerfile`(`e96fccd`) · `kernel/guest_tools.sh`
(`213a599`) · 이 문서. 숫자는 로그에서 그대로 옮겼다.

### 실측 1 — `BLK_DEV_SR`이 없었다 (착수 전, plan을 쓰면서)

`kernel/.config:1165`가 `# CONFIG_BLK_DEV_SR is not set`이었다. `-cdrom`은
q35의 AHCI에 ATAPI 장치로 붙고 그것을 `/dev/sr0`로 만드는 것이 `sr`이다.
`ATA`·`SATA_AHCI`·`SCSI`는 RM이 켰고 `sr` 하나가 빠져 있었다 — 확인 3이
파일시스템만 보고 드라이버를 안 봤다. 그래서 결정 10이 다섯에서 여섯이 됐다.

### 실측 2 — `blkid`·`lsblk`는 바이너리만 있었다 (착수 전)

확인 4가 "있다"고 적은 셋이 부르는 `libblkid1`·`libmount1`·`libsmartcols1`·
`libuuid1`이 Dockerfile 목록에 없었다. `util-linux:amd64`는 `dmesg` 하나
때문에 받았고 `dmesg`는 libc만 부르므로 지금까지 아무도 몰랐다.
`apt-get download`는 의존을 안 따라간다 — 라이브러리는 이름을 적어야 온다.

### 실측 3 — 커널 옵션 여섯이 bzImage를 77,824바이트 키운다 (측정 1)

손으로 다섯 줄을 `=y`로 바꾸고 빌드했다(20.59초 — plan이 잡은 1분 05초보다
빨랐다). `olddefconfig`가 여덟 줄을 딸려 왔다 — 예상한 일곱(`CDROM=y` ·
`# JOLIET` · `# ZISOFS` · `FAT_FS=y` · `FAT_DEFAULT_CODEPAGE=437` ·
`FAT_DEFAULT_IOCHARSET="iso8859-1"` · `# FAT_DEFAULT_UTF8`)에
`CONFIG_LEGACY_DIRECT_IO=y` 하나가 더 있다. `fs/fat/Kconfig:6`이 `FAT_FS`에
`select LEGACY_DIRECT_IO`를 건다. 되접은 뒤 재빌드해 고정점을 확인했다.

| | 바이트 |
|---|---|
| bzImage 전 | 4,486,144 |
| bzImage 후 | 4,563,968 |
| 차 | 77,824 |

### 실측 4 — 패키지는 열하나가 아니라 열이다 (측정 2)

trixie에 `libe2p2`가 없다. `libext2fs2t64` 하나가 `libext2fs.so.2`와
`libe2p.so.2`를 둘 다 싣는다(`dpkg -c`로 봤다). `e2fsprogs`의 의존은
`Depends:`가 아니라 `Pre-Depends:`에 있어 plan의 첫 질문이 `logsave` 하나만
돌려줬다. `libss2`는 안 받았다 — `debugfs`의 것이고 `mke2fs`가 안 부른다
(아래 `readelf`). 이미지는 1분 09.74초에 구워졌다.

셋이 부르는 것(`readelf -d`, 재귀 전):

| 바이너리 | 바이트 | DT_NEEDED |
|---|---|---|
| `usr/sbin/sfdisk` | 162,184 | libfdisk.so.1 · libsmartcols.so.1 · libtinfo.so.6 · libreadline.so.8 · libc.so.6 |
| `usr/sbin/mkfs.fat` | 64,352 | libc.so.6 |
| `usr/sbin/mke2fs` | 146,000 | libext2fs.so.2 · libcom_err.so.2 · libblkid.so.1 · libuuid.so.1 · libe2p.so.2 · libc.so.6 |

`libfdisk.so.1`이 `libuuid.so.1`·`libblkid.so.1`을 부르고 `libmount`는 안
부른다. `mkfs.vfat -> mkfs.fat`, `mkfs.ext2 -> mke2fs`가 심볼릭 링크다.
sysroot에 `etc/mke2fs.conf`(813바이트)가 왔지만 initrd에는 안 싣는다 — 실측
8이 그것 없이 어떻게 되는지를 봤다.

### 실측 5 — initrd가 1,100,550바이트 늘고 새 파일이 열이다 (측정 3)

| | 바이트 |
|---|---|
| initrd 전 | 40,735,276 |
| initrd 후 | 41,835,826 |
| 차 | 1,100,550 |

새 파일 열 — 도구 셋과 라이브러리 일곱. 푼 크기다.

| 파일 | 바이트 |
|---|---|
| lib/x86_64-linux-gnu/libfdisk.so.1 | 526,520 |
| lib/x86_64-linux-gnu/libext2fs.so.2 | 446,800 |
| lib/x86_64-linux-gnu/libblkid.so.1 | 396,256 |
| lib/x86_64-linux-gnu/libreadline.so.8 | 362,728 |
| lib/x86_64-linux-gnu/libsmartcols.so.1 | 313,496 |
| lib/x86_64-linux-gnu/libe2p.so.2 | 45,016 |
| lib/x86_64-linux-gnu/libuuid.so.1 | 39,048 |
| usr/bin/sfdisk | 162,184 |
| usr/bin/mke2fs | 146,000 |
| usr/bin/mkfs.vfat | 64,352 |
| 라이브러리 일곱 | 2,129,864 |
| 열 전부 | 2,502,400 |

`libmount`는 안 왔다(위 실측 4). `libtinfo`·`libcom_err`는 이미 있었다.
위험 7의 문턱(3,000,000)을 안 넘어 `sgdisk`는 안 쟀다. `tools` 체인이
목록 72→75로 PASS.

하네스가 덤으로 찾은 것 — `lsblk`는 `libudev.so.1`을 부르고 그것은
`libudev1` 패키지에 있어 sysroot에 없다. 하네스 전용 목록에서 `lsblk`를
뺐다(측정 스크립트가 안 쓴다). 저장소에는 원래 안 들어가는 것이라 고칠
것이 없다.

### 실측 6 — ISO 볼륨 ID의 기본값은 `ISOIMAGE`다 (측정 4)

`xorriso -pvd_info`의 `Volume Id`와 `blkid`의 `LABEL`이 같다. `UUID`는
굽는 시각(`2026-09-19-03-55-02-00`)이고 `PTTYPE=dos`(하이브리드의 보호
MBR)다. ISO는 49,463,296에서 50,640,896으로 1,177,600바이트 늘었다.

### 실측 7 — `-cdrom`이 `/dev/sr0`로 보이고 ISO9660으로 붙는다 (측정 5)

부팅 A(ISO + 빈 NVMe). `/proc/filesystems`에 `ext2 vfat iso9660`. dmesg에
`sr 2:0:0:0: [sr0] scsi3-mmc drive` · `cdrom: Uniform CD-ROM driver Revision:
3.20` · `Attached scsi CD-ROM sr0`. `blkid`가 `TYPE=iso9660 LABEL=ISOIMAGE`.
`mount -t iso9660 -o ro`가 rc 0이고 최상위가 `EFI boot boot.catalog`, 넷의
이름이 Rock Ridge 그대로(`boot/limine/limine.conf`, `LIMINE.CON;1`이 아니다)
이며 크기가 하네스 ISO의 것과 같다(bzImage 4,563,968 · initrd.cpio 42,169,589
· limine.conf 908 · BOOTX64.EFI 348,160). isofs는 dmesg에 아무 말도 안 한다.
빈 NVMe에 `blkid -p`는 빈 문자열을 돌려준다 — 설치기의 "빈 디스크" 판정이
기댈 수 있는 모양이다.

### 실측 8 — `sfdisk` → `mkfs.vfat` → `mke2fs`가 그대로 먹는다 (측정 6 · 7)

| 단계 | rc | ms |
|---|---|---|
| `sfdisk --wipe always` (세 줄 스크립트) | 0 | 3,546 |
| p1·p2 노드 | 첫 확인에서 있었다 | 0회 기다림 |
| `mkfs.vfat -F 32 -n TARS-BOOT` | 0 | 156 |
| `mke2fs -t ext2 -L tars-config` | 0 | 4,188 |
| `mount -t vfat` | 0 | |

`sfdisk`는 `type=uefi`·`type=linux` 별칭을 알아듣고 `C12A7328-…`·
`0FC63DAF-…`를 썼다. `sfdisk --dump`에 `name="TARS-BOOT"` ·
`name="TARS-CONFIG"`. 3.5초는 `Syncing disks.`까지 잰 것이다.

`mkfs.vfat`이 경고 셋을 찍는다 — `Cannot initialize conversion from codepage
850 to ANSI_X3.4-1968: Invalid argument`(반대 방향 하나 더) · `Using internal
CP850 conversion table`. 게스트에 iconv의 gconv 모듈이 없고 로캘이 C라
라벨 변환에 내장 표를 쓴 것이다. 라벨이 ASCII라 결과는 같다. M1이
stderr를 그대로 보여 주면 이 세 줄이 사용자 눈에 띈다.

`mke2fs`는 `mke2fs.conf` 없이 조용하다 — 언급 0줄. 내장 기본값으로 4k 블록
262,144개 · inode 65,536개를 만들었다. `blkid`가 p1을 `TYPE=vfat
LABEL=TARS-BOOT`, p2를 `TYPE=ext2 LABEL=tars-config`로 읽는다. vfat 마운트
뒤 dmesg에 codepage·iocharset 줄이 없다 — NLS 둘이 든 것이다.

### 실측 9 — 손으로 만든 ESP에서 `-cdrom` 없이 뜬다 (측정 8)

부팅 A가 넷을 복사했다 — `cp` 866ms, `sync` 29ms, `umount` 94ms.
`limine.conf`는 표지 ` tars.di=esp`가 붙어 908에서 920바이트가 됐다.

부팅 B(NVMe만). `efi: EFI v2.7 by Debian distribution of EDK II`, 콘솔 셸까지
4초, cmdline에 `tars.di=esp` — ESP의 `limine.conf`로 떴다. 설정 저장소는
`/dev/vda (label tars-di)`다. `init`이 아직 파티션을 안 보므로 p2를 못 잡는
것이 맞다(결정 6은 M1).

부팅 B에서 `/dev/sr0`가 `present`인데 `blkid`는 빈 문자열이다. `-cdrom`을
안 줘도 QEMU가 빈 CD-ROM 장치를 기본으로 붙인다(`-nodefaults`를 안 준다).
노드가 있다고 매체가 있는 것이 아니다 — 결정 4가 파일 존재로 판정하는
것이 맞고, M1은 `sr0`가 있다는 것으로 아무것도 결론짓지 않는다.

### 실측 10 — OVMF는 ISO를 먼저 고른다 (측정 9)

부팅 C(ISO + 설치된 NVMe). cmdline에 `tars.di=esp`가 없다 — ISO로 떴다.
게스트가 `sr0`를 `TYPE=iso9660 LABEL=ISOIMAGE`로, p1·p2를 실측 8과 같은
라벨로 본다 — M1의 목록이 볼 것 그대로다. 위험 1이 닫혔고 부팅 D
(`bootindex=0`)는 안 돌렸다. OVMF가 왜 그 순서인지는 안 캤다 — 이
QEMU 10.0.13 · Debian OVMF 조합에서 관측한 것이다.

### 실측 11 — 하네스 자체

부팅 셋이 콘솔 셸까지 5 · 4 · 5초, 측정 A가 11초(`uptime` 6.26→15.76).
설정 디스크에 쓴 로그를 QEMU를 죽인 직후 `debugfs`로 읽으면 비어 있었고
컨테이너가 끝난 뒤 읽으면 있었다 — Docker Desktop bind mount의 지연으로
본다. 시리얼 쪽이 완전하므로(A 79줄) 판정은 그쪽으로 했다.

## Milestone

| | 무엇 | 판정 |
|---|---|---|
| DI-M0 | 재는 것. 커널 옵션 다섯 · 패키지 셋과 딸려 온 라이브러리 · bzImage와 initrd 증가 · ISO 볼륨 ID. QEMU에서 손으로 `-cdrom` 매체가 ISO9660으로 붙고 빈 NVMe가 `sfdisk`·`mkfs.vfat`·`mke2fs`로 만들어지는 것까지 | 기존 열두 체인 회귀 없음. 실측이 이 문서에 적힌다 |
| DI-M1 | `tars-install`의 목록과 새 설치. `storage.zig`의 파티션 후보. `-V TARS`. 새 체인의 부팅 1 · 2 | `install/check.sh`가 `-cdrom` 없이 뜬 부팅에서 `config storage /dev/nvme0n1p2`를 본다 |
| DI-M2 | 갱신 경로(결정 8)와 부팅 3. README 실기 절에 설치 순서. `CHAINS`의 이름을 `DI-M2`로 | `di-marker`가 갱신을 넘는다. 루트 게이트 초록 |

첫 milestone이 재는 것인 것은 지금까지의 모양대로다.
