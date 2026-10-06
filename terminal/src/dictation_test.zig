const std = @import("std");
const dictation = @import("dictation.zig");

// 받아쓰기의 순수한 층을 호스트에서 본다(VD-M1). 시각은 전부 손으로 넣는다 — 실제
// 시계를 쓰면 창의 경계를 못 본다(Voxio `DoubleTapDetectorTests`의 머리 주석).
//
// 판정기 검사(1~9)는 Voxio의 `DoubleTapDetectorTests` · `TriggerEventRouterTests`
// 중 toggle 모드의 것을 옮겼다. 키보드 경로에 붙어야 뜻이 서는 것(자동 반복 · 왼쪽
// Cmd · `keyboard=pc` · 수정키 · Esc · `SYN_DROPPED`)은 `input_test`의 검사 75~83에
// 있다. hold 모드와 `recoverFromDroppedEvents`의 hold 갈래는 옮기지 않았다(design
// 비목표 3).

/// 시각은 밀리초로 적고 마이크로초로 넣는다. Voxio의 검사와 숫자를 맞춰 읽기 위해서다.
fn ms(v: u64) u64 {
    return v * 1000;
}

fn expectFire(got: bool, want: bool, what: []const u8) !void {
    if (got == want) return;
    std.debug.print("FAIL: {s}: fired={}, want {}\n", .{ what, got, want });
    return error.WrongTap;
}

fn expectTap(phase: ?dictation.Phase, want: dictation.TapAction) !void {
    const got = dictation.onTap(phase);
    if (got == want) return;
    std.debug.print("FAIL: onTap({any}) = .{s}, want .{s}\n", .{ phase, @tagName(got), @tagName(want) });
    return error.WrongTapAction;
}

fn expectOutcome(phase: dictation.Phase, code: ?u8, want: dictation.Outcome) !void {
    const got = dictation.outcome(phase, code);
    if (std.meta.eql(got, want)) return;
    std.debug.print("FAIL: outcome(.{s}, {?d}) = {any}, want {any}\n", .{ @tagName(phase), code, got, want });
    return error.WrongOutcome;
}

fn expectClean(raw: []const u8, want: []const u8) !void {
    var buf: [256]u8 = undefined;
    @memcpy(buf[0..raw.len], raw);
    const got = dictation.sanitize(buf[0..raw.len]);
    if (std.mem.eql(u8, got, want)) return;
    std.debug.print("FAIL: sanitize({any}) = {any}, want {any}\n", .{ raw, got, want });
    return error.WrongSanitize;
}

pub fn main() !void {
    // ── 검사 1: 창 안의 누름 → 뗌 → 누름이 발동한다 ──────────────────────
    // Voxio `doubleTapWithinWindowStarts`. 발동하는 것은 둘째 누름이다 — 뗌을
    // 기다리지 않는다.
    {
        var t: dictation.DoubleTap = .{};
        try expectFire(t.down(ms(0), false), false, "first down");
        t.up();
        try expectFire(t.down(ms(200), false), true, "second down at 200ms");
    }
    std.debug.print("dictation_test: down-up-down within 300ms fires OK\n", .{});

    // ── 검사 2: 발동한 뒤의 다음 더블 탭도 발동한다 ───────────────────────
    // Voxio `doubleTapWhileRecordingStops`. 그쪽은 둘째가 `.stop`이었는데 여기는
    // 판정기가 녹음을 모르므로 그냥 발동이다 — 끝인지는 `onTap`이 단계로 정한다
    // (검사 10). 발동한 누름은 새 판정의 첫 누름이 아니다: 그 뒤 한 번 더 눌러도
    // 안 발동하고, 새로 두 번 눌러야 한다.
    {
        var t: dictation.DoubleTap = .{};
        _ = t.down(ms(0), false);
        t.up();
        _ = t.down(ms(200), false);
        t.up();
        try expectFire(t.down(ms(1000), false), false, "first down of the next sequence");
        t.up();
        try expectFire(t.down(ms(1200), false), true, "second down of the next sequence");
    }
    std.debug.print("dictation_test: the next double tap fires again OK\n", .{});

    // ── 검사 3: 창은 닫힌 구간이다 — 300ms는 발동, 301ms는 아니다 ─────────
    // Voxio `exactWindowBoundaryStarts`. 301을 더한 것은 경계의 다른 쪽이다 —
    // `<=`가 `<`로 바뀌거나 창이 넓어지면 둘 중 하나가 빨개진다.
    {
        var t: dictation.DoubleTap = .{};
        _ = t.down(ms(1000), false);
        t.up();
        try expectFire(t.down(ms(1300), false), true, "second down at exactly 300ms");
        var u: dictation.DoubleTap = .{};
        _ = u.down(ms(1000), false);
        u.up();
        try expectFire(u.down(ms(1301), false), false, "second down at 301ms");
    }
    std.debug.print("dictation_test: the window is closed at 300ms and open at 301ms OK\n", .{});

    // ── 검사 4: 늦은 둘째 누름은 새 판정의 첫 누름이다 ────────────────────
    // Voxio `lateSecondTapBecomesNewSequence`. 버리면 사람이 "한 번 늦었으니 두 번
    // 더"를 해야 한다.
    {
        var t: dictation.DoubleTap = .{};
        _ = t.down(ms(0), false);
        t.up();
        try expectFire(t.down(ms(500), false), false, "late second down");
        t.up();
        try expectFire(t.down(ms(700), false), true, "the late down's own second down");
    }
    std.debug.print("dictation_test: a late second down starts a new sequence OK\n", .{});

    // ── 검사 5: 한 번 탭은 아무것도 안 한다 · 뗌이 없으면 안 발동한다 ───────
    // Voxio `singleTapDoesNothing`. 뒤 절반 — 누른 채 다시 누름이 오는 것은
    // evdev에서 자동 반복뿐이고 그것은 안 들어오지만, 들어와도 뗌이 없었으니
    // 발동하면 안 된다.
    {
        var t: dictation.DoubleTap = .{};
        try expectFire(t.down(ms(0), false), false, "single down");
        t.up();
        var u: dictation.DoubleTap = .{};
        _ = u.down(ms(0), false);
        try expectFire(u.down(ms(100), false), false, "down without an up in between");
    }
    std.debug.print("dictation_test: a single tap and a down without an up do nothing OK\n", .{});

    // ── 검사 6: 다른 키가 끼면 판정을 버린다 ─────────────────────────────
    // Voxio `otherKeyDownDiscardsPendingTap`. `reset`을 부르는 것은 `input.zig`의
    // 0.6번 단계다(다른 키의 누름).
    {
        var t: dictation.DoubleTap = .{};
        _ = t.down(ms(0), false);
        t.up();
        t.reset();
        try expectFire(t.down(ms(200), false), false, "second down after another key");
    }
    std.debug.print("dictation_test: another key in between discards the sequence OK\n", .{});

    // ── 검사 7: 다른 수정키가 눌린 누름은 발동도 시작도 안 한다 ─────────────
    // Voxio `downWithForeignModifierIsNotFed`. 둘째 누름에 Shift가 있으면 안 발동하고,
    // 첫 누름에 Shift가 있었으면 그것은 첫 탭이 아니다 — Shift를 놓고 한 번 더 눌러도
    // 안 발동한다.
    {
        var t: dictation.DoubleTap = .{};
        _ = t.down(ms(0), false);
        t.up();
        try expectFire(t.down(ms(200), true), false, "second down with a modifier held");
        var u: dictation.DoubleTap = .{};
        _ = u.down(ms(0), true);
        u.up();
        try expectFire(u.down(ms(200), false), false, "second down after a combined first down");
    }
    std.debug.print("dictation_test: a down with another modifier held neither fires nor starts OK\n", .{});

    // ── 검사 8: 짝 없는 뗌은 판정을 안 움직인다 ─────────────────────────
    // Voxio `repeatedUpDeliveryDoesNotAdvanceSequence`. 두 번 온 뗌도, 누름 없이 온
    // 뗌(terminal이 뜨기 전부터 눌려 있던 키)도 첫 탭이 아니다.
    {
        var t: dictation.DoubleTap = .{};
        _ = t.down(ms(0), false);
        t.up();
        t.up();
        try expectFire(t.down(ms(200), false), true, "second down after a repeated up");
        var u: dictation.DoubleTap = .{};
        u.up();
        try expectFire(u.down(ms(100), false), false, "down after an unpaired up");
    }
    std.debug.print("dictation_test: unpaired ups do not advance the sequence OK\n", .{});

    // ── 검사 9: 시각이 거꾸로 가면 창 밖이다 ────────────────────────────
    // `ev.time`은 벽시계라 뒤로 뛸 수 있다(`input.zig`의 `Tap.up`과 같은 이유).
    // 뺄셈이 감싸 돌면 엄청 긴 간격이라 결과는 같지만 명시한다.
    {
        var t: dictation.DoubleTap = .{};
        _ = t.down(ms(1000), false);
        t.up();
        try expectFire(t.down(ms(900), false), false, "second down earlier than the first");
    }
    std.debug.print("dictation_test: a clock that runs backwards is outside the window OK\n", .{});

    // ── 검사 10: 더블 탭의 뜻은 자식의 단계가 정한다 ──────────────────────
    // design 결정 10의 함정 3. 자식이 없으면 시작, 녹음 중이면 끝, 그 밖은 무시다.
    // 키 없이 끝난 실행(max_seconds · 키 없음 · 실패) 뒤에는 단계가 null로 돌아가므로
    // 다음 더블 탭이 시작이다 — Voxio V17의 "트리거가 한 번 씹힌다"가 여기서는 생길
    // 자리가 없다.
    try expectTap(null, .start);
    try expectTap(.starting, .ignore);
    try expectTap(.recording, .stop);
    try expectTap(.transcribing, .ignore);
    try expectTap(.cancelling, .ignore);
    std.debug.print("dictation_test: no child starts, recording stops, the rest is ignored OK\n", .{});

    // ── 검사 11: Esc는 마이크가 열려 있거나 열리는 중일 때만 받아쓰기의 것이다 ──
    // Voxio D11a · `isCapturing`.
    {
        const cases = [_]struct { p: ?dictation.Phase, want: bool }{
            .{ .p = null, .want = false },
            .{ .p = .starting, .want = true },
            .{ .p = .recording, .want = true },
            .{ .p = .transcribing, .want = false },
            .{ .p = .cancelling, .want = false },
        };
        for (cases) |cs| {
            if (dictation.escCancels(cs.p) != cs.want) {
                std.debug.print("FAIL: escCancels({any}) != {}\n", .{ cs.p, cs.want });
                return error.WrongEsc;
            }
        }
    }
    std.debug.print("dictation_test: Esc cancels only while starting or recording OK\n", .{});

    // ── 검사 12: 자식의 두 줄이 단계를 옮긴다 · 앞으로만 간다 ─────────────
    // 줄의 글자는 M0 `tars-dictate`의 정본이다. 비슷한 다른 줄(전사 결과 · 취소)은
    // 단계를 안 바꾼다.
    {
        const P = dictation.Phase;
        const cases = [_]struct { from: P, line: []const u8, want: P }{
            .{ .from = .starting, .line = "tars-dictate: recording; Ctrl+C stops (at most 300s)", .want = .recording },
            .{ .from = .starting, .line = "tars-dictate: no API key; write it to /config/groq.key (or set GROQ_API_KEY)", .want = .starting },
            .{ .from = .recording, .line = "tars-dictate: recording stopped by SIGINT after 1896ms", .want = .transcribing },
            .{ .from = .recording, .line = "tars-dictate: recording stopped at the 1s limit", .want = .transcribing },
            .{ .from = .recording, .line = "tars-dictate: unknown key 'colour' in /config/dictation.conf", .want = .recording },
            .{ .from = .transcribing, .line = "tars-dictate: recording; Ctrl+C stops (at most 300s)", .want = .transcribing },
            .{ .from = .cancelling, .line = "tars-dictate: recording stopped by SIGINT after 10ms", .want = .cancelling },
            .{ .from = .starting, .line = "tars-dictate: recording stopped at the 1s limit", .want = .starting },
        };
        for (cases) |cs| {
            const got = dictation.phaseAfter(cs.from, cs.line);
            if (got != cs.want) {
                std.debug.print("FAIL: phaseAfter(.{s}, \"{s}\") = .{s}, want .{s}\n", .{
                    @tagName(cs.from), cs.line, @tagName(got), @tagName(cs.want),
                });
                return error.WrongPhase;
            }
        }
    }
    std.debug.print("dictation_test: the child's two lines move the phase forward only OK\n", .{});

    // ── 검사 13: 단계가 상태 줄에 보이는 모양 ───────────────────────────
    if (dictation.showOf(.starting) != .rec or dictation.showOf(.recording) != .rec or
        dictation.showOf(.transcribing) != .wait or dictation.showOf(.cancelling) != null)
    {
        std.debug.print("FAIL: showOf is not rec, rec, wait, null\n", .{});
        return error.WrongShow;
    }
    std.debug.print("dictation_test: starting and recording show rec, transcribing shows wait, cancelling shows nothing OK\n", .{});

    // ── 검사 14: 종료 코드의 표(design 결정 6) ────────────────────────────
    // 넣는 것은 0 하나다. 2 · 130 · 143은 조용하고, 1 · 3은 사람이 고칠 것을 말하고,
    // 나머지는 전부 실패다. 취소 중이었으면 무엇으로 끝났든 조용하다.
    try expectOutcome(.transcribing, 0, .insert);
    try expectOutcome(.recording, 0, .insert);
    try expectOutcome(.transcribing, 2, .quiet);
    try expectOutcome(.transcribing, 130, .quiet);
    try expectOutcome(.recording, 143, .quiet);
    try expectOutcome(.starting, 1, .{ .notice = .no_mic });
    try expectOutcome(.starting, 3, .{ .notice = .no_key });
    try expectOutcome(.transcribing, 4, .{ .notice = .failed });
    try expectOutcome(.starting, 64, .{ .notice = .failed });
    try expectOutcome(.starting, 127, .{ .notice = .failed });
    try expectOutcome(.recording, null, .{ .notice = .failed });
    try expectOutcome(.cancelling, 143, .quiet);
    try expectOutcome(.cancelling, 0, .quiet);
    try expectOutcome(.cancelling, null, .quiet);
    std.debug.print("dictation_test: exit 0 inserts, 2/130/143 are quiet, 1 and 3 say why, the rest failed OK\n", .{});

    // ── 검사 15: 비밀번호 프롬프트는 ICANON이 켜지고 ECHO가 꺼진 것이다 ────────
    // 셸의 줄 편집기는 ECHO와 ICANON을 함께 끈다 — 그것을 비밀번호로 읽으면 모든
    // 프롬프트에서 받아쓰기가 막힌다(design 위험 2를 ECHO만으로 고르면 그렇다).
    if (!dictation.isPasswordPrompt(true, false) or dictation.isPasswordPrompt(false, false) or
        dictation.isPasswordPrompt(true, true) or dictation.isPasswordPrompt(false, true))
    {
        std.debug.print("FAIL: isPasswordPrompt is not exactly canonical-without-echo\n", .{});
        return error.WrongPassword;
    }
    std.debug.print("dictation_test: only canonical input without echo is a password prompt OK\n", .{});

    // ── 검사 16: 넣기 전의 거르기 ───────────────────────────────────────
    // `tars-dictate`의 `printable | strip`과 같은 결과여야 한다. 마지막 줄의 기대값이
    // M0 체인 검사 9(s8)의 표준 출력과 글자까지 같다 — 같은 입력을 두 자리에서 걸러도
    // 결과가 하나라는 뜻이다.
    try expectClean("안녕하세요 vd0-dictated", "안녕하세요 vd0-dictated");
    try expectClean(" 앞뒤 공백\n", "앞뒤 공백");
    try expectClean("a\x1b[201~b", "a[201~b");
    try expectClean("a\rb\x7fc", "abc");
    try expectClean("a\tb\nc", "a\tb\nc");
    try expectClean("a\xc2\x85b\xc2\x9fc\xc2\xa0d", "abc\xc2\xa0d");
    try expectClean("한\x1b", "한");
    try expectClean("\x1b\x07\r", "");
    try expectClean("vd0-ctrl a\x1b[201~b\rc\td\ne\xc2\x85f\x1b", "vd0-ctrl a[201~bc\td\nef");
    std.debug.print("dictation_test: C0 but tab and newline, DEL and C1 go, multibyte tails stay, ends are trimmed OK\n", .{});

    std.debug.print("dictation_test: all checks passed\n", .{});
}
