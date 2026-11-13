//! `display_proto.zig`의 호스트 검사(DY-M0). `make quick`이 `zig run`으로 돌린다.

const std = @import("std");
const p = @import("display_proto.zig");

pub fn main() !void {
    // 왕복: 보낸 글자가 그 값으로 돌아온다.
    for (std.enums.values(p.Request)) |v| {
        if (p.parseRequest(p.text(v)) != v) return error.RequestRoundTrip;
    }
    for (std.enums.values(p.Reply)) |v| {
        if (p.parseReply(p.text(v)) != v) return error.ReplyRoundTrip;
        if (p.text(v).len > p.MSG_MAX) return error.ReplyTooLong;
    }
    // 낱말 그대로만 — 줄 끝 · 공백 · 대문자 · 빈 것 · 다른 쪽의 낱말은 거절이다.
    for ([_][]const u8{ "yield\n", " yield", "Yield", "", "ok", "yield yield" }) |b| {
        if (p.parseRequest(b) != null) {
            std.debug.print("FAIL: parseRequest accepted \"{s}\"\n", .{b});
            return error.RequestAccepted;
        }
    }
    for ([_][]const u8{ "ok\n", "yield", "OK", "" }) |b| {
        if (p.parseReply(b) != null) {
            std.debug.print("FAIL: parseReply accepted \"{s}\"\n", .{b});
            return error.ReplyAccepted;
        }
    }
    // socket 경로는 sockaddr_un의 108바이트 안이다.
    if (p.PATH.len >= 108) return error.PathTooLong;
    if (!std.mem.startsWith(u8, p.PATH, p.DIR)) return error.PathOutsideDir;
    std.debug.print("display_proto_test: yield · ok · busy · refused round-trip, only the bare words parse\n", .{});
}
