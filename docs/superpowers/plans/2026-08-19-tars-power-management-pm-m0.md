# TARS Power Management PM-M0 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 파일 작성과
> 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을 제시하고
> 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는 이 저장소에 적용하지 않는다.

**Goal:** 게스트 안에서 시스템을 끌 수 있게 한다. 화면 터미널에
`kill -TERM 1`을 치면 PID 1이 그것을 받아, 자식들을 정리하고, 디스크를
내려쓴 뒤, `reboot(2)`를 부른다. 이 milestone이 끝나면 TARS를 끄는 방법이
"호스트에서 QEMU를 죽인다" 말고 하나 더 생긴다.

**Design doc:** `docs/superpowers/specs/2026-08-19-tars-power-management-design.md`
(결정 1의 `SIGTERM` 절반, 결정 2·3·5·6·7이 이 milestone의 몫. 결정 4·9와
결정 8의 부팅 A는 PM-M1이다.)

**Tech Stack:** Zig 0.16.0, `std.os.linux`(`sigaction`/`kill`/`waitpid`/
`sync`/`reboot`), QEMU monitor `sendkey`, `mkfs.ext2 -d`,
Docker(`tars-devcontainer`, arm64)

---

## 왜 이 순서인가

```
Task 1   power.zig — 시그널이 플래그가 된다           ← 부팅 없이 도는 저울
  ↓      호스트 검사가 0.1초에 판정한다
Task 2   power/ 체인을 만들고 **실패를 본다**          ← 게이트가 구현보다 먼저
  ↓      지금 kill -TERM 1은 아무 일도 안 한다
Task 3   종료 순서 + main.zig 결선                     ← 같은 게이트가 통과한다
  ↓
Task 4   루트 게이트에 다섯째 체인을 등록하고 3/3
```

**Task 1이 맨 앞인 이유**는 이 milestone에서 **부팅 없이 판정할 수 있는
유일한 조각**이기 때문이다. libc 없이 `rt_sigaction`을 직접 부르는 것은
구조체 하나만 어긋나도 조용히 실패하는 종류의 일인데, 그 실패를 게스트에서
만나면 원인이 "핸들러가 안 달렸다"인지 "종료 순서가 틀렸다"인지 가릴 수 없다.
`config_test`가 부팅 20초 앞에서 파서를 잡는 것과 같은 자리다.

**Task 2가 구현보다 앞인 이유**는 이 milestone의 실패가 **관측되지 않는
종류**이기 때문이다. 지금 게스트에서 `kill -TERM 1`을 치면 커널이 그 시그널을
조용히 버린다(design doc 조사 1). 화면에는 아무 일도 일어나지 않고 에러도
없다. 그 "아무 일도 없음"을 게이트로 한 번 보고 나서 구현에 들어가야,
Task 3의 통과가 무엇 때문인지 분명해진다.

**Task 3이 종료 순서와 결선을 한 Task에 묶는 이유**는 관측 가능성이다.
`shutdown()`만 먼저 써 두면 아무도 그것을 부르지 않으므로 **한 줄도 실행되지
않는다.** 호스트에서 시험 삼아 불러 볼 수도 없다 — 그 함수는 컨테이너를
정지시킨다. 부르는 자리(`supervise` 루프 머리)가 함께 생겨야 게이트가 볼 수
있다.

## 이번에 정하는 것 넷 (design doc이 안 정한 자리)

**1. 로그 문구 여덟을 여기서 확정한다.**

`project_gate_chain_composition`이 적어둔 그대로, 이 문자열들은 `init` 코드와
check 스크립트 **두 곳에 중복된다.** 한쪽을 고치면 다른 쪽도 고쳐야 한다.

| 문구 | 언제 |
|---|---|
| `tars-init: signal handlers installed (TERM)` | 부팅 시 1회 |
| `tars-init: shutdown requested (action power_off)` | 시그널을 받고 |
| `tars-init: sent SIGTERM to every process` | 1단계 |
| `tars-init: every child is gone (reaped N)` | 자식을 다 거뒀을 때 |
| `tars-init: grace period expired (reaped N)` | 유예가 끝났을 때 |
| `tars-init: sent SIGKILL to what was left` | 3단계 |
| `tars-init: filesystems synced` | 4단계 |
| `tars-init: calling reboot(POWER_OFF)` | 5단계 |

**2. 대화형 셸은 `SIGTERM`을 무시한다 — `SIGKILL` 경로가 예외가 아니라 정상
경로다.**

bash·zsh·fish는 **대화형으로 떴을 때 `SIGTERM`을 무시한다.** 로그인 셸이
지나가는 `kill`에 죽어버리면 곤란하기 때문이고, POSIX가 그렇게 하라고
적어 둔 동작이다. 그래서 우리 종료 순서에서 1단계(`SIGTERM`)에 죽는 것은
`/terminal`뿐이고, 셸 둘은 3초를 기다린 뒤 `SIGKILL`로 죽는다.

이것을 미리 적어두는 이유는 **게이트가 무엇을 기대해야 하는지**가 여기서
갈리기 때문이다. `grace period expired`는 버그 신호가 아니라 매번 나오는
줄이다. 대신 게이트는 **마지막에 `every child is gone`이 나오는 것**을
요구한다. 유예가 끝난 뒤에도 자식이 남아 있으면 `SIGKILL`이 안 먹었다는
뜻이고, 그건 진짜 실패다.

**3. PM 게이트의 게스트 셸은 bash다.**

`kill`은 initrd에 **바이너리로 들어 있지 않다**(`kernel/make_initrd.sh`가
넣는 것은 fish·bash·zsh와 cat·uname·mkdir·sleep뿐이다). bash와 zsh는
`kill`을 빌트인으로 가지고 있어서 상관없지만, **fish에 `kill` 빌트인이 있는지
확인되지 않았다.** 기본값이 fish이므로 그대로 두면 게이트가 "명령을 못
찾았다"로 죽을 수 있고, 그 실패는 시그널 처리의 실패와 구분되지 않는다.

IP-M2가 쓴 방법을 그대로 쓴다: `mkfs.ext2 -d`로 `shell=bash`가 이미 적힌
디스크를 굽는다. 게스트에 `/usr/bin/bash --norc`를 타이핑할 필요도 없어지고,
부팅 직후부터 bash 프롬프트다.

**4. `power.zig`를 새 파일로 두고, 네 줄짜리 헬퍼는 복사한다.**

`config.zig:4`에 이미 이렇게 적혀 있다.

> main.zig에도 같은 함수가 있다. 세 줄짜리 헬퍼 하나 때문에 공용 모듈을
> 만드는 것보다 각자 갖고 있는 편이 읽기 쉽다고 판단했다 — 이런 것이
> 다섯 개쯤 되면 그때 sys.zig로 모은다.

`power.zig`의 `failed`가 **세 벌째**다. 아직 다섯이 아니므로 그 판단을
유지한다. 대신 `power.zig`의 복사본에도 같은 사정을 적어서, 다음 사람이
"넷째를 만들지 다섯을 모을지"를 셀 수 있게 한다.

`main.zig`에 넣지 않고 파일을 나누는 이유는 책임이 다르기 때문이다.
`main.zig`는 "무엇을 띄우고 지키는가"이고 `power.zig`는 "언제 어떻게
멈추는가"다. 그리고 `power.zig`만 호스트 검사(`power_test`)를 갖는데,
`main.zig`는 PID 1 전용 코드라 호스트에서 실행할 수 없다.

## 사전 준비

모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서 실행한다.
`main` 브랜치, working tree가 깨끗한 상태에서 시작한다.

**`docker run`/`docker build`에 `--platform`을 붙이지 않는다**
(`docs/decisions/project_build_host_arch.md`).

**이번에 `/tmp` + `cp` + `diff` 경로를 쓰는 파일은 둘이다** —
`init/src/power.zig`(Task 3에서 100줄을 넘는다)와 `power/check.sh`(Task 2,
새 파일 150줄). 나머지는 전부 짧은 블록이라 인라인으로 제시한다.

**인라인으로 제시하는 블록은 "넣을 것"만 적는다.** IP-M2에서 문맥 줄을
포함한 블록을 제시했다가 기존 줄이 복제된 사고가 있었다. "이런 모양이 된다"는
예시가 필요하면 그것이 붙여넣기용이 아님을 명시한다.

**이미지 재빌드는 필요 없다.** bash는 이미 initrd에 들어가고
(`kernel/make_initrd.sh`), `mkfs.ext2 -d`도 IP-M2부터 쓰고 있다.

---

## Task 1: 시그널이 플래그가 된다

이 Task가 만드는 것은 **관측 장치**다. 시스템을 끄는 코드는 아직 없다.
`SIGTERM`이 도착했다는 사실이 감독 루프가 읽을 수 있는 값 하나로 남는
것까지가 여기다.

**Files:**
- Create: `init/src/power.zig`
- Create: `init/src/power_test.zig`
- Modify: `init/build.zig` (test step에 `power_test` 추가)

- [ ] **Step 1: 실패할 검사를 먼저 쓴다**

`init/src/power_test.zig`를 새로 만든다.

```zig
const std = @import("std");
const linux = std.os.linux;
const power = @import("power.zig");

/// PM-M0의 유일한 호스트 검사. 부팅 없이 판정할 수 있는 것은 "시그널이
/// 플래그가 되는가" 하나뿐이다 — 그 뒤의 종료 순서(reboot(2))는 부르는
/// 순간 이 컨테이너가 멈추므로 게스트에서만 볼 수 있다.
///
/// config_test와 같은 모양이다(호스트 아키텍처 실행 파일, 실패하면 0이
/// 아닌 종료 코드). 체인 스크립트가 둘을 똑같이 다룰 수 있어야 한다.
pub fn main() !void {
    // 1. 아직 아무 시그널도 오지 않았다.
    if (power.take() != null) {
        std.debug.print("FAIL: nothing was sent yet but take() returned something\n", .{});
        return error.UnexpectedAction;
    }

    power.install();

    // 2. 자기 자신에게 SIGTERM을 보낸다. 자기에게 보낸 시그널은 블록돼 있지
    //    않으면 kill(2)이 돌아오기 전에 배달되므로, 여기서 잠들 필요가 없다.
    _ = linux.kill(linux.getpid(), .TERM);

    const got = power.take() orelse {
        std.debug.print("FAIL: SIGTERM was delivered but no action was recorded\n", .{});
        return error.SignalNotObserved;
    };
    if (got != .power_off) {
        std.debug.print("FAIL: SIGTERM recorded {s}, want power_off\n", .{@tagName(got)});
        return error.WrongAction;
    }

    // 3. 한 번 읽으면 소비된다. 감독 루프가 매 바퀴 묻기 때문에, 남아 있으면
    //    같은 종료 요청을 두 번 처리하게 된다.
    if (power.take() != null) {
        std.debug.print("FAIL: the action was not consumed by take()\n", .{});
        return error.ActionNotConsumed;
    }

    std.debug.print("power_test: SIGTERM becomes a pending power_off action\n", .{});
}
```

- [ ] **Step 2: 아무것도 하지 않는 `power.zig`를 만든다**

일부러 **핸들러를 달지 않는** 판을 먼저 만든다. 이렇게 하면 다음 Step에서
"핸들러가 없으면 무슨 일이 일어나는가"를 눈으로 보게 된다.

`init/src/power.zig`를 새로 만든다.

```zig
const std = @import("std");
const linux = std.os.linux;

/// PID 1이 시그널을 받고 하기로 한 일. PM-M0은 끄는 것 하나뿐이고,
/// PM-M1에서 SIGINT가 restart를 더한다.
pub const Action = enum(u8) {
    power_off = 1,
};

/// 시그널 핸들러가 만질 수 있는 유일한 상태. 0은 "요청 없음"이다.
var pending: u8 = 0;

/// 아직 아무것도 하지 않는다. 다음 Step에서 채운다.
pub fn install() void {}

/// 밀린 요청을 꺼내면서 지운다. 감독 루프가 매 바퀴 부른다.
pub fn take() ?Action {
    const raw = @atomicRmw(u8, &pending, .Xchg, 0, .seq_cst);
    if (raw == 0) return null;
    return @enumFromInt(raw);
}
```

- [ ] **Step 3: `build.zig`의 test step에 검사를 등록한다**

`init/build.zig`의 마지막 두 줄

```zig
    const test_step = b.step("test", "호스트 아키텍처로 도는 검사를 실행한다");
    test_step.dependOn(&b.addRunArtifact(config_test).step);
```

**바로 위에** 이 블록을 넣는다.

```zig
    // PM-M0: 시그널이 플래그가 되는지 보는 검사. config_test와 같은 자리에
    // 두는 이유는 같다 — 부팅 20초를 쓰기 전에 0.1초로 잡을 수 있는 실패를
    // 먼저 잡는다.
    const power_test_mod = b.createModule(.{
        .root_source_file = b.path("src/power_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const power_test = b.addExecutable(.{
        .name = "power_test",
        .root_module = power_test_mod,
    });

```

그리고 마지막 줄 **뒤에** 한 줄을 더한다.

```zig
    test_step.dependOn(&b.addRunArtifact(power_test).step);
```

- [ ] **Step 4: 실패를 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer bash -c "zig build test"
```

기대: **`power_test`가 시그널 15에 죽는다.** 종료 코드가 아니라 시그널로
끝났다는 에러가 나온다. 대략 이런 모양이다.

```
run power_test: error: the following command terminated unexpectedly:
... (signal 15)
```

**이것이 이 milestone 전체의 출발점이다.** 핸들러가 없으면 `SIGTERM`의 기본
동작(프로세스 종료)이 그대로 일어난다. 게스트의 PID 1에서는 커널이 그 기본
동작을 막아주기 때문에 **아무 일도 일어나지 않고 조용히 버려지는데**, 여기
호스트 프로세스에서는 같은 부재가 죽음으로 나타난다. 부재를 눈에 보이게
만든 셈이다.

`config_test`는 그대로 통과해야 한다. 그것까지 깨졌으면 `build.zig` 편집이
틀린 것이니 알려 달라.

- [ ] **Step 5: 핸들러를 단다**

`init/src/power.zig`의

```zig
/// 아직 아무것도 하지 않는다. 다음 Step에서 채운다.
pub fn install() void {}
```

을 이것으로 바꾼다.

```zig
/// 시그널 핸들러 안에서는 재진입 안전하지 않은 것을 부를 수 없다. 우리 로그
/// 함수(std.debug.print)가 바로 그런 것이므로, 핸들러는 정수 하나를 남기고
/// 즉시 돌아온다. 로그는 깨어난 감독 루프가 찍는다.
fn onSignal(sig: linux.SIG) callconv(.c) void {
    const action: Action = switch (sig) {
        .TERM => .power_off,
        else => return,
    };
    @atomicStore(u8, &pending, @intFromEnum(action), .seq_cst);
}

/// 시그널 처리를 켠다. 이 함수를 부르기 전까지 PID 1에게 보낸 SIGTERM은
/// **커널이 조용히 버린다** — 기본 동작(종료)이 PID 1에 적용되면 곧바로
/// 커널 패닉이 되기 때문에 커널이 미리 막아 놓았다. 그래서 이 한 번의
/// 호출이 곧 "게스트에서 전원을 다룰 수 있다"는 기능 자체다.
pub fn install() void {
    const act: linux.Sigaction = .{
        .handler = .{ .handler = onSignal },
        .mask = linux.sigemptyset(),
        // SA_RESTART를 켜지 않는다. 켜면 커널이 supervise의 waitpid를 안에서
        // 자동 재시작해버려서, 플래그를 세워도 루프 머리로 영영 돌아오지
        // 못한다. 끄면 그 waitpid가 EINTR로 깨어나고, supervise의 errno
        // 분기(`if (e == .INTR) continue;`)가 이미 그것을 받고 있다.
        .flags = 0,
    };
    if (failed(linux.sigaction(.TERM, &act, null))) |e| {
        std.debug.print("tars-init: failed to install SIGTERM handler (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    std.debug.print("tars-init: signal handlers installed (TERM)\n", .{});
}
```

그리고 파일 맨 위 `const linux = std.os.linux;` **바로 아래**에 헬퍼를 넣는다.

```zig

/// main.zig와 config.zig에도 같은 함수가 있다. 이것이 **세 벌째**다.
/// config.zig:4가 "다섯 개쯤 되면 sys.zig로 모은다"고 적어 뒀고, 아직
/// 다섯이 아니므로 그 판단을 유지한다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}
```

- [ ] **Step 6: 통과를 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer bash -c "zig build test"
```

기대: 두 검사가 다 통과하고 마지막에 이 줄이 보인다.

```
tars-init: signal handlers installed (TERM)
power_test: SIGTERM becomes a pending power_off action
```

첫 줄이 함께 나오는 것이 정상이다. `install()`이 게스트용 로그를 그대로 찍기
때문이며, 이 검사는 호스트에서 도는 같은 코드다.

- [ ] **Step 7: 커밋**

```bash
git add init/src/power.zig init/src/power_test.zig init/build.zig
git commit -m "Let PID 1 notice a SIGTERM"
```

---

## Task 2: 게이트를 먼저 만들고 아무 일도 안 일어나는 것을 본다

새 체인 `power/`를 만든다. 이 시점에서는 **반드시 실패해야 한다.**
`main.zig`가 아직 `power.install()`을 부르지 않으므로, 게스트에서 친
`kill -TERM 1`은 커널이 버린다.

**Files:**
- Create: `power/make_disk.sh`
- Create: `power/check.sh`

- [ ] **Step 1: 설정 디스크를 굽는 스크립트를 만든다**

`power/make_disk.sh`를 새로 만든다.

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# PM 체인용 설정 디스크.
#
# 이 디스크가 하는 일은 하나뿐이다 — **PTY 셸을 bash로 띄우는 것**.
# kill은 initrd에 바이너리로 들어 있지 않고(make_initrd.sh가 넣는 것은
# 셸 셋과 cat/uname/mkdir/sleep뿐이다), bash와 zsh는 kill을 빌트인으로
# 가지고 있지만 기본값인 fish는 확인되지 않았다. 게이트가 "명령을 못
# 찾았다"로 죽으면 그 실패는 시그널 처리의 실패와 구분되지 않는다.
#
# IP-M2가 연 길을 그대로 쓴다: mkfs.ext2 -d로 **내용이 이미 든** 이미지를
# 구우면 게스트에 한 글자도 치지 않고 셸을 고를 수 있다.
SIZE=16M
IMG=../out/power.img

mkdir -p ../out
rm -f "$IMG"

# 매 회차 새로 굽는다. 이전 회차의 이미지가 남아 있으면 "이 설정이 정말
# 이 파일에서 왔는가"가 흐려진다.
SEED="$(mktemp -d)"
cat > "$SEED/tars.conf" <<'EOF'
# PM 체인이 미리 심어 두는 설정.
#
# shell=bash — kill 빌트인이 확실히 있는 셸로 띄운다. 게이트는 이 셸에
#              `kill -TERM 1`을 타이핑한다.
shell=bash
EOF

truncate -s "$SIZE" "$IMG"
mkfs.ext2 -F -q -m 0 -L tars-power -d "$SEED" "$IMG"
rm -rf "$SEED"

echo "make_disk: created ${IMG} (${SIZE}, ext2, shell=bash)"
```

실행 권한을 준다.

```bash
chmod +x power/make_disk.sh
```

- [ ] **Step 2: 게이트 스크립트를 만든다**

**이 파일은 150줄이 넘으므로 `/tmp` 경로를 쓴다.** Claude가
`/tmp/tars-power-check.sh`에 만들어 두면, 다음 명령으로 제자리에 넣고
대조한다.

```bash
cp /tmp/tars-power-check.sh power/check.sh
chmod +x power/check.sh
diff /tmp/tars-power-check.sh power/check.sh && echo "identical"
```

파일 내용은 다음과 같다.

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

REPO_ROOT="$(cd .. && pwd)"

# PM 체인 — 전원 관리.
#
# 이 게이트가 증명하는 사슬 전체:
#   sendkey k,i,l,l,... → 커널 atkbd → evdev → terminal/src/input.zig가
#   바이트를 만든다 → pty write → bash가 kill 빌트인을 실행한다
#   → 커널이 PID 1에게 SIGTERM을 배달한다(핸들러가 있을 때만!)
#   → init/src/power.zig가 자식을 정리하고 reboot(2)를 부른다
#   → 커널이 시스템을 멈춘다
#
# 마지막 칸을 게이트가 어떻게 보는가가 이 체인의 성격을 정한다. 우리 커널은
# ACPI가 꺼져 있어서(kernel/.config:377) reboot(POWER_OFF)이 HALT로 강등되고,
# 그때 커널이 찍는 줄이 아래 HALT_MARKER다. QEMU는 이 경우 스스로 끝나지
# 않으므로 -no-reboot을 그대로 두고 게이트가 죽인다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

# 호스트에서 도는 순수 로직 검사 둘(config.zig의 parse, power.zig의 시그널
# 플래그). 부팅 20초를 쓰기 전에 0.1초로 잡을 수 있는 실패를 먼저 잡는다.
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

if ! ./make_disk.sh; then
  echo "FAIL: disk image build failed"
  exit 1
fi

# 45455=TF, 45456=CP, 45457=IP. 겹치지 않는 번호를 쓰는 이유는 죽다 만 QEMU가
# 남았을 때 엉뚱한 게스트에 키를 보내지 않기 위해서다.
MONITOR_PORT=45458

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
    "tars-init: mounted ext2 at /config" \
    "tars-init: config shell=bash" \
    "tars-init: signal handlers installed" \
    "terminal: screen>" \
    "tars-init: shutdown requested" \
    "tars-init: sent SIGTERM to every process" \
    "tars-init: every child is gone" \
    "tars-init: filesystems synced" \
    "tars-init: calling reboot" \
    "Power off not available"; do
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

# 게스트 셸에 한 글자씩 타이핑한다. CP·IP와 같은 함수다 — sendkey가 보내는
# 것은 문자가 아니라 **키**이므로, 대문자는 shift-를 붙여야 한다.
type_keys() {
  local k
  for k in "$@"; do
    echo "sendkey $k" >&3
    sleep 0.3
  done
}

# kill -TERM 1
KILL_KEYS=(k i l l spc minus shift-t shift-e shift-r shift-m spc 1 ret)

qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -drive file="${REPO_ROOT}/out/power.img",if=virtio,format=raw \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

# "terminal: screen>" 첫 줄이 곧 DRM 열기 + 폰트 래스터라이즈 + evdev 열기 +
# 셸 spawn + 첫 렌더가 전부 끝났다는 신호다.
READY=0
for _ in $(seq 1 120); do
  if grep -q "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "terminal never rendered a prompt"
sleep 1

# 디스크가 정말 읽혔는지 먼저 본다. 이 줄이 없으면 셸은 fish이고, 그러면
# 아래 타이핑은 kill을 못 찾아서 실패한다 — 그 실패를 시그널 처리의 실패로
# 오진하지 않도록 여기서 갈라둔다.
grep -q "tars-init: config shell=bash" "$LOG" \
  || report_failure "the config disk was not read; the shell is not bash"

# bash가 정말 떴는지. --norc로 뜬 bash의 기본 PS1은 `\s-\v\$`라 화면에
# `bash-5.2$` 같은 프롬프트가 그려진다.
BASH_OK=0
for _ in $(seq 1 30); do
  if grep -q "terminal: screen>.*bash-" "$LOG"; then BASH_OK=1; break; fi
  sleep 1
done
[ "$BASH_OK" = "1" ] || report_failure "the PTY shell never showed a bash prompt"

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor"

echo "=== typing 'kill -TERM 1' into the guest ==="
type_keys "${KILL_KEYS[@]}"

# 종료 순서가 도는 데 걸리는 시간은 유예 3초가 지배한다. 대화형 셸은
# SIGTERM을 무시하므로(POSIX), 셸 둘은 그 3초가 지난 뒤 SIGKILL로 죽는다.
HALT_MARKER="Power off not available: System halted instead"
DONE=0
for _ in $(seq 1 30); do
  if grep -q "$HALT_MARKER" "$LOG"; then DONE=1; break; fi
  sleep 1
done

exec 3<&-
exec 3>&-

[ "$DONE" = "1" ] || report_failure "the guest never halted after kill -TERM 1"

# 여기서부터는 "어떻게 멈췄는가"를 따진다. 위의 HALT_MARKER 하나만 보면
# 시스템이 멈춘 것은 알 수 있지만 **왜** 멈췄는지는 알 수 없다.
for marker in \
  "tars-init: signal handlers installed (TERM)" \
  "tars-init: shutdown requested (action power_off)" \
  "tars-init: sent SIGTERM to every process" \
  "tars-init: every child is gone" \
  "tars-init: filesystems synced" \
  "tars-init: calling reboot(POWER_OFF)"; do
  grep -q "$marker" "$LOG" || report_failure "missing shutdown log line: ${marker}"
done

# 음성 검사 1 — PID 1이 죽어서 커널이 패닉한 것이 아니어야 한다. 시그널
# 처리가 잘못되면 시스템은 어차피 멈추므로, 이 검사가 없으면 위의
# HALT_MARKER는 두 가지 이유로 성립할 수 있다.
if grep -q "Attempted to kill init" "$LOG"; then
  report_failure "the kernel panicked instead of shutting down cleanly"
fi

# 음성 검사 2 — 종료 중에 감독 루프가 자식을 되살리면 안 된다. 되살리면
# 이 줄이 둘 이상이 된다.
STARTED="$(grep -c "tars-init: started console shell" "$LOG")"
if [ "$STARTED" != "1" ]; then
  report_failure "the supervisor restarted the console shell during shutdown (started ${STARTED} times)"
fi

# 관측만 하는 줄. 셸이 SIGTERM을 무시하는 것이 정상이므로 이 줄이 나오는
# 것은 실패가 아니다. 어느 경로였는지 사람이 알 수 있게 남긴다.
if grep -q "tars-init: grace period expired" "$LOG"; then
  echo "note: the grace period expired and SIGKILL finished the job (this is the normal path)"
else
  echo "note: every child died from SIGTERM alone"
fi

kill "$QEMU_PID" 2>/dev/null
wait "$QEMU_PID" 2>/dev/null
QEMU_PID=""

echo "PM-M0 PASS: the guest shut itself down from a shell command"
```

- [ ] **Step 3: 문법을 먼저 본다**

```bash
bash -n power/check.sh && bash -n power/make_disk.sh && echo "syntax ok"
```

- [ ] **Step 4: 실패를 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash power/check.sh
```

기대: **`the guest never halted after kill -TERM 1`으로 실패한다.**
마커 목록에서 `terminal: screen>`까지는 `found`이고, `shutdown requested`
아래로는 전부 `MISSING`이어야 한다.

이것이 지금 TARS의 상태다. 키는 게스트에 도착했고, bash는 `kill`을
실행했고, 커널은 PID 1에게 `SIGTERM`을 배달하려 했지만 **핸들러가 없어서
그 시그널을 버렸다.** 화면에도 로그에도 아무 흔적이 없다.

다른 이유로 실패하면(예: `the config disk was not read`, `bash prompt`)
구현이 아니라 게이트가 틀린 것이니 알려 달라.

- [ ] **Step 5: 커밋**

실패하는 게이트도 커밋한다. 다음 커밋이 무엇을 고쳤는지가 히스토리에 남는다.

```bash
git add power/check.sh power/make_disk.sh
git commit -m "Add a gate that asks the guest to shut itself down"
```

---

## Task 3: 종료 순서를 구현하고 게이트를 통과시킨다

**Files:**
- Modify: `init/src/power.zig` (`shutdown` + 헬퍼 셋 추가)
- Modify: `init/src/main.zig:3` (import), `main()` 안(install), `supervise()` 루프 머리

- [ ] **Step 1: `power.zig`에 종료 순서를 넣는다**

**이 편집으로 `power.zig`가 100줄을 넘으므로 `/tmp` 경로를 쓴다.** Claude가
`/tmp/tars-power.zig`에 완성본을 만들어 두면:

```bash
cp /tmp/tars-power.zig init/src/power.zig
diff /tmp/tars-power.zig init/src/power.zig && echo "identical"
```

완성본은 Task 1의 파일에 아래 셋이 더해진 것이다(위쪽 `Action`/`pending`/
`onSignal`/`install`/`take`/`failed`는 그대로 둔다).

```zig
/// 자식에게 주는 유예. 감독 루프의 재시작 backoff가 1초이고 우리 자식은
/// 터미널과 셸뿐이라 정리에 이보다 오래 걸릴 일이 없다.
const GRACE_SECONDS: isize = 3;

fn monotonicSeconds() isize {
    var ts: linux.timespec = undefined;
    if (failed(linux.clock_gettime(.MONOTONIC, &ts))) |_| return 0;
    return ts.sec;
}

fn sleepMillis(ms: isize) void {
    const req = linux.timespec{
        .sec = @divTrunc(ms, 1000),
        .nsec = @rem(ms, 1000) * 1_000_000,
    };
    _ = linux.nanosleep(&req, null);
}

/// 자식이 전부 사라질 때까지 거둔다. 다 거뒀으면 true, 유예가 끝났으면
/// false.
///
/// WNOHANG이라 살아 있는 자식이 있으면 0을 돌려주고 즉시 반환한다. 그래서
/// "잠깐 자고 다시 묻는" 모양이 된다 — 그냥 blocking waitpid를 쓰면 죽지
/// 않는 자식 하나 때문에 영영 못 나온다. 대화형 셸이 정확히 그런
/// 자식이다(SIGTERM을 무시한다).
fn reapAll() bool {
    const deadline = monotonicSeconds() + GRACE_SECONDS;
    var reaped: usize = 0;
    while (true) {
        var status: u32 = 0;
        const rc = linux.waitpid(-1, &status, linux.W.NOHANG);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                // rc가 0이면 "살아 있지만 아직 안 죽었다"이므로 아래로 간다.
                if (rc != 0) {
                    reaped += 1;
                    continue;
                }
            },
            .CHILD => {
                std.debug.print("tars-init: every child is gone (reaped {d})\n", .{reaped});
                return true;
            },
            // EINTR 등. 아래에서 기다렸다가 다시 묻는다.
            else => {},
        }
        if (monotonicSeconds() >= deadline) {
            std.debug.print("tars-init: grace period expired (reaped {d})\n", .{reaped});
            return false;
        }
        sleepMillis(100);
    }
}

/// 시스템을 끈다. **절대 반환하지 않는다** — supervise가 noreturn인 것과
/// 같은 이유이고, 그보다 하나 더 있다. 이 함수가 도는 동안 감독 루프로
/// 돌아가면 "안 떠 있는 자식을 띄운다"는 규칙이 방금 죽인 셸을 되살린다.
/// 돌아갈 길 자체를 타입으로 막아둔다.
pub fn shutdown(action: Action) noreturn {
    std.debug.print("tars-init: shutdown requested (action {s})\n", .{@tagName(action)});

    // -1은 "자기를 제외한 모든 프로세스"다. 감독 대상 둘뿐 아니라 PTY 안에서
    // 도는 셸까지 한 번에 닿으므로 자식 목록을 순회할 필요가 없고, 리눅스가
    // 호출자를 대상에서 빼주므로 PID 1이 자기를 죽이는 일도 없다.
    _ = linux.kill(-1, .TERM);
    std.debug.print("tars-init: sent SIGTERM to every process\n", .{});

    // 대화형 셸은 SIGTERM을 무시한다(POSIX). 그래서 여기서 false가 나오는
    // 것이 정상이고, SIGKILL은 예외 처리가 아니라 정상 경로의 일부다.
    if (!reapAll()) {
        _ = linux.kill(-1, .KILL);
        std.debug.print("tars-init: sent SIGKILL to what was left\n", .{});
        _ = reapAll();
    }

    // 커널은 reboot(2)에서 sync를 대신 해주지 않는다. 리눅스 소스의
    // kernel/reboot.c:726이 "reboot doesn't sync: do that yourself before
    // calling this"라고 직접 적어 두었다. /config는 MS_SYNCHRONOUS라 그
    // 파일시스템만 보면 필요 없지만, 시스템 콜 한 번이고 다른 파일시스템에는
    // 그 보장이 없다.
    linux.sync();
    std.debug.print("tars-init: filesystems synced\n", .{});

    const cmd: linux.LINUX_REBOOT.CMD = switch (action) {
        .power_off => .POWER_OFF,
    };
    std.debug.print("tars-init: calling reboot({s})\n", .{@tagName(cmd)});
    _ = linux.reboot(.MAGIC1, .MAGIC2, cmd, null);

    // 여기에 도달했다는 것은 reboot(2)가 실패했다는 뜻이다. PID 1의 반환은
    // 곧 커널 패닉이므로 돌아가지 않고 여기서 쉰다.
    std.debug.print("tars-init: reboot syscall returned; PID 1 stays alive\n", .{});
    while (true) sleepMillis(1000);
}
```

**이 함수를 호스트에서 시험 삼아 부르지 말 것.** `reboot(2)`는 컨테이너의
권한에 따라 그대로 먹을 수 있고, 그러면 개발 기계가 멈춘다. `power_test`가
이 함수를 부르지 않는 이유가 그것이다.

- [ ] **Step 2: 컴파일만 먼저 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer bash -c "zig build && zig build test"
```

기대: 둘 다 통과. `shutdown`은 아직 아무도 부르지 않으므로 동작은 그대로다.

- [ ] **Step 3: `main.zig`에 import를 더한다**

`init/src/main.zig:3`의

```zig
const config = @import("config.zig");
```

**바로 아래**에 한 줄을 넣는다.

```zig
const power = @import("power.zig");
```

- [ ] **Step 4: 부팅 초기에 시그널 처리를 켠다**

`init/src/main.zig`의

```zig
    std.debug.print("tars-init: starting as PID 1\n", .{});
```

**바로 아래**에 넣는다.

```zig

    // mount보다 먼저 켠다. 핸들러가 하는 일은 플래그를 세우는 것뿐이라 이
    // 시점에 달아도 안전하고, "PID 1은 태어날 때부터 시그널을 안다"가 읽기에
    // 맞다. 이 호출 전까지 커널은 PID 1에게 온 SIGTERM을 조용히 버린다.
    power.install();
```

- [ ] **Step 5: 감독 루프 머리에서 요청을 본다**

자리는 `supervise()` 안의 `while (true) {`와 그 다음 줄인
`var alive: usize = 0;` **사이**다. Step 4가 위쪽에 다섯 줄을 더했으므로 줄
번호는 밀려 있다. 아래 블록만 그 사이에 넣는다(`while`과 `var alive` 줄은
건드리지 않는다).

```zig
        // 자식을 다시 띄우기 **전에** 본다. 순서가 뒤집히면 방금 SIGTERM으로
        // 죽인 셸을 이 루프가 되살린다. waitpid는 SA_RESTART를 끈 덕분에
        // EINTR로 깨어나고, 아래의 `if (e == .INTR) continue;`가 그것을 여기로
        // 돌려보낸다.
        if (power.take()) |action| power.shutdown(action);

```

- [ ] **Step 6: 게이트를 통과시킨다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash power/check.sh
```

기대: 마지막 두 줄이 이렇게 나온다.

```
note: the grace period expired and SIGKILL finished the job (this is the normal path)
PM-M0 PASS: the guest shut itself down from a shell command
```

`note:` 줄이 반대쪽("every child died from SIGTERM alone")으로 나와도 게이트는
통과다. 다만 그건 셸이 `SIGTERM`에 죽었다는 뜻이라 예상과 다르므로 알려 달라.

- [ ] **Step 7: 다른 체인이 안 깨졌는지 본다**

`main.zig`와 `build.zig`를 건드렸으므로 나머지 넷을 한 번씩 돌린다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c \
  './boot/check.sh && ./terminal/check.sh && ./config/check.sh && ./input/check.sh'
```

기대: 넷 다 PASS. 여기서 깨진다면 원인은 `install()`이 찍는 새 로그 한 줄이
아니라(그 줄은 아무도 검사하지 않는다) `build.zig` 편집일 가능성이 높다.

- [ ] **Step 8: 커밋**

```bash
git add init/src/power.zig init/src/main.zig
git commit -m "Shut the system down when PID 1 gets a SIGTERM"
```

---

## Task 4: 루트 게이트에 다섯째 체인을 등록한다

**Files:**
- Modify: `check.sh:35-66` (주석과 체인 목록)
- Modify: `HANDOFF.md`

- [ ] **Step 1: 체인을 등록한다**

`check.sh`의

```bash
run_chain "IP-M2" ./input/check.sh
```

**바로 아래**에 한 줄을 넣는다.

```bash
run_chain "PM-M0" ./power/check.sh
```

- [ ] **Step 2: 부팅 횟수 주석을 갱신한다**

`check.sh`의

```bash
# 그래서 루트 게이트 한 번의 총 부팅 횟수는 15회에서 18회가 된다.
# 이 체인에서 비싼 쪽은 부팅(~4초)이 아니라 타이핑(글자당 0.3초)이다.
```

를 이것으로 바꾼다.

```bash
# 그래서 루트 게이트 한 번의 총 부팅 횟수는 15회에서 18회가 된다.
# 이 체인에서 비싼 쪽은 부팅(~4초)이 아니라 타이핑(글자당 0.3초)이다.
#
# PM 체인은 전원 관리를 본다. 게스트 셸에 `kill -TERM 1`을 타이핑하고,
# PID 1이 자식을 정리한 뒤 reboot(2)를 부르는 것까지 로그로 확인한다.
# 이 체인만 shell=bash가 적힌 디스크를 물고 뜬다 — kill이 initrd에
# 바이너리로 없어서 빌트인이 확실한 셸이 필요하기 때문이다.
#
# PM-M0은 부팅 1회다. 그래서 총 부팅 횟수는 18회에서 21회가 된다.
# PM-M1이 재부팅을 보는 부팅을 하나 더 붙이면 24회가 된다.
```

- [ ] **Step 3: 루트 게이트를 돌린다**

이 명령은 25분쯤 걸린다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh
```

기대: 마지막 줄이

```
TARS check PASS: all chains 3/3 consecutive runs succeeded
```

그리고 그 앞에 `PM-M0 PASS: 3/3 consecutive runs succeeded`가 있어야 한다.

**실제 소요 시간을 기록해 달라.** `HANDOFF.md`와 다음 plan이 그 숫자를 쓴다.

- [ ] **Step 4: 커밋**

```bash
git add check.sh
git commit -m "Register the Power Management chain in the root gate"
```

- [ ] **Step 5: `HANDOFF.md`를 갱신한다**

Claude가 쓴다. 담을 것: PM-M0 완료, 루트 게이트 다섯 체인과 실측 시간,
PM-M1에 남은 것(재시작·CAD_OFF·부팅 A·BF 사각지대), 그리고 이 milestone이
알아낸 사실 둘(대화형 셸의 `SIGTERM` 무시, ACPI 부재).

---

## 완료 조건

- [ ] `zig build test`가 검사 둘(`config_test`, `power_test`)을 통과한다
- [ ] `power/check.sh`가 단독으로 PASS한다
- [ ] 루트 게이트가 다섯 체인 3/3으로 PASS한다
- [ ] 커밋 다섯 개가 `main`에 있고 push까지 끝났다

## PM-M1 예고 (지금 하지 않는다)

`reboot(CAD_OFF)`, `SIGINT` → `RESTART`, `-no-reboot`을 뺀 부팅 A(설정을
고치고 게스트 안에서 재부팅해 반영을 확인), 그리고 `boot/check.sh`의
사각지대 닫기. plan은 PM-M0이 끝난 뒤에 새로 쓴다.
