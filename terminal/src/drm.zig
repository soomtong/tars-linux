const std = @import("std");
const logline = @import("logline.zig");

// C 헤더는 build.zig가 번역해 `c_drm`으로 넘긴다(ZU-M1). GL-M3이 `@cImport`
// 시절에 여기서 끄던 fortify는 패키지 번역에서는 끌 필요가 없어 켜져 있다.
// 끄는 자리는 이제 build.zig의 `c_poll` 하나이고 이유도 거기에 있다.
const c = @import("c_drm");

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
    name: [32]u8 = @splat(0),
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

/// `struct drm_mode_fb_dirty_cmd`(uapi `drm_mode.h`). clip이 없으면(`num_clips` 0,
/// `clips_ptr` 0) fb 전체가 손상이다 — 둘 중 하나만 0이면 커널이 `-EINVAL`을 낸다.
const DrmModeFbDirtyCmd = extern struct {
    fb_id: u32 = 0,
    flags: u32 = 0,
    color: u32 = 0,
    num_clips: u32 = 0,
    clips_ptr: u64 = 0,
};

/// `struct drm_clip_rect`(uapi `drm.h:96`). `x2` · `y2`는 끝 다음이다. DIRTYFB의 clip 하나.
pub const Clip = extern struct { x1: u16, y1: u16, x2: u16, y2: u16 };

/// 한 프레임에 넘기는 clip의 상한(DR-M2 plan 확정 9). 커널 상한은 `DRM_MODE_FB_DIRTY_MAX_CLIPS`
/// 256이고, 패널 여덟 × 행 47의 교대 run은 192까지 갈 수 있어 접는 규칙이 있어야 한다. 64인
/// 이유는 커널 6.18.42의 두 드라이버다 — virtio-gpu는 clip 전부를 경계 상자 하나로 합쳐
/// (`drm_atomic_helper_damage_merged`) 상자만 host로 옮기므로 개수가 뜻이 없고, simpledrm은
/// clip마다 `drm_fb_blit`를 하므로 64를 넘는 프레임은 어차피 화면 대부분이다.
pub const MAX_CLIPS = 64;

/// 한 프레임의 clip 목록(DR-M2). `push`로 다시 칠한 사각형을 더하고 `present`에 `slice()`를
/// 넘긴다. `all()`은 fb 전체다(통째 프레임) — 그 뒤의 `push`는 무시되고 `slice()`는 비어 있어
/// `present`가 clip 없이(fb 전체 손상) 보낸다. 가득 차면 전부를 경계 상자 하나로 접는다
/// (`folded`) — 접힌 상자는 언제나 상위 집합이라 안전하다.
///
/// 좌표는 fb 안으로 자른다. `fillRect` · `setPixel`과 달리 여기는 자르는 것이 맞다 — clip이
/// fb를 넘으면 커널이 거부하고(`drm_atomic_helper_check_plane_state`), 화살표는 가장자리에서
/// 실제로 잘린다(`pointer.Sprite.span`).
pub const ClipList = struct {
    items: [MAX_CLIPS]Clip = undefined,
    len: usize = 0,
    folded: bool = false,
    whole: bool = false,
    width: u32,
    height: u32,

    pub fn init(width: u32, height: u32) ClipList {
        return .{ .width = width, .height = height };
    }

    pub fn all(self: *ClipList) void {
        self.whole = true;
    }

    pub fn push(self: *ClipList, x: u32, y: u32, w: u32, h: u32) void {
        if (self.whole) return;
        if (x >= self.width or y >= self.height or w == 0 or h == 0) return;
        const r: Clip = .{
            .x1 = @intCast(x),
            .y1 = @intCast(y),
            .x2 = @intCast(@min(x + w, self.width)),
            .y2 = @intCast(@min(y + h, self.height)),
        };
        if (self.len == MAX_CLIPS and !self.folded) {
            var box = self.items[0];
            for (self.items[1..]) |o| box = merge(box, o);
            self.items[0] = box;
            self.len = 1;
            self.folded = true;
        }
        if (self.folded) {
            self.items[0] = merge(self.items[0], r);
        } else {
            self.items[self.len] = r;
            self.len += 1;
        }
    }

    pub fn slice(self: *const ClipList) []const Clip {
        return if (self.whole) &.{} else self.items[0..self.len];
    }

    fn merge(a: Clip, b: Clip) Clip {
        return .{
            .x1 = @min(a.x1, b.x1),
            .y1 = @min(a.y1, b.y1),
            .x2 = @max(a.x2, b.x2),
            .y2 = @max(a.y2, b.y2),
        };
    }
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
    fd: c_int,
    width: u32,
    height: u32,
    pitch: u32,
    /// `volatile`이 아니다(RS-M1). dumb buffer는 MAP_SHARED로 잡은 보통 메모리이고
    /// 장치 레지스터가 아니다. 포인터가 `mmap`에서 왔으므로 컴파일러는 `present`의
    /// `ioctl`이 이 메모리를 읽을 수 있다고 봐야 하고, 그 앞의 쓰기를 못 지운다.
    /// `volatile`이 막던 것은 쓰기를 묶는 일 — `fillRect`의 `@memset`이 쓰는 것이다.
    pixels: [*]u8,
    crtc_id: u32,
    fb_id: u32,
    connector_id: u32,
    mode: DrmModeModeinfo,
    /// 드라이버가 DIRTYFB를 받는가(RS-M3). `open`이 한 번 물어 정한다. false면
    /// `present`가 RS-M2까지처럼 SETCRTC를 한다.
    dirty: bool,

    pub fn setPixel(self: Framebuffer, x: u32, y: u32, color: u32) void {
        const offset = y * self.pitch + x * 4;
        const ptr: *u32 = @ptrCast(@alignCast(self.pixels + offset));
        ptr.* = color;
    }

    /// 우리가 쓴 픽셀을 그대로 되읽는다. dumb buffer를 MAP_SHARED로 잡았고
    /// (`:262`) 단일 버퍼라(present가 setcrtc 한 번) 렌더 직후에 읽으면
    /// 그것이 곧 화면이다. 게이트가 "렌더러가 색을 진짜로 칠했는가"를 보는
    /// 유일한 창구다(design 결정 7).
    pub fn getPixel(self: Framebuffer, x: u32, y: u32) u32 {
        const offset = y * self.pitch + x * 4;
        const ptr: *u32 = @ptrCast(@alignCast(self.pixels + offset));
        return ptr.*;
    }

    /// 사각형 하나를 한 색으로 칠한다(RS-M1). 행마다 그 행의 픽셀 `w`개를 `@memset`
    /// 한 번으로 쓴다. 픽셀마다 `setPixel`을 부르면 주소 산수와 ReleaseSafe의 overflow
    /// 검사가 픽셀마다 붙고, 4바이트씩 따로 쓴다. 여기서는 그것이 행마다 한 번이고
    /// 쓰기는 컴파일러가 넓게 묶는다. 찍히는 값은 픽셀마다 쓴 것과 같다.
    ///
    /// `setPixel`처럼 범위 검사가 없다. 부르는 자리가 화면 안으로 자른 사각형만 넘긴다.
    pub fn fillRect(self: Framebuffer, x: u32, y: u32, w: u32, h: u32, color: u32) void {
        var row: u32 = 0;
        while (row < h) : (row += 1) {
            const offset = (y + row) * self.pitch + x * 4;
            const line: [*]u32 = @ptrCast(@alignCast(self.pixels + offset));
            @memset(line[0..w], color);
        }
    }

    pub fn fill(self: Framebuffer, color: u32) void {
        self.fillRect(0, 0, self.width, self.height, color);
    }

    /// 이 fb를 CRTC에 건다(SETCRTC). 시작에 한 번이다(RS-M3) — `main`이 첫 `fill` 뒤에
    /// 부른다. DIRTYFB가 안 되는 드라이버에서는 `present`가 프레임마다 이것을 부른다.
    pub fn modeset(self: Framebuffer) !void {
        var connector_id_arr = [_]u32{self.connector_id};
        var crtc: DrmModeCrtc = .{
            .set_connectors_ptr = @intFromPtr(&connector_id_arr),
            .count_connectors = 1,
            .crtc_id = self.crtc_id,
            .fb_id = self.fb_id,
            .mode_valid = 1,
            .mode = self.mode,
        };
        // 프레임마다 시리얼에 한 줄을 찍던 자리다. RS-M1이 지웠다 — 그 줄이 그리기
        // 시간(`frame_us`) 안에 있었고 읽는 게이트가 없었다.
        try drmIoctl(self.fd, drmIowr(DrmModeCrtc, 0xA2), @ptrCast(&crtc));
    }

    /// 그린 것을 내보낸다. 모드셋이 아니라 "fb가 바뀌었다"를 알리는 DIRTYFB다(RS-M3).
    /// `clips`가 비어 있으면 fb 전체가 손상이고(DR-M2 전까지 늘 그랬다), 아니면 그 사각형들만이다
    /// (DR-M2, design 결정 6). simpledrm은 손상 영역을 VRAM으로 옮기고 virtio-gpu는 host로
    /// 옮긴다 — clip이 작을수록 옮기는 것이 적다. 둘 다 `drm_atomic_helper_dirtyfb`를 지나
    /// plane의 damage가 되고, virtio-gpu는 경계 상자 하나로 합친다(`ClipList` 주석).
    ///
    /// DIRTYFB를 안 받는 드라이버(`dirty` false)는 clip을 무시하고 SETCRTC다.
    pub fn present(self: Framebuffer, clips: []const Clip) !void {
        if (!self.dirty) return self.modeset();
        var cmd: DrmModeFbDirtyCmd = .{ .fb_id = self.fb_id };
        if (clips.len > 0) {
            cmd.num_clips = @intCast(clips.len);
            cmd.clips_ptr = @intFromPtr(clips.ptr);
        }
        try drmIoctl(self.fd, drmIowr(DrmModeFbDirtyCmd, 0xB1), @ptrCast(&cmd));
    }

    /// 같은 치수의 그림자 버퍼(DR-M1). 모든 그리기 함수가 `Framebuffer`를 값으로 받으므로,
    /// `pixels`만 heap 메모리를 가리키는 값을 하나 더 만들면 그 위에 같은 그림이 그려진다.
    /// verify 모드가 "같은 프레임을 통째 경로로 한 번 더 그려 비교할" 자리다.
    ///
    /// `fd`가 -1이고 id가 전부 0이다 — 이 값으로 `present` · `modeset`을 부르면 안 된다.
    /// 화면에 거는 것은 원본 하나뿐이다.
    pub fn shadow(self: Framebuffer, pixels: [*]u8) Framebuffer {
        return .{
            .fd = -1,
            .width = self.width,
            .height = self.height,
            .pitch = self.pitch,
            .pixels = pixels,
            .crtc_id = 0,
            .fb_id = 0,
            .connector_id = 0,
            .mode = self.mode,
            .dirty = false,
        };
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

    logline.print("kms: {d} crtcs, {d} connectors, {d} encoders\n", .{
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
        logline.print("kms: connector {d} connected, mode {d}x{d}\n", .{
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

pub fn open(allocator: std.mem.Allocator, path: [*:0]const u8) !Framebuffer {
    const fd = c.open(path, c.O_RDWR);
    if (fd < 0) return error.OpenFailed;

    const resources = try getResources(allocator, fd);
    const found = try findConnectedConnector(allocator, fd, resources.connector_ids);
    const encoder_id = if (found.connector.encoder_id != 0)
        found.connector.encoder_id
    else if (found.encoders.len > 0)
        found.encoders[0]
    else
        return error.NoEncoders;
    const crtc_id = try findCrtc(fd, encoder_id, resources.crtc_ids);

    logline.print("kms: selected crtc {d}\n", .{crtc_id});

    var dumb: DrmModeCreateDumb = .{
        .height = found.mode.vdisplay,
        .width = found.mode.hdisplay,
        .bpp = 32,
    };
    try drmIoctl(fd, drmIowr(DrmModeCreateDumb, 0xB2), @ptrCast(&dumb));
    logline.print("kms: dumb buffer handle={d} pitch={d} size={d}\n", .{
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
    logline.print("kms: created framebuffer fb_id={d}\n", .{fb_cmd.fb_id});

    // DIRTYFB를 받는지 묻는다(RS-M3). 드라이버의 fb funcs에 `.dirty`가 없으면 커널이
    // `-ENOSYS`를 낸다 — 그 판정은 plane을 안 보므로 아직 CRTC에 안 건 지금 물어도 답이
    // 같고, 걸리지 않은 fb의 dirty는 아무 일도 안 한다. 실패가 무엇이든 SETCRTC로 남는다.
    var probe: DrmModeFbDirtyCmd = .{ .fb_id = fb_cmd.fb_id };
    const dirty = if (drmIoctl(fd, drmIowr(DrmModeFbDirtyCmd, 0xB1), @ptrCast(&probe))) |_| true else |_| false;
    logline.print("kms: present by {s}\n", .{if (dirty) "dirtyfb" else "setcrtc"});

    return Framebuffer{
        .fd = fd,
        .width = dumb.width,
        .height = dumb.height,
        .pitch = dumb.pitch,
        .pixels = @ptrCast(map_ptr),
        .crtc_id = crtc_id,
        .fb_id = fb_cmd.fb_id,
        .connector_id = found.connector.connector_id,
        .mode = found.mode,
        .dirty = dirty,
    };
}
