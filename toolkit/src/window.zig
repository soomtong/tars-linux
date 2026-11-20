//! 창 층(TK design 결정 8 · 9, R-TKW-1 · 2 · 4). 앱 하나가 Wayland 클라이언트 하나이고 창(xdg_toplevel) 하나다(R-ARCH-3).
//!
//! 규칙
//! - 버퍼 둘. 버퍼마다 memfd · pool 하나, 매핑을 끝까지 들고 `Canvas`(z2d `Surface`)를 한 번 감싼다. 붙인 버퍼는 서버가
//!   `release`를 보낼 때까지 쓰지 않는다 — 서버는 commit 때 복사하지 않고 그릴 때 shm을 읽는다(WY 결정 9). 둘 다 붙어 있으면
//!   다음 `release`까지 미룬다.
//! - 바뀐 것이 있을 때만 그린다. 그릴 때만 frame을 걸고 commit한다 — 아무것도 안 바뀌면 commit이 0이다(R-TKW-1). frame을
//!   기다리는 동안 생긴 변화는 `done`에서 그린다.
//! - configure의 크기를 늘 따른다(R-TKW-2). 0이면 지금 크기를 지킨다. 크기가 바뀌면 버퍼 둘을 다시 만든다. 서버는
//!   `set_min_size`를 무시하므로(design 확인 8) 보내지 않는다.
//! - 배율: compositor 판 6의 `preferred_buffer_scale`(S)을 받으면 버퍼를 surface 크기 × S로 만들고 `set_buffer_scale(S)`(R-TKW-4).
//!   그리는 쪽은 물리 픽셀로 그린다(`Frame.scale`을 곱한다).
//! - `tars_menu_manager_v1`을 창보다 먼저 bind한다 — 원래 모드라 Cmd가 Super로 온다(design 결정 8, WY 결정 46).
//! - TK-M0은 통째 그리기다. damage는 `damage_buffer` 하나(판 전체). 더티 사각형은 TK-M1.
//!
//! 줄(design 결정 12): `tk> configure w= h= scale=` · `tk> draw w= h= dirty=x,y,w,h us=` · `tk> commit` · `tk> key code= state=` ·
//! `tk> native` · `tk> close`. 표준 출력에 버퍼 없이 쓴다(게이트가 `> 파일`로 받는다 — tars-wl-test와 같다).

const std = @import("std");
const linux = std.os.linux;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const tars = wayland.client.tars;
const Canvas = @import("canvas.zig").Canvas;

/// 서버가 내는 판(WY design 결정 5 · 27 · 46)을 넘지 않는다.
const COMPOSITOR_VERSION: u32 = 6;
const SHM_VERSION: u32 = 1;
const SEAT_VERSION: u32 = 7;
const WM_BASE_VERSION: u32 = 5;
const MENU_MANAGER_VERSION: u32 = 1;

/// configure가 0(클라이언트가 정하라)일 때의 첫 크기.
const DEFAULT_W: u32 = 640;
const DEFAULT_H: u32 = 480;

// ── 줄 ─────────────────────────────────────────────────────────────

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

/// `tk> …` 한 줄.
pub fn say(comptime fmt: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    const t = std.fmt.bufPrint(&buf, "tk> " ++ fmt ++ "\n", args) catch return;
    writeAll(1, t);
}

fn nowNs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

// ── 앱이 주는 것 ──────────────────────────────────────────────────────

/// 그릴 판 하나. `canvas`는 물리 픽셀(`width` × `height` = surface 크기 × `scale`)이다.
pub const Frame = struct {
    canvas: *Canvas,
    width: u32,
    height: u32,
    scale: u32,
};

/// 앱의 콜백. `draw`는 판 전체를 그린다(TK-M0 — 통째). `key`는 받은 키(evdev 코드)이고 없어도 된다.
pub const Handler = struct {
    ctx: *anyopaque,
    draw: *const fn (ctx: *anyopaque, frame: Frame) anyerror!void,
    key: ?*const fn (ctx: *anyopaque, code: u32, pressed: bool) void = null,
};

// ── 버퍼 ───────────────────────────────────────────────────────────

const Buffer = struct {
    buffer: ?*wl.Buffer = null,
    pixels: []u32 = &.{},
    canvas: Canvas = undefined,
    busy: bool = false,

    fn destroy(self: *Buffer) void {
        if (self.buffer) |b| {
            b.destroy();
            _ = linux.munmap(@ptrCast(self.pixels.ptr), self.pixels.len * 4);
        }
        self.* = .{};
    }
};

// ── 창 ─────────────────────────────────────────────────────────────

pub const Window = struct {
    alloc: std.mem.Allocator,
    handler: Handler,
    display: *wl.Display,
    registry: *wl.Registry,
    compositor: ?*wl.Compositor = null,
    shm: ?*wl.Shm = null,
    seat: ?*wl.Seat = null,
    wm_base: ?*xdg.WmBase = null,
    menu_global: ?struct { name: u32, version: u32 } = null,
    keyboard: ?*wl.Keyboard = null,
    surface: *wl.Surface = undefined,
    xdg_surface: *xdg.Surface = undefined,
    toplevel: *xdg.Toplevel = undefined,

    /// surface 크기(논리)와 배율. 버퍼는 × scale.
    width: u32 = DEFAULT_W,
    height: u32 = DEFAULT_H,
    scale: u32 = 1,
    pending_w: i32 = 0,
    pending_h: i32 = 0,
    configured: bool = false,

    bufs: [2]Buffer = .{ .{}, .{} },
    /// 버퍼의 release listener가 받는 자리(버퍼마다 하나 — `*Window`가 아니라 이것을 넘긴다).
    slots: [2]Slot = undefined,
    /// 다시 그려야 한다(크기 · 배율 · 앱의 `invalidate`).
    dirty: bool = true,
    /// frame을 걸고 아직 `done`을 못 받았다.
    frame_pending: bool = false,
    running: bool = true,
    failed: bool = false,
    commits: u64 = 0,

    const Slot = struct { win: *Window, index: usize };

    /// 붙고 창을 연다. 첫 commit(버퍼 없음)까지 보낸다 — 첫 configure가 오면 `run`이 그린다. `title`은 app id로도 쓴다.
    pub fn open(alloc: std.mem.Allocator, title: [*:0]const u8, handler: Handler) !*Window {
        const display = try wl.Display.connect(null);
        errdefer display.disconnect();
        const registry = try display.getRegistry();
        const win = try alloc.create(Window);
        win.* = .{ .alloc = alloc, .handler = handler, .display = display, .registry = registry };
        for (&win.slots, 0..) |*s, i| s.* = .{ .win = win, .index = i };
        registry.setListener(*Window, registryListener, win);
        if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

        const compositor = win.compositor orelse return error.NoCompositor;
        _ = win.shm orelse return error.NoShm;
        const wm_base = win.wm_base orelse return error.NoXdgWmBase;

        // 원래 모드(design 결정 8). 창보다 먼저 — 첫 포커스의 modifiers부터 Super로 받는다.
        if (win.menu_global) |mg| {
            _ = try registry.bind(mg.name, tars.MenuManagerV1, @min(mg.version, MENU_MANAGER_VERSION));
            say("native", .{});
        }

        win.surface = try compositor.createSurface();
        win.surface.setListener(*Window, surfaceListener, win);
        wm_base.setListener(*Window, wmBaseListener, win);
        if (win.seat) |seat| seat.setListener(*Window, seatListener, win);
        // seat capabilities를 받아 `get_keyboard`를 첫 commit보다 먼저 보낸다(tars-wl-test와 같은 까닭 — 첫 키를 놓치지 않는다).
        if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

        win.xdg_surface = try wm_base.getXdgSurface(win.surface);
        win.xdg_surface.setListener(*Window, xdgSurfaceListener, win);
        win.toplevel = try win.xdg_surface.getToplevel();
        win.toplevel.setListener(*Window, toplevelListener, win);
        win.toplevel.setTitle(title);
        win.toplevel.setAppId(title);
        win.surface.commit();
        return win;
    }

    /// close를 받을 때까지 이벤트를 돈다. 그리기는 이벤트(configure · done · release · invalidate) 끝에서만 일어난다.
    pub fn run(self: *Window) !void {
        while (self.running) {
            if (self.display.dispatch() != .SUCCESS) return error.DispatchFailed;
        }
        if (self.failed) return error.DrawFailed;
    }

    /// 앱이 "다시 그려라"를 알린다. frame을 기다리는 중이면 `done`에서 그린다.
    pub fn invalidate(self: *Window) void {
        self.dirty = true;
        self.maybeDraw();
    }

    /// 버퍼 둘을 지금 크기 × 배율로 (다시) 만든다.
    fn makeBuffers(self: *Window) !void {
        const shm = self.shm.?;
        const bw = self.width * self.scale;
        const bh = self.height * self.scale;
        const stride = bw * 4;
        const size: usize = @as(usize, stride) * bh;
        for (&self.bufs, 0..) |*b, i| {
            b.destroy();
            const fd_rc = linux.memfd_create("tars-tk", linux.MFD.CLOEXEC);
            if (linux.errno(fd_rc) != .SUCCESS) return error.MemfdFailed;
            const fd: i32 = @intCast(fd_rc);
            defer _ = linux.close(fd);
            if (linux.errno(linux.ftruncate(fd, @intCast(size))) != .SUCCESS) return error.FtruncateFailed;
            const addr = linux.mmap(null, size, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, 0);
            if (linux.errno(addr) != .SUCCESS) return error.MmapFailed;
            const pool = try shm.createPool(fd, @intCast(size));
            defer pool.destroy();
            const buffer = try pool.createBuffer(0, @intCast(bw), @intCast(bh), @intCast(stride), .argb8888);
            const pixels = @as([*]u32, @ptrFromInt(addr))[0 .. size / 4];
            b.* = .{ .buffer = buffer, .pixels = pixels, .canvas = Canvas.init(pixels, bw, bh) };
            buffer.setListener(*Slot, slotRelease, &self.slots[i]);
        }
    }

    /// 그릴 때인가 보고 그린다: configure를 받았고, 바뀐 것이 있고, frame을 기다리지 않고, 빈 버퍼가 있을 때.
    fn maybeDraw(self: *Window) void {
        if (!self.configured or !self.dirty or self.frame_pending or !self.running) return;
        const b = for (&self.bufs) |*b| {
            if (b.buffer != null and !b.busy) break b;
        } else return; // 둘 다 붙어 있다 — release에서 다시 온다.

        const bw = self.width * self.scale;
        const bh = self.height * self.scale;
        const t0 = nowNs();
        self.handler.draw(self.handler.ctx, .{ .canvas = &b.canvas, .width = bw, .height = bh, .scale = self.scale }) catch |e| {
            say("error draw={s}", .{@errorName(e)});
            self.failed = true;
            self.running = false;
            return;
        };
        const us = (nowNs() - t0) / std.time.ns_per_us;
        say("draw w={d} h={d} dirty=0,0,{d},{d} us={d}", .{ bw, bh, bw, bh, us });

        // buffer_scale은 double-buffered라 이 commit에 함께 든다. 1이면 보내지 않는다(tars-wl-test와 같은 요청 순서).
        if (self.scale != 1) self.surface.setBufferScale(@intCast(self.scale));
        self.surface.attach(b.buffer.?, 0, 0);
        b.busy = true;
        self.surface.damageBuffer(0, 0, @intCast(bw), @intCast(bh));
        const cb = self.surface.frame() catch {
            self.failed = true;
            self.running = false;
            return;
        };
        cb.setListener(*Window, frameListener, self);
        self.frame_pending = true;
        self.dirty = false;
        self.surface.commit();
        self.commits += 1;
        say("commit", .{});
    }
};

fn slotRelease(_: *wl.Buffer, event: wl.Buffer.Event, slot: *Window.Slot) void {
    switch (event) {
        .release => {
            slot.win.bufs[slot.index].busy = false;
            slot.win.maybeDraw();
        },
    }
}

// ── 이벤트 ─────────────────────────────────────────────────────────

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, win: *Window) void {
    switch (event) {
        .global => |global| {
            const name = std.mem.span(global.interface);
            if (std.mem.eql(u8, name, std.mem.span(wl.Compositor.interface.name))) {
                win.compositor = registry.bind(global.name, wl.Compositor, @min(global.version, COMPOSITOR_VERSION)) catch return;
            } else if (std.mem.eql(u8, name, std.mem.span(wl.Shm.interface.name))) {
                win.shm = registry.bind(global.name, wl.Shm, @min(global.version, SHM_VERSION)) catch return;
            } else if (std.mem.eql(u8, name, std.mem.span(wl.Seat.interface.name))) {
                win.seat = registry.bind(global.name, wl.Seat, @min(global.version, SEAT_VERSION)) catch return;
            } else if (std.mem.eql(u8, name, std.mem.span(xdg.WmBase.interface.name))) {
                win.wm_base = registry.bind(global.name, xdg.WmBase, @min(global.version, WM_BASE_VERSION)) catch return;
            } else if (std.mem.eql(u8, name, std.mem.span(tars.MenuManagerV1.interface.name))) {
                win.menu_global = .{ .name = global.name, .version = global.version };
            }
        },
        .global_remove => {},
    }
}

fn wmBaseListener(wm_base: *xdg.WmBase, event: xdg.WmBase.Event, _: *Window) void {
    switch (event) {
        .ping => |p| wm_base.pong(p.serial),
    }
}

fn toplevelListener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, win: *Window) void {
    switch (event) {
        .configure => |c| {
            win.pending_w = c.width;
            win.pending_h = c.height;
        },
        .close => {
            say("close", .{});
            win.running = false;
        },
        else => {},
    }
}

/// configure 묶음의 끝. ack하고, 크기가 바뀌었거나 처음이면 버퍼를 다시 만들고 그린다. 크기가 같은 configure(activated만 바뀜)는
/// ack만 하고 그리지 않는다 — 바뀐 것이 없다(R-TKW-1).
fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, win: *Window) void {
    switch (event) {
        .configure => |c| {
            xdg_surface.ackConfigure(c.serial);
            var w = win.width;
            var h = win.height;
            if (win.pending_w > 0 and win.pending_h > 0) {
                w = @intCast(win.pending_w);
                h = @intCast(win.pending_h);
            }
            const first = !win.configured;
            if (first or w != win.width or h != win.height) {
                win.width = w;
                win.height = h;
                win.configured = true;
                say("configure w={d} h={d} scale={d}", .{ w, h, win.scale });
                rebuild(win);
            }
        },
    }
}

/// 크기나 배율이 바뀌었다 — 버퍼 둘을 다시 만들고 그린다. 붙어 있던 옛 버퍼는 지운다(서버는 지운 버퍼를 다시 읽지 않는다 —
/// tars-wl-test의 `--follow-size`가 같은 길을 쓴다). frame을 기다리던 중이면 그 `done`에서 그린다.
fn rebuild(win: *Window) void {
    win.makeBuffers() catch |e| {
        say("error buffer={s}", .{@errorName(e)});
        win.failed = true;
        win.running = false;
        return;
    };
    win.dirty = true;
    win.maybeDraw();
}

/// 서버가 알리는 배율(WY 결정 27). 바뀌면 물리 크기 버퍼로 다시.
fn surfaceListener(_: *wl.Surface, event: wl.Surface.Event, win: *Window) void {
    switch (event) {
        .preferred_buffer_scale => |p| {
            const s: u32 = if (p.factor < 1) 1 else @intCast(p.factor);
            if (s == win.scale) return;
            win.scale = s;
            if (!win.configured) return; // 첫 configure가 이 값으로 만든다.
            say("configure w={d} h={d} scale={d}", .{ win.width, win.height, s });
            rebuild(win);
        },
        else => {},
    }
}

fn frameListener(cb: *wl.Callback, event: wl.Callback.Event, win: *Window) void {
    switch (event) {
        .done => {
            cb.destroy();
            win.frame_pending = false;
            win.maybeDraw();
        },
    }
}

fn seatListener(seat: *wl.Seat, event: wl.Seat.Event, win: *Window) void {
    switch (event) {
        .capabilities => |c| {
            if (c.capabilities.keyboard and win.keyboard == null) {
                const kb = seat.getKeyboard() catch return;
                kb.setListener(*Window, keyboardListener, win);
                win.keyboard = kb;
            } else if (!c.capabilities.keyboard and win.keyboard != null) {
                win.keyboard.?.release();
                win.keyboard = null;
            }
        },
        .name => {},
    }
}

/// 키는 줄 하나와 앱의 콜백(TK-M2의 responder 전까지). 키맵 fd는 닫는다 — TK-M0은 evdev 코드만 본다.
fn keyboardListener(_: *wl.Keyboard, event: wl.Keyboard.Event, win: *Window) void {
    switch (event) {
        .keymap => |k| _ = linux.close(k.fd),
        .key => |k| {
            const pressed = k.state == .pressed;
            say("key code={d} state={d}", .{ k.key, @intFromBool(pressed) });
            if (win.handler.key) |f| f(win.handler.ctx, k.key, pressed);
        },
        else => {},
    }
}
