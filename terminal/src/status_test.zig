const std = @import("std");
const hangul = @import("hangul.zig");
const input = @import("input.zig");
const status = @import("status.zig");
const dictation = @import("dictation.zig");

/// 상태 하나를 넣고 나온 줄을 본다.
///
/// `input.State`를 통째로 넘긴다(design 결정 5). 필드를 넷 늘어놓으면
/// 부르는 자리마다 순서를 틀릴 수 있고, IS-M1이 `caps_lock`을 더할 때 이
/// 헬퍼의 시그니처가 또 바뀐다.
///
/// `copy`는 `input.State` 밖이다(CI design 결정 4) — copy mode는 `vt.Screen`의
/// 상태이고 `input.State`는 그것을 모른다. 검사 1~12는 전부 `false`다.
fn expectText(state: input.State, copy: bool, want: []const u8) !void {
    var buf: [status.MAX_LEN]u8 = undefined;
    const got = status.statusText(&state, copy, null, null, &buf);
    if (std.mem.eql(u8, got, want)) {
        std.debug.print("status_test: \"{s}\" OK\n", .{got});
        return;
    }
    std.debug.print("FAIL: got \"{s}\", want \"{s}\"\n", .{ got, want });
    return error.WrongStatusText;
}

/// 상태 줄의 검사. 부팅도 폰트도 프레임버퍼도 안 쓴다 — 상태를 넣고
/// 문자열을 받는 순수 계산이다.
pub fn main() !void {
    // ── 검사 1: 기본값 ───────────────────────────────────────────────
    //
    // `input.State`의 기본값은 한/영 꺼짐 · `shin_pcs` · `qwerty`다.
    // 이 줄이 곧 아무 설정도 없는 부팅의 화면이다.
    try expectText(.{}, false, "EN  신세벌 PCS  쿼티  CAPS");

    // ── 검사 2: 한/영이 첫 칸을 가른다 ───────────────────────────────
    try expectText(.{ .hangul_on = true }, false, "한  신세벌 PCS  쿼티  CAPS");

    // ── 검사 3~6: 한글 자판 넷의 이름 ────────────────────────────────
    //
    // 자판 이름 표를 옮겨 적는 것이 이 milestone의 유일한 "사람이 읽고
    // 다시 적는" 자리다(HI-M2 실측 6). 넷을 전부 못 박는다.
    try expectText(.{ .hangul_layout = .dubeol }, false, "EN  두벌식  쿼티  CAPS");
    try expectText(.{ .hangul_layout = .sebeol_3p3 }, false, "EN  공세벌 3-P3  쿼티  CAPS");
    try expectText(.{ .hangul_layout = .shin_p2 }, false, "EN  신세벌 P2  쿼티  CAPS");
    try expectText(.{ .hangul_layout = .shin_pcs }, false, "EN  신세벌 PCS  쿼티  CAPS");

    // ── 검사 7~8: 영문 자판 둘의 이름 ────────────────────────────────
    try expectText(.{ .latin_layout = .qwerty }, false, "EN  신세벌 PCS  쿼티  CAPS");
    try expectText(.{ .latin_layout = .dvorak }, false, "EN  신세벌 PCS  드보락  CAPS");

    // ── 검사 9: 칸이 언제나 셋이다 ───────────────────────────────────
    //
    // 자리가 고정인 것이 결정 2다. 칸이 사라지거나 밀리면 사람도
    // 게이트도 매번 다른 자리를 봐야 한다. 두 칸 공백으로 갈라 센다.
    {
        var buf: [status.MAX_LEN]u8 = undefined;
        const line = status.statusText(&input.State{ .hangul_on = true }, false, null, null, &buf);
        var it = std.mem.splitSequence(u8, line, "  ");
        var fields: usize = 0;
        while (it.next()) |f| {
            if (f.len == 0) {
                std.debug.print("FAIL: empty field in \"{s}\"\n", .{line});
                return error.EmptyStatusField;
            }
            fields += 1;
        }
        if (fields != 4) {
            std.debug.print("FAIL: {d} field(s) in \"{s}\", want 4\n", .{ fields, line });
            return error.WrongStatusFieldCount;
        }
        std.debug.print("status_test: 4 fields OK\n", .{});
    }

    // ── 검사 10: 가장 긴 줄이 `MAX_LEN`과 정확히 같다 ────────────
    //
    // 크거나 같은지가 아니라 같은지를 본다. `MAX_LEN`은 이름 표에서
    // comptime에 센 값이므로, 정확히 안 맞는다는 것은 산수와 표가 어긋났다는
    // 뜻이다 — 버퍼가 남아도는 것도 사고의 신호다.
    //
    // 가장 긴 조합은 `한`(3, `EN`보다 길다) + `공세벌 3-P3`(14) +
    // `드보락`(9) + `CAPS`(4) + `W9`(2) + `COPY`(4) + `PASSWORD`(8) + 공백
    // 열둘 = 56이다.
    //
    // IS-M1에서 이 값이 30에서 36으로 저절로 늘었다. `statusText`에
    // `GAP + CAPS`를 더하면서 `MAX_LEN`의 산수도 함께 고쳤을 뿐, 버퍼를
    // 손으로 늘린 자리는 한 군데도 없다 — 그것이 이름 표에서 comptime에
    // 세게 한 값이고, IS-M0 실측 1이 "아직 오지 않았다"고 적어 둔 자리다.
    // CI-M0이 `COPY_TAIL`로 같은 일을 한 번 더 했다 — 36이 42가 됐고,
    // 이 검사는 `copy=true`로 바꾸기 전까지 36 ≠ 42로 빨갰다.
    // WP-M2가 `WS_TAIL_LEN`으로 한 번 더 했다 — 가장 긴 줄은 워크스페이스
    // 칸(`  W9`, 넷)까지 붙은 46이고, `statusText`가 칸을 쓰기 전까지 이
    // 검사는 42 ≠ 46으로 빨갰다.
    // VD-M1이 받아쓰기 칸으로 한 번 더 했다 — 가장 긴 글자 `PASSWORD`까지 붙은
    // 56이고, 이 호출에 칸을 넣기 전까지 46 ≠ 56으로 빨갰다.
    {
        var buf: [status.MAX_LEN]u8 = undefined;
        const line = status.statusText(&input.State{
            .hangul_on = true,
            .hangul_layout = .sebeol_3p3,
            .latin_layout = .dvorak,
        }, true, 9, .password, &buf);
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
    // 검사 3~6이 낡았는지를 보는 자리다. 위의 넷은 이름을 하나씩 못
    // 박지만 "빠진 자판이 없다"는 말하지 않는다 — 다섯째가 들어오면
    // `hangulName`의 `switch`가 컴파일 에러로 막고, 그 에러를 고친 사람이
    // 검사도 하나 더해야 한다는 것을 이 줄이 알려 준다.
    if (std.enums.values(hangul.Layout).len != 4) {
        std.debug.print("FAIL: {d} hangul layout(s), but only 4 are checked above\n", .{
            std.enums.values(hangul.Layout).len,
        });
        return error.LayoutCountChanged;
    }

    // ── 검사 12: 대문자 잠금은 글자를 안 바꾼다 ──────────────────
    //
    // design 결정 3이다 — `CAPS`와 `caps`는 흘깃 봐서 같아 보이므로 자리를
    // 유지한 채 색으로 가른다. 그래서 `statusText`는 `caps_lock`을 아예
    // 안 읽는다.
    //
    // 읽고 나서 무시하는 것보다 안 읽는 편이 낫다. 나중에 누가 켜졌을 때
    // 글자를 바꾸고 싶어지면, 그 자리에 필드가 없다는 것이 먼저 눈에 띈다.
    //
    // 색을 고르는 것은 `main.zig`이고 그것을 보는 것은 게이트의
    // `status> caps ink` 줄이다 — 이 파일은 색을 볼 수 없다.
    try expectText(.{ .caps_lock = true }, false, "EN  신세벌 PCS  쿼티  CAPS");
    try expectText(.{ .caps_lock = false }, false, "EN  신세벌 PCS  쿼티  CAPS");

    // ── 검사 13: copy mode면 꼬리에 `COPY`가 붙는다 ──────────────────
    //
    // CI design 결정 1 · 2다. 앞 넷은 한 바이트도 안 바뀌고(검사 1과 같은
    // 상태를 넣는다), 꼬리에 `GAP + COPY`가 붙는다. `CAPS`와 달리 색이
    // 아니라 글자가 생기므로 이 파일이 볼 수 있다.
    try expectText(.{}, true, "EN  신세벌 PCS  쿼티  CAPS  COPY");
    try expectText(.{ .hangul_on = true, .caps_lock = true }, true, "한  신세벌 PCS  쿼티  CAPS  COPY");

    // ── 검사 14: copy mode가 아니면 `COPY`가 어디에도 없다 ───────────
    //
    // 검사 1~12가 전부 `false`로 통과한 것이 이미 그 증명이지만, 그 열둘은
    // 줄 전체를 비교한다 — "어디에도 없다"를 한 줄로 못 박는다. 켜지는
    // 쪽(검사 13)만 보면 "영영 붙어 있는" 코드도 통과한다(IS-M1 plan 확정 7).
    {
        var buf: [status.MAX_LEN]u8 = undefined;
        const line = status.statusText(&input.State{}, false, null, null, &buf);
        if (std.mem.indexOf(u8, line, status.COPY) != null) {
            std.debug.print("FAIL: \"{s}\" has COPY outside copy mode\n", .{line});
            return error.CopyFieldLeaked;
        }
        std.debug.print("status_test: no COPY outside copy mode OK\n", .{});
    }

    // ── 검사 15: 워크스페이스 칸은 `CAPS` 뒤 · `COPY` 앞이다 (WP-M2) ──────
    //
    // WP design 결정 8. `COPY`는 모드라 맨 끝이고 워크스페이스는 자리라 그
    // 앞이다. `drawStatus`가 꼬리에서 `COPY_TAIL` · `WS_TAIL_LEN`만큼 물러나
    // `CAPS`의 시작을 세므로, 순서가 뒤집히면 색이 칸째 밀린다.
    {
        var buf: [status.MAX_LEN]u8 = undefined;
        const want = "EN  신세벌 PCS  쿼티  CAPS  W2  COPY";
        const got = status.statusText(&input.State{}, true, 2, null, &buf);
        if (!std.mem.eql(u8, got, want)) {
            std.debug.print("FAIL: got \"{s}\", want \"{s}\"\n", .{ got, want });
            return error.WrongWorkspaceOrder;
        }
        const plain = status.statusText(&input.State{}, false, 2, null, &buf);
        if (!std.mem.eql(u8, plain, "EN  신세벌 PCS  쿼티  CAPS  W2")) {
            std.debug.print("FAIL: got \"{s}\"\n", .{plain});
            return error.WrongWorkspaceField;
        }
        std.debug.print("status_test: \"{s}\" OK\n", .{got});
    }

    // ── 검사 16: 워크스페이스가 하나면(null) 칸이 어디에도 없다 ──────────
    //
    // 검사 1~14가 전부 null로 통과한 것이 이미 그 증명이지만, 검사 14와
    // 같은 이유로 "어디에도 없다"를 한 줄로 못 박는다 — 켜지는 쪽(15)만
    // 보면 "영영 붙어 있는" 코드도 통과한다.
    {
        var buf: [status.MAX_LEN]u8 = undefined;
        const line = status.statusText(&input.State{}, true, null, null, &buf);
        if (std.mem.indexOf(u8, line, "  " ++ status.WS_PREFIX) != null) {
            std.debug.print("FAIL: \"{s}\" has a workspace field with one workspace\n", .{line});
            return error.WorkspaceFieldLeaked;
        }
        std.debug.print("status_test: no workspace field with one workspace OK\n", .{});
    }

    // ── 검사 17: 받아쓰기 칸의 글자 일곱 (VD-M1) ───────────────────────
    //
    // 표를 옮겨 적는 자리라 하나씩 못 박는다(검사 3~6과 같은 이유). 앞 넷은 한
    // 바이트도 안 바뀌고 꼬리에 `GAP + 글자`가 붙는다.
    {
        const cases = [_]struct { s: dictation.Show, want: []const u8 }{
            .{ .s = .rec, .want = "EN  신세벌 PCS  쿼티  CAPS  REC" },
            .{ .s = .wait, .want = "EN  신세벌 PCS  쿼티  CAPS  WAIT" },
            .{ .s = .no_mic, .want = "EN  신세벌 PCS  쿼티  CAPS  NO MIC" },
            .{ .s = .no_key, .want = "EN  신세벌 PCS  쿼티  CAPS  NO KEY" },
            .{ .s = .failed, .want = "EN  신세벌 PCS  쿼티  CAPS  FAILED" },
            .{ .s = .password, .want = "EN  신세벌 PCS  쿼티  CAPS  PASSWORD" },
            .{ .s = .no_pane, .want = "EN  신세벌 PCS  쿼티  CAPS  NO PANE" },
        };
        for (cases) |cs| {
            var buf: [status.MAX_LEN]u8 = undefined;
            const got = status.statusText(&input.State{}, false, null, cs.s, &buf);
            if (!std.mem.eql(u8, got, cs.want)) {
                std.debug.print("FAIL: got \"{s}\", want \"{s}\"\n", .{ got, cs.want });
                return error.WrongDictWord;
            }
            if (got.len - status.dictTailLen(cs.s) != "EN  신세벌 PCS  쿼티  CAPS".len) {
                std.debug.print("FAIL: dictTailLen(.{s}) does not match the tail it wrote\n", .{@tagName(cs.s)});
                return error.WrongDictTailLen;
            }
        }
        if (std.enums.values(dictation.Show).len != cases.len) {
            std.debug.print("FAIL: dictation.Show has {d} value(s), but only {d} are checked above\n", .{
                std.enums.values(dictation.Show).len, cases.len,
            });
            return error.DictShowCountChanged;
        }
        std.debug.print("status_test: the seven dictation words OK\n", .{});
    }

    // ── 검사 18: 받아쓰기 칸은 꼬리의 맨 끝이다 (VD-M1) ──────────────────
    //
    // 워크스페이스 · `COPY`보다 뒤다. `drawStatus`가 꼬리에서 이 칸의 길이를 먼저
    // 물러나 `COPY`의 시작을 세므로, 순서가 뒤집히면 색이 칸째 밀린다.
    {
        var buf: [status.MAX_LEN]u8 = undefined;
        const want = "한  신세벌 PCS  쿼티  CAPS  W2  COPY  REC";
        const got = status.statusText(&input.State{ .hangul_on = true }, true, 2, .rec, &buf);
        if (!std.mem.eql(u8, got, want)) {
            std.debug.print("FAIL: got \"{s}\", want \"{s}\"\n", .{ got, want });
            return error.WrongDictOrder;
        }
        std.debug.print("status_test: \"{s}\" OK\n", .{got});
    }

    // ── 검사 19: 받아쓰기 칸이 없으면(null) 글자 일곱 어느 것도 없다 (VD-M1) ───
    //
    // 검사 14 · 16과 같은 이유다 — 켜지는 쪽(17)만 보면 "영영 붙어 있는" 코드도
    // 통과한다. `REC`만 보면 다른 여섯이 새는 것을 못 잡는다.
    {
        var buf: [status.MAX_LEN]u8 = undefined;
        const line = status.statusText(&input.State{}, true, 2, null, &buf);
        for ([_][]const u8{ "REC", "WAIT", "NO MIC", "NO KEY", "FAILED", "PASSWORD", "NO PANE" }) |w| {
            if (std.mem.indexOf(u8, line, w) != null) {
                std.debug.print("FAIL: \"{s}\" has {s} without a dictation\n", .{ line, w });
                return error.DictFieldLeaked;
            }
        }
        std.debug.print("status_test: no dictation field without a dictation OK\n", .{});
    }

    std.debug.print("status_test: all checks passed\n", .{});
}
