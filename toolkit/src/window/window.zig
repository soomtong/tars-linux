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
//! - 더티(TK-M1 plan 확정 5): 앱은 바뀐 사각형을 `invalidate(rect)`로 알린다(물리, 버퍼 좌표). 그릴 때 버퍼 나이(`age.zig`)로 이
//!   버퍼에 다시 그릴 사각형(repaint)을 셈해 `Frame.clip`으로 넘기고, 서버에는 이번 프레임의 더티(pending)만 `damage_buffer`
//!   사각형 하나로 보낸다 — 서버의 화면에는 지난 프레임이 이미 있다.
//! - 그리기는 이벤트 처리가 끝난 뒤 `run`의 루프에서만 일어난다. 그래서 `invalidate`는 적기만 하고, 앱이 콜백(키 · resize) 안에서
//!   레이어를 여러 번 바꿔도 한 프레임이 된다(그리는 중에 다시 그리기로 들어가는 일도 없다).
//!
//! 이 층은 창 층이다(R-ARCH-1의 맨 아래) — 그리는 법(CG)을 모른다. 넘기는 것은 픽셀 판 · 임시 판 · clip이고 판을 z2d로 감싸는
//! 것은 위 층의 일이다.
//!
//! 줄(design 결정 12): `tk> configure w= h= scale=` · `tk> draw w= h= dirty=x,y,w,h us= age=` (+ damage가 dirty와 다르면 ` damage=x,y,w,h`) ·
//! `tk> commit` · `tk> key code= state=` · `tk> native` · `tk> close`. `dirty=`는 이 버퍼에 다시 그린 사각형(`us`가 잰 것), `age=`는 이 버퍼가
//! 마지막으로 그려진 뒤 지난 프레임 수(새 버퍼면 0 — 통째). 표준 출력에 버퍼 없이 쓴다(게이트가 `> 파일`로 받는다 — tars-wl-test와 같다).

const std = @import("std");
const linux = std.os.linux;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const tars = wayland.client.tars;
pub const Rect = @import("tk_geom").Rect;
const Age = @import("age.zig").Age;

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

/// 그릴 판 하나. `pixels`는 ARGB8888 물리 픽셀(`width` × `height` = surface 크기 × `scale`, stride = 폭 × 4)이고 지난번 이 버퍼에
/// 그린 그림이 그대로 들어 있다. 앱은 `clip` 안만 다시 그린다 — 그 밖은 이미 맞다(버퍼 나이). `scratch`는 clip 크기의 임시 판으로
/// 쓰라고 주는 메모리다(버퍼와 같은 크기, TK-M1 plan 확정 2).
pub const Frame = struct {
    pixels: []u32,
    scratch: []u32,
    width: u32,
    height: u32,
    scale: u32,
    clip: Rect,
};

/// 앱의 콜백. `draw`는 `Frame.clip` 안을 그린다. `resize`는 버퍼 크기(물리)나 배율이 바뀔 때 그리기 전에 한 번 — 앱이 루트 레이어의
/// 크기를 맞추는 자리다(R-TKW-2). `key`는 받은 키(evdev 코드). 둘 다 없어도 된다.
pub const Handler = struct {
    ctx: *anyopaque,
    draw: *const fn (ctx: *anyopaque, frame: Frame) anyerror!void,
    resize: ?*const fn (ctx: *anyopaque, width: u32, height: u32, scale: u32) void = null,
    /// 애니메이션의 시계(TK-M1 plan 확정 6). 그릴 수 있을 때(configure 뒤, frame을 기다리지 않음, 빈 버퍼가 있음)마다 그리기 바로 앞에서
    /// monotonic 시각(ns)으로 부른다 — 그래서 값을 바꾼 tick 하나 뒤에는 늘 그림 하나가 따르고, 그 그림의 frame 콜백이 다음 tick을
    /// 부른다. 앱은 바뀐 것이 없으면 아무것도 안 하면 된다(idle commit 0).
    tick: ?*const fn (ctx: *anyopaque, now_ns: u64) void = null,
    key: ?*const fn (ctx: *anyopaque, code: u32, pressed: bool) void = null,
};

// ── 버퍼 ───────────────────────────────────────────────────────────

const Buffer = struct {
    buffer: ?*wl.Buffer = null,
    pixels: []u32 = &.{},
    busy: bool = false,
    /// 이 버퍼에 마지막으로 그린 프레임 번호(`Age.seq`). 새 버퍼면 null — 다음 그림은 통째다.
    drawn: ?u64 = null,

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
    /// clip으로 쓸 임시 판(버퍼와 같은 크기, `makeBuffers`가 잡는다).
    scratch: []u32 = &.{},
    /// 이번 프레임의 더티(물리, 버퍼 좌표). null이면 그릴 것이 없다.
    pending: ?Rect = null,
    age: Age = .{},
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

    /// 버퍼 · 임시 판 · 연결을 놓고 창을 지운다(`open`의 짝). 프로세스가 곧 끝나도 부른다 — allocator의 누수 검사(ReleaseSafe)가
    /// 끝날 때 셸에 줄을 쏟지 않게.
    pub fn deinit(self: *Window) void {
        for (&self.bufs) |*b| b.destroy();
        if (self.scratch.len != 0) self.alloc.free(self.scratch);
        self.display.disconnect();
        self.alloc.destroy(self);
    }

    /// close를 받을 때까지 이벤트를 돈다. 그리기는 이벤트 묶음(configure · done · release · 키)을 처리한 뒤 여기서만 일어난다.
    /// 그린 요청은 다음 `dispatch`가 보낸다(libwayland의 dispatch는 기다리기 전에 flush한다).
    pub fn run(self: *Window) !void {
        while (self.running) {
            self.maybeDraw();
            if (!self.running) break;
            if (self.display.dispatch() != .SUCCESS) return error.DispatchFailed;
        }
        if (self.failed) return error.DrawFailed;
    }

    /// 사각형 `r`(물리, 버퍼 좌표)이 바뀌었다. 적기만 한다 — 그리기는 `run`의 다음 바퀴(frame을 기다리는 중이면 그 `done` 뒤).
    pub fn invalidate(self: *Window, r: Rect) void {
        const whole = self.wholeRect();
        const c = Rect.intersect(r, whole) orelse return;
        self.pending = Rect.coverOpt(self.pending, c);
    }

    /// 판 전체가 바뀌었다.
    pub fn invalidateAll(self: *Window) void {
        self.pending = self.wholeRect();
    }

    fn wholeRect(self: *const Window) Rect {
        return .{ .x = 0, .y = 0, .w = @intCast(self.width * self.scale), .h = @intCast(self.height * self.scale) };
    }

    /// 버퍼 둘을 지금 크기 × 배율로 (다시) 만든다.
    fn makeBuffers(self: *Window) !void {
        const shm = self.shm.?;
        const bw = self.width * self.scale;
        const bh = self.height * self.scale;
        const stride = bw * 4;
        const size: usize = @as(usize, stride) * bh;
        if (self.scratch.len != 0) self.alloc.free(self.scratch);
        self.scratch = &.{};
        self.scratch = try self.alloc.alloc(u32, size / 4);
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
            b.* = .{ .buffer = buffer, .pixels = pixels };
            buffer.setListener(*Slot, slotRelease, &self.slots[i]);
        }
    }

    /// 그릴 때인가 보고 그린다: configure를 받았고, 바뀐 것이 있고, frame을 기다리지 않고, 빈 버퍼가 있을 때.
    fn maybeDraw(self: *Window) void {
        if (!self.configured or self.frame_pending or !self.running) return;
        const b = for (&self.bufs) |*b| {
            if (b.buffer != null and !b.busy) break b;
        } else return; // 둘 다 붙어 있다 — release 뒤 루프에서 다시 온다.
        if (self.handler.tick) |f| f(self.handler.ctx, nowNs());
        const pending = self.pending orelse return;

        const bw = self.width * self.scale;
        const bh = self.height * self.scale;
        const whole = self.wholeRect();
        const clip = self.age.repaint(b.drawn, pending, whole);
        const age: u64 = if (b.drawn) |d| self.age.seq - d else 0;
        const t0 = nowNs();
        self.handler.draw(self.handler.ctx, .{
            .pixels = b.pixels,
            .scratch = self.scratch,
            .width = bw,
            .height = bh,
            .scale = self.scale,
            .clip = clip,
        }) catch |e| {
            say("error draw={s}", .{@errorName(e)});
            self.failed = true;
            self.running = false;
            return;
        };
        const us = (nowNs() - t0) / std.time.ns_per_us;
        if (Rect.eql(clip, pending)) {
            say("draw w={d} h={d} dirty={d},{d},{d},{d} us={d} age={d}", .{ bw, bh, clip.x, clip.y, clip.w, clip.h, us, age });
        } else {
            say("draw w={d} h={d} dirty={d},{d},{d},{d} us={d} age={d} damage={d},{d},{d},{d}", .{ bw, bh, clip.x, clip.y, clip.w, clip.h, us, age, pending.x, pending.y, pending.w, pending.h });
        }
        b.drawn = self.age.record(pending);
        self.pending = null;

        // buffer_scale은 double-buffered라 이 commit에 함께 든다. 1이면 보내지 않는다(tars-wl-test와 같은 요청 순서).
        if (self.scale != 1) self.surface.setBufferScale(@intCast(self.scale));
        self.surface.attach(b.buffer.?, 0, 0);
        b.busy = true;
        self.surface.damageBuffer(pending.x, pending.y, pending.w, pending.h);
        const cb = self.surface.frame() catch {
            self.failed = true;
            self.running = false;
            return;
        };
        cb.setListener(*Window, frameListener, self);
        self.frame_pending = true;
        self.surface.commit();
        self.commits += 1;
        say("commit", .{});
    }
};

fn slotRelease(_: *wl.Buffer, event: wl.Buffer.Event, slot: *Window.Slot) void {
    switch (event) {
        .release => slot.win.bufs[slot.index].busy = false,
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

/// 크기나 배율이 바뀌었다 — 버퍼 둘을 다시 만들고(새 버퍼라 다음 둘은 통째) 앱의 `resize`를 부른 뒤 전체를 더티로. 붙어 있던 옛
/// 버퍼는 지운다(서버는 지운 버퍼를 다시 읽지 않는다 — tars-wl-test의 `--follow-size`가 같은 길을 쓴다). 그리기는 `run`의 다음
/// 바퀴(frame을 기다리던 중이면 그 `done` 뒤).
fn rebuild(win: *Window) void {
    win.makeBuffers() catch |e| {
        say("error buffer={s}", .{@errorName(e)});
        win.failed = true;
        win.running = false;
        return;
    };
    if (win.handler.resize) |f| f(win.handler.ctx, win.width * win.scale, win.height * win.scale, win.scale);
    win.invalidateAll();
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
