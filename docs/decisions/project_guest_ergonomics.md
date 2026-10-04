---
name: project_guest_ergonomics
description: 게스트에서 사람이 일하기 편하게 하는 작은 둘 — which(debianutils의 sh 스크립트, GUEST_TOOLS의 첫 비ELF)와 plugin · 런타임 없는 모던 시스템 vimrc(첫 줄 set nocompatible). copy_lib_deps가 ELF magic으로 스크립트를 건너뛴다. GE-M0 · M1, 2026-10-04 종료. 새 체인 없이 tools 검사 1c · 22와 render 검사 33~35가 본다
metadata:
  type: project
---

Guest Ergonomics(GE)는 2026-10-04에 M0 · M1로 닫혔다. 사용자의 요청 둘("기본 탑재되는
유틸리티에 which를 추가하자" · "vimrc 파일을 플러그인 없이 모던한 config 설정을")에서
시작했다. 설계와 plan은 Opus 서브에이전트가, 구현은 M0을 Sonnet · M1을 Opus
서브에이전트가 했고, Fable이 대조 · mutation · 루트 게이트 · commit을 맡았다.

- design: `docs/specs/2026-10-04-tars-guest-ergonomics-design.md`
- plan: `docs/plans/2026-10-04-tars-guest-ergonomics-ge-m0.md` · `-ge-m1.md`

## 무엇이 바뀌었나

- `which`(GE-M0). Debian은 `which`를 `debianutils`의 `/usr/bin/which.debianutils`(1,080바이트
  POSIX `#! /bin/sh` 스크립트)로 담고 `/usr/bin/which`는 alternatives 링크라 `dpkg -x`로 푼
  sysroot에 없다. 그래서 `GUEST_TOOLS`에 `usr/bin/which.debianutils:usr/bin/which` 한 줄이다
  (mawk→awk와 같은 자리). fish · bash에서는 이 스크립트가 돌고, zsh에서는 builtin이 가린다.
- `copy_lib_deps`(GE-M0). 목록에 ELF가 아닌 파일이 처음 들어왔다. 함수 맨 앞에서 4바이트
  magic(`7f454c46`)을 보고 아니면 돌아간다. 이 검사가 없어도 빌드는 살지만 stderr에
  `readelf: Error`가 남는다 — `tools/check.sh` 검사 1c가 `make_initrd.sh`의 stderr를 파일에
  담아 그 줄이 없는 것을 본다. 스크립트의 인터프리터(`#!` 줄)는 따라가지 않는다.
- 시스템 vimrc(GE-M1). `kernel/vim/vimrc`(→ `/etc/vim/vimrc`)가 CU-M1의 커서 세 줄에서 144줄이
  됐다. 첫 유효 줄이 `set nocompatible`이고(시스템 vimrc는 사용자 vimrc와 달리 `compatible`을
  자동으로 안 끈다), 그 뒤에 커서 세 줄 · `ttimeoutlen=50` · `number relativenumber` ·
  `cursorlineopt=number` · `laststatus=2`와 `statusline` · `incsearch hlsearch ignorecase smartcase` ·
  `expandtab shiftwidth=4 softtabstop=4 tabstop=8`(Makefile은 autocmd로 `noexpandtab`) ·
  `undofile`(`/tmp/vim-undo`, 재부팅에 사라진다) · `background=dark`와 `cterm` 강조 아홉 줄이다.
  전부 vim에 컴파일된 옵션과 `:highlight`다 — 런타임이 없다.
- `vim-runtime`은 싣지 않았다. Installed-Size 38,417KB이고 initrd 본체(firmware 꼬리를 뺀 압축
  전 129,655,808바이트)의 30%에 가깝다. 그래서 `syntax` · `filetype` · `colorscheme`은 여전히
  없다.

## 다시 조사하지 말 것

- `nocompatible`이면 vim의 `shortmess` 기본값이 `filnxtToOS`이고 그 `n` 때문에 새 파일
  메시지가 `[New File]`이 아니라 `[New]`다. `render` 검사 25가 그 글자를 기다리고, 그래서
  `set nocompatible`을 지우는 mutation이 거기서 잡힌다.
- `set number`는 `numberwidth` 기본값 4로 줄 번호 칸을 열어 빈 버퍼의 커서가 0행 4열이다
  (`render/check.sh`의 `VIM_COL`). `relativenumber`는 폭을 안 바꾼다. 게스트에서 잰 값과 셈이
  같았다.
- `cursorline`을 통째로 켜면 block 커서 칸의 색이 바뀌어 반전 셀 판정(`inverted_now` 1)이
  깨진다. 그래서 `cursorlineopt=number`다. 강조 그룹은 전부 `cterm=NONE`이라 reverse를 안 쓴다
  (기본 `StatusLine`이 reverse다).
- `nocompatible`이 되면 vim이 기동할 때 터미널에 묻는 것이 는다 — `ESC[>c` · `ESC[6n` 두 번 ·
  `OSC 10;?` · `OSC 11;?` · `ESC[?1004h`. 우리 터미널은 `write_pty`로 답하고(TQ-M1) 그 답은
  로그에 안 찍힌다. 게스트에서 빈 버퍼에 글자가 새지 않았다(커서가 4열에 그대로 있었다).
- `syntax on`을 넣으면 안 된다 — 런타임이 없어서 `E484`와 `Press ENTER`를 띄우고 검사 25가
  빨개진다. `smartindent`도 넣지 않는다 — filetype 규칙 없이는 `#`로 시작하는 줄을 0열로
  당긴다.
- `autoindent`와 붙여넣기. `Cmd+V`는 bracketed paste가 아니라서(CM 결정 9) 들여쓴 여러 줄을
  insert에서 붙이면 계단이 된다. 우회는 `:set paste` · `:set nopaste`. 고치는 일은 design 비목표 4.
- `readelf -d`를 ELF가 아닌 파일에 주면 메시지가 크기에 따라 다르다 — 헤더 64바이트보다 작으면
  `Failed to read file header`, 크면 `Not an ELF file - it has the wrong magic bytes at the start`.
  검사 1c의 패턴 `readelf: Error`는 둘 다 잡는다.
- vim 화면의 `style>` 덤프에서 기본 색과 다른 칸은 CU-M1의 6,976개에서 6,980개가 됐다(줄 번호
  칸). 판정은 `style_covers`라 영향이 없다.

## 탈출로

- `vim -u NONE` — 시스템 vimrc를 안 읽는다. `render` 검사 31 · 35가 이 길을 대조군으로 쓴다.
- 사람은 `/.vimrc`에서 어느 줄이든 되돌린다(시스템 vimrc가 먼저, 사용자 vimrc가 뒤에 읽힌다).
  다만 `/.vimrc`는 tmpfs라 재부팅에 사라진다 — `/config`로 seed하는 일은 design 비목표 2다.
- zsh에서 우리 `which` 스크립트를 쓰려면 `command which`나 `/usr/bin/which`다.

## 관련

[[project_cursor_shape]](같은 vimrc의 커서 세 줄과 stub `defaults.vim`) ·
[[project_userland_tools]](`GUEST_TOOLS`의 형식과 이름 바꾸기) ·
[[project_write_or_reuse]](`which`를 직접 쓰지 않은 저울) ·
[[project_gate_screen_echo]](검사 22 · 33 · 34의 판정 글자는 출력에만 있다) ·
[[project_terminal_queries]](vim의 새 질의에 터미널이 답하는 자리)
