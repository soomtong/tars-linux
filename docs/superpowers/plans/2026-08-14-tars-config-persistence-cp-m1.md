# TARS Config Persistence CP-M1 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 파일 작성과
> 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을 제시하고
> 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는 이 저장소에 적용하지 않는다.

**Goal:** CP-M0가 만든 `/config` 저장소에 **내용**을 담는다. `key=value` 설정
파일을 읽는 파서와, 빈 디스크로 처음 부팅했을 때 기본 설정 파일을 만들어 두는
first-boot seeding을 넣고, **한 스크립트 안에서 QEMU를 두 번 띄워** 1차 부팅이
만든 파일을 2차 부팅이 읽는 것을 확인한다. 여기서 영속성이 처음 증명된다.

**Design doc:** `docs/superpowers/specs/2026-08-14-tars-config-persistence-design.md`
(승인 완료 — 설계를 다시 열지 않는다)

**Tech Stack:** Zig 0.16.0(`std.os.linux`의 `open`/`read`/`write`/`close`,
libc 없음), bash, QEMU, Docker(`tars-devcontainer`, arm64)

---

## 왜 이 순서인가

이 milestone은 **코드 → 배선 → 게이트** 순으로 간다. 코드가 먼저인 이유는
게이트가 볼 마커(로그 문자열)를 코드가 정하기 때문이다.

```
config.zig   parse / load / save            ← Task 1  (파일 I/O + 파서)
  ↓
main.zig     mount 성공 여부 → load or seed  ← Task 2  (배선 + 로그 3종)
  ↓
config/check.sh  부팅 1회 → kill → 부팅 1회  ← Task 3  ★ 이번의 진짜 작업량
  ↓
check.sh     라벨 CP-M0 → CP-M1              ← Task 4
```

**게이트 구조 변경이 이 milestone의 무게중심이다.** BF·TF·CP 세 체인 모두
지금까지 "부팅 1회 + 로그 grep"이었다. 영속성은 원리적으로 한 번의 부팅으로
증명할 수 없다 — 1차 부팅이 만든 것을, **디스크를 다시 굽지 않고**, 2차 부팅이
읽어야 한다. `make_disk.sh`를 두 부팅 사이에 다시 부르면 게이트는 아무것도
검증하지 못하면서 초록불을 낸다(`project_gate_chain_composition`의 반복되는
함정).

---

## 설계에서 이번에 확정한 것 하나

design doc은 인터페이스를 이렇게 적었다.

```zig
pub fn load(path: [:0]const u8) Config;      // 실패해도 기본값을 돌려준다
pub fn save(path: [:0]const u8, c: Config) !void;
```

`load`를 **`?Config`로 바꾼다.** 이유는 seeding 판단 때문이다 — `Config`만
돌려주면 "파일이 없어서 기본값"과 "파일은 있는데 내용이 비어서 기본값"을
호출자가 구분할 수 없고, 그러면 언제 `save`를 불러야 하는지 알 수 없다.

null의 의미를 **오직 하나(ENOENT = 파일이 없다)로 좁힌다.** 열기 실패(권한 등),
읽기 실패, 파싱 실패는 전부 null이 아니라 기본값 `Config`를 돌려준다.
**못 읽은 파일을 우리가 덮어쓰면 사용자가 손으로 쓴 설정이 사라지기
때문이다.** "실패해도 기본값으로 부팅한다"는 design doc의 요구는 그대로
지켜진다.

---

## 사전 준비

모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서 실행한다.
`main` 브랜치, working tree 깨끗한 상태에서 시작한다.

**`docker run`/`docker build`에 `--platform`을 붙이지 않는다**
(`docs/decisions/project_build_host_arch.md`).

---

## Task 1: `init/src/config.zig` — 설정 모듈

**Files:**
- Create: `init/src/config.zig`

`init/build.zig`는 **건드리지 않는다.** `main.zig`가 root source file이고,
같은 모듈 안의 파일은 `@import("config.zig")` 한 줄로 붙는다 — `build.zig`에
모듈을 추가해야 하는 것은 *다른* 모듈(패키지)을 붙일 때뿐이다.

libc가 없으므로 `std.fs`가 아니라 `std.os.linux`의 시스템 콜을 직접 쓴다
(`docs/decisions/project_zig_c_uapi_rule.md`). 힙 할당자도 없으므로 파일
전체를 **스택 버퍼**에 읽는다.

- [ ] **Step 1: `init/src/config.zig` 생성**

```zig
const std = @import("std");
const linux = std.os.linux;

/// main.zig에도 같은 함수가 있다. 세 줄짜리 헬퍼 하나 때문에 공용 모듈을
/// 만드는 것보다 각자 갖고 있는 편이 읽기 쉽다고 판단했다 — 이런 것이
/// 다섯 개쯤 되면 그때 sys.zig로 모은다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// 셸 화이트리스트. 설정 파일에 적을 수 있는 것은 **이름**뿐이고 경로가
/// 아니다 — `shell=/etc/passwd` 같은 입력이 애초에 성립하지 않는다
/// (design doc "5. 설정 하나로 부팅이 막히지 않게 하는 세 장치"의 1번).
/// 이름을 실제 경로로 바꿔 셸을 띄우는 것은 CP-M2의 일이다.
pub const Shell = enum {
    fish,
    bash,
    zsh,
};

/// 설정 전체. 필드의 기본값이 곧 "설정 파일이 없을 때의 TARS"다.
pub const Config = struct {
    shell: Shell = .fish,
};

/// 설정 파일을 통째로 담는 스택 버퍼의 크기. 힙이 없으므로 상한이 필요하고,
/// 키가 수십 개가 되어도 4KB를 넘길 일은 없다. 넘치면 잘라서 파싱하고
/// 경고를 찍는다(조용히 무시하지 않는다).
const MAX_FILE = 4096;

/// 설정 파일을 읽어 파싱한다.
///
/// **optional을 돌려주는 이유는 딱 하나를 구분하기 위해서다.** null은 오직
/// "파일이 없다"(ENOENT)는 뜻이고, 그때만 호출자가 seeding(save)을 한다.
/// 파일은 있는데 못 열었거나 못 읽었으면 null이 아니라 기본값 Config를
/// 돌려준다 — 읽기에 실패한 파일을 우리가 덮어써 버리면 사용자가 손으로 쓴
/// 설정이 사라지기 때문이다.
pub fn load(path: [:0]const u8) ?Config {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |e| {
        if (e == .NOENT) return null;
        std.debug.print("tars-init: failed to open {s} (errno {d})\n", .{
            path, @intFromEnum(e),
        });
        return Config{};
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    var buf: [MAX_FILE]u8 = undefined;
    var len: usize = 0;
    while (len < buf.len) {
        // read(2)는 요청한 만큼을 다 준다는 보장이 없다. 파일이라 사실상 한
        // 번에 오지만, "돌아온 만큼 더한다"가 이 호출의 계약이다.
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            std.debug.print("tars-init: failed to read {s} (errno {d})\n", .{
                path, @intFromEnum(e),
            });
            return Config{};
        }
        if (n == 0) break; // EOF
        len += n;
    }
    if (len == buf.len) {
        std.debug.print("tars-init: {s} is at least {d} bytes, parsing that much only\n", .{
            path, buf.len,
        });
    }

    return parse(buf[0..len]);
}

/// 파일 내용을 Config로 바꾼다. 시스템 콜이 하나도 없는 순수 함수라서, 이
/// 파일에서 유일하게 게스트를 띄우지 않고도 검증할 수 있는 부분이다.
///
/// 규칙(design doc "3. 설정 파일"): `#`으로 시작하면 주석, 빈 줄은 무시,
/// 나머지는 **첫 번째** `=`에서 키와 값으로 나누고 양쪽 공백을 뗀다.
/// 모르는 키와 모르는 값은 로그만 남기고 넘어간다 — 설정 파일은 사용자가
/// 손으로 고치는 물건이라 깨진 입력이 예외가 아니라 규칙이다.
fn parse(text: []const u8) Config {
    var c = Config{};

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        // \r까지 떼는 것은 사용자가 호스트에서 편집한 파일을 넣을 수도 있기
        // 때문이다. CRLF 한 글자 때문에 값이 "fish\r"가 되면 원인을 찾기 어렵다.
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse {
            std.debug.print("tars-init: config line without '=' ignored: {s}\n", .{line});
            continue;
        };
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t");

        if (std.mem.eql(u8, key, "shell")) {
            // stringToEnum이 곧 화이트리스트다. enum에 없는 이름은 통과할 수
            // 없으므로 검사 목록을 따로 유지할 필요가 없다.
            c.shell = std.meta.stringToEnum(Shell, value) orelse {
                std.debug.print("tars-init: unknown shell '{s}', falling back to {s}\n", .{
                    value, @tagName(c.shell),
                });
                continue;
            };
        } else {
            std.debug.print("tars-init: unknown config key '{s}'\n", .{key});
        }
    }

    return c;
}

pub const SaveError = error{
    FormatFailed,
    OpenFailed,
    WriteFailed,
};

/// 설정을 파일로 쓴다. 이번 범위에서 이 함수의 유일한 호출자는 first-boot
/// seeding이다 — 빈 디스크로 처음 부팅하면 init이 기본 설정을 주석과 함께
/// 만들어 둔다. 그래야 사용자가 빈 디렉터리 앞에서 무엇을 쓸 수 있는지 알게
/// 되고, "쓰기" 코드가 아무도 부르지 않는 죽은 코드가 되지 않는다.
///
/// 파일 내용을 상수 문자열로 박지 않고 Config에서 만들어 내는 이유는 진실의
/// 출처를 하나로 두기 위해서다. Config의 기본값을 바꾸면 씨앗 파일도 따라
/// 바뀐다.
pub fn save(path: [:0]const u8, c: Config) SaveError!void {
    var buf: [MAX_FILE]u8 = undefined;
    const text = std.fmt.bufPrint(&buf,
        \\# TARS configuration. Edit and reboot to apply.
        \\# shell: fish | bash | zsh
        \\shell={s}
        \\
    , .{@tagName(c.shell)}) catch return error.FormatFailed;

    // O_EXCL을 쓰지 않는다. "파일이 있는가"는 load가 이미 답했고, save의
    // 계약은 "이 내용으로 만든다"이다. O_TRUNC는 나중에 이 함수가 갱신에도
    // 쓰일 때 남은 꼬리가 붙지 않게 한다.
    const rc = linux.open(path.ptr, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: failed to create {s} (errno {d})\n", .{
            path, @intFromEnum(e),
        });
        return error.OpenFailed;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    // /config는 MS_SYNCHRONOUS로 마운트돼 있다. 그래서 이 write가 돌아온
    // 시점에 데이터도 디렉터리 엔트리도 이미 디스크에 있다 — fsync를 따로
    // 부르지 않는 것이 실수가 아니라 그 마운트 플래그의 값어치다.
    var written: usize = 0;
    while (written < text.len) {
        const n = linux.write(fd, text.ptr + written, text.len - written);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            std.debug.print("tars-init: failed to write {s} (errno {d})\n", .{
                path, @intFromEnum(e),
            });
            return error.WriteFailed;
        }
        if (n == 0) return error.WriteFailed;
        written += n;
    }
}
```

- [ ] **Step 2: 컴파일되는지만 확인**

아직 `main.zig`가 이 파일을 import하지 않으므로 **빌드에 포함되지 않는다.**
Zig는 import되지 않은 파일을 컴파일하지 않는다. 그래서 이 Step에서는 파일이
제대로 만들어졌는지만 본다.

Run:
```bash
wc -l init/src/config.zig && head -3 init/src/config.zig
```

Expected: 180줄 안팎, 첫 줄이 `const std = @import("std");`.

실제 컴파일은 Task 2 Step 5에서 `main.zig`가 import한 뒤에 일어난다. **여기서
오타가 있어도 지금은 안 잡힌다** — Task 2에서 한꺼번에 잡힌다.

- [ ] **Step 3: Commit**

Claude가 수행한다.

---

## Task 2: `main.zig` 배선

**Files:**
- Modify: `init/src/main.zig` (`mountFs` 반환형 + 호출 5곳 + `loadConfig` 추가 + `main`)

여기서 정하는 **로그 세 줄이 곧 게이트의 마커**다.

| 상황 | 로그 |
|---|---|
| 디스크가 안 붙었다(BF·TF 체인) | `tars-init: no config storage, using defaults` |
| 붙었고 파일이 없었다(1차 부팅) | `tars-init: created /config/tars.conf` |
| 붙었고 파일이 있었다(2차 부팅) | `tars-init: loaded /config/tars.conf` |

그리고 **어느 경로든 마지막에 결과 한 줄**을 찍는다:
`tars-init: config shell=fish`. "어디서 왔는가"와 "결과가 무엇인가"를 나누어
찍으면, 나중에 값이 이상할 때 파싱이 틀린 건지 파일을 안 읽은 건지가 로그만
보고 갈린다.

- [ ] **Step 1: import 추가**

`init/src/main.zig:1-2`:

```zig
const std = @import("std");
const linux = std.os.linux;
```

를

```zig
const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");
```

로 바꾼다.

- [ ] **Step 2: `mountFs`가 성공 여부를 돌려주게 한다**

`init/src/main.zig:12-26`. **로그 문자열은 한 글자도 바꾸지 않는다** —
`tars-init: mounted {s} at {s}` 네 줄은 `boot/check.sh`·`terminal/check.sh`·
`config/check.sh`가 grep하는 마커다(`HANDOFF.md`의 "마커 문자열 중복 주의").

바꾸기 전:

```zig
fn mountFs(
    source: [:0]const u8,
    target: [:0]const u8,
    fstype: [:0]const u8,
    flags: u32,
) void {
    const rc = linux.mount(source.ptr, target.ptr, fstype.ptr, flags, 0);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: failed to mount {s} at {s} (errno {d})\n", .{
            fstype, target, @intFromEnum(e),
        });
    } else {
        std.debug.print("tars-init: mounted {s} at {s}\n", .{ fstype, target });
    }
}
```

바꾼 뒤:

```zig
/// 성공하면 true. /proc·/sys·/dev는 실패해도 할 수 있는 일이 없어서 결과를
/// 버리지만, /config는 다르다 — 저장소가 안 붙었는데 설정을 읽으려 들면
/// initramfs(tmpfs) 위의 빈 디렉터리에 파일을 만들게 되고, 그건 재부팅하면
/// 사라지는 가짜 영속성이다.
fn mountFs(
    source: [:0]const u8,
    target: [:0]const u8,
    fstype: [:0]const u8,
    flags: u32,
) bool {
    const rc = linux.mount(source.ptr, target.ptr, fstype.ptr, flags, 0);
    if (failed(rc)) |e| {
        std.debug.print("tars-init: failed to mount {s} at {s} (errno {d})\n", .{
            fstype, target, @intFromEnum(e),
        });
        return false;
    }
    std.debug.print("tars-init: mounted {s} at {s}\n", .{ fstype, target });
    return true;
}
```

- [ ] **Step 3: 기존 호출 두 자리를 `_ =`로 받는다**

`mountDevpts` 안(41번째 줄):

```zig
    _ = mountFs("devpts", "/dev/pts", "devpts", 0);
```

`mountConfig`(56-58번째 줄) — 여기는 버리지 않고 그대로 넘긴다:

```zig
fn mountConfig() bool {
    return mountFs("/dev/vda", "/config", "ext2", linux.MS.SYNCHRONOUS);
}
```

(`mountConfig` 위의 주석 블록은 그대로 둔다.)

- [ ] **Step 4: `loadConfig`를 추가한다**

`mountConfig` 함수 바로 다음에 넣는다.

```zig
/// 설정 파일의 자리. 저장소가 붙은 뒤에만 의미가 있다.
const CONFIG_PATH: [:0]const u8 = "/config/tars.conf";

/// 설정을 결정한다. 세 경로 전부 **부팅을 계속한다** — 설정 하나 때문에
/// 부팅이 막히면 그것이 이 설계의 실패다(design doc의 세 장치 중 3번).
///
///   저장소 없음  → 내장 기본값. BF·TF 체인이 매번 지나는 정상 경로다.
///   파일 없음    → first-boot seeding. 기본값을 주석과 함께 써 둔다.
///   파일 있음    → 읽어서 쓴다.
fn loadConfig(storage_mounted: bool) config.Config {
    if (!storage_mounted) {
        std.debug.print("tars-init: no config storage, using defaults\n", .{});
        return .{};
    }

    if (config.load(CONFIG_PATH)) |c| {
        std.debug.print("tars-init: loaded {s}\n", .{CONFIG_PATH});
        return c;
    }

    // load가 null을 준다는 것은 파일이 없다는 뜻뿐이다 = 이 디스크로 처음
    // 부팅했다. 씨앗을 심는다.
    const defaults = config.Config{};
    config.save(CONFIG_PATH, defaults) catch {
        std.debug.print("tars-init: could not seed {s}, using defaults\n", .{CONFIG_PATH});
        return defaults;
    };
    std.debug.print("tars-init: created {s}\n", .{CONFIG_PATH});
    return defaults;
}
```

- [ ] **Step 5: `main`에서 호출한다**

`init/src/main.zig`의 `main` 안, 마운트 묶음을 이렇게 바꾼다.

바꾸기 전:

```zig
    mountFs("proc", "/proc", "proc", 0);
    mountFs("sysfs", "/sys", "sysfs", 0);
    mountFs("devtmpfs", "/dev", "devtmpfs", 0);
    mountDevpts();
    mountConfig();

    logDrmDevicePresence();
```

바꾼 뒤:

```zig
    _ = mountFs("proc", "/proc", "proc", 0);
    _ = mountFs("sysfs", "/sys", "sysfs", 0);
    _ = mountFs("devtmpfs", "/dev", "devtmpfs", 0);
    mountDevpts();

    const storage_mounted = mountConfig();
    const cfg = loadConfig(storage_mounted);
    std.debug.print("tars-init: config shell={s}\n", .{@tagName(cfg.shell)});

    logDrmDevicePresence();
```

**`cfg`를 아직 아무도 쓰지 않는다.** `Kind.path()`가 이 값을 보는 것은
CP-M2다. 지금은 로그 한 줄이 유일한 사용처이고, 그것으로 충분하다 — 게이트가
2차 부팅에서 "파일을 열었다"를 넘어 **"내용이 실제로 파싱됐다"**까지 보게
해주는 줄이기 때문이다.

- [ ] **Step 6: 빌드**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c 'cd init && zig build'
```

Expected: 출력 없이 종료 코드 0.

**Task 1의 `config.zig`가 처음으로 컴파일되는 순간이다.** 에러가 나면 대부분
여기서 난다. 나오면 전문을 붙여서 알릴 것 — 특히 `linux.open`의 `O` 구조체
필드 이름(`ACCMODE`/`CREAT`/`TRUNC`)과 `linux.read`/`linux.write`의 포인터
타입이 후보다.

- [ ] **Step 7: 여전히 정적 바이너리인지 확인**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c 'readelf -d init/zig-out/bin/init | grep -c NEEDED; ls -l init/zig-out/bin/init'
```

Expected: `0`, 그리고 12MB 안팎.

`0`이어야 하는 이유는 CP-M0와 같다 — `make_initrd.sh`가 `init`에 대해서는
`copy_lib_deps`를 부르지 않으므로, 동적 의존이 하나라도 생기면 부팅이 로더
에러로 죽는다. `std.fs`가 아니라 `std.os.linux`를 쓴 것이 여기서 값을 한다.

- [ ] **Step 8: Commit**

Claude가 수행한다.

---

## Task 3: 게이트를 2회 부팅으로 바꾼다

**Files:**
- Modify: `config/check.sh` (전면 재작성)

**이 Task가 CP-M1의 실제 작업량이다.** 지금 스크립트는 "빌드 → 디스크 굽기 →
부팅 1회 → grep"인데, "빌드 → 디스크 굽기 → 부팅 → **kill** → **같은
이미지로** 부팅 → grep"이 되어야 한다.

세 가지를 특히 지킨다.

1. **`make_disk.sh`는 딱 한 번, 첫 부팅 앞에서만 부른다.** 두 부팅 사이에서
   다시 부르면 2차 부팅도 빈 디스크를 보게 되고, 게이트는 통과하면서
   아무것도 증명하지 않는다.
2. **1차 QEMU가 완전히 끝난 것을 확인하고 2차를 띄운다.** 두 QEMU가 같은
   이미지 파일을 동시에 열면 파일시스템이 깨진다. `kill` 다음의 `wait`이 그
   보장이다.
3. **부정 검사를 넣는다.** 1차 로그에 `loaded`가 **없어야** 하고, 2차 로그에
   `created`가 **없어야** 한다. 특히 2차의 `created` 부재가 곧 "1차가 쓴
   파일이 살아남았다"는 증거다 — 긍정 검사만으로는 매번 새로 만들어지는
   상황을 잡지 못한다.

- [ ] **Step 1: `config/check.sh`를 아래 내용으로 교체**

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

REPO_ROOT="$(cd .. && pwd)"

# 빌드 순서는 TF 체인과 같다(kernel → init → terminal → initrd).
if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 디스크는 매 회차 새로 굽는다. 남은 이미지를 재사용하면 "빈 디스크로 첫
# 부팅"이라는 전제가 무너지고, 아래 1차 부팅이 검증할 seeding 경로가 두 번
# 다시 실행되지 않은 채 게이트가 자기를 속이게 된다.
#
# 반대로 **두 부팅 사이에서는 절대 다시 부르지 않는다.** 그게 이 milestone의
# 검증 그 자체다 — 1차가 쓴 것을 2차가 읽어야 한다.
if ! ./make_disk.sh; then
  echo "FAIL: disk image build failed"
  exit 1
fi

LOG1="$(mktemp)"
LOG2="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# 부팅 한 번. $1 = 시리얼 로그 파일, $2 = 기다릴 마커.
#
# QEMU 인자는 CP-M0와 같다(TF 체인 + -drive). 두 부팅이 **같은 이미지 파일**을
# 가리키는 것이 핵심이고, 그래서 이 함수는 이미지 경로를 인자로 받지 않는다.
boot_once() {
  local log="$1"
  local marker="$2"

  qemu-system-x86_64 \
    -kernel ../kernel/build/arch/x86/boot/bzImage \
    -initrd ../kernel/initrd.cpio \
    -append "console=ttyS0" \
    -vga none \
    -device virtio-gpu-pci \
    -drive file="${REPO_ROOT}/out/config.img",if=virtio,format=raw \
    -display none \
    -serial file:"$log" \
    -no-reboot &
  QEMU_PID=$!

  # 고정 sleep 대신 로그 폴링. 마커가 나오면 즉시 끝낸다.
  local found=0
  for _ in $(seq 1 120); do
    if grep -q "$marker" "$log"; then
      found=1
      break
    fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
      break
    fi
    sleep 1
  done

  # 마커를 봤든 못 봤든 여기서 QEMU를 확실히 끝낸다. wait까지 하는 이유는
  # 다음 부팅이 **같은 디스크 이미지**를 열기 때문이다 — 두 QEMU가 같은
  # 이미지를 동시에 쓰면 파일시스템이 깨지고, 그 실패는 이 milestone이
  # 검증하려는 것과 구분이 안 되는 모양으로 나타난다.
  kill "$QEMU_PID" 2>/dev/null
  wait "$QEMU_PID" 2>/dev/null
  QEMU_PID=""

  [ "$found" = "1" ]
}

# 실패했을 때 "어디까지 갔는가"를 보여준다. 마커 하나하나가 부팅의 단계다.
report_failure() {
  local log="$1"
  local msg="$2"
  echo "FAIL: ${msg}"
  echo "--- markers ---"
  local marker
  for marker in \
    "\[vda\]" \
    "tars-init: mounted ext2 at /config" \
    "tars-init: failed to mount ext2 at /config" \
    "tars-init: created /config/tars.conf" \
    "tars-init: loaded /config/tars.conf" \
    "tars-init: config shell="; do
    if grep -q "$marker" "$log"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- tail ---"
  tail -n 60 "$log"
  exit 1
}

# ---------------------------------------------------------------- 1차 부팅
# 빈 디스크. init이 /config/tars.conf를 만들어야 한다.
echo "=== boot 1/2: empty disk, init should seed the config file ==="
if ! boot_once "$LOG1" "tars-init: created /config/tars.conf"; then
  report_failure "$LOG1" "first boot did not create /config/tars.conf"
fi

if ! grep -q "\[vda\]" "$LOG1"; then
  report_failure "$LOG1" "kernel never reported a [vda] block device on the first boot"
fi

# 빈 디스크였는데 loaded가 나왔다면 make_disk.sh가 안 돌았거나 이전 회차의
# 이미지가 남아 있는 것이다. 그 상태로는 seeding 경로가 검증되지 않는다.
if grep -q "tars-init: loaded /config/tars.conf" "$LOG1"; then
  report_failure "$LOG1" "first boot loaded an existing config; the disk was not empty"
fi

if grep -q "Attempted to kill init" "$LOG1"; then
  report_failure "$LOG1" "kernel panicked because PID 1 exited on the first boot"
fi
echo "boot 1: init seeded /config/tars.conf on a fresh disk"

# ---------------------------------------------------------------- 2차 부팅
# 같은 이미지를 그대로 다시 물린다. make_disk.sh를 부르지 않는다.
#
# 1차 부팅은 언마운트 없이 죽었으므로 ext2 슈퍼블록이 "not clean" 상태다.
# 리눅스 ext2는 그래도 마운트해 주고 경고만 찍는다(EXT2-fs ... mounting
# unchecked fs). 그 경고가 보이는 것이 정상이다.
echo "=== boot 2/2: same image, init should load what boot 1 wrote ==="
if ! boot_once "$LOG2" "tars-init: loaded /config/tars.conf"; then
  report_failure "$LOG2" "second boot did not load /config/tars.conf"
fi

# **이 검사가 이 게이트의 핵심이다.** 2차에서 또 created가 나왔다면 1차가 쓴
# 파일이 살아남지 못한 것이다(동기 마운트가 안 먹었거나, 이미지를 다시
# 구웠거나, 두 부팅이 서로 다른 이미지를 봤거나).
if grep -q "tars-init: created /config/tars.conf" "$LOG2"; then
  report_failure "$LOG2" "second boot re-created the config file; nothing persisted"
fi

# 파일을 열었다는 것과 내용이 파싱됐다는 것은 다르다. 기본 씨앗은 fish다.
if ! grep -q "tars-init: config shell=fish" "$LOG2"; then
  report_failure "$LOG2" "second boot did not parse shell=fish out of the config file"
fi

if grep -q "Attempted to kill init" "$LOG2"; then
  report_failure "$LOG2" "kernel panicked because PID 1 exited on the second boot"
fi
echo "boot 2: init loaded the config written by boot 1 (shell=fish)"

# 정보성. ext2가 "not clean"이라고 말하는 것은 예상된 결과이므로 실패로 보지
# 않되, 보이면 남긴다.
if grep -q "mounting unchecked fs" "$LOG2"; then
  echo "note: ext2 reported an unclean superblock on boot 2 (expected: boot 1 was killed)"
fi

# 성공해도 시리얼 로그의 init 줄은 남긴다. TF 체인이 "--- init log ---"를
# 찍는 것과 같은 이유다 — 루트 게이트가 만드는 통합 로그에서 이 체인이 무엇을
# 봤는지 나중에 확인할 수 있어야 한다(CP-M0에서 이걸 빼먹어 부팅 3회가 통합
# 로그에 없었다).
echo "--- init log (boot 1) ---"
grep 'tars-init:' "$LOG1" || true
echo "--- init log (boot 2) ---"
grep 'tars-init:' "$LOG2" || true

echo "PASS"
exit 0
```

- [ ] **Step 2: 실행 권한이 남아 있는지 확인**

Run:
```bash
ls -l config/check.sh config/make_disk.sh
```

Expected: 둘 다 `-rwxr-xr-x`. 편집기가 새 파일로 만들었다면 실행 비트가
사라졌을 수 있다 — 그러면 `chmod +x config/check.sh`.

- [ ] **Step 3: CP 체인 단독 실행**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash config/check.sh 2>&1 | tee /tmp/cp-m1.log
```

Expected: 마지막에

```
boot 1: init seeded /config/tars.conf on a fresh disk
boot 2: init loaded the config written by boot 1 (shell=fish)
--- init log (boot 1) ---
...
--- init log (boot 2) ---
...
PASS
```

**여기가 이 milestone에서 가장 깨지기 쉬운 지점이다.** 실패하면
`--- markers ---` 블록을 통째로 붙여서 알릴 것. 원인 갈래는 이렇다.

- **1차에서 `created`가 안 나오고 `mounted ext2 at /config`도 없다** →
  CP-M0가 깨진 것이다. 커널이나 디스크 쪽이지 이번 코드가 아니다.
- **`mounted`는 있는데 `created`가 없고 `failed to create ... (errno 13)`** →
  EACCES. `/config`가 읽기 전용으로 붙었다는 뜻이다.
- **`failed to create ... (errno 30)`** → EROFS. 같은 원인의 다른 얼굴.
- **`failed to write ... (errno 28)`** → ENOSPC. 16MB짜리 디스크가 찼을 리는
  없으니 이미지가 sparse인 채 커널에는 다른 크기로 보이는 상황을 의심한다.
- **2차에서 `created`가 또 나왔다** → 영속성이 실제로 안 된 것이다. 확인 순서:
  (1) `make_disk.sh`가 두 번 불리지 않았는지, (2) 두 QEMU가 같은
  `out/config.img`를 가리키는지, (3) `mountConfig`의 `MS_SYNCHRONOUS`가
  그대로인지.
- **2차에서 `loaded`는 나왔는데 `config shell=fish`가 없다** → 파일은
  읽었는데 파서가 값을 못 꺼낸 것이다. `--- init log (boot 2) ---`에
  `unknown config key` 또는 `unknown shell`이 함께 찍혀 있을 것이고, 그
  문자열이 곧 원인이다.

- [ ] **Step 4: Commit**

Claude가 수행한다.

---

## Task 4: 루트 게이트의 라벨

**Files:**
- Modify: `check.sh:40-45`

- [ ] **Step 1: 주석과 라벨 갱신**

바꾸기 전:

```bash
# CP 체인은 영속 저장소를 본다. 세 체인 중 유일하게 -drive로 디스크를 물고
# 부팅하며, 나머지 둘은 디스크 없이 부팅해도 통과해야 한다는 것 자체가
# 검사 대상이다(설정 저장소가 없다고 부팅이 막히면 안 된다).
run_chain "BF-M4" ./boot/check.sh
run_chain "TF-M4" ./terminal/check.sh
run_chain "CP-M0" ./config/check.sh
```

바꾼 뒤:

```bash
# CP 체인은 영속 저장소를 본다. 세 체인 중 유일하게 -drive로 디스크를 물고
# 부팅하며, 나머지 둘은 디스크 없이 부팅해도 통과해야 한다는 것 자체가
# 검사 대상이다(설정 저장소가 없다고 부팅이 막히면 안 된다).
#
# CP-M1부터 이 체인만 회차당 QEMU를 **두 번** 띄운다. 영속성은 한 번의
# 부팅으로 증명할 수 없기 때문이다 — 1차가 쓴 파일을 2차가 읽는다. 그래서
# 루트 게이트 한 번의 총 부팅 횟수는 9회가 아니라 12회다.
run_chain "BF-M4" ./boot/check.sh
run_chain "TF-M4" ./terminal/check.sh
run_chain "CP-M1" ./config/check.sh
```

`clean()`은 손대지 않는다 — 이미 `out`을 통째로 지우므로 `out/config.img`가
매 회차 사라지고, `config/check.sh`가 다시 굽는다. **이것이 "1차 부팅은 항상
빈 디스크"를 보장하는 장치다.**

- [ ] **Step 2: Commit**

Claude가 수행한다.

---

## Task 5: 나머지 두 체인과 전체 게이트

**Files:** 없음(확인만)

`init` 바이너리가 바뀌었으므로 세 체인을 다 돌린다. initrd를 읽는 경로가
BF(limine이 ISO에서 BIOS INT13h로)와 나머지(QEMU `-initrd`)로 서로 다르다.

- [ ] **Step 1: BF 체인 — 디스크가 없어도 통과해야 한다**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash boot/check.sh 2>&1 | tee /tmp/cp-m1-bf.log
```

Expected: `PASS`.

로그에는 CP-M0에서 생긴 실패 줄에 더해 **새 줄 두 개**가 나타나야 한다.

```
tars-init: failed to mount ext2 at /config (errno 2)
tars-init: no config storage, using defaults
tars-init: config shell=fish
```

**`created`도 `loaded`도 나오면 안 된다.** 나온다면 `loadConfig`가
`storage_mounted`를 안 보고 있다는 뜻이고, 그러면 initramfs(tmpfs) 위에 설정
파일을 만들고 있는 것이다 — 재부팅하면 사라지는 가짜 영속성이라 더 나쁘다.

확인:
```bash
grep -c 'tars-init: created /config/tars.conf' /tmp/cp-m1-bf.log
grep -c 'tars-init: no config storage, using defaults' /tmp/cp-m1-bf.log
```

Expected: `0`, `3`.

- [ ] **Step 2: TF 체인**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/check.sh 2>&1 | tee /tmp/cp-m1-tf.log
```

Expected: `PASS`. TF도 `-drive`가 없으므로 BF와 같은 세 줄이 나온다.

- [ ] **Step 3: 루트 게이트 전체**

Run:
```bash
time docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash check.sh 2>&1 | tee /tmp/cp-m1-gate.log
```

Expected 마지막 줄:

```
TARS check PASS: all chains 3/3 consecutive runs succeeded
```

CP-M0에서 **13분 08초**였다. 늘어나는 것은 CP 회차마다 부팅 1회씩, 총 3회분의
부팅 시간뿐이고 **빌드는 그대로다**(회차당 clean 재빌드 9회는 변함없다).
ZM-M3 이후 TF 계열 부팅 1회가 수 초 수준이므로 **13분 30초 안팎**을 예상한다.
**실제 시간을 재서 알릴 것** — 예상보다 크게 늘었다면 2차 부팅이 마커를 못
찾고 120초 타임아웃을 다 쓰고 있다는 신호일 수 있다(그 경우 FAIL이 나야
하지만, 폴링 상한이 어디에 걸리는지 아는 것이 다음 milestone에서 중요하다).

- [ ] **Step 4: 통합 로그에서 숫자 확인**

Run:
```bash
grep -c 'tars-init: starting as PID 1' /tmp/cp-m1-gate.log
grep -c 'tars-init: mounted ext2 at /config' /tmp/cp-m1-gate.log
grep -c 'tars-init: failed to mount ext2 at /config' /tmp/cp-m1-gate.log
grep -c 'tars-init: no config storage, using defaults' /tmp/cp-m1-gate.log
grep -c 'tars-init: created /config/tars.conf' /tmp/cp-m1-gate.log
grep -c 'tars-init: loaded /config/tars.conf' /tmp/cp-m1-gate.log
grep -c 'tars-init: config shell=fish' /tmp/cp-m1-gate.log
grep -c 'Attempted to kill init' /tmp/cp-m1-gate.log
```

Expected: `12`, `6`, `6`, `6`, `3`, `3`, `12`, `0`.

각 숫자가 무엇을 말하는지가 이 Step의 내용이다.

- **12** — 부팅 12회. BF 3 + TF 3 + CP 3회차×2 = 12. CP-M0의 9에서 3이 늘었다.
- **6** — 마운트 성공은 CP 3회차의 두 부팅씩 = 6.
- **6** — BF·TF 6회는 디스크가 없으므로 실패가 정상이다. **0이면 오히려
  이상하다**(마운트 시도 자체가 사라졌다는 뜻).
- **6** — 위 실패 6회와 정확히 짝을 이뤄야 한다. 짝이 안 맞으면
  `loadConfig`가 마운트 실패를 다르게 해석하고 있다.
- **3 / 3** — seeding은 회차마다 1차 부팅에서만, load는 2차 부팅에서만.
  **이 둘이 각각 3이라는 것이 영속성의 증명이다.** `created`가 6이면 2차
  부팅도 빈 디스크를 본 것이고, `loaded`가 6이면 1차 부팅이 빈 디스크가
  아니었던 것이다.
- **12** — 결과 줄은 어느 경로로 갔든 매 부팅 한 번.
- **0** — 하나라도 있으면 게이트가 PASS했더라도 실패로 본다.

---

## Task 6: 문서 갱신

**Files:**
- Modify: `HANDOFF.md`
- Modify: 이 plan 파일(말미에 "실제 실행에서 plan과 달라진 점" 추가)

- [ ] **Step 1: Claude가 문서를 갱신한다**

사용자는 Task 5까지의 결과만 전달하면 된다.

갱신 내용:
- 이 plan 말미에 "실제 실행에서 plan과 달라진 점". **다음 세션이 가장 먼저
  읽는 부분이므로 빠짐없이 적는다** — Zig 컴파일 에러가 났다면 무엇이었는지,
  2차 부팅의 ext2 경고 문구가 실제로 무엇이었는지, 게이트 소요 시간, 그리고
  Task 5 Step 4의 여덟 숫자.
- `HANDOFF.md`를 CP-M2 기준으로 다시 쓴다.

`docs/decisions/`의 새 기억 파일은 **CP-M2까지 끝난 뒤** 서브프로젝트 단위로
쓴다(design doc의 결정들이 셋 다 실행돼 봐야 "결정"으로 굳는다).

- [ ] **Step 2: Commit**

Claude가 수행한다.

---

## 이번 milestone에서 하지 않는 것

- **`Kind.path()`가 설정을 보는 것.** 셸은 여전히 `/usr/bin/fish` 상수다.
  `cfg.shell`은 읽히고 로그에 찍히지만 아직 아무 동작도 바꾸지 않는다 —
  CP-M2가 그 한 줄을 잇는다.
- **bash/zsh를 initrd에 넣는 것.** CP-M2. `Shell` enum에 이름만 있고 대응하는
  바이너리는 아직 게스트에 없다. **이것이 M2의 순서를 정한다** — 설정에
  `shell=zsh`를 써도 지금은 아무 일도 안 일어나므로 위험하지 않지만, M2에서
  경로를 잇는 순간 바이너리가 먼저 있어야 한다.
- **게스트에서 sendkey로 설정 파일을 고치는 것.** CP-M2. 이번 2차 부팅이 읽는
  것은 1차 부팅이 **스스로 쓴** 씨앗 파일이다.
- **설정 갱신 API.** `save`의 호출자는 seeding 하나뿐이다. "게스트에서 설정을
  바꾸는 명령"은 design doc의 비목표.
- **`parse`에 대한 단위 테스트.** `parse`는 시스템 콜이 없는 순수 함수라
  `zig build test`로 검증할 수 있는 유일한 부분이지만, 이 저장소에는 아직
  테스트 러너가 붙은 적이 없고 게이트가 그 자리를 대신해 왔다. 테스트를
  들이는 것은 그 자체로 하나의 결정이므로 여기서 곁다리로 하지 않는다 —
  파서가 복잡해지는 시점(키가 여러 개가 되는 CP-M2 이후)에 따로 꺼낸다.
- **`TERM` 전달.** `HANDOFF.md`의 숙제 그대로, CP-M2에서 zsh/bash가 실제로
  깨지는 것을 보고 나서 넣는다.
