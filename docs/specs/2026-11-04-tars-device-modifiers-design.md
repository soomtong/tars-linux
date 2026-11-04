# TARS Device Modifiers — Design

접두사: DM

Status: 끝났다(2026-11-04) — M0~M1, 결정 7 · 위험 3 · 실측 1~5. 수정키와 tap을 키보드 칸마다 들고, 빠진 키보드는 그 칸만 푼다. `keyboard` 체인 판정 8 · 9 · 10(M0에서 빨강 → M1에서 초록), mutation 셋 잡힘, 루트 게이트 27/27.

사용자가 정했다(2026-11-04): 결정 1~7을 추천안 그대로 받는다. 결정 2의 "다른 칸이 같은 tap 키를 쥐고 있으면 처음부터 소비"와
판정 10을 둔다. 키보드별 `keyboard=apple|pc`는 이번 범위가 아니다(비목표 1).

관련 문서: `2026-11-02-tars-keyboard-hotplug-design.md`(KH. 결정 3 · 4가 수정키를 하나로 합쳤고, 시나리오 S5와 비목표 5가 이
설계로 넘긴 자리) · `docs/decisions/project_keyboard_hotplug.md` · `docs/guides/carryover.md`의 KH 절 둘째 항목.

## 한 줄 요약

수정키 여덟과 tap 둘을 키보드 칸마다 따로 든다. 화면이 보는 "지금 Shift가 눌려 있는가"는 칸들의 OR이고, 키보드가 빠지면 그
칸의 것만 푼다. 한/영 · 조합 · CapsLock · copy mode 같은 사람 쪽 상태는 지금처럼 하나다.

## 왜 지금인가

KH가 키보드를 여럿 열면서 수정키를 하나의 `input.State`에 합쳤다(KH 결정 3). 장치를 건너는 조합(A의 Shift + B의 글자)은
그것으로 되지만, 대가가 둘 남았다(KH 결정 4의 끝, 시나리오 S5).

1. 같은 수정키를 두 키보드에서 겹쳐 쥐었다가 한쪽에서 떼면 둘 다 풀린다. 비트가 하나라 B의 뗌이 A의 누름을 지운다.
2. 한쪽 키보드가 빠지면 남은 쪽이 쥐고 있던 수정키도 풀린다. `releaseHeld`가 여덟을 다 거짓으로 만든다.

S5에는 tap 문제도 있다. A가 왼쪽 Ctrl을 쥔 동안 B의 왼쪽 Ctrl을 짧게 눌렀다 떼면, B의 뗌이 A의 누름에 짝지어져 한/영이
바뀐다. 사용자가 IK 다음으로 이 항목을 골랐다(2026-11-04). IK가 키보드 길을 막 정리해서 맥락이 가깝고, QEMU 게이트로 판정할 수
있다.

## 착수 전에 아는 것 (2026-11-04에 코드에서 확인, `8b8209d`)

### 확인 1 — 손의 상태는 `input.State`의 필드 열하나다

`terminal/src/input.zig`의 `State`:

| 필드 | 쓰는 곳 |
|---|---|
| `shift_left/right` · `ctrl_left/right` · `alt_left/right` · `meta_left/right` | `handleKey`의 수정키 갈래(쓰기), `shifted` · `ctrled` · `alted` · `metaed` · `modifiers` · `latinChar`와 받아쓰기의 `combined`(읽기) |
| `caps_tap` · `lctrl_tap`(`Tap`: `held` · `down_us` · `consumed`) | `handleKey`의 CapsLock · 왼쪽 Ctrl 갈래, `markTapConsumed` |
| `dictate_tap`(`dictation.DoubleTap`) | 오른쪽 Meta 갈래, 다른 키의 누름이 버린다, `SYN_DROPPED`가 버린다 |
| 위 전부 | `releaseHeld`(키보드가 빠질 때 `closeKeyboard`가 부른다) |

이 이름이 `input.zig`에 48번, `input_test.zig`에 10번, `main.zig`에 2번 나온다(`rg -c`). `main.zig`의 둘은 `closeKeyboard`의
`releaseHeld`와 그 주석이다. 읽는 쪽은 모두 `shifted()` 같은 함수를 거치거나 `handleKey` 안에 있다.

### 확인 2 — 어느 키보드의 키인지는 `readKeys` 한 번에 정해진다

`App.readKeyboards`가 키보드 칸을 순서대로 돌며 `readKeyboard(fd)` → `input.readKeys(&key_state, fd, …, ctx)`를 부른다. 한 번의
`readKeys`는 fd 하나를 읽으므로, 그 안의 모든 이벤트는 같은 키보드의 것이다. 칸 번호는 `readKeyboards`의 `ki`
(`fd_kbds[…]`)로 이미 손에 있고, 지금은 `closeKeyboard`에만 넘어간다. `input.Context`는 `readKeys` 호출 하나에 한 번 조립되는
값(DECCKM · `swap_alt_meta` · `dictating`)이라, 칸 번호가 들어갈 자리로 맞다.

### 확인 3 — `MAX_KEYBOARDS`는 `main.zig`에 있다

`main.zig:2383`의 `const MAX_KEYBOARDS = 8`. `input.zig`가 칸마다 상태를 들려면 이 수를 알아야 한다.

### 확인 4 — 커널이 해제 때 보내는 뗌은 그 장치의 것이다

KH 실측 9. `input_disconnect_device`는 빠지는 장치에서 눌려 있던 키만 뗌으로 흉내 낸다. 장치별로 들면 그 뗌은 빠지는 칸의 비트만
지우고, 다른 칸은 안 건드린다. KH가 "커널의 뗌과 `releaseHeld`가 둘 다 오면 같은 값을 두 번 쓸 뿐"이라고 적은 성질도 그대로
남는다.

### 확인 5 — 게이트가 장치를 골라 키를 쥘 수 있다

`keyboard/check.sh`의 `qmp_key gpu …`는 화면에 묶인 k2로, `qmp_key - …`는 묶이지 않은 k1로 간다(KH 실측 2). 판정 4가 이미
"k2의 Shift를 쥔 채 k1의 z"를 친다. 같은 Shift(qcode `shift`, 왼쪽)를 두 장치에서 따로 쥐고 떼는 것도 같은 길로 된다고 본다 —
QEMU가 키 상태를 장치 사이에서 나누지 않는지는 M0이 확인한다(위험 1).

## 결정

### 결정 1 — 수정키는 칸마다 비트 여덟이고, 읽을 때 OR한다

`State`의 수정키 bool 여덟을 `held: [MAX_KEYBOARDS]Mods`로 바꾼다. `Mods`는 bool 여덟짜리 `packed struct(u8)`이고 이름은 지금
필드 이름(`shift_left` … `meta_right`)을 그대로 쓴다. `handleKey`는 `held[ctx.device]`의 비트를 쓰고, 읽는 함수
(`shifted` · `ctrled` · `alted` · `metaed` · `modifiers`)는 여덟 칸의 OR를 본다.

OR이 KH 결정 3을 지킨다. A의 Shift + B의 글자는 여전히 대문자다(KH 판정 4 그대로). 바뀌는 것은 지우기다. B의 뗌은 B의 비트만
지우므로 A가 쥔 Shift가 남는다.

대안은 "그 수정키를 쥔 키보드의 수"를 세는 것이었다. 칸마다 비트를 들면 칸을 비울 때 그 칸의 몫을 정확히 알 수 있고, 수를 세면
그것을 모른다. 그래서 비트다. KH 결정 4가 "이 장치가 누른 수정키 비트 여덟"이라고 적어 둔 바로 그 모양이다.

비용은 메모리 8바이트와 읽기마다 OR 여덟 번이다. 키 하나에 수정키 읽기가 몇 번 있을 뿐이라 잴 만한 값이 아니다.

### 결정 2 — tap 둘도 칸마다 든다. 다른 칸의 누름은 소비로 친다

`caps_tap` · `lctrl_tap`을 `taps: [MAX_KEYBOARDS]Taps`(`caps` · `lctrl` 둘)로 바꾼다. 누름과 뗌의 짝은 같은 칸 안에서만
짓는다. 그래서 B의 뗌은 B의 누름에만 짝지어진다.

소비(`markTapConsumed`)는 칸을 건넌다. 어느 칸에서든 누름이 오면 모든 칸의 쥔 tap을 소비로 만든다. 같은 칸의 같은 키만 뺀다
(자동 반복이 자기를 소비하지 않게 — 지금 규칙 그대로다). 그래서 A의 Ctrl을 쥔 채 B의 글자를 치면, 지금처럼 A의 Ctrl은 tap이
아니다.

하나를 더한다. 다른 칸이 같은 tap 키를 이미 쥐고 있을 때의 누름은 처음부터 소비된 것으로 시작한다. S5의 B Ctrl이 그 경우다. 그
누름은 A가 쥔 Ctrl과 겹친 조합이지, 한/영을 바꾸려는 짧은 누름이 아니다. 이것이 없으면 위 규칙만으로는 A의 tap은 소비되지만 B의
tap이 남아 한/영이 바뀐다. 이 규칙은 키보드가 하나일 때는 생길 수 없는 경우만 건드린다. 한 키보드에는 같은 키가 둘 없으므로,
지금의 단일 키보드 동작은 한 줄도 안 바뀐다.

### 결정 3 — 받아쓰기 더블 탭은 하나 그대로다

`dictate_tap`은 칸마다 나누지 않는다. KH 시나리오 S6(A와 B의 오른쪽 Cmd를 한 번씩 → 더블 탭)은 받아들인 동작이고, 이 설계도
바꾸지 않는다. 더블 탭은 "사람이 두 번 눌렀다"는 판정이라 사람 쪽에 가깝다.

판정의 `combined`(다른 수정키가 눌려 있는가)는 결정 1의 OR를 본다. 다른 키보드의 Shift를 쥔 채 누른 오른쪽 Cmd도 조합이다 —
지금과 같다.

### 결정 4 — 키보드가 빠지면 그 칸만 푼다

`releaseHeld()`를 `releaseDevice(slot)`로 바꾼다. 그 칸의 `held`와 `taps`만 처음으로 돌린다. 다른 칸이 쥔 수정키와 tap은 남는다.
KH 결정 4의 대가("B가 빠지면 A의 Shift도 풀린다")가 이것으로 사라진다.

`dictate_tap`은 빠지는 칸이 오른쪽 Meta를 쥐고 있었을 때만 버린다. 그때는 첫 누름의 뗌이 영영 안 올 수 있으므로 판정이 "첫
누름"에 멈춘다(KH가 `releaseHeld`에서 버린 이유와 같다). 쥐고 있지 않았으면 그 키보드가 판정에 걸린 몫이 없으므로 진행 중인
판정을 그대로 둔다.

칸이 비면 다음에 들어오는 키보드가 그 칸을 쓴다. 비울 때 처음으로 돌리므로 새 키보드가 옛 비트를 물려받지 않는다.

사람 쪽(`hangul_on` · `hangul_buf` · `caps_lock` · `mode` …)은 지금처럼 안 건드린다(KH 시나리오 S4 그대로).

### 결정 5 — 칸 번호는 `Context.device`로 넘기고, `MAX_KEYBOARDS`는 `input.zig`로 옮긴다

`input.Context`에 `device: u8 = 0`을 더한다. `readKeyboards`가 이미 가진 `ki`를 `readKeyboard`에 넘기고, `readKeyboard`가
`Context`를 조립할 때 싣는다. `handleKey`의 시그니처는 안 바뀐다. 기본값이 0이라, 칸 번호를 모르는 단위 검사는 지금처럼 "키보드
하나"로 돈다.

`MAX_KEYBOARDS`는 `input.zig`로 옮겨 `pub`으로 두고, `main.zig`는 `input.MAX_KEYBOARDS`를 쓴다. 상태를 드는 쪽이 칸의 수를
정한다. 범위 밖 번호는 `handleKey` 머리의 `std.debug.assert`로 막는다. 칸 번호를 만드는 것은 `main.zig`의 칸 배열뿐이라 그
밖으로 나갈 길이 없다.

### 결정 6 — 로그 줄은 늘리지 않는다

`keyboard> close`가 이미 있고, 푸는 일은 그 줄 바로 뒤에 일어난다. 칸마다 쥔 비트를 찍는 줄을 더하면 키마다 줄이 생긴다. 게이트는
화면의 글자(대문자인가)와 `hangul>` 줄로 판정한다(결정 7).

### 결정 7 — 게이트는 `keyboard` 체인에 판정 셋을 더한다

체인 수는 27 그대로다. `keyboard/check.sh`에 KH 판정 7b 뒤로 셋을 더한다. 셋 다 지금 코드에서는 빨개야 한다(M0이 확인한다). 출력
글자는 명령줄에 없는 모양으로 고른다(KH 판정과 같은 요령).

8. 겹쳐 쥔 Shift의 한쪽 뗌(S5의 수정키 몫). k2(QMP `gpu`)의 Shift를 누른 채, k1(QMP `-`)의 Shift를 눌렀다 떼고, k1의 `z`. 화면에
   `Z`다. 지금 코드는 k1의 뗌이 비트를 지워 `z`다.
9. 남은 키보드의 Shift(결정 4). k1의 Shift를 누른 채 k2를 꽂았다가 `device_del`, 그다음 k1의 `z`. 화면에 `Z`다. 지금 코드는
   `releaseHeld`가 k1의 Shift까지 지워 `z`다. k2는 아무 키도 안 쥐었으므로 커널의 흉내 뗌도 없다 — 푸는 것은 우리 코드뿐이다.
10. 겹친 왼쪽 Ctrl tap(결정 2). k2의 왼쪽 Ctrl 누름 → k1의 왼쪽 Ctrl 누름 · 뗌 → k2의 뗌을 모두 300ms(`TAP_MAX_US`) 안에 한다.
    한/영이 안 바뀐다(`hangul> on=true` 줄이 새로 없다). 지금 코드는 k1의 뗌이 k2의 누름에 짝지어져 한/영이 켜진다.

KH 판정 4(장치를 건너는 조합) · 5(장치를 건너는 한글) · 7 · 7b는 그대로 초록이어야 한다. 이 설계가 바꾸면 안 되는 것을 그
판정들이 붙박는다.

mutation 셋(M1에서 돌린다). (a) 읽기의 OR를 `held[ctx.device]` 하나로 바꾼다 → KH 판정 4가 잡아야 한다. (b) `releaseDevice`가 모든
칸을 지운다 → 판정 9가 잡아야 한다. (c) 결정 2의 "처음부터 소비"를 뺀다 → 판정 10이 잡아야 한다.

단위 검사(`input_test.zig`)는 같은 셋과 받아쓰기 쪽 하나(결정 4 — 오른쪽 Meta를 쥔 칸이 빠지면 판정이 버려지고, 안 쥔 칸이 빠지면
남는다)를 칸 번호를 바꿔 가며 본다.

## 시나리오 다시 보기 (KH 시나리오 검토 중 이 설계가 바꾸는 것)

| | 시나리오 | KH의 동작 | DM 뒤 |
|---|---|---|---|
| S2 | A의 수정키 + B의 글자 | 조합이 된다 | 그대로(OR) |
| S4 | 조합 중에 A가 끊긴다 | 음절이 남는다 | 그대로 |
| S5 | A의 왼쪽 Ctrl을 쥐고 B의 왼쪽 Ctrl을 눌렀다 뗀다 | 한/영이 바뀌고 A의 Ctrl도 풀린다 | 한/영이 안 바뀌고 A의 Ctrl이 남는다 |
| S5' | A의 Shift를 쥔 채 B가 빠진다 | A의 Shift도 풀린다 | A의 Shift가 남는다 |
| S6 | A와 B의 오른쪽 Cmd로 더블 탭 | 더블 탭이 된다 | 그대로(결정 3) |
| S7 | 두 키보드의 자동 반복이 섞인다 | 섞인다 | 그대로(비목표 2) |
| S10 | 꽂는 순간 눌려 있던 키의 뗌 | 해 없음 | 그대로. 그 칸의 비트는 원래 거짓이다 |

## 위험

### 위험 1 — QEMU가 두 키보드의 같은 키를 따로 보내는지

판정 8 · 10은 같은 qcode(`shift` · `ctrl`)를 k1과 k2에서 겹쳐 쥔다. QEMU의 입력 층이 키 상태를 장치 사이에서 하나로 들고 "이미
눌린 키"의 둘째 누름을 버리면 판정이 시작부터 성립하지 않는다. KH 실측 2의 장치 건너 조합은 서로 다른 키였다. M0이 지금 코드에
판정을 붙여 빨강이 나오는 이유를 terminal의 로그로 확인한다. 둘째 누름이 게스트에 안 오면 `hidraw` 없이 볼 길이 없으므로, 그때는
판정 8 · 10을 단위 검사로만 두고 체인은 판정 9 하나로 줄인다.

### 위험 2 — 수정키 필드를 쓰는 자리가 넓다

확인 1의 60곳. 하나를 빠뜨리면 컴파일러가 잡는다 — 필드 이름이 `State`에서 사라지므로 옛 이름으로 읽는 줄은 빌드가 안 된다. 위험은
컴파일되는 실수다. `held[0]`처럼 칸을 고정해 쓰면 키보드 하나일 때는 맞고 둘일 때만 틀린다. M1은 편집 뒤 `rg 'held\[[0-9]'`가
`input.zig`에서 비어 있는지 보고, 단위 검사가 칸 0과 칸 1을 함께 쓰게 한다.

### 위험 3 — 칸 번호와 상태의 칸이 어긋난다

`main.zig`의 키보드 칸(`keyboard_devs`)과 `input.State`의 칸은 같은 번호를 쓴다는 약속으로만 이어진다. `readKeyboards`의 `ki`가 그
번호이고, `closeKeyboard`도 같은 `ki`로 `releaseDevice`를 부른다. 두 자리가 같은 변수를 쓰는 한 어긋나지 않는다. 칸을 옮기거나
압축하는 코드가 생기면 그때 깨진다 — 지금은 없다(빈 칸을 그대로 둔다).

## 비목표

1. 키보드마다 다른 `keyboard=apple|pc`(KH 비목표 1, `carryover.md` KH 절 셋째 항목). 장치를 고르는 키(이름 · vendor id)가
   설정에 생기는 일이라 따로 한다. 이 설계가 칸 번호를 `Context`에 싣는 것이 그 일의 자리가 된다 — `swap_alt_meta`를 칸마다 고르면
   된다.
2. 두 키보드의 자동 반복이 섞이는 것(S7) · 한 바퀴 안의 칸 순서(KH 위험 7) · 키 하나를 두 노드로 내는 키보드(KH 위험 6). 셋 다
   실기의 근거를 기다린다.
3. `SYN_DROPPED` 뒤에 `EVIOCGKEY`로 그 칸의 수정키를 다시 맞추기(KH 비목표 3). 칸마다 들게 되면서 할 자리는 생겼지만 핫플러그와
   같은 이유로 따로 한다.
4. 포인터 경로의 수정키(`modifiers()`, PD 결정 12)를 장치별로 나누기. 마우스는 키보드가 아니라서 "어느 키보드의 Shift인가"를 물을
   일이 없다. OR가 맞다.

## Milestone

한 milestone이 끝나면 다음 plan을 그때 쓴다.

- DM-M0 — 판정 8 · 9 · 10을 `keyboard/check.sh`에 먼저 넣고 지금 코드에서 돌린다. 셋이 빨개야 하고, 빨강의 이유가 위 "지금 코드는"
  문장과 같은지 로그로 본다(위험 1). terminal 코드는 0줄이다.
- DM-M1 — `input.zig`(결정 1 · 2 · 3 · 4 · 5, 단위 검사), `main.zig`(`ki`를 넘기기 · `MAX_KEYBOARDS` 옮기기 · `releaseDevice`).
  체인 초록, mutation 셋, 루트 게이트, 문서 닫기(KH design 결정 4의 대가 문단 · 비목표 5, `carryover.md` KH 둘째 항목, completed ·
  소개 페이지 · decisions · HANDOFF).

## 실측 (M0, 2026-11-04)

판정 셋을 넣은 체인의 일회용 사본(셋의 `report_failure`를 `echo "RED: …"`로 바꾼 것, 지웠다)을 `65b6f30`의 terminal로 두 판
돌렸다.

### 실측 1 — 커널 자동 반복이 수정키 결함을 가린다

첫 판에서 판정 10만 빨갛고 8 · 9는 초록이었다(`wZw0` · `vZv0`). 원인은 커널 input core의 자동 반복이다(`input_pass_values`).
장치마다 마지막에 누른 키를 250ms 뒤부터 33ms마다 value=2로 반복하고, 수정키도 반복한다. `handleKey`는 `shift_left = value != 0`이라
반복 이벤트가 비트를 다시 켠다.

- 판정 8: k2가 쥔 Shift의 반복이 k1의 뗌이 지운 비트를 곧 다시 켰다.
- 판정 9: `releaseHeld`가 지운 k1의 Shift를 k1 자신의 반복이 다시 켰다.

반복은 같은 장치에서 아무 키나 떼면 멈춘다(`input_stop_autorepeat`). 그래서 체인에 `stop_repeat`(그 장치의 오른쪽 Ctrl을 눌렀다
뗀다 — 화면에 아무것도 안 낸다)를 두고, 판정 8 · 9는 Shift를 쥔 뒤 그것을 부른다.

사람의 손에서 결함 둘이 드러나는 모양은 "Shift를 쥔 채 그 키보드로 글자를 하나 친 뒤"다. Shift만 쥐고 있는 동안은 반복이 비트를
지켜서 결함이 안 보인다. 실기에서 이 결함을 덜 겪은 이유가 이것일 수 있다. 판정 10(약 150ms)은 반복 지연 250ms보다 짧아 이
영향이 없었다.

결정은 그대로다. M1의 칸별 비트에서 반복은 자기 칸의 비트를 다시 켤 뿐이고, 그것이 맞는 동작이다.

### 실측 2 — 셋 다 빨갛고, 이유가 결정 7의 문장과 같다

`stop_repeat`을 넣은 둘째 판:

```
RED: k1's Shift key-up released the Shift k2 still holds (wzw0)
RED: k2 left and took k1's held Shift with it (vzv0)
RED: overlapping left Ctrl on two keyboards toggled hangul (hangul> on=true 3 -> 4)
```

판정 10의 양성 대조(k1 혼자의 왼쪽 Ctrl tap 둘이 한/영을 켜고 끈다)는 초록이었다 — QMP의 키가 tap 문턱 안에 온다. 판정 1~7b는
두 판 다 초록이다. 위험 1은 닫혔다. QEMU는 두 usb-kbd의 같은 qcode를 따로 보낸다. 사본 한 판은 컨테이너 빌드를 포함해 약 3분이다.

## 실측 (M1, 2026-11-04)

### 실측 3 — 단위 검사와 체인

`input_test` 검사 88(칸 0 · 1을 함께 쓰는 다섯 묶음, CapsLock의 겹친 tap 포함)이 초록이다. 검사 80 · 86은 `mods[0]` ·
`releaseDevice(0)`으로 고쳤고 뜻은 그대로다. `keyboard` 체인은 열한 판정이 다 초록이다 — M0에서 빨갰던 셋이 `wZw0` · `vZv0` ·
"한/영 그대로"다. KH 판정 1~7b도 그대로다.

### 실측 4 — mutation 셋이 다 잡혔다

| | 망가뜨린 것 | 잡은 판정 |
|---|---|---|
| a | `anyMods`가 칸 0만 읽는다 | 판정 3(`kh20` 없음) |
| b | `releaseDevice`가 모든 칸을 지운다 | 판정 9(`vzv0`) |
| c | 겹친 왼쪽 Ctrl의 "처음부터 소비"를 뺀다 | 판정 10(`on=true` 3 → 4) |

(a)는 결정 7이 기대한 판정 4보다 먼저 판정 3에서 잡혔다. k2가 칸 1이라 k2 혼자 친 `$`(Shift+4)도 Shift를 잃는다. 칸을 고정해 읽는
실수는 장치를 건너는 조합 없이도 "칸 0이 아닌 키보드" 하나로 드러난다.

### 실측 5 — 루트 게이트 27/27

15분 20초(prebuild 332 + lanes 586초), 잘린 로그 줄 0. `keyboard` 체인은 38초다(KH 실측 10의 34초 + 판정 셋). 첫 시도는 진입
검사에서 멈췄다 — 새 판정 두 줄의 `joined_screen_dump | grep -aq`(SIGPIPE가 `pipefail`로 거짓 판정이 되는 꼴, GA-M0)를
`grep -a … >/dev/null`로 고쳤다. `make quick`은 이 검사를 안 한다.
