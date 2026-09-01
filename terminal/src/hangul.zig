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

    /// 지금 중성이 겹모음을 **열 수 있는가**(`Cand.jung_opens`가 옮겨 온 값).
    ///
    /// **`codepoint()`는 이 값을 안 본다.** 그리는 데는 아무 영향이 없고,
    /// 그래서 `vt.zig`도 `main.zig`도 이 필드를 모른다. 겹모음을 만들지
    /// 판단하는 것은 **뒤 모음이 올 때**인데 그 판단의 근거는 **앞 모음이
    /// 어느 키에서 왔는가**라, 그 사이에 키가 하나 지나간다. 그래서 버퍼가
    /// 기억한다.
    jung_opens: bool = false,

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
            const v = self.jung orelse {
                // **종성만은 그려진다**(HI-M2가 넓혔다). `JONG` 표의 값이
                // 전부 호환 자모라 겹받침까지 한 글자다 — `font_test`가
                // `ㄳ`(12x9)과 `ㄺ`(11x9)을 굽고 둘 다 `cell_width=16`이다.
                //
                // 두벌식은 이 상태를 **안 만든다.** 자음 키가 전부 초성
                // 후보를 갖고 빈 상태의 우선순위가 초성 먼저이기 때문이며,
                // 아래 검사 7의 3-순열이 그것을 매번 다시 본다. 세벌식은
                // 종성 전용 키가 따로 있어서 만든다.
                if (self.jong) |j| return JONG[j];
                return null;
            };
            // 중성+종성은 완성형에 없다(design 결정 3).
            if (self.jong != null) return null;
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

/// 자판이 키 하나에서 뽑아낸 **후보**(design 결정 11).
///
/// **union이 아니라 struct인 것이 HI-M2의 가장 큰 결정이다.** 자판 넷의 겹침
/// 구조가 서로 반대이기 때문이다 — 두벌식은 같은 키가 초성이자 종성이고
/// (`r` = ㄱ/ㄱ) 중성과는 절대 안 겹치는데, 세벌식은 초성과 종성이 절대 안
/// 겹치고 중성이 양쪽과 겹친다(신세벌 PCS는 오른손 블록 열다섯이 전부
/// 중성∩종성이다).
///
/// 그래서 "이 키가 무엇인가"를 자판이 정하지 않는다. **자판은 될 수 있는 것을
/// 전부 적고, 조합 상태가 고른다**(`feed`의 우선순위 표).
pub const Cand = struct {
    cho: ?u5 = null,
    jung: ?u5 = null,
    jong: ?u5 = null,
    /// 이 중성이 겹모음의 **앞자리**가 될 수 있는가.
    ///
    /// 두벌식은 언제나 참이다. 세벌식은 ㅗ·ㅜ·ㅡ가 각각 두 자리에 있고
    /// **오른쪽만 겹모음을 만든다** — 3-P3에서 `/f`는 ㅘ이지만 `vf`는
    /// ㅗ와 ㅏ다. 이 표시가 없으면 `보아`가 `봐`가 된다.
    jung_opens: bool = false,
};

/// 두벌식의 자음. **같은 키가 초성도 종성도 되므로 둘을 함께 나른다.**
/// `jong`이 null인 것은 ㄸ·ㅃ·ㅉ 셋뿐이다 — 받침이 될 수 없는 자음이다.
fn cons(cho: u5, jong: ?u5) Cand {
    return .{ .cho = cho, .jong = jong };
}

/// 두벌식의 모음. **전부 겹모음을 연다** — ㅗ·ㅜ·ㅡ가 한 자리씩뿐이라
/// 세벌식 같은 갈림이 없다.
fn vowel(v: u5) Cand {
    return .{ .jung = v, .jung_opens = true };
}

/// 두벌식(KS X 5002). **인자는 쿼티 배치의 문자다.**
///
/// `'r'`은 "r이라는 글자"가 아니라 **"쿼티에서 r이 있는 자리의 키"**를 부르는
/// 이름이다. Patal의 자판 맵이 쓰는 규약과 같고(`KeyCodeMapper.swift:11`),
/// TARS에서 그 문자를 만드는 것은 `input.zig`의 `keymap` 배열(`:28`)이다.
/// **그래서 한글 자판은 영문 배열이 쿼티든 드보락이든 안 흔들린다.**
pub fn dubeol(ch: u8) ?Cand {
    return switch (ch) {
        // 닿소리 열아홉 — {초성 인덱스, 종성 인덱스}
        'r' => cons(0, 1), // ㄱ
        'R' => cons(1, 2), // ㄲ
        's' => cons(2, 4), // ㄴ
        'e' => cons(3, 7), // ㄷ
        'E' => cons(4, null), // ㄸ — 받침이 될 수 없다
        'f' => cons(5, 8), // ㄹ
        'a' => cons(6, 16), // ㅁ
        'q' => cons(7, 17), // ㅂ
        'Q' => cons(8, null), // ㅃ
        't' => cons(9, 19), // ㅅ
        'T' => cons(10, 20), // ㅆ
        'd' => cons(11, 21), // ㅇ
        'w' => cons(12, 22), // ㅈ
        'W' => cons(13, null), // ㅉ
        'c' => cons(14, 23), // ㅊ
        'z' => cons(15, 24), // ㅋ
        'x' => cons(16, 25), // ㅌ
        'v' => cons(17, 26), // ㅍ
        'g' => cons(18, 27), // ㅎ
        // 홀소리 열넷 — 겹모음은 키가 없고 조합으로 만든다
        'k' => vowel(0), // ㅏ
        'o' => vowel(1), // ㅐ
        'i' => vowel(2), // ㅑ
        'O' => vowel(3), // ㅒ
        'j' => vowel(4), // ㅓ
        'p' => vowel(5), // ㅔ
        'u' => vowel(6), // ㅕ
        'P' => vowel(7), // ㅖ
        'h' => vowel(8), // ㅗ
        'y' => vowel(12), // ㅛ
        'n' => vowel(13), // ㅜ
        'b' => vowel(17), // ㅠ
        'm' => vowel(18), // ㅡ
        'l' => vowel(20), // ㅣ
        else => null,
    };
}

// 표를 옮겨 적을 때 사람이 틀리는 자리에 못을 박는다. **plan을 쓰는 동안
// 실제로 두 번 틀렸다** — `g`를 ㄱ으로 읽어 `ghk`를 "과"로 적었는데 `g`는
// ㅎ이라 "화"가 맞다. 아래 넷은 그 종류의 착각이 컴파일을 통과하지 못하게 한다.
comptime {
    if (CHO[dubeol('r').?.cho.?] != 'ㄱ')
        @compileError("dubeol: r must be the initial of GIYEOK");
    if (CHO[dubeol('g').?.cho.?] != 'ㅎ')
        @compileError("dubeol: g must be the initial of HIEUH");
    if (JUNG[dubeol('k').?.jung.?] != 'ㅏ')
        @compileError("dubeol: k must be the vowel A");
    if (JUNG[dubeol('l').?.jung.?] != 'ㅣ')
        @compileError("dubeol: l must be the vowel I");
}

/// 갈마들이 공세벌식 3-P3(https://pat.im/1128). **인자는 쿼티 배치의 문자다.**
///
/// **초성은 오른손, 중성과 종성은 왼손이다.** 그래서 초성이 중성·종성과
/// 겹치는 키가 하나도 없고, 겹치는 것은 중성과 종성 여섯 자리뿐이다
/// (`c v r e f d`) — 그 여섯을 가르는 것이 `feed`의 우선순위다.
///
/// **숫자 열이 자모다.** `1`이 종성 ㅋ, `3`이 종성 ㅂ, `9`가 중성 ㅜ다.
/// 그래서 `nonSyllable`이 없으면 한글 상태에서 숫자를 칠 수가 없다.
///
/// 연타(`kk` = ㄲ)와 겹모음(`/f` = ㅘ)과 겹받침(`wx` = ㄺ)은 **표에 안 적는다** —
/// 각각 `tenseInitial`·`joinVowel`·`joinFinal`이 이미 한다.
fn sebeol3P3(ch: u8) ?Cand {
    return switch (ch) {
        // 초성 — 오른손.
        'k' => .{ .cho = 0 }, // ㄱ
        'h' => .{ .cho = 2 }, // ㄴ
        'u' => .{ .cho = 3 }, // ㄷ
        'y' => .{ .cho = 5 }, // ㄹ
        'i' => .{ .cho = 6 }, // ㅁ
        ';' => .{ .cho = 7 }, // ㅂ
        'n' => .{ .cho = 9 }, // ㅅ
        'j' => .{ .cho = 11 }, // ㅇ
        'l' => .{ .cho = 12 }, // ㅈ
        'o' => .{ .cho = 14 }, // ㅊ
        '0' => .{ .cho = 15 }, // ㅋ
        '\'' => .{ .cho = 16 }, // ㅌ
        'p' => .{ .cho = 17 }, // ㅍ
        'm' => .{ .cho = 18 }, // ㅎ

        // 중성만 — 종성과 안 겹치는 자리.
        't' => .{ .jung = 1 }, // ㅐ
        '6' => .{ .jung = 2 }, // ㅑ
        'T' => .{ .jung = 3 }, // ㅒ
        '7' => .{ .jung = 7 }, // ㅖ
        '4' => .{ .jung = 12 }, // ㅛ
        'b' => .{ .jung = 13 }, // ㅜ — 왼쪽. **겹모음을 안 연다**
        '5' => .{ .jung = 17 }, // ㅠ
        'g' => .{ .jung = 18 }, // ㅡ — 왼쪽. **겹모음을 안 연다**

        // 겹모음을 여는 오른쪽 셋(design 결정 12).
        '/' => .{ .jung = 8, .jung_opens = true }, // ㅗ — `/f` = ㅘ
        '9' => .{ .jung = 13, .jung_opens = true }, // ㅜ — `9r` = ㅝ
        '8' => .{ .jung = 18, .jung_opens = true }, // ㅡ — `8d` = ㅢ

        // 중성이자 종성 — 여섯. **이 자리가 갈마들이다.**
        'f' => .{ .jung = 0, .jong = 26 }, // ㅏ / ㅍ
        'r' => .{ .jung = 4, .jong = 23 }, // ㅓ / ㅊ
        'c' => .{ .jung = 5, .jong = 7 }, // ㅔ / ㄷ
        'e' => .{ .jung = 6, .jong = 25 }, // ㅕ / ㅌ
        'v' => .{ .jung = 8, .jong = 22 }, // ㅗ / ㅈ — 왼쪽 ㅗ라 안 연다
        'd' => .{ .jung = 20, .jong = 27 }, // ㅣ / ㅎ

        // 종성만.
        'x' => .{ .jong = 1 }, // ㄱ
        'X' => .{ .jong = 2 }, // ㄲ
        's' => .{ .jong = 4 }, // ㄴ
        'S' => .{ .jong = 6 }, // ㄶ
        'w' => .{ .jong = 8 }, // ㄹ
        'W' => .{ .jong = 9 }, // ㄺ
        'Z' => .{ .jong = 10 }, // ㄻ
        'Q' => .{ .jong = 15 }, // ㅀ
        'z' => .{ .jong = 16 }, // ㅁ
        '3' => .{ .jong = 17 }, // ㅂ
        'A' => .{ .jong = 18 }, // ㅄ
        'q' => .{ .jong = 19 }, // ㅅ
        '2' => .{ .jong = 20 }, // ㅆ
        'a' => .{ .jong = 21 }, // ㅇ
        '1' => .{ .jong = 24 }, // ㅋ
        else => null,
    };
}

// design 위험 1 — 표를 옮겨 적으면서 사람이 틀린다. HI-M0에서 실제로 두 번
// 틀렸고(`g`를 ㄱ으로 읽었다) 처방이 `dubeol`의 앵커 넷이었다. **자판을 셋 더
// 옮기는 HI-M2가 같은 위험을 셋 더 진다.**
//
// 3-P3의 앵커는 다섯이다. 손 양쪽에서 하나씩(초성 `k`, 종성 `x`), 갈마들이
// 자리 하나(`c`가 중성이면서 종성), 그리고 **겹모음을 여는 쪽과 안 여는 쪽**
// (`/`와 `v`가 둘 다 ㅗ인데 성질이 다르다). 마지막 둘이 가장 놓치기 쉽다 —
// 값이 같아서 눈으로는 안 갈린다.
comptime {
    if (CHO[sebeol3P3('k').?.cho.?] != 'ㄱ')
        @compileError("3-P3: k must be the initial GIYEOK");
    if (JONG[sebeol3P3('x').?.jong.?] != 'ㄱ')
        @compileError("3-P3: x must be the final GIYEOK");
    if (JUNG[sebeol3P3('c').?.jung.?] != 'ㅔ' or
        JONG[sebeol3P3('c').?.jong.?] != 'ㄷ')
        @compileError("3-P3: c must be both the vowel E and the final DIGEUT");
    if (JUNG[sebeol3P3('/').?.jung.?] != 'ㅗ' or !sebeol3P3('/').?.jung_opens)
        @compileError("3-P3: / must be the right-hand O that opens a diphthong");
    if (JUNG[sebeol3P3('v').?.jung.?] != 'ㅗ' or sebeol3P3('v').?.jung_opens)
        @compileError("3-P3: v must be the left-hand O that does not open one");
}

/// 복합 모음. (앞, 뒤) → 합친 것. 안 되면 null.
fn joinVowel(a: u5, b: u5) ?u5 {
    return switch (a) {
        8 => switch (b) { 0 => 9, 1 => 10, 20 => 11, else => null }, // ㅗ+ㅏㅐㅣ
        13 => switch (b) { 4 => 14, 5 => 15, 20 => 16, else => null }, // ㅜ+ㅓㅔㅣ
        18 => switch (b) { 20 => 19, else => null }, // ㅡ+ㅣ = ㅢ
        else => null,
    };
}

/// 복합 모음의 **앞 모음만** 준다. 홑모음이면 null.
/// **뒤 모음은 쓰는 자리가 없어서 안 만든다** — `erase`가 앞만 남기기 때문이다.
fn splitVowel(v: u5) ?u5 {
    return switch (v) {
        9, 10, 11 => 8, // ㅘㅙㅚ → ㅗ
        14, 15, 16 => 13, // ㅝㅞㅟ → ㅜ
        19 => 18, // ㅢ → ㅡ
        else => null,
    };
}

/// 겹받침. (앞, 뒤) → 합친 것. 안 되면 null.
fn joinFinal(a: u5, b: u5) ?u5 {
    return switch (a) {
        1 => switch (b) { 19 => 3, else => null }, // ㄱ+ㅅ = ㄳ
        4 => switch (b) { 22 => 5, 27 => 6, else => null }, // ㄴ+ㅈㅎ
        8 => switch (b) { // ㄹ
            1 => 9, 16 => 10, 17 => 11, 19 => 12,
            25 => 13, 26 => 14, 27 => 15,
            else => null,
        },
        17 => switch (b) { 19 => 18, else => null }, // ㅂ+ㅅ = ㅄ
        else => null,
    };
}

const FinalPair = struct { head: u5, tail: u5 };

/// 겹받침을 (앞, 뒤)로 가른다. 홑받침이면 null.
/// **여기는 앞뒤가 둘 다 필요하다** — 받침 넘기기가 앞은 남기고 뒤만 넘긴다.
fn splitFinal(j: u5) ?FinalPair {
    return switch (j) {
        3 => .{ .head = 1, .tail = 19 }, // ㄳ
        5 => .{ .head = 4, .tail = 22 }, // ㄵ
        6 => .{ .head = 4, .tail = 27 }, // ㄶ
        9 => .{ .head = 8, .tail = 1 }, // ㄺ
        10 => .{ .head = 8, .tail = 16 }, // ㄻ
        11 => .{ .head = 8, .tail = 17 }, // ㄼ
        12 => .{ .head = 8, .tail = 19 }, // ㄽ
        13 => .{ .head = 8, .tail = 25 }, // ㄾ
        14 => .{ .head = 8, .tail = 26 }, // ㄿ
        15 => .{ .head = 8, .tail = 27 }, // ㅀ
        18 => .{ .head = 17, .tail = 19 }, // ㅄ
        else => null,
    };
}

/// 종성 인덱스를 초성 인덱스로. **겹받침은 여기 안 온다** — `splitFinal`이
/// 먼저 갈라서 뒷자만 넘긴다. 그리고 종성에는 ㄸ·ㅃ·ㅉ이 없으므로 초성
/// 4·8·13은 이 함수에서 안 나온다.
fn finalToInitial(j: u5) ?u5 {
    return switch (j) {
        1 => 0, 2 => 1, 4 => 2, 7 => 3, 8 => 5, 16 => 6, 17 => 7,
        19 => 9, 20 => 10, 21 => 11, 22 => 12, 23 => 14, 24 => 15,
        25 => 16, 26 => 17, 27 => 18,
        else => null,
    };
}

/// 같은 초성을 잇달아 치면 된소리가 된다. **세벌식 셋만 쓴다**
/// (design 결정 12) — 두벌식은 Shift로 치므로 `rr`이 `ㄱㄱ`이어야 한다.
fn tenseInitial(c: u5) ?u5 {
    return switch (c) {
        0 => 1, // ㄱ → ㄲ
        3 => 4, // ㄷ → ㄸ
        7 => 8, // ㅂ → ㅃ
        9 => 10, // ㅅ → ㅆ
        12 => 13, // ㅈ → ㅉ
        else => null,
    };
}

/// 종성 자리의 연타. **둘뿐인 것은 우연이 아니다** — 종성에 올 수 있는
/// 된소리가 ㄲ과 ㅆ밖에 없다.
fn tenseFinal(j: u5) ?u5 {
    return switch (j) {
        1 => 2, // ㄱ → ㄲ
        19 => 20, // ㅅ → ㅆ
        else => null,
    };
}

/// 한글 자판. **`Shell`·`Keyboard`와 같은 화이트리스트 구조다**
/// (`init/src/config.zig`) — enum이 "무엇을 적을 수 있는가"를, 아래 switch들이
/// "그것이 무엇을 하는가"를 정한다. 이름을 하나 더하면 switch들이 전부
/// 컴파일 에러를 내서 빠뜨릴 수 없다.
pub const Layout = enum {
    dubeol,
    sebeol_3p3,
    shin_p2,
    shin_pcs,

    /// 쿼티 배치의 문자 하나 → 후보. **인자는 언제나 쿼티다**
    /// (design 결정 13) — 영문 배열이 드보락이어도 여기 오는 문자는 안 바뀐다.
    pub fn lookup(self: Layout, ch: u8) ?Cand {
        return switch (self) {
            .dubeol => dubeol(ch),
            .sebeol_3p3 => sebeol3P3(ch),
            // 신세벌 둘은 Task 5가 채운다.
            .shin_p2 => dubeol(ch),
            .shin_pcs => dubeol(ch),
        };
    }

    /// 받침 넘기기(도깨비불). **두벌식만이다**(design 결정 12).
    ///
    /// 세벌식은 초성 키와 종성 키가 아예 달라서 넘길 이유가 없고, 넘기면
    /// 틀린다 — 3-P3에서 `각`+ㅜ는 `가구`가 아니라 `각ㅜ`가 맞다.
    fn carriesFinal(self: Layout) bool {
        return switch (self) {
            .dubeol => true,
            .sebeol_3p3, .shin_p2, .shin_pcs => false,
        };
    }

    /// 연타 된소리. **세벌식 셋만이다.**
    fn tenseByRepeat(self: Layout) bool {
        return switch (self) {
            .dubeol => false,
            .sebeol_3p3, .shin_p2, .shin_pcs => true,
        };
    }
};

/// 자모 하나를 먹인 결과.
pub const Step = struct {
    /// 확정돼서 PTY로 갈 글자. 없으면 null이다.
    commit: ?u21 = null,
    /// 확정하고 남은 조합 상태.
    buf: Syllable = .{},
};

/// 후보 하나를 조합 버퍼에 먹인다. **자판이 아니라 조합 상태가 고른다**
/// (design 결정 11).
///
/// 우선순위가 상태마다 다른 것이 이 함수의 전부다.
///
/// | 상태 | 순서 |
/// |---|---|
/// | 빈 상태 | 초성 → 중성 → 종성 |
/// | 초성만 | 중성 → 초성 → 종성 |
/// | 중성만 | 겹모음 → 초성 → 중성 → 종성 |
/// | 종성만 | 겹받침 → 초성 → 종성 → 중성 |
/// | 초+중 | 겹모음 → 종성 → 초성 → 중성 |
/// | 초+중+종 | 겹받침 → 초성 → 종성 → 중성 |
///
/// **규칙 하나로 말하면 "종성 자리가 차 있으면 종성이 중성보다 먼저"다.**
/// 연타 된소리(신세벌의 `cc` = ㄲ받침)와 겹받침을 살리기 위해서다.
///
/// **초+중과 초+중+종에서 초성과 종성의 순서가 반대인 것은 순수하게 두벌식이
/// 정했다.** `가`+`r`은 `각`이어야 하고(종성 먼저) `각`+`e`는 `각ㄷ`이어야
/// 한다(초성 먼저 — 겹받침 ㄱㄷ이 없으니 새 음절이다). 세벌식은 초성과
/// 종성이 겹치는 키가 **하나도 없어서** 이 두 줄에 안 흔들린다.
pub fn feed(buf: Syllable, cand: Cand, layout: Layout) Step {
    const has_cho = buf.cho != null;
    const has_jung = buf.jung != null;
    const has_jong = buf.jong != null;

    if (has_jong) {
        // 겹받침이 먼저다. 초+중+종이든 종성만이든 같다.
        if (cand.jong) |j| {
            if (joinFinal(buf.jong.?, j)) |merged| return .{ .buf = .{
                .cho = buf.cho,
                .jung = buf.jung,
                .jong = merged,
                .jung_opens = buf.jung_opens,
            } };
        }
        if (cand.cho) |c| return commitAnd(buf, .{ .cho = c });
        if (cand.jong) |j| {
            // 연타 된소리 — 신세벌의 `cc`가 ㄲ받침이 되는 자리다. **겹받침을
            // 먼저 본 뒤이므로 `joinFinal`과 안 겹친다**(ㄱ+ㄱ은 겹받침 표에
            // 없다).
            if (layout.tenseByRepeat() and buf.jong.? == j) {
                if (tenseFinal(j)) |t| return .{ .buf = .{
                    .cho = buf.cho,
                    .jung = buf.jung,
                    .jong = t,
                    .jung_opens = buf.jung_opens,
                } };
            }
            return commitAnd(buf, .{ .jong = j });
        }
        if (cand.jung) |v| {
            // 받침 넘기기(도깨비불). **두벌식만이고, 초성과 중성이 함께
            // 있을 때만 뜻이 있다** — 종성만 있는 상태에서 넘기면 확정할
            // 음절이 없다.
            if (layout.carriesFinal() and has_cho and has_jung)
                return carryFinal(buf, v, cand.jung_opens);
            return commitAnd(buf, .{ .jung = v, .jung_opens = cand.jung_opens });
        }
        return .{ .buf = buf };
    }

    if (has_cho and has_jung) {
        // 겹모음 → 종성 → 초성 → 중성.
        if (cand.jung) |v| {
            if (buf.jung_opens) {
                if (joinVowel(buf.jung.?, v)) |merged| return .{ .buf = .{
                    .cho = buf.cho,
                    .jung = merged,
                    // 합쳐진 겹모음은 더 합쳐지지 않는다.
                    .jung_opens = false,
                } };
            }
        }
        if (cand.jong) |j| return .{ .buf = .{
            .cho = buf.cho,
            .jung = buf.jung,
            .jong = j,
            .jung_opens = buf.jung_opens,
        } };
        if (cand.cho) |c| return commitAnd(buf, .{ .cho = c });
        if (cand.jung) |v| return commitAnd(buf, .{
            .jung = v,
            .jung_opens = cand.jung_opens,
        });
        return .{ .buf = buf };
    }

    if (has_cho) {
        // 중성 → 초성 → 종성. **중성이 첫째인 것이 갈마들이의 자리다** —
        // 신세벌 PCS의 `p`는 빈 상태에선 ㅍ이고 초성 뒤에선 ㅗ다.
        if (cand.jung) |v| return .{ .buf = .{
            .cho = buf.cho,
            .jung = v,
            .jung_opens = cand.jung_opens,
        } };
        if (cand.cho) |c| {
            // 연타 된소리 — 세벌식의 `kk`가 ㄲ이 되는 자리다.
            if (layout.tenseByRepeat() and buf.cho.? == c) {
                if (tenseInitial(c)) |t| return .{ .buf = .{ .cho = t } };
            }
            return commitAnd(buf, .{ .cho = c });
        }
        if (cand.jong) |j| return commitAnd(buf, .{ .jong = j });
        return .{ .buf = buf };
    }

    if (has_jung) {
        // 겹모음 → 초성 → 중성 → 종성.
        if (cand.jung) |v| {
            if (buf.jung_opens) {
                if (joinVowel(buf.jung.?, v)) |merged| return .{ .buf = .{
                    .jung = merged,
                    .jung_opens = false,
                } };
            }
        }
        if (cand.cho) |c| return commitAnd(buf, .{ .cho = c });
        if (cand.jung) |v| return commitAnd(buf, .{
            .jung = v,
            .jung_opens = cand.jung_opens,
        });
        if (cand.jong) |j| return commitAnd(buf, .{ .jong = j });
        return .{ .buf = buf };
    }

    // 빈 상태 — 초성 → 중성 → 종성. **확정할 것이 없으므로 `commitAnd`가
    // 아니라 그냥 새 버퍼다**(`codepoint()`가 null을 주니 결과는 같지만,
    // 빈 상태를 확정 갈래로 보내지 않는 편이 읽기 쉽다).
    if (cand.cho) |c| return .{ .buf = .{ .cho = c } };
    if (cand.jung) |v| return .{ .buf = .{
        .jung = v,
        .jung_opens = cand.jung_opens,
    } };
    if (cand.jong) |j| return .{ .buf = .{ .jong = j } };
    return .{ .buf = buf };
}

/// 지금까지 모은 것을 확정하고 새 버퍼로 시작한다.
///
/// **빈 버퍼도 이 갈래로 올 수 있다** — `codepoint()`가 null을 주므로 확정될
/// 것이 없고, 그래서 빈 경우를 따로 적지 않는다.
fn commitAnd(buf: Syllable, next: Syllable) Step {
    return .{ .commit = buf.codepoint(), .buf = next };
}

/// 받침을 다음 음절의 초성으로 넘긴다. **두벌식의 핵심이고, 겹받침은 뒷자만
/// 넘어간다**(앉 + ㅓ → 안 + 저).
///
/// `.?` 둘이 단언이다. `splitFinal`의 tail도, 홑받침도 전부
/// `finalToInitial`의 표에 있다 — 종성 스물일곱 중 겹받침 열하나는 위
/// 갈래로 빠지고 나머지 열여섯이 표에 그대로 있다.
fn carryFinal(buf: Syllable, v: u5, opens: bool) Step {
    const j = buf.jong.?;
    if (splitFinal(j)) |pair| {
        const head = Syllable{ .cho = buf.cho, .jung = buf.jung, .jong = pair.head };
        return .{
            .commit = head.codepoint(),
            .buf = .{
                .cho = finalToInitial(pair.tail).?,
                .jung = v,
                .jung_opens = opens,
            },
        };
    }
    const head = Syllable{ .cho = buf.cho, .jung = buf.jung };
    return .{
        .commit = head.codepoint(),
        .buf = .{ .cho = finalToInitial(j).?, .jung = v, .jung_opens = opens },
    };
}

/// Backspace. 조합 중이면 **자모를 하나** 뺀다(design 결정 6).
///
/// **null은 "조합 중이 아니다"라는 뜻이다.** 그때는 부르는 쪽이 지금처럼
/// DEL(0x7F)을 PTY로 보낸다. 음절을 통째로 지우는 것은 Patal의 `글자단위삭제`
/// trait이고 안 옮긴다(design 비목표).
pub fn erase(buf: Syllable) ?Syllable {
    // **`jung_opens`를 따라 옮긴다.** 안 옮기면 `과`를 지워 `고`가 된 뒤에
    // 다시 친 `ㅏ`가 안 합쳐져서 `고ㅏ`가 된다.
    if (buf.jong) |j| {
        if (splitFinal(j)) |pair| {
            return .{
                .cho = buf.cho,
                .jung = buf.jung,
                .jong = pair.head,
                .jung_opens = buf.jung_opens,
            };
        }
        return .{ .cho = buf.cho, .jung = buf.jung, .jung_opens = buf.jung_opens };
    }
    if (buf.jung) |v| {
        // 겹모음을 한 겹 벗으면 **다시 열린 상태로 돌아간다** — 그 겹모음은
        // 열린 키에서 왔기 때문이다.
        if (splitVowel(v)) |head| return .{
            .cho = buf.cho,
            .jung = head,
            .jung_opens = true,
        };
        return .{ .cho = buf.cho };
    }
    if (buf.cho != null) return .{};
    return null;
}
