const std = @import("std");
const mb = @import("menubar.zig");
const theme = @import("theme");

// TK-M5: 메뉴 바의 순수한 셈(plan 확정 3 · 4 · 5 · 6)을 호스트에서 본다. 화면에 닿는 것은 wayland 체인이 본다(단계 B · C).
// 화면은 QEMU(게이트) 1280 × 800, 바의 왼쪽 끝은 `grid_origin.x` = 20이다.

var failures: u32 = 0;

fn check(ok: bool, comptime fmt: []const u8, args: anytype) void {
    if (ok) return;
    failures += 1;
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
}

/// 가짜 글꼴 — U+1100 아래는 1칸, 그 위(한글 등)는 2칸. terminal의 unifont가 라틴 8 px · 한글 16 px인 것과 같은 꼴이다.
fn fakeCells(_: *const anyopaque, cp: u21) u8 {
    return if (cp < 0x1100) 1 else 2;
}
const W: mb.Widths = .{ .ctx = undefined, .cellsOf = fakeCells };

const SCREEN_W = 1280;
const SCREEN_H = 800;

/// `tars-wl-test --menu`가 보내는 모델(plan 확정 13): File[Open Cmd+O, 구분선, Quit 비활성], Edit[Copy Cmd+C, 한글].
fn testModel() !mb.Model {
    var m: mb.Model = .{};
    try m.addMenu("File");
    try m.addItem(1, "Open", mb.MOD_SUPER, 24, 0);
    try m.addSeparator();
    try m.addItem(2, "Quit", 0, 0, mb.FLAG_DISABLED);
    try m.addMenu("Edit");
    try m.addItem(3, "Copy", mb.MOD_SUPER, 46, 0);
    try m.addItem(4, "한글", 0, 0, 0);
    return m;
}

// ── 1 모델 검증 · 상한 ───────────────────────────────────────────────

fn model() !void {
    const m = try testModel();
    check(m.menu_count == 2 and m.entry_count == 5, "model: 2 menus, 5 entries (got {d}, {d})", .{ m.menu_count, m.entry_count });
    check(m.entriesOf(0).len == 3 and m.entriesOf(1).len == 2, "model: File has 3, Edit has 2", .{});
    check(!m.entriesOf(0)[1].pickable() and !m.entriesOf(0)[2].pickable() and m.entriesOf(1)[1].pickable(), "model: separator and disabled are not pickable", .{});

    var e: mb.Model = .{};
    check(e.addItem(1, "a", 0, 0, 0) == error.NoMenu, "limits: an item before any menu is NoMenu", .{});
    check(e.addSeparator() == error.NoMenu, "limits: a separator before any menu is NoMenu", .{});
    const x65: [65]u8 = @splat('x');
    check(e.addMenu(&x65) == error.TooLong, "limits: a 65-byte title is TooLong", .{});
    try e.addMenu(x65[0..64]);
    check(e.addItem(1, "\xff\xfe", 0, 0, 0) == error.BadUtf8, "limits: a non-UTF-8 label is BadUtf8", .{});
    check(e.addItem(1, "가" ++ "\xea\xb0", 0, 0, 0) == error.BadUtf8, "limits: a cut UTF-8 label is BadUtf8", .{});
    var k: u32 = 0;
    while (k < mb.MAX_PER_MENU) : (k += 1) try e.addItem(k, "i", 0, 0, 0);
    check(e.addSeparator() == error.TooMany, "limits: entry 33 in one menu is TooMany", .{});
    // 전체 128: 메뉴 넷 × 32.
    var f: mb.Model = .{};
    var total: u32 = 0;
    for (0..4) |_| {
        try f.addMenu("m");
        for (0..32) |_| {
            try f.addItem(total, "i", 0, 0, 0);
            total += 1;
        }
    }
    try f.addMenu("fifth");
    check(f.addItem(0, "i", 0, 0, 0) == error.TooMany, "limits: entry 129 in all is TooMany", .{});
    var g: mb.Model = .{};
    for (0..mb.MAX_MENUS) |_| try g.addMenu("m");
    check(g.addMenu("ninth") == error.TooMany, "limits: menu 9 is TooMany", .{});
    g.clear();
    check(g.menu_count == 0 and g.entry_count == 0, "clear: empty again", .{});
    std.debug.print("menubar_test: model and limits\n", .{});
}

// ── 2 이름 ───────────────────────────────────────────────────────────

fn names() void {
    check(std.mem.eql(u8, mb.appName("org.chromium.Chromium", "New Tab"), "Chromium"), "appName: last piece of app_id", .{});
    check(std.mem.eql(u8, mb.appName("tars-files", "/tmp"), "tars-files"), "appName: app_id without dots", .{});
    check(std.mem.eql(u8, mb.appName("", "doom"), "doom"), "appName: title when app_id is empty", .{});
    check(std.mem.eql(u8, mb.appName("weird.", "t"), "weird."), "appName: app_id ending in a dot stays whole", .{});
    check(std.mem.eql(u8, mb.clampUtf8("abc", 64).?, "abc"), "clampUtf8: short stays", .{});
    check(mb.clampUtf8("a\xffb", 64) == null, "clampUtf8: not UTF-8 is dropped", .{});
    // "가나다" = 9바이트 — 4바이트에서 자르면 "가"(3)까지.
    check(std.mem.eql(u8, mb.clampUtf8("가나다", 4).?, "가"), "clampUtf8: cut at a character boundary", .{});
    check(std.mem.eql(u8, mb.clampUtf8("가나다", 6).?, "가나"), "clampUtf8: exact boundary", .{});
    std.debug.print("menubar_test: names\n", .{});
}

// ── 3 바 배치 ────────────────────────────────────────────────────────

fn bar() !void {
    const m = try testModel();
    const b = mb.layoutBar(W, 20, "tars-wl-test", &m, SCREEN_W);
    // 이름 12칸(20..116), 두 칸 띄고 File(132, 4칸), 두 칸 띄고 Edit(180).
    check(b.name_span.x == 20 and b.name_span.w == 96, "bar: name at 20, 96 px (got {d}, {d})", .{ b.name_span.x, b.name_span.w });
    check(b.count == 2, "bar: two titles (got {d})", .{b.count});
    check(b.titles[0].x == 132 and b.titles[0].w == 32, "bar: File at 132, 32 px (got {d}, {d})", .{ b.titles[0].x, b.titles[0].w });
    check(b.titles[1].x == 180 and b.titles[1].w == 32, "bar: Edit at 180 (got {d})", .{b.titles[1].x});
    const box0 = b.titleBox(0);
    const box1 = b.titleBox(1);
    check(box0.x == 124 and box0.w == 48 and box0.x + box0.w == box1.x, "bar: title boxes touch (124+48 = {d})", .{box1.x});
    // 이름만 — 모델이 없다.
    const n = mb.layoutBar(W, 20, "tars-wl-test", null, SCREEN_W);
    check(n.count == 0 and n.name_span.w == 96, "bar: name only without a model", .{});
    // 한글 이름은 칸 둘씩. 24칸을 넘으면 글자 경계에서 자른다 — 한글 13자(26칸) → 12자.
    const k = mb.layoutBar(W, 20, "가나다라마바사아자차카타파", null, SCREEN_W);
    check(k.name_span.w == 24 * 8 and std.mem.eql(u8, k.name, "가나다라마바사아자차카타"), "bar: a Hangul name is cut to 24 cells (got {d} px)", .{k.name_span.w});
    // 23칸 다음 한글 한 자(2칸)는 안 들어간다 — 23칸에서 그친다.
    const a23: [23]u8 = @splat('a');
    const k2 = mb.layoutBar(W, 20, &(a23 ++ "가".*), null, SCREEN_W);
    check(k2.name_span.w == 23 * 8, "bar: a wide character that would cross 24 cells is left out (got {d})", .{k2.name_span.w});
    // 이름이 없으면 제목이 이름 자리에서 시작한다.
    const e = mb.layoutBar(W, 20, "", &m, SCREEN_W);
    check(e.name_span.w == 0 and e.titles[0].x == 20, "bar: no name, first title at 20 (got {d})", .{e.titles[0].x});
    // 좁은 화면 — 칸이 넘치는 제목부터 안 놓는다. 188 = Edit의 칸 끝(220)보다 좁다.
    const s = mb.layoutBar(W, 20, "tars-wl-test", &m, 200);
    check(s.count == 1, "bar: a title past the screen is left out (got {d})", .{s.count});
    std.debug.print("menubar_test: bar layout\n", .{});
}

// ── 4 드롭다운 ───────────────────────────────────────────────────────

fn drop() !void {
    const m = try testModel();
    const b = mb.layoutBar(W, 20, "tars-wl-test", &m, SCREEN_W);
    // File: Open + 두 칸 + "Cmd+O"(5) = 11칸, + 좌우 = 13칸 = 104 px. 높이 16 + 8 + 16 = 40.
    const r = mb.dropRect(W, &m, &b, 0, SCREEN_W, SCREEN_H);
    check(r.x == 124 and r.y == 20 and r.w == 104 and r.h == 40, "drop: File at 124,20 104x40 (got {d},{d} {d}x{d})", .{ r.x, r.y, r.w, r.h });
    // Edit: Copy Cmd+C 11칸 · 한글 4칸 → 13칸.
    const r1 = mb.dropRect(W, &m, &b, 1, SCREEN_W, SCREEN_H);
    check(r1.x == 172 and r1.w == 104 and r1.h == 32, "drop: Edit at 172 104x32 (got {d} {d}x{d})", .{ r1.x, r1.w, r1.h });
    // 오른쪽에서 민다 — 화면 폭 200이면 x = 200 - 104 = 96.
    const r2 = mb.dropRect(W, &m, &b, 1, 200, SCREEN_H);
    check(r2.x == 96, "drop: pushed left from the right edge (got {d})", .{r2.x});
    // 아래에서 자른다 — 높이 50이면 30만.
    const r3 = mb.dropRect(W, &m, &b, 0, SCREEN_W, 50);
    check(r3.h == 30, "drop: cut at the bottom (got {d})", .{r3.h});
    // 짧은 메뉴는 제목의 칸보다 좁지 않다.
    var t: mb.Model = .{};
    try t.addMenu("Window");
    try t.addItem(1, "a", 0, 0, 0);
    const tb = mb.layoutBar(W, 20, "x", &t, SCREEN_W);
    const r4 = mb.dropRect(W, &t, &tb, 0, SCREEN_W, SCREEN_H);
    check(r4.w == tb.titleBox(0).w, "drop: never narrower than the title box (got {d})", .{r4.w});
    // 칸의 위 끝과 좌표의 칸.
    check(mb.entryTop(&m, 0, 0) == 0 and mb.entryTop(&m, 0, 1) == 16 and mb.entryTop(&m, 0, 2) == 24, "drop: entry tops 0 16 24", .{});
    check(mb.entryAt(&m, 0, 0) == 0 and mb.entryAt(&m, 0, 15) == 0 and mb.entryAt(&m, 0, 16) == 1 and mb.entryAt(&m, 0, 23) == 1 and
        mb.entryAt(&m, 0, 24) == 2 and mb.entryAt(&m, 0, 40) == null, "drop: entryAt rows", .{});
    std.debug.print("menubar_test: dropdown\n", .{});
}

// ── 5 키 ─────────────────────────────────────────────────────────────

fn keys() !void {
    const m = try testModel();
    // File: Open만 고를 수 있다 — 아래로 가도 위로 가도 Open으로 돌아온다.
    check(mb.step(&m, 0, null, .down) == 0, "step: first pickable of File is Open", .{});
    check(mb.step(&m, 0, 0, .down) == 0, "step: down from Open skips the separator and Quit and comes back", .{});
    check(mb.step(&m, 0, 0, .up) == 0, "step: up from Open comes back too", .{});
    check(mb.step(&m, 1, null, .down) == 0 and mb.step(&m, 1, 0, .down) == 1 and mb.step(&m, 1, 1, .down) == 0, "step: Edit wraps", .{});
    check(mb.step(&m, 1, null, .up) == 1, "step: up with nothing picked starts at the last", .{});
    var d: mb.Model = .{};
    try d.addMenu("Dead");
    try d.addSeparator();
    try d.addItem(1, "x", 0, 0, mb.FLAG_DISABLED);
    check(mb.step(&d, 0, null, .down) == null, "step: all disabled is null", .{});
    try d.addMenu("Empty");
    check(mb.step(&d, 1, null, .down) == null, "step: empty menu is null", .{});
    check(mb.nextMenu(2, 0, .right) == 1 and mb.nextMenu(2, 1, .right) == 0 and mb.nextMenu(2, 0, .left) == 1, "nextMenu wraps", .{});
    check(mb.nextMenu(0, 0, .right) == 0, "nextMenu: no menus", .{});
    std.debug.print("menubar_test: keys\n", .{});
}

// ── 6 hit-test ───────────────────────────────────────────────────────

fn hits() !void {
    const m = try testModel();
    const b = mb.layoutBar(W, 20, "tars-wl-test", &m, SCREEN_W);
    check(std.meta.eql(mb.hit(&m, &b, null, 124, 5), .{ .title = 0 }), "hit: File box left edge", .{});
    check(std.meta.eql(mb.hit(&m, &b, null, 171, 19), .{ .title = 0 }), "hit: File box right edge", .{});
    check(std.meta.eql(mb.hit(&m, &b, null, 172, 0), .{ .title = 1 }), "hit: Edit box", .{});
    check(mb.hit(&m, &b, null, 40, 5) == .inside, "hit: the name is inside", .{});
    check(mb.hit(&m, &b, null, 600, 5) == .inside, "hit: empty bar is inside", .{});
    check(mb.hit(&m, &b, null, 140, 20) == .outside, "hit: below the bar is outside", .{});
    const r = mb.dropRect(W, &m, &b, 0, SCREEN_W, SCREEN_H);
    const o: mb.Open = .{ .m = 0, .rect = r };
    check(std.meta.eql(mb.hit(&m, &b, o, 130, 20), .{ .entry = 0 }), "hit: Open row", .{});
    check(std.meta.eql(mb.hit(&m, &b, o, 130, 39), .{ .entry = 1 }), "hit: separator row", .{});
    check(std.meta.eql(mb.hit(&m, &b, o, 227, 59), .{ .entry = 2 }), "hit: Quit row, bottom right", .{});
    check(mb.hit(&m, &b, o, 228, 30) == .outside, "hit: right of the dropdown is outside", .{});
    check(mb.hit(&m, &b, o, 130, 60) == .outside, "hit: below the dropdown is outside", .{});
    check(std.meta.eql(mb.hit(&m, &b, o, 180, 3), .{ .title = 1 }), "hit: the bar still answers while open", .{});
    std.debug.print("menubar_test: hit-test\n", .{});
}

// ── 7 단축키 글 ──────────────────────────────────────────────────────

fn shortcuts() void {
    var buf: [mb.SHORTCUT_MAX]u8 = undefined;
    check(std.mem.eql(u8, mb.shortcutText(mb.MOD_SUPER, 24, &buf), "Cmd+O"), "shortcut: Cmd+O", .{});
    check(std.mem.eql(u8, mb.shortcutText(mb.MOD_SUPER | mb.MOD_SHIFT, 24, &buf), "Cmd+Shift+O"), "shortcut: Cmd+Shift+O order", .{});
    check(std.mem.eql(u8, mb.shortcutText(mb.MOD_SHIFT | mb.MOD_ALT | mb.MOD_CTRL | mb.MOD_SUPER, 14, &buf), "Cmd+Ctrl+Opt+Shift+Backspace"), "shortcut: all four, longest name", .{});
    check(std.mem.eql(u8, mb.shortcutText(mb.MOD_SUPER, 0, &buf), ""), "shortcut: key 0 is none", .{});
    check(std.mem.eql(u8, mb.shortcutText(mb.MOD_SUPER, 250, &buf), ""), "shortcut: unknown key is none", .{});
    check(std.mem.eql(u8, mb.shortcutText(0, 53, &buf), "/"), "shortcut: bare slash", .{});
    // 표의 이름 몇. 글자 26 · 숫자 10은 범위로 다 있다.
    const want = [_]struct { k: u32, n: []const u8 }{
        .{ .k = 16, .n = "Q" }, .{ .k = 25, .n = "P" }, .{ .k = 30, .n = "A" }, .{ .k = 38, .n = "L" },  .{ .k = 44, .n = "Z" },
        .{ .k = 50, .n = "M" }, .{ .k = 2, .n = "1" },  .{ .k = 11, .n = "0" }, .{ .k = 59, .n = "F1" }, .{ .k = 88, .n = "F12" },
    };
    for (want) |w| check(std.mem.eql(u8, mb.keyName(w.k).?, w.n), "keyName {d} = {s}", .{ w.k, w.n });
    var letters: u32 = 0;
    for (0..120) |k| if (mb.keyName(@intCast(k))) |n| if (n.len == 1 and n[0] >= 'A' and n[0] <= 'Z') {
        letters += 1;
    };
    check(letters == 26, "keyName: 26 letters (got {d})", .{letters});
    // 가장 긴 글이 버퍼 안이다.
    var longest: usize = 0;
    for (0..256) |k| {
        longest = @max(longest, mb.shortcutText(0x4D, @intCast(k), &buf).len);
    }
    check(longest <= mb.SHORTCUT_MAX, "shortcut: longest {d} fits", .{longest});
    std.debug.print("menubar_test: shortcut text\n", .{});
}

// ── 8 색(plan 확정 6) ────────────────────────────────────────────────

/// 게이트의 테스트 클라이언트(`tars-wl-test`)와 툴킷 데모 · 검사가 코드에 적어 쓰는 색(theme 밖). 바나 펼친 메뉴가 그 창 위나 옆에
/// 있을 때 덤프가 두 픽셀을 섞어 세지 않게 메뉴 색이 이것과도 달라야 한다.
const CLIENT_COLOURS = [_]u32{ 0x3366CC, 0xFFFFFF, 0x00FF00, 0x000000, 0x804020, 0x20A060, 0x6040C0, 0x808080, 0x7A7B7C, 0x112233, 0xFF00FF };

fn isSizeName(comptime name: []const u8) bool {
    for ([_][]const u8{ "TK_RADIUS", "TK_SPACE", "TK_PADDING", "TK_FONT", "TK_ROW", "TK_COLUMN", "TK_PREVIEW" }) |p| {
        if (std.mem.startsWith(u8, name, p)) return true;
    }
    return false;
}

fn colours() void {
    const decls = @typeInfo(theme).@"struct".decl_names;
    comptime var menu: u32 = 0;
    comptime var others: u32 = 0;
    comptime {
        @setEvalBranchQuota(40000);
        for (decls) |a| {
            if (!std.mem.startsWith(u8, a, "MENU_")) continue;
            menu += 1;
            const va: u32 = @field(theme, a) & 0x00FFFFFF;
            for (decls) |b| {
                if (std.mem.eql(u8, a, b) or isSizeName(b)) continue;
                if (va == @field(theme, b) & 0x00FFFFFF)
                    @compileError("theme: menu colour " ++ a ++ " equals " ++ b);
            }
            for (CLIENT_COLOURS) |c| if (va == c) @compileError("theme: menu colour " ++ a ++ " equals a client colour");
        }
        for (decls) |b| {
            if (!std.mem.startsWith(u8, b, "MENU_") and !isSizeName(b)) others += 1;
        }
    }
    check(menu == 6 and others >= 28, "colours: {d} menu colours share no value with {d} theme colours or {d} client colours (comptime)", .{ menu, others, CLIENT_COLOURS.len });
    std.debug.print("menubar_test: colours\n", .{});
}

pub fn main() !void {
    try model();
    names();
    try bar();
    try drop();
    try keys();
    try hits();
    shortcuts();
    colours();
    if (failures > 0) {
        std.debug.print("menubar_test: {d} failure(s)\n", .{failures});
        return error.Failed;
    }
    std.debug.print("menubar_test: all passed\n", .{});
}
