const std = @import("std");
const hangul = @import("hangul.zig");
const input = @import("input.zig");
const dictation = @import("dictation.zig");

/// 칸 사이를 벌리는 두 칸. 한 칸이 아닌 이유는 자판 이름 안에 이미 공백이
/// 있기 때문이다(`공세벌 3-P3`) — 한 칸으로 벌리면 칸 경계와 이름 안의 공백이
/// 눈으로도 게이트로도 안 갈린다.
const GAP = "  ";

/// 한글 자판의 사람이 읽는 이름(IS design 결정 4).
///
/// `else`를 안 단다. 자판을 다섯째로 더하는 사람이 이름을 빼먹으면 그
/// 순간 컴파일 에러가 난다. 배열이나 map으로 만들면 그 실수가 조용히 통과하고
/// 증상은 화면에 빈 칸이 뜨거나 엉뚱한 이름이 뜨는 것이다 — HI-M2 실측 6이
/// "이 위험은 '표를 옮긴다'가 아니라 '사람이 읽고 다시 적는다'에 딸려
/// 있었다"고 적어 둔 그 위험이다.
fn hangulName(l: hangul.Layout) []const u8 {
    return switch (l) {
        .dubeol => "두벌식",
        .sebeol_3p3 => "공세벌 3-P3",
        .shin_p2 => "신세벌 P2",
        .shin_pcs => "신세벌 PCS",
    };
}

/// 영문 자판의 사람이 읽는 이름. 같은 이유로 `else`가 없다.
fn latinName(l: input.LatinLayout) []const u8 {
    return switch (l) {
        .qwerty => "쿼티",
        .dvorak => "드보락",
    };
}

/// `CAPS` 칸의 글자. 상태와 무관하게 언제나 이 넉 자다(design 결정 3) —
/// 켜짐과 꺼짐은 글자가 아니라 색으로 가른다. `CAPS`와 `caps`로 가르지
/// 않는 것은 흘깃 봐서 같아 보이기 때문이고, 칸을 아예 지우지 않는 것은
/// 문자열 길이가 수시로 바뀌면 눈도 게이트도 어렵기 때문이다(결정 2).
///
/// `main.zig`가 이 이름을 쓴다. 상태 줄의 꼬리 `CAPS.len` 바이트만 다른
/// 색으로 그리는데, 그 길이를 저쪽에 4로 다시 적으면 여기를 고친 사람이
/// 저쪽을 안 고쳐도 컴파일이 통과한다.
pub const CAPS = "CAPS";

/// copy mode에 있을 때만 꼬리에 붙는 다섯째 칸(CI design 결정 2).
///
/// `CAPS`와 달리 자리를 남기지 않는다. 대문자 잠금은 켜 둔 것을 잊어도
/// 다른 흔적이 없어서 자리를 남겼지만, copy mode는 켜졌을 때만 뜻이 있는
/// 모드다 — vim이 normal에서 모드 이름을 안 적는 것과 같다. 그리고 꺼진
/// 화면이 한 픽셀도 안 바뀌어야 hangul 체인의 `text=` 비교가 그대로 선다.
///
/// `main.zig`가 이 이름을 쓴다. `drawStatus`가 꼬리에서 `CAPS`의 시작을
/// 셀 때 이 길이만큼 더 물러나야 하기 때문이다 — 길이를 저쪽에 다시 적지
/// 않는 이유는 `CAPS`와 같다.
pub const COPY = "COPY";

/// `COPY` 칸이 줄에 더하는 바이트. 칸을 가르는 `GAP`을 포함한다 —
/// `drawStatus`가 물러나야 하는 길이가 이것이고, `MAX_LEN`이 더하는 것도
/// 이것이다. 둘이 같은 이름을 보게 하면 하나만 고치는 사고가 없다.
pub const COPY_TAIL = GAP ++ COPY;

/// 워크스페이스 칸의 머리글자(WP design 결정 8). 칸은 `W2`처럼 이 글자 뒤에
/// 숫자 한 자리다.
pub const WS_PREFIX = "W";

/// 워크스페이스 칸이 줄에 더하는 바이트. `GAP` + `W` + 숫자 한 자리다.
///
/// 숫자가 한 자리인 것은 워크스페이스가 아홉까지이기 때문이다(`Cmd+1`~`9`가
/// 번호다). 두 자리를 만들 길이 없으므로 여기서도 셈하지 않는다.
///
/// `main.zig`가 이 이름을 쓴다 — `drawStatus`가 꼬리에서 `CAPS`의 시작을
/// 셀 때 이 길이만큼 더 물러난다. `COPY_TAIL`과 같은 이유다.
pub const WS_TAIL_LEN = GAP.len + WS_PREFIX.len + 1;

/// 받아쓰기 칸의 글자(VD-M1, design 결정 11). 꼬리의 맨 끝이고, 받아쓰기가 무엇을
/// 하고 있거나 방금 무엇으로 끝났을 때만 뜬다 — `COPY`와 같은 규칙이다. 받아쓰기를
/// 안 쓰는 화면은 한 글자도 안 바뀐다.
///
/// 영어 대문자인 것은 `CAPS` · `COPY`와 같은 줄에 서기 때문이다. 알림 다섯은 사람이
/// 고칠 것을 말한다 — `NO KEY`는 `/config/groq.key`, `NO MIC`는 장치, `PASSWORD`는
/// 비밀번호 프롬프트라 안 넣었다는 것, `NO PANE`은 말을 시작한 패널이 닫혔다는 것이다
/// (글자는 `/config/dictation.jsonl`에 있다). `FAILED`의 까닭은 시리얼의
/// `tars-dictate:` 줄에 있다.
///
/// `else`를 안 단다. `hangulName`과 같은 이유다 — `dictation.Show`에 여섯째 알림을
/// 더하는 사람이 글자를 빼먹으면 그 순간 컴파일 에러가 난다.
fn dictWord(s: dictation.Show) []const u8 {
    return switch (s) {
        .rec => "REC",
        .wait => "WAIT",
        .no_mic => "NO MIC",
        .no_key => "NO KEY",
        .failed => "FAILED",
        .password => "PASSWORD",
        .no_pane => "NO PANE",
    };
}

/// 받아쓰기 칸이 줄에 더하는 바이트. `GAP`을 포함한다. `main.zig`의 `drawStatus`가
/// 꼬리에서 이만큼 물러나 `COPY` · 워크스페이스 · `CAPS`의 자리를 센다 —
/// `COPY_TAIL`과 같은 이유로 길이를 저쪽에 다시 적지 않는다.
pub fn dictTailLen(s: dictation.Show) usize {
    return GAP.len + dictWord(s).len;
}

/// 상태 줄이 쓸 수 있는 가장 긴 바이트 수.
///
/// 이름 표에서 직접 센다(design 결정 5). `promptText`가 173을 주석의
/// 산수로 정당화한 것과 다른데, 여기는 값의 집합이 닫혀 있기 때문이다 —
/// needle 같은 가변 입력이 없고 자판 이름이 여섯, 한/영이 둘뿐이다.
/// 그래서 자판을 더하는 사람이 버퍼를 같이 안 늘려도 컴파일러가 맞춰
/// 준다. `hangulName`의 `switch`와 같은 종류의 못이다.
///
/// 한/영 칸은 `한`(3)과 `EN`(2) 중 긴 쪽인 3이다. `CAPS` 칸은 길이가 하나뿐
/// 이라 그대로 더한다.
///
/// IS-M1에서 30이 36이 됐고, CI-M0에서 36이 42가 됐고, WP-M2에서 42가 46이
/// 됐고, VD-M1에서 46이 56이 됐다(받아쓰기 칸의 가장 긴 글자 `PASSWORD`). 버퍼를
/// 손으로 늘린 자리는 넷 다 없다.
pub const MAX_LEN: usize = blk: {
    var hl: usize = 0;
    for (std.enums.values(hangul.Layout)) |t| {
        if (hangulName(t).len > hl) hl = hangulName(t).len;
    }
    var ll: usize = 0;
    for (std.enums.values(input.LatinLayout)) |t| {
        if (latinName(t).len > ll) ll = latinName(t).len;
    }
    var dl: usize = 0;
    for (std.enums.values(dictation.Show)) |s| {
        if (dictTailLen(s) > dl) dl = dictTailLen(s);
    }
    break :blk 3 + GAP.len + hl + GAP.len + ll + GAP.len + CAPS.len + WS_TAIL_LEN + COPY_TAIL.len + dl;
};

/// `buf`의 `at`부터 `s`를 쓰고 쓴 길이를 돌려준다.
fn put(buf: []u8, at: usize, s: []const u8) usize {
    @memcpy(buf[at..][0..s.len], s);
    return s.len;
}

/// 상태 줄 한 줄을 만든다.
///
/// 시스템 콜도 프레임버퍼도 `vt.zig`도 안 본다(design 결정 5). 상태를
/// 받아 문자열을 돌려주는 순수 계산이라 `status_test`가 자판 여섯 × 한/영
/// 둘을 전부 호스트에서 돈다. `promptText`가 `main.zig`의 private이라
/// `vt_test`가 못 부른 것(SP-M1 실측 5)이 이 파일이 따로 있는 이유다.
///
/// `copy`는 copy mode에 있는가다(CI design 결정 4). `*vt.Screen`을 받지
/// 않는 이유가 이 파일의 존재 이유와 같다 — 받으면 `status_test`가 ghostty
/// 패키지를 링크해야 하고 순수 계산이 아니게 된다. 값을 읽는 것은
/// `main.zig`의 `screen.copyActive()`다.
///
/// `workspace`는 지금 워크스페이스의 번호(1~9)이고, 하나뿐이면 null이다
/// (WP design 결정 8). 둘 이상일 때만 칸이 뜨는 것은 `COPY`가 copy mode일
/// 때만 뜨는 것과 같은 규칙이다 — 하나뿐인 화면이 한 글자도 안 바뀌어야
/// hangul 체인의 `text=` 비교와 `ink fg=` 기준값이 그대로 선다. null로
/// 고르는 것은 부르는 쪽(`main.zig`)이다 — 이 파일은 워크스페이스가 몇인지
/// 모른다.
///
/// `dict`는 받아쓰기 칸이다(VD-M1). null이면 칸이 없다. 무엇을 보일지(단계인지
/// 알림인지)는 부르는 쪽(`main.zig`)이 고른다 — 이 파일은 자식 프로세스를 모른다.
///
/// `buf`는 최소 `MAX_LEN`바이트여야 한다.
pub fn statusText(state: *const input.State, copy: bool, workspace: ?u8, dict: ?dictation.Show, buf: []u8) []const u8 {
    var len: usize = 0;
    len += put(buf, len, if (state.hangul_on) "한" else "EN");
    len += put(buf, len, GAP);
    len += put(buf, len, hangulName(state.hangul_layout));
    len += put(buf, len, GAP);
    len += put(buf, len, latinName(state.latin_layout));
    len += put(buf, len, GAP);
    // `state.caps_lock`을 안 읽는다(design 결정 3). 켜짐과 꺼짐은 글자가
    // 아니라 색으로 갈리며, 색을 고르는 것은 `main.zig`다. `status_test`의
    // 검사 12가 이 사실을 못 박는다.
    len += put(buf, len, CAPS);
    // 꼬리다. `CAPS` 뒤여야 한다 — `drawStatus`가 `CAPS`의 시작을 꼬리에서
    // `COPY_TAIL.len`만큼 물러나 세므로, 순서를 바꾸면 색이 한 칸 밀린다.
    // 워크스페이스 칸이 `COPY` 앞이다(WP design 결정 8). 둘 다 꼬리라
    // `drawStatus`가 둘의 길이를 모두 물러나 `CAPS`를 찾는다.
    if (workspace) |n| {
        len += put(buf, len, GAP);
        len += put(buf, len, WS_PREFIX);
        // 1~9만 온다(`WS_TAIL_LEN`의 주석). 0이나 10이 오면 숫자 대신 `?`를
        // 써서 칸의 길이를 지킨다 — 길이가 어긋나면 색이 칸째 밀린다.
        buf[len] = if (n >= 1 and n <= 9) '0' + n else '?';
        len += 1;
    }
    if (copy) len += put(buf, len, COPY_TAIL);
    // 받아쓰기 칸이 맨 끝이다(VD-M1). 모드(`COPY`)보다도 뒤인 것은 이 칸만 글자의
    // 길이가 바뀌기 때문이다 — 맨 끝이면 그 길이가 앞 칸들의 자리를 안 흔든다.
    if (dict) |s| {
        len += put(buf, len, GAP);
        len += put(buf, len, dictWord(s));
    }
    return buf[0..len];
}
