const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .gnu,
        .cpu_model = .baseline,
    });
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addIncludePath(b.path("vendor"));
    exe_mod.addCSourceFile(.{
        .file = b.path("src/stb_truetype_impl.c"),
        .flags = &.{},
    });
    exe_mod.link_libc = true;
    exe_mod.linkSystemLibrary("m", .{});

    const ghostty_dep = b.dependency("ghostty", .{
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("ghostty-vt", ghostty_dep.module("ghostty-vt"));

    const exe = b.addExecutable(.{
        .name = "terminal",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const pty_test_mod = b.createModule(.{
        .root_source_file = b.path("src/pty_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    pty_test_mod.link_libc = true;
    const pty_test = b.addExecutable(.{
        .name = "pty_test",
        .root_module = pty_test_mod,
    });
    b.installArtifact(pty_test);
}
