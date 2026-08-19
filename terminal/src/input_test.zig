const std = @import("std");
const input = @import("input.zig");

/// evdev 키코드를 커널이 정한 이름으로 쓴다. `input.c`는 input.zig가
/// `@cImport("linux/input.h")`한 것을 그대로 공개한 것이다(IP-M2).
/// 숫자를 남겨두면 "105가 ←였나 →였나"를 매번 헤아려야 하는데, 이 파일은
/// IP-M2에서 검사가 두 배로 는다.
const K = input.c;

/// IP-M0부터 handleKey는 바이트 **하나**가 아니라 바이트 **열**을 돌려준다.
/// "보낼 것 없음"은 null이 아니라 빈 슬라이스다.
///
/// IP-M1부터 handleKey는 `Context`도 받는다. 대부분의 검사는 기본값
/// (`cursor_keys=false`)으로 충분하므로 여기서 채워 넣고, DECCKM 두 형태를
/// 비교해야 하는 검사만 아래 expectCtx를 직접 부른다.
fn expect(state: *input.State, code: u16, value: i32, want: []const u8) !void {
    return expectCtx(state, .{}, code, value, want);
}

fn expectCtx(
    state: *input.State,
    ctx: input.Context,
    code: u16,
    value: i32,
    want: []const u8,
) !void {
    const got = state.handleKey(code, value, ctx);
    if (std.mem.eql(u8, got, want)) return;
    std.debug.print(
        "FAIL: code={d} value={d} ckm={} -> got={any}, want={any}\n",
        .{ code, value, ctx.cursor_keys, got, want },
    );
    return error.UnexpectedBytes;
}

pub fn main() !void {
    // struct input_event가 @cImport로 제대로 넘어왔는지부터 확인한다.
    std.debug.print("input_event size = {d} (expected 24)\n", .{input.eventSize()});
    if (input.eventSize() != 24) {
        std.debug.print("FAIL: unexpected struct input_event size\n", .{});
        return error.UnexpectedEventSize;
    }

    var state: input.State = .{};

    // "hi" 타이핑: 누를 때만 문자가 나오고, 뗄 때는 안 나온다.
    try expect(&state, K.KEY_H, 1, "h");
    try expect(&state, K.KEY_H, 0, "");
    try expect(&state, K.KEY_I, 1, "i");
    try expect(&state, K.KEY_I, 0, "");

    // Enter는 CR을 보낸다.
    try expect(&state, K.KEY_ENTER, 1, "\r");

    // Shift를 누르면 그 자체는 문자가 없고, 이어지는 키가 대문자가 된다.
    try expect(&state, K.KEY_LEFTSHIFT, 1, "");
    try expect(&state, K.KEY_H, 1, "H"); // shifted
    try expect(&state, K.KEY_LEFTSHIFT, 0, "");
    try expect(&state, K.KEY_H, 1, "h"); // unshifted 복귀

    // 좌우 Shift는 각자 추적된다. 왼쪽을 누른 채 오른쪽을 눌렀다 떼도
    // Shift는 풀리지 않아야 한다 — 손은 아직 왼쪽을 누르고 있다.
    try expect(&state, K.KEY_LEFTSHIFT, 1, "");
    try expect(&state, K.KEY_RIGHTSHIFT, 1, "");
    try expect(&state, K.KEY_RIGHTSHIFT, 0, "");
    try expect(&state, K.KEY_H, 1, "H"); // 여전히 대문자
    try expect(&state, K.KEY_LEFTSHIFT, 0, "");
    try expect(&state, K.KEY_H, 1, "h"); // 이제 소문자

    // Shift + 숫자 = 기호.
    try expect(&state, K.KEY_RIGHTSHIFT, 1, "");
    try expect(&state, K.KEY_1, 1, "!"); // shifted
    try expect(&state, K.KEY_RIGHTSHIFT, 0, "");

    // 자동 반복(value=2)도 문자를 만든다. 방향키를 누르고 있으면 계속
    // 움직여야 하므로 이 성질은 오히려 필요하다.
    try expect(&state, K.KEY_A, 2, "a"); // autorepeat

    // 표에 없는 키코드는 조용히 무시한다. 여기만 숫자로 남기는 이유는 이
    // 줄의 요점이 **이름이 없는 코드**라서다 — 이름을 붙이면 뜻이 사라진다.
    try expect(&state, 200, 1, "");

    // ── Ctrl 제어 문자 (IP-M0) ──────────────────────────────────────────
    //
    // 규칙은 한 줄이다: Shift를 먼저 적용해 문자를 정한 뒤 `& 0x1F`.
    // ASCII에서 제어 문자 0x00~0x1F는 `@ABC…Z[\]^_`(0x40~0x5F)에서 상위 두
    // 비트를 뗀 것이므로, 마스크가 곧 정의다.

    try expect(&state, K.KEY_LEFTCTRL, 1, ""); // 그 자체는 문자 없음
    try expect(&state, K.KEY_C, 1, "\x03"); // Ctrl+C → SIGINT를 부르는 바이트
    try expect(&state, K.KEY_D, 1, "\x04"); // Ctrl+D → EOF
    try expect(&state, K.KEY_Z, 1, "\x1a"); // Ctrl+Z → SIGTSTP
    try expect(&state, K.KEY_BACKSLASH, 1, "\x1c"); // Ctrl+\ → SIGQUIT
    try expect(&state, K.KEY_LEFTBRACE, 1, "\x1b"); // Ctrl+[ → ESC
    try expect(&state, K.KEY_SPACE, 1, "\x00"); // Ctrl+Space → NUL

    // 마스크가 의미 있는 것은 문자가 0x40~0x7F일 때뿐이다. Ctrl+1에
    // 적용하면 0x31 & 0x1F = 0x11(XON)이 나오는데 아무도 그런 뜻으로 쓰지
    // 않는다. 대상이 아닌 문자는 Ctrl을 무시하고 원래 문자를 보낸다.
    try expect(&state, K.KEY_1, 1, "1"); // Ctrl+1 → 그냥 '1'

    // Shift가 함께 눌려도 제어 문자는 같다.
    try expect(&state, K.KEY_LEFTSHIFT, 1, "");
    try expect(&state, K.KEY_C, 1, "\x03"); // Ctrl+Shift+C → 여전히 0x03
    // Shift+2는 '@'이고 '@' & 0x1F = 0x00이다.
    try expect(&state, K.KEY_2, 1, "\x00"); // Ctrl+Shift+2 → NUL
    try expect(&state, K.KEY_LEFTSHIFT, 0, "");

    try expect(&state, K.KEY_LEFTCTRL, 0, "");
    try expect(&state, K.KEY_C, 1, "c"); // Ctrl을 떼면 다시 평문

    // 오른쪽 Ctrl도 같다.
    try expect(&state, K.KEY_RIGHTCTRL, 1, "");
    try expect(&state, K.KEY_C, 1, "\x03");
    try expect(&state, K.KEY_RIGHTCTRL, 0, "");

    // 좌우 Ctrl 각자 추적. 왼쪽을 누른 채 오른쪽을 눌렀다 떼도 안 풀린다.
    try expect(&state, K.KEY_LEFTCTRL, 1, "");
    try expect(&state, K.KEY_RIGHTCTRL, 1, "");
    try expect(&state, K.KEY_RIGHTCTRL, 0, "");
    try expect(&state, K.KEY_C, 1, "\x03"); // 여전히 Ctrl
    try expect(&state, K.KEY_LEFTCTRL, 0, "");
    try expect(&state, K.KEY_C, 1, "c");

    // ── 특수키 → 이스케이프 시퀀스 (IP-M1) ──────────────────────────────
    //
    // 여기서 처음으로 키 하나가 바이트 여러 개가 된다. IP-M0가 반환 타입을
    // []const u8로 바꾼 이유가 이것이다 — 표를 아무리 늘려도 ?u8로는
    // `ESC [ D` 세 바이트를 표현할 수 없었다.

    // DECCKM 꺼짐(기본): `ESC [ X`
    try expect(&state, K.KEY_UP, 1, "\x1b[A");
    try expect(&state, K.KEY_DOWN, 1, "\x1b[B");
    try expect(&state, K.KEY_RIGHT, 1, "\x1b[C");
    try expect(&state, K.KEY_LEFT, 1, "\x1b[D");
    try expect(&state, K.KEY_HOME, 1, "\x1b[H");
    try expect(&state, K.KEY_END, 1, "\x1b[F");

    // 틸드 계열은 DECCKM과 무관하게 언제나 같은 모양이다.
    try expect(&state, K.KEY_DELETE, 1, "\x1b[3~");
    try expect(&state, K.KEY_PAGEUP, 1, "\x1b[5~");
    try expect(&state, K.KEY_PAGEDOWN, 1, "\x1b[6~");

    // 뗄 때는 여전히 아무것도 안 보낸다.
    try expect(&state, K.KEY_LEFT, 0, "");
    // 자동 반복은 보낸다 — 방향키를 누르고 있으면 계속 움직여야 한다.
    try expect(&state, K.KEY_LEFT, 2, "\x1b[D");

    // ── DECCKM 켜짐: 커서 계열만 `ESC O X`로 바뀐다 ─────────────────────
    //
    // 이 모드가 실제로 켜지는지는 셸에 달려 있고(smkx), --no-config로 뜬
    // 셸이 안 보내면 게이트는 이 경로를 한 번도 밟지 않는다(design doc
    // 위험 4). 그래서 **여기서** 두 형태를 다 본다.
    const ckm = input.Context{ .cursor_keys = true };
    try expectCtx(&state, ckm, K.KEY_UP, 1, "\x1bOA");
    try expectCtx(&state, ckm, K.KEY_DOWN, 1, "\x1bOB");
    try expectCtx(&state, ckm, K.KEY_RIGHT, 1, "\x1bOC");
    try expectCtx(&state, ckm, K.KEY_LEFT, 1, "\x1bOD");
    try expectCtx(&state, ckm, K.KEY_HOME, 1, "\x1bOH");
    try expectCtx(&state, ckm, K.KEY_END, 1, "\x1bOF");

    // 틸드 계열은 DECCKM이 켜져도 그대로다. 이 세 줄이 위 여섯 줄만큼
    // 중요하다 — "모드가 켜지면 전부 O로 바꾼다"는 흔한 오해를 막는다.
    try expectCtx(&state, ckm, K.KEY_DELETE, 1, "\x1b[3~");
    try expectCtx(&state, ckm, K.KEY_PAGEUP, 1, "\x1b[5~");
    try expectCtx(&state, ckm, K.KEY_PAGEDOWN, 1, "\x1b[6~");

    // ── modifier가 넷에서 여덟으로 (IP-M2, design doc 결정 4) ────────────
    //
    // Alt 좌우(56/100)와 Meta 좌우(125/126)가 들어온다. IP-M0가 이 넷을
    // "관측 가능해지는 시점에 넣는다"며 미룬 이유가 아래 두 줄이다 —
    // modifier 비트만 있으면 반환값이 한 글자도 안 바뀌어서 검사가 성립하지
    // 않는다. 그 시점이 바로 다음 블록(조합 dispatch)이다.
    try expect(&state, K.KEY_LEFTALT, 1, ""); // 그 자체는 문자가 없다
    try expect(&state, K.KEY_LEFTALT, 0, "");
    try expect(&state, K.KEY_LEFTMETA, 1, ""); // 125는 keymap.len(58) 밖이다
    try expect(&state, K.KEY_LEFTMETA, 0, "");

    // ── Option 조합 (design doc 결정 8) ─────────────────────────────────
    //
    // 셸이 **이미 아는 언어**로 번역한다(A안). ESC 접두사는 터미널에서
    // "Meta+그 글자"를 뜻하는 오래된 관례이고, readline/zle/fish가 전부
    // 기본값으로 안다 — 설정 파일 없이 동작한다는 것이 A안을 고른 결정적
    // 이유였다(그래야 --no-config로 뜬 셸에서 게이트가 증명할 수 있다).
    try expect(&state, K.KEY_LEFTALT, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1bb"); // backward-word
    try expect(&state, K.KEY_RIGHT, 1, "\x1bf"); // forward-word
    try expect(&state, K.KEY_BACKSPACE, 1, "\x1b\x7f"); // backward-kill-word
    try expect(&state, K.KEY_DELETE, 1, "\x1bd"); // kill-word

    // 표에 없는 조합은 modifier를 무시하고 원래 키를 보낸다. Ctrl이 마스크
    // 대상이 아닌 문자(Ctrl+1 → '1')를 다루는 방식과 같은 규칙이다 —
    // 가로챌 것만 가로채고 나머지는 평소대로.
    try expect(&state, K.KEY_B, 1, "b"); // Option+b는 이번 범위가 아니다
    try expect(&state, K.KEY_UP, 1, "\x1b[A"); // Option+↑도 그냥 ↑
    try expect(&state, K.KEY_LEFTALT, 0, "");

    // 오른쪽 Alt(100)도 같다. 좌우를 따로 추적하는 이유는 Shift/Ctrl과
    // 같다 — 하나를 누른 채 다른 하나를 눌렀다 떼도 풀리면 안 된다.
    try expect(&state, K.KEY_RIGHTALT, 1, "");
    try expect(&state, K.KEY_LEFTALT, 1, "");
    try expect(&state, K.KEY_RIGHTALT, 0, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1bb"); // 여전히 Option
    try expect(&state, K.KEY_LEFTALT, 0, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1b[D"); // 이제 맨 ←

    // ── Cmd 조합 ────────────────────────────────────────────────────────
    //
    // 이쪽은 ESC 접두사가 아니라 **제어 문자 한 바이트**다. Cmd+←가 0x01
    // (Ctrl+A)인 이유는 그것이 readline의 beginning-of-line이기 때문이지
    // 무슨 대응 관계가 있어서가 아니다 — "셸이 이미 아는 언어"라는 것이
    // 유일한 기준이다.
    try expect(&state, K.KEY_LEFTMETA, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x01"); // beginning-of-line
    try expect(&state, K.KEY_RIGHT, 1, "\x05"); // end-of-line
    try expect(&state, K.KEY_BACKSPACE, 1, "\x15"); // 줄 앞부분 삭제

    // Cmd+Delete는 표에 없다 → 맨 Delete가 나간다.
    try expect(&state, K.KEY_DELETE, 1, "\x1b[3~");
    // Cmd+C / Cmd+V는 **일부러 비워둔 자리**다(design doc 비목표).
    // 복사·붙여넣기는 스크롤백과 클립보드가 선행 조건이라
    // project_copy_mode의 몫이고, 그때 이 두 줄이 바뀐다.
    try expect(&state, K.KEY_C, 1, "c");
    try expect(&state, K.KEY_V, 1, "v");
    try expect(&state, K.KEY_LEFTMETA, 0, "");

    try expect(&state, K.KEY_RIGHTMETA, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x01"); // 오른쪽 Meta(126)도 같다
    try expect(&state, K.KEY_RIGHTMETA, 0, "");

    // ── 둘 다 눌리면 Cmd가 이긴다 ───────────────────────────────────────
    //
    // 임의의 선택이지만 **결정적**이어야 한다. macOS에서 Cmd가 더 강한
    // modifier라는 직관과 맞고, 코드에서는 chord가 Meta를 먼저 보는 것으로
    // 표현된다. 이 줄이 그 순서를 못 박는다.
    try expect(&state, K.KEY_LEFTALT, 1, "");
    try expect(&state, K.KEY_LEFTMETA, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x01"); // ESC b가 아니라 0x01
    try expect(&state, K.KEY_LEFTMETA, 0, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1bb"); // Meta를 떼면 Option으로
    try expect(&state, K.KEY_LEFTALT, 0, "");

    // ── 조합은 DECCKM보다 강하다 ────────────────────────────────────────
    //
    // dispatch가 특수키 조회보다 **먼저** 오기 때문이다(design doc 결정 2의
    // "가로챌 것을 먼저"). Option+←는 DECCKM이 켜져 있어도 ESC b이고,
    // ESC O D로 바뀌지 않는다. 순서가 뒤집히면 이 줄이 먼저 터진다.
    try expectCtx(&state, ckm, K.KEY_LEFTALT, 1, "");
    try expectCtx(&state, ckm, K.KEY_LEFT, 1, "\x1bb");
    try expectCtx(&state, ckm, K.KEY_LEFTALT, 0, "");
    try expectCtx(&state, ckm, K.KEY_LEFT, 1, "\x1bOD"); // 조합이 없으면 다시 DECCKM

    // ── keyboard=pc: Alt와 Meta를 맞바꾼다 (IP-M2, design doc 결정 9) ────
    //
    // 스페이스 옆 두 키의 순서가 Apple과 PC에서 정확히 뒤집혀 있다.
    //   Apple: [Ctrl] [Option 56] [Cmd 125]
    //   PC:    [Ctrl] [Win 125]   [Alt 56]
    // 그래서 하는 일은 modifier를 기록하기 **전에** 코드를 맞바꾸는 것뿐이고,
    // 그 뒤 로직(chord, keymap, specialKey)은 어느 키보드인지 전혀 모른다.
    //
    // 이 검사가 게이트보다 중요한 이유가 하나 있다: 게이트는 QEMU가 보내는
    // 물리 키 하나만 볼 수 있지만, 여기서는 네 키를 다 볼 수 있다.
    const pc = input.Context{ .swap_alt_meta = true };

    // 물리 Alt(56)를 누르면 Meta로 기록된다 → Cmd 의미가 나온다.
    try expectCtx(&state, pc, K.KEY_LEFTALT, 1, "");
    try expectCtx(&state, pc, K.KEY_LEFT, 1, "\x01"); // ESC b가 아니라 0x01
    try expectCtx(&state, pc, K.KEY_RIGHT, 1, "\x05");
    try expectCtx(&state, pc, K.KEY_LEFTALT, 0, "");

    // 물리 Meta(125)를 누르면 Alt로 기록된다 → Option 의미가 나온다.
    try expectCtx(&state, pc, K.KEY_LEFTMETA, 1, "");
    try expectCtx(&state, pc, K.KEY_LEFT, 1, "\x1bb"); // 0x01이 아니라 ESC b
    try expectCtx(&state, pc, K.KEY_BACKSPACE, 1, "\x1b\x7f");
    try expectCtx(&state, pc, K.KEY_LEFTMETA, 0, "");

    // 오른쪽 짝(100↔126)도 같이 바뀐다. 왼쪽만 고치는 실수를 여기서 잡는다.
    try expectCtx(&state, pc, K.KEY_RIGHTALT, 1, "");
    try expectCtx(&state, pc, K.KEY_LEFT, 1, "\x01");
    try expectCtx(&state, pc, K.KEY_RIGHTALT, 0, "");
    try expectCtx(&state, pc, K.KEY_RIGHTMETA, 1, "");
    try expectCtx(&state, pc, K.KEY_LEFT, 1, "\x1bb");
    try expectCtx(&state, pc, K.KEY_RIGHTMETA, 0, "");

    // 교환은 **modifier 키에만** 일어난다. 글자 키는 그대로다.
    try expectCtx(&state, pc, K.KEY_A, 1, "a");
    try expectCtx(&state, pc, K.KEY_LEFT, 1, "\x1b[D");

    // 뗌 이벤트도 같은 ctx로 들어오므로 짝이 맞는다. 부팅 중에 keyboard
    // 설정이 바뀌는 일은 없다 — PID 1이 부팅 시점에 한 번 정해서 argv로
    // 넘기고, 그 값은 프로세스가 사는 동안 상수다.
    try expectCtx(&state, pc, K.KEY_LEFTALT, 1, "");
    try expectCtx(&state, pc, K.KEY_LEFTALT, 0, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1b[D"); // 아무 modifier도 안 남았다

    // ── 여전히 안 하는 것 ───────────────────────────────────────────────
    //
    // Ctrl+방향키(`ESC [ 1 ; 5 D`)와 Shift+방향키는 **IP-M2도 하지 않는다.**
    // IP-M1의 주석은 "M2의 조합 dispatch가 이 위에 얹히면서 바뀐다"고 적었지만
    // 그렇지 않았다 — 결정 8의 표에 있는 것은 Option과 Cmd 일곱 줄뿐이고,
    // Ctrl+방향키를 누를 이유가 있는 앱이 아직 하나도 없다(design doc 비목표:
    // "게이트가 볼 수 없는 표를 늘리지 않는다").
    //
    // 그래서 State.seq의 8바이트 중 이번에도 4바이트까지만 쓴다. 6바이트를
    // 쓰는 형태가 바로 이 `ESC [ 1 ; 5 D`다.
    try expect(&state, K.KEY_LEFTCTRL, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1b[D"); // Ctrl+← → 아직도 그냥 ←
    try expect(&state, K.KEY_LEFTCTRL, 0, "");

    try expect(&state, K.KEY_LEFTSHIFT, 1, "");
    try expect(&state, K.KEY_LEFT, 1, "\x1b[D"); // Shift+← → 아직도 그냥 ←
    try expect(&state, K.KEY_LEFTSHIFT, 0, "");

    // 특수키 사이의 빈 코드(F1 등)는 여전히 조용히 무시된다.
    try expect(&state, K.KEY_F1, 1, "");
    try expect(&state, K.KEY_INSERT, 1, "");

    std.debug.print("PASS\n", .{});
}
