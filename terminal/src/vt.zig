const std = @import("std");
const ghostty_vt = @import("ghostty-vt");

pub const CellGlyph = struct {
    codepoint: u32,
    col: u16,
    row: u16,
};

/// 터미널 상태를 **계속 들고 있는** 화면.
///
/// TF-M2의 `parseToCells`는 호출할 때마다 Terminal을 새로 만들고 버렸다.
/// 입력이 생기면 PTY 출력이 여러 조각으로 나눠 도착하므로, 조각마다 새
/// Terminal을 만들면 앞 내용이 사라질 뿐 아니라 이스케이프 시퀀스가 조각
/// 경계에서 잘렸을 때 파서 상태도 잃는다. 그래서 Terminal과 Stream을
/// 프로그램 수명 내내 유지한다.
///
/// **반드시 힙에 두고 포인터로 다뤄야 한다.** `Terminal.vtStream()`이
/// 돌려주는 Stream은 내부에 `&terminal` 포인터를 담고 있어서
/// (`Terminal.zig:374-377`), Screen 값이 복사·이동되면 그 포인터가 옛 주소를
/// 가리키게 된다. `init`이 `*Screen`을 돌려주는 이유가 이것이다.
pub const Screen = struct {
    alloc: std.mem.Allocator,
    term: ghostty_vt.Terminal,
    /// `ghostty_vt.Stream`이 아니다 — 그쪽은 핸들러 타입을 받는 제네릭
    /// 함수(`stream.Stream(Handler)`)라서 필드 타입으로 못 쓴다.
    /// Terminal용으로 인스턴스화된 것이 `TerminalStream`이며
    /// (`stream_terminal.zig:26`), `Terminal.vtStream()`의 반환 타입이
    /// 정확히 이것이다(`Terminal.zig:30`).
    stream: ghostty_vt.TerminalStream,
    state: ghostty_vt.RenderState,

    pub fn init(
        io: std.Io,
        alloc: std.mem.Allocator,
        cols: u16,
        rows: u16,
    ) !*Screen {
        const self = try alloc.create(Screen);
        self.* = .{
            .alloc = alloc,
            .term = try .init(io, alloc, .{ .cols = cols, .rows = rows }),
            .stream = undefined,
            .state = .empty,
        };
        // term이 최종 주소에 자리잡은 **뒤에** stream을 만든다.
        self.stream = self.term.vtStream();
        return self;
    }

    pub fn deinit(self: *Screen) void {
        const alloc = self.alloc;
        self.state.deinit(alloc);
        self.stream.deinit();
        self.term.deinit(alloc);
        alloc.destroy(self);
    }

    /// PTY에서 읽은 바이트를 ANSI 파서에 먹인다. 화면 상태가 갱신된다.
    pub fn feed(self: *Screen, bytes: []const u8) void {
        self.stream.nextSlice(bytes);
    }

    /// 현재 화면에서 빈 칸이 아닌 셀만 out에 채워 반환한다.
    /// out은 최소 cols*rows 크기여야 안전하다.
    pub fn cells(self: *Screen, out: []CellGlyph) ![]CellGlyph {
        try self.state.update(self.alloc, &self.term);

        var n: usize = 0;
        const row_data = self.state.row_data.slice();
        const row_cells = row_data.items(.cells);
        for (0..self.state.rows) |y| {
            const cells_slice = row_cells[y].slice();
            const raws = cells_slice.items(.raw);
            for (0..self.state.cols) |x| {
                if (n >= out.len) return out[0..n];
                const cp = raws[x].codepoint();
                if (cp == 0) continue;
                out[n] = .{
                    .codepoint = @intCast(cp),
                    .col = @intCast(x),
                    .row = @intCast(y),
                };
                n += 1;
            }
        }
        return out[0..n];
    }
};
