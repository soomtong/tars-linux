const std = @import("std");

pub fn build(b: *std.Build) void {
    // 타깃을 호스트 기본값이 아니라 명시적으로 고정한다. 이유는
    // terminal/build.zig와 같다 — 게스트는 항상 x86_64 리눅스이고,
    // ZM-M3에서 빌드 컨테이너가 arm64로 바뀌어도 이 파일은 그대로여야 한다.
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .musl,
        .cpu_model = .baseline,
    });
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // PID 1은 스레드를 만들지 않는다. 끄면 TLS 준비 과정이 빠지고
        // 바이너리도 작아진다.
        .single_threaded = true,
    });
    // link_libc는 건드리지 않는다. 기본값이 false이고, 그것이 이 milestone의
    // 핵심 결정이다 — init이 쓰는 것은 전부 시스템 콜이라 libc가 필요 없고,
    // 링크하지 않으면 정적 바이너리가 되어 initrd에 .so를 넣지 않아도 된다.

    const exe = b.addExecutable(.{
        .name = "init",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    // ── 여기서부터는 게스트가 아니라 **빌드 호스트**가 실행한다 ──────────
    //
    // project_build_host_arch의 4번 규칙: "이 산출물은 누가 실행하는가"를
    // 먼저 묻는다. config_test는 QEMU 게스트가 아니라 컨테이너가 직접
    // 실행하므로 컨테이너의 아키텍처(arm64)로 빌드해야 한다. 위의 target
    // (x86_64-musl 고정)을 그대로 쓰면 빌드는 되지만 실행이 안 된다.
    //
    // 빈 쿼리 `.{}`가 네이티브다. config.zig는 std.os.linux만 쓰므로
    // 호스트에서도 libc 없이 그대로 컴파일된다.
    const host_target = b.resolveTargetQuery(.{});

    const config_test_mod = b.createModule(.{
        .root_source_file = b.path("src/config_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const config_test = b.addExecutable(.{
        .name = "config_test",
        .root_module = config_test_mod,
    });

    // installArtifact를 부르지 않는다. terminal/build.zig의 input_test는
    // 부르는데, 그건 TF-M3 시절 손으로 ./zig-out/bin/input_test를 돌리던
    // 잔재다. 여기는 처음부터 `zig build test`로만 도므로 install할 이유가
    // 없고, 네 체인이 전부 부르는 `zig build`를 무겁게 하지 않는다.
    const test_step = b.step("test", "호스트 아키텍처로 도는 검사를 실행한다");
    test_step.dependOn(&b.addRunArtifact(config_test).step);
}
