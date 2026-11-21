//! TARS 툴킷의 빌드(TK design 결정 1). terminal의 build와 따로 선다 — "툴킷은 라이브러리"(R-ARCH-3)의 경계를 terminal에 묶지
//! 않으려는 것이다. 부르는 자리는 `terminal/prepare.sh` 끝 한 줄이라 체인들의 BUILD_STEPS는 그대로다.
//!
//! 나오는 것
//!   모듈 `tk`          층들을 잇는 뿌리(src/tk.zig). 게스트(x86_64) 대상이다. 그 아래 층마다 모듈 하나(R-ARCH-1, TK-M1):
//!                      `tk_geom`(사각형, 층 밖) · `tk_window`(창, src/window/) · `tk_cg`(판 · 렌더 백엔드 · 글자, src/cg/) ·
//!                      `tk_ca`(레이어 트리, src/ca/) · `tk_kit`(AppKit — 뷰 · responder, src/kit/, TK-M2)과 층 밖의 순수 값
//!                      `tk_input`(입력 이벤트, src/input.zig) · `tk_menu`(메뉴 모델, src/menu.zig — TK-M6). kit은 창 층을 모른다. 아래 층이 위 층을 부를 import 이름을 여기서 주지 않고, 경로로 부르면
//!                      그 파일이 두 모듈에 들어 컴파일이 막는다("file exists in modules 'tk_ca' and 'tk_cg'" — 실측) — 층 경계를
//!                      컴파일이 지킨다.
//!   `tars-tk-demo`     TK-M0의 시험 앱(plan 확정 5). initrd의 /usr/bin에 실린다.
//!   `tars-files`       첫 앱(TK-M3, src/files/). initrd의 /usr/bin에 실린다.
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
    const image_impl = b.path("src/cg/stb_image_impl.c");

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
    // 텍스트 입력 · 클립보드(TK-M4) — 서버와 같은 판(terminal/build.zig).
    scanner.addCustomProtocol(b.path("../terminal/vendor/wayland/text-input-unstable-v3.xml"));
    scanner.generate("wl_compositor", 6);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 7);
    scanner.generate("xdg_wm_base", 5);
    scanner.generate("tars_menu_manager_v1", 2);
    scanner.generate("zwp_text_input_manager_v3", 1);
    scanner.generate("wl_data_device_manager", 2);
    const wayland = b.createModule(.{ .root_source_file = scanner.result });

    // libwayland-client는 컨테이너의 x86_64 sysroot에 있다(terminal/build.zig의 같은 줄 — WY design 확인 1).
    const amd64_sysroot = b.graph.environ_map.get("AMD64_SYSROOT") orelse "/usr/local/amd64-sysroot";
    const amd64_libdir: std.Build.LazyPath = .{ .cwd_relative = b.pathJoin(&.{ amd64_sysroot, "usr/lib/x86_64-linux-gnu" }) };

    // ── 층 모듈(R-ARCH-1) ──────────────────────────────────────────────
    const layers = layerModules(b, target, guest_optimize, theme, glyph, z2d);
    const tk_window = b.createModule(.{
        .root_source_file = b.path("src/window/window.zig"),
        .target = target,
        .optimize = guest_optimize,
        .link_libc = true,
    });
    tk_window.addImport("tk_geom", layers.geom);
    tk_window.addImport("tk_input", layers.input);
    tk_window.addImport("tk_menu", layers.menu);
    tk_window.addImport("wayland", wayland);

    // ── 모듈 tk ──────────────────────────────────────────────────────
    const tk = b.addModule("tk", .{
        .root_source_file = b.path("src/tk.zig"),
        .target = target,
        .optimize = guest_optimize,
        .link_libc = true,
    });
    tk.addImport("theme", theme);
    tk.addImport("tk_geom", layers.geom);
    tk.addImport("tk_window", tk_window);
    tk.addImport("tk_cg", layers.cg);
    tk.addImport("tk_ca", layers.ca);
    tk.addImport("tk_input", layers.input);
    tk.addImport("tk_menu", layers.menu);
    tk.addImport("tk_kit", layers.kit);
    tk.addImport("tk_tokens", layers.tokens);
    tk.addIncludePath(terminal_vendor);
    tk.addCSourceFile(.{ .file = stb_impl, .flags = &.{} });
    // 이미지 디코더(TK-M6 plan 확정 10) — 헤더는 terminal의 vendor, 구현은 툴킷의 것(PNG · JPEG).
    tk.addCSourceFile(.{ .file = image_impl, .flags = &.{} });
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

    // ── tars-files(TK-M3, design 결정 14) ─────────────────────────────
    // 첫 앱. `tk` 모듈만 import한다(경계는 import가 지킨다). 순수 모델 `src/files/model.zig`는 호스트 검사도 부른다.
    const files_mod = b.createModule(.{
        .root_source_file = b.path("src/files/main.zig"),
        .target = target,
        .optimize = guest_optimize,
        .link_libc = true,
    });
    files_mod.addImport("tk", tk);
    // 메뉴 모델 `src/files/menus.zig`(TK-M6)는 `tk` 아래의 순수 모듈 둘을 직접 부른다 — 호스트 검사가 같은 파일을 부르게(같은 모듈이라 `tk.menu`와 같은 타입).
    files_mod.addImport("tk_menu", layers.menu);
    files_mod.addImport("tk_input", layers.input);
    b.installArtifact(b.addExecutable(.{ .name = "tars-files", .root_module = files_mod }));

    // ── 호스트 검사 ─────────────────────────────────────────────────────
    // 창 층의 Wayland 부분은 빼고 CG · CA · kit과 창 층의 순수 부분(버퍼 나이 `window/age.zig` · 키 반복 `window/repeat.zig`) — 판은
    // 메모리 배열이다(R-ARCH-4).
    const host_layers = layerModules(b, host_target, optimize, theme, glyph_host, z2d_host);
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tk_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("theme", theme);
    test_mod.addImport("tk_geom", host_layers.geom);
    test_mod.addImport("tk_cg", host_layers.cg);
    test_mod.addImport("tk_ca", host_layers.ca);
    test_mod.addImport("tk_input", host_layers.input);
    test_mod.addImport("tk_menu", host_layers.menu);
    test_mod.addImport("tk_kit", host_layers.kit);
    test_mod.addImport("tk_tokens", host_layers.tokens);
    // `tars-files`의 순수한 것 — 검색(`search.zig`)이 모델(`model.zig`)을 경로로 부르므로 한 모듈이다(`files_search.model`, TK-M4 단계 C).
    const files_menus = b.createModule(.{ .root_source_file = b.path("src/files/menus.zig"), .target = host_target, .optimize = optimize });
    files_menus.addImport("tk_menu", host_layers.menu);
    files_menus.addImport("tk_input", host_layers.input);
    test_mod.addImport("files_menus", files_menus);
    // 미리보기의 판정(TK-M6 단계 B) — 순수 함수와 작은 읽기 하나.
    test_mod.addImport("files_preview", b.createModule(.{ .root_source_file = b.path("src/files/preview.zig"), .target = host_target, .optimize = optimize }));
    test_mod.addImport("files_search", b.createModule(.{ .root_source_file = b.path("src/files/search.zig"), .target = host_target, .optimize = optimize }));
    // 서버 키맵(TK-M4 — 글자 키 표 `tk_input.charFor`를 이 파일과 대조한다, design 결정 13 · 15). 서버와 같은 파일이다(terminal/build.zig).
    test_mod.addAnonymousImport("keymap", .{ .root_source_file = b.path("../terminal/vendor/keymap-us.xkb") });
    test_mod.addIncludePath(terminal_vendor);
    test_mod.addCSourceFile(.{ .file = stb_impl, .flags = &.{} });
    test_mod.addCSourceFile(.{ .file = image_impl, .flags = &.{} });
    test_mod.linkSystemLibrary("m", .{});
    const tk_test = b.addExecutable(.{ .name = "tk_test", .root_module = test_mod });
    b.installArtifact(tk_test);
    const run_test = b.addRunArtifact(tk_test);
    run_test.setCwd(b.path("."));
    b.step("test", "호스트 검사(tk_test)").dependOn(&run_test.step);
}

/// 대상 하나의 `tk_geom` · `tk_input` · `tk_cg` · `tk_ca` · `tk_kit`(게스트와 호스트 검사가 같은 모양으로 받는다). kit은 CA · CG · 층 밖 값을,
/// CA는 CG를, CG는 z2d · glyph를 안다.
fn layerModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    theme: *std.Build.Module,
    glyph: *std.Build.Module,
    z2d: *std.Build.Module,
) struct { geom: *std.Build.Module, input: *std.Build.Module, menu: *std.Build.Module, cg: *std.Build.Module, ca: *std.Build.Module, kit: *std.Build.Module, tokens: *std.Build.Module } {
    const geom = b.createModule(.{ .root_source_file = b.path("src/geom.zig"), .target = target, .optimize = optimize });
    const input = b.createModule(.{ .root_source_file = b.path("src/input.zig"), .target = target, .optimize = optimize });
    // 메뉴 모델(TK-M6 plan 확정 1) — 층 밖의 순수 값. 창 층이 직렬화하고 kit이 맞춘다.
    const menu = b.createModule(.{ .root_source_file = b.path("src/menu.zig"), .target = target, .optimize = optimize });
    menu.addImport("tk_input", input);
    const cg = b.createModule(.{ .root_source_file = b.path("src/cg/cg.zig"), .target = target, .optimize = optimize });
    cg.addImport("tk_geom", geom);
    cg.addImport("glyph", glyph);
    cg.addImport("z2d", z2d);
    const ca = b.createModule(.{ .root_source_file = b.path("src/ca/ca.zig"), .target = target, .optimize = optimize });
    ca.addImport("tk_geom", geom);
    ca.addImport("tk_cg", cg);
    // 테마 토큰(R-CA-5) — 앱과 위젯이 함께 부른다. 순수 상수라 층 밖이다.
    const tokens = b.createModule(.{ .root_source_file = b.path("src/tokens.zig"), .target = target, .optimize = optimize });
    tokens.addImport("theme", theme);
    const kit = b.createModule(.{ .root_source_file = b.path("src/kit/kit.zig"), .target = target, .optimize = optimize });
    kit.addImport("tk_tokens", tokens);
    kit.addImport("tk_geom", geom);
    kit.addImport("tk_input", input);
    kit.addImport("tk_menu", menu);
    kit.addImport("tk_cg", cg);
    kit.addImport("tk_ca", ca);
    return .{ .geom = geom, .input = input, .menu = menu, .cg = cg, .ca = ca, .kit = kit, .tokens = tokens };
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
