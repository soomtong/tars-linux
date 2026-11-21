//! 메뉴 바의 순수한 셈(TK-M5, plan 확정 3 · 4 · 5 — TK design 결정 16). 화면에 닿지 않는 것 전부가 여기 있다: 앱이 `tars_menu_v1`로
//! 보낸 모델의 검증과 상한, 바의 배치(앱 이름 · 메뉴 제목의 x와 폭), 펼친 메뉴(드롭다운)의 사각형, 키로 옮기기, 좌표로 고르기(hit-test),
//! 단축키 글. 서버(`wl/server.zig`)는 모델을 들고, 그리기(`main.zig`)는 여기서 받은 좌표에 칠한다 — 둘 다 같은 셈을 본다.
//! 호스트 검사는 `menubar_test.zig`.
//!
//! 글자 폭은 셀 단위다(terminal의 16 px unifont — 라틴 1칸 8 px, 한글 2칸). 여기는 글리프를 모르므로 폭을 재는 함수를 부르는 쪽이
//! 준다(`Widths`). 좌표는 논리 화면의 픽셀이다.

const std = @import("std");
const geometry = @import("geometry.zig");

/// 상한(plan 확정 3). 믿을 수 없는 클라이언트의 입력이라 넘으면 프로토콜 에러다. 모델 하나가 고정 배열이라 서버에 heap 할당이 없다.
pub const MAX_MENUS = 8;
pub const MAX_PER_MENU = 32;
pub const MAX_ENTRIES = 128;
pub const MAX_TEXT = 64;

/// 바의 앱 이름이 쓰는 칸의 상한(plan 확정 4). 넘으면 글자 경계에서 자른다.
pub const NAME_CELLS = 24;
/// 이름과 첫 제목 사이, 제목과 제목 사이의 칸 수.
pub const GAP_CELLS = 2;

pub const CELL_W = geometry.CELL_W;
/// 바의 높이 = 위 여백(plan 확정 1). 드롭다운은 이 아래부터다.
pub const BAR_H = geometry.MARGIN;
/// 바 글자의 y — 20 px 띠 안의 16 px 줄을 가운데(위아래 2 px).
pub const TEXT_Y = (BAR_H - geometry.ROW_HEIGHT) / 2;
/// 드롭다운의 행 높이 — 항목 16, 구분선 8(가운데 1 px 선).
pub const ROW_H = geometry.ROW_HEIGHT;
pub const SEP_H = 8;

pub const Error = error{ TooMany, TooLong, BadUtf8, NoMenu };

/// 고정 길이 글(제목 · 레이블). UTF-8로 검증한 것만 담긴다.
pub const Text = struct {
    buf: [MAX_TEXT]u8 = undefined,
    len: u8 = 0,

    pub fn init(bytes: []const u8) Error!Text {
        if (bytes.len > MAX_TEXT) return error.TooLong;
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.BadUtf8;
        var t: Text = .{ .len = @intCast(bytes.len) };
        @memcpy(t.buf[0..bytes.len], bytes);
        return t;
    }

    pub fn get(self: *const Text) []const u8 {
        return self.buf[0..self.len];
    }
};

/// 메뉴의 한 칸 — 항목 또는 구분선.
pub const Entry = struct {
    kind: enum { item, separator },
    id: u32 = 0,
    label: Text = .{},
    /// `wl_keyboard.modifiers`의 비트(xml `add_item`)와 evdev 키 코드. 키 0이면 단축키 없음.
    mods: u32 = 0,
    key: u32 = 0,
    disabled: bool = false,

    /// 키 · 포인터로 고를 수 있는가 — 구분선과 비활성 항목은 건너뛴다.
    pub fn pickable(self: *const Entry) bool {
        return self.kind == .item and !self.disabled;
    }
};

pub const Menu = struct {
    title: Text,
    /// 이 메뉴의 칸이 `Model.entries`의 어디부터 몇 개인가.
    first: u8,
    count: u8,
};

/// xml `item_flags`의 비트.
pub const FLAG_DISABLED: u32 = 1;

/// 모델 하나. 서버는 둘을 든다 — 쌓는 중인 것(pending)과 보이는 것(current). `commit`이 앞의 것을 뒤로 통째 옮긴다(증분 없음).
pub const Model = struct {
    menus: [MAX_MENUS]Menu = undefined,
    menu_count: u8 = 0,
    entries: [MAX_ENTRIES]Entry = undefined,
    entry_count: u8 = 0,

    pub fn clear(self: *Model) void {
        self.menu_count = 0;
        self.entry_count = 0;
    }

    pub fn menuList(self: *const Model) []const Menu {
        return self.menus[0..self.menu_count];
    }

    /// 메뉴 `m`의 칸들.
    pub fn entriesOf(self: *const Model, m: u8) []const Entry {
        const menu = self.menus[m];
        return self.entries[menu.first..][0..menu.count];
    }

    pub fn addMenu(self: *Model, title: []const u8) Error!void {
        if (self.menu_count == MAX_MENUS) return error.TooMany;
        const t = try Text.init(title);
        self.menus[self.menu_count] = .{ .title = t, .first = self.entry_count, .count = 0 };
        self.menu_count += 1;
    }

    pub fn addItem(self: *Model, id: u32, label: []const u8, mods: u32, key: u32, flags: u32) Error!void {
        try self.room();
        const t = try Text.init(label);
        self.push(.{ .kind = .item, .id = id, .label = t, .mods = mods, .key = key, .disabled = flags & FLAG_DISABLED != 0 });
    }

    pub fn addSeparator(self: *Model) Error!void {
        try self.room();
        self.push(.{ .kind = .separator });
    }

    /// 항목 · 구분선을 더할 자리가 있는가 — 메뉴가 먼저 있어야 하고, 마지막 메뉴와 전체의 상한 안이어야 한다.
    fn room(self: *const Model) Error!void {
        if (self.menu_count == 0) return error.NoMenu;
        if (self.entry_count == MAX_ENTRIES) return error.TooMany;
        if (self.menus[self.menu_count - 1].count == MAX_PER_MENU) return error.TooMany;
    }

    fn push(self: *Model, e: Entry) void {
        self.entries[self.entry_count] = e;
        self.entry_count += 1;
        self.menus[self.menu_count - 1].count += 1;
    }
};

// ── 이름 ───────────────────────────────────────────────────────────

/// 클라이언트가 보낸 글(`set_title` · `set_app_id`)을 `max`바이트 안으로(plan 확정 4). UTF-8이 아니면 null(버린다), 넘으면 글자 경계에서
/// 자른다.
pub fn clampUtf8(bytes: []const u8, max: usize) ?[]const u8 {
    if (!std.unicode.utf8ValidateSlice(bytes)) return null;
    if (bytes.len <= max) return bytes;
    var end = max;
    // 이어지는 바이트(10xxxxxx)에서 멈췄으면 그 글자의 처음까지 물러난다.
    while (end > 0 and bytes[end] & 0xC0 == 0x80) end -= 1;
    return bytes[0..end];
}

/// 바의 앱 이름(plan 확정 4): app_id가 있으면 그 마지막 `.` 뒤 조각(`org.chromium.Chromium` → `Chromium`), 조각이 비면 app_id 그대로,
/// app_id가 없으면 title.
pub fn appName(app_id: []const u8, title: []const u8) []const u8 {
    if (app_id.len == 0) return title;
    const dot = std.mem.lastIndexOfScalar(u8, app_id, '.') orelse return app_id;
    const tail = app_id[dot + 1 ..];
    return if (tail.len == 0) app_id else tail;
}

// ── 폭 ─────────────────────────────────────────────────────────────

/// 글자 하나의 칸 수를 재는 함수(부르는 쪽의 글꼴). 0을 돌려주면 1로 센다 — 그리기(`drawRun`)의 `@max(1, …)`와 같다.
pub const Widths = struct {
    ctx: *const anyopaque,
    cellsOf: *const fn (ctx: *const anyopaque, cp: u21) u8,

    pub fn cp(self: Widths, c: u21) u32 {
        return @max(1, self.cellsOf(self.ctx, c));
    }

    /// 글 전체의 칸 수.
    pub fn text(self: Widths, bytes: []const u8) u32 {
        var view = std.unicode.Utf8View.init(bytes) catch return 0;
        var it = view.iterator();
        var n: u32 = 0;
        while (it.nextCodepoint()) |c| n += self.cp(c);
        return n;
    }

    /// 앞에서부터 `max_cells` 칸 안에 드는 가장 긴 앞부분(글자 경계).
    pub fn fit(self: Widths, bytes: []const u8, max_cells: u32) []const u8 {
        var view = std.unicode.Utf8View.init(bytes) catch return bytes[0..0];
        var it = view.iterator();
        var n: u32 = 0;
        var end: usize = 0;
        while (it.nextCodepointSlice()) |s| {
            const c = std.unicode.utf8Decode(s) catch break;
            const w = self.cp(c);
            if (n + w > max_cells) break;
            n += w;
            end += s.len;
        }
        return bytes[0..end];
    }
};

// ── 바 ─────────────────────────────────────────────────────────────

/// 가로 한 토막(픽셀).
pub const Span = struct {
    x: u32,
    w: u32,

    fn end(self: Span) u32 {
        return self.x + self.w;
    }
};

/// 닫힌 바의 배치. 글자는 `name` · `titles[i]`의 x에서 y `TEXT_Y`로 그린다. 제목의 칸(`titleBox`)은 글자의 좌우로 한 칸씩 넓다 —
/// 열린 제목을 칠하는 자리이고 누름을 받는 자리다. 제목 사이가 두 칸이라 이웃 칸이 빈틈없이 맞닿는다.
pub const Bar = struct {
    /// 그릴 이름(자른 뒤)과 그 자리. 이름이 없으면 폭 0.
    name: []const u8,
    name_span: Span,
    /// 화면 안에 다 들어간 제목만(앞에서부터). 넘치는 제목부터는 없다.
    titles: [MAX_MENUS]Span = undefined,
    count: u8 = 0,

    pub fn titleBox(self: *const Bar, m: u8) Span {
        const t = self.titles[m];
        return .{ .x = t.x - CELL_W, .w = t.w + 2 * CELL_W };
    }
};

/// 바를 놓는다(plan 확정 1 · 2). `left`는 글자가 시작하는 x(`grid_origin.x`), `max_x`는 화면 폭. 모델이 없으면 이름만.
pub fn layoutBar(w: Widths, left: u32, name: []const u8, model: ?*const Model, max_x: u32) Bar {
    const shown = w.fit(name, NAME_CELLS);
    const name_cells = w.text(shown);
    var bar: Bar = .{ .name = shown, .name_span = .{ .x = left, .w = name_cells * CELL_W } };
    const m = model orelse return bar;
    // 이름이 비었으면 첫 제목이 이름 자리에서 시작한다. 제목의 칸이 왼쪽으로 한 칸 나가므로 `left`가 한 칸보다 작으면 한 칸 민다.
    var x: u32 = if (name_cells == 0) @max(left, CELL_W) else left + (name_cells + GAP_CELLS) * CELL_W;
    for (m.menuList(), 0..) |menu, i| {
        const cells = w.text(menu.title.get());
        const span: Span = .{ .x = x, .w = cells * CELL_W };
        // 제목의 칸(오른쪽 한 칸 포함)이 화면을 넘으면 여기서 그친다.
        if (span.end() + CELL_W > max_x) break;
        bar.titles[i] = span;
        bar.count += 1;
        x = span.end() + GAP_CELLS * CELL_W;
    }
    return bar;
}

// ── 드롭다운 ───────────────────────────────────────────────────────

pub const Rect = struct {
    x: u32,
    y: u32,
    w: u32,
    h: u32,

    pub fn contains(self: Rect, px: u32, py: u32) bool {
        return px >= self.x and px < self.x + self.w and py >= self.y and py < self.y + self.h;
    }
};

/// 칸 하나의 높이.
pub fn entryHeight(e: *const Entry) u32 {
    return if (e.kind == .separator) SEP_H else ROW_H;
}

/// 단축키 글이 있을 때 레이블과 단축키 사이의 칸 수.
pub const SHORTCUT_GAP_CELLS = 2;

/// 펼친 메뉴의 사각형(plan 확정 8). x는 그 제목의 칸(`titleBox`)의 왼쪽, y는 바 아래. 폭은 가장 긴 (레이블 + 두 칸 + 단축키) + 좌우 한
/// 칸씩이고 제목의 칸보다 좁지 않다. 오른쪽이 화면을 넘으면 왼쪽으로 민다. 아래가 넘으면 화면 끝에서 자른다(그 아래 칸은 안 보인다).
pub fn dropRect(w: Widths, model: *const Model, bar: *const Bar, m: u8, screen_w: u32, screen_h: u32) Rect {
    var cells: u32 = 0;
    var h: u32 = 0;
    var buf: [SHORTCUT_MAX]u8 = undefined;
    for (model.entriesOf(m)) |*e| {
        h += entryHeight(e);
        if (e.kind == .separator) continue;
        const sc = shortcutText(e.mods, e.key, &buf);
        const sc_cells: u32 = if (sc.len == 0) 0 else SHORTCUT_GAP_CELLS + @as(u32, @intCast(sc.len));
        cells = @max(cells, w.text(e.label.get()) + sc_cells);
    }
    const box = bar.titleBox(m);
    const width = @max((cells + 2) * CELL_W, box.w);
    const x = if (box.x + width > screen_w) screen_w -| width else box.x;
    const room = screen_h -| BAR_H;
    return .{ .x = x, .y = BAR_H, .w = width, .h = @min(h, room) };
}

/// 메뉴 `m`의 칸 `i`의 위 끝(드롭다운 안, 위에서 잰 픽셀).
pub fn entryTop(model: *const Model, m: u8, i: u8) u32 {
    var y: u32 = 0;
    for (model.entriesOf(m)[0..i]) |*e| y += entryHeight(e);
    return y;
}

/// 드롭다운 안 위에서 잰 `rel_y`의 칸. 칸들 아래면 null.
pub fn entryAt(model: *const Model, m: u8, rel_y: u32) ?u8 {
    var y: u32 = 0;
    for (model.entriesOf(m), 0..) |*e, i| {
        const h = entryHeight(e);
        if (rel_y < y + h) return @intCast(i);
        y += h;
    }
    return null;
}

// ── 키 ─────────────────────────────────────────────────────────────

pub const Dir = enum { up, down };

/// 메뉴 `m`에서 `cur` 다음(또는 앞) 고를 수 있는 칸(plan 확정 9). 구분선 · 비활성은 건너뛰고 끝에서 돌아간다. `cur`가 null이면
/// 아래로는 첫 칸, 위로는 마지막 칸부터 찾는다. 고를 칸이 없으면 null.
pub fn step(model: *const Model, m: u8, cur: ?u8, dir: Dir) ?u8 {
    const es = model.entriesOf(m);
    const n: u32 = @intCast(es.len);
    if (n == 0) return null;
    var at: u32 = if (cur) |c| c else switch (dir) {
        .down => n - 1,
        .up => 0,
    };
    var k: u32 = 0;
    while (k < n) : (k += 1) {
        at = switch (dir) {
            .down => (at + 1) % n,
            .up => (at + n - 1) % n,
        };
        if (es[at].pickable()) return @intCast(at);
    }
    return null;
}

/// 옆 메뉴(`←` `→`). 끝에서 돌아간다. 보이는 메뉴 수 `count`가 0이면 0.
pub fn nextMenu(count: u8, m: u8, dir: enum { left, right }) u8 {
    if (count == 0) return 0;
    return switch (dir) {
        .right => (m + 1) % count,
        .left => (m + count - 1) % count,
    };
}

// ── 좌표 ───────────────────────────────────────────────────────────

/// 펼친 메뉴 — 메뉴 번호와 그 사각형(`dropRect`).
pub const Open = struct { m: u8, rect: Rect };

/// 누름 하나가 닿은 곳(plan 확정 11).
pub const Hit = union(enum) {
    /// 바의 제목 칸.
    title: u8,
    /// 펼친 메뉴의 칸(구분선 · 비활성도 — 고를 수 있는지는 부르는 쪽이 `pickable`로 본다).
    entry: u8,
    /// 바의 나머지(이름 · 빈 자리), 또는 펼친 메뉴 안의 칸이 아닌 자리.
    inside,
    /// 바와 메뉴 밖.
    outside,
};

/// 화면 좌표 (`x`, `y`)가 닿은 곳. `open`은 펼친 메뉴(없으면 null)와 그 사각형이다. 펼친 메뉴가 바보다 먼저다 — 둘은 안 겹치지만
/// 순서를 정해 둔다.
pub fn hit(model: *const Model, bar: *const Bar, open: ?Open, x: u32, y: u32) Hit {
    if (open) |o| if (o.rect.contains(x, y)) {
        return if (entryAt(model, o.m, y - o.rect.y)) |i| .{ .entry = i } else .inside;
    };
    if (y >= BAR_H) return .outside;
    var i: u8 = 0;
    while (i < bar.count) : (i += 1) {
        const b = bar.titleBox(i);
        if (x >= b.x and x < b.end()) return .{ .title = i };
    }
    return .inside;
}

// ── 단축키 글 ──────────────────────────────────────────────────────

/// `wl_keyboard.modifiers`의 비트(`wl_logic.MOD_*`와 같은 값 — xml `add_item`이 약속한 것).
pub const MOD_SHIFT: u32 = 0x1;
pub const MOD_CTRL: u32 = 0x4;
pub const MOD_ALT: u32 = 0x8;
pub const MOD_SUPER: u32 = 0x40;

/// 단축키 글의 가장 긴 길이(`Cmd+Ctrl+Opt+Shift+Backspace` = 28).
pub const SHORTCUT_MAX = 32;

/// 단축키 글(plan 확정 6 — ASCII, `Cmd+Shift+O` 꼴). 수정키는 Cmd · Ctrl · Opt · Shift 순서. 키가 0이거나 이름 표에 없으면 빈 글
/// (단축키를 안 보인다).
pub fn shortcutText(mods: u32, key: u32, buf: *[SHORTCUT_MAX]u8) []const u8 {
    const name = keyName(key) orelse return buf[0..0];
    var n: usize = 0;
    const parts = [_]struct { bit: u32, text: []const u8 }{
        .{ .bit = MOD_SUPER, .text = "Cmd+" },
        .{ .bit = MOD_CTRL, .text = "Ctrl+" },
        .{ .bit = MOD_ALT, .text = "Opt+" },
        .{ .bit = MOD_SHIFT, .text = "Shift+" },
    };
    for (parts) |p| if (mods & p.bit != 0) {
        @memcpy(buf[n..][0..p.text.len], p.text);
        n += p.text.len;
    };
    @memcpy(buf[n..][0..name.len], name);
    return buf[0 .. n + name.len];
}

/// evdev 키 코드의 이름(linux/input-event-codes.h). 단축키에 흔한 것만 — 없으면 null.
pub fn keyName(key: u32) ?[]const u8 {
    const letters = "QWERTYUIOP";
    const letters2 = "ASDFGHJKL";
    const letters3 = "ZXCVBNM";
    const digits = "1234567890";
    return switch (key) {
        0 => null,
        2...11 => digits[key - 2 ..][0..1],
        16...25 => letters[key - 16 ..][0..1],
        30...38 => letters2[key - 30 ..][0..1],
        44...50 => letters3[key - 44 ..][0..1],
        59...68 => ([_][]const u8{ "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10" })[key - 59],
        87 => "F11",
        88 => "F12",
        1 => "Esc",
        12 => "-",
        13 => "=",
        14 => "Backspace",
        15 => "Tab",
        26 => "[",
        27 => "]",
        28 => "Enter",
        39 => ";",
        40 => "'",
        41 => "`",
        43 => "\\",
        51 => ",",
        52 => ".",
        53 => "/",
        57 => "Space",
        102 => "Home",
        103 => "Up",
        104 => "PageUp",
        105 => "Left",
        106 => "Right",
        107 => "End",
        108 => "Down",
        109 => "PageDown",
        111 => "Delete",
        else => null,
    };
}
