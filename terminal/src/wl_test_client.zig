//! `tars-wl-test` — 게이트의 Wayland 테스트 클라이언트(WY design 결정 13, WY-M0 plan 확정 3).
//!
//! xdg_toplevel 하나를 열고 한 색으로 채운 ARGB8888(알파 FF) `wl_shm` 버퍼를 붙인다. 받은 configure · keymap · key ·
//! modifiers · close · frame을 표준 출력에 한 줄씩 찍는다 — `wayland` 체인이 그 줄을 읽어 판정한다. `close`를 받으면
//! 끝난다. `--ignore-close`이면 close를 무시하고 `xdg_wm_base.ping`에 답하지 않는다(서버의 SIGKILL 판정용, 확정 11).
//! WY-M2: 기본은 창 모드라 서버가 셸 오른쪽 column에 연다. `--fullscreen`이면 첫 commit 전에 `set_fullscreen`을 보내
//! 자기 workspace를 받는다(WY-M0 · 둠의 길). configure 줄에 states를, 키보드의 `enter` · `leave`를 줄로 찍는다.
//! 포인터(단계 C): `pointer enter x= y=` · `motion x= y=`(처음 다섯) · `button code= state=` · `axis v=` · `pointer leave`.
//! `--hide-cursor`면 enter마다 `set_cursor(NULL)`을 보낸다(SDL_HideCursor처럼 — 서버가 화살표를 숨기는지 본다).
//! WY-M3(plan 확정 8): `--buffer-scale N`이면 버퍼를 surface 크기 × N으로 만들고 `set_buffer_scale(N)`, `--checker`면 한 색 대신
//! 1 버퍼 픽셀 바둑판. 서버가 알리는 배율을 `preferred scale=N` · `surface on output` · `output mode=WxH scale=N` 줄로 찍는다.
//! `wl_surface.enter`의 줄에 `enter`라는 낱말을 안 쓰는 것은 wayland 체인 판정 16이 이 로그의 `enter`(키보드)를 세기 때문이다.
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
const COMPOSITOR_VERSION: u32 = 6;
const OUTPUT_VERSION: u32 = 4;
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
    /// configure의 크기로 버퍼를 다시 만든다(SDL처럼 구는 클라이언트를 흉내 낸다).
    follow_size: bool = false,
    /// 첫 commit 전에 `set_fullscreen`(WY-M2 확정 12) — 서버가 자기 workspace를 준다.
    fullscreen: bool = false,
    /// 포인터 enter마다 `set_cursor(NULL)`(WY-M2 확정 12).
    hide_cursor: bool = false,
    /// buffer_scale(WY-M3 확정 8, 1..3). 버퍼는 surface 크기 × 이 값이다. `--size`와 configure는 surface 크기다.
    buffer_scale: u32 = 1,
    /// 1 버퍼 픽셀 바둑판 — `(x + y) & 1`이면 `--color`, 아니면 흰색. 게이트가 화면에서 1:1인지 늘린 것인지 가른다.
    checker: bool = false,
};

/// 바둑판의 둘째 색. 둘레의 검정과 갈리게 흰색이다.
const CHECKER_OTHER: u32 = 0xFFFFFF;

/// `motion` 줄은 처음 다섯만 — 포인터가 움직이는 동안 줄이 불어나지 않게.
const MOTION_LINES: u32 = 5;

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
        } else if (std.mem.eql(u8, a, "--follow-size")) {
            args.follow_size = true;
        } else if (std.mem.eql(u8, a, "--fullscreen")) {
            args.fullscreen = true;
        } else if (std.mem.eql(u8, a, "--hide-cursor")) {
            args.hide_cursor = true;
        } else if (std.mem.eql(u8, a, "--checker")) {
            args.checker = true;
        } else if (std.mem.eql(u8, a, "--buffer-scale")) {
            i += 1;
            if (i == argv.len) return null;
            const n = std.fmt.parseInt(u32, argv[i], 10) catch return null;
            if (n < 1 or n > 3) return null;
            args.buffer_scale = n;
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
        \\usage: tars-wl-test [--color RRGGBB] [--size WxH] [--ignore-close] [--follow-size] [--fullscreen]
        \\       [--hide-cursor] [--buffer-scale N] [--checker]
        \\  open one xdg_toplevel filled with one colour (default 3366CC, 320x200) and
        \\  print what the compositor sends, one line each. Ends on close, unless
        \\  --ignore-close (then close and ping are ignored). The buffer keeps its
        \\  own size unless --follow-size (then it takes the configured size).
        \\  --fullscreen asks for fullscreen before the first commit (its own
        \\  workspace); without it the window opens as a column right of the shell.
        \\  --hide-cursor hides the pointer (set_cursor NULL) over the window.
        \\  --buffer-scale N (1..3) draws a buffer N times the surface size and sets
        \\  that buffer scale; sizes (--size, configure) stay in surface units.
        \\  --checker fills a one-buffer-pixel checkerboard of the colour and white.
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
    output: ?*wl.Output = null,
    /// output의 mode · scale을 `done`까지 모은다. listener는 bind하는 자리에서 건다 — output의 이벤트는 첫 roundtrip이 끝난
    /// 뒤의 같은 읽기에 섞여 올 수 있고, listener 없는 proxy의 이벤트는 버려진다.
    out_info: OutputInfo = .{},
};

/// `wl_output`이 `done` 전에 준 값(WY-M3). `done`에서 한 줄로 찍는다.
const OutputInfo = struct { w: i32 = 0, h: i32 = 0, scale: i32 = 1 };

const State = struct {
    args: Args,
    shm: *wl.Shm,
    surface: *wl.Surface,
    keyboard: ?*wl.Keyboard = null,
    pointer: ?*wl.Pointer = null,
    motions: u32 = 0,
    buffer: ?*wl.Buffer = null,
    /// 지금 surface의 크기(버퍼는 × `args.buffer_scale`). 서버의 configure가 0이 아닌 크기를 주면 그것으로 다시 만든다.
    width: u32,
    height: u32,
    /// toplevel.configure가 준 크기. xdg_surface.configure(묶음의 끝)에서 적용한다.
    pending_w: i32 = 0,
    pending_h: i32 = 0,
    /// 같은 configure의 states(`4,5,6,7,8` 모양 — xdg_toplevel.state의 값). 비었으면 `-`.
    pending_states: [48]u8 = undefined,
    pending_states_len: usize = 0,
    configured: bool = false,
    frames: u32 = 0,
    running: bool = true,
    failed: bool = false,
};

// ── 버퍼 ───────────────────────────────────────────────────────────

/// 한 색(또는 `--checker`의 바둑판)으로 채운 ARGB8888 버퍼를 새로 만든다. 크기는 surface × buffer_scale이다. memfd는 풀을
/// 만든 뒤 닫는다 — 서버가 받은 fd로 따로 mmap한다.
fn makeBuffer(state: *State) !*wl.Buffer {
    const bw = state.width * state.args.buffer_scale;
    const bh = state.height * state.args.buffer_scale;
    const stride = bw * 4;
    const size = stride * bh;

    const fd_rc = linux.memfd_create("tars-wl-test", 0);
    if (linux.errno(fd_rc) != .SUCCESS) return error.MemfdFailed;
    const fd: i32 = @intCast(fd_rc);
    defer _ = linux.close(fd);
    if (linux.errno(linux.ftruncate(fd, size)) != .SUCCESS) return error.FtruncateFailed;

    const addr = linux.mmap(null, size, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, 0);
    if (linux.errno(addr) != .SUCCESS) return error.MmapFailed;
    const ptr: [*]u32 = @ptrFromInt(addr);
    // wl_shm의 ARGB8888은 리틀 엔디언 u32 하나가 픽셀 하나다(0xAARRGGBB).
    if (state.args.checker) {
        for (0..bh) |y| for (0..bw) |x| {
            ptr[y * bw + x] = 0xFF000000 | if ((x + y) & 1 == 1) state.args.color else CHECKER_OTHER;
        };
    } else @memset(ptr[0 .. size / 4], 0xFF000000 | state.args.color);
    _ = linux.munmap(@ptrFromInt(addr), size);

    const pool = try state.shm.createPool(fd, @intCast(size));
    defer pool.destroy();
    return pool.createBuffer(0, @intCast(bw), @intCast(bh), @intCast(stride), .argb8888);
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
    // buffer_scale은 double-buffered라 이 commit에 함께 든다. 1이면 보내지 않는다 — WY-M2까지와 같은 요청 순서.
    if (state.args.buffer_scale != 1) state.surface.setBufferScale(@intCast(state.args.buffer_scale));
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
            } else if (std.mem.eql(u8, name, std.mem.span(wl.Output.interface.name))) {
                const o = registry.bind(global.name, wl.Output, @min(global.version, OUTPUT_VERSION)) catch return;
                o.setListener(*OutputInfo, outputListener, &g.out_info);
                g.output = o;
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
            const st = if (state.pending_states_len == 0) "-" else state.pending_states[0..state.pending_states_len];
            say("configure w={d} h={d} states={s}", .{ state.pending_w, state.pending_h, st });
            // 기본은 제 크기(`--size`)를 지킨다. terminal은 화면 크기로 configure하는데(WY-M0 확정 4), 그것을 따르면
            // 버퍼가 화면을 꽉 채워 서버의 정수 배율과 검정 둘레(확정 8)를 볼 수 없다. `--follow-size`면 따른다.
            // 0은 "클라이언트가 정하라"다 — 그때도 지금 크기를 지킨다.
            var fresh = false;
            if (state.args.follow_size and state.pending_w > 0 and state.pending_h > 0) {
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
            var n: usize = 0;
            for (c.states.slice(u32), 0..) |v, i| {
                const part = std.fmt.bufPrint(state.pending_states[n..], "{s}{d}", .{ if (i == 0) "" else ",", v }) catch break;
                n += part.len;
            }
            state.pending_states_len = n;
        },
        .close => {
            say("close", .{});
            if (!state.args.ignore_close) state.running = false;
        },
        else => {},
    }
}

/// 서버가 알리는 배율(WY-M3 확정 8). 판 6 surface의 `preferred_buffer_scale`과 output `enter`.
fn surfaceListener(_: *wl.Surface, event: wl.Surface.Event, _: *State) void {
    switch (event) {
        .preferred_buffer_scale => |p| say("preferred scale={d}", .{p.factor}),
        .enter => say("surface on output", .{}),
        else => {},
    }
}

/// `wl_output`의 mode · scale을 모아 `done`에서 한 줄(WY-M3 확정 8). mode는 물리 크기다.
fn outputListener(_: *wl.Output, event: wl.Output.Event, info: *OutputInfo) void {
    switch (event) {
        .mode => |m| {
            info.w = m.width;
            info.h = m.height;
        },
        .scale => |sc| info.scale = sc.factor,
        .done => say("output mode={d}x{d} scale={d}", .{ info.w, info.h, info.scale }),
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
            if (c.capabilities.pointer and state.pointer == null) {
                const p = seat.getPointer() catch return;
                p.setListener(*State, pointerListener, state);
                state.pointer = p;
            } else if (!c.capabilities.pointer and state.pointer != null) {
                state.pointer.?.release();
                state.pointer = null;
            }
        },
        .name => {},
    }
}

/// 포인터 줄(WY-M2 확정 12). 좌표는 surface 좌표의 정수 부분이다.
fn pointerListener(p: *wl.Pointer, event: wl.Pointer.Event, state: *State) void {
    switch (event) {
        .enter => |e| {
            say("pointer enter x={d} y={d}", .{ e.surface_x.toInt(), e.surface_y.toInt() });
            if (state.args.hide_cursor) p.setCursor(e.serial, null, 0, 0);
        },
        .leave => say("pointer leave", .{}),
        .motion => |m| {
            state.motions += 1;
            if (state.motions <= MOTION_LINES) say("motion x={d} y={d}", .{ m.surface_x.toInt(), m.surface_y.toInt() });
        },
        .button => |b| say("button code={d} state={d}", .{ b.button, @backingInt(b.state) }),
        .axis => |a| say("axis v={d}", .{a.value.toInt()}),
        else => {},
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
        // 키보드 포커스(WY-M2 확정 9) — column 창은 포커스 slot이 될 때 enter, 셸로 옮기면 leave.
        .enter => say("enter", .{}),
        .leave => say("leave", .{}),
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
    surface.setListener(*State, surfaceListener, &state);
    wm_base.setListener(*State, wmBaseListener, &state);
    // seat가 없어도 창은 뜬다 — 키 줄만 안 나온다.
    if (g.seat) |seat| seat.setListener(*State, seatListener, &state);
    // seat의 capabilities를 여기서 받아 `get_keyboard` · `get_pointer`를 첫 commit보다 먼저 보낸다(WY-M3 단계 A). 서버는
    // 요청을 차례로 처리하므로 첫 configure가 나갈 때 키보드가 이미 있다 — 체인이 configure를 보자마자 친 키의 누름이
    // 키보드 없는 틈에 떨어지고 뗌만 오던 경쟁(wayland 판정 16의 `c16-1-1-1`)이 닫힌다.
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    const xdg_surface = try wm_base.getXdgSurface(surface);
    xdg_surface.setListener(*State, xdgSurfaceListener, &state);
    const toplevel = try xdg_surface.getToplevel();
    toplevel.setListener(*State, toplevelListener, &state);
    toplevel.setTitle("tars-wl-test");
    toplevel.setAppId("tars-wl-test");
    // 첫 commit 전이라 서버가 자리를 정할 때 본다(WY-M2 확정 3).
    if (args.fullscreen) toplevel.setFullscreen(null);
    // 첫 commit은 버퍼 없이 — 서버가 첫 configure를 보내게 한다(xdg-shell의 순서).
    surface.commit();

    while (state.running) {
        if (display.dispatch() != .SUCCESS) return error.DispatchFailed;
    }
    return if (state.failed) 1 else 0;
}
