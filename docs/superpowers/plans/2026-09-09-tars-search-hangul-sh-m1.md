# SH-M1 Implementation Plan — 칠 수 있다 (화면은 아직 깨져 보인다)

> **실행 방식은 `CLAUDE.md`를 따른다.** 설명 먼저 → 명령 실행은 Claude Code가
> → 결과를 상세히 설명. 승인 뒤의 `git commit`도 Claude Code가 만든다.
> **이번 세션에 한해 편집도 Claude Code가 한다** — 사용자가 2026-09-09에
> "이번 세션의 구현에 대한 모든 결정을 위임한다"고 정했다. 다음 세션은 다시
> 기본 규칙(사용자가 편집)으로 돌아간다.

**Goal:** `/` 프롬프트에서 자모 키가 needle의 한글이 된다. `Enter`가 확정하고
제출하며, `Esc`는 조합만 버리고, `Backspace`는 조합 중이면 자모 하나를 뺀다.

**Architecture:** find 분기가 `hangulLayer`를 **부른다**(다시 적지 않는다).
확정된 음절은 HI-M1이 만든 `commit_buf` 통로를 타고, **`readKeys`가 모드를
보고 목적지를 가른다** — 셸이냐 needle이냐.

**Tech Stack:** Zig · `terminal/src/input.zig` · `terminal/src/input_test.zig` ·
`terminal/src/main.zig` · `hangul/check.sh` · 컨테이너 안의 `zig build test`

---

## 이 milestone이 끝난 뒤에 무엇이 보이는가 — **깨져 보인다**

**의도된 중간 상태다.** `drawPrompt`가 아직 바이트 하나를 글자 하나로 세므로
(`main.zig:138`) needle의 `가`는 **글리프 셋**으로 그려지고 뒤 칸이 두 칸씩
밀린다. 그리고 조합 중인 글자는 **아예 안 보인다** — preedit은 격자 안에
그려지는데 copy mode에서는 `cells()`가 그것을 억제하기 때문이다(`vt_test`
검사 47).

**검색은 맞는 결과를 낸다.** 게이트가 그 갈림을 정확히 밟는다 —
`find> submit matches=N`은 초록인데 `find> overlay text=`의 글자는 화면에서
깨진다. **그 갈림이 SH-M2의 경계를 그린다.**

## SH-M0이 놓아 둔 것

`findBytes`가 "통째로 받거나 거절한다"이고 `findErase`가 UTF-8 한 글자를
지운다. **부르는 자리가 `vt_test`뿐이었고**, 이 milestone이 그 자리에
`main.zig`를 잇는다.

## 데이터 흐름 — 갈래가 나는 자리는 하나다

```
자모 키(find 모드)
  └→ find 분기 ── Esc·Enter를 먼저 가로챈다
                └→ hangulLayer  ── 조합 중 ─→ hangul_buf (아직 안 보인다)
                                └─ 확정 ────→ commit_buf
                                                  │
                        readKeys가 **handleKey 앞에서 읽은** 모드로 가른다
                              ├─ normal/copy ─→ PTY 바이트 (지금 그대로)
                              └─ find ────────→ copies에 `.find_commit`
                                                  → main.zig → findBytes
```

**`readKeys`가 모드를 앞에서 읽어야 하는 이유가 이 milestone의 함정이다.**
`Enter`가 `.find` → `.copy`로 모드를 바꾸므로, 뒤에서 읽으면 마지막 음절이
needle이 아니라 **셸로 샌다.** 증상은 "검색어의 마지막 글자가 빠지고 셸에
이상한 글자가 남는다"이고 원인에서 멀다(design 위험 1).

## 파일 구조

| 파일 | 무엇 |
|---|---|
| `terminal/src/input.zig` | `commit_buf`를 여덟 바이트로 · `pushCommit`이 **이어 붙인다** · find 분기가 `hangulLayer`를 부른다 · `Copy.find_commit` · `readKeys`의 목적지 갈래 |
| `terminal/src/input_test.zig` | 검사 49~56. **마지막이 `readKeys`를 파이프로 직접 돌리는 검사**이고, 그것만이 결정 5를 정면으로 본다 |
| `terminal/src/main.zig` | `.find_commit` 배선 한 자리(`screen.findBytes`) |
| `hangul/check.sh` | 검사 18 — 게스트에서 `/` → `kf` → `Enter` |

**안 건드리는 파일.** `vt.zig`는 SH-M0이 끝냈고 이 milestone이 한 글자도 안
바꾼다. `hangul.zig`도 그대로다 — **조합 로직은 한 벌뿐이고 우리는 그것을
부를 뿐이다**(design 결정 4).

---

## Task 1: find 분기가 `hangulLayer`를 부른다

**Files:**
- Modify: `terminal/src/input.zig` — `commit_buf`/`pushCommit`/find 분기
- Test: `terminal/src/input_test.zig` — 검사 49~55

- [ ] **Step 1: 실패하는 검사를 넣는다 (검사 49~55)**

`input_test.zig`의 마지막 검사(48) 뒤, `PASS` 앞에 넣는다. **새 `State`를
따로 만든다** — 위쪽 `hg`는 두벌식이고 tap 상태가 잔뜩 묻어 있다.

검사 일곱이 보는 것.

| 검사 | 무엇 | 왜 |
|---|---|---|
| 49 | **한글이 꺼진 프롬프트는 한 글자도 안 바뀐다** | 회귀. 이것이 없으면 아래 여섯이 "한글이 되는가"만 보고 ASCII가 깨진 것을 아무도 모른다 |
| 50 | 프롬프트 안에서 `Shift+Space`가 한/영을 켠다 | 결정 1. 프롬프트가 상태를 물려받으므로 **안에서도 바꿀 수 있어야** 한다 |
| 51 | 자모 키가 `.redraw`이고 조합이 자란다 | 배선. `find_char`로 새면 needle이 `gks`가 된다 |
| 52 | `Backspace` 두 갈래 | 조합 중이면 자모 하나, 아니면 `.find_erase` |
| 53 | `Esc`가 **조합만** 버린다 | 결정 3. 프롬프트가 살아 있고 모드가 `.find` 그대로다 |
| 54 | `Enter`가 확정하고 제출한다 | 결정 3. `.find_submit`과 `commit`이 **함께** 나온다 |
| 55 | 세벌식 기호 되돌림이 음절과 기호를 **둘 다** 싣는다 | 결정 6. `commit_buf`를 넓히는 유일한 이유 |

```zig

    // ── SH-M1: 검색 프롬프트의 한글 ──────────────────────────────────────
    //
    // **State를 새로 만든다.** 위의 `hg`는 tap 상태와 대문자 잠금이 묻어
    // 있고, 여기서 보는 것은 모드와 한글 층의 관계뿐이다.
    var fp: input.State = .{ .hangul_layout = .dubeol };

    // 검사 49. **대조군 — 한글이 꺼져 있으면 프롬프트가 한 글자도 안 바뀐다.**
    // 이 검사가 없으면 아래 여섯이 전부 "한글이 되는가"만 보고, ASCII 경로가
    // 깨진 것을 아무도 모른다(design 결정 4의 마지막 줄).
    try expect(&fp, K.KEY_LEFTMETA, 1, "");
    try expect(&fp, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&fp, K.KEY_C, .enter);
    try expect(&fp, K.KEY_LEFTSHIFT, 0, "");
    try expect(&fp, K.KEY_LEFTMETA, 0, "");
    try expectCopy(&fp, K.KEY_SLASH, .find_open);
    try expectCopy(&fp, K.KEY_G, .{ .find_char = 'g' });
    try expectCopy(&fp, K.KEY_K, .{ .find_char = 'k' });

    // 검사 50. **프롬프트 안에서 한/영을 켤 수 있다**(design 결정 1).
    // 프롬프트가 지금의 상태를 물려받으므로, 영문으로 열린 채 한글을 치려면
    // 여기서 바꾸는 길이 있어야 한다. `hangulLayer`가 이 갈래를 `hangul_on`
    // 검사보다 **앞**에 두고 있어 꺼져 있을 때도 닿는다.
    try expect(&fp, K.KEY_LEFTSHIFT, 1, "");
    try expectHangul(&fp, K.KEY_SPACE, "", null);
    try expect(&fp, K.KEY_LEFTSHIFT, 0, "");
    if (!fp.hangul_on) {
        std.debug.print("FAIL: Shift+Space in the find prompt did not turn hangul on\n", .{});
        return error.ToggleFailed;
    }
    if (fp.mode != .find) {
        std.debug.print("FAIL: Shift+Space closed the find prompt\n", .{});
        return error.FindModeLost;
    }

    // 검사 51. **자모 키가 needle이 아니라 조합으로 간다.** `gks`가 `한`이다.
    // **`.find_char`로 새면 needle이 `gks`가 되고**, 그것이 이 서브프로젝트가
    // 없애려는 바로 그 증상이다(design "왜 지금인가").
    try expectHangul(&fp, K.KEY_G, "", 'ㅎ');
    try expectHangul(&fp, K.KEY_K, "", '하');
    try expectHangul(&fp, K.KEY_S, "", '한');

    // 검사 52. **Backspace가 두 갈래다.** 조합 중이면 자모 하나(`한`→`하`),
    // 아니면 needle의 마지막 글자다. **갈래를 나누는 것은 `hangul.erase`가
    // 주는 null 하나**이고, 그래서 find 분기에 조건문이 안 생긴다.
    try expectHangul(&fp, K.KEY_BACKSPACE, "", '하');
    try expectHangul(&fp, K.KEY_BACKSPACE, "", 'ㅎ');
    try expectHangul(&fp, K.KEY_BACKSPACE, "", null);
    // 조합이 없으니 이제 needle을 지운다.
    try expectCopy(&fp, K.KEY_BACKSPACE, .find_erase);

    // 검사 53. **Esc는 조합만 버린다**(design 결정 3). 프롬프트는 살아 있고
    // 모드도 `.find` 그대로다 — `Esc`가 한 겹씩 벗기는 규칙(CN-M1 결정 9)이
    // 셋째 겹으로 늘어난 자리다.
    //
    // **버린다는 것이 요점이다** — 확정하면 `Esc`가 취소가 아니라 입력이 된다.
    try expectHangul(&fp, K.KEY_G, "", 'ㅎ');
    try expectHangul(&fp, K.KEY_K, "", '하');
    try expectHangulAt(&fp, K.KEY_ESC, 1, 0, "", null);
    if (fp.mode != .find) {
        std.debug.print("FAIL: Esc on a composing syllable also closed the prompt\n", .{});
        return error.FindModeLost;
    }
    // **두 번째 Esc가 프롬프트를 닫는다.** 조합이 없으니 평소의 갈래다.
    try expectCopy(&fp, K.KEY_ESC, .find_cancel);
    if (fp.mode != .copy) {
        std.debug.print("FAIL: the second Esc did not fall back to copy mode\n", .{});
        return error.FindCancelLeftMode;
    }

    // 검사 54. **Enter가 확정하고 제출한다**(design 결정 3). 둘이 **함께**
    // 나오는 것이 이 검사의 전부다 — `Action`은 하나만 담으므로 확정분은
    // `commit_buf`를 타고, `expectCommit`이 그것을 본다.
    //
    // **`Esc`와 다른 규칙인 것이 모순이 아니다.** `Esc`는 취소라 겹이,
    // `Enter`는 진행이라 폭포가 자연스럽다.
    try expectCopy(&fp, K.KEY_SLASH, .find_open);
    try expectHangul(&fp, K.KEY_G, "", 'ㅎ');
    try expectHangul(&fp, K.KEY_K, "", '하');
    try expectHangul(&fp, K.KEY_S, "", '한');
    try expectCopy(&fp, K.KEY_ENTER, .find_submit);
    try expectCommit(&fp, K.KEY_ENTER, "한");
    try expectPreedit(&fp, K.KEY_ENTER, null);
    if (fp.mode != .copy) {
        std.debug.print("FAIL: Enter in the find prompt did not leave the prompt\n", .{});
        return error.FindSubmitStayed;
    }
    try expectCopy(&fp, K.KEY_ESC, .exit);

    // 검사 55. **세벌식의 기호 되돌림이 프롬프트에서 둘을 함께 싣는다**
    // (design 결정 6). 셸에서는 음절이 `commit_buf`로, 기호가 `.bytes`로
    // 갈라져 나갔다(HI-M2 실측 7) — **목적지가 둘이었기 때문이다.**
    // 프롬프트에서는 목적지가 needle 하나뿐이라 통로 하나에 둘을 실어야
    // 하고, 그것이 `commit_buf`를 여덟 바이트로 넓히는 유일한 이유다.
    //
    // 3-P3에서 `k`는 초성 ㄱ, `f`는 중성 ㅏ, `Shift+M`은 숫자 `1`이다.
    var sb: input.State = .{ .hangul_layout = .sebeol_3p3 };
    sb.hangul_on = true;
    try expect(&sb, K.KEY_LEFTMETA, 1, "");
    try expect(&sb, K.KEY_LEFTSHIFT, 1, "");
    try expectCopy(&sb, K.KEY_C, .enter);
    try expect(&sb, K.KEY_LEFTSHIFT, 0, "");
    try expect(&sb, K.KEY_LEFTMETA, 0, "");
    try expectCopy(&sb, K.KEY_SLASH, .find_open);
    try expectHangul(&sb, K.KEY_K, "", 'ㄱ');
    try expectHangul(&sb, K.KEY_F, "", '가');
    try expect(&sb, K.KEY_LEFTSHIFT, 1, "");
    // **`.bytes`가 아니라 `.redraw`다.** 프롬프트에서 `.bytes`를 돌려주면
    // 그 기호가 PTY로 나가서 **셸에 `1`이 찍힌다.**
    try expectHangul(&sb, K.KEY_M, "가1", null);
    try expect(&sb, K.KEY_LEFTSHIFT, 0, "");

    std.debug.print("input_test: 검색 프롬프트의 한글 OK\n", .{});
```

**`expectHangul`이 확정분까지 본다는 것이 여기서 값을 한다** — 그 헬퍼가
`.redraw`가 아닌 것(`.bytes`·`.copy`·`.scroll`)을 전부 실패로 만들고, 이어서
`expectCommit`·`expectPreedit`을 부른다.

- [ ] **Step 2: 돌려서 실패를 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

**기대: 런타임 실패다.** 부를 함수는 다 있고 동작만 없다. 첫 실패는 검사
51에서 나야 한다 — 자모 키가 아직 `.find_char`이므로 `expectHangul`이
"got copy .find_char, want hangul"으로 죽는다.

**검사 49·50이 먼저 통과하는 것을 함께 본다.** 49는 지금 코드가 이미 하는
일이고, 50이 통과하는 것은 **의외가 아니다** — `handleKey`의 find 분기가
`hangulLayer`를 안 부르지만, `Shift+Space`는 `KEY_SPACE`라 find 분기의 `else`
갈래로 가서... **가 아니다.** 지금은 `.find_char = ' '`가 되므로 50도
실패한다. 실패 둘 중 앞의 것(50)이 먼저 보인다.

- [ ] **Step 3: `commit_buf`를 넓히고 `pushCommit`을 이어 붙이게 한다**

`terminal/src/input.zig`에서 이 두 줄을 찾는다.

```zig
    commit_buf: [4]u8 = undefined,
    commit_len: usize = 0,
```

`[4]`를 `[8]`로 고치고, 바로 위 주석의 마지막 문단(`**한 키가 확정시키는
음절은 많아야 하나다.** ...`)을 아래로 바꾼다.

```zig
    /// **한 키가 확정시키는 것은 많아야 둘이다**(SH design 결정 6). 음절
    /// 하나는 UTF-8로 언제나 세 바이트지만(U+0800~U+FFFF), 세벌식의 기호
    /// 되돌림은 **조합 중이던 음절과 그 기호를 함께** 내보낸다.
    ///
    /// **셸에서는 넷으로 충분했다**(HI-M2 실측 7). 목적지가 둘이라 음절은
    /// 이 버퍼로, 기호는 `.bytes`로 갈라 보냈기 때문이다. **검색 프롬프트는
    /// 목적지가 needle 하나뿐이라** 통로 하나에 둘을 실어야 한다 — 여덟은
    /// 음절 4 + 기호 4다.
    commit_buf: [8]u8 = undefined,
    commit_len: usize = 0,
```

`pushCommit`을 **이어 붙이게** 바꾼다. 지울 것:

```zig
    fn pushCommit(self: *State, cp: u21) void {
        self.commit_len = std.unicode.utf8Encode(cp, &self.commit_buf) catch 0;
    }
```

넣을 것:

```zig
    fn pushCommit(self: *State, cp: u21) void {
        var utf8: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &utf8) catch return;
        self.appendCommit(utf8[0..n]);
    }

    /// 확정 통로의 **뒤에** 바이트를 잇는다(SH-M1).
    ///
    /// **덮어쓰지 않는 것이 결정 6이다.** 한 키가 음절과 기호를 함께
    /// 확정시키는 경로가 있고(세벌식 기호 되돌림), 검색 프롬프트에서는 그
    /// 둘의 목적지가 같다.
    ///
    /// 넘치면 **뒤를 버린다.** 여덟 바이트는 음절 넷과 기호 넷이라 닿을 수
    /// 없는 경계지만, 자르는 자리를 정해 두지 않으면 그 자리가 없다.
    fn appendCommit(self: *State, bytes: []const u8) void {
        for (bytes) |b| {
            if (self.commit_len >= self.commit_buf.len) return;
            self.commit_buf[self.commit_len] = b;
            self.commit_len += 1;
        }
    }
```

**`commit_len`을 0으로 되돌리는 자리는 여전히 `takeCommit` 하나다.** 한 키가
끝날 때마다 `readKeys`가 비우므로 키를 건너 쌓이지 않는다.

- [ ] **Step 4: find 분기가 `hangulLayer`를 부르게 한다**

`input.zig`의 find 분기(`if (self.mode == .find) {`)의 `switch` 전체를 아래로
바꾼다. **지울 것은 `switch (code) { c.KEY_ESC => ... } }` 열여덟 줄이다**
(`c.KEY_ESC`부터 `}` 둘까지).

```zig
        if (self.mode == .find) {
            // **Esc와 Enter를 한글 층보다 먼저 가로챈다**(SH design 결정 3).
            //
            // 둘 다 `hangulLayer`에 그냥 넘기면 뜻이 어긋난다. Esc는 거기서
            // **확정**되는데(자모가 아닌 키의 갈래) 우리는 **버려야** 하고,
            // Enter는 확정된 뒤 null이 돌아와 아래 ASCII 갈래로 흘러
            // `find_char = '\r'`이 된다.
            switch (code) {
                c.KEY_ESC => {
                    // 조합 중이면 그 겹만 벗긴다. **확정하지 않는다** —
                    // 확정하면 Esc가 취소가 아니라 입력이 된다.
                    if (self.hangul_buf.codepoint() != null) {
                        self.hangul_buf = .{};
                        return .redraw;
                    }
                    self.mode = .copy;
                    return .{ .copy = .find_cancel };
                },
                c.KEY_ENTER => {
                    // 확정하고 제출한다(폭포). 확정분은 `commit_buf`를 타고
                    // `readKeys`가 needle로 옮기는데, **그 판단은 여기서
                    // 모드를 바꾸기 전의 값으로 해야 한다**(결정 5).
                    self.commitHangul();
                    self.mode = .copy;
                    return .{ .copy = .find_submit };
                },
                else => {},
            }
            // **한글 층을 부른다. 다시 적지 않는다**(design 결정 4).
            // 전환 키 넷 · Ctrl 조합 · 표 밖의 키 · 기호 되돌림 · Backspace가
            // 전부 그 함수 한 벌에 있고, 여기서 다시 적으면 두 벌이 된다.
            if (self.hangulLayer(code)) |act| {
                switch (act) {
                    // 기호 되돌림. 셸이었다면 이 바이트가 PTY로 나갔겠지만
                    // 프롬프트에서는 needle로 가야 한다 — **확정된 음절 뒤에**
                    // 이어 붙이고 화면만 다시 그린다(결정 6).
                    .bytes => |b| {
                        self.appendCommit(b);
                        return .redraw;
                    },
                    // 조합이 자랐거나 확정됐다. 확정분은 `commit_buf`에 있다.
                    else => return act,
                }
            }
            // 한글 층이 관심 없는 키다. **ASCII 경로가 한 글자도 안 바뀐다.**
            switch (code) {
                c.KEY_BACKSPACE => return .{ .copy = .find_erase },
                else => {
                    if (code >= qwerty_keymap.len) return nothing;
                    const ch = self.latinChar(code);
                    if (ch == 0) return nothing;
                    return .{ .copy = .{ .find_char = ch } };
                },
            }
        }
```

**`Backspace`가 아래로 내려간 것에 뜻이 있다.** 조합 중이면 `hangulLayer`가
자모를 하나 빼고 `.redraw`를 돌려주므로 여기 안 온다 — 갈래를 가르는 조건이
find 분기에 안 생기고 `hangul.erase`의 null 하나가 그 일을 한다.

- [ ] **Step 5: 돌려서 통과를 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

**기대: 새 줄 하나가 뜨고 마지막이 `PASS`다.**

```
input_test: 검색 프롬프트의 한글 OK
```

**옛 검사 17~23이 그대로 통과하는 것을 함께 본다** (`input_test: copy mode
OK`). 한글이 꺼진 프롬프트가 한 글자도 안 바뀌었다는 증거다.

- [ ] **Step 6: commit** — Claude Code가 만든다.

```bash
git add terminal/src/input.zig terminal/src/input_test.zig
git commit -m "Let the search prompt compose hangul through the one hangul layer"
```

---

## Task 2: 확정된 음절이 셸이 아니라 needle로 간다

**Files:**
- Modify: `terminal/src/input.zig` — `Copy.find_commit` · `readKeys`
- Modify: `terminal/src/main.zig` — 배선 한 자리
- Test: `terminal/src/input_test.zig` — 검사 56

- [ ] **Step 1: 실패하는 검사를 넣는다 (검사 56)**

**이 검사만이 결정 5를 정면으로 본다.** `handleKey`를 아무리 봐도 "모드를
언제 읽는가"는 안 보인다 — 그것은 `readKeys`의 두 줄 사이에 있는 사실이다.

**`readKeys`는 fd를 받으므로 파이프를 판다.** 컨테이너가 리눅스이고
`input_test`가 이미 `link_libc`라(`@cImport("linux/input.h")` 때문) libc의
`pipe`·`write`·`close`를 직접 선언해서 쓴다.

**`std.posix.pipe`를 안 쓰는 것은 취향이 아니라 사실이다** — Zig 0.16의
`std.posix`에는 `pipe`도 `write`도 `close`도 **없다**(컨테이너의
`lib/std/posix.zig`를 직접 확인했다). I/O가 `std.Io`로 옮겨 갔고, 남은 길이
`std.c`이거나 직접 선언이다. **`input.zig`가 `read`와 `open`을 이미 그렇게
선언해 두었으므로**(그 파일의 `extern "c" fn read` 주석) 같은 모양을 쓴다.

```zig

    // 검사 56. **확정된 음절이 셸이 아니라 needle로 간다**(SH design 결정 4·5).
    //
    // **`readKeys`를 직접 돌리는 이 파일의 첫 검사다.** 여태 `handleKey`만
    // 봤는데, 결정 5가 말하는 사실("모드를 `handleKey` **앞에서** 읽는다")은
    // 그 함수 안에 아예 없다 — `readKeys`의 두 줄 **사이**에 있다.
    //
    // 파이프를 파는 이유는 그 함수가 fd에서 읽기 때문이다. 이벤트 넷을 한
    // 번의 write로 넣으면 read 한 번이 전부 가져간다(PIPE_BUF가 4096이고
    // 이벤트 하나가 24바이트다).
    {
        var fk: input.State = .{ .hangul_layout = .dubeol };
        fk.hangul_on = true;
        fk.mode = .find;

        // `한` + Enter. **Enter가 이 검사의 심장이다** — 그 키가 모드를
        // `.copy`로 바꾸므로, `readKeys`가 모드를 뒤에서 읽으면 마지막 음절이
        // needle이 아니라 **셸로 샌다.**
        const evs = [_]input.c.struct_input_event{
            keyEvent(K.KEY_G, 1), keyEvent(K.KEY_K, 1),
            keyEvent(K.KEY_S, 1), keyEvent(K.KEY_ENTER, 1),
        };
        const fds = try feedEvents(&evs);
        defer _ = close(fds[0]);

        var out: [64]u8 = undefined;
        const keys = input.readKeys(&fk, fds[0], &out, .{});

        // **아무것도 셸로 안 샜다.** 이 한 줄이 결정 5의 판정 전부다 —
        // 뒤에서 읽는 구현은 여기서 `한`(세 바이트)을 내놓는다.
        if (keys.bytes.len != 0) {
            std.debug.print(
                "FAIL: {d} byte(s) \"{s}\" leaked to the shell from the find prompt\n",
                .{ keys.bytes.len, keys.bytes },
            );
            return error.LeakedToPty;
        }
        // 확정분이 먼저, 제출이 그다음이다. **순서가 뒤집히면 빈 검색어로
        // 검색한다.**
        if (keys.copies.len != 2) {
            std.debug.print(
                "FAIL: the find prompt made {d} copy command(s), want 2\n",
                .{keys.copies.len},
            );
            return error.WrongCopyCount;
        }
        switch (keys.copies[0]) {
            .find_commit => |cm| {
                if (!std.mem.eql(u8, cm.buf[0..cm.len], "한")) {
                    std.debug.print(
                        "FAIL: the needle got \"{s}\", want \"한\"\n",
                        .{cm.buf[0..cm.len]},
                    );
                    return error.WrongCommit;
                }
            },
            // **capture 없이 쓴다.** union의 `else` 갈래에서 payload를 잡으면
            // 남은 variant들의 타입이 같아야 하고, 여기서는 안 같다.
            else => {
                std.debug.print(
                    "FAIL: the first copy command is .{s}, want .find_commit\n",
                    .{@tagName(keys.copies[0])},
                );
                return error.WrongCopyCommand;
            },
        }
        // **`!=`로 태그를 비교할 수 없다** — union에는 `==`가 없다(CN-M1
        // Task 1이 `std.meta.eql`을 쓴 것과 같은 자리다). 여기서는 payload가
        // 없는 variant 하나만 보면 되므로 `activeTag`가 맞다.
        if (std.meta.activeTag(keys.copies[1]) != .find_submit) {
            std.debug.print(
                "FAIL: the second copy command is .{s}, want .find_submit\n",
                .{@tagName(keys.copies[1])},
            );
            return error.WrongCopyCommand;
        }
    }

    // 검사 57. **대조군 — 셸에서는 그대로 PTY로 나간다.** 이것이 없으면
    // "언제나 needle로 보낸다"는 구현도 검사 56을 통과하고, 그 구현은 셸의
    // 한글을 통째로 없앤다.
    {
        var nk: input.State = .{ .hangul_layout = .dubeol };
        nk.hangul_on = true;

        const evs = [_]input.c.struct_input_event{
            keyEvent(K.KEY_G, 1), keyEvent(K.KEY_K, 1),
            keyEvent(K.KEY_S, 1), keyEvent(K.KEY_ENTER, 1),
        };
        const fds = try feedEvents(&evs);
        defer _ = close(fds[0]);

        var out: [64]u8 = undefined;
        const keys = input.readKeys(&nk, fds[0], &out, .{});
        // 확정된 `한` 뒤에 Enter의 CR이다 — **순서가 곧 HI-M1의 계약이다.**
        if (!std.mem.eql(u8, keys.bytes, "한\r")) {
            std.debug.print(
                "FAIL: the shell got \"{s}\", want \"한\\r\"\n",
                .{keys.bytes},
            );
            return error.UnexpectedBytes;
        }
        if (keys.copies.len != 0) {
            std.debug.print(
                "FAIL: the shell path made {d} copy command(s), want 0\n",
                .{keys.copies.len},
            );
            return error.WrongCopyCount;
        }
    }

    std.debug.print("input_test: 확정된 음절이 모드를 따라 갈린다 OK\n", .{});
```

그리고 헬퍼를 파일의 헬퍼 무리 끝(`expectPreedit` 뒤)에 더한다.

```zig
/// **libc를 직접 선언한다**(SH-M1). Zig 0.16의 `std.posix`에는 `pipe`도
/// `write`도 `close`도 없다 — I/O가 `std.Io`로 옮겨 갔기 때문이다.
/// `input.zig`가 `read`와 `open`을 같은 이유로 이렇게 선언해 두었다.
extern "c" fn pipe(fds: *[2]c_int) c_int;
extern "c" fn write(fd: c_int, buf: [*]const u8, count: usize) isize;
extern "c" fn close(fd: c_int) c_int;

/// evdev 이벤트 하나를 만든다(SH-M1). **`readKeys`를 직접 돌리는 검사만
/// 쓴다** — 나머지는 `handleKey`를 부르므로 이벤트가 필요 없다.
///
/// `time`을 0으로 두는 것은 tap 판정을 안 건드리기 위해서다. 여기서 보는
/// 키는 전부 자모와 Enter라 tap과 무관하다.
fn keyEvent(code: u16, value: i32) input.c.struct_input_event {
    var ev = std.mem.zeroes(input.c.struct_input_event);
    ev.@"type" = input.c.EV_KEY;
    ev.code = code;
    ev.value = value;
    return ev;
}

/// 이벤트들을 파이프에 통째로 넣고 **읽는 쪽 fd만** 돌려준다.
///
/// **쓰는 쪽을 여기서 닫는 것이 계약이다.** 안 닫으면 `readKeys`의 `read`가
/// 다음 이벤트를 기다리며 막힐 수 있다. 닫아 두면 한 번의 read가 있는 것을
/// 전부 가져가고(24바이트 × 넷은 PIPE_BUF 4096 안이라 쪼개지지 않는다) 그
/// 뒤는 EOF다.
fn feedEvents(evs: []const input.c.struct_input_event) ![2]c_int {
    var fds: [2]c_int = undefined;
    if (pipe(&fds) != 0) return error.PipeFailed;
    const bytes = std.mem.sliceAsBytes(evs);
    if (write(fds[1], bytes.ptr, bytes.len) != @as(isize, @intCast(bytes.len)))
        return error.WriteFailed;
    _ = close(fds[1]);
    return fds;
}
```

- [ ] **Step 2: 돌려서 실패를 확인한다**

**기대: 컴파일 에러다.** `.find_commit`이 아직 없다.

```
error: no field named 'find_commit' in union 'input.Copy'
```

- [ ] **Step 3: `Copy.find_commit`과 `readKeys`의 갈래**

`input.zig`의 `Copy` union에서 `find_submit` 뒤에 넣는다.

```zig
    /// 프롬프트에서 확정된 글자가 needle로 간다(SH-M1, design 결정 4).
    ///
    /// **이 variant를 만드는 것은 `handleKey`가 아니라 `readKeys`다.** 그
    /// 갈림이 design이 "`find_text` variant를 안 골랐다"고 적은 것과 어긋나
    /// 보이지만 아니다 — 거기서 말한 후보는 **`handleKey`가 이것을
    /// 돌려주는** 모양이었고, 그러면 `Enter` 하나가 확정과 제출 둘을 담아야
    /// 해서 통로가 결국 둘이 된다. 여기서는 그 둘을 **`commit_buf`가 이미
    /// 갈라 놓았고**, 이 variant는 나르기만 한다.
    ///
    /// **payload가 슬라이스가 아니라 값인 것이 계약이다.** `commit_buf`는
    /// 다음 키가 덮어쓰므로, 한 번의 read에 여러 키가 실려 오면(자동 반복)
    /// 슬라이스는 마지막 값을 가리키게 된다 — `Action.bytes`를 `readKeys`가
    /// **즉시 복사하는** 것과 같은 이유이고, 여기서는 복사가 대입이다.
    find_commit: Commit,

    /// `find_commit`이 나르는 바이트. **여덟인 이유는 `commit_buf`와 같다**
    /// (design 결정 6) — 음절 넷 + 기호 넷.
    ///
    /// `buf`를 0으로 채워 두는 것은 `std.meta.eql` 때문이다.
    /// `input_test`의 `expectCopy`가 union을 그것으로 비교하는데,
    /// `undefined`로 두면 `len` 뒤의 쓰레기가 비교에 들어간다.
    pub const Commit = struct {
        buf: [8]u8 = [_]u8{0} ** 8,
        len: u8 = 0,

        pub fn init(bytes: []const u8) Commit {
            var out: Commit = .{};
            const n = @min(bytes.len, out.buf.len);
            @memcpy(out.buf[0..n], bytes[0..n]);
            out.len = @intCast(n);
            return out;
        }
    };
```

`readKeys`에서 `handleKey`를 부르는 자리를 바꾼다. 지울 것:

```zig
        const action = self.handleKey(ev.code, ev.value, eventMicros(ev), ctx);
```

넣을 것:

```zig
        // **모드를 `handleKey` 앞에서 읽는다**(SH design 결정 5). `Enter`가
        // `.find` → `.copy`로 모드를 바꾸므로, 뒤에서 읽으면 그 키가 확정시킨
        // 마지막 음절이 needle이 아니라 **셸로 샌다.** 증상이 "검색어의
        // 마지막 글자가 빠지고 셸에 이상한 글자가 남는다"라 원인에서 멀다.
        // `input_test`의 검사 56이 이 두 줄의 순서를 정면으로 본다.
        const to_needle = self.mode == .find;
        const action = self.handleKey(ev.code, ev.value, eventMicros(ev), ctx);
```

그리고 확정분을 옮기는 블록을 바꾼다. 지울 것:

```zig
        const commit = self.takeCommit();
        if (commit.len > 0) {
            redraw = true;
            for (commit) |byte| {
                if (written >= out.len) break;
                out[written] = byte;
                written += 1;
            }
        }
```

넣을 것:

```zig
        const commit = self.takeCommit();
        if (commit.len > 0) {
            redraw = true;
            if (to_needle) {
                // 검색 프롬프트에서 확정된 글자다. **PTY로 한 바이트도 안
                // 나간다** — 목적지가 needle이고, 그것을 아는 것은 `vt.zig`를
                // 볼 수 있는 `main.zig`다(IP design 결정 6).
                //
                // **copy 명령 목록에 싣는 것이 순서를 지킨다.** 같은 키가
                // 만든 `.find_submit`이 아래 switch에서 뒤에 실리므로,
                // 확정 → 제출의 순서가 저절로 맞는다.
                if (copied < self.copies.len) {
                    self.copies[copied] = .{ .find_commit = Copy.Commit.init(commit) };
                    copied += 1;
                }
            } else for (commit) |byte| {
                if (written >= out.len) break;
                out[written] = byte;
                written += 1;
            }
        }
```

- [ ] **Step 4: `main.zig`를 배선한다**

Step 3 뒤에 빌드하면 **`main.zig`가 컴파일 에러**다 — copy 명령 switch가
`else` 없이 닫혀 있어서 컴파일러가 배선할 자리를 알려준다(CM-M0부터의 규율).
`.find_submit` 갈래 **앞**에 넣는다.

```zig
                    // 확정된 한글이 needle로 들어간다(SH-M1). **`findChar`가
                    // 아니라 `findBytes`인 것이 SH-M0의 이유 전부다** —
                    // 바이트씩 넣으면 128바이트 경계에서 음절이 반만 들어간다.
                    .find_commit => |cm| {
                        screen.findBytes(cm.buf[0..cm.len]);
                        dumpFind(screen, "commit");
                    },
```

**`dumpFind`가 `find> commit needle=... len=N`을 찍는다.** 게이트가 "확정분이
needle에 닿았다"를 볼 유일한 창구이고, 문구가 `hangul/check.sh`와 중복되므로
**한쪽을 고치면 다른 쪽도 고쳐야 한다**(그 함수의 주석과 같은 계약이다).

- [ ] **Step 5: 돌려서 통과를 확인한다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

**기대: 새 줄 하나가 더 뜨고 마지막이 `PASS`다.**

```
input_test: 확정된 음절이 모드를 따라 갈린다 OK
```

- [ ] **Step 6: commit**

```bash
git add terminal/src/input.zig terminal/src/input_test.zig terminal/src/main.zig
git commit -m "Route a committed syllable to the needle while the prompt is open"
```

---

## Task 3: 게이트가 게스트에서 한글로 검색한다

**Files:**
- Modify: `hangul/check.sh` — 검사 18

**왜 `hangul/check.sh`인가.** `copy/check.sh`가 아니라 이쪽인 이유는 **이
체인만 `hangul_layout=sebeol_3p3`을 심은 디스크를 물기 때문이다**(design).
기본값으로 도는 체인에서 검사하면 자판에 대해 아무 말도 못 한다.

**검사 17이 끝난 자리를 그대로 쓴다** — 화면에 `가 `가 있고(ctrl-l로 지운
뒤라 깨끗하다) 한글이 **켜져 있다**(검사 15가 켰고 16이 그대로 뒀다).
**한글이 켜진 채로 프롬프트가 열리는 것 자체가 결정 1의 검사다.**

- [ ] **Step 1: 검사 18을 넣는다**

`hangul/check.sh`의 맨 끝(`echo "HI check PASS"` 앞)에 넣는다.

```bash

# ── 검사 18: 검색창에서 한글을 친다 ────────────────────────────────────
#
# **이 체인이 SH-M1의 사슬 전체를 밟는 유일한 자리다.**
#   copy mode 진입 → `/`가 프롬프트를 연다(한/영 상태를 물려받는다)
#   → 자판이 자모를 만들고 hangul.zig가 음절로 모은다
#   → 확정분이 **PTY가 아니라** find_buf로 간다(결정 4·5)
#   → Enter가 확정하고 제출해서 화면의 `가`를 찾는다
#
# **음성 검사가 여기서도 값이다.** `key>` 줄은 PTY로 바이트가 나갈 때만
# 찍히므로(main.zig의 `if (keys.bytes.len > 0)`), 개수가 안 늘어나는 것이 곧
# "조합도 확정도 셸로 안 샜다"이다. 샜다면 셸에 `가`가 찍히고 검색 결과가
# 아니라 명령행이 바뀐다.
#
# **`find> open`을 먼저 본다**(design 위험 3). `findOpen()`은 copy mode
# 안에서만 열리므로, copy mode 진입이 실패하면 그 뒤의 판정이 전부 "한글이
# 안 된다"처럼 보인다 — 2026-09-02에 실제로 그렇게 잘못 보고한 적이 있다.
echo "=== enter copy mode, open the prompt, type 가, submit ==="
KEYS_BEFORE="$(key_lines)"
type_keys meta_l-shift-c
sleep 1
type_keys slash
sleep 1
if ! grep -aq 'terminal: find> open' "$LOG"; then
  report_failure "the search prompt never opened, so copy mode was not active"
fi

# 3-P3에서 `k`가 초성 ㄱ, `f`가 중성 ㅏ다(위 검사 3~11이 쓰는 그 키다).
type_keys k f
sleep 1

# 조합 중에는 needle이 아직 안 자란다. **preedit으로 확인한다** — 이 줄이
# "자모가 needle로 새지 않았다"까지 함께 말한다.
PRE="$(hangul_field preedit)"
if [ "$PRE" != "가" ]; then
  report_failure "the prompt is composing preedit=${PRE}, expected 가"
fi

type_keys ret
sleep 1

# **확정분이 needle에 닿았다.** `find> commit`은 main.zig의 `.find_commit`
# 갈래만 찍는다 — 문구가 이 파일과 main.zig 양쪽에 있고, 한쪽을 고치면 다른
# 쪽도 고쳐야 한다.
if ! grep -aq 'terminal: find> commit needle=가 len=3' "$LOG"; then
  report_failure "the committed 가 never reached the needle (no find> commit line)"
fi

# **검색이 매치를 만들었다.** 화면에 `가 `가 있으므로 하나 이상이어야 한다.
SUBMIT="$(grep -a 'terminal: find> submit' "$LOG" | tail -n 1 | tr -d '\r')"
MATCHES="$(echo "$SUBMIT" | sed -E 's/.*matches=([0-9]+).*/\1/')"
if [ -z "$MATCHES" ] || [ "$MATCHES" -lt 1 ]; then
  report_failure "the hangul needle found ${MATCHES:-no} match(es): ${SUBMIT}"
fi

# **음성 검사.** 조합도 확정도 PTY로 안 나갔다.
KEYS_AFTER="$(key_lines)"
if [ "$KEYS_AFTER" != "$KEYS_BEFORE" ]; then
  report_failure "the prompt leaked to the shell (key> ${KEYS_BEFORE} -> ${KEYS_AFTER})"
fi
echo "the search prompt composed 가 and found ${MATCHES} match(es) without leaking to the shell"
```

- [ ] **Step 2: 이 체인만 한 번 돌린다**

**게이트 전체(18분)에 가기 전에 이 체인 하나(2분쯤)를 먼저 돌린다.**
HI-M3 실측 2가 세운 규율이다 — 실패했을 때 의심할 것이 새 검사 하나뿐이다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash hangul/check.sh
```

**기대: 마지막 줄이 `HI check PASS`이고, 그 앞에 새 줄이 하나 있다.**

```
the search prompt composed 가 and found N match(es) without leaking to the shell
```

- [ ] **Step 3: commit**

```bash
git add hangul/check.sh
git commit -m "Check that the search prompt types hangul inside the guest"
```

---

## Task 4: 루트 게이트 3/3

**Files:** 없다. 확인만 한다.

- [ ] **Step 1: 게이트를 돌린다**

**컨테이너 안에서 돌려야 한다.** SH-M0의 plan이 `time ./check.sh`라고 적어
호스트에서 돌렸다가 **macOS의 make 3.81이 커널 Makefile에 거절당했다**
(`GNU Make >= 4.0 is required`). 체인들은 `nproc`과 GNU make를 전제한다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } 2> /tmp/sh-m1.time
```

**기대: `TARS check PASS: all chains 3/3 consecutive runs succeeded`.**
기준선은 SH-M0의 실측값이고, 이 milestone은 키 넷을 더 보내므로 **몇 초쯤
늘어나는 것이 설명된다**(HI-M3이 검사 하나에 7~16초를 봤다).

- [ ] **Step 2: HANDOFF와 design을 고치고 커밋한다**

design의 SH-M1 절에 "SH-M1이 실측한 것"을 더한다.

```bash
git add HANDOFF.md docs/superpowers/specs/2026-09-09-tars-search-hangul-design.md
git commit -m "Close out SH-M1 with hangul reaching the search needle"
```

---

## 이 milestone이 **안 하는** 것

| 안 하는 것 | 어디로 |
|---|---|
| `drawPrompt`가 UTF-8과 폭 2를 안다 | SH-M2 |
| 조합 중인 글자를 프롬프트 끝에 반전해서 그린다 | SH-M2 |
| `promptText`·`Prompt`·`dumpOverlay`가 "어디부터 반전인지"를 나른다 | SH-M2 |
| 검색창의 붙여넣기 | SH 밖(design 비목표) |

## 위험

| # | 위험 | 처방 |
|---|---|---|
| 1 | **`readKeys`가 모드를 뒤에서 읽는다**(design 위험 1). `Enter`에서만 터지고 증상이 "마지막 글자가 빠진다"라 원인에서 멀다 | 검사 56이 `keys.bytes.len != 0`으로 정면으로 본다. **그 한 줄이 판정 전부다** |
| 2 | ~~`std.posix.pipe()`가 Zig 0.16에 없다~~ **착수 전에 확인해서 없앴다** — 컨테이너의 `lib/std/posix.zig`에 `pipe`·`write`·`close`가 하나도 없다. 처방은 libc 직접 선언이고 `input.zig`가 이미 쓰는 방법이다 | 그래도 남는 위험은 파이프 write가 쪼개지는 것인데, 96바이트는 `PIPE_BUF` 4096 안이라 원자적이다 |
| 3 | `Copy`에 payload가 붙어 `std.meta.eql` 비교가 쓰레기를 본다 | `Commit.buf`를 0으로 채운다. **`undefined`로 두면 `expectCopy`가 무작위로 실패한다** |
| 4 | **`.bytes` 갈래를 `appendCommit` 대신 그대로 돌려준다.** 세벌식에서만 터지고 두벌식 검사는 전부 초록이다 | 검사 55가 `sebeol_3p3`으로 그 자리를 본다. `expectHangul`이 `.bytes`를 실패로 취급하는 것이 잡는다 |
| 5 | 게이트의 `type_keys`가 로그가 안 자라 0.3초씩 기다린다 | 자모 키는 `.redraw`를 만들고 `dumpHangul`이 `hangul>` 줄을 찍으므로 로그가 자란다. **찍히는 조건은 `keys.redraw`이고 그것이 곧 우리가 돌려주는 값이다** |
