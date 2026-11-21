//! 클립보드의 순수한 셈(TK-M4 plan 확정 12, 호스트 검사). 받을 mime 고르기 — 서버 `wl_logic.pickMime`과 같은 우선순위(`text/plain;charset=utf-8` ·
//! `text/plain` · `UTF8_STRING` · `TEXT`, WY 결정 34). offer의 mime은 아는 넷의 비트로 든다.

const std = @import("std");

/// 내는 mime(복사)이자 받을 때의 우선순위. 서버가 이 순서로 고르고 offer한다.
pub const MIMES = [_][:0]const u8{ "text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "TEXT" };

/// 아는 mime이면 그 비트.
pub fn bit(mime: []const u8) u8 {
    for (MIMES, 0..) |m, i| if (std.mem.eql(u8, m, mime)) return @as(u8, 1) << @intCast(i);
    return 0;
}

/// offer의 비트에서 받을 mime(없으면 null).
pub fn pick(mask: u8) ?[:0]const u8 {
    for (MIMES, 0..) |m, i| if (mask & (@as(u8, 1) << @intCast(i)) != 0) return m;
    return null;
}
