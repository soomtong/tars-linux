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
    while (fresh.copyCursor().?.x > 0) fresh.copyMove(-1, 0);
    while (fresh.copyCursor().?.y > 0) fresh.copyMove(0, -1);
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
    fresh.copyMove(0, -1);
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

    std.debug.print("PASS\n", .{});
}
