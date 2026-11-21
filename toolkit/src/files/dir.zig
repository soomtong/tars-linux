//! 게스트의 `DirSource`(TK-M3 plan 확정 9 · 11) — getdents64로 디렉터리를 32 KiB씩 읽는다. `next` 한 번이 getdents64 한 번이다(메인 루프의
//! idle 한 조각). 종류는 `d_type`으로 정하고, 링크와 `DT_UNKNOWN`만 statx로 따라가 정한다(깨진 링크 · 못 따라가는 것은 파일). 소켓 · 장치 ·
//! FIFO는 파일로 보인다. 취소는 `close`(fd를 닫는다).
//!
//! 앞의 이름 조각은 다음 `next`까지 산다(손잡이의 버퍼를 다시 쓴다).

const std = @import("std");
const linux = std.os.linux;
const model = @import("model.zig");

pub const BUF_SIZE: usize = 32 * 1024;

const Handle = struct {
    fd: i32,
    buf: [BUF_SIZE]u8 align(8) = undefined,
    raws: std.ArrayList(model.Raw) = .empty,
};

pub const Dir = struct {
    alloc: std.mem.Allocator,

    pub fn source(self: *Dir) model.DirSource {
        return .{ .ctx = self, .open = open, .next = next, .close = close };
    }

    fn me(ctx: *anyopaque) *Dir {
        return @ptrCast(@alignCast(ctx));
    }

    fn open(ctx: *anyopaque, path: []const u8) anyerror!*anyopaque {
        const self = me(ctx);
        var pbuf: [4096]u8 = undefined;
        if (path.len >= pbuf.len) return error.NameTooLong;
        @memcpy(pbuf[0..path.len], path);
        pbuf[path.len] = 0;
        const rc = linux.openat(linux.AT.FDCWD, @ptrCast(&pbuf), .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
        switch (linux.errno(rc)) {
            .SUCCESS => {},
            .ACCES, .PERM => return error.AccessDenied,
            .NOENT => return error.FileNotFound,
            .NOTDIR => return error.NotDir,
            else => return error.OpenFailed,
        }
        const h = try self.alloc.create(Handle);
        h.* = .{ .fd = @intCast(rc) };
        return h;
    }

    fn next(ctx: *anyopaque, handle: *anyopaque) anyerror!?[]const model.Raw {
        const self = me(ctx);
        const h: *Handle = @ptrCast(@alignCast(handle));
        const rc = linux.getdents64(h.fd, &h.buf, BUF_SIZE);
        if (linux.errno(rc) != .SUCCESS) return error.ReadFailed;
        if (rc == 0) return null;
        h.raws.clearRetainingCapacity();
        var off: usize = 0;
        while (off < rc) {
            const d: *align(1) const linux.dirent64 = @ptrCast(&h.buf[off]);
            const reclen = d.reclen;
            const name_ptr: [*:0]const u8 = @ptrCast(&h.buf[off + @offsetOf(linux.dirent64, "name")]);
            const name = std.mem.span(name_ptr);
            const kind: model.Kind = switch (d.type) {
                linux.DT.DIR => .dir,
                linux.DT.LNK, linux.DT.UNKNOWN => follow(h.fd, name_ptr),
                else => .file,
            };
            try h.raws.append(self.alloc, .{ .name = name, .kind = kind });
            off += reclen;
        }
        return h.raws.items;
    }

    fn close(ctx: *anyopaque, handle: *anyopaque) void {
        const self = me(ctx);
        const h: *Handle = @ptrCast(@alignCast(handle));
        _ = linux.close(h.fd);
        h.raws.deinit(self.alloc);
        self.alloc.destroy(h);
    }
};

/// 링크 · 모르는 종류를 따라가 디렉터리인가 본다. 못 따라가면(깨진 링크) 파일.
fn follow(dirfd: i32, name: [*:0]const u8) model.Kind {
    var st: linux.Statx = undefined;
    const rc = linux.statx(dirfd, name, 0, .{ .TYPE = true }, &st);
    if (linux.errno(rc) != .SUCCESS) return .file;
    return if (st.mode & linux.S.IFMT == linux.S.IFDIR) .dir else .file;
}
