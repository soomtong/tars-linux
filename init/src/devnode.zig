const std = @import("std");
const logline = @import("logline.zig");
const linux = std.os.linux;

// udev 없이 장치 노드의 그룹을 여는 일(HP-M1의 `openToAudio`를 DY-M0이 일반화했다).
// devtmpfs가 만든 노드는 root 0600이라 그대로면 화면 셸(uid 1000)이 못 연다. Debian에서
// udev 규칙이 하는 일과 같은 모양이다 — 디렉터리 하나의 노드를 모두 `root:<그룹> 0660`으로.
// 부르는 자리: `/dev/snd`(audio, 카드가 선 뒤) · `/dev/dri`(display, terminal을 띄우기 전).

/// 같은 세 줄짜리 헬퍼다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// `dir` 바로 아래의 노드를 `root:<group> 0660`으로. 한 번 훑고 끝난다 — 뒤에 생긴 노드는
/// 안 바뀐다(init에 uevent가 없다). 결과는 `tars-init: <label>: …` 한 줄이다.
pub fn openNodes(dir: [:0]const u8, gid: u32, group: []const u8, label: []const u8) void {
    const rc = linux.open(dir.ptr, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (failed(rc)) |e| {
        logline.print("tars-init: {s}: cannot open {s} (errno {d}), its nodes stay root 600\n", .{ label, dir, @backingInt(e) });
        return;
    }
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var count: usize = 0;
    var refused: usize = 0;
    var buf: [2048]u8 align(8) = undefined;
    while (true) {
        const n = linux.getdents64(fd, &buf, buf.len);
        if (failed(n) != null or n == 0) break;
        var off: usize = 0;
        while (off < n) {
            const d: *align(1) const linux.dirent64 = @ptrCast(&buf[off]);
            off += d.reclen;
            const name: [*:0]const u8 = @ptrCast(&d.name);
            if (name[0] == '.') continue;
            const own = linux.fchownat(fd, name, 0, gid, 0);
            const mode = linux.fchmodat(fd, name, 0o660);
            if (failed(own) != null or failed(mode) != null) refused += 1 else count += 1;
        }
    }
    logline.print("tars-init: {s}: {d} nodes in {s} are root:{s} 660 ({d} refused)\n", .{ label, count, dir, group, refused });
}
