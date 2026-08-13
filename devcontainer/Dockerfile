# 호스트(Apple Silicon)와 같은 arm64로 돈다. 예전에는
# `--platform=linux/amd64`가 붙어 있어서 컴파일러와 QEMU 바이너리 자체가
# Rosetta 에뮬레이션을 통과했고, 그 안에서 다시 x86_64 게스트를 TCG로
# 돌렸다(에뮬레이터의 에뮬레이션). 게스트용 x86_64 산출물은 이제 전부
# 크로스 컴파일이거나 amd64 패키지에서 조달한다 — ZM-M3.
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gcc-multilib-x86-64-linux-gnu \
        binutils \
        qemu-system-x86 \
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
ENV AMD64_SYSROOT=/usr/local/amd64-sysroot

RUN dpkg --add-architecture amd64 \
    && apt-get update \
    && mkdir -p /tmp/debs "$AMD64_SYSROOT" \
    && (cd /tmp/debs && apt-get download \
        fish:amd64 \
        fish-common \
        coreutils:amd64 \
        libc6:amd64 \
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
