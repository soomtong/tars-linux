# TARS Keyboard Hotplug — Design

접두사: KH

Status: design(2026-11-02). M0 전.

관련 문서: `2026-10-05-tars-pointer-devices-design.md`(PD. 장치를 terminal이 스스로 찾고 uevent로 부팅 뒤 장치를 잡는
길 — 이 설계는 그 길에 키보드를 싣는다) · `2026-11-01-tars-bluetooth-design.md`(BT. 확인 7 · 비목표 1이 이 서브프로젝트를
남겼다) · `docs/decisions/project_device_discovery.md`(HD. init이 capability로 키보드를 고르는 규칙) ·
`docs/decisions/project_real_machine.md`(RM. `KEYBOARD_WAIT_MS` 3초가 생긴 이유).

## 한 줄 요약

terminal이 키보드를 포인터와 같은 길로 스스로 찾는다 — 부팅 때 `/dev/input`을 훑고, 그 뒤는 uevent로 새 노드를 연다.
키보드는 여러 개가 동시에 열리고, 한/영 · 조합 · CapsLock · copy mode 같은 상태는 모두가 하나를 같이 쓴다. 장치가
빠지면 그 fd를 닫고 눌려 있던 수정키를 푼다. 목표는 BT 키보드와 부팅 뒤에 꽂은 USB 키보드가 글자를 치는 것이다.

## 왜 지금인가

2026-11-02 Bluetooth를 닫은 자리에서 첫 후보로 둔 것을 사용자가 골랐다. BT는 키보드를 페어링하고 연결하고 evdev 노드까지
만들지만, terminal이 그 노드를 안 연다(BT design 확인 7). BT 마우스는 PD의 핫플러그로 끝까지 가는데 키보드만 멈춰 있다 —
이것이 없으면 BT의 절반이 값이 없다. 같은 틈이 USB에도 있다. 부팅 뒤에 꽂은 USB 키보드는 지금 아무것도 못 친다.

## 착수 전에 아는 것 (2026-11-02에 소스에서 확인)

### 확인 1 — 키보드는 init이 고른 fd 하나다

init의 `devices.resolveKeyboard`가 `/sys/class/input`을 훑어 키보드 하나를 고르고(`looksLikeKeyboard` — `EV_KEY`가 있고
`KEY_ESC`부터 `KEY_D`까지 서른두 키가 다 있다), 그 경로를 terminal argv로 넘긴다(`screen_args`의 `device_path`). terminal은
`openKeyboard`에서 그 경로를 블로킹으로 열고, 못 열면 `FATAL`로 끝난다. 그 뒤로 `fds[0]` 하나를 poll한다.

init은 키보드가 안 보이면 25ms마다 다시 보며 3초까지 기다리고(`KEYBOARD_WAIT_MS`, RM-M3), 그래도 없으면 `event0`으로
떨어진다 — 그 노드는 대개 전원 버튼이다. 즉 키보드 없이 부팅한 기계(BT 키보드만 쓰는 노트북)는 지금 부팅이 3초 늦고,
terminal은 전원 버튼을 키보드로 연다.

### 확인 2 — 포인터는 이미 terminal이 스스로 찾는다

PD-M0이 놓은 길이다. `openPointers`가 uevent netlink 소켓을 먼저 열고(그룹 1, 커널이 보내는 것) 그다음에 `/dev/input`을
훑는다(`scanPointers`) — 반대 순서면 둘 사이에 생긴 장치를 놓친다. 그 뒤로 uevent 소켓이 깨우면 `drainUevents`가
`pointer.ueventAddedNode`(`ACTION=add` · `SUBSYSTEM=input` · `DEVNAME=input/eventN`)로 노드 이름을 꺼내 `tryOpenPointer`에
넘긴다. 그 함수가 열고, ioctl로 성질(`EVIOCGBIT` 다섯)을 묻고, 포인터가 아니면 닫는다. 빠진 장치는 `remove` uevent가
아니라 그 fd의 `POLLERR` · `POLLHUP` · `ENODEV`로 알고 닫는다(PD 결정 1). `ENOBUFS`면 디렉터리를 다시 훑는다.

즉 키보드에 필요한 것의 절반 — 새 노드가 생겼다는 것을 알고, 그 노드를 열어 성질을 묻는 일 — 이 이미 있다. 지금은
키보드인 노드를 열어 본 뒤 "포인터가 아니다"로 닫는다(`pointer> skip … kind=none`).

### 확인 3 — `input.State`에는 손의 상태와 사람의 상태가 섞여 있다

`input.State`의 필드를 두 갈래로 나눌 수 있다.

| 갈래 | 필드 | 뜻 |
|---|---|---|
| 손(물리) | `shift_left/right` · `ctrl_left/right` · `alt_left/right` · `meta_left/right` · `caps_tap` · `lctrl_tap` · `dictate_tap` | 지금 어느 키가 눌려 있는가, 누름과 뗌 사이에 무엇이 끼었는가 |
| 사람(논리) | `hangul_on` · `hangul_buf` · `commit_buf` · `caps_lock` · `mode` · 자판 둘 · `toggles` | 지금 한글인가, 조합 중인 음절, 대문자 잠금, copy mode |

사람 쪽은 키보드가 몇 개든 하나여야 한다. 내장 키보드로 한글을 켜고 USB 키보드로 치면 한글이 나와야 하고, 조합 중이던
음절은 어느 키보드의 다음 키로든 이어져야 한다. 손 쪽은 원래 장치마다 따로다 — 다만 이것도 하나로 합치는 것이 흔한
선택이다(X11의 core keyboard, macOS는 모든 키보드의 수정키를 합친다). 수정키 필드는 `input.zig` 안에서 16자리가 쓴다.

### 확인 4 — 키보드 fd가 오류를 내면 지금 terminal이 바쁜 루프에 빠진다

`arm`이 `fds[0]`을 `POLLIN`으로 걸고 `tick`은 `revents & POLLIN`일 때만 `readKeyboard`를 부른다. 부팅 때 고른 USB 키보드를
뽑으면 poll이 그 fd에 `POLLERR`(또는 `POLLHUP`)를 매 바퀴 곧바로 돌려주는데, 아무도 그것을 안 보고 fd도 안 닫는다. PD
결정 1이 포인터에 대해 적어 둔 바로 그 함정(CPU를 다 쓴다)이 키보드에는 아직 열려 있다. 소스로 본 것이고 실측은 M0이다.

### 확인 5 — 게이트의 자리

- `terminal/check.sh`(113행)와 `input/check.sh`(132행)가 실패했을 때 찍는 표지 목록에 `terminal: opened /dev/input/event`가
  있다. 판정이 아니라 실패 진단의 목록이다. `device/check.sh` · `machine/check.sh`는 init의 `tars-init: keyboard device` 줄을
  판정으로 본다.
- `machine/check.sh`는 q35 `i8042=off`로 PS/2를 끄고 `-device usb-kbd`를 부팅 때 꽂는다(RM-M1) — "키보드가 USB 하나뿐인
  기계"의 선례다. 부팅 뒤에 `device_add`로 장치를 꽂는 선례는 `usb-mouse`(PD, measurements 78)와 `usb-net`(nic 체인)이다.
- QEMU HMP `sendkey`가 키보드가 여럿일 때 어느 장치로 가는지는 아직 모른다(위험 1).

## 결정

### 결정 1 — terminal이 키보드를 스스로 찾는다. 길은 포인터의 것 하나다

처음 훑기와 uevent의 `add`가 지나는 함수를 하나로 둔다. 노드를 한 번 열고 성질을 한 번 물은 뒤, 포인터면 포인터 칸에,
키보드면 키보드 칸에 넣는다. 지금 `tryOpenPointer`가 하는 일(열기 · `readCaps` · 이름 · 분류)에 키보드 갈래를 더하는
모양이고, 이름은 `tryOpenInput` 쯤이 된다. 장치를 두 번 열지 않는 것은 경로 비교 그대로다.

argv의 `device_path`는 프로토콜(`screen_args`)에 그대로 남기고 terminal이 열지 않는다. init의 키보드 고르기와 그 로그는
`device` · `machine` 체인이 판정으로 보므로 이 서브프로젝트에서는 안 건드린다(비목표 2). 이제 "하드웨어를 살펴 고르는 일은
PID 1이"(CP)라는 규칙에서 입력 장치는 빠진다 — 포인터가 PD에서 이미 빠졌고 키보드가 따라간다. 핫플러그를 하려면 장치를
아는 쪽이 장치를 계속 지켜보는 프로세스여야 하고, 그것은 terminal이다.

키보드 fd도 `O_NONBLOCK | O_CLOEXEC`로 연다. 지금 키보드만 블로킹인 이유는 "poll이 깨운 뒤 한 번만 읽는다"였는데, 키보드가
여럿이면 깨운 fd만 읽으므로 블로킹일 이유가 없고, 빠지는 순간의 read가 막히지 않는 편이 안전하다. 셸이 fd를 물려받지 않는
것(`CLOEXEC`)도 포인터와 같다.

### 결정 2 — 키보드의 판정은 init의 `looksLikeKeyboard`와 같은 기준이다

`EV_KEY`가 있고 `KEY_ESC`(1)부터 `KEY_D`(32)까지가 다 있다. 같은 기계에서 init이 "키보드"라고 부르는 것과 terminal이
여는 것이 달라지면 로그를 읽는 사람이 헷갈린다. 비트맵의 순서는 다르다 — init은 sysfs의 "높은 워드가 앞" 문자열이고
terminal은 ioctl의 바이트 배열이다(`pointer.bitSet`의 주석). 그래서 함수는 따로 두고 기준(첫 키 · 끝 키)만 맞춘다. 순수
함수로 `pointer.zig` 옆(또는 `input.zig`)에 두어 단위 검사가 비트맵으로 본다.

이 기준이 거르는 것: 전원 버튼(`KEY_POWER`만), `Video Bus`(밝기 키), `PC Speaker`, 노트북 제조사의 핫키 장치, 키보드에
딸린 `Consumer Control`(볼륨 · 미디어 키) 노드. 앞의 다섯은 글자 키가 없다. 미디어 키 노드를 안 여는 것은 지금과 같다 —
그 키는 지금도 terminal에 안 온다.

한 노드가 키보드이자 포인터일 수 있다(키보드에 터치패드가 붙은 BT 장치, 일부 무선 수신기). 그때는 칸 둘에 fd 둘로 연다.
evdev는 fd마다 모든 이벤트를 따로 내주므로 둘이 서로를 굶기지 않는다. 키보드 쪽은 `BTN_MISC`(0x100) 이상의 코드를 버린다
— 마우스 버튼이 CapsLock tap이나 받아쓰기 더블 탭을 끊지 않게.

### 결정 3 — `key_state`는 하나이고, 모든 키보드가 같이 쓴다

확인 3의 사람 쪽은 하나여야 한다는 것이 이 결정의 근거다. 손 쪽만 장치마다 나누는 길(`State`를 두 구조체로 쪼개고 수정키를
장치별로 OR)도 있지만, 얻는 것이 "한 키보드의 Shift와 다른 키보드의 글자는 조합이 아니다" 하나이고 그것은 사람이 바라는
동작도 아니다(X11 · macOS가 합친다). 잃는 것은 `input.zig`의 수정키 16자리와 tap 판정을 장치 인자와 함께 다시 쓰는 일이다.
그래서 `State`는 지금 모양 그대로 하나를 두고, `readKeys`를 키보드 fd마다 같은 `&key_state`로 부른다.

합친 것의 대가는 결정 4가 치른다.

### 결정 4 — 장치가 빠지면 fd를 닫고 손의 상태를 푼다

빠진 것은 포인터와 같이 `POLLERR` · `POLLHUP` · read의 `ENODEV`(또는 0)로 안다. 그때 칸을 비우고, `State`에 새로 둘
`releaseHeld()`를 부른다 — 수정키 여덟을 거짓으로, `caps_tap` · `lctrl_tap` · `dictate_tap`을 처음으로. Shift를 쥔 채 BT
키보드가 끊기면 뗌 이벤트가 영영 안 오므로, 이것이 없으면 다른 키보드로 친 글자가 계속 대문자다.

사람 쪽은 안 건드린다. 조합 중인 음절은 남고(다른 키보드의 다음 키가 잇는다), 한/영 · CapsLock · copy mode도 그대로다.

합친 것의 대가가 여기 있다. 키보드 A로 Shift를 쥔 채 키보드 B가 빠지면 A의 Shift도 풀린다. 사람이 그렇게 할 일이 드물고,
A의 Shift를 다시 누르면 돌아온다. 장치별로 "이 장치가 누른 수정키" 비트 여덟을 들면 피할 수 있지만 그것이 결정 3에서 안 고른
길의 절반이다 — 실기가 이것을 문제로 만들면 그때 더한다(비목표 5).

이 결정이 확인 4의 바쁜 루프도 닫는다. 부팅 때부터 있던 키보드도 이제 같은 칸 중 하나라서, 빠지면 같은 길로 닫힌다.

### 결정 5 — 키보드 칸은 여덟이고, poll 자리는 포인터 앞이다

`MAX_KEYBOARDS = 8`. 노트북 내장 하나 · USB 하나 · BT 하나가 흔한 최대이고, 무선 수신기가 노드를 여럿 낸다. 포인터
(`pointer.MAX_DEVICES` 8)와 같은 수라 칸의 모양을 맞추기 쉽다. 넘치면 포인터처럼 `skip … full` 한 줄을 찍고 닫는다.

`fds`의 자리는 `[0]` uevent 소켓 · `[1..kbd_end]` 키보드 · `[kbd_end..pty_base]` 포인터 · PTY · 받아쓰기 둘이 된다. 지금 고정
자리인 `fds[0]`(키보드) · `fds[1]`(uevent)을 쓰는 곳이 바뀐다. 키보드가 포인터보다 먼저인 것은 지금 `tick`의 순서(키보드 →
포인터 → PTY, PD 결정 3) 그대로다. 크기는 1 + 8 + 8 + 72 + 2다.

한 바퀴에 여러 키보드가 깨우면 칸 순서대로 `readKeyboard`를 부른다. 지금 `readKeyboard`는 그 머리에서 포커스 패널을 한 번
잡는데, 앞 키보드의 키가 워크스페이스를 바꿨으면 뒤 키보드의 키는 바뀐 쪽으로 가야 한다 — 키보드마다 머리에서 다시 잡으므로
그대로 맞다.

### 결정 6 — 로그는 `keyboard>` 줄 셋이다

```
terminal: keyboard> open /dev/input/event3 name=AT Translated Set 2 keyboard
terminal: keyboard> close /dev/input/event3
terminal: keyboard> skip /dev/input/event9 full name=…
```

`name=`은 포인터처럼 맨 끝이다(공백이 있다). 키보드가 아닌 노드에는 `keyboard>` 줄을 안 찍는다 — 그 노드는 이미
`pointer> skip … kind=none`이 한 줄씩 찍고, 둘을 찍으면 노드마다 줄이 둘이 된다.

`pointer>` 줄은 지금 그대로 둔다. 키보드로 연 노드도 포인터 층의 판정은 `skip … kind=none`이고, 그 줄이 먼저 나오고
`keyboard> open`이 뒤따른다. 두 층이 각자 자기 판정을 찍는 것이다. `pointer/check.sh`(558행)가 AT 키보드 · 전원 버튼의
`pointer> skip … kind=none` 줄을 판정으로 보므로, 이 줄을 없애면 그 체인이 빨개진다.

`terminal: opened /dev/input/eventN` 줄은 없앤다. 두 체인의 실패 진단 목록(확인 5)을 `terminal: keyboard> open`으로 고친다.
판정에 쓰이는 줄이 아니므로 다른 체인은 안 움직인다. 이 줄이 찍히는 때도 바뀐다 — 지금은 준비 2(셸을 띄우기 전)이고, 이제는
준비 4(uevent 소켓을 연 뒤)다. 줄의 순서를 판정으로 보는 체인이 있는지는 M1이 `rg`로 다시 본다.

### 결정 7 — 키보드 없이 부팅해도 terminal은 뜬다

`openKeyboard`의 `FATAL` 갈래가 사라진다. 키보드가 0개면 terminal은 화면을 그리고 셸을 띄우고 기다린다 — BT 키보드만 쓰는
기계에서 페어링된 키보드가 연결되는 순간부터 글자가 간다. 단 그 기계가 BT를 켜고 페어링하려면 한 번은 다른 키보드가
있어야 한다(`bluetoothctl`을 쳐야 하므로) — 이것은 BT의 사실이고 이 설계가 바꾸지 않는다.

키보드 칸이 0개일 때 화면에 무언가를 띄울지는 안 정한다(비목표 6). 부팅 때 칸이 0이면 `keyboard> none` 한 줄은 찍는다 —
로그를 읽는 사람이 "왜 안 쳐지나"에서 처음 볼 자리다.

### 결정 8 — 게이트는 스물넷째 체인 `keyboard/check.sh`다

`machine` 체인처럼 q35 `i8042=off`로 PS/2를 끄고, 부팅 때 키보드를 하나도 안 꽂는다. 그 기계에서:

1. 부팅이 끝나고 `keyboard> none`이 찍힌다. terminal이 살아 있다(`screen>`).
2. `device_add usb-kbd,id=k1` → `keyboard> open … name=QEMU … USB Keyboard`. `sendkey`로 `echo` 한 줄을 쳐서 화면에 결과가
   나온다. 부팅 뒤에 꽂은 키보드가 글자를 친다 — 이 서브프로젝트의 목표 그 자체다.
3. `device_add usb-kbd,id=k2` → 둘째 `open`. 다시 한 줄을 친다(위험 1이 정하는 대로 둘 중 하나로 간다).
4. `device_del k2` → `keyboard> close`. 남은 k1으로 한 줄을 친다. 빠진 뒤에도 terminal이 바쁜 루프에 안 빠졌다는 것을
   이 줄이 제때 오는 것으로 본다.
5. 한/영을 켠 채 장치를 바꿔도 한글이 이어지는지(결정 3) — 한글을 켜고 k2를 다시 꽂아 거기서 친 글자가 한글인지.

BT 키보드의 길(bluetoothd → uhid/hidp → evdev)은 게이트가 못 본다(BT 위험 4 그대로). terminal에게는 evdev 노드가 부팅 뒤에
생긴다는 것만 같으면 되고, 그것을 usb-kbd가 본다. 체인의 monitor 포트는 45495다(RP-M0 예약 범위의 다음 자리).

## 위험

### 위험 1 — QEMU `sendkey`가 어느 키보드로 가는가

QEMU의 입력 층은 키 이벤트를 "활성" 키보드 핸들러 하나에 준다. usb-kbd가 꽂히는 순간 스스로를 활성으로 만드는지(그러면
늘 마지막에 꽂은 키보드로 간다), 빼면 앞의 것으로 돌아가는지를 모른다. M0이 연다. 원하는 장치로 못 보내면 QMP의
`input-send-event`(`device` 인자로 장치를 고른다)가 다음 길인데, 체인들은 HMP만 쓴다 — 그때는 결정 8의 3 · 5를 "꽂은
뒤 · 뺀 뒤에 친 키가 간다"로 줄인다.

### 위험 2 — 키보드 없는 부팅은 init이 3초를 기다린다

확인 1. 체인 하나가 3초 길어지고, BT 키보드만 쓰는 실기도 그렇다. 이 서브프로젝트는 init을 안 고치므로(비목표 2) 남는다.
3초가 체인의 다른 시간 상한을 넘기는지는 M0이 본다.

### 위험 3 — 실기에는 키보드처럼 생긴 노드가 더 있을 수 있다

제조사 핫키 장치 중에 키맵을 통째로 선언하는 것이 있으면 결정 2가 그것도 연다. 여는 것 자체는 해가 없다(그 노드는 글자를
안 낸다). 칸 여덟이 차는 것만 문제인데, 그만큼 많으면 `skip … full`이 보인다.

### 위험 4 — `fds` 자리가 바뀌는 수정이 넓다

결정 5. `fds[0]` · `fds[1]` · `fds[2..pty_base]`를 이름으로 쓰는 자리가 `main.zig`에 흩어져 있다(`arm` · `tick` ·
`readPointers`). 하나를 빠뜨리면 키 대신 uevent를 읽는 식의 엉뚱한 증상이 난다. M1은 이 자리를 숫자 대신 이름 있는 경계
(`kbd_end` · `pty_base`)로만 쓰게 바꾸고, 그 뒤 `rg 'fds\[[0-9]'`가 비어 있는지 본다.

### 위험 5 — 처음 훑기와 uevent가 같은 노드를 두 번 준다

포인터에서 이미 있는 함정이고 경로 비교로 막는다(`tryOpenPointer` 머리). 결정 1이 함수를 하나로 합치므로 그 비교가 키보드
칸도 보게 해야 한다 — 안 그러면 같은 키보드가 칸 둘에 열려 글자가 두 번 나온다. 단위 검사로는 안 보이고 체인의 "글자가
한 번 나온다"가 본다.

## 비목표

1. 장치마다 다른 `keyboard=apple|pc`. Alt · Cmd 맞바꿈은 지금처럼 기계 하나에 하나다 — MacBook 내장 키보드에 PC USB 키보드를
   꽂으면 둘 중 하나는 어긋난다. 장치 이름이나 vendor id로 고르려면 키가 늘어난다.
2. init의 키보드 고르기 · 3초 기다림 · argv의 `device_path` 걷기. 셋 다 이제 terminal에게 쓸모가 없지만, init의 줄을 두 체인이
   판정으로 보고 PID 1을 고치는 일이라 따로 한다(위험 2의 3초를 없애는 것이 그 일의 값이다).
3. `SYN_DROPPED` 뒤에 `EVIOCGKEY`로 눌린 키를 다시 맞추기. `readKeys`의 주석이 적어 둔 오래된 구멍이고 핫플러그와 상관없다.
4. 키보드 LED(CapsLock 불). 지금도 안 켠다.
5. 장치별 수정키(결정 3 · 4의 대가를 없애는 길).
6. 키보드가 하나도 없을 때 화면에 알리기.
7. BLE HID의 uhid 길을 게이트로 보기(BT 위험 4).

## Milestone

한 milestone이 끝나면 다음 plan을 그때 쓴다.

- KH-M0 — 실측, 코드 0줄. `i8042=off` q35에 키보드 없이 부팅해 init의 3초와 terminal이 연 노드(전원 버튼), 부팅 뒤
  `device_add usb-kbd`의 uevent 글자와 노드 수, `sendkey`가 꽂은 · 뺀 뒤 어느 키보드로 가는지(위험 1), 부팅 키보드를 뽑았을
  때의 바쁜 루프(확인 4)를 본다. 지금 게스트의 `/dev/input` 노드마다 결정 2의 판정이 무엇을 고르는지도.
- KH-M1 — `input.zig`(판정 · `releaseHeld` · `BTN_MISC` 거르기 · 단위 검사), `main.zig`(키보드 칸 · 하나로 합친 여는 길 ·
  `fds` 자리 · 닫기 · 로그 셋), 두 체인의 진단 목록, `running-tars.md`.
- KH-M2 — 체인 `keyboard/check.sh`(결정 8), mutation, 루트 게이트(24체인), 문서 닫기(BT design 확인 7 · 비목표 1의 "아직 못
  친다"를 고친다, `carryover.md`의 BT 항목, completed · 소개 페이지 · decisions · HANDOFF).
