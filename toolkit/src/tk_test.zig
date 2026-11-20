//! 툴킷의 호스트 검사(R-ARCH-4 — Wayland 없이, 판은 메모리 배열). `zig build test`가 빌드 호스트에서 돌린다. 글꼴을
//! `vendor/fonts/Pretendard-Regular.otf` 상대 경로로 읽으므로 toolkit/ 안에서 돌린다(게이트가 그렇게 한다).
//!
//! 표는 이 판(z2d v0.13.2 · stb_truetype v1.26 · Pretendard 1.3.9)의 실측이다. 판을 올리면 다시 잰다.
//!
//! 덩어리(TK-M1부터):
//! 1 CG — 둥근 사각형 · 글자의 픽셀 표(TK-M0의 표를 `Painter`로), 빠른 길 · clip · translate.
//! 2 CA — 더티 = 옛 ∪ 새, masks 조상이 자름, hidden · 붙지 않은 레이어.
//! 3 부분 = 통째 — 무작위 트리에 속성을 여러 번 바꾸며 더티만 다시 그린 판과 새로 통째 그린 판을 바이트로 비교(clip 임시 판).
//! 4 버퍼 나이 — 버퍼 둘을 번갈아(가끔 같은 것 두 번, 가끔 오래 쉼) 흉내 내 각 버퍼가 매번 통째 그림과 같은가.

const std = @import("std");
const theme = @import("theme");
const geom = @import("tk_geom");
const Rect = geom.Rect;
const RectF = geom.RectF;
const cg = @import("tk_cg");
const Painter = cg.Painter;
const text = cg.text;
const ca = @import("tk_ca");
const Age = @import("window/age.zig").Age;

const W: u32 = 200;
const H: u32 = 120;
const WHOLE: Rect = .{ .x = 0, .y = 0, .w = W, .h = H };

var failures: u32 = 0;

fn check(ok: bool, comptime name: []const u8, args: anytype) void {
    if (ok) {
        std.debug.print("tk_test: " ++ name ++ " OK\n", args);
    } else {
        std.debug.print("tk_test: FAIL " ++ name ++ "\n", args);
        failures += 1;
    }
}

fn px(pixels: []const u32, x: u32, y: u32) u32 {
    return pixels[y * W + x] & 0x00FFFFFF;
}

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const alloc = init.gpa;
    var pixels: [W * H]u32 = undefined;
    var scratch: [W * H]u32 = undefined;
    const lut1 = text.gammaLut(1.0);

    // ── 1 CG: 둥근 사각형(20, 20, 160 × 80, r 12) ─────────────────────
    {
        var p = Painter.begin(io, alloc, &pixels, W, H, &scratch, WHOLE, &lut1);
        p.fillRect(WHOLE, theme.TK_BG, 255);
        try p.fillRoundedRect(.{ .x = 20, .y = 20, .w = 160, .h = 80 }, 12, theme.TK_ACCENT, 255);
        p.finish();
    }
    const c = &pixels;
    check(px(c, 100, 60) == theme.TK_ACCENT, "rect centre (100,60) is TK_ACCENT {x:0>6}", .{px(c, 100, 60)});
    check(px(c, 20, 20) == theme.TK_BG, "corner outside (20,20) is TK_BG {x:0>6}", .{px(c, 20, 20)});
    check(px(c, 19, 60) == theme.TK_BG and px(c, 20, 60) == theme.TK_ACCENT, "left edge: x=19 bg, x=20 fill", .{});
    check(px(c, 179, 60) == theme.TK_ACCENT and px(c, 180, 60) == theme.TK_BG, "right edge: x=179 fill, x=180 bg", .{});
    check(px(c, 100, 19) == theme.TK_BG and px(c, 100, 20) == theme.TK_ACCENT, "top edge: y=19 bg, y=20 fill", .{});
    // 모서리 대각선(원의 중심 (32,32)에서 반지름 12 — 경계는 (23.5,23.5) 언저리). 그 칸은 바탕도 채움도 아닌 중간값이다(AA).
    var mid: u32 = 0;
    var d: u32 = 20;
    while (d < 32) : (d += 1) {
        const v = px(c, d, d);
        if (v != theme.TK_BG and v != theme.TK_ACCENT) mid += 1;
    }
    check(mid >= 1, "corner diagonal has {d} antialiased pixel(s)", .{mid});
    check(px(c, 32, 20) == theme.TK_ACCENT and px(c, 20, 32) == theme.TK_ACCENT, "arc ends (32,20) (20,32) are filled", .{});

    // ── 1 CG: 빠른 길 · clip · translate · 알파 ──────────────────────────
    {
        @memset(&pixels, 0xFF000000);
        var p = Painter.begin(io, alloc, &pixels, W, H, &scratch, WHOLE, &lut1);
        p.translate(10, 5);
        p.pushClip(.{ .x = 0, .y = 0, .w = 20, .h = 20 }); // 버퍼 (10,5)..(30,25)
        p.fillRect(.{ .x = -5, .y = -5, .w = 100, .h = 100 }, 0x112233, 255);
        p.popClip();
        p.translate(-10, -5);
        p.fillRect(.{ .x = 100, .y = 100, .w = 10, .h = 10 }, 0xFFFFFF, 128);
        p.finish();
    }
    check(px(c, 10, 5) == 0x112233 and px(c, 29, 24) == 0x112233 and px(c, 30, 24) == 0 and px(c, 9, 5) == 0 and px(c, 10, 25) == 0, "fillRect: translate (10,5) + pushClip 20x20 cuts exactly", .{});
    check(px(c, 105, 105) == 0x808080, "fillRect alpha 128 of white over black is 808080 ({x:0>6})", .{px(c, 105, 105)});
    {
        // 프레임 clip이 판의 일부면 임시 판에 그리고 finish가 그 사각형만 옮긴다 — 밖은 그대로.
        @memset(&pixels, 0xFF000000);
        var p = Painter.begin(io, alloc, &pixels, W, H, &scratch, .{ .x = 50, .y = 40, .w = 30, .h = 20 }, &lut1);
        check(p.scratch_used, "a partial frame clip uses the scratch surface", .{});
        p.fillRect(WHOLE, theme.TK_BG, 255);
        try p.fillRoundedRect(.{ .x = 0, .y = 0, .w = 200, .h = 120 }, 30, theme.TK_ACCENT, 255);
        p.finish();
        check(px(c, 50, 40) == theme.TK_ACCENT and px(c, 79, 59) == theme.TK_ACCENT and px(c, 49, 40) == 0 and px(c, 80, 40) == 0 and px(c, 50, 60) == 0, "scratch clip 30x20 at (50,40): inside drawn, outside untouched", .{});
    }

    // ── 1 CG: 글자 ────────────────────────────────────────────────────
    const font = try std.Io.Dir.cwd().readFileAlloc(io, "vendor/fonts/Pretendard-Regular.otf", alloc, .unlimited);
    defer alloc.free(font);

    var f13 = try text.Face.init(alloc, font, 13);
    defer f13.deinit();
    var f14 = try text.Face.init(alloc, font, 14);
    defer f14.deinit();
    // Pretendard: upm 2048, ascent 1950, descent −494, gap 0 → 13 px에서 12.38 + 3.14 = 15.51(올림 16, design 확인 4).
    check(@ceil(f13.line_height) == 16, "13 px line height {d:.2} ceils to 16", .{f13.line_height});
    check(@ceil(f14.line_height) == 17, "14 px line height {d:.2} ceils to 17", .{f14.line_height});
    const a_han = f14.advance('한');
    const a_i = f14.advance('i');
    check(a_han > 10 and a_han < 15 and a_i > 2 and a_i < a_han / 2, "proportional: 14 px 한 {d:.3} vs i {d:.3}", .{ a_han, a_i });

    // 서브픽셀 칸: 같은 글자를 0 · 2칸으로 구우면 coverage가 다르다.
    const g0 = try f14.get('l', 0);
    const g2 = try f14.get('l', 2);
    check(!std.mem.eql(u8, g0.pixels, g2.pixels) or g0.width != g2.width, "subpixel 0 and 2/4 give different bitmaps for 'l'", .{});
    const sp = text.splitPen(10.9);
    check(sp.ix == 11 and sp.sub == 0, "splitPen(10.9) rounds to the next pixel ({d},{d})", .{ sp.ix, sp.sub });

    // 감마 1.0은 그대로다.
    var same = true;
    for (lut1, 0..) |v, i| same = same and v == i;
    check(same, "gamma 1.0 table is the identity", .{});
    // 기본 감마(1.8, 결정 4의 판정)는 끝점을 지키고 중간값을 밝힌다 — 어두운 바탕에서 획이 굵어진다.
    const lutd = text.gammaLut(text.GAMMA);
    check(lutd[0] == 0 and lutd[255] == 255 and lutd[128] > 128, "default gamma {d:.1}: 0 -> {d}, 128 -> {d}, 255 -> {d}", .{ text.GAMMA, lutd[0], lutd[128], lutd[255] });

    // "안녕"(14 px)을 (60, baseline 60)에 — 상자 안 잉크와 중간값.
    var end: f32 = 0;
    {
        var p = Painter.begin(io, alloc, &pixels, W, H, &scratch, WHOLE, &lut1);
        p.fillRect(WHOLE, theme.TK_BG, 255);
        end = try p.drawGlyphs(&f14, 60, 60, "안녕", theme.TK_TEXT, 255);
        p.finish();
    }
    var ink: u32 = 0;
    var full: u32 = 0;
    var y: u32 = 40;
    while (y < 66) : (y += 1) {
        var x: u32 = 58;
        while (x < 92) : (x += 1) {
            const v = px(c, x, y);
            if (v != theme.TK_BG) ink += 1;
            if (v == theme.TK_TEXT) full += 1;
        }
    }
    check(ink > 0 and ink > full, "안녕 box: ink {d}, full {d}, antialiased {d}, pen end {d:.2}", .{ ink, full, ink - full, end });
    check(px(c, 10, 10) == theme.TK_BG, "outside the text stays TK_BG", .{});

    // ── 2 CA: 더티 ───────────────────────────────────────────────────
    {
        var t = ca.Tree.init(alloc);
        defer t.deinit();
        const root = try t.create(.{ .frame = .{ .x = 0, .y = 0, .w = W, .h = H }, .background = theme.TK_BG });
        const a = try t.create(.{ .frame = .{ .x = 10, .y = 10, .w = 20, .h = 20 }, .background = theme.TK_ACCENT });
        const box = try t.create(.{ .frame = .{ .x = 100, .y = 50, .w = 40, .h = 30 }, .masks = true });
        const kid = try t.create(.{ .frame = .{ .x = 30, .y = 20, .w = 30, .h = 30 }, .background = theme.TK_TEXT });
        const loose = try t.create(.{ .frame = .{ .x = 0, .y = 0, .w = 5, .h = 5 } });
        try box.addChild(kid);
        try root.addChild(a);
        try root.addChild(box);
        t.setRoot(root);
        _ = t.takeDirty();

        a.setFrame(.{ .x = 50, .y = 15, .w = 20, .h = 20 });
        const d1 = t.takeDirty();
        check(d1 != null and Rect.eql(d1.?, .{ .x = 10, .y = 10, .w = 60, .h = 25 }), "move: dirty = old (10,10 20x20) cover new (50,15 20x20) = 10,10 60x25", .{});
        a.setFrame(.{ .x = 50.5, .y = 15.25, .w = 20, .h = 20 });
        const d2 = t.takeDirty();
        check(d2 != null and Rect.eql(d2.?, .{ .x = 50, .y = 15, .w = 21, .h = 21 }), "fractional move rounds outward: 50,15 21x21", .{});
        kid.setFrame(.{ .x = 35, .y = 20, .w = 30, .h = 30 });
        const d3 = t.takeDirty();
        // kid의 화면 사각형 130..165 · 135..170 → masks 조상 box(100..140, 50..80)로 자름 → 130..140 × 70..80.
        check(d3 != null and Rect.eql(d3.?, .{ .x = 130, .y = 70, .w = 10, .h = 10 }), "a child of a masking layer is clipped to it: 130,70 10x10", .{});
        a.setHidden(true);
        const d4 = t.takeDirty();
        check(d4 != null and Rect.eql(d4.?, .{ .x = 50, .y = 15, .w = 21, .h = 21 }), "hiding a layer dirties its rect", .{});
        a.setHidden(true);
        check(t.takeDirty() == null, "setting the same value dirties nothing", .{});
        loose.setFrame(.{ .x = 1, .y = 1, .w = 9, .h = 9 });
        check(t.takeDirty() == null, "a layer not attached to the root dirties nothing", .{});
        box.setMasks(false);
        const d5 = t.takeDirty();
        check(d5 != null and Rect.eql(d5.?, .{ .x = 100, .y = 50, .w = 65, .h = 50 }), "unmasking: dirty covers the overflowing child (100,50 65x50)", .{});
        t.setScale(2);
        const d6 = t.takeDirty();
        check(d6 != null and Rect.eql(d6.?, .{ .x = 0, .y = 0, .w = 2 * W, .h = 2 * H }), "scale 2 dirties the whole tree in physical pixels", .{});
    }

    // ── 3 부분 = 통째 · 4 버퍼 나이 ─────────────────────────────────────
    try randomTrees(io, alloc, &f13, &lut1);

    if (failures != 0) {
        std.debug.print("tk_test: {d} failure(s)\n", .{failures});
        return 1;
    }
    std.debug.print("tk_test: all checks passed\n", .{});
    return 0;
}

// ── 무작위 트리 ──────────────────────────────────────────────────────

const Label = struct {
    face: *text.Face,
    str: []const u8,

    fn draw(ctx: *anyopaque, p: *Painter, size: [2]f32, alpha: u8) anyerror!void {
        const self: *Label = @ptrCast(@alignCast(ctx));
        _ = size;
        _ = try p.drawGlyphs(self.face, 2.25, @intFromFloat(@ceil(self.face.ascent) + 2), self.str, theme.TK_TEXT, alpha);
    }
};

const N_LAYERS = 14;
const COLORS = [_]u32{ theme.TK_ACCENT, theme.TK_TEXT, 0x804020, 0x20A060, 0x6040C0 };

fn render(io: std.Io, alloc: std.mem.Allocator, t: *ca.Tree, pixels: []u32, scratch: []u32, clip: Rect, lut: *const [256]u8) !void {
    var p = Painter.begin(io, alloc, pixels, W, H, scratch, clip, lut);
    _ = try t.draw(&p);
    p.finish();
}

fn randFrame(r: std.Random, label: bool) RectF {
    const minw: u32 = if (label) 44 else 6;
    const minh: u32 = if (label) 22 else 6;
    const halves = [_]f32{ 0, 0.5, 0.25 };
    return .{
        .x = @as(f32, @floatFromInt(r.intRangeAtMost(i32, -20, 160))) + halves[r.uintLessThan(usize, 3)],
        .y = @as(f32, @floatFromInt(r.intRangeAtMost(i32, -20, 100))) + halves[r.uintLessThan(usize, 3)],
        .w = @floatFromInt(r.intRangeAtMost(u32, minw, 90)),
        .h = @floatFromInt(r.intRangeAtMost(u32, minh, 60)),
    };
}

/// 레이어 `l`이 `anc`의 자손인가(또는 같은가).
fn within(l: *ca.Layer, anc: *ca.Layer) bool {
    var x: ?*ca.Layer = l;
    while (x) |y| : (x = y.parent) if (y == anc) return true;
    return false;
}

fn mutate(r: std.Random, t: *ca.Tree, layers: []*ca.Layer, labels: []bool) !void {
    const i = r.uintLessThan(usize, layers.len);
    const l = layers[i];
    switch (r.uintLessThan(u32, 8)) {
        0, 1 => l.setFrame(randFrame(r, labels[i])),
        2 => l.setOpacity(([_]f32{ 0, 0.5, 1, 1, 0.75 })[r.uintLessThan(usize, 5)]),
        3 => l.setBackground(if (r.uintLessThan(u32, 4) == 0) null else COLORS[r.uintLessThan(usize, COLORS.len)]),
        4 => l.setRadius(@floatFromInt(r.uintLessThan(u32, 4) * 4)),
        5 => l.setHidden(r.boolean()),
        6 => l.setMasks(r.boolean()),
        else => {
            // 다른 부모로 옮긴다(루트 포함, 자기 자손은 빼고).
            const np = if (r.uintLessThan(u32, 3) == 0) t.root.? else layers[r.uintLessThan(usize, layers.len)];
            if (within(np, l)) return;
            if (l.parent) |op| op.removeChild(l);
            try np.addChild(l);
        },
    }
}

fn randomTrees(io: std.Io, alloc: std.mem.Allocator, face: *text.Face, lut: *const [256]u8) !void {
    const part = try alloc.alloc(u32, W * H);
    defer alloc.free(part);
    const ref = try alloc.alloc(u32, W * H);
    defer alloc.free(ref);
    const scratch = try alloc.alloc(u32, W * H);
    defer alloc.free(scratch);
    var bufs: [2][]u32 = undefined;
    for (&bufs) |*b| b.* = try alloc.alloc(u32, W * H);
    defer for (bufs) |b| alloc.free(b);

    var labels_store: [N_LAYERS]Label = undefined;
    const strs = [_][]const u8{ "가a1", "한글", "Ok", "뷁!" };

    var seed: u64 = 1;
    var partial_frames: u32 = 0;
    var partial_mismatch: u32 = 0;
    var age_frames: u32 = 0;
    var age_mismatch: u32 = 0;
    var age_partial: u32 = 0;
    var age_whole_fallback: u32 = 0;
    var masked_seen: u32 = 0;
    while (seed <= 6) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        const r = prng.random();
        var t = ca.Tree.init(alloc);
        defer t.deinit();
        const root = try t.create(.{ .frame = .{ .x = 0, .y = 0, .w = W, .h = H }, .background = theme.TK_BG });
        t.setRoot(root);
        var layers: [N_LAYERS]*ca.Layer = undefined;
        var labels: [N_LAYERS]bool = undefined;
        for (&layers, 0..) |*l, i| {
            labels[i] = i % 3 == 0;
            labels_store[i] = .{ .face = face, .str = strs[i % strs.len] };
            l.* = try t.create(.{
                .frame = randFrame(r, labels[i]),
                .background = COLORS[i % COLORS.len],
                .radius = @floatFromInt((i % 4) * 4),
                .opacity = if (i % 5 == 4) 0.5 else 1,
                .masks = i % 6 == 5,
                .content = if (labels[i]) .{ .ctx = &labels_store[i], .draw = Label.draw } else null,
            });
            const parent = if (i < 3 or r.boolean()) root else layers[r.uintLessThan(usize, i)];
            try parent.addChild(l.*);
        }

        // 3: 판 하나 — 처음 통째, 그 뒤 더티만.
        try render(io, alloc, &t, part, scratch, WHOLE, lut);
        // 4: 버퍼 둘 — 처음은 새 버퍼(통째).
        var age: Age = .{};
        var drawn: [2]?u64 = .{ null, null };
        for (bufs) |b| @memset(b, 0xFFFF00FF); // 새 버퍼는 쓰레기라고 본다 — 통째가 덮어야 한다.
        var next: usize = 0;
        var age_pending: ?Rect = WHOLE;
        _ = t.takeDirty();

        var step: u32 = 0;
        while (step < 60) : (step += 1) {
            try mutate(r, &t, &layers, &labels);
            const dirty = t.takeDirty();
            for (layers) |l| {
                if (l.masks and l.parent != null) masked_seen += 1;
            }
            try render(io, alloc, &t, ref, scratch, WHOLE, lut);
            if (dirty) |dr| {
                const clip = Rect.intersect(dr, WHOLE);
                if (clip) |cl| {
                    try render(io, alloc, &t, part, scratch, cl, lut);
                    partial_frames += 1;
                }
            }
            if (!std.mem.eql(u32, part, ref)) partial_mismatch += 1;

            // 버퍼 나이: 이 바퀴의 더티를 쌓아 두었다가 그린다(창 층의 pending과 같다).
            age_pending = Rect.coverOpt(age_pending, if (dirty) |dr| Rect.intersect(dr, WHOLE) else null);
            // 가끔 이번 바퀴는 안 그린다(프레임을 기다림). 가끔 같은 버퍼를 다시(release가 먼저 옴). 가끔 한 버퍼가 오래 쉰다.
            if (r.uintLessThan(u32, 5) == 0) continue;
            const pend = age_pending orelse continue;
            var bi = next;
            if (r.uintLessThan(u32, 7) == 0) bi = 1 - next; // 같은 버퍼를 한 번 더
            if (step >= 20 and step < 32) bi = 0; // 버퍼 1이 열두 바퀴 쉰다 → HISTORY를 넘으면 통째
            const clip = age.repaint(drawn[bi], pend, WHOLE);
            if (Rect.eql(clip, WHOLE)) {
                if (drawn[bi] != null) age_whole_fallback += 1;
            } else age_partial += 1;
            try render(io, alloc, &t, bufs[bi], scratch, clip, lut);
            drawn[bi] = age.record(pend);
            age_pending = null;
            next = 1 - bi;
            age_frames += 1;
            if (!std.mem.eql(u32, bufs[bi], ref)) age_mismatch += 1;
        }
    }
    check(partial_mismatch == 0 and partial_frames > 200, "partial = whole: {d} partial redraws over 6 random trees, {d} mismatch(es)", .{ partial_frames, partial_mismatch });
    check(masked_seen > 0, "the random trees had masking layers ({d} layer-steps)", .{masked_seen});
    check(age_mismatch == 0 and age_partial > 100 and age_whole_fallback > 0, "buffer age: {d} frames on 2 buffers ({d} partial, {d} whole by age), each = a whole redraw, {d} mismatch(es)", .{ age_frames, age_partial, age_whole_fallback, age_mismatch });
}
