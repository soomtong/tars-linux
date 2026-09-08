const std = @import("std");
const hangul = @import("hangul.zig");
const input = @import("input.zig");
const status = @import("status.zig");

/// 상태 하나를 넣고 나온 줄을 본다.
///
/// **`input.State`를 통째로 넘긴다**(design 결정 5). 필드를 넷 늘어놓으면
/// 부르는 자리마다 순서를 틀릴 수 있고, IS-M1이 `caps_lock`을 더할 때 이
/// 헬퍼의 시그니처가 또 바뀐다.
fn expectText(state: input.State, want: []const u8) !void {
    var buf: [status.MAX_LEN]u8 = undefined;
    const got = status.statusText(&state, &buf);
    if (std.mem.eql(u8, got, want)) {
        std.debug.print("status_test: \"{s}\" OK\n", .{got});
        return;
    }
    std.debug.print("FAIL: got \"{s}\", want \"{s}\"\n", .{ got, want });
    return error.WrongStatusText;
}

/// 상태 줄의 검사. **부팅도 폰트도 프레임버퍼도 안 쓴다** — 상태를 넣고
/// 문자열을 받는 순수 계산이다.
pub fn main() !void {
    // ── 검사 1: 기본값 ───────────────────────────────────────────────
    //
    // `input.State`의 기본값은 한/영 꺼짐 · `shin_pcs` · `qwerty`다.
    // **이 줄이 곧 아무 설정도 없는 부팅의 화면이다.**
    try expectText(.{}, "EN  신세벌 PCS  쿼티");

    // ── 검사 2: 한/영이 첫 칸을 가른다 ───────────────────────────────
    try expectText(.{ .hangul_on = true }, "한  신세벌 PCS  쿼티");

    // ── 검사 3~6: 한글 자판 넷의 이름 ────────────────────────────────
    //
    // **자판 이름 표를 옮겨 적는 것이 이 milestone의 유일한 "사람이 읽고
    // 다시 적는" 자리다**(HI-M2 실측 6). 넷을 전부 못 박는다.
    try expectText(.{ .hangul_layout = .dubeol }, "EN  두벌식  쿼티");
    try expectText(.{ .hangul_layout = .sebeol_3p3 }, "EN  공세벌 3-P3  쿼티");
    try expectText(.{ .hangul_layout = .shin_p2 }, "EN  신세벌 P2  쿼티");
    try expectText(.{ .hangul_layout = .shin_pcs }, "EN  신세벌 PCS  쿼티");

    // ── 검사 7~8: 영문 자판 둘의 이름 ────────────────────────────────
    try expectText(.{ .latin_layout = .qwerty }, "EN  신세벌 PCS  쿼티");
    try expectText(.{ .latin_layout = .dvorak }, "EN  신세벌 PCS  드보락");

    // ── 검사 9: 칸이 언제나 셋이다 ───────────────────────────────────
    //
    // **자리가 고정인 것이 결정 2다.** 칸이 사라지거나 밀리면 사람도
    // 게이트도 매번 다른 자리를 봐야 한다. 두 칸 공백으로 갈라 센다.
    {
        var buf: [status.MAX_LEN]u8 = undefined;
        const line = status.statusText(&input.State{ .hangul_on = true }, &buf);
        var it = std.mem.splitSequence(u8, line, "  ");
        var fields: usize = 0;
        while (it.next()) |f| {
            if (f.len == 0) {
                std.debug.print("FAIL: empty field in \"{s}\"\n", .{line});
                return error.EmptyStatusField;
            }
            fields += 1;
        }
        if (fields != 3) {
            std.debug.print("FAIL: {d} field(s) in \"{s}\", want 3\n", .{ fields, line });
            return error.WrongStatusFieldCount;
        }
        std.debug.print("status_test: 3 fields OK\n", .{});
    }

    // ── 검사 10: 가장 긴 줄이 `MAX_LEN`과 **정확히** 같다 ────────────
    //
    // 크거나 같은지가 아니라 **같은지**를 본다. `MAX_LEN`은 이름 표에서
    // comptime에 센 값이므로, 정확히 안 맞는다는 것은 산수와 표가 어긋났다는
    // 뜻이다 — 버퍼가 남아도는 것도 사고의 신호다.
    //
    // 가장 긴 조합은 `한`(3, `EN`보다 길다) + `공세벌 3-P3`(14) +
    // `드보락`(9) + 공백 넷이다.
    {
        var buf: [status.MAX_LEN]u8 = undefined;
        const line = status.statusText(&input.State{
            .hangul_on = true,
            .hangul_layout = .sebeol_3p3,
            .latin_layout = .dvorak,
        }, &buf);
        if (line.len != status.MAX_LEN) {
            std.debug.print("FAIL: longest line is {d} byte(s), MAX_LEN is {d}\n", .{
                line.len, status.MAX_LEN,
            });
            return error.WrongMaxLen;
        }
        std.debug.print("status_test: longest line is exactly MAX_LEN={d} OK\n", .{
            status.MAX_LEN,
        });
    }

    // ── 검사 11: 자판이 아직 넷이다 ─────────────────────────────────
    //
    // **검사 3~6이 낡았는지를 보는 자리다.** 위의 넷은 이름을 하나씩 못
    // 박지만 "빠진 자판이 없다"는 말하지 않는다 — 다섯째가 들어오면
    // `hangulName`의 `switch`가 컴파일 에러로 막고, 그 에러를 고친 사람이
    // **검사도 하나 더해야 한다**는 것을 이 줄이 알려 준다.
    if (std.enums.values(hangul.Layout).len != 4) {
        std.debug.print("FAIL: {d} hangul layout(s), but only 4 are checked above\n", .{
            std.enums.values(hangul.Layout).len,
        });
        return error.LayoutCountChanged;
    }

    std.debug.print("status_test: all checks passed\n", .{});
}
