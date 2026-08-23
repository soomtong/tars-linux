const std = @import("std");
const ghostty_vt = @import("ghostty-vt");

/// 렌더러에게 넘기는 셀 하나.
///
/// `fg`·`bg`는 프레임버퍼와 같은 `0x00RRGGBB` 형식으로 **이미 해소된** 값이다.
/// `Style`을 그대로 흘려보내지 않는 이유가 design 결정 1이다 — 색을 푸는 데
/// 필요한 것(팔레트, 기본 fg/bg, bold 옵션)이 전부 여기 `RenderState`에 있고,
/// 렌더러는 팔레트도 SGR도 몰라야 한다. inverse와 커서도 여기서 두 색을
/// 맞바꿔 해소하므로 `main.zig`는 "반전"이라는 개념 자체를 배우지 않는다.
pub const CellGlyph = struct {
    codepoint: u32,
    col: u16,
    row: u16,
    fg: u32,
    bg: u32,
};

/// `color.RGB`를 프레임버퍼의 XRGB8888 한 워드로 만든다.
fn packRgb(c: ghostty_vt.color.RGB) u32 {
    return (@as(u32, c.r) << 16) | (@as(u32, c.g) << 8) | c.b;
}

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
            // 기본 색을 여기서 준다(design 결정 5). 값은 main.zig가 쓰던
            // 상수와 같게 유지한다 — 이번 변경이 화면의 색을 바꾸는 일이 되면
            // 게이트의 회귀와 우리 변경을 가르기 어려워진다.
            //
            // `.init`은 "OSC로 덮어쓸 수 있는 기본값"이라는 뜻이다
            // (`color.zig:337`). 그래서 셸이 OSC 10/11로 배경·전경을 바꾸는
            // 것이 저절로 동작한다. `.unset`이면 라이브러리 기본값
            // (fg=#FFFFFF, bg=#000000)이 나온다.
            .term = try .init(io, alloc, .{
                .cols = cols,
                .rows = rows,
                .colors = .{
                    .background = .init(.{ .r = 0x10, .g = 0x20, .b = 0x30 }),
                    .foreground = .init(.{ .r = 0xFF, .g = 0xFF, .b = 0xFF }),
                    .cursor = .unset,
                    .palette = .default,
                },
            }),
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

    /// 그릴 것이 있는 셀을 out에 채워 반환한다. out은 최소 cols*rows
    /// 크기여야 안전하다.
    ///
    /// **글자가 없어도 색이 있으면 내보낸다**(design 결정 3). 배경색이
    /// 생긴 뒤로는 빈 셀도 그릴 것이 있기 때문이다 — `ls` 출력의 색 띠,
    /// 커서 자리, 그리고 나중의 선택 영역이 그렇다.
    pub fn cells(self: *Screen, out: []CellGlyph) ![]CellGlyph {
        // update()는 beginUpdate() + endUpdate()다(`render.zig:326`).
        // 셀별 style은 endUpdate에서 채워지므로 이 호출 뒤에 읽어도 된다.
        try self.state.update(self.alloc, &self.term);

        const colors = &self.state.colors;
        const default_fg = packRgb(colors.foreground);
        const default_bg = packRgb(colors.background);
        const cursor = self.state.cursor.viewport;

        var n: usize = 0;
        const row_data = self.state.row_data.slice();
        const row_cells = row_data.items(.cells);
        for (0..self.state.rows) |y| {
            const cells_slice = row_cells[y].slice();
            const raws = cells_slice.items(.raw);
            const styles = cells_slice.items(.style);
            for (0..self.state.cols) |x| {
                if (n >= out.len) return out[0..n];

                const raw = raws[x];
                const cp = raw.codepoint();

                var fg = default_fg;
                var bg = default_bg;

                // style_id가 기본값(0, `style.zig:17`의 default_id)일 때
                // style을 읽으면 쓰레기다. 라이브러리가 계약으로 명시한
                // 자리다(`render.zig:260-262`).
                if (raw.style_id != 0) {
                    const st = styles[x];
                    fg = packRgb(st.fg(.{
                        .default = colors.foreground,
                        .palette = &colors.palette,
                        // bold를 밝은 색으로 바꾸는 일을 라이브러리가 대신
                        // 해 준다(`style.zig:172-181`). 폰트가 하나뿐이라
                        // 굵은 자체가 없는 우리에게는 이것이 유일한 길이다.
                        .bold = .bright,
                    }));
                    // null이 "기본 배경"이라는 뜻이다(`style.zig:120`).
                    if (st.bg(&raw, &colors.palette)) |b| bg = packRgb(b);
                    // inverse는 아무도 처리해 주지 않는다 — fg()도 bg()도
                    // 이 플래그를 안 본다.
                    if (st.flags.inverse) std.mem.swap(u32, &fg, &bg);
                }

                // 커서는 inverse와 **같은 연산**이다(design 결정 2). 그래서
                // 렌더러는 커서라는 것도 배우지 않는다. 뷰포트 밖으로
                // 나가면 viewport가 null이므로 TR-M2가 이 자리를 다시
                // 손대지 않아도 된다.
                if (cursor) |vp| {
                    if (@as(usize, vp.x) == x and @as(usize, vp.y) == y) {
                        std.mem.swap(u32, &fg, &bg);
                    }
                }

                // 그릴 글자도 없고 칠할 색도 기본인 셀만 건너뛴다.
                if (cp == 0 and bg == default_bg) continue;

                out[n] = .{
                    .codepoint = @intCast(cp),
                    .col = @intCast(x),
                    .row = @intCast(y),
                    .fg = fg,
                    .bg = bg,
                };
                n += 1;
            }
        }
        return out[0..n];
    }

    /// 기본 전경/배경을 프레임버퍼 형식으로 돌려준다.
    ///
    /// `main.zig`가 같은 상수를 다시 적지 않게 하려고 여기서 내보낸다.
    /// 로그 문구가 두 곳에 중복되어 어긋난 사고가 이 저장소에 이미 있었고
    /// (`HANDOFF.md`), 색 상수도 같은 함정이다 — `init`이 Terminal에 넣은
    /// 값을 `RenderState`가 되돌려준 것이므로 이쪽이 언제나 실제로 쓰이는
    /// 값이다.
    ///
    /// **`cells()` 뒤에 부를 것.** `state.colors`는 `update()`가 채운다.
    pub fn defaultFg(self: *const Screen) u32 {
        return packRgb(self.state.colors.foreground);
    }

    pub fn defaultBg(self: *const Screen) u32 {
        return packRgb(self.state.colors.background);
    }
};
