const std = @import("std");
const hangul = @import("hangul.zig");

/// 한글 오토마타의 검사. **부팅도 폰트도 안 쓴다** — 자모를 넣고 코드포인트를
/// 받는 순수 계산이라 게스트가 볼 것이 하나도 없다. 그래서 `main`이
/// `std.process.Init`를 안 받는다(`vt_test`·`font_test`와 갈리는 자리다).
pub fn main() !void {
    // ── 1. 그릴 수 있는 네 상태 ───────────────────────────────────────
    const Want = struct { s: hangul.Syllable, cp: u21, what: []const u8 };
    const wants = [_]Want{
        .{ .s = .{ .cho = 3 }, .cp = 'ㄷ', .what = "초성만은 호환 자모" },
        .{ .s = .{ .jung = 0 }, .cp = 'ㅏ', .what = "중성만은 호환 자모" },
        .{ .s = .{ .cho = 3, .jung = 0 }, .cp = '다', .what = "초성+중성은 완성형" },
        .{ .s = .{ .cho = 3, .jung = 0, .jong = 4 }, .cp = '단', .what = "받침까지 완성형" },
    };
    for (wants) |want| {
        const got = want.s.codepoint();
        if (got == null or got.? != want.cp) {
            std.debug.print("FAIL: {s}: got {?d}, want U+{X}\n", .{ want.what, got, want.cp });
            return error.WrongCodepoint;
        }
        std.debug.print("hangul_test: {s} OK\n", .{want.what});
    }

    // ── 2. 그릴 수 없는 세 상태 (design 결정 3) ───────────────────────
    //
    // **모아주기를 뺀 것이 여기서 코드가 된다.** 완성형에 없는 조합이고
    // unifont가 첫가끝 자모를 겹쳐 그려 주지 않는다(HI-M0 실측 3). 아래
    // 검사 7이 "오토마타가 이 상태를 만들지 않는다"까지 본다.
    const cannot = [_]hangul.Syllable{
        .{ .cho = 3, .jong = 4 },
        .{ .jung = 0, .jong = 4 },
        .{ .jong = 4 },
    };
    for (cannot) |s| {
        if (s.codepoint() != null) {
            std.debug.print("FAIL: 그릴 수 없는 조합이 코드포인트를 냈다\n", .{});
            return error.UnexpectedCodepoint;
        }
    }
    std.debug.print("hangul_test: 모아주기 상태 셋은 그릴 것이 없다 OK\n", .{});

    std.debug.print("PASS\n", .{});
}
