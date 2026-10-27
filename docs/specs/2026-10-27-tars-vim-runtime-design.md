# TARS Vim Runtime — Design

Date: 2026-10-27
Status: 취소 — 착수 안 함(2026-10-27). 사용자는 실제 코드 작업을 neovim · helix로 하고 게스트 vim은 대충 쓰는 편집기라서, 문법
색에 RAM +12.8MB를 쓸 쓰임이 없다(`docs/decisions/user_editor_use.md`). 실측(확인 1~7)과 범위 결정은 다시 집을 때를 위해 그대로
둔다.

HANDOFF "다음 후보"의 "vim-runtime 축소(38MB — 문법 색 · filetype만 고르는 길)" 항목에서 시작한다(사용자가 2026-10-27에 골랐다).
이름과 달리 지금 initrd에는 vim 런타임이 아예 없다(GE-M1, `project_guest_ergonomics`). 이 일은 줄이는 것이 아니라 런타임에서 쓸
부분을 골라 새로 싣는 것이고, initrd는 커진다.

## 한 줄 요약

Debian `vim-runtime`(9.1.1230-2, 게스트 vim.basic과 같은 판)을 sysroot에 풀고, `make_initrd.sh`가 `/usr/share/vim/vim91`을 initrd에
복사하되 사람이 찾아가야만 쓰이는 디렉터리 넷(`lang` · `doc` · `spell` · `tutor`)만 뺀다. 시스템 vimrc가 `filetype plugin indent on`과
`syntax on`을 켠다. 게스트 RAM +12.8MB, initrd(gzip) +3.0MB.

## 배경

게스트의 vim은 바이너리(vim.basic) · 시스템 vimrc(`kernel/vim/vimrc`, 144줄) · 주석뿐인 stub `defaults.vim` 셋으로 돈다. 그래서
문법 색 · filetype 감지 · 언어별 들여쓰기 · colorscheme · 플러그인(matchparen · netrw)이 없고, vimrc는 컴파일된 옵션과 `:highlight`만
쓴다. `syntax on`을 넣으면 `E484`와 `Press ENTER`가 뜬다. GE-M1이 런타임을 안 실은 이유는 크기였다 — Installed-Size 38,417KB는
그때 initrd 본체의 30%에 가까웠다.

그 뒤로 Lean Initrd가 게스트 RAM을 24.8MB 되찾았고(LI-M1), 런타임의 무게는 문법 색과 관계없는 디렉터리에 몰려 있다(확인 1).

## 착수 전에 확인한 것

2026-10-27, HEAD `481598d`. 컨테이너(`tars-devcontainer:latest`)에서 `apt-get download vim-runtime`으로 받은
`vim-runtime_2%3a9.1.1230-2_all.deb`(7,126,616바이트)를 `dpkg -x`로 풀어 쟀다. 이미지와 저장소는 안 바꿨다.

1. 디렉터리별 크기(`du -sk`, KB). 전체 42,552 — `lang` 10,136 · `doc` 8,940 · `syntax` 8,896 · `spell` 3,600 · `tutor` 2,900 ·
   `ftplugin` 1,760 · `autoload` 1,756 · `indent` 1,128 · `pack` 1,068 · `colors` 704 · `compiler` 512 · `keymap` 508 · `print` 132 ·
   `macros` 108 · `plugin` 80, 최상위 `filetype.vim` 92. `syntax` 753 · `ftplugin` 398 · `indent` 177개 파일. 심볼릭 링크는 0개다.
2. 묶음별 크기(원본은 파일 바이트 합, gzip은 `tar | gzip -6`).

   | 묶음 | 원본 | gzip -6 | 파일 |
   |---|---|---|---|
   | 런타임 전체 | 37,820,104 | 약 11.8MB | 2,227 |
   | 넷(`lang` · `doc` · `spell` · `tutor`)을 뺀 나머지 | 12,783,317 | 2,966,795 | 1,778 |
   | `syntax` · `ftplugin` · `indent` · `autoload` · `plugin` · `colors` + 최상위 `*.vim` | 약 11.0MB | 약 2.5MB | 1,462 |
   | 언어 약 35개만 고른 것(비교용) | 약 1.1MB | 약 0.28MB | 116 |

   initrd는 게스트 tmpfs에 풀리므로 RAM 비용은 원본 칸이다.
3. 런타임은 안에서 서로 부른다. 고른 디렉터리만 실으면 끊긴다.
   - `ftplugin` 14개가 `compiler`를 부른다 — `zig.vim`(`compiler zig_build`) · `zsh.vim` · sh 계열(`compiler shellcheck`) ·
     `rust` · `python`(`pytest`) · `jq` 등. `compiler/`가 없으면 그 파일을 열 때 `E666`이다.
   - `plugin/netrwPlugin.vim`이 `packadd netrw`를 한다(`pack/dist/opt/netrw`, 712KB). `plugin/`만 있고 `pack/`이 없으면 vim이 뜰
     때마다 에러다.
   - `syntax/vim.vim` · `bib` · `cmod` · `pike`, `ftplugin/tex` · `ada` · `erlang` · `spec` · `plaintex`, `autoload/rust.vim`이
     `macros/` · `keymap/` · `print/` · `packadd` 가운데 하나를 부른다.
4. 빼는 넷은 사람이 찾아가야만 쓰인다. `lang`은 메시지 번역과 메뉴(LANG은 `C.UTF-8`), `doc`은 `:help`, `spell`은 `:set spell`,
   `tutor`는 `:Tutor`와 vimtutor(게스트에 없다)다. 런타임의 다른 파일이 이 넷을 자동으로 읽지는 않는다.
5. 런타임의 진짜 `defaults.vim`은 5,412바이트다. 사용자 vimrc가 없을 때 읽히고 `syntax on` · `filetype plugin indent on` ·
   `mouse` · `scrolloff` · 마지막 커서 자리 복원 autocmd 등을 켠다. 지금 stub과 같은 경로다.
6. Dockerfile은 sysroot를 `apt-get download …` 한 번과 `dpkg -x` 루프로 만든다(`devcontainer/Dockerfile:336-474`). arch가 `all`인
   패키지는 접미사 없이 적는다(`fish-common` · `zsh-common` · `ncurses-base`). `vim:amd64`는 이미 있다. 패키지 vim의 `Depends`가
   `vim-runtime (= 같은 판)`이고 같은 `apt-get update`에서 둘을 받으므로 판이 어긋날 수 없다.
7. `render` 체인의 vim 검사(25 · 26~35)는 `/tmp/cu.txt` · `/tmp/cunone.txt`를 연다 — 확장자 `.txt`라 filetype `text`이고 칠할 문법이
   거의 없다. 이 체인은 셀의 색을 `terminal: style> 행,열 fg=RRGGBB bg=RRGGBB`로 찍는다.

## 결정

### 결정 1. 범위는 "넷만 빼고 전부"다 (사용자 결정, 2026-10-27)

사용자는 "언어 전부"(RAM +11MB 안)를 골랐다. 확인 3 때문에 그 안을 "넣을 디렉터리 목록"이 아니라 "뺄 디렉터리 목록"으로 적는다 —
`compiler` · `pack` · `keymap` · `macros` · `print` · `import`가 함께 들어가 런타임 안의 참조가 끊기지 않는다. 값은 +1.8MB(11.0 →
12.8MB)이고, 대신 런타임 안의 의존을 우리가 따라갈 일이 없다. 뺄 목록은 확인 4의 넷이다. 언어를 고른 안(1.1MB)은 목록 관리와 의존
닫힘 검사가 드는 쪽이라 고르지 않았다.

### 결정 2. sysroot에 풀고 `make_initrd.sh`가 복사한다

`vim-runtime`을 Dockerfile의 `apt-get download` 목록에 한 줄(`vim-runtime`, 접미사 없음) 넣는다. `make_initrd.sh`의 CU-M1 vim
블록이 `$SYSROOT/usr/share/vim/vim91`에서 넷을 뺀 나머지를 `$WORKDIR/usr/share/vim/vim91`로 복사한다. 그 디렉터리가 sysroot에 없으면
`make_initrd: … not found` 류로 멈춘다 — 지금 CU design 위험 4(Debian이 vim 9.2로 올리면 `vim92`가 되어 stub이 안 읽힌다)가 게이트
중간의 vim 화면이 아니라 initrd 빌드의 첫 줄에서 드러난다.

`guest_tools.sh`의 `GUEST_TOOLS`(ELF와 그 라이브러리를 따라가는 목록)에는 넣지 않는다. 파일 1,778개짜리 데이터 디렉터리이고
`copy_lib_deps`가 볼 것이 없다.

### 결정 3. stub `defaults.vim`은 그대로 둔다 — 런타임 복사 뒤에 덮어쓴다

런타임에 진짜 `defaults.vim`이 생기지만(확인 5) 쓰지 않는다. 그것은 설정 디스크가 없을 때(`/.vimrc`가 댕글링일 때)만 읽혀서, 쓰면
설정 디스크의 유무에 따라 vim이 달라진다(마우스 · 커서 복원 · `scrolloff`). 시스템 vimrc가 이미 모든 부팅에서 같은 설정을 주므로
stub이 맞다. 다만 stub의 주석("the guest has no vim runtime")은 이유를 "시스템 vimrc가 이미 설정을 다 준다"로 고친다.

### 결정 4. 시스템 vimrc가 `filetype plugin indent on`과 `syntax on`을 켠다

자리는 Colors 절의 `set background=dark` 뒤, `highlight` 아홉 줄 앞이다. `syntax on`이 `syncolor.vim`으로 문법 그룹(Comment 등)의
색을 정하고, 그 뒤의 우리 `highlight`(LineNr · StatusLine 등 문법 그룹이 아닌 것)가 그대로 남는다. 순서가 맞는지는 M1이 게스트에서
본다.

함께 고친다.
- Makefile용 `autocmd … setlocal noexpandtab`(`augroup tars_vimrc`)는 지운다 — `ftplugin/make.vim`이 같은 일을 한다. M1이 Makefile을
  열어 `expandtab`이 꺼진 것을 확인한 뒤에 지운다.
- `smartindent`는 여전히 안 쓴다 — 이제 언어별 `indent/`가 있다.
- vimrc 머리말의 "The guest has no vim runtime … ':syntax on' fails with E484" 문단을 새 사실로 바꾼다.

### 결정 5. milestone 둘 — 싣기와 켜기를 나눈다

- VR-M0: Dockerfile · `make_initrd.sh`만. vimrc는 그대로다. 런타임에 `plugin/`이 생겨 vim이 뜰 때마다 netrw · matchparen · gzip
  · tar · zip 등을 읽기 시작한다 — 이것이 에러 없이 뜨는지를 기존 `render` 검사 25 · 35 뒤의 "에러 줄 없음"이 그대로 본다. 이미지를 다시
  굽는다. initrd 크기와 게스트 RAM(LI-M1과 같은 방법)을 잰다.
- VR-M1: vimrc(결정 4)와 `render` 체인의 새 검사. 새 검사는 filetype이 있는 파일(예: 시스템 vimrc 자신 `/etc/vim/vimrc`, 또는
  `.sh` · `.zig`)을 열어 (a) 에러 줄과 `Press ENTER`가 없고 (b) 문법 색이 칠해진 셀(`style>` 줄의 fg)이 나타나는 것을 본다. 대조군은
  `vim -u NONE`으로 같은 파일을 연 화면이다. 어느 파일 · 어느 색을 기다릴지는 M1 plan이 게스트에서 잰 값으로 정한다.

게이트가 실패하면 M0이면 "런타임을 싣는 것", M1이면 "켜는 것"이 원인이다.

### 결정 6. 문서도 함께 고친다

"게스트에는 vim 런타임이 없다"는 문장이 여러 곳에 있다 — `kernel/make_initrd.sh`의 CU-M1 블록, `kernel/vim/vimrc` 머리말,
`kernel/vim/defaults.vim`, Dockerfile의 CU-M1 주석, `docs/guides/key-files.md`의 `kernel/vim/` 항목,
`docs/decisions/project_guest_ergonomics.md`. M0이 앞의 넷 가운데 싣기에 관한 것을, M1이 켜기에 관한 것을 고친다. decisions 문서에는
새 기억(`project_vim_runtime.md`)에서 링크하고 옛 문장 옆에 "VR이 바꿨다"를 단다(PE-M1이 GE 문서에 한 방식).

## 비목표

1. `:help`. `doc`(8.9MB)을 안 싣는다. `:help`는 `E149`류로 답한다. 필요해지면 `doc`만 따로 더하는 것이 가장 작은 다음 단계다.
2. 맞춤법 검사(`spell`), 메시지 번역(`lang`), `:Tutor`.
3. colorscheme 고르기. `colors/`는 실려서 `:colorscheme`은 되지만 기본값은 지금의 `background=dark` + 우리 `highlight`다.
4. 24비트 색(`termguicolors`). vimrc의 256색 방침은 그대로다.
5. 설정 디스크에 런타임을 두는 길. 모든 부팅(ISO · 설정 디스크 없는 체인)에서 같아야 하므로 initrd다.

## 위험

1. 플러그인이 기동 때 터미널에 무언가를 묻거나 그린다. matchparen은 괄호 위에서만 칠하고 netrw는 디렉터리를 열 때만 돌 것으로 보지만(플러그인 소스를 읽어 확인하지는 않았다),
   기동 화면이 바뀌면 `render` 검사 25의 `[New]` 기다림 · `VIM_COL=4` · 반전 셀 판정이 흔들릴 수 있다. M0이 기존 검사로 본다.
2. `syntax on`이 우리 `highlight`를 덮는다. 결정 4의 순서로 막고 M1이 본다. `cursorlineopt=number`와 반전 셀 판정(GE 실측)은 문법 그룹과
   관계없다.
3. 이미지 재빌드. sysroot 단계가 다시 돌아 시간이 든다. 이미지가 바뀌면 루트 게이트의 prebuild는 cold다.
4. RAM. 게이트 게스트는 1GB이고 +12.8MB다. LI-M1이 되찾은 24.8MB 안이다.
5. 기동 시간. vim이 뜰 때 `filetype.vim`(92KB)과 플러그인 열네 개를 읽는다. 게이트가 기다림 시간 안에 뜨는지만 보고, 숫자가 필요하면 M1에서
   `vim --startuptime`으로 잰다.
