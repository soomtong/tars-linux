# TP-M7 — 편집기(mitos · neovim · emacs · ttt), 일곱째 묶음 editor

> 2026-11-07, `79a88d0` 기준. 줄 번호는 낡을 수 있다. 결과는 끝의 "결과" 절(구현 뒤 채운다).

Goal: design "Milestone"의 "편집기 · 터미널 유틸리티 · 문서"를 셋으로 나눈 첫째(사용자 결정 2026-11-06 — M7 편집기, M8 터미널 유틸리티, M9 문서).
편집기 넷을 새 묶음 `editor`(design 결정 7의 이름)에 싣는다. 판정은 묶음마다의 것 — 망 없이 편집기가 서고 파일을 고친다(design "판정"의 TP-M2 이후 줄).

사용자 결정(2026-11-06, 조사를 단계별로 보고):
- milestone을 셋으로 나눈다(편집기 · util · 문서). 뒤의 서버 · AI는 M10부터.
- emacs 자리는 `emacs-nox`. Doom Emacs는 사용자가 망이 있을 때 직접 설치한다(확인 4 — 빌드 때 시드로 싣는 길은 홈 경로에 묶여 안 섰다).
  mg(사용자가 물었다)는 싣지 않는다.
- 그 뒤 남은 결정을 위임하고 잤다 — 아래 "Claude가 맡아 정한 것".

## 착수 전 확인 (2026-11-06 ~ 07)

amd64 trixie-slim 컨테이너(OrbStack), 실행 시험은 망을 끊고(`--network none`) 돌렸다. ELF 검사는 binutils를 받아야 해서 망 있는 다른 컨테이너에서.

1. 판과 sha256:

   | 도구 | 판 | 받는 것 | 크기 | sha256의 출처 | 풀린 크기 |
   |---|---|---|---|---|---|
   | mitos | 0.1.3 | mitos-editor/mitos release `mitos-v0.1.3-x86_64-linux.tar.xz` | 22,057,504 | GitHub `digest` | 290MiB(문법 `.so` 301개 255MiB) |
   | neovim | 0.12.6 | neovim/neovim release `nvim-linux-x86_64.tar.gz` | 11,404,582 | GitHub `digest` | 40MiB |
   | ttt | 1.11.0 | eugenioenko/ttt release `ttt-linux-amd64`(압축 없는 실행 파일 하나) | 17,199,288 | GitHub `digest` | 17MiB |
   | emacs | 1:30.1+1-6+deb13u1 | Debian trixie `emacs-nox` | 의존 포함 `.deb` 118MB(패키지 127개, slim 기준) | apt | — |

2. mitos: tarball(맨 위 `mitos-v0.1.3-x86_64-linux/`)에 `ms`와 그 옆 `runtime/`(queries · grammars · themes · tutor · 사전), `contrib/completion`.
   helix의 갈래라 모양이 같다. `ms --health`의 런타임 자리 셋 가운데 마지막이 실행 파일의 실제 자리 옆 `runtime/`이다 —
   `/usr/local/bin/ms` 링크로 불러도 `/usr/local/lib/mitos-0.1.3/runtime`을 찾았다(`current_exe`가 링크를 푼다).
   - `NEEDED` libgcc_s · libm · libc, GLIBC 2.34까지. 문법 `.so`는 libc(118) · libstdc++(2) · 없음.
   - 망 없이 `ms --version` → `mitos 0.1.3 (c4ba9991)`, `ms --health` 336줄, `ms --health c`의 Tree-sitter parser와 쿼리 여섯이 모두 ✓
     (clangd · lldb-dap이 없다는 빨강은 LSP · 디버거 몫 — 싣지 않는다).
   - 처음 실행이 `~/.config/mitos` · `~/.cache/mitos`를 만든다. 환경 변수는 `MITOS_CONFIG_DIR` · `MITOS_RUH`.
   - CPU 수준: 심볼이 벗겨져 함수별로는 못 본다. `%ymm` 2,367개, `cpuid` 23곳 · `xgetbv` 3곳 — Rust의 `std_detect` · `memchr`식 실행 중 고르기로
     본다. 문법 `.so`의 `%ymm`은 0. 실기 확인으로 남긴다(TCG는 못 잡는다).
3. neovim: tarball(맨 위 `nvim-linux-x86_64/`)에 `bin/nvim` · `lib/nvim/parser/*.so`(7) · `share/nvim/runtime` · `share/man/man1/nvim.1`.
   - `NEEDED` libm · libgcc_s · libc · ld-linux, GLIBC 2.34까지, `%ymm` 0.
   - 링크로 불러도 `$VIMRUNTIME`이 `/usr/local/lib/nvim-0.12.6/share/nvim/runtime`. 망 없이 C 파일에서 `vim.treesitter.start()` 성공,
     `checkhealth vim.treesitter`의 parser 일곱이 OK, `:help lua-guide`가 열린다.
4. emacs와 Doom Emacs(사용자가 물었다):
   - mg(trixie `mg` 20240709, 설치 260KB): Emacs 키 · 버퍼 · dired · 매크로만. elisp · 패키지 · 구문 강조 · LSP가 없다.
   - `emacs-nox` 30.1: 의존이 libgccjit · gnutls · tree-sitter · sqlite · dbus · alsa 등 — native-comp 판이라 libgccjit가 gcc를 부른다(base에 있다).
   - Doom(`doomemacs/doomemacs` master `7ccac7f`, 릴리스 판 없음 — Emacs 27.1~31.1, git · ripgrep · fd): 망 있는 컨테이너에서 `doom install`이
     12분 43초, `~/.config/emacs` 289MB(straight.el 저장소 122개 263MB).
   - 그 홈을 다른 사용자 홈으로 복사해 망 없이: 기동은 `modules/doom/compat/+keybinds.el`의 `file-missing`으로 Doom 부팅이 멈춘다. `doom sync`는
     "Installed packages must be rebuilt. (y or n)"을 묻고, `yes |`로 답해도 `straight/build-30.1/magit/magit-autorevert.el.gz`의 `File is missing`으로
     10초 만에 죽는다. 원인: `build-30.1/`의 파일 3,957개가 `/home/alice/.config/emacs/.local/straight/repos/…`로의 절대 링크이고, `.local/etc`의
     파일 8개가 홈 경로를 박는다. TARS의 사용자 이름은 설치 때 정해져 빌드가 홈을 모른다 → 시드로 싣지 않는다(사용자 결정).
5. ttt: Go 1.25.14 정적(`GOAMD64=v1`), `%ymm` 3,491 — Go 런타임의 실행 중 고르기. 망 없이 `--version` → `ttt v1.11.0`.
   - `--exec "wait-for TEXT; screenshot PATH; quit"`(내장 시험 장치, 실패면 0 아닌 코드)가 tty 없이 돈다: `ttt --size 100x30 --exec … a.go </dev/null`
     rc=0, 498ms, 화면 글자에 `1  package main`. 처음 실행이 `~/.config/ttt/plugins`를 만든다.
   - `timeout 8 ttt a.go`(TUI)는 SIGTERM으로 끝나지 않았다 — 체인은 `--exec`만 쓴다.
   - 받은 파일에 실행 비트가 없다(GitHub 자산) — 놓을 때 `chmod`가 필요하다(첫 시험이 rc=126).
6. 지금 매니페스트의 `upstream` · `prebuilt` URL 22개는 모두 `.tar.*` 또는 `.zip`으로 끝난다 — "압축 확장자가 아니면 실행 파일 하나"로 갈라도 기존 줄은
   그대로다(결정 D). harvest는 `--no-install-recommends`로 실제 `apt-get install`(postinst · alternatives까지)을 돌리고 `/etc/alternatives`를 지나는
   링크를 편다 — `emacs-nox`의 `/usr/bin/emacs`(alternatives)도 같은 길이다.

## 결정 (이 plan이 정한다 — 뒤집을 것이 있으면 글자로)

A. 묶음은 `editor`(design 결정 7). `DEV_LAYERS` · 체인의 `LAYERS` · `ISO_LAYERS`에 넣고, 이름 순이라 lowerdir는 `base editor lang-beam …`.
   체인의 묶음 수는 일곱(부팅 3은 여섯)이 된다.
B. mitos는 `upstream` 한 줄, `exe=ms`(실행 파일이 `bin/` 아래가 아니다). `runtime/`은 그대로 옆에 — 문법 301개를 다 싣는다(주 편집기, 고르지 않는다).
C. neovim은 `upstream` 한 줄, `bin/`의 `nvim`이 저절로 링크된다. `man1=share/man/man1`(nvim.1).
D. ttt는 `upstream` 한 줄. build.sh의 풀기에 길 하나를 더한다: URL의 마지막 조각이 `.tar` · `.tar.*` · `.tgz` · `.zip`으로 끝나지 않으면 받은 파일을
   `<도구 디렉터리>/bin/<도구>`에 0755로 놓는다(그 뒤 `bin/` 링크는 같은 길). 그 줄에 `strip=`이 있으면 멈춘다. 선택 키는 늘리지 않는다(다섯 — 한도).
   M8의 util에 이런 도구가 많다(cloudflared · lsoff꼴).
E. emacs는 `debian` 한 줄 `emacs-nox`(판 `1:30.1+1-6+deb13u1`). 의존은 apt가 풀고, base와 같은 파일(gcc · binutils 쪽)은 묶음 사이 대조가 `shared`로 센다 —
   내용이 다르면 build.sh가 멈춘다(TP-M2 결정 E).
F. 체인: devtools 부팅 2에 더한다(망 없이, 사용자로, 작업 자리 `~/tp/m7`). 기다리는 글자는 계산된 값이다(TP-M4 확인한 것 9).
   1. ms: `ms --version`, `ms --health c`에서 ✓인 줄 수(parser와 쿼리 — 일곱), `runtime/grammars`의 수
   2. nvim: `--headless`로 C 파일을 열어 treesitter를 켜고 한 줄을 바꿔 `:wq`, 파일 내용과 parser 결과를 찍는다
   3. emacs: `--batch`로 판 · `native-comp-available-p` · `treesit-available-p`, 파일을 열어 한 줄을 넣고 저장
   4. ttt: `--exec`로 Go 파일을 열어 `wait-for`, `screenshot`의 글자
   5. man: `man nvim` · `man emacs`
   상한은 처음 하나에 120초, 잰 뒤 세 배(60초 아래로는 안 내린다) — 첫 체인에서 넷 다 2초 아래라 60초다. 부팅 3(lang-jvm이 깨진 판)에 `nvim --version` 한 줄 — editor가 lowerdir 둘째 자리라
   깨진 묶음 하나가 그 뒤 자리를 흔들지 않는지 본다.

## Claude가 맡아 정한 것 (사용자가 위임 — 뒤집을 것이 있으면 글자로)

1. `EDITOR` · `/usr/bin/editor`는 initrd의 vim 그대로 둔다. 개발 도구 층이 없는 부팅(라이브 USB)에서도 같은 값이어야 하고, `git commit` 같은 짧은 편집은
   vim이 맡던 자리다(`user_editor_use`). ms를 쓰려면 사용자가 rc에 `EDITOR=ms`를 둔다.
2. mitos는 `.deb`가 아니라 tarball. `.deb`는 같은 내용을 `/usr/…`의 절대 자리에 두는 꼴이라 결정 2(도구 디렉터리 + 링크)에 맞지 않는다.
3. mitos의 셸 완성(`contrib/completion`)은 싣기만 하고 시스템 rc에 잇지 않는다 — 다른 도구의 완성도 아직 잇지 않았다(M8에서 함께 본다).
4. ttt는 실행 파일 하나라도 `/usr/local/lib/ttt-1.11.0/bin/ttt` 자리에 둔다 — 판이 경로에 남아 묶음 사이 대조 · 갱신이 다른 도구와 같다.

## 할 일

1. 매니페스트: editor에 mitos · neovim · ttt · emacs-nox.
2. `devlayer/build.sh`: 실행 파일 하나의 길(결정 D).
3. editor를 잇는 자리: `Makefile`의 `DEV_LAYERS`, `devtools/check.sh`의 빌드 줄 · `LAYERS` · lowerdir · 묶음 수(일곱, 부팅 3은 여섯), `rg -n 'lang-beam'`로 한 번 더.
4. `make dev-layers` — 숫자: editor의 풀린 크기 · zstd, emacs-nox의 패키지 수, NEEDED(libgccjit 쪽이 base와 맞는지), base와 shared 수.
5. chroot로 결정 F의 덩이를 먼저.
6. 빨강: (a) 결정 D의 `chmod`를 빼면 ttt가 `Permission denied`로 F-4가 멈춘다. (b) mitos의 `runtime/`을 치우면 F-1의 ✓ 수가 0이 된다(chroot로 본다).
7. 체인 혼자 한 번, 숫자로 상한을 고친다.
8. `make quick`, 루트 게이트. design(편집기 줄 · 뺀 것 · Milestone의 셋 나누기 · 결정 1의 실행 파일 하나), HANDOFF.

## 판정

- `make dev-layers`가 초록이고, editor의 NEEDED · 겹침 · 묶음 사이 검사가 지난다.
- 체인의 부팅 2에서 결정 F의 다섯 덩이가 망 없이 사용자로 돈다. 할 일 6의 빨강 (a)를 체인 또는 chroot로 봤다.
- 루트 게이트 초록, 잘린 줄 0.

## 비목표

1. LSP 서버 · 디버거(clangd · lldb-dap · rust-analyzer 밖의 것). `ms --health`의 빨강 줄은 그대로다. rust-analyzer는 lang-native에 이미 있다.
2. neovim · emacs의 플러그인 · 설정 체계(LazyVim · Doom). 사용자가 망이 있을 때 깐다 — Doom은 확인 4.
3. emacs의 GUI(`emacs-gtk` 등, design 비목표 5).
4. 편집기 셸 완성 · `EDITOR` 바꾸기(맡아 정한 것 1 · 3).

## 위험

1. emacs-nox의 의존 폐포가 base와 다른 판의 같은 파일을 들고 오면(libgccjit의 gcc-14 쪽) 묶음 사이 대조가 멈춘다. 같은 날 같은 미러를 거두므로 판은 같아야 한다 —
   어긋나면 이름을 대고 멈추므로 그때 harvest-skip 또는 base로 옮긴다.
2. mitos · ttt의 AVX2. 둘 다 실행 중 고르기로 보이지만 에어 2011의 실기 확인으로 남긴다(TCG는 CPUID에 없는 AVX2도 실행한다 — TP-M3 확인 8).
3. ISO가 1.36GB에서 1.5GB 안팎으로(editor zstd 어림 120~150MiB). 2GiB 한도까지 여유가 준다(`project_release_0_2.md`의 사용자 결정 대기).
4. 체인 시간이 1분 안팎 늘고 lane-0도 그만큼 는다.
5. emacs의 native-comp: 사용자가 처음 여는 패키지를 백그라운드에서 `~/.emacs.d/eln-cache`로 컴파일한다(gcc를 부른다). 에어 2011에서 처음 몇 번이
   느릴 수 있다 — 실기 확인으로.

## 확인한 것

1. 첫 `make dev-layers`가 editor의 verify에서 멈췄다(rc=2): `differs from initrd /usr/bin/editor` 하나와 `dangling link: usr/share/emacs/30.1/{etc,lisp}/COPYING
   -> ../../../common-licenses/GPL-3` 둘. emacs-nox의 postinst가 alternatives 열둘을 만들었고, slim에 없던 `/usr/bin/editor`가 "새 경로"로 잡혀
   펴졌다(`flat usr/bin/editor -> emacs-nox`). `COPYING`의 대상은 slim에 원래 있는 base-files의 파일이라 목록에 없었다.
   - 고친 것(harvest.sh 두 곳): 이름을 다른 것에 맡긴 alternatives — `usr/bin/editor` · `usr/bin/ctags`와 그 man1 — 를 싣지 않는다(editor는 initrd의 vim,
     ctags는 base의 universal-ctags — 남기면 `man ctags`가 emacs판을 연다). 링크의 대상이 `/usr/share/common-licenses/` 아래면 그 본문도 싣는다
     (`C-h C-c`가 `etc/COPYING`을 읽는다). base는 원래 `common-licenses` 26개를 싣고 있었다 — 새 규칙이 base에 더한 것은 없다(paths 그대로).
   - harvest.sh가 바뀌어 base · lang-script · editor를 다시 거뒀다(10분 38초). base · lang-script의 verify 숫자는 그대로다.
2. editor: harvest 패키지 47개, paths 8,495, flattened 8, verify dropped 119 · relinked 5 · ELF 830 · unresolved 0. 풀면 620MiB, zstd15 140MiB. 다른 묶음과
   같은 경로 · 같은 내용 `shared=4220`(libgccjit의 의존으로 따라온 binutils · libc6-dev 등 — base와 판이 같다, 위험 1은 안 일어났다).
3. chroot(initrd + base + editor, 사용자 tars, `unshare -n`): ms 81ms · health 초록 7 · 문법 301, nvim `translation_unit` · 저장, emacs `30.1-t-t`(554ms) · 저장,
   ttt `--exec` 490ms · 화면에 `1  package main`, `man nvim` → `nvim — edit text`, `man emacs` → `emacs - GNU project Emacs editor`,
   `command -v editor ctags etags` → `/usr/bin/editor`(initrd) · `/usr/local/bin/ctags` · `/usr/bin/etags`. `man ctags`는 아무것도 없다(universal-ctags는
   man을 안 싣는다 — emacs판을 뺀 결과, 그대로 둔다).
   - nvim의 `"h7.c" 4L, 32B written`이 줄바꿈 없이 앞에 붙는다 — 체인은 표시 앞에도 줄바꿈을 둔다.
4. 빨강 (a): `install -m 0755`를 `cp`로 바꾸면 체인까지 가지 않고 굽기에서 멈춘다 — `ttt: nothing to link — no exe= and no executables in
   /usr/local/lib/ttt-1.11.0/bin (wrong strip=?)`. 캐시 파일이 `rw-r--r--`라 TP-M3의 "링크 0개면 멈춘다"가 잡았다(plan은 체인의 `Permission denied`를
   예상했다 — 더 이른 자리). 되돌린 뒤 diff가 같은 것을 봤다.
5. 빨강 (b): chroot에서 `mitos-0.1.3/runtime`을 지우면 `tp-m7-msok=0` — 체인의 `=7` 기다림이 빨강이 된다.
6. 체인 혼자(SandyBridge · 1GiB, 망 없음): PASS, 빌드 뒤 553초, 전체 13분 11초. ms 185ms, nvim 728ms, emacs 1,885ms, ttt 821ms. 묶음 일곱 1,302MiB 복사 7,165ms,
   overlay 55ms. ISO 1,508,337,664바이트(앞 판 1.36GB). 상한 넷을 60초로(잰 값의 세 배가 60초 아래).

## 결과

- 판정 셋 모두 초록. `make dev-layers` 초록(editor 140MiB), 체인 부팅 2의 편집기 넷이 망 없이 사용자로 돈다, 빨강 (a) · (b)를 봤다(확인한 것 4 · 5).
- 루트 게이트 31/31, 30분 11초(lanes 1,356초), 31개 모두 잘린 줄 0. devtools 652초(빌드 뒤 551초). ISO 1.51GB, 묶음 일곱 1,302MiB.
- 실기로 남긴 것(HANDOFF "남은 작업"): `ms` · `ttt`가 에어 2011에서 서는지(AVX2 — TCG는 못 잡는다), emacs의 첫 native-comp가 견딜 만한지,
  망이 있을 때 TARS 위에서 `doom install`이 되는지(git의 https 헬퍼 · ripgrep · fd · gcc는 있다 — 체인으로 안 봤다).
