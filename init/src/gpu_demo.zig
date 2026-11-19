//! DY-M2. `tars-gpu-demo [--seconds N] [--window WxH]` — 화면을 양보받아 GPU(GLES)로 그리는 데모(DY design 결정 10).
//!
//! SDL3의 KMSDRM 백엔드와 `SDL_Renderer`(opengles2)로 화면 가득 색 띠가 흐르고, 친 키의 이름이 아래에 찍힌다.
//! Esc · SIGTERM(SDL이 `SDL_EVENT_QUIT`으로 바꾼다)이면 끝난다. `--seconds N`이면 N초 뒤 스스로 끝난다(체인용).
//! `tars-fullscreen tars-gpu-demo`로 띄운다 — 양보 없이 띄우면 card0의 master가 terminal이라 화면을 못 건다.
//! WY-M2: `--window WxH`면 화면 가득 대신 그 크기의 창(`SDL_WINDOW_RESIZABLE`)을 연다. 셸에서 그냥 치면 SDL이 Wayland를
//! 골라 terminal의 Wayland 서버에 창이 되고, 서버는 셸 오른쪽 column으로 연다(WY design 결정 21). Wayland 전용 줄은
//! 없다 — 드라이버는 SDL이 고르고 `video <드라이버>` 줄이 말한다. 띠는 매 프레임 그리는 크기(`GetRenderOutputSize`)로
//! 그린다 — 창은 서버가 configure한 크기로 바뀐다. 창 모드에서는 커서를 숨기지 않는다.
//!
//! `libSDL3.so.0`은 gpu 묶음에 있다(Debian 3.2.10). 링크하지 않고 dlopen한다 — 빌드에 .so가 필요 없고, 묶음이
//! 없을 때 이유를 말할 수 있다. 그래서 이 실행 파일만 glibc 동적이다(init의 나머지는 musl 정적이라 dlopen이 없다).
//! 타입 · 상수는 SDL 3.2.10 헤더(`release-3.2.10`, DY-M2 plan 확인 5)에서 쓰는 것만 옮겼다 — 각 자리에 헤더의 줄.
//! SDL3은 3.x 안에서 ABI를 지킨다.
//!
//! 단계 줄(stderr, 체인과 실기의 `2>/tmp/gpu.log`가 같은 줄을 본다): `sdl <판>` · `video <드라이버>` · `mode WxH` ·
//! `renderer <이름>` · `gl <GL_RENDERER>` · `key <이름>` · `esc` · `quit` · `frames N in Mms`.
const std = @import("std");

const EXIT_USAGE: u8 = 2;

// ── SDL 3.2.10에서 옮긴 것 ─────────────────────────────────────────

const INIT_VIDEO: u32 = 0x20; // SDL_init.h:81
const WINDOW_FULLSCREEN: u64 = 0x1; // SDL_video.h:189
const WINDOW_RESIZABLE: u64 = 0x20; // SDL_video.h:194
const EVENT_QUIT: u32 = 0x100; // SDL_events.h:89
const EVENT_KEY_DOWN: u32 = 0x300; // SDL_events.h:168
const KEY_ESCAPE: u32 = 0x1b; // SDL_keycode.h:62
const GL_RENDERER: u32 = 0x1F01; // GLES2/gl2.h

/// `SDL_Event`는 128바이트 union이다(SDL_events.h:1040의 padding). 앞의 `type`만 늘 읽는다.
const Event = extern union {
    type: u32,
    key: KeyboardEvent,
    padding: [128]u8,
};

/// SDL_events.h:351.
const KeyboardEvent = extern struct {
    type: u32,
    reserved: u32,
    timestamp: u64,
    window_id: u32,
    which: u32,
    scancode: u32,
    key: u32,
    mod: u16,
    raw: u16,
    down: bool,
    repeat: bool,
};

/// SDL_video.h:137. `w` · `h`만 읽는다.
const DisplayMode = extern struct {
    display_id: u32,
    format: u32,
    w: c_int,
    h: c_int,
    pixel_density: f32,
    refresh_rate: f32,
    refresh_rate_numerator: c_int,
    refresh_rate_denominator: c_int,
    internal: ?*anyopaque,
};

const FRect = extern struct { x: f32, y: f32, w: f32, h: f32 };

/// dlsym으로 채우는 표. 필드 이름이 곧 심볼 이름이다(`SDL_` 뒤).
const Sdl = struct {
    GetVersion: *const fn () callconv(.c) c_int,
    GetError: *const fn () callconv(.c) [*:0]const u8,
    Init: *const fn (u32) callconv(.c) bool,
    Quit: *const fn () callconv(.c) void,
    GetCurrentVideoDriver: *const fn () callconv(.c) ?[*:0]const u8,
    GetPrimaryDisplay: *const fn () callconv(.c) u32,
    GetCurrentDisplayMode: *const fn (u32) callconv(.c) ?*const DisplayMode,
    CreateWindow: *const fn ([*:0]const u8, c_int, c_int, u64) callconv(.c) ?*anyopaque,
    CreateRenderer: *const fn (*anyopaque, ?[*:0]const u8) callconv(.c) ?*anyopaque,
    GetRendererName: *const fn (*anyopaque) callconv(.c) ?[*:0]const u8,
    SetRenderVSync: *const fn (*anyopaque, c_int) callconv(.c) bool,
    SetRenderScale: *const fn (*anyopaque, f32, f32) callconv(.c) bool,
    SetRenderDrawColor: *const fn (*anyopaque, u8, u8, u8, u8) callconv(.c) bool,
    RenderClear: *const fn (*anyopaque) callconv(.c) bool,
    RenderFillRect: *const fn (*anyopaque, *const FRect) callconv(.c) bool,
    RenderDebugText: *const fn (*anyopaque, f32, f32, [*:0]const u8) callconv(.c) bool,
    RenderPresent: *const fn (*anyopaque) callconv(.c) bool,
    GetRenderOutputSize: *const fn (*anyopaque, *c_int, *c_int) callconv(.c) bool,
    PollEvent: *const fn (*Event) callconv(.c) bool,
    GetKeyName: *const fn (u32) callconv(.c) [*:0]const u8,
    GetTicks: *const fn () callconv(.c) u64,
    HideCursor: *const fn () callconv(.c) bool,
    GL_GetProcAddress: *const fn ([*:0]const u8) callconv(.c) ?*const anyopaque,
};

// ── 줄 ─────────────────────────────────────────────────────────────

fn writeAll(bytes: []const u8) void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = std.os.linux.write(2, bytes[off..].ptr, bytes.len - off);
        if (std.os.linux.errno(n) != .SUCCESS) {
            if (std.os.linux.errno(n) == .INTR) continue;
            return;
        }
        off += n;
    }
}

fn say(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "tars-gpu-demo: " ++ fmt ++ "\n", args) catch return;
    writeAll(text);
}

// ── 인자(순수 — gpu_demo_test가 본다) ──────────────────────────────

pub const Args = struct {
    /// 0이면 Esc · 신호까지.
    seconds: u32 = 0,
    /// `--window WxH`(WY-M2). null이면 화면 가득.
    window: ?[2]u32 = null,
};

/// `--seconds N`(N > 0)과 `--window WxH`(각 변 1..8192)를 아무 순서로, 각각 한 번까지.
pub fn parseArgs(argv: []const []const u8) ?Args {
    var args: Args = .{};
    var seen_seconds = false;
    var i: usize = 0;
    while (i < argv.len) : (i += 2) {
        if (i + 1 >= argv.len) return null;
        const flag = argv[i];
        const value = argv[i + 1];
        if (std.mem.eql(u8, flag, "--seconds") and !seen_seconds) {
            args.seconds = std.fmt.parseInt(u32, value, 10) catch return null;
            if (args.seconds == 0) return null;
            seen_seconds = true;
        } else if (std.mem.eql(u8, flag, "--window") and args.window == null) {
            const x = std.mem.indexOfScalar(u8, value, 'x') orelse return null;
            const w = std.fmt.parseInt(u32, value[0..x], 10) catch return null;
            const h = std.fmt.parseInt(u32, value[x + 1 ..], 10) catch return null;
            if (w == 0 or h == 0 or w > 8192 or h > 8192) return null;
            args.window = .{ w, h };
        } else return null;
    }
    return args;
}

/// `SDL_GetVersion`의 정수(major*1000000 + minor*1000 + micro)를 `3.2.10`으로.
pub fn versionText(buf: []u8, v: c_int) []const u8 {
    const u: u32 = @intCast(@max(v, 0));
    return std.fmt.bufPrint(buf, "{d}.{d}.{d}", .{ u / 1000000, u / 1000 % 1000, u % 1000 }) catch "?";
}

/// 색 띠 i의 색. 시간(ms)에 따라 돈다 — 매 frame이 다르므로 화면이 멈추면 눈에 띈다.
pub fn bandColor(i: u32, ms: u64) [3]u8 {
    const phase: u32 = @intCast((ms / 8 + @as(u64, i) * 32) % 768);
    const ramp: u8 = @intCast(phase % 256);
    return switch (phase / 256) {
        0 => .{ 255 - ramp, ramp, 64 },
        1 => .{ 64, 255 - ramp, ramp },
        else => .{ ramp, 64, 255 - ramp },
    };
}

// ── 실행 ───────────────────────────────────────────────────────────

/// 끝내기의 시간을 재는 시계. SDL_Quit 뒤에도 읽으므로 SDL의 것이 아니다.
fn nowMs() u64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / 1_000_000;
}

fn usage() u8 {
    writeAll(
        \\usage: tars-gpu-demo [--seconds N] [--window WxH]
        \\  draw moving colour bands with SDL3 + OpenGL ES on the whole screen and
        \\  show the name of each key. Esc ends it; --seconds ends it after N
        \\  seconds. Needs the gpu bundle. Run it under tars-fullscreen. --window
        \\  opens a resizable WxH window instead (a Wayland window in a TARS shell).
        \\
    );
    return EXIT_USAGE;
}

fn load() ?Sdl {
    const handle = std.c.dlopen("libSDL3.so.0", .{ .NOW = true }) orelse {
        say("libSDL3.so.0 not found — the gpu bundle is not here", .{});
        return null;
    };
    var sdl: Sdl = undefined;
    inline for (@typeInfo(Sdl).@"struct".field_names) |name| {
        const sym = std.c.dlsym(handle, "SDL_" ++ name) orelse {
            say("libSDL3.so.0 has no SDL_{s}", .{name});
            return null;
        };
        @field(sdl, name) = @ptrCast(@alignCast(sym));
    }
    return sdl;
}

pub fn main(init: std.process.Init.Minimal) u8 {
    const vector = init.args.vector;
    var spans: [4][]const u8 = undefined;
    if (vector.len > spans.len + 1) return usage();
    for (vector[1..], 0..) |a, i| spans[i] = std.mem.span(a);
    const args = parseArgs(spans[0 .. vector.len - 1]) orelse return usage();

    const sdl = load() orelse return 1;
    var vbuf: [32]u8 = undefined;
    say("sdl {s}", .{versionText(&vbuf, sdl.GetVersion())});

    if (!sdl.Init(INIT_VIDEO)) {
        say("init failed: {s}", .{sdl.GetError()});
        return 1;
    }
    say("video {s}", .{sdl.GetCurrentVideoDriver() orelse "?"});

    const mode = sdl.GetCurrentDisplayMode(sdl.GetPrimaryDisplay()) orelse {
        say("no display mode: {s}", .{sdl.GetError()});
        return 1;
    };
    say("mode {d}x{d}", .{ mode.w, mode.h });
    // 창 모드(WY-M2)는 그 크기 · RESIZABLE — RESIZABLE이 아니면 SDL은 서버의 configure 크기를 따르지 않는다(WY-M2 조사 1).
    const win_w: c_int = if (args.window) |wh| @intCast(wh[0]) else mode.w;
    const win_h: c_int = if (args.window) |wh| @intCast(wh[1]) else mode.h;
    const flags: u64 = if (args.window != null) WINDOW_RESIZABLE else WINDOW_FULLSCREEN;
    if (args.window != null) say("window {d}x{d}", .{ win_w, win_h });
    const window = sdl.CreateWindow("tars-gpu-demo", win_w, win_h, flags) orelse {
        say("window failed: {s}", .{sdl.GetError()});
        return 1;
    };
    // design 결정 10은 GLES다 — 이름을 비워 두면 SDL이 고르는 순서(gpu · opengl · …)에 맡기게 된다.
    const renderer = sdl.CreateRenderer(window, "opengles2") orelse {
        say("renderer failed: {s}", .{sdl.GetError()});
        return 1;
    };
    say("renderer {s}", .{sdl.GetRendererName(renderer) orelse "?"});
    // 렌더러를 만든 직후에는 그 GL 문맥이 현재 문맥이다.
    if (sdl.GL_GetProcAddress("glGetString")) |p| {
        const getString: *const fn (u32) callconv(.c) ?[*:0]const u8 = @ptrCast(@alignCast(p));
        say("gl {s}", .{getString(GL_RENDERER) orelse "?"});
    } else say("gl ?", .{});
    _ = sdl.SetRenderVSync(renderer, 1);
    if (args.window == null) _ = sdl.HideCursor();

    const bands: u32 = 12;
    const start = sdl.GetTicks();
    var frames: u64 = 0;
    var last_key: [64:0]u8 = @splat(0);
    @memcpy(last_key[0..13], "press any key");
    var running = true;
    // 끝내라는 말(Esc · QUIT)을 받은 때. 탈출 조합은 SIGTERM 뒤 2초에 SIGKILL이라(DY design 결정 8b) 끝내기가 얼마나
    // 걸리는지를 줄로 남긴다.
    var asked: u64 = 0;
    while (running) {
        var ev: Event = undefined;
        while (sdl.PollEvent(&ev)) {
            if (ev.type == EVENT_QUIT) {
                say("quit", .{});
                running = false;
                asked = nowMs();
            } else if (ev.type == EVENT_KEY_DOWN and !ev.key.repeat) {
                if (ev.key.key == KEY_ESCAPE) {
                    say("esc", .{});
                    running = false;
                    asked = nowMs();
                    continue;
                }
                const name = std.mem.span(sdl.GetKeyName(ev.key.key));
                say("key {s}", .{name});
                const n = @min(name.len, last_key.len);
                @memset(&last_key, 0);
                @memcpy(last_key[0..n], name[0..n]);
            }
        }
        const now = sdl.GetTicks();
        if (args.seconds != 0 and now - start >= @as(u64, args.seconds) * 1000) running = false;

        // 그리는 크기는 매 프레임 묻는다 — 창은 서버가 바꾼다(column 폭, `Cmd+R`).
        var out_w: c_int = win_w;
        var out_h: c_int = win_h;
        _ = sdl.GetRenderOutputSize(renderer, &out_w, &out_h);
        const w: f32 = @floatFromInt(out_w);
        const h: f32 = @floatFromInt(out_h);
        _ = sdl.SetRenderDrawColor(renderer, 16, 16, 24, 255);
        _ = sdl.RenderClear(renderer);
        const bw = w / @as(f32, @floatFromInt(bands));
        var i: u32 = 0;
        while (i < bands) : (i += 1) {
            const c = bandColor(i, now);
            _ = sdl.SetRenderDrawColor(renderer, c[0], c[1], c[2], 255);
            const rect: FRect = .{ .x = bw * @as(f32, @floatFromInt(i)), .y = h * 0.1, .w = bw - 4, .h = h * 0.7 };
            _ = sdl.RenderFillRect(renderer, &rect);
        }
        // 디버그 글꼴은 8px다 — 4배로.
        _ = sdl.SetRenderScale(renderer, 4, 4);
        _ = sdl.SetRenderDrawColor(renderer, 240, 240, 240, 255);
        _ = sdl.RenderDebugText(renderer, 8, h * 0.85 / 4, &last_key);
        _ = sdl.SetRenderScale(renderer, 1, 1);
        _ = sdl.RenderPresent(renderer);
        frames += 1;
    }
    say("frames {d} in {d}ms", .{ frames, sdl.GetTicks() - start });
    if (asked == 0) asked = nowMs();
    say("left the loop {d}ms after the request", .{nowMs() - asked});
    sdl.Quit();
    say("shut down {d}ms after the request", .{nowMs() - asked});
    // main에서 돌아가지 않는다 — glibc의 exit가 Mesa · LLVM의 전역 소멸자를 부르는데, 그것은 아무것도 놓지 않으면서
    // (SDL이 쥔 화면 · fd는 위의 SDL_Quit이 놓았고 나머지는 커널이 닫는다) 느린 기계에서는 탈출 조합의 2초를 넘긴다
    // (DY-M2 plan 결과 — TCG의 QEMU에서 SIGKILL을 받았다).
    std.os.linux.exit_group(0);
}
