# TARS Hardware Discovery HD-M2 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 파일 작성과
> 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을 제시하고
> 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는 이 저장소에 적용하지 않는다.

**Goal:** QEMU monitor에서 `system_powerdown`을 보내면 게스트의 PID 1이 그것을
전원 버튼 누름으로 받아 종료 순서를 밟고, 기계가 스스로 꺼진다. 지금은 ACPI가
이벤트를 만들어 주지만 **받는 쪽이 없다.**

**Design doc:** `docs/superpowers/specs/2026-08-20-tars-hardware-discovery-design.md`
(결정 4·7·8·9와 결정 11의 HD-M2 항목이 이 milestone의 몫이다. design은 이미
승인되어 있으므로 다시 논의하지 않는다. 다만 결정 4는 **실행 방식이 하나
바뀐다** — 아래 "이번에 정하는 것 1번"에 이유를 적었다.)

**Tech Stack:** Zig 0.16(libc 없이 `std.os.linux`만), evdev `input_event`,
`poll(2)`, QEMU monitor의 `system_powerdown`, bash 게이트 스크립트

---

## 이 milestone이 만지는 것은 저장소에서 가장 민감한 코드다

`init/src/main.zig:264`의 `waitpid(-1, &status, 0)`은 PM-M0이 milestone 하나를
통째로 써서 얻어낸 자리다. 그 한 줄이 성립하는 근거가 `power.zig:46`의
`.flags = 0`이고, 거기 적힌 주석이 이렇다.

> `SA_RESTART`를 켜지 않는다. 켜면 커널이 supervise의 waitpid를 안에서 자동
> 재시작해버려서, 플래그를 세워도 루프 머리로 영영 돌아오지 못한다.

**`poll`로 바꿔도 이 성질은 그대로 유지해야 한다.** `poll` 역시 `SA_RESTART`가
켜져 있으면 커널이 안에서 재시작하고, 그러면 `kill -TERM 1`이 다시 먹통이
된다. 새 코드의 `if (e == .INTR) continue;`가 기존 것과 같은 자리를 지킨다.

design이 HD-M2를 마지막에 둔 이유가 이것이다(위험 4번). M0·M1이 전부 통과한
지금에야 이 자리에 손댄다.

## 왜 이 순서인가

```
Task 1  전원 버튼 후보를 성질로 찾는다        ← 호스트 검사만으로 끝난다
  ↓     "키보드는 후보가 아니다"를 검사로 박는다
Task 2  버튼 이벤트 바이트를 읽는다            ← 호스트 검사만으로 끝난다
  ↓     pipe로 진짜 fd를 통과시켜 시험한다
Task 3  종료 요청을 플래그 자리로 모은다       ← 호스트 검사만으로 끝난다
  ↓     (design 결정 9)
Task 4  PID 1이 버튼을 연다                    ← 여기서 처음 게스트를 띄운다
  ↓     감독 루프는 아직 안 건드린다. 로그 문구를 여기서 확정한다
Task 5  감독 루프를 poll 구조로 바꾼다         ← 가장 민감한 편집
  ↓
Task 6  기존 다섯 체인이 그대로 통과하는가     ← 회귀
  ↓
Task 7  새 체인 device/check.sh               ← 완료선
  ↓
Task 8  루트 게이트에 체인을 넣고 3/3
  ↓
Task 9  문서
```

**Task 1~3이 앞인 이유는 부팅 없이 판정할 수 있기 때문이다.** 셋 다
`zig build test` 한 번으로 끝나고, 커널 빌드도 QEMU도 필요 없다. 20초짜리
부팅으로 잡을 실패를 0.1초로 먼저 잡는다 — `init/build.zig:56`이 적어 둔
원칙이 그대로 적용된다.

**Task 4가 Task 5보다 앞인 이유는 중간 상태가 안전하기 때문이다.** 버튼 fd를
열어만 두고 아무도 `poll`하지 않는 상태는 무해하다. 커널의 이벤트 큐가
차기만 하고 그것을 기다리는 코드가 없다. 그 안전한 상태에서 "후보가 몇 개
열렸는가"를 실물로 확인하고 나서 감독 루프에 손댄다.

**Task 4가 Task 7보다 앞인 이유는 로그 문구 때문이다.** 게이트가 grep할
문자열은 실제로 찍힌 것을 보고 확정한다. 코드에 적은 문구와 게이트가 찾는
문구가 어긋나는 사고가 이 저장소에 이미 있었다(`HANDOFF.md`의 "로그 문구는
두 곳에 중복된다").

**Task 6이 Task 7보다 앞인 이유는 위험의 성격이다.** Task 5는 다섯 체인 전부가
딛고 선 코드를 바꾼다. 새 체인을 만들기 전에 **기존 것이 안 깨졌는지** 먼저
본다. 새 체인이 통과하는데 옛 체인이 깨지는 것이 이 milestone에서 가장
그럴듯한 실패다.

## 이번에 정하는 것 여섯 (design doc이 안 정한 자리)

### 1. 전원 버튼 후보에서 키보드를 제외한다

design 결정 4는 "`KEY_POWER`(116)가 서 있는 장치"를 후보로 정의했다. 그런데
**QEMU의 AT 키보드도 `KEY_POWER`를 갖고 있다.** HD-M0이 실측해
`devices_test.zig:137`에 적어 둔 비트맵을 그 기준으로 읽으면 이렇다.

| 키 | 코드 | 워드 | 비트 | AT 키보드 |
|---|---|---|---|---|
| `KEY_ESC` | 1 | 0 | 1 | 서 있음 |
| `KEY_A` | 30 | 0 | 30 | 서 있음 |
| **`KEY_POWER`** | **116** | **1** | **52** | **서 있음** |
| `KEY_SLEEP` | 142 | 2 | 14 | 서 있음 |

1번 워드가 `0xfeffffdfffefffff`이고 그 52번 비트가 1이다. `atkbd`가 ACPI 확장
키(전원·절전·깨우기)를 스캔코드 표에 갖고 있기 때문이며, 실 하드웨어의 USB
키보드도 대개 같다.

그래서 판정에 조건을 하나 더한다.

```
전원 버튼 = EV_KEY가 있고 + KEY_POWER가 서 있고 + 키보드가 아니다
```

**제외하지 않으면 무슨 일이 생기는가.**

1. PID 1이 키보드 fd를 열고 `poll` 목록에 넣는다. 그러면 **글자 하나를 칠
   때마다 감독 루프가 깨어난다.** 게이트가 게스트에 한 글자씩 0.3초 간격으로
   타이핑하므로 이것은 가정이 아니라 매 회차 일어나는 일이다.
2. 깨어나서 이벤트를 안 읽으면 큐가 그대로 남아 `poll`이 즉시 다시 반환하고,
   PID 1이 CPU를 태우는 바쁜 루프가 된다. 읽어서 버리더라도 같은 키를
   `terminal`과 PID 1이 각자 해석하는 구조가 남는다.
3. 키보드의 전원 키를 무엇으로 옮길지는 **Input Policy의 몫이다**
   (`docs/decisions/project_input_policy.md`). 그 결정을 이 milestone이 몰래
   가져가면 안 된다.

이 함수가 찾는 것은 "누르면 기계가 꺼지는 물리 버튼"이다. 키보드에 달린 키는
키보드의 일이다.

**결정 4의 정신은 그대로 남는다.** 후보를 하나만 고르지 않고 전부 여는 것,
상한을 넷으로 두는 것, 몇 개를 열었는지 로그로 남기는 것은 바뀌지 않는다.

### 2. 감독 루프의 backoff 1초를 `poll` 타임아웃이 대신한다

지금 감독 루프는 자식을 거둔 뒤 `sleepOneSecond()`로 재시작을 늦춘다
(`main.zig:312`). 새 구조에서 순서를 이렇게 잡으면 그 `sleep`이 필요 없어진다.

```
루프 머리 → 종료 요청 확인 → 안 떠 있는 자식을 띄운다
         → waitpid(WNOHANG)로 거둘 것을 전부 거둔다
         → poll(버튼 fd들, 1000ms)   ← 유일하게 잠드는 자리
```

거두기가 `poll`보다 **앞**이라, 자식이 죽으면 그 바퀴에서 거두고 곧바로
`poll`에 들어가 1초를 잔다. 다음 바퀴 머리에서 재시작이 일어나므로 재시작
간격은 여전히 1초 이상이다. **`poll` 타임아웃이 곧 backoff다.**

이렇게 하면 `sleepOneSecond()` 호출 셋이 전부 사라지고 "PID 1이 잠드는 자리는
`poll` 하나"가 된다. 대안으로 `Child`에 `restart_after` 필드를 더하는 길도
있지만, 가장 민감한 코드에 상태를 하나 더 얹는 것보다 순서로 푸는 편이 낫다.

`tars-init: restarting {s} in 1s` 로그 문구는 **그대로 둔다.** 여전히 참이고,
`terminal/check.sh:178`이 진단 목록에서 이 문구를 쓰고 있다.

### 3. 버튼 fd는 `O_NONBLOCK`으로 열고, 깨어나면 **전부** 읽어 비운다

`poll`이 알려 주는 것은 "읽을 것이 있다"까지다. 읽어서 비우지 않으면 다음
`poll`이 즉시 반환하고 바쁜 루프가 된다 — `terminal/src/main.zig:216`이 PTY
master의 `POLLHUP`에서 똑같은 함정을 이미 적어 두었다.

`O_NONBLOCK`인 이유는 비었을 때의 마지막 `read`가 `EAGAIN`으로 돌아와야
루프를 끝낼 수 있기 때문이다. 블로킹이면 그 자리에서 영영 멈춘다.

### 4. 한 번의 누름만 종료가 된다 (`value == 1`)

evdev는 같은 키에 대해 누름(1)·뗌(0)·자동 반복(2)을 각각 이벤트로 준다.
design 결정 8이 정한 대로 누름만 받는다. QEMU의 `system_powerdown`은 누름과
뗌을 한 쌍으로 보내므로, 이것을 안 거르면 한 번 누른 것이 두 번이 된다.

### 5. `device/check.sh`는 디스크 없이 부팅한다

전원 버튼은 설정과 무관하다. CP·IP·PM 체인이 `-drive`를 다는 것은 각자
설정 영속성·키맵·셸 종류를 봐야 하기 때문이고, 이 체인이 보는 것에는 그런
것이 없다. `make_disk.sh`를 만들지 않으므로 `device/` 디렉터리에는
`check.sh` 하나만 들어간다.

부수 효과가 하나 있다. 디스크가 없으면 셸은 기본값 fish이고, 이 체인은
게스트에 **한 글자도 타이핑하지 않는다** — 종료 명령이 monitor에서 오기
때문이다. 그래서 이 체인은 다른 것들보다 빠르다(회차당 부팅 1회, 타이핑 0회).

### 6. `-no-reboot`을 달고, 음성 검사로 리셋과 구별한다

`power/check.sh`가 HD-M1에서 정한 것과 같은 이유다. "QEMU가 사라졌다"는
`-no-reboot` 때문에 리셋으로도 성립하므로, 로그에 `Restarting system`이
**없어야 한다**는 음성 검사로 둘을 가른다.

## 새로 생기는 로그 문구 (두 곳에 중복된다)

`HANDOFF.md`의 목록에 넷이 는다. `init` 코드와 `device/check.sh` 양쪽에 있으니
한쪽을 고치면 다른 쪽도 고쳐야 한다.

| 문구 | 찍는 곳 | 게이트가 요구하는 것 |
|---|---|---|
| `tars-init: power button /dev/input/event` | `devices.zig` | 있어야 한다 |
| `tars-init: watching N power button(s)` | `devices.zig` | 개수는 Task 4에서 확정 |
| `tars-init: no power button found` | `devices.zig` | **없어야 한다** |
| `tars-init: power button pressed` | `main.zig` | 있어야 한다 |

## 사전 준비

모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서 실행한다.
`main` 브랜치, working tree가 깨끗한 상태에서 시작한다.

**`docker run`/`docker build`에 `--platform`을 붙이지 않는다**
(`docs/decisions/project_build_host_arch.md`).

**이미지 재빌드는 필요 없다.** 새 외부 의존이 없다.

**긴 편집은 `/tmp` 경로로 한다.** Task 5(`main.zig`의 `supervise` 교체)와
Task 7(`device/check.sh` 신규)이 그 대상이다. plan에 전문을 적어 두었고,
실행할 때 Claude가 같은 내용을 `/tmp`에 파일로 만들어 준다. 사용자는 `cp`로
제자리에 넣고, 기존 파일이면 넣기 전에 Claude가 `diff`로 대조한다.

**인라인으로 제시하는 블록은 "넣을 것"만 적는다.** 지울 것이 있는 편집은
`지울 것`과 `넣을 것`을 따로 표시했다.

---

## Task 1: 전원 버튼 후보를 성질로 찾는다

부팅 없이 끝나는 세 Task 중 첫째다. 검사를 먼저 쓰고, 실패를 확인하고,
구현한다.

**Files:**
- Modify: `init/src/devices_test.zig` (검사 추가)
- Modify: `init/src/devices.zig` (`KEY_POWER`, `MAX_BUTTONS`,
  `looksLikePowerButton`, `findPowerButtons` 추가)

- [ ] **Step 1: 실패하는 검사를 먼저 넣는다**

`init/src/devices_test.zig`의 마지막 줄(`devices_test: a missing keyboard falls
back to event0`을 찍는 `std.debug.print` 다음, 함수를 닫는 `}` **앞**)에 아래
블록을 넣는다.

```zig

    // ── 8. 전원 버튼 판정 (HD-M2) ─────────────────────────────────────
    //
    // **이 절의 첫 두 줄이 HD-M2에서 가장 중요한 검사다.** QEMU의 AT
    // 키보드도 KEY_POWER를 갖고 있다 — 위 keyboard_key의 1번 워드
    // 0xfeffffdfffefffff의 52번 비트가 그것이다. atkbd가 ACPI 확장 키를
    // 스캔코드 표에 갖고 있기 때문이고, 실 하드웨어의 USB 키보드도 대개
    // 같다. 그래서 "KEY_POWER가 서 있는 장치"를 그대로 후보로 삼으면
    // 키보드가 딸려 들어오고, PID 1이 글자 하나마다 깨어나게 된다.
    if (!devices.bitSet(keyboard_key, 116)) {
        std.debug.print("FAIL: the AT keyboard is expected to have KEY_POWER\n", .{});
        return error.KeyboardLostPowerKey;
    }
    if (devices.looksLikePowerButton("120013", keyboard_key)) {
        std.debug.print("FAIL: a keyboard must not pass as a power button\n", .{});
        return error.KeyboardMisreadAsButton;
    }
    // 진짜 전원 버튼은 통과해야 한다.
    if (!devices.looksLikePowerButton("3", "10000000000000 0")) {
        std.debug.print("FAIL: the ACPI power button should look like one\n", .{});
        return error.PowerButtonNotRecognized;
    }
    // BTN_LEFT만 가진 장치는 KEY_POWER가 없으므로 통과하면 안 된다.
    if (devices.looksLikePowerButton("3", "10000 0 0 0 0")) {
        std.debug.print("FAIL: a mouse must not pass as a power button\n", .{});
        return error.MouseMisreadAsButton;
    }

    std.debug.print("devices_test: a keyboard has KEY_POWER but is not a button\n", .{});

    // ── 9. 가짜 트리에서 후보를 고른다 ────────────────────────────────
    //
    // FULL에는 전원 버튼(event0) · 키보드(event1) · 마우스(event2)가 있다.
    // 골라야 할 것은 event0 하나뿐이다. 키보드가 함께 나오면 위 8번이
    // 잡지 못한 무언가가 findPowerButtons에 있다는 뜻이다.
    var buttons: [devices.MAX_BUTTONS]u8 = undefined;
    const count = devices.findPowerButtons(FULL, &buttons);
    if (count != 1) {
        std.debug.print("FAIL: found {d} power buttons in the fake tree, want 1\n", .{count});
        return error.WrongButtonCount;
    }
    if (buttons[0] != 0) {
        std.debug.print("FAIL: picked event{d} as the power button, want event0\n", .{buttons[0]});
        return error.WrongButtonPicked;
    }

    // 전원 버튼만 있는 트리에서도 같은 답이 나와야 한다.
    const lone = devices.findPowerButtons(BUTTON, &buttons);
    if (lone != 1 or buttons[0] != 0) {
        std.debug.print("FAIL: a lone power button was not found (count {d})\n", .{lone});
        return error.ButtonNotFound;
    }

    std.debug.print("devices_test: picked the power button and left the keyboard alone\n", .{});
```

- [ ] **Step 2: 검사가 실패하는지 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test'
```

기대: **컴파일 에러.** `devices.looksLikePowerButton`과
`devices.findPowerButtons`, `devices.MAX_BUTTONS`가 아직 없으므로
`error: root source file struct 'devices' has no member named ...` 같은 줄이
나온다. 여기서 통과가 나오면 무언가 잘못된 것이므로 멈춘다.

- [ ] **Step 3: `devices.zig`에 상수 둘을 더한다**

`init/src/devices.zig:45`의

```zig
const KEY_D: u16 = 32;
```

**다음**에 아래 블록을 넣는다.

```zig

/// 전원 버튼의 키 코드. include/uapi/linux/input-event-codes.h의 KEY_POWER다.
/// 116번이라 1번 워드의 52번 비트에 앉는다 — 비트맵을 뒤에서부터 세는 것이
/// 이 파일에서 유일하게 미묘한 부분이라고 bitSet에 적어 둔 그 자리다.
const KEY_POWER: u16 = 116;

/// 열어 둘 전원 버튼의 상한(design 결정 4). ACPI는 FADT의 고정 하드웨어
/// 버튼과 DSDT가 선언한 장치를 각각 등록할 수 있어서, 하나만 골랐다가 틀리면
/// 버튼이 **조용히** 죽는다. HD-M1의 실측으로는 QEMU에 하나뿐이지만, 그
/// 침묵보다는 넉넉한 상한으로 전부 여는 편이 낫다.
pub const MAX_BUTTONS: usize = 4;
```

- [ ] **Step 4: 판정 함수를 더한다**

같은 파일에서 `looksLikeKeyboard`가 끝나는 자리, 즉

```zig
pub fn looksLikeKeyboard(ev: []const u8, key: []const u8) bool {
    if (!bitSet(ev, EV_KEY)) return false;

    var code: u16 = KEY_ESC;
    while (code <= KEY_D) : (code += 1) {
        if (!bitSet(key, code)) return false;
    }
    return true;
}
```

**다음**에 아래 블록을 넣는다.

```zig

/// 이 장치가 "누르면 기계가 꺼지는 물리 버튼"인가.
///
/// **키보드를 명시적으로 제외하는 것이 이 함수의 핵심이다.** QEMU의 AT
/// 키보드도 KEY_POWER를 갖고 있다 — devices_test가 실측해 둔 비트맵의 1번
/// 워드 0xfeffffdfffefffff의 52번 비트가 그것이고, atkbd가 ACPI 확장 키를
/// 스캔코드 표에 갖고 있기 때문이다. 제외하지 않으면 PID 1이 키보드 fd까지
/// 열어서 글자 하나마다 감독 루프가 깨어나고, 같은 키를 terminal과 PID 1이
/// 서로 다른 뜻으로 읽게 된다.
///
/// 키보드에 달린 전원 키를 무엇으로 옮길지는 Input Policy의 몫이다
/// (docs/decisions/project_input_policy.md). 이 함수는 그 결정을 가져가지
/// 않는다.
pub fn looksLikePowerButton(ev: []const u8, key: []const u8) bool {
    if (!bitSet(ev, EV_KEY)) return false;
    if (!bitSet(key, KEY_POWER)) return false;
    return !looksLikeKeyboard(ev, key);
}
```

- [ ] **Step 5: 탐색 함수를 더한다**

같은 파일에서 `findKeyboard`가 끝나는 자리, 즉

```zig
        if (looksLikeKeyboard(ev, key)) return n;
    }
    return null;
}
```

**다음**에 아래 블록을 넣는다.

```zig

/// 전원 버튼처럼 생긴 evdev 번호를 out에 채우고 그 개수를 돌려준다.
///
/// 키보드와 달리 첫 번째 것만 쓰지 않고 **전부** 모은다(design 결정 4).
/// 키보드가 여럿일 이유는 없지만 전원 버튼은 둘일 수 있고, 그중 어느 것이
/// 실제로 우는지는 밖에서 알 수 없기 때문이다.
pub fn findPowerButtons(sys_root: []const u8, out: []u8) usize {
    var found: usize = 0;
    var n: u8 = 0;
    while (n < MAX_EVENT and found < out.len) : (n += 1) {
        var ev_buf: [MAX_BITMAP]u8 = undefined;
        const ev = readAttr(sys_root, n, "capabilities/ev", &ev_buf) orelse continue;

        var key_buf: [MAX_BITMAP]u8 = undefined;
        const key = readAttr(sys_root, n, "capabilities/key", &key_buf) orelse continue;

        if (!looksLikePowerButton(ev, key)) continue;
        out[found] = n;
        found += 1;
    }
    return found;
}
```

- [ ] **Step 6: 검사가 통과하는지 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test'
```

기대: 마지막에 아래 두 줄이 새로 찍히고 종료 코드가 0이다.

```
devices_test: a keyboard has KEY_POWER but is not a button
devices_test: picked the power button and left the keyboard alone
```

`the AT keyboard is expected to have KEY_POWER`가 나오면 조사가 틀렸다는
뜻이므로 멈추고 알려 줄 것 — 그 경우 이번에 정하는 것 1번의 전제가 무너지고
`looksLikePowerButton`의 제외 조건을 다시 논의해야 한다.

- [ ] **Step 7: 커밋**

```bash
git add init/src/devices.zig init/src/devices_test.zig
git commit -m "Tell a power button apart from a keyboard that has a power key"
```

---

## Task 2: 버튼 이벤트 바이트를 읽는다

fd에서 읽어 "전원 버튼이 눌렸는가"를 답하는 조각이다. 이것도 부팅 없이
끝난다 — 검사가 `pipe(2)`로 진짜 fd를 만들어 이벤트 바이트를 흘려 넣는다.

**Files:**
- Modify: `init/src/devices_test.zig` (검사 추가)
- Modify: `init/src/devices.zig` (`Event`, `drainButton` 추가)

- [ ] **Step 1: 실패하는 검사를 먼저 넣는다**

`init/src/devices_test.zig`의 마지막(Task 1이 넣은 블록 다음, 함수를 닫는 `}`
**앞**)에 아래 블록을 넣는다.

```zig

    // ── 10. 이벤트 바이트 (HD-M2) ─────────────────────────────────────
    //
    // 진짜 evdev를 열 수는 없으므로 pipe로 fd를 만들어 같은 바이트를
    // 흘려 넣는다. 커널이 주는 것과 다른 점은 "이벤트 경계로 잘라 준다"는
    // 보장이 없다는 것뿐이고, 우리가 24의 배수로 쓰면 그 차이가 없어진다.
    //
    // O_NONBLOCK으로 만드는 것이 요점이다. drainButton은 EAGAIN을 "이제
    // 비었다"로 읽고 루프를 끝내므로, 블로킹 pipe면 그 자리에서 영영 멈춘다.
    if (@sizeOf(devices.Event) != 24) {
        std.debug.print("FAIL: input_event is {d} bytes, want 24\n", .{
            @sizeOf(devices.Event),
        });
        return error.WrongEventSize;
    }

    var pipe_fds: [2]i32 = undefined;
    if (failed(linux.pipe2(&pipe_fds, .{ .NONBLOCK = true }))) |e| {
        std.debug.print("FAIL: pipe2 (errno {d})\n", .{@intFromEnum(e)});
        return error.PipeFailed;
    }
    const rd = pipe_fds[0];
    const wr = pipe_fds[1];

    // 비어 있는 fd는 "안 눌렸다"다. EAGAIN이 예외가 아니라 정상 경로라는
    // 것을 이 한 줄이 붙박는다.
    if (devices.drainButton(rd)) {
        std.debug.print("FAIL: an empty fd reported a press\n", .{});
        return error.EmptyFdReportedPress;
    }

    // QEMU의 system_powerdown이 실제로 보내는 모양: 누름 · 동기화 · 뗌 ·
    // 동기화. 뗌(0)까지 누름으로 세면 한 번의 누름이 두 번이 된다.
    const press = [_]devices.Event{
        .{ .sec = 0, .usec = 0, .@"type" = 1, .code = 116, .value = 1 },
        .{ .sec = 0, .usec = 0, .@"type" = 0, .code = 0, .value = 0 },
        .{ .sec = 0, .usec = 0, .@"type" = 1, .code = 116, .value = 0 },
        .{ .sec = 0, .usec = 0, .@"type" = 0, .code = 0, .value = 0 },
    };
    try writeEvents(wr, &press);
    if (!devices.drainButton(rd)) {
        std.debug.print("FAIL: a power press was not reported\n", .{});
        return error.PressNotSeen;
    }
    // 앞의 호출이 비웠어야 한다. 안 비우면 poll이 곧바로 다시 깨어나서
    // PID 1이 CPU를 태우는 바쁜 루프가 된다.
    if (devices.drainButton(rd)) {
        std.debug.print("FAIL: the fd still had events after draining\n", .{});
        return error.FdNotDrained;
    }

    // 뗌만 온 경우. 누름이 아니므로 종료가 되면 안 된다.
    const release_only = [_]devices.Event{
        .{ .sec = 0, .usec = 0, .@"type" = 1, .code = 116, .value = 0 },
    };
    try writeEvents(wr, &release_only);
    if (devices.drainButton(rd)) {
        std.debug.print("FAIL: a key release was reported as a press\n", .{});
        return error.ReleaseReportedAsPress;
    }

    // 다른 키가 눌린 경우. 이 fd에는 전원 버튼만 오게 되어 있지만, 코드를
    // 실제로 본다는 증거를 남긴다.
    const other_key = [_]devices.Event{
        .{ .sec = 0, .usec = 0, .@"type" = 1, .code = 30, .value = 1 },
    };
    try writeEvents(wr, &other_key);
    if (devices.drainButton(rd)) {
        std.debug.print("FAIL: KEY_A was reported as a power press\n", .{});
        return error.WrongKeyReported;
    }

    _ = linux.close(wr);
    _ = linux.close(rd);

    std.debug.print("devices_test: only a KEY_POWER press counts, and the fd is drained\n", .{});
```

같은 파일의 `main()` **앞**(예를 들어 `makeDevice` 함수 다음)에 헬퍼를 하나
넣는다.

```zig

/// 이벤트 배열을 fd에 그대로 쓴다. 커널이 evdev에 찍는 것과 같은 바이트다.
fn writeEvents(fd: i32, events: []const devices.Event) !void {
    const bytes = std.mem.sliceAsBytes(events);
    var written: usize = 0;
    while (written < bytes.len) {
        const n = linux.write(fd, bytes.ptr + written, bytes.len - written);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            std.debug.print("FAIL: write events (errno {d})\n", .{@intFromEnum(e)});
            return error.WriteFailed;
        }
        if (n == 0) return error.WriteFailed;
        written += n;
    }
}
```

- [ ] **Step 2: 검사가 실패하는지 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test'
```

기대: **컴파일 에러.** `devices.Event`와 `devices.drainButton`이 없다.

- [ ] **Step 3: 이벤트 구조체를 더한다**

`init/src/devices.zig`의 `MAX_BUTTONS` 정의 **다음**에 아래 블록을 넣는다.

```zig

/// evdev가 내놓는 이벤트 하나. include/uapi/linux/input.h:28의
/// struct input_event와 같은 모양이어야 한다. 64비트에서는 timeval이
/// 16바이트라 전체가 24바이트다.
///
/// terminal은 같은 구조체를 libc 헤더에서 가져오지만
/// (terminal/src/input.zig:426), init은 libc를 링크하지 않으므로 여기에 손으로
/// 적는다(docs/decisions/project_zig_c_uapi_rule.md). 손으로 적은 레이아웃이
/// 틀리면 조용히 엉뚱한 바이트를 읽게 되므로, devices_test가 @sizeOf를
/// 직접 확인한다.
///
/// 필드 이름 @"type"은 C의 것을 그대로 쓴 것이다. type이 Zig에서 원시 타입의
/// 이름이라 따옴표가 필요하고, terminal 쪽도 같은 모양으로 읽는다.
pub const Event = extern struct {
    sec: i64,
    usec: i64,
    @"type": u16,
    code: u16,
    value: i32,
};

/// 키를 누른 것. 뗌은 0이고 자동 반복은 2다. 누름만 받는 이유는 한 번의
/// 누름이 종료를 한 번만 일으켜야 하기 때문이다 — QEMU의 system_powerdown은
/// 누름과 뗌을 한 쌍으로 보내므로, 안 거르면 한 번이 두 번이 된다.
const VALUE_PRESS: i32 = 1;
```

- [ ] **Step 4: `drainButton`을 더한다**

같은 파일의 **맨 끝**(`resolveKeyboard`가 끝난 다음)에 아래 블록을 넣는다.

```zig

/// 버튼 fd에 쌓인 것을 **전부** 읽어 비우고, 그 안에 전원 버튼 누름이
/// 있었는지 돌려준다. poll이 "읽을 것이 있다"고 알려 준 뒤에만 부른다.
///
/// **다 읽어 비우는 것이 이 함수의 절반이다.** 남겨 두면 다음 poll이 곧바로
/// 다시 깨어나서 PID 1이 CPU를 태우는 바쁜 루프가 된다 —
/// terminal/src/main.zig:216이 PTY master의 POLLHUP에서 똑같은 함정을 적어
/// 두었다.
///
/// fd는 O_NONBLOCK으로 열려 있다. 그래서 마지막 read가 EAGAIN으로 돌아오는
/// 것이 예외가 아니라 이 루프의 정상 종료 경로다.
pub fn drainButton(fd: i32) bool {
    var pressed = false;
    var raw: [@sizeOf(Event) * 16]u8 = undefined;

    while (true) {
        const rc = linux.read(fd, &raw, raw.len);

        // EAGAIN이 이 루프의 정상 종료 경로다 — fd가 O_NONBLOCK이므로 "다
        // 읽었다"가 그 errno로 온다. EINTR도 여기서 끝낸다. 남은 것이
        // 있었다면 다음 poll이 다시 알려 주므로, 시그널 하나 때문에 여기
        // 머물 이유가 없다.
        if (failed(rc)) |_| return pressed;

        if (rc == 0) return pressed; // EOF. 장치가 사라진 경우다.

        var off: usize = 0;
        while (off + @sizeOf(Event) <= rc) : (off += @sizeOf(Event)) {
            const ev: *align(1) const Event = @ptrCast(&raw[off]);
            if (ev.@"type" != EV_KEY) continue;
            if (ev.code != KEY_POWER) continue;
            if (ev.value == VALUE_PRESS) pressed = true;
        }

        // 버퍼를 꽉 채워 왔으면 더 남아 있을 수 있다. 덜 채웠으면 그것이 곧
        // "이번에는 이게 전부"라는 뜻이다.
        if (rc < raw.len) return pressed;
    }
}
```

- [ ] **Step 5: 검사가 통과하는지 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test'
```

기대: 아래 줄이 새로 찍히고 종료 코드가 0이다.

```
devices_test: only a KEY_POWER press counts, and the fd is drained
```

`input_event is N bytes, want 24`가 나오면 구조체 레이아웃이 틀린 것이다.
**N을 그대로 알려 줄 것** — 정렬 문제인지 필드 크기 문제인지가 그 숫자로
갈린다.

- [ ] **Step 6: 커밋**

```bash
git add init/src/devices.zig init/src/devices_test.zig
git commit -m "Read a power button press out of the evdev byte stream"
```

---

## Task 3: 종료 요청을 플래그 자리로 모은다

design 결정 9다. 버튼을 보고 곧바로 `power.shutdown()`을 부르지 않고, 시그널이
쓰는 것과 **같은 플래그**에 세운다.

**Files:**
- Modify: `init/src/power_test.zig` (검사 추가)
- Modify: `init/src/power.zig` (`request` 추가, `onSignal`이 그것을 쓰게)

- [ ] **Step 1: 실패하는 검사를 먼저 넣는다**

`init/src/power_test.zig`의 마지막 줄(`power_test: SIGINT becomes a pending
restart action`을 찍는 `std.debug.print` 다음, 함수를 닫는 `}` **앞**)에 아래
블록을 넣는다.

```zig

    // 6. 시그널을 거치지 않고도 같은 자리에 요청이 선다.
    //
    //    전원 버튼이 쓰는 경로다(design 결정 9). 버튼을 보고 곧바로
    //    shutdown()을 부르지 않는 이유는 종료가 시작되는 자리가 한 곳이어야
    //    나중에 읽히기 때문이고, 이 검사가 그 한 곳을 붙박는다. take()의
    //    소비 규칙도 시그널 경로와 같아야 한다.
    power.request(.power_off);

    const from_button = power.take() orelse {
        std.debug.print("FAIL: request() did not leave a pending action\n", .{});
        return error.RequestNotObserved;
    };
    if (from_button != .power_off) {
        std.debug.print("FAIL: request(power_off) recorded {s}\n", .{@tagName(from_button)});
        return error.WrongAction;
    }
    if (power.take() != null) {
        std.debug.print("FAIL: the requested action was not consumed by take()\n", .{});
        return error.ActionNotConsumed;
    }

    std.debug.print("power_test: a button press takes the same road as a signal\n", .{});
```

- [ ] **Step 2: 검사가 실패하는지 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test'
```

기대: **컴파일 에러.** `power.request`가 없다.

- [ ] **Step 3: `request`를 더하고 `onSignal`이 그것을 쓰게 한다**

`init/src/power.zig:25-32`의 아래 블록을 **지운다.**

```zig
fn onSignal(sig: linux.SIG) callconv(.c) void {
    const action: Action = switch (sig) {
        .TERM => .power_off,
        .INT => .restart,
        else => return,
    };
    @atomicStore(u8, &pending, @intFromEnum(action), .seq_cst);
}
```

그 자리에 아래 블록을 **넣는다.**

```zig
fn onSignal(sig: linux.SIG) callconv(.c) void {
    const action: Action = switch (sig) {
        .TERM => .power_off,
        .INT => .restart,
        else => return,
    };
    request(action);
}

/// 시그널이 아닌 경로에서 온 종료 요청을 **같은 자리에** 세운다
/// (design 결정 9). 전원 버튼을 본 감독 루프가 이것을 부른다.
///
/// 버튼을 보고 곧바로 shutdown()을 부르지 않는 이유는, 종료가 시작되는 자리가
/// 한 곳이어야 나중에 읽히기 때문이다. 시그널로 오든 버튼으로 오든 실제
/// 종료는 감독 루프 머리의 take()가 시작한다.
///
/// 하는 일이 원자적 저장 하나뿐이라 시그널 핸들러 안에서 불러도 안전하다 —
/// 그래서 onSignal이 이 함수를 그대로 쓴다.
pub fn request(action: Action) void {
    @atomicStore(u8, &pending, @intFromEnum(action), .seq_cst);
}
```

- [ ] **Step 4: 검사가 통과하는지 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build test'
```

기대: 아래 줄이 새로 찍히고 종료 코드가 0이다. 앞의 다섯 절도 그대로 통과해야
한다 — `request`를 거치게 바꾼 `onSignal`이 여전히 같은 답을 내는지가 그
다섯 줄로 확인된다.

```
power_test: a button press takes the same road as a signal
```

- [ ] **Step 5: 커밋**

```bash
git add init/src/power.zig init/src/power_test.zig
git commit -m "Let a button ask for shutdown at the same place a signal does"
```

---

## Task 4: PID 1이 버튼을 연다

여기서 처음 게스트를 띄운다. **감독 루프는 아직 안 건드린다** — fd를 열어만
두고 아무도 `poll`하지 않는 상태는 무해하다. 커널의 이벤트 큐가 차기만 하고
그것을 기다리는 코드가 없기 때문이다.

이 Task의 목적은 둘이다. 후보가 실물로 몇 개 열리는지 확인하는 것과, Task 7의
게이트가 grep할 문구를 확정하는 것.

**Files:**
- Modify: `init/src/devices.zig` (`devicePath` 헬퍼, `openPowerButtons` 추가)
- Modify: `init/src/main.zig` (버튼 열기 호출)

- [ ] **Step 1: 경로 조립을 헬퍼로 뺀다**

`init/src/devices.zig`의 `resolveKeyboard` 안에 있는 아래 아홉 줄을 **지운다.**

```zig
    // MAX_PATH가 64인데 가장 긴 결과가 "/dev/input/event31"(18자)이라 이
    // bufPrint는 실패할 수 없다. 일어날 수 없는 실패를 처리하는 코드는
    // 아무도 실행하지 않으므로 unreachable로 적는다.
    const text = std.fmt.bufPrint(
        out.buf[0 .. out.buf.len - 1],
        "/dev/input/event{d}",
        .{n},
    ) catch unreachable;
    out.buf[text.len] = 0;
    out.len = text.len;
```

그 자리에 아래 **한 줄을 넣는다.**

```zig
    devicePath(n, out);
```

그리고 `resolveKeyboard` **앞**(`Path` 구조체 정의 다음, `readFile` 앞)에
헬퍼를 넣는다.

```zig

/// `/dev/input/event{n}`을 out에 적는다.
///
/// MAX_PATH가 64인데 가장 긴 결과가 "/dev/input/event31"(18자)이라 이
/// bufPrint는 실패할 수 없다. 일어날 수 없는 실패를 처리하는 코드는 아무도
/// 실행하지 않으므로 unreachable로 적는다.
fn devicePath(n: u8, out: *Path) void {
    const text = std.fmt.bufPrint(
        out.buf[0 .. out.buf.len - 1],
        "/dev/input/event{d}",
        .{n},
    ) catch unreachable;
    out.buf[text.len] = 0;
    out.len = text.len;
}
```

- [ ] **Step 2: `openPowerButtons`를 더한다**

`init/src/devices.zig`의 **맨 끝**(`drainButton` 다음)에 아래 블록을 넣는다.

```zig

/// 전원 버튼 후보를 전부 열고 fd를 out에 채운 뒤 그 개수를 돌려준다.
///
/// **여는 것은 진짜 /dev/input이다.** 탐색(sys_root)만 주입받고 여는 쪽은
/// 고정인 이유는, 이 함수가 하는 일의 절반이 open(2)이라 호스트 검사에서
/// 시험할 대상이 아니기 때문이다. 검사가 보는 것은 findPowerButtons까지다.
///
/// 하나도 못 찾아도 **부팅을 막지 않는다**(design 결정 6). 그때는 0을
/// 돌려주고, 감독 루프의 poll은 fd 0개짜리가 되어 그냥 1초 sleep이 된다 —
/// 폴백이 따로 필요 없는 구조다.
///
/// O_NONBLOCK으로 여는 이유는 drainButton에 적었다. 비었을 때의 read가
/// EAGAIN으로 돌아와야 다 읽었다는 것을 알 수 있다.
pub fn openPowerButtons(sys_root: []const u8, out: []i32) usize {
    var candidates: [MAX_BUTTONS]u8 = undefined;
    const n = findPowerButtons(sys_root, &candidates);
    if (n == 0) {
        // device/check.sh가 이 줄이 **없음**을 요구한다. 탐색기가 조용히
        // 실패하면 버튼은 안 먹는데 부팅은 멀쩡해 보이기 때문이다.
        std.debug.print("tars-init: no power button found under {s}\n", .{sys_root});
        return 0;
    }

    var opened: usize = 0;
    var i: usize = 0;
    while (i < n and opened < out.len) : (i += 1) {
        var path = Path{};
        devicePath(candidates[i], &path);

        const rc = linux.open(path.cstr(), .{ .ACCMODE = .RDONLY, .NONBLOCK = true }, 0);
        if (failed(rc)) |e| {
            std.debug.print("tars-init: could not open {s} (errno {d})\n", .{
                path.slice(), @intFromEnum(e),
            });
            continue;
        }
        out[opened] = @intCast(rc);
        opened += 1;

        // 이름은 판정에 쓰지 않고 로그에만 쓴다. resolveKeyboard와 같은
        // 이유다 — 사람이 로그를 읽을 때 "왜 이것을 열었나"를 알 수 있어야
        // 한다.
        var name_buf: [MAX_NAME]u8 = undefined;
        const raw = readAttr(sys_root, candidates[i], "name", &name_buf) orelse "";
        const name = std.mem.trim(u8, raw, " \t\r\n");

        // device/check.sh가 이 줄의 앞부분을 grep한다. 고치면 게이트도 함께
        // 고쳐야 한다(HANDOFF의 "로그 문구는 두 곳에 중복된다").
        std.debug.print("tars-init: power button {s} ({s})\n", .{ path.slice(), name });
    }

    std.debug.print("tars-init: watching {d} power button(s)\n", .{opened});
    return opened;
}
```

- [ ] **Step 3: PID 1이 그것을 부르게 한다**

`init/src/main.zig`의 아래 두 줄

```zig
    var keyboard_path = devices.Path{};
    devices.resolveKeyboard(devices.SYS_INPUT, &keyboard_path);
```

**다음**에 아래 블록을 넣는다.

```zig

    // 전원 버튼은 PID 1이 직접 연다(design 결정 7). terminal이 읽는 안은
    // 물렸다 — 자식이 전부 포기 상태여도 버튼은 살아 있어야 하고, 하필 다
    // 망가졌을 때 눌러야 하는 것이 전원 버튼이기 때문이다. BF 체인처럼
    // /dev/dri/card0이 없어 감독자가 terminal을 포기한 상태가 정확히 그
    // 경우다.
    //
    // keyboard_path와 마찬가지로 이 배열은 main()의 스택에 살고, supervise()가
    // 영영 반환하지 않으므로 프로세스 수명 내내 유효하다.
    var button_fds: [devices.MAX_BUTTONS]i32 = undefined;
    const button_count = devices.openPowerButtons(devices.SYS_INPUT, &button_fds);
    // Task 5가 이 값을 supervise에 넘기면서 이 한 줄을 지운다. 지금은 열어만
    // 두는 상태이고, 아무도 poll하지 않으므로 무해하다 — 커널의 이벤트 큐가
    // 차기만 한다.
    _ = button_count;
```

`_ = button_count;`가 필요한 이유는 Zig가 쓰이지 않은 지역 변수를 **에러로**
막기 때문이다. 이 한 줄이 Task 4를 그 자체로 빌드되는 상태로 만들고, 그래서
아래 Step 5에서 게스트를 띄워 볼 수 있다.

- [ ] **Step 4: 빌드가 되는지 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build 2>&1 | tail -n 20'
```

기대: 아무 출력 없이 성공한다. 에러가 나오면 멈추고 그대로 알려 줄 것.

- [ ] **Step 5: 게스트를 띄워 로그를 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  (cd kernel && ./build.sh) >/dev/null 2>&1 &&
  (cd init && zig build) &&
  (cd terminal && ./prepare.sh) >/dev/null 2>&1 &&
  (cd kernel && ./make_initrd.sh) >/dev/null 2>&1 &&
  mkdir -p out &&
  timeout 20 qemu-system-x86_64 \
    -kernel kernel/build/arch/x86/boot/bzImage \
    -initrd kernel/initrd.cpio \
    -append "console=ttyS0" \
    -vga none -device virtio-gpu-pci -display none \
    -serial file:/workspace/out/hd-m2-observe.log \
    -monitor none -no-reboot
  true'
```

기대: 20초 뒤 조용히 끝난다. `timeout`이 QEMU를 끊는 것이 정상이다.

- [ ] **Step 6: 무엇이 열렸는지 읽는다**

```bash
rg -n "input:|ACPI: button|keyboard device|power button|watching|no power button" \
  out/hd-m2-observe.log
```

기대: 아래가 보인다. **출력을 그대로 알려 줄 것.**

```
input: Power Button as /devices/LNXSYSTM:00/LNXPWRBN:00/input/input0
ACPI: button: Power Button [PWRF]
input: AT Translated Set 2 keyboard as /devices/platform/i8042/serio0/input/input1
tars-init: keyboard device /dev/input/event1 (AT Translated Set 2 keyboard)
tars-init: power button /dev/input/event0 (Power Button)
tars-init: watching 1 power button(s)
```

Claude가 다음 셋을 확인한다.

1. **`watching`의 개수가 1인가.** 2가 나오면 키보드가 후보에 들어온 것이므로
   이번에 정하는 것 1번이 안 먹은 것이다 — 멈추고 `event1`도 함께 열렸는지
   위의 `power button` 줄로 확인한다.
2. **`no power button found`가 없는가.** 있으면 탐색이 실패한 것이다.
3. **키보드는 여전히 `event1`인가.** HD-M1이 실측한 배치가 유지되어야 한다.

**이 개수가 Task 7의 게이트 검사 문구를 확정한다.**

**실측 결과(2026-08-22):** 예상 그대로였다. `event0`이 `Power Button`,
`event1`이 AT 키보드, `watching 1 power button(s)`. `terminal: opened
/dev/input/event1`도 같은 번호다. `could not open`은 없었고, `failed to mount
ext2 at /config (errno 2)`만 나왔는데 이 부팅에 `-drive`를 안 붙였기 때문이라
정상 경로다. **키보드가 `KEY_POWER`를 갖고 있는데도 개수가 1인 것이 이번에
정하는 것 1번의 실물 확인이다.**

- [ ] **Step 7: 커밋**

```bash
git add init/src/devices.zig init/src/main.zig
git commit -m "Open every power button PID 1 can find"
```

---

## Task 5: 감독 루프를 poll 구조로 바꾼다

**이 milestone에서 가장 민감한 편집이다.** `waitpid` 블로킹이 사라지고 그
자리에 `poll`이 들어간다.

바뀌는 것은 셋이다.

1. `poll(버튼 fd들, 1000ms)`이 유일하게 잠드는 자리가 된다.
2. `waitpid`가 `WNOHANG`이 되어 거둘 것을 전부 거두는 안쪽 루프가 된다.
3. `sleepOneSecond()` 호출 셋이 사라진다 — backoff를 `poll` 타임아웃이 준다
   (이번에 정하는 것 2번).

**바뀌지 않아야 하는 것도 셋이다.**

1. **루프 머리에서 `power.take()`를 먼저 본다.** 순서가 뒤집히면 방금 SIGTERM으로
   죽인 셸을 이 루프가 되살린다.
2. **`EINTR`이 루프 머리로 돌아간다.** `SA_RESTART`를 끈 것이 살아 있는 근거가
   이 분기다(`power.zig:46`).
3. **`shutdown`은 여전히 `noreturn`이다.** 돌아갈 길을 타입으로 막아 둔 것을
   그대로 둔다.

**Files:**
- Modify: `init/src/main.zig:192-201`(`sleepOneSecond` 삭제),
  `:242-314`(`supervise` 교체), `:388`(호출 자리)

**이 편집은 `/tmp` 경로로 한다.** Claude가 `/tmp/main.zig`를 만들고, 사용자가
`diff`로 대조한 뒤 `cp`로 넣는다.

- [ ] **Step 1: `sleepOneSecond`를 지운다**

`init/src/main.zig:198-201`의 아래 네 줄을 **지운다.**

```zig
fn sleepOneSecond() void {
    const req = linux.timespec{ .sec = 1, .nsec = 0 };
    _ = linux.nanosleep(&req, null);
}
```

감독 루프가 유일한 호출자였고, 그 셋이 전부 `poll` 타임아웃으로 대체된다.

- [ ] **Step 2: `supervise`를 통째로 바꾼다**

`init/src/main.zig`의 `supervise` 함수 전체(`/// PID 1의 본체.` 주석 줄부터
함수를 닫는 `}`까지)를 **지우고** 아래로 바꾼다.

```zig
/// 감독 루프가 한 바퀴에 잠드는 시간. 이 값이 세 가지를 동시에 정한다.
///
///   1. 전원 버튼을 눌렀을 때 최대 지각 — 사람이 못 느낀다.
///   2. 자식이 죽고 나서 다시 뜰 때까지의 backoff — 예전 sleepOneSecond()가
///      하던 일을 이제 이 타임아웃이 한다.
///   3. SIGCHLD 경합의 창 — waitpid(WNOHANG)이 "없다"를 답한 뒤 poll이 잠들기
///      전까지의 틈에 자식이 죽으면 그 죽음을 알려 줄 것이 아무것도 없다.
///      SIGCHLD 핸들러를 새로 달면 그 틈이 닫히지만, 그러면 power.zig의
///      "signal handlers installed (TERM, INT)" 로그와 그것을 grep하는
///      게이트까지 함께 흔들린다(design 결정 8).
const POLL_TIMEOUT_MS: i32 = 1000;

/// PID 1의 본체. **절대 반환하지 않는다** — 반환하면 커널이 패닉한다.
///
/// buttons가 비어 있어도 이 구조는 그대로 성립한다. fd 0개에 1초 타임아웃인
/// poll은 그냥 sleep이고, 그것이 design 결정 6의 폴백을 자연스럽게 받쳐 준다.
fn supervise(
    children: []Child,
    buttons: []const i32,
    envp: [*:null]const ?[*:0]const u8,
) noreturn {
    // poll에 넘길 배열. 버튼 fd는 부팅 때 한 번 정해지고 변하지 않으므로
    // 루프 밖에서 한 번만 채운다. revents만 커널이 매 호출 덮어쓴다.
    var fds: [devices.MAX_BUTTONS]linux.pollfd = undefined;
    for (buttons, 0..) |fd, i| {
        fds[i] = .{ .fd = fd, .events = linux.POLL.IN, .revents = 0 };
    }
    const nfds: linux.nfds_t = buttons.len;

    while (true) {
        // 자식을 다시 띄우기 **전에** 본다. 순서가 뒤집히면 방금 SIGTERM으로
        // 죽인 셸을 이 루프가 되살린다. 시그널로 왔든 버튼으로 왔든 종료가
        // 시작되는 자리는 여기 하나다(design 결정 9).
        if (power.take()) |action| power.shutdown(action);

        for (children) |*c| {
            if (c.pid < 0 and !c.given_up) start(c, envp);
        }

        // ── 거둘 것을 전부 거둔다 ────────────────────────────────────
        //
        // 이것이 poll보다 **앞**인 것이 backoff를 만든다. 자식이 죽으면 이
        // 바퀴에서 거두고 곧바로 아래 poll에서 1초를 자므로, 재시작은 다음
        // 바퀴 머리에서 일어난다. 예전 코드의 sleepOneSecond()가 하던 일을
        // 순서 하나가 대신한다.
        while (true) {
            var status: u32 = 0;
            const rc = linux.waitpid(-1, &status, linux.W.NOHANG);
            if (failed(rc)) |e| {
                if (e == .INTR) continue;
                // ECHILD는 자식이 하나도 없다는 뜻이고, 감독 대상이 전부
                // 포기 상태일 때의 정상 경로다.
                if (e != .CHILD) {
                    std.debug.print("tars-init: waitpid failed (errno {d})\n", .{
                        @intFromEnum(e),
                    });
                }
                break;
            }
            // 0은 "살아 있고 아직 안 죽었다"이다. 더 거둘 것이 없다.
            if (rc == 0) break;

            const pid: linux.pid_t = @intCast(rc);

            // -1은 "아무 자식이나"라서 내 자식뿐 아니라 부모를 잃고 PID 1에
            // 재부모화된 프로세스까지 함께 거둔다. 그것이 PID 1의 의무다.
            const c = find(children, pid) orelse {
                std.debug.print("tars-init: reaped orphan pid {d}\n", .{pid});
                continue;
            };

            const lived = monotonicSeconds() - c.started_at;
            c.pid = -1;

            if (linux.W.IFEXITED(status)) {
                std.debug.print("tars-init: {s} exited (pid {d}, status {d}, lived {d}s)\n", .{
                    c.kind.name(), pid, linux.W.EXITSTATUS(status), lived,
                });
            } else {
                std.debug.print("tars-init: {s} killed (pid {d}, signal {d}, lived {d}s)\n", .{
                    c.kind.name(), pid, @intFromEnum(linux.W.TERMSIG(status)), lived,
                });
            }

            if (lived < FAST_EXIT_SECONDS) {
                c.fast_restarts += 1;
            } else {
                c.fast_restarts = 0;
            }

            if (c.fast_restarts >= MAX_FAST_RESTARTS) {
                c.given_up = true;
                std.debug.print("tars-init: giving up on {s} after {d} fast exits\n", .{
                    c.kind.name(), c.fast_restarts,
                });
                continue;
            }

            // "1s"가 여전히 참인 이유는 아래 poll이 그만큼 자기 때문이다.
            // terminal/check.sh:178이 이 문구를 진단 목록에 갖고 있다.
            std.debug.print("tars-init: restarting {s} in 1s\n", .{c.kind.name()});
        }

        // ── 유일하게 잠드는 자리 ─────────────────────────────────────
        //
        // EINTR로 깨어나 루프 머리로 돌아가는 것이 시그널 경로의 전부다.
        // power.zig가 SA_RESTART를 켜지 않는 이유가 이 한 줄이며, 켜면
        // 커널이 이 poll을 안에서 재시작해버려 플래그를 세워도 영영 머리로
        // 못 돌아온다(PM-M0이 milestone 하나를 써서 얻은 자리다).
        const ready = linux.poll(&fds, nfds, POLL_TIMEOUT_MS);
        if (failed(ready)) |e| {
            if (e != .INTR) {
                std.debug.print("tars-init: poll failed (errno {d})\n", .{
                    @intFromEnum(e),
                });
            }
            continue;
        }
        if (ready == 0) continue; // 타임아웃. 흔한 경로다.

        for (fds[0..buttons.len]) |*p| {
            if (p.revents == 0) continue;

            // POLLIN이 아니라 POLLERR/POLLHUP으로 깨어났어도 일단 읽어 본다.
            // 읽지 않고 넘어가면 그 revents가 매 poll마다 다시 서서 PID 1이
            // CPU를 태우는 바쁜 루프가 되기 때문이다.
            if (devices.drainButton(p.fd)) {
                // device/check.sh가 이 줄을 grep한다.
                std.debug.print("tars-init: power button pressed\n", .{});
                power.request(.power_off);
            }

            // 읽어도 해결되지 않는 종류로 깨어났으면 이 fd를 목록에서 뺀다.
            // fd를 음수로 두면 커널이 그 자리를 통째로 건너뛴다(POSIX). 이것이
            // 없으면 장치가 사라졌을 때 read가 계속 실패하고 revents가 계속
            // 서서 바쁜 루프가 된다.
            //
            // **핫플러그를 지원하는 것이 아니다**(design 비목표). 장치가
            // 빠졌을 때 PID 1이 CPU를 태우지 않게 하는 것뿐이고, 그러고 나면
            // 버튼 없이 도는 상태가 된다 — 결정 6이 이미 허용한 상태다.
            const broken = linux.POLL.ERR | linux.POLL.HUP | linux.POLL.NVAL;
            if (p.revents & broken != 0) {
                std.debug.print("tars-init: power button fd {d} went away (revents {d})\n", .{
                    p.fd, p.revents,
                });
                p.fd = -1;
            }
        }
    }
}
```

- [ ] **Step 3: 호출 자리를 고친다**

`init/src/main.zig`에서 Task 4가 넣은 아래 **네 줄을 지운다.**

```zig
    // Task 5가 이 값을 supervise에 넘기면서 이 한 줄을 지운다. 지금은 열어만
    // 두는 상태이고, 아무도 poll하지 않으므로 무해하다 — 커널의 이벤트 큐가
    // 차기만 한다.
    _ = button_count;
```

그리고 파일의 마지막 줄

```zig
    supervise(&children, envp);
```

를 이것으로 바꾼다.

```zig
    supervise(&children, button_fds[0..button_count], envp);
```

- [ ] **Step 4: 빌드하고 호스트 검사를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build && zig build test'
```

기대: 빌드 성공, 그리고 호스트 검사 셋이 전부 통과한다. 이 검사들은 감독
루프를 보지 않으므로 **여기서 통과한다고 루프가 옳다는 뜻은 아니다** —
그것은 Task 6이 본다.

- [ ] **Step 5: 커밋**

```bash
git add init/src/main.zig
git commit -m "Wait on the power button and the children at the same time"
```

---

## Task 6: 기존 다섯 체인이 그대로 통과하는가

**이 milestone에서 가장 그럴듯한 실패는 "새 것이 되는데 옛 것이 깨지는
것"이다.** Task 5가 바꾼 코드를 다섯 체인 전부가 딛고 서 있다.

**Files:**
- (없음. 검증만 한다.)

- [ ] **Step 1: 감독 루프에 가장 민감한 두 체인을 먼저 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'bash boot/check.sh && bash power/check.sh'
```

기대: 둘 다 `PASS`. 이 둘을 고른 이유가 있다.

**BF 체인(`boot/check.sh:92`)은 재시작 개수를 정확히 요구한다.**
`started terminal`이 정확히 3회여야 하고, 그 뒤에 `giving up`이 나와야 한다.
GPU가 없어 `/terminal`이 매번 죽는 체인이라 backoff 구조를 정면으로 밟는다.
`poll` 타임아웃이 backoff를 제대로 대신하지 못하면 여기서 개수가 어긋난다.

**PM 체인(`power/check.sh:213`)은 종료 중 되살리기를 금지한다.**
`started console shell`이 정확히 1회여야 한다. 루프 머리의 `power.take()`가
`start()`보다 앞이라는 성질이 깨지면 여기가 잡는다. 부팅 2는 `EINTR` 경로
전체(`ctrl-alt-delete` → SIGINT → 재시작)를 본다 — `SA_RESTART`를 끈 것이
`poll`에서도 유효한지가 이 부팅으로 확인된다.

실패하면 각 스크립트가 찍는 마커 목록과 마지막 60줄을 그대로 알려 줄 것.

- [ ] **Step 2: 나머지 셋을 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'bash terminal/check.sh && bash config/check.sh && bash input/check.sh'
```

기대: 셋 다 `PASS`. TF 체인은 셸을 죽여 재시작을 보는 경로
(`terminal/check.sh:163`)를 갖고 있어 자식 수거를 확인해 준다. 재시작까지
60초를 기다리므로 `poll` 타임아웃 1초가 더해져도 여유가 충분하다.

이 Task는 커밋할 것을 만들지 않는다.

---

## Task 7: 새 체인 `device/check.sh`

이 milestone의 완료선이다. monitor에서 `system_powerdown`을 보내 게스트가
스스로 꺼지는 것을 본다.

**Files:**
- Create: `device/check.sh`

**이 파일은 `/tmp` 경로로 넣는다.** Claude가 `/tmp/device-check.sh`를 만들고,
사용자가 `mkdir -p device && cp /tmp/device-check.sh device/check.sh &&
chmod +x device/check.sh`로 제자리에 넣는다.

**Task 4 Step 6의 실측으로 `watching` 개수를 확정한 뒤에 쓴다.** 아래 전문은
개수가 1인 경우다.

- [ ] **Step 1: 파일을 만든다**

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# HD 체인 — 하드웨어 탐색과 전원 버튼.
#
# 이 게이트가 증명하는 사슬 전체:
#   QEMU monitor의 system_powerdown → QEMU가 ACPI 전원 버튼 이벤트를 만든다
#   → 커널의 acpi/button.c가 그것을 evdev 장치에 KEY_POWER로 올린다
#   → PID 1이 부팅 때 열어 둔 fd의 poll이 깨어난다
#   → init/src/devices.zig의 drainButton이 누름(value 1)을 가려낸다
#   → power.request(.power_off)가 시그널과 같은 플래그를 세운다
#   → 감독 루프 머리의 take()가 종료 순서를 시작한다
#   → reboot(POWER_OFF) → 커널이 ACPI로 전원을 끊는다 → QEMU가 사라진다
#
# PM 체인과 나란히 놓고 보면 이 체인의 자리가 분명해진다. PM은 **셸에서
# 시작하는** 종료를 보고(kill -TERM 1), 이쪽은 **바깥에서 눌린 버튼**으로
# 시작하는 종료를 본다. 마지막 절반은 같지만 첫 절반이 완전히 다르고, 그
# 첫 절반이 HD-M2가 만든 전부다.
#
# 디스크를 물지 않는다. 전원 버튼은 설정과 무관하고, 이 체인은 게스트에 한
# 글자도 타이핑하지 않는다 — 종료 명령이 monitor에서 오기 때문이다. 그래서
# 다른 체인보다 빠르다(회차당 부팅 1회, 타이핑 0회).
#
# -no-reboot을 다는 이유는 power/check.sh 부팅 1과 같다. 다만 그 옵션 때문에
# "QEMU가 사라졌다"가 리셋으로도 성립할 수 있으므로, 아래 음성 검사가
# Restarting system이 없음을 요구해서 둘을 가른다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

# 호스트에서 도는 순수 로직 검사 셋(config 파서, 시그널 플래그, 장치 탐색).
# HD-M2가 여기에 얹은 것이 둘이다 — "키보드는 전원 버튼이 아니다"와 "누름만
# 종료가 된다". 부팅 20초를 쓰기 전에 0.1초로 잡을 수 있는 실패를 먼저 잡는다.
if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../terminal && zig build test); then
  echo "FAIL: input_test failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 45455=TF, 45456=CP, 45457=IP, 45458=PM. 겹치지 않는 번호를 쓰는 이유는 죽다
# 만 QEMU가 남았을 때 엉뚱한 게스트에 명령을 보내지 않기 위해서다.
MONITOR_PORT=45459

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

report_failure() {
  echo "FAIL: $1"
  echo "--- markers ---"
  local marker
  for marker in \
    "ACPI: button: Power Button" \
    "tars-init: keyboard device /dev/input/event" \
    "tars-init: power button /dev/input/event" \
    "tars-init: watching 1 power button" \
    "terminal: screen>" \
    "tars-init: power button pressed" \
    "tars-init: shutdown requested (action power_off)" \
    "tars-init: sent SIGTERM to every process" \
    "tars-init: filesystems synced" \
    "tars-init: calling reboot(POWER_OFF)" \
    "reboot: Power down"; do
    if grep -q "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- last 60 lines ---"
  tail -n 60 "$LOG"
  exit 1
}

qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

# "terminal: screen>" 첫 줄이 곧 부팅이 끝까지 갔다는 신호다. 버튼을 누르기
# 전에 이것을 기다리는 이유는, 감독 루프가 자식을 띄우는 도중에 종료 요청이
# 오는 경우를 이 체인이 다루지 않기 때문이다 — 그 경합은 별도로 볼 일이다.
READY=0
for _ in $(seq 1 120); do
  if grep -q "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "terminal never rendered a prompt"
sleep 1

# ── 탐색 검사 ───────────────────────────────────────────────────────────
#
# 버튼을 누르기 **전에** 본다. 여기서 실패하면 아래의 종료가 왜 안 됐는지를
# 따로 물을 필요가 없다.

# 커널 쪽 전제. ACPI가 꺼지면 여기가 먼저 실패한다.
grep -q "ACPI: button: Power Button" "$LOG" \
  || report_failure "the kernel did not register an ACPI power button"

# 키보드는 여전히 성질로 찾아야 한다. 번호를 요구하지 않는 이유는 탐색기를
# 만든 이유와 같다(design 결정 2).
grep -q "tars-init: keyboard device /dev/input/event" "$LOG" \
  || report_failure "init did not discover a keyboard device"
grep -q "tars-init: no keyboard found" "$LOG" \
  && report_failure "init fell back to event0 instead of discovering a keyboard"

# 전원 버튼도 마찬가지다. 이 음성 검사가 없으면 탐색이 조용히 실패해도
# 부팅은 멀쩡해 보인다 — 그리고 아래 종료가 실패하는 이유를 알 수 없다.
grep -q "tars-init: power button /dev/input/event" "$LOG" \
  || report_failure "init did not open any power button"
grep -q "tars-init: no power button found" "$LOG" \
  && report_failure "init found no power button at all"

# ★ 개수를 요구하는 것이 이 체인에서 가장 값진 한 줄이다.
#
# QEMU의 AT 키보드도 KEY_POWER를 갖고 있다(devices_test의 실측 비트맵 1번
# 워드 0xfeffffdfffefffff의 52번 비트). looksLikePowerButton이 키보드를
# 제외하지 않으면 여기가 2가 되고, 그러면 PID 1이 글자 하나마다 깨어나는
# 상태로 조용히 굴러간다 — 종료는 여전히 되므로 개수를 안 보면 아무도
# 모른다.
grep -q "tars-init: watching 1 power button" "$LOG" \
  || report_failure "init is not watching exactly one power button (did the keyboard sneak in?)"

echo "init found the keyboard and exactly one power button"

# ── 버튼을 누른다 ───────────────────────────────────────────────────────

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor"

# QEMU의 system_powerdown은 ACPI 전원 버튼을 누른 것과 같다. sendkey와 달리
# 키보드를 거치지 않으므로, 이 체인은 IP 체인의 번역 경로를 하나도 밟지
# 않는다 — 여기서 증명되는 것은 순수하게 버튼 경로다.
echo "=== sending system_powerdown to the guest ==="
echo "system_powerdown" >&3
sleep 0.3

exec 3<&-
exec 3>&-

# 로그의 문자열이 아니라 프로세스의 존재를 본다. HD-M1이 power 체인에 세운
# 것과 같은 통과 조건이다.
GONE=0
for _ in $(seq 1 30); do
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then GONE=1; break; fi
  sleep 1
done

[ "$GONE" = "1" ] \
  || report_failure "the machine never switched itself off after the power button"

# 여기서 거둬야 좀비가 남지 않고, EXIT trap의 cleanup이 이미 없는 PID를
# 건드리지 않는다. 아래 검사들은 완성된 로그를 읽는다.
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""

# ── 어떻게 꺼졌는가 ─────────────────────────────────────────────────────
#
# 위의 GONE 하나만 보면 기계가 꺼진 것은 알 수 있지만 **왜** 꺼졌는지는 알 수
# 없다. 특히 첫 줄이 중요하다 — 그것이 없으면 버튼이 아니라 다른 경로로
# 꺼졌다는 뜻이고, 이 체인이 존재할 이유가 사라진다.
for marker in \
  "tars-init: power button pressed" \
  "tars-init: shutdown requested (action power_off)" \
  "tars-init: sent SIGTERM to every process" \
  "tars-init: filesystems synced" \
  "tars-init: calling reboot(POWER_OFF)"; do
  grep -q "$marker" "$LOG" || report_failure "missing shutdown log line: ${marker}"
done

# 커널 쪽 증거(kernel/reboot.c:711).
grep -q "reboot: Power down" "$LOG" \
  || report_failure "the kernel never reported 'Power down'"

# 음성 검사 1 — PID 1이 죽어서 커널이 패닉한 것이 아니어야 한다.
if grep -q "Attempted to kill init" "$LOG"; then
  report_failure "the kernel panicked instead of shutting down cleanly"
fi

# 음성 검사 2 — POWER_OFF가 HALT로 강등되지 않았는가.
if grep -q "Power off not available: System halted instead" "$LOG"; then
  report_failure "the kernel demoted POWER_OFF to a halt; is CONFIG_ACPI still on?"
fi

# 음성 검사 3 — 꺼진 것이지 리셋된 것이 아니어야 한다. -no-reboot이 붙어
# 있어서 게스트가 리셋을 걸어도 QEMU는 사라지고, 그러면 위의 GONE이 엉뚱한
# 이유로 참이 된다.
if grep -q "Restarting system" "$LOG"; then
  report_failure "the guest reset the machine instead of powering it off"
fi

# 음성 검사 4 — 종료 중에 감독 루프가 자식을 되살리면 안 된다. poll 구조로
# 바꾸면서 루프 머리의 take()가 start()보다 앞이라는 성질이 깨지면 이 개수가
# 는다. PM 체인이 콘솔 셸로 보는 것을 이쪽은 terminal로 본다.
STARTED="$(grep -c "tars-init: started terminal" "$LOG" || true)"
if [ "$STARTED" != "1" ]; then
  report_failure "the supervisor started the terminal ${STARTED} times, want exactly 1"
fi

# 음성 검사 5 — poll 구조가 자식을 잘못 포기하면 안 된다. 이 체인에는 GPU가
# 있으므로 terminal은 살아 있어야 한다.
if grep -q "tars-init: giving up on" "$LOG"; then
  report_failure "the supervisor gave up on a child that should have stayed alive"
fi

echo "--- init log ---"
grep 'tars-init:' "$LOG" || true

echo "HD-M2 PASS: the guest switched itself off because someone pressed the power button"
```

- [ ] **Step 2: 문법을 먼저 본다**

```bash
bash -n device/check.sh && echo "SYNTAX OK"
ls -l device/check.sh
```

기대: `SYNTAX OK`, 그리고 실행 권한(`-rwxr-xr-x`)이 붙어 있다.

- [ ] **Step 3: 새 체인을 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash device/check.sh
```

기대: 마지막 두 줄이 이렇다.

```
init found the keyboard and exactly one power button
HD-M2 PASS: the guest switched itself off because someone pressed the power button
```

실패하면 `report_failure`가 찍는 마커 목록과 마지막 60줄을 그대로 알려 줄 것.
**특히 `tars-init: power button pressed`가 `MISSING`인지가 갈림길이다** —
있으면 그 뒤의 종료 순서 문제이고, 없으면 `poll`이나 `drainButton`의 문제다.

- [ ] **Step 4: 커밋**

```bash
git add device/check.sh
git commit -m "Prove the machine switches off when the power button is pressed"
```

---

## Task 8: 루트 게이트에 체인을 넣고 3/3

**Files:**
- Modify: `check.sh` (체인 추가, 주석)

- [ ] **Step 1: 체인을 등록한다**

`check.sh:82`의

```bash
run_chain "PM-M1" ./power/check.sh
```

**다음**에 아래 한 줄을 넣는다.

```bash
run_chain "HD-M2" ./device/check.sh
```

- [ ] **Step 2: 주석을 더한다**

같은 파일에서 PM 체인 설명이 끝나는 자리, 즉

```bash
# BF 체인도 PM-M1부터 몇 초 길어진다. 배너 뒤에 감독 루프가 /terminal을
# 포기하는 것까지 기다리기 때문이다 — 재시작 backoff가 1초라 3초 남짓이다.
```

**다음**에 아래 블록을 넣는다.

```bash
#
# HD 체인은 하드웨어 탐색과 전원 버튼을 본다. 다섯 체인 중 유일하게 게스트에
# 한 글자도 타이핑하지 않는다 — 종료 명령이 QEMU monitor의 system_powerdown
# 으로 오기 때문이다. 디스크도 물지 않는다(전원 버튼은 설정과 무관하다).
# 회차당 부팅 1회라 총 부팅 횟수는 24회에서 27회가 된다.
#
# PM 체인과 나란히 놓으면 자리가 분명해진다. PM은 셸에서 시작하는 종료를,
# HD는 바깥에서 눌린 버튼으로 시작하는 종료를 본다. 마지막 절반은 같고 첫
# 절반이 다르다.
```

- [ ] **Step 3: 문법을 본다**

```bash
bash -n check.sh && echo "SYNTAX OK"
rg -n "^run_chain" check.sh
```

기대: `SYNTAX OK`, 그리고 `run_chain` 여섯 줄(BF·TF·CP·IP·PM·HD)이 나온다.

- [ ] **Step 4: 루트 게이트를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'time bash check.sh'
```

기대: 마지막 줄이

```
TARS check PASS: all chains 3/3 consecutive runs succeeded
```

그리고 `real` 값이 나온다. **직전 실측은 2026-08-21의 31분 30초다.** HD 체인이
회차당 더하는 것은 커널 빌드 한 번(약 53초)과 나머지 빌드·부팅이고, 타이핑이
없어 다른 체인보다 짧다. 기존 다섯 체인의 평균이 회차당 약 2분 6초이므로
**3분에서 5분 사이가 예상 범위**(34분 30초 ~ 36분 30초)다. 그보다 훨씬 크면
어딘가에서 기다리고 있다는 뜻이므로 멈추고 해석한다 — 가장 그럴듯한 후보는
`poll` 타임아웃이 부팅마다 몇 바퀴씩 붙는 것이다.

**시간이 견딜 만한지의 판단은 이 milestone 안에서 `check.sh`를 고치는 것으로
이어지지 않는다.** design 위험 1번이 정한 대로 `clean()` 정책 변경은 별도로
논의할 일이다. 판단 결과는 Task 9에서 `HANDOFF.md`에 적는다.

**실측 결과(2026-08-22):** `real 36m34.135s`(`user 119m23s`, `sys 33m50s`).
여섯 체인 전부 3/3이고 `FAIL`이 하나도 없었다. 증가분은 **5분 4초**로 예상
범위(3~5분)의 상단이다. HD 체인 한 회차가 1분 41초이고 다른 체인 평균은 2분
6초다 — 타이핑도 디스크도 없어서 짧다. 늘어난 시간의 대부분은 **커널 빌드 세
번**(53초 × 3 ≒ 2분 39초)이고, 부팅 세 번은 그에 비하면 작다. `clean()` 정책은
바꾸지 않았다.

- [ ] **Step 5: 커밋**

```bash
git add check.sh
git commit -m "Add the power button chain to the root gate"
```

---

## Task 9: 문서

**Files:**
- Modify: `docs/decisions/project_power_management.md`
- Modify: `docs/decisions/project_device_discovery.md`
- Modify: `docs/decisions/project_init_supervisor.md`
- Modify: `MEMORY.md` (한 줄 요약 갱신)
- Modify: `HANDOFF.md`

- [ ] **Step 1: 기억 파일 셋을 고친다**

내용은 Claude가 쓴다. 담을 것은 이렇다.

**`project_device_discovery.md`** — 탐색기가 이제 둘을 찾는다는 것과, 그중
**전원 버튼 판정에 "키보드는 아니다"가 들어간 이유**. 이것이 HD-M2가 알아낸
것 중 가장 옮겨 적을 값어치가 있는 사실이다: `KEY_POWER`가 키보드에도 서
있으므로 코드 하나만으로는 물리 버튼을 가려낼 수 없다. `watching N power
button(s)`의 개수를 게이트가 요구하는 이유도 함께 적는다.

**`project_init_supervisor.md`** — 감독 루프가 `poll` 구조가 됐다는 것.
`waitpid`가 `WNOHANG`이 되고 backoff를 `poll` 타임아웃이 대신한다는 것,
그리고 **`SA_RESTART`를 끈 것이 `poll`에서도 같은 이유로 필요하다**는 것.
지금 이 파일이 적고 있는 `POLLHUP` 사각지대 관련 서술도 다시 읽고 맞춘다.

**`project_power_management.md`** — 종료를 시작하는 경로가 셋이 됐다는 것
(SIGTERM · SIGINT · 전원 버튼)과, 셋이 전부 `power.zig`의 같은 플래그를
지난다는 것. `request()`가 그 자리다.

새 기억 파일을 따로 만들지는 판단한다. 위 셋에 나눠 담기는 분량으로 보이지만,
`poll` 구조 전환이 별도 파일이 될 만하다고 판단되면 만들고 `MEMORY.md`에 줄을
하나 더한다.

- [ ] **Step 2: HANDOFF 갱신**

담을 것.

- HD-M2가 끝났고 **Hardware Discovery 서브프로젝트 전체가 끝났다**는 것.
  다음 서브프로젝트는 아직 정하지 않았다는 것과, 후보(`HANDOFF.md`의 "나중
  후보")를 그대로 이월한다는 것
- Task 4 Step 6의 실측: 열린 전원 버튼의 개수와 장치 번호
- Task 8 Step 4의 실측: 루트 게이트 전체 시간(직전 31분 30초와 비교), 체인
  여섯 · 부팅 27회
- `clean()` 정책 논의가 필요한지의 판단
- 로그 문구 목록에 넷을 더한다: `power button /dev/input/event` ·
  `watching N power button(s)` · `no power button found`(없어야 한다) ·
  `power button pressed`
- 핵심 파일 목록 갱신: `init/src/main.zig`의 줄 번호가 전부 밀렸다.
  `supervise`의 `poll` 자리와 `POLL_TIMEOUT_MS`를 새로 가리킨다
- **이월 숙제는 그대로 남긴다** — `CONFIG_PRINTK_TIME`, `ACPI_EC`/
  `PNP_DEBUG_MESSAGES` 정리, `init`을 `ReleaseSafe`로, Zig 에러 트레이스,
  `terminal/sanity/`의 도구 둘. HD-M2가 손대지 않았다
- IP-M2가 남긴 것 넷도 그대로 이월한다

- [ ] **Step 3: 커밋**

```bash
git add docs MEMORY.md HANDOFF.md
git commit -m "Hand off with a machine that answers its own power button"
```

- [ ] **Step 4: push**

```bash
git rev-list --count origin/main..main
git push origin main
```

`rev-list`를 먼저 부르는 이유는 HD-M0의 HANDOFF가 "5개 앞서 있다"고 적어
두었는데 실제로는 이미 push되어 있었기 때문이다. 적어 둔 것을 믿지 말고 그때
센다.

---

## 위험과 대응

**1. `SA_RESTART`의 함정이 `poll`에서 재현된다.** `waitpid`가 그랬던 것처럼
`poll`도 `SA_RESTART`가 켜져 있으면 커널이 안에서 재시작한다. 지금
`power.zig:46`이 그것을 끄고 있으므로 구조는 그대로 유효하지만, 새 코드의
`if (e != .INTR)` 분기가 실수로 `continue` 대신 다른 것을 하면 같은 증상이
난다. Task 6 Step 1의 PM 체인 부팅 2(`ctrl-alt-delete` → SIGINT → 재시작)가
이것을 정면으로 본다.

**2. `poll`이 깨어났는데 안 읽으면 바쁜 루프가 된다.** `drainButton`이 fd를
비우는 것이 그 대응이고, Task 2의 검사가 "두 번째 `drainButton`은 false"를
요구해서 붙박는다. 읽어도 해결되지 않는 종류(`POLLERR`·`POLLHUP`·`POLLNVAL`)는
Task 5의 마지막 블록이 그 fd를 `-1`로 만들어 목록에서 뺀다. **우리 게이트는
CPU 사용률을 보지 않으므로 이 실패는 눈에 잘 안 띈다** — 로그가 이상하게
느려지는 것이 유일한 증상이고, 그래서 코드 쪽에서 미리 막아 둔다.

**3. backoff가 사라져 재시작이 폭주할 수 있다.** `sleepOneSecond()`를 지웠기
때문이다. 거두기를 `poll`보다 앞에 두는 순서가 그 대응이고(이번에 정하는 것
2번), BF 체인의 "정확히 3회"가 그것을 개수로 확인한다. 3회를 넘으면 backoff가
안 먹은 것이고, 3회 미만이면 `FAST_EXIT_SECONDS` 판정이 달라진 것이다 —
어느 쪽인지는 로그의 `lived Ns`가 말해 준다.

**4. 키보드가 전원 버튼 후보로 딸려 들어온다.** 이번에 정하는 것 1번이 그
대응이고, Task 1의 검사 둘과 Task 7의 `watching 1 power button` 검사가 이중으로
막는다. 후자가 중요한 이유는, 딸려 들어와도 **종료는 여전히 되기 때문에**
개수를 안 보면 아무도 모른다는 점이다.

**5. `input_event` 레이아웃을 손으로 적다가 틀린다.** libc를 안 링크하므로
`@cImport`가 확인해 주지 않는다(`project_zig_c_uapi_rule`). Task 2의
`@sizeOf(devices.Event) != 24` 검사가 그 대응이다. 크기가 맞아도 필드 순서가
틀릴 수는 있는데, 그 경우 Task 2의 나머지 검사들이 pipe로 흘려 넣은 이벤트를
잘못 읽어서 잡는다.

**6. 새 체인이 통과하는데 옛 체인이 깨진다.** 이 milestone에서 가장 그럴듯한
실패다. Task 6을 Task 7보다 앞에 둔 것이 그 대응이고, 특히 BF와 PM을 먼저
돌리는 것이 핵심이다.

**7. 부팅 도중에 버튼이 눌리는 경합.** 감독 루프가 자식을 띄우는 중에 종료
요청이 오면 어떻게 되는지를 이 체인은 보지 않는다(`terminal: screen>`를
기다린 뒤에 누른다). 구조상으로는 루프 머리의 `take()`가 `start()`보다 앞이라
안전하지만, 그 사이에 이미 `fork`된 자식은 `shutdown()`의 `kill(-1, TERM)`이
받는다. **이 경합을 게이트로 만들지 않는 것은 의도된 선택이다** — 타이밍에
의존하는 검사는 3회 반복 게이트에서 간헐 실패의 근원이 된다.
