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

const App = struct {
    io: std.Io,
    alloc: std.mem.Allocator,
    font: []const u8,
    lut: [256]u8,
    /// 배율마다 다시 연다(em × 배율). 지금 배율과 그 Face 둘 — "안녕"과 14 px 표본이 같은 `body`를 쓴다.
    scale: u32 = 0,
    small: ?tk.Face = null,
    body: ?tk.Face = null,

    fn faces(self: *App, s: u32) !void {
        if (self.scale == s) return;
        inline for (.{ &self.small, &self.body }) |f| if (f.*) |*x| x.deinit();
        const fs: f32 = @floatFromInt(s);
        self.small = try tk.Face.init(self.alloc, self.font, @as(f32, @floatFromInt(theme.TK_FONT_SMALL)) * fs);
        self.body = try tk.Face.init(self.alloc, self.font, @as(f32, @floatFromInt(theme.TK_FONT)) * fs);
        self.scale = s;
    }

    fn draw(ctx: *anyopaque, frame: tk.window.Frame) anyerror!void {
        const self: *App = @ptrCast(@alignCast(ctx));
        const s = frame.scale;
        try self.faces(s);
        const c = frame.canvas;
        c.fill(theme.TK_BG);

        const W = frame.width / s;
        const rw = @min(if (W > 2 * MARGIN) W - 2 * MARGIN else W, RECT_MAX_W);
        const rx = (W - rw) / 2;
        const ry = MARGIN;
        try c.roundedRect(self.io, self.alloc, @floatFromInt(rx * s), @floatFromInt(ry * s), @floatFromInt(rw * s), @floatFromInt(RECT_H * s), @floatFromInt(theme.TK_RADIUS * s), theme.TK_ACCENT);

        // "안녕" — 사각형 가운데.
        const hello = &self.body.?;
        const hw = hello.measure("안녕");
        const hx = @as(f32, @floatFromInt((rx + rw / 2) * s)) - hw / 2.0;
        const hb: i32 = @intFromFloat(@round(@as(f32, @floatFromInt((ry + RECT_H / 2) * s)) + (hello.ascent - hello.descent) / 2.0));
        _ = try c.drawText(hello, hx, hb, "안녕", theme.TK_TEXT, &self.lut);

        // 표본 — 13 px 넷, 14 px 넷.
        var y: f32 = @floatFromInt((ry + RECT_H + MARGIN) * s);
        const left: f32 = @floatFromInt(MARGIN * s);
        for ([_]*tk.Face{ &self.small.?, &self.body.? }, 0..) |f, k| {
            if (k == 1) y += @floatFromInt(theme.TK_SPACE * s);
            const lh = @ceil(f.line_height);
            for (SAMPLE) |line| {
                const base: i32 = @intFromFloat(@round(y + f.ascent));
                _ = try c.drawText(f, left, base, line, theme.TK_TEXT, &self.lut);
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

    var app: App = .{ .io = init.io, .alloc = alloc, .font = font, .lut = tk.text.gammaLut(gamma) };
    const win = tk.Window.open(alloc, "tars-tk-demo", .{ .ctx = &app, .draw = App.draw }) catch |e| {
        tk.window.say("error open={s}", .{@errorName(e)});
        return 1;
    };
    win.run() catch |e| {
        tk.window.say("error run={s}", .{@errorName(e)});
        return 1;
    };
    return 0;
}
