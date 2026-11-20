//! WY-M0: terminal 안의 Wayland 서버(WY design 결정 1 · 3 · 4 · 5 · 6 · 9 · 10 · 12, plan 확정 4 · 5 · 8 · 9 · 12).
//!
//! `main.zig`는 이 파일의 `Server` 하나를 들고 셋만 한다 — `poll`의 칸 하나(`fd`), 깨면 `dispatch`와 `takeEvents`,
//! 그린 뒤 `presented`. 서버는 App을 모른다. 일어난 일은 `Event`로 쌓고 App이 바퀴마다 꺼내 workspace를
//! 만들고 지운다. App도 서버의 객체를 쥐지 않는다 — toplevel을 번호(`id`)로만 부르므로, 클라이언트가 먼저
//! 끝나 객체가 사라져도 App 쪽에 매달린 포인터가 없다.
//!
//! 순수한 셈(배율 · 옮기기 · configure 순서)은 `wl_logic.zig`에 있다. 여기는 libwayland의 객체와 시스템 콜이다.
//!
//! 키(단계 C, 확정 10)는 포커스 창 하나에 간다 — App이 바퀴마다 `setFocus`로 앞 workspace의 창을 알리고, 서버가
//! 그 클라이언트의 `wl_keyboard`에 `leave` · `enter`(빈 키 목록) · `key` · `modifiers`를 보낸다. `Cmd+Q`(확정 11)는
//! `close` + `ping`과 2초 기한이다 — 기한은 `poll`의 시간 제한으로 건다(`timeout` · `expire`).
//!
//! 버퍼는 commit 때 복사하지 않는다(확정 8). 그릴 때 클라이언트의 shm에서 바로 읽고, 새 버퍼가 그 자리를 넘겨받을
//! 때 옛 것에 `release`를 보낸다 — 복사하지 않으므로 화면에 있는 동안은 쥐고 있어야 다시 그릴 수 있다(workspace를
//! 오가면 통째로 다시 그린다). weston의 pixman 렌더러와 같은 수명이다.

const std = @import("std");
const linux = std.os.linux;
const wayland = @import("wayland");
const wl = wayland.server.wl;
const xdg = wayland.server.xdg;
const zxdg = wayland.server.zxdg;
const logic = @import("../wl_logic.zig");
const logline = @import("../logline.zig");

/// 내는 global의 판(WY design 결정 5 — 구현한 요청이 다 되는 가장 낮은 판). `wl_shm`은 libwayland가 직접
/// 낸다(`wl_display_init_shm`, ARGB8888 · XRGB8888 둘). compositor는 WY-M3에서 6이다(design 결정 27) — surface 판 6의
/// `preferred_buffer_scale`로 배율을 알린다. 판 5의 `offset`도 함께 생긴다(받아서 버린다, 결정 28).
const COMPOSITOR_VERSION = 6;
const OUTPUT_VERSION = 4;
const SEAT_VERSION = 7;
const WM_BASE_VERSION = 5;
/// 장식 관리자(WY-M2, design 결정 25). 판 1뿐이다.
const DECORATION_VERSION = 1;
/// 클립보드(WY-M4, design 결정 32). 판 2 — 판 3의 새 요청은 전부 drag-and-drop 액션이다.
const DATA_DEVICE_MANAGER_VERSION = 2;

/// 파이프의 깃발(값은 asm-generic/fcntl.h — x86_64도 같다). 받기의 읽기 끝만 비블록이다 — epoll이 깨운 만큼만 읽는다.
/// `pipe2`에 O_NONBLOCK을 주면 클라이언트가 받는 쓰기 끝까지 비블록이 되어, EAGAIN을 다루지 않는 클라이언트가 64 KiB를
/// 넘는 글을 조용히 잘라 쓴다. 그래서 쓰기 끝은 보통 파이프로 두고 읽기 끝에만 `F_SETFL`로 건다.
const O_NONBLOCK: usize = 0o4000;
const O_CLOEXEC: c_int = 0o2000000;
const F_SETFL = 4;
const F_GETFL = 3;

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
    /// toplevel이 첫 commit을 했다(WY-M2 확정 3) — App이 자리를 정해 `placeWorkspace`나 `placeColumn`을 부르거나, 자리가
    /// 없으면 `refuse`한다. 만들 때가 아니라 첫 commit 때 내는 것은 `set_fullscreen`이 그 사이에 오기 때문이다(xdg-shell:
    /// 클라이언트는 역할을 만든 뒤 상태를 정하고 첫 commit으로 configure를 청한다). 둠은 그렇게 자기 workspace를 고른다.
    toplevel: Opened,
    /// toplevel이 사라졌다(클라이언트가 지웠거나 끝났다) — 그 workspace가 닫힌다.
    gone: u32,
    /// 보이는 내용이 바뀌었거나 frame 콜백을 기다린다 — 그 workspace가 앞이면 다시 그린다.
    commit: u32,
    /// 클라이언트의 selection을 서버 사본으로 다 받았다(WY-M4, design 결정 33). App이 `clipboard()`를 읽어
    /// `clipboard=shared`면 셸 클립보드에 넣는다(결정 37). 바이트를 싣지 않는 것은 사본의 주인이 서버라서다 — App은
    /// 꺼낸 그 바퀴에 복사한다.
    selection,
};

/// 첫 commit에 정해진 것(`Event.toplevel`).
pub const Opened = struct {
    id: u32,
    /// 첫 commit 전에 `set_fullscreen`을 받았다(design 결정 21).
    fullscreen: bool,
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    display: *wl.Server,
    loop: *wl.EventLoop,
    /// 화면(논리) 크기. configure의 크기가 이것이다.
    fb_w: u32,
    fb_h: u32,
    /// 물리 크기와 HS 배율(WY-M3, design 결정 27). `wl_output`의 mode · scale과 surface의 `preferred_buffer_scale`이다.
    /// 배율은 terminal 수명 동안 고정이다(바꾸는 길은 `reload terminal`).
    phys_w: u32,
    phys_h: u32,
    scale: u32,
    /// 봉인한 키맵 memfd(design 결정 6). 모든 클라이언트에 같은 fd를 준다 — libwayland가 보낼 때 복제한다.
    keymap_fd: i32,
    keymap_size: u32,
    next_id: u32 = 1,
    toplevels: std.ArrayList(*Toplevel) = .empty,
    events: std.ArrayList(Event) = .empty,
    /// 모든 `wl_keyboard`. 키는 포커스 창의 클라이언트 것에만 간다.
    keyboards: wl.list.Head(wl.Keyboard, null) = undefined,
    /// 모든 `wl_output`(WY-M3 확정 4). 창이 처음 configure될 때 그 클라이언트의 output마다 `wl_surface.enter`를 보낸다.
    outputs: wl.list.Head(wl.Output, null) = undefined,
    /// 모든 `xdg_wm_base`(단계 C, ping을 보낼 곳). 창과 같은 클라이언트의 것을 고른다.
    wm_bases: std.ArrayList(*xdg.WmBase) = .empty,
    /// 키보드 포커스 창(단계 C). App이 `setFocus`로 고친다. 창이 사라지면 null이 된다.
    focused: ?u32 = null,
    /// 포커스 창에 누름을 보낸 키(R-KEY-2 · R-KEY-7). 포커스가 바뀌면 비운다.
    held: logic.Held = .{},
    /// 지금 수정키(App이 키마다 준다)와 포커스 클라이언트에 마지막으로 보낸 값. 다르면 `modifiers`를 보낸다.
    mods: logic.Mask = .{ .depressed = 0, .locked = 0 },
    sent_mods: ?logic.Mask = null,
    client_created: wl.Listener(*wl.Client) = .init(clientCreated),
    /// 모든 `wl_pointer`(단계 C). 포인터 이벤트는 포인터 아래 창의 클라이언트 것에만 간다.
    pointers: wl.list.Head(wl.Pointer, null) = undefined,
    /// 포인터 포커스와 버튼 grab(`logic.PointerFocus`), 마지막 아래 창(창 안일 때만)과 자리(화면 좌표).
    ptr: logic.PointerFocus = .{},
    ptr_under: ?u32 = null,
    ptr_x: u32 = 0,
    ptr_y: u32 = 0,
    /// 클립보드(WY-M4). 모든 `wl_data_device` — offer(단계 B)는 키보드처럼 클라이언트로 골라 보낸다.
    data_devices: wl.list.Head(wl.DataDevice, null) = undefined,
    /// `set_selection`을 받아들이는 조건(design 결정 36) — 가장 최근에 키보드 포커스를 가졌던 클라이언트.
    gate: logic.SelectionGate = .{},
    /// 지금 selection을 쥔 클라이언트 source. 바뀌면 옛것에 `cancelled`. source가 사라지면 소멸 처리기가 null로 둔다.
    sel_source: ?*Source = null,
    /// 서버 사본(design 결정 33) — 클라이언트에서 다 받은 바이트. 셸 클립보드와 따로 드는 것은 `clipboard=pane`에서도
    /// 클라이언트끼리의 클립보드가 서야 해서다(결정 37). 단계 B에서 셸의 복사도 여기로 온다.
    clip: ?[]u8 = null,
    /// 서버 사본의 세대(WY-M4 단계 B). 사본이 바뀔 때마다 는다 — 옛 세대의 offer에 온 `receive`는 fd만 닫는다(확정 6).
    clip_gen: u32 = 0,
    /// 진행 중인 받기(하나뿐 — 새 `set_selection`이 오면 옛것을 버린다).
    intake: ?*Intake = null,

    /// 소켓을 연다(design 결정 3, 확정 4). `/run/user/<uid>`(0700, 그 계정의 것)를 만들고 `XDG_RUNTIME_DIR`을 거기로
    /// 둔 뒤 `wayland-0`을 열고, 소켓과 lock의 주인을 계정으로 바꾼다. 성공하면 `WAYLAND_DISPLAY=wayland-0`도 둔다 —
    /// 이 둘이 셸 자식의 환경에 들어간다(부르는 쪽이 셸을 띄우기 전에 부른다). 실패하면 둘을 지우고 에러다.
    ///
    /// `Server`는 heap에 있다 — listener가 libwayland의 목록에 들어가므로 자리가 움직이면 안 된다.
    pub fn start(allocator: std.mem.Allocator, uid: u32, gid: u32, fb_w: u32, fb_h: u32, phys_w: u32, phys_h: u32, scale: u32) !*Server {
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
            .phys_w = phys_w,
            .phys_h = phys_h,
            .scale = scale,
            .keymap_fd = kfd,
            .keymap_size = @intCast(KEYMAP.len + 1),
        };
        self.keyboards.init();
        self.outputs.init();
        self.pointers.init();
        self.data_devices.init();
        display.addClientCreatedListener(&self.client_created);
        _ = try wl.Global.create(display, wl.Compositor, COMPOSITOR_VERSION, *Server, self, bindCompositor);
        _ = try wl.Global.create(display, wl.Output, OUTPUT_VERSION, *Server, self, bindOutput);
        _ = try wl.Global.create(display, wl.Seat, SEAT_VERSION, *Server, self, bindSeat);
        _ = try wl.Global.create(display, xdg.WmBase, WM_BASE_VERSION, *Server, self, bindWmBase);
        _ = try wl.Global.create(display, zxdg.DecorationManagerV1, DECORATION_VERSION, *Server, self, bindDecorationManager);
        _ = try wl.Global.create(display, wl.DataDeviceManager, DATA_DEVICE_MANAGER_VERSION, *Server, self, bindDataDeviceManager);

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

    /// 서버 사본(WY-M4). `Event.selection`을 꺼낸 바퀴에 읽는다 — 다음 `dispatch`가 바꿀 수 있다.
    pub fn clipboard(self: *const Server) ?[]const u8 {
        return self.clip;
    }

    fn push(self: *Server, e: Event) void {
        self.events.append(self.allocator, e) catch logline.print("terminal: wl> event dropped (no memory)\n", .{});
    }

    fn find(self: *Server, id: u32) ?*Toplevel {
        for (self.toplevels.items) |t| if (t.id == id) return t;
        return null;
    }

    /// 키보드 포커스를 창 `want`로 옮긴다(확정 10, R-KEY-7). 옛 창의 클라이언트에 `leave`, 새 창의 클라이언트에
    /// `enter`(눌린 키는 빈 목록)와 지금 수정키. 같은 창이면 아무것도 안 한다. App이 바퀴마다 부른다 — 앞 workspace가
    /// app이면 그 창, 셸이면 null이다.
    pub fn setFocus(self: *Server, want: ?u32, mods: logic.Mask) void {
        self.mods = mods;
        if (self.focused == want) return;
        const old_id = self.focused;
        if (self.focused) |old| if (self.find(old)) |t| if (surfaceOf(t)) |sr| {
            const serial = self.display.nextSerial();
            var it = self.keyboards.iterator(.forward);
            while (it.next()) |kb| if (kb.getClient() == sr.getClient()) kb.sendLeave(serial, sr);
        };
        self.focused = want;
        self.held.clear();
        self.sent_mods = null;
        // column 창의 `activated`는 키보드 포커스다(확정 4). 바뀐 둘에 크기는 그대로 configure를 다시 보낸다 —
        // 아직 한 번도 안 보냈으면(막 연 창) 첫 configure가 `configureColumn`에서 이 값으로 나간다.
        if (old_id) |o| if (self.find(o)) |t| self.resendColumn(t);
        if (want) |w| if (self.find(w)) |t| self.resendColumn(t);
        const t = self.find(want orelse return) orelse return;
        const sr = surfaceOf(t) orelse return;
        // 이 클라이언트가 가장 최근의 포커스다 — 셸로 가도 남는다(design 결정 36).
        self.gate.focus(@intFromPtr(sr.getClient()));
        // selection은 키보드 `enter` 바로 앞이다(xml `wl_data_device.selection`, design 결정 34).
        self.offerTo(sr.getClient());
        var it = self.keyboards.iterator(.forward);
        while (it.next()) |kb| if (kb.getClient() == sr.getClient()) self.enterKeyboard(kb, sr);
        self.sent_mods = mods;
    }

    /// 키보드 하나에 `enter`와 수정키. 눌린 키 목록은 비운다(R-KEY-7 — 포커스 전에 누른 키는 클라이언트의 것이 아니다).
    fn enterKeyboard(self: *Server, kb: *wl.Keyboard, sr: *wl.Surface) void {
        var empty: wl.Array = .{ .size = 0, .alloc = 0, .data = null };
        kb.sendEnter(self.display.nextSerial(), sr, &empty);
        kb.sendModifiers(self.display.nextSerial(), self.mods.depressed, 0, self.mods.locked, 0);
    }

    /// 포커스 창에 키 하나(확정 10). `code`는 evdev 코드다(클라이언트가 +8 한다, 확인 3). 뗌은 누름을 보낸 키만 간다
    /// (`Held`). 키 뒤에 수정키가 바뀌었으면 `modifiers`를 보낸다 — 수정키를 누른 키 이벤트 다음에 상태가 오는 것이
    /// weston과 같은 순서다. 포커스 창이 없으면 아무것도 안 한다.
    pub fn key(self: *Server, code: u16, pressed: bool, mods: logic.Mask, time_ms: u32) void {
        self.mods = mods;
        const id = self.focused orelse return;
        const t = self.find(id) orelse return;
        const sr = surfaceOf(t) orelse return;
        const send = if (pressed) self.held.press(code) else self.held.release(code);
        const mods_changed = if (self.sent_mods) |m| !std.meta.eql(m, mods) else true;
        if (!send and !mods_changed) return;
        var it = self.keyboards.iterator(.forward);
        if (send) {
            const serial = self.display.nextSerial();
            const state: wl.Keyboard.KeyState = if (pressed) .pressed else .released;
            while (it.next()) |kb| if (kb.getClient() == sr.getClient()) kb.sendKey(serial, time_ms, code, state);
            logline.print("terminal: wl> key code={d} state={d} to={d}\n", .{ code, @intFromBool(pressed), id });
        }
        if (mods_changed) {
            const serial = self.display.nextSerial();
            it = self.keyboards.iterator(.forward);
            while (it.next()) |kb| if (kb.getClient() == sr.getClient())
                kb.sendModifiers(serial, mods.depressed, 0, mods.locked, 0);
            self.sent_mods = mods;
        }
    }

    /// 포인터가 화면 좌표 `x` · `y`로 움직였다(WY-M2 확정 8). `cand`는 그 자리의 창(App이 strip이나 앞 workspace로 고른다)이고,
    /// 서버가 창이 실제로 보이는 사각형(마지막 `fit`) 안인지 다시 본다 — 둘레의 검정은 창이 아니다. enter · leave ·
    /// motion은 `logic.PointerFocus`가 정한다(버튼을 쥔 동안 leave를 미룬다).
    pub fn pointerMove(self: *Server, cand: ?u32, x: u32, y: u32, time_ms: u32) void {
        self.ptr_x = x;
        self.ptr_y = y;
        self.ptr_under = under: {
            const id = cand orelse break :under null;
            const t = self.find(id) orelse break :under null;
            const f = t.last_fit orelse break :under null;
            break :under if (logic.inside(f, x, y)) id else null;
        };
        self.applyMove(self.ptr.move(self.ptr_under), time_ms);
    }

    /// 버튼 하나(evdev `BTN_*`). 포인터 아래 창이 없으면(셸 · 여백) 아무것도 안 간다. 마지막 뗌 뒤에는 미룬 leave를 낸다.
    pub fn pointerButton(self: *Server, code: u32, pressed: bool, time_ms: u32) void {
        const target = if (pressed) self.ptr.press() else self.ptr.release();
        if (target) |id| if (self.find(id)) |t| if (surfaceOf(t)) |sr| {
            const serial = self.display.nextSerial();
            const state: wl.Pointer.ButtonState = if (pressed) .pressed else .released;
            var it = self.pointers.iterator(.forward);
            while (it.next()) |p| if (p.getClient() == sr.getClient()) {
                p.sendButton(serial, time_ms, code, state);
                if (p.getVersion() >= 5) p.sendFrame();
            };
            logline.print("terminal: wl> button id={d} code={d} state={d}\n", .{ id, code, @intFromBool(pressed) });
        };
        if (!pressed and self.ptr.held == 0) self.applyMove(self.ptr.move(self.ptr_under), time_ms);
    }

    /// 휠 `notches`(양수가 앞으로 — 위). 포인터 아래 창에 axis_source(wheel) · axis · axis_discrete · frame(판 5+).
    pub fn pointerAxis(self: *Server, notches: i32, time_ms: u32) void {
        const id = self.ptr.focus orelse return;
        const t = self.find(id) orelse return;
        const sr = surfaceOf(t) orelse return;
        const a = logic.axisFor(notches);
        var it = self.pointers.iterator(.forward);
        while (it.next()) |p| if (p.getClient() == sr.getClient()) {
            if (p.getVersion() >= 5) p.sendAxisSource(.wheel);
            p.sendAxis(time_ms, .vertical_scroll, @fromBackingInt(@intCast(a.value)));
            if (p.getVersion() >= 5) {
                p.sendAxisDiscrete(.vertical_scroll, a.discrete);
                p.sendFrame();
            }
        };
        logline.print("terminal: wl> axis id={d} v={d}\n", .{ id, @divTrunc(a.value, 256) });
    }

    /// 포인터가 들어가 있는 창(App이 앞이 바뀌었을 때 그 창이 아직 보이는지 본다).
    pub fn pointerFocus(self: *const Server) ?u32 {
        return self.ptr.focus;
    }

    /// 포인터 아래 창의 클라이언트가 `set_cursor(NULL)`로 커서를 숨겼다(확정 10) — terminal이 화살표를 안 그린다.
    pub fn arrowHidden(self: *Server) bool {
        const id = self.ptr.focus orelse return false;
        const t = self.find(id) orelse return false;
        return t.cursor_hidden;
    }

    /// `logic.PointerFocus.move`가 정한 것을 보낸다 — leave, enter(surface 좌표와 함께), motion, 그리고 frame.
    fn applyMove(self: *Server, m: logic.PointerFocus.Move, time_ms: u32) void {
        if (m.leave) |id| if (self.find(id)) |t| if (surfaceOf(t)) |sr| {
            const serial = self.display.nextSerial();
            var it = self.pointers.iterator(.forward);
            while (it.next()) |p| if (p.getClient() == sr.getClient()) {
                p.sendLeave(serial, sr);
                if (p.getVersion() >= 5) p.sendFrame();
            };
            logline.print("terminal: wl> pointer leave id={d}\n", .{id});
        };
        if (m.enter) |id| if (self.find(id)) |t| if (surfaceOf(t)) |sr| {
            var it = self.pointers.iterator(.forward);
            while (it.next()) |p| if (p.getClient() == sr.getClient()) self.enterPointer(p, t, sr);
            logline.print("terminal: wl> pointer enter id={d}\n", .{id});
        };
        if (m.motion) |id| if (self.find(id)) |t| if (surfaceOf(t)) |sr| {
            const at = self.surfaceAt(t);
            var it = self.pointers.iterator(.forward);
            while (it.next()) |p| if (p.getClient() == sr.getClient()) {
                p.sendMotion(time_ms, @fromBackingInt(@intCast(at.x)), @fromBackingInt(@intCast(at.y)));
                if (p.getVersion() >= 5) p.sendFrame();
            };
        };
    }

    /// 포인터 하나에 `enter`(지금 자리의 surface 좌표)와 frame.
    fn enterPointer(self: *Server, p: *wl.Pointer, t: *Toplevel, sr: *wl.Surface) void {
        const at = self.surfaceAt(t);
        p.sendEnter(self.display.nextSerial(), sr, @fromBackingInt(@intCast(at.x)), @fromBackingInt(@intCast(at.y)));
        if (p.getVersion() >= 5) p.sendFrame();
    }

    /// 지금 포인터 자리를 창 `t`의 surface 좌표로(마지막으로 옮긴 자리 기준). 아직 안 옮긴 창은 0, 0이다.
    fn surfaceAt(self: *const Server, t: *const Toplevel) logic.Point {
        const f = t.last_fit orelse return .{ .x = 0, .y = 0 };
        return logic.surfacePoint(f, self.ptr_x, self.ptr_y);
    }

    /// `Cmd+Q`(확정 11, design 결정 12). 창 `id`에 `xdg_toplevel.close`, 그 클라이언트의 `xdg_wm_base`에 `ping`, 그리고
    /// 2초 기한. pong이 오거나 클라이언트가 끝나면 기한이 사라진다(`wmBaseRequest`의 pong · 창의 destroy). 기한이 이미
    /// 걸려 있으면 close만 다시 보낸다 — 거듭 눌러도 기한이 밀리지 않는다.
    pub fn close(self: *Server, id: u32, now_ms: i64) void {
        const t = self.find(id) orelse return;
        t.resource.sendClose();
        logline.print("terminal: wl> close id={d}\n", .{id});
        const client = t.resource.getClient();
        const serial = self.display.nextSerial();
        if (!t.deadline.arm(now_ms, serial)) return;
        t.pid = client.getCredentials().pid;
        for (self.wm_bases.items) |wm| if (wm.getClient() == client) {
            wm.sendPing(serial);
            break;
        };
        logline.print("terminal: wl> ping id={d}\n", .{id});
    }

    /// `poll`에 넘길 밀리초 — 가장 이른 `Cmd+Q` 기한까지. 없으면 -1.
    pub fn timeout(self: *const Server, now_ms: i64) i32 {
        var best: i32 = -1;
        for (self.toplevels.items) |t| {
            const ms = t.deadline.timeout(now_ms);
            if (ms >= 0 and (best < 0 or ms < best)) best = ms;
        }
        return best;
    }

    /// 기한이 지난 창의 클라이언트에 SIGKILL(design 결정 12). 끝은 libwayland가 소켓이 닫힌 것으로 알고 클라이언트를
    /// 지운다 — 그 길에 `wl> gone` 줄과 창의 `gone` 일이 나온다(다음 `dispatch`).
    pub fn expire(self: *Server, now_ms: i64) void {
        for (self.toplevels.items) |t| {
            if (!t.deadline.expired(now_ms)) continue;
            logline.print("terminal: wl> kill pid={d}\n", .{t.pid});
            if (t.pid > 0) _ = linux.kill(t.pid, .KILL);
        }
    }

    /// 받을 자리가 없다(workspace 아홉, 또는 strip의 slot 여덟 — 확정 3) — close를 보낸다.
    pub fn refuse(self: *Server, id: u32) void {
        const t = self.find(id) orelse return;
        t.resource.sendClose();
        logline.print("terminal: wl> toplevel refused id={d}\n", .{id});
    }

    /// 창이 자기 workspace를 받았다(WY-M0의 길 — 둠, 앞이 app workspace일 때). 화면 크기 · fullscreen · activated의
    /// configure 하나를 보낸다. 그 뒤로 크기가 안 바뀐다.
    pub fn placeWorkspace(self: *Server, id: u32) void {
        const t = self.find(id) orelse return;
        t.place = .workspace;
        t.area_w = self.fb_w;
        t.area_h = self.fb_h;
        sendConfigure(t, self.fb_w, self.fb_h, true);
    }

    /// 창이 strip의 column이다(확정 4, design 결정 22). `w` × `h`는 pane의 픽셀 크기다. App이 바퀴마다 모든 app slot에
    /// 부른다 — 크기나 `activated`가 지난번 보낸 것과 같으면 아무것도 안 보낸다. `activated`는 키보드 포커스다(`setFocus`).
    pub fn configureColumn(self: *Server, id: u32, w: u32, h: u32) void {
        const t = self.find(id) orelse return;
        t.place = .column;
        t.area_w = w;
        t.area_h = h;
        self.resendColumn(t);
    }

    /// column 창의 configure를 지금 값(크기 · 포커스)으로. 지난번 것과 같으면 보내지 않는다.
    fn resendColumn(self: *Server, t: *Toplevel) void {
        if (t.place != .column or t.area_w == 0 or t.area_h == 0) return;
        const want: Toplevel.Sent = .{ .w = t.area_w, .h = t.area_h, .act = self.focused == t.id };
        if (t.sent) |was| if (std.meta.eql(was, want)) return;
        sendConfigure(t, want.w, want.h, want.act);
    }

    /// toplevel `id`의 버퍼를 프레임버퍼의 사각형 `area` 안에 옮긴다(확정 8, WY-M2 확정 5). 그린 사각형을 돌려준다.
    /// 버퍼가 없거나 받지 않는 형식이면 null이다 — 그 자리는 부르는 쪽이 검정으로 둔다.
    pub fn paint(self: *Server, id: u32, dst: [*]u8, pitch: u32, area: logic.Area) ?logic.Fit {
        const t = self.find(id) orelse return null;
        const xs = t.xdg orelse return null;
        const s = xs.surface orelse return null;
        const buf = s.current orelse return null;
        const shm = wl.shm.Buffer.get(@ptrCast(buf)) orelse return null;
        if (!logic.formatOk(shm.getFormat())) return null;
        // 창의 크기는 surface 크기(버퍼 ÷ buffer_scale)다(WY-M3, design 결정 29) — `last_fit`과 포인터 좌표가 이 단위다.
        const sz = logic.surfaceSize(@intCast(shm.getWidth()), @intCast(shm.getHeight()), s.scale);
        const f = logic.fitIn(area, sz.w, sz.h) orelse return null;
        // 클라이언트가 풀을 줄였으면 읽기가 SIGBUS다 — libwayland이 그 틈을 막는다(begin · end).
        shm.beginAccess();
        defer shm.endAccess();
        const data: [*]const u8 = @ptrCast(shm.getData() orelse return null);
        logic.blit(dst, pitch, f, data, @intCast(shm.getStride()), s.scale);
        // 포인터 좌표를 거꾸로 셀 자리(단계 C).
        t.last_fit = f;
        return f;
    }

    /// 창 `id`의 buffer_scale(WY-M3). 창이나 버퍼가 없으면 1 — App이 물리 합성 목록에 넣을지 정한다(1이면 그림자 늘리기가
    /// 같은 그림을 만든다, design 결정 30).
    pub fn bufferScale(self: *Server, id: u32) u32 {
        const t = self.find(id) orelse return 1;
        const xs = t.xdg orelse return 1;
        const s = xs.surface orelse return 1;
        if (s.current == null) return 1;
        return s.scale;
    }

    /// 물리 합성(WY-M3 확정 7, design 결정 30). 창 `id`의 버퍼를 물리 dumb 버퍼 `out`에 — 논리 사각형 `area` 안의 자리를
    /// 지금 버퍼로 다시 셈한 `fit`을 × `s` 해서, 논리 `clip`과 겹친 자리만 옮긴다. `drm.Framebuffer.stage` 뒤 · `flush` 앞에
    /// 부른다(반대면 같은 프레임의 늘리기가 덮는다). 자리를 `last_fit`이 아니라 지금 버퍼로 다시 세는 것은, commit이 하한 안에서
    /// 그리기를 미룬 사이 화살표만 옮기는 바퀴가 올 수 있어서다 — 옛 자리로 새(작아진) 버퍼를 읽으면 버퍼 밖이다. buffer_scale이
    /// 1이 됐으면 아무것도 안 한다(그림자 늘리기가 맞다).
    pub fn paintPhys(self: *Server, id: u32, out: [*]u8, out_pitch: u32, s: u32, area: logic.Area, clip: logic.Area) void {
        const t = self.find(id) orelse return;
        const xs = t.xdg orelse return;
        const sf = xs.surface orelse return;
        if (sf.scale == 1) return;
        const buf = sf.current orelse return;
        const shm = wl.shm.Buffer.get(@ptrCast(buf)) orelse return;
        if (!logic.formatOk(shm.getFormat())) return;
        const sz = logic.surfaceSize(@intCast(shm.getWidth()), @intCast(shm.getHeight()), sf.scale);
        const f = logic.fitIn(area, sz.w, sz.h) orelse return;
        shm.beginAccess();
        defer shm.endAccess();
        const data: [*]const u8 = @ptrCast(shm.getData() orelse return);
        logic.blitClip(out, out_pitch, logic.scaleFit(f, s), data, @intCast(shm.getStride()), sf.scale, logic.scaleArea(clip, s));
    }

    /// toplevel `id`가 든 프레임을 화면에 냈다(확정 9) — 그 commit들의 frame 콜백에 `done`을 보낸다.
    pub fn presented(self: *Server, id: u32, ms: u32) void {
        const t = self.find(id) orelse return;
        const xs = t.xdg orelse return;
        const s = xs.surface orelse return;
        var it = s.frames.safeIterator(.forward);
        while (it.next()) |cb| cb.destroySendDone(ms);
    }

    // ── 클립보드: 앱 → 셸(WY-M4 단계 A, design 결정 33 · 36) ──

    /// 클라이언트의 첫 toplevel 번호. 로그의 `from=` · `id=`다 — 창이 없는 클라이언트면 0.
    fn toplevelOf(self: *const Server, client: *wl.Client) u32 {
        for (self.toplevels.items) |t| if (t.resource.getClient() == client) return t.id;
        return 0;
    }

    /// `set_selection`(xml: "copy data to the selection"). 받아들이면 그 자리에서 mime을 고르고 `send`로 파이프를 건넨다 —
    /// 즉시 받기(design 결정 33). 셸에서 붙일 때 받으면 셸의 `Cmd+V`가 비동기가 된다.
    fn setSelection(self: *Server, dev: *wl.DataDevice, source: ?*Source, serial: u32) void {
        const client = dev.getClient();
        const from = self.toplevelOf(client);
        const src = source orelse {
            // selection을 비운다. 지금 source의 주인일 때만 받는다. 서버 사본은 그대로다 — 셸 클립보드에는 "지우기"가 없다.
            const cur = self.sel_source orelse return;
            if (cur.resource.getClient() != client) return;
            cur.resource.sendCancelled();
            self.sel_source = null;
            if (self.intake) |in| if (in.source == cur) self.endIntake(.dropped);
            logline.print("terminal: wl> selection cleared id={d}\n", .{from});
            return;
        };
        if (src.used) return dev.postError(.used_source, "wl_data_source was already used for a selection");
        src.used = true;
        // serial 값은 보지 않는다(결정 36) — 로그에만 남긴다.
        if (!self.gate.allows(@intFromPtr(client))) {
            logline.print("terminal: wl> selection refused id={d} serial={d}\n", .{ from, serial });
            // 받지 않은 source다 — 클라이언트가 selection을 쥐었다고 믿지 않게 곧바로 거둔다.
            src.resource.sendCancelled();
            return;
        }
        // 옛 source는 바뀌었다(xml `cancelled`의 첫 까닭). 옛 받기는 버린다 — 진행 중 받기는 하나다.
        if (self.sel_source) |old| if (old != src) old.resource.sendCancelled();
        self.sel_source = src;
        self.endIntake(.dropped);
        const mime = logic.pickMime(src.mimes.items) orelse {
            logline.print("terminal: wl> selection ignored mimes={d} id={d}\n", .{ src.mimes.items.len, from });
            return;
        };
        var fds: [2]c_int = undefined;
        if (pipe2(&fds, O_CLOEXEC) != 0) {
            logline.print("terminal: wl> selection pipe failed\n", .{});
            return;
        }
        if (linux.errno(linux.fcntl(fds[0], F_SETFL, O_NONBLOCK)) != .SUCCESS) {
            _ = linux.close(fds[0]);
            _ = linux.close(fds[1]);
            logline.print("terminal: wl> selection pipe failed\n", .{});
            return;
        }
        src.resource.sendSend(mime, fds[1]);
        // libwayland은 이벤트를 만들 때(marshal) fd를 복제한다 — 우리 쓰기 끝은 곧바로 닫는다. 안 닫으면 클라이언트가
        // 쓰고 닫아도 쓰기 끝이 하나 남아 EOF가 영영 안 온다(plan 실측 1).
        _ = linux.close(fds[1]);
        self.startIntake(src, fds[0]) catch {
            _ = linux.close(fds[0]);
            logline.print("terminal: wl> selection intake failed\n", .{});
            return;
        };
        logline.print("terminal: wl> selection from={d} mime={s} serial={d}\n", .{ from, mime, serial });
    }

    /// 읽기 끝과 2초 기한을 서버의 epoll에 싣는다(design 결정 33) — `main.zig`의 poll에 칸을 더하지 않는다.
    fn startIntake(self: *Server, src: *Source, read_fd: i32) !void {
        const in = try self.allocator.create(Intake);
        errdefer self.allocator.destroy(in);
        in.* = .{ .srv = self, .source = src, .fd = read_fd, .readable = undefined, .timer = undefined };
        in.readable = try self.loop.addFd(*Intake, read_fd, .{ .readable = true }, intakeReadable, in);
        errdefer in.readable.remove();
        in.timer = try self.loop.addTimer(*Intake, intakeTimeout, in);
        errdefer in.timer.remove();
        try in.timer.timerUpdate(logic.SELECTION_TIMEOUT_MS);
        self.intake = in;
    }

    const Outcome = enum { done, too_big, timeout, failed, dropped };

    /// 진행 중인 받기를 끝낸다. `done`이면 받은 것이 서버 사본이 되고 `Event.selection`이 쌓인다. 나머지는 버리고 사본은
    /// 그대로다. 받기가 없으면 아무것도 안 한다.
    ///
    /// fd 콜백 · 타이머 콜백 안에서 불려도 된다 — libwayland은 지운 source를 dispatch가 끝난 뒤에 해제한다. `addFd`는
    /// 받은 fd를 복제해 epoll에 싣고 `remove`가 그 복제를 닫으므로, 원래 fd는 여기서 닫는다.
    fn endIntake(self: *Server, how: Outcome) void {
        const in = self.intake orelse return;
        self.intake = null;
        in.readable.remove();
        in.timer.remove();
        _ = linux.close(in.fd);
        defer self.allocator.destroy(in);
        defer in.buf.deinit(self.allocator);
        switch (how) {
            .done => {
                // 아무것도 안 쓴 source(실패한 클라이언트)가 클립보드를 비우지 않게 한다.
                if (in.buf.items.len == 0) {
                    logline.print("terminal: wl> selection empty\n", .{});
                    return;
                }
                const bytes = in.buf.toOwnedSlice(self.allocator) catch {
                    logline.print("terminal: wl> selection dropped (no memory)\n", .{});
                    return;
                };
                if (self.clip) |old| self.allocator.free(old);
                self.clip = bytes;
                self.clip_gen +%= 1;
                logline.print("terminal: wl> selection len={d}\n", .{bytes.len});
                self.push(.selection);
                // 사본이 바뀌면 늘 포커스 클라이언트에 새 offer다 — 대개 그 source 자신이다(SDL은 자기 source가 있으면
                // offer 대신 내부 데이터를 쓴다).
                self.offerFocused();
            },
            .too_big => logline.print("terminal: wl> selection too-big\n", .{}),
            .timeout => logline.print("terminal: wl> selection timeout\n", .{}),
            .failed => logline.print("terminal: wl> selection read failed\n", .{}),
            .dropped => logline.print("terminal: wl> selection dropped\n", .{}),
        }
    }

    // ── 클립보드: 셸 → 앱(WY-M4 단계 B, design 결정 34) ──

    /// 셸이 복사했다(copy mode `y` · 포인터 뗌, `clipboard=shared`일 때만 — 결정 37). 서버 사본을 갈고, 클라이언트가 쥔
    /// selection은 바뀌었으니 그 source에 `cancelled`, 진행 중 받기는 버린다. 포커스 클라이언트가 있으면 새 offer다 —
    /// 셸에서 복사하는 동안은 대개 없고, 다음 포커스의 `enter` 앞에서 간다(`setFocus`).
    ///
    /// 받기와 같은 한도(1 MiB)를 넘는 글은 내지 않는다 — 사본을 비우고 클라이언트에는 빈 selection이다. 셸 클립보드는
    /// 그대로다(셸 안의 `Cmd+V`는 한도가 없다).
    pub fn setClipboard(self: *Server, bytes: []const u8) void {
        if (self.sel_source) |old| old.resource.sendCancelled();
        self.sel_source = null;
        self.endIntake(.dropped);
        if (self.clip) |old| self.allocator.free(old);
        self.clip = null;
        self.clip_gen +%= 1;
        if (bytes.len > logic.SELECTION_MAX_BYTES) {
            logline.print("terminal: wl> clipboard too-big len={d}\n", .{bytes.len});
        } else {
            self.clip = self.allocator.dupe(u8, bytes) catch blk: {
                logline.print("terminal: wl> clipboard dropped (no memory)\n", .{});
                break :blk null;
            };
        }
        self.offerFocused();
    }

    /// 키보드 포커스 창의 클라이언트에 지금 사본의 offer. 포커스가 셸이면 아무것도 안 한다.
    fn offerFocused(self: *Server) void {
        const t = self.find(self.focused orelse return) orelse return;
        const sr = surfaceOf(t) orelse return;
        self.offerTo(sr.getClient());
    }

    /// 클라이언트의 모든 data device에 지금 사본을 offer한다 — `data_offer` → `offer` × 4 → `selection`. 사본이 없으면
    /// `selection(null)`. 장치가 하나라도 있었으면 줄 하나를 찍는다.
    fn offerTo(self: *Server, client: *wl.Client) void {
        var sent = false;
        var it = self.data_devices.iterator(.forward);
        while (it.next()) |dev| if (dev.getClient() == client) {
            self.offerDevice(dev);
            sent = true;
        };
        if (!sent) return;
        if (self.clip) |c|
            logline.print("terminal: wl> offer to={d} len={d}\n", .{ self.toplevelOf(client), c.len })
        else
            logline.print("terminal: wl> offer to={d} none\n", .{self.toplevelOf(client)});
    }

    fn offerDevice(self: *Server, dev: *wl.DataDevice) void {
        if (self.clip == null) return dev.sendSelection(null);
        const res = wl.DataOffer.create(dev.getClient(), dev.getVersion(), 0) catch return dev.postNoMemory();
        const o = self.allocator.create(Offer) catch {
            res.destroy();
            return dev.postNoMemory();
        };
        o.* = .{ .srv = self, .gen = self.clip_gen };
        res.setHandler(*Offer, offerRequest, offerDestroyed, o);
        dev.sendDataOffer(res);
        for (logic.OFFER_MIMES) |m| res.sendOffer(m);
        dev.sendSelection(res);
    }

    /// `receive`(확정 7). 받은 fd에 O_NONBLOCK을 걸고 요청 처리기 안에서 곧바로 쓴다 — SDL은 파이프를 14 ms만 기다린다.
    /// 다 썼으면 닫고, 남았으면(64 KiB 파이프를 넘는 글) 남은 것을 복사해 writable에 이어 쓴다(2초 기한). 읽는 쪽이 이미
    /// 닫았으면 EPIPE다 — terminal은 SIGPIPE를 무시하므로(결정 35) 죽지 않고 조용히 닫는다. fd는 서버가 닫는다.
    fn receive(self: *Server, o: *Offer, client: *wl.Client, mime: [*:0]const u8, out_fd: i32) void {
        const id = self.toplevelOf(client);
        const bytes = self.clip orelse {
            _ = linux.close(out_fd);
            return;
        };
        if (o.gen != self.clip_gen) {
            logline.print("terminal: wl> receive stale to={d}\n", .{id});
            _ = linux.close(out_fd);
            return;
        }
        const fl = linux.fcntl(out_fd, F_GETFL, 0);
        if (linux.errno(fl) != .SUCCESS or linux.errno(linux.fcntl(out_fd, F_SETFL, fl | O_NONBLOCK)) != .SUCCESS) {
            _ = linux.close(out_fd);
            return;
        }
        const first = writeSome(out_fd, bytes);
        logline.print("terminal: wl> receive to={d} mime={s} len={d} first={d}\n", .{ id, mime, bytes.len, first.n });
        if (first.broken) {
            logline.print("terminal: wl> receive closed to={d}\n", .{id});
            _ = linux.close(out_fd);
            return;
        }
        if (first.n == bytes.len) {
            _ = linux.close(out_fd);
            return;
        }
        self.startOutgo(out_fd, bytes[first.n..]) catch {
            logline.print("terminal: wl> receive dropped to={d}\n", .{id});
            _ = linux.close(out_fd);
        };
    }

    /// 남은 쓰기 하나를 epoll에 싣는다(writable + 2초 기한). 남은 바이트는 복사한다 — 사본은 그 사이에 바뀔 수 있다.
    fn startOutgo(self: *Server, out_fd: i32, rest: []const u8) !void {
        const out = try self.allocator.create(Outgo);
        errdefer self.allocator.destroy(out);
        const buf = try self.allocator.dupe(u8, rest);
        errdefer self.allocator.free(buf);
        out.* = .{ .srv = self, .fd = out_fd, .buf = buf, .writable = undefined, .timer = undefined };
        out.writable = try self.loop.addFd(*Outgo, out_fd, .{ .writable = true }, outgoWritable, out);
        errdefer out.writable.remove();
        out.timer = try self.loop.addTimer(*Outgo, outgoTimeout, out);
        errdefer out.timer.remove();
        try out.timer.timerUpdate(logic.SELECTION_TIMEOUT_MS);
    }
};

/// 비블록 쓰기를 EAGAIN이나 끝까지. `broken`이면 읽는 쪽이 닫았다(EPIPE)거나 다른 오류다.
fn writeSome(fd: i32, bytes: []const u8) struct { n: usize, broken: bool } {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = linux.write(fd, bytes[off..].ptr, bytes.len - off);
        switch (linux.errno(n)) {
            .SUCCESS => off += n,
            .INTR => continue,
            .AGAIN => return .{ .n = off, .broken = false },
            else => return .{ .n = off, .broken = true },
        }
    }
    return .{ .n = off, .broken = false };
}

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
/// 클립보드의 파이프(WY-M4). Zig의 `linux.pipe2`는 깃발이 packed struct라 다른 extern들과 같은 모양으로 둔다.
extern "c" fn pipe2(fds: *[2]c_int, flags: c_int) c_int;

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

fn clientGone(listener: *wl.Listener(*wl.Client), client: *wl.Client) void {
    const rec: *ClientRec = @fieldParentPtr("destroy", listener);
    logline.print("terminal: wl> gone pid={d}\n", .{rec.pid});
    // 포인터는 다음 클라이언트가 다시 쓸 수 있다 — 끝난 클라이언트를 "가장 최근 포커스"로 남기지 않는다(WY-M4).
    rec.srv.gate.forget(@intFromPtr(client));
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
            // 배율을 알린다(WY-M3 확정 3, design 결정 27). 판 6 이상의 surface에만 — 판 4로 bind한 클라이언트(둠)에는 이
            // 이벤트가 없다. 배율 1에서도 1을 보낸다(받기 전의 기본값과 뜻은 같지만 클라이언트가 줄로 찍는다).
            if (res.getVersion() >= 6) res.sendPreferredBufferScale(@intCast(srv.scale));
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
    /// buffer_scale(WY-M3 확정 5). `set_buffer_scale`이 pending을 고치고 commit이 current로 옮긴다 — double-buffered.
    /// 다른 길로는 둘 다 안 바뀐다(xml).
    pending_scale: u32 = 1,
    scale: u32 = 1,
};

fn surfaceRequest(res: *wl.Surface, req: wl.Surface.Request, s: *Surface) void {
    switch (req) {
        .destroy => res.destroy(),
        .attach => |a| {
            // 판 5+에서 0이 아닌 x · y는 오류다(xml, design 결정 28). 놓는 자리는 서버가 정한다 — 판 4 이하는 지금처럼 버린다.
            if (res.getVersion() >= 5 and (a.x != 0 or a.y != 0))
                return res.postError(.invalid_offset, "attach with a non-zero offset on wl_surface version 5+");
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
        .set_buffer_scale => |r| {
            if (!logic.scaleOk(r.scale)) return res.postError(.invalid_scale, "buffer scale must be greater than 0");
            s.pending_scale = @intCast(r.scale);
        },
        // damage는 아직 안 본다 — 통째 blit이다(부분 blit은 M5, R-WY-10). `offset`(판 5)은 받아서 버린다 — toplevel
        // 하나뿐이고 놓는 자리는 서버가 정한다(design 결정 28).
        .damage, .damage_buffer, .set_opaque_region, .set_input_region, .set_buffer_transform, .offset => {},
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
    // buffer_scale이 먼저 확정된다 — 아래 크기 검사와 `wl> commit` 줄이 새 값을 본다. 값만 바뀐 commit도 다시 그린다.
    var changed = s.scale != s.pending_scale;
    s.scale = s.pending_scale;
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
    // 버퍼 크기가 buffer_scale의 정수 배여야 한다(xml의 attach, design 결정 28).
    if (s.current) |b| if (wl.shm.Buffer.get(@ptrCast(b))) |shm| {
        if (!logic.sizeOk(@intCast(shm.getWidth()), @intCast(shm.getHeight()), s.scale))
            return s.resource.postError(.invalid_size, "buffer size is not a multiple of the buffer scale");
    };
    const waiting = !s.pending_frames.empty();
    s.frames.appendList(&s.pending_frames);

    const xs = s.role orelse return;
    const t = xs.toplevel orelse return;
    const step = logic.onCommit(xs.phase, xs.acked, s.current != null);
    switch (step.action) {
        .unconfigured_buffer => return xs.resource.postError(.unconfigured_buffer, "buffer before the first ack_configure"),
        // 첫 commit — 자리는 App이 정한다(`Event.toplevel`). configure는 App이 `placeWorkspace` · `configureColumn`으로
        // 같은 바퀴에 보낸다(이 dispatch 뒤 `takeEvents`, 바퀴 끝의 flush).
        .send_configure => s.srv.push(.{ .toplevel = .{ .id = t.id, .fullscreen = t.want_fullscreen } }),
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
    const sz = logic.surfaceSize(@intCast(shm.getWidth()), @intCast(shm.getHeight()), s.scale);
    const f = logic.fit(t.area_w, t.area_h, sz.w, sz.h) orelse return;
    const sig: Toplevel.Sig = .{ .w = shm.getWidth(), .h = shm.getHeight(), .fit = f, .bs = s.scale };
    if (t.last) |l| if (std.meta.eql(l, sig)) return;
    t.last = sig;
    // `scale=`은 `fit`의 늘림 배수다(체인 패턴이 본다). buffer_scale은 1이 아닐 때만 끝에 붙인다 — bs 1의 줄은 WY-M2와
    // 바이트가 같다(WY-M3 확정 6).
    var tail: [16]u8 = undefined;
    const bs_text = if (s.scale != 1) std.fmt.bufPrint(&tail, " bs={d}", .{s.scale}) catch "" else "";
    logline.print("terminal: wl> commit id={d} buf={d}x{d} scale={d} at={d},{d}{s}\n", .{ t.id, sig.w, sig.h, f.k, f.x, f.y, bs_text });
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

/// mode는 물리 크기("physical hardware units"), scale은 HS 배율이다(WY-M3 확정 2, design 결정 27). 이 클라이언트의 창이
/// 이미 보이면 그 surface에 `enter`(늦은 bind — 키보드의 늦은 `get_keyboard`와 같은 까닭).
fn bindOutput(client: *wl.Client, srv: *Server, version: u32, id: u32) void {
    const o = wl.Output.create(client, version, id) catch return client.postNoMemory();
    o.setHandler(*Server, outputRequest, outputDestroyed, srv);
    srv.outputs.append(o);
    o.sendGeometry(0, 0, 0, 0, .unknown, "TARS", "framebuffer", .normal);
    o.sendMode(.{ .current = true, .preferred = true }, @intCast(srv.phys_w), @intCast(srv.phys_h), 60000);
    if (version >= 2) o.sendScale(@intCast(srv.scale));
    if (version >= 4) {
        o.sendName("TARS-1");
        o.sendDescription("TARS framebuffer");
    }
    if (version >= 2) o.sendDone();
    for (srv.toplevels.items) |t| {
        if (t.sent == null) continue;
        const sr = surfaceOf(t) orelse continue;
        if (sr.getClient() == client) sr.sendEnter(o);
    }
}

fn outputRequest(o: *wl.Output, req: wl.Output.Request, _: *Server) void {
    switch (req) {
        .release => o.destroy(),
    }
}

fn outputDestroyed(o: *wl.Output, _: *Server) void {
    o.getLink().remove();
}

/// 창이 처음 configure된다(WY-M3 확정 4) — 그 클라이언트의 output마다 `wl_surface.enter`. output은 하나뿐이고 leave는
/// 보내지 않는다(xml이 허락한다 — 숨겨져도 leave가 없을 수 있다).
fn enterOutputs(t: *Toplevel) void {
    const sr = surfaceOf(t) orelse return;
    var it = t.srv.outputs.iterator(.forward);
    while (it.next()) |o| if (o.getClient() == sr.getClient()) sr.sendEnter(o);
}

// ── wl_seat · wl_keyboard ──────────────────────────────────────────────

fn bindSeat(client: *wl.Client, srv: *Server, version: u32, id: u32) void {
    const seat = wl.Seat.create(client, version, id) catch return client.postNoMemory();
    seat.setHandler(*Server, seatRequest, null, srv);
    seat.sendCapabilities(.{ .keyboard = true, .pointer = true });
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
            // 포커스 창의 클라이언트가 키보드를 나중에 얻었다(창을 만든 뒤 seat의 capabilities를 받는 순서가 흔하다).
            // 이 키보드에도 `enter`를 보낸다 — 안 보내면 다음 포커스 변경까지 키를 못 받는다.
            if (srv.focused) |id| if (srv.find(id)) |t| if (surfaceOf(t)) |sr| if (sr.getClient() == client)
                srv.enterKeyboard(kb, sr);
        },
        // WY-M2 단계 C. 포인터 아래 창의 클라이언트가 포인터를 나중에 얻었으면 그 포인터에도 `enter` — 키보드와 같은 까닭.
        .get_pointer => |r| {
            const p = wl.Pointer.create(client, seat.getVersion(), r.id) catch return seat.postNoMemory();
            p.setHandler(*Server, pointerRequest, pointerDestroyed, srv);
            srv.pointers.append(p);
            if (srv.ptr.focus) |id| if (srv.find(id)) |t| if (surfaceOf(t)) |sr| if (sr.getClient() == client)
                srv.enterPointer(p, t, sr);
        },
        // 터치는 아직 없다(capabilities에 없다). 묻는 클라이언트에게 아무 일도 안 하는 객체를 준다.
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

/// 커서 이미지는 합성하지 않는다 — terminal의 화살표를 계속 그린다. `set_cursor(NULL)`만 뜻이 있다: 그 클라이언트의 창
/// 위에서 화살표를 숨긴다(SDL_HideCursor — 게임 · 데모, 확정 10). 커서 surface의 commit은 역할 없는 surface로 받는다.
fn pointerRequest(p: *wl.Pointer, req: wl.Pointer.Request, srv: *Server) void {
    switch (req) {
        .release => p.destroy(),
        .set_cursor => |r| {
            const hidden = r.surface == null;
            for (srv.toplevels.items) |t| {
                if (t.resource.getClient() != p.getClient() or t.cursor_hidden == hidden) continue;
                t.cursor_hidden = hidden;
                logline.print("terminal: wl> cursor id={d} hidden={d}\n", .{ t.id, @intFromBool(hidden) });
            }
        },
    }
}

fn pointerDestroyed(p: *wl.Pointer, _: *Server) void {
    p.getLink().remove();
}

fn touchRequest(t: *wl.Touch, req: wl.Touch.Request, _: ?*anyopaque) void {
    switch (req) {
        .release => t.destroy(),
    }
}

// ── xdg_wm_base · xdg_positioner ───────────────────────────────────────

fn bindWmBase(client: *wl.Client, srv: *Server, version: u32, id: u32) void {
    const wm = xdg.WmBase.create(client, version, id) catch return client.postNoMemory();
    srv.wm_bases.append(srv.allocator, wm) catch {
        wm.destroy();
        return client.postNoMemory();
    };
    wm.setHandler(*Server, wmBaseRequest, wmBaseDestroyed, srv);
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
        // `Cmd+Q`의 ping에 답했다(확정 11) — 살아 있는 클라이언트다. 그 serial을 기다리던 창의 기한을 버린다.
        // close를 받고도 창을 안 닫는 것은 클라이언트의 선택이다(저장할지 묻는 창 등).
        .pong => |p| for (srv.toplevels.items) |t| {
            if (t.resource.getClient() == client) _ = t.deadline.pong(p.serial);
        },
    }
}

fn wmBaseDestroyed(wm: *xdg.WmBase, srv: *Server) void {
    for (srv.wm_bases.items, 0..) |x, i| if (x == wm) {
        _ = srv.wm_bases.swapRemove(i);
        break;
    };
}

/// 창의 `wl_surface`. xdg_surface나 surface가 먼저 사라졌으면 null이다.
fn surfaceOf(t: *Toplevel) ?*wl.Surface {
    const xs = t.xdg orelse return null;
    const s = xs.surface orelse return null;
    return s.resource;
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
    /// `Cmd+Q`의 2초 기한(단계 C)과 그때 잰 클라이언트의 pid.
    deadline: logic.Deadline = .{},
    pid: i32 = 0,
    /// 첫 commit 전에 `set_fullscreen`을 받았다(WY-M2 확정 3). `unset_fullscreen`이 지운다.
    want_fullscreen: bool = false,
    /// 놓인 자리와 그 크기(픽셀) — App이 정한다(`placeWorkspace` · `configureColumn`). 놓이기 전에는 null · 0이다.
    place: ?logic.Place = null,
    area_w: u32 = 0,
    area_h: u32 = 0,
    /// 마지막으로 보낸 configure(column의 같은 것 거르기).
    sent: ?Sent = null,
    /// 마지막으로 옮긴 자리(`paint`) — 포인터의 surface 좌표를 거꾸로 셀 때(단계 C).
    last_fit: ?logic.Fit = null,
    /// 이 창의 클라이언트가 `set_cursor(NULL)`을 보냈다(확정 10).
    cursor_hidden: bool = false,

    const Sig = struct { w: i32, h: i32, fit: logic.Fit, bs: u32 };
    const Sent = struct { w: u32, h: u32, act: bool };
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

/// configure 하나(WY-M0 확정 4 · WY-M2 확정 4). 자리(`t.place`)가 states를 고른다(`logic.toplevelStates` — 자기
/// workspace는 fullscreen · activated, column은 activated와 tiled 넷). 장식은 없다 — 장식 관리자가 늘 server_side라고
/// 답하고 서버는 아직 그리지 않는다(design 결정 25). `wm_capabilities`는 첫 configure에만.
fn sendConfigure(t: *Toplevel, w: u32, h: u32, act: bool) void {
    const xs = t.xdg orelse return;
    const place = t.place orelse return;
    if (t.sent == null and t.resource.getVersion() >= 5) {
        var caps = [_]u32{@intCast(@backingInt(xdg.Toplevel.WmCapabilities.fullscreen))};
        var arr: wl.Array = .{ .size = @sizeOf(@TypeOf(caps)), .alloc = @sizeOf(@TypeOf(caps)), .data = &caps };
        t.resource.sendWmCapabilities(&arr);
    }
    var buf: [6]u32 = undefined;
    const states = logic.toplevelStates(place, act, t.resource.getVersion(), &buf);
    var arr: wl.Array = .{ .size = states.len * @sizeOf(u32), .alloc = states.len * @sizeOf(u32), .data = states.ptr };
    t.resource.sendConfigure(@intCast(w), @intCast(h), &arr);
    xs.resource.sendConfigure(t.srv.display.nextSerial());
    const first = t.sent == null;
    t.sent = .{ .w = w, .h = h, .act = act };
    if (first) enterOutputs(t);
    logline.print("terminal: wl> configure id={d} w={d} h={d} act={d}\n", .{ t.id, w, h, @intFromBool(act) });
}

/// 창 메뉴 · 옮기기 · 크기 · 최대화 · 최소화 요청은 받기만 한다 — 크기는 서버가 정한다(자기 workspace는 화면, column은
/// pane). 전체 화면은 첫 commit 전의 것만 뜻이 있다(WY-M2 확정 3) — 그 뒤의 것은 받기만 한다(풀스크린으로 옮기기는
/// 결정 1의 다음 milestone 거리). 제목과 app id는 아직 안 쓴다.
fn toplevelRequest(res: *xdg.Toplevel, req: xdg.Toplevel.Request, t: *Toplevel) void {
    switch (req) {
        .destroy => res.destroy(),
        .set_fullscreen => t.want_fullscreen = true,
        .unset_fullscreen => t.want_fullscreen = false,
        else => {},
    }
}

// ── zxdg_decoration_manager_v1(WY-M2, design 결정 25) ───────────────────

fn bindDecorationManager(client: *wl.Client, _: *Server, version: u32, id: u32) void {
    const m = zxdg.DecorationManagerV1.create(client, version, id) catch return client.postNoMemory();
    m.setHandler(?*anyopaque, decorationManagerRequest, null, null);
}

/// 창마다 장식 객체 하나. 늘 `server_side`라고 답한다 — 클라이언트(SDL3 · libdecor)는 장식을 안 그리고, 서버는 아직
/// 장식을 그리지 않는다(M5). 답은 다음 `xdg_surface.configure`와 함께 적용된다 — 장식 객체는 보통 첫 commit 전에 생기고,
/// 그 첫 configure는 App이 자리를 정할 때 나간다.
fn decorationManagerRequest(m: *zxdg.DecorationManagerV1, req: zxdg.DecorationManagerV1.Request, _: ?*anyopaque) void {
    switch (req) {
        .destroy => m.destroy(),
        .get_toplevel_decoration => |r| {
            const d = zxdg.ToplevelDecorationV1.create(m.getClient(), m.getVersion(), r.id) catch return m.postNoMemory();
            d.setHandler(?*anyopaque, decorationRequest, null, null);
            d.sendConfigure(.server_side);
        },
    }
}

fn decorationRequest(d: *zxdg.ToplevelDecorationV1, req: zxdg.ToplevelDecorationV1.Request, _: ?*anyopaque) void {
    switch (req) {
        .destroy => d.destroy(),
        // 클라이언트가 바라는 것과 상관없이 server_side다(design 결정 25, R-WY-12).
        .set_mode, .unset_mode => d.sendConfigure(.server_side),
    }
}

fn toplevelDestroyed(_: *xdg.Toplevel, t: *Toplevel) void {
    const srv = t.srv;
    if (t.xdg) |xs| xs.toplevel = null;
    // 포커스 창이 사라졌다. surface가 같이 사라지므로 `leave`는 없다 — 클라이언트가 지운 것이다.
    if (srv.focused == t.id) {
        srv.focused = null;
        srv.held.clear();
        srv.sent_mods = null;
    }
    // 포인터도 같다 — leave 없이 포커스와 grab을 버린다.
    srv.ptr.drop(t.id);
    if (srv.ptr_under == t.id) srv.ptr_under = null;
    for (srv.toplevels.items, 0..) |x, i| if (x == t) {
        _ = srv.toplevels.swapRemove(i);
        break;
    };
    srv.push(.{ .gone = t.id });
    srv.allocator.destroy(t);
}

// ── wl_data_device_manager · wl_data_device · wl_data_source(WY-M4, design 결정 32 · 33) ──

/// 클라이언트의 source 하나. offer된 mime을 든다 — `logic.pickMime`이 그중에서 고른다. 서버가 source를 가리키는 자리는
/// `Server.sel_source`와 `Intake.source` 둘이고 둘 다 약한 참조다 — source가 사라지면 `sourceDestroyed`가 지운다.
const Source = struct {
    srv: *Server,
    resource: *wl.DataSource,
    mimes: std.ArrayList([]const u8) = .empty,
    /// `set_selection`에 한 번 쓰였다(xml: 다시 쓰면 `used_source`).
    used: bool = false,
};

/// 진행 중인 받기 하나(design 결정 33). 파이프의 읽기 끝(비블록)과 2초 기한이 서버의 epoll에 실려 있다.
const Intake = struct {
    srv: *Server,
    /// 쓰는 source. 받는 중에 사라지면 null이 되고 읽기는 계속한다 — 끝난 클라이언트의 쓰기 끝은 커널이 닫으므로 EOF가
    /// 오고, 받은 만큼을 쓴다(plan 확정 2 — `wl-copy`처럼 쓰고 곧 끝나는 프로그램과 가를 길이 없다).
    source: ?*Source,
    fd: i32,
    readable: *wl.EventSource,
    timer: *wl.EventSource,
    buf: std.ArrayList(u8) = .empty,
};

fn bindDataDeviceManager(client: *wl.Client, srv: *Server, version: u32, id: u32) void {
    const m = wl.DataDeviceManager.create(client, version, id) catch return client.postNoMemory();
    m.setHandler(*Server, dataDeviceManagerRequest, null, srv);
}

fn dataDeviceManagerRequest(m: *wl.DataDeviceManager, req: wl.DataDeviceManager.Request, srv: *Server) void {
    const client = m.getClient();
    switch (req) {
        .create_data_source => |r| {
            const res = wl.DataSource.create(client, m.getVersion(), r.id) catch return m.postNoMemory();
            const s = srv.allocator.create(Source) catch {
                res.destroy();
                return m.postNoMemory();
            };
            s.* = .{ .srv = srv, .resource = res };
            res.setHandler(*Source, sourceRequest, sourceDestroyed, s);
        },
        // seat은 하나다(`seat0`) — 어느 seat을 줘도 같은 장치다.
        .get_data_device => |r| {
            const dev = wl.DataDevice.create(client, m.getVersion(), r.id) catch return m.postNoMemory();
            dev.setHandler(*Server, dataDeviceRequest, dataDeviceDestroyed, srv);
            srv.data_devices.append(dev);
            // 포커스 클라이언트가 장치를 나중에 얻었다 — 이 장치에도 지금 selection(키보드의 늦은 `get_keyboard`와 같은 까닭).
            if (srv.focused) |id| if (srv.find(id)) |t| if (surfaceOf(t)) |sr| if (sr.getClient() == client)
                srv.offerDevice(dev);
        },
    }
}

fn dataDeviceRequest(dev: *wl.DataDevice, req: wl.DataDevice.Request, srv: *Server) void {
    switch (req) {
        .set_selection => |r| srv.setSelection(dev, if (r.source) |res| sourceOf(res) else null, r.serial),
        // drag-and-drop은 범위 밖이다(design 결정 32) — 받기만 하고 source를 곧바로 거둔다. origin · icon에 역할을 주지 않는다.
        .start_drag => |r| if (r.source) |res| res.sendCancelled(),
        .release => dev.destroy(),
    }
}

fn dataDeviceDestroyed(dev: *wl.DataDevice, _: *Server) void {
    dev.getLink().remove();
}

/// source resource의 우리 칸. `create_data_source`가 `setHandler`로 붙인 것이다.
fn sourceOf(res: *wl.DataSource) *Source {
    return @ptrCast(@alignCast(res.getUserData().?));
}

fn sourceRequest(res: *wl.DataSource, req: wl.DataSource.Request, s: *Source) void {
    switch (req) {
        .offer => |r| {
            const m = s.srv.allocator.dupe(u8, std.mem.span(r.mime_type)) catch return res.postNoMemory();
            s.mimes.append(s.srv.allocator, m) catch {
                s.srv.allocator.free(m);
                return res.postNoMemory();
            };
        },
        .destroy => res.destroy(),
    }
}

fn sourceDestroyed(_: *wl.DataSource, s: *Source) void {
    const srv = s.srv;
    if (srv.sel_source == s) srv.sel_source = null;
    if (srv.intake) |in| if (in.source == s) {
        in.source = null;
    };
    for (s.mimes.items) |m| srv.allocator.free(m);
    s.mimes.deinit(srv.allocator);
    srv.allocator.destroy(s);
}

/// 읽기 끝이 읽힌다. 비블록이라 EAGAIN까지 다 읽고 돌아간다. 0이면 EOF — 받기가 끝났다.
fn intakeReadable(fd: c_int, _: wl.EventMask, in: *Intake) c_int {
    const srv = in.srv;
    var chunk: [16384]u8 = undefined;
    while (true) {
        const n = linux.read(fd, &chunk, chunk.len);
        switch (linux.errno(n)) {
            .SUCCESS => {},
            .INTR => continue,
            .AGAIN => return 0,
            else => {
                srv.endIntake(.failed);
                return 0;
            },
        }
        if (n == 0) {
            srv.endIntake(.done);
            return 0;
        }
        if (in.buf.items.len + n > logic.SELECTION_MAX_BYTES) {
            srv.endIntake(.too_big);
            return 0;
        }
        in.buf.appendSlice(srv.allocator, chunk[0..n]) catch {
            srv.endIntake(.failed);
            return 0;
        };
    }
}

fn intakeTimeout(in: *Intake) c_int {
    in.srv.endIntake(.timeout);
    return 0;
}

// ── wl_data_offer와 남은 쓰기(WY-M4 단계 B, design 결정 34) ──────────────────

/// 서버가 만든 offer 하나. 만든 때의 사본 세대를 든다 — 사본이 바뀐 뒤의 `receive`는 fd만 닫는다.
const Offer = struct {
    srv: *Server,
    gen: u32,
};

fn offerRequest(res: *wl.DataOffer, req: wl.DataOffer.Request, o: *Offer) void {
    switch (req) {
        .receive => |r| o.srv.receive(o, res.getClient(), r.mime_type, r.fd),
        // drag-and-drop의 피드백이다(판 2) — selection에는 뜻이 없다.
        .accept => {},
        .destroy => res.destroy(),
    }
}

fn offerDestroyed(_: *wl.DataOffer, o: *Offer) void {
    o.srv.allocator.destroy(o);
}

/// 요청 처리기 안에서 다 못 쓴 `receive` 하나. 쓰기 끝(비블록)과 2초 기한이 서버의 epoll에 실려 있고, 끝나면 스스로 지운다.
const Outgo = struct {
    srv: *Server,
    fd: i32,
    buf: []u8,
    off: usize = 0,
    writable: *wl.EventSource,
    timer: *wl.EventSource,
};

/// 남은 쓰기를 끝낸다 — epoll source 둘을 지우고(`remove`는 그 복제 fd를 닫는다) 원래 fd를 닫는다.
fn endOutgo(out: *Outgo) void {
    const srv = out.srv;
    out.writable.remove();
    out.timer.remove();
    _ = linux.close(out.fd);
    srv.allocator.free(out.buf);
    srv.allocator.destroy(out);
}

fn outgoWritable(fd: c_int, _: wl.EventMask, out: *Outgo) c_int {
    const r = writeSome(fd, out.buf[out.off..]);
    out.off += r.n;
    if (r.broken) logline.print("terminal: wl> receive closed\n", .{});
    if (r.broken or out.off == out.buf.len) endOutgo(out);
    return 0;
}

fn outgoTimeout(out: *Outgo) c_int {
    logline.print("terminal: wl> receive timeout off={d} len={d}\n", .{ out.off, out.buf.len });
    endOutgo(out);
    return 0;
}
