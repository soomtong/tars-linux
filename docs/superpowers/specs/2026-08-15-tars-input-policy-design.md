# TARS Input Policy — Design

**Date:** 2026-08-15
**Status:** 설계 완료, IP-M0 착수 대기

## 배경

Config Persistence(CP-M0~M2)가 2026-08-15에 끝나면서 진행 중인 서브프로젝트가
없어졌다. 최종 비전에서 아직 손대지 않은 후보 중 **입력 정책(Input
Policy)** 을 다음으로 골랐다.

고른 이유는 세 가지다.

1. **이 프로젝트의 원래 동기다.** Boot Foundation design doc의 "배경"이
   나열한 최종 비전 첫 항목이 "macOS 키바인딩 의미론"이다. 그런데 지금
   TARS의 키보드는 Shift 하나만 아는 상태로 멈춰 있다.
2. **지금 만든 것 위에 바로 얹힌다.** 새 커널 옵션도, 새 장치도, 새
   외부 의존도 필요 없다. 이미 열려 있는 evdev fd에서 이미 읽고 있는
   이벤트를 **다르게 해석**하는 일이다.
3. **QEMU 안에서 게이트로 증명할 수 있다.** CP-M2가 monitor `sendkey`로
   게스트 셸에 직접 타이핑하는 길을 이미 뚫어놨다.

Terminal Foundation design doc(2026-08-08)의 6번 결정이 입력 처리에 세
조각이 필요하다고 적어두고, 마지막 문단을 이렇게 끝냈다:

> 단, 이 dispatch 테이블은 Terminal Foundation 자체 기능(탭 전환 등)을 위한
> 하드코딩된 작은 테이블이지, 사용자가 임의로 키를 재배치하는 범용
> 키바인딩 엔진이 아니다 — 그건 최종 비전의 별도 "input policy"
> 서브프로젝트 몫으로 남는다.

이 문서가 그 자리다. 다만 "범용 키바인딩 엔진"은 이번에도 만들지 않는다
(아래 비목표 참고).

### 출발 시점의 저장소 상태 (2026-08-15 실측)

`terminal/src/input.zig`는 148줄이고, 다음이 전부다.

- **keymap 테이블이 evdev 코드 57(`KEY_SPACE`)에서 끝난다.** 방향키
  (103/105/106/108), Home/End(102/107), Delete(111), PageUp/Down(104/109),
  F1~F12(59~88)는 배열 밖이라 `code >= keymap.len`에서 걸러진다.
- **`State`가 아는 modifier는 Shift 둘뿐이다** (`shift_left`,
  `shift_right`). 29번(`KEY_LEFTCTRL`)과 56번(`KEY_LEFTALT`)은 테이블에
  `.{ 0, 0 }`로 자리만 있고 주석에 "이번 범위 밖"이라고 적혀 있다.
- **`handleKey`의 반환 타입이 `?u8`이다.** 키 하나가 바이트 하나가 된다.

세 번째가 나머지 둘의 원인이다. 터미널에서 ←는 `ESC [ D` 3바이트이므로
**한 바이트만 돌려줄 수 있는 함수로는 방향키를 표현할 수 없다.** 표를
늘리는 것으로는 해결되지 않는다.

부수적으로, Ctrl+C가 지금 동작하지 않는 이유도 여기서 설명된다. 시그널을
우리가 보내야 해서가 아니라, `0x03` 바이트가 **만들어지지 않아서**다
(아래 3번 결정).

### 사용자가 정한 범위 (2026-08-15)

- **"다 됐다"의 기준:** 터미널 기본기(Ctrl 제어 문자, 특수키, terminfo)를
  깔고 **그 위에 macOS 편집 의미론까지** 올린다. 설정 파일로 키를 임의
  재배치하는 범용 엔진은 이번이 아니다.
- **물리 키보드:** Apple 키보드와 PC 키보드를 **둘 다 쓴다.** 따라서
  Alt↔Meta 보정을 코드에 박을 수 없고 스위치로 빼야 한다.

## 목표 (MVP)

부팅한 TARS의 화면 터미널에서 다음이 전부 동작한다.

1. **Ctrl 제어 문자** — `Ctrl+C`로 실행 중인 명령을 죽이고, `Ctrl+D`로
   EOF를 보내고, `Ctrl+Z`로 멈춘다.
2. **특수키** — 방향키, Home/End, Delete, PageUp/PageDown이 셸의 줄
   편집기에 제대로 전달된다.
3. **`TERM`이 진실을 말한다** — PTY 셸의 `TERM`이 `xterm`이고,
   그에 맞는 terminfo가 initrd에 있다.
4. **macOS 편집 의미론** — `Option+←/→`로 단어 단위 이동,
   `Option+Backspace`로 단어 삭제, `Cmd+←/→`로 줄 처음/끝 이동.
5. **키보드 종류를 설정으로 고른다** — `/config/tars.conf`의
   `keyboard=apple|pc`가 Alt↔Meta 보정을 켜고 끈다.

그리고 이 다섯이 **게이트로 증명된다** — 사람이 화면을 보고 판단하는
것이 아니라, `check.sh`가 QEMU monitor로 키를 보내고 화면 덤프를 검사해서
판정한다.

## 비목표

- **범용 키바인딩 엔진.** 매핑은 코드에 박힌 표다. 설정 파일에서 읽는 것은
  `keyboard=apple|pc` 하나뿐이며, 이건 재배치가 아니라 **하드웨어 종류
  선언**이다.
- **F1~F12, 키패드, Insert.** TUI 앱이 아직 하나도 없어서 누를 이유가
  없다. keymap 테이블에 넣는 비용 자체는 싸지만, 게이트가 볼 수 없는 표를
  늘리는 것은 `project_gate_chain_composition`이 경고한 것과 같은 종류의
  부채다.
- **마우스 입력.** TF design doc에서도 비목표였다.
- **CapsLock 재배치.** macOS 사용자가 흔히 Ctrl로 바꿔 쓰는 키지만, 그건
  "임의 재배치"의 문이다.
- **CSI u / modifyOtherKeys.** modifier를 명시적으로 인코딩해 넘기는 현대적
  방식이지만, 받는 쪽(zsh/bash)이 기본적으로 지원하지 않는다. TARS가 자기
  TUI 앱을 갖게 되면 그때 다시 본다.
- **`Cmd+C` / `Cmd+V` / `Cmd+↑↓`.** 복사·붙여넣기·스크롤은 스크롤백과
  클립보드가 선행 조건이라 `docs/decisions/project_copy_mode.md`의 몫이다.
  **이번에 이 조합들을 다른 용도로 쓰지 않고 비워둔다.**
- **키보드 레이아웃(비-US).** US QWERTY 하드코딩을 유지한다. 한/영 키
  처리도 CJK IME 서브프로젝트의 몫이다.
- **시리얼 콘솔 셸의 입력.** 그쪽은 커널의 tty 계층이 처리하며 우리
  코드를 지나지 않는다.

## 핵심 설계 결정

### 1. `handleKey`의 반환 타입을 `?u8`에서 `[]const u8`로

이 변경 하나에서 나머지 전부가 파생된다.

```zig
// 지금
pub fn handleKey(self: *State, code: u16, value: i32) ?u8

// 앞으로
pub fn handleKey(self: *State, code: u16, value: i32, ctx: Context) []const u8
```

빈 슬라이스가 지금의 `null`("보낼 것 없음") 자리를 대신한다. 바이트열의
저장소는 `State` 안의 고정 배열 `seq: [8]u8`이고, 반환 슬라이스는 그
배열을 가리킨다. 힙을 쓰지 않는다.

호출자 `readKeys`는 반환값을 즉시 `out`으로 복사하므로, 같은 read 배치의
다음 키가 `seq`를 덮어써도 안전하다. 8바이트인 이유는 이번 범위에서 가장
긴 시퀀스가 6바이트(`ESC [ 1 ; 5 D` 형태)이기 때문이다.

### 2. 키 하나가 지나가는 세 단계 — 순서가 곧 설계다

```
evdev fd ──poll──> readKeys ──> handleKey ──┐
                                            │  1. modifier 갱신
                                            │  2. 조합 dispatch
                                            │  3. 기본 번역
                                            └──> []const u8 ──> pty.write
```

**2번이 3번보다 먼저여야 한다.** 뒤에 두면 `Cmd+←`가 dispatch에 닿기 전에
3번에서 그냥 `←`로 번역돼 새어 나간다. "가로챌 것을 먼저 가로채고, 남은
것만 평소대로"가 규칙이다.

2번은 TF design doc 6번이 "조각 셋" 중 유일하게 비워둔 자리이며,
`project_copy_mode`의 선택 모드 진입키도 나중에 여기에 표 한 줄로 붙는다.

### 3. Ctrl+C의 시그널은 우리가 보내지 않는다

`terminal/src/pty.zig:37`이 쓰는 `forkpty`는 자식 쪽에서 `setsid` +
`TIOCSCTTY`까지 해준다. 즉 셸이 제어 터미널을 제대로 갖고 있고, PTY에는
커널의 line discipline(N_TTY)이 붙어 있다.

우리가 master fd에 `0x03` 한 바이트를 쓰면, **커널이** `ISIG`와
`VINTR == 0x03`을 보고 foreground process group에 SIGINT를 보낸다. 우리
쪽에 시그널 코드는 한 줄도 필요 없다.

Ctrl 제어 문자를 만드는 규칙은 한 줄이다: **Shift를 먼저 적용해 문자를
정한 뒤 `& 0x1F`.**

| 조합 | 문자 | 결과 | 뜻 |
|---|---|---|---|
| Ctrl+C | `c` 0x63 | `0x03` | SIGINT |
| Ctrl+D | `d` 0x64 | `0x04` | EOF |
| Ctrl+Z | `z` 0x7a | `0x1A` | SIGTSTP |
| Ctrl+`\` | `\` 0x5c | `0x1C` | SIGQUIT |
| Ctrl+`[` | `[` 0x5b | `0x1B` | ESC |
| Ctrl+Space | ` ` 0x20 | `0x00` | NUL |
| Ctrl+`_` | `_` 0x5f | `0x1F` | readline undo |

마스크가 표 전부를 설명하는 이유는 ASCII 배치 자체가 그렇기 때문이다 —
제어 문자 0x00~0x1F는 `@ABC…Z[\]^_`(0x40~0x5F)에서 상위 두 비트를 뗀
것이다.

다만 마스크는 문자가 0x40~0x7F일 때만 의미가 있다. `Ctrl+1`에 적용하면
`0x31 & 0x1F = 0x11`(XON)이 나오는데 아무도 그런 뜻으로 쓰지 않는다.
그래서 적용 대상을 **`a`~`z`, `@ [ \ ] ^ _`, Space, 그리고 예외로
`?`→`0x7F`** 로 명시적으로 한정하고, 나머지는 Ctrl을 무시하고 원래 문자를
보낸다. xterm이 하는 것과 같다.

### 4. modifier는 물리 키 하나당 비트 하나

추적할 키는 여덟이다. `KEY_LEFTSHIFT`(42)/`RIGHTSHIFT`(54),
`LEFTCTRL`(29)/`RIGHTCTRL`(97), `LEFTALT`(56)/`RIGHTALT`(100),
`LEFTMETA`(125)/`RIGHTMETA`(126).

논리 modifier는 "그 그룹에 비트가 하나라도 서 있는가"로 계산한다. 논리
상태 하나로 뭉치면 안 되는 이유는 — 왼쪽 Shift를 누른 채 오른쪽 Shift를
눌렀다 떼면 그 뗌 이벤트 하나가 논리 Shift를 통째로 꺼버리기 때문이다.
현재 코드의 `shift_left`/`shift_right` + `shifted()`가 이미 이 방식이며,
여덟으로 늘리는 것뿐이다.

### 5. DECCKM은 추측하지 않고 VT에게 물어본다

방향키는 상황에 따라 `ESC [ D`이기도 하고 `ESC O D`이기도 하다. DECCKM
(DEC Cursor Key Mode, 모드 1)이 켜졌는지에 달렸고, 그걸 켜는 것은 셸이
보내는 `ESC [ ? 1 h`다.

**그 시퀀스는 이미 우리가 파싱하고 있다.** `vt.zig`의 `Screen.feed`가
libghostty-vt에 먹이고, `terminal/ghostty-src/src/terminal/Terminal.zig:83`의
`modes` 필드가 상태를 들고 있으며,
`terminal/ghostty-src/src/terminal/modes.zig:288`에 `cursor_keys`(= 모드 1)가
있다. `screen.term.modes.get(.cursor_keys)`로 되읽으면 된다.

| 키 | DECCKM 꺼짐 | DECCKM 켜짐 |
|---|---|---|
| ↑ ↓ → ← | `ESC [ A/B/C/D` | `ESC O A/B/C/D` |
| Home / End | `ESC [ H` / `ESC [ F` | `ESC O H` / `ESC O F` |
| Delete | `ESC [ 3 ~` | 같음 |
| PageUp / PageDown | `ESC [ 5 ~` / `ESC [ 6 ~` | 같음 |

### 6. 그래도 `input.zig`는 `vt.zig`를 import 하지 않는다

DECCKM 상태가 `vt` 안에 있다고 해서 `input`이 `vt`를 직접 부르게 하지
않는다. `main.zig`가 읽어서 값으로 넘긴다.

```zig
pub const Context = struct {
    cursor_keys: bool = false,     // DECCKM. main이 modes.get(.cursor_keys)로 채운다
    swap_alt_meta: bool = false,   // PC 키보드 보정
};
```

이유가 셋이다.

1. **의존 방향이 단방향으로 유지된다.** 지금 `main.zig`만 다섯 모듈
   (`drm`/`font`/`input`/`pty`/`vt`)을 알고 그 다섯은 서로 모른다.
   `input → vt` 화살표를 그리면 이 성질이 깨지고, 다음에 `vt`가 무언가
   필요해지면 순환이 생긴다.
2. **`input_test`가 혼자 돌 수 있다.** `terminal/build.zig:61-69`의
   `input_test_mod`는 libc만 링크하고 `ghostty-vt`를 붙이지 않는다.
3. **bool 하나가 포인터보다 검증하기 쉽다.** 테스트에서
   `ctx.cursor_keys = true`로 두 형태를 다 확인할 수 있다.

대가는 `main.zig`의 루프가 매 키마다 `modes.get`을 호출한다는 것인데,
packed struct의 비트 읽기 한 번이라 값이 없다.

### 7. `TERM`이 지금 거짓말을 하고 있다

현재 PTY 셸이 보는 `TERM`은 `linux`다. 커널이 PID 1에게 주는 값
(`init/main.c`의 `envp_init`)을 init이 물려주고, `pty.zig:41`이
`execv`(환경 그대로 상속)를 쓰기 때문이다.

**그런데 PTY 셸이 말을 거는 상대는 리눅스 콘솔이 아니라
libghostty-vt다.** xterm 계열 에뮬레이터이고, `TERM=linux`와는 특수키
시퀀스가 실제로 다르다 — Home이 linux terminfo에서는 `ESC [ 1 ~`,
xterm terminfo(`khome`)에서는 `ESC O H`다. 우리가 어느 쪽을 보내든 한쪽은
틀린다.

(결정 5의 표에서 Home의 DECCKM 꺼짐 형태를 `ESC [ H`로 적은 것과 어긋나
보일 수 있는데, 어긋난 것이 아니다. xterm terminfo의 `khome`은 **DECCKM
켜짐 형태**를 등록해 두고 `smkx`로 그 모드를 켜는 구조다. 우리는 모드를
VT에서 되읽어 그때그때 맞는 쪽을 보내므로 양쪽 다 맞다.)

그래서 `terminal`이 `forkpty` 직전에 `setenv("TERM", "xterm", 1)`을
호출한다. `execv`가 환경을 상속하므로 fork 전에 고쳐두면 자식이 받는다.
**시리얼 콘솔 셸의 `TERM`은 `linux` 그대로 둔다** — 그쪽은 진짜 커널
콘솔이다. 같은 기계 안에서 두 셸의 `TERM`이 다른 것이 정상이다.

`xterm-256color`가 아니라 `xterm`인 이유는 우리가 아직 색을 한 개도 그리지
않기 때문이다(`terminal/src/main.zig:13`의 `TEXT_COLOR`가 흰색 상수 하나).
256색을 광고하면 반대 방향의 거짓말이 된다. 색상은 "터미널 완성도"
차례에 올린다.

이에 따라 initrd에 `/usr/share/terminfo/x/xterm`이 필요하다.
`ncurses-base` 패키지에 들어 있고, `project_build_host_arch`의 3번
규칙대로 `devcontainer/Dockerfile`의 **아래쪽** `apt-get download :amd64`
목록에 추가해야 한다(`ncurses-base`는 arch: all이다).

이것으로 HANDOFF의 "`TERM`/terminfo — 절반만 닫혔다" 숙제가 닫힌다.

### 8. macOS 의미론은 "셸이 이미 아는 언어"로 번역한다

`Option+←`를 눌렀을 때 PTY에 무슨 바이트를 흘려보낼 것인가. 셋을
검토했다.

- **A안 — 셸이 이미 아는 제어 코드/시퀀스로 번역한다.** `Cmd+←` →
  `0x01`(Ctrl+A) 같은 식. readline·zle·fish가 전부 기본값으로 아는
  것들이라 설정 없이 동작한다.
- **B안 — 표준 특수키 시퀀스를 보내고 셸 쪽에 바인딩을 심는다.** 더
  "정직"하지만 셸마다 설정 파일이 세 벌 생기고, 게이트가
  `--no-config`/`--norc`/`-f`로 도는 현재 구조와 정면 충돌한다. 그
  플래그는 프롬프트를 예측 가능하게 만들려고 일부러 넣은 것이라 뺄 수
  없다.
- **C안 — CSI u / modifyOtherKeys로 modifier를 인코딩해 넘긴다.** 애매함이
  없는 현대적 방식이지만 받는 쪽이 지원해야 의미가 있다.

**A안을 고른다. 결정적인 이유는 검증이다** — A안만이 "설정 파일 없는 셸
모두에서 즉시 동작"하고, 그건 곧 게이트가 화면 덤프로 증명할 수 있다는
뜻이다. B안의 검증은 우리가 심은 설정을 검증하는 자기충족이 되고, C안은
검증할 수신자가 없다.

| 조합 | 보내는 바이트 | readline / zle / fish에서의 뜻 |
|---|---|---|
| Option+← | `ESC b` | backward-word |
| Option+→ | `ESC f` | forward-word |
| Option+Backspace | `ESC 0x7F` | backward-kill-word |
| Option+Delete | `ESC d` | kill-word |
| Cmd+← | `0x01` | beginning-of-line |
| Cmd+→ | `0x05` | end-of-line |
| Cmd+Backspace | `0x15` | 줄 앞부분 삭제 |

**알고 들어가는 어긋남 하나:** `0x15`(Ctrl+U)가 bash에서는 커서 앞까지만
지우지만(`unix-line-discard`), zsh에서는 줄 전체를 지운다
(`kill-whole-line`). macOS의 Cmd+Backspace는 bash 쪽 동작이다. 셸을 바꿔
끼울 수 있는 시스템에서 이런 어긋남은 A안을 고른 대가이며, 감추지 않고
여기 적어둔다. fish의 기본 바인딩이 이 표를 어떻게 받는지는 IP-M2에서
실측하고, 어긋나는 것이 있으면 이 문서에 추가한다.

### 9. Alt ↔ Meta swap — `keyboard=apple|pc`

PC 키보드와 Apple 키보드는 스페이스 옆 두 키의 **순서가 정확히 뒤집혀**
있다.

```
Apple:  [Ctrl] [Option] [Cmd]    [Space]
         29      56      125
PC:     [Ctrl] [Win]   [Alt]     [Space]
         29     125      56
```

`keyboard=pc`일 때 하는 일은 **modifier 상태를 기록하기 전에 56↔125,
100↔126을 맞바꾸는 것**뿐이다. 파이프라인 1단계 맨 앞에서 한 번 교환하면
그 뒤 로직은 어느 키보드인지 전혀 몰라도 된다.

설정 경로는 CP가 깔아둔 길을 **한 글자도 바꾸지 않고** 그대로 쓴다.

```
/config/tars.conf ──읽는 것은 PID 1 하나뿐──> init/src/config.zig
   shell=zsh                                    Shell    enum (있음)
   keyboard=pc                                  Keyboard enum (추가)
                                                    │ argv로 흘려보낸다
                                                    ▼
   /terminal <셸 경로> <no-config 플래그> <keyboard>
```

`terminal`은 여전히 설정 파일을 읽지 않는다. CP가 "파서가 두 벌이 되면 두
프로세스가 같은 파일에서 서로 다른 답을 얻을 수 있다"는 이유로 정한
원칙이고, **이번이 그 구조가 두 번째 키에도 버티는지 보는 첫 시험이다.**

argv 셋째 자리를 쓰는 것이 안전한 이유는 `terminal/src/main.zig:116`이
셸에 넘기는 argv를 `{shell_path, shell_flag}` 둘로 따로 조립하기 때문이다
— 셋째 인자는 셸로 새지 않는다. 이름 붙은 플래그(`--keyboard=pc`) 파서는
넷째 인자가 생길 때 다시 본다.

기본값은 `apple`이고, 모르는 값이 오면 CP의 화이트리스트 원칙(= enum)대로
조용히 기본값으로 떨어진다.

### 10. 죽어 있던 테스트 바이너리 셋을 되살린다

`terminal/build.zig`는 `pty_test`/`vt_test`/`input_test` 세 실행 파일을
빌드하는데, **어느 게이트도 이것들을 실행하지 않는다.** `terminal/check.sh`는
`prepare.sh`(= `zig build`)만 부르고 끝난다. TF-M3 plan을 보면 당시엔 손으로
`./zig-out/bin/input_test`를 돌렸는데, 그때는 컨테이너가 amd64였다.
**ZM-M3에서 컨테이너를 arm64로 바꾼 뒤로는 실행 자체가 불가능하다** —
x86_64 바이너리이기 때문이다.

IP는 이 저장소에서 가장 표가 큰 작업이다. keymap 테이블, Ctrl 마스크 예외
목록, 특수키 시퀀스 표, dispatch 표 — 오타 하나가 조용히 지나갈 자리가
많다. 부팅 게이트만으로 다 덮으려면 부팅 시간이 감당되지 않는다.

해결은 `project_build_host_arch`의 4번 규칙 그대로다: **호스트에서 도는
도구는 호스트 아키텍처로 빌드한다.** `build.zig`에서 `terminal` 본체는
지금처럼 x86_64로 고정하고, `*_test` 셋만 native 타깃으로 다시 빌드한다.
컨테이너가 arm64 리눅스이므로 `@cImport("linux/input.h")`도 그대로 된다.
그리고 `terminal/check.sh`가 이 셋을 실제로 실행하게 한다.

이것이 IP-M0의 첫 Step이다. 새 기능을 얹기 전에 얹을 자리에 저울부터
놓는 것이다.

### 11. 네 번째 체인 `input/check.sh`, 부팅은 **한 번**

CP는 영속성을 증명해야 해서 QEMU를 두 번 띄웠지만, IP가 증명할 것은 전부
한 세션 안에 있다. **부팅 한 번**이면 된다.

디스크는 물리지 않는다. `/config` mount가 실패하면 CP가 만든 폴백이 fish로
떨어뜨려 주므로, IP 게이트는 그 폴백 경로를 덤으로 한 번 더 밟는다.

CP의 `boot_once`/`type_keys` 구조를 그대로 빌려오되 monitor 포트는
**45457**을 쓴다(BF/TF 45455, CP 45456). 죽다 만 QEMU에 엉뚱한 키를 보내지
않으려는 CP의 이유가 그대로 적용된다.

체인 디렉터리가 소스 디렉터리와 다른 것은 CP의 선례와 같다 — `config/`의
체인이 검사하는 소스는 `init/`에 있다.

## Milestones

### IP-M0 — 바닥 전환과 Ctrl

- 테스트 바이너리 셋을 native 타깃으로 빌드하고 `terminal/check.sh`가
  실행하게 한다 (결정 10)
- `handleKey`를 `[]const u8` + `Context`로 전환 (결정 1)
- modifier 8키 비트마스크 (결정 4)
- Ctrl 제어 문자 (결정 3)
- **Exit gate:** `input/check.sh` 신설. `sleep 100` 실행 중 `ctrl-c`를
  보내고, 이어서 친 `echo ctrlc_ok`가 화면에 나타난다

### IP-M1 — 특수키와 `TERM`

- keymap 테이블 확장 + 특수키 → 이스케이프 시퀀스 (결정 5)
- `main.zig`가 `modes.get(.cursor_keys)`를 `Context`에 채운다 (결정 6)
- `setenv("TERM", "xterm", 1)` + `ncurses-base` terminfo를 initrd에
  (결정 7)
- **Exit gate:** `echo abc`를 친 뒤 ← ←로 커서를 옮기고 `X`를 끼워 넣어
  화면이 `echo aXbc`가 된다. `echo abcX`는 **없어야** 한다

### IP-M2 — macOS 의미론

- Option/Cmd dispatch 표 (결정 8)
- `init/src/config.zig`에 `Keyboard` enum + argv 셋째 인자 (결정 9)
- Alt↔Meta swap
- **Exit gate:** bash 프롬프트에서 `echo foo bar`를 친 뒤 `alt-left`로
  단어 이동해 `echo foo Xbar`, 이어서 `meta_l-left`로 줄 처음에 가서
  `Yecho foo Xbar`. 각각의 "없어야 할 것"(`echo foo barX`)도 함께 검사

## 저장소 구조 (추가분)

```
input/
  check.sh              ← 새 체인 (부팅 1회)
terminal/src/
  input.zig             ← 대폭 확장. 이 서브프로젝트의 중심
  input_test.zig        ← 표 검증. native 타깃으로 실행
  main.zig              ← Context 채우기, setenv("TERM"), argv[3]
terminal/build.zig      ← *_test 셋을 native 타깃으로
terminal/check.sh       ← *_test 셋을 실행
init/src/config.zig     ← Keyboard enum
init/src/main.zig       ← keyboard를 argv로 전달
devcontainer/Dockerfile ← ncurses-base:amd64 추가
kernel/make_initrd.sh   ← terminfo 복사
check.sh                ← 네 번째 체인 등록
```

## 미리 알고 들어가는 위험

1. **QEMU `sendkey`가 `meta_l`을 실제로 게스트에 KEY_LEFTMETA로 전달하는지
   확인되지 않았다.** QEMU의 `QKeyCode` enum에는 있지만 PS/2 스캔코드 →
   `atkbd` → evdev 경로를 실측하지 않았다. IP-M2의 첫 확인 대상이다.
   전달되지 않으면 `keyboard=pc` 쪽(=Alt를 Cmd로 취급)으로 게이트를
   돌리는 우회가 있다.
2. **fish의 기본 바인딩이 결정 8의 표와 어긋날 수 있다.** readline과
   zle는 문서로 확실하지만 fish는 자체 에디터다. 그래서 IP-M2의 게이트는
   프롬프트에서 `bash`를 쳐서 readline 지형으로 들어간 뒤 검사한다.
3. **`ncurses-base`가 arch: all이라 `apt-get download ncurses-base:amd64`가
   기대대로 동작하지 않을 수 있다.** arch-independent 패키지의 `:amd64`
   지정은 apt 버전에 따라 다르게 처리된다.
4. **DECCKM이 실제로 켜지는지 관측하지 못할 수 있다.** `--no-config`로
   뜬 셸이 `smkx`를 보내지 않으면 `cursor_keys`가 계속 false이고, `ESC O`
   경로는 게이트가 한 번도 밟지 않는다. 그 경우는 `input_test`가 두 형태를
   모두 검사하는 것으로 대신하고, 게이트가 보지 못한다는 사실을 plan에
   명시한다.
5. **타이핑이 길어지면 게이트 시간이 는다.** 현재 루트 게이트는 3체인
   12부팅에 14분 35초다. IP 체인은 부팅 자체는 ~4초지만 `sendkey` 한
   글자당 0.3초가 든다. CP가 3부팅에 81초를 더했고 IP는 글자가 더 많으니
   +4~6분을 예상한다. 필요하면 `sendkey` 간격을 줄이는 것이 첫 손잡이다.

## 검증 방법

**검사는 화면 덤프의 명령줄 자체를 본다.** 실행 결과가 아니라 편집된 줄이
화면에 어떻게 그려졌는지가 증거다. `terminal/src/main.zig`의
`dumpScreen`이 화면 전체를 `terminal: screen> ` 한 줄로 찍고 행을 ` | `로
나누므로, 게이트는 그 줄을 grep한다.

**"없어야 할 것"을 함께 검사한다.** 방향키가 통째로 무시돼도
`echo abcX`는 멀쩡히 실행되므로 긍정 검사만으로는 구분이 안 된다.
`project_gate_chain_composition`이 남긴 교훈 — 게이트는 자기가 안 보는
것을 통과시킨다.

에러 처리는 전부 "조용히 아무것도 안 보낸다"로 수렴한다.

| 상황 | 처리 |
|---|---|
| keymap 배열 밖 keycode | 빈 슬라이스 (현재도 검사 있음) |
| 표에 있지만 값이 0인 키 | 빈 슬라이스 |
| `keyboard=` 값이 이상함 | `apple`로 폴백 |
| terminfo 파일 없음 | 부팅 계속. 셸이 기능을 덜 쓸 뿐 |
| evdev 짧은 read | 현재의 `n / ev_size` 버림 유지. 커널 evdev는 `input_event` 경계로만 넘겨주므로 잘린 꼬리가 생기지 않는다 |

자동 반복(`value == 2`)은 지금처럼 누름과 같게 처리한다 — 방향키를 누르고
있으면 계속 움직여야 하므로 오히려 필요하다.

## 협업 방식

기존과 같다. 설명 먼저 → 파일 작성과 명령 실행은 **사용자가 직접** →
결과를 Claude가 상세 해석. Claude는 design/plan 문서·`HANDOFF.md`·기억
파일 작성과 승인된 내용의 git commit만 대신 수행한다.

100줄이 넘는 파일은 CP-M2에서 정한 예외를 따른다 — Claude가 `/tmp`에
원본을 만들고 `diff`로 대조한 뒤 사용자가 `cp`로 제자리에 넣는다.
`input.zig`는 이번에 확실히 100줄을 넘으므로 이 경로를 쓴다.

관련 기억: `docs/decisions/project_config_persistence.md`,
`project_build_host_arch.md`, `project_gate_chain_composition.md`,
`project_copy_mode.md`, `feedback_execution_scope.md`,
`feedback_design_question_load.md`
