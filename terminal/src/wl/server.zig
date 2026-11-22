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
const zwp = wayland.server.zwp;
const tars = wayland.server.tars;
const logic = @import("../wl_logic.zig");
const logline = @import("../logline.zig");
const menubar = @import("../menubar.zig");

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
/// 한글 IME(WY-M5, design 결정 38). 판 1뿐이다.
const TEXT_INPUT_MANAGER_VERSION = 1;
/// subsurface(WY-M7, design 결정 48). 판 1이 유일한 판이다.
const SUBCOMPOSITOR_VERSION = 1;
/// 원래 모드의 문(WY-M6, design 결정 46). 판 1은 `destroy` 하나 — bind가 곧 "Cmd를 Super로 받는다"다. 판 2(TK-M5, plan 확정 3)가
/// 메뉴 모델(`get_menu` · `tars_menu_v1`)을 더한다. 판 1로 bind한 클라이언트는 그대로 원래 모드이고 모델이 없다(바에 이름만).
const MENU_MANAGER_VERSION = 2;

/// title · app_id의 상한(TK-M5 plan 확정 4) — 넘으면 UTF-8 경계에서 자른다.
const NAME_BYTES = 64;
/// `wl> title` 줄의 창마다 상한(plan 확정 4) — Chromium처럼 탭마다 제목을 바꾸는 창이 로그를 불리지 않게. CR-M2가 4에서 16으로
/// 올렸다(browser 체인이 한 창에서 페이지를 여섯 넘게 연다 — 다섯째 제목부터 줄이 안 나왔다).
const TITLE_LINES: u8 = 16;
/// `wl> menu` 줄의 창마다 상한(plan 확정 14).
const MENU_LINES: u8 = 8;
/// `wl> subsurface` 줄의 창마다 상한(WY-M7 확정 2) — 만들기 · 매핑 · 해제 · 닫기만 찍는다. Chromium의 bubble은 주소창에 글자를 칠 때마다 넷이다.
const SUB_LINES: u8 = 24;
/// `wl> tree` 줄(자식을 섞은 옮기기의 시간 — WY-M7 실측 1)의 창마다 상한.
const TREE_LINES: u8 = 16;
/// `wl> popup` 줄의 창마다 상한(WY-M7 단계 B). Chromium은 단추 위에 머물 때마다 툴팁 popup을 만들고 지운다.
const POP_LINES: u8 = 64;

/// 파이프의 깃발(값은 asm-generic/fcntl.h — x86_64도 같다). 받기의 읽기 끝만 비블록이다 — epoll이 깨운 만큼만 읽는다.
/// `pipe2`에 O_NONBLOCK을 주면 클라이언트가 받는 쓰기 끝까지 비블록이 되어, EAGAIN을 다루지 않는 클라이언트가 64 KiB를
/// 넘는 글을 조용히 잘라 쓴다. 그래서 쓰기 끝은 보통 파이프로 두고 읽기 끝에만 `F_SETFL`로 건다.
const O_NONBLOCK: usize = 0o4000;
const O_CLOEXEC: c_int = 0o2000000;
const F_SETFL = 4;
const F_GETFL = 3;

/// Cmd 키(evdev `KEY_LEFTMETA` · `KEY_RIGHTMETA`). 호환 창에는 이 둘의 key 이벤트를 안 보낸다(design 결정 54).
const KEY_LEFTMETA: u16 = 125;
const KEY_RIGHTMETA: u16 = 126;

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

/// `Server.damageFor`의 답(WY-M6 단계 B, design 결정 47). `part`는 화면(프레임버퍼) 좌표의 사각형이다.
pub const Damage = union(enum) {
    whole,
    none,
    part: logic.Area,
};

/// `wl> blit` 줄의 창마다 상한(WY-M6 확정 7). 통째는 둘(첫 그림과 그다음 — 체인의 창마다 두 줄), 부분은 판정 30의 `--damage` 창
/// 하나가 다 찍히도록 열여섯.
const BLIT_WHOLE_LINES: u8 = 2;
const BLIT_PART_LINES: u8 = 16;

/// 단조 시계(ns) — `wl> blit`의 `us=`. 서버는 `std.Io`를 들지 않아 시스템 콜을 바로 부른다.
fn monoNs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

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
    /// 매핑된 창이 `set_fullscreen`(`on`) · `unset_fullscreen`을 보냈다(CR-M2, WY design 결정 56) — Chromium의 F11. App이 자리를
    /// 정한다: column이면 자기 workspace로 옮기거나 거절하고(`answerFullscreen`), 자기 workspace면 상태만 바꾸거나(`setWorkspaceState`)
    /// column으로 되돌린다. 첫 commit 전의 것은 이 일이 아니라 `Opened.fullscreen`이다(결정 21).
    fullscreen: FullscreenReq,
    /// 클라이언트의 selection을 서버 사본으로 다 받았다(WY-M4, design 결정 33). App이 `clipboard()`를 읽어
    /// `clipboard=shared`면 셸 클립보드에 넣는다(결정 37). 바이트를 싣지 않는 것은 사본의 주인이 서버라서다 — App은
    /// 꺼낸 그 바퀴에 복사한다.
    selection,
};

/// `Server.menuOf`의 답 — 보이는 모델과 그 세대. 포인터는 다음 `dispatch`까지 유효하다(클라이언트의 commit · destroy가 바꾼다).
pub const MenuView = struct {
    model: *const menubar.Model,
    generation: u32,
};

/// `Event.fullscreen`의 값.
pub const FullscreenReq = struct { id: u32, on: bool };

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
    /// 포인터가 들어가 있는 surface(WY-M7, design 결정 51) — 창 안의 부모나 자식. 창 단위의 enter · leave는 `ptr`가 정하고, 창 안에서 surface가
    /// 바뀌면 이것이 바뀐다. surface가 사라지면 `surfaceDestroyed`가 null로 둔다(그 뒤 leave는 안 보낸다 — 객체가 없다).
    ptr_sr: ?*Surface = null,
    /// `wl> subsurface sub=N`의 번호(서버 수명 동안 는다).
    next_sub: u32 = 1,
    /// popup(WY-M7 단계 B, design 결정 52 · 53). 경계는 앞 workspace의 화면에서 위 띠와 상태 줄을 뺀 사각형이다 — App이 프레임마다 준다
    /// (`beginPopups`). `popup_changed`는 popup이 보이거나 사라지거나 움직였다 — 다음 프레임은 통째다(밑의 셸 pane을 다시 그린다).
    popup_bounds: ?logic.Area = null,
    /// 프레임 번호 — `beginPopups`가 프레임마다 하나 올린다. 창의 `painted_frame`과 같으면 그 창은 이번 프레임에 옮겨졌다(`grabPress`).
    frame_no: u64 = 0,
    popup_changed: bool = false,
    /// `wl> popup pop=N`의 번호.
    next_pop: u32 = 1,
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
    /// 모든 `zwp_text_input_v3`(WY-M5, design 결정 43). enter · leave는 키보드 포커스를 따라 클라이언트로 골라 보낸다.
    text_inputs: std.ArrayList(*TextInput) = .empty,
    /// 살아 있는 클라이언트마다의 기록(WY-M6). 호환 모드는 클라이언트의 것이라(design 결정 45 · 46) 키를 보낼 때 포커스
    /// 클라이언트의 기록을 찾는다. libwayland에서 `wl_client`로 그 destroy listener를 되찾는 길이 zig-wayland에 없어 목록으로 든다.
    clients: std.ArrayList(*ClientRec) = .empty,
    /// 마지막으로 `wl> keys to=` 줄에 찍은 모드(참이면 native) — 포커스가 바뀌어 모드가 달라질 때만 찍는다.
    keys_mode: ?bool = null,

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
        _ = try wl.Global.create(display, wl.Subcompositor, SUBCOMPOSITOR_VERSION, *Server, self, bindSubcompositor);
        _ = try wl.Global.create(display, wl.Output, OUTPUT_VERSION, *Server, self, bindOutput);
        _ = try wl.Global.create(display, wl.Seat, SEAT_VERSION, *Server, self, bindSeat);
        _ = try wl.Global.create(display, xdg.WmBase, WM_BASE_VERSION, *Server, self, bindWmBase);
        _ = try wl.Global.create(display, zxdg.DecorationManagerV1, DECORATION_VERSION, *Server, self, bindDecorationManager);
        _ = try wl.Global.create(display, wl.DataDeviceManager, DATA_DEVICE_MANAGER_VERSION, *Server, self, bindDataDeviceManager);
        _ = try wl.Global.create(display, zwp.TextInputManagerV3, TEXT_INPUT_MANAGER_VERSION, *Server, self, bindTextInputManager);
        _ = try wl.Global.create(display, tars.MenuManagerV1, MENU_MANAGER_VERSION, *Server, self, bindMenuManager);

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
        // 키보드 포커스가 그 창을 떠나면 그 창의 popup을 닫는다(design 결정 53 — 서버 쪽 닫기 셋의 첫째). Chromium은 스스로도 닫는다.
        if (old_id) |o| if (self.find(o)) |t| dismissPopups(t, "focus");
        if (self.focused) |old| if (self.find(old)) |t| if (surfaceOf(t)) |sr| {
            // text_input `leave`는 키보드 `leave` 바로 앞이다(design 결정 42 — 확정은 App이 이 앞에서 `imeSend`로 끝냈다).
            self.textLeave(sr);
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
        // text_input `enter`는 selection 뒤 · 키보드 `enter` 앞이다(design 결정 43).
        self.textEnter(sr);
        self.logKeysMode(t.id, sr.getClient());
        var it = self.keyboards.iterator(.forward);
        while (it.next()) |kb| if (kb.getClient() == sr.getClient()) self.enterKeyboard(kb, sr);
        self.sent_mods = self.maskFor(sr.getClient());
    }

    // ── 한글 IME(WY-M5, design 결정 39 · 41 · 43) ──

    /// 키보드 포커스 창에서 IME가 켜져 있는가 — 그 클라이언트의 text_input 하나가 enabled이고 들어간 surface가 포커스 창의
    /// surface다. App이 키를 읽는 순간 묻는다(단계 B의 `Context.ime`). 포커스가 셸이면 false.
    pub fn imeActive(self: *Server) bool {
        const t = self.find(self.focused orelse return false) orelse return false;
        const sr = surfaceOf(t) orelse return false;
        for (self.text_inputs.items) |ti| {
            if (ti.resource.getClient() == sr.getClient() and ti.state.activeOn(@intFromPtr(sr))) return true;
        }
        return false;
    }

    /// 포커스 창의 켜진 text_input에 확정(`text`)과 조합(`composing`)을 보낸다 — `commit_string`(비어 있지 않을 때), `preedit_string`(빈 것도, 커서는
    /// 끝), `done(commit 셈)`. 한 `done`에 확정과 다음 조합이 함께 간다(xml의 적용 순서가 그렇게 짜여 있다). 서버는 오토마타를
    /// 모른다 — 텍스트는 App이 준다(결정 39). 켜진 것이 없으면 아무것도 안 한다. `delete_surrounding_text`는 안 보낸다.
    pub fn imeSend(self: *Server, text: []const u8, composing: []const u8) void {
        const id = self.focused orelse return;
        const t = self.find(id) orelse return;
        const sr = surfaceOf(t) orelse return;
        var cbuf: [64]u8 = undefined;
        var pbuf: [64]u8 = undefined;
        const c = std.fmt.bufPrintSentinel(&cbuf, "{s}", .{text}, 0) catch return;
        const p = std.fmt.bufPrintSentinel(&pbuf, "{s}", .{composing}, 0) catch return;
        const len: i32 = @intCast(p.len);
        var sent = false;
        for (self.text_inputs.items) |ti| {
            if (ti.resource.getClient() != sr.getClient() or !ti.state.activeOn(@intFromPtr(sr))) continue;
            if (c.len > 0) ti.resource.sendCommitString(c.ptr);
            ti.resource.sendPreeditString(p.ptr, len, len);
            ti.resource.sendDone(ti.state.commits);
            sent = true;
        }
        if (!sent) return;
        logline.print("terminal: wl> ime to={d} commit={s} preedit={s}\n", .{
            id,
            if (c.len > 0) c else "(none)",
            if (p.len > 0) p else "(none)",
        });
    }

    /// 포커스를 받은 surface의 클라이언트 text_input 모두에 `enter`. 서버 쪽 상태는 무효가 된다 — 클라이언트가 다시 enable한다.
    fn textEnter(self: *Server, sr: *wl.Surface) void {
        for (self.text_inputs.items) |ti| if (ti.resource.getClient() == sr.getClient()) self.textEnterOne(ti, sr);
    }

    fn textEnterOne(self: *Server, ti: *TextInput, sr: *wl.Surface) void {
        const was = ti.state.enabled;
        ti.resource.sendEnter(sr);
        ti.state.enter(@intFromPtr(sr));
        ti.to = self.toplevelOn(@intFromPtr(sr));
        self.logEnabled(ti, was, ti.to);
    }

    /// 포커스를 잃는 surface에 들어가 있던 text_input 모두에 `leave`.
    fn textLeave(self: *Server, sr: *wl.Surface) void {
        for (self.text_inputs.items) |ti| {
            if (ti.resource.getClient() != sr.getClient() or ti.state.entered != @intFromPtr(sr)) continue;
            const was = ti.state.enabled;
            ti.resource.sendLeave(sr);
            ti.state.leave();
            self.logEnabled(ti, was, ti.to);
        }
    }

    /// current enabled가 바뀌었으면 줄 하나(plan 확정 3) — `wl> ti enable to=ID` · `wl> ti disable to=ID`. `to`는 그 text_input이 들어가 있는
    /// (또는 막 나온) surface의 창이다(WY-M7, design 결정 55) — 전에는 클라이언트의 첫 창을 찍어 창이 둘인 Chromium에서 어긋나 보였다.
    fn logEnabled(_: *const Server, ti: *const TextInput, was: bool, to: u32) void {
        if (was == ti.state.enabled) return;
        const verb = if (ti.state.enabled) "enable" else "disable";
        logline.print("terminal: wl> ti {s} to={d}\n", .{ verb, to });
    }

    /// `wl_surface`(포인터 값 — `logic.TextInput.entered`)가 뿌리인 창의 번호. 없으면 0.
    fn toplevelOn(self: *const Server, surface: usize) u32 {
        if (surface == 0) return 0;
        for (self.toplevels.items) |t| if (surfaceOf(t)) |sr| if (@intFromPtr(sr) == surface) return t.id;
        return 0;
    }

    /// 키보드 하나에 `enter`와 수정키. 눌린 키 목록은 비운다(R-KEY-7 — 포커스 전에 누른 키는 클라이언트의 것이 아니다).
    fn enterKeyboard(self: *Server, kb: *wl.Keyboard, sr: *wl.Surface) void {
        var empty: wl.Array = .{ .size = 0, .alloc = 0, .data = null };
        kb.sendEnter(self.display.nextSerial(), sr, &empty);
        const m = self.maskFor(kb.getClient());
        kb.sendModifiers(self.display.nextSerial(), m.depressed, 0, m.locked, 0);
    }

    /// 클라이언트 `client`가 볼 수정키(WY-M6, design 결정 45). `tars_menu_v1`을 bind한 클라이언트(원래 모드)는 지금 값
    /// 그대로, 아니면 호환 모드라 Super가 Ctrl로 보인다. 키 코드는 바꾸지 않는다 — 둠에서 Cmd가 쏘지 않고 `Held`의 짝이 맞는다.
    fn maskFor(self: *const Server, client: *wl.Client) logic.Mask {
        return if (self.isNative(client)) self.mods else logic.compatMask(self.mods);
    }

    /// `client`가 `tars_menu_v1`을 bind했는가(원래 모드). 기록이 없으면(만들 때 메모리가 모자랐다) 호환이다.
    fn isNative(self: *const Server, client: *wl.Client) bool {
        return if (self.recordOf(client)) |r| r.native else false;
    }

    fn recordOf(self: *const Server, client: *wl.Client) ?*ClientRec {
        for (self.clients.items) |r| if (r.client == client) return r;
        return null;
    }

    /// 포커스 창의 모드가 마지막으로 찍은 모드와 다르면 `wl> keys to=ID mode=compat|native`(WY-M6 확정 2). 처음 포커스를
    /// 받은 창은 늘 찍힌다. 같은 모드의 창 사이를 오가면 안 찍는다 — 줄은 "모드가 바뀌었다"의 기록이다.
    fn logKeysMode(self: *Server, id: u32, client: *wl.Client) void {
        const native = self.isNative(client);
        if (self.keys_mode) |was| if (was == native) return;
        self.keys_mode = native;
        logline.print("terminal: wl> keys to={d} mode={s}\n", .{ id, if (native) "native" else "compat" });
    }

    /// 포커스 창에 키 하나(확정 10). `code`는 evdev 코드다(클라이언트가 +8 한다, 확인 3). 뗌은 누름을 보낸 키만 간다
    /// (`Held`). 키 뒤에 수정키가 바뀌었으면 `modifiers`를 보낸다 — 수정키를 누른 키 이벤트 다음에 상태가 오는 것이
    /// weston과 같은 순서다. 포커스 창이 없으면 아무것도 안 한다.
    pub fn key(self: *Server, code: u16, pressed: bool, mods: logic.Mask, time_ms: u32) void {
        self.mods = mods;
        const id = self.focused orelse return;
        const t = self.find(id) orelse return;
        const sr = surfaceOf(t) orelse return;
        // 호환 창에는 Cmd(evdev 125 · 126) 자체의 key 이벤트를 안 보낸다(WY-M7, design 결정 54 — 결정 45를 고침). 수정키(아래)는 Ctrl로 간다 —
        // 웹 페이지가 `key=Meta`를 안 보고, 둠에서 Cmd가 안 쏜다. 누름을 안 보냈으므로 `Held`에도 없고 뗌도 안 간다.
        const native = self.isNative(sr.getClient());
        const quiet = !native and (code == KEY_LEFTMETA or code == KEY_RIGHTMETA);
        const send = if (quiet) false else if (pressed) self.held.press(code) else self.held.release(code);
        // 호환 모드면 Super가 Ctrl로 보인다(WY-M6, design 결정 45). 비교도 보낼 값으로 한다 — 이미 Ctrl을 보낸 뒤 Cmd를
        // 누르면 보이는 값이 같아 `modifiers`를 다시 보내지 않는다.
        const shown = self.maskFor(sr.getClient());
        const mods_changed = if (self.sent_mods) |m| !std.meta.eql(m, shown) else true;
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
                kb.sendModifiers(serial, shown.depressed, 0, shown.locked, 0);
            self.sent_mods = shown;
        }
    }

    // ── 메뉴 바(TK-M5) ──

    /// 창 `id`의 바 이름(plan 확정 4 — app_id의 마지막 조각, 없으면 title). 창이 없으면 빈 글.
    pub fn appName(self: *Server, id: u32) []const u8 {
        const t = self.find(id) orelse return "";
        return menubar.appName(t.app_id.get(), t.title.get());
    }

    /// 창 `id`의 보이는 메뉴 모델과 그 세대(commit마다 는다 — 그리기가 바뀜을 안다). 메뉴 객체가 없거나 아직 commit이 없으면 null.
    pub fn menuOf(self: *Server, id: u32) ?MenuView {
        const t = self.find(id) orelse return null;
        const m = t.menu orelse return null;
        if (m.generation == 0) return null;
        return .{ .model = &m.current, .generation = m.generation };
    }

    /// 창 `id`의 앱에 고른 항목을 알린다(`tars_menu_v1.activated`). 메뉴 객체가 없으면 아무것도 안 한다.
    pub fn activate(self: *Server, id: u32, item: u32) void {
        const t = self.find(id) orelse return;
        const m = t.menu orelse return;
        m.resource.sendActivated(item);
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
            if (popupHit(t, x, y) != null) break :under id;
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

    /// `logic.PointerFocus.move`가 정한 것을 보낸다 — leave, enter(surface 좌표와 함께), motion, 그리고 frame. 창 안에서는 surface를
    /// 고른다(WY-M7, design 결정 51): 자식의 입력 영역 위면 그 자식, 아니면 부모. 창 안에서 surface가 바뀌면 같은 frame에 leave · enter,
    /// 버튼을 쥔 동안(`ptr.held`)은 surface를 안 바꾼다. 줄(`wl> pointer enter · leave id=`)은 지금처럼 창 단위다.
    fn applyMove(self: *Server, m: logic.PointerFocus.Move, time_ms: u32) void {
        if (m.leave) |id| {
            if (self.ptr_sr) |old| self.sendPointer(old, null, time_ms);
            self.ptr_sr = null;
            logline.print("terminal: wl> pointer leave id={d}\n", .{id});
        }
        if (m.enter) |id| if (self.find(id)) |t| {
            if (self.pickAt(t)) |h| self.sendPointer(null, h, time_ms);
            logline.print("terminal: wl> pointer enter id={d}\n", .{id});
        };
        if (m.motion) |id| if (self.find(id)) |t| {
            const h = (if (self.ptr.held > 0) self.sameAt(t) else self.pickAt(t)) orelse return;
            if (self.ptr_sr != h.s) {
                self.sendPointer(self.ptr_sr, h, time_ms);
            } else {
                var it = self.pointers.iterator(.forward);
                while (it.next()) |p| if (p.getClient() == h.s.resource.getClient()) {
                    p.sendMotion(time_ms, @fromBackingInt(@intCast(h.x)), @fromBackingInt(@intCast(h.y)));
                    if (p.getVersion() >= 5) p.sendFrame();
                };
            }
        };
    }

    /// 포인터가 놓인 surface와 그 surface의 좌표(`wl_fixed`).
    const Hit = struct { s: *Surface, x: i64, y: i64 };

    /// `old`에 leave(있으면), `new`에 enter(있으면), 그리고 frame 하나. `ptr_sr`을 `new`로.
    fn sendPointer(self: *Server, old: ?*Surface, new: ?Hit, _: u32) void {
        const client = if (new) |h| h.s.resource.getClient() else if (old) |o| o.resource.getClient() else return;
        var it = self.pointers.iterator(.forward);
        while (it.next()) |p| if (p.getClient() == client) {
            if (old) |o| p.sendLeave(self.display.nextSerial(), o.resource);
            if (new) |h| p.sendEnter(self.display.nextSerial(), h.s.resource, @fromBackingInt(@intCast(h.x)), @fromBackingInt(@intCast(h.y)));
            if (p.getVersion() >= 5) p.sendFrame();
        };
        self.ptr_sr = if (new) |h| h.s else null;
    }

    /// 포인터 하나에 `enter`(지금 자리의 surface와 좌표)와 frame — 포인터를 늦게 얻은 클라이언트(`get_pointer`).
    fn enterPointer(self: *Server, p: *wl.Pointer, t: *Toplevel) void {
        const h = self.pickAt(t) orelse return;
        p.sendEnter(self.display.nextSerial(), h.s.resource, @fromBackingInt(@intCast(h.x)), @fromBackingInt(@intCast(h.y)));
        if (p.getVersion() >= 5) p.sendFrame();
        self.ptr_sr = h.s;
    }

    /// 창 `t` 안에서 지금 포인터 자리의 surface(design 결정 51). 뿌리 surface 좌표로 바꾼 점을 위의 자식부터 `logic.pick`에 묻고, 아무것도
    /// 아니면 뿌리다. 아직 안 옮긴 창은 뿌리의 (0, 0)이다.
    fn pickAt(self: *const Server, t: *const Toplevel) ?Hit {
        // popup이 먼저다(design 결정 51 — 위에서부터 geometry 사각형). 좌표는 popup surface 기준(그림자 여백 포함).
        if (popupHit(t, self.ptr_x, self.ptr_y)) |pp| if (pp.xs) |pxs| if (pxs.surface) |ps| if (pp.origin) |o| {
            const k: i64 = pp.k;
            return .{ .s = ps, .x = @divFloor((@as(i64, self.ptr_x) - o[0]) * 256, k), .y = @divFloor((@as(i64, self.ptr_y) - o[1]) * 256, k) };
        };
        const xs = t.xdg orelse return null;
        const root = xs.surface orelse return null;
        const f = t.last_fit orelse return .{ .s = root, .x = 0, .y = 0 };
        const at = logic.surfacePoint(f, self.ptr_x, self.ptr_y);
        var list: TreeList = .{};
        collectAbove(root, 0, 0, &list);
        var cands: [TREE_MAX]logic.Cand = undefined;
        // 위에서부터 — 그린 순서의 거꾸로.
        var n: usize = 0;
        var i = list.len;
        while (i > 0) {
            i -= 1;
            const e = list.items[i];
            cands[n] = .{ .x = e.x, .y = e.y, .w = e.w, .h = e.h, .input = e.s.input };
            n += 1;
        }
        if (logic.pick(cands[0..n], at.x, at.y)) |k| {
            const e = list.items[list.len - 1 - k];
            return .{ .s = e.s, .x = @as(i64, at.x) - e.x * 256, .y = @as(i64, at.y) - e.y * 256 };
        }
        return .{ .s = root, .x = at.x, .y = at.y };
    }

    /// 버튼을 쥔 동안 — 들어가 있던 surface 그대로, 좌표만 그 surface 기준으로.
    fn sameAt(self: *const Server, t: *const Toplevel) ?Hit {
        const s = self.ptr_sr orelse return self.pickAt(t);
        if (s.role) |sxs| if (sxs.popup) |pp| if (pp.origin) |o| {
            const k: i64 = pp.k;
            return .{ .s = s, .x = @divFloor((@as(i64, self.ptr_x) - o[0]) * 256, k), .y = @divFloor((@as(i64, self.ptr_y) - o[1]) * 256, k) };
        };
        const f = t.last_fit orelse return null;
        const at = logic.surfacePoint(f, self.ptr_x, self.ptr_y);
        const off = offsetOf(s);
        return .{ .s = s, .x = @as(i64, at.x) - off[0] * 256, .y = @as(i64, at.y) - off[1] * 256 };
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

    /// 창이 자기 workspace를 받았다(WY-M0의 길 — 둠, 앞이 app workspace일 때 · CR-M2의 옮기기). 화면 크기 · `state` · activated의
    /// configure 하나를 보낸다(`state`는 WY design 결정 58 — 클라이언트가 청했으면 fullscreen, `Cmd+Ctrl+F`면 maximized). 이미
    /// 매핑된 column 창이면 크기가 바뀌므로 그 popup을 닫는다(결정 53).
    pub fn placeWorkspace(self: *Server, id: u32, state: logic.WsState) void {
        const t = self.find(id) orelse return;
        t.place = state.place();
        t.area_w = self.fb_w;
        t.area_h = self.fb_h;
        if (t.sent) |was| if (was.w != self.fb_w or was.h != self.fb_h) dismissPopups(t, "resize");
        sendConfigure(t, self.fb_w, self.fb_h, true);
    }

    /// 자기 workspace 창의 상태만 바꾼다(CR-M2 확정 5) — 자리 · 크기는 그대로. `Cmd+Ctrl+F`로 옮긴 창이 F11을 켜고 끌 때다.
    /// 같은 상태면 지금 상태 그대로 답한다(`answerStay`, RF-M0 — `logic.wsAnswer`). 줄 `wl> state id=N fullscreen=0|1`.
    pub fn setWorkspaceState(self: *Server, id: u32, state: logic.WsState) void {
        const t = self.find(id) orelse return;
        switch (logic.wsAnswer(t.place, state)) {
            .none => return,
            .restate => return self.answerStay(id),
            .change => {},
        }
        t.place = state.place();
        sendConfigure(t, self.fb_w, self.fb_h, true);
        logline.print("terminal: wl> state id={d} fullscreen={d}\n", .{ id, @intFromBool(state == .fullscreen) });
    }

    /// 자기 workspace 창의 `set_fullscreen` · `unset_fullscreen`을 받았지만 자리도 상태도 그대로다(RF-M0) — 돌아갈 곳이 없다(`leaveOwn`) ·
    /// 이미 그 상태다. xdg-shell은 그 요청에 configure로 답하라고 하므로 지금 상태 그대로 하나를 보낸다(column의 `answerFullscreen`과
    /// 같은 생각). 줄 `wl> fullscreen id=N stays`.
    pub fn answerStay(self: *Server, id: u32) void {
        const t = self.find(id) orelse return;
        const p = t.place orelse return;
        if (p == .column) return self.answerFullscreen(id);
        sendConfigure(t, self.fb_w, self.fb_h, true);
        logline.print("terminal: wl> fullscreen id={d} stays\n", .{id});
    }

    /// column 창의 `set_fullscreen` · `unset_fullscreen`에 답한다(CR-M2 확정 2) — 옮기지 않았을 때(아홉이 찼다 · 이미 column)도
    /// xdg-shell은 configure로 답하라고 한다. 다음 `configureColumn`이 같은 값이어도 한 번 보낸다(fullscreen 없는 configure).
    pub fn answerFullscreen(self: *Server, id: u32) void {
        const t = self.find(id) orelse return;
        t.reanswer = true;
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
        if (t.sent) |was| if (!t.reanswer and std.meta.eql(was, want)) return;
        t.reanswer = false;
        // 부모의 크기가 바뀌면 그 popup을 닫는다(design 결정 53 — 다시 셈하지 않는다).
        if (t.sent) |was| if (was.w != want.w or was.h != want.h) dismissPopups(t, "resize");
        sendConfigure(t, want.w, want.h, want.act);
    }

    /// 다음 프레임에 창 `id`를 사각형 `area` 안에 어떻게 옮길지(WY-M6 단계 B, design 결정 47). `whole`이면 통째(둘레 검정 + 창 전체),
    /// `part`면 그 화면 사각형만(둘레는 안 건드린다 — 프레임버퍼에 이 창의 직전 그림이 그 자리 그대로 있다), `none`이면 옮길 것이 없다
    /// (frame 콜백만 기다린 commit). 통째인 때: 첫 그림, 버퍼 크기나 buffer_scale이 바뀜, 놓는 자리(`fit`)가 마지막으로 옮긴 자리와
    /// 다름, damage가 버퍼 전체, 자식이 매핑/해제/움직임/크기 바뀜(WY-M7). 통째 프레임 · 앞 창이 바뀐 프레임은 부르는 쪽이 이것을 묻지 않고
    /// 통째로 옮긴다. 자식의 damage는 화면 좌표로 바꿔 같은 사각형에 더한다(design 결정 49) — 캐럿 하나가 바뀐 자식은 그 자리만 옮긴다.
    pub fn damageFor(self: *Server, id: u32, area: logic.Area) Damage {
        const t = self.find(id) orelse return .whole;
        const xs = t.xdg orelse return .whole;
        const s = xs.surface orelse return .whole;
        const buf = s.current orelse return .whole;
        const shm = wl.shm.Buffer.get(@ptrCast(buf)) orelse return .whole;
        if (s.damage_whole or t.tree_dirty) return .whole;
        const bw: u32 = @intCast(shm.getWidth());
        const bh: u32 = @intCast(shm.getHeight());
        const sz = logic.surfaceSize(bw, bh, s.scale);
        const f = logic.fitGeom(area, sz.w, sz.h, xs.geom) orelse return .whole;
        const last = t.last_fit orelse return .whole;
        if (!std.meta.eql(last, f)) return .whole;
        var out: ?logic.Area = null;
        if (s.damage) |d| {
            if (d.x == 0 and d.y == 0 and d.w == bw and d.h == bh) return .whole;
            if (logic.damageScreen(f, s.scale, d)) |r| out = r;
        }
        const o = logic.rootOrigin(f);
        if (!childDamage(s, o[0], o[1], f.k, .{ .x = f.x, .y = f.y, .w = f.w, .h = f.h }, &out)) return .whole;
        if (out) |r| return .{ .part = r };
        // damage가 보이는 자리 밖이다(잘린 창의 가장자리) — 옮길 것이 없다. 쌓인 것은 버린다.
        clearDamage(s);
        return .none;
    }

    /// toplevel `id`의 버퍼를 프레임버퍼의 사각형 `area` 안에 옮긴다(확정 8, WY-M2 확정 5). 그린 사각형을 돌려준다.
    /// 버퍼가 없거나 받지 않는 형식이면 null이다 — 그 자리는 부르는 쪽이 검정으로 둔다. `clip`이 있으면(WY-M6 `damageFor`의
    /// `part`) 그 화면 사각형만 옮긴다. 옮긴 뒤 쌓인 damage를 비운다 — 이제 화면이 이 버퍼와 같다.
    /// 자식(WY-M7, design 결정 49): 부모 아래의 자식 → 부모(복사) → 위의 자식(z 순, ARGB는 섞음). 자식은 통째면 slot 사각형(`area`), 부분이면
    /// clip과 창 사각형이 겹친 자리 안에서 그린다 — 부모를 다시 옮긴 바로 그 자리에만 섞으므로 같은 픽셀을 두 번 섞지 않고, 부모의 캐럿이
    /// 자식 위에 구멍을 내지 않는다.
    pub fn paint(self: *Server, id: u32, dst: [*]u8, pitch: u32, area: logic.Area, clip: ?logic.Area) ?logic.Fit {
        const t = self.find(id) orelse return null;
        const xs = t.xdg orelse return null;
        const s = xs.surface orelse return null;
        const buf = s.current orelse return null;
        const shm = wl.shm.Buffer.get(@ptrCast(buf)) orelse return null;
        if (!logic.formatOk(shm.getFormat())) return null;
        // 창의 크기는 surface 크기(버퍼 ÷ buffer_scale)다(WY-M3, design 결정 29) — `last_fit`과 포인터 좌표가 이 단위다.
        const sz = logic.surfaceSize(@intCast(shm.getWidth()), @intCast(shm.getHeight()), s.scale);
        const f = logic.fitGeom(area, sz.w, sz.h, xs.geom) orelse return null;
        const box: logic.Area = .{ .x = f.x, .y = f.y, .w = f.w, .h = f.h };
        const rect: logic.Area = if (clip) |c| logic.intersect(c, box) orelse c else box;
        const tree_clip: logic.Area = if (clip != null) (logic.intersect(rect, area) orelse rect) else area;
        const o = logic.rootOrigin(f);
        const t0 = monoNs();
        var kids = drawChildren(s, o[0], o[1], f.k, dst, pitch, tree_clip, .below);
        {
            // 클라이언트가 풀을 줄였으면 읽기가 SIGBUS다 — libwayland이 그 틈을 막는다(begin · end).
            shm.beginAccess();
            defer shm.endAccess();
            const data: [*]const u8 = @ptrCast(shm.getData() orelse return null);
            logic.blitClip(dst, pitch, f, data, @intCast(shm.getStride()), s.scale, rect);
        }
        kids += drawChildren(s, o[0], o[1], f.k, dst, pitch, tree_clip, .above);
        const us = (monoNs() - t0) / 1000;
        // 실측 줄(WY-M7 실측 1) — 자식을 섞은 옮기기의 시간(부모 복사 + 섞기). 창마다 처음 `TREE_LINES`번.
        if (kids > 0 and t.tree_lines < TREE_LINES) {
            t.tree_lines += 1;
            logline.print("terminal: wl> tree id={d} kids={d} x={d} y={d} w={d} h={d} us={d}\n", .{ id, kids, rect.x, rect.y, rect.w, rect.h, us });
        }
        // 포인터 좌표를 거꾸로 셀 자리(단계 C).
        t.last_fit = f;
        t.painted_frame = self.frame_no;
        clearDamage(s);
        t.tree_dirty = false;
        // 실측 줄(WY-M6 확정 7) — 창마다 통째 · 부분을 따로 처음 몇 번만(같은 창의 통째와 부분을 맞대려고 창마다다).
        const n = if (clip != null) &t.blit_lines.part else &t.blit_lines.whole;
        const cap: u8 = if (clip != null) BLIT_PART_LINES else BLIT_WHOLE_LINES;
        if (n.* < cap) {
            n.* += 1;
            logline.print("terminal: wl> blit id={d} x={d} y={d} w={d} h={d} us={d}\n", .{ id, rect.x, rect.y, rect.w, rect.h, us });
        }
        return f;
    }

    /// 창 `id`의 buffer_scale(WY-M3) — 보이는 트리(부모와 자식)에서 가장 큰 값(WY-M7). 창이나 버퍼가 없으면 1 — App이 물리 합성 목록에
    /// 넣을지 정한다(1이면 그림자 늘리기가 같은 그림을 만든다, design 결정 30). 자식 하나라도 bs > 1이면 창 전체를 물리로 다시 합성한다.
    pub fn bufferScale(self: *Server, id: u32) u32 {
        const t = self.find(id) orelse return 1;
        const xs = t.xdg orelse return 1;
        const s = xs.surface orelse return 1;
        if (s.current == null) return 1;
        return treeScale(s);
    }

    /// 물리 합성(WY-M3 확정 7, design 결정 30). 창 `id`의 버퍼를 물리 dumb 버퍼 `out`에 — 논리 사각형 `area` 안의 자리를
    /// 지금 버퍼로 다시 셈한 `fit`을 × `s` 해서, 논리 `clip`과 겹친 자리만 옮긴다. `drm.Framebuffer.stage` 뒤 · `flush` 앞에
    /// 부른다(반대면 같은 프레임의 늘리기가 덮는다). 자리를 `last_fit`이 아니라 지금 버퍼로 다시 세는 것은, commit이 하한 안에서
    /// 그리기를 미룬 사이 화살표만 옮기는 바퀴가 올 수 있어서다 — 옛 자리로 새(작아진) 버퍼를 읽으면 버퍼 밖이다. 트리의 buffer_scale이
    /// 모두 1이 됐으면 아무것도 안 한다(그림자 늘리기가 맞다). 자식(WY-M7)은 그림자와 같은 순서로 물리에 섞는다 — 다만 창 사각형 안만이다:
    /// 그 밖은 `stage`가 그림자(자식이 이미 섞인 것)에서 늘린 자리라 다시 섞으면 반투명 픽셀이 두 번 섞인다.
    pub fn paintPhys(self: *Server, id: u32, out: [*]u8, out_pitch: u32, s: u32, area: logic.Area, clip: logic.Area) void {
        const t = self.find(id) orelse return;
        const xs = t.xdg orelse return;
        const sf = xs.surface orelse return;
        if (treeScale(sf) == 1) return;
        const buf = sf.current orelse return;
        const shm = wl.shm.Buffer.get(@ptrCast(buf)) orelse return;
        if (!logic.formatOk(shm.getFormat())) return;
        const sz = logic.surfaceSize(@intCast(shm.getWidth()), @intCast(shm.getHeight()), sf.scale);
        const f = logic.fitGeom(area, sz.w, sz.h, xs.geom) orelse return;
        const fp = logic.scaleFit(f, s);
        const o = logic.rootOrigin(fp);
        const inner = logic.intersect(clip, .{ .x = f.x, .y = f.y, .w = f.w, .h = f.h });
        if (inner) |c| _ = drawChildren(sf, o[0], o[1], fp.k, out, out_pitch, logic.scaleArea(c, s), .below);
        {
            shm.beginAccess();
            defer shm.endAccess();
            const data: [*]const u8 = @ptrCast(shm.getData() orelse return);
            logic.blitClip(out, out_pitch, fp, data, @intCast(shm.getStride()), sf.scale, logic.scaleArea(clip, s));
        }
        if (inner) |c| _ = drawChildren(sf, o[0], o[1], fp.k, out, out_pitch, logic.scaleArea(c, s), .above);
        // popup(WY-M7 단계 B)은 이 창 위에 걸친 자리만 물리로 다시 섞는다 — 방금 창을 새로 옮긴 자리라 두 번 섞이지 않는다. 그 밖(셸 pane 위)은
        // `stage`가 그림자(popup이 이미 섞인 것)에서 늘렸다.
        if (inner) |c| self.physPopups(out, out_pitch, s, c);
    }

    /// toplevel `id`가 든 프레임을 화면에 냈다(확정 9) — 그 commit들의 frame 콜백에 `done`을 보낸다. 자식들의 것도(WY-M7 — Chromium은
    /// bubble에 frame을 건다).
    pub fn presented(self: *Server, id: u32, ms: u32) void {
        const t = self.find(id) orelse return;
        const xs = t.xdg orelse return;
        const s = xs.surface orelse return;
        framesDone(s, ms);
        for (t.popups.items) |pp| if (pp.xs) |pxs| if (pxs.surface) |ps| framesDone(ps, ms);
    }

    // ── popup(WY-M7 단계 B, design 결정 52 · 53) ──

    /// 프레임의 처음(App) — 경계를 주고 지난 프레임에 그린 자리를 비운다. 이번 프레임에 그리는 것(`paintPopups`)만 보이고 포인터가 닿는다.
    pub fn beginPopups(self: *Server, bounds: logic.Area) void {
        self.popup_bounds = bounds;
        self.frame_no += 1;
        for (self.toplevels.items) |t| for (t.popups.items) |pp| {
            pp.shown = null;
            pp.hit = null;
        };
    }

    /// 이 프레임을 통째로 그려야 하나 — 보이는 popup이 있거나 지난 프레임 뒤 popup이 보이거나 사라지거나 움직였다(design 결정 52 — popup은 셸 pane을
    /// 덮고, 밑의 픽셀을 따로 들지 않는다). 읽으면 "바뀜"을 지운다.
    pub fn popupFull(self: *Server) bool {
        var any = self.popup_changed;
        self.popup_changed = false;
        for (self.toplevels.items) |t| for (t.popups.items) |pp| {
            if (pp.mapped and !pp.dismissed) any = true;
        };
        return any;
    }

    /// 창 `id`의 보이는 popup을 만든 순으로 그린다(그림자 · 논리 프레임버퍼). 프레임의 셸 pane · 창 · 프롬프트 · 띠 뒤, 펼친 메뉴(TK-M5) 앞에 부른다.
    /// 경계 밖은 자른다. 그린 수.
    pub fn paintPopups(self: *Server, id: u32, dst: [*]u8, pitch: u32) usize {
        const t = self.find(id) orelse return 0;
        const b = self.popup_bounds orelse return 0;
        var n: usize = 0;
        for (t.popups.items) |pp| {
            if (!pp.mapped or pp.dismissed) continue;
            const xs = pp.xs orelse continue;
            const ps = xs.surface orelse continue;
            if (ps.current == null) continue;
            const go = geomOrigin(xs, 0) orelse continue;
            const sz = surfaceSizeOf(ps);
            const k: i64 = go.k;
            const g = xs.geom orelse logic.Rect{ .x = 0, .y = 0, .w = @intCast(sz[0]), .h = @intCast(sz[1]) };
            const ox = go.x - @as(i64, g.x) * k;
            const oy = go.y - @as(i64, g.y) * k;
            const shown = clampArea(ox, oy, @as(i64, sz[0]) * k, @as(i64, sz[1]) * k, b) orelse continue;
            pp.origin = .{ ox, oy };
            pp.k = go.k;
            pp.shown = shown;
            pp.hit = clampArea(go.x, go.y, @as(i64, g.w) * k, @as(i64, g.h) * k, b);
            const t0 = monoNs();
            _ = drawChildren(ps, ox, oy, go.k, dst, pitch, shown, .below);
            blendSurface(ps, ox, oy, go.k, dst, pitch, shown);
            _ = drawChildren(ps, ox, oy, go.k, dst, pitch, shown, .above);
            n += 1;
            // 실측 줄(WY-M7 실측 1) — popup마다 처음 두 번의 섞기.
            if (pp.paint_lines < 2) {
                pp.paint_lines += 1;
                const us = (monoNs() - t0) / 1000;
                var buf: [96]u8 = undefined;
                const text = std.fmt.bufPrint(&buf, "paint x={d} y={d} w={d} h={d} us={d}", .{ shown.x, shown.y, shown.w, shown.h, us }) catch "paint";
                logPop(pp, text);
            }
        }
        return n;
    }

    /// 이 프레임에 그린 popup의 자리(화면, 경계 안) — App이 clip과 verify 그림자 복사에 쓴다.
    pub fn shownPopups(self: *const Server, out: []logic.Area) []logic.Area {
        var n: usize = 0;
        for (self.toplevels.items) |t| for (t.popups.items) |pp| {
            const r = pp.shown orelse continue;
            if (n == out.len) break;
            out[n] = r;
            n += 1;
        };
        return out[0..n];
    }

    /// 화면 점 위의 popup의 창(포인터 — App이 app slot보다 먼저 묻는다, design 결정 52). 없으면 null.
    pub fn popupAt(self: *const Server, x: u32, y: u32) ?u32 {
        for (self.toplevels.items) |t| if (popupHit(t, x, y) != null) return t.id;
        return null;
    }

    /// 누름 하나(App이 셸 · 창의 길보다 먼저 묻는다). grab한 popup이 보이는데 그 클라이언트의 surface(창 · popup) 밖이면 그 클라이언트의 popup을
    /// 위에서부터 닫고 참 — 누름은 삼킨다(design 결정 53). grab 없는 popup(툴팁)은 바깥 누름에 안 닫는다. 그 클라이언트 안의 누름은 보통 길이다
    /// (xml의 owner-events).
    pub fn grabPress(self: *Server, x: u32, y: u32) bool {
        var client: ?*wl.Client = null;
        for (self.toplevels.items) |t| for (t.popups.items) |pp| {
            if (pp.grabbed and pp.mapped and !pp.dismissed) client = t.resource.getClient();
        };
        const c = client orelse return false;
        for (self.toplevels.items) |t| {
            if (t.resource.getClient() != c) continue;
            if (popupHit(t, x, y) != null) return false;
            // 이번 프레임에 옮긴 창만 안쪽이다(RF-M0) — 다른 workspace로 간 창의 `last_fit`은 지워지지 않고 남는다.
            if (logic.shownFit(t.last_fit, t.painted_frame, self.frame_no)) |f| if (logic.inside(f, x, y)) return false;
        }
        for (self.toplevels.items) |t| if (t.resource.getClient() == c) dismissPopups(t, "outside");
        return true;
    }

    /// 물리 합성(`paintPhys`)의 popup — 논리 `inner`(방금 다시 옮긴 창 사각형 안)와 겹친 보이는 popup을 × `s`로 섞는다.
    fn physPopups(self: *Server, out: [*]u8, out_pitch: u32, s: u32, inner: logic.Area) void {
        for (self.toplevels.items) |t| for (t.popups.items) |pp| {
            const shown = pp.shown orelse continue;
            const o = pp.origin orelse continue;
            const cl = logic.intersect(inner, shown) orelse continue;
            const xs = pp.xs orelse continue;
            const ps = xs.surface orelse continue;
            const k = pp.k * s;
            const ss: i64 = s;
            _ = drawChildren(ps, o[0] * ss, o[1] * ss, k, out, out_pitch, logic.scaleArea(cl, s), .below);
            blendSurface(ps, o[0] * ss, o[1] * ss, k, out, out_pitch, logic.scaleArea(cl, s));
            _ = drawChildren(ps, o[0] * ss, o[1] * ss, k, out, out_pitch, logic.scaleArea(cl, s), .above);
        };
    }

    /// popup의 부모 `xs`의 geometry를 경계 안 좌표로(부모 geometry 좌표의 경계 — `logic.placePopup`). 부모가 아직 안 그려졌으면 null(제약 없음).
    fn boundsFor(self: *const Server, xs: *XdgSurface) ?logic.Rect {
        const b = self.popup_bounds orelse return null;
        const o = geomOrigin(xs, 0) orelse return null;
        const k: i64 = o.k;
        return .{
            .x = @intCast(@divFloor(@as(i64, b.x) - o.x, k)),
            .y = @intCast(@divFloor(@as(i64, b.y) - o.y, k)),
            .w = @intCast(@divFloor(@as(i64, b.w), k)),
            .h = @intCast(@divFloor(@as(i64, b.h), k)),
        };
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
    client: *wl.Client,
    pid: i32,
    /// `tars_menu_v1`을 bind했다 — 원래 모드(Cmd가 Super로 간다, WY-M6 design 결정 46). 한 번 켜지면 끝날 때까지다.
    native: bool = false,
    destroy: wl.Listener(*wl.Client) = .init(clientGone),
};

fn clientCreated(listener: *wl.Listener(*wl.Client), client: *wl.Client) void {
    const srv: *Server = @fieldParentPtr("client_created", listener);
    const pid = client.getCredentials().pid;
    logline.print("terminal: wl> client pid={d}\n", .{pid});
    const rec = srv.allocator.create(ClientRec) catch return;
    rec.* = .{ .srv = srv, .client = client, .pid = pid };
    // 목록에 못 넣으면 기록 없이 간다 — 그 클라이언트는 호환 모드로 남는다(`isNative`).
    srv.clients.append(srv.allocator, rec) catch {
        srv.allocator.destroy(rec);
        return;
    };
    client.addDestroyListener(&rec.destroy);
}

fn clientGone(listener: *wl.Listener(*wl.Client), client: *wl.Client) void {
    const rec: *ClientRec = @fieldParentPtr("destroy", listener);
    logline.print("terminal: wl> gone pid={d}\n", .{rec.pid});
    // 포인터는 다음 클라이언트가 다시 쓸 수 있다 — 끝난 클라이언트를 "가장 최근 포커스"로 남기지 않는다(WY-M4).
    rec.srv.gate.forget(@intFromPtr(client));
    for (rec.srv.clients.items, 0..) |r, i| if (r == rec) {
        _ = rec.srv.clients.swapRemove(i);
        break;
    };
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
            s.cached_frames.init();
            s.frames.init();
            // 쌓임 순서의 첫 칸은 이 surface 자신이다(null — WY-M7 확정 1).
            s.order_pending.append(srv.allocator, null) catch {
                srv.allocator.destroy(s);
                res.destroy();
                return comp.postNoMemory();
            };
            s.order.append(srv.allocator, null) catch {
                s.order_pending.deinit(srv.allocator);
                srv.allocator.destroy(s);
                res.destroy();
                return comp.postNoMemory();
            };
            res.setHandler(*Surface, surfaceRequest, surfaceDestroyed, s);
            // 배율을 알린다(WY-M3 확정 3, design 결정 27). 판 6 이상의 surface에만 — 판 4로 bind한 클라이언트(둠)에는 이
            // 이벤트가 없다. 배율 1에서도 1을 보낸다(받기 전의 기본값과 뜻은 같지만 클라이언트가 줄로 찍는다).
            if (res.getVersion() >= 6) res.sendPreferredBufferScale(@intCast(srv.scale));
        },
        .create_region => |r| {
            const res = wl.Region.create(client, comp.getVersion(), r.id) catch return comp.postNoMemory();
            const rg = srv.allocator.create(Region) catch {
                res.destroy();
                return comp.postNoMemory();
            };
            rg.* = .{ .srv = srv };
            res.setHandler(*Region, regionRequest, regionDestroyed, rg);
        },
    }
}

/// 영역 하나(WY-M7, design 결정 50) — 상자의 합 하나다. 입력 영역(`set_input_region`)만 쓴다(opaque는 여전히 버린다). `subtract`는 받되
/// 상자를 줄이지 않는다(넓게 잡는다 — 조사에서 Chromium은 한 번도 안 보냈다).
const Region = struct {
    srv: *Server,
    box: ?logic.Box = null,
};

fn regionRequest(region: *wl.Region, req: wl.Region.Request, rg: *Region) void {
    switch (req) {
        .destroy => region.destroy(),
        .add => |a| if (logic.boxOf(a.x, a.y, a.width, a.height, 1)) |b| {
            rg.box = logic.boxUnion(rg.box, b);
        },
        .subtract => {},
    }
}

fn regionDestroyed(_: *wl.Region, rg: *Region) void {
    rg.srv.allocator.destroy(rg);
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
    /// damage(WY-M6 단계 B, design 결정 47). commit 전의 둘 — `damage`(surface 좌표, commit의 buffer_scale로 곱한다)와
    /// `damage_buffer`(버퍼 좌표). commit이 버퍼로 잘라 `damage`(아직 화면에 안 옮긴 것의 합집합, 버퍼 좌표)에 더한다.
    pending_damage: ?logic.Box = null,
    pending_damage_surface: ?logic.Box = null,
    damage: ?logic.Area = null,
    /// 다음 옮기기는 통째다 — 첫 버퍼, 버퍼 크기나 buffer_scale이 바뀜. `paint`가 지운다.
    damage_whole: bool = true,
    /// 마지막 commit의 버퍼 크기와 buffer_scale(바뀌면 통째).
    dims: ?Dims = null,
    /// 역할(WY-M7). 한 번 정해지면 바뀌지 않는다 — 같은 역할로 다시 쓰는 것은 된다(Chromium은 bubble의 surface를 subsurface로 거듭 쓴다).
    kind: Kind = .none,
    /// 이 surface가 자식이면 그 subsurface 객체(design 결정 48). 객체가 사라지면 null(역할은 남는다).
    sub: ?*Subsurface = null,
    /// 이 surface에 붙은 자식(만든 순 — 수명용). 그리는 순서는 `order`다.
    children: std.ArrayList(*Subsurface) = .empty,
    /// 쌓임 순서(아래에서부터, null = 이 surface 자신). 새 자식 · `place_above/below`는 `order_pending`을 고치고 이 surface의 상태가 적용될 때
    /// `order`로 옮긴다(xml — 부모의 double-buffered 상태). 객체가 사라진 자식은 둘에서 곧바로 뺀다.
    order_pending: std.ArrayList(?*Subsurface) = .empty,
    order: std.ArrayList(?*Subsurface) = .empty,
    order_dirty: bool = false,
    /// 입력 영역(design 결정 50). pending → (cache) → current.
    pending_input: logic.Input = .{},
    pending_input_set: bool = false,
    input: logic.Input = .{},
    /// commit된 상태(xml의 "cached state"). commit은 늘 pending을 여기로 옮긴 뒤, sync처럼 구는 자식이 아니면 곧바로 적용한다 — sync 자식은
    /// 부모의 상태가 적용될 때 적용된다(design 결정 48). 그래서 적용하는 길은 하나(`apply`)다.
    cache: Cache = .{},
    cached_gone: wl.Listener(*wl.Resource) = .init(cachedGone),
    cached_frames: wl.list.Head(wl.Callback, null) = undefined,
    /// 이 자식에 `wl_surface.enter(output)`을 보냈다(처음 보일 때 한 번 — design 결정 49).
    entered_output: bool = false,

    const Dims = struct { w: i32, h: i32, bs: u32 };
    const Kind = enum { none, xdg, sub };
};

/// commit된 채 적용을 기다리는 상태(sync 자식). 값은 commit 때의 것이다 — 버퍼(attach가 있었을 때만), buffer_scale, damage 둘, 입력 영역.
const Cache = struct {
    has: bool = false,
    buffer_set: bool = false,
    buffer: ?*wl.Buffer = null,
    linked: bool = false,
    scale: u32 = 1,
    damage: ?logic.Box = null,
    damage_surface: ?logic.Box = null,
    input: ?logic.Input = null,
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
        // damage(WY-M6 단계 B, design 결정 47) — 둘 다 pending이고 commit에서 적용된다(xml). `damage`는 surface 좌표라 곱할
        // buffer_scale이 commit에서 정해진다 — 그래서 따로 쌓는다.
        .damage => |d| if (logic.boxOf(d.x, d.y, d.width, d.height, 1)) |b| {
            s.pending_damage_surface = logic.boxUnion(s.pending_damage_surface, b);
        },
        .damage_buffer => |d| if (logic.boxOf(d.x, d.y, d.width, d.height, 1)) |b| {
            s.pending_damage = logic.boxUnion(s.pending_damage, b);
        },
        // `offset`(판 5)은 받아서 버린다 — toplevel 하나뿐이고 놓는 자리는 서버가 정한다(design 결정 28).
        // 입력 영역(WY-M7, design 결정 50) — double-buffered. null region은 무한(xml의 처음 값)이다.
        .set_input_region => |r| {
            s.pending_input_set = true;
            s.pending_input = if (r.region) |rr| blk: {
                const rg: *Region = @ptrCast(@alignCast(rr.getUserData() orelse return));
                break :blk .{ .all = false, .box = rg.box };
            } else .{};
        },
        .set_opaque_region, .set_buffer_transform, .offset => {},
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

fn cachedGone(listener: *wl.Listener(*wl.Resource), _: *wl.Resource) void {
    const s: *Surface = @fieldParentPtr("cached_gone", listener);
    listener.link.remove();
    s.cache.linked = false;
    s.cache.buffer = null;
}

/// `wl_surface.commit`(WY-M7, design 결정 48). pending을 cache로 옮기고(`stash`), sync처럼 구는 자식이 아니면 곧바로 적용한다(`apply`).
/// sync 자식의 cache는 부모의 상태가 적용될 때 적용된다 — 그래서 적용하는 길은 하나다.
fn commit(s: *Surface) void {
    stash(s);
    if (s.sub) |ss| if (subSync(ss)) return;
    apply(s);
}

/// pending → cache. 버퍼는 attach가 있었을 때만 바꾸고(destroy listener를 옮긴다), damage는 합치고, frame 콜백은 cache의 목록 끝에 잇는다.
fn stash(s: *Surface) void {
    const c = &s.cache;
    c.has = true;
    c.scale = s.pending_scale;
    if (s.pending_set) {
        if (c.linked) {
            s.cached_gone.link.remove();
            c.linked = false;
        }
        if (s.pending_linked) {
            s.pending_gone.link.remove();
            s.pending_linked = false;
        }
        c.buffer = s.pending;
        c.buffer_set = true;
        if (c.buffer) |b| {
            @as(*wl.Resource, @ptrCast(b)).addDestroyListener(&s.cached_gone);
            c.linked = true;
        }
        s.pending = null;
        s.pending_set = false;
    }
    if (s.pending_damage) |b| c.damage = logic.boxUnion(c.damage, b);
    if (s.pending_damage_surface) |b| c.damage_surface = logic.boxUnion(c.damage_surface, b);
    s.pending_damage = null;
    s.pending_damage_surface = null;
    if (s.pending_input_set) {
        c.input = s.pending_input;
        s.pending_input_set = false;
    }
    s.cached_frames.appendList(&s.pending_frames);
}

/// cache → current(지금까지의 commit 본체). 이 surface의 상태가 적용되면 자식의 자리 · 순서가 적용되고(부모의 상태), 그 뒤 sync 자식의 cache가
/// 적용된다(xml — "immediately after the parent surface's state is applied"). 끝으로 역할(자식 · toplevel)마다 할 일.
fn apply(s: *Surface) void {
    applyAt(s, 0);
}

/// `depth`는 이 적용이 처음 부른 surface에서 몇 겹 아래인가. sync 자식의 재귀는 `TREE_DEPTH`에서 멈춘다(RF-M0 — `get_subsurface`가
/// 깊이를 막는 것의 두 번째 겹. 그보다 깊은 자식의 cache는 적용되지 않고 남는다).
fn applyAt(s: *Surface, depth: usize) void {
    const c = &s.cache;
    if (!c.has) return;
    c.has = false;
    // buffer_scale이 먼저 확정된다 — 아래 크기 검사와 `wl> commit` 줄이 새 값을 본다. 값만 바뀐 commit도 다시 그린다.
    var changed = s.scale != c.scale;
    s.scale = c.scale;
    const was_shown = s.current != null;
    if (c.buffer_set) {
        const next = c.buffer;
        if (c.linked) {
            s.cached_gone.link.remove();
            c.linked = false;
        }
        c.buffer = null;
        c.buffer_set = false;
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
    if (takeDamage(s)) changed = true;
    if (c.input) |inp| {
        s.input = inp;
        c.input = null;
    }
    const waiting = !s.cached_frames.empty();
    s.frames.appendList(&s.cached_frames);
    if (applyChildren(s)) changed = true;
    if (depth < TREE_DEPTH) for (s.children.items) |ch| if (ch.surface) |cs| if (cs.cache.has and subSync(ch)) applyAt(cs, depth + 1);

    if (s.sub) |ss| return subApplied(ss, s, was_shown, changed, waiting);
    const xs = s.role orelse return;
    // window geometry(WY-M7, design 결정 50) — xdg_surface의 double-buffered 상태라 이 commit에 적용된다.
    if (xs.pending_geom_set) {
        xs.pending_geom_set = false;
        if (!std.meta.eql(xs.geom, xs.pending_geom)) changed = true;
        xs.geom = xs.pending_geom;
    }
    if (xs.popup) |pp| return popupApplied(pp, xs, s, changed, waiting);
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

/// commit의 damage 적용(WY-M6 단계 B, design 결정 47). cache의 둘을 버퍼 좌표로 맞춰(`damage`는 × buffer_scale) 지금 버퍼로 자르고
/// 아직 안 옮긴 합집합에 더한다 — commit 둘이 한 프레임에 모이면 둘을 덮는 사각형이 된다. 버퍼 크기나 buffer_scale이 바뀌었으면
/// 다음 옮기기는 통째다. 보이는 내용이 바뀌었으면(damage가 버퍼에 닿았다) 참 — 같은 버퍼를 다시 붙인 commit도 다시 그린다.
fn takeDamage(s: *Surface) bool {
    const surf = s.cache.damage_surface;
    const buf = s.cache.damage;
    s.cache.damage_surface = null;
    s.cache.damage = null;
    const cur = s.current orelse return false;
    const shm = wl.shm.Buffer.get(@ptrCast(cur)) orelse return false;
    const dims: Surface.Dims = .{ .w = shm.getWidth(), .h = shm.getHeight(), .bs = s.scale };
    if (s.dims) |d| {
        if (!std.meta.eql(d, dims)) s.damage_whole = true;
    } else s.damage_whole = true;
    s.dims = dims;
    var box = buf;
    if (surf) |b| {
        const m: i64 = s.scale;
        box = logic.boxUnion(box, .{ .x0 = b.x0 * m, .y0 = b.y0 * m, .x1 = b.x1 * m, .y1 = b.y1 * m });
    }
    const area = logic.boxClamp(box orelse return false, @intCast(dims.w), @intCast(dims.h)) orelse return false;
    s.damage = logic.areaUnion(s.damage, area);
    return true;
}

/// `wl> commit` 줄(확정 5) — 버퍼 크기나 놓는 자리가 바뀔 때만.
fn logCommit(t: *Toplevel, s: *Surface) void {
    const buf = s.current orelse return;
    const shm = wl.shm.Buffer.get(@ptrCast(buf)) orelse return;
    const sz = logic.surfaceSize(@intCast(shm.getWidth()), @intCast(shm.getHeight()), s.scale);
    const f = logic.fitGeom(.{ .x = 0, .y = 0, .w = t.area_w, .h = t.area_h }, sz.w, sz.h, geomOf(t)) orelse return;
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
    var it3 = s.cached_frames.safeIterator(.forward);
    while (it3.next()) |cb| cb.destroy();
    if (s.cache.linked) s.cached_gone.link.remove();
    if (s.role) |xs| xs.surface = null;
    const srv = s.srv;
    if (srv.ptr_sr == s) srv.ptr_sr = null;
    // 자식이 사라졌다 — 부모의 그림에서 빠진다(xml: 매핑이 풀린다). subsurface 객체는 남고(클라이언트가 지운다) surface만 끊는다.
    if (s.sub) |ss| {
        ss.surface = null;
        if (ss.parent) |par| touchTree(par);
    }
    // 부모가 사라졌다 — 자식들은 매핑이 풀린다. 자식의 subsurface 객체는 남되 부모를 잃는다.
    for (s.children.items) |ch| ch.parent = null;
    s.children.deinit(srv.allocator);
    s.order_pending.deinit(srv.allocator);
    s.order.deinit(srv.allocator);
    srv.allocator.destroy(s);
}

// ── wl_subcompositor · wl_subsurface(WY-M7 단계 A, design 결정 48 ~ 51) ──────

/// 자식 하나(xml `wl_subsurface`). 자리(`x` · `y`)와 쌓임은 부모의 상태라 부모의 적용 때 바뀐다 — `px` · `py`는 그 pending이다.
/// `surface`는 자식 surface가 먼저 사라지면 null, `parent`는 부모 surface가 먼저 사라지면 null이다(둘 다 매핑이 풀린 것).
const Subsurface = struct {
    srv: *Server,
    resource: *wl.Subsurface,
    surface: ?*Surface,
    parent: ?*Surface,
    /// `wl> subsurface sub=N`의 번호.
    num: u32,
    /// 마지막으로 안 뿌리 창(줄의 `id=`). 클라이언트가 끝날 때는 부모 · 자식 surface가 이 객체보다 먼저 사라져 사슬로는 못 찾는다.
    top: u32 = 0,
    x: i32 = 0,
    y: i32 = 0,
    px: i32 = 0,
    py: i32 = 0,
    pos_set: bool = false,
    /// xml의 처음 모드는 sync다.
    sync: bool = true,
};

/// 트리의 깊이 · 크기 상한. 자식의 자식까지 셈하고 그리는 재귀와 포인터 후보 목록이 이것으로 묶인다(클라이언트가 깊은 사슬을 만들어도
/// 서버 스택이 안 자란다). Chromium의 bubble은 깊이 1 · 하나다. 깊이는 `get_subsurface`가 막는다(`logic.subFits`, RF-M0).
const TREE_DEPTH = logic.TREE_DEPTH;
const TREE_MAX = 32;

fn bindSubcompositor(client: *wl.Client, srv: *Server, version: u32, id: u32) void {
    const r = wl.Subcompositor.create(client, version, id) catch return client.postNoMemory();
    r.setHandler(*Server, subcompositorRequest, null, srv);
}

/// `get_subsurface`(xml): 역할이 이미 있거나(xdg) subsurface 객체가 있으면 `bad_surface`, 부모가 자기 자신이거나 자손이면 `bad_parent`. 붙이면
/// 트리가 `TREE_DEPTH`보다 깊어져도 `bad_parent`다(RF-M0 — 서버가 그리지 않는 깊이이고, 막지 않으면 `apply`의 재귀가 스택을 넘긴다). 자식을
/// 더하는 것은 부모의 double-buffered 상태라 부모의 다음 적용 때 그려진다(`order_pending` → `order`). 새 자식은 맨 위다.
fn subcompositorRequest(sc: *wl.Subcompositor, req: wl.Subcompositor.Request, srv: *Server) void {
    switch (req) {
        .destroy => sc.destroy(),
        .get_subsurface => |r| {
            const s: *Surface = @ptrCast(@alignCast(r.surface.getUserData() orelse return));
            const parent: *Surface = @ptrCast(@alignCast(r.parent.getUserData() orelse return));
            if (s.role != null or s.kind == .xdg or s.sub != null) return sc.postError(.bad_surface, "wl_surface already has a role or a wl_subsurface");
            var up: ?*Surface = parent;
            while (up) |u| {
                if (u == s) return sc.postError(.bad_parent, "the parent is the surface itself or one of its descendants");
                up = if (u.sub) |us| us.parent else null;
            }
            if (!logic.subFits(levelOf(parent), heightOf(s, TREE_DEPTH + 1)))
                return sc.postError(.bad_parent, "the subsurface tree would be deeper than the server draws");
            const res = wl.Subsurface.create(sc.getClient(), sc.getVersion(), r.id) catch return sc.postNoMemory();
            const ss = srv.allocator.create(Subsurface) catch {
                res.destroy();
                return sc.postNoMemory();
            };
            ss.* = .{ .srv = srv, .resource = res, .surface = s, .parent = parent, .num = srv.next_sub };
            // 목록 셋에 자리를 먼저 잡는다 — 적용(`applyChildren`)이 `order`에 옮길 때 메모리를 다시 안 청하게.
            parent.children.ensureUnusedCapacity(srv.allocator, 1) catch return failSub(sc, res, ss);
            parent.order_pending.ensureUnusedCapacity(srv.allocator, 1) catch return failSub(sc, res, ss);
            parent.order.ensureTotalCapacity(srv.allocator, parent.order_pending.items.len + 1) catch return failSub(sc, res, ss);
            parent.children.appendAssumeCapacity(ss);
            parent.order_pending.appendAssumeCapacity(ss);
            parent.order_dirty = true;
            srv.next_sub += 1;
            s.sub = ss;
            s.kind = .sub;
            res.setHandler(*Subsurface, subsurfaceRequest, subsurfaceDestroyed, ss);
            logSub(ss, if (parent.sub == null) "new parent=main" else "new parent=sub");
        },
    }
}

/// `s`가 뿌리에서 몇 겹 아래인가(부모 쪽 사슬, 끊긴 사슬은 거기까지). `TREE_DEPTH`를 넘으면 더 세지 않는다 — 어차피 거절이다.
fn levelOf(s0: *Surface) usize {
    var s = s0;
    var n: usize = 0;
    while (s.sub) |ss| {
        if (n > TREE_DEPTH) break;
        n += 1;
        s = ss.parent orelse break;
    }
    return n;
}

/// `s` 아래 가장 깊은 자손까지의 겹(자식 쪽, 자식이 없으면 0). `cap` 겹에서 멈춘다 — 재귀가 그보다 깊이 안 간다.
fn heightOf(s: *Surface, cap: usize) usize {
    if (cap == 0) return 0;
    var best: usize = 0;
    for (s.children.items) |ch| if (ch.surface) |cs| {
        best = @max(best, 1 + heightOf(cs, cap - 1));
    };
    return best;
}

fn failSub(sc: *wl.Subcompositor, res: *wl.Subsurface, ss: *Subsurface) void {
    ss.srv.allocator.destroy(ss);
    res.destroy();
    sc.postNoMemory();
}

fn subsurfaceRequest(res: *wl.Subsurface, req: wl.Subsurface.Request, ss: *Subsurface) void {
    switch (req) {
        .destroy => res.destroy(),
        .set_position => |p| {
            ss.px = p.x;
            ss.py = p.y;
            ss.pos_set = true;
        },
        .place_above => |r| restackSub(res, ss, r.sibling, true),
        .place_below => |r| restackSub(res, ss, r.sibling, false),
        .set_sync => ss.sync = true,
        // 즉시 효과다(xml). 이제 desync처럼 굴면 쌓인 cache를 곧바로 적용한다.
        .set_desync => {
            ss.sync = false;
            if (ss.surface) |s| if (s.cache.has and !subSync(ss)) apply(s);
        },
    }
}

/// `place_above/below` — 기준은 부모이거나 같은 부모의 다른 자식이어야 한다(아니면 `bad_surface`). 부모의 `order_pending`을 고친다.
fn restackSub(res: *wl.Subsurface, ss: *Subsurface, sibling: *wl.Surface, above: bool) void {
    const parent = ss.parent orelse return;
    const sib: *Surface = @ptrCast(@alignCast(sibling.getUserData() orelse return));
    const ref: ?*Subsurface = if (sib == parent) null else blk: {
        const so = sib.sub orelse return res.postError(.bad_surface, "the reference is not a sibling or the parent");
        if (so.parent != parent or so == ss) return res.postError(.bad_surface, "the reference is not a sibling or the parent");
        break :blk so;
    };
    if (!logic.restack(?*Subsurface, parent.order_pending.items, ss, ref, above))
        return res.postError(.bad_surface, "the reference is not a sibling or the parent");
    parent.order_dirty = true;
}

/// 객체가 사라졌다 — 곧바로 효과다(xml): 부모의 두 순서와 목록에서 빼고 창을 통째로 다시 그린다. surface는 남고(역할도 남는다) 매핑이 풀린다.
fn subsurfaceDestroyed(_: *wl.Subsurface, ss: *Subsurface) void {
    logSub(ss, "gone");
    if (ss.parent) |p| {
        for (p.children.items, 0..) |c, i| if (c == ss) {
            _ = p.children.orderedRemove(i);
            break;
        };
        for (p.order_pending.items, 0..) |c, i| if (c == ss) {
            _ = p.order_pending.orderedRemove(i);
            break;
        };
        for (p.order.items, 0..) |c, i| if (c == ss) {
            _ = p.order.orderedRemove(i);
            break;
        };
        touchTree(p);
    }
    if (ss.surface) |s| s.sub = null;
    ss.srv.allocator.destroy(ss);
}

/// subsurface가 실제로 sync처럼 구는가 — 자기부터 위로 sync 깃발을 모아 `logic.effectiveSync`(xml의 재귀 규칙).
fn subSync(ss: *Subsurface) bool {
    var chain: [TREE_DEPTH]bool = undefined;
    var n: usize = 0;
    var it: ?*Subsurface = ss;
    while (n < chain.len) {
        const x = it orelse break;
        chain[n] = x.sync;
        n += 1;
        const p = x.parent orelse break;
        it = p.sub;
    }
    return logic.effectiveSync(chain[0..n]);
}

/// 부모 `s`의 상태가 적용될 때 자식의 자리와 쌓임을 적용한다. 보이는 것이 움직였으면 참(창을 통째로 — `tree_dirty`). 같은 값의
/// `set_position`(Chromium은 키마다 보낸다)은 움직임이 아니다.
fn applyChildren(s: *Surface) bool {
    var moved = false;
    for (s.children.items) |ch| if (ch.pos_set) {
        ch.pos_set = false;
        if (ch.x != ch.px or ch.y != ch.py) {
            ch.x = ch.px;
            ch.y = ch.py;
            moved = true;
        }
    };
    if (s.order_dirty) {
        s.order_dirty = false;
        if (!std.mem.eql(?*Subsurface, s.order.items, s.order_pending.items)) {
            s.order.clearRetainingCapacity();
            // 자리는 `get_subsurface`가 미리 잡았다.
            s.order.appendSliceAssumeCapacity(s.order_pending.items);
            moved = true;
        }
    }
    if (moved) markTree(s);
    return moved;
}

/// 자식의 상태가 적용됐다. 처음 보이면 output `enter`, 보임이 바뀌면 줄과 통째 다시 그리기, 그리고 뿌리 창에 `Event.commit`(보이는 것이
/// 바뀌었거나 frame을 기다린다 — 부모의 commit 없이 자식만 commit하는 desync 자식이 이 길로 그려진다).
fn subApplied(ss: *Subsurface, s: *Surface, was_shown: bool, changed: bool, waiting: bool) void {
    const shown = s.current != null;
    if (shown and !s.entered_output) {
        s.entered_output = true;
        var it = s.srv.outputs.iterator(.forward);
        while (it.next()) |o| if (o.getClient() == s.resource.getClient()) s.resource.sendEnter(o);
    }
    if (shown != was_shown) {
        markTree(s);
        if (shown) {
            var buf: [64]u8 = undefined;
            const sz = surfaceSizeOf(s);
            // 자리는 부모의 다음 적용에 정해질 값이다(desync 자식은 부모보다 먼저 commit한다 — Chromium의 bubble · tars-wl-test).
            const ax = if (ss.pos_set) ss.px else ss.x;
            const ay = if (ss.pos_set) ss.py else ss.y;
            const text = std.fmt.bufPrint(&buf, "map w={d} h={d} bs={d} at={d},{d}", .{ sz[0], sz[1], s.scale, ax, ay }) catch "map";
            logSub(ss, text);
        } else logSub(ss, "unmap");
    }
    const t = rootToplevel(s) orelse return;
    if (changed or waiting) s.srv.push(.{ .commit = t.id });
}

/// 버퍼가 있는 surface의 크기(surface 단위). 없으면 0.
fn surfaceSizeOf(s: *const Surface) [2]u32 {
    const b = s.current orelse return .{ 0, 0 };
    const shm = wl.shm.Buffer.get(@ptrCast(b)) orelse return .{ 0, 0 };
    const sz = logic.surfaceSize(@intCast(shm.getWidth()), @intCast(shm.getHeight()), s.scale);
    return .{ sz.w, sz.h };
}

/// `wl> subsurface id=창 sub=N …`(WY-M7 확정 2) — 만들기 · 매핑 · 해제 · 닫기만, 창마다 `SUB_LINES`번.
fn logSub(ss: *Subsurface, what: []const u8) void {
    const from = ss.parent orelse ss.surface;
    if (from) |f| if (rootToplevel(f)) |t| {
        ss.top = t.id;
    };
    if (ss.srv.find(ss.top)) |t| {
        if (t.sub_lines >= SUB_LINES) return;
        t.sub_lines += 1;
    }
    logline.print("terminal: wl> subsurface id={d} sub={d} {s}\n", .{ ss.top, ss.num, what });
}

/// 자식을 따라 뿌리로 올라가 그 창(toplevel). 사슬이 끊겼거나(부모가 사라짐) 뿌리가 창이 아니면 null.
fn rootToplevel(s0: *Surface) ?*Toplevel {
    var s = s0;
    var n: usize = 0;
    while (s.sub) |ss| : (n += 1) {
        if (n == TREE_DEPTH) return null;
        s = ss.parent orelse return null;
    }
    const xs = s.role orelse return null;
    // popup의 자식은 popup의 창으로(WY-M7 단계 B).
    if (xs.popup) |pp| return pp.top;
    return xs.toplevel;
}

/// 뿌리 창을 다음 옮기기에 통째로(자식의 매핑 · 움직임 · 쌓임).
fn markTree(s: *Surface) void {
    if (rootToplevel(s)) |t| t.tree_dirty = true;
}

/// `markTree` + 다시 그리기를 청한다(부모의 commit 없이 바뀌는 것 — 객체가 사라짐).
fn touchTree(s: *Surface) void {
    const t = rootToplevel(s) orelse return;
    t.tree_dirty = true;
    t.srv.push(.{ .commit = t.id });
}

/// 뿌리 surface 좌표에서 `s`의 자리(surface 단위) — 자식의 자리를 위로 더한다.
fn offsetOf(s0: *const Surface) [2]i64 {
    var s = s0;
    var x: i64 = 0;
    var y: i64 = 0;
    var n: usize = 0;
    while (s.sub) |ss| : (n += 1) {
        if (n == TREE_DEPTH) break;
        x += ss.x;
        y += ss.y;
        s = ss.parent orelse break;
    }
    return .{ x, y };
}

fn geomOf(t: *const Toplevel) ?logic.Rect {
    const xs = t.xdg orelse return null;
    return xs.geom;
}

const Side = enum { below, above };

/// `s`의 자식 중 `s` 아래(`below`) 또는 위(`above`)의 것을 그린다 — 자식마다 그 아래 자식 → 그 자신(섞음) → 그 위 자식. `ox` · `oy`는 `s`의
/// surface (0, 0)이 놓인 화면 자리, `k`는 surface 단위 하나의 화면 픽셀(뿌리의 늘림 — 물리면 × 배율). 섞은 자식 수를 돌려준다(실측 줄).
fn drawChildren(s: *Surface, ox: i64, oy: i64, k: u32, dst: [*]u8, pitch: u32, clip: logic.Area, side: Side) usize {
    return drawChildrenAt(s, ox, oy, k, dst, pitch, clip, side, 0);
}

fn drawChildrenAt(s: *Surface, ox: i64, oy: i64, k: u32, dst: [*]u8, pitch: u32, clip: logic.Area, side: Side, depth: usize) usize {
    if (depth == TREE_DEPTH) return 0;
    var n: usize = 0;
    const self_at = std.mem.indexOfScalar(?*Subsurface, s.order.items, null) orelse return 0;
    const items = if (side == .below) s.order.items[0..self_at] else s.order.items[self_at + 1 ..];
    for (items) |e| {
        const ch = e orelse continue;
        const cs = ch.surface orelse continue;
        if (cs.current == null) continue;
        const cx = ox + @as(i64, ch.x) * k;
        const cy = oy + @as(i64, ch.y) * k;
        n += drawChildrenAt(cs, cx, cy, k, dst, pitch, clip, .below, depth + 1);
        blendSurface(cs, cx, cy, k, dst, pitch, clip);
        n += 1;
        n += drawChildrenAt(cs, cx, cy, k, dst, pitch, clip, .above, depth + 1);
    }
    return n;
}

/// 자식 surface 하나를 섞는다(ARGB는 premultiplied over, XRGB는 덮기 — design 결정 49).
fn blendSurface(s: *Surface, ox: i64, oy: i64, k: u32, dst: [*]u8, pitch: u32, clip: logic.Area) void {
    const b = s.current orelse return;
    const shm = wl.shm.Buffer.get(@ptrCast(b)) orelse return;
    const fmt = shm.getFormat();
    if (!logic.formatOk(fmt)) return;
    const sz = logic.surfaceSize(@intCast(shm.getWidth()), @intCast(shm.getHeight()), s.scale);
    shm.beginAccess();
    defer shm.endAccess();
    const data: [*]const u8 = @ptrCast(shm.getData() orelse return);
    logic.blendClip(dst, pitch, ox, oy, k, data, @intCast(shm.getStride()), s.scale, sz.w, sz.h, clip, fmt == logic.FORMAT_ARGB8888);
}

/// 보이는 트리(그리는 자식들)의 buffer_scale 가운데 가장 큰 값.
fn treeScale(s: *const Surface) u32 {
    return treeScaleAt(s, 0);
}

fn treeScaleAt(s: *const Surface, depth: usize) u32 {
    var best: u32 = if (s.current != null) s.scale else 1;
    if (depth == TREE_DEPTH) return best;
    for (s.order.items) |e| {
        const ch = e orelse continue;
        const cs = ch.surface orelse continue;
        if (cs.current == null) continue;
        best = @max(best, treeScaleAt(cs, depth + 1));
    }
    return best;
}

/// 보이는 자식들의 damage를 화면 사각형 `out`에 더한다(design 결정 49). 통째로 가야 하면 false — 자식의 첫 그림이나 크기 · buffer_scale이
/// 바뀜, 또는 damage를 받은 자식이 창의 보이는 사각형 `box` 밖으로 나감(그 바깥은 통째 프레임만 다시 그린다 — 부분 blit은 `box` 안만이다).
fn childDamage(s: *Surface, ox: i64, oy: i64, k: u32, box: logic.Area, out: *?logic.Area) bool {
    return childDamageAt(s, ox, oy, k, box, out, 0);
}

fn childDamageAt(s: *Surface, ox: i64, oy: i64, k: u32, box: logic.Area, out: *?logic.Area, depth: usize) bool {
    if (depth == TREE_DEPTH) return true;
    for (s.order.items) |e| {
        const ch = e orelse continue;
        const cs = ch.surface orelse continue;
        if (cs.current == null) continue;
        const cx = ox + @as(i64, ch.x) * k;
        const cy = oy + @as(i64, ch.y) * k;
        if (cs.damage_whole) return false;
        if (cs.damage) |d| {
            const sz = surfaceSizeOf(cs);
            if (!logic.within(cx, cy, @as(i64, sz[0]) * k, @as(i64, sz[1]) * k, box)) return false;
            if (logic.damageAt(cx, cy, k, cs.scale, d, box)) |r| out.* = logic.areaUnion(out.*, r);
        }
        if (!childDamageAt(cs, cx, cy, k, box, out, depth + 1)) return false;
    }
    return true;
}

/// 옮긴 뒤 — 트리 전체의 쌓인 damage를 비운다(이제 화면이 버퍼들과 같다).
fn clearDamage(s: *Surface) void {
    clearDamageAt(s, 0);
}

fn clearDamageAt(s: *Surface, depth: usize) void {
    s.damage = null;
    s.damage_whole = false;
    if (depth == TREE_DEPTH) return;
    for (s.children.items) |ch| if (ch.surface) |cs| clearDamageAt(cs, depth + 1);
}

/// 트리 전체의 frame 콜백에 `done`.
fn framesDone(s: *Surface, ms: u32) void {
    framesDoneAt(s, ms, 0);
}

fn framesDoneAt(s: *Surface, ms: u32, depth: usize) void {
    var it = s.frames.safeIterator(.forward);
    while (it.next()) |cb| cb.destroySendDone(ms);
    if (depth == TREE_DEPTH) return;
    for (s.children.items) |ch| if (ch.surface) |cs| framesDoneAt(cs, ms, depth + 1);
}

/// 포인터 후보 하나 — 뿌리 surface 좌표의 자리와 크기(surface 단위).
const TreeEntry = struct { s: *Surface, x: i64, y: i64, w: i64, h: i64 };
const TreeList = struct {
    items: [TREE_MAX]TreeEntry = undefined,
    len: usize = 0,
};

/// 뿌리 위에 그려지는 자식들을 그리는 순서로 모은다(뿌리 아래의 자식은 뿌리가 덮으므로 포인터가 닿지 않는다 — design 결정 51).
fn collectAbove(root: *Surface, ox: i64, oy: i64, list: *TreeList) void {
    const self_at = std.mem.indexOfScalar(?*Subsurface, root.order.items, null) orelse return;
    for (root.order.items[self_at + 1 ..]) |e| {
        const ch = e orelse continue;
        const cs = ch.surface orelse continue;
        collectSub(cs, ox + ch.x, oy + ch.y, list, 1);
    }
}

fn collectSub(s: *Surface, x: i64, y: i64, list: *TreeList, depth: usize) void {
    if (s.current == null or depth > TREE_DEPTH) return;
    const self_at = std.mem.indexOfScalar(?*Subsurface, s.order.items, null) orelse return;
    for (s.order.items[0..self_at]) |e| {
        const ch = e orelse continue;
        const cs = ch.surface orelse continue;
        collectSub(cs, x + ch.x, y + ch.y, list, depth + 1);
    }
    if (list.len < TREE_MAX) {
        const sz = surfaceSizeOf(s);
        list.items[list.len] = .{ .s = s, .x = x, .y = y, .w = sz[0], .h = sz[1] };
        list.len += 1;
    }
    for (s.order.items[self_at + 1 ..]) |e| {
        const ch = e orelse continue;
        const cs = ch.surface orelse continue;
        collectSub(cs, x + ch.x, y + ch.y, list, depth + 1);
    }
}

// ── xdg_popup(WY-M7 단계 B, design 결정 52 · 53) ─────────────────────────────

/// popup 하나. 자리 `at`은 부모 window geometry 좌표의 configure 값이다(`logic.placePopup`). 그린 자리(`origin` · `shown` · `hit`)는 App의 프레임이
/// 정한다 — `beginPopups`가 비우고 `paintPopups`가 채운다. `xs` · `parent` · `top`은 약한 참조다(먼저 사라지면 null).
const Popup = struct {
    srv: *Server,
    resource: *xdg.Popup,
    xs: ?*XdgSurface,
    parent: ?*XdgSurface,
    top: ?*Toplevel,
    /// `wl> popup pop=N`의 번호.
    num: u32,
    pos: logic.Positioner,
    at: logic.Rect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    grabbed: bool = false,
    mapped: bool = false,
    /// 서버가 `popup_done`을 보냈다 — 클라이언트가 지울 때까지 안 그린다.
    dismissed: bool = false,
    /// 이번 프레임에 그린 popup surface의 화면 원점과 늘림, 그 surface의 화면 사각형(경계 안 — verify 복사 · 물리), geometry 사각형(포인터).
    origin: ?[2]i64 = null,
    k: u32 = 1,
    shown: ?logic.Area = null,
    hit: ?logic.Area = null,
    paint_lines: u8 = 0,
};

/// 화면 원점과 늘림(`geomOrigin`).
const GeomOrigin = struct { x: i64, y: i64, k: u32 };

/// `xs`의 window geometry 왼쪽 위가 놓인 화면 자리. 창이면 마지막으로 옮긴 `fit`의 surface 원점 + geometry, popup이면 그 부모의 geometry 원점 +
/// configure의 (x, y)(× 늘림). 부모가 아직 안 그려졌으면 null.
fn geomOrigin(xs: *const XdgSurface, depth: usize) ?GeomOrigin {
    if (depth > TREE_DEPTH) return null;
    if (xs.toplevel) |t| {
        const f = t.last_fit orelse return null;
        const o = logic.rootOrigin(f);
        const g = xs.geom orelse logic.Rect{ .x = 0, .y = 0, .w = 0, .h = 0 };
        return .{ .x = o[0] + @as(i64, g.x) * f.k, .y = o[1] + @as(i64, g.y) * f.k, .k = f.k };
    }
    if (xs.popup) |pp| {
        const par = pp.parent orelse return null;
        const po = geomOrigin(par, depth + 1) orelse return null;
        return .{ .x = po.x + @as(i64, pp.at.x) * po.k, .y = po.y + @as(i64, pp.at.y) * po.k, .k = po.k };
    }
    return null;
}

/// 화면 사각형(원점은 음수일 수 있다)을 `b` 안으로 자른다. 겹치지 않으면 null.
fn clampArea(x: i64, y: i64, w: i64, h: i64, b: logic.Area) ?logic.Area {
    const x0 = @max(x, @as(i64, b.x));
    const y0 = @max(y, @as(i64, b.y));
    const x1 = @min(x + w, @as(i64, b.x) + b.w);
    const y1 = @min(y + h, @as(i64, b.y) + b.h);
    if (x1 <= x0 or y1 <= y0) return null;
    return .{ .x = @intCast(x0), .y = @intCast(y0), .w = @intCast(x1 - x0), .h = @intCast(y1 - y0) };
}

/// 창 `t`의 popup 가운데 화면 점 위의 맨 위 것(보이는 것만 — geometry 사각형).
fn popupHit(t: *const Toplevel, x: u32, y: u32) ?*Popup {
    var i = t.popups.items.len;
    while (i > 0) {
        i -= 1;
        const pp = t.popups.items[i];
        if (!pp.mapped or pp.dismissed) continue;
        const h = pp.hit orelse continue;
        if (x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h) return pp;
    }
    return null;
}

fn topOf(xs: *const XdgSurface) ?*Toplevel {
    if (xs.toplevel) |t| return t;
    if (xs.popup) |pp| return pp.top;
    return null;
}

/// `wl> popup id=창 pop=N …` — 만들기 · grab · 매핑 · 해제 · 다시 놓기 · 닫힘 · 지움, 그리고 처음 두 번의 섞기. 창마다 `POP_LINES`번.
fn logPop(pp: *Popup, what: []const u8) void {
    const id: u32 = if (pp.top) |t| blk: {
        if (t.pop_lines >= POP_LINES) return;
        t.pop_lines += 1;
        break :blk t.id;
    } else 0;
    logline.print("terminal: wl> popup id={d} pop={d} {s}\n", .{ id, pp.num, what });
}

/// 클라이언트의 `xdg_wm_base`에 에러(`invalid_positioner` · `not_the_topmost_popup` · `invalid_popup_parent`).
fn postWm(srv: *Server, client: *wl.Client, err: xdg.WmBase.Error, msg: [*:0]const u8) void {
    for (srv.wm_bases.items) |wm| if (wm.getClient() == client) return wm.postError(err, msg);
}

/// `get_popup`(xml). positioner가 완전해야 하고(`invalid_positioner`), 자리는 그때 셈한다 — 부모 geometry의 화면 자리와 경계로(design 결정 52).
/// 부모가 없거나(다른 프로토콜의 부모 — 우리는 모른다) 이미 닫힌 popup이면 곧 닫는다(xml).
fn getPopup(res: *xdg.Surface, xs: *XdgSurface, id: u32, parent_res: ?*xdg.Surface, positioner: *xdg.Positioner) void {
    const srv = xs.srv;
    if (xs.toplevel != null or xs.popup != null) return res.postError(.already_constructed, "xdg_surface already has a role object");
    const po: *PosObj = @ptrCast(@alignCast(positioner.getUserData() orelse return));
    if (!po.p.complete()) return postWm(srv, res.getClient(), .invalid_positioner, "the positioner has no size or no anchor rectangle");
    const parent: ?*XdgSurface = if (parent_res) |pr| @ptrCast(@alignCast(pr.getUserData() orelse return)) else null;
    const top: ?*Toplevel = if (parent) |px| topOf(px) else null;
    if (top) |t| t.popups.ensureUnusedCapacity(srv.allocator, 1) catch return res.postNoMemory();
    const p = xdg.Popup.create(res.getClient(), res.getVersion(), id) catch return res.postNoMemory();
    const pp = srv.allocator.create(Popup) catch {
        p.destroy();
        return res.postNoMemory();
    };
    pp.* = .{ .srv = srv, .resource = p, .xs = xs, .parent = parent, .top = top, .num = srv.next_pop, .pos = po.p };
    srv.next_pop += 1;
    pp.at = logic.placePopup(po.p, if (parent) |px| srv.boundsFor(px) else null);
    xs.popup = pp;
    p.setHandler(*Popup, popupRequest, popupDestroyed, pp);
    if (top) |t| t.popups.appendAssumeCapacity(pp);
    var buf: [96]u8 = undefined;
    const kind = if (parent) |px| (if (px.popup != null) "popup" else "main") else "none";
    const text = std.fmt.bufPrint(&buf, "new parent={s} at={d},{d} w={d} h={d} ca={d}", .{ kind, pp.at.x, pp.at.y, pp.at.w, pp.at.h, po.p.ca }) catch "new";
    logPop(pp, text);
    const parent_gone = if (parent) |px| (if (px.popup) |ppp| ppp.dismissed else false) else true;
    if (top == null or parent_gone) dismiss(pp, "parent");
}

fn popupRequest(res: *xdg.Popup, req: xdg.Popup.Request, pp: *Popup) void {
    switch (req) {
        // 맨 위 popup만 지울 수 있다(xml) — 이 popup을 부모로 둔 popup이 살아 있으면 에러.
        .destroy => {
            if (pp.top) |t| if (pp.xs) |xs| for (t.popups.items) |c| if (c.parent == xs)
                return postWm(pp.srv, res.getClient(), .not_the_topmost_popup, "a child popup is still alive");
            res.destroy();
        },
        // grab은 받되 키보드 포커스를 안 옮긴다(design 결정 53 — xml과 다른 점). 매핑 뒤면 `invalid_grab`, 부모가 grab 안 한 popup이면 `invalid_popup_parent`.
        .grab => {
            if (pp.mapped) return res.postError(.invalid_grab, "grab after the popup was mapped");
            if (pp.parent) |px| if (px.popup) |par| if (!par.grabbed)
                return postWm(pp.srv, res.getClient(), .invalid_popup_parent, "the parent popup did not grab");
            pp.grabbed = true;
            logPop(pp, "grab");
        },
        // 새 positioner로 다시 셈한다 — repositioned → configure → xdg_surface.configure(xml 순서). 서버가 이미 닫은 popup이면 아무것도
        // 안 한다(RF-M0, `logic.onReposition` — `popupApplied`와 같다).
        .reposition => |r| {
            const po: *PosObj = @ptrCast(@alignCast(r.positioner.getUserData() orelse return));
            switch (logic.onReposition(po.p, pp.dismissed)) {
                .invalid => return postWm(pp.srv, res.getClient(), .invalid_positioner, "the positioner has no size or no anchor rectangle"),
                .ignore => return,
                .configure => {},
            }
            pp.pos = po.p;
            pp.at = logic.placePopup(po.p, if (pp.parent) |px| pp.srv.boundsFor(px) else null);
            res.sendRepositioned(r.token);
            res.sendConfigure(pp.at.x, pp.at.y, pp.at.w, pp.at.h);
            if (pp.xs) |xs| xs.resource.sendConfigure(pp.srv.display.nextSerial());
            pp.srv.popup_changed = true;
            var buf: [64]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "reposition at={d},{d} w={d} h={d}", .{ pp.at.x, pp.at.y, pp.at.w, pp.at.h }) catch "reposition";
            logPop(pp, text);
        },
    }
}

fn popupDestroyed(_: *xdg.Popup, pp: *Popup) void {
    const srv = pp.srv;
    logPop(pp, "gone");
    if (pp.top) |t| {
        for (t.popups.items, 0..) |x, i| if (x == pp) {
            _ = t.popups.orderedRemove(i);
            break;
        };
        // 지운 popup이 보였으면 그 자리를 다시 그린다(통째 — `popup_changed`).
        srv.push(.{ .commit = t.id });
    }
    srv.popup_changed = true;
    if (pp.xs) |xs| xs.popup = null;
    srv.allocator.destroy(pp);
}

/// 서버가 popup을 닫는다(`popup_done`) — 다시 안 그리고 클라이언트가 지우기를 기다린다.
fn dismiss(pp: *Popup, why: []const u8) void {
    if (pp.dismissed) return;
    pp.dismissed = true;
    pp.mapped = false;
    pp.resource.sendPopupDone();
    pp.srv.popup_changed = true;
    var buf: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "done why={s}", .{why}) catch "done";
    logPop(pp, text);
    if (pp.top) |t| pp.srv.push(.{ .commit = t.id });
}

/// 창 `t`의 popup을 위에서부터(만든 순의 거꾸로 — xml의 닫는 순서) 닫는다.
fn dismissPopups(t: *Toplevel, why: []const u8) void {
    var i = t.popups.items.len;
    while (i > 0) {
        i -= 1;
        dismiss(t.popups.items[i], why);
    }
}

/// popup의 상태가 적용됐다(`apply`). configure 순서는 toplevel과 같다(`logic.onCommit` — 첫 commit에 configure, ack 뒤 버퍼가 매핑). 매핑 ·
/// 해제는 다음 프레임을 통째로, 보이는 것이 바뀌면 창을 다시 그린다.
fn popupApplied(pp: *Popup, xs: *XdgSurface, s: *Surface, changed: bool, waiting: bool) void {
    const srv = pp.srv;
    const step = logic.onCommit(xs.phase, xs.acked, s.current != null);
    switch (step.action) {
        .unconfigured_buffer => return xs.resource.postError(.unconfigured_buffer, "buffer before the first ack_configure"),
        .send_configure => {
            if (!pp.dismissed) {
                pp.resource.sendConfigure(pp.at.x, pp.at.y, pp.at.w, pp.at.h);
                xs.resource.sendConfigure(srv.display.nextSerial());
            }
        },
        .wait => {},
        .map, .update => {
            const shown = s.current != null and !pp.dismissed;
            const flipped = shown != pp.mapped;
            if (flipped) {
                pp.mapped = shown;
                srv.popup_changed = true;
                if (shown) {
                    if (!s.entered_output) {
                        s.entered_output = true;
                        var it = srv.outputs.iterator(.forward);
                        while (it.next()) |o| if (o.getClient() == s.resource.getClient()) s.resource.sendEnter(o);
                    }
                    const sz = surfaceSizeOf(s);
                    const g = xs.geom orelse logic.Rect{ .x = 0, .y = 0, .w = @intCast(sz[0]), .h = @intCast(sz[1]) };
                    var buf: [96]u8 = undefined;
                    const text = std.fmt.bufPrint(&buf, "map w={d} h={d} bs={d} geom={d},{d} {d}x{d} grab={d}", .{ sz[0], sz[1], s.scale, g.x, g.y, g.w, g.h, @intFromBool(pp.grabbed) }) catch "map";
                    logPop(pp, text);
                } else if (!pp.dismissed) logPop(pp, "unmap");
            }
            if (pp.top) |t| if (changed or waiting or flipped) srv.push(.{ .commit = t.id });
        },
    }
    xs.phase = step.next;
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
                srv.enterPointer(p, t);
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
            const po = srv.allocator.create(PosObj) catch {
                p.destroy();
                return wm.postNoMemory();
            };
            po.* = .{ .srv = srv };
            p.setHandler(*PosObj, positionerRequest, positionerDestroyed, po);
        },
        .get_xdg_surface => |r| {
            const s: *Surface = @ptrCast(@alignCast(r.surface.getUserData() orelse return));
            // 역할은 하나다(WY-M7) — 자식(subsurface)이었던 surface는 xdg_surface가 될 수 없다.
            if (s.role != null or s.kind == .sub) return wm.postError(.role, "wl_surface already has a role");
            s.kind = .xdg;
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

/// positioner 하나의 상태(WY-M7 단계 B). `get_popup` · `reposition`이 그때의 값을 복사한다(xml — 그 뒤의 바뀜은 앞의 popup에 안 간다).
const PosObj = struct {
    srv: *Server,
    p: logic.Positioner = .{},
    /// 판 3의 셋 — 받아서 담기만 한다(design 결정 53: 다시 셈하지 않고 부모 크기가 바뀌면 닫는다).
    reactive: bool = false,
    parent_w: i32 = 0,
    parent_h: i32 = 0,
    parent_serial: u32 = 0,
};

fn positionerRequest(p: *xdg.Positioner, req: xdg.Positioner.Request, po: *PosObj) void {
    switch (req) {
        .destroy => p.destroy(),
        .set_size => |r| {
            if (r.width <= 0 or r.height <= 0) return p.postError(.invalid_input, "positioner size must be greater than zero");
            po.p.w = r.width;
            po.p.h = r.height;
        },
        .set_anchor_rect => |r| {
            if (r.width < 0 or r.height < 0) return p.postError(.invalid_input, "anchor rectangle size must not be negative");
            po.p.ax = r.x;
            po.p.ay = r.y;
            po.p.aw = r.width;
            po.p.ah = r.height;
            po.p.anchor_set = true;
        },
        .set_anchor => |r| {
            const v = @backingInt(r.anchor);
            if (v < 0 or v > 8) return p.postError(.invalid_input, "unknown anchor");
            po.p.anchor = @intCast(v);
        },
        .set_gravity => |r| {
            const v = @backingInt(r.gravity);
            if (v < 0 or v > 8) return p.postError(.invalid_input, "unknown gravity");
            po.p.gravity = @intCast(v);
        },
        .set_constraint_adjustment => |r| po.p.ca = @bitCast(r.constraint_adjustment),
        .set_offset => |r| {
            po.p.ox = r.x;
            po.p.oy = r.y;
        },
        .set_reactive => po.reactive = true,
        .set_parent_size => |r| {
            po.parent_w = r.parent_width;
            po.parent_h = r.parent_height;
        },
        .set_parent_configure => |r| po.parent_serial = r.serial,
    }
}

fn positionerDestroyed(_: *xdg.Positioner, po: *PosObj) void {
    po.srv.allocator.destroy(po);
}

// ── xdg_surface · xdg_toplevel ─────────────────────────────────────────

const XdgSurface = struct {
    srv: *Server,
    resource: *xdg.Surface,
    surface: ?*Surface,
    toplevel: ?*Toplevel = null,
    phase: logic.Phase = .fresh,
    acked: bool = false,
    /// popup 역할(WY-M7 단계 B). toplevel과 둘 중 하나다.
    popup: ?*Popup = null,
    /// window geometry(WY-M7, design 결정 50) — `set_window_geometry`가 pending을 고치고 wl_surface의 commit이 옮긴다. null이면 보낸 적 없다
    /// (버퍼 전체 — 둠 · SDL · tars-wl-test).
    pending_geom: ?logic.Rect = null,
    pending_geom_set: bool = false,
    geom: ?logic.Rect = null,
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
    /// 다음 column configure는 같은 값이어도 보낸다(`answerFullscreen`).
    reanswer: bool = false,
    area_w: u32 = 0,
    area_h: u32 = 0,
    /// 마지막으로 보낸 configure(column의 같은 것 거르기).
    sent: ?Sent = null,
    /// 마지막으로 옮긴 자리(`paint`) — 포인터의 surface 좌표를 거꾸로 셀 때(단계 C).
    last_fit: ?logic.Fit = null,
    /// `last_fit`을 적은 프레임(`Server.frame_no`). 창이 안 보이게 되어도 `last_fit`은 남는다 — 누름은 이것으로 이번 프레임의 것만 센다.
    painted_frame: u64 = 0,
    /// 이 창의 클라이언트가 `set_cursor(NULL)`을 보냈다(확정 10).
    cursor_hidden: bool = false,
    /// `wl> blit` 줄을 찍은 수(WY-M6 확정 7).
    blit_lines: struct { whole: u8 = 0, part: u8 = 0 } = .{},
    /// `set_title` · `set_app_id`(TK-M5 plan 확정 4) — `NAME_BYTES`까지, UTF-8만. 바의 앱 이름은 `menubar.appName`이 고른다.
    title: Name = .{},
    app_id: Name = .{},
    /// `wl> title` 줄을 찍은 수.
    title_lines: u8 = 0,
    /// 이 창의 메뉴 객체(TK-M5 plan 확정 3). 하나뿐이다 — 둘째 `get_menu`는 `already_constructed`.
    menu: ?*Menu = null,
    /// 자식이 매핑/해제/움직임/쌓임 바뀜/크기 바뀜(WY-M7, design 결정 49) — 다음 옮기기는 통째다. `paint`가 지운다.
    tree_dirty: bool = false,
    /// `wl> subsurface` 줄을 찍은 수.
    sub_lines: u8 = 0,
    /// `wl> tree` 줄을 찍은 수(WY-M7 실측 1).
    tree_lines: u8 = 0,
    /// 이 창의 popup(만든 순 — 나중 것이 위다, xml). popup의 popup도 여기 든다.
    popups: std.ArrayList(*Popup) = .empty,
    /// `wl> popup` 줄을 찍은 수.
    pop_lines: u8 = 0,

    const Sig = struct { w: i32, h: i32, fit: logic.Fit, bs: u32 };
    const Name = struct {
        buf: [NAME_BYTES]u8 = undefined,
        len: u8 = 0,

        fn get(self: *const Name) []const u8 {
            return self.buf[0..self.len];
        }

        /// 클라이언트의 글로 바꾼다. UTF-8이 아니면 그대로 두고 false.
        fn set(self: *Name, raw: [*:0]const u8) bool {
            const text = menubar.clampUtf8(std.mem.span(raw), NAME_BYTES) orelse return false;
            @memcpy(self.buf[0..text.len], text);
            self.len = @intCast(text.len);
            return true;
        }
    };

    /// `set_title` · `set_app_id` 하나. 바뀌었으면 `wl> title id=ID app_id=… title=…`(비면 `-`, 창마다 `TITLE_LINES`번), UTF-8이
    /// 아니면 버리고 `wl> title id=ID dropped (not UTF-8)`.
    fn setName(t: *Toplevel, which: *Name, raw: [*:0]const u8) void {
        const was = which.*;
        if (!which.set(raw)) {
            if (t.title_lines < TITLE_LINES) logline.print("terminal: wl> title id={d} dropped (not UTF-8)\n", .{t.id});
            t.title_lines +|= 1;
            return;
        }
        if (std.mem.eql(u8, was.get(), which.get())) return;
        if (t.title_lines >= TITLE_LINES) return;
        t.title_lines += 1;
        const a = t.app_id.get();
        const n = t.title.get();
        logline.print("terminal: wl> title id={d} app_id={s} title={s}\n", .{ t.id, if (a.len > 0) a else "-", if (n.len > 0) n else "-" });
    }
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
        .get_popup => |r| getPopup(res, xs, r.id, r.parent, r.positioner),
        .set_window_geometry => |g| {
            if (g.width <= 0 or g.height <= 0) return res.postError(.invalid_size, "window geometry must be greater than zero");
            xs.pending_geom = .{ .x = g.x, .y = g.y, .w = g.width, .h = g.height };
            xs.pending_geom_set = true;
        },
        .ack_configure => {
            xs.acked = true;
        },
    }
}

fn xdgSurfaceDestroyed(_: *xdg.Surface, xs: *XdgSurface) void {
    if (xs.surface) |s| s.role = null;
    if (xs.toplevel) |t| t.xdg = null;
    if (xs.popup) |pp| pp.xs = null;
    // 이 xdg_surface를 부모로 둔 popup은 부모를 잃는다(자리 셈 · 그리기에서 빠진다).
    for (xs.srv.toplevels.items) |t| for (t.popups.items) |pp| if (pp.parent == xs) {
        pp.parent = null;
    };
    xs.srv.allocator.destroy(xs);
}

/// configure 하나(WY-M0 확정 4 · WY-M2 확정 4). 자리(`t.place`)가 states를 고른다(`logic.toplevelStates` — 자기
/// workspace는 fullscreen이나 maximized와 activated, column은 activated와 tiled 넷). 장식은 없다 — 장식 관리자가 늘 server_side라고
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
/// pane). `set_min_size`도 그렇다(strip의 pane 크기가 이긴다, TK design 결정 10). 전체 화면은 첫 commit 전의 것이 처음 자리를
/// 정하고(WY-M2 확정 3, `Opened.fullscreen`), 놓인 뒤의 것은 App에 `Event.fullscreen`으로 넘긴다(CR-M2, WY design 결정 56 —
/// 옮기기 · 되돌리기 · 상태 바꾸기는 App이 정한다). 제목과 app id는 담아 둔다(TK-M5 plan 확정 4) — 메뉴 바가 앱 이름으로 쓴다.
fn toplevelRequest(res: *xdg.Toplevel, req: xdg.Toplevel.Request, t: *Toplevel) void {
    switch (req) {
        .destroy => res.destroy(),
        .set_fullscreen, .unset_fullscreen => {
            const on = req == .set_fullscreen;
            t.want_fullscreen = on;
            if (t.place != null) t.srv.push(.{ .fullscreen = .{ .id = t.id, .on = on } });
        },
        .set_title => |r| t.setName(&t.title, r.title),
        .set_app_id => |r| t.setName(&t.app_id, r.app_id),
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

// ── tars_menu_manager_v1(WY-M6, design 결정 46) ─────────────────────────

/// 원래 모드의 문. bind한 클라이언트는 끝날 때까지 Cmd를 Super로 받는다 — 객체를 지워도 모드는 그대로다(xml). 포커스
/// 클라이언트가 지금 bind했으면 다음 키에서 보일 값이 바뀌어 `modifiers`가 다시 간다(`key`의 비교).
fn bindMenuManager(client: *wl.Client, srv: *Server, version: u32, id: u32) void {
    const m = tars.MenuManagerV1.create(client, version, id) catch return client.postNoMemory();
    m.setHandler(*Server, menuManagerRequest, null, srv);
    const rec = srv.recordOf(client) orelse return;
    if (rec.native) return;
    rec.native = true;
    logline.print("terminal: wl> keys pid={d} native\n", .{rec.pid});
}

/// `get_menu`(판 2, TK-M5 plan 확정 3). 판 1로 bind한 객체에는 libwayland가 이 요청을 들이지 않는다(그 판의 요청 수 밖이다).
fn menuManagerRequest(m: *tars.MenuManagerV1, req: tars.MenuManagerV1.Request, srv: *Server) void {
    switch (req) {
        .destroy => m.destroy(),
        .get_menu => |r| {
            const t: *Toplevel = @ptrCast(@alignCast(r.toplevel.getUserData() orelse return));
            const res = tars.MenuV1.create(m.getClient(), m.getVersion(), r.id) catch return m.postNoMemory();
            if (t.menu != null) return res.postError(.already_constructed, "the toplevel already has a tars_menu_v1");
            const menu = srv.allocator.create(Menu) catch {
                res.destroy();
                return m.postNoMemory();
            };
            menu.* = .{ .srv = srv, .resource = res, .toplevel = t };
            t.menu = menu;
            res.setHandler(*Menu, menuRequest, menuDestroyed, menu);
        },
    }
}

// ── tars_menu_v1(TK-M5, plan 확정 3) ───────────────────────────────────

/// 창 하나의 메뉴 모델. 쌓는 중인 것(`pending`)과 보이는 것(`current`) 둘 — `commit`이 통째로 옮긴다. 상한은 `menubar`가 지키고
/// 넘으면 프로토콜 에러다. 창이 먼저 사라지면 `toplevel`이 null이 되어 요청을 받고 버린다(xml의 inert).
const Menu = struct {
    srv: *Server,
    resource: *tars.MenuV1,
    toplevel: ?*Toplevel,
    pending: menubar.Model = .{},
    current: menubar.Model = .{},
    /// commit 수 — 0이면 아직 보인 모델이 없다(바에 이름만).
    generation: u32 = 0,
    lines: u8 = 0,
};

fn menuRequest(res: *tars.MenuV1, req: tars.MenuV1.Request, menu: *Menu) void {
    if (req == .destroy) return res.destroy();
    const t = menu.toplevel orelse return;
    const result: menubar.Error!void = switch (req) {
        .destroy => unreachable,
        .reset => menu.pending.clear(),
        .add_menu => |r| menu.pending.addMenu(std.mem.span(r.title)),
        .add_item => |r| menu.pending.addItem(r.id, std.mem.span(r.label), r.shortcut_mods, r.shortcut_key, @as(u32, @bitCast(r.flags))),
        .add_separator => menu.pending.addSeparator(),
        .commit => {
            menu.current = menu.pending;
            menu.pending.clear();
            menu.generation +%= 1;
            if (menu.generation == 0) menu.generation = 1;
            if (menu.lines < MENU_LINES) {
                menu.lines += 1;
                logline.print("terminal: wl> menu id={d} menus={d} items={d}\n", .{ t.id, menu.current.menu_count, menu.current.entry_count });
            }
            return;
        },
    };
    result catch |err| switch (err) {
        error.TooMany => res.postError(.too_many, "tars_menu_v1: more than 8 menus, 32 entries in a menu or 128 entries in all"),
        error.TooLong => res.postError(.too_long, "tars_menu_v1: a title or a label is longer than 64 bytes"),
        error.BadUtf8 => res.postError(.bad_utf8, "tars_menu_v1: a title or a label is not UTF-8"),
        error.NoMenu => res.postError(.no_menu, "tars_menu_v1: an item or a separator before any add_menu"),
    };
}

/// 객체가 사라졌다(`destroy` 또는 클라이언트의 끝) — 모델도 없어진다(바에 이름만).
fn menuDestroyed(_: *tars.MenuV1, menu: *Menu) void {
    if (menu.toplevel) |t| t.menu = null;
    menu.srv.allocator.destroy(menu);
}

fn toplevelDestroyed(_: *xdg.Toplevel, t: *Toplevel) void {
    const srv = t.srv;
    if (t.xdg) |xs| xs.toplevel = null;
    // 메뉴 객체는 남되 무력해진다(xml — 요청을 받고 버린다). 객체가 사라질 때 이 창을 찾지 않게 끊는다.
    if (t.menu) |m| m.toplevel = null;
    // 포커스 창이 사라졌다. surface가 같이 사라지므로 `leave`는 없다 — 클라이언트가 지운 것이다.
    if (srv.focused == t.id) {
        srv.focused = null;
        srv.held.clear();
        srv.sent_mods = null;
        // text_input도 같다 — leave 없이 상태만 버린다(포커스가 없으니 켜진 것이 없다).
        for (srv.text_inputs.items) |ti| if (ti.resource.getClient() == t.resource.getClient()) {
            const was = ti.state.enabled;
            ti.state.leave();
            srv.logEnabled(ti, was, t.id);
        };
    }
    // popup은 창을 잃는다(클라이언트가 지운다). 다음 프레임은 통째 — 셸 pane 위에 걸쳐 있었을 수 있다.
    for (t.popups.items) |pp| pp.top = null;
    if (t.popups.items.len > 0) srv.popup_changed = true;
    t.popups.deinit(srv.allocator);
    // 포인터도 같다 — leave 없이 포커스와 grab을 버린다.
    if (srv.ptr.focus == t.id) srv.ptr_sr = null;
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

// ── zwp_text_input_manager_v3 · zwp_text_input_v3(WY-M5, design 결정 38 · 43) ──

/// 클라이언트의 text_input 하나. 상태 셈은 `logic.TextInput`이 든다.
const TextInput = struct {
    srv: *Server,
    resource: *zwp.TextInputV3,
    state: logic.TextInput = .{},
    /// 마지막으로 들어간 surface의 창(WY-M7, design 결정 55) — `ti enable · disable to=`. enter 때 정해 둔다: 클라이언트가 끝나면 surface가 text_input보다
    /// 먼저 사라질 수 있어 그때 찾으면 못 찾는다.
    to: u32 = 0,
};

fn bindTextInputManager(client: *wl.Client, srv: *Server, version: u32, id: u32) void {
    const m = zwp.TextInputManagerV3.create(client, version, id) catch return client.postNoMemory();
    m.setHandler(*Server, textInputManagerRequest, null, srv);
}

fn textInputManagerRequest(m: *zwp.TextInputManagerV3, req: zwp.TextInputManagerV3.Request, srv: *Server) void {
    switch (req) {
        .destroy => m.destroy(),
        // seat은 하나다(`seat0`) — 어느 seat을 줘도 같다.
        .get_text_input => |r| {
            const client = m.getClient();
            const res = zwp.TextInputV3.create(client, m.getVersion(), r.id) catch return m.postNoMemory();
            const ti = srv.allocator.create(TextInput) catch {
                res.destroy();
                return m.postNoMemory();
            };
            ti.* = .{ .srv = srv, .resource = res };
            srv.text_inputs.append(srv.allocator, ti) catch {
                srv.allocator.destroy(ti);
                res.destroy();
                return m.postNoMemory();
            };
            res.setHandler(*TextInput, textInputRequest, textInputDestroyed, ti);
            // 포커스 클라이언트가 text_input을 나중에 얻었다 — 그 자리에서 `enter`(늦은 `get_keyboard`와 같은 까닭).
            if (srv.focused) |id| if (srv.find(id)) |t| if (surfaceOf(t)) |sr| if (sr.getClient() == client)
                srv.textEnterOne(ti, sr);
        },
    }
}

/// 상태 요청 셋(surrounding · change_cause · cursor_rectangle)은 받기만 한다(design 결정 38 — 오토마타가 앞뒤 글자를 안 보고
/// 후보 창이 없다). content_type은 줄 하나만 남긴다.
fn textInputRequest(res: *zwp.TextInputV3, req: zwp.TextInputV3.Request, ti: *TextInput) void {
    switch (req) {
        .destroy => res.destroy(),
        .enable => ti.state.enable(),
        .disable => ti.state.disable(),
        .set_surrounding_text, .set_text_change_cause, .set_cursor_rectangle => {},
        .set_content_type => |r| logline.print("terminal: wl> ti content purpose={d} hint=0x{x}\n", .{
            @backingInt(r.purpose), @as(u32, @bitCast(r.hint)),
        }),
        .commit => {
            const was = ti.state.enabled;
            ti.state.commit();
            ti.srv.logEnabled(ti, was, ti.to);
        },
    }
}

/// 객체가 사라졌다(`destroy` 또는 클라이언트의 끝). xml: 그 객체로 켠 것은 모두 꺼진다 — 목록에서 빼면 그렇다.
fn textInputDestroyed(_: *zwp.TextInputV3, ti: *TextInput) void {
    const srv = ti.srv;
    if (ti.state.enabled) logline.print("terminal: wl> ti disable to={d}\n", .{ti.to});
    for (srv.text_inputs.items, 0..) |x, i| if (x == ti) {
        _ = srv.text_inputs.swapRemove(i);
        break;
    };
    srv.allocator.destroy(ti);
}
