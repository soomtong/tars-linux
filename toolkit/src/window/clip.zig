//! 클립보드의 순수한 셈(TK-M4 plan 확정 12, 호스트 검사). 받을 mime 고르기 — 서버 `wl_logic.pickMime`과 같은 우선순위(`text/plain;charset=utf-8` ·
//! `UTF8_STRING` · `text/plain` · `TEXT`, WY 결정 34, `PICK_ORDER`). offer의 mime은 아는 넷의 비트로 든다.

const std = @import("std");

/// 내는(offer) mime 목록이자 `bit`의 번호 매기기 순서. 받을 때의 우선순위는 `PICK_ORDER`가 따로 정한다.
pub const MIMES = [_][:0]const u8{ "text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "TEXT" };

/// 받을 때의 우선순위. terminal 모듈의 `wl_logic.PICK_ORDER`와 같아야 한다 — toolkit은 terminal을 import하지 않아 복사해 둔다
/// (UTF8_STRING이 bare text/plain보다 앞: 서버와 어긋나면 같은 offer에서 앱마다 다른 mime을 받는다).
pub const PICK_ORDER = [_][:0]const u8{ "text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "TEXT" };

/// 아는 mime이면 그 비트.
pub fn bit(mime: []const u8) u8 {
    for (MIMES, 0..) |m, i| if (std.mem.eql(u8, m, mime)) return @as(u8, 1) << @intCast(i);
    return 0;
}

/// offer의 비트에서 받을 mime(없으면 null).
pub fn pick(mask: u8) ?[:0]const u8 {
    for (PICK_ORDER) |m| if (mask & bit(m) != 0) return m;
    return null;
}
