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

# UT-M0이 /bin · /tmp · /etc 셋을 더한다. 지금까지 없었고, 그 없음이 git에
# 그대로 걸린다(design 실측 2).
#
#   /bin   → sh 하나만 산다. #!/bin/sh 스크립트와 git의 셸 서브커맨드가
#            이 경로를 컴파일 타임에 박아 두고 찾는다.
#   /tmp   → git도 편집기도 임시 파일을 여기 만든다. 없으면 조용히 실패한다.
#   /etc   → passwd·group. whoami가 이름을 내고, git이 커밋 작성자를
#            유추할 자리다.
mkdir -p "$WORKDIR/usr/bin" "$WORKDIR/proc" "$WORKDIR/sys" "$WORKDIR/dev" \
         "$WORKDIR/config" "$WORKDIR/bin" "$WORKDIR/tmp" "$WORKDIR/etc"

# /tmp는 아무나 쓰고 남의 것은 못 지운다. 게스트가 지금은 root 하나뿐이라
# 동작 차이가 없지만, 이 비트가 없는 /tmp를 보고 겁내는 프로그램이 있다.
chmod 1777 "$WORKDIR/tmp"

cp ../init/zig-out/bin/init "$WORKDIR/init"
chmod 0755 "$WORKDIR/init"

# GL-M3(2026-08-29)에서 terminal이 ReleaseSafe가 됐다. 49,373,565 →
# 10,577,208바이트이고, 이 파일이 만드는 initrd는 16,199,658 →
# 10,988,773바이트다. 모드를 정하는 자리는 terminal/build.zig의
# `guest-optimize` 옵션이고 기본값이 ReleaseSafe다.
#
# **strip은 여전히 안 한다.** ReleaseSafe가 심볼을 지우지 않고도 78.6%를
# 줄이므로 strip을 검토할 이유가 없어졌다 — `readelf -S`로 확인하면
# `.debug_info`를 포함한 `.debug_*` 섹션 열 개가 그대로 있다.
#
# 옛 주석은 "심볼을 남기는 이유는 에러 트레이스"라고 적고 바로 다음 문장에서
# "단, 심볼이 있다고 트레이스가 바로 읽히지는 않았다"고 스스로를 부정하고
# 있었다 — 2026-08-12 TF-M4 실측에서 strip 버전은 `???` 주소 두 줄, 심볼
# 버전은 트레이스 자체가 없었다. **그 이유는 지금도 규명되지 않았고, Debug
# 에서도 안 읽혔으므로 ReleaseSafe에서 안 읽히는 것은 회귀가 아니다.**
cp ../terminal/zig-out/bin/terminal "$WORKDIR/terminal"
chmod 0755 "$WORKDIR/terminal"

mkdir -p "$WORKDIR/vendor/fonts"
cp ../terminal/vendor/fonts/unifont.otf "$WORKDIR/vendor/fonts/unifont.otf"

# init은 libc를 링크하지 않는 정적 바이너리라 copy_lib_deps가 필요 없다
# (ZM-M1). terminal은 glibc 동적 링크다.
copy_lib_deps "$WORKDIR/terminal"

# ── 유저랜드 바이너리 ────────────────────────────────────────────────────
#
# UT-M1 결정 7. **목록은 여기 없다** — guest_tools.sh의 GUEST_TOOLS 배열
# 하나이고, tools/check.sh가 같은 파일을 source해서 initrd 목록을 검사한다.
#
# 예전에는 바이너리 하나마다 cp·chmod·copy_lib_deps 세 줄을 이 자리에 손으로
# 썼다. 여덟 개일 때는 읽혔지만 50개는 못 읽고, 손으로 쓰는 한 `cp`는 했는데
# `copy_lib_deps`를 빼먹는 실수가 언제든 난다 — 그 실패는 빌드 때가 아니라
# **게스트가 그 명령을 처음 칠 때** 나타난다(design 위험 3). 루프 하나로
# 두면 빼먹을 자리가 없어진다.
install_tool() {
  local src="$SYSROOT/$1" dest="$WORKDIR/$2"

  # 없는 것을 조용히 건너뛰지 않는다. 게스트가 그 명령을 못 찾는 것은 부팅
  # 20분 뒤에 사람이 발견하는 실패이고, 여기서 죽으면 30초 뒤에 드러난다.
  if [ ! -f "$src" ]; then
    echo "make_initrd: ${1} not found in ${SYSROOT}" >&2
    echo "             add the package that provides it to devcontainer/Dockerfile" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  chmod 0755 "$dest"
  # copy_lib_deps는 이미 있는 소네임을 건너뛰므로 배열의 순서는 상관없다.
  copy_lib_deps "$dest"
}

. ./guest_tools.sh

for entry in "${GUEST_TOOLS[@]}"; do
  install_tool "${entry%%:*}" "${entry#*:}"
done

# /bin/sh는 **언제나 bash다.** tars.conf의 shell 설정과 무관하다 —
# #!/bin/sh 스크립트의 동작이 사용자의 셸 취향에 따라 달라지면 안 된다
# (design 결정 6). 셋 중 bash만이 POSIX sh 모드를 갖는다.
#
# 상대 경로로 건다. cpio가 링크의 내용을 그대로 담고 게스트의 루트가
# 곧 이 트리라 절대 경로도 맞지만, 상대로 두면 이 트리를 다른 자리에
# 풀어 봐도 끊어지지 않는다.
ln -sf ../usr/bin/bash "$WORKDIR/bin/sh"

# UT-M3. **vi와 vim은 한 실체다**(design 결정 4). guest_tools.sh에 줄을 둘
# 적으면 install_tool이 cp를 두 번 해서 1.76MB짜리 사본이 두 벌 생긴다 —
# 같은 파일에 이름이 둘 있는 것을 파일 둘로 만드는 것은 파일 시스템에
# 대한 거짓말이다. 위 /bin/sh가 이미 그 모양을 세워 뒀다.
ln -sf vim "$WORKDIR/usr/bin/vi"

# UT-M3. **Debian git의 기본 페이저는 `less`가 아니라 `pager`다** — alternatives
# 이름이고 postinst가 만드는 링크라 dpkg -x로 푼 sysroot에 없다. 2026-09-11에
# 게스트에서 직접 봤다:
#
#   root@(none) /t/r (main)# git log
#   error: cannot run pager: No such file or directory
#   fatal: unable to execute pager 'pager'
#
# **매달리는 것이 아니라 죽는다.** 그래서 게이트는 안 깨지고 사람만 깨진다 —
# `git log`·`git diff`·`git branch -a`가 전부 이 경로다. mawk→awk ·
# fdfind→fd · vim.tiny→vi와 **같은 종류**(결정 4)이고, 다른 것은 이 이름을
# 우리가 고른 것이 아니라 **git 바이너리가 컴파일 타임에 박아 뒀다**는 점이다.
ln -sf less "$WORKDIR/usr/bin/pager"

# 같은 종류가 하나 더 있다. 게스트에게 직접 물어서 알았다:
#
#   root@(none) ~# git var -l
#   GIT_EDITOR=editor        GIT_SEQUENCE_EDITOR=editor        GIT_PAGER=pager
#
# `git commit`을 -m 없이 치는 것 · `git rebase -i` · `git config --edit`가
# 전부 이 이름을 부른다. **vim은 이제 이름이 셋이고 실체는 하나다**
# (vim · vi · editor).
ln -sf vim "$WORKDIR/usr/bin/editor"

# UT-M3 결정 8. git은 전역 설정을 $HOME/.gitconfig에서 읽고 게스트의 HOME은
# /다. 그런데 /는 tmpfs라 **재부팅하면 사라진다** — 영속하는 것은 설정
# 디스크를 마운트하는 /config 하나뿐이고 그것은 읽기·쓰기다
# (init/src/main.zig가 MS_RDONLY 없이 마운트한다).
#
# **그래서 링크 하나로 잇는다.** GIT_CONFIG_GLOBAL 환경변수를 쓰는 쪽은
# "그 변수를 어디서 넣을까"(PID 1인지 terminal인지)를 또 정해야 하고,
# 그것은 결정 1이 PATH에 대해 이미 치른 비용을 한 번 더 치르는 일이다.
# 새 코드 경로가 없다.
#
# 상대 경로인 이유는 /bin/sh와 같다 — 이 트리를 다른 자리에 풀어도 안
# 끊어진다.
#
# **설정 디스크를 못 찾으면?** /config는 initrd 안의 빈 디렉터리로 남고
# 링크는 거기를 가리킨다. git이 쓰면 tmpfs에 쓰이고 재부팅하면 사라진다 —
# **부팅을 막지 않는다**는 것이 RM-M2가 라벨을 못 찾았을 때와 같은 모양이다.
ln -sf config/gitconfig "$WORKDIR/.gitconfig"

# git init이 새 저장소에 복사하는 템플릿(hooks 샘플 13 · info/exclude ·
# description). **26,140바이트이고, 없으면 git init이 매번 경고를 찍는다** —
# `warning: templates not found in /usr/share/git-core/templates`. 저장소는
# 그래도 만들어지지만, 개발용이라고 부르는 기계가 git init마다 경고를 내는
# 것은 고장으로 보인다. btop 테마를 뺀 것과 판단이 다른 이유가 그것이다:
# 저쪽은 안 쓰는 것이고 이쪽은 git init이 **매번** 쓴다.
mkdir -p "$WORKDIR/usr/share/git-core"
cp -r "$SYSROOT/usr/share/git-core/templates" "$WORKDIR/usr/share/git-core/"

# passwd가 없으면 whoami가 이름 대신 "cannot find name for user ID 0"을
# 내고, **git이 커밋 작성자를 유추하려다 실패한다.** 한 줄이면 된다.
#
# 셸을 /bin/sh로 적는 것에 뜻이 있다 — 위의 링크와 같은 자리를 가리켜야
# 하고, tars.conf가 셸을 바꿔도 이 줄은 안 바뀐다.
cat > "$WORKDIR/etc/passwd" <<'EOF'
root:x:0:0:root:/:/bin/sh
EOF
cat > "$WORKDIR/etc/group" <<'EOF'
root:x:0:
EOF

# /usr/share/fish/*는 fish 패키지가 아니라 fish-common(arch: all)이 준다.
mkdir -p "$WORKDIR/usr/share/fish"
cp -r "$SYSROOT/usr/share/fish/functions" "$WORKDIR/usr/share/fish/"
cp "$SYSROOT/usr/share/fish/config.fish" "$WORKDIR/usr/share/fish/"
cp "$SYSROOT/usr/share/fish/__fish_build_paths.fish" "$WORKDIR/usr/share/fish/"

# HI-M1: UTF-8 로케일. **terminal이 LANG=C.UTF-8을 넘기므로 그 데이터가
# 게스트에 있어야 그 말이 참이 된다** — terminfo와 정확히 같은 종류의 항목이다.
#
# 없으면 셸의 `setlocale`이 실패하고 `mbrtowc`가 바이트를 하나씩 돌려준다.
# 그러면 fish가 우리가 보낸 한글 세 바이트를 **한 글자가 아니라 세 글자로**
# 들고, 바이트마다 폭을 세어(0x80~0x9F는 0칸, 0xA0 이상은 1칸) 커서를 두 칸짜리
# 글자의 가운데에 세운다. **증상은 "한글이 안 쳐진다"가 아니라 "앞 글자가
# 지워진다"이고**, 그래서 원인에서 멀다.
#
# 404KB이고 그중 368KB가 LC_CTYPE이다. 카테고리 하나만 넣지 않는 이유는
# `setlocale(LC_ALL, ...)`이 카테고리마다 파일을 찾기 때문이다.
mkdir -p "$WORKDIR/usr/lib/locale"
cp -r "$SYSROOT/usr/lib/locale/C.utf8" "$WORKDIR/usr/lib/locale/"

# IP-M1: terminal이 PTY 셸의 TERM을 바꾸므로(design doc 결정 7) 그 terminfo가
# 게스트에 있어야 한다. 없으면 부팅은 계속되고 셸이 능력을 덜 쓸 뿐이다 —
# **조용한 실패**라서 input/check.sh가 initrd 목록을 직접 확인한다.
#
# **TR-M2에서 xterm-256color가 늘었다.** TR-M0이 TERM을 xterm에서
# xterm-256color로 바꿨는데(TR design 결정 8) 이 줄은 따라오지 않아서, 게스트가
# 광고하는 이름의 terminfo가 실제로는 없는 상태로 두 milestone을 건너왔다.
# input/check.sh의 검사가 `*terminfo/x/xterm*` 글로브라 xterm 하나만으로도
# 통과했다 — **조용한 실패를 막으려고 만든 검사가 조용히 실패한 자리다.**
#
# 옛 이름 xterm도 남긴다. 손으로 띄운 셸이 그 이름을 쓸 수 있고, 두 파일을
# 합쳐도 8KB다.
#
# 디렉터리를 통째로 복사하지 않는 이유는 그대로다. ncurses-base의
# /usr/share/terminfo에는 수백 개가 들어 있고 우리가 광고하는 이름은 하나다.
# 시리얼 콘솔 셸이 쓰는 `linux`는 넣지 않는다 — 그쪽은 terminfo 없이도 지금까지
# 잘 돌아왔고, 넣는 순간 "무엇이 왜 필요한가"가 흐려진다.
mkdir -p "$WORKDIR/usr/share/terminfo/x"
cp "$SYSROOT/usr/share/terminfo/x/xterm" "$WORKDIR/usr/share/terminfo/x/xterm"
cp "$SYSROOT/usr/share/terminfo/x/xterm-256color" \
  "$WORKDIR/usr/share/terminfo/x/xterm-256color"

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
# 73.0MB → gzip 16.8MB다(2026-08-23 폰트를 unifont로 바꾼 뒤 실측. Hanme일
# 때는 67.6MB → 15.5MB였고, 늘어난 1.2MB가 폰트 몫이다). 갱신할 때는 cpio가
# 찍는 blocks 수(×512B)와 `ls -l initrd.cpio`를 함께 본다.
# GL-M1: -9가 아니라 -6이다. 이 줄이 make_initrd.sh 9초의 거의 전부였고
# (cpio로 묶는 것은 154ms다), -9는 -6보다 224,663바이트(1.3%) 작아지자고
# 6.7초를 더 쓴다(16,835,576 대 17,060,239, 8,729ms 대 2,020ms). 루트 게이트는
# 그 6.7초를 24회 치른다.
#
# 크기를 늘려도 되는 근거는 실측이다 — ZM-M1에서 initrd가 11.8MB에서 14MB로
# 19% 늘었는데 BF 부팅 시간이 34/33/33초로 변하지 않았다
# (docs/decisions/project_gate_chain_composition.md). 1.3%는 그 영향권 밖이다.
# 53MB에서 부팅조차 못 했던 것은 선형적인 느려짐이 아니라 다른 종류의 벽이었다.
(cd "$WORKDIR" && find . | cpio -o -H newc) | gzip -6 > initrd.cpio
