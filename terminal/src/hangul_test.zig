const std = @import("std");
const hangul = @import("hangul.zig");

/// 두벌식으로 문자열을 통째로 치고 나온 글자를 모은다.
/// **마지막에 남은 조합도 확정한다** — 사람이 Enter를 치는 자리에 해당한다.
fn typeAll(keys: []const u8, out: []u8) ![]const u8 {
    var buf = hangul.Syllable{};
    var len: usize = 0;
    for (keys) |ch| {
        const jamo = hangul.dubeol(ch) orelse return error.NotAJamoKey;
        const step = hangul.feed(buf, jamo);
        if (step.commit) |cp| len += try std.unicode.utf8Encode(cp, out[len..]);
        buf = step.buf;
    }
    if (buf.codepoint()) |cp| len += try std.unicode.utf8Encode(cp, out[len..]);
    return out[0..len];
}

/// 친 것과 나온 것을 짝지어 본다.
fn expectTyped(keys: []const u8, want: []const u8) !void {
    var out: [64]u8 = undefined;
    const got = try typeAll(keys, &out);
    if (std.mem.eql(u8, got, want)) {
        std.debug.print("hangul_test: \"{s}\" -> \"{s}\" OK\n", .{ keys, want });
        return;
    }
    std.debug.print("FAIL: \"{s}\" -> \"{s}\", want \"{s}\"\n", .{ keys, got, want });
    return error.WrongComposition;
}

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

    // ── 3. 두벌식 표 ─────────────────────────────────────────────────
    //
    // **`jong`이 null인 키를 함께 본다.** ㄸ·ㅃ·ㅉ은 받침이 될 수 없고,
    // 그것을 빠뜨리면 "가ㄸ" 같은 자리에서만 증상이 나온다.
    if (hangul.dubeol('E').?.consonant.jong != null) {
        std.debug.print("FAIL: ㄸ이 받침이 될 수 있다고 되어 있다\n", .{});
        return error.WrongFinal;
    }
    if (hangul.dubeol('R').?.consonant.jong.? != 2) {
        std.debug.print("FAIL: ㄲ의 받침 인덱스가 2가 아니다\n", .{});
        return error.WrongFinal;
    }
    if (hangul.dubeol('1') != null) {
        std.debug.print("FAIL: 숫자 키가 자모를 냈다\n", .{});
        return error.NotAJamoKey;
    }
    std.debug.print("hangul_test: 두벌식 표 OK\n", .{});

    // ── 4. 기본 전이 ─────────────────────────────────────────────────
    //
    // **여덟이 서로 다른 갈래를 밟는다.** 초성만 · 중성만 · 초성+중성 ·
    // 초성 뒤에 자음이 와서 확정 · 받침 붙이기 · 받침이 될 수 없는 자음이
    // 와서 확정 · 중성 뒤에 모음이 와서 확정 · 여러 음절.
    //
    // **받침 넘기기가 필요한 것은 여기 없다.** `rkrk`("가가")처럼 받침 뒤에
    // 모음이 오는 경우는 Task 6이 들어와야 맞게 나온다 — 지금 넣으면
    // "각ㅏ"가 나온다.
    try expectTyped("g", "ㅎ");
    try expectTyped("k", "ㅏ");
    try expectTyped("rk", "가");
    try expectTyped("gr", "ㅎㄱ");
    try expectTyped("rkt", "갓");
    try expectTyped("rkE", "가ㄸ");
    try expectTyped("rkk", "가ㅏ");
    try expectTyped("gksrmf", "한글");

    std.debug.print("PASS\n", .{});
}
