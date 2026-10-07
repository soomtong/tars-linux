//! `logline.zig`의 호스트 검사(AL-M0). init의 사본은 `cmp`로 같으므로 여기서 함께
//! 덮인다.
//!
//! 이 저장소의 다른 `*_test.zig`처럼 `main`이 경우를 하나씩 돌리고 `OK` 줄을 찍는다.
//!
//! 나가는 바이트와 write의 횟수를 함께 본다. fd 2를 잠깐 SOCK_SEQPACKET 소켓의 한쪽
//! 끝으로 바꿔 두면 write 한 번이 메시지 하나가 되므로, 받은 메시지의 수가 곧 write의
//! 수다 — "한 줄 = write 한 번"이 이 파일이 지키는 성질이다.
const std = @import("std");
const linux = std.os.linux;
const logline = @import("logline.zig");

const Caught = struct {
    writes: usize = 0,
    data: [64 * 1024]u8 = undefined,
    len: usize = 0,

    fn bytes(self: *const Caught) []const u8 {
        return self.data[0..self.len];
    }
};

/// `f(arg)` 동안 fd 2에 쓰인 것을 write 단위로 받는다.
fn catchWrites(out: *Caught, comptime f: anytype, arg: anytype) !void {
    var sv: [2]i32 = undefined;
    if (linux.errno(linux.socketpair(linux.AF.UNIX, linux.SOCK.SEQPACKET | linux.SOCK.CLOEXEC, 0, &sv)) != .SUCCESS)
        return error.SocketPair;
    defer _ = linux.close(sv[0]);
    const saved: i32 = @intCast(linux.dup(2));
    _ = linux.dup2(sv[1], 2);
    _ = linux.close(sv[1]);
    f(arg);
    _ = linux.dup2(saved, 2); // 소켓의 쓰는 끝이 닫혀 아래 read가 0으로 끝난다
    _ = linux.close(saved);
    out.* = .{};
    while (true) {
        const rc = linux.read(sv[0], out.data[out.len..].ptr, out.data.len - out.len);
        if (linux.errno(rc) != .SUCCESS) return error.Read;
        if (rc == 0) break;
        out.len += rc;
        out.writes += 1;
    }
}

fn filled(buf: []u8, ascii_len: usize, tail: []const u8) []const u8 {
    @memset(buf[0..ascii_len], 'a');
    @memcpy(buf[ascii_len..][0..tail.len], tail);
    return buf[0 .. ascii_len + tail.len];
}

fn printS(s: []const u8) void {
    logline.print("{s}", .{s});
}

fn case1() !void {
    var c: Caught = .{};
    try catchWrites(&c, struct {
        fn f(_: void) void {
            logline.print("terminal: pointer> at x={d} y={d} buttons={d} wheel={d} shown={d} ink={d}\n", .{ 1279, 799, 0, 0, 1, 1 });
        }
    }.f, {});
    try std.testing.expectEqual(@as(usize, 1), c.writes);
    try std.testing.expectEqualStrings("terminal: pointer> at x=1279 y=799 buttons=0 wheel=0 shown=1 ink=1\n", c.bytes());
}

fn case2() !void {
    var c: Caught = .{};
    try catchWrites(&c, printS, "");
    try std.testing.expectEqual(@as(usize, 0), c.writes);
    try catchWrites(&c, printS, "\n");
    try std.testing.expectEqual(@as(usize, 1), c.writes);
    try std.testing.expectEqualStrings("\n", c.bytes());
}

fn case3() !void {
    var src: [logline.MAX]u8 = undefined;
    const s = filled(&src, logline.MAX - 1, "\n");
    var c: Caught = .{};
    try catchWrites(&c, printS, s);
    try std.testing.expectEqual(@as(usize, 1), c.writes);
    try std.testing.expectEqualStrings(s, c.bytes());
}

fn case4() !void {
    var src: [logline.MAX + 1]u8 = undefined;
    const s = filled(&src, logline.MAX, "\n");
    var c: Caught = .{};
    try catchWrites(&c, printS, s);
    try std.testing.expectEqual(@as(usize, 1), c.writes);
    try std.testing.expectEqual(@as(usize, logline.MAX), c.len);
    try std.testing.expectEqualStrings(s[0 .. logline.MAX - logline.CUT.len], c.bytes()[0 .. logline.MAX - logline.CUT.len]);
    try std.testing.expect(std.mem.endsWith(u8, c.bytes(), logline.CUT));
}

fn case5() !void {
    var src: [logline.MAX]u8 = undefined;
    const s = filled(&src, logline.MAX - 3, "가");
    var c: Caught = .{};
    try catchWrites(&c, printS, s);
    try std.testing.expectEqualStrings(s, c.bytes());
}

fn case6() !void {
    // 자르는 자리(MAX - CUT.len)가 `가`(3바이트)의 둘째 바이트 뒤에 온다.
    const room = logline.MAX - logline.CUT.len;
    var src: [logline.MAX + 16]u8 = undefined;
    const s = filled(&src, room - 2, "가나다라마");
    var c: Caught = .{};
    try catchWrites(&c, printS, s);
    var want: [logline.MAX]u8 = undefined;
    const w = filled(&want, room - 2, logline.CUT);
    try std.testing.expectEqualStrings(w, c.bytes());
}

fn case7() !void {
    const room = logline.MAX - logline.CUT.len;
    var src: [logline.MAX + 16]u8 = undefined;
    const s = filled(&src, room - 3, "가나다라마");
    var c: Caught = .{};
    try catchWrites(&c, printS, s);
    var want: [logline.MAX]u8 = undefined;
    const w = filled(&want, room - 3, "가" ++ logline.CUT);
    try std.testing.expectEqualStrings(w, c.bytes());
}

fn case8() !void {
    const room = logline.MAX - logline.CUT.len;
    var src: [logline.MAX + 1]u8 = undefined;
    @memset(&src, 0x80);
    var c: Caught = .{};
    try catchWrites(&c, printS, &src);
    try std.testing.expectEqual(@as(usize, logline.MAX), c.len);
    try std.testing.expect(std.mem.allEqual(u8, c.bytes()[0..room], 0x80));
}

fn case9() !void {
    var c: Caught = .{};
    try catchWrites(&c, struct {
        fn f(_: void) void {
            var buf: [256]u8 = undefined;
            var l = logline.Line.init(&buf);
            l.print("terminal: screen> ", .{});
            l.print("{s}", .{"a"});
            l.print(" | ", .{});
            l.print("{s}", .{"가"});
            l.print("\n", .{});
            l.flush();
        }
    }.f, {});
    try std.testing.expectEqual(@as(usize, 1), c.writes);
    try std.testing.expectEqualStrings("terminal: screen> a | 가\n", c.bytes());
}

fn case10() !void {
    var c: Caught = .{};
    try catchWrites(&c, struct {
        fn f(_: void) void {
            var buf: [256]u8 = undefined;
            var l = logline.Line.init(&buf);
            l.print("terminal: screen> ", .{});
            l.print("{s}", .{"a"});
        }
    }.f, {});
    try std.testing.expectEqual(@as(usize, 0), c.writes);
}

fn case11() !void {
    var c: Caught = .{};
    try catchWrites(&c, struct {
        fn f(_: void) void {
            var buf: [10 + logline.CUT.len]u8 = undefined;
            var l = logline.Line.init(&buf);
            l.print("{s}", .{"0123456789ABCDEFGH"});
            l.print("{s}", .{"X"});
            l.flush();
            l.print("ok\n", .{});
            l.flush();
        }
    }.f, {});
    try std.testing.expectEqual(@as(usize, 2), c.writes);
    try std.testing.expectEqualStrings("0123456789 [cut]\nok\n", c.bytes());
}

fn case13() !void {
    // 자른 자리가 글자 앞으로 물러나면 버퍼 끝에 빈 자리가 남는다. 그 뒤의 조각이 표시 뒤에
    // 붙으면 줄이 `[cut]` 다음에 이어진다 — 넘친 뒤의 `print`는 아무것도 안 해야 한다.
    var c: Caught = .{};
    try catchWrites(&c, struct {
        fn f(_: void) void {
            var buf: [5 + logline.CUT.len]u8 = undefined;
            var l = logline.Line.init(&buf);
            l.print("{s}", .{"abc가나다라"});
            l.print("{s}", .{"X"});
            l.flush();
        }
    }.f, {});
    try std.testing.expectEqual(@as(usize, 1), c.writes);
    try std.testing.expectEqualStrings("abc [cut]\n", c.bytes());
}

fn case12() !void {
    var c: Caught = .{};
    try catchWrites(&c, struct {
        fn f(_: void) void {
            var buf: [logline.CUT.len]u8 = undefined;
            var l = logline.Line.init(&buf);
            l.print("terminal: x\n", .{});
            l.flush();
            var none: [0]u8 = .{};
            var z = logline.Line.init(&none);
            z.print("y\n", .{});
            z.flush();
        }
    }.f, {});
    try std.testing.expectEqual(@as(usize, 0), c.writes);
}

pub fn main() !void {
    const cases = .{
        .{ "a line that fits leaves as the same bytes in one write", case1 },
        .{ "an empty format writes nothing, a bare newline writes one byte", case2 },
        .{ "MAX bytes exactly is not cut", case3 },
        .{ "MAX + 1 bytes is cut to MAX with the mark, still one write", case4 },
        .{ "a hangul syllable ending exactly at MAX is kept whole", case5 },
        .{ "a cut that would split a syllable backs off to the syllable's start", case6 },
        .{ "a syllable ending exactly at the cut point stays", case7 },
        .{ "bytes that are not UTF-8 are cut at the cut point", case8 },
        .{ "pieces of a Line leave in one write only at flush", case9 },
        .{ "a Line that is never flushed writes nothing", case10 },
        .{ "after a cut further pieces are dropped, and flush starts a fresh line", case11 },
        .{ "a buffer no larger than the mark writes nothing instead of panicking", case12 },
        .{ "pieces after a cut that backed off do not land after the mark", case13 },
    };
    inline for (cases) |c| {
        c[1]() catch |err| {
            std.debug.print("FAIL: {s}: {s}\n", .{ c[0], @errorName(err) });
            return err;
        };
        std.debug.print("logline_test: {s} OK\n", .{c[0]});
    }
}
