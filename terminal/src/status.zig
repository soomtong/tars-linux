const std = @import("std");
const hangul = @import("hangul.zig");
const input = @import("input.zig");

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
/// IS-M1에서 30이 36이 됐고, 버퍼를 손으로 늘린 자리는 없다.
pub const MAX_LEN: usize = blk: {
    var hl: usize = 0;
    for (std.enums.values(hangul.Layout)) |t| {
        if (hangulName(t).len > hl) hl = hangulName(t).len;
    }
    var ll: usize = 0;
    for (std.enums.values(input.LatinLayout)) |t| {
        if (latinName(t).len > ll) ll = latinName(t).len;
    }
    break :blk 3 + GAP.len + hl + GAP.len + ll + GAP.len + CAPS.len;
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
/// `buf`는 최소 `MAX_LEN`바이트여야 한다.
pub fn statusText(state: *const input.State, buf: []u8) []const u8 {
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
    return buf[0..len];
}
