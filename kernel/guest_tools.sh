# 게스트에 들어가는 유저랜드 바이너리 목록 — **이것이 사는 유일한 자리다.**
#
# UT-M1 결정 7. 예전에는 바이너리 하나마다 세 줄(`cp` · `chmod` ·
# `copy_lib_deps`)을 make_initrd.sh에 손으로 썼다. 여덟 개일 때는 읽혔지만
# **50개를 그렇게 쓸 수 없고**, 손으로 쓰는 한 `cp`는 했는데
# `copy_lib_deps`를 빼먹는 실수가 언제든 난다. 그 실패는 빌드 때가 아니라
# **게스트가 그 명령을 처음 칠 때** `error while loading shared libraries`로
# 나타난다(design 위험 3) — 원인에서 가장 먼 자리다.
#
# **tools/check.sh가 이 파일을 그대로 source해서 initrd 목록을 검사한다.**
# 그래서 여기 한 줄을 더하면 게이트가 그 줄을 자동으로 본다. 목록과 검사가
# 어긋날 자리가 구조적으로 없다.
#
# 그러려면 이 파일은 **데이터만** 있어야 한다 — SYSROOT도 WORKDIR도 참조하지
# 않고, 명령을 하나도 실행하지 않는다. 부작용이 하나라도 있으면 게이트
# 체인이 이것을 source할 수 없다.
#
# ── 형식 ────────────────────────────────────────────────────────────────
#
#   sysroot 안의 경로 : initrd 안의 경로      (둘 다 앞의 / 없이)
#
# 둘이 다를 수 있는 것이 이 형식의 이유다 — **initrd 안의 이름은 우리가
# 정한다**(design 결정 4). 지금 당장의 실례가 `mawk`다: mawk 패키지는
# /usr/bin/mawk만 담고 /usr/bin/awk는 Debian의 alternatives가 postinst에서
# 만든다. .deb를 dpkg -x로 푼 sysroot에는 그 링크가 없다. UT-M2의
# `fdfind`→`fd`, `batcat`→`bat`도 같은 자리를 쓴다.
#
# ── 지울 때 보아야 할 것 ────────────────────────────────────────────────
#
# 게이트 체인이 이름을 박아 두고 쓰는 것들이 섞여 있다. 지우기 전에 `rg`로
# 센다.
#
#   fish        열한 체인 대부분의 첫 판정이 `Welcome to fish`다
#   bash        input/check.sh가 `/usr/bin/bash --norc`를 타이핑한다.
#               그리고 /bin/sh 심볼릭 링크가 이것을 가리킨다(결정 6)
#   zsh         config·power 체인이 `execve /usr/bin/zsh`를 로그에서 본다
#   sleep       IP-M0이 **Ctrl+C로 죽일 자식**으로 넣은 것이다. 셸이 아닌
#               프로세스가 foreground에 있어야 SIGINT 경로가 증명된다
#   ls          UT-M0의 심장. tools/check.sh가 절대 경로 없이 친다
#
# cat · uname · mkdir 셋은 게이트 판정에 필요해서 하나씩 들어왔던 것인데
# (design "왜 지금인가"의 표), 지금은 어느 체인도 그 이름을 타이핑하지
# 않는다. **그래도 뺄 이유가 없다** — coreutils 한 벌의 일부다.

GUEST_TOOLS=(
  # ── 셸 셋 ──────────────────────────────────────────────────────────────
  # CP-M2가 tars.conf로 고를 수 있게 했다. initrd 안의 자리는 sysroot의 원래
  # 자리와 무관하게 우리가 정하지만, **init/src/config.zig의 Shell.path()가
  # 여기와 같은 경로를 돌려줘야 한다.** 둘이 어긋나면 부팅 후 "execve failed"
  # 로만 나타난다.
  usr/bin/fish:usr/bin/fish
  usr/bin/bash:usr/bin/bash
  usr/bin/zsh:usr/bin/zsh

  # ── 층 1 · GNU coreutils 36 ────────────────────────────────────────────
  # design 최종 목록의 35에 uname을 더한 것이다. uname은 이미 initrd에 있던
  # 것이라 목록에서 빼면 회귀다 — 최종 목록이 그것을 빠뜨렸다.
  #
  # 전부 sysroot에 이미 있었다(Dockerfile이 coreutils:amd64를 통째로 받아
  # 두고 있다). UT-M1이 치르는 비용은 복사 줄뿐이고 그 줄이 지금 이 배열이다.
  usr/bin/ls:usr/bin/ls
  usr/bin/cp:usr/bin/cp
  usr/bin/mv:usr/bin/mv
  usr/bin/rm:usr/bin/rm
  usr/bin/ln:usr/bin/ln
  usr/bin/mkdir:usr/bin/mkdir
  usr/bin/rmdir:usr/bin/rmdir
  usr/bin/cat:usr/bin/cat
  usr/bin/head:usr/bin/head
  usr/bin/tail:usr/bin/tail
  usr/bin/sort:usr/bin/sort
  usr/bin/uniq:usr/bin/uniq
  usr/bin/wc:usr/bin/wc
  usr/bin/cut:usr/bin/cut
  usr/bin/tr:usr/bin/tr
  usr/bin/date:usr/bin/date
  usr/bin/df:usr/bin/df
  usr/bin/du:usr/bin/du
  usr/bin/stat:usr/bin/stat
  usr/bin/touch:usr/bin/touch
  usr/bin/chmod:usr/bin/chmod
  usr/bin/chown:usr/bin/chown
  usr/bin/readlink:usr/bin/readlink
  usr/bin/realpath:usr/bin/realpath
  usr/bin/sleep:usr/bin/sleep
  usr/bin/echo:usr/bin/echo
  usr/bin/pwd:usr/bin/pwd
  usr/bin/env:usr/bin/env
  usr/bin/dirname:usr/bin/dirname
  usr/bin/basename:usr/bin/basename
  usr/bin/seq:usr/bin/seq
  usr/bin/id:usr/bin/id
  usr/bin/whoami:usr/bin/whoami
  usr/bin/tee:usr/bin/tee
  usr/bin/sync:usr/bin/sync
  usr/bin/uname:usr/bin/uname

  # ── 층 1 · coreutils가 아닌 것 11 ──────────────────────────────────────
  # 이 열하나가 UT-M1이 Dockerfile을 넓힌 이유다. grep·find·sed·awk·diff·
  # less·ps·top·dmesg는 전부 별도 패키지라 sysroot에 없었다.
  usr/bin/grep:usr/bin/grep
  usr/bin/find:usr/bin/find
  usr/bin/xargs:usr/bin/xargs
  usr/bin/sed:usr/bin/sed

  # mawk를 awk로 넣는다 — 위 "형식" 절이 이 한 줄에 대한 설명이다.
  usr/bin/mawk:usr/bin/awk

  usr/bin/diff:usr/bin/diff
  usr/bin/cmp:usr/bin/cmp

  # less·top은 **게이트가 타이핑하지 않는다.** 둘 다 화면을 통째로 가져가는
  # 대화형 프로그램이라 sendkey로 치면 체인이 그 자리에서 매달린다. 목록
  # 검사(파일이 들어갔는가)까지가 게이트가 이 둘에 대해 보는 전부다.
  usr/bin/less:usr/bin/less

  # ps는 libproc2 → libsystemd → libcap 세 층을 데려온다. **M1까지는 저장소에서
  # 가장 긴 동적 사슬이었고**(M2의 libgit2 사슬 열여섯이 그 자리를 가져갔다),
  # 그래서 tools/check.sh가 `ps ax`를 실제로 친다 — 위험 3의 대표 검사다.
  usr/bin/ps:usr/bin/ps
  usr/bin/top:usr/bin/top

  usr/bin/dmesg:usr/bin/dmesg

  # ── 층 2 · 모던 13 ─────────────────────────────────────────────────────
  # design 최종 목록의 층 2 열둘에 **btop**을 더한 것이다(사용자가 2026-09-11에
  # 요청했다). 라이브러리 열아홉이 딸려 오고, 그중 열여섯이 eza·bat 둘이
  # 데려오는 libgit2 사슬이다 — **네트워크가 없는 기계의 TLS·Kerberos·SSH
  # 스택**이고 design 결정 3이 그 대가를 명시적으로 감수했다.
  #
  # **게이트가 타이핑하는 것은 eza·fd·jq 셋뿐이다.** htop·btop·ncdu는 화면을
  # 통째로 가져가는 대화형이라 sendkey로 치면 체인이 타임아웃으로 매달린다
  # (design 실측 26 — less·top이 같은 이유로 빠져 있다). bat은 매달리지는
  # 않지만 화면에 내는 글자가 전부 다른 검사와 겹쳐서 판정을 못 만든다
  # (아래 tools/check.sh의 주석).
  usr/bin/eza:usr/bin/eza

  # 이름을 바꾸는 둘 — **결정 4**. Debian이 이름 충돌을 피하려고 바꿔 놓은
  # 것이고(design 실측 9), 우리 initrd에는 그 제약이 없다. mawk→awk와 같은
  # 자리다.
  #
  # **fd는 심볼릭 링크가 아니라 실체를 적는다.** .deb 안에서
  # usr/bin/fdfind는 ../lib/cargo/bin/fd를 가리키는 상대 링크이고, cp가
  # 따라가 주기는 하지만 sysroot 구조가 바뀌면 조용히 깨진다.
  usr/bin/batcat:usr/bin/bat
  usr/lib/cargo/bin/fd:usr/bin/fd

  usr/bin/rg:usr/bin/rg
  usr/bin/sd:usr/bin/sd
  usr/bin/procs:usr/bin/procs
  usr/bin/htop:usr/bin/htop

  # btop은 게스트에서 **libstdc++.so.6의 유일한 사용자다**(기존 50개와 층 2의
  # 나머지 열둘 전부의 DT_NEEDED를 2026-09-11에 확인했다). 이 줄을 지우는
  # 사람은 devcontainer/Dockerfile의 libstdc++6도 함께 지운다.
  #
  # 테마(/usr/share/btop/themes 63,503바이트)는 안 넣는다 — 내장 Default로
  # 돈다. btop이 UTF-8 로케일을 요구하는 것은 terminal이 LANG=C.UTF-8을
  # 넘기고 usr/lib/locale/C.utf8이 initrd에 있어서 이미 충족돼 있다(HI-M1).
  usr/bin/btop:usr/bin/btop

  usr/bin/tree:usr/bin/tree
  usr/bin/duf:usr/bin/duf
  usr/bin/ncdu:usr/bin/ncdu
  usr/bin/jq:usr/bin/jq
  usr/bin/hyperfine:usr/bin/hyperfine
)
