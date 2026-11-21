//! 메뉴 모델(TK-M6 plan 확정 1, R-KIT-7 · 9 — TK design 결정 16). 층 밖의 순수 값 모듈 `tk_menu`다: 창 층이 이것을 `tars_menu_v1` 요청 열로
//! 직렬화하고(`emit`), kit이 키를 이것에 맞춘다(`match`) — 창 층은 kit을 모르므로(R-ARCH-1) 둘 다 부를 수 있는 자리에 둔다(`tk_geom` ·
//! `tk_input`과 같다).
//!
//! 모델은 앱이 상수로 짓는다(메뉴 · 항목 · 구분선). 항목의 `action`은 프로토콜의 id 그대로다 — 서버가 `activated(id)`로 돌려주면 같은 값으로
//! 같은 동작을 찾는다. 단축키는 구조(수정키 + evdev 코드)로 들고, 서버가 글을 그린다(xml `add_item`). 비활성은 모델이 들지 않는다 — 보낼 때
//! kit이 responder chain에 물어 셈한 `Disabled`(항목 순서의 비트)를 함께 넘긴다.
//!
//! 상한은 서버와 같은 수다(xml `tars_menu_v1`의 설명, `terminal/src/menubar.zig`의 `MAX_*`) — 넘으면 서버가 프로토콜 에러로 연결을 끊으므로
//! 툴킷이 먼저 `check`로 거른다. terminal 파일은 import하지 않는다(menubar가 terminal의 `geometry.zig`를 끈다).

const std = @import("std");
const input = @import("tk_input");

pub const MAX_MENUS = 8;
pub const MAX_PER_MENU = 32;
pub const MAX_ENTRIES = 128;
pub const MAX_TEXT = 64;

/// xml의 error enum과 같은 넷(`already_constructed`는 창 층의 일이라 뺐다). 이 모양의 모델에서는 메뉴 밖 항목이 없어 `NoMenu`는 안 나지만
/// 서버의 목록과 맞춰 둔다.
pub const Error = error{ TooMany, TooLong, BadUtf8, NoMenu };

/// kit이 예약한 표준 action(plan 확정 2). 텍스트 필드가 구현한다. 앱의 action은 `FIRST_APP`부터.
pub const UNDO: u32 = 1;
pub const CUT: u32 = 2;
pub const COPY: u32 = 3;
pub const PASTE: u32 = 4;
pub const SELECT_ALL: u32 = 5;
pub const FIRST_APP: u32 = 16;

/// 항목 하나. `name`은 로그 줄(`tk> action name=`)의 이름(ASCII), `label`은 바에 보일 글(UTF-8). `key` 0이면 단축키 없음.
pub const Item = struct {
    action: u32,
    name: []const u8,
    label: []const u8,
    mods: input.Mods = .{},
    key: u32 = 0,
};

pub const Entry = union(enum) {
    item: Item,
    separator,
};

pub const Menu = struct {
    title: []const u8,
    entries: []const Entry,
};

pub const Model = struct {
    menus: []const Menu,

    /// 구분선을 넣은 항목 수(서버의 `wl> menu … items=`와 같은 셈).
    pub fn entryCount(self: *const Model) usize {
        var n: usize = 0;
        for (self.menus) |m| n += m.entries.len;
        return n;
    }

    /// 서버의 상한 넷을 먼저 본다(plan 확정 1). 통과하면 보내도 서버가 연결을 끊지 않는다.
    pub fn check(self: *const Model) Error!void {
        if (self.menus.len > MAX_MENUS) return error.TooMany;
        if (self.entryCount() > MAX_ENTRIES) return error.TooMany;
        for (self.menus) |m| {
            try checkText(m.title);
            if (m.entries.len > MAX_PER_MENU) return error.TooMany;
            for (m.entries) |e| switch (e) {
                .item => |it| try checkText(it.label),
                .separator => {},
            };
        }
    }

    /// 항목 순서 번호(구분선 포함, 메뉴를 차례로)가 `index`인 항목.
    pub fn itemAt(self: *const Model, index: usize) ?Item {
        var i: usize = 0;
        for (self.menus) |m| for (m.entries) |e| {
            if (i == index) return switch (e) {
                .item => |it| it,
                .separator => null,
            };
            i += 1;
        };
        return null;
    }
};

fn checkText(t: []const u8) Error!void {
    if (t.len > MAX_TEXT) return error.TooLong;
    if (!std.unicode.utf8ValidateSlice(t)) return error.BadUtf8;
}

/// 항목마다 비활성 비트 하나(항목 순서 번호 — 구분선 자리도 센다, 늘 0).
pub const Disabled = std.StaticBitSet(MAX_ENTRIES);

/// 수정키 넷의 `wl_keyboard.modifiers` 비트(`input.modsFromMask`의 역 — caps는 뺀다). 프로토콜의 `shortcut_mods`.
pub fn maskOf(m: input.Mods) u32 {
    var v: u32 = 0;
    if (m.shift) v |= input.MASK_SHIFT;
    if (m.ctrl) v |= input.MASK_CTRL;
    if (m.alt) v |= input.MASK_ALT;
    if (m.super) v |= input.MASK_SUPER;
    return v;
}

fn sameMods(a: input.Mods, b: input.Mods) bool {
    return a.shift == b.shift and a.ctrl == b.ctrl and a.alt == b.alt and a.super == b.super;
}

pub const Found = struct { item: Item, index: usize };

/// 키 하나(수정키 · evdev 코드)에 맞는 첫 항목. caps는 안 보고 나머지 넷은 같아야 한다. 코드 0은 아무것에도 안 맞는다.
pub fn match(model: *const Model, mods: input.Mods, code: u32) ?Found {
    if (code == 0) return null;
    var i: usize = 0;
    for (model.menus) |m| for (m.entries) |e| {
        switch (e) {
            .item => |it| if (it.key == code and sameMods(it.mods, mods)) return .{ .item = it, .index = i },
            .separator => {},
        }
        i += 1;
    };
    return null;
}

/// action 값의 첫 항목(`activated(id)`가 온 때).
pub fn find(model: *const Model, action: u32) ?Found {
    var i: usize = 0;
    for (model.menus) |m| for (m.entries) |e| {
        switch (e) {
            .item => |it| if (it.action == action) return .{ .item = it, .index = i },
            .separator => {},
        }
        i += 1;
    };
    return null;
}

/// 모델을 요청 열로(plan 확정 7). `sink`는 `addMenu(title)` · `addItem(id, label, mods, key, disabled)` · `addSeparator()` · `commit()`을 가진
/// 것 — 창 층은 `tars_menu_v1`으로, 호스트 검사는 기록기로 받는다. `check`를 통과한 모델만 넘긴다.
pub fn emit(model: *const Model, disabled: *const Disabled, sink: anytype) void {
    var i: usize = 0;
    for (model.menus) |m| {
        sink.addMenu(m.title);
        for (m.entries) |e| {
            switch (e) {
                .item => |it| sink.addItem(it.action, it.label, maskOf(it.mods), it.key, disabled.isSet(i)),
                .separator => sink.addSeparator(),
            }
            i += 1;
        }
    }
    sink.commit();
}

const CMD: input.Mods = .{ .super = true };

/// 표준 Edit 조각(plan 확정 4) — 앱이 자기 Edit 메뉴에 넣는다. 글은 한글.
pub const standard_edit = [_]Entry{
    .{ .item = .{ .action = UNDO, .name = "undo", .label = "되돌리기", .mods = CMD, .key = input.KEY_Z } },
    .separator,
    .{ .item = .{ .action = CUT, .name = "cut", .label = "오려두기", .mods = CMD, .key = input.KEY_X } },
    .{ .item = .{ .action = COPY, .name = "copy", .label = "복사", .mods = CMD, .key = input.KEY_C } },
    .{ .item = .{ .action = PASTE, .name = "paste", .label = "붙여넣기", .mods = CMD, .key = input.KEY_V } },
    .{ .item = .{ .action = SELECT_ALL, .name = "select_all", .label = "전체 선택", .mods = CMD, .key = input.KEY_A } },
};

/// 모델이 없는 `Root`가 쓰는 기본 표(plan 확정 4) — 필드만 쓰는 앱(데모)의 `Cmd+A/C/X/V/Z`가 안 깨진다. 서버에 보내지는 않는다.
pub const default_table: Model = .{ .menus = &.{.{ .title = "Edit", .entries = &standard_edit }} };
