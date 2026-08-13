# TARS Zig Migration — ZM-M1 `init`을 Zig로 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **단, 이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md` 참고):** 파일
> 작성과 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을
> 제시하고 결과를 해석한다. 위 SUB-SKILL 문구는 다른 저장소용 기본값이며 이
> 저장소에는 적용하지 않는다.

**Goal:** PID 1인 `tars-init`을 Rust에서 Zig로 다시 쓴다. **libc를 링크하지
않고** `std.os.linux`의 raw syscall을 직접 호출한다. 관측 가능한 동작은 한
줄도 바꾸지 않는다 — 로그 문자열까지 그대로 유지한다.

**Architecture:** Rust 소스는 이 milestone에서 지우지 않는다(ZM-M2에서 지운다).
`init/`에 `build.zig`와 `src/main.zig`를 추가해 Cargo와 잠시 공존시키고,
initrd·게이트 스크립트가 참조하는 산출물 경로만 `init/target/release/tars-init`
에서 `init/zig-out/bin/init`으로 옮긴다. 게이트가 깨지면 그 한 줄만 되돌리면
Rust 시절로 복귀한다.

libc를 링크하지 않는 선택에서 따라오는 결과가 둘이다. 첫째,
`kernel/make_initrd.sh`의 `copy_lib_deps "$WORKDIR/init"`이 불필요해진다 —
정적 바이너리라 `.so` 의존이 없다. 둘째, 리눅스가 실패를 "음수 errno"로
그대로 돌려주는 규약을 코드에서 직접 다루게 된다. libc가 `-1` 리턴 + `errno`
전역으로 바꿔주던 그 변환을 `std.os.linux.errno()`로 우리가 한다.

**Tech Stack:** Zig 0.16.0(`std.os.linux`, `std.process.Init.Minimal`),
bash, Docker(`tars-devcontainer` 이미지), QEMU

---

## 사전 준비

이 plan의 모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서
실행한다. Terminal Foundation이 완료되어 `./check.sh`가 `TARS check PASS`로
끝남이 확인된 상태여야 한다(design doc 커밋 `b9b2b65`, working tree는
`.claude/` 미추적만 남은 상태).

**이 milestone에서 쓰는 Zig 0.16.0 API는 전부 호스트의 표준 라이브러리
소스(`/opt/homebrew/Cellar/zig/0.16.0_1/lib/zig/std`, 컨테이너와 동일한
0.16.0)에서 확인했다.** 문서가 아니라 소스에서 확인한 것들이라 시그니처는
정확하다.

| 쓰는 것 | 위치 | 시그니처 |
|---|---|---|
| `errno` | `os/linux.zig:592` | `fn errno(r: usize) E` |
| `mount` | `os/linux.zig:994` | `fn mount(special: ?[*:0]const u8, dir: [*:0]const u8, fstype: ?[*:0]const u8, flags: u32, data: usize) usize` |
| `mkdir` | `os/linux.zig:970` | `fn mkdir(path: [*:0]const u8, mode: mode_t) usize` |
| `access` | `os/linux.zig:1394` | `fn access(path: [*:0]const u8, mode: u32) usize` |
| `fork` | `os/linux.zig:656` | `fn fork() usize` |
| `execve` | `os/linux.zig:638` | `fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) usize` |
| `open` | `os/linux.zig:1554` | `fn open(path: [*:0]const u8, flags: O, perm: mode_t) usize` |
| `setsid` | `os/linux.zig:2153` | `fn setsid() usize` |
| `ioctl` | `os/linux.zig:2759` | `fn ioctl(fd: fd_t, request: u32, arg: usize) usize` |
| `dup2` | `os/linux.zig:606` | `fn dup2(old: i32, new: i32) usize` |
| `close` | `os/linux.zig:1592` | `fn close(fd: fd_t) usize` |
| `exit` | `os/linux.zig:1679` | `fn exit(status: i32) noreturn` |
| `T.IOCSCTTY` | `os/linux.zig:5241` | `0x540e` |
| `F_OK` | `os/linux.zig:3867` | `0` |
| `O` | `os/linux.zig:310` | x86_64는 `packed struct(u32)`, `.ACCMODE` 필드 |

**design doc의 리스크 두 개가 이 조사로 해소됐다.**

1. **`TIOCSCTTY`를 손으로 선언할 필요가 없다.** `std.os.linux.T.IOCSCTTY`가
   이미 있다(x86_64에서 `0x540e`). design doc의 "필요한 상수는 손으로
   선언한다"는 이 milestone에서는 적용되지 않는다.
2. **`environ` 대체 경로가 확정됐다.** Zig 0.16의 main은 첫 인자로
   `std.process.Init.Minimal`을 받을 수 있고(`std/start.zig:699`), 그 안의
   `environ.block.slice`가 커널이 PID 1 스택에 올려준 envp다. libc 없이
   시작하는 경로(`std/start.zig:508-519`)가 스택에서 직접 읽어 채운다.
   `.ptr`을 붙여 `execve`에 넘기는 것은 std 자신이 쓰는 방식과 같다
   (`std/Io/Threaded.zig:16792`의 `env_block.slice.ptr`).

**`Init.Minimal`을 쓰는 이유:** 인자 없는 `main()`이나 전체 `Init`을 받으면
`std/start.zig:704-716`이 allocator·`Io.Threaded`·environ map을 먼저
구성한다. PID 1에게는 전부 불필요한 준비 작업이고, libc 없는 Debug 빌드에서는
`smp_allocator`까지 끌어온다. `Init.Minimal`은 그 분기를 통째로 건너뛴다.

---

## Task 1: Zig 프로젝트 골격과 빌드

이 Task는 **부팅 경로를 건드리지 않는다.** initrd에는 여전히 Rust `init`이
들어간다. 여기서 확인하는 것은 "Zig로 컴파일이 되는가"와 "정적 바이너리가
나오는가" 둘뿐이다.

**Files:**
- Modify: `.gitignore`
- Create: `init/build.zig`
- Create: `init/src/main.zig`

- [ ] **Step 1: `.gitignore`에 Zig 산출물 추가**

`init/target/` 줄 **바로 아래**에 두 줄을 넣는다. 첫 `zig build`보다 먼저
해야 한다 — 이 저장소는 빌드 산출물을 실수로 커밋한 전력이 있다
(`CLAUDE.md`의 "Commit 전 git status 확인").

수정 후 `.gitignore`의 해당 부분:

```gitignore
init/target/
init/zig-out/
init/.zig-cache/
kms/target/
```

- [ ] **Step 2: `init/build.zig` 작성**

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    // 타깃을 호스트 기본값이 아니라 명시적으로 고정한다. 이유는
    // terminal/build.zig와 같다 — 게스트는 항상 x86_64 리눅스이고,
    // ZM-M3에서 빌드 컨테이너가 arm64로 바뀌어도 이 파일은 그대로여야 한다.
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .musl,
        .cpu_model = .baseline,
    });
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // PID 1은 스레드를 만들지 않는다. 끄면 TLS 준비 과정이 빠지고
        // 바이너리도 작아진다.
        .single_threaded = true,
    });
    // link_libc는 건드리지 않는다. 기본값이 false이고, 그것이 이 milestone의
    // 핵심 결정이다 — init이 쓰는 것은 전부 시스템 콜이라 libc가 필요 없고,
    // 링크하지 않으면 정적 바이너리가 되어 initrd에 .so를 넣지 않아도 된다.

    const exe = b.addExecutable(.{
        .name = "init",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);
}
```

`abi`를 `.musl`로 둔 것은 관례일 뿐 실질 영향이 없다. libc를 링크하지 않으면
abi 태그는 링크 결과에 관여하지 않는다.

- [ ] **Step 3: `init/src/main.zig` 작성**

Rust판(`init/src/main.rs`)과 함수 단위로 1:1 대응하고, **출력 문자열도 전부
동일하다.** 다른 것은 libc 래퍼가 raw syscall로 바뀐 것뿐이다.

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
        // 이미 있으면 문제가 아니다. Rust판의 create_dir_all이 조용히
        // 넘어가던 경우와 같다.
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

fn runTerminal(envp: [*:null]const ?[*:0]const u8) void {
    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: fork for terminal failed (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    if (pid == 0) {
        const argv = [_:null]?[*:0]const u8{"/terminal"};
        _ = linux.execve("/terminal", &argv, envp);
        // execve가 돌아왔다는 것은 실패했다는 뜻이다.
        std.debug.print("tars-init: execve /terminal failed\n", .{});
        linux.exit(1);
    }
    std.debug.print("tars-init: forked terminal (pid {d})\n", .{pid});
}

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

    std.debug.print("tars-init: set up /dev/console as controlling terminal\n", .{});
}

pub fn main(init: std.process.Init.Minimal) void {
    // 커널이 PID 1의 스택에 올려준 환경 변수 블록. Rust판이 libc의 `environ`
    // 전역을 extern으로 가져다 쓰던 자리를 대신한다.
    const envp = init.environ.block.slice.ptr;

    std.debug.print("tars-init: starting as PID 1\n", .{});

    mountFs("proc", "/proc", "proc");
    mountFs("sysfs", "/sys", "sysfs");
    mountFs("devtmpfs", "/dev", "devtmpfs");
    mountDevpts();

    logDrmDevicePresence();

    runTerminal(envp);

    setupControllingTerminal();

    const argv = [_:null]?[*:0]const u8{"/usr/bin/fish"};
    _ = linux.execve("/usr/bin/fish", &argv, envp);

    // 여기 도달했다는 것은 fish를 띄우지 못했다는 뜻이다. Rust판과 마찬가지로
    // PID 1이 그냥 반환하며, 커널이 곧 패닉을 낸다. 그 동작을 유지한다.
    std.debug.print("tars-init: execve failed\n", .{});
}
```

- [ ] **Step 4: 빌드**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c 'cd init && zig build'
```

Expected: 아무 것도 출력하지 않고 종료 코드 0. `init/zig-out/bin/init`이
생긴다.

컴파일 에러가 나면 그대로 붙여서 알려줄 것. 위 API는 전부 0.16.0 소스에서
확인했지만, 가장 가능성 있는 실패 지점은 `init.environ.block.slice.ptr`의
타입 coercion과 `main`의 인자 타입 매칭이다.

- [ ] **Step 5: 정적 바이너리인지 확인**

libc를 링크하지 않은 것이 실제로 반영됐는지 보는 단계다. 이게 확인돼야
Task 2에서 `copy_lib_deps` 줄을 지울 수 있다.

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c \
  'file init/zig-out/bin/init; ldd init/zig-out/bin/init; ls -l init/zig-out/bin/init init/target/release/tars-init'
```

Expected:
- `file`: `ELF 64-bit LSB executable, x86_64 ... statically linked`
- `ldd`: `not a dynamic executable`
- `ls -l`: Zig판 크기와 Rust판 크기가 함께 보인다. Debug 빌드라 Zig판이
  더 클 수 있는데, initrd는 gzip으로 압축되므로 문제가 아니다
  (`make_initrd.sh:57-62`). 두 숫자를 기록해 둘 것.

`ldd`가 `not a dynamic executable`이 아니라 라이브러리 목록을 뱉으면 어딘가에서
libc가 링크된 것이다. 그 경우 Task 2의 `copy_lib_deps` 삭제를 하면 안 되므로
즉시 알릴 것.

- [ ] **Step 6: Commit**

```bash
git add .gitignore init/build.zig init/src/main.zig
git status
git commit -m "Add a Zig implementation of init alongside the Rust one"
```

`git status`에 `init/zig-out/`이나 `init/.zig-cache/`가 보이면 Step 1이
반영되지 않은 것이다 — 커밋하지 말고 알릴 것.

---

## Task 2: 부팅 경로를 Zig `init`으로 전환

여기서 실제로 부팅되는 PID 1이 바뀐다.

**Files:**
- Modify: `kernel/make_initrd.sh:20`, `kernel/make_initrd.sh:45`
- Modify: `boot/check.sh:7`
- Modify: `terminal/check.sh:14`
- Modify: `check.sh:18`

- [ ] **Step 1: `kernel/make_initrd.sh`의 복사 경로 변경**

현재 20번째 줄:

```bash
cp ../init/target/release/tars-init "$WORKDIR/init"
```

이것을 다음으로 바꾼다:

```bash
cp ../init/zig-out/bin/init "$WORKDIR/init"
```

- [ ] **Step 2: `kernel/make_initrd.sh`에서 init의 라이브러리 복사 제거**

45번째 줄 `copy_lib_deps "$WORKDIR/init"`을 **삭제**하고, 그 자리에 왜
없어졌는지 남긴다. 수정 후 45~50번째 줄 근처는 이렇게 된다:

```bash
# init은 libc를 링크하지 않는 정적 바이너리라 copy_lib_deps가 필요 없다
# (ZM-M1). 나머지는 전부 glibc 동적 링크다.
copy_lib_deps "$WORKDIR/terminal"
copy_lib_deps "$WORKDIR/usr/bin/fish"
copy_lib_deps "$WORKDIR/usr/bin/cat"
copy_lib_deps "$WORKDIR/usr/bin/uname"
copy_lib_deps "$WORKDIR/usr/bin/mkdir"
```

- [ ] **Step 3: `boot/check.sh`의 빌드 명령 교체**

현재 7번째 줄:

```bash
(cd ../init && cargo build --release)
```

이것을 다음으로 바꾼다:

```bash
(cd ../init && zig build)
```

- [ ] **Step 4: `terminal/check.sh`의 빌드 명령 교체**

현재 14번째 줄이 포함된 블록:

```bash
if ! (cd ../init && cargo build --release); then
  echo "FAIL: init build failed"
  exit 1
fi
```

이것을 다음으로 바꾼다:

```bash
if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi
```

- [ ] **Step 5: 루트 `check.sh`의 clean 목록 갱신**

현재 18번째 줄:

```bash
  rm -rf kernel/build init/target terminal/zig-out terminal/.zig-cache out
```

이것을 다음으로 바꾼다:

```bash
  rm -rf kernel/build init/zig-out init/.zig-cache terminal/zig-out terminal/.zig-cache out
```

`init/.zig-cache`를 지워도 되는 이유는 `init`이 외부 패키지에 의존하지 않기
때문이다 — `terminal/zig-pkg`처럼 네트워크로만 복구되는 디렉터리가 생기지
않는다. 15~16번째 줄의 `kms/target` 관련 주석은 그대로 둔다(ZM-M2에서 함께
정리한다).

- [ ] **Step 6: TF 체인 1회 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/check.sh 2>&1 | tee /tmp/zm-m1-tf.log
```

Expected: 마지막에 `PASS`. 소요 시간은 TF-M4 때와 비슷할 것이다.

- [ ] **Step 7: `tars-init` 로그를 육안으로 확인**

**이 Step을 건너뛰면 안 된다.** 게이트는 `tars-init:` 로그를 하나도
grep하지 않으므로(`boot/check.sh:38`은 fish 배너를, `terminal/check.sh:87`은
`terminal: screen>`을 본다), `init`이 마운트에 전부 실패해도 부팅만 되면
PASS가 나올 수 있다.

Run:
```bash
grep 'tars-init:' /tmp/zm-m1-tf.log
```

Expected — 이 여덟 줄이 이 순서로 나와야 한다:

```
tars-init: starting as PID 1
tars-init: mounted proc at /proc
tars-init: mounted sysfs at /sys
tars-init: mounted devtmpfs at /dev
tars-init: mounted devpts at /dev/pts
tars-init: /dev/dri/card0 exists
tars-init: forked terminal (pid 2)
tars-init: set up /dev/console as controlling terminal
```

`failed to mount`가 하나라도 있으면 실패다. `pid`는 2가 아닐 수도 있다.
`/dev/dri/card0 exists`는 TF 체인에서만 나온다 — BF 체인은 `-device
virtio-gpu-pci` 없이 부팅하므로 `not found`가 정상이다(`HANDOFF.md`의 "실행
중 알게 된 사실" 참고).

로그가 이전(Rust판)과 다른 부분이 있으면 그 줄을 그대로 알릴 것.

- [ ] **Step 8: Commit**

```bash
git add kernel/make_initrd.sh boot/check.sh terminal/check.sh check.sh
git status
git commit -m "Boot the Zig init instead of the Rust one"
```

---

## Task 3: BF 체인 확인

BF는 TF와 initrd 로딩 경로가 다르다 — limine이 ISO9660에서 BIOS INT13h로
읽는다. `make_initrd.sh`를 건드렸으므로 반드시 따로 확인한다. DF-M3와
TF-M4에서 이 파일 변경으로 다른 체인이 조용히 깨진 사고가 두 번 있었다.

**Files:** 없음(확인만)

- [ ] **Step 1: BF 체인 1회 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash boot/check.sh 2>&1 | tee /tmp/zm-m1-bf.log
```

Expected: `PASS`. `boot/check.sh:35-47`이 fish 배너까지 걸린 실제 시간을
출력하므로 그 숫자를 기록할 것 — TF-M4 기준은 약 34초였다.

- [ ] **Step 2: 로그에서 두 가지 확인**

Run:
```bash
grep -E 'tars-init:|OpenFailed|seconds' /tmp/zm-m1-bf.log
```

Expected:
- `tars-init: /dev/dri/card0 not found` — BF에는 가상 GPU가 없으니 정상이다.
- `error: OpenFailed` — `drm.zig:231`에서 나오는 정상 출력이다. fork된
  `/terminal` 자식만 죽고 PID 1은 그대로 fish를 exec한다.
- 배너까지 걸린 초 — 34초 언저리면 정상.

- [ ] **Step 3: initrd 크기 확인**

Run:
```bash
ls -l kernel/initrd.cpio
```

Expected: 11.8MB 근처. `init`이 정적이 되면서 조금 커지고 `.so` 복사가
빠지면서 조금 작아지므로 순변화는 작을 것이다. **13MB를 넘으면 알릴 것** —
BF는 initrd 크기에 민감한 경로다(53MB에서는 부팅 자체가 안 됐다).

---

## Task 4: 종료 게이트 3/3

**Files:** 없음(확인만)

- [ ] **Step 1: 루트 게이트 전체 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash check.sh 2>&1 | tee /tmp/zm-m1-gate.log
```

Expected 마지막 줄:
```
TARS check PASS: all chains 3/3 consecutive runs succeeded
```

BF 3회 + TF 3회이고 매 회차 `clean()` 후 재빌드라 시간이 오래 걸린다.

- [ ] **Step 2: 6회 전부에서 init 로그 확인**

Run:
```bash
grep -c 'tars-init: starting as PID 1' /tmp/zm-m1-gate.log
grep -c 'tars-init: failed' /tmp/zm-m1-gate.log
```

Expected: 첫 명령은 `6`, 두 번째는 `0`.

두 번째가 0이 아니면 게이트가 PASS했더라도 실패로 본다 — Task 2 Step 7에서
설명한 사각지대다.

---

## Task 5: 문서와 기억 갱신

**Files:**
- Modify: `docs/superpowers/specs/2026-08-13-tars-zig-migration-design.md`
- Modify: `HANDOFF.md`
- Modify: 이 plan 파일(말미에 "실제 실행에서 plan과 달라진 점" 추가)

- [ ] **Step 1: Claude가 문서를 갱신한다**

이 저장소 관례상 design doc·plan·`HANDOFF.md` 작성은 Claude가 한다
(`docs/decisions/feedback_commit_delegation.md`). 사용자는 Task 4까지의
결과만 전달하면 된다.

갱신 내용:
- design doc의 Status를 `ZM-M1 complete`로.
- design doc 리스크 절에서 `environ`과 ioctl 상수 항목을 실제 결과로 교체.
- 이 plan 말미에 "실제 실행에서 plan과 달라진 점"을 추가. **이 절이 다음
  세션이 가장 먼저 읽는 부분이므로 빠짐없이 적는다.**
- `HANDOFF.md`를 ZM-M2 기준으로 다시 씀.

- [ ] **Step 2: Commit**

Claude가 수행한다.

---

## 이번 milestone에서 하지 않는 것

- **Rust 소스 삭제** — ZM-M2. 이 milestone 동안은 되돌아갈 곳으로 남긴다.
- **`kms/` 삭제, `display/check.sh` 삭제, Dockerfile rustup 제거** — ZM-M2.
- **`init`의 최적화 모드 변경** — libc를 안 쓰므로 `ReleaseSafe`가 가능해지지만,
  동작을 바꾸지 않는다는 원칙에 따라 Debug 기본값을 유지한다. 최적화는
  필요해질 때 별도로 다룬다.
- **PID 1 기능 보강(좀비 수거, 셸 종료 처리)** — design doc의 비목표.
