# TARS 키보드 의미 — Cmd는 시스템, Ctrl은 프로그램

TARS의 키보드가 macOS의 modifier 의미를 따르는 이유와, 키 하나가 evdev에서
PTY까지 가는 길, 그리고 지금 실제로 동작하는 조합의 표를 한 곳에 정리한다.
설계의 근거와 milestone별 경과는 각 design doc에 있다 — 이 문서는 그
결과만 모은 지도다.

- 파이프라인과 Cmd · Opt 편집 표: `docs/specs/2026-08-15-tars-input-policy-design.md`
- copy mode: `docs/specs/2026-08-24-tars-copy-mode-design.md`
- workspace와 pane: `docs/specs/2026-10-03-tars-workspace-panes-design.md`
- 한글 입력과 전환 키: `docs/specs/2026-08-31-tars-hangul-input-design.md`
- Esc가 한글을 끄는 전환: `docs/specs/2026-10-05-tars-escape-latin-design.md`
- 붙여넣기: `docs/specs/2026-10-04-tars-paste-ergonomics-design.md`
- 코드: `terminal/src/input.zig`(`handleKey` · `chord` · `specialKey`),
  검사: `terminal/src/input_test.zig`, 게이트: `input/check.sh` · `copy/check.sh` · `pane/check.sh`

## 왜 TARS인가

Wayland compositor와 터미널 에뮬레이터를 설정으로 맞추면 `Super+C/V`를
copy/paste로, `Ctrl+C`를 터미널 입력으로 쓸 수 있다. TARS가 푸는 문제는
그것이 불가능해서가 아니다. 그 동작이 compositor · 터미널 · 셸 · 입력기마다
흩어진 설정에 기대고 있고, 하나라도 빠지면 어느 한 프로그램에서만 다르게
동작한다는 점이다.

TARS에서 키보드 의미는 부팅 시점부터 시스템 하나의 정책이다. 키는 evdev에서
우리 terminal로 바로 오고, 사이에 X도 Wayland도 입력기 데몬도 없다. 정하는
자리가 `terminal/src/input.zig` 한 곳뿐이다.

- Cmd는 control plane이다. Cmd chord는 workspace · pane · clipboard · 줄 편집
  같은 시스템 동작으로 끝나고, 동작인 것은 PTY에 가지 않는다.
- Ctrl은 data plane이다. terminal이 가로채지 않는다. 제어 문자로 인코딩해
  PTY로 보낸다.
- Opt는 편집 modifier다. 셸이 이미 아는 바이트로 번역한다 — `Opt+←`는
  `ESC b`다. readline · zle · fish가 설정 파일 없이 그대로 받는다.
- 한/영은 terminal 안의 상태다. 조합 중인 글자는 PTY로 가지 않고 커서
  자리에 우리가 그린다. 확정된 글자만 PTY에 쓴다.

## 키 하나가 지나가는 네 단계

```
evdev ──> 0. 키보드 보정 ──> 1. modifier 갱신 ──> 2. chord ──> 3. 기본 번역 ──> PTY
             (apple|pc)         (8키 비트)        (시스템이        (keymap ·
                                                  가져간다)         specialKey)
```

- 0은 `keyboard=pc`일 때만 한다. evdev 코드 56↔125, 100↔126을 맞바꾼다. 그
  뒤의 단계는 어느 키보드인지 모른다.
- 1은 물리 키 하나당 비트 하나다. 왼쪽 · 오른쪽 Shift · Ctrl · Alt · Meta
  여덟 개를 따로 든다. 하나로 뭉치면 왼쪽 Shift를 누른 채 오른쪽 Shift를
  눌렀다 뗐을 때 그 뗌 하나가 논리 Shift를 통째로 끈다.
- 2가 3보다 먼저다. 순서를 바꾸면 `Cmd+←`가 chord에 닿기 전에 `ESC [ D`로
  번역돼 PTY로 새어 나간다. 가로챌 것을 먼저 가로채고, 남은 것만 평소대로
  보낸다. DECCKM이 켜진 문맥에서도 `Opt+←`가 `ESC O D`가 아니라 `ESC b`인지
  보는 검사가 이 순서를 지킨다.
- 3은 특수키(방향키 · Home · End · Delete · PageUp/Down)를 이스케이프
  시퀀스로, 나머지를 keymap으로 번역한다. 방향키의 형태(`ESC [ D` 또는
  `ESC O D`)는 추측하지 않고 VT에게 DECCKM 상태를 물어서 정한다.

copy mode에 들어가 있으면 이 네 단계 앞에서 copy 분기가 키를 전부 가져간다.
모드 안에서는 Cmd 조합조차 chord에 닿지 않는다.

## Cmd — 시스템 동작

전부 PTY에 가지 않는다. 숫자 키는 물리 자리(`KEY_1`~`KEY_9`)라 자판이
드보락이어도 같다. 키는 iTerm2를 그대로 따랐다 — 손이 아는 키를 바꾸지
않는다.

| 입력 | 동작 |
|---|---|
| `Cmd+1`~`Cmd+9` | 그 번호의 workspace로. 없으면 아무 일도 안 한다 |
| `Cmd+T` | 새 workspace를 끝에 만들고 그리로 간다 (최대 아홉) |
| `Cmd+D` | 포커스 pane을 세로로 갈라 오른쪽에 새 셸 |
| `Cmd+Shift+D` | 포커스 pane을 가로로 갈라 아래에 새 셸 (한 workspace에 여덟까지) |
| `Cmd+W` | 포커스 pane의 셸에 SIGHUP. 셸이 끝나면 pane이 닫힌다 |
| `Cmd+]` · `Cmd+[` | 다음 · 이전 pane으로 포커스. 끝에서 감긴다 |
| `Cmd+Opt+←↑↓→` | 그 방향의 이웃 pane으로 포커스 |
| `Cmd+Shift+C` | copy mode 진입 |
| `Cmd+V` | clipboard 붙여넣기. copy mode 안팎 모두 |

`Cmd+V`는 자식이 모드 2004(bracketed paste)를 켰으면 `ESC[200~` · 본문 ·
`ESC[201~`로 감싸고, 꺼져 있으면 본문만 쓴다. 본문은 한 바이트도 바꾸지
않는다. clipboard는 terminal 전체에 하나다(`clipboard=shared`, 기본값).
pane마다 따로 두는 옛 동작은 `clipboard=pane`이다.

## Cmd · Opt — 줄 편집

바이트로 번역된다. 번역의 기준은 "셸이 이미 아는 언어"다 — 표의 바이트는
readline · zle · fish의 기본 바인딩이라, `--norc` · `--no-config`로 뜬
셸에서도 설정 없이 동작한다. 그래야 게이트가 화면 덤프로 증명할 수 있다.

| 입력 | PTY로 가는 바이트 | readline · zle · fish에서의 뜻 |
|---|---|---|
| `Cmd+←` | `0x01` | beginning-of-line |
| `Cmd+→` | `0x05` | end-of-line |
| `Cmd+Backspace` | `0x15` | 커서 앞 삭제 (아래 "알고 있는 어긋남") |
| `Opt+←` | `ESC b` | backward-word |
| `Opt+→` | `ESC f` | forward-word |
| `Opt+Backspace` | `ESC 0x7F` | backward-kill-word |
| `Opt+Delete` | `ESC d` | kill-word |

`ESC b`의 ESC는 `Ctrl+[`이 만드는 것과 같은 바이트다. 받는 쪽이 "Meta
조합"과 "혼자 온 ESC"를 가르는 방법은 다음 바이트를 잠깐 기다리는
것(readline의 keyseq-timeout)이고, 우리가 지킬 것은 두 바이트를 한 번의
write로 보내는 것뿐이다.

## Ctrl — 그대로 전달

Ctrl 조합은 terminal이 뜻을 두지 않는다. 규칙은 한 줄이다 — Shift를 먼저
적용해 문자를 정한 뒤 `& 0x1F`. 제어 문자 `0x00`~`0x1F`가
`@ABC…Z[\]^_`(`0x40`~`0x5F`)에서 상위 두 비트를 뗀 것이므로 마스크 하나가
표 전부를 설명한다.

| 입력 | 바이트 | 뜻 |
|---|---|---|
| `Ctrl+C` | `0x03` | SIGINT (N_TTY가 보낸다) |
| `Ctrl+D` | `0x04` | EOF |
| `Ctrl+Z` | `0x1A` | SIGTSTP |
| `Ctrl+\` | `0x1C` | SIGQUIT |
| `Ctrl+[` | `0x1B` | ESC |
| `Ctrl+V` | `0x16` | readline quoted-insert |
| `Ctrl+Space` | `0x00` | NUL |
| `Ctrl+_` | `0x1F` | readline undo |
| `Ctrl+?` | `0x7F` | DEL (예외) |

마스크는 문자가 `a`~`z`, `@ [ \ ] ^ _`, Space, `?`일 때만 적용한다.
`Ctrl+1`에 적용하면 `0x11`(XON)이 나오는데 아무도 그 뜻으로 쓰지 않으므로,
나머지는 Ctrl을 무시하고 원래 문자를 보낸다. xterm과 같다.

`Ctrl+C` 자체는 시그널이 아니다. terminal이 PTY master에 `0x03`을 쓰면
커널의 N_TTY line discipline이 `ISIG`와 `VINTR=^C`를 보고 foreground process
group에 `SIGINT`를 보낸다. `forkpty`가 자식 쪽에서 `setsid` · `TIOCSCTTY`를
해 주므로 셸이 제어 터미널을 갖고 있고, 우리 코드에 시그널은 한 줄도 없다.
raw mode의 vim은 그 바이트를 직접 받는다.

## Shift — 스크롤

| 입력 | 동작 |
|---|---|
| `Shift+PageUp` · `Shift+PageDown` | 스크롤백을 한 화면씩 |
| `Shift+Home` · `Shift+End` | 맨 위 · 맨 아래 |

xterm · 리눅스 콘솔 · tmux가 전부 쓰는 형태다. Mac 노트북의 `Fn+↑`도
evdev에는 `KEY_PAGEUP`으로 오므로 키보드 종류와 무관하다.

## copy mode

`Cmd+Shift+C`로 들어간다. 안에서는 키를 전부 terminal이 가져가고 PTY에는
아무것도 가지 않는다. 상태 줄에 `COPY`가 뜬다.

| 키 | 동작 |
|---|---|
| `h` `j` `k` `l` · 방향키 | 커서 이동 |
| `w` · `b` | 다음 · 이전 단어 |
| `v` · `V` | 문자 · 줄 선택 시작 |
| `/` | 검색. 매치는 amber로, 지금 매치는 더 밝게. 검색창에 `[3/4]` 위치 |
| `n` · `N` | 다음 · 이전 매치 |
| `y` · `Cmd+C` | 선택을 clipboard로 옮기고 모드를 나간다 |
| `Cmd+V` | 붙여넣기. 모드를 닫지 않는다 |
| `Esc` | 모드를 나간다 (검색창이 열려 있으면 검색창만 닫는다) |

검색창에는 한글도 친다. 검색창의 한/영 상태는 셸의 한/영 상태와 같은 것이다
— 모드에 들어갔다 나와도 그대로다.

## 한/영 전환과 Esc

입력기 데몬이 없다. terminal 안의 오토마타가 자모를 모으고, 조합 중인
글자는 커서 자리에 우리가 그린다. 자판은 `tars.conf`가 고른다 —
`hangul_layout`(두벌식 · 공세벌 3-P3 · 신세벌 P2 · 신세벌 PCS, 기본
`shin_pcs`)과 `latin_layout`(쿼티 · 드보락, 기본 `qwerty`). 한글 자판 맵의
글자는 글자가 아니라 쿼티 자리의 이름이라, 영문 배열을 드보락으로 바꿔도
한글 배열은 안 바뀐다.

| 입력 | 동작 |
|---|---|
| 한/영 키 | 전환 |
| `Shift+Space` | 전환 |
| CapsLock 짧게 | 전환 (길게 누르면 CapsLock) |
| 왼쪽 Ctrl 짧게 | 전환 (다른 키와 함께 누르면 Ctrl) |
| 한글 조합 중 `Esc` | 조합을 확정하고 영문으로 돌아온다. Esc는 프로그램에 그대로 간다 |

앞의 넷은 `hangul_toggle` 목록이 고르고 기본값은 넷 다다. 다섯째 Esc는
`esc_latin=on|off`(기본 `on`)로 따로 있는 키다 — 조합 중이었으면 "음절
3바이트 + ESC"가 한 번의 write로 나가서, vim은 글자를 받은 뒤에 Esc를 받고
다음 키가 명령이 된다. 한 방향 전환이다. 영문에서 Esc를 눌러도 한글로
가지 않는다.

Ctrl · Opt · Cmd 조합은 한글이 아니다. 조합 중에 그 조합을 누르면 조합 중인
음절을 먼저 확정해 PTY에 보내고, 그 다음에 조합을 처리한다.

상태 줄 맨 아래에 한/영(`EN` · `한`) · 한글 자판 · 라틴 자판 · CapsLock이
함께 바뀐다.

## 키보드 둘 — `keyboard=apple|pc`

Apple과 PC 키보드는 스페이스 옆 두 키의 순서가 뒤집혀 있을 뿐이다.

```
Apple:  [Ctrl] [Option] [Cmd]    [Space]
         29      56      125
PC:     [Ctrl] [Win]   [Alt]     [Space]
         29     125      56
```

`keyboard=pc`가 하는 일은 modifier를 기록하기 전에 evdev 코드 56↔125,
100↔126을 맞바꾸는 것뿐이다. 파이프라인 맨 앞에서 한 번 교환하면 chord ·
keymap · specialKey는 어느 키보드인지 몰라도 된다. 기본값은 `apple`이고,
모르는 값은 조용히 `apple`로 떨어진다. 설정 파일을 읽는 것은 PID 1 하나이고
terminal은 argv로 값을 받는다.

## 표에 없는 조합

- 표에 없는 Cmd · Opt 조합은 modifier를 무시하고 원래 키를 보낸다 —
  `Opt+b`는 `b`, `Cmd+C`는 copy mode 밖에서 `c`다. `Ctrl+1`이 `1`인 것과
  같은 규칙이다. 단 `Cmd+Shift` · `Cmd+Opt` 조합은 표에 없으면 Shift · Opt
  없는 표로 떨어지지 않고 아무것도 보내지 않는다. 떨어지면 `Cmd+Shift+W`가
  `Cmd+W`(pane 닫기)가 된다.
- Cmd와 Opt가 둘 다 눌리면 Cmd가 이긴다. 임의의 선택이지만 결정적이어야
  해서 `chord`가 Meta를 먼저 보는 한 곳에서 정하고 검사가 못 박는다.
- 자동 반복(`value == 2`)은 누름과 같다. 시스템이 가져간 chord는 반복도
  가져간다.

## 알고 있는 어긋남

- `Cmd+Backspace`의 `0x15`는 bash에서 커서 앞까지만 지우고
  (`unix-line-discard`), zsh에서는 줄 전체를 지운다(`kill-whole-line`).
  macOS는 bash 쪽이다. 셸이 아는 바이트로 번역하는 방식의 대가이고, 셸을
  바꿔 끼울 수 있는 시스템이라 감추지 않고 적어 둔다.
- `Cmd+Shift+←·→·Backspace`는 아무것도 보내지 않는다(Shift가 표에 없다).
  WP 전에는 Shift를 무시하고 `0x01` · `0x05` · `0x15`였다.
- copy mode 밖의 `Cmd+C`가 `c`로 나가는 것은 "Cmd는 PTY에 가지 않는다"와
  어긋난다. macOS 사용자가 선택 없이 `Cmd+C`를 눌렀을 때 기대하는 것은
  아무 일도 없는 것이다. `chord`의 Meta 분기 `else`를 "삼킴"으로 바꾸면
  닫히고, 그 경우 `Ctrl+1 → 1`과의 대칭은 깨지지만 Ctrl은 data plane이라
  규칙이 달라도 된다. 아직 정하지 않았다.

## 일부러 비워 둔 것

- 설정 파일로 키를 재배치하는 범용 키바인딩 엔진. 표는 코드에 있고,
  설정에서 읽는 것은 `keyboard` · `hangul_layout` · `latin_layout` ·
  `hangul_toggle` · `esc_latin` · `clipboard`뿐이다 — 재배치가 아니라 하드웨어와
  자판의 선언이다.
- CapsLock → Ctrl 재배치. macOS 사용자가 흔히 바꿔 쓰는 키지만 "임의
  재배치"의 첫 문이라 열지 않는다. CapsLock 짧게 누름은 한/영 전환이다.
- CSI u / modifyOtherKeys. modifier를 명시적으로 인코딩해 넘기는 현대적
  방식이지만 받는 쪽(bash · zsh)이 기본으로 지원하지 않는다. TARS가 자기 TUI
  앱을 갖게 되면 다시 본다.
- F1~F12, 키패드, Insert, 비-US 라틴 배열. 누를 이유가 생기면 더한다.
