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

# WL-M1. 무선 firmware cpio. 이 파일의 끝에서 initrd 뒤에 이어 붙인다.
# 목록이 안 바뀌었으면 곧바로 끝난다(그 스크립트의 스탬프).
./vendor_firmware.sh

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

  # GE-M0. ELF가 아닌 파일은 따라갈 DT_NEEDED가 없다. guest_tools.sh의 which는
  # #! /bin/sh 스크립트라서, 이 검사 없이 들어오면 빌드는 살지만 아래 readelf -d가
  # `readelf: Error: Not an ELF file - it has the wrong magic bytes at the start`를
  # stderr에 찍는다(ELF 헤더 64바이트보다 작은 파일이면 `Failed to read file header`다 —
  # GE-M0 실측 4). 빌드가 사는
  # 것은 우연이다 — .interp 줄은 2>/dev/null || true로 막혀 있고, readelf -d는
  # for의 단어 목록 안이라 set -e가 그 실패를 안 본다. 실패가 아닌데 실패처럼 생긴
  # 줄이 빌드 로그에 남으면 진짜 에러가 그 사이에 묻힌다.
  #
  # magic 4바이트(7f 45 4c 46)만 본다. readelf -h로 묻지 않는 이유는 망가진
  # ELF(복사가 끊긴 바이너리)까지 조용히 건너뛰기 때문이다 — 그런 파일은 지금처럼
  # 아래 readelf까지 가서 에러를 내야 한다. od를 거치는 이유는 첫 4바이트에 NUL이
  # 있는 파일이면 bash가 명령 치환에서 `ignored null byte` 경고를 찍기 때문이다.
  # 스크립트의 인터프리터(#! 줄)는 따라가지 않는다(GE design 결정 2 · 비목표 3).
  # tools/check.sh 검사 1c가 이 검사를 지킨다.
  if [ "$(head -c 4 "$bin" | od -An -tx1 | tr -d ' \n')" != 7f454c46 ]; then
    return 0
  fi

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
    # 에 사본이 하나 더 생긴다. ldd는 SONAME을 절대 경로로 해석해 돌려주므로
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

# DI-M1: 설치기. init과 같은 zig build가 만들고 같은 이유로 정적이라
# copy_lib_deps가 필요 없다. 부르는 도구 셋(sfdisk · mkfs.vfat · mke2fs)은
# guest_tools.sh의 층 7이 싣는다. /usr/bin인 이유는 tq-probe와 같다 — 게스트의
# PATH가 /usr/bin:/bin이다.
cp ../init/zig-out/bin/tars-install "$WORKDIR/usr/bin/tars-install"
chmod 0755 "$WORKDIR/usr/bin/tars-install"

# CT-M1: 서비스 제어 명령. tars-install과 같은 까닭으로 정적이고 /usr/bin이다.
cp ../init/zig-out/bin/tars-service "$WORKDIR/usr/bin/tars-service"
chmod 0755 "$WORKDIR/usr/bin/tars-service"

# GL-M3(2026-08-29)에서 terminal이 ReleaseSafe가 됐다. 49,373,565 →
# 10,577,208바이트이고, 이 파일이 만드는 initrd는 16,199,658 →
# 10,988,773바이트다. 모드를 정하는 자리는 terminal/build.zig의
# `guest-optimize` 옵션이고 기본값이 ReleaseSafe다.
#
# strip은 여전히 안 한다. ReleaseSafe가 심볼을 지우지 않고도 78.6%를
# 줄이므로 strip을 검토할 이유가 없어졌다 — `readelf -S`로 확인하면
# `.debug_info`를 포함한 `.debug_*` 섹션 열 개가 그대로 있다.
#
# 옛 주석은 "심볼을 남기는 이유는 에러 트레이스"라고 적고 바로 다음 문장에서
# "단, 심볼이 있다고 트레이스가 바로 읽히지는 않았다"고 스스로를 부정하고
# 있었다 — 2026-08-12 TF-M4 실측에서 strip 버전은 `???` 주소 두 줄, 심볼
# 버전은 트레이스 자체가 없었다. 그 이유는 지금도 규명되지 않았고, Debug
# 에서도 안 읽혔으므로 ReleaseSafe에서 안 읽히는 것은 회귀가 아니다.
cp ../terminal/zig-out/bin/terminal "$WORKDIR/terminal"
chmod 0755 "$WORKDIR/terminal"

mkdir -p "$WORKDIR/vendor/fonts"
cp ../terminal/vendor/fonts/unifont.otf "$WORKDIR/vendor/fonts/unifont.otf"

# init은 libc를 링크하지 않는 정적 바이너리라 copy_lib_deps가 필요 없다
# (ZM-M1). terminal은 glibc 동적 링크다.
copy_lib_deps "$WORKDIR/terminal"

# ── 유저랜드 바이너리 ────────────────────────────────────────────────────
#
# UT-M1 결정 7. 목록은 여기 없다 — guest_tools.sh의 GUEST_TOOLS 배열
# 하나이고, tools/check.sh가 같은 파일을 source해서 initrd 목록을 검사한다.
#
# 예전에는 바이너리 하나마다 cp·chmod·copy_lib_deps 세 줄을 이 자리에 손으로
# 썼다. 여덟 개일 때는 읽혔지만 50개는 못 읽고, 손으로 쓰는 한 `cp`는 했는데
# `copy_lib_deps`를 빼먹는 실수가 언제든 난다 — 그 실패는 빌드 때가 아니라
# 게스트가 그 명령을 처음 칠 때 나타난다(design 위험 3). 루프 하나로
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
  # copy_lib_deps는 이미 있는 SONAME을 건너뛰므로 배열의 순서는 상관없다.
  copy_lib_deps "$dest"
}

. ./guest_tools.sh

for entry in "${GUEST_TOOLS[@]}"; do
  install_tool "${entry%%:*}" "${entry#*:}"
done

# /bin/sh는 언제나 bash다. tars.conf의 shell 설정과 무관하다 —
# #!/bin/sh 스크립트의 동작이 사용자의 셸 취향에 따라 달라지면 안 된다
# (design 결정 6). 셋 중 bash만이 POSIX sh 모드를 갖는다.
#
# 상대 경로로 건다. cpio가 링크의 내용을 그대로 담고 게스트의 루트가
# 곧 이 트리라 절대 경로도 맞지만, 상대로 두면 이 트리를 다른 자리에
# 풀어 봐도 끊어지지 않는다.
ln -sf ../usr/bin/bash "$WORKDIR/bin/sh"

# UT-M3. vi와 vim은 한 실체다(design 결정 4). guest_tools.sh에 줄을 둘
# 적으면 install_tool이 cp를 두 번 해서 3.9MB짜리 사본이 두 벌 생긴다 —
# 같은 파일에 이름이 둘 있는 것을 파일 둘로 만드는 것은 파일 시스템에
# 대한 거짓말이다. 위 /bin/sh가 이미 그 모양을 세워 뒀다.
ln -sf vim "$WORKDIR/usr/bin/vi"

# UT-M3. Debian git의 기본 페이저는 `less`가 아니라 `pager`다 — alternatives
# 이름이고 postinst가 만드는 링크라 dpkg -x로 푼 sysroot에 없다. 2026-09-11에
# 게스트에서 직접 봤다:
#
#   root@(none) /t/r (main)# git log
#   error: cannot run pager: No such file or directory
#   fatal: unable to execute pager 'pager'
#
# 매달리는 것이 아니라 죽는다. 그래서 게이트는 안 깨지고 사람만 깨진다 —
# `git log`·`git diff`·`git branch -a`가 전부 이 경로다. mawk→awk ·
# fdfind→fd · vim.basic→vim과 같은 종류(결정 4)이고, 다른 것은 이 이름을
# 우리가 고른 것이 아니라 git 바이너리가 컴파일 타임에 박아 뒀다는 점이다.
ln -sf less "$WORKDIR/usr/bin/pager"

# 같은 종류가 하나 더 있다. 게스트에게 직접 물어서 알았다:
#
#   root@(none) ~# git var -l
#   GIT_EDITOR=editor        GIT_SEQUENCE_EDITOR=editor        GIT_PAGER=pager
#
# `git commit`을 -m 없이 치는 것 · `git rebase -i` · `git config --edit`가
# 전부 이 이름을 부른다. vim은 이제 이름이 셋이고 실체는 하나다
# (vim · vi · editor).
ln -sf vim "$WORKDIR/usr/bin/editor"

# CU-M1. vim에 딸린 파일 둘. 위의 링크 셋과 같이 vim에 딸린 것을 여기 모은다.
#
# /etc/vim/vimrc는 시스템 vimrc다. CU-M1이 커서 세 줄(t_SI · t_SR · t_EI — insert는
# bar, replace는 underline, normal은 block)을 두었고, GE-M1이 모던 설정 한 벌
# (nocompatible · 줄 번호 · 상태 줄 · 빠른 Esc 등)을 더했다. 런타임 없이 vim에
# 컴파일된 옵션과 :highlight만 쓴다(GE design 결정 5 · 6). /config가
# 아니라 initrd에 두는 이유는 모든 부팅에서 되게 하려는 것이다 — ISO로 뜬
# 세션에도, 설정 디스크 없이 뜨는 render 체인에도 /config가 없다. vim은
# 사용자 vimrc(/.vimrc — 설정 디스크의 /config/vimrc로 가는 링크, 아래 PE-M2
# 블록)를 이 파일 뒤에 읽으므로 사람이 `set t_SI= t_SR= t_EI=`로 끌 수 있다.
# 다른 후보(seed vimrc · VIMINIT · EXINIT)가 왜 안 되는지는 CU design 결정 7의
# 후보 표에 있다. PE-M2가 까는 seed vimrc는 주석뿐이라 그 판단과 안 부딪친다.
#
# /usr/share/vim/vim91/defaults.vim은 주석뿐인 stub이다. vim.basic은 사용자
# vimrc가 없으면 $VIMRUNTIME/defaults.vim을 읽으려 하고, 게스트에는 런타임이
# 없어서 `E1187: Failed to source defaults.vim`과 `Press ENTER`를 띄운 채 키를
# 기다린다. 시스템 vimrc에 skip_defaults_vim을 두는 것으로는 못 막는다 — 그
# 변수를 보는 코드가 defaults.vim 안에 있다(CU design 실측 6). vim.tiny에는
# 없던 증상이다.
#
# 경로에 vim 판이 박혀 있다. $VIM이 없으면 /usr/share/vim이고 그 아래 vim91이
# $VIMRUNTIME이다. Debian이 vim 9.2로 올리면 vim92가 되어 이 stub이 안 읽힌다
# (CU design 위험 4). 그날은 render 체인 검사 25가 E1187로 빨개진다.
#
# 두 파일은 sysroot가 아니라 저장소(kernel/vim/)에서 온다. 우리가 쓴 파일이라
# 30-tars-ntp와 같은 자리다. 0644인 이유도 같다 — 실행이 아니라 읽히는 파일이다.
# cp · chmod 두 줄 대신 install 한 줄로 쓴 것은 파일 하나를 빼는 것이 줄 하나를
# 지우는 것이 되게 하려는 것이다(CU-M1 plan의 mutation).
mkdir -p "$WORKDIR/etc/vim" "$WORKDIR/usr/share/vim/vim91"
install -m 0644 vim/vimrc "$WORKDIR/etc/vim/vimrc"
install -m 0644 vim/defaults.vim "$WORKDIR/usr/share/vim/vim91/defaults.vim"

# NW-M2 결정 11. Debian의 /usr/bin/nc는 alternatives가 만드는 링크이고 실체가
# nc.traditional이다. alternatives 링크는 패키지의 postinst가 만드는 것이라
# dpkg -x로 푼 sysroot에 없다 — pager·vi·editor와 글자 그대로 같은 자리다.
# 다른 점은 이 이름을 우리가 골랐다는 것이다: 사람이 `nc`라고 친다.
ln -sf nc.traditional "$WORKDIR/usr/bin/nc"

# NW-M2. dhcpcd가 쓰는 자리 둘(M0 실측 7). 리스는 /var/lib/dhcpcd/eth0.lease에
# 쓰고(10.x는 /var/db가 아니다), /run/dhcpcd는 /run만 있으면 자기가 만든다.
# 지금 initrd에는 /var도 /run도 아예 없다 — UT-M0이 /bin·/tmp·/etc 셋을
# 더한 것과 같은 자리다.
mkdir -p "$WORKDIR/var/lib/dhcpcd" "$WORKDIR/run"

# NW-M2 결정 C. dhcpcd는 주소를 받으면 hook을 부르고, 그 hook이
# /etc/resolv.conf를 쓴다. M0의 실측 6이 이것이 없을 때 무슨 일이 생기는지
# 봤다 —
#
#   eth0: executing: /usr/lib/dhcpcd/dhcpcd-run-hooks BOUND
#   script_run: /usr/lib/dhcpcd/dhcpcd-run-hooks: No such file or directory
#
# 주소는 붙는데 이름만 안 풀린다. install_tool이 바이너리 하나만 복사하기
# 때문이고, 증상이 조용해서 원인에서 멀다.
#
# 경로를 바꾸면 안 된다. dhcpcd가 이 자리를 컴파일 타임에 박아 두고 찾는다 —
# zsh 모듈 트리가 sysroot와 같은 경로를 유지해야 하는 것과 같은 이유다.
#
# 넷 중 둘만 넣는다. 30-hostname은 hostname을 부르고(게스트에 없다),
# 50-timesyncd.conf는 systemd가 있을 때의 것이며, 01-test는 이름대로다.
# dhcpcd-run-hooks가 그 디렉터리를 훑어 있는 것만 돌리므로 빼는 데 비용이 없다.
#
# 20-resolv.conf가 이름으로 부르는 것은 sed·rm·cat·tail·head·mkdir·chmod
# 일곱이고 전부 게스트에 있다. resolvconf도 열세 번 나오지만 그것은 있는지
# 물어보고 없으면 직접 쓰는 갈래다.
mkdir -p "$WORKDIR/usr/lib/dhcpcd/dhcpcd-hooks"
cp "$SYSROOT/usr/lib/dhcpcd/dhcpcd-run-hooks" "$WORKDIR/usr/lib/dhcpcd/"
cp "$SYSROOT/usr/lib/dhcpcd/dhcpcd-hooks/20-resolv.conf" \
   "$WORKDIR/usr/lib/dhcpcd/dhcpcd-hooks/"
chmod 0755 "$WORKDIR/usr/lib/dhcpcd/dhcpcd-run-hooks"

# TS-M2. 우리 hook. 위의 20-resolv.conf와 계약이 같다 — dhcpcd-run-hooks가
# 이 디렉터리를 훑어 있는 파일을 전부 source하고, 각 hook은 new_* 변수에서
# 자기 몫을 꺼낸다. 저쪽은 $new_domain_name_servers로 /etc/resolv.conf를,
# 이쪽은 $new_ntp_servers로 /run/tars/chrony.sources/dhcp.sources를 쓴다(DS-M1).
#
# sysroot가 아니라 저장소에서 온다. 우리가 쓴 파일이기 때문이고, 저장소에
# 파일로 두는 이유는 net/check.sh의 호스트 검사가 그것을 sh로 직접 돌려
# 보기 때문이다(TS-M2 결정 M2-B) — heredoc이면 그 검사가 이 스크립트를
# 실행하지 않고는 hook을 얻을 수 없다.
#
# 0644인 것도 위의 것과 같다. 실행이 아니라 source라서 실행 권한이 필요 없다.
cp dhcpcd-hooks/30-tars-ntp "$WORKDIR/usr/lib/dhcpcd/dhcpcd-hooks/"
chmod 0644 "$WORKDIR/usr/lib/dhcpcd/dhcpcd-hooks/30-tars-ntp"

# WL-M2. 무선의 두 조각(WL design 결정 4). hook은 위의 30-tars-ntp와 같은
# 계약이고(source된다, 0644), wrapper는 init이 감독 목록의 path로 exec하는
# 실행 파일이다(0755). wrapper의 자리는 init/src/wifi.zig의 WIFI_PATH와 같은
# 글자여야 한다 — 어긋나면 증상이 `execve … failed (errno 2)` 하나다.
cp dhcpcd-hooks/10-tars-wifi "$WORKDIR/usr/lib/dhcpcd/dhcpcd-hooks/"
chmod 0644 "$WORKDIR/usr/lib/dhcpcd/dhcpcd-hooks/10-tars-wifi"
mkdir -p "$WORKDIR/usr/lib/tars"
cp wifi/tars-wifi "$WORKDIR/usr/lib/tars/tars-wifi"
chmod 0755 "$WORKDIR/usr/lib/tars/tars-wifi"

# TQ-M1. 터미널이 자식의 질의에 답하는지 재는 프로브. 게이트가 이름으로 친다.
#
# sysroot가 아니라 저장소에서 온다 — 우리가 쓴 파일이라 게스트에 넣을 원본이
# 여기밖에 없다. dhcpcd hook과 같은 자리이고, 다른 점은 이것을 게스트가
# 직접 실행한다는 것이다(저쪽은 source된다). 그래서 0755다.
#
# /usr/bin에 두는 이유는 게스트의 PATH가 /usr/bin:/bin이라 거기서만 이름으로
# 닿기 때문이다(NW-M0 실측 3 — /usr/sbin/dhcpcd를 못 찾은 그 자리다).
cp tq-probe.sh "$WORKDIR/usr/bin/tq-probe"
chmod 0755 "$WORKDIR/usr/bin/tq-probe"

# UT-M3 결정 8. git은 전역 설정을 $HOME/.gitconfig에서 읽고 게스트의 HOME은
# /다. 그런데 /는 tmpfs라 재부팅하면 사라진다 — 영속하는 것은 설정
# 디스크를 마운트하는 /config 하나뿐이고 그것은 읽기·쓰기다
# (init/src/main.zig가 MS_RDONLY 없이 마운트한다).
#
# 그래서 링크 하나로 잇는다. GIT_CONFIG_GLOBAL 환경변수를 쓰는 쪽은
# "그 변수를 어디서 넣을까"(PID 1인지 terminal인지)를 또 정해야 하고,
# 그것은 결정 1이 PATH에 대해 이미 치른 비용을 한 번 더 치르는 일이다.
# 새 코드 경로가 없다.
#
# 상대 경로인 이유는 /bin/sh와 같다 — 이 트리를 다른 자리에 풀어도 안
# 끊어진다.
#
# 설정 디스크를 못 찾으면? /config는 initrd 안의 빈 디렉터리로 남고
# 링크는 거기를 가리킨다. git이 쓰면 tmpfs에 쓰이고 재부팅하면 사라진다 —
# 부팅을 막지 않는다는 것이 RM-M2가 라벨을 못 찾았을 때와 같은 모양이다.
ln -sf config/gitconfig "$WORKDIR/.gitconfig"

# SC-M0 결정 1. 위 .gitconfig과 글자 그대로 같은 문제에 같은 답이다 —
# 셸의 rc 파일도 $HOME에서 읽히고 게스트의 HOME은 / 이며 /는 tmpfs다.
# 영속하는 것은 /config 하나뿐이다.
#
# /config 안은 평평하다. fish만 홈에서 한 단 더 깊은 자리를 쓰는데
# ($XDG_CONFIG_HOME/fish/config.fish, 즉 /.config/fish/config.fish),
# 대상 이름을 fish.config로 두어 gitconfig·bashrc·zshrc와 같은 층에
# 세운다 — /config/fish/ 디렉터리를 만들면 그 디렉터리는 fish만 쓴다.
#
# 파일은 여기서 안 만든다. initrd에 넣으면 tmpfs에 생겨서 부팅마다
# 초기화되고, 그러면 링크가 가리키는 자리와 파일이 있는 자리가 갈린다.
# seed는 init이 /config를 마운트한 뒤에 깐다(SC-M1).
#
# 설정 디스크를 못 찾으면? .gitconfig과 같다 — 링크가 initrd 안의 빈
# /config를 가리키고 셸은 rc가 없는 채로 뜬다. 부팅을 안 막는다.
mkdir -p "$WORKDIR/.config/fish"
ln -sf ../../config/fish.config "$WORKDIR/.config/fish/config.fish"
ln -sf config/bashrc "$WORKDIR/.bashrc"
ln -sf config/zshrc "$WORKDIR/.zshrc"

# PE-M2. vim의 사용자 vimrc도 위 .gitconfig · rc 셋과 같은 문제에 같은 답이다 —
# vim은 $HOME/.vimrc를 읽고(vim --version의 `user vimrc file`) 게스트의 HOME은
# / 이며 /는 tmpfs다. 위 CU-M1 블록의 시스템 vimrc(/etc/vim/vimrc)는 initrd에서
# 와서 부팅마다 같고, 사람이 고쳐서 재부팅 뒤에도 남기는 자리는 이 링크가
# 가리키는 /config/vimrc다.
#
# 파일은 여기서 안 만든다. 주석뿐인 seed를 init이 /config를 마운트한 뒤에
# 깐다(init/src/config.zig의 VIMRC_SEED). 설정 디스크를 못 찾으면 링크가
# initrd 안의 빈 /config를 가리켜 댕글링이고, vim은 그것을 "사용자 vimrc
# 없음"으로 보고 지금처럼 stub defaults.vim을 읽는다(PE design 실측 6) —
# render 체인이 그 부팅이다. 부팅을 안 막는 것도 rc와 같다.
ln -sf config/vimrc "$WORKDIR/.vimrc"

# git init이 새 저장소에 복사하는 템플릿(hooks 샘플 13 · info/exclude ·
# description). 26,140바이트이고, 없으면 git init이 매번 경고를 찍는다 —
# `warning: templates not found in /usr/share/git-core/templates`. 저장소는
# 그래도 만들어지지만, 개발용이라고 부르는 기계가 git init마다 경고를 내는
# 것은 고장으로 보인다. btop 테마를 뺀 것과 판단이 다른 이유가 그것이다:
# 저쪽은 안 쓰는 것이고 이쪽은 git init이 매번 쓴다.
mkdir -p "$WORKDIR/usr/share/git-core"
cp -r "$SYSROOT/usr/share/git-core/templates" "$WORKDIR/usr/share/git-core/"

# passwd가 없으면 whoami가 이름 대신 "cannot find name for user ID 0"을
# 내고, git이 커밋 작성자를 유추하려다 실패한다. 한 줄이면 된다.
#
# 셸을 /bin/sh로 적는 것에 뜻이 있다 — 위의 링크와 같은 자리를 가리켜야
# 한다. 이 파일에서는 안 바뀌지만, 부팅 때 init이 root 줄의 셸 자리를
# tars.conf의 셸로 다시 쓴다(SV 결정 9) — ssh 세션의 셸이 그 자리에서 온다.
#
# SV-M2: sshd의 privilege separation 사용자와 그 그룹. 없으면 sshd가
# "Privilege separation user sshd does not exist"로 안 뜬다(SV-M0 실측 4).
# /usr/sbin/nologin은 게스트에 없지만 sshd는 그 자리를 실행하지 않는다.
cat > "$WORKDIR/etc/passwd" <<'EOF'
root:x:0:0:root:/:/bin/sh
sshd:x:100:65534::/run/sshd:/usr/sbin/nologin
EOF
cat > "$WORKDIR/etc/group" <<'EOF'
root:x:0:
nogroup:x:65534:
EOF

# LB-M2. 이름 풀이(LB design 결정 5). 셋이 한 묶음이다.
#
#   /etc/hosts          localhost 한 이름. NSS를 안 거치는 resolver(정적 Go
#                       등)도 이 파일은 읽는다
#   /etc/nsswitch.conf  hosts만 적는다. 파일 → *.localhost → DNS 순서다.
#                       안 적은 데이터베이스(passwd 등)는 glibc가 files로 본다
#   libnss_myhostname   *.localhost를 127.0.0.1로 답하는 모듈
#
# 이 셋이 없을 때 localhost는 net=dhcp에서만, SLIRP 너머 호스트 DNS가 답해
# 줄 때만 풀렸다(LB-M0 실측 4). 파일은 passwd 옆이라 같은 heredoc이다.
cat > "$WORKDIR/etc/hosts" <<'EOF'
127.0.0.1 localhost
EOF
cat > "$WORKDIR/etc/nsswitch.conf" <<'EOF'
hosts: files myhostname dns
EOF

# glibc가 nsswitch.conf의 이름을 보고 실행 중에 dlopen하는 모듈이라 어느
# 바이너리의 DT_NEEDED에도 없다 — 이름으로 복사한다. 그 모듈의 의존은
# copy_lib_deps로 따라간다(zsh 모듈과 같은 이유다: 빠진 것이 부팅 뒤 dlopen
# 때가 아니라 여기서 드러나게). 지금 NEEDED는 libcap.so.2 · libc뿐이고 둘 다
# 이미 있다(LB-M0 실측 6).
if ! NSS_MYHOSTNAME="$(find_in_sysroot libnss_myhostname.so.2)"; then
  echo "make_initrd: libnss_myhostname.so.2 not in the sysroot (rebuild the devcontainer)" >&2
  exit 1
fi
cp "$NSS_MYHOSTNAME" "${WORKDIR}${LIB_DEST}/"
copy_lib_deps "${WORKDIR}${LIB_DEST}/libnss_myhostname.so.2"

# FW-M1. 방화벽 규칙 둘(FW design 결정 3 · 5). init의 firewall.zig가 tars.conf에
# firewall=on이 있을 때만 앞의 것을 nft -f로 올리고, 실패하면 뒤의 것을 올린다.
#
#   firewall.nft       기본 규칙 + /config/nftables.d/*.nft. 사람이 여는 포트가
#                      chain 안으로 include된다 — 파일 한 줄이 규칙 한 줄이다
#   firewall-base.nft  include가 없는 같은 규칙. 사람의 파일이 틀려서 앞의 것이
#                      실패했을 때 닫힌 채로 끝나게 한다. nft -f는 원자적이라
#                      실패하면 아무것도 안 바뀌고(FW-M0 실측 8), 부팅 첫 회에는
#                      "앞의 규칙"이 없으므로 이 파일이 없으면 열린 채다
#
# 표는 inet이 아니라 ip다. NF_TABLES_INET이 IPV6를 요구하고 우리 커널에는
# IPv6가 없다(design 확인 6 · 위험 6). include glob이 아무것도 못 찾아도 nft는
# 에러로 보지 않는다(실측 4) — /config가 안 붙은 부팅도 같은 파일을 올린다.
#
# 파일 안의 주석은 ASCII다. nft의 파서가 주석 안의 UTF-8을 어떻게 다루는지 잰
# 적이 없고, 이 파일이 안 읽히면 갈래 2 · 3으로 떨어진다.
mkdir -p "$WORKDIR/etc/tars"
cat > "$WORKDIR/etc/tars/firewall.nft" <<'EOF'
# TARS inbound firewall (FW design decision 3). Loaded by init when tars.conf
# says firewall=on. Do not edit this file; open ports in /config/nftables.d/.
flush ruleset
table ip tars {
	chain input {
		type filter hook input priority filter; policy drop;
		iif "lo" accept
		ct state established,related accept
		ct state invalid drop
		include "/config/nftables.d/*.nft"
	}
}
EOF
cat > "$WORKDIR/etc/tars/firewall-base.nft" <<'EOF'
# TARS inbound firewall without /config/nftables.d (FW design decision 5).
# init loads this only when firewall.nft failed, so the machine stays closed.
flush ruleset
table ip tars {
	chain input {
		type filter hook input priority filter; policy drop;
		iif "lo" accept
		ct state established,related accept
		ct state invalid drop
	}
}
EOF

# SV-M2. sshd의 자리 셋과 템플릿(SV design 결정 6).
#   /run/sshd                        privsep 디렉터리. 비어 있어야 한다(SV-M0 실측 4)
#   /etc/ssh/sshd_config             키는 /config/ssh에, 비밀번호는 없다
#   /etc/ssh/sshd_config.d/          init이 부팅 때 tars-env.conf를 쓴다(SV 결정 9)
#   /etc/tars/services/sshd          사람이 /config/services.d에 링크로 켠다
mkdir -p "$WORKDIR/run/sshd" "$WORKDIR/etc/ssh/sshd_config.d" "$WORKDIR/etc/tars/services"
chmod 755 "$WORKDIR/run/sshd"
cat > "$WORKDIR/etc/ssh/sshd_config" <<'EOF'
# TARS sshd (SV design decision 6). Do not edit; this file comes from the initrd.
# init writes sshd_config.d/tars-env.conf at boot so sessions get the console's env.
Include /etc/ssh/sshd_config.d/*.conf
HostKey /config/ssh/ssh_host_ed25519_key
AuthorizedKeysFile /config/ssh/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
UsePAM no
EOF
cat > "$WORKDIR/etc/tars/services/sshd" <<'EOF'
#!/bin/sh
# TARS sshd service (SV design decision 6). Turn it on with
#   ln -s /etc/tars/services/sshd /config/services.d/sshd
# and put your public key in /config/ssh/authorized_keys. With firewall=on, also
# open port 22 in /config/nftables.d/ (for example: tcp dport 22 accept).
key=/config/ssh/ssh_host_ed25519_key
if [ ! -e "$key" ]; then
  mkdir -p /config/ssh && chmod 700 /config/ssh || exit 1
  ssh-keygen -q -t ed25519 -N '' -C 'tars host key' -f "$key" || exit 1
  echo "sshd: generated a host key in /config/ssh"
fi
echo "sshd: host key $(ssh-keygen -l -f "$key.pub")"
exec /usr/bin/sshd -D -e -f /etc/ssh/sshd_config
EOF
chmod 755 "$WORKDIR/etc/tars/services/sshd"

# /usr/share/fish/*는 fish 패키지가 아니라 fish-common(arch: all)이 준다.
mkdir -p "$WORKDIR/usr/share/fish"
cp -r "$SYSROOT/usr/share/fish/functions" "$WORKDIR/usr/share/fish/"
cp "$SYSROOT/usr/share/fish/config.fish" "$WORKDIR/usr/share/fish/"
cp "$SYSROOT/usr/share/fish/__fish_build_paths.fish" "$WORKDIR/usr/share/fish/"

# TS-M3 결정 8·10. 시간대 규칙 전체. tars.conf의 timezone=Asia/Seoul 같은
# 이름을 init이 TZ 환경변수로 넘기면 glibc가 이 트리에서 그 파일을 읽는다 —
# 로케일과 정확히 같은 종류의 항목이고, 없으면 date가 조용히 UTC를 찍는다.
#
# 통째로 넣는다. 도시 몇을 우리가 고르면 새 도시마다 다시 빌드해야 하고,
# 전체가 압축 171KB라 고를 이유가 없다(TS 확인 8 — dhcpcd 바이너리 하나의
# 절반이 안 된다). TZif 파일은 대부분이 0이라 잘 눌린다.
#
# cp -r은 링크를 링크로 복사한다. 이 트리의 링크 51개가 그대로 링크로
# 남아야 크기가 확인 8의 값이다. 그중 localtime -> /etc/localtime은 게스트에
# 대상이 없는 링크가 되는데, 아무도 그 이름을 안 연다 — glibc가 TZ 없이 보는
# /etc/localtime은 이 링크가 아니라 그 대상이고, 그것이 없으면 UTC다.
#
# sysroot에서 온다(결정 10). 컨테이너 자신의 /usr/share/zoneinfo와 바이트까지
# 같지만 게스트 파일의 출처를 하나로 유지한다.
mkdir -p "$WORKDIR/usr/share"
cp -r "$SYSROOT/usr/share/zoneinfo" "$WORKDIR/usr/share/"

# HI-M1: UTF-8 로케일. terminal이 LANG=C.UTF-8을 넘기므로 그 데이터가
# 게스트에 있어야 그 말이 참이 된다 — terminfo와 정확히 같은 종류의 항목이다.
#
# 없으면 셸의 `setlocale`이 실패하고 `mbrtowc`가 바이트를 하나씩 돌려준다.
# 그러면 fish가 우리가 보낸 한글 세 바이트를 한 글자가 아니라 세 글자로
# 들고, 바이트마다 폭을 세어(0x80~0x9F는 0칸, 0xA0 이상은 1칸) 커서를 두 칸짜리
# 글자의 가운데에 세운다. 증상은 "한글이 안 쳐진다"가 아니라 "앞 글자가
# 지워진다"이고, 그래서 원인에서 멀다.
#
# 404KB이고 그중 368KB가 LC_CTYPE이다. 카테고리 하나만 넣지 않는 이유는
# `setlocale(LC_ALL, ...)`이 카테고리마다 파일을 찾기 때문이다.
mkdir -p "$WORKDIR/usr/lib/locale"
cp -r "$SYSROOT/usr/lib/locale/C.utf8" "$WORKDIR/usr/lib/locale/"

# IP-M1: terminal이 PTY 셸의 TERM을 바꾸므로(design doc 결정 7) 그 terminfo가
# 게스트에 있어야 한다. 없으면 부팅은 계속되고 셸이 능력을 덜 쓸 뿐이다 —
# 조용한 실패라서 input/check.sh가 initrd 목록을 직접 확인한다.
#
# TR-M2에서 xterm-256color가 늘었다. TR-M0이 TERM을 xterm에서
# xterm-256color로 바꿨는데(TR design 결정 8) 이 줄은 따라오지 않아서, 게스트가
# 광고하는 이름의 terminfo가 실제로는 없는 상태로 두 milestone을 건너왔다.
# input/check.sh의 검사가 `*terminfo/x/xterm*` 글로브라 xterm 하나만으로도
# 통과했다 — 조용한 실패를 막으려고 만든 검사가 조용히 실패한 자리다.
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

# SV-M2 결정 8. ssh로 붙는 사람의 터미널이 보내는 이름들. 없으면 less가
# "terminal is not fully functional"을 찍고 RETURN을 기다린다(SV-M0 실측 7).
# ncurses-term 통째(1,802개 · 12MB)가 아니라 흔한 것만 고른다.
#
# xterm-ghostty · xterm-kitty는 Debian의 ncurses-term에 없다 — ghostty · kitty라는
# 이름으로만 있다. infocmp로 풀어 첫 줄에 이름을 더하고 tic으로 다시 굽는다
# (SV 실측 14). tic은 컨테이너(arm64)의 것이지만 terminfo는 형식이 정해진
# 바이트라 게스트에서 그대로 읽힌다.
TI_SRC="$SYSROOT/usr/share/terminfo"
for pair in ghostty:xterm-ghostty kitty:xterm-kitty; do
  base="${pair%%:*}" alias="${pair#*:}"
  infocmp -x -A "$TI_SRC" "$base" | sed "s/^${base}|/${alias}|${base}|/" > "$WORKDIR/ti.src"
  tic -x -o "$WORKDIR/usr/share/terminfo" "$WORKDIR/ti.src"
done
rm -f "$WORKDIR/ti.src"
for t in a/alacritty w/wezterm f/foot t/tmux-256color s/screen-256color; do
  mkdir -p "$WORKDIR/usr/share/terminfo/${t%%/*}"
  cp "$TI_SRC/$t" "$WORKDIR/usr/share/terminfo/$t"
done

# zsh는 바이너리 하나가 아니다. zle(줄 편집), complete, parameter 같은
# "내장처럼 보이는" 기능 대부분이 실행 중에 dlopen되는 .so 모듈이고, 그것을
# 찾을 자리(module_path)는 zsh 안에 컴파일 타임에 박혀 있다. 그래서 이 트리만은
# initrd 안에서도 sysroot와 같은 경로를 유지해야 한다 — 다른 라이브러리처럼
# /lib/x86_64-linux-gnu로 모으면 zsh가 영영 못 찾는다.
mkdir -p "$WORKDIR/usr/lib/x86_64-linux-gnu"
cp -r "$SYSROOT/usr/lib/x86_64-linux-gnu/zsh" "$WORKDIR/usr/lib/x86_64-linux-gnu/"

# 38개 중 둘만 sysroot에 없는 라이브러리를 요구한다(2026-08-14 실측):
# zsh/curses는 libncursesw.so.6, zsh/db/gdbm은 libgdbm.so.6. 둘 다 zmodload로
# 이름을 대고 부를 때만 열리는 선택적 모듈이라 우리 셸은 부를 일이 없다.
# 라이브러리 두 개를 게스트에 들이는 대신 모듈을 뺀다 — 남겨두면 아래
# copy_lib_deps가 그 SONAME을 찍고 즉시 죽는다(그게 정상 동작이다).
rm -f  "$WORKDIR/usr/lib/x86_64-linux-gnu/zsh/"*/zsh/curses.so
rm -rf "$WORKDIR/usr/lib/x86_64-linux-gnu/zsh/"*/zsh/db

# 모듈도 각자 동적 의존을 갖는다. 바이너리에만 copy_lib_deps를 돌리면 빠진
# 라이브러리가 부팅 후 dlopen 시점에야 드러나고, 그 실패는 로그에서
# 알아보기 어렵다. 여기서 돌려야 make_initrd.sh가 SONAME을 찍고 즉시 죽는다.
while IFS= read -r mod; do
  copy_lib_deps "$mod"
done < <(find "$WORKDIR/usr/lib/x86_64-linux-gnu/zsh" -name '*.so')

# /usr/share/zsh(zsh-common)는 넣지 않는다. fish가 fish-common을 필요로
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

# WL-M1. 무선 firmware를 뒤에 이어 붙인다. 커널은 이어 붙인 cpio를 차례로
# 풀어 한 트리로 합친다(WL design 실측 9). 따로 두는 이유는 압축이다 — 38MB를
# 체인마다 다시 gzip하면 게이트 한 판에 1분 가까이 든다(GL-M1이 -9를 -6으로
# 내린 것과 같은 계산). vendor_firmware.sh가 목록이 바뀔 때만 다시 만든다.
#
# ⚠ `gzip -dc initrd.cpio | cpio -it`는 첫 archive의 끝 표시에서 멈춘다 —
# firmware는 그 목록에 안 나온다. tools/check.sh가 꼬리를 따로 대조한다.
cat src/firmware/firmware.cpio.gz >> initrd.cpio
