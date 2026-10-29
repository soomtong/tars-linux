//! 렌더의 순수한 비교 둘. 하나는 verify 모드의 픽셀 비교(DR-M1, design 결정 7) — 실제 fb와
//! 그림자 fb를 행마다 대조해 다른 격자 행을 센다. 다른 하나는 부분 갱신의 행 비교(DR-M2,
//! design 결정 9) — 지난 프레임의 셀 목록과 이번 목록에서 dirty 행을 낸다. 둘 다 fb도 libc도
//! 로그도 모른다. 줄을 찍는 것은 `main.zig`의 `render`다.
//!
//! 셀 타입을 `comptime`으로 받는 이유는 이 파일이 `vt.zig`를 import하지 않기 위해서다 —
//! `vt.zig`는 ghostty를 끌고 오고, `verify_test`는 ghostty 없이 돈다. 무작위 검사(`dirty_test`)가
//! 진짜 `vt.CellGlyph`로 같은 함수를 돌린다.
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

/// 행마다 시작 위치. `starts[r]..starts[r+1]`이 r행의 셀이다(`starts`는 `rows + 1`칸).
/// 목록이 행 오름차순이 아니면 false다 — `cells()`는 행 바깥 · 열 안쪽 순서로 돌므로 늘
/// 오름차순이지만, 그것은 `vt.zig`의 성질이지 이 함수가 아는 계약이 아니다. false면 부르는
/// 쪽이 그 패널을 통째로 그린다(M2 plan 확정 6).
///
/// `rows`를 넘는 행이 있어도 false다. `starts`가 그 행을 가리킬 수 없다.
pub fn rowStarts(comptime Cell: type, cells: []const Cell, starts: []u32) bool {
    const rows = starts.len - 1;
    var row: usize = 0;
    starts[0] = 0;
    for (cells, 0..) |cell, i| {
        const r: usize = cell.row;
        if (r >= rows) return false;
        if (r < row) return false;
        // 비어 있는 행들(row..r)은 이 셀에서 시작하고 끝난다.
        while (row < r) : (row += 1) starts[row + 1] = @intCast(i);
    }
    while (row < rows) : (row += 1) starts[row + 1] = @intCast(cells.len);
    return true;
}

/// 두 목록을 행마다 비교해 다른 행에 `dirty[r] = true`를 쓰고 그 수를 돌려준다. 같은 행은
/// 길이가 같고 바이트가 같은 행이다 — 셀의 모든 필드(글자 · 자리 · 색 둘)가 들어간다.
///
/// 바이트 비교가 패딩을 읽지 않으려면 `Cell`에 패딩이 없어야 한다. 아래 `comptime` 단언이
/// 그것을 본다 — `vt.CellGlyph`는 4 + 2 + 2 + 4 + 4 = 16바이트다. 패딩이 생기면 컴파일이
/// 막히고, 그때는 필드마다 비교하는 판으로 바꾼다.
pub fn dirtyRows(
    comptime Cell: type,
    prev: []const Cell,
    prev_starts: []const u32,
    cur: []const Cell,
    cur_starts: []const u32,
    dirty: []bool,
) u16 {
    comptime {
        var sum: usize = 0;
        for (@typeInfo(Cell).@"struct".field_types) |T| sum += @sizeOf(T);
        if (sum != @sizeOf(Cell)) @compileError("dirtyRows: " ++ @typeName(Cell) ++ " has padding; compare fields instead of bytes");
    }
    var n: u16 = 0;
    for (dirty, 0..) |*d, r| {
        const a = prev[prev_starts[r]..prev_starts[r + 1]];
        const b = cur[cur_starts[r]..cur_starts[r + 1]];
        d.* = !std.mem.eql(u8, std.mem.sliceAsBytes(a), std.mem.sliceAsBytes(b));
        if (d.*) n += 1;
    }
    return n;
}
