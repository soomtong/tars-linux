const std = @import("std");
const config = @import("config.zig");

/// `expectQuietSeed`가 훅을 몇 개까지 셀 수 있는가. 힙이 없어서 상한이
/// 필요하고, 지금은 셸마다 둘이다(`zoxide`·`fzf`). 늘리면 그 함수가 조용히
/// 덜 검사하는 대신 실패한다 — 상한이 검사를 좁히는 것보다 낫다.
const MAX_HOOK_LINES = 8;

/// 이 기계가 훅을 걸어야 하는 도구들. `hookLines()`가 이 둘을 전부 덮는지
/// 보는 것이 `expectHooksCoverTheTools`이고, 그것이 없으면 "씨앗과
/// `hookLines()`에서 함께 지우기"가 조용히 통과한다 — 정방향도 역방향도
/// 만족되기 때문이다.
///
/// 그 편집이 정당할 수도 있다(도구를 뺀다면). 그때는 이 배열을 먼저
/// 고쳐야 한다 — 손이 한 번 멈추는 자리를 만드는 것이 이 배열의 전부다.
const HOOKED_TOOLS = [_][]const u8{ "zoxide", "fzf" };

/// config.zig에서 유일하게 시스템 콜이 없는 함수가 parse다. HANDOFF가
/// "단위 테스트가 없다"고 오래 적어두고 있었는데, keyboard 키가 들어오면서
/// 파서의 분기가 둘이 된 지금이 그 저울을 놓을 자리다.
///
/// terminal/src/input_test.zig와 같은 모양(호스트 아키텍처 실행 파일,
/// 실패하면 0이 아닌 종료 코드)으로 맞춘다 — 체인 스크립트가 둘을 똑같이
/// 다룰 수 있어야 한다.
/// 필드 넷을 전부 비교한다. HI-M2가 둘을 더하면서 넓혔는데, 안 넓혔다면
/// 새 키의 검사가 아무것도 안 보고 초록이 떴을 것이다 — 이 저장소가 반복해서
/// 부딪친 "통과했다와 볼 것이 없었다를 가르는" 자리다(SP-M0 실측 4).
fn expect(text: []const u8, want: config.Config) !void {
    const got = config.parse(text);
    if (got.shell == want.shell and got.keyboard == want.keyboard and
        got.hangul_layout == want.hangul_layout and
        got.latin_layout == want.latin_layout and
        // SC-M0: 여섯째 필드. 이 줄이 없으면 아래 shell_config 검사가
        // 아무것도 안 보고 초록으로 지나간다 — 이 함수의 머리 주석이
        // HI-M2에 대해 적어 둔 것과 글자 그대로 같은 자리다.
        got.shell_config == want.shell_config and
        // `std.meta.eql`인 이유는 `Toggles`가 struct이기 때문이다 —
        // 앞의 넷은 enum이라 `==`가 되지만 이쪽은 필드 넷을 비교해야 한다.
        std.meta.eql(got.hangul_toggle, want.hangul_toggle)) return;
    var got_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    var want_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    std.debug.print(
        "FAIL: input={s}\n  got  shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s}\n" ++
            "  want shell={s} keyboard={s} hangul={s} latin={s} toggles={s} shell_config={s}\n",
        .{
            text,
            @tagName(got.shell),
            @tagName(got.keyboard),
            @tagName(got.hangul_layout),
            @tagName(got.latin_layout),
            got.hangul_toggle.arg(&got_buf),
            @tagName(got.shell_config),
            @tagName(want.shell),
            @tagName(want.keyboard),
            @tagName(want.hangul_layout),
            @tagName(want.latin_layout),
            want.hangul_toggle.arg(&want_buf),
            @tagName(want.shell_config),
        },
    );
    return error.UnexpectedConfig;
}

/// 씨앗 rc가 쓸 수 있는 줄을 담고 있는지 확인한다(SC-M1, SM-M1이 넓혔다).
///
/// 셋 다 문법이 다른 셸의 파일이라 우리가 파싱할 수는 없다. 대신 우리가
/// 쓸 수 있는 줄의 종류를 제한한다.
///
/// | | 종류 | 왜 조용한가 |
/// |---|---|---|
/// | SC-M1 | 주석 | 셸이 안 읽는다 |
/// | SC-M1 | `alias …` | 정의만 하고 실행하지 않는다 |
/// | SM-M1 | `hookLines()`의 한 줄과 글자 그대로 같은 줄 | 실측 23이 셋 다 0바이트를 쟀다 |
///
/// SM-M1이 문법 범주가 아니라 정확 허용 목록으로 넓힌 이유(design 결정 6):
/// *"주석 · alias · `eval` 세 범주"*로 넓히면 `eval` 뒤에 아무 문장이나 올 수
/// 있고, 그러면 이 규칙이 막으려던 것이 정확히 그것이다.
///
/// 역방향도 본다. 정방향만으로는 훅을 지우는 것이 통과한다 — 아무
/// 줄도 안 남으면 위반할 줄도 없기 때문이다.
///
/// 위험 3의 반쪽이 여기 있다. design이 *"우리가 까는 것은 절대로 셸을
/// 죽이지 않아야 한다"*고 적었고, 그 "절대로"를 지키는 장치가 이 함수다.
fn expectQuietSeed(sh: config.Shell) !void {
    const text = sh.rcSeed();
    if (text.len == 0 or text[text.len - 1] != '\n') {
        std.debug.print("FAIL: the {s} seed does not end with a newline\n", .{@tagName(sh)});
        return error.BadSeed;
    }
    const hooks = sh.hookLines();
    // 훅이 씨앗에서 보였는가. 힙이 없으므로 상한이 필요하고, 지금 둘이다 —
    // 넘치면 조용히 덜 검사하지 말고 여기서 죽는다.
    var seen = [_]bool{false} ** MAX_HOOK_LINES;
    if (hooks.len > seen.len) {
        std.debug.print("FAIL: the {s} shell has {d} hook lines; raise MAX_HOOK_LINES\n", .{
            @tagName(sh), hooks.len,
        });
        return error.BadSeed;
    }
    var lines = std.mem.splitScalar(u8, text, '\n');
    var aliases: usize = 0;
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;
        if (std.mem.startsWith(u8, line, "alias ")) {
            aliases += 1;
            continue;
        }
        // `startsWith`가 아니라 `eql`이다. 접두사로 보면
        // `command -v zoxide >/dev/null && rm -rf /`가 통과한다.
        var is_hook = false;
        for (hooks, 0..) |hook, i| {
            if (!std.mem.eql(u8, line, hook)) continue;
            seen[i] = true;
            is_hook = true;
            break;
        }
        if (is_hook) continue;
        std.debug.print(
            "FAIL: the {s} seed has a line that is not a comment, not an alias,\n" ++
                "      and not one of its hook lines:\n  {s}\n" ++
                "      the hook lines are:\n",
            .{ @tagName(sh), line },
        );
        for (hooks) |hook| std.debug.print("        {s}\n", .{hook});
        return error.BadSeed;
    }
    // ── 역방향 — 훅을 지우는 것이 통과하지 않게 한다 ──────────────────
    for (hooks, 0..) |hook, i| {
        if (seen[i]) continue;
        std.debug.print(
            "FAIL: the {s} seed does not carry its hook line:\n  {s}\n",
            .{ @tagName(sh), hook },
        );
        return error.BadSeed;
    }
    // alias가 하나도 없으면 1차 부팅의 `tars-config`가 무의미해진다.
    // 게이트는 그 alias가 있다는 것으로 "셸이 이 파일을 읽었다"를 판정한다.
    if (aliases == 0) {
        std.debug.print("FAIL: the {s} seed defines no alias for the gate to find\n", .{@tagName(sh)});
        return error.BadSeed;
    }
    // 씨앗은 자기 파일의 이름을 자기 안에 적는다. 그 이름이 틀리면 사용자가
    // `tars-rc`를 쳤을 때 없는 파일을 cat한다 — 문서가 아니라 실행되는
    // 문장이라 틀린 것이 드러난다.
    if (std.mem.indexOf(u8, text, sh.rcPath()) == null) {
        std.debug.print("FAIL: the {s} seed never names its own path {s}\n", .{
            @tagName(sh), sh.rcPath(),
        });
        return error.BadSeed;
    }
}

/// 훅 목록이 도구 둘 다에 훅을 거는가(SM-M1).
///
/// `expectQuietSeed`의 양방향으로는 안 닫히는 길이 하나 있다 — 씨앗과
/// `hookLines()`에서 함께 지우면 정방향(위반할 줄이 없다)도
/// 역방향(찾을 훅이 없다)도 만족된다. 그 길을 닫는 것이 이 함수다.
///
/// 도구 이름이 훅 줄에 들어 있는지만 본다. 훅이 실제로 도는 것은 호스트가
/// 증명할 수 없고, `config/check.sh`의 7차 부팅이 그것을 본다 — 여기가 보는
/// 것은 *"우리가 그 둘을 걸려고 했다"*까지다.
fn expectHooksCoverTheTools(sh: config.Shell) !void {
    const hooks = sh.hookLines();
    for (HOOKED_TOOLS) |tool| {
        var found = false;
        for (hooks) |hook| {
            if (std.mem.indexOf(u8, hook, tool) != null) {
                found = true;
                break;
            }
        }
        if (found) continue;
        std.debug.print("FAIL: no {s} hook line for the {s} seed\n", .{ tool, @tagName(sh) });
        return error.BadSeed;
    }
}

/// 히스토리 env가 셸의 성질과 맞는가(SM-M2 design 결정 3).
///
/// `expectQuietSeed`와 짝이 아니다 — 이 milestone은 씨앗을 안 건드린다.
/// 히스토리는 rc가 아니라 env로 세우고(실측 9·10·11), 그 결정이 옳은지는
/// `config/check.sh`의 8차 부팅이 본다. 여기가 보는 것은 우리가 셸마다
/// 무엇을 주려고 했는가까지다.
///
/// 보는 것 셋:
///   1. 개수가 셸의 성질과 맞다 — fish 0 · bash 2 · zsh 3
///   2. 모든 항목이 `NAME=VALUE`이고 이름이 셋 중 하나다
///   3. `SAVEHIST`는 zsh만 받는다 — 실측 9를 코드 모양으로 못 박는 줄이다
fn expectHistEntries(sh: config.Shell) !void {
    const want_len: usize = switch (sh) {
        .fish => 0,
        .bash => 2,
        .zsh => 3,
    };
    const entries = sh.histEntries();
    if (entries.len != want_len) {
        std.debug.print("FAIL: the {s} shell carries {d} history env entries, want {d}\n", .{
            @tagName(sh), entries.len, want_len,
        });
        return error.BadHistEnv;
    }

    var saw_savehist = false;
    for (entries) |e| {
        const eq = std.mem.indexOfScalar(u8, e, '=') orelse {
            std.debug.print("FAIL: history env \"{s}\" is not NAME=VALUE\n", .{e});
            return error.BadHistEnv;
        };
        const name = e[0..eq];
        if (std.mem.eql(u8, name, "SAVEHIST")) saw_savehist = true;
        if (!std.mem.eql(u8, name, "HISTFILE") and
            !std.mem.eql(u8, name, "HISTSIZE") and
            !std.mem.eql(u8, name, "SAVEHIST"))
        {
            std.debug.print("FAIL: the {s} shell wants an unexpected env {s}\n", .{
                @tagName(sh), name,
            });
            return error.BadHistEnv;
        }
    }
    if ((sh == .zsh) != saw_savehist) {
        std.debug.print("FAIL: SAVEHIST belongs to zsh alone; the {s} shell has it: {}\n", .{
            @tagName(sh), saw_savehist,
        });
        return error.BadHistEnv;
    }
}

/// cmdline 한 줄이 rc를 끄는가(SC-M2 결정 9).
///
/// `expect`와 같은 자리에 있는 함수다 — `config.zig`에서 시스템 콜이
/// 없는 부분이 이제 둘이고, 둘 다 게스트를 안 띄우고 검증할 수 있다.
fn expectCmdline(text: []const u8, want: bool) !void {
    const got = config.cmdlineWantsNoConfig(text);
    if (got == want) return;
    std.debug.print("FAIL: cmdline \"{s}\" gave {}, want {}\n", .{ text, got, want });
    return error.UnexpectedCmdline;
}

pub fn main() !void {
    // 빈 입력은 기본값이다. 이 한 줄이 "설정 파일이 없을 때의 TARS"를 못
    // 박는다 — Config의 기본값을 바꾸면 여기가 먼저 터진다.
    try expect("", .{});

    // 각 키 하나씩.
    try expect("shell=zsh\n", .{ .shell = .zsh });
    try expect("keyboard=pc\n", .{ .keyboard = .pc });

    // 둘이 함께. IP 체인의 2차 부팅이 실제로 쓰는 조합이다.
    try expect("shell=bash\nkeyboard=pc\n", .{ .shell = .bash, .keyboard = .pc });

    // 주석·빈 줄·양쪽 공백. 사람이 손으로 고치는 파일이라 이 셋이 규칙이다.
    try expect("# a comment\n\n  shell = zsh  \n", .{ .shell = .zsh });

    // CRLF. 호스트에서 편집한 파일을 넣었을 때 값이 "zsh\r"이 되면 원인을
    // 찾기 어렵다 — trim이 \r까지 떼는 이유다.
    try expect("shell=zsh\r\nkeyboard=pc\r\n", .{ .shell = .zsh, .keyboard = .pc });

    // 마지막 줄에 개행이 없어도 된다.
    try expect("keyboard=pc", .{ .keyboard = .pc });

    // ── 깨진 입력은 전부 기본값으로 떨어진다 ────────────────────────────
    //
    // 이것이 CP design doc의 "설정 하나로 부팅이 막히지 않게 하는 장치"다.
    // 어느 줄도 예외를 던지지 않고, 어느 줄도 부팅을 멈추지 않는다.
    try expect("shell=nushell\n", .{}); // enum에 없는 셸
    // 다른 enum의 이름이 새어 들어가지 않는다. `dvorak`은 이제
    // `LatinLayout`의 이름이지만 `Keyboard`에는 없다 — 화이트리스트가
    // 키마다 따로 선다는 뜻이다.
    try expect("keyboard=dvorak\n", .{});
    try expect("colour=red\n", .{}); // 모르는 키
    try expect("no equals here\n", .{}); // '=' 없음
    try expect("=value\n", .{}); // 키 없음
    try expect("shell=\n", .{}); // 값 없음

    // shell=/etc/passwd 같은 입력이 애초에 성립하지 않는다는 것 —
    // 화이트리스트가 이름만 받고 경로를 안 받는다는 설계의 증거다.
    try expect("shell=/usr/bin/fish\n", .{});

    // 첫 번째 '='에서만 나눈다. 값 쪽에 '='가 남으면 enum에 없는 이름이 된다.
    try expect("shell=zsh=extra\n", .{});

    // 뒤에 오는 줄이 이긴다. "마지막이 이긴다"는 정책을 못 박아 둔다.
    try expect("shell=zsh\nshell=bash\n", .{ .shell = .bash });

    // 한 줄이 깨져도 나머지 줄은 살아남는다. 이 성질이 없으면 오타 하나가
    // 파일 전체를 무효로 만든다.
    try expect("shell=nope\nkeyboard=pc\n", .{ .keyboard = .pc });

    // ── HI-M2: 자판 두 줄 ───────────────────────────────────────────────
    //
    // 자판 이름 여섯이 전부 파싱된다. 이 여섯 줄이 `config.zig`의 enum과
    // `terminal/src/hangul.zig`의 `Layout`을 잇는 문자열을 못 박는다 — 둘을
    // 잇는 것은 argv의 문자열뿐이라 컴파일러가 안 잡아 준다.
    try expect("hangul_layout=dubeol\n", .{ .hangul_layout = .dubeol });
    try expect("hangul_layout=sebeol_3p3\n", .{ .hangul_layout = .sebeol_3p3 });
    try expect("hangul_layout=shin_p2\n", .{ .hangul_layout = .shin_p2 });
    try expect("hangul_layout=shin_pcs\n", .{ .hangul_layout = .shin_pcs });
    try expect("latin_layout=qwerty\n", .{ .latin_layout = .qwerty });
    try expect("latin_layout=dvorak\n", .{ .latin_layout = .dvorak });

    // 넷이 함께. 다른 키를 안 건드린다는 것까지 본다.
    try expect(
        "shell=bash\nkeyboard=pc\nhangul_layout=sebeol_3p3\nlatin_layout=dvorak\n",
        .{
            .shell = .bash,
            .keyboard = .pc,
            .hangul_layout = .sebeol_3p3,
            .latin_layout = .dvorak,
        },
    );

    // 깨진 값은 기본값(shin_pcs · qwerty)에 머문다.
    try expect("hangul_layout=sebul\n", .{});
    try expect("latin_layout=colemak\n", .{});
    // 자판 이름이 서로 새어 들어가지 않는다. `qwerty`는 `LatinLayout`의
    // 이름이지 `HangulLayout`의 이름이 아니다.
    try expect("hangul_layout=qwerty\n", .{});

    // HI 게이트가 심는 파일 그대로. 기본값이 아닌 값 하나를 심는 것이
    // 요점이다(design 결정 14).
    try expect(
        "# HI 체인이 미리 심어 두는 설정\nhangul_layout=sebeol_3p3\n",
        .{ .hangul_layout = .sebeol_3p3 },
    );

    // ── HI-M3: hangul_toggle ────────────────────────────────────────────
    //
    // 이 키만 목록이다. 앞의 넷은 하나를 고르지만 전환 키는 배타적이지
    // 않다 — 한/영 키를 쓰면서 CapsLock도 쓰는 것이 정상이다.
    const none = config.Toggles{};

    // 빈 값은 뜻이 있는 입력이다. `shell=`이 기본값으로 떨어지는 것과
    // 다르다 — 여기서 기본값으로 떨어지면 전환 키를 전부 끌 방법이 없어진다.
    try expect("hangul_toggle=\n", .{ .hangul_toggle = none });

    try expect("hangul_toggle=hangul_key\n", .{
        .hangul_toggle = .{ .hangul_key = true },
    });
    try expect("hangul_toggle=capslock_tap,lctrl_tap\n", .{
        .hangul_toggle = .{ .capslock_tap = true, .lctrl_tap = true },
    });

    // 공백과 순서. 정규화되므로 적은 순서는 결과에 안 남는다.
    try expect("hangul_toggle= lctrl_tap , shift_space \n", .{
        .hangul_toggle = .{ .shift_space = true, .lctrl_tap = true },
    });

    // 모르는 이름 하나가 나머지를 안 죽인다. "한 줄이 깨져도 살아남는다"는
    // 규칙이 목록 안에서도 서는지 보는 자리다.
    try expect("hangul_toggle=hangul_key,nosuch,lctrl_tap\n", .{
        .hangul_toggle = .{ .hangul_key = true, .lctrl_tap = true },
    });

    // 빈 항목은 건너뛴다.
    try expect("hangul_toggle=,,\n", .{ .hangul_toggle = none });

    // 다른 키의 이름이 새어 들어가지 않는다. `dubeol`은 자판 이름이고
    // `pc`는 키보드 이름이다 — 화이트리스트가 키마다 따로 선다.
    try expect("hangul_toggle=dubeol\n", .{ .hangul_toggle = none });
    try expect("hangul_toggle=pc\n", .{ .hangul_toggle = none });

    // 넷 다 — 기본값과 같다.
    try expect("hangul_toggle=hangul_key,shift_space,capslock_tap,lctrl_tap\n", .{});

    // HI 게이트가 심는 값. `hangul_key`가 빠진 것이 요점이다 — 기본값과
    // 달라야 게이트 검사 0이 뜻을 갖는다(design 결정 14와 같은 논리).
    try expect("hangul_toggle=shift_space,capslock_tap,lctrl_tap\n", .{
        .hangul_toggle = .{
            .shift_space = true,
            .capslock_tap = true,
            .lctrl_tap = true,
        },
    });

    // 다섯 키가 함께. 다른 키를 안 건드린다는 것까지 본다.
    try expect(
        "shell=bash\nkeyboard=pc\nhangul_layout=sebeol_3p3\nlatin_layout=dvorak\n" ++
            "hangul_toggle=capslock_tap\n",
        .{
            .shell = .bash,
            .keyboard = .pc,
            .hangul_layout = .sebeol_3p3,
            .latin_layout = .dvorak,
            .hangul_toggle = .{ .capslock_tap = true },
        },
    );

    // ── SC-M0: 여섯째 키 ────────────────────────────────────────────────
    //
    // 앞의 다섯과 완전히 같은 모양이다(hangul_toggle만 다르다).
    // enum이 화이트리스트이고, 모르는 값은 기본값에 머문다.
    try expect("shell_config=off\n", .{ .shell_config = .off });
    // 기본값을 명시적으로 적는 것도 통과한다. 씨앗 파일이 실제로 그렇게
    // 생겼으므로 이 왕복이 참이어야 한다.
    try expect("shell_config=on\n", .{});
    try expect("shell_config=yes\n", .{}); // enum에 없는 값
    try expect("shell_config=\n", .{}); // 값 없음
    // 다른 키와 섞여도 각자 선다. 깨진 줄 하나가 파일 전체를 무효로 만들지
    // 않는다는 성질이 여섯째 키에도 그대로 적용된다.
    try expect("shell=zsh\nshell_config=off\n", .{ .shell = .zsh, .shell_config = .off });

    // ── `arg()` → `parse()` 왕복 ────────────────────────────────────────
    //
    // 이 왕복이 argv 배선의 계약이다. init이 `arg()`로 쓰고 terminal이
    // 같은 문법으로 읽는데, 둘을 잇는 것은 문자열 하나뿐이라 컴파일러가 못
    // 잡는다 — `HangulLayout` ↔ `hangul.Layout`과 정확히 같은 자리다.
    var arg_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    const all = config.Toggles{
        .hangul_key = true,
        .shift_space = true,
        .capslock_tap = true,
        .lctrl_tap = true,
    };
    const all_text = all.arg(&arg_buf);
    if (!std.mem.eql(u8, all_text, "hangul_key,shift_space,capslock_tap,lctrl_tap")) {
        std.debug.print("FAIL: Toggles.arg gave \"{s}\"\n", .{all_text});
        return error.UnexpectedToggleArg;
    }
    if (!std.meta.eql(config.Toggles.parse(all_text), all)) {
        std.debug.print("FAIL: Toggles.arg -> parse did not round-trip\n", .{});
        return error.ToggleRoundTripFailed;
    }

    // 순서가 정규화된다는 것을 여기서 못 박는다. 거꾸로 적어도 같은
    // 문자열이 나오므로, 게이트가 로그에서 읽는 값이 흔들리지 않는다.
    const reversed = config.Toggles.parse("lctrl_tap,capslock_tap,shift_space,hangul_key");
    var rev_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    if (!std.mem.eql(u8, reversed.arg(&rev_buf), all_text)) {
        std.debug.print("FAIL: Toggles.arg is not order-normalized\n", .{});
        return error.UnexpectedToggleArg;
    }

    // 빈 집합은 `none`이고, 그 `none`은 다시 빈 집합으로 돌아온다.
    // 파서가 이 이름 하나를 명시적으로 건너뛰기 때문이고, 안 그러면 전환 키를
    // 다 끈 사람의 부팅 로그에 매번 "모르는 이름 none"이 찍힌다.
    var none_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    const none_text = none.arg(&none_buf);
    if (!std.mem.eql(u8, none_text, "none")) {
        std.debug.print("FAIL: empty Toggles gave \"{s}\", want \"none\"\n", .{none_text});
        return error.UnexpectedToggleArg;
    }
    if (!std.meta.eql(config.Toggles.parse(none_text), none)) {
        std.debug.print("FAIL: \"none\" did not round-trip to an empty set\n", .{});
        return error.ToggleRoundTripFailed;
    }

    // ── SC-M1: 씨앗 rc의 불변식 ─────────────────────────────────────────
    //
    // 이 검사의 목적은 지금 통과하는 것이 아니라 나중에 막는 것이다.
    // 설정 디스크를 붙이는 체인이 다섯이고(design 실측 4) 그중 셋이 화면의
    // 셀 좌표로 판정한다. 씨앗이 부팅할 때 한 글자라도 찍으면 그 좌표가
    // 통째로 밀리고, 증상은 부팅 20초 뒤에 엉뚱한 체인이 깨지는 것이다.
    //
    // 그래서 규칙을 코드 모양으로 못 박는다: 주석이 아닌 줄은 `alias `로
    // 시작하거나 그 셸의 훅 줄과 글자 그대로 같다.
    //
    // ── SM-M1: 그 문을 두 줄만큼 넓혔다 ─────────────────────────────────
    //
    // 넓히는 방법이 정확 허용 목록인 이유가 design 결정 6이고, 검사가
    // 셋인 이유는 각각 다른 실수를 막기 때문이다.
    //
    //   정방향  씨앗에 아무 문장이나 들어오는 것
    //   역방향  훅을 지우는 것이 통과하는 것
    //   덮개    씨앗과 hookLines()에서 함께 지우는 것
    for (std.enums.values(config.Shell)) |sh| try expectQuietSeed(sh);
    for (std.enums.values(config.Shell)) |sh| try expectHooksCoverTheTools(sh);

    // ── SM-M2: 히스토리 env ─────────────────────────────────────────────
    for (std.enums.values(config.Shell)) |sh| try expectHistEntries(sh);
    // bash와 zsh가 같은 파일을 보면 안 된다. 형식이 다르다 — zsh는
    // `: <ts>:<dur>;<cmd>`, bash는 평문이라 섞이면 서로의 것을 못 읽는다.
    // 위 함수는 항목을 하나씩만 보므로 이 한 줄이 따로 필요하다.
    if (std.mem.eql(u8, config.Shell.bash.histEntries()[0], config.Shell.zsh.histEntries()[0])) {
        std.debug.print("FAIL: bash and zsh point HISTFILE at the same file\n", .{});
        return error.BadHistEnv;
    }

    // ── SC-M2: cmdline 토큰 ─────────────────────────────────────────────
    //
    // 탈출로 2의 전부가 이 함수 하나다(design 결정 9). rc가 셸을 죽이면
    // `tars.conf`를 고칠 자리가 사라지므로, 그때 사람이 쥘 수 있는 것은
    // 부팅 순간의 cmdline 한 단어뿐이다(실측 12 — 실기는 limine 메뉴를
    // 지난다).
    //
    // 토큰으로 본다. 부분 문자열로 찾으면 아래 넷째·다섯째 줄이 참이
    // 되고, 그 실수의 증상은 "부팅했더니 rc가 안 읽힌다" 하나뿐이라 원인에서
    // 아주 멀다.
    try expectCmdline("console=ttyS0", false);
    try expectCmdline("console=ttyS0 tars.noconfig", true);
    try expectCmdline("tars.noconfig console=ttyS0", true);
    try expectCmdline("console=ttyS0 tars.noconfigured", false);
    try expectCmdline("console=ttyS0 nottars.noconfig", false);
    // 실제 cmdline은 줄바꿈으로 끝난다(`/proc/cmdline`이 그렇다).
    try expectCmdline("console=ttyS0 tars.noconfig\n", true);
    // 빈 cmdline도 정상 입력이다.
    try expectCmdline("", false);
    // 값이 붙어도 받는다. 이 토큰은 있고 없음이 전부이고 값은 뜻이
    // 없다 — 끄는 방법은 `tars.noconfig=0`이 아니라 안 적는 것이다.
    // 받아 주지 않으면 `=1`을 적은 사람이 아무 일도 안 일어나는 것을 보고
    // 탈출로가 아예 없다고 믿는다.
    try expectCmdline("tars.noconfig=1", true);
    try expectCmdline("tars.noconfig=0", true);

    std.debug.print("PASS\n", .{});
}
