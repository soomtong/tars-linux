const std = @import("std");

/// 한글 조합. **시스템 콜도 `vt.zig`도 `drm.zig`도 안 본다**(design 결정 1).
/// 그 대가로 `hangul_test.zig`가 호스트에서 돈다 — 게이트 16분이 아니라
/// `zig build test` 9.5초로 오토마타를 돌려볼 수 있고, 이 서브프로젝트에서
/// 가장 크고 가장 틀리기 쉬운 부분이 오토마타이므로 그 자리가 값을 한다.

/// 초성 열아홉의 순서. **완성형 계산의 첫째 자리다.**
///
/// 값은 첫가끝 자모(U+1100대)가 아니라 **호환 자모**(U+3131대)의
/// 코드포인트다. 초성만 있는 상태를 그릴 때 그대로 쓰기 때문이고, 완성형
/// 계산은 값이 아니라 **인덱스**로 하므로 값이 무엇이든 상관이 없다.
///
/// HI-M0 실측 3: 이 표의 글자들은 unifont에서 9x9로 구워지고 `cell_width`가
/// 16이다 — **완성형과 똑같이 두 칸이라 조합하는 내내 폭이 안 바뀐다.**
pub const CHO: [19]u21 = .{
    'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ',
    'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
};

/// 중성 스물하나. 값이 호환 자모인 이유는 CHO와 같다.
pub const JUNG: [21]u21 = .{
    'ㅏ', 'ㅐ', 'ㅑ', 'ㅒ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅖ', 'ㅗ', 'ㅘ',
    'ㅙ', 'ㅚ', 'ㅛ', 'ㅜ', 'ㅝ', 'ㅞ', 'ㅟ', 'ㅠ', 'ㅡ', 'ㅢ', 'ㅣ',
};

/// 종성 스물여덟. **0번 칸은 자리만 채운다.**
///
/// 완성형 계산이 0을 "받침 없음"으로 쓰기 때문에 표의 인덱스를 그 규약에
/// 맞춘다. 그래서 이 칸의 값은 아무도 안 읽는다 — `Syllable.jong`이 `?u5`라
/// "없음"을 null로 적고 0을 안 쓴다.
pub const JONG: [28]u21 = .{
    0,    'ㄱ', 'ㄲ', 'ㄳ', 'ㄴ', 'ㄵ', 'ㄶ', 'ㄷ', 'ㄹ', 'ㄺ',
    'ㄻ', 'ㄼ', 'ㄽ', 'ㄾ', 'ㄿ', 'ㅀ', 'ㅁ', 'ㅂ', 'ㅄ', 'ㅅ',
    'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ',
};

// 위 세 표의 규약은 "N번째 칸이 인덱스 N"인데, 그것을 지켜 주는 것은 주석뿐이다.
// 중간에 한 칸이 끼면 뒤가 전부 밀리고, 그래도 **컴파일은 통과하며**, 증상은
// "치면 다른 글자가 나온다"로만 나타난다. `input.zig:98`이 `keymap`에 같은 못을
// 박았고 이유도 같다.
//
// 양끝과 가운데를 잡는 이유는, 한 칸이 끼면 그 뒤의 앵커가 **반드시** 하나는
// 어긋나기 때문이다.
comptime {
    if (CHO.len != 19) @compileError("CHO must have 19 entries");
    if (JUNG.len != 21) @compileError("JUNG must have 21 entries");
    if (JONG.len != 28) @compileError("JONG must have 28 entries");
    if (CHO[0] != 'ㄱ' or CHO[11] != 'ㅇ' or CHO[18] != 'ㅎ')
        @compileError("CHO table drifted");
    if (JUNG[0] != 'ㅏ' or JUNG[8] != 'ㅗ' or JUNG[20] != 'ㅣ')
        @compileError("JUNG table drifted");
    if (JONG[0] != 0 or JONG[8] != 'ㄹ' or JONG[27] != 'ㅎ')
        @compileError("JONG table drifted");
}

/// 조합 중인 음절 하나.
///
/// **코드포인트가 아니라 인덱스를 담는다.** 완성형 계산이 인덱스로 하고,
/// 그리는 데 쓸 코드포인트는 위의 세 표가 준다.
pub const Syllable = struct {
    cho: ?u5 = null,
    jung: ?u5 = null,
    /// **null이 "받침 없음"이다.** `JONG[0]`은 표의 자리만 채우는 값이라
    /// 여기서 0을 쓰지 않는다 — "없음"을 두 가지로 적을 수 있게 두면
    /// 비교하는 자리마다 둘을 다 봐야 한다.
    jong: ?u5 = null,

    pub fn isEmpty(self: Syllable) bool {
        return self.cho == null and self.jung == null and self.jong == null;
    }

    /// 지금 상태를 화면에 그릴 글자 하나. **못 그리는 조합이면 null이다.**
    ///
    /// 못 그리는 것이 셋이다(design 결정 3): 초성+종성 · 중성+종성 · 종성만.
    /// 완성형에 그런 글자가 없고, **unifont가 첫가끝 자모를 겹쳐 그려 주지도
    /// 않는다** — HI-M0 실측 3이 U+1103(초성)과 U+11AB(종성)을 재 보니 둘 다
    /// 호환 자모와 똑같은 9x9에 `x_off=+4`였다. 셀 가운데의 같은 조각이라
    /// 포개 봐야 두 글자가 겹칠 뿐이다.
    ///
    /// **오토마타는 그 셋을 절대 안 만들며** `hangul_test`의 검사 일곱이
    /// 그것을 확인한다 — 여기서 null을 주는 것은 방어가 아니라 **타입이
    /// 표현할 수 있는 여덟 조합을 빠짐없이 덮는 것**이다.
    ///
    /// 빈 상태도 null이다. 그 성질을 `feedConsonant`가 쓴다 — 확정할 것이
    /// 없는 경우를 따로 갈라 적지 않아도 된다.
    pub fn codepoint(self: Syllable) ?u21 {
        const c = self.cho orelse {
            if (self.jong != null) return null;
            const v = self.jung orelse return null;
            return JUNG[v];
        };
        const v = self.jung orelse {
            if (self.jong != null) return null;
            return CHO[c];
        };
        const j: u21 = if (self.jong) |x| x else 0;
        return 0xAC00 + (@as(u21, c) * 21 + @as(u21, v)) * 28 + j;
    }
};
