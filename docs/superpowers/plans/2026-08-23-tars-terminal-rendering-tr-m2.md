# TARS Terminal Rendering TR-M2 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 구현 파일 편집은
> 사용자가 하고, 빌드·QEMU·게이트·조사성 명령은 Claude가 실행하며, Claude는 각
> Step의 정확한 내용을 제시하고 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는
> 이 저장소에 적용하지 않는다.

**Goal:** 화면 밖으로 밀려난 줄을 Shift+PageUp으로 다시 볼 수 있다. 스크롤백이
1000줄까지 쌓이고, 스크롤 키가 PTY로 새어 나가지 않으며, Shift+End나 새 출력이
오면 맨 아래로 돌아온다. 게이트가 **뷰포트 위치와 화면 내용 두 겹으로** 그것을
증명한다.

**Design doc:** `docs/superpowers/specs/2026-08-23-tars-terminal-rendering-design.md`
(결정 10~13과 TR-M2 절이 이 milestone의 몫이다. 결정 1~9는 TR-M0·M1에서 끝났다.
design은 승인되어 있으므로 다시 논의하지 않는다.)

**Tech Stack:** Zig 0.16, libghostty-vt(`PageList` 스크롤백 · `Terminal.scrollViewport`
· `PageList.scrollbar`), evdev, DRM dumb buffer, QEMU monitor `sendkey`, bash 게이트
스크립트

---

## 착수 전에 이미 확정된 사실 (2026-08-23 실측)

**vendor된 ghostty 소스를 읽고 컨테이너에서 프로브를 돌려 확인한 값들이다.
다시 조사하지 않는다.** 프로브는 `/tmp/tr_m2_probe.zig`를 `terminal/src/vt_test.zig`
자리에 마운트해 `zig build test`로 돌렸다(저장소는 안 건드린다).

### 1. `max_scrollback_lines`만 주면 아무 일도 안 일어난다

design 결정 10은 `max_scrollback_lines = 1000`만 말하는데, **바이트 한도가 먼저
걸려서 그 값이 무시된다.** 155×47 격자에 2000줄을 먹여 실측한 값이다.

| 설정 | 남은 history | 메모리 |
|---|---|---|
| `bytes=10_000, lines=null` (지금) | 454줄 | 0.77MB |
| `bytes=10_000, lines=1000` | **454줄 (그대로)** | 0.77MB |
| **`bytes=null, lines=1000`** | **754줄** | **1.15MB** |
| `bytes=null, lines=null` | 1954줄 | 2.68MB |

효력 있는 한도는 `max(사용자가 준 값, 활성 영역을 담을 최소값)`이라
(`PageList.Limits.max`) 10,000바이트는 최소값보다 작아서 처음부터 무시되고 있었다.

**history가 1000이 아니라 754인 것은 정상이다.** 가지치기가 **페이지 통째로**
일어나므로(155칸에서 한 페이지가 약 286줄) 1000을 넘는 순간 한 페이지가 사라져
754로 떨어진다. 즉 754~1000줄 사이를 오간다.

부수 사실: **지금도 스크롤백은 454줄이 쌓이고 있다.** 없는 것이 아니라 올라가는
길이 없을 뿐이다.

### 2. 스크롤 API는 `Terminal.scrollViewport(behavior)` 하나면 된다

```zig
pub const ScrollViewport = union(Tag) {
    top,            // 스크롤백의 맨 위
    bottom,         // 활성 영역의 맨 위 = 평소 상태
    delta: isize,   // 상대 이동. 위가 음수다
    row: usize,     // 절대 행 번호
};
```

`Terminal.zig:2504`에 있고 `:2541`이 그것을 `screens.active.scroll(...)`로 넘긴다.
`Screen.scroll`이나 `PageList.Scroll`을 직접 부를 필요가 없다.

> **design doc과 이름이 다르다.** design 결정 12의 표는 `.delta_row`·`.active`라고
> 적었는데 그것은 한 겹 아래인 `PageList.Scroll`의 이름이다. `Terminal` 쪽 이름은
> `.delta`·`.bottom`이고, 우리가 부르는 것은 이쪽이다.

### 3. 위치를 로그로 낼 창구는 `pages.scrollbar()`다

`PageList.zig:3763`이 `{total, offset, len}`을 준다. `total`은 스크롤 가능한 전체
행 수, `offset`은 뷰포트 맨 윗줄이 그중 몇 번째인가, `len`은 언제나 `rows`다.
맨 아래에서 `total=501 offset=454 len=47`, 한 화면 올리면 `offset=407`, `.top`이면
`offset=0`이었다. **즉 "바닥에 있다"는 `offset == total - len`으로 검사한다.**

닿는 길은 `terminal.screens.active.pages.scrollbar()`다. `ScreenSet.active`가
`*Screen`이라 포인터를 따로 잡을 필요가 없다(`ScreenSet.zig:28`).

### 4. `RenderState`가 뷰포트를 따라간다 — `cells()`는 손댈 것이 없다

`update()`가 `pages.getTopLeft(.viewport)`에서 시작한다(`render.zig:362`). 스크롤한
뒤 `cells()`를 부르면 옛 줄이 그대로 나온다. **커서도 자동으로 사라진다** —
뷰포트 밖이면 `state.cursor.viewport`가 null이다(실측 확인). design 결정 2가
예고한 그대로다.

### 5. 새 출력은 뷰포트를 안 내린다 — 결정 13은 우리 코드가 해야 한다

올라간 상태에서 3줄을 더 먹여도 화면 첫 줄이 그대로였다. PTY 출력이 도착하는
자리에서 `scrollViewport(.bottom)`을 우리가 불러야 한다.

부수 효과가 하나 있다: 그렇게 하면 **뷰포트가 history에 머무는 동안 가지치기가
일어나는 상황이 구조적으로 안 생긴다.** 가지치기는 그 페이지를 가리키던 pin을
`garbage`로 만드는데, 결정 13이 그 창을 닫는다.

### 6. 렌더 경로를 키 쪽으로도 열어야 한다

지금 `main.zig`의 렌더는 **PTY 출력 분기 안에만** 있다(`main.zig:398-427`).
스크롤은 키로 일어나므로 그대로 두면 화면이 안 바뀐다.

### 7. 게스트에서 47줄 넘게 찍는 방법

게스트에는 `seq` 바이너리가 없지만 **fish가 `seq`를 함수로 갖고 있고**
(`/usr/share/fish/functions/seq.fish`, `make_initrd.sh:59`가 디렉터리째 복사한다)
`PATH` 없이도 동작한다. `seq 200` 한 줄이면 된다.

### 8. `sendkey shift-pgup`

QEMU monitor의 키 이름은 `pgup`·`pgdn`·`home`·`end`이고 `shift-` 접두사를 붙인다.
지금 `specialKey`가 PageUp/PageDown/Home/End를 이미 알고 있으므로
(`input.zig:156-169`), 가로채는 자리는 그보다 앞인 `chord()`다.

### 9. `xterm-256color` terminfo가 initrd에 없다

TR-M0이 `TERM`을 `xterm-256color`로 바꿨는데 `make_initrd.sh:146`은 여전히 `xterm`
파일 하나만 복사한다. `input/check.sh:73`의 검사가 `*terminfo/x/xterm*` 글로브라
그대로 통과한다. 컨테이너 sysroot에 `/usr/share/terminfo/x/xterm-256color`(4071B)가
있는 것을 확인했다 — **고치는 것은 두 줄이다.**

## 저장소 쪽 출발 상태

- `terminal/src/vt.zig:64-73` `Terminal.init`에 `.cols`·`.rows`·`.colors`만 준다.
  스크롤백 한도를 안 주므로 `max_scrollback_bytes`가 기본 10,000이다.
- `terminal/src/vt.zig` **스크롤 API도 위치 조회도 없다.** `Screen`이 내보내는
  것은 `feed`·`cells`·`defaultFg`·`defaultBg` 넷뿐이다.
- `terminal/src/input.zig:343` `handleKey`가 `[]const u8` 하나를 돌려준다.
- `terminal/src/input.zig:312-338` `chord`가 `?[]const u8`이고 Meta·Alt 두 분기만
  있다. **Shift는 특수키에 대해 아무 의미가 없다.**
- `terminal/src/input.zig:425` `readKeys`가 `[]const u8`을 돌려준다. 루프 조건이
  `while (i < count and written < out.len)`이라 **바이트 버퍼가 차면 이벤트 처리
  자체가 멈춘다.**
- `terminal/src/main.zig:398-427` 렌더·`dumpScreen`·`dumpStyles`·`dumpInk`가 전부
  PTY 분기 **안**에 있다.
- `terminal/src/input_test.zig:20` `expectCtx`가 반환값을 `[]const u8`로 비교한다.
  이 파일의 검사 100여 개가 전부 이 함수를 거친다.
- `kernel/make_initrd.sh:145-146` terminfo 파일 하나(`xterm`)만 복사한다.
- `input/check.sh:71-81` initrd 목록을 `*usr/share/terminfo/x/xterm*` 글로브로 본다.
- `render/check.sh` TR 체인. monitor 45460. 검사 일곱(색 셋 + 한글 넷) + 음성 검사 셋.

## 왜 이 순서인가

```
Task 1  vt.zig — 스크롤백 한도와 스크롤 API      ← 부팅 없음. TDD
  ↓     한도가 정말 효력을 갖는지를 호스트에서 먼저 못 박는다
Task 2  input.zig — 반환을 "바이트열 또는 동작"으로 ← 부팅 없음. TDD
  ↓
Task 3  main.zig — 렌더를 루프 끝으로, 스크롤을 잇는다 ← 부팅. 스모크
  ↓     scroll> 로그도 여기서 나온다 (같은 편집 묶음이다)
Task 4  render/check.sh에 스크롤 검사를 더한다      ← 완료선
  ↓
Task 5  xterm-256color terminfo                    ← 이월 숙제
  ↓
Task 6  루트 게이트 3/3
  ↓
Task 7  문서
```

**Task 1과 2가 앞인 이유는 둘 다 부팅 없이 끝나기 때문이다.** 부팅 1.5초(+커널
빌드 1분 30초)를 쓰기 전에 0.1초로 잡을 수 있는 실패를 먼저 잡는 것은 HD-M2가
세우고 TR-M0·M1이 이어온 방식이다.

**Task 1이 Task 2보다 앞인 이유는 "스크롤할 것이 있는가"가 "스크롤 키가
동작하는가"보다 아래층이기 때문이다.** 한도가 안 걸려 있으면 키가 아무리
정확해도 볼 것이 454줄뿐이고, 그 실패를 키 쪽에서 조사하게 된다.

**Task 3이 `scroll>` 로그까지 한 번에 넣는 이유는 그것이 이 Task의 검증
도구이기 때문이다.** TR-M1은 렌더링(Task 3)과 로그(Task 4)를 나눴는데, 그때는
`ink>`가 "렌더러가 이미 동작한 뒤에야 의미가 있는 값"이었다. 여기서는 반대다 —
`scroll>`이 없으면 Task 3이 잘 됐는지를 볼 방법이 없다.

**Task 5(terminfo)가 Task 4 뒤인 이유는 initrd를 건드리기 때문이다.** 스크롤
검사가 통과하는 것을 먼저 보고 나서, 부팅 환경을 바꾸는 변경을 얹는다. 순서를
바꾸면 게이트가 실패했을 때 원인이 둘로 갈린다.

## 이번에 정하는 것 여섯 (design doc이 안 정한 자리)

**1. `max_scrollback_bytes = null`을 함께 준다.**

위 실측 1이 근거다. design 결정 10은 줄 수만 말했고, 그것만으로는 **아무것도
바뀌지 않는다.** design 결정을 뒤집는 것이 아니라 그 결정이 실제로 효력을 갖게
하는 데 필요한 두 번째 값을 채우는 것이다.

**2. `handleKey`의 반환은 `Action` union이고, 화면 크기는 안 들어간다.**

```zig
pub const Scroll = enum { top, bottom, page_up, page_down };
pub const Action = union(enum) { bytes: []const u8, scroll: Scroll };
```

`page_up`이 몇 줄인지를 `input.zig`가 정하지 않는 것이 요점이다. 격자 크기를
아는 것은 `main.zig`이고 그쪽이 `rows` 만큼의 delta로 바꾼다. IP design 결정 6이
"`input.zig`는 `vt.zig`를 import하지 않는다"로 세운 경계와 같은 것이고, TR-M0이
색을 `vt.zig`에서 확정해 넘긴 것과도 같은 경계다.

**3. `readKeys`는 스크롤 동작을 배열로 모아 돌려준다. 마지막 하나만 남기지
않는다.**

PageUp을 누르고 있으면 자동 반복이 **한 번의 `read`에 여러 개를 실어 온다.**
마지막 하나만 보면 몇 번을 눌렀든 한 화면만 올라간다. 저장소는 `State.seq`와
같은 이유로 힙을 안 쓰는 고정 배열(여덟 칸)이다.

같은 이유로 `readKeys`의 루프 조건에서 `written < out.len`을 뺀다. 지금은 바이트
버퍼가 차면 **이벤트 처리 자체가 멈추는데**, 그러면 뒤따라온 스크롤 키가 통째로
사라진다.

**4. 스크롤 키는 Cmd·Option보다 약하다.**

`chord()`의 Meta·Alt 분기는 조합이 표에 없어도 `null`을 돌려주며 `chord` 전체를
끝낸다. 그래서 Shift 분기를 맨 뒤에 두면 **Cmd+Shift+PageUp은 스크롤하지 않고 맨
PageUp이 된다.** 임의의 선택이지만 결정적이고, Cmd는 `project_copy_mode`가
예약한 자리라 여기서 뜻을 더하지 않는다. 이 성질을 `input_test`가 못 박는다.

**5. `scroll>` 로그는 매 프레임 찍는다.**

```
terminal: scroll> total=N offset=M len=L
```

`font>`처럼 "바뀌었을 때만"으로 하면 게이트가 `tail -n 1`로 **현재** 상태를 읽을
수 없어진다. "바닥에 그대로 있다"도 검사해야 하는 사실이라(결정 13), 매번
찍어야 마지막 줄이 곧 지금이다.

**화면에는 스크롤바를 그리지 않는다.** design의 "비워 두는 자리"가
"`PageList.scrollbar()`가 값을 주지만 화면에 그리지 않는다. TR-M2에서 로그로만
찍을지도 그때 정한다"고 남긴 항목이고, **로그로만 찍는 쪽으로 정한다.** 그리려면
격자 바깥 여백에 픽셀을 칠하는 코드가 새로 필요한데, 그것이 증명하는 것은 이미
`scroll>`이 증명하고 있다. 눈으로 보는 사람이 생기면 그때 더한다.

**6. 게이트는 `seq 200`을 치고, 위치와 화면 내용을 따로 본다.**

`seq 200`은 8타에 끝나고 fish의 함수라 `PATH`가 비어 있어도 된다(실측 7). 200을
고른 이유는 **history가 47줄(한 화면)보다 넉넉히 커야** `.top`과 `page_up`이
서로 다른 자리로 가기 때문이다 — 60줄이면 한 번의 `page_up`이 맨 위에 닿아
버려서 두 키를 구분할 수 없다. 1000줄 한도에는 한참 못 미치므로 게이트에서
가지치기가 일어나지 않는다.

화면 내용은 **`| 1 |`이 한 줄 전체와 일치한다**는 성질로 본다. `dumpScreen`이
행 사이에 ` | `를 넣으므로 숫자 하나뿐인 줄은 이 형태로만 나타나고, `10`이나
`21`에는 걸리지 않는다. 첫 행에는 앞쪽 구분자가 없으므로 `screen> 1 |` 형태도
함께 본다.

---

## Task 1: `vt.zig`에 스크롤백 한도와 스크롤 API를 넣는다

**Files:**
- Modify: `terminal/src/vt.zig` (`init`의 `Terminal.init` 인자, 파일 끝에 메서드 넷)
- Test: `terminal/src/vt_test.zig`

부팅 없이 끝난다. design 결정 10과 위 "이번에 정하는 것 1".

- [ ] **Step 1: 실패하는 검사를 먼저 쓴다**

`terminal/src/vt_test.zig`의 **맨 위**(`const vt = @import("vt.zig");` 다음 줄)에
헬퍼를 하나 넣는다.

**넣을 것:**

```zig

/// 한 행의 글자만 이어 붙인다. "화면이 정말 달라졌는가"를 비교하는 데 쓴다.
///
/// 위치 숫자(`scrollbar()`)만 보면 **뷰포트는 움직였는데 화면은 그대로인**
/// 상태를 못 잡는다. 그것이 정확히 `cells()`가 뷰포트를 안 따라갈 때의
/// 증상이라 여기서 따로 본다.
fn rowText(cells: []const vt.CellGlyph, row: u16, buf: []u8) []const u8 {
    var n: usize = 0;
    for (cells) |cell| {
        if (cell.row != row) continue;
        if (cell.codepoint == 0) continue;
        const len = std.unicode.utf8Encode(@intCast(cell.codepoint), buf[n..]) catch continue;
        n += len;
    }
    return buf[0..n];
}
```

그리고 같은 파일 맨 끝의 `std.debug.print("PASS\n", .{});` **앞에** 아래를 넣는다.

**넣을 것:**

```zig

    // ── TR-M2: 스크롤백 ───────────────────────────────────────────────
    //
    // 격자를 155x47로 잡는 이유는 **게이트가 실제로 쓰는 크기**이기 때문이다
    // (프레임버퍼 1280x800, 여백 20, 셀 8x16). 가지치기가 페이지 통째로
    // 일어나므로 한 페이지에 몇 줄이 들어가는지가 cols에 달려 있고, 다른
    // 크기로 재면 아래 단언의 여유폭이 뜻을 잃는다.
    const big = try vt.Screen.init(init.io, init.gpa, 155, 47);
    defer big.deinit();

    var line: [32]u8 = undefined;
    var fed: usize = 1;
    while (fed <= 2000) : (fed += 1) {
        big.feed(std.fmt.bufPrint(&line, "L{d}\r\n", .{fed}) catch unreachable);
    }

    var big_buf: [155 * 47]vt.CellGlyph = undefined;
    var text_a: [512]u8 = undefined;
    var text_b: [512]u8 = undefined;

    // ── 1. 한도가 정말 효력을 갖는가 ──────────────────────────────────
    //
    // **design 결정 10이 말한 max_scrollback_lines만으로는 아무 일도
    // 일어나지 않는다.** 기본 max_scrollback_bytes(10,000)가 먼저 걸려서
    // history가 454줄에서 멈춘다 — 2026-08-23에 실측한 값이다. 아래쪽 경계
    // 700이 그 옛 동작을 막는 자리다.
    //
    // 754가 1000이 아닌 것은 정상이다. 가지치기가 페이지 통째로 일어나고
    // (155칸에서 한 페이지가 약 286줄), 1000을 넘는 순간 한 페이지가 통째로
    // 사라져 754로 떨어진다.
    const filled = big.scrollbar();
    const history = filled.total - filled.len;
    std.debug.print("vt_test: history={d} rows (total={d} offset={d} len={d})\n", .{
        history, filled.total, filled.offset, filled.len,
    });
    if (history <= 700 or history > 1000) {
        std.debug.print("FAIL: history {d} rows is outside 700..1000\n", .{history});
        return error.ScrollbackLimitWrong;
    }
    std.debug.print("vt_test: 스크롤백 한도가 효력을 갖는다 OK\n", .{});

    // ── 2. 새 출력 뒤에는 바닥에 있다 ─────────────────────────────────
    //
    // "바닥"의 정의를 여기서 못 박는다. 아래 검사들과 게이트가 전부 이
    // 식(offset == total - len)을 쓴다.
    if (filled.offset != filled.total - filled.len) {
        std.debug.print("FAIL: 먹인 직후인데 바닥이 아니다 (offset={d}, expected {d})\n", .{
            filled.offset, filled.total - filled.len,
        });
        return error.NotAtBottom;
    }
    std.debug.print("vt_test: 먹인 직후에는 바닥에 있다 OK\n", .{});

    // ── 3. .top이 뷰포트를 옮기고 cells()가 따라간다 ──────────────────
    //
    // 위치와 화면을 **따로** 본다. offset만 보면 뷰포트는 움직였는데
    // cells()가 옛 자리를 그대로 읽는 상태를 못 잡는다.
    const at_bottom = try big.cells(&big_buf);
    const bottom_row0 = rowText(at_bottom, 0, &text_a);

    big.scrollToTop();
    const at_top_sb = big.scrollbar();
    if (at_top_sb.offset != 0) {
        std.debug.print("FAIL: .top 뒤에 offset={d} (expected 0)\n", .{at_top_sb.offset});
        return error.TopDidNotScroll;
    }
    const at_top = try big.cells(&big_buf);
    const top_row0 = rowText(at_top, 0, &text_b);
    if (std.mem.eql(u8, top_row0, bottom_row0)) {
        std.debug.print("FAIL: offset은 0인데 화면 첫 줄이 그대로다 ('{s}')\n", .{top_row0});
        return error.CellsDidNotFollowViewport;
    }
    std.debug.print("vt_test: .top이 뷰포트를 옮기고 cells()가 따라간다 OK ('{s}' -> '{s}')\n", .{
        bottom_row0, top_row0,
    });

    // ── 4. .bottom과 delta ────────────────────────────────────────────
    big.scrollToBottom();
    const back = big.scrollbar();
    if (back.offset != back.total - back.len) {
        std.debug.print("FAIL: .bottom 뒤에 offset={d} (expected {d})\n", .{
            back.offset, back.total - back.len,
        });
        return error.BottomDidNotScroll;
    }
    big.scrollByRows(-47);
    const up = big.scrollbar();
    if (up.offset != back.offset - 47) {
        std.debug.print("FAIL: delta -47 뒤에 offset={d} (expected {d})\n", .{
            up.offset, back.offset - 47,
        });
        return error.DeltaDidNotScroll;
    }
    std.debug.print("vt_test: .bottom과 delta가 정확히 움직인다 OK\n", .{});

    // ── 5. 새 출력은 뷰포트를 **안** 내린다 (design 결정 13의 근거) ────
    //
    // 이 단언이 통과한다는 것은 라이브러리가 그 일을 해 주지 않는다는 뜻이고,
    // 그래서 main.zig가 feed 직후에 scrollToBottom()을 불러야 한다. 여기가
    // 뒤집히면(라이브러리가 저절로 내려오면) 결정 13의 코드는 필요 없어지므로,
    // 그때는 plan을 다시 읽어야 한다.
    //
    // 200줄만 먹인 새 화면을 쓰는 이유는 위 big이 이미 한도에 걸려 있어서다.
    // 한도에 걸린 상태로 더 먹이면 가지치기가 일어나 행 번호 자체가 밀리고,
    // 그러면 이 검사가 무엇을 보는지 흐려진다.
    const fresh = try vt.Screen.init(init.io, init.gpa, 155, 47);
    defer fresh.deinit();
    var more: usize = 1;
    while (more <= 200) : (more += 1) {
        fresh.feed(std.fmt.bufPrint(&line, "M{d}\r\n", .{more}) catch unreachable);
    }
    fresh.scrollByRows(-47);
    const before_feed = fresh.scrollbar();
    const before_cells = try fresh.cells(&big_buf);
    const before_row0 = rowText(before_cells, 0, &text_a);

    fresh.feed("NEW\r\nNEW\r\nNEW\r\n");
    const after_cells = try fresh.cells(&big_buf);
    const after_row0 = rowText(after_cells, 0, &text_b);
    if (!std.mem.eql(u8, before_row0, after_row0)) {
        std.debug.print(
            "FAIL: 새 출력이 뷰포트를 저절로 내렸다 ('{s}' -> '{s}'). 결정 13을 다시 볼 것\n",
            .{ before_row0, after_row0 },
        );
        return error.ViewportMovedByItself;
    }
    std.debug.print(
        "vt_test: 새 출력은 뷰포트를 안 내린다 OK (offset={d}에서 '{s}' 그대로)\n",
        .{ before_feed.offset, after_row0 },
    );

    // 그리고 우리가 부르면 내려온다.
    fresh.scrollToBottom();
    const snapped = fresh.scrollbar();
    if (snapped.offset != snapped.total - snapped.len) {
        std.debug.print("FAIL: scrollToBottom 뒤에 offset={d} (expected {d})\n", .{
            snapped.offset, snapped.total - snapped.len,
        });
        return error.SnapFailed;
    }
    std.debug.print("vt_test: 우리가 부르면 바닥으로 돌아온다 OK\n", .{});
```

- [ ] **Step 2: 실패하는 것을 확인한다**

Claude가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && zig build test' 2>&1 | tail -20
```

기대: **컴파일 에러.** `vt.Screen`에 `scrollbar`가 없다는 내용이다
(`no field or member function named 'scrollbar' in 'vt.Screen'`). 이것이 옳은
실패다.

- [ ] **Step 3: `vt.zig`에 한도를 준다**

`terminal/src/vt.zig`의 현재 `:64-73`이 이렇다.

**지울 것:**

```zig
            .term = try .init(io, alloc, .{
                .cols = cols,
                .rows = rows,
                .colors = .{
```

**넣을 것:**

```zig
            .term = try .init(io, alloc, .{
                .cols = cols,
                .rows = rows,
                // 스크롤백 한도(design 결정 10). **두 값을 함께 줘야 한다.**
                //
                // 결정 10은 max_scrollback_lines만 말했는데, 그것만 주면
                // 아무것도 바뀌지 않는다 — 기본 max_scrollback_bytes(10,000)가
                // 먼저 걸려서 155x47 격자에서 history가 454줄에 멈춘다
                // (2026-08-23 실측). 효력 있는 한도는 `max(준 값, 활성 영역을
                // 담을 최소값)`이라(PageList.Limits.max) 10,000바이트는 처음부터
                // 무시되고 있었다.
                //
                // 바이트가 아니라 줄로 세는 이유는 그것이 사람이 생각하는
                // 단위이고, 게이트가 "N줄 찍고 올라가서 첫 줄을 본다"로
                // 검사하기 쉽기 때문이다. 실제로 남는 history는 754~1000줄을
                // 오간다 — 가지치기가 페이지 통째로 일어나기 때문이고,
                // 1.15MB라 128MB 게스트가 감당한다.
                .max_scrollback_bytes = null,
                .max_scrollback_lines = 1000,
                .colors = .{
```

- [ ] **Step 4: `vt.zig`에 스크롤 API를 넣는다**

`terminal/src/vt.zig`의 `defaultBg` 함수 **다음**, `};`(Screen 구조체를 닫는 줄)
**앞에** 아래를 넣는다.

**넣을 것:**

```zig

    /// 뷰포트가 스크롤백의 어디에 있는지.
    ///
    /// `total`은 스크롤 가능한 전체 행 수, `offset`은 뷰포트 맨 윗줄이 그중
    /// 몇 번째인가, `len`은 언제나 `rows`다. **"바닥에 있다"는
    /// `offset == total - len`이다.**
    ///
    /// 라이브러리 타입을 그대로 흘려보내지 않고 우리 struct로 옮겨 담는
    /// 이유는 TR-M0이 색에 대해 한 것과 같다(design 결정 1) — `main.zig`가
    /// `ghostty-vt`의 타입을 배우지 않게 한다.
    pub const Scrollbar = struct {
        total: usize,
        offset: usize,
        len: usize,
    };

    pub fn scrollbar(self: *Screen) Scrollbar {
        const sb = self.term.screens.active.pages.scrollbar();
        return .{ .total = sb.total, .offset = sb.offset, .len = sb.len };
    }

    /// 스크롤백의 맨 위로.
    pub fn scrollToTop(self: *Screen) void {
        self.term.scrollViewport(.top);
    }

    /// 활성 영역의 맨 위로 = 평소 상태로.
    ///
    /// **PTY 출력이 도착할 때마다 불러야 한다**(design 결정 13). 라이브러리는
    /// 그 일을 해 주지 않는다 — 올라간 상태에서 출력을 먹여도 뷰포트가
    /// 그대로라는 것을 2026-08-23에 실측했고, `vt_test`가 그 사실을 못 박고
    /// 있다.
    pub fn scrollToBottom(self: *Screen) void {
        self.term.scrollViewport(.bottom);
    }

    /// 상대 이동. **위가 음수다.**
    ///
    /// 몇 줄이 한 화면인지는 여기서 정하지 않는다. 격자 크기를 아는 것은
    /// `main.zig`이고, 그쪽이 `rows`를 넘겨준다.
    pub fn scrollByRows(self: *Screen, delta: isize) void {
        self.term.scrollViewport(.{ .delta = delta });
    }
```

- [ ] **Step 5: 검사가 통과하는지 본다**

Claude가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && zig build test' 2>&1 | tail -25
```

기대 출력에 이 줄들이 있어야 한다.

```
vt_test: history=754 rows (total=801 offset=754 len=47)
vt_test: 스크롤백 한도가 효력을 갖는다 OK
vt_test: 먹인 직후에는 바닥에 있다 OK
vt_test: .top이 뷰포트를 옮기고 cells()가 따라간다 OK ('...' -> '...')
vt_test: .bottom과 delta가 정확히 움직인다 OK
vt_test: 새 출력은 뷰포트를 안 내린다 OK (offset=... 에서 '...' 그대로)
vt_test: 우리가 부르면 바닥으로 돌아온다 OK
PASS
```

**`history`가 454로 나오면 `max_scrollback_bytes = null`이 안 들어간 것이다.**
그 값이 이 milestone의 첫 단추다.

**"새 출력은 뷰포트를 안 내린다"에서 실패하면 plan을 멈추고 다시 읽는다.**
라이브러리가 저절로 내려온다는 뜻이고, 그러면 Task 3의 `scrollToBottom()` 호출과
design 결정 13이 필요 없어진다.

`input_test`와 `font_test`의 기존 출력도 함께 나와야 한다. `main.zig`는 아직
안 고쳤지만 이 Task는 `main.zig`를 안 건드리므로 `zig build`도 통과한다.

- [ ] **Step 6: 커밋**

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Give the terminal a scrollback worth scrolling into"
```

---

## Task 2: `handleKey`의 반환을 "바이트열 또는 동작"으로 넓힌다

**Files:**
- Modify: `terminal/src/input.zig` (타입 셋 추가, `State` 필드 하나, `chord`,
  `handleKey`, `readKeys`)
- Test: `terminal/src/input_test.zig` (헬퍼 둘, 검사 블록 하나)

design 결정 11·12와 위 "이번에 정하는 것 2·3·4". 부팅 없이 끝난다.

- [ ] **Step 1: 실패하는 검사를 먼저 쓴다**

`terminal/src/input_test.zig`의 현재 `:20-34`가 이렇다.

**지울 것:**

```zig
fn expectCtx(
    state: *input.State,
    ctx: input.Context,
    code: u16,
    value: i32,
    want: []const u8,
) !void {
    const got = state.handleKey(code, value, ctx);
    if (std.mem.eql(u8, got, want)) return;
    std.debug.print(
        "FAIL: code={d} value={d} ckm={} -> got={any}, want={any}\n",
        .{ code, value, ctx.cursor_keys, got, want },
    );
    return error.UnexpectedBytes;
}
```

**넣을 것:**

```zig
/// TR-M2부터 handleKey는 바이트열이 아니라 `Action`을 돌려준다. 이 파일의
/// 검사 대부분은 여전히 바이트를 보므로, **"바이트가 아닌 것이 왔다"를
/// 실패로 취급하는 것**이 이 헬퍼의 새 일이다. 그냥 무시하면 스크롤 키가
/// 실수로 PTY 쪽 표에 들어갔을 때 검사가 조용히 통과한다.
fn expectCtx(
    state: *input.State,
    ctx: input.Context,
    code: u16,
    value: i32,
    want: []const u8,
) !void {
    switch (state.handleKey(code, value, ctx)) {
        .bytes => |bytes| {
            if (std.mem.eql(u8, bytes, want)) return;
            std.debug.print(
                "FAIL: code={d} value={d} ckm={} -> got={any}, want={any}\n",
                .{ code, value, ctx.cursor_keys, bytes, want },
            );
            return error.UnexpectedBytes;
        },
        .scroll => |s| {
            std.debug.print(
                "FAIL: code={d} value={d} -> got scroll .{s}, want bytes {any}\n",
                .{ code, value, @tagName(s), want },
            );
            return error.UnexpectedScroll;
        },
    }
}

/// 스크롤 동작을 기대하는 검사. **바이트가 오면 실패다** — 그것이 곧
/// "스크롤 키가 PTY로 샜다"는 뜻이고, design 결정 11이 막으려는 바로 그
/// 상황이다.
fn expectScroll(
    state: *input.State,
    code: u16,
    value: i32,
    want: input.Scroll,
) !void {
    switch (state.handleKey(code, value, .{})) {
        .scroll => |s| {
            if (s == want) return;
            std.debug.print(
                "FAIL: code={d} -> got scroll .{s}, want .{s}\n",
                .{ code, @tagName(s), @tagName(want) },
            );
            return error.WrongScroll;
        },
        .bytes => |bytes| {
            std.debug.print(
                "FAIL: code={d} -> got bytes {any}, want scroll .{s}\n",
                .{ code, bytes, @tagName(want) },
            );
            return error.ExpectedScroll;
        },
    }
}
```

그리고 같은 파일의 `// ── 여전히 안 하는 것 ─...` 블록(현재 `:296`) **앞에**
아래를 넣는다.

**넣을 것:**

```zig
    // ── Shift 스크롤 (TR-M2, design 결정 11·12) ─────────────────────────
    //
    // 여기서 처음으로 키가 **바이트가 아닌 것**을 돌려준다. IP-M2까지
    // handleKey의 반환은 []const u8 하나였고, 그래서 "PTY로 보내지 않고
    // 우리가 처리한다"를 표현할 방법이 아예 없었다.
    //
    // 몇 줄이 한 화면인지는 여기 안 나온다. input.zig는 격자 크기를 모르고,
    // page_up을 rows 만큼의 delta로 바꾸는 것은 main.zig의 일이다.
    try expect(&state, K.KEY_LEFTSHIFT, 1, "");
    try expectScroll(&state, K.KEY_PAGEUP, 1, .page_up);
    try expectScroll(&state, K.KEY_PAGEDOWN, 1, .page_down);
    try expectScroll(&state, K.KEY_HOME, 1, .top);
    try expectScroll(&state, K.KEY_END, 1, .bottom);

    // 자동 반복도 스크롤한다 — 누르고 있으면 계속 올라가야 한다.
    try expectScroll(&state, K.KEY_PAGEUP, 2, .page_up);
    // 뗄 때는 여전히 아무 일도 없다.
    try expect(&state, K.KEY_PAGEUP, 0, "");

    // Shift+표에 없는 특수키는 평소대로 PTY로 나간다.
    try expect(&state, K.KEY_DELETE, 1, "\x1b[3~");
    try expect(&state, K.KEY_LEFTSHIFT, 0, "");

    // **Shift를 떼면 넷 다 원래대로 돌아온다.** 이 줄들이 없으면 "스크롤이
    // 되는가"만 보고 "안 되어야 할 때 원래대로인가"를 안 보게 된다. Home/End는
    // 특히 중요하다 — 셸의 줄 편집이 쓰는 키다.
    try expect(&state, K.KEY_PAGEUP, 1, "\x1b[5~");
    try expect(&state, K.KEY_PAGEDOWN, 1, "\x1b[6~");
    try expect(&state, K.KEY_HOME, 1, "\x1b[H");
    try expect(&state, K.KEY_END, 1, "\x1b[F");

    // 오른쪽 Shift도 같다. 좌우를 따로 추적하는 성질은 그대로다.
    try expect(&state, K.KEY_RIGHTSHIFT, 1, "");
    try expectScroll(&state, K.KEY_PAGEUP, 1, .page_up);
    try expect(&state, K.KEY_RIGHTSHIFT, 0, "");

    // ── Cmd가 Shift를 이긴다 ────────────────────────────────────────────
    //
    // chord가 Meta를 먼저 보고, 조합이 표에 없으면 null로 chord 전체를
    // 끝내기 때문이다. 그래서 Cmd+Shift+PageUp은 스크롤하지 않고 맨 PageUp이
    // 된다. 임의의 선택이지만 결정적이어야 하고, Cmd는 project_copy_mode가
    // 예약한 자리라 여기서 뜻을 더하지 않는다.
    try expect(&state, K.KEY_LEFTMETA, 1, "");
    try expect(&state, K.KEY_LEFTSHIFT, 1, "");
    try expect(&state, K.KEY_PAGEUP, 1, "\x1b[5~");
    try expect(&state, K.KEY_LEFTSHIFT, 0, "");
    try expect(&state, K.KEY_LEFTMETA, 0, "");

    // Option도 마찬가지다.
    try expect(&state, K.KEY_LEFTALT, 1, "");
    try expect(&state, K.KEY_LEFTSHIFT, 1, "");
    try expect(&state, K.KEY_HOME, 1, "\x1b[H");
    try expect(&state, K.KEY_LEFTSHIFT, 0, "");
    try expect(&state, K.KEY_LEFTALT, 0, "");
```

마지막으로 그 아래 "여전히 안 하는 것" 블록의 주석 한 줄을 고친다. Shift+방향키는
그대로지만 Shift+Home/End는 이제 뜻이 생겼기 때문이다.

**지울 것:**

```zig
    // Ctrl+방향키(`ESC [ 1 ; 5 D`)와 Shift+방향키는 **IP-M2도 하지 않는다.**
```

**넣을 것:**

```zig
    // Ctrl+방향키(`ESC [ 1 ; 5 D`)와 Shift+방향키는 **TR-M2도 하지 않는다.**
    // TR-M2가 뜻을 준 것은 Shift+PageUp/PageDown/Home/End 넷뿐이고, 방향키
    // 자체는 여전히 맨 시퀀스로 나간다.
```

- [ ] **Step 2: 실패하는 것을 확인한다**

Claude가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && zig build test' 2>&1 | tail -20
```

기대: **컴파일 에러.** `input.Scroll`이 없다는 내용이거나(`no member named
'Scroll'`), `handleKey`의 반환값에 `switch`를 걸 수 없다는 내용이다. 이것이 옳은
실패다.

- [ ] **Step 3: `input.zig`에 타입 셋을 넣는다**

`terminal/src/input.zig`의 `Context` 구조체가 끝나는 `};`(현재 `:131`) **다음**,
`/// ESC(0x1b).` 주석 **앞에** 아래를 넣는다.

**넣을 것:**

```zig

/// 스크롤백을 움직이는 동작(design 결정 12).
///
/// **여기에 화면 크기가 없는 것이 요점이다.** `page_up`이 몇 줄인지는
/// `input.zig`가 알 수 없고 알 필요도 없다 — 격자 크기를 아는 것은
/// `main.zig`이고, 그쪽이 이 값을 `rows` 만큼의 delta로 바꾼다. design doc
/// 결정 6이 "input.zig는 vt.zig를 import하지 않는다"로 세운 경계와 같은
/// 것이고, TR-M0이 색을 vt.zig에서 확정해 넘긴 것과도 같다.
pub const Scroll = enum {
    /// 스크롤백의 맨 위
    top,
    /// 활성 영역의 맨 아래 = 평소 상태
    bottom,
    /// 한 화면 위
    page_up,
    /// 한 화면 아래
    page_down,
};

/// 키 하나가 만드는 결과.
///
/// IP 시절 이 자리는 `[]const u8` 하나였다. 보낼 것이 바이트뿐이었기
/// 때문이다. **스크롤 키는 바이트가 아니라 동작이고 PTY로 새어 나가면 안
/// 되므로**, 그 구분을 표현할 수 있게 넓힌다(design 결정 11).
///
/// `project_copy_mode`가 "IP의 dispatch 단계가 그대로 진입점"이라고 적어 둔
/// 자리가 이곳이다. 이번에 넓히는 것은 **통로**이고 모드 상태는 넣지
/// 않는다 — copy mode가 나중에 이 union에 자기 variant를 더한다.
pub const Action = union(enum) {
    /// PTY로 보낼 바이트열. 빈 슬라이스는 "보낼 것이 없다"는 뜻이다.
    bytes: []const u8,
    /// 우리가 처리할 동작. **PTY로 보내지 않는다.**
    scroll: Scroll,
};

/// 한 번의 read가 만든 것 전부.
pub const Keys = struct {
    bytes: []const u8,
    /// **순서대로 적용해야 한다.** PageUp을 누르고 있으면 자동 반복이 한
    /// 번의 read에 여러 개를 실어 오는데, 마지막 하나만 보면 몇 번을 눌렀든
    /// 한 화면만 올라간다.
    scrolls: []const Scroll,
};
```

- [ ] **Step 4: `none` 옆에 `nothing`을 놓고 `State`에 배열을 더한다**

`terminal/src/input.zig`의 현재 `:190-191`이 이렇다.

**지울 것:**

```zig
/// "보낼 것이 없다"를 뜻하는 빈 슬라이스. IP-M0 전에는 `null`이 이 자리였다.
const none: []const u8 = &[_]u8{};
```

**넣을 것:**

```zig
/// "보낼 것이 없다"를 뜻하는 빈 슬라이스. IP-M0 전에는 `null`이 이 자리였다.
const none: []const u8 = &[_]u8{};

/// 같은 뜻을 Action으로 감싼 것. TR-M2 전에는 `none` 자체가 반환값이었다.
const nothing: Action = .{ .bytes = none };
```

그리고 `State`의 `seq` 필드(현재 `:224`) **다음**, `fn shifted` **앞에** 아래를
넣는다.

**넣을 것:**

```zig

    /// 한 번의 read에서 나온 스크롤 동작의 저장소. `seq`와 같은 이유로 힙을
    /// 쓰지 않는다.
    ///
    /// 여덟을 넘기면 나머지는 버린다. 자동 반복이 그만큼 쌓이려면 poll이
    /// 여덟 프레임을 놓쳐야 하고, 그런 상황에서 한 화면 덜 올라가는 것은
    /// 문제가 아니다 — out이 모자랄 때 바이트를 버리는 것과 같은 판단이다.
    scrolls: [8]Scroll = undefined,
```

- [ ] **Step 5: `chord`에 Shift 분기를 더한다**

`terminal/src/input.zig`의 현재 `:312-338`이 이렇다.

**지울 것:**

```zig
    fn chord(self: *State, code: u16) ?[]const u8 {
        if (self.metaed()) {
            // Cmd 계열은 제어 문자 한 바이트다. 0x01이 beginning-of-line인
            // 이유는 그것이 readline의 기본 바인딩이기 때문이지 Cmd와 A
            // 사이에 무슨 관계가 있어서가 아니다.
            return switch (code) {
                c.KEY_LEFT => self.one(0x01), // Ctrl+A: beginning-of-line
                c.KEY_RIGHT => self.one(0x05), // Ctrl+E: end-of-line
                // 0x15는 bash에서 커서 앞까지, zsh에서는 줄 전체를 지운다.
                // macOS의 Cmd+Backspace는 bash 쪽이다 — 셸을 바꿔 끼울 수
                // 있는 시스템에서 이 어긋남은 A안을 고른 대가이고, 감추지
                // 않고 여기 적어둔다(design doc 결정 8).
                c.KEY_BACKSPACE => self.one(0x15),
                else => null,
            };
        }
        if (self.alted()) {
            return switch (code) {
                c.KEY_LEFT => self.escPrefixed('b'), // backward-word
                c.KEY_RIGHT => self.escPrefixed('f'), // forward-word
                c.KEY_BACKSPACE => self.escPrefixed(0x7f), // backward-kill-word
                c.KEY_DELETE => self.escPrefixed('d'), // kill-word
                else => null,
            };
        }
        return null;
    }
```

**넣을 것:**

```zig
    fn chord(self: *State, code: u16) ?Action {
        if (self.metaed()) {
            // Cmd 계열은 제어 문자 한 바이트다. 0x01이 beginning-of-line인
            // 이유는 그것이 readline의 기본 바인딩이기 때문이지 Cmd와 A
            // 사이에 무슨 관계가 있어서가 아니다.
            return switch (code) {
                c.KEY_LEFT => .{ .bytes = self.one(0x01) }, // beginning-of-line
                c.KEY_RIGHT => .{ .bytes = self.one(0x05) }, // end-of-line
                // 0x15는 bash에서 커서 앞까지, zsh에서는 줄 전체를 지운다.
                // macOS의 Cmd+Backspace는 bash 쪽이다 — 셸을 바꿔 끼울 수
                // 있는 시스템에서 이 어긋남은 A안을 고른 대가이고, 감추지
                // 않고 여기 적어둔다(design doc 결정 8).
                c.KEY_BACKSPACE => .{ .bytes = self.one(0x15) },
                else => null,
            };
        }
        if (self.alted()) {
            return switch (code) {
                c.KEY_LEFT => .{ .bytes = self.escPrefixed('b') }, // backward-word
                c.KEY_RIGHT => .{ .bytes = self.escPrefixed('f') }, // forward-word
                c.KEY_BACKSPACE => .{ .bytes = self.escPrefixed(0x7f) }, // backward-kill-word
                c.KEY_DELETE => .{ .bytes = self.escPrefixed('d') }, // kill-word
                else => null,
            };
        }
        // Shift 계열 — 스크롤(TR design 결정 12). **바이트가 아니라 동작이다.**
        //
        // Cmd·Option보다 **뒤에** 있는 것에 뜻이 있다. 위 두 분기는 조합이
        // 표에 없어도 null을 돌려주며 chord 전체를 끝내므로, Cmd+Shift+PageUp은
        // 스크롤하지 않고 맨 PageUp이 된다. 임의의 선택이지만 결정적이고,
        // Cmd는 project_copy_mode가 예약한 자리라 여기서 뜻을 더하지 않는다.
        //
        // Shift+PageUp을 고른 이유는 xterm·리눅스 콘솔·tmux가 전부 쓰는
        // 형태라서다. Mac 노트북의 Fn+↑도 evdev에는 KEY_PAGEUP으로 도착하므로
        // 키보드 종류와 무관하게 동작한다.
        if (self.shifted()) {
            return switch (code) {
                c.KEY_PAGEUP => .{ .scroll = .page_up },
                c.KEY_PAGEDOWN => .{ .scroll = .page_down },
                c.KEY_HOME => .{ .scroll = .top },
                c.KEY_END => .{ .scroll = .bottom },
                else => null,
            };
        }
        return null;
    }
```

- [ ] **Step 6: `handleKey`의 반환 타입을 바꾼다**

`terminal/src/input.zig`의 현재 `:340-414`가 이렇다. 바뀌는 것은 **시그니처와
반환문뿐**이고 로직은 그대로다.

**지울 것:**

```zig
    /// EV_KEY 이벤트 하나를 처리한다.
    /// value: 0=뗌, 1=누름, 2=자동 반복.
    /// PTY로 보낼 바이트열을 반환한다. 보낼 것이 없으면 빈 슬라이스다.
    pub fn handleKey(self: *State, raw_code: u16, value: i32, ctx: Context) []const u8 {
```

**넣을 것:**

```zig
    /// EV_KEY 이벤트 하나를 처리한다.
    /// value: 0=뗌, 1=누름, 2=자동 반복.
    ///
    /// TR-M2부터 반환이 `Action`이다. 그전에는 `[]const u8` 하나였고, 그래서
    /// "PTY로 보내지 않고 우리가 처리한다"를 표현할 방법이 없었다
    /// (design 결정 11).
    pub fn handleKey(self: *State, raw_code: u16, value: i32, ctx: Context) Action {
```

그리고 같은 함수 안에서 반환문 열둘을 바꾼다.

**지울 것:**

```zig
        switch (code) {
            c.KEY_LEFTSHIFT => {
                self.shift_left = value != 0;
                return none;
            },
            c.KEY_RIGHTSHIFT => {
                self.shift_right = value != 0;
                return none;
            },
            c.KEY_LEFTCTRL => {
                self.ctrl_left = value != 0;
                return none;
            },
            c.KEY_RIGHTCTRL => {
                self.ctrl_right = value != 0;
                return none;
            },
            c.KEY_LEFTALT => {
                self.alt_left = value != 0;
                return none;
            },
            c.KEY_RIGHTALT => {
                self.alt_right = value != 0;
                return none;
            },
            c.KEY_LEFTMETA => {
                self.meta_left = value != 0;
                return none;
            },
            c.KEY_RIGHTMETA => {
                self.meta_right = value != 0;
                return none;
            },
            else => {},
        }
        // 뗄 때는 아무것도 보내지 않는다. 누름(1)과 자동 반복(2)만 문자를 만든다.
        if (value == 0) return none;

        // 2번 단계 — 조합 dispatch. 특수키 조회보다 **먼저**다.
        // 뒤에 두면 Cmd+←가 여기 닿기 전에 ESC [ D로 번역돼 새어 나간다.
        if (self.chord(code)) |bytes| return bytes;
```

**넣을 것:**

```zig
        switch (code) {
            c.KEY_LEFTSHIFT => {
                self.shift_left = value != 0;
                return nothing;
            },
            c.KEY_RIGHTSHIFT => {
                self.shift_right = value != 0;
                return nothing;
            },
            c.KEY_LEFTCTRL => {
                self.ctrl_left = value != 0;
                return nothing;
            },
            c.KEY_RIGHTCTRL => {
                self.ctrl_right = value != 0;
                return nothing;
            },
            c.KEY_LEFTALT => {
                self.alt_left = value != 0;
                return nothing;
            },
            c.KEY_RIGHTALT => {
                self.alt_right = value != 0;
                return nothing;
            },
            c.KEY_LEFTMETA => {
                self.meta_left = value != 0;
                return nothing;
            },
            c.KEY_RIGHTMETA => {
                self.meta_right = value != 0;
                return nothing;
            },
            else => {},
        }
        // 뗄 때는 아무것도 보내지 않는다. 누름(1)과 자동 반복(2)만 문자를 만든다.
        if (value == 0) return nothing;

        // 2번 단계 — 조합 dispatch. 특수키 조회보다 **먼저**다.
        // 뒤에 두면 Cmd+←가 여기 닿기 전에 ESC [ D로 번역돼 새어 나가고,
        // TR-M2부터는 Shift+PageUp이 ESC [ 5 ~ 로 번역돼 새어 나간다.
        if (self.chord(code)) |action| return action;
```

이어서 같은 함수의 나머지 반환문 넷이다.

**지울 것:**

```zig
        if (specialKey(code)) |key| return self.escape(key, ctx);

        if (code >= keymap.len) return none;

        const ch = keymap[code][if (self.shifted()) 1 else 0];
        if (ch == 0) return none;

        // Ctrl이 눌려 있고 이 문자가 마스크 대상이면 제어 문자로 바꾼다.
        // 대상이 아니면(숫자 등) Ctrl을 무시하고 원래 문자를 보낸다.
        if (self.ctrled()) {
            if (control(ch)) |ctl| return self.one(ctl);
        }
        return self.one(ch);
    }
```

**넣을 것:**

```zig
        if (specialKey(code)) |key| return .{ .bytes = self.escape(key, ctx) };

        if (code >= keymap.len) return nothing;

        const ch = keymap[code][if (self.shifted()) 1 else 0];
        if (ch == 0) return nothing;

        // Ctrl이 눌려 있고 이 문자가 마스크 대상이면 제어 문자로 바꾼다.
        // 대상이 아니면(숫자 등) Ctrl을 무시하고 원래 문자를 보낸다.
        if (self.ctrled()) {
            if (control(ch)) |ctl| return .{ .bytes = self.one(ctl) };
        }
        return .{ .bytes = self.one(ch) };
    }
```

- [ ] **Step 7: `readKeys`가 둘 다 돌려준다**

`terminal/src/input.zig`의 현재 `:423-450`이 이렇다.

**지울 것:**

```zig
/// fd에서 한 번 read하고(poll이 읽을 게 있다고 알려준 뒤에만 호출한다),
/// 그 안의 EV_KEY 이벤트들을 문자 바이트로 바꿔 out에 채운다.
pub fn readKeys(self: *State, fd: c_int, out: []u8, ctx: Context) []const u8 {
    const ev_size = @sizeOf(c.struct_input_event);
    var raw: [ev_size * 64]u8 = undefined;

    const n = read(fd, &raw, raw.len);
    if (n <= 0) return out[0..0];

    const count = @as(usize, @intCast(n)) / ev_size;
    var written: usize = 0;
    var i: usize = 0;
    while (i < count and written < out.len) : (i += 1) {
        const ev: *align(1) const c.struct_input_event =
            @ptrCast(&raw[i * ev_size]);
        if (ev.@"type" != c.EV_KEY) continue;
        // 키 하나가 여러 바이트가 될 수 있으므로(IP-M1의 이스케이프 시퀀스)
        // 슬라이스를 통째로 옮긴다. out이 모자라면 거기서 멈춘다 — 다음
        // poll에서 이어지지 않고 버려지지만, out은 64바이트이고 한 번의
        // read에 그만큼의 키가 들어오는 일은 사람 손으로는 일어나지 않는다.
        for (self.handleKey(ev.code, ev.value, ctx)) |byte| {
            if (written >= out.len) break;
            out[written] = byte;
            written += 1;
        }
    }
    return out[0..written];
}
```

**넣을 것:**

```zig
/// fd에서 한 번 read하고(poll이 읽을 게 있다고 알려준 뒤에만 호출한다),
/// 그 안의 EV_KEY 이벤트들을 처리한다. PTY로 보낼 바이트는 out에 채우고,
/// 스크롤 동작은 State의 배열에 모아 둘 다 돌려준다.
///
/// **루프 조건에서 `written < out.len`이 빠진 것이 TR-M2의 변경이다.**
/// 그전에는 바이트 버퍼가 차면 이벤트 처리 자체가 멈췄는데, 그러면 뒤따라온
/// 스크롤 키가 통째로 사라진다. 바이트는 여전히 버려지지만(아래 break),
/// 그것과 "동작을 못 본다"는 다른 종류의 손실이다.
pub fn readKeys(self: *State, fd: c_int, out: []u8, ctx: Context) Keys {
    const ev_size = @sizeOf(c.struct_input_event);
    var raw: [ev_size * 64]u8 = undefined;

    const n = read(fd, &raw, raw.len);
    if (n <= 0) return .{ .bytes = out[0..0], .scrolls = self.scrolls[0..0] };

    const count = @as(usize, @intCast(n)) / ev_size;
    var written: usize = 0;
    var scrolled: usize = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const ev: *align(1) const c.struct_input_event =
            @ptrCast(&raw[i * ev_size]);
        if (ev.@"type" != c.EV_KEY) continue;
        switch (self.handleKey(ev.code, ev.value, ctx)) {
            // 키 하나가 여러 바이트가 될 수 있으므로(IP-M1의 이스케이프
            // 시퀀스) 슬라이스를 통째로 옮긴다. handleKey가 돌려준 슬라이스는
            // State.seq를 가리키고 다음 키가 그것을 덮어쓰므로, **여기서 즉시
            // 복사하는 것이 계약이다.**
            .bytes => |bytes| for (bytes) |byte| {
                if (written >= out.len) break;
                out[written] = byte;
                written += 1;
            },
            // 순서를 지켜 모은다. 자동 반복으로 여러 개가 한 번에 올 수 있고,
            // 마지막 하나만 남기면 몇 번을 눌렀든 한 화면만 올라간다.
            .scroll => |s| if (scrolled < self.scrolls.len) {
                self.scrolls[scrolled] = s;
                scrolled += 1;
            },
        }
    }
    return .{ .bytes = out[0..written], .scrolls = self.scrolls[0..scrolled] };
}
```

- [ ] **Step 8: 검사가 통과하는지 본다**

Claude가 실행한다. **`main.zig`가 아직 옛 `readKeys` 시그니처를 쓰므로
`zig build`(게스트 바이너리)는 막힌다.** `test` step은 `main.zig`를 안 만지므로
통과한다. Task 3이 그것을 고친다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && zig build test' 2>&1 | tail -20
```

기대: `input_test`가 `PASS`로 끝나고, `vt_test`·`font_test`도 그대로 통과한다.

**여기서 `UnexpectedScroll`이 나오면 `chord`의 Shift 분기가 너무 앞에 있다.**
Meta·Alt 분기보다 뒤여야 한다.

- [ ] **Step 9: 커밋**

```bash
git add terminal/src/input.zig terminal/src/input_test.zig
git commit -m "Let a key mean an action instead of bytes"
```

---

## Task 3: 렌더를 루프 끝으로 빼고 스크롤을 잇는다

**Files:**
- Modify: `terminal/src/main.zig` (`dumpInk` 아래에 함수 하나, 루프 변수 하나,
  `while (true)` 블록 전체)

위 실측 5·6과 design 결정 13, "이번에 정하는 것 5". **여기서 스크롤이 처음
동작한다.**

- [ ] **Step 1: `dumpScroll`을 더한다**

`terminal/src/main.zig`의 `dumpInk` 함수가 끝나는 `}`(현재 `:238`) **다음**,
`pub fn main` **앞에** 아래를 넣는다.

**넣을 것:**

```zig

/// 뷰포트가 스크롤백의 어디에 있는지를 찍는다.
///
/// **게이트가 스크롤 위치를 볼 수 있는 유일한 창구다.** 화면 덤프만으로는
/// "올라갔다"와 "출력이 달라졌다"를 가를 수 없다 — 같은 글자가 두 번 나오는
/// 화면이면 둘이 구분되지 않는다. 거꾸로 이 줄만 보면 **뷰포트는 움직였는데
/// 화면은 그대로인** 상태를 못 잡으므로, 게이트는 둘을 나란히 본다.
/// `style>`/`pixel>`이 색을 두 겹으로 보는 것과 같은 구조다(design 결정 7).
///
/// **매 프레임 찍는다.** `font>`처럼 "바뀌었을 때만"으로 하면 게이트가
/// `tail -n 1`로 현재 상태를 읽을 수 없어진다 — "바닥에 그대로 있다"도
/// 검사해야 하는 사실이다(design 결정 13).
fn dumpScroll(screen: *vt.Screen) void {
    const sb = screen.scrollbar();
    std.debug.print("terminal: scroll> total={d} offset={d} len={d}\n", .{
        sb.total, sb.offset, sb.len,
    });
}
```

- [ ] **Step 2: 루프 변수에 `needs_redraw`를 더한다**

`terminal/src/main.zig`의 현재 `:353-356`이 이렇다.

**지울 것:**

```zig
    var last_glyph_count: usize = 0;
    var key_state: input.State = .{};
```

**넣을 것:**

```zig
    var last_glyph_count: usize = 0;
    // TR-M2의 구조 변경. 그전에는 렌더가 PTY 출력 분기 **안에만** 있었다 —
    // 스크롤은 키로 일어나므로 그대로 두면 뷰포트만 움직이고 화면은 안 바뀐다.
    var needs_redraw = false;
    var key_state: input.State = .{};
```

- [ ] **Step 3: 루프 본문을 갈아 끼운다**

`terminal/src/main.zig`의 현재 `:363-428`(`while (true) {`부터 그것을 닫는 `}`까지)
전체를 바꾼다.

**지울 것:**

```zig
    while (true) {
        // -1 = 무한 대기. 이벤트가 없으면 CPU를 전혀 쓰지 않는다.
        const ready = c.poll(&fds, fds.len, -1);
        if (ready < 0) continue; // EINTR 등은 그냥 다시 기다린다

        if (fds[0].revents & c.POLLIN != 0) {
            // DECCKM은 셸이 언제든 켜고 끌 수 있으므로(프롬프트를 그릴 때
            // smkx, 외부 명령을 실행하기 전에 rmkx 하는 식으로 오간다)
            // 캐시하지 않고 **키를 읽는 순간의 값**을 쓴다. packed struct의
            // 비트 읽기 한 번이라 비용이 없다 — design doc 결정 6이 "값으로
            // 넘긴다"를 고르면서 감수하기로 한 대가가 이것이다.
            const ctx = input.Context{
                .cursor_keys = screen.term.modes.get(.cursor_keys),
                // DECCKM과 달리 이 값은 부팅 내내 상수다. 매 키마다 다시
                // 넣는 것은 Context를 한 자리에서 조립하기 위해서일 뿐이다.
                .swap_alt_meta = swap_alt_meta,
            };
            const bytes = input.readKeys(&key_state, keyboard_fd, &key_buf, ctx);
            if (bytes.len > 0) {
                // 앞부분("terminal: key> ")은 input/check.sh가 grep하는
                // 마커라 **그대로 둔다**. 뒤에 decckm을 덧붙이는 이유는
                // design doc 위험 4다 — 게이트가 `ESC O` 경로를 실제로
                // 밟았는지 아니면 `ESC [`만 봤는지를 로그로 알 수 있어야 한다.
                std.debug.print("terminal: key> {d} byte(s) decckm={}\n", .{
                    bytes.len, ctx.cursor_keys,
                });
                pty.write(session.master_fd, bytes);
            }
        }

        // PTY master는 slave가 전부 닫히면 POLLIN이 아니라 POLLHUP을 올린다.
        // 남은 출력이 있으면 POLLIN과 함께 오지만 다 읽고 나면 POLLHUP만
        // 남으므로, POLLIN만 보면 read를 영영 호출하지 못하고 poll이 즉시
        // 반환하는 바쁜 루프에 빠진다. POLLHUP에서도 read를 시도하면 남은
        // 데이터를 먼저 비우고, 비고 나면 read가 EIO를 내 EOF 경로로 간다.
        if (fds[1].revents & (c.POLLIN | c.POLLHUP | c.POLLERR) != 0) {
            const out = pty.readSome(session.master_fd, &pty_buf);
            if (out.len == 0) {
                std.debug.print("terminal: child exited (pty EOF)\n", .{});
                break;
            }
            screen.feed(out);
            const cells = try screen.cells(cell_buf);
            const frame_start = std.Io.Clock.now(.awake, init.io);
            try render(fb, &cache, cells);
            if (!first_frame_timed) {
                first_frame_timed = true;
                std.debug.print("terminal: render> first frame {d}us\n", .{
                    @divTrunc(frame_start.untilNow(init.io, .awake).nanoseconds, 1000),
                });
            }

            dumpScreen(cells);
            // render 뒤에 부른다 — 그 전에 부르면 이전 프레임의 픽셀을 읽는다.
            // 기본 색을 여기 상수로 다시 적지 않고 screen에서 얻는 이유는
            // vt.zig의 defaultFg 주석에 있다.
            dumpStyles(fb, cells, screen.defaultFg(), screen.defaultBg());
            dumpInk(fb, &cache, cells);
            if (cache.count() != last_glyph_count) {
                last_glyph_count = cache.count();
                std.debug.print("terminal: font> {d} glyph(s) cached, {d} bitmap bytes\n", .{
                    last_glyph_count, cache.bitmap_bytes,
                });
            }
        }
    }
```

**넣을 것:**

```zig
    while (true) {
        // -1 = 무한 대기. 이벤트가 없으면 CPU를 전혀 쓰지 않는다.
        const ready = c.poll(&fds, fds.len, -1);
        if (ready < 0) continue; // EINTR 등은 그냥 다시 기다린다

        if (fds[0].revents & c.POLLIN != 0) {
            // DECCKM은 셸이 언제든 켜고 끌 수 있으므로(프롬프트를 그릴 때
            // smkx, 외부 명령을 실행하기 전에 rmkx 하는 식으로 오간다)
            // 캐시하지 않고 **키를 읽는 순간의 값**을 쓴다. packed struct의
            // 비트 읽기 한 번이라 비용이 없다 — design doc 결정 6이 "값으로
            // 넘긴다"를 고르면서 감수하기로 한 대가가 이것이다.
            const ctx = input.Context{
                .cursor_keys = screen.term.modes.get(.cursor_keys),
                // DECCKM과 달리 이 값은 부팅 내내 상수다. 매 키마다 다시
                // 넣는 것은 Context를 한 자리에서 조립하기 위해서일 뿐이다.
                .swap_alt_meta = swap_alt_meta,
            };
            const keys = input.readKeys(&key_state, keyboard_fd, &key_buf, ctx);
            if (keys.bytes.len > 0) {
                // 앞부분("terminal: key> ")은 input/check.sh가 grep하는
                // 마커라 **그대로 둔다**. 뒤에 decckm을 덧붙이는 이유는
                // design doc 위험 4다 — 게이트가 `ESC O` 경로를 실제로
                // 밟았는지 아니면 `ESC [`만 봤는지를 로그로 알 수 있어야 한다.
                std.debug.print("terminal: key> {d} byte(s) decckm={}\n", .{
                    keys.bytes.len, ctx.cursor_keys,
                });
                pty.write(session.master_fd, keys.bytes);
            }
            // 스크롤은 PTY로 나가지 않는다(design 결정 11). **한 화면이 몇
            // 줄인지를 아는 것은 여기뿐이라**, page_up/page_down을 rows 만큼의
            // delta로 바꾸는 것도 여기서 한다 — input.zig는 격자 크기를 모른다.
            //
            // 순서대로 도는 이유는 자동 반복 때문이다. PageUp을 누르고 있으면
            // 한 번의 read에 여러 개가 실려 오고, 그만큼 올라가야 한다.
            for (keys.scrolls) |s| {
                switch (s) {
                    .top => screen.scrollToTop(),
                    .bottom => screen.scrollToBottom(),
                    .page_up => screen.scrollByRows(-@as(isize, rows)),
                    .page_down => screen.scrollByRows(@as(isize, rows)),
                }
                needs_redraw = true;
            }
        }

        // PTY master는 slave가 전부 닫히면 POLLIN이 아니라 POLLHUP을 올린다.
        // 남은 출력이 있으면 POLLIN과 함께 오지만 다 읽고 나면 POLLHUP만
        // 남으므로, POLLIN만 보면 read를 영영 호출하지 못하고 poll이 즉시
        // 반환하는 바쁜 루프에 빠진다. POLLHUP에서도 read를 시도하면 남은
        // 데이터를 먼저 비우고, 비고 나면 read가 EIO를 내 EOF 경로로 간다.
        if (fds[1].revents & (c.POLLIN | c.POLLHUP | c.POLLERR) != 0) {
            const out = pty.readSome(session.master_fd, &pty_buf);
            if (out.len == 0) {
                std.debug.print("terminal: child exited (pty EOF)\n", .{});
                break;
            }
            screen.feed(out);
            // design 결정 13. **라이브러리는 이것을 해 주지 않는다** — 올라간
            // 상태에서 출력을 먹여도 뷰포트가 그대로라는 것을 2026-08-23에
            // 실측했고, vt_test가 그 사실을 못 박고 있다. 대부분의 터미널이
            // 이렇게 동작하며, 그러지 않으면 "화면이 멈춘 것 같다"는 혼란이
            // 생긴다.
            //
            // 부수 효과가 하나 있다: 뷰포트가 history에 머무는 동안 가지치기가
            // 일어나는 상황이 이 한 줄로 **구조적으로** 안 생긴다. 가지치기는
            // 그 페이지를 가리키던 pin을 무효로 만드는데, 여기서 창이 닫힌다.
            screen.scrollToBottom();
            needs_redraw = true;
        }

        // 렌더를 루프 끝으로 뺀 것이 TR-M2의 구조 변경이다. 그전에는 렌더가
        // PTY 출력 분기 **안에만** 있었다 — 스크롤은 키로 일어나므로 그대로
        // 두면 뷰포트만 움직이고 화면은 안 바뀐다.
        //
        // 플래그를 두는 이유는 그리는 횟수를 늘리지 않기 위해서다. modifier
        // 키처럼 아무것도 바꾸지 않는 이벤트에서는 그리지 않는다.
        if (!needs_redraw) continue;
        needs_redraw = false;

        const cells = try screen.cells(cell_buf);
        const frame_start = std.Io.Clock.now(.awake, init.io);
        try render(fb, &cache, cells);
        if (!first_frame_timed) {
            first_frame_timed = true;
            std.debug.print("terminal: render> first frame {d}us\n", .{
                @divTrunc(frame_start.untilNow(init.io, .awake).nanoseconds, 1000),
            });
        }

        dumpScreen(cells);
        // render 뒤에 부른다 — 그 전에 부르면 이전 프레임의 픽셀을 읽는다.
        // 기본 색을 여기 상수로 다시 적지 않고 screen에서 얻는 이유는
        // vt.zig의 defaultFg 주석에 있다.
        dumpStyles(fb, cells, screen.defaultFg(), screen.defaultBg());
        dumpInk(fb, &cache, cells);
        dumpScroll(screen);
        if (cache.count() != last_glyph_count) {
            last_glyph_count = cache.count();
            std.debug.print("terminal: font> {d} glyph(s) cached, {d} bitmap bytes\n", .{
                last_glyph_count, cache.bitmap_bytes,
            });
        }
    }
```

- [ ] **Step 4: 빌드한다**

Claude가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && zig build && zig build test' 2>&1 | tail -20
```

기대: 에러 없이 끝난다. **Task 2가 남겨 둔 옛 시그니처 오류가 여기서 해소된다.**

- [ ] **Step 5: 지금 있는 체인이 여전히 통과하는지 본다**

Claude가 실행한다(커널 빌드 포함 약 2분). **이것이 구조 변경의 스모크 테스트다** —
`render/check.sh`는 아직 스크롤을 안 치므로, 여기서 보는 것은 "렌더를 루프 끝으로
뺐는데 색·한글 검사 일곱이 그대로인가"와 "`scroll>`이 찍히는가" 둘이다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash render/check.sh > /tmp/gate.out 2>&1
  echo "=== gate verdict ==="; tail -5 /tmp/gate.out
  echo "=== scroll lines ==="; grep -ah "terminal: scroll>" /tmp/tmp.* | tail -5
'
```

기대: `TR-M1 PASS: ...`로 끝나고 `scroll>` 줄이 나온다.

```
terminal: scroll> total=47 offset=0 len=47
```

**부팅 직후에는 `total`이 `len`과 같고 `offset`이 0이다.** 화면을 채울 만큼
찍지 않았으므로 밀려난 줄이 없다 — 정상이다. Task 4가 `seq 200`으로 그것을
바꾼다.

**여기서 색·한글 검사가 깨지면 원인은 하나뿐이다:** 렌더 블록을 옮기면서
`dumpStyles`/`dumpInk`가 `render()`보다 **앞**으로 갔는지 본다. 그 셋의 순서가
계약이다(그 전에 부르면 이전 프레임의 픽셀을 읽는다).

`grep`에 `-a`를 반드시 붙인다 — 로그에 NUL이 한 바이트라도 있으면 `grep`이
파일을 binary로 취급한다(`project_terminal_rendering`).

- [ ] **Step 6: 커밋**

```bash
git add terminal/src/main.zig
git commit -m "Redraw when the viewport moves, not only when output arrives"
```

---

## Task 4: `render/check.sh`에 스크롤 검사를 더한다

**Files:**
- Modify: `render/check.sh` (검사 7 뒤, 음성 검사 앞에 스크롤 절 · `report_failure`의
  마커 목록 · 맨 끝 통과 문구)

**완료선이다.** 사슬 전체를 본다: 셸이 200줄을 뱉고 → libghostty-vt가 밀려난 줄을
간직하고 → 우리가 Shift+PageUp을 가로채고 → 뷰포트가 움직이고 → `cells()`가
따라가고 → 렌더러가 다시 그린다.

- [ ] **Step 1: `report_failure`가 새 마커도 보게 한다**

`render/check.sh`의 현재 `:83-89`가 이렇다.

**지울 것:**

```bash
  for marker in \
    "terminal: screen>" \
    "terminal: style>" \
    "terminal: pixel>" \
    "terminal: ink>" \
    "terminal: font>" \
    "terminal: key>"; do
```

**넣을 것:**

```bash
  for marker in \
    "terminal: screen>" \
    "terminal: style>" \
    "terminal: pixel>" \
    "terminal: ink>" \
    "terminal: font>" \
    "terminal: scroll>" \
    "terminal: key>"; do
```

- [ ] **Step 2: 스크롤 절을 더한다**

`render/check.sh`의 **검사 7이 끝난 뒤**(`echo "the glyph cache is ${FONT_BYTES}
bytes, well inside the guest's memory"` 다음), **`# ── 음성 검사 ──` 앞에** 아래를
넣는다.

**넣을 것:**

```bash

# ── 스크롤백을 만든다 (TR-M2) ──────────────────────────────────────────
#
# `seq 200`. 게스트에 seq 바이너리는 없지만 **fish가 seq를 함수로 갖고 있고**
# (/usr/share/fish/functions/seq.fish, make_initrd.sh가 디렉터리째 복사한다)
# PATH가 비어 있어도 동작한다. 8타로 끝나는 것도 이유다.
#
# 200줄인 이유는 **history가 한 화면(47줄)보다 넉넉히 커야** .top과 page_up이
# 서로 다른 자리로 가기 때문이다. 60줄이면 한 번의 page_up이 맨 위에 닿아
# 버려서 두 키를 구분할 수 없다. 1000줄 한도에는 한참 못 미치므로 게이트에서
# 가지치기가 일어나지 않는다 — 그래야 아래 검사들이 행 번호에 기대도 된다.
#
# 화면 내용은 `| 1 |`이 **한 줄 전체**와 일치한다는 성질로 본다. dumpScreen이
# 행 사이에 " | "를 넣으므로 숫자 하나뿐인 줄은 이 형태로만 나타나고, 10이나
# 21에는 걸리지 않는다. 첫 행에는 앞쪽 구분자가 없으므로 `screen> 1 |` 형태도
# 함께 본다.
echo "=== typing 'seq 200' ==="
type_keys s e q spc 2 0 0 ret
sleep 4

# scroll> 줄에서 값 하나를 뽑는다. 아래에서 여러 번 쓰므로 함수로 둔다.
# **언제나 마지막 줄을 본다** — 이 로그는 매 프레임 찍히므로 마지막 줄이 곧
# 지금의 상태다.
scroll_field() {
  grep -a 'terminal: scroll>' "$LOG" | tail -n 1 | sed -E "s/.*$1=([0-9]+).*/\1/"
}

# 지금 화면에 밀려난 첫 줄이 있는지 본다. 있으면 0, 없으면 1을 돌려준다.
#
# 파이프라인 끝에 `grep -q`를 두지 않고 변수에 담아 case로 보는 이유는 이
# 스크립트의 pipefail이다. `... | grep -q`는 grep이 첫 매치에서 빠져나가며
# 앞단에 SIGPIPE를 일으키고, pipefail이 그것을 파이프라인 실패로 판정한다 —
# input/check.sh가 initrd 목록에서 이미 한 번 데인 함정이다.
line_one_on_screen() {
  local last
  last="$(grep -a 'terminal: screen>' "$LOG" | tail -n 1)"
  case "$last" in
    *"screen> 1 |"* | *"| 1 |"* | *"| 1") return 0 ;;
    *) return 1 ;;
  esac
}

# ── 검사 8: 스크롤백이 쌓였고 지금은 바닥이다 ──────────────────────────
SCROLL_LINE="$(grep -a 'terminal: scroll>' "$LOG" | tail -n 1)"
if [ -z "$SCROLL_LINE" ]; then
  report_failure "the terminal never reported a scroll position"
fi
echo "scroll line: ${SCROLL_LINE}"
TOTAL="$(scroll_field total)"
BOTTOM_OFFSET="$(scroll_field offset)"
LEN="$(scroll_field len)"
if [ "$((TOTAL - LEN))" -lt "$LEN" ]; then
  report_failure "only $((TOTAL - LEN)) rows scrolled off, which is less than one screen (${LEN}) -- the scrollback limit may not be in effect"
fi
if [ "$BOTTOM_OFFSET" -ne "$((TOTAL - LEN))" ]; then
  report_failure "the viewport is not at the bottom after output (offset=${BOTTOM_OFFSET}, expected $((TOTAL - LEN)))"
fi
echo "$((TOTAL - LEN)) rows of history exist and the viewport sits at the bottom"

# ── 검사 9: 밀려난 줄은 지금 화면에 없다 ───────────────────────────────
#
# **이 음성 검사가 없으면 검사 12가 뜻을 잃는다** — 처음부터 화면에 있었다면
# "스크롤해서 보였다"를 증명하지 못한다.
if line_one_on_screen; then
  echo "FAIL: line '1' is still on screen before scrolling"
  echo "--- the screen ---"
  grep -a 'terminal: screen>' "$LOG" | tail -n 1
  report_failure "200 lines did not push the first line off a ${LEN}-row screen"
fi
echo "line '1' has scrolled off the screen"

BOTTOM_SCREEN="$(grep -a 'terminal: screen>' "$LOG" | tail -n 1)"

# ── 한 화면 올라간다 ───────────────────────────────────────────────────
#
# QEMU monitor의 키 이름은 pgup/pgdn/home/end이고 shift- 접두사를 붙인다.
echo "=== sendkey shift-pgup ==="
type_keys shift-pgup
sleep 2

# ── 검사 10: 뷰포트가 정확히 한 화면 올라갔는가 ────────────────────────
#
# 정확한 값을 요구하는 이유는 "움직이기만 하면 통과"가 되지 않게 하려는
# 것이다. rows 대신 1이나 다른 수를 넘기는 실수가 여기서 드러난다.
UP_OFFSET="$(scroll_field offset)"
if [ "$UP_OFFSET" -ne "$((BOTTOM_OFFSET - LEN))" ]; then
  report_failure "shift-pgup moved the viewport to offset=${UP_OFFSET}, expected $((BOTTOM_OFFSET - LEN)) (one screen of ${LEN} rows)"
fi
echo "the viewport moved up exactly one screen (offset ${BOTTOM_OFFSET} -> ${UP_OFFSET})"

# ── 검사 11: 화면도 함께 바뀌었는가 ────────────────────────────────────
#
# **위치 숫자만 보면 뷰포트는 움직였는데 화면은 그대로인 상태를 못 잡는다.**
# 렌더를 키 쪽으로 열지 않았을 때가 정확히 그 상태다(TR-M2의 구조 변경).
UP_SCREEN="$(grep -a 'terminal: screen>' "$LOG" | tail -n 1)"
if [ "$UP_SCREEN" = "$BOTTOM_SCREEN" ]; then
  echo "FAIL: the viewport moved but the screen dump is identical"
  echo "--- the screen ---"
  echo "$UP_SCREEN"
  report_failure "the renderer did not follow the viewport, so nothing was redrawn on a key"
fi
echo "the rendered frame followed the viewport"

# ── 맨 위로 간다 ───────────────────────────────────────────────────────
echo "=== sendkey shift-home ==="
type_keys shift-home
sleep 2

# ── 검사 12: 맨 위에서 밀려났던 줄이 보이는가 ──────────────────────────
#
# **이 체인에서 TR-M2가 더하는 가장 값진 검사다.** 위치와 내용을 한 번에
# 본다 — offset이 0이고, 검사 9에서 없다고 확인한 바로 그 줄이 화면에 있다.
TOP_OFFSET="$(scroll_field offset)"
if [ "$TOP_OFFSET" -ne 0 ]; then
  report_failure "shift-home left the viewport at offset=${TOP_OFFSET}, expected 0"
fi
if ! line_one_on_screen; then
  echo "FAIL: at the top of the scrollback but line '1' is not on screen"
  echo "--- the screen ---"
  grep -a 'terminal: screen>' "$LOG" | tail -n 1
  report_failure "the viewport reached the top but the scrollback did not hold the first line"
fi
echo "at the top of the scrollback, the line that had scrolled off is on screen"

# ── 맨 아래로 돌아온다 ─────────────────────────────────────────────────
echo "=== sendkey shift-end ==="
type_keys shift-end
sleep 2

# ── 검사 13: 바닥으로 돌아왔는가 ───────────────────────────────────────
END_OFFSET="$(scroll_field offset)"
if [ "$END_OFFSET" -ne "$((TOTAL - LEN))" ]; then
  report_failure "shift-end left the viewport at offset=${END_OFFSET}, expected $((TOTAL - LEN))"
fi
if line_one_on_screen; then
  report_failure "back at the bottom but line '1' is still on screen"
fi
echo "shift-end brought the viewport back to the bottom"

# ── 출력이 오면 저절로 내려온다 (design 결정 13) ───────────────────────
#
# 올라간 상태에서 글자 하나를 친다. 셸이 그것을 되울려 보내므로 PTY 출력이
# 도착하고, 그때 우리가 scrollToBottom()을 불러야 한다. **라이브러리는 이
# 일을 해 주지 않는다** — vt_test가 호스트에서 그 사실을 못 박고 있고,
# 여기서는 우리 코드가 그것을 메웠는지를 본다.
echo "=== sendkey shift-pgup, then a plain key ==="
type_keys shift-pgup
sleep 2
AWAY_OFFSET="$(scroll_field offset)"
if [ "$AWAY_OFFSET" -eq "$((TOTAL - LEN))" ]; then
  report_failure "could not scroll away from the bottom before testing the snap-back"
fi
type_keys x
sleep 2

# ── 검사 14: 새 출력이 뷰포트를 바닥으로 데려왔는가 ────────────────────
SNAP_OFFSET="$(scroll_field offset)"
SNAP_TOTAL="$(scroll_field total)"
if [ "$SNAP_OFFSET" -ne "$((SNAP_TOTAL - LEN))" ]; then
  report_failure "output arrived while scrolled up (offset=${AWAY_OFFSET}) but the viewport stayed at offset=${SNAP_OFFSET} instead of $((SNAP_TOTAL - LEN))"
fi
echo "output snapped the viewport back to the bottom (offset ${AWAY_OFFSET} -> ${SNAP_OFFSET})"

# 친 글자를 지운다. 뒤에 오는 음성 검사들이 깨끗한 화면을 보게 한다.
type_keys backspace
sleep 1
```

- [ ] **Step 3: 맨 끝의 통과 문구를 고친다**

`render/check.sh`의 현재 `:299-301`이 이렇다.

**지울 것:**

```bash
echo "--- ink lines ---"
grep -a 'terminal: ink>' "$LOG" | tail -n 10
echo "TR-M1 PASS: colors reach the framebuffer and Hangul covers both of its cells"
```

**넣을 것:**

```bash
echo "--- ink lines ---"
grep -a 'terminal: ink>' "$LOG" | tail -n 10
echo "--- scroll lines ---"
grep -a 'terminal: scroll>' "$LOG" | tail -n 10
echo "TR-M2 PASS: colors reach the framebuffer, Hangul covers both of its cells, and the viewport scrolls and comes back"
```

- [ ] **Step 4: 체인을 돌린다**

Claude가 실행한다(약 2분 30초). TR-M1보다 `sendkey`가 열댓 번 늘어 20초쯤
더 걸린다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash render/check.sh 2>&1 | tail -40
```

기대 출력:

```
=== typing 'seq 200' ===
scroll line: terminal: scroll> total=NNN offset=MMM len=47
NNN rows of history exist and the viewport sits at the bottom
line '1' has scrolled off the screen
=== sendkey shift-pgup ===
the viewport moved up exactly one screen (offset MMM -> MMM-47)
the rendered frame followed the viewport
=== sendkey shift-home ===
at the top of the scrollback, the line that had scrolled off is on screen
=== sendkey shift-end ===
shift-end brought the viewport back to the bottom
=== sendkey shift-pgup, then a plain key ===
output snapped the viewport back to the bottom (offset ... -> ...)
TR-M2 PASS: ...
```

막혔을 때 어디를 먼저 보는지는 이렇다.

- **검사 8에서 "only N rows scrolled off"** — `seq 200`이 안 돌았거나 스크롤백
  한도가 안 들어갔다. `screen>` 마지막 줄에 숫자가 있는지 먼저 본다. fish의 `seq`
  함수가 없으면 `command not found`가 화면에 남는다.
- **검사 10에서 offset이 안 움직였다** — `chord`의 Shift 분기까지 못 갔다.
  QEMU가 `shift-pgup`을 어떻게 보냈는지는 `key>` 줄로 알 수 있다. **스크롤이
  제대로 가로채였으면 `key>` 줄이 안 나온다** — 나온다면 `ESC [ 5 ~`가 PTY로
  샌 것이고, `chord`가 `specialKey`보다 뒤에 있다는 뜻이다.
- **검사 11에서 화면이 그대로다** — `needs_redraw`가 안 걸렸거나 렌더 블록이
  아직 PTY 분기 안에 있다.
- **검사 14에서 안 내려왔다** — `screen.feed(out)` 뒤의 `scrollToBottom()`이 빠졌다.

- [ ] **Step 5: 커밋**

```bash
git add render/check.sh
git commit -m "Make the gate prove the viewport moves and comes back"
```

---

## Task 5: `xterm-256color` terminfo를 initrd에 넣는다

**Files:**
- Modify: `kernel/make_initrd.sh` (terminfo 절)
- Modify: `input/check.sh` (initrd 목록 검사)

**이월 숙제이고 TR-M2의 주제는 아니지만, 같은 서브프로젝트가 만든 구멍이다.**
TR-M0이 `TERM`을 `xterm-256color`로 바꿨는데 initrd에는 `xterm`만 들어 있다.
그리고 그 사실을 **막았어야 할 검사가 글로브라서 통과시켰다** — 조용한 실패를
막으려고 만든 검사가 조용히 실패한 자리라, 고치는 것은 두 줄이지만 남겨 둘
이유가 없다.

- [ ] **Step 1: initrd에 파일을 하나 더 넣는다**

`kernel/make_initrd.sh`의 현재 `:136-146`이 이렇다.

**지울 것:**

```bash
# IP-M1: terminal이 PTY 셸의 TERM을 xterm으로 바꾸므로(design doc 결정 7)
# 그 terminfo가 게스트에 있어야 한다. 없으면 부팅은 계속되고 셸이 능력을
# 덜 쓸 뿐이다 — **조용한 실패**라서 input/check.sh가 initrd 목록을 직접
# 확인한다.
#
# 디렉터리를 통째로 복사하지 않고 파일 하나(3977B)만 넣는다. ncurses-base의
# /usr/share/terminfo에는 수백 개가 들어 있고 우리가 광고하는 이름은
# 하나뿐이다. 시리얼 콘솔 셸이 쓰는 `linux`는 넣지 않는다 — 그쪽은 terminfo
# 없이도 지금까지 잘 돌아왔고, 넣는 순간 "무엇이 왜 필요한가"가 흐려진다.
mkdir -p "$WORKDIR/usr/share/terminfo/x"
cp "$SYSROOT/usr/share/terminfo/x/xterm" "$WORKDIR/usr/share/terminfo/x/xterm"
```

**넣을 것:**

```bash
# IP-M1: terminal이 PTY 셸의 TERM을 바꾸므로(design doc 결정 7) 그 terminfo가
# 게스트에 있어야 한다. 없으면 부팅은 계속되고 셸이 능력을 덜 쓸 뿐이다 —
# **조용한 실패**라서 input/check.sh가 initrd 목록을 직접 확인한다.
#
# **TR-M2에서 xterm-256color가 늘었다.** TR-M0이 TERM을 xterm에서
# xterm-256color로 바꿨는데(TR design 결정 8) 이 줄은 따라오지 않아서, 게스트가
# 광고하는 이름의 terminfo가 실제로는 없는 상태로 두 milestone을 건너왔다.
# input/check.sh의 검사가 `*terminfo/x/xterm*` 글로브라 xterm 하나만으로도
# 통과했다 — **조용한 실패를 막으려고 만든 검사가 조용히 실패한 자리다.**
#
# 옛 이름 xterm도 남긴다. 시리얼 콘솔 셸이나 손으로 띄운 셸이 그 이름을 쓸 수
# 있고, 두 파일을 합쳐도 8KB다.
#
# 디렉터리를 통째로 복사하지 않는 이유는 그대로다. ncurses-base의
# /usr/share/terminfo에는 수백 개가 들어 있고 우리가 광고하는 이름은 하나다.
# 시리얼 콘솔 셸이 쓰는 `linux`는 넣지 않는다 — 그쪽은 terminfo 없이도 지금까지
# 잘 돌아왔고, 넣는 순간 "무엇이 왜 필요한가"가 흐려진다.
mkdir -p "$WORKDIR/usr/share/terminfo/x"
cp "$SYSROOT/usr/share/terminfo/x/xterm" "$WORKDIR/usr/share/terminfo/x/xterm"
cp "$SYSROOT/usr/share/terminfo/x/xterm-256color" \
  "$WORKDIR/usr/share/terminfo/x/xterm-256color"
```

- [ ] **Step 2: 검사가 정확한 이름을 보게 한다**

`input/check.sh`의 현재 `:63-81`에서 주석과 `case`를 고친다.

**지울 것:**

```bash
# TERM=xterm이 진실이려면 그 terminfo가 게스트 안에 있어야 한다(design doc
# 결정 7). 없어도 부팅은 계속되고 셸은 기능을 덜 쓸 뿐이라 **조용한 실패**다 —
# 부팅해서 알아내는 것보다 여기서 cpio 목록을 보는 편이 싸고 정확하다.
```

**넣을 것:**

```bash
# TERM이 진실이려면 그 terminfo가 게스트 안에 있어야 한다(design doc 결정 7).
# 없어도 부팅은 계속되고 셸은 기능을 덜 쓸 뿐이라 **조용한 실패**다 — 부팅해서
# 알아내는 것보다 여기서 cpio 목록을 보는 편이 싸고 정확하다.
#
# **이름을 정확히 본다(TR-M2).** 그전에는 `*terminfo/x/xterm*` 글로브라
# xterm-256color가 없어도 통과했고, 실제로 TR-M0이 TERM을 바꾼 뒤로 두
# milestone 동안 그 상태였다. 조용한 실패를 막으려고 만든 검사가 조용히
# 실패한 자리라, 접두사가 아니라 파일 이름 전체를 본다.
```

이어서 `case` 블록이다.

**지울 것:**

```bash
case "$INITRD_LIST" in
  *usr/share/terminfo/x/xterm*) ;;
  *)
    echo "FAIL: xterm terminfo is missing from the initrd"
    echo "      (devcontainer/Dockerfile needs ncurses-base, and"
    echo "       kernel/make_initrd.sh needs to copy the file)"
    exit 1
    ;;
esac
```

**넣을 것:**

```bash
# 목록 앞뒤에 줄바꿈을 덧대고 줄 하나를 통째로 맞춘다.
PADDED_LIST="$(printf '\n%s\n' "$INITRD_LIST")"
for want in xterm xterm-256color; do
  case "$PADDED_LIST" in
    *$'\n'"usr/share/terminfo/x/${want}"$'\n'*) ;;
    *)
      echo "FAIL: ${want} terminfo is missing from the initrd"
      echo "      (devcontainer/Dockerfile needs ncurses-base, and"
      echo "       kernel/make_initrd.sh needs to copy the file)"
      exit 1
      ;;
  esac
done
```

> **줄 하나를 통째로 맞추는 것이 요점이다.** `*.../xterm*`이면
> `usr/share/terminfo/x/xterm-256color` 줄에도 걸려서 `xterm`이 없어도 통과한다 —
> 지금 고치는 것이 바로 그 종류의 느슨함이라, 새 검사가 같은 함정에 빠지지 않게
> 한다. 앞뒤에 줄바꿈을 덧대는 것은 첫 줄과 마지막 줄을 특별 취급하지 않기
> 위해서다. `grep -qx`로 쓰지 않는 이유는 위 `line_one_on_screen`과 같다 —
> `grep -q`가 파이프라인 앞단에 SIGPIPE를 일으키고 pipefail이 그것을 실패로
> 본다.

- [ ] **Step 3: initrd에 정말 들어갔는지 본다**

Claude가 실행한다(약 40초). 부팅하지 않고 목록만 본다 — 파일이 들어갔는지는
cpio 목록이 답한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd kernel && ./make_initrd.sh > /dev/null 2>&1
  zcat initrd.cpio | cpio -t 2>/dev/null | grep terminfo
'
```

기대 출력:

```
usr/share/terminfo
usr/share/terminfo/x
usr/share/terminfo/x/xterm
usr/share/terminfo/x/xterm-256color
```

**`xterm-256color`가 없으면 sysroot에 그 파일이 없는 것이다.** 컨테이너에
있다는 것은 2026-08-23에 확인했으므로(4071바이트), 없다면 `SYSROOT` 경로를
의심한다.

- [ ] **Step 4: IP 체인이 통과하는지 본다**

Claude가 실행한다(약 4분). 이 체인은 **부팅을 두 번** 한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash input/check.sh 2>&1 | tail -20
```

기대: `IP-M2 PASS`로 끝난다. terminfo 검사가 두 이름을 다 보고 통과해야 한다.

**여기서 화면 검사가 달라지면 그것이 이 변경의 진짜 결과다.** 셸과 ncurses가
이제 256색 terminfo를 읽으므로 프롬프트가 색 시퀀스를 쓰기 시작할 수 있다 —
TR-M0의 위험 1이 "fish는 실제로 안 쓴다"로 닫혔지만, 그때는 terminfo가 없어서
셸이 능력을 몰랐다. **즉 위험 1이 여기서 처음으로 진짜로 시험된다.**

- [ ] **Step 5: 커밋**

```bash
git add kernel/make_initrd.sh input/check.sh
git commit -m "Put the terminfo we actually advertise into the initrd"
```

---

## Task 6: 루트 게이트 3/3

**Files:** 없음(실행만 한다)

- [ ] **Step 1: 일곱 체인을 3회씩 돌린다**

Claude가 실행한다. **약 50분이 걸린다.** 직전 기준선이 46분 33초이고, TR 체인에
스크롤 명령(약 20초 × 3회)이 더해진다. **Bash 도구의 10분 상한을 넘으므로
백그라운드로 돌린다.**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh
```

`--platform`을 붙이지 않는다(`project_build_host_arch`).

기대: 일곱 체인(BF-M4 · TF-M4 · CP-M2 · IP-M2 · PM-M1 · HD-M2 · TR-M2)이 전부
3/3이다.

**가장 그럴듯한 실패 둘을 미리 적어 둔다.**

1. **terminfo가 다섯 체인의 화면 검사를 흔든다.** Task 5 Step 4가 IP 체인만
   봤다. 셸이 256색 terminfo를 읽고 프롬프트에 색 시퀀스를 쓰기 시작하면
   `screen>` 줄을 grep하는 검사가 어긋날 수 있다. **터지면 Task 5의 두 줄만
   되돌리고 나머지를 살린다** — TR-M2의 주제가 아니라 이월 숙제였다.
2. **렌더 경로 변경이 프레임 수를 바꾼다.** `needs_redraw`를 도입하면서
   modifier 키 이벤트에서 안 그리게 됐다. 화면 내용을 보는 검사는 영향이
   없지만, 특정 시점의 프레임을 기다리는 검사가 있으면 여기서 드러난다.

- [ ] **Step 2: 걸린 시간을 적어 둔다**

Task 7의 문서에 들어간다. `project_terminal_rendering.md`의 표에 한 줄 더한다.

---

## Task 7: 문서

**Files:**
- Modify: `docs/decisions/project_terminal_rendering.md`
- Modify: `docs/decisions/project_input_policy.md` (반환 타입이 넓어진 것)
- Modify: `docs/decisions/project_guest_environment.md` (terminfo 구멍을 닫았다)
- Modify: `docs/decisions/project_copy_mode.md` (선행 조건 1·2가 끝났다)
- Modify: `MEMORY.md` (한 줄 요약 갱신)
- Modify: `docs/superpowers/specs/2026-08-23-tars-terminal-rendering-design.md`
  (TR-M2 절에 결과를 붙인다)
- Rewrite: `HANDOFF.md`

Claude가 쓴다. 담을 것은 다음과 같다.

**`project_terminal_rendering.md`에 더할 사실:**

- **`max_scrollback_lines`만으로는 아무 일도 안 일어난다**는 것과 그 이유
  (`PageList.Limits.max`가 바이트 한도를 먼저 적용한다). 실측 표 넷.
- **가지치기가 페이지 통째로** 일어나므로 history가 754~1000을 오간다는 것.
- `Terminal.scrollViewport`의 이름이 `PageList.Scroll`과 다르다는 것
  (`.bottom`/`.delta` 대 `.active`/`.delta_row`).
- **`RenderState`가 뷰포트를 따라가므로 `cells()`는 손댈 것이 없었다**는 것,
  그리고 커서가 뷰포트 밖에서 저절로 사라진다는 것.
- **새 출력이 뷰포트를 안 내리는 것은 라이브러리의 성질**이고 결정 13은 우리
  코드라는 것. 그 한 줄이 가지치기와 pin 무효화의 창까지 닫는다는 것.
- **렌더가 PTY 분기 안에만 있었다**는 것과 `needs_redraw`로 뺀 것.
- 루트 게이트에 걸린 시간(Task 6 Step 2에서 잰 값).

**`project_input_policy.md`에 더할 사실:**

- `handleKey`의 반환이 `[]const u8`에서 `Action` union으로 넓어졌다는 것.
  IP design 결정 2의 dispatch 단계가 처음으로 **바이트가 아닌 것**을 돌려준다.
- `readKeys`가 스크롤을 배열로 모으는 이유(자동 반복), 그리고 루프 조건에서
  `written < out.len`을 뺀 이유.
- Shift 분기가 Meta·Alt보다 뒤라서 **Cmd가 Shift를 이긴다**는 것.
- `input.zig`가 여전히 격자 크기를 모른다는 것 — 경계가 유지됐다.

**`project_guest_environment.md`에서 고칠 것:** `xterm-256color`가 없다고 적어
둔 절을 "TR-M2에서 넣었다"로 바꾸고, **검사가 글로브라 통과했다**는 사실과 그
검사를 어떻게 조였는지를 남긴다.

**`project_copy_mode.md`에서 고칠 것:** 선행 조건 1(스크롤백)과 2(셀별 속성
렌더링)가 **둘 다 끝났다**는 것. 남은 것은 3(클립보드)뿐이고, `Action` union이
copy mode가 쓸 통로라는 것.

**design doc TR-M2 절에 붙일 결과:** 완료 조건 셋을 만족했는지, 그리고 결정
10이 값 하나를 빠뜨렸다는 것.

**`HANDOFF.md`에 적을 것:** TR 서브프로젝트가 끝났으므로 **다음 서브프로젝트를
고르는 것이 다음 일**이라는 것(`project_copy_mode`가 유력 후보이고 남은 선행
조건이 클립보드 하나다), plan에서 어긋난 곳, 이월 숙제(terminfo 항목은 지운다),
그리고 게이트 현황(일곱 체인 · 새 소요 시간 · `scroll>` 마커).

---

## 완료 조건

design의 TR-M2 절이 적어 둔 것 그대로다.

- [ ] 화면보다 많은 줄을 찍고 Shift+PageUp으로 올라가면 밀려난 줄이 보인다 —
      검사 10·11·12가 **위치와 화면 두 겹으로** 본다.
- [ ] Shift+End로 맨 아래로 돌아온다 — 검사 13.
- [ ] 새 출력으로도 맨 아래로 돌아온다 — 검사 14(design 결정 13).
- [ ] 스크롤 키가 PTY로 새지 않는다 — `input_test`의 `expectScroll`이 호스트에서
      보고, 게이트에서는 `key>` 줄이 안 나오는 것으로 나타난다.
- [ ] 스크롤백이 1000줄까지 쌓인다 — `vt_test`가 호스트에서 700~1000줄을 단언한다.
- [ ] 루트 게이트 일곱 체인이 3/3이다.
