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
    /// 앵커(선택의 시작점)는 여기 두지 않는다. 라이브러리의 tracked
    /// selection이 든다(design 결정 5) — 뷰포트가 움직여도 저절로 따라간다.
    copy_cursor: ?Cursor = null,

    /// 지금 무엇을 잡고 있는가. null이면 커서만 움직이는 중이다.
    copy_kind: ?SelectKind = null,

    /// 앵커의 **screen 좌표 y**. 가지치기 감시용이다(CM-M1).
    ///
    /// 이 값이 왜 필요한지가 이 milestone에서 가장 미묘한 자리다.
    /// `main.zig`가 copy mode 중에 `scrollToBottom()`을 억제하므로, 뷰포트가
    /// history에 머무는 동안 가지치기가 일어날 수 있다(design 위험 1).
    /// **그때 라이브러리는 선택을 null로 만들지 않는다** — tracked pin을
    /// 살아 있는 이웃 페이지의 왼쪽 위로 옮긴다
    /// (`PageList.erasePage`, `PageList.eraseRows`). 선택은 멀쩡히 존재하고
    /// 가리키는 내용만 달라진다. 그래서 "selection이 null인가"로는 절대 못
    /// 잡고, 조용히 엉뚱한 자리를 복사하게 된다.
    ///
    /// screen 좌표는 목록 맨 위에서부터 세는 절대 좌표라 **아래에 줄이 붙는
    /// 것으로는 안 변한다.** 변하는 경우가 앞에서 줄이 지워졌을 때와 pin이
    /// 옮겨졌을 때뿐이고, 그 둘이 정확히 우리가 잡고 싶은 것이다.
    copy_anchor_y: ?u32 = null,

    /// 가지치기 때문에 모드가 끊겼다는 것을 `main.zig`가 한 번 가져간다.
    copy_pruned: bool = false,

    /// 클립보드. `y`가 만든 문자열을 **소유한다.**
    ///
    /// 프로세스 하나가 디스플레이를 독점하는 구조(TF design 결정 1)에서는
    /// 버퍼 하나로 충분하다(`project_copy_mode`). 다음 `y`가 옛것을 해제한다.
    clip: ?[:0]const u8 = null,

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
        if (self.clip) |text| alloc.free(text);
        self.state.deinit(alloc);
        self.stream.deinit();
        self.term.deinit(alloc);
        alloc.destroy(self);
    }

    /// PTY에서 읽은 바이트를 ANSI 파서에 먹인다. 화면 상태가 갱신된다.
    ///
    /// **먹인 뒤에 앵커가 제자리에 있는지 본다**(CM-M1, design 위험 1).
    /// 어긋났으면 모드를 통째로 닫는다 — 조용히 엉뚱한 자리를 복사하는 것보다
    /// 낫고, 사람은 다시 `Cmd+Shift+C`를 누르면 된다.
    ///
    /// 대체 화면(vim 등)으로 갈아타서 `selection`이 사라지는 경우도 같은
    /// 조건에 걸린다. 그때 나가는 것도 옳다.
    ///
    /// 선택 중이 아니면(`copy_anchor_y`가 null이면) 아무 일도 안 한다.
    /// 커서만 있는 상태에서는 잘못 복사될 것이 없기 때문이다.
    pub fn feed(self: *Screen, bytes: []const u8) void {
        self.stream.nextSlice(bytes);

        const want = self.copy_anchor_y orelse return;
        const now = anchorY(self.term.screens.active);
        if (now != null and now.? == want) return;

        self.copyExit();
        self.copy_pruned = true;
    }

    /// 지금 선택의 앵커가 screen 좌표로 몇 번째 행에 있는가.
    ///
    /// 선택이 없으면 null이다. `pointFromPin`은 라이브러리가 스스로 "느리다"고
    /// 적어 둔 함수라(`Selection.zig`의 NOTE) 셀마다 부르면 안 되지만, 여기는
    /// **선택이 있을 때 PTY 출력 한 조각에 한 번**이라 문제가 되지 않는다.
    fn anchorY(s: *ghostty_vt.Screen) ?u32 {
        const sel = s.selection orelse return null;
        const pt = s.pages.pointFromPin(.screen, sel.start()) orelse return null;
        return pt.screen.y;
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
        // 그 행에서 선택된 x 범위. **라이브러리가 채워 준다**
        // (`render.zig`가 `sel.topLeft()`/`bottomRight()`로 계산한다). 절대 행
        // 번호를 우리가 세지 않는 이유가 이것이다(design 결정 6).
        const row_sels = row_data.items(.selection);
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

                // 선택 영역도 inverse·커서와 **같은 연산**이다(design 결정 6).
                // 그래서 렌더러는 "선택"이라는 말을 배우지 않는다. 양 끝을
                // 포함하는 범위다(`render.zig`가 `start.x <= end.x`를 단언한
                // 뒤 그대로 담는다).
                if (row_sels[y]) |range| {
                    if (x >= @as(usize, range[0]) and x <= @as(usize, range[1])) {
                        std.mem.swap(u32, &fg, &bg);
                    }
                }

                // 커서는 inverse와 **같은 연산**이다(design 결정 2). 그래서
                // 렌더러는 커서라는 것도 배우지 않는다. 뷰포트 밖으로
                // 나가면 viewport가 null이므로 TR-M2가 이 자리를 다시
                // 손대지 않아도 된다.
                //
                // **copy mode 중에는 셸 커서를 그리지 않는다**(CM-M0). 반전된
                // 셀이 둘이면 게이트가 어느 것이 copy 커서인지 못 가른다.
                //
                // 커서가 선택 안에 있으면 위에서 한 번, 여기서 또 한 번
                // 맞바뀌어 **원래 색으로 돌아온다**(CM-M1). 예외를 두지 않는다 —
                // 반전된 띠 가운데 뚫린 구멍이 곧 커서라 오히려 잘 보이고,
                // 예외를 넣으면 "선택"이 렌더 쪽으로 새어 나간다.
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

    /// copy mode를 나간다. **선택도 함께 지운다** — 안 지우면 모드를 나간 뒤에도
    /// 반전된 띠가 화면에 남는다.
    pub fn copyExit(self: *Screen) void {
        self.copy_cursor = null;
        self.copy_kind = null;
        self.copy_anchor_y = null;
        self.term.screens.active.clearSelection();
    }

    /// 가지치기로 모드가 끊겼다는 사실을 **한 번만** 돌려준다.
    /// `main.zig`가 로그 한 줄을 찍는 데 쓴다.
    pub fn copyTakePruned(self: *Screen) bool {
        defer self.copy_pruned = false;
        return self.copy_pruned;
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
    /// **격자 크기를 `state`가 아니라 `pages`에서 읽는다**(CM-M1에서 고쳤다).
    /// `state`는 마지막 `cells()`가 찍은 스냅숏이라, 한 번도 그리지 않은
    /// 화면에서는 `cols`·`rows`가 0이고 그러면 이 함수가 **조용히 아무 일도
    /// 안 한다.** CM-M0의 주석은 "cells()보다 먼저 불려도 안전하다"고 적었는데,
    /// 크래시가 안 난다는 뜻으로는 맞지만 동작한다는 뜻으로는 틀렸다 —
    /// 실전에서 안 드러난 이유는 main.zig가 키를 받기 전에 이미 한 프레임을
    /// 그렸기 때문이다. `pages`는 언제나 살아 있는 값이다.
    pub fn copyMove(self: *Screen, dx: i32, dy: i32) !void {
        const cur = self.copy_cursor orelse return;
        const pages = &self.term.screens.active.pages;
        if (pages.cols == 0 or pages.rows == 0) return;

        const max_x: i32 = @as(i32, pages.cols) - 1;
        const max_y: i32 = @as(i32, pages.rows) - 1;

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

        // 선택 중이면 커서를 따라 넓힌다. 앵커는 우리가 안 들고 있고
        // **지금 선택의 start가 곧 앵커다**(design 결정 5). 줄 선택일 때 그
        // start는 앵커 줄 위의 어느 pin이므로, selectLine이 같은 줄을 다시
        // 돌려준다.
        if (self.copy_kind == null) return;
        const sel = self.term.screens.active.selection orelse return;
        const cursor = self.copyPin() orelse return;
        try self.copyApply(sel.start(), cursor);
    }

    /// 단어 경계로 치는 코드포인트.
    ///
    /// **값은 ghostty 자신의 검사가 쓰는 기본값과 같다**(`Screen.zig:9800`).
    /// 라이브러리는 이 목록을 설정에서 받도록 되어 있는데
    /// (`Surface.zig:1217`의 `selection_word_chars`) 우리에게는 설정이 없으므로
    /// 상수로 둔다. `/config/tars.conf`로 뺄 수 있는 자리이지만 바꾸고 싶어 한
    /// 사람이 없다 — 필요해지면 그때 뺀다.
    const WORD_BOUNDARY = [_]u21{
        0,   ' ', '\t', '\'', '"',
        '│',
        '`', '|', ':',  ';',  ',',
        '(', ')', '[',  ']',  '{',
        '}', '<', '>',  '$',
    };

    /// 단어 이동의 방향. `w`가 next, `b`가 prev다.
    pub const WordDir = enum { next, prev };

    /// 그 자리에 글자가 쓰였는가. **한 번도 안 쓰인 셀과 공백은 다르다** —
    /// `"alpha"` 뒤의 공백은 쓰인 셀이고, 줄 끝의 남은 칸은 아니다.
    /// `selectWord`가 후자에서 null을 주므로(plan 확정 사실 3) 우리도 그
    /// 경계를 같은 기준으로 본다.
    fn written(pin: ghostty_vt.Pin) bool {
        return pin.rowAndCell().cell.hasText();
    }

    /// 그 자리가 단어 경계인가. **쓰이지 않은 셀도 경계로 친다.**
    fn boundaryAt(pin: ghostty_vt.Pin) bool {
        const cell = pin.rowAndCell().cell;
        if (!cell.hasText()) return true;
        return std.mem.indexOfScalar(
            u21,
            &WORD_BOUNDARY,
            cell.content.codepoint.data,
        ) != null;
    }

    /// 두 pin이 같은 자리인가. `Pin`은 `{ node, y, x }`라 셋을 본다.
    fn samePin(a: ghostty_vt.Pin, b: ghostty_vt.Pin) bool {
        return a.node == b.node and a.y == b.y and a.x == b.x;
    }

    /// `w`/`b`. **커서를 단어 단위로 옮긴다.**
    ///
    /// **라이브러리가 세는 "단어"와 vim의 `w`는 다르다**(design 결정 3).
    /// `selectWord`는 공백 덩어리도 한 단어로 세므로(`"ABC  DEF"`가 셋),
    /// 공백에 내려앉으면 한 번 더 건너뛰는 일을 우리가 한다. **경계 판정이라는
    /// 어려운 부분은 끝까지 라이브러리에 남는다** — 우리가 정하는 것은 "어느
    /// 방향으로 몇 번 부르는가"뿐이다.
    ///
    /// 쓰이지 않은 자리에 닿으면 **움직이지 않는다**(CN-M0 plan 결정 1).
    /// vim은 다음 줄의 첫 단어로 가지만, 줄 사이 이동은 `j`/`k`가 이미 한다.
    pub fn copyMoveWord(self: *Screen, dir: WordDir) !void {
        if (self.copy_cursor == null) return;
        const s = self.term.screens.active;
        const from = self.copyPin() orelse return;

        const target = switch (dir) {
            .next => wordNext(s, from),
            .prev => wordPrev(s, from),
        } orelse return;

        self.copyPlace(target);

        // 선택 중이면 커서를 따라 넓힌다. **`copyMove`와 같은 문을 통과한다**
        // (design 결정 11) — 이동 수단마다 선택 갱신을 따로 짜면 그중 하나만
        // 어긋나도 "어떤 키로 움직였느냐에 따라 복사되는 글자가 다르다"가 된다.
        if (self.copy_kind == null) return;
        const sel = s.selection orelse return;
        const cursor = self.copyPin() orelse return;
        try self.copyApply(sel.start(), cursor);
    }

    /// 다음 단어의 첫 글자. 갈 곳이 없으면 null.
    ///
    /// **두 번까지만 건너뛴다.** 지금 단어에서 한 번, 그것이 공백 덩어리면 한
    /// 번 더다. 세 번째는 있을 수 없다 — 경계 문자들이 연달아 오면 라이브러리가
    /// 그것을 **한 덩어리로** 묶기 때문이다(`expect_boundary` 로직).
    fn wordNext(s: *ghostty_vt.Screen, from: ghostty_vt.Pin) ?ghostty_vt.Pin {
        var pin = from;
        var hop: u8 = 0;
        while (hop < 2) : (hop += 1) {
            const word = s.selectWord(pin, &WORD_BOUNDARY) orelse return null;
            pin = word.end().rightWrap(1) orelse return null;
            if (!written(pin)) return null;
            if (!boundaryAt(pin)) return pin;
        }
        return pin;
    }

    /// 이전 단어의 첫 글자. 갈 곳이 없으면 null.
    ///
    /// **커서가 단어 중간이면 그 단어의 시작으로 간다**(vim과 같다,
    /// CN-M0 plan 결정 2). 그러지 않으면 `w`로 간 자리에서 `b`를 눌러도 원래
    /// 자리로 안 돌아온다.
    fn wordPrev(s: *ghostty_vt.Screen, from: ghostty_vt.Pin) ?ghostty_vt.Pin {
        if (s.selectWord(from, &WORD_BOUNDARY)) |word| {
            const st = word.start();
            if (!samePin(st, from)) return st;
        }

        var pin = from.leftWrap(1) orelse return null;
        var hop: u8 = 0;
        while (hop < 2) : (hop += 1) {
            if (!written(pin)) return null;
            const word = s.selectWord(pin, &WORD_BOUNDARY) orelse return null;
            if (!boundaryAt(pin)) return word.start();
            pin = word.start().leftWrap(1) orelse return null;
        }
        return pin;
    }

    /// 목표 pin에 커서를 놓는다. **화면 밖이면 뷰포트를 옮긴다.**
    ///
    /// `pointFromPin(.viewport, …)`이 뷰포트 **위쪽** 밖은 null로 알려주지만
    /// **아래쪽 밖은 알려주지 않는다** — 노드를 계속 따라가며 y를 더해서
    /// `rows`보다 큰 값을 그냥 돌려준다(`PageList.zig:5614`). 그래서 아래쪽은
    /// 우리가 가른다. **이것을 빠뜨리면 커서가 화면 밖 좌표를 갖고, 증상은
    /// 크래시가 아니라 "커서가 안 보인다"가 된다.**
    ///
    /// 뷰포트를 미는 두 경로가 모두 `Screen.scroll`을 통과하는 것에 뜻이 있다.
    /// `pages.scroll`을 직접 부르면 `assertIntegrity`와 kitty dirty 표시를
    /// 건너뛴다(`Screen.zig:1576`). **`Terminal.ScrollViewport`에는 `.pin`이
    /// 없어서**(`Terminal.zig:2504`) 기존 `scrollByRows`로는 위쪽을 못 다룬다.
    fn copyPlace(self: *Screen, pin: ghostty_vt.Pin) void {
        const s = self.term.screens.active;
        const rows: u32 = s.pages.rows;

        if (s.pages.pointFromPin(.viewport, pin)) |pt| {
            const co = pt.coord();
            if (co.y < rows) {
                self.copy_cursor = .{ .x = @intCast(co.x), .y = @intCast(co.y) };
                return;
            }
            // 뷰포트 **아래**다. 최소한만 민다 — 목표가 맨 아랫줄이 된다.
            s.scroll(.{ .delta_row = @intCast(co.y - rows + 1) });
        } else {
            // 뷰포트 **위**다. 목표를 화면 맨 윗줄로 올린다.
            s.scroll(.{ .pin = pin });
        }

        const pt = s.pages.pointFromPin(.viewport, pin) orelse return;
        const co = pt.coord();
        if (co.y >= rows) return;
        self.copy_cursor = .{ .x = @intCast(co.x), .y = @intCast(co.y) };
    }

    /// 선택 방식. `v`가 char, `V`가 line이다.
    pub const SelectKind = enum { char, line };

    /// 지금 커서 자리를 라이브러리의 pin으로 바꾼다.
    ///
    /// 뷰포트 좌표를 그대로 넘길 수 있는 것이 요점이다 — 절대 행 번호를 우리가
    /// 셀 필요가 없다. 뷰포트 밖이거나 폭이 줄어든 페이지면 null이다.
    fn copyPin(self: *Screen) ?ghostty_vt.Pin {
        const cc = self.copy_cursor orelse return null;
        return self.term.screens.active.pages.pin(.{
            .viewport = .{ .x = cc.x, .y = cc.y },
        });
    }

    /// `v`/`V`. **같은 방식을 다시 누르면 푼다.**
    ///
    /// 다른 방식을 누르면 앵커를 지금 커서 자리로 새로 잡는다. vim은 앵커를
    /// 유지하지만, 그러려면 "문자 앵커를 줄 앵커로 승격하는" 자리가 하나 더
    /// 생긴다 — 게이트가 볼 수 없는 표를 늘리는 일이라 지금 하지 않는다.
    pub fn copySelect(self: *Screen, kind: SelectKind) !void {
        if (self.copy_cursor == null) return;
        if (self.copy_kind) |cur| {
            if (cur == kind) {
                self.copy_kind = null;
                self.copy_anchor_y = null;
                self.term.screens.active.clearSelection();
                return;
            }
        }
        self.copy_kind = kind;
        const pin = self.copyPin() orelse return;
        try self.copyApply(pin, pin);
    }

    /// 앵커와 커서로 선택을 다시 만들어 화면에 넘긴다.
    ///
    /// **역방향(앵커보다 커서가 앞)을 우리가 정렬하지 않는다**(design 위험 3의
    /// 답). `selectionString`은 `sel.topLeft()`/`bottomRight()`를 쓰고
    /// (`formatter.zig`), 렌더도 같은 둘을 쓴다(`render.zig`). 그래서
    /// `ordered()`를 부를 자리가 없다.
    fn copyApply(
        self: *Screen,
        anchor: ghostty_vt.Pin,
        cursor: ghostty_vt.Pin,
    ) !void {
        const s = self.term.screens.active;
        const kind = self.copy_kind orelse return;

        const sel: ghostty_vt.Selection = switch (kind) {
            .char => .init(anchor, cursor, false),
            // 줄 선택은 양 끝을 줄 전체로 넓힌다. **줄 끝 공백 트림을 손으로
            // 짜지 않는다** — selectLine이 이미 한다.
            .line => copyLineSel(s, anchor, cursor) orelse .init(anchor, cursor, false),
        };
        try s.select(sel);
        self.copy_anchor_y = anchorY(s);
    }

    /// 앵커 줄과 커서 줄을 합친 선택.
    ///
    /// 어느 쪽이 위인지를 **라이브러리에게 묻는다**. 화면 좌표를 우리가 세면
    /// 스크롤백 위에서 틀린다 — 앵커가 뷰포트 밖에 있을 수 있기 때문이다.
    fn copyLineSel(
        s: *ghostty_vt.Screen,
        anchor: ghostty_vt.Pin,
        cursor: ghostty_vt.Pin,
    ) ?ghostty_vt.Selection {
        const a = s.selectLine(.{ .pin = anchor }) orelse return null;
        const b = s.selectLine(.{ .pin = cursor }) orelse return null;
        const probe: ghostty_vt.Selection = .init(a.start(), b.start(), false);
        return switch (probe.order(s)) {
            // 앵커 줄이 아래에 있다. 위아래를 뒤집어 담는다.
            .reverse => .init(a.end(), b.start(), false),
            else => .init(a.start(), b.end(), false),
        };
    }

    /// `y`. 선택을 클립보드로 옮기고 **모드를 나간다.**
    ///
    /// 돌려주는 슬라이스는 `self.clip`이 소유한다 — 다음 `y`까지만 유효하다.
    /// 선택이 없으면 null을 돌려주고 클립보드는 그대로 둔다(모드는 나간다).
    pub fn copyYank(self: *Screen) !?[]const u8 {
        const s = self.term.screens.active;
        const sel = s.selection orelse {
            self.copyExit();
            return null;
        };
        const text = try s.selectionString(self.alloc, .{ .sel = sel });
        if (self.clip) |old| self.alloc.free(old);
        self.clip = text;
        // copyExit이 선택을 지우므로 **문자열을 먼저 뽑아 둔 뒤에** 부른다.
        self.copyExit();
        return text;
    }

    /// 클립보드의 지금 내용. `y`를 한 번도 안 눌렀으면 null이다.
    ///
    /// `main.zig`가 `self.clip`을 직접 읽지 않게 하려고 함수로 낸다 —
    /// `copyCursor`·`scrollbar`와 같은 규율이다(TR design 결정 1).
    ///
    /// 반환 타입이 `?[]const u8`인 것에 뜻이 있다. `clip`은 실제로
    /// `?[:0]const u8`인데, sentinel을 밖으로 내보내면 호출부가 그것을 직접
    /// free해도 되는 값으로 오해할 여지가 생긴다. **소유권은 `Screen`에 있고
    /// 다음 `y`가 옛것을 해제한다.**
    ///
    /// `return self.clip;` 한 줄로 줄이지 않는다. 그렇게 쓰면 `?[:0]const u8`을
    /// `?[]const u8`로 바꾸는 일을 **optional 껍질을 쓴 채** 요구하게 된다.
    /// 먼저 풀고 나서 돌려주면 sentinel을 떼는 평범한 슬라이스 coercion이 되고,
    /// 그 형태는 바로 위 `copyYank`가 이미 쓰고 있는 것이다.
    pub fn clipboard(self: *const Screen) ?[]const u8 {
        const text = self.clip orelse return null;
        return text;
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
