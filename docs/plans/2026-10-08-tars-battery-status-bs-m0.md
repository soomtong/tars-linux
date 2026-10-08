# BS-M0 — 가짜 배터리와 순수 층

Date: 2026-10-08
Design: `docs/specs/2026-10-08-tars-battery-status-design.md`
Status: plan을 썼다(구현 전). 구현과 루트 게이트의 값은 끝난 뒤 맨 아래 "BS-M0이 실측한 것"에 적는다. 다음은 BS-M1(`-bs-m1.md`).

## 누가 무엇을 하나

design 결정 12. Task 0~7은 구현 서브에이전트가 main 작업 트리에서 직접 편집하고 돌린다. Task 8(루트 게이트 2회 · 실측 절 · commit)은
lead가 한다. 구현자는 commit하지 않고, 끝에 `git diff --stat` · `git diff | rg '^-'` · 각 Task의 명령 출력을 그대로 보고한다. 이 plan의
"착수 전에 확정한 것" 절은 구현자가 고치지 않는다.

권하는 모델은 Sonnet이다. 새 파일 둘은 이 plan의 코드 블록을 글자 그대로 넣고, 편집은 `old_string` · `new_string`을 그대로 넣는다. 구현자가
새로 지을 코드는 없다. 이 plan의 Zig 코드는 컨테이너에서 컴파일해 본 글자가 아니다(plan을 쓸 때 Docker를 안 켰다) — 호스트 zig 0.17의
`zig ast-check`로 문법만 봤다(확정 13). 그래서 Task 1 · 2의 첫 `zig build test`가 컴파일 에러를 내면, 에러 줄을 보고 그 자리만 고치고 무엇을
어떻게 고쳤는지 보고에 적는다. 동작(검사의 기대값)이 다르면 고치지 말고 멈추고 보고한다.

| 파일 | 무엇을 | 줄 |
|---|---|---|
| `terminal/src/battery.zig` | 새 파일 — sysfs 글자 · 고르기 · 갈래 · 칸 글자 · uevent · poll timeout의 순수 함수 아홉 | +175 |
| `terminal/src/battery_test.zig` | 새 파일 — 그 호스트 검사 열일곱 | +227 |
| `terminal/build.zig` | 편집 둘 — `battery_test` 등록 | +15 |
| `kernel/.config` | 두 줄 — `CONFIG_TEST_POWER=y`, 내장 cmdline에 낱말 하나 | +2 −2 |
| `boot/limine.conf` | 한 줄 — `cmdline:`에 `initcall_blacklist=test_power_init` | +1 −1 |
| `init/src/disk_test.zig` | 두 줄 — 검사 10이 베껴 둔 limine.conf의 `cmdline:` 줄(확정 4) | +2 −2 |
| `wifi/check.sh` | 검사 1의 주석과 grep 한 줄 — 줄 전체 비교를 낱말 비교로 | +4 −3 |

합해서 추적 파일 5개 +24 −8, 새 파일 둘 402줄. `terminal/src/main.zig`와 `status.zig`는 한 줄도 안 바뀐다 — terminal은 아직 배터리를 안 읽고 화면은
그대로다. design의 `Status:` · `CLAUDE.md` · `MEMORY.md` · `docs/decisions/` · `docs/guides/` · `HANDOFF.md`는 구현자가 안 고친다.

모든 명령은 저장소 루트에서 친다. 서브에이전트의 Bash는 호출마다 작업 디렉터리가 돌아가므로 명령 앞에
`cd /Users/dp/Repository/tars-linux &&`를 붙인다. 빌드 · 체인은 언제나 컨테이너에서 한다(호스트의 zig는 0.17, 컨테이너는 0.16.0).
호스트에서 찾을 때는 `rg`를 쓴다(이 기계에 GNU grep이 없다). 측정 파일은 `/tmp/run/bs0/` 아래에 둔다.

Docker VM의 메모리가 4GB다. 컨테이너 둘을 겹쳐 돌리면 `zig build`가 `Killed`로 죽거나 VM이 재시작된다(lessons PD-6). 컨테이너는 언제나
하나씩 돌린다. 다른 에이전트가 같은 시간에 돌 수 있으므로 모든 `docker run`을 아래로 감싼다. 명령이 실패해도 lock은 꼭 푼다.

```bash
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run … ; rc=$?
rmdir /tmp/run/docker.lock
```

20분 넘게 기다리면 `docker ps`를 보고, 컨테이너가 하나도 없으면 lock이 낡은 것이니 `rmdir`하고 진행한다.

## 이 milestone이 끝나면

- `zig build test`에 `battery_test`가 더해져 돈다. design 결정 7의 표 여덟 함수와 `statusName` 하나가 호스트에서 검사된다.
- 커널에 test_power가 내장된다. QEMU `-kernel` 부팅에는 `test_ac` · `test_battery` · `test_usb`가 생기고 `test_battery/present`가 `0`이다.
  `-append`에 `test_power.battery_present=true`를 주면 `1`이다.
- limine으로 뜨는 부팅(ISO · 설치된 ESP)에서는 test_power가 아예 등록되지 않는다 — `/sys/class/power_supply/`가 비었다.
- `wifi/check.sh`의 검사 1이 내장 cmdline에서 자기 낱말 하나만 본다.
- 화면 · 상태 줄 · 로그 줄은 하나도 안 바뀐다. 루트 게이트 스물한 체인이 그것을 본다(design 결정 12).

## 착수 전에 확정한 것

2026-10-08, HEAD `fbffcd5`. design · 커널 소스(`kernel/src/linux-6.18.42/`) · 저장소 코드를 읽어 정했다. Docker는 안 켰다.

1. QEMU에 배터리 장치가 없다. design "착수 전에 확인한 것" 10이 lead의 확인으로 이미 닫았다. design 끝 조건 4가 그 한 줄을 다시 요구하므로
   Task 6이 같은 명령을 한 번 더 친다(기대 0줄).

2. sysfs 파일의 유무. `power_supply_sysfs.c`는 장치의 속성 표에 있는 속성만 파일로 낸다. test_power의 표(`test_power.c`의
   `test_power_battery_props` · `test_power_ac_props`)를 읽으면 셋이 갈린다.

   | 장치 | `type` | `present` | `scope` | `status` · `capacity` |
   |---|---|---|---|---|
   | `test_battery` | `Battery` | 있다(기본 `1`) | 없다 | 있다(기본 `Discharging` · `50`) |
   | `test_ac` | `Mains` | 없다 | 없다 | 없다(`online`만) |
   | `test_usb` | `USB` | 없다 | 없다 | 없다(`online`만) |

   그래서 `counts`가 "파일이 없으면 null"을 받는 것이 test_power에서도 실제로 밟힌다. `test_battery`의 `scope`가 없으므로 `scope` 조건은
   언제나 통과이고, `present` 조건이 거르기의 전부다. `test_ac` · `test_usb`는 `type`에서 먼저 빠진다.

3. 파라미터 setter는 등록 전에는 아무것도 안 한다. `signal_power_supply_changed`가 `module_initialized`를 본다(`test_power.c`). 그래서
   limine 부팅에서 `initcall_blacklist`가 `test_power_init`을 막아도, 내장 cmdline의 `test_power.battery_present=false`는 값만 바꾸고
   `power_supply_changed(NULL)`을 부르지 않는다. 파라미터 파일(`/sys/module/test_power/parameters/`)은 그 부팅에도 생긴다(design 확인
   8) — 써도 아무 장치도 안 생긴다. Task 6이 ISO 부팅에서 그 목록을 찍어 둔다.

4. limine `cmdline:` 줄을 바꾸면 닿는 자리 넷을 읽었다.

   | 자리 | 영향 | 처리 |
   |---|---|---|
   | `init/src/disk.zig`의 `espConf` | 줄 끝에 ` tars.installed`를 붙일 뿐이다. 버퍼는 `install.zig`의 `conf_in` 8192 · `conf_out` 16384바이트이고 파일은 908 → 948바이트가 된다 | 안 고친다 |
   | `install/check.sh` 판정 9(와 부팅 4의 같은 grep) | `Kernel command line: .*tars\.installed( \|${CR}\|$)`. 새 줄 `… console=ttyS0 initcall_blacklist=test_power_init tars.installed`에도 맞는다(호스트 `rg`로 봤다. Task 4가 컨테이너 grep으로 다시 본다) | 안 고친다 |
   | `init/src/disk_test.zig` 검사 10 | 주석이 "원본은 boot/limine.conf의 항목 부분을 글자 그대로 옮긴 것이다"라고 말한다. 안 고쳐도 검사는 초록이지만 주석이 거짓이 된다 | 두 줄을 고친다(Task 4). design 범위에 없던 파일이다 |
   | `machine/check.sh` · `boot/check.sh` | cmdline 글자를 안 본다. 그러나 둘 다 limine으로 뜬다 — `boot`는 BIOS로, `machine`은 UEFI로 | Task 7이 둘을 함께 돌린다(lead가 적은 순서에 `boot`를 더했다) |

5. 내장 cmdline과 부트로더 cmdline의 순서. `arch/x86/kernel/setup.c`의 `CMDLINE_BOOL` 갈래가 내장 문자열 뒤에 공백과 부트로더의 것을
   붙인다. 그래서 `/proc/cmdline`과 `Kernel command line:` 줄은 언제나 `mac80211_hwsim.radios=0 test_power.battery_present=false`로
   시작한다. Task 6의 기대값이 이 순서다.

6. Kconfig. `TEST_POWER`는 `drivers/power/supply/Kconfig`의 `if POWER_SUPPLY` 안에 있는 `tristate`이고 `depends`도 `select`도 없다.
   저장소의 Kconfig 전체에서 `TEST_POWER`를 가리키는 다른 항목도 없다(`rg TEST_POWER --glob 'Kconfig*'`가 정의 한 줄). 그래서
   `olddefconfig`가 더할 기호가 없다는 것이 기대값이다 — 되접기 diff는 비고, `.config`의 diff는 고친 두 줄뿐이다. `CONFIG_MODULES`가
   꺼져 있어서 `tristate`의 값은 `y`만 된다. 착수 전에 `kernel/.config`와 `kernel/build/.config`는 이미 같았다(고정점이 유지되고 있다).

7. 블랙리스트의 이름. `test_power_init`은 `static int __init`이고 `module_init(test_power_init)`으로 등록된다. `init/main.c`의
   `initcall_blacklisted`가 `sprint_symbol_no_offset`으로 initcall 주소의 이름을 구해 비교하므로 `CONFIG_KALLSYMS=y`(있다)가 필요하다.
   이름이 맞든 틀리든 커널은 `pr_debug`만 찍는다(design 위험 3). 주소가 initcall 표에 들어가므로 gcc가 `.isra` 같은 꼬리를 붙일 수 없지만,
   Task 3이 `System.map`에서 ` t test_power_init` 한 줄을 확인해 둔다. 실제로 막혔다는 것은 Task 6의 ISO 부팅이 본다.

8. test_power가 커널 로그에 찍는 것. `test_power_get_battery_property`의 `default` 갈래만 `pr_info("… some properties deliberately report
   errors.")`를 찍는다. 등록 · uevent(`power_supply_uevent`) · thermal zone은 속성 표에 있는 속성만 읽고, 그 표의 스물두 속성에는 전부
   `case`가 있다. 그래서 QEMU 부팅에서 그 줄은 0줄이 기대값이다. 0이 아니면 이 printk가 terminal의 화면 줄을 가운데서 자를 수 있다(lessons
   "커널 printk가 terminal의 화면 줄을 가운데서 자른다 (AU-M2)") — Task 6이 부팅마다 센다.

9. 함수 하나를 더했다 — `statusName(Status) []const u8`. design 결정 10의 `battery> read … status=Discharging`은 커널의 글자를 찍는데,
   `@tagName`은 `discharging`을 낸다. M1이 그 줄을 찍으려면 enum → 글자가 필요하다. `parseStatus`도 이 함수로 비교하므로 표가 한 벌이다.
   design의 여덟 함수는 이름 · 인자 · 동작이 design 표 그대로다. `counts`의 첫 인자는 Zig 예약어 `type`을 피해 `kind`라고 부른다.

10. `class`에서 `Unknown`. design 결정 5의 표를 위에서부터 읽었다 — `plugged`가 아니고 잔량이 15 이하면 `low`이므로 `Unknown` · 10은
    `low`이고, `Unknown` · 50과 `Unknown` · 잔량 모름은 `normal`이다. 표의 `normal` 칸에 `Unknown`이 적힌 것은 잔량이 16 이상이거나 모를
    때라고 읽었다. `battery_test` 검사 11이 이 읽기를 박아 둔다. design의 뜻이 "Unknown은 언제나 회색"이었다면 lead가 고쳐야 할 자리다.

11. `build.zig`의 자리. design 결정 7은 "`status_test`와 같은 자리로 등록"이라고 했다. `status_test`는 `link_libc`와 `c_input`
    번역을 갖는다(`status.zig`가 `input.State`를 import한다). `battery.zig`는 `std`만 쓰므로 `clipboard_test` · `dictation_test`와 같은 모양
    (libc 없음)으로 `logline_test` 뒤에 둔다. design 끝 조건 2가 보는 `dependOn` 목록은 그래도 한 줄만 는다.

12. 게스트 파일의 출력 규칙. 루트 `check.sh`의 `require_no_debug_print`가 `terminal/src`의 `*_test.zig`가 아닌 파일에서
    `std.debug.print`를 찾으면 게이트를 시작하지 않는다(AL-M0). `battery.zig`는 아무것도 안 찍는다. `battery_test.zig`는 호스트 검사라
    `std.debug.print`를 쓴다(다른 `*_test.zig`와 같다).

13. 문법. 이 plan의 두 Zig 파일을 `/tmp/run/bs0-plan/`에 뽑아 호스트 zig 0.17로 `zig ast-check`를 돌렸고 둘 다 에러가 없었다. 이것은 문법
    검사일 뿐이다 — 타입 검사와 0.16의 std API(`std.mem.trimEnd` · `std.mem.order` · `std.fmt.parseInt` · `std.meta.eql`)는 Task 1 · 2의
    컨테이너 `zig build test`가 처음 본다. 쓴 API는 전부 저장소의 0.16 코드에서 같은 모양을 찾아 골랐다 — `trimEnd`는
    `init/src/disk.zig`, `order(u8, …) == .lt`는 `init/src/services.zig`, `splitScalar(u8, msg, 0)`은 `terminal/src/pointer.zig`,
    `maxInt(c_int)`은 `terminal/src/png.zig`, 검사의 `{any}` · `{?d}` · `{?s}` · `std.meta.eql`은 `dictation_test.zig` · `clipboard_test.zig`.

14. `parseCapacity`는 `i32`로 읽는다. 커널의 `intval`이 `int`라 그보다 큰 글자는 sysfs에서 안 온다. 오면(`99999999999`) 정수가 아닌 것과
    같이 null이다. `std.fmt.parseInt`는 앞의 `+`를 받는다 — `+7`은 7이다. sysfs는 `+`를 안 쓰므로 검사하지 않는다.

## Task 0: 바꾸기 전의 기준값

1. 돌고 있는 게이트나 컨테이너가 없는지, Docker가 켜져 있는지 본다.

   ```bash
   docker info >/dev/null 2>&1 && echo DOCKER-OK
   docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
   ls -d /tmp/run/docker.lock 2>&1
   ```

   `DOCKER-OK`가 안 나오면 `orb start`를 치고 다시 본다. 컨테이너가 있으면 끝나기를 기다린다(위 lock 절차). 남의 컨테이너를 죽이지 않는다.

2. 작업 트리를 본다.

   ```bash
   cd /Users/dp/Repository/tars-linux && git status --short && git log --oneline -3
   ls terminal/src/battery.zig terminal/src/battery_test.zig 2>&1
   ```

   기대: 맨 위 commit이 `fbffcd5 Trim handoff and sync docs with implemented features`이거나 그 위에 lead의 commit(design · 이 plan)이 있다.
   `git status`에 design · 이 plan · `HANDOFF.md` · `MEMORY.md` · `docs/decisions/`가 있을 수 있다. 그 밖의 소스 파일이 `M`이면 멈추고
   보고한다. `ls`는 두 파일 다 `No such file or directory`여야 한다.

3. 커널 설정의 고정점과 고칠 두 줄을 본다.

   ```bash
   cd /Users/dp/Repository/tars-linux && diff kernel/.config kernel/build/.config; echo "diff exit=$?"
   rg -n '^CONFIG_CMDLINE=|TEST_POWER' kernel/.config
   rg -n 'cmdline:' boot/limine.conf
   mkdir -p /tmp/run/bs0
   ```

   기대.

   ```
   diff exit=0
   367:CONFIG_CMDLINE="mac80211_hwsim.radios=0"
   2468:# CONFIG_TEST_POWER is not set
   18:    cmdline: console=ttyS0
   ```

   `kernel/build/.config`가 없으면 `diff`가 `No such file`을 낸다 — 그것은 괜찮다(Task 3의 빌드가 만든다). 그 밖의 줄이 나오면 멈추고 보고한다.

## Task 1: `terminal/src/battery.zig`(새 파일)

design 결정 1 · 3 · 4 · 5 · 7 · 8의 순수한 층. 시스템 콜이 없고, 파일 · 디렉터리 · 시계 · 소켓은 BS-M1의 `main.zig`가 다룬다. 이 Task가 끝나도
아무 바이너리가 이 파일을 안 쓴다(Task 2가 검사에 붙인다).

아래 블록을 글자 그대로 Write로 넣는다.

`terminal/src/battery.zig`:

```zig
//! 배터리 칸의 순수한 층(BS-M0). 설계는 `docs/specs/2026-10-08-tars-battery-status-design.md`의
//! 결정 1 · 3 · 4 · 5 · 7 · 8이다.
//!
//! sysfs 파일의 바이트를 받아 값을 돌려준다. 파일을 열고 디렉터리를 훑고 시계를 읽는 일은
//! BS-M1이 `main.zig`의 배터리 절에 둔다 — `pointer.zig` · `dictation.zig`와 `main.zig`의
//! 경계와 같은 자리다. 그래서 `battery_test`가 부팅 없이 경계값을 전부 본다. 60초 주기는
//! 게이트가 못 밟는 길이라(design 결정 11) `pollTimeout`의 검사가 그 길을 보는 유일한
//! 자리다.
//!
//! 게스트에서 도는 파일이지만 아무것도 안 찍는다. 로그 줄은 `main.zig`가 `logline.print`로
//! 찍는다(루트 `check.sh`의 `require_no_debug_print`).

const std = @import("std");

/// `status` 파일의 다섯 값. 글자는 커널 `power_supply_sysfs.c`의 표에서 왔다(`statusName`).
pub const Status = enum {
    unknown,
    charging,
    discharging,
    not_charging,
    full,
};

/// `parseStatus`가 훑는 순서. `statusName`의 `switch`는 빠진 갈래를 컴파일러가 잡지만 이
/// 목록은 못 잡는다 — 그 자리는 `battery_test` 검사 3의 왕복이 본다.
const ALL_STATUS = [_]Status{ .unknown, .charging, .discharging, .not_charging, .full };

/// 커널이 `status` 파일에 쓰는 글자. BS-M1의 `battery> read` 줄이 이 글자를 그대로 찍는다
/// (design 결정 10). `@tagName`은 소문자라 그 줄에 못 쓴다.
pub fn statusName(s: Status) []const u8 {
    return switch (s) {
        .unknown => "Unknown",
        .charging => "Charging",
        .discharging => "Discharging",
        .not_charging => "Not charging",
        .full => "Full",
    };
}

/// sysfs의 `show`가 값 뒤에 붙이는 줄바꿈을 뗀다.
fn chomp(bytes: []const u8) []const u8 {
    return std.mem.trimEnd(u8, bytes, "\n");
}

/// `status` 파일의 내용 → enum(design 결정 3). 모르는 글자와 빈 값(읽기 실패)은 `unknown`이다.
///
/// 대소문자를 구분한다. test_power의 파라미터는 소문자(`charging`)를 받지만 sysfs 파일은
/// 언제나 `statusName`의 글자로 낸다 — 소문자가 왔다면 그것은 이 파일의 내용이 아니다.
pub fn parseStatus(bytes: []const u8) Status {
    const text = chomp(bytes);
    for (ALL_STATUS) |s| {
        if (std.mem.eql(u8, text, statusName(s))) return s;
    }
    return .unknown;
}

/// `capacity` 파일의 내용 → 0~100(design 결정 3). 범위 밖은 가까운 끝으로 자르고, 정수가
/// 아니면 null이다. null이면 칸은 `  ?%`다(`cellText`).
///
/// `i32`로 읽는다. 커널의 `intval`이 `int`라 그보다 큰 글자는 이 파일에서 안 오고, 오면
/// 정수가 아닌 것과 같이 null이다.
pub fn parseCapacity(bytes: []const u8) ?u8 {
    const v = std.fmt.parseInt(i32, chomp(bytes), 10) catch return null;
    if (v < 0) return 0;
    if (v > 100) return 100;
    return @intCast(v);
}

/// 장치 하나가 칸에 들어갈 배터리인가(design 결정 1의 세 조건). 인자는 그 장치 디렉터리의
/// `type` · `present` · `scope` 파일 내용이고, 파일이 없으면 null을 넘긴다. 첫 인자의 이름이
/// `kind`인 것은 `type`이 Zig의 예약어이기 때문이다.
///
/// `present`가 없으면 있는 것으로, `scope`가 없으면 통과로 본다. test_power의 `test_battery`에는
/// `scope` 파일이 아예 없다(BS-M0 plan 확정 2).
pub fn counts(kind: []const u8, present: ?[]const u8, scope: ?[]const u8) bool {
    if (!std.mem.eql(u8, chomp(kind), "Battery")) return false;
    if (present) |p| {
        if (std.mem.eql(u8, chomp(p), "0")) return false;
    }
    if (scope) |s| {
        if (std.mem.eql(u8, chomp(s), "Device")) return false;
    }
    return true;
}

/// `counts`를 통과한 이름 중 바이트 순서로 첫째(design 결정 2). 없으면 null이다.
///
/// 순서는 `init/src/services.zig`가 `services.d`를 정렬하는 것과 같은 바이트 비교다.
/// `BAT10`이 `BAT2`보다 앞이 되지만, 배터리가 열 개인 기계는 없다.
pub fn pick(names: []const []const u8) ?[]const u8 {
    var best: ?[]const u8 = null;
    for (names) |name| {
        if (best == null or std.mem.order(u8, name, best.?) == .lt) best = name;
    }
    return best;
}

/// 칸의 색 셋(design 결정 5). 색 상수는 BS-M1이 `main.zig`에 둔다.
pub const Class = enum {
    /// 배터리로 돈다. 잔량을 모를 때도 이것이다.
    normal,
    /// 어댑터가 꽂혀 있다 — `Charging` · `Full` · `Not charging`.
    plugged,
    /// 꽂혀 있지 않고 잔량이 `LOW_MAX` 이하다.
    low,
};

/// 이 값 이하가 `low`다. 15는 `low`, 16은 `normal`이다(`battery_test` 검사 10).
pub const LOW_MAX: u8 = 15;

/// 상태와 잔량 → 갈래. 꽂혀 있으면 잔량과 무관하게 `plugged`다. `Unknown`은 꽂혀 있다는
/// 뜻이 아니므로 잔량이 낮으면 `low`다(BS-M0 plan 확정 10).
pub fn class(status: Status, capacity: ?u8) Class {
    switch (status) {
        .charging, .full, .not_charging => return .plugged,
        .unknown, .discharging => {},
    }
    const c = capacity orelse return .normal;
    return if (c <= LOW_MAX) .low else .normal;
}

/// 칸의 폭(design 결정 4). `100%`가 가장 긴 값이다.
pub const CELL_LEN = 4;

/// 잔량 → 넉 자. 숫자를 오른쪽에 붙이고 앞을 공백으로 채운다 — `100%` · ` 85%` · `  5%`,
/// 모르면 `  ?%`. 돌려주는 조각은 `buf` 전체다.
///
/// `u8` 전체를 받는다. `parseCapacity`가 100으로 자르므로 셋째 자리까지만 쓰이지만,
/// 255가 와도 넉 자를 넘지 않는다.
pub fn cellText(capacity: ?u8, buf: *[CELL_LEN]u8) []const u8 {
    buf.* = .{ ' ', ' ', ' ', '%' };
    var v = capacity orelse {
        buf[CELL_LEN - 2] = '?';
        return buf;
    };
    var i: usize = CELL_LEN - 2;
    while (true) {
        buf[i] = '0' + v % 10;
        v /= 10;
        if (v == 0 or i == 0) break;
        i -= 1;
    }
    return buf;
}

/// uevent datagram 하나가 power_supply의 것인가(design 결정 7 · 8). `ACTION`도 장치 이름도
/// 안 본다 — 그 이유는 design "착수 전에 확인한 것" 4 · 6이다.
///
/// 필드를 NUL로 나눠 `SUBSYSTEM=power_supply`와 글자 그대로 같은 필드를 찾는다
/// (`pointer.ueventAddedNode`와 같은 읽기). 머리(`change@/devices/…/power_supply/test_ac`)는
/// 경로에 그 낱말이 있어도 같은 필드가 아니라 안 걸린다.
pub fn ueventIsPowerSupply(msg: []const u8) bool {
    var it = std.mem.splitScalar(u8, msg, 0);
    while (it.next()) |field| {
        if (std.mem.eql(u8, field, "SUBSYSTEM=power_supply")) return true;
    }
    return false;
}

/// 주기(design 결정 8). 고른 배터리가 있으면 마지막으로 읽은 뒤 이만큼 지나 다시 읽는다.
pub const PERIOD_MS: i64 = 60_000;

/// `poll`의 timeout(밀리초). `due_ms`는 다음에 읽을 시각이고, 고른 배터리가 없으면 null이다 —
/// 그러면 -1(무한 대기)이라 배터리가 없는 기계의 terminal은 BS 전과 똑같이 이벤트가 없으면
/// 안 깬다.
///
/// 기한이 지났으면 0이고, `c_int`를 넘으면 그 최댓값으로 자른다. 뺄셈은 `i128`에서 한다 —
/// `i64`의 양 끝값끼리 빼도 넘치지 않는다.
pub fn pollTimeout(now_ms: i64, due_ms: ?i64) c_int {
    const due = due_ms orelse return -1;
    const left = @as(i128, due) - now_ms;
    if (left <= 0) return 0;
    if (left > std.math.maxInt(c_int)) return std.math.maxInt(c_int);
    return @intCast(left);
}
```

확인.

```bash
cd /Users/dp/Repository/tars-linux && wc -l terminal/src/battery.zig && rg -c 'std\.debug\.print' terminal/src/battery.zig; echo "rg exit=$?"
```

기대: `rg`가 아무것도 안 찍고 `rg exit=1`(그 이름이 없다 — 확정 12). 줄 수는 보고에 적는다.

## Task 2: `terminal/src/battery_test.zig`(새 파일) · `terminal/build.zig`

### 2-1. 검사 목록

design 끝 조건 1의 경우를 전부 담는다. 번호는 파일 안의 `검사 N` 주석과 출력 줄의 번호와 같다.

| 검사 | 함수 | 경우 |
|---|---|---|
| 1 | `parseStatus` | sysfs의 다섯 글자(`Unknown\n` · `Charging\n` · `Discharging\n` · `Not charging\n` · `Full\n`) |
| 2 | `parseStatus` | 모르는 글자 → `unknown`: test_power 파라미터의 소문자 `charging\n`, `Bogus\n`, 빈 값, 꼬리 공백 `Charging \n` |
| 3 | `statusName` | 다섯 enum의 왕복(`parseStatus(statusName(s)) == s`) |
| 4 | `parseCapacity` | design 끝 조건 1의 여섯 — `100\n`→100 · `0`→0 · `105`→100 · `-3`→0 · 빈 값→null · `abc`→null |
| 5 | `parseCapacity` | 그 밖 — `50\n`→50 · `15\n`→15 · `12abc`→null · `\n`→null · `99999999999`→null(확정 14) |
| 6 | `counts` | test_power의 모양(확정 2) — 꺼진 `test_battery`(`Battery` · `0` · 없음)→false, 켜진 것(`1`)→true, `Mains` · `USB`→false |
| 7 | `counts` | 실기의 모양 — `present` 없음→true, `scope` `System`→true · `Device`→false · `Unknown`→true, 줄바꿈 없는 `Battery`→true |
| 8 | `pick` | 빈 목록→null, 하나, `BAT1` · `BAT0`→`BAT0`, `BAT0` · `BAT1`→`BAT0` |
| 9 | `class` | `plugged` — `Charging` 5 · `Full` 100 · `Not charging` 10 · `Charging` 잔량 모름 |
| 10 | `class` | 경계 — `Discharging` 15→`low` · 16→`normal` · 0→`low` · 100→`normal` |
| 11 | `class` | 모름 — `Discharging` 잔량 모름→`normal` · `Unknown` 잔량 모름→`normal` · `Unknown` 50→`normal` · `Unknown` 10→`low`(확정 10) |
| 12 | `cellText` | 넉 자 넷 — `100%` · ` 85%` · `  5%` · `  ?%` |
| 13 | `cellText` | 0~100 전부 넉 자이고 끝이 `%`이고 숫자를 되읽으면 같은 값, 그리고 255→`255%` |
| 14 | `ueventIsPowerSupply` | power_supply의 것 — test_power의 `test_ac` `change`(design 확인 4), ACPI `BAT0`의 `add` · `remove`(확인 6) |
| 15 | `ueventIsPowerSupply` | 아닌 것 — 입력 장치 `add`, `test_battery`가 등록하는 thermal zone의 `add`(확인 7), `SUBSYSTEM` 필드가 없는 머리만, 빈 datagram |
| 16 | `pollTimeout` | 다섯 경우 — 기한 전(1000, 61000)→60000 · 기한(61000, 61000)→0 · 기한 뒤(70000, 61000)→0 · 배터리 없음(5, null)→-1 · `c_int` 넘침(0, `maxInt(i64)`)→`maxInt(c_int)`. 그리고 `i64` 양 끝값 둘 |
| 17 | 상수 | `PERIOD_MS` 60000 · `LOW_MAX` 15 · `CELL_LEN` 4 — design의 수와 같다 |

uevent의 바이트는 커널 `kobject_uevent_env`가 짓는 모양(머리 `ACTION@DEVPATH` 뒤에 NUL로 나뉜 `KEY=value`)을 손으로 적은 것이다. 게스트에서
떠 온 글자가 아니다 — BS-M1이 게스트에서 볼 때 다르면 그 plan이 이 검사를 고친다.

### 2-2. 새 파일

아래 블록을 글자 그대로 Write로 넣는다.

`terminal/src/battery_test.zig`:

```zig
const std = @import("std");
const battery = @import("battery.zig");

// 배터리 칸의 순수한 층을 호스트에서 본다(BS-M0). 입력은 sysfs 파일과 uevent의 바이트를
// 글자로 적은 것이다 — 파일의 모양은 `docs/plans/2026-10-08-tars-battery-status-bs-m0.md`의
// 확정 2, 검사 번호는 그 plan의 Task 2 표와 같다.

fn expectStatus(bytes: []const u8, want: battery.Status) !void {
    const got = battery.parseStatus(bytes);
    if (got == want) return;
    std.debug.print("FAIL: parseStatus({any}) = .{s}, want .{s}\n", .{ bytes, @tagName(got), @tagName(want) });
    return error.WrongStatus;
}

fn expectCapacity(bytes: []const u8, want: ?u8) !void {
    const got = battery.parseCapacity(bytes);
    if (std.meta.eql(got, want)) return;
    std.debug.print("FAIL: parseCapacity({any}) = {?d}, want {?d}\n", .{ bytes, got, want });
    return error.WrongCapacity;
}

fn expectCounts(kind: []const u8, present: ?[]const u8, scope: ?[]const u8, want: bool) !void {
    const got = battery.counts(kind, present, scope);
    if (got == want) return;
    std.debug.print("FAIL: counts({any}, {any}, {any}) = {}, want {}\n", .{ kind, present, scope, got, want });
    return error.WrongCounts;
}

fn expectPick(names: []const []const u8, want: ?[]const u8) !void {
    const got = battery.pick(names);
    const same = if (got == null or want == null) got == null and want == null else std.mem.eql(u8, got.?, want.?);
    if (same) return;
    std.debug.print("FAIL: pick({d} names) = {?s}, want {?s}\n", .{ names.len, got, want });
    return error.WrongPick;
}

fn expectClass(status: battery.Status, capacity: ?u8, want: battery.Class) !void {
    const got = battery.class(status, capacity);
    if (got == want) return;
    std.debug.print("FAIL: class(.{s}, {?d}) = .{s}, want .{s}\n", .{ @tagName(status), capacity, @tagName(got), @tagName(want) });
    return error.WrongClass;
}

fn expectCell(capacity: ?u8, want: []const u8) !void {
    var buf: [battery.CELL_LEN]u8 = undefined;
    const got = battery.cellText(capacity, &buf);
    if (std.mem.eql(u8, got, want)) return;
    std.debug.print("FAIL: cellText({?d}) = \"{s}\", want \"{s}\"\n", .{ capacity, got, want });
    return error.WrongCell;
}

fn expectUevent(msg: []const u8, want: bool) !void {
    const got = battery.ueventIsPowerSupply(msg);
    if (got == want) return;
    std.debug.print("FAIL: ueventIsPowerSupply({any}) = {}, want {}\n", .{ msg, got, want });
    return error.WrongUevent;
}

fn expectTimeout(now_ms: i64, due_ms: ?i64, want: c_int) !void {
    const got = battery.pollTimeout(now_ms, due_ms);
    if (got == want) return;
    std.debug.print("FAIL: pollTimeout({d}, {?d}) = {d}, want {d}\n", .{ now_ms, due_ms, got, want });
    return error.WrongTimeout;
}

pub fn main() !void {
    // ── 검사 1: sysfs의 다섯 글자 ───────────────────────────────────────
    // 커널이 `status` 파일에 쓰는 글자 그대로다. 줄바꿈이 붙어 온다.
    try expectStatus("Unknown\n", .unknown);
    try expectStatus("Charging\n", .charging);
    try expectStatus("Discharging\n", .discharging);
    try expectStatus("Not charging\n", .not_charging);
    try expectStatus("Full\n", .full);
    std.debug.print("battery_test: 1. the five status words OK\n", .{});

    // ── 검사 2: 모르는 글자는 unknown이다 ──────────────────────────────
    // 소문자는 test_power 파라미터의 글자이지 파일의 글자가 아니다. 빈 값은 읽기가
    // 실패했을 때 main.zig가 넘기는 것이다.
    try expectStatus("charging\n", .unknown);
    try expectStatus("Bogus\n", .unknown);
    try expectStatus("", .unknown);
    try expectStatus("Charging \n", .unknown);
    std.debug.print("battery_test: 2. unknown status words are unknown OK\n", .{});

    // ── 검사 3: statusName과 parseStatus의 왕복 ─────────────────────────
    // battery.zig의 ALL_STATUS가 하나를 빠뜨리면 그 값이 unknown으로 돌아와 여기서 빨개진다.
    for ([_]battery.Status{ .unknown, .charging, .discharging, .not_charging, .full }) |s| {
        try expectStatus(battery.statusName(s), s);
    }
    std.debug.print("battery_test: 3. statusName round-trips through parseStatus OK\n", .{});

    // ── 검사 4: capacity — design 끝 조건 1의 여섯 ──────────────────────
    try expectCapacity("100\n", 100);
    try expectCapacity("0", 0);
    try expectCapacity("105", 100);
    try expectCapacity("-3", 0);
    try expectCapacity("", null);
    try expectCapacity("abc", null);
    std.debug.print("battery_test: 4. capacity clamps to 0..100 and refuses non-integers OK\n", .{});

    // ── 검사 5: capacity — 그 밖 ───────────────────────────────────────
    try expectCapacity("50\n", 50);
    try expectCapacity("15\n", 15);
    try expectCapacity("12abc", null);
    try expectCapacity("\n", null);
    try expectCapacity("99999999999", null);
    std.debug.print("battery_test: 5. capacity edge texts OK\n", .{});

    // ── 검사 6: counts — test_power의 장치 셋 ──────────────────────────
    // test_battery에는 scope 파일이 없고, test_ac · test_usb에는 present 파일이 없다.
    try expectCounts("Battery\n", "0\n", null, false);
    try expectCounts("Battery\n", "1\n", null, true);
    try expectCounts("Mains\n", null, null, false);
    try expectCounts("USB\n", null, null, false);
    std.debug.print("battery_test: 6. counts on test_power's three supplies OK\n", .{});

    // ── 검사 7: counts — 실기의 모양 ───────────────────────────────────
    // ACPI 배터리는 scope를 안 내고, 주변기기 배터리는 Device다.
    try expectCounts("Battery\n", null, null, true);
    try expectCounts("Battery\n", "1\n", "System\n", true);
    try expectCounts("Battery\n", "1\n", "Device\n", false);
    try expectCounts("Battery\n", "1\n", "Unknown\n", true);
    try expectCounts("Battery", "1", null, true);
    std.debug.print("battery_test: 7. counts on present, scope and missing files OK\n", .{});

    // ── 검사 8: pick — 바이트 순서로 첫째 ──────────────────────────────
    {
        const none = [_][]const u8{};
        const one = [_][]const u8{"test_battery"};
        const reversed = [_][]const u8{ "BAT1", "BAT0" };
        const ordered = [_][]const u8{ "BAT0", "BAT1" };
        try expectPick(&none, null);
        try expectPick(&one, "test_battery");
        try expectPick(&reversed, "BAT0");
        try expectPick(&ordered, "BAT0");
    }
    std.debug.print("battery_test: 8. pick takes the first name in byte order OK\n", .{});

    // ── 검사 9: class — 꽂혀 있으면 잔량과 무관하게 plugged ──────────────
    try expectClass(.charging, 5, .plugged);
    try expectClass(.full, 100, .plugged);
    try expectClass(.not_charging, 10, .plugged);
    try expectClass(.charging, null, .plugged);
    std.debug.print("battery_test: 9. charging, full and not charging are plugged OK\n", .{});

    // ── 검사 10: class — 문턱 15의 양쪽 ────────────────────────────────
    // `<=`가 `<`로 바뀌면 15가, 문턱이 바뀌면 16이 빨개진다.
    try expectClass(.discharging, 15, .low);
    try expectClass(.discharging, 16, .normal);
    try expectClass(.discharging, 0, .low);
    try expectClass(.discharging, 100, .normal);
    std.debug.print("battery_test: 10. low is 15 and below while discharging OK\n", .{});

    // ── 검사 11: class — 상태나 잔량을 모를 때 ──────────────────────────
    try expectClass(.discharging, null, .normal);
    try expectClass(.unknown, null, .normal);
    try expectClass(.unknown, 50, .normal);
    try expectClass(.unknown, 10, .low);
    std.debug.print("battery_test: 11. unknown status or capacity OK\n", .{});

    // ── 검사 12: cellText — 넉 자 넷 ──────────────────────────────────
    try expectCell(100, "100%");
    try expectCell(85, " 85%");
    try expectCell(5, "  5%");
    try expectCell(null, "  ?%");
    std.debug.print("battery_test: 12. the four cell texts OK\n", .{});

    // ── 검사 13: cellText — 0~100 전부 넉 자이고 %의 자리가 같다 ─────────
    {
        var v: u8 = 0;
        while (v <= 100) : (v += 1) {
            var buf: [battery.CELL_LEN]u8 = undefined;
            const got = battery.cellText(v, &buf);
            const digits = std.mem.trimStart(u8, got[0 .. got.len - 1], " ");
            const back = std.fmt.parseInt(u8, digits, 10) catch 255;
            if (got.len != battery.CELL_LEN or got[battery.CELL_LEN - 1] != '%' or back != v) {
                std.debug.print("FAIL: cellText({d}) = \"{s}\"\n", .{ v, got });
                return error.WrongCell;
            }
        }
        try expectCell(255, "255%");
    }
    std.debug.print("battery_test: 13. every capacity fills exactly four cells OK\n", .{});

    // ── 검사 14: uevent — power_supply의 것 ────────────────────────────
    // test_power의 battery_present를 쓰면 uevent는 test_battery가 아니라 test_ac에서 온다.
    try expectUevent("change@/devices/virtual/power_supply/test_ac\x00ACTION=change\x00" ++
        "DEVPATH=/devices/virtual/power_supply/test_ac\x00SUBSYSTEM=power_supply\x00" ++
        "POWER_SUPPLY_NAME=test_ac\x00POWER_SUPPLY_TYPE=Mains\x00POWER_SUPPLY_ONLINE=1\x00SEQNUM=812\x00", true);
    try expectUevent("add@/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0C0A:00/power_supply/BAT0\x00ACTION=add\x00" ++
        "DEVPATH=/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0C0A:00/power_supply/BAT0\x00SUBSYSTEM=power_supply\x00" ++
        "POWER_SUPPLY_NAME=BAT0\x00SEQNUM=1200\x00", true);
    try expectUevent("remove@/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0C0A:00/power_supply/BAT0\x00ACTION=remove\x00" ++
        "DEVPATH=/devices/LNXSYSTM:00/LNXSYBUS:00/PNP0C0A:00/power_supply/BAT0\x00SUBSYSTEM=power_supply\x00SEQNUM=1201\x00", true);
    std.debug.print("battery_test: 14. power_supply uevents from any device and action OK\n", .{});

    // ── 검사 15: uevent — 아닌 것 ─────────────────────────────────────
    // thermal zone은 test_battery가 등록하지만 SUBSYSTEM이 thermal이다. 머리만 있는 것은
    // 경로에 power_supply가 있어도 아니다.
    try expectUevent("add@/devices/platform/i8042/serio1/input/input3/event3\x00ACTION=add\x00" ++
        "DEVPATH=/devices/platform/i8042/serio1/input/input3/event3\x00SUBSYSTEM=input\x00DEVNAME=input/event3\x00", false);
    try expectUevent("add@/devices/virtual/thermal/thermal_zone0\x00ACTION=add\x00" ++
        "DEVPATH=/devices/virtual/thermal/thermal_zone0\x00SUBSYSTEM=thermal\x00", false);
    try expectUevent("change@/devices/virtual/power_supply/test_ac", false);
    try expectUevent("", false);
    std.debug.print("battery_test: 15. other uevents are not power_supply OK\n", .{});

    // ── 검사 16: pollTimeout ──────────────────────────────────────────
    // 주기 경로는 게이트가 못 본다(design 결정 11). 이 다섯이 그 길의 검증이다.
    try expectTimeout(1_000, 61_000, 60_000);
    try expectTimeout(61_000, 61_000, 0);
    try expectTimeout(70_000, 61_000, 0);
    try expectTimeout(5, null, -1);
    try expectTimeout(0, std.math.maxInt(i64), std.math.maxInt(c_int));
    try expectTimeout(std.math.minInt(i64), std.math.maxInt(i64), std.math.maxInt(c_int));
    try expectTimeout(std.math.maxInt(i64), std.math.minInt(i64), 0);
    std.debug.print("battery_test: 16. poll timeout before, at and after the due time, without a battery and past c_int OK\n", .{});

    // ── 검사 17: design의 수 ──────────────────────────────────────────
    if (battery.PERIOD_MS != 60_000 or battery.LOW_MAX != 15 or battery.CELL_LEN != 4) {
        std.debug.print("FAIL: PERIOD_MS={d} LOW_MAX={d} CELL_LEN={d}, want 60000 15 4\n", .{ battery.PERIOD_MS, battery.LOW_MAX, battery.CELL_LEN });
        return error.WrongConstants;
    }
    std.debug.print("battery_test: 17. period 60s, low at 15, four cells OK\n", .{});

    std.debug.print("battery_test: all checks passed\n", .{});
}
```

### 2-3. `terminal/build.zig` — 편집 둘

Edit 도구로 넣는다. 각 `old_string`은 파일에 정확히 한 번 있다.

E1 — `old_string`:

```zig
    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
```

`new_string`:

```zig
    // battery_test도 호스트에서 돈다(BS-M0). `clipboard_test`와 같은 자리다 —
    // sysfs 글자 · uevent · poll timeout의 순수 계산이라 libc도 번역도 필요 없다.
    // 파일을 여는 것은 `main.zig`이고(BS-M1) 게이트가 본다.
    const battery_test_mod = b.createModule(.{
        .root_source_file = b.path("src/battery_test.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    const battery_test = b.addExecutable(.{
        .name = "battery_test",
        .root_module = battery_test_mod,
    });
    b.installArtifact(battery_test);

    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
```

E2 — `old_string`:

```zig
    test_step.dependOn(&b.addRunArtifact(logline_test).step);
```

`new_string`:

```zig
    test_step.dependOn(&b.addRunArtifact(logline_test).step);
    test_step.dependOn(&b.addRunArtifact(battery_test).step);
```

### 2-4. 넣고 확인

먼저 `build.zig`의 diff가 design 끝 조건 2의 모양인지 본다. 같은 모양의 줄이 열셋 늘어선 자리라 다른 줄을 지우거나 바꾸기 쉽다(IS-M0 실측 4).

```bash
cd /Users/dp/Repository/tars-linux && git diff --stat terminal/build.zig
git diff terminal/build.zig | rg '^-'
git diff terminal/build.zig | rg '^\+.*dependOn'
```

기대.

```
 terminal/build.zig | 15 +++++++++++++++
 1 file changed, 15 insertions(+)
--- a/terminal/build.zig
+    test_step.dependOn(&b.addRunArtifact(battery_test).step);
```

`rg '^-'`는 `--- a/terminal/build.zig` 머리 한 줄뿐이어야 한다. 그다음 컨테이너에서 호스트 검사를 돌린다. 처음 빌드는 vendor가 이미 있으면
1~2분이다.

```bash
cd /Users/dp/Repository/tars-linux
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer bash -c \
  'zig build test > /tmp/t.log 2>&1; echo "test exit=$?"; grep -aE "^src/.*error" /tmp/t.log | head -n 20; grep -a "battery_test:" /tmp/t.log' \
  > /tmp/run/bs0/task2.out 2>&1
rmdir /tmp/run/docker.lock
cat /tmp/run/bs0/task2.out
```

기대: `test exit=0`, 에러 줄 없음, 그리고 `battery_test: 1.` ~ `battery_test: 17.`의 열일곱 줄과 `battery_test: all checks passed`.

`src/battery.zig:…: error:`나 `src/battery_test.zig:…: error:`가 나오면 컴파일 에러다(확정 13). 그 줄이 가리키는 자리만 고쳐 다시 돌리고,
고친 줄의 전과 후를 보고에 적는다. `FAIL:` 줄이 나오면 동작이 기대와 다른 것이니 고치지 말고 멈추고 그 줄을 보고한다.

### 2-5. mutation 둘

검사가 실제로 그 자리를 보는지 본다. 저장소 파일은 안 건드린다 — 고친 사본을 `-v`로 덮는다(lessons "범용 명령"의 mutation 절).

```bash
cd /Users/dp/Repository/tars-linux && mkdir -p /tmp/run/bs0/mut
cp terminal/src/battery.zig /tmp/run/bs0/mut/m1.zig && sd -F 'c <= LOW_MAX' 'c < LOW_MAX' /tmp/run/bs0/mut/m1.zig
cp terminal/src/battery.zig /tmp/run/bs0/mut/m2.zig && sd -F 'orelse return -1' 'orelse return 0' /tmp/run/bs0/mut/m2.zig
diff terminal/src/battery.zig /tmp/run/bs0/mut/m1.zig; diff terminal/src/battery.zig /tmp/run/bs0/mut/m2.zig
for m in m1 m2; do
  until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
  docker run --rm -v "$PWD":/workspace -v /tmp/run/bs0/mut/$m.zig:/workspace/terminal/src/battery.zig:ro \
    -w /workspace/terminal tars-devcontainer bash -c \
    'zig build test > /tmp/t.log 2>&1; echo "test exit=$?"; grep -a "FAIL:" /tmp/t.log' > /tmp/run/bs0/mut/$m.out 2>&1
  rmdir /tmp/run/docker.lock
  echo "== $m"; cat /tmp/run/bs0/mut/$m.out
done
```

기대. 두 `diff`가 각각 한 줄씩 바뀐 것을 보이고, 판마다 종료 코드가 0이 아니고 `FAIL:` 줄이 하나다.

```
== m1
test exit=1
FAIL: class(.discharging, 15) = .normal, want .low
== m2
test exit=1
FAIL: pollTimeout(5, null) = 0, want -1
```

`test exit=`의 수는 zig build가 정한다(1이 아닐 수 있다). 0이 아니면 된다. `-v`로 파일 하나를 덮으면 저장소의 파일은 그대로다 —
끝나고 `git status --short terminal/src/`가 새 파일 둘(`??`)만 보이는지 본다.

## Task 3: 커널 — `CONFIG_TEST_POWER=y`와 내장 cmdline

design 결정 9의 겹 1. 두 줄을 Edit로 바꾼다.

E1 — `old_string`:

```
CONFIG_CMDLINE="mac80211_hwsim.radios=0"
```

`new_string`:

```
CONFIG_CMDLINE="mac80211_hwsim.radios=0 test_power.battery_present=false"
```

E2 — `old_string`:

```
# CONFIG_TEST_POWER is not set
```

`new_string`:

```
CONFIG_TEST_POWER=y
```

값은 반드시 `false`다. `0`이면 커널이 조용히 무시해서 모든 부팅에 50%짜리 배터리가 생긴다(design 확인 2).

1. 고친 두 줄을 본다.

   ```bash
   cd /Users/dp/Repository/tars-linux && git diff --stat kernel/.config && git diff kernel/.config | rg '^[-+][^-+]'
   ```

   기대.

   ```
    kernel/.config | 4 ++--
    1 file changed, 2 insertions(+), 2 deletions(-)
   -CONFIG_CMDLINE="mac80211_hwsim.radios=0"
   +CONFIG_CMDLINE="mac80211_hwsim.radios=0 test_power.battery_present=false"
   -# CONFIG_TEST_POWER is not set
   +CONFIG_TEST_POWER=y
   ```

2. 빌드한다. `.config`가 바뀌었으므로 `build.sh`의 스탬프가 안 맞아 `olddefconfig`와 `make`를 돈다. `kernel/build`가 이미 있어서 바뀐
   설정에 걸린 파일만 다시 컴파일한다 — 몇 분이다. Bash 도구의 timeout을 600000으로 준다.

   ```bash
   cd /Users/dp/Repository/tars-linux
   until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
   { time docker run --rm -v "$PWD":/workspace -w /workspace/kernel tars-devcontainer ./build.sh > /tmp/run/bs0/kbuild1.log 2>&1 ; } 2> /tmp/run/bs0/kbuild1.time; echo "exit=$?"
   rmdir /tmp/run/docker.lock
   tail -n 3 /tmp/run/bs0/kbuild1.log; cat /tmp/run/bs0/kbuild1.time
   ```

   기대: `exit=0`, 로그 끝이 `Kernel: arch/x86/boot/bzImage is ready` 꼴. `skipping make`는 안 나온다.

3. 되접기(`docs/decisions/project_kernel_config.md`). `olddefconfig`가 무엇을 더했는지 본다.

   ```bash
   cd /Users/dp/Repository/tars-linux && diff kernel/.config kernel/build/.config; echo "diff exit=$?"
   ```

   기대: 출력 없이 `diff exit=0`(확정 6 — 딸려 오는 기호가 없다).

   줄이 나오면 그것이 test_power가 들여온 것이다. 그때는 아래로 되접고 다시 빌드한 뒤 `diff`가 비는 것을 보고, 나온 줄을 전부 보고에
   적는다(design 결정 9가 "되접기 diff가 그것을 확정한다"고 남겨 둔 자리다). 멈추지는 않는다.

   ```bash
   cd /Users/dp/Repository/tars-linux && cp kernel/build/.config kernel/.config
   # 그다음 2의 빌드를 한 번 더 돌리고 3의 diff를 다시 본다.
   ```

4. 고정점을 확인한다. 같은 `build.sh`를 한 번 더 돌린다. 입력이 같으므로 빌드를 건너뛰어야 한다.

   ```bash
   cd /Users/dp/Repository/tars-linux
   until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
   docker run --rm -v "$PWD":/workspace -w /workspace/kernel tars-devcontainer ./build.sh > /tmp/run/bs0/kbuild2.log 2>&1; echo "exit=$?"
   rmdir /tmp/run/docker.lock
   cat /tmp/run/bs0/kbuild2.log
   diff kernel/.config kernel/build/.config; echo "diff exit=$?"
   ```

   기대: `exit=0`, 로그 한 줄 `kernel: bzImage matches .config and build.sh, skipping make`, `diff exit=0`.

5. 늘어난 기호를 센다(design 끝 조건 3). 비교 기준은 HEAD의 `.config`다.

   ```bash
   cd /Users/dp/Repository/tars-linux && git diff kernel/.config | rg -c '^\+CONFIG_[A-Z0-9_]+=y$'
   git diff kernel/.config | rg '^[-+](# )?CONFIG_' | rg -v 'CONFIG_CMDLINE=' | rg -c .
   ```

   기대: 첫 줄 `1`(`TEST_POWER` 하나만 `=y`가 됐다), 둘째 줄 `2`(`-# CONFIG_TEST_POWER is not set` · `+CONFIG_TEST_POWER=y`). 3에서 되접기를
   했다면 그 수가 늘어난 만큼 다르다 — 그 수와 줄을 보고에 적는다.

6. 블랙리스트가 맞출 이름이 커널에 있다(확정 7).

   ```bash
   cd /Users/dp/Repository/tars-linux && rg -n ' t test_power_init$' kernel/build/System.map
   ```

   기대: 한 줄(`ffffffff…  t test_power_init` 꼴). 없으면 limine의 블랙리스트가 조용히 아무것도 안 막는다(design 위험 3) — 멈추고
   `rg -n test_power_init kernel/build/System.map`의 출력을 보고한다.

## Task 4: `boot/limine.conf` · `init/src/disk_test.zig`

design 결정 9의 겹 2와, 그 줄을 글자 그대로 베껴 둔 검사의 사본(확정 4).

`boot/limine.conf` E1 — `old_string`:

```
    cmdline: console=ttyS0
```

`new_string`:

```
    cmdline: console=ttyS0 initcall_blacklist=test_power_init
```

`init/src/disk_test.zig` E1 — `old_string`:

```zig
            \\    cmdline: console=ttyS0
            \\
        ;
        const want =
```

`new_string`:

```zig
            \\    cmdline: console=ttyS0 initcall_blacklist=test_power_init
            \\
        ;
        const want =
```

`init/src/disk_test.zig` E2 — `old_string`:

```zig
            \\    cmdline: console=ttyS0 tars.installed
```

`new_string`:

```zig
            \\    cmdline: console=ttyS0 initcall_blacklist=test_power_init tars.installed
```

`limine.conf`의 맨 위 주석은 안 고친다. cmdline 줄에 무엇이 왜 있는지는 design 결정 9가 말하고, 이 파일의 주석은 `serial: yes`의 이유다.

1. diff를 본다.

   ```bash
   cd /Users/dp/Repository/tars-linux && git diff --stat boot/limine.conf init/src/disk_test.zig
   git diff boot/limine.conf init/src/disk_test.zig | rg '^[-+][^-+]'
   ```

   기대.

   ```
    boot/limine.conf       | 2 +-
    init/src/disk_test.zig | 4 ++--
    2 files changed, 3 insertions(+), 3 deletions(-)
   -    cmdline: console=ttyS0
   +    cmdline: console=ttyS0 initcall_blacklist=test_power_init
   -            \\    cmdline: console=ttyS0
   +            \\    cmdline: console=ttyS0 initcall_blacklist=test_power_init
   -            \\    cmdline: console=ttyS0 tars.installed
   +            \\    cmdline: console=ttyS0 initcall_blacklist=test_power_init tars.installed
   ```

2. install 판정 9의 grep이 새 cmdline에도 맞는지 컨테이너의 grep으로 본다. 아래 파일을 Write로 `/tmp/run/bs0/install_re.sh`에 만든다.

   ```bash
   #!/usr/bin/env bash
   # BS-M0 Task 4 — install/check.sh 판정 9 · 부팅 4의 grep이 새 limine cmdline에도 맞는가.
   # 줄은 커널이 찍는 모양 그대로다 — 내장 cmdline이 앞이고(확정 5) 표지가 끝이다.
   CR=$'\r'
   for line in \
     '[    0.000000] Kernel command line: mac80211_hwsim.radios=0 test_power.battery_present=false console=ttyS0 initcall_blacklist=test_power_init tars.installed' \
     "[    0.000000] Kernel command line: mac80211_hwsim.radios=0 test_power.battery_present=false console=ttyS0 initcall_blacklist=test_power_init tars.installed${CR}" \
     '[    0.000000] Kernel command line: mac80211_hwsim.radios=0 test_power.battery_present=false console=ttyS0 initcall_blacklist=test_power_init' \
     '[    0.000000] Kernel command line: console=ttyS0 tars.installedx'; do
     if printf '%s\n' "$line" | grep -aE "Kernel command line: .*tars\.installed( |${CR}|\$)" >/dev/null; then
       echo "match   ${line%"$CR"}"
     else
       echo "nomatch ${line%"$CR"}"
     fi
   done
   ```

   ```bash
   cd /Users/dp/Repository/tars-linux
   until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
   docker run --rm -v /tmp/run/bs0:/tmp/run/bs0 tars-devcontainer bash /tmp/run/bs0/install_re.sh; echo "exit=$?"
   rmdir /tmp/run/docker.lock
   ```

   기대: 앞의 둘이 `match`, 뒤의 둘이 `nomatch`, `exit=0`.

3. init의 호스트 검사(`disk_test` 검사 10).

   ```bash
   cd /Users/dp/Repository/tars-linux
   until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
   docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c \
     'zig build test > /tmp/t.log 2>&1; echo "test exit=$?"; grep -a "disk_test:" /tmp/t.log | tail -n 2' > /tmp/run/bs0/task4.out 2>&1
   rmdir /tmp/run/docker.lock
   cat /tmp/run/bs0/task4.out
   ```

   기대: `test exit=0`와 `disk_test: signatures, sizes, arguments, labels, the YES gate and the ESP conf hold`.

## Task 5: `wifi/check.sh` 검사 1

design 결정 9의 끝 문단. 줄 전체 비교를 낱말 비교로 바꾼다. Edit 둘.

E1 — `old_string`:

```bash
# 드러난다(nic 체인 검사 1과 같은 자리). 내장 cmdline은 글자 그대로 본다 — 빠지면
# 모든 부팅에 가짜 라디오 둘이 생긴다(결정 2). 부팅 C가 그 결과를 따로 본다.
```

`new_string`:

```bash
# 드러난다(nic 체인 검사 1과 같은 자리). 내장 cmdline에 hwsim의 낱말이 있는지 본다 — 빠지면
# 모든 부팅에 가짜 라디오 둘이 생긴다(결정 2). 부팅 C가 그 결과를 따로 본다. 줄 전체를 안
# 보는 것은 같은 줄에 battery 체인의 낱말도 있기 때문이다(BS design 결정 9).
```

E2 — `old_string`:

```bash
if ! grep -x 'CONFIG_CMDLINE="mac80211_hwsim.radios=0"' "$CONFIG" >/dev/null; then
```

`new_string`:

```bash
if ! grep -E '^CONFIG_CMDLINE="([^"]* )?mac80211_hwsim\.radios=0( [^"]*)?"$' "$CONFIG" >/dev/null; then
```

그 아래의 `echo "FAIL: the built-in cmdline no longer turns hwsim's radios off"`는 그대로 둔다 — 뜻이 같다.

1. diff를 본다.

   ```bash
   cd /Users/dp/Repository/tars-linux && git diff --stat wifi/check.sh && git diff wifi/check.sh | rg '^-'
   ```

   기대: `1 file changed, 4 insertions(+), 3 deletions(-)`. `rg '^-'`는 머리 `--- a/wifi/check.sh`와 위의 `old_string` 세 줄뿐이다.

2. 바꾼 grep이 옛 줄과 새 줄 둘 다 통과하고, 틀린 줄은 거르는지 컨테이너의 grep으로 본다. 아래 파일을 Write로 `/tmp/run/bs0/wifi_re.sh`에
   만든다. 마지막 두 줄은 저장소의 실제 `kernel/.config`에 두 체인의 regex를 대 본다(battery의 것은 BS-M1이 쓸 글자다).

   ```bash
   #!/usr/bin/env bash
   # BS-M0 Task 5 — wifi 검사 1의 새 grep과 battery 체인이 쓸 grep을 줄 몇 개와 실제 .config에 대 본다.
   WIFI_RE='^CONFIG_CMDLINE="([^"]* )?mac80211_hwsim\.radios=0( [^"]*)?"$'
   BAT_RE='^CONFIG_CMDLINE="([^"]* )?test_power\.battery_present=false( [^"]*)?"$'
   for line in \
     'CONFIG_CMDLINE="mac80211_hwsim.radios=0"' \
     'CONFIG_CMDLINE="mac80211_hwsim.radios=0 test_power.battery_present=false"' \
     'CONFIG_CMDLINE="test_power.battery_present=false mac80211_hwsim.radios=0"' \
     'CONFIG_CMDLINE="a mac80211_hwsim.radios=0 b"' \
     'CONFIG_CMDLINE="mac80211_hwsim.radios=3"' \
     'CONFIG_CMDLINE="mac80211_hwsim.radios=00"' \
     'CONFIG_CMDLINE="xmac80211_hwsim.radios=0"' \
     'CONFIG_CMDLINE="test_power.battery_present=false"' \
     '# CONFIG_CMDLINE is not set'; do
     if printf '%s\n' "$line" | grep -E "$WIFI_RE" >/dev/null; then echo "match   $line"; else echo "nomatch $line"; fi
   done
   grep -E "$WIFI_RE" /workspace/kernel/.config >/dev/null && echo "wifi regex finds its word in kernel/.config"
   grep -E "$BAT_RE" /workspace/kernel/.config >/dev/null && echo "battery regex finds its word in kernel/.config"
   ```

   ```bash
   cd /Users/dp/Repository/tars-linux
   until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
   docker run --rm -v "$PWD":/workspace -v /tmp/run/bs0:/tmp/run/bs0 tars-devcontainer bash /tmp/run/bs0/wifi_re.sh; echo "exit=$?"
   rmdir /tmp/run/docker.lock
   ```

   기대(plan을 쓸 때 호스트 `rg`로 같은 regex를 대 본 결과와 같아야 한다).

   ```
   match   CONFIG_CMDLINE="mac80211_hwsim.radios=0"
   match   CONFIG_CMDLINE="mac80211_hwsim.radios=0 test_power.battery_present=false"
   match   CONFIG_CMDLINE="test_power.battery_present=false mac80211_hwsim.radios=0"
   match   CONFIG_CMDLINE="a mac80211_hwsim.radios=0 b"
   nomatch CONFIG_CMDLINE="mac80211_hwsim.radios=3"
   nomatch CONFIG_CMDLINE="mac80211_hwsim.radios=00"
   nomatch CONFIG_CMDLINE="xmac80211_hwsim.radios=0"
   nomatch CONFIG_CMDLINE="test_power.battery_present=false"
   nomatch # CONFIG_CMDLINE is not set
   wifi regex finds its word in kernel/.config
   battery regex finds its word in kernel/.config
   exit=0
   ```

3. 진입 검사 셋을 고친 체인에 대 본다(lessons "게이트를 돌리고 읽는 법"의 명령 그대로, 컨테이너 안에서).

   ```bash
   cd /Users/dp/Repository/tars-linux
   until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
   docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
     require_build_steps ./wifi/check.sh && require_no_early_exit_pipe ./wifi/check.sh &&
     require_explicit_nic ./wifi/check.sh && echo ENTRY-OK'
   rmdir /tmp/run/docker.lock
   ```

   기대: `ENTRY-OK`.

## Task 6: 사본 실측 셋과 QEMU 장치 목록

design 끝 조건 4. 게스트에 한 글자도 안 친다 — wifi · audio 체인처럼 설정 디스크의 `services.d/probe`가 sysfs를 읽어 시리얼에 찍는다
(`audio/probe.sh`의 머리 주석이 그 길을 설명한다). 부팅은 셋이다.

| 부팅 | 띄우는 법 | 빌린 곳 | 볼 것 |
|---|---|---|---|
| `k1` | `-kernel` · `-append "console=ttyS0"` | `wifi/check.sh`의 `boot()` | `test_battery/present`가 `0` |
| `k2` | `-kernel` · `-append "console=ttyS0 test_power.battery_present=true"` | 같다 | `present`가 `1` |
| `iso` | q35 · OVMF · `-cdrom out/tars.iso` · 설정 디스크는 NVMe | `machine/check.sh`의 QEMU 줄 | `/sys/class/power_supply/`가 비었다 |

ISO 부팅의 설정 디스크를 NVMe에 두는 이유. ISO로 뜬 기계는 `tars.installed`가 없어서 init이 디스크 전체만 후보로 보고, machine 체인이 같은
모양(`-device nvme`, 라벨 `tars-machine`)으로 뜬다. 라벨은 `tars-`로 시작해야 init이 설정 디스크로 본다.

1. 아래 두 파일을 Write로 만든다.

   `/tmp/run/bs0/probe.sh`:

   ```bash
   #!/usr/bin/bash
   # BS-M0 Task 6의 게스트 쪽 — 설정 디스크의 services.d/probe로 들어간다(audio/probe.sh와 같은 자리).
   # sysfs의 power_supply와 test_power 파라미터를 읽어 시리얼에 찍고 잠든다. 감독자가 끝난
   # 서비스를 다시 띄우므로 나가지 않는다.
   exec > /dev/console 2>&1 < /dev/null
   say() { echo "bs0-probe: $*"; }
   flat() { tr '\n' ' ' | sed 's/ $//'; }
   say "cmdline [$(cat /proc/cmdline)]"
   say "supplies [$(ls /sys/class/power_supply/ 2>&1 | flat)]"
   for d in /sys/class/power_supply/*; do
     [ -e "$d" ] || continue
     n="${d##*/}"
     for f in type present scope status capacity; do
       if [ -e "$d/$f" ]; then v="$(cat "$d/$f" 2>&1)"; else v="-"; fi
       say "$n $f [$v]"
     done
   done
   say "params [$(ls /sys/module/test_power/parameters 2>&1 | flat)]"
   say "done"
   exec sleep 100000
   ```

   `/tmp/run/bs0/measure.sh`:

   ```bash
   #!/usr/bin/env bash
   # BS-M0 Task 6 — 사본 실측 셋과 QEMU 장치 목록. 컨테이너 안에서 /workspace를 저장소로 두고 돈다.
   set -uo pipefail
   cd /workspace
   OUT=/tmp/run/bs0
   # $GUEST_MEM 하나 때문에 source한다(함수와 변수뿐이다).
   source ./gate_lib.sh

   (cd kernel && ./build.sh) || exit 1
   (cd init && zig build) || exit 1
   (cd terminal && ./prepare.sh) || exit 1
   (cd kernel && ./make_initrd.sh) || exit 1
   (cd boot && ./build.sh) || exit 1
   (cd boot && ./make_iso.sh) || exit 1

   # design 확인 10을 한 줄로 다시 본다.
   echo "qemu battery devices: $(qemu-system-x86_64 -device help 2>&1 | grep -i -E 'batt|power' | wc -l)"

   SEED="$(mktemp -d)"
   mkdir -p "$SEED/services.d"
   cp "$OUT/probe.sh" "$SEED/services.d/probe"
   chmod 0755 "$SEED/services.d/probe"
   DISK="$OUT/bs0.img"
   rm -f "$DISK"
   truncate -s 16M "$DISK"
   mkfs.ext2 -F -q -m 0 -L tars-bs0 -d "$SEED" "$DISK"
   rm -rf "$SEED"

   finish() {
     local pid="$1" log="$2" seconds="$3" i
     for i in $(seq 1 "$seconds"); do
       if grep -a 'bs0-probe: done' "$log" >/dev/null; then break; fi
       if ! kill -0 "$pid" 2>/dev/null; then break; fi
       sleep 1
     done
     kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
     echo "=== ${log##*/} ==="
     grep -a 'bs0-probe:' "$log" | tr -d '\r'
     echo "deliberately-report-errors lines: $(grep -ac 'deliberately report errors' "$log")"
     echo "kernel command line: $(grep -a 'Kernel command line:' "$log" | tr -d '\r' | sed 's/.*Kernel command line: //')"
   }

   # -nic none — 네트워크를 안 쓴다(require_explicit_nic와 같은 규칙).
   boot_kernel() {
     local name="$1" append="$2" log="$OUT/serial-$1.log"
     rm -f "$log"
     qemu-system-x86_64 \
       -nic none \
       -m "$GUEST_MEM" \
       -kernel kernel/build/arch/x86/boot/bzImage \
       -initrd kernel/initrd.cpio \
       -append "console=ttyS0${append}" \
       -vga none \
       -device virtio-gpu-pci \
       -display none \
       -drive file="$DISK",if=virtio,format=raw \
       -serial file:"$log" \
       -no-reboot &
     finish $! "$log" 90
   }

   boot_iso() {
     local log="$OUT/serial-iso.log" vars
     rm -f "$log"
     vars="$(mktemp)"
     cp /usr/share/OVMF/OVMF_VARS_4M.fd "$vars"
     qemu-system-x86_64 \
       -machine q35 \
       -nic none \
       -m "$GUEST_MEM" \
       -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
       -drive if=pflash,format=raw,unit=1,file="$vars" \
       -cdrom out/tars.iso \
       -drive file="$DISK",if=none,id=cfg,format=raw \
       -device nvme,drive=cfg,serial=tarscfg \
       -serial file:"$log" \
       -display none \
       -no-reboot &
     finish $! "$log" 240
     rm -f "$vars"
   }

   boot_kernel k1 ""
   boot_kernel k2 " test_power.battery_present=true"
   boot_iso
   ```

2. 돌린다. 빌드는 앞 Task들이 했으므로 대부분 건너뛰고(initrd · ISO는 다시 짓는다), 부팅 셋이 1~4분씩이다. 합해서 10분 안팎이라 Bash
   도구의 `run_in_background`로 돌리고 끝나면 출력을 본다.

   ```bash
   cd /Users/dp/Repository/tars-linux
   until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
   { time docker run --rm -v "$PWD":/workspace -v /tmp/run/bs0:/tmp/run/bs0 -w /workspace tars-devcontainer \
       bash /tmp/run/bs0/measure.sh > /tmp/run/bs0/measure.out 2>&1 ; } 2> /tmp/run/bs0/measure.time; echo "exit=$?"
   rmdir /tmp/run/docker.lock
   rg -a '^(qemu battery devices|===|bs0-probe:|deliberately|kernel command line)' /tmp/run/bs0/measure.out; cat /tmp/run/bs0/measure.time
   ```

3. 기대. 줄 순서는 아래와 같다. `…`는 값을 안 정한 자리이고 보고에 실제 값을 적는다.

   ```
   qemu battery devices: 0
   === serial-k1.log ===
   bs0-probe: cmdline [mac80211_hwsim.radios=0 test_power.battery_present=false console=ttyS0]
   bs0-probe: supplies [test_ac test_battery test_usb]
   bs0-probe: test_ac type [Mains]
   bs0-probe: test_ac present [-]
   bs0-probe: test_ac scope [-]
   bs0-probe: test_ac status [-]
   bs0-probe: test_ac capacity [-]
   bs0-probe: test_battery type [Battery]
   bs0-probe: test_battery present [0]
   bs0-probe: test_battery scope [-]
   bs0-probe: test_battery status [Discharging]
   bs0-probe: test_battery capacity [50]
   bs0-probe: test_usb type [USB]
   bs0-probe: test_usb present [-]
   bs0-probe: test_usb scope [-]
   bs0-probe: test_usb status [-]
   bs0-probe: test_usb capacity [-]
   bs0-probe: params [ac_online battery_capacity battery_charge_counter battery_current battery_extension battery_health battery_present battery_status battery_technology battery_voltage usb_online]
   bs0-probe: done
   deliberately-report-errors lines: 0
   kernel command line: mac80211_hwsim.radios=0 test_power.battery_present=false console=ttyS0
   === serial-k2.log ===
   bs0-probe: cmdline [mac80211_hwsim.radios=0 test_power.battery_present=false console=ttyS0 test_power.battery_present=true]
   …(k1과 같고 test_battery present만 [1])
   deliberately-report-errors lines: 0
   === serial-iso.log ===
   bs0-probe: cmdline [mac80211_hwsim.radios=0 test_power.battery_present=false console=ttyS0 initcall_blacklist=test_power_init]
   bs0-probe: supplies []
   bs0-probe: params […]
   bs0-probe: done
   deliberately-report-errors lines: 0
   kernel command line: mac80211_hwsim.radios=0 test_power.battery_present=false console=ttyS0 initcall_blacklist=test_power_init
   ```

   판정은 넷이다 — `qemu battery devices: 0`, `k1`의 `test_battery present [0]`, `k2`의 `test_battery present [1]`, `iso`의 `supplies []`.
   넷 중 하나라도 다르면 멈추고 그 부팅의 `bs0-probe:` 줄 전부와 `tail -n 40 /tmp/run/bs0/serial-<부팅>.log`를 보고한다.

   판정이 아닌 줄은 값을 그대로 보고에 적는다. 특히 셋.

   - `iso`의 `params`. 확정 3은 목록이 k1과 같을 것으로 본다. 비어 있거나 `No such file`이면 design 확인 8이 틀린 것이다.
   - `deliberately-report-errors lines`. 0이 아니면 확정 8이 틀린 것이고, 그 printk가 BS-M1 게이트의 화면 줄을 자를 수 있다.
   - `params`의 이름 수. 위의 열하나와 다르면 이름을 그대로 적는다.

   `bs0-probe: done`이 안 나오고 `===` 줄 아래가 비면 프로브가 안 돈 것이다. 그때는 그 시리얼 로그에서
   `rg -a 'tars-init: (config storage|mounted|started service probe|no disk)' /tmp/run/bs0/serial-<부팅>.log`를 보고한다 — 설정 디스크를
   못 찾았거나 `services.d`를 안 읽은 것이다.

## Task 7: 체인 회전

바뀐 것마다 그것을 밟는 체인을 돈다. 체인 하나가 1~3분이라 체인마다 Bash 호출을 따로 한다. 컨테이너 `/tmp`를 호스트에 묶어 시리얼 로그를
남긴다(lessons AL-M0 절).

| 순서 | 체인 | 왜 | 시간(최근 plan의 값) |
|---|---|---|---|
| 1 | terminal 호스트 검사 | `battery_test` — Task 2-4에서 이미 돌았다. 다시 안 돈다 | — |
| 2 | `wifi` | 검사 1의 grep이 바뀌었다. 커널에 test_power가 더해진 채 hwsim 부팅 셋 | 120초(TC-M2) |
| 3 | `install` | limine cmdline이 바뀌었다 — 판정 9 · 부팅 4의 `Kernel command line` grep, `espConf`가 새 줄에 표지를 붙인다 | 110초(TC-M0) |
| 4 | `machine` | UEFI limine으로 뜬다. design 결정 11의 `seen=0` 판정이 BS-M1에서 붙을 체인이다 | 보고에 적는다 |
| 5 | `boot` | BIOS limine으로 뜬다(확정 4) | 25초(TC-M2) |

```bash
cd /Users/dp/Repository/tars-linux && ch=wifi && mkdir -p /tmp/run/bs0/logs-$ch && rm -rf /tmp/run/bs0/logs-$ch/*
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/bs0/logs-$ch:/tmp -w /workspace tars-devcontainer ./$ch/check.sh \
    > /tmp/run/bs0/chain-$ch.log 2>&1 ; } 2> /tmp/run/bs0/chain-$ch.time; echo "$ch exit=$?"
rmdir /tmp/run/docker.lock
tail -n 3 /tmp/run/bs0/chain-$ch.log; cat /tmp/run/bs0/chain-$ch.time
```

`ch=`만 `install` · `machine` · `boot`으로 바꿔 차례로 친다. 기대: 넷 다 `exit=0`이고 로그에 `FAIL`이 없다.

그다음 limine 부팅이 실제로 새 cmdline을 받았는지 시리얼 로그에서 본다.

```bash
cd /Users/dp/Repository/tars-linux
rg -a --no-filename 'Kernel command line:' /tmp/run/bs0/logs-install/ /tmp/run/bs0/logs-machine/ /tmp/run/bs0/logs-boot/ | tr -d '\r' | sed 's/.*Kernel command line: //' | sort | uniq -c
```

기대: 줄 모양이 셋이다.

```
   5 mac80211_hwsim.radios=0 test_power.battery_present=false console=ttyS0 initcall_blacklist=test_power_init
   3 mac80211_hwsim.radios=0 test_power.battery_present=false console=ttyS0 initcall_blacklist=test_power_init tars.installed
   1 mac80211_hwsim.radios=0 test_power.battery_present=false console=ttyS0 tars.installed usb-storage.delay_use=4
```

첫째는 ISO로 뜬 부팅 다섯(install 부팅 1 · 3 · 5, machine, boot), 둘째는 설치된 ESP로 뜬 부팅 셋(install 부팅 2 · 4 · 6), 셋째는 install
부팅 7의 `-kernel`이다. install은 부팅마다 `mktemp`로 로그를 따로 둔다(`boot_guest` · `boot_kernel_usb`). 셋째는 limine을 안 거쳐서
블랙리스트가 없고, test_power는 등록되되 배터리가 꺼진 채다(design 결정 9의 표). 줄 모양은 판정이고 수는 기대다 — 수가 다르면 그대로
보고에 적는다. 체인이 빨개지면 그 로그의 `FAIL` 줄과 `cut log lines` 줄(루트 게이트가 아니라 체인만 돌렸으므로 없을 수 있다)을 그대로
보고하고 멈춘다.

마지막으로 전체 diff를 본다.

```bash
cd /Users/dp/Repository/tars-linux && git status --short && git diff --stat && git diff | rg '^-' && wc -l terminal/src/battery.zig terminal/src/battery_test.zig
```

기대: `git diff --stat`이 다섯 파일 `24 insertions(+), 8 deletions(-)`(Task 3에서 되접기를 했다면 `kernel/.config`의 수가 다르다). `git status`의
`??`에 새 파일 둘과 lead의 문서 말고는 없다 — 특히 `out/` · `*.img` · `kernel/build/` 산출물이 안 보인다(`.gitignore` 대상이다).
`rg '^-'`의 줄은 각 Task의 `old_string`과 머리 줄뿐이다.

## Task 8: 루트 게이트(lead)

커널이 바뀌었으므로 스물한 체인 전부다(design 끝 조건 5). 약 50분이라 lead가 `run_in_background`로 돌린다. 알림이 오면
`pgrep -f 'tars-devcontainer bash check.sh'`가 비었는지 먼저 본다(lessons).

```bash
cd /Users/dp/Repository/tars-linux && mkdir -p /tmp/run/bs0/gate && rm -rf /tmp/run/bs0/gate/*
until mkdir /tmp/run/docker.lock 2>/dev/null; do sleep 15; done
{ time docker run --rm -v "$PWD":/workspace -v /tmp/run/bs0/gate:/tmp -w /workspace tars-devcontainer bash check.sh \
    > /tmp/run/bs0/gate.log 2>&1 ; } 2> /tmp/run/bs0/gate.time; echo "gate exit=$?"
rmdir /tmp/run/docker.lock
```

기대.

- 마지막 줄 `TARS check PASS: all chains 2/2 consecutive runs succeeded (logs in /tmp/tars-gate.…)`.
- `rg -c 'skipping make' /tmp/run/bs0/gate.log`가 `41`(체인 21 × 회차 2 − 1, lessons GL-M1 절).
- `rg 'cut log lines' /tmp/run/bs0/gate.log | rg -v 'A=0 B=0 C=0'`가 아무것도 안 찍는다.
- hangul 체인의 `ink fg=383` · `caps ink off=87`이 착수 전과 같다 — 배터리 칸이 아직 없으므로 픽셀이 하나도 안 바뀐다. 게이트가 초록이면
  그 판정이 이미 이것을 본 것이다.

빨개진 체인이 있으면 design 결정 12의 가름대로 커널을 먼저 의심한다(이 milestone에서 terminal 바이너리가 바뀐 것은 없다 — `battery.zig`를
아무도 import하지 않는다).

## 끝 조건

design "BS-M0" 절의 다섯과 그것을 보는 명령.

| design 끝 조건 | 보는 명령 | 기대 |
|---|---|---|
| 1. `battery_test`가 호스트에서 초록이다 — 여덟 함수, 경우 전부 | Task 2-4의 `zig build test`, Task 2-5의 mutation 둘 | `battery_test: all checks passed`, mutation 둘이 각각 검사 10 · 16에서 `FAIL` |
| 2. `build.zig`의 `dependOn` 목록이 한 줄만 늘었다 | Task 2-4의 `git diff terminal/build.zig \| rg …` | `-`는 머리뿐, `+…dependOn`은 `battery_test` 한 줄 |
| 3. 되접기 diff가 비었다, 늘어난 기호를 센다 | Task 3의 3 · 4 · 5 | `diff exit=0` 둘, `skipping make`, `=y` 하나 |
| 4. 사본의 실측 셋과 QEMU 장치 한 줄 | Task 6 | `qemu battery devices: 0`, `present [0]` · `present [1]`, `supplies []` |
| 5. 루트 게이트 21체인이 초록이다 | Task 8 | `2/2`, `skipping make` 41, cut 셋 0 |

## 닫을 때(lead의 몫)

- 이 plan의 `Status:`를 고치고, 맨 아래에 "BS-M0이 실측한 것" 절을 더한다 — Task 2의 컴파일 에러를 고친 자리(있었다면), Task 3의 되접기
  결과와 빌드 시간, Task 6의 출력 전부(특히 `iso`의 `params`와 printk 수), Task 7의 체인 시간과 cmdline 셈, 루트 게이트의 시간.
- 확정 10(`Unknown`의 갈래)과 확정 9(`statusName`을 더한 것)가 design의 뜻과 맞는지 보고, 아니면 BS-M1 plan 전에 design에 덧붙인다.
- commit은 둘로 나눌 수 있다 — 커널(`kernel/.config`) · limine · `disk_test` · `wifi/check.sh`와, terminal의 새 파일 둘 · `build.zig`.
  `project_kernel_config`가 정규화와 의도한 변경을 나누라고 했지만, 이번에는 되접기가 비면 정규화 commit이 없다.
