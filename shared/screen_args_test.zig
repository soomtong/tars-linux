//! `screen_args.zig`의 호스트 검사(SA design 결정 6). init의 `zig build test`가
//! 돌린다 — 체인 다섯과 tools가 그것을 부른다.
//!
//! SA 전에는 이 왕복을 볼 검사가 있을 수 없었다. 쓰는 쪽(init의 `arg()`)과 읽는
//! 쪽(terminal의 `stringToEnum` · `parseToggles`)이 다른 프로그램에 있어서,
//! `config_test`는 `arg()`가 `@tagName`과 같은지만, `clipboard_test`는 이름 둘이
//! 통과하는지만 봤다. 이제 둘이 한 파일이라 한 프로세스 안에서 돈다.

const std = @import("std");
const sa = @import("screen_args.zig");

/// 한 종류의 모든 값이 `arg()` → `stringToEnum`으로 제자리에 돌아오는가.
fn expectEnumRoundTrip(comptime T: type) !void {
    for (std.enums.values(T)) |v| {
        const text = v.arg();
        const back = std.meta.stringToEnum(T, text) orelse {
            std.debug.print("FAIL: {s}: arg \"{s}\" does not parse back\n", .{ @typeName(T), text });
            return error.EnumRoundTripFailed;
        };
        if (back != v) {
            std.debug.print("FAIL: {s}: arg \"{s}\" came back as {s}\n", .{ @typeName(T), text, @tagName(back) });
            return error.EnumRoundTripChanged;
        }
        // execve가 읽을 끝의 NUL. `[:0]const u8`가 타입으로 보장하지만 한 번 눈으로 본다.
        if (text.ptr[text.len] != 0) return error.ArgNotNulTerminated;
    }
}

/// 모르는 이름을 세는 sink. `parse(.file, …)`가 `esc_latin`을 넘기는지 본다.
const CountUnknown = struct {
    n: *usize,
    pub fn unknown(self: CountUnknown, _: []const u8) void {
        self.n.* += 1;
    }
};

fn togglesFromBits(bits: u5) sa.Toggles {
    return .{
        .hangul_key = bits & 1 != 0,
        .shift_space = bits & 2 != 0,
        .capslock_tap = bits & 4 != 0,
        .lctrl_tap = bits & 8 != 0,
        .esc_latin = bits & 16 != 0,
    };
}

pub fn main() !void {
    // ── 1. 값의 종류 넷 — 모든 값의 왕복 ──
    try expectEnumRoundTrip(sa.Keyboard);
    try expectEnumRoundTrip(sa.HangulLayout);
    try expectEnumRoundTrip(sa.LatinLayout);
    try expectEnumRoundTrip(sa.ClipboardScope);

    // ── 2. Toggles 서른두 조합 — arg → parse(.argv) 왕복 ──
    //
    // 빈 집합은 `none`으로 나가고 `none`은 빈 집합으로 돌아온다.
    var buf: [sa.TOGGLE_ARG_MAX]u8 = undefined;
    var bits: u6 = 0;
    while (bits < 32) : (bits += 1) {
        const t = togglesFromBits(@intCast(bits));
        const text = t.arg(&buf);
        if (bits == 0 and !std.mem.eql(u8, text, "none")) {
            std.debug.print("FAIL: empty Toggles gave \"{s}\", want \"none\"\n", .{text});
            return error.UnexpectedToggleArg;
        }
        const back = sa.Toggles.parse(.argv, text, sa.ignore_unknown);
        if (!std.meta.eql(back, t)) {
            std.debug.print("FAIL: Toggles arg \"{s}\" did not round-trip\n", .{text});
            return error.ToggleRoundTripFailed;
        }
    }

    // ── 3. 파일은 넷, argv는 다섯 ──
    {
        var n: usize = 0;
        const from_file = sa.Toggles.parse(.file, "shift_space,esc_latin", CountUnknown{ .n = &n });
        if (from_file.esc_latin or !from_file.shift_space or n != 1) {
            std.debug.print("FAIL: parse(.file) esc_latin={} shift_space={} unknown={d}\n", .{ from_file.esc_latin, from_file.shift_space, n });
            return error.FileScopeWrong;
        }
        n = 0;
        const from_argv = sa.Toggles.parse(.argv, "shift_space,esc_latin", CountUnknown{ .n = &n });
        if (!from_argv.esc_latin or !from_argv.shift_space or n != 0) {
            std.debug.print("FAIL: parse(.argv) esc_latin={} shift_space={} unknown={d}\n", .{ from_argv.esc_latin, from_argv.shift_space, n });
            return error.ArgvScopeWrong;
        }
        // 모르는 이름은 sink에 가고 나머지는 산다. 빈 항목과 `none`은 sink에 안 간다.
        n = 0;
        const mixed = sa.Toggles.parse(.file, "bogus, lctrl_tap ,,none", CountUnknown{ .n = &n });
        if (!mixed.lctrl_tap or mixed.hangul_key or n != 1) {
            std.debug.print("FAIL: mixed list lctrl_tap={} unknown={d}\n", .{ mixed.lctrl_tap, n });
            return error.UnknownHandlingWrong;
        }
    }

    // ── 4. 순서 정규화 — 거꾸로 적어도 같은 글자 ──
    {
        const reversed = sa.Toggles.parse(.argv, "esc_latin,lctrl_tap,capslock_tap,shift_space,hangul_key", sa.ignore_unknown);
        const text = reversed.arg(&buf);
        if (!std.mem.eql(u8, text, "hangul_key,shift_space,capslock_tap,lctrl_tap,esc_latin")) {
            std.debug.print("FAIL: Toggles.arg is not order-normalized: \"{s}\"\n", .{text});
            return error.UnexpectedToggleArg;
        }
        // argv의 기본값이 그 가장 긴 목록이다.
        if (!std.mem.eql(u8, sa.default_toggles_arg, text)) return error.DefaultTogglesDrifted;
    }

    // ── 5. 자리 — 1번부터 8번까지 빈 칸 없이, 0번은 비워 둔다 ──
    {
        var seen: [sa.ARGC]bool = @splat(false);
        for (std.enums.values(sa.Slot)) |s| seen[@backingInt(s)] = true;
        if (seen[0]) return error.SlotZeroTaken;
        for (seen[1..], 1..) |taken, i| {
            if (!taken) {
                std.debug.print("FAIL: argv slot {d} has no Slot name\n", .{i});
                return error.SlotGap;
            }
        }
    }

    // ── 6. Args — encode → decode 왕복(SA-M1, plan 확정 7) ──
    //
    // 기본값 전부인 것과 전부 다른 것 둘. 포인터 칸은 글자로 비교한다 — `encode`는
    // 포인터를 그대로 넣으므로 같은 주소가 돌아오지만, 보려는 것은 글자다.
    {
        const all_default = sa.Args{
            .shell_path = sa.default_shell_path,
            .shell_flag = sa.default_shell_flag,
            .keyboard = sa.default_keyboard,
            .device_path = sa.default_device_path,
            .hangul = sa.default_hangul,
            .latin = sa.default_latin,
            .toggles = sa.default_toggles,
            .clipboard = sa.default_clipboard,
        };
        const all_other = sa.Args{
            .shell_path = "/usr/bin/zsh",
            .shell_flag = "none",
            .keyboard = .pc,
            .device_path = "/dev/input/event3",
            .hangul = .dubeol,
            .latin = .dvorak,
            .toggles = .{ .shift_space = true },
            .clipboard = .pane,
        };
        var tbuf: [sa.TOGGLE_ARG_MAX]u8 = undefined;
        for ([_]sa.Args{ all_default, all_other }) |a| {
            const v = sa.encode(a, &tbuf);
            // 0번은 terminal 자신이고, 아홉 칸이 전부 차 있다.
            if (!std.mem.eql(u8, std.mem.span(v[0].?), sa.TERMINAL_PATH)) return error.ArgvZeroNotTerminal;
            for (v, 0..) |slot, i| {
                if (slot == null) {
                    std.debug.print("FAIL: encode left slot {d} null\n", .{i});
                    return error.EncodeLeftNull;
                }
            }
            try expectArgsEql(sa.decode(v), a);
        }
        // `default_toggles`(집합)와 `default_toggles_arg`(글자)는 같은 것이다.
        if (!std.mem.eql(u8, sa.default_toggles.arg(&tbuf), sa.default_toggles_arg)) return error.DefaultTogglesSplit;
    }

    // ── 7. decode — 빈 argv는 기본값, 엉뚱한 글자는 그 칸만 기본값 ──
    {
        const empty: sa.Argv = @splat(null);
        const d = sa.decode(empty);
        if (!std.mem.eql(u8, std.mem.span(d.shell_path), std.mem.span(sa.default_shell_path)) or
            !std.mem.eql(u8, std.mem.span(d.shell_flag), std.mem.span(sa.default_shell_flag)) or
            !std.mem.eql(u8, std.mem.span(d.device_path), std.mem.span(sa.default_device_path)) or
            d.keyboard != sa.default_keyboard or d.hangul != sa.default_hangul or d.latin != sa.default_latin or
            d.clipboard != sa.default_clipboard or !std.meta.eql(d.toggles, sa.default_toggles))
        {
            return error.EmptyArgvNotDefault;
        }

        var tbuf: [sa.TOGGLE_ARG_MAX]u8 = undefined;
        var v = sa.encode(.{
            .shell_path = "/usr/bin/zsh",
            .shell_flag = "none",
            .keyboard = .pc,
            .device_path = "/dev/input/event3",
            .hangul = .dubeol,
            .latin = .dvorak,
            .toggles = .{ .lctrl_tap = true },
            .clipboard = .pane,
        }, &tbuf);
        v[sa.Slot.hangul.index()] = "bogus";
        const b = sa.decode(v);
        if (b.hangul != sa.default_hangul) return error.BogusEnumNotDefault;
        if (b.keyboard != .pc or b.latin != .dvorak or b.clipboard != .pane or !b.toggles.lctrl_tap or b.toggles.hangul_key or
            !std.mem.eql(u8, std.mem.span(b.device_path), "/dev/input/event3"))
        {
            std.debug.print("FAIL: a bogus hangul slot disturbed another field\n", .{});
            return error.BogusEnumSpread;
        }
    }

    // ── 8. argvOf — 짧은 슬라이스는 남는 칸이 null, 긴 슬라이스는 ARGC에서 잘린다 ──
    {
        const short = [_][*:0]const u8{ "/terminal", "/usr/bin/zsh" };
        const v = sa.argvOf(&short);
        if (!std.mem.eql(u8, std.mem.span(v[0].?), "/terminal")) return error.ArgvOfSlotZero;
        if (!std.mem.eql(u8, std.mem.span(v[1].?), "/usr/bin/zsh")) return error.ArgvOfSlotOne;
        for (v[2..], 2..) |slot, i| {
            if (slot != null) {
                std.debug.print("FAIL: argvOf filled slot {d} from a two-item slice\n", .{i});
                return error.ArgvOfOverfilled;
            }
        }
        const long = [_][*:0]const u8{ "/terminal", "a", "b", "c", "d", "e", "f", "g", "h", "extra" };
        const w = sa.argvOf(&long);
        if (!std.mem.eql(u8, std.mem.span(w[sa.ARGC - 1].?), "h")) return error.ArgvOfLastSlot;
        // 빈 슬라이스(인자가 하나도 없다)는 전부 null이고 decode가 기본값을 준다.
        const none = sa.argvOf(&[_][*:0]const u8{});
        if (sa.decode(none).keyboard != sa.default_keyboard) return error.ArgvOfEmpty;
    }

    std.debug.print("screen_args_test: all checks passed\n", .{});
}

/// `Args` 둘이 같은가. 포인터 셋은 글자로, 나머지는 값으로 본다.
fn expectArgsEql(got: sa.Args, want: sa.Args) !void {
    const strs = [_][2][*:0]const u8{
        .{ got.shell_path, want.shell_path },
        .{ got.shell_flag, want.shell_flag },
        .{ got.device_path, want.device_path },
    };
    for (strs) |pair| {
        if (!std.mem.eql(u8, std.mem.span(pair[0]), std.mem.span(pair[1]))) {
            std.debug.print("FAIL: Args string \"{s}\" came back as \"{s}\"\n", .{ pair[1], pair[0] });
            return error.ArgsStringChanged;
        }
    }
    if (got.keyboard != want.keyboard or got.hangul != want.hangul or got.latin != want.latin or
        got.clipboard != want.clipboard or !std.meta.eql(got.toggles, want.toggles))
    {
        std.debug.print("FAIL: Args enum/toggle field did not round-trip\n", .{});
        return error.ArgsValueChanged;
    }
}
