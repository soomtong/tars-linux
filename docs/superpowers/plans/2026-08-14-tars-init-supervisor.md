# TARS Init Supervisor (IS) Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 파일 작성과
> 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을 제시하고
> 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는 이 저장소에 적용하지 않는다.

**Goal:** PID 1이 실제로 PID 1의 일을 하게 만든다. `init`은 더 이상 자신을
셸로 덮어쓰지 않고, 자식 둘(`/terminal`, 콘솔 셸)을 fork해 감독한다.
`waitpid` 루프로 좀비를 거두고, 자식이 죽으면 되살리며, **절대 반환하지
않는다.**

**Scope:** 서브프로젝트가 아니라 **단일 milestone**이다. 다음 서브프로젝트
(설정 영속화 + 부팅 셸 선택)의 준비운동이며, 그쪽이 요구하는 "설정을 읽어
셸을 고른다"가 정확히 이 구조 변경 위에 얹힌다. design doc은 만들지 않는다.

**Tech Stack:** Zig 0.16.0(`std.os.linux`, `std.process.Init.Minimal`), bash,
Docker(`tars-devcontainer`, arm64), QEMU

---

## 왜 이 milestone인가

현재 부팅 후 프로세스 트리는 이렇다.

```
PID 1 = fish              ← init이 execve로 자기를 덮어씀 (init/src/main.zig:108)
  └─ /terminal            ← execve 전에 fork해 둔 자식 (init/src/main.zig:52)
       └─ fish            ← PTY 안. 화면(DRM)에 그려지는 쪽
```

문제가 셋이다.

1. **PID 1이 죽으면 커널이 패닉한다.** `execve` 이후 PID 1은 fish 그 자체다.
   fish가 끝나면 `Attempted to kill init!`이 난다.
2. **아무도 `waitpid`를 하지 않는다.** 리눅스는 부모를 잃은 프로세스를 전부
   PID 1에 재부모화하는데, 지금 PID 1은 그것을 거둘 코드가 없는 fish다.
3. **`/terminal`이 죽지 않으려고 버틴다**(`terminal/src/main.zig:152-156`).
   PTY 자식이 끝나면 `poll(fds, 0, 1000)`으로 영원히 잠든다. TF 단계에서
   "자식이 죽어도 패닉하지 말자"고 넣은 코드인데, **되살려 줄 감독자가
   없었기 때문에** 필요했던 임시방편이다.

3번을 함께 고치는 것이 이 plan의 핵심 결정이다. 감독자가 생기면 이 버티기는
방해가 된다 — 화면 셸을 끝내도 아무 일이 안 일어나므로 **재시작 경로를
게이트에서 관측할 방법이 사라진다.** 반대로 `/terminal`이 정상 종료하게
두면, 게이트에서 `exit` 한 번으로 "죽음 → 수거 → 재시작 → 새 프롬프트"
전 경로가 한 번에 검증된다.

목표 트리:

```
PID 1 = tars-init         ← 절대 반환하지 않음. waitpid 루프
  ├─ /terminal            ← 죽으면 재시작
  │    └─ fish (PTY)
  └─ fish (/dev/console)  ← 죽으면 재시작
```

---

## 설계

### 재시작 정책

무조건 재시작하면 `/terminal`이 DRM을 못 열 때 초당 수천 번 fork하는 상태가
된다. 그래서 두 가지를 건다.

- 재시작 직전 **1초 `nanosleep`**.
- **10초를 못 채우고 죽은 것이 연속 3회**면 그 컴포넌트를 포기하고 로그만
  남긴다. 10초 이상 살았으면 카운터를 0으로 되돌린다.

포기해도 **루프는 계속 돈다.** 좀비 수거는 PID 1이 지는 의무이고, 감독 대상이
전부 포기 상태여도 그 의무는 남는다.

3회로 잡은 이유는 BF 체인 때문이다. BF는 `-device virtio-gpu-pci` 없이
부팅하므로 `/terminal`이 매번 DRM 열기에 실패해 죽는다. 재시도 횟수가 그대로
BF 로그의 노이즈이자 시리얼 출력 경합이 되므로 작게 잡는다.

### 콘솔 셸의 제어 터미널

지금은 PID 1이 스스로 `setsid()` + `TIOCSCTTY`를 하고 그대로 fish가 된다
(`init/src/main.zig:79-80`). 앞으로 이 시퀀스는 **콘솔 셸 자식 안에서** 돈다 —
`/dev/console`을 제어 터미널로 잡고 세션 리더가 되는 것은 셸의 일이다.

PID 1 자신은 커널이 열어준 fd 0/1/2(`/dev/console`)를 그대로 쓴다. 그래서
`std.debug.print`가 지금처럼 시리얼로 나간다 — 첫 줄
`tars-init: starting as PID 1`이 `setupControllingTerminal()`보다 먼저 찍히는
것이 이미 그 증거다.

### 시간 측정

`clock_gettime(MONOTONIC)`을 쓴다. libc가 없어도 안전하다 —
`std/start.zig:550`이 libc 없는 시작 경로에서 `elf_aux_maybe`를 채우므로
std의 vDSO 조회가 동작하고, auxv에 `AT_SYSINFO_EHDR`이 없더라도 시스템 콜로
폴백한다.

### 이번에 새로 쓰는 Zig 0.16.0 API

전부 호스트의 std 소스(`/opt/homebrew/Cellar/zig/0.16.0_1/lib/zig/std`,
컨테이너와 같은 0.16.0)에서 확인했다.

| 쓰는 것 | 위치 | 시그니처 / 값 |
|---|---|---|
| `waitpid` | `os/linux.zig:1804` | `fn waitpid(pid: pid_t, status: *u32, flags: u32) usize` (내부는 `wait4`) |
| `clock_gettime` | `os/linux.zig:1937` | `fn clock_gettime(clk_id: clockid_t, tp: *timespec) usize` |
| `nanosleep` | `os/linux.zig:1999` | `fn nanosleep(req: *const timespec, rem: ?*timespec) usize` |
| `timespec` | `os/linux.zig:8715` | `extern struct { sec: isize, nsec: isize }` |
| `clockid_t.MONOTONIC` | `os/linux.zig:5580` | `1` |
| `pid_t` | `os/linux.zig:3667` | `i32` |
| `W.IFEXITED` / `EXITSTATUS` / `TERMSIG` | `os/linux.zig:3880-3897` | 상태 워드 해석 |
| `E.CHILD` / `E.INTR` | `os/linux.zig:3086` / `3080` | `10` / `4` |

---

## 사전 준비

모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서 실행한다.
`main` 브랜치, working tree 깨끗한 상태에서 시작한다.

**`docker run`에 `--platform`을 붙이지 않는다.** 붙이면 ZM-M3에서 없앤
에뮬레이션 층이 그대로 돌아온다(`docs/decisions/project_build_host_arch.md`).

---

## Task 1: `init`을 supervisor로 다시 쓴다

**Files:**
- Modify: `init/src/main.zig`

- [ ] **Step 1: `init/src/main.zig` 전체 교체**

앞부분(`failed`, `mountFs`, `mountDevpts`, `logDrmDevicePresence`,
`setupControllingTerminal`)은 그대로다. 바뀌는 것은 `runTerminal`이
일반화된 `spawn`으로 대체되고, `main` 끝의 `execve`가 감독 루프로 바뀌는
것이다.

```zig
const std = @import("std");
const linux = std.os.linux;

/// 리눅스는 시스템 콜 실패를 "음수 errno"로 그대로 돌려준다. libc가 그것을
/// -1 리턴 + errno 전역 변수로 바꿔주는데, 여기서는 libc를 링크하지 않으므로
/// 그 변환을 직접 한다. 성공이면 null, 실패면 errno를 돌려준다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

fn mountFs(source: [:0]const u8, target: [:0]const u8, fstype: [:0]const u8) void {
    const rc = linux.mount(source.ptr, target.ptr, fstype.ptr, 0, 0);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: failed to mount {s} at {s} (errno {d})\n", .{
            fstype, target, @intFromEnum(e),
        });
    } else {
        std.debug.print("tars-init: mounted {s} at {s}\n", .{ fstype, target });
    }
}

/// devtmpfs는 드라이버가 등록한 장치 노드만 담기 때문에 /dev/pts 디렉터리를
/// 만들어주지 않는다. forkpty()는 /dev/ptmx를 연 뒤 커널이 지정한
/// /dev/pts/N을 열어야 하므로, 마운트 지점을 먼저 만들고 devpts를 붙인다.
fn mountDevpts() void {
    const rc = linux.mkdir("/dev/pts", 0o755);
    if (failed(rc)) |e| {
        if (e != .EXIST) {
            std.debug.print("tars-init: failed to create /dev/pts (errno {d})\n", .{
                @intFromEnum(e),
            });
            return;
        }
    }
    mountFs("devpts", "/dev/pts", "devpts");
}

fn logDrmDevicePresence() void {
    // 열지 않고 존재만 본다. 곧 fork될 /terminal이 이 장치를 독점해서
    // 열 것이므로 여기서는 건드리지 않는 편이 안전하다.
    if (failed(linux.access("/dev/dri/card0", linux.F_OK))) |_| {
        std.debug.print("tars-init: /dev/dri/card0 not found\n", .{});
    } else {
        std.debug.print("tars-init: /dev/dri/card0 exists\n", .{});
    }
}

/// 제어 터미널 잡기는 PID 1이 아니라 **콘솔 셸 자식**이 한다. setsid()로 새
/// 세션의 리더가 된 뒤 TIOCSCTTY로 /dev/console을 제어 터미널로 붙여야
/// Ctrl-C 같은 것이 그 셸에 전달된다. PID 1은 초기 세션에 그대로 남아
/// 커널이 열어준 fd 0/1/2로 자기 로그를 계속 찍는다.
fn setupControllingTerminal() void {
    const rc = linux.open("/dev/console", .{ .ACCMODE = .RDWR }, 0);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: failed to open /dev/console (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    const fd: i32 = @intCast(rc);

    _ = linux.setsid();
    _ = linux.ioctl(fd, linux.T.IOCSCTTY, 0);
    _ = linux.dup2(fd, 0);
    _ = linux.dup2(fd, 1);
    _ = linux.dup2(fd, 2);
    if (fd > 2) _ = linux.close(fd);
}

/// 감독 대상. 지금은 둘뿐이라 배열을 컴파일 타임에 고정한다. 설정 파일에서
/// 목록을 읽는 것은 다음 서브프로젝트(설정 영속화)의 일이다.
const Kind = enum {
    terminal,
    console_shell,

    fn name(self: Kind) []const u8 {
        return switch (self) {
            .terminal => "terminal",
            .console_shell => "console shell",
        };
    }

    fn path(self: Kind) [:0]const u8 {
        return switch (self) {
            .terminal => "/terminal",
            .console_shell => "/usr/bin/fish",
        };
    }
};

/// 이 초를 못 채우고 죽으면 "빨리 죽었다"로 센다.
const FAST_EXIT_SECONDS: isize = 10;
/// 빨리 죽는 것이 연속 이 횟수면 그 컴포넌트를 포기한다. BF 체인은 GPU가
/// 없어 /terminal이 매번 죽으므로 이 숫자가 곧 BF 로그의 노이즈 양이다.
const MAX_FAST_RESTARTS: u32 = 3;

const Child = struct {
    kind: Kind,
    /// -1이면 지금 돌고 있지 않다는 뜻이다.
    pid: linux.pid_t = -1,
    started_at: isize = 0,
    fast_restarts: u32 = 0,
    given_up: bool = false,
};

fn monotonicSeconds() isize {
    var ts: linux.timespec = undefined;
    if (failed(linux.clock_gettime(.MONOTONIC, &ts))) |_| return 0;
    return ts.sec;
}

fn sleepOneSecond() void {
    const req = linux.timespec{ .sec = 1, .nsec = 0 };
    _ = linux.nanosleep(&req, null);
}

fn spawn(kind: Kind, envp: [*:null]const ?[*:0]const u8) linux.pid_t {
    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: fork for {s} failed (errno {d})\n", .{
            kind.name(), @intFromEnum(e),
        });
        return -1;
    }
    if (pid == 0) {
        // 여기부터는 자식이다.
        if (kind == .console_shell) setupControllingTerminal();
        const p = kind.path();
        const argv = [_:null]?[*:0]const u8{p.ptr};
        _ = linux.execve(p.ptr, &argv, envp);
        // execve가 돌아왔다는 것은 실패했다는 뜻이다.
        std.debug.print("tars-init: execve {s} failed\n", .{p});
        linux.exit(127);
    }
    return @intCast(pid);
}

fn start(c: *Child, envp: [*:null]const ?[*:0]const u8) void {
    const pid = spawn(c.kind, envp);
    if (pid < 0) return; // 다음 바퀴에서 다시 시도한다
    c.pid = pid;
    c.started_at = monotonicSeconds();
    std.debug.print("tars-init: started {s} (pid {d})\n", .{ c.kind.name(), pid });
}

fn find(children: []Child, pid: linux.pid_t) ?*Child {
    for (children) |*c| {
        if (c.pid == pid) return c;
    }
    return null;
}

/// PID 1의 본체. **절대 반환하지 않는다** — 반환하면 커널이 패닉한다.
fn supervise(children: []Child, envp: [*:null]const ?[*:0]const u8) noreturn {
    while (true) {
        var alive: usize = 0;
        for (children) |*c| {
            if (c.pid < 0 and !c.given_up) start(c, envp);
            if (c.pid >= 0) alive += 1;
        }

        // 감독 대상이 전부 포기 상태여도 PID 1은 죽으면 안 되고, 재부모화된
        // 고아를 거둘 의무도 남는다. 그래서 종료하지 않고 쉬면서 돈다.
        if (alive == 0) {
            sleepOneSecond();
            continue;
        }

        var status: u32 = 0;
        const rc = linux.waitpid(-1, &status, 0);
        if (failed(rc)) |e| {
            if (e == .INTR) continue;
            if (e != .CHILD) {
                std.debug.print("tars-init: waitpid failed (errno {d})\n", .{
                    @intFromEnum(e),
                });
            }
            sleepOneSecond();
            continue;
        }
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

        std.debug.print("tars-init: restarting {s} in 1s\n", .{c.kind.name()});
        sleepOneSecond();
    }
}

pub fn main(init: std.process.Init.Minimal) void {
    // 커널이 PID 1의 스택에 올려준 환경 변수 블록.
    const envp = init.environ.block.slice.ptr;

    std.debug.print("tars-init: starting as PID 1\n", .{});

    mountFs("proc", "/proc", "proc");
    mountFs("sysfs", "/sys", "sysfs");
    mountFs("devtmpfs", "/dev", "devtmpfs");
    mountDevpts();

    logDrmDevicePresence();

    var children = [_]Child{
        .{ .kind = .terminal },
        .{ .kind = .console_shell },
    };
    supervise(&children, envp);
}
```

**로그 문자열이 바뀌는 지점을 정리해 둔다.** 게이트가 grep하는 마운트 네 줄
(`tars-init: mounted ...`)은 **하나도 안 바뀐다**. 없어지는 줄은
`tars-init: forked terminal (pid N)`과
`tars-init: set up /dev/console as controlling terminal` 둘이고, 어느 게이트도
이 둘을 보지 않는다(`boot/check.sh:53-57`, `terminal/check.sh:198-202`).

- [ ] **Step 2: 빌드**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c 'cd init && zig build'
```

Expected: 출력 없이 종료 코드 0.

컴파일 에러가 나면 그대로 붙여서 알릴 것. 가장 가능성 있는 실패 지점은
셋이다.

1. `for (children) |*c|` — `children`이 슬라이스이므로 포인터 캡처가 되지만,
   `main`의 `&children`이 `[]Child`로 coercion되는지.
2. `linux.timespec`의 필드 이름(`sec`/`nsec`). 0.16에서 확인했지만 아키텍처별
   분기가 있는 타입이다.
3. `void`를 반환하는 `main`의 마지막 문장이 `noreturn` 함수 호출인 것 —
   Zig는 허용하지만 unreachable 코드 경고가 날 수 있다.

- [ ] **Step 3: 정적 바이너리인지 재확인**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c \
  'readelf -d init/zig-out/bin/init | grep -c NEEDED; ls -l init/zig-out/bin/init'
```

Expected: 첫 줄이 `0`. `ldd`가 아니라 `readelf`인 이유는
`project_build_host_arch`의 규칙 2다 — 빌드 호스트가 arm64라 x86_64 바이너리를
동적 로더에 태울 수 없다.

`0`이 아니면 어딘가에서 libc가 링크된 것이므로 즉시 알릴 것
(`kernel/make_initrd.sh`가 `init`에 대해 `copy_lib_deps`를 부르지 않는다).

- [ ] **Step 4: Commit**

Claude가 수행한다. 사용자는 Step 2·3 결과만 전달하면 된다.

---

## Task 2: `terminal`이 PTY EOF에서 정상 종료하게 한다

**Files:**
- Modify: `terminal/src/main.zig:151-157`

- [ ] **Step 1: 무한 sleep 제거**

현재 파일 끝(151~157번째 줄):

```zig
    // 자식이 죽어도 패닉하지 않고 화면을 유지한 채 남는다.
    // nfds=0인 poll은 "아무 fd도 안 보고 timeout만 기다린다" = sleep이다.
    while (true) {
        _ = c.poll(&fds, 0, 1000);
    }
}
```

이것을 다음으로 바꾼다:

```zig
    // 셸이 끝나면 터미널도 끝난다. PID 1(tars-init)이 우리를 다시 띄우고,
    // 새 프로세스가 DRM을 다시 열어 새 프롬프트를 그린다. TF 시절의 무한
    // sleep은 되살려 줄 감독자가 없어서 필요했던 것이라 이제 지운다.
}
```

`main`의 반환 타입은 그대로 두고, EOF에서 `break`한 뒤 `defer`들이 정리를
수행하며 자연스럽게 0으로 종료한다.

**PTY 자식(fish)을 여기서 `waitpid`하지 않는 것은 의도적이다.** 우리가 곧
종료하므로 그 좀비는 PID 1로 재부모화되고, PID 1이 거둔다 — 게이트는 그
`tars-init: reaped orphan pid N` 줄로 **좀비 수거가 실제로 동작함을
관측한다.** 이 milestone이 고치려는 문제 2번의 직접 증거다.

- [ ] **Step 2: Commit**

Claude가 수행한다. 빌드는 Task 3의 게이트 실행에서 함께 확인한다.

---

## Task 3: TF 게이트에 재시작 경로 검증을 추가한다

**Files:**
- Modify: `terminal/check.sh`

게이트는 자기가 안 보는 것을 통과시킨다
(`docs/decisions/project_gate_chain_composition.md`). 재시작을 코드로만
만들고 검사를 안 넣으면, 다음 milestone에서 조용히 깨져도 PASS가 난다.

- [ ] **Step 1: `exit` 주입과 검증 블록 추가**

**위치가 중요하다.** 키를 보내려면 QEMU monitor로 연결된 **fd 3이 아직 열려
있어야** 한다. 그 구간은 141번째 줄에서 끝난다.

```
138  # 3) 키를 넣은 뒤 화면
139  echo "screendump ${AFTER}" >&3
140  sleep 1
141                    <-- 여기에 아래 블록을 넣는다
142  exec 3<&-
143  exec 3>&-
```

즉 `AFTER` 스크린샷을 먼저 뜨고(터미널이 아직 살아 있는 화면), **그 뒤에**
`exit`를 친다. 42 검증(182~188번째 줄)은 QEMU가 죽은 뒤 `$LOG` 파일만 보는
구간이라 그쪽에는 넣을 수 없다.

넣을 블록:

```bash
# --- 재시작 경로 검증 (IS) ---------------------------------------------
# 화면 셸에 exit를 쳐서 죽인다. 그러면 이 순서가 일어나야 한다:
#   fish 종료 → terminal이 PTY EOF로 종료 → PID 1이 수거 → PID 1이 재시작
#   → 새 terminal이 DRM을 다시 열고 새 프롬프트를 그린다
# 이 milestone 전에는 terminal이 무한 sleep으로 버텨서 아무 일도 안 났다.
SPAWNS_BEFORE=$(grep -c "terminal: spawned child pid" "$LOG")

for k in e x i t ret; do
  echo "sendkey $k" >&3
  sleep 0.3
done

RESTARTED=0
for _ in $(seq 1 60); do
  if [ "$(grep -c "terminal: spawned child pid" "$LOG")" -gt "$SPAWNS_BEFORE" ]; then
    RESTARTED=1
    break
  fi
  sleep 1
done

if [ "$RESTARTED" != "1" ]; then
  echo "FAIL: init did not restart the terminal within 60s after the shell exited"
  echo "--- restart markers ---"
  for marker in \
    "terminal: child exited (pty EOF)" \
    "tars-init: terminal exited" \
    "tars-init: restarting terminal" \
    "tars-init: started terminal"; do
    if grep -q "$marker" "$LOG"; then
      echo "  ok      ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  tail -n 60 "$LOG"
  exit 1
fi
echo "init restarted the terminal after the shell exited"

# 좀비 수거 검증: 죽은 fish는 terminal이 거두지 않으므로 PID 1로
# 재부모화되고, PID 1이 거둔다. 이 줄이 없으면 좀비가 쌓인다는 뜻이다.
if ! grep -q "tars-init: reaped orphan pid" "$LOG"; then
  echo "FAIL: init never reaped a re-parented orphan"
  tail -n 60 "$LOG"
  exit 1
fi
echo "init reaped the re-parented shell"

# 이 milestone의 존재 이유를 직접 지키는 검사.
if grep -q "Attempted to kill init" "$LOG"; then
  echo "FAIL: kernel panicked because PID 1 exited"
  tail -n 60 "$LOG"
  exit 1
fi
```

- [ ] **Step 2: 나머지 검사 블록은 손대지 않는다**

149번째 줄 이후(스크린샷 존재 확인, 픽셀 차이, 42 검증,
`--- init log ---`와 마운트 네 줄 검사)는 전부 그대로 둔다. Step 1의 블록이
그 앞에 들어가므로 줄 번호만 밀린다.

주의할 것 하나: Step 1 블록은 `exit` 이후 **새 프롬프트가 그려진 화면**을
만들어 놓고 끝난다. 그 뒤의 픽셀 차이 검사는 `BEFORE`(첫 프롬프트)와
`AFTER`(42가 찍힌 화면)를 비교하므로 영향을 받지 않는다 — 두 스크린샷 모두
`exit`를 치기 **전**에 떴기 때문이다.

- [ ] **Step 3: Commit**

Claude가 수행한다.

---

## Task 4: 두 체인을 각각 1회 돌린다

**Files:** 없음(확인만)

`init`과 `make_initrd.sh` 경로를 건드리지 않았더라도 `init` 바이너리 자체가
바뀌었으므로 **두 체인을 모두** 돈다. BF는 initrd 로딩 경로가 다르다
(limine이 ISO9660에서 BIOS INT13h로 읽는다).

- [ ] **Step 1: TF 체인**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/check.sh 2>&1 | tee /tmp/is-tf.log
```

Expected 마지막: `PASS`. 중간에 새로 나와야 하는 두 줄:

```
init restarted the terminal after the shell exited
init reaped the re-parented shell
```

**여기가 이 milestone에서 가장 깨지기 쉬운 지점이다.** 재시작된 `/terminal`이
DRM master를 다시 잡을 수 있어야 한다. 죽은 프로세스의 fd가 닫히면 커널이
master를 놓는 것이 정상 동작이지만, QEMU virtio-gpu에서 두 번째 modeset이
깨끗하게 되는지는 돌려봐야 안다.

실패하면 `--- restart markers ---` 출력을 그대로 붙여서 알릴 것. 어디까지
갔는지가 원인을 가른다.

- `terminal: child exited (pty EOF)`가 없다 → `exit` 키 주입이 안 먹었다.
- `tars-init: terminal exited`가 없다 → Task 2가 반영 안 됐다(터미널이 아직
  버티고 있다).
- `tars-init: started terminal`은 있는데 `terminal: spawned child pid`가 안
  늘었다 → **재시작된 터미널이 DRM/evdev를 다시 열지 못한 것이다.** 이 경우
  `error: OpenFailed`나 `cannot open /dev/input/event0`이 로그에 있을 것이다.
  여기서 막히면 A안(터미널은 그대로 두고 콘솔 셸로만 검증)으로 후퇴한다.

- [ ] **Step 2: BF 체인**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash boot/check.sh 2>&1 | tee /tmp/is-bf.log
```

Expected: `PASS`, 배너까지 약 4초.

**BF에서는 로그가 눈에 띄게 달라진다.** GPU가 없어 `/terminal`이 매번 죽으므로
이런 흐름이 정상이다.

```
tars-init: /dev/dri/card0 not found
tars-init: started terminal (pid N)
tars-init: started console shell (pid M)
error: OpenFailed                         ← terminal이 DRM을 못 연다
tars-init: terminal exited (pid N, status 1, lived 0s)
tars-init: restarting terminal in 1s
...(3회 반복)...
tars-init: giving up on terminal after 3 fast exits
```

그리고 fish 배너는 그대로 나와야 한다. **배너 grep이 실패하면
`MAX_FAST_RESTARTS`를 낮추는 것을 검토한다** — 터미널의 에러 출력과 fish
배너가 같은 시리얼에 섞여 배너 줄이 쪼개졌을 가능성이 있다.

- [ ] **Step 3: 로그 확인**

Run:
```bash
grep -E 'tars-init:|Attempted to kill init' /tmp/is-bf.log
```

Expected: `Attempted to kill init`이 **없어야** 한다.

---

## Task 5: 종료 게이트 3/3

**Files:** 없음(확인만)

- [ ] **Step 1: 루트 게이트 전체**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash check.sh 2>&1 | tee /tmp/is-gate.log
```

Expected 마지막 줄:
```
TARS check PASS: all chains 3/3 consecutive runs succeeded
```

ZM-M3 기준 전체 8분 52초. 걸린 시간을 기록할 것 — 재시작 대기(1초 backoff)와
BF의 3회 재시도가 얼마나 더해지는지 보는 숫자다.

- [ ] **Step 2: 6회 전부에서 확인**

Run:
```bash
grep -c 'tars-init: starting as PID 1' /tmp/is-gate.log
grep -c 'Attempted to kill init' /tmp/is-gate.log
grep -c 'init restarted the terminal after the shell exited' /tmp/is-gate.log
```

Expected: `6`, `0`, `3`(TF 3회분).

두 번째가 0이 아니면 게이트가 PASS했더라도 실패로 본다.

---

## Task 6: 문서와 기억 갱신

**Files:**
- Modify: `HANDOFF.md`
- Modify: 이 plan 파일(말미에 "실제 실행에서 plan과 달라진 점" 추가)
- Create: `docs/decisions/project_init_supervisor.md`, `MEMORY.md`에 한 줄

- [ ] **Step 1: Claude가 문서를 갱신한다**

사용자는 Task 5까지의 결과만 전달하면 된다.

갱신 내용:
- 이 plan 말미에 "실제 실행에서 plan과 달라진 점". **다음 세션이 가장 먼저
  읽는 부분이므로 빠짐없이 적는다.**
- `docs/decisions/project_init_supervisor.md` — PID 1이 지는 의무와 재시작
  정책, 그리고 "게이트가 재시작을 관측하려면 터미널이 죽어야 한다"는 결합
  관계를 남긴다. 다음 서브프로젝트가 이 구조 위에 설정 읽기를 얹는다.
- `HANDOFF.md`를 다음 서브프로젝트(설정 영속화 + 부팅 셸 선택) 기준으로
  다시 쓴다.

- [ ] **Step 2: Commit**

Claude가 수행한다.

---

## 이번 milestone에서 하지 않는 것

- **시그널 처리(SIGTERM/SIGINT/reboot).** PID 1은 기본 처리기가 없어 신호를
  무시하는 것이 기본이고, 지금 신호를 보낼 주체가 없다. 전원 관리(reboot,
  poweroff)를 다룰 때 함께 한다.
- **설정 파일에서 감독 목록·재시작 정책 읽기.** 다음 서브프로젝트(설정
  영속화)의 첫 사용 사례다. 지금은 `Kind` enum에 컴파일 타임으로 고정한다.
- **부팅 셸 선택.** 같은 이유로 다음 서브프로젝트.
- **`terminal`이 자기 PTY 자식을 `waitpid`하는 것.** 일부러 안 한다 — 좀비를
  PID 1로 흘려보내야 게이트가 수거를 관측할 수 있다(Task 2 Step 1 참고).
- **`init`을 `ReleaseSafe`로 바꾸는 것.** initrd 크기가 실제 문제가 될 때
  꺼낼 카드로 계속 남긴다.
