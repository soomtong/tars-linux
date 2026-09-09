# SH-M2 Implementation Plan — 보인다

> **실행 방식은 `CLAUDE.md`를 따른다.** 설명 먼저 → 명령 실행은 Claude Code가
> → 결과를 상세히 설명. 승인 뒤의 `git commit`도 Claude Code가 만든다.
> **이번 세션에 한해 편집도 Claude Code가 한다**(사용자가 2026-09-09에 위임).

**Goal:** 프롬프트의 한글이 제 모양으로 보이고, 조합 중인 글자가 검색어 끝에
**반전**으로 자란다.

```
  /한글█ㅅ█        ← ㅅ이 조합 중이라 반전돼 있다
  /한글█서█        ← 그 자리에서 자라난다
  /한글서버         ← 확정되면 반전이 풀린다
```

**Architecture:** `drawPrompt`가 IS-M1의 `drawRun`을 **재사용해** UTF-8과 폭 2를
알게 되고, 조합 중인 글자 하나를 그 뒤에 색을 맞바꿔 그린다. 그리고 그린
결과(다음 칸의 col과 반전 구간의 픽셀 범위)를 **돌려주어** 게이트가 판정할
자리를 만든다.

**Tech Stack:** Zig · `terminal/src/main.zig` · `hangul/check.sh` ·
컨테이너 안의 `zig build` · 게이트

---

## 지금 무엇이 깨져 있는가

SH-M1이 끝난 시점에 **검색은 맞는 결과를 내고 화면만 틀리다.**

| | 지금 | 왜 |
|---|---|---|
| needle의 `가` | 글리프 **셋**(EA·B0·80 각각)으로 그려지고 뒤 칸이 두 칸 밀린다 | `drawPrompt`가 `for (text) \|ch\|`로 **바이트 하나를 글자 하나로** 센다(`main.zig:138`) |
| 조합 중인 글자 | **아예 안 보인다** | preedit은 격자 안에 그려지는데 copy mode에서는 `cells()`가 억제한다(`vt_test` 검사 47) |

**둘째가 SH design 결정 2를 못 지키는 자리다.** "보이는 것과 찾을 것이 다르다"를
사람이 볼 길이 없으면, `Enter`를 쳤을 때 `서`가 먼저 확정되고 검색된다는 사실이
화면 어디에도 안 나타난다.

## 결정 — **조합 중인 글자를 `text`에 안 붙인다**

`promptText`가 만드는 문자열에 조합 중인 글자를 **이어 붙이지 않고**,
`Prompt`가 `edit: ?u21`로 따로 나른다.

**붙이는 쪽을 안 고른 이유가 셋이다.**

1. 붙이면 **"어디부터 반전인가"를 바이트 오프셋으로 함께 날라야 한다.** 값 둘이
   서로 맞아야 하는 상태가 하나 늘고, 어긋나면 반전이 한 글자 밀린다.
2. `promptText`는 갈래가 셋인데(SP design 결정 7) 조합이 붙는 곳은 **하나**다.
   붙이려면 그 함수 안에서 갈래를 다시 갈라야 한다.
3. **조합 중인 글자는 언제나 하나다.** 코드포인트 하나면 충분하고, 그리는 쪽이
   폭을 물어보는 것도 한 번이다.

**결정 2(반전)와 결정 9(UTF-8)는 그대로다** — 바꾼 것은 그것을 나르는 모양뿐이다.

## 게이트가 무엇으로 판정하는가 — **정수 하나가 UTF-8을 가른다**

`drawPrompt`가 **다음 칸의 col**을 돌려주고 그것을 시리얼에 찍는다.

```
/가  →  cols=3   (슬래시 1 + 한글 2)   ← 폭 2를 알았다
/가  →  cols=4   (슬래시 1 + 바이트 3) ← 바이트를 셌다
```

**반전은 IS-M1의 `caps ink on=87 off=87`과 같은 방법으로 본다** — 반전 구간
안에서 **두 색을 함께** 센다.

```
terminal: find> ink cols=5 inv=226 ink=30
                      │      │        └ 배경색으로 그려진 글자의 획
                      │      └ 글자색으로 칠해진 배경(반전)
                      └ 그린 칸 수
```

**`inv`만 보면 "글자를 안 그리고 사각형만 칠했다"가 통과한다.** 둘을 한 줄에
함께 찍는 것이 그 갈림을 만든다.

**범위를 다시 계산하지 않는다.** `dumpStatus`는 `drawStatus`와 같은 산수로 y를
다시 구해야 했고 IS-M0이 그 위험을 적어 뒀는데(어긋나면 언제나 0이고, 증상이
"안 그렸다"와 똑같다), 여기서는 **그린 함수가 자기가 칠한 픽셀 범위를 그대로
돌려준다.** 같은 산수가 두 곳에 안 생긴다.

## 파일 구조

| 파일 | 무엇 |
|---|---|
| `terminal/src/main.zig` | `drawRun`에 클립 한 줄 · `drawPrompt`가 UTF-8과 반전을 안다 · `Prompt.edit` · `PromptInk` · `render`의 반환값 · `dumpOverlay`에 `preedit=` · `dumpPromptInk` |
| `hangul/check.sh` | 검사 19 |

**호스트 검사가 안 는다 — 그것이 이 milestone의 성질이다.** `promptText`도
`drawPrompt`도 `main.zig`에 있고 그 파일은 프레임버퍼와 시리얼을 잡고 있어
호스트에서 못 돈다. **CS-M1이 `find> overlay`를 만든 이유가 정확히 이것이었다.**
그래서 게이트 판정 셋(`cols` · `inv` · `ink`)이 이 milestone의 검증 전부다.

---

## Task 1: `drawPrompt`가 UTF-8과 폭 2를 안다

**Files:**
- Modify: `terminal/src/main.zig` — `drawRun` · `drawPrompt` · `Prompt` ·
  `render` · 호출부

- [ ] **Step 1: `drawRun`이 화면 밖으로 안 나가게 한다**

`drawRun`의 `while` 안, `drawGlyph` **앞**에 넣는다.

```zig
        // **화면 밖으로 안 나간다.** `setPixel`은 범위를 검사하지 않으므로
        // (`drm.zig:149`) 여기서 멈추지 않으면 프레임버퍼 밖에 쓴다.
        //
        // **`drawPrompt`가 이 함수를 쓰기 시작하면서 필요해졌다**(SH-M2).
        // needle은 128바이트까지 자라는데 격자는 100칸 남짓이다. 상태 줄은
        // 짧아서 여태 안 닿았지만, 같은 함수가 지키는 편이 낫다.
        if (GRID_X + col * CELL_W + glyph.cell_width > fb.width) break;
```

- [ ] **Step 2: `Prompt`에 조합 중인 글자를 더하고 `drawPrompt`를 다시 쓴다**

`Prompt`에 필드 하나를 더한다.

```zig
    /// 조합 중인 글자(SH-M2, design 결정 2). **프롬프트가 열려 있을 때만
    /// 있다** — 닫힌 뒤의 오버레이(`/needle [3/12]`)에는 조합이 붙지 않는다.
    ///
    /// **`text`에 안 붙인 이유가 SH-M2 plan의 결정이다.** 붙이면 "어디부터
    /// 반전인가"를 바이트 오프셋으로 함께 날라야 하고, 그 둘이 어긋나면
    /// 반전이 한 글자 밀린다.
    edit: ?u21,
```

`drawPrompt`를 통째로 바꾼다. **지울 것은 함수 하나(주석 포함)이고**, 넣을
것이 아래다.

```zig
/// 프롬프트가 그려진 결과(SH-M2). **게이트가 이 값으로 판정한다.**
///
/// `cols`는 마지막으로 쓴 **다음 칸**이다 — `/가`가 3이면 폭 2를 안 것이고
/// 4면 바이트를 센 것이라, 정수 하나가 결정 9를 통째로 본다.
///
/// `x0`·`x1`은 반전 구간의 픽셀 범위다. 조합 중이 아니면 둘이 같다.
/// **그린 함수가 자기가 칠한 범위를 그대로 돌려주는 것**이 요점이다 —
/// `dumpStatus`처럼 산수를 다시 하면 어긋났을 때 언제나 0이 나오고 증상이
/// "안 그렸다"와 구별되지 않는다(IS-M0 실측의 경고).
const PromptInk = struct {
    cols: u32,
    x0: u32,
    x1: u32,
    y: u32,
};

/// 프롬프트 오버레이(CN-M1 design 결정 7). **격자를 다 그린 뒤 마지막 줄만
/// 덮는다.**
///
/// **`render`가 `present()`로 끝나므로 반드시 그 안에서, present 앞에 그려야
/// 한다.** 밖에서 그리면 다음 프레임까지 화면에 안 나온다.
///
/// 줄 전체를 먼저 배경색으로 지운다. 안 지우면 검색어가 짧아졌을 때 지난
/// 프레임의 꼬리가 오른쪽에 남는다 — Backspace를 눌렀는데 글자가 안 지워지는
/// 것처럼 보인다.
///
/// **검색어는 반전하지 않는다**(CN-M1 plan 결정 6). 선택도 copy 커서도 "색
/// 둘을 맞바꾼다"로 나타나므로, 프롬프트까지 반전하면 화면 맨 아래의 흰 띠가
/// 선택인지 프롬프트인지 갈리지 않는다. 앞의 `/` 한 글자가 그 표시다.
///
/// **조합 중인 글자 하나만 반전한다**(SH design 결정 2). 격자 안의 preedit이
/// 이미 쓰는 규칙이고, 위 문단과 어긋나지 않는다 — 저기서 말한 것은 **줄
/// 전체**이고 이것은 **글자 하나**다. 그리고 그 하나는 "아직 검색어가 아닌
/// 것"이라 표시가 필요하다.
///
/// **`drawRun`을 재사용한다**(SH design 결정 9). IS-M1이 상태 줄의 색을 칸마다
/// 가르려고 "한 토막을 한 색으로 그리고 다음 col을 돌려준다"는 모양으로
/// 만들었는데, 프롬프트의 반전 구간이 정확히 그 모양을 필요로 한다.
fn drawPrompt(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    p: Prompt,
) !PromptInk {
    if (p.rows == 0) return .{ .cols = 0, .x0 = 0, .x1 = 0, .y = 0 };
    const y = GRID_Y + @as(u32, p.rows - 1) * ROW_HEIGHT;

    var col: u32 = 0;
    while (col < p.cols) : (col += 1) {
        drawCellBackground(fb, GRID_X + col * CELL_W, y, p.bg);
    }

    col = try drawRun(fb, cache, p.text, y, p.fg, 0);

    const cp = p.edit orelse return .{ .cols = col, .x0 = 0, .x1 = 0, .y = y };

    // **조합 중인 글자는 색을 맞바꿔 그린다.** 배경을 글자색으로 칠하고 획을
    // 배경색으로 찍는다 — 격자 안의 커서·선택이 쓰는 규칙 그대로다.
    //
    // **두 칸을 칠해야 한다.** `drawGlyph`는 16픽셀을 첫 셀의 색 하나로
    // 찍으므로, 한 칸만 반전하면 글자의 오른쪽 절반이 어두운 바탕에 어두운
    // 색으로 그려져 **사라진다**(HI-M1 실측 3 · 2026-09-02의 사고와 같은
    // 메커니즘이다).
    const glyph = try cache.find(cp);
    const span = @max(1, glyph.cell_width / CELL_W);
    const x0 = GRID_X + col * CELL_W;
    var i: u32 = 0;
    while (i < span and col + i < p.cols) : (i += 1) {
        drawCellBackground(fb, GRID_X + (col + i) * CELL_W, y, p.fg);
    }
    drawGlyph(fb, glyph, x0, y, p.bg);
    return .{ .cols = col + span, .x0 = x0, .x1 = x0 + i * CELL_W, .y = y };
}
```

**`i`를 `span` 대신 `x1`에 쓰는 것에 뜻이 있다** — 칸이 모자라 덜 칠했으면
덜 칠한 만큼만 세야 판정이 실제 픽셀과 맞는다.

- [ ] **Step 3: `render`가 그 결과를 돌려준다**

`render`의 시그니처를 `!void`에서 `!?PromptInk`로 바꾸고, 프롬프트 갈래를
아래로 바꾼다.

```zig
    var ink: ?PromptInk = null;
    if (prompt) |p| ink = try drawPrompt(fb, cache, p);
```

끝에서 `try fb.present();` **뒤에** `return ink;`를 넣는다.

- [ ] **Step 4: 호출부 셋을 고친다**

`main` 루프의 프롬프트 구성에 `edit`을 더한다.

```zig
        const prompt: ?Prompt = if (promptText(screen, &prompt_buf)) |t| .{
            .text = t,
            // **프롬프트가 열려 있을 때만 조합을 붙인다**(SH-M2). 닫힌 뒤의
            // 오버레이는 지난 검색의 결과 표시이고, 그 위에 조합을 그리면
            // 검색어가 자라는 것처럼 보인다.
            //
            // `findNeedle()`이 열림의 진실이다 — `promptText`가 갈래를 가를
            // 때 보는 값과 같은 것이라, 둘이 어긋날 수 없다.
            .edit = if (screen.findNeedle() != null) key_state.preedit() else null,
            .rows = rows,
            .cols = cols,
            .fg = screen.defaultFg(),
            .bg = screen.defaultBg(),
        } else null;
```

`render` 호출을 바꾼다.

```zig
        const prompt_ink = try render(fb, &cache, cells, prompt, status_line);
```

`dumpOverlay` 뒤에 한 줄을 더한다.

```zig
        dumpPromptInk(fb, prompt_ink, prompt);
```

- [ ] **Step 5: 덤프 둘**

`dumpOverlay`를 바꾼다.

```zig
fn dumpOverlay(prompt: ?Prompt) void {
    const p = prompt orelse return;
    // **조합 중인 글자를 함께 찍는다**(SH-M2). `text=`만 보면 "조합이 아직
    // 검색어가 아니다"를 게이트가 볼 창구가 없다.
    //
    // `(none)`이라고 쓰는 이유는 `dumpHangul`과 같다 — 빈 문자열이면 줄이
    // 잘린 것인지 값이 없는 것인지 갈리지 않는다.
    var utf8: [4]u8 = undefined;
    const len: usize = if (p.edit) |cp|
        std.unicode.utf8Encode(cp, &utf8) catch 0
    else
        0;
    const edit: []const u8 = if (len == 0) "(none)" else utf8[0..len];
    std.debug.print("terminal: find> overlay text={s} preedit={s}\n", .{ p.text, edit });
}

/// 프롬프트가 실제로 그린 것을 픽셀로 센다(SH-M2).
///
/// **판정 셋이 한 줄에 있다.**
///   `cols` — 그린 칸 수. `/가`가 3이면 폭 2를 안 것이고 4면 바이트를 센 것이다
///   `inv`  — 반전 구간에서 **글자색**인 픽셀. 배경이 뒤집혔다는 증거
///   `ink`  — 반전 구간에서 **배경색**인 픽셀. 그 위에 글자를 그렸다는 증거
///
/// **`inv`만 보면 사각형만 칠한 구현도 통과한다.** IS-M1이 `CAPS` 칸에서
/// `on`과 `off`를 한 줄에 함께 찍은 것과 같은 이유다.
///
/// **범위를 여기서 다시 계산하지 않는다.** `drawPrompt`가 자기가 칠한 픽셀
/// 범위를 그대로 돌려준다 — `dumpStatus`가 `drawStatus`의 y 산수를 다시 해야
/// 했던 자리와 갈리는 지점이고, 어긋나면 언제나 0이 나오는 그 함정을 아예
/// 안 만든다.
///
/// **반드시 `render()` 뒤에 부른다** — 그 전에 부르면 이전 프레임을 읽는다.
///
/// 문구가 이 파일과 `hangul/check.sh` 양쪽에 중복된다.
/// **한쪽을 고치면 다른 쪽도 고쳐야 한다.**
fn dumpPromptInk(fb: drm.Framebuffer, ink: ?PromptInk, prompt: ?Prompt) void {
    const k = ink orelse return;
    const p = prompt orelse return;
    var inv: usize = 0;
    var glyph_ink: usize = 0;
    var x = k.x0;
    while (x < k.x1) : (x += 1) {
        var row: u32 = 0;
        while (row < ROW_HEIGHT) : (row += 1) {
            const px = fb.getPixel(x, k.y + row) & 0x00FFFFFF;
            if (px == (p.fg & 0x00FFFFFF)) inv += 1;
            if (px == (p.bg & 0x00FFFFFF)) glyph_ink += 1;
        }
    }
    std.debug.print("terminal: find> ink cols={d} inv={d} ink={d}\n", .{
        k.cols, inv, glyph_ink,
    });
}
```

- [ ] **Step 6: 빌드와 호스트 검사**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대: 둘 다 초록이고 검사 개수가 안 는다.** 이 milestone은 호스트에서 볼
수 있는 층을 안 건드린다.

- [ ] **Step 7: commit**

```bash
git add terminal/src/main.zig
git commit -m "Draw the search prompt in UTF-8 and invert the composing letter"
```

---

## Task 2: 게이트가 반전 픽셀 두 색을 센다

**Files:**
- Modify: `hangul/check.sh` — 검사 19

- [ ] **Step 1: 검사 19를 넣는다**

**검사 18이 끝난 자리를 그대로 쓴다** — 한글이 켜져 있고 화면에 `가`가 있고
copy mode 안이다(검사 18의 `Enter`가 프롬프트만 닫았다).

`hangul/check.sh`의 `echo "HI check PASS"` 앞에 넣는다.

```bash

# ── 검사 19: 프롬프트의 한글이 제 모양으로 보이고 조합이 반전된다 (SH-M2) ─
#
# **판정 셋이 한 줄에서 나온다**(`find> ink`).
#   cols — `/가ㄱ`가 5칸이다. 바이트를 세는 구현은 4가 된다(/ 1 + 가 3,
#          그리고 조합은 아예 안 그린다)
#   inv  — 반전 구간이 **글자색**으로 칠해졌다
#   ink  — 그 위에 글자가 **배경색**으로 그려졌다
#
# **`inv`만 보면 사각형만 칠한 구현이 통과한다.** IS-M1의 `caps ink on/off`와
# 같은 짝이다.
#
# 3-P3에서 `k`는 초성 ㄱ, `f`는 중성 ㅏ다. `k f k`면 `가`가 확정되어 needle에
# 들어가고 새 `ㄱ`이 조합 중으로 남는다 — **한 프레임에 확정된 한글과 조합
# 중인 한글이 함께 있는 상태**이고, 그것이 이 검사가 필요로 하는 그림이다.
echo "=== reopen the prompt and compose on top of a committed syllable ==="
type_keys slash
sleep 1
type_keys k f k
sleep 1

if ! grep -aq 'terminal: find> overlay text=/가 preedit=ㄱ' "$LOG"; then
  report_failure "the overlay does not carry the committed 가 and the composing ㄱ"
fi

COLS="$(find_ink cols)"
INV="$(find_ink inv)"
INK="$(find_ink ink)"
if [ "$COLS" != "5" ]; then
  report_failure "the prompt drew ${COLS} column(s) for /가ㄱ, expected 5 (it is counting bytes)"
fi
if [ "$INV" -le 0 ]; then
  report_failure "the composing letter is not inverted (inv=${INV})"
fi
if [ "$INK" -le 0 ]; then
  report_failure "the inverted block has no glyph in it (ink=${INK}); it is a solid rectangle"
fi
echo "the prompt drew /가ㄱ in ${COLS} columns with the composing letter inverted (inv=${INV} ink=${INK})"

# ── 검사 19a: Esc가 조합만 버린다 (SH design 결정 3) ───────────────────
#
# **`input_test`의 검사 53이 같은 사실을 반환값 쪽에서 본다.** 여기서는
# 화면 쪽에서 본다 — 반전이 사라지고 검색어는 남는다.
type_keys esc
sleep 1
if ! grep -aq 'terminal: find> overlay text=/가 preedit=(none)' "$LOG"; then
  report_failure "Esc did not drop the composing letter (or it dropped the needle too)"
fi
INV="$(find_ink inv)"
if [ "$INV" -ne 0 ]; then
  report_failure "the inverted block is still on screen after Esc (inv=${INV})"
fi
COLS="$(find_ink cols)"
if [ "$COLS" != "3" ]; then
  report_failure "the prompt drew ${COLS} column(s) for /가, expected 3"
fi
echo "Esc dropped only the composing letter and left /가 (cols=${COLS})"
```

그리고 헬퍼를 `status_caps` 옆에 더한다.

```bash
# 마지막 `find> ink` 줄에서 값 하나를 뽑는다(SH-M2).
#
# `tr -d '\r'`는 `status_caps`와 같은 이유다 — `ink=`가 줄 끝이라 안 지우면
# `[ "$X" -le 0 ]`가 **"integer expression expected"로 죽는다**.
find_ink() {
  grep -a 'terminal: find> ink ' "$LOG" | tail -n 1 | tr -d '\r' |
    sed -E "s/.*$1=([0-9]+).*/\1/"
}
```

- [ ] **Step 2: 이 체인만 한 번 돌린다** (약 1분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash hangul/check.sh
```

**기대: `HI check PASS`이고 새 줄 둘이 그 앞에 있다.**

- [ ] **Step 3: commit**

```bash
git add hangul/check.sh
git commit -m "Count the inverted pixels of the composing letter in the prompt"
```

---

## Task 3: 루트 게이트 3/3과 마무리

- [ ] **Step 1: 게이트를 돌린다** (약 19분)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } 2> /tmp/sh-m2.time
```

- [ ] **Step 2: design의 `Status:`를 닫고 HANDOFF를 고친다**

**서브프로젝트가 끝나므로 design doc의 `Status:` 줄을 함께 고친다**
(`CLAUDE.md`의 규율). `docs/decisions/`에 기억도 한 파일 남기고 `MEMORY.md`에
한 줄 더한다.

```bash
git add HANDOFF.md MEMORY.md docs/
git commit -m "Close out Search Hangul with a prompt that shows what it composes"
```

---

## 위험

| # | 위험 | 처방 |
|---|---|---|
| 1 | **`p.fg`와 `p.bg`가 `getPixel`이 주는 값과 형식이 다르다**(알파 바이트) | `dumpStatus`가 이미 `& 0x00FFFFFF`로 마스크한다. 양쪽 다 마스크한다 |
| 2 | 반전 구간의 `ink`가 0이다 — 글리프가 배경색과 **정확히** 같은 색으로 안 그려졌을 수 있다 | `drawGlyph`는 준 색을 그대로 찍는다(`setPixel(color)`). 0이면 그것은 진짜로 안 그린 것이다 |
| 3 | **`cols`가 5가 아니라 4다 — `가`가 확정 안 되고 `ㄱ`만 조합 중일 수 있다** | 3-P3의 `k`는 초성 전용이라 초+중 상태에서 새 음절을 연다. 검사 18이 같은 키로 `가`를 이미 만들었다 |
| 4 | 프롬프트가 매 프레임 시리얼 두 줄을 더 찍어 게이트가 느려진다 | 프롬프트가 열린 프레임에만 찍힌다. `find> hl`·`find> overlay`가 이미 같은 조건이다 |
| 5 | `drawRun`의 새 클립이 상태 줄을 자른다 | 상태 줄은 30칸 남짓이고 화면은 100칸이다. 자르는 조건이 `fb.width`라 실화면에서 안 닿는다 |
