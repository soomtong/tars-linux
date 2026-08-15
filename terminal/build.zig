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

    const vt_test_mod = b.createModule(.{
        .root_source_file = b.path("src/vt_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    vt_test_mod.addImport("ghostty-vt", ghostty_dep.module("ghostty-vt"));
    const vt_test = b.addExecutable(.{
        .name = "vt_test",
        .root_module = vt_test_mod,
    });
    b.installArtifact(vt_test);

    // ── 여기서부터는 게스트가 아니라 **빌드 호스트**가 실행한다 ──────────
    //
    // project_build_host_arch의 4번 규칙: "이 산출물은 누가 실행하는가"를
    // 먼저 묻는다. input_test는 QEMU 게스트가 아니라 컨테이너가 직접
    // 실행하므로 컨테이너의 아키텍처(arm64)로 빌드해야 한다. 위의 `target`
    // (x86_64 고정)을 그대로 쓰면 빌드는 되지만 실행이 안 된다 — 실제로
    // ZM-M3에서 컨테이너를 arm64로 바꾼 뒤 이 바이너리는 아무도 실행하지
    // 못하는 상태로 남아 있었다.
    //
    // 빈 쿼리 `.{}`가 네이티브다.
    const host_target = b.resolveTargetQuery(.{});

    const input_test_mod = b.createModule(.{
        .root_source_file = b.path("src/input_test.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    input_test_mod.link_libc = true;
    const input_test = b.addExecutable(.{
        .name = "input_test",
        .root_module = input_test_mod,
    });
    b.installArtifact(input_test);

    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
    //
    // 기본 `zig build`와 분리하는 이유는 속도다. 기본 빌드는 x86_64
    // terminal 본체까지 만드느라 vendor 트리(stb_truetype, libghostty-vt)가
    // 준비돼 있어야 하지만, 이 step은 input_test 하나만 필요하다.
    const test_step = b.step("test", "호스트 아키텍처로 도는 검사를 실행한다");
    test_step.dependOn(&b.addRunArtifact(input_test).step);

    // pty_test와 vt_test는 x86_64로 남겨둔다. 호스트로 옮길 수 없어서다:
    //   pty_test  — /usr/bin/fish를 exec한다. 그 fish는 게스트용 x86_64다.
    //   vt_test   — libghostty-vt를 arm64로 빌드해야 하는데 검증된 적이 없다
    //               (src/simd/ 아래에 벡터 코드가 있다).
    // 둘 다 지금은 빌드만 되고 아무도 실행하지 않는다는 사실을 여기 적어둔다.
}
