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

    // DI-M1: 설치기. init과 같은 타깃·같은 모드이고 libc를 안 쓴다 — 게스트에
    // mount 명령이 없어서 시스템 콜로 붙이는 것까지 init과 같다(DI design
    // 결정 5). 별도 exe인 이유는 부팅 경로에 안 들어가야 해서다.
    // make_initrd.sh가 zig-out/bin/tars-install을 usr/bin에 싣는다.
    const install_mod = b.createModule(.{
        .root_source_file = b.path("src/install.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .single_threaded = true,
    });
    const install_exe = b.addExecutable(.{
        .name = "tars-install",
        .root_module = install_mod,
    });
    b.installArtifact(install_exe);

    // ── 여기서부터는 게스트가 아니라 빌드 호스트가 실행한다 ──────────
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

    // RM-M2: ext2 superblock의 매직과 라벨을 보는 함수의 검사. 이것도
    // 게스트가 아니라 컨테이너가 직접 실행하므로 host_target이다.
    // storage.zig의 tarsLabel은 시스템 콜을 안 하는 순수 함수라(devices.zig가
    // bitSet을 그렇게 가른 것과 같은 선) 진짜 블록 장치가 필요 없다 —
    // 이 검사가 개발 기계의 디스크를 건드리지 않는다.
    const storage_test_mod = b.createModule(.{
        .root_source_file = b.path("src/storage_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const storage_test = b.addExecutable(.{
        .name = "storage_test",
        .root_module = storage_test_mod,
    });

    // UT-M0: 커널 envp 블록에 PATH를 더하는 함수의 검사. storage_test와 같은
    // 이유로 host_target이다 — environ.zig는 시스템 콜을 하나도 안 하는 순수
    // 계산이라 게스트가 필요 없다. main.zig에 두면 이 검사가 원리적으로
    // 불가능해진다(PID 1의 감독 루프는 호스트에서 못 돈다).
    const environ_test_mod = b.createModule(.{
        .root_source_file = b.path("src/environ_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const environ_test = b.addExecutable(.{
        .name = "environ_test",
        .root_module = environ_test_mod,
    });

    // TD-M1: 시계를 chronyd에게 넘기는 배관의 순수한 쪽 셋(설정 파일 ·
    // 기본 경로 · 서버 파일). 위 다섯과 같은 이유로 host_target이다 —
    // clock.zig에서 시스템 콜을 하는 부분은 이 셋 아래에만 있다.
    //
    // TS-M1부터 있던 sntp_test의 자리다. 패킷과 era를 보던 검사는 그 코드와
    // 함께 지웠다(TD design 결정 1).
    const clock_test_mod = b.createModule(.{
        .root_source_file = b.path("src/clock_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const clock_test = b.addExecutable(.{
        .name = "clock_test",
        .root_module = clock_test_mod,
    });

    // DI-M1: 설치기의 순수한 쪽(디스크 앞머리 판정 · 크기 · 인자 · YES).
    // storage_test와 같은 이유로 host_target이다.
    const disk_test_mod = b.createModule(.{
        .root_source_file = b.path("src/disk_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const disk_test = b.addExecutable(.{
        .name = "disk_test",
        .root_module = disk_test_mod,
    });

    // installArtifact를 부르지 않는다. terminal/build.zig의 input_test는
    // 부르는데, 그건 TF-M3 시절 손으로 ./zig-out/bin/input_test를 돌리던
    // 잔재다. 여기는 처음부터 `zig build test`로만 도므로 install할 이유가
    // 없고, 네 체인이 전부 부르는 `zig build`를 무겁게 하지 않는다.
    const test_step = b.step("test", "호스트 아키텍처로 도는 검사를 실행한다");
    test_step.dependOn(&b.addRunArtifact(config_test).step);
    test_step.dependOn(&b.addRunArtifact(power_test).step);
    test_step.dependOn(&b.addRunArtifact(devices_test).step);
    test_step.dependOn(&b.addRunArtifact(storage_test).step);
    test_step.dependOn(&b.addRunArtifact(environ_test).step);
    test_step.dependOn(&b.addRunArtifact(clock_test).step);
    test_step.dependOn(&b.addRunArtifact(disk_test).step);
}
