const std = @import("std");
const drm = @import("drm.zig");

const c = @cImport({
    @cInclude("unistd.h");
});

const BACKGROUND: u32 = 0x00102030;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const fb = try drm.open(allocator, "/dev/dri/card0");
    fb.fill(BACKGROUND);
    std.debug.print("terminal: filled framebuffer with background\n", .{});
    try fb.present();

    while (true) {
        _ = c.sleep(1);
    }
}
