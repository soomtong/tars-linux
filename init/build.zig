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

    // CT-M1: 서비스를 멈추고 띄우는 명령. tars-install과 같은 까닭으로 따로 된 exe이고
    // 같은 타깃 · 모드다. make_initrd.sh가 zig-out/bin/tars-service를 usr/bin에 싣는다.
    const service_mod = b.createModule(.{
        .root_source_file = b.path("src/service_cli.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .single_threaded = true,
    });
    const service_exe = b.addExecutable(.{
        .name = "tars-service",
        .root_module = service_mod,
    });
    b.installArtifact(service_exe);

    // TC-M0: /config/tars.conf를 보고 고치는 명령. tars-service와 같은 까닭으로 따로 된
    // exe이고 같은 타깃 · 모드다. config.zig를 init과 함께 쓰는 것이 요점이다 — 값을
    // 받을지는 init이 부팅에 쓰는 그 parse가 정한다(TC design 결정 3).
    // make_initrd.sh가 zig-out/bin/tars-config를 usr/bin에 싣는다.
    const config_cli_mod = b.createModule(.{
        .root_source_file = b.path("src/config_cli.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .single_threaded = true,
    });
    const config_cli_exe = b.addExecutable(.{
        .name = "tars-config",
        .root_module = config_cli_mod,
    });
    b.installArtifact(config_cli_exe);

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

    // TD-M1: 시계를 chronyd에게 넘기는 배관의 순수한 쪽 둘(설정 파일 ·
    // 서버 파일). 위 다섯과 같은 이유로 host_target이다 — clock.zig에서
    // 시스템 콜을 하는 부분은 이 둘 아래에만 있다.
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

    // SV-M1: services.d를 읽고 고르는 것의 검사. devices_test와 같은 이유로
    // host_target이다 — discover가 디렉터리 경로를 인자로 받으므로 /tmp의 가짜
    // 디렉터리를 읽는다.
    const services_test_mod = b.createModule(.{
        .root_source_file = b.path("src/services_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const services_test = b.addExecutable(.{
        .name = "services_test",
        .root_module = services_test_mod,
    });

    // SV-M2: 로그인 셸과 sshd의 SetEnv를 쓰는 것의 검사. apply가 경로를 인자로
    // 받으므로 /tmp의 파일에 쓴다 — 개발 기계의 /etc/passwd를 안 건드린다.
    const login_test_mod = b.createModule(.{
        .root_source_file = b.path("src/login_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const login_test = b.addExecutable(.{
        .name = "login_test",
        .root_module = login_test_mod,
    });

    // CT-M1: 통로 · 감독 규칙 · 글자. login_test와 같은 이유로 host_target이다 —
    // 규칙은 anytype으로 필드만 만져 가짜 구조체로 보고, 소켓은 /tmp에 연다.
    const control_test_mod = b.createModule(.{
        .root_source_file = b.path("src/control_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const control_test = b.addExecutable(.{
        .name = "control_test",
        .root_module = control_test_mod,
    });

    // WL-M2: wpa_supplicant를 감독 목록에 넣을지의 검사. login_test와 같은 이유로
    // host_target이다 — `wants`가 설정 파일 경로를 인자로 받아 /tmp를 본다.
    const wifi_test_mod = b.createModule(.{
        .root_source_file = b.path("src/wifi_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const wifi_test = b.addExecutable(.{
        .name = "wifi_test",
        .root_module = wifi_test_mod,
    });

    // AU-M1: 믹서를 켜고 적는 배관의 순수한 쪽(동사 · argv · wait status · 적을지).
    // clock_test와 같은 이유로 host_target이다 — audio.zig에서 시스템 콜을 하는
    // 부분은 이 넷 아래에만 있다.
    const audio_test_mod = b.createModule(.{
        .root_source_file = b.path("src/audio_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const audio_test = b.addExecutable(.{
        .name = "audio_test",
        .root_module = audio_test_mod,
    });

    // TC-M0: tars-config의 글자 쪽(줄 고르기 · 줄 바꾸기 · 값의 글자 · 듣기). config_test와
    // 같은 이유로 host_target이다 — config_edit.zig에는 시스템 콜이 없다.
    const config_edit_test_mod = b.createModule(.{
        .root_source_file = b.path("src/config_edit_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const config_edit_test = b.addExecutable(.{
        .name = "config_edit_test",
        .root_module = config_edit_test_mod,
    });

    // TC-M1: 앞문 넷의 글자 쪽(포트 · 규칙 한 줄 · wpa 덩어리 · 키 몸통 · 받아쓰기 키). config_edit_test와
    // 같은 이유로 host_target이다. tars-dictate의 case를 읽으므로 init/에서 돈다(zig build의 자리).
    const config_front_edit_test_mod = b.createModule(.{
        .root_source_file = b.path("src/config_front_edit_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const config_front_edit_test = b.addExecutable(.{
        .name = "config_front_edit_test",
        .root_module = config_front_edit_test_mod,
    });

    // TC-M2: reload가 무엇을 할지(diff · 갈래 · 순서 · services.d · 답의 글자). PID 1의 코드라 셈과
    // 경계를 여기서 다 본다(reload design 결정 8). config_test와 같은 이유로 host_target이다.
    const reload_test_mod = b.createModule(.{
        .root_source_file = b.path("src/reload_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const reload_test = b.addExecutable(.{
        .name = "reload_test",
        .root_module = reload_test_mod,
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
    test_step.dependOn(&b.addRunArtifact(services_test).step);
    test_step.dependOn(&b.addRunArtifact(login_test).step);
    test_step.dependOn(&b.addRunArtifact(control_test).step);
    test_step.dependOn(&b.addRunArtifact(wifi_test).step);
    test_step.dependOn(&b.addRunArtifact(audio_test).step);
    test_step.dependOn(&b.addRunArtifact(config_edit_test).step);
    test_step.dependOn(&b.addRunArtifact(config_front_edit_test).step);
    test_step.dependOn(&b.addRunArtifact(reload_test).step);
}
