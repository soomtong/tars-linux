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

const BACKGROUND: u32 = 0x00102030;
const TEXT_COLOR: u32 = 0x00FFFFFF;
const GRID_X: u32 = 20;
const GRID_Y: u32 = 20;
const CELL_W: u32 = 8; // 8x4x4-fonts의 라틴 글리프 폭(font.zig:19-22 참고)
const ROW_HEIGHT: u32 = 16;

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
    // Task 1 임시 확인 — design 위험 4. Task 6에서 진짜 로그로 바뀐다.
    std.debug.print("terminal: probe> wrote {X:0>6} read {X:0>6}\n", .{
        BACKGROUND, fb.getPixel(100, 100) & 0x00FFFFFF,
    });

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
    // xterm-256color가 아니라 xterm인 이유는 우리가 아직 색을 하나도 그리지
    // 않기 때문이다(TEXT_COLOR 상수 하나). 256색을 광고하면 반대 방향의
    // 거짓말이 된다.
    _ = setenv("TERM", "xterm", 1);

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
            const bytes = input.readKeys(&key_state, keyboard_fd, &key_buf, ctx);
            if (bytes.len > 0) {
                // 앞부분("terminal: key> ")은 input/check.sh가 grep하는
                // 마커라 **그대로 둔다**. 뒤에 decckm을 덧붙이는 이유는
                // design doc 위험 4다 — 게이트가 `ESC O` 경로를 실제로
                // 밟았는지 아니면 `ESC [`만 봤는지를 로그로 알 수 있어야 한다.
                std.debug.print("terminal: key> {d} byte(s) decckm={}\n", .{
                    bytes.len, ctx.cursor_keys,
                });
                pty.write(session.master_fd, bytes);
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
            const cells = try screen.cells(cell_buf);
            try render(fb, cache, cells);
            dumpScreen(cells);
        }
    }

    // 셸이 끝나면 터미널도 끝난다. PID 1(tars-init)이 우리를 다시 띄우고,
    // 새 프로세스가 DRM을 다시 열어 새 프롬프트를 그린다. TF 시절의 무한
    // sleep은 되살려 줄 감독자가 없어서 필요했던 것이라 이제 지운다.
}
