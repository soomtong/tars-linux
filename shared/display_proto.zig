//! 화면 양보의 약속(DY design 결정 3). terminal이 듣는 쪽이고 `tars-fullscreen`이 묻는 쪽이다 —
//! 둘이 같은 파일을 컴파일하므로 경로와 낱말이 어긋날 수 없다. 순수하다(libc · 시스템 콜 없음).
//!
//! 주고받는 것은 낱말 하나씩이다. 손님 → `yield`, terminal → `ok` · `busy` · `refused`.
//! 양보를 끝내는 메시지는 없다 — 연결이 닫히는 것이 끝이다(앱이 어떻게 죽든 커널이 닫는다).

const std = @import("std");

pub const DIR: [:0]const u8 = "/run/tars";
pub const PATH: [:0]const u8 = "/run/tars/display.sock";

/// 메시지 하나의 상한. 가장 긴 낱말이 `refused` 일곱 자다.
pub const MSG_MAX: usize = 16;

pub const Request = enum { yield };

pub const Reply = enum {
    /// terminal이 master를 놓았다. 손님은 이제 `card0`을 열면 master다.
    ok,
    /// 이미 다른 손님이 화면을 가졌거나, 놓은 화면을 아직 되찾지 못했다.
    busy,
    /// master를 놓지 못했다(까닭은 terminal의 로그에), 또는 모르는 요청이다.
    refused,
};

/// 낱말 그대로만 받는다 — 줄 끝 문자도 공백도 없다. 짓는 쪽이 `text` 하나라서다.
pub fn parseRequest(bytes: []const u8) ?Request {
    return std.meta.stringToEnum(Request, bytes);
}

pub fn parseReply(bytes: []const u8) ?Reply {
    return std.meta.stringToEnum(Reply, bytes);
}

/// 보낼 글자. `@tagName`이라 enum의 이름이 곧 선 위의 글자다.
pub fn text(v: anytype) []const u8 {
    return @tagName(v);
}
