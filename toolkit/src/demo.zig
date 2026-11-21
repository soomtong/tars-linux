//! `tars-tk-demo` — 툴킷의 시험 앱(TK-M0 plan 확정 5, TK-M1 plan 확정 9). 셸에서 띄우면 셸 오른쪽 column으로 열리고(WY 결정 21),
//! configure 크기 전체를 테마 바탕으로 칠한 뒤 가운데 위쪽에 둥근 사각형(반지름 12) 하나와 그 안의 "안녕"(14 px), 그 아래에 결정 4의
//! 사람 판정용 표본 네 줄을 13 px와 14 px로, 그 아래에 면 하나를 그린다. `Cmd+R`(compositor의 폭 preset)이 새 configure를 낳으면 그
//! 크기로 다시 배치한다. `space`가 면의 불투명도를 0 → 1(다시 누르면 1 → 0)로 애니메이션한다. close(`Cmd+Q`)에 끝난다.
//!
//! 그림은 레이어 트리이고 배치는 세로 스택 하나다(R-CA-4): 위 여백 24, 간격 16(`tokens.space.l`), 가운데 정렬. 창이 준 clip 안만
//! 다시 그린다.
//!
//! 자리(논리 픽셀, 그릴 때 배율을 곱한다 — 게이트가 좌표를 셈할 수 있게 여기 적는다. W = configure 폭):
//! - 둥근 사각형: 폭 min(W − 48, 320), 높이 96, x = (W − 폭) / 2(내림), y 24 — TK-M0과 같은 자리.
//! - "안녕": 사각형 가운데(폭은 잰 값, baseline은 사각형 세로 가운데 + ascent/2 근사).
//! - 표본 레이어: y 136, 폭 W, 높이 156. 글자는 그 안 위 8(= y 144)부터 왼쪽 24에서 — 13 px 네 줄 → 8 띄우고 14 px 네 줄(줄 간격은 글꼴의
//!   줄 높이 올림). 위아래 8은 글자가 레이어 밖으로 넘지 않게 둔 여유다(content는 레이어 밖에 그리면 안 된다 — layer.zig).
//! - 면: 64 × 32, x = (W − 64) / 2(내림), y 308, 색 `tokens.color.text`. 처음 불투명도 0(안 보임). 616 폭에서 x 276, 1240 폭에서 x 588.
//!
//! 인자: `--font PATH`(기본 `/vendor/fonts/Pretendard-Regular.otf`) · `--gamma G`(기본 `tk.text.GAMMA` 1.8, 0.5..3.0) ·
//! `--anim-ms N`(면 애니메이션 길이, 기본 250, 0..60000) · `--easing ease-out|linear`(기본 ease-out — 체인은 linear 3000).

const std = @import("std");
const tk = @import("tk");
const tokens = tk.tokens;

const SAMPLE = [_][]const u8{
    "안녕하세요. 파일 관리자 tars-files — 다운로드 · 문서 · 사진",
    "Documents  설정.conf  12,345 KB  2026-11-20 오후 6:43",
    "갉 꽃잎 뷁 쐈 읽음 됐다 흙 ㄱㄴㄷ 한글 입력기 (preedit) 밑줄",
    "The quick brown fox jumps over 0123456789 ilI1|",
};

const RECT_H: f32 = 96;
const RECT_MAX_W: f32 = 320;
const MARGIN: f32 = 24;
/// 표본 여덟 줄의 높이: 13 px 줄 높이 16 × 4 + 띄움 8 + 14 px 17 × 4 = 140(tk_test가 줄 높이 16 · 17을 지킨다).
const SAMPLES_H: f32 = 4 * 16 + 8 + 4 * 17;
const SAMPLES_PAD: f32 = 8;
const FACE_W: f32 = 64;
const FACE_H: f32 = 32;

const App = struct {
    io: std.Io,
    alloc: std.mem.Allocator,
    font: []const u8,
    lut: [256]u8,
    anim_ms: u32,
    easing: tk.Easing,
    /// 배율마다 다시 연다(em × 배율). 지금 배율과 그 Face 둘 — "안녕"과 14 px 표본이 같은 `body`를 쓴다.
    scale: u32 = 0,
    small: ?tk.Face = null,
    body: ?tk.Face = null,
    tree: tk.Tree,
    root: *tk.Layer = undefined,
    rect: *tk.Layer = undefined,
    samples: *tk.Layer = undefined,
    face: *tk.Layer = undefined,
    /// 면이 향하는 끝(`space`마다 뒤집힌다).
    face_on: bool = false,

    fn faces(self: *App, s: u32) !void {
        if (self.scale == s) return;
        inline for (.{ &self.small, &self.body }) |f| if (f.*) |*x| x.deinit();
        self.small = null;
        self.body = null;
        const fs: f32 = @floatFromInt(s);
        self.small = try tk.Face.init(self.alloc, self.font, tokens.font.small * fs);
        self.body = try tk.Face.init(self.alloc, self.font, tokens.font.body * fs);
        self.scale = s;
    }

    fn build(self: *App) !void {
        const t = &self.tree;
        self.root = try t.create(.{ .background = tokens.color.bg });
        self.rect = try t.create(.{ .background = tokens.color.accent, .radius = tokens.radius.m, .content = .{ .ctx = self, .draw = drawHello } });
        self.samples = try t.create(.{ .content = .{ .ctx = self, .draw = drawSamples } });
        self.face = try t.create(.{ .background = tokens.color.text, .opacity = 0 });
        try self.root.addChild(self.rect);
        try self.root.addChild(self.samples);
        try self.root.addChild(self.face);
        t.setRoot(self.root);
    }

    /// 창 층의 resize — 루트를 configure 크기로, 자식들은 세로 스택으로(머리 주석의 자리).
    fn resize(ctx: *anyopaque, width: u32, height: u32, s: u32) void {
        const self: *App = @ptrCast(@alignCast(ctx));
        self.tree.setScale(s);
        const W: f32 = @floatFromInt(width / s);
        const H: f32 = @floatFromInt(height / s);
        self.root.setFrame(.{ .x = 0, .y = 0, .w = W, .h = H });
        const rw = @min(if (W > 2 * MARGIN) W - 2 * MARGIN else W, RECT_MAX_W);
        const stack: tk.Stack = .{
            .axis = .vertical,
            .spacing = tokens.space.l,
            .padding = .{ .top = MARGIN },
            .alignment = .center,
            .items = &.{
                .{ .layer = self.rect, .size = RECT_H, .cross = rw },
                .{ .layer = self.samples, .size = SAMPLES_H + 2 * SAMPLES_PAD, .cross = W },
                .{ .layer = self.face, .size = FACE_H, .cross = FACE_W },
            },
        };
        stack.layout(.{ .x = 0, .y = 0, .w = W, .h = H });
    }

    /// 입력(TK-M2 — 창 층의 `Handler.input`). 지금 화면이 쓰는 것은 `space`의 누름 하나다(반복은 무시 — 누르고 있어도 한 번).
    fn input(ctx: *anyopaque, ev: tk.input.Event) void {
        const self: *App = @ptrCast(@alignCast(ctx));
        const k = switch (ev) {
            .key => |k| k,
            else => return,
        };
        if (k.key != .space or !k.pressed or k.repeat) return;
        self.face_on = !self.face_on;
        self.tree.animate(self.face, .{ .opacity = if (self.face_on) 1 else 0 }, self.anim_ms, self.easing) catch |e| {
            tk.window.say("error anim={s}", .{@errorName(e)});
        };
    }

    fn tick(ctx: *anyopaque, now_ns: u64) void {
        const self: *App = @ptrCast(@alignCast(ctx));
        self.tree.tick(now_ns);
    }

    fn draw(ctx: *anyopaque, frame: tk.window.Frame) anyerror!void {
        const self: *App = @ptrCast(@alignCast(ctx));
        try self.faces(frame.scale);
        try tk.drawTree(self.io, self.alloc, &self.tree, frame, &self.lut);
    }

    /// "안녕" — 사각형 가운데(사각형 레이어의 content, 레이어 왼쪽 위가 (0, 0)).
    fn drawHello(ctx: *anyopaque, p: *tk.Painter, size: [2]f32, alpha: u8) anyerror!void {
        const self: *App = @ptrCast(@alignCast(ctx));
        const s = self.scale;
        const hello = &self.body.?;
        const hw = hello.measure("안녕");
        const rw: u32 = @intFromFloat(size[0]);
        const half_h: u32 = @intFromFloat(RECT_H / 2);
        const hx = @as(f32, @floatFromInt((rw / s) / 2 * s)) - hw / 2.0;
        const hb: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(half_h * s)) + (hello.ascent - hello.descent) / 2.0));
        _ = try p.drawGlyphs(hello, hx, hb, "안녕", tokens.color.text, alpha);
    }

    /// 표본 — 13 px 넷, 14 px 넷(표본 레이어의 content).
    fn drawSamples(ctx: *anyopaque, p: *tk.Painter, size: [2]f32, alpha: u8) anyerror!void {
        _ = size;
        const self: *App = @ptrCast(@alignCast(ctx));
        const s: f32 = @floatFromInt(self.scale);
        var y: f32 = SAMPLES_PAD * s;
        const left: f32 = MARGIN * s;
        for ([_]*tk.Face{ &self.small.?, &self.body.? }, 0..) |f, k| {
            if (k == 1) y += tokens.space.m * s;
            const lh = @ceil(f.line_height);
            for (SAMPLE) |line| {
                const base: i32 = @intFromFloat(@round(y + f.ascent));
                _ = try p.drawGlyphs(f, left, base, line, tokens.color.text, alpha);
                y += lh;
            }
        }
    }
};

fn usage() u8 {
    tk.window.say("usage: tars-tk-demo [--font PATH] [--gamma G] [--anim-ms N] [--easing ease-out|linear]", .{});
    return 2;
}

pub fn main(init: std.process.Init) !u8 {
    const alloc = init.gpa;
    var font_path: []const u8 = tk.FONT_PATH;
    var gamma: f32 = tk.text.GAMMA;
    var anim_ms: u32 = 250;
    var easing: tk.Easing = .ease_out_cubic;
    const argv = try init.minimal.args.toSlice(init.arena.allocator());
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "--font") and i + 1 < argv.len) {
            i += 1;
            font_path = argv[i];
        } else if (std.mem.eql(u8, a, "--gamma") and i + 1 < argv.len) {
            i += 1;
            gamma = std.fmt.parseFloat(f32, argv[i]) catch return usage();
            if (gamma < 0.5 or gamma > 3.0) return usage();
        } else if (std.mem.eql(u8, a, "--anim-ms") and i + 1 < argv.len) {
            i += 1;
            anim_ms = std.fmt.parseInt(u32, argv[i], 10) catch return usage();
            if (anim_ms > 60000) return usage();
        } else if (std.mem.eql(u8, a, "--easing") and i + 1 < argv.len) {
            i += 1;
            if (std.mem.eql(u8, argv[i], "linear")) {
                easing = .linear;
            } else if (std.mem.eql(u8, argv[i], "ease-out")) {
                easing = .ease_out_cubic;
            } else return usage();
        } else return usage();
    }

    const font = std.Io.Dir.cwd().readFileAlloc(init.io, font_path, alloc, .unlimited) catch |e| {
        tk.window.say("error font={s} path={s}", .{ @errorName(e), font_path });
        return 1;
    };
    defer alloc.free(font);

    var app: App = .{
        .io = init.io,
        .alloc = alloc,
        .font = font,
        .lut = tk.text.gammaLut(gamma),
        .anim_ms = anim_ms,
        .easing = easing,
        .tree = tk.Tree.init(alloc),
    };
    defer app.tree.deinit();
    defer inline for (.{ &app.small, &app.body }) |f| if (f.*) |*x| x.deinit();
    app.build() catch |e| {
        tk.window.say("error tree={s}", .{@errorName(e)});
        return 1;
    };
    const win = tk.Window.open(alloc, "tars-tk-demo", .{
        .ctx = &app,
        .draw = App.draw,
        .resize = App.resize,
        .input = App.input,
        .tick = App.tick,
    }) catch |e| {
        tk.window.say("error open={s}", .{@errorName(e)});
        return 1;
    };
    defer win.deinit();
    tk.connect(&app.tree, win);
    win.run() catch |e| {
        tk.window.say("error run={s}", .{@errorName(e)});
        return 1;
    };
    return 0;
}
