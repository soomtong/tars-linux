# SH-M0 Implementation Plan — needle이 UTF-8을 안다

> 실행 방식은 `CLAUDE.md`를 따른다. 설명 먼저 → 파일 편집은 사용자가
> → 명령 실행은 Claude Code가 → 결과를 상세히 설명. 승인 뒤의 `git commit`도
> Claude Code가 만든다. 체크박스는 진행 추적용이다.

Goal: `find_buf`가 UTF-8을 글자 단위로 다루게 해서, 검색어에 한글이
들어와도 음절이 반으로 잘리지 않게 한다.

Architecture: `vt.zig`에 함수 하나를 더하고(`findBytes` — 통째로 받거나
거절) 하나를 고친다(`findErase` — UTF-8 한 글자를 지운다). `findChar`는
`findBytes`의 껍데기가 되어 넘칠 때의 규칙이 한 자리에만 남는다. 칠 길은
아직 안 만든다 — SH-M1의 일이다.

Tech Stack: Zig · `terminal/src/vt.zig` · `terminal/src/vt_test.zig` ·
컨테이너 안의 `zig build test`

검증은 호스트에서 초 단위다. 18분짜리 게이트에 안 간다 — 이 milestone이
건드리는 것은 프레임버퍼도 시리얼도 아니고 버퍼 하나다.

---

## 왜 이것부터인가

design의 "막혀 있는 것 넷" 중 아래 두 층이다. 위의 둘(`input.zig`의 find
분기, `main.zig`의 `drawPrompt`)은 이 층이 먼저 서야 얹힌다.

지금 구멍이 어떻게 생겼는가. `findChar`는 바이트 하나를 넣고 버퍼가 차면
조용히 버린다. `findErase`는 `find_len -= 1`이다. 둘 다 "한 바이트 = 한 글자"를
전제하고, 그 전제는 ASCII에서만 참이다.

```
`가` = EA B0 80  (UTF-8 세 바이트)

findErase 한 번  →  EA B0        ← 두 바이트짜리 쓰레기
```

증상이 조용한 것이 이 구멍의 성질이다. 깨진 바이트열은 화면의 어떤 셀과도
안 맞으므로 "지웠는데 못 찾는다"로 나타나고, 사람은 검색어가 깨진 줄 모른다.

## 파일 구조

| 파일 | 무엇 |
|---|---|
| `terminal/src/vt.zig` | `findBytes` 새로 · `findChar`를 껍데기로 · `findErase`를 고침. 줄 수는 늘지만 책임은 안 는다 — 여전히 "검색어 버퍼를 관리한다" 하나다 |
| `terminal/src/vt_test.zig` | 검사 52·53·54를 함수 끝(검사 51 뒤, `PASS` 앞)에 잇는다 |

안 건드리는 파일 둘을 적어 둔다. `main.zig:1049`의 `screen.findChar(ch)`와
`main.zig:1053`의 `screen.findErase()`는 한 글자도 안 바뀐다 —
`findChar`의 시그니처를 그대로 두는 것이 그 이유이고, 그래서 이 milestone에
회귀 위험이 거의 없다.

## 착수 전 확인 — 기준선이 초록이다

이미 확인했다(2026-09-09).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

마지막 줄이 `PASS`이고 `vt_test`의 마지막 검사가 51이다
(`vt_test: copy 커서도 한글 위에서 두 칸이다 OK`). 새 검사는 52부터다.

---

## Task 1: `findBytes` — 통째로 받거나 거절한다

Files:
- Modify: `terminal/src/vt.zig:691-701` (`findChar`)
- Test: `terminal/src/vt_test.zig` — 함수 끝(검사 51의 print 뒤, `PASS` 앞)

- [ ] Step 1: 실패하는 검사를 넣는다 (검사 52·53)

`terminal/src/vt_test.zig`에서 이 줄을 찾는다 (파일 끝 근처).

```zig
    std.debug.print("vt_test: copy 커서도 한글 위에서 두 칸이다 OK\n", .{});
```

그 줄 바로 다음에 아래를 넣는다. (`std.debug.print("PASS\n", .{});`
보다 앞이다.)

```zig

    // ── SH-M0: needle이 UTF-8을 안다 ────────────────────────────────────
    //
    // **화면을 따로 만든다**(CM-M1 이래의 규율). 여기서 보는 것은 버퍼뿐이라
    // 20×5로 충분하다. `copyEnter` 앞에 feed·cells가 있는 것은 검사 18과 같은
    // 이유다 — `findOpen()`은 copy mode 안에서만 열린다.
    const um = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer um.deinit();
    um.feed("hello\r\n");
    _ = try um.cells(&buf);
    um.copyEnter();
    um.findOpen();

    // 검사 52. **음절 하나가 통째로 들어간다**(SH design 결정 7).
    // `가`는 EA B0 80, `나`는 EB 82 98이라 여섯 바이트여야 한다.
    um.findBytes("가");
    um.findBytes("나");
    var un = um.findNeedle() orelse return error.NoFindPrompt;
    if (!std.mem.eql(u8, un, "가나")) {
        std.debug.print("FAIL: 프롬프트가 '{s}'를 들고 있다(가나여야 한다)\n", .{un});
        return error.FindNeedleWrong;
    }
    if (un.len != 6) {
        std.debug.print("FAIL: needle이 {d}바이트다(6이어야 한다)\n", .{un.len});
        return error.FindNeedleWrong;
    }
    std.debug.print("vt_test: 프롬프트가 한글 음절을 통째로 받는다 OK ('{s}')\n", .{un});

    // 검사 53. **자리가 모자라면 하나도 안 넣는다**(SH design 결정 7).
    //
    // **이 검사가 이 Task의 본체다.** "들어가는 만큼 넣는다"는 구현도 검사
    // 52를 통과하고, 그 구현은 경계에서 음절을 반만 남긴다. 깨진 바이트열은
    // 화면의 어떤 셀과도 안 맞아 **"검색이 조용히 안 맞는다"**가 된다.
    //
    // 지금 6바이트다. 120을 더해 126으로 만든다.
    var pad: usize = 0;
    while (pad < 120) : (pad += 1) um.findChar('z');
    un = um.findNeedle().?;
    if (un.len != 126) {
        std.debug.print("FAIL: 채운 뒤 needle이 {d}바이트다(126이어야 한다)\n", .{un.len});
        return error.FindNeedleWrong;
    }
    // 126 + 3 > 128이므로 `다`는 통째로 거절된다. 바이트 단위였으면 두
    // 바이트만 들어가 128이 되고 꼬리가 깨진다.
    um.findBytes("다");
    un = um.findNeedle().?;
    if (un.len != 126) {
        std.debug.print(
            "FAIL: 자리가 둘뿐인데 needle이 {d}바이트가 됐다(126이어야 한다)\n",
            .{un.len},
        );
        return error.FindNeedleOverflow;
    }
    // **그래도 ASCII 둘은 들어간다.** 거절이 "버퍼를 잠근다"가 아니라 "이
    // 덩어리가 안 맞는다"라는 뜻임을 못 박는다.
    um.findChar('y');
    um.findChar('y');
    un = um.findNeedle().?;
    if (un.len != 128) {
        std.debug.print("FAIL: ASCII 둘 뒤 needle이 {d}바이트다(128이어야 한다)\n", .{un.len});
        return error.FindNeedleWrong;
    }
    // 이제 꽉 찼다. 한 바이트도 더 안 들어간다(검사 20이 보던 것과 같은 규칙).
    um.findChar('y');
    if (um.findNeedle().?.len != 128) {
        std.debug.print("FAIL: 꽉 찬 needle이 더 자랐다\n", .{});
        return error.FindNeedleOverflow;
    }
    std.debug.print("vt_test: 자리가 모자라면 음절을 통째로 거절한다 OK\n", .{});
```

변수 이름이 `needle`이 아니라 `un`인 것에 뜻이 있다. 같은 함수 안 위쪽에
`var needle`이 이미 있고 Zig는 이름 가리기를 막는다(HI-M1 실측 8 ·
SP-M0 실측 9). `needle`로 쓰면 컴파일 에러다.

- [ ] Step 2: 돌려서 실패를 확인한다

Claude Code가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

기대: 컴파일 에러다.

```
error: no member named 'findBytes' in struct 'vt.Screen'
```

런타임 실패가 아니라 컴파일 실패인 것이 정상이다 — 부를 함수가 아직
없다. `findBytes`가 이미 있는데 이 단계가 초록이면 편집이 안 들어간 것이므로
Step 1로 돌아간다.

- [ ] Step 3: `findBytes`를 만들고 `findChar`를 껍데기로 바꾼다

`terminal/src/vt.zig`에서 이 열한 줄을 지운다 (691~701행).

```zig
    /// 프롬프트에 글자 하나. **버퍼가 차면 조용히 버린다.**
    ///
    /// 버리는 것을 로그로 알리지 않는 이유는 128자에 닿는 상황이 실전에
    /// 없기 때문이다. 닿았다면 그것은 사람이 친 것이 아니라 키가 붙어 있는
    /// 것이고, 그 증상은 화면에서 바로 보인다.
    pub fn findChar(self: *Screen, ch: u8) void {
        if (!self.find_open) return;
        if (self.find_len >= self.find_buf.len) return;
        self.find_buf[self.find_len] = ch;
        self.find_len += 1;
    }
```

그 자리에 이것을 넣는다.

```zig
    /// 프롬프트에 바이트 여럿을 **통째로** 넣는다(SH design 결정 7).
    ///
    /// **다 들어가거나 하나도 안 들어간다.** 바이트 단위로 채우다가 자리가
    /// 떨어지면 UTF-8 한 글자가 반만 남는데, 깨진 바이트열은 화면의 어떤
    /// 셀과도 안 맞으므로 **검색이 조용히 안 맞는다.** 버퍼가 128바이트라
    /// 손으로 쳐서는 사실상 안 닿는 경계지만(한글 42자), 붙여넣기가 들어오면
    /// yank한 줄 하나가 한 번에 닿는다.
    ///
    /// 버리는 것을 로그로 알리지 않는 이유는 예전 `findChar`의 주석과 같다 —
    /// 128자에 닿는 상황은 사람이 친 것이 아니라 키가 붙어 있는 것이고, 그
    /// 증상은 화면에서 바로 보인다.
    pub fn findBytes(self: *Screen, bytes: []const u8) void {
        if (!self.find_open) return;
        if (self.find_len + bytes.len > self.find_buf.len) return;
        @memcpy(self.find_buf[self.find_len .. self.find_len + bytes.len], bytes);
        self.find_len += bytes.len;
    }

    /// 프롬프트에 글자 하나. **ASCII 한 바이트가 곧 한 글자다.**
    ///
    /// `findBytes`의 껍데기다 — 넘칠 때의 규칙을 두 자리에 적지 않기 위함이고,
    /// 그래서 `main.zig`의 `find_char` 갈래는 한 글자도 안 바뀐다.
    pub fn findChar(self: *Screen, ch: u8) void {
        const one = [_]u8{ch};
        self.findBytes(&one);
    }
```

- [ ] Step 4: 돌려서 통과를 확인한다

Claude Code가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

기대: 새 줄 둘이 뜨고 마지막이 `PASS`다.

```
vt_test: 프롬프트가 한글 음절을 통째로 받는다 OK ('가나')
vt_test: 자리가 모자라면 음절을 통째로 거절한다 OK
PASS
```

옛 검사 20(`검색어가 128자에서 멈춘다`)이 그대로 통과하는 것을 함께
본다. `findChar`가 껍데기가 됐는데 뜻이 안 바뀌었다는 증거이고, 안 보이면
껍데기가 규칙을 바꾼 것이다.

- [ ] Step 5: commit — Claude Code가 만든다.

`git diff --stat`으로 더한 줄과 지운 줄을 먼저 세고, 지운 것이 위의 열한 줄이
맞는지 `git diff | grep '^-'`로 읽는다 (CC-M0의 규율). 그 뒤:

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Let the search needle take a whole UTF-8 character at once"
```

---

## Task 2: `findErase` — UTF-8 한 글자를 지운다

Files:
- Modify: `terminal/src/vt.zig` — `findErase` (줄 번호를 안 적는다. Task 1이
  `findChar` 자리에 스무 줄 남짓을 넣어 아래가 전부 밀렸다. `findErase`를
  이름으로 찾는다 — `findBytes`·`findChar` 바로 다음이다)
- Test: `terminal/src/vt_test.zig` — Task 1이 넣은 블록 끝에 이어서

- [ ] Step 1: 실패하는 검사를 넣는다 (검사 54)

`terminal/src/vt_test.zig`에서 Task 1이 넣은 마지막 줄을 찾는다.

```zig
    std.debug.print("vt_test: 자리가 모자라면 음절을 통째로 거절한다 OK\n", .{});
```

그 줄 바로 다음에 아래를 넣는다.

```zig

    // 검사 54. **Backspace가 음절을 통째로 지운다**(SH design 결정 8).
    //
    // `findOpen()`이 `find_len`을 0으로 되돌리므로 꽉 찬 버퍼를 여기서 비운다.
    um.findOpen();
    um.findBytes("가");
    um.findBytes("나");
    um.findErase();
    un = um.findNeedle().?;
    if (!std.mem.eql(u8, un, "가")) {
        std.debug.print("FAIL: Backspace가 '{s}'를 남겼다(가여야 한다)\n", .{un});
        return error.FindEraseWrong;
    }
    // **바이트 수를 따로 본다.** 바이트 단위로 지우면 6 → 5가 되는데, 그
    // 다섯 바이트를 `{s}`로 찍으면 눈에는 `가` 뒤에 깨진 두 바이트가 붙어
    // 있는 것으로 보인다 — 위의 eql이 이미 그것을 잡지만, **틀린 값이
    // 몇인지**를 로그가 말해 주는 편이 고치는 자리를 좁힌다.
    if (un.len != 3) {
        std.debug.print("FAIL: Backspace 뒤 needle이 {d}바이트다(3이어야 한다)\n", .{un.len});
        return error.FindEraseWrong;
    }
    // **ASCII는 뜻이 안 바뀐다.** 한 바이트가 곧 한 글자다.
    um.findChar('z');
    um.findErase();
    un = um.findNeedle().?;
    if (!std.mem.eql(u8, un, "가")) {
        std.debug.print("FAIL: ASCII Backspace가 '{s}'를 남겼다(가여야 한다)\n", .{un});
        return error.FindEraseWrong;
    }
    // **빈 프롬프트에서는 여전히 아무 일도 안 한다**(CN-M1 plan 결정 2).
    // 검사 19가 ASCII로 보던 것을 여기서 한글 뒤에도 확인한다 — 앞으로
    // 걸어가는 루프가 0에서 멈추는지가 이 줄이 보는 것이다.
    um.findErase();
    um.findErase();
    un = um.findNeedle() orelse {
        std.debug.print("FAIL: Backspace가 빈 프롬프트를 닫았다\n", .{});
        return error.FindEraseClosedPrompt;
    };
    if (un.len != 0) {
        std.debug.print("FAIL: 프롬프트가 비어야 하는데 {d}바이트다\n", .{un.len});
        return error.FindEraseWrong;
    }
    std.debug.print("vt_test: Backspace가 UTF-8 한 글자를 지운다 OK\n", .{});
```

- [ ] Step 2: 돌려서 실패를 확인한다

Claude Code가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

기대: 런타임 실패다. 이번에는 부를 함수가 다 있으므로 컴파일은 된다.

```
FAIL: Backspace가 '가▒▒'를 남겼다(가여야 한다)
```

깨진 두 바이트가 터미널에서 어떻게 보이는지는 폰트에 딸린 문제라 `▒`가
아닐 수 있다. 판정은 그 줄이 떴다는 것이고, 안 뜨고 초록이면 편집이 안
들어간 것이므로 Step 1로 돌아간다.

- [ ] Step 3: `findErase`를 고친다

`terminal/src/vt.zig`에서 이 아홉 줄을 지운다. Task 1 뒤라 줄 번호가
밀렸으므로 `pub fn findErase`를 이름으로 찾는다.

```zig
    /// Backspace. **빈 프롬프트에서는 아무 일도 안 한다**(CN-M1 plan 결정 2).
    ///
    /// vim은 여기서 프롬프트를 닫지만 우리는 안 닫는다. 닫으면 Esc와 뜻이
    /// 겹치고, 지우려고 연타하던 사람이 마지막 한 번에 프롬프트를 잃는다.
    pub fn findErase(self: *Screen) void {
        if (!self.find_open) return;
        if (self.find_len == 0) return;
        self.find_len -= 1;
    }
```

그 자리에 이것을 넣는다.

```zig
    /// Backspace. **UTF-8 한 글자를 지운다**(SH design 결정 8).
    ///
    /// 바이트 하나만 줄이면 `가`(EA B0 80)가 두 바이트짜리 쓰레기가 되고, 그
    /// needle은 화면의 어떤 셀과도 안 맞는다 — **증상이 "지웠는데 못
    /// 찾는다"라 조용하다.**
    ///
    /// 이어지는 바이트(`0b10xxxxxx`)를 앞으로 건너뛰어 시작 바이트를 찾는다.
    /// **0까지 가면 그대로 비운다** — 시작 바이트가 없는 버퍼는 `findBytes`가
    /// 만들지 않지만, 여기서 멈추지 못해 아래로 도는 것이 더 나쁘다.
    ///
    /// **빈 프롬프트에서는 아무 일도 안 한다**(CN-M1 plan 결정 2). vim은
    /// 여기서 프롬프트를 닫지만 우리는 안 닫는다. 닫으면 Esc와 뜻이 겹치고,
    /// 지우려고 연타하던 사람이 마지막 한 번에 프롬프트를 잃는다.
    pub fn findErase(self: *Screen) void {
        if (!self.find_open) return;
        if (self.find_len == 0) return;
        var i = self.find_len - 1;
        while (i > 0 and (self.find_buf[i] & 0xC0) == 0x80) i -= 1;
        self.find_len = i;
    }
```

- [ ] Step 4: 돌려서 통과를 확인한다

Claude Code가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build test'
```

기대: 새 줄이 하나 더 뜨고 마지막이 `PASS`다.

```
vt_test: 프롬프트가 한글 음절을 통째로 받는다 OK ('가나')
vt_test: 자리가 모자라면 음절을 통째로 거절한다 OK
vt_test: Backspace가 UTF-8 한 글자를 지운다 OK
PASS
```

옛 검사 18·19가 그대로 통과하는 것을 함께 본다 (`프롬프트가 글자를 받고
지운다` · `빈 프롬프트의 Backspace가 안 닫는다`). ASCII의 뜻이 한 글자도 안
바뀌었다는 증거다.

- [ ] Step 5: commit — Claude Code가 만든다.

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Erase a whole UTF-8 character from the search needle"
```

---

## Task 3: 게이트를 한 번 돌려 회귀가 없음을 본다

Files: 없다. 확인만 한다.

왜 이 Task가 있는가. SH-M0은 게이트가 보는 층을 안 건드리므로 아무것도
안 바뀌는 것이 기대값이다. 그런데 `findChar`가 껍데기가 됐고
`findErase`의 몸이 바뀌었으므로, `copy/check.sh`의 검색 검사들이 그대로
초록인지를 한 번은 봐야 한다. "안 바뀔 것이다"와 "안 바뀌었다"는 다르다.

- [ ] Step 1: 게이트를 돌린다

Claude Code가 실행한다. 아홉 체인 3/3이라 18분쯤 걸린다.

```bash
time ./check.sh
```

기대: `TARS check PASS: all chains 3/3 consecutive runs succeeded`.

시간은 직전 기준선이 18분 32.80초다(IS-M1). 이 milestone은 부팅하는
바이너리를 사실상 안 바꾸므로 잡음 범위 안이어야 한다 — 같은 세션이 아닌
다른 날의 측정이라 ±3분까지는 신호가 아니다(HI-M2 실측 11).

- [ ] Step 2: 결과를 HANDOFF에 적는다

`HANDOFF.md`를 SH-M0 시점으로 고친다. Claude Code가 넣을 것을 제시하고
사용자가 넣는다. 그 뒤 Claude Code가 커밋한다.

```bash
git add HANDOFF.md
git commit -m "Close out SH-M0 with a UTF-8-aware search needle"
```

---

## 이 milestone이 안 하는 것

셋 다 다음 milestone의 일이고, 지금 손대면 검증할 길이 없다.

| 안 하는 것 | 어디로 |
|---|---|
| find 분기가 한글 층을 부른다 | SH-M1 |
| `commit_buf`를 여덟 바이트로 · `readKeys`의 목적지 갈래 | SH-M1 |
| `drawPrompt`의 UTF-8 · preedit 반전 | SH-M2 |

그래서 이 milestone이 끝나도 사람이 검색창에 한글을 칠 수는 없다.
`findBytes`를 부르는 자리가 `vt_test`뿐이다 — 의도된 상태이고, 그것이
"호스트에서 초 단위로 답한다"는 이 milestone의 값과 맞바꾼 것이다.

## 위험

| # | 위험 | 처방 |
|---|---|---|
| 1 | Task 1 Step 1에서 변수 이름을 `needle`로 쓴다. 같은 함수 위쪽에 이미 있고 Zig는 이름 가리기를 막는다 | plan이 `un`으로 준다. 컴파일 에러라 조용하지 않다 |
| 2 | 지울 줄만 주고 위치가 어긋난다. `findChar`와 `findErase`가 나란히 있고 둘 다 `if (!self.find_open) return;`로 시작한다 | 지울 것을 주석까지 통째로 준다. 커밋 전 `git diff \| grep '^-'`로 읽는다(IS-M0 실측 4가 똑같이 생긴 줄에서 겪은 것) |
| 3 | `findErase`의 while이 시작 바이트를 못 찾고 아래로 돈다 | `i > 0` 조건이 막는다. 검사 54의 마지막 갈래(빈 프롬프트에서 두 번 더)가 그 자리를 본다 |
| 4 | 경계 검사의 산수가 틀려 아무것도 안 보고 통과한다 | 6 + 120 = 126, 126 + 3 = 129 > 128이라 거절, 126 + 1 + 1 = 128이라 수용. 검사가 세 값을 전부 확인한다 |
