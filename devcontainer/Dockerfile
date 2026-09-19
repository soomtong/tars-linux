# 호스트(Apple Silicon)와 같은 arm64로 돈다. 예전에는
# `--platform=linux/amd64`가 붙어 있어서 컴파일러와 QEMU 바이너리 자체가
# Rosetta 에뮬레이션을 통과했고, 그 안에서 다시 x86_64 게스트를 TCG로
# 돌렸다(에뮬레이터의 에뮬레이션). 게스트용 x86_64 산출물은 이제 전부
# 크로스 컴파일이거나 amd64 패키지에서 조달한다 — ZM-M3.
FROM debian:trixie-slim

# RM-M0이 ovmf를 더한다. 게이트의 아홉 체인은 전부 QEMU의 기본 BIOS(SeaBIOS)로
# 부팅하는데, 실머신 노트북은 예외 없이 UEFI다. ovmf는 EDK II를 미리 빌드해 둔
# 펌웨어 이미지(/usr/share/OVMF/OVMF_CODE_4M.fd)라서 Architecture: all이다 —
# 컨테이너가 arm64인데도 x86_64 게스트용 펌웨어가 그대로 깔린다. 3.6MB다.
#
# UT-M1이 zstd를 더한다. 어떤 빌드 단계도 이것을 부르지 않는다 — 재는
# 도구다. UT-M0의 크기 스파이크가 압축기 셋 중 zstd 하나를 컨테이너에 없어서
# 못 쟀고(design 실측 15), UT-M2가 27MB를 더하면 그 질문이 다시 살아난다.
# 그때 재려고 이미지를 또 굽지 않으려고 지금 넣는다. 커널은 CONFIG_RD_ZSTD를
# 이미 켜 뒀으므로 카드는 커널 재설정 없이 손에 있다.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gcc-multilib-x86-64-linux-gnu \
        binutils \
        qemu-system-x86 \
        ovmf \
        git \
        ca-certificates \
        flex \
        bison \
        bc \
        libssl-dev \
        libelf-dev \
        curl \
        cpio \
        rsync \
        file \
        xorriso \
        imagemagick \
        xz-utils \
        unzip \
        e2fsprogs \
        zstd \
    && rm -rf /var/lib/apt/lists/*

# initrd에 들어갈 x86_64 유저랜드. 컨테이너가 arm64라서 컨테이너 자신의
# /usr/bin/fish를 복사할 수 없다 — amd64 .deb를 받아 여기에 풀어두고
# kernel/make_initrd.sh가 이 디렉터리에서만 복사한다. 네트워크는 이미지
# 빌드 때 한 번만 쓴다: 게이트는 clean 재빌드를 6회 하므로 initrd 생성이
# 네트워크에 나가면 안 된다(느리고, 오프라인에서 죽고, 회차마다 패키지
# 버전이 달라질 수 있다).
#
# 목록은 옛 initrd에 실제로 들어 있던 .so 아홉 개에서 역산한 최소 집합이다.
# libpthread/librt/libutil은 fish가 아니라 terminal(Zig 산출물)이 요구하며
# 셋 다 libc6 소속이다. fish 4.0.2는 Rust로 작성돼 libstdc++가 필요 없다.
# fish-common은 architecture: all이라 :amd64를 붙이지 않는다 —
# /usr/share/fish/{functions,config.fish,__fish_build_paths.fish}가 여기 있다.
#
# CP-M2가 셋을 더한다. bash는 libtinfo6만 있으면 되고, zsh는 libtinfo6 +
# libcap2를 요구한다. zsh-common은 fish-common과 같은 구조로 arch: all이라
# :amd64를 붙이지 않는다 — /usr/share/zsh의 함수들이 거기 있다. apt-get
# download는 의존을 따라가지 않으므로 이 목록은 언제나 명시적이다.
#
# IP-M1이 ncurses-base를 더한다. terminal이 PTY 셸의 TERM을 xterm으로
# 바꾸므로(design doc 결정 7) 그 terminfo가 게스트에 있어야 진실이 된다 —
# /usr/share/terminfo/x/xterm이 이 패키지에 들어 있다. fish-common/zsh-common과
# 같이 architecture: all이라 :amd64를 붙이지 않는다.
#
# HI-M1이 libc-bin을 더한다. libc6에는 로케일 데이터가 없다 — Debian은
# 미리 컴파일된 /usr/lib/locale/C.utf8을 libc-bin에 담는다. 그것이 없으면
# 게스트에 UTF-8 로케일이 아예 없고, 셸의 `setlocale`이 실패해서 fish가
# 우리가 보낸 한글 세 바이트를 한 글자가 아니라 바이트 셋으로 읽는다.
# 증상은 "입력이 안 된다"가 아니라 명령줄의 앞 글자가 지워지는 것이다 —
# fish가 바이트마다 폭을 세어(0x80~0x9F는 0칸, 0xA0 이상은 1칸) 커서를
# 두 칸짜리 글자의 가운데에 세우고 거기에 다음 글자를 쓰기 때문이다.
# ncurses-base와 같은 종류의 항목이다: 우리가 게스트에게 한 말을 참으로
# 만들어 주는 데이터.
#
# UT-M1이 층 1(GNU 한 벌)을 더한다 — UT가 이 목록을 처음 넓히는 자리다.
# coreutils는 이미 있었고(UT-M0 전부터), 없던 것은 별도 패키지 여덟이다:
# grep · findutils(find·xargs) · sed · mawk(awk) · diffutils(diff·cmp) ·
# less · procps(ps·top) · util-linux(dmesg 하나 때문에 받는다).
#
# 라이브러리 넷이 따라온다. design 실측 3은 둘이라고 적었는데 그것이
# 불완전했다 — 바이너리의 DT_NEEDED만 보고 .so의 DT_NEEDED를 안 봤다.
#
#   libacl1     sed·cp·mv
#   libattr1    coreutils(cp·mv 계열). 실측 3에 없던 이름이다
#   libproc2-0  ps·top
#   libsystemd0 libproc2가 데려온다. 이것도 실측 3에 없었다
#
# libsystemd는 lzma·zstd·gcrypt를 dlopen으로만 열고 DT_NEEDED에는
# libcap·libm·libc뿐이다(libcap은 zsh가 이미 데려와 있다). 저널 압축을 쓸
# 때만 열리는 경로이고 ps/top은 저널을 안 본다 — 그래서 copy_lib_deps가
# 따라가는 사슬은 4.2MB가 아니라 1.38MB다.
#
# apt-get download가 의존을 안 따라가는 것이 여기서 값을 낸다. 라이브러리
# 넷을 손으로 안 적으면 make_initrd.sh가 그 SONAME을 찍고 즉시 죽는다 —
# 게스트가 부팅한 뒤 그 명령을 처음 칠 때가 아니라 빌드 때 드러난다.
#
# ── UT-M2: 층 2(모던 13개)와 라이브러리 열아홉 ──────────────────────────
#
# 도구 13에 딸려 오는 새 SONAME을 2026-09-11에 컨테이너 안에서 다시 쟀다.
# 바이너리의 DT_NEEDED만 보지 않고 .so의 DT_NEEDED까지 재귀로 봤다 —
# UT-M1이 libsystemd를 놓쳤던 자리이고(design 실측 22), M2는 라이브러리를
# 열아홉 더하므로 같은 누락의 값이 훨씬 비싸다.
#
#   libgit2 사슬 16   eza · bat 둘이 데려온다. design 실측 5는 15라고 적었고
#                     그 표에 libresolv.so.2가 없다 — libkrb5가 데려온다.
#                     libresolv는 libc6이 담고 있어 여기 안 적는다.
#   libncursesw6      htop · ncdu
#   libjq1 · libonig5 jq (libonig는 libjq가 데려온다)
#   libstdc++6        btop 하나뿐이다. btop을 빼는 사람은 이 줄도 뺀다
#
# libcrypto.so.3 하나가 6.5MB로 가장 크다. 네트워크가 없는 기계가 TLS·
# Kerberos·SSH 스택을 지는 것이고, 사용자가 그 대가를 알고 Debian 경로를
# 유지하기로 정했다(design 결정 3).
#
# 버전이 이름에 박힌 패키지가 넷이다(libgit2-1.9 · libssh2-1t64 ·
# libssl3t64 · libmbedtls21/libmbedx509-7/libmbedcrypto16). trixie가 올라가면
# apt가 "없는 패키지"라고 죽는다 — 그때는 `apt-cache search` 한 번으로 새
# 이름을 찾아 여기를 고치면 된다. 조용히 실패하지 않는다.
#
# ── UT-M3: 층 3(git · vim.tiny)과 라이브러리 0 ──────────────────────
#
# 줄 둘이 전부다. 착수 전에 M2와 똑같은 규칙으로(.so의 DT_NEEDED까지
# 재귀) closure를 쟀고 새 SONAME이 하나도 없었다.
#
#   git        libpcre2-8 · libz · libc      셋 다 이미 있다
#              (libz는 eza·bat의 libgit2 사슬이 데려와 있다)
#   vim.tiny   libm · libtinfo · libselinux · libacl   넷 다 이미 있다
#              (libacl은 sed가, libselinux는 fish가 데려왔다)
#
# design의 "층 3은 새 라이브러리가 없다"가 M1·M2에서는 두 번 다 틀렸고
# 여기서 처음 맞았다. 그래도 재고 나서 알았다는 것이 이 주석의 요지다 —
# 30초짜리 확인을 건너뛰면 맞는 날과 틀린 날이 구별되지 않는다.
#
# git 패키지의 나머지는 안 쓴다. /usr/lib/git-core의 168 항목 중
# 141이 심볼릭 링크이고 실체는 26이다(design 실측 7은 "하드링크"라고
# 적었는데 trixie에서는 심볼릭 링크다 — 결론은 같다). 실체 26 중 큰 것
# 일곱(약 16MB)이 design 결정 5가 뺀 네트워크 헬퍼이고, init·add·commit·
# log·diff·branch는 전부 git 바이너리 안의 builtin이라 그 트리가 통째로
# 없어도 돈다. .deb는 통째로 풀되 initrd에는 guest_tools.sh가 적은 둘만
# 들어간다 — 푸는 자리(sysroot)와 넣는 자리(initrd)가 다른 것이 이 구조의
# 값이다.
#
# ── NW-M2: 층 5(네트워크 넷)와 라이브러리 스물 ──────────────────────────
#
# 도구 넷을 더한다. 이 목록에서 도구 하나가 라이브러리를 데려오는 비율이
# 가장 극단적으로 갈리는 층이다.
#
#   dhcpcd-base          주소를 받는 것 전부. 새 라이브러리 0개
#   iproute2             ip. 사람이 주소를 눈으로 보는 도구. 새 라이브러리 셋
#   netcat-traditional   nc. 연결이 되는지 묻는 도구. 새 라이브러리 0개
#   curl                 밖으로 나가는 도구. 새 라이브러리 스물
#
# procps는 안 더한다 — 이미 있다(UT-M1이 ps·top 때문에 받았다). 층 5가
# 쓰는 pgrep·kill이 같은 패키지에서 오므로 그 둘이 공짜다.
#
# dhcpcd가 0개인 것이 이 milestone이 착수 전에 배운 것이다. apt는
# dhcpcd-base가 libssl3t64와 libudev1을 요구한다고 말하는데, 바이너리의
# DT_NEEDED에는 libcrypto.so.3과 libc.so.6 둘뿐이고 둘 다 이미 있다.
# libssl·libudev는 dlopen으로 열리는 udev 플러그인 몫이라 copy_lib_deps가
# 따라오지도 않는다. 패키지 의존과 바이너리 의존이 다르다는 것이고,
# 도구를 저울질할 때 보는 것은 apt-cache show의 Installed-Size가 아니라
# readelf -d의 DT_NEEDED다.
#
# curl 하나가 이 블록이 길어진 이유 전부다. 스물 중 열여덟이 TLS와 그
# 아래의 암호 사슬이고(gnutls → nettle·hogweed·gmp·tasn1·p11-kit·ffi ·
# idn2 → unistring · ldap → sasl2 · brotli · nghttp2·nghttp3 · rtmp · psl),
# 푼 것 기준 10,927,904바이트다. 사용자가 그 값을 알고 넣기로 정했다.
#
# ip의 셋은 libbpf·libelf·libmnl이다. libelf1t64는 컨테이너 쪽
# libelf-dev(커널 빌드가 쓴다)와 다른 물건이다 — 이쪽은 amd64 sysroot에
# 풀리는 런타임 라이브러리다. curl도 같은 자리에 이름이 둘이다: 위
# apt-get install의 curl은 컨테이너(arm64)가 zig를 받는 데 쓰는 것이고,
# 아래 curl:amd64는 게스트에 들어갈 x86_64 바이너리다.
#
# 이름에 버전이 박힌 것이 여섯이다(libcurl4t64 · libpsl5t64 ·
# libgnutls30t64 · libnettle8t64 · libhogweed6t64 · libelf1t64). UT-M2의
# 넷과 같은 성질이고, trixie가 올라가면 apt가 "없는 패키지"라고 죽는다.
# 조용히 실패하지 않는다.
#
# ── TS-M3: 층 6(시간대 데이터) ──────────────────────────────────────────
#
# tzdata 하나다. Architecture: all이라 `:amd64`를 안 붙인다 — fish-common ·
# zsh-common · ncurses-base와 같은 줄이다. 바이너리가 아니라 데이터라 새
# 라이브러리가 0개이고, 푼 것이 2.1MB · initrd에서 약 171KB다(TS 확인 8).
#
# 컨테이너 자신의 /usr/share/zoneinfo와 바이트까지 같은 파일들이다. 그래도
# sysroot를 거치게 하는 이유가 TS design 결정 10이다 — 게스트에 들어가는
# 파일의 출처가 하나여야 make_initrd.sh를 읽는 사람이 "이 파일은 어디서
# 왔나"를 한 자리에서 답한다.
#
# trixie는 옛 이름(US/Pacific · Japan 같은 것)을 tzdata-legacy로 갈라
# 두었다. 안 받는다 — 지역/도시 꼴의 이름이 전부 tzdata에 있다.
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
# 아래 라이브러리 일곱은 apt가 저 셋의 Depends·Pre-Depends로 적은 것에서
# 이미 sysroot에 있는 것(libcom-err2 · libncursesw6 · libtinfo6)과 mke2fs가
# 안 부르는 것(libss2 — debugfs의 것이다)을 뺀 것이다. libext2fs2t64 하나가
# libext2fs.so.2와 libe2p.so.2를 둘 다 싣는다 — trixie에 libe2p2라는
# 패키지는 없다. 실제로 initrd에 딸려 오는 수는 copy_lib_deps가 DT_NEEDED로
# 센 만큼이고 그 수는 guest_tools.sh 층 7 주석에 있다.
#
# libblkid1 · libmount1 · libsmartcols1 · libuuid1이 지금까지 없었다는 것이
# DI-M0이 착수 전에 배운 것이다 — util-linux:amd64는 dmesg 하나 때문에
# 통째로 받았고, 그 안의 blkid·lsblk는 바이너리만 풀려 있었지 부를
# 라이브러리가 없어서 게스트에서 돌 수 없는 상태였다.
ENV AMD64_SYSROOT=/usr/local/amd64-sysroot

RUN dpkg --add-architecture amd64 \
    && apt-get update \
    && mkdir -p /tmp/debs "$AMD64_SYSROOT" \
    && (cd /tmp/debs && apt-get download \
        fish:amd64 \
        fish-common \
         bash:amd64 \
        zsh:amd64 \
        zsh-common \
        ncurses-base \
        libtinfo6:amd64 \
        libcap2:amd64 \
        coreutils:amd64 \
        grep:amd64 \
        findutils:amd64 \
        sed:amd64 \
        mawk:amd64 \
        diffutils:amd64 \
        less:amd64 \
        procps:amd64 \
        util-linux:amd64 \
        eza:amd64 \
        bat:amd64 \
        fd-find:amd64 \
        ripgrep:amd64 \
        sd:amd64 \
        htop:amd64 \
        btop:amd64 \
        tree:amd64 \
        duf:amd64 \
        ncdu:amd64 \
        jq:amd64 \
        hyperfine:amd64 \
        git:amd64 \
        vim-tiny:amd64 \
        zoxide:amd64 \
        fzf:amd64 \
        libgit2-1.9:amd64 \
        libgssapi-krb5-2:amd64 \
        libkrb5-3:amd64 \
        libk5crypto3:amd64 \
        libkrb5support0:amd64 \
        libcom-err2:amd64 \
        libkeyutils1:amd64 \
        libmbedtls21:amd64 \
        libmbedx509-7:amd64 \
        libmbedcrypto16:amd64 \
        libhttp-parser2.9:amd64 \
        libssh2-1t64:amd64 \
        libssl3t64:amd64 \
        libzstd1:amd64 \
        zlib1g:amd64 \
        libncursesw6:amd64 \
        libjq1:amd64 \
        libonig5:amd64 \
        libstdc++6:amd64 \
        libacl1:amd64 \
        libattr1:amd64 \
        libproc2-0:amd64 \
        libsystemd0:amd64 \
        libc6:amd64 \
        libc-bin:amd64 \
        libgcc-s1:amd64 \
        libpcre2-8-0:amd64 \
        libpcre2-32-0:amd64 \
        libselinux1:amd64 \
        dhcpcd-base:amd64 \
        iproute2:amd64 \
        netcat-traditional:amd64 \
        curl:amd64 \
        libcurl4t64:amd64 \
        libnghttp2-14:amd64 \
        libnghttp3-9:amd64 \
        libidn2-0:amd64 \
        libunistring5:amd64 \
        librtmp1:amd64 \
        libpsl5t64:amd64 \
        libgnutls30t64:amd64 \
        libp11-kit0:amd64 \
        libnettle8t64:amd64 \
        libhogweed6t64:amd64 \
        libgmp10:amd64 \
        libtasn1-6:amd64 \
        libffi8:amd64 \
        libldap2:amd64 \
        libsasl2-2:amd64 \
        libbrotli1:amd64 \
        libbpf1:amd64 \
        libelf1t64:amd64 \
        libmnl0:amd64 \
        fdisk:amd64 \
        dosfstools:amd64 \
        e2fsprogs:amd64 \
        libfdisk1:amd64 \
        libmount1:amd64 \
        libsmartcols1:amd64 \
        libblkid1:amd64 \
        libuuid1:amd64 \
        libreadline8t64:amd64 \
        libext2fs2t64:amd64 \
        tzdata) \
    && for deb in /tmp/debs/*.deb; do dpkg -x "$deb" "$AMD64_SYSROOT"; done \
    && rm -rf /tmp/debs /var/lib/apt/lists/*

ENV ZIG_VERSION=0.16.0 \
    PATH=/usr/local/zig:$PATH

RUN curl -sSL -o /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-aarch64-linux-${ZIG_VERSION}.tar.xz" \
    && mkdir -p /usr/local/zig \
    && tar -xJf /tmp/zig.tar.xz -C /usr/local/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz

WORKDIR /workspace
