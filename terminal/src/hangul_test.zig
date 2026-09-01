const std = @import("std");
const hangul = @import("hangul.zig");

/// 자판 하나로 문자열을 통째로 치고 나온 글자를 모은다.
/// **마지막에 남은 조합도 확정한다** — 사람이 Enter를 치는 자리에 해당한다.
///
/// **조합 순서를 통째로 넣고 결과 문자열을 보는 것이 이 검사의 모양이다**
/// (design 위험 2). 갈마들이는 "이 키가 무슨 자모인가"가 아니라 "이 상태에서
/// 이 키가 무엇이 되는가"라, 표와 오토마타를 따로 보면 안 보인다.
fn typeAll(layout: hangul.Layout, keys: []const u8, out: []u8) ![]const u8 {
    var buf = hangul.Syllable{};
    var len: usize = 0;
    for (keys) |ch| {
        const cand = layout.lookup(ch) orelse return error.NotAJamoKey;
        const step = hangul.feed(buf, cand, layout);
        if (step.commit) |cp| len += try std.unicode.utf8Encode(cp, out[len..]);
        buf = step.buf;
    }
    if (buf.codepoint()) |cp| len += try std.unicode.utf8Encode(cp, out[len..]);
    return out[0..len];
}

/// 친 것과 나온 것을 짝지어 본다.
fn expectTyped(layout: hangul.Layout, keys: []const u8, want: []const u8) !void {
    var out: [64]u8 = undefined;
    const got = try typeAll(layout, keys, &out);
    if (std.mem.eql(u8, got, want)) {
        std.debug.print("hangul_test: [{s}] \"{s}\" -> \"{s}\" OK\n", .{
            @tagName(layout), keys, want,
        });
        return;
    }
    std.debug.print("FAIL: [{s}] \"{s}\" -> \"{s}\", want \"{s}\"\n", .{
        @tagName(layout), keys, got, want,
    });
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
        .{ .s = .{ .jong = 4 }, .cp = 'ㄴ', .what = "종성만은 호환 자모" },
        .{ .s = .{ .jong = 3 }, .cp = 'ㄳ', .what = "겹받침만도 호환 자모" },
    };
    for (wants) |want| {
        const got = want.s.codepoint();
        if (got == null or got.? != want.cp) {
            std.debug.print("FAIL: {s}: got {?d}, want U+{X}\n", .{ want.what, got, want.cp });
            return error.WrongCodepoint;
        }
        std.debug.print("hangul_test: {s} OK\n", .{want.what});
    }

    // ── 2. 그릴 수 없는 두 상태 (design 결정 3) ───────────────────────
    //
    // **모아주기를 뺀 것이 여기서 코드가 된다.** 완성형에 없는 조합이고
    // unifont가 첫가끝 자모를 겹쳐 그려 주지 않는다(HI-M0 실측 3). 아래
    // 검사 7이 "오토마타가 이 상태를 만들지 않는다"까지 본다.
    //
    // **셋이 아니라 둘이다.** 종성만은 HI-M2에서 그릴 수 있는 쪽으로 옮겼다 —
    // 세벌식이 그 상태를 실제로 만들고, 호환 자모 하나로 그려진다. 남은 둘은
    // 여전히 완성형에 없다.
    const cannot = [_]hangul.Syllable{
        .{ .cho = 3, .jong = 4 },
        .{ .jung = 0, .jong = 4 },
    };
    for (cannot) |s| {
        if (s.codepoint() != null) {
            std.debug.print("FAIL: 그릴 수 없는 조합이 코드포인트를 냈다\n", .{});
            return error.UnexpectedCodepoint;
        }
    }
    std.debug.print("hangul_test: 모아주기 상태 둘은 그릴 것이 없다 OK\n", .{});

    // ── 3. 두벌식 표 ─────────────────────────────────────────────────
    //
    // **`jong`이 null인 키를 함께 본다.** ㄸ·ㅃ·ㅉ은 받침이 될 수 없고,
    // 그것을 빠뜨리면 "가ㄸ" 같은 자리에서만 증상이 나온다.
    if (hangul.dubeol('E').?.jong != null) {
        std.debug.print("FAIL: ㄸ이 받침이 될 수 있다고 되어 있다\n", .{});
        return error.WrongFinal;
    }
    if (hangul.dubeol('R').?.jong.? != 2) {
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
    try expectTyped(.dubeol, "g", "ㅎ");
    try expectTyped(.dubeol, "k", "ㅏ");
    try expectTyped(.dubeol, "rk", "가");
    try expectTyped(.dubeol, "gr", "ㅎㄱ");
    try expectTyped(.dubeol, "rkt", "갓");
    try expectTyped(.dubeol, "rkE", "가ㄸ");
    try expectTyped(.dubeol, "rkk", "가ㅏ");
    try expectTyped(.dubeol, "gksrmf", "한글");

    // ── 5. 겹자모와 받침 넘기기 ───────────────────────────────────────
    //
    // **여섯이 서로 다른 갈래를 밟는다.** 복합 모음 · ㅡㅣ · 홑받침 넘기기 ·
    // 겹받침 만들기 · 겹받침 넘기기 · 쌍자음.
    try expectTyped(.dubeol, "rhk", "과");
    try expectTyped(.dubeol, "rml", "긔");
    try expectTyped(.dubeol, "dksk", "아나");
    try expectTyped(.dubeol, "dkswrj", "앉거");
    try expectTyped(.dubeol, "dkswj", "안저");
    try expectTyped(.dubeol, "Rk", "까");

    // ── 5.5. 공세벌 3-P3 (design 위험 2) ─────────────────────────────
    //
    // **열둘이 서로 다른 갈래를 밟는다.** 기본 음절 · 받침 · 갈마들이(같은
    // 키가 중성이자 종성) · 연타 된소리(초성과 종성) · 겹모음을 여는 키와 안
    // 여는 키 · 받침 넘기기가 없다는 것 · 겹받침 · 종성만 상태.
    try expectTyped(.sebeol_3p3, "kf", "가");
    try expectTyped(.sebeol_3p3, "kfx", "각");
    // `c`는 초성 뒤에서는 중성 ㅔ이고, 초성+중성 뒤에서는 종성 ㄷ이다.
    try expectTyped(.sebeol_3p3, "kc", "게");
    try expectTyped(.sebeol_3p3, "kfc", "갇");
    // 연타 — 초성 `kk`는 ㄲ, 종성 `xx`는 ㄲ받침.
    try expectTyped(.sebeol_3p3, "kkf", "까");
    try expectTyped(.sebeol_3p3, "kfxx", "갂");
    // 겹모음은 **오른쪽 ㅗ에서만** 열린다. `/`는 열고 `v`는 안 연다.
    try expectTyped(.sebeol_3p3, "k/f", "과");
    try expectTyped(.sebeol_3p3, "kvf", "곺"); // ㅗ가 안 열려서 `f`가 종성 ㅍ
    // **받침 넘기기가 없다**(design 결정 12). 두벌식이라면 `가구`가 될 자리다.
    //
    // **중성 후보만 있는 키를 골라야 한다.** `f`는 중성 ㅏ이자 종성 ㅍ이라
    // 우선순위(종성 → 중성)에서 종성이 먼저 걸려 `각ㅍ`이 나온다 — 그것도
    // 맞는 동작이지만 받침 넘기기를 보는 검사가 아니다. `b`는 중성 ㅜ뿐이다.
    try expectTyped(.sebeol_3p3, "kfxb", "각ㅜ");
    // 종성 후보가 있는 키는 새 종성으로 간다. 위와 짝이다.
    try expectTyped(.sebeol_3p3, "kfxf", "각ㅍ");
    // 겹받침은 두벌식과 같은 `joinFinal` 표를 쓴다.
    try expectTyped(.sebeol_3p3, "kfxq", "갃");
    // 종성 전용 키를 먼저 누르면 **종성만 상태**가 된다(검사 1의 다섯째 줄).
    try expectTyped(.sebeol_3p3, "x", "ㄱ");

    // ── 6. Backspace ─────────────────────────────────────────────────
    //
    // `단`을 세 번 지운다: 단 → 다 → ㄷ → 빈 상태. **그다음 한 번 더 지우면
    // null이고 그것이 "조합 중이 아니다"**이며, 그때 부르는 쪽이 DEL을 보낸다.
    var b = hangul.Syllable{ .cho = 3, .jung = 0, .jong = 4 };
    const back = [_]?u21{ '다', 'ㄷ', null };
    for (back) |want| {
        const next = hangul.erase(b) orelse {
            std.debug.print("FAIL: 조합 중인데 erase가 null을 냈다\n", .{});
            return error.UnexpectedEnd;
        };
        const got = next.codepoint();
        if (!std.meta.eql(got, want)) {
            std.debug.print("FAIL: erase -> {?d}, want {?d}\n", .{ got, want });
            return error.WrongErase;
        }
        b = next;
    }
    if (hangul.erase(b) != null) {
        std.debug.print("FAIL: 빈 상태에서 erase가 null이 아니다\n", .{});
        return error.UnexpectedErase;
    }
    std.debug.print("hangul_test: 단 -> 다 -> ㄷ -> 빈 상태 -> null OK\n", .{});

    // 겹자모는 **한 겹만** 벗는다. 앉 → 안, 과 → 고.
    if (hangul.erase(.{ .cho = 11, .jung = 0, .jong = 5 }).?.codepoint().? != '안') {
        std.debug.print("FAIL: 앉을 지웠는데 안이 안 나온다\n", .{});
        return error.WrongErase;
    }
    if (hangul.erase(.{ .cho = 0, .jung = 9 }).?.codepoint().? != '고') {
        std.debug.print("FAIL: 과를 지웠는데 고가 안 나온다\n", .{});
        return error.WrongErase;
    }
    std.debug.print("hangul_test: 겹받침과 복합 모음은 한 겹만 벗는다 OK\n", .{});

    // ── 7. 오토마타는 그릴 수 없는 상태를 만들지 않는다 (design 결정 3) ─
    //
    // **검사 2와 짝이다.** 검사 2는 "그런 상태는 그릴 것이 없다"만 말하고
    // 이 검사가 "오토마타가 그런 상태를 애초에 안 만든다"를 말한다. 둘이
    // 함께 있어야 모아주기를 뺀 것이 안전하다는 근거가 선다.
    //
    // 두벌식 키 서른셋을 3-순열로 전부 먹이고 **매 단계**를 본다. 마지막
    // 상태만 보면 안 된다 — 중간에 한 번 지나가는 것만으로도 화면에서
    // 글자가 사라진다.
    //
    // **셋이면 충분한 이유가 있다.** 조합 상태는 (초, 중, 종) 셋이라
    // 넷째 키부터는 앞의 상태가 되풀이된다.
    const keys = "rRseEfaqQtTdwWczxvgkoiOjpuPhynbml";
    var bad: usize = 0;
    var seen: usize = 0;
    for (keys) |k1| for (keys) |k2| for (keys) |k3| {
        var s = hangul.Syllable{};
        for ([_]u8{ k1, k2, k3 }) |ch| {
            s = hangul.feed(s, hangul.dubeol(ch).?, .dubeol).buf;
            seen += 1;
            if (!s.isEmpty() and s.codepoint() == null) bad += 1;
        }
    };
    if (bad != 0) {
        std.debug.print("FAIL: {d}단계 중 {d}번 그릴 수 없는 상태가 됐다\n", .{ seen, bad });
        return error.UnreachableStateReached;
    }
    std.debug.print(
        "hangul_test: 3-순열 {d}단계에서 그릴 수 없는 상태가 0번 OK\n",
        .{seen},
    );

    std.debug.print("PASS\n", .{});
}
