//! 이미지 디코더와 축소(TK-M6 plan 확정 10 · 15, R-CG-3 · R-FM-5 · R-FM-7). 믿을 수 없는 입력의 자리다 — 그래서 모양을 셋으로 묶는다.
//!
//! 1. 파일을 열지 않는다. 부르는 쪽이 읽은 바이트만 받는 순수 함수(`decode`)다. 이 함수 경계가 곧 격리의 자리라, 나중에 디코더를 별도
//!    프로세스로 옮겨도(바이트를 파이프로 넣고 작은 판을 받는다) 부르는 쪽은 안 바뀐다(R-FM-7 — 원칙만, 구현은 뒤로).
//! 2. 크기는 머리로 먼저 본다(`stbi_info_from_memory` — 할당 없음). 상한 셋(입력 16 MiB · 한 변 8192 — 요구사항 결정 13, 넓이 × 4 ≤ 64 MiB —
//!    plan 확정 10)을 넘으면 풀지 않는다(`error.TooBig`). 머리를 못 읽으면 `error.Invalid`.
//! 3. 푼 결과는 곧장 작은 판으로 줄이고(`fitInto` — 박스 평균, 확대 없음) 원본은 놓는다 — 미리보기는 작은 판 하나만 든다.
//!
//! 디코더는 stb_image(PNG · JPEG만 — `stb_image_impl.c`)이고 헤더는 번역하지 않고 쓰는 함수 셋만 선언한다(terminal `png.zig`와 같은 까닭 —
//! `docs/decisions/project_zig_c_uapi_rule.md`). 결과는 RGBA 8비트(16비트 PNG · 회색 · 팔레트 · CMYK JPEG도 stb가 RGBA로 편다)이고 이 모듈이
//! premultiplied ARGB(`0xAARRGGBB`, z2d · wl_shm과 같은 배치)로 바꾼다.

const std = @import("std");

extern "c" fn stbi_info_from_memory(buffer: [*]const u8, len: c_int, x: *c_int, y: *c_int, comp: *c_int) c_int;
extern "c" fn stbi_load_from_memory(buffer: [*]const u8, len: c_int, x: *c_int, y: *c_int, comp: *c_int, req_comp: c_int) ?[*]u8;
extern "c" fn stbi_image_free(retval_from_stbi_load: ?*anyopaque) void;

/// 입력 상한(요구사항 결정 13).
pub const MAX_INPUT: usize = 16 * 1024 * 1024;
/// 한 변 상한(요구사항 결정 13).
pub const MAX_SIDE: u32 = 8192;
/// 푼 RGBA의 상한(plan 확정 10 — 8192² × 4 = 256 MiB는 RAM 위 게스트에 무리다).
pub const MAX_DECODED: u64 = 64 * 1024 * 1024;

pub const Error = error{ Invalid, TooBig, OutOfMemory };

pub const Format = enum { png, jpeg };

/// 바이트 머리로 형식을 가른다(확장자가 아니라 — plan 확정 12).
pub fn sniff(bytes: []const u8) ?Format {
    if (bytes.len >= 8 and std.mem.eql(u8, bytes[0..8], "\x89PNG\r\n\x1a\n")) return .png;
    if (bytes.len >= 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF) return .jpeg;
    return null;
}

pub const Info = struct { w: u32, h: u32 };

/// 머리만 읽어 크기를 본다(할당 없음). 상한 셋을 넘으면 `TooBig`.
pub fn info(bytes: []const u8) Error!Info {
    if (bytes.len > MAX_INPUT) return error.TooBig;
    if (bytes.len == 0) return error.Invalid;
    // PNG는 IHDR의 크기를 먼저 직접 본다 — stb의 머리 읽기는 tRNS를 찾느라 IHDR 뒤 chunk까지 지나서, 크기를 거짓으로 적은 머리가 "깨짐"으로만
    // 끝나 "너무 큼"과 갈리지 않는다.
    if (sniff(bytes) == .png and bytes.len >= 24 and std.mem.eql(u8, bytes[12..16], "IHDR")) {
        try checkSize(std.mem.readInt(u32, bytes[16..20], .big), std.mem.readInt(u32, bytes[20..24], .big));
    }
    var w: c_int = 0;
    var h: c_int = 0;
    var comp: c_int = 0;
    if (stbi_info_from_memory(bytes.ptr, @intCast(bytes.len), &w, &h, &comp) == 0) return error.Invalid;
    if (w <= 0 or h <= 0) return error.Invalid;
    const uw: u32 = @intCast(w);
    const uh: u32 = @intCast(h);
    try checkSize(uw, uh);
    return .{ .w = uw, .h = uh };
}

/// 상한 둘(한 변 · 넓이).
fn checkSize(w: u32, h: u32) Error!void {
    if (w > MAX_SIDE or h > MAX_SIDE) return error.TooBig;
    if (@as(u64, w) * h * 4 > MAX_DECODED) return error.TooBig;
}

/// premultiplied ARGB 판. `pixels`는 받은 allocator의 것.
pub const Image = struct {
    w: u32,
    h: u32,
    pixels: []u32,

    pub fn deinit(self: *Image, alloc: std.mem.Allocator) void {
        alloc.free(self.pixels);
        self.* = undefined;
    }

    pub fn view(self: *const Image) View {
        return .{ .w = self.w, .h = self.h, .pixels = self.pixels };
    }
};

/// 그리기에 넘기는 판(빌린 것).
pub const View = struct {
    w: u32,
    h: u32,
    pixels: []const u32,
};

/// RGBA 8비트 한 픽셀 → premultiplied ARGB.
pub fn premul(r: u8, g: u8, b: u8, a: u8) u32 {
    const aa: u32 = a;
    const pr = (@as(u32, r) * aa + 127) / 255;
    const pg = (@as(u32, g) * aa + 127) / 255;
    const pb = (@as(u32, b) * aa + 127) / 255;
    return (aa << 24) | (pr << 16) | (pg << 8) | pb;
}

/// 바이트를 원본 크기의 premultiplied ARGB 판으로 푼다(머리로 상한을 먼저 본다).
pub fn decode(alloc: std.mem.Allocator, bytes: []const u8) Error!Image {
    const hd = try info(bytes);
    var w: c_int = 0;
    var h: c_int = 0;
    var comp: c_int = 0;
    const px = stbi_load_from_memory(bytes.ptr, @intCast(bytes.len), &w, &h, &comp, 4) orelse return error.Invalid;
    defer stbi_image_free(px);
    // 머리와 본문이 다른 크기를 말하면 믿지 않는다.
    if (w <= 0 or h <= 0 or @as(u32, @intCast(w)) != hd.w or @as(u32, @intCast(h)) != hd.h) return error.Invalid;
    const n = @as(usize, hd.w) * hd.h;
    const out = try alloc.alloc(u32, n);
    for (out, 0..) |*o, i| o.* = premul(px[i * 4], px[i * 4 + 1], px[i * 4 + 2], px[i * 4 + 3]);
    return .{ .w = hd.w, .h = hd.h, .pixels = out };
}

/// (w, h)를 (max_w, max_h) 안에 비율을 지켜 맞춘 크기 — 이미 들어가면 그대로(확대하지 않는다, plan 확정 10). 0이 되지 않는다.
pub fn fit(w: u32, h: u32, max_w: u32, max_h: u32) Info {
    if (w <= max_w and h <= max_h) return .{ .w = w, .h = h };
    // 가로가 먼저 닿는가: w / max_w ≥ h / max_h.
    if (@as(u64, w) * max_h >= @as(u64, h) * max_w) {
        return .{ .w = max_w, .h = @max(1, @as(u32, @intCast(@as(u64, h) * max_w / w))) };
    }
    return .{ .w = @max(1, @as(u32, @intCast(@as(u64, w) * max_h / h))), .h = max_h };
}

/// 박스(넓이 평균) 축소: `src`(sw × sh)를 `dst`(dw × dh, dw ≤ sw · dh ≤ sh)로. 대상 픽셀마다 그것이 덮는 원본 칸(정수 경계 — 바닥 · 천장)의
/// 평균. premultiplied라 채널별 평균이 곧 맞는 합성이다. 같은 크기면 복사.
pub fn boxScale(src: []const u32, sw: u32, sh: u32, dst: []u32, dw: u32, dh: u32) void {
    var dy: u32 = 0;
    while (dy < dh) : (dy += 1) {
        const y0: u32 = @intCast(@as(u64, dy) * sh / dh);
        const y1: u32 = @max(y0 + 1, @as(u32, @intCast((@as(u64, dy) + 1) * sh / dh)));
        var dx: u32 = 0;
        while (dx < dw) : (dx += 1) {
            const x0: u32 = @intCast(@as(u64, dx) * sw / dw);
            const x1: u32 = @max(x0 + 1, @as(u32, @intCast((@as(u64, dx) + 1) * sw / dw)));
            var sa: u64 = 0;
            var sr: u64 = 0;
            var sg: u64 = 0;
            var sb: u64 = 0;
            var y = y0;
            while (y < y1) : (y += 1) {
                for (src[@as(usize, y) * sw + x0 .. @as(usize, y) * sw + x1]) |p| {
                    sa += p >> 24;
                    sr += (p >> 16) & 0xFF;
                    sg += (p >> 8) & 0xFF;
                    sb += p & 0xFF;
                }
            }
            const cnt: u64 = @as(u64, x1 - x0) * (y1 - y0);
            const a: u32 = @intCast((sa + cnt / 2) / cnt);
            const r: u32 = @intCast((sr + cnt / 2) / cnt);
            const g: u32 = @intCast((sg + cnt / 2) / cnt);
            const b: u32 = @intCast((sb + cnt / 2) / cnt);
            dst[@as(usize, dy) * dw + dx] = (a << 24) | (r << 16) | (g << 8) | b;
        }
    }
}

/// 정수배 확대(가장 가까운 이웃) — 배율 2의 화면에서 1:1 논리 크기를 물리 판으로(미리보기가 부른다).
pub fn nearestScale(src: []const u32, sw: u32, sh: u32, dst: []u32, k: u32) void {
    const dw = sw * k;
    var y: u32 = 0;
    while (y < sh * k) : (y += 1) {
        var x: u32 = 0;
        while (x < dw) : (x += 1) dst[@as(usize, y) * dw + x] = src[@as(usize, y / k) * sw + x / k];
    }
}

/// 디코드 + 맞춤(plan 확정 10): `bytes`를 풀어 (max_w, max_h) 안에 맞춘 판 하나를 돌려주고 원본은 놓는다. `k`는 화면 배율 — 원본이 논리
/// 크기로 들어가면 k배 최근접(물리 1:1 = 논리 1:1), 아니면 물리 상자에 박스 축소. 돌려주는 판은 물리 픽셀이다.
pub fn decodeFit(alloc: std.mem.Allocator, bytes: []const u8, max_w: u32, max_h: u32, k: u32) Error!Image {
    var full = try decode(alloc, bytes);
    defer full.deinit(alloc);
    if (full.w <= max_w and full.h <= max_h) {
        const out = try alloc.alloc(u32, @as(usize, full.w) * k * full.h * k);
        nearestScale(full.pixels, full.w, full.h, out, k);
        return .{ .w = full.w * k, .h = full.h * k, .pixels = out };
    }
    const f = fit(full.w, full.h, max_w * k, max_h * k);
    const out = try alloc.alloc(u32, @as(usize, f.w) * f.h);
    boxScale(full.pixels, full.w, full.h, out, f.w, f.h);
    return .{ .w = f.w, .h = f.h, .pixels = out };
}
