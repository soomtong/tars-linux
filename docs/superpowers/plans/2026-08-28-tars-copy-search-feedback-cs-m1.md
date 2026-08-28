# TARS Copy Search Feedback CS-M1 Implementation Plan

> **협업 방식(이 저장소 규칙):** 구현 파일 편집은 **사용자**가 한다. 각 Step의
> "넣을 것"/"지울 것"을 그대로 넣으면 된다. 빌드·검사·QEMU·게이트 실행과
> git commit은 **Claude**가 한다.

**Goal:** 검색이 **말을 하게 만든다.** 못 찾았을 때 화면 아랫줄에
`/needle: not found`를 쓰고, 지난 검색어를 기억해 빈 Enter로 다시 돌린다.

**Design doc:** `docs/superpowers/specs/2026-08-28-tars-copy-search-feedback-design.md`
(결정 8·9가 내용을 이미 정해 두었다)

**Architecture:** 상태를 둘 더한다 — `find_last`(마지막으로 확정한 검색어)와
`find_missed`(마지막 검색이 아무것도 못 찾았는가). `findSubmit`이 둘 다 정하고,
이미 있는 오버레이 한 줄이 `find_missed`를 읽어 두 갈래로 갈린다.
**`drawPrompt`도 `cells()`도 안 바뀐다.**

**Tech Stack:** Zig 0.16, libghostty-vt(`search.Screen`), QEMU monitor

---

## 이 milestone은 CS-M0과 겹치지 않는다

design의 Milestone 표가 그 선을 이렇게 적었다.

> **둘이 건드리는 코드 경로가 겹치지 않는 것이 이 선의 근거다.** M0이 깨지면
> 색이 틀리고 M1이 깨지면 글자가 틀린다 — 섞이지 않는다.

그래서 이 milestone은 **`cells()`를 한 줄도 안 건드린다.** `hl_spans`·`RowSpan`·
`MATCH_BG`·`findSpans`를 읽지도 않는다. 반대로 CS-M0은 오버레이 문자열을 안
건드렸다.

**키도 한 개 안 더한다.** `input.zig`도 `input_test.zig`도 안 건드린다 — 빈
Enter는 이미 `.find_submit`으로 도착하고 있다(`input.zig:591~594`가 버퍼 내용을
안 보고 Enter를 그대로 넘긴다). CS-M0과 같은 자리이고, HANDOFF의 "서브프로젝트를
넘어 유효한 실측" 1·2·3이 말하는 함정이 이번에도 통째로 해당되지 않는다.

## 착수 전에 이미 확정된 사실 — 다시 조사하지 않는다

### design doc이 정해 둔 것

**결정 8(검색 기록).** `find_last: [128]u8` + `find_last_len`. `find_buf`와 같은
고정 크기이고 같은 이유다. 빈 Enter가 그것을 다시 쓴다. **성공·실패와 무관하게
비지 않은 검색어는 전부 남긴다.** `/`는 **언제나 빈 프롬프트로 연다.**
`copyExit`이 `find`·`find_matches`·`find_buf`는 지우고 **`find_last`만 남긴다.**

**결정 9("못 찾음" 메시지).** 상태줄을 만들지 않고 이미 있는 오버레이 한 줄을
쓴다. `findSubmit`이 `matches == 0`이면 플래그를 켜고, `main.zig`가 copy 명령을
처리하기 **직전 한 자리**에서 끈다. `?Prompt`를 만드는 자리가 두 갈래가 된다.
**`drawPrompt`는 안 바뀐다.**

### 이 plan을 쓰면서 우리 소스에서 확인한 것 여섯

**1. 빈 Enter는 이미 `findSubmit`까지 도착한다.** `input.zig:591~594`의 `.find`
분기가 `KEY_ENTER`를 버퍼 내용과 무관하게 `.find_submit`으로 바꾼다. 지금
`vt.zig:575`의 `if (len == 0) return none;` 한 줄이 그것을 버리고 있을 뿐이다.

**2. `findNeedle()`은 프롬프트가 닫히면 null이다**(`vt.zig:548~551`). 그래서
"못 찾았다" 메시지에 쓸 글자는 **`find_buf`에서 못 온다** — 그때는 이미 닫혀
있다. `find_last`가 그 글자의 출처가 되는 것이 결정 8과 9가 맞물리는 자리다.

**3. 오버레이 문자열을 만드는 자리는 `main.zig:751~764` 하나다.** `prompt_buf`가
`[129]u8`이고 그 129는 `/` 하나 + needle 128이다. `: not found` 열한 자를 더하면
**140**이 필요하다.

**4. `dumpStyles`가 덮인 줄을 통째로 건너뛴다**(`main.zig:785`의
`if (prompt != null) rows - 1 else null`). 그래서 **오버레이 내용은 `style>`로도
못 본다.** `screen>`에 안 나오는 것은 CN-M1이 이미 적어 두었고, 이 둘을 합치면
게이트가 메시지를 볼 창구가 **하나도 없다** — Task 3이 그 창구를 만든다.

**5. `copy/check.sh`의 `find>` grep은 전부 낱말까지 박혀 있다**(`open`·`type`·
`submit`·`next`·`hl`). 그래서 `find> overlay` 줄을 새로 더해도 기존 검사 열여섯을
하나도 안 흔든다.

**6. `copy/check.sh`는 `set -uo pipefail`이다**(`:2`). **파이프라인 끝에
`grep -q`를 두면 안 된다** — 첫 매치에서 빠져나가며 앞단에 SIGPIPE를 일으키고
`pipefail`이 그것을 실패로 판정한다(HANDOFF). 기존 코드가 전부
`$(... | grep -ac ... || true)` 모양인 이유가 이것이고, 새 검사도 그 모양을 쓴다.

## 이번에 정하는 것 넷 (design doc이 안 정한 자리)

### 결정 1. `find_missed`는 "켠다"가 아니라 **매번 값을 정한다**

design 결정 9의 글자는 "`matches == 0`이면 플래그를 켠다"인데, 그대로 하면
**끄는 자리가 `main.zig` 하나뿐**이 된다. 그러면 성공한 검색이 앞의 실패를 안
지우는 경로가 생긴다 — `vt_test`처럼 poll 루프를 안 거치는 호출자가 그렇다.

그래서 `findSubmit`의 끝에서 `self.find_missed = count == 0;`으로 **매번
정한다.** 켜는 자리와 끄는 자리가 갈리지 않는 것이 요점이고, CS-M0이
`refreshMatches`를 셋 다에서 부른 것과 같은 규율이다.

### 결정 2. 끄는 자리는 `switch`보다 **앞**이다

`main.zig`의 `for (keys.copies) |cmd|` 루프에서 `switch` **바로 앞**에
`screen.findClearMissed()`를 둔다. 루프 **밖**이 아니라 안이다.

밖에 두면 한 번의 read에 여러 키가 실려 왔을 때(자동 반복) 첫 키만 메시지를
지운다. 안에 두고 `switch`보다 앞이면 **모든 명령이 예외 없이 지우고**, 그중
`.find_submit`만이 그 뒤에 다시 켤 수 있다. 순서 하나로 "다음 키에 사라진다"와
"새로 실패하면 다시 뜬다"가 함께 나온다.

### 결정 3. 오버레이 내용을 로그로 내는 줄을 하나 만든다

**게이트가 메시지를 볼 창구가 지금 하나도 없다**(위의 확인 4). `find> submit
matches=0`은 "검색이 못 찾았다"까지만 말하지 "화면에 그렇게 쓰였다"를 말하지
않는다. 그 둘은 이 milestone에서 **정확히 갈라야 하는 것**이다 — Task 1·2가
`vt.zig`를 고치고 Task 3이 `main.zig`를 고치므로, 창구가 없으면 Task 3의 실수를
게이트가 영영 못 잡는다.

`dumpOverlay(prompt)`가 `render()`에 넘어간 **바로 그 값**을 받아 찍는다.
문자열을 다시 만들지 않는 이유는, 다시 만들면 그리는 것과 찍는 것이 갈릴 수
있기 때문이다. **CS-M0의 `find> hl`과 같은 규율로 매 프레임 찍는다** — "바뀔
때만"은 상태를 하나 더 만들고 그 판정이 틀리면 증상이 "로그가 안 나온다"라
조사하기 나쁘다.

### 결정 4. 게이트의 순서는 **기록 먼저, 못 찾음 나중**이다

`zzz`를 먼저 찾으면 그것이 `find_last`를 덮어써서, 이어지는 빈 Enter가
`matches=0`을 낸다. 그러면 **"기록이 동작했다"와 "빈 Enter가 아무 일도 안
했다"가 안 갈린다** — 두 경우의 숫자가 똑같이 0이다.

순서를 뒤집으면 그 문제가 통째로 없어진다. 검사 16이 끝난 자리의 `find_last`는
`findme`이고, 그것을 되부른 빈 Enter는 **`matches=4`**를 낸다. CS-M1 전이라면
`matches=0`이었다 — 두 숫자가 이 기능의 있고 없음을 정확히 가른다.

**그리고 검사 16의 `esc`를 그대로 재사용한다.** 그 한 줄이 곧 "`copyExit`이
`find_last`만 안 지웠다"의 시험대다.

### 결정 5. 게이트가 아홉 키를 더한다

`type_keys`가 키마다 `sleep 0.3`이므로, 새 검사 둘은 키 아홉(`meta_l-shift-c` ·
`slash ret` · `slash z z z ret` · `k`)에 `sleep` 아홉을 더해 **부팅 하나당 약
12초**다. `copy` 체인이 게이트에서 세 회차 도므로 **전체에 약 36초**다.

**이 게이트의 잡음이 ±3분이라 이 증가분은 측정으로 안 갈린다**(HANDOFF). 그래도
적어 두는 이유는, 나중에 게이트가 길어졌을 때 "무엇이 더했는가"를 되짚을 수
있어야 하기 때문이다. **CS-M0은 0초였고 CS-M1은 36초다.**

---

## Task 1: 지난 검색어를 기억한다

**Files:**
- Modify: `terminal/src/vt.zig` (필드 둘, `findOpen`·`findSubmit`의 주석,
  `findSubmit`의 입력 처리)
- Modify: `terminal/src/vt_test.zig` (검사 32·33)

**메시지는 다음 Task다.** 기록과 메시지를 나누는 이유는 CS-M0이 좌표와 색을
나눈 것과 같다 — 한꺼번에 넣으면 "빈 Enter가 안 먹는다"와 "메시지가 안 뜬다"를
가르는 데 빌드 한 바퀴가 든다.

### Step 1: 필드 둘을 더한다 (사용자가 편집)

**넣을 것** — `terminal/src/vt.zig:151`의 `find_len: usize = 0,` **바로 다음
줄**이다. 즉 `/// 확정된 검색.`으로 시작하는 주석 앞이다.

```zig

    /// 마지막으로 확정한 검색어(design 결정 8). **`copyExit`이 지우지 않는
    /// 유일한 검색 상태다.**
    ///
    /// 빈 Enter가 이것을 다시 쓴다. **모드를 나갔다 다시 들어와도 `/`+Enter가
    /// 동작하는 것이 이 기능의 전부다** — 그래서 `copyExit`의 정리 목록에서
    /// 이것만 빠진다.
    ///
    /// `find_buf`와 같은 고정 128바이트이고 같은 이유다 — 동적 할당은 "언제
    /// 해제하는가"를 여러 자리에 나눠 놓는다.
    ///
    /// **성공·실패를 안 가리고 남긴다.** 못 찾은 검색어를 고쳐 다시 치는 것이
    /// 흔한 일이고, vim도 그렇게 한다.
    find_last: [128]u8 = undefined,
    find_last_len: usize = 0,
```

### Step 2: `findOpen`의 주석을 고친다 (사용자가 편집)

**지울 것** — `terminal/src/vt.zig:504-505`.

```zig
    /// `/`. 프롬프트를 연다. **언제나 빈 검색어로 시작한다** — 지난 검색어를
    /// 되부르는 것은 design이 비워 둔 자리다.
```

**넣을 것**

```zig
    /// `/`. 프롬프트를 연다. **언제나 빈 검색어로 시작한다**(design 결정 8) —
    /// 미리 채우면 전혀 다른 것을 찾을 때 먼저 여러 번 지워야 한다.
    ///
    /// 지난 검색어를 다시 쓰는 길은 **빈 Enter**이고 `findSubmit`이 그 자리다.
    /// 프롬프트에서 `↑`로 되부르는 것은 design이 비워 둔 자리로 남는다.
```

### Step 3: `findSubmit`의 주석을 고친다 (사용자가 편집)

**지울 것** — `terminal/src/vt.zig:566-568`.

```zig
    /// 빈 검색어로 Enter를 누르면 프롬프트만 닫는다. 지난 검색은 그대로 살아
    /// 있으므로 `n`이 계속 동작한다 — vim과 다른 자리이지만(vim은 지난 검색어를
    /// 다시 쓴다) 검색 기록이 없는 우리에게는 이것이 가장 덜 놀라운 동작이다.
```

**넣을 것**

```zig
    /// **빈 검색어로 Enter를 누르면 지난 검색어를 다시 쓴다**(CS-M1, design
    /// 결정 8). vim과 같은 동작이다. 되부를 것이 아예 없으면 예전처럼 프롬프트만
    /// 닫고, 그때도 지난 검색은 살아 있으므로 `n`이 계속 동작한다.
```

### Step 4: 빈 Enter가 지난 검색어를 쓴다 (사용자가 편집)

**지울 것** — `terminal/src/vt.zig:573-575`.

```zig
        const len = self.find_len;
        self.find_open = false;
        if (len == 0) return none;
```

**넣을 것**

```zig
        self.find_open = false;

        // **빈 Enter는 지난 검색어를 다시 쓴다**(design 결정 8). CN-M1이
        // 프롬프트만 닫던 자리이고, 그때 "검색 기록이 없어서"라고 적어 두었다.
        //
        // 되부를 것이 아예 없으면 그대로 프롬프트만 닫는다 — 부팅 직후 `/`를
        // 열고 그냥 Enter를 누른 경우다.
        var len = self.find_len;
        if (len == 0) {
            if (self.find_last_len == 0) return none;
            len = self.find_last_len;
            @memcpy(self.find_buf[0..len], self.find_last[0..len]);
        }

        // **성공·실패와 무관하게 남긴다**(design 결정 8). 못 찾은 검색어를 고쳐
        // 다시 치는 것이 흔한 일이고, 그러려면 실패한 것도 기억해야 한다.
        //
        // 위에서 되부른 경우에는 같은 값을 도로 쓰는 셈인데, 그래도 분기를
        // 안 만든다 — `find_buf`와 `find_last`는 **서로 다른 배열**이라 겹칠
        // 일이 없고, 규칙이 하나면 빠뜨릴 자리도 없다.
        @memcpy(self.find_last[0..len], self.find_buf[0..len]);
        self.find_last_len = len;
```

**`const len`이 `var len`이 된 것에 주의한다.** 아래에서 `self.find_buf[0..len]`을
읽는 자리(`ghostty_vt.search.Screen.init`의 셋째 인자)는 그대로다.

### Step 5: 빌드하고 검사를 돌린다 (Claude가 실행, 약 3분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대:** 조용히 끝나고 `vt_test`가 **CS-M0까지와 글자 하나 다르지 않은 PASS**를
낸다. 아직 새 검사를 안 더했다.

**`zig build`를 함께 도는 이유**는 HANDOFF의 실측 1이다 — Zig가 참조되지 않는
함수를 분석하지 않아서 `zig build test`만으로는 `main.zig`가 깨진 것을 두 번
놓쳤다.

### Step 6: 검사 32·33을 더한다 (사용자가 편집)

**넣을 것** — `terminal/src/vt_test.zig`에서 `std.debug.print("PASS\n", .{});`
**바로 앞**이다.

```zig

    // ── CS-M1: 검색 기록과 "못 찾았다" 메시지 ─────────────────────────────
    //
    // **새 화면을 만든다.** 앞의 `hs`는 검사 31에서 `copyExit`으로 끝났고 그
    // 상태에 검사 넷이 기대고 있다 — 남의 화면에 붙이면 앞 검사가 흔들린다.
    // CM-M1이 `cm`, CM-M2가 `pruned`, CN-M0이 `wm`, CN-M1이 `fm`·`fs`,
    // CS-M0이 `hs`를 새로 만든 것과 같은 규율이다.
    //
    // 화면 모양은 `hs`와 같다(20x5, 8번과 18번 줄이 표적). 같은 모양을 쓰는
    // 것은 게으름이 아니라 **기대값을 옮겨 쓸 수 있게 하려는 것**이다 —
    // 검사 26이 확정한 `matches=2`를 여기서 다시 세지 않아도 된다.
    const ls = try vt.Screen.init(init.io, init.gpa, 20, 5);
    defer ls.deinit();
    var ls_i: usize = 1;
    while (ls_i <= 20) : (ls_i += 1) {
        if (ls_i == 8 or ls_i == 18) {
            ls.feed("xxTARGETxx\r\n");
        } else {
            ls.feed(std.fmt.bufPrint(&line, "R{d}\r\n", .{ls_i}) catch unreachable);
        }
    }
    // **`copyEnter` 전에 한 번 그린다.** `state.cursor.viewport`는 `cells()`가
    // 채우므로, 그 전에 들어가면 커서가 (0,0)에서 시작한다.
    _ = try ls.cells(&buf);
    ls.copyEnter();

    // 검사 32. **빈 Enter가 지난 검색어를 다시 쓴다.**
    ls.findOpen();
    for ("TARGET") |ch| ls.findChar(ch);
    const lhit = try ls.findSubmit();
    if (lhit.matches == 0) {
        std.debug.print("FAIL: /TARGET found nothing\n", .{});
        return error.HistorySearchFoundNothing;
    }
    ls.findOpen();
    // 글자를 하나도 안 치고 곧바로 Enter다.
    const lhit2 = try ls.findSubmit();
    if (lhit2.matches != lhit.matches) {
        std.debug.print("FAIL: the empty Enter found {d} (expected the previous {d})\n", .{
            lhit2.matches, lhit.matches,
        });
        return error.EmptySubmitDidNotRepeat;
    }
    std.debug.print("vt_test: 빈 Enter가 지난 검색어를 다시 쓴다 OK (matches={d})\n", .{lhit2.matches});

    // 검사 33. **copy mode를 나갔다 들어와도 검색어가 남는다.**
    //
    // `copyExit`은 `find`·`find_matches`·`find_buf`를 전부 버린다 —
    // **`find_last`만 안 버린다**(design 결정 8). 그 하나가 이 기능의 전부이고,
    // 실수로 함께 지우면 여기서 `matches=0`이 되어 잡힌다.
    ls.copyExit();
    ls.copyEnter();
    ls.findOpen();
    const lhit3 = try ls.findSubmit();
    if (lhit3.matches != lhit.matches) {
        std.debug.print("FAIL: after leaving copy mode the empty Enter found {d} (expected {d})\n", .{
            lhit3.matches, lhit.matches,
        });
        return error.HistoryLostOnExit;
    }
    std.debug.print("vt_test: copy mode를 나갔다 들어와도 검색어가 남는다 OK (matches={d})\n", .{lhit3.matches});
```

### Step 7: 검사를 돌린다 (Claude가 실행, 약 3분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대:** 새 줄 둘이 나오고 `PASS`로 끝난다.

```
vt_test: 빈 Enter가 지난 검색어를 다시 쓴다 OK (matches=2)
vt_test: copy mode를 나갔다 들어와도 검색어가 남는다 OK (matches=2)
```

**`matches=2`가 기대값이다.** 검사 26이 같은 화면에서 이미 확정한 숫자다. 다르게
나오면 **plan이 아니라 실측이 답이다**(CS-M0에서 두 번 그랬다).

**검사 33이 `matches=0`으로 실패하면 Step 1의 필드가 `copyExit`에 섞여 들어간
것이다** — `copyExit`은 이 Task에서 한 글자도 안 바뀌어야 한다.

### Step 8: 커밋 (Claude가 실행)

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Repeat the last search when Enter is pressed on an empty prompt"
```

---

## Task 2: 못 찾았다는 사실을 상태로 만든다

**Files:**
- Modify: `terminal/src/vt.zig` (필드 하나, `copyExit`, `findSubmit`의 끝,
  접근자 둘)
- Modify: `terminal/src/vt_test.zig` (검사 34·35·36)

**아직 화면에 아무것도 안 쓴다.** 상태와 그리기를 나누는 이유는 Task 1과 같다 —
`vt_test`는 오버레이를 못 보므로, 여기서 상태를 다 확정해 두면 Task 3에서 남는
의심이 "글자를 어디에 쓰는가" 하나뿐이 된다.

### Step 1: 필드를 더한다 (사용자가 편집)

**넣을 것** — Task 1의 Step 1에서 넣은 `find_last_len: usize = 0,` **바로 다음
줄**이다.

```zig

    /// 마지막 검색이 아무것도 못 찾았는가(design 결정 9). **오버레이 한 줄에
    /// `/needle: not found`를 쓰는 조건이다.**
    ///
    /// `findSubmit`이 정하고, **`main.zig`가 copy 명령을 처리하기 직전 한
    /// 자리에서 끈다.** 시계를 안 들여오는 이유는 poll 루프가 지금 시각을 안
    /// 보기 때문이고, 다음 키까지 떠 있으면 사람이 메시지를 못 보고 넘길 일도
    /// 없다.
    ///
    /// **메시지에 쓸 글자는 `find_last`에서 온다.** 메시지가 뜰 때는 프롬프트가
    /// 이미 닫혀 있어서 `findNeedle()`이 null을 주기 때문이다 — 결정 8과 9가
    /// 맞물리는 자리가 여기다.
    find_missed: bool = false,
```

### Step 2: `copyExit`이 메시지를 끈다 (사용자가 편집)

**넣을 것** — `terminal/src/vt.zig:500`의
`self.hl_spans.clearRetainingCapacity();` **바로 다음 줄**이다. 즉
`self.term.screens.active.clearSelection();` 앞이다.

```zig
        // "못 찾았다" 메시지도 끈다(design 결정 9). 안 끄면 모드를 나간 뒤에도
        // 화면 아랫줄에 메시지가 남는다.
        //
        // **`find_last`는 여기서 안 지운다**(design 결정 8). 이 함수가 검색
        // 상태를 전부 버리는 자리인데 그것 하나만 빠지는 것이고, **모드를
        // 나갔다 들어와도 `/`+Enter가 동작하는 것이 CS-M1의 전부다.**
        // 검사 33이 이 예외를 본다.
        self.find_missed = false;
```

### Step 3: `findSubmit`이 매번 값을 정한다 (사용자가 편집)

**지울 것** — `findSubmit`의 마지막 네 줄이다(Task 1의 편집으로 줄 번호가
밀렸으므로 내용으로 찾는다).

```zig
        const moved = try self.findStep(.next, true);
        // **이동 뒤에 스냅숏을 뜬다.** 왜 뒤여야 하는지는 `refreshMatches`에
        // 적혀 있다 — `select()`가 앞의 목록을 해제한다.
        try self.refreshMatches();
        return .{ .matches = self.find.?.matchesLen(), .moved = moved };
```

**넣을 것**

```zig
        const moved = try self.findStep(.next, true);
        // **이동 뒤에 스냅숏을 뜬다.** 왜 뒤여야 하는지는 `refreshMatches`에
        // 적혀 있다 — `select()`가 앞의 목록을 해제한다.
        try self.refreshMatches();

        const count = self.find.?.matchesLen();
        // **켜기만 하지 않고 매번 값을 정한다**(CS-M1 plan 결정 1). design은
        // "0이면 켠다"라고 적었는데, 그대로 하면 끄는 자리가 `main.zig` 하나뿐이
        // 되어 **성공한 검색이 앞의 실패를 안 지우는 경로**가 생긴다. poll 루프를
        // 안 거치는 호출자(`vt_test`)가 그렇다.
        //
        // 켜는 자리와 끄는 자리를 안 가르는 것이 요점이고, CS-M0이
        // `refreshMatches`를 셋 다에서 부른 것과 같은 규율이다.
        self.find_missed = count == 0;
        return .{ .matches = count, .moved = moved };
```

### Step 4: 접근자 둘을 더한다 (사용자가 편집)

**넣을 것** — `findNeedle` 함수가 닫히는 `}`(`terminal/src/vt.zig:551`) **바로
다음**이다. 즉 `/// 검색 결과. `main.zig`가 로그에 쓴다.` 주석 앞이다.

```zig

    /// 못 찾은 검색어. **메시지가 꺼져 있으면 null이다**(design 결정 9).
    ///
    /// `findNeedle`과 짝이다 — 그쪽은 "지금 치고 있는 것", 이쪽은 "방금 못 찾은
    /// 것"이고, 오버레이 한 줄을 두 갈래로 가르는 것이 이 둘이다.
    ///
    /// **`main.zig`가 `find_last`를 직접 읽지 않게 하려고 함수로 낸다** —
    /// `findNeedle`·`clipboard`·`copyCursor`와 같은 규율이다.
    pub fn findMissed(self: *const Screen) ?[]const u8 {
        if (!self.find_missed) return null;
        return self.find_last[0..self.find_last_len];
    }

    /// "못 찾았다" 메시지를 끈다. **`main.zig`가 copy 명령을 처리하기 직전
    /// 한 자리에서 부른다**(design 결정 9).
    ///
    /// 끄는 것이 명령 처리보다 **앞**이라, 새로 실패한 검색의 메시지는
    /// `findSubmit`이 그 뒤에 다시 켜서 살아남는다. 순서 하나로 "다음 키에
    /// 사라진다"와 "새로 실패하면 다시 뜬다"가 함께 나온다(plan 결정 2).
    pub fn findClearMissed(self: *Screen) void {
        self.find_missed = false;
    }
```

### Step 5: 검사 34·35·36을 더한다 (사용자가 편집)

**넣을 것** — Task 1의 Step 6에서 넣은 마지막 `std.debug.print` **바로
다음**이다.

```zig

    // 검사 34. **못 찾으면 메시지가 켜지고 그 검색어를 준다.**
    if (ls.findMissed() != null) {
        std.debug.print("FAIL: the not-found message was on before any search failed\n", .{});
        return error.MissedFlagStuckOn;
    }
    ls.findOpen();
    for ("NOPE") |ch| ls.findChar(ch);
    const lhit4 = try ls.findSubmit();
    if (lhit4.matches != 0) {
        std.debug.print("FAIL: /NOPE found {d} match(es) (expected none)\n", .{lhit4.matches});
        return error.MissedSearchFoundSomething;
    }
    const lmiss = ls.findMissed() orelse {
        std.debug.print("FAIL: findMissed() was null after a search found nothing\n", .{});
        return error.MissedFlagNotSet;
    };
    if (!std.mem.eql(u8, lmiss, "NOPE")) {
        std.debug.print("FAIL: findMissed() gave '{s}' (expected 'NOPE')\n", .{lmiss});
        return error.MissedNeedleWrong;
    }
    std.debug.print("vt_test: 못 찾으면 메시지가 그 검색어를 준다 OK (needle={s})\n", .{lmiss});

    // 검사 35. **메시지를 끄면 사라지고, 못 찾은 검색어도 기록에는 남는다.**
    //
    // 뒷부분이 design 결정 8의 "성공·실패와 무관하게 남긴다"를 보는 자리다.
    // **판정을 `matches`로 하면 안 된다** — 되부른 `NOPE`도 0을 내고 "아무 일도
    // 안 했다"도 0을 내서 둘이 안 갈린다. `findMissed()`가 다시 `NOPE`를 주는
    // 것이 "정말로 되불렀다"의 증거다.
    ls.findClearMissed();
    if (ls.findMissed() != null) {
        std.debug.print("FAIL: findClearMissed() did not turn the message off\n", .{});
        return error.MissedFlagNotCleared;
    }
    ls.findOpen();
    const lhit5 = try ls.findSubmit();
    if (lhit5.matches != 0) {
        std.debug.print("FAIL: the empty Enter found {d} (expected none)\n", .{lhit5.matches});
        return error.FailedNeedleNotRemembered;
    }
    const lmiss2 = ls.findMissed() orelse {
        std.debug.print("FAIL: the empty Enter did not re-run the failed needle\n", .{});
        return error.FailedNeedleNotRemembered;
    };
    if (!std.mem.eql(u8, lmiss2, "NOPE")) {
        std.debug.print("FAIL: the empty Enter re-ran '{s}' (expected 'NOPE')\n", .{lmiss2});
        return error.FailedNeedleWrong;
    }
    std.debug.print("vt_test: 못 찾은 검색어도 기록에 남는다 OK (needle={s})\n", .{lmiss2});

    // 검사 36. **copy mode를 나가면 메시지가 꺼진다.**
    //
    // 검사 33이 `find_last`가 **남는** 것을 보고, 이 검사가 `find_missed`는
    // **안 남는** 것을 본다. 둘이 같은 함수의 서로 반대되는 두 계약이라 나란히
    // 둔다.
    ls.copyExit();
    if (ls.findMissed() != null) {
        std.debug.print("FAIL: the not-found message survived copyExit\n", .{});
        return error.MissedFlagSurvivedExit;
    }
    std.debug.print("vt_test: copy mode를 나가면 메시지가 꺼진다 OK\n", .{});
```

### Step 6: 검사를 돌린다 (Claude가 실행, 약 3분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대:** 새 줄 셋이 더 나오고 `PASS`로 끝난다.

```
vt_test: 못 찾으면 메시지가 그 검색어를 준다 OK (needle=NOPE)
vt_test: 못 찾은 검색어도 기록에 남는다 OK (needle=NOPE)
vt_test: copy mode를 나가면 메시지가 꺼진다 OK
```

**검사 34가 `MissedSearchFoundSomething`으로 실패하면 `NOPE`가 화면에 있다는
뜻이다.** 그 화면은 `R1`~`R20`과 `xxTARGETxx`뿐이라 그럴 수 없지만, 만약 그렇다면
needle을 바꾸는 것이 답이지 코드를 고치는 것이 아니다.

### Step 7: 커밋 (Claude가 실행)

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Remember that the last search found nothing"
```

---

## Task 3: 오버레이 한 줄이 두 갈래가 된다

**Files:**
- Modify: `terminal/src/main.zig` (`promptText` 추가, `dumpOverlay` 추가,
  프롬프트 버퍼, copy 루프의 끄는 자리, `dumpOverlay` 호출)

**이 Task가 화면을 바꾸는 유일한 자리다.** 그리고 **`vt_test`가 못 보는
자리다** — `zig build test`가 통과해도 아무것도 증명되지 않으므로, Task 4의
게이트가 이 Task의 유일한 시험대다.

### Step 1: `promptText`를 더한다 (사용자가 편집)

**넣을 것** — `terminal/src/main.zig`의 `Prompt` struct가 닫히는 `};`
(`:171`) **바로 다음**이다.

```zig

/// 오버레이 한 줄에 쓸 글자를 정한다. **프롬프트가 우선이고, 닫혀 있으면
/// "못 찾았다" 메시지다**(design 결정 9). 둘 다 없으면 null이고, 그러면
/// 오버레이를 아예 안 그린다.
///
/// **`drawPrompt`는 이것을 모른다.** 그리는 함수는 "한 줄을 준 색으로 쓴다"
/// 하나만 알고, 무엇을 쓸지는 여기서 끝난다 — CN-M1이 앞의 `/`를 `vt.zig`가
/// 아니라 `main.zig`에서 붙인 것과 같은 경계다(모양은 여기가 정한다).
///
/// **프롬프트를 먼저 보는 것에 뜻이 있다.** 못 찾은 뒤에 `/`를 다시 열면 사람이
/// 지금 치고 있는 것이 화면에 나와야 한다. 순서를 뒤집으면 새 검색어를 치는
/// 동안 지난 실패 메시지가 화면에 남는다.
///
/// `buf`는 최소 **140바이트**여야 한다: `/` 하나 + needle 128 + `: not found`
/// 열하나.
fn promptText(screen: *vt.Screen, buf: []u8) ?[]const u8 {
    const MISS = ": not found";
    if (screen.findNeedle()) |n| {
        buf[0] = '/';
        @memcpy(buf[1 .. 1 + n.len], n);
        return buf[0 .. 1 + n.len];
    }
    if (screen.findMissed()) |n| {
        buf[0] = '/';
        @memcpy(buf[1 .. 1 + n.len], n);
        @memcpy(buf[1 + n.len ..][0..MISS.len], MISS);
        return buf[0 .. 1 + n.len + MISS.len];
    }
    return null;
}
```

### Step 2: `dumpOverlay`를 더한다 (사용자가 편집)

**넣을 것** — `dumpFind` 함수가 닫히는 `}`(`terminal/src/main.zig:374`) **바로
다음**이다. 즉 `dumpHighlight`의 주석 앞이다.

```zig

/// 오버레이 한 줄에 무엇이 쓰였는지(CS-M1 plan 결정 3). **없으면 한 줄도 안
/// 찍는다.**
///
/// **이 줄이 유일한 관측 수단이다.** 오버레이는 `cells()`에 안 섞이므로
/// `screen>`에 영영 안 나오고, `dumpStyles`는 덮인 줄을 통째로 건너뛴다
/// (`overlaid_row`). 그래서 이 줄이 없으면 게이트가 "화면에 그렇게 쓰였다"를
/// 볼 창구가 하나도 없다 — `find> submit matches=0`은 "검색이 못 찾았다"까지만
/// 말한다.
///
/// **`render()`에 넘어간 바로 그 값을 받는다.** 문자열을 여기서 다시 만들지
/// 않는 이유는, 다시 만들면 그리는 것과 찍는 것이 갈릴 수 있기 때문이다.
///
/// `find> hl`과 같이 **매 프레임 찍는다**. "바뀔 때만"은 상태를 하나 더 만들고
/// 그 판정이 틀리면 증상이 "로그가 안 나온다"라 조사하기 나쁘다.
///
/// 문구가 이 파일과 `copy/check.sh` 양쪽에 중복된다.
/// **한쪽을 고치면 다른 쪽도 고쳐야 한다.**
fn dumpOverlay(prompt: ?Prompt) void {
    const p = prompt orelse return;
    std.debug.print("terminal: find> overlay text={s}\n", .{p.text});
}
```

### Step 3: 메시지를 끄는 자리를 만든다 (사용자가 편집)

**지울 것** — `terminal/src/main.zig:615-616`.

```zig
            for (keys.copies) |cmd| {
                switch (cmd) {
```

**넣을 것**

```zig
            for (keys.copies) |cmd| {
                // **"못 찾았다" 메시지는 다음 키에 사라진다**(design 결정 9).
                //
                // 끄는 자리가 **루프 안**인 것에 뜻이 있다. 밖에 두면 한 번의
                // read에 여러 키가 실려 왔을 때(자동 반복) 첫 키만 메시지를
                // 지운다.
                //
                // 그리고 `switch`보다 **앞**이라, 모든 명령이 예외 없이 지우고
                // 그중 `.find_submit`만이 그 뒤에 다시 켤 수 있다. 순서 하나로
                // "다음 키에 사라진다"와 "새로 실패하면 다시 뜬다"가 함께 나온다.
                screen.findClearMissed();
                switch (cmd) {
```

### Step 4: 프롬프트 문자열을 `promptText`에서 받는다 (사용자가 편집)

**지울 것** — `terminal/src/main.zig:750-764`.

```zig
        // 버퍼가 needle보다 한 칸 크다. `/` 한 글자 때문이다.
        var prompt_buf: [129]u8 = undefined;
        const prompt: ?Prompt = if (screen.findNeedle()) |n| blk: {
            prompt_buf[0] = '/';
            @memcpy(prompt_buf[1 .. 1 + n.len], n);
            break :blk .{
                .text = prompt_buf[0 .. 1 + n.len],
                .rows = rows,
                .cols = cols,
                // **`cells()` 뒤에 읽어야 한다** — `state.colors`는 update()가
                // 채운다(vt.zig의 defaultFg 주석).
                .fg = screen.defaultFg(),
                .bg = screen.defaultBg(),
            };
        } else null;
```

**넣을 것**

```zig
        // 버퍼가 needle보다 **열두 칸** 크다. 앞의 `/` 하나와 뒤의
        // `: not found` 열하나 때문이다(CS-M1).
        var prompt_buf: [140]u8 = undefined;
        const prompt: ?Prompt = if (promptText(screen, &prompt_buf)) |t| .{
            .text = t,
            .rows = rows,
            .cols = cols,
            // **`cells()` 뒤에 읽어야 한다** — `state.colors`는 update()가
            // 채운다(vt.zig의 defaultFg 주석).
            .fg = screen.defaultFg(),
            .bg = screen.defaultBg(),
        } else null;
```

### Step 5: 프레임마다 오버레이를 찍는다 (사용자가 편집)

**넣을 것** — `terminal/src/main.zig:776`의 `dumpHighlight(screen);` **바로 다음
줄**이다.

```zig
        dumpOverlay(prompt);
```

### Step 6: 빌드하고 검사를 돌린다 (Claude가 실행, 약 3분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/terminal tars-devcontainer \
  bash -c 'zig build && zig build test'
```

**기대:** 조용히 끝나고 `vt_test`가 Task 2와 같은 `PASS`를 낸다. 이 Task는
`vt_test`가 안 보는 자리(`main.zig`)만 바꾸므로 검사 출력이 안 변하는 것이
정상이다.

**그래도 `zig build`를 함께 도는 이유**가 여기 있다 — 이 Task의 실수는
`zig build test`가 영영 못 잡는다.

**`@memcpy`에서 길이 관련 에러가 나면 `prompt_buf`의 140을 먼저 본다.**

### Step 7: 커밋 (Claude가 실행)

```bash
git add terminal/src/main.zig
git commit -m "Say on screen when a search finds nothing"
```

---

## Task 4: 게이트가 둘 다 본다

**Files:**
- Modify: `copy/check.sh` (검사 17·18 추가)

**새 부팅은 없다.** 검사 16이 `esc`로 끝난 자리를 그대로 이어받는다 —
**그 `esc`가 곧 "`copyExit`이 `find_last`만 안 지웠다"의 시험대다**(plan 결정 4).

### Step 1: 검사 17·18을 더한다 (사용자가 편집)

**넣을 것** — `copy/check.sh:816`의
`echo "leaving copy mode cleared the highlight"` **바로 다음**이다. 즉
`# ── 음성 검사: 로그에 NUL이 섞이지 않았다` 주석 앞이다.

```sh

# ── 검사 17: 검색 기록 (CS-M1) ─────────────────────────────────────────
#
# **검사 16이 끝난 자리를 그대로 쓴다.** 방금 `esc`가 copy mode를 닫았고,
# `copyExit`이 검색 상태를 전부 버리면서 **`find_last`만 남겼다**(design 결정 8).
# 그것이 이 검사의 대상이다 — 모드를 나갔다 들어와서 `/`+Enter만 쳐도 지난
# `findme`가 다시 돌아야 한다.
#
# **순서가 중요하다**(plan 결정 4). 아래 검사 18의 `zzz`를 먼저 찾으면 그것이
# `find_last`를 덮어써서 빈 Enter도 matches=0을 낸다 — 그러면 "기록이
# 동작했다"와 "빈 Enter가 아무 일도 안 했다"가 안 갈린다.
#
# **matches=4가 판정이다.** CS-M1 전에는 빈 Enter가 프롬프트만 닫아 matches=0이
# 나왔다. 두 숫자가 이 기능의 있고 없음을 정확히 가른다. 넷인 것의 산수는
# 검사 15에 적혀 있다(표적 둘 × 명령줄·출력줄 둘).
SUBMITS_BEFORE="$(grep -ac 'terminal: find> submit' "$LOG" || true)"

type_keys meta_l-shift-c
sleep 2
type_keys slash ret
sleep 3

SUBMITS_AFTER="$(grep -ac 'terminal: find> submit' "$LOG" || true)"
# **줄이 늘었는지 먼저 본다.** 앞의 검색도 matches=4를 찍었으므로, 줄 수를 안
# 세면 "빈 Enter가 아무 줄도 안 남겼다"를 옛 줄로 통과시킨다.
if [ "$SUBMITS_AFTER" -le "$SUBMITS_BEFORE" ]; then
  report_failure "the empty Enter did not submit (find> submit ${SUBMITS_BEFORE} -> ${SUBMITS_AFTER})"
fi
REPEAT="$(grep -a 'terminal: find> submit' "$LOG" | tail -n 1)"
case "$REPEAT" in
  *"matches=4"*) ;;
  *) report_failure "the empty Enter did not re-run 'findme': ${REPEAT}" ;;
esac
echo "an empty Enter re-ran the remembered search: ${REPEAT}"

# ── 검사 18: "못 찾았다" 메시지 (CS-M1) ────────────────────────────────
#
# **오버레이는 screen> 에 영영 안 나오고**(CN-M1 design 결정 7) **style> 도
# 덮인 줄을 건너뛴다**(main.zig의 overlaid_row). 그래서 `find> overlay` 한 줄이
# 유일한 관측 수단이다(plan 결정 3).
#
# `zzz`는 이 화면 어디에도 없다 — 스크롤백은 `seq 1 100`의 숫자와 `findme`와
# 셸 프롬프트뿐이다.
type_keys slash z z z ret
sleep 3

MISS="$(grep -a 'terminal: find> submit' "$LOG" | tail -n 1)"
case "$MISS" in
  *"matches=0"*) ;;
  *) report_failure "expected /zzz to find nothing, got: ${MISS}" ;;
esac

# **판정.** 마지막 프레임의 오버레이가 못 찾았다고 쓴다.
#
# 위의 matches=0과 이 줄은 **다른 것을 본다** — 그쪽은 "검색이 못 찾았다"이고
# 이쪽은 "화면에 그렇게 쓰였다"이다. Task 3의 실수는 이 줄로만 잡힌다.
#
# **파이프 끝에 grep -q를 두지 않는다.** 첫 매치에서 빠져나가며 앞단에 SIGPIPE를
# 일으키고 `set -o pipefail`이 그것을 실패로 판정한다.
if [ "$(last_frame | grep -acF 'terminal: find> overlay text=/zzz: not found' || true)" -eq 0 ]; then
  echo "--- overlay lines ---"
  grep -a 'terminal: find> overlay' "$LOG" | tail -n 5
  report_failure "the overlay did not say that /zzz was not found"
fi
echo "the overlay reported that /zzz was not found"

# **판정(음성).** 다음 키 하나에 메시지가 사라진다(design 결정 9).
#
# `k`는 copy 커서를 한 칸 올릴 뿐이라 화면의 다른 것을 안 건드린다. 안 사라지면
# main.zig의 끄는 자리가 빠진 것이고, 증상은 **"메시지가 화면 아랫줄에 영영
# 붙어 있다"**이다 — 사람에게는 "터미널이 고장 났다"로 보인다.
type_keys k
sleep 2
if [ "$(last_frame | grep -ac 'terminal: find> overlay' || true)" -ne 0 ]; then
  echo "--- last frame overlay lines ---"
  last_frame | grep -a 'terminal: find> overlay'
  report_failure "the not-found message survived the next key"
fi
echo "the next key cleared the not-found message"
```

### Step 2: `copy` 체인만 단독으로 돌린다 (Claude가 실행, **약 8분**)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash copy/check.sh
```

**8분이라 Bash 도구의 10분 상한에 가깝다** — `run_in_background`로 돌린다.

**기대:** 검사 16까지 지금과 같고, 새 줄 넷이 더 나온 뒤 체인이 통과한다.

```
an empty Enter re-ran the remembered search: terminal: find> submit matches=4 moved=... us=...
the overlay reported that /zzz was not found
the next key cleared the not-found message
```

**`the empty Enter did not re-run 'findme'`로 실패하고 `matches=0`이 나오면**
Task 1의 Step 4가 안 들어갔거나 `copyExit`이 `find_last`를 함께 지운 것이다.
`vt_test`의 검사 33이 후자를 먼저 잡으므로, 거기가 통과했는데 여기가 실패하면
남는 의심은 **부팅한 바이너리가 낡았다** 하나다.

**`the overlay did not say...`로 실패하면 `--- overlay lines ---`를 먼저
읽는다.** 줄이 하나도 없으면 Task 3의 Step 5(호출)가 빠진 것이고, 줄은 있는데
글자가 다르면 Step 1의 `MISS` 문자열이 다른 것이다.

### Step 3: 커밋 (Claude가 실행)

```bash
git add copy/check.sh
git commit -m "Check that the gate sees the search history and the miss message"
```

---

## Task 5: 루트 게이트와 마무리

**Files:**
- Modify: `docs/superpowers/specs/2026-08-28-tars-copy-search-feedback-design.md`
  (`Status:` 줄)
- Modify: `HANDOFF.md`
- Modify: `MEMORY.md` + `docs/decisions/project_copy_search_feedback.md`

### Step 1: 루트 게이트를 돌린다 (Claude가 실행, **약 22분**)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
    bash check.sh > /tmp/gate.out 2>&1 ; } 2> /tmp/gate.time
```

**22분이라 Bash 도구의 상한을 넘는다** — `run_in_background`로 돌린다.
**`| tail`을 붙이지 않는다**(HANDOFF: 진행 상황이 안 보이고 종료 코드가 `tail`의
것이 된다).

**기대:** 여덟 체인 3/3, 부팅 30회 이상.

확인할 것 셋.

```bash
grep -c 'skipping make' /tmp/gate.out    # 23이어야 한다 (GL-M1)
tail -n 30 /tmp/gate.out                 # 3/3 판정
cat /tmp/gate.time                       # 기준선과 비교
```

**기준선은 21분 27초~37초다**(CS-M0이 세 번 쟀다). **CS-M1은 키 아홉을
더했으므로 약 36초가 늘어야 맞다**(plan 결정 5) — 그런데 **이 게이트의 잡음이
±3분이라 그 증가분은 측정으로 안 갈린다.** 22분대 안이면 정상으로 읽고, 크게
벗어나면 코드를 의심하기 전에 기계를 먼저 의심한다(TR-M2의 6시간 12분은
Chrome이 원인이었다).

### Step 2: 게이트를 세 번 돌린다 (Claude가 실행, **약 66분**)

한 번의 통과는 판정이 아니다. 위 명령을 세 번 돌려 전부 3/3인 것을 본다.
**`run_in_background`로 순차 실행한다.**

### Step 3: design doc의 `Status:`를 갱신한다 (Claude가 편집)

3번째 줄을 `**Status:** 설계 확정. **CS-M0·CS-M1 완료(2026-08-28). 서브프로젝트
종료.**`로 바꾼다.

**이 저장소에는 `Status:` 줄이 낡은 design doc이 이미 셋 있다**(Config
Persistence · Power Management · Hardware Discovery). CN design도 CS design도 그
빚을 새로 만들지 않았다.

### Step 4: 기억을 갱신한다 (Claude가 편집)

`docs/decisions/project_copy_search_feedback.md`는 이미 있다. **새로 만들지 말고
CS-M1 절을 더한다.** `MEMORY.md`의 한 줄도 "CS-M1 미착수"를 고친다.

**담을 것**은 실행이 증명한 것만이다.

- 빈 Enter가 `findSubmit`까지 이미 도착하고 있었다는 것(`input.zig`가 버퍼
  내용을 안 본다) — 그래서 키를 하나도 안 더했다
- `findNeedle()`이 프롬프트가 닫히면 null이라 **메시지에 쓸 글자가 `find_last`
  에서 올 수밖에 없다**는 것(결정 8과 9가 맞물리는 자리)
- `find_missed`를 "켠다"가 아니라 **매번 값을 정한다**로 바꾼 이유(plan 결정 1)
- 끄는 자리가 `switch`보다 **앞**인 것이 두 계약을 한꺼번에 만든다는 것
- 오버레이 내용을 볼 창구가 `screen>`에도 `style>`에도 없어서 **줄을 새로
  만들어야 했다**는 것
- 게이트 검사 순서를 뒤집은 이유(`zzz`가 `find_last`를 덮어쓰면 판정이 무너진다)
- 게이트 실측 시간

### Step 5: `HANDOFF.md`를 갱신한다 (Claude가 편집)

- 제목과 "지금 어디인가"를 CS-M1 이후로. **진행 중인 서브프로젝트가 없어진다**
- copy mode 표에 "검색 기록"과 "못 찾음 메시지" 줄
- 로그 문구 목록에 `terminal: find> overlay text=…`
- 게이트 기준선을 실측으로, 그리고 CS-M1이 키 아홉을 더했다는 것
- "이월 숙제"에서 CS-M1을 **끝난 숙제**로 옮긴다
- 핵심 파일의 줄 번호를 CS-M1 이후로
- `CLAUDE.md`의 "완료된 서브프로젝트" 목록에 Copy Search Feedback을 더한다

### Step 6: 커밋 (Claude가 실행)

```bash
git status --short
git add docs/ HANDOFF.md MEMORY.md CLAUDE.md
git commit -m "Close out CS-M1"
```

**`git add`로 디렉터리를 통째로 넣기 전에 `git status`를 먼저 본다**(저장소
규칙). `M`과 신규를 가른다.

---

## 완료 조건

- [ ] `zig build && zig build test`가 통과하고 `vt_test`에 검사 32~36이 있다
- [ ] `copy` 체인이 단독으로 통과하고 새 줄 셋이 나온다
- [ ] 루트 게이트가 **3회 연속 8체인 3/3**이고 `skipping make`가 매번 23이다
- [ ] design doc의 `Status:`가 CS-M1 완료로 갱신됐다
- [ ] `docs/decisions/project_copy_search_feedback.md`에 CS-M1 절이 있다
- [ ] `HANDOFF.md`가 CS-M1 이후 상태를 적고 있다

## 이 milestone이 안 하는 것

- **키를 안 더한다.** `input.zig`·`input_test.zig`를 안 건드린다.
- **`cells()`를 안 건드린다.** 색 결정은 CS-M0이 끝냈다.
- **`drawPrompt`를 안 바꾼다**(design 결정 9). 그리는 함수는 여전히 "한 줄을
  준 색으로 쓴다" 하나만 안다.
- **검색어를 여러 개 기억하지 않는다.** `find_last` 하나다 — 목록과 그것을 훑는
  키(`↑`)는 design이 비워 둔 자리다.
- **`/`를 열 때 지난 검색어를 미리 채우지 않는다**(design 결정 8).
- **매치 위치 표시(`[3/12]`)도 현재 매치 색 구분도 안 한다**(design "비워 두는
  자리").
- **메시지를 시계로 지우지 않는다.** 다음 키 하나가 지운다.
