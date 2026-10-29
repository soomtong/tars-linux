//! 부분 갱신의 행 비교를 진짜 `vt.Screen`으로 본다(DR-M2 plan 확정 11, design 결정 9).
//!
//! ghostty의 `testIncrementalMatchesFresh`(`src/terminal/render.zig`)를 옮긴 것이다 — 고정 seed로
//! 300회차 동안 무작위 VT 조작을 넣고, 회차마다 `verify.rowStarts` · `verify.dirtyRows`가 낸 dirty
//! 비트를 "행마다 목록을 `row` 필드로 걸러 낸 뒤 셀을 하나씩 비교한" 정답지와 대조한다. 다르다고
//! 한 행은 정말 달라야 하고 같다고 한 행은 정말 같아야 한다. `verify_test`의 가짜 셀이 못 만드는
//! 모양(spacer 뒷칸 · 반전된 커서 칸 · 선택 띠 · 매치 하이라이트 · preedit · 스크롤로 통째로 밀린
//! 화면)이 여기서 나온다.
//!
//! 픽셀 쪽(지우기 · overlay 행 · clip)은 이 검사가 못 닿고 게이트의 verify 모드가 본다(design
//! 결정 9의 "두 검사가 나눠 맡는다").
const std = @import("std");
const vt = @import("vt.zig");
const verify = @import("verify.zig");

/// `main.zig`와 같은 셀 크기. 다르게 두면 커서 띠 · 이미지의 산수가 게스트와 갈린다.
const CELL: vt.CellPx = .{ .w = 8, .h = 16 };
const COLS: u16 = 40;
const ROWS: u16 = 12;
const ROUNDS: usize = 300;
/// 고정이다. 실패하면 메시지에 seed와 회차가 찍히고, 그 둘로 같은 길을 다시 밟을 수 있다.
const SEED: u64 = 0x5441_5253_4452_4d32;

fn fail(comptime fmt: []const u8, args: anytype) error{DirtyTestFailed} {
    std.debug.print("FAIL: " ++ fmt ++ "\n", args);
    return error.DirtyTestFailed;
}

/// 정답지. `r`행의 셀을 두 목록에서 차례로 꺼내 하나씩 비교한다 — `rowStarts`를 안 쓴다.
fn rowEql(a: []const vt.CellGlyph, b: []const vt.CellGlyph, r: u16) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (true) {
        while (i < a.len and a[i].row != r) i += 1;
        while (j < b.len and b[j].row != r) j += 1;
        const a_end = i == a.len;
        const b_end = j == b.len;
        if (a_end or b_end) return a_end and b_end;
        if (!std.meta.eql(a[i], b[j])) return false;
        i += 1;
        j += 1;
    }
}

const HANGUL = [_][]const u8{ "가", "나", "다", "라", "마", "바", "사", "아", "자", "차", "카", "타", "파", "하" };
const HANGUL_CP = [_]u21{ '가', '나', '다', '한', '글' };

/// 조작 하나. 돌려주는 이름은 실패 메시지용이다.
fn step(screen: *vt.Screen, rnd: std.Random, buf: []u8) ![]const u8 {
    switch (rnd.uintLessThan(u8, 26)) {
        // 글자가 가장 흔하다 — 화면이 차야 나머지 조작이 뜻을 가진다.
        0, 1, 2, 3, 4 => {
            const len = rnd.intRangeAtMost(usize, 1, 30);
            for (buf[0..len]) |*ch| ch.* = rnd.intRangeAtMost(u8, 0x20, 0x7e);
            screen.feed(buf[0..len]);
            return "ascii";
        },
        5, 6 => {
            const n = rnd.intRangeAtMost(usize, 1, 8);
            var len: usize = 0;
            for (0..n) |_| {
                const s = HANGUL[rnd.uintLessThan(usize, HANGUL.len)];
                @memcpy(buf[len..][0..s.len], s);
                len += s.len;
            }
            screen.feed(buf[0..len]);
            return "hangul";
        },
        7, 8 => {
            screen.feed("\r\n");
            return "crlf";
        },
        9 => {
            screen.feed("\r");
            return "cr";
        },
        10 => {
            const s = try std.fmt.bufPrint(buf, "\x1b[{d};{d}H", .{ rnd.intRangeAtMost(u16, 1, ROWS), rnd.intRangeAtMost(u16, 1, COLS) });
            screen.feed(s);
            return "cup";
        },
        11, 12 => {
            const s = switch (rnd.uintLessThan(u8, 5)) {
                0 => try std.fmt.bufPrint(buf, "\x1b[3{d}m", .{rnd.uintLessThan(u8, 8)}),
                1 => try std.fmt.bufPrint(buf, "\x1b[4{d}m", .{rnd.uintLessThan(u8, 8)}),
                2 => "\x1b[7m",
                3 => "\x1b[1m",
                else => "\x1b[0m",
            };
            screen.feed(s);
            return "sgr";
        },
        13 => {
            screen.feed(if (rnd.boolean()) "\x1b[K" else "\x1b[2K");
            return "el";
        },
        14 => {
            screen.feed(if (rnd.boolean()) "\x1b[2J" else "\x1b[J");
            return "ed";
        },
        15 => {
            screen.feed(if (rnd.boolean()) "\x1b[?1049h" else "\x1b[?1049l");
            return "altscreen";
        },
        16 => {
            screen.scrollByRows(rnd.intRangeAtMost(isize, -5, 5));
            return "scroll";
        },
        17 => {
            screen.setPreedit(if (rnd.boolean()) HANGUL_CP[rnd.uintLessThan(usize, HANGUL_CP.len)] else null);
            return "preedit";
        },
        18, 19 => {
            if (!screen.copyActive()) {
                screen.copyEnter();
                return "copy enter";
            }
            switch (rnd.uintLessThan(u8, 4)) {
                0, 1 => {
                    try screen.copyMove(rnd.intRangeAtMost(i32, -6, 6), rnd.intRangeAtMost(i32, -3, 3));
                    return "copy move";
                },
                2 => {
                    try screen.copySelect(if (rnd.boolean()) .char else .line);
                    return "copy select";
                },
                else => {
                    screen.copyExit();
                    return "copy exit";
                },
            }
        },
        20, 21 => {
            if (screen.findNeedle() == null) {
                screen.findOpen();
                return "find open";
            }
            switch (rnd.uintLessThan(u8, 4)) {
                0, 1 => {
                    screen.findChar(rnd.intRangeAtMost(u8, 'a', 'f'));
                    return "find char";
                },
                2 => {
                    _ = try screen.findSubmit();
                    return "find submit";
                },
                else => {
                    screen.findCancel();
                    return "find cancel";
                },
            }
        },
        22 => {
            screen.focused = !screen.focused;
            return "focus";
        },
        23 => {
            const s = try std.fmt.bufPrint(buf, "\x1b[{d}{c}", .{ rnd.intRangeAtMost(u8, 1, 4), "@PLMS"[rnd.uintLessThan(usize, 5)] });
            screen.feed(s);
            return "ich/dch/il/dl/su";
        },
        24 => {
            screen.feed(if (rnd.boolean()) "\x1b[?25l" else "\x1b[?25h");
            return "cursor visible";
        },
        else => {
            // 기본 배경 · 전경이 바뀌면 내보내는 셀의 색이 통째로 바뀐다(M2 plan 확정 1의 자리).
            const s = try std.fmt.bufPrint(buf, "\x1b]1{d};#{x:0>6}\x1b\\", .{ rnd.uintLessThan(u8, 2), rnd.int(u24) });
            screen.feed(s);
            return "osc color";
        },
    }
}

pub fn main(init: std.process.Init) !void {
    const screen = try vt.Screen.init(init.io, init.gpa, COLS, ROWS, CELL);
    defer screen.deinit();
    screen.focused = true;

    var prng = std.Random.DefaultPrng.init(SEED);
    const rnd = prng.random();

    // `main.zig`의 `Pane`과 같은 두 벌(plan 확정 5). `shown`이 화면에 있는 쪽이다.
    var bufs: [2][COLS * ROWS]vt.CellGlyph = undefined;
    var starts: [2][ROWS + 1]u32 = undefined;
    var shown: u1 = 0;
    var shown_len: usize = (try screen.cells(&bufs[0])).len;
    if (!verify.rowStarts(vt.CellGlyph, bufs[0][0..shown_len], &starts[0])) return fail("첫 프레임의 행이 오름차순이 아니다", .{});

    var op_buf: [64]u8 = undefined;
    var dirty_rows_total: usize = 0;
    var dirty_frames: usize = 0;
    var round: usize = 0;
    while (round < ROUNDS) : (round += 1) {
        const op = try step(screen, rnd, &op_buf);
        const next = shown ^ 1;
        const cur = try screen.cells(&bufs[next]);
        if (!verify.rowStarts(vt.CellGlyph, cur, &starts[next])) return fail("seed {x} 회차 {d} ({s}): 행이 오름차순이 아니다", .{ SEED, round, op });

        var dirty: [ROWS]bool = undefined;
        const n = verify.dirtyRows(vt.CellGlyph, bufs[shown][0..shown_len], &starts[shown], cur, &starts[next], &dirty);
        var truth_n: u16 = 0;
        for (0..ROWS) |r| {
            const truth = !rowEql(bufs[shown][0..shown_len], cur, @intCast(r));
            if (truth != dirty[r]) return fail("seed {x} 회차 {d} ({s}): {d}행 dirty={} 정답 {}", .{ SEED, round, op, r, dirty[r], truth });
            if (truth) truth_n += 1;
        }
        if (n != truth_n) return fail("seed {x} 회차 {d} ({s}): n={d} 정답 {d}", .{ SEED, round, op, n, truth_n });
        dirty_rows_total += n;
        if (n > 0) dirty_frames += 1;
        shown = next;
        shown_len = cur.len;
    }
    // 조작이 화면을 바꾸지 않는 회차(같은 자리에 같은 SGR 등)가 있으니 dirty가 0인 프레임도 있다.
    // 그러나 전부 0이거나 전부 전체이면 검사가 아무것도 안 본 것이다.
    if (dirty_rows_total == 0) return fail("300회차에 dirty 행이 하나도 없다", .{});
    if (dirty_rows_total == ROUNDS * ROWS) return fail("300회차가 전부 모든 행 dirty다", .{});
    std.debug.print("dirty_test: {d}회차 OK — dirty 행 합 {d}, dirty 프레임 {d}, 마지막 셀 {d}개 (seed {x})\n", .{
        ROUNDS, dirty_rows_total, dirty_frames, shown_len, SEED,
    });
}
