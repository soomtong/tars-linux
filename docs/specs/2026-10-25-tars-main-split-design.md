# TARS Main Split — Design

Date: 2026-10-25
Status: 끝났다 — MS-M0(2026-10-25, 루트 게이트 22/22, prebuild 293초 + lanes 289초) · MS-M1(2026-10-25, 루트 게이트 22/22,
prebuild 293초 + lanes 289초). plan은 `docs/plans/2026-10-25-tars-main-split-ms-m{0,1}.md`, 기억은
`docs/decisions/project_main_split.md`. 구현 중 design과 달라진 자리 — 결정 4의 "`readPointers`가 `round` · `before_spot` · `supply_seen`을 struct 하나로"는 `Pointers`가
됐고 `ws`는 `wirePointer`가 구한다. 그리기 단계의 `render` → `dumpFrame` 사이는 `Frame` struct(프롬프트 · 상태 줄 버퍼 포함,
`tick`의 스택)로 건넨다. probe anchor는 셋이 아니라 넷이다(plan 실측 6).

HANDOFF "다음 후보"의 첫 항목에서 시작한다(2026-10-24 프로젝트 점검이 남긴 넷 가운데 추천 1순위. 사용자가 2026-10-25에 골랐다).

> `terminal/src/main.zig`의 `main`이 1,100줄쯤, init의 `main`이 400줄쯤 — 설정 꺼내기 · 장치 열기 · 이벤트 루프로 나눈다.
> 다음 기능(부분 갱신 · WP-M3)이 전부 이 함수에 더해질 자리다.

## 한 줄 요약

terminal의 `main`(1,072줄)과 init의 `main`(406줄)을 "준비 → 바퀴 → 정리"의 단계 함수로 나누고, 바퀴를 넘어 사는 값은 struct 하나
(terminal `App` · init `Boot`)의 필드로 모은다. `main`은 단계를 순서대로 부르는 열 줄쯤이 되어 "무엇이 무엇보다 앞인가"가 주석이
아니라 코드의 순서로 보인다. 동작 · 로그 글자 · 프레임 수 · argv · env는 하나도 바뀌지 않고, 체인 스크립트도 안 고친다.

## 배경

### terminal의 `main`

2817~3889줄, 1,072줄이고 그 가운데 530줄이 주석이다. 모양은 둘로 갈린다.

| 구간 | 줄 | 무엇을 |
|---|---|---|
| 준비 | 358 | DRM · 격자 · 폰트 · argv `decode` · 키보드 · env 셋 · 셸 argv · 첫 패널 · 로그 넷 · 버퍼 · 포인터(uevent 소켓 · 훑기) · 배터리 · poll 배열 |
| `main_loop` | 714 | fds 짓기 24 · poll 12 · 키보드 290(switch 넷: 스크롤 · copy · 패널 · 받아쓰기) · 포인터 82 · PTY 103(EOF · 패널 닫기 · 워크스페이스 당기기) · 받아쓰기 파이프 7 · 그릴지 정하기 35 · 그리기와 덤프 127 |

준비 구간에 지역 변수가 56개다. 둘이 섞여 있다 — 바퀴를 넘어 사는 것(`needs_redraw` · `last_frame_ms` · `pointer_shown` ·
`battery_state` · `last_status_*` …)과 한 바퀴 안의 것(`ws` · `focus` · `round` · `before_spot` · `supply_seen` · `want`). 바퀴
안의 단계 순서는 전부 주석이 지킨다 — "키보드 뒤 · PTY 앞이다(PD design 결정 3)", "PTY 뒤 · 렌더 앞이다", "`!needs_redraw`의
`continue`보다 앞이어야 한다(검사 A3)". 그 순서가 이 함수의 뜻인데, 함수가 한 화면을 열 번 넘으니 순서를 한눈에 볼 자리가 없다.

같은 파일에 이미 선례가 있다. PD-M4의 `PointerWire`는 포인터 분기가 바퀴 안에서 만지는 상태를 포인터로 묶고 `edge` · `moved` ·
`wheel` · `run`으로 나눈 것이고, `Dictation` · `BatteryState` · `Clips`도 상태 묶음에 함수가 붙은 모양이다. 바퀴 전체에 같은
모양을 준다.

### init의 `main`

1066~1472줄, 406줄이고 210줄이 주석이다. 여섯 절이다 — 시그널과 마운트, 설정(mount · load · cmdline 탈출로 · seed 넷 · `config`
로그 줄), 장치(DRM 존재 · 키보드 경로 · 전원 버튼), 셸과 env(`resolveShell` · 시간대 · env 블록 · 로그 · `login.apply`), 일꾼
(`audio.start` · `firewall.up`), 자식(원하는 데몬 셋 · 서비스 목록 · 플래그 셋 · `encode` · `Live` · `children` 열셋). 끝이
`supervise`이고 그것은 이미 함수다(218줄, 구조는 lessons "감독 루프의 구조").

이 함수의 특징은 수명이다. `supervise`가 영영 반환하지 않으므로 `main`의 스택이 프로세스 수명이고, 자식의 argv와 env가 가리키는
버퍼 아홉(`terminal_toggle_buf` · `keyboard_path` · `button_fds` · `tz_buf` · `env_buf` · `service_list` · `live` · `children`과
그 안의 포인터)이 거기 산다. 그 사실을 적은 주석("`main()`의 스택에 살고 `supervise()`가 영영 반환하지 않으므로 프로세스 수명
내내 유효하다")이 여섯 번 반복된다. 규칙 하나가 여섯 자리에 흩어진 것이다.

### 왜 지금

다음 기능이 전부 이 두 함수 안에 더해진다 — 부분 갱신은 그리기 단계에, WP-M3 방향 포커스는 패널 switch에, 새 설정 키는 init의
자식 절에. 더하기 전에 자리를 만든다. 그리고 이번은 기능이 아니라 이해를 위한 작업이다 — 두 프로그램의 뼈대가 "단계 호출의 순서표"
한 함수로 읽히면, 다음 사람이 바퀴의 순서를 주석을 모아 재구성하지 않아도 된다.

## 착수 전에 확인한 것

2026-10-25, HEAD `3a64dc3`.

1. terminal `main`은 2817~3889줄(1,072줄). 준비 358줄에 지역 변수 56개, `main_loop:` 714줄. 바퀴를 넘어 사는 것과 한 바퀴 것의
   목록은 위 배경에 있다. 바퀴 안에서 `init.io`를 13번, `allocator`를 2번(`spawnPane`) 쓴다 — struct가 둘을 들어야 한다.
2. init `main`은 1066~1472줄(406줄). `supervise`(847~1065)는 이미 함수다. 프로세스 수명 내내 살아야 하는 버퍼는 위 배경의 아홉이다.
3. init의 `toggle_buf`(1152줄)에 붙은 주석 "이 배열이 argv로도 간다"는 SA-M1 뒤로 거짓이다 — argv의 7번 칸은 `terminal_toggle_buf`를
   가리키고(`screen_args.encode`), `toggle_buf`는 `config shell=` 로그 줄에만 쓰인다. 설정 절의 지역 변수로 내려올 수 있다.
4. `main.zig`를 글자로 보는 스크립트는 여섯이고 다섯은 주석이다(`make_initrd.sh` · `gate_lib.sh` · `input/check.sh` ·
   `config/check.sh`의 줄 번호 인용). `probe/patch.pl`만 소스를 고친다 — anchor 셋이 `var pty_buf: [4096]u8 = undefined;`
   (들여쓰기 4) · `pane.screen.feed(out);`(들여쓰기 무관) · `dumpPointerAt(…)` 앞의 주석 줄과 호출(들여쓰기 8)이고, 끼우는 코드가
   `init.io` · `frame_start` · `frame_us`를 이름으로 쓴다. 게이트가 아니라 RS의 프로브다(lessons "핵심 파일" `probe/`).
5. 체인이 보는 것은 로그 줄과 화면이다. 로그 서식 문자열은 `rg -o 'logline\.print\(\s*"[^"]*"' --multiline`으로 뽑으면 terminal
   `main.zig` 94개(그중 `main` 안 29) · init `main.zig` 56개(`main` 안 7)다. 전후의 집합이 같으면 글자는 안 바뀐 것이다 — 순서는
   별도다.
6. `App`과 `Boot`라는 이름은 두 파일에 없다.
7. Zig에서 struct를 값으로 돌려줄 때 자기 필드를 가리키는 포인터가 있으면 복사 뒤에 낡은 주소가 된다. terminal의 상태 가운데 자기
   안을 가리키는 것은 `fd_panes`(`workspaces` 안의 패널 포인터) 하나이고, 바퀴마다 poll 앞에서 다시 지어 그 바퀴 안에서만 읽는다.
   `PointerWire`도 바퀴마다 새로 짓는다. 그 밖에는 없다 — `cache` · `clips.shared`는 힙을 가리킨다.
8. `.workspace_1`~`9` 갈래의 `continue`는 아래 `needs_redraw = true`를 건너뛰는 것이 뜻이다. switch를 함수로 빼도 `for`가 함께
   가므로 `continue`의 뜻은 그대로다. `break :main_loop`(마지막 패널 EOF)만 반환값으로 바뀐다.

## 결정

### 결정 1. 동작은 0줄 바뀐다. 검사는 셋이다

로그의 글자와 순서, 프레임 수, argv, env, `defer`의 순서까지 그대로다. 체인 스크립트는 편집하지 않는다. "그대로"를 보는 길은 셋이다.

- (a) 확인 5의 로그 서식 문자열 집합을 전후로 뽑아 `diff`한다. 두 파일 모두 빈 diff여야 한다.
- (b) `git diff --color-moved=dimmed-zebra`로 본다. 옮기기만 한 줄은 흐리게, 글자가 바뀐 줄만 진하게 나온다 — 진한 줄이 "새로
  쓴 것"(struct 선언 · 함수 머리 · `self.` 접두사 · 반환값)에 한정되는지 읽는다. 지역 변수가 필드가 되면 선언 `var x = …;`가
  `x: T = …,`로, 그것을 쓰는 줄은 `x`가 `self.x`로 바뀌어 진하게 나온다 — 수는 많지만 모양이 둘이다. 그 줄들은
  `git diff --word-diff`로 보면 바뀐 낱말이 `self.` 하나뿐인지가 바로 드러난다. 주석 줄은 들여쓰기만 바뀌므로
  `--color-moved-ws=allow-indentation-change`를 함께 준다.
- (c) 루트 게이트 22/22. init과 terminal이 모든 체인에서 부팅한다.

### 결정 2. terminal — `App` struct 하나, `main`은 `open → tick 반복 → close`

바퀴를 넘어 사는 값 전부가 필드다. 지역 변수에 붙어 있던 주석은 그 필드의 문서 주석이 된다(지우지 않는다). 묶음은 이렇다.

| 묶음 | 필드 |
|---|---|
| 화면 | `fb` · `cache` · `io` · `allocator` · `cols` · `rows` · `whole` · `cell_buf` · `screen_line_buf` · `img_buf` |
| 셸 | `shell_path` · `argv` · `swap_alt_meta` |
| 패널 | `workspaces` · `current` · `clips` · `last_pane` |
| 입력 | `keyboard_fd` · `key_state` · `key_buf` · `pty_buf` |
| 포인터 | `pointer_devs` · `pointer_state` · `sprite` · `pointer_shown` · `gesture` · `gesture_ws` · `grab` · `grab_ws` · `uevent_fd` |
| 배터리 | `battery_clock` · `battery_state` |
| 받아쓰기 | `dict` |
| 프레임 | `needs_redraw` · `output_pending` · `last_frame_ms` · `first_frame_timed` · `last_glyph_count` · `last_status` · `last_status_len` · `last_status_caps` · `last_status_battery` |
| poll | `fds` · `fd_devs` · `fd_panes` · `nfds` · `pty_base` · `pty_end` |

한 바퀴 안의 것(`ws` · `focus` · `round` · `before_spot` · `supply_seen` · `want`)은 필드가 아니다 — `tick`의 지역 변수거나 단계
함수의 반환값이다. `ws`는 단계마다 `&self.workspaces[self.current].?`로 다시 구한다. 키보드 단계가 `current`를 바꾸면 그 뒤
단계는 새 값을 본다 — 지금 코드가 `ws = &workspaces[current].?`를 바꾸는 자리마다 다시 대입하는 것과 같다. 키보드 단계 안의
`focus`는 지금처럼 단계 머리에서 한 번 잡고 패널 명령이 옮겨도 그 배치 안에서는 안 바꾼다(받아쓰기 명령이 `ws.focus`로 다시
구하는 것도 그대로다).

구조체 안에 자기 필드를 가리키는 포인터를 두지 않는다(확인 7). `fd_panes`는 바퀴마다 다시 짓는 규칙을 문서 주석에 적는다.
`open`이 값으로 돌려주고 `main`의 스택에 놓이므로 크기는 지금과 같다 — 지금도 전부 `main`의 스택에 있다.

### 결정 3. `open`은 지금의 준비 순서를 지키는 단계 함수 다섯이다

| 단계 | 무엇을 | 찍는 로그 |
|---|---|---|
| `openScreen` | `drm.open` · `fill` · `modeset` · 격자 · 폰트 | `grid` · `font cache ready` |
| `openKeyboard` | `screen_args.decode` · `input.openDevice` | `opened` |
| `spawnFirst` | `setenv` 셋 · 셸 argv · `Clips` · 워크스페이스 하나 · `spawnPane` · 버퍼 둘 | `spawned child pid` · `keyboard=` · `hangul layout=` · `clipboard scope=` |
| `openPointers` | uevent 소켓 · `touchpad_screen` · `scanPointers` | (실패 때만 `pointer> uevent failed`) |
| `openBattery` | `battery_clock` · `scanBattery` | — |

일곱 줄의 로그 순서가 지금과 같아야 한다 — `grid` → `font cache ready` → `opened` → `spawned child pid` → `keyboard=` →
`hangul layout=` → `clipboard scope=`. `config/check.sh`가 `keyboard` 줄 다음에 `clipboard` 줄이 온다는 것을 쓴다(753줄).

준비 중의 실패는 지금처럼 에러를 돌려주고 프로세스가 끝난다 — init이 되살린다. 중간에 연 것을 닫지 않는 것도 지금과 같다.

### 결정 4. `tick`은 단계 호출 열 줄쯤이고, 순서 주석은 여기에 모인다

```
arm()            fds를 짓는다 — 키보드 · uevent · 포인터 장치 · 모든 패널 · 받아쓰기 둘
poll             배터리 기한과 프레임 하한 가운데 이른 쪽
readKeyboard()   키 → PTY · 스크롤 · copy · 패널 · 받아쓰기 명령
readPointers()   빠진 장치 닫기 · 읽기 · uevent → round
pollBattery()    uevent에 power_supply가 있었거나 기한이 지났으면
wirePointer()    round → PointerWire
readPanes()      PTY 출력 · EOF(마지막 패널이면 quit)
readDictation()  파이프 둘 · 끝나면 넣기
decideFrame()    하한 · 화살표만 고치는 갈래(그릴 일이 없으면 여기서 끝)
render() → dumpFrame()
```

지금 주석이 지키는 순서("키보드 뒤 · PTY 앞", "PTY 뒤 · 렌더 앞", "`!needs_redraw`의 `continue`보다 앞")가 `tick`의 열 줄에 한
번씩 적힌다. 단계 함수의 머리에는 "어느 단계이고 앞뒤가 무엇인가" 한 줄만 둔다. 바퀴를 끝내는 길은 둘이다 — `readPanes`가 마지막
패널의 EOF를 보면 `tick`이 `false`를 돌려주고(`break :main_loop`의 자리), `decideFrame`이 그릴 일이 없다고 하면 `true`를 돌려주되
그리기를 건너뛴다(`continue`의 자리). `main`은 `while (try app.tick()) {}`다.

`tickBattery`라는 함수가 이미 있어 배터리 단계는 `pollBattery`다. 한 바퀴 안의 값은 반환값으로 건넨다 — `readPointers`가
`round` · `before_spot` · `supply_seen`을 struct 하나로 돌려주고 `pollBattery` · `wirePointer` · `dumpFrame`이 그것을 받는다.

### 결정 5. 키보드 단계는 switch 넷을 함수 넷으로

`readKeyboard`는 키를 읽고 바이트를 PTY에 쓰고, 나머지는 `runScrolls` · `runCopies` · `runPanes` · `runDictates`가 받는다. 네
switch에 `else`가 없는 규율은 그대로다(lessons "핵심 파일" — "copy 배선 switch에 `else`가 없는 규율이 매번 값을 한다"). 순서도
그대로다 — 스크롤 → copy → `keys.redraw`의 preedit → 패널 → 받아쓰기이고, 그 순서의 이유(포커스를 옮기기 전에 떠나는 패널의
조합 글자를 지운다 등)는 각 함수 머리의 주석으로 옮긴다.

### 결정 6. 그리기 단계는 `render`와 `dumpFrame` 둘이다

`render`는 포커스 아닌 패널 → 포커스 패널 → 프롬프트 · 상태 줄 → `renderFinish`까지이고, `dumpFrame`은 덤프 열둘과 `font>` 줄 ·
`dumpPointerAt`이다. 덤프의 순서는 게이트의 계약이다(`dumpCursor`가 `dumpInk` 뒤 · `dumpScroll` 앞, `dumpPointerAt`이 맨 뒤 —
pointer 검사 11) — 그대로 옮긴다. `frame_start` · `frame_us`라는 이름은 유지한다(확인 4의 probe가 쓴다).

### 결정 7. `probe/patch.pl`의 anchor 셋을 새 자리로 고친다

프로브는 게이트가 아니지만 그리기를 고칠 때마다 전후를 재는 도구이고(부분 갱신이 다음 후보다), anchor가 깨지면 그때 가서 고쳐야
한다. 이번에 고친다 — `var pty_buf` 줄은 필드 선언으로, `dumpPointerAt` 호출은 `dumpFrame` 안의 자리로, 끼우는 코드의 `init.io`는
`self.io`로. `perl probe/patch.pl terminal/src/main.zig /tmp/x`가 anchor 셋을 한 번씩 찾는 것을 확인한다. 사본이 컴파일되는지까지
보려면 `probe/run.sh`가 부팅 한 번이다 — M0 plan이 그 비용을 보고 정한다.

### 결정 8. init — `Boot` struct 하나, `main`은 단계 호출 일곱

프로세스 수명 내내 살아야 하는 버퍼 아홉이 `Boot`의 필드다. "`main()`의 스택에 살고 `supervise()`가 영영 반환하지 않으므로"가
타입의 문서 주석 한 자리에 한 번 적히고, 여섯 자리의 반복은 사라진다. `main`은 이렇다.

```
mountEarly()       power.install · disableCtrlAltDel · mount 셋 · devpts · /dev/fd · lo
readConfig()       mountConfig · loadConfig · cmdline 탈출로 · seed 넷 · XDG · `config shell=` 로그
probeDevices()     DRM 존재 로그 · 키보드 경로 · 전원 버튼
buildEnv()         resolveShell · 시간대 · env 블록 · `env` 로그 · login.apply
startHelpers()     audio.start · firewall.up
placeChildren()    원하는 데몬 셋 · 서비스 목록 · 플래그 셋 · encode · Live · children 열셋
control.open → supervise
```

`toggle_buf`는 `readConfig`의 지역 변수가 되고 낡은 주석(확인 3)은 지운다 — 유일하게 "옮기기"가 아닌 편집이고, 동작은 같다.
`ntp_buf` · `ssh_env`도 로그 한 줄 · 호출 한 번에만 쓰여 지역으로 남는다. `supervise` · `doReload` · `doReloadTerminal`은 건드리지
않는다.

init은 힙이 없고 libc가 없다. `Boot`의 버퍼 필드는 `= undefined` 기본값으로 두고 단계가 채운다 — 지금 `var x: [N]u8 = undefined;`
와 같은 모양이다. `main`의 스택에 `var boot: Boot = .{}` 하나가 놓이고 단계는 `*Boot`를 받는다. 값으로 돌려주지 않는다 — argv와
env 블록이 이 안의 버퍼를 가리키므로 복사하면 주소가 낡는다(terminal과 다른 점이고, 그래서 두 struct의 짓는 법이 다르다).

### 결정 9. 새 파일은 만들지 않는다

두 `main.zig` 안에서만 옮긴다. 이유는 결정 1(b)다 — 한 파일 안의 이동은 `--color-moved`가 전부 짝을 지어 주고, 읽는 사람은 진한
줄만 본다. 덤프 절 · 배터리 절 · 포인터 절 · 받아쓰기 절을 파일로 내는 것은 다른 일이고 비목표 2다.

### 결정 10. 주석은 옮기되 지우지 않는다

이 두 함수의 주석은 결정의 기록이다(어느 milestone이 왜 이 순서를 골랐는가). 지역 변수의 주석은 필드의 문서 주석으로, 분기 머리의
주석은 단계 함수의 문서 주석으로 간다. 지우는 것은 확인 3의 거짓 주석 하나다. 줄 번호를 인용한 주석(`init/src/main.zig:389` 등)은
원래도 낡아 있었고 이번에 더 낡는다 — 보이는 것만 고치고 찾아다니지 않는다.

### 결정 11. 루트 게이트로 닫는다

M0(terminal)과 M1(init) 각각 루트 게이트다. 모든 체인이 둘 다 부팅하므로 체인 하나로 끝내지 않는다. 호스트 0.17의
`zig fmt --check` · `ast-check`는 컨테이너 빌드 앞에 돈다.

## Milestone

- MS-M0 — terminal `App`(결정 1 ~ 7 · 9 ~ 11). 한 번에 다 옮기지 않고 단계마다 컨테이너 빌드와 (a) 검사를 거친다 — plan에 순서가
  있다.
- MS-M1 — init `Boot`(결정 1 · 8 ~ 11). plan은 M0의 게이트가 끝난 뒤 쓴다.

## 위험

1. 옮기면서 순서가 바뀐다. 가장 큰 위험이고 컴파일러가 못 잡는다 — 렌더 앞에서 `ws` · `focus`를 다시 구하는 자리, `needs_redraw`를
   켜는 자리, `output_pending`과 하한의 관계, `pointer_shown`을 끄는 두 자리. 막는 길은 단계마다 옮기고 매번 빌드 · (a) · 체인
   하나(terminal 또는 pointer)로 보는 것이다. 게이트의 `screen>` 줄 수가 프레임 수를 세므로 프레임이 하나 늘거나 줄면 빨개진다.
2. `continue` · `break`의 뜻. 확인 8 — `for` 안의 것은 함수로 함께 가므로 그대로이고, `break :main_loop`와 바깥 `continue` 둘만
   반환값이 된다. 그 둘을 옮기는 자리에서 한 번 더 읽는다.
3. `App`을 값으로 돌려줄 때의 자기 포인터(확인 7). 규칙을 문서 주석에 적고, `fd_panes`를 `arm` 밖에서 읽는 자리가 없는지 본다.
4. `defer`의 순서. 지금 `main`의 `defer` 다섯(`cache.deinit` · `clips.shared.deinit` · 패널 `deinit` · 버퍼 `free` 둘 · 받아쓰기
   `signalDictation`)이 `close` 하나로 모인다 — 등록의 역순 그대로 쓴다. 순서에 의존은 없지만 바꿀 이유도 없다.
5. probe anchor(결정 7). anchor가 깨지면 `patch.pl`이 멈추므로 숨지는 않는다.
6. 문서가 지역 변수 이름을 인용한다 — lessons "핵심 파일"의 두 `main.zig` 줄, `project_render_speed`의 `output_pending` ·
   `needs_redraw`, `project_pointer_devices`의 `pointer_shown`. 이름을 필드로 그대로 가져가므로 글자는 맞고, "지역 변수"라는 말만
   낡는다. 닫을 때 lessons의 두 줄은 고치고 decisions는 찾아다니지 않는다.
7. 큰 diff. terminal은 1,000줄이 움직인다. 결정 1(b)가 읽는 법이고, plan이 단계를 나눠 commit 하나가 한 단계가 되게 한다 — 읽는
   사람이 한 번에 보는 진한 줄이 백 줄 안이어야 한다.

## 비목표

1. 동작 · 로그 · 기능의 변경. 부분 갱신도 WP-M3도 이번이 아니다 — 자리를 만들 뿐이다.
2. 절을 새 파일로 내는 것(덤프 · 배터리 · 포인터 · 받아쓰기 절). `main.zig`가 3,889줄인 것은 다음 후보다.
3. `supervise` · `doReload` · `doReloadTerminal` · `PointerWire`의 모양. 이미 함수다.
4. 호스트 검사를 더하는 것. 순수한 이동이라 새 검사가 볼 것이 없다 — 큰 파일 셋의 호스트 검사는 HANDOFF 후보 (3)이다.
5. 소개 페이지(`gh-pages` `data.js`). 기능이 아닌 내부 작업은 타임라인에서 건너뛴다(사용자 결정, 2026-10-25).

## 닫을 때(lead의 몫)

- 이 design의 `Status:`, `docs/guides/completed.md`의 한 행.
- `docs/decisions/project_main_split.md`와 `MEMORY.md` 한 줄, `HANDOFF.md`의 후보 (2) 지우기.
- lessons "핵심 파일"의 두 `main.zig` 줄 — `App` · `Boot`와 단계 이름으로. "감독 루프의 구조" 절은 그대로다.

## 관련

- `docs/decisions/project_screen_args.md` — terminal `main`의 argv 읽기가 `decode` 한 줄이 된 자리. 이번의 출발점.
- `docs/decisions/project_pointer_devices.md` — `PointerWire`, 바퀴 안의 상태를 struct로 묶은 선례(PD-M4).
- `docs/decisions/project_render_speed.md` — `output_pending` · 하한 · probe. 부분 갱신이 이 뒤에 들어올 자리.
- `docs/decisions/project_init_supervisor.md` — `supervise`가 반환하지 않는 이유, `main`의 스택이 프로세스 수명인 이유.
- `docs/decisions/feedback_execution_scope.md` — 구현은 Claude가, 사용자의 검토는 읽기. 결정 1(b)가 그 읽기의 도구다.
