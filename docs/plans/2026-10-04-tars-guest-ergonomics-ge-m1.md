# GE-M1 — 게스트 vim에 모던 vimrc를 준다

Date: 2026-10-04
Design: `docs/specs/2026-10-04-tars-guest-ergonomics-design.md`
Status: 착수 전. 실측은 맨 아래 "GE-M1이 실측한 것" 절에 구현자가 채운다.

## 누가 무엇을 하나

design 결정 8. Task 0~5와 Task 7은 구현 서브에이전트(Opus)가 한다. Task 6(mutation · 루트
게이트)은 lead가 한다. 구현자는 Task 5에서 `render` 체인을 한 번(약 2분) 돌려 결과를 보고한다.
commit은 lead가 한다 — 구현자는 commit하지 않는다.

| 파일 | 무엇을 |
|---|---|
| `kernel/vim/vimrc` | 통째로 바꾼다(Task 1의 전문) |
| `render/check.sh` | vim 구간의 기대값 넷, 검사 33~35, 주석 |
| `kernel/make_initrd.sh` | CU-M1 블록의 주석만 |
| `docs/specs/2026-10-04-tars-cursor-shape-design.md` | 결정 7 끝에 덧붙이는 문단 하나 |
| `docs/guides/lessons.md` | `kernel/vim/` · `render/check.sh` 항목 |
| 이 plan | 맨 아래 실측 절 |

이미지 재빌드는 없다. vimrc는 sysroot가 아니라 저장소에서 온다.

## 이 milestone이 끝나면

- 게스트에서 `vim`이 사용자 vimrc 없이도 `nocompatible`로 뜬다. 줄 번호(커서 줄은 절대, 나머지는
  상대), 창마다 상태 줄, 마지막 줄의 `-- INSERT --`, 50ms 안에 끝나는 Esc, 공백 넷의 들여쓰기,
  검색 하이라이트가 켜진다. 커서 모양 셋은 그대로다.
- 런타임이 없으므로 문법 색 · filetype · colorscheme은 여전히 없다(design 결정 5).
- 탈출로는 그대로 `vim -u NONE`이다. 사람은 `/.vimrc`에서 어느 줄이든 되돌린다.
- `render/check.sh`의 vim 검사가 새 화면에 맞춰 바뀌고(커서 4열, `[New]`), 검사 33~35가
  시스템 vimrc가 읽혔다는 것을 직접 본다.

## 착수 전에 확정한 것

1. 선행 조건. GE-M0이 commit돼 있으면 좋다 — 그러면 이 milestone의 게이트 차이가 vimrc 하나다.
   둘은 서로 안 기대므로 순서가 바뀌어도 동작은 같다.
2. design 실측 9 · 10 · 11이 이 plan의 바탕이다. 컨테이너(같은 판 `2:9.1.1230-2`의 arm64 vim,
   `script`의 47×100 pty)에서 Task 1의 vimrc로 잰 것이다.
   - DECSCUSR은 6 · 2 · 4 · 2로 CU-M1과 같다.
   - 새 파일 메시지가 `[New File]`이 아니라 `[New]`다. `nocompatible`의 `shortmess` 기본값
     `filnxtToOS`의 `n` 때문이다. `vim -u NONE`은 여전히 `[New File]`이다.
   - `-- INSERT --` · `-- REPLACE --`와 상태 줄 ` utf-8 unix  0:0  100%`가 화면에 나온다.
   - `E숫자:`도 `Press ENTER`도 없다.
3. 커서의 열은 셈이고 아직 게스트에서 잰 값이 아니다. `number`가 여는 줄 번호 칸은
   `numberwidth` 기본값 4(숫자 셋 + 공백 하나)이고 `relativenumber`는 폭을 안 바꾼다. 그래서 빈
   버퍼의 커서는 `row=0 col=4`일 것이다. 다르면 그 값으로 `VIM_COL`을 정하고 실측 절에 적는다.
4. 반전 셀 수는 안 바뀌어야 한다(design 결정 7). `cursorlineopt=number`라서 커서 칸의 배경이 안
   바뀌고, 강조 그룹이 전부 `cterm=NONE`이라 반전된 칸이 새로 생기지 않는다. `inverted_now`가
   기대와 다르면 마지막 프레임의 `style>` 줄 중 `fg=102030`인 것을 실측 절에 옮기고 lead에게
   보고한다 — 기대값을 고쳐서 맞추지 않는다.
5. NonText 색. CU-M1은 `~` 줄의 채움 색을 `fg=7AA6DA`로 쟀다. `background=dark`를 정하면 vim의
   기본 `NonText` 색이 바뀔 수 있다. 판정은 그 색을 안 보지만 `vim_shape_check`의 주석에 그 값이
   있으므로, 게스트에서 잰 값이 다르면 주석을 고친다.
6. 새 검사의 판정 글자(`project_gate_screen_echo`).
   - 검사 33의 `utf-8 unix`는 우리 `statusline`의 오른쪽이 만든다. 친 줄(`printf
     '\033[H\033[2J'; vim /tmp/cu.txt`)에 없고, `screens_since "$VIM_LOG_START"`로 vim을 띄운
     뒤의 화면만 본다.
   - 검사 34의 `-- INSERT --`는 vim의 `showmode`만 만든다. 게이트는 `i` 키 하나를 칠 뿐 그 글자를
     치지 않는다. `i`를 치기 직전의 로그 크기부터 본다.
   - 검사 25의 기다림 `\[New\]`는 vim 전의 화면에도, 검사 31의 `[New File]`에도 안 맞는다(`New`
     바로 뒤에 `]`를 요구한다).
7. vimrc는 ASCII이고 줄 이음을 안 쓴다. 주석은 영어이고 언제나 따로 한 줄이다(design 결정 6의
   원칙 5). `:map`과 `:autocmd`는 줄 끝의 `"`를 주석으로 읽지 않는다.
8. mutation은 vimrc 사본을 `-v /tmp/run/vimrc:/workspace/kernel/vim/vimrc:ro`로 덮어서 한다.
   `make_initrd.sh`가 `kernel/`에서 `install -m 0644 vim/vimrc …`로 읽으므로 그 사본이 initrd에
   들어간다. mutation을 돌리면 저장소의 `kernel/initrd.cpio`가 망가진 판으로 남지만 다음 체인이
   언제나 다시 만든다.
9. `render` 체인 하나는 약 2분이다(CU-M1 실측 6에서 1분 47.51초). 검사 셋은 화면 판정뿐이라
   몇 초를 더할 것이다.

## Task 0: 기준값

CU-M1 실측 6의 검사 25~32 줄이 기준값이다. 이 milestone은 커널 · init · terminal을 안 바꾸므로
따로 재지 않는다. 시작 전에 `pgrep -fl 'tars-devcontainer'`가 비었는지만 본다.

## Task 1: `kernel/vim/vimrc`

파일을 아래 내용으로 통째로 바꾼다. 커서 세 줄(`let &t_SI` · `let &t_SR` · `let &t_EI`)은 글자
그대로 남는다. 각 줄의 이유는 design 결정 6의 표와 같다.

```vim
" TARS system vimrc. It comes from the initrd (kernel/vim/vimrc in the repo);
" edits made in the guest are lost on reboot. Why each line is here: CU design
" decision 7 (cursor shape) and GE design decisions 5 and 6 (everything else).
"
" vim reads this file first and the user vimrc (/.vimrc) after it, so any line
" here can be undone there. To start vim without this file:
"   vim -u NONE
" To turn off only the cursor shapes, put this in /.vimrc:
"   set t_SI= t_SR= t_EI=
"
" The guest has no vim runtime: $VIMRUNTIME holds only a stub defaults.vim.
" So there is no syntax highlighting, no filetype detection, no colorscheme and
" no plugin (matchparen, netrw). ':syntax on' fails with E484. Everything below
" is a built-in option or an explicit ':highlight'. The file stays plain ASCII
" and uses no line continuation.

" First line on purpose. A system vimrc does not switch 'compatible' off (only
" a user vimrc does), and switching it off resets many options, so it must come
" before them.
set nocompatible

" ---- Cursor shape (CU design decision 7) ------------------------------------
" DECSCUSR on mode changes: bar in insert, underline in replace, block in normal.
let &t_SI = "\e[6 q"
let &t_SR = "\e[4 q"
let &t_EI = "\e[2 q"

" ---- Encoding ----------------------------------------------------------------
" The terminal passes LANG=C.UTF-8, which already means utf-8. Saying it here
" keeps Hangul intact when vim starts without LANG (env -i, a bare script).
set encoding=utf-8

" ---- Keys and timing ---------------------------------------------------------
" Backspace may delete indent, line breaks and text from before this insert.
set backspace=indent,eol,start
" Wait at most 50 ms for the rest of a terminal key code. Without this, Esc in
" insert mode waits for 'timeoutlen' and the cursor stays a bar that long.
set ttimeout
set ttimeoutlen=50
" Wait half a second for the rest of a mapping.
set timeoutlen=500
" Y yanks to the end of the line, like D and C (Neovim does the same).
nnoremap Y y$
" Ctrl-L also clears the search highlight, then redraws as it always did.
nnoremap <silent> <C-L> :nohlsearch<CR><C-L>

" ---- Editing -----------------------------------------------------------------
" Switch buffers without writing the current one first.
set hidden
" A new line keeps the indent of the line before it. No 'smartindent': without
" filetype rules it pulls every line starting with '#' to column 0.
set autoindent
" Tab inserts four spaces and Backspace removes four. A real tab in a file
" still shows as 8 columns, as most tools assume.
set expandtab
set shiftwidth=4
set softtabstop=4
set tabstop=8
" Makefiles need real tabs. There is no filetype plugin to say so, so say it
" here by file name.
augroup tars_vimrc
  autocmd!
  autocmd BufNewFile,BufRead Makefile,makefile,GNUmakefile,*.mk setlocal noexpandtab
augroup END
" Ctrl-A on 007 gives 008, not 010.
set nrformats-=octal
" J drops the comment leader of the line it joins.
set formatoptions+=j

" ---- Search ------------------------------------------------------------------
" Show matches while typing, keep them lit, and ignore case unless the pattern
" has a capital letter.
set incsearch
set hlsearch
set ignorecase
set smartcase

" ---- Screen ------------------------------------------------------------------
" Absolute number on the cursor line, distance to it on the others.
set number
set relativenumber
" Light up the cursor line's number only. Lighting the whole line would also
" recolor the cell under the block cursor.
set cursorline
set cursorlineopt=number
" Keep five lines and columns of context around the cursor.
set scrolloff=5
set sidescrolloff=5
" Show as much of a long last line as fits, with '@@@' at the end.
set display=truncate
" Make tabs, trailing spaces and no-break spaces visible, in ASCII.
set list
set listchars=tab:>-,trail:-,nbsp:+
" Show a half-typed command and the current mode on the last line.
set showcmd
set showmode
" Every window gets a status line: name, flags, encoding, format, position.
" It replaces 'ruler'.
set laststatus=2
let &statusline = ' %f%m%r%h%w%= %{&fileencoding !=# "" ? &fileencoding : &encoding} %{&fileformat}  %l:%c  %p%% '
" Command-line completion: complete the common part, then show a menu.
set wildmenu
set wildmode=longest:full,full
" No intro screen when vim starts without a file.
set shortmess+=I
" No beep and no screen flash.
set belloff=all
" New splits open below and to the right.
set splitbelow
set splitright
" Our terminal has no mouse reporting and ignores the window title.
set mouse=
set notitle

" ---- Files -------------------------------------------------------------------
set history=1000
" No swap file. The guest has one user, and a swap file in /config or in a git
" work tree is litter.
set noswapfile
set nobackup
" Undo history survives closing a file, until the next boot (/tmp is tmpfs).
set undofile
set undodir=/tmp/vim-undo
if !isdirectory(&undodir)
  call mkdir(&undodir, 'p', 0700)
endif
" The user is root, so modelines stay off (this is also vim's default for root).
set nomodeline

" ---- Colors ------------------------------------------------------------------
" Our terminal background is dark. Setting it here also stops vim from changing
" it later, which would reset the highlight groups below.
set background=dark
" 256-color cterm values: grays from the 232-255 ramp, accents from the first
" 16 colors so they follow the terminal palette. No 'termguicolors'.
highlight LineNr       cterm=NONE ctermfg=243  ctermbg=NONE
highlight CursorLineNr cterm=NONE ctermfg=11   ctermbg=NONE
highlight StatusLine   cterm=NONE ctermfg=252  ctermbg=238
highlight StatusLineNC cterm=NONE ctermfg=245  ctermbg=236
highlight VertSplit    cterm=NONE ctermfg=238  ctermbg=238
highlight Visual       cterm=NONE ctermfg=NONE ctermbg=239
highlight Search       cterm=NONE ctermfg=234  ctermbg=11
highlight IncSearch    cterm=NONE ctermfg=234  ctermbg=214
highlight SpecialKey   cterm=NONE ctermfg=239  ctermbg=NONE

```

편집 뒤 확인한다.

```bash
LC_ALL=C grep -c '[^ -~]' kernel/vim/vimrc     # 0 — ASCII뿐이다
grep -c '^let &t_S[IR]\|^let &t_EI' kernel/vim/vimrc   # 3 — 커서 세 줄
grep -n 'nocompatible' kernel/vim/vimrc | head -1   # 주석이 아닌 첫 줄이어야 한다
git diff --stat kernel/vim/vimrc
```

## Task 2: 컨테이너에서 먼저 띄워 본다

게스트를 부팅하기 전에(2분) 컨테이너에서 1분 안에 vimrc의 에러와 화면을 본다. design 실측 10과
같은 하네스다. 컨테이너가 `apt-get install vim`을 하므로 네트워크가 필요하다.

스크립트는 heredoc이 아니라 Write 도구로 `/tmp/run/ge_m1_probe.sh`에 만든다(lessons "범용
명령"의 heredoc 주의).

```bash
#!/usr/bin/env bash
# GE-M1 probe: the guest's vim setup in a throwaway container. Not a gate.
set -u
apt-get update -qq >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq vim >/dev/null 2>&1
dpkg -l vim | tail -1

# Make it look like the guest: no runtime but the stub, our system vimrc.
VR=/usr/share/vim/vim91
rm -rf /usr/share/vim/vimfiles /etc/vim
find "$VR" -mindepth 1 -delete
cp /workspace/kernel/vim/defaults.vim "$VR/defaults.vim"
mkdir -p /etc/vim /tmp/h
cp /workspace/kernel/vim/vimrc /etc/vim/vimrc

run() {
  local name="$1" cmd="$2" keys="$3"
  rm -f /tmp/cu.txt /tmp/out.$name
  ( sleep 2; eval "$keys"; sleep 1.5 ) | HOME=/tmp/h TERM=xterm-256color LANG=C.UTF-8 \
    script -qfec "stty rows 47 cols 100; $cmd" /tmp/out.$name >/dev/null 2>&1
  echo "== $name: $cmd =="
  echo -n "DECSCUSR: "; grep -aoE $'\e\\[[0-9]* q' /tmp/out.$name | tr -d '\033' | tr '\n' ' '; echo
  perl -pe 's/\e\][^\a\e]*(\a|\e\\)//g; s/\e\[[0-9;?>=]*[a-zA-Z]//g; s/\e[()][AB0]//g; s/\e[=>]//g; s/\r/\n/g' \
    /tmp/out.$name > /tmp/clean.$name
  grep -aoE '\[New[^]]*\]|-- (INSERT|REPLACE) --|E[0-9]{2,4}:[^"]*|Press ENTER|utf-8 unix[^%]*%' \
    /tmp/clean.$name | sort | uniq -c
}

run sys 'vim /tmp/cu.txt' "printf i; sleep 1.5; printf '\033'; sleep 1.5; printf R; sleep 1.5; printf '\033'; sleep 1.5; printf ':q!\r'"
run none 'vim -u NONE /tmp/cu.txt' "printf iab; sleep 1.5; printf '\033'; sleep 1.5; printf ':q!\r'"
run make 'vim /tmp/Makefile' "printf ':set et?\r'; sleep 1.5; printf ':q!\r'"
grep -aoE 'noexpandtab|  expandtab' /tmp/clean.make | sort | uniq -c
ls -ld /tmp/vim-undo /tmp/h/.viminfo 2>&1
```

```bash
docker run --rm -v "$PWD":/workspace:ro -v /tmp/run:/tmp/run tars-devcontainer bash /tmp/run/ge_m1_probe.sh
```

기대(design 실측 10):

```
== sys: vim /tmp/cu.txt ==
DECSCUSR: [6 q [2 q [4 q [2 q
      1 -- INSERT --
      1 -- REPLACE --
      1 [New]
      1 utf-8 unix  0:0  100%
== none: vim -u NONE /tmp/cu.txt ==
DECSCUSR:
      1 [New File]
== make: vim /tmp/Makefile ==
      … [New] · utf-8 unix …
      1 noexpandtab
drwx------ … /tmp/vim-undo
-rw------- … /tmp/h/.viminfo
```

`E숫자:`나 `Press ENTER`가 한 줄이라도 나오면 Task 3으로 넘어가지 않고 vimrc를 고친다.

## Task 3: `render/check.sh`

vim 구간(`rg -n '── vim — CU-M1' render/check.sh`부터 `# ── 음성 검사` 앞까지)만 고친다. 검사
1~24와 헬퍼(`vim_shape_check` · `style_covers` · `screens_since` 등)의 본문은 안 고친다.

### 3-1. 구간 머리 주석과 `VIM_COL`

`# ── vim — CU-M1 ──` 블록의 주석에서 낡는 문장이 셋이다.

- "이 부팅에는 설정 디스크가 없으므로 사용자 vimrc도 없다. 그래서 vim은 compatible이고 showmode가
  꺼져 `-- INSERT --`가 안 나온다. insert에 들어갔다는 증거는 cursor>의 vt=bar다(CU-M1 plan 확정
  7)." → 이렇게 바꾼다.

  ```
  # 이 부팅에는 설정 디스크가 없으므로 사용자 vimrc도 없다. GE-M1 뒤로 시스템 vimrc의
  # 첫 줄이 set nocompatible이라 vim은 그래도 nocompatible로 뜬다. 그래서 showmode가
  # 켜져 `-- INSERT --`가 나오고(검사 34), 새 파일 메시지는 shortmess의 n 때문에
  # `[New File]`이 아니라 `[New]`다. insert에 들어갔다는 첫 증거는 여전히 cursor>의
  # vt=bar다.
  ```

- "파일을 주면 `~` 45줄(색 하나)과 커서뿐이다." → "파일을 주면 `~` 줄과 상태 줄(GE-M1의
  laststatus=2)과 커서뿐이다."
- "vim은 빈 버퍼의 (0,0)에 커서를 두지만 메시지를 쓰려고 맨 아래 줄에 갔다가 돌아온다. 그래서
  기다림 패턴에 row=0 col=0을 넣는다" → "(0,0)"을 "(0,VIM_COL)"로, "row=0 col=0"을
  "row=0 col=${VIM_COL}"로.

그 블록 바로 뒤(검사 25 머리 앞)에 넣는다.

```bash
# 빈 버퍼에서 vim 커서의 열(GE-M1). 시스템 vimrc의 number가 줄 번호 칸을 연다 —
# numberwidth 기본값 4(숫자 셋 + 공백 하나)이고 relativenumber는 폭을 안 바꾼다.
# vim -u NONE(검사 31)은 줄 번호가 없어서 이 값을 안 쓴다.
VIM_COL=4
```

Task 5에서 잰 값이 4가 아니면 이 줄과 확정 3을 그 값으로 고친다.

### 3-2. 검사 25

- 주석의 "[New File]만 기다리면 15초를 다 쓰고" → "[New]만 기다리면 15초를 다 쓰고".
- 기다림과 실패 메시지. 지금:

  ```bash
  if ! wait_for_screen '\[New File\]|Press ENTER'; then
    report_failure "vim never drew its first screen (no [New File] and no Press ENTER)"
  fi
  ```

  바꾼 뒤:

  ```bash
  # GE-M1: [New]는 set nocompatible의 증거이기도 하다. vimrc는 shortmess에 n을
  # 넣지 않으므로, 그 줄이 안 돌면 vim은 compatible의 shortmess=S로 [New File]을
  # 쓰고 이 기다림이 15초를 다 쓴다. 그 경우를 따로 말한다.
  if ! wait_for_screen '\[New\]|Press ENTER'; then
    case "$(screens_since "$VIM_LOG_START")" in
      *"[New File]"*) report_failure "vim said [New File], not [New]: the system vimrc did not turn off compatible" ;;
    esac
    report_failure "vim never drew its first screen (no [New] and no Press ENTER)"
  fi
  ```

- 끝의 `vim_shape_check "vim started" 'vt=block drawn=block row=0 col=0 cols=1 ' …` →
  `vim_shape_check "vim started" "vt=block drawn=block row=0 col=${VIM_COL} cols=1 " "ink=0 box=0x0" 1`.
  패턴에 변수가 들어가므로 작은따옴표를 큰따옴표로 바꾼다.

### 3-3. 검사 33 — 상태 줄(새것, 25 바로 뒤)

```bash
# ── 검사 33: 시스템 vimrc가 읽혔다 — 상태 줄 (GE-M1) ──────────────────────
#
# 번호가 32 뒤이고 자리는 25 뒤다. vim이 뜬 화면을 25가 이미 기다렸으므로 여기서
# 바로 본다.
#
# `utf-8 unix`는 우리 statusline의 오른쪽(%{&fileencoding …} %{&fileformat})이
# 만든다. vim의 기본 상태(laststatus=1, 창 하나)에는 상태 줄이 없다. 친 줄에도
# vim 전의 화면에도 이 글자가 없고, screens_since로 vim을 띄운 뒤의 화면만 본다.
# 검사 35가 vim -u NONE에서 이 글자가 없는 것을 본다 — 그것이 대조다.
if ! grep -aq 'utf-8 unix' <<<"$(screens_since "$VIM_LOG_START")"; then
  report_failure "vim has no status line from the system vimrc (no 'utf-8 unix' on screen): $(screens_since "$VIM_LOG_START" | tail -n 1)"
fi
echo "the system vimrc gave vim a status line"
```

### 3-4. 검사 26과 검사 34(새것, 26 바로 뒤)

검사 26을 이렇게 바꾼다.

```bash
# ── 검사 26: i — insert는 bar ─────────────────────────────────────────────
VIM_I_START="$(wc -c < "$LOG")"
type_keys i
vim_shape_check "insert (i)" "vt=bar drawn=bar row=0 col=${VIM_COL} " "ink=32 box=2x16" 0

# ── 검사 34: showmode — insert에서 -- INSERT -- (GE-M1) ───────────────────
#
# 번호가 33 뒤이고 자리는 26 뒤다. compatible이면 showmode가 꺼져 이 글자가 없다
# (CU-M1 plan 확정 7). 게이트는 i 하나를 칠 뿐 이 글자를 치지 않고, i를 치기
# 직전의 로그부터 본다. 검사 35가 vim -u NONE에서 이 글자가 없는 것을 본다.
if ! grep -aq -- '-- INSERT --' <<<"$(screens_since "$VIM_I_START")"; then
  report_failure "vim did not show -- INSERT -- after i (showmode is off): $(screens_since "$VIM_I_START" | tail -n 1)"
fi
echo "vim shows -- INSERT -- in insert mode"
```

### 3-5. 검사 27~29

세 `vim_shape_check`의 패턴에서 `row=0 col=0 `을 `row=0 col=${VIM_COL} `로 바꾸고 작은따옴표를
큰따옴표로 바꾼다. 기대 ink · 반전 셀 수는 그대로다(block `ink=0 box=0x0` 1, underline
`ink=16 box=8x2` 0).

### 3-6. 검사 30

패턴(`CU_ROW` · `CU_COL`)은 그대로다. 마지막 프레임 판정만 바꾼다.

```bash
case "$(last_frame | grep -a 'terminal: screen>' | tail -n 1 || true)" in
  *"[New]"*) report_failure "the last frame after :q! still shows vim's [New] line" ;;
esac
```

안 바꾸면 이 음성 판정은 언제나 초록이다 — 이제 vim은 `New File`이라는 글자를 안 쓴다.

### 3-7. 검사 31과 검사 35(새것, 31 안)

검사 31은 그대로다(`[New File]` · `col=2`). 시스템 vimrc를 안 읽으므로 `compatible`이다. 주석의
"showmode가 꺼져 있어 화면 글자로는 못 본다"도 그대로 맞다.

31의 마지막 `case … *"New File"*) …` 블록 뒤, `# 두 vim 세션 전체에 에러 줄이 없다.` 앞에 넣는다.

```bash
# ── 검사 35: 대조군 — vim -u NONE에는 상태 줄도 -- INSERT --도 없다 (GE-M1)
#
# 번호가 34 뒤이고 자리는 31 안이다. 검사 33 · 34가 본 글자가 우리 시스템 vimrc에서
# 왔다는 증명이다 — 같은 바이너리, 같은 터미널, 같은 키(i)인데 vimrc 하나만 없다.
NONE_SCREENS="$(screens_since "$VIM_NONE_START")"
if grep -aq -- '-- INSERT --' <<<"$NONE_SCREENS"; then
  report_failure "vim -u NONE showed -- INSERT --, so showmode is not coming from the system vimrc"
fi
if grep -aq 'utf-8 unix' <<<"$NONE_SCREENS"; then
  report_failure "vim -u NONE showed our status line, so it is not coming from the system vimrc"
fi
echo "control: vim -u NONE shows neither the status line nor -- INSERT --"
```

### 3-8. 끝 줄과 진입 검사

마지막 `echo "TR-M2 PASS: …"`의 끝 "and vim switches the cursor shape between modes" 뒤에 ", and the
system vimrc turns on line numbers, a status line and showmode"를 붙인다.

lessons "게이트를 돌리고 읽는 법"의 `ENTRY-OK` 명령을 `X`를 `render`로 바꿔 친다. 새 줄은 파이프
뒤에 `grep -q`가 없다(전부 here-string이다).

## Task 4: `kernel/make_initrd.sh` — 주석만

CU-M1 블록(`rg -n '# CU-M1. vim에 딸린 파일 둘' kernel/make_initrd.sh`)의 첫 문단에서 "/etc/vim/vimrc는
시스템 vimrc다. 커서 세 줄(t_SI · t_SR · t_EI)이라 vim이 insert에서 bar, replace에서 underline,
normal에서 block을 보낸다." 두 문장을 이렇게 바꾼다.

```
# /etc/vim/vimrc는 시스템 vimrc다. CU-M1이 커서 세 줄(t_SI · t_SR · t_EI — insert는
# bar, replace는 underline, normal은 block)을 두었고, GE-M1이 모던 설정 한 벌
# (nocompatible · 줄 번호 · 상태 줄 · 빠른 Esc 등)을 더했다. 런타임 없이 vim에
# 컴파일된 옵션과 :highlight만 쓴다(GE design 결정 5 · 6).
```

나머지 문장과 `install` 두 줄은 안 고친다. 편집 뒤 `git diff kernel/make_initrd.sh | rg '^-'`로 지운
줄이 그 두 문장의 줄뿐인지 본다.

## Task 5: 체인 한 번(구현자)

```bash
mkdir -p /tmp/run
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run:/tmp/run -w /workspace \
  tars-devcontainer bash -c '
  bash render/check.sh > /tmp/run/render.log 2>&1; echo "exit=$?"
  n=0; for f in /tmp/tmp.*; do
    if grep -a "tars-init" "$f" >/dev/null 2>&1; then n=$((n+1)); cp "$f" /tmp/run/serial_$n.log; fi
  done' ; } 2> /tmp/run/render.time
grep -E 'vim|insert|normal|replace|:q!|status line|INSERT|control|PASS|FAIL' /tmp/run/render.log
cat /tmp/run/render.time
```

기대하는 줄(커서 열은 확정 3의 셈이다):

```
vim started: vt=block drawn=block row=0 col=4 cols=1 ink=0 box=0x0, 1 inverted cell(s)
the system vimrc gave vim a status line
insert (i): vt=bar drawn=bar row=0 col=4 cols=1 ink=32 box=2x16, 0 inverted cell(s)
vim shows -- INSERT -- in insert mode
normal (Esc): vt=block drawn=block row=0 col=4 cols=1 ink=0 box=0x0, 1 inverted cell(s)
replace (R): vt=underline drawn=underline row=0 col=4 cols=1 ink=16 box=8x2, 0 inverted cell(s)
normal again (Esc): vt=block drawn=block row=0 col=4 cols=1 ink=0 box=0x0, 1 inverted cell(s)
after :q!: vt=block drawn=block row=0 col=15 cols=1 ink=0 box=0x0, 1 inverted cell(s)
vim -u NONE insert (i a b): vt=block drawn=block row=0 col=2 cols=1 ink=0 box=0x0, 1 inverted cell(s)
after vim -u NONE :q!: vt=block drawn=block row=0 col=15 cols=1 ink=0 box=0x0, 1 inverted cell(s)
control: vim -u NONE shows neither the status line nor -- INSERT --
no vim error line in either session
bar set inside 1049: vt=block drawn=block row=0 col=15 cols=1 ink=0 box=0x0, 1 inverted cell(s)
```

`col=15`는 CU-M1 실측 6의 `CU_COL`이고 이 milestone이 안 바꾼다.

시리얼 로그에서 실측 절에 옮길 것.

```bash
perl -pe 's/\e\][^\a\e]*(\a|\e\\)//g; s/\e\[[0-9;?>=]*[a-zA-Z]//g;
          s/\e[()][AB0]//g; s/\r/\n/g' /tmp/run/serial_1.log > /tmp/run/serial.clean
# 검사 25가 판정한 vim 첫 화면(상태 줄 · [New] 줄 포함)
grep -a 'terminal: screen>' /tmp/run/serial.clean | grep -a '\[New\]' | head -1 | tr '|' '\n' | sed -n '1,3p;44,48p'
# 그 프레임의 style 줄 앞머리 — 줄 번호 칸의 색, 커서 칸, NonText 색
grep -a 'terminal: style>' /tmp/run/serial.clean | grep -aE 'style> 0,[0-9]+ |style> 1,0 ' | tail -8
```

옮길 것은 화면의 0 · 1행과 44~46행(마지막 `~` · 상태 줄 · 메시지 줄), 0행의 `style>` 줄(줄 번호 칸
넷과 커서 칸), `1,0` 칸의 `fg`(NonText 색, 확정 5)다. 체인이 빨가면 그 줄과 마지막 `cursor>` 줄을
그대로 보고한다. 기대값을 고쳐서 초록을 만들지 않는다(확정 3 · 4).

## Task 6: mutation과 루트 게이트(lead)

1. mutation 셋. 저장소 파일은 안 고치고 vimrc 사본을 `-v`로 덮는다(확정 8). 돌리기 전에 `diff`로
   사본에 편집이 들어갔는지 본다.

   ```bash
   mkdir -p /tmp/run
   cp kernel/vim/vimrc /tmp/run/vimrc
   # (a) 줄 번호 칸을 없앤다. relativenumber만 남아도 칸이 열리므로 둘 다 지운다.
   sd -F 'set number' '" mutation: no number' /tmp/run/vimrc
   sd -F 'set relativenumber' '" mutation: no relativenumber' /tmp/run/vimrc
   # (b)는 원본 사본에 한 줄을 붙인다:   echo 'set nosuchoption' >> /tmp/run/vimrc
   # (c)는 원본 사본에서:                sd -F 'set nocompatible' '" mutation: compatible' /tmp/run/vimrc
   diff kernel/vim/vimrc /tmp/run/vimrc
   docker run --rm -v "$PWD":/workspace \
     -v /tmp/run/vimrc:/workspace/kernel/vim/vimrc:ro \
     -w /workspace tars-devcontainer bash render/check.sh > /tmp/run/mut.log 2>&1; echo "exit=$?"
   grep -E 'FAIL|vim started' /tmp/run/mut.log
   ```

   | mutation | 기대 |
   |---|---|
   | (a) `number` · `relativenumber` 없음 | 검사 25가 빨갛다. 기다림이 15초를 다 쓰고 마지막 줄이 `col=0`이다: `FAIL: vim started: the cursor line never matched /vt=block drawn=block row=0 col=4 cols=1 /: terminal: cursor> vt=block drawn=block row=0 col=0 …` |
   | (b) 없는 옵션 한 줄 | 검사 25가 빨갛다. vim이 대체 화면에 들어가기 전에 에러와 프롬프트를 찍는다: `FAIL: vim showed an error when it started: E518: Unknown option: nosuchoption …`과 `Press ENTER` |
   | (c) `set nocompatible` 없음 | 검사 25가 빨갛다. vim이 `[New File]`을 쓰므로: `FAIL: vim said [New File], not [New]: the system vimrc did not turn off compatible` |

   (c)가 이 milestone의 첫 줄이 정말 효과를 내는지 보는 유일한 자리다. `showmode`는 vimrc가 따로
   켜므로 (c)에서도 검사 34는 초록일 수 있다 — 그래서 (c)를 잡는 것은 검사 25의 `[New]`다.
   mutation이 예상과 다른 검사에서 죽거나 통과하면 그대로 적는다.
2. regression은 루트 게이트가 맡는다. initrd가 바뀌므로 열여덟 체인이 전부 새 initrd로 부팅한다.
   vim을 띄우는 체인은 `render` 하나다. 18체인 × 3, 약 1시간 5분. `run_in_background`로 돌리고
   `{ time …; }`로 감싼다. 완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가
   비었는지 먼저 본다.

## Task 7: 문서(구현자)

- `docs/specs/2026-10-04-tars-cursor-shape-design.md`의 결정 7. "시스템 vimrc의 내용은 세 줄이다."로
  시작하는 문단과 그 아래 vim 코드 블록 뒤에 한 문단을 덧붙인다. 앞의 글은 고치지 않는다 — 그때의
  결정이다.

  ```
  GE-M1(2026-10-04)이 이 파일을 모던 설정 한 벌로 넓혔다. 첫 줄이 `set nocompatible`이라
  vim은 이제 사용자 vimrc 없이도 `nocompatible`로 뜨고, 위 후보 표의 "사용자 vimrc가 없으면
  vim은 지금처럼 `compatible`로 뜬다 — 커서 말고는 안 바뀐다"는 더 이상 맞지 않는다. 커서
  세 줄은 그대로다. 내용과 이유는 `docs/specs/2026-10-04-tars-guest-ergonomics-design.md`의
  결정 5 · 6이다.
  ```

- `docs/guides/lessons.md`의 "핵심 파일" 절.
  - `kernel/vim/` 항목의 "(`vimrc` → `/etc/vim/vimrc`, 커서 세 줄)" → "(`vimrc` →
    `/etc/vim/vimrc`, 커서 세 줄과 GE-M1의 모던 설정 — 첫 줄이 `set nocompatible`이다)". 같은
    항목 끝에 한 문장: "런타임이 없으므로 그 vimrc는 컴파일된 옵션과 `:highlight`만 쓴다.
    `syntax on`을 넣으면 vim이 뜰 때마다 `E484`와 `Press ENTER`를 띄우고 `render` 검사 25가
    빨개진다."
  - `render/check.sh` 항목. "검사 25~31(CU-M1)이 …" 문장 뒤에 한 문장: "GE-M1 뒤로 vim 커서는 줄
    번호 칸 때문에 0행 4열(`VIM_COL`)이고 새 파일 메시지는 `[New]`다. 검사 33~35가 상태 줄과
    `-- INSERT --`로 시스템 vimrc가 읽혔다는 것을, `vim -u NONE`에서 둘 다 없는 것을 본다."
- 이 plan의 "GE-M1이 실측한 것" 절. Task 2의 출력, Task 5의 체인 시간 · 실제 줄 · 화면 행 ·
  `style>` 줄, `VIM_COL`과 NonText 색이 셈과 같았는지. lead가 Task 6을 끝내면 mutation 셋과 루트
  게이트 시간을 lead가 더한다.
- `HANDOFF.md` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · design의 `Status:`는 손대지 않는다
  (design "닫을 때").

## GE-M1이 실측한 것

(구현자와 lead가 채운다.)
