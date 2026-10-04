# TARS Guest Ergonomics — Design

Date: 2026-10-04
Status: 끝났다(2026-10-04, GE-M0 · GE-M1). plan은
`docs/plans/2026-10-04-tars-guest-ergonomics-ge-m0.md` · `docs/plans/2026-10-04-tars-guest-ergonomics-ge-m1.md`이고
각 끝에 실측이 있다. 착수 전에 잰 값은 아래 "착수 전에 실측한 것" 절에 있다.

사용자의 요청에서 시작한다(2026-10-04). 두 가지다.

1. 게스트에 기본으로 들어가는 유틸리티에 `which`를 더한다.
2. 게스트의 vim에 plugin 없는 모던 vimrc 설정을 준다.

## 한 줄 요약

GE-M0은 Debian `debianutils`의 `which` 스크립트 하나를 `/usr/bin/which`로 싣고, 그
스크립트가 ELF가 아니라서 `copy_lib_deps`가 내던 에러 한 줄을 없앤다. GE-M1은 initrd의
시스템 vimrc(`kernel/vim/vimrc` → `/etc/vim/vimrc`)를 커서 세 줄에서 모던 설정 한 벌로
넓힌다. 런타임(`vim-runtime`)은 싣지 않으므로 그 설정은 vim에 컴파일돼 있는 옵션과
`:highlight` 줄로만 만든다.

```
GE-M0   which which        →  /usr/bin/which
GE-M1   vim /tmp/cu.txt    →  줄 번호 · 상태 줄 · -- INSERT -- · 빠른 Esc · 커서 모양 셋(그대로)
```

## 왜 둘을 한 서브프로젝트로 묶나

둘 다 "기계가 무엇을 하는가"가 아니라 "사람이 게스트에서 일하기 편한가"의 일이다. 그리고 둘
다 작다. 우리 코드로 치면 M0은 `make_initrd.sh`의 몇 줄과 목록 한 줄이고, M1은 우리가 쓰는
설정 파일 하나다. 따로 서브프로젝트를 열면 design · 기억 · 표 한 줄이 둘씩 생기는데, 그만큼
나눌 내용이 없다.

순서는 M0 → M1이다. M0이 더 작고 다른 것에 기대지 않는다. M1은 `render` 체인의 기대값을
여럿 바꾸므로 뒤에 둔다. 둘은 서로 독립이라 순서를 바꿔도 동작은 같다.

## 결정

### 결정 1 — `which`는 debianutils의 스크립트를 쓴다(GE-M0)

`project_write_or_reuse`의 두 기준을 대 보면 둘 다 "아니다"다. 우리가 원하는 동작은
`PATH`를 훑어 첫 실행 파일의 경로를 찍는 것이고 Debian의 것과 글자 그대로 같다. 품질
차이도 쓰면서 드러날 자리가 없다. 그래서 갖다 쓴다.

| 후보 | 왜 아닌가 |
|---|---|
| 직접 쓴다(셸 스크립트나 Zig) | 위 두 기준이 다 아니다. 배울 것도 원하는 모양의 차이도 없다 |
| busybox의 `which` applet | busybox는 sysroot에 있지만 게이트 전용이다(WL design 결정 7). initrd에 넣으면 applet 수백 개짜리 바이너리 하나가 이름 하나를 위해 들어오고, 같은 이름을 두 계열(coreutils와 busybox)이 맡는 첫 자리가 된다. 크기는 재지 않았다 — 고르지 않을 것이라 잴 이유가 없었다 |
| seed rc에 `command -v`로 함수나 별칭을 둔다 | rc가 켜진 셸에서만 된다. ISO로 뜬 세션과 `tars.noconfig`에서는 없고, `#!/bin/sh` 스크립트가 `which`를 부르면 여전히 없다 |
| debianutils의 `/usr/bin/which.debianutils` | 고른 것. 1,080바이트짜리 POSIX `#! /bin/sh` 스크립트다(실측 1). `/bin/sh`는 언제나 bash이고(UT 결정 6) 스크립트가 쓰는 것(`set -ef` · `getopts` · `printf` · `case`)은 전부 bash의 builtin이라 새로 딸려 오는 것이 없다 |

싣는 줄은 하나다.

```bash
usr/bin/which.debianutils:usr/bin/which
```

왼쪽과 오른쪽이 다른 이유는 `mawk`→`awk`와 같다. `/usr/bin/which`는 debianutils의
postinst가 alternatives로 만드는 링크라서 `dpkg -x`로 푼 sysroot에는 없다(실측 1). 그래서
실체의 이름을 왼쪽에 적고, 사람이 치는 이름을 오른쪽에 적는다. 자리는 `GUEST_TOOLS`의 맨
끝에 새 층(`층 13 · 셸 편의`)으로 둔다. Dockerfile의 층 번호(층 12가 무선)와 맞춘다.

debianutils가 함께 담는 것(`run-parts` · `savelog` · `ischroot` · `add-shell` ·
`remove-shell` · `update-shells` · `installkernel` · `/usr/share/debianutils/shells`)은
싣지 않는다. 게스트에서 그것을 부를 것이 없다. Dockerfile의 `apt-get download` 목록에
`debianutils:amd64`를 더하면 그 파일들은 sysroot에만 풀린다.

셸마다 `which`라는 이름이 가리키는 것이 다르다.

| 셸 | `which`를 치면 | 우리 스크립트에 닿는 법 |
|---|---|---|
| fish(게이트의 콘솔 셸) | 우리 스크립트. fish에는 `which` builtin이 없다 | 그대로 |
| bash | 우리 스크립트. bash에도 builtin이 없다(`type`이 있다) | 그대로 |
| zsh | zsh의 builtin(`whence -c`와 같다) | `command which` 또는 `/usr/bin/which` |

zsh의 builtin을 막지 않는다. zsh 사용자가 기대하는 동작이 그것이고, 막으려면 seed rc를
고쳐야 하는데 그것은 이 요청의 범위 밖이다.

### 결정 2 — `copy_lib_deps`는 ELF가 아닌 파일을 처음에 건너뛴다(GE-M0)

`install_tool`은 복사한 파일마다 `copy_lib_deps`를 부르고, 그 함수는 파일이 ELF라고
가정한다. 스크립트를 넘기면 빌드는 살지만 `readelf: Error: <파일>: Failed to read file
header`가 stderr에 찍힌다(실측 2). 빌드가 살아남는 이유는 우연이다. `.interp`를 묻는
줄은 `2>/dev/null || true`로 막혀 있고, `readelf -d`는 `for` 문의 단어 목록 안에 있어서
`set -e`가 그 실패를 안 본다. 그래서 그 에러 줄은 실패가 아닌데 실패처럼 생긴 줄이다. 그런
줄이 빌드 로그에 남으면 진짜 에러가 났을 때 사람이 그것을 "늘 나오던 그 줄"로 읽는다.

함수의 맨 앞에서 ELF magic(`7f 45 4c 46`) 4바이트를 보고, 아니면 `return 0`한다.

```bash
if [ "$(head -c 4 "$bin" | od -An -tx1 | tr -d ' \n')" != 7f454c46 ]; then
  return 0
fi
```

| 후보 | 왜 아닌가 |
|---|---|
| `readelf -h "$bin" >/dev/null 2>&1 \|\| return 0` | 망가진 ELF(복사가 중간에 끊긴 바이너리)도 조용히 건너뛴다. 그 바이너리의 의존이 안 실리고, 실패가 게스트에서 그 명령을 처음 칠 때로 밀린다(UT design 위험 3이 막으려던 바로 그 모양) |
| `file`로 종류를 묻는다 | 빌드에 도구 하나와 libmagic이 더 필요하다. 컨테이너에 있는지 재지 않았고, 4바이트를 보는 데 그만한 값이 없다 |
| `#!`로 시작하면 건너뛴다(스크립트만) | 스크립트도 아니고 ELF도 아닌 파일이 목록에 들어오면 여전히 `readelf` 에러가 난다. 그런 파일에 대해 "따라갈 `DT_NEEDED`가 없다"는 말은 스크립트와 똑같이 참이다 |
| `install_tool`에서 거른다 | `copy_lib_deps`를 부르는 자리는 `install_tool` 말고도 셋(terminal · `libnss_myhostname` · zsh 모듈)이다. "ELF만 따라간다"는 그 함수의 성질이므로 그 함수에 둔다 |
| ELF magic 4바이트 | 고른 것. ELF인데 망가진 파일은 지금처럼 `readelf`까지 가서 에러를 낸다. ELF가 아닌 파일에 대해서는 "따라갈 의존이 없다"가 언제나 참이다 |

`od` · `head` · `tr`은 coreutils이고 컨테이너에 이미 있다. `head -c 4`의 출력을 바로 문자열로
비교하지 않고 `od`를 거치는 이유는, 첫 4바이트에 NUL이 있는 파일이면 bash가 명령 치환에서
`ignored null byte` 경고를 stderr에 찍기 때문이다 — 없애려던 종류의 줄을 다시 만드는 셈이다.

스크립트의 인터프리터(`#! /bin/sh`)는 따라가지 않는다. `which`의 인터프리터 `/bin/sh`는
뼈대라서 `tools/check.sh`의 검사 1이 literal로 이미 본다. 인터프리터까지 따라가는 일은
비목표 3이다.

### 결정 3 — 게이트는 `tools` 체인에 검사 둘을 더한다(GE-M0)

새 체인은 없다. `tools` 체인이 "게스트가 명령을 이름으로 찾고, 그 도구가 실제로 도는가"를
보는 자리이고, 설정 디스크 없이 fish로 뜬다. fish에는 `which` builtin이 없으므로 그 체인에서
`which`를 치면 우리 스크립트가 실제로 돈다.

| 검사 | 무엇을 | 왜 |
|---|---|---|
| 1 | 손대지 않는다 | `guest_tools.sh`를 source하므로 새 줄의 오른쪽(`usr/bin/which`)이 initrd에 있는지를 공짜로 본다. 목록을 되읽는 검사라 tautology라는 것도 그대로다 |
| 1c(새것, 부팅 전) | `make_initrd.sh`의 stderr에 `readelf: Error`가 없다 | 결정 2를 지킨다. 누가 ELF 검사를 지우면 빌드는 여전히 초록이므로, 검사가 없으면 그 회귀가 아무 데서도 안 드러난다. 덤으로 망가진 ELF가 내는 같은 에러도 여기서 빨개진다 — 지금은 그 경우에도 빌드가 초록이다 |
| 22(새것, 부팅 뒤) | `which which`를 치고 `/usr/bin/which`를 기다린다. 이어서 `which ge-none; echo ge-rc=$status`를 치고 `ge-rc=1`을 기다린다 | 판정 글자가 출력에만 생긴다(`project_gate_screen_echo`). 친 줄에는 슬래시가 없고 `ge-rc=` 뒤에는 `$status`가 있다. 둘째 줄은 종료 코드의 약속(못 찾으면 조용히 1)을 본다 — 스크립트가 `if which foo >/dev/null`로 쓰는 것이 그 약속이다. fish가 이름을 못 찾았다면 127이므로 패턴은 `ge-rc=1`의 뒤에 공백이나 줄 끝이 오는 것으로 잡는다 |

검사 22는 번호가 21 뒤이고 자리는 음성 검사 19 앞이다. 19는 맨 뒤에서 `Unknown command`를 한
번 보는 그물이라, `which`를 못 찾으면 19도 함께 빨개진다(그 검사의 주석이 말하는 규칙이다).

`/usr/bin/which`가 다른 데서 화면에 나올 수 있는지 확인했다. 같은 부팅의 앞 검사들이 화면에
내는 것(`ls` · `ls -l /bin` · `ps ax` · `/etc/passwd` · `vi --version` · fzf · zoxide · loopback)
어디에도 그 글자가 없다. fish의 자동 제안은 같은 부팅에 앞서 친 명령줄을 다시 보여 주는
것이고, 앞서 `which`를 친 줄이 없다.

### 결정 4 — 모던 설정은 시스템 vimrc 한 파일에 둔다(GE-M1)

lead가 정했다. `kernel/vim/vimrc`(initrd의 `/etc/vim/vimrc`)를 넓힌다. 그 파일은 initrd에
있으므로 설정 디스크가 없는 기계(ISO로 뜬 세션)와 `render` 체인에서도 읽힌다. vim은 사용자
vimrc(`/.vimrc`)를 시스템 vimrc 뒤에 읽으므로 사람은 어느 줄이든 거기서 되돌릴 수 있다.

| 후보 | 왜 아닌가 |
|---|---|
| seed vimrc(`/config/vimrc` · `/.vimrc` 링크) | 설정 디스크가 있는 기계에서만 된다. 그리고 사용자 vimrc는 사람의 것이다 — 우리가 거기 쓰기 시작하면 사람이 고친 것과 우리가 고친 것이 섞인다. 비목표 2 |
| Debian식으로 `/etc/vim/vimrc`가 `vimrc.local`을 읽게 나눈다 | 그 나눔은 패키지가 소유한 파일과 관리자가 소유한 파일을 가르려는 것이다. 우리는 둘 다 소유하므로 나눌 이유가 없다 |
| 시스템 vimrc 한 파일 | 고른 것. CU 결정 7이 커서 세 줄을 그 자리에 둔 이유가 그대로 적용된다 |

이 결정이 CU 결정 7의 한 문장을 낡게 만든다. 그 결정은 "사용자 vimrc가 없으면 vim은 지금처럼
`compatible`로 뜬다 — 커서 말고는 안 바뀐다"고 적었다. GE-M1 뒤로는 vim이 언제나
`nocompatible`로 뜨고 많은 것이 바뀐다. CU design에는 덧붙이는 한 줄로 이 사실을 적는다(M1
plan의 마지막 Task).

### 결정 5 — `vim-runtime`은 싣지 않는다(GE-M1)

lead가 정했다. `vim-runtime` `2:9.1.1230-2`는 Installed-Size가 38,417KB다(실측 3). 지금의
initrd는 firmware 꼬리를 뺀 본체가 압축 전 129,655,808바이트(약 130MB)이므로, 런타임 하나가
본체를 30% 가까이 키운다. 그 38MB의 대부분은 우리가 안 쓸 파일(수백 언어의 syntax · ftplugin ·
indent · 문서 · 색 배합)이고, 쓸 몇 개만 고르는 일은 비목표 1에서 따로 연다.

그 결과 vim에서 안 되는 것이 정해진다. 문법 색(`syntax`), 파일 종류 감지(`filetype`), 색
배합(`colorscheme`), 기본 plugin(`matchparen` · `netrw`)은 읽을 파일이 없다. `:runtime!`는
없는 파일에 대해 조용하지만 아무 일도 안 한다. 사람이 `:syntax on`을 치면 `E484`가 난다. 그래서
vimrc는 vim 바이너리에 컴파일된 옵션과 명시적인 `:highlight` 줄로만 만든다. 런타임을 싣는
것은 비목표 1이다.

### 결정 6 — vimrc의 내용(GE-M1)

전문은 M1 plan의 Task 1에 있다. 원칙은 다섯이다.

1. 첫 유효 줄이 `set nocompatible`이다. 시스템 vimrc는 `compatible`을 끄지 않는다 — 그것은
   사용자 vimrc가 있을 때만 일어난다(실측 4, CU 실측 5). 그리고 `nocompatible`로 바꾸는 순간
   여러 옵션이 기본값으로 다시 정해지므로, 다른 옵션보다 앞에 있어야 한다.
2. 커서 세 줄(`t_SI` · `t_SR` · `t_EI`)은 그대로 남긴다. 머리 주석에 탈출로 `vim -u NONE`과
   `set t_SI= t_SR= t_EI=`를 남긴다.
3. 우리 터미널이 안 하는 것을 켜지 않는다. 마우스 보고가 없으므로 `mouse=`, 창 제목 OSC를
   무시하므로 `notitle`이다. 둘 다 vim 기본값과 같지만, 명시해 두면 그 줄의 주석이 이유를
   남긴다.
4. 색은 256색 `cterm` 값이다. 회색은 232~255 회색 단계에서, 강조색은 앞의 16색에서 고른다.
   앞의 16색은 우리 터미널의 팔레트이므로 vim의 강조색이 터미널 테마를 따라간다.
   `termguicolors`를 켜면 vim이 24비트 색을 직접 보내서 팔레트와 무관해지고, 기본 강조 그룹의
   gui 색(파랑 `0000FF` 같은 것)이 그대로 나온다.
5. 파일은 ASCII이고 줄 이음(`\`)을 쓰지 않는다. 주석은 영어이고 옵션마다 이유를 단다(게스트로
   나가는 설정 파일의 관습, CU-M1 plan 확정 12). 주석은 언제나 따로 한 줄을 차지한다 — `:map`과
   `:autocmd`는 줄 끝 `"`를 주석으로 안 읽기 때문이다.

들어가는 옵션은 아래와 같다. 각 줄의 이유는 vimrc 주석에도 같은 뜻으로 있다.

| 무리 | 옵션 | 이유 |
|---|---|---|
| 인코딩 | `encoding=utf-8` | `LANG=C.UTF-8`이면 이미 utf-8이다. `env -i`처럼 `LANG` 없이 뜬 vim에서도 한글이 안 깨지게 한다 |
| 키 | `backspace=indent,eol,start` | 이것이 없으면 insert에서 Backspace가 줄 머리와 들여쓰기에서 멈춘다 |
| 키 | `ttimeout` `ttimeoutlen=50` | 이것이 커서 모양과 가장 가까운 설정이다. 기본값은 `ttimeoutlen=-1`이라 `timeoutlen`(1000ms)을 쓰고(실측 4), insert에서 Esc를 친 뒤 bar가 최대 1초 남는다 |
| 키 | `timeoutlen=500` | 매핑의 나머지를 반 초 기다린다 |
| 키 | `nnoremap Y y$` | `D` · `C`와 같은 뜻이 된다. Neovim의 기본값과 같다 |
| 키 | `nnoremap <silent> <C-L> :nohlsearch<CR><C-L>` | 화면을 다시 그리는 김에 검색 하이라이트를 끈다. `hlsearch`를 켰을 때 끄는 길이 필요하다 |
| 편집 | `hidden` | 저장하지 않고 버퍼를 바꾼다 |
| 편집 | `autoindent` | 새 줄이 앞 줄의 들여쓰기를 따른다 |
| 편집 | `expandtab` `shiftwidth=4` `softtabstop=4` `tabstop=8` | Tab이 공백 넷을 넣는다. 파일 안의 진짜 탭은 대부분의 도구가 가정하는 8칸으로 보인다 |
| 편집 | `autocmd … Makefile,makefile,GNUmakefile,*.mk setlocal noexpandtab` | Makefile은 진짜 탭이 필요하다. 그것을 말해 줄 filetype plugin이 없으므로 파일 이름으로 말한다(실측 5에서 `noexpandtab`이 됐다) |
| 편집 | `nrformats-=octal` | 기본값에 `octal`이 있다(실측 4). `007`에서 Ctrl-A가 `010`이 아니라 `008`이 된다 |
| 편집 | `formatoptions+=j` | `J`로 이을 때 주석 머리를 지운다 |
| 검색 | `incsearch` `hlsearch` `ignorecase` `smartcase` | 치는 동안 매치를 보이고, 남겨 두고, 대문자가 없으면 대소문자를 무시한다 |
| 화면 | `number` `relativenumber` | 커서 줄은 절대 번호, 나머지는 거리다. `5j` 같은 이동의 수를 화면에서 읽는다 |
| 화면 | `cursorline` `cursorlineopt=number` | 커서 줄의 번호만 밝힌다. 줄 전체를 밝히면 block 커서 아래 칸의 배경까지 바뀐다(결정 7) |
| 화면 | `scrolloff=5` `sidescrolloff=5` | 커서 둘레에 다섯 줄 · 다섯 칸의 맥락을 남긴다 |
| 화면 | `display=truncate` | 화면에 다 안 들어가는 마지막 줄을 `@@@`로 줄이지 않고 들어가는 만큼 보인다 |
| 화면 | `list` `listchars=tab:>-,trail:-,nbsp:+` | 탭 · 줄 끝 공백 · no-break space를 ASCII로 보인다 |
| 화면 | `showcmd` `showmode` | 치다 만 명령과 지금 모드를 마지막 줄에 보인다. `-- INSERT --`가 이것이다 |
| 화면 | `laststatus=2`와 `statusline` | 창마다 상태 줄이 있다 — 이름 · 표시 · 인코딩 · 줄 끝 형식 · 위치. `ruler`를 대신한다 |
| 화면 | `wildmenu` `wildmode=longest:full,full` | 명령 줄 자동완성이 공통 부분을 채우고 메뉴를 보인다 |
| 화면 | `shortmess+=I` | 파일 없이 띄울 때 인트로 화면이 없다 |
| 화면 | `belloff=all` | 벨도 화면 깜빡임(`t_vb`)도 없다 |
| 화면 | `splitbelow` `splitright` | 새 창이 아래와 오른쪽에 열린다 |
| 화면 | `mouse=` `notitle` | 원칙 3 |
| 파일 | `history=1000` | 명령 줄 기록을 길게 남긴다 |
| 파일 | `noswapfile` `nobackup` | 게스트는 사용자가 한 명이다. swap 파일이 `/config`나 git 작업 트리에 생기면 지울 것만 는다 |
| 파일 | `undofile` `undodir=/tmp/vim-undo`(없으면 `mkdir()`로 0700) | 파일을 닫았다 열어도 되돌리기가 남는다. `/tmp`가 tmpfs라 다음 부팅까지다 |
| 파일 | `nomodeline` | 사용자가 root이므로 modeline을 끈다. root에게는 vim의 기본값도 꺼짐이지만(실측 4) 의도를 적어 둔다 |
| 색 | `background=dark` | 우리 터미널의 바탕이 어둡다. 명시해 두면 vim이 나중에 터미널의 답(OSC 11)을 보고 바꾸지 않는다 — 바꾸면 아래 강조 그룹이 기본값으로 돌아간다 |
| 색 | `highlight` 아홉 줄 | `LineNr` · `CursorLineNr` · `StatusLine` · `StatusLineNC` · `VertSplit` · `Visual` · `Search` · `IncSearch` · `SpecialKey`. 전부 `cterm=NONE`이라 반전(reverse)을 안 쓴다(결정 7) |

넣지 않은 것과 그 이유:

| 후보 | 왜 안 넣나 |
|---|---|
| `syntax on` · `filetype plugin indent on` · `colorscheme` | 결정 5. 읽을 파일이 없고 `E484`를 낸다 |
| `smartindent` | filetype 규칙이 없으면 `#`로 시작하는 줄을 전부 0열로 당긴다. 셸 · Python · 설정 파일의 주석이 그렇게 된다 |
| `listchars`에 `»` · `·` · `␣` | lead의 후보였다. unifont에 글리프는 있을 것이지만, 셋 중 `»`(U+00BB)와 `·`(U+00B7)는 East Asian Ambiguous 폭이다. 사람이 `ambiwidth=double`을 쓰면 화면이 어긋난다. 그리고 vimrc가 ASCII가 아니게 되어 `scriptencoding`이 하나 더 필요하다. ASCII로도 같은 정보를 보인다 |
| `cursorline`만(줄 전체) | 커서 줄의 배경이 바뀌면 block 커서가 반전하는 칸의 색이 바뀐다. 결정 7 |
| `let mapleader = " "` | 사용자의 `/.vimrc`와 사람이 가져다 붙이는 설정 조각의 모든 `<leader>` 뜻이 바뀐다. 시스템 vimrc가 정할 취향이 아니다. 그래서 `<leader>` 매핑도 두지 않는다 |
| `termguicolors` | 원칙 4 |
| `mouse=a` | 우리 터미널에 마우스 보고가 없다 |
| `ruler` | `laststatus=2`와 `statusline`이 있으면 `ruler`는 안 보인다 |
| swap 파일을 `/tmp`로(`directory=/tmp//`) | 지울 것은 줄지만, 사용자가 한 명이고 tmpfs가 전원과 함께 사라지는 기계에서 복구 가치가 작다. 끄는 쪽이 단순하다 |

`viminfo`는 vim의 기본값(`'100,<50,s10,h`, 실측 4)을 그대로 쓴다. `nocompatible`이 되면서
켜지는 것이고, vim을 나올 때 `/.viminfo`에 명령 줄 기록과 표시를 쓴다. 홈이 tmpfs라 재부팅에
사라진다. 남기는 일은 비목표 2와 같은 일이다.

### 결정 7 — `render` 체인의 기대값이 바뀌고, 검사 셋이 더해진다(GE-M1)

새 체인은 없다. `render` 체인이 vim을 띄우는 유일한 체인이고(검사 25~32), 그 판정 중 넷이
vimrc의 영향을 받는다.

| 검사 | 지금 | GE-M1 뒤 | 왜 |
|---|---|---|---|
| 25 기다림 | `\[New File\]\|Press ENTER` | `\[New\]\|Press ENTER` | `nocompatible`의 `shortmess` 기본값에 `n`이 있어서 vim이 `[New File]` 대신 `[New]`라고 쓴다(실측 4 · 5) |
| 25~29 커서 | `row=0 col=0` | `row=0 col=4` | `number`가 줄 번호 칸을 연다. `numberwidth` 기본값 4(숫자 셋 + 공백 하나)라 빈 버퍼의 커서가 4열이다. `relativenumber`는 폭을 안 바꾼다. 4는 셈이고 게스트에서 잰 값이 아니다 — M1 plan이 잰다 |
| 30 마지막 프레임 | `New File`이 없다 | `[New]`가 없다 | 25와 같은 이유. 안 고치면 이 음성 판정이 언제나 초록이 된다 |
| 31(`vim -u NONE`) | `[New File]` · `col=2` | 그대로 | 시스템 vimrc를 안 읽으므로 `compatible`이고 `shortmess=S`다(실측 5) |

반전 셀 수(25~29의 1 · 0 · 1 · 0 · 1)는 안 바뀌어야 한다. 그렇게 되도록 고른 것이 셋이다.

- `cursorlineopt=number`. 커서 줄 전체에 배경을 깔면, block 커서가 반전하는 칸의 `fg`가 기본
  배경(`102030`)이 아니라 그 배경색이 된다. `inverted_now`는 `fg=102030`인 칸을 세므로 1이 0이
  된다.
- 강조 그룹에 반전을 안 쓴다. vim의 기본 `StatusLine`은 `cterm=reverse,bold`다. 반전된 칸은
  `fg`가 `102030`이 되므로, 상태 줄의 칸이 `style>` 덤프에 찍히면 반전 셀로 세진다. 지금은 덤프가
  0~1행에서 잘려서(CU-M1 실측 5) 45행의 상태 줄까지 안 가지만, 그 성질에 기대지 않는다.
- 줄 번호 칸의 색. `LineNr`(243)과 `CursorLineNr`(11)은 `102030`이 아니다.

판정이 "style 덤프가 커서 칸을 지났다"(`style_covers`)인 것은 그대로다. 커서는 0행 4열이고,
덤프는 0행의 줄 번호 칸 넷과 커서 칸을 먼저 찍는다.

그리고 시스템 vimrc가 읽혔다는 것을 직접 보는 검사 셋을 더한다. 지금까지는 커서 모양(26의
bar)이 그 증거의 전부였다.

| 검사 | 자리 | 본다 |
|---|---|---|
| 33 | 25 뒤 | vim을 띄운 뒤의 화면에 상태 줄의 `utf-8 unix`가 있다. 그 글자는 우리 `statusline`이 만들고, 친 명령줄(`printf …; vim /tmp/cu.txt`)에 없다 |
| 34 | 26 뒤 | `i`를 친 뒤의 화면에 `-- INSERT --`가 있다. `showmode`가 켜졌다는 뜻이다 |
| 35 | 31 안 | `vim -u NONE` 세션의 화면에 `-- INSERT --`도 `utf-8 unix`도 없다. 33 · 34가 우리 vimrc에서 왔다는 대조다 |

`[New]` 자체도 증거다. vimrc는 `shortmess`에 `n`을 넣지 않는다. 그 글자는 `set nocompatible`이
돌아야만 나오므로, 그 줄을 지우면 검사 25의 기다림이 15초를 다 쓰고 빨개진다. M1 plan의
mutation 하나가 이것을 본다.

vimrc에 문법 에러가 생기면 vim은 대체 화면에 들어가기 전에 `Error detected while processing
/etc/vim/vimrc`와 `E…:` 줄과 `Press ENTER`를 찍는다. 검사 25가 기동 직후에 그것을 찾으므로
vimrc의 에러를 잡는 자리도 검사 25다. M1 plan의 mutation 하나가 이것을 본다.

### 결정 8 — 구현은 서브에이전트가, 검증 · 게이트 · commit은 lead가 한다

lead가 정했다. GE-M0은 Sonnet 서브에이전트가, GE-M1은 Opus 서브에이전트가 plan만 보고
구현한다. lead(Fable)는 결과 파일을 `Read`로 대조하고, 게이트를 돌리고, commit한다. 그래서 두
plan은 고칠 파일과 심볼, 편집의 모양, 칠 명령, 기대하는 출력, mutation을 다 적는다.

## 검증

### GE-M0 — `tools/check.sh`

- 검사 1: `usr/bin/which`가 initrd에 있다(목록 되읽기, 손 안 댐).
- 검사 1c(새것): `make_initrd.sh`의 stderr에 `readelf: Error`가 없다.
- 검사 22(새것): `which which` → `/usr/bin/which`, `which ge-none; echo ge-rc=$status` →
  `ge-rc=1`.
- mutation 둘. ELF 검사를 지운 `make_initrd.sh`로는 1c가 부팅 전에 빨개진다. `which` 줄을 지운
  `guest_tools.sh`로는 검사 1이 초록인 채(tautology라서) 22가 빨개진다.

### GE-M1 — `render/check.sh`

- 검사 25~30의 기대값 변경(결정 7의 표)과 검사 33~35.
- mutation 셋. `number`와 `relativenumber`를 지우면 검사 25가 `col=0`으로(`relativenumber`만
  남아도 줄 번호 칸이 열리므로 둘 다 지운다), 없는 옵션 한 줄을 넣으면 검사 25가
  `E518`로, `set nocompatible`을 지우면 검사 25가 `[New]` 기다림으로 빨개진다.

### 둘 다

루트 게이트 18체인 × 3, 약 1시간 5분. initrd가 바뀌므로 열여덟 체인이 전부 새 initrd로
부팅한다.

## Milestone

### GE-M0 — `which`

Dockerfile에 `debianutils:amd64`(이미지 재빌드 30~50초), `guest_tools.sh`에 한 줄과 층 13
주석, `copy_lib_deps`의 ELF 검사, `tools/check.sh`의 검사 1c · 22. 이 milestone이 끝나면
게스트의 fish와 bash에서 `which <이름>`이 경로를 찍는다.

### GE-M1 — 모던 vimrc

`kernel/vim/vimrc`를 넓히고, `render/check.sh`의 vim 구간 기대값을 고치고 검사 33~35를
더한다. 이 milestone이 끝나면 게스트에서 `vim`이 줄 번호 · 상태 줄 · `-- INSERT --`와 함께
뜨고, Esc가 50ms 안에 normal로 돌아온다.

## 위험

1. `nocompatible`이 되면 vim이 기동할 때 터미널에 묻는 것이 는다(실측 6). 2차 장치 속성
   (`ESC[>c`), 커서 위치(`ESC[6n` 두 번), 전경 · 배경색(`OSC 10` · `OSC 11`), 포커스 보고
   켜기(`ESC[?1004h`)다. 우리 터미널은 라이브러리가 만드는 답을 `write_pty`로 pty에 돌려준다
   (TQ-M1). 그 답은 로그에 안 찍힌다. vim이 답을 잘못 읽어 글자로 받아들이면 빈 버퍼에 글자가
   생겨 커서가 4열에서 밀리므로 검사 25가 빨개진다. 포커스 보고는 vim이 켜기만 하고, 우리
   터미널이 패널 포커스를 바꿀 때 `ESC[I` · `ESC[O`를 보내는지는 확인하지 않았다.
2. `autoindent`와 붙여넣기. 우리 터미널은 `Cmd+V`를 bracketed paste로 감싸지 않는다(CM
   design 결정 9, `main.zig`의 `dumpPaste` 주석). vim이 `ESC[?2004h`를 보내도 붙인 글자는 친
   글자와 구별되지 않는다. 그래서 insert 모드에서 들여쓴 여러 줄을 붙이면 `autoindent`가 줄마다
   들여쓰기를 더해 계단이 된다. GE-M1 전에는 `compatible`이라 `autoindent`가 꺼져 있어서 이
   증상이 없었다. 우회는 붙이기 전에 `:set paste`, 붙인 뒤에 `:set nopaste`다. 고치는 일은 비목표
   4다.
3. `expandtab`. 탭이 뜻을 갖는 파일 중 Makefile만 autocmd로 막는다. Go 소스처럼 탭을 쓰는 다른
   형식에서는 공백이 들어간다(gofmt가 고치기는 한다).
4. `/usr/share/vim/vim91`의 판 번호(CU 위험 4)는 그대로다. 이 서브프로젝트가 새로 만드는 위험은
   아니다.
5. Debian이 debianutils에서 `which.debianutils`의 이름이나 자리를 바꾸면 `install_tool`이 빌드
   때 `not found in sysroot`로 죽는다. 조용한 실패가 아니라서 받아들인다.
6. `/bin/sh`가 bash가 아니게 되면 `which`의 인터프리터가 바뀐다. 스크립트가 POSIX sh라 dash로도
   돌 것이지만, `/bin/sh`를 바꾸는 일 자체가 UT 결정 6을 다시 여는 일이다.
7. M1의 측정(실측 4~6)은 컨테이너의 arm64 vim(같은 판)과 `script`의 pty로 했다. 우리 터미널에서의
   커서 열 · style 덤프 · 상태 줄의 실제 모양은 게스트에서만 잴 수 있고, M1 plan이 잰다.

## 착수 전에 실측한 것

1~8은 lead가 2026-10-04에 쟀다(그대로 옮긴다). 9~12는 design을 쓰며 같은 날 컨테이너에서
쟀다.

1. sysroot(`tars-devcontainer` 이미지의 `/usr/local/amd64-sysroot`, Debian trixie)에 `which`가
   하나도 없다. Debian은 `which`를 패키지 `debianutils`(5.23.2, `.deb` 92,412바이트,
   Installed-Size 369KB)에 `/usr/bin/which.debianutils`로 담는다. 1,080바이트짜리 POSIX
   `#! /bin/sh` 스크립트이고, `set -ef`, `getopts`로 `-a` · `-s`를 받고, `$PATH`를 훑는다.
   `/usr/bin/which`는 postinst가 만드는 Debian alternatives 링크라서 `dpkg -x` 뒤에는 없다.
   debianutils는 그 밖에 `run-parts` · `savelog` · `ischroot` · `add-shell` ·
   `remove-shell` · `update-shells` · `installkernel` · `/usr/share/debianutils/shells`를
   담는다.
2. `make_initrd.sh`는 `set -euo pipefail`이다. ELF가 아닌 파일을 `copy_lib_deps`에 주면
   `.interp`를 묻는 줄은 `2>/dev/null || true`로 조용하고, `for soname in $(...)`의 단어
   목록 안에 있는 `readelf -d`는 errexit를 안 일으킨다. 그래서 빌드는 살지만 stderr에
   `readelf: Error: <파일>: Failed to read file header`가 찍힌다(컨테이너에서 두 줄짜리 스크립트로
   쟀다). 1,080바이트인 `which.debianutils`처럼 ELF 헤더 64바이트보다 큰 파일이면 글자가
   `readelf: Error: Not an ELF file - it has the wrong magic bytes at the start`다(M0 실측 4) —
   검사 1c의 패턴 `readelf: Error`는 둘 다 잡는다.
3. `vim-runtime` `2:9.1.1230-2`는 Installed-Size 38,417KB(`.deb` 7,126,616바이트)다. 지금의
   initrd(`kernel/initrd.cpio`, 2026-10-04 14:07 빌드)는 압축된 채 90MB이고 `gzip -dc`로 풀면
   230,445,056바이트인데, 그중 100,789,248바이트가 WL-M1의 firmware 꼬리다. 본체는
   129,655,808바이트(약 130MB)다. lead가 처음 planner에게 준 "약 42MB"는 DI-M0 때(2026-09-23)의
   값이라 지금과 다르고, 이 숫자로 바꿨다.
4. vim 바이너리는 `vim.basic`(`+eval +syntax +cursorshape`, 3,921,984바이트)이다. 게스트에는
   사용자 vimrc가 없고 `/etc/vim/vimrc`(저장소의 `kernel/vim/vimrc`)가 시스템 vimrc이며
   `/usr/share/vim/vim91/defaults.vim`은 주석뿐인 stub이다. 시스템 vimrc는 `compatible`을
   안 끈다(사용자 vimrc만 끈다 — CU 실측 5에서 vim은 지금 `compatible`이고 `showmode`가 꺼진 채
   뜬다).
5. 화면 셸의 `TERM`은 `xterm-256color`(`init/src/environ.zig`), `LANG=C.UTF-8`이다. 우리
   터미널은 ghostty vt 위에 있고 true color SGR을 그리지만(TR) 마우스 보고가 없고 창 제목 OSC에
   반응하지 않는다.
6. `render/check.sh`의 검사 25~32는 `printf '\033[H\033[2J'; vim /tmp/cu.txt`를 치고
   `[New File]`(또는 E1187을 잡으려고 `Press ENTER`)을 기다린 뒤 `cursor>` 줄을 본다. bar는
   `ink=32 box=2x16`, underline은 `ink=16 box=8x2`이고, vim의 NonText 색 `~` 줄이 96줄짜리
   style 덤프를 언제나 채우므로 `style_covers`를 쓴다. `render` 체인 하나는 약 2분이다(CU-M1이
   1분 47초를 쟀다).
7. `tools/check.sh`의 검사 1은 `guest_tools.sh`를 source하므로 `GUEST_TOOLS`의 새 줄은 정적으로
   공짜로 덮인다. 그 체인의 콘솔 셸은 fish이고 fish에는 `which` builtin이 없다. zsh에는 우리
   것을 가리는 `which` builtin이 있다.
8. 새 체인은 45481번 포트부터 쓰지만 두 milestone 다 새 체인이 필요 없다. 루트 게이트는
   18체인 × 3, 약 1시간 5분이다.

9. `nocompatible`일 때의 기본값(`vim -u NONE -N`, 같은 판 `2:9.1.1230-2` arm64). vimrc가 고치는
   옵션의 출발점이다.

   ```
   shortmess=filnxtToOS  nrformats=bin,octal,hex  viminfo='100,<50,s10,h  nomodeline
   ttimeoutlen=-1  timeoutlen=1000  backspace=indent,eol,start  showmode  laststatus=1
   ```

   `shortmess`의 `n`이 `[New File]`을 `[New]`로 줄인다. `nomodeline`인 것은 사용자가 root이기 때문이다(vim의 기본값은
   root가 아니면 켜짐이다).

10. 제안한 vimrc(M1 plan Task 1의 전문)를 게스트처럼 꾸민 컨테이너에서 띄웠다. 런타임을 지우고
    주석 한 줄짜리 stub `defaults.vim`만 두고, vimrc를 `/etc/vim/vimrc`에 두고, 빈 `HOME`,
    `TERM=xterm-256color`, `LANG=C.UTF-8`, `script`로 47×100 pty를 줬다. 키 사이는 1.5초다.

    | 경우 | 친 것 | DECSCUSR | 화면에 나온 것 |
    |---|---|---|---|
    | 새 vimrc | `vim /tmp/cu.txt`, `i` Esc `R` Esc `:q!` | 6 · 2 · 4 · 2 | `[New]` · `-- INSERT --` · `-- REPLACE --` · 상태 줄 ` utf-8 unix  0:0  100%`. `E숫자:`도 `Press ENTER`도 없다 |
    | `vim -u NONE` | `i` `ab` Esc `:q!` | 없음 | `[New File]`. `-- INSERT --`도 상태 줄도 없다 |
    | 새 vimrc, Makefile | `vim /tmp/Makefile`, `:set et?` | — | `noexpandtab` |

    vim을 나온 뒤 `/tmp/vim-undo`(`drwx------`)와 `$HOME/.viminfo`(972바이트)가 생겼다. 커서
    모양 셋은 CU-M1과 같다 — 새 줄들이 커서 세 줄을 안 건드린다.

11. 같은 조건에서 vim이 터미널에 보낸 제어 시퀀스를 옛 vimrc(커서 세 줄)와 비교했다. SGR ·
    커서 이동 · 지우기 · DECSCUSR을 뺀 나머지 중 새 vimrc에만 있는 것은 다섯 종류다.

    ```
    ESC[>c            2차 장치 속성 질의(t_RV)
    ESC[6n  ×2        커서 위치 질의(t_u7 등)
    ESC]10;?BEL       전경색 질의(t_RF)
    ESC]11;?BEL       배경색 질의(t_RB)
    ESC[?1004h / l    포커스 보고 켜기 · 끄기
    ```

    `ESC[?2004h`(bracketed paste)는 옛 vimrc에서도 이미 보냈다. 반대로 옛 vimrc에만 있는 것은
    `ESC=`(키패드 응용 모드) 하나다.

12. 앞의 측정 중 Ex 모드(`vim -es`)로 vimrc를 읽히려던 것은 쓸 수 없었다. `-es`는 `-u`가 없으면
    vimrc를 안 읽어서 `compatible`인 채로 끝났다. vimrc에 에러가 없다는 판정은 10의 pty
    기동(화면에 `E숫자:`와 `Press ENTER`가 없다)에서 왔다.

## 비목표

1. `vim-runtime`을 싣는 것(결정 5). 문법 색과 filetype을 원하면 따로 여는 서브프로젝트다 — 그때는
   런타임 전체가 아니라 필요한 syntax 파일 몇 개만 고르는 길도 저울에 올린다.
2. 사용자 vimrc를 `/config`로 seed하거나 부팅 사이에 남기는 것(`/.vimrc` · `/.viminfo` →
   `/config`). CU 비목표 7과 같은 일이다.
3. `copy_lib_deps`가 스크립트의 인터프리터(`#!` 줄)까지 따라가는 것(결정 2).
4. 터미널의 bracketed paste(위험 2). `Cmd+V`의 모양을 바꾸는 일이라 CM 결정 9와 FP의 결정을 다시 연다.
5. zsh의 `which` builtin을 우리 스크립트로 바꾸는 것(결정 1).
6. debianutils의 다른 도구(`run-parts` 등).
7. `tars.conf`로 vim 설정을 고르게 하는 것.

## 닫을 때(lead의 몫)

서브프로젝트를 닫을 때 lead가 한다. 구현 서브에이전트는 안 한다.

- 이 design의 `Status:`를 `끝났다(날짜)`로 고친다.
- `CLAUDE.md`의 완료 표에 한 줄.
- `docs/decisions/project_guest_ergonomics.md`를 만들고 `MEMORY.md`에 한 줄.
- `docs/decisions/project_cursor_shape.md`의 "시스템 vimrc 세 줄" · "사용자 vimrc가 없으면 vim은
  그대로 `compatible`이라 커서 말고는 안 바뀐다"에 GE-M1이 바꿨다는 한 줄과
  `[[project_guest_ergonomics]]`.
- `HANDOFF.md`.

## 관련

- `docs/specs/2026-10-04-tars-cursor-shape-design.md` — 시스템 vimrc와 stub이 생긴 자리(결정 7),
  `render` 검사 25~32
- `docs/specs/2026-09-10-tars-userland-tools-design.md` — `GUEST_TOOLS`의 형식과 이름 바꾸기
  (결정 4), `/bin/sh`(결정 6)
- `docs/decisions/project_write_or_reuse.md` — 결정 1의 저울
- `docs/decisions/project_measuring_tool_cost.md` — alternatives 링크는 `dpkg -x`로 안 생긴다
- `docs/decisions/project_gate_screen_echo.md` — 검사 22 · 33의 판정 글자
