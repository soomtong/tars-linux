//! `tars-tk-demo` — TK-M0의 시험 앱(plan 확정 5). 셸에서 띄우면 셸 오른쪽 column으로 열리고(WY 결정 21), configure 크기 전체를
//! 테마 바탕으로 칠한 뒤 가운데 위쪽에 둥근 사각형(반지름 12) 하나와 그 안의 "안녕"(14 px), 그 아래에 결정 4의 사람 판정용 표본
//! 네 줄을 13 px와 14 px로 그린다. `Cmd+R`(compositor의 폭 preset)이 새 configure를 낳으면 그 크기로 다시 그린다. close(`Cmd+Q`)에
//! 끝난다.
//!
//! 자리(논리 픽셀, 그릴 때 배율을 곱한다 — 게이트가 좌표를 셈할 수 있게 여기 적는다):
//! - 둥근 사각형: 폭 min(W − 48, 320), 높이 96, 가운데 정렬(x = (W − 폭) / 2, 정수 내림), 위에서 24.
//! - "안녕": 사각형 가운데(폭은 잰 값, baseline은 사각형 세로 가운데 + ascent/2 근사).
//! - 표본: 사각형 아래 24부터, 왼쪽 24에서. 13 px 네 줄 → 8 띄우고 14 px 네 줄. 줄 간격은 글꼴의 줄 높이(올림).
//!
//! - 면(TK-M1 단계 A): 왼쪽 24, 위 300에 64 × 32 `TK_TEXT` 면. 처음에는 불투명도 0(안 보임)이고 `space`가 0 ↔ 1을 바꾼다 — 부분 그리기
//!   · 버퍼 나이 · 부분 blit을 실제로 지나게 하는 스위치다(단계 B가 이것을 애니메이션으로 바꾼다).
//!
//! TK-M1부터 그림은 레이어 트리다(루트 = 바탕, 사각형 레이어 + "안녕" content, 표본 레이어 + content, 면). 창이 준 clip 안만 다시
//! 그린다 — 자리와 색은 TK-M0과 같다.
//!
//! 인자: `--font PATH`(기본 `/vendor/fonts/Pretendard-Regular.otf`) · `--gamma G`(기본 `tk.text.GAMMA` 1.8, 0.5..3.0).

const std = @import("std");
const tk = @import("tk");
const theme = tk.theme;

const SAMPLE = [_][]const u8{
    "안녕하세요. 파일 관리자 tars-files — 다운로드 · 문서 · 사진",
    "Documents  설정.conf  12,345 KB  2026-11-20 오후 6:43",
    "갉 꽃잎 뷁 쐈 읽음 됐다 흙 ㄱㄴㄷ 한글 입력기 (preedit) 밑줄",
    "The quick brown fox jumps over 0123456789 ilI1|",
};

const RECT_H: u32 = 96;
const RECT_MAX_W: u32 = 320;
const MARGIN: u32 = 24;
/// 표본 여덟 줄이 차지하는 높이(논리): 13 px 줄 높이 16 × 4 + 띄움 8 + 14 px 17 × 4 = 140(tk_test가 줄 높이 16 · 17을 지킨다). 위아래로
/// 글자가 넘칠 자리 4씩을 더해 레이어를 잡는다 — content는 레이어 밖에 그리면 안 된다(layer.zig).
const SAMPLES_H: u32 = 4 * 16 + 8 + 4 * 17;
const SAMPLES_PAD: u32 = 4;
/// 단계 A의 면(위 머리 주석).
const FACE_X: f32 = 24;
const FACE_Y: f32 = 300;
const FACE_W: f32 = 64;
const FACE_H: f32 = 32;
/// evdev KEY_SPACE.
const KEY_SPACE: u32 = 57;

const App = struct {
    io: std.Io,
    alloc: std.mem.Allocator,
    font: []const u8,
    lut: [256]u8,
    /// 배율마다 다시 연다(em × 배율). 지금 배율과 그 Face 둘 — "안녕"과 14 px 표본이 같은 `body`를 쓴다.
    scale: u32 = 0,
    small: ?tk.Face = null,
    body: ?tk.Face = null,
    tree: tk.Tree,
    root: *tk.Layer = undefined,
    rect: *tk.Layer = undefined,
    samples: *tk.Layer = undefined,
    face: *tk.Layer = undefined,

    fn faces(self: *App, s: u32) !void {
        if (self.scale == s) return;
        inline for (.{ &self.small, &self.body }) |f| if (f.*) |*x| x.deinit();
        self.small = null;
        self.body = null;
        const fs: f32 = @floatFromInt(s);
        self.small = try tk.Face.init(self.alloc, self.font, @as(f32, @floatFromInt(theme.TK_FONT_SMALL)) * fs);
        self.body = try tk.Face.init(self.alloc, self.font, @as(f32, @floatFromInt(theme.TK_FONT)) * fs);
        self.scale = s;
    }

    fn build(self: *App) !void {
        const t = &self.tree;
        self.root = try t.create(.{ .background = theme.TK_BG });
        self.rect = try t.create(.{ .background = theme.TK_ACCENT, .radius = @floatFromInt(theme.TK_RADIUS), .content = .{ .ctx = self, .draw = drawHello } });
        self.samples = try t.create(.{ .content = .{ .ctx = self, .draw = drawSamples } });
        self.face = try t.create(.{ .frame = .{ .x = FACE_X, .y = FACE_Y, .w = FACE_W, .h = FACE_H }, .background = theme.TK_TEXT, .opacity = 0 });
        try self.root.addChild(self.rect);
        try self.root.addChild(self.samples);
        try self.root.addChild(self.face);
        t.setRoot(self.root);
    }

    /// 창 층의 resize — 루트를 configure 크기로, 자식들을 그 폭에 맞춰(TK-M0과 같은 자리).
    fn resize(ctx: *anyopaque, width: u32, height: u32, s: u32) void {
        const self: *App = @ptrCast(@alignCast(ctx));
        self.tree.setScale(s);
        const W = width / s;
        const H = height / s;
        const rw = @min(if (W > 2 * MARGIN) W - 2 * MARGIN else W, RECT_MAX_W);
        const rx = (W - rw) / 2;
        self.root.setFrame(.{ .x = 0, .y = 0, .w = @floatFromInt(W), .h = @floatFromInt(H) });
        self.rect.setFrame(.{ .x = @floatFromInt(rx), .y = @floatFromInt(MARGIN), .w = @floatFromInt(rw), .h = @floatFromInt(RECT_H) });
        const sy = MARGIN + RECT_H + MARGIN - SAMPLES_PAD;
        self.samples.setFrame(.{ .x = 0, .y = @floatFromInt(sy), .w = @floatFromInt(W), .h = @floatFromInt(SAMPLES_H + 2 * SAMPLES_PAD) });
    }

    fn key(ctx: *anyopaque, code: u32, pressed: bool) void {
        const self: *App = @ptrCast(@alignCast(ctx));
        if (code == KEY_SPACE and pressed) self.face.setOpacity(if (self.face.opacity > 0) 0 else 1);
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
        const hx = @as(f32, @floatFromInt((rw / s) / 2 * s)) - hw / 2.0;
        const hb: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(RECT_H / 2 * s)) + (hello.ascent - hello.descent) / 2.0));
        _ = try p.drawGlyphs(hello, hx, hb, "안녕", theme.TK_TEXT, alpha);
    }

    /// 표본 — 13 px 넷, 14 px 넷(표본 레이어의 content).
    fn drawSamples(ctx: *anyopaque, p: *tk.Painter, size: [2]f32, alpha: u8) anyerror!void {
        _ = size;
        const self: *App = @ptrCast(@alignCast(ctx));
        const s = self.scale;
        var y: f32 = @floatFromInt(SAMPLES_PAD * s);
        const left: f32 = @floatFromInt(MARGIN * s);
        for ([_]*tk.Face{ &self.small.?, &self.body.? }, 0..) |f, k| {
            if (k == 1) y += @floatFromInt(theme.TK_SPACE * s);
            const lh = @ceil(f.line_height);
            for (SAMPLE) |line| {
                const base: i32 = @intFromFloat(@round(y + f.ascent));
                _ = try p.drawGlyphs(f, left, base, line, theme.TK_TEXT, alpha);
                y += lh;
            }
        }
    }
};

fn usage() u8 {
    tk.window.say("usage: tars-tk-demo [--font PATH] [--gamma G]", .{});
    return 2;
}

pub fn main(init: std.process.Init) !u8 {
    const alloc = init.gpa;
    var font_path: []const u8 = tk.FONT_PATH;
    var gamma: f32 = tk.text.GAMMA;
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
        } else return usage();
    }

    const font = std.Io.Dir.cwd().readFileAlloc(init.io, font_path, alloc, .unlimited) catch |e| {
        tk.window.say("error font={s} path={s}", .{ @errorName(e), font_path });
        return 1;
    };
    defer alloc.free(font);

    var app: App = .{ .io = init.io, .alloc = alloc, .font = font, .lut = tk.text.gammaLut(gamma), .tree = tk.Tree.init(alloc) };
    defer app.tree.deinit();
    defer inline for (.{ &app.small, &app.body }) |f| if (f.*) |*x| x.deinit();
    app.build() catch |e| {
        tk.window.say("error tree={s}", .{@errorName(e)});
        return 1;
    };
    const win = tk.Window.open(alloc, "tars-tk-demo", .{ .ctx = &app, .draw = App.draw, .resize = App.resize, .key = App.key }) catch |e| {
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
