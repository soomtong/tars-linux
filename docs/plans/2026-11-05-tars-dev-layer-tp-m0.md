# TP-M0 — 매니페스트 · `base` 묶음 · JDK

> 줄 번호와 판 번호는 `d687092` 기준이라 낡을 수 있다. 결과는 끝의 "결과" 절(구현 뒤 채운다).

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
   `libc.so.6`가 말하는 판과 같아야 하고, 다르면 빌드가 두 판을 찍고 실패한다. 미러가 옛 판을 내렸으면 apt가 실패한다 — 그때는
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
   바뀐 파일(설치 전에도 있던 경로)이 나오면 이름을 찍는다 — 결정 4 검사가 initrd와 대조한다.
F. 풀기(`upstream`): tarball을 `usr/local/lib/<도구>-<버전>/`에 그대로 풀고, `bin/`의 실행 파일마다 `usr/local/bin/<이름>` 상대 링크를
   둔다(`../lib/<도구>-<버전>/bin/<이름>`). JDK는 `lib/security/cacerts`를 자기 안에 갖는다(design 확인 7) — `/etc`는 건드리지 않는다.
G. 결정 4 검사의 비교 대상은 `kernel/initrd.cpio`의 첫 archive다. `gzip -dc`를 파일로 받은 뒤 `cpio -idm`으로 임시 디렉터리에 푼다
   (파이프 안에 두면 pipefail이 gzip의 EPIPE를 거짓 빨강으로 올린다 — HANDOFF). firmware 꼬리는 `lib/firmware`라 개발 도구 층과 안 겹친다.
   같은 경로가 둘에 있으면: 내용(파일은 sha256, 링크는 대상)이 같으면 묶음에서 빼고 개수를 센다. 다르면 경로를 찍고 실패한다.
   initrd가 없으면 "먼저 make initrd"를 찍고 실패한다.
H. 결정 5 검사: 묶음 안의 ELF마다(`readelf -d`) `NEEDED`를 다음 순서로 찾는다 — 그 ELF의 `RUNPATH`/`RPATH`(`$ORIGIN`을 편다),
   그다음 initrd + 묶음의 `lib/x86_64-linux-gnu` · `usr/lib/x86_64-linux-gnu` · `lib64` · `usr/lib`. 못 찾은 것은 ELF · soname 쌍으로
   찍고 실패한다. 예외는 `devlayer/needed-ignore.tsv`(경로 패턴 · soname · 이유)에만 둔다. M0에서 넣을 수 있는 이유는 GUI 하나다
   (design 비목표 5 — JDK의 `libawt_xawt.so` · `libsplashscreen.so` 등이 끄는 X11 계열). 그 밖은 `debian` 줄을 더해 푼다.
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

(구현 중 채운다)

## 결과

(구현 뒤 채운다)
