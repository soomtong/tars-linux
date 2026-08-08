# TARS Terminal Foundation — TF-M1 Framebuffer Text Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **단, 이 저장소는 pairing 방식 고정(`CLAUDE.md`, HANDOFF.md 참고):** 파일
> 작성과 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을
> 제시하고 결과를 해석한다. 위 SUB-SKILL 문구는 다른 저장소용 기본값이며 이
> 저장소에는 적용하지 않는다.

**Goal:** TF-M1을 완료한다 — Terminal Foundation 앱(Zig)이 `/dev/dri/card0`를
직접 열어(raw DRM ioctl, `kms/src/main.rs`를 Zig로 포팅) 프레임버퍼를 얻고,
`8x4x4-fonts` + `stb_truetype`으로 만든 glyph cache에서 고정 문자열
`"TARS 하이"`(ASCII + 한글 음절)를 blit해 화면에 그린다. `libghostty-vt`는
아직 쓰지 않는다(ANSI 파싱은 PTY가 들어오는 TF-M2부터). QEMU screendump에서
배경색 픽셀 검사 + 글리프 영역 non-background 픽셀 검사로 자동 검증한다.

**Architecture:** `terminal/src/`에 세 개의 작은 모듈을 둔다 —
`drm.zig`(raw DRM ioctl로 프레임버퍼를 얻고 픽셀을 쓰는 계층, `kms/src/main.rs`의
1:1 포팅), `font.zig`(`stb_truetype` FFI로 코드포인트별 비트맵을 한 번
래스터라이징해 두는 glyph cache), `main.zig`(둘을 엮어 배경을 채우고 문자열을
blit). Terminal Foundation 앱이 이제부터 `/dev/dri/card0`를 소유하므로,
`init`이 fork/exec하던 대상을 `/kms`에서 `/terminal`로 바꾸고
`kernel/make_initrd.sh`도 그에 맞춘다(`kms` crate 자체는 Display Foundation
산출물로 저장소에 남지만 boot chain에서는 빠진다).

**Tech Stack:** Zig 0.16.0(TF-M0에서 devcontainer에 설치됨),
`stb_truetype.h`(TF-M0에서 벤더링됨, `terminal/vendor/stb_truetype.h`),
`Hanme_8x4x4.ttf`(TF-M0에서 벤더링됨, `terminal/vendor/fonts/`), libc(`sys/ioctl.h`,
`sys/mman.h` — Zig `@cImport`로 직접 사용, DRM 구조체/ioctl 번호는 손으로
정의해 이해를 유지), 기존 devcontainer(`tars-devcontainer` 이미지, 변경 없음)

---

## 사전 준비

이 plan의 모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서
실행한다. 빌드+QEMU 검증 스크립트(`terminal/check.sh`)는 **devcontainer
안에서** 통째로 실행한다(`display/check.sh`와 동일 패턴 — 스크립트 내부에서
`docker run`을 또 부르지 않고, `docker run ... bash terminal/check.sh`
한 번으로 빌드부터 QEMU screendump까지 전부 컨테이너 안에서 돈다).
개별 `zig build-exe` 컴파일/실행 스텝(Task 1, Task 3)은 지금까지와 같이
`docker run --rm ... tars-devcontainer <command>` 형태로 실행한다.

**Design doc과의 관계:**
[2026-08-08-tars-terminal-foundation-design.md](../specs/2026-08-08-tars-terminal-foundation-design.md)의
TF-M1 절("글리프 캐시 구축 + 고정 문자열을 KMS 프레임버퍼에 렌더링")을 구현한다.
이번 브레인스토밍에서 구체화한 결정:
- KMS 접근: `kms` crate를 링크하지 않고 Zig로 raw ioctl 재구현(설계 결정 1,
  "단일 프로세스가 디스플레이 독점"과 일치).
- 고정 문자열: ASCII("TARS ") + 한글 음절 2자("하이") — `8x4x4-fonts`의
  한글 지원까지 이번 milestone에서 검증한다. `Hanme_8x4x4.ttf`는 완성형 한글
  음절 11,172자를 표준 유니코드 코드포인트로 직접 매핑하고 있어(cmap 확인
  완료), 우리 앱이 초성/중성/종성을 조합할 필요는 없다 — ASCII와 동일하게
  코드포인트 하나당 `stbtt_GetCodepointBitmap` 한 번이면 된다.
- glyph cache 범위: 테스트 문자열에 등장하는 코드포인트만.
- 검증: screendump에서 (a) 배경색 단일 픽셀 검사, (b) 글리프가 그려질 좌표
  영역을 crop해 unique color 개수(배경색 + 글자색 이상)로 "뭔가 그려졌다"만
  자동 확인. 정확한 글자 모양까지는 육안으로 확인한다.

**색상 규칙(이 plan 전체에서 고정):** 프레임버퍼는 32bpp/depth24 XRGB
포맷이다(DF-M0에서 이미 검증됨 — `0x00FF0000`을 그대로 픽셀에 쓰면 화면에
빨간색으로 나타났다). 즉 `u32` 리터럴의 16진수 자릿수 그룹이 그대로
R,G,B 순서다. 배경은 `0x00102030`(짙은 남색, hex `#102030`), 글자색은
`0x00FFFFFF`(흰색)로 고정한다.

---

### Task 1: Zig 프로젝트 스캐폴드

**Files:**
- Create: `terminal/src/main.zig`
- Modify: `.gitignore`

- [ ] **Step 1: `.gitignore`에 Zig 빌드 산출물 경로 추가**

`.gitignore` 끝에 추가:

```gitignore

terminal/zig-out/
terminal/.zig-cache/
```

`zig build-exe`는 기본적으로 `.zig-cache/`에 증분 컴파일 캐시를 만든다
(Rust의 `target/`와 같은 역할) — 소스가 아니므로 커밋 대상에서 뺀다.

- [ ] **Step 2: `terminal/src/main.zig` 작성**

```zig
const std = @import("std");

pub fn main() void {
    std.debug.print("terminal: starting\n", .{});
}
```

- [ ] **Step 3: 컴파일**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c "mkdir -p terminal/zig-out && cd terminal && \
  zig build-exe src/main.zig -femit-bin=zig-out/terminal"
```

Expected: 종료 코드 0, `terminal/zig-out/terminal` 바이너리 생성.

- [ ] **Step 4: 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer terminal/zig-out/terminal
```

Expected: `terminal: starting` 한 줄 출력.

- [ ] **Step 5: 커밋**

```bash
git add .gitignore terminal/src/main.zig
git commit -m "Add Zig project scaffold for Terminal Foundation app"
```

---

### Task 2: DRM/KMS를 Zig로 포팅 + 배경색 채우기 + boot chain 교체

**Files:**
- Create: `terminal/src/drm.zig`
- Modify: `terminal/src/main.zig`
- Modify: `init/src/main.rs`
- Modify: `kernel/make_initrd.sh`
- Create: `terminal/check.sh`

- [ ] **Step 1: `terminal/src/drm.zig` 작성**

`kms/src/main.rs`(DF-M0에서 이미 검증된 raw DRM ioctl 시퀀스)를 Zig로
그대로 포팅한다. 구조체 필드 순서/타입은 원본과 1:1로 맞춘다 — ioctl은
바이너리 레이아웃이 정확히 맞아야 커널이 올바르게 해석한다.

```zig
const std = @import("std");

const c = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("sys/mman.h");
});

const DrmModeCardRes = extern struct {
    fb_id_ptr: u64 = 0,
    crtc_id_ptr: u64 = 0,
    connector_id_ptr: u64 = 0,
    encoder_id_ptr: u64 = 0,
    count_fbs: u32 = 0,
    count_crtcs: u32 = 0,
    count_connectors: u32 = 0,
    count_encoders: u32 = 0,
    min_width: u32 = 0,
    max_width: u32 = 0,
    min_height: u32 = 0,
    max_height: u32 = 0,
};

const DrmModeModeinfo = extern struct {
    clock: u32 = 0,
    hdisplay: u16 = 0,
    hsync_start: u16 = 0,
    hsync_end: u16 = 0,
    htotal: u16 = 0,
    hskew: u16 = 0,
    vdisplay: u16 = 0,
    vsync_start: u16 = 0,
    vsync_end: u16 = 0,
    vtotal: u16 = 0,
    vscan: u16 = 0,
    vrefresh: u32 = 0,
    flags: u32 = 0,
    mode_type: u32 = 0,
    name: [32]u8 = [_]u8{0} ** 32,
};

const DrmModeGetConnector = extern struct {
    encoders_ptr: u64 = 0,
    modes_ptr: u64 = 0,
    props_ptr: u64 = 0,
    prop_values_ptr: u64 = 0,
    count_modes: u32 = 0,
    count_props: u32 = 0,
    count_encoders: u32 = 0,
    encoder_id: u32 = 0,
    connector_id: u32 = 0,
    connector_type: u32 = 0,
    connector_type_id: u32 = 0,
    connection: u32 = 0,
    mm_width: u32 = 0,
    mm_height: u32 = 0,
    subpixel: u32 = 0,
    pad: u32 = 0,
};

const DrmModeGetEncoder = extern struct {
    encoder_id: u32 = 0,
    encoder_type: u32 = 0,
    crtc_id: u32 = 0,
    possible_crtcs: u32 = 0,
    possible_clones: u32 = 0,
};

const DrmModeCreateDumb = extern struct {
    height: u32 = 0,
    width: u32 = 0,
    bpp: u32 = 0,
    flags: u32 = 0,
    handle: u32 = 0,
    pitch: u32 = 0,
    size: u64 = 0,
};

const DrmModeMapDumb = extern struct {
    handle: u32 = 0,
    pad: u32 = 0,
    offset: u64 = 0,
};

const DrmModeCrtc = extern struct {
    set_connectors_ptr: u64 = 0,
    count_connectors: u32 = 0,
    crtc_id: u32 = 0,
    fb_id: u32 = 0,
    x: u32 = 0,
    y: u32 = 0,
    gamma_size: u32 = 0,
    mode_valid: u32 = 0,
    mode: DrmModeModeinfo = .{},
};

const DrmModeFbCmd = extern struct {
    fb_id: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    pitch: u32 = 0,
    bpp: u32 = 0,
    depth: u32 = 0,
    handle: u32 = 0,
};

fn drmIowr(comptime T: type, nr: u32) u32 {
    const drm_ioctl_base: u32 = 'd';
    return (@as(u32, 3) << 30) | (drm_ioctl_base << 8) | nr | (@as(u32, @sizeOf(T)) << 16);
}

fn drmIoctl(fd: c_int, request: u32, arg: *anyopaque) !void {
    const rc = c.ioctl(fd, @as(c_ulong, request), arg);
    if (rc < 0) return error.IoctlFailed;
}

pub const Framebuffer = struct {
    file: std.fs.File,
    width: u32,
    height: u32,
    pitch: u32,
    pixels: [*]volatile u8,

    pub fn setPixel(self: Framebuffer, x: u32, y: u32, color: u32) void {
        const offset = y * self.pitch + x * 4;
        const ptr: *volatile u32 = @ptrCast(@alignCast(self.pixels + offset));
        ptr.* = color;
    }

    pub fn fill(self: Framebuffer, color: u32) void {
        var row: u32 = 0;
        while (row < self.height) : (row += 1) {
            var col: u32 = 0;
            while (col < self.width) : (col += 1) {
                self.setPixel(col, row, color);
            }
        }
    }
};

fn getResources(allocator: std.mem.Allocator, fd: c_int) !struct {
    crtc_ids: []u32,
    connector_ids: []u32,
} {
    var res: DrmModeCardRes = .{};
    try drmIoctl(fd, drmIowr(DrmModeCardRes, 0xA0), @ptrCast(&res));

    const crtc_ids = try allocator.alloc(u32, res.count_crtcs);
    const connector_ids = try allocator.alloc(u32, res.count_connectors);
    const encoder_ids = try allocator.alloc(u32, res.count_encoders);
    defer allocator.free(encoder_ids);

    res.crtc_id_ptr = @intFromPtr(crtc_ids.ptr);
    res.connector_id_ptr = @intFromPtr(connector_ids.ptr);
    res.encoder_id_ptr = @intFromPtr(encoder_ids.ptr);
    res.fb_id_ptr = 0;

    try drmIoctl(fd, drmIowr(DrmModeCardRes, 0xA0), @ptrCast(&res));

    std.debug.print("kms: {d} crtcs, {d} connectors, {d} encoders\n", .{
        res.count_crtcs, res.count_connectors, res.count_encoders,
    });

    return .{ .crtc_ids = crtc_ids, .connector_ids = connector_ids };
}

fn findConnectedConnector(
    allocator: std.mem.Allocator,
    fd: c_int,
    connector_ids: []const u32,
) !struct { connector: DrmModeGetConnector, mode: DrmModeModeinfo, encoders: []u32 } {
    for (connector_ids) |id| {
        var conn: DrmModeGetConnector = .{ .connector_id = id };
        try drmIoctl(fd, drmIowr(DrmModeGetConnector, 0xA7), @ptrCast(&conn));

        if (conn.connection != 1 or conn.count_modes == 0) continue;

        const modes = try allocator.alloc(DrmModeModeinfo, conn.count_modes);
        defer allocator.free(modes);
        const encoders = try allocator.alloc(u32, conn.count_encoders);

        conn.modes_ptr = @intFromPtr(modes.ptr);
        conn.encoders_ptr = @intFromPtr(encoders.ptr);
        conn.props_ptr = 0;
        conn.prop_values_ptr = 0;
        conn.count_props = 0;

        try drmIoctl(fd, drmIowr(DrmModeGetConnector, 0xA7), @ptrCast(&conn));

        const mode = modes[0];
        std.debug.print("kms: connector {d} connected, mode {d}x{d}\n", .{
            id, mode.hdisplay, mode.vdisplay,
        });
        return .{ .connector = conn, .mode = mode, .encoders = encoders };
    }
    return error.NoConnectedConnector;
}

fn findCrtc(fd: c_int, encoder_id: u32, crtc_ids: []const u32) !u32 {
    var enc: DrmModeGetEncoder = .{ .encoder_id = encoder_id };
    try drmIoctl(fd, drmIowr(DrmModeGetEncoder, 0xA6), @ptrCast(&enc));

    if (enc.crtc_id != 0) return enc.crtc_id;

    for (crtc_ids, 0..) |crtc_id, i| {
        if (enc.possible_crtcs & (@as(u32, 1) << @as(u5, @intCast(i))) != 0) return crtc_id;
    }
    return error.NoUsableCrtc;
}

pub fn open(allocator: std.mem.Allocator, path: []const u8) !Framebuffer {
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });
    const fd: c_int = @intCast(file.handle);

    const resources = try getResources(allocator, fd);
    const found = try findConnectedConnector(allocator, fd, resources.connector_ids);
    const encoder_id = if (found.connector.encoder_id != 0)
        found.connector.encoder_id
    else if (found.encoders.len > 0)
        found.encoders[0]
    else
        return error.NoEncoders;
    const crtc_id = try findCrtc(fd, encoder_id, resources.crtc_ids);

    std.debug.print("kms: selected crtc {d}\n", .{crtc_id});

    var dumb: DrmModeCreateDumb = .{
        .height = found.mode.vdisplay,
        .width = found.mode.hdisplay,
        .bpp = 32,
    };
    try drmIoctl(fd, drmIowr(DrmModeCreateDumb, 0xB2), @ptrCast(&dumb));
    std.debug.print("kms: dumb buffer handle={d} pitch={d} size={d}\n", .{
        dumb.handle, dumb.pitch, dumb.size,
    });

    var map: DrmModeMapDumb = .{ .handle = dumb.handle };
    try drmIoctl(fd, drmIowr(DrmModeMapDumb, 0xB3), @ptrCast(&map));

    const map_ptr = c.mmap(
        null,
        dumb.size,
        c.PROT_READ | c.PROT_WRITE,
        c.MAP_SHARED,
        fd,
        @as(c.off_t, @intCast(map.offset)),
    );
    if (@intFromPtr(map_ptr) == std.math.maxInt(usize)) {
        return error.MmapFailed;
    }

    var fb_cmd: DrmModeFbCmd = .{
        .width = dumb.width,
        .height = dumb.height,
        .pitch = dumb.pitch,
        .bpp = 32,
        .depth = 24,
        .handle = dumb.handle,
    };
    try drmIoctl(fd, drmIowr(DrmModeFbCmd, 0xAE), @ptrCast(&fb_cmd));
    std.debug.print("kms: created framebuffer fb_id={d}\n", .{fb_cmd.fb_id});

    var connector_id_arr = [_]u32{found.connector.connector_id};
    var crtc: DrmModeCrtc = .{
        .set_connectors_ptr = @intFromPtr(&connector_id_arr),
        .count_connectors = 1,
        .crtc_id = crtc_id,
        .fb_id = fb_cmd.fb_id,
        .mode_valid = 1,
        .mode = found.mode,
    };
    try drmIoctl(fd, drmIowr(DrmModeCrtc, 0xA2), @ptrCast(&crtc));
    std.debug.print("kms: set crtc {d} to fb {d}\n", .{ crtc_id, fb_cmd.fb_id });

    return Framebuffer{
        .file = file,
        .width = dumb.width,
        .height = dumb.height,
        .pitch = dumb.pitch,
        .pixels = @ptrCast(map_ptr),
    };
}
```

`init`이 `/dev`를 이미 `devtmpfs`로 mount한 뒤 이 프로세스를 fork/exec하므로
(Task 3 참고), `kms/src/main.rs`에 있던 `ensure_devtmpfs_mounted()`는 여기서
다시 부르지 않는다.

**만약 `zig build-exe`가 `c.ioctl`/`c.mmap` 인자 타입 에러를 내면:** `fd`를
넘기는 자리에 `@as(c_int, fd)`를 명시적으로 추가하거나, `map.offset`을
`@as(c.off_t, @intCast(map.offset))` 대신 `@intCast(map.offset)`만 써서
타입을 컴파일러가 문맥으로 추론하게 해본다 — Zig 버전별로 C 타입 추론
엄격도가 다를 수 있다.

- [ ] **Step 2: `terminal/src/main.zig`을 배경 채우기로 교체**

```zig
const std = @import("std");
const drm = @import("drm.zig");

const BACKGROUND: u32 = 0x00102030;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const fb = try drm.open(allocator, "/dev/dri/card0");
    fb.fill(BACKGROUND);
    std.debug.print("terminal: filled framebuffer with background\n", .{});

    while (true) {
        std.time.sleep(std.time.ns_per_s);
    }
}
```

- [ ] **Step 3: `init/src/main.rs`에서 `/kms` 대신 `/terminal`을 실행하도록 교체**

`init/src/main.rs` 전체를 다음으로 교체한다(`run_kms` 함수만 `run_terminal`로
바뀌고 나머지는 동일):

```rust
use std::ffi::CString;
use std::ptr;

extern "C" {
    static environ: *const *const libc::c_char;
}

fn mount_fs(source: &str, target: &str, fstype: &str) {
    let source_c = CString::new(source).expect("CString::new failed");
    let target_c = CString::new(target).expect("CString::new failed");
    let fstype_c = CString::new(fstype).expect("CString::new failed");

    let ret = unsafe {
        libc::mount(
            source_c.as_ptr(),
            target_c.as_ptr(),
            fstype_c.as_ptr(),
            0,
            ptr::null(),
        )
    };

    if ret == 0 {
        println!("tars-init: mounted {} at {}", fstype, target);
    } else {
        let errno = unsafe { *libc::__errno_location() };
        println!(
            "tars-init: failed to mount {} at {} (errno {})",
            fstype, target, errno
        );
    }
}

fn log_drm_device_presence() {
    if std::path::Path::new("/dev/dri/card0").exists() {
        println!("tars-init: /dev/dri/card0 exists");
    } else {
        println!("tars-init: /dev/dri/card0 not found");
    }
}

fn run_terminal() {
    let pid = unsafe { libc::fork() };
    if pid == 0 {
        let terminal = CString::new("/terminal").expect("CString::new failed");
        let argv: [*const libc::c_char; 2] = [terminal.as_ptr(), ptr::null()];
        unsafe {
            libc::execve(terminal.as_ptr(), argv.as_ptr(), environ);
        }
        let errno = unsafe { *libc::__errno_location() };
        eprintln!("tars-init: execve /terminal failed (errno {})", errno);
        unsafe { libc::_exit(1) };
    } else if pid > 0 {
        println!("tars-init: forked terminal (pid {})", pid);
    } else {
        let errno = unsafe { *libc::__errno_location() };
        println!("tars-init: fork for terminal failed (errno {})", errno);
    }
}

fn setup_controlling_terminal() {
    let console = CString::new("/dev/console").expect("CString::new failed");
    let fd = unsafe { libc::open(console.as_ptr(), libc::O_RDWR) };
    if fd < 0 {
        let errno = unsafe { *libc::__errno_location() };
        println!("tars-init: failed to open /dev/console (errno {})", errno);
        return;
    }

    unsafe {
        libc::setsid();
        libc::ioctl(fd, libc::TIOCSCTTY, 0);
        libc::dup2(fd, 0);
        libc::dup2(fd, 1);
        libc::dup2(fd, 2);
        if fd > 2 {
            libc::close(fd);
        }
    }

    println!("tars-init: set up /dev/console as controlling terminal");
}

fn main() {
    println!("tars-init: starting as PID 1");

    mount_fs("proc", "/proc", "proc");
    mount_fs("sysfs", "/sys", "sysfs");
    mount_fs("devtmpfs", "/dev", "devtmpfs");

    log_drm_device_presence();

    run_terminal();

    setup_controlling_terminal();

    let shell = CString::new("/usr/bin/fish").expect("CString::new failed");
    let argv: [*const libc::c_char; 2] = [shell.as_ptr(), ptr::null()];

    unsafe {
        libc::execve(shell.as_ptr(), argv.as_ptr(), environ);
    }

    let errno = unsafe { *libc::__errno_location() };
    eprintln!("tars-init: execve failed (errno {})", errno);
}
```

- [ ] **Step 4: `kernel/make_initrd.sh`에서 `kms` 대신 `terminal` 바이너리를 담도록 교체**

`kernel/make_initrd.sh`의 다음 두 줄:

```bash
cp ../kms/target/release/kms "$WORKDIR/kms"
chmod 0755 "$WORKDIR/kms"
```

를 다음으로 바꾼다:

```bash
cp ../terminal/zig-out/terminal "$WORKDIR/terminal"
chmod 0755 "$WORKDIR/terminal"
```

그리고 `copy_lib_deps "$WORKDIR/kms"` 줄을 `copy_lib_deps "$WORKDIR/terminal"`로
바꾼다. 최종 파일 전체:

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

copy_lib_deps() {
  local bin="$1"
  local lib
  for lib in $(ldd "$bin" | grep -oE '/[^ ]+\.so[0-9.]*'); do
    mkdir -p "$WORKDIR$(dirname "$lib")"
    cp -n "$lib" "$WORKDIR$lib"
  done
}

mkdir -p "$WORKDIR/usr/bin" "$WORKDIR/proc" "$WORKDIR/sys" "$WORKDIR/dev"

cp ../init/target/release/tars-init "$WORKDIR/init"
chmod 0755 "$WORKDIR/init"

cp ../terminal/zig-out/terminal "$WORKDIR/terminal"
chmod 0755 "$WORKDIR/terminal"

cp /usr/bin/fish "$WORKDIR/usr/bin/fish"
chmod 0755 "$WORKDIR/usr/bin/fish"

copy_lib_deps "$WORKDIR/init"
copy_lib_deps "$WORKDIR/terminal"
copy_lib_deps "$WORKDIR/usr/bin/fish"

mkdir -p "$WORKDIR/usr/share/fish"
cp -r /usr/share/fish/functions "$WORKDIR/usr/share/fish/"
cp /usr/share/fish/config.fish "$WORKDIR/usr/share/fish/"
cp /usr/share/fish/__fish_build_paths.fish "$WORKDIR/usr/share/fish/"

(cd "$WORKDIR" && find . | cpio -o -H newc) > initrd.cpio
```

`kms` crate 자체(`kms/src/main.rs`, `display/check.sh`)는 그대로 저장소에
남는다 — Display Foundation 산출물이자 이번 `drm.zig` 포팅의 원본 참고
코드로서 유효하다. 다만 이제부터 실제 boot chain(`init` → `initrd`)에는
들어가지 않는다.

- [ ] **Step 5: `terminal/check.sh` 작성**

`display/check.sh`와 같은 패턴이되, kms 빌드 대신 Zig 빌드를 하고, 검사
좌표/색을 이번 milestone 값으로 바꾼다:

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && cargo build --release); then
  echo "FAIL: init build failed"
  exit 1
fi

mkdir -p zig-out
if ! (cd . && zig build-exe src/main.zig -femit-bin=zig-out/terminal); then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

MONITOR_PORT=45455
SCREENSHOT="$(mktemp /tmp/tf-m1-XXXXXX.ppm)"
LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

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

MONITOR_READY=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then
    MONITOR_READY=1
    break
  fi
  sleep 0.5
done

if [ "$MONITOR_READY" != "1" ]; then
  echo "FAIL: could not connect to QEMU monitor on port ${MONITOR_PORT}"
  cat "$LOG"
  exit 1
fi

sleep 5
echo "screendump ${SCREENSHOT}" >&3
sleep 1
exec 3<&-
exec 3>&-

kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

if [ ! -s "$SCREENSHOT" ]; then
  echo "FAIL: screendump did not produce a file at ${SCREENSHOT}"
  cat "$LOG"
  exit 1
fi

if command -v magick >/dev/null 2>&1; then
  IDENTIFY=(magick identify)
  CONVERT=(magick)
else
  IDENTIFY=(identify)
  CONVERT=(convert)
fi

DIMENSIONS=$("${IDENTIFY[@]}" -format "%wx%h" "$SCREENSHOT" 2>&1) || {
  echo "FAIL: ImageMagick could not read ${SCREENSHOT}: ${DIMENSIONS}"
  exit 1
}
echo "Captured screendump: ${SCREENSHOT} (${DIMENSIONS})"

PIXEL=$("${CONVERT[@]}" "${SCREENSHOT}" -crop 1x1+5+5 +repage txt:- 2>&1) || {
  echo "FAIL: ImageMagick could not extract pixel at (5,5): ${PIXEL}"
  exit 1
}
echo "Pixel at (5,5): ${PIXEL}"

if ! echo "$PIXEL" | grep -qi '#102030'; then
  echo "FAIL: expected background (#102030) at (5,5), got: ${PIXEL}"
  exit 1
fi

echo "PASS"
exit 0
```

Task 4에서 이 스크립트에 글리프 영역 검사를 추가한다 — 지금은 배경색
검사까지만으로 "Zig가 짠 DRM 코드로 화면에 뭔가 나온다"를 먼저 확인한다.

- [ ] **Step 6: 실행 권한 부여**

```bash
chmod +x terminal/check.sh
```

- [ ] **Step 7: 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/check.sh
```

Expected: 마지막 줄 `PASS`, 종료 코드 0. `Pixel at (5,5): ...`에
`#102030`(대소문자 무관)이 포함되어 있어야 한다.

**만약 FAIL이면:** 출력된 `LOG`(직렬 콘솔) 내용을 먼저 본다 —
`tars-init: /dev/dri/card0 not found`가 보이면 DF-M0/M1과 동일하게
virtio-gpu 드라이버 문제, `kms: ...` 로그가 전혀 없으면 `/terminal`
exec 자체가 실패한 것(Step 3의 경로 오타 등)일 가능성이 높다.

- [ ] **Step 8: 커밋**

```bash
git add terminal/src/drm.zig terminal/src/main.zig init/src/main.rs \
  kernel/make_initrd.sh terminal/check.sh
git commit -m "Port DRM/KMS to Zig and switch boot chain from kms to terminal"
```

---

### Task 3: 폰트 로드 + glyph cache (stb_truetype FFI)

**Files:**
- Create: `terminal/src/font.zig`
- Create: `terminal/src/font_test.zig`

- [ ] **Step 1: `terminal/src/font.zig` 작성**

```zig
const std = @import("std");

const stb = @cImport({
    @cDefine("STB_TRUETYPE_IMPLEMENTATION", "1");
    @cInclude("stb_truetype.h");
});

pub const Glyph = struct {
    codepoint: u32,
    width: u32,
    height: u32,
    cell_width: u32,
    bitmap: ?[*]u8,
};

pub const GlyphCache = struct {
    glyphs: []Glyph,
};

fn cellWidth(codepoint: u32) u32 {
    // 8x4x4-fonts는 라틴 8px, 한글 16px 고정 grid다(design doc 4번 결정).
    return if (codepoint > 0x7F) 16 else 8;
}

pub fn build(allocator: std.mem.Allocator, font_data: []const u8, codepoints: []const u32) !GlyphCache {
    var font: stb.stbtt_fontinfo = undefined;
    if (stb.stbtt_InitFont(&font, font_data.ptr, 0) == 0) {
        return error.FontInitFailed;
    }

    const glyphs = try allocator.alloc(Glyph, codepoints.len);
    const pixel_height: f32 = 16.0;
    const scale = stb.stbtt_ScaleForPixelHeight(&font, pixel_height);

    for (codepoints, 0..) |codepoint, i| {
        var w: c_int = 0;
        var h: c_int = 0;
        var xoff: c_int = 0;
        var yoff: c_int = 0;
        const bitmap = stb.stbtt_GetCodepointBitmap(
            &font,
            scale,
            scale,
            @intCast(codepoint),
            &w,
            &h,
            &xoff,
            &yoff,
        );
        // 공백처럼 잉크가 없는 글자는 stb가 0x0 비트맵(bitmap == null)을
        // 돌려준다 — 에러가 아니라 "그릴 게 없다"는 정상 결과다.
        if (bitmap == null and w * h != 0) return error.RasterizeFailed;

        glyphs[i] = Glyph{
            .codepoint = codepoint,
            .width = @intCast(w),
            .height = @intCast(h),
            .cell_width = cellWidth(codepoint),
            .bitmap = bitmap,
        };
    }

    return GlyphCache{ .glyphs = glyphs };
}
```

- [ ] **Step 2: `terminal/src/font_test.zig` 작성(호스트에서 바로 실행하는 native 테스트, QEMU 불필요)**

```zig
const std = @import("std");
const font = @import("font.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const file = try std.fs.cwd().readFileAlloc(
        allocator,
        "vendor/fonts/Hanme_8x4x4.ttf",
        10 * 1024 * 1024,
    );

    // "TARS 하이"
    const codepoints = [_]u32{ 'T', 'A', 'R', 'S', ' ', 0xD558, 0xC774 };
    const cache = try font.build(allocator, file, &codepoints);

    for (cache.glyphs) |glyph| {
        if (glyph.bitmap) |bitmap| {
            var nonzero: usize = 0;
            var idx: usize = 0;
            while (idx < glyph.width * glyph.height) : (idx += 1) {
                if (bitmap[idx] > 0) nonzero += 1;
            }
            std.debug.print(
                "codepoint U+{X}: {d}x{d} pixels, cell_width={d}, {d} non-zero\n",
                .{ glyph.codepoint, glyph.width, glyph.height, glyph.cell_width, nonzero },
            );
        } else {
            std.debug.print(
                "codepoint U+{X}: no bitmap (whitespace), cell_width={d}\n",
                .{ glyph.codepoint, glyph.cell_width },
            );
        }
    }
}
```

- [ ] **Step 3: 컴파일**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c "cd terminal && zig build-exe src/font_test.zig \
  -I vendor -lc -lm -femit-bin=zig-out/font_test"
```

Expected: 종료 코드 0, `terminal/zig-out/font_test` 생성.

**만약 `stb_truetype.h`를 못 찾는다는 에러가 나면:** `-I vendor` 경로가
`terminal/vendor/stb_truetype.h`를 가리키는지 확인한다(TF-M0 Task 5와
동일한 벤더링 결과물이어야 한다).

- [ ] **Step 4: 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c "cd terminal && ./zig-out/font_test"
```

Expected: 코드포인트 7개(`T`, `A`, `R`, `S`, ` `, `D558`, `C774`) 각각에
대해 한 줄씩 출력. `' '`(공백)만 `no bitmap (whitespace)`, 나머지 6개는
`WxH pixels, cell_width=(8 또는 16), N non-zero`(N > 0) 형태여야 한다.
특히 `D558`, `C774`(한글 음절)의 `cell_width`가 `16`인지 확인 — 8이면
`cellWidth` 함수의 분기 조건이 잘못된 것이다.

- [ ] **Step 5: 커밋**

```bash
git add terminal/src/font.zig terminal/src/font_test.zig
git commit -m "Add glyph cache built from stb_truetype FFI"
```

---

### Task 4: 렌더러 통합 + 전체 파이프라인 검증

**Files:**
- Modify: `terminal/src/main.zig`
- Modify: `terminal/check.sh`

- [ ] **Step 1: `terminal/src/main.zig`을 glyph cache + blit으로 교체**

```zig
const std = @import("std");
const drm = @import("drm.zig");
const font = @import("font.zig");

const BACKGROUND: u32 = 0x00102030;
const TEXT_COLOR: u32 = 0x00FFFFFF;
const TEXT_X: u32 = 20;
const TEXT_Y: u32 = 20;

fn drawGlyph(fb: drm.Framebuffer, glyph: font.Glyph, x: u32, y: u32) void {
    const bitmap = glyph.bitmap orelse return;
    var row: u32 = 0;
    while (row < glyph.height) : (row += 1) {
        var col: u32 = 0;
        while (col < glyph.width) : (col += 1) {
            const coverage = bitmap[row * glyph.width + col];
            if (coverage > 127) {
                fb.setPixel(x + col, y + row, TEXT_COLOR);
            }
        }
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const fb = try drm.open(allocator, "/dev/dri/card0");
    fb.fill(BACKGROUND);
    std.debug.print("terminal: filled framebuffer with background\n", .{});

    const font_data = try std.fs.cwd().readFileAlloc(
        allocator,
        "vendor/fonts/Hanme_8x4x4.ttf",
        10 * 1024 * 1024,
    );

    // "TARS 하이"
    const codepoints = [_]u32{ 'T', 'A', 'R', 'S', ' ', 0xD558, 0xC774 };
    const cache = try font.build(allocator, font_data, &codepoints);

    var x: u32 = TEXT_X;
    for (cache.glyphs) |glyph| {
        drawGlyph(fb, glyph, x, TEXT_Y);
        x += glyph.cell_width;
    }
    std.debug.print("terminal: rendered test string\n", .{});

    while (true) {
        std.time.sleep(std.time.ns_per_s);
    }
}
```

`stbtt_GetCodepointBitmap`이 돌려주는 `xoff`/`yoff`(문자별 베이스라인
정렬 오프셋)는 이번 milestone에서 무시하고 모든 글리프를 셀 좌상단에
맞춰 그린다 — 완전히 정렬된 모노스페이스 그리드가 아니라 살짝 삐뚤 수
있지만, TF-M1의 목표는 "읽을 수 있는 텍스트가 나오는가"이지 타이포그래피
품질이 아니다(design doc 비목표 참고).

- [ ] **Step 2: `terminal/check.sh`에 glyph 영역 검사 추가**

`terminal/check.sh`에서 다음 블록:

```bash
if ! echo "$PIXEL" | grep -qi '#102030'; then
  echo "FAIL: expected background (#102030) at (5,5), got: ${PIXEL}"
  exit 1
fi

echo "PASS"
exit 0
```

를 다음으로 바꾼다(배경색 검사는 그대로 두고, 글리프 영역 검사를
추가한다. 문자열 "TARS 하이"는 폭 `5*8 + 2*16 = 72px`, 높이 `16px`이므로
`(20,20)`에서 `72x16` 영역을 crop한다):

```bash
if ! echo "$PIXEL" | grep -qi '#102030'; then
  echo "FAIL: expected background (#102030) at (5,5), got: ${PIXEL}"
  exit 1
fi

UNIQUE_COLORS=$("${CONVERT[@]}" "${SCREENSHOT}" -crop 72x16+20+20 +repage \
  -format "%k" info: 2>&1) || {
  echo "FAIL: ImageMagick could not count colors in glyph region: ${UNIQUE_COLORS}"
  exit 1
}
echo "Unique colors in glyph region (20,20)-(92,36): ${UNIQUE_COLORS}"

if [ "$UNIQUE_COLORS" -lt 2 ]; then
  echo "FAIL: glyph region has only ${UNIQUE_COLORS} unique color(s), expected >= 2 (background + text)"
  exit 1
fi

echo "PASS"
exit 0
```

`-format "%k"`는 이미지(여기서는 crop된 영역) 안의 unique color 개수를
센다. 배경색 하나만 있으면 `1`, 글자가 실제로 그려졌으면 최소 배경+흰색
2개 이상이 나온다 — "정확한 글자 모양"까지는 아니지만 "이 영역에 뭔가
그려졌다"는 자동으로 확인된다.

- [ ] **Step 3: 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/check.sh
```

Expected: `Pixel at (5,5): ...#102030...`, `Unique colors in glyph region
...: N`(N >= 2), 마지막 줄 `PASS`, 종료 코드 0.

**만약 `Unique colors`가 `1`이면:** 배경만 채워지고 글자가 안 그려진
것이다 — `coverage > 127` 임계값이 너무 높거나(`stb_truetype`은
0~255 grayscale coverage를 돌려준다), `TEXT_X`/`TEXT_Y`/crop 좌표가
어긋났을 가능성을 먼저 의심한다. screendump 파일(`$SCREENSHOT` 경로가
출력에 남는다)을 로컬로 복사해 직접 열어보면 원인을 눈으로 확인할 수
있다.

- [ ] **Step 4: 커밋**

```bash
git add terminal/src/main.zig terminal/check.sh
git commit -m "Render fixed ASCII+Hangul string to framebuffer and verify via screendump"
```

---

## TF-M1 완료 확인

Task 4 Step 3이 `PASS`로 끝나면, design doc 기준 TF-M1의 목표("glyph cache
구축 + 고정 문자열을 KMS 프레임버퍼에 렌더링")가 자동 검증까지 포함해
완료된다. 이 시점에서 `terminal/check.sh`가 만든 screendump를 육안으로도
한 번 열어봐서 "TARS 하이"가 실제로 읽을 수 있는 모양인지 확인한 뒤,
TF-M2(PTY + `libghostty-vt` 연동) plan을 별도로 작성한다.
