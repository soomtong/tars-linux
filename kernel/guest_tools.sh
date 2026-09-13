# 게스트에 들어가는 유저랜드 바이너리 목록 — 이것이 사는 유일한 자리다.
#
# UT-M1 결정 7. 예전에는 바이너리 하나마다 세 줄(`cp` · `chmod` ·
# `copy_lib_deps`)을 make_initrd.sh에 손으로 썼다. 여덟 개일 때는 읽혔지만
# 50개를 그렇게 쓸 수 없고, 손으로 쓰는 한 `cp`는 했는데
# `copy_lib_deps`를 빼먹는 실수가 언제든 난다. 그 실패는 빌드 때가 아니라
# 게스트가 그 명령을 처음 칠 때 `error while loading shared libraries`로
# 나타난다(design 위험 3) — 원인에서 가장 먼 자리다.
#
# tools/check.sh가 이 파일을 그대로 source해서 initrd 목록을 검사한다.
# 그래서 여기 한 줄을 더하면 게이트가 그 줄을 자동으로 본다. 목록과 검사가
# 어긋날 자리가 구조적으로 없다.
#
# 그러려면 이 파일은 데이터만 있어야 한다 — SYSROOT도 WORKDIR도 참조하지
# 않고, 명령을 하나도 실행하지 않는다. 부작용이 하나라도 있으면 게이트
# 체인이 이것을 source할 수 없다.
#
# ── 형식 ────────────────────────────────────────────────────────────────
#
#   sysroot 안의 경로 : initrd 안의 경로      (둘 다 앞의 / 없이)
#
# 둘이 다를 수 있는 것이 이 형식의 이유다 — initrd 안의 이름은 우리가
# 정한다(design 결정 4). 지금 당장의 실례가 `mawk`다: mawk 패키지는
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
#   sleep       IP-M0이 Ctrl+C로 죽일 자식으로 넣은 것이다. 셸이 아닌
#               프로세스가 foreground에 있어야 SIGINT 경로가 증명된다
#   ls          UT-M0의 심장. tools/check.sh가 절대 경로 없이 친다
#
# cat · uname · mkdir 셋은 게이트 판정에 필요해서 하나씩 들어왔던 것인데
# (design "왜 지금인가"의 표), 지금은 어느 체인도 그 이름을 타이핑하지
# 않는다. 그래도 뺄 이유가 없다 — coreutils 한 벌의 일부다.

GUEST_TOOLS=(
  # ── 셸 셋 ──────────────────────────────────────────────────────────────
  # CP-M2가 tars.conf로 고를 수 있게 했다. initrd 안의 자리는 sysroot의 원래
  # 자리와 무관하게 우리가 정하지만, init/src/config.zig의 Shell.path()가
  # 여기와 같은 경로를 돌려줘야 한다. 둘이 어긋나면 부팅 후 "execve failed"
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

  # less·top은 게이트가 타이핑하지 않는다. 둘 다 화면을 통째로 가져가는
  # 대화형 프로그램이라 sendkey로 치면 체인이 그 자리에서 매달린다. 목록
  # 검사(파일이 들어갔는가)까지가 게이트가 이 둘에 대해 보는 전부다.
  usr/bin/less:usr/bin/less

  # ps는 libproc2 → libsystemd → libcap 세 층을 데려온다. M1까지는 저장소에서
  # 가장 긴 동적 사슬이었고(M2의 libgit2 사슬 열여섯이 그 자리를 가져갔다),
  # 그래서 tools/check.sh가 `ps ax`를 실제로 친다 — 위험 3의 대표 검사다.
  usr/bin/ps:usr/bin/ps
  usr/bin/top:usr/bin/top

  usr/bin/dmesg:usr/bin/dmesg

  # ── 층 2 · 모던 12 ─────────────────────────────────────────────────────
  # design 최종 목록의 층 2 열둘에 btop을 더하고(사용자가 2026-09-11에
  # 요청했다) procs를 뺀 것이다(2026-09-13). procs를 뺀 자리에서 사라진
  # 라이브러리는 없다 — libgcc_s·libm 둘을 부르는데 libgcc_s는 btop의
  # libstdc++와 zoxide가, libm은 vim.tiny와 hyperfine이 여전히 부른다.
  # 그래서 남은 라이브러리는 여전히 열아홉이고, 그중 열여섯이 eza·bat 둘이
  # 데려오는 libgit2 사슬이다 — 네트워크가 없는 기계의 TLS·Kerberos·SSH
  # 스택이고 design 결정 3이 그 대가를 명시적으로 감수했다.
  #
  # 게이트가 타이핑하는 것은 eza·fd·jq 셋뿐이다. htop·btop·ncdu는 화면을
  # 통째로 가져가는 대화형이라 sendkey로 치면 체인이 타임아웃으로 매달린다
  # (design 실측 26 — less·top이 같은 이유로 빠져 있다). bat은 매달리지는
  # 않지만 화면에 내는 글자가 전부 다른 검사와 겹쳐서 판정을 못 만든다
  # (아래 tools/check.sh의 주석).
  usr/bin/eza:usr/bin/eza

  # 이름을 바꾸는 둘 — 결정 4. Debian이 이름 충돌을 피하려고 바꿔 놓은
  # 것이고(design 실측 9), 우리 initrd에는 그 제약이 없다. mawk→awk와 같은
  # 자리다.
  #
  # fd는 심볼릭 링크가 아니라 실체를 적는다. .deb 안에서
  # usr/bin/fdfind는 ../lib/cargo/bin/fd를 가리키는 상대 링크이고, cp가
  # 따라가 주기는 하지만 sysroot 구조가 바뀌면 조용히 깨진다.
  usr/bin/batcat:usr/bin/bat
  usr/lib/cargo/bin/fd:usr/bin/fd

  usr/bin/rg:usr/bin/rg
  usr/bin/sd:usr/bin/sd
  usr/bin/htop:usr/bin/htop

  # btop은 게스트에서 libstdc++.so.6의 유일한 사용자다(기존 50개와 층 2의
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

  # ── 층 3 · 개발 2 ──────────────────────────────────────────────────────
  # 사용자가 2026-09-10에 조건으로 달았다 — *"tars-linux는 거의 개발용으로
  # 사용되기 때문에 git은 필수 도구가 될 것"*.
  #
  # 줄 둘에 새 라이브러리가 하나도 안 딸려 온다. git은 libpcre2-8·libz·
  # libc를, vim.tiny는 libm·libtinfo·libselinux·libacl·libc를 부르는데
  # 일곱 다 이미 initrd에 있다(libz는 M2의 libgit2 사슬이, libacl은 sed가,
  # libselinux는 fish가 데려왔다). M1·M2에서 두 번 틀렸던 예측이 여기서
  # 처음 맞았고, 그래도 재고 나서 알았다.
  #
  # /usr/lib/git-core는 안 넣는다. init·add·commit·log·diff·branch가
  # 전부 git 바이너리 안의 builtin이라 그 트리 없이 돈다. 거기 있는 실체
  # 26개 중 큰 것 일곱이 네트워크 헬퍼이고(design 결정 5), 이 기계는
  # `# CONFIG_NET is not set`이다.
  #
  # 게이트는 git을 친다. vi는 `--version`까지만 친다 — 편집기는 화면을
  # 통째로 가져가는 대화형이라 sendkey로 열면 체인이 매달린다(less·top·
  # htop·btop·ncdu와 같다). 다만 `--version`은 찍고 즉시 끝나므로 그 넷과
  # 달리 바이너리가 도는 것까지는 본다.
  usr/bin/git:usr/bin/git

  # 이름을 바꾸는 셋째 — 결정 4. mawk→awk · fdfind→fd와 같은 자리다.
  # 실체는 vim 하나이고 `/usr/bin/vi`는 make_initrd.sh가 심볼릭 링크로
  # 건다 — 여기 줄을 둘 적으면 1.76MB짜리 사본이 두 벌 생긴다. 링크를
  # 거는 자리가 /bin/sh와 같고, 그래서 tools/check.sh의 검사 1이 `usr/bin/vi`
  # 를 뼈대 쪽 literal로 본다.
  usr/bin/vim.tiny:usr/bin/vim

  # ── 층 4 · 셸 메모리 2 ─────────────────────────────────────────────────
  # SM-M0. 기계가 사용자에게서 배운 것을 뒤지는 도구 둘이다 — zoxide는 어느
  # 디렉터리에 자주 갔는지를, fzf는 무엇을 쳤는지를(Ctrl+R) 뒤진다.
  #
  # UT 비목표 6이 이 둘을 여기까지 미뤄 둔 이유는 크기가 아니라 훅이었다 —
  # 셸이 무조건 no-config로 뜨는 한 rc에 훅을 걸 자리가 없었다. SC가 그 자리를
  # 만들었고(/config의 rc 셋), SM-M1이 거기에 훅을 건다. M0에는 아직
  # 없다 — 사람이 이름으로 직접 부르는 것까지다.
  #
  # 새 라이브러리가 0이다. zoxide는 libgcc_s·libm·libc를, fzf는 libc만
  # 부른다. libgcc_s는 btop의 libstdc++가, libm은 vim.tiny가 이미 데려왔다
  # (2026-09-11 amd64 .deb의 DT_NEEDED로 확인). 그래서 이 둘에 대해서는
  # copy_lib_deps를 빼도 게스트가 멀쩡하다 — design 위험이 하나 없는
  # milestone이고, 그것을 아는 것이 모르는 것보다 낫다.
  #
  # fzf의 .deb가 데려오는 나머지는 안 넣는다.
  #   usr/bin/fzf-tmux                              tmux가 없다
  #   usr/share/doc/fzf/examples/key-bindings.*      결정 7이 이유다
  #   usr/share/fish/vendor_functions.d/fzf_*.fish   같은 이유
  # fzf 0.60에는 `--zsh`/`--bash`/`--fish`가 내장돼 있고 그쪽이 자동완성까지
  # 함께 낸다. SM-M1의 훅이 파일이 아니라 그 플래그를 쓴다.
  #
  # 게이트는 둘 다 친다. fzf는 TUI라 그냥 치면 매달리지만(less·top·htop·
  # btop·ncdu와 같은 자리) `--filter`가 찍고 즉시 끝난다 — 이 저장소에서
  # 처음으로, 대화형 도구를 비대화형 모드로 쳐서 보는 자리다.
  usr/bin/zoxide:usr/bin/zoxide
  usr/bin/fzf:usr/bin/fzf
)
