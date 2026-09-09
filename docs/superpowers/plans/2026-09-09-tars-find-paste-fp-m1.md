# FP-M1 Implementation Plan — `Cmd+V`가 프롬프트에 닿는다

> **실행 방식은 `CLAUDE.md`를 따른다.** 설명 먼저 → 파일 편집 → 명령 실행은
> Claude Code가 → 결과를 상세히 설명. 승인 뒤의 `git commit`도 Claude Code가
> 만든다. 체크박스는 진행 추적용이다.
>
> **이 milestone도 편집을 Claude Code가 한다** — 사용자가 2026-09-09에
> 외출하며 위임했다. FP-M0의 예외와 같은 종류다.

**Goal:** `/` 프롬프트에서 `Cmd+V`를 누르면 클립보드의 첫 줄이 **셸이 아니라
검색어로** 간다.

**Architecture:** `Cmd+V`가 "붙여넣기다"라고 적힌 자리를 **둘에서 하나로**
줄인다(FP design 결정 1). 판단은 모드 분기 셋보다 앞의 한 자리에서 하고,
목적지는 `main.zig`가 프롬프트가 열렸는지로 가른다(결정 3). FP-M0이 세운
`findPaste`가 받는 쪽이다.

**Tech Stack:** Zig · `terminal/src/input.zig` · `terminal/src/input_test.zig` ·
`terminal/src/main.zig` · `hangul/check.sh` · 컨테이너 안의 `zig build test`와
게이트

---

## 착수 전에 코드를 읽고 확인한 것 — **다시 조사하지 말 것**

**실측 1. 게이트의 음성 검사를 `key_lines`로 하면 안 된다 — design을 고쳤다.**
검사 18이 "`key>` 줄이 안 늘었다"로 "셸로 안 샜다"를 보는데, **붙여넣기에는
그 수법이 통하지 않는다.** `dumpPaste`는 `pty.write`를 **직접** 부르지
`keys.bytes`를 거치지 않으므로 **`key>` 줄을 아예 안 만든다** —
`copy/check.sh:439`가 그 사실을 주석에 적어 뒀다.

**새는 것을 못 보는 음성 검사를 넣었으면 게이트가 초록인 채로 버그가 남는다.**
맞는 판정은 **`clip> paste` 줄 수가 안 늘었다**이다 — 셸 갈래가 찍는 줄이 그
줄이고, 두 갈래가 다른 접두사를 쓰는 것이 판정을 만든다.

**실측 2. 지우는 두 줄을 `input_test`가 이미 각각 하나씩 보고 있다.**

| 검사 | 무엇 | 지우는 줄 |
|---|---|---|
| `input_test` 11 | `Cmd+V`가 모드 **밖**에서 붙여넣는다 | `input.zig:1074`(`chord()`) |
| `input_test` 12 | 모드 **안**에서도 붙여넣는다 | `input.zig:1365`(copy 표) |

검사 12의 주석이 **"한쪽만 넣으면 나머지 모드에서 조용히 안 먹는다"**라고
적어 뒀다 — 결정 1이 없애는 중복이 바로 그것이다. **Task 1의 회귀 위험이
18분이 아니라 초 단위로 답한다.**

**실측 3. `metaed()`는 find 분기 앞에서 참이다.** modifier switch가
`input.zig:1184`, 뗄 때 거르는 줄이 `1231`, find 분기가 `1233`이다. 새 자리는
`1231`과 `1233` 사이이고, 그래서 **누름과 자동 반복에서만 돈다.**

**실측 4. 게이트에서 클립보드를 만드는 자리가 이미 마련돼 있다.** 검사 17이
`ctrl-l` 뒤에 `가`를 치고 `left left`로 **셸 커서를 그 글자 위에** 올려 뒀다.
`Cmd+Shift+C`로 들어가면 copy 커서가 그 자리를 물려받으므로(`copyEnter`가
셸 커서의 viewport 좌표를 쓴다), **커서를 한 칸도 안 옮기고 `v`·`y`로
클립보드에 `가`를 넣을 수 있다.**

## 파일 구조

| 파일 | 무엇 |
|---|---|
| `terminal/src/input.zig` | 1.35번 단계를 **더하고** 두 줄을 **지운다**. 순 감소는 아니지만 **같은 뜻이 적힌 자리가 2 → 1**이다 |
| `terminal/src/input_test.zig` | 검사 58·59를 함수 끝(검사 57 뒤)에 잇는다 |
| `terminal/src/main.zig` | `.paste` 갈래를 둘로 가르고 `dumpFindPaste`를 더한다 |
| `hangul/check.sh` | 검사 20을 검사 19a 뒤, `echo "HI check PASS"` 앞에 잇는다 |

**안 건드리는 파일 둘.** `vt.zig`는 FP-M0이 끝냈고 한 글자도 안 바뀐다.
`copy/check.sh`도 안 바뀐다 — **안 바뀐 채로 통과하는 것이 Task 1의 판정이다.**

---

## Task 1: `Cmd+V`의 판단을 한 자리로 모은다

**동작이 한 글자도 안 바뀌는 Task다** — 프롬프트 안을 빼고는. 그래서 판정이
"기존 검사가 그대로 통과한다"이다.

**Files:**
- Modify: `terminal/src/input.zig` — 더할 곳 `1231`과 `1233` 사이, 지울 곳
  `1067~1074`(chord)과 `1351~1369`(copy 표)
- Test: `terminal/src/input_test.zig` — 검사 57 블록 뒤

- [ ] **Step 1: 실패하는 검사를 넣는다 (검사 58·59)**

`terminal/src/input_test.zig`에서 이 줄을 찾는다 (1546행).

```zig
    std.debug.print("input_test: 확정된 음절이 모드를 따라 갈린다 OK\n", .{});
```

**그 줄 바로 다음에** 아래를 **넣는다**.

```zig

    // 검사 58. **프롬프트 안의 `Cmd+V`가 붙여넣기다**(FP design 결정 1).
    //
    // 지금은 `.find_char = 'v'`가 돌아온다 — find 분기가 copy 표와 `chord()`
    // 보다 **앞**이라 `Cmd+V`가 둘 중 어디에도 안 닿고, `latinChar()`는
    // modifier를 안 보기 때문이다. **needle에 글자 `v`가 들어가는 것**이
    // 이 Task가 없애는 증상이다.
    //
    // **대조군이 같은 블록에 있다** — Meta를 떼면 `v`는 여전히 글자다.
    // 그것이 없으면 "프롬프트에서 v는 언제나 paste"라는 구현도 통과하고,
    // 그 구현은 검색어에 `v`를 못 치게 만든다.
    {
        var fv: input.State = .{};
        try expect(&fv, K.KEY_LEFTMETA, 1, "");
        try expect(&fv, K.KEY_LEFTSHIFT, 1, "");
        try expectCopy(&fv, K.KEY_C, .enter);
        try expect(&fv, K.KEY_LEFTSHIFT, 0, "");
        try expectCopy(&fv, K.KEY_SLASH, .find_open);
        // Meta는 아직 눌려 있다.
        try expectCopy(&fv, K.KEY_V, .paste);
        // **붙여넣기는 프롬프트를 안 닫는다.** copy mode에서 그런 것과 같다
        // (`input_test` 검사 12) — 붙여넣고 이어서 더 칠 수 있어야 한다.
        if (fv.mode != .find) {
            std.debug.print("FAIL: Cmd+V in the find prompt left the prompt\n", .{});
            return error.PasteLeftFindMode;
        }
        // 대조군.
        try expect(&fv, K.KEY_LEFTMETA, 0, "");
        try expectCopy(&fv, K.KEY_V, .{ .find_char = 'v' });
    }

    // 검사 59. **조합 중에 붙여넣으면 음절이 먼저 확정된다**(FP design 결정 2).
    //
    // 새 자리가 `hangulLayer`보다 **앞**이라, `commitHangul()`을 명시적으로
    // 안 부르면 조합 중인 `한`이 **소리 없이 사라진다.** 증상은 "붙여넣었더니
    // 앞 글자가 없어졌다"이고 원인에서 멀다.
    //
    // **`Enter`가 이미 같은 한 줄을 쓴다**(`input.zig`의 find 분기). 새
    // 기계가 아니라 같은 처방의 두 번째 손님이다.
    {
        var fc: input.State = .{ .hangul_layout = .dubeol };
        fc.hangul_on = true;
        fc.mode = .find;
        try expectHangul(&fc, K.KEY_G, "", 'ㅎ');
        try expectHangul(&fc, K.KEY_K, "", '하');
        try expectHangul(&fc, K.KEY_S, "", '한');
        try expect(&fc, K.KEY_LEFTMETA, 1, "");
        try expectCopy(&fc, K.KEY_V, .paste);
        // 확정분은 `commit_buf`에 있다. **`Action`은 하나만 담으므로**
        // 붙여넣기와 확정이 같은 키에서 함께 나올 길은 이것뿐이다.
        try expectCommit(&fc, K.KEY_V, "한");
        try expectPreedit(&fc, K.KEY_V, null);
        try expect(&fc, K.KEY_LEFTMETA, 0, "");
    }

    std.debug.print("input_test: 프롬프트의 Cmd+V가 붙여넣기다 OK\n", .{});
```

**이름 둘을 골라 썼다.** `fv`·`fc`가 이 함수에 없는 이름인지 세어서 확인했다 —
`fp`·`fk`·`nk`·`fsb`·`cm`이 이미 쓰여 있고 **Zig는 이름 가리기를 막는다**
(SH-M1 실측 1이 한 Task에서 두 번 밟았다).

- [ ] **Step 2: 돌려서 실패를 확인한다**

Claude Code가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

**기대: 런타임 실패다.** 부를 것이 다 있으므로 컴파일은 된다.

```
FAIL: code=47 -> got copy .find_char, want copy .paste
```

**컴파일 에러가 아니라 런타임 실패인 것이 정상이다** — FP-M0의 Task 1과
반대다. 그때는 함수가 없었고 지금은 함수는 있는데 **뜻이 틀린 것**이다.

- [ ] **Step 3: 1.35번 단계를 넣는다**

`terminal/src/input.zig`에서 이 두 줄을 찾는다 (1230~1233행).

```zig
        // 뗄 때는 아무것도 보내지 않는다. 누름(1)과 자동 반복(2)만 문자를 만든다.
        if (value == 0) return nothing;
```

**그 줄 바로 다음에** 아래를 **넣는다**. (`// 1.4번 단계 — 검색 프롬프트`
주석보다 앞이다.)

```zig

        // 1.35번 단계 — 붙여넣기(FP design 결정 1·2). **모드 분기 셋보다
        // 앞이고, 그 자리가 이 단계의 전부다.**
        //
        // `Cmd+V`가 "붙여넣기다"라고 적힌 자리가 여기 **하나**다. 예전에는
        // 둘이었다 — copy 표 안(모드 안)과 `chord()`의 Meta 분기(모드 밖).
        // 그리고 find 분기가 그 둘보다 앞이라 **프롬프트에서는 `v`가 글자로
        // 새고 있었다.** 셋째 자리를 더하는 대신 하나로 모은다. 넷째 모드가
        // 생길 때 빼먹는 것이 다음 사고이기 때문이고, IS-M1이 `Action.caps`를
        // 안 만든 이유와 같은 종류다.
        //
        // **목적지는 여기서 안 정한다.** 무엇을 보낼지가 클립보드에 달려
        // 있고 클립보드는 `vt.zig`가 든다 — `input.zig`는 그 파일을 import하지
        // 않는다(IP design 결정 6). `main.zig`가 프롬프트가 열렸는지로 가른다.
        //
        // **`commitHangul()`이 필요한 이유는 이 자리가 `hangulLayer`보다
        // 앞이기 때문이다.** 조합 중에 `Cmd+V`를 누르면 음절이 먼저 확정돼야
        // 하는데, 그 일을 해 주던 층을 지나치게 됐다. `Enter`가 아래 find
        // 분기에서 이미 같은 한 줄을 쓴다.
        //
        // **그 뒤는 저절로 맞는다.** `readKeys`의 `takeCommit()`이 action과
        // 무관하게 돌면서 `to_needle`로 목적지를 가르므로, 셸이면 PTY로 find
        // 모드면 needle로 간다 — 새 통로가 안 는다.
        if (self.metaed() and code == c.KEY_V) {
            self.commitHangul();
            return .{ .copy = .paste };
        }
```

- [ ] **Step 4: `chord()`의 `Cmd+V` 줄을 지운다**

`terminal/src/input.zig`에서 이 **여덟 줄을 지운다** (Step 3이 아래를
밀었으므로 `c.KEY_V => .{ .copy = .paste },`를 이름으로 찾는다 — `chord()`
안에 하나뿐이다).

```zig
                // Cmd+V(CM-M2). **이 줄은 모드 밖의 붙여넣기만 담당한다** —
                // 모드 안에서는 아래 copy 표가 chord()보다 먼저라 여기까지
                // 오지 않으므로, 같은 뜻이 그쪽에도 적혀 있다(design 결정 4).
                //
                // 바이트가 아니라 copy 명령인 이유는, 무엇을 보낼지가
                // 클립보드에 달려 있고 클립보드는 vt.zig가 들기 때문이다.
                // input.zig는 vt.zig를 import하지 않는다(IP design 결정 6).
                c.KEY_V => .{ .copy = .paste },
```

**넣을 것은 없다.** 바로 위의 `c.KEY_BACKSPACE => ...` 줄과 바로 아래의
`else => null,` 줄이 그대로 이어진다.

- [ ] **Step 5: copy 표의 `Cmd+V` 갈래를 지운다**

`terminal/src/input.zig`에서 이 **열아홉 줄을 지운다** (`c.KEY_V => {`를
이름으로 찾는다 — 이제 파일에 하나뿐이다).

```zig
                // `v` 하나가 세 갈래다(CM-M2에서 늘었다).
                //
                //   Cmd+V   → 붙여넣기. **모드를 닫지 않는다.**
                //   Shift+V → 줄 선택
                //   v       → 문자 선택
                //
                // **Meta를 가장 먼저 보는 것은 chord()의 규칙과 같다** — 둘 다
                // 눌렸을 때 Cmd가 이긴다. 임의의 선택이지만 결정적이어야 해서
                // 두 곳이 같은 순서를 쓴다.
                //
                // Shift를 여기서 보는 것은 chord()의 예외와 성격이 다르다.
                // 모드 안의 표는 원래 문자 키를 직접 읽으므로, 대문자 V가
                // 소문자 v와 다른 명령이라는 것을 볼 자리가 여기뿐이다.
                c.KEY_V => {
                    if (self.metaed()) return .{ .copy = .paste };
                    return .{
                        .copy = if (self.shifted()) .select_line else .select_char,
                    };
                },
```

그 자리에 이것을 **넣는다**.

```zig
                // `v`가 두 갈래다. **셋이었는데 하나가 위로 올라갔다** —
                // `Cmd+V`는 1.35번 단계가 모드를 가리지 않고 먼저 가로챈다
                // (FP design 결정 1). 그래서 여기 오는 `v`에는 Meta가 없다.
                //
                // Shift를 여기서 보는 것은 chord()의 예외와 성격이 다르다.
                // 모드 안의 표는 원래 문자 키를 직접 읽으므로, 대문자 V가
                // 소문자 v와 다른 명령이라는 것을 볼 자리가 여기뿐이다.
                c.KEY_V => return .{
                    .copy = if (self.shifted()) .select_line else .select_char,
                },
```

- [ ] **Step 6: 돌려서 통과를 확인한다**

Claude Code가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

**기대: 새 줄 하나가 뜨고 마지막이 `PASS`다.**

```
input_test: 프롬프트의 Cmd+V가 붙여넣기다 OK
PASS
```

**옛 검사 둘이 그대로 통과하는 것이 이 Step의 본체다**(실측 2) — 검사
11(`Cmd+V`가 모드 밖에서 붙여넣는다)과 검사 12(모드 안에서도 붙여넣는다)가
방금 지운 두 줄을 각각 하나씩 보고 있었다. 둘 다 초록이면 **자리를 옮겼을
뿐 뜻은 안 바뀌었다**는 증거다.

- [ ] **Step 7: `copy/check.sh` 한 체인을 돌린다**

Claude Code가 실행한다. **한 체인이라 3~5분쯤 걸린다.**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash copy/check.sh
```

**기대: `CM check PASS`.** 실기에서 `Cmd+V`가 셸(391·446줄)과 copy
mode(495~507줄) 양쪽에서 그대로 동작하는 것을 본다. **결정 1의 유일한 위험이
정확히 이 체인의 범위 안이다.**

- [ ] **Step 8: commit** — Claude Code가 만든다.

`git diff | grep '^-'`로 지운 것이 위의 여덟 줄 + 열아홉 줄이 맞는지 읽는다
(CC-M0의 규율, IS-M0 실측 4가 똑같이 생긴 줄에서 겪은 것). 그 뒤:

```bash
git add terminal/src/input.zig terminal/src/input_test.zig
git commit -m "Decide Cmd+V once, before the mode branches"
```

---

## Task 2: `main.zig`가 목적지를 가른다

**Files:**
- Modify: `terminal/src/main.zig:873` 근처(`dumpPaste` 뒤) · `1157`(`.paste` 갈래)

- [ ] **Step 1: `dumpFindPaste`를 더한다**

`terminal/src/main.zig`에서 `dumpPaste`의 닫는 `}`를 찾는다 (882행).

```zig
    pty.write(master_fd, text);
    std.debug.print("terminal: clip> paste len={d}\n", .{text.len});
}
```

**그 줄 바로 다음에** 아래를 **넣는다**.

```zig

/// `Cmd+V`가 클립보드의 첫 줄을 **검색어에** 붙인다(FP design 결정 3·6).
///
/// **두 수를 한 줄에 함께 찍는다.** `put=0` 하나만으로는 "클립보드가 비었다"와
/// "128바이트를 넘어 거절됐다"가 안 갈리고, `clip=50 put=20`은 여러 줄이 첫
/// 줄에서 잘렸다는 것까지 한 줄로 말한다. IS-M1 실측 5가 `on=87 off=87`로
/// 배운 것과 같다.
///
/// **접두사가 `clip>`가 아니라 `find>`인 것에 뜻이 있다.** 게이트의 음성
/// 검사가 "`clip> paste` 줄이 안 늘었다"로 셸 갈래를 안 탔음을 보므로,
/// 두 갈래가 다른 접두사를 써야 그 판정이 선다. **`key>` 줄로는 못 본다** —
/// 붙여넣기는 `pty.write`를 직접 부르지 `keys.bytes`를 안 거친다.
///
/// 문구가 이 파일과 `hangul/check.sh` 양쪽에 있다 — **한쪽을 고치면 다른
/// 쪽도 고쳐야 한다**(`clip>`가 이미 그런 자리다).
fn dumpFindPaste(screen: *vt.Screen) void {
    const clip_len = if (screen.clipboard()) |t| t.len else 0;
    const put = screen.findPaste();
    std.debug.print("terminal: find> paste clip={d} put={d}\n", .{ clip_len, put });
}
```

- [ ] **Step 2: `.paste` 갈래를 둘로 가른다**

`terminal/src/main.zig`에서 이 **여섯 줄을 지운다** (Step 1이 아래를 밀었으므로
`.paste => dumpPaste`를 이름으로 찾는다).

```zig
                    // 붙여넣기는 **모드를 건드리지 않는다.** 그래서 모드 안에서
                    // 누르면 아래 dumpCopy가 좌표를 그대로 찍고, 모드 밖에서
                    // 누르면 `copy> paste`만 찍힌다. 게이트가 그 차이로 "모드가
                    // 살아 있는가"를 본다.
                    //
                    // 이것이 copies 배열에서 **유일하게 PTY로 나가는 명령**이다.
                    // 다른 아홉은 전부 우리 안에서 끝난다.
                    .paste => dumpPaste(screen, session.master_fd),
```

그 자리에 이것을 **넣는다**.

```zig
                    // 붙여넣기는 **모드를 건드리지 않는다.** 그래서 모드 안에서
                    // 누르면 아래 dumpCopy가 좌표를 그대로 찍고, 모드 밖에서
                    // 누르면 `copy> paste`만 찍힌다. 게이트가 그 차이로 "모드가
                    // 살아 있는가"를 본다.
                    //
                    // **목적지가 여기서 갈린다**(FP design 결정 3). `input.zig`는
                    // `vt.zig`를 import하지 않으므로(IP design 결정 6) 이 갈래는
                    // 여기에만 설 수 있다 — 저쪽은 `Cmd+V`가 눌렸다는 것까지만
                    // 알고, 클립보드도 프롬프트도 이 파일이 본다.
                    //
                    // **판단 근거가 `input.State`의 모드가 아니라 `findNeedle()`
                    // 이다.** `main.zig`가 볼 수 있는 것이 화면 쪽 사실이고,
                    // `findBytes`가 이미 `find_open`을 스스로 지킨다.
                    //
                    // 셸 갈래는 여전히 copies 배열에서 **유일하게 PTY로 나가는
                    // 명령**이다. 다른 아홉은 전부 우리 안에서 끝난다.
                    .paste => if (screen.findNeedle() != null)
                        dumpFindPaste(screen)
                    else
                        dumpPaste(screen, session.master_fd),
```

- [ ] **Step 3: 빌드가 되는지 본다**

Claude Code가 실행한다. **호스트 검사로는 이 Task를 못 본다** —
`main.zig`에는 검사가 없다. 컴파일이 통과하는지만 여기서 보고, 뜻은 Task 3의
게이트가 본다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대: 조용히 끝나고 검사들이 `PASS`.**

- [ ] **Step 4: commit** — Claude Code가 만든다.

```bash
git add terminal/src/main.zig
git commit -m "Route a paste to the needle when the search prompt is open"
```

---

## Task 3: 게이트가 붙여넣기를 본다 (`hangul/check.sh` 검사 20)

**Files:**
- Modify: `hangul/check.sh` — 검사 19a 뒤, `echo "HI check PASS"` 앞

- [ ] **Step 1: 검사 20을 넣는다**

`hangul/check.sh`에서 이 두 줄을 찾는다 (886~888행, 파일 끝).

```bash
echo "Esc dropped only the composing letter and left /가 (cols=${COLS})"

echo "HI check PASS"
```

**그 사이에** 아래를 **넣는다**.

```bash
# ── 검사 20: 화면의 한글을 잡아 검색창에 붙여넣는다 (FP-M1) ────────────
#
# **이 체인이 FP의 사슬 전체를 밟는 유일한 자리다.**
#   copy mode에서 `가`를 잡는다 → y가 클립보드에 넣는다
#   → `/`가 프롬프트를 연다 → `Cmd+V`가 **셸이 아니라 needle로** 간다
#   → Enter가 제출해서 화면의 `가`를 찾는다
#
# **작업 흐름이 여기서 닫힌다.** 지금까지는 화면에서 본 한글을 눈으로 읽고
# 손으로 다시 쳐야 했다(검사 18이 그 손을 흉내 낸다).
#
# **커서를 한 칸도 안 옮긴다**(FP-M1 실측 4). 검사 17이 `ctrl-l` 뒤에 `가`를
# 치고 `left left`로 셸 커서를 그 글자 위에 올려 뒀고, `copyEnter`가 셸
# 커서의 viewport 좌표를 물려받는다.
#
# **음성 검사가 `key_lines`가 아니라 `clip> paste` 줄 수인 것이 요점이다**
# (FP-M1 실측 1). 붙여넣기는 `pty.write`를 직접 부르지 `keys.bytes`를 안
# 거치므로 `key>` 줄을 아예 안 만든다 — 그 수법을 여기 쓰면 셸로 새도
# 초록이다.
echo "=== yank 가, open the prompt, paste it back ==="
PASTES_BEFORE="$(grep -ac 'terminal: clip> paste' "$LOG" || true)"

# 프롬프트를 닫고(Esc 하나) copy mode도 나간다(Esc 둘). **둘 다 삼켜진다** —
# 모드 밖이었다면 ESC가 셸로 나갔을 것이다.
type_keys esc
sleep 1
type_keys esc
sleep 1

# 다시 들어가면 copy 커서가 셸 커서 자리, 곧 `가` 위다.
type_keys meta_l-shift-c
sleep 1
type_keys v
sleep 1
type_keys y
sleep 1

CLIP_LINE="$(grep -a 'terminal: clip> len=' "$LOG" | tail -n 1 | tr -d '\r')"
CLIP_LEN="$(echo "$CLIP_LINE" | sed -E 's/.*len=([0-9]+).*/\1/')"
if [ -z "$CLIP_LEN" ] || [ "$CLIP_LEN" -lt 1 ]; then
  echo "--- clip> lines ---"
  grep -a 'terminal: clip>' "$LOG" | tail -n 5
  report_failure "y did not put anything on the clipboard: ${CLIP_LINE}"
fi

# 붙여넣는다.
type_keys meta_l-shift-c
sleep 1
type_keys slash
sleep 1
if ! grep -aq 'terminal: find> open' "$LOG"; then
  report_failure "the search prompt never reopened for the paste"
fi
type_keys meta_l-v
sleep 1

# **판정 하나가 두 수를 함께 본다.** `put`이 `clip`과 같으면 통째로
# 들어갔다는 뜻이고, 0이면 안 들어간 것이다. 첫 줄 자르기는 `vt_test`의
# 검사 58이 호스트에서 초 단위로 이미 본다 — 여기서 보는 것은 **배선**이다.
PASTE_LINE="$(grep -a 'terminal: find> paste ' "$LOG" | tail -n 1 | tr -d '\r')"
if [ -z "$PASTE_LINE" ]; then
  echo "--- find> lines ---"
  grep -a 'terminal: find> ' "$LOG" | tail -n 5
  report_failure "Cmd+V in the prompt produced no 'find> paste' line at all"
fi
PUT="$(echo "$PASTE_LINE" | sed -E 's/.*put=([0-9]+).*/\1/')"
if [ "$PUT" != "$CLIP_LEN" ]; then
  report_failure "the paste put ${PUT} byte(s) into the needle, expected ${CLIP_LEN}: ${PASTE_LINE}"
fi

# **음성 검사.** 셸 갈래를 안 탔다.
PASTES_AFTER="$(grep -ac 'terminal: clip> paste' "$LOG" || true)"
if [ "$PASTES_AFTER" != "$PASTES_BEFORE" ]; then
  report_failure "the paste went to the shell instead of the needle (clip> paste ${PASTES_BEFORE} -> ${PASTES_AFTER})"
fi

# **needle이 그 글자다.** 기존 `find> overlay` 줄을 그대로 쓴다.
if ! grep -aq 'terminal: find> overlay text=/가' "$LOG"; then
  echo "--- overlay lines ---"
  grep -a 'terminal: find> overlay' "$LOG" | tail -n 5
  report_failure "the pasted 가 never showed up in the prompt overlay"
fi

# **붙인 한글이 화면의 한글을 찾는다.**
type_keys ret
sleep 1
SUBMIT="$(grep -a 'terminal: find> submit' "$LOG" | tail -n 1 | tr -d '\r')"
MATCHES="$(echo "$SUBMIT" | sed -E 's/.*matches=([0-9]+).*/\1/')"
if [ -z "$MATCHES" ] || [ "$MATCHES" -lt 1 ]; then
  report_failure "the pasted needle found ${MATCHES:-no} match(es): ${SUBMIT}"
fi
echo "yanked 가 went into the needle (${PUT}/${CLIP_LEN} bytes) and found ${MATCHES} match(es)"
```

- [ ] **Step 2: `hangul/check.sh` 한 체인을 돌린다**

Claude Code가 실행한다. **한 체인이라 3~5분쯤 걸린다.** 전체 게이트에 가기
전에 새 검사가 맞는지 여기서 본다 — **HI-M3 실측 2가 "확인 Step을 따로 둔
것이 값을 했다"고 적은 그 자리다.**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash hangul/check.sh
```

**기대: `HI check PASS`.**

- [ ] **Step 3: commit** — Claude Code가 만든다.

```bash
git add hangul/check.sh
git commit -m "Watch a yanked hangul travel into the search needle"
```

---

## Task 4: 전체 게이트

**Files:** 없다. 확인만 한다.

- [ ] **Step 1: 게이트를 돌린다**

Claude Code가 실행한다. **아홉 체인 3/3이라 19분쯤 걸린다.**

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } 2> /tmp/gate.time
```

**기대: `TARS check PASS: all chains 3/3 consecutive runs succeeded`.**

직전 기준선은 SH가 남긴 **18분 58.81초**다. 검사 하나가 늘었으므로 7~16초
증가는 설명되는 값이다(2026-09-02의 사고를 고칠 때 같은 폭이었다). 다른 날의
측정이라 **±3분까지는 신호가 아니다**(HI-M2 실측 11).

- [ ] **Step 2: HANDOFF와 design의 `Status:`를 고친다**

FP가 닫히므로 design doc의 `Status:` 줄도 함께 고친다(`CLAUDE.md`의 규칙).
그 뒤:

```bash
git add HANDOFF.md docs/superpowers/specs/2026-09-09-tars-find-paste-design.md
git commit -m "Close out Find Paste with a clipboard that reaches the needle"
```

---

## 위험 다섯

| # | 위험 | 처방 |
|---|---|---|
| 1 | **두 줄을 지우다 회귀한다.** 결정 1의 유일한 위험 | `input_test` 검사 11·12가 **초 단위로** 각각 하나씩 본다(실측 2). 그다음 `copy/check.sh`가 실기에서 본다 |
| 2 | **음성 검사가 아무것도 안 본다.** `key_lines`를 썼으면 셸로 새도 초록이었다 | 착수 전에 코드를 읽고 `clip> paste` 줄 수로 고쳤다(실측 1). design도 함께 고쳤다 |
| 3 | **게이트의 `v`+`y`가 `가` 세 바이트가 아닐 수 있다.** 폭 2 글자 한 칸을 문자 선택하면 spacer가 딸려 올 수도 있다 | **길이를 하드코딩하지 않는다.** `clip> len=`에서 뽑아 `put`과 **같은지**만 본다 — 판정의 뜻("통째로 들어갔다")은 그대로이고 값에만 안 매인다 |
| 4 | **`commitHangul()`을 빼먹는다** | 검사 59가 그 자리만 본다. 빼먹으면 `committed "", want "한"`으로 실패한다 |
| 5 | **Step 4·5의 지울 줄이 서로 비슷하다.** 둘 다 `c.KEY_V`로 시작한다 | 하나는 `=> .{ .copy = .paste },` 한 줄이고 다른 하나는 `=> {` 블록이라 모양이 다르다. 그래도 커밋 전 `git diff \| grep '^-'`로 읽는다 |

## 이 milestone이 **안** 하는 것

| 안 하는 것 | 왜 |
|---|---|
| bracketed paste | CM 결정 9가 근거를 대고 비워 뒀다. FP가 안 뒤집는다 |
| 시스템 클립보드(OSC 52) | TARS의 클립보드는 `y`가 채우는 것 하나다 |
| 프롬프트 안의 커서 이동·편집 | 지금도 끝에서만 지운다. 붙여넣기가 그 규칙을 안 흔든다 |
