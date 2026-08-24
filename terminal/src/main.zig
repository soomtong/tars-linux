const std = @import("std");
const drm = @import("drm.zig");
const font = @import("font.zig");
const input = @import("input.zig");
const pty = @import("pty.zig");
const vt = @import("vt.zig");

const c = @cImport({
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

/// 화면 전체를 지우고 셀 목록을 다시 그린다. 키 입력 빈도에서 부분 갱신은
/// 불필요한 복잡도다(YAGNI) — `RenderState`가 dirty를 주지만 쓰지 않는다.
///
/// **두 벌로 나눠 그린다**(design 결정 6). 배경을 전부 칠하고 나서 글리프를
/// 전부 그린다. 섞으면 다음 셀의 배경이 앞 글자의 삐져나온 획을 지운다.
/// `cache`가 `*font.Cache`인 이유는 TR-M1부터 **그리는 도중에 글자를 굽기
/// 때문이다.** 캐시에 없는 글자가 화면에 나타나면 그 자리에서 래스터라이징이
/// 일어난다 — 한 자당 밀리초 이하이고 같은 글자는 한 번뿐이다.
fn render(fb: drm.Framebuffer, cache: *font.Cache, cells: []const vt.CellGlyph) !void {
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

    try fb.present();
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
) void {
    var shown: usize = 0;
    var skipped: usize = 0;
    for (cells) |cell| {
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
                switch (cmd) {
                    .enter => screen.copyEnter(),
                    .exit => screen.copyExit(),
                    .left => screen.copyMove(-1, 0),
                    .down => screen.copyMove(0, 1),
                    .up => screen.copyMove(0, -1),
                    .right => screen.copyMove(1, 0),
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
            // copy mode 중에 1000줄이 쏟아져야 닿는 자리라 게이트로 만들지
            // 않았고, CM-M1이 선택이 무효가 됐는지를 매 프레임 보는 방어를
            // 넣는다.
            if (!screen.copyActive()) screen.scrollToBottom();
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
        const frame_start = std.Io.Clock.now(.awake, init.io);
        try render(fb, &cache, cells);
        if (!first_frame_timed) {
            first_frame_timed = true;
            std.debug.print("terminal: render> first frame {d}us\n", .{
                @divTrunc(frame_start.untilNow(init.io, .awake).nanoseconds, 1000),
            });
        }

        dumpScreen(cells);
        // render 뒤에 부른다 — 그 전에 부르면 이전 프레임의 픽셀을 읽는다.
        // 기본 색을 여기 상수로 다시 적지 않고 screen에서 얻는 이유는
        // vt.zig의 defaultFg 주석에 있다.
        dumpStyles(fb, cells, screen.defaultFg(), screen.defaultBg());
        dumpInk(fb, &cache, cells);
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
