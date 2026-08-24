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
    /// copy mode의 커서. null이면 copy mode가 아니다.
    ///
    /// **뷰포트 좌표다**(0이 화면 맨 윗줄). 절대 행이 아닌 이유는 이동이
    /// 화면 위의 일이기 때문이다 — 뷰포트가 한 줄 올라가면 커서는 화면의
    /// 같은 자리에 남고, 그래서 가리키는 내용이 한 줄 위가 된다. 그것이
    /// 화면 끝에서 계속 움직였을 때 사람이 기대하는 동작이다.
    ///
    /// 앵커(선택의 시작점)는 여기 두지 않는다. CM-M1이 라이브러리의 tracked
    /// selection에 맡긴다(design 결정 5).
    copy_cursor: ?Cursor = null,

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
                // 스크롤백 한도(design 결정 10). **두 값을 함께 줘야 한다.**
                //
                // 결정 10은 max_scrollback_lines만 말했는데, 그것만 주면
                // 아무것도 바뀌지 않는다 — 기본 max_scrollback_bytes(10,000)가
                // 먼저 걸려서 155x47 격자에서 history가 454줄에 멈춘다
                // (2026-08-23 실측). 효력 있는 한도는 `max(준 값, 활성 영역을
                // 담을 최소값)`이라(PageList.Limits.max) 10,000바이트는 처음부터
                // 무시되고 있었다.
                //
                // 바이트가 아니라 줄로 세는 이유는 그것이 사람이 생각하는
                // 단위이고, 게이트가 "N줄 찍고 올라가서 첫 줄을 본다"로
                // 검사하기 쉽기 때문이다. 실제로 남는 history는 754~1000줄을
                // 오간다 — 가지치기가 페이지 통째로 일어나기 때문이고,
                // 1.15MB라 128MB 게스트가 감당한다.
                .max_scrollback_bytes = null,
                .max_scrollback_lines = 1000,
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
                //
                // **copy mode 중에는 셸 커서를 그리지 않는다**(CM-M0). 반전된
                // 셀이 둘이면 게이트가 어느 것이 copy 커서인지 못 가른다.
                if (self.copy_cursor) |cc| {
                    if (@as(usize, cc.x) == x and @as(usize, cc.y) == y) {
                        std.mem.swap(u32, &fg, &bg);
                    }
                } else if (cursor) |vp| {
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

    /// 뷰포트 좌표 한 쌍. 로그와 검사가 함께 쓴다.
    pub const Cursor = struct { x: u16, y: u16 };

    /// copy mode에 들어간다. 커서는 셸 커서 자리에서 시작한다.
    ///
    /// 셸 커서가 뷰포트 밖에 있으면(스크롤백을 올려다보는 중이면) 화면 맨
    /// 왼쪽 위에서 시작한다 — 안 보이는 자리에 커서를 두면 사람이 무엇을
    /// 움직이는지 알 수 없다.
    pub fn copyEnter(self: *Screen) void {
        self.copy_cursor = if (self.state.cursor.viewport) |vp|
            .{ .x = vp.x, .y = vp.y }
        else
            .{ .x = 0, .y = 0 };
    }

    /// copy mode를 나간다.
    pub fn copyExit(self: *Screen) void {
        self.copy_cursor = null;
    }

    pub fn copyActive(self: *const Screen) bool {
        return self.copy_cursor != null;
    }

    pub fn copyCursor(self: *const Screen) ?Cursor {
        return self.copy_cursor;
    }

    /// 커서를 옮긴다. **화면 끝을 넘으면 뷰포트가 대신 움직인다.**
    ///
    /// 좌우는 화면 안에서 멈춘다(줄을 넘나들지 않는다). 위아래는 화면 끝에서
    /// 뷰포트를 한 줄 밀고 커서는 그 끝에 남는다 — 스크롤백을 거슬러 올라가며
    /// 훑는 동작이 이것으로 만들어진다.
    ///
    /// `cells()`보다 먼저 불려도 안전하다. `state.rows`·`cols`는 init에서
    /// 준 격자 크기이고 매 프레임 같은 값이다.
    pub fn copyMove(self: *Screen, dx: i32, dy: i32) void {
        const cur = self.copy_cursor orelse return;
        if (self.state.cols == 0 or self.state.rows == 0) return;

        const max_x: i32 = @as(i32, self.state.cols) - 1;
        const max_y: i32 = @as(i32, self.state.rows) - 1;

        var x: i32 = @as(i32, cur.x) + dx;
        if (x < 0) x = 0;
        if (x > max_x) x = max_x;

        var y: i32 = @as(i32, cur.y) + dy;
        if (y < 0) {
            self.scrollByRows(-1);
            y = 0;
        } else if (y > max_y) {
            self.scrollByRows(1);
            y = max_y;
        }

        self.copy_cursor = .{ .x = @intCast(x), .y = @intCast(y) };
    }

    /// 뷰포트가 스크롤백의 어디에 있는지.
    ///
    /// `total`은 스크롤 가능한 전체 행 수, `offset`은 뷰포트 맨 윗줄이 그중
    /// 몇 번째인가, `len`은 언제나 `rows`다. **"바닥에 있다"는
    /// `offset == total - len`이다.**
    ///
    /// 라이브러리 타입을 그대로 흘려보내지 않고 우리 struct로 옮겨 담는
    /// 이유는 TR-M0이 색에 대해 한 것과 같다(design 결정 1) — `main.zig`가
    /// `ghostty-vt`의 타입을 배우지 않게 한다.
    pub const Scrollbar = struct {
        total: usize,
        offset: usize,
        len: usize,
    };

    pub fn scrollbar(self: *Screen) Scrollbar {
        const sb = self.term.screens.active.pages.scrollbar();
        return .{ .total = sb.total, .offset = sb.offset, .len = sb.len };
    }

    /// 스크롤백의 맨 위로.
    pub fn scrollToTop(self: *Screen) void {
        self.term.scrollViewport(.top);
    }

    /// 활성 영역의 맨 위로 = 평소 상태로.
    ///
    /// **PTY 출력이 도착할 때마다 불러야 한다**(design 결정 13). 라이브러리는
    /// 그 일을 해 주지 않는다 — 올라간 상태에서 출력을 먹여도 뷰포트가
    /// 그대로라는 것을 2026-08-23에 실측했고, `vt_test`가 그 사실을 못 박고
    /// 있다.
    pub fn scrollToBottom(self: *Screen) void {
        self.term.scrollViewport(.bottom);
    }

    /// 상대 이동. **위가 음수다.**
    ///
    /// 몇 줄이 한 화면인지는 여기서 정하지 않는다. 격자 크기를 아는 것은
    /// `main.zig`이고, 그쪽이 `rows`를 넘겨준다.
    pub fn scrollByRows(self: *Screen, delta: isize) void {
        self.term.scrollViewport(.{ .delta = delta });
    }
};
