# TARS Pointer Devices — Design

Date: 2026-10-05
Status: 끝났다(2026-10-05, PD-M0~M4 같은 날). M0~M3을 닫은 뒤 사용자의 결정으로 비목표 1(마우스 보고)을 결정 12 · PD-M4로
이어 했고 같은 날 닫았다. plan은 `-pd-m4.md`까지 다섯. plan은 `docs/plans/2026-10-05-tars-pointer-devices-pd-m0.md` · `-pd-m1.md` ·
`-pd-m2.md` · `-pd-m3.md`이고 각 끝의 "실측한 것" 절이 값이다. plan들이 바로잡은 전제는 결정 1 · 2 · 4 · 6 · 8 · 9 · 10과
위험 7 · 8에 덧붙여 두었다. 기억은 `docs/decisions/project_pointer_devices.md`.

사용자의 요청(2026-10-05)에서 시작한다.

> 1. 마우스 장치 지원: 마우스 포인터 및 인터렉션(드래그 선택) 2. 터치패드 역시 지원.

## 한 줄 요약

마우스와 터치패드가 화면에 화살표 하나를 움직인다. 누르고 끌면 copy mode의 선택이 그대로 만들어지고,
떼면 그 글자가 클립보드에 들어간다(`Cmd+C`와 같은 바이트). 다른 패널을 누르면 포커스가 그리로 가고,
휠은 포인터 아래 패널의 스크롤백을 움직인다. 터치패드는 그 위에 번역 층 하나를 더한다 — 한 손가락은
이동, 짧게 두드리면 클릭, 두 손가락을 세로로 밀면 휠이다.

```
PD-M0   USB 마우스를 꽂는다 / 뺀다      →  terminal이 열고 닫는다(부팅 뒤에 꽂아도). 화면은 그대로
        마우스를 움직인다              →  로그의 pointer> 좌표가 움직인다
PD-M1   마우스를 움직인다              →  화살표가 따라온다. 키를 치면 숨는다
        휠을 굴린다                    →  포인터 아래 패널이 세 줄씩 위아래로
PD-M2   다른 패널을 누른다              →  포커스가 그리로 간다
        글자 위를 누르고 끌다 뗀다       →  반전이 늘어나고, 떼는 순간 클립보드에. Cmd+V로 붙는다
PD-M3   노트북 터치패드                 →  한 손가락 이동 · 탭 클릭 · 두 손가락 스크롤
```

## 왜 마우스와 터치패드를 한 서브프로젝트로 묶나

둘은 같은 자리를 쓴다. 장치를 찾아 여는 자리, 포인터 좌표와 버튼 상태, 화면의 화살표, 누름 · 끎 · 뗌이
패널과 copy mode에 닿는 자리가 전부 같다. 터치패드가 더하는 것은 evdev의 절대 좌표 다중 접촉(ABS_MT)을
"상대 이동 · 버튼 · 휠"로 바꾸는 번역 층 하나다. 그 번역의 출력이 마우스 디코더의 출력과 같은 모양이면,
그 아래는 한 벌이다.

순서에도 이유가 있다. 터치패드는 QEMU에 없고(실측 7) 커널 드라이버도 지금 하나도 안 켜져 있다(실측 6).
마우스는 커널을 안 고쳐도 evdev가 되고 QEMU의 HMP로 움직일 수 있다(실측 1 · 2). 그래서 마우스로 공통
부분을 끝까지 만들고 게이트로 본 뒤에, 터치패드는 그 공통 부분 앞에 번역 층과 커널만 더한다.

## 모델

| 이름 | 무엇 | 사는 자리 |
|---|---|---|
| 장치 | `/dev/input/eventN` 하나. 마우스 또는 터치패드로 분류된 것만 연다 | `main.zig`의 장치 칸(최대 8) |
| 디코더 | 장치 하나의 raw `input_event`를 `SYN_REPORT` 단위의 `Frame`으로 바꾼다 | `pointer.zig`(마우스) · `touchpad.zig`(터치패드) |
| `Frame` | `dx` · `dy`(픽셀) · `wheel`(줄 단위로 바꾸기 전의 눈금) · 버튼 셋의 상태 | 두 디코더의 공통 출력 |
| 포인터 | 화면에 하나. 프레임버퍼 픽셀 좌표(clamp)와 장치 전체를 합친 버튼 상태 | `pointer.zig`의 `Pointer` |
| 제스처 | 누름 · 끎 · 뗌 · 휠을 "포커스 옮김 · 선택 시작 · 선택 늘림 · 복사 · 스크롤" 의도로 바꾼다 | `pointer.zig`의 `Gesture`(순수), 실행은 `main.zig` |

장치가 여럿이어도 포인터는 하나다. USB 마우스와 터치패드가 함께 있으면 둘이 같은 화살표를 움직인다.

### 동작 표

| 사람이 한 일 | 일어나는 일 | milestone |
|---|---|---|
| 포인터 장치를 움직인다 | 화살표가 나타나 따라온다 | M1 |
| PTY로 바이트가 나가는 키를 친다 | 화살표가 숨는다. 다음 움직임에 다시 나타난다 | M1 |
| 휠을 한 눈금 굴린다 | 포인터 아래 패널이 세 줄 움직인다. 포커스는 안 바뀐다 | M1 |
| 포커스가 아닌 패널을 누른다 | 그 패널로 포커스. 옛 패널의 copy mode는 닫힌다 | M2 |
| 글자 위를 누르고 다른 칸까지 끈다 | copy mode에 들어가 문자 단위 선택이 늘어난다(반전) | M2 |
| 끌다가 뗀다 | 선택을 클립보드에 넣고 copy mode를 나간다(`Cmd+C`와 같다) | M2 |
| 끌지 않고 뗀다(클릭) | 선택 없음. 그 패널이 copy mode였으면 닫힌다 | M2 |
| 여백 · 구분선 · 상태 줄을 누른다 | 아무 일도 없다 | M2 |
| 터치패드를 한 손가락으로 민다 · 두드린다 · 두 손가락으로 민다 | 이동 · 왼쪽 클릭 · 휠 | M3 |

## 결정

### 결정 1 — 포인터 장치는 terminal이 찾고, 부팅 뒤에 꽂힌 것도 inotify로 잡는다

> PD-M0이 바꾼 것 둘(2026-10-05). (1) inotify가 아니라 netlink uevent(`NETLINK_KOBJECT_UEVENT` 그룹 1)다. 게스트 커널에
> `INOTIFY_USER`가 없어 켰더니 `FSNOTIFY`가 따라 켜진 커널이 TCG에서 initramfs 풀기를 1.2초 늦춰 `install` 체인 부팅 7의
> 창을 닫았고 루트 게이트가 두 번 빨갰다(M0 plan 확정 7 · 실측 7~10). uevent는 커널 config가 필요 없고, 노드는 uevent가 올
> 때 이미 있다. (2) ioctl 넷을 손으로 짓지 않는다 — ZU-M1의 translate-c가 `EVIOCGBIT` 등을 inline fn으로 넘긴다(아래 실측
> 15는 `@cImport` 시절의 사실). `pointer_test`가 그 값을 C 헤더와 대조한다.

키보드는 PID 1이 부팅 때 찾아 `argv[4]`로 넘긴다(HD 결정 3). 포인터 장치도 그 모양을 따를지가 첫
물음이다.

| 후보 | 무엇 | 왜 아닌가 / 왜 이것인가 |
|---|---|---|
| (a) init이 부팅 때 찾아 argv로 넘긴다 | HD 결정 3의 모양 그대로. 핫플러그 없음 | 부팅 뒤에 꽂은 USB 마우스를 영영 못 쓴다. 그리고 부팅 때도 경합이 있다 — USB 열거는 비동기라서 init이 키보드를 3초까지 기다리는 것(`findKeyboardWaiting`)과 같은 일을 마우스에도 해야 하고, 마우스가 없는 기계는 그 3초를 매 부팅 낸다. 노트북에서 USB 마우스는 늘 꽂혀 있는 장치가 아니다 |
| (b) terminal이 `/dev/input`을 inotify로 보고, 연 fd에 ioctl로 성질을 물어 스스로 열고 닫는다 | 핫플러그 포함 | 고른다. 부팅 때 이미 있던 장치(처음 훑기)와 뒤에 생긴 장치(`IN_CREATE`)가 같은 함수를 지나고, 빠진 장치는 그 fd의 `POLLERR` · `POLLHUP` · `ENODEV`로 안다. PD-M3의 게이트(uinput으로 부팅 뒤에 만드는 가짜 터치패드, 결정 10)도 이것이 전제다 |
| (c) init이 inotify로 보고 새 fd를 소켓(`SCM_RIGHTS`)으로 terminal에 넘긴다 | 결정은 PID 1에 남는다 | init과 terminal 사이에 통로와 프로토콜이 하나 더 생긴다. 넘겨받은 fd를 terminal이 다시 분류해야 터치패드의 축 범위를 알 수 있으므로 분류도 결국 두 자리가 된다 |
| (d) init이 장치가 생길 때마다 terminal을 다시 띄운다 | 감독 루프가 이미 있다 | 셸과 스크롤백이 전부 사라진다 |

(b)는 CP-M2 · HD 결정 3이 정한 "하드웨어를 살펴 고르는 일은 PID 1이 하고 terminal은 실행만 한다"를
포인터에 한해 바꾼다. 그 규칙의 이유는 "파서 · 탐색기가 두 벌이 되면 두 프로세스가 다른 답을 얻는다"였다.
포인터 장치는 terminal만 쓰므로 두 벌이 생기지 않는다 — init은 포인터를 찾지 않는다. 그리고 그 규칙이
만들어질 때 핫플러그는 비목표였다(HD 비목표). 계속 살아 있으면서 장치의 등장과 소멸을 지켜볼 수 있는
프로세스는 그 장치를 읽는 terminal이다.

키보드 경로는 그대로 둔다. init의 `resolveKeyboard`와 `argv[4]`를 안 건드린다 — HD의 결정을 되돌리지
않는다. 키보드 핫플러그는 비목표 9이고, 이 결정이 만드는 inotify 기계가 그때의 재료가 된다.

성질은 sysfs가 아니라 연 fd의 ioctl로 읽는다. HD 결정 1은 sysfs를 골랐는데 그 이유는 HD 조사 6 — `EVIOCGBIT`이
인자를 받는 C 매크로라 translate-c로 안 넘어온다는 것이었다. 지금은 두 가지가 다르다. 첫째, 터치패드의
축 범위(min · max · resolution)는 sysfs에 없고 `EVIOCGABS`로만 읽힌다. 어차피 ioctl을 하나 손으로 짜야 하면,
같은 장치의 성질을 두 출처(sysfs 비트맵 + ioctl)에서 읽을 이유가 없다. 둘째, ioctl 번호를 비트 연산으로
손수 만드는 선례가 `drm.zig`의 `drmIowr`에 있다. `EVIOCGBIT(ev, len)` · `EVIOCGPROP(len)` ·
`EVIOCGABS(abs)` · `EVIOCGNAME(len)` 넷을 같은 모양으로 짓는다(`_IOC_READ`, 타입 `'E'`). `struct
input_absinfo`는 구조체라 `c_input` 번역으로 넘어온다(`project_zig_c_uapi_rule`).

watch를 먼저 걸고 그다음에 디렉터리를 훑는다. 순서가 반대면 훑은 뒤 watch를 걸기 전에 생긴 장치를 놓친다.
같은 경로가 두 번 들어오면(훑기와 `IN_CREATE`가 겹친 경우) 이미 연 경로는 건너뛴다. 이름이 `event`로
시작하지 않는 노드(`mice` · `mouseN`)는 보지 않는다 — `INPUT_MOUSEDEV`가 꺼져 있어 생기지도 않는다(실측 6).

빠진 장치는 fd 쪽에서 안다. `IN_DELETE`는 보지 않는다. poll이 그 fd에 `POLLERR`나 `POLLHUP`을 돌려주거나
read가 `ENODEV`로 실패하면 닫고 칸을 비운다. 이것을 빠뜨리면 poll이 그 fd에 대해 매 바퀴 즉시 돌아와
terminal이 CPU를 다 쓴다 — 결정 10의 검사가 `close` 줄로 본다.

### 결정 2 — 분류는 순수 함수이고, 마우스 · 터치패드 · 그 밖의 셋으로 가른다

```zig
pub const Kind = enum { mouse, touchpad, none };
pub fn classify(caps: Caps) Kind;   // Caps = ev · key · rel · abs · prop 비트맵 다섯
```

| 종류 | 조건 | 예 |
|---|---|---|
| `mouse` | `EV_REL`에 `REL_X` · `REL_Y`, `EV_KEY`에 `BTN_LEFT` | QEMU USB Mouse(실측 1) · PS/2 마우스 · ThinkPad TrackPoint · 모드 전환 전의 I2C-HID 터치패드 |
| `touchpad` | `EV_ABS`에 `ABS_MT_POSITION_X` · `ABS_MT_POSITION_Y`(없으면 `ABS_X` · `ABS_Y`), 그리고 `INPUT_PROP_POINTER` 또는 `EV_KEY`의 `BTN_TOOL_FINGER` | hid-multitouch · psmouse synaptics/elantech · RMI4가 내는 노드 |
| `none` | 그 밖의 전부 | 키보드 · 전원 버튼 · usb-tablet(실측 3) · 터치스크린(`INPUT_PROP_DIRECT`) |

판정은 HD 결정 2처럼 이름이 아니라 capability다. `INPUT_PROP_DIRECT`가 서 있으면 다른 조건과 상관없이
`none`이다 — 터치스크린은 손가락이 닿은 자리가 곧 좌표인 장치라 터치패드의 상대 이동 번역을 받으면 틀린
동작을 한다(비목표 4). usb-tablet은 `PROP=0`에 `ABS_X` · `ABS_Y`만 있고 `BTN_TOOL_FINGER`가 없어
`none`이다(실측 3).

키보드와 마우스를 한 노드로 내는 장치(무선 수신기 일부)는 init이 키보드로 열고 terminal이 마우스로 또
연다. EVIOCGRAB을 아무도 안 하므로 두 fd가 같은 이벤트를 다 받는다. 키보드 쪽 `readKeys`는 `EV_KEY`만
보는데 `BTN_LEFT`(0x110)도 `EV_KEY`라 `handleKey`에 닿는다 — 키맵 밖의 코드라 아무것도 안 만든다는 것을
`input_test`에 검사 하나로 둔다. 포인터 쪽은 `BTN_*`만 보고 `KEY_*`를 버린다.

분류 함수와 비트맵 읽기(`bitSet`)는 순수하게 두고 호스트에서 본다. ioctl 비트맵은 바이트 배열에 낮은
번호부터 담기므로 sysfs의 "높은 워드가 앞" 형식(HD 결정 2)과 다르다 — init의 `bitSet`을 옮겨 오지 않고
새로 짓는다. 둘을 같은 함수로 만들면 한쪽 형식에서 반드시 틀린다.

### 결정 3 — 포인터 이벤트는 `input.zig`의 `Action`에 합류하지 않고, 층 셋으로 간다

| 후보 | 왜 아닌가 / 왜 이것인가 |
|---|---|
| `input.Action`에 `pointer` variant를 더하고 `readKeys`가 포인터 장치도 읽는다 | `input.zig`는 "evdev 코드를 셸이 아는 바이트로 번역한다"가 책임이다. 포인터 이벤트는 셸로 가는 바이트가 없고, 좌표를 패널 · 셀로 바꾸려면 `layout`과 `vt`를 알아야 하는데 `input.zig`는 `vt.zig`를 import하지 않는다(IP 결정 6). `Keys`에 좌표를 실으면 그 구조체가 두 장치 계열의 합이 된다 |
| 디코딩부터 패널 처리까지 전부 `main.zig`에 | 판단(언제가 클릭이고 언제가 끌기인가, 휠 눈금 몇 줄)이 시스템 콜과 섞여 호스트에서 못 본다 |
| 층 셋 — 디코더(순수) → 포인터 · 제스처(순수) → `main.zig`의 실행 | 고른다. 위 둘은 `pointer_test` · `touchpad_test`가 부팅 없이 보고, `main.zig`는 의도를 실행하는 배선만 한다 |

층의 모양은 이렇다(이름은 plan이 확정한다).

```zig
// pointer.zig — 순수. 시스템 콜 없음, vt · layout import 없음
pub const Frame = struct { dx: i32 = 0, dy: i32 = 0, wheel: i32 = 0, buttons: Buttons = .{} };
pub const Mouse = struct { pub fn feed(self: *Mouse, ev_type: u16, code: u16, value: i32) ?Frame; };
pub const Pointer = struct {
    x: u32, y: u32, w: u32, h: u32,        // 프레임버퍼 크기 안에 clamp
    pub fn apply(self: *Pointer, dev: u3, f: Frame) Events;  // 장치별 버튼을 합쳐 눌림 · 뗌의 전이를 낸다
};
pub const Hit = struct { leaf: u4, col: u16, row: u16 };     // main.zig가 계산해 넣는다
pub const Gesture = struct {
    pub fn press(self: *Gesture, hit: ?Hit, focus: u4) Intents;
    pub fn motion(self: *Gesture, clamped: ?Hit) Intents;
    pub fn release(self: *Gesture) Intents;
};
pub const Intent = union(enum) { focus: u4, select_start: Hit, select_to: Hit, copy, cancel, scroll: Scroll };
```

디코더는 `SYN_REPORT`를 만나야 `Frame`을 낸다. 그 사이의 `REL_X` · `REL_Y`는 더해 둔다. `SYN_DROPPED`를
만나면 다음 `SYN_REPORT`까지 버린다(TF 결정 6이 적은 재동기화. 마우스는 버튼 상태만 잃을 수 있고, 다음
누름이 그것을 고친다). `EV_MSC`(`MSC_SCAN`, 실측 2)는 버린다.

`main.zig`의 의도 switch는 `else` 없이 닫는다. `Copy` · `Pane`의 규율과 같다 — variant를 하나 더하면
컴파일러가 배선할 자리를 알려 준다.

poll 배열은 키보드 하나, inotify 하나, 포인터 장치 최대 8, PTY 최대 72다. 지금 `fd_panes[nfds - 1]`이 "키보드
다음부터 PTY"를 전제하므로, 그 자리의 오프셋이 바뀌는 것을 plan이 짚는다. 포인터 분기는 키보드 분기 뒤,
PTY 분기 앞이다. 한 poll 회차에 들어온 포인터 이벤트는 전부 처리한 뒤 프레임을 하나만 그린다 — 이벤트마다
그리면 마우스의 보고 빈도(수백 Hz)가 그대로 프레임 수가 된다.

장치가 여럿일 때 버튼은 장치별로 따로 들고, 포인터의 버튼은 그 합(OR)이다. 눌림과 뗌은 합이 바뀔 때만
나온다. 마우스로 누른 채 터치패드를 두드려도 뗌이 두 번 나오지 않는다.

### 결정 4 — 커서는 작은 화살표이고, 움직임만 있는 프레임은 다시 그리지 않고 그 자리만 고친다

> PD-M1이 정한 것 둘(lead, 2026-10-05). 보이는 조건 3을 끄는 자리는 `keys.bytes`가 PTY에 나가는 블록 하나다 — `Cmd+V`와
> 터미널 질의의 답은 숨기지 않는다. 그리고 마지막 장치가 빠지면 조건 2(움직였다)도 꺼져, 다시 꽂은 마우스는 움직여야 보인다.
> 전체 프레임에서는 저장한 픽셀을 되돌리지 않고 버린다(`fill`이 이미 지웠다). 화살표는 테두리 49 + 안쪽 69 = `ink` 118.

모양은 12 × 19 픽셀 안의 왼쪽 위 끝이 뾰족한 화살표이고, 끝이 포인터 좌표(hotspot)다. 색은 전용 상수
둘이다.

| 상수 | 값(제안) | 쓰임 |
|---|---|---|
| `POINTER_FILL` | `0x00FCFCF4` | 안쪽 |
| `POINTER_EDGE` | `0x00040810` | 테두리 한 픽셀. 밝은 글자 위에서도 보인다 |

전용 색인 이유는 CI 결정 3 · WP의 `SEPARATOR`와 같다 — 게이트가 그 색만 세어 "그 자리에 그렸는가"를 본다.
두 값은 지금의 색 상수(`MARGIN_COLOR` · `STATUS_*` · `SEPARATOR` · `CURSOR_COLOR` · `MATCH_BG` ·
`CURRENT_BG`)와 xterm 256색 팔레트(6단 큐브 `00 5f 87 af d7 ff`, 회색 `08`부터 10씩)에 없는 것을 골랐다.
plan이 `rg '0x00[0-9A-F]{6}'`로 한 번 더 대조한다.

그리는 방법이 이 결정의 본론이다.

| 후보 | 왜 아닌가 / 왜 이것인가 |
|---|---|
| (a) 움직일 때마다 `needs_redraw`를 켜고 화면 전체를 다시 그린다. 화살표는 `renderFinish`의 `present` 앞 | 렌더러에 부분 갱신이 없다(lessons 이월 숙제). 프레임마다 `fill`이 84.7%인 렌더(RC-M0)가 마우스를 움직이는 동안 쉬지 않고 돈다. 그리고 프레임마다 `screen>` · `style>` · `pane>` 등 덤프가 찍힌다 — 게이트에서 덤프 줄 수가 움직임 수만큼 늘고 `wait_for_screen`이 보는 로그가 커진다 |
| (b) 하드웨어 커서 plane(`DRM_IOCTL_MODE_CURSOR`) | 실기의 simpledrm(RM 결정)에는 커서 plane이 없다. 게이트의 virtio-gpu와 실기가 다른 경로를 타게 된다 |
| (c) save-under. 화살표 밑의 픽셀을 저장해 두고, 움직임만 있는 회차에는 저장한 픽셀을 되돌리고 · 새 자리 밑을 저장하고 · 그리고 · `present` | 고른다. 움직임만 있는 회차는 렌더도 덤프도 없다. 전체 프레임(셀이 바뀐 회차)은 지금처럼 그리고, `present` 바로 앞에서 새로 저장하고 그린다 |

(c)의 산수는 `image.zig`처럼 대상이 `anytype`인 순수 함수로 둔다. `pointer_test`가 `u32` 배열에 그리고 되돌려
"되돌린 뒤 배열이 처음과 같다"를 본다. 프레임버퍼 가장자리에서 화살표가 잘리는 것도 여기서 막는다 —
`setPixel`에 범위 검사가 없다.

전체 프레임에서 화살표는 `present` 앞에 그린다. 그래서 `present` 뒤의 덤프가 화살표 픽셀을 읽는다. 이것을
받아들인다. 화살표가 보이는 것은 사람이 포인터를 움직인 뒤뿐이고(아래), 기존 열여덟 체인은 포인터를 안
움직이므로 그 체인들의 덤프는 한 픽셀도 안 바뀐다. 덤프 뒤에 그리고 `present`를 한 번 더 부르는 안은
버렸다 — 단일 버퍼라 두 `present` 사이에 화살표 없는 화면이 보이고, 출력이 흐르는 동안 화살표가 깜박인다.

보이는 조건은 셋이다.

1. 열린 포인터 장치가 하나 이상이다.
2. 열린 뒤 포인터가 움직였거나 버튼이 눌렸다. 처음에는 안 보인다. 좌표의 출발은 프레임버퍼 가운데다.
3. 그 뒤로 키보드가 PTY에 바이트를 보내지 않았다. 보내면 숨고, 다음 움직임에 다시 보인다.

3은 lead의 방향(자동 숨김 비목표)과 다르다. 비목표로 둔 것은 "몇 초 안 움직이면 숨는다"이고, 그것은
타이머가 필요하다(poll이 `-1`로 기다린다). 3은 타이머가 없다 — 키를 친 회차에 플래그 하나를 끄는 것이다.
넣는 이유는 화살표가 글자 칸 위에 앉아 있기 때문이다. 셸에 치는 동안 화살표가 그 줄의 글자를 가리면
사람이 마우스를 일부러 치워야 한다. macOS 터미널들도 치는 동안 화살표를 숨긴다. 2와 3이 함께 있어서,
기존 체인이 포인터 장치를 갖게 되어도(PD-M3의 PS/2 마우스, 결정 9) 화면이 안 바뀐다.

### 결정 5 — 픽셀은 `main.zig`가 격자 칸으로, 칸은 `layout.zig`가 잎으로 바꾼다

변환은 두 단계다.

1. 픽셀 → 격자 칸. `main.zig`의 작은 함수다. `GRID_X` · `GRID_Y` · `CELL_W` · `ROW_HEIGHT`가 거기 있다.
   `x < GRID_X`이거나 격자 오른쪽 · 아래 끝을 넘으면 null(여백 · 상태 줄).
2. 격자 칸 → 잎과 패널 안의 칸. `layout.Tree.hit(whole, col, row) ?Hit`을 새로 둔다. 순수하고
   `layout_test`가 본다. 구분선 칸은 어느 잎의 사각형에도 안 들어가므로 null이다.

역변환이 `paneOrigin`과 같은 상수를 쓰는 것이 요점이다. 다른 상수를 쓰면 화살표 끝과 선택이 시작되는 칸이
한 칸 어긋나고, 그 어긋남은 글자만 보는 판정으로는 안 보인다. 결정 10의 검사가 셀 가운데가 아니라 셀
왼쪽 위 끝 픽셀과 오른쪽 아래 끝 픽셀을 눌러 경계를 본다.

가장자리 처리.

| 자리 | 누름 | 끄는 중 |
|---|---|---|
| 여백 · 상태 줄 | 아무 일도 없다. 포커스도 안 바뀐다 | — |
| 구분선 | 아무 일도 없다 | — |
| 누른 패널 밖으로 끌어 나감 | — | 선택 끝은 누른 패널의 사각형 안으로 clamp한다. 이웃 패널로 넘어가지 않는다. 위 · 아래로 나가도 뷰포트가 따라 움직이지 않는다(비목표 3) |
| 다른 워크스페이스 | 안 보이므로 닿을 수 없다 | — |

clamp는 `Gesture`가 "누른 잎"을 기억하고, `main.zig`가 끄는 동안의 칸을 그 잎의 사각형으로 잘라 넘기는
것으로 한다. 다른 패널 위로 끌어도 `Hit.leaf`는 누른 잎이다.

### 결정 6 — 드래그 선택은 copy mode의 기계를 그대로 쓰고, 모드의 두 사본을 함께 옮긴다

선택의 표현은 copy mode와 같다. ghostty의 tracked selection이 앵커를 들고 `copy_cursor`가 끝을 든다
(CM 결정 5). 그래서 반전은 `cells()`가 지금처럼 그리고, 끌어 만든 선택에서 `y`를 쳐도 같은 결과가 나온다.

`vt.Screen`에 공개 함수 둘을 더한다. 지금의 `copyPin` · `copyApply`는 private이고, `copySelect`는
`copy_cursor`가 있어야 돈다.

- `copyEnterAt(x, y)` — copy mode에 들어가며 커서를 그 칸에 두고 문자 단위 선택을 시작한다(`copyEnter` +
  `copy_cursor = (x, y)` + `copySelect(.char)`).
- `copyPointTo(x, y)` — 커서를 그 칸으로 옮기고 `copyApply(앵커, 그 칸)`. 칸이 같으면 아무것도 안 한다.

| 순간 | 일 |
|---|---|
| 누름 | 위치만 기억한다(잎 · 칸). copy mode에 아직 안 들어간다. 그 패널이 키보드 copy mode였으면 닫는다(복사 없이) |
| 처음으로 다른 칸에 닿음 | `copyEnterAt(누른 칸)` 뒤 `copyPointTo(지금 칸)`. 상태 줄에 `COPY`가 뜬다 |
| 계속 끎 | 칸이 바뀔 때마다 `copyPointTo` |
| 뗌(끈 뒤) | `copyYank()` — 클립보드에 넣고 모드를 나간다. `clip>` 줄이 `Cmd+C`와 같은 모양으로 찍힌다 |
| 뗌(안 끈 채) | 아무 일도 없다 |

copy mode에 누름이 아니라 첫 칸 이동에 들어가는 이유는 클릭 때문이다. 누름에 들어가면 모든 클릭이 한
프레임 동안 `COPY`를 띄우고 copy 커서를 그렸다가 지운다. 그리고 떼는 순간 앵커와 끝이 같은 한 칸 선택이
남는데, 그것을 복사할지 버릴지를 따로 정해야 한다.

입력 모드는 두 곳에 있다. `input.State.mode`(키를 어떻게 해석하나, CM 결정 1)와 `vt.Screen.copy_cursor`(화면이
모드인가)다. 키보드 경로는 둘을 같은 키에서 함께 바꾼다(`Cmd+Shift+C`가 `mode = .copy`를 세우고 `.enter`를
낸다). 포인터 경로가 화면 쪽만 바꾸면, 끌어서 copy mode에 들어간 뒤 친 `j`가 셸로 가거나 복사한 뒤 친 글자가
copy 표에 삼켜진다. 그래서 `input.State`에 공개 함수 하나를 둔다.

```zig
/// 포인터가 모드를 바꾼다. 조합 중인 한글은 normal이었으면 확정해 돌려주고(호출부가 옛 포커스의
/// PTY에 쓴다), find였으면 버린다(Esc와 같은 뜻). 그리고 mode를 to로 둔다.
pub fn pointerMode(self: *State, to: Mode) []const u8;
```

조합 중인 한글을 이렇게 다루는 이유는 HI 결정 6 · WP 결정 4와 같다. 칠 때의 패널로 가야 맞는 글자이고,
검색 프롬프트의 조합은 검색어지 셸 입력이 아니다. 확정분을 PTY에 쓴 뒤에 포커스를 옮긴다.

키보드 copy mode와 섞일 때.

| 상황 | 일 |
|---|---|
| 키보드 copy mode인 패널을 누른다 | copy mode를 닫는다(복사 없이). 그다음 누름으로 다룬다. 선택의 주인은 한 번에 하나다 |
| 끄는 중에 `Esc` | 키보드 경로가 모드를 닫는다. 뗄 때까지의 움직임은 무시한다(`Gesture`가 copy가 꺼진 것을 본다) |
| 끄는 중에 `y` · `Cmd+C` | 키보드 경로가 복사하고 닫는다. 뗌은 아무것도 안 한다 |
| 끄는 중에 다른 키 | copy 표가 삼킨다(CM 결정 3). 셸로 안 간다 |
| 검색 프롬프트가 열린 패널을 누른다 | 프롬프트와 모드를 닫는다(`copyExit`이 `findCancel`까지 한다). 조합은 버린다 |

뗀 뒤에는 반전이 남지 않는다. `copyYank`가 `copyExit`을 부르기 때문이다. iTerm2는 뗀 뒤에도 반전을 남기는데,
그러려면 "copy mode 밖의 선택"이라는 상태가 하나 더 생기고 그 선택을 언제 지우는지(출력이 오면? 키를
치면?)를 정해야 한다. 비목표 5로 둔다. 무엇을 복사했는지는 `Cmd+V`로 보면 된다.

포커스를 옮기는 클릭은 그 패널 안에서 끌기도 시작할 수 있다. 다른 패널을 누르고 그대로 끌면 포커스가
옮겨 가고 그 패널에서 선택이 시작된다. 누름이 포커스 옮김과 위치 기억을 함께 한다.

### 결정 7 — 휠 한 눈금은 세 줄이고, 포인터 아래 패널을 움직인다

| 물음 | 정한 것 | 왜 |
|---|---|---|
| 어느 패널 | 포인터 아래 패널. 포커스는 안 바뀐다 | 옆 패널의 로그를 올려 보며 이쪽에서 계속 치는 것이 휠의 쓰임이다. 여백 · 구분선 위에서는 아무 일도 없다 |
| 몇 줄 | 한 눈금(`REL_WHEEL` 1) = 3줄. 상수 `WHEEL_ROWS` | xterm 계열 터미널이 흔히 쓰는 값이다. 설정은 비목표 7 |
| 방향 | `REL_WHEEL`이 양수(휠을 앞으로 밂)면 위로, 즉 `scrollByRows(-3)` | 커널의 약속(양수 = 위)과 리눅스 · 윈도우 터미널의 기본이다. macOS의 "자연스러운 스크롤"과는 반대다 — 사용자가 고를 자리이고 그때 `tars.conf` 항목이 된다(비목표 7) |
| `REL_WHEEL_HI_RES` | 버린다 | QEMU 마우스가 둘 다 낸다(실측 1). 커널은 고해상도 휠에서 120 단위마다 `REL_WHEEL`도 내므로, 둘 다 세면 두 번 움직인다 |
| 키보드 copy mode인 패널 | 휠을 무시한다 | copy 커서는 뷰포트 좌표다. 뷰포트를 밖에서 밀면 커서가 다른 글자를 가리키는데 선택은 안 따라온다. 키보드 copy mode는 자기 이동으로 뷰포트를 민다(CM 결정 4) |
| 끄는 중 | 휠이 누른 패널을 움직이고, 선택 끝을 지금 포인터 칸으로 다시 맞춘다 | 한 화면보다 긴 선택을 만드는 길이다. 가장자리 자동 스크롤(비목표 3)의 대신이다 |

출력이 도착하면 그 패널이 바닥으로 돌아가는 것(`scrollToBottom`, copy mode 중 억제)은 그대로다. `PageUp`으로
올라간 뒤와 같다.

### 결정 8 — 터치패드 번역은 이동 · 탭 · 두 손가락 세로 스크롤 · 물리 버튼까지다

`touchpad.zig`는 순수 상태 기계다. 입력은 raw `input_event`와 그 장치의 축 정보(`EVIOCGABS`의 min · max ·
resolution)이고 출력은 결정 3의 `Frame`이다. 마우스 디코더와 출력이 같으므로 `Pointer` · `Gesture` 아래는
터치패드를 모른다.

| 하는 것 | 어떻게 |
|---|---|
| 접촉 추적 | MT 프로토콜 B. `ABS_MT_SLOT`으로 칸을 고르고, `ABS_MT_TRACKING_ID`가 -1이면 그 손가락이 떨어졌다. 손가락 수는 `BTN_TOOL_FINGER` · `DOUBLETAP` · `TRIPLETAP`에서 읽는다 — 칸보다 손가락을 더 세는 장치가 있다 |
| 한 손가락 이동 | 그 접촉의 프레임 사이 변화량을 픽셀로. 배율은 "패드 가로 전체 = 프레임버퍼 가로 전체"를 출발값으로 하고, 두 축의 resolution이 0이 아니면 세로를 같은 mm당 픽셀로 맞춘다. 가속 없음(비목표 6) |
| 탭 → 왼쪽 클릭 | 한 손가락 접촉이 짧고(출발값 180ms) 움직임이 작으면(출발값 축 범위의 2%) 뗄 때 누름과 뗌을 한 `Frame` 쌍으로 낸다. 시각은 `ev.time`이다 — 타이머가 없어도 된다 |
| 두 손가락 세로 → 휠 | 두 접촉의 평균 세로 변화를 픽셀로 바꿔 모으고, `ROW_HEIGHT`마다 한 줄씩 낸다. 방향은 손가락을 따라 내용이 움직이는 쪽(macOS 트랙패드 기본)이다. 두 손가락인 동안 포인터는 안 움직인다 |
| 물리 버튼 | clickpad의 `BTN_LEFT`를 그대로 통과시킨다. 버튼이 눌린 동안은 두 손가락이어도 스크롤로 안 가고, 마지막에 닿은 손가락이 포인터를 움직인다 — 엄지로 누르고 검지로 끄는 동작 |
| `SYN_DROPPED` | 모든 접촉을 뗀 것으로 하고 다음 `SYN_REPORT`부터 새로 센다. `EVIOCGMTSLOTS`로 다시 맞추지 않는다 |

출발값 셋(180ms · 2% · 배율)은 재지 않은 제안이다. 실기 없이 정할 수 없는 값이라 plan은 상수로 두고, 실기에서
사람이 손으로 본 뒤 고친다(위험 3).

안 하는 것은 비목표 6에 모았다 — 가속 · 손바닥 거부 · 치는 동안 끄기 · 가장자리 스크롤 · 세 손가락 · 집기 ·
관성 스크롤 · 두 손가락 탭 오른쪽 클릭 · 탭 뒤 끌기 · 반쯤 MT인 장치(`INPUT_PROP_SEMI_MT`)의 보정.

### 결정 9 — 커널은 노트북 터치패드의 세 경로를 켜고, 심볼 · 드라이버 등록 · 실제 부팅 하나로 본다

> PD-M3이 바꾼 것(2026-10-05, M3 plan "design과 다르게 적은 것"). `MOUSE_PS2_ELANTECH`와 RMI4 하위(F03 · F3A)는 기본값이
> 없어 명시로 켠다 · AMD(`X86_AMD_PLATFORM_DEVICE`)와 옛 Intel(`X86_INTEL_LPSS`) 플랫폼 심볼을 더했다 · Intel THC는 6.18에
> 있어 QuickI2C만 켠다(QuickSPI는 비목표) · `HID_RMI` · `I2C_PIIX4`는 켜지 않는다 · 심볼은 41개, bzImage +323,584바이트.
> 검증 셋째 겹의 psmouse alias는 modinfo에 마지막 serio 표만 남아 판정 글자로 못 쓴다(pinctrl의 ACPI id로 대신). 검사 20은
> 부팅 A에 두면 M0 · M1의 판정 셋이 깨져 부팅 B로 옮기고 부팅 A는 `i8042.noaux`로 띄운다.

실제 노트북 터치패드는 지금 커널에서 노드조차 안 생긴다(실측 6). 경로가 셋이고 셋 다 켠다.

| 경로 | 기계 | 켜는 심볼 |
|---|---|---|
| PS/2 | i8042에 붙은 Synaptics · Elantech · ALPS · 일부 Focaltech, ThinkPad TrackPoint | `INPUT_MOUSE` · `MOUSE_PS2`(하위 프로토콜 `MOUSE_PS2_SYNAPTICS` · `ELANTECH` · `ALPS` · `BYD` · `FOCALTECH` · `TRACKPOINT`는 기본값으로 따라온다 — plan이 `olddefconfig` 뒤 값으로 확인) |
| SMBus(RMI4 · Elan) | 근래의 ThinkPad 등 Synaptics InterTouch, Elan의 SMBus 패드 | `RMI4_CORE` · `RMI4_SMB` · `RMI4_F11` · `RMI4_F12` · `RMI4_F30` · `I2C_I801` · `MOUSE_ELAN_I2C` · `MOUSE_ELAN_I2C_I2C` · `MOUSE_ELAN_I2C_SMBUS` |
| I2C-HID | 2015년 이후 노트북 대부분(Precision Touchpad) | `I2C_HID_ACPI` · `HID_MULTITOUCH` · `I2C_DESIGNWARE_PLATFORM` · `MFD_INTEL_LPSS_PCI` · `MFD_INTEL_LPSS_ACPI` · `GPIOLIB` · `PINCTRL` · `PINCTRL_INTEL`과 세대별 하위(`SUNRISEPOINT` · `CANNONLAKE` · `ICELAKE` · `TIGERLAKE` · `ALDERLAKE` · `METEORLAKE` 등) · `PINCTRL_AMD` |

게이트용 하나를 더 켠다. `INPUT_MISC` · `INPUT_UINPUT`(결정 10). 게스트의 root가 입력 장치를 만들 수 있게 되는데,
root는 이미 무엇이든 할 수 있다.

켜지 않는 것.

- `HID_APPLE` · `HID_MAGICMOUSE` · `MOUSE_BCM5974` · `KEYBOARD_APPLESPI`. lessons 이월 숙제가 적은 대로 `HID_APPLE`은
  Apple 키보드의 fn 키를 커널에서 바꿔 `keyboard=apple`과 부딪칠 수 있다. Intel MacBook의 트랙패드(bcm5974 ·
  applespi)는 "일반 x86_64 노트북"(RM)의 범위 밖이다(비목표 10).
- `INPUT_MOUSEDEV`. `/dev/input/mice`는 evdev 이전의 통로이고 우리는 evdev만 읽는다.
- Intel THC(최신 세대의 터치 컨트롤러). 6.18에 있는지, 어느 기계가 쓰는지 재지 않았다 — plan이 커널 소스에서
  본다.

크기는 재지 않았다. plan이 `bzImage` 크기 변화를 잰다. `I2C_I801` · `PINCTRL` 계열은 터치패드 말고도 다른 장치가
붙는 길이라 크기가 기대보다 클 수 있다.

검증은 세 겹이다. UW 결정 3의 방식(QEMU에 없는 장치는 심볼과 표로 본다)에 실제 부팅 하나를 더한다.

1. `kernel/.config`에 위 심볼이 `=y`인가. `wifi/check.sh` 검사 1과 같은 loop.
2. 드라이버가 실제로 등록됐는가. 게스트 셸에 `ls /sys/bus/i2c/drivers /sys/bus/hid/drivers /sys/bus/serio/drivers
   /sys/bus/rmi4/drivers`를 쳐서 `i2c_hid_acpi` · `hid-multitouch` · `psmouse` · `rmi4_smbus` · `elan_i2c`가 화면에
   나오는지 본다. 심볼은 켜졌는데 의존 관계로 빌드에서 빠진 경우를 잡는다.
3. `modules.builtin.modinfo`에서 대표 alias(`i2c_hid_acpi`의 `PNP0C50` ACPI id, `hid_multitouch`의 HID 그룹)를 본다.
   UW 검사의 모양이다. 정확한 문자열은 plan이 그 파일에서 뽑는다.

그리고 `MOUSE_PS2`는 QEMU에서 진짜로 돈다. QEMU pc 머신은 PS/2 마우스를 늘 갖고 있다(실측 4). psmouse가 그것을
`ImPS/2` 계열 마우스로 등록하면 terminal이 `kind=mouse`로 연다 — 그 줄을 본다. synaptics 프로토콜 자체는 QEMU에
없으므로 이 부팅이 보는 것은 "psmouse가 i8042 AUX를 잡는다"까지다.

이것의 부작용 하나. PD-M3부터 pc 머신의 모든 체인에 포인터 장치가 하나 생기고, 모든 terminal이 그것을 연다.
결정 4의 보이는 조건 2 때문에 화면은 안 바뀐다. `pointer> open` 줄이 로그에 하나 늘 뿐이고, 기존 체인에 그 줄을
세는 검사는 없다. psmouse의 탐지가 부팅을 늦추는지는 재지 않았다 — plan이 `render` 체인의 첫 `screen>`까지의
시간을 전후로 잰다.

### 결정 10 — 게이트는 새 체인 `pointer/check.sh` 하나(열아홉번째), 부팅 둘

> 끝난 모양(2026-10-05): 부팅 A(`-usb -device usb-mouse,id=pdboot`, `i8042.noaux`, 포트 45488)와 부팅 B(설정 디스크 `tars-pd`에
> `tp-replay`, 포트 45489). 검사는 M0 7 · M1 5 · M2 9 · M3 7이고 mutation은 4 · 5 · 4 · 4였다. M0 mutation "REL_Y 부호"는
> 그대로, M3의 "`INPUT_PROP_POINTER`를 안 본다"는 잡히지 않는 mutant라(`BTN_TOOL_FINGER`로도 터치패드다) "터치패드를 디코더에
> 잇지 않는다"와 "세로 resolution 보정 제거"로 바꿨다.

기존 체인에 끼우지 않는다. `copy` · `pane` 체인의 판정은 포인터가 없는 화면을 전제하고, 이 체인은 화살표가 보이는
프레임을 일부러 만든다.

부팅 A(PD-M0~M2)는 `-usb -device usb-mouse`로 뜬다(실측 1). 포인터는 HMP `mouse_move dx dy [dz]` ·
`mouse_button N`으로 움직인다(실측 2, `-display none`에서도 간다). 핫플러그는 HMP `device_add usb-mouse,id=m2` ·
`device_del m2`로 본다 — 이것이 QEMU에서 되는지, 빠진 뒤 HMP의 대상 마우스가 원래 것으로 돌아가는지는 재지 않았다,
plan이 잰다. 부팅 B(PD-M3)는 설정 디스크를 하나 붙여 uinput 되감기 도구를 싣는다.

로그 줄(새 줄 `pointer>`).

```
terminal: pointer> open /dev/input/event2 kind=mouse name=QEMU QEMU USB Mouse shown=0
terminal: pointer> skip /dev/input/event1 kind=none
terminal: pointer> at x=650 y=405 buttons=0 wheel=0 shown=1 ink=163
terminal: pointer> press leaf=0 row=3 col=10
terminal: pointer> release drag=1
terminal: pointer> close /dev/input/event5
```

`at` 줄은 포인터 이벤트가 있던 poll 회차마다 하나다. `ink`는 `POINTER_FILL` · `POINTER_EDGE` 픽셀 수인데, 세는
범위는 프레임버퍼 전체가 아니라 직전 화살표 자리와 지금 화살표 자리의 사각형 둘(각 12 × 19)이다 — 화살표가 다
보이면 모양이 정하는 상수이고, 숨으면 0이고, 옛 자리를 못 지웠으면 상수보다 크다. 전체를 세지 않는 이유는 이 줄이
움직임 회차마다 찍히기 때문이다. `pane>`의 `sep ink`는 전체(1280 × 800 = 약 100만 픽셀 되읽기)를 세지만 패널이
바뀐 프레임에만 찍고, 실기의 프레임버퍼는 캐시가 없는 메모리라 되읽기가 쓰기보다 훨씬 느리다. 자국은 save-under가
되돌리지 못한 옛 자리에 남으므로 사각형 둘 안에서 잡힌다. 두 자리가 겹치면 합집합을 한 번만 센다. (설계자의 초안은
전체를 세고 plan이 비용을 재는 것이었는데, lead가 비용이 확실하다고 보고 여기서 정했다.)

검사(번호는 plan이 확정한다).

| 검사 | 친다 | 본다 | milestone |
|---|---|---|---|
| 1 | 부팅 A | `open … kind=mouse` 정확히 하나 · 키보드와 전원 버튼은 `skip` · `shown=0` | M0 |
| 2 | `mouse_move 10 5` | `at x=650 y=405`(출발 640, 400) | M0 |
| 3 | `mouse_button 1` · `0` | `buttons=1` 뒤 `buttons=0` | M0 |
| 4 | `mouse_move 0 0 1` | `wheel=1` | M0 |
| 5 | 왼쪽 위로 크게 밂 | `x=0 y=0`(clamp). 오른쪽 아래로 밀면 `x=1279 y=799` | M0 |
| 6 | `device_add` 뒤 `device_del` | 둘째 `open` · 그 경로의 `close` · 그 뒤에 친 `echo`가 화면에 온다(poll이 안 막혔다) | M0 |
| 7 | 부팅 뒤 움직이기 전 | 마지막 프레임의 `pane>`가 포인터 없는 부팅과 같다. M0 동안은 움직인 뒤에도 `ink=0`(그리지 않는다) | M0 |
| 8 | 움직임 | `shown=1 ink=`상수 · 두 번째 움직임 뒤에도 같은 상수(자국 없음) | M1 |
| 9 | 글자를 친다 | 다음 프레임에 `shown=0 ink=0` · 움직이면 다시 상수 | M1 |
| 10 | 오른쪽 아래 끝 | `ink`가 상수보다 작고 0보다 크다(잘린 그리기, 범위 밖 쓰기 없음) | M1 |
| 11 | `seq 200` 뒤 패널 위에서 휠 위로 한 눈금 | `scroll>`의 `offset`이 3 줄었다 · 아래로 한 눈금이면 되돌아온다 | M1 |
| 12 | 여백 위에서 휠 | `scroll>` 변화 없음 | M1 |
| 13 | `Cmd+D` 뒤 왼쪽 패널의 셀 왼쪽 위 끝 픽셀 누르고 떼기 | `pane> focus=0` · `clip>` 줄이 안 는다 | M2 |
| 14 | 구분선 칸 누르기 | `focus`가 그대로 | M2 |
| 15 | `echo pd-drag-word` 뒤 그 글자를 누르고 끌어 뗌 | `copy>` 진입 · `clip> len=12 text=pd-drag-word` · 그 뒤 `Cmd+V`의 에코가 화면에(왕복) | M2 |
| 16 | 끈 채로 이웃 패널 위까지 | `clip>`의 텍스트가 누른 패널의 마지막 열에서 끝난다 | M2 |
| 17 | 키보드 copy mode(`Cmd+Shift+C`) 중 클릭 | `copy> exit` · 그다음 친 글자가 셸에 온다(입력 모드가 normal로 돌아왔다) | M2 |
| 18 | 끌어 복사한 직후 글자를 친다 | 그 글자가 셸에 온다(모드의 두 사본이 함께 돌아왔다) | M2 |
| 19 | 커널 심볼 · `/sys/bus/*/drivers` · modinfo alias | 결정 9의 세 겹 | M3 |
| 20 | 부팅 A의 로그 | psmouse가 QEMU PS/2 마우스를 등록했고 terminal이 그것을 `kind=mouse`로 열었다 | M3 |
| 21 | 부팅 B, 도구가 가짜 터치패드를 만든다 | `open … kind=touchpad` | M3 |
| 22 | 한 손가락 이동 | `at`의 x가 배율대로 움직인다 | M3 |
| 23 | 탭(짧게) · 긴 누름(길게) | 탭은 `press` · `release`, 긴 누름은 아무것도 안 낸다 | M3 |
| 24 | 두 손가락 세로 | `scroll>`이 움직이고 `at`의 x · y는 그대로 | M3 |
| 25 | 도구가 끝난다 | `close` | M3 |

판정 글자가 친 명령줄과 겹치지 않게 하는 것은 `project_gate_screen_echo`의 규율이다. 검사 15는 `clip>` 줄로 보므로
화면 에코와 상관없다. 검사 6 · 17 · 18은 각자 새 글자를 친다.

좌표를 아는 법. 포인터의 출발은 프레임버퍼 가운데(640, 400)다. 칸을 누르려면 먼저 왼쪽 위로 밀어 (0, 0)에 붙인 뒤
상대 이동한다. QEMU의 USB HID는 보고 하나에 -127~127만 담으므로 큰 이동이 쪼개지는지 잘리는지는 재지 않았다 —
게이트는 한 번에 100 이하로 민다. 칸의 줄 번호는 마지막 `screen>`에서 그 글자가 든 `|` 구간의 번호로 구한다
(`copy` 체인이 쓰는 수법이다).

부팅 B의 되감기 도구. 정적 Zig 프로그램 하나(`pointer/replay/`)를 체인이 빌드해 설정 디스크에 싣는다. `wifi`
체인이 hostapd를 initrd가 아니라 디스크에 싣는 것과 같은 이유다 — 게이트만 쓰는 것을 제품 initrd에 넣지 않는다.
도구는 `/dev/uinput`으로 터치패드 하나를 만들고(`INPUT_PROP_POINTER` · `BUTTONPAD`, MT 두 칸, 축 0~1000 · 0~600,
resolution 10) stdin에서 한 줄씩 명령(`move` · `tap` · `hold` · `scroll` · `quit`)을 받아 그 이벤트를 쓴다.
게이트는 `/config/pd/tp-replay`를 친 뒤 `open … kind=touchpad` 줄을 기다리고, 명령을 하나씩 쳐서 그 결과 줄을
기다린다. 시각은 커널이 주입 순간에 찍으므로 탭의 길이는 도구가 자는 시간이 정한다. terminal이 늦게 읽어도
판정이 안 흔들린다.

uinput으로 보는 것과 못 보는 것.

| 본다 | 못 본다 |
|---|---|
| 부팅 뒤에 생긴 장치의 탐색(inotify) · 분류(`INPUT_PROP_POINTER`) · 축 정보 읽기 · 상태 기계 · 화살표 · 사라진 장치 닫기 | 실제 드라이버(hid-multitouch · psmouse synaptics · RMI4)가 내는 이벤트의 모양. 그것은 결정 9의 세 겹과 실기의 몫이다 |

`(b) 호스트 단위 테스트 + 커널 심볼 검사만`을 고르지 않은 이유는 그 안이 이 서브프로젝트에서 새로 만드는 배관
(inotify · ioctl 분류 · 터치패드 디코더를 `Pointer`에 잇는 자리)을 하나도 안 지나기 때문이다. 호스트 테스트는
`touchpad_test`로 따로 둔다 — 같은 시나리오를 부팅 없이 보고, 체인이 빨개졌을 때 어느 층인지 가른다. uinput의
비용은 커널 심볼 둘, 도구 하나(약 200줄로 예상하지만 재지 않았다), 체인의 부팅 하나다.

포트. monitor는 부팅 A가 45488, 부팅 B가 45489다(실측 8). 새 QEMU 호출은 둘 다 `-nic none`이다
(`require_explicit_nic`). `check.sh`의 `CHAINS`에 `"PD-Mn:./pointer/check.sh"`가 들어가고 진입 검사 셋을 지난다.

mutation 후보(각 plan이 고르고 더한다).

| milestone | 심는 고장 | 잡는 자리 |
|---|---|---|
| M0 | `classify`가 `EV_KEY`만 보고 마우스로 판정 | `input_test`/`pointer_test`가 부팅 전에. 건너뛰면 검사 1의 "정확히 하나" |
| M0 | `IN_CREATE`를 안 본다 | 검사 6의 둘째 `open` |
| M0 | `POLLHUP`에 닫지 않는다 | 검사 6의 `close`(그리고 poll이 매 바퀴 즉시 돌아온다) |
| M0 | `REL_Y`의 부호를 뒤집는다 | 검사 2의 `y=405` |
| M1 | 보이는 조건 2를 뺀다(처음부터 그린다) | 검사 7 — 그리고 기존 체인의 픽셀 덤프 |
| M1 | save-under의 되돌리기를 뺀다 | 검사 8의 둘째 `ink`가 상수보다 크다 |
| M1 | 휠 부호를 뒤집는다 | 검사 11의 방향 |
| M1 | `REL_WHEEL_HI_RES`도 센다 | 검사 11에서 3이 아니라 더 많이 움직인다(QEMU가 HI_RES를 몇으로 내는지는 plan이 잰다) |
| M2 | `hit`이 구분선 칸을 왼쪽 잎에 넣는다 | 검사 14 |
| M2 | 뗌에서 `copyYank`를 안 부른다 | 검사 15의 `clip>` |
| M2 | `pointerMode`를 안 부른다 | 검사 18(글자가 copy 표에 삼켜진다) |
| M2 | 끄는 칸을 누른 패널로 clamp하지 않는다 | 검사 16 |
| M3 | 탭의 시간 조건을 뺀다 | `touchpad_test`가 부팅 전에. 건너뛰면 검사 23의 긴 누름 |
| M3 | 두 손가락을 이동으로 보낸다 | 검사 24의 "x · y가 그대로" |
| M3 | `INPUT_PROP_POINTER`를 안 본다 | 검사 21 |

### 결정 11 — 구현은 서브에이전트가, 검증 · 게이트 · commit은 lead가 한다

PE 결정 9 · GE 결정 8과 같다. plan은 milestone마다 그 시점에 Opus 서브에이전트가 쓴다. 구현은 PD-M0 · M2 · M3을
Opus, PD-M1을 Sonnet 서브에이전트가 plan만 보고 한다. lead(Fable)는 결과 파일을 `Read`로 대조하고, 게이트를 돌리고,
commit한다. 그래서 plan은 고칠 파일과 심볼, 편집의 모양, 칠 명령, 기대하는 출력, mutation을 다 적는다.

M1이 Sonnet인 이유는 그 milestone이 이미 정해진 모양(save-under 산수, 휠 상수, 보이는 조건 셋)을 옮기는 일이기
때문이다. M0은 새 배관(inotify · 손으로 짓는 ioctl · poll 배열 오프셋)이고, M2는 모드의 두 사본과 copy mode의
경계를 만지고, M3은 커널 config와 상태 기계와 게스트 도구를 함께 만든다.

### 결정 12 — 자식이 마우스를 원하면 보고하고, 우리 선택은 Shift로 간다(PD-M4)

비목표 1을 사용자의 결정(2026-10-05)으로 열었다. 자식(vim `mouse=a` · fzf · lazygit · htop)이 마우스 모드를 켜면 누름 ·
끎 · 뗌 · 휠을 우리 제스처 대신 그 자식의 PTY에 보낸다.

라이브러리가 이미 하는 것과 우리가 할 것이 갈린다. 둘 다 vendored ghostty 소스에서 읽고 PD-M4 plan이 사본에서 컴파일해
확인했다.

| 일 | 누가 | 근거 |
|---|---|---|
| 모드 해석(9 · 1000 · 1002 · 1003, 형식 1005 · 1006 · 1015 · 1016) | ghostty vt. `Terminal.flags.mouse_event` · `mouse_format`에 담긴다 | `stream_terminal.zig`의 모드 갈래 |
| 사건 하나를 바이트로 | ghostty의 `input.encodeMouse`(`lib_vt.zig`가 공개한다). 모드별로 무엇을 보고하나, 다섯 형식, 칸이 안 바뀐 움직임 거르기, 1부터 세는 좌표, 패널 밖 좌표의 처리가 그 안에 있다 | `input/mouse_encode.zig` |
| 누구의 것인가 · 어느 패널인가 · 픽셀 좌표 · PTY에 쓰기 · 휠을 화살표 키로 | 우리 | 아래 |

우리 코드는 세 층에 나뉜다. 결정 3의 층 그대로다.

| 층 | 더하는 것 |
|---|---|
| `pointer.zig`(순수) | `Owner` · `Pane` · `ownerOf` · `Grab`(버튼이 눌린 동안의 주인) · `wheelRoute` · `Gesture.handOff` |
| `vt.zig` | `mouseWanted` · `wheelKeys` · `wheelKey` · `mouseEncode`(인코더 감싸개). 라이브러리 타입은 이 파일 밖으로 안 나간다(TR 결정 1, `pasteParts`와 같은 규율) |
| `input.zig` | `State.modifiers()` — Shift · Ctrl · Alt가 눌렸나 |
| `main.zig` | `PointerWire`가 전이마다 주인을 가르고, 자식의 것이면 `mouseEncode`의 바이트를 그 PTY에 쓴다 |

#### 누구의 것인가

| 후보 | 왜 아닌가 / 왜 이것인가 |
|---|---|
| (a) 자식이 원하면 언제나 자식의 것. 우리 선택은 없다 | vim 화면의 글자를 우리 클립보드로 꺼낼 길이 없어진다. 자식이 클립보드에 쓰는 길(OSC 52)이 우리에게 없다(비목표 16) |
| (b) Shift를 누른 채면 우리 것 | 고른다. xterm 이래의 관례이고 ghostty · kitty · WezTerm · tmux가 같다. ghostty의 `Surface.zig`도 기본 설정(`mouse-shift-capture = false`)에서 Shift가 눌렸으면 보고하지 않는다 |
| (c) Option(Alt)을 누른 채면 우리 것(iTerm2의 방식) | Alt는 보고에 실리는 수정키다(+8). Alt+클릭을 받는 프로그램과 부딪친다. 우리 키보드에서 Alt는 셸의 meta이기도 하다 |
| (d) 지금처럼 우리 선택이 언제나 먼저 | 비목표 1을 연 이유 자체다 |

규칙은 한 줄이다. 누른 자리의 패널이 마우스를 원하고, 그 패널이 키보드 copy mode가 아니고, Shift가 안 눌렸으면 자식의
것이고 나머지는 우리 것이다(`ownerOf`). copy mode를 우리 것으로 두는 이유는 사람이 `Cmd+Shift+C`로 "우리 선택"을 이미
골랐기 때문이다. 여백 · 구분선 · 상태 줄은 우리 것이고 거기서는 지금처럼 아무 일도 없다.

Shift는 `input.State`의 수정키에서 읽는다. `pointer.zig`는 `input.zig`를 import하지 않으므로 `main.zig`가 회차마다
`State.modifiers()`를 `PointerWire`에 넘긴다. poll 회차 안에서 키보드 분기가 포인터 분기보다 먼저 돌므로 같은 회차에
들어온 Shift도 보인다. 보고에 싣는 수정키는 Alt(+8) · Ctrl(+16)이다. Shift는 실릴 일이 없다 — 눌렸으면 보고하지 않는다.
Meta(Cmd)는 형식에 비트가 없다.

#### 주인은 첫 누름이 정하고 마지막 뗌까지 간다

버튼이 하나도 안 눌렸을 때의 첫 누름이 주인과 패널을 정하고(`Grab.press`), 마지막 버튼을 뗄 때까지 바뀌지 않는다. 짝을
맞추기 위해서다. 자식이 누름을 받았으면 뗌도 받아야 하고(vim은 뗌이 올 때까지 Visual을 늘린다), 우리 제스처가 누름을
받았으면 뗌도 받아야 한다(복사가 뗌에 있다). 그래서 누르는 동안 모드나 Shift가 바뀌어도 그 손동작은 처음 주인의 것이다.

| 누르는 동안 일어난 일 | 일 |
|---|---|
| 보고를 받던 자식이 모드를 끈다(vim이 끝났다) | 나머지 끎 · 뗌은 인코더가 버린다 — 모드가 `none`이면 아무것도 안 짠다. 우리 제스처로 넘어가지 않는다 |
| 우리가 끌던 중에 자식이 모드를 켠다 | 우리 끌기가 뗌까지 가서 복사한다. 자식이 대체 화면으로 갈아탔으면 결정 6의 가지치기가 copy mode를 이미 닫았고 뗌은 아무것도 안 한다 |
| Shift를 누른 채 누르고 끄는 중에 Shift를 뗀다 | 우리 끌기 그대로다 |
| 장치가 누른 채 빠진다 · 한 회차의 전이가 넘쳐 뗌을 잃는다 | 회차 끝의 `Grab.settle`이 주인의 버튼을 포인터의 버튼에 맞춘다. 이것이 없으면 그 뒤의 모든 누름이 옛 주인에게 간다 |
| 누른 뒤 키보드로 워크스페이스를 옮긴다 | 그 손동작의 보고는 버린다. 자식은 뗌을 못 받지만 다음 누름이 고친다 |

자식의 것인 누름은 `Gesture`를 건너뛴다. 다만 첫 누름은 `Gesture.handOff`로 `cancel`과(다른 패널이면) `focus`를 먼저
낸다. 조합 중인 한글이 보고보다 먼저 옛 포커스의 PTY에 가고, 옛 포커스의 copy mode가 닫히고, 포커스가 누른 패널로
옮겨 간 뒤에 보고가 나간다. tmux의 기본 바인딩(`MouseDown1Pane`이 `select-pane` 뒤에 `send-keys -M`)과 같은 순서다.

오른쪽 · 가운데 버튼도 보고한다. 우리 제스처는 지금처럼 왼쪽만 쓰고, 우리 것인 오른쪽 · 가운데는 지금처럼 아무 일도 없다
(비목표 8). 그래서 PD-M2가 왼쪽만 담던 회차의 전이 칸(`PointerEdge`)이 버튼 셋을 다 담는다.

#### 어느 패널, 어떤 좌표

| 사건 | 받는 패널 | 포커스 |
|---|---|---|
| 누름 · 끎 · 뗌 | 첫 누름의 패널(`Grab.leaf`). 패널 밖으로 끌어도 그 패널이다 | 첫 누름이 그 패널로 옮긴다 |
| 휠 | 포인터 아래 패널 | 안 바뀐다(결정 7과 같다) |
| 버튼 없는 움직임 | 포인터 아래 패널. 실제로 보내는 것은 모드 1003뿐이다(인코더가 거른다) | 안 바뀐다 |

좌표는 그 패널의 왼쪽 위 끝에서 잰 픽셀로 인코더에 넘긴다. 칸이 아니라 픽셀인 이유는 둘이다. 인코더가 칸을 셈하고
패널 밖 좌표를 처리한다 — 밖에서의 누름과 버튼 없는 움직임은 버리고, 뗌과 누른 채 움직임은 가장자리 칸으로 붙인다.
그리고 SGR-Pixels(1016)가 픽셀 그대로를 원한다. 크기는 `vt.Screen`이 라이브러리에 준 값(`width_px` · `height_px` ·
셀 8 × 16)이라 칸을 세는 산수가 렌더러 · `gridCell`과 같다. 패널의 왼쪽 위 끝은 `paneOrigin`이 같은 상수 넷으로 구한다 —
결정 5의 "역변환이 같은 상수를 쓴다"가 여기에도 그대로다. 1부터 세는 것은 인코더가 한다.

#### 형식

인코더가 다섯을 다 짠다. 그래서 지원 목록을 따로 정하지 않는다 — X10(9와 형식 없는 1000) · UTF-8(1005) · SGR(1006) ·
urxvt(1015) · SGR-Pixels(1016)가 다 간다. 게이트는 SGR만 보고 `vt_test`가 X10 하나를 더 본다. 나머지 셋은 라이브러리의
몫이다. X10은 223열을 넘는 칸을 못 담는다(인코더가 버린다). 실기의 큰 화면(2560 × 1600이면 315열)에서는 SGR을 쓰는
프로그램만 오른쪽 끝을 받는다. 게스트 vimrc가 `ttymouse=sgr`을 거는 이유다(아래).

#### 휠

| 포인터 아래 패널 | 휠 한 눈금 | 왜 |
|---|---|---|
| 키보드 copy mode | 아무 일도 없다 | 결정 7 그대로 |
| Shift를 누른 채 | 우리 스크롤백 | 누름과 같은 규칙. 대체 화면이면 스크롤백이 없어 아무 일도 없다 |
| 자식이 마우스를 원한다 | 버튼 4(위) · 5(아래)의 누름 하나 | xterm의 모양. 우리 스크롤백은 안 움직인다 |
| 대체 화면이고 모드 1007이 켜져 있다 | 화살표 키 `WHEEL_ROWS`(3)번. DECCKM이면 `ESC O A` | 마우스를 안 켜는 대체 화면 프로그램(`less` · `man`)에서 휠이 줄을 움직인다 |
| 그 밖 | 우리 스크롤백 3줄 | 결정 7 그대로 |

보고가 화살표 키보다 먼저다. 마우스를 켠 대체 화면 프로그램(vim `mouse=a`)은 휠을 버튼으로 받는다. ghostty의
`Surface.zig`도 같은 순서다(1007은 `mouse_event`가 `none`일 때만). 1007의 기본값은 ghostty가 켜짐이고 xterm은 꺼짐인데,
라이브러리를 따른다 — 지금 대체 화면의 휠은 움직일 스크롤백이 없어 아무 일도 안 하므로 잃는 것이 없다. 원하지 않는
프로그램은 `ESC[?1007l`을 보낸다. 끄는 중의 휠(결정 7)은 이 표보다 먼저 본다 — 우리가 끄는 중이면 우리 것이다.

#### 게스트 vimrc

`set mouse=`를 `set mouse=a`로 바꾸고 `set ttymouse=sgr`을 더한다. GE design 원칙 3("우리 터미널이 안 하는 것을 켜지
않는다")의 전제가 바뀐 것이다. 원칙은 그대로 두고 그 자리에 PD-M4가 바꿨다고 덧붙인다. `ttymouse=sgr`은 vim이 TERM을 보고
고르는 값을 정해 둔다 — X10 계열의 223열 한계가 없다.

대가가 하나 있다. vim 안에서 그냥 끌면 vim의 Visual이고 우리 클립보드가 아니다. 우리 선택은 Shift를 누른 끌기다. 그것이
싫은 사람은 `/.vimrc`(설정 디스크의 `/config/vimrc`)에 `set mouse=`를 적는다. vimrc 주석에 그 탈출로를 남긴다.

#### 게이트

자식이 받은 바이트를 보는 길이 둘이다.

| 후보 | 보는 것 | 못 보는 것 |
|---|---|---|
| (a) 게스트의 프로브. 모드를 켜고 `read -N`으로 정해진 바이트를 읽어 `cat -v`로 찍는 bash 스크립트 | 자식이 받은 바이트 그대로 · 모드를 마음대로 켠다(1000 · 1002 · 1049) · Shift · 1007 · 패널 | 실제 프로그램 |
| (b) vim(`mouse=a`)에서 클릭하면 커서가 옮겨 간다 | 실제 프로그램과 vimrc의 두 줄 | 바이트(vim의 해석만 보인다) · 어느 모드를 켜나가 vim에 달렸다 |

둘 다 쓴다. (a)가 판정의 대부분이고 (b)는 검사 하나다. 프로브는 이스케이프 바이트가 든 파일이라 타이핑으로 만들 수
없다(lessons 실측 53, `tq-probe`와 같은 이유). 게스트에 `stty`가 없어서 bash의 `read`가 터미널을 raw로 바꾸는 유일한
길이고, 켜기 · 읽기 · 끄기가 한 프로세스 안에 있어야 한다 — 프롬프트로 돌아온 셸이 먼저 읽으면 그 셸의 키가 된다.

자리는 부팅 B다. 부팅 B는 이미 설정 디스크(`tars-pd`)를 물고 있어 프로브와 vim이 열 파일을 거기에 더하면 된다. 부팅 A는
디스크가 없다 — 디스크를 물리면 init이 설정을 읽어 M0~M2의 판정이 기대는 화면이 바뀐다. 셋째 부팅은 체인에 30초 남짓을
더한다. 부팅 B의 HMP 대상은 PS/2 마우스 하나이고 이동이 1:1이다(PD-M4 plan 확정 7).

판정은 둘을 같은 글자로 맞춘다. terminal이 보낸 것(새 로그 줄 `pointer> report`, `cat -v` 모양)과 자식이 읽은 것(프로브가
찍은 화면 줄)이다. 로그 줄만 보면 PTY에 안 쓴 고장이 안 보이고, 화면 줄만 보면 어느 패널에 보냈는지가 안 보인다.

```
terminal: pointer> report leaf=0 n=1 text=^[[<0;11;2M
terminal: pointer> report leaf=0 n=3 text=^[[A
```

`n`은 같은 바이트를 몇 번 보냈는가다. 마우스 보고는 1이고, 휠을 바꾼 화살표 키는 눈금 × `WHEEL_ROWS`다.

| 검사 | 친다 | 본다 |
|---|---|---|
| 26 | 프로브가 1000 · 1006을 켠다. 1행 10열을 눌러 12열까지 끌어 뗀다 | 누름 `^[[<0;11;2M`과 뗌 `^[[<0;13;2m`만. 끎은 없고 우리 제스처(`press` · `copy> enter`)도 안 돈다 |
| 27 | 1002 · 1006으로 같은 손동작 | 끎 `^[[<32;13;2M`이 사이에 하나 |
| 28 | 1000 · 1006에서 휠 위 · 아래 한 눈금씩 | `^[[<64;13;2M^[[<65;13;2M` · 우리 스크롤백은 바닥 그대로 |
| 29 | 1000 · 1006에서 Shift를 누른 채 프로브의 ready 줄 0~7열을 끈다 | `clip> len=8 text=pd-mouse` · 자식은 0바이트 |
| 30 | 프로브가 1049로 대체 화면에 들어간다(마우스 모드 없음). 휠 위로 한 눈금 | `^[[A` 세 번 · report 줄 `n=3` |
| 31 | `vim`으로 서른 줄 파일을 열고 4행 9열을 누른다 | report 줄 `^[[<0;10;5M` · vim의 상태 줄이 `1:1`에서 `5:6` |
| 32 | `Cmd+D` 뒤 오른쪽 패널에서 프로브를 띄우고 `Cmd+[`로 포커스를 왼쪽에 둔다. 오른쪽 패널의 1행 2열을 누르고 뗀다 | 포커스가 오른쪽으로 · report 줄 `leaf=1` · 자식이 패널 안의 칸 `3;2`를 받는다 |

Shift를 누른 채 두는 것은 HMP `sendkey shift 3000`이다. QEMU는 그 키를 뗄 때까지 다음 키를 큐에 두지만 마우스 사건은
큐를 안 거친다. 그 3초 안에 누르고 끌고 뗀다.

mutation은 넷이고 전부 `main.zig`의 한 줄이다. 순수 층의 규칙은 호스트 검사가 부팅 전에 보므로, 체인이 잡아야 하는 것은
배선이다.

| 심는 고장 | 잡는 자리 |
|---|---|
| `paneAt`이 모드를 안 읽는다(`wants`가 늘 거짓) | 검사 26 — report 줄이 안 나온다 |
| 누름이 Shift를 안 본다 | 검사 29 — 클립보드가 그대로이고 자식이 누름을 받는다 |
| 보고 좌표를 패널이 아니라 격자의 원점에서 잰다 | 검사 32 — 오른쪽 패널의 2열이 80열로 재여 77열 패널의 밖이 되고, 인코더가 밖에서의 누름을 버려 보고가 없다. 패널 하나인 검사 26~31은 두 원점이 같아서 못 본다 |
| `paneAt`이 1007을 안 읽는다 | 검사 30 — 우리 스크롤이 되고 대체 화면에는 스크롤백이 없어 자식이 0바이트 |

호스트 검사는 `pointer_test` 검사 23~28(`ownerOf` · `Grab` · `settle` · `handOff` · `wheelRoute` · `Buttons.with`),
`vt_test` 검사 102~106(바이트 · 1002 · 1003 · X10 · 1007 · DECCKM), `input_test` 검사 68(`modifiers`)이다.

구현은 결정 11의 모양을 따른다. plan은 Opus가 쓰고, 구현은 Opus 서브에이전트가 plan만 보고 하고, lead가 대조 · 게이트 ·
commit을 한다.

## 실기에서 같은 코드로 가는가

질문은 "노트북에 터치패드와 USB 마우스가 함께 있을 때, 터치패드가 PS/2로 잡히든 I2C-HID로 잡히든 같은 코드로
가는가"였다. 답은 "분류가 같은 곳으로 보낸다"이다. 근거는 커널의 약속이고, 실기로 재지는 않았다.

| 경로 | 커널이 만드는 노드 | 우리 분류 |
|---|---|---|
| psmouse synaptics · elantech · alps | MT 프로토콜 B, `INPUT_PROP_POINTER`, 대개 `BUTTONPAD` | `touchpad` |
| RMI4 SMBus(psmouse가 넘겨준 Synaptics) | 같은 모양. psmouse 쪽 노드는 사라지거나 조용해진다 | `touchpad` |
| I2C-HID + hid-multitouch | 같은 모양. 대개 "… Touchpad" 노드와 "… Mouse" 노드 둘 | `touchpad` 하나, `mouse` 하나(조용하다) |
| I2C-HID인데 hid-multitouch가 없을 때 | hid-generic이 마우스 모드로 낸다(`REL_X` · `REL_Y`) | `mouse`. 이동과 버튼만 되고 두 손가락 스크롤은 안 된다 |
| TrackPoint | `REL` 마우스 | `mouse` |
| USB 마우스 | `REL` 마우스(실측 1) | `mouse` |

`Pointer`는 장치를 몇 개 받든 화살표 하나를 움직이므로 USB 마우스와 터치패드는 서로를 방해하지 않는다. 버튼은
장치별로 들고 합친다(결정 3).

실기 확인은 `docs/guides/running-tars.md`의 실기 절에 항목으로 남긴다(닫을 때). 실기에서 볼 것은 셋이다 — 로그의
`pointer> open` 줄의 `kind=`, 결정 8의 출발값 셋이 손에 맞는지, 그리고 두 손가락 스크롤의 방향이다.

## 검증

### 호스트(모든 체인이 부팅 전에 돌린다)

- `pointer_test`(새). 분류 표 전부(QEMU USB Mouse · usb-tablet · 키보드 · 전원 버튼 · 터치패드 · 터치스크린의 비트맵) ·
  `Mouse.feed`의 `SYN_REPORT` 묶기 · `SYN_DROPPED` 버리기 · `REL_WHEEL_HI_RES` 버리기 · `Pointer`의 clamp와 버튼 합치기 ·
  `Gesture`의 누름 · 첫 칸 이동 · 뗌 · 클릭 · clamp · 키보드 copy mode 중 누름 · save-under 왕복.
- `touchpad_test`(새). 슬롯 추적 · 한 손가락 이동의 배율 · 탭과 긴 누름 · 탭이지만 많이 움직인 것 · 두 손가락 세로 ·
  버튼을 누른 채 두 손가락 · `SYN_DROPPED`.
- `layout_test`. `hit` — 각 잎의 네 모서리 칸, 구분선 칸, 격자 밖.
- `vt_test`. `copyEnterAt` · `copyPointTo`가 `copySelect` · `copyMove`로 만든 것과 같은 선택 문자열을 낸다.
- `input_test`. `pointerMode`가 normal에서 조합을 확정해 돌려주고, find에서 버리고, mode를 바꾼다. 키보드 fd로 온
  `BTN_LEFT`가 아무것도 안 만든다(결정 2).
- PD-M4(결정 12). `pointer_test`가 누름의 주인(`ownerOf`) · 첫 누름부터 마지막 뗌까지 가는 주인(`Grab`) · 놓친 뗌의
  `settle` · `handOff` · 휠의 갈 곳(`wheelRoute`)을, `vt_test`가 인코더가 짠 바이트(SGR의 누름 · 뗌 · 버튼 4 · 5 · 수정키 ·
  칸 경계 · 패널 밖, 1002 · 1003의 움직임, X10, 모드 끄기)와 대체 화면의 화살표 키(1007 · DECCKM)를, `input_test`가
  `modifiers`를 본다.

### 게이트

결정 10의 체인. 그리고 milestone마다 기존 열여덟 체인이 그대로 지나야 한다 — 특히 M0 · M1 뒤에 `render` · `copy` ·
`pane`의 픽셀 판정이 한 픽셀도 안 바뀌어야 한다(보이는 조건 2). M3 뒤에는 모든 pc 체인에 PS/2 마우스가 생기므로
같은 판정을 한 번 더 본다.

PD-M4는 부팅 B에 결정 12의 검사 26~32를 더한다. 게스트 vimrc가 바뀌므로 vim을 쓰는 `render` · `copy` · `config` ·
`tools` 체인이 regression이다.

루트 게이트는 milestone마다 한 번, 열아홉 체인 × 3이다. 지금(열여덟 체인) 약 1시간 5분이고 새 체인이 얼마를
더하는지는 재지 않았다.

## Milestone

### PD-M0 — 탐색 · 읽기 · 로그(화면 변화 0)

`pointer.zig`(분류 · `Mouse` 디코더 · `Pointer`) · `pointer_test` · ioctl 넷 · inotify · poll 배열의 장치 칸 · 빠진
장치 닫기 · `pointer>`의 `open` · `skip` · `close` · `at` 줄. 그리지 않고 아무 의도도 실행하지 않는다. 새 체인
`pointer/check.sh`의 부팅 A와 검사 1~7. 이 milestone이 끝나면 terminal이 부팅 전후의 USB 마우스를 열고 닫고, 그
움직임을 로그로 말한다.

### PD-M1 — 화살표와 휠

save-under 그리기 · 전용 색 둘 · 보이는 조건 셋 · 휠(`WHEEL_ROWS`, 포인터 아래 패널, 키보드 copy mode 패널 제외).
`layout.Tree.hit`과 픽셀 → 칸 변환이 여기 들어온다(휠이 패널을 골라야 한다). 검사 8~12.

### PD-M2 — 클릭 · 드래그 선택 · 복사

`Gesture`의 누름 · 끎 · 뗌 · `vt`의 `copyEnterAt` · `copyPointTo` · `input`의 `pointerMode` · 포커스 옮김 · 끄는 동안의
휠. 검사 13~18. 이 milestone이 끝나면 사용자의 요청 1이 끝난다.

### PD-M3 — 터치패드

커널 config(결정 9) · `touchpad.zig` · `touchpad_test` · 분류의 `touchpad` 갈래를 디코더에 잇기 · 되감기 도구 ·
부팅 B. 검사 19~25. 이 milestone이 끝나면 사용자의 요청 2가 QEMU 안에서 볼 수 있는 데까지 끝난다. 실기 확인은
그 뒤 사람이 한다.

### PD-M4 — 마우스 보고

사용자의 결정(2026-10-05)으로 비목표 1을 열었다. `pointer.zig`의 `Owner` · `Pane` · `ownerOf` · `Grab` · `wheelRoute` ·
`Gesture.handOff`, `vt.zig`의 `mouseWanted` · `wheelKeys` · `wheelKey` · `mouseEncode`, `input.zig`의 `State.modifiers`,
`main.zig`의 전이 칸(버튼 셋) · `PointerWire`의 주인 가르기와 보고 · `pointer> report` 줄. 게스트 vimrc의 `mouse=a` ·
`ttymouse=sgr`과 GE design 원칙 3의 덧붙임. 부팅 B의 설정 디스크에 프로브와 서른 줄 파일, 검사 26~32. 이 milestone이
끝나면 vim · fzf · lazygit · htop이 클릭 · 끎 · 휠을 받고, 사람은 Shift를 누른 채 끌어 우리 클립보드에 넣는다.

## 위험

1. 렌더 비용. 화면을 다시 그리는 프레임 하나가 TCG에서 21ms 근처다(RC-M0). save-under가 움직임만 있는 프레임을
   그 비용에서 빼지만, 출력이 흐르는 동안 포인터를 움직이면 전체 프레임이 계속 돈다. 실기의 프레임버퍼가
   크면(2560 × 1600은 게이트의 네 배) 더 무겁다. 이월 숙제의 부분 갱신을 다시 집을 신호가 "사람이 느린 것을
   느낀다"인데, 마우스가 그것을 처음 느끼게 하는 장치일 수 있다.
2. 누름과 첫 칸 이동 사이에 PTY 출력이 오면 그 패널이 바닥으로 내려가고(copy mode가 아직 아니다), 기억해 둔 누른
   칸이 다른 글자를 가리킨다. 그 사이는 사람의 손이 한 칸을 움직이는 시간이다. 출력이 쉬지 않는 패널(`top`)에서
   선택이 한 줄 어긋날 수 있다. 막으려면 누름에서 tracked pin을 잡아야 하는데, 그 pin을 누가 언제 놓는지가 새 수명이
   된다. 실제로 겪으면 그때 한다.
3. 터치패드의 출발값 셋(결정 8)은 실기 없이 정했다. 손에 안 맞으면 탭이 안 먹거나, 타이핑 중 손바닥이 클릭이
   된다(손바닥 거부는 비목표다). 실기에서 고치되 고친 값을 `touchpad_test`에도 옮긴다.
4. 실기 커널 경로 셋 중 QEMU에서 실제로 도는 것은 psmouse의 기본 마우스 프로토콜뿐이다. hid-multitouch가 PTP 모드로
   바꾸는 것, RMI4 SMBus로 넘어가는 것, LPSS · pinctrl의 GPIO 인터럽트는 전부 실기에서만 보인다. 심볼과 드라이버 등록은
   "켜졌다"까지만 말한다(UW 위험과 같다).
5. 모드의 두 사본. 이 design이 포인터 경로에서는 둘을 함께 옮기지만(결정 6), 지금도 하나가 따로 움직이는 자리가 있다 —
   가지치기가 copy mode를 닫을 때(`vt.zig`의 `feed`) `input.State.mode`는 `.copy`에 남는다. 이 서브프로젝트는 그 자리를
   안 고친다. 끌어 만든 선택 중에 가지치기가 나면 같은 일이 일어나고, 사람은 `Esc`를 한 번 더 친다.
6. 화살표는 전체 프레임에서 `present` 앞에 그리므로 그 프레임의 픽셀 덤프가 화살표를 본다(결정 4). 포인터 체인 안에서
   `style>` · `cursor>`를 판정에 쓰는 검사는 화살표가 숨은 뒤(글자를 친 뒤)에 둔다.
7. psmouse(PD-M3)가 실기에서 i8042의 탐지로 부팅을 늦추거나, 터치패드가 없는 기계에서 엉뚱한 AUX 장치를 잡을 수 있다.
   QEMU에서의 시간만 plan이 잰다.
   > M3 실측(2026-10-05): QEMU에서 `Run /init`이 3.0초 → 3.9~4.2초로 늦어졌는데 psmouse도 새 드라이버의 초기화도 아니었다
   > (전부 5ms 아래, `i8042.noaux`로도 같다). 늦어진 것은 initramfs 풀기이고 원인은 코드 배치다 — gzip `inflate_fast`가 앞쪽
   > 코드에 밀려 페이지 경계를 넘으면 QEMU TCG가 그 번역 블록을 직접 잇지 못한다(HEAD 설정에 `X86_INTEL_LPSS` 하나만 켠
   > 커널로 확인). 게이트만의 비용이고 실기와 무관하다. M0의 FSNOTIFY(결정 1의 덧붙임)도 같은 것이었을 가능성이 크지만 그때
   > System.map을 안 봐서 재지 않았다. `install` 부팅 7의 `delay_use`를 3에서 4로 올려 여유를 0 → 900ms로 되돌렸다.
8. (M0 plan 확정 1이 실측으로 풀었다 — 꽂으면 새 마우스로 가고 뽑으면 원래 것으로 돌아온다. 검사 6이 그 성질을 판정에 쓴다.)
   QEMU의 HMP가 `device_add`로 붙인 두 번째 USB 마우스를 대상으로 바꾸는지, `device_del` 뒤에 원래 마우스로 돌아가는지
   (결정 10). 안 돌아가면 검사 6 뒤의 검사가 움직임을 못 보낸다 — 그때는 검사 6을 부팅 A의 맨 끝으로 옮긴다.
9. (PD-M4) 자식이 모드를 켠 채 죽으면(`kill -9`로 끝난 vim) 모드가 남는다. 그 뒤로 셸 위의 클릭이 `^[[<0;11;2M` 같은
   글자로 프롬프트에 찍힌다. 모든 터미널이 같고, 사람은 `printf '\e[?1000l'`로 끈다(게스트에 `reset`은 없다). Shift를 누른 끌기는 그동안에도
   우리 선택이다. 셸이 프롬프트를 그릴 때 모드를 끄게 하는 것은 seed rc의 몫이고 이 milestone은 안 한다.
10. (PD-M4) vim의 `mouse=a`의 대가(결정 12). 그냥 끌면 vim의 Visual이고 우리 클립보드가 아니다. Shift를 모르는 사람에게는
    "vim에서 복사가 안 된다"로 보인다. 탈출로는 `/.vimrc`의 `set mouse=`이고 vimrc 주석에 있다. 자주 걸리면 OSC 52(비목표 16)가
    다음 길이다.
11. (PD-M4) Shift 판정은 poll 회차 안에서 키보드 분기가 포인터 분기보다 먼저 돈다는 순서에 기댄다. 사람이 버튼을 먼저
    누르고 Shift를 뒤에 누르면 그 손동작은 Shift 없는 것이다 — 주인은 첫 누름에 정해진다(결정 12). 의도한 동작이다.

## 비목표

다시 열 조건을 함께 적는다.

1. (사용자의 결정으로 PD-M4가 됐다, 2026-10-05 — 결정 12.) 마우스 보고(자식에게 SGR 1006으로 클릭 · 휠을 보내는 것). ghostty vt가 모드(9 · 1000 · 1002 · 1003 · 1006)를 이미 해석하고
   `encodeMouse`가 있다. 우리는 안 쓴다. 다음 서브프로젝트의 첫 후보다 — vim `mouse=a`, fzf, lazygit, htop의 클릭이 이것으로
   된다. 열면 "자식이 마우스를 원할 때 우리의 드래그 선택을 언제 하나"(관례는 Shift를 누른 끌기)와, 대체 화면에서 휠을
   화살표 키로 바꾸는 모드 1007이 함께 온다. 게스트 vimrc의 `set mouse=`도 그때 다시 본다.
2. 더블클릭 단어 선택 · 세 번 클릭 줄 선택 · Shift 클릭으로 늘리기. `ev.time`이 있어 타이머 없이 할 수 있다. CN의 단어
   경계(`copyMoveWord`)가 재료다. 끌기 선택을 쓰다가 단어 하나 잡는 것이 불편해지면 연다.
3. 끄는 중 가장자리에서 뷰포트가 저절로 따라가기. 시간이 지나면 한 줄씩 미는 것이라 타이머가 필요하다. 끄는 중의
   휠이 그 대신이다(결정 7).
4. 절대 좌표 장치 — usb-tablet · virtio-tablet · 터치스크린(`INPUT_PROP_DIRECT`). usb-tablet은 축을 화면에 비례로 대는
   열 줄 남짓이지만, 그러면 터치스크린도 같은 갈래로 오는데 터치스크린은 "닿음 = 누름"이라 다른 제스처 표가 필요하다.
   VM 창(UTM · virt-manager의 기본이 tablet이다)에서 TARS를 쓸 일이 생기거나, 터치스크린 노트북이 생기면 연다.
5. 뗀 뒤에도 반전 남기기(결정 6). "copy mode 밖의 선택"이라는 상태와 그것을 지우는 때를 정해야 한다.
6. 포인터 가속과 터치패드의 나머지(결정 8의 목록). 가속이 없으면 큰 화면에서 패드를 여러 번 밀어야 한다 — 실기에서
   그것이 불편하면 가속부터 연다.
7. `tars.conf` 항목 — 휠 방향(자연스러운 스크롤) · 휠 줄 수 · 탭 켜고 끄기 · 패드 배율. 사용자가 기본값과 다른 것을
   원하면 연다. 휠 방향이 가장 먼저 열릴 후보다.
8. 왼손잡이 버튼 교체 · 가운데 버튼 붙여넣기 · 오른쪽 버튼 메뉴. 지금 오른쪽 · 가운데 버튼은 로그에만 나온다.
9. 키보드 핫플러그. 결정 1의 inotify 기계가 재료다. 부팅 뒤에 USB 키보드를 바꿔 꽂을 일이 생기면 연다. 그때는 init의
   `argv[4]`와의 관계(HD 결정 3)를 함께 정한다.
10. Apple 트랙패드(`bcm5974` · `applespi` · Magic Trackpad)와 `HID_APPLE`. Intel MacBook에서 띄울 일이 생기면 연다 —
    `keyboard=apple`과의 충돌(lessons 이월 숙제)을 먼저 정한다.
11. 패널 경계를 끌어 비율 바꾸기. 비율이 늘 1/2인 것은 WP 결정 2다. `layout.Tree`에 비율 필드가 생겨야 한다.
12. 포커스가 포인터를 따라가기 · 상태 줄 클릭(IS 비목표의 "마우스로 눌러 자판 바꾸기") · URL 열기.
13. 시간이 지나면 화살표 숨기기. 타이머가 필요하다. 키를 치면 숨는 것(결정 4)으로 부족하면 연다.

PD-M4(결정 12)가 열면서 생긴 것.

14. 포커스 보고(모드 1004). ghostty에 `encodeFocus`가 있지만 포커스가 바뀌는 자리가 다섯이다(`Cmd+[` · `Cmd+]` · `Cmd+1~9` ·
    패널 닫기 · 클릭). 자리마다 옛 패널과 새 패널에 보내야 해서 공짜가 아니다. vim의 `FocusGained`(`autoread`)를 원하면 연다.
15. 자식이 Shift를 가져가기(XTSHIFTESCAPE `CSI > 1 s`, ghostty의 `mouse_shift_capture`). Shift는 언제나 우리 것이다.
16. OSC 52(자식이 우리 클립보드에 쓰기). vim의 `"+y`와 tmux의 복사가 우리 클립보드에 닿는 길이고, `mouse=a`의 대가(위험 10)를
    줄인다. vim 안에서 고른 글자를 바로 붙이고 싶어지면 연다.
17. 가로 휠(버튼 6 · 7)과 포인터 모양(OSC 22, ghostty의 `MouseShape`). 디코더가 가로 휠을 버린다(결정 7). 화살표는 하나다.
18. 보고를 끄는 설정(`tars.conf`의 항목). 지금은 프로그램이 모드를 켜는 대로 따른다. 특정 프로그램의 보고가 방해가 되면 연다.

## 착수 전에 실측한 것

lead(Fable)가 2026-10-05에 QEMU 10.0.13 · 커널 6.18.42 · 그날의 initrd로 쟀다. 측정 스크립트는 저장소 밖의
`/tmp/run/mp0/probe.sh`다. `render` 체인의 QEMU 호출에 `-usb -device usb-mouse` 또는 `-usb -device usb-tablet`을 더해
부팅하고, HMP monitor로 `info mice` · `mouse_move` · `mouse_button`을 보내고, 게스트 셸에서
`head -c 240 /dev/input/event2 | cat -v`로 이벤트 바이트를 봤다. 시리얼 로그는 `/tmp/run/mp0/mouse/serial.log` ·
`/tmp/run/mp0/tablet/serial.log`였다(저장소에 없다).

1. 커널을 안 고쳐도 USB 마우스는 evdev가 된다. `-usb -device usb-mouse`로 뜨면 부팅 로그에 이 두 줄이 나온다.

   ```
   input: QEMU QEMU USB Mouse as /devices/pci0000:00/0000:00:01.2/usb1/1-1/1-1:1.0/0003:0627:0001.0001/input/input3
   hid-generic 0003:0627:0001.0001: input: USB HID v0.01 Mouse [QEMU QEMU USB Mouse]
   ```

   게스트의 `/proc/bus/input/devices`로 성질을 봤다. `H: Handlers=event2`, `B: PROP=0`, `B: EV=17`(SYN · KEY · REL · MSC),
   `B: REL=903`(`REL_X` 0 · `REL_Y` 1 · `REL_WHEEL` 8 · `REL_WHEEL_HI_RES` 11). event0은 Power Button, event1은 AT
   키보드였다. `-usb`가 있어야 usb-bus가 생긴다(pc 머신의 PIIX3 UHCI).

2. `-display none`에서도 HMP의 `mouse_move dx dy [dz]` · `mouse_button N`이 그 장치로 간다. `info mice`가 이렇게 답했고 별표가
   지금의 대상(usb-mouse)이다.

   ```
     Mouse #2: QEMU PS/2 Mouse
   * Mouse #3: QEMU HID Mouse
   ```

   게스트에서 읽은 `input_event`(24바이트: sec 8 · usec 8 · type 2 · code 2 · value 4) 열 개를 `cat -v`로 풀었다.

   | HMP | 게스트가 받은 것 |
   |---|---|
   | `mouse_move 10 5` | `EV_REL REL_X 10`(`^B^@ ^@^@ ^J...` — 행 경계에 잘렸다) · `EV_REL REL_Y 5`(`^B^@^A^@^E^@^@^@`) · `SYN_REPORT` |
   | `mouse_button 1` | `EV_MSC MSC_SCAN 0x90001`(`^D^@^D^@^A^@^@^@`) · `EV_KEY BTN_LEFT(0x110) 1`(`^A^@^P^A^A^@^@^@`) · `SYN_REPORT` |
   | `mouse_button 0` | `MSC_SCAN` · `BTN_LEFT 0` · `SYN_REPORT` |
   | `mouse_move 0 0 1` | `EV_REL REL_WHEEL(8) 1`(`^B^@^H^@^A^@^@^@`) |

   `mouse_button`의 비트는 1 = 왼쪽, 2 = 오른쪽, 4 = 가운데다(QEMU HMP 문서).

3. `-usb -device usb-tablet`은 절대 좌표 장치다. 이름 `QEMU QEMU USB Tablet`, `B: EV=1f`(ABS가 더해졌다), `B: REL=900`(휠만),
   `B: ABS=3`(`ABS_X` · `ABS_Y`), `PROP=0`. `info mice`에 `QEMU HID Tablet (absolute)`로 나온다. 바이트는 못 봤다 —
   `head -c 240`이 차기 전에 측정이 끝났다.

4. QEMU는 `-device usb-mouse`가 없어도 pc 머신에 `QEMU PS/2 Mouse`를 갖고 있다(위 `info mice`의 #2). 게스트 커널의
   `CONFIG_INPUT_MOUSE`(psmouse)가 꺼져 있어 지금은 노드가 안 생긴다. `MOUSE_PS2`를 켜면 모든 pc 체인에 i8042 AUX 마우스
   evdev가 하나 더 생긴다. TF-M3의 실측과 같다.

5. 게스트에 `od` · `xxd` · `hexdump` · `timeout`이 없다. 바이트를 보려면 `head -c N … | cat -v`를 쓴다. HMP `sendkey colon`은
   invalid parameter이고 `:`는 `shift-semicolon`이다.

6. `kernel/.config`(6.18.42)의 지금 값. `rg`로 각 심볼의 줄을 봤다.

   | 켜짐 | 꺼짐 |
   |---|---|
   | `INPUT_EVDEV` · `KEYBOARD_ATKBD` · `SERIO_I8042` · `SERIO_LIBPS2` · `HID` · `HID_GENERIC` · `USB_HID` · `USB_XHCI/EHCI/OHCI/UHCI` · `I2C=y` · `I2C_HID`(core만, `HID_SUPPORT`가 저절로) · `ACPI` · `KALLSYMS` | `INPUT_MOUSE`(그래서 `MOUSE_PS2` · synaptics · elantech · alps 심볼 줄 자체가 없다) · `INPUT_MOUSEDEV` · `INPUT_TABLET` · `INPUT_TOUCHSCREEN` · `INPUT_MISC`(그래서 `INPUT_UINPUT`도 없다) · `RMI4_CORE` · `HID_MULTITOUCH` · `HID_MAGICMOUSE` · `I2C_HID_ACPI` · `I2C_HID_OF` · `I2C_I801` · `I2C_DESIGNWARE_CORE/PLATFORM` · `MFD_INTEL_LPSS_*` · `PINCTRL` · `GPIOLIB` · `VIRTIO_INPUT` · `NEW_LEDS` |

   `HID_APPLE`은 줄 자체가 없고 `IKCONFIG`도 없다. 그래서 실제 노트북 터치패드(I2C-HID + hid-multitouch, PS/2
   synaptics · elantech, RMI4 SMBus)는 지금 커널에서 노드조차 안 생긴다. `docs/guides/running-tars.md`의 "안 되는 것"
   표에 있는 "커널에 드라이버는 있지만 `terminal`이 포인터를 안 읽는다"는 틀렸다(닫을 때 고친다).

7. QEMU 10.0.13의 입력 장치는 `usb-mouse` · `usb-tablet` · `usb-wacom-tablet` · `virtio-mouse-pci` · `virtio-tablet-pci` ·
   `virtio-multitouch-pci` · `virtio-input-host-pci` · `vmmouse`다(`-device help`). 터치패드(`INPUT_PROP_POINTER` + ABS_MT)
   에뮬레이션은 없다. `virtio-multitouch`는 터치스크린 모양(`DIRECT`)이고 QMP `input-send-event`의 `mtt` 타입으로만
   움직인다(HMP에는 없다). 그래서 게이트가 터치패드 경로를 QEMU 안에서 보려면 (a) 게스트 uinput으로 가짜 터치패드를
   만들어 되감거나(`INPUT_MISC` + `INPUT_UINPUT`이 필요하고, 부팅 뒤에 생기는 장치라 핫플러그 탐색이 전제다) (b) 호스트
   단위 테스트로 상태 기계만 보고 커널은 심볼로 보는(UW 방식) 둘 중 하나다. 결정 10이 (a)를 고르고 (b)를 보조로 둔다.

8. 모니터 포트. lessons는 "새 체인은 45481부터"라 적었지만 `service/check.sh`가 45481~45486을, `pane/check.sh`가 45487을
   쓰고 그 파일의 주석이 "45455~45486"을 적었다. 새 체인은 45488부터가 안전하다. 이 실측은 45490 · 45491을 썼다.

### design을 쓰며 코드를 읽어 확인한 것(2026-10-05, `62896bb`)

측정이 아니라 읽기다. 줄 번호는 참고값이고 심볼로 `rg`한다(lessons "핵심 파일").

9. `input.zig`의 `readKeys`는 이벤트 64개까지 읽고 `EV_KEY`가 아니면 버린다. `openDevice`는 `O_RDONLY` 블로킹이고
   EVIOCGRAB이 없다. `Action`은 `bytes` · `scroll` · `copy` · `redraw` · `pane`이고, `input.zig`는 `vt.zig`를 import하지
   않는다.
10. copy mode의 상태는 두 곳이다. `input.State.mode`(normal · copy · find)는 `Cmd+Shift+C` · `Esc` · `y` · `Cmd+C` ·
    `/` · 프롬프트의 `Esc` · `Enter`가 바꾼다. `vt.Screen`의 `copy_cursor` · `copy_kind` · `copy_anchor_y`는 `main.zig`의
    copy 배선이 바꾸고, `feed`가 가지치기를 만나면 `copyExit`을 스스로 부른다 — 그때 `input.State.mode`는 안 바뀐다.
11. `copyPin` · `copyApply` · `copyPlace`는 private이다. `copyApply`는 `copy_kind`가 null이면 아무것도 안 한다.
    `copyYank`는 문자열을 뽑은 뒤 `copyExit`을 부른다.
12. `main.zig`의 poll은 타임아웃이 `-1`이다. fd 배열은 매 바퀴 다시 짓고 `fds[0]`이 키보드, 그 뒤가 PTY이며
    `fd_panes[nfds - 1]`로 패널을 찾는다. 렌더는 루프 끝의 `needs_redraw` 하나가 문지기이고 순서는 `renderBackdrop` →
    비포커스 `renderPane` → 포커스 `renderPane` → `renderFinish`(`drawPrompt` · `drawStatus` · `present`) → 덤프들이다.
    덤프는 다시 그린 프레임마다 `screen>`을 격자 전체로 찍는다. `present`는 매번 SETCRTC이고 `kms: set crtc` 줄을 찍는다.
13. 게이트의 프레임버퍼는 1280 × 800이고 격자는 155 × 47이다(`terminal: grid 155x47 (fb 1280x800)`). 격자는 (20, 20)에서
    시작해 (1260, 772)에서 끝나고, 그 아래 28픽셀이 상태 줄의 여백이다. 패널 둘이면 왼쪽이 `0,0 77x47`, 구분선이 77열,
    오른쪽이 `78,0 77x47`이다(WP).
14. init의 `devices.zig`는 sysfs 비트맵(높은 워드가 앞)을 읽고 `EV_REL` · `EV_ABS` 상수가 없다. `devices_test`에
    `BTN_LEFT`만 가진 가짜 마우스가 "키보드로 안 뽑힌다"로 이미 있다. 체인들은 event 번호를 판정에 쓰지 않는다 —
    `device` · `terminal` 체인은 "event0으로 물러나지 않았다"만 본다. 장치 수를 세는 검사도 없다.
15. HD 조사 6이 sysfs를 고른 이유는 `EVIOCGBIT`이 매크로라 translate-c로 안 넘어오는 것이었다. `drm.zig`의 `drmIowr`가
    ioctl 번호를 손으로 짓는 선례다. `c_input` 번역(`linux/input.h`)은 게스트용과 호스트 테스트용이 따로 있다.

## 닫을 때(lead의 몫)

- 이 design의 `Status:`를 `끝났다(날짜)`로 고친다.
- `CLAUDE.md`의 완료 표에 한 줄.
- `docs/decisions/project_pointer_devices.md`를 만들고 `MEMORY.md`에 한 줄.
- 다시 연 결정에 한 줄씩 덧붙인다. HD design 결정 3과 비목표(핫플러그 · 마우스), WP design 비목표("드래그 · 마우스"),
  CM design 비목표("마우스"), IP design 비목표, TF design 비목표. 각각 "PD가 이것을 바꿨다"와
  `[[project_pointer_devices]]`.
- `docs/guides/running-tars.md`. "안 되는 것" 표의 터치패드 줄을 고치고(실측 6), 실기에서 볼 것 셋("실기에서 같은
  코드로 가는가" 절)을 실기 절에 둔다.
- `docs/guides/lessons.md`. 포트 목록(45488 · 45489), "새 체인은 45490부터", 핵심 파일 지도에 `pointer.zig` ·
  `touchpad.zig`, 이월 숙제에 위험 2 · 5와 비목표 1.
- `HANDOFF.md`.

## 관련

- `docs/specs/2026-08-20-tars-hardware-discovery-design.md` — 결정 1(sysfs) · 2(capability 판정) · 3(PID 1이 찾는다) ·
  조사 6(ioctl 매크로). 결정 1이 포인터에 한해 그 모양을 바꾼다
- `docs/specs/2026-08-24-tars-copy-mode-design.md` — 결정 1(모드는 `input`, 선택은 `vt`) · 3(모드가 키를 삼킨다) ·
  5(앵커는 tracked selection). 결정 6이 그 기계를 그대로 쓴다
- `docs/specs/2026-10-03-tars-workspace-panes-design.md` — 결정 2(`layout.zig`가 순수) · 4(조합 중 한글을 확정한 뒤
  옮긴다) · 6(`paneOrigin`). 결정 5가 그 역변환이다
- `docs/specs/2026-10-03-tars-copy-indicator-design.md` — 전용 색과 `ink` 판정의 이유
- `docs/specs/2026-09-28-tars-usb-wireless-design.md` — QEMU에 없는 장치를 심볼 · alias로 보는 방식(결정 9)
- `docs/specs/2026-08-30-tars-render-cost-design.md` — 프레임 비용(결정 4 · 위험 1)
- `docs/decisions/project_zig_c_uapi_rule.md` — ioctl 매크로를 손으로 짓는 이유
- `docs/decisions/project_gate_screen_echo.md` — 판정 글자와 친 글자를 겹치지 않게 하는 규율
