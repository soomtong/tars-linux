#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# initrd에 들어가는 유저랜드는 전부 x86_64다. 빌드 컨테이너는 ZM-M3부터
# arm64라서 컨테이너 자신의 /usr/bin/fish를 복사할 수 없다 — Dockerfile이
# 구워둔 amd64 sysroot에서만 가져온다. 여기서 실패하면 게이트가 엉뚱한
# 곳(부팅 후 로더 에러)에서 죽으므로 시작 전에 확인한다.
SYSROOT="${AMD64_SYSROOT:-/usr/local/amd64-sysroot}"
if [ ! -d "$SYSROOT" ]; then
  echo "make_initrd: amd64 sysroot not found at ${SYSROOT}" >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# "찾는 곳"과 "넣는 곳"을 분리한다.
#
# 찾는 곳: sysroot는 .deb를 푼 자리라 usrmerge 규칙대로 /usr/lib/... 이다.
# 넣는 곳: initrd 안은 /lib/x86_64-linux-gnu로 고정한다 — 옛 방식(ldd)이
#          알려준 경로가 /lib/... 이었고 지금 부팅되는 initrd가 그 모양이다.
# 둘을 같게 만들면(=찾은 자리에 그대로 복사) 게스트 로더는 /usr/lib도 뒤지니
# 부팅은 되겠지만, 파일 경로가 통째로 바뀌어 옛 initrd와 대조가 불가능해진다.
LIB_DEST=/lib/x86_64-linux-gnu

find_in_sysroot() {
  local soname="$1" dir
  for dir in /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/lib64 /lib64; do
    if [ -e "${SYSROOT}${dir}/${soname}" ]; then
      echo "${SYSROOT}${dir}/${soname}"
      return 0
    fi
  done
  return 1
}

# 예전에는 ldd를 썼다. ldd는 대상 바이너리를 실제 동적 로더에 태워서 답을
# 얻는 것이라, arm64 호스트에서 x86_64 바이너리에는 쓸 수 없다. readelf는
# 파일을 읽기만 하므로 아키텍처와 무관하다. 대신 두 가지를 직접 해야 한다 —
# (1) 인터프리터는 DT_NEEDED가 아니라 PT_INTERP에 있어서 따로 봐야 하고,
# (2) 의존의 의존은 재귀로 따라가야 한다. ldd는 둘 다 대신 해줬었다.
copy_lib_deps() {
  local bin="$1" interp src soname dest

  interp="$(readelf -p .interp "$bin" 2>/dev/null | grep -oE '/[^ ]*ld-linux[^ ]*' || true)"
  if [ -n "$interp" ] && [ ! -e "${WORKDIR}${interp}" ]; then
    if ! src="$(find_in_sysroot "$(basename "$interp")")"; then
      echo "make_initrd: cannot resolve interpreter ${interp} (needed by ${bin})" >&2
      exit 1
    fi
    mkdir -p "${WORKDIR}$(dirname "$interp")"
    cp "$src" "${WORKDIR}${interp}"
  fi

  for soname in $(readelf -d "$bin" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
    # 로더는 위에서 PT_INTERP가 지정한 자리(/lib64)에 이미 넣었다. DT_NEEDED에
    # 로더를 또 적어두는 바이너리가 있는데, 그대로 처리하면 /lib/x86_64-linux-gnu
    # 에 사본이 하나 더 생긴다. ldd는 소네임을 절대 경로로 해석해 돌려주므로
    # 이 중복이 드러나지 않았다.
    case "$soname" in ld-linux*) continue ;; esac

    dest="${WORKDIR}${LIB_DEST}/${soname}"
    if [ ! -e "$dest" ]; then
      if ! src="$(find_in_sysroot "$soname")"; then
        echo "make_initrd: cannot resolve ${soname} (needed by ${bin}) in ${SYSROOT}" >&2
        echo "             add the package that provides it to devcontainer/Dockerfile" >&2
        exit 1
      fi
      mkdir -p "${WORKDIR}${LIB_DEST}"
      cp "$src" "$dest"
      copy_lib_deps "$src"
    fi
  done
}

mkdir -p "$WORKDIR/usr/bin" "$WORKDIR/proc" "$WORKDIR/sys" "$WORKDIR/dev" \
         "$WORKDIR/config"

cp ../init/zig-out/bin/init "$WORKDIR/init"
chmod 0755 "$WORKDIR/init"

# terminal은 Debug 빌드라 42MB이고 대부분이 디버그 심볼이다. strip하면
# initrd가 6.5MB까지 줄지만(부팅 25초 → 34초 차이), 심볼을 남긴다 —
# strip한 바이너리에서는 QEMU 안의 에러 트레이스가 원리적으로 복구
# 불가능해지기 때문이다. 단, 심볼이 있다고 트레이스가 바로 읽히지는
# 않았다(2026-08-12 TF-M4 실측: strip 버전은 `???` 주소 두 줄, 심볼 버전은
# 트레이스 자체가 없었다 — 원인 미규명). 크기는 아래 gzip으로 처리한다.
cp ../terminal/zig-out/bin/terminal "$WORKDIR/terminal"
chmod 0755 "$WORKDIR/terminal"

mkdir -p "$WORKDIR/vendor/fonts"
cp ../terminal/vendor/fonts/Hanme_8x4x4.ttf "$WORKDIR/vendor/fonts/Hanme_8x4x4.ttf"

cp "$SYSROOT/usr/bin/fish" "$WORKDIR/usr/bin/fish"
chmod 0755 "$WORKDIR/usr/bin/fish"

# CP-M2: 설정으로 고를 수 있는 셸 셋. initrd 안의 자리는 sysroot의 원래
# 자리와 무관하게 우리가 정한다 — init/src/config.zig의 Shell.path()가
# 여기와 같은 경로를 돌려줘야 한다. 둘이 어긋나면 부팅 후 "execve failed"로만
# 나타난다.
cp "$SYSROOT/usr/bin/bash" "$WORKDIR/usr/bin/bash"
cp "$SYSROOT/usr/bin/zsh" "$WORKDIR/usr/bin/zsh"
chmod 0755 "$WORKDIR/usr/bin/bash" "$WORKDIR/usr/bin/zsh"

cp "$SYSROOT/usr/bin/cat" "$WORKDIR/usr/bin/cat"
cp "$SYSROOT/usr/bin/uname" "$WORKDIR/usr/bin/uname"
cp "$SYSROOT/usr/bin/mkdir" "$WORKDIR/usr/bin/mkdir"
# IP-M0: 게이트가 Ctrl+C로 죽일 자식이 필요하다. 프롬프트에서 줄이
# 취소되는 것만 보면 "셸이 바이트를 받았다"까지만 증명된다 — 커널이
# foreground process group에 SIGINT를 보낸다는 것(design doc 결정 3)을
# 검사하려면 셸이 아닌 프로세스가 하나 떠 있어야 한다. coreutils는 이미
# sysroot에 있으므로 Dockerfile은 건드리지 않는다.
cp "$SYSROOT/usr/bin/sleep" "$WORKDIR/usr/bin/sleep"
chmod 0755 "$WORKDIR/usr/bin/cat" "$WORKDIR/usr/bin/uname" \
           "$WORKDIR/usr/bin/mkdir" "$WORKDIR/usr/bin/sleep"

# init은 libc를 링크하지 않는 정적 바이너리라 copy_lib_deps가 필요 없다
# (ZM-M1). 나머지는 전부 glibc 동적 링크다.
copy_lib_deps "$WORKDIR/terminal"
copy_lib_deps "$WORKDIR/usr/bin/fish"
copy_lib_deps "$WORKDIR/usr/bin/bash"
copy_lib_deps "$WORKDIR/usr/bin/zsh"
copy_lib_deps "$WORKDIR/usr/bin/cat"
copy_lib_deps "$WORKDIR/usr/bin/uname"
copy_lib_deps "$WORKDIR/usr/bin/mkdir"
copy_lib_deps "$WORKDIR/usr/bin/sleep"

# /usr/share/fish/*는 fish 패키지가 아니라 fish-common(arch: all)이 준다.
mkdir -p "$WORKDIR/usr/share/fish"
cp -r "$SYSROOT/usr/share/fish/functions" "$WORKDIR/usr/share/fish/"
cp "$SYSROOT/usr/share/fish/config.fish" "$WORKDIR/usr/share/fish/"
cp "$SYSROOT/usr/share/fish/__fish_build_paths.fish" "$WORKDIR/usr/share/fish/"

# IP-M1: terminal이 PTY 셸의 TERM을 xterm으로 바꾸므로(design doc 결정 7)
# 그 terminfo가 게스트에 있어야 한다. 없으면 부팅은 계속되고 셸이 능력을
# 덜 쓸 뿐이다 — **조용한 실패**라서 input/check.sh가 initrd 목록을 직접
# 확인한다.
#
# 디렉터리를 통째로 복사하지 않고 파일 하나(3977B)만 넣는다. ncurses-base의
# /usr/share/terminfo에는 수백 개가 들어 있고 우리가 광고하는 이름은
# 하나뿐이다. 시리얼 콘솔 셸이 쓰는 `linux`는 넣지 않는다 — 그쪽은 terminfo
# 없이도 지금까지 잘 돌아왔고, 넣는 순간 "무엇이 왜 필요한가"가 흐려진다.
mkdir -p "$WORKDIR/usr/share/terminfo/x"
cp "$SYSROOT/usr/share/terminfo/x/xterm" "$WORKDIR/usr/share/terminfo/x/xterm"

# zsh는 바이너리 하나가 아니다. zle(줄 편집), complete, parameter 같은
# "내장처럼 보이는" 기능 대부분이 실행 중에 dlopen되는 .so 모듈이고, 그것을
# 찾을 자리(module_path)는 zsh 안에 컴파일 타임에 박혀 있다. 그래서 이 트리만은
# initrd 안에서도 **sysroot와 같은 경로**를 유지해야 한다 — 다른 라이브러리처럼
# /lib/x86_64-linux-gnu로 모으면 zsh가 영영 못 찾는다.
mkdir -p "$WORKDIR/usr/lib/x86_64-linux-gnu"
cp -r "$SYSROOT/usr/lib/x86_64-linux-gnu/zsh" "$WORKDIR/usr/lib/x86_64-linux-gnu/"

# 38개 중 둘만 sysroot에 없는 라이브러리를 요구한다(2026-08-14 실측):
# zsh/curses는 libncursesw.so.6, zsh/db/gdbm은 libgdbm.so.6. 둘 다 zmodload로
# 이름을 대고 부를 때만 열리는 선택적 모듈이라 우리 셸은 부를 일이 없다.
# 라이브러리 두 개를 게스트에 들이는 대신 모듈을 뺀다 — 남겨두면 아래
# copy_lib_deps가 그 소네임을 찍고 즉시 죽는다(그게 정상 동작이다).
rm -f  "$WORKDIR/usr/lib/x86_64-linux-gnu/zsh/"*/zsh/curses.so
rm -rf "$WORKDIR/usr/lib/x86_64-linux-gnu/zsh/"*/zsh/db

# 모듈도 각자 동적 의존을 갖는다. 바이너리에만 copy_lib_deps를 돌리면 빠진
# 라이브러리가 **부팅 후 dlopen 시점에야** 드러나고, 그 실패는 로그에서
# 알아보기 어렵다. 여기서 돌려야 make_initrd.sh가 소네임을 찍고 즉시 죽는다.
while IFS= read -r mod; do
  copy_lib_deps "$mod"
done < <(find "$WORKDIR/usr/lib/x86_64-linux-gnu/zsh" -name '*.so')

# /usr/share/zsh(zsh-common)는 **넣지 않는다.** fish가 fish-common을 필요로
# 했던 것과 같은 구조이긴 한데 크기가 다르다 — 17MB이고 대부분이 완성
# 함수(Completion)다. zsh는 이 트리가 없어도 조용히 시작한다: 여기 있는 것은
# 전부 fpath에서 autoload되는 함수이고, ~/.zshrc가 없는 우리 게스트에서는
# compinit도 promptinit도 불리지 않는다. 필요해지면 아래 한 줄을 살린다
# (패키지는 이미 sysroot에 구워져 있으므로 네트워크 없이 켤 수 있다).
#
#   cp -r "$SYSROOT/usr/share/zsh" "$WORKDIR/usr/share/"

# gzip으로 압축해 둔다. 커널은 initramfs의 magic을 보고 알아서 푼다
# (CONFIG_RD_GZIP=y). 파일명은 initrd.cpio 그대로 유지한다 — limine.conf와
# 두 check 스크립트가 이 이름을 참조하기 때문이다. 압축이 필요한 이유는 BF
# 체인인데, limine이 BIOS INT13h로 ISO에서 읽는 경로가 에뮬레이션에서
# 극단적으로 느려 53MB(TF-M2 시절 측정)에서는 부팅조차 못 했다. 그 뒤 init이
# Rust에서 Zig 디버그 빌드(11.6MB)로 바뀌고 CP-M2가 셸 셋을 담으면서 지금은
# 67.6MB → gzip 15.5MB다(2026-08-14 실측). 갱신할 때는 cpio가 찍는 blocks 수
# (×512B)와 `ls -l initrd.cpio`를 함께 본다.
(cd "$WORKDIR" && find . | cpio -o -H newc) | gzip -9 > initrd.cpio
