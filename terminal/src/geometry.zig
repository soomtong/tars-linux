//! 격자의 자리 셈(FU-M0). 순수 산수라 호스트에서 검사한다(`geometry_test.zig`) — `scale.zig`와 같은 모양이다.
//!
//! 여백이 있으면 격자 둘레에 `MARGIN`px를 두고, 전체 화면이면 여백 없이 화면을 셀로 나눈다(FU design 결정 1).
//! 나누어떨어지지 않고 남는 픽셀은 둘레에 반씩 — 격자를 가운데 둔다. 여백이 있을 때는 지금까지의 셈 그대로다:
//! 원점 (20, 20), 남는 픽셀은 오른쪽 · 아래 여백에 붙는다(상태 줄이 아래 여백에 산다).

pub const CELL_W: u32 = 8;
pub const ROW_HEIGHT: u32 = 16;
pub const MARGIN: u32 = 20;

pub const Grid = struct {
    /// 격자 왼쪽 위의 픽셀.
    x: u32,
    y: u32,
    cols: u16,
    rows: u16,
};

/// `w × h`(논리 fb — 배율이 1보다 크면 늘리기 전의 크기, HS design 결정 1) 위의 격자.
pub fn grid(w: u32, h: u32, fullscreen: bool) Grid {
    if (fullscreen) {
        const cols = w / CELL_W;
        const rows = h / ROW_HEIGHT;
        return .{
            .x = (w - cols * CELL_W) / 2,
            .y = (h - rows * ROW_HEIGHT) / 2,
            .cols = @intCast(cols),
            .rows = @intCast(rows),
        };
    }
    return .{
        .x = MARGIN,
        .y = MARGIN,
        .cols = @intCast((w - 2 * MARGIN) / CELL_W),
        .rows = @intCast((h - 2 * MARGIN) / ROW_HEIGHT),
    };
}

pub const Rect = struct { x: u32, y: u32, w: u32, h: u32 };

/// 사각형을 `fw × fh` 안으로 자른다. 다 밖이면 null.
///
/// `drm.Framebuffer.fillRect`가 부른다(FU-M0). 마지막 열의 폭 2 preedit은 커서 사각형과 조합 글자를 격자
/// 오른쪽으로 반 칸 내민다 — 여백이 있으면 그 반 칸이 여백에 떨어지지만, 전체 화면에서 오른쪽 여백이 0이면
/// 다음 픽셀 줄을 덮거나 맨 아래 줄에서 버퍼 밖에 쓴다. 글리프는 `drawGlyph`가 이미 자른다.
pub fn clip(r: Rect, fw: u32, fh: u32) ?Rect {
    if (r.x >= fw or r.y >= fh or r.w == 0 or r.h == 0) return null;
    return .{ .x = r.x, .y = r.y, .w = @min(r.w, fw - r.x), .h = @min(r.h, fh - r.y) };
}
