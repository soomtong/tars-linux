//! kitty 이미지 하나를 픽셀 대상에 그린다(TG design 결정 4).
//!
//! 순수 모듈이다. 대상은 `anytype` — `getPixel(x, y) u32`와
//! `setPixel(x, y, color)`가 있는 것 — 이라 게스트에서는 `drm.Framebuffer`가,
//! 호스트 검사(`image_test.zig`)에서는 `u32` 배열이 들어온다. 최근접 이웃 ·
//! 자르기 · 알파 합성은 틀리기 쉬운 산수인데, 부팅 게이트로만 보면 한 번
//! 확인에 수 분이 걸린다. 그래서 산수를 여기 모으고 호스트에서 본다.
//!
//! 색은 프레임버퍼 형식 `0x00RRGGBB`다.

const vt = @import("vt.zig");

/// 그려도 되는 사각형. `x1` · `y1`은 포함하지 않는다.
///
/// `main.zig`가 격자로 정한다 — 여백과 상태 줄에는 이미지를 안 그린다.
/// `drm.Framebuffer.setPixel`에 범위 검사가 없으므로(`drm.zig:149`) 이
/// 사각형이 곧 게스트를 프레임버퍼 밖 쓰기에서 지키는 자리다.
pub const Clip = struct { x0: i32, y0: i32, x1: i32, y1: i32 };

/// `src`를 알파 `a`(0~255)로 `dst` 위에 얹는다. 채널마다
/// `(s × a + d × (255 − a) + 127) / 255` — 127은 반올림이다.
pub fn blend(src: u32, dst: u32, a: u32) u32 {
    var out: u32 = 0;
    var shift: u5 = 0;
    while (shift <= 16) : (shift += 8) {
        const s = (src >> shift) & 0xFF;
        const d = (dst >> shift) & 0xFF;
        out |= ((s * a + d * (255 - a) + 127) / 255) << shift;
    }
    return out;
}

/// placement 하나를 그린다. `origin`은 격자 왼쪽 위의 대상 좌표다 —
/// `p.dst_x` · `p.dst_y`는 격자 기준이고 음수일 수 있다(TG 실측 4).
///
/// 목적지 픽셀 `(dx, dy)`(사각형 안의 상대 좌표)는 원본
/// `(src_x + dx × src_w / dst_w, src_y + dy × src_h / dst_h)`를 가져온다.
/// 정수 나눗셈이라 확대 배율이 정수면 경계가 정확히 떨어지고, 게이트가
/// "이 픽셀은 이 색"으로 판정할 수 있다. 쌍선형을 안 쓰는 이유는 design
/// 결정 4에 있다.
///
/// 자르기를 원본 좌표가 아니라 목적지 루프의 범위로 한다. 잘린 부분의
/// 원본 좌표는 위 식이 정하므로, 사각형을 미리 잘라 원본을 다시 셈하지
/// 않아도 남은 픽셀이 잘리기 전과 같은 원본을 가져온다.
pub fn draw(target: anytype, p: vt.ImagePlacement, origin_x: i32, origin_y: i32, clip: Clip) void {
    if (p.src_w == 0 or p.src_h == 0 or p.dst_w == 0 or p.dst_h == 0) return;
    const bpp: u64 = switch (p.format) {
        .rgb => 3,
        .rgba => 4,
    };

    const left: i64 = @as(i64, origin_x) + p.dst_x;
    const top: i64 = @as(i64, origin_y) + p.dst_y;
    const x_start = @max(left, clip.x0);
    const x_end = @min(left + p.dst_w, clip.x1);
    const y_start = @max(top, clip.y0);
    const y_end = @min(top + p.dst_h, clip.y1);
    if (x_start >= x_end or y_start >= y_end) return;

    var y = y_start;
    while (y < y_end) : (y += 1) {
        const dy: u64 = @intCast(y - top);
        const sy = p.src_y + dy * p.src_h / p.dst_h;
        var x = x_start;
        while (x < x_end) : (x += 1) {
            const dx: u64 = @intCast(x - left);
            const sx = p.src_x + dx * p.src_w / p.dst_w;
            const i = (sy * p.width + sx) * bpp;
            // 라이브러리가 data 길이를 width × height × bpp로 맞춰 두지만,
            // 틀리면 여기가 남의 메모리를 읽는다. 한 번 더 막는다.
            if (i + bpp > p.data.len) continue;

            const rgb = @as(u32, p.data[i]) << 16 | @as(u32, p.data[i + 1]) << 8 | p.data[i + 2];
            const a: u32 = if (bpp == 4) p.data[i + 3] else 255;
            if (a == 0) continue;

            const tx: u32 = @intCast(x);
            const ty: u32 = @intCast(y);
            target.setPixel(tx, ty, if (a == 255) rgb else blend(rgb, target.getPixel(tx, ty) & 0x00FFFFFF, a));
        }
    }
}
