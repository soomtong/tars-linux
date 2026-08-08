const std = @import("std");

const c = @cImport({
    @cInclude("fcntl.h");
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
    fd: c_int,
    width: u32,
    height: u32,
    pitch: u32,
    pixels: [*]volatile u8,
    crtc_id: u32,
    fb_id: u32,
    connector_id: u32,
    mode: DrmModeModeinfo,

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

    pub fn present(self: Framebuffer) !void {
        var connector_id_arr = [_]u32{self.connector_id};
        var crtc: DrmModeCrtc = .{
            .set_connectors_ptr = @intFromPtr(&connector_id_arr),
            .count_connectors = 1,
            .crtc_id = self.crtc_id,
            .fb_id = self.fb_id,
            .mode_valid = 1,
            .mode = self.mode,
        };
        try drmIoctl(self.fd, drmIowr(DrmModeCrtc, 0xA2), @ptrCast(&crtc));
        std.debug.print("kms: set crtc {d} to fb {d}\n", .{ self.crtc_id, self.fb_id });
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
    };
}
