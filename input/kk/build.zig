const std = @import("std");

// KK-M0: 게이트 전용 Apple 대역 키보드. 제품 initrd에는 안 들어간다 — input 체인이
// 빌드해 1차 부팅의 설정 디스크에 싣는다(KK design 결정 7).
//
// 타깃 · 모드 · libc 없음은 pointer/replay/build.zig(tp-replay)와 같다. 게스트는
// 언제나 x86_64이고, libc를 링크하지 않으면 정적 바이너리라 디스크에 .so를 함께
// 실을 일이 없다.
pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .musl,
        .cpu_model = .baseline,
    });
    const mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .single_threaded = true,
    });
    const exe = b.addExecutable(.{
        .name = "kk-apple",
        .root_module = mod,
    });
    b.installArtifact(exe);
}
