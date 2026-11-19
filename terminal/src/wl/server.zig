//! WY-M0: terminal 안의 Wayland 서버(WY design 결정 1 · 3 · 4 · 5 · 6 · 9 · 10 · 12, plan 확정 4 · 5 · 8 · 9 · 12).
//!
//! `main.zig`는 이 파일의 `Server` 하나를 들고 셋만 한다 — `poll`의 칸 하나(`fd`), 깨면 `dispatch`와 `takeEvents`,
//! 그린 뒤 `presented`. 서버는 App을 모른다. 일어난 일은 `Event`로 쌓고 App이 바퀴마다 꺼내 workspace를
//! 만들고 지운다. App도 서버의 객체를 쥐지 않는다 — toplevel을 번호(`id`)로만 부르므로, 클라이언트가 먼저
//! 끝나 객체가 사라져도 App 쪽에 매달린 포인터가 없다.
//!
//! 순수한 셈(배율 · 옮기기 · configure 순서)은 `wl_logic.zig`에 있다. 여기는 libwayland의 객체와 시스템 콜이다.
//!
//! 버퍼는 commit 때 복사하지 않는다(확정 8). 그릴 때 클라이언트의 shm에서 바로 읽고, 새 버퍼가 그 자리를 넘겨받을
//! 때 옛 것에 `release`를 보낸다 — 복사하지 않으므로 화면에 있는 동안은 쥐고 있어야 다시 그릴 수 있다(workspace를
//! 오가면 통째로 다시 그린다). weston의 pixman 렌더러와 같은 수명이다.

const std = @import("std");
const linux = std.os.linux;
const wayland = @import("wayland");
const wl = wayland.server.wl;
const xdg = wayland.server.xdg;
const logic = @import("../wl_logic.zig");
const logline = @import("../logline.zig");

/// 내는 global의 판(WY design 결정 5 — 구현한 요청이 다 되는 가장 낮은 판). `wl_shm`은 libwayland가 직접
/// 낸다(`wl_display_init_shm`, ARGB8888 · XRGB8888 둘).
const COMPOSITOR_VERSION = 4;
const OUTPUT_VERSION = 4;
const SEAT_VERSION = 7;
const WM_BASE_VERSION = 5;

/// 키 반복(design 결정 6 — terminal의 반복 설정과 같은 값). terminal은 반복을 스스로 안 하고 커널 evdev의
/// 자동 반복을 받는다. 그 기본값이 지연 250ms · 간격 33ms(초당 약 30)이다.
const REPEAT_RATE = 30;
const REPEAT_DELAY = 250;

/// 키맵 텍스트(design 결정 6, `build.zig`의 `keymap` — 만든 명령과 판은 그 주석에). 텍스트는 고치지 않는다.
const KEYMAP = @embedFile("keymap");

/// memfd와 봉인. Zig의 std에 이름이 없는 것만 여기 둔다(값은 linux/memfd.h · linux/fcntl.h).
const MFD_CLOEXEC = 0x1;
const MFD_ALLOW_SEALING = 0x2;
const F_ADD_SEALS = 1033;
const F_SEAL_SHRINK = 0x2;
const F_SEAL_GROW = 0x4;
const F_SEAL_WRITE = 0x8;

/// App이 바퀴마다 꺼내는 일(`takeEvents`).
pub const Event = union(enum) {
    /// toplevel이 생겼다 — App이 끝에 workspace를 만들거나, 아홉이면 `refuse`한다.
    toplevel: u32,
    /// toplevel이 사라졌다(클라이언트가 지웠거나 끝났다) — 그 workspace가 닫힌다.
    gone: u32,
    /// 보이는 내용이 바뀌었거나 frame 콜백을 기다린다 — 그 workspace가 앞이면 다시 그린다.
    commit: u32,
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    display: *wl.Server,
    loop: *wl.EventLoop,
    /// 화면(논리) 크기. configure의 크기와 `wl_output`의 mode가 이것이다.
    fb_w: u32,
    fb_h: u32,
    /// 봉인한 키맵 memfd(design 결정 6). 모든 클라이언트에 같은 fd를 준다 — libwayland가 보낼 때 복제한다.
    keymap_fd: i32,
    keymap_size: u32,
    next_id: u32 = 1,
    toplevels: std.ArrayList(*Toplevel) = .empty,
    events: std.ArrayList(Event) = .empty,
    /// 모든 `wl_keyboard`(단계 C가 키를 보낸다).
    keyboards: wl.list.Head(wl.Keyboard, null) = undefined,
    client_created: wl.Listener(*wl.Client) = .init(clientCreated),

    /// 소켓을 연다(design 결정 3, 확정 4). `/run/user/<uid>`(0700, 그 계정의 것)를 만들고 `XDG_RUNTIME_DIR`을 거기로
    /// 둔 뒤 `wayland-0`을 열고, 소켓과 lock의 주인을 계정으로 바꾼다. 성공하면 `WAYLAND_DISPLAY=wayland-0`도 둔다 —
    /// 이 둘이 셸 자식의 환경에 들어간다(부르는 쪽이 셸을 띄우기 전에 부른다). 실패하면 둘을 지우고 에러다.
    ///
    /// `Server`는 heap에 있다 — listener가 libwayland의 목록에 들어가므로 자리가 움직이면 안 된다.
    pub fn start(allocator: std.mem.Allocator, uid: u32, gid: u32, fb_w: u32, fb_h: u32) !*Server {
        var dir_buf: [32]u8 = undefined;
        const dir = try std.fmt.bufPrintSentinel(&dir_buf, "/run/user/{d}", .{uid}, 0);
        _ = std.c.mkdir("/run/user", 0o755);
        if (std.c.mkdir(dir, 0o700) != 0 and std.c.errno(-1) != .EXIST) return error.MkdirFailed;
        if (chown(dir, uid, gid) != 0) return error.ChownFailed;
        if (chmod(dir, 0o700) != 0) return error.ChmodFailed;
        // libwayland은 소켓 이름을 `XDG_RUNTIME_DIR` 아래에 만든다. 셸 자식도 같은 값을 받는다.
        if (setenv("XDG_RUNTIME_DIR", dir, 1) != 0) return error.SetenvFailed;
        errdefer _ = unsetenv("XDG_RUNTIME_DIR");

        const display = try wl.Server.create();
        errdefer display.destroy();
        // zig-wayland의 `addSocketAuto`는 일부러 wayland-0을 건너뛴다(확인 1). R-WY-3은 wayland-0이다.
        try display.addSocket("wayland-0");
        for ([_][]const u8{ "wayland-0", "wayland-0.lock" }) |name| {
            var p: [64]u8 = undefined;
            const path = try std.fmt.bufPrintSentinel(&p, "{s}/{s}", .{ dir, name }, 0);
            if (chown(path, uid, gid) != 0) return error.ChownFailed;
        }
        try display.initShm();

        const kfd = try makeKeymap();
        errdefer _ = linux.close(kfd);

        const self = try allocator.create(Server);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .display = display,
            .loop = display.getEventLoop(),
            .fb_w = fb_w,
            .fb_h = fb_h,
            .keymap_fd = kfd,
            .keymap_size = @intCast(KEYMAP.len + 1),
        };
        self.keyboards.init();
        display.addClientCreatedListener(&self.client_created);
        _ = try wl.Global.create(display, wl.Compositor, COMPOSITOR_VERSION, *Server, self, bindCompositor);
        _ = try wl.Global.create(display, wl.Output, OUTPUT_VERSION, *Server, self, bindOutput);
        _ = try wl.Global.create(display, wl.Seat, SEAT_VERSION, *Server, self, bindSeat);
        _ = try wl.Global.create(display, xdg.WmBase, WM_BASE_VERSION, *Server, self, bindWmBase);

        if (setenv("WAYLAND_DISPLAY", "wayland-0", 1) != 0) return error.SetenvFailed;
        logline.print("terminal: wl> listen path={s}/wayland-0\n", .{dir});
        return self;
    }

    /// `poll`에 넣을 fd(이벤트 루프의 epoll fd — 확인 4).
    pub fn fd(self: *const Server) i32 {
        return self.loop.getFd();
    }

    /// 깨었을 때 한 번. 기다리지 않는다.
    pub fn dispatch(self: *Server) void {
        self.loop.dispatch(0) catch {};
    }

    /// 바퀴 끝에 한 번(결정 4). 이 바퀴에 쌓인 이벤트(configure · frame done · release)를 내보낸다.
    pub fn flush(self: *Server) void {
        self.display.flushClients();
    }

    /// 쌓인 일을 꺼낸다. 돌려준 조각은 다음 `dispatch`까지 유효하다.
    pub fn takeEvents(self: *Server) []const Event {
        const out = self.events.items;
        self.events.items.len = 0;
        return out;
    }

    fn push(self: *Server, e: Event) void {
        self.events.append(self.allocator, e) catch logline.print("terminal: wl> event dropped (no memory)\n", .{});
    }

    fn find(self: *Server, id: u32) ?*Toplevel {
        for (self.toplevels.items) |t| if (t.id == id) return t;
        return null;
    }

    /// workspace가 아홉이라 받을 자리가 없다(확정 12) — close를 보낸다.
    pub fn refuse(self: *Server, id: u32) void {
        const t = self.find(id) orelse return;
        t.resource.sendClose();
        logline.print("terminal: wl> toplevel refused id={d}\n", .{id});
    }

    /// toplevel `id`의 버퍼를 프레임버퍼에 옮긴다(확정 8). 그린 사각형을 돌려준다. 버퍼가 없거나 받지 않는
    /// 형식이면 null이다 — 그 자리는 부르는 쪽이 검정으로 둔다.
    pub fn paint(self: *Server, id: u32, dst: [*]u8, pitch: u32, fb_w: u32, fb_h: u32) ?logic.Fit {
        const t = self.find(id) orelse return null;
        const xs = t.xdg orelse return null;
        const s = xs.surface orelse return null;
        const buf = s.current orelse return null;
        const shm = wl.shm.Buffer.get(@ptrCast(buf)) orelse return null;
        if (!logic.formatOk(shm.getFormat())) return null;
        const w: u32 = @intCast(shm.getWidth());
        const h: u32 = @intCast(shm.getHeight());
        const f = logic.fit(fb_w, fb_h, w, h) orelse return null;
        // 클라이언트가 풀을 줄였으면 읽기가 SIGBUS다 — libwayland이 그 틈을 막는다(begin · end).
        shm.beginAccess();
        defer shm.endAccess();
        const data: [*]const u8 = @ptrCast(shm.getData() orelse return null);
        logic.blit(dst, pitch, f, data, @intCast(shm.getStride()));
        return f;
    }

    /// toplevel `id`가 든 프레임을 화면에 냈다(확정 9) — 그 commit들의 frame 콜백에 `done`을 보낸다.
    pub fn presented(self: *Server, id: u32, ms: u32) void {
        const t = self.find(id) orelse return;
        const xs = t.xdg orelse return;
        const s = xs.surface orelse return;
        var it = s.frames.safeIterator(.forward);
        while (it.next()) |cb| cb.destroySendDone(ms);
    }
};

/// 봉인한 memfd 하나에 키맵 텍스트와 NUL을 쓴다(design 결정 6). 크기는 NUL까지다 — 클라이언트(libxkbcommon)가
/// 문자열로 읽는다.
fn makeKeymap() !i32 {
    const rc = linux.memfd_create("tars-keymap", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (linux.errno(rc) != .SUCCESS) return error.MemfdFailed;
    const kfd: i32 = @intCast(rc);
    errdefer _ = linux.close(kfd);
    for ([_][]const u8{ KEYMAP, "\x00" }) |part| {
        var off: usize = 0;
        while (off < part.len) {
            const n = linux.write(kfd, part[off..].ptr, part.len - off);
            if (linux.errno(n) != .SUCCESS) return error.KeymapWriteFailed;
            off += n;
        }
    }
    if (linux.errno(linux.fcntl(kfd, F_ADD_SEALS, F_SEAL_SHRINK | F_SEAL_GROW | F_SEAL_WRITE)) != .SUCCESS)
        return error.SealFailed;
    return kfd;
}

extern "c" fn chown(path: [*:0]const u8, owner: u32, group: u32) c_int;
extern "c" fn chmod(path: [*:0]const u8, mode: c_uint) c_int;
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

// ── 클라이언트 ─────────────────────────────────────────────────────────

const ClientRec = struct {
    srv: *Server,
    pid: i32,
    destroy: wl.Listener(*wl.Client) = .init(clientGone),
};

fn clientCreated(listener: *wl.Listener(*wl.Client), client: *wl.Client) void {
    const srv: *Server = @fieldParentPtr("client_created", listener);
    const pid = client.getCredentials().pid;
    logline.print("terminal: wl> client pid={d}\n", .{pid});
    const rec = srv.allocator.create(ClientRec) catch return;
    rec.* = .{ .srv = srv, .pid = pid };
    client.addDestroyListener(&rec.destroy);
}

fn clientGone(listener: *wl.Listener(*wl.Client), _: *wl.Client) void {
    const rec: *ClientRec = @fieldParentPtr("destroy", listener);
    logline.print("terminal: wl> gone pid={d}\n", .{rec.pid});
    listener.link.remove();
    rec.srv.allocator.destroy(rec);
}

// ── wl_compositor · wl_region ──────────────────────────────────────────

fn bindCompositor(client: *wl.Client, srv: *Server, version: u32, id: u32) void {
    const r = wl.Compositor.create(client, version, id) catch return client.postNoMemory();
    r.setHandler(*Server, compositorRequest, null, srv);
}

fn compositorRequest(comp: *wl.Compositor, req: wl.Compositor.Request, srv: *Server) void {
    const client = comp.getClient();
    switch (req) {
        .create_surface => |r| {
            const res = wl.Surface.create(client, comp.getVersion(), r.id) catch return comp.postNoMemory();
            const s = srv.allocator.create(Surface) catch {
                res.destroy();
                return comp.postNoMemory();
            };
            s.* = .{ .srv = srv, .resource = res };
            s.pending_frames.init();
            s.frames.init();
            res.setHandler(*Surface, surfaceRequest, surfaceDestroyed, s);
        },
        .create_region => |r| {
            const res = wl.Region.create(client, comp.getVersion(), r.id) catch return comp.postNoMemory();
            res.setHandler(?*anyopaque, regionRequest, null, null);
        },
    }
}

/// 영역은 받기만 한다 — opaque · input 영역을 아직 안 쓴다(합성이 통째 blit이고 포인터는 M2).
fn regionRequest(region: *wl.Region, req: wl.Region.Request, _: ?*anyopaque) void {
    switch (req) {
        .destroy => region.destroy(),
        .add, .subtract => {},
    }
}

// ── wl_surface ─────────────────────────────────────────────────────────

const Surface = struct {
    srv: *Server,
    resource: *wl.Surface,
    /// attach가 둔 버퍼(commit 전). `pending_set`이면 attach가 있었다(null 버퍼도 attach다).
    pending: ?*wl.Buffer = null,
    pending_set: bool = false,
    pending_gone: wl.Listener(*wl.Resource) = .init(pendingGone),
    pending_linked: bool = false,
    /// 보이는 버퍼(commit된 것). 새 버퍼가 넘겨받을 때 `release`를 보낸다.
    current: ?*wl.Buffer = null,
    current_gone: wl.Listener(*wl.Resource) = .init(currentGone),
    current_linked: bool = false,
    /// frame 콜백(확정 9). commit이 `pending_frames`를 `frames`로 옮기고, 그 commit을 담은 프레임을 낸 뒤
    /// `presented`가 `done`을 보낸다. 목록은 resource의 link로 든다 — 콜백이 먼저 사라지면 그 destroy가 스스로
    /// 목록에서 빠진다(`frameDestroyed`).
    pending_frames: wl.list.Head(wl.Callback, null) = undefined,
    frames: wl.list.Head(wl.Callback, null) = undefined,
    role: ?*XdgSurface = null,
};

fn surfaceRequest(res: *wl.Surface, req: wl.Surface.Request, s: *Surface) void {
    switch (req) {
        .destroy => res.destroy(),
        .attach => |a| {
            if (s.pending_linked) {
                s.pending_gone.link.remove();
                s.pending_linked = false;
            }
            s.pending = a.buffer;
            s.pending_set = true;
            if (a.buffer) |b| {
                @as(*wl.Resource, @ptrCast(b)).addDestroyListener(&s.pending_gone);
                s.pending_linked = true;
            }
        },
        .frame => |f| {
            const cb = wl.Callback.create(res.getClient(), 1, f.callback) catch return res.postNoMemory();
            cb.setHandler(?*anyopaque, frameDestroyed, null);
            s.pending_frames.append(cb);
        },
        .commit => commit(s),
        // damage는 아직 안 본다 — 통째 blit이다(부분 blit은 M5, R-WY-10).
        .damage, .damage_buffer, .set_opaque_region, .set_input_region, .set_buffer_transform, .set_buffer_scale => {},
    }
}

fn frameDestroyed(cb: *wl.Callback, _: ?*anyopaque) void {
    cb.getLink().remove();
}

fn pendingGone(listener: *wl.Listener(*wl.Resource), _: *wl.Resource) void {
    const s: *Surface = @fieldParentPtr("pending_gone", listener);
    listener.link.remove();
    s.pending_linked = false;
    s.pending = null;
}

fn currentGone(listener: *wl.Listener(*wl.Resource), _: *wl.Resource) void {
    const s: *Surface = @fieldParentPtr("current_gone", listener);
    listener.link.remove();
    s.current_linked = false;
    s.current = null;
}

fn commit(s: *Surface) void {
    var changed = false;
    if (s.pending_set) {
        const next = s.pending;
        if (s.pending_linked) {
            s.pending_gone.link.remove();
            s.pending_linked = false;
        }
        s.pending = null;
        s.pending_set = false;
        if (next != s.current) {
            if (s.current) |old| {
                s.current_gone.link.remove();
                s.current_linked = false;
                old.sendRelease();
            }
            s.current = next;
            if (next) |b| {
                @as(*wl.Resource, @ptrCast(b)).addDestroyListener(&s.current_gone);
                s.current_linked = true;
            }
            changed = true;
        }
    }
    const waiting = !s.pending_frames.empty();
    s.frames.appendList(&s.pending_frames);

    const xs = s.role orelse return;
    const t = xs.toplevel orelse return;
    const step = logic.onCommit(xs.phase, xs.acked, s.current != null);
    switch (step.action) {
        .unconfigured_buffer => return xs.resource.postError(.unconfigured_buffer, "buffer before the first ack_configure"),
        .send_configure => sendConfigure(t),
        .wait => {},
        .map, .update => {
            if (changed) logCommit(t, s);
            if (changed or waiting) s.srv.push(.{ .commit = t.id });
        },
    }
    xs.phase = step.next;
}

/// `wl> commit` 줄(확정 5) — 버퍼 크기나 놓는 자리가 바뀔 때만.
fn logCommit(t: *Toplevel, s: *Surface) void {
    const buf = s.current orelse return;
    const shm = wl.shm.Buffer.get(@ptrCast(buf)) orelse return;
    const f = logic.fit(s.srv.fb_w, s.srv.fb_h, @intCast(shm.getWidth()), @intCast(shm.getHeight())) orelse return;
    const sig: Toplevel.Sig = .{ .w = shm.getWidth(), .h = shm.getHeight(), .fit = f };
    if (t.last) |l| if (std.meta.eql(l, sig)) return;
    t.last = sig;
    logline.print("terminal: wl> commit id={d} buf={d}x{d} scale={d} at={d},{d}\n", .{ t.id, sig.w, sig.h, f.k, f.x, f.y });
}

fn surfaceDestroyed(_: *wl.Surface, s: *Surface) void {
    if (s.pending_linked) s.pending_gone.link.remove();
    if (s.current_linked) s.current_gone.link.remove();
    // 남은 콜백은 아직 살아 있다(먼저 사라졌으면 스스로 빠졌다). 같이 지운다.
    var it = s.pending_frames.safeIterator(.forward);
    while (it.next()) |cb| cb.destroy();
    var it2 = s.frames.safeIterator(.forward);
    while (it2.next()) |cb| cb.destroy();
    if (s.role) |xs| xs.surface = null;
    s.srv.allocator.destroy(s);
}

// ── wl_output ──────────────────────────────────────────────────────────

fn bindOutput(client: *wl.Client, srv: *Server, version: u32, id: u32) void {
    const o = wl.Output.create(client, version, id) catch return client.postNoMemory();
    o.setHandler(?*anyopaque, outputRequest, null, null);
    o.sendGeometry(0, 0, 0, 0, .unknown, "TARS", "framebuffer", .normal);
    o.sendMode(.{ .current = true, .preferred = true }, @intCast(srv.fb_w), @intCast(srv.fb_h), 60000);
    if (version >= 2) o.sendScale(1);
    if (version >= 4) {
        o.sendName("TARS-1");
        o.sendDescription("TARS framebuffer");
    }
    if (version >= 2) o.sendDone();
}

fn outputRequest(o: *wl.Output, req: wl.Output.Request, _: ?*anyopaque) void {
    switch (req) {
        .release => o.destroy(),
    }
}

// ── wl_seat · wl_keyboard ──────────────────────────────────────────────

fn bindSeat(client: *wl.Client, srv: *Server, version: u32, id: u32) void {
    const seat = wl.Seat.create(client, version, id) catch return client.postNoMemory();
    seat.setHandler(*Server, seatRequest, null, srv);
    seat.sendCapabilities(.{ .keyboard = true });
    if (version >= 2) seat.sendName("seat0");
}

fn seatRequest(seat: *wl.Seat, req: wl.Seat.Request, srv: *Server) void {
    const client = seat.getClient();
    switch (req) {
        .get_keyboard => |r| {
            const kb = wl.Keyboard.create(client, seat.getVersion(), r.id) catch return seat.postNoMemory();
            kb.setHandler(?*anyopaque, keyboardRequest, keyboardDestroyed, null);
            srv.keyboards.append(kb);
            kb.sendKeymap(.xkb_v1, srv.keymap_fd, srv.keymap_size);
            if (seat.getVersion() >= 4) kb.sendRepeatInfo(REPEAT_RATE, REPEAT_DELAY);
        },
        // 포인터 · 터치는 아직 없다(capabilities에 없다). 그래도 묻는 클라이언트에게 아무 일도 안 하는 객체를 준다 —
        // 오류로 끊는 것보다 너그럽다. `wl_pointer`는 M2다.
        .get_pointer => |r| {
            const p = wl.Pointer.create(client, seat.getVersion(), r.id) catch return seat.postNoMemory();
            p.setHandler(?*anyopaque, pointerRequest, null, null);
        },
        .get_touch => |r| {
            const t = wl.Touch.create(client, seat.getVersion(), r.id) catch return seat.postNoMemory();
            t.setHandler(?*anyopaque, touchRequest, null, null);
        },
        .release => seat.destroy(),
    }
}

fn keyboardRequest(kb: *wl.Keyboard, req: wl.Keyboard.Request, _: ?*anyopaque) void {
    switch (req) {
        .release => kb.destroy(),
    }
}

fn keyboardDestroyed(kb: *wl.Keyboard, _: ?*anyopaque) void {
    kb.getLink().remove();
}

fn pointerRequest(p: *wl.Pointer, req: wl.Pointer.Request, _: ?*anyopaque) void {
    switch (req) {
        .release => p.destroy(),
        .set_cursor => {},
    }
}

fn touchRequest(t: *wl.Touch, req: wl.Touch.Request, _: ?*anyopaque) void {
    switch (req) {
        .release => t.destroy(),
    }
}

// ── xdg_wm_base · xdg_positioner ───────────────────────────────────────

fn bindWmBase(client: *wl.Client, srv: *Server, version: u32, id: u32) void {
    const wm = xdg.WmBase.create(client, version, id) catch return client.postNoMemory();
    wm.setHandler(*Server, wmBaseRequest, null, srv);
}

fn wmBaseRequest(wm: *xdg.WmBase, req: xdg.WmBase.Request, srv: *Server) void {
    const client = wm.getClient();
    switch (req) {
        .destroy => wm.destroy(),
        .create_positioner => |r| {
            const p = xdg.Positioner.create(client, wm.getVersion(), r.id) catch return wm.postNoMemory();
            p.setHandler(?*anyopaque, positionerRequest, null, null);
        },
        .get_xdg_surface => |r| {
            const s: *Surface = @ptrCast(@alignCast(r.surface.getUserData() orelse return));
            if (s.role != null) return wm.postError(.role, "wl_surface already has a role");
            const res = xdg.Surface.create(client, wm.getVersion(), r.id) catch return wm.postNoMemory();
            const xs = srv.allocator.create(XdgSurface) catch {
                res.destroy();
                return wm.postNoMemory();
            };
            xs.* = .{ .srv = srv, .resource = res, .surface = s };
            s.role = xs;
            res.setHandler(*XdgSurface, xdgSurfaceRequest, xdgSurfaceDestroyed, xs);
        },
        // 단계 C(확정 11)가 pong으로 응답 없는 클라이언트를 가린다.
        .pong => {},
    }
}

/// popup의 자리 셈은 M5(R-WY-14)다. 받기만 한다.
fn positionerRequest(p: *xdg.Positioner, req: xdg.Positioner.Request, _: ?*anyopaque) void {
    switch (req) {
        .destroy => p.destroy(),
        else => {},
    }
}

// ── xdg_surface · xdg_toplevel ─────────────────────────────────────────

const XdgSurface = struct {
    srv: *Server,
    resource: *xdg.Surface,
    surface: ?*Surface,
    toplevel: ?*Toplevel = null,
    phase: logic.Phase = .fresh,
    acked: bool = false,
};

const Toplevel = struct {
    srv: *Server,
    id: u32,
    resource: *xdg.Toplevel,
    xdg: ?*XdgSurface,
    /// 마지막 `wl> commit` 줄의 값.
    last: ?Sig = null,

    const Sig = struct { w: i32, h: i32, fit: logic.Fit };
};

fn xdgSurfaceRequest(res: *xdg.Surface, req: xdg.Surface.Request, xs: *XdgSurface) void {
    const client = res.getClient();
    switch (req) {
        .destroy => res.destroy(),
        .get_toplevel => |r| {
            if (xs.toplevel != null) return res.postError(.already_constructed, "xdg_surface already has a toplevel");
            const tr = xdg.Toplevel.create(client, res.getVersion(), r.id) catch return res.postNoMemory();
            const t = xs.srv.allocator.create(Toplevel) catch {
                tr.destroy();
                return res.postNoMemory();
            };
            t.* = .{ .srv = xs.srv, .id = xs.srv.next_id, .resource = tr, .xdg = xs };
            xs.srv.toplevels.append(xs.srv.allocator, t) catch {
                xs.srv.allocator.destroy(t);
                tr.destroy();
                return res.postNoMemory();
            };
            xs.srv.next_id += 1;
            xs.toplevel = t;
            tr.setHandler(*Toplevel, toplevelRequest, toplevelDestroyed, t);
            xs.srv.push(.{ .toplevel = t.id });
        },
        // popup은 M5(R-WY-14). 만들자마자 닫혔다고 알린다.
        .get_popup => |r| {
            const p = xdg.Popup.create(client, res.getVersion(), r.id) catch return res.postNoMemory();
            p.setHandler(?*anyopaque, popupRequest, null, null);
            p.sendPopupDone();
        },
        .set_window_geometry => {},
        .ack_configure => {
            xs.acked = true;
        },
    }
}

fn popupRequest(p: *xdg.Popup, req: xdg.Popup.Request, _: ?*anyopaque) void {
    switch (req) {
        .destroy => p.destroy(),
        .grab, .reposition => {},
    }
}

fn xdgSurfaceDestroyed(_: *xdg.Surface, xs: *XdgSurface) void {
    if (xs.surface) |s| s.role = null;
    if (xs.toplevel) |t| t.xdg = null;
    xs.srv.allocator.destroy(xs);
}

/// 처음이자 유일한 configure(확정 4 — 풀스크린 = 자기 workspace). 크기는 화면, 상태는 fullscreen과 activated다.
/// 장식은 없다(app workspace는 늘 chrome 없음).
fn sendConfigure(t: *Toplevel) void {
    const xs = t.xdg orelse return;
    if (t.resource.getVersion() >= 5) {
        var caps = [_]u32{@intCast(@backingInt(xdg.Toplevel.WmCapabilities.fullscreen))};
        var arr: wl.Array = .{ .size = @sizeOf(@TypeOf(caps)), .alloc = @sizeOf(@TypeOf(caps)), .data = &caps };
        t.resource.sendWmCapabilities(&arr);
    }
    var states = [_]u32{
        @intCast(@backingInt(xdg.Toplevel.State.fullscreen)),
        @intCast(@backingInt(xdg.Toplevel.State.activated)),
    };
    var arr: wl.Array = .{ .size = @sizeOf(@TypeOf(states)), .alloc = @sizeOf(@TypeOf(states)), .data = &states };
    t.resource.sendConfigure(@intCast(t.srv.fb_w), @intCast(t.srv.fb_h), &arr);
    xs.resource.sendConfigure(t.srv.display.nextSerial());
}

/// 창 메뉴 · 옮기기 · 크기 · 최대화 · 최소화 · 전체 화면 요청은 받기만 한다 — 창은 늘 자기 workspace를
/// 채운다(확정 4). 제목과 app id는 아직 안 쓴다.
fn toplevelRequest(res: *xdg.Toplevel, req: xdg.Toplevel.Request, _: *Toplevel) void {
    switch (req) {
        .destroy => res.destroy(),
        else => {},
    }
}

fn toplevelDestroyed(_: *xdg.Toplevel, t: *Toplevel) void {
    const srv = t.srv;
    if (t.xdg) |xs| xs.toplevel = null;
    for (srv.toplevels.items, 0..) |x, i| if (x == t) {
        _ = srv.toplevels.swapRemove(i);
        break;
    };
    srv.push(.{ .gone = t.id });
    srv.allocator.destroy(t);
}
