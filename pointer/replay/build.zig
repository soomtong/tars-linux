const std = @import("std");

// PD-M3: 게이트 전용 되감기 도구. 제품 initrd에는 안 들어간다 — pointer 체인이
// 빌드해 부팅 B의 설정 디스크에 싣는다(PD design 결정 10).
//
// 타깃 · 모드 · libc 없음은 init/build.zig와 같다. 게스트는 언제나 x86_64이고,
// libc를 링크하지 않으면 정적 바이너리라 디스크에 .so를 함께 실을 일이 없다.
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
        .name = "tp-replay",
        .root_module = mod,
    });
    b.installArtifact(exe);
}
