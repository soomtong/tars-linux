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

/// 자판이 키 하나에서 뽑아낸 자모.
///
/// **variant가 둘뿐인 것이 지금 쓰는 전부다.** 세벌식은 초성 전용·종성 전용
/// 키가 있고 신세벌식은 조합 상태에 따라 중성과 종성이 갈리므로, HI-M2에서
/// 이 union이 넓어진다. **미리 만들어 두지 않는 이유는** `feed`의 switch가
/// `else` 없이 닫혀 있어서 variant를 더하는 순간 컴파일러가 배선할 자리를
/// 알려주기 때문이다(CM-M0부터 지켜 온 규율).
pub const Jamo = union(enum) {
    /// 자음 하나. **두벌식은 같은 키가 초성도 종성도 되므로 둘을 함께 나른다.**
    /// `jong`이 null인 것은 ㄸ·ㅃ·ㅉ 셋뿐이다 — 받침이 될 수 없는 자음이다.
    consonant: struct { cho: u5, jong: ?u5 },
    /// 모음 하나. 중성 인덱스다.
    vowel: u5,
};

fn cons(cho: u5, jong: ?u5) Jamo {
    return .{ .consonant = .{ .cho = cho, .jong = jong } };
}

/// 두벌식(KS X 5002). **인자는 쿼티 배치의 문자다.**
///
/// `'r'`은 "r이라는 글자"가 아니라 **"쿼티에서 r이 있는 자리의 키"**를 부르는
/// 이름이다. Patal의 자판 맵이 쓰는 규약과 같고(`KeyCodeMapper.swift:11`),
/// TARS에서 그 문자를 만드는 것은 `input.zig`의 `keymap` 배열(`:28`)이다.
/// **그래서 한글 자판은 영문 배열이 쿼티든 드보락이든 안 흔들린다.**
pub fn dubeol(ch: u8) ?Jamo {
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
        'k' => .{ .vowel = 0 }, // ㅏ
        'o' => .{ .vowel = 1 }, // ㅐ
        'i' => .{ .vowel = 2 }, // ㅑ
        'O' => .{ .vowel = 3 }, // ㅒ
        'j' => .{ .vowel = 4 }, // ㅓ
        'p' => .{ .vowel = 5 }, // ㅔ
        'u' => .{ .vowel = 6 }, // ㅕ
        'P' => .{ .vowel = 7 }, // ㅖ
        'h' => .{ .vowel = 8 }, // ㅗ
        'y' => .{ .vowel = 12 }, // ㅛ
        'n' => .{ .vowel = 13 }, // ㅜ
        'b' => .{ .vowel = 17 }, // ㅠ
        'm' => .{ .vowel = 18 }, // ㅡ
        'l' => .{ .vowel = 20 }, // ㅣ
        else => null,
    };
}

// 표를 옮겨 적을 때 사람이 틀리는 자리에 못을 박는다. **plan을 쓰는 동안
// 실제로 두 번 틀렸다** — `g`를 ㄱ으로 읽어 `ghk`를 "과"로 적었는데 `g`는
// ㅎ이라 "화"가 맞다. 아래 넷은 그 종류의 착각이 컴파일을 통과하지 못하게 한다.
comptime {
    if (CHO[dubeol('r').?.consonant.cho] != 'ㄱ')
        @compileError("dubeol: r must be the initial of GIYEOK");
    if (CHO[dubeol('g').?.consonant.cho] != 'ㅎ')
        @compileError("dubeol: g must be the initial of HIEUH");
    if (JUNG[dubeol('k').?.vowel] != 'ㅏ')
        @compileError("dubeol: k must be the vowel A");
    if (JUNG[dubeol('l').?.vowel] != 'ㅣ')
        @compileError("dubeol: l must be the vowel I");
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

/// 자모 하나를 먹인 결과.
pub const Step = struct {
    /// 확정돼서 PTY로 갈 글자. 없으면 null이다.
    commit: ?u21 = null,
    /// 확정하고 남은 조합 상태.
    buf: Syllable = .{},
};

/// 자모 하나를 조합 버퍼에 먹인다. **두벌식의 규칙이다.**
///
/// 세벌식·신세벌식이 들어오는 HI-M2에서 이 함수가 자판을 인자로 받게 된다.
/// switch에 `else`가 없으므로 `Jamo`에 variant를 더하면 여기가 컴파일 에러를
/// 낸다.
pub fn feed(buf: Syllable, jamo: Jamo) Step {
    return switch (jamo) {
        .consonant => |c| feedConsonant(buf, c.cho, c.jong),
        .vowel => |v| feedVowel(buf, v),
    };
}

fn feedConsonant(buf: Syllable, cho: u5, jong: ?u5) Step {
    if (buf.jong) |cur| {
        // 받침 자리가 찼으면 겹받침이 되는지 본다.
        if (jong) |j| {
            if (joinFinal(cur, j)) |merged| {
                return .{ .buf = .{ .cho = buf.cho, .jung = buf.jung, .jong = merged } };
            }
        }
    } else if (buf.cho != null and buf.jung != null) {
        // 초성+중성이 서 있으면 받침으로 붙는다. ㄸ·ㅃ·ㅉ만 못 붙는다.
        if (jong) |j| {
            return .{ .buf = .{ .cho = buf.cho, .jung = buf.jung, .jong = j } };
        }
    }
    // 나머지는 전부 "앞을 확정하고 새 초성으로 시작한다"이다.
    // **빈 버퍼도 이 갈래로 온다** — `codepoint()`가 null을 주므로 확정될
    // 것이 없고, 그래서 빈 경우를 따로 적지 않는다.
    return .{ .commit = buf.codepoint(), .buf = .{ .cho = cho } };
}

fn feedVowel(buf: Syllable, v: u5) Step {
    // 받침이 있는데 모음이 왔다 — 그 받침을 다음 음절의 초성으로 넘긴다.
    // **두벌식의 핵심이고, 겹받침은 뒷자만 넘어간다**(앉 + ㅓ → 안 + 저).
    //
    // `.?` 둘이 단언이다. `splitFinal`의 tail도, 홑받침도 전부
    // `finalToInitial`의 표에 있다 — 종성 스물일곱 중 겹받침 열하나는 위
    // 갈래로 빠지고 나머지 열여섯이 표에 그대로 있다.
    if (buf.jong) |j| {
        if (splitFinal(j)) |pair| {
            const head = Syllable{ .cho = buf.cho, .jung = buf.jung, .jong = pair.head };
            return .{
                .commit = head.codepoint(),
                .buf = .{ .cho = finalToInitial(pair.tail).?, .jung = v },
            };
        }
        const head = Syllable{ .cho = buf.cho, .jung = buf.jung };
        return .{
            .commit = head.codepoint(),
            .buf = .{ .cho = finalToInitial(j).?, .jung = v },
        };
    }
    if (buf.jung == null) {
        if (buf.cho) |c| return .{ .buf = .{ .cho = c, .jung = v } };
        return .{ .buf = .{ .jung = v } };
    }
    // 중성이 이미 있다 — 복합 모음이 되는지 먼저 본다.
    if (joinVowel(buf.jung.?, v)) |merged| {
        return .{ .buf = .{ .cho = buf.cho, .jung = merged } };
    }
    // 안 되면 앞을 확정하고 **중성만 있는 상태**로 남는다. 모아주기를
    // 뺐으므로 이 상태는 그릴 수 있다(design 결정 3의 표).
    return .{ .commit = buf.codepoint(), .buf = .{ .jung = v } };
}
