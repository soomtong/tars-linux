//! 빌드에 박을 버전 글자(BV-M0).
//!
//! 원천은 저장소 뿌리의 `VERSION` 한 줄이고, build.zig가 git에 물어 "이 트리가 그
//! 태그 그대로인가"를 알아 온다. 여기는 그 답들로 글자만 짓는다 — git을 부르는 일은
//! build.zig에만 있고, 이 파일은 시스템 콜이 없어 version_test가 호스트에서 본다
//! (docs/specs/2026-10-20-tars-build-version-design.md 결정 6).

const std = @import("std");

/// `VERSION`의 한 줄이 넘으면 안 되는 길이(design 결정 1).
pub const BASE_MAX = 64;
/// 지은 글자의 최대 길이 — 번호, `+`, 커밋(git이 더 길게 줘도 40자), `-dirty`.
pub const MAX = BASE_MAX + 1 + 40 + "-dirty".len;

pub const BaseError = error{ Empty, TooLong };

/// `VERSION` 파일의 글자에서 앞뒤 공백 · 줄바꿈을 벗긴다. 비었거나 길면 거절한다 —
/// 버전 없는 이미지를 조용히 굽지 않는다.
pub fn base(text: []const u8) BaseError![]const u8 {
    const t = std.mem.trim(u8, text, " \t\r\n");
    if (t.len == 0) return error.Empty;
    if (t.len > BASE_MAX) return error.TooLong;
    return t;
}

/// design 결정 2의 표. `head`는 HEAD의 짧은 커밋이고, null이면 git을 못 쓴 것이라
/// (결정 3) `ver` 그대로다 — 그때는 dirty도 모른다.
pub fn format(buf: *[MAX]u8, ver: []const u8, head: ?[]const u8, tag_matches: bool, dirty: bool) []const u8 {
    const h = head orelse return ver;
    if (tag_matches and !dirty) return ver;
    return std.fmt.bufPrint(buf, "{s}+{s}{s}", .{ ver, h[0..@min(h.len, 40)], if (dirty) "-dirty" else "" }) catch unreachable;
}
