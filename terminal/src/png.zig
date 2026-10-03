//! kitty `f=100`(PNG)을 푸는 디코더(TG design 결정 6).
//!
//! 라이브러리는 PNG 디코더를 함수 포인터 하나(`sys.decode_png`)로 비워 두고,
//! lib 빌드에서는 null이라 PNG를 `EINVAL`로 거절한다(TG 실측 3). 이 파일이 그
//! 자리를 `stb_image`로 채운다. 넣는 것은 `vt.Screen.init`이다.
//!
//! 헤더를 번역하지 않고 쓰는 함수 셋만 선언한다. 번역하면 glibc 헤더까지
//! 따라 읽고, fortify가 켜진 번역이 통하는지를 헤더마다 따로 재야 한다
//! (`docs/decisions/project_zig_c_uapi_rule.md`, ZU-M1에서 poll.h는 안 통했다). 구현은 `stb_image_impl.c`가
//! PNG만 켜서 컴파일한다.

const std = @import("std");
const sys = @import("ghostty-vt").sys;

extern "c" fn stbi_info_from_memory(buffer: [*]const u8, len: c_int, x: *c_int, y: *c_int, comp: *c_int) c_int;
extern "c" fn stbi_load_from_memory(buffer: [*]const u8, len: c_int, x: *c_int, y: *c_int, comp: *c_int, req_comp: c_int) ?[*]u8;
extern "c" fn stbi_image_free(retval_from_stbi_load: ?*anyopaque) void;

/// 풀린 RGBA가 이것을 넘으면 풀기 전에 거절한다(TG-M3 plan 정한 것 2).
///
/// `stb_image`는 라이브러리의 제한된 할당자를 안 거치고 `malloc`으로 푼다.
/// 라이브러리의 상한(한 변 10000 · 400MB)은 데스크톱 기준이라, 그대로 두면
/// 작은 PNG 하나가 RAM 위 게스트에 수백 MB를 요구할 수 있다. 값은 저장
/// 한도(lib 기본 10MB, design 결정 5)와 같다 — 그보다 큰 한 장은 어차피
/// 저장소에 못 들어간다.
pub const MAX_BYTES: u64 = 10 * 1000 * 1000;

/// `sys.DecodePngFn`의 모양이다. 결과는 받은 `alloc`으로 만든다 —
/// 라이브러리가 같은 할당자로 해제한다(`sys.zig`의 계약).
pub fn decode(alloc: std.mem.Allocator, data: []const u8) sys.DecodeError!sys.Image {
    if (data.len > std.math.maxInt(c_int)) return error.InvalidData;
    const len: c_int = @intCast(data.len);

    // 머리(IHDR)만 읽는다. 여기서는 아무것도 할당하지 않는다.
    var w: c_int = 0;
    var h: c_int = 0;
    var comp: c_int = 0;
    if (stbi_info_from_memory(data.ptr, len, &w, &h, &comp) == 0) return error.InvalidData;
    if (w <= 0 or h <= 0) return error.InvalidData;
    if (@as(u64, @intCast(w)) * @as(u64, @intCast(h)) * 4 > MAX_BYTES) return error.InvalidData;

    // 채널은 4로 고정한다. 라이브러리는 PNG 결과를 rgba로 적으므로
    // (`graphics_image.zig:584`) 회색 PNG도 여기서 RGBA로 펴야 한다.
    const px = stbi_load_from_memory(data.ptr, len, &w, &h, &comp, 4) orelse return error.InvalidData;
    defer stbi_image_free(px);

    const n = @as(usize, @intCast(w)) * @as(usize, @intCast(h)) * 4;
    const out = try alloc.alloc(u8, n);
    @memcpy(out, px[0..n]);
    return .{ .width = @intCast(w), .height = @intCast(h), .data = out };
}
