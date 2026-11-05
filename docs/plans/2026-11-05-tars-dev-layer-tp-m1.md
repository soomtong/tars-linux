# TP-M1 — 커널 · init · ISO · 설치기 · 체인 `devtools`

> 2026-11-05, `4fb06a3` 기준. 줄 번호는 낡을 수 있다. 결과는 끝의 "결과" 절(구현 뒤 채운다).

Goal: TP design 결정 8~13. TP-M0이 구운 `base.sqfs` · `lang-jvm.sqfs`를 ISO가 싣고, `tars-install`이 p3로 옮기고, init이
부팅마다 loop · squashfs로 열어 `/usr` 위에 읽기 전용 overlay로 얹는다. 망 없는 게스트에서 사용자로 `gcc` · `make` · `javac` ·
`java` · `jwebserver`가 돈다(판정 TP-M1). 묶음이 없거나 깨진 부팅은 지금과 같다.

## 착수 전 확인 (2026-11-05, `4fb06a3`)

1. 커널 `.config`의 임시 사본에 `scripts/config -e BLK_DEV_LOOP -e OVERLAY_FS -e MISC_FILESYSTEMS -e SQUASHFS -e
   SQUASHFS_ZSTD` → `olddefconfig`(개발 컨테이너)을 하면 따라 켜지는 것은 `BLK_DEV_LOOP_MIN_COUNT=8` · `FS_STACK` ·
   `OVERLAY_FS_REDIRECT_ALWAYS_FOLLOW` · `SQUASHFS_FILE_CACHE` · `SQUASHFS_DECOMP_SINGLE` · `SQUASHFS_ZLIB`(기본 y)다.
   `SQUASHFS`는 `MISC_FILESYSTEMS` 메뉴 안이라 그것 없이는 줄조차 안 생긴다(design 확인 4의 "줄이 없다"가 이것이다).
   `MISC_FILESYSTEMS` 밑의 다른 파일시스템은 모두 꺼진 채다. diff에 `# CONFIG_X86_CPU_RESCTRL is not set` 한 줄이 더
   나왔다 — 지금 `.config`가 `olddefconfig`의 결과로 정규화되어 있지 않았던 흔적이다(`build.sh`가 매번 `olddefconfig`를 돌리므로
   빌드는 같다).
2. 음성 검사: `rg -n 'BLK_DEV_LOOP|OVERLAY_FS|SQUASHFS' */check.sh docs/guides`가 비었다(LP 배운 것 1).
3. 구운 두 묶음은 `unsquashfs -s`로 `Number of xattr ids 0`이다. `SQUASHFS_XATTR`를 꺼 둔 채로 둔다.
4. init의 순서(`main.zig`): `mountEarly` → `readConfig`(`mountConfig` → `mountHome` → `loadConfig` → seed → `pickUser`) →
   `probeDevices` → `buildEnv` → `startHelpers` → `placeChildren`. 결정 9의 자리("`/home`을 붙인 직후, 셸과 서비스를 띄우기
   전")는 `mountHome()` 바로 뒤다. `/`는 rootfs(ramfs)이고 `/etc`는 그 안의 디렉터리다. 따로 붙인 tmpfs가 아니다.
5. `tars-install`의 갱신은 지금 p3를 열지 않고 계획에 `p3 (tars-home) <- not opened`를 찍는다(HP design 결정 10). 그 글자를
   `disk_test.zig`의 `UPDATE_TAIL`과 `dualboot/check.sh`가 본다. 새 설치는 `writeAccount`가 p3를 `/tmp/tars-install/home`에
   붙였다 뗀다.
6. 게이트(`check.sh`)는 개발 컨테이너 안에서 돈다. amd64 거두기(`devlayer/harvest.sh`)는 거기서 못 돈다. 받기 · 검사 ·
   굽기(`devlayer/build.sh`)는 돈다. 거두기 tar(`devlayer/build/base.harvest.tar`, 204MiB)와 JDK tarball은 `out/` 밖이라
   `clean()`을 넘어 남는다.
7. 묶음 안의 버전 줄(`usr/share/tars/layers/<묶음>`, `git describe`)은 stamp에 안 든다. 그래서 묶음은 커밋을 넘어 캐시되고, 그
   줄은 ISO의 init 버전과 거의 늘 다르다 — 결정 E.
8. monitor 포트는 45503(sleep)까지 쓰였다. 45504가 비어 있다.

## 결정 (이 plan이 정한다 — 뒤집을 것이 있으면 글자로)

A. 커널은 다섯 심볼을 켜고 `olddefconfig`의 결과를 그대로 커밋한다(확인 1의 정규화 줄 포함). `SQUASHFS_ZLIB`는 기본값대로
   둔다. 끄면 줄 하나가 더 늘고, 켜 두면 gzip 이미지도 열린다. bzImage 크기 차이를 결과에 적는다.
B. 묶음의 자리: p3 `/.tars/layers/<묶음>.sqfs`(게스트에서 `/home/.tars/layers/`), 그 옆에 `version` 한 줄. 디렉터리는
   root 0755, 파일은 root 0644. `.tars`는 점으로 시작해서 사용자 이름이 될 수 없다(`account`의 이름 규칙).
C. init(`init/src/layers.zig` 새 파일, 순수한 부분은 `layers_test.zig`):
   1. `/home`이 붙었을 때만 본다. `/home/.tars/layers`가 없으면 `tars-init: layers: none in /home/.tars/layers` 한 줄로
      끝난다(판정의 "layer 줄").
   2. `version`을 읽어 init의 `build_info.version`과 비교한다(결정 E). 다르거나 없으면 `tars-init: layers: built for <X>,
      this image is <Y>`(없으면 `no version file`) 한 줄로 아무것도 안 얹는다.
   3. `getdents64`로 `*.sqfs`를 이름 순으로 모은다(최대 16, 이름은 `[a-z0-9-]`만 — 그 밖은 `layer <파일>: bad name`).
   4. 묶음마다: `/dev/loop-control`에 `LOOP_CTL_GET_FREE` → `/dev/loopN`을 열어 `LOOP_CONFIGURE`(fd, `LO_FLAGS_READ_ONLY |
      LO_FLAGS_AUTOCLEAR`) → `/run/tars-layers/<이름>`에 `squashfs`, `MS_RDONLY | MS_NOSUID | MS_NODEV`. 실패한 단계는
      `tars-init: layer <이름>: <단계> failed (errno N)` 한 줄을 남기고 다음 묶음으로 간다(design 결정 11). loop를 열었는데
      mount가 실패하면 그 loop를 `LOOP_CLR_FD`로 푼다.
   5. 하나 이상 섰으면 `overlay`를 `/usr`에 `MS_RDONLY`, `lowerdir=/usr:/run/tars-layers/<a>/usr:…`로 얹는다. `/usr`(initrd)를 맨
      위에 둔다 — design 결정 9는 묶음들을 앞에 적었지만, 이 순서여야 결정 4("initrd가 이긴다")가 빌드 검사가 놓친 경우에도
      런타임에서 지켜진다. M0의 검사가 겹친 파일을 이미 뺐으므로 보통의 결과는 같다. upper가 없어 `/usr`는 읽기 전용이다.
      성공하면 `tars-init: overlay /usr from N layers in Mms`.
   6. 결정 10: overlay가 선 뒤, 선 묶음마다 `etc/` 아래 보통 파일을 `/etc`의 같은 자리로 복사한다(디렉터리는 만들고, 이미 있는
      파일은 안 덮는다 — initrd가 이긴다, `O_EXCL`). 링크 · 장치는 싣지 않고 `layer <이름>: etc/<경로> skipped`. 깊이는 8까지.
      base의 `etc/gprofng.rc` 하나가 지금의 대상이다.
   7. overlay가 실패하면 붙인 묶음을 모두 떼고 `tars-init: overlay /usr failed (errno N)` — 지금과 같은 부팅이다.
D. 설치기(`install.zig`, 계획 줄은 `disk.zig`):
   1. 매체에 `boot/layers/*.sqfs`가 있을 때만 개발 도구 층을 다룬다. 없으면 지금과 글자 하나 다르지 않다 — 다른 체인의 ISO는
      묶음을 안 싣는다(결정 F).
   2. 새 설치: 계획에 `  layers  <묶음 이름들> (N MiB) -> p3 /.tars/layers` 한 줄. `writeAccount` 다음에 p3를 다시 붙여 복사한다.
   3. 갱신: YES 전에 p3를 `MS_RDONLY`로 붙여 지금의 `version`과 빈 자리를 읽는다. 계획의 `p3 (tars-home) <- not opened`가
      `p3 (tars-home) <- layers <옛 버전 | none> -> <새 버전> (N MiB), your files are not touched`로 바뀐다. 자리가 모자라면
      (빈 자리 + 지금 묶음들 < 새 묶음들 + 1MiB) 거절하고 아무것도 안 바꾼다. p3가 없는 옛 디스크(`nums[2] == 0`)는
      `layers  skipped, this disk has no tars-home partition`.
   4. 복사 순서: `version`을 먼저 지운다 → 묶음마다 `<이름>.sqfs.new`에 쓰고 rename → 매체에 없는 `*.sqfs`를 지운다 →
      `sync` → `version`을 `.new`에서 rename. 중간에 끊기면 `version`이 없어 init이 아무것도 안 얹는다(결정 C.2). ESP의
      `boot/version`이 회전의 마지막인 것과 같은 꼴이다.
   5. 설치된 기계에서 USB를 꽂고 갱신하면 p3가 이미 `/home`에 붙어 있고 묶음은 loop로 열려 있다. ext4는 같은 장치를 두 번 붙일 수
      있고, rename은 열린 inode를 건드리지 않는다. 그 기계는 재부팅 전까지 옛 묶음을 쓴다. 이 길은 위험 3이고 체인은 USB 부팅
      길만 본다.
E. 결정 13의 비교 대상은 설치기가 묶음 옆에 쓰는 `version`(설치기의 `build_info.version` = 같은 매체의 이미지 버전)이다. ESP의
   `boot/version`과 같은 글자다. 묶음 안의 `usr/share/tars/layers/<묶음>`은 출처 기록으로 남기고 비교하지 않는다(확인 7). 비교는
   old 슬롯만이 아니라 매 부팅에서 한다. 새 슬롯은 정의상 같고, old 슬롯과 반쪽 갱신은 다르거나 없다 — 한 규칙이 셋을 다 덮는다.
F. ISO: `make_iso.sh`가 `ISO_LAYERS`(묶음 이름, 기본 빈 값)와 `ISO_OUT`(기본 `../out/tars.iso`)을 받는다. 묶음은
   `../devlayer/build/<이름>.sqfs`에서 `boot/layers/`로 간다. 없으면 이름을 대고 실패한다. `Makefile`의 `iso`에 `ISO_LAYERS ?=`를
   넘긴다. 릴리스 ISO에 싣는 단계는 TP를 닫을 때 `project_release.md`에 적는다(design "닫을 때"). 파일 하나가 4GiB 아래라
   `-iso-level 3`은 아직 필요 없다.
G. 체인 `devtools/check.sh`(`TP-M1:./devtools/check.sh`, `CHAINS` 끝, monitor 45504):
   - 빌드 단계 넷(`require_build_steps`) 뒤에 `devlayer/build.sh base` · `devlayer/build.sh lang-jvm`. 캐시가 있으면 굽기는
     건너뛰고 검사(G · H)는 방금 만든 initrd와 대조한다. 거두기 tar가 없으면 `make dev-layers`를 먼저 치라고 하고 빨갛다.
     `Makefile`의 `gate`가 `dev-layers`를 먼저 부르게 해서 `make gate`는 그대로 된다.
   - `ISO_LAYERS="base lang-jvm" ISO_OUT=../out/tars-dev.iso ./make_iso.sh`. 다른 체인의 `out/tars.iso`는 그대로다.
   - 부팅 넷, 모두 `-nic none`, OVMF, 최소 NVMe(16GiB + 2MiB, sparse). 시리얼 FIFO의 root 셸, 사용자는 `setpriv`(pm · mise의 모양).
     1. ISO + 빈 NVMe: `tars-install --yes /dev/nvme0n1` — 계획의 `layers` 줄, 복사 줄 둘, `done`. 그 셸에서 p3를 붙여
        `/.tars/layers`의 크기 · `version`.
     2. NVMe만: `tars-init: overlay /usr from 2 layers in Nms`, `/proc/mounts`의 overlay 줄. root의 `touch /usr/tp-probe`가
        `Read-only file system`. `/etc/gprofng.rc`가 있다. 사용자로 `gcc hello.c && ./a.out`(`-lm -lresolv`), `Makefile` 하나로
        `make`, `javac Hello.java && java Hello`, `jwebserver -b 127.0.0.1 -p 8000 -d <dir>` 뒤 `curl`이 파일을 받는다.
        시간(`date +%s%N` 차): 얹기, gcc, javac, java, jwebserver 첫 응답. 끝에 root가 `/home/.tars/layers/lang-jvm.sqfs`를
        4KiB의 0으로 바꾼다(확인한 것 9 — 게스트에 `mount`가 없어 첫 판의 "부팅 3에서 p3를 붙여 덮기"가 빨갰다).
     3. NVMe만: `tars-init: layer lang-jvm: mount failed (errno N)`와 `overlay /usr from 1 layers`. `gcc`는 돌고 `java`는 없다,
        `config shell=` 줄은 그대로다(결정 11).
     4. ISO + 같은 NVMe: `tars-install --yes /dev/nvme0n1`(갱신) — `p3 (tars-home) <- layers <ver> -> <ver>`, 옛 묶음 둘을 지우고
        새로 — 깨진 `lang-jvm.sqfs`가 바이트 그대로 돌아온다.
   - 결정 E의 다른 판(버전이 다름 · 없음)과 이름 거르기는 `layers_test.zig`가 본다. 부팅 하나에 40초가 넘게 들어 체인에 넣지 않는다.
H. 위험 1(읽기 전용 `/usr`)의 범위를 글자로 둔다. 게이트에서 `/usr`가 읽기 전용이 되는 것은 이 체인뿐이다. 다른 체인의 ISO와
   디스크에는 묶음이 없어서 overlay가 안 선다. 그래서 이 체인의 부팅 2가 terminal · 서비스 · 사용자 셸이 읽기 전용 `/usr`
   위에서 뜨는지를 본다(화면 셸의 첫 프롬프트, `tars-config` 한 번). 루트 게이트는 커널 · init의 변화가 다른 스물아홉을 흔들지
   않는지를 본다.

## 할 일

1. 커널(결정 A). `kernel/.config`를 바꾸고 `make kernel`. bzImage 크기 전후.
2. `init/src/layers.zig` · `layers_test.zig`(결정 C · E). `build.zig`에 테스트 등록. `main.zig`의 `readConfig`에서 `mountHome()`
   바로 뒤에 한 번 부른다. loop ioctl 번호와 `loop_config`의 배치는 커널 소스의 `include/uapi/linux/loop.h`에서 옮기고 주석에
   출처를 단다.
3. 설치기(결정 D). 계획 줄은 `disk.zig`의 함수로 떼어 `disk_test.zig`가 본다(새 설치 줄, 갱신 줄, p3 없음, 자리 모자람).
   매체에 묶음이 없을 때의 `UPDATE_TAIL`이 그대로인지도 본다.
4. `boot/make_iso.sh` · `Makefile`(결정 F, `gate`의 `dev-layers`), `make help`의 `dev-layers` 줄의 "부팅에는 아직 안 얹는다"를 고친다.
5. 체인 `devtools/check.sh`와 `CHAINS`(결정 G). 혼자 한 번 돌리고, 빨강 셋을 본다 — (a) `layers.zig`에서 overlay 호출을 빼면
   부팅 2가 `gcc`에서 빨갛다, (b) 설치기의 복사를 빼면 부팅 2가 `layers: none` 줄로 빨갛다, (c) 부팅 3의 덮어쓰기를 빼면
   부팅 4가 `overlay … from 2`로 빨갛다. 되돌리면 초록.
6. `make quick`, 컨테이너의 `zig build test`.
7. 루트 게이트(31체인, 약 23분 예상 — 지금 18분 14초에 이 체인 4~5분). `time make gate`의 출력은 scratchpad에.

## 판정

- 체인 `devtools`가 초록이고 할 일 5의 빨강 셋을 봤다.
- 루트 게이트 31/31, 잘린 줄 0.
- 숫자: bzImage 크기 차, ISO 크기(`tars.iso` · `tars-dev.iso`), 설치기의 묶음 복사 시간, 얹기 ms, gcc · javac · java ·
  jwebserver 첫 응답의 시간(TCG).

## 위험

1. ld.so가 묶음의 `usr/lib/x86_64-linux-gnu`(`libanl.so.1` 등)를 찾는가. M0의 chroot에서는 찾았지만(결과 4) 게스트의 ld.so.cache는
   initrd 것이다. 캐시에 없으면 기본 디렉터리로 간다 — 부팅 2의 `-lresolv`와 `java`가 본다. 안 되면 묶음에 맞는 캐시를 `etc/`로
   싣는 것이 처방 후보다(결정 C.6이 그대로 옮긴다).
2. TCG에서 `javac`와 JVM 시작이 느려 체인의 대기 시간을 넘는다. 부팅 2의 시간 상한은 처음 한 번 잰 숫자의 세 배로 잡는다.
3. 설치된 기계에서 USB를 꽂고 하는 갱신(결정 D.5). 게이트가 안 보는 길이다. 실기에서 문제가 나오면 `carryover.md`.
4. 복사가 길다. 지금 두 묶음 190MiB는 짧지만 모든 묶음이 실리면 수 GB다(design 위험 4). 복사 줄에 크기를 찍는다.
5. `/usr`를 맨 위에 두는 순서(결정 C.5)가 overlay의 디렉터리 병합에서 예상과 다른 자리. 체인의 `ls /usr/local/bin`과
   `/usr/bin/gcc`가 본다.

## 확인한 것

1. 커널(할 일 1): 증분 빌드 31초, bzImage 11,355,136 → 11,437,056바이트(+80KiB, 모두 `=y`라 모든 체인의 부팅에 붙는다).
   빌드가 도는 `olddefconfig`가 커밋한 `.config`를 한 줄도 안 바꾼다(`build/.config`와 같은 바이트).
2. `LOOP_CLR_FD`는 필요 없다(결정 C.4를 고친다). `drivers/block/loop.c`의 `lo_release`가 마지막 fd가 닫힐 때 `AUTOCLEAR`면
   장치를 스스로 푼다 — mount가 실패하면 init의 fd를 닫는 것으로, overlay가 실패해 umount하면 그것으로 풀린다.
3. 갱신의 복사 순서를 고쳤다(결정 D.4). 묶음마다 `.new` → rename이면 옛 묶음과 새 묶음이 잠깐 함께 자리를 차지해 자리 셈이
   묶음별 크기 대조를 요구한다. `version`을 먼저 지우면 init은 어차피 아무것도 안 얹으므로 옛 `*.sqfs`를 모두 먼저 지운다 —
   자리 판정이 `빈 자리 + 지금 묶음 ≥ 새 묶음 + 1MiB` 하나로 정확해진다(`disk.layersFit`). 예외는 위험 3의 길(열린 묶음의
   자리는 재부팅 전까지 안 풀린다).
4. `layers.scan`은 줄을 내보낼 곳(sink)을 받는다. `logline`은 init의 `tars-init:` 줄이라 설치기가 매체의 `boot/layers`를 같은
   함수로 읽으면 그 머리말이 섞인다 — init은 `layers.InitLog`, 설치기는 `Complain`을 준다.
5. 갱신 계획의 `p3 (tars-home) <- not opened`는 매체에 묶음이 없을 때 그대로다 — `planLines`의 새 인자에 `null`을 준 기존
   다섯 검사가 `UPDATE_TAIL`을 바이트 그대로 본다(`disk_test` 16).
6. Zig 0.17에는 배열 곱 `**`가 없다(`binary operator '*' has whitespace on one side`). 반복 글자는 `@as([N]u8, @splat('a'))`.
7. initrd에 `base64` · `dd`가 없다. 체인의 소스는 `printf` 한 겹으로 짓고(콘솔 fish의 작은따옴표는 `\n` · `\t`를 bash에 그대로
   넘긴다, C의 줄바꿈은 `%c`에 10), 묶음 망가뜨리기는 `head -c 4096 /dev/zero >`다.
8. `devlayer/build.sh`의 버전 줄 주석을 결정 E로 고쳤다. 스크립트가 stamp에 들어 두 묶음이 한 번 다시 구워진다.
9. 게스트에 `mount` · `free`가 없다(util-linux의 `mount`, procps의 `free`). init과 설치기는 mount(2)를 직접 부르므로 필요한 적이
   없었다. 체인 첫 판의 부팅 3(ISO로 떠 p3를 손으로 붙여 묶음 덮기)이 `mount: command not found`로 빨갰다 — 망가뜨리기를
   설치된 디스크로 뜬 부팅 2의 `/home`으로 옮겼다. 메모리는 `/proc/meminfo`로 본다.
10. 깨진 묶음의 실제 모양: 커널이 `Can't find a SQUASHFS superblock on loop1`, mount(2)가 EINVAL(22), init이 `layer lang-jvm:
    mount failed (errno 22)` 뒤 base 하나로 `overlay /usr from 1 layers in 26ms`. 그 loop가 실제로 풀렸는지는 체인이 안 본다.

## 결과

1. 체인 `devtools`가 초록이다(혼자 4분 20초 — 빌드 뒤 92초, 게이트 안에서 101초). 부팅 넷의 판정 B1~B4가 모두 섰다.
2. 할 일 5의 빨강 셋은 plan이 적은 자리보다 앞에서 잡혔다 — (a) overlay 호출을 빼면 부팅 2의 `init did not lay two layers
   over /usr`(gcc보다 먼저 보는 init 줄), (b) 새 설치의 복사를 빼면 부팅 1의 `tars-install did not copy base.sqfs byte for
   byte`, (c) 망가뜨리기를 빼면 부팅 3의 `init did not name the broken layer`. 셋 다 되돌린 뒤 원본과 같은 바이트(`cmp`).
3. 루트 게이트 31/31, 20분 14초(앞 판 18분 14초), 잘린 줄 0. 다른 서른 체인은 커널 +80KiB · init의 새 줄(`layers: none` 등)
   위에서 그대로다.
4. 숫자(게이트 안, TCG `-cpu qemu64 -m 1024`):

   | 항목 | 값 |
   |---|---|
   | 묶음 둘(base 64MiB + lang-jvm 126MiB) | 200,884,224바이트(192MiB) |
   | ISO | `tars.iso` 143,589,376 · `tars-dev.iso` 344,477,696바이트 |
   | 설치기의 복사(CD → p3) | 1,017ms |
   | init의 얹기(loop 둘 · squashfs 둘 · overlay) | 32ms(묶음 하나일 때 26ms) |
   | 사용자 gcc(`-lm -lresolv`) · make | 1,835ms · 444ms |
   | javac · `java Hello` | 10,508ms · 568ms |
   | jwebserver 시작부터 curl 첫 응답 | 3,402ms |
   | JVM 뒤 MemAvailable | 604,088kB |

5. 위험 1(ld.so가 묶음의 `usr/lib/x86_64-linux-gnu`를 찾는가)은 일어나지 않았다 — `-lresolv`로 링크한 프로그램과 java가 initrd의
   ld.so.cache 위에서 돈다. 위험 2(TCG의 JVM)도 qemu64 · 1GiB에서 상한 안이다. 위험 5(`/usr`를 맨 위에 둔 순서)는 `/proc/mounts`의
   `lowerdir=/usr:/run/tars-layers/base/usr:/run/tars-layers/lang-jvm/usr`와 `/usr/local/bin/java` · `/usr/bin/gcc`가 함께 선 것으로
   지났다.
