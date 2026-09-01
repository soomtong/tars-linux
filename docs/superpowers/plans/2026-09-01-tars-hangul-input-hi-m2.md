# HI-M2 — 자판이 여섯이 되고 설정 파일이 고른다

**Date:** 2026-09-01
**Design:** `docs/superpowers/specs/2026-08-31-tars-hangul-input-design.md`
**Status:** 착수 전

## 이 milestone이 끝나면

- **한글 자판이 넷이다.** 두벌식 · 공세벌 3-P3 · 신세벌 P2 · 신세벌 PCS.
  자판은 키 하나에 대해 **후보**를 주고 조합 상태가 그중 하나를 고른다
  (design 결정 11).
- **영문 자판이 둘이다.** 쿼티와 드보락. **드보락을 켜도 한글 배열은 안
  흔들린다**(결정 13) — 한글 조회는 언제나 쿼티 표로 한다.
- **`tars.conf`가 고른다.** `hangul_layout`과 `latin_layout`이 생기고 기본값이
  `shin_pcs`와 `qwerty`다(결정 7).
- **종성만 있는 조합 상태가 그려진다.** 세벌식은 종성 전용 키가 있어서 그
  상태를 만든다. `JONG` 표의 값이 전부 호환 자모라 겹받침까지 한 글자다
  (결정 3의 다섯째 줄).
- **한글 상태에서 숫자와 기호를 칠 수 있다.** 3-P3은 숫자 열이 자모라서
  `nonSyllableMap`이 없으면 막힌다.
- **게이트의 유일한 부팅이 세벌식이 된다.** 설정 디스크를 물고 3-P3으로
  `가나다`를 친다(결정 14). **게이트 시간은 디스크 굽기 몇 초 말고는 안 는다.**

**아직 안 하는 것.** 한/영 키 · CapsLock · tap-vs-hold · `hangul_toggle`
설정(HI-M3). 기호 확장과 Patal의 옵션 trait들(비목표).

**편집도 Claude Code가 한다.** 이 서브프로젝트의 예외이고 근거는 design 실측
7이다. **CC-M0의 규율을 그대로 쓴다** — 매 편집 뒤 `git diff --stat`으로 더한
줄과 지운 줄을 따로 세고, 지우는 편집은 `git diff | grep '^-'`로 내용을 직접
읽는다.

## 왜 이 순서인가

**Task 1이 동작을 하나도 안 바꾸는 것이 이 쪼갬의 핵심이다.** 자판 표의 모양을
union에서 후보 struct로 바꾸는 것이 이 milestone에서 가장 크고 가장 틀리기 쉬운
변경인데, **기존 검사 열넷이 한 글자도 안 바뀐 채 통과하는 것**이 그것이 맞았다는
증거가 된다. 새 자판을 함께 넣으면 실패했을 때 "표가 틀렸나 우선순위가 틀렸나"를
가를 수 없다.

**Task 2~3이 바닥을 넓힌다.** 종성만 상태(Task 2)와 자판 성질(Task 3)이 없으면
세벌식 표를 넣어도 검사를 쓸 수가 없다.

**Task 4·5가 표를 옮긴다.** 셋을 한 Task에 넣지 않는다 — design 위험 1(표를
옮겨 적으면서 사람이 틀린다)이 자판마다 따로 서고, 3-P3과 신세벌은 겹침 구조가
다르다(결정 11의 표).

**Task 8의 게이트가 마지막이다.** 호스트 검사가 전부 통과한 뒤에 부팅한다 —
18분을 쓰기 전에 9.5초로 잡을 수 있는 실패를 먼저 잡는다.

## 착수 전에 확정한 것

### 1. 우선순위 표 — design 결정 11의 표를 고쳐 적는다

design에 적은 표에서 **초+중+종과 종성만 두 줄의 순서를 고쳤다.** 착수 전에
자판 넷을 손으로 돌려 보다가 신세벌의 `cc`(ㄲ받침)가 깨지는 것을 찾았다.

| 상태 | 순서 |
|---|---|
| 빈 상태 | 초성 → 중성 → 종성 |
| 초성만 | 중성 → 초성 → 종성 |
| 중성만 | 겹모음 → 초성 → 중성 → 종성 |
| **종성만** | 겹받침 → 초성 → **종성 → 중성** |
| 초+중 | 겹모음 → **종성 → 초성** → 중성 |
| **초+중+종** | 겹받침 → 초성 → **종성 → 중성** |

**규칙 하나로 말할 수 있다 — 종성 자리가 차 있으면 종성이 중성보다 먼저다.**
연타 된소리와 겹받침을 살리기 위해서다. 비어 있으면 중성이 먼저다.

증거가 되는 자리 넷.

| 자판 | 친 것 | 이 순서라야 나오는 것 | 뒤집으면 |
|---|---|---|---|
| 신세벌 PCS | `kfcc` | `갂` — `c`는 중성 ㅔ이자 종성 ㄱ이고, 종성 자리가 찼으니 연타 ㄲ | `각ㅔ` |
| 두벌식 | `rkre` | `각ㄷ` — 겹받침 ㄱㄷ이 없으니 **초성** ㄷ으로 새로 시작 | `각` + 종성 ㄷ이 남아 다음 모음에서 `각다`가 안 나온다 |
| 두벌식 | `rkrk` | `가가` — 종성 후보가 없는 모음 키라 받침 넘기기로 간다 | 같음(모음 키는 `jong`이 없다) |
| 두벌식 | `rkr` | `각` — 초+중에서 종성이 초성보다 먼저 | `가ㄱ` |

**초+중과 초+중+종에서 초성과 종성의 순서가 반대인 것이 이상해 보이는데 둘 다
근거가 있다.** 초+중에서는 두벌식 `가`+`r`이 `각`이어야 하고, 초+중+종에서는
두벌식 `각`+`e`가 `각ㄷ`이어야 한다. 세벌식은 초성∩종성이 **0**이라(결정 11의
표) 어느 쪽으로 두든 안 흔들린다 — **이 두 줄은 순수하게 두벌식이 정한다.**

### 2. `jung_opens`는 키가 아니라 **버퍼**가 기억한다

겹모음을 여는지는 **앞 모음이 어느 키에서 왔는가**로 정해지는데, 겹모음을
만들지 판단하는 것은 **뒤 모음이 올 때**다. 그 사이에 키가 하나 지나가므로
조합 버퍼가 기억해야 한다.

```zig
pub const Syllable = struct {
    cho: ?u5 = null,
    jung: ?u5 = null,
    jong: ?u5 = null,
    jung_opens: bool = false,   // ← 이번에 는다
};
```

**`codepoint()`는 이 값을 안 본다.** 그리는 데는 아무 영향이 없고, 그래서
`vt.zig`도 `main.zig`도 이 필드를 모른다.

**`erase`는 이 값을 보존한다.** `과`(열린 ㅗ에서 온 ㅘ)를 지우면 `고`가 되고
그 ㅗ는 **여전히 열려 있어야 한다** — 안 그러면 지웠다 다시 친 `과`가 `고ㅏ`가
된다.

### 3. `nonSyllable`은 `commit_buf`가 아니라 `.bytes`로 나간다

한글 상태에서 3-P3의 `M`을 누르면 두 가지가 나가야 한다 — **조합 중이던 음절**과
**숫자 `1`**이다. `commit_buf`는 코드포인트 하나짜리라(`pushCommit`이 덮어쓴다)
둘을 담을 수 없다.

**넓히지 않는다.** `hangulLayer`가 `commitHangul()`을 부른 뒤 `.bytes`를 담은
`Action`을 돌려주면 된다 — `readKeys`가 **`takeCommit()`을 그 키의 바이트보다
먼저** 비우므로(HI-M1 실측 2) 순서가 저절로 맞다.

```zig
if (self.hangul_layout.nonSyllable(ch)) |cp| {
    self.commitHangul();
    const n = std.unicode.utf8Encode(cp, &self.seq) catch return .hangul;
    return .{ .bytes = self.seq[0..n] };
}
```

`?u21`인 이유는 신세벌 P2가 `✕`·`○`·`△`·`※`·`□`·`·`·`―`·`…`를 주기
때문이다. `seq`가 8바이트라 3바이트 UTF-8이 넉넉히 들어간다.

### 4. 세벌식에서 Shift는 "중성 강제"다

Patal의 신세벌 맵이 `"f": 중성.아, "F": 중성.아`처럼 대문자를 함께 적어 둔 것이
그 뜻이다. 왼손 글쇠는 갈마들이 때문에 중성도 종성도 되는데, **Shift를 누르면
종성 후보가 빠지고 중성만 남는다.** 그래야 `앋`을 칠 수 없는 자리에서 `아ㄷ`을
칠 수 있다.

우리 표에서는 대문자 칸의 `Cand`에 `jong`을 안 적는 것으로 나타난다.

**3-P3은 반대다** — Shift가 아예 다른 자모다(`X`=ㄲ받침 · `W`=ㄺ · `T`=ㅒ).
그래서 3-P3의 대문자 칸은 자기 값을 따로 갖는다.

### 5. 연타 된소리 표는 다섯과 둘이다

```
초성  ㄱ→ㄲ  ㄷ→ㄸ  ㅂ→ㅃ  ㅅ→ㅆ  ㅈ→ㅉ     (다섯)
종성  ㄱ→ㄲ  ㅅ→ㅆ                          (둘)
```

**종성이 둘뿐인 것은 우연이 아니다** — 종성에 올 수 있는 된소리가 ㄲ과 ㅆ밖에
없다. 자판 셋(3-P3 · P2 · PCS)의 연타 항목 일곱(`kk` `uu` `;;` `nn` `ll` ·
`xx`/`cc` `qq`)이 이 두 표에 하나도 남김없이 들어간다.

### 6. 겹모음·겹받침 표는 자판 넷이 공유한다 — 확인했다

세벌식 겹받침 스물둘이 기존 `joinFinal`에 전부 있다.

| 자판 | 시퀀스 | 우리 표 |
|---|---|---|
| 3-P3 | `xq` `sv` `sd` `wx` `wz` `w3` `wq` `we` `wf` `wd` `3q` | `joinFinal(ㄱ,ㅅ)` … `joinFinal(ㅂ,ㅅ)` |
| 신세벌 | `cq` `sv` `sd` `wc` `wz` `we` `wq` `wr` `wf` `wd` `eq` | 같음 |

겹모음도 마찬가지다 — `/f`(3-P3) · `pf`(신세벌) · `hk`(두벌식)가 전부
`joinVowel(ㅗ, ㅏ)`다.

### 7. `State.hangul_layout`의 기본값은 Task 7에서 옮긴다

Task 3에서 필드를 만들 때는 `.dubeol`이다. 그때는 세벌식 표가 아직 없어서
`.shin_pcs`를 기본값으로 둘 수가 없다. **Task 7에서 `.shin_pcs`로 옮기고,
기존 `input_test`의 한글 검사 여덟에 `st.hangul_layout = .dubeol;`을 명시적으로
더한다** — 그래야 "설정의 기본값"이라는 진실이 `config.zig` 한 곳에만 남는다.

---

## Task 1: 자판은 후보를 주고 상태가 고른다 (동작 0 변화)

**Files:**
- Modify: `terminal/src/hangul.zig` — `Jamo` → `Cand`, `Syllable.jung_opens`,
  `feed` 재작성
- Modify: `terminal/src/hangul_test.zig` — `.consonant` 접근 셋
- Modify: `terminal/src/input.zig:595` — 이름만

- [ ] **Step 1: `Jamo`를 `Cand`로 바꾼다**

`terminal/src/hangul.zig`에서 지울 것:

```zig
pub const Jamo = union(enum) {
    consonant: struct { cho: u5, jong: ?u5 },
    vowel: u5,
};

fn cons(cho: u5, jong: ?u5) Jamo {
    return .{ .consonant = .{ .cho = cho, .jong = jong } };
}
```

넣을 것:

```zig
/// 자판이 키 하나에서 뽑아낸 **후보**(design 결정 11).
///
/// **union이 아니라 struct인 것이 이 milestone의 가장 큰 결정이다.** 자판
/// 넷의 겹침 구조가 서로 반대이기 때문이다 — 두벌식은 같은 키가 초성이자
/// 종성이고(`r` = ㄱ/ㄱ) 중성과는 절대 안 겹치는데, 세벌식은 초성과 종성이
/// 절대 안 겹치고 중성이 양쪽과 겹친다(신세벌 PCS는 오른손 블록 열다섯이
/// 전부 중성∩종성이다).
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

fn cons(cho: u5, jong: ?u5) Cand {
    return .{ .cho = cho, .jong = jong };
}

/// 두벌식의 모음. **전부 겹모음을 연다** — ㅗ·ㅜ·ㅡ가 한 자리씩뿐이라
/// 세벌식 같은 갈림이 없다.
fn vowel(v: u5) Cand {
    return .{ .jung = v, .jung_opens = true };
}
```

- [ ] **Step 2: `Syllable`에 `jung_opens`를 더한다**

`terminal/src/hangul.zig`의 `Syllable`에서 지울 것:

```zig
    jong: ?u5 = null,

    pub fn isEmpty(self: Syllable) bool {
```

넣을 것:

```zig
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
```

- [ ] **Step 3: `dubeol`의 반환형과 `vowel` 호출을 고친다**

`terminal/src/hangul.zig`에서 `pub fn dubeol(ch: u8) ?Jamo {` 을
`pub fn dubeol(ch: u8) ?Cand {` 으로 바꾸고, 모음 열넷을 `vowel()` 호출로
바꾼다. 지울 것(홀소리 열넷):

```zig
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
```

넣을 것:

```zig
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
```

- [ ] **Step 4: `comptime` 앵커를 새 모양에 맞춘다**

지울 것:

```zig
    if (CHO[dubeol('r').?.consonant.cho] != 'ㄱ')
        @compileError("dubeol: r must be the initial of GIYEOK");
    if (CHO[dubeol('g').?.consonant.cho] != 'ㅎ')
        @compileError("dubeol: g must be the initial of HIEUH");
    if (JUNG[dubeol('k').?.vowel] != 'ㅏ')
        @compileError("dubeol: k must be the vowel A");
    if (JUNG[dubeol('l').?.vowel] != 'ㅣ')
        @compileError("dubeol: l must be the vowel I");
```

넣을 것:

```zig
    if (CHO[dubeol('r').?.cho.?] != 'ㄱ')
        @compileError("dubeol: r must be the initial of GIYEOK");
    if (CHO[dubeol('g').?.cho.?] != 'ㅎ')
        @compileError("dubeol: g must be the initial of HIEUH");
    if (JUNG[dubeol('k').?.jung.?] != 'ㅏ')
        @compileError("dubeol: k must be the vowel A");
    if (JUNG[dubeol('l').?.jung.?] != 'ㅣ')
        @compileError("dubeol: l must be the vowel I");
```

- [ ] **Step 5: `feed`를 우선순위 표로 다시 쓴다**

`terminal/src/hangul.zig`에서 `feed` · `feedConsonant` · `feedVowel` 셋을
통째로 지우고 아래를 넣는다.

```zig
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
/// 연타 된소리(`cc` = ㄲ받침)와 겹받침을 살리기 위해서다.
///
/// **초+중과 초+중+종에서 초성과 종성의 순서가 반대인 것은 순수하게 두벌식이
/// 정했다.** `가`+`r`은 `각`이어야 하고(종성 먼저) `각`+`e`는 `각ㄷ`이어야
/// 한다(초성 먼저 — 겹받침 ㄱㄷ이 없으니 새 음절이다). 세벌식은 초성과
/// 종성이 겹치는 키가 **하나도 없어서** 이 두 줄에 안 흔들린다.
pub fn feed(buf: Syllable, cand: Cand) Step {
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
        if (cand.jong) |j| return commitAnd(buf, .{ .jong = j });
        if (cand.jung) |v| {
            // 받침 넘기기(도깨비불). **초성이 있을 때만 뜻이 있다** —
            // 종성만 있는 상태에서 넘기면 확정할 음절이 없다.
            if (has_cho and has_jung) return carryFinal(buf, v, cand.jung_opens);
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
        if (cand.cho) |c| return commitAnd(buf, .{ .cho = c });
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
```

- [ ] **Step 6: `erase`가 `jung_opens`를 보존하게 한다**

지울 것:

```zig
pub fn erase(buf: Syllable) ?Syllable {
    if (buf.jong) |j| {
        if (splitFinal(j)) |pair| {
            return .{ .cho = buf.cho, .jung = buf.jung, .jong = pair.head };
        }
        return .{ .cho = buf.cho, .jung = buf.jung };
    }
    if (buf.jung) |v| {
        if (splitVowel(v)) |head| return .{ .cho = buf.cho, .jung = head };
        return .{ .cho = buf.cho };
    }
```

넣을 것:

```zig
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
```

- [ ] **Step 7: `hangul_test`의 세 자리를 고친다**

`terminal/src/hangul_test.zig`에서 지울 것:

```zig
        const jamo = hangul.dubeol(ch) orelse return error.NotAJamoKey;
        const step = hangul.feed(buf, jamo);
```

넣을 것:

```zig
        const cand = hangul.dubeol(ch) orelse return error.NotAJamoKey;
        const step = hangul.feed(buf, cand);
```

지울 것:

```zig
    if (hangul.dubeol('E').?.consonant.jong != null) {
        std.debug.print("FAIL: ㄸ이 받침이 될 수 있다고 되어 있다\n", .{});
        return error.WrongFinal;
    }
    if (hangul.dubeol('R').?.consonant.jong.? != 2) {
```

넣을 것:

```zig
    if (hangul.dubeol('E').?.jong != null) {
        std.debug.print("FAIL: ㄸ이 받침이 될 수 있다고 되어 있다\n", .{});
        return error.WrongFinal;
    }
    if (hangul.dubeol('R').?.jong.? != 2) {
```

- [ ] **Step 8: 검사를 돌린다 — 기존 열넷이 한 글자도 안 바뀐 채 통과해야 한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && ./prepare.sh >/dev/null && zig build test'
```

Expected: `hangul_test: 3-순열 107811단계에서 그릴 수 없는 상태가 0번 OK`까지
전부 통과하고 `PASS`. **`input_test`와 `vt_test`도 통과해야 한다** — 이 Task는
동작을 하나도 안 바꾼다.

- [ ] **Step 9: diff를 센다**

```bash
git diff --stat
git diff | grep '^-' | grep -v '^---'
```

지운 줄이 전부 위 Step들이 명시적으로 지우라고 적은 것인지 확인한다.

- [ ] **Step 10: 커밋**

```bash
git add terminal/src/hangul.zig terminal/src/hangul_test.zig
git commit -m "Let the composition state pick among candidates"
```

---

## Task 2: 종성만 있는 상태를 그린다

**Files:**
- Modify: `terminal/src/hangul.zig` — `Syllable.codepoint()`
- Modify: `terminal/src/hangul_test.zig` — 검사 1과 2
- Modify: `terminal/src/font_test.zig` — 겹받침 호환 자모 실측

- [ ] **Step 1: 겹받침 호환 자모가 unifont에 있는지 먼저 잰다**

HI-M0 실측 3이 홑자모만 쟀다(`ㄷ` `ㄱ` `ㅏ` `ㄸ`). **겹받침을 그리겠다고
정하기 전에 그것이 실제로 구워지는지 본다.**

`terminal/src/font_test.zig`의 기대값 표에 아래 넷을 더한다. 표의 정확한 모양은
파일을 열어 기존 항목을 그대로 따른다(`what` · `cp` 같은 필드 이름을 새로
짓지 말 것).

```
ㄳ U+3133 · ㄵ U+3135 · ㄺ U+313A · ㅄ U+3144
```

**보는 것은 두 가지다** — 비트맵이 있는가, 그리고 `cell_width`가 16인가.
**폭이 16이 아니면 결정 3의 다섯째 줄을 다시 열어야 한다**(조합하는 내내 폭이
안 바뀐다는 HI-M0 실측 3의 전제가 깨진다).

- [ ] **Step 2: 실측을 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && ./prepare.sh >/dev/null && zig build test'
```

Expected: 넷 다 비트맵이 있고 `cell_width=16`.

**여기서 실패하면 멈추고 사용자에게 알린다.** 겹받침이 안 그려지면 종성만
상태를 허용할 수 없고, 세벌식의 종성 전용 키를 다르게 다뤄야 한다.

- [ ] **Step 3: `codepoint()`에 갈래를 더한다**

`terminal/src/hangul.zig`에서 지울 것:

```zig
    pub fn codepoint(self: Syllable) ?u21 {
        const c = self.cho orelse {
            if (self.jong != null) return null;
            const v = self.jung orelse return null;
            return JUNG[v];
        };
```

넣을 것:

```zig
    pub fn codepoint(self: Syllable) ?u21 {
        const c = self.cho orelse {
            const v = self.jung orelse {
                // **종성만은 그려진다**(HI-M2가 넓혔다). `JONG` 표의 값이
                // 전부 호환 자모라 겹받침까지 한 글자다 — `ㄳ`도 `ㅄ`도
                // 코드포인트 하나이고 `font_test`가 굽는 것을 봤다.
                //
                // 두벌식은 이 상태를 **안 만든다**. 자음 키가 전부 초성
                // 후보를 갖고, 빈 상태의 우선순위가 초성 먼저이기 때문이다.
                // 세벌식은 종성 전용 키가 따로 있어서 만든다.
                if (self.jong) |j| return JONG[j];
                return null;
            };
            // 중성+종성은 완성형에 없다(design 결정 3).
            if (self.jong != null) return null;
            return JUNG[v];
        };
```

- [ ] **Step 4: 검사 1과 2를 옮긴다**

`terminal/src/hangul_test.zig`에서 지울 것:

```zig
        .{ .s = .{ .cho = 3, .jung = 0, .jong = 4 }, .cp = '단', .what = "받침까지 완성형" },
    };
```

넣을 것:

```zig
        .{ .s = .{ .cho = 3, .jung = 0, .jong = 4 }, .cp = '단', .what = "받침까지 완성형" },
        .{ .s = .{ .jong = 4 }, .cp = 'ㄴ', .what = "종성만은 호환 자모" },
        .{ .s = .{ .jong = 3 }, .cp = 'ㄳ', .what = "겹받침만도 호환 자모" },
    };
```

지울 것:

```zig
    // ── 2. 그릴 수 없는 세 상태 (design 결정 3) ───────────────────────
    //
    // **모아주기를 뺀 것이 여기서 코드가 된다.** 완성형에 없는 조합이고
    // unifont가 첫가끝 자모를 겹쳐 그려 주지 않는다(HI-M0 실측 3). 아래
    // 검사 7이 "오토마타가 이 상태를 만들지 않는다"까지 본다.
    const cannot = [_]hangul.Syllable{
        .{ .cho = 3, .jong = 4 },
        .{ .jung = 0, .jong = 4 },
        .{ .jong = 4 },
    };
    for (cannot) |s| {
        if (s.codepoint() != null) {
            std.debug.print("FAIL: 그릴 수 없는 조합이 코드포인트를 냈다\n", .{});
            return error.UnexpectedCodepoint;
        }
    }
    std.debug.print("hangul_test: 모아주기 상태 셋은 그릴 것이 없다 OK\n", .{});
```

넣을 것:

```zig
    // ── 2. 그릴 수 없는 두 상태 (design 결정 3) ───────────────────────
    //
    // **모아주기를 뺀 것이 여기서 코드가 된다.** 완성형에 없는 조합이고
    // unifont가 첫가끝 자모를 겹쳐 그려 주지 않는다(HI-M0 실측 3). 아래
    // 검사 7이 "오토마타가 이 상태를 만들지 않는다"까지 본다.
    //
    // **셋이 아니라 둘이다.** 종성만은 HI-M2에서 그릴 수 있는 쪽으로 옮겼다 —
    // 세벌식이 그 상태를 실제로 만들고, 호환 자모 하나로 그려진다.
    const cannot = [_]hangul.Syllable{
        .{ .cho = 3, .jong = 4 },
        .{ .jung = 0, .jong = 4 },
    };
    for (cannot) |s| {
        if (s.codepoint() != null) {
            std.debug.print("FAIL: 그릴 수 없는 조합이 코드포인트를 냈다\n", .{});
            return error.UnexpectedCodepoint;
        }
    }
    std.debug.print("hangul_test: 모아주기 상태 둘은 그릴 것이 없다 OK\n", .{});
```

- [ ] **Step 5: 검사를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && ./prepare.sh >/dev/null && zig build test'
```

Expected: 검사 1이 여섯 줄, 검사 2가 "둘", 그리고 **검사 7의 3-순열이 그대로
0번**. 두벌식이 종성만 상태를 안 만들기 때문에 이 값이 안 바뀌는 것이 맞다.

- [ ] **Step 6: 커밋**

```bash
git add terminal/src/hangul.zig terminal/src/hangul_test.zig terminal/src/font_test.zig
git commit -m "Draw a lone final consonant with its compatibility jamo"
```

---

## Task 3: 자판마다 다른 성질은 bool 둘이다

**Files:**
- Modify: `terminal/src/hangul.zig` — `Layout` enum · 된소리 표 둘 · `feed` 인자
- Modify: `terminal/src/input.zig` — `State.hangul_layout`
- Modify: `terminal/src/hangul_test.zig` — `typeAll`이 자판을 받는다

- [ ] **Step 1: 된소리 표 둘을 더한다**

`terminal/src/hangul.zig`의 `finalToInitial` 아래에 넣을 것:

```zig
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
```

- [ ] **Step 2: `Layout` enum을 더한다**

`terminal/src/hangul.zig`의 `dubeol`과 그 `comptime` 앵커 **아래**에 넣을 것.
(자판 셋은 Task 4·5에서 채운다. 지금은 두벌식만 배선한다.)

```zig
/// 한글 자판. **`Shell`·`Keyboard`와 같은 화이트리스트 구조다**
/// (`init/src/config.zig`) — enum이 "무엇을 적을 수 있는가"를, 아래 switch들이
/// "그것이 무엇을 하는가"를 정한다. 이름을 하나 더하면 switch 넷이 전부
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
            .sebeol_3p3 => dubeol(ch),
            .shin_p2 => dubeol(ch),
            .shin_pcs => dubeol(ch),
        };
    }

    /// 받침 넘기기(도깨비불). **두벌식만이다**(design 결정 12).
    ///
    /// 세벌식은 초성 키와 종성 키가 아예 달라서 넘길 이유가 없고, 넘기면
    /// 틀린다 — 3-P3에서 `각`+ㅏ는 `가가`가 아니라 `각ㅏ`가 맞다.
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
```

`.sebeol_3p3`·`.shin_p2`·`.shin_pcs`가 지금 `dubeol`을 가리키는 것은 **자리를
잡아 두는 것**이고 Task 4·5가 채운다. 셋이 다 같은 자판인 채로 `hangul_test`가
통과하는 상태를 만들지 않기 위해, Task 4·5가 끝날 때까지 이 셋을 부르는 검사를
쓰지 않는다.

- [ ] **Step 3: `feed`가 자판을 받게 한다**

`terminal/src/hangul.zig`의 `feed` 시그니처를 바꾸고 두 자리를 자판에 딸리게
한다.

지울 것:

```zig
pub fn feed(buf: Syllable, cand: Cand) Step {
    const has_cho = buf.cho != null;
```

넣을 것:

```zig
pub fn feed(buf: Syllable, cand: Cand, layout: Layout) Step {
    const has_cho = buf.cho != null;
```

지울 것(`has_jong` 갈래의 종성 자리):

```zig
        if (cand.cho) |c| return commitAnd(buf, .{ .cho = c });
        if (cand.jong) |j| return commitAnd(buf, .{ .jong = j });
        if (cand.jung) |v| {
            // 받침 넘기기(도깨비불). **초성이 있을 때만 뜻이 있다** —
            // 종성만 있는 상태에서 넘기면 확정할 음절이 없다.
            if (has_cho and has_jung) return carryFinal(buf, v, cand.jung_opens);
            return commitAnd(buf, .{ .jung = v, .jung_opens = cand.jung_opens });
        }
```

넣을 것:

```zig
        if (cand.cho) |c| return commitAnd(buf, .{ .cho = c });
        if (cand.jong) |j| {
            // 연타 된소리 — `cc`가 ㄲ받침이 되는 자리다. **겹받침을 먼저 본
            // 뒤이므로 `joinFinal`과 안 겹친다**(ㄱ+ㄱ은 겹받침 표에 없다).
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
```

지울 것(`has_cho` 갈래의 초성 자리):

```zig
        if (cand.cho) |c| return commitAnd(buf, .{ .cho = c });
        if (cand.jong) |j| return commitAnd(buf, .{ .jong = j });
        return .{ .buf = buf };
    }

    if (has_jung) {
```

넣을 것:

```zig
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
```

- [ ] **Step 4: `input.zig`에 자판 필드를 만든다**

`terminal/src/input.zig`의 `hangul_buf` 아래에 넣을 것:

```zig
    /// 한글 자판(HI-M2). **부팅 내내 상수다** — 설정 파일이 정하고 argv로
    /// 오며, 런타임 전환은 안 한다(design 결정 7).
    ///
    /// **기본값이 `.dubeol`인 것은 이 필드의 뜻이 아니다.** 설정의 기본값은
    /// `init/src/config.zig`의 `Config`에 있고 그것이 진실이다. 여기 값은
    /// `main.zig`가 argv로 매번 덮어쓴다.
    hangul_layout: hangul.Layout = .dubeol,
```

그리고 `hangulLayer`에서 지울 것:

```zig
        const jamo = hangul.dubeol(ch) orelse {
            self.commitHangul();
            return null;
        };
        const step = hangul.feed(self.hangul_buf, jamo);
```

넣을 것:

```zig
        const cand = self.hangul_layout.lookup(ch) orelse {
            self.commitHangul();
            return null;
        };
        const step = hangul.feed(self.hangul_buf, cand, self.hangul_layout);
```

- [ ] **Step 5: `hangul_test`가 자판을 받게 한다**

`terminal/src/hangul_test.zig`에서 지울 것:

```zig
fn typeAll(keys: []const u8, out: []u8) ![]const u8 {
    var buf = hangul.Syllable{};
    var len: usize = 0;
    for (keys) |ch| {
        const cand = hangul.dubeol(ch) orelse return error.NotAJamoKey;
        const step = hangul.feed(buf, cand);
        if (step.commit) |cp| len += try std.unicode.utf8Encode(cp, out[len..]);
        buf = step.buf;
    }
    if (buf.codepoint()) |cp| len += try std.unicode.utf8Encode(cp, out[len..]);
    return out[0..len];
}

/// 친 것과 나온 것을 짝지어 본다.
fn expectTyped(keys: []const u8, want: []const u8) !void {
    var out: [64]u8 = undefined;
    const got = try typeAll(keys, &out);
    if (std.mem.eql(u8, got, want)) {
        std.debug.print("hangul_test: \"{s}\" -> \"{s}\" OK\n", .{ keys, want });
        return;
    }
    std.debug.print("FAIL: \"{s}\" -> \"{s}\", want \"{s}\"\n", .{ keys, got, want });
    return error.WrongComposition;
}
```

넣을 것:

```zig
/// 자판 하나로 문자열을 통째로 치고 나온 글자를 모은다.
/// **마지막에 남은 조합도 확정한다** — 사람이 Enter를 치는 자리에 해당한다.
///
/// **조합 순서를 통째로 넣고 결과 문자열을 보는 것이 이 검사의 모양이다**
/// (design 위험 2). 갈마들이는 "이 키가 무슨 자모인가"가 아니라 "이 상태에서
/// 이 키가 무엇이 되는가"라, 표와 오토마타를 따로 보면 안 보인다.
fn typeAll(layout: hangul.Layout, keys: []const u8, out: []u8) ![]const u8 {
    var buf = hangul.Syllable{};
    var len: usize = 0;
    for (keys) |ch| {
        const cand = layout.lookup(ch) orelse return error.NotAJamoKey;
        const step = hangul.feed(buf, cand, layout);
        if (step.commit) |cp| len += try std.unicode.utf8Encode(cp, out[len..]);
        buf = step.buf;
    }
    if (buf.codepoint()) |cp| len += try std.unicode.utf8Encode(cp, out[len..]);
    return out[0..len];
}

/// 친 것과 나온 것을 짝지어 본다.
fn expectTyped(layout: hangul.Layout, keys: []const u8, want: []const u8) !void {
    var out: [64]u8 = undefined;
    const got = try typeAll(layout, keys, &out);
    if (std.mem.eql(u8, got, want)) {
        std.debug.print("hangul_test: [{s}] \"{s}\" -> \"{s}\" OK\n", .{
            @tagName(layout), keys, want,
        });
        return;
    }
    std.debug.print("FAIL: [{s}] \"{s}\" -> \"{s}\", want \"{s}\"\n", .{
        @tagName(layout), keys, got, want,
    });
    return error.WrongComposition;
}
```

`expectTyped` 호출 열넷 전부에 `.dubeol,`을 첫 인자로 더한다. 예:

```zig
    try expectTyped(.dubeol, "g", "ㅎ");
```

그리고 검사 7의 3-순열에서 지울 것:

```zig
            s = hangul.feed(s, hangul.dubeol(ch).?).buf;
```

넣을 것:

```zig
            s = hangul.feed(s, hangul.dubeol(ch).?, .dubeol).buf;
```

- [ ] **Step 6: 검사를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && ./prepare.sh >/dev/null && zig build test'
```

Expected: 전부 통과. 로그가 `hangul_test: [dubeol] "rk" -> "가" OK` 모양으로
바뀐다.

- [ ] **Step 7: 커밋**

```bash
git add terminal/src/hangul.zig terminal/src/hangul_test.zig terminal/src/input.zig
git commit -m "Give each layout its two composition traits"
```

---

## Task 4: 공세벌 3-P3

**Files:**
- Modify: `terminal/src/hangul.zig` — `sebeol3P3` + `comptime` 앵커
- Modify: `terminal/src/hangul_test.zig` — 조합 순서 검사

**출처:** `/Users/dp/Repository/_input-method/PatInputMethod/macOS/Patal/
Layouts/Han3P3.swift`의 `_chosungMap` · `_jungsungMap` · `_jongsungMap`.
연타(`kk`)와 겹모음(`/f`)과 겹받침(`wx`)은 **표에 안 적는다** — 각각
`tenseInitial` · `joinVowel` · `joinFinal`이 이미 한다.

- [ ] **Step 1: 표를 넣는다**

`terminal/src/hangul.zig`의 두벌식 `comptime` 앵커 아래에 넣을 것:

```zig
/// 갈마들이 공세벌식 3-P3(https://pat.im/1128). **인자는 쿼티 배치의 문자다.**
///
/// **초성은 오른손, 중성과 종성은 왼손이다.** 그래서 초성이 중성·종성과
/// 겹치는 키가 하나도 없고, 겹치는 것은 중성과 종성 여섯 자리뿐이다
/// (`c v r e f d`) — 그 여섯을 가르는 것이 `feed`의 우선순위다.
///
/// **숫자 열이 자모다.** `1`이 종성 ㅋ, `3`이 종성 ㅂ, `9`가 중성 ㅜ다.
/// 그래서 `nonSyllable`이 없으면 한글 상태에서 숫자를 칠 수가 없다.
fn sebeol3P3(ch: u8) ?Cand {
    return switch (ch) {
        // 초성 — 오른손. 연타는 `tenseInitial`이 한다(`kk` = ㄲ).
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

        // 종성만. 연타는 `tenseFinal`, 겹받침 시퀀스는 `joinFinal`이 한다.
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
```

- [ ] **Step 2: `comptime` 앵커를 건다**

바로 아래에 넣을 것:

```zig
// design 위험 1 — 표를 옮겨 적으면서 사람이 틀린다. HI-M0에서 실제로 두 번
// 틀렸고(`g`를 ㄱ으로 읽었다) 처방이 `dubeol`의 앵커 넷이었다. **자판을 셋 더
// 옮기는 이 milestone이 같은 위험을 셋 더 진다.**
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
```

- [ ] **Step 3: `Layout.lookup`을 배선한다**

지울 것:

```zig
            .sebeol_3p3 => dubeol(ch),
```

넣을 것:

```zig
            .sebeol_3p3 => sebeol3P3(ch),
```

- [ ] **Step 4: 조합 순서 검사를 더한다**

`terminal/src/hangul_test.zig`의 검사 6(Backspace) **앞**에 넣을 것:

```zig
    // ── 5.5. 공세벌 3-P3 (design 위험 2) ─────────────────────────────
    //
    // **여덟이 서로 다른 갈래를 밟는다.** 기본 음절 · 받침 · 갈마들이(같은
    // 키가 중성이자 종성) · 연타 된소리(초성) · 연타 된소리(종성) · 겹모음을
    // 여는 키 · 안 여는 키 · **받침 넘기기가 없다는 것**.
    try expectTyped(.sebeol_3p3, "kf", "가");
    try expectTyped(.sebeol_3p3, "kfx", "각");
    // `c`는 초성 뒤에서는 중성 ㅔ이고, 초성+중성 뒤에서는 종성 ㄷ이다.
    try expectTyped(.sebeol_3p3, "kc", "게");
    try expectTyped(.sebeol_3p3, "kfc", "갇");
    // 연타 — 초성 `kk`는 ㄲ, 종성 `xx`는 ㄲ받침.
    try expectTyped(.sebeol_3p3, "kkf", "까");
    try expectTyped(.sebeol_3p3, "kfxx", "갂");
    // 겹모음은 **오른쪽 ㅗ에서만** 열린다. `/`는 열고 `v`는 안 연다.
    try expectTyped(.sebeol_3p3, "k/f", "과");
    try expectTyped(.sebeol_3p3, "kvf", "곺"); // ㅗ가 안 열려서 `f`가 종성 ㅍ
    // **받침 넘기기가 없다**(design 결정 12). 두벌식이라면 `가구`가 될 자리다.
    //
    // **중성 후보만 있는 키를 골라야 한다.** `f`는 중성 ㅏ이자 종성 ㅍ이라
    // 우선순위(종성 → 중성)에서 종성이 먼저 걸려 `각ㅍ`이 나온다 — 그것도
    // 맞는 동작이지만 받침 넘기기를 보는 검사가 아니다. `b`는 중성 ㅜ뿐이다.
    try expectTyped(.sebeol_3p3, "kfxb", "각ㅜ");
    // 종성 후보가 있는 키는 새 종성으로 간다. 위와 짝이다.
    try expectTyped(.sebeol_3p3, "kfxf", "각ㅍ");
    // 겹받침은 두벌식과 같은 `joinFinal` 표를 쓴다.
    try expectTyped(.sebeol_3p3, "kfxq", "갃");
    // 종성 전용 키를 먼저 누르면 **종성만 상태**가 된다(Task 2).
    try expectTyped(.sebeol_3p3, "x", "ㄱ");
```

- [ ] **Step 5: 검사를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && ./prepare.sh >/dev/null && zig build test'
```

Expected: 열하나가 전부 OK. **실패하면 기대값을 먼저 의심한다** — HI-M0 실측 5가
"코드가 맞았고 기대값이 틀렸다"였다. 손으로 다시 세기 전에 `comptime` 앵커
다섯이 통과한 것을 근거로 삼는다.

- [ ] **Step 6: 커밋**

```bash
git add terminal/src/hangul.zig terminal/src/hangul_test.zig
git commit -m "Add the sebeol 3-P3 layout"
```

---

## Task 5: 신세벌 P2와 PCS

**Files:**
- Modify: `terminal/src/hangul.zig` — `shinP2` · `shinPcs` + 앵커
- Modify: `terminal/src/hangul_test.zig` — 갈마들이 검사

**출처:** `Han3ShinP2.swift`와 `Han3ShinPCS.swift`. **둘의 차이는 넷뿐이다** —
초성 ㅌ·ㅋ의 자리(`'`·`/` 대 `,`·`.`)와, P2에만 있는 `/`(중성 ㅗ, 겹모음을
연다)다.

- [ ] **Step 1: 공통 표를 넣는다**

`terminal/src/hangul.zig`의 3-P3 앵커 아래에 넣을 것:

```zig
/// 신세벌식 P2·PCS의 **공통 부분**. 둘의 차이는 넷뿐이라 나머지를 여기 모은다.
///
/// **오른손 블록 열다섯이 전부 중성이자 종성이다**(design 결정 11의 표).
/// 신세벌식이 "갈마들이"라 불리는 이유가 이것이고, 이 자판을 옮기면서 후보
/// struct가 필요해졌다.
///
/// **대문자는 중성을 강제한다.** 왼손 글쇠가 중성도 종성도 되는데 Shift를
/// 누르면 종성 후보가 빠진다 — 그래야 `앋`이 될 자리에서 `아ㄷ`을 칠 수 있다.
/// Patal이 `"f": 중성.아, "F": 중성.아`로 적어 둔 것이 그 뜻이다.
fn shinCommon(ch: u8) ?Cand {
    return switch (ch) {
        // 초성 — 오른손. 연타는 `tenseInitial`이 한다.
        'k' => .{ .cho = 0 }, // ㄱ
        'h' => .{ .cho = 2 }, // ㄴ
        'u' => .{ .cho = 3 }, // ㄷ
        'y' => .{ .cho = 5 }, // ㄹ
        ';' => .{ .cho = 7 }, // ㅂ
        'n' => .{ .cho = 9 }, // ㅅ
        'j' => .{ .cho = 11 }, // ㅇ
        'l' => .{ .cho = 12 }, // ㅈ
        'm' => .{ .cho = 18 }, // ㅎ

        // 초성이자 중성 — 갈마들이 셋. 빈 상태에선 초성이고 초성 뒤에선
        // 중성이다(`feed`의 우선순위: 초성만 상태는 중성이 첫째).
        'i' => .{ .cho = 6, .jung = 18, .jung_opens = true }, // ㅁ / ㅡ
        'o' => .{ .cho = 14, .jung = 13, .jung_opens = true }, // ㅊ / ㅜ
        'p' => .{ .cho = 17, .jung = 8, .jung_opens = true }, // ㅍ / ㅗ

        // 중성이자 종성 — 왼손 열다섯.
        'f' => .{ .jung = 0, .jong = 26 }, // ㅏ / ㅍ
        'e' => .{ .jung = 1, .jong = 17 }, // ㅐ / ㅂ
        'w' => .{ .jung = 2, .jong = 8 }, // ㅑ / ㄹ
        'q' => .{ .jung = 3, .jong = 19 }, // ㅒ / ㅅ
        'r' => .{ .jung = 4, .jong = 25 }, // ㅓ / ㅌ
        'c' => .{ .jung = 5, .jong = 1 }, // ㅔ / ㄱ
        't' => .{ .jung = 6, .jong = 24 }, // ㅕ / ㅋ
        's' => .{ .jung = 7, .jong = 4 }, // ㅖ / ㄴ
        'v' => .{ .jung = 8, .jong = 22 }, // ㅗ / ㅈ — 왼쪽 ㅗ라 안 연다
        'x' => .{ .jung = 12, .jong = 20 }, // ㅛ / ㅆ
        'b' => .{ .jung = 13, .jong = 23 }, // ㅜ / ㅊ — 왼쪽 ㅜ라 안 연다
        'a' => .{ .jung = 17, .jong = 21 }, // ㅠ / ㅇ
        'g' => .{ .jung = 18, .jong = 7 }, // ㅡ / ㄷ — 왼쪽 ㅡ라 안 연다
        'z' => .{ .jung = 19, .jong = 16 }, // ㅢ / ㅁ
        'd' => .{ .jung = 20, .jong = 27 }, // ㅣ / ㅎ

        // 대문자 — **중성만 남는다.**
        'F' => .{ .jung = 0 },
        'E' => .{ .jung = 1 },
        'W' => .{ .jung = 2 },
        'Q' => .{ .jung = 3 },
        'R' => .{ .jung = 4 },
        'C' => .{ .jung = 5 },
        'T' => .{ .jung = 6 },
        'S' => .{ .jung = 7 },
        'V' => .{ .jung = 8 },
        'X' => .{ .jung = 12 },
        'B' => .{ .jung = 13 },
        'A' => .{ .jung = 17 },
        'G' => .{ .jung = 18 },
        'Z' => .{ .jung = 19 },
        'D' => .{ .jung = 20 },
        else => null,
    };
}

/// 신세벌식 P2. 공통에 더해 초성 ㅌ이 `'`, ㅋ이 `/`이고, **`/`는 중성 ㅗ이기도
/// 하다** — 이 자판에만 있는 네 번째 갈마들이 키다.
fn shinP2(ch: u8) ?Cand {
    return switch (ch) {
        '\'' => .{ .cho = 16 }, // ㅌ
        '/' => .{ .cho = 15, .jung = 8, .jung_opens = true }, // ㅋ / ㅗ
        else => shinCommon(ch),
    };
}

/// 신세벌식 PCS. 오른쪽 새끼손가락 키가 없는 50% 미만 키보드를 위한 배열이라
/// 초성 ㅌ·ㅋ이 `,`와 `.`으로 내려와 있다. **`/`와 `'`는 자모가 아니다.**
fn shinPcs(ch: u8) ?Cand {
    return switch (ch) {
        ',' => .{ .cho = 16 }, // ㅌ
        '.' => .{ .cho = 15 }, // ㅋ
        else => shinCommon(ch),
    };
}
```

- [ ] **Step 2: 앵커를 건다**

바로 아래에 넣을 것:

```zig
// 신세벌의 앵커는 여섯이다. 갈마들이 두 종류를 각각 하나씩(`c`가 중성이자
// 종성, `p`가 초성이자 중성), **대문자가 종성 후보를 떨어뜨리는 것**,
// 겹모음을 여는 쪽과 안 여는 쪽(`p`와 `v`가 둘 다 ㅗ), 그리고 **P2와 PCS를
// 가르는 자리**다.
comptime {
    if (JUNG[shinPcs('c').?.jung.?] != 'ㅔ' or JONG[shinPcs('c').?.jong.?] != 'ㄱ')
        @compileError("shin: c must be both the vowel E and the final GIYEOK");
    if (CHO[shinPcs('p').?.cho.?] != 'ㅍ' or JUNG[shinPcs('p').?.jung.?] != 'ㅗ')
        @compileError("shin: p must be both the initial PIEUP and the vowel O");
    if (shinPcs('C').?.jong != null)
        @compileError("shin: shift must drop the final candidate");
    if (!shinPcs('p').?.jung_opens or shinPcs('v').?.jung_opens)
        @compileError("shin: only the right-hand O opens a diphthong");
    if (CHO[shinPcs(',').?.cho.?] != 'ㅌ' or shinPcs('\'') != null)
        @compileError("shin PCS: TIEUT is on comma and the quote is not a jamo");
    if (CHO[shinP2('\'').?.cho.?] != 'ㅌ' or CHO[shinP2('/').?.cho.?] != 'ㅋ')
        @compileError("shin P2: TIEUT is on quote and KIEUK on slash");
}
```

- [ ] **Step 3: `Layout.lookup`을 배선한다**

지울 것:

```zig
            .shin_p2 => dubeol(ch),
            .shin_pcs => dubeol(ch),
```

넣을 것:

```zig
            .shin_p2 => shinP2(ch),
            .shin_pcs => shinPcs(ch),
```

- [ ] **Step 4: 갈마들이 검사를 더한다**

`terminal/src/hangul_test.zig`의 3-P3 검사 아래에 넣을 것:

```zig
    // ── 5.6. 신세벌 PCS (design 위험 2) ──────────────────────────────
    //
    // **갈마들이가 두 종류다.** `p`는 초성 ㅍ이자 중성 ㅗ이고, `c`는 중성
    // ㅔ이자 종성 ㄱ이다. 앞의 것은 "빈 상태냐 초성 뒤냐"로 갈리고 뒤의 것은
    // "초성만이냐 초성+중성이냐"로 갈린다 — **같은 표로 두 갈림을 다 만드는
    // 것이 후보 struct의 값이다.**
    try expectTyped(.shin_pcs, "kf", "가");
    try expectTyped(.shin_pcs, "p", "ㅍ"); // 빈 상태 → 초성
    try expectTyped(.shin_pcs, "kp", "고"); // 초성 뒤 → 중성
    try expectTyped(.shin_pcs, "kc", "게"); // 초성 뒤 → 중성
    try expectTyped(.shin_pcs, "kfc", "각"); // 초성+중성 뒤 → 종성
    // 연타 — 초성 `kk`는 ㄲ, 종성 `cc`는 ㄲ받침. **`cc`가 종성이 중성보다
    // 먼저여야 하는 유일한 증거다**(착수 전 확정 1).
    try expectTyped(.shin_pcs, "kkf", "까");
    try expectTyped(.shin_pcs, "kfcc", "갂");
    // 겹모음은 오른쪽에서만 열린다. `p`는 열고 `v`는 안 연다.
    try expectTyped(.shin_pcs, "kpf", "과");
    try expectTyped(.shin_pcs, "kvf", "곺");
    // 대문자가 종성 후보를 떨어뜨린다. `kfg`는 `갇`이지만 `kfG`는 `가ㅡ`다.
    try expectTyped(.shin_pcs, "kfg", "갇");
    try expectTyped(.shin_pcs, "kfG", "가ㅡ");
    // 받침 넘기기가 없다. **신세벌은 왼손 열다섯이 전부 중성이자 종성이라
    // 중성 후보만 있는 키가 대문자뿐이다** — `F`가 그것이다.
    try expectTyped(.shin_pcs, "kfcF", "각ㅏ");
    // 겹받침 — `wd`(ㄹ+ㅎ)가 ㅀ이다.
    try expectTyped(.shin_pcs, "kfwd", "갏");
    // ㅌ과 ㅋ은 PCS에서 `,`와 `.`이다.
    try expectTyped(.shin_pcs, ",f", "타");
    try expectTyped(.shin_pcs, ".f", "카");

    // ── 5.7. 신세벌 P2 — PCS와 갈리는 자리만 본다 ────────────────────
    //
    // **나머지가 같다는 것은 `shinCommon` 하나를 공유하는 것으로 이미 서 있다.**
    // 여기서 볼 것은 갈린 넷뿐이다.
    try expectTyped(.shin_p2, "'f", "타"); // ㅌ이 `'`
    try expectTyped(.shin_p2, "/f", "카"); // ㅋ이 `/`
    try expectTyped(.shin_p2, "k/f", "과"); // `/`가 중성 ㅗ이기도 하다
    try expectTyped(.shin_p2, "kf", "가");
```

- [ ] **Step 5: 검사를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && ./prepare.sh >/dev/null && zig build test'
```

Expected: 열아홉이 전부 OK.

- [ ] **Step 6: 커밋**

```bash
git add terminal/src/hangul.zig terminal/src/hangul_test.zig
git commit -m "Add the shin-sebeol P2 and PCS layouts"
```

---

## Task 6: 한글 상태에서 숫자와 기호를 친다

**Files:**
- Modify: `terminal/src/hangul.zig` — `Layout.nonSyllable`
- Modify: `terminal/src/input.zig` — `hangulLayer`에 갈래 하나
- Modify: `terminal/src/input_test.zig` — 검사 둘

- [ ] **Step 1: 표를 넣는다**

`terminal/src/hangul.zig`의 신세벌 앵커 아래에 넣을 것:

```zig
/// 한글 상태에서 자모가 아닌 것을 내는 키(Patal의 `nonSyllableMap`).
///
/// **세벌식은 이것이 없으면 숫자를 못 친다.** 3-P3은 숫자 열이 자모라
/// (`1`이 종성 ㅋ) 되돌려 줄 자리가 필요하고, 신세벌 PCS는 오른쪽 새끼손가락
/// 키가 없는 키보드를 가정해서 괄호와 따옴표를 왼쪽으로 옮겨 놓았다.
///
/// **두벌식은 빈 표다.** 두벌식에서 숫자 키는 애초에 자모가 아니라서
/// `lookup`이 null을 주고, 그러면 기존 길(확정하고 그 키의 바이트를 보낸다)로
/// 흘러간다.
///
/// **`u21`인 이유는 P2가 `✕`·`○`·`△` 같은 기호를 주기 때문이다.**
/// 나가는 길은 `input.zig`의 `.bytes`이고 `commit_buf`가 아니다 — 조합 중이던
/// 음절과 이 기호가 **둘 다** 나가야 하는데 `commit_buf`는 하나만 담는다.
pub fn nonSyllable(self: Layout, ch: u8) ?u21 {
    return switch (self) {
        .dubeol => null,
        .sebeol_3p3 => switch (ch) {
            'Y' => '/',
            'U' => '7',
            'I' => '8',
            'O' => '9',
            'P' => ';',
            'G' => '<',
            'H' => '\'',
            'J' => '4',
            'K' => '5',
            'L' => '6',
            'B' => '>',
            'N' => '0',
            'M' => '1',
            '<' => '2',
            '>' => '3',
            else => null,
        },
        .shin_p2 => switch (ch) {
            'Y' => '✕',
            'U' => '○',
            'I' => '△',
            'O' => '※',
            'P' => ';',
            'H' => '□',
            'J' => '\'',
            'K' => '"',
            'L' => '·',
            '"' => '/',
            'N' => '―',
            'M' => '…',
            else => null,
        },
        .shin_pcs => switch (ch) {
            'Y' => '{',
            'U' => '}',
            'I' => '\'',
            'O' => '"',
            'P' => ';',
            'H' => '[',
            'J' => ']',
            'K' => ',',
            'L' => '.',
            'N' => '(',
            'M' => ')',
            else => null,
        },
    };
}
```

**이 함수는 `Layout` enum 안에 넣는다** — `lookup`·`carriesFinal`·
`tenseByRepeat`과 같은 자리다.

- [ ] **Step 2: `hangulLayer`에 갈래를 더한다**

`terminal/src/input.zig`에서 지울 것:

```zig
        const cand = self.hangul_layout.lookup(ch) orelse {
            self.commitHangul();
            return null;
        };
```

넣을 것:

```zig
        // 자판이 되돌려 주는 기호(세벌식의 숫자 열 등). **조합 중이던 음절과
        // 이 기호가 둘 다 나가야 한다.** `commit_buf`는 코드포인트 하나짜리라
        // 둘을 못 담으므로 음절은 그쪽으로, 기호는 `.bytes`로 내보낸다 —
        // `readKeys`가 `takeCommit()`을 그 키의 바이트보다 **먼저** 비우므로
        // 순서가 저절로 맞다(HI-M1 실측 2).
        if (self.hangul_layout.nonSyllable(ch)) |cp| {
            self.commitHangul();
            const n = std.unicode.utf8Encode(cp, &self.seq) catch return .hangul;
            return .{ .bytes = self.seq[0..n] };
        }
        const cand = self.hangul_layout.lookup(ch) orelse {
            self.commitHangul();
            return null;
        };
```

- [ ] **Step 3: 검사를 더한다**

`terminal/src/input_test.zig`의 한글 검사(24~31) 뒤에 검사 둘을 더한다. 기존
헬퍼의 이름과 모양은 파일을 열어 그대로 따른다 — **새 헬퍼를 만들지 않는다.**

보는 것은 둘이다.

1. **3-P3에서 `Shift+M`이 `1`을 낸다.** 한글이 켜져 있고 조합이 비어 있을 때다.
2. **조합 중이면 음절이 먼저 나간다.** `kf`(가)를 친 뒤 `Shift+M`을 누르면
   나가는 바이트가 `가` 세 바이트 **다음에** `1`이다. **이 순서가 검사의
   전부다** — 뒤집히면 `1가`가 된다.

두 번째는 `handleKey`만으로는 못 본다(`takeCommit`과 `.bytes`가 갈려 있다).
`readKeys`를 거치는 기존 검사가 있으면 그것을 따르고, 없으면 `handleKey` 뒤에
`takeCommit()`을 부르고 그 다음 action의 바이트를 붙여 두 슬라이스를 이어
비교한다 — **`readKeys`가 하는 것과 같은 순서로.**

- [ ] **Step 4: 검사를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && ./prepare.sh >/dev/null && zig build test'
```

Expected: 전부 통과.

- [ ] **Step 5: `input.zig`의 diff를 사용자에게 보여 준다**

```bash
git diff terminal/src/input.zig
```

`input.zig`는 한글 이야기만이 아니므로 diff를 남긴다(HANDOFF의 협업 규율).

- [ ] **Step 6: 커밋**

```bash
git add terminal/src/hangul.zig terminal/src/input.zig terminal/src/input_test.zig
git commit -m "Let the sebeol layouts type digits and symbols"
```

---

## Task 7: 설정 두 줄과 드보락

**Files:**
- Modify: `init/src/config.zig` — enum 둘 · `Config` 필드 둘 · `parse` · `save`
- Modify: `init/src/config_test.zig` — 검사
- Modify: `init/src/main.zig` — argv 5칸 → 7칸
- Modify: `terminal/src/main.zig` — `args[5]` · `args[6]`
- Modify: `terminal/src/input.zig` — 드보락 `keymap` · `latin_layout` · 기본값
- Modify: `terminal/src/input_test.zig` — 기존 한글 검사에 `.dubeol` 명시

- [ ] **Step 1: `config.zig`에 enum 둘을 더한다**

`init/src/config.zig`의 `Keyboard` 아래에 넣을 것:

```zig
/// 한글 자판(HI design 결정 7). **`Shell`·`Keyboard`와 같은 화이트리스트
/// 구조다** — enum에 없는 이름은 파싱을 통과할 수 없다.
///
/// **이름이 `terminal/src/hangul.zig`의 `Layout`과 짝이어야 한다.** 여기가
/// "무엇을 적을 수 있는가"이고 저기가 "그것이 어떻게 조합하는가"인데, 둘을
/// 잇는 것은 argv의 문자열 하나뿐이라 컴파일러가 못 잡는다. **어긋나면 증상은
/// "설정을 적었는데 기본 자판으로 뜬다"이고 로그에 자판 이름이 찍히므로
/// 게이트가 본다**(Task 8).
pub const HangulLayout = enum {
    dubeol,
    sebeol_3p3,
    shin_p2,
    shin_pcs,

    pub fn arg(self: HangulLayout) [:0]const u8 {
        return switch (self) {
            .dubeol => "dubeol",
            .sebeol_3p3 => "sebeol_3p3",
            .shin_p2 => "shin_p2",
            .shin_pcs => "shin_pcs",
        };
    }
};

/// 영문 자판. **한글 자판과 직교한다**(HI design 결정 13) — 한글 배열은 물리
/// 키 위치를 쓰므로 이 값이 무엇이든 안 흔들린다.
pub const LatinLayout = enum {
    qwerty,
    dvorak,

    pub fn arg(self: LatinLayout) [:0]const u8 {
        return switch (self) {
            .qwerty => "qwerty",
            .dvorak => "dvorak",
        };
    }
};
```

- [ ] **Step 2: `Config`에 필드 둘을 더한다**

지울 것:

```zig
pub const Config = struct {
    shell: Shell = .fish,
    keyboard: Keyboard = .apple,
};
```

넣을 것:

```zig
pub const Config = struct {
    shell: Shell = .fish,
    keyboard: Keyboard = .apple,
    /// **기본값이 `shin_pcs`인 것은 `keyboard`가 `apple`인 것과 같은
    /// 근거다** — 이 기계를 쓰는 사람이 쓰는 것이 기본값이다. 두벌식이 더
    /// 흔하다는 것은 이 기계의 사실이 아니다.
    hangul_layout: HangulLayout = .shin_pcs,
    latin_layout: LatinLayout = .qwerty,
};
```

- [ ] **Step 3: `parse`에 키 둘을 더한다**

지울 것:

```zig
        } else {
            std.debug.print("tars-init: unknown config key '{s}'\n", .{key});
        }
```

넣을 것:

```zig
        } else if (std.mem.eql(u8, key, "hangul_layout")) {
            c.hangul_layout = std.meta.stringToEnum(HangulLayout, value) orelse {
                std.debug.print("tars-init: unknown hangul_layout '{s}', falling back to {s}\n", .{
                    value, @tagName(c.hangul_layout),
                });
                continue;
            };
        } else if (std.mem.eql(u8, key, "latin_layout")) {
            c.latin_layout = std.meta.stringToEnum(LatinLayout, value) orelse {
                std.debug.print("tars-init: unknown latin_layout '{s}', falling back to {s}\n", .{
                    value, @tagName(c.latin_layout),
                });
                continue;
            };
        } else {
            std.debug.print("tars-init: unknown config key '{s}'\n", .{key});
        }
```

- [ ] **Step 4: `save`의 씨앗 파일에 두 줄을 더한다**

지울 것:

```zig
        \\keyboard={s}
        \\
    , .{ @tagName(c.shell), @tagName(c.keyboard) }) catch return error.FormatFailed;
```

넣을 것:

```zig
        \\keyboard={s}
        \\# hangul_layout: dubeol | sebeol_3p3 | shin_p2 | shin_pcs
        \\hangul_layout={s}
        \\# latin_layout: qwerty | dvorak
        \\#   한글 자판은 물리 키 위치를 쓰므로 이 값에 안 흔들린다
        \\latin_layout={s}
        \\
    , .{
        @tagName(c.shell),
        @tagName(c.keyboard),
        @tagName(c.hangul_layout),
        @tagName(c.latin_layout),
    }) catch return error.FormatFailed;
```

- [ ] **Step 5: `config_test`에 검사를 더한다**

`init/src/config_test.zig`를 열어 기존 검사의 모양을 그대로 따라 아래 넷을
더한다. **새 헬퍼를 만들지 않는다.**

1. **기본값이 `shin_pcs`와 `qwerty`다** — 빈 문자열을 파싱한 결과.
2. **이름 여섯이 전부 파싱된다** — `hangul_layout` 넷과 `latin_layout` 둘.
3. **모르는 값은 기본값에 머문다** — `hangul_layout=sebul` 같은 오타.
4. **다른 키를 안 건드린다** — `hangul_layout=dubeol`만 적은 파일에서
   `shell`이 여전히 `fish`다.

- [ ] **Step 6: `init/src/main.zig`의 argv를 7칸으로 넓힌다**

`init/src/main.zig`에서 지울 것:

```zig
    argv: [5:null]?[*:0]const u8,
```

넣을 것:

```zig
    argv: [7:null]?[*:0]const u8,
```

`keyboard_arg` 옆에 넣을 것:

```zig
    const hangul_arg = cfg.hangul_layout.arg();
    const latin_arg = cfg.latin_layout.arg();
```

그리고 argv 조립 두 자리를 고친다. terminal 쪽에서 지울 것:

```zig
                keyboard_arg.ptr,
                keyboard_path.cstr(),
            },
```

넣을 것:

```zig
                keyboard_arg.ptr,
                keyboard_path.cstr(),
                hangul_arg.ptr,
                latin_arg.ptr,
            },
```

콘솔 셸 쪽에서 지울 것:

```zig
            .argv = .{ shell_path.ptr, null, null, null, null },
```

넣을 것:

```zig
            .argv = .{ shell_path.ptr, null, null, null, null, null, null },
```

그리고 설정 로그 한 줄을 넓힌다. 지울 것:

```zig
    std.debug.print("tars-init: config shell={s} keyboard={s}\n", .{
        @tagName(cfg.shell), @tagName(cfg.keyboard),
    });
```

넣을 것:

```zig
    // **줄을 새로 만들지 않고 이 줄을 넓힌다.** 다른 체인들이
    // `tars-init: config shell=`로 grep하고 있어서 앞부분이 안 바뀌어야 한다.
    std.debug.print("tars-init: config shell={s} keyboard={s} hangul={s} latin={s}\n", .{
        @tagName(cfg.shell),
        @tagName(cfg.keyboard),
        @tagName(cfg.hangul_layout),
        @tagName(cfg.latin_layout),
    });
```

- [ ] **Step 7: 다른 체인이 이 줄을 어떻게 읽는지 확인한다**

```bash
rg -n 'config shell' --glob '*.sh'
```

Expected: `config/check.sh`가 `tars-init: config shell=fish`와
`tars-init: config shell=zsh`로 grep한다 — **줄 끝에 뭐가 붙어도 안 깨진다.**
`=`로 끝나는 패턴이 있으면 그것도 안 깨진다. **줄 전체를 비교하는 곳이
있으면 거기를 고친다.**

- [ ] **Step 8: 드보락 `keymap`을 더한다**

`terminal/src/input.zig`의 `keymap` 배열 이름을 `qwerty_keymap`으로 바꾸고
드보락을 나란히 둔다. 지울 것:

```zig
const keymap = [_][2]u8{
```

넣을 것:

```zig
const qwerty_keymap = [_][2]u8{
```

배열 끝(`.{ ' ', ' ' }, // 57: KEY_SPACE` 다음 줄의 `};`) 아래에 넣을 것:

```zig
/// 드보락. **쿼티와 같은 칸에 같은 evdev 코드가 온다** — 다른 것은 값뿐이다.
///
/// **한글 자판은 이 표에 안 딸린다**(HI design 결정 13). 한글은 물리 키
/// 위치를 쓰므로 조회는 언제나 `qwerty_keymap`으로 한다. 이 표가 쓰이는 것은
/// 라틴 문자를 PTY로 보낼 때뿐이다.
const dvorak_keymap = [_][2]u8{
    .{ 0, 0 }, //  0: (없음)
    .{ 0x1b, 0x1b }, //  1: KEY_ESC
    .{ '1', '!' }, //  2
    .{ '2', '@' }, //  3
    .{ '3', '#' }, //  4
    .{ '4', '$' }, //  5
    .{ '5', '%' }, //  6
    .{ '6', '^' }, //  7
    .{ '7', '&' }, //  8
    .{ '8', '*' }, //  9
    .{ '9', '(' }, // 10
    .{ '0', ')' }, // 11
    .{ '[', '{' }, // 12: 쿼티의 `-` 자리
    .{ ']', '}' }, // 13: 쿼티의 `=` 자리
    .{ 0x7f, 0x7f }, // 14: KEY_BACKSPACE
    .{ '\t', '\t' }, // 15: KEY_TAB
    .{ '\'', '"' }, // 16: 쿼티 q
    .{ ',', '<' }, // 17: 쿼티 w
    .{ '.', '>' }, // 18: 쿼티 e
    .{ 'p', 'P' }, // 19: 쿼티 r
    .{ 'y', 'Y' }, // 20: 쿼티 t
    .{ 'f', 'F' }, // 21: 쿼티 y
    .{ 'g', 'G' }, // 22: 쿼티 u
    .{ 'c', 'C' }, // 23: 쿼티 i
    .{ 'r', 'R' }, // 24: 쿼티 o
    .{ 'l', 'L' }, // 25: 쿼티 p
    .{ '/', '?' }, // 26: 쿼티 `[`
    .{ '=', '+' }, // 27: 쿼티 `]`
    .{ '\r', '\r' }, // 28: KEY_ENTER
    .{ 0, 0 }, // 29: KEY_LEFTCTRL
    .{ 'a', 'A' }, // 30
    .{ 'o', 'O' }, // 31: 쿼티 s
    .{ 'e', 'E' }, // 32: 쿼티 d
    .{ 'u', 'U' }, // 33: 쿼티 f
    .{ 'i', 'I' }, // 34: 쿼티 g
    .{ 'd', 'D' }, // 35: 쿼티 h
    .{ 'h', 'H' }, // 36: 쿼티 j
    .{ 't', 'T' }, // 37: 쿼티 k
    .{ 'n', 'N' }, // 38: 쿼티 l
    .{ 's', 'S' }, // 39: 쿼티 `;`
    .{ '-', '_' }, // 40: 쿼티 `'`
    .{ '`', '~' }, // 41
    .{ 0, 0 }, // 42: KEY_LEFTSHIFT
    .{ '\\', '|' }, // 43
    .{ ';', ':' }, // 44: 쿼티 z
    .{ 'q', 'Q' }, // 45: 쿼티 x
    .{ 'j', 'J' }, // 46: 쿼티 c
    .{ 'k', 'K' }, // 47: 쿼티 v
    .{ 'x', 'X' }, // 48: 쿼티 b
    .{ 'b', 'B' }, // 49: 쿼티 n
    .{ 'm', 'M' }, // 50
    .{ 'w', 'W' }, // 51: 쿼티 `,`
    .{ 'v', 'V' }, // 52: 쿼티 `.`
    .{ 'z', 'Z' }, // 53: 쿼티 `/`
    .{ 0, 0 }, // 54: KEY_RIGHTSHIFT
    .{ '*', '*' }, // 55: KEY_KPASTERISK
    .{ 0, 0 }, // 56: KEY_LEFTALT
    .{ ' ', ' ' }, // 57: KEY_SPACE
};

/// 영문 자판. **한글 자판과 직교한다**(HI design 결정 13).
pub const LatinLayout = enum { qwerty, dvorak };

// 두 표가 같은 길이여야 한다 — 아니면 한쪽에서만 배열 밖을 읽는다.
// **길이 검사가 두 벌인 이유는 `qwerty_keymap.len`이 여러 곳에서 상한으로
// 쓰이기 때문이다.**
comptime {
    if (dvorak_keymap.len != qwerty_keymap.len)
        @compileError("dvorak_keymap must be the same length as qwerty_keymap");
    if (dvorak_keymap[c.KEY_S][0] != 'o')
        @compileError("dvorak_keymap drifted at KEY_S");
    if (dvorak_keymap[c.KEY_Z][0] != ';')
        @compileError("dvorak_keymap drifted at KEY_Z");
}
```

기존 `keymap` 앵커의 이름도 바꾼다. 지울 것:

```zig
    if (keymap.len != c.KEY_SPACE + 1)
        @compileError("keymap must end exactly at KEY_SPACE");
    if (keymap[c.KEY_1][0] != '1') @compileError("keymap drifted at KEY_1");
    if (keymap[c.KEY_ENTER][0] != '\r') @compileError("keymap drifted at KEY_ENTER");
    if (keymap[c.KEY_A][0] != 'a') @compileError("keymap drifted at KEY_A");
    if (keymap[c.KEY_Z][0] != 'z') @compileError("keymap drifted at KEY_Z");
```

넣을 것:

```zig
    if (qwerty_keymap.len != c.KEY_SPACE + 1)
        @compileError("qwerty_keymap must end exactly at KEY_SPACE");
    if (qwerty_keymap[c.KEY_1][0] != '1') @compileError("keymap drifted at KEY_1");
    if (qwerty_keymap[c.KEY_ENTER][0] != '\r') @compileError("keymap drifted at KEY_ENTER");
    if (qwerty_keymap[c.KEY_A][0] != 'a') @compileError("keymap drifted at KEY_A");
    if (qwerty_keymap[c.KEY_Z][0] != 'z') @compileError("keymap drifted at KEY_Z");
```

- [ ] **Step 9: `State`가 두 표를 갈라 쓰게 한다**

`terminal/src/input.zig`의 `State`에 넣을 것(`hangul_layout` 옆):

```zig
    /// 영문 자판(HI-M2). `hangul_layout`과 마찬가지로 부팅 내내 상수다.
    latin_layout: LatinLayout = .qwerty,
```

그리고 `State`에 헬퍼를 하나 둔다:

```zig
    /// 이 키가 만드는 **라틴 문자**. 영문 자판이 정한다.
    ///
    /// **한글 조회는 이 함수를 안 쓴다**(HI design 결정 13) — 한글 자판은
    /// 물리 키 위치를 쓰므로 언제나 `qwerty_keymap`을 직접 본다. 그 갈림을
    /// 함수 하나로 나눠 두면 "어느 쪽을 봐야 하는가"를 세 곳에서 각각
    /// 판단하지 않아도 된다.
    fn latinChar(self: State, code: u16) u8 {
        const shift: usize = if (self.shifted()) 1 else 0;
        return switch (self.latin_layout) {
            .qwerty => qwerty_keymap[code][shift],
            .dvorak => dvorak_keymap[code][shift],
        };
    }
```

그리고 `keymap`을 읽던 세 자리를 고친다.

**`hangulLayer`(약 581·585줄)** — 지울 것:

```zig
        if (code >= keymap.len) {
            self.commitHangul();
            return null;
        }
        const ch = keymap[code][if (self.shifted()) 1 else 0];
```

넣을 것:

```zig
        if (code >= qwerty_keymap.len) {
            self.commitHangul();
            return null;
        }
        // **언제나 쿼티다**(HI design 결정 13). 드보락을 켜도 한글 배열은 안
        // 흔들린다 — 한글 자판이 쓰는 것은 문자가 아니라 물리 키 위치이고,
        // 그 위치를 부르는 이름이 쿼티 배치의 문자다.
        const ch = qwerty_keymap[code][if (self.shifted()) 1 else 0];
```

**`find` 프롬프트(약 757·758줄)** — 지울 것:

```zig
                    if (code >= keymap.len) return nothing;
                    const ch = keymap[code][if (self.shifted()) 1 else 0];
```

넣을 것:

```zig
                    if (code >= qwerty_keymap.len) return nothing;
                    const ch = self.latinChar(code);
```

**기본 번역(약 871·873줄)** — 지울 것:

```zig
        if (code >= keymap.len) return nothing;
```

넣을 것:

```zig
        if (code >= qwerty_keymap.len) return nothing;
```

그리고 그 아래의 지울 것:

```zig
        const ch = keymap[code][if (self.shifted()) 1 else 0];
```

넣을 것:

```zig
        const ch = self.latinChar(code);
```

**`rg -n 'keymap\[' terminal/src/input.zig`로 남은 자리가 없는지 확인한다.**

- [ ] **Step 10: `terminal/src/main.zig`가 argv를 읽게 한다**

`terminal/src/main.zig:618` 근처에 넣을 것:

```zig
    // 값이 enum 이름과 안 맞으면 기본값으로 떨어진다. **init이 화이트리스트를
    // 이미 거쳤으므로 여기 오는 값은 언제나 맞다** — 이 fallback은 terminal을
    // 손으로 띄울 때를 위한 것이다.
    const hangul_arg: []const u8 = if (args.len > 5) std.mem.span(args[5]) else "shin_pcs";
    const latin_arg: []const u8 = if (args.len > 6) std.mem.span(args[6]) else "qwerty";
    const hangul_layout = std.meta.stringToEnum(hangul.Layout, hangul_arg) orelse .shin_pcs;
    const latin_layout = std.meta.stringToEnum(input.LatinLayout, latin_arg) orelse .qwerty;
```

`key_state`를 만드는 자리에서 두 필드를 채우고, `keyboard=` 로그 옆에 한 줄을
더한다.

```zig
    std.debug.print("terminal: hangul layout={s} latin={s}\n", .{
        @tagName(hangul_layout), @tagName(latin_layout),
    });
```

**이 줄이 게이트의 판정이 된다**(Task 8).

`hangul`을 import하고 있지 않으면 파일 맨 위에 더한다.

- [ ] **Step 11: `State`의 기본값을 옮기고 기존 검사를 명시로 바꾼다**

`terminal/src/input.zig`에서 지울 것:

```zig
    hangul_layout: hangul.Layout = .dubeol,
```

넣을 것:

```zig
    hangul_layout: hangul.Layout = .shin_pcs,
```

그리고 주석의 "기본값이 `.dubeol`인 것은" 문장을 `.shin_pcs`로 고친다.

`terminal/src/input_test.zig`의 한글 검사(24~31)에서 `State`를 만드는 자리마다
`.hangul_layout = .dubeol` 을 명시한다 — **그 검사들은 두벌식을 보고 있고,
이제 그것이 기본값이 아니다.**

- [ ] **Step 12: 검사를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build && zig build test && cd ../terminal && ./prepare.sh >/dev/null && zig build test'
```

Expected: `config_test`·`hangul_test`·`input_test`·`vt_test`·`font_test`가
전부 통과.

- [ ] **Step 13: diff를 사용자에게 보여 준다**

```bash
git diff --stat
git diff terminal/src/input.zig terminal/src/main.zig init/src/main.zig
```

- [ ] **Step 14: 커밋**

```bash
git add init/src/config.zig init/src/config_test.zig init/src/main.zig \
        terminal/src/main.zig terminal/src/input.zig terminal/src/input_test.zig
git commit -m "Let the config file choose the hangul and latin layouts"
```

---

## Task 8: 게이트를 세벌식으로 옮긴다

**Files:**
- Create: `hangul/make_disk.sh`
- Modify: `hangul/check.sh`

- [ ] **Step 1: 설정 디스크를 굽는 스크립트를 만든다**

`hangul/make_disk.sh`를 새로 만든다. **`input/make_disk.sh`를 본보기로 삼되
베끼지 말고 이 체인의 이유를 적는다.**

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# HI 체인용 설정 디스크.
#
# **이 체인이 디스크를 물게 된 이유가 HI-M2다.** HI-M1까지는 자판이 하나라
# 설정과 무관했는데, 이제 `hangul_layout`이 자판을 고른다. 그 값이 설정
# 파일에서 init의 argv를 거쳐 terminal의 조합기까지 닿는 길은 **호스트 검사가
# 절대 못 본다** — `config_test`는 파싱까지만, `hangul_test`는 자판 표만 본다.
#
# **부팅을 하나 더 붙이지 않고 있는 부팅에 디스크를 물린다**(design 결정 14).
# IP가 같은 이유로 같은 방법을 쓴다 — `mkfs.ext2`의 `-d`가 디렉터리 하나를
# 파일시스템 루트로 채워 넣으므로(e2fsprogs 1.43+) 게스트 안에서 타이핑해서
# 심을 필요가 없다.
#
# **심는 값이 기본값과 달라야 한다.** 기본값은 shin_pcs이고 여기 심는 것은
# sebeol_3p3다 — 같은 값을 심으면 설정을 통째로 무시하는 코드도 초록이 뜬다.
SIZE=16M
IMG=../out/hangul.img

mkdir -p ../out
rm -f "$IMG"

# 매 회차 새로 굽는다. 이전 회차의 이미지가 남아 있으면 "설정이 정말 이
# 파일에서 왔는가"가 흐려진다.
SEED="$(mktemp -d)"
cat > "$SEED/tars.conf" <<'EOF'
# HI 체인이 미리 심어 두는 설정. 게스트는 이 파일을 읽기만 한다.
#
# hangul_layout=sebeol_3p3 — **기본값(shin_pcs)이 아닌 것이 요점이다.**
#                            이 한 줄이 조합기를 갈아 끼운다.
hangul_layout=sebeol_3p3
EOF

truncate -s "$SIZE" "$IMG"
mkfs.ext2 -F -q -m 0 -L tars-hangul -d "$SEED" "$IMG"
rm -rf "$SEED"

echo "make_disk: created ${IMG} (${SIZE}, ext2, hangul_layout=sebeol_3p3)"
```

```bash
chmod +x hangul/make_disk.sh
```

- [ ] **Step 2: `check.sh`가 디스크를 굽고 물게 한다**

`hangul/check.sh`의 머리 주석에서 지울 것:

```
# 디스크를 물지 않는다. HI-M1의 한/영은 설정과 무관하다 — 자판과 전환 키가
# 설정으로 가는 것은 HI-M2·M3이고, 그때 이 체인에 2차 부팅이 붙는다.
```

넣을 것:

```
# **디스크를 문다(HI-M2).** `hangul_layout=sebeol_3p3`이 든 이미지를 굽고
# 읽기만 한다. **2차 부팅은 안 붙였다** — 설정이 자판까지 닿는지만 보면 되고,
# 설정을 쓰고 다시 읽는 왕복은 CP 체인이 이미 본다(design 결정 14).
#
# 그래서 **이 체인이 게스트에서 돌리는 자판은 3-P3 하나다.** 두벌식은
# `hangul_test`가, 기본값이 shin_pcs라는 것은 `config_test`가 본다. 그
# 교환을 받아들인 이유는 설정 → argv → 자판 선택 배선이 호스트 검사로는
# 절대 안 보이는 유일한 구간이기 때문이다.
```

`make_initrd.sh` 호출 뒤에 넣을 것:

```bash
if ! ./make_disk.sh; then
  echo "FAIL: hangul config disk build failed"
  exit 1
fi
```

QEMU를 띄우는 자리에 `-drive`를 더한다. `input/check.sh:481`의 모양을 그대로
따른다:

```bash
  -drive file="${REPO_ROOT}/out/hangul.img",if=virtio,format=raw \
```

- [ ] **Step 3: 키 시퀀스를 3-P3으로 바꾼다**

`hangul/check.sh`에서 두벌식 키를 3-P3으로 옮긴다. **글자는 하나도 안 바꾸고
키만 바꾼다** — 그래야 기존 판정(반전 셀 개수 · `key>` 줄 · 로케일)이 전부
그대로 산다.

| 글자 | 두벌식 | 3-P3 |
|---|---|---|
| 가 | `rk` | `kf` |
| 나 | `sk` | `hf` |
| 다 | `ek` | `uf` |
| 갓 | `rkt` | `kfq` |

**`가나다`가 `kfhfuf`다.** 검사 11(로케일)이 이 여섯 키를 쓴다.

- [ ] **Step 4: 설정이 자판을 골랐다는 판정을 더한다**

검사 하나를 새로 만든다. 로그에서 두 줄을 본다.

```
tars-init: config shell=fish keyboard=apple hangul=sebeol_3p3 latin=qwerty
terminal: hangul layout=sebeol_3p3 latin=qwerty
```

**둘을 다 보는 것에 뜻이 있다.** 앞의 줄은 "init이 파일에서 읽었다"를, 뒤의
줄은 "그 값이 argv를 건너 terminal에 닿았다"를 말한다. 앞만 보면 argv 배선이
끊겨도 초록이고, 뒤만 보면 terminal의 기본값이 우연히 맞아도 초록이다.

**`grep -a`를 쓴다**(머리 주석의 이유). 그리고 **`tr -d '\r'`를 잊지 않는다** —
값이 줄 끝에 오는 헬퍼를 새로 만들면 HI-M1 실측 5의 함정을 다시 만난다.

- [ ] **Step 5: 체인 하나만 돌린다**

```bash
time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash hangul/check.sh
```

Expected: 검사 열둘이 전부 통과. **여기서 실패하면 로그를 통째로 호스트로
빼낸다** — `out/`(gitignore) 아래로 남기고 `head`로 자르지 않는다(SP-M0의
교훈).

- [ ] **Step 6: `.gitignore`에 산출물이 걸려 있는지 확인한다**

```bash
git status --short
```

Expected: `out/hangul.img`가 안 나온다(`out/`이 이미 gitignore다).

- [ ] **Step 7: 커밋**

```bash
git add hangul/make_disk.sh hangul/check.sh
git commit -m "Point the hangul gate at a layout the config file chose"
```

---

## Task 9: 루트 게이트 3회전

- [ ] **Step 1: 돌린다 (회차당 약 18분, 3회전이면 약 55분)**

```bash
for i in 1 2 3; do
  echo "=== run $i ==="
  time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
    bash check.sh
done
```

- [ ] **Step 2: 시간을 적는다**

| | 체인 | 시간 |
|---|---|---|
| HI-M1 + 로케일 | 아홉 | 18분 24초 |
| **HI-M2** | 아홉 | **?** |

**갈렸다고 말하려면 두 삼중값의 폭이 안 겹쳐야 한다**(GL-M2 실측 1, 잡음 ±3분).
체인 개수가 안 늘었고 디스크 굽기 몇 초가 붙었을 뿐이므로 **안 갈리는 것이
예상이다.**

- [ ] **Step 3: design doc의 `Status:`와 결정 11의 우선순위 표를 고친다**

- 결정 11의 표를 **착수 전에 확정한 것 1**의 최종형으로 고친다(초+중+종과
  종성만 두 줄).
- `Status:`를 "HI-M2 완료"로 고치고 값을 적는다.
- "HI-M2가 실측한 것" 절을 새로 쓴다.

- [ ] **Step 4: `HANDOFF.md`와 `MEMORY.md`·`docs/decisions/project_hangul_input.md`를 갱신한다**

- [ ] **Step 5: 커밋**

```bash
git add docs/ HANDOFF.md MEMORY.md
git commit -m "Close out HI-M2"
```

---

## 이 plan을 다시 읽으면서 잡은 것

**1. `cc`가 우선순위를 바꿨다.** design 결정 11의 표는 초+중+종을 "겹받침 →
초성 → 중성 → 종성"으로 적었는데, 신세벌 PCS의 `c`가 중성이자 종성이라 그
순서로는 `kfcc`가 `각ㅔ`가 된다. **종성이 중성보다 먼저여야 한다.** design을
Task 9에서 고친다.

**2. `commit_buf`는 코드포인트 하나짜리다.** `nonSyllable`을 그 통로로 보내면
조합 중이던 음절을 덮어쓴다. `.bytes`로 보내면 `readKeys`의 기존 순서가
그대로 답이 된다 — **버퍼를 안 넓히는 것이 더 정확하다.**

**3. 검사 7의 3-순열은 두벌식만 돈다.** 자판 넷으로 넓히지 않는다 — 세벌식은
종성만 상태를 **일부러** 만들고, 그 상태는 이제 그릴 수 있으므로 이 검사가
보는 것("그릴 수 없는 상태를 안 만든다")이 자판마다 다른 뜻이 된다. 세벌식의
근거는 조합 순서 검사가 선다.

**4. `keymap`을 `qwerty_keymap`으로 이름을 바꾸면 세 자리가 함께 바뀐다.**
그중 하나(`hangulLayer`)는 **이름만 바꾸고 드보락을 안 봐야 한다** — 나머지
둘과 다르다. `rg -n 'keymap\['`로 남은 자리를 확인하는 Step을 넣은 이유가
이것이다.

**5. `tars-init: config shell=` 로그 줄을 넓힌다.** 새 줄을 만들지 않는 이유는
`config/check.sh`가 그 줄을 grep하고 있어서다. 앞부분이 안 바뀌면 안 깨진다 —
Task 7의 Step 7이 그것을 확인한다.
