//! TARS 툴킷의 빌드(TK design 결정 1). terminal의 build와 따로 선다 — "툴킷은 라이브러리"(R-ARCH-3)의 경계를 terminal에 묶지
//! 않으려는 것이다. 부르는 자리는 `terminal/prepare.sh` 끝 한 줄이라 체인들의 BUILD_STEPS는 그대로다.
//!
//! 나오는 것
//!   모듈 `tk`          창 · 그리기 · 글자(src/tk.zig). 게스트(x86_64) 대상이다.
//!   `tars-tk-demo`     TK-M0의 시험 앱(plan 확정 5). initrd의 /usr/bin에 실린다.
//!   `zig build test`   호스트 검사(tk_test — 메모리 판으로 둥근 사각형 · 글자 표).
//!
//! terminal에서 빌려 오는 것(경로로): stb 헤더와 구현 C 파일, Wayland xml 다섯(`terminal/vendor/wayland` · `terminal/protocol`).
//! 그 vendor는 prepare.sh가 이 build를 부르기 전에 받아 둔다. shared/의 `theme` · `glyph`는 terminal과 같은 파일이다(결정 2).

const std = @import("std");
const Translator = @import("translate_c").Translator;
const Scanner = @import("wayland").Scanner;

pub fn build(b: *std.Build) void {
    // 대상과 최적화 모드는 terminal과 같다(plan 확정 2) — 게이트가 부팅하는 것이 곧 제품이다(terminal/build.zig의 GL-M3 주석).
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .gnu,
        .cpu_model = .baseline,
    });
    const optimize = b.standardOptimizeOption(.{});
    const guest_optimize = b.option(
        std.lang.Optimize,
        "guest-optimize",
        "게스트로 가는 툴킷 바이너리의 최적화 모드 (기본 ReleaseSafe)",
    ) orelse .safe;
    const host_target = b.resolveTargetQuery(.{});

    const terminal_vendor = b.path("../terminal/vendor");
    const stb_impl = b.path("../terminal/src/stb_truetype_impl.c");

    // ── shared/ ────────────────────────────────────────────────────
    const theme = b.createModule(.{ .root_source_file = b.path("../shared/theme.zig") });

    const c_stb = translateC(b, "c_stb_truetype", "#include <stb_truetype.h>\n", target, guest_optimize);
    c_stb.addIncludePath(terminal_vendor);
    const glyph = b.createModule(.{
        .root_source_file = b.path("../shared/glyph.zig"),
        .target = target,
        .optimize = guest_optimize,
    });
    glyph.addImport("c_stb_truetype", c_stb.mod);

    const c_stb_host = translateC(b, "c_stb_truetype", "#include <stb_truetype.h>\n", host_target, optimize);
    c_stb_host.addIncludePath(terminal_vendor);
    const glyph_host = b.createModule(.{
        .root_source_file = b.path("../shared/glyph.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    glyph_host.addImport("c_stb_truetype", c_stb_host.mod);

    // ── z2d(design 결정 3, v0.13.2) ──────────────────────────────────
    const z2d = b.dependency("z2d", .{ .target = target, .optimize = guest_optimize }).module("z2d");
    const z2d_host = b.dependency("z2d", .{ .target = host_target, .optimize = optimize }).module("z2d");

    // ── Wayland 클라이언트 바인딩 ──────────────────────────────────────
    // terminal의 서버와 같은 xml · 같은 판이다(terminal/build.zig의 `scanner`). 스캐너는 server · client를 함께 만들고 우리는 client만 쓴다.
    const scanner = Scanner.create(b, .{
        .wayland_xml = b.path("../terminal/vendor/wayland/wayland.xml"),
        .wayland_protocols = b.path("../terminal/vendor/wayland"),
    });
    scanner.addCustomProtocol(b.path("../terminal/vendor/wayland/xdg-shell.xml"));
    scanner.addCustomProtocol(b.path("../terminal/protocol/tars-menu-v1.xml"));
    scanner.generate("wl_compositor", 6);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 7);
    scanner.generate("xdg_wm_base", 5);
    scanner.generate("tars_menu_manager_v1", 1);
    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    // libwayland-client는 컨테이너의 x86_64 sysroot에 있다(terminal/build.zig의 같은 줄 — WY design 확인 1).
    const amd64_sysroot = b.graph.environ_map.get("AMD64_SYSROOT") orelse "/usr/local/amd64-sysroot";
    const amd64_libdir: std.Build.LazyPath = .{ .cwd_relative = b.pathJoin(&.{ amd64_sysroot, "usr/lib/x86_64-linux-gnu" }) };

    // ── 모듈 tk ──────────────────────────────────────────────────────
    const tk = b.addModule("tk", .{
        .root_source_file = b.path("src/tk.zig"),
        .target = target,
        .optimize = guest_optimize,
        .link_libc = true,
    });
    tk.addImport("theme", theme);
    tk.addImport("glyph", glyph);
    tk.addImport("z2d", z2d);
    tk.addImport("wayland", wayland);
    tk.addIncludePath(terminal_vendor);
    tk.addCSourceFile(.{ .file = stb_impl, .flags = &.{} });
    tk.linkSystemLibrary("m", .{});
    tk.addLibraryPath(amd64_libdir);
    tk.linkSystemLibrary("wayland-client", .{ .use_pkg_config = .no });

    // ── tars-tk-demo ─────────────────────────────────────────────────
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("src/demo.zig"),
        .target = target,
        .optimize = guest_optimize,
        .link_libc = true,
    });
    demo_mod.addImport("tk", tk);
    b.installArtifact(b.addExecutable(.{ .name = "tars-tk-demo", .root_module = demo_mod }));

    // ── 호스트 검사 ─────────────────────────────────────────────────────
    // 창 층(Wayland)은 빼고 그리기 · 글자만 — 판은 메모리 배열이다(R-ARCH-4).
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tk_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("theme", theme);
    test_mod.addImport("glyph", glyph_host);
    test_mod.addImport("z2d", z2d_host);
    test_mod.addIncludePath(terminal_vendor);
    test_mod.addCSourceFile(.{ .file = stb_impl, .flags = &.{} });
    test_mod.linkSystemLibrary("m", .{});
    const tk_test = b.addExecutable(.{ .name = "tk_test", .root_module = test_mod });
    b.installArtifact(tk_test);
    const run_test = b.addRunArtifact(tk_test);
    run_test.setCwd(b.path("."));
    b.step("test", "호스트 검사(tk_test)").dependOn(&run_test.step);
}

/// C 헤더 번역(terminal/build.zig의 같은 이름 함수와 같다 — ZU-M1).
fn translateC(
    b: *std.Build,
    name: []const u8,
    header: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
) Translator {
    return .init(b.dependency("translate_c", .{}), .{
        .name = name,
        .c_source_file = b.addWriteFiles().add(b.fmt("{s}.h", .{name}), header),
        .target = target,
        .optimize = optimize,
    });
}
