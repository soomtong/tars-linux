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
//! 5 애니메이션 — 지어낸 시각으로 tick: 값 · 이징 · 끝 · 프레임 수 · 더티 · 알림, 목록이 비면 아무것도 안 함(TK-M1 단계 B).
//! 6 스택 — 세로 · 가로, 간격 · 여백 · 정렬 · 고정/신축의 프레임 표.
//! 7 토큰 — 앱 색과 셸 색이 겹치지 않는다(comptime).
//! 8 입력 · 키 반복 — evdev 표 · 수정키 비트, 반복 상태 기계를 지어낸 시각으로(TK-M2 단계 A).
//! 9 hit-test — 겹침(뒤 자식이 위) · 넘친 자식 · masks · hidden · 불투명도 0 · 경계.
//! 10 kit — responder chain(받음 · 부모로 · unhandled), Tab · Shift+Tab 순환(숨은 뷰 건너뜀), 클릭 포커스 · 휠 라우팅 · 창 포커스.
//! 11 리스트(TK-M2 단계 B) — 행 수 100 · 10만 · 1,000만에서 같은 조작열의 선택 · 오프셋 · 더티 표가 같다, 세는 데이터 소스(통째 ≤ 보이는 행 + 1,
//!    선택 이동은 0번, 부분은 clip과 겹치는 행만), 부분 = 통째 바이트 비교(무작위 조작, 리스트 둘), 끝 경계, 강조 애니메이션 · 색 · 휠 · 클릭.
//! 12 List의 데이터 바뀜 · column view(TK-M3 단계 A) — `reload` · `restore` · `reset`, 가짜 디렉터리 트리로 `→ → ←`의 열 수 · 포커스 · 스크롤 ·
//!    화면 색, 파일에서 `→`, 첫 열의 `←`, 선택 바뀜이 오른쪽 열을 버림, 클릭 포커스, Tab이 column view를 한 자리로, 버린 first responder,
//!    풀(300바퀴에 레이어 수 그대로), 깊이 32의 거절, 부분 = 통째(가로 스크롤 포함), 이미 열린 오른쪽 열로의 `→`(단계 B).
//! 13 분할 뷰 — 폭 616 · 1240 · 201 · 100의 배치 표와 알림.
//! 14 `tars-files` 모델(TK-M3 단계 B) — 자연 순서 · 디렉터리 먼저, 조각 크기 1 · 7 · 전부의 같은 결과 · 숨김 빠짐, 취소 뒤 새로 읽기, 10만 항목
//!    조각 병합 = 한 번 정렬, 안정 선택 표 · 스크롤, 첫 로딩의 선택(확정 10).
//! 15 텍스트 놓기(TK-M4 단계 A) — 클러스터(잘못된 바이트 · 결합 표시 · L V T · 홀로 선 자모 · 4바이트), 대체의 폭이 측정 = 그리기, 캐럿 x 왕복,
//!    부분 폭 = 따로 잰 폭, 실제 글꼴에서 `measure` = 끝 펜 · NFD = NFC의 픽셀, 가운데 생략, 줄 나누기, 글자 키 표 = 서버 키맵, 긴 이름 행의 부분 = 통째.
//! 16 텍스트 필드 · text-input · 클립보드 · 경로(TK-M4 단계 B) — 필드 모델 표(입력 · 클러스터 · 낱말 · 선택 · 되돌리기 맞바꿈 · 붙여넣기 첫 줄 · IME 적용 ·
//!    포커스 잃음 · 4096 한도 · 스크롤), ime 상태 기계(enter 전후 · leave · serial 불일치 · 100번 왕복), mime 고르기, 경로 해석 · 열 경로, 필드 뷰(키 표로
//!    타이핑 · Cmd+A/C/X/V/Z · Ctrl+A/E · Enter · Esc · unhandled · IME 라우팅 · ime 훅), 필드 그림(밑줄 행 · 확정 뒤 · 캐럿 · 링 · 선택 · 부분 = 통째),
//!    `ColumnView.setColumns`.
//! 17 필터 · 검색(TK-M4 단계 C) — 걷기(너비 우선 · 숨김 · 링크 · 뿌리 `/`의 제외 · 20만 · 주입한 시계의 10초), 점수 순서(연속 · 이름 · 짧은 경로 · 성분 처음 · 한글),
//!    판정 25의 결과 순서, 걷는 중 질의 늘이기 = 처음부터, 상위 100 = 전체 정렬의 앞 100, 줄인 질의, 필터의 일치 · 안정 선택 · 갱신 뒤 유지.

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
const Repeat = @import("window/repeat.zig").Repeat;
const input = @import("tk_input");
const kit = @import("tk_kit");

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

    try animations(alloc);
    try stacks(alloc);
    tokenColours();
    inputAndRepeat();
    try hitTests(alloc);
    try kitTests(alloc);
    try listTests(io, alloc, &f13, &lut1);
    try columnTests(io, alloc, &f13, &lut1);
    try modelTests(alloc);
    try layoutTests(io, alloc, &f13, &lut1);
    keyCharTests();
    fieldModelTests();
    imeTests();
    clipTests();
    pathTests();
    try fieldTests(io, alloc, font, &f13, &lut1);
    try setColumnsTests(alloc, &f13);
    try searchTests(alloc);
    try filterTests(alloc);

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

// ── 5 애니메이션 ──────────────────────────────────────────────────────

const Events = struct {
    starts: u32 = 0,
    ends: u32 = 0,
    last_frames: u32 = 0,
    last_ms: u64 = 0,

    fn on(ctx: *anyopaque, ev: ca.anim.Event) void {
        const self: *Events = @ptrCast(@alignCast(ctx));
        switch (ev) {
            .start => self.starts += 1,
            .end => |e| {
                self.ends += 1;
                self.last_frames = e.frames;
                self.last_ms = e.ms;
            },
        }
    }
};

fn near(a: f32, b: f32) bool {
    return @abs(a - b) < 1e-4;
}

fn animations(alloc: std.mem.Allocator) !void {
    const ms = std.time.ns_per_ms;
    var t = ca.Tree.init(alloc);
    defer t.deinit();
    var evs: Events = .{};
    t.hook = .{ .ctx = &evs, .on = Events.on };
    const root = try t.create(.{ .frame = .{ .x = 0, .y = 0, .w = W, .h = H }, .background = theme.TK_BG });
    const face = try t.create(.{ .frame = .{ .x = 20, .y = 30, .w = 64, .h = 32 }, .background = theme.TK_TEXT, .opacity = 0 });
    try root.addChild(face);
    t.setRoot(root);
    _ = t.takeDirty();

    t.tick(5 * ms);
    check(!t.animating() and t.takeDirty() == null and evs.starts == 0, "no animation: tick does nothing (no dirty — idle commit 0)", .{});

    try t.animate(face, .{ .opacity = 1 }, 100, .linear);
    check(t.takeDirty() == null, "animate() itself dirties nothing — the first tick starts it", .{});
    const t0: u64 = 1000 * ms;
    t.tick(t0);
    const d0 = t.takeDirty();
    check(near(face.opacity, 0) and evs.starts == 1 and d0 != null and Rect.eql(d0.?, .{ .x = 20, .y = 30, .w = 64, .h = 32 }), "first tick: start event, value = from (0), the layer is dirty anyway", .{});
    t.tick(t0 + 50 * ms);
    check(near(face.opacity, 0.5), "linear at 50/100 ms: opacity {d:.3}", .{face.opacity});
    t.tick(t0 + 99 * ms);
    check(near(face.opacity, 0.99) and t.animating(), "linear at 99 ms: {d:.3}, still running", .{face.opacity});
    t.tick(t0 + 130 * ms);
    check(face.opacity == 1 and !t.animating() and evs.ends == 1 and evs.last_frames == 4 and evs.last_ms == 130, "past the end: exactly 1, removed, end event frames={d} ms={d}", .{ evs.last_frames, evs.last_ms });
    _ = t.takeDirty();
    t.tick(t0 + 200 * ms);
    check(t.takeDirty() == null, "after the end no tick dirties anything", .{});

    // 이징 · 다른 속성.
    check(near(ca.Easing.ease_out_cubic.apply(0.5), 0.875) and near(ca.Easing.ease_out_cubic.apply(0), 0) and near(ca.Easing.ease_out_cubic.apply(1), 1), "easeOutCubic: 0 -> 0, 0.5 -> 0.875, 1 -> 1", .{});
    try t.animate(face, .{ .frame = .{ .x = 120, .y = 30, .w = 64, .h = 32 } }, 200, .ease_out_cubic);
    try t.animate(face, .{ .background = 0x000000 }, 200, .linear);
    t.tick(0);
    _ = t.takeDirty();
    t.tick(100 * ms);
    const d1 = t.takeDirty();
    // x: 20 + 100 × 0.875 = 107.5 → 화면 107..172. 더티는 옛(20..84) 덮기 새.
    check(near(face.frame.x, 107.5) and d1 != null and Rect.eql(d1.?, .{ .x = 20, .y = 30, .w = 152, .h = 32 }), "frame with easeOutCubic at half time: x {d:.2}, dirty = old cover new", .{face.frame.x});
    // F4F6F8 → 000000의 반: 7A7B7C(반올림).
    check(face.background.? == 0x7A7B7C, "background colour halfway: {x:0>6}", .{face.background.?});
    t.tick(250 * ms);
    check(!t.animating() and face.frame.x == 120 and face.background.? == 0, "both end on their exact targets", .{});
    // 같은 레이어 · 같은 속성을 다시 걸면 바꿔 단다.
    try t.animate(face, .{ .opacity = 0 }, 100, .linear);
    try t.animate(face, .{ .opacity = 1 }, 100, .linear);
    check(t.anims.items.len == 1, "re-animating the same property replaces the running animation", .{});
}

// ── 6 스택 ───────────────────────────────────────────────────────────

fn frameIs(l: *const ca.Layer, x: f32, y: f32, w: f32, h: f32) bool {
    return l.frame.x == x and l.frame.y == y and l.frame.w == w and l.frame.h == h;
}

fn stacks(alloc: std.mem.Allocator) !void {
    var t = ca.Tree.init(alloc);
    defer t.deinit();
    var ls: [4]*ca.Layer = undefined;
    for (&ls) |*l| l.* = try t.create(.{});

    // 세로: 고정 40 · 신축 1 · 고정 24, 간격 8, 여백 16, fill — 616 × 752.
    const v: ca.Stack = .{ .axis = .vertical, .spacing = 8, .padding = ca.stack.Insets.all(16), .alignment = .fill, .items = &.{
        .{ .layer = ls[0], .size = 40 },
        .{ .layer = ls[1], .flex = 1 },
        .{ .layer = ls[2], .size = 24 },
    } };
    v.layout(.{ .x = 0, .y = 0, .w = 616, .h = 752 });
    check(frameIs(ls[0], 16, 16, 584, 40) and frameIs(ls[1], 16, 64, 584, 640) and frameIs(ls[2], 16, 712, 584, 24), "vertical 40 / flex / 24, spacing 8, padding 16: y 16 · 64 · 712, flex height 640", .{});

    // 가로 가운데: 고정 셋, 교차 크기 각각, 남는 공간은 그대로(신축 없음).
    const h: ca.Stack = .{ .axis = .horizontal, .spacing = 10, .padding = .{ .left = 5, .top = 4, .bottom = 4 }, .alignment = .center, .items = &.{
        .{ .layer = ls[0], .size = 30, .cross = 20 },
        .{ .layer = ls[1], .size = 50, .cross = 41 },
        .{ .layer = ls[2], .size = 20 },
    } };
    h.layout(.{ .x = 100, .y = 0, .w = 400, .h = 100 });
    check(frameIs(ls[0], 105, 40, 30, 20) and frameIs(ls[1], 145, 29, 50, 41) and frameIs(ls[2], 205, 4, 20, 92), "horizontal centre: x 105 · 145 · 205, cross 20 at y 40, 41 at y 29 (4 + floor(51/2)), none = fill 92", .{});

    // 신축 셋이 100을 나눈다 — 정수 경계, 마지막이 끝에 맞음.
    const f: ca.Stack = .{ .axis = .horizontal, .alignment = .start, .items = &.{
        .{ .layer = ls[0], .flex = 1, .cross = 10 },
        .{ .layer = ls[1], .flex = 1, .cross = 10 },
        .{ .layer = ls[2], .flex = 1, .cross = 10 },
    } };
    f.layout(.{ .x = 0, .y = 0, .w = 100, .h = 10 });
    const sum = ls[0].frame.w + ls[1].frame.w + ls[2].frame.w;
    check(sum == 100 and ls[1].frame.x == ls[0].frame.x + ls[0].frame.w and ls[2].frame.x + ls[2].frame.w == 100, "three flex children split 100 into integers {d} {d} {d} with no gap", .{ ls[0].frame.w, ls[1].frame.w, ls[2].frame.w });

    // 넘침: 남은 공간이 음수면 신축은 0, 고정은 그대로.
    const o: ca.Stack = .{ .axis = .vertical, .spacing = 4, .items = &.{
        .{ .layer = ls[0], .size = 60 },
        .{ .layer = ls[1], .flex = 2 },
        .{ .layer = ls[3], .size = 60 },
    } };
    o.layout(.{ .x = 0, .y = 0, .w = 50, .h = 100 });
    check(ls[1].frame.h == 0 and ls[3].frame.y == 68 and ls[3].frame.h == 60, "overflow: flex child gets 0, fixed ones keep their size (last at y 68)", .{});

    // 데모의 배치(demo.zig 머리 주석의 숫자) — 616 폭.
    const rw: f32 = 320;
    const d: ca.Stack = .{ .axis = .vertical, .spacing = 16, .padding = .{ .top = 24 }, .alignment = .center, .items = &.{
        .{ .layer = ls[0], .size = 96, .cross = rw },
        .{ .layer = ls[1], .size = 156, .cross = 616 },
        .{ .layer = ls[2], .size = 32, .cross = 64 },
    } };
    d.layout(.{ .x = 0, .y = 0, .w = 616, .h = 752 });
    check(frameIs(ls[0], 148, 24, 320, 96) and frameIs(ls[1], 0, 136, 616, 156) and frameIs(ls[2], 276, 308, 64, 32), "the demo's stack at 616: rect 148,24 · samples 0,136 · face 276,308", .{});
}

// ── 7 토큰 ───────────────────────────────────────────────────────────

fn isSizeName(comptime name: []const u8) bool {
    for ([_][]const u8{ "TK_RADIUS", "TK_SPACE", "TK_PADDING", "TK_FONT", "TK_ROW", "TK_COLUMN", "TK_PREVIEW" }) |p| {
        if (std.mem.startsWith(u8, name, p)) return true;
    }
    return false;
}

fn tokenColours() void {
    const decls = @typeInfo(theme).@"struct".decl_names;
    comptime var app: u32 = 0;
    comptime var shell: u32 = 0;
    comptime {
        @setEvalBranchQuota(20000);
        for (decls) |a| {
            if (!std.mem.startsWith(u8, a, "TK_") or isSizeName(a)) continue;
            app += 1;
            for (decls) |b| {
                if (std.mem.startsWith(u8, b, "TK_")) continue;
                if (@field(theme, a) == @field(theme, b))
                    @compileError("theme: app colour " ++ a ++ " equals shell colour " ++ b);
            }
        }
        for (decls) |b| {
            if (!std.mem.startsWith(u8, b, "TK_")) shell += 1;
        }
    }
    comptime {
        for (decls) |a| {
            if (!std.mem.startsWith(u8, a, "TK_") or isSizeName(a) or std.mem.eql(u8, a, "TK_SELECTION_INACTIVE")) continue;
            if (@field(theme, a) == theme.TK_SELECTION_INACTIVE) @compileError("theme: TK_SELECTION_INACTIVE equals app colour " ++ a);
        }
    }
    check(app == 8 and shell >= 18, "tokens: {d} app colours share no value with {d} shell colours (comptime)", .{ app, shell });
}

// ── 8 입력 · 키 반복 ────────────────────────────────────────────────

fn inputAndRepeat() void {
    check(input.keyFromCode(108) == .down and input.keyFromCode(15) == .tab and input.keyFromCode(107) == .end and input.keyFromCode(30) == .other, "evdev table: 108 down, 15 tab, 107 end, 30 other", .{});
    const m = input.modsFromMask(0x41, 0x2);
    check(m.shift and m.super and m.caps and !m.ctrl and !m.alt, "mask 0x41 locked 0x2 -> shift super caps", .{});
    check(input.repeats(input.KEY_DOWN) and input.repeats(30) and !input.repeats(input.KEY_TAB) and !input.repeats(input.KEY_LEFTSHIFT) and !input.repeats(input.KEY_ENTER), "repeating keys: arrows and letters, not Tab Enter modifiers", .{});

    const ms = std.time.ns_per_ms;
    const t0: u64 = 1_000 * ms;
    var r: Repeat = .{};
    r.press(108, true, t0);
    check(r.deadline() == null, "no repeat before repeat_info (rate 0)", .{});
    r.setInfo(30, 250);
    r.press(108, true, t0);
    check(r.deadline().? == t0 + 250 * ms and r.fire(t0 + 249 * ms) == null, "first repeat after the 250 ms delay, not before", .{});
    const f1 = r.fire(t0 + 250 * ms);
    check(f1 == 108 and r.fire(t0 + 283 * ms) == null and r.fire(t0 + 284 * ms) == 108, "then every 1/30 s (33.3 ms)", .{});
    // 늦게 깬 타이머: 1초 늦어도 하나만, 다음은 그때부터 한 간격 뒤.
    const late = t0 + 1_300 * ms;
    const one = r.fire(late);
    const again = r.fire(late);
    check(one == 108 and again == null and r.deadline().? == late + std.time.ns_per_s / 30, "a late timer gives one repeat, not a burst; the next is one interval later", .{});
    r.release(30);
    check(r.deadline() != null, "releasing another key keeps the repeat", .{});
    r.release(108);
    check(r.deadline() == null and r.fire(late + 100 * ms) == null, "releasing the key stops it", .{});
    r.press(108, true, t0);
    r.press(30, true, t0 + 10 * ms);
    check(r.code == 30 and r.deadline().? == t0 + 260 * ms, "another key's press takes over the repeat", .{});
    r.press(input.KEY_TAB, false, t0 + 20 * ms);
    check(r.deadline() == null, "a non-repeating key's press stops the repeat", .{});
    r.press(108, true, t0);
    r.stop();
    check(r.deadline() == null, "keyboard leave stops the repeat", .{});
    r.press(108, true, t0);
    r.setInfo(0, 250);
    check(r.deadline() == null, "rate 0 turns repeat off", .{});

    // 1초 누르고 있기(타이머가 제때 깬다): 1 + floor((1000 − 250) / 33.3) = 23.
    r.setInfo(30, 250);
    r.press(108, true, 0);
    var n: u32 = 0;
    while (r.deadline()) |d| {
        if (d >= 1_000 * ms) break;
        if (r.fire(d) != null) n += 1;
    }
    check(n == 23, "held for 1 s at 30/s after 250 ms: {d} repeats (want 23)", .{n});
}

// ── 9 hit-test ──────────────────────────────────────────────────────

fn hitTests(alloc: std.mem.Allocator) !void {
    var t = ca.Tree.init(alloc);
    defer t.deinit();
    const root = try t.create(.{ .frame = .{ .x = 0, .y = 0, .w = 200, .h = 120 } });
    const a = try t.create(.{ .frame = .{ .x = 10, .y = 10, .w = 100, .h = 60 } });
    const a1 = try t.create(.{ .frame = .{ .x = 20, .y = 20, .w = 30, .h = 20 } });
    const ao = try t.create(.{ .frame = .{ .x = -5, .y = -5, .w = 10, .h = 10 } }); // a 밖으로 넘친 자식
    const b = try t.create(.{ .frame = .{ .x = 60, .y = 40, .w = 100, .h = 60 } }); // a 위에 겹친다(뒤에 붙음)
    const hid = try t.create(.{ .frame = .{ .x = 0, .y = 100, .w = 50, .h = 20 }, .hidden = true });
    const zero = try t.create(.{ .frame = .{ .x = 100, .y = 100, .w = 50, .h = 20 }, .opacity = 0 });
    const m = try t.create(.{ .frame = .{ .x = 160, .y = 0, .w = 30, .h = 40 }, .masks = true });
    const mc = try t.create(.{ .frame = .{ .x = 20, .y = 30, .w = 40, .h = 40 } }); // 화면 (180,30)..(220,70), m이 y 40까지 자른다
    try root.addChild(a);
    try a.addChild(a1);
    try a.addChild(ao);
    try root.addChild(b);
    try root.addChild(hid);
    try root.addChild(zero);
    try root.addChild(m);
    try m.addChild(mc);
    t.setRoot(root);

    check(t.hitTest(35, 35) == a1, "hit (35,35) is the grandchild a1", .{});
    check(t.hitTest(15, 15) == a, "hit (15,15) is a", .{});
    check(t.hitTest(70, 50) == b, "hit (70,50) where a and b overlap is b (added later, drawn on top)", .{});
    check(t.hitTest(7, 7) == ao, "hit (7,7) is a's child overflowing a (a does not mask)", .{});
    check(t.hitTest(5, 110) == root, "a hidden layer is not hit (root)", .{});
    check(t.hitTest(120, 110) == root, "an opacity-0 layer is not hit (root under it)", .{});
    check(t.hitTest(185, 35) == mc, "inside a masking layer its child is hit", .{});
    check(t.hitTest(185, 50) == root, "a child clipped away by masks is not hit", .{});
    check(t.hitTest(200, 60) == null and t.hitTest(-1, 5) == null, "outside the root: nothing (right edge excluded)", .{});
    check(t.hitTest(16, 10) == a and t.hitTest(110, 30) == root, "left/top edges included, right edge excluded", .{});
    b.setFrame(.{ .x = 60, .y = 80, .w = 100, .h = 30 });
    check(t.hitTest(70, 50) == a, "after b moves away (70,50) is a", .{});
    zero.setOpacity(1);
    check(t.hitTest(120, 110) == zero, "the layer is hit once it is visible", .{});
}

// ── 10 kit ──────────────────────────────────────────────────────────

const TV = struct {
    view: kit.View = undefined,
    accepts: bool = false,
    handles: []const input.Key = &.{},
    scrolls_ok: bool = false,
    mouse_ok: bool = false,
    keys: u32 = 0,
    scrolls: u32 = 0,
    mouses: u32 = 0,
    lx: f32 = 0,
    ly: f32 = 0,
    focus_on: u32 = 0,
    focus_off: u32 = 0,
    wfocus: ?bool = null,

    const vt: kit.VTable = .{
        .keyDown = keyDown,
        .scroll = scroll,
        .mouseDown = mouseDown,
        .acceptsFocus = acceptsFocus,
        .focusChanged = focusChanged,
        .windowFocusChanged = windowFocusChanged,
    };

    fn init(self: *TV, layer: *ca.Layer, name: []const u8) void {
        self.view = .{ .layer = layer, .vtable = &vt, .ctx = self, .name = name };
    }
    fn me(ctx: *anyopaque) *TV {
        return @ptrCast(@alignCast(ctx));
    }
    fn keyDown(ctx: *anyopaque, ev: input.KeyEvent) bool {
        const self = me(ctx);
        for (self.handles) |k| if (k == ev.key) {
            self.keys += 1;
            return true;
        };
        return false;
    }
    fn scroll(ctx: *anyopaque, ev: input.ScrollEvent) bool {
        _ = ev;
        const self = me(ctx);
        if (!self.scrolls_ok) return false;
        self.scrolls += 1;
        return true;
    }
    fn mouseDown(ctx: *anyopaque, ev: input.ButtonEvent, lx: f32, ly: f32) bool {
        _ = ev;
        const self = me(ctx);
        if (!self.mouse_ok) return false;
        self.mouses += 1;
        self.lx = lx;
        self.ly = ly;
        return true;
    }
    fn acceptsFocus(ctx: *anyopaque) bool {
        return me(ctx).accepts;
    }
    fn focusChanged(ctx: *anyopaque, on: bool) void {
        const self = me(ctx);
        if (on) self.focus_on += 1 else self.focus_off += 1;
    }
    fn windowFocusChanged(ctx: *anyopaque, on: bool) void {
        me(ctx).wfocus = on;
    }
};

const KitLog = struct {
    unhandled: u32 = 0,
    last_code: u32 = 0,
    last_super: bool = false,
    focus_names: [16][]const u8 = undefined,
    focus_n: usize = 0,

    fn onUnhandled(ctx: *anyopaque, ev: input.KeyEvent) void {
        const self: *KitLog = @ptrCast(@alignCast(ctx));
        self.unhandled += 1;
        self.last_code = ev.code;
        self.last_super = ev.mods.super;
    }
    fn onFocus(ctx: *anyopaque, v: ?*kit.View) void {
        const self: *KitLog = @ptrCast(@alignCast(ctx));
        if (self.focus_n < self.focus_names.len) self.focus_names[self.focus_n] = if (v) |x| x.name else "-";
        self.focus_n += 1;
    }
};

fn keyEv(code: u32, mods: input.Mods) input.Event {
    return .{ .key = .{ .code = code, .key = input.keyFromCode(code), .pressed = true, .mods = mods } };
}

fn kitTests(alloc: std.mem.Allocator) !void {
    var t = ca.Tree.init(alloc);
    defer t.deinit();
    // 뷰 트리: root ─ panel ─ listA, listB(+ 장식 레이어) / hiddenV(숨김) / listC
    const lroot = try t.create(.{ .frame = .{ .x = 0, .y = 0, .w = 300, .h = 200 } });
    const lpanel = try t.create(.{ .frame = .{ .x = 0, .y = 0, .w = 200, .h = 200 } });
    const la = try t.create(.{ .frame = .{ .x = 0, .y = 0, .w = 100, .h = 100 } });
    const lb = try t.create(.{ .frame = .{ .x = 100, .y = 0, .w = 100, .h = 100 } });
    const lbdeco = try t.create(.{ .frame = .{ .x = 10, .y = 10, .w = 20, .h = 20 } }); // owner 없는 레이어
    const lh = try t.create(.{ .frame = .{ .x = 0, .y = 100, .w = 100, .h = 100 }, .hidden = true });
    const lc = try t.create(.{ .frame = .{ .x = 200, .y = 0, .w = 100, .h = 200 } });
    try lroot.addChild(lpanel);
    try lpanel.addChild(la);
    try lpanel.addChild(lb);
    try lb.addChild(lbdeco);
    try lpanel.addChild(lh);
    try lroot.addChild(lc);
    t.setRoot(lroot);

    var vroot: TV = .{ .scrolls_ok = true, .mouse_ok = true };
    var panel: TV = .{ .handles = &.{.left} };
    var la_v: TV = .{ .accepts = true, .handles = &.{ .down, .up }, .scrolls_ok = true, .mouse_ok = true };
    var lb_v: TV = .{ .accepts = true, .handles = &.{.down}, .mouse_ok = true };
    var lh_v: TV = .{ .accepts = true };
    var lc_v: TV = .{ .accepts = true };
    vroot.init(lroot, "root");
    panel.init(lpanel, "panel");
    la_v.init(la, "listA");
    lb_v.init(lb, "listB");
    lh_v.init(lh, "hidden");
    lc_v.init(lc, "listC");
    defer inline for (.{ &vroot, &panel, &la_v, &lb_v, &lh_v, &lc_v }) |x| x.view.deinit(alloc);
    try vroot.view.addChild(alloc, &panel.view);
    try panel.view.addChild(alloc, &la_v.view);
    try panel.view.addChild(alloc, &lb_v.view);
    try panel.view.addChild(alloc, &lh_v.view);
    try vroot.view.addChild(alloc, &lc_v.view);

    var log: KitLog = .{};
    var root = kit.Root.init(&t);
    root.setView(&vroot.view);
    root.hook = .{ .ctx = &log, .on = KitLog.onFocus };
    root.unhandled = .{ .ctx = &log, .on = KitLog.onUnhandled };

    // Tab 순환: 아무도 아님 → listA → listB → listC(숨은 것 건너뜀) → listA, Shift+Tab → listC.
    root.handle(keyEv(input.KEY_TAB, .{}));
    const s1 = root.first == &la_v.view;
    root.handle(keyEv(input.KEY_TAB, .{}));
    const s2 = root.first == &lb_v.view;
    root.handle(keyEv(input.KEY_TAB, .{}));
    const s3 = root.first == &lc_v.view;
    root.handle(keyEv(input.KEY_TAB, .{}));
    const s4 = root.first == &la_v.view;
    root.handle(keyEv(input.KEY_TAB, .{ .shift = true }));
    const s5 = root.first == &lc_v.view;
    check(s1 and s2 and s3 and s4 and s5, "Tab: none -> listA -> listB -> listC (hidden skipped) -> listA; Shift+Tab -> listC", .{});
    check(log.focus_n == 5 and std.mem.eql(u8, log.focus_names[2], "listC") and std.mem.eql(u8, log.focus_names[4], "listC"), "focus hook fired on every change ({d})", .{log.focus_n});
    check(la_v.focus_on == 2 and la_v.focus_off == 2 and lc_v.focus_on == 2 and lc_v.focus_off == 1, "focusChanged: listA on 2 off 2, listC on 2 off 1", .{});
    root.handle(keyEv(input.KEY_TAB, .{ .ctrl = true }));
    check(root.first == &lc_v.view and log.unhandled == 1, "Ctrl+Tab does not move focus (unhandled)", .{});
    root.handle(keyEv(input.KEY_TAB, .{ .shift = true }));
    check(root.first == &lb_v.view, "Shift+Tab from listC -> listB", .{});
    // 숨김을 풀면 순서에 든다.
    lh.setHidden(false);
    root.handle(keyEv(input.KEY_TAB, .{}));
    check(root.first == &lh_v.view, "an unhidden view joins the order (listB -> hidden)", .{});
    lh.setHidden(true);

    // responder chain
    _ = root.setFirstResponder(&la_v.view);
    root.handle(keyEv(input.KEY_DOWN, .{}));
    check(la_v.keys == 1 and panel.keys == 0, "down goes to the first responder listA and stops there", .{});
    root.handle(keyEv(input.KEY_LEFT, .{}));
    check(panel.keys == 1 and la_v.keys == 1, "left (not listA's) goes up to the parent panel", .{});
    const unh0 = log.unhandled;
    root.handle(keyEv(30, .{ .super = true }));
    check(log.unhandled == unh0 + 1 and log.last_code == 30 and log.last_super, "Super+A nobody takes reaches unhandled with super", .{});
    var rel = keyEv(input.KEY_DOWN, .{});
    rel.key.pressed = false;
    root.handle(rel);
    check(la_v.keys == 1 and log.unhandled == unh0 + 1, "a release goes nowhere", .{});
    check(!root.setFirstResponder(&panel.view) and root.first == &la_v.view, "a view that does not accept focus cannot become first responder", .{});
    _ = root.setFirstResponder(null);
    root.handle(keyEv(input.KEY_LEFT, .{}));
    check(panel.keys == 1 and log.unhandled == unh0 + 2, "with no first responder keys start at the root view", .{});

    // 클릭: listB의 장식 레이어(owner 없음)를 누르면 listB가 포커스, mouseDown은 listB 기준 좌표.
    root.handle(.{ .button = .{ .code = input.BTN_LEFT, .pressed = true, .x = 115, .y = 15 } });
    check(root.first == &lb_v.view and lb_v.mouses == 1 and lb_v.lx == 15 and lb_v.ly == 15, "click on listB's undecorated child focuses listB, local (15,15)", .{});
    root.handle(.{ .button = .{ .code = input.BTN_LEFT, .pressed = false, .x = 115, .y = 15 } });
    check(lb_v.mouses == 1, "the release is not a mouseDown", .{});
    root.handle(.{ .button = .{ .code = input.BTN_LEFT, .pressed = true, .x = 50, .y = 150 } });
    check(root.first == &lb_v.view and vroot.mouses == 1, "click on the panel (not focusable, no mouseDown) keeps focus; root gets the mouseDown", .{});
    root.handle(.{ .button = .{ .code = 273, .pressed = true, .x = 50, .y = 50 } });
    check(root.first == &lb_v.view and la_v.mouses == 0, "the right button does nothing", .{});

    // 휠: 포인터 아래 뷰(포커스와 무관). listA는 받고, listC는 안 받아 루트로.
    root.handle(.{ .scroll = .{ .dy = 10, .discrete = 1, .x = 50, .y = 50 } });
    check(la_v.scrolls == 1 and root.first == &lb_v.view, "wheel over listA goes to listA while listB has focus", .{});
    root.handle(.{ .scroll = .{ .dy = 10, .discrete = 1, .x = 250, .y = 50 } });
    check(vroot.scrolls == 1, "wheel over listC (no scroll) goes up to the root view", .{});
    check(root.viewAt(15 + 100, 15) == &lb_v.view and root.viewAt(250, 199) == &lc_v.view, "viewAt finds the owner through undecorated layers", .{});

    // 창 포커스
    root.handle(.{ .focus = false });
    check(vroot.wfocus == false and la_v.wfocus == false and lh_v.wfocus == false and !root.window_focused, "window focus out reaches every view", .{});
    root.handle(.{ .focus = true });
    check(lc_v.wfocus == true and root.window_focused, "window focus in reaches every view", .{});
}

// ── 11 리스트 ───────────────────────────────────────────────────────

const LW: u32 = 616;
const LH: u32 = 752;
const LWHOLE: Rect = .{ .x = 0, .y = 0, .w = LW, .h = LH };

/// 행을 세며 그리는 데이터 소스(레이블은 셈으로 — 데모와 같은 꼴).
const CountSource = struct {
    n: usize,
    face: *text.Face,
    calls: usize = 0,

    fn count(ctx: *anyopaque) usize {
        const self: *CountSource = @ptrCast(@alignCast(ctx));
        return self.n;
    }
    fn drawRow(ctx: *anyopaque, p: *Painter, index: usize, rect: Rect, state: kit.RowState) anyerror!void {
        const self: *CountSource = @ptrCast(@alignCast(ctx));
        self.calls += 1;
        var buf: [48]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "문서 {d:0>6}.txt", .{index}) catch return;
        const base: i32 = rect.y + @as(i32, @intFromFloat(@round((@as(f32, @floatFromInt(rect.h)) + self.face.ascent - self.face.descent) / 2)));
        _ = try p.drawGlyphs(self.face, @as(f32, @floatFromInt(rect.x)) + 16, base, label, theme.TK_TEXT, state.alpha);
    }
    fn source(self: *CountSource) kit.ListSource {
        return .{ .ctx = self, .count = count, .drawRow = drawRow };
    }
};

const ROOT_VT: kit.VTable = .{};

/// 데모의 리스트 화면과 같은 모양: 616 × 752, list1(416) · list2(200), 루트 뷰, first responder list1, 창 포커스 있음.
const ListEnv = struct {
    tree: ca.Tree,
    root_layer: *ca.Layer = undefined,
    root_view: kit.View = undefined,
    root: kit.Root = undefined,
    srcs: [2]CountSource,
    lists: [2]kit.List = undefined,
    alloc: std.mem.Allocator,

    fn init(self: *ListEnv, alloc: std.mem.Allocator, face: *text.Face, n1: usize, n2: usize, anim_ms: u32) !void {
        self.* = .{ .tree = ca.Tree.init(alloc), .srcs = .{ .{ .n = n1, .face = face }, .{ .n = n2, .face = face } }, .alloc = alloc };
        const t = &self.tree;
        self.root_layer = try t.create(.{ .frame = .{ .x = 0, .y = 0, .w = LW, .h = LH }, .background = theme.TK_BG });
        try self.lists[0].init(t, "list1", self.srcs[0].source(), anim_ms);
        try self.lists[1].init(t, "list2", self.srcs[1].source(), anim_ms);
        try self.root_layer.addChild(self.lists[0].view.layer);
        try self.root_layer.addChild(self.lists[1].view.layer);
        t.setRoot(self.root_layer);
        const stack: ca.Stack = .{ .axis = .horizontal, .items = &.{
            .{ .layer = self.lists[0].view.layer, .flex = 1 },
            .{ .layer = self.lists[1].view.layer, .size = 200 },
        } };
        stack.layout(.{ .x = 0, .y = 0, .w = LW, .h = LH });
        self.root_view = .{ .layer = self.root_layer, .vtable = &ROOT_VT, .ctx = self, .name = "root" };
        self.root = kit.Root.init(t);
        self.root.setView(&self.root_view);
        try self.root_view.addChild(alloc, &self.lists[0].view);
        try self.root_view.addChild(alloc, &self.lists[1].view);
        for (&self.lists) |*l| l.sync();
        _ = self.root.setFirstResponder(&self.lists[0].view);
        self.root.handle(.{ .focus = true });
        _ = t.takeDirty();
    }

    fn deinit(self: *ListEnv) void {
        for (&self.lists) |*l| l.deinit(self.alloc);
        self.root_view.deinit(self.alloc);
        self.tree.deinit();
    }

    fn key(self: *ListEnv, code: u32) ?Rect {
        self.root.handle(.{ .key = .{ .code = code, .key = input.keyFromCode(code), .pressed = true } });
        return self.tree.takeDirty();
    }
};

fn lrender(io: std.Io, alloc: std.mem.Allocator, t: *ca.Tree, pixels: []u32, scratch: []u32, clip: Rect, lut: *const [256]u8) !void {
    var p = Painter.begin(io, alloc, pixels, LW, LH, scratch, clip, lut);
    _ = try t.draw(&p);
    p.finish();
}

const Step = struct { sel: usize, offset: u64, dirty: ?Rect };

fn rectEql(a: ?Rect, b: ?Rect) bool {
    if (a == null or b == null) return a == null and b == null;
    return Rect.eql(a.?, b.?);
}

fn lpx(pixels: []const u32, x: u32, y: u32) u32 {
    return pixels[y * LW + x] & 0x00FFFFFF;
}

fn listTests(io: std.Io, alloc: std.mem.Allocator, face: *text.Face, lut: *const [256]u8) !void {
    const pixels = try alloc.alloc(u32, LW * LH);
    defer alloc.free(pixels);
    const ref = try alloc.alloc(u32, LW * LH);
    defer alloc.free(ref);
    const scratch = try alloc.alloc(u32, LW * LH);
    defer alloc.free(scratch);

    // ── 행 수에 무관한 표 ──
    const ops = [_]u32{ input.KEY_DOWN, input.KEY_DOWN, input.KEY_DOWN, input.KEY_DOWN, input.KEY_DOWN, input.KEY_DOWN, input.KEY_DOWN, input.KEY_DOWN, input.KEY_DOWN, input.KEY_DOWN, input.KEY_PAGEDOWN, input.KEY_PAGEDOWN, input.KEY_UP, input.KEY_PAGEUP, input.KEY_HOME };
    var table: [3][ops.len]Step = undefined;
    const counts = [_]usize{ 100, 100_000, 10_000_000 };
    var end_ok = true;
    var calls_sel: usize = 0;
    var whole_calls: [3]usize = undefined;
    for (counts, 0..) |n, ci| {
        var env: ListEnv = undefined;
        try env.init(alloc, face, n, 50, 0);
        defer env.deinit();
        const l = &env.lists[0];
        env.srcs[0].calls = 0;
        for (ops, 0..) |code, k| {
            const d = env.key(code);
            table[ci][k] = .{ .sel = l.selected, .offset = l.offset, .dirty = d };
        }
        _ = env.key(input.KEY_END);
        const want_off = @as(u64, n) * 24 - LH;
        end_ok = end_ok and l.selected == n - 1 and l.offset == want_off and l.first() == want_off / 24 and l.visibleEnd() == n;
        calls_sel += env.srcs[0].calls;
        env.srcs[0].calls = 0;
        try lrender(io, alloc, &env.tree, pixels, scratch, LWHOLE, lut);
        whole_calls[ci] = env.srcs[0].calls;
    }
    var same = true;
    for (1..3) |ci| for (0..ops.len) |k| {
        const a = table[0][k];
        const b = table[ci][k];
        same = same and a.sel == b.sel and a.offset == b.offset and rectEql(a.dirty, b.dirty);
    };
    check(same, "100 / 100,000 / 10,000,000 rows: the same keys give the same selection, offset and dirty table ({d} steps)", .{ops.len});
    const t9 = table[0][9];
    check(t9.sel == 10 and t9.offset == 0 and rectEql(t9.dirty, .{ .x = 0, .y = 216, .w = 416, .h = 48 }), "after 10 downs: sel 10, offset 0, last dirty = rows 9 and 10 (0,216 416x48)", .{});
    const t10 = table[0][10];
    check(t10.sel == 40 and t10.offset == 40 * 24 + 24 - LH and rectEql(t10.dirty, .{ .x = 0, .y = 0, .w = 416, .h = 752 }), "PgDn moves 30 rows (31 visible - 1) and scrolls minimally: sel 40, offset {d}, dirty = the whole list", .{t10.offset});
    const t14 = table[0][14];
    check(t14.sel == 0 and t14.offset == 0, "Home: sel 0, offset 0", .{});
    check(end_ok, "End: sel n-1, offset n*24-752, first = offset/24, visible end = n (all three counts)", .{});
    check(calls_sel == 0, "moving the selection and End call drawRow 0 times ({d})", .{calls_sel});
    check(whole_calls[0] <= 33 and whole_calls[0] == whole_calls[1] and whole_calls[1] == whole_calls[2], "a whole draw calls drawRow {d} / {d} / {d} times (<= ceil(752/24)+1 = 33, independent of the row count)", .{ whole_calls[0], whole_calls[1], whole_calls[2] });

    // ── 부분 그리기의 행 수 · 색 · 휠 · 클릭 · Tab ──
    {
        var env: ListEnv = undefined;
        try env.init(alloc, face, 100_000, 50, 0);
        defer env.deinit();
        try lrender(io, alloc, &env.tree, pixels, scratch, LWHOLE, lut);
        const d = env.key(input.KEY_DOWN).?;
        env.srcs[0].calls = 0;
        env.srcs[1].calls = 0;
        try lrender(io, alloc, &env.tree, pixels, scratch, d, lut);
        check(env.srcs[0].calls == 2 and env.srcs[1].calls == 0, "a down's partial draw (0,0 416x48) calls drawRow only for the 2 rows in the clip ({d}, list2 {d})", .{ env.srcs[0].calls, env.srcs[1].calls });
        check(lpx(pixels, 400, 30) == theme.TK_SELECTION and lpx(pixels, 400, 10) == theme.TK_BG and lpx(pixels, 600, 10) == theme.TK_SELECTION_INACTIVE, "focused list1 row 1 is TK_SELECTION, row 0 the background, list2's row 0 TK_SELECTION_INACTIVE", .{});
        // Tab → list2, 강조색이 바뀐다.
        env.root.handle(.{ .key = .{ .code = input.KEY_TAB, .key = .tab, .pressed = true } });
        const dt = env.tree.takeDirty();
        try lrender(io, alloc, &env.tree, pixels, scratch, dt.?, lut);
        check(env.root.first == &env.lists[1].view and lpx(pixels, 400, 30) == theme.TK_SELECTION_INACTIVE and lpx(pixels, 600, 10) == theme.TK_SELECTION, "Tab: list2 is first responder, list1's highlight dims, list2's row 0 is TK_SELECTION", .{});
        env.root.handle(.{ .focus = false });
        _ = env.tree.takeDirty();
        check(env.lists[1].highlight.background == theme.TK_SELECTION_INACTIVE, "window focus out dims the focused list too", .{});
        env.root.handle(.{ .focus = true });
        env.root.handle(.{ .key = .{ .code = input.KEY_TAB, .key = .tab, .pressed = true, .mods = .{ .shift = true } } });
        check(env.root.first == &env.lists[0].view, "Shift+Tab back to list1", .{});
        // 휠: 포인터 아래 리스트, 칸당 3행. 선택은 그대로.
        env.root.handle(.{ .scroll = .{ .dy = 10, .discrete = 1, .x = 100, .y = 100 } });
        check(env.lists[0].offset == 72 and env.lists[0].selected == 1, "wheel one notch down over list1: offset 72, selection stays 1", .{});
        env.root.handle(.{ .scroll = .{ .dy = 10, .discrete = 1, .x = 500, .y = 100 } });
        check(env.lists[1].offset == 72 and env.lists[0].offset == 72, "wheel over list2 (50 rows = 1200 > 752) scrolls list2 only: offset {d}", .{env.lists[1].offset});
        env.root.handle(.{ .scroll = .{ .dy = -30, .discrete = -3, .x = 100, .y = 100 } });
        check(env.lists[0].offset == 0, "wheel up past the top clamps to 0", .{});
        env.root.handle(.{ .scroll = .{ .dy = 10, .discrete = 1, .x = 100, .y = 100 } });
        // 클릭: (100, 100) → 행 (72 + 100) / 24 = 7.
        env.root.handle(.{ .button = .{ .code = input.BTN_LEFT, .pressed = true, .x = 100, .y = 100 } });
        check(env.lists[0].selected == 7 and env.lists[0].offset == 72, "click at y 100 with offset 72 selects row 7", .{});
        env.root.handle(.{ .button = .{ .code = input.BTN_LEFT, .pressed = true, .x = 500, .y = 30 } });
        check(env.root.first == &env.lists[1].view and env.lists[1].selected == 4, "click on list2 at y 30 (offset 72 -> row 4) focuses list2 and selects row 4", .{});
        // Super+↓는 리스트의 것이 아니다.
        const before = env.lists[1].selected;
        env.root.handle(.{ .key = .{ .code = input.KEY_DOWN, .key = .down, .pressed = true, .mods = .{ .super = true } } });
        check(env.lists[1].selected == before, "Super+Down is not the list's", .{});
        // 막대: 10만 행이면 최소 높이 24, End면 바닥.
        _ = env.root.setFirstResponder(&env.lists[0].view);
        _ = env.key(input.KEY_END);
        const bf = env.lists[0].bar.frame;
        check(!env.lists[0].bar.hidden and bf.h == 24 and bf.y + bf.h == 752 and bf.x == 410, "the scroll bar is 6x24 at the bottom after End (x {d}, y {d})", .{ bf.x, bf.y });
        _ = env.key(input.KEY_HOME);
        check(env.lists[0].bar.frame.y == 0, "Home puts the bar at the top", .{});
    }

    // ── 강조 애니메이션 ──
    {
        var env: ListEnv = undefined;
        try env.init(alloc, face, 1000, 50, 120);
        defer env.deinit();
        _ = env.key(input.KEY_DOWN);
        const t0: u64 = 5 * std.time.ns_per_s;
        const ms = std.time.ns_per_ms;
        env.tree.tick(t0);
        env.tree.tick(t0 + 60 * ms);
        const mid = env.lists[0].highlight.frame.y;
        env.tree.tick(t0 + 130 * ms);
        check(mid > 0 and mid < 24 and env.lists[0].highlight.frame.y == 24 and !env.tree.animating(), "the highlight slides to row 1 over 120 ms (mid y {d:.1}, end 24)", .{mid});
        // 스크롤이 생기는 이동은 바로.
        _ = env.key(input.KEY_END);
        check(!env.tree.animating() and env.lists[0].highlight.frame.y == 752 - 24, "a move that scrolls places the highlight at once (no animation)", .{});
    }

    // ── 부분 = 통째(무작위 조작, 리스트 둘) ──
    {
        var env: ListEnv = undefined;
        try env.init(alloc, face, 100_000, 50, 0);
        defer env.deinit();
        try lrender(io, alloc, &env.tree, pixels, scratch, LWHOLE, lut);
        var prng = std.Random.DefaultPrng.init(0x7A11);
        const r = prng.random();
        const keys = [_]u32{ input.KEY_DOWN, input.KEY_DOWN, input.KEY_DOWN, input.KEY_UP, input.KEY_PAGEDOWN, input.KEY_PAGEUP, input.KEY_HOME, input.KEY_END, input.KEY_TAB };
        var mismatch: u32 = 0;
        var partial: u32 = 0;
        var steps: u32 = 0;
        while (steps < 300) : (steps += 1) {
            switch (r.uintLessThan(u32, 6)) {
                0, 1, 2 => {
                    const code = keys[r.uintLessThan(usize, keys.len)];
                    env.root.handle(.{ .key = .{ .code = code, .key = input.keyFromCode(code), .pressed = true, .mods = .{ .shift = r.boolean() and code == input.KEY_TAB } } });
                },
                3 => env.root.handle(.{ .scroll = .{ .dy = 0, .discrete = r.intRangeAtMost(i32, -2, 2), .x = @floatFromInt(r.uintLessThan(u32, LW)), .y = @floatFromInt(r.uintLessThan(u32, LH)) } }),
                4 => env.root.handle(.{ .button = .{ .code = input.BTN_LEFT, .pressed = true, .x = @floatFromInt(r.uintLessThan(u32, LW)), .y = @floatFromInt(r.uintLessThan(u32, LH)) } }),
                else => env.root.handle(.{ .focus = r.uintLessThan(u32, 4) != 0 }),
            }
            const d = env.tree.takeDirty() orelse continue;
            const clip = Rect.intersect(d, LWHOLE) orelse continue;
            if (!Rect.eql(clip, LWHOLE)) partial += 1;
            try lrender(io, alloc, &env.tree, pixels, scratch, clip, lut);
            try lrender(io, alloc, &env.tree, ref, scratch, LWHOLE, lut);
            if (!std.mem.eql(u32, pixels, ref)) mismatch += 1;
        }
        check(mismatch == 0 and partial > 50, "list partial = whole: 300 random steps on two lists, {d} partial redraws, {d} mismatch(es)", .{ partial, mismatch });
    }

    // ── 끝 경계 ──
    {
        var env: ListEnv = undefined;
        try env.init(alloc, face, 0, 1, 0);
        defer env.deinit();
        const d0 = env.key(input.KEY_DOWN);
        const d1 = env.key(input.KEY_END);
        env.srcs[0].calls = 0;
        try lrender(io, alloc, &env.tree, pixels, scratch, LWHOLE, lut);
        check(d0 == null and d1 == null and env.srcs[0].calls == 0 and env.lists[0].highlight.hidden and env.lists[0].bar.hidden, "0 rows: keys change nothing, nothing drawn, no highlight, no bar", .{});
        env.root.handle(.{ .button = .{ .code = input.BTN_LEFT, .pressed = true, .x = 100, .y = 100 } });
        check(env.lists[0].selected == 0 and env.tree.takeDirty() == null, "0 rows: a click selects nothing", .{});
        _ = env.root.setFirstResponder(&env.lists[1].view);
        _ = env.tree.takeDirty();
        const u = env.key(input.KEY_UP);
        const dn = env.key(input.KEY_DOWN);
        check(u == null and dn == null and env.lists[1].selected == 0 and env.lists[1].bar.hidden, "1 row: up and down make no dirty, no bar", .{});
    }
    {
        var env: ListEnv = undefined;
        try env.init(alloc, face, 5, 50, 0);
        defer env.deinit();
        const top = env.key(input.KEY_UP);
        _ = env.key(input.KEY_END);
        const sel_end = env.lists[0].selected;
        const off = env.lists[0].offset;
        const bottom = env.key(input.KEY_DOWN);
        check(top == null and bottom == null and sel_end == 4 and off == 0 and env.lists[0].bar.hidden, "5 rows (shorter than the view): up at the top and down at the bottom make no dirty, End = row 4, offset 0, no bar", .{});
        const pd = env.key(input.KEY_PAGEUP);
        check(env.lists[0].selected == 0 and pd != null, "PgUp from row 4 goes to row 0", .{});
    }
}

// ── 12 List의 데이터 바뀜 · column view · 13 분할 뷰(TK-M3 단계 A) ─────────────────

/// 가짜 디렉터리 트리 — 이름과 자식(디렉터리면 `kids`가 null이 아님). kit은 파일을 모르므로 column view의 검사는 이것만 꽂는다.
const FNode = struct {
    name: []const u8,
    kids: ?[]const FNode = null,
};

const TREE_B = [_]FNode{ .{ .name = "c", .kids = &.{} }, .{ .name = "x.txt" } };
const TREE_A = [_]FNode{.{ .name = "b", .kids = &TREE_B }};
const TREE_TOP = [_]FNode{ .{ .name = "a", .kids = &TREE_A }, .{ .name = "z", .kids = &.{} }, .{ .name = "m.txt" } };

/// 열 하나의 데이터(가짜 디렉터리 하나).
const FCol = struct {
    kids: []const FNode = &.{},
    face: *text.Face = undefined,
    calls: usize = 0,
    /// `deep`이면 행은 늘 열린다(깊이 검사).
    deep: bool = false,

    fn count(ctx: *anyopaque) usize {
        const self: *FCol = @ptrCast(@alignCast(ctx));
        return if (self.deep) 3 else self.kids.len;
    }
    fn drawRow(ctx: *anyopaque, p: *Painter, index: usize, rect: Rect, state: kit.RowState) anyerror!void {
        const self: *FCol = @ptrCast(@alignCast(ctx));
        self.calls += 1;
        const name = if (self.deep) "d" else self.kids[index].name;
        const base: i32 = rect.y + @as(i32, @intFromFloat(@round((@as(f32, @floatFromInt(rect.h)) + self.face.ascent - self.face.descent) / 2)));
        _ = try p.drawGlyphs(self.face, @as(f32, @floatFromInt(rect.x)) + 16, base, name, theme.TK_TEXT, state.alpha);
    }
    fn source(self: *FCol) kit.ListSource {
        return .{ .ctx = self, .count = count, .drawRow = drawRow };
    }
};

/// 가짜 ColumnSource — 열마다 FCol 하나(열 i = 깊이 i).
const FSrc = struct {
    cols: [kit.column.MAX_COLUMNS]FCol = @splat(.{}),
    opens: u32 = 0,
    truncs: u32 = 0,
    last_trunc: usize = 0,

    fn open(ctx: *anyopaque, column: usize, row: usize) ?kit.ListSource {
        const self: *FSrc = @ptrCast(@alignCast(ctx));
        self.opens += 1;
        const c = &self.cols[column];
        const nc = &self.cols[column + 1];
        nc.face = c.face;
        if (c.deep) {
            nc.deep = true;
            return nc.source();
        }
        const kids = c.kids[row].kids orelse return null;
        nc.* = .{ .kids = kids, .face = c.face };
        return nc.source();
    }
    fn truncated(ctx: *anyopaque, n: usize) void {
        const self: *FSrc = @ptrCast(@alignCast(ctx));
        self.truncs += 1;
        self.last_trunc = n;
    }
    fn source(self: *FSrc) kit.ColumnSource {
        return .{ .ctx = self, .open = open, .truncated = truncated };
    }
};

const ColLog = struct {
    columns: u32 = 0,
    selects: u32 = 0,
    last: kit.ColumnEvent = undefined,

    fn on(ctx: *anyopaque, _: *kit.ColumnView, ev: kit.ColumnEvent) void {
        const self: *ColLog = @ptrCast(@alignCast(ctx));
        switch (ev) {
            .columns => self.columns += 1,
            .select => self.selects += 1,
        }
        self.last = ev;
    }
};

/// `tars-files`의 모양: 616 × 752 루트 → 분할 뷰(column view 신축 | 미리보기 200, `TK_SURFACE`) — 루트 뷰 아래 분할 뷰 → column view,
/// 그리고 Tab 검사용 리스트 하나(`other`, 화면 밖 0 × 0 — 보이지 않게 숨기지는 않는다).
const ColEnv = struct {
    tree: ca.Tree,
    alloc: std.mem.Allocator,
    root_layer: *ca.Layer = undefined,
    preview: *ca.Layer = undefined,
    root_view: kit.View = undefined,
    root: kit.Root = undefined,
    split: kit.SplitView = undefined,
    cv: kit.ColumnView = undefined,
    src: FSrc = .{},
    other_src: CountSource = undefined,
    other: kit.List = undefined,
    log: ColLog = .{},
    kit_log: KitLog = .{},

    fn init(self: *ColEnv, alloc: std.mem.Allocator, face: *text.Face, deep: bool) !void {
        self.* = .{ .tree = ca.Tree.init(alloc), .alloc = alloc };
        const t = &self.tree;
        self.src.cols[0] = .{ .kids = &TREE_TOP, .face = face, .deep = deep };
        self.root_layer = try t.create(.{ .frame = .{ .x = 0, .y = 0, .w = LW, .h = LH }, .background = theme.TK_BG });
        t.setRoot(self.root_layer);
        self.root_view = .{ .layer = self.root_layer, .vtable = &ROOT_VT, .ctx = self, .name = "root" };
        self.root = kit.Root.init(t);
        self.root.setView(&self.root_view);
        self.root.unhandled = .{ .ctx = &self.kit_log, .on = KitLog.onUnhandled };
        try self.cv.init(t, &self.root, alloc, "columns", self.src.source(), self.src.cols[0].source(), 0);
        self.cv.hook = .{ .ctx = &self.log, .on = ColLog.on };
        self.preview = try t.create(.{ .background = theme.TK_SURFACE });
        try self.split.init(t, "split", self.cv.view.layer, self.preview, 200);
        self.split.notify = .{ .ctx = self, .on = splitLaidOut };
        try self.root_layer.addChild(self.split.view.layer);
        try self.root_view.addChild(alloc, &self.split.view);
        try self.split.view.addChild(alloc, &self.cv.view);
        self.other_src = .{ .n = 5, .face = face };
        try self.other.init(t, "other", self.other_src.source(), 0);
        try self.root_layer.addChild(self.other.view.layer);
        try self.root_view.addChild(alloc, &self.other.view);
        self.split.layout(.{ .x = 0, .y = 0, .w = LW, .h = LH });
        self.root.handle(.{ .focus = true });
        self.cv.focusFirst();
        _ = t.takeDirty();
    }

    fn splitLaidOut(ctx: *anyopaque, _: *kit.SplitView) void {
        const self: *ColEnv = @ptrCast(@alignCast(ctx));
        self.cv.sync();
    }

    fn deinit(self: *ColEnv) void {
        self.cv.deinit();
        self.other.deinit(self.alloc);
        self.split.deinit(self.alloc);
        self.root_view.deinit(self.alloc);
        self.tree.deinit();
    }

    fn key(self: *ColEnv, code: u32) void {
        self.root.handle(keyEv(code, .{}));
    }

    fn firstName(self: *ColEnv) []const u8 {
        return if (self.root.first) |f| f.name else "-";
    }
};

fn columnTests(io: std.Io, alloc: std.mem.Allocator, face: *text.Face, lut: *const [256]u8) !void {
    const pixels = try alloc.alloc(u32, LW * LH);
    defer alloc.free(pixels);
    const ref = try alloc.alloc(u32, LW * LH);
    defer alloc.free(ref);
    const scratch = try alloc.alloc(u32, LW * LH);
    defer alloc.free(scratch);

    // ── List의 reload · restore · reset ──
    {
        var env: ListEnv = undefined;
        try env.init(alloc, face, 100, 50, 120);
        defer env.deinit();
        var hooks: u32 = 0;
        const HookCount = struct {
            fn on(ctx: *anyopaque, _: *kit.List, _: kit.list.ListEvent) void {
                const n: *u32 = @ptrCast(@alignCast(ctx));
                n.* += 1;
            }
        };
        const l = &env.lists[0];
        l.hook = .{ .ctx = &hooks, .on = HookCount.on };
        l.select(50);
        hooks = 0;
        const off50 = l.offset;
        env.srcs[0].n = 10;
        l.reload();
        const d = env.tree.takeDirty();
        check(l.selected == 9 and l.offset == 0 and off50 > 0 and hooks == 0 and !env.tree.animating(), "reload after 100 -> 10 rows: sel 50 -> 9, offset {d} -> 0, no line, no animation", .{off50});
        check(d != null and Rect.eql(Rect.intersect(d.?, .{ .x = 0, .y = 0, .w = 416, .h = 752 }).?, .{ .x = 0, .y = 0, .w = 416, .h = 752 }), "reload redraws the whole list", .{});
        // 같은 오프셋에서 내용만 바뀌어도 다시 그린다.
        l.reload();
        check(env.tree.takeDirty() != null, "reload with the same offset still redraws the text", .{});
        env.srcs[0].n = 100_000;
        l.reload();
        l.restore(5000, 5000 * 24 - 100);
        check(l.selected == 5000 and l.offset == 5000 * 24 - 100 and hooks == 0 and !l.highlight.hidden and l.highlight.frame.y == 100, "restore(5000, offset): selection and offset as given, highlight at y 100, no line", .{});
        l.restore(200_000, 1 << 40);
        check(l.selected == 99_999 and l.offset == l.maxOffset(), "restore clamps the index and the offset", .{});
        env.srcs[0].n = 0;
        l.reload();
        check(l.selected == 0 and l.offset == 0 and l.highlight.hidden, "reload to 0 rows: sel 0, offset 0, no highlight", .{});
        env.srcs[0].n = 30;
        l.restore(20, 500);
        var other: CountSource = .{ .n = 3, .face = face };
        l.reset(other.source());
        check(l.selected == 0 and l.offset == 0 and l.count() == 3 and hooks == 0, "reset(source): new data, sel 0, offset 0", .{});
    }

    // ── → → ← (design의 끝나는 조건) ──
    {
        var env: ColEnv = undefined;
        try env.init(alloc, face, false);
        defer env.deinit();
        const cv = &env.cv;
        check(cv.view.layer.frame.w == 415 and env.split.separator.frame.x == 415 and env.preview.frame.x == 416 and env.preview.frame.w == 200, "split 616: columns 0..414, separator 415, preview 416..615", .{});
        check(cv.n == 1 and cv.focus == 0 and std.mem.eql(u8, env.firstName(), "col0"), "start: one column, col0 is first responder", .{});
        env.key(input.KEY_RIGHT);
        check(cv.n == 2 and cv.focus == 1 and cv.scroll == 0 and std.mem.eql(u8, env.firstName(), "col1"), "-> on a: two columns, focus col1, scroll 0", .{});
        env.key(input.KEY_RIGHT);
        check(cv.n == 3 and cv.focus == 2 and cv.scroll == 201, "-> on b: three columns, focus 2, scroll 201 (the third column needs 602 > 415)", .{});
        env.key(input.KEY_LEFT);
        const last = env.log.last;
        check(cv.n == 3 and cv.focus == 1 and cv.scroll == 201 and std.mem.eql(u8, env.firstName(), "col1") and last == .columns and last.columns.n == 3 and last.columns.focus == 1 and last.columns.scroll == 201, "<-: three columns stay, focus col1, scroll 201 (columns n=3 focus=1 scroll=201)", .{});
        check(!cv.list(0).accepts_focus and cv.list(1).accepts_focus and !cv.list(2).accepts_focus, "only the focused column accepts focus", .{});
        try crender(io, alloc, &env.tree, pixels, scratch, LWHOLE, lut);
        // 화면: col1 x 0..199, 구분선 200, col2 x 201..400, 구분선 401, 바탕 402..414, 분할 구분선 415, 미리보기 416..
        check(lpx(pixels, 150, 10) == theme.TK_SELECTION and lpx(pixels, 300, 10) == theme.TK_SELECTION_INACTIVE and lpx(pixels, 300, 34) == theme.TK_BG, "col1 row 0 is TK_SELECTION, col2 row 0 TK_SELECTION_INACTIVE, col2 row 1 the background", .{});
        check(lpx(pixels, 200, 300) == theme.TK_SEPARATOR and lpx(pixels, 401, 300) == theme.TK_SEPARATOR and lpx(pixels, 408, 300) == theme.TK_BG and lpx(pixels, 415, 300) == theme.TK_SEPARATOR and lpx(pixels, 500, 300) == theme.TK_SURFACE, "separators at x 200 / 401, background 402..414, split separator 415, preview TK_SURFACE", .{});
        // 셈을 다시: 열 0의 행 0만 열 0에 남았다(화면 밖).
        check(cv.list(0).selected == 0 and cv.list(1).selected == 0, "col0 and col1 keep their selections", .{});
        // 파일에서 →: 아무 일 없고 체인은 멈춘다(unhandled 0).
        env.key(input.KEY_LEFT);
        env.key(input.KEY_DOWN);
        env.key(input.KEY_DOWN);
        const opens = env.src.opens;
        env.key(input.KEY_RIGHT);
        env.key(input.KEY_ENTER);
        check(cv.focus == 0 and cv.n == 1 and cv.list(0).selected == 2 and env.src.opens == opens + 2 and env.kit_log.unhandled == 0, "-> and Enter on m.txt (a file): nothing, the keys stop at the column view", .{});
        // 첫 열의 ←: 아무 일 없음.
        const cols_before = env.log.columns;
        env.key(input.KEY_LEFT);
        check(cv.focus == 0 and env.log.columns == cols_before and env.kit_log.unhandled == 0, "<- on the first column: nothing", .{});
        // 수정키가 섞이면 column view의 것이 아니다.
        env.root.handle(keyEv(input.KEY_RIGHT, .{ .super = true }));
        check(env.kit_log.unhandled == 1, "Super+-> is not the column view's (unhandled)", .{});
    }

    // ── 이미 열린 오른쪽 열로의 → 는 포커스만 옮긴다(단계 B — lead의 대조) ──
    {
        var env: ColEnv = undefined;
        try env.init(alloc, face, false);
        defer env.deinit();
        const cv = &env.cv;
        env.key(input.KEY_RIGHT);
        env.key(input.KEY_RIGHT);
        env.key(input.KEY_DOWN);
        const opens = env.src.opens;
        const truncs = env.src.truncs;
        env.key(input.KEY_LEFT);
        env.key(input.KEY_RIGHT);
        check(cv.n == 3 and cv.focus == 2 and cv.list(2).selected == 1 and env.src.opens == opens and env.src.truncs == truncs and std.mem.eql(u8, env.firstName(), "col2"), "-> <- -> back into the open col2 keeps its selection (x.txt), opens nothing, truncates nothing", .{});
        env.key(input.KEY_LEFT);
        env.key(input.KEY_LEFT);
        env.key(input.KEY_ENTER);
        env.key(input.KEY_RIGHT);
        check(cv.n == 3 and cv.focus == 2 and cv.list(2).selected == 1 and env.src.opens == opens, "Enter and -> from col0 walk back to col2 the same way (opens {d})", .{env.src.opens});
    }

    // ── 선택 바뀜이 오른쪽 열을 버린다 · 클릭 · Tab ──
    {
        var env: ColEnv = undefined;
        try env.init(alloc, face, false);
        defer env.deinit();
        const cv = &env.cv;
        env.key(input.KEY_RIGHT);
        env.key(input.KEY_RIGHT);
        env.key(input.KEY_LEFT);
        env.key(input.KEY_LEFT);
        check(cv.n == 3 and cv.focus == 0 and cv.scroll == 0, "<- <- to col0: three columns stay, scroll back to 0", .{});
        env.key(input.KEY_DOWN);
        check(cv.n == 1 and cv.focus == 0 and env.src.last_trunc == 1 and cv.list(0).selected == 1, "a down in col0 (a -> z) drops the columns on its right (truncated n=1)", .{});
        env.key(input.KEY_UP);
        env.key(input.KEY_RIGHT);
        env.key(input.KEY_RIGHT);
        env.key(input.KEY_LEFT);
        // 클릭: 화면의 col2(x 201..400, 스크롤 201) 행 1(x.txt)을 누르면 col2가 포커스, 오른쪽 열이 없으니 버림 없음.
        env.root.handle(.{ .button = .{ .code = input.BTN_LEFT, .pressed = true, .x = 300, .y = 30 } });
        check(cv.focus == 2 and cv.n == 3 and cv.list(2).selected == 1 and std.mem.eql(u8, env.firstName(), "col2"), "a click on col2 row 1 focuses col2 and selects x.txt", .{});
        // 같은 행 클릭(바뀌지 않음)으로 col1에 포커스 — 오른쪽 열은 남는다.
        env.root.handle(.{ .button = .{ .code = input.BTN_LEFT, .pressed = true, .x = 100, .y = 10 } });
        check(cv.focus == 1 and cv.n == 3, "a click on col1's selected row focuses col1 and keeps col2", .{});
        // Tab: column view는 한 자리 — col1 → other → col1(col0 · col2를 안 거친다).
        env.key(input.KEY_TAB);
        const t1 = env.firstName();
        env.key(input.KEY_TAB);
        const t2 = env.firstName();
        env.root.handle(keyEv(input.KEY_TAB, .{ .shift = true }));
        const t3 = env.firstName();
        check(std.mem.eql(u8, t1, "other") and std.mem.eql(u8, t2, "col1") and std.mem.eql(u8, t3, "other"), "Tab: col1 -> {s} -> {s}, Shift+Tab -> {s} (the column view is one stop)", .{ t1, t2, t3 });
        // 포커스가 column view 밖일 때의 ←는 column view에 안 온다(other가 받지 않으니 unhandled).
        const un = env.kit_log.unhandled;
        env.key(input.KEY_LEFT);
        check(cv.focus == 1 and env.kit_log.unhandled == un + 1, "<- while 'other' has the focus does not reach the column view", .{});
        // 바깥 포커스에서 열을 클릭하면 열이 포커스를 가져온다.
        env.root.handle(.{ .button = .{ .code = input.BTN_LEFT, .pressed = true, .x = 300, .y = 10 } });
        check(cv.focus == 2 and std.mem.eql(u8, env.firstName(), "col2") and cv.n == 3, "a click on col2 from outside takes the focus to col2", .{});
        // 창 포커스: 다시 붙은 열도 창 포커스를 안다.
        env.root.handle(.{ .focus = false });
        env.key(input.KEY_LEFT);
        env.key(input.KEY_LEFT);
        env.key(input.KEY_DOWN);
        env.key(input.KEY_UP);
        env.key(input.KEY_RIGHT);
        env.key(input.KEY_RIGHT);
        check(cv.list(2).highlight.background == theme.TK_SELECTION_INACTIVE and !cv.list(2).window_focused, "a column re-attached while the window is unfocused draws the inactive colour", .{});
        env.root.handle(.{ .focus = true });
        check(cv.list(2).highlight.background == theme.TK_SELECTION, "window focus back: the focused column is TK_SELECTION", .{});
    }

    // ── 버린 열이 first responder일 때(갱신이 오른쪽 열을 버림) ──
    {
        var env: ColEnv = undefined;
        try env.init(alloc, face, false);
        defer env.deinit();
        const cv = &env.cv;
        env.key(input.KEY_RIGHT);
        env.key(input.KEY_RIGHT);
        cv.truncate(2);
        check(cv.n == 2 and cv.focus == 1 and std.mem.eql(u8, env.firstName(), "col1") and cv.scroll == 0, "truncate(2) while col2 has the focus: focus moves to col1 first, scroll 0", .{});
        cv.truncate(1);
        check(cv.n == 1 and cv.focus == 0 and std.mem.eql(u8, env.firstName(), "col0"), "truncate(1): col0", .{});
        var probe: TV = .{ .accepts = true };
        const pl = try env.tree.create(.{});
        probe.init(pl, "probe");
        defer probe.view.deinit(alloc);
        try env.root_view.addChild(alloc, &probe.view);
        _ = env.root.setFirstResponder(&probe.view);
        env.root_view.removeChild(&probe.view);
        env.root.viewRemoved(&probe.view);
        check(env.root.first == null and probe.focus_off == 1 and probe.view.parent == null, "View.removeChild + Root.viewRemoved clear a removed first responder", .{});
    }

    // ── 풀: 수백 번 오가도 레이어 수가 늘지 않는다 · 깊이 32의 거절 ──
    {
        var env: ColEnv = undefined;
        try env.init(alloc, face, false);
        defer env.deinit();
        env.key(input.KEY_RIGHT);
        env.key(input.KEY_RIGHT);
        env.key(input.KEY_LEFT);
        env.key(input.KEY_LEFT);
        env.key(input.KEY_DOWN);
        env.key(input.KEY_UP);
        const layers = env.tree.all.items.len;
        const kids = env.cv.view.children.capacity;
        for (0..300) |_| {
            env.key(input.KEY_RIGHT);
            env.key(input.KEY_RIGHT);
            env.key(input.KEY_LEFT);
            env.key(input.KEY_LEFT);
            env.key(input.KEY_DOWN);
            env.key(input.KEY_UP);
        }
        check(env.tree.all.items.len == layers and env.cv.view.children.capacity == kids and env.cv.n == 1, "300 rounds of -> -> <- <- down up: {d} layers before and after, view children capacity unchanged", .{layers});
    }
    {
        var env: ColEnv = undefined;
        try env.init(alloc, face, true);
        defer env.deinit();
        for (0..40) |_| env.key(input.KEY_RIGHT);
        const cv = &env.cv;
        const want_scroll = kit.column.columnX(31) + 200 - 415;
        check(cv.n == kit.column.MAX_COLUMNS and cv.focus == 31 and env.kit_log.unhandled == 0 and cv.scroll >= want_scroll and cv.scroll % 201 == 0 and cv.scroll <= kit.column.columnX(31), "depth: 40 rights stop at 32 columns (focus 31, scroll {d} on a column boundary)", .{cv.scroll});
        for (0..40) |_| env.key(input.KEY_LEFT);
        check(cv.focus == 0 and cv.scroll == 0 and cv.n == 32, "40 lefts: focus 0, scroll 0, 32 columns stay", .{});
    }

    // ── 부분 = 통째(가로 스크롤 포함, 무작위 조작) ──
    {
        var env: ColEnv = undefined;
        try env.init(alloc, face, false);
        defer env.deinit();
        try crender(io, alloc, &env.tree, pixels, scratch, LWHOLE, lut);
        var prng = std.Random.DefaultPrng.init(0xC0C0);
        const r = prng.random();
        const keys = [_]u32{ input.KEY_RIGHT, input.KEY_RIGHT, input.KEY_LEFT, input.KEY_DOWN, input.KEY_UP, input.KEY_ENTER, input.KEY_HOME, input.KEY_END, input.KEY_TAB };
        var mismatch: u32 = 0;
        var partial: u32 = 0;
        var scrolls: u32 = 0;
        var last_scroll = env.cv.scroll;
        var steps: u32 = 0;
        while (steps < 300) : (steps += 1) {
            switch (r.uintLessThan(u32, 6)) {
                0, 1, 2 => env.key(keys[r.uintLessThan(usize, keys.len)]),
                3 => env.root.handle(.{ .button = .{ .code = input.BTN_LEFT, .pressed = true, .x = @floatFromInt(r.uintLessThan(u32, 415)), .y = @floatFromInt(r.uintLessThan(u32, 80)) } }),
                4 => env.root.handle(.{ .scroll = .{ .dy = 0, .discrete = r.intRangeAtMost(i32, -1, 1), .x = @floatFromInt(r.uintLessThan(u32, 415)), .y = 100 } }),
                else => env.root.handle(.{ .focus = r.uintLessThan(u32, 4) != 0 }),
            }
            if (env.cv.scroll != last_scroll) scrolls += 1;
            last_scroll = env.cv.scroll;
            const d = env.tree.takeDirty() orelse continue;
            const clip = Rect.intersect(d, LWHOLE) orelse continue;
            if (!Rect.eql(clip, LWHOLE)) partial += 1;
            try crender(io, alloc, &env.tree, pixels, scratch, clip, lut);
            try crender(io, alloc, &env.tree, ref, scratch, LWHOLE, lut);
            if (!std.mem.eql(u32, pixels, ref)) mismatch += 1;
        }
        check(mismatch == 0 and partial > 50 and scrolls > 5, "column view partial = whole: 300 random steps, {d} partial redraws, {d} horizontal scrolls, {d} mismatch(es)", .{ partial, scrolls, mismatch });
    }

    // ── 13 분할 뷰 배치 표 ──
    {
        var t = ca.Tree.init(alloc);
        defer t.deinit();
        const a = try t.create(.{});
        const b = try t.create(.{});
        var sv: kit.SplitView = undefined;
        try sv.init(&t, "split", a, b, 200);
        defer sv.deinit(alloc);
        var notified: u32 = 0;
        const N = struct {
            fn on(ctx: *anyopaque, _: *kit.SplitView) void {
                const n: *u32 = @ptrCast(@alignCast(ctx));
                n.* += 1;
            }
        };
        sv.notify = .{ .ctx = &notified, .on = N.on };
        const Row = struct { w: f32, ax: f32, aw: f32, sx: f32, bx: f32, bw: f32 };
        const rows = [_]Row{
            .{ .w = 616, .ax = 0, .aw = 415, .sx = 415, .bx = 416, .bw = 200 },
            .{ .w = 1240, .ax = 0, .aw = 1039, .sx = 1039, .bx = 1040, .bw = 200 },
            .{ .w = 201, .ax = 0, .aw = 0, .sx = 0, .bx = 1, .bw = 200 },
            .{ .w = 100, .ax = 0, .aw = 0, .sx = 0, .bx = 1, .bw = 200 },
        };
        var ok = true;
        for (rows) |row| {
            sv.layout(.{ .x = 10, .y = 20, .w = row.w, .h = 300 });
            ok = ok and a.frame.x == row.ax and a.frame.w == row.aw and sv.separator.frame.x == row.sx and sv.separator.frame.w == 1 and
                b.frame.x == row.bx and b.frame.w == row.bw and a.frame.h == 300 and b.frame.h == 300 and sv.view.layer.frame.x == 10;
        }
        check(ok and notified == rows.len and sv.view.layer.masks, "split layout table: 616 / 1240 / 201 / 100 wide (first flex, 1 px separator, second 200), notified each time", .{});
    }
}

fn crender(io: std.Io, alloc: std.mem.Allocator, t: *ca.Tree, pixels: []u32, scratch: []u32, clip: Rect, lut: *const [256]u8) !void {
    try lrender(io, alloc, t, pixels, scratch, clip, lut);
}

// ── 14 tars-files 모델(TK-M3 단계 B) ──────────────────────────────────

const fsearch = @import("files_search");
const fm = fsearch.model;

/// 메모리 표 DirSource — 항목을 `chunk`개씩 준다. 열고 닫은 수를 센다.
const MemDir = struct {
    items: []const fm.Raw,
    chunk: usize,
    opened: u32 = 0,
    closed: u32 = 0,
    fail_open: bool = false,

    const MH = struct { pos: usize };
    var handles: [8]MH = undefined;
    var used: usize = 0;

    fn open(ctx: *anyopaque, path: []const u8) anyerror!*anyopaque {
        _ = path;
        const self: *MemDir = @ptrCast(@alignCast(ctx));
        if (self.fail_open) return error.AccessDenied;
        self.opened += 1;
        const h = &handles[used % handles.len];
        used += 1;
        h.* = .{ .pos = 0 };
        return h;
    }
    fn next(ctx: *anyopaque, handle: *anyopaque) anyerror!?[]const fm.Raw {
        const self: *MemDir = @ptrCast(@alignCast(ctx));
        const h: *MH = @ptrCast(@alignCast(handle));
        if (h.pos >= self.items.len) return null;
        const end = @min(h.pos + self.chunk, self.items.len);
        defer h.pos = end;
        return self.items[h.pos..end];
    }
    fn close(ctx: *anyopaque, handle: *anyopaque) void {
        _ = handle;
        const self: *MemDir = @ptrCast(@alignCast(ctx));
        self.closed += 1;
    }
    fn source(self: *MemDir) fm.DirSource {
        return .{ .ctx = self, .open = open, .next = next, .close = close };
    }
};

fn names(l: *const fm.Listing, buf: []u8) []const u8 {
    var w: usize = 0;
    for (l.items(), 0..) |e, i| {
        const s = std.fmt.bufPrint(buf[w..], "{s}{s}{s}", .{ if (i == 0) "" else " ", e.name, if (e.kind == .dir) "/" else "" }) catch return buf[0..w];
        w += s.len;
    }
    return buf[0..w];
}

fn ent(name: []const u8, kind: fm.Kind) fm.Entry {
    return .{ .name = name, .kind = kind };
}

fn modelTests(alloc: std.mem.Allocator) !void {
    // ── 순서 ──
    const O = std.math.Order;
    const pairs = [_]struct { a: []const u8, b: []const u8, want: O }{
        .{ .a = "a2", .b = "a10", .want = .lt },
        .{ .a = "a10", .b = "a9", .want = .gt },
        .{ .a = "a02", .b = "a2", .want = .lt }, // 값은 같고 바이트로 가른다
        .{ .a = "a", .b = "B", .want = .lt },
        .{ .a = "File", .b = "file", .want = .lt }, // 대소문자만 다르면 바이트 순(F 0x46 < f 0x66)
        .{ .a = "가", .b = "나", .want = .lt },
        .{ .a = "z", .b = "가", .want = .lt }, // ASCII가 한글(UTF-8 0xEA..)보다 앞
        .{ .a = "문서 9", .b = "문서 10", .want = .lt },
        .{ .a = "x", .b = "x1", .want = .lt },
        .{ .a = "1", .b = "a", .want = .lt },
    };
    var ord_ok = true;
    for (pairs) |p| ord_ok = ord_ok and fm.naturalOrder(p.a, p.b) == p.want and fm.naturalOrder(p.b, p.a) == p.want.invert();
    check(ord_ok, "natural order: a2 < a10, a02 < a2, a < B, File < file, 가 < 나, z < 가, 문서 9 < 문서 10, x < x1, 1 < a ({d} pairs both ways)", .{pairs.len});
    check(fm.order(ent("zzz", .dir), ent("aaa", .file)) == .lt, "directories come before files", .{});

    // ── 조각 크기 1 · 7 · 전부, 숨김 ──
    const raw = [_]fm.Raw{
        ent("m.txt", .file), ent(".", .dir),   ent("..", .dir),     ent("z", .dir),     ent(".h", .file), ent("a10", .file),
        ent("a", .dir),      ent("a2", .file), ent("B.txt", .file),
        ent("문서", .dir),
        ent("가나.txt", .file),
        ent(".git", .dir),   ent("b", .dir),   ent("file", .file),  ent("File", .file),
    };
    const want = "a/ b/ z/ 문서/ a2 a10 B.txt File file m.txt 가나.txt";
    var bufs: [3][256]u8 = undefined;
    var got: [3][]const u8 = undefined;
    for ([_]usize{ 1, 7, raw.len }, 0..) |k, i| {
        var md: MemDir = .{ .items = &raw, .chunk = k };
        var l = try fm.readAll(alloc, md.source(), "/x");
        defer l.deinit();
        got[i] = names(&l, &bufs[i]);
        check(md.opened == 1 and md.closed == 1 and l.state == .done and l.chunks == (raw.len + k - 1) / k, "chunk size {d}: opened and closed once, {d} chunks", .{ k, l.chunks });
    }
    check(std.mem.eql(u8, got[0], want) and std.mem.eql(u8, got[1], want) and std.mem.eql(u8, got[2], want), "chunk sizes 1 / 7 / all give the same sorted list without hidden names: {s}", .{got[0]});

    // ── 취소: 한 조각 뒤 닫은 손잡이는 다시 안 읽고, 새로 연 목록은 처음부터 ──
    {
        var md: MemDir = .{ .items = &raw, .chunk = 4 };
        const src = md.source();
        var l1 = fm.Listing.init(alloc);
        const h1 = try src.open(src.ctx, "/x");
        _ = try l1.addChunk((try src.next(src.ctx, h1)).?);
        src.close(src.ctx, h1);
        const partial = l1.items().len;
        l1.deinit();
        var l2 = try fm.readAll(alloc, src, "/x");
        defer l2.deinit();
        var b2: [256]u8 = undefined;
        check(partial == 2 and md.opened == 2 and md.closed == 2 and std.mem.eql(u8, names(&l2, &b2), want), "cancel after one chunk (2 kept of 4 — . and .. filtered), the next load starts over and matches", .{});
        md.fail_open = true;
        check(if (fm.readAll(alloc, src, "/x")) |_| false else |_| true, "a failed open is an error (the app shows the column as unopenable)", .{});
    }

    // ── 10만 항목: 조각 병합 = 한 번 정렬 ──
    {
        const N = 100_000;
        const pool = try alloc.alloc(u8, N * 16);
        defer alloc.free(pool);
        const raws = try alloc.alloc(fm.Raw, N);
        defer alloc.free(raws);
        var prng = std.Random.DefaultPrng.init(0xF11E5);
        const r = prng.random();
        // 이름: 순서를 섞은 "f<번호>.txt"와 디렉터리 "d<번호>"(1/10) — 이름은 모두 다르다.
        const perm = try alloc.alloc(u32, N);
        defer alloc.free(perm);
        for (perm, 0..) |*p, i| p.* = @intCast(i);
        r.shuffle(u32, perm);
        for (raws, perm, 0..) |*x, v, i| {
            const dirk = v % 10 == 0;
            const s = try std.fmt.bufPrint(pool[i * 16 .. i * 16 + 16], "{s}{d}{s}", .{ if (dirk) "d" else "f", v, if (dirk) "" else ".txt" });
            x.* = .{ .name = s, .kind = if (dirk) .dir else .file };
        }
        var md: MemDir = .{ .items = raws, .chunk = 818 };
        const t0 = nowMs();
        var l = try fm.readAll(alloc, md.source(), "/big");
        defer l.deinit();
        const t1 = nowMs();
        const sorted = try alloc.dupe(fm.Entry, raws);
        defer alloc.free(sorted);
        std.sort.pdq(fm.Entry, sorted, {}, fm.lessThan);
        const t2 = nowMs();
        var same = l.items().len == N;
        if (same) for (l.items(), sorted) |a, b| {
            same = same and a.kind == b.kind and std.mem.eql(u8, a.name, b.name);
        };
        check(same and l.chunks == 123 and std.mem.eql(u8, l.items()[0].name, "d0") and std.mem.eql(u8, l.items()[N - 1].name, "f99999.txt"), "100,000 entries in 123 chunks of 818: merged list = one sort (merge {d} ms, one sort {d} ms, host)", .{ t1 - t0, t2 - t1 });
    }

    // ── 안정 선택(확정 12) — 행 24, 뷰 240(10행) ──
    const RH = 24;
    const VH = 240;
    const Case = struct {
        what: []const u8,
        new: []const fm.Entry,
        sel: ?fm.Entry,
        index: usize,
        offset: u64,
        want_index: ?usize,
        want_offset: u64,
        want_gone: bool,
    };
    const add_above = [_]fm.Entry{ ent("a", .dir), ent("b", .dir), ent("d", .dir), ent("f", .file), ent("h", .file), ent("j", .file) };
    const del_above = [_]fm.Entry{ ent("d", .dir), ent("f", .file), ent("h", .file), ent("j", .file) };
    const del_sel = [_]fm.Entry{ ent("b", .dir), ent("d", .dir), ent("h", .file), ent("j", .file) };
    const del_last = [_]fm.Entry{ ent("b", .dir), ent("d", .dir), ent("f", .file), ent("h", .file) };
    const case_pair = [_]fm.Entry{ ent("Readme", .file), ent("readme", .file) };
    const cases = [_]Case{
        .{ .what = "one added above", .new = &add_above, .sel = ent("f", .file), .index = 2, .offset = 0, .want_index = 3, .want_offset = 0, .want_gone = false },
        .{ .what = "one removed above", .new = &del_above, .sel = ent("f", .file), .index = 2, .offset = 0, .want_index = 1, .want_offset = 0, .want_gone = false },
        .{ .what = "the selection removed -> the next one", .new = &del_sel, .sel = ent("f", .file), .index = 2, .offset = 0, .want_index = 2, .want_offset = 0, .want_gone = true },
        .{ .what = "the last one removed -> the new last", .new = &del_last, .sel = ent("j", .file), .index = 4, .offset = 0, .want_index = 3, .want_offset = 0, .want_gone = true },
        .{ .what = "everything removed -> no selection", .new = &.{}, .sel = ent("f", .file), .index = 2, .offset = 0, .want_index = null, .want_offset = 0, .want_gone = true },
        .{ .what = "case-only twins: the exact name", .new = &case_pair, .sel = ent("readme", .file), .index = 0, .offset = 0, .want_index = 1, .want_offset = 0, .want_gone = false },
        .{ .what = "a file that became a directory", .new = &[_]fm.Entry{ ent("f", .dir), ent("b", .file) }, .sel = ent("f", .file), .index = 2, .offset = 0, .want_index = 0, .want_offset = 0, .want_gone = false },
    };
    var st_ok = true;
    for (cases) |c| {
        const a = fm.follow(.{ .sel = c.sel, .index = c.index, .offset = c.offset, .touched = true }, c.new, VH, RH);
        const ok = std.meta.eql(a.index, c.want_index) and a.offset == c.want_offset and a.gone == c.want_gone;
        if (!ok) std.debug.print("tk_test:   stable selection '{s}': got index {?d} offset {d} gone {}\n", .{ c.what, a.index, a.offset, a.gone });
        st_ok = st_ok and ok;
    }
    check(st_ok, "stable selection table: {d} cases (added / removed above, selection removed, last removed, all removed, case twins, kind changed)", .{cases.len});

    // 스크롤: 화면 위치를 지킨다 · 화면 밖이면 오프셋 그대로(자름만).
    {
        const big = try alloc.alloc(fm.Entry, 20_000);
        defer alloc.free(big);
        const nb = try alloc.alloc(u8, 20_000 * 8);
        defer alloc.free(nb);
        for (big, 0..) |*e, i| e.* = ent(try std.fmt.bufPrint(nb[i * 8 .. i * 8 + 8], "n{d:0>6}", .{i}), .file);
        // 선택 n000500이 화면 셋째 행(오프셋 = 498 × 24): 위에 1만 개를 더하면(같은 이름 꼴로 앞에) 색인 10500, 같은 화면 자리.
        const sel = big[500];
        const a1 = fm.follow(.{ .sel = sel, .index = 500, .offset = 498 * 24, .touched = true }, big, VH, RH);
        check(a1.index.? == 500 and a1.offset == 498 * 24, "the same list: index and offset unchanged", .{});
        const a2 = fm.follow(.{ .sel = sel, .index = 100, .offset = 98 * 24, .touched = true }, big, VH, RH);
        check(a2.index.? == 500 and a2.offset == 498 * 24, "the row moved from 100 to 500 keeps its screen place (offset 98*24 -> 498*24)", .{});
        const a3 = fm.follow(.{ .sel = sel, .index = 100, .offset = 5000 * 24, .touched = true }, big, VH, RH);
        check(a3.index.? == 500 and a3.offset == 5000 * 24, "a selection off screen: the offset stays (5000*24)", .{});
        const a4 = fm.follow(.{ .sel = sel, .index = 100, .offset = 5000 * 24, .touched = true }, big[0..600], VH, RH);
        check(a4.index.? == 500 and a4.offset == 600 * 24 - VH, "a shorter list clamps the offset ({d})", .{a4.offset});
        const a5 = fm.follow(.{ .sel = big[19_999], .index = 19_999, .offset = 19_990 * 24, .touched = true }, big[0..10], VH, RH);
        check(a5.index.? == 9 and a5.offset == 0 and a5.gone, "the selection beyond the new end: the last row, offset 0", .{});
    }

    // ── 첫 로딩의 선택(확정 10): 안 건드렸으면 0행, 건드렸으면 이름 ──
    {
        // 셋째 조각까지: 조각마다 앞쪽 이름이 끼어든다.
        const chunks = [_][]const fm.Raw{
            &.{ ent("m", .file), ent("p", .file) },
            &.{ ent("c", .file), ent("x", .file) },
            &.{ ent("a", .file), ent("n", .file) },
        };
        var untouched = fm.Listing.init(alloc);
        defer untouched.deinit();
        var touched = fm.Listing.init(alloc);
        defer touched.deinit();
        var u_index: usize = 0;
        var t_index: usize = 0;
        var t_ok = true;
        var u_ok = true;
        for (chunks, 0..) |ch, k| {
            const ub: fm.Before = .{ .sel = if (untouched.items().len != 0) untouched.items()[u_index] else null, .index = u_index, .offset = 0, .touched = false };
            _ = try untouched.addChunk(ch);
            u_index = fm.follow(ub, untouched.items(), VH, RH).index.?;
            u_ok = u_ok and u_index == 0;
            const tb: fm.Before = .{ .sel = if (touched.items().len != 0) touched.items()[t_index] else null, .index = t_index, .offset = 0, .touched = k >= 1 };
            _ = try touched.addChunk(ch);
            t_index = fm.follow(tb, touched.items(), VH, RH).index.?;
            // 첫 조각 뒤 사용자가 `↓`로 p(1행)를 골랐다고 친다.
            if (k == 0) t_index = 1;
            t_ok = t_ok and std.mem.eql(u8, touched.items()[t_index].name, "p");
        }
        check(u_ok and std.mem.eql(u8, untouched.items()[0].name, "a"), "first load untouched: always row 0 (now 'a' after three chunks)", .{});
        check(t_ok and t_index == 4, "first load touched: the selection follows 'p' as names land above it (row {d})", .{t_index});
    }

    var jb: [64]u8 = undefined;
    check(std.mem.eql(u8, try fm.join(&jb, "/", "tmp"), "/tmp") and std.mem.eql(u8, try fm.join(&jb, "/tmp/tkf", "a"), "/tmp/tkf/a"), "join: / + tmp = /tmp, /tmp/tkf + a = /tmp/tkf/a", .{});
}

fn nowMs() u64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1000 + @as(u64, @intCast(ts.nsec)) / 1_000_000;
}

// ── 15 텍스트 놓기 · 글자 키 표(TK-M4 단계 A) ────────────────────────────

const layout = cg.layout;

/// 결정적인 가짜 글꼴: ASCII 10 · 그 밖 20 · 결합 표시 0 · `…` 10, kern은 (A, V) −2 하나. U+1100대 · 漢 · U+FFFD는 글리프가 없다(Pretendard처럼).
const FakeFont = struct {
    fallback: bool = true,

    fn adv(_: *anyopaque, cp: u21) f32 {
        if (layout.isMark(cp)) return 0;
        if (cp == layout.ELLIPSIS_CP) return 10;
        return if (cp < 0x80) 10 else 20;
    }
    fn kern(_: *anyopaque, l: u21, r: u21) f32 {
        return if (l == 'A' and r == 'V') -2 else 0;
    }
    fn has(ctx: *anyopaque, cp: u21) bool {
        const self: *FakeFont = @ptrCast(@alignCast(ctx));
        if (cp >= 0x1100 and cp <= 0x11FF) return false;
        if (cp == 0x6F22 or cp == 0xFFFD) return false;
        if (cp == layout.FALLBACK) return self.fallback;
        return true;
    }
    fn metrics(self: *FakeFont) layout.Metrics {
        return .{ .ctx = self, .advance_fn = adv, .kern_fn = kern, .has_fn = has };
    }
};

fn clusterCount(s: []const u8) usize {
    var it = layout.Clusters.init(s);
    var n: usize = 0;
    while (it.next()) |_| n += 1;
    return n;
}

fn placerEnd(m: layout.Metrics, s: []const u8) f32 {
    var pl = layout.Placer.init(m, s, 0);
    while (pl.next()) |_| {}
    return pl.pen;
}

fn displayed(m: layout.Metrics, s: []const u8, out: []u21) []u21 {
    var pl = layout.Placer.init(m, s, 0);
    var n: usize = 0;
    while (pl.next()) |g| {
        if (n < out.len) out[n] = g.cp;
        n += 1;
    }
    return out[0..@min(n, out.len)];
}

fn layoutTests(io: std.Io, alloc: std.mem.Allocator, face: *text.Face, lut: *const [256]u8) !void {
    var fake: FakeFont = .{};
    const m = fake.metrics();

    // 클러스터: a · 잘못된 바이트 · e+U+0301 · NFD 한(1112 1161 11AB) · 홀로 선 ㄱ(1100) · 4바이트 😀 · 홀로 선 중성 ㅏ(1161).
    const mixed = "a\xffe\u{301}\u{1112}\u{1161}\u{11AB}\u{1100}\u{1F600}\u{1161}";
    {
        var it = layout.Clusters.init(mixed);
        var got: [10]layout.Cluster = undefined;
        var n: usize = 0;
        while (it.next()) |cl| : (n += 1) got[n] = cl;
        check(n == 7, "clusters of a·FF·e+0301·NFD 한·ᄀ·😀·ᅡ: {d} (want 7)", .{n});
        check(got[0].start == 0 and got[0].end == 1 and got[0].cps[0] == 'a', "cluster 0: a [0,1)", .{});
        check(got[1].start == 1 and got[1].end == 2 and got[1].cps[0] == '?' and got[1].n == 1, "cluster 1: an invalid byte is one byte shown as ?", .{});
        check(got[2].start == 2 and got[2].end == 5 and got[2].n == 2 and got[2].cps[0] == 'e' and got[2].cps[1] == 0x301, "cluster 2: e + U+0301 is one cluster [2,5)", .{});
        check(got[3].start == 5 and got[3].end == 14 and got[3].n == 1 and got[3].cps[0] == 0xD55C, "cluster 3: NFD L V T (9 bytes) shows as the syllable 한 U+D55C", .{});
        check(got[4].end - got[4].start == 3 and got[4].cps[0] == 0x3131, "cluster 4: a lone choseong ᄀ shows as compatibility ㄱ U+3131", .{});
        check(got[5].end - got[5].start == 4 and got[5].cps[0] == 0x1F600, "cluster 5: a 4-byte code point is one cluster", .{});
        check(got[6].cps[0] == 0x314F and got[6].end == mixed.len, "cluster 6: a lone jungseong ᅡ shows as ㅏ U+314F", .{});
        check(layout.compatJamo(0x11A8) == 0x3131 and layout.compatJamo(0x11C2) == 0x314E and layout.compatJamo(0x1112) == 0x314E and layout.compatJamo(0x1175) == 0x3163 and layout.compatJamo(0x1113) == null, "compatibility jamo: T ᆨ→ㄱ, T ᇂ→ㅎ, L ᄒ→ㅎ, V ᅵ→ㅣ, old jamo none", .{});
        // NFD 가(L V, T 없음)와 L V 다음의 L(다음 음절)
        var it2 = layout.Clusters.init("\u{1100}\u{1161}\u{1102}\u{1161}");
        const c0 = it2.next().?;
        const c1 = it2.next().?;
        check(c0.cps[0] == 0xAC00 and c1.cps[0] == 0xB098 and it2.next() == null, "NFD 가나 (L V L V) is two syllables 가 나", .{});
    }

    // 대체와 측정 = 그리기.
    {
        var buf: [8]u21 = undefined;
        const d = displayed(m, "\u{6F22}x\u{301}", &buf);
        check(d.len == 3 and d[0] == layout.FALLBACK and d[1] == 'x' and d[2] == 0x301, "a missing glyph shows as □, marks stay", .{});
        check(layout.measure(m, "\u{6F22}") == 20 and placerEnd(m, "\u{6F22}") == 20, "□'s width is measured as it is drawn (20)", .{});
        var nofb: FakeFont = .{ .fallback = false };
        const m2 = nofb.metrics();
        const d2 = displayed(m2, "\u{6F22}", &buf);
        check(d2.len == 1 and d2[0] == 0x6F22, "without □ in the font the missing glyph is kept (.notdef)", .{});
        const samples = [_][]const u8{ "", "AV", "hello", mixed, "\u{6F22}\u{6F22}a", "AVAV\xff\xfe", "\u{1100}\u{1161}\u{11A8}\u{1100}" };
        var all = true;
        for (samples) |sm| all = all and layout.measure(m, sm) == placerEnd(m, sm);
        check(all, "fake metrics: measure = placer's end pen for {d} samples", .{samples.len});
        check(layout.measure(m, "AV") == 18 and layout.measure(m, "VA") == 20, "kern AV -2: AV 18, VA 20", .{});
        check(layout.measure(m, "a\xffb") == 30, "an invalid byte has the width of ? (a?b = 30)", .{});
        check(layout.measure(m, "\u{1112}\u{1161}\u{11AB}") == layout.measure(m, "한"), "NFD 한 measures as NFC 한", .{});
    }

    // 경계 · 캐럿 x 왕복 · 부분 폭.
    {
        const sx = "xAV\u{1112}\u{1161}e\u{301}\xffz";
        var st_buf: [32]layout.Stop = undefined;
        const st = try layout.stops(m, sx, &st_buf);
        var xs_buf: [32]f32 = undefined;
        const xs = try layout.caretXs(m, sx, &xs_buf);
        check(st.len == 8 and xs.len == 8 and st[7].byte == sx.len and st[7].x == layout.measure(m, sx), "stops: 7 clusters + the end, the last x = the width {d:.1}", .{st[7].x});
        var round = true;
        var spans = true;
        var carets = true;
        for (st, 0..) |a, i| {
            round = round and layout.indexAt(m, sx, a.x) == a.byte;
            carets = carets and layout.caretX(m, sx, a.byte) == a.x and xs[i] == a.x;
            if (i + 1 < st.len) {
                const mid = (a.x + st[i + 1].x) / 2;
                round = round and layout.indexAt(m, sx, mid - 0.01) == a.byte and layout.indexAt(m, sx, mid + 0.01) == st[i + 1].byte;
            }
            var j = i + 1;
            while (j < st.len) : (j += 1) spans = spans and layout.spanWidth(st, i, j) == layout.measure(m, sx[a.byte..st[j].byte]);
        }
        check(round, "indexAt(caret x) = the boundary, and past a cluster's middle it is the right boundary", .{});
        check(carets, "caretX = caretXs = stops x at every boundary", .{});
        check(spans, "spanWidth(a, b) = measure(s[a..b]) for every pair (kern AV inside)", .{});
        check(layout.indexAt(m, sx, -5) == 0 and layout.indexAt(m, sx, 1e6) == sx.len, "indexAt clamps: left of the text 0, right of it the end", .{});
        var small: [3]layout.Stop = undefined;
        check(if (layout.stops(m, sx, &small)) |_| false else |_| true, "stops into too few slots is error.NoSpace", .{});
    }

    // 가운데 생략.
    {
        var sc: [64]layout.Stop = undefined;
        var buf: [128]u8 = undefined;
        const s10 = "abcdefghij";
        const same = try layout.elideMiddle(m, s10, 100, &sc, &buf);
        check(same.ptr == s10.ptr and same.len == s10.len, "elide: a text that fits comes back as itself", .{});
        const e60 = try layout.elideMiddle(m, s10, 60, &sc, &buf);
        check(std.mem.eql(u8, e60, "ab\u{2026}hij"), "elide 10 x 10 px into 60: ab…hij (tail leaning) got {s}", .{e60});
        const e59 = try layout.elideMiddle(m, s10, 59, &sc, &buf);
        check(std.mem.eql(u8, e59, "ab\u{2026}ij"), "elide into 59: ab…ij got {s}", .{e59});
        const e9 = try layout.elideMiddle(m, s10, 9, &sc, &buf);
        const e10 = try layout.elideMiddle(m, s10, 10, &sc, &buf);
        check(e9.len == 0 and std.mem.eql(u8, e10, "\u{2026}"), "elide: under the width of … is empty, exactly … is …", .{});
        const name = "long-directory-name-0123456789-\u{1112}\u{1161}\u{11AB}\u{1100}\u{1161}\u{11A8}-end.txt";
        var ok = true;
        var w: f32 = 0;
        while (w < layout.measure(m, name) + 20) : (w += 3) {
            const e = try layout.elideMiddle(m, name, w, &sc, &buf);
            if (layout.measure(m, e) > w) ok = false;
            if (e.len == 0 or e.ptr == name.ptr) continue;
            const k = std.mem.indexOf(u8, e, layout.ELLIPSIS) orelse {
                ok = false;
                continue;
            };
            const head = e[0..k];
            const tail = e[k + layout.ELLIPSIS.len ..];
            if (!std.mem.startsWith(u8, name, head) or !std.mem.endsWith(u8, name, tail)) ok = false;
            // 머리 끝 · 꼬리 처음이 클러스터 경계다(NFD 음절을 가르지 않는다).
            const st = try layout.stops(m, name, &sc);
            var hb = false;
            var tb = false;
            for (st) |x| {
                if (x.byte == head.len) hb = true;
                if (x.byte == name.len - tail.len) tb = true;
            }
            ok = ok and hb and tb;
            // 꼬리 기울기: 수는 꼬리가 먼저 는다. 넓은 클러스터(20)가 꼬리를 막으면 남은 폭을 머리가 한두 개 더 채운다.
            if (clusterCount(head) > clusterCount(tail) + 2) ok = false;
        }
        check(ok, "elide over every width: result <= width, head/tail are a prefix/suffix cut at cluster boundaries (NFD kept whole), the head is at most 2 clusters longer than the tail", .{});
        // 실제 글꼴(13 px): 판정 19의 긴 이름.
        const fm2 = face.metrics();
        const long = "long-directory-name-0123456789-abcdefghij-end";
        const e = try layout.elideMiddle(fm2, long, 150, &sc, &buf);
        check(layout.measure(fm2, e) <= 150 and std.mem.indexOf(u8, e, layout.ELLIPSIS) != null and std.mem.endsWith(u8, e, "-end"), "13 px {s} in 150 px -> {s} ({d:.2} px)", .{ long, e, layout.measure(fm2, e) });
    }

    // 줄 나누기.
    {
        var sc: [64]layout.Stop = undefined;
        var ln: [16]layout.Line = undefined;
        const Case = struct { s: []const u8, w: f32, want: []const []const u8, label: ?[]const u8 = null };
        const cases = [_]Case{
            .{ .s = "hello world foo", .w = 60, .want = &.{ "hello", "world", "foo" } },
            .{ .s = "hello world foo", .w = 115, .want = &.{ "hello world", "foo" } },
            .{ .s = "가나다라마", .w = 50, .want = &.{ "가나", "다라", "마" } },
            .{ .s = "abcdefghij", .w = 35, .want = &.{ "abc", "def", "ghi", "j" } },
            .{ .s = "가나다.", .w = 60, .want = &.{ "가나", "다." } },
            .{ .s = "가(나다", .w = 40, .want = &.{ "가", "(나", "다" } },
            .{ .s = "ab  cd", .w = 30, .want = &.{ "ab", "cd" } },
            .{ .s = "a\nb", .w = 100, .want = &.{ "a", "b" }, .label = "a<LF>b" },
            .{ .s = "a\n", .w = 100, .want = &.{ "a", "" }, .label = "a<LF>" },
            .{ .s = "", .w = 100, .want = &.{""} },
            .{ .s = "한글 text", .w = 60, .want = &.{ "한글", "text" } },
            .{ .s = "x", .w = 1, .want = &.{"x"} },
        };
        for (cases) |cs| {
            const lines = try layout.wrap(m, cs.s, cs.w, &sc, &ln);
            var ok = lines.len == cs.want.len;
            if (ok) for (lines, cs.want) |l, wnt| {
                ok = ok and std.mem.eql(u8, cs.s[l.start..l.end], wnt);
            };
            check(ok, "wrap \"{s}\" in {d}: {d} line(s)", .{ cs.label orelse cs.s, cs.w, lines.len });
        }
    }

    // 실제 글꼴: measure = 그리기의 끝 펜, NFD = NFC의 픽셀, 대체 □, 생략한 긴 이름 행의 부분 = 통째.
    {
        const samples = [_][]const u8{ "안녕", "long-directory-name", "AVAWAY", "\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}", "\u{6F22}\xffé", "e\u{301}" };
        var pixels: [W * H]u32 = undefined;
        var scratch: [W * H]u32 = undefined;
        var all = true;
        for (samples) |sm| {
            var p = Painter.begin(io, alloc, &pixels, W, H, &scratch, WHOLE, lut);
            p.fillRect(WHOLE, theme.TK_BG, 255);
            const end = try p.drawGlyphs(face, 3.25, 40, sm, theme.TK_TEXT, 255);
            p.finish();
            all = all and @abs(end - 3.25 - face.measure(sm)) < 0.001;
        }
        check(all, "Pretendard 13 px: drawGlyphs' end pen = x + measure for {d} samples", .{samples.len});
        // 참고(판정 아님 — plan 실측 1, 판정 19의 좌표): 13 px advance와 tars-files 열(200)의 이름 칸.
        {
            const chev = @round(200 - (kit.list.BAR_W + 4) - face.measure("\u{203A}"));
            const dir_w = chev - 4 - 16;
            const file_w: f32 = 200 - (kit.list.BAR_W + 4) - 16;
            var sc2: [64]layout.Stop = undefined;
            var b1: [128]u8 = undefined;
            var b2: [128]u8 = undefined;
            const dn = try layout.elideMiddle(face.metrics(), "long-directory-name-0123456789-abcdefghij-end", dir_w, &sc2, &b1);
            const fnm = try layout.elideMiddle(face.metrics(), "long-file-name-0123456789-abcdefghij-tail.txt", file_w, &sc2, &b2);
            std.debug.print("tk_test: reference 13 px advance … {d:.3} › {d:.3} □ {d:.3} ? {d:.3} U+0301 {d:.3} .notdef(漢) {d:.3}\n", .{ face.advance(0x2026), face.advance(0x203A), face.advance(0x25A1), face.advance('?'), face.advance(0x301), face.advance(0x6F22) });
            std.debug.print("tk_test: reference files column 200: › pen x {d} · dir name width {d} -> {s} ({d:.2}) · file name width {d} -> {s} ({d:.2})\n", .{ chev, dir_w, dn, face.measure(dn), file_w, fnm, face.measure(fnm) });
            const nd = try face.get(0x6F22, 0);
            var nd_ink: u32 = 0;
            for (nd.pixels) |v| nd_ink += @intFromBool(v != 0);
            std.debug.print("tk_test: reference .notdef bitmap {d}x{d} inked {d} (drawn only when □ is missing too)\n", .{ nd.width, nd.height, nd_ink });
        }
        check(face.hasGlyph(0x2026) and face.hasGlyph(0x203A) and face.hasGlyph(0x25A1) and !face.hasGlyph(0x1100) and !face.hasGlyph(0xFFFD) and !face.hasGlyph(0x6F22), "Pretendard has … › □, not U+1100 U+FFFD 漢", .{});
        var a: [W * H]u32 = undefined;
        var b: [W * H]u32 = undefined;
        {
            var p = Painter.begin(io, alloc, &a, W, H, &scratch, WHOLE, lut);
            p.fillRect(WHOLE, theme.TK_BG, 255);
            _ = try p.drawGlyphs(face, 10, 40, "한글", theme.TK_TEXT, 255);
            p.finish();
        }
        {
            var p = Painter.begin(io, alloc, &b, W, H, &scratch, WHOLE, lut);
            p.fillRect(WHOLE, theme.TK_BG, 255);
            _ = try p.drawGlyphs(face, 10, 40, "\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}", theme.TK_TEXT, 255);
            p.finish();
        }
        check(std.mem.eql(u32, &a, &b), "NFD 한글 draws the same pixels as NFC 한글", .{});
        // 생략한 긴 이름: 통째 그림과, 가운데를 가로지르는 부분 clip 그림이 clip 안에서 바이트까지 같다.
        var sc: [64]layout.Stop = undefined;
        var buf: [128]u8 = undefined;
        const shown = try layout.elideMiddle(face.metrics(), "long-directory-name-0123456789-abcdefghij-end", 150, &sc, &buf);
        {
            var p = Painter.begin(io, alloc, &a, W, H, &scratch, WHOLE, lut);
            p.fillRect(WHOLE, theme.TK_BG, 255);
            _ = try p.drawGlyphs(face, 16, 40, shown, theme.TK_TEXT, 255);
            p.finish();
        }
        const clip: Rect = .{ .x = 60, .y = 25, .w = 47, .h = 21 };
        @memset(&b, 0xFF000000);
        {
            var p = Painter.begin(io, alloc, &b, W, H, &scratch, clip, lut);
            p.fillRect(WHOLE, theme.TK_BG, 255);
            _ = try p.drawGlyphs(face, 16, 40, shown, theme.TK_TEXT, 255);
            p.finish();
        }
        var same = true;
        var inked = false;
        var yy: u32 = 25;
        while (yy < 46) : (yy += 1) {
            var xx: u32 = 60;
            while (xx < 107) : (xx += 1) {
                same = same and a[yy * W + xx] == b[yy * W + xx];
                inked = inked or (a[yy * W + xx] & 0xFFFFFF) != theme.TK_BG;
            }
        }
        check(same and inked, "elided long name: a partial clip 47x21 across its middle = the whole drawing (inked {})", .{inked});
    }
}

/// 서버 키맵의 keysym 이름 → 문자(글자 키 표에 나오는 것만). 나머지 이름은 글자가 아니다(0).
fn keysymChar(name: []const u8) u8 {
    if (name.len == 1) return name[0];
    const T = struct { n: []const u8, c: u8 };
    const table = [_]T{
        .{ .n = "exclam", .c = '!' },       .{ .n = "at", .c = '@' },          .{ .n = "numbersign", .c = '#' },  .{ .n = "dollar", .c = '$' },
        .{ .n = "percent", .c = '%' },      .{ .n = "asciicircum", .c = '^' }, .{ .n = "ampersand", .c = '&' },   .{ .n = "asterisk", .c = '*' },
        .{ .n = "parenleft", .c = '(' },    .{ .n = "parenright", .c = ')' },  .{ .n = "minus", .c = '-' },       .{ .n = "underscore", .c = '_' },
        .{ .n = "equal", .c = '=' },        .{ .n = "plus", .c = '+' },        .{ .n = "bracketleft", .c = '[' }, .{ .n = "braceleft", .c = '{' },
        .{ .n = "bracketright", .c = ']' }, .{ .n = "braceright", .c = '}' },  .{ .n = "semicolon", .c = ';' },   .{ .n = "colon", .c = ':' },
        .{ .n = "apostrophe", .c = '\'' },  .{ .n = "quotedbl", .c = '"' },    .{ .n = "grave", .c = '`' },       .{ .n = "asciitilde", .c = '~' },
        .{ .n = "backslash", .c = '\\' },   .{ .n = "bar", .c = '|' },         .{ .n = "comma", .c = ',' },       .{ .n = "less", .c = '<' },
        .{ .n = "period", .c = '.' },       .{ .n = "greater", .c = '>' },     .{ .n = "slash", .c = '/' },       .{ .n = "question", .c = '?' },
        .{ .n = "space", .c = ' ' },
    };
    for (table) |t| if (std.mem.eql(u8, t.n, name)) return t.c;
    return 0;
}

/// 서버 키맵(`terminal/vendor/keymap-us.xkb`)을 읽어 evdev 2..57의 (Shift 없음, Shift) 문자 표를 짓는다. keycodes 절의 `<NAME> = N;`(xkb 코드 =
/// evdev + 8)와 symbols 절의 `key <NAME> { [ a, b ] };`. 키패드(`<KP…>`)는 표에서 뺐다(NumLock 비트가 없다).
fn keymapTable() [58][2]u8 {
    const km = @embedFile("keymap");
    var codes: [58]?[]const u8 = @splat(null);
    var out: [58][2]u8 = @splat(.{ 0, 0 });
    const sym_at = std.mem.indexOf(u8, km, "xkb_symbols") orelse return out;
    var lines = std.mem.splitScalar(u8, km[0..sym_at], '\n');
    while (lines.next()) |raw| {
        const l = std.mem.trim(u8, raw, " \t");
        if (l.len < 3 or l[0] != '<') continue;
        const gt = std.mem.indexOfScalar(u8, l, '>') orelse continue;
        const eq = std.mem.indexOfScalar(u8, l, '=') orelse continue;
        const semi = std.mem.indexOfScalar(u8, l, ';') orelse continue;
        const v = std.fmt.parseInt(u32, std.mem.trim(u8, l[eq + 1 .. semi], " \t"), 10) catch continue;
        if (v < 8 or v - 8 >= 58) continue;
        if (codes[v - 8] == null) codes[v - 8] = l[1..gt];
    }
    var sl = std.mem.splitScalar(u8, km[sym_at..], '\n');
    while (sl.next()) |raw| {
        const l = std.mem.trim(u8, raw, " \t");
        if (!std.mem.startsWith(u8, l, "key <")) continue;
        const gt = std.mem.indexOfScalar(u8, l, '>') orelse continue;
        const name = l[5..gt];
        if (std.mem.startsWith(u8, name, "KP")) continue;
        const ob = std.mem.indexOfScalar(u8, l, '[') orelse continue;
        const cb = std.mem.indexOfScalar(u8, l, ']') orelse continue;
        for (codes, 0..) |cn, code| {
            const n = cn orelse continue;
            if (!std.mem.eql(u8, n, name)) continue;
            var parts = std.mem.splitScalar(u8, l[ob + 1 .. cb], ',');
            const a = keysymChar(std.mem.trim(u8, parts.next() orelse "", " \t"));
            const b = keysymChar(std.mem.trim(u8, parts.next() orelse "", " \t"));
            out[code] = .{ a, if (b == 0) a else b };
        }
    }
    return out;
}

fn keyCharTests() void {
    const km = keymapTable();
    var same = true;
    var letters: u32 = 0;
    for (km, 0..) |pair, code| {
        if (!std.mem.eql(u8, &pair, &input.US_CHARS[code])) {
            same = false;
            std.debug.print("tk_test: keymap code {d}: server {any} vs table {any}\n", .{ code, pair, input.US_CHARS[code] });
        }
        if (pair[0] != 0) letters += 1;
    }
    check(same and letters == 48, "the glyph key table = the server keymap (keymap-us.xkb) for evdev 2..57: {d} printing keys", .{letters});
    const none: input.Mods = .{};
    const sh: input.Mods = .{ .shift = true };
    const cp: input.Mods = .{ .caps = true };
    const shcp: input.Mods = .{ .shift = true, .caps = true };
    check(input.charFor(30, none) == 'a' and input.charFor(30, sh) == 'A' and input.charFor(30, cp) == 'A' and input.charFor(30, shcp) == 'a', "a: none a, Shift A, Caps A, Shift+Caps a (ALPHABETIC)", .{});
    check(input.charFor(2, none) == '1' and input.charFor(2, sh) == '!' and input.charFor(2, cp) == '1' and input.charFor(2, shcp) == '!', "1: Caps does not touch digits (1 ! 1 !)", .{});
    check(input.charFor(53, sh) == '?' and input.charFor(57, sh) == ' ' and input.charFor(40, none) == '\'', "/ with Shift is ?, Space is space, ' is '", .{});
    check(input.charFor(30, .{ .ctrl = true }) == null and input.charFor(30, .{ .alt = true }) == null and input.charFor(30, .{ .super = true }) == null, "Ctrl/Alt/Super+a are commands, not text", .{});
    check(input.charFor(14, none) == null and input.charFor(28, none) == null and input.charFor(15, none) == null and input.charFor(1, none) == null and input.charFor(55, none) == null and input.charFor(103, none) == null, "Backspace Enter Tab Esc KP* Up give no text", .{});
    check(input.keyFromCode(14) == .backspace and input.keyFromCode(111) == .delete and input.repeats(14) and input.repeats(111), "evdev 14 backspace, 111 delete, both repeat", .{});
}

// ── 16 텍스트 필드 · text-input · 클립보드 · 경로 바(TK-M4 단계 B) ───────────────

const TF = kit.textfield;
const ImeSm = @import("window/ime.zig").Ime;
const clipm = @import("window/clip.zig");

fn mtext(m: *const TF.Model) []const u8 {
    return m.text();
}

fn fieldModelTests() void {
    var m: TF.Model = .{};
    m.setText("/tmp/tkf");
    check(std.mem.eql(u8, m.text(), "/tmp/tkf") and m.caret == 8 and m.anchor == 8 and !m.has_undo, "setText: caret at the end, no selection, no undo", .{});
    m.insert("/");
    m.insert("a");
    check(std.mem.eql(u8, m.text(), "/tmp/tkf/a") and m.caret == 10, "typing inserts at the caret", .{});
    _ = m.undo();
    check(std.mem.eql(u8, m.text(), "/tmp/tkf") and m.caret == 8, "Cmd+Z undoes the whole typing run (one group)", .{});
    _ = m.undo();
    check(std.mem.eql(u8, m.text(), "/tmp/tkf/a") and m.caret == 10, "Cmd+Z again redoes it (swap)", .{});
    m.step(false, false, false);
    m.step(false, false, true);
    check(m.caret == 8 and m.anchor == 9 and std.mem.eql(u8, m.selected(), "/"), "<- then Shift+<- selects one cluster back", .{});
    m.step(true, false, false);
    check(m.caret == 9 and m.selection() == null, "-> with a selection collapses to its end", .{});
    m.moveTo(0, false);
    m.step(true, true, false);
    check(m.caret == 4, "Opt+-> from 0 skips '/' then the word tmp (caret 4)", .{});
    m.step(true, true, false);
    check(m.caret == 8, "Opt+-> again: tkf (caret 8)", .{});
    m.moveTo(m.len, false);
    m.step(false, true, false);
    check(m.caret == 9, "Opt+<- from the end: the word a starts at 9", .{});
    m.moveTo(m.len, false);
    m.backspace(true);
    check(std.mem.eql(u8, m.text(), "/tmp/tkf/"), "Opt+Backspace deletes the word before the caret", .{});
    m.backspace(false);
    m.backspace(false);
    check(std.mem.eql(u8, m.text(), "/tmp/tk"), "Backspace twice", .{});
    _ = m.undo();
    check(std.mem.eql(u8, m.text(), "/tmp/tkf/a"), "the deletes (word + two) are one group: undo restores /tmp/tkf/a", .{});
    // 한글 · NFD 클러스터: Backspace 하나가 클러스터 하나.
    m.setText("가\u{1112}\u{1161}\u{11AB}");
    m.backspace(false);
    check(std.mem.eql(u8, m.text(), "가"), "Backspace removes an NFD syllable (9 bytes) as one cluster", .{});
    m.moveTo(0, false);
    m.deleteForward();
    check(m.len == 0, "Delete removes 가", .{});
    // 전체 선택 · 바꾸기 · 붙여넣기 첫 줄.
    m.setText("abc");
    m.selectAll();
    check(std.mem.eql(u8, m.selected(), "abc"), "Cmd+A selects all", .{});
    m.insert("x");
    check(std.mem.eql(u8, m.text(), "x"), "typing over a selection replaces it", .{});
    m.selectAll();
    m.paste("/one\nsecond line");
    check(std.mem.eql(u8, m.text(), "/one") and m.caret == 4, "paste keeps the first line and replaces the selection", .{});
    check(std.mem.eql(u8, TF.firstLine("a\r\nb"), "a") and std.mem.eql(u8, TF.firstLine("ab"), "ab"), "firstLine cuts at CR or LF", .{});
    m.selectAll();
    m.deleteSelection();
    check(m.len == 0, "cut (delete selection) leaves nothing", .{});
    // IME(text-input-v3 순서).
    m.setText("/tmp/tkf/");
    m.ime("", "ㅎ");
    check(std.mem.eql(u8, m.text(), "/tmp/tkf/") and std.mem.eql(u8, m.preedit(), "ㅎ"), "a preedit does not touch the buffer", .{});
    m.ime("", "한");
    m.ime("한", "ㄱ");
    check(std.mem.eql(u8, m.text(), "/tmp/tkf/한") and std.mem.eql(u8, m.preedit(), "ㄱ") and m.caret == m.len, "one done with commit 한 + preedit ㄱ: 한 in the buffer, ㄱ composing", .{});
    m.ime("ㄱ", "");
    check(std.mem.eql(u8, m.text(), "/tmp/tkf/한ㄱ") and m.pre_len == 0, "commit ㄱ with an empty preedit ends the composition", .{});
    m.selectAll();
    m.ime("", "ㅁ");
    check(m.len == 0 and std.mem.eql(u8, m.preedit(), "ㅁ"), "the first preedit over a selection deletes the selection", .{});
    check(m.commitPreedit() and std.mem.eql(u8, m.text(), "ㅁ") and m.pre_len == 0 and !m.commitPreedit(), "losing the focus commits the preedit into the body (once)", .{});
    // 넘침: 4096에서 자른다(클러스터 경계).
    var big: [TF.MAX_TEXT + 10]u8 = undefined;
    @memset(&big, 'a');
    m.setText(&big);
    check(m.len == TF.MAX_TEXT, "setText cuts at 4096 bytes", .{});
    m.moveTo(TF.MAX_TEXT - 1, false);
    m.insert("한");
    check(m.len == TF.MAX_TEXT, "a full buffer takes nothing (no half code point)", .{});
    // 가로 스크롤: 캐럿이 보이게 최소만.
    check(TF.TextField.scrollFor(0, 50, 300, 100) == 0 and TF.TextField.scrollFor(0, 150, 300, 100) == 51 and TF.TextField.scrollFor(60, 20, 300, 100) == 20 and TF.TextField.scrollFor(200, 80, 80, 100) == 0, "scrollFor: stays, follows right (51), follows left (20), clamps when the text shrinks", .{});
}

fn imeTests() void {
    var s: ImeSm = .{};
    check(s.setWant(true) == null and s.want, "want before enter: nothing to send yet", .{});
    check(s.enter().? == true, "enter while wanted: enable", .{});
    s.sent();
    check(s.setWant(true) == null, "the same want again: nothing", .{});
    s.preedit("한");
    const d1 = s.done(1);
    check(std.mem.eql(u8, d1.preedit, "한") and d1.commit.len == 0 and d1.match, "done(1) after one commit: preedit 한, match", .{});
    s.commitString("한");
    s.preedit("ㄱ");
    const d2 = s.done(1);
    check(std.mem.eql(u8, d2.commit, "한") and std.mem.eql(u8, d2.preedit, "ㄱ"), "commit + preedit in one done", .{});
    const d3 = s.done(1);
    check(d3.commit.len == 0 and d3.preedit.len == 0, "done resets the pending (empty strings)", .{});
    check(s.setWant(false).? == false, "want off while entered: disable", .{});
    s.sent();
    const d4 = s.done(1);
    check(!d4.match and d4.serial == 1 and s.commits == 2, "a stale serial still applies, match 0", .{});
    s.preedit("x");
    s.leave();
    check(s.setWant(true) == null and s.pre_len == 0, "after leave: pending dropped, want is held until the next enter", .{});
    check(s.enter().? == true, "the next enter enables again (the server resets on enter)", .{});
    s.sent();
    var s2: ImeSm = .{};
    check(s2.enter() == null, "enter while not wanted: nothing (the server starts disabled)", .{});
    var round: u32 = 0;
    var ok = true;
    while (round < 100) : (round += 1) {
        if (s2.setWant(round % 2 == 0)) |_| s2.sent();
        ok = ok and s2.done(s2.commits).match;
    }
    check(ok and s2.commits == 100, "100 enable/disable rounds: every done(commits) matches", .{});
}

fn clipTests() void {
    check(clipm.pick(clipm.bit("TEXT") | clipm.bit("text/plain")).?.ptr == clipm.MIMES[1].ptr, "pick prefers text/plain over TEXT", .{});
    check(std.mem.eql(u8, clipm.pick(0xF).?, "text/plain;charset=utf-8") and clipm.pick(0) == null and clipm.bit("image/png") == 0, "pick: utf-8 first, nothing for none, unknown mimes ignored", .{});
    check(std.mem.eql(u8, clipm.pick(clipm.bit("UTF8_STRING")).?, "UTF8_STRING"), "pick UTF8_STRING alone", .{});
}

fn pathTests() void {
    var b: [4096]u8 = undefined;
    const Case = struct { t: []const u8, want: []const u8 };
    const cases = [_]Case{
        .{ .t = "/tmp/tkf/a/b", .want = "/tmp/tkf/a/b" },
        .{ .t = "/tmp//tkf/./a/", .want = "/tmp/tkf/a" },
        .{ .t = "/tmp/tkf/a/..", .want = "/tmp/tkf" },
        .{ .t = "/../..", .want = "/" },
        .{ .t = "a/b", .want = "/tmp/tkf/a/b" },
        .{ .t = "..", .want = "/tmp" },
        .{ .t = "~", .want = "/root" },
        .{ .t = "~/x/", .want = "/root/x" },
        .{ .t = "  /tmp  ", .want = "/tmp" },
        .{ .t = "/tmp/tkf/한", .want = "/tmp/tkf/한" },
    };
    var all = true;
    for (cases) |c| {
        const got = fm.resolvePath(&b, c.t, "/tmp/tkf", "/root") catch "ERR";
        if (!std.mem.eql(u8, got, c.want)) {
            all = false;
            std.debug.print("tk_test: resolvePath {s} -> {s} (want {s})\n", .{ c.t, got, c.want });
        }
    }
    check(all, "resolvePath: absolute · // · . · trailing / · .. · past the root · relative · ~ · spaces · Hangul ({d} cases)", .{cases.len});
    check(if (fm.resolvePath(&b, "  ", "/", null)) |_| false else |e| e == error.Empty, "an empty path is error.Empty", .{});
    check(if (fm.resolvePath(&b, "~", "/", null)) |_| false else |e| e == error.NoHome, "~ without HOME is error.NoHome", .{});
    var out: [32][]const u8 = undefined;
    const p1 = fm.columnPaths("/tmp/tkf", "/tmp/tkf/a/b", &out) catch &.{};
    check(p1.len == 3 and std.mem.eql(u8, p1[0], "/tmp/tkf") and std.mem.eql(u8, p1[1], "/tmp/tkf/a") and std.mem.eql(u8, p1[2], "/tmp/tkf/a/b"), "columnPaths inside the start: /tmp/tkf, /a, /a/b", .{});
    const p2 = fm.columnPaths("/tmp/tkf", "/tmp/tkf", &out) catch &.{};
    check(p2.len == 1 and std.mem.eql(u8, p2[0], "/tmp/tkf"), "columnPaths of the start itself: one column", .{});
    const p3 = fm.columnPaths("/tmp/tkf", "/usr/bin", &out) catch &.{};
    check(p3.len == 3 and std.mem.eql(u8, p3[0], "/") and std.mem.eql(u8, p3[1], "/usr") and std.mem.eql(u8, p3[2], "/usr/bin"), "columnPaths outside the start: from /", .{});
    const p4 = fm.columnPaths("/tmp/tkf", "/tmp/tkfx", &out) catch &.{};
    check(p4.len == 3 and std.mem.eql(u8, p4[0], "/"), "/tmp/tkfx is not inside /tmp/tkf (from /)", .{});
    const p5 = fm.columnPaths("/", "/tmp", &out) catch &.{};
    const p6 = fm.columnPaths("/x", "/", &out) catch &.{};
    check(p5.len == 2 and std.mem.eql(u8, p5[1], "/tmp") and p6.len == 1 and std.mem.eql(u8, p6[0], "/"), "columnPaths: start / -> /, /tmp; target / -> one column", .{});
    var deep_buf: [200]u8 = undefined;
    var n: usize = 0;
    for (0..40) |_| {
        deep_buf[n] = '/';
        deep_buf[n + 1] = 'd';
        n += 2;
    }
    check(if (fm.columnPaths("/", deep_buf[0..n], &out)) |_| false else |e| e == error.TooDeep, "41 columns is error.TooDeep (pool 32)", .{});
    check(std.mem.eql(u8, fm.basename("/tmp/tkf/a"), "a") and std.mem.eql(u8, fm.dirname("/tmp/tkf/a"), "/tmp/tkf") and std.mem.eql(u8, fm.dirname("/a"), "/"), "basename · dirname", .{});
}

/// 필드 하나와 루트(검사 판 W × H). ime 훅 · 클립보드 delegate를 센다.
const FieldEnv = struct {
    tree: ca.Tree,
    alloc: std.mem.Allocator,
    root_layer: *ca.Layer = undefined,
    root_view: kit.View = undefined,
    root: kit.Root = undefined,
    field: TF.TextField = undefined,
    other: kit.List = undefined,
    other_src: CountSource = undefined,
    face: ?text.Face = null,
    ime_on: bool = false,
    ime_calls: u32 = 0,
    copied: [64]u8 = undefined,
    copied_len: usize = 0,
    clip_text: []const u8 = "",
    actions: u32 = 0,
    last_action: TF.Action = .escape,

    fn init(self: *FieldEnv, alloc: std.mem.Allocator, font: []const u8, face13: *text.Face) !void {
        self.* = .{ .tree = ca.Tree.init(alloc), .alloc = alloc };
        self.face = try text.Face.init(alloc, font, 13);
        const t = &self.tree;
        self.root_layer = try t.create(.{ .frame = .{ .x = 0, .y = 0, .w = W, .h = H }, .background = theme.TK_BG });
        t.setRoot(self.root_layer);
        self.root_view = .{ .layer = self.root_layer, .vtable = &ROOT_VT, .ctx = self, .name = "root" };
        self.root = kit.Root.init(t);
        self.root.setView(&self.root_view);
        self.root.ime_hook = .{ .ctx = self, .on = onIme };
        try self.field.init(t, "field", &self.face);
        self.field.delegate = .{ .ctx = self, .action = onAction, .copy = onCopy, .paste = onPaste };
        self.field.view.layer.setFrame(.{ .x = 20, .y = 30, .w = 150, .h = 24 });
        try self.root_layer.addChild(self.field.view.layer);
        try self.root_view.addChild(alloc, &self.field.view);
        self.other_src = .{ .n = 3, .face = face13 };
        try self.other.init(t, "other", self.other_src.source(), 0);
        self.other.view.layer.setFrame(.{ .x = 0, .y = 70, .w = 200, .h = 50 });
        self.other.sync();
        try self.root_layer.addChild(self.other.view.layer);
        try self.root_view.addChild(alloc, &self.other.view);
        self.root.handle(.{ .focus = true });
        _ = t.takeDirty();
    }
    fn deinit(self: *FieldEnv) void {
        self.other.deinit(self.alloc);
        self.field.view.deinit(self.alloc);
        self.root_view.deinit(self.alloc);
        if (self.face) |*f| f.deinit();
        self.tree.deinit();
    }
    fn onIme(ctx: *anyopaque, on: bool) void {
        const self: *FieldEnv = @ptrCast(@alignCast(ctx));
        self.ime_on = on;
        self.ime_calls += 1;
    }
    fn onAction(ctx: *anyopaque, _: *TF.TextField, a: TF.Action) void {
        const self: *FieldEnv = @ptrCast(@alignCast(ctx));
        self.actions += 1;
        self.last_action = a;
    }
    fn onCopy(ctx: *anyopaque, bytes: []const u8) void {
        const self: *FieldEnv = @ptrCast(@alignCast(ctx));
        const n = @min(bytes.len, self.copied.len);
        @memcpy(self.copied[0..n], bytes[0..n]);
        self.copied_len = n;
    }
    fn onPaste(ctx: *anyopaque, buf: []u8) ?[]const u8 {
        const self: *FieldEnv = @ptrCast(@alignCast(ctx));
        @memcpy(buf[0..self.clip_text.len], self.clip_text);
        return buf[0..self.clip_text.len];
    }
    fn key(self: *FieldEnv, code: u32, mods: input.Mods) void {
        self.root.handle(keyEv(code, mods));
    }
    fn typeText(self: *FieldEnv, s: []const u8) void {
        for (s) |ch| {
            var code: u32 = 0;
            var shift = false;
            for (input.US_CHARS, 0..) |pair, i| {
                if (pair[0] == ch) {
                    code = @intCast(i);
                    break;
                }
                if (pair[1] == ch) {
                    code = @intCast(i);
                    shift = true;
                    break;
                }
            }
            self.key(code, .{ .shift = shift });
        }
    }
};

fn fieldTests(io: std.Io, alloc: std.mem.Allocator, font: []const u8, face13: *text.Face, lut: *const [256]u8) !void {
    var env: FieldEnv = undefined;
    try env.init(alloc, font, face13);
    defer env.deinit();
    const f = &env.field;
    check(!env.ime_on and env.ime_calls == 0, "no text input before the field has the focus", .{});
    _ = env.root.setFirstResponder(&f.view);
    check(env.ime_on and env.ime_calls == 1 and f.focused, "the field as first responder turns text input on (one hook call)", .{});
    f.setText("/tmp/tkf");
    env.typeText("/A b");
    check(std.mem.eql(u8, f.text(), "/tmp/tkf/A b"), "typed through the key table: Shift+a is A, space is a space ({s})", .{f.text()});
    env.key(input.KEY_BACKSPACE, .{});
    env.key(input.KEY_HOME, .{});
    env.key(input.KEY_RIGHT, .{ .shift = true });
    env.key(46, .{ .super = true });
    check(env.copied_len == 1 and env.copied[0] == '/', "Home, Shift+->, Cmd+C copies '/'", .{});
    env.key(30, .{ .super = true });
    env.key(45, .{ .super = true });
    check(f.text().len == 0 and env.copied_len == 11, "Cmd+A, Cmd+X cuts everything (11 bytes)", .{});
    env.clip_text = "/tmp/tkf/a\n";
    env.key(47, .{ .super = true });
    check(std.mem.eql(u8, f.text(), "/tmp/tkf/a"), "Cmd+V pastes the first line", .{});
    env.key(44, .{ .super = true });
    check(f.text().len == 0, "Cmd+Z undoes the paste", .{});
    env.key(44, .{ .super = true });
    env.key(30, .{ .ctrl = true });
    check(f.model.caret == 0 and std.mem.eql(u8, f.text(), "/tmp/tkf/a"), "Cmd+Z again redoes, Ctrl+A goes to the start (not select all)", .{});
    env.key(18, .{ .ctrl = true });
    check(f.model.caret == f.model.len, "Ctrl+E goes to the end", .{});
    env.key(input.KEY_ENTER, .{});
    check(env.actions == 1 and env.last_action == .enter, "Enter goes to the delegate", .{});
    env.key(input.KEY_ESC, .{});
    check(env.actions == 2 and env.last_action == .escape, "Esc goes to the delegate", .{});
    var un: KitLog = .{};
    env.root.unhandled = .{ .ctx = &un, .on = KitLog.onUnhandled };
    env.key(38, .{ .super = true });
    check(un.unhandled == 1, "Cmd+L is not the field's: it reaches unhandled", .{});
    // IME 이벤트: first responder에.
    f.setText("/tmp/tkf/");
    env.root.handle(.{ .ime = .{ .commit = "", .preedit = "한" } });
    check(std.mem.eql(u8, f.model.preedit(), "한") and std.mem.eql(u8, f.text(), "/tmp/tkf/"), "an ime event reaches the field: preedit 한", .{});

    // 그림: 밑줄 행 · 확정 뒤 · 캐럿 · 선택.
    const pixels = try alloc.alloc(u32, W * H);
    defer alloc.free(pixels);
    const ref = try alloc.alloc(u32, W * H);
    defer alloc.free(ref);
    const scratch = try alloc.alloc(u32, W * H);
    defer alloc.free(scratch);
    try render(io, alloc, &env.tree, pixels, scratch, WHOLE, lut);
    const face = &env.face.?;
    const base: i32 = 30 + @as(i32, @intFromFloat(@round((24 + face.ascent - face.descent) / 2)));
    const pad: f32 = 20 + 8;
    const pre_x0: u32 = @intFromFloat(@round(pad + face.measure("/tmp/tkf/")));
    const pre_x1: u32 = @intFromFloat(@round(pad + face.measure("/tmp/tkf/") + face.measure("한")));
    const uy: u32 = @intCast(base + 2);
    var under: u32 = 0;
    var x = pre_x0;
    while (x < pre_x1) : (x += 1) under += @intFromBool(px(pixels, x, uy) == theme.TK_TEXT);
    check(under == pre_x1 - pre_x0 and px(pixels, pre_x0, uy + 1) != theme.TK_TEXT, "preedit underline: row baseline+2 = {d}, x {d}..{d} all TK_TEXT, the row below is not", .{ uy, pre_x0, pre_x1 });
    std.debug.print("tk_test: reference field underline y={d} x={d}..{d} (field at 20,30 150x24, pad 8)\n", .{ uy, pre_x0, pre_x1 });
    env.root.handle(.{ .ime = .{ .commit = "한", .preedit = "" } });
    try render(io, alloc, &env.tree, pixels, scratch, WHOLE, lut);
    under = 0;
    x = pre_x0;
    while (x + 1 < pre_x1) : (x += 1) under += @intFromBool(px(pixels, x, uy) == theme.TK_TEXT);
    var ink: u32 = 0;
    var yy: u32 = @intCast(base - 12);
    while (yy < @as(u32, @intCast(base))) : (yy += 1) {
        x = pre_x0;
        while (x < pre_x1) : (x += 1) ink += @intFromBool(px(pixels, x, yy) != theme.TK_SURFACE);
    }
    check(std.mem.eql(u8, f.text(), "/tmp/tkf/한") and under < 3 and ink > 10, "after the commit: 한 in the body, no underline ({d} text pixels on the row — glyph only), glyph ink {d}", .{ under, ink });
    const caret_x: u32 = @intFromFloat(@round(pad + face.measure("/tmp/tkf/한")));
    check(px(pixels, caret_x, @intCast(base - 4)) == theme.TK_TEXT, "the caret (1 px TK_TEXT) at x {d}", .{caret_x});
    check(px(pixels, 60, 30) == theme.TK_ACCENT and px(pixels, 60, 31) == theme.TK_ACCENT and px(pixels, 60, 32) == theme.TK_SURFACE and px(pixels, 20, 42) == theme.TK_ACCENT, "focus ring: 2 px accent on the top edge (y 30 31), surface at y 32, accent on the left edge", .{});
    // 부분 = 통째: 필드 한 글자 입력의 더티만 다시 그린 판 = 새로 통째.
    _ = env.tree.takeDirty();
    env.typeText("x");
    const d = env.tree.takeDirty();
    check(d != null and Rect.eql(d.?, .{ .x = 20, .y = 30, .w = 150, .h = 24 }), "typing dirties only the field rectangle", .{});
    try render(io, alloc, &env.tree, pixels, scratch, d.?, lut);
    try render(io, alloc, &env.tree, ref, scratch, WHOLE, lut);
    check(std.mem.eql(u32, pixels, ref), "partial redraw of the field = whole", .{});
    // 선택 색 · 포커스를 잃으면 preedit을 본문에, text input 끔.
    env.key(30, .{ .super = true });
    try render(io, alloc, &env.tree, pixels, scratch, WHOLE, lut);
    check(px(pixels, @intFromFloat(@round(pad + 1)), @intCast(base - 2)) != theme.TK_SURFACE, "Cmd+A paints the selection behind the text", .{});
    env.key(input.KEY_END, .{});
    env.root.handle(.{ .ime = .{ .commit = "", .preedit = "ㄱ" } });
    _ = env.root.setFirstResponder(&env.other.view);
    check(std.mem.eql(u8, f.text(), "/tmp/tkf/한xㄱ") and f.model.pre_len == 0 and !env.ime_on and env.ime_calls == 2, "focus to the list: the preedit ㄱ goes into the body, text input off", .{});
    // 레이어를 숨기면 포커스를 못 받는다.
    f.view.layer.setHidden(true);
    check(!env.root.setFirstResponder(&f.view), "a hidden field does not take the focus", .{});
}

fn setColumnsTests(alloc: std.mem.Allocator, face: *text.Face) !void {
    var env: ColEnv = undefined;
    try env.init(alloc, face, false);
    defer env.deinit();
    const cv = &env.cv;
    env.key(input.KEY_RIGHT);
    env.key(input.KEY_RIGHT);
    env.src.cols[1] = .{ .kids = &TREE_A, .face = face };
    env.src.cols[2] = .{ .kids = &TREE_B, .face = face };
    const before = env.log.columns;
    try cv.setColumns(&.{ env.src.cols[0].source(), env.src.cols[1].source() });
    check(cv.n == 2 and cv.focus == 1 and cv.scroll == 0 and env.log.columns == before + 1, "setColumns(2) from 3 columns: n 2, focus 1, scroll 0, one columns event", .{});
    try cv.setColumns(&.{ env.src.cols[0].source(), env.src.cols[1].source(), env.src.cols[2].source() });
    check(cv.n == 3 and cv.focus == 2 and cv.scroll == 201, "setColumns(3): n 3, focus 2, scroll 201", .{});
    cv.focusFirst();
    check(std.mem.eql(u8, env.firstName(), "col2"), "focusFirst after setColumns: col2", .{});
    try cv.setColumns(&.{env.src.cols[0].source()});
    check(cv.n == 1 and cv.focus == 0 and cv.list(0).selected == 0, "setColumns(1): back to one column, selection 0", .{});
}

// ── 17 필터 · 검색(TK-M4 단계 C) ──────────────────────────────────────

/// 경로로 찾는 가짜 디렉터리 트리 — `dirs`의 경로마다 항목 목록. 조각은 `chunk`개씩. 모르는 경로는 못 연다.
const TDir = struct { path: []const u8, items: []const fm.Raw };
const TreeDir = struct {
    dirs: []const TDir,
    chunk: usize = 2,
    opens: u32 = 0,
    closes: u32 = 0,
    hs: [8]struct { items: []const fm.Raw, pos: usize } = undefined,
    hn: usize = 0,

    fn open(ctx: *anyopaque, path: []const u8) anyerror!*anyopaque {
        const self: *TreeDir = @ptrCast(@alignCast(ctx));
        for (self.dirs) |d| if (std.mem.eql(u8, d.path, path)) {
            self.opens += 1;
            const h = &self.hs[self.hn % self.hs.len];
            self.hn += 1;
            h.* = .{ .items = d.items, .pos = 0 };
            return h;
        };
        return error.FileNotFound;
    }
    fn next(ctx: *anyopaque, handle: *anyopaque) anyerror!?[]const fm.Raw {
        const self: *TreeDir = @ptrCast(@alignCast(ctx));
        const h: *@TypeOf(self.hs[0]) = @ptrCast(@alignCast(handle));
        if (h.pos >= h.items.len) return null;
        const end = @min(h.pos + self.chunk, h.items.len);
        defer h.pos = end;
        return h.items[h.pos..end];
    }
    fn close(ctx: *anyopaque, _: *anyopaque) void {
        const self: *TreeDir = @ptrCast(@alignCast(ctx));
        self.closes += 1;
    }
    fn source(self: *TreeDir) fm.DirSource {
        return .{ .ctx = self, .open = open, .next = next, .close = close };
    }
};

/// 뿌리 하나에 파일 `n`개(`f0` …)를 1000개씩 지어 주는 소스(20만 상한 · 네이티브 점수 재기).
const GenDir = struct {
    n: usize,
    pos: usize = 0,
    names: std.ArrayList(u8) = .empty,
    raws: [1000]fm.Raw = undefined,
    alloc: std.mem.Allocator,

    fn open(ctx: *anyopaque, path: []const u8) anyerror!*anyopaque {
        const self: *GenDir = @ptrCast(@alignCast(ctx));
        if (!std.mem.eql(u8, path, "/g")) return error.FileNotFound;
        self.pos = 0;
        return self;
    }
    fn next(ctx: *anyopaque, _: *anyopaque) anyerror!?[]const fm.Raw {
        const self: *GenDir = @ptrCast(@alignCast(ctx));
        if (self.pos >= self.n) return null;
        const end = @min(self.pos + self.raws.len, self.n);
        self.names.clearRetainingCapacity();
        var offs: [1001]usize = undefined;
        var k: usize = 0;
        while (self.pos + k < end) : (k += 1) {
            offs[k] = self.names.items.len;
            const i = self.pos + k;
            // 이름은 섞인 글자(질의가 고르게 맞도록) — f<i>-<i*7919 % 1000>.txt
            var b: [48]u8 = undefined;
            const nm = try std.fmt.bufPrint(&b, "f{d}-{d}.txt", .{ i, (i * 7919) % 1000 });
            try self.names.appendSlice(self.alloc, nm);
        }
        offs[k] = self.names.items.len;
        for (0..k) |j| self.raws[j] = .{ .name = self.names.items[offs[j]..offs[j + 1]], .kind = .file };
        self.pos = end;
        return self.raws[0..k];
    }
    fn close(_: *anyopaque, _: *anyopaque) void {}
    fn source(self: *GenDir) fm.DirSource {
        return .{ .ctx = self, .open = open, .next = next, .close = close };
    }
};

const FakeClock = struct {
    t: u64 = 0,
    step: u64 = 0,
    fn now(ctx: *anyopaque) u64 {
        const self: *FakeClock = @ptrCast(@alignCast(ctx));
        self.t += self.step;
        return self.t;
    }
    fn clock(self: *FakeClock) fsearch.Clock {
        return .{ .ctx = self, .now_ms = now };
    }
};

fn rd(name: []const u8, kind: fm.Kind) fm.Raw {
    return .{ .name = name, .kind = kind };
}

const TKF = [_]TDir{
    .{ .path = "/tmp/tkf", .items = &.{ rd("a", .dir), rd(".h", .file), rd("z", .dir), rd("한", .dir), rd("m.txt", .file), .{ .name = "loop", .kind = .dir, .link = true } } },
    .{ .path = "/tmp/tkf/a", .items = &.{ rd("0", .dir), rd("b", .dir) } },
    .{ .path = "/tmp/tkf/z", .items = &.{} },
    .{ .path = "/tmp/tkf/한", .items = &.{rd("x.txt", .file)} },
    .{ .path = "/tmp/tkf/a/0", .items = &.{} },
    .{ .path = "/tmp/tkf/a/b", .items = &.{ rd("c", .dir), rd("x.txt", .file) } },
    .{ .path = "/tmp/tkf/a/b/c", .items = &.{} },
    .{ .path = "/tmp/tkf/loop", .items = &.{rd("never", .file)} },
};

fn walkAll(w: *fsearch.Walker) u32 {
    var steps: u32 = 0;
    while (w.step()) steps += 1;
    return steps;
}

fn joinPaths(w: *const fsearch.Walker, buf: []u8) []const u8 {
    var n: usize = 0;
    for (0..w.items.items.len) |i| {
        const s = std.fmt.bufPrint(buf[n..], "{s}{s}", .{ if (i == 0) "" else " ", w.path(@intCast(i)) }) catch return buf[0..n];
        n += s.len;
    }
    return buf[0..n];
}

fn topPaths(sr: *const fsearch.Search, buf: []u8) []const u8 {
    var n: usize = 0;
    for (sr.results(), 0..) |h, i| {
        const s = std.fmt.bufPrint(buf[n..], "{s}{s}", .{ if (i == 0) "" else " ", sr.walker.path(h.item) }) catch return buf[0..n];
        n += s.len;
    }
    return buf[0..n];
}

fn searchTests(alloc: std.mem.Allocator) !void {
    var clk: FakeClock = .{ .step = 1 };
    var buf: [4096]u8 = undefined;
    // 걷기: 너비 우선 · 숨김 빠짐 · 링크는 항목이지만 내려가지 않음.
    {
        var src: TreeDir = .{ .dirs = &TKF };
        var w = fsearch.Walker.init(alloc, src.source(), clk.clock(), "/tmp/tkf");
        defer w.deinit();
        _ = walkAll(&w);
        const got = joinPaths(&w, &buf);
        check(std.mem.eql(u8, got, "a z 한 m.txt loop a/0 a/b 한/x.txt a/b/c a/b/x.txt") and w.done and !w.capped, "walk /tmp/tkf breadth first, .h hidden, the link listed but not entered: {s}", .{got});
        check(src.opens == 7 and src.opens == src.closes, "walk opened 7 directories (not loop) and closed each ({d}/{d})", .{ src.opens, src.closes });
        check(std.mem.eql(u8, w.name(9), "x.txt") and w.items.items[9].kind == .file, "the name of a/b/x.txt is x.txt", .{});
    }
    // 뿌리 `/`: 맨 위의 proc sys dev run만 뺀다.
    {
        const ROOT = [_]TDir{
            .{ .path = "/", .items = &.{ rd("proc", .dir), rd("sys", .dir), rd("dev", .dir), rd("run", .dir), rd("tmp", .dir), rd("etc", .file) } },
            .{ .path = "/tmp", .items = &.{ rd("proc", .dir), rd("run", .file) } },
            .{ .path = "/tmp/proc", .items = &.{} },
            .{ .path = "/proc", .items = &.{rd("1", .dir)} },
        };
        var src: TreeDir = .{ .dirs = &ROOT, .chunk = 100 };
        var w = fsearch.Walker.init(alloc, src.source(), clk.clock(), "/");
        defer w.deinit();
        _ = walkAll(&w);
        const got = joinPaths(&w, &buf);
        check(std.mem.eql(u8, got, "tmp etc tmp/proc tmp/run"), "walk / leaves out the top proc sys dev run only: {s}", .{got});
    }
    // 상한: 20만 항목 · 10초.
    {
        var g: GenDir = .{ .n = 250_000, .alloc = alloc };
        defer g.names.deinit(alloc);
        var c0: FakeClock = .{ .step = 0 };
        var w = fsearch.Walker.init(alloc, g.source(), c0.clock(), "/g");
        defer w.deinit();
        _ = walkAll(&w);
        check(w.capped and w.items.items.len == fsearch.MAX_ENTRIES, "250k entries: capped at {d}", .{w.items.items.len});
        var src: TreeDir = .{ .dirs = &TKF, .chunk = 1 };
        var c1: FakeClock = .{ .step = 1000 };
        var w2 = fsearch.Walker.init(alloc, src.source(), c1.clock(), "/tmp/tkf");
        defer w2.deinit();
        const steps = walkAll(&w2);
        check(w2.capped and w2.ms >= fsearch.MAX_MS and steps < 12, "a clock of 1 s per look stops the walk at 10 s ({d} steps, {d} ms)", .{ steps, w2.ms });
    }
    // 점수 순서.
    {
        const S = fsearch.score;
        check(S("abc", 0, "ab").? > S("axb", 0, "ab").?, "consecutive > scattered (abc vs axb for ab)", .{});
        check(S("a/xy", 2, "xy").? > S("xy/a", 3, "xy").?, "a name match > a path match (a/xy vs xy/a)", .{});
        check(S("xy", 0, "xy").? > S("xyz", 0, "xy").?, "the shorter path wins (xy vs xyz)", .{});
        check(S("q/bar", 2, "b").? > S("q/abr", 2, "b").?, "a match at a component start wins (q/bar vs q/abr for b)", .{});
        check(S("한/x.txt", 4, "한") != null and S("a", 0, "한") == null and S("README", 0, "read") != null and S("x", 0, "") == null, "Hangul as is, ASCII case folded, an empty query matches nothing", .{});
        check(S("a/b/x.txt", 4, "xtxt") != null and S("한/x.txt", 4, "xtxt") != null and S("m.txt", 0, "xtxt") == null, "xtxt is in a/b/x.txt and 한/x.txt, not m.txt", .{});
        check(S("a/b/x.txt", 4, "xtxt").? == S("한/x.txt", 4, "xtxt").?, "a/b/x.txt and 한/x.txt tie (both 9 bytes) — the byte order decides", .{});
    }
    // 검색 결과: 판정 25의 모양, 같은 점수는 경로 바이트 순.
    {
        var src: TreeDir = .{ .dirs = &TKF };
        const w = fsearch.Walker.init(alloc, src.source(), clk.clock(), "/tmp/tkf");
        var sr = fsearch.Search.init(alloc, w);
        defer sr.deinit();
        _ = walkAll(&sr.walker);
        try sr.scanNew();
        try sr.setQuery("xtxt");
        const got = topPaths(&sr, &buf);
        check(std.mem.eql(u8, got, "a/b/x.txt 한/x.txt"), "search xtxt in /tmp/tkf: {s}", .{got});
    }
    // 상위 100 = 전체 정렬의 앞 100, 질의 늘이기 = 처음부터, 걷는 중에 바꾼 질의.
    {
        var g: GenDir = .{ .n = 5000, .alloc = alloc };
        defer g.names.deinit(alloc);
        const w = fsearch.Walker.init(alloc, g.source(), clk.clock(), "/g");
        var inc = fsearch.Search.init(alloc, w);
        defer inc.deinit();
        try inc.setQuery("1");
        _ = inc.walker.step();
        try inc.scanNew();
        try inc.setQuery("12");
        _ = inc.walker.step();
        try inc.scanNew();
        try inc.setQuery("12t");
        while (inc.walker.step()) try inc.scanNew();
        try inc.scanNew();
        // 처음부터: 다 걷고 한 번에.
        const w2 = fsearch.Walker.init(alloc, g.source(), clk.clock(), "/g");
        var fresh = fsearch.Search.init(alloc, w2);
        defer fresh.deinit();
        while (fresh.walker.step()) {}
        try fresh.setQuery("12t");
        var same = inc.top_n == fresh.top_n;
        if (same) for (inc.results(), fresh.results()) |a, b| {
            same = same and std.mem.eql(u8, inc.walker.path(a.item), fresh.walker.path(b.item)) and a.score == b.score;
        };
        check(same and fresh.top_n == fsearch.TOP, "query 1 -> 12 -> 12t while walking = 12t from scratch after the walk ({d} results)", .{fresh.top_n});
        // 전체 정렬(점수 내림 · 경로 오름)의 앞 100.
        var all: std.ArrayList(fsearch.Hit) = .empty;
        defer all.deinit(alloc);
        for (0..fresh.walker.items.items.len) |i| {
            const it = fresh.walker.items.items[i];
            if (fsearch.score(fresh.walker.path(@intCast(i)), it.name, "12t")) |s| try all.append(alloc, .{ .item = @intCast(i), .score = s });
        }
        const Ctx = struct {
            w: *const fsearch.Walker,
            fn lt(c: @This(), a: fsearch.Hit, b: fsearch.Hit) bool {
                if (a.score != b.score) return a.score > b.score;
                return std.mem.order(u8, c.w.path(a.item), c.w.path(b.item)) == .lt;
            }
        };
        std.mem.sort(fsearch.Hit, all.items, Ctx{ .w = &fresh.walker }, Ctx.lt);
        var eq = all.items.len >= fsearch.TOP;
        if (eq) for (fresh.results(), all.items[0..fsearch.TOP]) |a, b| {
            eq = eq and a.item == b.item;
        };
        check(eq, "top 100 = the first 100 of a full sort ({d} candidates)", .{all.items.len});
        // 이어지지 않는 질의(줄임)도 처음부터와 같다.
        try inc.setQuery("1");
        try fresh.setQuery("1");
        var same2 = inc.top_n == fresh.top_n;
        if (same2) for (inc.results(), fresh.results()) |a, b| {
            same2 = same2 and std.mem.eql(u8, inc.walker.path(a.item), fresh.walker.path(b.item));
        };
        check(same2, "a shorter query re-reads everything (same as from scratch)", .{});
    }
    // 네이티브 재기(참고 — 판정 아님, plan 실측 7): 20만 가짜 항목의 걷기 · 점수 매기기.
    {
        var g: GenDir = .{ .n = 200_000, .alloc = alloc };
        defer g.names.deinit(alloc);
        const w = fsearch.Walker.init(alloc, g.source(), clk.clock(), "/g");
        var sr = fsearch.Search.init(alloc, w);
        defer sr.deinit();
        const t0 = nowUs();
        while (sr.walker.step()) {}
        const t1 = nowUs();
        try sr.setQuery("1");
        const t2 = nowUs();
        const n1 = sr.cands.items.len;
        try sr.setQuery("12");
        const t3 = nowUs();
        const n2 = sr.cands.items.len;
        try sr.setQuery("12t");
        const t4 = nowUs();
        const n3 = sr.cands.items.len;
        try sr.setQuery("x9");
        const t5 = nowUs();
        std.debug.print("tk_test: reference native (host test build mode) 200k fake entries: walk {d} us, score '1' {d} us ({d} cands), '12' (extends) {d} us ({d}), '12t' {d} us ({d}), 'x9' (not extending, all again) {d} us ({d})\n", .{ t1 - t0, t2 - t1, n1, t3 - t2, n2, t4 - t3, n3, t5 - t4, sr.cands.items.len });
    }
}

fn nowUs() u64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000 + @as(u64, @intCast(ts.nsec)) / 1000;
}

fn filterTests(alloc: std.mem.Allocator) !void {
    check(fm.nameMatches("m.txt", "m") and fm.nameMatches("README.md", "readme") and !fm.nameMatches("a", "m") and fm.nameMatches("x", "") and fm.nameMatches("한글", "글") and !fm.nameMatches("ab", "abc"), "nameMatches: substring, ASCII case folded, Hangul bytes, empty matches all", .{});
    const items = [_]fm.Entry{ ent("a", .dir), ent("z", .dir), ent("한", .dir), ent("m.txt", .file) };
    var out: std.ArrayList(fm.Entry) = .empty;
    defer out.deinit(alloc);
    try fm.filterInto(alloc, &items, "m", &out);
    check(out.items.len == 1 and std.mem.eql(u8, out.items[0].name, "m.txt"), "filter m over a z 한 m.txt: m.txt", .{});
    // 안정 선택: a를 고른 채 거르면 a가 사라져 0행(m.txt), 풀면 이름으로 m.txt를 따라간다.
    const b0: fm.Before = .{ .sel = items[0], .index = 0, .offset = 0, .touched = true };
    const a1 = fm.follow(b0, out.items, 600, 24);
    check(a1.index.? == 0 and a1.gone, "filtering out the selection a: row 0 and gone (the right columns go)", .{});
    const b1: fm.Before = .{ .sel = out.items[0], .index = 0, .offset = 0, .touched = true };
    try fm.filterInto(alloc, &items, "", &out);
    const a2 = fm.follow(b1, out.items, 600, 24);
    check(a2.index.? == 3 and !a2.gone, "clearing the filter: the selection follows m.txt to row 3", .{});
    // 갱신 뒤 필터 유지: 새 목록(mm 더함)을 같은 글로 다시 거르면 선택 이름을 따라간다.
    const items2 = [_]fm.Entry{ ent("a", .dir), ent("z", .dir), ent("한", .dir), ent("m.txt", .file), ent("mm", .file) };
    try fm.filterInto(alloc, &items, "m", &out);
    const sel = out.items[0];
    var out2: std.ArrayList(fm.Entry) = .empty;
    defer out2.deinit(alloc);
    try fm.filterInto(alloc, &items2, "m", &out2);
    const a3 = fm.follow(.{ .sel = sel, .index = 0, .offset = 0, .touched = true }, out2.items, 600, 24);
    check(out2.items.len == 2 and a3.index.? == 0 and std.mem.eql(u8, out2.items[a3.index.?].name, "m.txt"), "a refresh with the filter kept: 2 rows, the selection stays on m.txt", .{});
}
