# TARS Keyboard Kind — Design

접두사: KK

Status: KK-M0 끝남(2026-11-04) — 다음 KK-M1. 결정 8 · 위험 4 · 실측 1~3.

사용자가 정했다(2026-11-04). 방식은 `auto` 값 + vendor 판정이다(결정 1 · 2). 기본값은 `auto`로 바꾼다(결정 4 — 초안의 추천은
`apple` 유지였다). 게이트는 `input` 체인의 부팅으로 보고(결정 7), Cmd · Option을 보내는 체인은 디스크에 `keyboard=apple`을
적는다(결정 8의 A안).

관련 문서: `2026-11-04-tars-device-modifiers-design.md`(DM. 결정 5가 칸 번호를 `Context.device`로 실었고, 비목표 1이 이 설계로
넘긴 자리) · `2026-11-02-tars-keyboard-hotplug-design.md`(KH. 비목표 1, 시나리오 S13) · `docs/guides/carryover.md`의 KH 절 넷째 항목 ·
IP design(`keyboard=` 결정 9, `swap_alt_meta`가 생긴 자리) · PD design 결정 10(`tp-replay` — 게이트 전용 uinput 도구의 선례).

## 한 줄 요약

`keyboard=auto`를 더하고 기본값으로 삼는다. 그 값이면 terminal이 키보드를 열 때 `EVIOCGID`로 vendor를 읽어 Apple이면 `apple`,
아니면 `pc`로 그 칸의 Alt · Meta 맞바꿈을 정한다. `apple` · `pc`는 지금처럼 모든 키보드에 같은 값을 강제한다.

## 왜 지금인가

KH가 키보드를 여럿 열게 했지만 `keyboard=`는 기계 하나에 하나다(KH 시나리오 S13). MacBook이 아닌 일반 노트북에 Apple 키보드를
꽂으면, 내장 키보드(PC 배열)와 Apple 키보드 중 한쪽의 Option · Cmd가 어긋난다. TARS의 대상이 "일반 x86_64 노트북"(RM)이고
기본값이 `apple`인 이유가 "이 기계를 쓰는 사람이 Apple 키보드를 먼저 꽂는다"(`config.zig`)이므로, 이 둘이 함께 있는 것이 이
기계의 보통 모습이다. 사용자가 DM 다음으로 이 항목을 골랐다(2026-11-04). DM이 칸 번호를 `Context`에 실어 자리가 이미 있다.

## 착수 전에 아는 것 (2026-11-04에 코드에서 확인, `58a2640`)

### 확인 1 — `keyboard=`가 하는 일은 `swap_alt_meta` 하나다

`shared/screen_args.zig`의 `Keyboard`(`apple` · `pc`)가 init의 설정과 terminal argv의 계약이다. terminal은 `main.zig`에서
`self.swap_alt_meta = keyboard == .pc`로 bool 하나를 만들고, `readKeyboard`가 키를 읽을 때마다 `input.Context.swap_alt_meta`에
넣는다. `handleKey`의 0번 단계가 그 값이 참이면 `swapAltMeta`로 Alt와 Meta의 키 코드를 맞바꾼다(왼쪽 · 오른쪽 둘씩). 수정키
기록 · 받아쓰기 트리거(`keyboard=pc`면 오른쪽 Alt, `input_test` 검사 78) · Option/Cmd 조합이 전부 맞바꾼 뒤의 코드를 본다.

즉 칸마다 bool 하나를 고르면 `input.zig`의 `handleKey`는 안 바뀐다. `Context`는 이미 `readKeys` 호출 하나에 한 번 조립되고, 그
호출은 키보드 하나의 fd만 읽는다(DM 확인 2).

Ctrl+Alt+Del은 이 길이 아니다. 커널 VT 키보드 핸들러가 받아 PID 1에 SIGINT를 보낸다(`power` 체인). 맞바꿈과 상관없다.

### 확인 2 — 장치의 vendor는 `EVIOCGID` 한 번으로 안다

`EVIOCGID`는 `struct input_id { bustype, vendor, product, version }`를 준다. terminal은 키보드를 열 때 이미 `EVIOCGNAME`을 부르고
(`keyboard> open … name=`), 같은 자리에서 한 번 더 부르면 된다.

| 장치 | bus | vendor |
|---|---|---|
| Apple USB 키보드 · Magic Keyboard(유선) · 2015년 전 MacBook 내장 | USB(0x03) | 0x05ac |
| Magic Keyboard(BT, 2015년 뒤) | Bluetooth(0x05) | 0x004c(BT SIG의 Apple 회사 번호) |
| 옛 Apple Wireless Keyboard(BT) | Bluetooth(0x05) | 0x05ac |
| 일반 노트북 내장(i8042, `AT Translated Set 2 keyboard`) | i8042(0x11) | 0x0001 |
| QEMU `usb-kbd` | USB(0x03) | 0x0627 |

커널에 `HID_APPLE`이 꺼져 있다(`audio` · `wifi` 체인이 붙박는다 — fn 키를 커널이 바꿔 `keyboard=apple`과 부딪치므로). 그래서
Apple 키보드도 `hid-generic`이 받고, vendor는 HID 장치의 것이 그대로 evdev에 온다.

### 확인 3 — 게이트에서 Apple 키보드를 흉내 낼 길은 uinput이고, 선례가 있다

QEMU의 `usb-kbd`에는 vendor를 바꾸는 속성이 없다(`-device usb-kbd,help` — `attached` · `display` · `msos-desc` · `pcap` · `port`
· `serial` · `usb_version`). `virtio-keyboard-pci`도 같다. 커널에는 `CONFIG_INPUT_UINPUT=y`가 있다.

`pointer/replay/`의 `tp-replay`(PD-M3)가 같은 일을 터치패드로 한다. libc 없이 Zig로 빌드하고, 체인이 설정 디스크에 싣고, 게스트
셸에서 친다. `/dev/uinput`의 요청 번호는 손으로 만든 상수다. 이 설계의 도구는 그것을 키보드로 옮긴 것이다.

### 확인 4 — 화면이 Option과 Cmd를 가르는 판정이 이미 있다

`input/check.sh`의 판정 8 ~ 11. bash에서 `alt-left`는 Option+←(단어 이동), `meta_l-left`는 Cmd+←(줄 처음)이고, 2차 부팅
(`keyboard=pc`)에서 둘이 뒤집힌다. 결과는 친 줄이 무엇으로 실행됐는지로 본다.

### 확인 5 — 게이트의 여러 체인이 기본값 `apple`에 기대어 Cmd · Option을 친다

QEMU 키보드(vendor 0x0627)는 `auto`에서 `pc`다. 지금 Cmd · Option을 보내는 체인과 그 부팅의 설정 디스크:

| 체인 | Cmd · Option을 보내는 곳(`rg` 줄 수) | 설정 디스크 |
|---|---|---|
| `pane` | 30 | 부팅 A 없음, 부팅 B 있음 |
| `input` | 20 | 1차 없음, 2차 `keyboard=pc` |
| `copy` | 15 | 없음 |
| `dictation` | 11(오른쪽 Cmd) | 부팅 A · B 둘 다 있음 |
| `pointer` | 7 | 부팅 A 없음, 부팅 B 있음 |
| `hangul` | 4 | 있음(`make_disk.sh`) |

게이트가 아닌 `site/capture.sh`(소개 페이지의 화면 찍기)도 Cmd를 친다. `config` 체인과 init의 단위 검사(`reload_test` ·
`config_edit_test`)는 기본값의 글자(`keyboard=apple`, `keyboard: apple -> pc`)를 본다.

## 결정

### 결정 1 — 새 값 `auto`를 더하고, `apple` · `pc`의 뜻은 그대로 둔다

`Keyboard` enum에 `auto`를 더한다. `apple` · `pc`는 지금처럼 모든 키보드에 같은 값을 강제한다. `keyboard=`를 적어 둔 기계는 한
줄도 안 바뀐다. `auto`일 때만 칸마다 고른다.

대안은 둘이었다.

- `apple` · `pc`를 "알아보지 못한 키보드의 값"으로 바꾸고 Apple vendor는 늘 `apple`로 보는 것. 값이 하나 덜 생기지만, `pc`라고 적은
  사람의 Apple 키보드가 말없이 바뀐다. 적힌 값이 뜻을 잃는다.
- 장치 이름이나 vendor를 설정에 적는 키(`keyboard.<이름>=pc` 같은 것). 확인 2의 표로 가려지지 않는 키보드(위험 1)를 고칠 유일한
  길이지만, 이름에 빈칸이 있고 설정 문법이 는다. 비목표 1로 둔다.

### 결정 2 — Apple의 판정은 vendor 둘이다

`0x05ac`(bus 상관없이)와 `0x004c`(bus가 Bluetooth일 때만)면 `apple`, 나머지는 `pc`다. `0x004c`에 bus를 묻는 이유는 그 번호가 BT
SIG의 회사 번호이지 USB vendor가 아니기 때문이다. 이 판정은 순수 함수(`input.kindOf(setting, bus, vendor)` 같은 모양)로 두고 단위
검사가 표로 본다.

이름은 안 본다. `name=`에 `Apple`이 든 서드파티 키보드가 있고, 이름은 BT에서 사용자가 바꿀 수도 있다.

### 결정 3 — 칸마다 고른 값은 `KeyboardDev`에 들고, `Context`에 그대로 싣는다

`takeKeyboard`가 `EVIOCGID`를 읽어 결정 2로 고른 bool을 `KeyboardDev.swap_alt_meta`에 넣는다. `readKeyboard`는 `self.swap_alt_meta`
대신 그 칸의 값을 `Context`에 싣는다. `App`은 bool 대신 설정값(`apple` · `pc` · `auto`)을 들고 있다가 칸을 열 때마다 결정 2의
함수에 넘긴다.

값은 칸이 열려 있는 동안 상수다. 칸이 비면 함께 사라지고, 다음 키보드가 그 칸을 열 때 새로 고른다. 그래서 DM의 칸별 수정키와
어긋날 자리가 없다. A(pc)의 물리 Alt는 맞바꿈 뒤 Meta로 A의 칸에 기록되고, B(apple)의 글자와 만나면 OR로 Cmd 조합이 된다.
장치를 건너는 조합의 뜻은 "각 키보드에서 그 키가 무엇인가"로 정해지고, 사람이 기대하는 것도 그것이다.

`EVIOCGID`가 실패하면 그 칸은 `pc`로 본다(vendor를 모르는 키보드와 같다). 실패는 로그에 찍는다.

`Context.swap_alt_meta`의 주석("부팅 내내 상수")만 "칸이 열려 있는 동안 상수"로 고친다.

### 결정 4 — 기본값은 `auto`다

사용자가 정했다(2026-11-04). 일반 노트북의 내장 키보드는 PC 배열이고, 거기에 Apple 키보드를 꽂는 것이 이 기계의 보통
모습이다(왜 지금인가). `auto`는 두 경우를 다 맞춘다. MacBook 내장(2015년 전)과 Apple 키보드만 쓰는 사람에게는 지금의 `apple`과
같다.

`config.zig`의 `Config.keyboard` 기본값과 그 주석(기본값이 `apple`인 이유)을 고친다. 설정 파일이 없는 기계, `keyboard=` 줄이
없는 기계가 이 값을 받는다.

대가는 게이트다(확인 5). QEMU 키보드가 `pc`가 되므로 Cmd · Option을 치는 체인이 결정 8로 `apple`을 적는다.

### 결정 5 — 로그: `keyboard> open`에 `kind=`와 id를 더한다

```
terminal: keyboard> open /dev/input/event3 kind=pc bus=0003 vendor=0627 name=QEMU QEMU USB Keyboard
```

`kind=`는 그 칸이 실제로 쓰는 값이다(`auto`가 아니라 고른 결과). `apple` · `pc`로 강제한 설정에서도 찍는다 — 줄의 모양이 설정에
따라 달라지지 않게. bus · vendor는 실기에서 `auto`가 틀리게 골랐을 때의 첫 단서다(위험 1). `name=`은 빈칸을 품으므로 끝에 둔다.

이 줄을 글자로 보는 판정은 `keyboard` · `device` · `terminal` · `machine` 체인에 있다. `name=` 바로 앞까지 글자로 보는 자리(`open
${K1_PATH} name=…` · `open /dev/input/event[0-9]* name=`)는 M1이 함께 고친다.

시작 줄 `terminal: keyboard={s} (swap_alt_meta={})`는 `auto`일 때 `terminal: keyboard=auto (swap_alt_meta=per keyboard)`가
된다. `apple` · `pc`의 줄은 글자 그대로다.

### 결정 6 — 설정 쪽은 이름 하나와 기본값이다

init의 파싱은 enum 화이트리스트라 `auto`가 저절로 통과한다. 값의 목록이 적힌 자리는 설정 파일 견본의 주석(`config.zig`의
`# keyboard: apple | pc`) 하나뿐이고, 그것을 고친다. 기본값의 글자가 바뀌므로 그 글자를 보는 단위 검사(`reload_test` ·
`config_edit_test` · `config_test`)와 `config` 체인(`TC_LIST_WANT`, `keyboard: apple -> pc`, `keeps keyboard=apple`)이 `auto`로
따라간다. `tars-config reload terminal`로 바뀌는 것은 지금과 같다(terminal이 다시 뜨며 키보드를 다시 연다).

### 결정 7 — `input` 체인을 부팅 셋으로 다시 짠다

체인 수는 27 그대로다. `input` 체인이 `keyboard=`의 주인이다.

- 1차 — `keyboard=` 줄이 없는 디스크(기본값 `auto`)에 Apple 대역 도구(이름은 M0이 정한다, 예: `kk-apple`)를 싣는다. 지금의 1차는
  디스크 없이 떠서 "mount 실패 → 기본값"의 길을 덤으로 밟았는데, 그 길은 디스크 없는 다른 체인들(`terminal` 등)이 그대로 밟는다.
  Ctrl+C · TERM · 방향키 판정은 여기 그대로 남는다.
- 2차 — `keyboard=pc`(지금 그대로).
- 3차 — `keyboard=apple`. 지금 1차의 Option/Cmd 판정(8 · 9)과 `keyboard=apple (swap_alt_meta=false)` 줄이 여기로 온다.

새 판정(번호는 M0 plan이 매긴다):

- (가) 기본값의 QEMU 키보드는 `pc`다. 1차에서 `terminal: keyboard=auto` 줄, `keyboard> open … kind=pc … vendor=0627`, 그리고
  `alt-left`가 줄 처음으로 간다(지금 판정 10과 같은 모양). M0 정정: `input` 체인의 키보드는 PS/2라 찍힐 id는
  `bus=0011 vendor=0001`이다(실측 1).
- (나) 기본값의 Apple 키보드는 `apple`이다. 1차에서 셸로 도구를 띄우면 vendor 0x05ac인 키보드가 생기고(`keyboard> open … kind=apple
  … vendor=05ac`), 도구가 스스로 `echo aa bb` · Alt+← · `X` · Enter를 친다. 줄이 `echo aa Xbb`로 실행된다(지금 판정 8과 같은 모양).
  같은 부팅의 (가)와 뜻이 반대이므로, 칸마다 다르게 골랐다는 증거다.
- (다) 섞인 조합 — QEMU 키보드(pc)의 물리 Alt(= Cmd)를 쥔 채 Apple 대역으로 `←`를 친다. 줄 처음으로 가야 한다. 도구가 바깥 키를
  기다리는 모양이 까다로우면(위험 2) 뺀다. (가) · (나)로 결정 3이 선다. → M0에서 뺐다(실측 2).

지금 코드에서 1차는 init이 `keyboard=` 줄 없이 `apple`을 쓰므로 (가)가 빨갛고, (나)는 우연히 초록이다. M0의 빨강은 (가)이고,
(나)는 M1 뒤 mutation이 붙박는다.

mutation 셋(M1에서 돌린다). (a) 결정 2의 판정이 vendor를 무시하고 늘 `pc` → (나)가 잡아야 한다. (b) 칸의 값 대신 처음 연 칸의 값을
모든 칸에 싣는다 → (나)가 잡아야 한다(QEMU가 먼저 열린다). (c) 기본값을 `apple`로 되돌린다 → (가)가 잡아야 한다.

단위 검사: 결정 2의 표(확인 2의 다섯 행 + `0x004c`의 USB · 강제 `apple` · `pc`가 vendor를 무시함), 그리고 `input_test`에서 칸 0은
맞바꾸고 칸 1은 안 맞바꾸는 두 `Context`가 같은 `State`를 쓸 때 Alt · Meta가 각 칸의 뜻으로 기록되는지.

### 결정 8 — Cmd · Option을 치는 체인은 디스크에 `keyboard=apple`을 적는다

사용자가 정했다(2026-11-04, A안). 확인 5의 체인은 키보드 종류가 아니라 패널 · 복사 · 받아쓰기 · 포인터 · 한글을 보는 체인이다.
그 체인의 키 입력(`meta_l-d` 등)과 "Cmd"라는 주석이 그대로 읽히도록, 설정에 `keyboard=apple`을 적어 지금 뜻을 지킨다. 키보드
종류는 `input` 체인 하나가 책임진다.

- 디스크가 있는 부팅(`pane` B · `dictation` A · B · `pointer` B · `hangul`)은 `tars.conf`에 한 줄을 더한다.
- 디스크가 없는 부팅 셋(`copy` · `pane` A · `pointer` A)은 `keyboard=apple` 한 줄짜리 작은 디스크를 붙인다. 붙은 디스크가 그
  부팅의 다른 판정을 흔드는지(`/config`가 생긴다, virtio 장치가 하나 는다)는 M0이 본다(위험 4).
- `site/capture.sh`도 같다.

대안(B안)은 체인들이 PC 키보드의 키를 누르게 바꾸는 것이었다(`meta_l` ↔ `alt`, `meta_r` → `alt_r`, 약 80곳). 새 기본값의 길을 여러
체인이 밟지만, 주석의 "Cmd"와 누르는 물리 키가 어긋나 읽기 어렵다.

이 줄들은 지금 코드에서 아무것도 안 바꾼다(기본값이 이미 `apple`이다). 그래서 M0에 먼저 넣고, 그 체인들이 그대로 초록인지 본다.

## 시나리오

| | 상황 | 지금 | KK 뒤(기본값 `auto`) |
|---|---|---|---|
| S1 | 일반 노트북 내장 키보드만 | Option/Cmd가 뒤집혀 있다. `pc`를 적어야 맞다 | `pc`로 맞다 |
| S2 | 일반 노트북 + Apple USB · BT 키보드 | 한쪽이 어긋난다 | 각자 맞다 |
| S3 | Intel MacBook(2015년 전) 내장 | `apple` | `apple`(USB 0x05ac) |
| S4 | Mac 배열인 서드파티 키보드(Keychron Mac 모드 등) | `apple`로 맞다 | vendor가 Apple이 아니면 `pc`로 틀린다(위험 1). `keyboard=apple`을 적으면 지금과 같다 |
| S5 | `apple` · `pc`를 적은 기계 | 그대로 | 그대로(결정 1) |
| S6 | 키보드를 뽑았다 다른 것을 같은 칸에 꽂는다 | — | 새 키보드의 vendor로 다시 고른다(결정 3) |

## 위험

### 위험 1 — vendor가 배열을 말하지 않는 키보드

S4. Mac 배열을 흉내 내는 서드파티 키보드는 자기 vendor를 쓰는 경우가 많고, 반대로 Mac 모드에서 Apple vendor를 흉내 내는 것도
있다고 알려져 있다(확인 못 했다). 기본값이 `auto`라 이런 키보드 하나만 쓰는 사람은 지금(`apple`)보다 나빠진다 — `keyboard=apple`을
적어야 한다. 그런 키보드를 PC 키보드와 함께 쓰면 고칠 길이 없다(비목표 1). 판단의 근거는 `open` 줄의 bus · vendor다.

### 위험 2 — 도구의 키보드가 terminal에게 키보드로 보이고, 친 키가 닿는지

terminal의 판정(KH 결정 2)은 `EV_KEY`와 `KEY_ESC` ~ `KEY_D`다. 도구가 그 비트를 다 켜야 열린다. 그리고 도구가 장치를 만든 직후
친 키는 terminal이 아직 안 연 노드로 갈 수 있다 — 도구가 열림을 기다려야 한다(예: 만든 뒤 1초를 쉰다). M0이 지금 코드에서
`keyboard> open … name=<도구 이름>`이 찍히고 친 글자가 화면에 오는지 먼저 확인한다.

### 위험 3 — `EVIOCGID`의 C 매크로

`EVIOCGNAME`은 길이를 받는 함수 모양 매크로라 `pointer.eviocgname`으로 손으로 풀었다. `EVIOCGID`는 길이가 고정된 `_IOR`이라
cImport가 바로 풀 수도 있다. 안 되면 같은 방식으로 상수를 손으로 만들고 단위 검사가 값을 붙박는다(`pointer_test`의
`EVIOCGNAME(64)` 검사와 같은 모양).

### 위험 4 — 디스크를 새로 문 부팅이 다른 판정을 흔든다

결정 8의 디스크 없는 부팅 셋. `/config`가 마운트되면 init이 기본값 대신 파일을 읽고(`tars-init: config …` 줄이 바뀐다),
`services.d` 같은 디렉터리를 찾는다. virtio 블록 장치가 하나 늘어 PCI 주소나 `/dev/vda` 이름에 기대는 판정이 있으면 흔들린다.
M0이 세 부팅을 돌려 초록을 확인한다. 흔들리는 판정이 있으면 그 부팅만 B안(키 이름 바꾸기)으로 돌린다.

## 비목표

1. 장치 이름 · vendor를 설정에 적어 고르기(위험 1의 키보드를 위한 길). 실기에서 그런 키보드가 생기면 그때 한다.
2. Apple 키보드의 fn 키 · 미디어 키(`HID_APPLE`). 지금처럼 끈 채다.
3. 키보드마다 다른 한글 · 영문 자판. 자판은 사람의 것이고 키보드의 것이 아니다(KH 결정 3의 사람 쪽 상태).

## Milestone

한 milestone이 끝나면 다음 plan을 그때 쓴다.

- KK-M0 — 고치기 전 코드에서 하는 일. (1) Apple 대역 uinput 도구(`tp-replay`의 모양). (2) `input` 체인을 부팅 셋으로(결정 7) — 새
  판정 (가)가 기대한 이유(`keyboard=apple`이 기본값)로 빨갛고, 도구의 키보드가 열려 글자가 오는지(위험 2). (3) 결정 8의 `keyboard=apple`
  줄과 디스크 — 그 체인들이 그대로 초록인지(위험 4). terminal · init 코드는 0줄이다.
- KK-M1 — `screen_args`(`auto`), init(기본값 · 견본 주석 · 단위 검사의 글자), terminal(`EVIOCGID` · 결정 2의 함수 · 칸별 값 · 로그
  줄), 단위 검사, `config` 체인과 `open` 줄 판정의 글자, 체인 초록, mutation 셋, 루트 게이트, 문서 닫기(KH design 비목표 1 · DM
  비목표 1, `carryover.md` KH 넷째 항목, completed · 소개 페이지 · decisions · HANDOFF).

## 실측 (M0, 2026-11-04)

### 실측 1 — `input` 체인의 키보드는 PS/2다

`start_guest`에 `-machine`이 없어 기본 `pc` 기계의 i8042 AT 키보드(`AT Translated Set 2 keyboard`, bus 0x11 · vendor 0x0001)가
붙는다. 결정 7 (가)의 예시 줄(`vendor=0627`)은 `keyboard` 체인의 QEMU `usb-kbd` 것이었다. M1 뒤 `input` 체인에 찍힐 줄은 `kind=pc
bus=0011 vendor=0001`이고, 일반 노트북 내장 키보드와 같은 모양이라 판정의 뜻은 그대로다.

### 실측 2 — 판정 12(가)가 기대한 이유로 빨갛고, 13(나)는 도구로 선다

`input` 체인의 일회용 사본(판정 12와 1차 끝 로그 판정의 `report_failure`를 `echo "RED: …"`로 바꾼 것, 지웠다)을 `aab1d97`의
terminal · init로 한 판 돌렸다.

- 1차: `config storage /dev/vda (label tars-input-auto)` → `loaded /config/tars.conf` → `config shell=fish keyboard=apple …`. 디스크를
  물려도 판정 1 ~ 7은 초록이다.
- 판정 12: `RED` — 화면에 `kk: command not found`. 지금 코드는 PS/2 키보드를 apple로 읽어 Alt+←가 단어 이동이 됐다.
- 판정 13: 초록 — terminal이 `TARS KK Keyboard`를 열었고(uevent), 도구가 친 키가 bash에 닿아 `mm Xnn`, 도구가 끝나며 `close`.
  design 위험 2가 닫혔다. 지금 코드는 맞바꿈이 전역 거짓이라 어느 키보드든 apple로 읽으므로 이 초록은 우연이다 — M1의 mutation
  (a) · (b)가 값을 붙박는다.
- 1차 끝 로그 판정 둘(`keyboard=auto` · `swap_alt_meta=per keyboard`): `RED`, M1의 값이다.
- 2차(`tars-input-pc`) · 3차(`tars-input-apple`): 초록. 옮긴 판정 8 · 9가 IP-M2 때 글자 그대로 3차에서 선다.

판정 (다)(섞인 조합)는 넣지 않았다. HMP `sendkey`는 키를 쥔 채 둘 수 없고, 도구가 바깥 키를 기다리는 모양은 위험 2를 키운다. 칸을
건너는 조합은 DM이 Shift로 체인에서 이미 보고, M1의 `input_test`가 Alt · Meta로 본다.

결정 8의 디스크 없던 부팅 셋에 붙인 판정은 plan과 하나 다르다. 기본값이 아직 `apple`인 동안은 `config … keyboard=apple` 줄만으로는
디스크가 안 붙어도 초록이라, `tars-init: loaded /config/tars.conf` 줄을 함께 본다.

### 실측 3 — 루트 게이트

25/27, prebuild 332초 · lanes 587초, 잘린 로그 줄은 모든 체인에서 0이다.

- `IP-M2`(`input`): 판정 12에서 빨강 — 실측 2와 같은 이유(`… the PS/2 keyboard's alt-left still moved by a word`). M1 커밋까지
  기대값이다.
- 결정 8의 다섯 체인은 초록이다 — `CM-M2`(`copy`, 173초) · `CB-M0`(`pane`, 56초) · `PD-M4`(`pointer`, 122초) · `VD-M0`
  (`dictation`, 92초) · `HI-M3`(`hangul`, 78초). 새로 물린 디스크와 `loaded` · `keyboard=apple` 판정이 다 섰다. 위험 4는 나타나지
  않았다.
- `BT-M2`(`bluetooth`): 빨강. `traps: btvirt[105] general protection fault` → 재시작한 bluetoothd가 `controllers 0` —
  `carryover.md`의 btvirt 간헐과 같은 서명이다. 이 milestone은 그 체인을 안 건드렸고, 같은 산출물로 체인만 다시 돌린 판은 crash
  없이 초록이다. 두 번째 기록이라 carryover 항목에 적었다.

