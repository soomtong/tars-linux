---
aliases: [ESC 크래시 코스, 키보드 이스케이프 시퀀스]
tags:
  - study
  - terminal
  - input
  - escape-sequence
  - ansi
---

# 키보드 입력 이스케이프 시퀀스 크래시 코스

> 대상: `terminal/src/input.zig`가 왜 지금 방향키를 못 보내는지, IP-M0~M2가
> 무엇을 고치는 것인지 바닥부터 이해하기.
> 근거 문서: `docs/superpowers/specs/2026-08-15-tars-input-policy-design.md`
> 예제는 이 저장소의 실제 코드에서 가져왔다 — 파일명:줄번호로 표기했다.

---

## 한줄 요약

키보드에는 문자로 표현할 수 없는 키(방향키, F키, Home)가 있는데 터미널은
**바이트 하나짜리 통로**뿐이라, `ESC`(0x1B)를 "다음에 오는 건 글자가 아니라
명령"이라는 탈출구로 삼아 여러 바이트를 한 덩어리로 묶어 보내는 규약이 생겼다.

---

## 1. 왜 이것이 필요한가?

### 문제: 통로는 바이트 하나인데 키는 100개가 넘는다

PTY(pseudo terminal)는 **바이트 스트림**이다. 파이프와 같다. 구조체도,
메시지 경계도, 타입도 없다. `a`를 누르면 `0x61` 한 바이트가 흐른다.

그런데 키보드에는 이런 게 있다.

```
←  →  ↑  ↓  Home  End  PageUp  Delete  F1..F12  Insert
```

이들에 대응하는 문자가 **ASCII에 없다.** 0x00–0x7F 128칸은 이미 다 찼고,
그중 제어 문자 33개(0x00–0x1F + 0x7F)도 1963년 텔레타이프 시절에 각자
의미가 정해졌다.

### 있을 법한 해법 셋과 그 운명

| 방식 | 내용 | 왜 안 됐나 |
|---|---|---|
| 8비트 확장 | 0x80~0xFF에 특수키 배정 | 당시 회선이 7비트였다. 지금은 UTF-8이 그 자리를 다 씀 |
| 길이 접두사 | `[길이][데이터]` 프레이밍 | 바이트 스트림을 **사람도 읽을 수 있게** 유지하려던 설계 철학에 반함 |
| **탈출 문자** | 특정 바이트를 "여기서부터 다르게 읽어라"로 예약 | **채택됨** |

세 번째가 이스케이프 시퀀스다. `ESC`(0x1B)를 만나면 그 뒤 몇 바이트를
문자가 아니라 **명령**으로 읽는다. 통로는 그대로 두고 의미 계층만 하나 얹는
방식이라, 기존 회선·기존 소프트웨어와 공존할 수 있었다.

### 이게 없으면 생기는 일

TARS의 현재 상태가 정확히 그 예시다. `input.zig`의 `handleKey` 반환 타입이
`?u8` — **바이트 하나**다.

```zig
// terminal/src/input.zig:93
pub fn handleKey(self: *State, code: u16, value: i32) ?u8 {
```

←는 최소 3바이트(`ESC [ D`)라서 이 타입으로는 **표현 자체가 불가능하다.**
keymap이 짧아서가 아니다. 그릇이 작아서다. IP-M0 Task 2가 이걸
`[]const u8`로 넓히는 이유다.

---

## 2. 근본적인 동작 원리

### 2.1 전체 데이터 흐름

키 한 번이 셸에 닿기까지 TARS에서 실제로 거치는 경로다.

```
 물리 키보드
     │  USB HID
     ▼
 리눅스 커널 evdev                    /dev/input/event*
     │  struct input_event { time, type, code, value }
     │  type=EV_KEY, code=105(KEY_LEFT), value=1(누름)
     ▼
 input.zig  readKeys()                ← 여기가 우리 코드의 시작
     │  keycode → 바이트열 번역
     │  105 → "\x1b[D"  (3바이트)
     ▼
 PTY master                            terminal이 쥔 fd
     │
     ▼
 커널 line discipline                  ★ 우리가 아닌 커널이 일하는 구간
     │  - 0x03을 보면 SIGINT 발생
     │  - CR(0x0D) → LF(0x0A) 변환 (ICRNL)
     │  - canonical mode면 줄 단위로 버퍼링
     ▼
 PTY slave → 셸(bash/fish)
     │  readline이 "\x1b[D"를 보고 커서를 왼쪽으로
     ▼
 셸이 화면 갱신 시퀀스를 되돌려 보냄     ← 방향이 반대!
     │
     ▼
 vt.zig → libghostty-vt → 화면
```

**여기서 가장 중요한 것:** 이스케이프 시퀀스는 **양방향으로 흐르지만 어휘가
다르다.**

| 방향 | 누가 보냄 | 예 | 뜻 |
|---|---|---|---|
| **입력** (키보드 → 앱) | 우리 `input.zig` | `ESC [ D` | "왼쪽 화살표를 눌렀다" |
| **출력** (앱 → 화면) | 셸/앱 | `ESC [ D` | "커서를 왼쪽으로 옮겨라" (CUB) |

**바이트열이 똑같은데 의미가 다르다.** 문법은 공유하고 의미는 문맥이 정한다.
이 대칭성이 편리하기도 하고 혼란의 근원이기도 하다 — 방향키를 그대로 에코하면
화면이 실제로 움직여 버린다. 5절의 DECCKM이 바로 이 문제에서 나왔다.

### 2.2 ESC의 계층 구조

`ESC` 뒤에 무엇이 오느냐로 세 갈래가 된다.

```
ESC (0x1B)
 ├─ 0x20~0x2F 중간문자 → 2바이트 명령 (ESC ( B  = 문자셋 지정)
 ├─ 0x30~0x7E 최종문자 → 짧은 명령    (ESC =    = DECKPAM)
 └─ C1 제어문자의 7비트 표현          ← 대부분이 여기
      ├─ ESC [  = CSI  (Control Sequence Introducer)   ★ 90%가 이것
      ├─ ESC ]  = OSC  (Operating System Command)
      ├─ ESC O  = SS3  (Single Shift 3)
      └─ ESC P  = DCS  (Device Control String)
```

**C1의 7비트 표현이라는 것이 핵심 개념이다.** 원래 CSI는 8비트 값 `0x9B`
한 바이트였다. 7비트 회선에서 이걸 못 보내니 `ESC` + (원래값 − 0x40)으로
표현하기로 했다.

```
CSI  0x9B − 0x40 = 0x5B = '['   →  ESC [
SS3  0x8F − 0x40 = 0x4F = 'O'   →  ESC O
OSC  0x9D − 0x40 = 0x5D = ']'   →  ESC ]
```

즉 `ESC O D`의 `O`는 **알파벳 O가 아니라 제어문자다.** 우연히 대문자 O로
보일 뿐이다. 이걸 알면 왜 하필 O인지 외울 필요가 없어진다.

### 2.3 CSI 시퀀스의 해부

ECMA-48이 정한 문법이다. 바이트 범위로 역할이 갈린다.

```
   ESC  [   ?   1 ; 2   $   h
   └┬┘ └┬┘ └┬┘ └──┬──┘ └┬┘ └┬┘
    │   │   │     │     │   └── 최종문자 0x40~0x7E : 명령 종류. 여기서 끝
    │   │   │     │     └────── 중간문자 0x20~0x2F : 변형 (거의 안 씀)
    │   │   │     └──────────── 파라미터 0x30~0x3F : 숫자와 ';'
    │   │   └────────────────── 사설 접두사 '<=>?' : 벤더 확장 표시
    │   └────────────────────── CSI
    └────────────────────────── ESC
```

파서 입장에서 이 설계가 훌륭한 점: **모르는 시퀀스도 안전하게 건너뛸 수
있다.** 0x40~0x7E가 나올 때까지 먹다가 나오면 끝, 모르는 명령이면 버린다.
확장에 열려 있으면서 파서가 깨지지 않는다. 40년간 새 기능이 계속 추가될 수
있었던 구조적 이유다.

`?`가 붙으면 **사설(private) 모드**다. ECMA-48이 `< = > ?` 네 글자를
벤더용으로 예약했고 DEC이 `?`를 골랐다. 그래서 이 둘은 완전히 다른 명령이다.

```
ESC [ 1 h      표준 모드 1 (GATM)
ESC [ ? 1 h    DEC 사설 모드 1 (DECCKM)   ← 우리가 다루는 것
```

### 2.4 우리가 보내야 하는 실제 바이트열

`TERM=xterm` 기준. IP-M1의 구현 대상이다.

| 키 | DECCKM 꺼짐 | DECCKM 켜짐 |
|---|---|---|
| ↑ | `ESC [ A` | `ESC O A` |
| ↓ | `ESC [ B` | `ESC O B` |
| → | `ESC [ C` | `ESC O C` |
| ← | `ESC [ D` | `ESC O D` |
| Home | `ESC [ H` | `ESC O H` |
| End | `ESC [ F` | `ESC O F` |
| Delete | `ESC [ 3 ~` | 같음 |
| PageUp | `ESC [ 5 ~` | 같음 |
| PageDown | `ESC [ 6 ~` | 같음 |

규칙성이 보인다. **`~`로 끝나는 것들은 숫자로 키를 식별**하고 DECCKM의 영향을
받지 않는다. **글자로 끝나는 것들만** 두 형태를 갖는다. 화살표·Home·End만
"커서 키"로 분류됐기 때문이다.

---

## 3. 핵심 개념 정리

### 3.1 제어 문자 — ESC 이전의 세계

0x00–0x1F는 이스케이프 시퀀스가 아니라 **그 자체로 한 바이트 명령**이다.
터미널 입력에서 지금도 살아 있는 것들:

| 바이트 | 이름 | 키 | 하는 일 |
|---|---|---|---|
| 0x03 | ETX | Ctrl+C | **커널**이 SIGINT 발생 |
| 0x04 | EOT | Ctrl+D | EOF |
| 0x08 | BS | Ctrl+H | 백스페이스 (아래 함정 참고) |
| 0x09 | HT | Tab | 탭 |
| 0x0D | CR | Enter | 캐리지 리턴 |
| 0x1A | SUB | Ctrl+Z | SIGTSTP |
| 0x1B | ESC | Esc | **이스케이프** |
| 0x7F | DEL | Backspace | 삭제 |

**Ctrl 조합의 규칙은 산술이다.** 문자에서 상위 비트 두 개를 떼면 된다.

```
Ctrl+A  'A'(0x41) & 0x1F = 0x01
Ctrl+C  'C'(0x43) & 0x1F = 0x03
Ctrl+[  '['(0x5B) & 0x1F = 0x1B  ← ESC와 완전히 같은 바이트!
```

마지막 줄이 중요하다. `Ctrl+[`와 `Esc`는 **구분이 불가능하다.** vim 사용자가
`Ctrl+[`를 Esc 대용으로 쓰는 이유가 이것이고, 동시에 이 규약의 근본적 한계를
보여주는 예다.

이 규칙은 design doc 결정 3이자 IP-M0 Task 3의 구현 내용이다. 대상은
`a-zA-Z @ [ \ ] ^ _`와 Space, 그리고 `?`(→ 0x7F 특례)다.

### 3.2 시그널은 우리가 안 보낸다

착각하기 쉬운 지점이다. Ctrl+C를 눌렀을 때 `input.zig`가 하는 일은
**`0x03` 한 바이트를 쓰는 것뿐**이다. SIGINT는 우리가 안 만든다.

```
input.zig  →  0x03을 PTY에 write
                    ↓
            커널 line discipline이 이 바이트를 봄
                    ↓
            "이건 VINTR 문자다" → foreground process group에 SIGINT
```

이게 가능한 이유는 `pty.zig`의 `forkpty`(`terminal/src/pty.zig:37`)가
`setsid` + `TIOCSCTTY`까지 해서 **제어 터미널(controlling terminal)** 을
제대로 만들어 뒀기 때문이다. 제어 터미널이 없으면 이 자동 처리가 안 일어난다.

한 줄 요약: **터미널의 절반은 커널이 이미 구현해 놨다.** 우리 몫은 바이트를
정확히 만드는 것까지다.

### 3.3 evdev — 문자가 아니라 물리 키

리눅스가 우리에게 주는 것은 문자가 아니다.

```c
struct input_event {
    struct timeval time;   // 16 bytes (x86_64)
    __u16 type;            //  2   EV_KEY = 1
    __u16 code;            //  2   KEY_LEFT = 105
    __s32 value;           //  4   0=뗌 1=누름 2=자동반복
};                         // = 24 bytes
```

`code`는 **물리적 위치**다. 레이아웃도, Shift 적용 여부도, 문자도 모른다.
그걸 문자로 바꾸는 게 `keymap`(`input.zig:19-78`)이고, 지금은 US QWERTY
하나만 하드코딩돼 있다.

**현재 keymap은 코드 57(Space)에서 끝난다.** 그런데 방향키는:

```
KEY_HOME      102        KEY_UP       103
KEY_PAGEUP    104        KEY_LEFT     105
KEY_RIGHT     106        KEY_END      107
KEY_DOWN      108        KEY_PAGEDOWN 109
KEY_INSERT    110        KEY_DELETE   111
```

전부 100번대다. `input.zig:107`의 `if (code >= keymap.len) return null;`에
걸려 **조용히 버려지고 있다.** 이게 "방향키가 안 되는" 표면적 이유고, 진짜
이유는 앞서 본 `?u8` 타입이다.

### 3.4 modifier는 물리 키 하나당 비트 하나

`value != 0`으로 누름/뗌을 추적하는 작은 상태 머신이 필요하다.

```zig
// terminal/src/input.zig:82-88
pub const State = struct {
    shift_left: bool = false,
    shift_right: bool = false,

    fn shifted(self: State) bool {
        return self.shift_left or self.shift_right;
    }
```

**왜 논리 상태 하나로 뭉치면 안 되는가:**

```
왼쪽 Shift 누름          → shift = true
오른쪽 Shift 누름        → shift = true  (이미 true)
오른쪽 Shift 뗌          → shift = false ← 왼쪽은 아직 눌려 있는데!
```

물리 키마다 비트를 따로 두고 OR로 합치면 이 버그가 원천 차단된다. design
doc 결정 4가 최종 8개(Shift/Ctrl/Alt/Meta × 좌우)로 늘리는 이유다.

### 3.5 알아두면 덜 헤매는 함정 넷

**(1) Backspace는 0x08이 아니라 0x7F를 보낸다**

이름은 BS(0x08)인데 터미널 관례는 DEL(0x7F)이다. 우리 코드도 그렇게 돼 있다.

```zig
// terminal/src/input.zig:34
.{ 0x7f, 0x7f }, // 14: KEY_BACKSPACE — 터미널 관례상 BS(0x08)가 아니라 DEL
```

DEC 단말이 그렇게 했고 그게 관례가 됐다. `stty erase`로 바꿀 수 있는데,
이 불일치가 "SSH 접속하면 백스페이스가 `^H`로 찍히는" 고전적 증상의 원인이다.

**(2) Enter는 CR(0x0D)을 보낸다. LF가 아니다**

키보드는 CR을 보내고, **커널 line discipline이 ICRNL 플래그로 LF로 바꿔서**
앱에 전달한다. 우리가 LF를 보내면 안 된다 — 변환이 두 번 되거나 앱이
줄바꿈으로 인식하지 못한다.

**(3) Alt는 ESC 접두사다**

`Alt+b`는 별도 코드가 없다. `ESC` + `b` 2바이트다. 그래서 결정 8의
`Option+←` → `ESC b` 번역이 자연스럽게 성립한다. readline이 이미 `ESC b`를
"한 단어 뒤로"로 알고 있다.

역사적으로 "8번째 비트를 세우는" 방식(0xE2)도 있었지만 UTF-8과 충돌해서
사실상 사라졌다.

**(4) ESC 하나만 온 건지, 시퀀스의 시작인지 알 수 없다**

`0x1B`를 읽었을 때 그것이 Esc 키인지 `ESC [ D`의 첫 바이트인지 **원리적으로
구분할 방법이 없다.** 실제 구현들은 **타임아웃**으로 때운다 — vim의
`ttimeoutlen`(기본 수십 ms)이 그것이다. 그래서 느린 SSH에서 Esc를 눌렀는데
엉뚱한 명령이 실행되는 일이 생긴다.

우리는 **보내는 쪽**이라 이 문제를 직접 겪지 않는다. 다만 우리가 보낸 바이트를
받는 셸은 이 판정을 하고 있다는 걸 알아둘 필요가 있다.

### 3.6 DECCKM — 같은 키, 두 형태

`ESC [ D`냐 `ESC O D`냐를 결정하는 모드다. **DEC C**ursor **K**eys **M**ode,
사설 모드 1.

```
셸이 편집 모드 진입 → terminfo의 smkx 문자열 출력 → ESC [ ? 1 h
                                                        ↓
                                            우리 VT가 이걸 파싱해서 상태 저장
                                                        ↓
                                       screen.term.modes.get(.cursor_keys) == true
                                                        ↓
                                            이제 ← 는 ESC O D 로 보내야 함
```

**왜 두 형태가 필요했나:** `ESC [ D`는 출력 방향에서 "커서 왼쪽으로"(CUB)라는
진짜 명령이다. 에코되면 화면이 움직인다. 편집기처럼 키를 **명령으로만** 쓰는
앱에게는 충돌하지 않는 별도 형태가 필요했고, 그게 SS3 계열이다.

**TARS의 설계 결정 두 가지가 여기 걸린다:**

- 결정 5 — **추측하지 않고 VT에게 물어본다.** 이건 논리로 유도할 수 있는
  규칙이 아니라 상대가 무엇을 켰는지에 달린 **상태**다.
- 결정 6 — 그래도 `input.zig`는 `vt.zig`를 import하지 않는다. `main.zig`가
  읽어서 `Context{ cursor_keys: bool }`로 넘긴다. 의존 방향을 단방향으로
  유지하고, `input_test`가 ghostty-vt 없이 혼자 돌 수 있게 하기 위해서다.

### 3.7 terminfo — 규약의 사전

터미널마다 시퀀스가 다르니 앱이 하드코딩할 수 없다. terminfo DB가 `TERM`
값별로 시퀀스를 등록해 두고 앱은 **이름으로** 찾는다.

| 이름 | 뜻 | xterm에서의 값 |
|---|---|---|
| `kcub1` | key cursor back 1 | `ESC O D` |
| `kcuf1` | key cursor forward 1 | `ESC O C` |
| `khome` | key home | `ESC O H` |
| `smkx` | set keypad transmit | `ESC [ ? 1 h` |
| `rmkx` | reset keypad transmit | `ESC [ ? 1 l` |

**`TERM`이 지금 거짓말 중이다**(결정 7). 커널이 PID 1에게 준 `linux`가
`execv` 환경 상속을 타고 PTY 셸까지 내려오는데, 그 셸이 말을 거는 상대는
리눅스 콘솔이 아니라 **libghostty-vt(xterm 계열)** 다. Home 하나만 봐도
`linux`는 `ESC [ 1 ~`, `xterm`은 `ESC O H`로 다르다.

그래서 `forkpty` 직전에 `setenv("TERM", "xterm", 1)`을 부른다. 시리얼 콘솔
셸은 `linux` 그대로 둔다 — 그쪽은 진짜 커널 콘솔이다.

> `xterm-256color`가 아니라 `xterm`인 이유: 아직 색을 하나도 안 그린다
> (`terminal/src/main.zig:13`의 `TEXT_COLOR`가 흰색 상수 하나). 256색을
> 광고하면 반대 방향의 거짓말이 된다.

---

## 4. 이해도 확인 Q&A

### Q1. `input.zig`가 방향키를 못 보내는 진짜 이유는? keymap을 100번대까지 늘리면 해결되는가?

**A**: 해결되지 않는다. 표면적으로는 keymap이 코드 57에서 끝나 `code >=
keymap.len`에 걸리는 것이지만, 근본 원인은 **`handleKey`의 반환 타입이
`?u8`** 이라는 것이다. ←는 `ESC [ D` 3바이트인데 이 타입으로는 표현 자체가
불가능하다. keymap을 늘려도 담을 그릇이 없다. IP-M0 Task 2가 `[]const u8`로
넓히는 것이 순서상 먼저인 이유이고, 이것이 "테이블이 짧아서"라는 오진을
피하는 지점이다.

### Q2. `ESC O D`의 `O`는 왜 하필 O인가? 외워야 하는가?

**A**: 외울 필요 없다. 유도된다. `ESC O`는 C1 제어문자 **SS3(0x8F)의 7비트
표현**이고, 규칙은 `ESC` + (원래값 − 0x40)이다. `0x8F − 0x40 = 0x4F = 'O'`.
알파벳 O가 아니라 제어문자가 우연히 O로 보이는 것이다. 같은 규칙으로 CSI
(0x9B)는 `[`(0x5B), OSC(0x9D)는 `]`(0x5D)가 된다.

### Q3. Ctrl+C를 눌렀을 때 SIGINT를 보내는 주체는 누구인가? 왜 그렇게 설계됐나?

**A**: **커널의 line discipline**이다. `input.zig`는 `0x03` 한 바이트를 PTY에
쓸 뿐이다. 이게 가능한 이유는 `pty.zig:37`의 `forkpty`가 `setsid` +
`TIOCSCTTY`로 제어 터미널을 제대로 만들어 뒀기 때문이다. 이 설계가 옳은 이유는
**시그널 대상이 foreground process group**인데, 그 정보는 커널만 정확히
알기 때문이다. 우리가 직접 보내려면 프로세스 그룹을 추적해야 하고, 파이프라인이
있으면 금세 틀린다. 우리 몫은 바이트를 정확히 만드는 것까지다.

### Q4. modifier를 논리 상태 하나(`shift: bool`)로 관리하면 어떤 버그가 나는가?

**A**: 양쪽 Shift를 함께 쓸 때 깨진다. 왼쪽 Shift를 누른 채 오른쪽 Shift를
눌렀다 떼면, 그 **뗌 이벤트 하나가 논리 Shift를 통째로 꺼버린다**. 왼쪽은
여전히 눌려 있는데 상태는 false다. evdev가 물리 키 단위로 이벤트를 주므로
상태도 물리 키 단위로 들고 OR로 합쳐야 한다. `shift_left || shift_right`가
그 형태이고, 결정 4가 이를 8개로 확장한다.

### Q5. DECCKM 상태를 `input.zig`가 `vt.zig`에서 직접 읽지 않고 `main.zig`를 거쳐 값으로 받는 이유는? 대가는 무엇인가?

**A**: 세 가지다. (1) **의존 방향이 단방향으로 유지된다** — 현재 `main.zig`만
다섯 모듈을 알고 그들끼리는 서로 모른다. `input → vt` 화살표를 그리면 이
성질이 깨지고 나중에 순환이 생길 여지가 열린다. (2) **`input_test`가 혼자
돌 수 있다** — `build.zig`의 `input_test_mod`는 libc만 링크하고 ghostty-vt를
안 붙인다. (3) **bool 하나가 포인터보다 검증하기 쉽다** — 테스트에서
`ctx.cursor_keys`를 뒤집어 두 형태를 다 확인할 수 있다. 대가는 매 키마다
`modes.get`을 호출하는 것인데, packed struct 비트 읽기 한 번이라 무시할 수준이다.

### Q6. `TERM=linux`를 그대로 두면 구체적으로 무엇이 깨지는가?

**A**: 앱이 잘못된 사전을 참조한다. Home 키만 봐도 `linux` terminfo는
`ESC [ 1 ~`, `xterm`은 `ESC O H`로 등록돼 있다. 우리 VT는 xterm 계열
(libghostty-vt)인데 셸은 `linux`용 시퀀스를 기대하므로, 우리가 어느 쪽을
보내든 **한쪽은 반드시 틀린다.** 게다가 이건 조용히 틀린다 — 에러가 아니라
"방향키가 이상한 문자를 찍는" 증상으로 나타나 원인 추적이 어렵다.

### Q7. `ESC [ 3 ~`(Delete)는 DECCKM의 영향을 받지 않는데 `ESC [ D`(←)는 받는다. 이 구분의 기준은?

**A**: **"커서 키"로 분류됐는가**다. DECCKM의 이름 그대로 대상은 화살표 4개와
Home/End뿐이다. 이유는 이들만 출력 방향에서 실제 커서 이동 명령(CUB/CUF/CUU/
CUD)과 바이트열이 겹치기 때문이다. `~`로 끝나는 시퀀스들은 숫자로 키를
식별하며 출력 명령과 충돌하지 않아서 별도 형태가 필요 없었다. 즉 이 구분은
분류학이 아니라 **충돌 회피**의 산물이다.

### Q8. IP-M1 게이트가 `--no-config` 셸을 쓰면 `ESC O` 경로를 한 번도 안 밟을 수 있다. 왜이고, 어떻게 대응하는가?

**A**: DECCKM을 켜는 주체는 **셸**이다(terminfo `smkx` 출력). `--no-config`로
뜬 셸이 `smkx`를 안 보내면 `cursor_keys`가 계속 false라 우리는 `ESC [ D`만
보내게 되고, `ESC O D` 분기는 실행되지 않는다. QEMU 화면 덤프로는 증명할 수
없는 경로다. 대응은 **검증 수단을 바꾸는 것** — `input_test`에서
`ctx.cursor_keys`를 true/false 양쪽으로 두고 두 형태를 모두 확인한다.
"게이트로 못 보는 것은 단위 테스트로 본다"는 분업이다.

### Q9. `Ctrl+[`와 `Esc`가 같은 바이트인 것은 버그인가?

**A**: 버그가 아니라 Ctrl 규칙(`& 0x1F`)의 **필연적 귀결**이다.
`'[' (0x5B) & 0x1F = 0x1B` = ESC. 다만 이것이 이 규약의 근본 한계를 드러내는
사례이기도 하다 — `Ctrl+I`와 `Tab`(둘 다 0x09), `Ctrl+M`과 `Enter`(둘 다
0x0D)도 마찬가지로 구분 불가능하다. 현대의 kitty keyboard protocol이
해결하려는 것이 정확히 이 모호성이다. 다만 그 규약은 **앱이 명시적으로
요청해야** 켜지고 bash/readline은 요청하지 않으므로, TARS의 현재 범위에서는
도입 대상이 아니다.

---

## 5. 더 알아보기

### 이 저장소 안에서

- `docs/superpowers/specs/2026-08-15-tars-input-policy-design.md` — 결정 11개.
  특히 결정 3(Ctrl), 5(DECCKM), 6(Context), 7(TERM), 8(macOS 의미론)
- `terminal/src/input.zig:19-78` keymap, `:82-112` `State`, `:122-142` `readKeys`
- `terminal/src/pty.zig:23-47` `forkpty` — line discipline이 살아나는 지점
- `terminal/ghostty-src/src/terminal/modes.zig:288` — `cursor_keys` 정의
- `terminal/ghostty-src/src/terminal/Terminal.zig:83` — `modes` 필드

### 바깥 자료

- **XTerm Control Sequences** (Thomas Dickey) — 이 분야의 사실상 레지스트리.
  공식 표준은 아니지만 모든 구현체가 참조한다
- **ECMA-48 5th edition (1991)** — CSI 문법의 원전. 이후 개정 없음
- **VT100 User Guide** / **DEC STD 070** — DEC 사설 모드의 출처
- `man 4 console_codes` — 리눅스 콘솔이 이해하는 시퀀스 목록
- `infocmp xterm` — terminfo 항목을 직접 덤프해서 확인하는 명령

### 다음에 볼 만한 주제

- **kitty keyboard protocol** — Ctrl+I/Tab 구분, 키 뗌 이벤트, 전 키
  modifier 보고. ghostty-vt는 이미 파싱을 구현하고 있어서, 나중에 vim류를
  띄울 때 인코딩만 붙이면 된다
- **modifyOtherKeys** (`CSI > 4 ; 2 m`) — 같은 문제에 대한 xterm의 더 오래된 답
- **line discipline의 termios 플래그** — `ICRNL`, `ICANON`, `ISIG`, `ECHO`가
  각각 무엇을 켜고 끄는가
- **bracketed paste** (`ESC [ ? 2004 h`) — 붙여넣기와 타이핑을 구분하는 모드.
  DEC의 `?` 자리를 현대에 재활용한 좋은 예
