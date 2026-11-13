//! DY-M0. `tars-kms-fill <RRGGBB> <초>` — 화면을 한 색으로 칠하고 기다리는 시험 프로그램.
//!
//! 양보의 문제와 GL의 문제를 섞지 않으려고 Mesa도 SDL도 없이 dumb buffer 하나로 한다(DY design
//! Milestone). `card0`을 스스로 여는 기성 프로그램의 흉내다 — master가 비어 있으면 연 것만으로
//! master다(확인 3). 단계마다 `tars-kms-fill: <단계> ok|errno N`을 stderr에 찍는다(게이트와 실기의
//! `2>/tmp/fill.log`가 같은 줄을 본다). 모양은 프로브 `display/probe/kms-handover.c`의
//! `find` · `mkfb` · `setcrtc`다. terminal의 `drm.zig`를 끌어오지 않는다 — 그쪽은 libc와 배율을 안다.
//!
//! `<초>`가 0이면 신호가 올 때까지 기다린다. 끝나거나 죽으면 커널이 fd를 닫고 fb가 사라진다 —
//! terminal이 되찾는 것은 그 뒤다(확인 5).
const std = @import("std");
const linux = std.os.linux;

// uapi `drm_mode.h`의 구조체. terminal/src/drm.zig와 같은 모양이다.
const CardRes = extern struct {
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

const ModeInfo = extern struct {
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

const GetConnector = extern struct {
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

const GetEncoder = extern struct {
    encoder_id: u32 = 0,
    encoder_type: u32 = 0,
    crtc_id: u32 = 0,
    possible_crtcs: u32 = 0,
    possible_clones: u32 = 0,
};

const CreateDumb = extern struct {
    height: u32 = 0,
    width: u32 = 0,
    bpp: u32 = 0,
    flags: u32 = 0,
    handle: u32 = 0,
    pitch: u32 = 0,
    size: u64 = 0,
};

const MapDumb = extern struct { handle: u32 = 0, pad: u32 = 0, offset: u64 = 0 };

const FbCmd = extern struct {
    fb_id: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    pitch: u32 = 0,
    bpp: u32 = 0,
    depth: u32 = 0,
    handle: u32 = 0,
};

const Crtc = extern struct {
    set_connectors_ptr: u64 = 0,
    count_connectors: u32 = 0,
    crtc_id: u32 = 0,
    fb_id: u32 = 0,
    x: u32 = 0,
    y: u32 = 0,
    gamma_size: u32 = 0,
    mode_valid: u32 = 0,
    mode: ModeInfo = .{},
};

/// `_IOWR('d', nr, T)`.
fn iowr(comptime T: type, nr: u32) u32 {
    return (@as(u32, 3) << 30) | (@as(u32, @sizeOf(T)) << 16) | (@as(u32, 'd') << 8) | nr;
}

const EXIT_USAGE: u8 = 64;
const MAX_IDS = 16;
const MAX_MODES = 64;

fn writeAll(fd: i32, bytes: []const u8) void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = linux.write(fd, bytes[off..].ptr, bytes.len - off);
        if (linux.errno(n) != .SUCCESS) {
            if (linux.errno(n) == .INTR) continue;
            return;
        }
        off += n;
    }
}

fn say(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "tars-kms-fill: " ++ fmt ++ "\n", args) catch return;
    writeAll(2, text);
}

/// 단계 하나의 결과를 찍는다. 실패면 false — 부르는 쪽이 1로 끝난다.
fn step(name: []const u8, rc: usize) bool {
    const e = linux.errno(rc);
    if (e == .SUCCESS) {
        say("{s} ok", .{name});
        return true;
    }
    say("{s} errno {d}", .{ name, @backingInt(e) });
    return false;
}

fn ioctl(fd: i32, req: u32, arg: anytype) usize {
    return linux.ioctl(fd, req, @intFromPtr(arg));
}

fn usage() u8 {
    writeAll(2,
        \\usage: tars-kms-fill RRGGBB SECONDS
        \\  paint the whole screen one colour through /dev/dri/card0 and wait;
        \\  SECONDS 0 waits until a signal. Run it under tars-fullscreen.
        \\
    );
    return EXIT_USAGE;
}

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    if (argv.len != 3) return usage();
    const hex = std.mem.span(argv[1]);
    if (hex.len != 6) return usage();
    const rgb = std.fmt.parseInt(u32, hex, 16) catch return usage();
    const seconds = std.fmt.parseInt(u32, std.mem.span(argv[2]), 10) catch return usage();

    const open_rc = linux.open("/dev/dri/card0", .{ .ACCMODE = .RDWR, .CLOEXEC = true }, 0);
    if (!step("open /dev/dri/card0", open_rc)) return 1;
    const fd: i32 = @intCast(open_rc);

    // 자원. 개수를 처음부터 넉넉한 배열로 받는다 — 커널은 그보다 많으면 개수만 고쳐 준다.
    var crtcs: [MAX_IDS]u32 = @splat(0);
    var conns: [MAX_IDS]u32 = @splat(0);
    var res: CardRes = .{
        .crtc_id_ptr = @intFromPtr(&crtcs),
        .count_crtcs = MAX_IDS,
        .connector_id_ptr = @intFromPtr(&conns),
        .count_connectors = MAX_IDS,
    };
    if (!step("resources", ioctl(fd, iowr(CardRes, 0xA0), &res))) return 1;
    if (res.count_crtcs == 0 or res.count_connectors == 0) {
        say("no crtc or connector", .{});
        return 1;
    }

    // 첫 연결된 connector와 그 첫 mode. GETCONNECTOR는 버퍼 없이 한 번 먼저 불러야 커널이 mode를
    // 채운다(기억 project_display_yield 7).
    var modes: [MAX_MODES]ModeInfo = undefined;
    var found: ?GetConnector = null;
    for (conns[0..@min(res.count_connectors, MAX_IDS)]) |id| {
        var probe: GetConnector = .{ .connector_id = id };
        if (linux.errno(ioctl(fd, iowr(GetConnector, 0xA7), &probe)) != .SUCCESS) continue;
        var conn: GetConnector = .{ .connector_id = id, .modes_ptr = @intFromPtr(&modes), .count_modes = MAX_MODES };
        if (linux.errno(ioctl(fd, iowr(GetConnector, 0xA7), &conn)) != .SUCCESS) continue;
        if (conn.connection != 1 or conn.count_modes == 0) continue;
        found = conn;
        break;
    }
    const conn = found orelse {
        say("connector errno none connected", .{});
        return 1;
    };
    const mode = modes[0];
    say("connector {d} mode {d}x{d}", .{ conn.connector_id, mode.hdisplay, mode.vdisplay });

    // CRTC: connector의 지금 encoder가 물린 것, 없으면 첫 CRTC.
    var crtc_id = crtcs[0];
    if (conn.encoder_id != 0) {
        var enc: GetEncoder = .{ .encoder_id = conn.encoder_id };
        if (linux.errno(ioctl(fd, iowr(GetEncoder, 0xA6), &enc)) == .SUCCESS and enc.crtc_id != 0) crtc_id = enc.crtc_id;
    }

    var dumb: CreateDumb = .{ .width = mode.hdisplay, .height = mode.vdisplay, .bpp = 32 };
    if (!step("dumb buffer", ioctl(fd, iowr(CreateDumb, 0xB2), &dumb))) return 1;
    var map: MapDumb = .{ .handle = dumb.handle };
    if (!step("map", ioctl(fd, iowr(MapDumb, 0xB3), &map))) return 1;
    const addr = linux.mmap(null, @intCast(dumb.size), .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, @intCast(map.offset));
    if (!step("mmap", addr)) return 1;

    // 한 색으로. XRGB8888이라 RRGGBB가 그대로 픽셀 값이다.
    const pixels: [*]u8 = @ptrFromInt(addr);
    var row: u32 = 0;
    while (row < dumb.height) : (row += 1) {
        const line: [*]u32 = @ptrCast(@alignCast(pixels + @as(usize, row) * dumb.pitch));
        @memset(line[0..dumb.width], rgb);
    }

    var fb: FbCmd = .{ .width = dumb.width, .height = dumb.height, .pitch = dumb.pitch, .bpp = 32, .depth = 24, .handle = dumb.handle };
    if (!step("addfb", ioctl(fd, iowr(FbCmd, 0xAE), &fb))) return 1;

    var conn_id = [_]u32{conn.connector_id};
    var set: Crtc = .{
        .set_connectors_ptr = @intFromPtr(&conn_id),
        .count_connectors = 1,
        .crtc_id = crtc_id,
        .fb_id = fb.fb_id,
        .mode_valid = 1,
        .mode = mode,
    };
    // master가 아니면 여기서 EACCES(13)다 — terminal이 양보하지 않았다는 뜻이다(확인 1).
    if (!step("setcrtc", ioctl(fd, iowr(Crtc, 0xA2), &set))) return 1;
    say("{s} on {d}x{d} for {d}s", .{ hex, dumb.width, dumb.height, seconds });

    if (seconds == 0) {
        while (true) _ = linux.pause();
    }
    var left: linux.timespec = .{ .sec = @intCast(seconds), .nsec = 0 };
    while (linux.errno(linux.nanosleep(&left, &left)) == .INTR) {}
    return 0;
}
