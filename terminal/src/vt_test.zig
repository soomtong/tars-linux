const std = @import("std");
const vt = @import("vt.zig");

/// 한 행의 글자만 이어 붙인다. "화면이 정말 달라졌는가"를 비교하는 데 쓴다.
///
/// 위치 숫자(`scrollbar()`)만 보면 **뷰포트는 움직였는데 화면은 그대로인**
/// 상태를 못 잡는다. 그것이 정확히 `cells()`가 뷰포트를 안 따라갈 때의
/// 증상이라 여기서 따로 본다.
fn rowText(cells: []const vt.CellGlyph, row: u16, buf: []u8) []const u8 {
    var n: usize = 0;
    for (cells) |cell| {
        if (cell.row != row) continue;
        if (cell.codepoint == 0) continue;
        const len = std.unicode.utf8Encode(@intCast(cell.codepoint), buf[n..]) catch continue;
        n += len;
    }
    return buf[0..n];
}

pub fn main(init: std.process.Init) !void {
    const screen = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer screen.deinit();

    var buf: [100]vt.CellGlyph = undefined;

    // 1차: "TARS 하이" — TF-M2와 동일한 검증.
    screen.feed("TARS \xed\x95\x98\xec\x9d\xb4\r\n");
    const first = try screen.cells(&buf);
    std.debug.print("after 1st feed: {d} cells\n", .{first.len});
    if (first.len == 0) return error.NoCells;
    if (first[0].codepoint != 'T' or first[0].row != 0 or first[0].col != 0) {
        std.debug.print("FAIL: expected first cell 'T' at (0,0)\n", .{});
        return error.UnexpectedFirstCell;
    }

    // 2차: 두 번째 조각을 먹인다. **1차 내용이 살아 있어야 한다** —
    // 이게 TF-M3에서 새로 필요해진 성질이다.
    screen.feed("OK\r\n");
    const second = try screen.cells(&buf);
    std.debug.print("after 2nd feed: {d} cells\n", .{second.len});
    for (second) |cell| {
        std.debug.print("  row={d} col={d} codepoint=U+{X}\n", .{ cell.row, cell.col, cell.codepoint });
    }
    if (second.len <= first.len) {
        std.debug.print("FAIL: 2nd feed should ADD cells, not replace them\n", .{});
        return error.StateNotRetained;
    }
    if (second[0].codepoint != 'T') {
        std.debug.print("FAIL: 1st feed content was lost\n", .{});
        return error.StateNotRetained;
    }

    // 이스케이프 시퀀스가 조각 경계에서 잘려도 파서 상태가 이어지는지 확인.
    // "\x1b[" + "2J"는 합쳐야 화면 지우기(ED)가 된다.
    screen.feed("\x1b[");
    screen.feed("2J");
    const third = try screen.cells(&buf);
    std.debug.print("after split escape (clear): {d} cells\n", .{third.len});
    // TR-M0 전까지 이 단언은 `third.len != 0`이었다. 결정 3 뒤로는 **커서
    // 셀 하나가 남는다** — 글자는 없지만 색이 반전되어 기본 배경과 다르기
    // 때문이다. 회귀가 아니라 의도한 결과이고, 그래서 "글자가 하나도
    // 안 남았는가"로 조건을 옮긴다.
    if (third.len != 1) {
        std.debug.print("FAIL: expected only the cursor cell to remain\n", .{});
        return error.SplitEscapeNotHandled;
    }
    if (third[0].codepoint != 0) {
        std.debug.print("FAIL: a glyph survived the clear (cp={d})\n", .{third[0].codepoint});
        return error.SplitEscapeNotHandled;
    }

    // ── TR-M0: 색 ─────────────────────────────────────────────────────
    //
    // 기대값은 plan을 쓰면서 컨테이너에서 직접 재 둔 것이다. 팔레트가 xterm
    // 고전값이 아니라는 것이 요점이다 — 빨강이 #CD0000이 아니라 #CC6666이다.
    screen.feed("\x1b[2J\x1b[H");
    screen.feed("A\x1b[31mB\x1b[0m\x1b[41mC\x1b[0m\x1b[1;31mD\x1b[0m\x1b[7mE\x1b[0m\x1b[38;2;18;52;86mF\x1b[0mG");
    const styled = try screen.cells(&buf);

    const Want = struct { cp: u32, fg: u32, bg: u32, what: []const u8 };
    const wants = [_]Want{
        .{ .cp = 'A', .fg = 0xFFFFFF, .bg = 0x102030, .what = "스타일을 가진 적 없는 셀" },
        .{ .cp = 'B', .fg = 0xCC6666, .bg = 0x102030, .what = "SGR 31 빨강 전경" },
        .{ .cp = 'C', .fg = 0xFFFFFF, .bg = 0xCC6666, .what = "SGR 41 빨강 배경" },
        .{ .cp = 'D', .fg = 0xD54E53, .bg = 0x102030, .what = "SGR 1;31 bold는 밝게" },
        .{ .cp = 'E', .fg = 0x102030, .bg = 0xFFFFFF, .what = "SGR 7 inverse는 맞바꾼다" },
        .{ .cp = 'F', .fg = 0x123456, .bg = 0x102030, .what = "truecolor" },
        // A와 다른 것을 본다. A는 스타일을 가진 적이 없고, G는 **가졌다가
        // SGR 0으로 되돌아온** 셀이다. 리셋이 고장나면 A는 멀쩡한데 G만
        // 틀린다.
        .{ .cp = 'G', .fg = 0xFFFFFF, .bg = 0x102030, .what = "SGR 0 뒤의 셀" },
    };

    for (wants) |want| {
        var found = false;
        for (styled) |cell| {
            if (cell.codepoint != want.cp) continue;
            found = true;
            if (cell.fg != want.fg or cell.bg != want.bg) {
                std.debug.print(
                    "FAIL: {s}: '{c}' fg=#{X:0>6} bg=#{X:0>6} (expected fg=#{X:0>6} bg=#{X:0>6})\n",
                    .{ want.what, @as(u8, @intCast(want.cp)), cell.fg, cell.bg, want.fg, want.bg },
                );
                return error.WrongColor;
            }
            std.debug.print("vt_test: {s} OK\n", .{want.what});
            break;
        }
        if (!found) {
            std.debug.print("FAIL: {s}: '{c}' 셀이 없다\n", .{ want.what, @as(u8, @intCast(want.cp)) });
            return error.CellMissing;
        }
    }

    // ── TR-M0: 커서 ───────────────────────────────────────────────────
    //
    // 커서는 inverse와 같은 연산이라 코드가 따로 없다(design 결정 2). 대신
    // "그 셀이 결과에 들어오는가"를 여기서 못박는다 — 결정 3(빈 셀도
    // 내보낸다)이 없으면 커서가 빈 자리에 있을 때 조용히 사라진다.
    screen.feed("\x1b[2J\x1b[H");
    screen.feed("XY");
    const with_cursor = try screen.cells(&buf);

    // 커서는 'Y' 다음 칸(col=2, row=0)에 있고 글자가 없다. 기본 색이
    // 맞바뀌어 fg=#102030 bg=#FFFFFF여야 한다.
    var cursor_found = false;
    for (with_cursor) |cell| {
        if (cell.row != 0 or cell.col != 2) continue;
        cursor_found = true;
        if (cell.codepoint != 0 or cell.fg != 0x102030 or cell.bg != 0xFFFFFF) {
            std.debug.print(
                "FAIL: 커서 셀이 cp={d} fg=#{X:0>6} bg=#{X:0>6} (expected cp=0 fg=#102030 bg=#FFFFFF)\n",
                .{ cell.codepoint, cell.fg, cell.bg },
            );
            return error.WrongCursorCell;
        }
        std.debug.print("vt_test: 커서 셀이 반전되어 결과에 들어온다 OK\n", .{});
        break;
    }
    if (!cursor_found) {
        std.debug.print("FAIL: 커서 자리(row=0,col=2) 셀이 결과에 없다\n", .{});
        return error.CursorCellMissing;
    }

    // ── TR-M2: 스크롤백 ───────────────────────────────────────────────
    //
    // 격자를 155x47로 잡는 이유는 **게이트가 실제로 쓰는 크기**이기 때문이다
    // (프레임버퍼 1280x800, 여백 20, 셀 8x16). 가지치기가 페이지 통째로
    // 일어나므로 한 페이지에 몇 줄이 들어가는지가 cols에 달려 있고, 다른
    // 크기로 재면 아래 단언의 여유폭이 뜻을 잃는다.
    const big = try vt.Screen.init(init.io, init.gpa, 155, 47);
    defer big.deinit();

    var line: [32]u8 = undefined;
    var fed: usize = 1;
    while (fed <= 2000) : (fed += 1) {
        big.feed(std.fmt.bufPrint(&line, "L{d}\r\n", .{fed}) catch unreachable);
    }

    var big_buf: [155 * 47]vt.CellGlyph = undefined;
    var text_a: [512]u8 = undefined;
    var text_b: [512]u8 = undefined;

    // ── 1. 한도가 정말 효력을 갖는가 ──────────────────────────────────
    //
    // **design 결정 10이 말한 max_scrollback_lines만으로는 아무 일도
    // 일어나지 않는다.** 기본 max_scrollback_bytes(10,000)가 먼저 걸려서
    // history가 454줄에서 멈춘다 — 2026-08-23에 실측한 값이다. 아래쪽 경계
    // 700이 그 옛 동작을 막는 자리다.
    //
    // 754가 1000이 아닌 것은 정상이다. 가지치기가 페이지 통째로 일어나고
    // (155칸에서 한 페이지가 약 286줄), 1000을 넘는 순간 한 페이지가 통째로
    // 사라져 754로 떨어진다.
    const filled = big.scrollbar();
    const history = filled.total - filled.len;
    std.debug.print("vt_test: history={d} rows (total={d} offset={d} len={d})\n", .{
        history, filled.total, filled.offset, filled.len,
    });
    if (history <= 700 or history > 1000) {
        std.debug.print("FAIL: history {d} rows is outside 700..1000\n", .{history});
        return error.ScrollbackLimitWrong;
    }
    std.debug.print("vt_test: 스크롤백 한도가 효력을 갖는다 OK\n", .{});

    // ── 2. 새 출력 뒤에는 바닥에 있다 ─────────────────────────────────
    //
    // "바닥"의 정의를 여기서 못 박는다. 아래 검사들과 게이트가 전부 이
    // 식(offset == total - len)을 쓴다.
    if (filled.offset != filled.total - filled.len) {
        std.debug.print("FAIL: 먹인 직후인데 바닥이 아니다 (offset={d}, expected {d})\n", .{
            filled.offset, filled.total - filled.len,
        });
        return error.NotAtBottom;
    }
    std.debug.print("vt_test: 먹인 직후에는 바닥에 있다 OK\n", .{});

    // ── 3. .top이 뷰포트를 옮기고 cells()가 따라간다 ──────────────────
    //
    // 위치와 화면을 **따로** 본다. offset만 보면 뷰포트는 움직였는데
    // cells()가 옛 자리를 그대로 읽는 상태를 못 잡는다.
    const at_bottom = try big.cells(&big_buf);
    const bottom_row0 = rowText(at_bottom, 0, &text_a);

    big.scrollToTop();
    const at_top_sb = big.scrollbar();
    if (at_top_sb.offset != 0) {
        std.debug.print("FAIL: .top 뒤에 offset={d} (expected 0)\n", .{at_top_sb.offset});
        return error.TopDidNotScroll;
    }
    const at_top = try big.cells(&big_buf);
    const top_row0 = rowText(at_top, 0, &text_b);
    if (std.mem.eql(u8, top_row0, bottom_row0)) {
        std.debug.print("FAIL: offset은 0인데 화면 첫 줄이 그대로다 ('{s}')\n", .{top_row0});
        return error.CellsDidNotFollowViewport;
    }
    std.debug.print("vt_test: .top이 뷰포트를 옮기고 cells()가 따라간다 OK ('{s}' -> '{s}')\n", .{
        bottom_row0, top_row0,
    });

    // ── 4. .bottom과 delta ────────────────────────────────────────────
    big.scrollToBottom();
    const back = big.scrollbar();
    if (back.offset != back.total - back.len) {
        std.debug.print("FAIL: .bottom 뒤에 offset={d} (expected {d})\n", .{
            back.offset, back.total - back.len,
        });
        return error.BottomDidNotScroll;
    }
    big.scrollByRows(-47);
    const up = big.scrollbar();
    if (up.offset != back.offset - 47) {
        std.debug.print("FAIL: delta -47 뒤에 offset={d} (expected {d})\n", .{
            up.offset, back.offset - 47,
        });
        return error.DeltaDidNotScroll;
    }
    std.debug.print("vt_test: .bottom과 delta가 정확히 움직인다 OK\n", .{});

    // ── 5. 새 출력은 뷰포트를 **안** 내린다 (design 결정 13의 근거) ────
    //
    // 이 단언이 통과한다는 것은 라이브러리가 그 일을 해 주지 않는다는 뜻이고,
    // 그래서 main.zig가 feed 직후에 scrollToBottom()을 불러야 한다. 여기가
    // 뒤집히면(라이브러리가 저절로 내려오면) 결정 13의 코드는 필요 없어지므로,
    // 그때는 plan을 다시 읽어야 한다.
    //
    // 200줄만 먹인 새 화면을 쓰는 이유는 위 big이 이미 한도에 걸려 있어서다.
    // 한도에 걸린 상태로 더 먹이면 가지치기가 일어나 행 번호 자체가 밀리고,
    // 그러면 이 검사가 무엇을 보는지 흐려진다.
    const fresh = try vt.Screen.init(init.io, init.gpa, 155, 47);
    defer fresh.deinit();
    var more: usize = 1;
    while (more <= 200) : (more += 1) {
        fresh.feed(std.fmt.bufPrint(&line, "M{d}\r\n", .{more}) catch unreachable);
    }
    fresh.scrollByRows(-47);
    const before_feed = fresh.scrollbar();
    const before_cells = try fresh.cells(&big_buf);
    const before_row0 = rowText(before_cells, 0, &text_a);

    fresh.feed("NEW\r\nNEW\r\nNEW\r\n");
    const after_cells = try fresh.cells(&big_buf);
    const after_row0 = rowText(after_cells, 0, &text_b);
    if (!std.mem.eql(u8, before_row0, after_row0)) {
        std.debug.print(
            "FAIL: 새 출력이 뷰포트를 저절로 내렸다 ('{s}' -> '{s}'). 결정 13을 다시 볼 것\n",
            .{ before_row0, after_row0 },
        );
        return error.ViewportMovedByItself;
    }
    std.debug.print(
        "vt_test: 새 출력은 뷰포트를 안 내린다 OK (offset={d}에서 '{s}' 그대로)\n",
        .{ before_feed.offset, after_row0 },
    );

    // 그리고 우리가 부르면 내려온다.
    fresh.scrollToBottom();
    const snapped = fresh.scrollbar();
    if (snapped.offset != snapped.total - snapped.len) {
        std.debug.print("FAIL: scrollToBottom 뒤에 offset={d} (expected {d})\n", .{
            snapped.offset, snapped.total - snapped.len,
        });
        return error.SnapFailed;
    }
    std.debug.print("vt_test: 우리가 부르면 바닥으로 돌아온다 OK\n", .{});

    // ── CM-M0: copy 커서 ────────────────────────────────────────────────
    //
    // 이 검사들은 앞의 스크롤백 검사가 만들어 둔 화면 위에서 돈다.

    // 검사 1. 들어가면 커서가 생기고, 나가면 사라진다.
    if (fresh.copyActive()) {
        std.debug.print("FAIL: copy mode was active before we entered\n", .{});
        return error.CopyActiveTooEarly;
    }
    fresh.copyEnter();
    const entered = fresh.copyCursor() orelse return error.NoCopyCursor;
    std.debug.print("copy cursor starts at {d},{d}\n", .{ entered.y, entered.x });

    // 검사 2. 반전. 커서가 앉은 셀은 fg와 bg가 맞바뀌어 나온다.
    //
    // **글자가 없는 셀이어도 나와야 한다** — 반전된 배경이 그릴 것이기
    // 때문이다(TR design 결정 3). 그래서 좌표를 화면 왼쪽 위로 옮겨 놓고 본다.
    fresh.copyExit();
    fresh.copyEnter();
    while (fresh.copyCursor().?.x > 0) try fresh.copyMove(-1, 0);
    while (fresh.copyCursor().?.y > 0) try fresh.copyMove(0, -1);
    var cbuf: [8192]vt.CellGlyph = undefined;
    const copy_cells = try fresh.cells(&cbuf);
    var found = false;
    for (copy_cells) |cell| {
        if (cell.row != 0 or cell.col != 0) continue;
        found = true;
        if (cell.bg != fresh.defaultFg()) {
            std.debug.print(
                "FAIL: cell 0,0 bg={X} but the copy cursor should have made it {X}\n",
                .{ cell.bg, fresh.defaultFg() },
            );
            return error.CursorNotInverted;
        }
    }
    if (!found) {
        std.debug.print("FAIL: cell 0,0 is missing while the copy cursor sits on it\n", .{});
        return error.CursorCellMissing;
    }

    // 검사 3. 맨 윗줄에서 위로 더 가면 **뷰포트가 대신 올라간다.**
    const before = fresh.scrollbar().offset;
    try fresh.copyMove(0, -1);
    const after = fresh.scrollbar().offset;
    if (fresh.copyCursor().?.y != 0) {
        std.debug.print("FAIL: the cursor left row 0 instead of moving the viewport\n", .{});
        return error.CursorEscapedTop;
    }
    if (after >= before) {
        std.debug.print(
            "FAIL: viewport did not move up (offset {d} -> {d})\n",
            .{ before, after },
        );
        return error.ViewportDidNotFollow;
    }
    std.debug.print("copy cursor pushed the viewport {d} -> {d}\n", .{ before, after });

    // 검사 4. 나가면 커서가 사라지고 셸 커서가 돌아온다.
    fresh.copyExit();
    if (fresh.copyActive()) {
        std.debug.print("FAIL: copy mode stayed active after copyExit\n", .{});
        return error.CopyStillActive;
    }
    std.debug.print("vt_test: copy cursor OK\n", .{});

    // ── CM-M1: 선택과 클립보드 ──────────────────────────────────────────
    //
    // 작은 화면을 새로 만든다. 앞의 화면들은 스크롤백 검사가 지나간 뒤라
    // 몇 번째 줄에 무엇이 있는지가 검사마다 달라지고, 그러면 아래 단언들이
    // 무엇을 보는지 흐려진다.
    const cm = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer cm.deinit();
    cm.feed("hello world\r\nsecond line\r\n");
    // **한 프레임을 먼저 그린다.** copyEnter는 셸 커서 자리를 RenderState에서
    // 읽는데(`state.cursor.viewport`), 한 번도 그리지 않은 화면에서는 그 값이
    // null이라 커서가 셸 커서가 아니라 왼쪽 위에서 시작한다. main.zig는 키를
    // 받기 전에 이미 그렸으므로, 검사도 같은 조건에서 시작해야 실제 동작을 본다.
    _ = try cm.cells(&buf);

    // 검사 5. 문자 선택 → 반전 → 복사.
    //
    // 커서는 셸 커서 자리(row 2, col 0)에서 시작하므로 두 번 올라가면 row 0이다.
    cm.copyEnter();
    try cm.copyMove(0, -1);
    try cm.copyMove(0, -1);
    const at = cm.copyCursor() orelse return error.NoCopyCursor;
    if (at.x != 0 or at.y != 0) {
        std.debug.print("FAIL: expected the copy cursor at 0,0 but it is {d},{d}\n", .{ at.y, at.x });
        return error.WrongCopyCursor;
    }
    try cm.copySelect(.char);
    var moved: usize = 0;
    while (moved < 4) : (moved += 1) try cm.copyMove(1, 0);

    // 색을 먼저 본다. **복사보다 렌더를 먼저 보는 이유**는, y가 선택을
    // 지우고 나가기 때문이다.
    //
    // 이 시점의 선택은 col 0..4 = "hello"이고 커서는 col 4다. col 0은
    // 반전되어 있어야 하고, **col 4는 선택과 커서가 겹쳐 두 번 뒤집히므로
    // 기본 색으로 돌아와 있어야 한다.**
    const painted = try cm.cells(&buf);
    var saw_start = false;
    var saw_cursor = false;
    for (painted) |cell| {
        if (cell.row != 0) continue;
        if (cell.col == 0) {
            saw_start = true;
            if (cell.fg != cm.defaultBg() or cell.bg != cm.defaultFg()) {
                std.debug.print(
                    "FAIL: selected cell 0,0 is fg=#{X:0>6} bg=#{X:0>6} (expected the two swapped)\n",
                    .{ cell.fg, cell.bg },
                );
                return error.SelectionNotInverted;
            }
        }
        if (cell.col == 4) {
            saw_cursor = true;
            if (cell.fg != cm.defaultFg() or cell.bg != cm.defaultBg()) {
                std.debug.print(
                    "FAIL: cell 0,4 is fg=#{X:0>6} bg=#{X:0>6}; the cursor inside the selection should cancel out\n",
                    .{ cell.fg, cell.bg },
                );
                return error.DoubleSwapWrong;
            }
        }
    }
    if (!saw_start or !saw_cursor) {
        std.debug.print("FAIL: row 0 is missing col 0 ({}) or col 4 ({})\n", .{ saw_start, saw_cursor });
        return error.SelectedCellMissing;
    }
    std.debug.print("vt_test: 선택이 셀의 색을 맞바꾼다 OK\n", .{});

    const yanked = (try cm.copyYank()) orelse return error.NothingYanked;
    if (!std.mem.eql(u8, yanked, "hello")) {
        std.debug.print("FAIL: yanked '{s}' (expected 'hello')\n", .{yanked});
        return error.WrongClipText;
    }
    if (cm.copyActive()) {
        std.debug.print("FAIL: y did not leave copy mode\n", .{});
        return error.YankDidNotLeave;
    }
    std.debug.print("vt_test: 문자 선택과 y OK ('{s}')\n", .{yanked});

    // 검사 6. **역방향 선택**(design 위험 3). 앵커를 col 4에 두고 왼쪽으로
    // 끌어도 같은 글자가 나와야 한다. 라이브러리가 topLeft/bottomRight로
    // 정렬한다는 것을 여기서 실행으로 확인한다.
    cm.copyEnter();
    try cm.copyMove(0, -1);
    try cm.copyMove(0, -1);
    moved = 0;
    while (moved < 4) : (moved += 1) try cm.copyMove(1, 0);
    try cm.copySelect(.char);
    moved = 0;
    while (moved < 4) : (moved += 1) try cm.copyMove(-1, 0);
    const backward = (try cm.copyYank()) orelse return error.NothingYanked;
    if (!std.mem.eql(u8, backward, "hello")) {
        std.debug.print("FAIL: backward selection yanked '{s}' (expected 'hello')\n", .{backward});
        return error.BackwardSelectionWrong;
    }
    std.debug.print("vt_test: 역방향 선택도 같은 글자를 준다 OK ('{s}')\n", .{backward});

    // 검사 7. 줄 선택. **줄 끝 공백이 트림되어 나오는 것**이 요점이다 —
    // 화면은 20칸이고 글자는 11자다.
    cm.copyEnter();
    try cm.copyMove(0, -1);
    try cm.copySelect(.line);
    const whole_line = (try cm.copyYank()) orelse return error.NothingYanked;
    if (!std.mem.eql(u8, whole_line, "second line")) {
        std.debug.print("FAIL: line selection yanked '{s}' (expected 'second line')\n", .{whole_line});
        return error.LineSelectionWrong;
    }
    std.debug.print("vt_test: 줄 선택이 끝 공백을 트림한다 OK ('{s}')\n", .{whole_line});

    // 검사 8. 같은 방식을 다시 누르면 선택이 풀린다. 풀린 뒤의 y는 아무것도
    // 안 준다. **이것이 없으면 "v는 언제나 새 선택"도 통과한다.**
    cm.copyEnter();
    try cm.copySelect(.char);
    try cm.copySelect(.char);
    if ((try cm.copyYank()) != null) {
        std.debug.print("FAIL: yank found a selection after v toggled it off\n", .{});
        return error.SelectionNotCleared;
    }
    std.debug.print("vt_test: v를 다시 누르면 선택이 풀린다 OK\n", .{});

    // 검사 9. **가지치기 방어**(design 위험 1). 두 겹으로 본다.
    const pruned = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer pruned.deinit();
    var pl: usize = 1;
    while (pl <= 200) : (pl += 1) {
        pruned.feed(std.fmt.bufPrint(&line, "P{d}\r\n", .{pl}) catch unreachable);
    }
    pruned.scrollByRows(-10);
    pruned.copyEnter();
    try pruned.copySelect(.char);

    // (1) 대조군 — 평범한 출력으로는 모드가 안 끊긴다. **이것이 없으면
    //     "언제나 나간다"도 통과한다.**
    pruned.feed("just a line\r\n");
    if (!pruned.copyActive()) {
        std.debug.print("FAIL: an ordinary line of output dropped copy mode\n", .{});
        return error.PruneGuardTooEager;
    }
    if (pruned.copyTakePruned()) {
        std.debug.print("FAIL: an ordinary line of output was reported as pruning\n", .{});
        return error.PruneGuardTooEager;
    }

    // (2) 한도를 넘겨 가지치기를 일으킨다. 한도는 1000줄이다(vt.zig의 init).
    pl = 1;
    while (pl <= 3000) : (pl += 1) {
        pruned.feed(std.fmt.bufPrint(&line, "Q{d}\r\n", .{pl}) catch unreachable);
    }
    if (pruned.copyActive()) {
        std.debug.print("FAIL: pruning did not drop copy mode\n", .{});
        return error.PruneNotDetected;
    }
    if (!pruned.copyTakePruned()) {
        std.debug.print("FAIL: copy mode ended without reporting the pruning\n", .{});
        return error.PruneNotReported;
    }
    if (pruned.copyTakePruned()) {
        std.debug.print("FAIL: copyTakePruned reported the same event twice\n", .{});
        return error.PruneReportedTwice;
    }
    std.debug.print("vt_test: 가지치기가 copy mode를 끊는다 OK\n", .{});

    // ── CM-M2: 클립보드를 되읽는다 ──────────────────────────────────────
    //
    // 검사 10. `clipboard()`가 마지막 y의 결과를 그대로 들고 있다.
    //
    // **검사 8이 아무것도 못 담은 y를 불렀는데도 값이 남아 있어야 한다.**
    // 빈 yank가 클립보드를 지우면 붙여넣기가 조용히 사라지는데, 그 사고는
    // 게이트가 못 본다 — 게이트는 y를 한 번만 누른다.
    const held = cm.clipboard() orelse {
        std.debug.print("FAIL: the clipboard is empty after four yanks\n", .{});
        return error.ClipboardEmpty;
    };
    if (!std.mem.eql(u8, held, "second line")) {
        std.debug.print("FAIL: the clipboard holds '{s}' (expected 'second line')\n", .{held});
        return error.WrongClipboard;
    }

    // 대조군. y를 한 번도 안 부른 화면의 클립보드는 null이다. **이것이 없으면
    // "clipboard()가 언제나 무언가를 준다"도 통과한다.**
    if (pruned.clipboard() != null) {
        std.debug.print("FAIL: a screen that never yanked already has a clipboard\n", .{});
        return error.ClipboardNotEmpty;
    }
    std.debug.print("vt_test: 클립보드를 되읽는다 OK ('{s}')\n", .{held});

    std.debug.print("vt_test: copy selection OK\n", .{});

    // ── CN-M0: 단어 단위 이동 ───────────────────────────────────────────
    //
    // 화면을 따로 만든다. 위의 cm·pruned는 검사가 여럿 지나간 자리라 몇 번째
    // 줄에 무엇이 있는지가 흐려진다(CM-M1이 같은 이유로 cm을 새로 만들었다).
    //
    // 20칸 화면에 "alpha beta gamma"(16자)를 넣으면 자리가 이렇게 된다.
    //
    //   col:  0....4 5 6...9 10 11...15 16......19
    //         alpha  _ beta  _  gamma   (쓰인 적 없음)
    //
    // **공백 둘(col 5, col 10)이 이 검사의 핵심이다.** 라이브러리는 그것도
    // 한 단어로 세므로(plan의 확정 사실 2), 우리 w가 한 번 더 건너뛰지
    // 않으면 아래 첫 단언에서 6이 아니라 5가 나온다.
    const wm = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer wm.deinit();
    wm.feed("alpha beta gamma\r\n");
    // 한 프레임을 먼저 그린다 — copyEnter가 셸 커서 자리를 RenderState에서
    // 읽는다(CM-M1이 배운 것).
    _ = try wm.cells(&buf);
    wm.copyEnter();
    // 셸 커서는 다음 줄(row 1)에 있다. 한 번 올라가면 글자가 있는 줄이다.
    try wm.copyMove(0, -1);

    // 검사 11. `w`가 **다음 단어의 첫 글자**로 간다.
    try wm.copyMoveWord(.next);
    var wc = wm.copyCursor() orelse return error.NoCopyCursor;
    if (wc.y != 0 or wc.x != 6) {
        std.debug.print(
            "FAIL: w landed at row={d} col={d} (expected row=0 col=6, the 'b' of beta)\n",
            .{ wc.y, wc.x },
        );
        return error.WordNextWrong;
    }
    try wm.copyMoveWord(.next);
    wc = wm.copyCursor().?;
    if (wc.x != 11) {
        std.debug.print(
            "FAIL: the second w landed at col {d} (expected 11, the 'g' of gamma)\n",
            .{wc.x},
        );
        return error.WordNextWrong;
    }
    std.debug.print("vt_test: w가 공백 덩어리를 건너뛴다 OK (0 -> 6 -> 11)\n", .{});

    // 검사 12. **쓰이지 않은 자리에 닿으면 움직이지 않는다**(plan 결정 1).
    // gamma가 마지막 단어이고 col 16부터는 한 번도 쓰인 적이 없다.
    //
    // **이 검사가 없으면 "빈 셀을 한 칸씩 기어간다"도 통과한다** — 그 구현은
    // w가 l과 같아지는 구간을 만든다.
    try wm.copyMoveWord(.next);
    wc = wm.copyCursor().?;
    if (wc.x != 11) {
        std.debug.print(
            "FAIL: w walked into the unwritten area (col {d}, expected to stay at 11)\n",
            .{wc.x},
        );
        return error.WordNextRanOff;
    }
    std.debug.print("vt_test: w가 쓰이지 않은 자리에서 멈춘다 OK\n", .{});

    // 검사 13. `b`가 `w`를 정확히 되돌린다.
    try wm.copyMoveWord(.prev);
    wc = wm.copyCursor().?;
    if (wc.x != 6) {
        std.debug.print("FAIL: b landed at col {d} (expected 6)\n", .{wc.x});
        return error.WordPrevWrong;
    }
    try wm.copyMoveWord(.prev);
    wc = wm.copyCursor().?;
    if (wc.x != 0) {
        std.debug.print("FAIL: the second b landed at col {d} (expected 0)\n", .{wc.x});
        return error.WordPrevWrong;
    }
    std.debug.print("vt_test: b가 w를 되돌린다 OK (11 -> 6 -> 0)\n", .{});

    // 검사 14. 줄 맨 앞에서 `b`를 더 눌러도 위로 안 샌다. 이 화면의 row 0
    // 위에는 아무것도 없다.
    try wm.copyMoveWord(.prev);
    wc = wm.copyCursor().?;
    if (wc.y != 0 or wc.x != 0) {
        std.debug.print(
            "FAIL: b escaped the top of the screen to row={d} col={d}\n",
            .{ wc.y, wc.x },
        );
        return error.WordPrevRanOff;
    }
    std.debug.print("vt_test: b가 화면 위로 안 샌다 OK\n", .{});

    // 검사 15. **단어 중간에서 b는 그 단어의 시작으로 간다**(plan 결정 2).
    //
    // col 0에서 오른쪽으로 여덟 칸 = beta의 't'(col 8). 거기서 b는 col 6이다.
    // **이 검사가 없으면 "언제나 이전 단어로 간다"도 통과하고**, 그러면 w로
    // 간 자리에서 b를 눌러도 원래 자리로 안 돌아온다.
    var step: usize = 0;
    while (step < 8) : (step += 1) try wm.copyMove(1, 0);
    try wm.copyMoveWord(.prev);
    wc = wm.copyCursor().?;
    if (wc.x != 6) {
        std.debug.print(
            "FAIL: b from the middle of 'beta' landed at col {d} (expected 6)\n",
            .{wc.x},
        );
        return error.WordPrevMidWrong;
    }
    std.debug.print("vt_test: 단어 중간의 b가 그 단어 앞으로 간다 OK\n", .{});

    // 검사 16. **선택 중이면 함께 넓힌다**(design 결정 11).
    //
    // col 6('b')에서 v로 잡고 w를 누르면 커서가 col 11로 가고, 선택은
    // col 6..11이 된다. **끝 셀이 포함되므로 여섯 자다** — "beta g".
    // 게이트는 이 왕복을 안 본다(plan 결정 3). 여기가 유일한 자리다.
    try wm.copySelect(.char);
    try wm.copyMoveWord(.next);
    const grabbed = (try wm.copyYank()) orelse return error.NothingYanked;
    if (!std.mem.eql(u8, grabbed, "beta g")) {
        std.debug.print(
            "FAIL: v then w yanked '{s}' (expected 'beta g')\n",
            .{grabbed},
        );
        return error.WordSelectionWrong;
    }
    std.debug.print("vt_test: 선택이 w를 따라 넓어진다 OK ('{s}')\n", .{grabbed});

    // ── CN-M1: 검색 프롬프트 ────────────────────────────────────────────
    //
    // 화면을 따로 만든다(CM-M1 이래의 규율). 여기서는 버퍼만 보므로 작아도 된다.
    const fm = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer fm.deinit();
    fm.feed("hello\r\n");
    _ = try fm.cells(&buf);

    // 검사 17. **copy mode가 아니면 프롬프트가 안 열린다.**
    fm.findOpen();
    if (fm.findNeedle() != null) {
        std.debug.print("FAIL: the find prompt opened outside copy mode\n", .{});
        return error.FindOpenedOutsideCopy;
    }

    // 검사 18. 열고, 치고, 지운다.
    fm.copyEnter();
    fm.findOpen();
    fm.findChar('a');
    fm.findChar('b');
    fm.findChar('c');
    var needle = fm.findNeedle() orelse return error.NoFindPrompt;
    if (!std.mem.eql(u8, needle, "abc")) {
        std.debug.print("FAIL: the prompt holds '{s}' (expected 'abc')\n", .{needle});
        return error.FindNeedleWrong;
    }
    fm.findErase();
    needle = fm.findNeedle().?;
    if (!std.mem.eql(u8, needle, "ab")) {
        std.debug.print("FAIL: backspace left '{s}' (expected 'ab')\n", .{needle});
        return error.FindEraseWrong;
    }
    std.debug.print("vt_test: 프롬프트가 글자를 받고 지운다 OK ('{s}')\n", .{needle});

    // 검사 19. **빈 프롬프트에서 Backspace는 프롬프트를 안 닫는다**
    // (plan 결정 2). 이 검사가 없으면 "비면 닫는다"도 통과하고, 그러면
    // 지우려고 연타하던 사람이 마지막 한 번에 프롬프트를 잃는다.
    fm.findErase();
    fm.findErase();
    fm.findErase();
    needle = fm.findNeedle() orelse {
        std.debug.print("FAIL: backspace closed an empty prompt\n", .{});
        return error.FindEraseClosedPrompt;
    };
    if (needle.len != 0) {
        std.debug.print("FAIL: the prompt should be empty, holds '{s}'\n", .{needle});
        return error.FindEraseWrong;
    }
    std.debug.print("vt_test: 빈 프롬프트의 Backspace가 안 닫는다 OK\n", .{});

    // 검사 20. **버퍼가 넘쳐도 무너지지 않는다**(design 결정 8). 128자를 채우고
    // 스무 자를 더 친다.
    var fill: usize = 0;
    while (fill < 148) : (fill += 1) fm.findChar('z');
    needle = fm.findNeedle().?;
    if (needle.len != 128) {
        std.debug.print("FAIL: the needle grew to {d} (expected to stop at 128)\n", .{needle.len});
        return error.FindNeedleOverflow;
    }
    std.debug.print("vt_test: 검색어가 128자에서 멈춘다 OK\n", .{});

    // 검사 21. **copyExit이 프롬프트도 닫는다**(design 결정 10). 안 닫으면
    // 모드를 다시 열었을 때 지난 검색어가 화면에 남는다.
    fm.copyExit();
    if (fm.findNeedle() != null) {
        std.debug.print("FAIL: copyExit left the find prompt open\n", .{});
        return error.FindSurvivedCopyExit;
    }
    std.debug.print("vt_test: copyExit이 프롬프트를 닫는다 OK\n", .{});

    // 검사 22~25. **실제로 찾아서 커서를 옮긴다.**
    //
    // 스크롤백을 가진 화면을 새로 만든다. 20칸 5줄에 60줄을 먹이면 위쪽
    // 55줄이 history로 간다.
    //
    //   L1 … L9  MARK  L11 … L29  MARK  L31 … L60
    //            (10)            (30)
    //
    // **MARK가 둘인 것이 요점이다.** 하나면 `n`이 감기는지 옮기는지 갈리지
    // 않는다.
    const fs = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer fs.deinit();
    var fl: usize = 1;
    while (fl <= 60) : (fl += 1) {
        if (fl == 10 or fl == 30) {
            fs.feed("MARK\r\n");
        } else {
            fs.feed(std.fmt.bufPrint(&line, "L{d}\r\n", .{fl}) catch unreachable);
        }
    }
    _ = try fs.cells(&buf);
    fs.copyEnter();

    // 검사 22. `/MARK` + Enter가 **가장 최근** MARK(30번째 줄)로 간다.
    fs.findOpen();
    for ("MARK") |ch| fs.findChar(ch);
    const hit = try fs.findSubmit();
    if (hit.matches != 2) {
        std.debug.print("FAIL: found {d} match(es) for MARK (expected 2)\n", .{hit.matches});
        return error.FindMatchCountWrong;
    }
    if (!hit.moved) {
        std.debug.print("FAIL: the cursor did not move to a match\n", .{});
        return error.FindDidNotMove;
    }
    // 커서가 선 줄의 글자를 읽어 확인한다. **좌표가 아니라 내용을 본다** —
    // 뷰포트가 어디로 밀렸는지는 화면 크기에 딸린 값이라 바뀌기 쉽다.
    var cur = fs.copyCursor() orelse return error.NoCopyCursor;
    var text = rowText(try fs.cells(&buf), cur.y, &line);
    if (!std.mem.startsWith(u8, text, "MARK")) {
        std.debug.print("FAIL: / landed on '{s}' (expected a MARK row)\n", .{text});
        return error.FindLandedWrong;
    }
    std.debug.print("vt_test: /가 매치로 커서를 옮긴다 OK (matches={d})\n", .{hit.matches});

    // 검사 23. **프롬프트가 닫혔다.** Enter가 안 닫으면 그 뒤의 키가 전부
    // 글자가 되어 copy mode가 먹통이 된다.
    if (fs.findNeedle() != null) {
        std.debug.print("FAIL: Enter left the find prompt open\n", .{});
        return error.FindSubmitLeftPromptOpen;
    }

    // 검사 24. `n`이 **더 위의** MARK(10번째 줄)로 간다.
    const prev_y = fs.scrollbar().offset + cur.y;
    if (!try fs.findNext()) {
        std.debug.print("FAIL: n did not move\n", .{});
        return error.FindNextDidNotMove;
    }
    cur = fs.copyCursor().?;
    text = rowText(try fs.cells(&buf), cur.y, &line);
    if (!std.mem.startsWith(u8, text, "MARK")) {
        std.debug.print("FAIL: n landed on '{s}' (expected a MARK row)\n", .{text});
        return error.FindNextLandedWrong;
    }
    const next_y = fs.scrollbar().offset + cur.y;
    if (next_y >= prev_y) {
        std.debug.print(
            "FAIL: n went down or stayed ({d} -> {d}), expected up\n",
            .{ prev_y, next_y },
        );
        return error.FindNextWrongDirection;
    }
    std.debug.print("vt_test: n이 더 위의 매치로 간다 OK ({d} -> {d})\n", .{ prev_y, next_y });

    // 검사 25. **매치가 없으면 커서가 안 움직인다.**
    //
    // **`before`/`after`라는 이름을 못 쓴다** — 이 파일의 CM-M0 검사가
    // `:327`·`:329`에서 이미 쓰고 있고, Zig는 같은 함수 안의 shadowing을
    // 컴파일 에러로 막는다.
    const miss_from = fs.copyCursor().?;
    fs.findOpen();
    for ("NOSUCHTHING") |ch| fs.findChar(ch);
    const miss = try fs.findSubmit();
    if (miss.matches != 0 or miss.moved) {
        std.debug.print(
            "FAIL: a bogus needle reported matches={d} moved={}\n",
            .{ miss.matches, miss.moved },
        );
        return error.FindFalsePositive;
    }
    const miss_to = fs.copyCursor().?;
    if (miss_to.x != miss_from.x or miss_to.y != miss_from.y) {
        std.debug.print("FAIL: a failed search moved the cursor\n", .{});
        return error.FindMissMovedCursor;
    }
    std.debug.print("vt_test: 매치가 없으면 커서가 안 움직인다 OK\n", .{});

    // ── CS-M0: 매치 하이라이트 ────────────────────────────────────────────
    //
    // **새 화면을 만든다.** 앞의 `fs`는 20x5에 60줄을 먹였고 검사 22~25가 그
    // 커서 자리에 기대고 있다 — 남의 화면에 붙이면 앞 검사가 흔들린다.
    // CM-M1이 `cm`, CM-M2가 `pruned`, CN-M0이 `wm`, CN-M1이 `fm`·`fs`를 새로
    // 만든 것과 같은 규율이다.
    //
    // 표적을 **두 줄**(8번·18번)에 심는다. 5줄짜리 화면이라 한 번에 하나만
    // 보이고, 그래서 "화면에 보이는 것만 칠한다"를 검사가 가를 수 있다.
    const hs = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer hs.deinit();
    var hl_i: usize = 1;
    while (hl_i <= 20) : (hl_i += 1) {
        if (hl_i == 8 or hl_i == 18) {
            hs.feed("xxTARGETxx\r\n");
        } else {
            hs.feed(std.fmt.bufPrint(&line, "R{d}\r\n", .{hl_i}) catch unreachable);
        }
    }
    // **`copyEnter` 전에 한 번 그린다.** `state.cursor.viewport`는 `cells()`가
    // 채우므로, 그 전에 들어가면 커서가 (0,0)에서 시작한다.
    _ = try hs.cells(&buf);
    hs.copyEnter();

    // 검사 26. 보관한 매치 수가 검색이 찾은 수와 같다.
    hs.findOpen();
    for ("TARGET") |ch| hs.findChar(ch);
    const hhit = try hs.findSubmit();
    if (hhit.matches == 0) {
        std.debug.print("FAIL: /TARGET found nothing\n", .{});
        return error.HighlightSearchFoundNothing;
    }
    if (hs.findMatchCount() != hhit.matches) {
        std.debug.print("FAIL: kept {d} match(es) but the search found {d}\n", .{
            hs.findMatchCount(), hhit.matches,
        });
        return error.FindMatchSliceWrong;
    }
    std.debug.print("vt_test: 매치 목록을 그대로 보관한다 OK (matches={d})\n", .{hhit.matches});

    // 검사 27. **다시 검색해도 앞 목록이 이중 해제되지 않는다.**
    //
    // `matches()`가 주는 것은 얕은 복사라(design 결정 6), 원소를 `deinit`하면
    // ScreenSearch가 같은 버퍼를 다시 해제한다. 그 실수는 **두 번째 검색에서**
    // 터진다 — 첫 검색만 하는 검사로는 영영 안 잡힌다.
    hs.findOpen();
    for ("R1") |ch| hs.findChar(ch);
    const hhit2 = try hs.findSubmit();
    if (hs.findMatchCount() != hhit2.matches) {
        std.debug.print("FAIL: after re-searching, kept {d} but found {d}\n", .{
            hs.findMatchCount(), hhit2.matches,
        });
        return error.FindMatchSliceStale;
    }
    std.debug.print("vt_test: 다시 검색해도 매치 목록이 온전하다 OK (matches={d})\n", .{hhit2.matches});

    // 아래 검사들이 볼 수 있게 목록을 TARGET으로 되돌린다.
    hs.findOpen();
    for ("TARGET") |ch| hs.findChar(ch);
    _ = try hs.findSubmit();

    // 검사 28. **화면에 보이는 매치 하나만 범위가 된다.**
    //
    // `copyPlace`가 뷰포트 위의 매치를 화면 맨 윗줄로 올리므로(`vt.zig:748`)
    // `/`가 끝난 자리에서 매치는 언제나 row 0이다. 표적을 두 줄에 심었지만
    // 화면이 5줄이라 한 번에 하나만 보인다 — 그것이 이 검사의 요점이다.
    //
    // **`cells()`를 부르고 나서 본다.** 범위는 그 안에서 만들어진다.
    _ = try hs.cells(&buf);
    const hspans = hs.hlSpans();
    if (hspans.len != 1) {
        std.debug.print("FAIL: {d} span(s) in view (expected 1)\n", .{hspans.len});
        for (hspans) |sp| {
            std.debug.print("  span row={d} x0={d} x1={d}\n", .{ sp.row, sp.x0, sp.x1 });
        }
        return error.HighlightSpanCountWrong;
    }
    // `xxTARGETxx`에서 TARGET은 x=2..7이다.
    if (hspans[0].row != 0 or hspans[0].x0 != 2 or hspans[0].x1 != 7) {
        std.debug.print("FAIL: span is row={d} x0={d} x1={d} (expected 0,2,7)\n", .{
            hspans[0].row, hspans[0].x0, hspans[0].x1,
        });
        return error.HighlightSpanWrong;
    }
    const hstats = hs.hlStats() orelse {
        std.debug.print("FAIL: hlStats() was null while a search was live\n", .{});
        return error.HighlightStatsMissing;
    };
    if (hstats.cells != 6) {
        std.debug.print("FAIL: highlight covered {d} cell(s) (expected 6)\n", .{hstats.cells});
        return error.HighlightCellCountWrong;
    }
    std.debug.print("vt_test: 보이는 매치만 범위가 된다 OK (spans={d} cells={d})\n", .{
        hstats.spans, hstats.cells,
    });

    // 검사 29. **매치 셀의 바탕이 MATCH_BG다.**
    //
    // 범위를 옳게 풀고도 색을 안 넣을 수 있다 — 검사 28과 이 검사가 그 둘을
    // 가른다.
    // **여섯이 아니라 다섯이다.** `/` 뒤 copy 커서는 매치의 첫 칸에 서 있고
    // (`copyPlace`가 `top_x`로 옮긴다), 커서는 매치 **위에** 얹히는 층이라 그
    // 한 칸이 또 한 번 맞바뀐다 — `fg=MATCH_BG, bg=기본`이 되어 아래 `hcnt`에서
    // 빠진다. **그 한 칸을 따로 세는 것이 이 검사의 요점이다**: 여섯 번째가
    // 조용히 사라진 것과 커서가 뒤집은 것은 다른 일이고, `hcnt`만 보면 안 갈린다.
    //
    // 칠하기 **전**의 수가 여섯인 것은 검사 28의 `cells=6`이 이미 확인했다.
    var hcnt: usize = 0;
    var hcursor: usize = 0;
    for (try hs.cells(&buf)) |c| {
        // 이름이 `painted`가 아닌 이유: CM-M0의 검사가 `:386`에서 그 이름을
        // 쓰고 있고, `main()` 하나가 파일 전체라 Zig가 shadowing을 막는다.
        // **SP-M0이 색을 바꿨다.** 이 화면은 매치가 하나만 보이고 그 하나가 곧
        // 현재 매치이므로, 여기 칠해지는 것은 `MATCH_BG`가 아니라 `CURRENT_BG`다.
        // **`MATCH_BG` 쪽을 보는 검사는 `ps` 화면의 검사 39가 이어받는다** — 매치가
        // 둘 이상 보여야 두 색이 함께 나오기 때문이다.
        const hpaint = c.bg == vt.CURRENT_BG or c.fg == vt.CURRENT_BG;
        if (!hpaint) continue;
        if (c.row != 0 or c.col < 2 or c.col > 7) {
            std.debug.print("FAIL: painted a cell outside the match at {d},{d}\n", .{
                c.row, c.col,
            });
            return error.HighlightPaintedWrongCell;
        }
        if (c.bg == vt.CURRENT_BG) hcnt += 1 else hcursor += 1;
    }
    if (hcnt != 5 or hcursor != 1) {
        std.debug.print("FAIL: {d} plain + {d} inverted match cell(s) (expected 5 + 1)\n", .{
            hcnt, hcursor,
        });
        return error.HighlightPaintCountWrong;
    }
    std.debug.print("vt_test: 현재 매치 셀의 바탕이 CURRENT_BG다 OK (plain={d} cursor={d})\n", .{
        hcnt, hcursor,
    });

    // 검사 30. **선택 안의 매치는 맞바뀌어 여전히 갈린다.**
    //
    // 매치를 맞바꿈으로 만들었다면 여기서 두 번 뒤집혀 기본 색으로 돌아왔을
    // 것이고, 이 검사가 그것을 잡는다. 커서가 매치의 첫 칸에 서 있으므로
    // (`copyPlace`가 `top_x`로 옮긴다) **그 한 칸은 또 한 번 맞바뀐다** — 그래서
    // 뒤집힌 매치 셀은 여섯이 아니라 다섯이다.
    try hs.copySelect(.line);
    var hswapped: usize = 0;
    for (try hs.cells(&buf)) |c| {
        // **상수만 옮긴다.** 이 검사가 보는 것은 색의 값이 아니라 **"맞바꿈이
        // 아니라 값을 정하는 층인가"**이므로, 상수를 옮겨도 뜻이 그대로 남는다.
        if (c.fg == vt.CURRENT_BG and c.bg != vt.CURRENT_BG) hswapped += 1;
    }
    if (hswapped != 5) {
        std.debug.print("FAIL: {d} match cell(s) survived the selection (expected 5)\n", .{
            hswapped,
        });
        return error.HighlightUnderSelectionWrong;
    }
    std.debug.print("vt_test: 선택 안의 매치가 맞바뀌어 남는다 OK (cells={d})\n", .{hswapped});

    // 검사 31. **copy mode를 나가면 하이라이트가 사라진다.**
    //
    // `copyExit`이 `find_matches`를 안 버리면 여기서 잡힌다. 게이트의 음성
    // 검사와 같은 것을 보지만, 이쪽이 훨씬 빨리 실패를 알려준다.
    hs.copyExit();
    var hleft: usize = 0;
    for (try hs.cells(&buf)) |c| {
        // **두 색을 함께 센다**(SP-M0). 한 색만 보면, 이 화면처럼 그 색이 애초에
        // 안 쓰이는 경우에 **아무것도 안 보는 검사**가 된다.
        const hgone = c.bg == vt.MATCH_BG or c.fg == vt.MATCH_BG or
            c.bg == vt.CURRENT_BG or c.fg == vt.CURRENT_BG;
        if (hgone) hleft += 1;
    }
    if (hleft != 0) {
        std.debug.print("FAIL: {d} highlighted cell(s) survived copyExit\n", .{hleft});
        return error.HighlightSurvivedExit;
    }
    if (hs.hlStats() != null) {
        std.debug.print("FAIL: hlStats() was not null after copyExit\n", .{});
        return error.HighlightStatsSurvivedExit;
    }
    std.debug.print("vt_test: copy mode를 나가면 하이라이트가 사라진다 OK\n", .{});

    // ── CS-M1: 검색 기록과 "못 찾았다" 메시지 ─────────────────────────────
    //
    // **새 화면을 만든다.** 앞의 `hs`는 검사 31에서 `copyExit`으로 끝났고 그
    // 상태에 검사 넷이 기대고 있다 — 남의 화면에 붙이면 앞 검사가 흔들린다.
    // CM-M1이 `cm`, CM-M2가 `pruned`, CN-M0이 `wm`, CN-M1이 `fm`·`fs`,
    // CS-M0이 `hs`를 새로 만든 것과 같은 규율이다.
    //
    // 화면 모양은 `hs`와 같다(20x5, 8번과 18번 줄이 표적). 같은 모양을 쓰는
    // 것은 게으름이 아니라 **기대값을 옮겨 쓸 수 있게 하려는 것**이다 —
    // 검사 26이 확정한 `matches=2`를 여기서 다시 세지 않아도 된다.
    const ls = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer ls.deinit();
    var ls_i: usize = 1;
    while (ls_i <= 20) : (ls_i += 1) {
        if (ls_i == 8 or ls_i == 18) {
            ls.feed("xxTARGETxx\r\n");
        } else {
            ls.feed(std.fmt.bufPrint(&line, "R{d}\r\n", .{ls_i}) catch unreachable);
        }
    }
    // **`copyEnter` 전에 한 번 그린다.** `state.cursor.viewport`는 `cells()`가
    // 채우므로, 그 전에 들어가면 커서가 (0,0)에서 시작한다.
    _ = try ls.cells(&buf);
    ls.copyEnter();

    // 검사 32. **빈 Enter가 지난 검색어를 다시 쓴다.**
    ls.findOpen();
    for ("TARGET") |ch| ls.findChar(ch);
    const lhit = try ls.findSubmit();
    if (lhit.matches == 0) {
        std.debug.print("FAIL: /TARGET found nothing\n", .{});
        return error.HistorySearchFoundNothing;
    }
    ls.findOpen();
    // 글자를 하나도 안 치고 곧바로 Enter다.
    const lhit2 = try ls.findSubmit();
    if (lhit2.matches != lhit.matches) {
        std.debug.print("FAIL: the empty Enter found {d} (expected the previous {d})\n", .{
            lhit2.matches, lhit.matches,
        });
        return error.EmptySubmitDidNotRepeat;
    }
    std.debug.print("vt_test: 빈 Enter가 지난 검색어를 다시 쓴다 OK (matches={d})\n", .{lhit2.matches});

    // 검사 33. **copy mode를 나갔다 들어와도 검색어가 남는다.**
    //
    // `copyExit`은 `find`·`find_matches`·`find_buf`를 전부 버린다 —
    // **`find_last`만 안 버린다**(design 결정 8). 그 하나가 이 기능의 전부이고,
    // 실수로 함께 지우면 여기서 `matches=0`이 되어 잡힌다.
    ls.copyExit();
    ls.copyEnter();
    ls.findOpen();
    const lhit3 = try ls.findSubmit();
    if (lhit3.matches != lhit.matches) {
        std.debug.print("FAIL: after leaving copy mode the empty Enter found {d} (expected {d})\n", .{
            lhit3.matches, lhit.matches,
        });
        return error.HistoryLostOnExit;
    }
    std.debug.print("vt_test: copy mode를 나갔다 들어와도 검색어가 남는다 OK (matches={d})\n", .{lhit3.matches});

    // 검사 34. **못 찾으면 메시지가 켜지고 그 검색어를 준다.**
    if (ls.findMissed() != null) {
        std.debug.print("FAIL: the not-found message was on before any search failed\n", .{});
        return error.MissedFlagStuckOn;
    }
    ls.findOpen();
    for ("NOPE") |ch| ls.findChar(ch);
    const lhit4 = try ls.findSubmit();
    if (lhit4.matches != 0) {
        std.debug.print("FAIL: /NOPE found {d} match(es) (expected none)\n", .{lhit4.matches});
        return error.MissedSearchFoundSomething;
    }
    const lmiss = ls.findMissed() orelse {
        std.debug.print("FAIL: findMissed() was null after a search found nothing\n", .{});
        return error.MissedFlagNotSet;
    };
    if (!std.mem.eql(u8, lmiss, "NOPE")) {
        std.debug.print("FAIL: findMissed() gave '{s}' (expected 'NOPE')\n", .{lmiss});
        return error.MissedNeedleWrong;
    }
    std.debug.print("vt_test: 못 찾으면 메시지가 그 검색어를 준다 OK (needle={s})\n", .{lmiss});

    // 검사 35. **메시지를 끄면 사라지고, 못 찾은 검색어도 기록에는 남는다.**
    //
    // 뒷부분이 design 결정 8의 "성공·실패와 무관하게 남긴다"를 보는 자리다.
    // **판정을 `matches`로 하면 안 된다** — 되부른 `NOPE`도 0을 내고 "아무 일도
    // 안 했다"도 0을 내서 둘이 안 갈린다. `findMissed()`가 다시 `NOPE`를 주는
    // 것이 "정말로 되불렀다"의 증거다.
    ls.findClearStatus();
    if (ls.findMissed() != null) {
        std.debug.print("FAIL: findClearStatus() did not turn the message off\n", .{});
        return error.MissedFlagNotCleared;
    }
    ls.findOpen();
    const lhit5 = try ls.findSubmit();
    if (lhit5.matches != 0) {
        std.debug.print("FAIL: the empty Enter found {d} (expected none)\n", .{lhit5.matches});
        return error.FailedNeedleNotRemembered;
    }
    const lmiss2 = ls.findMissed() orelse {
        std.debug.print("FAIL: the empty Enter did not re-run the failed needle\n", .{});
        return error.FailedNeedleNotRemembered;
    };
    if (!std.mem.eql(u8, lmiss2, "NOPE")) {
        std.debug.print("FAIL: the empty Enter re-ran '{s}' (expected 'NOPE')\n", .{lmiss2});
        return error.FailedNeedleWrong;
    }
    std.debug.print("vt_test: 못 찾은 검색어도 기록에 남는다 OK (needle={s})\n", .{lmiss2});

    // 검사 36. **copy mode를 나가면 메시지가 꺼진다.**
    //
    // 검사 33이 `find_last`가 **남는** 것을 보고, 이 검사가 `find_status`는
    // **안 남는** 것을 본다. 둘이 같은 함수의 서로 반대되는 두 계약이라 나란히
    // 둔다.
    ls.copyExit();
    if (ls.findMissed() != null) {
        std.debug.print("FAIL: the not-found message survived copyExit\n", .{});
        return error.MissedFlagSurvivedExit;
    }
    std.debug.print("vt_test: copy mode를 나가면 메시지가 꺼진다 OK\n", .{});

    // ── SP-M0: 현재 매치 ────────────────────────────────────────────────
    //
    // **자기 화면을 새로 만든다.** 화면마다 크기와 history가 다르므로 남의
    // 검사에 붙이면 기대값이 흔들린다. `hs`(CS-M0)와 같은 20x5에 같은 8·18번
    // 줄을 표적으로 두는 것은 게으름이 아니라 **기대값을 옮겨 쓰기 위한
    // 것이다** — 다른 것은 8번 줄에 매치가 **둘**이라는 점 하나다.
    //
    // 이름이 `ps`인 이유: `main()` 하나가 파일 전체라 이 파일의 모든 지역
    // 변수가 서로 부딪치고 Zig가 shadowing을 컴파일 에러로 막는다.
    // `cm`·`painted`·`pruned`·`wm`·`fm`·`fs`·`hs`·`ls`가 이미 쓰여 있다.
    const ps = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer ps.deinit();
    var ps_i: usize = 1;
    while (ps_i <= 20) : (ps_i += 1) {
        if (ps_i == 8) {
            // **한 줄에 매치 둘.** 같은 줄이면 뷰포트가 어디에 있든 함께
            // 보이므로, 두 색을 나란히 보는 검사가 스크롤에 안 딸린다.
            ps.feed("qqzqqqzqqq\r\n");
        } else if (ps_i == 18) {
            ps.feed("qqzqqqqqqq\r\n");
        } else {
            ps.feed(std.fmt.bufPrint(&line, "R{d}\r\n", .{ps_i}) catch unreachable);
        }
    }
    // **`copyEnter` 전에 한 번 그린다.** `state.cursor.viewport`는 `cells()`가
    // 채우므로, 그 전에 들어가면 커서가 (0,0)에서 시작한다.
    _ = try ps.cells(&buf);
    ps.copyEnter();

    // 검사 37. **`/` 직후의 인덱스는 0이다.**
    //
    // 라이브러리 주석이 "0 = most recent match"라고 적었고(`SelectedMatch`),
    // `select(.next)`가 선택이 없을 때 인덱스 0을 만든다(`selectNext`의 첫
    // 분기). **그 뜻을 여기서 실행으로 고정한다** — 소스를 읽어 얻은 사실을
    // 검사로 옮기는 규율이고, 이것이 깨지면 SP-M1의 번호가 거꾸로 나온다.
    ps.findOpen();
    for ("zq") |ch| ps.findChar(ch);
    const phit = try ps.findSubmit();
    if (phit.matches != 3) {
        std.debug.print("FAIL: /zq found {d} match(es) (expected 3)\n", .{phit.matches});
        return error.CurrentMatchSetupWrong;
    }
    const pcur = ps.findCurrentIndex() orelse {
        std.debug.print("FAIL: no current index right after the search\n", .{});
        return error.CurrentIndexMissing;
    };
    if (pcur != 0) {
        std.debug.print("FAIL: the first match has index {d} (expected 0)\n", .{pcur});
        return error.CurrentIndexWrong;
    }
    std.debug.print("vt_test: 검색 직후의 현재 매치는 0번이다 OK (matches={d})\n", .{phit.matches});

    // 검사 38. **`n`이 인덱스를 하나 올린다.**
    //
    // 검사 37이 "0에서 시작한다"를 보고 이 검사가 "한 칸씩 간다"를 본다.
    // 둘이 함께 있어야 번호가 뜻을 갖는다 — 시작점만 맞고 걸음이 틀리면
    // `[3/12]`가 조용히 어긋난다.
    if (!try ps.findNext()) {
        std.debug.print("FAIL: n did not move to another match\n", .{});
        return error.CurrentIndexNoMove;
    }
    const pcur2 = ps.findCurrentIndex() orelse {
        std.debug.print("FAIL: no current index after n\n", .{});
        return error.CurrentIndexMissing;
    };
    if (pcur2 != 1) {
        std.debug.print("FAIL: after one n the index is {d} (expected 1)\n", .{pcur2});
        return error.CurrentIndexWrong;
    }
    std.debug.print("vt_test: n이 현재 매치를 한 칸 옮긴다 OK (idx={d})\n", .{pcur2});

    // 검사 39. **두 색이 한 화면에 나란히 있다.**
    //
    // `n`을 한 번 눌렀으므로 현재 매치는 8번 줄의 두 매치 중 하나다.
    // `copyPlace`가 그 줄을 뷰포트 맨 위로 올리므로 **같은 줄의 다른 매치도
    // 함께 보인다** — 한 줄에 둘을 심은 이유가 이것이고, 그래서 이 판정이
    // 스크롤 위치에 안 딸린다.
    //
    // **어느 쪽이 현재 매치인지는 안 본다.** 라이브러리가 한 줄 안의 매치를
    // 어느 순서로 주는지 확인한 적이 없고, 그것에 기대면 검사가 라이브러리의
    // 안 적힌 성질에 딸리게 된다. 왼쪽이든 오른쪽이든 **셈은 똑같다.**
    _ = try ps.cells(&buf);
    const pspans = ps.hlSpans();
    if (pspans.len != 2) {
        std.debug.print("FAIL: {d} span(s) in view (expected 2)\n", .{pspans.len});
        for (pspans) |sp| {
            std.debug.print("  span row={d} x0={d} x1={d} current={}\n", .{
                sp.row, sp.x0, sp.x1, sp.current,
            });
        }
        return error.CurrentSpanCountWrong;
    }
    var cur_n: usize = 0;
    for (pspans) |sp| {
        if (sp.current) cur_n += 1;
    }
    if (cur_n != 1) {
        std.debug.print("FAIL: {d} span(s) marked current (expected exactly 1)\n", .{cur_n});
        return error.CurrentSpanMarkWrong;
    }

    // **셈이 이렇게 갈린다.** needle이 두 글자이므로 매치 하나가 두 칸이다.
    //   - 현재 매치: 첫 칸에 copy 커서가 서서 한 번 더 맞바뀌므로
    //     `bg=CURRENT_BG`가 **하나**, `fg=CURRENT_BG`가 **하나**
    //   - 다른 매치: `bg=MATCH_BG`가 **둘**
    // CS-M0의 검사 29가 `plain=5 cursor=1`로 본 것과 **같은 갈림**이고, HANDOFF의
    // 실측 3("매치 여섯 칸 중 하나는 언제나 뒤집혀 있다")이 여기서도 그대로다.
    var p_cur_plain: usize = 0;
    var p_cur_cursor: usize = 0;
    var p_other: usize = 0;
    for (try ps.cells(&buf)) |c| {
        if (c.bg == vt.CURRENT_BG) p_cur_plain += 1;
        if (c.fg == vt.CURRENT_BG) p_cur_cursor += 1;
        if (c.bg == vt.MATCH_BG) p_other += 1;
    }
    if (p_cur_plain != 1 or p_cur_cursor != 1 or p_other != 2) {
        std.debug.print("FAIL: current plain={d} cursor={d}, other={d} (expected 1, 1, 2)\n", .{
            p_cur_plain, p_cur_cursor, p_other,
        });
        return error.CurrentPaintCountWrong;
    }
    std.debug.print("vt_test: 현재 매치와 나머지가 다른 색이다 OK (cur={d}+{d} other={d})\n", .{
        p_cur_plain, p_cur_cursor, p_other,
    });

    // 검사 40. **`hlStats`의 `cur`이 현재 매치만 센다.**
    //
    // 검사 39는 `cells()`가 내놓은 색을 세고, 이 검사는 `vt.zig`가 **스스로 센
    // 값**을 본다. 둘이 어긋나면 게이트의 `cur=`을 믿을 수 없게 된다 —
    // 게이트는 색을 직접 못 세고 이 숫자에 기댄다.
    //
    // **`cur`은 커서를 모른다.** 커서는 `cells()`가 얹는 층이라 `findSpans`
    // 뒤에 온다. 그래서 `cur=2`이고 화면에 보이는 `bg=CURRENT_BG`는 하나다 —
    // **둘이 다른 것이 정상이고, 그 차이가 정확히 1이다.**
    const pstats = ps.hlStats() orelse {
        std.debug.print("FAIL: hlStats() was null while a search was live\n", .{});
        return error.CurrentStatsMissing;
    };
    if (pstats.cells != 4 or pstats.cur != 2) {
        std.debug.print("FAIL: cells={d} cur={d} (expected 4 and 2)\n", .{
            pstats.cells, pstats.cur,
        });
        return error.CurrentStatsWrong;
    }
    if (pstats.cur != p_cur_plain + p_cur_cursor) {
        std.debug.print("FAIL: cur={d} but the framebuffer shows {d}+{d}\n", .{
            pstats.cur, p_cur_plain, p_cur_cursor,
        });
        return error.CurrentStatsMismatch;
    }
    std.debug.print("vt_test: hlStats의 cur이 현재 매치만 센다 OK (cells={d} cur={d})\n", .{
        pstats.cells, pstats.cur,
    });

    // ── SP-M1: 결과 표시 ────────────────────────────────────────────────
    //
    // **자기 화면을 새로 만든다.** `hs`(CS-M0)·`ls`(CS-M1)와 같은 20x5에 같은
    // 8·18번 줄을 표적으로 두는 것은 게으름이 아니라 **기대값(`matches=2`)을
    // 옮겨 쓰기 위한 것이다.**
    //
    // 이름이 `ns`인 이유: `main()` 하나가 파일 전체라 이 파일의 모든 지역
    // 변수가 서로 부딪치고 Zig가 shadowing을 컴파일 에러로 막는다.
    // `cm`·`painted`·`pruned`·`wm`·`fm`·`fs`·`hs`·`ls`·`ps`가 이미 쓰여 있다.
    const ns = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer ns.deinit();
    var ns_i: usize = 1;
    while (ns_i <= 20) : (ns_i += 1) {
        if (ns_i == 8 or ns_i == 18) {
            ns.feed("xxTARGETxx\r\n");
        } else {
            ns.feed(std.fmt.bufPrint(&line, "R{d}\r\n", .{ns_i}) catch unreachable);
        }
    }
    // **`copyEnter` 전에 한 번 그린다.** `state.cursor.viewport`는 `cells()`가
    // 채우므로, 그 전에 들어가면 커서가 (0,0)에서 시작한다.
    _ = try ns.cells(&buf);
    ns.copyEnter();

    // 검사 41. **성공한 검색이 결과 표시를 켜고, 그것은 "못 찾음"이 아니다.**
    //
    // CS-M1에서는 성공한 검색이 플래그를 **껐다.** SP-M1이 그것을 뒤집으므로
    // 여기가 그 변경의 자리다 — `findStatusNeedle()`은 needle을 주고
    // `findMissed()`는 null이어야 한다. **둘이 같은 플래그 위에 서 있으면서도
    // 서로 다른 답을 내는 것이 결정 5의 요점이다.**
    ns.findOpen();
    for ("TARGET") |ch| ns.findChar(ch);
    const nhit = try ns.findSubmit();
    if (nhit.matches != 2) {
        std.debug.print("FAIL: /TARGET found {d} match(es) (expected 2)\n", .{nhit.matches});
        return error.StatusSetupWrong;
    }
    const nneedle = ns.findStatusNeedle() orelse {
        std.debug.print("FAIL: findStatusNeedle() was null after a search found matches\n", .{});
        return error.StatusFlagNotSet;
    };
    if (!std.mem.eql(u8, nneedle, "TARGET")) {
        std.debug.print("FAIL: findStatusNeedle() gave '{s}' (expected 'TARGET')\n", .{nneedle});
        return error.StatusNeedleWrong;
    }
    if (ns.findMissed() != null) {
        std.debug.print("FAIL: findMissed() was set after a search that found matches\n", .{});
        return error.MissedSetOnSuccess;
    }
    std.debug.print("vt_test: 성공한 검색이 결과 표시를 켠다 OK (needle={s})\n", .{nneedle});

    // 검사 42. **번호의 재료가 맞고 `n`이 그것을 하나 올린다.**
    //
    // `promptText`가 쓰는 값이 정확히 이 둘이다 — `findCurrentIndex() + 1`과
    // `findMatchCount()`. **그 함수는 `main.zig`의 private이라 여기서 못
    // 부르므로**, 재료를 보는 것이 이 파일이 할 수 있는 전부이고 글자 자체는
    // 게이트의 `find> overlay text=`가 본다.
    //
    // 검사 37·38이 `idx`만 보았고 이 검사가 **분모까지** 함께 본다. 분모는
    // 스냅숏에서 오므로(`findMatchCount`), 그것이 `matchesLen()`과 어긋나면
    // `[3/12]`의 뒤 숫자가 조용히 틀린다.
    if (ns.findMatchCount() != 2) {
        std.debug.print("FAIL: findMatchCount()={d} (expected 2)\n", .{ns.findMatchCount()});
        return error.StatusTotalWrong;
    }
    const nidx = ns.findCurrentIndex() orelse {
        std.debug.print("FAIL: no current index right after the search\n", .{});
        return error.StatusIndexMissing;
    };
    if (nidx != 0) {
        std.debug.print("FAIL: the first match has index {d} (expected 0)\n", .{nidx});
        return error.StatusIndexWrong;
    }
    if (!try ns.findNext()) {
        std.debug.print("FAIL: n did not move to another match\n", .{});
        return error.StatusIndexNoMove;
    }
    const nidx2 = ns.findCurrentIndex() orelse {
        std.debug.print("FAIL: no current index after n\n", .{});
        return error.StatusIndexMissing;
    };
    if (nidx2 != 1 or ns.findMatchCount() != 2) {
        std.debug.print("FAIL: after n the numbers are [{d}/{d}] (expected [2/2])\n", .{
            nidx2 + 1, ns.findMatchCount(),
        });
        return error.StatusIndexWrong;
    }
    std.debug.print("vt_test: 번호가 [{d}/{d}]로 간다 OK\n", .{ nidx2 + 1, ns.findMatchCount() });

    // 검사 43. **끄면 사라지고 `n`이 다시 켠다.**
    //
    // 결정 7의 수명이 이것이다 — 다음 키에 사라지고, 그 키가 검색 키면 다시
    // 뜬다. `main.zig`가 `switch`보다 **앞**에서 끄기 때문에 그 순서가 나온다.
    // **여기서는 그 순서를 손으로 흉내 낸다** — poll 루프를 안 거치기 때문이다.
    ns.findClearStatus();
    if (ns.findStatusNeedle() != null) {
        std.debug.print("FAIL: findClearStatus() did not turn the status off\n", .{});
        return error.StatusNotCleared;
    }
    if (!try ns.findNext()) {
        std.debug.print("FAIL: the second n did not move\n", .{});
        return error.StatusIndexNoMove;
    }
    if (ns.findStatusNeedle() == null) {
        std.debug.print("FAIL: n did not turn the status back on\n", .{});
        return error.StatusNotReset;
    }
    std.debug.print("vt_test: 끄면 사라지고 n이 다시 켠다 OK\n", .{});

    // 검사 44. **매치가 없으면 번호가 아니라 "못 찾음"이다**(design 위험 1).
    //
    // 같은 플래그가 켜져 있는데 `findMissed()`가 needle을 주고
    // `findCurrentIndex()`는 null이며 `hlSpans()`는 비어 있다 — **`promptText`의
    // 두 갈래를 가르는 것이 `findMatchCount()` 하나**라는 것을 여기서 못 박는다.
    ns.findOpen();
    for ("NOPE") |ch| ns.findChar(ch);
    const nhit2 = try ns.findSubmit();
    if (nhit2.matches != 0) {
        std.debug.print("FAIL: /NOPE found {d} match(es) (expected none)\n", .{nhit2.matches});
        return error.StatusMissSetupWrong;
    }
    const nmiss = ns.findMissed() orelse {
        std.debug.print("FAIL: findMissed() was null after a search found nothing\n", .{});
        return error.StatusMissNotSet;
    };
    if (!std.mem.eql(u8, nmiss, "NOPE")) {
        std.debug.print("FAIL: findMissed() gave '{s}' (expected 'NOPE')\n", .{nmiss});
        return error.StatusMissNeedleWrong;
    }
    if (ns.findCurrentIndex() != null) {
        std.debug.print("FAIL: there is a current index with no matches\n", .{});
        return error.StatusIndexOnEmpty;
    }
    _ = try ns.cells(&buf);
    if (ns.hlSpans().len != 0) {
        std.debug.print("FAIL: {d} span(s) painted with no matches\n", .{ns.hlSpans().len});
        return error.StatusSpansOnEmpty;
    }
    std.debug.print("vt_test: 매치가 없으면 번호가 아니라 못 찾음이다 OK (needle={s})\n", .{nmiss});

    std.debug.print("PASS\n", .{});
}
