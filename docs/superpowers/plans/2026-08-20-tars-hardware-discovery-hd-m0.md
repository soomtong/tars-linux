# TARS Hardware Discovery HD-M0 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 파일 작성과
> 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을 제시하고
> 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는 이 저장소에 적용하지 않는다.

**Goal:** 키보드를 **번호가 아니라 성질로** 찾는다. PID 1이 부팅 시점에
sysfs를 훑어 "완전한 키보드"인 evdev 장치를 고르고, 그 경로를 `argv[4]`로
`terminal`에 넘긴다. `terminal/src/main.zig:24`의
`const INPUT_DEVICE = "/dev/input/event0"`가 사라진다.

**Design doc:** `docs/superpowers/specs/2026-08-20-tars-hardware-discovery-design.md`
(결정 1·2·3·5·6과 결정 11의 HD-M0 항목이 이 milestone의 몫이다. 결정
4(전원 버튼 후보를 전부 연다)·7·8·9는 HD-M2, 결정 10은 HD-M1이다. design은
이미 승인되어 있으므로 다시 논의하지 않는다.)

**Tech Stack:** Zig 0.16.0(`std.os.linux`의 `open`/`read`, `std.fmt.bufPrint`,
`std.mem.tokenizeAny`), Docker(`tars-devcontainer`, arm64), QEMU

---

## 이 milestone의 합격 기준이 특이하다

**아무 일도 안 일어난 것처럼 보여야 한다.** 지금 게스트에서는 `event0`이 곧
AT 키보드이므로, 탐색기가 옳다면 결과가 예전 상수와 **똑같다.** 다섯 체인이
그대로 통과하고 로그가 한 줄 늘 뿐이다.

그래서 이 단계에서 게이트가 실제로 확인할 수 있는 것은 "탐색이 돌았다"까지다.
**탐색이 옳다는 증명은 HD-M1이 한다** — ACPI가 켜져 장치 번호가 밀렸는데도
TF·IP 체인이 통과하는 순간이 그 증명이다. 지금 할 일은 그때 증명될 물건을
정확하게 만들어 두는 것이고, 그 정확함은 호스트 검사가 대신 본다.

이 사정 때문에 Task 1·2가 이 plan의 무게중심이다.

## 왜 이 순서인가

```
Task 1   비트맵을 읽는 함수 둘 + 호스트 검사        ← 부팅 없이 도는 저울
  ↓      bitSet(뒤에서부터 센다) · looksLikeKeyboard
Task 2   가짜 sysfs 트리에서 장치를 고른다           ← 여전히 부팅 없이
  ↓      findKeyboard · resolveKeyboard(폴백 포함)
Task 3   PID 1이 찾고 terminal이 받는다              ← 첫 부팅
  ↓      argv가 넷에서 다섯으로, 상수가 사라진다
Task 4   게이트가 탐색 로그를 요구한다 + 루트 3/3
  ↓
Task 5   문서
```

**Task 1·2가 앞인 이유**는 PM-M0·PM-M1과 같다. 부팅 20초를 쓰기 전에 0.1초로
잡을 수 있는 실패를 먼저 잡는다. 이번에는 그 이유가 한층 더 강하다 —
**틀린 탐색기도 지금은 통과한다.** 비트맵을 거꾸로 읽든, `ev`를 안 보든,
`event0`이 어차피 답이면 부팅은 성공한다. 부팅으로는 이 milestone의 진짜
내용을 검사할 수 없다.

**Task 3이 Task 4보다 앞인 이유**는 로그 문구 때문이다. 게이트가 grep할
문자열은 실제로 찍힌 것을 보고 확정해야 한다. 코드에 적은 문구와 게이트가
찾는 문구가 어긋나는 사고가 이 저장소에 이미 있었다(`HANDOFF.md`의 "로그
문구는 두 곳에 중복된다").

## 이번에 정하는 것 다섯 (design doc이 안 정한 자리)

**1. 디렉터리를 훑지 않고 `event0`부터 `event31`까지 열어 본다.**

`/sys/class/input`을 열어 엔트리를 순회하는 것이 자연스러워 보이지만, init은
**libc도 힙도 없다.** `getdents64`를 직접 다루면 버퍼 관리와 가변 길이 레코드
파싱이 들어오는데, 그것은 이 milestone이 사려는 물건이 아니다. 장치 번호는
0부터 촘촘히 붙으므로 `open`을 서른두 번 시도하는 편이 훨씬 짧고 예측
가능하다. 없는 번호는 `ENOENT`로 즉시 돌아온다.

**2. 로그 문구를 여기서 확정한다.**

```
tars-init: keyboard device /dev/input/event0 (AT Translated Set 2 keyboard)
```

`terminal/check.sh`가 Task 4에서 이 앞부분을 grep한다. **이름은 판정에 쓰지
않고 로그에만 쓴다**(design 결정 2). 사람이 로그를 읽을 때 "왜 이걸 골랐나"를
알 수 있어야 하기 때문이다. 게이트도 이름까지 요구하지는 않는다 — 실
하드웨어에서 그 문자열이 달라지는 것이 정상이다.

못 찾았을 때는 그 앞에 한 줄이 더 붙는다.

```
tars-init: no keyboard found under /sys/class/input, falling back to event0
```

**3. 경로는 값으로 들고 `main()`의 스택에 산다.**

힙이 없으므로 탐색 결과를 담을 곳이 필요한데, `main()`의 스택이 답이다.
`supervise()`가 **영영 반환하지 않는다**(`noreturn`)는 성질 덕분에 그
스택 프레임은 프로세스 수명 내내 살아 있고, `argv`에 넣은 포인터가 뜨지
않는다. 지금 `shell_path.ptr`가 문자열 리터럴을 가리키는 것과 수명이 같아진다.

**4. 검사는 진짜 `/sys`를 절대 읽지 않는다.**

design 결정 5가 탐색 함수에 뿌리 경로를 인자로 받게 한 이유다. 검사는
`/tmp/tars-devices-test` 아래에 가짜 트리를 만들어 그것만 읽는다. 진짜
`/sys`를 읽으면 개발 기계에 무엇이 꽂혀 있느냐에 따라 검사 결과가 달라진다 —
`power_test`가 `reboot(2)`에 닿으면 안 되는 것과 같은 종류의 규칙이다.

**5. design doc의 `EV_KEY` 비트 번호를 정정했다.**

design 결정 2에 "비트 0"이라고 적었던 것은 틀렸다. `EV_SYN`이 0번이고
`EV_KEY`는 **1번**이다. 0으로 읽으면 `EV_SYN`만 가진 장치가 전부 키보드로
보인다. design doc은 이 plan과 함께 고쳐서 커밋한다.

## 사전 준비

모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서 실행한다.
`main` 브랜치, working tree가 깨끗한 상태에서 시작한다.

**`docker run`/`docker build`에 `--platform`을 붙이지 않는다**
(`docs/decisions/project_build_host_arch.md`).

**`/tmp` + `cp` + `diff` 경로를 쓰는 파일은 둘이다** —
`init/src/devices.zig`(약 170줄)와 `init/src/devices_test.zig`(약 170줄).
둘 다 새 파일이므로 `diff` 대조는 넣은 뒤 한 번만 한다. 나머지 편집은 전부
짧아서 인라인으로 제시한다.

**인라인으로 제시하는 블록은 "넣을 것"만 적는다.** 문맥 줄을 포함한 블록을
제시했다가 기존 줄이 복제된 사고가 IP-M2에 있었다.

**이미지 재빌드는 필요 없다.** 새 외부 의존이 없다.

---

## Task 1: 비트맵을 뒤에서부터 읽는다

이 milestone에서 가장 틀리기 쉬운 곳이다. sysfs는 비트맵을 **가장 높은 워드부터**
찍으므로, 앞에서부터 세면 방향이 뒤집힌 채로 그럴듯하게 동작한다.

**Files:**
- Create: `init/src/devices.zig` (이 Task에서는 상수와 함수 둘까지만)
- Create: `init/src/devices_test.zig`
- Modify: `init/build.zig` (검사 하나 추가)

- [ ] **Step 1: 실패할 검사를 먼저 쓴다**

`init/src/devices_test.zig`를 **새로** 만든다. 100줄이 넘으므로 Claude가
`/tmp/devices_test.zig`에 원본을 만들어 두고, 다음 명령으로 제자리에 넣는다.

```bash
cp /tmp/devices_test.zig init/src/devices_test.zig
```

이 Task에서 넣을 내용은 아래와 같다(Task 2에서 뒷부분이 더 붙는다).

```zig
const std = @import("std");
const linux = std.os.linux;
const devices = @import("devices.zig");

/// config_test·power_test와 같은 모양이다: 호스트 아키텍처 실행 파일이고,
/// 실패하면 0이 아닌 종료 코드로 끝난다. 체인 스크립트가 셋을 똑같이 다룰
/// 수 있어야 한다.
pub fn main() !void {
    // ── 1. 워드의 방향 ────────────────────────────────────────────────
    //
    // 이 파일에서 가장 중요한 두 줄이다. sysfs는 가장 높은 워드를 맨 앞에
    // 찍으므로(drivers/input/input.c의 input_print_bitmap), "1 0"은 워드가
    // 둘이고 **뒤엣것이 0번 워드**다. 따라서 64번 비트가 서 있고 0번 비트는
    // 비어 있다. 방향을 뒤집어 읽으면 정확히 반대로 나오는데, 그래도 아래
    // 검사들이 대부분 통과해 버리기 때문에 여기서 못 잡으면 못 잡는다.
    if (!devices.bitSet("1 0", 64)) {
        std.debug.print("FAIL: bit 64 of \"1 0\" should be set (words run high to low)\n", .{});
        return error.WordOrderReversed;
    }
    if (devices.bitSet("1 0", 0)) {
        std.debug.print("FAIL: bit 0 of \"1 0\" should be clear (words run high to low)\n", .{});
        return error.WordOrderReversed;
    }

    // ── 2. 워드가 모자란 경우 ─────────────────────────────────────────
    //
    // 커널은 비어 있는 상위 워드를 아예 안 찍는다. 그래서 물어본 비트가
    // 찍힌 워드 수를 넘어가면 그 비트는 "서 있지 않다"가 정답이다. 전원
    // 버튼의 ev가 "3" 한 워드뿐이라 이 경로를 실제로 밟는다.
    if (devices.bitSet("3", 116)) {
        std.debug.print("FAIL: \"3\" has one word, bit 116 cannot be set\n", .{});
        return error.MissingWordNotHandled;
    }

    // ── 3. 실제 값으로 읽어 본다 ──────────────────────────────────────
    //
    // EV_KEY는 1번이다. 0번은 EV_SYN이고, 그것은 거의 모든 장치가 갖고
    // 있어서 판정에 쓸 수 없다.
    if (!devices.bitSet("3", 1)) {
        std.debug.print("FAIL: \"3\" should have EV_KEY (bit 1)\n", .{});
        return error.BitNotFound;
    }
    // KEY_POWER는 116번이라 1번 워드의 52번 비트다. 0x10000000000000이
    // 정확히 1<<52이고, 그것이 QEMU의 전원 버튼이 내놓는 값이다.
    if (!devices.bitSet("10000000000000 0", 116)) {
        std.debug.print("FAIL: KEY_POWER (116) should be set\n", .{});
        return error.BitNotFound;
    }
    // 같은 장치에 KEY_A(30)는 없다. 전원 버튼이 키보드로 오인되지 않는
    // 근거가 이것이다.
    if (devices.bitSet("10000000000000 0", 30)) {
        std.debug.print("FAIL: KEY_A (30) should not be set on a power button\n", .{});
        return error.UnexpectedBit;
    }

    std.debug.print("devices_test: bitmap words are read from the tail end\n", .{});

    // ── 4. capability 판정 ────────────────────────────────────────────
    //
    // QEMU의 AT 키보드가 실제로 내놓는 값이다. 마지막 워드
    // 0xfffffffffffffffe에 1~63번 비트가 전부 서 있어서 KEY_ESC(1)부터
    // KEY_D(32)까지의 조건을 채운다.
    const keyboard_key = "402000000 3803078f800d001 feffffdfffefffff fffffffffffffffe";
    if (!devices.looksLikeKeyboard("120013", keyboard_key)) {
        std.debug.print("FAIL: the AT keyboard should look like a keyboard\n", .{});
        return error.KeyboardNotRecognized;
    }
    // 전원 버튼은 EV_KEY를 갖고 있다. 그래서 ev만 보면 키보드와 구별되지
    // 않고, KEY_ESC~KEY_D 범위를 요구하는 것이 유일한 구분선이다.
    if (devices.looksLikeKeyboard("3", "10000000000000 0")) {
        std.debug.print("FAIL: a power button must not pass as a keyboard\n", .{});
        return error.PowerButtonMisread;
    }
    // ev를 실제로 본다는 증거. 키는 완전한 키보드인데 EV_KEY가 없으면
    // 통과하면 안 된다.
    if (devices.looksLikeKeyboard("0", keyboard_key)) {
        std.debug.print("FAIL: a device without EV_KEY must not pass\n", .{});
        return error.EvBitmapIgnored;
    }

    std.debug.print("devices_test: capability decides, not the name\n", .{});
}
```

- [ ] **Step 2: 검사를 빌드에 매단다**

`init/build.zig`의

```zig
    const test_step = b.step("test", "호스트 아키텍처로 도는 검사를 실행한다");
    test_step.dependOn(&b.addRunArtifact(config_test).step);
    test_step.dependOn(&b.addRunArtifact(power_test).step);
```

에서 마지막 줄 **뒤에** 다음을 넣는다.

```zig
    test_step.dependOn(&b.addRunArtifact(devices_test).step);
```

그리고 `power_test`를 만드는 블록

```zig
    const power_test = b.addExecutable(.{
        .name = "power_test",
        .root_module = power_test_mod,
    });
```

**뒤에** 다음 블록을 넣는다.

```zig

    // HD-M0: sysfs 비트맵을 읽는 함수들을 보는 검사. 이것도 게스트가 아니라
    // 컨테이너가 직접 실행하므로 host_target이다. devices.zig는 진짜 /sys가
    // 아니라 인자로 받은 뿌리 경로를 읽으므로(design 결정 5), 이 검사가
    // 개발 기계의 입력 장치를 건드리지 않는다.
    const devices_test_mod = b.createModule(.{
        .root_source_file = b.path("src/devices_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const devices_test = b.addExecutable(.{
        .name = "devices_test",
        .root_module = devices_test_mod,
    });
```

- [ ] **Step 3: 실패를 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer bash -c "zig build test"
```

기대: **컴파일 에러.** `devices.zig`가 아직 없다.

```
error: unable to load 'src/devices.zig': FileNotFound
```

PM-M1의 Task 1이 "시그널에 죽는" 실패였던 것과 달리 이번에는 파일이 없는
실패다. 검사가 먼저 있고 구현이 뒤에 오는 순서 자체는 같다.

- [ ] **Step 4: `devices.zig`의 앞부분을 만든다**

`init/src/devices.zig`를 **새로** 만든다. Claude가 `/tmp/devices.zig`에
원본(Task 2 몫까지 포함한 전체)을 만들어 두고, 다음 명령으로 제자리에 넣는다.

```bash
cp /tmp/devices.zig init/src/devices.zig
```

이 Task가 쓰는 부분은 다음과 같다. **파일 전체는 Task 2 Step 3에 이어서
적혀 있고, `cp` 한 번으로 둘 다 들어간다** — Task 2에서 다시 복사할 필요가
없다는 뜻이다. Task 1의 검사는 아래 부분만으로 통과한다.

```zig
const std = @import("std");
const linux = std.os.linux;

/// main.zig·config.zig에도 같은 함수가 있다. config.zig가 적어 둔 그대로,
/// 세 줄짜리 헬퍼 하나 때문에 공용 모듈을 만들지 않는다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// 게스트의 진짜 sysfs 뿌리. 검사는 이 자리에 /tmp의 가짜 트리를 넣는다
/// (design 결정 5).
pub const SYS_INPUT: []const u8 = "/sys/class/input";

/// 훑어볼 evdev 번호의 상한. 디렉터리를 열어 순회하는 대신 event0부터
/// 차례로 열어 보는 이유는 init에 libc도 힙도 없기 때문이다 — getdents64를
/// 직접 다루는 것보다 open 서른두 번이 짧고 예측 가능하다. 장치 번호는
/// 0부터 촘촘히 붙으므로 32면 넉넉하다.
const MAX_EVENT: u8 = 32;

/// capabilities 파일 하나의 상한. key 비트맵이 가장 길지만
/// (KEY_MAX가 0x2ff이라 워드 열둘) 공백까지 200바이트를 넘지 않는다.
const MAX_BITMAP = 256;

/// 장치 이름의 상한. 로그에만 쓴다.
const MAX_NAME = 128;

/// 경로 버퍼의 크기. 가장 긴 결과가 "/dev/input/event31"(18자)이다.
pub const MAX_PATH = 64;

/// sysfs 비트맵의 워드 폭. 커널은 unsigned long 단위로 찍는다. 32비트
/// 프로세스가 읽으면 32비트씩 쪼개 주지만(input_bits_to_string의
/// in_compat_syscall 분기), init도 검사도 64비트라 그 경로에 닿지 않는다.
const WORD_BITS: usize = 64;

/// 입력 이벤트 종류. include/uapi/linux/input-event-codes.h와 같아야 한다.
/// **EV_SYN이 0번이라 EV_KEY는 1번이다.** 여기를 0으로 착각하면 EV_SYN만
/// 가진 장치까지 전부 통과한다.
const EV_KEY: u16 = 1;

/// "완전한 키보드"의 판정 범위. KEY_ESC(1)부터 KEY_D(32)까지가 ESC·숫자
/// 열·Q~D를 덮는다. udev의 input_id가 쓰는 것과 같은 기준이고, 키 몇 개만
/// 가진 전원 버튼은 이 범위를 절대 못 채운다.
const KEY_ESC: u16 = 1;
const KEY_D: u16 = 32;

/// sysfs 비트맵 문자열에서 code번 비트가 서 있는지 본다.
///
/// **문자열은 가장 높은 워드가 맨 앞이다.** 커널의 input_print_bitmap이
/// 배열을 거꾸로 훑으면서 찍고, 비어 있는 상위 워드는 아예 건너뛴다. 그래서
/// 워드의 개수가 고정이 아니고, 우리가 원하는 워드는 **뒤에서부터** 세어야
/// 찾을 수 있다. 이 뒤집힘이 이 파일에서 유일하게 미묘한 부분이다.
pub fn bitSet(bitmap: []const u8, code: u16) bool {
    const want_word: usize = code / WORD_BITS;
    const want_bit: u6 = @intCast(code % WORD_BITS);

    var counter = std.mem.tokenizeAny(u8, bitmap, " \t\r\n");
    var count: usize = 0;
    while (counter.next()) |_| count += 1;

    // 상위 워드가 통째로 생략됐다는 뜻이다 = 그 비트는 서 있지 않다.
    if (want_word >= count) return false;

    const index_from_front = count - 1 - want_word;
    var it = std.mem.tokenizeAny(u8, bitmap, " \t\r\n");
    var i: usize = 0;
    while (it.next()) |token| : (i += 1) {
        if (i != index_from_front) continue;
        const word = std.fmt.parseInt(u64, token, 16) catch return false;
        return (word >> want_bit) & 1 == 1;
    }
    return false;
}

/// 이 장치가 "완전한 키보드"인가. 이름은 보지 않는다(design 결정 2) —
/// 실제 기계에서 USB 키보드는 제조사마다 다른 이름을 달고 나온다.
pub fn looksLikeKeyboard(ev: []const u8, key: []const u8) bool {
    if (!bitSet(ev, EV_KEY)) return false;

    var code: u16 = KEY_ESC;
    while (code <= KEY_D) : (code += 1) {
        if (!bitSet(key, code)) return false;
    }
    return true;
}
```

- [ ] **Step 5: 통과를 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer bash -c "zig build test"
```

기대: 마지막에 아래 두 줄이 나오고 종료 코드가 0이다.

```
devices_test: bitmap words are read from the tail end
devices_test: capability decides, not the name
```

`config_test`와 `power_test`의 줄도 함께 나온다. 셋 다 같은 `test` step에
매달려 있다.

- [ ] **Step 6: 커밋**

```bash
git add init/src/devices.zig init/src/devices_test.zig init/build.zig
git commit -m "Read evdev capability bitmaps from the tail end"
```

`devices.zig`는 Task 2 몫까지 들어 있는 상태로 커밋된다. 아직 아무도 부르지
않는 함수가 몇 개 섞여 있지만, 파일을 두 번에 나눠 넣는 것보다 `cp` 한 번이
사고가 적다.

---

## Task 2: 가짜 sysfs 트리에서 장치를 고른다

Task 1이 만든 판정 위에 파일 읽기를 얹는다. 여전히 부팅하지 않는다.

**Files:**
- Modify: `init/src/devices_test.zig` (뒤에 검사 추가)
- Verify: `init/src/devices.zig` (Task 1의 `cp`로 이미 들어와 있다)

- [ ] **Step 1: 가짜 트리를 만드는 검사를 쓴다**

`init/src/devices_test.zig`의 마지막 줄

```zig
    std.debug.print("devices_test: capability decides, not the name\n", .{});
}
```

에서 `}` **앞**에 아래 블록을 넣는다(마지막 `}`는 그대로 두고 그 위에 끼운다).

```zig

    // ── 5. 가짜 sysfs 트리 ────────────────────────────────────────────
    //
    // 진짜 /sys를 읽지 않는 이유는 design 결정 5다. 이 검사는 빌드
    // 컨테이너에서 도는데, 그 안의 /sys는 개발 기계의 것이라 무엇이 꽂혀
    // 있느냐에 따라 결과가 달라진다.
    try mkdirOne(ROOT);
    try mkdirOne(FULL);
    try mkdirOne(BUTTON);

    // 값 셋 다 sysfs가 실제로 주는 모양이다 — 줄 끝의 개행까지 포함한다.
    // 개행을 빼고 검사하면 tokenize가 그것을 걸러 준다는 사실을 못 보게 된다.
    try makeDevice(FULL, 0, "Power Button\n", "3\n", "10000000000000 0\n");
    try makeDevice(FULL, 1, "AT Translated Set 2 keyboard\n", "120013\n",
        "402000000 3803078f800d001 feffffdfffefffff fffffffffffffffe\n");
    // BTN_LEFT(0x110 = 272)만 가진 장치. EV_KEY는 있지만 키보드는 아니다.
    try makeDevice(FULL, 2, "TARS fake mouse\n", "3\n", "10000 0 0 0 0\n");

    const found = devices.findKeyboard(FULL) orelse {
        std.debug.print("FAIL: no keyboard found in the fake tree\n", .{});
        return error.KeyboardNotFound;
    };
    if (found != 1) {
        std.debug.print("FAIL: picked event{d}, want event1\n", .{found});
        return error.WrongDevicePicked;
    }

    // 순서가 중요하다. event0(전원 버튼)이 먼저 오는데도 event1을 골랐다는
    // 것은 번호가 아니라 성질로 판단했다는 뜻이다. ACPI를 켜면 실제로 이
    // 배치가 된다(design 조사 5).
    std.debug.print("devices_test: picked event1 past a power button at event0\n", .{});

    // ── 6. 키보드가 하나도 없으면 ─────────────────────────────────────
    try makeDevice(BUTTON, 0, "Power Button\n", "3\n", "10000000000000 0\n");
    if (devices.findKeyboard(BUTTON) != null) {
        std.debug.print("FAIL: a lone power button was reported as a keyboard\n", .{});
        return error.PowerButtonMisread;
    }

    // ── 7. 폴백은 부팅을 막지 않는다 (design 결정 6) ──────────────────
    var fallback = devices.Path{};
    devices.resolveKeyboard(BUTTON, &fallback);
    if (!std.mem.eql(u8, fallback.slice(), "/dev/input/event0")) {
        std.debug.print("FAIL: fallback gave '{s}', want /dev/input/event0\n", .{
            fallback.slice(),
        });
        return error.WrongFallback;
    }

    var resolved = devices.Path{};
    devices.resolveKeyboard(FULL, &resolved);
    if (!std.mem.eql(u8, resolved.slice(), "/dev/input/event1")) {
        std.debug.print("FAIL: resolved '{s}', want /dev/input/event1\n", .{
            resolved.slice(),
        });
        return error.WrongPath;
    }

    std.debug.print("devices_test: a missing keyboard falls back to event0\n", .{});
```

- [ ] **Step 2: 검사가 쓰는 헬퍼를 파일 맨 위에 넣는다**

같은 파일의

```zig
const devices = @import("devices.zig");
```

**바로 다음**에 아래 블록을 넣는다(`pub fn main` 앞이다).

```zig

/// 이 검사가 만드는 가짜 트리의 뿌리. 게스트가 아니라 빌드 컨테이너의
/// /tmp에 만든다.
const ROOT = "/tmp/tars-devices-test";
const FULL = ROOT ++ "/full";
const BUTTON = ROOT ++ "/button";

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// 경로를 조립하는 버퍼. 돌려준 슬라이스는 **다음 호출에서 덮인다** —
/// 아래 호출들이 전부 만들자마자 바로 쓰기 때문에 이것으로 충분하다.
var path_buf: [256]u8 = undefined;

fn join(comptime fmt: []const u8, args: anytype) [:0]const u8 {
    const text = std.fmt.bufPrint(path_buf[0 .. path_buf.len - 1], fmt, args) catch unreachable;
    path_buf[text.len] = 0;
    return path_buf[0..text.len :0];
}

/// 있으면 그냥 넘어간다. 검사를 두 번 돌려도 같은 결과가 나와야 한다.
fn mkdirOne(path: [:0]const u8) !void {
    const rc = linux.mkdir(path.ptr, 0o755);
    if (failed(rc)) |e| {
        if (e == .EXIST) return;
        std.debug.print("FAIL: mkdir {s} (errno {d})\n", .{ path, @intFromEnum(e) });
        return error.MkdirFailed;
    }
}

fn writeFile(path: [:0]const u8, text: []const u8) !void {
    const rc = linux.open(path.ptr, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644);
    if (failed(rc)) |e| {
        std.debug.print("FAIL: create {s} (errno {d})\n", .{ path, @intFromEnum(e) });
        return error.OpenFailed;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    var written: usize = 0;
    while (written < text.len) {
        const n = linux.write(fd, text.ptr + written, text.len - written);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            std.debug.print("FAIL: write {s} (errno {d})\n", .{ path, @intFromEnum(e) });
            return error.WriteFailed;
        }
        if (n == 0) return error.WriteFailed;
        written += n;
    }
}

/// 진짜 sysfs에서 device는 심볼릭 링크지만 여기서는 그냥 디렉터리로 만든다.
/// 우리가 하는 일은 그 아래의 파일을 열어 읽는 것뿐이라 결과가 같다.
fn makeDevice(
    root: []const u8,
    n: u8,
    name: []const u8,
    ev: []const u8,
    key: []const u8,
) !void {
    try mkdirOne(join("{s}/event{d}", .{ root, n }));
    try mkdirOne(join("{s}/event{d}/device", .{ root, n }));
    try mkdirOne(join("{s}/event{d}/device/capabilities", .{ root, n }));
    try writeFile(join("{s}/event{d}/device/name", .{ root, n }), name);
    try writeFile(join("{s}/event{d}/device/capabilities/ev", .{ root, n }), ev);
    try writeFile(join("{s}/event{d}/device/capabilities/key", .{ root, n }), key);
}
```

- [ ] **Step 3: `devices.zig`의 나머지를 확인한다**

Task 1의 `cp`로 이미 들어와 있어야 하는 부분이다. `init/src/devices.zig`의
`looksLikeKeyboard` **뒤에** 다음이 있는지 `Read`로 확인한다. 없으면
`/tmp/devices.zig`가 옛 버전이라는 뜻이므로 다시 `cp` 한다.

```zig
/// 널 종료 경로를 담는 고정 버퍼. init에는 힙이 없으므로 호출자가 이 값을
/// 스택에 두고 포인터만 argv로 넘긴다. main()의 스택은 supervise()가 영영
/// 반환하지 않으므로 프로세스 수명 내내 살아 있다 — 지금 argv에 들어가는
/// 문자열 리터럴과 수명이 같아진다.
pub const Path = struct {
    buf: [MAX_PATH]u8 = [_]u8{0} ** MAX_PATH,
    len: usize = 0,

    /// execve의 argv에 그대로 넣을 수 있는 포인터. 슬라이스에 :0을 붙이면
    /// 널 종료를 컴파일러가 실제로 검사해 준다.
    pub fn cstr(self: *const Path) [*:0]const u8 {
        return self.buf[0..self.len :0].ptr;
    }

    pub fn slice(self: *const Path) []const u8 {
        return self.buf[0..self.len];
    }
};

/// 파일 하나를 통째로 buf에 읽는다. config.load와 같은 모양이다 —
/// read(2)가 요청한 만큼을 다 준다는 보장이 없으므로 "돌아온 만큼 더한다".
fn readFile(path: [*:0]const u8, buf: []u8) ?[]const u8 {
    const rc = linux.open(path, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |_| return null; // 없는 장치 번호는 ENOENT다. 정상이다.
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return null;
        }
        if (n == 0) break; // EOF
        len += n;
    }
    return buf[0..len];
}

/// `{sys_root}/event{n}/device/{attr}`를 읽는다.
fn readAttr(sys_root: []const u8, n: u8, attr: []const u8, buf: []u8) ?[]const u8 {
    var path: [MAX_PATH * 2]u8 = undefined;
    const text = std.fmt.bufPrint(
        path[0 .. path.len - 1],
        "{s}/event{d}/device/{s}",
        .{ sys_root, n, attr },
    ) catch return null;
    path[text.len] = 0;
    return readFile(path[0..text.len :0].ptr, buf);
}

/// 키보드처럼 생긴 첫 evdev 번호. 없으면 null.
///
/// 번호가 작은 것부터 보므로 여럿이면 첫 번째를 쓴다(design 결정 4). 화면
/// 하나에 셸 하나인 구조라 키보드가 여럿일 이유가 없다.
pub fn findKeyboard(sys_root: []const u8) ?u8 {
    var n: u8 = 0;
    while (n < MAX_EVENT) : (n += 1) {
        var ev_buf: [MAX_BITMAP]u8 = undefined;
        const ev = readAttr(sys_root, n, "capabilities/ev", &ev_buf) orelse continue;

        var key_buf: [MAX_BITMAP]u8 = undefined;
        const key = readAttr(sys_root, n, "capabilities/key", &key_buf) orelse continue;

        if (looksLikeKeyboard(ev, key)) return n;
    }
    return null;
}

/// 키보드 장치 경로를 정하고 로그로 남긴다. 못 찾아도 **부팅을 막지 않는다**
/// (design 결정 6) — 탐색기의 버그가 기계를 못 켜게 만드는 것이 가장 나쁜
/// 결말이다. 그때는 예전 상수와 같은 event0으로 떨어진다.
pub fn resolveKeyboard(sys_root: []const u8, out: *Path) void {
    const n = findKeyboard(sys_root) orelse blk: {
        std.debug.print("tars-init: no keyboard found under {s}, falling back to event0\n", .{
            sys_root,
        });
        break :blk 0;
    };

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

    // 이름은 판정에 쓰지 않고 로그에만 쓴다. 사람이 로그를 읽을 때 "왜
    // 이것을 골랐나"를 알 수 있어야 하기 때문이다.
    var name_buf: [MAX_NAME]u8 = undefined;
    const raw = readAttr(sys_root, n, "name", &name_buf) orelse "";
    const name = std.mem.trim(u8, raw, " \t\r\n");

    // terminal/check.sh가 이 줄의 앞부분을 grep한다. 고치면 게이트도 함께
    // 고쳐야 한다(HANDOFF의 "로그 문구는 두 곳에 중복된다").
    std.debug.print("tars-init: keyboard device {s} ({s})\n", .{ out.slice(), name });
}
```

- [ ] **Step 4: 검사를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer bash -c "zig build test"
```

기대: 아래 네 줄이 모두 나오고 종료 코드가 0이다. 사이에
`tars-init: keyboard device ...` 줄도 섞여 나오는데, `resolveKeyboard`가
로그를 찍는 함수라서 그렇다 — 검사에서도 그 문구를 눈으로 확인할 수 있는
것이 이득이다.

```
devices_test: bitmap words are read from the tail end
devices_test: capability decides, not the name
devices_test: picked event1 past a power button at event0
devices_test: a missing keyboard falls back to event0
```

- [ ] **Step 5: 가짜 트리가 실제로 만들어졌는지 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer bash -c "zig build test >/dev/null 2>&1; find /tmp/tars-devices-test -type f | sort"
```

기대: 파일 열두 개(장치 넷 × 셋)가 나온다. 컨테이너는 `--rm`이라 매번 새
`/tmp`에서 시작하므로, 이 목록이 나온다는 것은 검사가 트리를 직접 만들었다는
뜻이다.

```
/tmp/tars-devices-test/button/event0/device/capabilities/ev
/tmp/tars-devices-test/button/event0/device/capabilities/key
/tmp/tars-devices-test/button/event0/device/name
/tmp/tars-devices-test/full/event0/device/capabilities/ev
...
```

- [ ] **Step 6: 커밋**

```bash
git add init/src/devices_test.zig
git commit -m "Pick the keyboard by capability, not by number"
```

---

## Task 3: PID 1이 찾고 terminal이 받는다

여기서 처음으로 부팅한다.

**Files:**
- Modify: `init/src/main.zig` (import, `Child.argv`, `main()`의 배선)
- Modify: `terminal/src/main.zig` (상수 제거, `argv[4]` 수신)

- [ ] **Step 1: init에 모듈을 들인다**

`init/src/main.zig`의

```zig
const power = @import("power.zig");
```

**다음 줄**에 넣는다.

```zig
const devices = @import("devices.zig");
```

- [ ] **Step 2: argv 자리를 다섯으로 늘린다**

같은 파일의

```zig
    /// IP-M2에서 셋에서 넷으로 늘었다. terminal이 받는 넷째 자리가
    /// keyboard이고, 콘솔 셸은 그 자리를 null로 둔다.
    argv: [4:null]?[*:0]const u8,
```

를 이것으로 바꾼다.

```zig
    /// IP-M2에서 셋에서 넷으로, HD-M0에서 넷에서 다섯으로 늘었다. terminal이
    /// 받는 넷째가 keyboard, 다섯째가 키보드 장치 경로이고, 콘솔 셸은 그
    /// 자리를 전부 null로 둔다.
    argv: [5:null]?[*:0]const u8,
```

- [ ] **Step 3: 부팅 시점에 탐색한다**

같은 파일의

```zig
    logDrmDevicePresence();
```

**다음**에 아래 블록을 넣는다.

```zig

    // sysfs를 붙인 뒤여야 한다(:332). 이 값은 main()의 스택에 살고,
    // supervise()가 영영 반환하지 않으므로 argv에 넣은 포인터가 뜨지 않는다.
    var keyboard_path = devices.Path{};
    devices.resolveKeyboard(devices.SYS_INPUT, &keyboard_path);
```

- [ ] **Step 4: 자식 둘의 argv를 고친다**

같은 파일의

```zig
            .argv = .{ TERMINAL_PATH.ptr, shell_path.ptr, shell_flag.ptr, keyboard_arg.ptr },
```

를 이것으로 바꾼다.

```zig
            .argv = .{
                TERMINAL_PATH.ptr,
                shell_path.ptr,
                shell_flag.ptr,
                keyboard_arg.ptr,
                keyboard_path.cstr(),
            },
```

그리고

```zig
            .argv = .{ shell_path.ptr, null, null, null },
```

를 이것으로 바꾼다.

```zig
            .argv = .{ shell_path.ptr, null, null, null, null },
```

- [ ] **Step 5: terminal의 상수를 지운다**

`terminal/src/main.zig`의

```zig
const INPUT_DEVICE = "/dev/input/event0";
```

를 **줄째 지운다**(위아래 빈 줄은 그대로 둔다).

- [ ] **Step 6: terminal이 argv[4]를 받게 한다**

같은 파일의

```zig
    const swap_alt_meta = std.mem.eql(u8, std.mem.span(keyboard), "pc");
```

**다음**에 아래 블록을 넣는다.

```zig

    // 다섯째 인자가 키보드 장치 경로다(HD-M0). 번호를 여기서 고르지 않는
    // 이유는 CP가 세운 규칙 그대로다 — 하드웨어를 살펴 고르는 일은 PID 1이
    // 하고 terminal은 그 결정을 실행만 한다. 손으로 실행할 때를 위한
    // 기본값은 예전 상수와 같다.
    const input_device: [*:0]const u8 = if (args.len > 4) args[4] else "/dev/input/event0";
```

- [ ] **Step 7: 열고 찍는 자리를 고친다**

같은 파일의

```zig
    const keyboard_fd = input.openDevice(INPUT_DEVICE) catch |err| {
        std.debug.print("terminal: FATAL cannot open {s}: {any}\n", .{ INPUT_DEVICE, err });
        return err;
    };
    std.debug.print("terminal: opened {s}\n", .{INPUT_DEVICE});
```

를 이것으로 바꾼다.

```zig
    const keyboard_fd = input.openDevice(input_device) catch |err| {
        std.debug.print("terminal: FATAL cannot open {s}: {any}\n", .{ input_device, err });
        return err;
    };
    std.debug.print("terminal: opened {s}\n", .{input_device});
```

- [ ] **Step 8: 부팅해서 로그를 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash terminal/check.sh
```

기대: `PASS`. 그리고 중간의 `--- init log ---` 아래에 다음 줄이 있어야 한다.

```
tars-init: keyboard device /dev/input/event0 (AT Translated Set 2 keyboard)
```

**이름이 정확히 저것인지 확인하는 것이 이 Step의 요점이다.** 다음 Task의
게이트 문구를 여기서 본 것으로 확정한다. 이름이 다르게 나오면 알려 줄 것 —
게이트는 이름을 요구하지 않으므로 문제는 아니지만, 우리가 어떤 장치를 골랐는지
아는 것은 중요하다.

`terminal: opened /dev/input/event0`도 함께 나온다. 이 줄은 예전과 글자 하나
안 바뀐다 — 값이 상수에서 인자로 바뀌었을 뿐 내용이 같기 때문이고, 그것이 이
milestone이 "아무 일도 안 일어난 것처럼 보여야 한다"는 뜻이다.

- [ ] **Step 9: 커밋**

```bash
git add init/src/main.zig terminal/src/main.zig
git commit -m "Let PID 1 hand the keyboard path to the terminal"
```

---

## Task 4: 게이트가 탐색을 요구한다

**Files:**
- Modify: `terminal/check.sh` (검사 하나 추가)

- [ ] **Step 1: 검사를 넣는다**

`terminal/check.sh`의

```bash
echo "init mounted all four filesystems"
```

**다음**에 아래 블록을 넣는다.

```bash

# HD-M0: 키보드를 번호가 아니라 성질로 찾았는가.
#
# 지금은 event0이 곧 키보드라 결과가 예전 상수와 같다. 그래서 이 검사가
# 지금 보는 것은 "탐색이 실제로 돌았다"까지다 — 탐색이 **옳다**는 증명은
# ACPI를 켜는 HD-M1이 한다. 그때 장치 번호가 밀리는데도 아래 화면 검사들이
# 통과하는 것이 그 증명이고, 이 줄의 번호가 바뀌는 것으로 눈에도 보인다.
#
# 장치 이름은 요구하지 않는다. 실 하드웨어에서 달라지는 것이 정상이고,
# 판정에도 쓰지 않는 값이다(design 결정 2).
if ! grep -q "tars-init: keyboard device /dev/input/event" "$LOG"; then
  echo "FAIL: init did not discover a keyboard device"
  grep 'tars-init:' "$LOG" | tail -n 20
  exit 1
fi
if grep -q "tars-init: no keyboard found" "$LOG"; then
  echo "FAIL: init fell back to event0 instead of discovering a keyboard"
  grep 'tars-init:' "$LOG" | tail -n 20
  exit 1
fi
echo "init discovered the keyboard by capability"
```

**둘째 검사가 있어야 하는 이유가 이 Task의 핵심이다.** 첫째 검사만 두면
폴백(결정 6)이 그것을 통과시킨다 — 탐색이 통째로 실패해도 `resolveKeyboard`는
`event0`을 찍기 때문이다. 그러면 게이트가 "탐색이 돌았다"와 "탐색이
실패했지만 운 좋게 답이 같다"를 구별하지 못한다. 게이트가 자기가 안 보는 것을
통과시키는 그 실패다(`project_gate_chain_composition`).

- [ ] **Step 2: 문법을 먼저 본다**

```bash
bash -n terminal/check.sh
```

기대: 아무 출력도 없다.

- [ ] **Step 3: 체인을 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash terminal/check.sh
```

기대: `init discovered the keyboard by capability`가 찍히고 `PASS`.

- [ ] **Step 4: 루트 게이트 3/3**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh
```

기대: 다섯 체인 전부 3/3. 시간은 직전과 비슷한 28분 남짓이다(부팅 횟수가
늘지 않았다). 끝 줄:

```
TARS check PASS: all chains 3/3 consecutive runs succeeded
```

**BF 체인을 특히 눈여겨볼 것.** BF는 virtio-gpu를 안 주므로 `/terminal`이
매번 죽는데, 이제 그 전에 PID 1이 sysfs를 훑는다. BF 게이트가 요구하는
`started terminal` 세 번과 `giving up on terminal`이 그대로 나와야 한다.

- [ ] **Step 5: 커밋**

```bash
git add terminal/check.sh
git commit -m "Ask the terminal gate to prove discovery ran"
```

---

## Task 5: 문서

**Files:**
- Modify: `docs/superpowers/specs/2026-08-20-tars-hardware-discovery-design.md`
  (이미 고쳐 커밋했다면 넘어간다)
- Modify: `HANDOFF.md`
- Modify: `docs/decisions/` + `MEMORY.md`

- [ ] **Step 1: 기억을 남긴다**

`docs/decisions/project_device_discovery.md`를 새로 만든다. 내용은 Claude가
쓴다. 담을 것:

- sysfs 비트맵의 워드 순서(가장 높은 워드가 맨 앞, 빈 상위 워드는 생략)
- `EV_KEY`가 1번이라는 것과 0번(`EV_SYN`)으로 착각했을 때의 증상
- 판정 기준이 `KEY_ESC`~`KEY_D`인 근거(udev `input_id`)
- 탐색 함수가 뿌리 경로를 인자로 받는 이유(검사가 개발 기계의 `/sys`를 읽지
  않게)
- 폴백이 게이트의 사각지대를 만든다는 것과 그것을 닫은 방법(Task 4의 둘째
  검사)

`MEMORY.md`에 한 줄을 더한다.

- [ ] **Step 2: HANDOFF 갱신**

HD-M0이 끝났고 다음은 HD-M1(ACPI)이라는 것, HD-M1에서 실측할 것 셋(커널 빌드
시간 증가분, 등록되는 `Power Button` 장치, `Restarting system` 유지)을 적는다.

- [ ] **Step 3: 커밋**

```bash
git add docs HANDOFF.md MEMORY.md
git commit -m "Hand off with the keyboard found by capability"
```

---

## 위험과 대응

**1. `Path.cstr()`의 수명.** `keyboard_path`는 `main()`의 지역 변수이고
`children`도 그렇다. `supervise()`가 `noreturn`이라 안전하지만, 나중에 누군가
`supervise`를 반환하게 만들면 이 포인터가 뜬다. `Path`의 doc comment에 그
의존을 적어 두는 것이 대응이다(Task 2 Step 3의 주석).

**2. 컨테이너의 `/tmp`가 더러울 때.** `mkdirOne`이 `EEXIST`를 넘기고
`writeFile`이 `O_TRUNC`를 쓰므로 두 번 돌려도 결과가 같다. `docker run --rm`
이라 실제로는 매번 빈 `/tmp`에서 시작한다.

**3. 게스트에 입력 장치가 정말 하나뿐인가.** `kernel/.config`는
`CONFIG_INPUT_MOUSEDEV`·`CONFIG_INPUT_JOYDEV`·`CONFIG_HID_SUPPORT`가 전부
꺼져 있고 켜진 것은 `CONFIG_INPUT_KEYBOARD`와 `CONFIG_SERIO_I8042`뿐이다.
그래서 지금은 AT 키보드 하나만 등록된다 — Task 3 Step 8이 `event0`을 볼 것으로
예상하는 근거다. 다르게 나오면 그 자체가 새로운 사실이므로 멈추고 해석한다.

**4. `bufPrint`의 `catch unreachable` 둘.** `resolveKeyboard`와 검사의
`join`에 있다. 둘 다 버퍼가 결과보다 세 배 이상 크다. init을 나중에
`ReleaseSafe`로 바꿔도(이월 숙제) `unreachable`은 안전하게 패닉하므로 조용히
틀리지 않는다.
