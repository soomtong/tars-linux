//! 미리보기의 판정과 읽기(TK-M6 plan 확정 12 · 13, R-FM-5). 순수한 판정(`classify` · `textOf`)은 호스트 검사가 부르고, 읽기(`readHead`)는
//! 파일 하나를 열어 앞부분만 읽는 작은 함수다 — 디코더(`tk.cg.image`)는 파일을 모르고 여기서 읽은 바이트만 받는다(plan 확정 15).
//!
//! 판정 순서(plan 확정 12): 디렉터리 → 아이콘. 일반 파일은 바이트 머리가 PNG · JPEG면 그림(입력 16 MiB를 넘으면 "너무 큼" 아이콘), 아니면
//! 크기 ≤ 1 MiB이고 앞 8 KiB에 NUL이 없으면 텍스트(앞 16 KiB만 그린다), 그 밖은 아이콘(이진 · 너무 큼).

const std = @import("std");
const linux = std.os.linux;

/// 텍스트 미리보기가 다루는 파일 크기의 상한(R-FM-5).
pub const TEXT_MAX: u64 = 1024 * 1024;
/// 텍스트로 읽어 그리는 앞부분(plan 확정 12 — 판에 보이는 줄은 스무 남짓이다).
pub const TEXT_HEAD: usize = 16 * 1024;
/// 이진 판정에 보는 앞부분(git의 규칙과 같은 8 KiB).
pub const SNIFF: usize = 8 * 1024;
/// 그림 입력의 상한(요구사항 결정 13 — `tk.cg.image.MAX_INPUT`과 같은 값).
pub const IMAGE_MAX: u64 = 16 * 1024 * 1024;

pub const Reason = enum { dir, binary, big, unreadable };

pub const Kind = union(enum) {
    text,
    png,
    jpeg,
    icon: Reason,
};

/// 일반 파일의 판정 — `head`는 파일 앞부분(많아야 `SNIFF` 이상 읽은 것), `size`는 파일 크기.
pub fn classify(head: []const u8, size: u64) Kind {
    if (head.len >= 8 and std.mem.eql(u8, head[0..8], "\x89PNG\r\n\x1a\n")) return if (size > IMAGE_MAX) .{ .icon = .big } else .png;
    if (head.len >= 3 and head[0] == 0xFF and head[1] == 0xD8 and head[2] == 0xFF) return if (size > IMAGE_MAX) .{ .icon = .big } else .jpeg;
    if (size > TEXT_MAX) return .{ .icon = .big };
    if (std.mem.indexOfScalar(u8, head[0..@min(head.len, SNIFF)], 0) != null) return .{ .icon = .binary };
    return .text;
}

/// 그릴 글: 탭은 공백 넷, `\r`은 뺀다, 끝에서 잘린 UTF-8 한 글자는 버린다(앞 16 KiB에서 끊긴 자리). 결과는 `out`의 앞.
pub fn textOf(raw: []const u8, out: []u8) []const u8 {
    var end = raw.len;
    // 끝의 잘린 다중 바이트: 마지막 시작 바이트부터 남은 길이가 모자라면 뗀다.
    var k: usize = 0;
    while (k < 4 and k < end) : (k += 1) {
        const b = raw[end - 1 - k];
        if (b & 0xC0 != 0x80) {
            const need: usize = if (b & 0x80 == 0) 1 else if (b & 0xE0 == 0xC0) 2 else if (b & 0xF0 == 0xE0) 3 else if (b & 0xF8 == 0xF0) 4 else 1;
            if (need > k + 1) end -= k + 1;
            break;
        }
    }
    var n: usize = 0;
    for (raw[0..end]) |c| {
        switch (c) {
            '\t' => for (0..4) |_| {
                if (n < out.len) {
                    out[n] = ' ';
                    n += 1;
                }
            },
            '\r' => {},
            else => if (n < out.len) {
                out[n] = c;
                n += 1;
            },
        }
    }
    return out[0..n];
}

pub const Head = struct {
    size: u64,
    /// 잡은 칸(부르는 쪽의 allocator로 놓는다)과 그중 읽은 길이.
    buf: []u8,
    n: usize,

    pub fn bytes(self: *const Head) []const u8 {
        return self.buf[0..self.n];
    }

    pub fn deinit(self: *Head, alloc: std.mem.Allocator) void {
        alloc.free(self.buf);
    }
};

/// 파일 `path`를 열어 크기를 보고 앞 `max`바이트(파일이 작으면 전부)를 읽는다. 일반 파일이 아니거나 못 열면 null.
pub fn readHead(alloc: std.mem.Allocator, path: []const u8, max: u64) ?Head {
    var pbuf: [4097]u8 = undefined;
    if (path.len >= pbuf.len) return null;
    @memcpy(pbuf[0..path.len], path);
    pbuf[path.len] = 0;
    const rc = linux.openat(linux.AT.FDCWD, @ptrCast(&pbuf), .{ .ACCMODE = .RDONLY, .CLOEXEC = true, .NONBLOCK = true }, 0);
    if (linux.errno(rc) != .SUCCESS) return null;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var st: linux.Statx = undefined;
    if (linux.errno(linux.statx(fd, "", linux.AT.EMPTY_PATH, .{ .TYPE = true, .SIZE = true }, &st)) != .SUCCESS) return null;
    if (st.mode & linux.S.IFMT != linux.S.IFREG) return null;
    const want: usize = @intCast(@min(st.size, max));
    const buf = alloc.alloc(u8, want) catch return null;
    var n: usize = 0;
    while (n < want) {
        const r = linux.read(fd, buf[n..].ptr, want - n);
        if (linux.errno(r) == .INTR) continue;
        if (linux.errno(r) != .SUCCESS or r == 0) break;
        n += r;
    }
    return .{ .size = st.size, .buf = buf, .n = n };
}
