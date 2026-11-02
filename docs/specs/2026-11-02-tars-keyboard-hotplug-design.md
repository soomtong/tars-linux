# TARS Keyboard Hotplug — Design

접두사: KH

Status: 끝났다(2026-11-02) — M0~M2, 결정 9 · 위험 7 · 시나리오 S1~S13 · 실측 1~11. terminal이 키보드를 포인터의 길로 열고, 키보드가 여럿 함께 열리고, 빠진 키보드는 닫히고 손의 상태가 풀린다. 체인 스물넷째 `keyboard/check.sh`(판정 여덟), mutation 셋 잡힘(하나는 7b를 더한 뒤).

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
결정 1이 포인터에 대해 적어 둔 바로 그 함정(CPU를 다 쓴다)이 키보드에는 아직 열려 있다. 소스로 본 것이고, M0 실측 4가 확인했다 — 1초에 약 100틱(CPU 하나를 다 쓴다), 로그는 한 줄도 없다.

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

M2에서 고친 것(실측 9). "영영 안 온다"는 반만 맞다. 커널은 장치를 해제할 때 눌린 키마다 뗌을 흉내 내 보내고
(`input_disconnect_device`), terminal이 그것을 evdev가 죽은 표시를 하기 전에 읽으면 Shift는 거기서 풀린다 — 보통은 그렇다.
`releaseHeld`가 푸는 것은 terminal이 그 틈을 놓친 경우다(그때 read는 `ENODEV`, poll은 `POLLHUP|POLLERR`라 버퍼의 뗌이
안 읽힌다). 결정은 그대로이고 이유가 좁아졌다. 커널이 보낸 뗌과 `releaseHeld`가 둘 다 오면 같은 값을 두 번 쓸 뿐이다.

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

`machine` 체인처럼 q35 `i8042=off`로 PS/2를 끄고, 부팅 때 키보드를 하나도 안 꽂는다. 키를 어느 장치로 보내는지는 M0
실측 1 · 2가 정했다. k1은 화면에 안 묶고 HMP `sendkey`로 친다(묶이지 않은 마지막 키보드로 간다). k2는
`display=gpu`로 화면에 묶고 QMP `input-send-event`의 `device: gpu`로 친다. 그래서 체인은 `-parallel none` ·
`virtio-gpu-pci,id=gpu` · `-qmp`를 함께 둔다(실측 2). 그 기계에서:

1. 부팅이 끝나고 `keyboard> none`이 찍힌다. terminal이 살아 있다(`screen>`).
2. `device_add usb-kbd,id=k1` → `keyboard> open … name=QEMU QEMU USB Keyboard`. `sendkey`로 `echo` 한 줄을 쳐서 화면에 결과가
   나온다. 부팅 뒤에 꽂은 키보드가 글자를 친다 — 이 서브프로젝트의 목표 그 자체다.
3. `device_add usb-kbd,id=k2,display=gpu` → 둘째 `open`. QMP로 한 줄을 친다 — k2의 글자다. 이어서 `sendkey`로 한 줄 — 여전히
   k1의 글자다. 두 장치가 동시에 열려 있다.
4. 장치를 건너는 조합(결정 3, 시나리오 검토 S2). QMP로 k2의 Shift 누름 → `device` 없는 QMP로 k1의 `a` → k2의 Shift 뗌.
   화면에 `A`가 나온다. 반대로 결정 3을 장치별로 바꾼 mutation은 `a`를 낸다.
5. 한/영을 켠 채 장치를 바꿔도 조합이 이어지는지(시나리오 검토 S3) — k1로 한글을 켜고 자음 하나, k2로 모음 하나.
6. `device_del k2` → `keyboard> close`. 남은 k1으로 한 줄을 친다. 빠진 뒤 terminal이 바쁜 루프에 안 빠졌는지는 게스트 셸에서
   terminal의 `/proc/<pid>/stat` utime + stime을 1초 간격으로 두 번 읽어 본다(실측 4 — 바쁜 루프면 1초에 약 100 늘어난다).
7. 빠진 키보드의 Shift(결정 4). k2를 다시 꽂고 QMP로 Shift를 누른 채 뗌 없이 `device_del k2` → k1로 `x`. 화면에 `x`다. KH-M2
   plan을 쓰며 더했다. 누가 풀었는지는 안 가린다 — 보통은 커널이 푼다(실측 9).
8. (7b) terminal이 커널의 뗌을 못 읽은 경우. 설정 디스크의 `kh-stop`이 terminal을 SIGSTOP으로 멈춘 동안 Shift를 쥔 k2를 빼고
   SIGCONT한다. 그 Shift를 푸는 것은 `releaseHeld`뿐이다. KH-M2에서 mutation이 7을 지나친 뒤 더했다.

BT 키보드의 길(bluetoothd → uhid/hidp → evdev)은 게이트가 못 본다(BT 위험 4 그대로). terminal에게는 evdev 노드가 부팅 뒤에
생긴다는 것만 같으면 되고, 그것을 usb-kbd가 본다. 체인의 monitor 포트는 45495, QMP는 45496이다(RP-M0 예약 범위의 다음 두 자리).

### 결정 9 — 키보드 fd도 단조 시계로 연다

`EVIOCSCLOCKID`에 `CLOCK_MONOTONIC`을 준다. 포인터가 MC design 결정 2에서 한 것과 같다. tap 판정(`Tap.up`)과 받아쓰기 더블
탭은 이벤트의 커널 시각끼리 뺀다. 키보드가 여럿이면 누름과 뗌, 첫 탭과 둘째 탭이 서로 다른 fd에서 올 수 있다(시나리오 검토
S5 · S6). 시계는 fd마다 따로 고르는 값이므로, 모든 키보드를 같은 시계로 열어야 그 뺄셈이 뜻을 가진다. 실패해도 장치는 쓰고
`keyboard> clock … error=` 한 줄을 찍는다(포인터와 같다).

부수 효과로 지금 있는 작은 구멍도 닫힌다. 키보드는 지금 기본값인 `CLOCK_REALTIME`이라, chronyd가 시계를 맞추는 순간에 걸친
tap은 시간 차가 튄다(MC-M0 확정 1이 포인터에서 본 것과 같은 일). 시각은 "얼마나 지났나"로만 쓰고 날짜로는 안 쓰므로 바꿔도
잃는 것이 없다.

## 여러 키보드를 함께 쓸 때 (시나리오 검토, 2026-11-02)

사용자 요청으로 결정 3(상태 하나를 같이 쓴다) · 결정 4(빠지면 손의 상태를 푼다)를 동시 사용 시나리오에 대 봤다. 판정의
근거는 `input.zig`의 `Tap`(누름 없는 뗌은 tap이 아니다, 자동 반복은 누른 시각을 안 덮는다)과 커널 input core의 자동
반복(장치마다 따로, 그 장치에서 마지막으로 누른 키 하나)이다.

| | 시나리오 | 결정 3 · 4 아래의 동작 | 판정 |
|---|---|---|---|
| S1 | 노트북 내장 + 외장 USB(또는 BT). 한 번에 하나로 친다 | 둘 다 열려 있고 어느 쪽 키든 같은 상태로 간다. 한/영 · 조합 · CapsLock이 바꿔 잡아도 이어진다 | 목표 그대로 |
| S2 | A의 Shift · Ctrl · Cmd를 누른 채 B의 글자 | 수정키가 합쳐지므로 조합이 된다(대문자 · 제어 문자 · 단축키) | 의도한 동작(X11 · macOS와 같다). 게이트 6 |
| S3 | 한글 조합 중에 키보드를 바꿔 잡는다(A의 ㅎ, B의 ㅏ) | `hangul_buf`가 하나라 `하`로 이어진다 | 의도한 동작. 게이트 5 |
| S4 | 조합 중에 A가 끊긴다(BT 절전 · 선 뽑힘) | `releaseHeld`는 사람 쪽을 안 건드린다. 음절은 화면에 남고 B의 다음 키가 잇거나 확정한다 | 의도한 동작 |
| S5 | A의 왼쪽 Ctrl을 누르고 B의 왼쪽 Ctrl을 눌렀다 뗀다 | `lctrl_tap`이 하나다. B의 누름은 이미 `held`라 무시되고, B의 뗌이 A의 누름에 짝지어져 짧으면 한/영이 바뀐다. 그 뒤 A가 쥔 Ctrl도 `ctrl_left = false`로 풀린다 | 결함이지만 받아들인다 — 한 사람이 같은 수정키를 두 키보드에서 겹쳐 쥘 일이 드물다. 장치별 수정키(비목표 5)가 고치는 자리다 |
| S6 | 받아쓰기 더블 탭을 A와 B의 오른쪽 Cmd로 한 번씩 | 판정이 하나라 더블 탭이 된다 | 받아들인다. 결정 9가 없으면 두 fd의 시계가 같다는 보장이 없다 |
| S7 | A의 글자를 길게 눌러 반복 중에 B의 글자를 누른다 | 커널의 반복은 장치마다 따로라 A의 반복이 안 멈춘다. `aaabababab`처럼 섞인다. 한 키보드였으면 B를 누르는 순간 A의 반복이 멈춘다 | 결함이지만 받아들인다 — 두 손으로 두 키보드의 글자를 겹쳐 누르는 경우다. 고치려면 키 하나를 누를 때 다른 장치의 반복을 버려야 하는데, 그러면 반복을 우리가 다시 만들어야 한다 |
| S8 | 한 poll 바퀴에 A와 B 둘 다 읽을 것이 있다 | 칸 순서대로 읽는다. 시각 순서가 아니다. B의 Shift가 먼저 눌렸어도 A의 글자가 먼저 처리되면 소문자다 | 위험 7. 사람의 손으로는 두 장치의 누름 간격이 수십 ms인데 한 바퀴는 1ms 안이라 드물다 |
| S9 | 한 물리 키가 두 노드로 온다(키보드 하나가 같은 키를 두 인터페이스로 보고) | 두 칸에 열려 글자가 두 번 나온다 | 위험 6. 게이트로는 못 본다 |
| S10 | 새 키보드를 꽂는 순간 그 키보드의 키가 눌려 있다 | 연 뒤 첫 이벤트가 누름 없는 뗌이다. 수정키는 거짓이 되고(원래 거짓), `Tap.up`은 `held`가 거짓이라 tap이 아니다 | 해 없음 |
| S11 | BT 키보드가 절전 뒤 다시 붙는다 | 옛 노드가 빠지고(`close` · `releaseHeld`) 새 번호로 생긴다(`open`). 같은 번호가 곧바로 다시 쓰이면 PD 결정과 같은 이유로 닫기가 uevent보다 먼저다 | 의도한 동작. 게이트 4가 같은 길 |
| S12 | 두 사람이 두 키보드로 같은 화면을 친다 | 상태가 하나라 서로의 한/영 · 수정키가 섞인다 | 범위 밖. TARS는 한 사람의 기계다 |
| S13 | `keyboard=apple` 기계에 PC 키보드를 더 꽂는다 | Alt · Cmd 맞바꿈이 기계 하나에 하나라 한쪽이 어긋난다 | 비목표 1 |

검토의 결론. 결정 3 · 4는 그대로 간다. 결함 둘(S5 · S7)은 "한 사람이 두 키보드에서 같은 순간에 겹쳐 누른다"는 경우에만
나타나고, 그것을 고치는 길(장치별 손의 상태 · 장치를 건너는 반복 정리)은 결정 3에서 안 고른 길이다. 이 검토가 새로 더한
것은 결정 9(시계), 게이트 6(장치를 건너는 조합), 위험 6 · 7이다.

## 위험

### 위험 1 — QEMU `sendkey`가 어느 키보드로 가는가

QEMU의 입력 층은 키 이벤트를 "활성" 키보드 핸들러 하나에 준다. usb-kbd가 꽂히는 순간 스스로를 활성으로 만드는지(그러면
늘 마지막에 꽂은 키보드로 간다), 빼면 앞의 것으로 돌아가는지를 모른다. M0이 연다. 원하는 장치로 못 보내면 QMP의
`input-send-event`(`device` 인자로 장치를 고른다)가 다음 길인데, 체인들은 HMP만 쓴다 — 그때는 결정 8의 3 · 5를 "꽂은
뒤 · 뺀 뒤에 친 키가 간다"로 줄인다.

닫음(M0 실측 1 · 2). `sendkey`는 마지막에 꽂은 키보드로 가고, 빼면 앞의 것으로 돌아간다. 장치를 골라 보내는 길도 있다 — 키보드를
화면에 묶고 QMP로 그 화면을 고른다. 결정 8을 그 두 길로 고쳤다.

남는 것 하나. PS/2 키보드가 있는 기계(체인 대부분)에 usb-kbd를 꽂으면 `sendkey`가 그쪽으로 넘어간다(실측 1의 부팅 B). M1
전의 terminal은 그 키를 못 읽으므로, KH 전에 그런 체인을 만들었다면 키가 사라졌을 것이다. M1 뒤에는 둘 다 읽으므로 문제가 아니다.
다만 앞으로 PS/2 기계에 usb-kbd를 꽂는 체인은 그 뒤의 키가 USB 키보드에서 온다는 것을 안다.

### 위험 2 — 키보드 없는 부팅은 init이 3초를 기다린다

확인 1. 체인 하나가 3초 길어지고, BT 키보드만 쓰는 실기도 그렇다. 이 서브프로젝트는 init을 안 고치므로(비목표 2) 남는다.
3초가 체인의 다른 시간 상한을 넘기는지는 M0이 본다.

M0 실측 3: 3.07초다. 체인이 `screen>`을 기다리는 상한은 120초라 넘기지 않는다.

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

### 위험 6 — 키 하나가 두 노드로 오는 키보드는 글자가 두 번 나온다

시나리오 검토 S9. 일부 키보드는 인터페이스를 둘 낸다(부트 프로토콜용 하나와 NKRO용 하나). 보통은 한 키가 한쪽으로만
보고되지만, 둘 다로 보고하는 펌웨어가 있으면 결정 2가 둘 다 열어 글자가 두 번 나온다. 지금은 그런 장치가 근거로 없다.
실기에서 보이면 첫 단서는 `keyboard> open` 줄 둘이 같은 `name=`이라는 것이다. 처방 후보는 같은 물리 장치(`EVIOCGPHYS`의
앞부분)에서 온 키보드 노드를 하나만 여는 것이다.

### 위험 7 — 한 바퀴 안의 두 키보드는 시각 순서가 아니라 칸 순서로 읽힌다

시나리오 검토 S8. 고치려면 그 바퀴에 깨운 키보드를 다 읽고 이벤트를 커널 시각으로 섞어 `handleKey`에 먹여야 한다 —
`readKeys`가 fd 하나를 받는 지금 모양과 다르다. 사람의 손으로는 거의 안 생기는 일이라 지금은 안 한다. 실기에서 장치를 건너는
조합이 가끔 소문자로 나오면 이것이다.

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
  때의 바쁜 루프(확인 4)를 본다. 지금 게스트의 `/dev/input` 노드마다 결정 2의 판정이 무엇을 고르는지도. QMP
  `input-send-event`가 장치를 골라 보내는지(게이트 6).
- KH-M1 — `input.zig`(판정 · `releaseHeld` · `BTN_MISC` 거르기 · 단위 검사), `main.zig`(키보드 칸 · 하나로 합친 여는 길 ·
  `fds` 자리 · 닫기 · 로그 셋), 두 체인의 진단 목록, `running-tars.md`.
- KH-M2 — 체인 `keyboard/check.sh`(결정 8), mutation, 루트 게이트(24체인), 문서 닫기(BT design 확인 7 · 비목표 1의 "아직 못
  친다"를 고친다, `carryover.md`의 BT 항목, completed · 소개 페이지 · decisions · HANDOFF).

## 실측 (M0, 2026-11-02)

하네스는 세션 scratchpad의 `kh/`(`probe.sh` · `run.sh`)였고 커밋하지 않았다. 모양은 KH-M0 plan 그대로다 — 설정 디스크의
`services.d/kh`가 노드를 지켜보고 노드마다 `cat /dev/input/eventN`을 띄워 받은 바이트를 `/config/kh/out/`에 쓰고, 호스트가
QEMU를 끝낸 뒤 `debugfs rdump`로 꺼내 `<qqHHi`로 풀었다. 커널 · init · terminal은 BT-M2 게이트의 산출물(`529d5db`, 그 뒤로 코드
변경 없음)이다. 부팅은 넷이다 — A(q35 `i8042=off`, 키보드 없음), A2(A에 k1을 화면에 묶음), B(PS/2가 있는 pc), C(q35 `i8042=off`,
부팅 때 usb-kbd).

### 실측 1 — `sendkey`는 마지막에 꽂은 키보드로 가고, 빼면 앞의 것으로 돌아간다(위험 1)

| 부팅 | 그때 있는 키보드 | `sendkey a`를 받은 노드 |
|---|---|---|
| A | k1 | k1 |
| A | k1 · k2 | k2 |
| A | k2를 뺀 뒤 k1 | k1 |
| B | PS/2 | PS/2(terminal이 `key> 1 byte(s)`) |
| B | PS/2 · k1 | k1(terminal의 `key>` 줄이 없다 — 키가 terminal에 안 닿았다) |
| B | k1을 뺀 뒤 PS/2 | PS/2(`key>` 줄이 다시 나온다) |

키 하나는 144바이트, `input_event` 여섯이다 — usb-kbd를 풀면 누름과 뗌이 각각 `MSC_SCAN`(type 4) · `EV_KEY`(type 1) ·
`SYN_REPORT`(type 0)다. 한 노드를 여럿이 함께 읽어도 각자 다 받는다 — B의 PS/2는 프로브의 `cat`이 144바이트를 받는 동안
terminal의 키보드 fd도 같은 키로 `key>` 줄을 냈다.

### 실측 2 — QMP로 장치를 골라 보내려면 키보드를 화면에 묶는다(게이트 6)

`input-send-event`의 `device`는 키보드가 아니라 화면 장치다. 겪은 순서:

1. `device: k1`로 보내자 QEMU가 abort로 죽었다 — `Unexpected error in object_property_find_err() … Property
   'qemu-fixed-text-console.device' not found`. 콘솔을 돌다 `device` 속성이 없는 텍스트 콘솔에서 넘어진다. 그 콘솔은 지정하지 않은
   parallel 포트의 기본값(`vc`)에서 온다. `-parallel none`이면 안 죽는다.
2. 그다음은 `Device k1 (head 0) is not bound to a QemuConsole`이다.
3. `usb-kbd`에는 `display` 속성은 있고 `head` 속성은 없다(`Property 'usb-kbd.head' not found`). 그래서 키보드 둘을 한 화면의
   head 둘에 묶는 길은 없다.
4. 된 모양: `-device virtio-gpu-pci,id=gpu`, `device_add usb-kbd,…,id=k1,display=gpu`, k2는 안 묶는다. QMP `device: gpu`는 k1로,
   `device` 없는 QMP와 HMP `sendkey`는 묶이지 않은 마지막 키보드(k2)로 간다. 묶인 k1만 있을 때 HMP `sendkey`는 어디에도 안 간다.

장치를 건너는 조합의 커널 시각(A2): k1 Shift 누름 → +63ms k2 `a` 누름 → +54ms `a` 뗌 → +55ms k1 Shift 뗌. 하네스가 보낸 순서
그대로이고, 간격이 한 poll 바퀴보다 훨씬 길어 위험 7에 안 걸린다. 결정 8은 k1 · k2의 역할을 바꿔(화면에 안 묶은 k1은
`sendkey`, 묶은 k2는 QMP) 그대로 쓴다.

### 실측 3 — 키보드 없는 부팅은 3.07초 늦고, terminal은 전원 버튼을 연다(확인 1 · 위험 2)

A의 로그: `no keyboard found under /sys/class/input in 3000ms, falling back to event0` · `keyboard device /dev/input/event0 (Power
Button)` · `terminal: opened /dev/input/event0`. 프로브(부팅 뒤 10초를 자고 시작한다)가 시작한 uptime이 A 17.83초, C(키보드
있음) 14.76초다 — 3.07초. 이 기계에 부팅 때 있는 노드는 `Power Button` 하나뿐이다.

### 실측 4 — 부팅 키보드를 빼면 terminal이 CPU 하나를 다 쓴다(확인 4)

C. terminal(pid 50)의 utime + stime이 빼기 전 5초 동안 18틱 그대로, `device_del k0` 뒤 1초마다 135 · 236 · 337 · 437 · 537 · 638
— 1초에 약 101틱이다(`CLK_TCK` 100). terminal은 그 뒤로 한 줄도 안 찍는다. 사람이 보면 "키보드를 뽑았더니 팬이 돈다"이고 로그에
단서가 없다. 결정 4가 닫는 자리다.

### 실측 5 — 노드와 uevent, 그리고 결정 2의 판정

`device_add usb-kbd`는 노드 하나(`QEMU QEMU USB Keyboard`)를 만들고, 프로브가 그 노드를 본 것은 540 · 610 · 630 · 1000 ·
1320ms 뒤다(25 · 50ms 간격으로 보았으므로 그만큼 늦게 셌다). 노드의 `uevent`는 `MAJOR=13 MINOR=65 DEVNAME=input/event1`이다.
terminal의 포인터 층이 그 uevent를 받아 노드를 이미 열어 본다(`pointer> skip /dev/input/event1 kind=none name=QEMU QEMU USB
Keyboard`) — 결정 1이 기대는 길이 지금 살아 있다. `device_del`은 110 ~ 240ms 뒤에 노드를 지운다.

본 노드 넷과 결정 2의 기준(`EV_KEY` + `KEY_ESC`~`KEY_D`, 즉 `key`의 마지막 워드의 비트 1~32).

| 노드 | `ev` | `key`의 마지막 워드 | 판정 |
|---|---|---|---|
| Power Button(`LNXPWRBN`) | 3 | 0 | 아니다 |
| AT Translated Set 2 keyboard | 120013 | fffffffffffffffe | 키보드 |
| ImExPS/2 Generic Explorer Mouse(B, `i8042.noaux` 없음) | 7 | 0 | 아니다 |
| QEMU QEMU USB Keyboard | 120013 | fffffffffffffffe | 키보드 |

키보드인 둘만 고른다. 결정 2는 그대로다.

## 실측 (M1, 2026-11-02)

### 실측 6 — 루트 게이트 22/23, 빨강 하나는 btvirt의 crash다

23체인 중 BT-M2만 빨강이다. 판정 문구는 `after the restart bluetoothd does not know the pairing … controllers 0`이고, 그 앞에
`traps: btvirt[107] general protection fault`가 있다 — 페어링 직후 가상 컨트롤러를 만드는 Debian `btvirt`가 죽어 컨트롤러 둘이
사라졌다. 이 부팅에서 KH가 바꾼 것은 `keyboard> open … AT Translated Set 2 keyboard` 한 줄이다. 같은 산출물로 BT 체인만 두 번
다시 돌리니 crash 없이 초록이다(`controllers 2 paired yes`). 새 간헐로 `carryover.md`의 BT 절에 적었고 판정은 안 넓혔다.
`terminal: opened`가 빠진 것 말고 바뀐 로그로 빨개진 체인은 없다.

### 실측 7 — 부팅 키보드를 빼도 CPU가 그대로다(실측 4가 닫혔다)

KH-M0의 부팅 C를 새 terminal로 다시. 빼기 전 5초 39틱, `keyboard> close /dev/input/event1` 뒤 40틱에서 움직이지 않는다. M0은 1초에
약 101틱이었다.

### 실측 8 — 키보드 없이 부팅하고, 꽂은 키보드가 친다

KH-M0의 부팅 A를 새 terminal로 다시. `keyboard> none` → `device_add` 뒤 `keyboard> open /dev/input/event1 name=QEMU QEMU USB
Keyboard` → 그 키가 `key> 1 byte(s)`. 둘째를 꽂으면 둘째 `open`, 빼면 `keyboard> close /dev/input/event2`이고 남은 키보드의 키가
계속 간다. `terminal: opened`와 `FATAL`은 없다.

## 실측 (M2, 2026-11-02)

### 실측 9 — 커널이 해제 때 뗌을 흉내 내 보내서, 판정 7은 `releaseHeld`를 못 가린다

체인은 첫 판에 일곱 판정이 초록이었다(판정 6의 틱 차는 0). mutation 셋 가운데 M-a(키보드 칸에 안 넣는다)는 판정 2에서, M-b
(`POLLERR` · `POLLHUP`을 안 본다)는 판정 6의 `keyboard> close`에서 잡혔다. M-c(`closeKeyboard`가 `releaseHeld`를 안 부른다)는 일곱이
다 초록이었다.

원인은 커널이다(6.18.60 소스). `input_unregister_device` → `input_disconnect_device`가 "stuck 키를 막으려고" 눌린 키마다
`EV_KEY … 0`과 `SYN_REPORT`를 흉내 내 보낸다(`drivers/input/input.c` `input_dev_release_keys`). 그다음 `evdev_disconnect`가
`cdev_device_del`(sysfs · uevent) 뒤에야 `evdev_mark_dead`를 한다. 그 사이에 깨어난 terminal이 뗌을 읽어 Shift가 풀렸다. 죽은
표시 뒤에는 read가 버퍼가 있어도 `-ENODEV`이고(`evdev.c` `evdev_read`), poll은 `EPOLLHUP | EPOLLERR`(+버퍼가 있으면 `EPOLLIN`)다
— `readKeyboards`는 그때 읽지 않고 닫으므로 뗌을 잃고, 푸는 것은 `releaseHeld`뿐이다.

그래서 판정 7b를 더했다. 설정 디스크의 `kh-stop`이 terminal을 SIGSTOP으로 멈춘 동안 Shift를 쥔 k2를 빼고(`USB disconnect`를
기다린다) SIGCONT한다. 그 판에서 M-c는 7b에서 잡혔다. 화면은 `ECHOㅀ/ㅀ$ㄴㅐㅇㅐㄷㄴ`이었다 — Shift가 남아 대문자가 되고, Space가
Shift+Space(한/영)가 되어 나머지가 한글로 갔다. 같은 판의 판정 7은 초록이었다(`qxq0`). 결정 4의 "뗌이 영영 안 온다"를 고쳤다.

### 실측 10 — 체인 34초

`keyboard/check.sh`는 루트 게이트 안에서 34초다(부팅 하나, init의 3초 포함). 가장 짧은 축이다.

### 실측 11 — 루트 게이트 24/24

11분 18초(prebuild 361 + lanes 316초), verify 8407줄 전부 통과. M1에서 빨갰던 BT-M2(btvirt crash)도 이번 판은 초록이다.
