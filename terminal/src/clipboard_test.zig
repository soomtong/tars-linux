const std = @import("std");
const clipboard = @import("clipboard.zig");

const Clipboard = clipboard.Clipboard;

/// `alloc`으로 `s`의 사본을 만든다. `copyYank`가 `selectionString`으로 하는
/// 일과 같은 모양 — 할당자가 준 sentinel 슬라이스다.
fn dup(alloc: std.mem.Allocator, s: []const u8) ![:0]const u8 {
    return try alloc.dupeZ(u8, s);
}

fn expectText(what: []const u8, got: ?[]const u8, want: ?[]const u8) !void {
    const same = if (got == null or want == null) got == null and want == null else std.mem.eql(u8, got.?, want.?);
    if (same) {
        std.debug.print("clipboard_test: {s} = {?s} OK\n", .{ what, got });
        return;
    }
    std.debug.print("FAIL: {s} = {?s}, want {?s}\n", .{ what, got, want });
    return error.WrongClipText;
}

fn expectPick(what: []const u8, got: *Clipboard, want: *Clipboard) !void {
    if (got == want) {
        std.debug.print("clipboard_test: {s} OK\n", .{what});
        return;
    }
    std.debug.print("FAIL: {s} picked the other clipboard\n", .{what});
    return error.WrongPick;
}

pub fn main() !void {
    // 누수를 이 할당자가 센다. `set`이 옛것을 안 해제하거나 `deinit`이
    // 남기면 맨 끝의 `deinit()`이 `.leak`을 돌려준다 — 검사 2 · 5가 보는
    // 것이 그 하나다.
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const alloc = gpa.allocator();

    // 검사 1. 새 칸은 비었다. 대조군이다 — 이것이 없으면 아래 검사들이
    // "언제나 무언가를 준다"도 통과한다.
    var a = Clipboard.init(alloc);
    try expectText("a fresh clipboard", a.text(), null);

    // 검사 2. `set`한 것이 그대로 나오고, 다음 `set`이 옛것을 바꾼다.
    // 옛것의 해제는 맨 끝의 누수 판정이 본다.
    a.set(try dup(alloc, "echo cb-pane"));
    try expectText("after one set", a.text(), "echo cb-pane");
    a.set(try dup(alloc, "가나\n다라"));
    try expectText("after a second set", a.text(), "가나\n다라");

    // 검사 3. 범위가 칸을 고른다. `shared`면 공유 칸, `pane`이면 그 패널의
    // 칸이다. 칸 둘의 주소로 본다 — 내용으로 보면 둘이 우연히 같을 때 못
    // 가른다.
    var own = Clipboard.init(alloc);
    try expectPick("shared picks the shared clipboard", clipboard.pick(.shared, &a, &own), &a);
    try expectPick("pane picks the pane's own clipboard", clipboard.pick(.pane, &a, &own), &own);

    // 검사 4. 패널 칸에 넣은 것은 공유 칸에 안 보인다. `main.zig`가 패널마다
    // 칸을 하나씩 들고 `pick`으로 고른다는 모양이 이 성질 위에 서 있다.
    clipboard.pick(.pane, &a, &own).set(try dup(alloc, "only here"));
    try expectText("the pane's own clipboard", own.text(), "only here");
    try expectText("the shared clipboard after a pane set", a.text(), "가나\n다라");

    // 검사 5. 범위 이름이 `tars.conf`의 값과 같다. init이 argv로 보낸 글자를
    // `main.zig`가 `stringToEnum`으로 되돌리므로, 이름이 바뀌면 설정이 조용히
    // 기본값으로 떨어진다.
    if (std.meta.stringToEnum(clipboard.Scope, "shared") != .shared or
        std.meta.stringToEnum(clipboard.Scope, "pane") != .pane or
        std.meta.stringToEnum(clipboard.Scope, "workspace") != null)
    {
        std.debug.print("FAIL: the scope names are not exactly shared and pane\n", .{});
        return error.WrongScopeNames;
    }
    std.debug.print("clipboard_test: scope names shared · pane OK\n", .{});

    a.deinit();
    own.deinit();
    if (gpa.deinit() == .leak) {
        std.debug.print("FAIL: the clipboards leaked\n", .{});
        return error.Leak;
    }
    std.debug.print("clipboard_test: no leak OK\n", .{});
    std.debug.print("clipboard_test: all checks passed\n", .{});
}
