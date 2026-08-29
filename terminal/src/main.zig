const std = @import("std");
const drm = @import("drm.zig");
const font = @import("font.zig");
const input = @import("input.zig");
const pty = @import("pty.zig");
const vt = @import("vt.zig");

// fortify를 끄는 이유는 drm.zig의 @cImport 위에 적혀 있다. 이 파일이 걸리는
// 자리는 헤더가 아니라 `c.poll` 호출이다 — fortify가 켜지면 poll이 함수가
// 아니라 매크로가 되고, 그 번역이 c_int 자리에 bool을 놓는다.
const c = @cImport({
    @cDefine("_FORTIFY_SOURCE", "0"); // GL-M3
    @cInclude("poll.h");
});

/// libc의 setenv를 직접 선언한다. 이 파일의 @cImport는 poll.h 하나뿐이고,
/// setenv 하나 때문에 stdlib.h를 통째로 끌어오면 이름 충돌 가능성만 는다.
/// `input.zig`가 open/read를, `pty.zig`가 execv를 이렇게 선언한 것과 같다.
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

// 화면 여백을 칠할 색. 셀의 배경색은 이제 상수가 아니라 vt.zig가 셀마다
// 확정해서 넘긴다(design 결정 1·5) — 이 상수는 격자 **바깥**에만 쓴다.
const MARGIN_COLOR: u32 = 0x00102030;
const GRID_X: u32 = 20;
const GRID_Y: u32 = 20;
const CELL_W: u32 = 8; // unifont의 라틴 advance. 폰트가 준 값과 같아야
                       // 한다 — font.zig의 Glyph.cell_width가 그 값이다.
const ROW_HEIGHT: u32 = 16;

/// 한 셀의 배경을 칠한다. 글리프보다 **먼저** 전부 칠해야 한다
/// (design 결정 6) — 글자가 셀 경계를 넘을 수 있어서, 섞어 그리면 다음
/// 셀의 배경이 앞 글자의 삐져나온 획을 지운다.
fn drawCellBackground(fb: drm.Framebuffer, x: u32, y: u32, color: u32) void {
    var row: u32 = 0;
    while (row < ROW_HEIGHT) : (row += 1) {
        var col: u32 = 0;
        while (col < CELL_W) : (col += 1) {
            fb.setPixel(x + col, y + row, color);
        }
    }
}

/// 알파 블렌딩을 하지 않고 문턱값으로 찍는다(design 결정 4).
///
/// TR-M1에서 이 선택의 근거가 짐작에서 실측으로 바뀌었다. 이 폰트의
/// coverage는 **0 아니면 255뿐이고 그 사이 값이 하나도 없다.** unifont는
/// 16x16 격자를 그대로 담은 비트맵 폰트이고 unitsPerEm이 64라 16px에서
/// scale이 정확히 0.25다 — 안티앨리어싱이 아예 일어나지 않는다. 그래서
/// 게이트의 픽셀 검사가 정확한 상수와 비교할 수 있다.
///
/// **글리프의 오프셋을 반영한다.** stb가 주는 비트맵은 글자를 감싸는 최소
/// 사각형이라, 셀 모서리에 그대로 찍으면 'A'와 'g'의 baseline이 어긋나고
/// 한글이 라틴보다 위로 솟는다. `Glyph`가 들고 있는 두 오프셋은 굽는
/// 자리에서 이미 셀 기준으로 바뀌어 있으므로 여기서는 더하기만 한다.
///
/// **좌표를 부호 있는 수로 계산하고 범위를 검사한다.** `setPixel`이 검사를
/// 하지 않기 때문이다(`drm.zig:128`) — 프레임버퍼 밖에 쓰면 mmap 영역을
/// 넘어 게스트가 죽는다. font_test가 "한글 11172자가 전부 셀 안에 들어간다"를
/// 단언하지만, 그것은 이 폰트에 대한 사실이지 코드의 성질이 아니다.
fn drawGlyph(fb: drm.Framebuffer, glyph: font.Glyph, x: u32, y: u32, color: u32) void {
    const bitmap = glyph.bitmap orelse return;
    const origin_x = @as(i32, @intCast(x)) + glyph.x_offset;
    const origin_y = @as(i32, @intCast(y)) + glyph.y_offset;
    const limit_x = @as(i32, @intCast(fb.width));
    const limit_y = @as(i32, @intCast(fb.height));

    var row: u32 = 0;
    while (row < glyph.height) : (row += 1) {
        const py = origin_y + @as(i32, @intCast(row));
        if (py < 0 or py >= limit_y) continue;
        var col: u32 = 0;
        while (col < glyph.width) : (col += 1) {
            const px = origin_x + @as(i32, @intCast(col));
            if (px < 0 or px >= limit_x) continue;
            const coverage = bitmap[row * glyph.width + col];
            if (coverage > 127) {
                fb.setPixel(@intCast(px), @intCast(py), color);
            }
        }
    }
}

/// 프롬프트 오버레이(design 결정 7). **격자를 다 그린 뒤 마지막 줄만 덮는다.**
///
/// **`render`가 `present()`로 끝나므로 반드시 그 안에서, present 앞에 그려야
/// 한다.** 밖에서 그리면 다음 프레임까지 화면에 안 나온다.
///
/// 줄 전체를 먼저 배경색으로 지운다. 안 지우면 검색어가 짧아졌을 때 지난
/// 프레임의 꼬리가 오른쪽에 남는다 — Backspace를 눌렀는데 글자가 안 지워지는
/// 것처럼 보인다.
///
/// **반전하지 않는다**(CN-M1 plan 결정 6). 선택도 copy 커서도 "색 둘을
/// 맞바꾼다"로 나타나므로, 프롬프트까지 반전하면 화면 맨 아래의 흰 띠가
/// 선택인지 프롬프트인지 갈리지 않는다. 앞의 `/` 한 글자가 그 표시다.
fn drawPrompt(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    text: []const u8,
    rows: u16,
    cols: u16,
    fg: u32,
    bg: u32,
) !void {
    if (rows == 0) return;
    const y = GRID_Y + @as(u32, rows - 1) * ROW_HEIGHT;

    var col: u32 = 0;
    while (col < cols) : (col += 1) {
        drawCellBackground(fb, GRID_X + col * CELL_W, y, bg);
    }

    col = 0;
    for (text) |ch| {
        if (col >= cols) break;
        const glyph = try cache.find(ch);
        drawGlyph(fb, glyph, GRID_X + col * CELL_W, y, fg);
        col += 1;
    }
}

/// 화면 전체를 지우고 셀 목록을 다시 그린다. 키 입력 빈도에서 부분 갱신은
/// 불필요한 복잡도다(YAGNI) — `RenderState`가 dirty를 주지만 쓰지 않는다.
///
/// **두 벌로 나눠 그린다**(design 결정 6). 배경을 전부 칠하고 나서 글리프를
/// 전부 그린다. 섞으면 다음 셀의 배경이 앞 글자의 삐져나온 획을 지운다.
/// `cache`가 `*font.Cache`인 이유는 TR-M1부터 **그리는 도중에 글자를 굽기
/// 때문이다.** 캐시에 없는 글자가 화면에 나타나면 그 자리에서 래스터라이징이
/// 일어난다 — 한 자당 밀리초 이하이고 같은 글자는 한 번뿐이다.
fn render(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    cells: []const vt.CellGlyph,
    prompt: ?Prompt,
) !void {
    // 여백(격자 바깥)만 상수로 칠한다. 격자 안은 아래에서 셀마다 덮는다.
    fb.fill(MARGIN_COLOR);

    // x를 글리프 폭으로 누적하지 않고 col로 계산하는 것이 중요하다.
    // libghostty-vt는 한글 같은 폭 2칸 문자 뒤에 spacer 셀을 넣어 col을
    // 이미 맞춰두기 때문에(TF-M2에서 '이'의 col이 6이 아니라 7이었던
    // 그 성질), col*CELL_W가 곧 정확한 픽셀 위치다.
    for (cells) |cell| {
        const x = GRID_X + @as(u32, cell.col) * CELL_W;
        const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
        drawCellBackground(fb, x, y, cell.bg);
    }

    for (cells) |cell| {
        // 빈 셀은 배경만 칠하고 끝난다. 캐시에 codepoint 0을 넣지 않기
        // 위해서이기도 하다 — 커서 자리와 색 띠가 전부 이쪽이라 흔하다.
        if (cell.codepoint == 0) continue;
        const x = GRID_X + @as(u32, cell.col) * CELL_W;
        const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
        const glyph = try cache.find(cell.codepoint);
        drawGlyph(fb, glyph, x, y, cell.fg);
    }

    if (prompt) |p| {
        try drawPrompt(fb, cache, p.text, p.rows, p.cols, p.fg, p.bg);
    }

    try fb.present();
}

/// 오버레이 한 줄에 필요한 것 전부.
///
/// 인자를 일곱 개 늘어놓지 않고 묶는 이유는 **호출부가 하나뿐**이기 때문이다.
/// 늘어놓으면 `rows`와 `cols`, `fg`와 `bg`를 뒤바꿔 넣어도 컴파일이 통과한다.
const Prompt = struct {
    text: []const u8,
    rows: u16,
    cols: u16,
    fg: u32,
    bg: u32,
};

/// 오버레이 한 줄에 쓸 글자를 정한다. **프롬프트가 우선이고, 닫혀 있으면
/// "못 찾았다" 메시지다**(design 결정 9). 둘 다 없으면 null이고, 그러면
/// 오버레이를 아예 안 그린다.
///
/// **`drawPrompt`는 이것을 모른다.** 그리는 함수는 "한 줄을 준 색으로 쓴다"
/// 하나만 알고, 무엇을 쓸지는 여기서 끝난다 — CN-M1이 앞의 `/`를 `vt.zig`가
/// 아니라 `main.zig`에서 붙인 것과 같은 경계다(모양은 여기가 정한다).
///
/// **프롬프트를 먼저 보는 것에 뜻이 있다.** 못 찾은 뒤에 `/`를 다시 열면 사람이
/// 지금 치고 있는 것이 화면에 나와야 한다. 순서를 뒤집으면 새 검색어를 치는
/// 동안 지난 실패 메시지가 화면에 남는다.
///
/// `buf`는 최소 **140바이트**여야 한다: `/` 하나 + needle 128 + `: not found`
/// 열하나.
fn promptText(screen: *vt.Screen, buf: []u8) ?[]const u8 {
    const MISS = ": not found";
    if (screen.findNeedle()) |n| {
        buf[0] = '/';
        @memcpy(buf[1 .. 1 + n.len], n);
        return buf[0 .. 1 + n.len];
    }
    if (screen.findMissed()) |n| {
        buf[0] = '/';
        @memcpy(buf[1 .. 1 + n.len], n);
        @memcpy(buf[1 + n.len ..][0..MISS.len], MISS);
        return buf[0 .. 1 + n.len + MISS.len];
    }
    return null;
}

/// 한 프레임에 찍는 style/pixel 줄의 상한. 화면 전체에 색이 깔린 프로그램이
/// 돌면 셀 수천 개가 매 프레임 로그로 쏟아진다. 게이트가 검사에 쓰는 셀은
/// 한 줄 안의 몇 개라 이만큼이면 넉넉하다.
const STYLE_DUMP_LIMIT: usize = 16;

/// 검증용으로 화면 내용을 serial 콘솔에 한 줄로 덤프한다.
/// check.sh가 이 줄을 grep해서 "입력이 실제로 셸을 움직였는가"를 판단한다.
///
/// **이 줄의 형식은 바꾸지 않는다.** 여섯 체인 중 다섯(TF·CP·IP·PM·HD)이
/// `terminal: screen>.*` 형태로 이 줄을 보고 화면을 판정한다. 색은 여기
/// 섞지 않고 아래 dumpStyles가 별도의 줄로 낸다(design 결정 7).
fn dumpScreen(cells: []const vt.CellGlyph) void {
    std.debug.print("terminal: screen> ", .{});
    var last_row: u16 = 0;
    for (cells) |cell| {
        if (cell.row != last_row) {
            std.debug.print(" | ", .{});
            last_row = cell.row;
        }
        // 글자 없는 셀도 이제 여기 도착한다(vt.zig의 design 결정 3).
        // 걸러내지 않으면 utf8Encode(0)이 NUL 바이트를 만들어 로그 줄에
        // 섞인다.
        if (cell.codepoint == 0) continue;
        var utf8: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(cell.codepoint), &utf8) catch continue;
        std.debug.print("{s}", .{utf8[0..len]});
    }
    std.debug.print("\n", .{});
}

/// 기본 색과 다른 셀을 두 줄씩 찍는다 — 파서가 본 색과, 프레임버퍼에서
/// 되읽은 실제 픽셀이다(design 결정 7).
///
/// 두 겹인 이유는 HD-M2가 잡은 "조용한 실패"와 같은 종류의 구멍을 막기
/// 위해서다. `style>`만 찍으면 파서가 옳고 렌더러가 틀렸을 때 게이트가
/// 통과한다. `pixel>`만 찍으면 실패는 잡히지만 어느 단계에서 틀어졌는지를
/// 따로 조사해야 한다.
///
/// **반드시 render() 뒤에 불러야 한다.** 그 전에 부르면 이전 프레임의
/// 픽셀을 읽는다.
fn dumpStyles(
    fb: drm.Framebuffer,
    cells: []const vt.CellGlyph,
    default_fg: u32,
    default_bg: u32,
    /// 프롬프트가 덮은 행. 없으면 null이다(CN-M1 plan 결정 4).
    overlaid_row: ?u16,
) void {
    var shown: usize = 0;
    var skipped: usize = 0;
    var hidden: usize = 0;
    for (cells) |cell| {
        // **덮인 줄은 아예 건너뛴다.** 이 함수가 두 줄을 찍는 것에 뜻이 있다 —
        // `style>`는 파서가 본 색이고 `pixel>`은 프레임버퍼에서 되읽은 값이며,
        // 둘이 어긋나면 렌더러가 틀렸다는 뜻이다(TR design 결정 7). 우리가 덮은
        // 줄에서는 그 전제가 깨진다: pixel>이 셀이 아니라 프롬프트를 말한다.
        //
        // 지금 이 줄을 보는 체인은 없지만(pixel>을 쓰는 것은 render 체인
        // 하나뿐이고 그 체인은 copy mode에 안 들어간다) **게이트가 못 보는
        // 부채를 새로 만들지 않는다.**
        if (overlaid_row) |r| {
            if (cell.row == r) {
                hidden += 1;
                continue;
            }
        }
        if (cell.fg == default_fg and cell.bg == default_bg) continue;
        if (shown >= STYLE_DUMP_LIMIT) {
            skipped += 1;
            continue;
        }
        shown += 1;
        std.debug.print("terminal: style> {d},{d} fg={X:0>6} bg={X:0>6}\n", .{
            cell.row, cell.col, cell.fg, cell.bg,
        });
        // 셀의 **중앙**을 읽는다. 모서리는 이웃 셀과의 경계라 off-by-one에
        // 취약하다.
        const px = GRID_X + @as(u32, cell.col) * CELL_W + CELL_W / 2;
        const py = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT + ROW_HEIGHT / 2;
        std.debug.print("terminal: pixel> {d},{d} = {X:0>6}\n", .{
            cell.row, cell.col, fb.getPixel(px, py) & 0x00FFFFFF,
        });
    }
    // 조용히 자르면 "색이 없다"와 "너무 많아서 안 찍었다"를 가를 수 없다.
    if (skipped > 0) {
        std.debug.print("terminal: style> {d} more cell(s) not shown\n", .{skipped});
    }
    // 조용히 건너뛰면 "그 줄에 색이 없다"와 "덮여서 안 봤다"를 가를 수 없다.
    if (hidden > 0) {
        std.debug.print("terminal: style> {d} cell(s) hidden by the find prompt\n", .{hidden});
    }
}

/// 한 프레임에 찍는 ink 줄의 상한. 한글이 화면을 덮은 상태에서 매 프레임
/// 수백 줄이 쏟아지는 것을 막는다. 게이트가 보는 것은 한 줄 안의 한두
/// 글자다.
const INK_DUMP_LIMIT: usize = 8;

/// 폭 2칸 글자가 **정말 두 칸에 걸쳐 찍혔는지**를 프레임버퍼에서 되읽어
/// 센다.
///
/// `style>`/`pixel>`이 색을 두 겹으로 보는 것과 같은 이유다(design 결정 7).
/// 한글은 **"파서가 폭 2칸으로 셌는가"와 "렌더러가 두 칸을 칠했는가"가 따로
/// 틀릴 수 있다.** 셀 하나만 보면 그 차이를 못 잡는다 — 글자가 왼쪽 반쪽만
/// 그려져도 그 셀에는 잉크가 있기 때문이다. 그래서 왼쪽 8픽셀과 오른쪽
/// 8픽셀을 따로 센다.
///
/// **반드시 render() 뒤에 불러야 한다.** 그 전에 부르면 이전 프레임의
/// 픽셀을 읽는다.
fn dumpInk(fb: drm.Framebuffer, cache: *font.Cache, cells: []const vt.CellGlyph) void {
    var shown: usize = 0;
    for (cells) |cell| {
        if (shown >= INK_DUMP_LIMIT) break;
        // render와 같은 이유로 빈 셀을 거른다. 이것이 없으면 dumpInk가
        // codepoint 0을 캐시에 집어넣어, render 쪽에서 막아 둔 것이 무효가
        // 된다.
        if (cell.codepoint == 0) continue;
        // 폭 2칸인 글자만 본다. cell_width는 폰트의 advance에서 온 값이라
        // "0x7F를 넘으면 넓다"는 짐작보다 정확하다.
        const glyph = cache.find(cell.codepoint) catch continue;
        if (glyph.cell_width <= CELL_W) continue;

        const x = GRID_X + @as(u32, cell.col) * CELL_W;
        const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
        // 마지막 칸에 폭 2칸 글자가 있으면 오른쪽 칸이 프레임버퍼 밖이다.
        // libghostty-vt가 그런 배치를 만들지 않지만, getPixel도 범위 검사를
        // 하지 않으므로 여기서 막는다.
        if (x + 2 * CELL_W > fb.width or y + ROW_HEIGHT > fb.height) continue;
        shown += 1;

        var left: u32 = 0;
        var right: u32 = 0;
        var row: u32 = 0;
        while (row < ROW_HEIGHT) : (row += 1) {
            var col: u32 = 0;
            while (col < 2 * CELL_W) : (col += 1) {
                if (fb.getPixel(x + col, y + row) & 0x00FFFFFF != cell.bg) {
                    if (col < CELL_W) left += 1 else right += 1;
                }
            }
        }
        std.debug.print("terminal: ink> {d},{d} U+{X} left={d} right={d}\n", .{
            cell.row, cell.col, cell.codepoint, left, right,
        });
    }
}

/// 뷰포트가 스크롤백의 어디에 있는지를 찍는다.
///
/// **게이트가 스크롤 위치를 볼 수 있는 유일한 창구다.** 화면 덤프만으로는
/// "올라갔다"와 "출력이 달라졌다"를 가를 수 없다 — 같은 글자가 두 번 나오는
/// 화면이면 둘이 구분되지 않는다. 거꾸로 이 줄만 보면 **뷰포트는 움직였는데
/// 화면은 그대로인** 상태를 못 잡으므로, 게이트는 둘을 나란히 본다.
/// `style>`/`pixel>`이 색을 두 겹으로 보는 것과 같은 구조다(design 결정 7).
///
/// **매 프레임 찍는다.** `font>`처럼 "바뀌었을 때만"으로 하면 게이트가
/// `tail -n 1`로 현재 상태를 읽을 수 없어진다 — "바닥에 그대로 있다"도
/// 검사해야 하는 사실이다(design 결정 13).
fn dumpScroll(screen: *vt.Screen) void {
    const sb = screen.scrollbar();
    std.debug.print("terminal: scroll> total={d} offset={d} len={d}\n", .{
        sb.total, sb.offset, sb.len,
    });
}

/// copy mode에서 무슨 일이 일어났는지를 찍는다.
///
/// **게이트가 모드 안을 볼 수 있는 유일한 창구다.** 화면만 보면 "모드에
/// 들어갔다"와 "아무 일도 안 일어났다"가 구분되지 않는다 — 모드에 들어가도
/// 화면에서 달라지는 것은 커서 반전 하나뿐이기 때문이다.
///
/// 문구가 이 파일과 `copy/check.sh` 양쪽에 중복된다(design 결정 8). 기존
/// 체인들과 같은 구조이고, **한쪽을 고치면 다른 쪽도 고쳐야 한다.**
fn dumpCopy(screen: *vt.Screen, what: []const u8) void {
    if (screen.copyCursor()) |cc| {
        std.debug.print("terminal: copy> {s} row={d} col={d}\n", .{ what, cc.y, cc.x });
    } else {
        // exit에는 좌표가 없다. 커서가 이미 사라졌기 때문이다.
        std.debug.print("terminal: copy> {s}\n", .{what});
    }
}

/// 검색 프롬프트의 상태를 찍는다.
///
/// **게이트가 프롬프트를 볼 수 있는 유일한 창구다.** 프롬프트는 오버레이라
/// `cells()`의 결과에 안 섞이고(design 결정 7), 그래서 `terminal: screen>` 줄에
/// 절대 안 나타난다. 그 격리가 다섯 체인의 화면 판정을 지키는 대신 관측 수단을
/// 하나 없앤다 — 이 줄이 그 자리를 메운다.
///
/// **`screen>`의 형식을 안 바꾸는 것이 이 설계 전체의 이유다.** 프롬프트를 셀에
/// 섞었다면 로그 한 줄로 끝났겠지만, 그 줄을 보던 체인 다섯이 전부 흔들린다.
///
/// 문구가 이 파일과 `copy/check.sh` 양쪽에 중복된다(design 결정 8).
/// **한쪽을 고치면 다른 쪽도 고쳐야 한다.**
fn dumpFind(screen: *vt.Screen, what: []const u8) void {
    if (screen.findNeedle()) |n| {
        std.debug.print("terminal: find> {s} needle={s} len={d}\n", .{ what, n, n.len });
    } else {
        // 프롬프트가 닫힌 뒤다. cancel과 submit이 여기로 온다.
        std.debug.print("terminal: find> {s}\n", .{what});
    }
}

/// 오버레이 한 줄에 무엇이 쓰였는지(CS-M1 plan 결정 3). **없으면 한 줄도 안
/// 찍는다.**
///
/// **이 줄이 유일한 관측 수단이다.** 오버레이는 `cells()`에 안 섞이므로
/// `screen>`에 영영 안 나오고, `dumpStyles`는 덮인 줄을 통째로 건너뛴다
/// (`overlaid_row`). 그래서 이 줄이 없으면 게이트가 "화면에 그렇게 쓰였다"를
/// 볼 창구가 하나도 없다 — `find> submit matches=0`은 "검색이 못 찾았다"까지만
/// 말한다.
///
/// **`render()`에 넘어간 바로 그 값을 받는다.** 문자열을 여기서 다시 만들지
/// 않는 이유는, 다시 만들면 그리는 것과 찍는 것이 갈릴 수 있기 때문이다.
///
/// `find> hl`과 같이 **매 프레임 찍는다**. "바뀔 때만"은 상태를 하나 더 만들고
/// 그 판정이 틀리면 증상이 "로그가 안 나온다"라 조사하기 나쁘다.
///
/// 문구가 이 파일과 `copy/check.sh` 양쪽에 중복된다.
/// **한쪽을 고치면 다른 쪽도 고쳐야 한다.**
fn dumpOverlay(prompt: ?Prompt) void {
    const p = prompt orelse return;
    std.debug.print("terminal: find> overlay text={s}\n", .{p.text});
}

/// 매치 하이라이트가 이 프레임에 무엇을 칠했는지(design 결정 5).
///
/// **상한을 안 두기로 한 결정의 근거를 남기는 줄이다.** `us=`가 밀리초 단위로
/// 커지면 그때 상한을 논의한다. `style>`는 프레임당 16줄이 상한이라
/// (`STYLE_DUMP_LIMIT`) 셀 수를 그것만으로 셀 수 없다 — 이 줄에는 상한이 없고,
/// 둘을 함께 보는 것이 plan 결정 3이다.
///
/// **검색이 없으면 한 줄도 안 찍는다.** `hlStats()`가 null을 주는 자리가
/// 그것이다(plan 결정 2).
///
/// **반드시 `render()` 뒤에 부른다** — 값은 그 프레임의 `cells()`가 만든다.
///
/// 문구가 이 파일과 `copy/check.sh` 양쪽에 중복된다.
/// **한쪽을 고치면 다른 쪽도 고쳐야 한다.**
fn dumpHighlight(screen: *vt.Screen) void {
    const hl = screen.hlStats() orelse return;
    // **`cur=`을 `cells=` 뒤·`us=` 앞에 넣는다**(SP-M0 plan 결정 5).
    // `copy/check.sh`의 검사 16이 `sed -E 's/.*cells=([0-9]+).*/\1/'`로
    // `cells=`를 뽑으므로 그 뒤에 필드를 더하는 것은 안전하지만, **`cells=`를
    // 옮기거나 `cells`를 부분 문자열로 갖는 이름을 쓰면 깨진다.**
    std.debug.print("terminal: find> hl spans={d} cells={d} cur={d} us={d}\n", .{
        hl.spans, hl.cells, hl.cur, hl.us,
    });
}

/// `y`가 클립보드에 무엇을 담았는지를 찍는다.
///
/// **게이트가 클립보드를 볼 수 있는 유일한 창구다.** 화면만 보면 복사가 됐는지
/// 알 방법이 아예 없다 — 복사는 화면을 안 바꾼다.
///
/// `len`을 함께 찍는 이유는 글자가 잘리거나 뒤에 뭐가 더 붙는 경우를 게이트가
/// 한 줄로 가릴 수 있게 하기 위해서다. `text=`가 맞아도 `len=`이 다르면 그것은
/// 다른 문자열이다.
///
/// 문구가 이 파일과 `copy/check.sh` 양쪽에 중복된다(design 결정 8).
/// **한쪽을 고치면 다른 쪽도 고쳐야 한다.**
fn dumpClip(text: ?[]const u8) void {
    if (text) |t| {
        std.debug.print("terminal: clip> len={d} text={s}\n", .{ t.len, t });
    } else {
        // 선택이 없는데 y를 눌렀다. 조용히 넘어가면 게이트가 "복사가 안 됐다"와
        // "y가 아예 안 도착했다"를 못 가른다.
        std.debug.print("terminal: clip> empty\n", .{});
    }
}

/// `Cmd+V`가 클립보드를 셸에 쓴다.
///
/// 쓰는 일과 찍는 일을 한 함수에 둔 이유는 **길이가 두 곳에서 갈리지 않게**
/// 하기 위해서다. 게이트가 `len=11`을 보고 "11바이트가 나갔다"로 읽는데, 쓰기와
/// 로그가 떨어져 있으면 그 둘이 다른 슬라이스를 볼 여지가 생긴다.
///
/// **bracketed paste로 감싸지 않는다**(design 결정 9). 여러 줄을 붙이면 개행이
/// 곧 실행이 되는 것을 감수한다 — 셸이 그 모드를 받는지 확인한 적이 없고,
/// 확인 없이 넣으면 게이트가 못 보는 코드가 느는 것이
/// `project_gate_chain_composition`이 경고한 부채 그대로다.
///
/// 새 접두사를 만들지 않고 `clip>`를 쓰는 것은 design 결정 8이다. 문구가 이
/// 파일과 `copy/check.sh` 양쪽에 중복된다 — **한쪽을 고치면 다른 쪽도 고쳐야
/// 한다.**
fn dumpPaste(screen: *vt.Screen, master_fd: c_int) void {
    const text = screen.clipboard() orelse {
        // 아직 아무것도 복사하지 않았는데 Cmd+V를 눌렀다. 조용히 넘어가면
        // 게이트가 "클립보드가 비었다"와 "Cmd+V가 아예 안 도착했다"를 못 가른다.
        std.debug.print("terminal: clip> paste empty\n", .{});
        return;
    };
    pty.write(master_fd, text);
    std.debug.print("terminal: clip> paste len={d}\n", .{text.len});
}

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    const fb = try drm.open(allocator, "/dev/dri/card0");
    fb.fill(MARGIN_COLOR);
    try fb.present();

    // 화면 크기를 여기서 **한 번만** 계산해 렌더러·Terminal·PTY winsize
    // 세 곳에 같은 값을 넘긴다. 이 셋이 어긋나면 셸이 생각하는 폭과 우리가
    // 그리는 폭이 달라져 줄바꿈이 엉킨다.
    const cols: u16 = @intCast((fb.width - 2 * GRID_X) / CELL_W);
    const rows: u16 = @intCast((fb.height - 2 * GRID_Y) / ROW_HEIGHT);
    std.debug.print("terminal: grid {d}x{d} (fb {d}x{d})\n", .{ cols, rows, fb.width, fb.height });

    const font_data = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "vendor/fonts/unifont.otf",
        allocator,
        .unlimited,
    );

    // 미리 굽지 않는다. 처음 쓸 때 굽는 캐시가 대신한다(design의 TR-M1 절).
    //
    // 이 폰트에 완성형 한글 11172자가 전부 들어 있어서 미리 굽기가 성립하지
    // 않는다 — 전부 구우면 비트맵만 2.07MB이고, 컨테이너(arm64 native)에서도
    // Debug 빌드로 396밀리초가 드는 일을 TCG 에뮬레이션 게스트가 부팅마다
    // 할 이유가 없다.
    //
    // font_data를 free하지 않는다. stb_truetype이 그 바이트를 복사하지 않고
    // 참조만 하므로 캐시보다 오래 살아야 한다.
    var cache = try font.Cache.init(allocator, font_data);
    defer cache.deinit();
    std.debug.print("terminal: font cache ready (lazy)\n", .{});

    // 다섯째 인자가 키보드 장치 경로다(HD-M0). 번호를 여기서 고르지 않는
    // 이유는 CP가 세운 규칙 그대로다 — 하드웨어를 살펴 고르는 일은 PID 1이
    // 하고 terminal은 그 결정을 실행만 한다. 손으로 실행할 때를 위한
    // 기본값은 예전 상수와 같다.
    //
    // args를 셸 인자를 꺼내는 자리보다 위에서 선언하는 이유는 장치를 여는
    // 일이 그보다 먼저 오기 때문이다. 로그 순서를 그대로 두려고 여는 자리를
    // 내리지 않고 선언을 올렸다.
    const args = init.minimal.args.vector;
    const input_device: [*:0]const u8 = if (args.len > 4) args[4] else "/dev/input/event0";

    const keyboard_fd = input.openDevice(input_device) catch |err| {
        std.debug.print("terminal: FATAL cannot open {s}: {any}\n", .{ input_device, err });
        return err;
    };
    std.debug.print("terminal: opened {s}\n", .{input_device});

    // 어느 셸을 띄울지는 init이 정해서 argv로 넘겨준다(CP-M2). 설정 파일을
    // 읽는 것은 PID 1의 일이고, terminal은 그 결정을 실행만 한다 — 파서가 두
    // 벌이 되면 두 프로세스가 같은 파일에서 서로 다른 답을 얻을 수 있다.
    // 인자 없이 손으로 실행할 때를 위해 기본값은 남긴다.
    //
    // `-c` 없이 실행하면 대화형 모드다 — 프롬프트를 그리고 입력을 기다린다.
    // no-config 플래그(fish --no-config / bash --norc / zsh -f)를 계속 주는
    // 이유는 프롬프트가 예측 가능해야 게이트가 화면을 검사할 수 있기 때문이다.
    const shell_path: [*:0]const u8 = if (args.len > 1) args[1] else "/usr/bin/fish";
    const shell_flag: [*:0]const u8 = if (args.len > 2) args[2] else "--no-config";
    // 넷째 인자가 키보드 종류다(IP-M2, design doc 결정 9). enum을 여기 다시
    // 정의하지 않고 문자열 하나만 비교하는 것이 요점이다 — CP가 정한
    // "파서는 한 벌"을 지킨다. init이 enum으로 이미 걸렀으므로 여기 도착하는
    // 값은 apple 아니면 pc이고, 그 외 무엇이 오더라도 apple로 떨어진다.
    const keyboard: [*:0]const u8 = if (args.len > 3) args[3] else "apple";
    const swap_alt_meta = std.mem.eql(u8, std.mem.span(keyboard), "pc");

    // TERM은 지금까지 거짓말을 하고 있었다. 커널의 envp_init이 준
    // `TERM=linux`가 PID 1을 거쳐 여기까지 상속되는데
    // (docs/decisions/project_guest_environment.md), 이 셸이 말을 거는 상대는
    // 리눅스 콘솔이 아니라 libghostty-vt다. 셸과 ncurses 프로그램은 terminfo를
    // 보고 시퀀스를 고르므로, 이름이 틀리면 우리가 보내는 특수키와 셸이
    // 기대하는 것이 어긋난다 — Home이 linux에서는 `ESC [ 1 ~`, xterm에서는
    // `ESC O H`다.
    //
    // execv는 환경을 그대로 상속하므로 **fork 전에** 고쳐두면 자식이 받는다.
    // 이 setenv가 PID 1이 아니라 여기 있는 이유는 시리얼 콘솔 셸 때문이다 —
    // 그쪽은 정말로 커널 콘솔이라 TERM=linux가 맞다. 같은 기계 안에서 두
    // 셸의 TERM이 다른 것이 정상이다(design doc 결정 7).
    //
    // TR-M0부터 xterm-256color다. 그전에는 "우리가 색을 하나도 그리지 않아서"
    // xterm이었는데, 이제 팔레트 256색과 truecolor를 전부 칠하므로 xterm이라고
    // 말하는 쪽이 거짓말이 된다(design 결정 8).
    _ = setenv("TERM", "xterm-256color", 1);

    const argv = [_:null]?[*:0]const u8{ shell_path, shell_flag };
    const session = try pty.spawn(shell_path, &argv, cols, rows);
    // 경로까지 찍는다. 게이트가 "화면의 셸도 바뀌었는가"를 볼 수 있는 유일한
    // 줄이다. 앞부분("terminal: spawned child pid ")은 terminal/check.sh가
    // 개수를 세는 마커라 **그대로 둔다**.
    std.debug.print("terminal: spawned child pid {d} ({s})\n", .{
        session.child_pid, shell_path,
    });
    // 게이트가 "설정이 여기까지 왔는가"를 볼 수 있는 유일한 줄이다.
    // 이 값이 실제로 무슨 일을 하는지는 화면으로만 증명되지만(input/check.sh의
    // 2차 부팅), 그 화면이 틀렸을 때 "설정이 안 왔다"와 "설정은 왔는데 뜻이
    // 틀렸다"를 가르는 것이 이 줄이다.
    std.debug.print("terminal: keyboard={s} (swap_alt_meta={})\n", .{
        keyboard, swap_alt_meta,
    });

    const screen = try vt.Screen.init(init.io, allocator, cols, rows);
    defer screen.deinit();

    const cell_buf = try allocator.alloc(vt.CellGlyph, @as(usize, cols) * rows);
    defer allocator.free(cell_buf);

    // 첫 프레임만 잰다. 매 프레임 찍으면 로그가 시끄럽고, 첫 프레임이 가장
    // 비싼 경우(폰트 캐시도 페이지도 차갑다)라 상한을 본다.
    var first_frame_timed = false;
    // 캐시가 자랐을 때만 찍는다. 매 프레임 찍으면 키를 칠 때마다 같은 줄이
    // 반복된다. design 위험 3을 게이트가 볼 수 있게 하는 자리다.
    var last_glyph_count: usize = 0;
    // TR-M2의 구조 변경. 그전에는 렌더가 PTY 출력 분기 **안에만** 있었다 —
    // 스크롤은 키로 일어나므로 그대로 두면 뷰포트만 움직이고 화면은 안 바뀐다.
    var needs_redraw = false;
    var key_state: input.State = .{};
    var key_buf: [64]u8 = undefined;
    var pty_buf: [4096]u8 = undefined;

    var fds = [_]c.struct_pollfd{
        .{ .fd = keyboard_fd, .events = c.POLLIN, .revents = 0 },
        .{ .fd = session.master_fd, .events = c.POLLIN, .revents = 0 },
    };

    while (true) {
        // -1 = 무한 대기. 이벤트가 없으면 CPU를 전혀 쓰지 않는다.
        const ready = c.poll(&fds, fds.len, -1);
        if (ready < 0) continue; // EINTR 등은 그냥 다시 기다린다

        if (fds[0].revents & c.POLLIN != 0) {
            // DECCKM은 셸이 언제든 켜고 끌 수 있으므로(프롬프트를 그릴 때
            // smkx, 외부 명령을 실행하기 전에 rmkx 하는 식으로 오간다)
            // 캐시하지 않고 **키를 읽는 순간의 값**을 쓴다. packed struct의
            // 비트 읽기 한 번이라 비용이 없다 — design doc 결정 6이 "값으로
            // 넘긴다"를 고르면서 감수하기로 한 대가가 이것이다.
            const ctx = input.Context{
                .cursor_keys = screen.term.modes.get(.cursor_keys),
                // DECCKM과 달리 이 값은 부팅 내내 상수다. 매 키마다 다시
                // 넣는 것은 Context를 한 자리에서 조립하기 위해서일 뿐이다.
                .swap_alt_meta = swap_alt_meta,
            };
            const keys = input.readKeys(&key_state, keyboard_fd, &key_buf, ctx);
            if (keys.bytes.len > 0) {
                // 앞부분("terminal: key> ")은 input/check.sh가 grep하는
                // 마커라 **그대로 둔다**. 뒤에 decckm을 덧붙이는 이유는
                // design doc 위험 4다 — 게이트가 `ESC O` 경로를 실제로
                // 밟았는지 아니면 `ESC [`만 봤는지를 로그로 알 수 있어야 한다.
                std.debug.print("terminal: key> {d} byte(s) decckm={}\n", .{
                    keys.bytes.len, ctx.cursor_keys,
                });
                pty.write(session.master_fd, keys.bytes);
            }
            // 스크롤은 PTY로 나가지 않는다(design 결정 11). **한 화면이 몇
            // 줄인지를 아는 것은 여기뿐이라**, page_up/page_down을 rows 만큼의
            // delta로 바꾸는 것도 여기서 한다 — input.zig는 격자 크기를 모른다.
            //
            // 순서대로 도는 이유는 자동 반복 때문이다. PageUp을 누르고 있으면
            // 한 번의 read에 여러 개가 실려 오고, 그만큼 올라가야 한다.
            for (keys.scrolls) |s| {
                switch (s) {
                    .top => screen.scrollToTop(),
                    .bottom => screen.scrollToBottom(),
                    .page_up => screen.scrollByRows(-@as(isize, rows)),
                    .page_down => screen.scrollByRows(@as(isize, rows)),
                }
                needs_redraw = true;
            }
            // copy mode 명령도 PTY로 나가지 않는다(design 결정 3). 스크롤과
            // 같은 이유로 순서대로 돈다 — j를 누르고 있으면 자동 반복이 여러
            // 개를 실어 온다.
            for (keys.copies) |cmd| {
                // **"못 찾았다" 메시지는 다음 키에 사라진다**(design 결정 9).
                //
                // 끄는 자리가 **루프 안**인 것에 뜻이 있다. 밖에 두면 한 번의
                // read에 여러 키가 실려 왔을 때(자동 반복) 첫 키만 메시지를
                // 지운다.
                //
                // 그리고 `switch`보다 **앞**이라, 모든 명령이 예외 없이 지우고
                // 그중 `.find_submit`만이 그 뒤에 다시 켤 수 있다. 순서 하나로
                // "다음 키에 사라진다"와 "새로 실패하면 다시 뜬다"가 함께 나온다.
                screen.findClearMissed();
                switch (cmd) {
                    .enter => screen.copyEnter(),
                    .exit => screen.copyExit(),
                    .left => try screen.copyMove(-1, 0),
                    .down => try screen.copyMove(0, 1),
                    .up => try screen.copyMove(0, -1),
                    .right => try screen.copyMove(1, 0),
                    // 단어 이동(CN-M0). copyMove와 형제이고 선택 갱신도 같은
                    // copyApply를 통과한다 — 그래서 여기 배선은 한 줄이다.
                    .word_next => try screen.copyMoveWord(.next),
                    .word_prev => try screen.copyMoveWord(.prev),
                    .select_char => try screen.copySelect(.char),
                    .select_line => try screen.copySelect(.line),
                    // yank는 **모드를 나간다.** 그래서 아래 dumpCopy는 좌표
                    // 없이 `copy> yank`만 찍는다 — 커서가 이미 사라졌기
                    // 때문이다.
                    .yank => dumpClip(try screen.copyYank()),
                    // 붙여넣기는 **모드를 건드리지 않는다.** 그래서 모드 안에서
                    // 누르면 아래 dumpCopy가 좌표를 그대로 찍고, 모드 밖에서
                    // 누르면 `copy> paste`만 찍힌다. 게이트가 그 차이로 "모드가
                    // 살아 있는가"를 본다.
                    //
                    // 이것이 copies 배열에서 **유일하게 PTY로 나가는 명령**이다.
                    // 다른 아홉은 전부 우리 안에서 끝난다.
                    .paste => dumpPaste(screen, session.master_fd),
                    // 검색 프롬프트(CN-M1). **넷 다 화면 상태를 바꾸지 않는다** —
                    // needle 버퍼만 만지고, 그리는 것은 아래 render가 한다.
                    .find_open => {
                        screen.findOpen();
                        dumpFind(screen, "open");
                    },
                    .find_char => |ch| {
                        screen.findChar(ch);
                        dumpFind(screen, "type");
                    },
                    .find_erase => {
                        screen.findErase();
                        dumpFind(screen, "erase");
                    },
                    .find_cancel => {
                        screen.findCancel();
                        dumpFind(screen, "cancel");
                    },
                    // **이 milestone에서 유일하게 시간이 걸리는 명령이다.**
                    // searchAll()이 스크롤백 전체를 훑는 동안 화면이 멈춘다
                    // (design 결정 5). 얼마나 멈추는지를 여기서 재서 찍는다 —
                    // 그 값이 "증분으로 바꿔야 하는가"를 나중에 가른다.
                    .find_submit => {
                        const t0 = std.Io.Clock.now(.awake, init.io);
                        const r = try screen.findSubmit();
                        std.debug.print(
                            "terminal: find> submit matches={d} moved={} us={d}\n",
                            .{
                                r.matches,
                                r.moved,
                                @divTrunc(t0.untilNow(init.io, .awake).nanoseconds, 1000),
                            },
                        );
                    },
                    // **결과를 버리지 않고 찍는다.** 못 옮긴 것과 옮긴 것은
                    // 사람에게 다른 뜻이고, 아래 dumpCopy의 좌표만으로는
                    // "안 움직였다"와 "같은 자리가 맞다"를 못 가른다.
                    .find_next => std.debug.print(
                        "terminal: find> next moved={}\n",
                        .{try screen.findNext()},
                    ),
                    .find_prev => std.debug.print(
                        "terminal: find> prev moved={}\n",
                        .{try screen.findPrev()},
                    ),
                }
                dumpCopy(screen, @tagName(cmd));
                needs_redraw = true;
            }
        }

        // PTY master는 slave가 전부 닫히면 POLLIN이 아니라 POLLHUP을 올린다.
        // 남은 출력이 있으면 POLLIN과 함께 오지만 다 읽고 나면 POLLHUP만
        // 남으므로, POLLIN만 보면 read를 영영 호출하지 못하고 poll이 즉시
        // 반환하는 바쁜 루프에 빠진다. POLLHUP에서도 read를 시도하면 남은
        // 데이터를 먼저 비우고, 비고 나면 read가 EIO를 내 EOF 경로로 간다.
        if (fds[1].revents & (c.POLLIN | c.POLLHUP | c.POLLERR) != 0) {
            const out = pty.readSome(session.master_fd, &pty_buf);
            if (out.len == 0) {
                std.debug.print("terminal: child exited (pty EOF)\n", .{});
                break;
            }
            screen.feed(out);
            // design 결정 13. **라이브러리는 이것을 해 주지 않는다** — 올라간
            // 상태에서 출력을 먹여도 뷰포트가 그대로라는 것을 2026-08-23에
            // 실측했고, vt_test가 그 사실을 못 박고 있다. 대부분의 터미널이
            // 이렇게 동작하며, 그러지 않으면 "화면이 멈춘 것 같다"는 혼란이
            // 생긴다.
            //
            // 부수 효과가 하나 있다: 뷰포트가 history에 머무는 동안 가지치기가
            // 일어나는 상황이 이 한 줄로 **구조적으로** 안 생긴다. 가지치기는
            // 그 페이지를 가리키던 pin을 무효로 만드는데, 여기서 창이 닫힌다.
            // **copy mode 중에는 억제한다**(CM-M0). 백그라운드 출력이 한 줄만
            // 도착해도 사람이 올라가서 보고 있던 자리가 화면 밖으로 튕기기
            // 때문이다.
            //
            // 그 대가로 위 주석이 말한 창이 열린다 — 뷰포트가 history에
            // 머무는 동안 가지치기가 일어날 수 있게 된다(design 위험 1).
            // CM-M1이 방어를 넣었는데, **계획했던 모양이 아니다**: 가지치기는
            // 선택을 null로 만들지 않고 tracked pin을 이웃 페이지의 왼쪽 위로
            // 옮기므로, vt.zig의 feed가 앵커의 screen 좌표 y를 대신 감시한다.
            //
            // **이 억제 분기 자체는 CM-M2의 게이트가 밟는다.** 모드 안에서는
            // 셸에 아무것도 보낼 수 없어 출력을 만들 방법이 없었는데,
            // Cmd+V가 그 방법이 됐다 — 붙여넣은 글자를 셸이 되울리는 것이
            // 곧 "모드 중에 도착한 PTY 출력"이다.
            if (!screen.copyActive()) screen.scrollToBottom();
            // 위 feed가 가지치기를 만났으면 vt.zig가 모드를 이미 닫았다
            // (design 위험 1). **로그를 안 남기면 사람이 "왜 갑자기 모드가
            // 풀렸지"를 영영 모른다.**
            if (screen.copyTakePruned()) dumpCopy(screen, "pruned");
            needs_redraw = true;
        }

        // 렌더를 루프 끝으로 뺀 것이 TR-M2의 구조 변경이다. 그전에는 렌더가
        // PTY 출력 분기 **안에만** 있었다 — 스크롤은 키로 일어나므로 그대로
        // 두면 뷰포트만 움직이고 화면은 안 바뀐다.
        //
        // 플래그를 두는 이유는 그리는 횟수를 늘리지 않기 위해서다. modifier
        // 키처럼 아무것도 바꾸지 않는 이벤트에서는 그리지 않는다.
        if (!needs_redraw) continue;
        needs_redraw = false;

        const cells = try screen.cells(cell_buf);

        // 프롬프트 문자열을 여기서 만든다. **`vt.zig`는 앞의 `/`를 모른다** —
        // 그것은 표현이지 상태가 아니고, TR-M0이 색을 vt.zig에서 확정해 넘긴
        // 것과 반대 방향의 같은 경계다(모양은 main.zig가 정한다).
        //
        // 버퍼가 needle보다 **열두 칸** 크다. 앞의 `/` 하나와 뒤의
        // `: not found` 열하나 때문이다(CS-M1).
        var prompt_buf: [140]u8 = undefined;
        const prompt: ?Prompt = if (promptText(screen, &prompt_buf)) |t| .{
            .text = t,
            .rows = rows,
            .cols = cols,
            // **`cells()` 뒤에 읽어야 한다** — `state.colors`는 update()가
            // 채운다(vt.zig의 defaultFg 주석).
            .fg = screen.defaultFg(),
            .bg = screen.defaultBg(),
        } else null;

        const frame_start = std.Io.Clock.now(.awake, init.io);
        try render(fb, &cache, cells, prompt);
        if (!first_frame_timed) {
            first_frame_timed = true;
            std.debug.print("terminal: render> first frame {d}us\n", .{
                @divTrunc(frame_start.untilNow(init.io, .awake).nanoseconds, 1000),
            });
        }

        dumpScreen(cells);
        dumpHighlight(screen);
        dumpOverlay(prompt);
        // render 뒤에 부른다 — 그 전에 부르면 이전 프레임의 픽셀을 읽는다.
        // 기본 색을 여기 상수로 다시 적지 않고 screen에서 얻는 이유는
        // vt.zig의 defaultFg 주석에 있다.
        dumpStyles(
            fb,
            cells,
            screen.defaultFg(),
            screen.defaultBg(),
            if (prompt != null) rows - 1 else null,
        );        dumpInk(fb, &cache, cells);
        dumpScroll(screen);
        if (cache.count() != last_glyph_count) {
            last_glyph_count = cache.count();
            std.debug.print("terminal: font> {d} glyph(s) cached, {d} bitmap bytes\n", .{
                last_glyph_count, cache.bitmap_bytes,
            });
        }
    }

    // 셸이 끝나면 터미널도 끝난다. PID 1(tars-init)이 우리를 다시 띄우고,
    // 새 프로세스가 DRM을 다시 열어 새 프롬프트를 그린다. TF 시절의 무한
    // sleep은 되살려 줄 감독자가 없어서 필요했던 것이라 이제 지운다.
}
