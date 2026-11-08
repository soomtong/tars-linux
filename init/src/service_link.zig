//! TP-M11 plan 결정 C. `tars-service enable|disable NAME`이 무엇을 할지 정하는 순수 함수들.
//!
//! 켜기는 `/config/services.d/NAME -> /etc/tars/services/NAME` 링크 하나이고(sshd의 `tars-config ssh on`과 같은 모양),
//! 그 뒤 init에 `reload`를 보내면 init이 새 이름을 띄우고 사라진 이름을 멈춘다(reload design 결정 11). 새 감독 장치가 없다.
//! 파일 시스템과 소켓은 `service_cli.zig`가 만지고, 여기는 판정만 한다 — `service_link_test.zig`가 호스트에서 본다.
const std = @import("std");
const services = @import("services.zig");

pub const TEMPLATE_DIR = "/etc/tars/services";

pub const Verb = enum { enable, disable };

/// 링크 경로를 짓는 이름이라 control의 검사보다 좁다. `/`는 디렉터리를 넘고, `.`으로 시작하면
/// `services.discover`가 건너뛰며(숨은 파일), 공백 · 제어 문자는 요청의 낱말을 가른다.
pub fn nameOk(name: []const u8) bool {
    if (name.len == 0 or name.len > services.NAME_MAX) return false;
    if (name[0] == '.') return false;
    for (name) |b| if (b <= 0x20 or b == 0x7f or b == '/') return false;
    return true;
}

pub const Link = enum {
    /// services.d에 그 이름이 없다.
    none,
    /// 이 명령이 만드는 그 링크다.
    template,
    /// 다른 무엇이다 — 사람이 둔 파일이거나 다른 곳을 가리키는 링크. 손대지 않는다.
    other,
};

/// `readlink` 결과로 가른다. `target`이 null이면 이름이 없었다(ENOENT),
/// `not_link`면 무언가 있지만 링크가 아니다(EINVAL).
pub fn classify(target: ?[]const u8, not_link: bool, template: []const u8) Link {
    if (not_link) return .other;
    const t = target orelse return .none;
    return if (std.mem.eql(u8, t, template)) .template else .other;
}

pub const Step = enum {
    /// 링크를 만든다.
    link,
    /// 링크를 지운다.
    unlink,
    /// 이미 켜져 있다 — 링크는 그대로, reload는 보낸다(포기된 것을 다시 세우지는 않는다 — 그건 start).
    already_on,
    already_off,
    /// 남의 것이다. 거절.
    foreign,
};

pub fn decide(verb: Verb, link: Link) Step {
    return switch (link) {
        .other => .foreign,
        .none => if (verb == .enable) .link else .already_off,
        .template => if (verb == .enable) .already_on else .unlink,
    };
}

pub const Said = enum { starts, stops };

/// reload의 답에서 그 서비스의 줄을 찾는다. init은 `service NAME: starts`, `service NAME: starts (new in …)`,
/// `service NAME: stops`를 쓴다(main.zig `steer` · `doReload`). 그 밖의 줄(`no free slot` 등)은 null — 기다릴 것이 없다.
pub fn said(reply: []const u8, label: []const u8) ?Said {
    var lines = std.mem.splitScalar(u8, reply, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, label)) continue;
        const rest = line[label.len..];
        if (std.mem.startsWith(u8, rest, ": starts")) return .starts;
        if (std.mem.startsWith(u8, rest, ": stops")) return .stops;
    }
    return null;
}
