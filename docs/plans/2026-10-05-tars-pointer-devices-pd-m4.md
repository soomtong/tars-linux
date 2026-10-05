# PD-M4 — 마우스 보고: 자식이 원하면 누름 · 끎 · 휠을 보내고, Shift를 누르면 우리 선택이다

Date: 2026-10-05
Design: `docs/specs/2026-10-05-tars-pointer-devices-design.md`(결정 12)
Status: 끝났다(2026-10-05). 실측은 맨 아래 "PD-M4가 실측한 것" 절에 있다. 이것으로 PD가 M4까지 닫혔다.

## 누가 무엇을 하나

design 결정 11 · 12. Task 0~7은 구현 서브에이전트(Opus)가 main 작업 트리에서 직접 편집한다. Task 8(루트 게이트 2회 ·
실측 절 · commit · 닫기)은 lead(Fable)가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` ·
각 Task의 명령 출력을 그대로 보고한다. mutation(Task 7)도 구현자가 돌린다. 이 plan의 "확정한 것" 절과 "실측한 것" 절은
구현자가 고치지 않는다.

이 plan의 코드는 저장소 밖 사본(`/tmp/run/pdm4/repo/`)에 먼저 넣어 컴파일 · 호스트 검사 · 체인 · regression · mutation까지
돌렸고, 아래의 `old_string` · `new_string`은 그 사본에서 기계로 뽑은 것이다(`/tmp/run/pdm4/render.py`). 기준은 HEAD `1050b6f`의
파일(`/tmp/run/pdm4/base/`)이고 편집 뒤의 파일은 `/tmp/run/pdm4/new/`다. 구현자는 코드를 새로 짓지 않는다. 편집은 Edit 도구에
글자 그대로 넣고, 각 Task 끝에서 `new/`와 `diff`해 같은지 본다. 다르면 편집이 빗나간 것이니 plan의 글자에 맞춰 고친다.
plan의 글자와 `new/`가 서로 다르다고 보이면 고치지 말고 그 자리를 보고한다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `terminal/src/pointer.zig` | 편집 넷 — 머리 주석 · `Buttons.has` · `with`와 `Button` · `Gesture.handOff` · 마우스 보고 절(`Owner` · `Pane` · `ownerOf` · `Grab` · `WheelRoute` · `wheelRoute`) | +157 −1 |
| `terminal/src/pointer_test.zig` | 검사 23~28 | +98 |
| `terminal/src/vt.zig` | 편집 둘 — `mouse_last` 칸 · `MouseAction` · `MouseButton` · `MouseMods` · `mouseWanted` · `wheelKeys` · `wheelKey` · `mouseEncode` | +95 |
| `terminal/src/vt_test.zig` | 검사 102~106과 `expectMouse` | +73 |
| `terminal/src/input.zig` | `State.modifiers`와 `Modifiers` | +17 |
| `terminal/src/input_test.zig` | 검사 68 | +18 |
| `terminal/src/main.zig` | 편집 열 — 전이 칸의 버튼 · 드레인 · `dumpReport` · `PointerWire`의 칸 셋과 함수 다섯(`paneAt` · `edge` · `moved` · `report` · `reportTo`) · 휠 · 변수 둘 · 루프 | +183 −16 |
| `kernel/vim/vimrc` | `mouse=` → `mouse=a`, `ttymouse=sgr`, 주석 | +11 −2 |
| `docs/specs/2026-10-04-tars-guest-ergonomics-design.md` | 원칙 3과 표 두 줄에 PD-M4가 바꿨다고 덧붙인다 | +5 −2 |
| `pointer/check.sh` | 편집 일곱 — 머리 주석 셋 · 표식 · 설정 디스크의 프로브와 서른 줄 파일 · 검사 26~32와 도구 · PASS 줄 | +321 −3 |
| `check.sh` | 체인 설명 문단과 `CHAINS`의 `"PD-M3:…"` → `"PD-M4:…"` | +3 −1 |

`layout.zig` · `touchpad.zig` · `kernel/.config` · `kernel/make_initrd.sh` · `kernel/guest_tools.sh`는 안 고친다. 프로브는 initrd가
아니라 부팅 B의 설정 디스크에 싣는다(확정 6) — 그래서 `tools/check.sh`의 initrd 목록도 그대로다.

`docs/guides/lessons.md` · PD design의 `Status:`와 결정마다의 덧붙임 · `HANDOFF.md` · `CLAUDE.md` · `MEMORY.md` ·
`docs/decisions/`는 구현자가 안 고친다. lead가 Task 8에서 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. Zig 빌드 · 테스트 · 체인은 언제나 컨테이너에서 한다 — 호스트
`PATH`의 zig는 0.17이고 컨테이너는 0.16.0이다. 구현자의 측정용 파일은 `/tmp/run/pdm4/impl/` 아래에 둔다.
`/tmp/run/pdm4/` 바로 아래는 이 plan을 쓰며 만든 것이고 대조에 쓴다. 지우지 않는다.

Docker VM의 메모리가 4GB다. 컨테이너 둘을 겹쳐 돌리면 `zig build`가 `Killed`로 죽거나 VM이 재시작된다(PD-M1 plan
확정 11). 컨테이너는 언제나 하나씩 돌린다. 캐시를 지운 빌드가 `Killed`로 죽으면 다른 컨테이너가 없는지 보고 그 판만
다시 돈다.

## 이 milestone이 끝나면

- 자식이 마우스 모드(9 · 1000 · 1002 · 1003)를 켜면 누름 · 끎 · 뗌 · 휠이 우리 제스처 대신 그 자식의 PTY에 간다. 바이트는
  ghostty의 인코더가 자식이 고른 형식(X10 · UTF-8 · SGR · urxvt · SGR-Pixels)으로 짠다. 오른쪽 · 가운데 버튼도 간다.
- 누름의 주인은 버튼이 하나도 안 눌렸을 때의 첫 누름이 정하고 마지막 뗌까지 간다. Shift를 누른 채 누르면 자식이
  원해도 우리 것이다 — PD-M2의 드래그 선택이 그대로 돈다. 키보드 copy mode인 패널의 누름도 우리 것이다.
- 포커스가 아닌 패널을 누르면 포커스가 그리로 옮겨 간 뒤 그 패널의 자식이 누름을 받는다(tmux와 같다). 좌표는 그 패널
  안의 칸이다.
- 휠은 포인터 아래 패널의 자식이 원하면 버튼 4 · 5의 누름이고, 대체 화면이고 모드 1007이 켜져 있으면 화살표 키 세 번
  (`less` · `man`이 줄을 움직인다)이다. 그 밖은 PD-M1 그대로 우리 스크롤백이다.
- 게스트 vim이 시스템 vimrc의 `mouse=a` · `ttymouse=sgr`로 클릭 · 끎 · 휠을 받는다. vim 안에서 우리 클립보드로 복사하려면
  Shift를 누른 채 끈다.
- `pointer/check.sh`의 부팅 B에 검사 26~32가 더해진다. 부팅 수와 체인 수는 그대로다. 호스트 검사가 셋 는다(`pointer_test`
  23~28 · `vt_test` 102~106 · `input_test` 68).

로그 줄(정본 — `main.zig`와 `pointer/check.sh`가 이 글자를 쓴다). 새 줄은 하나다.

```
terminal: pointer> report leaf=0 n=1 text=^[[<0;11;2M
terminal: pointer> report leaf=0 n=3 text=^[[A
```

자식에게 쓴 바이트를 `cat -v`의 모양으로 찍는다 — 제어 바이트는 `^`와 64를 더한 글자, 0x7F는 `^?`, 0x80 이상은 `M-`와
아래 7비트다. `n`은 같은 바이트를 몇 번 썼는가다. 마우스 보고는 1이고, 휠을 바꾼 화살표 키는 눈금 × `WHEEL_ROWS`(3)다.
인코더가 보낼 것이 없다고 한 사건(1000에서의 끎 같은 것)은 줄이 없다. 우리 것인 누름은 PD-M2의 `press` · `release` 줄
그대로다.

## 착수 전에 확정한 것

2026-10-05에 이 plan을 쓰며 vendored ghostty 소스와 코드를 읽어 정했고, VM이 빈 뒤 저장소 사본(`/tmp/run/pdm4/repo/`)에서
쟀다. 저장소의 작업 트리는 design 파일과 이 plan 말고는 한 글자도 안 바뀌었다.

1. 라이브러리에 필요한 것이 다 있다. `terminal/ghostty-src/src/lib_vt.zig`의 `input` 구조체가 `MouseAction` ·
   `MouseButton` · `MouseEncodeOptions` · `MouseEncodeEvent` · `encodeMouse`를 공개한다(128~133행). 옵션의 `size` 필드 타입
   (`renderer/size.zig`의 `Size`)은 공개되지 않았지만 결과 자리의 익명 리터럴(`.{ .screen = …, .cell = …, .padding = .{} }`)로
   채워진다 — 사본에서 `zig build` · `zig build test`가 exit 0이었다. `ghostty_vt.Coordinate`(`last_cell`의 타입)는 공개다.
   `focus.encode`(모드 1004)도 공개지만 쓰지 않는다(design 비목표 14).

2. 인코더(`input/mouse_encode.zig`)가 하는 것. 이것을 우리가 다시 짓지 않는다.

   | 일 | 어떻게 |
   |---|---|
   | 모드별 보고 | `none`은 없음 · `x10`(모드 9)은 왼쪽 · 가운데 · 오른쪽의 누름만 · `normal`(1000)은 움직임 빼고 다 · `button`(1002)은 버튼이 실린 사건만 · `any`(1003)는 다 |
   | 버튼 칸 | 왼쪽 0 · 가운데 1 · 오른쪽 2 · 버튼 없음 3 · 버튼 4는 64 · 버튼 5는 65 · Shift +4 · Alt +8 · Ctrl +16(X10 모드는 수정키 없음) · 움직임 +32. SGR 밖의 형식은 뗌을 늘 3으로 짠다 |
   | 패널 밖 좌표 | 뗌은 늘 보낸다. 누름 · 버튼 없는 움직임은 버린다. 누른 채 움직임은 1002 · 1003이고 `any_button_pressed`일 때만 보낸다 |
   | 칸 | 픽셀 ÷ 셀 크기, 0 아래와 격자 끝 위는 가장자리로 붙인다. 형식이 1부터 센다 |
   | 같은 칸의 움직임 | `last_cell`이 있으면 칸이 안 바뀐 움직임을 버린다(SGR-Pixels는 빼고) |
   | 형식 | X10(`ESC [ M` + 세 바이트, 223칸까지) · UTF-8 · SGR(`ESC [ < b ; x ; y M/m`) · urxvt · SGR-Pixels |

3. 모드의 상태. vt stream(`terminal/stream_terminal.zig` 734~764행)이 `Terminal.flags.mouse_event` · `mouse_format`을 바꾼다.
   모드 9 · 1000 · 1002 · 1003 중 어느 것이든 `l`이면 `mouse_event`가 `none`이 되고, 형식 넷 중 어느 것이든 `l`이면 `x10`으로
   돌아간다. 모드 1007(`mouse_alternate_scroll`)의 기본값은 켜짐이다(`modes.zig` 314행, xterm은 꺼짐). 대체 화면인가는
   `term.screens.active_key == .alternate`다. 패널마다 `Terminal`이 따로라 모드도 패널마다 따로다(`pasteParts`와 같다).

4. ghostty 앱(`Surface.zig`)의 규칙을 참고했다. 기본 설정(`mouse-shift-capture = false`)에서 Shift가 눌렸으면 보고하지
   않는다(3943~3950행). 휠은 대체 화면이고 `mouse_event`가 `none`이고 1007이면 화살표 키(DECCKM이면 `ESC O`), 아니면 보고
   중이면 버튼 4 · 5(3569~3625행). design 결정 12가 이 둘을 따른다. 다른 점 하나 — ghostty는 Shift를 누른 휠도 보고하고 우리는
   우리 스크롤로 돌린다(누름과 같은 규칙을 휠에도 쓴다).

5. 층별 모양. design 결정 12의 표다. 결정이 필요했던 자리만 적는다.

   | 자리 | 정한 것 | 왜 |
   |---|---|---|
   | `Grab`의 주인 | 첫 누름이 정하고 `held`가 빌 때까지 간다 | 누름과 뗌의 짝. 누르는 동안 모드나 Shift가 바뀌어도 손동작 하나가 두 주인에게 나뉘지 않는다 |
   | `Grab.settle` | 회차 끝에 `held &= Pointer.buttons` | `Pointer.forget`(누른 채 빠진 장치)의 뗌은 전이 칸에 안 담긴다. 이것이 없으면 그 뒤의 모든 누름이 옛 주인에게 간다(`pointer_test` 검사 25) |
   | `Gesture.handOff` | `cancel` · (다른 패널이면) `focus`를 내고 `phase = .ignored` | 첫 누름이 자식의 것이어도 조합 확정 · 옛 포커스의 copy mode 닫기 · 포커스 옮기기는 해야 한다. `PointerWire.run`의 두 갈래를 그대로 쓴다. `ignored`는 뗄 때까지 아무것도 안 하는 기존 상태다 |
   | 전이 칸 | `PointerEdge`에 `button`을 더하고 셋을 다 담는다 | 오른쪽 · 가운데도 보고한다. 우리 것이면 지금처럼 왼쪽만 `Gesture`로 간다 |
   | 좌표 | 그 패널의 `paneOrigin`에서 잰 픽셀(`i32`, 음수 가능) | 인코더가 칸을 세고 밖을 처리한다. SGR-Pixels도 그대로 간다. 상수는 렌더러 · `gridCell`과 같은 넷이다 |
   | `vt.Screen.mouse_last` | 패널마다 `?ghostty_vt.Coordinate` | 인코더의 `last_cell`. 칸이 안 바뀐 움직임을 거른다 |
   | 수정키 | `input.State.modifiers()`가 Shift · Ctrl · Alt를 좌우 합쳐 돌려주고 `main.zig`가 회차마다 `PointerWire.mods`로 넘긴다 | `pointer.zig`는 `input.zig`를 import하지 않는다. 키보드 분기가 포인터 분기 앞이라 같은 회차의 Shift가 보인다 |
   | 휠의 순서 | 끄는 중(`Gesture.wheel`) → copy mode 무시 → Shift면 우리 스크롤 → 원하면 보고 → 1007이면 화살표 키 → 우리 스크롤 | 확정 4. 화살표 키는 `WHEEL_ROWS`번이다 — 우리 스크롤의 세 줄과 같은 양이다 |
   | 워크스페이스 | 첫 누름의 워크스페이스(`grab_ws`)가 지금과 다르면 그 손동작의 보고를 버린다 | 그 패널은 지금의 `ws`에 없다. `gesture_ws`와 같은 모양이다 |

6. 게스트 쪽. 게스트에 `stty` · `od` · `reset`이 없다(`kernel/guest_tools.sh`). 그래서 프로브는 bash의 `read -rs -N 길이 -t 초`로
   터미널을 raw로 바꾸고 에코를 끈다 — `tq-probe`(`read -n 20 -t 2`)와 같은 길이다. 시간이 다 되면 그때까지 읽은 것이 변수에
   남는다(검사 29가 0을 본다). 프로브는 설정 디스크(`/config/pd/mouse`)에 싣는다 — 부팅 B가 이미 디스크를 물고 있고, 게이트만
   쓰는 것을 제품 initrd에 안 넣는다(design 결정 10의 `tp-replay`와 같은 이유). 부팅 A에 디스크를 물리면 init이 설정을 읽어
   M0~M2의 화면이 바뀐다. 셋째 부팅은 체인에 30초 남짓을 더한다.

   게스트 vim은 amd64 sysroot의 `vim.basic`이라 arm64 호스트의 컨테이너에서는 못 돌린다. QEMU에서 쟀다 — `mouse=a` ·
   `ttymouse=sgr`의 vim이 클릭을 `ESC[<0;10;5M`(SGR)로 받아 커서를 5:6으로 옮겼다(사본의 검사 31). `config` 체인(`vim -T dumb
   -e`의 에러 검사)도 지났다 — `ttymouse=sgr`이 dumb 터미널에서 에러를 안 낸다. TERM은 `xterm-256color`다.

7. 부팅 B의 포인터. 부팅 B의 HMP 대상은 PS/2 마우스 하나다(터치패드는 HMP 대상이 아니다). `mouse_move`가 1:1이다 —
   사본의 검사 26~32가 `move_to`(마지막 at 줄에서 상대 이동, 정확한 자리의 at 줄을 기다린다)로 다 지났다. 휠의 부호도 USB
   마우스와 같다 — `mouse_move 0 0 1`이 버튼 4(64)다. 터치패드가 닫힌 뒤라 at 줄의 자리가 이어진다(검사 25 뒤 x=819 y=464).

8. Shift를 누른 채 두기. HMP `sendkey shift 3000`이 Shift를 3초 누르고 뗀다. QEMU는 그 사이에 온 `sendkey`를 큐에 두고
   뗀 뒤에 보내지만 마우스 사건은 큐를 안 거친다. 그래서 그 3초 안에 누름 · 끎 · 뗌이 가고, 뒤의 `type_keys`는 Shift가
   떨어진 뒤에 간다. 사본의 검사 29가 지났다(`clip> len=8 text=pd-mouse`, 자식 0바이트). Shift를 보낸 뒤 0.3초를 쉰다 —
   Shift에는 로그 줄이 없어서 terminal이 읽었는지를 볼 창구가 없다.

9. 판정에서 배운 것 넷. 전부 사본의 첫 판들이 빨개져서 고쳤다.
   - `scroll>` 줄은 PTY 출력으로도 찍힌다(바닥에서 total이 는다). 검사 28은 줄 수가 아니라 값을 본다 — 그 동안 찍힌
     `scroll>`이 전부 바닥(offset = total − len)이다.
   - `wait_for_screen`은 로그의 모든 `screen>` 줄을 본다. 옛 화면에 이미 있는 글자(프롬프트)는 바로 맞는다. 그래서
     `wait_for_new_screen N 패턴`을 두어 N번째 뒤의 `screen>`만 본다(새 패널의 첫 프롬프트, vim이 끝난 뒤).
   - vim이 끝나기 전에 친 글자는 vim이 먹는다(`:q` 뒤에 친 `echo`의 `e`가 사라졌다). 주 화면이 돌아와 vim을 친 명령줄이
     다시 보일 때까지 기다린다 — 그 줄은 vim이 도는 동안(대체 화면)에는 안 보인다.
   - 프로브의 줄에는 ERE 특수 문자(`^ [ ]`)가 가득해서 `wait_for_screen_text`(grep -F)로 본다.

10. 시간. 같은 사본에서 따뜻한 캐시로 잰 `pointer` 체인이 HEAD 판 51초, 이 plan의 판 73초다 — 검사 26~32가 22초를 더한다.
    루트 게이트는 체인을 두 번 돌리므로 PD-M3의 49분 29초에 45초쯤을 더한 50분 15초 안팎으로 본다.

11. regression. vimrc가 바뀌므로 vim을 쓰는 체인 넷을 사본에서 돌렸다. 넷 다 exit 0이다.

    | 체인 | 시간 | vim을 쓰는 자리 |
    |---|---|---|
    | `render` | 1분 49초 | 커서 모양 · `[New]` · 줄 번호 칸 |
    | `copy` | 2분 52초 | 붙여넣기의 `autoindent` 계단 |
    | `config` | 2분 44초 | `vim -T dumb -e +scriptnames`와 vimrc 에러 검사 |
    | `tools` | 1분 1초 | initrd 목록(vimrc 파일) · vim 실행 |

    `main.zig`의 변경은 포인터가 움직이고 누를 때만 도는 길이라, 포인터를 안 움직이는 나머지 체인은 영향이 없다. 루트
    게이트가 전부를 본다.

12. mutation 넷. 전부 `main.zig`의 한 줄이고 호스트 검사를 안 건드린다 — 순수 층의 규칙은 `pointer_test`가 부팅 전에 보므로
    체인이 잡아야 하는 것은 배선이다.

    | mutation | 바꾸는 줄(`main.zig`) | 잡은 자리 | `FAIL` 줄 | 시간 |
    |---|---|---|---|---|
    | 1 `paneAt`이 모드를 안 읽는다 | `.wants = p.screen.mouseWanted(),` → `.wants = false,` | 검사 26 | `a press in a pane with mode 1000 printed no 'pointer> report' line (last press: 'terminal: pointer> press leaf=0 row=1 col=10')` — 누름이 우리 제스처로 갔다 | 2분 16초 |
    | 2 누름이 Shift를 안 본다 | `grab.press(…, self.mods.shift)` → `grab.press(…, false)` | 검사 29 | `a Shift-press in mode 1000 printed no 'pointer> press' line (last report: 'terminal: pointer> report leaf=0 n=1 text=^[[<0;1;46M')` — 자식이 받았다 | 2분 25초 |
    | 3 보고 좌표를 격자의 원점에서 잰다 | `paneOrigin(rs[leaf])` → `paneOrigin(self.whole)` | 검사 32 | `a press on the unfocused pane with mode 1000 printed no 'pointer> report' line` — 오른쪽 패널의 2열이 80열로 재여 77열 패널 밖이 되고 인코더가 누름을 버렸다 | 2분 36초 |
    | 4 `paneAt`이 1007을 안 읽는다 | `.alt_keys = p.screen.wheelKeys(),` → `.alt_keys = false,` | 검사 30 | `a wheel notch on the alternate screen printed no 'pointer> report' line` — 우리 스크롤이 됐다 | 2분 30초 |

    시간은 캐시를 지운 터미널 빌드를 포함한다. mutation 3이 design의 첫 예상(`81;2`)과 달랐다 — 좌표가 틀린 보고가 아니라
    보고가 없어졌다. 판정은 같은 검사가 한다.

13. 앵커. 편집 서른셋의 `old_string`이 HEAD 파일에 정확히 한 번씩 있고, `new_string`이 사본에 정확히 한 번씩 있다
    (`python3 /tmp/run/pdm4/anchors.py pre "$PWD"` → `pre: 33 edits, 0 bad`).

14. 흔들림 하나. mutation 4의 첫 판이 M4와 무관한 자리에서 빨갰다 — 부팅 B의 검사 19 둘째(PD-M3)가 친 `seq 200`의 끝에
    프롬프트가 15초 안에 안 그려졌다(`FAIL: boot B: seq 200 did not finish`, 마지막 화면이 `… | 200 |`에서 끝나고 커널의
    `random: crng init done`이 섞였다). 같은 사본으로 부팅 B를 열 번 넘게 띄우는 동안 한 번이다. 다시 돌린 판은 예상한 자리
    (검사 30)에서 빨갰다. 로그는 `/tmp/run/pdm4/mut/m4_flake.log`다. 루트 게이트에서 같은 줄이 보이면 이 흔들림이다.

15. 호스트 검사의 수(HEAD → 이 plan). `pointer_test` OK 107 → 140(검사 23~28이 서른셋), `vt_test` OK 78 → 82,
    `input_test` OK 15 → 16. `zig build test`의 `all checks passed` 넷과 `PASS` 다섯은 그대로다.

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트나 컨테이너가 없는지 본다.

   ```bash
   docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
   pgrep -fl 'tars-devcontainer'
   ```

   둘 다 아무것도 안 나와야 한다. 나오면 멈추고 보고한다.

2. 작업 트리를 본다.

   ```bash
   git status --short
   git log --oneline -3
   ```

   기대: `git status`는 이 plan 파일과 design(`docs/specs/2026-10-05-tars-pointer-devices-design.md`)이 commit 전이면 그 둘뿐이고,
   lead가 고치는 중일 수 있는 `HANDOFF.md`가 더 있을 수 있다. 맨 위 commit이 `1050b6f Reopen pointer devices for PD-M4: …`이거나
   그 위에 이 plan과 design을 넣은 lead의 commit 하나다.

3. 편집의 앵커가 지금 파일에 맞는지 본다(확정 13).

   ```bash
   python3 /tmp/run/pdm4/anchors.py pre "$PWD"
   ```

   기대: `pre: 33 edits, 0 bad`. 하나라도 `bad`면 그 줄을 보고하고 멈춘다.

4. 호스트 검사의 지금 값을 본다.

   ```bash
   mkdir -p /tmp/run/pdm4/impl
   docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c '
     zig build test > /tmp/t.out 2>&1; echo "exit=$?"
     grep -a -c "^pointer_test: .* OK$" /tmp/t.out
     grep -a -c "^vt_test: .* OK$" /tmp/t.out
     grep -a -c "^input_test: .* OK$" /tmp/t.out
     grep -a -E "all checks passed|^PASS$|FAIL" /tmp/t.out'
   ```

   기대: `exit=0`, `pointer_test` OK 107 · `vt_test` OK 78 · `input_test` OK 15, `all checks passed` 넷 · `PASS` 다섯,
   `FAIL` 0줄.

## Task 1: `terminal/src/pointer.zig` · `pointer_test.zig` — 주인과 휠의 갈 곳

확정 5의 순수 층이다. `vt.zig` · `input.zig`를 import하지 않는다는 머리 주석의 규칙은 그대로다 — 패널의 상태는 `Pane`으로,
Shift는 `bool`로 받는다.

### 1-1. `pointer.zig` — 편집 넷

P1 — `old_string`(기준 파일 9줄부터):

```zig
//! `Gesture`(누름 · 끎 · 뗌 · 휠을 의도로, PD-M2).
```

`new_string`:

```zig
//! `Gesture`(누름 · 끎 · 뗌 · 휠을 의도로, PD-M2). 자식이 마우스를 원하면
//! `Grab`이 그 누름을 자식의 것으로 정하고 `Gesture`를 건너뛴다(PD-M4).
```

P2 — `old_string`(기준 파일 135줄부터):

```zig
        return @bitCast(self);
    }
};
```

`new_string`:

```zig
        return @bitCast(self);
    }

    /// 버튼 `b`가 서 있는가(PD-M4).
    pub fn has(self: Buttons, b: Button) bool {
        return switch (b) {
            .left => self.left,
            .right => self.right,
            .middle => self.middle,
        };
    }

    /// 버튼 `b` 하나를 세우거나 내린 값(PD-M4).
    pub fn with(self: Buttons, b: Button, down: bool) Buttons {
        var out = self;
        switch (b) {
            .left => out.left = down,
            .right => out.right = down,
            .middle => out.middle = down,
        }
        return out;
    }
};

/// 버튼 하나의 이름(PD-M4). 보고는 셋을 다 보낸다 — 우리 제스처는 왼쪽만 쓴다.
pub const Button = enum { left, right, middle };
```

P3 — `old_string`(기준 파일 608줄부터):

```zig
    /// 휠을 굴렸다. 버튼이 패널 칸 위에서 눌린 채면 누른 패널을 움직이고
```

`new_string`:

```zig
    /// 이 누름은 자식의 것이다(PD-M4, design 결정 12). 누름처럼 `cancel`과
    /// (다른 패널이면) `focus`를 내고, 뗄 때까지 아무것도 안 한다 — 끎과
    /// 뗌은 자식에게 보고로 간다.
    ///
    /// 포커스를 먼저 옮기는 것은 tmux의 기본 바인딩(`select-pane` 뒤에
    /// `send-keys -M`)과 같다. 확정한 한글이 보고보다 먼저 PTY에 간다.
    pub fn handOff(self: *Gesture, leaf: u4, focus: u4) Intents {
        var out: Intents = .{};
        self.phase = .ignored;
        out.push(.cancel);
        if (leaf != focus) out.push(.{ .focus = leaf });
        return out;
    }

    /// 휠을 굴렸다. 버튼이 패널 칸 위에서 눌린 채면 누른 패널을 움직이고
```

P4 — `old_string`(기준 파일 645줄부터):

```zig
    return a.leaf == b.leaf and a.col == b.col and a.row == b.row;
}
```

`new_string`:

```zig
    return a.leaf == b.leaf and a.col == b.col and a.row == b.row;
}

// ── 마우스 보고(PD-M4) ────────────────────────────────────────────────
//
// 자식이 마우스를 원하면(모드 9 · 1000 · 1002 · 1003) 누름 · 끎 · 뗌 · 휠을
// 우리 제스처 대신 그 자식에게 보낸다(PD design 결정 12). 여기는 "누구의
// 것인가"만 정한다. 바이트를 짜는 것은 `vt.Screen.mouseEncode`(ghostty의
// 인코더)이고, 쓰는 것은 `main.zig`다.

/// 누름의 주인.
pub const Owner = enum {
    /// 우리 것이다 — 왼쪽 버튼은 `Gesture`로 가고 휠은 스크롤백을 움직인다.
    ours,
    /// 자식의 것이다 — 그 패널의 PTY에 보고로 간다.
    child,
};

/// 포인터 아래 패널의 지금 상태. `main.zig`가 그 패널의 `vt.Screen`에서
/// 읽어 채운다 — 이 파일은 `vt.zig`를 import하지 않는다(머리 주석).
pub const Pane = struct {
    leaf: u4,
    /// 자식이 마우스 보고를 켰다(모드 9 · 1000 · 1002 · 1003 중 하나).
    wants: bool,
    /// 키보드 copy mode다.
    copy: bool,
    /// 휠을 화살표 키로 바꿀 자리다 — 대체 화면이고 모드 1007이 켜져 있다.
    alt_keys: bool,
};

/// 이 패널 위의 누름 · 움직임이 누구의 것인가(design 결정 12).
///
/// 자식이 원하고, 그 패널이 키보드 copy mode가 아니고, Shift가 안 눌렸으면
/// 자식의 것이다. 여백 · 구분선 · 상태 줄(null)은 언제나 우리 것이다 — 우리
/// 것이어도 거기서는 아무 일도 없다(design 결정 5).
///
/// Shift가 우리에게 돌려준다. xterm 이래의 관례이고 ghostty · kitty · tmux가
/// 같다. copy mode는 사람이 `Cmd+Shift+C`로 "우리 선택"을 고른 상태라 거기서의
/// 누름도 우리 것이다.
pub fn ownerOf(under: ?Pane, shift: bool) Owner {
    const p = under orelse return .ours;
    return if (p.wants and !p.copy and !shift) .child else .ours;
}

/// 버튼이 눌린 동안의 주인(design 결정 12). 버튼이 하나도 안 눌렸을 때의
/// 첫 누름이 주인과 패널을 정하고, 마지막 버튼을 뗄 때까지 간다.
///
/// 붙어 있는 이유는 짝을 맞추기 위해서다. 자식이 누름을 받았으면 뗌도 받아야
/// 하고(vim은 뗌이 올 때까지 Visual을 늘린다), 우리 제스처가 누름을 받았으면
/// 뗌도 받아야 한다(복사가 뗌에 있다). 누른 뒤 자식이 모드를 켜고 끄거나
/// Shift를 떼도 주인은 안 바뀐다.
pub const Grab = struct {
    held: Buttons = .{},
    owner: Owner = .ours,
    /// 첫 누름의 잎. `owner`가 `child`일 때 보고가 가는 패널이다.
    leaf: u4 = 0,

    pub fn active(self: *const Grab) bool {
        return self.held.bits() != 0;
    }

    /// 버튼 `b`가 눌렸다. `under`는 누른 자리의 패널이다. 돌려주는 것이 이
    /// 누름의 주인이다.
    pub fn press(self: *Grab, b: Button, under: ?Pane, shift: bool) Owner {
        if (!self.active()) {
            self.owner = ownerOf(under, shift);
            self.leaf = if (under) |p| p.leaf else 0;
        }
        self.held = self.held.with(b, true);
        return self.owner;
    }

    /// 버튼 `b`를 뗐다. 돌려주는 것이 이 뗌의 주인이다 — 마지막 버튼이어도
    /// 그 버튼의 주인을 돌려준 뒤에 풀린다.
    pub fn release(self: *Grab, b: Button) Owner {
        self.held = self.held.with(b, false);
        return self.owner;
    }

    /// 포인터가 아는 버튼 상태에 맞춘다. 장치가 누른 채 빠졌거나(`Pointer.forget`)
    /// 한 회차의 전이가 넘쳐 뗌을 잃으면 `held`가 영영 눌린 채로 남고, 그
    /// 뒤의 모든 누름이 옛 주인에게 간다. 회차마다 끝에서 부른다.
    pub fn settle(self: *Grab, now: Buttons) void {
        self.held = @bitCast(self.held.bits() & now.bits());
    }

    /// 끄는 보고에 실을 버튼. 여럿이 눌렸으면 왼쪽 · 가운데 · 오른쪽 순이다.
    /// 아무것도 안 눌렸으면 null — 버튼 없는 움직임이다.
    pub fn dragButton(self: *const Grab) ?Button {
        if (self.held.left) return .left;
        if (self.held.middle) return .middle;
        if (self.held.right) return .right;
        return null;
    }
};

/// 휠 한 회차가 어디로 가나(design 결정 12의 휠 표).
pub const WheelRoute = enum {
    /// 아무 일도 없다 — 키보드 copy mode인 패널(design 결정 7).
    ignore,
    /// 버튼 4 · 5의 누름으로 자식에게 보고한다.
    report,
    /// 화살표 키(위 · 아래)로 자식에게 보낸다. 한 눈금이 세 번이다.
    keys,
    /// 우리 스크롤백을 움직인다(PD-M1).
    scroll,
};

/// 포인터 아래 패널 `p`에서 굴린 휠의 갈 곳. 끄는 중의 휠(`Gesture.wheel`)은
/// 이것보다 먼저 본다.
///
/// Shift는 누름과 같이 우리에게 돌려준다. 대체 화면에서 우리 스크롤은 움직일
/// 스크롤백이 없으므로 아무 일도 없다.
pub fn wheelRoute(p: Pane, shift: bool) WheelRoute {
    if (p.copy) return .ignore;
    if (shift) return .scroll;
    if (p.wants) return .report;
    if (p.alt_keys) return .keys;
    return .scroll;
}
```

### 1-2. `pointer_test.zig` — 검사 23~28

PT1 — `old_string`(기준 파일 584줄부터):

```zig
    std.debug.print("pointer_test: all checks passed\n", .{});
```

`new_string`:

```zig
    // ── 검사 23: 누름의 주인(PD-M4) ──────────────────────────────────────
    //
    // 자식이 원하고, copy mode가 아니고, Shift가 없을 때만 자식의 것이다
    // (design 결정 12). 여백(null)은 언제나 우리 것이다.
    {
        const wants: pointer.Pane = .{ .leaf = 1, .wants = true, .copy = false, .alt_keys = false };
        try expectTrue("a pane that wants the mouse owns a plain press", pointer.ownerOf(wants, false) == .child);
        try expectTrue("Shift takes the press back from a pane that wants the mouse", pointer.ownerOf(wants, true) == .ours);
        var in_copy = wants;
        in_copy.copy = true;
        try expectTrue("a press in keyboard copy mode is ours even if the child wants the mouse", pointer.ownerOf(in_copy, false) == .ours);
        var quiet = wants;
        quiet.wants = false;
        try expectTrue("a pane that does not want the mouse leaves the press to us", pointer.ownerOf(quiet, false) == .ours);
        try expectTrue("a press on the margin is ours", pointer.ownerOf(null, false) == .ours);
    }

    // ── 검사 24: 주인은 첫 누름이 정하고 마지막 뗌까지 간다 ─────────────
    //
    // 누른 채 자식이 모드를 끄거나 Shift를 눌러도 그 뗌은 누름의 주인에게 간다
    // (design 결정 12의 "모드가 바뀌면"). 다른 버튼을 더 눌러도 같은 주인이다.
    {
        const wants: pointer.Pane = .{ .leaf = 1, .wants = true, .copy = false, .alt_keys = false };
        const quiet: pointer.Pane = .{ .leaf = 0, .wants = false, .copy = false, .alt_keys = false };
        var g: pointer.Grab = .{};
        try expectTrue("the first press on a wanting pane goes to the child", g.press(.left, wants, false) == .child);
        try expectTrue("the grab remembers the pane of the first press", g.leaf == 1 and g.active());
        try expectTrue("a second button pressed over a quiet pane with Shift stays with the child", g.press(.right, quiet, true) == .child);
        try expectTrue("the drag button is the left one while both are held", g.dragButton().? == .left);
        try expectTrue("releasing one of two buttons keeps the grab", g.release(.left) == .child and g.active());
        try expectTrue("with only the right one held the drag button is the right one", g.dragButton().? == .right);
        try expectTrue("the last release still belongs to the child", g.release(.right) == .child);
        try expectTrue("after the last release nothing is held", !g.active() and g.dragButton() == null);
        try expectTrue("the next press decides again (a quiet pane is ours)", g.press(.left, quiet, false) == .ours);
        try expectTrue("a press on a wanting pane while ours is held stays ours", g.press(.middle, wants, false) == .ours);
        try expectTrue("the grab still names the first pane", g.leaf == 0);
    }

    // ── 검사 25: 놓친 뗌은 포인터의 버튼에 맞춰 풀린다 ─────────────────
    //
    // 장치가 누른 채 빠지면 `Pointer.forget`이 버튼을 놓지만 전이 칸에는 안
    // 담긴다. `settle`이 없으면 다음 누름이 옛 주인에게 간다.
    {
        const wants: pointer.Pane = .{ .leaf = 2, .wants = true, .copy = false, .alt_keys = false };
        const quiet: pointer.Pane = .{ .leaf = 0, .wants = false, .copy = false, .alt_keys = false };
        var g: pointer.Grab = .{};
        _ = g.press(.left, wants, false);
        g.settle(.{ .left = true });
        try expectTrue("settle keeps a button the pointer still holds", g.active());
        g.settle(.{});
        try expectTrue("settle drops a button the pointer no longer holds", !g.active());
        try expectTrue("so the next press decides its owner again", g.press(.left, quiet, false) == .ours);
    }

    // ── 검사 26: 자식에게 넘기는 누름은 포커스만 옮긴다 ─────────────────
    //
    // `cancel`(조합 확정 · 옛 포커스의 copy mode 닫기)과 다른 패널이면 `focus`를
    // 낸다. 그 뒤로 제스처는 아무것도 안 한다 — 움직임도 뗌도 휠도 자식의 것이다.
    {
        var g: pointer.Gesture = .{};
        try expectIntents("handing a press on another pane to its child moves the focus", g.handOff(1, 0), &.{
            .cancel,
            .{ .focus = 1 },
        });
        try expectTrue("the gesture holds nothing after a hand-off", g.held() == null);
        try expectIntents("a drag after a hand-off makes no selection", g.motion(.{ .leaf = 1, .col = 4, .row = 2 }, .normal), &.{});
        try expectTrue("a wheel after a hand-off is not the gesture's", g.wheel(1, .normal) == null);
        try expectIntents("the release after a hand-off copies nothing", g.release(.normal), &.{});
        try expectIntents("handing a press on the focused pane only cancels", g.handOff(0, 0), &.{.cancel});
    }

    // ── 검사 27: 휠의 갈 곳 ───────────────────────────────────────────────
    //
    // copy mode는 무시(PD-M1) · Shift는 우리 스크롤 · 자식이 원하면 보고 ·
    // 대체 화면의 1007이면 화살표 키 · 나머지는 우리 스크롤이다. 보고가 화살표
    // 키보다 먼저다 — 마우스를 켠 대체 화면 프로그램(vim `mouse=a`)은 휠을
    // 버튼 4 · 5로 받는다.
    {
        const base: pointer.Pane = .{ .leaf = 0, .wants = false, .copy = false, .alt_keys = false };
        var p = base;
        try expectTrue("a plain pane scrolls its scrollback", pointer.wheelRoute(p, false) == .scroll);
        p.alt_keys = true;
        try expectTrue("the alternate screen with mode 1007 gets arrow keys", pointer.wheelRoute(p, false) == .keys);
        p.wants = true;
        try expectTrue("a pane that wants the mouse gets the wheel as a report, before arrow keys", pointer.wheelRoute(p, false) == .report);
        try expectTrue("Shift turns the wheel back into our scroll", pointer.wheelRoute(p, true) == .scroll);
        p.copy = true;
        try expectTrue("keyboard copy mode ignores the wheel", pointer.wheelRoute(p, false) == .ignore);
        try expectTrue("keyboard copy mode ignores the wheel with Shift too", pointer.wheelRoute(p, true) == .ignore);
    }

    // ── 검사 28: 버튼 하나를 세우고 읽는다 ───────────────────────────────
    {
        const b = (pointer.Buttons{}).with(.middle, true).with(.left, true).with(.left, false);
        try expectTrue("with() sets and clears one button", b.has(.middle) and !b.has(.left) and !b.has(.right));
        try expectNum("the middle button alone is bit 4 (HMP mouse_button)", b.bits(), 4);
    }

    std.debug.print("pointer_test: all checks passed\n", .{});
```

### 1-3. 확인

```bash
diff terminal/src/pointer.zig /tmp/run/pdm4/new/terminal/src/pointer.zig && echo SAME-pointer
diff terminal/src/pointer_test.zig /tmp/run/pdm4/new/terminal/src/pointer_test.zig && echo SAME-pointer_test
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c '
  zig build test > /tmp/t.out 2>&1; echo "exit=$?"
  grep -a -c "^pointer_test: .* OK$" /tmp/t.out
  grep -a -E "^FAIL|error:" /tmp/t.out | head -5'
```

기대: `SAME-pointer` · `SAME-pointer_test`, `exit=0`, `pointer_test` OK 140, `FAIL` · `error:` 0줄. `main.zig`는 아직 새 것을
안 쓰므로 빌드가 그대로 지난다.

## Task 2: `vt.zig` · `vt_test.zig` · `input.zig` · `input_test.zig` — 인코더 감싸개와 수정키

`vt.zig`가 라이브러리 타입을 밖에 안 내는 규율(TR design 결정 1)을 따른다. `main.zig`는 `vt.Screen.MouseAction` ·
`MouseButton` · `MouseMods`만 안다.

### 2-1. `vt.zig` — 편집 둘

V1 — `old_string`(기준 파일 428줄부터):

```zig
    shell_cursor: ?CursorMark = null,
```

`new_string`:

```zig
    shell_cursor: ?CursorMark = null,

    /// 마지막으로 보고한 칸(PD-M4). ghostty의 인코더가 움직임 보고를 칸이
    /// 바뀔 때만 내려고 들고 다니는 값이다(`MouseEncodeOptions.last_cell`).
    /// 패널마다 따로다 — 보고가 가는 자식이 패널마다 따로이기 때문이다.
    mouse_last: ?ghostty_vt.Coordinate = null,
```

V2 — `old_string`(기준 파일 2044줄부터):

```zig
    /// 뷰포트가 스크롤백의 어디에 있는지.
```

`new_string`:

```zig
    /// 마우스 사건의 종류 · 버튼 · 수정키(PD-M4). 라이브러리의 타입을 그대로
    /// 넘기지 않고 우리 것으로 둔다 — `main.zig`가 `ghostty-vt`의 타입을 배우지
    /// 않게 하는 규율이다(TR design 결정 1, `Scrollbar`와 같다).
    pub const MouseAction = enum { press, release, motion };
    pub const MouseButton = enum { left, middle, right, wheel_up, wheel_down };
    /// Shift는 없다. Shift를 누른 사건은 보고하지 않고 우리가 갖는다(PD design
    /// 결정 12).
    pub const MouseMods = struct { alt: bool = false, ctrl: bool = false };

    /// 자식이 마우스 보고를 켰는가 — 모드 9 · 1000 · 1002 · 1003 중 하나(PD-M4).
    ///
    /// 형식(1005 · 1006 · 1015 · 1016)은 여기서 안 본다. 형식만 켜고 모드를
    /// 안 켠 자식은 보고를 원하지 않는다. 모드는 `Terminal` 하나에 하나라
    /// 대체 화면에서 켠 것과 주 화면에서 켠 것이 같은 값이다.
    pub fn mouseWanted(self: *const Screen) bool {
        return self.term.flags.mouse_event != .none;
    }

    /// 휠을 화살표 키로 바꿀 자리인가 — 대체 화면이고 모드 1007(alternate
    /// scroll)이 켜져 있다(PD-M4). 자식이 마우스 보고를 켰는지는 안 본다 —
    /// 그것은 `pointer.wheelRoute`가 먼저 가른다.
    ///
    /// 1007의 기본값은 켜짐이다(ghostty `modes.zig`, xterm의 기본값은 꺼짐).
    /// 그래서 `less` · `man`처럼 마우스를 안 켜는 대체 화면 프로그램에서 휠이
    /// 줄을 움직인다. 끄려는 프로그램은 `ESC[?1007l`을 보낸다.
    pub fn wheelKeys(self: *const Screen) bool {
        return self.term.screens.active_key == .alternate and
            self.term.modes.get(.mouse_alternate_scroll);
    }

    /// 휠 한 줄의 화살표 키. 자식이 DECCKM(모드 1)을 켰으면 `ESC O A`, 아니면
    /// `ESC [ A`다 — 키보드의 화살표(`input.zig`)와 같은 규칙이다.
    pub fn wheelKey(self: *const Screen, up: bool) []const u8 {
        if (self.term.modes.get(.cursor_keys)) return if (up) "\x1bOA" else "\x1bOB";
        return if (up) "\x1b[A" else "\x1b[B";
    }

    /// 마우스 사건 하나를 자식이 고른 형식으로 `out`에 짠다(PD-M4). 보고할
    /// 사건이 아니면 빈 조각이다.
    ///
    /// 판단과 바이트는 ghostty의 인코더(`input.encodeMouse`)가 한다. 모드가
    /// 무엇을 보고하나(1000은 누름 · 뗌, 1002는 누른 채 움직임도, 1003은 모든
    /// 움직임, 9는 누름만), 형식(X10 · UTF-8 · SGR · urxvt · SGR-Pixels), 칸이
    /// 안 바뀐 움직임 거르기, 1부터 세는 좌표가 그 안에 있다.
    ///
    /// `x` · `y`는 이 패널의 왼쪽 위 끝에서 잰 픽셀이다. 음수나 패널보다 큰 수도
    /// 된다 — 패널 밖으로 끈 것이고, 인코더가 가장자리 칸으로 붙이거나(뗌 ·
    /// 누른 채 움직임) 버린다(누름 · 버튼 없는 움직임). `held`는 지금 버튼이
    /// 하나라도 눌렸는가다. 크기는 `init`이 라이브러리에 준 값(`width_px` ·
    /// `height_px` · `cell`)을 그대로 쓴다 — 칸을 세는 산수가 `cells()`와 같다.
    pub fn mouseEncode(
        self: *Screen,
        out: []u8,
        action: MouseAction,
        button: ?MouseButton,
        mods: MouseMods,
        x: i32,
        y: i32,
        held: bool,
    ) []const u8 {
        var w: std.Io.Writer = .fixed(out);
        ghostty_vt.input.encodeMouse(&w, .{
            .action = switch (action) {
                .press => .press,
                .release => .release,
                .motion => .motion,
            },
            .button = if (button) |b| switch (b) {
                .left => .left,
                .middle => .middle,
                .right => .right,
                .wheel_up => .four,
                .wheel_down => .five,
            } else null,
            .mods = .{ .alt = mods.alt, .ctrl = mods.ctrl },
            .pos = .{ .x = @floatFromInt(x), .y = @floatFromInt(y) },
        }, .{
            .event = self.term.flags.mouse_event,
            .format = self.term.flags.mouse_format,
            .size = .{
                .screen = .{ .width = self.term.width_px, .height = self.term.height_px },
                .cell = .{ .width = self.cell.w, .height = self.cell.h },
                .padding = .{},
            },
            .any_button_pressed = held,
            .last_cell = &self.mouse_last,
        }) catch return out[0..0];
        return w.buffered();
    }

    /// 뷰포트가 스크롤백의 어디에 있는지.
```

### 2-2. `vt_test.zig` — 검사 102~106

칸 (10, 5)의 가운데 픽셀은 (83, 87)이다. 검사 105의 X10 바이트 `ESC [ M` 뒤 셋은 32 + 0(공백) · 32 + 11(`+`) · 32 + 6(`&`)이다.

VT1 — `old_string`(기준 파일 2718줄부터):

```zig
    std.debug.print("PASS\n", .{});
}
```

`new_string`:

```zig
    // 검사 102. 마우스 보고(PD-M4). 자식이 모드를 안 켰으면 아무것도 안 짠다.
    // 칸 (10, 5)의 가운데 픽셀은 (10 × 8 + 3, 5 × 16 + 7)이다.
    const ms = try vt.Screen.init(init.io, init.gpa, 20, 8, CELL);
    defer ms.deinit();
    var mbuf: [32]u8 = undefined;
    const mx: i32 = 10 * 8 + 3;
    const my: i32 = 5 * 16 + 7;
    if (ms.mouseWanted()) return error.MouseWantedAtStart;
    try expectMouse(ms.mouseEncode(&mbuf, .press, .left, .{}, mx, my, true), "", "a press before any mode");

    // 검사 103. 1000 + 1006(SGR). 좌표는 1부터 세고, 뗌은 소문자 m이다.
    // 1000은 누른 채 움직여도 보고하지 않는다. 버튼 4 · 5가 64 · 65,
    // Alt가 +8 · Ctrl이 +16이다.
    ms.feed("\x1b[?1000h\x1b[?1006h");
    if (!ms.mouseWanted()) return error.MouseNotWanted;
    try expectMouse(ms.mouseEncode(&mbuf, .press, .left, .{}, mx, my, true), "\x1b[<0;11;6M", "1000 · 1006 press");
    try expectMouse(ms.mouseEncode(&mbuf, .motion, .left, .{}, mx + 16, my, true), "", "1000 does not report a drag");
    try expectMouse(ms.mouseEncode(&mbuf, .release, .left, .{}, mx + 16, my, false), "\x1b[<0;13;6m", "1000 · 1006 release");
    try expectMouse(ms.mouseEncode(&mbuf, .press, .right, .{}, mx, my, true), "\x1b[<2;11;6M", "the right button is 2");
    try expectMouse(ms.mouseEncode(&mbuf, .press, .wheel_up, .{}, mx, my, false), "\x1b[<64;11;6M", "wheel up is button 4");
    try expectMouse(ms.mouseEncode(&mbuf, .press, .wheel_down, .{}, mx, my, false), "\x1b[<65;11;6M", "wheel down is button 5");
    try expectMouse(ms.mouseEncode(&mbuf, .press, .left, .{ .ctrl = true, .alt = true }, mx, my, true), "\x1b[<24;11;6M", "Ctrl and Alt add 16 and 8");
    // 칸의 왼쪽 위 끝 픽셀은 그 칸이고, 한 픽셀 왼쪽 위는 이웃 칸이다.
    try expectMouse(ms.mouseEncode(&mbuf, .press, .left, .{}, 80, 80, true), "\x1b[<0;11;6M", "the top-left pixel of a cell is that cell");
    try expectMouse(ms.mouseEncode(&mbuf, .press, .left, .{}, 79, 79, true), "\x1b[<0;10;5M", "one pixel up-left is the neighbour cell");
    // 패널 밖으로 끌고 뗀 것은 가장자리 칸으로 붙는다. 밖에서의 누름은 버린다.
    try expectMouse(ms.mouseEncode(&mbuf, .release, .left, .{}, -50, -50, false), "\x1b[<0;1;1m", "a release off the top-left edge clamps to 1;1");
    try expectMouse(ms.mouseEncode(&mbuf, .press, .left, .{}, 20 * 8 + 40, my, true), "", "a press right of the pane is dropped");
    std.debug.print("vt_test: 1000 · 1006 보고의 바이트 OK\n", .{});

    // 검사 104. 1002는 누른 채 움직임을 +32로 보고하고, 같은 칸의 움직임은
    // 거른다. 버튼 없는 움직임은 1003만 보고한다(버튼 칸이 3).
    ms.feed("\x1b[?1002h");
    try expectMouse(ms.mouseEncode(&mbuf, .motion, .left, .{}, mx + 16, my, true), "\x1b[<32;13;6M", "1002 reports a drag");
    try expectMouse(ms.mouseEncode(&mbuf, .motion, .left, .{}, mx + 17, my, true), "", "1002 skips a motion inside the same cell");
    try expectMouse(ms.mouseEncode(&mbuf, .motion, null, .{}, mx, my, false), "", "1002 does not report a hover");
    ms.feed("\x1b[?1003h");
    try expectMouse(ms.mouseEncode(&mbuf, .motion, null, .{}, mx, my, false), "\x1b[<35;11;6M", "1003 reports a hover");
    std.debug.print("vt_test: 1002 · 1003 움직임 보고 OK\n", .{});

    // 검사 105. 형식을 끄면 X10이다(라이브러리가 공짜로 준다). `ESC [ M` 뒤 세
    // 바이트가 32 + 버튼 · 32 + 열 · 32 + 행이다. 모드를 끄면 다시 아무것도
    // 안 짠다.
    ms.feed("\x1b[?1006l");
    try expectMouse(ms.mouseEncode(&mbuf, .press, .left, .{}, mx, my, true), "\x1b[M +&", "1003 without 1006 is X10");
    ms.feed("\x1b[?1003l\x1b[?1002l\x1b[?1000l");
    if (ms.mouseWanted()) return error.MouseStillWanted;
    try expectMouse(ms.mouseEncode(&mbuf, .press, .left, .{}, mx, my, true), "", "a press after the modes are off");
    std.debug.print("vt_test: X10 형식과 모드 끄기 OK\n", .{});

    // 검사 106. 휠을 화살표 키로(모드 1007). 주 화면에서는 아니고, 대체
    // 화면에서는 기본값이 켜짐이다. DECCKM이면 `ESC O`다. 1007을 끄면 아니다.
    if (ms.wheelKeys()) return error.WheelKeysOnPrimary;
    ms.feed("\x1b[?1049h");
    if (!ms.wheelKeys()) return error.NoWheelKeysOnAlternate;
    try expectMouse(ms.wheelKey(true), "\x1b[A", "wheel up on the alternate screen");
    try expectMouse(ms.wheelKey(false), "\x1b[B", "wheel down on the alternate screen");
    ms.feed("\x1b[?1h");
    try expectMouse(ms.wheelKey(true), "\x1bOA", "wheel up under DECCKM");
    ms.feed("\x1b[?1007l");
    if (ms.wheelKeys()) return error.WheelKeysAfter1007Off;
    ms.feed("\x1b[?1007h\x1b[?1049l");
    if (ms.wheelKeys()) return error.WheelKeysBackOnPrimary;
    std.debug.print("vt_test: 대체 화면의 휠은 화살표 키 OK\n", .{});

    std.debug.print("PASS\n", .{});
}

/// 마우스 보고 하나가 기대한 바이트인가(PD-M4). 다르면 둘 다 `{any}`로 찍는다 —
/// 이스케이프 바이트가 그대로 터미널에 나가지 않게.
fn expectMouse(got: []const u8, want: []const u8, what: []const u8) !void {
    if (std.mem.eql(u8, got, want)) return;
    std.debug.print("FAIL: {s}: got {any}, want {any}\n", .{ what, got, want });
    return error.WrongMouseBytes;
}
```

### 2-3. `input.zig` · `input_test.zig` — `modifiers`

I1 — `old_string`(기준 파일 798줄부터):

```zig
        return self.shift_left or self.shift_right;
    }
```

`new_string`:

```zig
        return self.shift_left or self.shift_right;
    }

    /// 지금 눌린 수정키 셋(PD-M4). 포인터 경로가 읽는다 — Shift는 자식이
    /// 마우스를 원해도 누름을 우리 것으로 돌리고, Alt · Ctrl은 마우스 보고에
    /// 실린다(PD design 결정 12). Meta(Cmd)는 안 싣는다. 보고 형식에 그 비트가
    /// 없다.
    ///
    /// 좌우를 합친다. `keyboard=apple`의 맞바꿈은 `handleKey` 맨 앞에서 이미
    /// 끝났으므로 `alt`는 Option 자리의 키다(결정 9).
    pub fn modifiers(self: State) Modifiers {
        return .{
            .shift = self.shifted(),
            .ctrl = self.ctrl_left or self.ctrl_right,
            .alt = self.alt_left or self.alt_right,
        };
    }

    pub const Modifiers = struct { shift: bool, ctrl: bool, alt: bool };
```

IT1 — `old_string`(기준 파일 1820줄부터):

```zig
    std.debug.print("PASS\n", .{});
```

`new_string`:

```zig
    // 검사 68. 포인터 경로가 읽는 수정키(PD-M4). 좌우를 합치고, 누른 동안만
    // 서 있다. Shift는 자식이 마우스를 원해도 누름을 우리 것으로 돌린다.
    {
        var md: input.State = .{};
        if (md.modifiers().shift or md.modifiers().ctrl or md.modifiers().alt) return error.ModifierAtStart;
        try expect(&md, K.KEY_RIGHTSHIFT, 1, "");
        if (!md.modifiers().shift) return error.RightShiftNotSeen;
        try expect(&md, K.KEY_LEFTCTRL, 1, "");
        try expect(&md, K.KEY_LEFTALT, 1, "");
        const both = md.modifiers();
        if (!both.shift or !both.ctrl or !both.alt) return error.ModifiersMissing;
        try expect(&md, K.KEY_RIGHTSHIFT, 0, "");
        try expect(&md, K.KEY_LEFTCTRL, 0, "");
        try expect(&md, K.KEY_LEFTALT, 0, "");
        if (md.modifiers().shift or md.modifiers().ctrl or md.modifiers().alt) return error.ModifierStuck;
    }
    std.debug.print("input_test: 포인터 경로가 읽는 수정키 OK\n", .{});

    std.debug.print("PASS\n", .{});
```

### 2-4. 확인

```bash
for f in vt vt_test input input_test; do diff terminal/src/$f.zig /tmp/run/pdm4/new/terminal/src/$f.zig && echo SAME-$f; done
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c '
  zig build test > /tmp/t.out 2>&1; echo "exit=$?"
  grep -a -c "^vt_test: .* OK$" /tmp/t.out
  grep -a -c "^input_test: .* OK$" /tmp/t.out
  grep -a -E "PD-M4|보고의 바이트|움직임 보고|X10 형식|화살표 키 OK|수정키 OK" /tmp/t.out
  grep -a -E "^FAIL|error:" /tmp/t.out | head -5'
```

기대: `SAME-` 넷, `exit=0`, `vt_test` OK 82 · `input_test` OK 16(Task 0보다 넷 · 하나). 가운데 `grep`은 다섯 줄이다.

```
input_test: 포인터 경로가 읽는 수정키 OK
vt_test: 1000 · 1006 보고의 바이트 OK
vt_test: 1002 · 1003 움직임 보고 OK
vt_test: X10 형식과 모드 끄기 OK
vt_test: 대체 화면의 휠은 화살표 키 OK
```

## Task 3: `terminal/src/main.zig` — 편집 열

확정 5의 배선이다. 순서대로 넣는다. E1 · E2가 전이 칸, E3이 드레인, E4가 `dumpReport`, E5가 `PointerWire`의 칸 셋, E6이
함수 다섯, E7이 휠, E8이 변수 둘, E9 · E10이 루프의 주석과 배선이다.

E1 — `old_string`(기준 파일 1485줄부터):

```zig
/// 한 회차의 왼쪽 버튼 전이 하나(PD-M2). 그 순간의 포인터 자리와 함께 든다 —
/// 회차가 끝난 뒤의 자리 하나로는 "누르고 끌고 뗐다"의 순서를 되살릴 수 없다.
const PointerEdge = struct { down: bool, x: u32, y: u32 };
```

`new_string`:

```zig
/// 한 회차의 버튼 전이 하나(PD-M2). 그 순간의 포인터 자리와 함께 든다 —
/// 회차가 끝난 뒤의 자리 하나로는 "누르고 끌고 뗐다"의 순서를 되살릴 수 없다.
/// PD-M2는 왼쪽만 담았고, PD-M4부터 셋을 다 담는다 — 오른쪽 · 가운데도
/// 자식에게 보고로 간다.
const PointerEdge = struct { down: bool, button: pointer.Button, x: u32, y: u32 };
```

E2 — `old_string`(기준 파일 1501줄부터):

```zig
    /// 왼쪽 버튼의 눌림 · 뗌(PD-M2). 회차 안의 순서대로, 그 순간의 자리와 함께.
```

`new_string`:

```zig
    /// 버튼의 눌림 · 뗌(PD-M2, PD-M4부터 셋 다). 회차 안의 순서대로, 그 순간의
    /// 자리와 함께.
```

E3 — `old_string`(기준 파일 1762줄부터):

```zig
                // 왼쪽 버튼의 전이는 그 순간의 자리와 함께 순서대로 담는다(PD-M2).
                // 한 회차에 누르고 끌고 떼는 보고가 다 들어와도 순서가 남는다.
                if ((e.pressed.left or e.released.left) and round.edge_count < MAX_EDGES) {
                    round.edges[round.edge_count] = .{ .down = e.pressed.left, .x = state.x, .y = state.y };
```

`new_string`:

```zig
                // 버튼의 전이는 그 순간의 자리와 함께 순서대로 담는다(PD-M2).
                // 한 회차에 누르고 끌고 떼는 보고가 다 들어와도 순서가 남는다.
                for ([_]pointer.Button{ .left, .right, .middle }) |b| {
                    const down = e.pressed.has(b);
                    if (!down and !e.released.has(b)) continue;
                    if (round.edge_count == MAX_EDGES) break;
                    round.edges[round.edge_count] = .{ .down = down, .button = b, .x = state.x, .y = state.y };
```

E4 — `old_string`(기준 파일 1780줄부터):

```zig
    devs[slot] = null;
```

`new_string`:

```zig
    devs[slot] = null;
}

/// 자식에게 보낸 보고 한 줄(PD-M4). `n`은 같은 바이트를 몇 번 보냈는가다 —
/// 마우스 보고는 1, 휠을 바꾼 화살표 키는 눈금 × `WHEEL_ROWS`다.
///
///   terminal: pointer> report leaf=0 n=1 text=^[[<0;11;6M
///
/// 바이트는 `cat -v`의 모양으로 찍는다 — 제어 바이트는 `^` 뒤에 64를 더한
/// 글자, 0x7F는 `^?`, 0x80 이상은 `M-` 뒤에 아래 7비트다. 게이트가 게스트의
/// `cat -v`가 찍은 화면 줄과 이 줄을 같은 글자로 맞춘다.
fn dumpReport(leaf: u4, n: usize, bytes: []const u8) void {
    var buf: [128]u8 = undefined;
    var len: usize = 0;
    for (bytes) |raw| {
        if (len + 4 > buf.len) break;
        var b = raw;
        if (b >= 0x80) {
            buf[len] = 'M';
            buf[len + 1] = '-';
            len += 2;
            b -= 0x80;
        }
        if (b < 0x20 or b == 0x7F) {
            buf[len] = '^';
            buf[len + 1] = if (b == 0x7F) '?' else b + 0x40;
            len += 2;
        } else {
            buf[len] = b;
            len += 1;
        }
    }
    std.debug.print("terminal: pointer> report leaf={d} n={d} text={s}\n", .{ leaf, n, buf[0..len] });
```

E5 — `old_string`(기준 파일 1808줄부터):

```zig
    /// 의도가 화면을 바꿨다. 부르는 쪽이 `needs_redraw`로 옮긴다.
```

`new_string`:

```zig
    /// 버튼이 눌린 동안의 주인(PD-M4, `pointer.Grab`).
    grab: *pointer.Grab,
    /// 주인을 정한 누름의 워크스페이스 번호. 다른 워크스페이스로 옮긴 뒤의
    /// 보고는 버린다 — 그 패널은 지금 `ws`에 없다.
    grab_ws: *usize,
    /// 이 회차의 수정키(`input.State.modifiers`). 키보드 분기가 포인터 분기
    /// 앞이라 같은 회차에 친 Shift도 들어 있다.
    mods: input.State.Modifiers,
    /// 의도가 화면을 바꿨다. 부르는 쪽이 `needs_redraw`로 옮긴다.
```

E6 — `old_string`(기준 파일 1821줄부터):

```zig
        return if (p.screen.copyActive()) .copy else .normal;
```

`new_string`:

```zig
        return if (p.screen.copyActive()) .copy else .normal;
    }

    /// 포인터 아래 패널과 그 상태(PD-M4). 여백 · 구분선 · 상태 줄이면 null이다.
    fn paneAt(self: *const PointerWire, x: u32, y: u32) ?pointer.Pane {
        const gc = gridCell(x, y, self.cols, self.rows) orelse return null;
        const h = self.ws.tree.hit(self.whole, gc.col, gc.row) orelse return null;
        const p = &self.ws.panes[h.leaf].?;
        return .{
            .leaf = h.leaf,
            .wants = p.screen.mouseWanted(),
            .copy = p.screen.copyActive(),
            .alt_keys = p.screen.wheelKeys(),
        };
    }

    /// 버튼 하나의 전이(PD-M4). 버튼이 하나도 안 눌렸을 때의 첫 누름이 주인을
    /// 정하고(`pointer.Grab`), 그 주인이 마지막 뗌까지 간다(design 결정 12).
    ///
    /// 우리 것이면 PD-M2 그대로다 — 왼쪽만 `Gesture`로 가고 오른쪽 · 가운데는
    /// 아무 일도 없다. 자식의 것이면 첫 누름이 포커스를 옮긴 뒤 보고하고,
    /// 나머지 누름 · 뗌은 보고만 한다.
    fn edge(self: *PointerWire, e: PointerEdge) !void {
        if (!e.down) {
            switch (self.grab.release(e.button)) {
                .child => self.report(.release, e.button, e.x, e.y),
                .ours => if (e.button == .left) try self.release(),
            }
            return;
        }
        const fresh = !self.grab.active();
        const owner = self.grab.press(e.button, self.paneAt(e.x, e.y), self.mods.shift);
        if (fresh) self.grab_ws.* = self.current;
        switch (owner) {
            .child => {
                if (fresh) try self.run(self.gesture.handOff(self.grab.leaf, self.ws.focus));
                self.report(.press, e.button, e.x, e.y);
            },
            .ours => if (e.button == .left) try self.press(e.x, e.y),
        }
    }

    /// 포인터가 움직였다(PD-M4). 버튼이 눌린 채면 그 주인에게 — 자식이면 누른
    /// 채 움직임으로 보고하고, 우리면 `Gesture`의 끎이다. 안 눌렸으면 포인터
    /// 아래 패널의 자식에게 버튼 없는 움직임으로 보고한다. 그것을 실제로
    /// 보내는 것은 모드 1003뿐이다(인코더가 거른다).
    fn moved(self: *PointerWire, x: u32, y: u32) !void {
        if (!self.grab.active()) {
            const p = self.paneAt(x, y) orelse return;
            if (pointer.ownerOf(p, self.mods.shift) == .child) self.reportTo(p.leaf, .motion, null, x, y);
            return;
        }
        switch (self.grab.owner) {
            .child => self.report(.motion, self.grab.dragButton(), x, y),
            .ours => try self.motion(x, y),
        }
    }

    /// 주인을 정한 패널에 보고한다. 그 워크스페이스를 떠났으면 버린다 —
    /// 자식은 뗌을 못 받지만 다음 누름이 고친다.
    fn report(self: *PointerWire, action: vt.Screen.MouseAction, b: ?pointer.Button, x: u32, y: u32) void {
        if (self.grab_ws.* != self.current) return;
        const button: ?vt.Screen.MouseButton = if (b) |v| switch (v) {
            .left => .left,
            .right => .right,
            .middle => .middle,
        } else null;
        self.reportTo(self.grab.leaf, action, button, x, y);
    }

    /// 패널 `leaf`의 자식에게 마우스 사건 하나를 보낸다(PD-M4). 좌표는 그
    /// 패널의 왼쪽 위 끝에서 잰 픽셀이다 — `paneOrigin`이 렌더러와 `gridCell`이
    /// 쓰는 상수 넷으로 그 끝을 구한다(design 결정 5와 같은 이유). 인코더가
    /// 보낼 것이 없다고 하면(모드가 그 사건을 원하지 않는다) 아무것도 안 한다.
    fn reportTo(self: *PointerWire, leaf: u4, action: vt.Screen.MouseAction, button: ?vt.Screen.MouseButton, x: u32, y: u32) void {
        const p = if (self.ws.panes[leaf]) |*pane| pane else return;
        var rs: [layout.MAX_LEAVES]layout.Rect = undefined;
        self.ws.tree.rects(self.whole, &rs);
        const o = paneOrigin(rs[leaf]);
        var buf: [32]u8 = undefined;
        const bytes = p.screen.mouseEncode(
            &buf,
            action,
            button,
            .{ .alt = self.mods.alt, .ctrl = self.mods.ctrl },
            @as(i32, @intCast(x)) - @as(i32, @intCast(o.x)),
            @as(i32, @intCast(y)) - @as(i32, @intCast(o.y)),
            self.grab.active(),
        );
        if (bytes.len == 0) return;
        pty.write(p.session.master_fd, bytes);
        dumpReport(leaf, 1, bytes);
```

E7 — `old_string`(기준 파일 1873줄부터):

```zig
    fn wheel(self: *PointerWire, notches: i32, x: u32, y: u32) !void {
        if (self.gesture.wheel(notches, self.target())) |its| return self.run(its);
        const cell = gridCell(x, y, self.cols, self.rows) orelse return;
        const h = self.ws.tree.hit(self.whole, cell.col, cell.row) orelse return;
        const p = &self.ws.panes[h.leaf].?;
        if (p.screen.copyActive()) return;
        p.screen.scrollByRows(-WHEEL_ROWS * @as(isize, notches));
        self.redraw = true;
```

`new_string`:

```zig
    ///
    /// PD-M4부터 그 패널의 자식이 마우스를 원하면 눈금마다 버튼 4(위) · 5(아래)의
    /// 누름으로 보고하고, 대체 화면이고 모드 1007이면 화살표 키를 눈금마다
    /// `WHEEL_ROWS`번 보낸다(`pointer.wheelRoute`). 포커스는 어느 쪽이든 안
    /// 바뀐다.
    fn wheel(self: *PointerWire, notches: i32, x: u32, y: u32) !void {
        if (self.gesture.wheel(notches, self.target())) |its| return self.run(its);
        const pane = self.paneAt(x, y) orelse return;
        const p = &self.ws.panes[pane.leaf].?;
        switch (pointer.wheelRoute(pane, self.mods.shift)) {
            .ignore => {},
            .scroll => {
                p.screen.scrollByRows(-WHEEL_ROWS * @as(isize, notches));
                self.redraw = true;
            },
            .report => for (0..@abs(notches)) |_| {
                self.reportTo(pane.leaf, .press, if (notches > 0) .wheel_up else .wheel_down, x, y);
            },
            .keys => {
                const key = p.screen.wheelKey(notches > 0);
                const n = @as(usize, @intCast(WHEEL_ROWS)) * @abs(notches);
                for (0..n) |_| pty.write(p.session.master_fd, key);
                dumpReport(pane.leaf, n, key);
            },
        }
```

E8 — `old_string`(기준 파일 2223줄부터):

```zig
    var gesture_ws: usize = 0;
```

`new_string`:

```zig
    var gesture_ws: usize = 0;
    // 버튼이 눌린 동안의 주인과 그 워크스페이스(PD-M4). 자식이 마우스를
    // 원하면 누름이 `gesture` 대신 그 자식에게 보고로 간다.
    var grab: pointer.Grab = .{};
    var grab_ws: usize = 0;
```

E9 — `old_string`(기준 파일 2583줄부터):

```zig
        // 왼쪽 버튼의 전이를 회차 안의 순서대로 먼저 돈다. 전이마다 그 순간의
        // 자리로 움직임을 먼저 주고 그다음 누름이나 뗌을 준다 — 끌다가 뗀 보고
        // 하나는 마지막 칸까지 선택을 늘린 뒤에 복사해야 한다. 그다음 회차
        // 끝의 자리로 움직임 한 번, 마지막이 휠이다.
```

`new_string`:

```zig
        // 버튼의 전이를 회차 안의 순서대로 먼저 돈다. 전이마다 그 순간의
        // 자리로 움직임을 먼저 주고 그다음 누름이나 뗌을 준다 — 끌다가 뗀 보고
        // 하나는 마지막 칸까지 선택을 늘린 뒤에 복사해야 한다. 그다음 회차
        // 끝의 자리로 움직임 한 번, 마지막이 휠이다.
        //
        // PD-M4부터 전이마다 주인을 가른다(`pointer.Grab`, design 결정 12).
        // 자식이 마우스를 원하는 패널의 누름은 `Gesture`를 건너뛰고 그 PTY에
        // 보고로 간다. 회차 끝에 `settle`이 주인의 버튼을 포인터의 버튼에
        // 맞춘다 — 누른 채 빠진 장치의 버튼이 영영 눌린 채로 남지 않게.
```

E10 — `old_string`(기준 파일 2603줄부터):

```zig
            };
            for (round.edges[0..round.edge_count]) |e| {
                try wire.motion(e.x, e.y);
                if (e.down) try wire.press(e.x, e.y) else try wire.release();
            }
            if (round.woke) try wire.motion(pointer_state.x, pointer_state.y);
```

`new_string`:

```zig
                .grab = &grab,
                .grab_ws = &grab_ws,
                .mods = key_state.modifiers(),
            };
            for (round.edges[0..round.edge_count]) |e| {
                try wire.moved(e.x, e.y);
                try wire.edge(e);
            }
            grab.settle(pointer_state.buttons);
            if (round.woke) try wire.moved(pointer_state.x, pointer_state.y);
```

### 3-1. 확인

```bash
diff terminal/src/main.zig /tmp/run/pdm4/new/terminal/src/main.zig && echo SAME-main
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c '
  ./prepare.sh > /tmp/p.out 2>&1; echo "prepare exit=$?"
  zig build test > /tmp/t.out 2>&1; echo "test exit=$?"
  grep -a -E "^FAIL|error:" /tmp/t.out | head -5'
```

기대: `SAME-main`, `prepare exit=0` · `test exit=0`, 마지막 `grep` 0줄.

## Task 4: 게스트 vimrc와 GE design

design 결정 12의 "게스트 vimrc". 주석은 vimrc의 관습대로 영어이고 따로 한 줄을 차지한다(GE design 원칙 5).

### 4-1. `kernel/vim/vimrc`

R1 — `old_string`(기준 파일 113줄부터):

```vim
" Our terminal has no mouse reporting and ignores the window title.
set mouse=
```

`new_string`:

```vim
" Our terminal reports clicks, drags and the wheel to a program that asks
" (PD design decision 12), so vim takes the mouse in every mode: a click moves
" the cursor, a drag makes a Visual selection, the wheel scrolls. Hold Shift to
" select text for the terminal's own clipboard instead. To give the mouse back
" to the terminal, put this in /.vimrc:
"   set mouse=
set mouse=a
" SGR reports have no column limit. The older xterm format stops at column 223,
" which a wide laptop screen passes.
set ttymouse=sgr
" Our terminal ignores the window title.
```

### 4-2. `docs/specs/2026-10-04-tars-guest-ergonomics-design.md` — 덧붙임 셋

옛 글은 그대로 두고 PD-M4가 바꿨다고 덧붙인다(다시 연 결정의 관습).

G1 — `old_string`(기준 파일 172줄부터):

```markdown
   남긴다.
```

`new_string`:

```markdown
   남긴다.
   > PD-M4가 마우스 쪽 전제를 바꿨다(2026-10-05). 터미널이 자식에게 마우스를 보고하게 되어 vimrc가
   > `mouse=a` · `ttymouse=sgr`이 됐다. 원칙은 그대로이고 그 원칙이 고른 값이 바뀐 것이다 — 이제 우리
   > 터미널이 하는 일이다. 우리 선택은 Shift를 누른 끌기다. PD design 결정 12, [[project_pointer_devices]].
```

G2 — `old_string`(기준 파일 209줄부터):

```markdown
| 화면 | `mouse=` `notitle` | 원칙 3 |
```

`new_string`:

```markdown
| 화면 | `mouse=` `notitle` | 원칙 3. PD-M4가 `mouse=`를 `mouse=a` · `ttymouse=sgr`로 바꿨다(PD design 결정 12) |
```

G3 — `old_string`(기준 파일 227줄부터):

```markdown
| `mouse=a` | 우리 터미널에 마우스 보고가 없다 |
```

`new_string`:

```markdown
| `mouse=a` | 우리 터미널에 마우스 보고가 없다. PD-M4가 보고를 더해 이 줄이 vimrc에 들어갔다(PD design 결정 12) |
```

### 4-3. 확인

```bash
diff kernel/vim/vimrc /tmp/run/pdm4/new/kernel/vim/vimrc && echo SAME-vimrc
diff docs/specs/2026-10-04-tars-guest-ergonomics-design.md /tmp/run/pdm4/new/docs/specs/2026-10-04-tars-guest-ergonomics-design.md && echo SAME-ge
LC_ALL=C rg -c '[^\x00-\x7F]' kernel/vim/vimrc || echo ASCII-ONLY
```

기대: `SAME-vimrc` · `SAME-ge` · `ASCII-ONLY`(vimrc는 ASCII다 — GE design 원칙 5).

## Task 5: `pointer/check.sh` · `check.sh`

### 5-1. `pointer/check.sh` — 편집 일곱

검사 26~32는 부팅 B의 검사 25 뒤, NUL 검사 앞에 들어간다. 설정 디스크에는 프로브(`pd/mouse`)와 vim이 열 서른 줄
파일(`pd/lines`)이 더해진다. heredoc의 따옴표(`<<'MOUSE'`)가 프로브 안의 `$`와 `\033`을 게이트의 셸에서 지킨다.

C1 — `old_string`(기준 파일 6줄부터):

```bash
# PD 체인 — 포인터 장치(PD-M0~M3). 열아홉번째 체인.
```

`new_string`:

```bash
# PD 체인 — 포인터 장치(PD-M0~M4). 열아홉번째 체인.
```

C2 — `old_string`(기준 파일 28줄부터):

```bash
#     (부팅 B)
```

`new_string`:

```bash
#     (부팅 B)
#   → 자식이 마우스 모드를 켜면 누름 · 끎 · 뗌 · 휠이 우리 선택 대신 그 자식의
#     PTY에 보고로 간다. Shift를 누르면 우리 것이고, 대체 화면의 휠은 화살표
#     키가 된다. vim이 시스템 vimrc의 mouse=a로 클릭을 받는다(PD-M4, 부팅 B)
```

C3 — `old_string`(기준 파일 53줄부터):

```bash
#                그대로 쓴다.
```

`new_string`:

```bash
#                그대로 쓴다.
#   report 줄과 프로브의 화면 줄 — terminal이 자식에게 보낸 바이트(report 줄,
#                cat -v 모양)와 자식이 실제로 읽은 바이트(설정 디스크의
#                /config/pd/mouse가 cat -v로 찍은 화면 줄)를 같은 글자로 본다
#                (검사 26~32).
```

C4 — `old_string`(기준 파일 164줄부터):

```bash
    "tp-replay:"; do
```

`new_string`:

```bash
    "tp-replay:" \
    "terminal: pointer> report" \
    "pd-mouse-ready" \
    "pd-mouse-got"; do
```

C5 — `old_string`(기준 파일 1136줄부터):

```bash
chmod 0755 "$SEED/pd/drivers"
```

`new_string`:

```bash
chmod 0755 "$SEED/pd/drivers"
# PD-M4의 프로브. 마우스 모드를 켜고, terminal이 보낸 보고를 정해진 바이트 수만큼
# 읽어 cat -v로 찍는다. 이스케이프 바이트는 게이트가 타이핑으로 만들 수 없어서
# (lessons 실측 53, tq-probe와 같은 이유) 파일로 싣는다.
#
#   /config/pd/mouse <표지> <바이트 수> <초> <DECSET 번호…>
#
# 표지는 화면 줄을 이 호출의 것으로 가른다 — 친 명령줄(pd/mouse)과 판정 글자
# (pd-mouse-ready-표지 · pd-mouse-got-표지)가 안 겹친다(project_gate_screen_echo).
# 켜기 · 읽기 · 끄기가 한 프로세스 안에 있어야 한다. 보고는 pty의 입력이고,
# 프롬프트로 돌아온 셸이 먼저 읽으면 그 셸의 키가 된다(tq-probe와 같다).
# read -N은 정해진 글자 수를 읽고 -s가 에코를 끈다. 시간이 다 되면 그때까지
# 읽은 것을 남긴다 — 보고가 없으면 0이다. 게스트에 stty가 없어서 bash의 read가
# 터미널을 raw로 바꾸는 유일한 길이다.
cat > "$SEED/pd/mouse" <<'MOUSE'
#!/usr/bin/bash
tag=$1 len=$2 secs=$3
shift 3
for m in "$@"; do printf '\033[?%sh' "$m"; done
echo "pd-mouse-ready-${tag}"
IFS= read -rs -N "$len" -t "$secs" got
for m in "$@"; do printf '\033[?%sl' "$m"; done
printf 'pd-mouse-got-%s %d [%s]\n' "$tag" "${#got}" "$(printf '%s' "$got" | cat -v)"
MOUSE
chmod 0755 "$SEED/pd/mouse"
# vim이 클릭을 받는지 볼 파일(검사 31). 서른 줄이라 한 화면에 다 든다.
for i in $(seq -w 1 30); do echo "pd-line-${i}"; done > "$SEED/pd/lines"
```

C6 — `old_string`(기준 파일 1326줄부터):

```bash
echo "closed: $(grep -a 'terminal: pointer> close ' "$LOG" | tail -n 1 | tr -d '\r')"
```

`new_string`:

```bash
echo "closed: $(grep -a 'terminal: pointer> close ' "$LOG" | tail -n 1 | tr -d '\r')"

# ══ PD-M4: 마우스 보고 (부팅 B) ══════════════════════════════════════════
#
# 자식이 마우스 모드를 켜면 누름 · 끎 · 뗌 · 휠이 그 자식의 PTY에 보고로 간다
# (design 결정 12). 판정은 둘을 같은 글자로 맞춘다 — terminal이 보낸 것(report
# 줄)과 자식이 읽은 것(/config/pd/mouse가 찍은 화면 줄). report 줄만 보면 PTY에
# 안 쓴 고장이 안 보이고, 화면 줄만 보면 어느 패널에 보냈는지가 안 보인다.
#
# 포인터는 PS/2 마우스로 움직인다. 부팅 B의 HMP 대상은 그것 하나이고 이동이
# 1:1이다(PD-M4 plan 확정 7). 터치패드가 닫힌 뒤라 at 줄의 자리가 그대로 이어진다.
#
# 누르는 칸은 1행 10열이고 끄는 칸은 1행 12열이다. 칸의 가운데 픽셀(+3, +7)을
# 쓴다 — 칸 경계는 vt_test 검사 103이 본다. 1행에 무엇이 있든 상관없다. 보고는
# 글자를 안 보고, 프로브가 도는 동안 셸은 그 줄을 안 다시 그린다.

# ── PD-M4의 도구 ──────────────────────────────────────────────────────

# report 줄의 개수와 마지막 줄.
report_count() {
  grep -ac 'terminal: pointer> report ' "$LOG" || true
}

last_report() {
  grep -a 'terminal: pointer> report ' "$LOG" | tail -n 1 | tr -d '\r'
}

# 글자열 하나를 sendkey 이름으로 바꿔 치고 Enter를 친다. 영소문자 · 숫자 ·
# 공백 · / · - 만 쓴다.
type_cmd() {
  local s="$1" keys=() ch i
  for ((i = 0; i < ${#s}; i++)); do
    ch="${s:i:1}"
    case "$ch" in
      ' ') keys+=(spc) ;;
      /) keys+=(slash) ;;
      -) keys+=(minus) ;;
      *) keys+=("$ch") ;;
    esac
  done
  type_keys "${keys[@]}" ret
}

# 화면 줄에 글자 그대로($1)가 나타날 때까지 기다린다. 15초. 프로브의 줄에는
# ERE의 특수 문자(^ [ ])가 가득해서 wait_for_screen에 못 넘긴다.
wait_for_screen_text() {
  local text="$1" i
  for i in $(seq 1 150); do
    if grep -aqF -- "$text" <<<"$(grep -a 'terminal: screen>' "$LOG")"; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 화면 줄 중 N번째 뒤의 것에 패턴(ERE)이 나타날 때까지 기다린다. 15초.
# wait_for_screen은 로그 전체를 보므로 옛 화면에 바로 맞는 자리에 쓴다.
wait_for_new_screen() {
  local n="$1" pattern="$2" i
  for i in $(seq 1 150); do
    if grep -aqE -- "$pattern" <<<"$(grep -a 'terminal: screen>' "$LOG" | tail -n "+$((n + 1))")"; then return 0; fi
    sleep 0.1
  done
  return 1
}

# 프로브를 띄우고 모드가 켜질 때까지 기다린다. 인자는 표지 · 바이트 수 · 초 ·
# DECSET 번호들이다. ready 줄은 모드를 켠 printf 뒤에 찍히므로, 그 줄을 그린
# 프레임이 보이면 terminal은 모드 바이트를 이미 먹었다.
probe_start() {
  type_cmd "/config/pd/mouse $*"
  wait_for_screen_text "pd-mouse-ready-$1"
}

# 프로브가 찍은 결과 줄(마지막 screen>에서 pd-mouse-got-표지로 시작하는 행).
# 나올 때까지 기다린 뒤 그 행을 낸다. 20초 — 프로브가 시간이 다 되어 끝나는
# 검사(29)가 있다.
probe_result() {
  local tag="$1" i
  for i in $(seq 1 200); do
    if grep -aqF -- "pd-mouse-got-${tag} " <<<"$(grep -a 'terminal: screen>' "$LOG")"; then break; fi
    sleep 0.1
  done
  grep -a 'terminal: screen>' "$LOG" | tail -n 1 | tr -d '\r' |
    TAG="$tag" perl -ne 's/^.*?terminal: screen> //; chomp;
      for my $r (split / \| /, $_, -1) { print "$r\n" if index($r, "pd-mouse-got-$ENV{TAG} ") == 0 }' | tail -n 1
}

# HMP mouse_button 하나를 보내고 report 줄이 하나 늘 때까지 기다린다.
report_button() {
  local n
  n="$(report_count)"
  hmp "mouse_button $1"
  wait_for_count report_count '' "$((n + 1))"
}

CX=$(( $(cell_x 10) + 3 ))
CY=$(( $(cell_y 1) + 7 ))
DX=$(( $(cell_x 12) + 3 ))

# ── 검사 26: 모드 1000은 누름과 뗌만 받는다 ───────────────────────────
#
# 1000 · 1006(SGR)을 켜고 10열을 눌러 12열까지 끌어 뗀다. 자식이 받는 것은
# 누름(ESC[<0;11;2M)과 뗌(ESC[<0;13;2m)이고 끎은 없다 — 좌표는 1부터 세고 뗌은
# 소문자 m이다. 우리 제스처는 안 돈다(press 줄 · copy> enter가 안 는다).
# 모드를 무시하고 언제나 우리 것으로 다루면(mutation 1) report 줄이 안 나온다.
echo "=== boot B: mode 1000 gets the press and the release, not the drag ==="
move_to "$CX" "$CY" || report_failure "the PS/2 mouse did not bring the pointer to ${CX},${CY} (last at: '$(last_at)')"
PRESSES_BEFORE="$(pointer_count 'press ')"
ENTERS_BEFORE="$(copy_lines enter)"
REPORTS_BEFORE="$(report_count)"
probe_start a 20 8 1000 1006 || report_failure "the probe never printed pd-mouse-ready-a"
report_button 1 || report_failure "a press in a pane with mode 1000 printed no 'pointer> report' line (last press: '$(last_press)')"
[ "$(last_report)" = 'terminal: pointer> report leaf=0 n=1 text=^[[<0;11;2M' ] ||
  report_failure "the press was reported as '$(last_report)', expected 'report leaf=0 n=1 text=^[[<0;11;2M'"
move_to "$DX" "$CY" || report_failure "the drag did not reach ${DX},${CY} (last at: '$(last_at)')"
report_button 0 || report_failure "the release in mode 1000 printed no 'pointer> report' line"
[ "$(last_report)" = 'terminal: pointer> report leaf=0 n=1 text=^[[<0;13;2m' ] ||
  report_failure "the release was reported as '$(last_report)', expected 'report leaf=0 n=1 text=^[[<0;13;2m'"
GOT="$(probe_result a)"
[ "$GOT" = 'pd-mouse-got-a 20 [^[[<0;11;2M^[[<0;13;2m]' ] ||
  report_failure "the child read '${GOT}', expected 'pd-mouse-got-a 20 [^[[<0;11;2M^[[<0;13;2m]'"
[ "$(report_count)" -eq "$((REPORTS_BEFORE + 2))" ] ||
  report_failure "mode 1000 reported more than the press and the release ($((REPORTS_BEFORE)) -> $(report_count), last '$(last_report)')"
[ "$(pointer_count 'press ')" -eq "$PRESSES_BEFORE" ] && [ "$(copy_lines enter)" -eq "$ENTERS_BEFORE" ] ||
  report_failure "a reported press also ran our gesture (press lines ${PRESSES_BEFORE} -> $(pointer_count 'press '), copy> enter ${ENTERS_BEFORE} -> $(copy_lines enter))"
echo "1000: ${GOT}"

# ── 검사 27: 모드 1002는 누른 채 움직임도 받는다 ───────────────────────
#
# 같은 손동작에 끎 하나가 더해진다. 끎은 버튼 0에 32를 더한 32다. 끄는 보고에
# 버튼을 안 실으면 인코더가 1002에서 그것을 버린다.
echo "=== boot B: mode 1002 also gets the drag ==="
move_to "$CX" "$CY" || report_failure "the pointer did not come back to ${CX},${CY} (last at: '$(last_at)')"
probe_start b 31 8 1002 1006 || report_failure "the probe never printed pd-mouse-ready-b"
report_button 1 || report_failure "a press in mode 1002 printed no 'pointer> report' line"
N="$(report_count)"
move_to "$DX" "$CY" || report_failure "the drag did not reach ${DX},${CY} (last at: '$(last_at)')"
wait_for_count report_count '' "$((N + 1))" ||
  report_failure "a drag in mode 1002 printed no 'pointer> report' line"
[ "$(last_report)" = 'terminal: pointer> report leaf=0 n=1 text=^[[<32;13;2M' ] ||
  report_failure "the drag was reported as '$(last_report)', expected 'report leaf=0 n=1 text=^[[<32;13;2M'"
report_button 0 || report_failure "the release in mode 1002 printed no 'pointer> report' line"
GOT="$(probe_result b)"
[ "$GOT" = 'pd-mouse-got-b 31 [^[[<0;11;2M^[[<32;13;2M^[[<0;13;2m]' ] ||
  report_failure "the child read '${GOT}', expected 'pd-mouse-got-b 31 [^[[<0;11;2M^[[<32;13;2M^[[<0;13;2m]'"
echo "1002: ${GOT}"

# ── 검사 28: 마우스를 원하는 패널의 휠은 버튼 4 · 5다 ─────────────────
#
# 포인터는 12열에 있다. 위로 한 눈금 · 아래로 한 눈금이 64 · 65이고, 우리
# 스크롤백은 안 움직인다. scroll> 줄은 프로브의 출력으로도 찍히므로 줄 수가 아니라
# 값을 본다 — 이 검사 동안 찍힌 scroll> 줄이 전부 바닥(offset = total - len)이다.
echo "=== boot B: the wheel over a pane in mode 1000 is buttons 4 and 5 ==="
SCROLLS_N="$(grep -ac 'terminal: scroll>' "$LOG" || true)"
probe_start c 22 8 1000 1006 || report_failure "the probe never printed pd-mouse-ready-c"
N="$(report_count)"
hmp "mouse_move 0 0 1"
wait_for_count report_count '' "$((N + 1))" || report_failure "a wheel notch up in mode 1000 printed no 'pointer> report' line"
hmp "mouse_move 0 0 -1"
wait_for_count report_count '' "$((N + 2))" || report_failure "a wheel notch down in mode 1000 printed no 'pointer> report' line"
GOT="$(probe_result c)"
[ "$GOT" = 'pd-mouse-got-c 22 [^[[<64;13;2M^[[<65;13;2M]' ] ||
  report_failure "the child read '${GOT}', expected 'pd-mouse-got-c 22 [^[[<64;13;2M^[[<65;13;2M]'"
LIFTED="$(grep -a 'terminal: scroll>' "$LOG" | tail -n "+$((SCROLLS_N + 1))" | tr -d '\r' |
  perl -ne 'print if /total=(\d+) offset=(\d+) len=(\d+)/ and $1 - $3 != $2')"
[ -z "$LIFTED" ] ||
  report_failure "a reported wheel also moved our scrollback: $(sed -n 1p <<<"$LIFTED")"
echo "wheel: ${GOT}"

# ── 검사 29: Shift를 누르면 자식이 원해도 우리 선택이다 ──────────────────
#
# 프로브의 ready 줄(pd-mouse-ready-s)의 0열에서 7열까지 Shift를 누른 채 끈다.
# 우리 제스처가 돌아 pd-mouse 여덟 글자가 클립보드에 들어가고, 자식은 아무것도
# 못 받는다 — 프로브가 6초를 기다려 0을 찍는다. Shift를 안 보면(mutation 2)
# 자식이 그 누름을 받고 클립보드는 그대로다.
#
# HMP sendkey의 마지막 수는 누르고 있는 시간(ms)이다. QEMU는 키를 뗄 때까지 다음
# 키를 큐에 두지만 마우스는 큐를 안 거친다 — 그 3초 안에 누르고 끌고 뗀다. 뒤의
# type_keys는 그 큐 뒤에 서므로 Shift가 떨어진 다음에 간다.
echo "=== boot B: Shift takes the drag back from a child that wants the mouse ==="
CLIPS_BEFORE="$(clip_lines)"
REPORTS_BEFORE="$(report_count)"
probe_start s 10 6 1000 1006 || report_failure "the probe never printed pd-mouse-ready-s"
ROW="$(screen_row pd-mouse-ready-s)"
[ "$ROW" -ge 0 ] || report_failure "no screen row is exactly pd-mouse-ready-s"
move_to "$(( $(cell_x 0) + 3 ))" "$(( $(cell_y "$ROW") + 7 ))" ||
  report_failure "the pointer did not reach the ready line (last at: '$(last_at)')"
echo "sendkey shift 3000" >&3
sleep 0.3
button_down || report_failure "a Shift-press in mode 1000 printed no 'pointer> press' line (last report: '$(last_report)')"
[ "$(last_press)" = "terminal: pointer> press leaf=0 row=${ROW} col=0" ] ||
  report_failure "the Shift-press printed '$(last_press)', expected 'press leaf=0 row=${ROW} col=0'"
move_to "$(( $(cell_x 7) + 3 ))" "$(( $(cell_y "$ROW") + 7 ))" ||
  report_failure "the Shift-drag did not reach column 7 (last at: '$(last_at)')"
button_up || report_failure "the Shift-release printed no 'pointer> release' line"
wait_for_count clip_lines '' "$((CLIPS_BEFORE + 1))" ||
  report_failure "a Shift-drag over a child in mode 1000 put nothing on the clipboard (last report: '$(last_report)')"
[ "$(last_clip)" = "terminal: clip> len=8 text=pd-mouse" ] ||
  report_failure "the Shift-drag copied '$(last_clip)', expected 'clip> len=8 text=pd-mouse'"
GOT="$(probe_result s)"
[ "$GOT" = 'pd-mouse-got-s 0 []' ] ||
  report_failure "the child read '${GOT}' during a Shift-drag, expected 'pd-mouse-got-s 0 []'"
[ "$(report_count)" -eq "$REPORTS_BEFORE" ] ||
  report_failure "a Shift-drag was reported to the child: '$(last_report)'"
echo "shift: $(last_clip), ${GOT}"

# ── 검사 30: 대체 화면의 휠은 화살표 키다(모드 1007) ────────────────────
#
# 프로브가 1049로 대체 화면에 들어간다. 마우스 모드는 안 켠다. 1007은 기본이
# 켜짐이라 휠 위로 한 눈금이 ESC[A 세 번이다(WHEEL_ROWS). report 줄은 n=3으로
# 한 줄이다. 1007을 안 보면(mutation 4) 우리 스크롤이 되고 대체 화면에는
# 스크롤백이 없어 아무 일도 없다 — 프로브는 0을 찍는다.
echo "=== boot B: the wheel on the alternate screen is arrow keys ==="
probe_start k 9 8 1049 || report_failure "the probe never printed pd-mouse-ready-k"
N="$(report_count)"
hmp "mouse_move 0 0 1"
wait_for_count report_count '' "$((N + 1))" ||
  report_failure "a wheel notch on the alternate screen printed no 'pointer> report' line"
[ "$(last_report)" = 'terminal: pointer> report leaf=0 n=3 text=^[[A' ] ||
  report_failure "the wheel on the alternate screen was sent as '$(last_report)', expected 'report leaf=0 n=3 text=^[[A'"
GOT="$(probe_result k)"
[ "$GOT" = 'pd-mouse-got-k 9 [^[[A^[[A^[[A]' ] ||
  report_failure "the child read '${GOT}', expected 'pd-mouse-got-k 9 [^[[A^[[A^[[A]'"
echo "alternate: ${GOT}"

# ── 검사 31: vim이 시스템 vimrc의 mouse=a로 클릭을 받는다 ───────────────
#
# 서른 줄 파일을 열고 4행 9열을 누른다. 줄 번호 칸이 넷(numberwidth)이라 9열은
# 글자로 5열이고 4행은 5번째 줄이다 — vim의 상태 줄 위치가 1:1에서 5:6이 된다.
# 이 검사가 vimrc의 두 줄(mouse=a · ttymouse=sgr)과 실제 프로그램을 본다.
# vim이 무슨 모드를 켜는지(1000이냐 1002냐)는 안 본다. report 줄의 SGR 모양만
# 본다.
echo "=== boot B: vim takes a click through mouse=a ==="
type_cmd "vim /config/pd/lines"
wait_for_screen 'unix  1:1 ' || report_failure "vim did not open /config/pd/lines at 1:1"
move_to "$(( $(cell_x 9) + 3 ))" "$(( $(cell_y 4) + 7 ))" ||
  report_failure "the pointer did not reach row 4 column 9 (last at: '$(last_at)')"
report_button 1 || report_failure "vim did not turn on mouse reporting (a press printed no 'pointer> report' line, last press: '$(last_press)')"
[ "$(last_report)" = 'terminal: pointer> report leaf=0 n=1 text=^[[<0;10;5M' ] ||
  report_failure "the press in vim was reported as '$(last_report)', expected 'report leaf=0 n=1 text=^[[<0;10;5M' (ttymouse=sgr)"
report_button 0 || report_failure "the release in vim printed no 'pointer> report' line"
wait_for_screen 'unix  5:6 ' || report_failure "vim did not move its cursor to 5:6 after the click"
# vim이 끝나기 전에 친 글자는 vim이 먹는다. 주 화면이 돌아와 vim을 친 명령줄이
# 다시 보이면 끝난 것이다 — 그 줄은 vim이 도는 동안(대체 화면)에는 안 보인다.
SCREENS_N="$(screen_lines)"
type_keys shift-semicolon q ret
wait_for_new_screen "$SCREENS_N" '\| root@\(none\) ~# vim /config/pd/lines \|' ||
  report_failure "vim did not quit back to the shell after :q"
echo "vim: clicked to 5:6"

# ── 검사 32: 포커스가 아닌 패널을 누르면 포커스가 옮겨 간 뒤 그 패널이 받는다 ──
#
# Cmd+D로 가르면 포커스가 새 패널(1)에 있다. 거기서 프로브를 띄우고 Cmd+[로
# 포커스를 0에 돌린 뒤, 1의 1행 2열(격자 80열)을 누르고 뗀다. 포커스가 1로
# 옮겨 가고(tmux의 기본과 같다), 보고의 좌표는 그 패널 안의 칸 3;2다. 격자의
# 원점으로 재면(mutation 3) 80열이 77열 패널의 오른쪽 밖이 되고, 인코더가 밖에서의
# 누름을 버려 report 줄이 안 나온다.
echo "=== boot B: a press on another pane moves the focus, then reports to it ==="
SCREENS_N="$(screen_lines)"
type_keys meta_l-d
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=1 rect=78,0 77x47 ' ||
  report_failure "Cmd+D did not give 'panes=2 focus=1 rect=78,0 77x47' (last pane> line: '$(last_pane_line)')"
# 새 셸의 프롬프트가 그 패널의 첫 줄에 보일 때까지. 그 전에 친 글자는 fish가
# 시작하며 버릴 수 있다. wait_for_screen은 로그 전체를 보므로 옛 프롬프트에
# 맞는다 — Cmd+D 뒤의 screen> 줄만 본다.
wait_for_new_screen "$SCREENS_N" 'terminal: screen> root@\(none\) ~#' ||
  report_failure "the new pane never showed a prompt on its first row"
probe_start p 18 10 1000 1006 || report_failure "the probe never printed pd-mouse-ready-p in the right pane"
type_keys meta_l-bracket_left
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=0 rect=0,0 77x47 ' ||
  report_failure "Cmd+[ did not move the focus to the left pane (last pane> line: '$(last_pane_line)')"
move_to "$(( $(cell_x 80) + 3 ))" "$CY" ||
  report_failure "the pointer did not reach the right pane's row 1 column 2 (last at: '$(last_at)')"
report_button 1 || report_failure "a press on the unfocused pane with mode 1000 printed no 'pointer> report' line"
[ "$(last_report)" = 'terminal: pointer> report leaf=1 n=1 text=^[[<0;3;2M' ] ||
  report_failure "the press was reported as '$(last_report)', expected 'report leaf=1 n=1 text=^[[<0;3;2M' (cells count from the pane, not the grid)"
wait_for_pane '^terminal: pane> ws=1/1 panes=2 focus=1 rect=78,0 77x47 ' ||
  report_failure "the press did not move the focus to the right pane (last pane> line: '$(last_pane_line)')"
report_button 0 || report_failure "the release on the right pane printed no 'pointer> report' line"
GOT="$(probe_result p)"
[ "$GOT" = 'pd-mouse-got-p 18 [^[[<0;3;2M^[[<0;3;2m]' ] ||
  report_failure "the child in the right pane read '${GOT}', expected 'pd-mouse-got-p 18 [^[[<0;3;2M^[[<0;3;2m]'"
echo "panes: ${GOT}, $(last_pane_line)"
```

C7 — `old_string`(기준 파일 1335줄부터):

```bash
echo "PD-M3 check PASS"
```

`new_string`:

```bash
echo "PD-M4 check PASS"
```

### 5-2. `check.sh` — 문단과 `CHAINS`

K1 — `old_string`(기준 파일 328줄부터):

```bash
# PS/2 마우스를 잡는다. 부팅 전에 커널의 터치패드 심볼과 장치 표를 본다.
```

`new_string`:

```bash
# PS/2 마우스를 잡는다. 부팅 전에 커널의 터치패드 심볼과 장치 표를 본다.
# PD-M4가 부팅 B에 마우스 보고를 더했다 — 설정 디스크의 프로브가 마우스 모드를
# 켜고 terminal이 보낸 바이트를 cat -v로 찍고, vim이 mouse=a로 클릭을 받는다.
```

K2 — `old_string`(기준 파일 352줄부터):

```bash
  "PD-M3:./pointer/check.sh"
```

`new_string`:

```bash
  "PD-M4:./pointer/check.sh"
```

### 5-3. 확인

```bash
bash -n pointer/check.sh && echo SYNTAX-OK
bash -n check.sh && echo ROOT-SYNTAX-OK
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./pointer/check.sh && require_no_early_exit_pipe ./pointer/check.sh &&
  require_explicit_nic ./pointer/check.sh && require_no_early_exit_pipe ./check.sh && echo ENTRY-OK'
diff pointer/check.sh /tmp/run/pdm4/new/pointer/check.sh && echo SAME
diff check.sh /tmp/run/pdm4/new/check.sh && echo SAME-root
python3 /tmp/run/pdm4/anchors.py post "$PWD"
```

기대: `SYNTAX-OK` · `ROOT-SYNTAX-OK` · `ENTRY-OK` · `SAME` · `SAME-root` · `post: 33 edits, 0 bad`.

## Task 6: 체인 한 번과 regression

체인은 하나씩 돈다. 전부 같은 `kernel/initrd.cpio`를 다시 만들고, VM의 메모리가 4GB다.

### 6-1. `pointer` 체인

```bash
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm4:/tmp/run/pdm4 -w /workspace tars-devcontainer bash -c '
    bash pointer/check.sh > /tmp/run/pdm4/impl/pointer.log 2>&1; echo "exit=$?"' ; } 2>&1 | tail -4
rg -a -n '^=== boot B: (mode|the wheel|Shift|vim|a press on another)|^FAIL|^1000|^1002|^wheel: pd|^shift|^alternate|^vim|^panes|PD-M4 check' /tmp/run/pdm4/impl/pointer.log
```

기대: `exit=0`. `rg`는 이렇다(사본의 판).

```
=== boot B: mode 1000 gets the press and the release, not the drag ===
1000: pd-mouse-got-a 20 [^[[<0;11;2M^[[<0;13;2m]
=== boot B: mode 1002 also gets the drag ===
1002: pd-mouse-got-b 31 [^[[<0;11;2M^[[<32;13;2M^[[<0;13;2m]
=== boot B: the wheel over a pane in mode 1000 is buttons 4 and 5 ===
wheel: pd-mouse-got-c 22 [^[[<64;13;2M^[[<65;13;2M]
=== boot B: Shift takes the drag back from a child that wants the mouse ===
shift: terminal: clip> len=8 text=pd-mouse, pd-mouse-got-s 0 []
=== boot B: the wheel on the alternate screen is arrow keys ===
alternate: pd-mouse-got-k 9 [^[[A^[[A^[[A]
=== boot B: vim takes a click through mouse=a ===
vim: clicked to 5:6
=== boot B: a press on another pane moves the focus, then reports to it ===
panes: pd-mouse-got-p 18 [^[[<0;3;2M^[[<0;3;2m], terminal: pane> ws=1/1 panes=2 focus=1 rect=78,0 77x47 sep ink=6016
PD-M4 check PASS
```

체인 끝의 `boot B pointer> lines:` 목록에 `report` 줄 열둘이 섞여 있다(검사 26 둘 · 27 셋 · 28 둘 · 29 없음 · 30 하나 · 31 둘 ·
32 둘). vim은 버튼 없는 움직임을 안 받는 모드를 켠다 — 포인터를 vim 위로 옮기는 동안 줄이 안 생긴다.
빨개지면 `report_failure`가 찍는 표식과 마지막 40줄을 그대로 보고한다.

### 6-2. regression — `render` · `copy` · `config` · `tools`

vimrc가 바뀌어 vim을 쓰는 체인 넷이다(확정 11). 한 컨테이너에서 차례로 돈다. 약 8분 반이다.

```bash
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm4:/tmp/run/pdm4 -w /workspace tars-devcontainer bash -c '
    for c in render copy config tools; do s=$(date +%s); bash $c/check.sh > /tmp/run/pdm4/impl/reg_$c.log 2>&1
      echo "$c exit=$? $(( $(date +%s) - s ))s"; done' ; } 2>&1 | tail -6
```

기대: 넷 다 `exit=0`. 사본에서는 109 · 172 · 164 · 61초였다.

## Task 7: mutation 넷

확정 12의 표다. 사본은 `/tmp/run/pdm4/impl/mut/`에 만든다. 돌리기 전에 `diff`로 편집이 정확히 한 줄 들어갔는지 본다 —
`sd -F`가 빗나가도 에러가 없다. 한 줄이 아니면 돌리지 말고 보고한다.

### 7-0. 사본을 만든다

```bash
M=/tmp/run/pdm4/impl/mut; mkdir -p $M
for i in 1 2 3 4; do cp terminal/src/main.zig $M/main_m$i.zig; done
sd -F '            .wants = p.screen.mouseWanted(),' '            .wants = false,' $M/main_m1.zig
sd -F '        const owner = self.grab.press(e.button, self.paneAt(e.x, e.y), self.mods.shift);' '        const owner = self.grab.press(e.button, self.paneAt(e.x, e.y), false);' $M/main_m2.zig
sd -F '        const o = paneOrigin(rs[leaf]);' '        const o = paneOrigin(self.whole);' $M/main_m3.zig
sd -F '            .alt_keys = p.screen.wheelKeys(),' '            .alt_keys = false,' $M/main_m4.zig
bash -c 'for i in 1 2 3 4; do echo "== m$i"; diff terminal/src/main.zig /tmp/run/pdm4/impl/mut/main_m$i.zig; done'
```

기대: 네 `diff`가 각각 한 줄의 차이다. 넷 다 그 변수가 다른 자리에서도 쓰이므로 안 쓰는 변수의 컴파일 에러가 안 난다.

### 7-1. 체인 넷

호스트 검사를 건너뛸 필요가 없다 — 넷 다 배선의 고장이라 `zig build test`가 지난다. `-e m=$m`으로 번호를 컨테이너에
넘긴다(PE-M1 실측 5). 캐시 삭제는 같은 `docker run` 안에서 한다(`project_zig_out_staleness`).

```bash
bash -c 'cd /Users/dp/Repository/tars-linux
for m in 1 2 3 4; do
  echo "== mutation $m"
  { time docker run --rm -v "$PWD":/workspace -v /tmp/run/pdm4:/tmp/run/pdm4 \
      -v /tmp/run/pdm4/impl/mut/main_m$m.zig:/workspace/terminal/src/main.zig:ro -e m=$m \
      -w /workspace tars-devcontainer bash -c "
    echo \"mounted: m1=\$(grep -c \"            .wants = false,\" terminal/src/main.zig) m2=\$(grep -c \"self.paneAt(e.x, e.y), false);\" terminal/src/main.zig) m3=\$(grep -c \"paneOrigin(self.whole);\" terminal/src/main.zig) m4=\$(grep -c \"            .alt_keys = false,\" terminal/src/main.zig)\"
    rm -rf terminal/.zig-cache terminal/zig-out
    bash pointer/check.sh > /tmp/run/pdm4/impl/mut/m\$m.log 2>&1; echo \"exit=\$?\"" ; } 2>&1 | tail -6
  rg -a -n "^===|^FAIL" /tmp/run/pdm4/impl/mut/m$m.log | tail -2
done'
```

로그에 `Killed`가 보이고 `FAIL: terminal build failed`로 끝나면 mutation의 결과가 아니라 메모리다 — 다른 컨테이너가 없는지
보고 그 판만 다시 돈다.

기대(확정 12에서 본 그대로). `mounted:`는 그 번호 자리만 1이다.

| mutation | `mounted:` | 어디서 빨개지나 | `FAIL` 줄 |
|---|---|---|---|
| 1 | `m1=1 m2=0 m3=0 m4=0` | 검사 26 | `FAIL: a press in a pane with mode 1000 printed no 'pointer> report' line (last press: 'terminal: pointer> press leaf=0 row=1 col=10')` |
| 2 | `m1=0 m2=1 m3=0 m4=0` | 검사 29 | `FAIL: a Shift-press in mode 1000 printed no 'pointer> press' line (last report: 'terminal: pointer> report leaf=0 n=1 text=^[[<0;1;46M')` — 행 46은 그 판의 ready 줄 자리라 달라도 된다 |
| 3 | `m1=0 m2=0 m3=1 m4=0` | 검사 32 | `FAIL: a press on the unfocused pane with mode 1000 printed no 'pointer> report' line` |
| 4 | `m1=0 m2=0 m3=0 m4=1` | 검사 30 | `FAIL: a wheel notch on the alternate screen printed no 'pointer> report' line` |

판마다 2분 10초~2분 40초다(터미널을 다시 빌드한다).

mutation이 예상과 다른 자리에서 죽거나 초록이면 그대로 적어 보고한다. 초록이면 먼저 바이너리를 의심한다
(`project_zig_out_staleness` — 캐시 삭제가 같은 `docker run` 안에 있었는지, `mounted:`가 1이었는지).

### 7-2. 되돌린다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf terminal/.zig-cache terminal/zig-out
  (cd terminal && ./prepare.sh > /tmp/p.out 2>&1 && zig build test > /tmp/t.out 2>&1); echo "exit=$?"
  grep -a -c "^pointer_test: .* OK$" /tmp/t.out
  (cd kernel && ./make_initrd.sh > /tmp/i.out 2>&1); echo "initrd exit=$?"'
git status --short
```

기대: `exit=0`, `pointer_test` OK 140, `initrd exit=0`. `git status`는 `M` 열하나(`check.sh` · GE design · `kernel/vim/vimrc` ·
`pointer/check.sh` · `terminal/src/`의 일곱)이고, plan과 PD design이 commit 전이면 그 둘이 더 있다. 다른 것이 보이면(특히 `-v`로
없는 파일을 덮어 Docker가 만든 0바이트 파일) 그 목록을 보고한다.

### 7-3. 보고

- `git diff --stat`(전체)과 `git diff | rg '^-'`(전체).
- Task 0의 출력.
- Task 1~5의 확인 출력(`SAME` · OK 줄 수 · `ENTRY-OK` · `anchors.py`).
- Task 6의 `exit=` · `real` · `rg` 출력과 regression 넷의 줄.
- Task 7의 `diff` 넷 · `mounted:` · `exit=` · `real` · `FAIL` 줄, 7-2의 출력.
- plan의 기대와 글자나 수가 다른 것이 있으면 그 줄을 그대로.

## Task 8: lead가 하는 것

1. 보고를 받아 diff를 직접 읽고, 파일 전부를 이 plan의 사본(`/tmp/run/pdm4/new/`)과 `cmp`한다. Task 6의 로그를 대조한다.
2. 루트 게이트 2회(`feedback_gate_runs`), 열아홉 체인 × 2다. 판정은 `PASS: 2/2` × 19와 `PD-M4 check PASS` 둘이다. 커널을 안
   바꾸므로 첫 체인이 커널 전체 빌드를 치르는 것은 PD-M3과 같다(`clean()`이 `kernel/build`를 지운다). PD-M3의 49분 29초에
   `pointer` 체인의 증가분(확정 10) 두 판을 더한 것으로 본다. `run_in_background`로 돌리고 `{ time …; }`로 감싼다. 다른
   컨테이너와 겹치지 않는다.

   ```bash
   { time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh > /tmp/gate_pd4.log 2>&1 ; echo "exit=$?" ; } 2> /tmp/gate_pd4.time
   ```

   완료 알림이 오면 `pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 보고 판정한다.
   `rg -c 'PASS: 2/2' /tmp/gate_pd4.log`가 19, `rg -c 'PD-M4 check PASS' /tmp/gate_pd4.log`가 2여야 한다.
3. 실측 절 채우기.
4. commit. 넣는 것은 `terminal/src/pointer.zig` · `pointer_test.zig` · `vt.zig` · `vt_test.zig` · `input.zig` · `input_test.zig` ·
   `main.zig` · `kernel/vim/vimrc` · GE design · `pointer/check.sh` · `check.sh` · 이 plan이고, design이 commit 전이면 함께 넣는다.
   `git add`는 경로를 하나씩 지정한다.
5. 닫기. 아래 "닫을 때"의 목록이다. 서브프로젝트를 닫는 commit은 PD-M4 commit과 따로 만든다.

## 닫을 때

PD는 PD-M3에서 한 번 닫았고(`15cc760`) PD-M4를 위해 다시 열었다(`1050b6f`). 닫을 때 고칠 것은 PD-M3 때의 목록 가운데 M4가
바꾼 것이다.

1. PD design의 `Status:`를 `끝났다(날짜, PD-M0~M4)`로 고친다. "다시 열었다" 줄은 지우지 않고 한 줄로 줄인다. 결정 3 · 7 · 10에
   아래 "design과 다르게 적은 것"의 넷을 한 줄씩 덧붙인다. 비목표 1의 괄호는 그대로다.
2. `CLAUDE.md`의 완료 표에서 Pointer Devices 줄을 고친다 — milestone이 `PD-M0~M4`이고, "무엇이 섰나" 칸에 "자식이 마우스를
   원하면 보고하고 Shift를 누른 끌기는 우리 선택"을 더한다. 끝난 날을 고친다.
3. `docs/decisions/project_pointer_devices.md`에 PD-M4 절. 담을 것 — 인코더는 ghostty의 것이고 우리 몫은 주인 · 패널 · 좌표 ·
   쓰기다, 주인은 첫 누름이 정하고 마지막 뗌까지(`Grab`과 `settle`), Shift와 copy mode가 우리 것, 휠의 순서와 1007의 기본값,
   프로브의 방식(설정 디스크 · `read -N`), `sendkey shift N`으로 Shift를 누른 채 두는 법. `MEMORY.md`의 한 줄을 고친다.
4. 다시 연 결정. GE design 원칙 3은 Task 4-2가 이미 덧붙였다. CM design · WP design의 비목표에 "마우스 보고"가 있으면
   PD-M4가 했다고 덧붙인다(`rg -n '마우스 보고|mouse report' docs/specs/`로 찾는다).
5. `docs/guides/running-tars.md`. 쓰는 법에 한 단락 — vim · fzf 안에서 클릭 · 휠이 그 프로그램으로 가고, 우리 선택은 Shift를
   누른 끌기다. vim에서 돌려받으려면 `/.vimrc`에 `set mouse=`.
6. `docs/guides/lessons.md`. 이월 숙제에서 비목표 1(마우스 보고)을 지우고 design 비목표 14~18 중 다음 후보(OSC 52 · 포커스
   보고)를 적는다. 게이트 요령 셋 — `scroll>` 줄은 출력으로도 찍힌다(값을 본다), `wait_for_screen`은 로그 전체를 본다(새
   화면만 보려면 `wait_for_new_screen`), vim이 끝나기 전에 친 글자는 vim이 먹는다(확정 9). 그리고 HMP `sendkey 키 ms`로 수정키를
   누른 채 두는 법(확정 8).
7. `HANDOFF.md`.

## design과 다르게 적은 것

design 결정 12는 이 plan과 같은 날 함께 썼고, 이 plan이 사본에서 잰 것을 반영했다. 결정 12와 다른 것은 없다. 앞 결정과
달라지는 것은 아래 넷이고, lead가 닫을 때 그 결정에 한 줄씩 덧붙인다.

1. 결정 3의 층 그림에 `Grab`이 들어간다. `Gesture`는 우리 것인 왼쪽 버튼만 받고, 누름의 주인은 그 앞에서 `Grab`이 가른다.
2. 결정 7의 휠 표("포인터 아래 패널이 세 줄")는 그 패널의 자식이 마우스를 안 원하고 대체 화면의 1007도 아닐 때의 갈래가
   됐다. 끄는 중의 휠은 그대로 맨 앞이다.
3. 결정 10의 로그 줄에 `report`가 더해진다. PD-M2 plan이 왼쪽 버튼만 담던 회차의 전이 칸이 버튼 셋을 담는다.
4. 결정 10의 검사 표가 25에서 끝나고 26~32는 결정 12의 표에 있다. 부팅 B의 설정 디스크에 `tp-replay` · `drivers` 말고
   `mouse` · `lines`가 실린다.

## 이 milestone에서 안 하는 것

- 포커스 보고(모드 1004) · XTSHIFTESCAPE · OSC 52 · 가로 휠과 포인터 모양 · 보고를 끄는 설정(design 비목표 14~18).
- 자식이 모드를 켠 채 죽었을 때 셸이 모드를 끄게 하기(design 위험 9). seed rc의 몫이다.
- 우리 것인 오른쪽 · 가운데 버튼(design 비목표 8). 자식의 것이면 이제 보고로 간다.
- 1005 · 1015 · 1016 형식의 게이트. 인코더의 몫이고 `vt_test`는 SGR과 X10만 본다.
- 1003(버튼 없는 움직임)의 게이트. 배선은 `moved`의 갈래 하나이고 `vt_test` 검사 104가 인코더 쪽을 본다. 게이트로 보려면
  움직임마다 보고 줄이 생기는 것을 세야 해서 판정이 무겁다.
- 실기 확인. 터치패드의 탭 · 두 손가락 스크롤이 자식에게 버튼과 휠로 가는지는 PD-M3의 번역을 지나 같은 `Frame`이 되므로
  같은 길이다. 사람이 실기에서 vim을 띄워 본다.

## PD-M4가 실측한 것

구현은 Opus 서브에이전트가 2026-10-05에 plan 그대로 했다. 편집 서른셋을 plan 본문에서 뽑아(`anchors.json`과 글자가 같았다)
정확 치환(각 1회)으로 넣었고, Task마다 사본 `new/`와 `SAME`, `anchors.py post` 33 edits, 0 bad. lead가 파일 열하나 ·
`check.sh` · vimrc · GE design을 사본과 `cmp`해 전부 같음을 봤다. plan 코드를 고친 곳은 없다.

1. 호스트 검사. `pointer_test` OK 107 → 140, `vt_test` 78 → 82, `input_test` 15 → 16. 지운 줄은 전부 plan의 `old_string`
   안이고 PD design에서는 한 줄도 안 지워졌다.
2. `pointer` 체인 1분 14초(plan 73초). 검사 26~32의 `rg` 출력이 plan의 기대 블록과 글자까지 같다. `report` 줄 열둘(leaf=0 열 ·
   leaf=1 둘), `^[[A` 세 번(`n=3`) 하나. 확정 14의 흔들림(`seq 200`)은 이번에는 없었다.
3. regression — `render` 108초 · `copy` 171초 · `config` 163초 · `tools` 59초, 넷 다 PASS(합 8분 22초). `config`의 `vim -T dumb`
   에러 음성 검사가 `mouse=a ttymouse=sgr`로도 지났다.
4. mutation 넷 전부 빨감, `Killed` 0번.

   | mutation | 잡은 자리 | 문구 | 시간 |
   |---|---|---|---|
   | 1 모드를 무시하고 보고하지 않는다 | 검사 26 | `a press in a pane with mode 1000 printed no 'pointer> report' line` | 2분 21초 |
   | 2 Shift를 무시한다 | 검사 29 | `a Shift-press in mode 1000 printed no 'pointer> press' line (last report: '… text=^[[<0;1;46M')` | 2분 28초 |
   | 3 격자 원점을 패널 원점으로 쓴다 | 검사 32 | `a press on the unfocused pane with mode 1000 printed no 'pointer> report' line` | 2분 44초 |
   | 4 모드 1007을 무시한다 | 검사 30 | `a wheel notch on the alternate screen printed no 'pointer> report' line` | 2분 35초 |

5. plan의 기대와 다른 것은 없었다 — 구현자가 Edit 도구 대신 plan에서 뽑은 쌍을 스크립트로 넣은 것(글자는 같다)과 시간 몇 초뿐.
6. 루트 게이트(2회): 열아홉 체인 2/2, `PD-M4 check PASS` 둘, `FAIL` 0줄, 49분 56초(2026-10-05, docker 작업 없이 단독).
   `install` 부팅 7은 `init waited 1100ms` 둘. PD-M3의 49분 29초에서 27초 늘었다(`pointer` 체인 검사 일곱 × 2회).
