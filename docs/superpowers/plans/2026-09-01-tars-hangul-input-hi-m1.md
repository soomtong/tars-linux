# HI-M1 — 실제로 한글을 칠 수 있게 된다

**Date:** 2026-09-01
**Design:** `docs/superpowers/specs/2026-08-31-tars-hangul-input-design.md`
**Status:** 착수 전

## 이 milestone이 끝나면

- **Shift+Space 하나로 한/영이 바뀐다.** `input.State`에 축이 하나 생기고
  `Mode`와 직교한다(design 결정 5).
- **두벌식으로 조합한 글자가 커서 자리에 보인다.** `vt.zig`의 `cells()`에 층이
  하나 늘고 순서는 `inverse → 매치 → 선택 → preedit → 커서`다(결정 4).
- **확정된 음절이 UTF-8 세 바이트로 PTY에 나간다.** 확정을 유발하는 것의
  목록(결정 6)이 전부 선다 — 자모가 아닌 문자 키 · Enter · Tab · Esc ·
  방향키 · 한/영 전환 · copy mode 진입 · Ctrl·Alt·Meta 조합.
- **Backspace가 조합 중이면 자모를 하나 뺀다.** 조합 중이 아니면 지금처럼
  DEL(0x7F)을 보낸다.
- **게이트 체인이 아홉이 된다.** `hangul/check.sh`가 생기고 게이트가 대략 2분
  는다(design 결정 10).

**아직 안 하는 것.** 자판은 두벌식 하나뿐이고 설정 파일도 안 건드린다(HI-M2).
한/영 키 · CapsLock · tap-vs-hold도 안 한다(HI-M3).

**편집도 Claude Code가 한다.** 이 서브프로젝트의 예외이고 근거는 design 실측
7이다. **CC-M0의 규율을 그대로 쓴다** — 매 편집 뒤 `git diff --stat`으로 더한
줄과 지운 줄을 따로 세고, 지우는 편집은 `git diff | grep '^-'`로 내용을 직접
읽는다. **`input.zig`·`vt.zig`·`main.zig`를 건드리는 Task는 diff를 사용자에게
보여 준다**(HANDOFF의 협업 규율).

## 왜 이 순서인가

**Task 1이 가장 크고 그것만 호스트에서 9.5초로 돌려볼 수 있다.** 한글 층의
분기 순서와 확정 목록이 이 milestone에서 가장 틀리기 쉬운 자리인데,
`input_test`가 부팅 없이 전부 본다. HI-M0이 오토마타를 그렇게 세운 것과 같은
이유다.

**Task 2·3·4가 통로를 한 칸씩 잇는다.** `readKeys`(배치) → `vt.zig`(그리기) →
`main.zig`(배선). 각각이 끝날 때마다 `zig build test`가 돌고, 뒤 단계가
틀렸을 때 앞 단계를 의심할 필요가 없다.

**Task 5의 게이트가 마지막이다.** 호스트 검사가 전부 통과한 뒤에 부팅한다 —
16분을 쓰기 전에 0.1초로 잡을 수 있는 실패를 먼저 잡는다.

## 착수 전에 확정한 것

### 1. `Action`은 확정된 글자를 못 나른다 — 그래서 통로를 하나 더 둔다

조합을 끝내는 키는 **자기 몫의 결과를 따로 갖는다.**

| 조합 중에 누른 키 | 확정 | 그 키 자신의 결과 |
|---|---|---|
| Enter | `한` | `.bytes = "\r"` |
| `←` | `한` | `.bytes = "\x1b[D"` |
| Shift+PageUp | `한` | `.scroll = .page_up` |
| Cmd+Shift+C | `한` | `.copy = .enter` |
| Ctrl+C | `한` | `.bytes = "\x03"` |

`Action`은 union이라 **하나만** 담는다. 세 variant 전부에 "앞에 붙은 글자가
있을 수 있다"를 지우는 것보다, 통로를 하나 더 두고 **그 통로를 비우는 자리를
한 곳으로 못 박는** 쪽을 고른다.

- `State.commit_buf` / `commit_len` — `handleKey`가 채운다.
- `State.takeCommit()` — 가져가면 비워진다.
- **`readKeys`가 `handleKey` 직후, 그 키의 바이트보다 먼저 비운다.**

**순서가 이 결정의 전부다.** 뒤집히면 `한` 뒤에 친 Enter가 셸에 먼저 도착해서
빈 줄이 실행되고 글자는 다음 줄에 남는다.

### 2. `Action`의 새 variant는 payload가 없다

```zig
hangul,
```

나르는 것은 "조합 중인 글자가 바뀌었을 수 있으니 다시 그려라"라는 사실
하나뿐이다. **값은 `State.preedit()`이 준다** — 조합은 마지막 하나만 화면에
남으므로 스크롤·copy처럼 순서대로 모을 것이 없다.

**이 variant가 없으면 조합 중인 글자가 영영 화면에 안 나온다.** 자모 키는
PTY로 아무것도 안 보내고 스크롤도 copy 명령도 안 만들어서 `needs_redraw`가
안 켜진다(`main.zig:838`).

### 3. 한글 층은 copy 표 **뒤**, `chord()` **앞**이다

| 자리 | 왜 |
|---|---|
| find 분기 뒤 | 프롬프트 안의 `j`는 검색어의 글자여야 한다 |
| copy 표 뒤 | 모드 안의 `j`는 아래로 가야 한다 — CN-M1의 `n`과 같은 갈림 |
| `chord()` 앞 | 결정 6의 목록에 Ctrl·Alt·Meta와 copy 진입이 있는데, `chord()`가 먼저 돌면 그 키들이 한글 층에 안 닿는다 |

한글 층이 `null`을 돌려주면 그 키는 평소의 길(`chord` → `specialKey` →
`keymap`)을 **한 글자도 안 바뀐 채** 간다. 확정만 해 두고 흘려보내는 것이
Ctrl·Alt·Meta 갈래의 전부다.

### 4. 커서는 조합 중에 **두 칸**을 반전한다

한글은 16픽셀, 곧 두 칸이다(HI-M0 실측 4). **한 칸만 반전하면 글자의 오른쪽
절반이 어두운 바탕에 어두운 색으로 그려져 사라진다** — `drawGlyph`가 셀
하나의 `fg`로 16픽셀을 통째로 찍기 때문이다(`main.zig:155`).

두 칸이 함께 밝아야 조합 중인 글자가 통째로 보이고, **게이트도 그 둘을 셀 수
있다**: 반전 셀이 1개(평소 커서) → 2개(조합 중)로 갈린다.

**커서가 마지막 열이면 오른쪽 칸이 없다.** 그 프레임에서는 한 칸만 반전되고
글리프의 오른쪽 절반이 격자 밖 여백에 그려진다. `drawGlyph`가 프레임버퍼
경계를 검사하므로(`main.zig:64-74`) 게스트가 죽지는 않는다. **줄바꿈을 하지
않는 것이 의도다** — 조합 중인 글자는 아직 화면의 내용이 아니다.

### 5. 조합 중에는 폭을 조건부로 재지 않는다

HI-M0 실측 4가 근거다. 초성만(`ㄱ` 9×9)이든 완성형(`갓` 14×14)이든
`cell_width`가 전부 16이다. **조합하는 내내 폭이 안 바뀌므로** 커서 뒤의
글자가 밀렸다 당겨지는 일이 없고, `cells()`가 언제나 두 칸을 반전하면 된다.

### 6. `hangul_buf`가 비지 않았으면 `hangul_on`이 반드시 참이다

한/영을 끄는 자리가 **먼저 확정하기 때문에** 성립하는 불변식이다. 이것이
서 있으므로 `hangulLayer`가 `if (!self.hangul_on) return null;` 한 줄로
한글이 꺼진 경우를 통째로 빠져나갈 수 있다 — 꺼져 있는데 조합이 남아 있는
상태를 따로 다룰 필요가 없다.

### 7. Shift+Space를 고른 대가를 적어 둔다

**대문자를 이어 치다가 Shift를 누른 채 공백을 치면 한/영이 바뀐다.**
`HELLO WORLD`를 칠 때 흔한 손버릇이다. design 결정 7이 전환 키를 다중
선택으로 만들어 두었고 HI-M3이 나머지 셋(한/영 키 · 짧은 CapsLock · 짧은 왼쪽
Ctrl)을 더하므로, **그때 Shift+Space를 끌 수 있게 된다.** 지금은 게이트가
보낼 수 있는 유일한 전환 키라 이것으로 시작한다(HI-M0 실측 1이 `lang1`을
막았다).

### 8. 셸이 한글을 되울리는지는 아직 모른다

게스트에 `LANG`도 `LC_ALL`도 설정하는 코드가 없다(`rg 'LANG|LC_ALL|locale'
init/src kernel/make_initrd.sh`가 빈 결과다). C 로케일의 fish가 UTF-8 세
바이트를 그대로 되울리는지는 **부팅해서 봐야 안다.**

**그래서 게이트의 뼈대는 셸에 안 기댄다.** 확정된 바이트가 나갔다는 것은
`terminal: key> 4 byte(s)` 한 줄이 증명한다 — 우리 프로세스가 PTY에 무엇을
썼는지는 셸이 그것으로 무엇을 하든 상관없이 우리가 안다. **셸의 되울림은
Task 5 Step 1에서 실측하고, 되울리면 검사 7을 넣고 안 되울리면 그 사실을
숙제로 적는다.**

---

## Task 1 — 한글 층을 `input.zig`에 넣는다

**Files:**
- Modify: `terminal/src/input.zig`
- Modify: `terminal/src/input_test.zig`

**이 Task가 이 milestone의 절반이다.** 그리고 전부 호스트에서 9.5초에 돈다.

### Step 1: `hangul.zig`를 import한다

`terminal/src/input.zig:1`

지울 것:
```zig
const std = @import("std");
```

넣을 것:
```zig
const std = @import("std");
const hangul = @import("hangul.zig");
```

**`vt.zig`가 아니라 `hangul.zig`인 것이 요점이다.** IP design 결정 6("input.zig는
vt.zig를 import하지 않는다")은 그대로 유효하다 — `hangul.zig`는 시스템 콜도
`vt.zig`도 `drm.zig`도 안 보는 순수 계산이라 `input_test`가 그것을 끌고 와도
빌드가 안 무거워진다(HI design 결정 1).

### Step 2: `Action`에 variant를 하나 더한다

`terminal/src/input.zig:160`

지울 것:
```zig
pub const Action = union(enum) {
    /// PTY로 보낼 바이트열. 빈 슬라이스는 "보낼 것이 없다"는 뜻이다.
    bytes: []const u8,
    /// 우리가 처리할 동작. **PTY로 보내지 않는다.**
    scroll: Scroll,
    /// copy mode의 명령. 이것도 PTY로 보내지 않는다.
    copy: Copy,
};
```

넣을 것:
```zig
pub const Action = union(enum) {
    /// PTY로 보낼 바이트열. 빈 슬라이스는 "보낼 것이 없다"는 뜻이다.
    bytes: []const u8,
    /// 우리가 처리할 동작. **PTY로 보내지 않는다.**
    scroll: Scroll,
    /// copy mode의 명령. 이것도 PTY로 보내지 않는다.
    copy: Copy,
    /// 한글 층이 이 키를 처리했다(HI-M1). **payload가 없는 것에 뜻이 있다.**
    ///
    /// 나르는 것은 "조합 중인 글자가 바뀌었을 수 있으니 다시 그려라"라는
    /// 사실 하나뿐이다. **값은 `State.preedit()`이 준다** — 조합은 마지막
    /// 하나만 화면에 남으므로 스크롤·copy처럼 순서대로 모을 것이 없다.
    ///
    /// **확정된 글자도 여기 없다.** 그것은 `takeCommit()`이 따로 주며,
    /// 이유는 그 함수의 주석에 있다.
    ///
    /// 이 variant가 없으면 조합 중인 글자가 **영영 화면에 안 나온다.**
    /// 자모 키는 PTY로 아무것도 안 보내고 스크롤도 copy 명령도 안 만들어서
    /// `main.zig`의 `needs_redraw`가 안 켜진다.
    hangul,
};
```

**이 한 줄이 배선할 자리를 알려준다.** `input_test.zig`의 헬퍼 셋이 `Action`을
`else` 없이 switch하고 있으므로 여기서 컴파일 에러가 셋 난다 — CM-M0부터 지켜
온 규율이다.

### Step 3: `State`에 한글 상태 셋을 더한다

`terminal/src/input.zig:352` (`copies` 필드 **뒤**, `mode` 필드 **앞**)

넣을 것:
```zig
    /// 한글을 치는 중인가(HI design 결정 5). **`Mode`에 넣지 않는다** —
    /// `Mode`는 normal·copy·find인데 한/영은 그것과 독립이고, copy mode에
    /// 들어갔다 나와도 이 값은 그대로여야 한다.
    hangul_on: bool = false,

    /// 조합 중인 음절. **비어 있지 않으면 `hangul_on`이 반드시 참이다** —
    /// 한/영을 끄는 자리가 먼저 확정하기 때문이다(아래 `hangulLayer`).
    /// 그 불변식이 서 있으므로 "꺼져 있는데 조합이 남은" 상태를 따로 다룰
    /// 필요가 없다.
    hangul_buf: hangul.Syllable = .{},

    /// 확정됐지만 아직 PTY로 못 간 글자의 UTF-8(HI design 결정 6).
    ///
    /// **왜 반환값이 아니라 여기인가.** 조합을 끝내는 키는 자기 몫의 결과를
    /// 따로 갖는다 — Enter는 바이트를, Shift+PageUp은 스크롤을, Cmd+Shift+C는
    /// copy 명령을 만든다. `Action`은 그중 **하나만** 담을 수 있으므로
    /// 확정된 글자를 담을 자리가 반환값에 없다. 세 variant 전부에 "앞에 붙은
    /// 글자가 있을 수 있다"를 지우는 것보다, 통로를 하나 더 두고 **그 통로를
    /// 비우는 자리를 한 곳으로 못 박는** 쪽을 골랐다.
    ///
    /// **한 키가 확정시키는 음절은 많아야 하나다.** 한글 음절은 UTF-8로
    /// 언제나 세 바이트라(U+0800~U+FFFF) 넷이면 넉넉하다.
    commit_buf: [4]u8 = undefined,
    commit_len: usize = 0,
```

### Step 4: 확정과 조회를 하는 함수 넷을 더한다

`terminal/src/input.zig`의 `State` 안, `chord` 정의 **앞**에 넣는다.

넣을 것:
```zig
    /// 조합 중인 글자를 확정해 `commit_buf`에 담고 버퍼를 비운다.
    ///
    /// **`codepoint()`가 null인 경우는 "조합 중이 아니다"뿐이다.** 그릴 수
    /// 없는 상태를 오토마타가 애초에 안 만들기 때문이고(`hangul_test`의
    /// 검사 7이 3-순열 107,811단계에서 0번을 봤다), 그래서 여기서 null을
    /// "버릴 것이 없다"로 읽어도 안전하다.
    fn commitHangul(self: *State) void {
        if (self.hangul_buf.codepoint()) |cp| self.pushCommit(cp);
        self.hangul_buf = .{};
    }

    /// 확정된 코드포인트를 UTF-8로 담는다.
    ///
    /// 한글은 언제나 세 바이트라 실패하지 않는다. 실패했을 때 아무것도 안
    /// 보내는 쪽을 고른 것은, 잘못된 바이트가 셸에 도착하면 그 뒤의 모든
    /// 글자가 밀려서 증상이 원인에서 멀어지기 때문이다.
    fn pushCommit(self: *State, cp: u21) void {
        self.commit_len = std.unicode.utf8Encode(cp, &self.commit_buf) catch 0;
    }

    /// 방금 확정된 글자를 가져간다. 없으면 빈 슬라이스다.
    ///
    /// **`handleKey` 직후에, 그 키가 만든 바이트보다 먼저 부른다.** 순서가
    /// 뒤집히면 `한` 뒤에 친 Enter가 셸에 먼저 도착해서 빈 줄이 실행되고
    /// 글자는 다음 줄에 남는다. 그 순서를 지키는 자리는 `readKeys` 하나이며
    /// `input_test`가 같은 순서로 검사한다.
    pub fn takeCommit(self: *State) []const u8 {
        const out = self.commit_buf[0..self.commit_len];
        self.commit_len = 0;
        return out;
    }

    /// 지금 조합 중인 글자. 없으면 null.
    ///
    /// **`main.zig`가 이것을 `vt.zig`에 넘긴다.** `input.zig`는 `vt.zig`를
    /// import하지 않으므로(IP design 결정 6) 직접 그릴 길이 없고, 그릴 수
    /// 있는 쪽은 조합을 모른다. 둘을 잇는 것이 `main.zig`이며 `find_open`이
    /// 이미 같은 모양이다.
    pub fn preedit(self: State) ?u21 {
        return self.hangul_buf.codepoint();
    }

    /// 1.7번 단계 — 한글(HI design 결정 2·5·6).
    /// **copy 표 뒤·`chord()` 앞이다.**
    ///
    /// **왜 copy 표 뒤인가.** copy mode와 검색 프롬프트 안에서는 키가
    /// 명령이거나 검색어의 글자여야 한다. 한글을 그보다 앞에 두면 모드 안에서
    /// 친 `j`가 아래로 가는 대신 ㅓ가 된다 — CN-M1이 `n`에서 겪은 것과 같은
    /// 종류의 갈림이고 답도 같다: **먼저 오는 분기가 이긴다.**
    ///
    /// **왜 `chord()` 앞인가.** 확정을 유발하는 것의 목록(결정 6)에
    /// Ctrl·Alt·Meta 조합과 copy mode 진입이 들어 있는데, `chord()`가 먼저
    /// 돌면 그 키들이 여기 닿지 않는다. 여기서 확정만 해 두고 **null을 돌려
    /// 흘려보내면** 그 키의 원래 뜻은 한 글자도 안 바뀐다.
    ///
    /// null은 "한글 층이 이 키에 관심이 없다"는 뜻이고, 그때 키는 평소의
    /// 길(`chord` → `specialKey` → `keymap`)을 그대로 간다.
    fn hangulLayer(self: *State, code: u16) ?Action {
        // 한/영은 Shift+Space다(HI-M1). **한글이 꺼져 있을 때도 봐야 하므로**
        // 아래 `hangul_on` 검사보다 앞이다.
        //
        // Ctrl·Alt·Meta를 함께 보는 이유는 Cmd+Shift+Space 같은 조합이
        // 한/영을 뜻하지 않기 때문이다. 그 조합들은 아래 갈래로 내려가
        // 확정만 하고 흘러간다.
        if (code == c.KEY_SPACE and self.shifted() and
            !self.ctrled() and !self.alted() and !self.metaed())
        {
            self.commitHangul();
            self.hangul_on = !self.hangul_on;
            return .hangul;
        }
        if (!self.hangul_on) return null;

        // Ctrl·Alt·Meta 조합은 한글이 아니다(결정 6). **확정만 하고
        // 흘려보낸다** — Cmd+Shift+C(copy mode 진입)도 이 갈래로 온다.
        if (self.ctrled() or self.alted() or self.metaed()) {
            self.commitHangul();
            return null;
        }

        // Backspace는 **조합 중일 때만** 우리 것이다(결정 6). 조합 중이 아니면
        // null을 돌려 평소처럼 DEL(0x7F)이 나가게 한다 — `erase`가 그 둘을
        // null로 갈라 준다.
        if (code == c.KEY_BACKSPACE) {
            const next = hangul.erase(self.hangul_buf) orelse return null;
            self.hangul_buf = next;
            return .hangul;
        }

        // 표 밖의 키(방향키·PageUp·Delete 등)는 확정을 유발한다(결정 6).
        if (code >= keymap.len) {
            self.commitHangul();
            return null;
        }
        const ch = keymap[code][if (self.shifted()) 1 else 0];
        // 문자를 만들지 않는 키(표 안의 modifier 자리)다. 여기 오는 일은
        // 사실상 없지만, 0을 `dubeol`에 먹이지 않기 위해 먼저 거른다.
        if (ch == 0) {
            self.commitHangul();
            return null;
        }
        // 자모가 아닌 문자 키(숫자·기호·공백)와 Enter·Tab·Esc가 여기 온다 —
        // `dubeol`이 셋 다 null을 준다. **확정한 글자가 그 키의 바이트보다
        // 먼저 나가는 것을 보장하는 것은 `readKeys`다.**
        const jamo = hangul.dubeol(ch) orelse {
            self.commitHangul();
            return null;
        };
        const step = hangul.feed(self.hangul_buf, jamo);
        if (step.commit) |cp| self.pushCommit(cp);
        self.hangul_buf = step.buf;
        return .hangul;
    }
```

### Step 5: `handleKey`에 한 줄을 끼운다

`terminal/src/input.zig:691`

지울 것:
```zig
        // 2번 단계 — 조합 dispatch. 특수키 조회보다 **먼저**다.
```

넣을 것:
```zig
        // 1.7번 단계 — 한글(HI-M1). **copy 표 뒤·chord() 앞이다.**
        // 그 자리를 고른 이유는 hangulLayer의 주석에 있다.
        if (self.hangulLayer(code)) |action| return action;

        // 2번 단계 — 조합 dispatch. 특수키 조회보다 **먼저**다.
```

### Step 6: `input_test.zig`의 헬퍼 셋에 갈래를 더한다

**세 자리 전부 컴파일 에러로 잡힌다.** 아래 셋을 각 switch의 마지막 갈래로
넣는다.

`expectCtx`의 `.copy` 갈래 **뒤**에 넣을 것:
```zig
        .hangul => {
            std.debug.print(
                "FAIL: code={d} value={d} -> got hangul, want bytes {any}\n",
                .{ code, value, want },
            );
            return error.UnexpectedHangul;
        },
```

`expectCopy`의 `.scroll` 갈래 **뒤**에 넣을 것:
```zig
        .hangul => {
            std.debug.print(
                "FAIL: code={d} -> got hangul, want copy .{s}\n",
                .{ code, @tagName(want) },
            );
            return error.UnexpectedHangul;
        },
```

`expectScroll`의 `.copy` 갈래 **뒤**에 넣을 것:
```zig
        .hangul => {
            std.debug.print(
                "FAIL: code={d} -> got hangul, want scroll .{s}\n",
                .{ code, @tagName(want) },
            );
            return error.UnexpectedHangul;
        },
```

### Step 7: 한글용 헬퍼 셋을 더한다

`input_test.zig`의 `expectScroll` **뒤**에 넣을 것:
```zig
/// 한글 층이 이 키를 처리하기를 기대한다(HI-M1). **바이트가 오면 실패다** —
/// 그것이 곧 "조합 중인 자모가 PTY로 샜다"이고, 이 milestone의 가장 흔한
/// 실패 방식이다.
///
/// 셋을 한 번에 본다: 어느 variant가 왔는가 · 무엇이 확정됐는가 · 무엇을
/// 조합 중인가. **셋이 함께 있어야 뜻이 선다** — 확정만 보면 화면이 안 바뀐
/// 것을 못 잡고, 조합만 보면 확정된 글자가 셸에 안 간 것을 못 잡는다.
fn expectHangul(
    state: *input.State,
    code: u16,
    want_commit: []const u8,
    want_preedit: ?u21,
) !void {
    switch (state.handleKey(code, 1, .{})) {
        .hangul => {},
        .bytes => |bytes| {
            std.debug.print(
                "FAIL: code={d} -> got {d} byte(s) {any}, want hangul\n",
                .{ code, bytes.len, bytes },
            );
            return error.LeakedToPty;
        },
        .scroll => |s| {
            std.debug.print(
                "FAIL: code={d} -> got scroll .{s}, want hangul\n",
                .{ code, @tagName(s) },
            );
            return error.UnexpectedScroll;
        },
        .copy => |cmd| {
            std.debug.print(
                "FAIL: code={d} -> got copy .{s}, want hangul\n",
                .{ code, @tagName(cmd) },
            );
            return error.UnexpectedCopy;
        },
    }
    try expectCommit(state, code, want_commit);
    try expectPreedit(state, code, want_preedit);
}

/// 확정된 글자를 본다. **`handleKey`를 부른 **직후에만** 뜻이 있다** — 한 번
/// 가져가면 비워지기 때문이다(`takeCommit`). `readKeys`가 지키는 순서를 이
/// 파일이 같은 순서로 흉내 내는 자리다.
fn expectCommit(state: *input.State, code: u16, want: []const u8) !void {
    const got = state.takeCommit();
    if (std.mem.eql(u8, got, want)) return;
    std.debug.print(
        "FAIL: code={d} -> committed \"{s}\", want \"{s}\"\n",
        .{ code, got, want },
    );
    return error.WrongCommit;
}

/// 조합 중인 글자를 본다. null이 "조합 중이 아니다"이다.
fn expectPreedit(state: *input.State, code: u16, want: ?u21) !void {
    const got = state.preedit();
    if (std.meta.eql(got, want)) return;
    std.debug.print(
        "FAIL: code={d} -> preedit {?d}, want {?d}\n",
        .{ code, got, want },
    );
    return error.WrongPreedit;
}
```

### Step 8: 검사 여섯을 더한다

`input_test.zig`의 `std.debug.print("input_test: copy mode OK\n", .{});`
**뒤**, `PASS` **앞**에 넣을 것:
```zig
    // ── HI-M1: 한글 ───────────────────────────────────────────────────

    var hg: input.State = .{};

    // 검사 24. **대조군 — 한글이 꺼져 있으면 아무것도 안 바뀐다.**
    // 이 검사가 없으면 아래 검사들이 "한글이 되는가"만 보고 "영문이 계속
    // 되는가"를 안 본다. `r`은 두벌식에서 ㄱ이라 가장 잘 갈린다.
    try expect(&hg, K.KEY_R, 1, "r");
    try expectPreedit(&hg, K.KEY_R, null);

    // 검사 25. **Shift+Space가 한/영을 바꾸고 공백은 PTY로 안 나간다.**
    // 빈 슬라이스가 아니라 `.hangul`이 와야 한다 — `.bytes = ""`로 만들면
    // 화면이 다시 안 그려져서 그 뒤의 조합이 안 보인다.
    try expect(&hg, K.KEY_LEFTSHIFT, 1, "");
    try expectHangul(&hg, K.KEY_SPACE, "", null);
    try expect(&hg, K.KEY_LEFTSHIFT, 0, "");
    if (!hg.hangul_on) {
        std.debug.print("FAIL: Shift+Space did not turn hangul on\n", .{});
        return error.ToggleFailed;
    }

    // 검사 26. **두벌식으로 `한글`을 친다.** `gksrmf`이고 `hangul_test`의
    // 검사 4가 같은 글자열을 오토마타 쪽에서 본다 — **이 검사가 보는 것은
    // 오토마타가 아니라 배선이다.** evdev 코드 → keymap → dubeol → feed까지
    // 한 줄이라도 어긋나면 여기서 갈린다.
    try expectHangul(&hg, K.KEY_G, "", 'ㅎ');
    try expectHangul(&hg, K.KEY_K, "", '하');
    try expectHangul(&hg, K.KEY_S, "", '한');
    // `ㄱ`은 `ㄴ`과 겹받침이 안 되므로 `한`이 확정되고 새 초성이 된다.
    try expectHangul(&hg, K.KEY_R, "한", 'ㄱ');
    try expectHangul(&hg, K.KEY_M, "", '그');
    try expectHangul(&hg, K.KEY_F, "", '글');

    // 검사 27. **Enter가 확정시키고, 확정된 글자와 CR이 둘 다 나간다.**
    // `expect`가 반환된 바이트를, 이어지는 `expectCommit`이 그보다 **먼저**
    // 나갈 글자를 본다 — 두 줄의 순서가 곧 `readKeys`의 계약이다.
    try expect(&hg, K.KEY_ENTER, 1, "\r");
    try expectCommit(&hg, K.KEY_ENTER, "글");
    try expectPreedit(&hg, K.KEY_ENTER, null);

    // 검사 28. **확정을 유발하는 것 다섯**(design 결정 6). 다섯이 서로 다른
    // 갈래로 빠진다: 공백(자모가 아닌 문자 키) · 방향키(표 밖) ·
    // Ctrl 조합 · Meta 조합으로 copy mode 진입 · 한/영 전환.
    //
    // **Cmd+Shift+C가 이 목록에서 가장 미묘하다.** 반환값이 `.copy = .enter`라
    // 확정된 글자를 담을 자리가 없고, 그래서 `commit_buf`라는 통로가 생겼다.
    try expectHangul(&hg, K.KEY_R, "", 'ㄱ');
    try expectHangul(&hg, K.KEY_K, "", '가');
    try expect(&hg, K.KEY_SPACE, 1, " ");
    try expectCommit(&hg, K.KEY_SPACE, "가");

    try expectHangul(&hg, K.KEY_R, "", 'ㄱ');
    try expectHangul(&hg, K.KEY_K, "", '가');
    try expect(&hg, K.KEY_LEFT, 1, "\x1b[D");
    try expectCommit(&hg, K.KEY_LEFT, "가");

    try expectHangul(&hg, K.KEY_R, "", 'ㄱ');
    try expectHangul(&hg, K.KEY_K, "", '가');
    try expect(&hg, K.KEY_LEFTCTRL, 1, "");
    try expect(&hg, K.KEY_C, 1, "\x03");
    try expectCommit(&hg, K.KEY_C, "가");
    try expect(&hg, K.KEY_LEFTCTRL, 0, "");

    try expectHangul(&hg, K.KEY_R, "", 'ㄱ');
    try expectHangul(&hg, K.KEY_K, "", '가');
    try expect(&hg, K.KEY_LEFTMETA, 1, "");
    try expect(&hg, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&hg, K.KEY_C, .enter);
    try expectCommit(&hg, K.KEY_C, "가");
    try expect(&hg, K.KEY_LEFTSHIFT, 0, "");
    try expect(&hg, K.KEY_LEFTMETA, 0, "");

    // 검사 29. **한글이 켜져 있어도 copy mode의 `j`는 아래로 간다.**
    // 한글 층이 copy 표보다 **뒤**라는 것이 이 한 줄이고, 순서를 뒤집으면
    // 모드 안에서 커서가 안 움직이고 ㅓ가 조합된다.
    if (!hg.hangul_on) {
        std.debug.print("FAIL: copy mode entry turned hangul off\n", .{});
        return error.HangulLostOnCopyEnter;
    }
    try expectCopy(&hg, K.KEY_J, .down);
    try expectCopy(&hg, K.KEY_ESC, .exit);
    // **모드를 나와도 한/영은 그대로다**(design 결정 5의 직교성).
    if (!hg.hangul_on) {
        std.debug.print("FAIL: leaving copy mode turned hangul off\n", .{});
        return error.HangulLostOnCopyExit;
    }

    // 검사 30. **Backspace가 자모를 하나씩 뺀다.** 마지막 하나가 대조군이다 —
    // 조합이 비고 나면 평소처럼 DEL이 나가야 한다. 그 줄이 없으면 "조합 중이
    // 아닌데도 Backspace를 삼킨다"가 통과하고, 증상은 "셸에서 글자를 못
    // 지운다"라 원인에서 멀다.
    try expectHangul(&hg, K.KEY_G, "", 'ㅎ');
    try expectHangul(&hg, K.KEY_K, "", '하');
    try expectHangul(&hg, K.KEY_S, "", '한');
    try expectHangul(&hg, K.KEY_BACKSPACE, "", '하');
    try expectHangul(&hg, K.KEY_BACKSPACE, "", 'ㅎ');
    try expectHangul(&hg, K.KEY_BACKSPACE, "", null);
    try expect(&hg, K.KEY_BACKSPACE, 1, "\x7f");

    // 검사 31. **한/영을 끄면 조합이 먼저 확정된다.** 이것이
    // "`hangul_buf`가 비지 않았으면 `hangul_on`이 참"이라는 불변식을 세우는
    // 자리다 — 안 확정하면 꺼진 채로 조합이 남아 화면에 글자가 붙박인다.
    try expectHangul(&hg, K.KEY_R, "", 'ㄱ');
    try expectHangul(&hg, K.KEY_K, "", '가');
    try expect(&hg, K.KEY_LEFTSHIFT, 1, "");
    try expectHangul(&hg, K.KEY_SPACE, "가", null);
    try expect(&hg, K.KEY_LEFTSHIFT, 0, "");
    if (hg.hangul_on) {
        std.debug.print("FAIL: Shift+Space did not turn hangul off\n", .{});
        return error.ToggleFailed;
    }
    // 껐으니 `r`은 다시 `r`이다.
    try expect(&hg, K.KEY_R, 1, "r");

    std.debug.print("input_test: hangul OK\n", .{});
```

### Step 9: 돌린다

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c './prepare.sh >/dev/null && zig build test'
```
Expected: `input_test: hangul OK`가 새로 나오고 `PASS`. `vt_test`·`font_test`·
`hangul_test`의 기존 출력은 한 줄도 안 바뀐다.

**`hangul_test`의 출력이 안 바뀌는 것이 신호다.** 이 Task는 오토마타를 한
글자도 안 건드렸다.

### Step 10: diff를 확인하고 커밋

Run:
```bash
git diff --stat terminal/src/input.zig terminal/src/input_test.zig
git diff terminal/src/input.zig | grep '^-' | grep -v '^---'
```
Expected: 지운 줄은 Step 1·2·5가 대체한 것들뿐이다(`const std` 한 줄 ·
`Action` 정의 여섯 줄 · 주석 한 줄). **그 밖의 줄이 지워졌으면 멈춘다.**

**diff를 사용자에게 보여 준 뒤** 커밋한다.

```bash
git add terminal/src/input.zig terminal/src/input_test.zig
git commit -m "Compose hangul in the input layer"
```

---

## Task 2 — `readKeys`가 확정된 글자를 먼저 내보낸다

**Files:** Modify `terminal/src/input.zig`

**이 Task가 순서 계약을 코드로 만든다.** Task 1은 `commit_buf`를 채우기만
했고 아무도 안 비웠다.

### Step 1: `Keys`에 필드를 하나 더한다

`terminal/src/input.zig:243`

지울 것:
```zig
    /// copy mode 명령도 같은 이유로 순서대로 모은다. `j`를 누르고 있으면
    /// 자동 반복이 여러 개를 실어 오고, 그만큼 내려가야 한다.
    copies: []const Copy,
};
```

넣을 것:
```zig
    /// copy mode 명령도 같은 이유로 순서대로 모은다. `j`를 누르고 있으면
    /// 자동 반복이 여러 개를 실어 오고, 그만큼 내려가야 한다.
    copies: []const Copy,
    /// 이 배치에서 조합 중인 글자가 바뀌었는가(HI-M1).
    ///
    /// **값이 아니라 사실만 나른다.** 값은 `State.preedit()`이 주며,
    /// 조합은 마지막 하나만 화면에 남으므로 스크롤·copy처럼 **순서대로 모을
    /// 것이 없다** — 자동 반복으로 자모가 여럿 실려 와도 그려야 할 글자는
    /// 마지막 하나다.
    hangul: bool,
};
```

### Step 2: `readKeys`의 이른 반환을 고친다

`terminal/src/input.zig:740`

지울 것:
```zig
    if (n <= 0) return .{
        .bytes = out[0..0],
        .scrolls = self.scrolls[0..0],
        .copies = self.copies[0..0],
    };
```

넣을 것:
```zig
    if (n <= 0) return .{
        .bytes = out[0..0],
        .scrolls = self.scrolls[0..0],
        .copies = self.copies[0..0],
        .hangul = false,
    };
```

### Step 3: 루프에서 확정된 글자를 먼저 옮긴다

`terminal/src/input.zig:747`

지울 것:
```zig
    var written: usize = 0;
    var scrolled: usize = 0;
    var copied: usize = 0;
```

넣을 것:
```zig
    var written: usize = 0;
    var scrolled: usize = 0;
    var copied: usize = 0;
    var hangul_changed = false;
```

`terminal/src/input.zig:755`

지울 것:
```zig
        switch (self.handleKey(ev.code, ev.value, ctx)) {
```

넣을 것:
```zig
        const action = self.handleKey(ev.code, ev.value, ctx);
        // **그 키의 결과보다 먼저** 확정된 글자를 옮긴다(HI design 결정 6).
        //
        // 순서가 뒤집히면 `한` 뒤에 친 Enter가 셸에 먼저 도착해서 빈 줄이
        // 실행되고 글자는 다음 줄에 남는다. **이 두 줄의 자리가 곧
        // `takeCommit`의 계약이다.**
        //
        // 확정이 일어났다는 것은 조합 버퍼가 비었다는 뜻이므로 화면도 다시
        // 그려야 한다 — 그래서 `hangul_changed`를 여기서도 켠다.
        const commit = self.takeCommit();
        if (commit.len > 0) {
            hangul_changed = true;
            for (commit) |byte| {
                if (written >= out.len) break;
                out[written] = byte;
                written += 1;
            }
        }
        switch (action) {
```

### Step 4: `.hangul` 갈래를 더하고 반환에 실어 보낸다

`terminal/src/input.zig:772` (`.copy` 갈래 **뒤**)

지울 것:
```zig
            .copy => |cmd| if (copied < self.copies.len) {
                self.copies[copied] = cmd;
                copied += 1;
            },
        }
    }
    return .{
        .bytes = out[0..written],
        .scrolls = self.scrolls[0..scrolled],
        .copies = self.copies[0..copied],
    };
```

넣을 것:
```zig
            .copy => |cmd| if (copied < self.copies.len) {
                self.copies[copied] = cmd;
                copied += 1;
            },
            // 조합만 바뀐 키다. PTY로 나갈 것도 모을 것도 없고, `main.zig`가
            // 다시 그리기만 하면 된다.
            .hangul => hangul_changed = true,
        }
    }
    return .{
        .bytes = out[0..written],
        .scrolls = self.scrolls[0..scrolled],
        .copies = self.copies[0..copied],
        .hangul = hangul_changed,
    };
```

### Step 5: 돌린다

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```
Expected: 출력이 Task 1과 **한 글자도 안 다르다.** `readKeys`를 부르는 검사가
없기 때문이고, 그것이 이 Task를 게이트가 보아야 하는 이유다(Task 5).

### Step 6: diff를 확인하고 커밋

Run:
```bash
git diff --stat terminal/src/input.zig
git diff terminal/src/input.zig | grep '^-' | grep -v '^---'
```
Expected: 지운 줄은 위 셋이 대체한 것들뿐이다.

**diff를 사용자에게 보여 준 뒤** 커밋한다.

```bash
git add terminal/src/input.zig
git commit -m "Send the committed syllable before the key that ended it"
```

---

## Task 3 — 조합 중인 글자를 커서 자리에 그린다

**Files:**
- Modify: `terminal/src/vt.zig`
- Modify: `terminal/src/vt_test.zig`

### Step 1: `Screen`에 필드를 하나 더한다

`terminal/src/vt.zig:152` (`copy_pruned` 필드 **뒤**)

넣을 것:
```zig
    /// 조합 중인 한글 한 글자(HI design 결정 4). null이면 조합 중이 아니다.
    ///
    /// **PTY로 안 간 글자다.** 확정될 때만 셸로 가고, 그때까지는 우리가 커서
    /// 자리에 그린다. 매 키마다 PTY로 보내고 백스페이스로 고치는 길을 버린
    /// 이유는 design 결정 4에 있다 — 셸의 readline이 두 칸짜리 글자의 폭을
    /// 알아야 한다.
    ///
    /// **같은 사실이 `input.State`에도 있다.** `find_open`이 그런 것과 같은
    /// 중복이고 이유도 같다 — `input.zig`는 키를 자모로 돌리기 위해, 여기는
    /// **그려야 하기 때문에** 알아야 한다. `input.zig`는 `vt.zig`를 import하지
    /// 않으므로(IP design 결정 6) 물어볼 길이 아예 없고, `main.zig`가 키를
    /// 읽은 직후에 넘긴다.
    preedit: ?u21 = null,
```

### Step 2: setter를 더한다

`terminal/src/vt.zig:535` (`defaultBg` **뒤**, `pub const Cursor` **앞**)

넣을 것:
```zig
    /// 조합 중인 글자를 정한다. null이면 조합 중이 아니다.
    ///
    /// **`main.zig`가 키를 읽은 직후에 부른다.** 값을 만드는 것은
    /// `input.State`이고 그리는 것은 아래 `cells()`이며, 둘을 잇는 것이
    /// `main.zig`다(HI design 결정 2).
    pub fn setPreedit(self: *Screen, cp: ?u21) void {
        self.preedit = cp;
    }
```

**`copyExit`에서 안 지운다.** copy mode에 들어가는 순간 `input.zig`가 이미
확정했고(design 결정 6), `main.zig`가 그 결과로 `setPreedit(null)`을 부른다.
여기서 또 지우면 같은 사실을 두 곳이 관리하게 된다.

### Step 3: `cells()`의 `cp`를 바꿀 수 있게 한다

`terminal/src/vt.zig:413`

지울 것:
```zig
                const raw = raws[x];
                const cp = raw.codepoint();
```

넣을 것:
```zig
                const raw = raws[x];
                // **`var`인 것이 HI-M1의 변경이다.** 아래 preedit 층이 커서
                // 자리의 글자를 조합 중인 것으로 갈아 끼운다.
                var cp = raw.codepoint();
```

### Step 4: 커서 층에 preedit을 얹는다

`terminal/src/vt.zig:494`

지울 것:
```zig
                if (self.copy_cursor) |cc| {
                    if (@as(usize, cc.x) == x and @as(usize, cc.y) == y) {
                        std.mem.swap(u32, &fg, &bg);
                    }
                } else if (cursor) |vp| {
                    if (@as(usize, vp.x) == x and @as(usize, vp.y) == y) {
                        std.mem.swap(u32, &fg, &bg);
                    }
                }
```

넣을 것:
```zig
                if (self.copy_cursor) |cc| {
                    if (@as(usize, cc.x) == x and @as(usize, cc.y) == y) {
                        std.mem.swap(u32, &fg, &bg);
                    }
                } else if (cursor) |vp| {
                    // preedit 층(HI design 결정 4). **선택 뒤·커서 앞이 이
                    // 층의 자리다** — 지금 치고 있는 글자라 무엇에도 안
                    // 가려져야 하고, 커서는 여전히 그 자리를 가리켜야 한다.
                    //
                    // **copy mode 중에는 여기 안 온다**(위 갈래로 빠진다).
                    // 셸 커서가 뷰포트 밖이면 `cursor`가 null이라 저절로 안
                    // 그려진다 — 안 보이는 자리에 조합을 그릴 수는 없다.
                    if (@as(usize, vp.x) == x and @as(usize, vp.y) == y) {
                        if (self.preedit) |pcp| cp = pcp;
                    }
                    // 커서는 한 칸, **조합 중에는 두 칸**을 반전한다.
                    //
                    // 한글은 16픽셀, 곧 두 칸이다(HI-M0 실측 3). `drawGlyph`가
                    // 셀 하나의 `fg`로 16픽셀을 통째로 찍으므로, 한 칸만
                    // 반전하면 글자의 오른쪽 절반이 어두운 바탕에 어두운
                    // 색으로 그려져 **사라진다.** 두 칸이 함께 밝아야 조합
                    // 중인 글자가 통째로 보이고, 게이트도 그 둘을 셀 수 있다.
                    //
                    // 커서가 마지막 열이면 오른쪽 칸이 없으므로 한 칸만
                    // 반전된다. 그 프레임에서는 글리프의 오른쪽 절반이 격자
                    // 밖 여백에 그려지고, `drawGlyph`가 프레임버퍼 경계를
                    // 검사하므로 게스트가 죽지는 않는다. **줄바꿈을 하지
                    // 않는 것이 의도다** — 조합 중인 글자는 아직 화면의
                    // 내용이 아니다.
                    const span: usize = if (self.preedit == null) 1 else 2;
                    if (@as(usize, vp.y) == y and
                        x >= @as(usize, vp.x) and x < @as(usize, vp.x) + span)
                    {
                        std.mem.swap(u32, &fg, &bg);
                    }
                }
```

**아래 `if (cp == 0 and bg == default_bg) continue;`는 안 고친다.** preedit이
얹힌 셀은 `cp`가 0이 아니라 저절로 내보내지고, 오른쪽 칸은 글자가 없어도
반전되어 `bg`가 기본과 달라 역시 내보내진다.

### Step 5: `vt_test`에 검사 셋을 더한다

`vt_test.zig`의 `PASS` **앞**에 넣을 것:
```zig
    // ── HI-M1: 조합 중인 글자 ─────────────────────────────────────────
    //
    // 반전된 셀은 기본 색이 뒤집힌 것이다(fg=102030 bg=FFFFFF). 선택도
    // 커서도 같은 연산이라 같은 모양으로 나타나므로, **전후를 비교해야**
    // 뜻이 생긴다 — 게이트의 `inverted_cells`가 쓰는 것과 같은 판정이다.
    const pre = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer pre.deinit();
    pre.feed("ab");

    // 검사 45. **대조군 — 조합 중이 아니면 반전된 셀이 하나다.**
    {
        var inv: usize = 0;
        for (try pre.cells(&buf)) |cell| {
            if (cell.fg == 0x102030 and cell.bg == 0xFFFFFF) inv += 1;
        }
        if (inv != 1) {
            std.debug.print("FAIL: 커서만 있는데 반전된 셀이 {d}개다\n", .{inv});
            return error.WrongCursorCells;
        }
    }

    // 검사 46. **조합 중인 글자가 커서 자리에 뜨고 두 칸이 반전된다.**
    //
    // 두 칸인 것이 이 검사의 값이다(HI-M0 실측 3). 한 칸만 반전하면 게스트
    // 화면에서 글자의 오른쪽 절반이 사라지는데, **화면을 안 보는 검사로는
    // 그것을 셀 수로만 잡을 수 있다.**
    pre.setPreedit('가');
    {
        var inv: usize = 0;
        var found = false;
        for (try pre.cells(&buf)) |cell| {
            if (cell.fg == 0x102030 and cell.bg == 0xFFFFFF) inv += 1;
            // "ab" 뒤라 셸 커서는 0행 2열이다.
            if (cell.codepoint == '가' and cell.row == 0 and cell.col == 2) {
                found = true;
            }
        }
        if (!found) {
            std.debug.print("FAIL: 조합 중인 글자가 커서 자리에 없다\n", .{});
            return error.PreeditNotDrawn;
        }
        if (inv != 2) {
            std.debug.print("FAIL: 조합 중인데 반전된 셀이 {d}개다(2여야 한다)\n", .{inv});
            return error.PreeditNotTwoCells;
        }
    }

    // 검사 47. **null로 되돌리면 흔적이 하나도 안 남는다.** 안 지워지면
    // 증상이 "확정한 글자가 화면에 두 번 보인다"라 원인에서 멀다.
    pre.setPreedit(null);
    {
        var inv: usize = 0;
        for (try pre.cells(&buf)) |cell| {
            if (cell.fg == 0x102030 and cell.bg == 0xFFFFFF) inv += 1;
            if (cell.codepoint == '가') {
                std.debug.print("FAIL: 조합을 껐는데 글자가 남아 있다\n", .{});
                return error.PreeditNotCleared;
            }
        }
        if (inv != 1) {
            std.debug.print("FAIL: 조합을 껐는데 반전된 셀이 {d}개다\n", .{inv});
            return error.WrongCursorCells;
        }
    }

    // 검사 48. **copy mode 중에는 안 그린다.** 그때 반전된 셀은 copy 커서
    // 하나여야 하고, 둘이면 게이트가 어느 것이 copy 커서인지 못 가른다 —
    // CM-M0이 셸 커서를 안 그리기로 한 것과 같은 이유다.
    pre.setPreedit('가');
    pre.copyEnter();
    {
        for (try pre.cells(&buf)) |cell| {
            if (cell.codepoint == '가') {
                std.debug.print("FAIL: copy mode 중에 조합이 그려졌다\n", .{});
                return error.PreeditDrawnInCopyMode;
            }
        }
    }
    pre.copyExit();
    pre.setPreedit(null);

    std.debug.print("vt_test: preedit OK\n", .{});
```

### Step 6: 돌린다

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```
Expected: `vt_test: preedit OK`가 새로 나오고 `PASS`. **기존 `vt_test` 출력이
한 줄도 안 바뀌어야 한다** — preedit이 null인 동안 `cells()`의 결과가 전과
같다는 뜻이고, `span`이 1로 남는 것을 44개의 기존 검사가 함께 본다.

### Step 7: diff를 확인하고 커밋

Run:
```bash
git diff --stat terminal/src/vt.zig terminal/src/vt_test.zig
git diff terminal/src/vt.zig | grep '^-' | grep -v '^---'
```
Expected: 지운 줄은 Step 3의 두 줄과 Step 4의 아홉 줄뿐이다.

**diff를 사용자에게 보여 준 뒤** 커밋한다.

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Draw the composing syllable at the cursor"
```

---

## Task 4 — `main.zig`가 둘을 잇는다

**Files:** Modify `terminal/src/main.zig`

### Step 1: `dumpHangul`을 더한다

`terminal/src/main.zig:453` (`dumpFind` **뒤**, `dumpOverlay` **앞**)

넣을 것:
```zig
/// 한글 입력기의 상태를 한 줄로 찍는다(HI-M1). 게이트가 "한/영이 바뀌었다"와
/// "지금 이 글자를 조합 중이다"를 볼 수 있는 유일한 줄이다.
///
/// **`screen>`만 보면 갈리지 않는 것이 있다.** 조합 중인 글자는 셸이 되울린
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
```

### Step 2: poll 루프에 배선한다

`terminal/src/main.zig:786`

지울 것:
```zig
                dumpCopy(screen, @tagName(cmd));
                needs_redraw = true;
            }
        }
```

넣을 것:
```zig
                dumpCopy(screen, @tagName(cmd));
                needs_redraw = true;
            }
            // 조합 중인 글자를 화면에 넘긴다(HI design 결정 2). **값을 만드는
            // 것은 `input.State`이고 그리는 것은 `vt.zig`이며, 둘을 잇는 것이
            // 여기다** — `input.zig`는 `vt.zig`를 import하지 않는다
            // (IP design 결정 6). `find_open`이 이미 같은 길로 돈다.
            //
            // **`needs_redraw`를 여기서 켜야 한다.** 조합만 바뀐 키는 PTY로
            // 아무것도 안 보내고 스크롤도 copy 명령도 안 만든다 — 그래서
            // 이 한 줄이 없으면 조합 중인 글자가 **영영 화면에 안 나온다.**
            //
            // copy 루프 **뒤**인 것에도 뜻이 있다. copy mode에 들어가는 키가
            // 조합을 확정시키므로(design 결정 6), 그 확정 결과를 화면에
            // 반영하는 것은 모드 전환이 끝난 뒤여야 한다.
            if (keys.hangul) {
                screen.setPreedit(key_state.preedit());
                dumpHangul(&key_state);
                needs_redraw = true;
            }
        }
```

### Step 3: 빌드한다

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c './prepare.sh >/dev/null && zig build && zig build test'
```
Expected: 빌드가 통과하고 호스트 검사 출력이 Task 3과 같다.

**`zig build`를 따로 부르는 것에 뜻이 있다.** `zig build test`는 호스트 검사
넷만 만들고 게스트 바이너리를 안 만든다 — `main.zig`의 실수는 그쪽에서만
잡힌다.

### Step 4: diff를 확인하고 커밋

Run:
```bash
git diff --stat terminal/src/main.zig
git diff terminal/src/main.zig | grep '^-' | grep -v '^---'
```
Expected: 지운 줄은 Step 2가 대체한 세 줄뿐이다.

**diff를 사용자에게 보여 준 뒤** 커밋한다.

```bash
git add terminal/src/main.zig
git commit -m "Wire the composing syllable to the screen"
```

---

## Task 5 — 게이트 체인 `hangul/check.sh`

**Files:**
- Create: `hangul/check.sh`
- Modify: `check.sh`

### Step 1: 먼저 손으로 한 번 부팅해서 로그를 읽는다 (Claude가 실행, 약 4분)

**게이트의 기대값을 짐작으로 적지 않는다.** 특히 확정 전 실측 8(셸이 한글을
되울리는가)이 여기서 답을 얻는다.

Claude가 `/tmp/hi-m1-probe.sh`를 만들어 컨테이너 안에서 돌린다.

```bash
#!/bin/bash
set -eu
cd /workspace/kernel && ./build.sh >/dev/null
cd /workspace/init && zig build >/dev/null
cd /workspace/terminal && ./prepare.sh >/dev/null
cd /workspace/kernel && ./make_initrd.sh >/dev/null
cd /workspace/terminal

MONITOR_PORT=45999
LOG="$(mktemp)"
qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none -device virtio-gpu-pci -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

for _ in $(seq 1 120); do
  grep -aq "terminal: screen>" "$LOG" && break
  sleep 1
done
sleep 1
exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"
source /workspace/gate_lib.sh

type_keys e c h o spc
type_keys shift-spc
type_keys r k t
type_keys ret
sleep 2
type_keys shift-spc

sleep 1
exec 3<&- ; exec 3>&-
kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true

mkdir -p /workspace/out/probe
cp "$LOG" /workspace/out/probe/hi-m1.log
grep -a 'terminal: hangul>' "$LOG"
echo "--- key> ---"
grep -a 'terminal: key>' "$LOG" | tail -n 5
echo "--- last frame screen> ---"
awk '/terminal: screen>/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$LOG" |
  grep -a 'terminal: screen>'
echo "--- last frame style> ---"
awk '/terminal: screen>/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$LOG" |
  grep -a 'terminal: style>'
```

**읽는 것 넷.**

1. `hangul> on=true preedit=ㄱ` → `가` → `갓` 순으로 나오는가.
2. `갓`을 조합하는 동안 `key>` 줄이 **안 늘었는가**(음성 검사의 근거).
3. Enter 뒤 `terminal: key> 4 byte(s)`가 나오는가 — 확정된 세 바이트와 CR
   하나가 **한 번의 write로** 나갔다는 증명이다.
4. **마지막 프레임의 `screen>`에 `갓`이 몇 번 나오는가.** 두 번이면 셸이
   한글을 되울린 것이고(명령줄 + 출력줄) 검사 7을 게이트에 넣는다. 안
   나오거나 깨져 나오면 **그것이 실측이고** 검사 7 대신 그 사실을 design에
   숙제로 적는다(확정 전 실측 8).

**`out/`은 gitignore이고, 루트 게이트를 돌리면 `clean()`이 통째로 지운다**
(`check.sh:15`). 그래서 Task 6보다 먼저 여기서 읽어 둔다.

### Step 2: `hangul/check.sh`를 만든다

**100줄이 넘으므로 Claude가 `/tmp/hangul_check.sh`에 만들어 둔다.**

```bash
mkdir -p hangul
cp /tmp/hangul_check.sh hangul/check.sh
chmod +x hangul/check.sh
```

내용:

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# HI 체인 — 한글 입력.
#
# 이 게이트가 증명하는 사슬 전체:
#   게스트에서 Shift+Space를 누른다
#   → input.zig의 hangulLayer가 한/영을 켠다
#   → 두벌식 키가 자모가 되고 hangul.zig가 음절로 모은다
#   → 그 글자가 **PTY로 안 나가고** 커서 자리에 그려진다
#   → Backspace가 자모를 하나 뺀다
#   → Enter가 조합을 확정시켜 UTF-8 세 바이트와 CR을 **한 번에** 내보낸다
#   → Shift+Space를 다시 누르면 영문으로 돌아온다
#
# **음성 검사가 이 체인의 값이다.** "한글이 조합된다"만 보면 조합 중인 자모가
# PTY로 새는지는 아무것도 증명되지 않는다 — 그리고 그것이 이 기능의 가장 흔한
# 실패 방식이다. 도구는 CM 체인과 같은 `terminal: key>` 줄 개수다. 그 줄은
# PTY로 바이트가 나갈 때만 찍히므로(main.zig의 `if (keys.bytes.len > 0)`)
# 개수가 안 늘어나는 것이 곧 "아무것도 안 나갔다"이다.
#
# **반전된 셀의 개수가 두 번째 도구다.** 한글은 두 칸이라(HI-M0 실측 3) 조합
# 중에는 커서가 두 칸을 반전한다. 하나만 반전되면 게스트 화면에서 글자의
# 오른쪽 절반이 사라지는데, 로그만 보는 게이트가 그것을 잡는 길이 이 셀
# 개수다.
#
# grep에 -a를 붙이는 이유는 로그에 NUL이 한 바이트라도 섞이면 grep이 파일을
# binary로 취급해 "Binary file matches"만 뱉기 때문이다.
#
# 디스크를 물지 않는다. HI-M1의 한/영은 설정과 무관하다 — 자판과 전환 키가
# 설정으로 가는 것은 HI-M2·M3이고, 그때 이 체인에 2차 부팅이 붙는다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

# 한글 층의 분기 순서와 확정 목록은 전부 여기서 먼저 걸러진다 — 부팅 1.5초를
# 쓰기 전에 0.1초로 잡을 수 있는 실패다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed (input_test, vt_test or hangul_test)"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 45455=TF, 45456=CP, 45457=IP, 45458=PM, 45459=HD, 45460=TR, 45461=CM.
# 겹치지 않는 번호를 쓰는 이유는 죽다 만 QEMU가 남았을 때 엉뚱한 게스트에
# 명령을 보내지 않기 위해서다.
MONITOR_PORT=45462

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  exec 3<&- 2>/dev/null
  exec 3>&- 2>/dev/null
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

report_failure() {
  echo "FAIL: $1"
  echo "--- markers ---"
  local marker
  for marker in \
    "terminal: screen>" \
    "terminal: hangul>" \
    "terminal: key>"; do
    if grep -aq "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- hangul lines ---"
  grep -a 'terminal: hangul>' "$LOG" | tail -n 20
  echo "--- key lines ---"
  grep -a 'terminal: key>' "$LOG" | tail -n 10
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

source ../gate_lib.sh

# key> 줄이 지금까지 몇 개 찍혔는지. 음성 검사가 이 값의 변화를 본다.
key_lines() {
  grep -ac 'terminal: key>' "$LOG" || true
}

# 마지막 hangul> 줄에서 값 하나를 뽑는다. **언제나 마지막 줄을 본다** — 그
# 줄이 곧 지금의 상태다.
hangul_field() {
  grep -a 'terminal: hangul>' "$LOG" | tail -n 1 |
    sed -E "s/.*$1=([^ ]+).*/\1/"
}

# 마지막 프레임만 잘라낸다. main.zig가 한 프레임을 screen> 로 시작하므로
# (dumpScreen이 render 직후 첫 번째다) 마지막 screen> 부터 파일 끝까지가 곧
# 마지막 프레임이다. **누적으로 세면 "부팅 이후 몇 번 찍혔는가"가 된다.**
last_frame() {
  awk '/terminal: screen>/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$LOG"
}

# 마지막 프레임에서 **반전된 셀**이 전부 몇 개인가.
#
# 기본 색은 fg=FFFFFF bg=102030이고(vt.zig의 init), 반전되면 정확히 뒤집힌
# 값이 된다. 이 화면에는 선택도 매치도 없으므로 반전된 셀은 커서뿐이고,
# 그래서 개수가 곧 "커서가 몇 칸을 먹었는가"다.
inverted_cells() {
  last_frame | grep -acE "terminal: style> [0-9]+,[0-9]+ fg=102030 bg=FFFFFF" || true
}

# 마지막 프레임의 화면 줄에서 그 문자열이 몇 번 나오는가.
screen_count() {
  last_frame | grep -a 'terminal: screen>' | grep -oaF "$1" | wc -l
}

qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -aq "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "terminal never rendered a prompt"
sleep 1

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor"

# ── 검사 1: 대조군 — 한글이 꺼져 있으면 키가 PTY로 나간다 ──────────────
#
# **이 검사가 없으면 아래 음성 검사가 뜻을 잃는다.** 키가 원래부터 안 나가고
# 있었다면 "조합 중에 안 나간다"는 아무것도 증명하지 않는다.
echo "=== typing 'echo ' with hangul off ==="
BEFORE_ECHO="$(key_lines)"
type_keys e c h o spc
sleep 1
AFTER_ECHO="$(key_lines)"
if [ "$AFTER_ECHO" -le "$BEFORE_ECHO" ]; then
  report_failure "plain keys did not reach the PTY (key> lines ${BEFORE_ECHO} -> ${AFTER_ECHO})"
fi
if [ "$(screen_count 'echo')" -lt 1 ]; then
  report_failure "the shell never echoed 'echo'"
fi
echo "plain keys reach the PTY and the shell echoes them"

# 조합 중이 아닐 때 커서가 먹는 칸 수. 아래 검사 3이 이 값과 비교한다.
CURSOR_CELLS="$(inverted_cells)"
if [ "$CURSOR_CELLS" != "1" ]; then
  report_failure "expected exactly 1 inverted cell for the shell cursor, got ${CURSOR_CELLS}"
fi

# ── 검사 2: Shift+Space가 한/영을 켠다 ─────────────────────────────────
#
# **`hangul>` 줄이 나온다는 것 자체가 절반이다.** 그 줄은 `keys.hangul`이
# 참일 때만 찍히므로(main.zig), 줄이 없으면 `Action.hangul`이 `readKeys`까지
# 못 왔다는 뜻이다.
echo "=== sendkey shift-spc ==="
BEFORE_TOGGLE="$(key_lines)"
type_keys shift-spc
sleep 1
if ! grep -aq 'terminal: hangul>' "$LOG"; then
  report_failure "Shift+Space produced no hangul> line at all"
fi
ON="$(hangul_field on)"
if [ "$ON" != "true" ]; then
  report_failure "Shift+Space left hangul on=${ON}, expected true"
fi
# **공백이 셸로 새면 안 된다.** 전환 키가 글자를 만들면 명령줄에 빈칸이
# 하나씩 늘어난다.
AFTER_TOGGLE="$(key_lines)"
if [ "$AFTER_TOGGLE" != "$BEFORE_TOGGLE" ]; then
  report_failure "Shift+Space leaked to the PTY (key> lines ${BEFORE_TOGGLE} -> ${AFTER_TOGGLE})"
fi
echo "Shift+Space turned hangul on and sent nothing to the shell"

# ── 검사 3: 두벌식이 조합되고, 그 글자는 PTY로 안 나간다 ───────────────
#
# `r`=ㄱ, `k`=ㅏ 라 `가`가 된다. 세 가지를 함께 본다.
#
#   1. `hangul> preedit=가`      — 조합 상태가 맞다
#   2. 마지막 프레임의 `screen>`에 `가`  — **화면에 실제로 그려졌다**
#   3. 반전된 셀이 **둘**        — 두 칸을 먹었다(HI-M0 실측 3)
#   4. `key>` 줄이 안 늘었다     — 음성 검사
#
# **1만 보면 "값은 맞는데 안 그렸다"를 못 잡고, 2만 보면 "그렸는데 값이
# 틀렸다"를 못 잡는다.** SP-M1의 실측 5가 같은 자리를 적어 두었다.
echo "=== typing 'rk' (가) ==="
type_keys r k
sleep 1
PRE="$(hangul_field preedit)"
if [ "$PRE" != "가" ]; then
  report_failure "typing 'rk' composed preedit=${PRE}, expected 가"
fi
if [ "$(screen_count '가')" -lt 1 ]; then
  report_failure "the composing syllable 가 was never drawn on screen"
fi
INV="$(inverted_cells)"
if [ "$INV" != "2" ]; then
  report_failure "the composing syllable took ${INV} inverted cell(s), expected 2"
fi
AFTER_JAMO="$(key_lines)"
if [ "$AFTER_JAMO" != "$AFTER_TOGGLE" ]; then
  report_failure "composing jamo leaked to the PTY (key> lines ${AFTER_TOGGLE} -> ${AFTER_JAMO})"
fi
echo "가 is composed, drawn across two cells, and nothing reached the shell"

# ── 검사 4: 받침이 붙는다 ──────────────────────────────────────────────
echo "=== typing 't' (갓) ==="
type_keys t
sleep 1
PRE="$(hangul_field preedit)"
if [ "$PRE" != "갓" ]; then
  report_failure "adding the final gave preedit=${PRE}, expected 갓"
fi
echo "the final attached: 가 -> 갓"

# ── 검사 5: Backspace가 자모를 하나 뺀다 ───────────────────────────────
#
# **음절을 통째로 지우지 않는 것이 요점이다**(design 결정 6). 그리고
# Backspace도 PTY로 안 나가야 한다 — 나가면 셸이 앞 글자를 하나 지운다.
echo "=== sendkey backspace ==="
type_keys backspace
sleep 1
PRE="$(hangul_field preedit)"
if [ "$PRE" != "가" ]; then
  report_failure "backspace gave preedit=${PRE}, expected 가"
fi
AFTER_BKSP="$(key_lines)"
if [ "$AFTER_BKSP" != "$AFTER_JAMO" ]; then
  report_failure "backspace while composing leaked to the PTY (key> lines ${AFTER_JAMO} -> ${AFTER_BKSP})"
fi
echo "backspace removed one jamo and sent nothing to the shell"

# ── 검사 6: Enter가 확정시키고 네 바이트가 한 번에 나간다 ──────────────
#
# **`key> 4 byte(s)`가 이 milestone의 결승선이다.** 확정된 음절의 UTF-8 세
# 바이트와 CR 하나가 **같은 write**로 나갔다는 뜻이고, 그것이 `readKeys`가
# 지키는 순서 계약(확정이 먼저)의 유일한 관측 가능한 증거다.
#
# 셋이 아니라 넷인 것에 뜻이 있다. 셋이면 CR이 빠진 것이고, 하나면 확정이
# 통째로 사라진 것이다.
echo "=== typing 't' then Enter ==="
type_keys t
sleep 1
type_keys ret
sleep 2
if ! grep -aq 'terminal: key> 4 byte(s)' "$LOG"; then
  report_failure "Enter did not send the committed syllable and CR as one 4-byte write"
fi
PRE="$(hangul_field preedit)"
if [ "$PRE" != "(none)" ]; then
  report_failure "Enter left preedit=${PRE}, expected (none)"
fi
echo "Enter committed 갓 and sent 3 UTF-8 bytes plus CR in one write"

# ── 검사 7: 조합이 끝난 뒤 커서가 다시 한 칸이다 ───────────────────────
#
# 안 돌아오면 증상이 "커서가 항상 두 칸으로 뚱뚱하다"이고, 원인은 `preedit`을
# 안 지운 것이다. **검사 3의 값과 짝이어야 뜻이 선다.**
INV="$(inverted_cells)"
if [ "$INV" != "1" ]; then
  report_failure "after committing, the cursor takes ${INV} inverted cell(s), expected 1"
fi
echo "the cursor is back to one cell"

# ── 검사 8: Shift+Space가 한/영을 끈다 ─────────────────────────────────
echo "=== sendkey shift-spc again ==="
type_keys shift-spc
sleep 1
ON="$(hangul_field on)"
if [ "$ON" != "false" ]; then
  report_failure "the second Shift+Space left hangul on=${ON}, expected false"
fi
echo "Shift+Space turned hangul off"

# ── 검사 9: 영문이 돌아온다 ────────────────────────────────────────────
#
# **대조군이 하나 더 필요한 이유가 있다.** 검사 1은 한글을 켜기 **전**을
# 봤으므로, 껐을 때 되돌아오는지는 아무것도 말하지 않는다 — 토글이 한
# 방향으로만 동작해도 검사 1과 8이 전부 통과한다.
echo "=== typing 'rk' with hangul off ==="
BEFORE_LATIN="$(key_lines)"
type_keys r k
sleep 1
AFTER_LATIN="$(key_lines)"
if [ "$AFTER_LATIN" -le "$BEFORE_LATIN" ]; then
  report_failure "latin keys did not reach the PTY after turning hangul off"
fi
if [ "$(screen_count 'rk')" -lt 1 ]; then
  report_failure "the shell never echoed 'rk' after turning hangul off"
fi
echo "latin input is back"

echo "HI check PASS"
```

**검사 7이 원래 자리에 없다.** Step 1의 실측 4가 "셸이 한글을 되울린다"로
나오면, 검사 6 뒤에 아래를 끼워 넣고 번호를 하나씩 민다.

```bash
# ── 검사 (선택): 셸이 되울린 한글이 화면에 있다 ────────────────────────
#
# **Step 1의 실측으로만 넣는다.** 게스트에 LANG도 LC_ALL도 없어서 C 로케일의
# fish가 UTF-8을 그대로 되울리는지는 부팅해서 봐야 안다. 되울리면 명령줄과
# 출력줄에 하나씩, 모두 둘이다.
if [ "$(screen_count '갓')" -lt 2 ]; then
  report_failure "the shell did not echo the committed syllable back"
fi
```

### Step 3: 루트 게이트의 목록에 아홉째를 더한다

`check.sh:154`

지울 것:
```bash
  "CM-M2:./copy/check.sh"
)
```

넣을 것:
```bash
  "CM-M2:./copy/check.sh"
  "HI-M1:./hangul/check.sh"
)
```

`check.sh:157`

지울 것:
```
# 진입 검사는 **첫 부팅 전에** 여덟 개를 전부 훑는다.
```

넣을 것:
```
# 진입 검사는 **첫 부팅 전에** 아홉 개를 전부 훑는다.
```

그리고 `check.sh`의 체인 설명 주석 끝(`# 이 체인이 더하는 비용의 대부분은 ...`
문단 **뒤**, `# 이름과 경로를 한 곳에 모은다.` **앞**)에 넣을 것:

```
# HI 체인은 한글 입력을 본다. CM 체인과 판정 도구가 같다 — `key>` 줄 개수의
# **음성** 검사가 이 체인의 값이고, 조합 중인 자모가 PTY로 새는 것이 이
# 기능의 가장 흔한 실패 방식이다.
#
# 여기만 쓰는 도구가 하나 있다: **반전된 셀의 개수**다. 한글은 두 칸이라
# (HI-M0 실측 3) 조합 중에는 커서가 두 칸을 먹는데, 하나만 반전되면 게스트
# 화면에서 글자의 오른쪽 절반이 사라진다. 로그만 보는 게이트가 그 사고를
# 잡는 길이 그 개수다.
#
# 회차당 부팅 1회라 총 부팅 횟수는 30회에서 33회가 된다.
```

### Step 4: 체인 하나만 먼저 돌린다 (Claude가 실행, 약 6분)

**루트 게이트 18분을 쓰기 전에 이 체인만 3회 돌린다.**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  for i in 1 2 3; do
    echo "=== HI run ${i}/3 ==="
    bash hangul/check.sh || exit 1
  done
'
```
Expected: `HI check PASS`가 세 번 나온다.

**3회를 도는 이유는 flakiness다.** 타이핑이 게스트의 응답을 기다리는 구조라
(GL-M2) 한 번 통과한 것이 다음에도 통과한다는 보장이 없다.

### Step 5: 커밋

```bash
git add hangul/check.sh check.sh
git commit -m "Add the hangul gate chain"
```

---

## Task 6 — 루트 게이트

### Step 1: 돌린다 (Claude가 실행, 약 18분)

**Bash 도구의 10분 타임아웃을 넘으므로 `run_in_background`로 돌린다.**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash ./check.sh
```
Expected: `TARS check PASS: all chains 3/3 consecutive runs succeeded`

### Step 2: 걸린 시간을 적어 둔다

기준선은 HI-M0의 **16분 37.07초**(여덟 체인)이고, GL-M3의 16분 01~11초와
CC-M0의 16분 48.91초가 그 옆에 있다. **체인 하나에 약 2분이라는 design
결정 10의 셈이 여기서 처음 검증된다.**

**잡음이 ±3분이라는 것을 잊지 않는다.** 18분대가 나와도 "2분 늘었다"고
단정할 수 없다 — 갈렸다고 말하려면 GL-M2의 실측 1처럼 두 삼중값의 폭이 안
겹쳐야 한다. 값만 적고 판단은 보수적으로 쓴다.

---

## Task 7 — 문서를 맞춘다

**Files:** design doc · `HANDOFF.md` · `MEMORY.md` · `docs/decisions/`

### Step 1: design doc을 고친다

`docs/superpowers/specs/2026-08-31-tars-hangul-input-design.md`

- `Status:` 줄을 **HI-M1 완료**로 바꾸고 plan 경로를 더한다.
- **"HI-M1이 실측한 것"** 절을 만든다. 적을 것 넷.
  1. 셸이 한글을 되울리는가 (Task 5 Step 1의 실측 4). **안 되울리면 그것이
     HI-M2 이후의 숙제이고, 원인이 로케일이라는 것까지 적는다.**
  2. 게이트 시간과 체인 하나의 실제 비용 (Task 6).
  3. `Action`을 넓히는 대신 통로를 하나 더 둔 결정과 그 근거(확정 전 실측 1).
     **design 결정 6이 "확정 목록"만 적고 "어떻게 내보내는가"를 안 적었으므로
     그 자리를 여기서 메운다.**
  4. 커서가 두 칸을 반전하는 이유(확정 전 실측 4).
- **결정 4에 두 칸 반전을 한 줄 더한다.** 지금은 "커서 칸과 그 오른쪽 칸을
  함께 먹는다"까지만 적혀 있고 **왜 반전까지 두 칸인지**가 없다.

### Step 2: `HANDOFF.md`를 고친다

- 맨 위를 **"HI-M1이 끝났다"**로 바꾸고 다음 세션의 첫 일을 HI-M2의 plan으로
  적는다.
- **"HI-M1이 실행으로 증명한 것 — 다시 조사하지 말 것"** 절을 만든다.
- **"copy mode가 지금 할 수 있는 것" 표 옆에 한글 표를 하나 만든다** —
  Shift+Space · 두벌식 · Backspace · 확정을 유발하는 것들.
- 게이트 체인이 아홉이 됐다는 것과 새 시간을 적는다.

### Step 3: 기억을 고친다

`docs/decisions/project_hangul_input.md`에 HI-M1 절을 더한다. **새 파일을
만들지 않는다** — 같은 서브프로젝트다.

### Step 4: `CLAUDE.md`

**서브프로젝트가 아직 안 끝났다**(HI-M2·M3이 남았다). 완료 목록은 안 고치고,
"진행 중인 서브프로젝트: Hangul Input(HI)" 줄의 **"HI-M0 완료"를 "HI-M1
완료"로만** 고친다.

### Step 5: 커밋

```bash
git add docs/ HANDOFF.md MEMORY.md CLAUDE.md
git commit -m "Close out HI-M1"
```
