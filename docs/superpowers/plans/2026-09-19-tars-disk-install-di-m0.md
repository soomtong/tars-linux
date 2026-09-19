# DI-M0 — 설치기를 쓰기 전에 아홉을 재고, 손으로 한 번 설치해 본다

> 이 plan을 실행하는 사람에게: 이 milestone은 `tars-install`을 한 줄도 안
> 쓴다. 저장소에 들어가는 것은 셋이다 — 커널 옵션(`kernel/.config`) · sysroot
> 패키지(`devcontainer/Dockerfile`) · 게스트 도구 세 줄(`kernel/guest_tools.sh`).
> 그리고 design 문서의 실측 절 하나. 측정 하네스는 `/tmp/di/` 아래에만 산다.
> TS-M0 · IN-M0 · NW-M0의 plan과 같은 형식이고 TDD 구조가 아니다.

Goal: DI design의 확인 3 · 4 · 9와 위험 1 · 2 · 3 · 7을 부팅 셋과 컨테이너 명령
몇 줄로 답해서, DI-M1이 `install.zig`를 쓸 때 남아 있는 미지수를 없앤다.

Architecture: 커널에 파일시스템 둘과 CD-ROM 드라이버를 켜고, sysroot에 파티션·
포맷 도구 셋과 그 라이브러리를 들이고, 게스트 도구 목록에 셋을 더한 뒤 각각의
크기 증가를 잰다. 그 다음 OVMF로 ISO를 부팅해 콘솔 셸에 시리얼 FIFO로 명령을
넣어, 부팅 매체를 ISO9660으로 붙이고 빈 NVMe를 `sfdisk` · `mkfs.vfat` ·
`mke2fs`로 만들고 부트 파일 넷을 손으로 복사한다. 그 디스크로 `-cdrom` 없이
한 번, ISO와 함께 한 번 더 떠서 "USB 없이 뜨는가"와 "펌웨어가 무엇을 먼저
고르는가"를 본다. 게스트 쪽 측정 스크립트는 라벨 `tars-di`의 설정 디스크에
실어 `/config`에서 부른다 — 시리얼로 긴 명령을 치면서 따옴표를 세 겹으로
싸는 일을 안 하기 위해서다.

Tech Stack: bash · QEMU 10.0.11(OVMF · q35 · NVMe · virtio-blk) · util-linux
2.41(`sfdisk` · `blkid`) · dosfstools 4.2 · e2fsprogs 1.47 · 기존 빌드 스크립트
여섯(`kernel/build.sh` · `init/zig build` · `terminal/prepare.sh` ·
`kernel/make_initrd.sh` · `boot/build.sh` · `boot/make_iso.sh`)

---

## design과 달라진 것 둘, 넓힌 것 하나

plan을 쓰기 전에 고칠 자리의 소스를 읽었고 design이 못 본 것이 둘 나왔다.

1. 부팅 매체가 `/dev/sr0`로 보이려면 `CONFIG_BLK_DEV_SR`(SCSI CD-ROM)이
   있어야 하는데 `kernel/.config:1165`가 `# CONFIG_BLK_DEV_SR is not set`이다.
   `-cdrom`은 q35의 AHCI에 ATAPI 장치로 붙고 그것을 블록 장치로 만드는 것이
   `sr`이다 — `ATA` · `SATA_AHCI` · `SCSI`는 RM이 켰고 `sr` 하나가 없다.
   파일시스템 둘을 켜도 이것이 없으면 노드 자체가 안 생긴다. 그래서 켜는
   옵션이 design 결정 10의 다섯이 아니라 여섯이다.
2. design 확인 4가 "`blkid` · `lsblk` · `wipefs`는 sysroot에 있다"고 적었는데
   바이너리만 있다. `libblkid1` · `libsmartcols1` · `libmount1` · `libuuid1`
   넷 다 Dockerfile의 다운로드 목록에 없다(`util-linux:amd64`는 `dmesg` 하나
   때문에 받았고 `dmesg`는 libc만 부른다). `apt-get download`가 의존을 안
   따라가므로 라이브러리는 이름을 적어야 온다. 이 넷은 `sfdisk`가 어차피
   부르는 것이라 비용이 겹친다.

그리고 M0의 범위를 하나 넓힌다. design은 "위험 1(OVMF의 부팅 순서)은 재는
것으로 안 닫히고 M1의 첫 부팅이 닫는다"고 적었는데, 부팅 A에서 도구 셋을
손으로 돌린 뒤 `cp` 넉 줄만 더 치면 설치된 디스크가 생긴다. 그 디스크로
부팅을 둘 더 하면(`-cdrom` 없이 · ISO와 함께) 위험 1이 M0에서 답해지고
M1은 답을 알고 코드를 쓴다. 비용은 OVMF 부팅 둘(3분)이다.

하네스 전용으로 게스트에 `mount` · `umount` · `blkid` · `lsblk`를 싣는다.
저장소의 `guest_tools.sh`에는 안 들어간다(design 결정 5 — `tars-install`은
시스콜로 붙인다). `mount`는 `--rm` 컨테이너 안에서 그때만 sysroot에 풀고,
목록은 bind mount한 사본으로 덮는다(NW-M0이 `guest_tools.sh`에 쓴 수법).

## 무엇을 재는가

| 측정 | 무엇 | 어느 확인·위험 | 어디서 |
|---|---|---|---|
| 1 | 커널 옵션 여섯이 bzImage를 몇 바이트 키우는가, `olddefconfig`가 무엇을 딸려 오는가 | 결정 10 | Task 1 |
| 2 | 패키지 셋이 sysroot에 어떤 경로를 풀고 세 바이너리가 무엇을 부르는가 | 확인 4 · 위험 7 | Task 2 |
| 3 | 도구 셋이 initrd를 몇 바이트 키우고 새 라이브러리가 몇 개인가 | 위험 7 | Task 3 |
| 4 | ISO 볼륨 ID의 기본값 | 확인 9 | Task 4 |
| 5 | `-cdrom`이 `/dev/sr0`로 보이고 ISO9660(Rock Ridge)으로 붙는가 | 확인 3 | 부팅 A |
| 6 | `sfdisk` → `mkfs.vfat` → `mke2fs`가 되고 FAT 마운트가 codepage를 찾는가 | 확인 3 · 결정 3 | 부팅 A |
| 7 | `sfdisk` 뒤 파티션 노드가 언제 나타나는가 | 위험 2 | 부팅 A |
| 8 | 손으로 복사한 ESP에서 `-cdrom` 없이 뜨는가. `sync`가 얼마나 걸리는가 | 위험 3 | 부팅 B |
| 9 | ISO와 설치된 NVMe가 둘 다 있을 때 OVMF가 무엇을 먼저 고르는가 | 위험 1 | 부팅 C(·D) |

측정 9에 부팅 D가 조건부로 붙는다. C에서 OVMF가 NVMe를 골랐으면 처방 후보
하나(ISO 장치에 `bootindex=0`)를 그 자리에서 재 본다. OVMF가 QEMU의 부팅
순서를 읽는 길이 fw_cfg의 `bootorder`이고 그것을 채우는 것이 장치의
`bootindex`다 — design이 적은 `-boot order=d`는 SeaBIOS 쪽 문법이라 그 대신
이것을 잰다.

## 왜 부팅 셋인가

측정 5 · 6 · 7은 한 게스트에서 순서대로 답해진다. 8은 그 게스트가 만든
디스크로 다시 떠야 하고, 9는 그 디스크와 ISO를 함께 물려야 한다. 셋이
같은 디스크 이미지를 잇달아 쓰므로 하네스 하나가 셋을 차례로 띄운다.

## Task 0 — 기준선을 잰다

호스트(macOS)에서 친다. 이 Task가 끝나기 전에는 저장소를 한 글자도 안 고친다.

- [ ] Step 1: 디렉터리를 만든다

```bash
mkdir -p /tmp/di
ls -la /tmp/di
```

기대: 비어 있다. 이전 세션의 찌꺼기가 있으면 `rm -f /tmp/di/*`로 지운다.

- [ ] Step 2: 지금 HEAD의 산출물을 컨테이너에서 만든다 (약 1분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  (cd kernel && ./build.sh) && (cd init && zig build) &&
  (cd terminal && ./prepare.sh) && (cd kernel && ./make_initrd.sh) &&
  (cd boot && ./build.sh) && (cd boot && ./make_iso.sh)' 2>&1 | tail -5
```

기대: 첫 줄이 `kernel: bzImage matches .config and build.sh, skipping make`이고
마지막이 xorriso와 limine의 출력이다. 커널이 실제로 빌드되면 그것도 괜찮다 —
호스트의 `kernel/build`가 낡았던 것이다.

- [ ] Step 3: 세 산출물의 바이트 수를 적는다

```bash
stat -f '%N %z' kernel/build/arch/x86/boot/bzImage kernel/initrd.cpio out/tars.iso \
  | tee /tmp/di/baseline.txt
```

macOS의 `stat`은 `-f '%N %z'`다(GNU의 `-c '%n %s'`가 아니다). 이 세 수가 이
milestone의 "전"이다.

- [ ] Step 4: initrd의 파일 목록을 적어 둔다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  gzip -dc kernel/initrd.cpio | cpio -t 2>/dev/null | sort' > /tmp/di/initrd.before.txt
wc -l /tmp/di/initrd.before.txt
```

Task 3이 이 목록과의 차이로 "새로 들어온 파일"을 센다. `Installed-Size`가
아니라 이것이 우리가 치르는 비용이다(`project_measuring_tool_cost`).

- [ ] Step 5: `.config`가 `olddefconfig`의 고정점인지 본다

```bash
diff kernel/.config kernel/build/.config && echo "fixed point"
```

기대: `fixed point`. 차이가 있으면 Task 1 전에 되접기만 따로 커밋한다
(`project_kernel_config` — 정규화와 의도한 변경을 한 커밋에 섞지 않는다):

```bash
cp kernel/build/.config kernel/.config
git add kernel/.config
git commit -m "Record the settings the kernel is actually built with"
```

## Task 1 — 측정 1: 커널 옵션 여섯

`kernel/.config`만 고친다. 손으로 켜는 줄은 다섯이다 — `FAT_FS`는 Kconfig에
프롬프트가 없어서(`fs/fat/Kconfig:2-3`, `tristate` 뒤에 문자열이 없다) 우리가
적어도 `olddefconfig`가 지우고 `VFAT_FS`의 `select`가 도로 켠다.

- [ ] Step 1: 다섯 항목에 프롬프트가 있는지 Kconfig에서 본다

```bash
rg -n -A1 '^config (ISO9660_FS|VFAT_FS|BLK_DEV_SR)$' \
  kernel/src/linux-6.18.42/fs/isofs/Kconfig kernel/src/linux-6.18.42/fs/fat/Kconfig \
  kernel/src/linux-6.18.42/drivers/scsi/Kconfig
rg -n -A1 '^config (NLS_CODEPAGE_437|NLS_ISO8859_1)$' kernel/src/linux-6.18.42/fs/nls/Kconfig
```

기대: 다섯 다 다음 줄이 `tristate "..."`로 문자열이 붙어 있다. 프롬프트가
있는 항목만 `=y`가 남는다(`project_kernel_config`).

- [ ] Step 2: 다섯 줄을 켠다

```bash
for o in ISO9660_FS VFAT_FS NLS_CODEPAGE_437 NLS_ISO8859_1 BLK_DEV_SR; do
  sd "^# CONFIG_${o} is not set\$" "CONFIG_${o}=y" kernel/.config
done
rg -n 'CONFIG_(ISO9660_FS|VFAT_FS|NLS_CODEPAGE_437|NLS_ISO8859_1|BLK_DEV_SR)=' kernel/.config
```

기대: 다섯 줄이 `=y`로 나온다. 넷이나 여섯이면 `sd`의 패턴이 한 줄을 못
찾았거나 두 번 맞은 것이다 — `git diff kernel/.config`로 본다.

- [ ] Step 3: 빌드하고 시간을 잰다 (증분. NW-M0 기준 약 1분 05초)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash kernel/build.sh ; } > /tmp/di/build1.log 2> /tmp/di/build1.time
tail -3 /tmp/di/build1.time
tail -3 /tmp/di/build1.log
```

기대: `Kernel: arch/x86/boot/bzImage is ready`. 스탬프가 `.config`의 해시를
보므로 `skipping make`가 나오면 안 된다.

- [ ] Step 4: `olddefconfig`가 무엇을 딸려 왔는지 읽는다

```bash
diff kernel/.config kernel/build/.config | tee /tmp/di/config.diff
```

예상하는 것(정확한 줄은 실측이 답이다): `CONFIG_FAT_FS=y` ·
`CONFIG_FAT_DEFAULT_CODEPAGE=437` · `CONFIG_FAT_DEFAULT_IOCHARSET="iso8859-1"` ·
`# CONFIG_FAT_DEFAULT_UTF8 is not set` · `# CONFIG_JOLIET is not set` ·
`# CONFIG_ZISOFS is not set` · `CONFIG_CDROM=y`. 예상 밖의 줄이 있으면
design 실측에 그대로 적는다 — HD-M1 때 ACPI 하나가 `SERIAL_8250_PNP`를
바꿨듯 무관해 보이는 것이 움직인다.

`JOLIET`가 `not set`인 것이 맞다. `boot/make_iso.sh`가 `-J`를 주어 ISO에
Joliet 볼륨 서술자가 있지만 커널은 그것 없이 primary 서술자와 Rock Ridge로
긴 이름을 읽는다. 부팅 A의 측정 5가 그 이름(`limine.conf`가 `LIMINE.CON;1`이
아닌 것)을 직접 본다.

- [ ] Step 5: 되접고 다시 빌드해 고정점을 확인한다 (약 20초)

```bash
cp kernel/build/.config kernel/.config
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash kernel/build.sh 2>&1 | tail -2
diff kernel/.config kernel/build/.config && echo "fixed point"
```

기대: 둘째 빌드는 해시가 바뀌었으므로 `make`를 다시 돌리지만 고칠 오브젝트가
없어 빨리 끝나고, `diff`가 비어 `fixed point`가 찍힌다.

- [ ] Step 6: bzImage 증가를 잰다

```bash
stat -f '%N %z' kernel/build/arch/x86/boot/bzImage | tee -a /tmp/di/after.txt
grep bzImage /tmp/di/baseline.txt
```

두 수의 차가 측정 1이다. 바이트 그대로 적는다.

- [ ] Step 7: 더한 줄과 지운 줄을 따로 센다

```bash
git diff --stat
git diff kernel/.config | grep '^-' | grep -v '^---'
```

기대: 바뀐 파일이 `kernel/.config` 하나. 지운 줄은 Step 2의 `is not set`
다섯과 되접기가 옮긴 줄뿐이어야 한다. 그 밖의 `-` 줄이 있으면 무엇인지
읽고 실측에 적는다.

- [ ] Step 8: 커밋한다

```bash
git add kernel/.config
git commit -F - <<'EOF'
Let the kernel read the boot medium and write an EFI system partition

DI-M0. Six options, each for one thing the installer will do:

  BLK_DEV_SR        the boot ISO is an ATAPI device on q35's AHCI and a
                    USB stick is SCSI; without sr there is no /dev/sr0
  ISO9660_FS        read the boot medium. Rock Ridge comes with it, Joliet
                    stays off (the kernel does not need it for long names)
  VFAT_FS (+FAT_FS) mount the ESP to write bzImage and initrd.cpio into it
  NLS_CODEPAGE_437  FAT's default codepage; without it vfat mount fails
  NLS_ISO8859_1     FAT's default iocharset; same failure mode
EOF
```

## Task 2 — 측정 2: sysroot에 패키지 열하나

- [ ] Step 1: trixie에 그 이름들이 있는지 컨테이너에서 묻는다 (약 30초)

```bash
docker run --rm tars-devcontainer bash -c '
  dpkg --add-architecture amd64 >/dev/null; apt-get update -qq 2>/dev/null
  for p in fdisk dosfstools e2fsprogs libfdisk1 libmount1 libsmartcols1 \
           libblkid1 libuuid1 libreadline8t64 libext2fs2 libe2p2; do
    v=$(apt-cache policy "$p:amd64" | sed -n "s/^  Candidate: //p")
    echo "$p:amd64 -> ${v:-MISSING}"
  done'
```

기대: 열한 줄 모두 버전이 찍힌다. `MISSING`이 하나라도 있으면 그 이름이
trixie에서 다른 것이다 — `apt-cache search <이름 앞부분>`으로 찾아 아래
Step 2의 그 줄을 고친다. 이름에 버전이 박힌 것(`libreadline8t64`)이 그럴
가능성이 가장 크다.

- [ ] Step 2: Dockerfile을 고친다

`devcontainer/Dockerfile`의 두 자리다. 첫째, `ENV AMD64_SYSROOT=` 줄 바로 위
(TS-M3의 tzdata 주석 블록 뒤)에 이 블록을 더한다.

```dockerfile
#
# ── DI-M0: 층 7(디스크를 만드는 도구 셋) ──────────────────────────────
#
# tars-install이 fork+execve로 부르는 셋이다(DI design 결정 3). trixie에서
# sfdisk는 util-linux가 아니라 fdisk 패키지에 있다.
#
#   fdisk        sfdisk. GPT를 쓴다. 라이브러리 여섯을 끈다(design 위험 7)
#   dosfstools   mkfs.vfat. libc뿐
#   e2fsprogs    mke2fs 하나만 싣는다. libext2fs·libe2p·libcom-err(이미 있다)
#
# 아래 라이브러리 여덟은 apt가 저 셋의 Depends로 적은 것에서 이미 sysroot에
# 있는 것(libcom-err2 · libncursesw6 · libtinfo6)을 뺀 것이다. 실제로 initrd에
# 딸려 오는 수는 copy_lib_deps가 DT_NEEDED로 센 만큼이고 그 수는
# guest_tools.sh 층 7 주석에 있다.
#
# libblkid1 · libmount1 · libsmartcols1 · libuuid1이 지금까지 없었다는 것이
# DI-M0이 착수 전에 배운 것이다 — util-linux:amd64는 dmesg 하나 때문에
# 통째로 받았고, 그 안의 blkid·lsblk는 바이너리만 풀려 있었지 부를
# 라이브러리가 없어서 게스트에서 돌 수 없는 상태였다.
```

둘째, `apt-get download` 목록의 `libmnl0:amd64 \` 줄 다음, `tzdata) \` 줄
앞에 열한 줄을 더한다.

```dockerfile
        fdisk:amd64 \
        dosfstools:amd64 \
        e2fsprogs:amd64 \
        libfdisk1:amd64 \
        libmount1:amd64 \
        libsmartcols1:amd64 \
        libblkid1:amd64 \
        libuuid1:amd64 \
        libreadline8t64:amd64 \
        libext2fs2:amd64 \
        libe2p2:amd64 \
```

- [ ] Step 3: 더한 줄만 있는지 센다

```bash
git diff --stat
git diff devcontainer/Dockerfile | grep '^-' | grep -v '^---'
```

기대: 지운 줄 0. 순수 추가다.

- [ ] Step 4: 이미지를 다시 굽는다 (TS-M3 기준 약 50초, 다운로드가 있어 더 걸릴 수 있다)

```bash
{ time docker build -t tars-devcontainer devcontainer/ ; } \
  > /tmp/di/image.log 2> /tmp/di/image.time
tail -3 /tmp/di/image.time
grep -iE 'error|E: ' /tmp/di/image.log | head
```

기대: 시간 세 줄이 찍히고 `grep`이 비어 있다.

- [ ] Step 5: sysroot에 무엇이 어떤 경로로 풀렸는지 본다

```bash
docker run --rm tars-devcontainer bash -c '
  SR=/usr/local/amd64-sysroot
  echo "=== 세 바이너리의 자리 (심볼릭 링크면 -> 뒤에 실체) ==="
  ls -l $SR/usr/sbin/sfdisk $SR/usr/sbin/mkfs.vfat $SR/usr/sbin/mkfs.fat \
        $SR/usr/sbin/mke2fs $SR/usr/sbin/mkfs.ext2 2>&1
  echo "=== mke2fs가 읽는 설정 파일 ==="
  ls -l $SR/etc/mke2fs.conf 2>&1
  echo "=== 셋이 부르는 것 (DT_NEEDED, 재귀 전) ==="
  for b in usr/sbin/sfdisk usr/sbin/mkfs.fat usr/sbin/mke2fs; do
    echo "--- $b ($(stat -c %s $SR/$b) bytes)"
    readelf -d $SR/$b | sed -n "s/.*(NEEDED).*\[\(.*\)\]/  \1/p"
  done
  echo "=== 그 라이브러리들이 sysroot에 있나 ==="
  for so in libfdisk.so.1 libsmartcols.so.1 libmount.so.1 libblkid.so.1 libuuid.so.1 \
            libreadline.so.8 libtinfo.so.6 libext2fs.so.2 libcom_err.so.2 libe2p.so.2; do
    if [ -e $SR/usr/lib/x86_64-linux-gnu/$so ]; then echo "  있다   $so"; else echo "  없다   $so"; fi
  done'
```

기대: `mkfs.vfat -> mkfs.fat`, `mkfs.ext2 -> mke2fs`가 링크다. `install_tool`의
`cp`는 링크를 따라가 실체를 복사하므로 `guest_tools.sh`의 왼쪽에 링크 이름을
써도 된다. `없다`가 하나라도 있으면 그 라이브러리를 담은 패키지가 목록에
빠진 것이다 — `apt-file`이 없으므로 `apt-cache search <so 이름 앞부분>`으로
찾아 Step 2에 더하고 Step 4부터 다시 한다. `readelf`가 찍는 목록이
측정 2다 — 그대로 실측에 옮긴다.

- [ ] Step 6: 커밋한다

```bash
git add devcontainer/Dockerfile
git commit -m "Stock the sysroot with the three tools that make a disk bootable"
```

## Task 3 — 측정 3: 게스트 도구 셋과 initrd 증가

- [ ] Step 1: `kernel/guest_tools.sh`에 층 7을 더한다

배열의 닫는 `)` 바로 앞, `usr/bin/kill:usr/bin/kill` 줄 뒤에 이 블록을 넣는다.

```bash

  # ── 층 7 · 디스크를 만드는 도구 3 ─────────────────────────────────────
  # DI-M0. tars-install이 fork+execve로 부르는 셋이다(DI design 결정 3).
  # PATH가 /usr/bin:/bin이라(environ.zig) 셋 다 오른쪽을 /usr/bin에 둔다 —
  # dhcpcd가 층 5에서 같은 이유로 자리를 옮겼다.
  #
  # mkfs.vfat은 sysroot에서 mkfs.fat을 가리키는 링크다. install_tool의 cp가
  # 링크를 따라가 실체를 복사하므로 왼쪽에 링크 이름을 써도 되지만, 실체를
  # 적어 두는 것이 "이 파일은 어디서 왔나"에 한 번에 답한다(mawk→awk와
  # 같은 자리). mke2fs는 실체이고 mkfs.ext2가 그것을 가리키는 링크다.
  #
  # 새 라이브러리 수(DI-M0 실측. 푼 것 기준, Task 3 Step 3의 수로 고친다):
  #   sfdisk      (바이트)   새 라이브러리 (개)
  #   mkfs.fat    (바이트)   0개
  #   mke2fs      (바이트)   새 라이브러리 (개)
  usr/sbin/sfdisk:usr/bin/sfdisk
  usr/sbin/mkfs.fat:usr/bin/mkfs.vfat
  usr/sbin/mke2fs:usr/bin/mke2fs
```

괄호 안의 `(바이트)` · `(개)`는 Step 3의 수로 이 Task 안에서 채운다 — 커밋
전에 남아 있으면 안 된다.

- [ ] Step 2: initrd를 다시 만든다 (약 15초)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd kernel && ./make_initrd.sh' 2>&1 | tail -3
stat -f '%N %z' kernel/initrd.cpio | tee -a /tmp/di/after.txt
grep initrd /tmp/di/baseline.txt
```

기대: `make_initrd: cannot resolve` 없이 끝나고 cpio의 blocks 수가 찍힌다.
`cannot resolve <so>`로 죽으면 Task 2 Step 5에서 `없다`였던 것이고 그리로
돌아간다. 두 수의 차가 측정 3의 바이트다.

- [ ] Step 3: 새로 들어온 파일을 센다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  gzip -dc kernel/initrd.cpio | cpio -t 2>/dev/null | sort' > /tmp/di/initrd.after.txt
diff /tmp/di/initrd.before.txt /tmp/di/initrd.after.txt | grep '^>' | tee /tmp/di/initrd.new.txt
echo "new files: $(wc -l < /tmp/di/initrd.new.txt)"
docker run --rm -v "$PWD":/workspace -v /tmp/di:/tmp/di -w /workspace tars-devcontainer bash -c '
  mkdir -p /tmp/x && cd /tmp/x && gzip -dc /workspace/kernel/initrd.cpio | cpio -id 2>/dev/null
  total=0
  for f in $(sed "s/^> //" /tmp/di/initrd.new.txt); do
    s=$(stat -L -c %s "$f" 2>/dev/null || echo 0); total=$((total+s))
    printf "  %10d  %s\n" "$s" "$f"
  done; echo "  $total bytes unpacked"'
```

initrd를 풀어서 그 안의 파일을 재는 것은 "우리가 치르는 비용"이 initrd 안의
바이트이기 때문이다 — sysroot의 경로(`usr/sbin/sfdisk`)와 initrd의 경로
(`usr/bin/sfdisk`)가 다르므로 sysroot 쪽을 재면 이름을 되짚어야 한다.

기대: 셋(`usr/bin/sfdisk` · `usr/bin/mkfs.vfat` · `usr/bin/mke2fs`)과 라이브러리
몇 개(`lib/x86_64-linux-gnu/lib*.so.*`). 도구가 아닌 것이 섞여 있으면
`make_initrd.sh`의 다른 자리가 sysroot 변화에 반응한 것이다 — 무엇인지 읽고
실측에 적는다. `Step 1`의 주석 괄호를 이 수로 채운다(도구별 라이브러리 수는
Task 2 Step 5의 `readelf` 목록에서 "이미 있던 것"을 뺀 수다. `libcom_err.so.2`가
이미 있던 것이다).

- [ ] Step 4: 위험 7을 판단한다

새 라이브러리의 푼 크기 합이 3,000,000바이트를 넘으면 같은 방법으로 `sgdisk`를
잰다.

```bash
docker run --rm tars-devcontainer bash -c '
  dpkg --add-architecture amd64 >/dev/null; apt-get update -qq 2>/dev/null
  mkdir -p /tmp/w && cd /tmp/w && apt-get download -qq gdisk:amd64 >/dev/null 2>&1
  mkdir -p root; for d in *.deb; do dpkg -x "$d" root; done
  echo "sgdisk $(stat -c %s root/usr/sbin/sgdisk) bytes"
  readelf -d root/usr/sbin/sgdisk | sed -n "s/.*(NEEDED).*\[\(.*\)\]/  \1/p"'
```

두 수를 나란히 실측에 적고 어느 쪽을 쓸지는 사용자에게 묻는다 — design
결정 3이 "외부 도구"까지이고 어느 도구인지는 이 수가 정한다. 3,000,000을
안 넘으면 `sfdisk`로 가고 이 Step은 실측에 "재지 않았다, 합이 N이라"로 적는다.

- [ ] Step 5: `tools` 체인만 돌린다 (부팅 하나)

```bash
N_BEFORE=$(git show HEAD:kernel/guest_tools.sh | grep -cE '^\s+usr/')
N_AFTER=$(grep -cE '^\s+usr/' kernel/guest_tools.sh)
echo "list: ${N_BEFORE} -> ${N_AFTER}"
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh 2>&1 | tail -8
```

기대: `list:`의 두 수가 3 차이이고, 체인이 `the initrd carries the four bones
and all ${N_AFTER} tools the list names`와 `PASS`를 찍는다. 이 체인이
`guest_tools.sh`를 source해서 initrd 목록을 대조하므로 세 줄이 initrd에
실제로 들어갔는지를 여기서 본다.

- [ ] Step 6: 더한 줄과 지운 줄을 센다

```bash
git diff --stat
git diff kernel/guest_tools.sh | grep '^-' | grep -v '^---'
```

기대: 지운 줄 0. `(바이트)` · `(개)`가 남아 있지 않은지 `rg '\(바이트\)|\(개\)' kernel/guest_tools.sh`로 본다 — 비어야 한다.

- [ ] Step 7: 커밋한다

```bash
git add kernel/guest_tools.sh
git commit -m "Carry sfdisk, mkfs.vfat and mke2fs in the initrd"
```

## Task 4 — 측정 4: ISO 볼륨 ID의 기본값

부팅이 필요 없다. `make_iso.sh`는 Task 0 Step 2에서 이미 돌았지만 initrd가
바뀌었으므로 다시 굽는다.

- [ ] Step 1: ISO를 다시 굽고 볼륨 ID를 두 도구로 읽는다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  (cd boot && ./make_iso.sh) >/dev/null 2>&1
  echo "=== xorriso가 읽는 primary volume descriptor ==="
  xorriso -indev out/tars.iso -pvd_info 2>/dev/null | grep -E "Volume Id|Volume Set|Publisher|App Id"
  echo "=== blkid가 읽는 것 (게스트의 blkid와 같은 코드다) ==="
  blkid -p -o export out/tars.iso'
stat -f '%N %z' out/tars.iso | tee -a /tmp/di/after.txt
```

기대: `Volume Id`에 xorriso의 기본값(보통 `ISOIMAGE`)이 찍히고 `blkid`의
`LABEL=`이 같은 값이다. 그 값이 측정 4다. M1이 `-V TARS`를 주면 여기가
바뀐다.

## Task 5 — 하네스 전문

셋을 만든다. 게스트 쪽 측정 스크립트(설정 디스크에 실린다) · 하네스 전용
도구 목록(bind mount로 `guest_tools.sh`를 덮는다) · 컨테이너 쪽 하네스.

- [ ] Step 1: `/tmp/di/di-probe.sh`를 만든다

호스트에서 이 내용 그대로 쓴다. 게스트의 `/config/di-probe.sh`가 된다.

```bash
#!/bin/bash
# DI-M0의 게스트 쪽 측정. 라벨 tars-di의 설정 디스크에 실려 init이 /config에
# 붙이고, 콘솔 셸에서 `bash /config/di-probe.sh A`로 부른다.
#
# 시리얼로 명령을 한 줄씩 치지 않는 이유는 따옴표다 — bash 하네스 → fish →
# bash -c의 세 겹을 지나는 printf 한 줄이 읽히지 않는다. 파일로 실으면
# 게스트가 치는 것은 이 한 줄뿐이다.
#
# 모든 관측 줄은 DIM0-로 시작한다. p()가 시리얼(stdout)과 /config의 로그에
# 같은 줄을 쓴다 — 시리얼은 fish의 에코와 ANSI가 섞이고 /config 쪽은 깨끗하다.
# 하네스는 시리얼의 DIM0-<부팅>-END를 기다리고, 사람은 debugfs로 /config
# 쪽을 읽는다.
BOOT="${1:?boot name A/B/C/D}"
TARGET=/dev/nvme0n1
MEDIUM=/dev/sr0
OUT="/config/di-${BOOT}.log"
: > "$OUT"

p() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "$OUT"; }
ms() { echo $(( ($(date +%s%N) - $1) / 1000000 )); }

p "DIM0-${BOOT}-START uptime=$(cut -d' ' -f1 /proc/uptime)"
p "DIM0-${BOOT}-CMDLINE $(cat /proc/cmdline)"

if [ "$BOOT" != "A" ]; then
  # 부팅 B·C·D. 무엇으로 떴는지는 cmdline의 tars.di=esp가 말한다 — 부팅 A가
  # ESP에 복사한 limine.conf에만 그 글자가 있다.
  if grep -q 'tars.di=esp' /proc/cmdline; then
    p "DIM0-${BOOT}-BOOTED-FROM nvme-esp"
  else
    p "DIM0-${BOOT}-BOOTED-FROM iso"
  fi
  if [ -b "$MEDIUM" ]; then
    p "DIM0-${BOOT}-SR0 present $(blkid -p -o export $MEDIUM 2>&1 | grep -E '^(TYPE|LABEL)=' | tr '\n' ' ')"
  else
    p "DIM0-${BOOT}-SR0 absent"
  fi
  for part in p1 p2; do
    p "DIM0-${BOOT}-${part^^} $(blkid -p -o export ${TARGET}${part} 2>&1 | grep -E '^(TYPE|LABEL|PART_ENTRY_NAME)=' | tr '\n' ' ')"
  done
  p "DIM0-${BOOT}-END"
  exit 0
fi

# ── 부팅 A: 측정 5 · 6 · 7과 손 설치 ────────────────────────────────────

p "DIM0-FS $(grep -E 'iso9660|vfat|ext2' /proc/filesystems | tr -s '\t ' ' ' | tr '\n' ' ')"
for d in "$MEDIUM" "$TARGET"; do
  if [ -b "$d" ]; then p "DIM0-DEV $d present"; else p "DIM0-DEV $d MISSING"; fi
done
p "DIM0-DMESG-SR $(dmesg | grep -aE 'sr0|sr 0:|cdrom' | tail -3 | tr '\n' '|')"
p "DIM0-BLKID-SR $(blkid -p -o export $MEDIUM 2>&1 | tr '\n' ' ')"
p "DIM0-TARGET size=$(cat /sys/block/nvme0n1/size) sectors model=$(tr -d ' ' < /sys/block/nvme0n1/device/model 2>/dev/null) removable=$(cat /sys/block/nvme0n1/removable)"
p "DIM0-BLKID-TARGET-BEFORE [$(blkid -p -o export $TARGET 2>&1 | tr '\n' ' ')]"

# 측정 5. 매체를 ISO9660으로 붙이고 Rock Ridge 이름으로 넷을 찾는다.
mkdir -p /run/di/iso /run/di/esp
mount -t iso9660 -o ro "$MEDIUM" /run/di/iso
p "DIM0-ISOMOUNT rc=$?"
p "DIM0-ISOTOP $(ls /run/di/iso | tr '\n' ' ')"
p "DIM0-ISOFILES $(cd /run/di/iso && stat -c '%n=%s' boot/bzImage boot/initrd.cpio boot/limine/limine.conf EFI/BOOT/BOOTX64.EFI 2>&1 | tr '\n' ' ')"
p "DIM0-DMESG-ISO $(dmesg | grep -aiE 'iso9660|isofs' | tail -2 | tr '\n' '|')"

# 측정 6 · 7. GPT를 쓰고 노드가 나타나기까지를 100ms 단위로 센다 — sfdisk의
# BLKRRPART 뒤 devtmpfs가 p1·p2를 만드는 시간이다(design 위험 2).
printf 'label: gpt\nsize=256MiB, type=uefi, name=TARS-BOOT\nsize=1GiB, type=linux, name=TARS-CONFIG\n' > /run/di/layout
t0=$(date +%s%N)
sfdisk --wipe always "$TARGET" < /run/di/layout > /run/di/sfdisk.out 2>&1
p "DIM0-SFDISK rc=$? ms=$(ms $t0)"
polls=0
while [ $polls -lt 30 ]; do
  if [ -b "${TARGET}p1" ] && [ -b "${TARGET}p2" ]; then break; fi
  sleep 0.1; polls=$((polls + 1))
done
if [ $polls -lt 30 ]; then
  p "DIM0-PARTNODES present after ${polls} polls of 100ms"
else
  p "DIM0-PARTNODES MISSING after 3s"
fi
p "$(sed 's/^/DIM0-SFDISK-OUT /' /run/di/sfdisk.out)"
p "$(sfdisk --dump "$TARGET" 2>&1 | sed 's/^/DIM0-DUMP /')"

t0=$(date +%s%N)
mkfs.vfat -F 32 -n TARS-BOOT "${TARGET}p1" > /run/di/mkvfat.out 2>&1
p "DIM0-MKVFAT rc=$? ms=$(ms $t0)"
p "$(sed 's/^/DIM0-MKVFAT-OUT /' /run/di/mkvfat.out)"

# -q를 안 준다. /etc/mke2fs.conf가 initrd에 없을 때 mke2fs가 무슨 말을 하는지가
# 관측 대상이다 — 조용히 내장 기본값을 쓰는지, 경고를 찍는지.
t0=$(date +%s%N)
mke2fs -t ext2 -L tars-config "${TARGET}p2" > /run/di/mke2fs.out 2>&1
p "DIM0-MKE2FS rc=$? ms=$(ms $t0)"
p "$(sed 's/^/DIM0-MKE2FS-OUT /' /run/di/mke2fs.out)"
p "DIM0-MKE2FS-CONF $(grep -c 'mke2fs.conf' /run/di/mke2fs.out) lines mention mke2fs.conf"

p "DIM0-BLKID-P1 $(blkid -p -o export ${TARGET}p1 2>&1 | grep -E '^(TYPE|LABEL|PART_ENTRY_NAME|PART_ENTRY_TYPE)=' | tr '\n' ' ')"
p "DIM0-BLKID-P2 $(blkid -p -o export ${TARGET}p2 2>&1 | grep -E '^(TYPE|LABEL|PART_ENTRY_NAME|PART_ENTRY_TYPE)=' | tr '\n' ' ')"

# 측정 6의 나머지. vfat 마운트가 codepage 437과 iso8859-1을 찾는가 —
# 못 찾으면 mount가 EINVAL로 죽고 dmesg에 "codepage cp437 not found"가 남는다.
mount -t vfat "${TARGET}p1" /run/di/esp
p "DIM0-ESPMOUNT rc=$?"
p "DIM0-DMESG-FAT $(dmesg | grep -aiE 'codepage|iocharset|nls|FAT-fs' | tail -3 | tr '\n' '|')"

# 손 설치. 넷을 복사하되 limine.conf에만 표지를 남긴다 — 다음 부팅이 어느
# 볼륨에서 떴는지 cmdline으로 알기 위해서다. 설치기는 바이트 그대로 복사한다
# (design 확인 2). 이 표지는 이 측정만의 것이다.
mkdir -p /run/di/esp/boot/limine /run/di/esp/EFI/BOOT
t0=$(date +%s%N)
cp /run/di/iso/boot/bzImage /run/di/iso/boot/initrd.cpio /run/di/esp/boot/ &&
cp /run/di/iso/EFI/BOOT/BOOTX64.EFI /run/di/esp/EFI/BOOT/ &&
sed 's/console=ttyS0/console=ttyS0 tars.di=esp/' /run/di/iso/boot/limine/limine.conf \
  > /run/di/esp/boot/limine/limine.conf
p "DIM0-COPY rc=$? ms=$(ms $t0)"
t0=$(date +%s%N); sync; p "DIM0-SYNC ms=$(ms $t0)"
p "DIM0-ESPFILES $(cd /run/di/esp && stat -c '%n=%s' boot/bzImage boot/initrd.cpio boot/limine/limine.conf EFI/BOOT/BOOTX64.EFI 2>&1 | tr '\n' ' ')"
p "DIM0-MARKER $(grep -c 'tars.di=esp' /run/di/esp/boot/limine/limine.conf) line(s) carry the marker"
t0=$(date +%s%N); umount /run/di/esp; p "DIM0-ESPUMOUNT rc=$? ms=$(ms $t0)"
umount /run/di/iso; p "DIM0-ISOUMOUNT rc=$?"
p "DIM0-A-END uptime=$(cut -d' ' -f1 /proc/uptime)"
```

- [ ] Step 2: 문법을 본다

```bash
bash -n /tmp/di/di-probe.sh && echo "syntax ok"
```

- [ ] Step 3: 하네스 전용 도구 목록을 만든다

저장소의 `guest_tools.sh`에서 닫는 `)`를 떼고 넷을 붙인다. 저장소 파일은
안 건드린다.

```bash
sed '$d' kernel/guest_tools.sh > /tmp/di/guest_tools.sh
cat >> /tmp/di/guest_tools.sh <<'EOF'

  # ── DI-M0 하네스 전용. 저장소의 목록에는 안 들어간다(design 결정 5) ──
  usr/bin/mount:usr/bin/mount
  usr/bin/umount:usr/bin/umount
  usr/sbin/blkid:usr/bin/blkid
  usr/bin/lsblk:usr/bin/lsblk
)
EOF
tail -8 /tmp/di/guest_tools.sh
bash -n /tmp/di/guest_tools.sh && echo "syntax ok"
```

기대: 마지막 줄이 `)` 하나다. `sed '$d'`는 저장소 파일의 마지막 줄이 `)`라는
것에 기대고 있다 — `tail -1 kernel/guest_tools.sh`가 `)`가 아니면 그만큼
줄을 더 뗀다.

- [ ] Step 4: `/tmp/di/guest.sh`를 만든다

호스트에서 이 내용 그대로 쓴다. 컨테이너 안에서 돈다.

```bash
#!/usr/bin/env bash
# DI-M0 측정 5~9. 컨테이너 안에서 돈다.
#
# machine/check.sh의 QEMU 줄에서 -serial file과 -monitor tcp를 -serial stdio와
# -monitor none으로 바꾼 것이다(TS-M0 · IN-M0과 같다). 콘솔 셸에 FIFO로 명령을
# 넣으므로 USB 키보드는 안 친다 — 그래도 물려 둔다. i8042=off 기계에서 키보드가
# 하나도 없을 때 init이 어떻게 구는지는 이 측정의 관심사가 아니다.
#
# 부팅 셋(또는 넷)이 같은 NVMe 이미지를 잇달아 쓴다.
#   A  ISO + 빈 NVMe        매체를 붙이고 디스크를 만들고 넷을 복사한다
#   B  NVMe만               USB 없이 뜨는가(위험 3)
#   C  ISO + 설치된 NVMe    OVMF가 무엇을 먼저 고르는가(위험 1)
#   D  C + bootindex=0      C에서 NVMe를 골랐을 때만. 처방 후보 하나를 잰다
set -uo pipefail
cd /workspace

DI=/tmp/di
SR=/usr/local/amd64-sysroot
DISK=$DI/target.img       # 2GiB 빈 NVMe. 매 실행 새로 만든다
SEED=$DI/seed.img         # 라벨 tars-di. di-probe.sh를 싣는다
OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd

rm -f "$DI"/guest-*.log "$DI"/guest-*.fifo "$DISK" "$SEED"

# ── 하네스 전용 mount를 sysroot에 푼다 ────────────────────────────────
# 이 컨테이너는 --rm이라 이미지에는 안 남는다. 게스트의 mount는 이 측정에만
# 있고 tars-install은 시스콜로 붙인다(design 결정 5).
mkdir -p /tmp/debs && (cd /tmp/debs &&
  dpkg --add-architecture amd64 >/dev/null &&
  apt-get update -qq 2>/dev/null &&
  apt-get download -qq mount:amd64 >/dev/null 2>&1 &&
  for d in *.deb; do dpkg -x "$d" "$SR"; done) || {
  echo "DIM0: could not fetch mount:amd64 into the sysroot"; exit 1; }
ls -l "$SR/usr/bin/mount" "$SR/usr/bin/umount" || { echo "DIM0: mount is not where expected"; exit 1; }
echo "DIM0: harness-only mount unpacked into the sysroot"

# ── 빌드 ──────────────────────────────────────────────────────────────
# kernel/guest_tools.sh는 docker run의 bind mount로 /tmp/di/guest_tools.sh가
# 덮고 있다. 그래서 이 initrd에는 mount·umount·blkid·lsblk가 있다.
(cd kernel && ./build.sh)       || { echo "DIM0: kernel build failed"; exit 1; }
(cd init && zig build)          || { echo "DIM0: init build failed"; exit 1; }
(cd terminal && ./prepare.sh)   || { echo "DIM0: terminal build failed"; exit 1; }
(cd kernel && ./make_initrd.sh) || { echo "DIM0: initrd build failed"; exit 1; }
(cd boot && ./build.sh)         || { echo "DIM0: limine fetch failed"; exit 1; }
(cd boot && ./make_iso.sh)      || { echo "DIM0: iso build failed"; exit 1; }
gzip -dc kernel/initrd.cpio | cpio -t 2>/dev/null | grep -cE 'usr/bin/(mount|umount|blkid|lsblk)$' \
  | sed 's/^/DIM0: harness tools in initrd: /'

# ── 디스크 둘 ─────────────────────────────────────────────────────────
truncate -s 2G "$DISK"
STAGE="$(mktemp -d)"
cat > "$STAGE/tars.conf" <<'EOF'
# DI-M0 하네스의 설정 디스크. di-probe.sh를 게스트에 실어 나르는 것이 전부다.
EOF
cp "$DI/di-probe.sh" "$STAGE/di-probe.sh"
dd if=/dev/zero of="$SEED" bs=1M count=8 status=none
mkfs.ext2 -F -q -m 0 -L tars-di -d "$STAGE" "$SEED"
rm -rf "$STAGE"
echo "DIM0: target $(stat -c %s "$DISK") bytes, seed labelled tars-di"

[ -f "$OVMF_CODE" ] || { echo "DIM0: $OVMF_CODE missing"; exit 1; }

QEMU_PID=""
LOG=""
FIFO=""
cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null; wait "$QEMU_PID" 2>/dev/null
  fi
  exec 4>&- 2>/dev/null
  [ -n "$FIFO" ] && rm -f "$FIFO"
}
trap cleanup EXIT

# boot_guest <이름> [qemu 인자...]. 콘솔 셸까지 기다린다. 0이면 셸이 떴다.
boot_guest() {
  local name="$1"; shift
  LOG="$DI/guest-${name}.log"
  FIFO="$DI/guest-${name}.fifo"
  local vars; vars="$(mktemp)"
  cp /usr/share/OVMF/OVMF_VARS_4M.fd "$vars"
  rm -f "$FIFO"; mkfifo "$FIFO"
  exec 4<>"$FIFO"
  qemu-system-x86_64 \
    -machine q35,i8042=off \
    -m 512 \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,unit=1,file="$vars" \
    -device qemu-xhci,id=xhci \
    -device usb-kbd,bus=xhci.0 \
    -drive file="$DISK",if=none,id=target,format=raw \
    -device nvme,drive=target,serial=tarstarget \
    -drive file="$SEED",if=virtio,format=raw \
    "$@" \
    -serial stdio \
    -monitor none \
    -display none \
    -no-reboot \
    < "$FIFO" > "$LOG" 2>&1 &
  QEMU_PID=$!
  sleep 2
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    echo "DIM0: boot ${name}: qemu died at startup"; cat "$LOG"; return 1
  fi
  local waited=0
  while [ "$waited" -lt 180 ]; do
    if grep -aq "started console shell" "$LOG" 2>/dev/null; then break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1; waited=$((waited + 1))
  done
  if ! grep -aq "started console shell" "$LOG" 2>/dev/null; then
    echo "DIM0: boot ${name}: console shell never started (${waited}s)"
    sed -e 's/\x1b\[[0-9;=?]*[a-zA-Z]//g' "$LOG" | grep -aE 'PANIC|panic|efi: EFI|Shell>|tars-init' | head -12
    return 1
  fi
  echo "DIM0: boot ${name}: console shell up after ${waited}s"
  echo "DIM0: boot ${name}: firmware $(grep -a 'efi: EFI v' "$LOG" | head -1 | sed 's/.*efi: //')"
  echo "DIM0: boot ${name}: config $(grep -a 'tars-init: config storage' "$LOG" | head -1 | sed 's/.*tars-init: //')"
  sleep 3
  return 0
}

# 셸에 한 줄 넣고 표지가 나올 때까지 기다린다. 0이면 나왔다.
run_probe() {
  local name="$1" limit="${2:-240}" i
  printf 'bash /config/di-probe.sh %s\n' "$name" >&4
  for i in $(seq 1 "$limit"); do
    if grep -aq "DIM0-${name}-END" "$LOG"; then
      echo "DIM0: boot ${name}: probe finished after ${i}s"; return 0
    fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
      echo "DIM0: boot ${name}: qemu died during the probe"; return 1
    fi
    sleep 1
  done
  echo "DIM0: boot ${name}: probe never printed DIM0-${name}-END (${limit}s)"
  return 1
}

stop_guest() {
  kill "$QEMU_PID" 2>/dev/null; wait "$QEMU_PID" 2>/dev/null; QEMU_PID=""
  exec 4>&-; rm -f "$FIFO"; FIFO=""
}

# 부팅 뒤 /config에 쓰인 깨끗한 로그를 seed.img에서 꺼낸다.
dump_probe() {
  echo "=== probe ${1} (from the config disk) ==="
  debugfs -R "cat di-${1}.log" "$SEED" 2>/dev/null
}

echo "=== boot A: ISO + blank NVMe ==="
boot_guest A -cdrom out/tars.iso || exit 1
run_probe A 300
stop_guest
dump_probe A

echo "=== boot B: the NVMe alone ==="
boot_guest B || { echo "DIM0: boot B did not reach the shell — the hand-made ESP does not boot"; exit 1; }
run_probe B 60
stop_guest
dump_probe B

echo "=== boot C: ISO + the installed NVMe ==="
boot_guest C -cdrom out/tars.iso || exit 1
run_probe C 60
stop_guest
dump_probe C

if debugfs -R "cat di-C.log" "$SEED" 2>/dev/null | grep -q 'BOOTED-FROM nvme-esp'; then
  echo "=== boot D: same, with bootindex=0 on the ISO ==="
  boot_guest D \
    -drive file=out/tars.iso,if=none,id=cd,media=cdrom,format=raw \
    -device ide-cd,drive=cd,bootindex=0 || exit 1
  run_probe D 60
  stop_guest
  dump_probe D
else
  echo "DIM0: boot C came up from the ISO — boot D is not needed"
fi

echo "=== done ==="
```

- [ ] Step 5: 문법을 보고 실행 권한을 준다

```bash
bash -n /tmp/di/guest.sh && echo "syntax ok"
chmod +x /tmp/di/guest.sh /tmp/di/di-probe.sh
```

## Task 6 — 하네스를 돌린다

- [ ] Step 1: 돌린다 (부팅 셋이면 약 8분, 넷이면 약 10분)

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/di:/tmp/di \
  -v /tmp/di/guest_tools.sh:/workspace/kernel/guest_tools.sh:ro \
  -w /workspace tars-devcontainer bash /tmp/di/guest.sh > /tmp/di/run.log 2>&1
echo "exit=$?"
```

10분이 Bash 도구의 한도라 `run_in_background`로 돌린다.

- [ ] Step 2: 컨테이너 쪽 관찰을 본다

```bash
grep -E "^DIM0:|^=== " /tmp/di/run.log
```

기대: `harness tools in initrd: 4` · 부팅마다 `console shell up` · `probe
finished` · 마지막에 `=== done ===`. `qemu died`나 `never`가 있으면 Step 5로.

- [ ] Step 3: 게스트 쪽 관찰을 본다 — 깨끗한 쪽

```bash
sed -n '/^=== probe A/,/^=== boot B/p' /tmp/di/run.log
sed -n '/^=== probe B/,/^=== boot C/p' /tmp/di/run.log
sed -n '/^=== probe C/,$p' /tmp/di/run.log
```

- [ ] Step 4: 시리얼 로그도 걷어서 둔다

```bash
for b in A B C D; do
  [ -f /tmp/di/guest-$b.log ] || continue
  perl -pe 's/\e\][^\a\e]*(\a|\e\\)//g; s/\e\[[0-9;?>=]*[a-zA-Z]//g;
            s/\e[()][AB0]//g; s/\r/\n/g' /tmp/di/guest-$b.log > /tmp/di/guest-$b.clean
  echo "--- $b: $(grep -ac 'DIM0-' /tmp/di/guest-$b.clean) DIM0 lines, $(grep -ac 'terminal: screen>' /tmp/di/guest-$b.clean) screens"
done
```

`/config` 쪽 로그가 비어 있을 때(스크립트가 중간에 죽었을 때) 시리얼 쪽이
어디까지 갔는지를 말해 준다.

- [ ] Step 5: 실패한 자리가 있으면 원본을 직접 본다

```bash
grep -anE 'DIM0-|tars-init|PANIC|Kernel panic|Shell>' /tmp/di/guest-A.clean | head -60
```

## Task 7 — 관측을 판정으로 바꾼다

표지 하나하나가 무엇을 뜻하는지다. 표대로 읽고 갈린 자리는 실측에 적는다.

| 표지 | 초록 | 빨강이면 |
|---|---|---|
| `DIM0-FS` | `iso9660 vfat ext2` 셋 | 빠진 것은 Task 1의 옵션이 안 들어간 것. `kernel/build/.config`를 본다 |
| `DIM0-DEV /dev/sr0 present` | 있다 | `BLK_DEV_SR`이 안 켜졌거나 `-cdrom`이 AHCI에 안 붙었다. `DIM0-DMESG-SR`에 `sr 0:0:0:0`이 있는지 |
| `DIM0-BLKID-SR` | `TYPE=iso9660 LABEL=<Task 4의 값>` | 노드는 있는데 읽히지 않는다. dmesg의 `sr0` 줄 |
| `DIM0-ISOMOUNT rc=0` · `DIM0-ISOFILES` 넷의 크기가 Task 0의 수와 같다 | 확인 3의 ISO 쪽이 닫혔다 | `rc=32`면 `DIM0-DMESG-ISO`. 이름이 `LIMINE.CON;1`이면 Rock Ridge를 못 읽은 것 |
| `DIM0-SFDISK rc=0` · `DIM0-DUMP`에 `type=C12A7328-...`(EFI)와 `0FC63DAF-...`(Linux), `name="TARS-BOOT"` | 결정 3의 스크립트 세 줄이 그대로 먹는다 | `DIM0-SFDISK-OUT`이 답이다. `type=uefi` 별칭을 모르면 GUID를 직접 쓴다 |
| `DIM0-PARTNODES present after N polls` | 위험 2의 수. N이 0이면 즉시 | `MISSING`이면 위험 2가 현실이고 M1의 기다림 상한을 늘린다 |
| `DIM0-MKVFAT rc=0` · `DIM0-BLKID-P1`에 `TYPE=vfat LABEL=TARS-BOOT` | | |
| `DIM0-MKE2FS rc=0` · `DIM0-BLKID-P2`에 `TYPE=ext2 LABEL=tars-config` · `DIM0-MKE2FS-CONF 0 lines` | 설정 파일 없이 조용하다 | `mke2fs.conf`를 언급하면 M1이 `etc/mke2fs.conf`를 initrd에 싣거나 `-t ext2`를 빼는 것을 정한다 |
| `DIM0-ESPMOUNT rc=0` | 확인 3의 FAT 쪽이 닫혔다. NLS 둘이 든 것 | `rc=32`와 `DIM0-DMESG-FAT`의 `codepage cp437 not found`면 NLS가 빠진 것 |
| `DIM0-COPY rc=0` · `DIM0-SYNC ms=` · `DIM0-ESPUMOUNT rc=0 ms=` | 위험 3의 수 둘. `cp`가 빨리 돌아오고 `sync`가 비용을 치르는지 | |
| `DIM0-B-BOOTED-FROM nvme-esp` · 부팅 B의 `firmware EFI v` | USB 없이 뜬다. 위험 3이 닫혔다 — 캐시에만 있었으면 이 부팅이 없다 | 부팅 B가 셸까지 못 오면 하네스가 거기서 멈추고 `Shell>`(EFI 셸)이나 limine `PANIC`을 찍는다 |
| 부팅 B의 `config` 줄이 `/dev/vda (label tars-di)` | `init`이 아직 파티션을 안 보므로 p2를 못 잡는 것이 맞다(결정 6은 M1) | `nvme0n1p2`가 잡히면 `storage.zig`를 누가 이미 고친 것이다 |
| `DIM0-C-BOOTED-FROM iso` | 위험 1이 닫혔다. OVMF가 CD를 먼저 고른다 | `nvme-esp`면 위험 1이 현실이다. 부팅 D를 본다 |
| `DIM0-D-BOOTED-FROM iso` | 처방은 `bootindex=0`이고 M1의 체인이 그것을 쓴다 | D도 `nvme-esp`면 처방 후보가 OVMF_VARS 쪽으로 넘어간다. 사용자에게 보고하고 M1 design을 고친다 |
| `DIM0-C-SR0 present` · `DIM0-C-P2`에 `LABEL=tars-config` | 부팅 C의 게스트가 매체와 설치된 디스크를 둘 다 본다 — M1의 목록이 볼 것 | |

- [ ] Step 1: 표대로 읽고 갈린 자리를 `/tmp/di/verdict.txt`에 적는다

```bash
{
  echo "boot A:"; grep -E 'DIM0-(FS|DEV|ISOMOUNT|SFDISK rc|PARTNODES|MKVFAT rc|MKE2FS rc|MKE2FS-CONF|ESPMOUNT|COPY|SYNC|ESPUMOUNT)' /tmp/di/run.log
  echo "boot B/C/D:"; grep -E 'DIM0-[BCD]-(BOOTED-FROM|SR0|P1|P2)' /tmp/di/run.log
} | tee /tmp/di/verdict.txt
```

- [ ] Step 2: initrd를 저장소의 목록으로 되돌린다

하네스가 `kernel/initrd.cpio`를 하네스 전용 목록으로 만들어 두었다. 게이트는
체인마다 `make_initrd.sh`를 다시 돌리므로 어차피 덮이지만, 지금 이 파일로
무언가를 재면 넷이 섞인다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd kernel && ./make_initrd.sh && cd ../boot && ./make_iso.sh' 2>&1 | tail -2
stat -f '%N %z' kernel/initrd.cpio
```

기대: Task 3 Step 2의 바이트 수와 같다.

## Task 8 — 회귀 없음: 루트 게이트

- [ ] Step 1: 돌린다 (열두 체인 3/3, TS-M3 뒤 32분 58초)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } > /tmp/di/gate.log 2> /tmp/di/gate.time
```

Bash 도구의 10분 한도를 넘으므로 `run_in_background`로 돌린다.

- [ ] Step 2: 결과를 본다

```bash
tail -5 /tmp/di/gate.log; tail -3 /tmp/di/gate.time
grep -c PASS /tmp/di/gate.log
```

기대: 열두 체인 3/3. 커널이 바뀌었으므로 첫 회차가 진짜로 빌드하고(GL-M1)
그 뒤는 `skipping make`다. 빨강이 있으면 그 체인을 단독으로 돌려 시리얼
로그를 꺼내 본다(HANDOFF 명령 모음의 "그 체인이 실패했을 때").

## Task 9 — design에 실측을 적고 커밋한다

- [ ] Step 1: design에 절을 더한다

`docs/superpowers/specs/2026-09-19-tars-disk-install-design.md`의 "## Milestone"
바로 앞에 절을 더한다.

```markdown
## DI-M0이 실행으로 증명한 것

(실측 1부터 번호를 매긴다. 각 실측은 "무엇을 했고 무엇이 나왔고 그래서
무엇이 정해졌나"를 적는다. 숫자는 로그에서 그대로 옮긴다 — 반올림하거나
"약"으로 쓰지 않는다.)
```

적을 것이 최소 아홉이다 — 측정 1~9 각각 하나씩. 그리고 plan에 없던 것.
착수 전에 이미 둘이 나왔다(`BLK_DEV_SR` · 라이브러리 넷의 부재) — 그 둘도
실측으로 적고, 확인 3과 확인 4의 문단 끝에 `⚠ DI-M0이 고쳤다(실측 N).`을
붙인다. TS-M0은 여섯을 재고 plan에 없던 것을 더 적었다.

- [ ] Step 2: design의 결정 10과 위험 절을 고친다

결정 10의 제목을 "커널 옵션 여섯을 켠다"로 바꾸고 `BLK_DEV_SR`을 목록에
더한다. 닫힌 위험에는 `DI-M0이 닫았다(실측 N).`을, 현실이 된 위험에는
`⚠ 현실이 됐다(실측 N).`과 무엇이 바뀌었는지를 적는다. 위험 1은 부팅 C의
답과 (D를 돌렸으면) 처방을 적고, milestone 표의 M1 판정 줄에서 "위험 1은
M1의 첫 부팅이 닫는다"를 지운다.

- [ ] Step 3: `Status:` 줄을 고친다

```
Status: 열렸다(2026-09-19). M0이 끝났다(<날짜>) — 실측 절에 있다. M1은 plan부터.
```

- [ ] Step 4: 더한 줄과 지운 줄을 따로 센다

```bash
git diff --stat
git diff | grep '^-' | grep -v '^---'
```

기대: design 문서 하나. 지운 줄은 결정 10의 제목 · 위험 1의 "M1의 첫 부팅이
닫는다" 문장 · `Status:` 줄뿐이다.

- [ ] Step 5: 커밋한다

```bash
git add docs/superpowers/specs/2026-09-19-tars-disk-install-design.md \
        docs/superpowers/plans/2026-09-19-tars-disk-install-di-m0.md
git commit -m "Measure what installing to a disk will need"
```

## Task 10 — HANDOFF를 갱신한다

`handoff` 스킬로 `HANDOFF.md`를 고친다. 담을 것 다섯이다.

- "지금 어디인가": DI-M0이 끝났고 M1의 plan이 없다. 위험 1의 답(부팅 C·D).
- "DI가 한 일": M0 문단. 커밋 넷(`.config` · Dockerfile · `guest_tools.sh` ·
  design)과 수 셋(bzImage · initrd · 새 라이브러리).
- "⚠ M0이 이미지를 다시 구웠다" — TS-M3과 같은 경고. 새로 받은 사람은
  `docker build`부터.
- "명령 모음": Task 6 Step 1의 하네스 한 줄과 Step 3의 읽는 법. 하네스
  전문은 이 plan의 Task 5에 있다고 가리킨다.
- "게이트 현황": Task 8의 시각과 직전 값과의 차.

## 이 milestone이 끝난 자리

- `/tmp/di/`의 하네스 셋(`di-probe.sh` · `guest_tools.sh` · `guest.sh`)과 로그
  (`run.log` · `guest-A..D.log` · `.clean` · `verdict.txt` · `baseline.txt` ·
  `after.txt` · `initrd.*.txt` · `config.diff`). 호스트 `/tmp`라 언젠가
  사라지고, 다시 필요하면 이 plan의 Task 5에 전문이 글자 그대로 있다.
- 저장소에 커밋 넷: 커널 옵션 여섯 · sysroot 패키지 열하나 · 게스트 도구
  셋 · design의 실측 절.
- `tars-install`은 없다. `install/check.sh`도 없다. `storage.zig`도 그대로다.

끝 기준: 측정 아홉이 다 답해져 design에 실측으로 적혔고, 부팅 B가 `-cdrom`
없이 셸까지 왔고, 위험 1의 답이 예(ISO 먼저)이거나 `bootindex=0`으로 우회할
길이 정해졌고, 루트 게이트가 열두 체인 3/3이다.
