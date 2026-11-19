//! `tars-wl-test` — 게이트의 Wayland 테스트 클라이언트(WY design 결정 13, WY-M0 plan 확정 3).
//!
//! xdg_toplevel 하나를 열고 한 색으로 채운 ARGB8888(알파 FF) `wl_shm` 버퍼를 붙인다. 받은 configure · keymap · key ·
//! modifiers · close · frame을 표준 출력에 한 줄씩 찍는다 — `wayland` 체인이 그 줄을 읽어 판정한다. `close`를 받으면
//! 끝난다. `--ignore-close`이면 close를 무시하고 `xdg_wm_base.ping`에 답하지 않는다(서버의 SIGKILL 판정용, 확정 11).
//!
//! 바인딩은 terminal의 서버와 같은 스캐너가 만든 것이다(`build.zig`의 `wayland` 모듈 — 서버는 `server`, 이쪽은
//! `client` 이름공간). libwayland-client는 동적으로 링크하고 `make_initrd.sh`의 `copy_lib_deps`가 따라 싣는다.

const std = @import("std");
const linux = std.os.linux;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;

const EXIT_USAGE: u8 = 2;

/// 서버가 내는 판(WY design 결정 5)을 넘지 않는다. 서버가 더 낮게 내면 그 판으로 bind한다.
const COMPOSITOR_VERSION: u32 = 4;
const SHM_VERSION: u32 = 1;
const SEAT_VERSION: u32 = 7;
const WM_BASE_VERSION: u32 = 5;

/// `frame` 줄은 처음 열 번만 찍는다 — 체인은 콜백이 도는지만 보고, 그 뒤로는 로그가 프레임마다 불어난다.
const FRAME_LINES: u32 = 10;

// ── 줄 ─────────────────────────────────────────────────────────────

/// 표준 출력에 바로 쓴다(버퍼 없음). 체인이 `> /tmp/wl.log`로 받고, `--ignore-close`이면 SIGKILL로 끝나므로
/// 버퍼에 남은 줄이 사라지면 안 된다.
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
    const text = std.fmt.bufPrint(&buf, "wl-test> " ++ fmt ++ "\n", args) catch return;
    writeAll(1, text);
}

// ── 인자 ───────────────────────────────────────────────────────────

const Args = struct {
    /// 0xRRGGBB. 버퍼에는 알파 FF를 붙여 0xFFRRGGBB로 쓴다.
    color: u32 = 0x3366CC,
    width: u32 = 320,
    height: u32 = 200,
    ignore_close: bool = false,
};

fn parseSize(text: []const u8) ?[2]u32 {
    const x = std.mem.indexOfScalar(u8, text, 'x') orelse return null;
    const w = std.fmt.parseInt(u32, text[0..x], 10) catch return null;
    const h = std.fmt.parseInt(u32, text[x + 1 ..], 10) catch return null;
    // 4096은 한 변의 상한이다 — 버퍼가 64MB를 넘지 않게 한다(지금 화면은 1080p 정도).
    if (w == 0 or h == 0 or w > 4096 or h > 4096) return null;
    return .{ w, h };
}

fn parseArgs(argv: []const []const u8) ?Args {
    var args: Args = .{};
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "--ignore-close")) {
            args.ignore_close = true;
        } else if (std.mem.eql(u8, a, "--color")) {
            i += 1;
            if (i == argv.len or argv[i].len != 6) return null;
            args.color = std.fmt.parseInt(u32, argv[i], 16) catch return null;
        } else if (std.mem.eql(u8, a, "--size")) {
            i += 1;
            if (i == argv.len) return null;
            const wh = parseSize(argv[i]) orelse return null;
            args.width = wh[0];
            args.height = wh[1];
        } else return null;
    }
    return args;
}

fn usage() u8 {
    writeAll(2,
        \\usage: tars-wl-test [--color RRGGBB] [--size WxH] [--ignore-close]
        \\  open one xdg_toplevel filled with one colour (default 3366CC, 320x200) and
        \\  print what the compositor sends, one line each. Ends on close, unless
        \\  --ignore-close (then close and ping are ignored).
        \\
    );
    return EXIT_USAGE;
}

// ── 상태 ───────────────────────────────────────────────────────────

const Globals = struct {
    compositor: ?*wl.Compositor = null,
    shm: ?*wl.Shm = null,
    seat: ?*wl.Seat = null,
    wm_base: ?*xdg.WmBase = null,
};

const State = struct {
    args: Args,
    shm: *wl.Shm,
    surface: *wl.Surface,
    keyboard: ?*wl.Keyboard = null,
    buffer: ?*wl.Buffer = null,
    /// 지금 버퍼의 크기. 서버의 configure가 0이 아닌 크기를 주면 그것으로 다시 만든다.
    width: u32,
    height: u32,
    /// toplevel.configure가 준 크기. xdg_surface.configure(묶음의 끝)에서 적용한다.
    pending_w: i32 = 0,
    pending_h: i32 = 0,
    configured: bool = false,
    frames: u32 = 0,
    running: bool = true,
    failed: bool = false,
};

// ── 버퍼 ───────────────────────────────────────────────────────────

/// 한 색으로 채운 ARGB8888 버퍼를 새로 만든다. memfd는 풀을 만든 뒤 닫는다 — 서버가 받은 fd로 따로 mmap한다.
fn makeBuffer(state: *State) !*wl.Buffer {
    const stride = state.width * 4;
    const size = stride * state.height;

    const fd_rc = linux.memfd_create("tars-wl-test", 0);
    if (linux.errno(fd_rc) != .SUCCESS) return error.MemfdFailed;
    const fd: i32 = @intCast(fd_rc);
    defer _ = linux.close(fd);
    if (linux.errno(linux.ftruncate(fd, size)) != .SUCCESS) return error.FtruncateFailed;

    const addr = linux.mmap(null, size, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, 0);
    if (linux.errno(addr) != .SUCCESS) return error.MmapFailed;
    const ptr: [*]u32 = @ptrFromInt(addr);
    // wl_shm의 ARGB8888은 리틀 엔디언 u32 하나가 픽셀 하나다(0xAARRGGBB).
    @memset(ptr[0 .. size / 4], 0xFF000000 | state.args.color);
    _ = linux.munmap(@ptrFromInt(addr), size);

    const pool = try state.shm.createPool(fd, @intCast(size));
    defer pool.destroy();
    return pool.createBuffer(0, @intCast(state.width), @intCast(state.height), @intCast(stride), .argb8888);
}

/// 버퍼를 붙이고 frame 콜백을 건 뒤 commit한다. `fresh`이면 버퍼를 다시 만든다(크기가 바뀌었을 때).
fn draw(state: *State, fresh: bool) void {
    if (fresh or state.buffer == null) {
        if (state.buffer) |old| old.destroy();
        state.buffer = makeBuffer(state) catch |e| {
            say("error buffer={s}", .{@errorName(e)});
            state.failed = true;
            state.running = false;
            return;
        };
    }
    state.surface.attach(state.buffer.?, 0, 0);
    state.surface.damageBuffer(0, 0, std.math.maxInt(i32), std.math.maxInt(i32));
    requestFrame(state);
    state.surface.commit();
}

fn requestFrame(state: *State) void {
    const cb = state.surface.frame() catch return;
    cb.setListener(*State, frameListener, state);
}

// ── 이벤트 ─────────────────────────────────────────────────────────

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, g: *Globals) void {
    switch (event) {
        .global => |global| {
            const name = std.mem.span(global.interface);
            if (std.mem.eql(u8, name, std.mem.span(wl.Compositor.interface.name))) {
                g.compositor = registry.bind(global.name, wl.Compositor, @min(global.version, COMPOSITOR_VERSION)) catch return;
            } else if (std.mem.eql(u8, name, std.mem.span(wl.Shm.interface.name))) {
                g.shm = registry.bind(global.name, wl.Shm, @min(global.version, SHM_VERSION)) catch return;
            } else if (std.mem.eql(u8, name, std.mem.span(wl.Seat.interface.name))) {
                g.seat = registry.bind(global.name, wl.Seat, @min(global.version, SEAT_VERSION)) catch return;
            } else if (std.mem.eql(u8, name, std.mem.span(xdg.WmBase.interface.name))) {
                g.wm_base = registry.bind(global.name, xdg.WmBase, @min(global.version, WM_BASE_VERSION)) catch return;
            }
        },
        .global_remove => {},
    }
}

fn wmBaseListener(wm_base: *xdg.WmBase, event: xdg.WmBase.Event, state: *State) void {
    switch (event) {
        .ping => |p| if (!state.args.ignore_close) wm_base.pong(p.serial),
    }
}

fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, state: *State) void {
    switch (event) {
        .configure => |c| {
            xdg_surface.ackConfigure(c.serial);
            say("configure w={d} h={d}", .{ state.pending_w, state.pending_h });
            // 0은 "클라이언트가 정하라"다 — 지금 크기를 지킨다.
            var fresh = false;
            if (state.pending_w > 0 and state.pending_h > 0) {
                const w: u32 = @intCast(state.pending_w);
                const h: u32 = @intCast(state.pending_h);
                if (w != state.width or h != state.height) {
                    state.width = w;
                    state.height = h;
                    fresh = true;
                }
            }
            state.configured = true;
            draw(state, fresh);
        },
    }
}

fn toplevelListener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, state: *State) void {
    switch (event) {
        .configure => |c| {
            state.pending_w = c.width;
            state.pending_h = c.height;
        },
        .close => {
            say("close", .{});
            if (!state.args.ignore_close) state.running = false;
        },
        else => {},
    }
}

fn frameListener(cb: *wl.Callback, event: wl.Callback.Event, state: *State) void {
    switch (event) {
        .done => {
            cb.destroy();
            state.frames += 1;
            if (state.frames <= FRAME_LINES) say("frame n={d}", .{state.frames});
            // 내용은 같다 — 콜백이 계속 도는지 보려고 다음 프레임을 다시 건다.
            requestFrame(state);
            state.surface.commit();
        },
    }
}

fn seatListener(seat: *wl.Seat, event: wl.Seat.Event, state: *State) void {
    switch (event) {
        .capabilities => |c| {
            if (c.capabilities.keyboard and state.keyboard == null) {
                const kb = seat.getKeyboard() catch return;
                kb.setListener(*State, keyboardListener, state);
                state.keyboard = kb;
            } else if (!c.capabilities.keyboard and state.keyboard != null) {
                state.keyboard.?.release();
                state.keyboard = null;
            }
        },
        .name => {},
    }
}

fn keyboardListener(_: *wl.Keyboard, event: wl.Keyboard.Event, _: *State) void {
    switch (event) {
        .keymap => |k| {
            say("keymap size={d}", .{k.size});
            _ = linux.close(k.fd);
        },
        .key => |k| say("key code={d} state={d}", .{ k.key, @backingInt(k.state) }),
        .modifiers => |m| say("mods depressed=0x{x}", .{m.mods_depressed}),
        else => {},
    }
}

// ── 실행 ───────────────────────────────────────────────────────────

pub fn main(init: std.process.Init.Minimal) u8 {
    const vector = init.args.vector;
    var spans: [8][]const u8 = undefined;
    if (vector.len > spans.len + 1) return usage();
    for (vector[1..], 0..) |a, i| spans[i] = std.mem.span(a);
    const args = parseArgs(spans[0 .. vector.len - 1]) orelse return usage();
    return run(args) catch |e| {
        say("error {s}", .{@errorName(e)});
        return 1;
    };
}

fn run(args: Args) !u8 {
    const display = try wl.Display.connect(null);
    defer display.disconnect();
    const registry = try display.getRegistry();
    defer registry.destroy();

    var g: Globals = .{};
    registry.setListener(*Globals, registryListener, &g);
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    const compositor = g.compositor orelse return error.NoCompositor;
    const shm = g.shm orelse return error.NoShm;
    const wm_base = g.wm_base orelse return error.NoXdgWmBase;

    const surface = try compositor.createSurface();
    var state: State = .{
        .args = args,
        .shm = shm,
        .surface = surface,
        .width = args.width,
        .height = args.height,
    };
    wm_base.setListener(*State, wmBaseListener, &state);
    // seat가 없어도 창은 뜬다 — 키 줄만 안 나온다.
    if (g.seat) |seat| seat.setListener(*State, seatListener, &state);

    const xdg_surface = try wm_base.getXdgSurface(surface);
    xdg_surface.setListener(*State, xdgSurfaceListener, &state);
    const toplevel = try xdg_surface.getToplevel();
    toplevel.setListener(*State, toplevelListener, &state);
    toplevel.setTitle("tars-wl-test");
    toplevel.setAppId("tars-wl-test");
    // 첫 commit은 버퍼 없이 — 서버가 첫 configure를 보내게 한다(xdg-shell의 순서).
    surface.commit();

    while (state.running) {
        if (display.dispatch() != .SUCCESS) return error.DispatchFailed;
    }
    return if (state.failed) 1 else 0;
}
