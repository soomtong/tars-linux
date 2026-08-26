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

    // GL-M1: initrd에 들어가는 것은 이 exe 하나뿐이라 여기만 최적화 모드를
    // 고정한다. Debug 11,745,656 → ReleaseSafe 3,331,160바이트(72% 감소)이고,
    // 그만큼 gzip도 부팅 중 압축 해제도 빨라진다.
    //
    // init이 이 길로 갈 수 있는 이유는 libc를 링크하지 않기 때문이다 —
    // terminal을 Debug에 묶어 둔 fortify 제약(@cImport가 최적화 모드에서
    // 깨진다)이 여기에는 없다(docs/decisions/project_zig_c_uapi_rule.md).
    //
    // 게스트 안 에러 트레이스는 살아 있다. ReleaseSafe는 strip이 아니라
    // 심볼도 안전 검사도 유지한다 — strip을 안 쓰기로 한 이유는
    // docs/decisions/project_gate_chain_composition.md에 있다.
    //
    // 아래 세 test_mod는 위의 `optimize`를 그대로 쓴다. 호스트가 돌리는
    // 검사라 크기와 무관하고, 여기까지 최적화하면 `zig build test`만 느려진다.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
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

    // PM-M0: 시그널이 플래그가 되는지 보는 검사. config_test와 같은 자리에
    // 두는 이유는 같다 — 부팅 20초를 쓰기 전에 0.1초로 잡을 수 있는 실패를
    // 먼저 잡는다.
    const power_test_mod = b.createModule(.{
        .root_source_file = b.path("src/power_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const power_test = b.addExecutable(.{
        .name = "power_test",
        .root_module = power_test_mod,
    });

    // HD-M0: sysfs 비트맵을 읽는 함수들을 보는 검사. 이것도 게스트가 아니라
    // 컨테이너가 직접 실행하므로 host_target이다. devices.zig는 진짜 /sys가
    // 아니라 인자로 받은 뿌리 경로를 읽으므로(design 결정 5), 이 검사가
    // 개발 기계의 입력 장치를 건드리지 않는다.
    const devices_test_mod = b.createModule(.{
        .root_source_file = b.path("src/devices_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const devices_test = b.addExecutable(.{
        .name = "devices_test",
        .root_module = devices_test_mod,
    });

    // installArtifact를 부르지 않는다. terminal/build.zig의 input_test는
    // 부르는데, 그건 TF-M3 시절 손으로 ./zig-out/bin/input_test를 돌리던
    // 잔재다. 여기는 처음부터 `zig build test`로만 도므로 install할 이유가
    // 없고, 네 체인이 전부 부르는 `zig build`를 무겁게 하지 않는다.
    const test_step = b.step("test", "호스트 아키텍처로 도는 검사를 실행한다");
    test_step.dependOn(&b.addRunArtifact(config_test).step);
    test_step.dependOn(&b.addRunArtifact(power_test).step);
    test_step.dependOn(&b.addRunArtifact(devices_test).step);
}
