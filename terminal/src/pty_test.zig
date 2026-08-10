const std = @import("std");
const pty = @import("pty.zig");

pub fn main() !void {
    const session = try pty.spawnFish("echo \"TARS 하이\"");

    var buf: [4096]u8 = undefined;
    const output = pty.readAll(session.master_fd, &buf);

    std.debug.print("pty output ({d} bytes): {s}\n", .{ output.len, output });

    if (std.mem.indexOf(u8, output, "TARS 하이") == null) {
        std.debug.print("FAIL: expected output to contain 'TARS 하이'\n", .{});
        return error.UnexpectedOutput;
    }
    std.debug.print("PASS\n", .{});
}
