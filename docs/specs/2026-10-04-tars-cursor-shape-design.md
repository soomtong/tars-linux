# TARS Cursor Shape — Design

Date: 2026-10-04
Status: 끝났다(2026-10-04, CU-M0 · CU-M1). plan은
`docs/plans/2026-10-04-tars-cursor-shape-cu-m0.md` · `docs/plans/2026-10-04-tars-cursor-shape-cu-m1.md`이고
각 끝에 실측이 있다. 착수 전에 잰 값은 아래 "착수 전에 실측한 것" 절에 있다.

사용자의 요청에서 시작한다(2026-10-04): "vi에서 입력 모드에 따른 커서
모양이 항상 동일해서 불편함이 있다. normal mode/insert mode에 따라 변경
가능한지. (보통 노멀 모드는 블록 타입; 인서트 모드는 버티컬 라인을
사용한다)"

## 한 줄 요약

터미널이 DECSCUSR(`CSI Ps SP q`)이 정한 커서 모양 셋(block · bar ·
underline)을 그리고, 게스트의 vi가 모드를 바꿀 때 그 시퀀스를 보내게 한다.
앞의 것은 우리 렌더러의 일이고(CU-M0), 뒤의 것은 vi 바이너리를 바꾸고
시스템 vimrc 세 줄을 initrd에 넣는 일이다(CU-M1).

```
normal   █        block      — 지금처럼 셀 반전
insert   ▏        bar        — 셀 왼쪽 2픽셀 세로 띠
replace  ▁        underline  — 셀 아래 2픽셀 가로 띠
```

## 왜 이 일이 둘로 나뉘는가

"vi에서 모양이 안 바뀐다"에는 원인이 둘 있고, 둘 다 사실이다.

1. 우리 렌더러가 모양을 모른다. `vt.zig`의 `cells()`는 커서를 언제나 한 칸
   반전으로 그리고(`std.mem.swap(u32, &fg, &bg)`), `CellGlyph`에도 렌더
   루프에도 모양이라는 개념이 없다. 라이브러리(ghostty vt)는 DECSCUSR을
   해석해 `RenderState.cursor.visual_style`에 담아 주는데 아무도 안 읽는다
   (실측 9).
2. 게스트의 vi가 그 시퀀스를 보내지 않는다. 게스트의 `vi` · `vim`은
   Debian `vim-tiny`이고, 이 빌드는 `-cursorshape`라 `t_SI` · `t_EI`를
   어떻게 설정해도 한 바이트도 안 낸다(실측 1 · 2). terminfo의 `Ss`가 있어도
   vim은 그것으로 `t_SI`를 채우지 않는다(실측 3).

1만 고치면 터미널은 준비가 됐는데 vi가 말을 안 한다. 2만 고치면 vi가
말하는데 터미널이 못 알아듣는다. 그래서 순서는 1 → 2다. 1은 vi와 무관하게
값을 한다. DECSCUSR을 보내는 프로그램이면 어느 것이든(fish의 vi 모드,
나중에 들일 편집기, `printf '\033[6 q'`) 모양이 바뀐다.

## 결정

### 결정 1 — 모양 셋을 이렇게 그린다

| 모양 | 그리는 법 | 픽셀(셀 8×16) |
|---|---|---|
| block | 지금처럼 `cells()`가 셀의 두 색을 맞바꾼다 | 셀 전체 |
| bar | 셀 왼쪽에 세로 띠를 전용 색으로 칠한다 | 2×16 |
| underline | 셀 아래에 가로 띠를 전용 색으로 칠한다. 폭 2 글자 위면 두 칸 폭이다 | 8×2(16×2) |

두께 후보:

| 후보 | 왜 아닌가 |
|---|---|
| 1픽셀 | 셀이 8픽셀이라 실기 화면에서 커서가 안 보일 만큼 가늘다. 게이트의 ink 값(16)이 underline(8×2=16)과 같아져서 둘이 숫자로 안 갈린다 |
| 3픽셀 이상 | 셀의 절반에 가까워져 block과 bar의 차이가 흐려진다. 글리프의 왼쪽 획을 더 많이 덮는다 |
| 2픽셀 | 고른 것. bar 32 · underline 16이라 ink 값만으로 둘이 갈린다 |

색 후보:

| 후보 | 왜 아닌가 |
|---|---|
| 셀의 `fg`(block 반전이 보여 주는 색과 같다) | 커서 칸의 글자도 같은 색이라 게이트가 띠의 픽셀과 글리프의 픽셀을 못 가른다 |
| 기본 전경 `0xFFFFFF` | 같은 이유다. 셸 글자 대부분이 이 색이다 |
| OSC 12가 정한 커서 색(`state.colors.cursor`) | 지금 `init`이 `.cursor = .unset`으로 준다. 따르게 하면 값이 앱에 따라 바뀌어 게이트가 상수로 못 본다(비목표 3) |
| 전용 `CURSOR_COLOR = 0x00F0F0F0` | 고른 것. CI 결정 3 · WP의 `SEPARATOR`와 같은 이유다 — 이 색은 커서 띠만 쓰므로 셀 안에서 이 색의 픽셀을 세면 그것이 곧 띠다. 기본 팔레트 256색(이름 16 · 큐브 · 회색 8~238)에 없는 값이다(실측 9). 사람 눈에는 흰색과 구별이 안 된다 |

`block_hollow`(ghostty만의 모양, 가운데가 빈 block)는 block으로 그린다.
DECSCUSR로는 만들 수 없는 값이다 — 라이브러리 설정의 기본 모양
(`default_cursor_style`)으로만 생기고, 우리는 그 값을 안 준다(실측 9).
`switch`에 `else`를 안 두고 넷을 다 적어서, 업스트림이 모양을 더하면 컴파일이
막히게 한다.

### 결정 2 — 깜빡임은 그리지 않는다

DECSCUSR의 홀수 번호(1 · 3 · 5)와 `cursor_blinking` 모드는 무시하고 같은
모양을 가만히 그린다. `\033[5 q`는 `\033[6 q`와 똑같이 보인다.

| 후보 | 왜 아닌가 |
|---|---|
| 타이머로 깜빡이기 | 렌더가 이벤트 기반이다 — `main.zig`의 `poll`이 시간 제한 `-1`로 잠들고, `needs_redraw`가 문지기다(실측 11). 깜빡이려면 timerfd와 반 초마다의 다시 그리기가 필요하다. 그러면 게이트가 무너진다. `gate_lib.sh`의 `type_keys`는 "아무 일도 없으면 로그가 조용하다"를 전제로 키가 도착했는지 판정한다(그 함수의 주석). 반 초마다 프레임 덤프가 찍히면 그 전제가 거짓이 된다 |
| 무시한다 | 고른 것. vim의 기본(우리가 넣을 vimrc)은 깜빡이지 않는 2 · 4 · 6을 쓴다 |

### 결정 3 — 모양은 `vt.zig`가 정하고 `main.zig`는 사각형을 칠한다

`cells()`가 셸 커서에 대한 판단을 한 번 하고 그 결과를 `Screen`에 남긴다.
`main.zig`는 접근자로 그 결과를 받아, block이 아니면 사각형 하나를 칠한다.
`CellGlyph`는 안 바뀐다.

```zig
pub const CursorShape = enum { block, bar, underline };
pub const PxRect = struct { x: u32, y: u32, w: u32, h: u32 };
pub const CursorMark = struct {
    row: u16,
    col: u16,
    asked: CursorShape, // 라이브러리가 든 모양(DECSCUSR이 정한 것)
    shape: CursorShape, // 실제로 그리는 모양(결정 4가 덮어쓸 수 있다)
    cols: u8,           // 덮는 칸 수 — preedit이나 폭 2 글자 위면 2
    px: ?PxRect,        // 패널 원점 기준 픽셀 사각형. block이면 null
};
```

| 후보 | 왜 아닌가 |
|---|---|
| `CellGlyph`에 모양 필드를 더한다 | 셀 수천 개가 필드 하나를 나르는데 쓰는 것은 하나다. 그리고 bar 커서가 빈 칸에 있으면 그 셀은 지금 규칙("글자도 없고 색도 기본이면 건너뛴다")에 걸려 아예 안 나온다 — 커서 셀만 억지로 내보내는 예외가 생긴다 |
| `main.zig`가 `state.cursor`를 직접 읽는다 | copy mode · preedit · 포커스의 우선순위를 `main.zig`가 다시 구현해야 한다. 같은 판단이 두 자리에 생기고, 어긋나면 반전과 띠가 함께 그려진다. TR 결정 1("커서와 색은 `vt.zig`가 해소한다")과도 어긋난다 |
| `Screen.cursorMark()`가 매번 다시 계산한다 | 위와 같은 병이다. 계산하는 코드가 둘이면 언젠가 갈린다 |
| `cells()`가 한 번 계산해 `shell_cursor` 필드에 두고, `cursorMark()`가 그것을 돌려준다 | 고른 것. 반전할지(block) 띠를 칠할지(bar · underline)를 같은 값 하나가 정한다. `defaultFg()`처럼 "`cells()` 뒤에 부른다"는 규칙 하나가 붙는다 |

픽셀 사각형을 `vt.zig`가 계산하는 것은 TG의 선례를 따른 것이다 —
`images()`가 placement를 픽셀 사각형으로 내고 `image.zig`가 칠한다(TG
결정). `Screen`이 `cell: CellPx`를 이미 들고 있으므로(WP-M1) 새로 받을
것이 없고, `vt_test`가 사각형을 숫자로 본다.

`main.zig`는 `renderPane`의 맨 끝(`above_text` 이미지 뒤)에서 띠를
칠한다. 커서는 무엇에도 안 가려져야 한다. 띠는 그 칸의 글리프 위에
그려지므로 글자의 왼쪽(bar) 또는 아래(underline) 2픽셀을 덮는다. ghostty
앱 렌더러도 같다.

`dumpStyles`가 안 흔들리는 이유. block일 때는 반전이 지금과 바이트까지
같다. bar · underline일 때는 커서 셀이 반전되지 않으므로 `style>` 줄에서
사라진다 — 그래서 새 덤프 줄이 필요하다(결정 6). `pixel>`은 셀 가운데
(`CELL_W / 2`, `ROW_HEIGHT / 2`)를 읽고, 띠는 왼쪽 두 열 또는 아래 두 줄이라
가운데에 안 닿는다(실측 12).

### 결정 4 — preedit과 copy 커서는 지금 규칙 그대로이고, 모양보다 앞선다

`cells()`의 커서 층 우선순위는 그대로다. 모양은 그 맨 아래에 붙는다.

```
copy mode인가        → copy 커서를 반전한다. 셸 커서는 없다(shell_cursor = null)
포커스 없는 패널인가 → 셸 커서는 없다(결정 5)
뷰포트 밖인가        → 셸 커서는 없다(지금처럼)
조합 중인가          → 두 칸 반전(block). DECSCUSR 모양을 무시한다
그 밖                → DECSCUSR 모양
```

| 자리 | 왜 이렇게 하나 |
|---|---|
| copy 커서는 언제나 block | copy mode는 우리 UI이고 vim의 normal 모드에 해당한다. 앱이 정한 모양을 따를 이유가 없다. copy 체인의 `inverted_cells`가 이 반전을 센다 |
| preedit은 모양을 무시한다 | 두 칸 반전은 커서이기 전에 "아직 확정 안 된 글자"의 표시다(HI 결정 4). bar로 그리면 조합 중인 글자가 바탕과 구별이 안 된다. hangul 체인이 그 두 칸을 센다. vim insert 모드에서 한글을 치면 조합하는 동안만 두 칸 block이고, 확정하면 bar로 돌아온다 |

### 결정 5 — 포커스 없는 패널은 지금처럼 아무것도 안 그린다

WP 결정 6 그대로다. `shell_cursor`가 null이라 반전도 띠도 없다. iTerm2처럼
속 빈 block을 그리는 것은 비목표다(비목표 5).

### 결정 6 — 게이트는 새 줄 `cursor>`로 세 층을 본다

`main.zig`가 매 프레임 `dumpStyles` 뒤에 한 줄을 찍는다.

```
terminal: cursor> vt=bar drawn=bar row=46 col=14 cols=1 ink=32 box=2x16
terminal: cursor> vt=block drawn=block row=46 col=14 cols=1 ink=0 box=0x0
terminal: cursor> vt=bar drawn=none
```

| 칸 | 어디서 오는가 | 무엇을 증명하나 |
|---|---|---|
| `vt=` | `Screen.cursorAsked()` — 라이브러리의 `visual_style` | DECSCUSR이 해석됐다 |
| `drawn=` | `CursorMark.shape`, 없으면 `none` | 우리 우선순위(결정 4)가 그렇게 정했다 |
| `row=` `col=` `cols=` | `CursorMark` | 띠가 칠해질 자리 |
| `ink=` `box=` | 프레임버퍼를 되읽은 값. 커서 칸들 안의 `CURSOR_COLOR` 픽셀 수와 그 경계 사각형 | 렌더러가 그 모양을 실제로 칠했다 |

`style>` / `pixel>`이 "파서가 본 색"과 "프레임버퍼의 색"을 두 겹으로 본 것과
같은 구조이고(TR 결정 7), 한 겹이 더 있다. 고장마다 빨개지는 칸이 다르다.

| 고장 | 어느 칸이 빨개지나 |
|---|---|
| `vt.zig`가 `visual_style`을 안 읽는다(모양을 무시한다) | `vt=block` |
| `cells()`가 모양과 무관하게 반전한다 | 마지막 프레임에 반전 셀이 1(0이어야 한다) |
| `main.zig`가 띠를 안 칠한다 | `ink=0 box=0x0` |
| 띠의 방향이나 크기가 틀렸다 | `box=`가 `2x16` · `8x2`가 아니다 |

매 프레임 찍는 이유는 `find> hl`과 같다(CS-M0) — "바뀔 때만"이면 상태가
하나 늘고, 그 판정이 틀렸을 때 증상이 "로그가 안 나온다"라 조사하기 나쁘다.
커서 칸 하나(최대 256픽셀)만 되읽으므로 비용은 없다.

판정 자리는 `render` 체인이다. 새 체인을 안 연다.

| 후보 | 왜 아닌가 |
|---|---|
| 새 체인 `cursor/check.sh` | 체인 하나가 커널 빌드 셋과 부팅 셋을 더한다(TR 때 6분 13초). CI · TG가 기존 체인에 검사를 더한 것과 같은 판단이다 |
| `copy` · `hangul` 체인 | 그 둘은 커서 반전 셀 수를 판정에 쓴다. 모양을 바꿔 놓고 되돌리는 것을 잊으면 뒤 검사가 전부 흔들린다 |
| `render` 체인의 끝 | 고른 것. 색과 픽셀을 보는 체인이고, 설정 디스크 없이 뜬다 — CU-M1의 시스템 vimrc도 디스크가 필요 없으므로 같은 체인에서 vim까지 볼 수 있다. 마지막 검사가 `\033[0 q`로 block을 되돌리고 그 뒤에는 음성 검사만 남는다 |

게이트는 이스케이프 바이트를 키로 칠 수 없지만 fish의 `printf`가 `\033`을
만들어 준다 — `render` 체인이 이미 `printf '\033[41m …'`으로 쓰는 길이다.

### 결정 7 — 게스트 vi는 `vim.basic`으로 바꾸고, 커서 세 줄은 시스템 vimrc에 둔다(CU-M1)

`vim-tiny`로는 원리적으로 안 된다. `-cursorshape`는 컴파일 시점의 기능이라
`t_SI`를 넣어도 vim이 그 값을 보내는 코드 자체가 바이너리에 없다(실측 2).

| 후보 | 왜 아닌가 |
|---|---|
| `vim-tiny`에 seed vimrc(`/config/vimrc`)를 깐다 | 위의 이유로 아무 효과가 없다. 실측 2의 다섯째 줄이 정확히 이 경우다 |
| neovim | 게스트에 없다. 기본값으로 모드별 커서를 보낸다는 장점이 있지만 의존(LuaJIT · libuv · msgpack · tree-sitter · unibilium 등)이 vim보다 훨씬 무겁다. 무게는 재지 않았다 — 고르지 않을 것이라 잴 이유가 없었다 |
| `vim`(`vim.basic`) + seed vimrc(`/config/vimrc`, `/.vimrc` 링크) | 설정 디스크가 붙은 기계에서만 된다. ISO로 뜬 세션과 `render` 체인에는 디스크가 없다. 그리고 사용자 vimrc가 생기면 vim이 `nocompatible`로 바뀌어 커서 말고 다른 동작까지 달라진다 |
| `VIMINIT` env | 값이 있으면 vim이 사용자 vimrc를 아예 안 읽는다. 사람이 `/.vimrc`를 만들어도 무시된다 |
| `EXINIT` env | 사용자 vimrc가 있으면 안 읽힌다. 사람이 vimrc를 만드는 순간 커서가 조용히 block으로 돌아간다 |
| `vim.basic` + initrd의 시스템 vimrc(`/etc/vim/vimrc`) | 고른 것. 모든 부팅에서 된다. 사용자 vimrc는 그 뒤에 읽히므로 사람이 `set t_SI= t_SR= t_EI=`로 끌 수 있다(실측 5). 사용자 vimrc가 없으면 vim은 지금처럼 `compatible`로 뜬다 — 커서 말고는 안 바뀐다 |

시스템 vimrc의 내용은 세 줄이다. `t_SR`(replace 모드)이 underline을
맡으므로 모양 셋이 전부 vim에서 쓰인다.

```vim
let &t_SI = "\e[6 q"
let &t_SR = "\e[4 q"
let &t_EI = "\e[2 q"
```

같이 해야 하는 것이 하나 있다. `vim.basic`은 사용자 vimrc가 없으면
`$VIMRUNTIME/defaults.vim`을 읽으려 하고, 런타임이 없는 게스트에서는
`E1187: Failed to source defaults.vim`와 `Press ENTER` 프롬프트를 띄운다
(실측 6). 지금의 `vim.tiny`에는 없는 증상이다. 시스템 vimrc에
`skip_defaults_vim`을 두는 것으로는 안 막힌다 — 그 변수를 보는 코드가
`defaults.vim` 안에 있다. 그래서 주석 한 줄짜리 `defaults.vim`을
`/usr/share/vim/vim91/`에 둔다. 원래 파일(5,412바이트)을 넣지 않는 이유는
그 파일이 `syntax on` · `filetype plugin indent on` · `mouse=a`를 켜서 커서
말고 다른 동작이 바뀌고, 런타임이 없는 게스트에서는 그 명령들이 다시 에러를
낼 것이기 때문이다(재지는 않았다).

탈출로는 `vim -u NONE`이다(실측 5). 시스템 vimrc는 `/config`가 아니라
initrd에 있으므로 `tars.noconfig`와 무관하다 — 그 탈출로는 셸 rc가 망가져
셸을 못 쓸 때를 위한 것이고, vimrc가 망가져도 부팅과 셸은 멀쩡하다.

무게: 바이너리가 1,761,704 → 3,921,984바이트(+2.16MB)이고 새 라이브러리가
둘이다(`libsodium.so.23` 375KB · `libgpm.so.2` 27KB). 둘 다 `libc`만
부른다(실측 7).

## 검증

### 호스트 — `vt_test`(CU-M0)

검사 82~92. 화면을 새로 만들고(이름 앞머리 `cu_`), 대조군(기본 block 반전)을
먼저 본다. bar · underline의 사각형 숫자, 반전이 사라지는 것, 깜빡임 번호가
같은 모양인 것, `0`과 빈 인자가 block인 것, preedit · copy mode · 포커스 없음이
모양을 덮는 것, 폭 2 글자 위의 underline, 대체 화면(1049)에서 정한 모양이
나온 뒤 기본 화면으로 안 새는 것(실측 10), 뷰포트를 올리면 셸 커서가 없는 것. 목록과 모양은 plan에 있다.

### 게이트 — `render/check.sh`(CU-M0: 검사 20~24, CU-M1: 검사 25~)

CU-M0은 `printf '\033[H\033[2J\033[N q'`로 화면을 지우며 모양을 바꾸고 `cursor>`의 세 층과 마지막
프레임의 반전 셀 수를 본다. 첫 검사는 대조군이다 — 아무것도 안 했을 때
`cursor>`의 자리가 반전 셀(`style> R,C fg=102030`)의 자리와 같아야 한다.
그래야 뒤의 bar · underline 검사가 보는 `row=` `col=`을 믿을 수 있다. 화면을 지우는 이유는 `dumpStyles`의 96셀 상한이다 — 긴 명령 줄이 남아 있으면 맨 아래 커서 셀의 `style>` 줄이 잘려 "반전 셀 0"이 거짓으로 나온다.

CU-M1은 `vim`을 띄워 `i` · `Esc` · `R` · `Esc` · `:q!`를 치고, `vim -u NONE`이
대조군이다(모양이 안 바뀌어야 한다 — bar가 우리 vimrc에서 왔다는 증명).

## Milestone

### CU-M0 — 터미널이 DECSCUSR 모양 셋을 그린다

`vt.zig`(결정 3 · 4) · `main.zig`(띠 칠하기 · `cursor>`) · `vt_test`
검사 82~92 · `render/check.sh` 검사 20~24. 게스트의 vi는 아직 안 바뀐다 —
이 milestone이 끝나면 `printf '\033[6 q'`를 친 셸 프롬프트에서 bar가 보인다.

### CU-M1 — 게스트 vi가 모드마다 모양을 바꾼다

Dockerfile의 sysroot 목록에서 `vim-tiny`를 `vim` · `libsodium23` ·
`libgpm2`로 바꾸고(이미지 재빌드), `kernel/guest_tools.sh`가
`usr/bin/vim.basic:usr/bin/vim`을 담는다. `make_initrd.sh`가 저장소의
`kernel/vim/vimrc` · `kernel/vim/defaults.vim`을 `/etc/vim/vimrc` ·
`/usr/share/vim/vim91/defaults.vim`으로 넣는다. `render` 체인이 vim을 띄워
본다. plan은 CU-M0이 끝난 뒤에 쓴다.

## 위험

1. 셸이나 seed rc가 언젠가 DECSCUSR을 보내기 시작하면(fish의 vi 키 바인딩,
   zsh-vi-mode 같은 것) 프롬프트의 커서가 bar가 되고, `hangul/check.sh`의
   `inverted_cells` 넷과 `render` 검사 3이 한꺼번에 빨개진다. 지금은 셸 셋이
   한 바이트도 안 보낸다(실측 8). `render` 검사 20(대조군)이 "셸은 block으로
   시작한다"를 직접 판정하므로, 그날 빨개지는 첫 검사가 원인을 말해 준다.
2. 커서 칸에 `CURSOR_COLOR`와 정확히 같은 truecolor 글자가 있으면 `ink=`가
   부푼다. 게이트는 그런 글자를 안 친다. 사람에게는 아무 차이가 없다.
3. `vim.basic`이 `vim.tiny`와 다르게 동작하는 자리가 있을 수 있다. 둘 다
   사용자 vimrc 없이 `compatible`로 뜨고 런타임이 없다는 점은 같다(실측 5 ·
   6). `+eval` · `+syntax`가 생기지만 런타임이 없으니 사람이 `:syntax on`을
   치면 에러가 난다 — 지금은 그 명령 자체가 없다(`E319`). CU-M1이 게스트에서
   `vim`을 띄워 화면에 `E`로 시작하는 에러 줄이 없는 것을 본다.
4. `/usr/share/vim/vim91`은 vim의 버전이 들어간 경로다. Debian이 vim 9.2로
   올리면 stub이 안 읽히고 E1187이 돌아온다. CU-M1의 게이트 검사가 화면에
   `E1187`이 없는 것을 보므로 그날 빨개진다.
5. initrd가 약 2.6MB(압축 전) 커진다. 부팅 시간에 줄 영향은 CU-M1이 잰다.

## 착수 전에 실측한 것

2026-10-04, devcontainer(`tars-devcontainer`, arm64)에서 쟀다. vim은 게스트와
같은 패키지 판(`2:9.1.1230-2`)을 arm64로 설치했고, 게스트처럼
`/etc/vim` · `/usr/share/vim`을 치운 뒤 `vim`이라는 이름으로 불렀다. pty는
`script -qfec`이고, 키는 FIFO를 `exec 4<>`로 열어 단계마다 1초 남짓 띄워
넣었다. 단계마다 출력 파일 크기를 적어 두고, 그 구간 안에서
`\e\[(\d*) q`를 셌다.

1. 게스트 vi의 실체. `kernel/guest_tools.sh`의 `usr/bin/vim.tiny:usr/bin/vim`
   한 줄이고, `vi` · `editor`는 `make_initrd.sh`가 거는 링크다. sysroot의
   바이너리는 `VIM - Vi IMproved 9.1`, Dockerfile이 받는 패키지는
   `vim-tiny:amd64`다. 같은 판의 기능 목록은 `-cursorshape -eval -syntax
   +autocmd`다. 게스트 initrd에는 바이너리만 있고 `/etc/vim`도 런타임도
   없다.

2. `vim-tiny`는 어떤 설정에서도 DECSCUSR을 안 낸다. 단계는 기동 · `i` ·
   `abc` · `Esc` · `:q!`이다.

   | 설정 | 구간마다 DECSCUSR |
   |---|---|
   | vimrc 없음 | 0 · 0 · 0 · 0 · 0 |
   | `-u NONE` | 0 · 0 · 0 · 0 · 0 |
   | vimrc `set nocompatible` | 0 · 0 · 0 · 0 · 0 |
   | vimrc `let &t_SI = "\e[6 q"` · `t_EI` | 0 · 0 · 0 · 0 · 0(`-eval`이라 `let`이 없다) |
   | vimrc `set t_SI=<ESC>[6\ q` · `t_EI`(ESC 바이트를 글자 그대로) | 0 · 0 · 0 · 0 · 0 |

   키가 vim에 닿았다는 증거는 같은 출력에 있다 — `-- INSERT --`와 `abc`가
   찍혔고 `:q!` 뒤에 `ESC[?1049l`이 나왔다. 기본값은 `t_SI=` · `t_EI=` ·
   `t_SR=`(빈 값), `t_SH=^[[%p1%d q`, `t_RS=^[P$q q^[\`, `compatible`이다.

3. 게스트의 terminfo `xterm-256color`(`make_initrd.sh`가 넣는다)에는
   `Ss=\E[%p1%d q` · `Se=\E[2 q`가 있다(`infocmp -1 -x`). vim은 그 값을
   `t_SH`로만 가져가고 `t_SI` · `t_EI`를 안 채운다(2의 기본값).

4. `vim.basic`(패키지 `vim` `2:9.1.1230-2`, `+cursorshape +eval +syntax`)은
   vimrc가 시키면 낸다.

   | 설정 | 구간마다 DECSCUSR |
   |---|---|
   | vimrc 없음 · `-u NONE` · `set nocompatible`만 | 0 · 0 · 0 · 0 · 0 |
   | vimrc `let &t_SI` · `let &t_EI` | 0 · 6 · 0 · 2 · 0 |
   | 거기에 `let &t_SR = "\e[4 q"`, 키 `i ab Esc R x Esc` | 6 · 2 · 4 · 2 |

   바이트 순서는 `ESC[?1049h` … `-- INSERT --` → `ESC[6 q` … `ESC[2 q` …
   `:q!` → `ESC[?1049l`이다. 기동할 때 `t_EI`를 미리 보내지 않고, 끝날 때도
   DECSCUSR 없이 대체 화면을 나간다.

5. 시스템 vimrc는 `/etc/vim/vimrc`다(`vim.basic --version`의 `system vimrc
   file`). 세 줄(`t_SI` · `t_SR` · `t_EI`)을 거기 두고 잰 값:

   | 경우 | DECSCUSR | 상태 |
   |---|---|---|
   | 사용자 vimrc 없음 | 6 · 2 · 4 · 2 | `compatible`, `t_SI=^[[6 q` |
   | `-u NONE` | 없음 | 탈출로 |
   | 사용자 vimrc `set nocompatible` | 6 · 2 · 4 · 2 | 시스템 vimrc가 먼저 읽힌다 |
   | 사용자 vimrc `set t_SI= t_SR= t_EI=` | 없음 | 사람이 끌 수 있다 |

6. 사용자 vimrc도 런타임도 없으면 `vim.basic`이
   `E1187: Failed to source defaults.vim`과 `Press ENTER`를 띄운다. 시스템
   vimrc에 `let g:skip_defaults_vim = 1`을 둬도 그대로다. 주석 한 줄짜리
   `/usr/share/vim/vim91/defaults.vim`을 두면 에러가 없고 DECSCUSR은
   6 · 2 · 4 · 2 그대로다. `--clean`은 stub이 없을 때 같은 에러를 낸다.
   원래 `defaults.vim`은 5,412바이트다.

7. 무게(amd64 `.deb`를 `dpkg -x`로 풀어 쟀다).

   | 파일 | 바이트 | `DT_NEEDED` |
   |---|---|---|
   | `vim.tiny`(지금) | 1,761,704 | libm · libtinfo · libselinux · libacl · libc |
   | `vim.basic` | 3,921,984 | 위 다섯 + libsodium · libgpm |
   | `libsodium.so.23.3.0` | 375,496 | libc · ld-linux |
   | `libgpm.so.2` | 26,552 | libc |

   다섯은 sysroot에 이미 있고 둘이 없다(`find /usr/local/amd64-sysroot`).

8. 셸 셋은 DECSCUSR을 안 낸다. fish 4.0.2 · zsh 5.9 · bash 5.2.37을 각각
   `exec <셸> -i`로 pty 아래에 띄우고 `echo hi`와 `exit`을 쳤다. 셋 다 0이다.
   그래서 지금의 열여덟 체인에서 셸 커서는 언제나 block이고, 셸 커서의 반전에
   기대는 검사(`render` 검사 3 · `hangul/check.sh`의 `inverted_cells` 넷)는 이
   서브프로젝트가 안 흔든다. `copy/check.sh`의 `inverted_cells`는 copy 커서를
   세므로 처음부터 무관하다.

9. 라이브러리 쪽(소스를 읽었다).
   - `stream.zig`의 DECSCUSR 갈래가 인자 0개와 `0`을 `.default`로, 1~6을
     blinking/steady × block/underline/bar로 읽고 그 밖은 경고만 찍고
     버린다.
   - `Terminal.setCursorStyle`이 `screens.active.cursor.cursor_style`과
     `cursor_blinking` 모드를 함께 정한다. `.default`는
     `cursor.default_style`(우리가 안 바꾸므로 `.block`)이다.
   - `RenderState.update`가 매번 `visual_style` · `blinking` · `visible`을
     `state.cursor`에 옮긴다. `viewport`를 정하는 자리와 같은 함수라서
     `cells()`가 `state.update` 뒤에 `self.state.cursor.visual_style`을 바로
     읽을 수 있다.
   - `cursor.Style`은 넷(`bar` · `block` · `underline` · `block_hollow`)이고
     `block_hollow`는 DECSCUSR로 만들 수 없다(그 파일의 주석).
   - 기본 팔레트는 이름 16색(`Name.default`) · 6단 큐브(0 · 0x5F · 0x87 ·
     0xAF · 0xD7 · 0xFF) · 회색 8~238이다. `0xF0F0F0`은 어디에도 없다.

10. 커서 모양은 화면(기본 · 대체)마다 따로다. `cursor_style`이
    `Screen.cursor`의 필드이고, 1049를 켜면 대체 화면이 기본 화면의 커서를
    통째로 복사하고(`cursorCopy`), 끄면 기본 화면으로 돌아가
    `restoreCursor`를 하는데 `SavedCursor`에 `cursor_style`이 없다. 그래서
    vim이 대체 화면에서 bar를 남기고 끝나도 셸 프롬프트는 block이다. 소스로
    읽은 사실이라 CU-M0의 `vt_test` 검사 91이 실행으로 다시 본다.

11. 렌더는 타이머가 없다. `main.zig`의 `poll(&fds, nfds, -1)`이 유일하게
    잠드는 자리이고 다시 그리기는 `needs_redraw`가 켜졌을 때뿐이다.

12. `dumpStyles`는 기본 색과 다른 셀만 찍고, `pixel>`은 셀 가운데
    (`+CELL_W / 2`, `+ROW_HEIGHT / 2`)를 읽는다. bar(왼쪽 두 열)와
    underline(아래 두 줄)는 가운데에 안 닿는다.

13. CU-M1 plan이 착수 전에 컨테이너에서 vim.basic을 쳐 보고 드러난 것 넷(그 plan의 확정 7).
    - 사용자 vimrc가 없으면 vim은 `compatible`이고 `showmode`가 꺼져 있다. 화면에
      `-- INSERT --`가 안 나온다. 실측 4의 바이트 순서에 그 글자가 있는 것은 사용자 vimrc가
      있어서 vim이 `nocompatible`로 뜬 경우다. 그래서
      insert에 들어간 증거는 `cursor>`의 `vt=bar`이고, 대조군(`-u NONE`)에서는 친 글자의
      수(`col=2`)다.
    - 새 파일 메시지는 `"/tmp/cu.txt" [New File]`이다.
    - stub이 없을 때의 `E1187`과 `Press ENTER`는 대체 화면에 들어가기 전, 기본 화면에 찍힌다.
      다음 키가 그 프롬프트를 닫고 명령으로도 쓰이므로 에러 판정은 기동 직후에 한다.
    - vim은 Esc로 나가든 Ctrl-O로 나가든 `t_EI`(block)를 보내고 대체 화면을 나간다. 그래서
      vim으로는 실측 10(대체 화면의 모양이 기본 화면으로 안 샌다)을 판정할 수 없고, CU-M1의
      검사 32가 printf로 판정한다.

14. 게스트에서 잰 것 하나가 위의 셈과 달랐다(CU-M1 실측 5). vim은 `~` 줄의 나머지를 NonText
    색의 공백으로 채워서, vim 화면의 `style>` 셀은 45개가 아니라 6,976개다. 덤프 상한 96에
    언제나 닿는다. 게이트는 "덤프가 커서 칸을 지났다"로 판정한다(`render/check.sh`의
    `style_covers`).

## 비목표

1. 깜빡임(결정 2).
2. `block_hollow`를 따로 그리기(결정 1).
3. OSC 12가 정한 커서 색. `state.colors.cursor`가 있지만 `init`이
   `.unset`으로 준다.
4. DECTCEM(`CSI ?25l`)로 커서 숨기기. 라이브러리가 `state.cursor.visible`로
   주지만 지금 렌더러는 안 보고, 이 서브프로젝트도 안 본다. vim은 다시
   그리는 동안 커서를 숨겼다가 곧 다시 보인다(실측 4의 바이트 순서) — 무시해도
   남는 것은 그 순간의 커서 한 칸이다. 따로 열 일이다.
5. 포커스 없는 패널에 속 빈 커서(결정 5).
6. copy 커서의 모양을 바꾸기(결정 4).
7. 사용자 vimrc를 부팅 사이에 남기기(`/.vimrc` → `/config/vimrc` 링크와
   seed). 지금 `/.vimrc`는 tmpfs의 홈이라 재부팅에 사라진다. gitconfig와 같은
   모양으로 할 수 있지만 커서와는 별개의 일이다.
8. neovim(결정 7).
9. 모양 · 두께 · 색을 `tars.conf`로 빼기.
10. `pty.zig`의 `ws_xpixel` · `ws_ypixel`(`docs/guides/lessons.md`의 이월
    숙제). 커서와 무관하다.

## 관련

- `docs/specs/2026-08-23-tars-terminal-rendering-design.md` — 색과 커서를
  `vt.zig`가 해소한다는 결정 1 · 2
- `docs/specs/2026-08-31-tars-hangul-input-design.md` — preedit 두 칸 반전
  (결정 4)
- `docs/specs/2026-10-03-tars-workspace-panes-design.md` — 포커스 없는
  패널의 커서(결정 6)
- `docs/specs/2026-10-03-tars-terminal-graphics-design.md` — `vt.zig`가 픽셀
  사각형을 내는 선례
- `docs/specs/2026-10-03-tars-copy-indicator-design.md` — 전용 색으로
  게이트가 픽셀을 세는 선례(결정 3)
- `docs/decisions/project_userland_tools.md` — vim이 게스트에 들어온 자리
  (UT-M3 결정 4)
