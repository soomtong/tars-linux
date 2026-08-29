const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .gnu,
        .cpu_model = .baseline,
    });
    const optimize = b.standardOptimizeOption(.{});

    // GL-M3: **게스트로 가는 것**의 최적화 모드. 위의 `optimize`와 갈라 놓은
    // 것이 이 milestone의 핵심 결정이다.
    //
    // 이 저장소에는 별도의 배포 경로가 없다 — prepare.sh가 만든 바이너리가
    // 그대로 initrd에 들어가고 게이트가 그것을 부팅한다. **게이트가 부팅하는
    // 바이너리가 곧 제품이다.** 그래서 "개발은 Debug, 배포는 Release"를 그대로
    // 옮기면 게이트가 배포되지 않는 것을 검사하게 된다
    // (docs/decisions/project_gate_chain_composition.md의 "게이트는 자기가 안
    // 보는 것을 통과시킨다"와 같은 병이다). **기본값이 배포되는 것과 같아야
    // 하는 이유가 이것이다.**
    //
    // 그래도 문은 둔다. 소스를 고친 뒤 `zig build`가 Debug 17.7초 대
    // ReleaseSafe 27.1초라 개발 한 바퀴에 9.4초가 붙기 때문이다. 다만 그
    // 문은 명시적으로 열어야 한다:
    //
    //   zig build -Dguest-optimize=Debug
    //
    // **이 문이 게이트를 흔들지 않는다.** clean()이 zig-out을 지우고 여덟
    // 체인이 각자 부르는 prepare.sh:20이 **옵션 없이** zig build를 부르므로,
    // 손으로 남긴 Debug 바이너리는 다음 게이트가 기본값으로 덮어쓴다.
    //
    // 위의 `optimize`는 이제 **호스트 검사 전용**이다. 그쪽은 게스트에 안
    // 가므로 크기와 무관하고, 최적화하면 `zig build test`만 느려진다
    // (소스를 고친 뒤 9.5초 대 25.8초). init/build.zig:29가 같은 선을 긋는다.
    const guest_optimize = b.option(
        std.builtin.OptimizeMode,
        "guest-optimize",
        "게스트로 가는 terminal 바이너리의 최적화 모드 (기본 ReleaseSafe)",
    ) orelse .ReleaseSafe;

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        // GL-M3: Debug 49,373,160 → ReleaseSafe 10,577,200바이트(78.6% 감소).
        // initrd는 16,199,658 → 10,988,958바이트가 된다. 이 길이 열린 것은
        // fortify를 세 자리에서 껐기 때문이다(drm.zig · main.zig · pty.zig).
        .optimize = guest_optimize,
    });
    exe_mod.addIncludePath(b.path("vendor"));
    exe_mod.addCSourceFile(.{
        .file = b.path("src/stb_truetype_impl.c"),
        .flags = &.{},
    });
    exe_mod.link_libc = true;
    exe_mod.linkSystemLibrary("m", .{});

    // 이 의존도 게스트로 간다. 함께 옮기는 것이 공짜라는 것을 쟀다 —
    // exe_mod만 옮기면 11,218,920바이트에 clean 빌드 71.0초이고, 둘 다
    // 옮기면 10,577,200바이트에 70.9초다. **작아지면서 안 느려진다.**
    //
    // 그리고 이쪽이 성능의 본체다. searchAll()의 60~70밀리초를 쓰는 코드가
    // 여기 있다(CN-M1 실측). 아래 ghostty_host_dep은 호스트 검사용이라
    // `optimize`를 그대로 쓴다.
    const ghostty_dep = b.dependency("ghostty", .{
        .target = target,
        .optimize = guest_optimize,
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

    // vt_test도 호스트에서 돈다. 2026-08-23에 libghostty-vt를 aarch64로
    // 빌드해 실행되는 것을 확인했다 — 그전까지 "검증된 적이 없다"는 이유로
    // x86_64에 남겨 두었고, 그래서 **빌드만 되고 아무도 실행하지 않았다.**
    // simd는 Google Highway를 쓰고 ghostty 자체가 Apple Silicon에서 도는
    // 프로그램이라 놀랄 일은 아니었다.
    const ghostty_host_dep = b.dependency("ghostty", .{
        .target = host_target,
        .optimize = optimize,
    });
    const vt_test_mod = b.createModule(.{
        .root_source_file = b.path("src/vt_test.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    vt_test_mod.addImport("ghostty-vt", ghostty_host_dep.module("ghostty-vt"));
    const vt_test = b.addExecutable(.{
        .name = "vt_test",
        .root_module = vt_test_mod,
    });
    b.installArtifact(vt_test);

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

    // font_test도 호스트에서 돈다. 폰트 래스터라이저는 게스트 하드웨어와
    // 아무 상관이 없다 — stb_truetype에 바이트를 먹이고 비트맵을 받는 순수
    // 계산이라, 부팅 1.5초를 쓸 이유가 없다.
    //
    // 이 파일은 TR-M1 전까지 **build.zig에 등록조차 되어 있지 않았다.**
    // 빌드도 실행도 되지 않는 채로 남아 있었고, 그래서 폰트에 관한 단언이
    // 저장소 어디에도 없었다.
    //
    // vendor/fonts/unifont.otf를 상대 경로로 읽으므로 `zig build test`를
    // terminal/ 안에서 돌려야 한다. 게이트가 이미 그렇게 하고 있다.
    const font_test_mod = b.createModule(.{
        .root_source_file = b.path("src/font_test.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    font_test_mod.addIncludePath(b.path("vendor"));
    font_test_mod.addCSourceFile(.{
        .file = b.path("src/stb_truetype_impl.c"),
        .flags = &.{},
    });
    font_test_mod.link_libc = true;
    font_test_mod.linkSystemLibrary("m", .{});
    const font_test = b.addExecutable(.{
        .name = "font_test",
        .root_module = font_test_mod,
    });
    b.installArtifact(font_test);

    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
    //
    // 기본 `zig build`와 분리하는 이유는 속도였는데, **그 이유가 이제 거의
    // 남지 않았다.** TR-M0에서 vt_test가 들어오면서 libghostty-vt가 필요해졌고,
    // TR-M1에서 font_test가 들어오면서 stb_truetype까지 필요해졌다. 남은
    // 차이는 x86_64 terminal 본체와 pty_test를 안 만든다는 것뿐이다.
    // 두 vendor 트리가 없으면(prepare.sh를 안 돌렸으면) 여기서 막힌다.
    const test_step = b.step("test", "호스트 아키텍처로 도는 검사를 실행한다");
    test_step.dependOn(&b.addRunArtifact(input_test).step);
    test_step.dependOn(&b.addRunArtifact(vt_test).step);
    test_step.dependOn(&b.addRunArtifact(font_test).step);

    // pty_test만 x86_64로 남는다. /usr/bin/fish를 exec하는데 그 fish는
    // 게스트용 x86_64라 호스트로 옮길 수 없다 — **빌드만 되고 아무도
    // 실행하지 않는다.** vt_test는 TR-M0에서 호스트로 옮겨 이제 돈다.
}
