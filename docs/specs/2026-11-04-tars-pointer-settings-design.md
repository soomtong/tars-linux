# TARS Pointer Settings — Design

접두사: PS

Status: 닫힘(2026-11-04) — M0 설정 넷의 길 · 칸마다 휠 부호(판정 가~마), M1 가속 곡선 `pointer.Ballistics`(판정 바). mutation 넷 잡힘.

사용자의 요청(2026-11-04)에서 시작한다.

> 마우스 휠의 설정과 터치패드의 이동은 반대 방향을 가진다. 마우스/터치패드를 구분하는 능력이 필요하다.
> 키보드처럼 하나의 머신에 여러 포인팅 장치가 연결될 수 있다.
> 포인터 가속을 위한 수치 세팅은 0~10 또는 0~100 정도 제한하자.

사용자가 정했다(2026-11-04). 키는 종류별로 넷이다(결정 1). 방향의 기본값은 지금 동작 그대로다(결정 2). 가속은 0~10의 정수이고
기본값은 0이다(결정 3). 기본 속도(빠르기 배율)는 이번에 안 연다(비목표 1). 넷 다 초안의 추천안이다.

관련 문서: `2026-10-05-tars-pointer-devices-design.md`(PD. 결정 2 분류, 결정 7 휠 방향, 결정 8 터치패드 번역, 결정 10 `tp-replay`,
비목표 6 가속 · 비목표 7 휠 방향 설정이 이 설계로 넘어온 자리) · `2026-11-04-tars-keyboard-kind-design.md`(KK. 칸마다 값을 고르는
선례 — `KeyboardDev.swap_alt_meta`) · SA design(`shared/screen_args.zig`, argv 칸을 더하는 규칙).

## 한 줄 요약

`tars.conf`에 `mouse_scroll` · `touchpad_scroll`(방향)과 `mouse_accel` · `touchpad_accel`(0~10)을 더한다. terminal이 포인터 장치를
열 때 그 장치의 종류(PD 결정 2의 `classify`)로 값을 골라 장치 칸에 들고, 휠 부호와 가속을 칸 안에서 적용한 뒤에 한 회차로
합친다. 마우스와 터치패드가 함께 붙어 있으면 각자 자기 종류의 값을 쓴다.

## 왜 지금인가

PD는 두 가지를 상수로 두고 "사용자가 고를 자리이고 그때 `tars.conf` 항목이 된다"고 남겼다(PD 결정 7 · 비목표 7). 가속도 비목표 6으로
미뤘다. 그 뒤 KH · DM · KK가 "장치마다 다른 값을 칸에 든다"는 모양을 키보드 쪽에 세웠고, 포인터 쪽은 장치 칸이 처음부터 있었다.
실기 없이 게이트로 끝까지 볼 수 있는 몇 안 되는 후보다(HANDOFF 2026-11-04).

## 착수 전에 아는 것 (2026-11-04에 코드에서 확인, `57a063a`)

### 확인 1 — 종류는 이미 장치 칸마다 갈린다

`terminal/src/main.zig`의 `takePointer`가 `pointer.classify(caps)`로 `mouse` · `touchpad` · `none`을 가르고, 장치 칸
`PointerDev.decoder`가 `union(pointer.Kind)`로 그 종류의 디코더를 든다. 칸은 `pointer.MAX_DEVICES`개다. 사용자가 말한 "구분하는
능력"은 PD-M3부터 있다. 이 설계가 더하는 것은 그 종류를 설정과 엮는 일이다.

TrackPoint와 모드 전환 전의 I2C-HID 터치패드는 `mouse`로 읽힌다(PD 결정 2의 표). 그 장치들은 `mouse_*` 값을 따른다(위험 1).

### 확인 2 — 휠 방향은 지금 두 장치가 이미 반대다

| 장치 | 지금 | 자리 |
|---|---|---|
| 마우스 | `REL_WHEEL` 양수(앞으로 밂)가 위로 — `scrollByRows(-3)` | `pointer.Mouse.feed` → PD 결정 7 |
| 터치패드 | 손가락을 아래로 밀면 양수 — 내용이 손가락을 따라간다(macOS 기본) | `touchpad.zig`의 `scroll` |

두 디코더의 `Frame.wheel`은 같은 부호 규약(양수 = 위의 글을 보이게 한다)으로 나온다. 그래서 장치마다 부호 하나를 곱하면
방향을 바꿀 수 있다. 디코더는 손대지 않는다.

### 확인 3 — 여러 장치의 값은 `drainPointer`에서 합쳐진다

`drainPointer(dev, slot, state, round)`가 장치 하나의 이벤트를 디코더에 먹이고, 나온 `Frame`을 `Pointer.apply`에 넣고,
`round.wheel`에 더한다. 그 뒤로는 어느 장치가 낸 값인지 모른다. 방향과 가속은 `dev.feed`가 `Frame`을 낸 바로 뒤, `apply` 전에
적용해야 한다.

### 확인 4 — 설정이 terminal에 닿는 길은 argv 칸이다

`tars.conf` → init `config.zig`의 `Config` → `shared/screen_args.zig`의 `Args` · `encode` → terminal의 `decode`. `ARGC`는 9다.
`tars-config reload terminal`이 `decode` → 필드 교체 → `encode`로 terminal을 다시 띄운다(`init/src/main.zig`의
`doReloadTerminal`). 지금 `tars.conf`의 키는 전부 이름(enum) 값이다. 숫자 값은 처음이다.

### 확인 5 — 게이트는 두 종류를 한 부팅에 띄운다

`pointer/check.sh`의 boot B가 PS/2 마우스(HMP `mouse_move`)와 `tp-replay`의 uinput 터치패드를 함께 연다. `tp-replay`의 `move`는
10단위씩 8ms 간격, `scroll DY`는 두 손가락을 15단위씩 민다. boot B는 설정 디스크를 문다(`pd/tp-replay`를 싣는 자리).

`pointer> open` 줄은 체인이 글자 그대로 본다 — `kind=mouse shown=0 name=…`(566 · 1579행 근처) 등. 줄의 모양을 바꾸면 그
matcher들도 함께 바뀐다(결정 7).

## 결정

### 결정 1 — 키는 종류별로 넷이다 (사용자 결정)

```
# mouse_scroll: normal | natural
mouse_scroll=normal
# touchpad_scroll: natural | normal
touchpad_scroll=natural
# mouse_accel: 0..10 (0 = off)
mouse_accel=0
# touchpad_accel: 0..10 (0 = off)
touchpad_accel=0
```

| 후보 | 왜 아닌가 / 왜 이것인가 |
|---|---|
| 종류별 넷 | 고른다. 사용자가 말한 "두 장치는 방향이 반대다"를 그대로 적는다. 가속도 마우스(카운트)와 터치패드(패드 단위를 픽셀로 바꾼 값)의 손맛이 달라 따로 둔다 |
| 방향은 종류별, 가속은 하나 | 키가 셋이라 짧다. 두 장치의 속도 분포가 달라 같은 단계가 같은 손맛이 아니다 |
| 장치 이름별 설정 | 비목표 2. 마우스가 둘이면 둘 다 `mouse_*`를 따른다 |

`normal`은 "휠을 앞으로 밀거나 손가락을 위로 밀면 위의 글이 보인다", `natural`은 "내용이 손가락 · 휠을 따라간다"(macOS)이다.
이름은 macOS의 "자연스러운 스크롤"에서 왔다.

### 결정 2 — 방향의 기본값은 지금 그대로이고, 장치 칸이 부호 하나를 든다 (기본값은 사용자 결정)

기본값은 `mouse_scroll=normal` · `touchpad_scroll=natural`이다. 지금 동작과 같으므로 PD 검사 11 · 24가 그대로다.

장치를 열 때 `takePointer`가 종류와 설정으로 `wheel_sign`을 정해 `PointerDev`에 든다.

| 종류 | 설정 | `wheel_sign` |
|---|---|---|
| mouse | normal | +1 |
| mouse | natural | −1 |
| touchpad | natural | +1 |
| touchpad | normal | −1 |

`+1`이 지금 동작이다. 표는 순수 함수(`pointer.wheelSign(kind, scroll)`)이고 `pointer_test`가 넷을 본다. KK의 `swap_alt_meta`처럼
칸이 비면 함께 사라지고, 다음 장치가 그 칸을 열 때 새로 고른다.

끄는 중의 휠(PD 결정 7)과 자식에게 가는 휠 보고 · 화살표 키(PD 결정 12)는 부호가 적용된 뒤의 값을 받는다. `natural` 마우스로 vim
`mouse=a`에 휠을 굴리면 vim도 반대로 받는다. 손이 보는 화면 기준으로 같은 방향이 되게 하는 것이 설정의 뜻이라 이것이 맞다.

### 결정 3 — 가속은 0~10의 정수이고, 기본값은 0이다 (사용자 결정)

0은 가속 없음이고 지금 동작과 비트 단위로 같다. 그래서 기존 체인의 이동 판정(PD `at x= y=`)이 그대로다.

곡선은 속도에 따른 배율 하나다.

```
v    = |(dx, dy)| / dt            # 이 장치의 직전 이동 Frame과의 간격, 픽셀/ms
t    = clamp((v − V_LOW) / (V_HIGH − V_LOW), 0, 1)
gain = 1 + (level / 10) × (GAIN_MAX − 1) × t
```

| 상수 | 출발값 | 뜻 |
|---|---|---|
| `V_LOW` | 0.3 px/ms | 이보다 느리면 배율 1. 글자 칸을 고르는 손의 속도는 안 건드린다 |
| `V_HIGH` | 3.0 px/ms | 이보다 빠르면 배율 상한 |
| `GAIN_MAX` | 4 | level 10의 상한. level 5면 2.5 |
| `IDLE_US` | 100ms | 직전 이동과 이보다 멀면 `dt`를 모르는 것으로 하고 배율 1 |

출발값 넷은 재지 않은 제안이다(PD 결정 8과 같은 처지). 실기 없이 정할 수 없는 값이라 plan은 상수로 두고, 실기에서 사람이 손으로
본 뒤 고친다(위험 2). 셈은 정수 고정소수점으로 하고, 나머지를 다음 Frame에 넘긴다(`touchpad.zig`의 `scale`과 같은 이유 — 느린
이동이 반올림으로 사라지지 않게).

0~100이 아니라 0~10인 것은 실기 근거 없이 101단계를 구분할 수 없어서다(사용자 결정).

### 결정 4 — 가속은 칸 안에서, 이동에만 적용한다

`PointerDev`에 `accel: pointer.Accel`을 둔다. `Accel`은 순수 상태 기계이고 입력은 `Frame`의 `dx` · `dy`와 그 `SYN_REPORT`의 시각,
출력은 배율을 곱한 `dx` · `dy`다. 시각은 `eventUs(ev)` — 장치를 열 때 `CLOCK_MONOTONIC`을 고른 값이다(MC design 결정 2).

| 적용하나 | 무엇 | 왜 |
|---|---|---|
| 한다 | 마우스 `dx` · `dy`, 터치패드 한 손가락 이동(배율을 거친 픽셀) | 가속의 대상 |
| 안 한다 | 휠 · 두 손가락 스크롤 | 휠 한 눈금 = 세 줄(PD 결정 7)이 깨진다. 스크롤 가속은 비목표 3 |
| 안 한다 | 탭 · 버튼 Frame(`dx = dy = 0`) | 움직임이 없다 |

`Accel`은 장치 칸마다 하나다. 두 장치를 함께 움직여도 서로의 속도가 섞이지 않는다.

### 결정 5 — argv 칸 넷을 더한다

`screen_args.Slot`에 `mouse_scroll = 9` · `touchpad_scroll = 10` · `mouse_accel = 11` · `touchpad_accel = 12`를 더하고 `ARGC`를
13으로 올린다. `Args`에 같은 이름의 필드 넷을 더한다 — 기본값 없이(SA 결정 7: init이 빠뜨리면 컴파일이 막힌다).

| 칸 | 타입 | 글자 |
|---|---|---|
| `mouse_scroll` · `touchpad_scroll` | `WheelDirection = enum { normal, natural }` | `@tagName` |
| `mouse_accel` · `touchpad_accel` | `Accel = struct { level: u4 }`, 0~10 | `"0"`~`"10"` — comptime 표 열하나에서 고른다(버퍼가 필요 없다) |

이름 `Scroll`은 `pointer.zig`의 끄는 중 휠 구조체와 겹쳐 `WheelDirection`이다. `Accel`이 맨 `u4`가 아니라 구조체인 것은 init의
`config_edit.fieldText` · `hintFor` · `reload.same` · `reload.text`가 `Ntp` · `Timezone`처럼 타입으로 갈래를 고르기 때문이다(PS-M0 plan
확정 2).

`decode`의 기본값은 결정 2 · 3의 값이고, 숫자 칸의 글자가 0~10 밖이면 기본값이다. 콘솔 셸과 서비스 셋의 argv는 null이 넷 늘
뿐이다(SA의 규칙).

### 결정 6 — `tars.conf`의 첫 숫자 키는 이름 키와 같은 실패 규칙을 따른다

`config.zig`가 `mouse_accel=` · `touchpad_accel=`를 10진 정수로 읽는다. 숫자가 아니거나 0~10 밖이면 `unknown mouse_accel '…',
falling back to 0`처럼 한 줄을 찍고 기본값으로 간다 — 잘라 쓰지 않는다(`11`을 10으로 올리지 않는다). `firewall` · `esc_latin` ·
`clipboard`가 모르는 이름에 하는 일과 같은 모양이다. 설정 파일은 사람이 손으로 고치는 물건이라 깨진 입력이 예외가 아니라 규칙이다
(CP의 판단).

함께 고칠 것: init의 기본 `tars.conf` 견본(네 줄과 주석), 부팅 `tars-init: config …` 줄과 `reload terminal` 줄에 네 값.
`tars-config set`의 키 목록(`config_edit.KEYS`)은 `Config`의 필드 이름에서 지어지므로 따로 안 고친다 — `config_edit_test`가 모든
필드를 `parse`에 넣어 "모르는 키"가 없는지 보는 검사가 갈래를 빠뜨리면 잡는다. `LINE_MAX` 주석의 "가장 긴 키 `hangul_layout`"은
`touchpad_scroll`(열다섯 글자)로 바뀐다. 버퍼 256은 그대로 넉넉하다.

### 결정 7 — 로그: `pointer> open` 줄에 `scroll=` · `accel=`를 더한다

```
terminal: pointer> open /dev/input/event3 kind=mouse scroll=normal accel=0 shown=0 name=QEMU QEMU USB Mouse
terminal: pointer> open /dev/input/event5 kind=touchpad scroll=natural accel=0 slots=… shown=0 name=TARS Replay Touchpad
```

`kind=` 바로 뒤에 둔다. 칸이 실제로 고른 값이라, 실기에서 "왜 이 마우스가 반대로 도는가"의 첫 단서가 이 줄이다(KK 결정 5와 같은
이유). `pointer/check.sh`가 글자 그대로 보는 matcher(확인 5)는 M0이 함께 고친다. `name=`은 그대로 맨 끝이다.

### 결정 8 — 게이트: `pointer` 체인에 설정 디스크를 문 부팅 C를 더한다

boot C는 boot B처럼 PS/2 마우스와 `tp-replay` 터치패드를 함께 열고, 디스크의 `tars.conf`에 기본값의 반대를 적는다 —
`mouse_scroll=natural` · `touchpad_scroll=normal`(M0), 그리고 `touchpad_accel=10`(M1). `mouse_accel`은 기본 0으로 둔다 — 두 칸이 같은
값이면 "터치패드가 마우스의 값을 쓴다"를 못 잡고(M0 실측 3), 마우스의 가속은 체인이 안 본다(아래 끝 단락). 이 문서가 처음
적은 "둘 다 10"을 PS-M1 plan 확정 8이 바꿨다.

| 판정 | 무엇 | M |
|---|---|---|
| 가 | `tars-init: loaded /config/tars.conf`와 `tars-init: config … mouse_scroll=natural touchpad_scroll=normal` | M0 |
| 나 | 두 `open` 줄이 각자 `scroll=natural` · `scroll=normal`(한 부팅에서 다른 값) | M0 |
| 다 | `seq 200` 뒤 마우스 휠 위로 한 눈금 → `scroll>`의 `offset`이 PD 검사 11의 반대로 움직인다 | M0 |
| 라 | 같은 패널에서 `tp-replay`의 `scroll` → PD 검사 24의 반대로 움직인다 | M0 |
| 마 | `tars-config set touchpad_scroll=natural` → `reload` → `reload terminal` 뒤, 마우스 natural(−1) · 터치패드 natural(+1)로 두 칸의 부호가 다를 때 두 손가락 아래 → 위의 글(PS-M0이 더했다, 실측 3) | M0 |
| 바 | 터치패드 `open` 줄이 `accel=10`(마우스는 `accel=0`), 그리고 같은 `tp-replay move 100 0`이 boot B(accel 0)의 128픽셀보다 멀리, 배율 상한 4 × 128 안 | M1 |

boot B를 고치지 않고 새 부팅을 두는 것은, 기본값의 판정(PD 검사 11 · 24)이 그대로 남아야 "기본값은 지금 동작"이 계속 서기
때문이다. 판정 바의 "멀리"는 `tp-replay move`의 속도가 `V_LOW`를 넘어야 선다 — 넘는지는 plan이 패드 축 범위와 화면 폭으로
셈한다. 모자라면 `tp-replay`에 빠른 이동 명령을 더한다(PD 결정 10의 도구를 넓히는 일).

마우스의 가속은 체인에서 안 본다. HMP `mouse_move` 하나가 보고 하나라 `dt`를 모르고(배율 1), 명령 사이의 간격은 모니터 왕복이
정해 손으로 고를 수 없다. 마우스 쪽 곡선은 `pointer_test`가 시각을 지어 본다.

## 시나리오

| # | 상황 | 기대 |
|---|---|---|
| S1 | 설정 없음, 마우스와 노트북 터치패드 | 지금과 같다 — 휠 앞으로 = 위, 두 손가락 아래로 = 내용이 아래로, 가속 없음 |
| S2 | `mouse_scroll=natural` | 마우스만 뒤집힌다. 터치패드는 그대로 |
| S3 | `touchpad_scroll=normal` | 터치패드만 뒤집힌다 |
| S4 | 마우스 둘 | 둘 다 `mouse_*`를 따른다 |
| S5 | `mouse_accel=10`, 마우스를 천천히 | 배율 1 — 칸 하나를 고르는 손이 그대로다 |
| S6 | `mouse_accel=10`, 마우스를 빠르게 | 같은 손 거리가 최대 4배 간다 |
| S7 | `touchpad_accel=11` 또는 `fast` | 경고 한 줄, 값은 0 |
| S8 | `tars-config set mouse_scroll=natural` 뒤 `tars-config reload terminal` | 다시 뜬 terminal의 `open` 줄이 `scroll=natural` |
| S9 | `natural` 마우스로 vim `mouse=a`에 휠 | vim도 반대로 받는다(결정 2) |

## 위험

### 위험 1 — `mouse`로 읽히는 터치패드

모드 전환 전의 I2C-HID 터치패드나 PS/2 기본 프로토콜로만 잡힌 터치패드는 `REL_*`를 내 `mouse`로 분류된다(PD 결정 2). 그 장치는
`mouse_*`를 따르므로 사용자가 `touchpad_scroll`을 바꿔도 안 바뀐다. `open` 줄의 `kind=`가 그것을 보여 준다. 실기에서 만나면
`carryover.md`에 적는다.

### 위험 2 — 곡선의 출발값

`V_LOW` · `V_HIGH` · `GAIN_MAX`는 재지 않았다. 실기에서 level 10이 너무 약하거나 level 1이 이미 거슬리면 상수를 고친다. 단계의 뜻
(0 = 끔, 10 = 최대)은 유지한다.

### 위험 3 — 터치패드 보고 간격과 `dt`

터치패드는 손가락이 닿은 동안 보고를 꾸준히 내지만(대개 7~12ms), 손가락을 뗐다 다시 대면 첫 이동의 `dt`가 길다. `IDLE_US`가 그
경우를 배율 1로 둔다. `tp-replay`는 8ms 간격이라 게이트는 그 바깥을 못 본다.

### 위험 4 — 부팅 하나가 체인을 늘린다

boot C가 `pointer` 체인을 수십 초 늘린다. 루트 게이트의 lane 배치에서 `pointer`가 가장 긴 lane을 넘는지 M0의 게이트에서 본다.

## 비목표

1. 기본 속도(빠르기 배율) — `mouse_speed` · `touchpad_speed`. 터치패드의 "패드 가로 = 화면 가로"는 그대로 출발값이다. 실기에서
   너무 느리거나 빠르면 연다(사용자 결정 2026-11-04).
2. 장치 이름 · vendor별 설정. 종류 둘만 가른다.
3. 스크롤 가속 · 관성 스크롤 · 휠 한 눈금의 줄 수 설정.
4. 가로 휠(`REL_HWHEEL`)과 두 손가락 가로 스크롤 — PD가 버린 그대로다.
5. libinput식 곡선 프로파일(flat · adaptive) 선택. 곡선은 하나다.
6. 설정을 terminal을 다시 띄우지 않고 바꾸기. `reload terminal`이 패널을 잃는 것은 다른 키와 같다.

## Milestone

| M | 무엇 | 게이트 |
|---|---|---|
| M0 | `WheelDirection` · argv 칸 넷 · `config.zig`의 네 키(가속 칸은 읽어 나르기만) · `wheel_sign` · `open` 줄 · matcher 고치기 · boot C의 판정 가~마 | `pointer` 체인 + 루트 게이트 |
| M1 | 가속 상태 기계(순수, 이름은 M1 plan — `pointer.Accel`은 M0에서 단계 값의 이름이 됐다) · `pointer_test`의 곡선 검사 · 칸에 붙이기 · boot C의 판정 바 · mutation(가속을 안 곱하면 바가 빨강) | `pointer` 체인 + 루트 게이트 |

닫을 때: 이 문서의 `Status:`와 실측 절, PD design 비목표 6 · 7에 "PS로 갔다" 한 줄, `completed.md`, `docs/decisions/project_pointer_settings.md`
+ `MEMORY.md`, 소개 페이지 `data.js`, HANDOFF.

## 실측 (M0, 2026-11-04)

### 실측 1 — init이 막힌 자리 셋

plan 확인 1 · 2가 짚은 둘(`reload.Keys`의 `u16`, 타입으로 갈래를 고르는 네 함수)은 그대로였다. `Keys.Bits = u32`로 넓히고 상한을
`@bitSizeOf(Bits)`로 묶었다. 셋째는 plan이 못 본 것이다 — `config_test`의 실패 줄 하나가 값 열일곱의 got · want와 입력을 한
`print`에 넣어 인자가 35개가 되고, Zig의 format이 32개까지라 컴파일이 막혔다. got · want를 따로 찍는 `printConfig`로 나눴다.
`ARGC`가 13이 되며 서비스 argv 리터럴 넷(dbus · bluetoothd · wifi · chronyd · dhcpcd)과 init `main.zig`의 둘(콘솔 셸 · 서비스 자식)이
길이 불일치로 막혔다 — null을 넷씩 더했다.

seed `tars.conf`는 3376바이트, `user` 꼬리를 붙이면 3616바이트다(`MAX_FILE` 4096 안, `config_test`).

### 실측 2 — 부팅 C (판정 가~라)

| 판정 | 값 |
|---|---|
| 다 | natural 마우스의 휠을 뒤로 한 눈금 → offset 155 → 152, 앞으로 → 155. `at` 줄은 `wheel=1`(부호를 곱한 뒤) |
| 라 | normal 터치패드에서 두 손가락 위로 90단위 → 바닥에서 6줄 위, `at` 줄의 wheel 합 2 |

라는 첫 판에서 "읽어 둔 offset − 6"을 봤다가 빨갰다. 기준을 읽은 뒤 도구를 띄운 명령의 줄바꿈이 늦게 와 total이 204 → 205로
늘고, 패널이 그 바닥(158)으로 내려간 다음 152로 올라갔다(157 → 152, 5줄). 검사 24처럼 바닥에서의 거리(total − len − offset)로
판정해 섰다.

### 실측 3 — mutation 둘, 그리고 판정 마

| | 망가뜨린 것 | 잡은 판정 |
|---|---|---|
| a | `drainPointer`가 부호를 안 곱한다 | 다(offset 155 그대로, 기대 152) |
| b | `takePointer`가 종류를 안 보고 마우스의 값으로 부호를 고른다 | 처음엔 아무것도 못 잡았다(초록) → 판정 마 |

b가 빠져나간 이유: 부팅 C의 설정(마우스 natural · 터치패드 normal)은 두 칸의 부호가 둘 다 −1이고, 부팅 B의 기본값은 둘 다 +1이다.
"두 칸의 값이 다르다"를 보이려고 고른 조합이 "부호는 같다"였다. plan이 적은 "부팅 B 검사 24도 잡는다"도 같은 이유로 틀렸다.
그래서 판정 마를 더했다 — `tars-config set touchpad_scroll=natural` → `reload` → `reload terminal`로 다시 띄워 마우스 −1 · 터치패드
+1을 만들고, 두 손가락 아래가 위의 글을 보이는지 본다. b에서 offset이 158(바닥) 그대로라 빨갰다. 이 판정이 design 시나리오 S8
(`reload terminal`로 바뀐 값이 장치 칸까지 간다)도 함께 본다.

### 실측 4 — `pointer` 체인의 간헐: `screen_row`가 쓰는 중인 줄을 읽는다

PS-M0의 체인 회차 넷 가운데 둘이 부팅 A에서 빨갰다 — MC의 `mc-one mc-two:three is not a row of its own`과 `the 77-column row is not
on the last screen`. 둘 다 `screen_row`가 마지막 `screen>` 줄 하나에서 행을 찾는 판정이고, 바로 앞의 `wait_for_screen`은 같은 글자를
이미 봤으며, 실패 순간 시리얼 꼬리의 덤프에는 그 행이 있었다(저장한 꼬리로 다시 셈하면 행 44). `screen>` 한 줄은 수 KB라 시리얼
로그에 차례로 쓰이고, 쓰는 도중의 줄을 읽으면 뒤쪽(아래 행)이 아직 없다. 이번 변경은 프레임마다 찍는 줄을 늘리지 않았다 — 원래
있던 경합이다. `screen_row`가 못 찾으면 0.1초씩 3초까지 다시 읽게 했다. 그 뒤 체인 회차 셋(본 회차 둘 · mutation b)이 부팅 A를
다 통과했다.

### 실측 5 — 체인 시간

`pointer` 체인 259~274초(부팅 C 포함, 단독). `config` 330초 · `pane` 190초는 글자만 고친 체인이다.

### 실측 6 — 루트 게이트

`RUNS=1`: 26/27, 약 16분 50초(prebuild 375초 · lanes 635초), 잘린 로그 줄 0. 빨간 하나는 `BT-M2`의 `btvirt` GPF 간헐(세 번째,
`carryover.md`의 BT 항목)이고 체인만 다시 돌린 판은 초록이다. `pointer`(PD-M4) 회차는 146초로 가장 긴 레인(PM 246초) 안이다 —
위험 4는 일어나지 않았다. 부팅 C의 판정 가~마가 게이트 안에서도 섰다.


## 실측 (M1, 2026-11-04)

### 실측 7 — 곡선 검사

`pointer_test`에 `Ballistics` 검사 열넷(plan Task 2의 열한 행과 끝수 합). 손으로 셈한 기대값이 처음 판에 다 맞았다 — 단 plan 초안의
11행(빗변 (3, 4))은 t를 815로 반올림해 적었다가 셈 단계에서 814(`divTrunc`)로 고쳤다. 고정소수점의 기대값은 반올림이 아니라
버림으로 셈한다.

### 실측 8 — 판정 바

| 회차 | `move 100 0` | 비고 |
|---|---|---|
| 셈(8ms 간격) | 약 294픽셀 | 첫 보고 1:1, 나머지 아홉 걸음 배율 약 2.44 |
| 체인 단독 | 247픽셀(x 640 → 887) | |
| 루트 게이트 | 252픽셀 | |
| mutation a · b | 128픽셀 | 부팅 B와 같다 |

셈보다 짧은 것은 TCG에서 `tp-replay`의 8ms 걸음이 늘어난 만큼이다(걸음 간격 약 10ms면 맞는다). 판정이 범위(128 초과 · 512 이하)인
이유다. 부팅 B 검사 22(768 · 464)가 그대로라 단계 0은 PS 전과 같다.

### 실측 9 — mutation 둘

| | 망가뜨린 것 | 잡은 판정 |
|---|---|---|
| a | `drainPointer`가 `ballistics.apply`의 결과를 버린다 | 바(128) |
| b | `takePointer`가 종류를 안 보고 `prefs.mouse_accel`로 칸을 연다 | 바(128). `open` 줄은 `prefs`를 찍으므로 나는 초록 — plan의 예상대로 |

b는 디스크를 `mouse_accel=0` · `touchpad_accel=10`으로 가른 덕에 잡혔다(PS-M1 plan 확정 8, M0 실측 3의 교훈).

### 실측 10 — 루트 게이트

`RUNS=1`: 27/27, 15분 28초(prebuild 337초 · lanes 591초), 잘린 로그 줄 0. `pointer`(PD-M4) 회차 146초로 M0과 같다 — 판정 바가 더한
시간은 1~2초다. 가장 긴 레인은 PM 237초.
