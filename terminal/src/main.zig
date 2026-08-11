const std = @import("std");
const drm = @import("drm.zig");
const font = @import("font.zig");
const input = @import("input.zig");
const pty = @import("pty.zig");
const vt = @import("vt.zig");

const c = @cImport({
    @cInclude("poll.h");
});

const BACKGROUND: u32 = 0x00102030;
const TEXT_COLOR: u32 = 0x00FFFFFF;
const GRID_X: u32 = 20;
const GRID_Y: u32 = 20;
const CELL_W: u32 = 8; // 8x4x4-fonts의 라틴 글리프 폭(font.zig:19-22 참고)
const ROW_HEIGHT: u32 = 16;

const INPUT_DEVICE = "/dev/input/event0";

fn drawGlyph(fb: drm.Framebuffer, glyph: font.Glyph, x: u32, y: u32) void {
    const bitmap = glyph.bitmap orelse return;
    var row: u32 = 0;
    while (row < glyph.height) : (row += 1) {
        var col: u32 = 0;
        while (col < glyph.width) : (col += 1) {
            const coverage = bitmap[row * glyph.width + col];
            if (coverage > 127) {
                fb.setPixel(x + col, y + row, TEXT_COLOR);
            }
        }
    }
}

/// 화면 전체를 지우고 셀 목록을 다시 그린다. 키 입력 빈도에서 부분 갱신은
/// 불필요한 복잡도다(YAGNI).
fn render(fb: drm.Framebuffer, cache: font.GlyphCache, cells: []const vt.CellGlyph) !void {
    fb.fill(BACKGROUND);
    for (cells) |cell| {
        // x를 글리프 폭으로 누적하지 않고 col로 계산하는 것이 중요하다.
        // libghostty-vt는 한글 같은 폭 2칸 문자 뒤에 spacer 셀을 넣어 col을
        // 이미 맞춰두기 때문에(TF-M2에서 '이'의 col이 6이 아니라 7이었던
        // 그 성질), col*CELL_W가 곧 정확한 픽셀 위치다.
        const x = GRID_X + @as(u32, cell.col) * CELL_W;
        const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
        if (font.find(cache, cell.codepoint)) |glyph| {
            drawGlyph(fb, glyph, x, y);
        }
    }
    try fb.present();
}

/// 검증용으로 화면 내용을 serial 콘솔에 한 줄로 덤프한다.
/// check.sh가 이 줄을 grep해서 "입력이 실제로 셸을 움직였는가"를 판단한다.
fn dumpScreen(cells: []const vt.CellGlyph) void {
    std.debug.print("terminal: screen> ", .{});
    var last_row: u16 = 0;
    for (cells) |cell| {
        if (cell.row != last_row) {
            std.debug.print(" | ", .{});
            last_row = cell.row;
        }
        var utf8: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(cell.codepoint), &utf8) catch continue;
        std.debug.print("{s}", .{utf8[0..len]});
    }
    std.debug.print("\n", .{});
}

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    const fb = try drm.open(allocator, "/dev/dri/card0");
    fb.fill(BACKGROUND);
    try fb.present();

    // 화면 크기를 여기서 **한 번만** 계산해 렌더러·Terminal·PTY winsize
    // 세 곳에 같은 값을 넘긴다. 이 셋이 어긋나면 셸이 생각하는 폭과 우리가
    // 그리는 폭이 달라져 줄바꿈이 엉킨다.
    const cols: u16 = @intCast((fb.width - 2 * GRID_X) / CELL_W);
    const rows: u16 = @intCast((fb.height - 2 * GRID_Y) / ROW_HEIGHT);
    std.debug.print("terminal: grid {d}x{d} (fb {d}x{d})\n", .{ cols, rows, fb.width, fb.height });

    const font_data = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "vendor/fonts/Hanme_8x4x4.ttf",
        allocator,
        .unlimited,
    );

    // 사용자가 아무 키나 칠 수 있으므로 출력 가능한 ASCII 전체를 미리
    // 래스터라이징한다(0x20 ' ' ~ 0x7E '~', 95자).
    var codepoints: [95]u32 = undefined;
    for (&codepoints, 0..) |*cp, i| cp.* = @intCast(0x20 + i);
    const cache = try font.build(allocator, font_data, &codepoints);
    std.debug.print("terminal: rasterized {d} glyphs\n", .{codepoints.len});

    const keyboard_fd = input.openDevice(INPUT_DEVICE) catch |err| {
        std.debug.print("terminal: FATAL cannot open {s}: {any}\n", .{ INPUT_DEVICE, err });
        return err;
    };
    std.debug.print("terminal: opened {s}\n", .{INPUT_DEVICE});

    // `-c` 없이 실행하면 대화형 모드다 — 프롬프트를 그리고 입력을 기다린다.
    // `--no-config`는 유지한다(사용자 설정 파일이 initrd에 없기도 하고,
    // 프롬프트가 예측 가능해야 검증이 쉽다).
    const argv = [_:null]?[*:0]const u8{ "fish", "--no-config" };
    const session = try pty.spawn("/usr/bin/fish", &argv, cols, rows);
    std.debug.print("terminal: spawned child pid {d}\n", .{session.child_pid});

    const screen = try vt.Screen.init(init.io, allocator, cols, rows);
    defer screen.deinit();

    const cell_buf = try allocator.alloc(vt.CellGlyph, @as(usize, cols) * rows);
    defer allocator.free(cell_buf);

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
            const bytes = input.readKeys(&key_state, keyboard_fd, &key_buf);
            if (bytes.len > 0) {
                std.debug.print("terminal: key> {d} byte(s)\n", .{bytes.len});
                pty.write(session.master_fd, bytes);
            }
        }

        if (fds[1].revents & c.POLLIN != 0) {
            const out = pty.readSome(session.master_fd, &pty_buf);
            if (out.len == 0) {
                std.debug.print("terminal: child exited (pty EOF)\n", .{});
                break;
            }
            screen.feed(out);
            const cells = try screen.cells(cell_buf);
            try render(fb, cache, cells);
            dumpScreen(cells);
        }
    }

    // 자식이 죽어도 패닉하지 않고 화면을 유지한 채 남는다.
    // nfds=0인 poll은 "아무 fd도 안 보고 timeout만 기다린다" = sleep이다.
    while (true) {
        _ = c.poll(&fds, 0, 1000);
    }
}
