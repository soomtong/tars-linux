const std = @import("std");
const drm = @import("drm.zig");
const font = @import("font.zig");
const hangul = @import("hangul.zig");
const image = @import("image.zig");
const input = @import("input.zig");
const layout = @import("layout.zig");
const pointer = @import("pointer.zig");
const pty = @import("pty.zig");
const status = @import("status.zig");
const vt = @import("vt.zig");

// C 헤더는 build.zig가 번역해 `c_poll`로 넘긴다(ZU-M1). fortify를 끄는 유일한
// 번역이다 — 켜지면 `c.poll`이 인라인 래퍼가 되고 그 번역이 c_int 자리에
// bool을 놓는다. 자세한 것은 build.zig의 `c_poll` 위에 있다.
const c = @import("c_poll");

/// libc의 setenv를 직접 선언한다. 이 파일이 받는 번역은 poll.h 하나뿐이고,
/// setenv 하나 때문에 stdlib.h를 통째로 끌어오면 이름 충돌 가능성만 는다.
/// `input.zig`가 open/read를, `pty.zig`가 execv를 이렇게 선언한 것과 같다.
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

/// ioctl도 같은 이유로 직접 선언한다(PD-M0). 시그니처는 `drm.zig`가 받는
/// `c_drm` 번역의 것과 같다. 요청 번호는 `pointer.zig`가 번역된 매크로로 짓는다.
extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;

/// socket도 직접 선언한다. `std.c`에 있지만 공개가 아니다(PD-M0 plan 확정 4).
/// 부팅 뒤에 꽂힌 포인터 장치를 커널의 uevent netlink 소켓으로 안다.
extern "c" fn socket(domain: c_uint, sock_type: c_uint, protocol: c_uint) c_int;

// 화면 여백을 칠할 색. 셀의 배경색은 이제 상수가 아니라 vt.zig가 셀마다
// 확정해서 넘긴다(design 결정 1·5) — 이 상수는 격자 바깥에만 쓴다.
const MARGIN_COLOR: u32 = 0x00102030;
const GRID_X: u32 = 20;
const GRID_Y: u32 = 20;
const CELL_W: u32 = 8; // unifont의 라틴 advance. 폰트가 준 값과 같아야
                       // 한다 — font.zig의 Glyph.cell_width가 그 값이다.
const ROW_HEIGHT: u32 = 16;

/// 상태 줄 앞 세 칸의 글자 색(IS design 결정 7). 여백(`MARGIN_COLOR`) 위에서
/// 읽히되 눈을 안 끄는 회색이다 — 이것은 터미널의 내용이 아니라 창틀이다.
const STATUS_FG: u32 = 0x00808890;

/// 대문자 잠금이 켜졌을 때 `CAPS` 칸의 색(IS-M1).
///
/// SP-M0의 `CURRENT_BG`와 같은 앰버다. 이 저장소는 이미 그 색으로
/// "지금 봐야 할 것"을 뜻한다(검색의 현재 매치) — 켜진 대문자 잠금이
/// 정확히 그런 것이다.
const STATUS_ON: u32 = 0x00C08000;

/// 꺼졌을 때 `CAPS` 칸의 색. 여백(`MARGIN_COLOR` = 0x00102030)보다 조금
/// 밝아 자리는 보이되 안 읽힌다.
///
/// 칸을 지우지 않는 이유는 결정 2다 — 문자열 길이가 수시로 바뀌면 눈도
/// 게이트도 어렵다. 그리고 이 색이 게이트의 대조군이다: 꺼졌을 때
/// `off>0`을 함께 보지 않으면 "아예 안 그렸다"와 "어둡게 그렸다"가 안
/// 갈린다.
///
/// `MARGIN_COLOR`와 달라야 한다. 같으면 `dumpStatus`가 여백 전체를
/// 세면서 픽셀 수만 개를 돌려준다.
const STATUS_OFF: u32 = 0x00303840;

/// copy mode일 때 꼬리에 붙는 `COPY` 칸의 색(CI design 결정 3).
///
/// 앰버(`STATUS_ON`)를 재사용하지 않는다. `dumpStatus`가 띠 전체의
/// `STATUS_ON` · `STATUS_OFF` 픽셀을 `CAPS` 칸의 값으로 읽는데(IS-M1 plan
/// 확정 3), 여백 안에 앰버를 쓰는 둘째 칸이 생기면 그 전제가 조용히
/// 거짓이 된다 — copy mode 안에서 `CAPS`가 꺼져 있어도 `on`이 0이 아니게
/// 된다. 전용 색이면 `copy ink` 줄이 `COPY` 칸만 센다.
///
/// 여백과 `STATUS_FG`보다 밝다. 모드는 창틀이 아니라 지금 봐야 할 것이다.
/// 셀의 기본 전경(`0xFFFFFF`)과는 다른 값이다 — 상태 줄은 격자 밖이라
/// 섞일 일이 없지만, 같은 값을 피하는 쪽이 조사할 때 덜 헷갈린다.
const STATUS_COPY: u32 = 0x00E0E8F0;

/// 패널 사이 구분선의 색(WP design 결정 2).
///
/// 전용 색인 이유는 CI 결정 3과 같다. `dumpPane`이 프레임버퍼 전체에서 이
/// 색의 픽셀을 세어 `sep ink=`로 찍는데, 다른 무엇이 같은 색을 쓰면 "구분선이
/// 그 자리에 그려졌다"는 판정이 조용히 거짓이 된다. 여백(`MARGIN_COLOR`
/// 0x102030)보다 밝아 눈에 보이되 상태 줄 색 셋(`STATUS_FG` · `STATUS_ON` ·
/// `STATUS_OFF`)과 다르다.
///
/// 픽셀 한 줄이 아니라 셀 한 칸이다. 폭 2 글자의 spacer 규칙과 셀 격자를
/// 흐리지 않으려면 구분선도 격자의 한 칸이어야 한다.
const SEPARATOR: u32 = 0x00405060;

/// 한 셀의 배경을 칠한다. 글리프보다 먼저 전부 칠해야 한다
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

/// 사각형 하나를 한 색으로 칠한다. bar · underline 커서의 띠가 이것이다
/// (CU design 결정 3).
///
/// `setPixel`에 범위 검사가 없다. 여기서도 안 본다 — 부르는 자리가 넘기는
/// 사각형은 `vt.Screen.cursorMark()`의 것이고, 그쪽이 칸 수(`cols`)를 격자
/// 안으로 자르므로 패널 밖으로 안 나간다.
fn fillRect(fb: drm.Framebuffer, x: u32, y: u32, w: u32, h: u32, color: u32) void {
    var row: u32 = 0;
    while (row < h) : (row += 1) {
        var col: u32 = 0;
        while (col < w) : (col += 1) {
            fb.setPixel(x + col, y + row, color);
        }
    }
}

/// 알파 블렌딩을 하지 않고 문턱값으로 찍는다(design 결정 4).
///
/// TR-M1에서 이 선택의 근거가 짐작에서 실측으로 바뀌었다. 이 폰트의
/// coverage는 0 아니면 255뿐이고 그 사이 값이 하나도 없다. unifont는
/// 16x16 격자를 그대로 담은 비트맵 폰트이고 unitsPerEm이 64라 16px에서
/// scale이 정확히 0.25다 — 안티앨리어싱이 아예 일어나지 않는다. 그래서
/// 게이트의 픽셀 검사가 정확한 상수와 비교할 수 있다.
///
/// 글리프의 오프셋을 반영한다. stb가 주는 비트맵은 글자를 감싸는 최소
/// 사각형이라, 셀 모서리에 그대로 찍으면 'A'와 'g'의 baseline이 어긋나고
/// 한글이 라틴보다 위로 솟는다. `Glyph`가 들고 있는 두 오프셋은 굽는
/// 자리에서 이미 셀 기준으로 바뀌어 있으므로 여기서는 더하기만 한다.
///
/// 좌표를 부호 있는 수로 계산하고 범위를 검사한다. `setPixel`이 검사를
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

/// 프롬프트가 그려진 결과(SH-M2). 게이트가 이 값으로 판정한다.
///
/// `cols`는 마지막으로 쓴 다음 칸이다 — `/가`가 3이면 폭 2를 안 것이고
/// 4면 바이트를 센 것이라, 정수 하나가 SH design 결정 9를 통째로 본다.
///
/// `x0`·`x1`은 반전 구간의 픽셀 범위다. 조합 중이 아니면 둘이 같다.
/// 그린 함수가 자기가 칠한 범위를 그대로 돌려주는 것이 요점이다 —
/// `dumpStatus`처럼 산수를 다시 하면 어긋났을 때 언제나 0이 나오고 증상이
/// "안 그렸다"와 구별되지 않는다(IS-M0 실측의 경고).
const PromptInk = struct {
    cols: u32,
    x0: u32,
    x1: u32,
    y: u32,
};

/// 프롬프트 오버레이(CN-M1 design 결정 7). 격자를 다 그린 뒤 마지막 줄만
/// 덮는다.
///
/// `render`가 `present()`로 끝나므로 반드시 그 안에서, present 앞에 그려야
/// 한다. 밖에서 그리면 다음 프레임까지 화면에 안 나온다.
///
/// 줄 전체를 먼저 배경색으로 지운다. 안 지우면 검색어가 짧아졌을 때 지난
/// 프레임의 꼬리가 오른쪽에 남는다 — Backspace를 눌렀는데 글자가 안 지워지는
/// 것처럼 보인다.
///
/// 검색어는 반전하지 않는다(CN-M1 plan 결정 6). 선택도 copy 커서도 "색
/// 둘을 맞바꾼다"로 나타나므로, 프롬프트까지 반전하면 화면 맨 아래의 흰 띠가
/// 선택인지 프롬프트인지 갈리지 않는다. 앞의 `/` 한 글자가 그 표시다.
///
/// 조합 중인 글자 하나만 반전한다(SH design 결정 2). 위 문단과 어긋나지
/// 않는다 — 저기서 말한 것은 줄 전체이고 이것은 글자 하나다. 그리고
/// 그 하나는 "아직 검색어가 아닌 것"이라 표시가 필요하다. 격자 안의 preedit이
/// 이미 같은 규칙을 쓴다.
///
/// `drawRun`을 재사용한다(SH design 결정 9). IS-M1이 상태 줄의 색을 칸마다
/// 가르려고 "한 토막을 한 색으로 그리고 다음 col을 돌려준다"는 모양으로
/// 만들었는데, 프롬프트의 반전 구간이 정확히 그 모양을 필요로 한다.
/// 바이트 하나를 글자 하나로 세던 옛 코드가 이 재사용으로 사라진다 —
/// IS design이 주석에 미리 적어 둔 함정이었다.
fn drawPrompt(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    p: Prompt,
) !PromptInk {
    if (p.rect.rows == 0) return .{ .cols = 0, .x0 = 0, .x1 = 0, .y = 0 };
    const o = paneOrigin(p.rect);
    const y = o.y + @as(u32, p.rect.rows - 1) * ROW_HEIGHT;

    var col: u32 = 0;
    while (col < p.rect.cols) : (col += 1) {
        drawCellBackground(fb, o.x + col * CELL_W, y, p.bg);
    }

    // 패널 오른쪽 끝에서 끊는다. needle은 128바이트까지 자라는데 격자는
    // 100칸 남짓이라, 안 끊으면 검색어가 여백으로 삐져나온다.
    //
    // `drawRun`의 col은 격자 기준이라 패널의 `rect.col`에서 시작하고, 돌아온
    // 값에서 그것을 빼 패널 기준으로 되돌린다(WP design 결정 6). `cols=`
    // 로그가 패널 기준이어야 패널 하나일 때 지금과 같은 값이다.
    const max_x = o.x + @as(u32, p.rect.cols) * CELL_W;
    col = try drawRun(fb, cache, p.text, y, p.fg, p.rect.col, max_x) - p.rect.col;

    const cp = p.edit orelse return .{ .cols = col, .x0 = 0, .x1 = 0, .y = y };

    // 조합 중인 글자는 색을 맞바꿔 그린다. 배경을 글자색으로 칠하고 획을
    // 배경색으로 찍는다 — 격자 안의 커서·선택이 쓰는 규칙 그대로다.
    //
    // 두 칸을 칠해야 한다. `drawGlyph`는 16픽셀을 첫 셀의 색 하나로
    // 찍으므로, 한 칸만 반전하면 글자의 오른쪽 절반이 어두운 바탕에 어두운
    // 색으로 그려져 사라진다(HI-M1 실측 3 · 2026-09-02의 사고와 같은
    // 메커니즘이다).
    const glyph = try cache.find(cp);
    const span = @max(1, glyph.cell_width / CELL_W);
    const x0 = o.x + col * CELL_W;
    var i: u32 = 0;
    while (i < span and col + i < p.rect.cols) : (i += 1) {
        drawCellBackground(fb, o.x + (col + i) * CELL_W, y, p.fg);
    }
    drawGlyph(fb, glyph, x0, y, p.bg);
    // `span`이 아니라 `i`로 x1을 센다. 칸이 모자라 덜 칠했으면 덜 칠한
    // 만큼만 세야 판정이 실제 픽셀과 맞는다.
    return .{ .cols = col + span, .x0 = x0, .x1 = x0 + i * CELL_W, .y = y };
}

/// 입력기 상태 줄(IS design 결정 6). 격자 바깥의 아래 여백에 그린다 —
/// 터미널 줄을 한 줄도 안 뺏는다.
///
/// ```
/// 격자 아래 끝 = GRID_Y + rows * ROW_HEIGHT = 20 + 47*16 = 772
/// 아래 여백    = fb.height - 772            = 28
/// 글자 줄의 y  = 772 + (28 - 16) / 2        = 778
/// ```
///
/// `drawPrompt`를 재사용할 수 없다. 그쪽은 `for (text) |ch|`로 바이트
/// 하나를 글자 하나로 세는데(검색 needle이 지금 ASCII뿐이라 여태 안
/// 드러났다), 이 줄에는 `한`처럼 UTF-8 세 바이트짜리 글자가 들어간다. 그대로
/// 두면 글리프 셋이 그려지고 뒤 칸이 전부 두 칸씩 밀린다.
///
/// 폭 2 글자는 두 칸을 전진한다. `render()`가 격자에서 col을 쓰는 것과
/// 같은 규칙인데, 거기는 라이브러리가 spacer 셀로 col을 미리 맞춰 줬고
/// (TF-M2) 여기는 우리가 센다.
///
/// 여백이 한 줄보다 좁으면 아무것도 안 그린다. 높이가 다른 화면에서는
/// `rows`가 여백을 다 먹을 수 있는데, 그때 그리면 격자 바깥이 아니라 화면
/// 밖에 쓴다 — `setPixel`은 범위를 검사하지 않는다(`drm.zig:149`).
///
/// 띠를 따로 안 지운다. `render()`가 매 프레임 `fill(MARGIN_COLOR)`로
/// 시작하므로 지난 프레임의 꼬리가 남을 수 없다. `drawPrompt`가 줄 전체를
/// 먼저 칠해야 했던 것은 그쪽이 격자 안이라 `fill` 뒤에 셀 배경이 다시
/// 덮이기 때문이고, 여백은 그 덮임이 없다.
fn drawStatus(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    st: Status,
) !void {
    const grid_bottom = GRID_Y + @as(u32, st.rows) * ROW_HEIGHT;
    if (fb.height < grid_bottom + ROW_HEIGHT) return;
    const y = grid_bottom + (fb.height - grid_bottom - ROW_HEIGHT) / 2;

    // 꼬리가 `CAPS` 칸이고, copy mode면 그 뒤에 `COPY_TAIL`이 더 붙어
    // 있다(CI-M0). 길이를 4나 6으로 여기 다시 적지 않고 `status`의 이름에서
    // 얻는다 — 이름을 고치는 사람이 이 파일을 안 고쳐도 되게.
    // `statusText`가 언제나 그 순서로 끝내므로 이 자름은 항상 맞는다.
    //
    // `st.copy`를 안 보고 `CAPS.len`만 물러나면 copy mode 안에서 `CAPS`가
    // 회색으로, `COPY`가 `CAPS`의 색으로 그려진다 — 색이 한 칸 밀리는데
    // 글자는 맞아서 `text=`로는 안 보인다(CI design 위험 2). 그것을 잡는
    // 것이 copy 체인의 `copy ink>0`이다.
    //
    // WP-M2부터 꼬리가 둘이다 — `… CAPS[  W2][  COPY]`(WP-M2 plan 확정 1).
    // 워크스페이스 칸도 같은 이유로 `st.workspace`를 보고 물러난다. 안 보면
    // 워크스페이스가 둘일 때 `CAPS`가 `STATUS_FG`로, `  W2`의 앞 두 글자가
    // `CAPS`의 색으로 그려지고 hangul 체인의 `caps ink`가 틀린다.
    const copy_len = if (st.copy) status.COPY_TAIL.len else 0;
    const ws_len: usize = if (st.workspace != null) status.WS_TAIL_LEN else 0;
    if (st.text.len < status.CAPS.len + ws_len + copy_len) return;
    const copy_at = st.text.len - copy_len;
    const ws_at = copy_at - ws_len;
    const caps_at = ws_at - status.CAPS.len;

    // 네 번 나눠 그린다(WP-M2 전에는 셋). 색이 칸마다 다르다고 해서 인덱스를 세며 한 번에
    // 그리면 바이트 위치와 col을 동시에 굴려야 하고, 폭 2 글자에서 어긋나기
    // 쉽다 — 그 어긋남은 "글자가 겹쳐 보인다"로 나타나 원인에서 멀다.
    // 상태 줄의 경계는 화면 끝이다. 격자 바깥의 여백에 그리므로 격자
    // 오른쪽 끝에 맞출 이유가 없다 — 프롬프트와 갈리는 자리다.
    var col = try drawRun(fb, cache, st.text[0..caps_at], y, STATUS_FG, 0, fb.width);
    col = try drawRun(
        fb,
        cache,
        st.text[caps_at..ws_at],
        y,
        if (st.caps) STATUS_ON else STATUS_OFF,
        col,
        fb.width,
    );
    // 워크스페이스 칸은 앞 세 칸과 같은 색이다(WP design 결정 8). 켜고
    // 꺼지는 것이 아니라 자리를 말하는 칸이라 모드의 색(`STATUS_COPY`)이나
    // 잠금의 색(`STATUS_ON`)을 안 쓴다. 하나뿐이면 빈 슬라이스다.
    col = try drawRun(fb, cache, st.text[ws_at..copy_at], y, STATUS_FG, col, fb.width);
    // copy mode가 아니면 빈 슬라이스라 아무것도 안 그리고 col만 돌려준다.
    _ = try drawRun(fb, cache, st.text[copy_at..], y, STATUS_COPY, col, fb.width);
}

/// 상태 줄의 한 토막을 `start_col`부터 한 색으로 그리고, 다음 칸의 col을
/// 돌려준다.
///
/// `drawStatus`가 이것을 두 번 부른다 — 앞 세 칸은 `STATUS_FG`로, 꼬리의
/// `CAPS`는 잠금 상태에 따라 `STATUS_ON`이나 `STATUS_OFF`로.
///
/// `drawPrompt`를 재사용하지 않는 이유가 이 함수의 두 줄에 있다
/// (design 결정 6). 그쪽은 바이트 하나를 글자 하나로 세므로 `한`이 글리프
/// 셋으로 그려진다. 여기는 UTF-8을 디코드하고, 폭 2 글자는 두 칸을 전진한다.
fn drawRun(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    text: []const u8,
    y: u32,
    fg: u32,
    start_col: u32,
    /// 이 x를 넘어가는 글자는 안 그린다(SH-M2). 아래 주석에 근거가 있다.
    max_x: u32,
) !u32 {
    // `statusText`가 만든 문자열이라 UTF-8이 깨질 수 없다. 그래도 catch로
    // 받는 것은, 깨졌을 때 터미널이 죽는 대신 상태 줄만 사라지는 쪽이
    // 낫기 때문이다 — `pushCommit`이 인코딩 실패에 대해 고른 것과 같은 판단이다.
    var view = std.unicode.Utf8View.init(text) catch return start_col;
    var it = view.iterator();
    var col = start_col;
    while (it.nextCodepoint()) |cp| {
        const glyph = try cache.find(cp);
        // 부르는 쪽이 정한 경계에서 멈춘다(SH-M2). `setPixel`은 범위를
        // 검사하지 않으므로(`drm.zig:149`) 멈추지 않으면 프레임버퍼 밖에 쓴다.
        //
        // 경계를 인자로 받는 이유는 둘이 다르기 때문이다. 상태 줄은 격자
        // 바깥이라 화면 끝(`fb.width`)이 경계이고, 프롬프트는 격자의 마지막
        // 줄이라 격자 오른쪽 끝이 경계다 — 여백으로 삐져나오면 검색어가
        // 터미널 밖에 그려진다. needle은 128바이트까지 자라는데 격자는
        // 100칸 남짓이라 실제로 닿는 경계다.
        if (GRID_X + col * CELL_W + glyph.cell_width > max_x) break;
        drawGlyph(fb, glyph, GRID_X + col * CELL_W, y, fg);
        // `@max`로 0을 막는다. 폭 0인 글리프가 오면 col이 안 늘어 다음
        // 글자가 같은 자리에 겹쳐 그려지고, 증상이 "글자 하나가 뭉갠 것처럼
        // 보인다"라 원인에서 멀다.
        col += @max(1, glyph.cell_width / CELL_W);
    }
    return col;
}

/// 화면 전체를 지우고 셀 목록을 다시 그린다. 키 입력 빈도에서 부분 갱신은
/// 불필요한 복잡도다(YAGNI) — `RenderState`가 dirty를 주지만 쓰지 않는다.
///
/// 한 프레임이 세 단계다(WP-M1). `renderBackdrop` → 패널마다 `renderPane`
/// → `renderFinish`. 패널 하나를 그리는 일이 둘째이고, WP 전의 `render`
/// 본문이 거의 그대로 그 안에 있다.
///
/// 하나의 함수로 안 묶은 이유는 그리는 순서와 계산하는 순서가 엇갈리기
/// 때문이다. 포커스 패널을 마지막에 그려야 덤프 넷이 읽는 `cell_buf` ·
/// `img_buf`가 포커스 패널의 것으로 남는데, 프롬프트는 포커스 패널의
/// `cells()` 뒤에야 만들 수 있다(`defaultFg`가 그 갱신을 본다). 그래서
/// 순서는 `main`의 루프가 잡는다.
///
/// 이 단계는 여백을 칠하고 구분선을 긋는다. 패널 안은 다음 단계가 셀마다
/// 덮는다.
///
/// 구분선을 따로 긋는 이유는 WP-M1 plan 확정 4다 — `cells()`가 빈 셀을 안
/// 내보내므로 격자를 통째로 구분선 색으로 칠하면 패널 안 빈 칸이 그 색으로
/// 남는다.
fn renderBackdrop(fb: drm.Framebuffer, tree: *const layout.Tree, whole: layout.Rect) void {
    fb.fill(MARGIN_COLOR);
    var buf: [layout.MAX_LEAVES - 1]layout.Rect = undefined;
    for (tree.separators(whole, &buf)) |sep| {
        const o = paneOrigin(sep);
        var row: u32 = 0;
        while (row < sep.rows) : (row += 1) {
            var col: u32 = 0;
            while (col < sep.cols) : (col += 1) {
                drawCellBackground(fb, o.x + col * CELL_W, o.y + row * ROW_HEIGHT, SEPARATOR);
            }
        }
    }
}

/// 패널 하나를 그린다. 배경 · 이미지 · 글리프의 층 순서가 여기 있다.
///
/// 두 벌로 나눠 그린다(design 결정 6). 배경을 전부 칠하고 나서 글리프를
/// 전부 그린다. 섞으면 다음 셀의 배경이 앞 글자의 삐져나온 획을 지운다.
/// `cache`가 `*font.Cache`인 이유는 TR-M1부터 그리는 도중에 글자를 굽기
/// 때문이다. 캐시에 없는 글자가 화면에 나타나면 그 자리에서 래스터라이징이
/// 일어난다 — 한 자당 밀리초 이하이고 같은 글자는 한 번뿐이다.
fn renderPane(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    cells: []const vt.CellGlyph,
    // kitty 이미지(TG-M2). z 순이고 패널 기준 좌표다. `default_bg`는 아래
    // 투명 배경 규칙에 쓴다.
    imgs: []const vt.ImagePlacement,
    default_bg: u32,
    // 이 패널이 격자 안에서 차지하는 사각형(WP design 결정 6). 셀 좌표에
    // 이 원점을 더해 그리고, 이미지는 이 사각형 밖에 안 그린다 — 그래서
    // `clip`을 따로 받지 않고 여기서 계산한다. 패널 하나면 격자 전체라
    // 산수 결과가 WP 전과 같다.
    rect: layout.Rect,
    // 이 패널의 셸 커서(CU design 결정 3). 그 화면의 `cells()` 뒤에
    // `cursorMark()`로 얻은 값이다. null이면 띠를 안 칠한다 — copy mode ·
    // 포커스 없음 · 뷰포트 밖이고, block도 `px`가 null이라 여기서는 아무
    // 일도 안 한다(반전은 `cells()`가 이미 했다).
    cursor: ?vt.CursorMark,
) !void {
    const o = paneOrigin(rect);
    const clip = paneClip(rect);

    // 층 순서는 TG design 결정 4다 — 배경 아래 · 셀 배경 · 글자 아래 · 글리프 ·
    // 글자 위. 이미지가 없는 프레임에서 세 호출은 빈 슬라이스를 돌고 끝난다.
    drawImages(fb, imgs, .below_bg, o, clip);

    // x를 글리프 폭으로 누적하지 않고 col로 계산하는 것이 중요하다.
    // libghostty-vt는 한글 같은 폭 2칸 문자 뒤에 spacer 셀을 넣어 col을
    // 이미 맞춰두기 때문에(TF-M2에서 '이'의 col이 6이 아니라 7이었던
    // 그 성질), col*CELL_W가 곧 정확한 픽셀 위치다.
    for (cells) |cell| {
        const x = o.x + @as(u32, cell.col) * CELL_W;
        const y = o.y + @as(u32, cell.row) * ROW_HEIGHT;
        // 기본 배경은 `below_bg` 이미지 위에서 투명하다(TG-M2 plan 정한 것 2).
        // `cells()`는 글자가 있는 셀을 기본 배경이어도 내보내므로, 그대로
        // 칠하면 배경 아래 이미지가 글자 셀마다 덮인다.
        if (cell.bg == default_bg and overBelowBg(imgs, o, x, y)) continue;
        drawCellBackground(fb, x, y, cell.bg);
    }

    drawImages(fb, imgs, .below_text, o, clip);

    for (cells) |cell| {
        // 빈 셀은 배경만 칠하고 끝난다. 캐시에 codepoint 0을 넣지 않기
        // 위해서이기도 하다 — 커서 자리와 색 띠가 전부 이쪽이라 흔하다.
        if (cell.codepoint == 0) continue;
        const x = o.x + @as(u32, cell.col) * CELL_W;
        const y = o.y + @as(u32, cell.row) * ROW_HEIGHT;
        const glyph = try cache.find(cell.codepoint);
        drawGlyph(fb, glyph, x, y, cell.fg);
    }

    drawImages(fb, imgs, .above_text, o, clip);

    // 커서는 무엇에도 안 가려진다(CU design 결정 3). 그래서 글자 위 이미지
    // 뒤, 이 함수의 맨 끝이다. 띠는 그 칸의 글리프 위에 그려져 글자의
    // 왼쪽(bar) 또는 아래(underline) 2픽셀을 덮는다 — ghostty 앱 렌더러도
    // 같다. block은 `cells()`가 이미 반전으로 그렸고 `px`가 null이다.
    if (cursor) |cm| if (cm.px) |cr| fillRect(fb, o.x + cr.x, o.y + cr.y, cr.w, cr.h, vt.CURSOR_COLOR);
}

/// 프레임을 끝낸다 — 포커스 패널의 프롬프트와 상태 줄을 얹고 내보낸다.
fn renderFinish(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    prompt: ?Prompt,
    // 이름이 `status`가 아니다. 이 파일이 `status.zig`를 그 이름으로
    // import하는데 Zig는 안쪽 블록에서도 이름 가리기를 막는다
    // (HI-M1 실측 8 · SP-M0 실측 9와 같은 자리).
    st: Status,
) !?PromptInk {
    // 그린 결과를 돌려준다(SH-M2). 게이트가 "무엇을 그렸는가"를 볼 창구가
    // 이것이고, 반전 구간의 픽셀 범위를 여기서 나르므로 `dumpPromptInk`가
    // 같은 산수를 다시 하지 않는다.
    var ink: ?PromptInk = null;
    if (prompt) |p| ink = try drawPrompt(fb, cache, p);

    // 프롬프트와 안 겹친다 — 프롬프트는 격자의 마지막 줄이고 이것은 격자
    // 바깥이다. 그래서 순서에 뜻이 없고, `present` 앞이라는 것만 중요하다.
    try drawStatus(fb, cache, st);

    try fb.present();
    return ink;
}

/// 한 층의 이미지를 z 순으로 그린다. 산수는 전부 `image.zig`에 있다.
/// placement의 좌표는 패널 기준이라 패널 원점 `o`를 더한다.
fn drawImages(fb: drm.Framebuffer, imgs: []const vt.ImagePlacement, layer: vt.ImageLayer, o: Origin, clip: image.Clip) void {
    for (imgs) |p| {
        if (p.layer == layer) image.draw(fb, p, @intCast(o.x), @intCast(o.y), clip);
    }
}

/// 셀 `(x, y)`(프레임버퍼 좌표)가 `below_bg` 이미지 하나와라도 겹치는가.
/// 이미지 좌표는 패널 기준이라 패널 원점 `o`를 더한다.
fn overBelowBg(imgs: []const vt.ImagePlacement, o: Origin, x: u32, y: u32) bool {
    for (imgs) |p| {
        if (p.layer != .below_bg) continue;
        const left = @as(i64, o.x) + p.dst_x;
        const top = @as(i64, o.y) + p.dst_y;
        if (x + CELL_W > left and x < left + p.dst_w and
            y + ROW_HEIGHT > top and y < top + p.dst_h) return true;
    }
    return false;
}

/// 오버레이 한 줄에 필요한 것 전부.
///
/// 인자를 일곱 개 늘어놓지 않고 묶는 이유는 호출부가 하나뿐이기 때문이다.
/// 늘어놓으면 `rows`와 `cols`, `fg`와 `bg`를 뒤바꿔 넣어도 컴파일이 통과한다.
const Prompt = struct {
    text: []const u8,
    /// 조합 중인 글자(SH-M2, design 결정 2). 프롬프트가 열려 있을 때만
    /// 있다 — 닫힌 뒤의 오버레이(`/needle [3/12]`)에는 조합이 붙지 않는다.
    ///
    /// `text`에 안 붙인 것이 SH-M2 plan의 결정이다. 붙이면 "어디부터
    /// 반전인가"를 바이트 오프셋으로 함께 날라야 하고, 그 둘이 어긋나면
    /// 반전이 한 글자 밀린다. 조합 중인 글자는 언제나 하나라 코드포인트
    /// 하나면 충분하다.
    edit: ?u21,
    /// 포커스 패널의 사각형(WP design 결정 6). 오버레이는 격자가 아니라
    /// 이 패널의 마지막 줄이고, 폭도 이 패널의 것이다.
    rect: layout.Rect,
    fg: u32,
    bg: u32,
};

/// 상태 줄 한 줄에 필요한 것 전부. `Prompt`와 같은 이유로 묶는다 —
/// 호출부가 하나뿐이고, 늘어놓으면 `rows`를 다른 `u16`과 뒤바꿔 넣어도
/// 컴파일이 통과한다.
///
/// `Prompt`와 달리 optional이 아니다. 상태 줄은 언제나 뜬다(결정 2).
const Status = struct {
    text: []const u8,
    rows: u16,
    /// 대문자 잠금이 켜져 있는가(IS-M1).
    ///
    /// `text`에는 안 들어 있다. `CAPS` 넉 자는 언제나 그대로이고 이 값은
    /// 색만 고른다(design 결정 3) — 그래서 `statusText`가 아니라 여기서
    /// 따로 나른다.
    caps: bool,
    /// copy mode에 있는가(CI-M0).
    ///
    /// `text`에 이미 들어 있다 — `statusText`가 이 값으로 꼬리에 `COPY`를
    /// 붙인다. 그래도 따로 나르는 이유는 `drawStatus`가 `CAPS` 칸의 시작을
    /// 꼬리에서 세기 때문이다. 문자열을 되읽어 `COPY`로 끝나는지 보는
    /// 쪽은 자판 이름에 그 넉 자가 들어오는 날 조용히 틀린다.
    copy: bool,
    /// 지금 워크스페이스의 번호(1~9). 하나뿐이면 null이다(WP-M2).
    ///
    /// `copy`와 같은 이유로 따로 나른다 — `text`에 이미 들어 있지만
    /// `drawStatus`가 꼬리에서 `CAPS`를 셀 때 이 칸의 길이를 알아야 한다.
    workspace: ?u8,
};

/// 오버레이 한 줄에 쓸 글자를 정한다. 갈래가 셋이다(SP design 결정 7).
///
/// ```
/// 프롬프트가 열려 있다        → /needle
/// 닫혀 있고 상태가 켜져 있다  → 매치 0이면  /needle: not found
///                               아니면      /needle [3/12]
/// 그 밖                       → null (오버레이를 아예 안 그린다)
/// ```
///
/// `drawPrompt`는 이것을 모른다. 그리는 함수는 "한 줄을 준 색으로 쓴다"
/// 하나만 알고, 무엇을 쓸지는 여기서 끝난다 — CN-M1이 앞의 `/`를 `vt.zig`가
/// 아니라 `main.zig`에서 붙인 것과 같은 경계다(모양은 여기가 정한다).
///
/// 프롬프트를 먼저 보는 것에 뜻이 있다. 검색을 마친 뒤에 `/`를 다시 열면
/// 사람이 지금 치고 있는 것이 화면에 나와야 한다. 순서를 뒤집으면 새 검색어를
/// 치는 동안 지난 결과가 화면에 남는다.
///
/// 두 갈래를 가르는 것은 `findMatchCount()` 하나다. `find_status`는 "방금
/// 검색했다"만 말하고 성패를 모른다 — `vt_test`의 검사 44가 그 갈림을 본다.
///
/// 번호는 라이브러리가 준 값을 그대로 쓴다(결정 6). `idx + 1`이고
/// `total - idx`로 뒤집지 않는다 — 뒤집으면 off-by-one이 들어갈 자리가 하나
/// 생기고, 그 증상은 "번호가 하나씩 어긋난다"라 조용하다.
///
/// `findCurrentIndex()`가 null이면 번호를 안 붙이고 needle만 쓴다
/// (design 위험 1). 매치는 있는데 선택이 없는 경로이고, 그때 0이나 1을
/// 지어내면 사람이 커서와 어긋난 번호를 보게 된다.
///
/// `buf`는 최소 173바이트여야 한다: `/` 하나 + needle 128 + ` [` 둘 +
/// 숫자 20 + `/` 하나 + 숫자 20 + `]` 하나. `usize`가 최대 스무 자리다.
fn promptText(screen: *vt.Screen, buf: []u8) ?[]const u8 {
    const MISS = ": not found";
    if (screen.findNeedle()) |n| {
        buf[0] = '/';
        @memcpy(buf[1 .. 1 + n.len], n);
        return buf[0 .. 1 + n.len];
    }

    const n = screen.findStatusNeedle() orelse return null;
    buf[0] = '/';
    @memcpy(buf[1 .. 1 + n.len], n);
    const len = 1 + n.len;

    const total = screen.findMatchCount();
    if (total == 0) {
        @memcpy(buf[len..][0..MISS.len], MISS);
        return buf[0 .. len + MISS.len];
    }

    const idx = screen.findCurrentIndex() orelse return buf[0..len];
    // `bufPrint`가 실패하면 needle만 남긴다. 위의 산수대로면 일어나지
    // 않지만, 버퍼 크기를 누가 줄였을 때 증상이 panic이 되지 않게 막는다.
    const tail = std.fmt.bufPrint(buf[len..], " [{d}/{d}]", .{ idx + 1, total }) catch
        return buf[0..len];
    return buf[0 .. len + tail.len];
}

/// 한 프레임에 찍는 style/pixel 줄의 상한. 화면 전체에 색이 깔린 프로그램이
/// 돌면 셀 수천 개가 매 프레임 로그로 쏟아진다.
///
/// SC-M0이 16에서 96으로 올렸다. 16은 "게이트가 검사에 쓰는 셀은 한 줄
/// 안의 몇 개라 넉넉하다"고 적고 고른 수였는데, 그 문장이 참이었던 이유는
/// 셸이 색을 하나도 안 썼기 때문이다 — `--no-config`로 뜬 fish는 구문
/// 강조를 안 해서 프롬프트도 명령줄도 기본 색이었고, 색이 있는 셀은 검사가
/// 만든 것뿐이었다.
///
/// 설정을 읽는 fish는 프롬프트를 칠하고 명령줄을 강조한다. 그러면 셀이
/// 순서대로 덤프되므로 화면 맨 위의 명령줄이 예산을 먼저 다 쓰고, 그 아래
/// 줄에 있는 프로그램 출력의 색이 잘린다 — `render/check.sh`가
/// `printf '\033[41m \033[0m\n'`의 빨강 배경을 영영 못 보게 된다(SC-M0 실측
/// 19(a)). 명령줄 하나가 32칸을 썼고, 한 줄은 최대 80칸이다.
///
/// 96은 색칠된 80칸 한 줄 + 검사가 보는 아래 줄들을 덮는 수다. 상한이
/// 있다는 성질은 그대로이고(`{d} more cell(s) not shown`이 잘린 것을 말한다),
/// 자르는 자리만 셸이 색을 쓰는 세상으로 옮겼다.
const STYLE_DUMP_LIMIT: usize = 96;

/// 검증용으로 화면 내용을 serial 콘솔에 한 줄로 덤프한다.
/// check.sh가 이 줄을 grep해서 "입력이 실제로 셸을 움직였는가"를 판단한다.
///
/// 이 줄의 형식은 바꾸지 않는다. 여섯 체인 중 다섯(TF·CP·IP·PM·HD)이
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
/// 반드시 render() 뒤에 불러야 한다. 그 전에 부르면 이전 프레임의
/// 픽셀을 읽는다.
fn dumpStyles(
    fb: drm.Framebuffer,
    cells: []const vt.CellGlyph,
    default_fg: u32,
    default_bg: u32,
    /// 프롬프트가 덮은 행. 없으면 null이다(CN-M1 plan 결정 4).
    overlaid_row: ?u16,
    /// 셀이 그려진 패널(WP design 결정 6). `render`와 같은 원점에서 읽어야
    /// 한다 — 안 받으면 패널 하나일 때만 맞는 값이 나온다. 찍는 좌표는
    /// 패널 기준 그대로다.
    rect: layout.Rect,
) void {
    const o = paneOrigin(rect);
    var shown: usize = 0;
    var skipped: usize = 0;
    var hidden: usize = 0;
    for (cells) |cell| {
        // 덮인 줄은 아예 건너뛴다. 이 함수가 두 줄을 찍는 것에 뜻이 있다 —
        // `style>`는 파서가 본 색이고 `pixel>`은 프레임버퍼에서 되읽은 값이며,
        // 둘이 어긋나면 렌더러가 틀렸다는 뜻이다(TR design 결정 7). 우리가 덮은
        // 줄에서는 그 전제가 깨진다: pixel>이 셀이 아니라 프롬프트를 말한다.
        //
        // 지금 이 줄을 보는 체인은 없지만(pixel>을 쓰는 것은 render 체인
        // 하나뿐이고 그 체인은 copy mode에 안 들어간다) 게이트가 못 보는
        // 부채를 새로 만들지 않는다.
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
        // 셀의 중앙을 읽는다. 모서리는 이웃 셀과의 경계라 off-by-one에
        // 취약하다.
        const px = o.x + @as(u32, cell.col) * CELL_W + CELL_W / 2;
        const py = o.y + @as(u32, cell.row) * ROW_HEIGHT + ROW_HEIGHT / 2;
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

/// 폭 2칸 글자가 정말 두 칸에 걸쳐 찍혔는지를 프레임버퍼에서 되읽어
/// 센다.
///
/// `style>`/`pixel>`이 색을 두 겹으로 보는 것과 같은 이유다(design 결정 7).
/// 한글은 "파서가 폭 2칸으로 셌는가"와 "렌더러가 두 칸을 칠했는가"가 따로
/// 틀릴 수 있다. 셀 하나만 보면 그 차이를 못 잡는다 — 글자가 왼쪽 반쪽만
/// 그려져도 그 셀에는 잉크가 있기 때문이다. 그래서 왼쪽 8픽셀과 오른쪽
/// 8픽셀을 따로 센다.
///
/// 반드시 render() 뒤에 불러야 한다. 그 전에 부르면 이전 프레임의
/// 픽셀을 읽는다.
/// `rect`는 셀이 그려진 패널이다 — `dumpStyles`와 같은 이유로 받는다
/// (WP design 결정 6).
fn dumpInk(fb: drm.Framebuffer, cache: *font.Cache, cells: []const vt.CellGlyph, rect: layout.Rect) void {
    const o = paneOrigin(rect);
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

        const x = o.x + @as(u32, cell.col) * CELL_W;
        const y = o.y + @as(u32, cell.row) * ROW_HEIGHT;
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

/// 셸 커서를 세 겹으로 찍는다(CU design 결정 6).
///
///   terminal: cursor> vt=bar drawn=bar row=46 col=14 cols=1 ink=32 box=2x16
///   terminal: cursor> vt=bar drawn=none
///
/// | 칸 | 어디서 오는가 | 무엇을 증명하나 |
/// |---|---|---|
/// | `vt=` | `cursorAsked()` — 라이브러리의 모양 | DECSCUSR이 해석됐다 |
/// | `drawn=` | `cursorMark().shape`, 없으면 `none` | 우리 우선순위(결정 4)가 그렇게 정했다 |
/// | `row=` `col=` `cols=` | `cursorMark()` | 띠가 칠해질 자리 |
/// | `ink=` `box=` | 프레임버퍼를 되읽은 값 | 렌더러가 그 모양을 실제로 칠했다 |
///
/// `ink`는 커서 칸들 안에서 `CURSOR_COLOR`인 픽셀의 수이고 `box`는 그
/// 픽셀들의 경계 사각형이다(없으면 `0x0`). 사각형을 `cursorMark()`의 `px`에서
/// 그대로 찍지 않고 픽셀을 되읽는 이유가 이 줄의 값이다 — `px`는 "칠하려던
/// 것"이지 "칠한 것"이 아니다. `style>`만 보면 렌더러가 틀려도 통과하는
/// 것과 같은 구멍이다(TR design 결정 7).
///
/// 매 프레임 찍는다. `find> hl`과 같은 이유다(CS-M0) — "바뀔 때만"이면 상태가
/// 하나 늘고, 그 판정이 틀렸을 때 증상이 "로그가 안 나온다"라 조사하기
/// 나쁘다. 되읽는 것은 커서 칸(최대 2 × 128픽셀)뿐이다.
///
/// 반드시 render() 뒤에 부른다. 그 전에 부르면 이전 프레임의 픽셀을 읽는다.
/// `screen`의 `cells()` 뒤이기도 해야 한다 — 두 접근자가 그 결과를 읽는다.
fn dumpCursor(fb: drm.Framebuffer, screen: *vt.Screen, rect: layout.Rect) void {
    const asked = @tagName(screen.cursorAsked());
    const cm = screen.cursorMark() orelse {
        std.debug.print("terminal: cursor> vt={s} drawn=none\n", .{asked});
        return;
    };
    const o = paneOrigin(rect);
    const x0 = o.x + @as(u32, cm.col) * CELL_W;
    const y0 = o.y + @as(u32, cm.row) * ROW_HEIGHT;
    const span_w = @as(u32, cm.cols) * CELL_W;

    var ink: u32 = 0;
    // 경계 사각형. 픽셀이 하나도 없으면 `ink`가 0이고 `0x0`을 찍는다.
    var min_x: u32 = std.math.maxInt(u32);
    var min_y: u32 = std.math.maxInt(u32);
    var max_x: u32 = 0;
    var max_y: u32 = 0;
    // `getPixel`도 범위 검사를 안 한다. `dumpInk`처럼 여기서 막는다. 그런
    // 배치는 `cursorMark()`가 안 만들지만, 조용히 건너뛰지 않고 줄에 적는다.
    const outside = x0 + span_w > fb.width or y0 + ROW_HEIGHT > fb.height;
    if (!outside) {
        var row: u32 = 0;
        while (row < ROW_HEIGHT) : (row += 1) {
            var col: u32 = 0;
            while (col < span_w) : (col += 1) {
                if (fb.getPixel(x0 + col, y0 + row) & 0x00FFFFFF != vt.CURSOR_COLOR) continue;
                ink += 1;
                min_x = @min(min_x, col);
                min_y = @min(min_y, row);
                max_x = @max(max_x, col);
                max_y = @max(max_y, row);
            }
        }
    }
    const box_w: u32 = if (ink == 0) 0 else max_x - min_x + 1;
    const box_h: u32 = if (ink == 0) 0 else max_y - min_y + 1;
    std.debug.print("terminal: cursor> vt={s} drawn={s} row={d} col={d} cols={d} ink={d} box={d}x{d}{s}\n", .{
        asked, @tagName(cm.shape), cm.row, cm.col, cm.cols, ink, box_w, box_h,
        if (outside) " (outside the framebuffer)" else "",
    });
}

/// 그린 kitty 이미지를 두 겹으로 찍는다(TG-M2 plan 정한 것 6).
///
///   terminal: image> id=1 layer=above_text dst=20,52 32x32 src=0,0 2x2 frame=1234us
///   terminal: imgpx> id=1 tl=FF0000 tr=00FF00 bl=0000FF br=FFFFFF
///
/// 앞 줄은 `vt.zig`가 낸 사각형이고(dst는 패널 원점을 더한 프레임버퍼
/// 좌표 — 패널 하나면 격자 원점이다), 뒷 줄은 그 사각형의 네 사분면 중심에서 실제로 읽은 픽셀이다.
/// `style>` / `pixel>`과 같은 구조다 — 앞의 것만 보면 "계산은 맞는데 안
/// 칠했다"를 못 잡는다. 사분면 중심이 격자 밖이면 `--`다.
///
/// `frame`은 그 프레임의 `render()` 전체 시간이다(TG design 위험 1). 이미지가
/// 없는 프레임에는 아무것도 안 찍는다.
///
/// 반드시 render() 뒤에 부른다 — 그 전에 부르면 이전 프레임을 읽는다.
fn dumpImages(fb: drm.Framebuffer, imgs: []const vt.ImagePlacement, dropped: usize, frame_us: i96, rect: layout.Rect) void {
    const o = paneOrigin(rect);
    const clip = paneClip(rect);
    for (imgs, 0..) |p, i| {
        if (i >= 4) break;
        const left = @as(i64, o.x) + p.dst_x;
        const top = @as(i64, o.y) + p.dst_y;
        std.debug.print("terminal: image> id={d} layer={s} dst={d},{d} {d}x{d} src={d},{d} {d}x{d} frame={d}us\n", .{
            p.image_id, @tagName(p.layer), left,  top,   p.dst_w, p.dst_h,
            p.src_x,    p.src_y,           p.src_w, p.src_h, frame_us,
        });
        var hex: [4][6]u8 = undefined;
        const corners = [4][2]i64{ .{ 1, 1 }, .{ 3, 1 }, .{ 1, 3 }, .{ 3, 3 } };
        for (corners, 0..) |q, k| {
            const x = left + @divTrunc(@as(i64, p.dst_w) * q[0], 4);
            const y = top + @divTrunc(@as(i64, p.dst_h) * q[1], 4);
            if (x < clip.x0 or x >= clip.x1 or y < clip.y0 or y >= clip.y1) {
                hex[k] = "------".*;
                continue;
            }
            const px = fb.getPixel(@intCast(x), @intCast(y)) & 0x00FFFFFF;
            _ = std.fmt.bufPrint(&hex[k], "{X:0>6}", .{px}) catch unreachable;
        }
        std.debug.print("terminal: imgpx> id={d} tl={s} tr={s} bl={s} br={s}\n", .{
            p.image_id, hex[0], hex[1], hex[2], hex[3],
        });
    }
    if (dropped > 0) std.debug.print("terminal: image> {d} placement(s) not drawn (buffer full)\n", .{dropped});
}

/// 뷰포트가 스크롤백의 어디에 있는지를 찍는다.
///
/// 게이트가 스크롤 위치를 볼 수 있는 유일한 창구다. 화면 덤프만으로는
/// "올라갔다"와 "출력이 달라졌다"를 가를 수 없다 — 같은 글자가 두 번 나오는
/// 화면이면 둘이 구분되지 않는다. 거꾸로 이 줄만 보면 뷰포트는 움직였는데
/// 화면은 그대로인 상태를 못 잡으므로, 게이트는 둘을 나란히 본다.
/// `style>`/`pixel>`이 색을 두 겹으로 보는 것과 같은 구조다(design 결정 7).
///
/// 매 프레임 찍는다. `font>`처럼 "바뀌었을 때만"으로 하면 게이트가
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
/// 게이트가 모드 안을 볼 수 있는 유일한 창구다. 화면만 보면 "모드에
/// 들어갔다"와 "아무 일도 안 일어났다"가 구분되지 않는다 — 모드에 들어가도
/// 화면에서 달라지는 것은 커서 반전 하나뿐이기 때문이다.
///
/// 문구가 이 파일과 `copy/check.sh` 양쪽에 중복된다(design 결정 8). 기존
/// 체인들과 같은 구조이고, 한쪽을 고치면 다른 쪽도 고쳐야 한다.
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
/// 게이트가 프롬프트를 볼 수 있는 유일한 창구다. 프롬프트는 오버레이라
/// `cells()`의 결과에 안 섞이고(design 결정 7), 그래서 `terminal: screen>` 줄에
/// 절대 안 나타난다. 그 격리가 다섯 체인의 화면 판정을 지키는 대신 관측 수단을
/// 하나 없앤다 — 이 줄이 그 자리를 메운다.
///
/// `screen>`의 형식을 안 바꾸는 것이 이 설계 전체의 이유다. 프롬프트를 셀에
/// 섞었다면 로그 한 줄로 끝났겠지만, 그 줄을 보던 체인 다섯이 전부 흔들린다.
///
/// 문구가 이 파일과 `copy/check.sh` 양쪽에 중복된다(design 결정 8).
/// 한쪽을 고치면 다른 쪽도 고쳐야 한다.
fn dumpFind(screen: *vt.Screen, what: []const u8) void {
    if (screen.findNeedle()) |n| {
        std.debug.print("terminal: find> {s} needle={s} len={d}\n", .{ what, n, n.len });
    } else {
        // 프롬프트가 닫힌 뒤다. cancel과 submit이 여기로 온다.
        std.debug.print("terminal: find> {s}\n", .{what});
    }
}

/// 오버레이 한 줄에 무엇이 쓰였는지(CS-M1 plan 결정 3). 없으면 한 줄도 안
/// 찍는다.
///
/// 이 줄이 유일한 관측 수단이다. 오버레이는 `cells()`에 안 섞이므로
/// `screen>`에 영영 안 나오고, `dumpStyles`는 덮인 줄을 통째로 건너뛴다
/// (`overlaid_row`). 그래서 이 줄이 없으면 게이트가 "화면에 그렇게 쓰였다"를
/// 볼 창구가 하나도 없다 — `find> submit matches=0`은 "검색이 못 찾았다"까지만
/// 말한다.
///
/// `render()`에 넘어간 바로 그 값을 받는다. 문자열을 여기서 다시 만들지
/// 않는 이유는, 다시 만들면 그리는 것과 찍는 것이 갈릴 수 있기 때문이다.
///
/// `find> hl`과 같이 매 프레임 찍는다. "바뀔 때만"은 상태를 하나 더 만들고
/// 그 판정이 틀리면 증상이 "로그가 안 나온다"라 조사하기 나쁘다.
///
/// 문구가 이 파일과 `copy/check.sh` 양쪽에 중복된다.
/// 한쪽을 고치면 다른 쪽도 고쳐야 한다.
/// 한글 입력기의 상태를 한 줄로 찍는다(HI-M1). 게이트가 "한/영이 바뀌었다"와
/// "지금 이 글자를 조합 중이다"를 볼 수 있는 유일한 줄이다.
///
/// `screen>`만 보면 갈리지 않는 것이 있다. 조합 중인 글자는 셸이 되울린
/// 글자와 화면에서 똑같이 생겼으므로, `screen>`에 `가`가 있는 것만으로는
/// "아직 조합 중"과 "이미 셸에 갔다"를 못 가른다. CS-M1이 오버레이 내용을
/// 볼 창구가 없어서 `find> overlay`를 새로 만든 것과 같은 자리다.
///
/// 조합 중이 아닐 때 `(none)`이라고 쓰는 이유는 빈 문자열이면 줄 끝이
/// `preedit=`으로 끝나서, 로그가 잘린 것인지 값이 없는 것인지 갈리지 않기
/// 때문이다.
fn dumpHangul(state: *const input.State) void {
    var utf8: [4]u8 = undefined;
    const len: usize = if (state.preedit()) |cp|
        std.unicode.utf8Encode(cp, &utf8) catch 0
    else
        0;
    const text: []const u8 = if (len == 0) "(none)" else utf8[0..len];
    std.debug.print("terminal: hangul> on={} preedit={s}\n", .{
        state.hangul_on, text,
    });
}

fn dumpOverlay(prompt: ?Prompt) void {
    const p = prompt orelse return;
    // 조합 중인 글자를 함께 찍는다(SH-M2). `text=`만 보면 "조합이 아직
    // 검색어가 아니다"를 게이트가 볼 창구가 없다.
    //
    // `(none)`이라고 쓰는 이유는 `dumpHangul`과 같다 — 빈 문자열이면 줄이
    // 잘린 것인지 값이 없는 것인지 갈리지 않는다.
    var utf8: [4]u8 = undefined;
    const len: usize = if (p.edit) |cp|
        std.unicode.utf8Encode(cp, &utf8) catch 0
    else
        0;
    const edit: []const u8 = if (len == 0) "(none)" else utf8[0..len];
    std.debug.print("terminal: find> overlay text={s} preedit={s}\n", .{ p.text, edit });
}

/// 프롬프트가 실제로 그린 것을 픽셀로 센다(SH-M2).
///
/// 판정 셋이 한 줄에 있다.
///   `cols` — 그린 칸 수. `/가`가 3이면 폭 2를 안 것이고 4면 바이트를 센 것이다
///   `inv`  — 반전 구간에서 글자색인 픽셀. 배경이 뒤집혔다는 증거
///   `ink`  — 반전 구간에서 배경색인 픽셀. 그 위에 글자를 그렸다는 증거
///
/// `inv`만 보면 사각형만 칠한 구현도 통과한다. IS-M1이 `CAPS` 칸에서
/// `on`과 `off`를 한 줄에 함께 찍은 것과 같은 이유다.
///
/// 범위를 여기서 다시 계산하지 않는다. `drawPrompt`가 자기가 칠한 픽셀
/// 범위를 그대로 돌려준다 — `dumpStatus`가 `drawStatus`의 y 산수를 다시 해야
/// 했던 자리와 갈리는 지점이고, 어긋나면 언제나 0이 나오는 그 함정을 아예
/// 안 만든다.
///
/// 반드시 `render()` 뒤에 부른다 — 그 전에 부르면 이전 프레임을 읽는다.
///
/// 문구가 이 파일과 `hangul/check.sh` 양쪽에 중복된다.
/// 한쪽을 고치면 다른 쪽도 고쳐야 한다.
fn dumpPromptInk(fb: drm.Framebuffer, ink: ?PromptInk, prompt: ?Prompt) void {
    const k = ink orelse return;
    const p = prompt orelse return;
    var inv: usize = 0;
    var glyph_ink: usize = 0;
    var x = k.x0;
    while (x < k.x1) : (x += 1) {
        var row: u32 = 0;
        while (row < ROW_HEIGHT) : (row += 1) {
            const px = fb.getPixel(x, k.y + row) & 0x00FFFFFF;
            if (px == (p.fg & 0x00FFFFFF)) inv += 1;
            if (px == (p.bg & 0x00FFFFFF)) glyph_ink += 1;
        }
    }
    std.debug.print("terminal: find> ink cols={d} inv={d} ink={d}\n", .{
        k.cols, inv, glyph_ink,
    });
}

/// 입력기 상태 줄을 시리얼에 찍는다(IS-M0). 값이 바뀌었을 때만 찍는다.
///
/// RC-M0 실측 7이 시리얼 한 줄에 0.6~8.8밀리초라고 쟀다. 프레임이 21
/// 밀리초인데 두 줄을 매 프레임 찍으면 최악 18밀리초가 붙는다. 덤으로 로그가
/// 읽기 좋아진다 — 한 줄이 곧 한 번의 전환이다.
///
/// 첫 프레임은 반드시 찍힌다(`last_len`이 null이다). 기준선이 없으면
/// 게이트가 "부팅 직후의 상태"를 볼 창구가 없다.
///
/// 줄이 셋인 이유가 이 서브프로젝트의 검증 구조다. 여백은 격자 밖이라
/// `screen>`·`style>`·`ink>`가 하나도 못 본다. `text=`만 있으면 `statusText`가
/// 만든 문자열을 되읽는 것뿐이고 "글자는 만들었는데 화면에 안 그렸다"를 못
/// 잡는다. 그래서 띠 안에서 우리 색인 픽셀을 직접 센다 — `dumpInk`가
/// `getPixel`로 프레임버퍼를 읽는 것과 같은 방법이다.
///
/// 셋째 줄(`caps ink`)은 `text=`가 원리적으로 못 보는 것을 본다(IS-M1).
/// `CAPS` 칸은 켜지든 꺼지든 글자가 똑같으므로(design 결정 3) 갈리는
/// 것은 색뿐이다.
///
/// x 범위를 안 잰다 — 띠 전체를 세도 답이 같다. `STATUS_ON`과
/// `STATUS_OFF`는 여백 안에서 `CAPS` 칸에만 쓰이기 때문이다. 범위를 재려
/// 들면 `drawStatus`의 col 전진 산수까지 여기서 다시 해야 하고, 어긋나면
/// 언제나 0이 나온다 — 증상이 "안 그렸다"와 똑같아서 원인을 엉뚱한 데서
/// 찾게 된다.
///
/// 메모가 `text`만 보면 안 된다. `CAPS`는 켜져도 글자가 안 바뀌므로,
/// `caps`를 함께 기억하지 않으면 CapsLock을 눌러도 새 줄이 한 줄도 안
/// 찍힌다 — 그리고 그 증상은 "구멍이 안 고쳐졌다"와 구별이 안 된다
/// (둘 다 `on=0`이다).
///
/// `render` 뒤에 불러야 한다. 그 전에 부르면 이전 프레임의 픽셀을 읽는다.
fn dumpStatus(
    fb: drm.Framebuffer,
    st: Status,
    last: *[status.MAX_LEN]u8,
    last_len: *?usize,
    last_caps: *bool,
) void {
    if (last_len.*) |n| {
        if (std.mem.eql(u8, last[0..n], st.text) and last_caps.* == st.caps) return;
    }
    @memcpy(last[0..st.text.len], st.text);
    last_len.* = st.text.len;
    last_caps.* = st.caps;
    std.debug.print("terminal: status> text={s}\n", .{st.text});

    // 띠 안에서 우리 색인 픽셀을 센다. `drawStatus`와 같은 산수로 y를
    // 구해야 한다 — 어긋나면 언제나 0이 나오고, 증상이 "안 그렸다"와 똑같아서
    // 원인을 `drawStatus`에서 찾게 된다.
    const grid_bottom = GRID_Y + @as(u32, st.rows) * ROW_HEIGHT;
    if (fb.height < grid_bottom + ROW_HEIGHT) {
        std.debug.print("terminal: status> ink fg=0 (no room below the grid)\n", .{});
        std.debug.print("terminal: status> caps ink on=0 off=0 (no room)\n", .{});
        std.debug.print("terminal: status> copy ink=0 (no room)\n", .{});
        return;
    }
    const y = grid_bottom + (fb.height - grid_bottom - ROW_HEIGHT) / 2;

    // 한 번 훑으며 넷을 함께 센다. 띠를 네 번 훑을 이유가 없다.
    var fg: usize = 0;
    var on: usize = 0;
    var off: usize = 0;
    var copy: usize = 0;
    var row: u32 = 0;
    while (row < ROW_HEIGHT) : (row += 1) {
        var col: u32 = 0;
        while (col < fb.width) : (col += 1) {
            const px = fb.getPixel(col, y + row) & 0x00FFFFFF;
            if (px == STATUS_FG) fg += 1;
            if (px == STATUS_ON) on += 1;
            if (px == STATUS_OFF) off += 1;
            if (px == STATUS_COPY) copy += 1;
        }
    }
    std.debug.print("terminal: status> ink fg={d}\n", .{fg});
    // `on`과 `off`를 한 줄에 함께 찍는다. 하나만 보면 "아예 안 그렸다"와
    // "반대 색으로 그렸다"가 안 갈린다 — 게이트가 언제나 둘을 같이 읽는다.
    std.debug.print("terminal: status> caps ink on={d} off={d}\n", .{ on, off });
    // `COPY` 칸의 픽셀(CI design 결정 6). `text=`만 보면 `drawStatus`가
    // 꼬리를 안 그려도, 색을 한 칸 밀려 그려도 초록이다 — 이 수가 그 둘을
    // 잡는다. copy 체인이 들어간 뒤 `>0`, Esc 뒤 `=0`을 짝으로 본다. 메모를
    // 넓힐 일은 없다 — `CAPS`와 달리 `COPY`는 글자 자체가 생기고 사라져서
    // `text`가 바뀐다.
    std.debug.print("terminal: status> copy ink={d}\n", .{copy});
}

/// 매치 하이라이트가 이 프레임에 무엇을 칠했는지(design 결정 5).
///
/// 상한을 안 두기로 한 결정의 근거를 남기는 줄이다. `us=`가 밀리초 단위로
/// 커지면 그때 상한을 논의한다. `style>`는 프레임당 16줄이 상한이라
/// (`STYLE_DUMP_LIMIT`) 셀 수를 그것만으로 셀 수 없다 — 이 줄에는 상한이 없고,
/// 둘을 함께 보는 것이 plan 결정 3이다.
///
/// 검색이 없으면 한 줄도 안 찍는다. `hlStats()`가 null을 주는 자리가
/// 그것이다(plan 결정 2).
///
/// 반드시 `render()` 뒤에 부른다 — 값은 그 프레임의 `cells()`가 만든다.
///
/// 문구가 이 파일과 `copy/check.sh` 양쪽에 중복된다.
/// 한쪽을 고치면 다른 쪽도 고쳐야 한다.
fn dumpHighlight(screen: *vt.Screen) void {
    const hl = screen.hlStats() orelse return;
    // `cur=`을 `cells=` 뒤·`us=` 앞에 넣는다(SP-M0 plan 결정 5).
    // `copy/check.sh`의 검사 16이 `sed -E 's/.*cells=([0-9]+).*/\1/'`로
    // `cells=`를 뽑으므로 그 뒤에 필드를 더하는 것은 안전하지만, `cells=`를
    // 옮기거나 `cells`를 부분 문자열로 갖는 이름을 쓰면 깨진다.
    std.debug.print("terminal: find> hl spans={d} cells={d} cur={d} us={d}\n", .{
        hl.spans, hl.cells, hl.cur, hl.us,
    });
}

/// `y`가 클립보드에 무엇을 담았는지를 찍는다.
///
/// 게이트가 클립보드를 볼 수 있는 유일한 창구다. 화면만 보면 복사가 됐는지
/// 알 방법이 아예 없다 — 복사는 화면을 안 바꾼다.
///
/// `len`을 함께 찍는 이유는 글자가 잘리거나 뒤에 뭐가 더 붙는 경우를 게이트가
/// 한 줄로 가릴 수 있게 하기 위해서다. `text=`가 맞아도 `len=`이 다르면 그것은
/// 다른 문자열이다.
///
/// 문구가 이 파일과 `copy/check.sh` 양쪽에 중복된다(design 결정 8).
/// 한쪽을 고치면 다른 쪽도 고쳐야 한다.
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
/// 쓰는 일과 찍는 일을 한 함수에 둔 이유는 길이가 두 곳에서 갈리지 않게
/// 하기 위해서다. 게이트가 `len=11`을 보고 "11바이트가 나갔다"로 읽는데, 쓰기와
/// 로그가 떨어져 있으면 그 둘이 다른 슬라이스를 볼 여지가 생긴다.
///
/// 자식이 모드 2004를 켰으면 bracketed paste로 감싼다(PE design 결정 2).
/// 감쌀지와 무엇으로 감쌀지는 `vt.zig`의 `pasteParts`가 정하고, 여기는 그
/// 세 조각을 차례로 쓰기만 한다. 게스트의 셸 셋(zsh · bash · fish)과 vim이
/// 전부 그 모드를 켜므로(PE design 실측 1), 여러 줄을 붙여도 Enter 전에는
/// 실행되지 않고 vim의 `autoindent`가 계단을 만들지 않는다. 모드가 꺼져
/// 있으면(`cat`처럼 모드를 모르는 프로그램) 머리와 꼬리가 비어서 본문만
/// 나간다 — PE-M1 전과 같은 바이트다.
///
/// 이어 붙여 한 번에 쓰지 않는다(PE design 결정 3). 클립보드에 상한이 없어서
/// 매번 할당이 들고, 한 번에 써도 자식이 한 번에 읽는다는 보장이 없다.
///
/// `len=`은 본문의 길이이고 `bracketed=`는 감쌌는지(1 또는 0)다. 머리와
/// 꼬리의 12바이트를 `len=`에 더하지 않는 것은 그 숫자가 계속 "클립보드에
/// 무엇이 들었나"를 말하게 하기 위해서다. 새 필드를 맨 뒤에 붙였으므로
/// `clip> paste len=11`을 접두로 보는 판정이 그대로 맞는다(PE design 결정 4).
///
/// 새 접두사를 만들지 않고 `clip>`를 쓰는 것은 design 결정 8이다. 문구가 이
/// 파일과 `copy/check.sh` 양쪽에 중복된다 — 한쪽을 고치면 다른 쪽도 고쳐야
/// 한다.
fn dumpPaste(screen: *vt.Screen, master_fd: c_int) void {
    const text = screen.clipboard() orelse {
        // 아직 아무것도 복사하지 않았는데 Cmd+V를 눌렀다. 조용히 넘어가면
        // 게이트가 "클립보드가 비었다"와 "Cmd+V가 아예 안 도착했다"를 못 가른다.
        std.debug.print("terminal: clip> paste empty\n", .{});
        return;
    };
    const parts = screen.pasteParts(text);
    for (parts) |p| {
        if (p.len > 0) pty.write(master_fd, p);
    }
    std.debug.print("terminal: clip> paste len={d} bracketed={d}\n", .{
        parts[1].len,
        @intFromBool(parts[0].len > 0),
    });
}

/// `Cmd+V`가 클립보드의 첫 줄을 검색어에 붙인다(FP design 결정 3·6).
///
/// 두 수를 한 줄에 함께 찍는다. `put=0` 하나만으로는 "클립보드가 비었다"와
/// "128바이트를 넘어 거절됐다"가 안 갈리고, `clip=50 put=20`은 여러 줄이 첫
/// 줄에서 잘렸다는 것까지 한 줄로 말한다. IS-M1 실측 5가 `on=87 off=87`로
/// 배운 것과 같다.
///
/// 접두사가 `clip>`가 아니라 `find>`인 것에 뜻이 있다. 게이트의 음성
/// 검사가 "`clip> paste` 줄이 안 늘었다"로 셸 갈래를 안 탔음을 보므로,
/// 두 갈래가 다른 접두사를 써야 그 판정이 선다. `key>` 줄로는 못 본다 —
/// 붙여넣기는 `pty.write`를 직접 부르지 `keys.bytes`를 안 거친다.
///
/// 문구가 이 파일과 `hangul/check.sh` 양쪽에 있다 — 한쪽을 고치면 다른
/// 쪽도 고쳐야 한다(`clip>`가 이미 그런 자리다).
fn dumpFindPaste(screen: *vt.Screen) void {
    const clip_len = if (screen.clipboard()) |t| t.len else 0;
    const put = screen.findPaste();
    std.debug.print("terminal: find> paste clip={d} put={d}\n", .{ clip_len, put });
}

/// 셸 하나(WP design 결정 1). WP 전에 `main`이 변수로 들던 `screen` ·
/// `session`이 그대로 필드가 되고, 격자 안의 자리가 하나 더해진다.
const Pane = struct {
    screen: *vt.Screen,
    session: pty.Session,
    /// 격자 안의 자리(셀 단위). 하나뿐이면 격자 전체다.
    rect: layout.Rect,
};

/// iTerm2의 탭 하나. 패널의 트리와 포커스 하나씩(WP design "모델" 절).
///
/// `panes`는 잎 번호로 바로 인덱싱한다 — `layout.Tree`가 잎 번호를 0..7로
/// 주는 이유다. null인 칸은 그 번호의 잎이 없다는 뜻이다.
const Workspace = struct {
    tree: layout.Tree,
    panes: [layout.MAX_LEAVES]?Pane,
    /// 키보드가 가는 패널의 잎 번호(결정 4).
    focus: u4,
};

/// 워크스페이스 수의 상한. Cmd+1~9가 번호라 아홉이다(WP design "모델" 절).
const MAX_WORKSPACES = 9;

/// 패널 왼쪽 위 셀의 프레임버퍼 좌표.
const Origin = struct { x: u32, y: u32 };

/// 셀 좌표를 픽셀로 옮기는 원점(WP design 결정 6). WP 전의
/// `GRID_X + col * CELL_W`가 `GRID_X + (rect.col + col) * CELL_W`가 되는
/// 자리다 — 그리는 함수와 프레임버퍼를 되읽는 덤프가 전부 이것을 부르므로
/// 둘이 다른 원점을 볼 수 없다.
fn paneOrigin(rect: layout.Rect) Origin {
    return .{
        .x = GRID_X + @as(u32, rect.col) * CELL_W,
        .y = GRID_Y + @as(u32, rect.row) * ROW_HEIGHT,
    };
}

/// 이미지를 그려도 되는 사각형은 그 패널이다(결정 6). 여백 · 상태 줄 ·
/// 이웃 패널에는 안 그린다. WP 전에는 격자 전체를 상수(`grid_clip`)로 들었다.
fn paneClip(rect: layout.Rect) image.Clip {
    const o = paneOrigin(rect);
    return .{
        .x0 = @intCast(o.x),
        .y0 = @intCast(o.y),
        .x1 = @intCast(o.x + @as(u32, rect.cols) * CELL_W),
        .y1 = @intCast(o.y + @as(u32, rect.rows) * ROW_HEIGHT),
    };
}

/// 패널 하나를 띄운다 — PTY와 그 위의 셸, 그리고 그 출력을 해석할
/// `vt.Screen`. 둘의 크기가 `rect`에서 함께 나오므로 셸이 아는 폭과 우리가
/// 그리는 폭이 어긋날 수 없다.
///
/// 부팅의 첫 패널이 이것을 부르고, WP-M1의 분할이 같은 함수를 부른다.
fn spawnPane(
    io: std.Io,
    alloc: std.mem.Allocator,
    path: [*:0]const u8,
    argv: [*:null]const ?[*:0]const u8,
    rect: layout.Rect,
) !Pane {
    const session = try pty.spawn(path, argv, rect.cols, rect.rows);
    const screen = try vt.Screen.init(io, alloc, rect.cols, rect.rows, .{ .w = CELL_W, .h = ROW_HEIGHT });
    return .{ .screen = screen, .session = session, .rect = rect };
}

/// `poll`의 fd 하나가 누구의 것인가(WP-M1). 패널 포인터와, 그 패널을
/// 트리에서 지울 때 필요한 두 번호.
const PaneRef = struct { pane: *Pane, ws: usize, leaf: u4 };

/// 워크스페이스의 수(WP-M2). 번호가 자리라 배열의 앞에서부터 빈틈없이
/// 차 있다 — 지울 때 뒤를 당긴다(EOF 경로). 그래서 이 수가 곧 첫 빈 칸이고
/// `Cmd+T`가 새 워크스페이스를 놓는 자리다.
fn workspaceCount(workspaces: *const [MAX_WORKSPACES]?Workspace) usize {
    var n: usize = 0;
    for (workspaces) |slot| {
        if (slot != null) n += 1;
    }
    return n;
}

/// 모든 워크스페이스의 패널 수. 0이 되면 terminal이 끝난다(결정 5).
fn paneCount(workspaces: *const [MAX_WORKSPACES]?Workspace) usize {
    var n: usize = 0;
    for (workspaces) |slot| {
        if (slot) |w| n += w.tree.count();
    }
    return n;
}

/// 트리가 바뀐 뒤 패널들의 크기를 맞춘다(WP design 결정 3). 분할 뒤와
/// 닫기 뒤 둘 다 이것을 부른다.
///
/// 규칙이 하나다 — `rect`가 바뀐 패널만 다시 잰다. 분할이면 갈린 패널
/// 하나가 작아지고, 닫기면 올라간 형제(와 그 아래 패널들)가 커진다. 어느
/// 경우인지를 여기서 가르지 않아도 사각형을 비교하면 저절로 그 패널들만 남는다.
///
/// `vt.Screen.resize`와 `pty.resize`가 짝이다. 한쪽만 바꾸면 셸이 아는 폭과
/// 우리가 그리는 폭이 어긋나 줄바꿈이 엉킨다(`spawnPane`의 주석과 같은 병).
///
/// 새 잎의 칸은 아직 null이라 건너뛴다. 부르는 쪽이 돌려받은 사각형으로
/// 그 칸에 `spawnPane`한다.
fn applyLayout(ws: *Workspace, whole: layout.Rect) ![layout.MAX_LEAVES]layout.Rect {
    var rs: [layout.MAX_LEAVES]layout.Rect = undefined;
    ws.tree.rects(whole, &rs);
    for (&ws.panes, 0..) |*slot, leaf| {
        const p = if (slot.*) |*p| p else continue;
        const r = rs[leaf];
        if (std.meta.eql(p.rect, r)) continue;
        try p.screen.resize(r.cols, r.rows);
        pty.resize(p.session.master_fd, r.cols, r.rows);
        p.rect = r;
    }
    return rs;
}

/// `pane>` 줄을 찍을지 가르는 값(WP design 결정 7). 이 중 하나가 바뀐
/// 프레임에만 찍는다.
///
/// 워크스페이스 둘(`ws` · `total`)은 WP-M2가 더했다. 없으면 `Cmd+1`로 같은
/// 모양(패널 하나 · 격자 전체)의 워크스페이스로 옮겨도 줄이 안 찍히고,
/// 다른 워크스페이스가 사라져 `ws=1/2`가 `ws=1/1`이 돼도 안 찍힌다.
///
/// `dumpStatus`가 매 프레임 찍지 않는 이유와 같다(RC-M0 실측 7 — 시리얼 한
/// 줄이 밀리초 단위다). 셸 출력으로 다시 그리는 프레임이 대부분이고 그때
/// 패널 배치는 안 바뀐다.
const PaneSig = struct {
    ws: usize,
    total: usize,
    panes: usize,
    focus: u4,
    rect: layout.Rect,
};

/// 패널 배치를 한 줄로 찍는다(WP design 결정 7).
///
///   terminal: pane> ws=1/1 panes=2 focus=1 rect=78,0 77x47 sep ink=752
///
/// `sep ink`는 프레임버퍼 전체에서 `SEPARATOR` 픽셀 수다. CI의 `copy ink`와
/// 같은 자리다 — 트리가 맞아도 구분선을 안 그리면 0이고, 글자만 보는 판정은
/// 그것을 못 잡는다. 전체를 세는 것은 그 색이 구분선에만 쓰이기 때문이다
/// (`dumpStatus`가 띠 전체에서 `STATUS_COPY`를 세는 것과 같은 논리).
///
/// 첫 프레임에는 반드시 찍힌다(`last`가 null). 기준선이 없으면 게이트가
/// 부팅 직후의 배치를 볼 창구가 없다.
///
/// 문구가 이 파일과 `pane/check.sh` 양쪽에 있다. 한쪽을 고치면 다른 쪽도
/// 고쳐야 한다.
///
/// `render` 뒤에 부른다 — 그 전에 부르면 이전 프레임의 픽셀을 센다.
fn dumpPane(
    fb: drm.Framebuffer,
    workspaces: *const [MAX_WORKSPACES]?Workspace,
    current: usize,
    last: *?PaneSig,
) void {
    const ws = workspaces[current].?;
    const sig: PaneSig = .{
        .ws = current,
        .total = workspaceCount(workspaces),
        .panes = ws.tree.count(),
        .focus = ws.focus,
        .rect = ws.panes[ws.focus].?.rect,
    };
    if (last.*) |l| {
        if (std.meta.eql(l, sig)) return;
    }
    last.* = sig;

    var ink: usize = 0;
    var y: u32 = 0;
    while (y < fb.height) : (y += 1) {
        var x: u32 = 0;
        while (x < fb.width) : (x += 1) {
            if (fb.getPixel(x, y) & 0x00FFFFFF == SEPARATOR) ink += 1;
        }
    }
    std.debug.print("terminal: pane> ws={d}/{d} panes={d} focus={d} rect={d},{d} {d}x{d} sep ink={d}\n", .{
        current + 1,  sig.total,    sig.panes,     sig.focus,
        sig.rect.col, sig.rect.row, sig.rect.cols, sig.rect.rows,
        ink,
    });
}

// ── 포인터 장치(PD-M0) ───────────────────────────────────────────────
//
// 찾고 열고 읽고 닫는 시스템 콜 쪽이다. 판단(분류 · 디코딩 · 좌표)은 전부
// `pointer.zig`에 있고 여기는 fd와 로그만 다룬다(PD design 결정 3).

/// 포인터 장치를 찾는 디렉터리. 처음 훑기가 이것을 읽는다(design 결정 1).
const POINTER_DIR = "/dev/input";
/// `/dev/input/eventN`의 경로 버퍼. `event` 뒤 번호가 몇 자리여도 넉넉하다.
const POINTER_PATH_MAX = 64;
/// 장치 이름(`EVIOCGNAME`)의 버퍼. 로그에 찍기만 한다 — 판정은 이름을 안 본다.
const POINTER_NAME_MAX = 64;

/// 장치 칸 하나. 경로를 드는 이유는 둘이다 — 처음 훑기와 uevent가 겹쳐
/// 같은 경로가 두 번 오면 건너뛰려고, 그리고 `close` 줄에 찍으려고.
const PointerDev = struct {
    fd: c_int,
    path: [POINTER_PATH_MAX]u8,
    path_len: usize,
    mouse: pointer.Mouse = .{},

    fn pathSlice(self: *const PointerDev) []const u8 {
        return self.path[0..self.path_len];
    }
};

/// 한 poll 회차의 포인터 이벤트 요약. 회차가 끝나면 `at` 줄 하나가 된다.
const PointerRound = struct {
    frames: usize = 0,
    wheel: i32 = 0,
};

/// 연 fd에 성질을 묻는다. 하나라도 실패하면 null이다 — 분류할 수 없는
/// 장치라 열지 않는다. sysfs가 아니라 ioctl인 이유는 design 결정 1이다.
fn readCaps(fd: c_int) ?pointer.Caps {
    var caps: pointer.Caps = .{};
    if (ioctl(fd, pointer.eviocgbit(0, caps.ev.len), &caps.ev) < 0) return null;
    if (ioctl(fd, pointer.eviocgbit(pointer.c.EV_KEY, caps.key.len), &caps.key) < 0) return null;
    if (ioctl(fd, pointer.eviocgbit(pointer.c.EV_REL, caps.rel.len), &caps.rel) < 0) return null;
    if (ioctl(fd, pointer.eviocgbit(pointer.c.EV_ABS, caps.abs.len), &caps.abs) < 0) return null;
    if (ioctl(fd, pointer.eviocgprop(caps.prop.len), &caps.prop) < 0) return null;
    return caps;
}

/// `/dev/input/<name>`을 열어 보고 마우스면 빈 칸에 넣는다(design 결정 1 · 2).
/// 처음 훑기와 uevent의 `add`가 이 함수 하나를 지난다.
///
/// `O_NONBLOCK`인 이유. 키보드(`input.openDevice`)는 블로킹이고 poll이 깨운
/// 뒤 한 번만 읽는다. 포인터는 한 회차에 쌓인 것을 다 읽고 `EAGAIN`에서
/// 멈춰야 회차마다 `at` 줄이 하나다(design 결정 3). `O_CLOEXEC`는 패널의
/// 셸이 이 fd를 물려받지 않게 한다.
///
/// 줄의 `name=`은 언제나 맨 끝이다. 이름에 공백이 들어 있어서다.
///
/// PD-M0은 마우스만 연다. 분류가 `touchpad`를 내도 `skip`이다 — 터치패드
/// 디코더는 PD-M3이 더한다.
fn tryOpenPointer(devs: *[pointer.MAX_DEVICES]?PointerDev, name: []const u8) void {
    var path_buf: [POINTER_PATH_MAX]u8 = undefined;
    const path = std.fmt.bufPrintZ(&path_buf, POINTER_DIR ++ "/{s}", .{name}) catch return;
    for (devs) |slot| {
        const d = slot orelse continue;
        if (std.mem.eql(u8, d.pathSlice(), path)) return;
    }
    const fd = std.c.open(path, .{ .ACCMODE = .RDONLY, .NONBLOCK = true, .CLOEXEC = true });
    if (fd < 0) {
        std.debug.print("terminal: pointer> skip {s} error={s}\n", .{ path, @tagName(std.c.errno(fd)) });
        return;
    }
    const caps = readCaps(fd) orelse {
        std.debug.print("terminal: pointer> skip {s} error=ioctl\n", .{path});
        _ = std.c.close(fd);
        return;
    };
    var name_buf: [POINTER_NAME_MAX]u8 = @splat(0);
    _ = ioctl(fd, pointer.eviocgname(name_buf.len), &name_buf);
    // 커널은 NUL까지 쓰지만, 이름이 버퍼보다 길면 잘린 채 NUL이 없다.
    name_buf[name_buf.len - 1] = 0;
    const dev_name = std.mem.sliceTo(&name_buf, 0);

    const kind = pointer.classify(&caps);
    if (kind != .mouse) {
        std.debug.print("terminal: pointer> skip {s} kind={s} name={s}\n", .{ path, @tagName(kind), dev_name });
        _ = std.c.close(fd);
        return;
    }
    const free = for (devs, 0..) |slot, i| {
        if (slot == null) break i;
    } else {
        std.debug.print("terminal: pointer> skip {s} full name={s}\n", .{ path, dev_name });
        _ = std.c.close(fd);
        return;
    };
    devs[free] = .{ .fd = fd, .path = undefined, .path_len = path.len };
    @memcpy(devs[free].?.path[0..path.len], path);
    // `shown=0`은 화살표가 아직 안 보인다는 뜻이다. 열린 뒤 움직여야 보인다
    // (design 결정 4의 보이는 조건 2). PD-M0은 아예 안 그리므로 언제나 0이다.
    std.debug.print("terminal: pointer> open {s} kind=mouse shown=0 name={s}\n", .{ path, dev_name });
}

/// 부팅 때 이미 있던 장치를 훑는다. uevent 소켓을 연 뒤에 부른다 — 반대면
/// 훑은 뒤 소켓을 열기 전에 생긴 장치를 놓친다(design 결정 1). 실패해도 terminal은
/// 산다. 포인터 없이 키보드만으로 지금처럼 쓴다.
fn scanPointers(io: std.Io, devs: *[pointer.MAX_DEVICES]?PointerDev) void {
    var dir = std.Io.Dir.openDirAbsolute(io, POINTER_DIR, .{ .iterate = true }) catch |err| {
        std.debug.print("terminal: pointer> scan failed error={s}\n", .{@errorName(err)});
        return;
    };
    defer dir.close(io);
    var it = dir.iterate();
    // `event`로 시작하는 이름만 본다. `mice` · `mouseN`은 evdev 이전의
    // 통로이고 `INPUT_MOUSEDEV`가 꺼져 있어 생기지도 않는다(design 실측 6).
    while (it.next(io) catch null) |entry| {
        if (std.mem.startsWith(u8, entry.name, "event")) tryOpenPointer(devs, entry.name);
    }
}

/// uevent 소켓에 쌓인 것을 다 읽는다. 부팅 뒤에 꽂힌 장치가 여기로 온다.
///
/// datagram 하나가 uevent 하나다. 무엇을 열지는 `pointer.ueventAddedNode`가
/// 가른다(`ACTION=add` · `SUBSYSTEM=input` · `DEVNAME=input/eventN`).
/// devtmpfs는 노드를 만든 뒤에 uevent를 보내므로 그때 노드가 이미 있다
/// (PD-M0 plan 확정 7).
///
/// `remove`는 안 본다. 빠진 장치는 그 fd의 `POLLERR` · `POLLHUP` · `ENODEV`로
/// 안다(design 결정 1). read가 `ENOBUFS`면 소켓 버퍼가 넘쳐 커널이 메시지를
/// 버린 것이다 — 놓친 장치가 있을 수 있으므로 디렉터리를 다시 훑는다. 이미
/// 연 경로는 건너뛴다.
fn drainUevents(fd: c_int, io: std.Io, devs: *[pointer.MAX_DEVICES]?PointerDev) void {
    // 커널 uevent 하나는 `UEVENT_BUFFER_SIZE`(2048바이트) 안이다.
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = std.c.read(fd, &buf, buf.len);
        if (n < 0) {
            if (std.c.errno(n) != .NOBUFS) return; // EAGAIN — 다 읽었다
            scanPointers(io, devs);
            continue;
        }
        if (n == 0) return;
        const name = pointer.ueventAddedNode(buf[0..@intCast(n)]) orelse continue;
        tryOpenPointer(devs, name);
    }
}

/// 열린 장치에서 읽을 것을 다 읽어 `Pointer`에 적용한다. `EAGAIN`에서 멈춘다.
/// 장치가 사라졌으면(`ENODEV` 등) `.gone`이다.
///
/// read를 열여섯 번까지만 한다. 장치가 쉬지 않고 이벤트를 내도 이 회차가
/// 끝나야 키보드와 PTY가 돈다 — 남은 것은 다음 poll이 다시 알린다.
fn drainPointer(dev: *PointerDev, slot: u3, state: *pointer.Pointer, round: *PointerRound) enum { open, gone } {
    const ev_size = @sizeOf(pointer.c.struct_input_event);
    var raw: [ev_size * 64]u8 = undefined;
    for (0..16) |_| {
        const n = std.c.read(dev.fd, &raw, raw.len);
        if (n < 0) return if (std.c.errno(n) == .AGAIN) .open else .gone;
        if (n == 0) return .gone;
        const count = @as(usize, @intCast(n)) / ev_size;
        for (0..count) |i| {
            const ev: *align(1) const pointer.c.struct_input_event = @ptrCast(&raw[i * ev_size]);
            const frame = dev.mouse.feed(ev.type, ev.code, ev.value) orelse continue;
            const e = state.apply(slot, frame);
            round.frames += 1;
            round.wheel +|= e.wheel;
        }
    }
    return .open;
}

/// 장치 칸을 비운다. 그 장치가 누르고 있던 버튼도 놓는다(`Pointer.forget`).
fn closePointer(devs: *[pointer.MAX_DEVICES]?PointerDev, slot: usize, state: *pointer.Pointer) void {
    const d = &devs[slot].?;
    std.debug.print("terminal: pointer> close {s}\n", .{d.pathSlice()});
    _ = std.c.close(d.fd);
    _ = state.forget(@intCast(slot));
    devs[slot] = null;
}

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    const fb = try drm.open(allocator, "/dev/dri/card0");
    fb.fill(MARGIN_COLOR);
    try fb.present();

    // 화면 크기를 여기서 한 번만 계산해 렌더러·Terminal·PTY winsize
    // 세 곳에 같은 값을 넘긴다. 이 셋이 어긋나면 셸이 생각하는 폭과 우리가
    // 그리는 폭이 달라져 줄바꿈이 엉킨다.
    //
    // WP-M0부터 이것은 격자 전체이고, Terminal·PTY가 받는 것은 그 안의
    // 패널 사각형이다(`spawnPane`). 패널 하나면 둘이 같다.
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
    //
    // SC-M0 전에는 이 플래그가 조건 없이 붙었다. 이유로 적혀 있던 것은
    // "프롬프트가 예측 가능해야 게이트가 화면을 검사할 수 있다"였는데,
    // 2026-09-11에 재 보니 설정을 다 읽은 fish의 프롬프트가 `--no-config`로
    // 뜬 것과 글자까지 같았다(design 실측 14(c)). 그 이유는 이제 없다.
    //
    // 인자 없이 손으로 실행할 때의 기본값은 `--no-config`로 남긴다 — 그때는
    // init이 없어서 `"none"`을 넘겨줄 사람이 없다.
    const shell_path: [*:0]const u8 = if (args.len > 1) args[1] else "/usr/bin/fish";
    const shell_flag: [*:0]const u8 = if (args.len > 2) args[2] else "--no-config";
    // 넷째 인자가 키보드 종류다(IP-M2, design doc 결정 9). enum을 여기 다시
    // 정의하지 않고 문자열 하나만 비교하는 것이 요점이다 — CP가 정한
    // "파서는 한 벌"을 지킨다. init이 enum으로 이미 걸렀으므로 여기 도착하는
    // 값은 apple 아니면 pc이고, 그 외 무엇이 오더라도 apple로 떨어진다.
    const keyboard: [*:0]const u8 = if (args.len > 3) args[3] else "apple";
    const swap_alt_meta = std.mem.eql(u8, std.mem.span(keyboard), "pc");

    // 여섯째와 일곱째가 자판 둘이다(HI-M2, design 결정 7). keyboard와 달리
    // enum 이름이 그대로 오므로 `stringToEnum`으로 되돌린다 — 이름이
    // `init/src/config.zig`의 enum과 짝이어야 하고 컴파일러가 그것을 못
    // 잡는다. init이 화이트리스트를 이미 거쳤으므로 여기 도착하는 값은
    // 언제나 맞고, 아래 fallback은 terminal을 손으로 띄울 때를 위한 것이다.
    const hangul_arg: []const u8 = if (args.len > 5) std.mem.span(args[5]) else "shin_pcs";
    const latin_arg: []const u8 = if (args.len > 6) std.mem.span(args[6]) else "qwerty";
    const hangul_layout = std.meta.stringToEnum(hangul.Layout, hangul_arg) orelse .shin_pcs;
    const latin_layout = std.meta.stringToEnum(input.LatinLayout, latin_arg) orelse .qwerty;

    // 여덟째가 한/영 전환 키 목록이다(HI-M3, design 결정 7). 자판 둘과 달리
    // enum 하나가 아니라 집합이라 `stringToEnum` 대신 콤마 파서를 쓴다.
    //
    // fallback을 문자열로 두는 것에 뜻이 있다. 집합 리터럴로 쓰면 기본값이
    // 이 파일에도 한 벌 생기는데, 그 값은 `init/src/config.zig`의 `Config`와
    // 같아야 하고 컴파일러가 그것을 못 잡는다. 문자열로 두면 적어도 눈으로
    // 대조할 형태가 설정 파일과 같아진다.
    const toggle_arg: []const u8 = if (args.len > 7)
        std.mem.span(args[7])
    else
        "hangul_key,shift_space,capslock_tap,lctrl_tap";
    const toggles = input.parseToggles(toggle_arg);

    // TERM은 지금까지 거짓말을 하고 있었다. 커널의 envp_init이 준
    // `TERM=linux`가 PID 1을 거쳐 여기까지 상속되는데
    // (docs/decisions/project_guest_environment.md), 이 셸이 말을 거는 상대는
    // 리눅스 콘솔이 아니라 libghostty-vt다. 셸과 ncurses 프로그램은 terminfo를
    // 보고 시퀀스를 고르므로, 이름이 틀리면 우리가 보내는 특수키와 셸이
    // 기대하는 것이 어긋난다 — Home이 linux에서는 `ESC [ 1 ~`, xterm에서는
    // `ESC O H`다.
    //
    // execv는 환경을 그대로 상속하므로 fork 전에 고쳐두면 자식이 받는다.
    // 이 setenv가 PID 1이 아니라 여기 있는 이유는 시리얼 콘솔 셸 때문이다 —
    // 그쪽은 정말로 커널 콘솔이라 TERM=linux가 맞다. 같은 기계 안에서 두
    // 셸의 TERM이 다른 것이 정상이다(design doc 결정 7).
    //
    // TR-M0부터 xterm-256color다. 그전에는 "우리가 색을 하나도 그리지 않아서"
    // xterm이었는데, 이제 팔레트 256색과 truecolor를 전부 칠하므로 xterm이라고
    // 말하는 쪽이 거짓말이 된다(design 결정 8).
    _ = setenv("TERM", "xterm-256color", 1);

    // 로케일도 여기서 정한다(HI-M1). TERM과 같은 자리에 있는 이유가 다르다 —
    // TERM은 시리얼 콘솔 셸과 값이 갈려야 해서 여기 있고, LANG은 갈릴 이유가
    // 없는데도 여기 있다. PID 1은 커널이 준 envp 블록을 그대로 execve에 넘기고
    // (`init/src/main.zig:389`) 거기에 항목을 더하려면 블록을 새로 만들어야
    // 하는데, 한글 입력을 받는 셸은 이쪽 하나뿐이라 그 값을 치르지 않는다.
    // 시리얼 콘솔 셸은 C 로케일로 남는다.
    //
    // 이것이 없으면 셸이 한글을 한 글자로 읽지 못한다. `setlocale`이
    // 실패하면 `mbrtowc`가 바이트를 하나씩 돌려주고, fish는 우리가 보낸 세
    // 바이트를 세 글자로 들고 바이트마다 폭을 센다(0x80~0x9F는 0칸,
    // 0xA0 이상은 1칸). 그러면 커서가 두 칸짜리 글자의 가운데에 서고 다음
    // 글자가 앞 글자를 지운다 — 증상이 입력이 아니라 화면에 나타난다.
    //
    // 값이 참이 되려면 `/usr/lib/locale/C.utf8`이 게스트에 있어야 한다.
    // `make_initrd.sh`가 그것을 넣고, terminfo와 정확히 같은 종류의 짝이다.
    _ = setenv("LANG", "C.UTF-8", 1);

    // SC-M0 결정 6. TERM·LANG과 같은 자리에 있는 이유가 TERM과 같다 —
    // 값이 두 셸에서 갈려야 해서 여기 있다. 화면은 TARS의 화면이라 다른
    // 제품의 배너가 뜰 자리가 아니고, 시리얼 콘솔은 fish를 그대로 보는
    // 자리다(machine/check.sh:117이 그 인사말을 UEFI 부팅의 마커로 쓴다 —
    // 여기서 끄면 그 마커가 살고, /etc/fish/config.fish로 끄면 죽는다).
    //
    // fish의 `fish_greeting` 함수는 `set -q fish_greeting`이 참이면 기본
    // 문구를 안 만들고, 값이 비어 있으면 아무것도 안 찍는다. 환경 변수는
    // fish에서 전역 변수로 보이므로 `set -q`가 참이 된다. 2026-09-11에
    // 게스트에서 확인했다(design 실측 14(b)).
    //
    // bash·zsh는 이런 이름의 환경 변수를 모른다 — 조건 없이 넣는다.
    _ = setenv("fish_greeting", "", 1);

    // SC-M0 결정 3. init이 `"none"`을 넘기면 셸에 플래그를 안 붙인다 —
    // 슬롯을 null로 덮으면 execv가 거기서 멈추므로 배열 길이를 안 바꿔도
    // 된다(sentinel은 그대로 배열 끝에 있다).
    //
    // 문자열 하나로 말하는 이유는 `config.zig`의 `configFlag` 주석에
    // 있다 — argv를 짓는 쪽(PID 1)과 쓰는 쪽(여기)이 프로세스 경계로
    // 갈려 있어서 "인자가 없다"를 포인터로 못 보낸다.
    var argv = [_:null]?[*:0]const u8{ shell_path, shell_flag };
    if (std.mem.eql(u8, std.mem.span(shell_flag), "none")) argv[1] = null;

    // 부팅은 패널 하나짜리 워크스페이스 하나다(WP-M0). 패널의 사각형도
    // 트리에서 받는다 — 하나면 격자 전체지만, 분할이 생기는 M1에서 이
    // 자리가 따로 산수를 하고 있으면 둘이 갈린다.
    //
    // `current`는 `Cmd+T` · `Cmd+1`~`9`가 바꾸고, 워크스페이스가 사라지면
    // EOF 경로가 맞춘다(WP-M2).
    const whole: layout.Rect = .{ .col = 0, .row = 0, .cols = cols, .rows = rows };
    var workspaces: [MAX_WORKSPACES]?Workspace = @splat(null);
    var current: usize = 0;
    workspaces[current] = .{ .tree = layout.Tree.init(), .panes = @splat(null), .focus = 0 };
    var boot_rects: [layout.MAX_LEAVES]layout.Rect = undefined;
    workspaces[current].?.tree.rects(whole, &boot_rects);
    const first = try spawnPane(init.io, allocator, shell_path, &argv, boot_rects[0]);
    workspaces[current].?.panes[0] = first;
    defer for (workspaces) |slot| {
        const w = slot orelse continue;
        for (w.panes) |maybe| {
            if (maybe) |pane| pane.screen.deinit();
        }
    };
    // 경로까지 찍는다. 게이트가 "화면의 셸도 바뀌었는가"를 볼 수 있는 유일한
    // 줄이다. 앞부분("terminal: spawned child pid ")은 terminal/check.sh가
    // 개수를 세는 마커라 그대로 둔다.
    std.debug.print("terminal: spawned child pid {d} ({s})\n", .{
        first.session.child_pid, shell_path,
    });
    // 게이트가 "설정이 여기까지 왔는가"를 볼 수 있는 유일한 줄이다.
    // 이 값이 실제로 무슨 일을 하는지는 화면으로만 증명되지만(input/check.sh의
    // 2차 부팅), 그 화면이 틀렸을 때 "설정이 안 왔다"와 "설정은 왔는데 뜻이
    // 틀렸다"를 가르는 것이 이 줄이다.
    std.debug.print("terminal: keyboard={s} (swap_alt_meta={})\n", .{
        keyboard, swap_alt_meta,
    });
    // 같은 이유의 줄이 자판에도 하나 필요하다(HI-M2). `tars-init:`의 줄과
    // 짝이다 — 그쪽은 "init이 파일에서 읽었다"를, 이쪽은 "그 값이 argv를
    // 건너 여기 닿았다"를 말한다. 앞만 보면 argv 배선이 끊겨도 초록이고,
    // 뒤만 보면 여기 기본값이 우연히 맞아도 초록이다. HI 게이트가 둘을 다 본다.
    // `toggles=`는 파싱한 결과를 다시 문자열로 만든 것이다(HI-M3).
    // argv로 받은 문자열을 그대로 찍으면 "글자가 도착했다"만 증명되고
    // "우리가 그것을 맞게 읽었다"는 아무것도 증명되지 않는다.
    var toggle_buf: [input.TOGGLE_ARG_MAX]u8 = undefined;
    std.debug.print("terminal: hangul layout={s} latin={s} toggles={s}\n", .{
        @tagName(hangul_layout),
        @tagName(latin_layout),
        input.togglesArg(toggles, &toggle_buf),
    });

    const cell_buf = try allocator.alloc(vt.CellGlyph, @as(usize, cols) * rows);
    defer allocator.free(cell_buf);

    // 첫 프레임만 잰다. 매 프레임 찍으면 로그가 시끄럽고, 첫 프레임이 가장
    // 비싼 경우(폰트 캐시도 페이지도 차갑다)라 상한을 본다.
    var first_frame_timed = false;
    // kitty 이미지(TG-M2). 16칸을 넘는 placement가 한 화면에 보이면
    // `images_dropped`가 덤프에 찍힌다 — 그때 키운다.
    var img_buf: [16]vt.ImagePlacement = undefined;
    // 캐시가 자랐을 때만 찍는다. 매 프레임 찍으면 키를 칠 때마다 같은 줄이
    // 반복된다. design 위험 3을 게이트가 볼 수 있게 하는 자리다.
    var last_glyph_count: usize = 0;
    // 마지막으로 찍은 상태 줄. `?usize`인 것에 뜻이 있다 — 0을 초기값으로
    // 쓰면 "빈 줄을 찍었다"와 "아직 아무것도 안 찍었다"가 안 갈린다.
    var last_status: [status.MAX_LEN]u8 = undefined;
    var last_status_len: ?usize = null;
    // 글자와 따로 기억해야 한다(IS-M1). `CAPS` 칸은 켜져도 글자가 안
    // 바뀌므로, 이 값이 없으면 CapsLock을 눌러도 새 `status>` 줄이 한 줄도
    // 안 찍힌다. 첫 프레임은 `last_status_len`이 null이라 어차피 찍히므로
    // 초기값은 무엇이든 된다.
    var last_status_caps = false;
    // TR-M2의 구조 변경. 그전에는 렌더가 PTY 출력 분기 안에만 있었다 —
    // 스크롤은 키로 일어나므로 그대로 두면 뷰포트만 움직이고 화면은 안 바뀐다.
    var needs_redraw = false;
    var key_state: input.State = .{
        .hangul_layout = hangul_layout,
        .latin_layout = latin_layout,
        .toggles = toggles,
    };
    var key_buf: [64]u8 = undefined;
    var pty_buf: [4096]u8 = undefined;

    // 포인터 장치(PD-M0). 키보드와 달리 terminal이 스스로 찾고, 부팅 뒤에
    // 꽂힌 것도 잡는다(PD design 결정 1). init의 `argv[4]`는 그대로다.
    //
    // 부팅 뒤의 장치는 커널의 uevent로 안다. udev가 듣는 것과 같은 netlink
    // 소켓이고 커널 config가 더 필요 없다 — inotify를 켜면 initramfs 풀기가
    // 느려진다(PD-M0 plan 확정 7). 소켓을 먼저 열고 그다음에 훑는다.
    //
    // 소켓이 실패해도 terminal은 산다 — 부팅 때 있던 장치만 쓰고 핫플러그를
    // 잃는다. 그때 `uevent_fd`는 -1이고 poll은 음수 fd를 건너뛴다.
    var pointer_devs: [pointer.MAX_DEVICES]?PointerDev = @splat(null);
    var pointer_state = pointer.Pointer.init(fb.width, fb.height);
    const uevent_fd: c_int = uevent: {
        const linux = std.os.linux;
        const fd = socket(linux.AF.NETLINK, linux.SOCK.DGRAM | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC, linux.NETLINK.KOBJECT_UEVENT);
        if (fd < 0) {
            std.debug.print("terminal: pointer> uevent failed error={s}\n", .{@tagName(std.c.errno(fd))});
            break :uevent -1;
        }
        // 그룹 1이 커널이 보내는 uevent다(그룹 2는 udevd가 다시 보내는 것). pid
        // 0은 소켓의 주소를 커널이 고르게 한다.
        const addr: linux.sockaddr.nl = .{ .pid = 0, .groups = 1 };
        const rc = std.c.bind(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.nl));
        if (rc < 0) {
            std.debug.print("terminal: pointer> uevent failed error={s}\n", .{@tagName(std.c.errno(rc))});
            _ = std.c.close(fd);
            break :uevent -1;
        }
        break :uevent fd;
    };
    scanPointers(init.io, &pointer_devs);

    // poll이 보는 fd. 키보드 하나, uevent 소켓 하나(PD-M0), 열린 포인터 장치,
    // 그리고 모든 워크스페이스의 모든 패널이다(WP design 위험 1). 포커스 없는
    // 워크스페이스의 PTY도 읽어야 한다 — 안 읽으면 그 셸이 출력 버퍼에 막혀
    // 멈춘다.
    //
    // 크기는 상한(1 + 1 + 8 + 9 × 8)으로 고정하고 쓴 길이만 넘긴다. 패널 수와
    // 장치 수가 바뀌므로 매 바퀴 다시 짓는다 — 82칸을 채우는 비용은 없고,
    // "언제 고쳐 쓰는가"를 따로 들 필요가 없어진다.
    //
    // 자리는 `[0]` 키보드 · `[1]` uevent 소켓 · `[2..pty_base]` 포인터 장치 ·
    // `[pty_base..nfds]` PTY다. PD 전에는 PTY가 `[1..]`이었다 — 그 오프셋이
    // 이제 바퀴마다 다르므로 `pty_base`로 든다.
    var fds: [2 + pointer.MAX_DEVICES + MAX_WORKSPACES * layout.MAX_LEAVES]c.struct_pollfd = undefined;
    // `fds[2 + k]`가 어느 장치 칸의 것인지.
    var fd_devs: [pointer.MAX_DEVICES]usize = undefined;
    // `fds[pty_base + i]`가 어느 패널의 것인지. 패널은 `workspaces` 배열 안에
    // 그 자리 그대로 있으므로 포인터가 바퀴 안에서 안 흔들린다.
    //
    // 워크스페이스 번호와 잎 번호를 함께 드는 이유는 EOF다(WP-M1). 그
    // 패널을 닫으려면 트리에서 지워야 하고, 트리는 잎 번호만 안다.
    var fd_panes: [MAX_WORKSPACES * layout.MAX_LEAVES]PaneRef = undefined;
    // 마지막으로 찍은 `pane>` 줄의 서명(WP design 결정 7). null이면 아직 한
    // 번도 안 찍었다 — 첫 프레임이 반드시 찍힌다.
    var last_pane: ?PaneSig = null;

    main_loop: while (true) {
        fds[0] = .{ .fd = keyboard_fd, .events = c.POLLIN, .revents = 0 };
        fds[1] = .{ .fd = uevent_fd, .events = c.POLLIN, .revents = 0 };
        var nfds: usize = 2;
        for (&pointer_devs, 0..) |*slot, di| {
            const d = if (slot.*) |*d| d else continue;
            fds[nfds] = .{ .fd = d.fd, .events = c.POLLIN, .revents = 0 };
            fd_devs[nfds - 2] = di;
            nfds += 1;
        }
        const pty_base = nfds;
        for (&workspaces, 0..) |*slot, wi| {
            const w = if (slot.*) |*w| w else continue;
            for (&w.panes, 0..) |*pane_slot, leaf| {
                const pane = if (pane_slot.*) |*pane| pane else continue;
                fds[nfds] = .{ .fd = pane.session.master_fd, .events = c.POLLIN, .revents = 0 };
                fd_panes[nfds - pty_base] = .{ .pane = pane, .ws = wi, .leaf = @intCast(leaf) };
                nfds += 1;
            }
        }

        // -1 = 무한 대기. 이벤트가 없으면 CPU를 전혀 쓰지 않는다.
        const ready = c.poll(&fds, @intCast(nfds), -1);
        if (ready < 0) continue; // EINTR 등은 그냥 다시 기다린다

        // 키보드 · copy · 프롬프트 · 상태 줄 · 렌더 · 덤프가 보는 것은 전부
        // 포커스 패널이다(WP design 결정 1). 그래서 그 코드는 WP 전의
        // `screen` · `session`이 `focus.screen` · `focus.session`으로 이름만
        // 바뀌었다.
        //
        // `var`인 이유는 포커스가 바퀴 안에서 바뀌기 때문이다(WP-M1). 패널
        // 명령이 옮기고, EOF가 포커스 패널을 닫는다. 렌더 앞에서 다시 구한다.
        var ws = &workspaces[current].?;
        var focus = &ws.panes[ws.focus].?;

        if (fds[0].revents & c.POLLIN != 0) {
            // DECCKM은 셸이 언제든 켜고 끌 수 있으므로(프롬프트를 그릴 때
            // smkx, 외부 명령을 실행하기 전에 rmkx 하는 식으로 오간다)
            // 캐시하지 않고 키를 읽는 순간의 값을 쓴다. packed struct의
            // 비트 읽기 한 번이라 비용이 없다 — design doc 결정 6이 "값으로
            // 넘긴다"를 고르면서 감수하기로 한 대가가 이것이다.
            const ctx = input.Context{
                .cursor_keys = focus.screen.term.modes.get(.cursor_keys),
                // DECCKM과 달리 이 값은 부팅 내내 상수다. 매 키마다 다시
                // 넣는 것은 Context를 한 자리에서 조립하기 위해서일 뿐이다.
                .swap_alt_meta = swap_alt_meta,
            };
            const keys = input.readKeys(&key_state, keyboard_fd, &key_buf, ctx);
            if (keys.bytes.len > 0) {
                // 앞부분("terminal: key> ")은 input/check.sh가 grep하는
                // 마커라 그대로 둔다. 뒤에 decckm을 덧붙이는 이유는
                // design doc 위험 4다 — 게이트가 `ESC O` 경로를 실제로
                // 밟았는지 아니면 `ESC [`만 봤는지를 로그로 알 수 있어야 한다.
                std.debug.print("terminal: key> {d} byte(s) decckm={}\n", .{
                    keys.bytes.len, ctx.cursor_keys,
                });
                pty.write(focus.session.master_fd, keys.bytes);
            }
            // 스크롤은 PTY로 나가지 않는다(design 결정 11). 한 화면이 몇
            // 줄인지를 아는 것은 여기뿐이라, page_up/page_down을 rows 만큼의
            // delta로 바꾸는 것도 여기서 한다 — input.zig는 격자 크기를 모른다.
            // 한 화면은 포커스 패널의 줄 수다(WP design 결정 1).
            //
            // 순서대로 도는 이유는 자동 반복 때문이다. PageUp을 누르고 있으면
            // 한 번의 read에 여러 개가 실려 오고, 그만큼 올라가야 한다.
            for (keys.scrolls) |s| {
                switch (s) {
                    .top => focus.screen.scrollToTop(),
                    .bottom => focus.screen.scrollToBottom(),
                    .page_up => focus.screen.scrollByRows(-@as(isize, focus.rect.rows)),
                    .page_down => focus.screen.scrollByRows(@as(isize, focus.rect.rows)),
                }
                needs_redraw = true;
            }
            // copy mode 명령도 PTY로 나가지 않는다(design 결정 3). 스크롤과
            // 같은 이유로 순서대로 돈다 — j를 누르고 있으면 자동 반복이 여러
            // 개를 실어 온다.
            for (keys.copies) |cmd| {
                // "못 찾았다" 메시지는 다음 키에 사라진다(design 결정 9).
                //
                // 끄는 자리가 루프 안인 것에 뜻이 있다. 밖에 두면 한 번의
                // read에 여러 키가 실려 왔을 때(자동 반복) 첫 키만 메시지를
                // 지운다.
                //
                // 그리고 `switch`보다 앞이라, 모든 명령이 예외 없이 지우고
                // 그중 `.find_submit`만이 그 뒤에 다시 켤 수 있다. 순서 하나로
                // "다음 키에 사라진다"와 "새로 실패하면 다시 뜬다"가 함께 나온다.
                focus.screen.findClearStatus();
                switch (cmd) {
                    .enter => focus.screen.copyEnter(),
                    .exit => focus.screen.copyExit(),
                    .left => try focus.screen.copyMove(-1, 0),
                    .down => try focus.screen.copyMove(0, 1),
                    .up => try focus.screen.copyMove(0, -1),
                    .right => try focus.screen.copyMove(1, 0),
                    // 단어 이동(CN-M0). copyMove와 형제이고 선택 갱신도 같은
                    // copyApply를 통과한다 — 그래서 여기 배선은 한 줄이다.
                    .word_next => try focus.screen.copyMoveWord(.next),
                    .word_prev => try focus.screen.copyMoveWord(.prev),
                    .select_char => try focus.screen.copySelect(.char),
                    .select_line => try focus.screen.copySelect(.line),
                    // yank는 모드를 나간다. 그래서 아래 dumpCopy는 좌표
                    // 없이 `copy> yank`만 찍는다 — 커서가 이미 사라졌기
                    // 때문이다.
                    .yank => dumpClip(try focus.screen.copyYank()),
                    // 붙여넣기는 모드를 건드리지 않는다. 그래서 모드 안에서
                    // 누르면 아래 dumpCopy가 좌표를 그대로 찍고, 모드 밖에서
                    // 누르면 `copy> paste`만 찍힌다. 게이트가 그 차이로 "모드가
                    // 살아 있는가"를 본다.
                    //
                    // 목적지가 여기서 갈린다(FP design 결정 3). `input.zig`는
                    // `vt.zig`를 import하지 않으므로(IP design 결정 6) 이 갈래는
                    // 여기에만 설 수 있다 — 저쪽은 `Cmd+V`가 눌렸다는 것까지만
                    // 알고, 클립보드도 프롬프트도 이 파일이 본다.
                    //
                    // 판단 근거가 `input.State`의 모드가 아니라 `findNeedle()`
                    // 이다. `main.zig`가 볼 수 있는 것이 화면 쪽 사실이고,
                    // `findBytes`가 이미 `find_open`을 스스로 지킨다.
                    //
                    // 셸 갈래는 여전히 copies 배열에서 유일하게 PTY로 나가는
                    // 명령이다. 다른 아홉은 전부 우리 안에서 끝난다.
                    .paste => if (focus.screen.findNeedle() != null)
                        dumpFindPaste(focus.screen)
                    else
                        dumpPaste(focus.screen, focus.session.master_fd),
                    // 검색 프롬프트(CN-M1). 넷 다 화면 상태를 바꾸지 않는다 —
                    // needle 버퍼만 만지고, 그리는 것은 아래 render가 한다.
                    .find_open => {
                        focus.screen.findOpen();
                        dumpFind(focus.screen, "open");
                    },
                    .find_char => |ch| {
                        focus.screen.findChar(ch);
                        dumpFind(focus.screen, "type");
                    },
                    .find_erase => {
                        focus.screen.findErase();
                        dumpFind(focus.screen, "erase");
                    },
                    .find_cancel => {
                        focus.screen.findCancel();
                        dumpFind(focus.screen, "cancel");
                    },
                    // 확정된 한글이 needle로 들어간다(SH-M1). `findChar`가
                    // 아니라 `findBytes`인 것이 SH-M0의 이유 전부다 —
                    // 바이트씩 넣으면 128바이트 경계에서 음절이 반만 들어간다.
                    //
                    // 이 명령을 만드는 것은 `handleKey`가 아니라
                    // `readKeys`다(design 결정 4·5). 그 함수가 모드를
                    // `handleKey` 앞에서 읽어 목적지를 가른다.
                    .find_commit => |cmt| {
                        focus.screen.findBytes(cmt.buf[0..cmt.len]);
                        dumpFind(focus.screen, "commit");
                    },
                    // 이 milestone에서 유일하게 시간이 걸리는 명령이다.
                    // searchAll()이 스크롤백 전체를 훑는 동안 화면이 멈춘다
                    // (design 결정 5). 얼마나 멈추는지를 여기서 재서 찍는다 —
                    // 그 값이 "증분으로 바꿔야 하는가"를 나중에 가른다.
                    .find_submit => {
                        const t0 = std.Io.Clock.now(.awake, init.io);
                        const r = try focus.screen.findSubmit();
                        std.debug.print(
                            "terminal: find> submit matches={d} moved={} us={d}\n",
                            .{
                                r.matches,
                                r.moved,
                                @divTrunc(t0.untilNow(init.io, .awake).nanoseconds, 1000),
                            },
                        );
                    },
                    // 결과를 버리지 않고 찍는다. 못 옮긴 것과 옮긴 것은
                    // 사람에게 다른 뜻이고, 아래 dumpCopy의 좌표만으로는
                    // "안 움직였다"와 "같은 자리가 맞다"를 못 가른다.
                    .find_next => std.debug.print(
                        "terminal: find> next moved={}\n",
                        .{try focus.screen.findNext()},
                    ),
                    .find_prev => std.debug.print(
                        "terminal: find> prev moved={}\n",
                        .{try focus.screen.findPrev()},
                    ),
                }
                dumpCopy(focus.screen, @tagName(cmd));
                needs_redraw = true;
            }
            // 조합 중인 글자를 화면에 넘긴다(HI design 결정 2). 값을 만드는
            // 것은 `input.State`이고 그리는 것은 `vt.zig`이며, 둘을 잇는 것이
            // 여기다 — `input.zig`는 `vt.zig`를 import하지 않는다
            // (IP design 결정 6). `find_open`이 이미 같은 길로 돈다.
            //
            // `needs_redraw`를 여기서 켜야 한다. 화면만 바뀐 키는 PTY로
            // 아무것도 안 보내고 스크롤도 copy 명령도 안 만든다 — 그래서
            // 이 한 줄이 없으면 조합 중인 글자가 영영 화면에 안 나오고,
            // 대문자 잠금을 켜도 `CAPS` 칸이 다음 키를 칠 때까지 안
            // 밝아진다(IS design 결정 8).
            //
            // copy 루프 뒤인 것에도 뜻이 있다. copy mode에 들어가는 키가
            // 조합을 확정시키므로(design 결정 6), 그 확정 결과를 화면에
            // 반영하는 것은 모드 전환이 끝난 뒤여야 한다.
            if (keys.redraw) {
                focus.screen.setPreedit(key_state.preedit());
                dumpHangul(&key_state);
                needs_redraw = true;
            }
            // 패널 명령(WP-M1). PTY로 나가지 않는다 — 스크롤 · copy와 같이
            // 순서대로 돈다.
            //
            // `keys.redraw` 뒤인 것에 뜻이 있다. 포커스를 옮기는 키는 조합
            // 중인 한글을 먼저 확정시키고(HI 결정 6) 그 확정이 `redraw`를
            // 켠다. 위 블록이 떠나기 전 패널의 조합 글자를 지워야 하므로, 포커스가
            // 바뀌기 전에 돌아야 한다. 순서를 뒤집으면 지우는 일이 새 패널에
            // 가고 떠난 패널에 확정된 글자가 조합 중인 모양으로 남는다.
            //
            // 바이트(확정된 `한` 포함)는 이 블록보다 먼저 옛 패널의 셸에
            // 갔다(WP design 결정 4).
            for (keys.panes) |cmd| {
                switch (cmd) {
                    .split_right, .split_below => {
                        const dir: layout.Dir = if (cmd == .split_right) .right else .below;
                        // 꽉 찼거나 가를 수 없을 만큼 작다(`Tree.split`).
                        // 조용히 넘어가면 사람도 게이트도 "키가 안 왔다"와
                        // 구별을 못 한다.
                        const leaf = ws.tree.split(ws.focus, dir, whole) orelse {
                            std.debug.print("terminal: pane> split refused\n", .{});
                            continue;
                        };
                        const rs = try applyLayout(ws, whole);
                        // 새 셸은 부팅의 것과 같은 셸이다. `spawned child pid`
                        // 줄은 안 찍는다(WP-M1 plan 확정 1) — terminal/check.sh가
                        // 그 줄의 개수로 "init이 terminal을 되살렸다"를 판정하므로,
                        // 분할이 그 줄을 찍으면 그 판정이 거짓 초록이 된다.
                        // `pane>` 줄이 대신한다.
                        ws.panes[leaf] = try spawnPane(init.io, allocator, shell_path, &argv, rs[leaf]);
                        ws.focus = leaf;
                    },
                    // 보내기만 한다(결정 5). 셸이 끝나면 아래 EOF 경로가
                    // 닫는다 — `exit`를 친 것과 같은 길이다.
                    .close => {
                        const fp = &ws.panes[ws.focus].?;
                        pty.hangup(fp.session);
                        std.debug.print("terminal: pane> hangup leaf={d} pid={d}\n", .{
                            ws.focus, fp.session.child_pid,
                        });
                    },
                    .focus_next => ws.focus = ws.tree.next(ws.focus),
                    .focus_prev => ws.focus = ws.tree.prev(ws.focus),
                    // 새 워크스페이스는 끝에 선다(WP-M2). 번호가 자리라 빈
                    // 칸은 언제나 맨 뒤 하나다(`workspaceCount`).
                    .new_workspace => {
                        const n = workspaceCount(&workspaces);
                        // 아홉이 찼다. `split refused`와 같은 이유로 찍는다 —
                        // 조용하면 "키가 안 왔다"와 안 갈린다.
                        if (n == MAX_WORKSPACES) {
                            std.debug.print("terminal: pane> workspace refused\n", .{});
                            continue;
                        }
                        // 패널 하나짜리 트리의 사각형은 격자 전체다
                        // (`layout_test` 검사 1). `rects`를 돌리지 않는다.
                        workspaces[n] = .{ .tree = layout.Tree.init(), .panes = @splat(null), .focus = 0 };
                        workspaces[n].?.panes[0] = try spawnPane(init.io, allocator, shell_path, &argv, whole);
                        current = n;
                        // 이 배치의 뒤 명령(같은 read에 실려 온 Cmd+D 등)이 새
                        // 워크스페이스에 가도록 여기서 다시 구한다.
                        ws = &workspaces[current].?;
                    },
                    // 없는 번호와 지금 번호는 아무 일도 안 한다 — 로그도 다시
                    // 그리기도 없다(`continue`가 아래 `needs_redraw`를 건너뛴다).
                    // 게이트가 `pane>` 줄 수가 안 는 것으로 그것을 본다.
                    .workspace_1, .workspace_2, .workspace_3, .workspace_4, .workspace_5, .workspace_6, .workspace_7, .workspace_8, .workspace_9 => {
                        const target: usize = @intFromEnum(cmd) - @intFromEnum(input.Pane.workspace_1);
                        if (target >= workspaceCount(&workspaces) or target == current) continue;
                        current = target;
                        ws = &workspaces[current].?;
                    },
                }
                needs_redraw = true;
            }
        }

        // 포인터 장치(PD-M0). 키보드 뒤 · PTY 앞이다(design 결정 3).
        //
        // 빠진 장치를 uevent보다 먼저 닫는다. 빠진 번호가 곧바로 다시 쓰이면
        // 옛 칸의 경로가 남아 새 장치를 "이미 열었다"로 건너뛰기 때문이다.
        //
        // `POLLERR` · `POLLHUP`이면 읽지 않고 닫는다. 이것을 빠뜨리면 poll이
        // 그 fd에 대해 매 바퀴 즉시 돌아와 terminal이 CPU를 다 쓴다(design
        // 결정 1).
        var round: PointerRound = .{};
        for (fds[2..pty_base], fd_devs[0 .. pty_base - 2]) |pfd, di| {
            if (pfd.revents == 0) continue;
            var gone = pfd.revents & (c.POLLERR | c.POLLHUP) != 0;
            if (!gone and pfd.revents & c.POLLIN != 0) {
                gone = drainPointer(&pointer_devs[di].?, @intCast(di), &pointer_state, &round) == .gone;
            }
            if (gone) closePointer(&pointer_devs, di, &pointer_state);
        }
        if (fds[1].revents & c.POLLIN != 0) drainUevents(uevent_fd, init.io, &pointer_devs);
        // 회차마다 한 줄이다. 이벤트마다 찍으면 마우스의 보고 빈도(수백 Hz)가
        // 그대로 줄 수가 된다(design 결정 3). PD-M0은 그리지 않으므로
        // `needs_redraw`를 안 켠다 — 화면이 한 픽셀도 안 바뀐다. 그래서
        // `shown`과 `ink`는 상수 0이다. PD-M1이 둘을 채운다(design 결정 10).
        if (round.frames > 0) {
            std.debug.print("terminal: pointer> at x={d} y={d} buttons={d} wheel={d} shown=0 ink=0\n", .{
                pointer_state.x, pointer_state.y, pointer_state.buttons.bits(), round.wheel,
            });
        }

        // PTY master는 slave가 전부 닫히면 POLLIN이 아니라 POLLHUP을 올린다.
        // 남은 출력이 있으면 POLLIN과 함께 오지만 다 읽고 나면 POLLHUP만
        // 남으므로, POLLIN만 보면 read를 영영 호출하지 못하고 poll이 즉시
        // 반환하는 바쁜 루프에 빠진다. POLLHUP에서도 read를 시도하면 남은
        // 데이터를 먼저 비우고, 비고 나면 read가 EIO를 내 EOF 경로로 간다.
        //
        // 패널마다 본다(WP design 위험 1). 포커스 아닌 패널도 읽어서
        // `feed`까지 하고, 그리는 것은 아래에서 포커스 패널만 한다.
        for (fds[pty_base..nfds], fd_panes[0 .. nfds - pty_base]) |pfd, ref| {
            if (pfd.revents & (c.POLLIN | c.POLLHUP | c.POLLERR) == 0) continue;
            const pane = ref.pane;
            const out = pty.readSome(pane.session.master_fd, &pty_buf);
            if (out.len == 0) {
                std.debug.print("terminal: child exited (pty EOF)\n", .{});
                // 마지막 패널이면 WP 전처럼 terminal이 끝나고 init이 되살린다
                // (WP design 결정 5).
                if (paneCount(&workspaces) == 1) break :main_loop;
                // 아니면 그 패널만 닫는다. 닫는 자리는 여기 하나다 — `exit`도
                // `Cmd+W`(SIGHUP)도 셸을 끝내고, 셸이 끝나면 여기로 온다.
                const w = &workspaces[ref.ws].?;
                std.debug.print("terminal: pane> closed leaf={d}\n", .{ref.leaf});
                pty.close(pane.session);
                pane.screen.deinit();
                w.panes[ref.leaf] = null;
                // 포커스를 먼저 옮긴다. 자리를 넘겨받는 형제로 간다(WP-M2,
                // 사용자가 2026-10-03에 골랐다 — M1은 순회의 다음이었다).
                // `heir`는 그 잎이 트리에 있어야 형제를 안다 — 지운 뒤에
                // 물으면 제자리를 돌려준다.
                if (w.focus == ref.leaf) w.focus = w.tree.heir(ref.leaf);
                w.tree.remove(ref.leaf);
                needs_redraw = true;
                // 워크스페이스의 마지막 패널이었다(WP-M2). 워크스페이스가
                // 사라지고 뒤의 것들이 한 자리씩 앞으로 온다 — 번호는 자리다
                // (design "모델" 절). 전체의 마지막 패널이었다면 위에서 이미
                // 루프를 나갔다.
                if (w.tree.count() == 0) {
                    std.debug.print("terminal: pane> workspace closed ws={d}\n", .{ref.ws + 1});
                    var i = ref.ws;
                    while (i + 1 < MAX_WORKSPACES) : (i += 1) workspaces[i] = workspaces[i + 1];
                    workspaces[MAX_WORKSPACES - 1] = null;
                    const left = workspaceCount(&workspaces);
                    // 지금 보던 워크스페이스가 사라졌으면 같은 자리(이제 뒤의
                    // 것이 왔다)로, 그것이 끝이었으면 한 칸 앞으로. 뒤의 것을
                    // 보던 중이었으면 번호가 하나 당겨진다.
                    if (current == ref.ws) {
                        current = @min(ref.ws, left - 1);
                    } else if (current > ref.ws) {
                        current -= 1;
                    }
                    // `fd_panes`의 남은 항목은 이 바퀴에 지은 것이라 `ws`
                    // 번호와 패널 포인터가 당기기 전의 자리를 가리킨다
                    // (WP-M2 plan 확정 4). 여기서 PTY 루프를 끝낸다. 안 읽은
                    // 출력은 다음 `poll`이 다시 알린다.
                    break;
                }
                _ = try applyLayout(w, whole);
                // 이 패널의 슬롯은 비었다. `pane`은 이제 아무것도 안
                // 가리키므로 이 바퀴에서 더 안 만진다.
                continue;
            }
            pane.screen.feed(out);
            // 자식이 질의를 보냈으면(`ESC[6n` 커서 위치 등) 답이 여기 쌓여
            // 있다. `feed` 바로 뒤에서 돌려주는 것이 TQ design 결정 3이다 —
            // pty에 쓰는 자리가 여기 하나뿐이라 순서 문제가 안 생기고,
            // 질의의 답이 그 뒤에 친 키보다 먼저 나간다(그 순서가 fzf에게
            // 뜻이 있다: --height 상자 높이를 정하는 것이 답이다).
            //
            // 답의 내용은 라이브러리가 만든다. 우리가 여기서 정하는 것은
            // "언제 어디로 보내는가"뿐이다.
            const replies = pane.screen.takeReplies();
            if (replies.len > 0) pty.write(pane.session.master_fd, replies);
            // design 결정 13. 라이브러리는 이것을 해 주지 않는다 — 올라간
            // 상태에서 출력을 먹여도 뷰포트가 그대로라는 것을 2026-08-23에
            // 실측했고, vt_test가 그 사실을 못 박고 있다. 대부분의 터미널이
            // 이렇게 동작하며, 그러지 않으면 "화면이 멈춘 것 같다"는 혼란이
            // 생긴다.
            //
            // 부수 효과가 하나 있다: 뷰포트가 history에 머무는 동안 가지치기가
            // 일어나는 상황이 이 한 줄로 구조적으로 안 생긴다. 가지치기는
            // 그 페이지를 가리키던 pin을 무효로 만드는데, 여기서 창이 닫힌다.
            // copy mode 중에는 억제한다(CM-M0). 백그라운드 출력이 한 줄만
            // 도착해도 사람이 올라가서 보고 있던 자리가 화면 밖으로 튕기기
            // 때문이다.
            //
            // 그 대가로 위 주석이 말한 창이 열린다 — 뷰포트가 history에
            // 머무는 동안 가지치기가 일어날 수 있게 된다(design 위험 1).
            // CM-M1이 방어를 넣었는데, 계획했던 모양이 아니다: 가지치기는
            // 선택을 null로 만들지 않고 tracked pin을 이웃 페이지의 왼쪽 위로
            // 옮기므로, vt.zig의 feed가 앵커의 screen 좌표 y를 대신 감시한다.
            //
            // 이 억제 분기 자체는 CM-M2의 게이트가 밟는다. 모드 안에서는
            // 셸에 아무것도 보낼 수 없어 출력을 만들 방법이 없었는데,
            // Cmd+V가 그 방법이 됐다 — 붙여넣은 글자를 셸이 되울리는 것이
            // 곧 "모드 중에 도착한 PTY 출력"이다.
            if (!pane.screen.copyActive()) pane.screen.scrollToBottom();
            // 위 feed가 가지치기를 만났으면 vt.zig가 모드를 이미 닫았다
            // (design 위험 1). 로그를 안 남기면 사람이 "왜 갑자기 모드가
            // 풀렸지"를 영영 모른다.
            if (pane.screen.copyTakePruned()) dumpCopy(pane.screen, "pruned");
            needs_redraw = true;
        }

        // 렌더를 루프 끝으로 뺀 것이 TR-M2의 구조 변경이다. 그전에는 렌더가
        // PTY 출력 분기 안에만 있었다 — 스크롤은 키로 일어나므로 그대로
        // 두면 뷰포트만 움직이고 화면은 안 바뀐다.
        //
        // 플래그를 두는 이유는 그리는 횟수를 늘리지 않기 위해서다. modifier
        // 키처럼 아무것도 바꾸지 않는 이벤트에서는 그리지 않는다.
        if (!needs_redraw) continue;
        needs_redraw = false;

        // 포커스를 다시 구한다(WP-M1). 위의 패널 명령이 옮겼거나 EOF가
        // 포커스 패널을 닫았을 수 있다 — 그때 위의 `focus`는 빈 슬롯을
        // 가리킨다. 워크스페이스도 다시 구한다(WP-M2) — EOF가 워크스페이스를
        // 지워 배열을 당겼으면 위의 `ws`는 다른 워크스페이스를 가리킨다.
        ws = &workspaces[current].?;
        focus = &ws.panes[ws.focus].?;

        // 포커스 아닌 패널을 먼저 그린다(WP-M1). 포커스 패널이 마지막이어야
        // 아래 덤프 넷이 읽는 `cell_buf` · `img_buf`가 그 패널의 것으로
        // 남는다. 두 버퍼를 패널마다 다시 쓰는 것은 design 위험 4다 —
        // `cell_buf`가 격자 전체 크기라 어느 패널에도 충분하다.
        //
        // `focused`를 매 프레임 여기서 맞춘다(결정 6). 포커스의 진실은
        // `ws.focus` 하나이고, 화면 쪽 값은 그리기 직전의 사본이다 —
        // 포커스를 옮기는 자리마다 그 값을 고치게 하면 하나를 빠뜨린다.
        const frame_start = std.Io.Clock.now(.awake, init.io);
        renderBackdrop(fb, &ws.tree, whole);
        for (&ws.panes, 0..) |*slot, leaf| {
            const p = if (slot.*) |*p| p else continue;
            if (leaf == ws.focus) continue;
            p.screen.focused = false;
            const p_cells = try p.screen.cells(cell_buf);
            const p_bg = p.screen.defaultBg();
            // 포커스 없는 화면이라 `cursorMark()`는 null이다(결정 5). 그래도
            // 넘기는 이유는 그 판단을 `vt.zig` 한 자리에 두기 위해서다.
            try renderPane(fb, &cache, p_cells, p.screen.images(&img_buf), p_bg, p.rect, p.screen.cursorMark());
        }
        focus.screen.focused = true;

        const cells = try focus.screen.cells(cell_buf);

        // 프롬프트 문자열을 여기서 만든다. `vt.zig`는 앞의 `/`를 모른다 —
        // 그것은 표현이지 상태가 아니고, TR-M0이 색을 vt.zig에서 확정해 넘긴
        // 것과 반대 방향의 같은 경계다(모양은 main.zig가 정한다).
        //
        // 버퍼가 needle보다 마흔다섯 칸 크다. 앞의 `/` 하나와, 뒤에 올 수
        // 있는 것 중 긴 쪽인 ` [20/20]` 마흔넷 때문이다(SP-M1). `usize`가
        // 최대 스무 자리라 숫자 둘이 마흔이고, ` [`·`/`·`]`가 넷이다.
        // `: not found` 열하나는 그보다 짧으므로 이 크기가 둘 다 덮는다.
        var prompt_buf: [173]u8 = undefined;
        const prompt: ?Prompt = if (promptText(focus.screen, &prompt_buf)) |t| .{
            .text = t,
            // 프롬프트가 열려 있을 때만 조합을 붙인다(SH-M2). 닫힌 뒤의
            // 오버레이는 지난 검색의 결과 표시이고, 그 위에 조합을 그리면
            // 검색어가 자라는 것처럼 보인다.
            //
            // `findNeedle()`이 열림의 진실이다 — `promptText`가 갈래를 가를
            // 때 보는 값과 같은 것이라 둘이 어긋날 수 없다.
            .edit = if (focus.screen.findNeedle() != null) key_state.preedit() else null,
            .rect = focus.rect,
            // `cells()` 뒤에 읽어야 한다 — `state.colors`는 update()가
            // 채운다(vt.zig의 defaultFg 주석).
            .fg = focus.screen.defaultFg(),
            .bg = focus.screen.defaultBg(),
        } else null;

        // 상태 줄을 여기서 만든다. `prompt`와 같은 자리이고 같은 이유다 —
        // 모양은 `main.zig`가 정하고 그리는 함수는 "한 줄을 준 색으로 쓴다"
        // 하나만 안다.
        var status_buf: [status.MAX_LEN]u8 = undefined;
        // copy mode는 `vt.Screen`의 상태다. `status.zig`가 `vt.zig`를 import하지
        // 않으므로(CI design 결정 4) 여기서 bool 하나로 넘긴다. 갱신 경로는
        // 새로 없다 — copy 명령은 전부 위의 copy 루프에서 `needs_redraw`를
        // 켜고, 이 자리는 그 프레임 안이다.
        const copy_active = focus.screen.copyActive();
        // 워크스페이스가 둘 이상일 때만 번호를 단다(WP design 결정 8). 하나뿐인
        // 화면은 M1과 글자도 픽셀도 같아야 한다 — hangul 체인의 `text=`와
        // `ink fg=` 기준값이 그대로 서는 것이 그 판정이다.
        const ws_number: ?u8 = if (workspaceCount(&workspaces) > 1) @intCast(current + 1) else null;
        const status_line: Status = .{
            .text = status.statusText(&key_state, copy_active, ws_number, &status_buf),
            .rows = rows,
            // `statusText`가 아니라 여기서 읽는다(design 결정 3). 잠금은
            // 글자가 아니라 색을 고르므로 순수 모듈이 알 일이 아니다.
            .caps = key_state.caps_lock,
            .copy = copy_active,
            .workspace = ws_number,
        };

        // `images()`의 데이터는 다음 `feed`까지만 유효하다. 이 자리는 feed와
        // render 사이라 안전하다.
        const imgs = focus.screen.images(&img_buf);
        try renderPane(fb, &cache, cells, imgs, focus.screen.defaultBg(), focus.rect, focus.screen.cursorMark());
        const prompt_ink = try renderFinish(fb, &cache, prompt, status_line);
        const frame_us = @divTrunc(frame_start.untilNow(init.io, .awake).nanoseconds, 1000);
        if (!first_frame_timed) {
            first_frame_timed = true;
            std.debug.print("terminal: render> first frame {d}us\n", .{frame_us});
        }
        dumpImages(fb, imgs, focus.screen.images_dropped, frame_us, focus.rect);

        dumpScreen(cells);
        dumpHighlight(focus.screen);
        dumpOverlay(prompt);
        dumpPromptInk(fb, prompt_ink, prompt);
        dumpStatus(fb, status_line, &last_status, &last_status_len, &last_status_caps);
        dumpPane(fb, &workspaces, current, &last_pane);
        // render 뒤에 부른다 — 그 전에 부르면 이전 프레임의 픽셀을 읽는다.
        // 기본 색을 여기 상수로 다시 적지 않고 `focus.screen`에서 얻는 이유는
        // vt.zig의 defaultFg 주석에 있다.
        dumpStyles(
            fb,
            cells,
            focus.screen.defaultFg(),
            focus.screen.defaultBg(),
            if (prompt != null) focus.rect.rows - 1 else null,
            focus.rect,
        );
        dumpInk(fb, &cache, cells, focus.rect);
        // `dumpInk` 뒤 · `dumpScroll` 앞이다(CU-M0 plan 확정 7). 마지막
        // `screen>`부터 파일 끝까지를 한 프레임으로 자르는 게이트의
        // `last_frame`이 이 줄을 담으려면 `screen>` 뒤여야 한다.
        dumpCursor(fb, focus.screen, focus.rect);
        dumpScroll(focus.screen);
        if (cache.count() != last_glyph_count) {
            last_glyph_count = cache.count();
            std.debug.print("terminal: font> {d} glyph(s) cached, {d} bitmap bytes\n", .{
                last_glyph_count, cache.bitmap_bytes,
            });
        }
    }

    // 마지막 패널의 셸이 끝나면 터미널도 끝난다(WP design 결정 5). PID
    // 1(tars-init)이 우리를 다시 띄우고, 새 프로세스가 DRM을 다시 열어 새
    // 프롬프트를 그린다. TF 시절의 무한 sleep은 되살려 줄 감독자가 없어서
    // 필요했던 것이라 이제 지운다.
}
