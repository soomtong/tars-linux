---
name: project_userland_tools
description: "게스트 도구 한 벌(GNU + 모던 + git, 65개)과 그 이름이 PATH로 손에 닿게 한 층(UT-M0~M3, 2026-09-10·11). 목록은 kernel/guest_tools.sh 한 자리, 조달은 Debian .deb 하나로. 함정 — 비용은 DT_NEEDED가 데려오는 .so 한 겹 더 · Debian alternatives 링크는 dpkg -x에 없다 · initramfs는 tmpfs라 푼 크기가 RAM이다 · 목록과 검사가 같은 파일을 보면 tautology"
metadata:
  node_type: memory
  type: project
---

사용자가 2026-09-10에 기계를 실제로 써 보고 지목했다 — "기본적인 unix/linux
utilities가 부족하다. `ls` 같은 것들이 없다." 조건 둘 — 모던 대안을 기본 탑재,
git은 필수. design은 `docs/specs/2026-09-10-tars-userland-tools-design.md`,
UT-M0~M3이 2026-09-10·11에 끝났다. milestone별 경과와 게이트 시간은 2026-10-10에
지웠다(커밋 이력에 있다). 여기에는 다시 밟지 말 함정과 결정만 남긴다.

## 사용자가 정한 것

- 조달은 Debian `.deb` 하나로 통일한다. `eza` · `bat`의 `libgit2` 사슬 16개 11.4MB
  (`libcrypto` · Kerberos · mbedTLS · `libssh2`)를 알고 감수했다 — upstream musl 정적을
  쓰면 의존이 0이지만 경로가 둘로 갈린다. git이 필수가 되면서 `eza --git`과 `bat`의
  변경 줄 표시가 실제 쓸모를 갖는다.
- 패키지 매니저는 안 만든다(사용자가 `herdr`를 언급하며 "Homebrew for Linux로
  관리된다, 지금은 건너뛴다"). 바탕 한 벌만 굽고 긴 꼬리는 나중에 패키지 매니저가
  맡는다. 메모는 `HANDOFF.md`의 이미지 뷰어 절.
- 편집기는 vim이다. `helix` · `dust` · `bottom`은 trixie에 없고 `neovim`은 런타임
  24MB로 UT 전체보다 무겁다. 실체는 `vim.tiny`였다가 CU-M1이 커서 모양 때문에
  `vim.basic`으로 바꿨다([[project_cursor_shape]]).
- `btop`은 사용자가 더했고 `libstdc++`의 유일한 사용자다. btop을 빼면 `libstdc++6`도
  뺀다(`guest_tools.sh`와 Dockerfile 양쪽에 적혀 있다).

## 세운 것

| 무엇 | 어디 |
|---|---|
| `PATH=/usr/bin:/bin`을 붙인 env 블록을 짓는 순수 함수와 검사 | `init/src/environ.zig` · `environ_test.zig` |
| `GUEST_TOOLS` 배열 — 바이너리 목록이 사는 유일한 자리(`src:dest`) | `kernel/guest_tools.sh` |
| `install_tool()` — `cp` · `chmod` · `copy_lib_deps`를 한 루프에서. 링크 넷(`vi` · `pager` · `editor` · `.gitconfig`) · git 템플릿 · `/etc/passwd` | `kernel/make_initrd.sh` |
| `.deb` 목록과 라이브러리 목록 | `devcontainer/Dockerfile` |
| `GUEST_MEM=512` · `wait_for_screen` | `gate_lib.sh` |
| 열한번째 체인 — 절대 경로 없이 도구를 치고 목록을 정적으로 대조 | `tools/check.sh` |

진짜 벽은 `ls`가 없는 것이 아니라 `PATH`가 없는 것이었다([[project_guest_environment]]).

## 비용은 바이너리 크기가 아니라 DT_NEEDED가 데려오는 것 — 그리고 한 겹 더

- 도구의 무게는 `Installed-Size`가 아니라 `readelf -d`로 잰다. `copy_lib_deps`가
  재귀로 따라가므로 그것이 진짜 비용이다. 절차는 [[project_measuring_tool_cost]].
- 바이너리의 `DT_NEEDED`만 보고 `.so`의 `DT_NEEDED`를 안 보면 틀린다. M1에서
  "새 라이브러리 둘"이라고 적었는데 넷이었다(`libproc2` → `libsystemd` 1.1MB,
  coreutils → `libattr`). M2는 착수 전에 `.so`까지 재귀로 재서 `MISSING` 0을 빌드 전에
  알았고 한 번에 통과했다. M3의 "새 라이브러리 0"은 맞았지만 그것도 재고 나서 알았다 —
  맞는 날과 틀린 날은 재기 전에 구별되지 않고 그 확인은 30초다.
- `dlopen`으로 여는 것은 `DT_NEEDED`에 없다. `libsystemd`는 lzma · zstd · gcrypt를
  안 데려온다(trixie는 `dlopen`). 이 구분을 안 하면 `ps` 하나에 OpenSSL급 비용을
  치른다고 잘못 판단한다. 반대로 `libresolv`는 `libgit2` 사슬에 나오지만 `libc6`이
  담고 있어 Dockerfile에 적으면 apt가 "없는 패키지"로 죽는다.
- `git`은 사슬보다 싸다(`libpcre2-8` · `libz`). `/usr/lib/git-core`는 통째로 안
  넣는다 — 168 항목 중 심볼릭 링크 141, 실체 26, 큰 것 일곱 약 16MB가 네트워크 헬퍼다.
  `init` · `add` · `commit` · `log` · `status`는 builtin이라 그 트리 없이 돈다.

## Debian이 이름을 바꿔 둔 것과 alternatives — dpkg -x에는 없다

- `bat`은 `/usr/bin/batcat`, `fd`의 실체는 `/usr/lib/cargo/bin/fd`(`fdfind`는 링크).
  실체를 복사한다 — 링크를 복사하면 initrd 안에서 끊어진다. initrd 안의 이름은 우리가
  정한다(목록이 `src:dest`인 이유).
- `awk`는 `.deb` 안에 없다. `mawk` 패키지는 `/usr/bin/mawk`만 담고 `/usr/bin/awk`는
  postinst가 만드는 alternatives 링크다. `nc` · `pager` · `editor` · `vi`도 같은 자리다.
- 바이너리가 이름으로 부르는 다른 프로그램도 본다 — `DT_NEEDED`는 라이브러리만
  말한다. Debian git은 `GIT_PAGER=pager` · `GIT_EDITOR=editor`로 부르고(`git var -l`로
  게스트에게 물었다) 없으면 `git log`가 매달리는 것이 아니라 죽는다(`error: cannot run
  pager`). 게이트는 `--no-pager`로 쳐서 영영 못 보므로 그 링크들은 `tools/check.sh`에
  literal로 박아 두었다.
- 커밋에는 `user.email`이 필수다 — 호스트 이름이 `(none)`이라 git이 자동으로 못
  만든다. 이름은 `/etc/passwd`의 gecos에서 온다(작성자 `root <tars>`). `git config
  --global`은 `/.gitconfig` 링크를 따라 `/config/gitconfig`에 쓴다 — 읽는 자리를 바꿔서
  물어야 링크를 따라간 것과 덮어쓴 것이 갈린다.

## initramfs는 tmpfs다 — 푼 크기가 그대로 RAM이다

- 크기의 벽은 없었다(TF-M2의 53MB 벽이 걱정이었다). 진짜 `.deb` 스물넷을 밸러스트로
  얹어 트리 78MB · gzip 30MB로 부팅하니 원본 4초 대 5초. 밸러스트는 반드시 진짜
  바이너리여야 한다 — 난수는 안 줄고 0은 통째로 사라져 압축률이 다르다. `xz`는 9MB
  작지만 압축에 31초라 `gzip -6`을 유지한다(`CONFIG_RD_XZ` · `RD_ZSTD`는 켜져 있어
  바꾸려면 압축기만 바꾸면 된다).
- 그런데 QEMU 기본 메모리 128MiB에서 기계가 안 켜졌다(`System is deadlocked on
  memory`). 푼 84MB가 통째로 RAM에 남아 커널과 예약 48MB를 빼면 자리가 없다 — 78MB는
  되고 84MB는 안 되는 경계를 아무도 잰 적이 없었다. 처방은 `gate_lib.sh`의
  `GUEST_MEM=512`(256은 뜨지만 여유 125MB). 그때까지 QEMU 호출 열둘 중
  `machine/check.sh`만 `-m 512`를 갖고 있었고 나머지는 기본값으로 돌고 있었다 — 아무도
  그 수를 고른 적이 없었다. 실기(GB 단위)에서는 영원히 안 보였을 게이트만의 제약이다.
  게스트 payload를 키우는 변경은 도구가 도는가보다 기계가 켜지는가를 먼저 본다.

## 게이트가 가르쳐 준 것

- cpio 목록에 `./` 접두사가 없다. `make_initrd.sh`가 만든 항목은 `usr/bin/ls`다. plan이
  `./`를 붙여 적어 뒀고 그대로 썼으면 언제나 빨강이었다. initrd 목록을 보는 검사를 쓸
  때는 `tools/check.sh`의 기존 검사를 먼저 본다.
- `/etc/passwd`를 넣으니 fish가 uid 0을 이름으로 풀어 프롬프트가 `root@(none) ~#`이
  됐고 `copy/check.sh`의 `col 16`이 20이 됐다. 프롬프트 폭에 기대는 자리는 저장소에서
  그 하나뿐이다(`rg`로 셌다). 게스트의 사용자 데이터베이스를 건드리면 그 수도 본다.
  증상은 CM 체인의 FAIL이고 원인은 `make_initrd.sh`라 서로 멀다.
- 목록과 검사가 같은 파일을 보면 그 검사는 tautology다. 정적 검사가 증명하는 것은
  "목록이 완전한가"가 아니라 "`make_initrd.sh`가 목록이 말하는 것을 전부 넣었는가"다.
  목록의 완전성은 design이 답할 질문이다. 링크 넷과 템플릿은 배열이 아니라
  `tools/check.sh`에 literal로 적혀 있어서 `make_initrd.sh`에서 지우면 부팅 전에
  죽는다 — 같은 파일을 보면 tautology, 다른 파일을 보면 진짜 검사.
- 특정 도구를 겨냥한 음성 확인은 그 도구만 건너뛰게 한다. 루프가 fish · bash · zsh도
  다루므로 `copy_lib_deps` 한 줄을 빼면 기계 전체가 안 뜬다 — 고칠 자리가 하나인 것의
  뒷면이 망가뜨릴 자리도 하나인 것이고, 그것이 첫 판정에서 드러나는 것이 이 구조가
  안전한 이유다.
- 게이트가 타이핑하면 안 되는 도구 — `less` · `top` · `htop` · `btop` · `ncdu`는 화면을
  가져가는 대화형이라 체인이 매달리고 증상이 타임아웃이라 원인에서 멀다. `dmesg`는
  출력이 커널 로그 전체라 화면 로그를 뒤덮는다. `bat`은 판정 글자를 못 만든다. 그
  넷이 쓰는 라이브러리는 검사 1이 정적으로만 본다.
- `sleep 2`가 짐작이었고 8회 중 2회 틀렸다. `ps ax`가 화면을 통째로 채우고 TCG의 그
  한 프레임이 2초를 넘는 회차가 있어서, 깨진 회차의 마지막 화면에 찾던 글자가 정확히
  찍혀 있었다 — 출력이 틀린 것이 아니라 검사가 먼저 본 것이다. 처방은 `gate_lib.sh`의
  `wait_for_screen`(15초까지 0.1초 간격). 고정 sleep 합계 17초가 사라져 게이트가 오히려
  빨라졌다.
- 긴 출력의 첫 줄은 화면 프레임에 안 남는다. `vi --version`의 `VIM - Vi IMproved`가
  프레임 어디에도 없었다(0회) — 50줄이 한 번에 오고 프레임이 그려질 때는 첫 줄이 이미
  스크롤로 사라진 뒤다. 판정은 마지막까지 남는 줄로(`Linking: gcc`).
- `PADDED_LIST="$(printf '\n%s\n' "$LIST")"`는 명령 치환이 끝의 개행을 지워 아카이브의
  마지막 항목을 영영 못 찾는다. `.gitconfig`이 마침 마지막이라 드러났다. 증상이 조용한
  초록이 아니라 설명 안 되는 빨강이다. 고침은 명령 치환을 안 쓰는 것.
- `git checkout`으로 소스를 되돌려도 `zig-out`이 안 따라온다 — 음성 확인 뒤에는
  `rm -rf zig-out`([[project_zig_out_staleness]]).

## How to apply

게스트에 도구를 더할 때 — (1) 바이너리의 `DT_NEEDED`가 데려오는 `.so`를 한 겹 더
재고(`dlopen`은 안 나온다), (2) Debian이 이름을 바꿔 둔 것과 alternatives 링크(실체
없음)를 찾고, (3) 그 도구가 이름으로 부르는 다른 프로그램(페이저 · 편집기 · 헬퍼)을
보고, (4) 푼 크기가 RAM이라는 것을 `GUEST_MEM`과 함께 보고, (5) 게이트가 사람과 다른
모양으로 치는 자리(`--no-pager`)가 생기면 사람 쪽에 필요한 것을 정적 검사에 literal로
박는다. 게스트 화면의 글자를 바꾸는 변경은 체인 전부를 돌린다.

관련: [[project_guest_environment]], [[project_gate_chain_composition]],
[[project_kernel_config]], [[project_gate_latency]], [[project_measuring_tool_cost]]
