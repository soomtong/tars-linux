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
//! - `tars_menu_manager_v1`을 창보다 먼저 bind한다 — 원래 모드라 Cmd가 Super로 온다(design 결정 8, WY 결정 46). 판 2(TK-M6 plan 확정 7)로
//!   bind하고 manager를 들고 있다가, `open`이 메뉴 모델(`Options.menu`)을 받으면 toplevel 뒤 · 첫 commit 앞에 `get_menu` + 모델 + commit을 보낸다
//!   (창이 처음 보일 때부터 바에 제목이 있다). 그 뒤의 비활성 바뀜은 `sendMenu`(매번 전체 — 서버는 증분이 없다). 모델이 서버의 상한을 넘으면
//!   보내지 않고 줄만(연결을 잃지 않는다), 서버가 판 1이면 조용히 건너뛴다. 고른 항목(`activated`)은 `input.Event.menu`로 올린다.
//! - 더티(TK-M1 plan 확정 5): 앱은 바뀐 사각형을 `invalidate(rect)`로 알린다(물리, 버퍼 좌표). 그릴 때 버퍼 나이(`age.zig`)로 이
//!   버퍼에 다시 그릴 사각형(repaint)을 셈해 `Frame.clip`으로 넘기고, 서버에는 이번 프레임의 더티(pending)만 `damage_buffer`
//!   사각형 하나로 보낸다 — 서버의 화면에는 지난 프레임이 이미 있다.
//! - 그리기는 이벤트 처리가 끝난 뒤 `run`의 루프에서만 일어난다. 그래서 `invalidate`는 적기만 하고, 앱이 콜백(키 · resize) 안에서
//!   레이어를 여러 번 바꿔도 한 프레임이 된다(그리는 중에 다시 그리기로 들어가는 일도 없다).
//! - 입력(TK-M2 plan 확정 1~3): Wayland의 키 · 포인터를 `tk_input.Event`로 바꿔 `Handler.input` 하나로 올린다. 키는 evdev 코드 표와
//!   서버가 채운 수정키 비트로 읽는다(xkb 없음 — input.zig 머리). 키 반복은 이 층의 몫이다(R-KEY-2, `repeat.zig`) — 그래서 대기는
//!   `display.dispatch()`가 아니라 연결 fd와 timerfd 둘의 `poll`이다. 포인터는 `wl_pointer.frame` 하나에 이벤트 하나.
//!
//! 이 층은 창 층이다(R-ARCH-1의 맨 아래) — 그리는 법(CG)을 모른다. 넘기는 것은 픽셀 판 · 임시 판 · clip이고 판을 z2d로 감싸는
//! 것은 위 층의 일이다.
//!
//! - 텍스트 입력 · 클립보드(TK-M4 plan 확정 9 · 12): `zwp_text_input_v3` 하나와 `wl_data_device` 하나를 창보다 먼저 얻는다(첫 포커스의 `enter` ·
//!   `selection`을 놓치지 않는다). 켜고 끄는 것은 `setTextInput`(앱 · kit의 훅이 부른다), 셈은 순수 상태 기계 `ime.zig`. 복사 `copyText`는 source 하나에
//!   mime 넷을 offer하고 마지막 키 · 버튼의 serial로 `set_selection` — 서버가 그 자리에서 `send`로 읽어 간다(WY 결정 33). 붙여넣기 `pasteText`는
//!   동기다: 지금 offer에 `receive` → flush → 쓰기 끝을 닫고 읽기 끝을 1초씩 poll. offer는 늘 서버 사본이라 자기 복사를 붙여도 교착이 없다.
//!   SIGPIPE는 무시한다(서버가 기한으로 읽기 끝을 닫은 뒤 쓰면 앱이 죽지 않게).
//!
//! 줄(design 결정 12): `tk> configure w= h= scale=` · `tk> draw w= h= dirty=x,y,w,h us= age=` (+ damage가 dirty와 다르면 ` damage=x,y,w,h`) ·
//! `tk> commit` · `tk> key code= state=`(반복이면 끝에 ` repeat=1`) · `tk> native` · `tk> close`, TK-M4: `tk> ti enter|leave|enable|disable` ·
//! `tk> ime commit= preedit= serial= match=` · `tk> copy len= serial=` · `tk> send mime= len= us=` · `tk> cancelled` · `tk> offer mimes=`|`offer none` ·
//! `tk> paste len= us=`(없으면 `paste none`), TK-M6: `tk> menu sent menus= items=` · `tk> menu activated id=` · `tk> menu unsupported` ·
//! `tk> menu error=` · `tk> quit`. `dirty=`는 이 버퍼에 다시 그린 사각형(`us`가 잰 것), `age=`는 이 버퍼가
//! 마지막으로 그려진 뒤 지난 프레임 수(새 버퍼면 0 — 통째). 표준 출력에 버퍼 없이 쓴다(게이트가 `> 파일`로 받는다 — tars-wl-test와 같다).

const std = @import("std");
const linux = std.os.linux;
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const tars = wayland.client.tars;
const zwp = wayland.client.zwp;
pub const Rect = @import("tk_geom").Rect;
const Age = @import("age.zig").Age;
const Repeat = @import("repeat.zig").Repeat;
const Ime = @import("ime.zig").Ime;
const clipboard = @import("clip.zig");
pub const input = @import("tk_input");
pub const menu = @import("tk_menu");

/// 서버가 내는 판(WY design 결정 5 · 27 · 46)을 넘지 않는다.
const COMPOSITOR_VERSION: u32 = 6;
const SHM_VERSION: u32 = 1;
const SEAT_VERSION: u32 = 7;
const WM_BASE_VERSION: u32 = 5;
/// 판 2 — 메뉴 모델(`get_menu`, TK-M6). 판 1 서버면 `@min`이 1로 bind해 원래 모드만 쓴다.
const MENU_MANAGER_VERSION: u32 = 2;
const TEXT_INPUT_MANAGER_VERSION: u32 = 1;
const DATA_DEVICE_MANAGER_VERSION: u32 = 2;
/// 복사로 들고 있는 글의 상한(경로 · 필드 — 파이프 64 KiB에 다 들어 블록 쓰기가 멈추지 않는다).
pub const COPY_MAX: usize = 4096;

extern "c" fn pipe2(fds: *[2]c_int, flags: c_int) c_int;
const O_CLOEXEC: c_int = 0o2000000;

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
/// 크기를 맞추는 자리다(R-TKW-2). `input`은 키 · 키보드 포커스 · 포인터 · 휠(`tk_input.Event`). 없어도 된다.
pub const Handler = struct {
    ctx: *anyopaque,
    draw: *const fn (ctx: *anyopaque, frame: Frame) anyerror!void,
    resize: ?*const fn (ctx: *anyopaque, width: u32, height: u32, scale: u32) void = null,
    /// 애니메이션의 시계(TK-M1 plan 확정 6). 그릴 수 있을 때(configure 뒤, frame을 기다리지 않음, 빈 버퍼가 있음)마다 그리기 바로 앞에서
    /// monotonic 시각(ns)으로 부른다 — 그래서 값을 바꾼 tick 하나 뒤에는 늘 그림 하나가 따르고, 그 그림의 frame 콜백이 다음 tick을
    /// 부른다. 앱은 바뀐 것이 없으면 아무것도 안 하면 된다(idle commit 0).
    tick: ?*const fn (ctx: *anyopaque, now_ns: u64) void = null,
    input: ?*const fn (ctx: *anyopaque, ev: input.Event) void = null,
    /// 바쁘지 않을 때의 일 한 조각(TK-M3 plan 확정 9 — 디렉터리 로딩의 getdents 한 번). `run`의 한 바퀴마다 이벤트 처리 · 반복 뒤에
    /// 부르고, 참(할 일이 더 있다)이면 다음 대기를 0으로 해 곧 다시 부른다 — 그 사이 키 · configure · 그리기는 늘 먼저 돈다. 없거나 거짓이면
    /// 지금처럼 이벤트가 올 때까지 잔다(idle commit 0).
    idle: ?*const fn (ctx: *anyopaque) bool = null,
};

/// `open`의 선택 인자(TK-M6). `menu`가 있으면 첫 commit 앞에 보낸다 — `disabled`는 그때의 비활성(kit `Root.disabled`).
pub const Options = struct {
    menu: ?*const menu.Model = null,
    disabled: ?*const menu.Disabled = null,
};

// ── 버퍼 ───────────────────────────────────────────────────────────

/// `wl_pointer.frame` 하나에 모은 것(TK-M2 plan 확정 3). frame에서 차례로 올린다: 움직임 · 버튼 · 휠 · 나감.
const PointerPending = struct {
    motion: bool = false,
    button: ?struct { code: u32, pressed: bool } = null,
    dy: f32 = 0,
    discrete: i32 = 0,
    axis: bool = false,
    leave: bool = false,
};

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
    menu_manager: ?*tars.MenuManagerV1 = null,
    /// 이 창의 메뉴 객체와 그 모델(보낸 뒤 — `sendMenu`가 다시 쓴다).
    menu_obj: ?*tars.MenuV1 = null,
    menu_model: ?*const menu.Model = null,
    keyboard: ?*wl.Keyboard = null,
    pointer: ?*wl.Pointer = null,
    text_input_manager: ?*zwp.TextInputManagerV3 = null,
    data_device_manager: ?*wl.DataDeviceManager = null,
    text_input: ?*zwp.TextInputV3 = null,
    data_device: ?*wl.DataDevice = null,
    ime: Ime = .{},
    /// 마지막 키 · 키보드 enter · 버튼의 serial(`set_selection`에 — 서버는 값을 안 보지만 xml의 뜻대로).
    serial: u32 = 0,
    /// 지금 selection offer와 그 mime 비트(`clip.bit`). 막 온 offer(아직 `selection` 전)는 따로.
    offer: ?*wl.DataOffer = null,
    offer_mask: u8 = 0,
    new_offer: ?*wl.DataOffer = null,
    new_mask: u8 = 0,
    /// 내가 낸 selection과 그 글.
    source: ?*wl.DataSource = null,
    copy_buf: [COPY_MAX]u8 = undefined,
    copy_len: usize = 0,
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

    /// 지금 수정키(`modifiers`가 바꾼다)와 키 반복, 반복의 타이머.
    mods: input.Mods = .{},
    repeat: Repeat = .{},
    timer_fd: i32 = -1,
    /// 포인터: 마지막 자리(surface 논리 좌표)와 이번 `frame`까지 모은 것.
    ptr_x: f32 = 0,
    ptr_y: f32 = 0,
    ptr_pending: PointerPending = .{},

    const Slot = struct { win: *Window, index: usize };

    /// 붙고 창을 연다. 첫 commit(버퍼 없음)까지 보낸다 — 첫 configure가 오면 `run`이 그린다. `title`은 app id로도 쓴다.
    pub fn open(alloc: std.mem.Allocator, title: [*:0]const u8, handler: Handler, opts: Options) !*Window {
        const display = try wl.Display.connect(null);
        errdefer display.disconnect();
        const registry = try display.getRegistry();
        const win = try alloc.create(Window);
        win.* = .{ .alloc = alloc, .handler = handler, .display = display, .registry = registry };
        for (&win.slots, 0..) |*s, i| s.* = .{ .win = win, .index = i };
        errdefer alloc.destroy(win);
        const tfd = linux.timerfd_create(.MONOTONIC, .{ .CLOEXEC = true, .NONBLOCK = true });
        if (linux.errno(tfd) != .SUCCESS) return error.TimerfdFailed;
        win.timer_fd = @intCast(tfd);
        errdefer _ = linux.close(win.timer_fd);
        registry.setListener(*Window, registryListener, win);
        if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;
        ignoreSigpipe();

        const compositor = win.compositor orelse return error.NoCompositor;
        _ = win.shm orelse return error.NoShm;
        const wm_base = win.wm_base orelse return error.NoXdgWmBase;

        // 원래 모드(design 결정 8). 창보다 먼저 — 첫 포커스의 modifiers부터 Super로 받는다.
        if (win.menu_global) |mg| {
            win.menu_manager = try registry.bind(mg.name, tars.MenuManagerV1, @min(mg.version, MENU_MANAGER_VERSION));
            say("native", .{});
        }

        win.surface = try compositor.createSurface();
        win.surface.setListener(*Window, surfaceListener, win);
        wm_base.setListener(*Window, wmBaseListener, win);
        if (win.seat) |seat| {
            seat.setListener(*Window, seatListener, win);
            // 텍스트 입력 · 클립보드 장치(TK-M4) — 창보다 먼저(첫 포커스의 `enter` · `selection`을 놓치지 않는다).
            if (win.text_input_manager) |m| {
                const ti = try m.getTextInput(seat);
                ti.setListener(*Window, textInputListener, win);
                win.text_input = ti;
            }
            if (win.data_device_manager) |m| {
                const dev = try m.getDataDevice(seat);
                dev.setListener(*Window, dataDeviceListener, win);
                win.data_device = dev;
            }
        }
        // seat capabilities를 받아 `get_keyboard`를 첫 commit보다 먼저 보낸다(tars-wl-test와 같은 까닭 — 첫 키를 놓치지 않는다).
        if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

        win.xdg_surface = try wm_base.getXdgSurface(win.surface);
        win.xdg_surface.setListener(*Window, xdgSurfaceListener, win);
        win.toplevel = try win.xdg_surface.getToplevel();
        win.toplevel.setListener(*Window, toplevelListener, win);
        win.toplevel.setTitle(title);
        win.toplevel.setAppId(title);
        if (opts.menu) |m| try win.startMenu(m, opts.disabled);
        win.surface.commit();
        return win;
    }

    /// 메뉴 객체를 얻고 첫 모델을 보낸다(첫 commit 앞). 서버가 판 1이거나 global이 없으면 `tk> menu unsupported`, 상한을 넘으면 `tk> menu error=`.
    fn startMenu(self: *Window, m: *const menu.Model, disabled: ?*const menu.Disabled) !void {
        const mgr = self.menu_manager orelse return say("menu unsupported", .{});
        if (mgr.getVersion() < 2) return say("menu unsupported", .{});
        m.check() catch |e| return say("menu error={s}", .{@errorName(e)});
        const obj = try mgr.getMenu(self.toplevel);
        obj.setListener(*Window, menuListener, self);
        self.menu_obj = obj;
        self.menu_model = m;
        const none: menu.Disabled = .empty;
        self.sendMenu(disabled orelse &none);
    }

    /// 모델 전체를 다시 보낸다(비활성이 바뀐 때 — kit `Root`의 훅). 메뉴 객체가 없으면 아무것도.
    pub fn sendMenu(self: *Window, disabled: *const menu.Disabled) void {
        const obj = self.menu_obj orelse return;
        const m = self.menu_model orelse return;
        var sink: MenuSink = .{ .obj = obj };
        menu.emit(m, disabled, &sink);
        say("menu sent menus={d} items={d}", .{ m.menus.len, m.entryCount() });
    }

    /// 앱이 스스로 끝낸다(메뉴의 "끝내기" — 서버의 `close`와 같은 끝).
    pub fn quit(self: *Window) void {
        say("quit", .{});
        self.running = false;
    }

    /// 버퍼 · 임시 판 · 연결을 놓고 창을 지운다(`open`의 짝). 프로세스가 곧 끝나도 부른다 — allocator의 누수 검사(ReleaseSafe)가
    /// 끝날 때 셸에 줄을 쏟지 않게.
    pub fn deinit(self: *Window) void {
        for (&self.bufs) |*b| b.destroy();
        if (self.scratch.len != 0) self.alloc.free(self.scratch);
        if (self.timer_fd >= 0) _ = linux.close(self.timer_fd);
        self.display.disconnect();
        self.alloc.destroy(self);
    }

    /// close를 받을 때까지 이벤트를 돈다. 그리기는 이벤트 묶음(configure · done · release · 키)을 처리한 뒤 여기서만 일어난다.
    ///
    /// 한 바퀴(TK-M2 plan 확정 2): 그릴 것을 그리고 → `prepareRead`(큐에 이미 있으면 그것부터 처리하고 다시) → `flush`(그린 요청을
    /// 보낸다) → 반복의 시각으로 timerfd를 맞추고 → 연결 fd와 timerfd를 `poll` → 읽을 것이 있으면 `readEvents`, 아니면 `cancelRead`
    /// → `dispatchPending` → 반복 하나 → `Handler.idle` 한 조각(참이면 다음 poll의 시간 제한 0, TK-M3). libwayland의 `dispatch()`가 하던 일
    /// (flush · 기다림 · 읽기 · 처리)에 타이머와 idle을 끼운 모양이다.
    pub fn run(self: *Window) !void {
        const fd = self.display.getFd();
        // `Handler.idle`이 참을 돌려줬다 — 다음 poll은 기다리지 않는다.
        var busy = false;
        while (self.running) {
            self.maybeDraw();
            if (!self.running) break;
            if (!self.display.prepareRead()) {
                if (self.display.dispatchPending() != .SUCCESS) return error.DispatchFailed;
                continue;
            }
            // 보낼 것이 소켓에 다 안 들어갔으면(AGAIN) 쓸 수 있을 때도 깬다.
            const fl = self.display.flush();
            const want_out = fl == .AGAIN;
            if (fl != .SUCCESS and !want_out) {
                self.display.cancelRead();
                return error.DispatchFailed;
            }
            self.armTimer();
            var fds = [2]linux.pollfd{
                .{ .fd = fd, .events = linux.POLL.IN | (if (want_out) @as(i16, linux.POLL.OUT) else 0) },
                .{ .fd = self.timer_fd, .events = linux.POLL.IN },
            };
            const rc = linux.poll(&fds, fds.len, if (busy) 0 else -1);
            if (linux.errno(rc) != .SUCCESS) {
                self.display.cancelRead();
                if (linux.errno(rc) == .INTR) continue;
                return error.PollFailed;
            }
            if (fds[0].revents & (linux.POLL.IN | linux.POLL.ERR | linux.POLL.HUP) != 0) {
                if (self.display.readEvents() != .SUCCESS) return error.DispatchFailed;
            } else {
                self.display.cancelRead();
            }
            if (fds[1].revents & linux.POLL.IN != 0) {
                var n: u64 = 0;
                _ = linux.read(self.timer_fd, @ptrCast(&n), 8);
            }
            if (self.display.dispatchPending() != .SUCCESS) return error.DispatchFailed;
            // 읽은 이벤트를 먼저 처리한다 — 같은 깨움에 뗌이 함께 왔으면 반복은 이미 멈췄다(뗀 키를 한 번 더 내지 않는다).
            self.fireRepeat();
            busy = if (self.handler.idle) |f| f(self.handler.ctx) else false;
        }
        if (self.failed) return error.DrawFailed;
    }

    /// timerfd를 반복의 다음 시각(monotonic 절대 시각)에 맞춘다. 반복이 없으면 끈다(0).
    fn armTimer(self: *Window) void {
        var spec: linux.itimerspec = .{ .it_interval = .{ .sec = 0, .nsec = 0 }, .it_value = .{ .sec = 0, .nsec = 0 } };
        if (self.repeat.deadline()) |d| {
            // 0은 "끈다"라 이미 지난 시각도 1 ns 뒤로.
            const t = @max(d, 1);
            spec.it_value = .{ .sec = @intCast(t / std.time.ns_per_s), .nsec = @intCast(t % std.time.ns_per_s) };
        }
        _ = linux.timerfd_settime(self.timer_fd, .{ .ABSTIME = true }, &spec, null);
    }

    /// 반복할 때가 됐으면 키 하나(`repeat = true`)를 올린다 — 많아야 하나(repeat.zig).
    fn fireRepeat(self: *Window) void {
        const code = self.repeat.fire(nowNs()) orelse return;
        say("key code={d} state=1 repeat=1", .{code});
        self.emit(.{ .key = .{ .code = code, .key = input.keyFromCode(code), .pressed = true, .repeat = true, .mods = self.mods } });
    }

    fn emit(self: *Window, ev: input.Event) void {
        if (self.handler.input) |f| f(self.handler.ctx, ev);
    }

    // ── 텍스트 입력 · 클립보드(TK-M4) ────────────────────────────────────

    /// text-input을 켜 달라(참) · 꺼 달라(거짓) — first responder가 텍스트 필드인가(kit `Root`의 훅이 부른다, design 결정 8).
    pub fn setTextInput(self: *Window, on: bool) void {
        if (self.ime.setWant(on)) |en| self.sendEnable(en);
    }

    fn sendEnable(self: *Window, on: bool) void {
        const ti = self.text_input orelse return;
        if (on) {
            ti.enable();
            ti.setContentType(.{}, .normal);
        } else ti.disable();
        ti.commit();
        self.ime.sent();
        say("ti {s}", .{if (on) "enable" else "disable"});
    }

    /// 글을 클립보드로(복사). source 하나에 mime 넷, 마지막 serial로 `set_selection`. 서버가 곧 `send`로 읽어 간다.
    pub fn copyText(self: *Window, bytes: []const u8) void {
        const dev = self.data_device orelse return say("copy no-device", .{});
        const mgr = self.data_device_manager orelse return;
        const n = @min(bytes.len, COPY_MAX);
        const src = mgr.createDataSource() catch return say("copy no-source", .{});
        if (self.source) |old| old.destroy();
        @memcpy(self.copy_buf[0..n], bytes[0..n]);
        self.copy_len = n;
        self.source = src;
        src.setListener(*Window, sourceListener, self);
        for (clipboard.MIMES) |m| src.offer(m.ptr);
        dev.setSelection(src, self.serial);
        say("copy len={d} serial={d}", .{ n, self.serial });
    }

    /// 지금 selection을 `buf`에 받는다(동기 — 파일 머리). 없거나 실패하면 null.
    pub fn pasteText(self: *Window, buf: []u8) ?[]const u8 {
        const o = self.offer orelse {
            say("paste none", .{});
            return null;
        };
        const mime = clipboard.pick(self.offer_mask) orelse {
            say("paste none", .{});
            return null;
        };
        const t0 = nowNs();
        var fds: [2]c_int = undefined;
        if (pipe2(&fds, O_CLOEXEC) != 0) return null;
        o.receive(mime.ptr, fds[1]);
        _ = self.display.flush();
        _ = linux.close(fds[1]);
        defer _ = linux.close(fds[0]);
        var n: usize = 0;
        while (n < buf.len) {
            var pfd = [1]linux.pollfd{.{ .fd = fds[0], .events = linux.POLL.IN, .revents = 0 }};
            const rc = linux.poll(&pfd, 1, 1000);
            if (linux.errno(rc) == .INTR) continue;
            if (linux.errno(rc) != .SUCCESS or rc == 0) break;
            const r = linux.read(fds[0], buf[n..].ptr, buf.len - n);
            if (linux.errno(r) == .INTR) continue;
            if (linux.errno(r) != .SUCCESS or r == 0) break;
            n += r;
        }
        say("paste len={d} us={d}", .{ n, (nowNs() - t0) / std.time.ns_per_us });
        return buf[0..n];
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

/// `menu.emit`의 받는 쪽 — 글을 NUL 끝 칸에 옮겨 `tars_menu_v1` 요청으로(글은 `check`가 64바이트 이하로 걸렀다).
const MenuSink = struct {
    obj: *tars.MenuV1,

    fn z(buf: *[menu.MAX_TEXT + 1]u8, t: []const u8) [*:0]const u8 {
        const n = @min(t.len, menu.MAX_TEXT);
        @memcpy(buf[0..n], t[0..n]);
        buf[n] = 0;
        return buf[0..n :0].ptr;
    }

    pub fn addMenu(self: *MenuSink, title: []const u8) void {
        var buf: [menu.MAX_TEXT + 1]u8 = undefined;
        self.obj.addMenu(z(&buf, title));
    }

    pub fn addItem(self: *MenuSink, id: u32, label: []const u8, mods: u32, key: u32, disabled: bool) void {
        var buf: [menu.MAX_TEXT + 1]u8 = undefined;
        self.obj.addItem(id, z(&buf, label), mods, key, .{ .disabled = disabled });
    }

    pub fn addSeparator(self: *MenuSink) void {
        self.obj.addSeparator();
    }

    pub fn commit(self: *MenuSink) void {
        self.obj.commit();
    }
};

/// 서버가 고른 항목을 알렸다 — 줄과 `Event.menu`.
fn menuListener(_: *tars.MenuV1, event: tars.MenuV1.Event, win: *Window) void {
    switch (event) {
        .activated => |a| {
            say("menu activated id={d}", .{a.id});
            win.emit(.{ .menu = a.id });
        },
    }
}

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
            } else if (std.mem.eql(u8, name, std.mem.span(zwp.TextInputManagerV3.interface.name))) {
                win.text_input_manager = registry.bind(global.name, zwp.TextInputManagerV3, @min(global.version, TEXT_INPUT_MANAGER_VERSION)) catch return;
            } else if (std.mem.eql(u8, name, std.mem.span(wl.DataDeviceManager.interface.name))) {
                win.data_device_manager = registry.bind(global.name, wl.DataDeviceManager, @min(global.version, DATA_DEVICE_MANAGER_VERSION)) catch return;
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
                win.repeat.stop();
            }
            // 포인터(TK-M2, 요구사항 결정 11 — 클릭 선택과 휠 스크롤). `set_cursor`는 보내지 않는다 — 서버가 terminal의 화살표를 그린다.
            if (c.capabilities.pointer and win.pointer == null) {
                const p = seat.getPointer() catch return;
                p.setListener(*Window, pointerListener, win);
                win.pointer = p;
            } else if (!c.capabilities.pointer and win.pointer != null) {
                win.pointer.?.release();
                win.pointer = null;
            }
        },
        .name => {},
    }
}

/// 키는 줄 하나와 `Handler.input`. 키맵 fd는 닫는다 — 서버의 키맵은 고정 us · pc105 텍스트이고 수정키 비트를 서버가 직접 채우므로
/// (R-WY-7) evdev 코드 표(`tk_input`)로 읽으면 서버가 뜻한 그대로다(TK design 결정 13 — xkb 없음, initrd에 libxkbcommon도 없다).
fn keyboardListener(_: *wl.Keyboard, event: wl.Keyboard.Event, win: *Window) void {
    switch (event) {
        .keymap => |k| _ = linux.close(k.fd),
        .key => |k| {
            win.serial = k.serial;
            const pressed = k.state == .pressed;
            say("key code={d} state={d}", .{ k.key, @intFromBool(pressed) });
            if (pressed) win.repeat.press(k.key, input.repeats(k.key), nowNs()) else win.repeat.release(k.key);
            win.emit(.{ .key = .{ .code = k.key, .key = input.keyFromCode(k.key), .pressed = pressed, .mods = win.mods } });
        },
        .modifiers => |m| win.mods = input.modsFromMask(m.mods_depressed | m.mods_latched, m.mods_locked),
        .repeat_info => |r| win.repeat.setInfo(r.rate, r.delay),
        // 서버는 enter의 눌린 키 목록을 비워 보낸다(R-KEY-7). 떠나면 반복을 멈춘다.
        .enter => |e| {
            win.serial = e.serial;
            win.emit(.{ .focus = true });
        },
        .leave => {
            win.repeat.stop();
            win.mods = .{};
            win.emit(.{ .focus = false });
        },
    }
}

/// 포인터. 이벤트를 모았다가 `frame`에서 올린다(TK-M2 plan 확정 3). 좌표는 surface 논리 좌표(wl_fixed) — 레이어 frame과 같은 단위다.
/// 서버는 seat 판 5 이상에 늘 `frame`을 보낸다(terminal `server.zig`의 pointer 함수들).
fn pointerListener(_: *wl.Pointer, event: wl.Pointer.Event, win: *Window) void {
    const pp = &win.ptr_pending;
    switch (event) {
        .enter => |e| {
            win.ptr_x = @floatCast(e.surface_x.toDouble());
            win.ptr_y = @floatCast(e.surface_y.toDouble());
            pp.motion = true;
            pp.leave = false;
        },
        .motion => |m| {
            win.ptr_x = @floatCast(m.surface_x.toDouble());
            win.ptr_y = @floatCast(m.surface_y.toDouble());
            pp.motion = true;
        },
        .leave => pp.leave = true,
        .button => |b| {
            win.serial = b.serial;
            pp.button = .{ .code = b.button, .pressed = b.state == .pressed };
        },
        .axis => |a| if (a.axis == .vertical_scroll) {
            pp.dy += @floatCast(a.value.toDouble());
            pp.axis = true;
        },
        .axis_discrete => |d| if (d.axis == .vertical_scroll) {
            pp.discrete += d.discrete;
        },
        .frame => {
            const x = win.ptr_x;
            const y = win.ptr_y;
            const p = pp.*;
            pp.* = .{};
            if (p.motion) win.emit(.{ .pointer_motion = .{ .x = x, .y = y } });
            if (p.button) |b| win.emit(.{ .button = .{ .code = b.code, .pressed = b.pressed, .x = x, .y = y } });
            if (p.axis) win.emit(.{ .scroll = .{ .dy = p.dy, .discrete = p.discrete, .x = x, .y = y } });
            if (p.leave) win.emit(.pointer_leave);
        },
        else => {},
    }
}

// ── 텍스트 입력 · 클립보드(TK-M4) ─────────────────────────────────────

fn ignoreSigpipe() void {
    const act: linux.Sigaction = .{
        .handler = .{ .handler = linux.SIG.IGN },
        .mask = linux.sigemptyset(),
        .flags = 0,
    };
    _ = linux.sigaction(.PIPE, &act, null);
}

fn span(t: ?[*:0]const u8) []const u8 {
    return if (t) |x| std.mem.span(x) else "";
}

/// text_input 이벤트(plan 확정 9): enter · leave는 상태 기계에, preedit · commit은 모았다가 `done`에서 이벤트 하나로.
fn textInputListener(_: *zwp.TextInputV3, event: zwp.TextInputV3.Event, win: *Window) void {
    switch (event) {
        .enter => {
            say("ti enter", .{});
            if (win.ime.enter()) |en| win.sendEnable(en);
        },
        .leave => {
            say("ti leave", .{});
            win.ime.leave();
        },
        .preedit_string => |e| win.ime.preedit(span(e.text)),
        .commit_string => |e| win.ime.commitString(span(e.text)),
        .delete_surrounding_text => {},
        .done => |e| {
            const d = win.ime.done(e.serial);
            say("ime commit={s} preedit={s} serial={d} match={d}", .{ d.commit, d.preedit, d.serial, @intFromBool(d.match) });
            win.emit(.{ .ime = .{ .commit = d.commit, .preedit = d.preedit } });
        },
    }
}

/// 서버의 offer. `data_offer` 뒤에 `offer`들, 그 뒤 `selection`이 그것을 selection으로 정한다(xml). 옛 offer는 지운다.
fn dataDeviceListener(_: *wl.DataDevice, event: wl.DataDevice.Event, win: *Window) void {
    switch (event) {
        .data_offer => |d| {
            if (win.new_offer) |old| if (old != win.offer) old.destroy();
            win.new_offer = d.id;
            win.new_mask = 0;
            d.id.setListener(*Window, offerListener, win);
        },
        .selection => |s| {
            if (win.offer) |old| if (s.id != old) old.destroy();
            win.offer = s.id;
            win.offer_mask = if (s.id != null and s.id == win.new_offer) win.new_mask else 0;
            win.new_offer = null;
            if (s.id == null) return say("offer none", .{});
            var names: [96]u8 = undefined;
            var n: usize = 0;
            for (clipboard.MIMES) |m| if (win.offer_mask & clipboard.bit(m) != 0) {
                if (n != 0 and n < names.len) {
                    names[n] = ',';
                    n += 1;
                }
                const k = @min(m.len, names.len - n);
                @memcpy(names[n .. n + k], m[0..k]);
                n += k;
            };
            say("offer mimes={s}", .{names[0..n]});
        },
        else => {},
    }
}

fn offerListener(o: *wl.DataOffer, event: wl.DataOffer.Event, win: *Window) void {
    switch (event) {
        .offer => |e| if (o == win.new_offer) {
            win.new_mask |= clipboard.bit(std.mem.span(e.mime_type));
        },
    }
}

/// 서버가 내 selection을 청했다(`send`) — 그 자리에서 쓰고 닫는다(블록 파이프 · 4096 이하라 멈추지 않는다).
fn sourceListener(src: *wl.DataSource, event: wl.DataSource.Event, win: *Window) void {
    switch (event) {
        .send => |e| {
            const t0 = nowNs();
            const n = if (src == win.source) win.copy_len else 0;
            writeAll(e.fd, win.copy_buf[0..n]);
            _ = linux.close(e.fd);
            say("send mime={s} len={d} us={d}", .{ e.mime_type, n, (nowNs() - t0) / std.time.ns_per_us });
        },
        .cancelled => {
            say("cancelled", .{});
            if (src == win.source) win.source = null;
            src.destroy();
        },
        .target => {},
    }
}
