# 호스트(Apple Silicon)와 같은 arm64로 돈다. 예전에는
# `--platform=linux/amd64`가 붙어 있어서 컴파일러와 QEMU 바이너리 자체가
# Rosetta 에뮬레이션을 통과했고, 그 안에서 다시 x86_64 게스트를 TCG로
# 돌렸다(에뮬레이터의 에뮬레이션). 게스트용 x86_64 산출물은 이제 전부
# 크로스 컴파일이거나 amd64 패키지에서 조달한다 — ZM-M3.
FROM debian:trixie-slim

# RM-M0이 ovmf를 더한다. 게이트의 아홉 체인은 전부 QEMU의 기본 BIOS(SeaBIOS)로
# 부팅하는데, 실머신 노트북은 예외 없이 UEFI다. ovmf는 EDK II를 미리 빌드해 둔
# 펌웨어 이미지(/usr/share/OVMF/OVMF_CODE_4M.fd)라서 **Architecture: all이다** —
# 컨테이너가 arm64인데도 x86_64 게스트용 펌웨어가 그대로 깔린다. 3.6MB다.
#
# UT-M1이 zstd를 더한다. **어떤 빌드 단계도 이것을 부르지 않는다** — 재는
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
# HI-M1이 libc-bin을 더한다. **libc6에는 로케일 데이터가 없다** — Debian은
# 미리 컴파일된 /usr/lib/locale/C.utf8을 libc-bin에 담는다. 그것이 없으면
# 게스트에 UTF-8 로케일이 아예 없고, 셸의 `setlocale`이 실패해서 **fish가
# 우리가 보낸 한글 세 바이트를 한 글자가 아니라 바이트 셋으로 읽는다.**
# 증상은 "입력이 안 된다"가 아니라 **명령줄의 앞 글자가 지워지는 것**이다 —
# fish가 바이트마다 폭을 세어(0x80~0x9F는 0칸, 0xA0 이상은 1칸) 커서를
# 두 칸짜리 글자의 가운데에 세우고 거기에 다음 글자를 쓰기 때문이다.
# ncurses-base와 같은 종류의 항목이다: **우리가 게스트에게 한 말을 참으로
# 만들어 주는 데이터.**
#
# UT-M1이 층 1(GNU 한 벌)을 더한다 — **UT가 이 목록을 처음 넓히는 자리다.**
# coreutils는 이미 있었고(UT-M0 전부터), 없던 것은 별도 패키지 여덟이다:
# grep · findutils(find·xargs) · sed · mawk(awk) · diffutils(diff·cmp) ·
# less · procps(ps·top) · util-linux(dmesg 하나 때문에 받는다).
#
# 라이브러리 넷이 따라온다. **design 실측 3은 둘이라고 적었는데 그것이
# 불완전했다** — 바이너리의 DT_NEEDED만 보고 .so의 DT_NEEDED를 안 봤다.
#
#   libacl1     sed·cp·mv
#   libattr1    coreutils(cp·mv 계열). 실측 3에 없던 이름이다
#   libproc2-0  ps·top
#   libsystemd0 **libproc2가 데려온다.** 이것도 실측 3에 없었다
#
# libsystemd는 lzma·zstd·gcrypt를 dlopen으로만 열고 DT_NEEDED에는
# libcap·libm·libc뿐이다(libcap은 zsh가 이미 데려와 있다). 저널 압축을 쓸
# 때만 열리는 경로이고 ps/top은 저널을 안 본다 — 그래서 copy_lib_deps가
# 따라가는 사슬은 4.2MB가 아니라 1.38MB다.
#
# **apt-get download가 의존을 안 따라가는 것이 여기서 값을 낸다.** 라이브러리
# 넷을 손으로 안 적으면 make_initrd.sh가 그 소네임을 찍고 즉시 죽는다 —
# 게스트가 부팅한 뒤 그 명령을 처음 칠 때가 아니라 빌드 때 드러난다.
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
        libacl1:amd64 \
        libattr1:amd64 \
        libproc2-0:amd64 \
        libsystemd0:amd64 \
        libc6:amd64 \
        libc-bin:amd64 \
        libgcc-s1:amd64 \
        libpcre2-8-0:amd64 \
        libpcre2-32-0:amd64 \
        libselinux1:amd64) \
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
