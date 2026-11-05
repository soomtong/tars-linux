# TP-M0 — 매니페스트 · `base` 묶음 · JDK

> 구현은 lead가 직접 넣었다(2026-11-05). 줄 번호와 판 번호는 `d687092` 기준이라 낡을 수 있다. 결과는 끝의 "결과" 절.
> 결정 B · E · G · H는 구현이 드러낸 사실로 고쳤다 — "확인한 것"의 번호로 이유를 단다.

Goal: TP design 결정 1~7(빌드 쪽). 출처 두 종류(`debian` · `upstream`)를 하나씩 세워 `base.sqfs`(gcc · `libc6-dev` · make)와
`lang-jvm.sqfs`(Temurin JDK LTS)를 굽고, 결정 4(겹친 경로) · 5(`NEEDED`) 검사를 지난다. 부팅 · 커널 · ISO · `tars-install`은
바꾸지 않는다(M1의 몫).

## 착수 전 확인 (2026-11-05, `d687092`)

1. 개발 컨테이너는 arm64다(`uname -m` = `aarch64`, Dockerfile 머리의 ZM-M3 주석). amd64 패키지는 `apt-get download` +
   `dpkg -x`로 sysroot에 풀 뿐 postinst를 돌리지 않는다. 그래서 결정 2의 "`apt-get install`(postinst까지)"은 개발 컨테이너에서 안 된다.
   `docker run --platform=linux/amd64 debian:trixie-slim`은 OrbStack(Rosetta)에서 0.34초에 뜨고 `dpkg --print-architecture`가
   `amd64`다. CI의 GitHub 러너는 amd64라 그대로 원래 아키텍처다.
2. glibc 판: 개발 컨테이너 sysroot의 `libc.so.6`가 `Debian GLIBC 2.41-12+deb13u4`, amd64 trixie 미러의 후보가 `libc6`
   · `libc6-dev` 둘 다 `2.41-12+deb13u4`다. `gcc-14` 14.2.0-19, `make` 4.4.1-2. 오늘은 같지만 Debian 점 릴리스가 나오면 미러가
   옛 판을 내린다 — 아래 결정 B.
3. 개발 컨테이너에 `mksquashfs`가 없다(결정 A가 더한다). `readelf` · `objdump` · `cpio` · `xz` · `zstd`(1.5.7)는 있다.
4. 루트 게이트의 `clean()`(`check.sh`)이 `out`을 통째로 지운다. design 결정 6의 `out/dev-cache/`는 게이트마다 사라진다 — 결정 C.
5. `Makefile`은 `*/check.sh`를 가진 디렉터리를 체인으로 센다(`CHAINS := … wildcard */check.sh`). 새 디렉터리의 검사 스크립트는
   `check.sh`라는 이름을 쓰지 않는다.
6. 커널: `# CONFIG_BLK_DEV_LOOP is not set`, `# CONFIG_OVERLAY_FS is not set`, `SQUASHFS`는 줄이 없다. 셋 다 M1에서 켠다(design
   확인 4의 "loop는 M0이 확인"이 이것이다).
7. 위험 1의 첫 훑기: `init/src` · `terminal/src` · `shared`의 Zig에서 `/usr/…` 경로로 쓰기(`create` · `mkdir` · `rename` 등)가 없고,
   `*/check.sh`에서 게스트의 `/usr`로 `>` · `cp` · `ln -s` · `mkdir -p`가 없다. 아래 할 일 6이 더 넓게 본다.

## 결정 (이 plan이 정한다 — 뒤집을 것이 있으면 글자로)

A. 두 컨테이너로 나눈다. 거두기(`debian` 줄)만 버리는 amd64 컨테이너(`docker run --rm --platform=linux/amd64 debian:trixie-slim`,
   `devlayer/harvest.sh`)에서 하고, 결과를 tar 하나(`devlayer/build/<묶음>.harvest.tar`)로 내놓는다. 그 컨테이너에는 아무것도 더
   깔지 않는다 — 거두기 전에 무엇이든(예: `binutils`) 깔면 "새로 생긴 파일"에서 빠진다(`as` · `ld`). 받기 · 풀기 · 검사 · 굽기는
   개발 컨테이너에서 한다(`devlayer/build.sh`). Dockerfile에 `squashfs-tools`를 더한다(사용자, 2026-11-05 —
   `feedback_devcontainer_additions`). arm64의 `readelf`는 x86_64 ELF를 읽고, squashfs 이미지는 아키텍처를 타지 않는다.
B. `debian` 줄은 버전을 `=`로 고정한다(`apt-get install libc6-dev=2.41-12+deb13u4 …`). `libc6-dev` 줄의 버전은 initrd의
   `libc.so.6`가 말하는 판과 같아야 하고, 다르면 `build.sh`가 풀린 initrd의 `lib/x86_64-linux-gnu/libc.so.6`를 읽어 두 판을 찍고
   실패한다. 미러가 옛 판을 내렸으면 apt가 실패한다 — 그때는
   개발 컨테이너 이미지(initrd의 glibc)와 매니페스트를 함께 올린다. snapshot.debian.org로 옛 판을 받는 길은 M0에서 만들지 않는다.
C. 캐시와 산출물은 `out/` 밖이다. 받은 tarball은 `devlayer/cache/<sha256>`, 구운 묶음은 `devlayer/build/<묶음>.sqfs`와
   `<묶음>.stamp`(그 묶음의 매니페스트 줄들의 sha256). 둘 다 `.gitignore`. stamp가 같으면 다시 굽지 않는다(결정 6).
D. 매니페스트 `devlayer/manifest.tsv`의 열은 design 결정 1 그대로 여섯이다: `도구 · 묶음 · 버전 · 종류 · URL · sha256`.
   `debian` 줄은 URL 자리에 패키지 이름, sha256 자리에 `apt`를 쓴다 — 서명된 Release가 검증한다. 의존은 apt가 푼다. 실제로 깔린
   패키지 목록(`dpkg-query -W`)을 묶음 안 `usr/share/tars/layers/<묶음>.pkgs`에 남긴다. 같은 자리의 `<묶음>`(파일 하나)은 design
   결정 13의 버전 줄이다 — M0은 `git describe` 값을 쓴다.
E. 거두기(`debian`): 설치 전후로 `find /usr /etc -xdev`(경로 · 종류 · 링크 대상 · sha256)를 떠서 새로 생기거나 바뀐 것만 묶음 뿌리에
   복사한다. `/etc/alternatives/*`를 가리키는 링크는 `readlink -f`의 최종 대상으로 펴서 상대 링크로 놓고(결정 2), `/etc/alternatives`는
   싣지 않는다. 그 밖의 새 `/etc` 파일은 묶음의 `etc/`에 넣고 목록을 찍는다(base는 0개 기대). `/var` · `/root` · `/tmp`는 버린다.
   바뀐 파일(설치 전에도 있던 경로)이 나오면 이름을 찍는다 — 결정 4 검사가 initrd와 대조한다. 펴기는 새 경로에만 한다(확인한 것 1).
   고정한 패키지의 의존 폐포 가운데 slim에 이미 있던 패키지의 `/usr` 파일도 싣는다(확인한 것 3). 거두기 컨테이너에서 이미 끊긴
   링크는 싣지 않는다(확인한 것 4).
F. 풀기(`upstream`): tarball을 `usr/local/lib/<도구>-<버전>/`에 그대로 풀고, `bin/`의 실행 파일마다 `usr/local/bin/<이름>` 상대 링크를
   둔다(`../lib/<도구>-<버전>/bin/<이름>`). JDK는 `lib/security/cacerts`를 자기 안에 갖는다(design 확인 7) — `/etc`는 건드리지 않는다.
G. 결정 4 검사의 비교 대상은 `kernel/initrd.cpio`의 첫 archive다. `gzip -dc`를 파일로 받은 뒤 `cpio -idm`으로 임시 디렉터리에 푼다
   (파이프 안에 두면 pipefail이 gzip의 EPIPE를 거짓 빨강으로 올린다 — HANDOFF). firmware 꼬리는 `lib/firmware`라 개발 도구 층과 안 겹친다.
   같은 경로가 둘에 있으면: 내용(파일은 sha256, 링크는 대상)이 같으면 묶음에서 빼고 개수를 센다. 다르면 경로를 찍고 실패한다.
   initrd가 없으면 "먼저 make initrd"를 찍고 실패한다. initrd는 merged-usr가 아니어서(확인한 것 2) 묶음의 `usr/lib/…` ·
   `usr/lib64/…`는 initrd의 짝(`lib/…` · `lib64/…`)과도 대조한다 — 같은 바이트면 빼고, 다르면 실패한다. 그렇게 빠져 대상을 잃은
   상대 링크는 짝의 절대 경로(`/lib/x86_64-linux-gnu/…`)로 바꾼다(relinked).
H. 결정 5 검사: 묶음 안의 ELF마다(`readelf -d`) `NEEDED`를 다음 순서로 찾는다 — 그 ELF의 `RUNPATH`/`RPATH`(`$ORIGIN`을 편다),
   그다음 initrd + 묶음의 `lib/x86_64-linux-gnu` · `usr/lib/x86_64-linux-gnu` · `lib64` · `usr/lib`. 못 찾은 것은 ELF · soname 쌍으로
   찍고 실패한다. 예외는 `devlayer/needed-ignore.tsv`(경로 패턴 · soname · 이유)에만 둔다. 이유는 둘이다 — GUI(design 비목표 5,
   JDK의 `libawt_xawt.so` · `libsplashscreen.so`가 끄는 X11 계열)와 jvm-loaded(확인한 것 6). 그 밖은 `debian` 줄을 더해 푼다.
   이 검사가 base에서 특히 값을 내는 자리: 거두기의 기준은 `trixie-slim`이고 initrd가 아니다. slim에는 있고 initrd에는 없는
   라이브러리(예: `cc1`이 끄는 것)는 "새로 생긴 파일"에서 빠진다 — 그것을 여기서 잡는다.
I. `mksquashfs`는 `-all-root -noappend`와 고정 시각(`-mkfs-time 0 -all-time 0`)으로 굽는다 — 같은 입력이면 같은 파일. 묶음 뿌리는
   `usr/`(와 있으면 `etc/`)다(design 결정 9의 `lowerdir=<묶음>/usr`).
J. 압축(결정 7): 두 묶음을 `gzip` · `xz -Xbcj x86` · `zstd -Xcompression-level 15` · `zstd 19`로 각각 굽고 크기 · 굽는 시간 ·
   다 읽는 시간(`unsquashfs -processors 1 -d` — 맥북 에어 2011의 한 코어에 가깝게)을 잰다. 고르는 기준은 다 읽는 시간이 xz의 절반
   아래면 zstd(낮은 레벨), 아니면 xz. 고른 것은 `build.sh`의 기본값이 되고, M1이 그 압축 하나만 커널에 켠다.
K. g++은 `base`에 넣지 않는다 — design 표가 gcc · g++을 `lang-native`에 두고 판정 TP-M0이 base를 gcc · `libc6-dev` · make로 적었다.
   `lang-native` milestone이 두 묶음 사이의 겹침(g++-14가 끄는 gcc-14)을 다룬다.

## 할 일

1. `devlayer/manifest.tsv` — base 넷(`libc6-dev` · `gcc` · `make`, 고정 판)과 JDK 한 줄. JDK는 Adoptium의 최신 LTS(25) GA를
   `api.adoptium.net/v3/assets/latest/25/hotspot?os=linux&architecture=x64&image_type=jdk`로 찾아 판 · URL · sha256을 고정한다.
   GitHub 다운로드가 504를 내면(HANDOFF의 실패 기록) 다시 시도하고, 받은 것은 캐시에 남는다.
2. Dockerfile에 `squashfs-tools`(층 주석과 함께), `make container`로 로컬 빌드. `devlayer/harvest.sh <묶음>`(amd64 컨테이너, E)과
   `devlayer/build.sh <묶음>`(개발 컨테이너) — 매니페스트를 읽어 거두기 tar를 풀거나 받기 · sha256 확인 · 풀기(F) → 검사(G · H,
   `devlayer/verify.sh`) → 굽기(I). 끝에 한 줄 요약: 파일 수 · 풀린 크기 · sqfs 크기 · 뺀 겹친 경로 수 · 펴진 alternatives 수.
3. `Makefile`에 `dev-layers`(묶음을 고르는 `DEV_LAYERS ?= base lang-jvm`). `help`에 한 줄. `.gitignore`에 `devlayer/cache/` ·
   `devlayer/build/`.
4. 검사가 실제로 빨개지는지 하나씩 본다 — (a) 매니페스트의 JDK sha256 한 글자를 바꾸면 이름을 대고 실패, (b) initrd에 있는 파일
   하나(`usr/bin/make`가 없으면 `usr/lib/x86_64-linux-gnu/libz.so.1`)를 묶음에 다른 내용으로 넣으면 경로를 대고 실패, (c)
   `needed-ignore.tsv`를 비우면 JDK의 X11 줄이 빨갛다. 되돌리면 초록.
5. 압축 넷의 실측(J)과 선택.
6. 위험 1 넓게 — `rg`로 게스트 쪽 코드 · seed · rc · 체인이 실행 중에 `/usr`에 쓰는 자리를 찾는다(`/usr/local`, `/usr/share`의 캐시 ·
   `ldconfig` · fish의 completion 생성 등). 찾은 것은 M1 plan의 입력으로 이 plan의 "확인한 것"에 적는다.
7. 컨테이너 밖에서 한 번 손으로 — 구운 `base.sqfs`를 `unsquashfs`로 풀어 `chroot` 없이 `readelf`로 `usr/bin/gcc`의 대상과
   `cc` 링크가 펴졌는지, JDK의 `usr/local/bin/java`가 맞는 자리를 가리키는지 본다. 부팅은 M1이 한다.
8. `make quick`(shellcheck가 새 스크립트를 본다). 루트 게이트는 돌리지 않는다 — 부팅 · 체인이 쓰는 파일이 안 바뀐다. `make
   quick`이 체인 목록을 세는 자리에 `devlayer`가 안 끼는지도 본다(확인 5).

## 판정

- `make dev-layers`가 두 묶음을 굽고 검사 G · H가 초록. 두 번째 실행은 받기 · 굽기를 건너뛴다(stamp).
- 할 일 4의 세 빨강을 봤다.
- 숫자: 묶음마다 패키지 수 · 파일 수 · 풀린 크기 · 압축별 sqfs 크기와 시간 · 겹쳐서 뺀 경로 수 · 펴진 alternatives 수.

## 위험

1. Rosetta 아래 amd64 `apt-get`과 postinst가 원래 아키텍처와 다르게 도는 자리(드묾). CI(원래 amd64)에서 같은 stamp가 나오는지는
   M1에서 CI에 올릴 때 본다.
2. JDK의 `NEEDED`가 GUI 밖에서도 initrd에 없는 것을 끈다(libasound · libfreetype 등). 나오면 `debian` 줄 — 크기를 숫자로 남긴다.
3. 거두기의 "바뀐 파일"이 많으면(slim의 라이브러리가 의존 때문에 올라감) 결정 4가 실패한다. 그 경우 libc6 · `libstdc++6` 판이
   initrd와 다른 것이니 결정 B와 같은 처방(이미지와 함께 올리기)이다.

## 확인한 것

1. 첫 거두기의 "바뀐 파일"에 `awk` · `nawk` · `pager` · `which` · `rmt`가 섞였다. slim에 원래 있던 alternatives 링크를 펴기 루프가
   함께 펴서 내용이 바뀐 것이다. 펴기를 새 경로에만 하자 바뀐 것은 `/etc/ld.so.cache` 하나(싣지 않는다)로 줄었다. 펴진 것은 넷 —
   `cc -> x86_64-linux-gnu-gcc-14`, `c89 -> c89-gcc`, `c99 -> c99-gcc`, `usr/lib/cpp -> ../bin/x86_64-linux-gnu-cpp-14`.
2. initrd는 merged-usr가 아니다. `bin -> usr/bin`은 링크지만 `lib`와 `lib64`는 진짜 디렉터리이고, 공유 라이브러리 109개가
   `lib/x86_64-linux-gnu`에, `usr/lib/x86_64-linux-gnu`에는 둘이 있다. `build.sh`의 첫 판은 libc를 Debian 자리(`usr/lib/…`)에서 찾아
   "extraction failed"로 멈췄다. 개발 도구 층은 `/usr`에만 얹히므로 묶음의 `usr/lib/x86_64-linux-gnu/libX`와 initrd의 같은 이름은
   경로가 달라 겹침 검사에 안 걸린다 — 결정 G에 짝 대조를 더했다.
3. 처음 검사를 돌렸을 때 끊긴 링크가 25개였다. `libc6-dev`의 개발용 링크 아홉(`libanl.so -> libanl.so.1`, `libresolv.so`, `libcrypt.so`,
   `libmvec.so`, `libthread_db.so` 등)과 doc 링크 열여섯(`usr/share/doc/gcc-14 -> gcc-14-base`)이다. 대상이 libc6 · libcrypt1 ·
   gcc-14-base의 것이고, 그 패키지들은 slim에 이미 있어 "새로 생긴 파일"에서 빠졌다 — 결정 H가 예상한 틈이 ELF 밖에서 먼저 나왔다.
   이대로면 게스트의 `cc … -lresolv`가 링크에서 실패한다. 의존 폐포(`apt-cache depends --recurse`) 가운데 slim에 있던 여덟(`gcc-14-base`
   · `libc6` · `libcrypt1` · `libgcc-s1` · `libgmp10` · `libstdc++6` · `libzstd1` · `zlib1g`, 파일 301개)을 함께 싣고, initrd의 짝과
   같은 바이트인 21개를 뺐다(`differs=0` — 판이 어긋난 라이브러리는 없다). 대상이 빠진 링크 다섯은 `/lib/x86_64-linux-gnu/…`로
   바꿨다. initrd에 없는 런타임 라이브러리(`libanl.so.1` · `libmvec.so.1` 등)는 묶음의 `usr/lib/x86_64-linux-gnu`에 남는다.
4. 그래도 하나가 끊겼다 — `usr/share/doc/cpp-x86-64-linux-gnu/README.Bugs -> ../gcc-14/README.Bugs`. slim의
   `/etc/dpkg/dpkg.cfg.d/docker`가 `usr/share/doc/*`를 풀지 않아 거두기 컨테이너 안에서도 대상이 없다. TARS가 아니라 거둔 자리의
   사정이므로 그 컨테이너에서 이미 끊긴 링크는 싣지 않는다(`broken=1`). 게스트에 `man`이 없어 slim의 doc · man 제외는 그대로 둔다 —
   문서는 design 결정 19(dasht)의 몫이다.
5. `tar -tf … | head -n1`이 `lang-jvm`의 `build.sh`를 말없이 끝냈다. head가 닫으면 tar가 SIGPIPE(141)로 죽고 pipefail과 `set -e`가
   스크립트를 멈춘다 — gzip EPIPE와 같은 종류다. 목록을 파일로 받는다.
6. JDK의 미해결 20개: X11 일곱(GUI)과 `libjvm.so` 열셋. JDK의 `lib/*.so`는 `libjvm.so`를 NEEDED로 부르는데 그것은 `lib/server/`에
   있고 RUNPATH가 거기를 안 가리킨다(`libjava.so`는 RPATH도 없다, `bin/java`는 `RPATH $ORIGIN` · NEEDED `libjli.so`). launcher가
   `lib/server/libjvm.so`를 먼저 dlopen하고 ld.so가 이미 올라온 것을 soname으로 맞추는 JVM 고유의 길이라 예외의 둘째 이유
   `jvm-loaded`로 적었다. 아래 결과 4의 `java Hello`가 그 길이 실제로 도는 것을 보였다. libasound(`libjsound.so`)는 initrd에서
   풀렸고, freetype은 JDK 안에 있다 — 위험 2는 일어나지 않았다.
7. 받은 파일의 sha256을 캐시 이름으로 옮긴 뒤에 보던 첫 판은 틀린 바이트에 캐시 이름을 줄 수 있었다. `.part`에서 먼저 본다.
8. 할 일 6(위험 1): 실행 중에 `/usr`에 쓰는 자리를 찾지 못했다. `/usr`에 쓰는 것은 모두 `make_initrd.sh`가 빌드 때 `$WORKDIR`에
   쓰는 것이고, init · terminal의 Zig에는 실행 경로(`/usr/lib/tars/tars-wifi` 등)만 있고, 체인은 게스트의 `/usr`를 `stat`으로
   읽기만 한다. 판정은 design대로 M1의 루트 게이트다.
9. 묶음 뿌리를 `/workspace` 아래가 아니라 컨테이너 안 임시 디렉터리에 푼다. `/workspace`는 macOS APFS(대소문자를 안 가림)라
   `linux-libc-dev`의 `xt_MARK.h` · `xt_mark.h` 같은 쌍이 한쪽으로 덮인다. 그 자리에는 tar · sqfs 같은 파일 하나짜리만 둔다.

## 결과

1. `make dev-layers`가 두 묶음을 굽고 초록이다. 두 번째 실행은 둘 다 `cached`, 13초(뿌리 만들기와 검사만 돈다).

   | 묶음 | 패키지 · 줄 | 파일 | 풀린 크기 | zstd15 | 뺀 경로 | relinked | ELF | 예외 |
   |---|---|---|---|---|---|---|---|---|
   | base | 37 + 의존 8 | 2,736 | 194MiB | 64MiB | 21 | 5 | 358 | 0 |
   | lang-jvm | JDK 25.0.5+8 | 196 | 301MiB | 126MiB | 0 | 0 | 72 | 20 |

   첫 거두기는 1분 13초(Rosetta의 apt), 굽기는 묶음마다 3~4초.
2. 압축(할 일 5, 결정 J) — read는 `unsquashfs -processors 1`로 다 푸는 시간이다.

   | 묶음 | gzip | xz `-Xbcj x86` | zstd 15 | zstd 19 |
   |---|---|---|---|---|
   | base | 71.8MiB · 굽기 3.6초 · read 0.7초 | 56.9 · 9.3 · 2.8 | 65.0 · 2.5 · 0.3 | 64.0 · 6.4 · 0.3 |
   | lang-jvm | 136.3 · 4.2 · 1.0 | 117.9 · 13.1 · 5.2 | 126.6 · 3.6 · 0.3 | 125.5 · 9.6 · 0.3 |

   zstd는 xz보다 7~14% 크고 읽기가 9~17배 빠르다 — 기준(xz의 절반 아래)대로 zstd다. 19는 15보다 1% 작고 굽기가 2.5배라 zstd15를
   기본값으로 둔다. M1은 커널에 `SQUASHFS_ZSTD` 하나를 켠다.
3. 할 일 4의 빨강 셋: (a) 매니페스트 sha256 한 글자 → `jdk: cached … has sha256 6898…, manifest says 7898…`. (b) 작은 뿌리에 initrd의
   `usr/bin/bash`를 넣어 `verify.sh`를 직접 — 같은 바이트는 `dropped=1`, 한 바이트 더하면 `differs from initrd /usr/bin/bash` ·
   0 아닌 종료. (c) 예외 tsv가 비었을 때 JDK 20줄이 빨갰다(확인한 것 6). 셋 다 되돌린 뒤 초록.
4. plan 밖의 검사 하나: 버리는 amd64 컨테이너에서 풀린 initrd 위에 두 묶음을 덮고 `chroot`(TARS의 실제 `/` 모양) —
   `cc -O2 h.c -lm -lresolv`(pthread 포함) → `hello 1.414 res_init=0`, 같은 것을 `make`로, `cc -static`도 실행된다. `javac
   Hello.java && java Hello` → `hello 25.0.5+8-LTS`. relinked 링크와 jvm-loaded 예외의 주장이 실제로 맞다. 부팅(overlay · loop)은 M1이다.
5. `make quick` PASS. 새 스크립트 넷은 같은 shellcheck 플래그(`-x -P SCRIPTDIR -S style`)로 깨끗하다(add 전이라 quick의 64개에는 없다).
   `devlayer/`는 `check.sh`가 없어 체인으로 세지 않는다. 루트 게이트는 돌리지 않았다 — 부팅 · 체인이 쓰는 파일이 안 바뀌었다
   (Dockerfile은 끝에 층 하나를 더했을 뿐이다).

## M1에 넘길 것

- 커널: `BLK_DEV_LOOP` · `OVERLAY_FS` · `SQUASHFS` + `SQUASHFS_ZSTD`.
- 구운 묶음은 게이트가 안 지우는 `devlayer/build/`에 남는다. design 결정 6의 "`make iso`는 구워진 개발 도구 층이 있으면 싣는다"를
  그대로 두면 게이트 ISO가 커진다 — 명시적으로 고를 때만 싣는다.
- 버전 줄은 지금 `git describe`(`v0.1.4-16-ga98564f-dirty`)이고 stamp에 안 든다. 결정 13의 비교 대상(TARS 버전)은 M1이 정한다.
- 묶음의 `etc/`는 base에 `etc/gprofng.rc` 하나다(결정 10의 복사 대상).

(구현 뒤 채운다)
