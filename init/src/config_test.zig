const std = @import("std");
const config = @import("config.zig");

/// config.zig에서 유일하게 시스템 콜이 없는 함수가 parse다. HANDOFF가
/// "단위 테스트가 없다"고 오래 적어두고 있었는데, keyboard 키가 들어오면서
/// 파서의 분기가 둘이 된 지금이 그 저울을 놓을 자리다.
///
/// terminal/src/input_test.zig와 같은 모양(호스트 아키텍처 실행 파일,
/// 실패하면 0이 아닌 종료 코드)으로 맞춘다 — 체인 스크립트가 둘을 똑같이
/// 다룰 수 있어야 한다.
/// **필드 넷을 전부 비교한다.** HI-M2가 둘을 더하면서 넓혔는데, 안 넓혔다면
/// 새 키의 검사가 아무것도 안 보고 초록이 떴을 것이다 — 이 저장소가 반복해서
/// 부딪친 "통과했다와 볼 것이 없었다를 가르는" 자리다(SP-M0 실측 4).
fn expect(text: []const u8, want: config.Config) !void {
    const got = config.parse(text);
    if (got.shell == want.shell and got.keyboard == want.keyboard and
        got.hangul_layout == want.hangul_layout and
        got.latin_layout == want.latin_layout and
        // **`std.meta.eql`인 이유는 `Toggles`가 struct이기 때문이다** —
        // 앞의 넷은 enum이라 `==`가 되지만 이쪽은 필드 넷을 비교해야 한다.
        std.meta.eql(got.hangul_toggle, want.hangul_toggle)) return;
    var got_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    var want_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    std.debug.print(
        "FAIL: input={s}\n  got  shell={s} keyboard={s} hangul={s} latin={s} toggles={s}\n" ++
            "  want shell={s} keyboard={s} hangul={s} latin={s} toggles={s}\n",
        .{
            text,
            @tagName(got.shell),
            @tagName(got.keyboard),
            @tagName(got.hangul_layout),
            @tagName(got.latin_layout),
            got.hangul_toggle.arg(&got_buf),
            @tagName(want.shell),
            @tagName(want.keyboard),
            @tagName(want.hangul_layout),
            @tagName(want.latin_layout),
            want.hangul_toggle.arg(&want_buf),
        },
    );
    return error.UnexpectedConfig;
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
    // **다른 enum의 이름이 새어 들어가지 않는다.** `dvorak`은 이제
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
    // **자판 이름 여섯이 전부 파싱된다.** 이 여섯 줄이 `config.zig`의 enum과
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
    // **자판 이름이 서로 새어 들어가지 않는다.** `qwerty`는 `LatinLayout`의
    // 이름이지 `HangulLayout`의 이름이 아니다.
    try expect("hangul_layout=qwerty\n", .{});

    // HI 게이트가 심는 파일 그대로. **기본값이 아닌 값 하나를 심는 것이
    // 요점이다**(design 결정 14).
    try expect(
        "# HI 체인이 미리 심어 두는 설정\nhangul_layout=sebeol_3p3\n",
        .{ .hangul_layout = .sebeol_3p3 },
    );

    // ── HI-M3: hangul_toggle ────────────────────────────────────────────
    //
    // **이 키만 목록이다.** 앞의 넷은 하나를 고르지만 전환 키는 배타적이지
    // 않다 — 한/영 키를 쓰면서 CapsLock도 쓰는 것이 정상이다.
    const none = config.Toggles{};

    // 빈 값은 **뜻이 있는 입력이다.** `shell=`이 기본값으로 떨어지는 것과
    // 다르다 — 여기서 기본값으로 떨어지면 전환 키를 전부 끌 방법이 없어진다.
    try expect("hangul_toggle=\n", .{ .hangul_toggle = none });

    try expect("hangul_toggle=hangul_key\n", .{
        .hangul_toggle = .{ .hangul_key = true },
    });
    try expect("hangul_toggle=capslock_tap,lctrl_tap\n", .{
        .hangul_toggle = .{ .capslock_tap = true, .lctrl_tap = true },
    });

    // 공백과 순서. **정규화되므로 적은 순서는 결과에 안 남는다.**
    try expect("hangul_toggle= lctrl_tap , shift_space \n", .{
        .hangul_toggle = .{ .shift_space = true, .lctrl_tap = true },
    });

    // 모르는 이름 하나가 나머지를 안 죽인다. **"한 줄이 깨져도 살아남는다"는
    // 규칙이 목록 안에서도 서는지 보는 자리다.**
    try expect("hangul_toggle=hangul_key,nosuch,lctrl_tap\n", .{
        .hangul_toggle = .{ .hangul_key = true, .lctrl_tap = true },
    });

    // 빈 항목은 건너뛴다.
    try expect("hangul_toggle=,,\n", .{ .hangul_toggle = none });

    // **다른 키의 이름이 새어 들어가지 않는다.** `dubeol`은 자판 이름이고
    // `pc`는 키보드 이름이다 — 화이트리스트가 키마다 따로 선다.
    try expect("hangul_toggle=dubeol\n", .{ .hangul_toggle = none });
    try expect("hangul_toggle=pc\n", .{ .hangul_toggle = none });

    // 넷 다 — 기본값과 같다.
    try expect("hangul_toggle=hangul_key,shift_space,capslock_tap,lctrl_tap\n", .{});

    // HI 게이트가 심는 값. **`hangul_key`가 빠진 것이 요점이다** — 기본값과
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

    // ── `arg()` → `parse()` 왕복 ────────────────────────────────────────
    //
    // **이 왕복이 argv 배선의 계약이다.** init이 `arg()`로 쓰고 terminal이
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

    // **순서가 정규화된다는 것을 여기서 못 박는다.** 거꾸로 적어도 같은
    // 문자열이 나오므로, 게이트가 로그에서 읽는 값이 흔들리지 않는다.
    const reversed = config.Toggles.parse("lctrl_tap,capslock_tap,shift_space,hangul_key");
    var rev_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    if (!std.mem.eql(u8, reversed.arg(&rev_buf), all_text)) {
        std.debug.print("FAIL: Toggles.arg is not order-normalized\n", .{});
        return error.UnexpectedToggleArg;
    }

    // 빈 집합은 `none`이고, **그 `none`은 다시 빈 집합으로 돌아온다.**
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

    std.debug.print("PASS\n", .{});
}
