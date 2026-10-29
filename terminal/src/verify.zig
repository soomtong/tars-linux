//! verify 모드의 비교(DR-M1, design 결정 7). 실제 fb와 그림자 fb의 픽셀을 행마다 대조해
//! 다른 격자 행을 센다. 순수하다 — fb도 libc도 로그도 모른다. 줄을 찍는 것은 `main.zig`의
//! `render`다. DR-M2의 행 비교(design 결정 9 — 지난 셀 목록과 이번 셀 목록에서 dirty 행을
//! 내는 함수)도 이 파일에 들어온다.
const std = @import("std");

/// 보고에 담는 격자 행의 최대 수. 잔상이 어디서 났는지 보는 데는 앞 몇 행이면 되고,
/// 화면 전체가 다르면 `rows`가 그것을 말한다.
pub const MAX_FIRST = 8;

/// 픽셀 행 `y`를 격자 행으로 묶는 산수. `top` 위의 여백은 0번 행에, 격자 아래(상태 줄이
/// 있는 여백)는 `rows`번에 붙인다 — 여백 자체는 행이 아니지만 어느 이웃에 가까운지는 말해 준다.
pub const Grid = struct {
    top: u32,
    row_height: u32,
    rows: u16,

    pub fn rowOf(self: Grid, y: u32) u16 {
        if (y < self.top) return 0;
        const row = (y - self.top) / self.row_height;
        return if (row >= self.rows) self.rows else @intCast(row);
    }
};

pub const Report = struct {
    /// 다른 격자 행의 수. 격자 아래는 한 행(`rows`번)으로 센다.
    rows: u16 = 0,
    /// 그 가운데 앞 `MAX_FIRST`개, 위에서 아래 순.
    first: [MAX_FIRST]u16 = @splat(0),

    pub fn ok(self: Report) bool {
        return self.rows == 0;
    }

    pub fn listed(self: *const Report) []const u16 {
        return self.first[0..@min(self.rows, MAX_FIRST)];
    }
};

/// 픽셀 행마다 `width_bytes`만 본다 — pitch의 패딩은 우리가 쓴 적 없는 바이트라 양쪽 값이
/// 달라도 뜻이 없다. 다른 픽셀 행은 `grid.rowOf`로 격자 행이 되고, 한 격자 행의 픽셀 행
/// 열여섯이 다 달라도 한 행이다.
pub fn compare(a: [*]const u8, b: [*]const u8, width_bytes: usize, pitch: usize, height: u32, grid: Grid) Report {
    var r: Report = .{};
    var last: ?u16 = null;
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        const off = @as(usize, y) * pitch;
        if (std.mem.eql(u8, a[off..][0..width_bytes], b[off..][0..width_bytes])) continue;
        const row = grid.rowOf(y);
        if (last == row) continue;
        last = row;
        if (r.rows < MAX_FIRST) r.first[r.rows] = row;
        r.rows += 1;
    }
    return r;
}
