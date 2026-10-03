# FP-M0 Implementation Plan — `findPaste`가 클립보드의 첫 줄을 넣는다

> 실행 방식은 `CLAUDE.md`를 따른다. 설명 먼저 → 파일 편집은 사용자가
> → 명령 실행은 Claude Code가 → 결과를 상세히 설명. 승인 뒤의 `git commit`도
> Claude Code가 만든다. 체크박스는 진행 추적용이다.
>
> SH의 예외는 그 세션 한정이었다. 이 서브프로젝트는 다시 기본 규칙이고,
> 구현 파일 편집은 사용자가 한다.

Goal: `vt.zig`에 `findPaste`를 더해, 클립보드의 첫 줄이 검색어에
붙게 한다. 부르는 자리는 아직 `vt_test`뿐이다.

Architecture: 함수 하나를 더한다. 클립보드(`self.clip`)와
needle(`find_buf`)이 둘 다 `Screen`에 살므로 첫 줄 자르기가 `vt.zig`에
앉는다(FP design 결정 4). 넣는 일은 SH-M0이 만든 `findBytes`에 그대로
넘긴다 — 넘칠 때의 규칙을 두 자리에 적지 않는다.

Tech Stack: Zig · `terminal/src/vt.zig` · `terminal/src/vt_test.zig` ·
컨테이너 안의 `zig build test`

검증은 호스트에서 초 단위다. 게이트를 안 돌린다 — 아래 "게이트를 왜 안
돌리는가" 절이 근거다.

---

## 왜 이것부터인가

design의 결정 4·5다. 위의 둘(`input.zig`의 판단 한 자리, `main.zig`의 목적지
갈래)은 이 층이 먼저 서야 얹힌다.

지금 구멍이 어떻게 생겼는가. `Cmd+V`는 클립보드를 PTY로만 쓴다
(`main.zig:873 dumpPaste`). needle로 가는 길이 아예 없고, `findBytes`는
SH-M0이 바로 이 손님을 위해 만들어 놓고 아직 `vt_test`만 부르고 있다.

```
클립보드  "가나\n다라"   (13바이트 — 아래 실측 1)
                  ↑
                  여기서 자른다.  개행이 든 needle은 화면의 어떤 셀과도
                  안 맞아서 **"붙여넣었는데 못 찾음이 뜬다"**가 된다.
```

## 착수 전에 실행으로 확인한 것 — 다시 조사하지 말 것

실측 1. 여러 줄을 yank하면 개행이 정말 들어간다. `0A` 한 바이트이고 CR이
없다. 결정 5 전체가 이 전제 위에 서 있어서 임시 프로브로 쟀다
(2026-09-09, `vt_test`에 넣었다 되돌렸다).

```
PROBE: yanked len=13 text='가나
다라'
PROBE: bytes=EA B0 80 EB 82 98 0A EB 8B A4 EB 9D BC
```

줄 끝 공백은 트림된다. row 0이 20칸인데 `가나` 여섯 바이트 뒤에 바로
`0A`가 온다 — `copyYank`가 그 일을 이미 하므로 FP가 공백을 따로 다룰 필요가
없다. `vt_test`의 검사 7이 줄 선택에 대해 같은 것을 보고 있었고, 이 프로브가
여러 줄 문자 선택에 대해서도 참임을 보탰다.

실측 2. 프로브가 쓴 키 순서가 그대로 검사가 된다. `copyMove(dx, dy)`이고
`copyEnter` 뒤 커서는 셸 커서 자리(여기서는 row 2)다. 아래 검사 58의
`copyMove(0, -1)` 둘 → `copySelect(.char)` → `copyMove(0, 1)` →
`copyMove(1, 0)` 셋이 그 순서다.

실측 3. `copyYank`는 `copyExit`을 거쳐 `findCancel()`까지 부른다
(`vt.zig:646-652`, CM 결정 10). 그래서 검사 안에서 yank가 먼저이고
`copyEnter`·`findOpen`이 나중이다 — 순서를 뒤집으면 프롬프트가 닫혀서
`findPaste`가 아무 일도 안 하고, 증상이 "붙여넣기가 안 된다"라 원인에서
멀다. 실제 사람의 손 순서와도 같다(잡아서 y → `/` → `Cmd+V`).

## 파일 구조

| 파일 | 무엇 |
|---|---|
| `terminal/src/vt.zig` | `findPaste`를 더하기만 한다. `findErase` 바로 뒤에 앉힌다 — `findBytes`·`findChar`·`findErase`가 이미 그 순서로 모여 있다. 책임은 안 는다: 여전히 "검색어 버퍼를 관리한다" 하나다 |
| `terminal/src/vt_test.zig` | 검사 55~59를 함수 끝(검사 54 뒤, `PASS` 앞)에 잇는다 |

안 건드리는 파일 셋을 적어 둔다. `input.zig` · `main.zig` ·
`hangul/check.sh`는 한 글자도 안 바뀐다. 전부 FP-M1의 일이다.

## 착수 전 확인 — 기준선이 초록이다

이미 확인했다(2026-09-09, 위 프로브를 되돌린 뒤).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

마지막 줄이 `PASS`이고 `vt_test`의 마지막 검사가 54다
(`vt_test: Backspace가 UTF-8 한 글자를 지운다 OK`). 새 검사는 55부터다.

---

## Task 1: `findPaste` — 클립보드의 첫 줄을 needle에 넣는다

Files:
- Modify: `terminal/src/vt.zig` — `findErase` 바로 뒤에 함수 하나를 더한다
  (지우는 것이 없다)
- Test: `terminal/src/vt_test.zig:1710` 뒤 (검사 54의 print 뒤, `PASS` 앞)

- [ ] Step 1: 실패하는 검사를 넣는다 (검사 55~59)

`terminal/src/vt_test.zig`에서 이 줄을 찾는다 (1710행, 파일 끝 근처).

```zig
    std.debug.print("vt_test: Backspace가 UTF-8 한 글자를 지운다 OK\n", .{});
```

그 줄 바로 다음에 아래를 넣는다. (`std.debug.print("PASS\n", .{});`
보다 앞이다. 지우는 것은 없다.)

```zig

    // ── FP-M0: 클립보드의 첫 줄이 needle로 간다 ─────────────────────────

    // 검사 55. **대조군.** `um`은 한 번도 y를 안 눌렀다. 빈 클립보드에
    // 붙여넣기를 하면 0을 돌려주고 needle이 안 자란다.
    //
    // **이 검사가 대조군인 것에 뜻이 있다.** 아래 56~59가 전부 "무언가
    // 들어갔다"를 보므로, "아무것도 없을 때 아무 일도 안 한다"를 따로 안
    // 보면 `findPaste`가 늘 무언가를 넣는 구현도 전부 통과한다.
    if (um.findPaste() != 0) {
        std.debug.print("FAIL: 빈 클립보드가 needle에 무언가를 넣었다\n", .{});
        return error.FindPasteFromEmptyClip;
    }
    if (um.findNeedle().?.len != 0) {
        std.debug.print(
            "FAIL: 빈 클립보드 뒤 needle이 {d}바이트다(0이어야 한다)\n",
            .{um.findNeedle().?.len},
        );
        return error.FindPasteFromEmptyClip;
    }
    std.debug.print("vt_test: 빈 클립보드는 needle을 안 건드린다 OK\n", .{});

    // 화면을 새로 만든다. 두 줄이 필요하고 `um`은 "hello" 한 줄뿐이다.
    // `가나`·`다라`가 각각 폭 2 글자 둘이라 col 0~3을 먹는다.
    const pm = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer pm.deinit();
    pm.feed("가나\r\n다라\r\n");
    _ = try pm.cells(&buf);

    // 검사 56. **한 줄 클립보드가 통째로 들어간다.**
    //
    // **yank가 먼저이고 findOpen이 나중이다**(plan 실측 3). `copyYank`가
    // `copyExit` → `findCancel()`까지 부르므로 순서를 뒤집으면 프롬프트가
    // 닫힌 채로 붙여넣게 된다.
    pm.copyEnter();
    try pm.copyMove(0, -1); // row 2(셸 커서) → row 1 = `다라`
    try pm.copySelect(.line);
    const one = (try pm.copyYank()) orelse return error.NothingYanked;
    if (!std.mem.eql(u8, one, "다라")) {
        std.debug.print("FAIL: 한 줄 yank가 '{s}'를 줬다(다라여야 한다)\n", .{one});
        return error.WrongClipText;
    }
    pm.copyEnter();
    pm.findOpen();
    var put = pm.findPaste();
    if (put != 6) {
        std.debug.print("FAIL: 붙여넣기가 {d}바이트를 넣었다(6이어야 한다)\n", .{put});
        return error.FindPasteWrong;
    }
    un = pm.findNeedle() orelse return error.NoFindPrompt;
    if (!std.mem.eql(u8, un, "다라")) {
        std.debug.print("FAIL: 붙여넣은 뒤 needle이 '{s}'다(다라여야 한다)\n", .{un});
        return error.FindPasteWrong;
    }
    std.debug.print("vt_test: 클립보드 한 줄이 needle로 간다 OK ('{s}')\n", .{un});

    // 검사 57. **이미 친 글자 뒤에 붙는다.** 덮어쓰지 않는다.
    //
    // `findOpen()`이 `find_len`을 0으로 되돌리므로 여기서 다시 열어 비운다.
    pm.findOpen();
    pm.findBytes("가");
    put = pm.findPaste();
    if (put != 6) {
        std.debug.print("FAIL: 이어 붙일 때 {d}바이트를 넣었다(6이어야 한다)\n", .{put});
        return error.FindPasteWrong;
    }
    un = pm.findNeedle().?;
    if (!std.mem.eql(u8, un, "가다라")) {
        std.debug.print("FAIL: 이어 붙인 needle이 '{s}'다(가다라여야 한다)\n", .{un});
        return error.FindPasteWrong;
    }
    if (un.len != 9) {
        std.debug.print("FAIL: 이어 붙인 needle이 {d}바이트다(9여야 한다)\n", .{un.len});
        return error.FindPasteWrong;
    }
    std.debug.print("vt_test: 붙여넣기가 친 글자 뒤에 이어진다 OK ('{s}')\n", .{un});

    // 검사 58. **여러 줄이면 첫 줄만 넣는다**(FP design 결정 5).
    //
    // **이 검사가 이 Task의 본체다.** 개행이 든 needle은 화면의 어떤 셀과도
    // 안 맞으므로 "붙여넣었는데 못 찾음이 뜬다"가 되고, 그 증상은 조용하다.
    //
    // 키 순서는 plan 실측 2가 프로브로 확인한 것이다. row 0에 앵커를 두고
    // row 1의 col 3까지 끈다.
    pm.copyEnter();
    try pm.copyMove(0, -1);
    try pm.copyMove(0, -1); // row 0 = `가나`
    try pm.copySelect(.char);
    try pm.copyMove(0, 1); // row 1 = `다라`
    var mv: usize = 0;
    while (mv < 3) : (mv += 1) try pm.copyMove(1, 0);
    const many = (try pm.copyYank()) orelse return error.NothingYanked;
    // **클립보드 쪽을 먼저 못 박는다**(plan 실측 1). 여기가 초록이어야
    // 아래 판정이 "첫 줄만 넣었다"를 뜻한다 — 클립보드에 애초에 개행이
    // 없었다면 "잘랐다"와 "자를 것이 없었다"가 안 갈린다.
    if (many.len != 13) {
        std.debug.print("FAIL: 두 줄 yank가 {d}바이트다(13이어야 한다)\n", .{many.len});
        return error.WrongClipText;
    }
    if (many[6] != '\n') {
        std.debug.print("FAIL: 두 줄 yank의 7번째 바이트가 0x{X:0>2}다(0A여야 한다)\n", .{many[6]});
        return error.WrongClipText;
    }
    pm.copyEnter();
    pm.findOpen();
    put = pm.findPaste();
    if (put != 6) {
        std.debug.print("FAIL: 두 줄에서 {d}바이트를 넣었다(첫 줄 6이어야 한다)\n", .{put});
        return error.FindPasteMultiline;
    }
    un = pm.findNeedle().?;
    if (!std.mem.eql(u8, un, "가나")) {
        std.debug.print("FAIL: 첫 줄만 넣었어야 하는데 needle이 '{s}'다\n", .{un});
        return error.FindPasteMultiline;
    }
    std.debug.print("vt_test: 여러 줄은 첫 줄만 들어간다 OK ('{s}')\n", .{un});

    // 검사 59. **자리가 모자라면 하나도 안 넣는다.** 규칙이 `findBytes`
    // 한 자리에 있다는 것을 붙여넣기 쪽에서도 못 박는다(SH design 결정 7).
    //
    // 126 + 6 = 132 > 128이라 통째로 거절된다. 바이트 단위로 채웠다면 두
    // 바이트만 들어가 `가`가 반만 남는다.
    pm.findOpen();
    var pad2: usize = 0;
    while (pad2 < 126) : (pad2 += 1) pm.findChar('z');
    put = pm.findPaste();
    if (put != 0) {
        std.debug.print("FAIL: 자리가 둘뿐인데 {d}바이트를 넣었다(0이어야 한다)\n", .{put});
        return error.FindPasteOverflow;
    }
    un = pm.findNeedle().?;
    if (un.len != 126) {
        std.debug.print("FAIL: 거절 뒤 needle이 {d}바이트다(126이어야 한다)\n", .{un.len});
        return error.FindPasteOverflow;
    }
    std.debug.print("vt_test: 자리가 모자라면 붙여넣기를 통째로 거절한다 OK\n", .{});
```

이름 셋에 뜻이 있다. `un`은 SH-M0이 만든 것을 다시 선언하지 않고 그대로
쓴다(`var un`이 1616행에 이미 있다). `pad2`는 1634행의 `pad`와 다른 이름이어야
한다. `pm`·`put`·`one`·`many`·`mv`도 이 함수 안에 없는 이름인지 `rg`로 세어서
확인했다 — Zig는 이름 가리기를 막고, 그것이 SH-M1 실측 1이 한 Task에서 두
번 밟은 함정이다.

- [ ] Step 2: 돌려서 실패를 확인한다

Claude Code가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

기대: 컴파일 에러다.

```
error: no member named 'findPaste' in struct 'vt.Screen'
```

런타임 실패가 아니라 컴파일 실패인 것이 정상이다 — 부를 함수가 아직
없다. 초록이 나오면 편집이 안 들어간 것이므로 Step 1로 돌아간다.

- [ ] Step 3: `findPaste`를 만든다

`terminal/src/vt.zig`에서 `pub fn findErase`를 이름으로 찾는다. 그 함수의
닫는 `}` 바로 다음, `/// 프롬프트만 닫는다`(= `findCancel`) 앞에
아래를 넣는다. 지우는 것은 없다.

```zig

    /// `Cmd+V`. 클립보드의 **첫 줄**을 needle에 붙이고, 넣은 바이트 수를
    /// 돌려준다(FP design 결정 4·5).
    ///
    /// **개행에서 자르는 것이 이 함수의 본체다.** 화면 셀에는 개행이 없으므로
    /// 개행이 든 needle은 **영영 안 맞는다** — 증상이 "붙여넣었는데 못 찾음이
    /// 뜬다"라 조용하다. 셸 쪽 `dumpPaste`는 개행이 곧 실행이 되는 것을
    /// 감수했지만(CM design 결정 9), 검색은 감수할 수 있는 종류가 아니다.
    /// 셸에서는 잘못 붙은 것이 화면에 보이고 검색에서는 안 보인다.
    ///
    /// **줄 끝 공백은 여기서 안 다룬다.** `copyYank`가 이미 트림한다 —
    /// 두 줄을 잡으면 `가나\n다라` 열세 바이트가 나오고 `가나` 뒤에 바로
    /// `0A`가 온다(FP-M0 실측 1).
    ///
    /// **넣는 일은 `findBytes`에 그대로 넘긴다.** 통째로 받거나 거절하는
    /// 규칙도, 프롬프트가 닫혀 있으면 아무 일도 안 하는 규칙도 그쪽 한
    /// 자리에만 적힌다(SH design 결정 7).
    ///
    /// 돌려주는 수를 `main.zig`가 `put=`으로 찍는다. **`clip=`과 함께 한 줄에
    /// 찍는 것이 판정을 만든다**(FP design 결정 6) — 0 하나만으로는 "클립보드가
    /// 비었다"와 "너무 길어 거절됐다"가 안 갈린다.
    pub fn findPaste(self: *Screen) usize {
        const text = self.clip orelse return 0;
        const end = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
        const before = self.find_len;
        self.findBytes(text[0..end]);
        return self.find_len - before;
    }
```

- [ ] Step 4: 돌려서 통과를 확인한다

Claude Code가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

기대: 새 줄 다섯이 뜨고 마지막이 `PASS`다.

```
vt_test: 빈 클립보드는 needle을 안 건드린다 OK
vt_test: 클립보드 한 줄이 needle로 간다 OK ('다라')
vt_test: 붙여넣기가 친 글자 뒤에 이어진다 OK ('가다라')
vt_test: 여러 줄은 첫 줄만 들어간다 OK ('가나')
vt_test: 자리가 모자라면 붙여넣기를 통째로 거절한다 OK
PASS
```

옛 검사 다섯이 그대로 통과하는 것을 함께 본다 — 검사 10
(`clipboard()`가 마지막 y의 결과를 들고 있다) · 검사 52·53·54(SH-M0의
needle 검사 셋). 이 Task는 더하기만 하므로 하나도 안 바뀌는 것이
기대값이고, 바뀌었다면 편집이 지울 것을 지운 것이다.

- [ ] Step 5: commit — Claude Code가 만든다.

`git diff --stat`으로 지운 줄이 0인지 먼저 본다 (이 Task는 더하기만
한다). 그 뒤:

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Put the first line of the clipboard into the search needle"
```

---

## Task 2: HANDOFF를 FP-M0 시점으로 옮긴다

Files:
- Modify: `HANDOFF.md`

- [ ] Step 1: 넣을 것을 사용자가 넣는다

Claude Code가 제시하고 사용자가 넣는다. 담을 것 넷: FP가 시작됐다는 것 ·
design과 이 plan의 자리 · 위 실측 셋 · 다음이 FP-M1이라는 것.

- [ ] Step 2: commit — Claude Code가 만든다.

```bash
git add HANDOFF.md
git commit -m "Close out FP-M0 with a paste path into the search needle"
```

---

## 게이트를 왜 안 돌리는가

이 milestone은 부팅하는 바이너리의 동작을 한 글자도 안 바꾼다.
`findPaste`를 부르는 자리가 `vt_test`뿐이고, 지운 줄이 하나도 없다.

SH-M0은 게이트를 한 번 돌렸는데 전제가 달랐다 — 그쪽은 `findChar`를
껍데기로 바꾸고 `findErase`의 몸을 갈아서, "옛 검사가 그대로 통과하는가"를
볼 이유가 있었다. FP-M0에는 갈아 낀 것이 없다.

FP-M1의 Task 1이 그 자리다. 거기서 `input.zig`의 두 줄을 지우므로
`copy/check.sh` 한 체인을 돌리고, Task 4에서 전체 게이트를 돌린다.

## 이 milestone이 안 하는 것

셋 다 FP-M1의 일이고, 지금 손대면 검증할 길이 없다.

| 안 하는 것 | 어디로 |
|---|---|
| `Cmd+V`의 판단을 1.35번 단계 한 자리로 모은다 | FP-M1 Task 1 |
| `main.zig`의 목적지 갈래와 `dumpFindPaste` | FP-M1 Task 2 |
| `hangul/check.sh` 검사 20 | FP-M1 Task 3 |

그래서 이 milestone이 끝나도 사람이 검색창에 붙여넣을 수는 없다.
`findPaste`를 부르는 자리가 `vt_test`뿐이다 — 의도된 상태이고, 그것이
"호스트에서 초 단위로 답한다"는 이 milestone의 값과 맞바꾼 것이다. SH-M0이
같은 모양이었다.

## 위험 넷

| # | 위험 | 처방 |
|---|---|---|
| 1 | 검사에서 yank와 `findOpen`의 순서를 뒤집는다. `copyYank`가 `findCancel()`까지 부르므로 프롬프트가 닫힌 채 붙여넣게 되고, 증상이 "붙여넣기가 안 된다"라 원인에서 멀다 | plan이 순서를 준다(실측 3). 검사 56이 그 자리를 지나므로 뒤집으면 `put != 6`으로 즉시 빨갛다 |
| 2 | 이름 가리기. `un`·`pad`가 같은 함수 위쪽에 이미 있다 | `un`은 재선언하지 않고 그대로 쓰고, `pad2`·`pm`·`put`·`one`·`many`·`mv`는 `rg`로 세어서 비어 있음을 확인했다. 컴파일 에러라 조용하지 않다 |
| 3 | `findPaste`가 `find_open`을 안 봐서 닫힌 프롬프트에 쓴다 | 안 본다. `findBytes`가 자기 첫 줄에서 본다 — 규칙이 한 자리라는 것이 결정 4의 값이고, 검사 55가 그 경로를 지난다 |
| 4 | 경계 검사의 산수가 틀려 아무것도 안 보고 통과한다 | 126 + 6 = 132 > 128이라 거절, needle은 126에 머문다. 검사 59가 두 값을 둘 다 확인한다(넣은 수 0과 남은 길이 126) |
