# IS-M0 — 상태 줄이 아래 여백에 뜬다 (칸 셋)

**Date:** 2026-09-02
**Design:** `docs/superpowers/specs/2026-09-02-tars-input-status-design.md`
**Status:** 착수 전.

## 이 milestone이 끝나면

- **화면 맨 아래 여백 28픽셀에 상태 줄 하나가 뜬다.** 격자 바깥이라 터미널
  47줄을 한 줄도 안 뺏는다.
- **칸이 셋이다** — 한/영(`한`/`EN`) · 한글 자판 · 영문 자판. **`CAPS` 칸은
  IS-M1이 넣는다.**
- **자판 이름은 사람이 읽는 이름이고, 표는 `else` 없는 `switch`다**(결정 4).
  자판을 다섯째로 더하는 사람이 이름을 빼먹으면 **컴파일 에러**다.
- **글자 만들기가 새 모듈 `terminal/src/status.zig`로 선다**(결정 5).
  `status_test`가 호스트에서 자판 여섯 × 한/영 둘을 전부 돈다.
- **갱신은 기존 경로만 쓴다.** `Action.hangul`이 이미 `needs_redraw`를 켠다 —
  **새 경로를 하나도 안 만드는 것이 이 milestone의 요점이다.**

**아직 안 하는 것.** `CAPS` 칸과 색 셋(IS-M1). `Action.hangul` →
`Action.redraw` 이름 바꾸기(IS-M1 — **지금은 그 구멍을 밟을 일이 없다**,
대문자 잠금을 안 그리므로). design 비목표 전부.

## 왜 이 순서인가

**Task 1이 부팅을 하나도 안 한다.** 글자 만들기는 순수 계산이라 `zig build
test`가 초 단위로 답한다 — 18분을 쓰기 전에 이름 표와 버퍼 크기를 전부
확정한다. HI-M2의 Task 1이 같은 모양이었다.

**Task 2와 Task 3을 나누는 이유는 "실패했을 때 어디가 틀렸는지"다.** Task 2는
그리고 Task 3은 찍는다. 게이트가 실패했을 때 `text=`가 틀렸으면 Task 3(또는
Task 1)이고, `ink fg=0`이면 Task 2다. **SP-M1 실측 5가 말한 "두 파일이 나눠
본다"를 여기서는 두 Task가 나눠 진다.**

**Task 4의 게이트가 마지막에서 두 번째다.** 호스트 검사가 전부 통과한 뒤에
부팅한다.

---

## 착수 전에 확정한 것

### 1. 게이트 판정이 둘이 아니라 셋이다 — design보다 하나 많다

design은 IS-M0의 게이트 판정을 둘로 적었다(부팅 직후의 `text=` · 한/영 전환
뒤의 `text=`). **plan을 쓰면서 구멍을 하나 찾았다: 그 둘은 `statusText`가
만든 문자열을 되읽을 뿐이고, "글자는 만들었는데 화면에 안 그렸다"를 못
잡는다.** 여백은 격자 밖이라 `screen>`·`style>`·`ink>`가 하나도 못 본다.

design은 그 구멍을 IS-M1의 `CAPS` 칸 ink 판정으로 막기로 했는데, **그러면
IS-M0의 `drawStatus`가 한 milestone 내내 검증 없이 서 있게 된다.** 그래서
IS-M0에도 값싼 픽셀 판정 하나를 넣는다 — **상태 줄 띠 안에서 `STATUS_FG`
색인 픽셀의 개수**다.

```
terminal: status> ink fg=214
```

이것이 증명하는 것은 "우리 색이 그 띠에 실제로 닿았다"이고, IS-M1의 판정
(`CAPS` 칸 하나의 `on`/`off` 개수)보다 넓고 무디다. **둘 다 필요하다** —
넓은 것은 "안 그렸다"를, 좁은 것은 "색이 안 바뀌었다"를 잡는다.

### 2. `status.zig`는 `input.zig`를 import한다

design 결정 5가 `status.zig`를 "시스템 콜도 프레임버퍼도 `vt.zig`도 안 보는
순수 모듈"이라고 적었다. **그것은 `status.zig`가 스스로 하는 일에 대한
말이고, import까지 비어 있다는 뜻은 아니다.**

`statusText`는 `input.State`를 받고 `input.LatinLayout`을 읽어야 하므로
`input.zig`를 import한다. 그러면 `input.zig`의
`@cImport(@cInclude("linux/input.h"))`가 따라온다 — 그래서
**`status_test`도 `input_test`처럼 `link_libc = true`가 필요하다.**

`hangul_test`가 libc 없이 도는 것과 여기서 갈린다. `hangul.zig`는 아무것도
import하지 않지만 `status.zig`는 상태를 받는 모듈이라 상태의 타입이 사는
곳을 봐야 한다.

**`LatinLayout`을 옮기지 않는다.** 옮기면 `input.zig`의
`latinChar()`와 `keymap` 둘이 남의 파일을 보게 되고, 이름 하나 때문에
경계를 흔드는 것은 이 milestone의 일이 아니다.

### 3. `MAX_LEN`은 이름 표에서 `comptime`에 센다

`promptText`가 173바이트를 주석의 산수로 정당화한 것과 다르다. **여기는 값의
집합이 닫혀 있어서**(needle 같은 가변 입력이 없다) 컴파일러가 직접 셀 수 있다.

`std.enums.values`가 Zig 0.16에서 도는 것을 확인했다. `공세벌 3-P3`이
**14바이트**(한글 셋 9 + 공백 1 + `3-P3` 4)이고, IS-M0의 `MAX_LEN`은
3(`한`) + 2 + 14 + 2 + 9(`드보락`) = **30**이다. IS-M1이 `  CAPS` 여섯을
더해 36이 된다.

### 4. 편집은 사용자가 한다 — HI의 예외가 끝났다

`CLAUDE.md`가 그렇게 적어 두었다: "**다음 서브프로젝트는 다시 기본
규칙(사용자가 편집)으로 돌아간다.**" HI의 예외는 "사용자가 macOS용 한글
입력기를 직접 만들어 본 영역이라 코드를 읽는 자리의 값이 낮다"였고, 상태
줄과 렌더 배선은 그 영역이 아니다.

**명령 실행은 Claude Code가 한다**(2026-08-22 변경). Task 5의 루트 게이트는
**18분 안팎**이 걸린다.

### 5. 컨테이너 한 줄

모든 빌드·검사·게이트는 이 안에서 돈다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '...'
```

호스트는 macOS aarch64이고 `linux/input.h`가 없으므로 **`zig build test`를
호스트에서 직접 돌릴 수 없다.**

---

## Task 1: `status.zig`와 호스트 검사

**Files:**
- Create: `terminal/src/status.zig`
- Create: `terminal/src/status_test.zig`
- Modify: `terminal/build.zig` — 모듈·실행 파일 등록과 `test_step` 한 줄

- [ ] **Step 1: 검사를 먼저 만든다**

`terminal/src/status_test.zig`를 **새로 만든다.**

```zig
const std = @import("std");
const hangul = @import("hangul.zig");
const input = @import("input.zig");
const status = @import("status.zig");

/// 상태 하나를 넣고 나온 줄을 본다.
///
/// **`input.State`를 통째로 넘긴다**(design 결정 5). 필드를 넷 늘어놓으면
/// 부르는 자리마다 순서를 틀릴 수 있고, IS-M1이 `caps_lock`을 더할 때 이
/// 헬퍼의 시그니처가 또 바뀐다.
fn expectText(state: input.State, want: []const u8) !void {
    var buf: [status.MAX_LEN]u8 = undefined;
    const got = status.statusText(&state, &buf);
    if (std.mem.eql(u8, got, want)) {
        std.debug.print("status_test: \"{s}\" OK\n", .{got});
        return;
    }
    std.debug.print("FAIL: got \"{s}\", want \"{s}\"\n", .{ got, want });
    return error.WrongStatusText;
}

/// 상태 줄의 검사. **부팅도 폰트도 프레임버퍼도 안 쓴다** — 상태를 넣고
/// 문자열을 받는 순수 계산이다.
pub fn main() !void {
    // ── 검사 1: 기본값 ───────────────────────────────────────────────
    //
    // `input.State`의 기본값은 한/영 꺼짐 · `shin_pcs` · `qwerty`다.
    // **이 줄이 곧 아무 설정도 없는 부팅의 화면이다.**
    try expectText(.{}, "EN  신세벌 PCS  쿼티");

    // ── 검사 2: 한/영이 첫 칸을 가른다 ───────────────────────────────
    try expectText(.{ .hangul_on = true }, "한  신세벌 PCS  쿼티");

    // ── 검사 3~6: 한글 자판 넷의 이름 ────────────────────────────────
    //
    // **자판 이름 표를 옮겨 적는 것이 이 milestone의 유일한 "사람이 읽고
    // 다시 적는" 자리다**(HI-M2 실측 6). 넷을 전부 못 박는다.
    try expectText(.{ .hangul_layout = .dubeol }, "EN  두벌식  쿼티");
    try expectText(.{ .hangul_layout = .sebeol_3p3 }, "EN  공세벌 3-P3  쿼티");
    try expectText(.{ .hangul_layout = .shin_p2 }, "EN  신세벌 P2  쿼티");
    try expectText(.{ .hangul_layout = .shin_pcs }, "EN  신세벌 PCS  쿼티");

    // ── 검사 7~8: 영문 자판 둘의 이름 ────────────────────────────────
    try expectText(.{ .latin_layout = .qwerty }, "EN  신세벌 PCS  쿼티");
    try expectText(.{ .latin_layout = .dvorak }, "EN  신세벌 PCS  드보락");

    // ── 검사 9: 칸이 언제나 셋이다 ───────────────────────────────────
    //
    // **자리가 고정인 것이 결정 2다.** 칸이 사라지거나 밀리면 사람도
    // 게이트도 매번 다른 자리를 봐야 한다. 두 칸 공백으로 갈라 센다.
    {
        var buf: [status.MAX_LEN]u8 = undefined;
        const line = status.statusText(&input.State{ .hangul_on = true }, &buf);
        var it = std.mem.splitSequence(u8, line, "  ");
        var fields: usize = 0;
        while (it.next()) |f| {
            if (f.len == 0) {
                std.debug.print("FAIL: empty field in \"{s}\"\n", .{line});
                return error.EmptyStatusField;
            }
            fields += 1;
        }
        if (fields != 3) {
            std.debug.print("FAIL: {d} field(s) in \"{s}\", want 3\n", .{ fields, line });
            return error.WrongStatusFieldCount;
        }
        std.debug.print("status_test: 3 fields OK\n", .{});
    }

    // ── 검사 10: 가장 긴 줄이 `MAX_LEN`과 **정확히** 같다 ────────────
    //
    // 크거나 같은지가 아니라 **같은지**를 본다. `MAX_LEN`은 이름 표에서
    // comptime에 센 값이므로, 정확히 안 맞는다는 것은 산수와 표가 어긋났다는
    // 뜻이다 — 버퍼가 남아도는 것도 사고의 신호다.
    //
    // 가장 긴 조합은 `한`(3, `EN`보다 길다) + `공세벌 3-P3`(14) +
    // `드보락`(9) + 공백 넷이다.
    {
        var buf: [status.MAX_LEN]u8 = undefined;
        const line = status.statusText(&input.State{
            .hangul_on = true,
            .hangul_layout = .sebeol_3p3,
            .latin_layout = .dvorak,
        }, &buf);
        if (line.len != status.MAX_LEN) {
            std.debug.print("FAIL: longest line is {d} byte(s), MAX_LEN is {d}\n", .{
                line.len, status.MAX_LEN,
            });
            return error.WrongMaxLen;
        }
        std.debug.print("status_test: longest line is exactly MAX_LEN={d} OK\n", .{
            status.MAX_LEN,
        });
    }

    // ── 검사 11: 자판이 아직 넷이다 ─────────────────────────────────
    //
    // **검사 3~6이 낡았는지를 보는 자리다.** 위의 넷은 이름을 하나씩 못
    // 박지만 "빠진 자판이 없다"는 말하지 않는다 — 다섯째가 들어오면
    // `hangulName`의 `switch`가 컴파일 에러로 막고, 그 에러를 고친 사람이
    // **검사도 하나 더해야 한다**는 것을 이 줄이 알려 준다.
    if (std.enums.values(hangul.Layout).len != 4) {
        std.debug.print("FAIL: {d} hangul layout(s), but only 4 are checked above\n", .{
            std.enums.values(hangul.Layout).len,
        });
        return error.LayoutCountChanged;
    }

    std.debug.print("status_test: all checks passed\n", .{});
}
```

- [ ] **Step 2: `build.zig`에 등록한다**

`terminal/build.zig`에서 지울 것:

```zig
    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
```

넣을 것:

```zig
    // status_test도 호스트에서 돈다. **`link_libc`가 필요한 것이
    // `hangul_test`와 다른 자리다**(IS-M0) — `status.zig`가 `input.State`를
    // 받으므로 `input.zig`의 `@cImport("linux/input.h")`가 따라온다.
    const status_test_mod = b.createModule(.{
        .root_source_file = b.path("src/status_test.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    status_test_mod.link_libc = true;
    const status_test = b.addExecutable(.{
        .name = "status_test",
        .root_module = status_test_mod,
    });
    b.installArtifact(status_test);

    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
```

이어서 같은 파일에서 지울 것:

```zig
    test_step.dependOn(&b.addRunArtifact(hangul_test).step);
```

넣을 것:

```zig
    test_step.dependOn(&b.addRunArtifact(hangul_test).step);
    test_step.dependOn(&b.addRunArtifact(status_test).step);
```

- [ ] **Step 3: 검사가 실패하는 것을 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd terminal && zig build test
'
```

기대: **컴파일 실패.** `src/status.zig`가 없으므로
`unable to load '.../src/status.zig': FileNotFound` 계열 메시지가 나온다.

이 실패를 굳이 보는 이유는, 다음 Step이 통과했을 때 **그것이 새 파일 때문임을
확인하기 위해서다.** `test_step`에 줄을 안 더했으면 검사가 아예 안 돌면서도
`zig build test`는 초록이다.

- [ ] **Step 4: `status.zig`를 만든다**

`terminal/src/status.zig`를 **새로 만든다.**

```zig
const std = @import("std");
const hangul = @import("hangul.zig");
const input = @import("input.zig");

/// 칸 사이를 벌리는 두 칸. **한 칸이 아닌 이유**는 자판 이름 안에 이미 공백이
/// 있기 때문이다(`공세벌 3-P3`) — 한 칸으로 벌리면 칸 경계와 이름 안의 공백이
/// 눈으로도 게이트로도 안 갈린다.
const GAP = "  ";

/// 한글 자판의 사람이 읽는 이름(IS design 결정 4).
///
/// **`else`를 안 단다.** 자판을 다섯째로 더하는 사람이 이름을 빼먹으면 그
/// 순간 컴파일 에러가 난다. 배열이나 map으로 만들면 그 실수가 조용히 통과하고
/// 증상은 화면에 빈 칸이 뜨거나 엉뚱한 이름이 뜨는 것이다 — HI-M2 실측 6이
/// "이 위험은 '표를 옮긴다'가 아니라 **'사람이 읽고 다시 적는다'**에 딸려
/// 있었다"고 적어 둔 그 위험이다.
fn hangulName(l: hangul.Layout) []const u8 {
    return switch (l) {
        .dubeol => "두벌식",
        .sebeol_3p3 => "공세벌 3-P3",
        .shin_p2 => "신세벌 P2",
        .shin_pcs => "신세벌 PCS",
    };
}

/// 영문 자판의 사람이 읽는 이름. 같은 이유로 `else`가 없다.
fn latinName(l: input.LatinLayout) []const u8 {
    return switch (l) {
        .qwerty => "쿼티",
        .dvorak => "드보락",
    };
}

/// 상태 줄이 쓸 수 있는 가장 긴 바이트 수.
///
/// **이름 표에서 직접 센다**(design 결정 5). `promptText`가 173을 주석의
/// 산수로 정당화한 것과 다른데, 여기는 **값의 집합이 닫혀 있기** 때문이다 —
/// needle 같은 가변 입력이 없고 자판 이름이 여섯, 한/영이 둘뿐이다.
/// 그래서 **자판을 더하는 사람이 버퍼를 같이 안 늘려도 컴파일러가 맞춰
/// 준다.** `hangulName`의 `switch`와 같은 종류의 못이다.
///
/// 한/영 칸은 `한`(3)과 `EN`(2) 중 긴 쪽인 3이다.
///
/// **IS-M1이 여기에 `GAP.len + "CAPS".len`을 더한다** — 30에서 36이 된다.
pub const MAX_LEN: usize = blk: {
    var hl: usize = 0;
    for (std.enums.values(hangul.Layout)) |t| {
        if (hangulName(t).len > hl) hl = hangulName(t).len;
    }
    var ll: usize = 0;
    for (std.enums.values(input.LatinLayout)) |t| {
        if (latinName(t).len > ll) ll = latinName(t).len;
    }
    break :blk 3 + GAP.len + hl + GAP.len + ll;
};

/// `buf`의 `at`부터 `s`를 쓰고 쓴 길이를 돌려준다.
fn put(buf: []u8, at: usize, s: []const u8) usize {
    @memcpy(buf[at..][0..s.len], s);
    return s.len;
}

/// 상태 줄 한 줄을 만든다.
///
/// **시스템 콜도 프레임버퍼도 `vt.zig`도 안 본다**(design 결정 5). 상태를
/// 받아 문자열을 돌려주는 순수 계산이라 `status_test`가 자판 여섯 × 한/영
/// 둘을 전부 호스트에서 돈다. `promptText`가 `main.zig`의 private이라
/// `vt_test`가 못 부른 것(SP-M1 실측 5)이 이 파일이 따로 있는 이유다.
///
/// `buf`는 최소 `MAX_LEN`바이트여야 한다.
pub fn statusText(state: *const input.State, buf: []u8) []const u8 {
    var len: usize = 0;
    len += put(buf, len, if (state.hangul_on) "한" else "EN");
    len += put(buf, len, GAP);
    len += put(buf, len, hangulName(state.hangul_layout));
    len += put(buf, len, GAP);
    len += put(buf, len, latinName(state.latin_layout));
    return buf[0..len];
}
```

- [ ] **Step 5: 검사가 통과하는 것을 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd terminal && zig build test
'
```

기대: `status_test:` 줄 **열하나**가 찍히고 마지막이
`status_test: all checks passed`. 여덟은 `expectText`의 것이고, 검사 9·10이
하나씩, 마지막이 하나다(검사 11은 통과하면 아무것도 안 찍는다).
그중 하나가 `status_test: longest line is exactly MAX_LEN=30 OK`여야 한다 —
**30이 아니면 이름 표와 산수가 어긋난 것이다.**
**`input_test`·`vt_test`·`font_test`·
`hangul_test`도 함께 돌고 전부 통과해야 한다** — 이 Task는 기존 파일을 하나도
안 건드렸으므로 그것들이 갈리면 무언가 잘못 붙은 것이다.

- [ ] **Step 6: 커밋**

```bash
git add terminal/src/status.zig terminal/src/status_test.zig terminal/build.zig
git commit -m "Turn the input state into one line of text"
```

---

## Task 2: 상태 줄을 아래 여백에 그린다

**Files:**
- Modify: `terminal/src/main.zig` — import 한 줄 · `STATUS_FG` · `drawStatus` ·
  `Status` struct · `render` 시그니처와 호출부

- [ ] **Step 1: import를 더한다**

`terminal/src/main.zig`에서 지울 것:

```zig
const pty = @import("pty.zig");
const vt = @import("vt.zig");
```

넣을 것:

```zig
const pty = @import("pty.zig");
const status = @import("status.zig");
const vt = @import("vt.zig");
```

- [ ] **Step 2: 색 상수를 더한다**

`terminal/src/main.zig`에서 지울 것:

```zig
const ROW_HEIGHT: u32 = 16;
```

넣을 것:

```zig
const ROW_HEIGHT: u32 = 16;

/// 상태 줄의 글자 색(IS design 결정 7). 여백(`MARGIN_COLOR`) 위에서 읽히되
/// 눈을 안 끄는 회색이다 — 이것은 터미널의 내용이 아니라 창틀이다.
///
/// **IS-M1이 여기에 둘을 더한다**(`STATUS_ON`·`STATUS_OFF`).
const STATUS_FG: u32 = 0x00808890;
```

- [ ] **Step 3: `drawStatus`를 더한다**

`terminal/src/main.zig`에서 `/// 화면 전체를 지우고 셀 목록을 다시 그린다.`
바로 **앞**에 넣을 것:

```zig
/// 입력기 상태 줄(IS design 결정 6). **격자 바깥의 아래 여백에 그린다** —
/// 터미널 줄을 한 줄도 안 뺏는다.
///
/// ```
/// 격자 아래 끝 = GRID_Y + rows * ROW_HEIGHT = 20 + 47*16 = 772
/// 아래 여백    = fb.height - 772            = 28
/// 글자 줄의 y  = 772 + (28 - 16) / 2        = 778
/// ```
///
/// **`drawPrompt`를 재사용할 수 없다.** 그쪽은 `for (text) |ch|`로 **바이트
/// 하나를 글자 하나로** 세는데(검색 needle이 지금 ASCII뿐이라 여태 안
/// 드러났다), 이 줄에는 `한`처럼 UTF-8 세 바이트짜리 글자가 들어간다. 그대로
/// 두면 글리프 셋이 그려지고 뒤 칸이 전부 두 칸씩 밀린다.
///
/// **폭 2 글자는 두 칸을 전진한다.** `render()`가 격자에서 col을 쓰는 것과
/// 같은 규칙인데, 거기는 라이브러리가 spacer 셀로 col을 미리 맞춰 줬고
/// (TF-M2) 여기는 우리가 센다.
///
/// **여백이 한 줄보다 좁으면 아무것도 안 그린다.** 높이가 다른 화면에서는
/// `rows`가 여백을 다 먹을 수 있는데, 그때 그리면 격자 바깥이 아니라 **화면
/// 밖에** 쓴다 — `setPixel`은 범위를 검사하지 않는다(`drm.zig:149`).
///
/// **띠를 따로 안 지운다.** `render()`가 매 프레임 `fill(MARGIN_COLOR)`로
/// 시작하므로 지난 프레임의 꼬리가 남을 수 없다. `drawPrompt`가 줄 전체를
/// 먼저 칠해야 했던 것은 그쪽이 **격자 안**이라 `fill` 뒤에 셀 배경이 다시
/// 덮이기 때문이고, 여백은 그 덮임이 없다.
fn drawStatus(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    text: []const u8,
    rows: u16,
) !void {
    const grid_bottom = GRID_Y + @as(u32, rows) * ROW_HEIGHT;
    if (fb.height < grid_bottom + ROW_HEIGHT) return;
    const y = grid_bottom + (fb.height - grid_bottom - ROW_HEIGHT) / 2;

    // `statusText`가 만든 문자열이라 UTF-8이 깨질 수 없다. 그래도 catch로
    // 받는 것은, 깨졌을 때 터미널이 죽는 대신 상태 줄만 사라지는 쪽이
    // 낫기 때문이다 — `pushCommit`이 인코딩 실패에 대해 고른 것과 같은 판단이다.
    var view = std.unicode.Utf8View.init(text) catch return;
    var it = view.iterator();
    var col: u32 = 0;
    while (it.nextCodepoint()) |cp| {
        const glyph = try cache.find(cp);
        drawGlyph(fb, glyph, GRID_X + col * CELL_W, y, STATUS_FG);
        // `@max`로 0을 막는다. 폭 0인 글리프가 오면 col이 안 늘어 다음
        // 글자가 같은 자리에 겹쳐 그려지고, 증상이 "글자 하나가 뭉갠 것처럼
        // 보인다"라 원인에서 멀다.
        col += @max(1, glyph.cell_width / CELL_W);
    }
}
```

- [ ] **Step 4: `Status` struct를 더한다**

`terminal/src/main.zig`에서 지울 것:

```zig
const Prompt = struct {
    text: []const u8,
    rows: u16,
    cols: u16,
    fg: u32,
    bg: u32,
};
```

넣을 것:

```zig
const Prompt = struct {
    text: []const u8,
    rows: u16,
    cols: u16,
    fg: u32,
    bg: u32,
};

/// 상태 줄 한 줄에 필요한 것 전부. `Prompt`와 같은 이유로 묶는다 —
/// 호출부가 하나뿐이고, 늘어놓으면 `rows`를 다른 `u16`과 뒤바꿔 넣어도
/// 컴파일이 통과한다.
///
/// **`Prompt`와 달리 optional이 아니다.** 상태 줄은 언제나 뜬다(결정 2).
const Status = struct {
    text: []const u8,
    rows: u16,
};
```

- [ ] **Step 5: `render`가 상태 줄을 받아 그리게 한다**

`terminal/src/main.zig`에서 지울 것:

```zig
fn render(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    cells: []const vt.CellGlyph,
    prompt: ?Prompt,
) !void {
```

넣을 것:

```zig
fn render(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    cells: []const vt.CellGlyph,
    prompt: ?Prompt,
    // **이름이 `status`가 아니다.** 이 파일이 `status.zig`를 그 이름으로
    // import하는데 Zig는 안쪽 블록에서도 이름 가리기를 막는다
    // (HI-M1 실측 8 · SP-M0 실측 9와 같은 자리).
    st: Status,
) !void {
```

이어서 같은 파일에서 지울 것:

```zig
    if (prompt) |p| {
        try drawPrompt(fb, cache, p.text, p.rows, p.cols, p.fg, p.bg);
    }

    try fb.present();
```

넣을 것:

```zig
    if (prompt) |p| {
        try drawPrompt(fb, cache, p.text, p.rows, p.cols, p.fg, p.bg);
    }

    // **프롬프트와 안 겹친다** — 프롬프트는 격자의 마지막 줄이고 이것은 격자
    // 바깥이다. 그래서 순서에 뜻이 없고, `present` 앞이라는 것만 중요하다.
    try drawStatus(fb, cache, st.text, st.rows);

    try fb.present();
```

- [ ] **Step 6: 호출부가 상태 줄을 만들어 넘기게 한다**

`terminal/src/main.zig`에서 지울 것:

```zig
        const frame_start = std.Io.Clock.now(.awake, init.io);
        try render(fb, &cache, cells, prompt);
```

넣을 것:

```zig
        // 상태 줄을 여기서 만든다. **`prompt`와 같은 자리이고 같은 이유다** —
        // 모양은 `main.zig`가 정하고 그리는 함수는 "한 줄을 준 색으로 쓴다"
        // 하나만 안다.
        var status_buf: [status.MAX_LEN]u8 = undefined;
        const status_line: Status = .{
            .text = status.statusText(&key_state, &status_buf),
            .rows = rows,
        };

        const frame_start = std.Io.Clock.now(.awake, init.io);
        try render(fb, &cache, cells, prompt, status_line);
```

- [ ] **Step 7: 빌드가 통과하는 것을 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd terminal && zig build && zig build test
'
```

기대: 둘 다 성공. **이 Task는 아직 화면에 대해 아무것도 증명하지 않는다** —
게스트를 안 띄웠으므로 "그려졌다"의 증거는 Task 4의 `ink fg=` 하나뿐이다.

- [ ] **Step 8: diff를 확인하고 커밋**

```bash
git diff --stat terminal/src/main.zig
git diff terminal/src/main.zig | grep '^-' | grep -v '^---'
```

지운 줄이 **함수 시그니처와 그 앞뒤 문맥뿐**이어야 한다 — 이 파일은 한글
이야기만이 아니므로 지우는 편집은 내용을 직접 읽는다(CC-M0의 규율).

```bash
git add terminal/src/main.zig
git commit -m "Draw the status line in the margin below the grid"
```

---

## Task 3: 상태 줄을 시리얼에 찍는다 (값이 바뀔 때만)

**Files:**
- Modify: `terminal/src/main.zig` — `dumpStatus` · 루프 상태 둘 · 호출 한 줄

- [ ] **Step 1: `dumpStatus`를 더한다**

`terminal/src/main.zig`에서 지울 것:

```zig
fn dumpOverlay(prompt: ?Prompt) void {
    const p = prompt orelse return;
    std.debug.print("terminal: find> overlay text={s}\n", .{p.text});
}
```

넣을 것:

```zig
fn dumpOverlay(prompt: ?Prompt) void {
    const p = prompt orelse return;
    std.debug.print("terminal: find> overlay text={s}\n", .{p.text});
}

/// 입력기 상태 줄을 시리얼에 찍는다(IS-M0). **값이 바뀌었을 때만 찍는다.**
///
/// **RC-M0 실측 7이 시리얼 한 줄에 0.6~8.8밀리초라고 쟀다.** 프레임이 21
/// 밀리초인데 두 줄을 매 프레임 찍으면 최악 18밀리초가 붙는다. 덤으로 로그가
/// 읽기 좋아진다 — **한 줄이 곧 한 번의 전환이다.**
///
/// **첫 프레임은 반드시 찍힌다**(`last_len`이 null이다). 기준선이 없으면
/// 게이트가 "부팅 직후의 상태"를 볼 창구가 없다.
///
/// **줄이 둘인 이유가 이 milestone의 검증 구조다.** 여백은 격자 밖이라
/// `screen>`·`style>`·`ink>`가 하나도 못 본다. `text=`만 있으면 `statusText`가
/// 만든 문자열을 되읽는 것뿐이고 **"글자는 만들었는데 화면에 안 그렸다"를 못
/// 잡는다.** 그래서 띠 안에서 `STATUS_FG`인 픽셀을 직접 센다 — `dumpInk`가
/// `getPixel`로 프레임버퍼를 읽는 것과 같은 방법이다.
///
/// **`render` 뒤에 불러야 한다.** 그 전에 부르면 이전 프레임의 픽셀을 읽는다.
fn dumpStatus(
    fb: drm.Framebuffer,
    text: []const u8,
    rows: u16,
    last: *[status.MAX_LEN]u8,
    last_len: *?usize,
) void {
    if (last_len.*) |n| {
        if (std.mem.eql(u8, last[0..n], text)) return;
    }
    @memcpy(last[0..text.len], text);
    last_len.* = text.len;
    std.debug.print("terminal: status> text={s}\n", .{text});

    // 띠 안에서 우리 색인 픽셀을 센다. `drawStatus`와 **같은 산수로** y를
    // 구해야 한다 — 어긋나면 언제나 0이 나오고, 증상이 "안 그렸다"와 똑같아서
    // 원인을 `drawStatus`에서 찾게 된다.
    const grid_bottom = GRID_Y + @as(u32, rows) * ROW_HEIGHT;
    if (fb.height < grid_bottom + ROW_HEIGHT) {
        std.debug.print("terminal: status> ink fg=0 (no room below the grid)\n", .{});
        return;
    }
    const y = grid_bottom + (fb.height - grid_bottom - ROW_HEIGHT) / 2;

    var count: usize = 0;
    var row: u32 = 0;
    while (row < ROW_HEIGHT) : (row += 1) {
        var col: u32 = 0;
        while (col < fb.width) : (col += 1) {
            if (fb.getPixel(col, y + row) & 0x00FFFFFF == STATUS_FG) count += 1;
        }
    }
    std.debug.print("terminal: status> ink fg={d}\n", .{count});
}
```

- [ ] **Step 2: 루프 상태 둘을 더한다**

`terminal/src/main.zig`에서 지울 것:

```zig
    // 캐시가 자랐을 때만 찍는다. 매 프레임 찍으면 키를 칠 때마다 같은 줄이
    // 반복된다. design 위험 3을 게이트가 볼 수 있게 하는 자리다.
    var last_glyph_count: usize = 0;
```

넣을 것:

```zig
    // 캐시가 자랐을 때만 찍는다. 매 프레임 찍으면 키를 칠 때마다 같은 줄이
    // 반복된다. design 위험 3을 게이트가 볼 수 있게 하는 자리다.
    var last_glyph_count: usize = 0;
    // 마지막으로 찍은 상태 줄. **`?usize`인 것에 뜻이 있다** — 0을 초기값으로
    // 쓰면 "빈 줄을 찍었다"와 "아직 아무것도 안 찍었다"가 안 갈린다.
    var last_status: [status.MAX_LEN]u8 = undefined;
    var last_status_len: ?usize = null;
```

- [ ] **Step 3: 호출을 더한다**

`terminal/src/main.zig`에서 지울 것:

```zig
        dumpScreen(cells);
        dumpHighlight(screen);
        dumpOverlay(prompt);
```

넣을 것:

```zig
        dumpScreen(cells);
        dumpHighlight(screen);
        dumpOverlay(prompt);
        dumpStatus(fb, status_line.text, status_line.rows, &last_status, &last_status_len);
```

- [ ] **Step 4: 빌드가 통과하는 것을 본다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd terminal && zig build && zig build test
'
```

기대: 둘 다 성공.

- [ ] **Step 5: diff를 확인하고 커밋**

```bash
git diff --stat terminal/src/main.zig
git diff terminal/src/main.zig | grep '^-' | grep -v '^---'
```

```bash
git add terminal/src/main.zig
git commit -m "Log the status line whenever it changes"
```

---

## Task 4: 게이트가 상태 줄을 본다

**Files:**
- Modify: `hangul/check.sh` — 헬퍼 하나와 검사 둘

- [ ] **Step 1: 값을 뽑는 헬퍼를 더한다**

`hangul/check.sh`에서 지울 것:

```sh
# 마지막 프레임만 잘라낸다. main.zig가 한 프레임을 screen> 로 시작하므로
```

넣을 것:

```sh
# 마지막 status> text= 줄의 값. **언제나 마지막 줄을 본다** — 그 줄이 곧
# 지금의 상태다(`hangul_field`와 같은 이유).
#
# **함정 둘을 한꺼번에 피한다.**
#   1. `tr -d '\r'` — 시리얼 로그는 줄을 CRLF로 끝내는데 `text=`의 값이 줄
#      끝이다. 안 지우면 `"EN  공세벌 3-P3  쿼티"`와 비교했을 때 **똑같아
#      보이는 값으로 실패한다**(HI-M1 실측 4 · HI-M3 실측 1이 같은 자리다).
#   2. `s/.*text=//` — `hangul_field`처럼 `([^ ]+)`로 잡으면 **첫 칸에서
#      멈춘다.** 이 값에는 공백이 들어 있다.
status_text() {
  grep -a 'terminal: status> text=' "$LOG" | tail -n 1 | tr -d '\r' |
    sed -E 's/.*text=//'
}

# 마지막 `status> ink fg=` 줄의 개수.
status_ink() {
  grep -a 'terminal: status> ink fg=' "$LOG" | tail -n 1 | tr -d '\r' |
    sed -E 's/.*fg=([0-9]+).*/\1/'
}

# 마지막 프레임만 잘라낸다. main.zig가 한 프레임을 screen> 로 시작하므로
```

- [ ] **Step 2: 검사 0a를 더한다 (부팅 직후)**

`hangul/check.sh`에서 지울 것:

```sh
# ── 검사 1: 대조군 — 한글이 꺼져 있으면 키가 PTY로 나간다 ──────────────
```

(`hangul/check.sh:268`이다.)

넣을 것 (지운 줄을 마지막에 그대로 돌려놓는다):

```sh
# ── 검사 0a: 부팅 직후의 상태 줄 ───────────────────────────────────────
#
# **판정이 둘이다.**
#   1. `text=` — `statusText`가 만든 글자가 맞다
#   2. `ink fg=` — **그 글자가 프레임버퍼에 실제로 닿았다**
#
# **둘째가 이 체인에서 상태 줄의 그리기를 보는 유일한 자리다.** 상태 줄은
# 격자 **바깥**의 여백에 있어서 `screen>`·`style>`·`ink>`가 하나도 못 본다 —
# 첫째만 보면 `statusText`가 만든 문자열을 되읽는 것뿐이고 `drawStatus`가
# 통째로 비어 있어도 초록이다.
#
# **자판 칸이 `공세벌 3-P3`인 것이 판정의 절반이다.** 기본값은 `신세벌 PCS`이고
# 게이트 디스크가 `sebeol_3p3`을 심으므로, 설정을 통째로 무시하는 코드는
# 여기서 갈린다(검사 0과 같은 규율).
echo "=== the status line should be drawn in the bottom margin ==="
TEXT="$(status_text)"
if [ "$TEXT" != "EN  공세벌 3-P3  쿼티" ]; then
  report_failure "the status line reads \"${TEXT}\", expected \"EN  공세벌 3-P3  쿼티\""
fi
INK="$(status_ink)"
if [ -z "$INK" ]; then
  report_failure "no 'status> ink fg=' line at all, so dumpStatus never ran"
fi
if [ "$INK" -le 0 ]; then
  report_failure "the status band has no STATUS_FG pixels (fg=${INK}), so nothing was drawn"
fi
echo "the status line reads \"${TEXT}\" and put ${INK} pixel(s) in the margin"

# ── 검사 1: 대조군 — 한글이 꺼져 있으면 키가 PTY로 나간다 ──────────────
```

- [ ] **Step 3: 검사 2a를 더한다 (한/영 전환 뒤)**

`hangul/check.sh`에서 지울 것:

```sh
echo "Shift+Space turned hangul on and sent nothing to the shell"
```

넣을 것:

```sh
echo "Shift+Space turned hangul on and sent nothing to the shell"

# ── 검사 2a: 상태 줄의 첫 칸이 한/영을 따라간다 ────────────────────────
#
# **자판 칸이 안 흔들리는 것도 함께 본다.** 한/영만 바뀌었으므로 뒤 두 칸은
# 같아야 한다 — 통째로 다시 만드는 코드가 자판을 잘못 읽으면 여기서 갈린다.
#
# **키를 하나도 안 더한다.** 검사 2가 이미 `shift-spc`를 눌렀고, 그 전환이
# `Action.hangul` → `needs_redraw` → 새 프레임 → **값이 바뀌었으니 새
# `status>` 줄**을 만든다. IS-M0이 새 갱신 경로를 하나도 안 만들었다는 것의
# 증거가 이 줄이다.
TEXT="$(status_text)"
if [ "$TEXT" != "한  공세벌 3-P3  쿼티" ]; then
  report_failure "after Shift+Space the status line reads \"${TEXT}\", expected \"한  공세벌 3-P3  쿼티\""
fi
echo "the status line followed the toggle: \"${TEXT}\""
```

- [ ] **Step 4: 체인을 단독으로 돌린다**

**약 3~4분** 걸린다(빌드 + 부팅 한 번).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash hangul/check.sh
```

기대: 마지막 줄이 `HI check PASS`. 새 줄 둘이 중간에 보인다.

```
the status line reads "EN  공세벌 3-P3  쿼티" and put NNN pixel(s) in the margin
the status line followed the toggle: "한  공세벌 3-P3  쿼티"
```

**실패했을 때 어디를 보는가.**

| 증상 | 원인 |
|---|---|
| `no 'status> ink fg=' line at all` | Task 3 Step 3의 호출이 안 들어갔다 |
| `text=`가 다르다 | Task 1의 이름 표 또는 Task 3의 `dumpStatus` |
| `fg=0`인데 `text=`는 맞다 | **Task 2의 `drawStatus`다** — y 산수나 `col` 전진 |
| 전환 뒤에도 `EN` | `needs_redraw`가 안 켜졌거나 `status_line`을 루프 밖에서 만들었다 |
| 값이 같아 보이는데 실패한다 | `tr -d '\r'`가 빠졌다(HI-M1 실측 4) |

- [ ] **Step 5: 커밋**

```bash
git add hangul/check.sh
git commit -m "Check that the status line reaches the screen and follows the toggle"
```

---

## Task 5: 루트 게이트 3회전과 문서 갱신

- [ ] **Step 1: 루트 게이트를 돌린다**

**약 18분** 걸린다. 아홉 체인 × 3회.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh ; } 2> /tmp/is-m0.time
tail -3 /tmp/is-m0.time
```

기대: `TARS check PASS: all chains 3/3 consecutive runs succeeded`.

**시간이 얼마나 늘어야 정상인가.** 키를 하나도 안 더했고 새 로그 줄은 전환이
있을 때만 찍히므로 **거의 안 늘어야 한다.** 직전 값이 **18분 43.9초**(2026-09-02
spacer 수정 뒤)다. 몇십 초 안의 차이는 잡음이고(HI-M2 실측 11), **분 단위로
늘었다면 `status>` 줄이 매 프레임 찍히고 있다는 뜻이다** — `dumpStatus`의
"바뀌었을 때만" 조건을 다시 본다.

- [ ] **Step 2: 첫 프레임 시간을 대조한다**

design 위험 4(폰트 캐시에 없는 한글)의 확인이다.

```bash
grep -a 'render> first frame' /tmp/is-m0.time 2>/dev/null || true
```

값은 게이트 로그에 있다. 착수 전 기준선(GL-M3 이후 **11~22밀리초**)과
비교한다. **몇 밀리초 늘어나는 것이 정상이다** — `공세벌 3-P3`의 한글 셋과
`쿼티` 둘이 첫 프레임에 처음 구워진다. 수십 밀리초로 뛰었다면 캐시가 매
프레임 다시 굽고 있다는 뜻이고, 그때는 `cache.count()` 줄이 반복해서 찍힌다.

- [ ] **Step 3: design의 `Status:` 줄을 고친다**

`docs/superpowers/specs/2026-09-02-tars-input-status-design.md`에서 지울 것:

```markdown
**Status:** 착수 전. IS-M0의 plan을 이 문서 다음에 쓴다. milestone은 둘
(IS-M0 · IS-M1)이고, IS-M1의 plan은 IS-M0이 끝난 뒤에 새로 쓴다.
```

넣을 것 (실제 값으로 채운다):

```markdown
**Status:** **IS-M0 완료(2026-09-02).** 상태 줄이 아래 여백에 뜨고 칸이 셋이다
(한/영 · 한글 자판 · 영문 자판). 게이트 아홉 체인 3/3으로 **NN분 NN초**.
plan은 `docs/superpowers/plans/2026-09-02-tars-input-status-is-m0.md`이고 값은
아래 "IS-M0이 실측한 것" 절에 있다. **다음은 IS-M1이고 plan은 그 시점에 새로
쓴다.**
```

- [ ] **Step 4: design에 "IS-M0이 실측한 것" 절을 더한다**

`## 비목표` 절 **바로 앞**에 넣는다. 아래는 자리표가 아니라 **실제로 실행하며
확인한 것만** 적는 자리다. 최소한 다음 넷은 답이 나와 있다.

1. `MAX_LEN`이 30으로 계산됐는가, 검사 10이 정확히 같다고 했는가
2. `status> ink fg=`의 실제 값 (부팅 직후)
3. 게이트 시간과 직전 값(18분 43.9초)의 차이
4. `render> first frame`이 얼마나 늘었는가 (위험 4)

**"안 일어났다"도 값이다** — 예상한 함정을 안 밟았으면 그렇게 적는다.

- [ ] **Step 5: `HANDOFF.md`를 갱신한다**

맨 위 절을 IS-M0 기준으로 다시 쓴다. 반드시 담을 것.

- 진행 중인 서브프로젝트가 **Input Status**이고 **다음이 IS-M1**이라는 것
- 게이트 시간(아홉 체인 3/3)
- "지금 서 있는 것" 목록에 **`status.zig`**와 **`main.zig`의 상태 줄 층**을
  더한다
- 호스트 검사 목록에 **`status_test`**를 더한다
- **`Action.hangul`의 갱신 구멍이 아직 열려 있다**는 것 — IS-M1이 닫는다.
  지금은 대문자 잠금을 안 그리므로 밟을 일이 없다

- [ ] **Step 6: `MEMORY.md`와 `docs/decisions/`를 갱신한다**

`docs/decisions/project_input_status.md`를 새로 만들고 `MEMORY.md`에 한 줄을
더한다. 본문에 담을 것은 **코드를 읽으면 알 수 있는 것이 아니라** 결정의
근거다 — 왜 여백인지, 왜 예쁜 이름인지, `Action.hangul`의 구멍이 왜 지금까지
버그가 아니었는지.

- [ ] **Step 7: 커밋**

```bash
git add docs/superpowers/specs/2026-09-02-tars-input-status-design.md \
        docs/decisions/project_input_status.md \
        HANDOFF.md MEMORY.md
git commit -m "Close out IS-M0 with the status line on screen"
```

---

## 위험

**1. 로그 두 줄을 매 프레임 찍는 것.** Task 3의 "바뀌었을 때만"이 처방이다.
증상은 게이트 시간이 분 단위로 느는 것이고 Task 5 Step 1이 그것을 본다.

**2. `drawStatus`와 `dumpStatus`의 y 산수가 어긋나는 것.** 같은 세 줄이 두
곳에 있다. 어긋나면 `fg=0`이 나오는데 **증상이 "안 그렸다"와 똑같다.** 지금은
두 곳뿐이라 상수로 빼지 않았지만, 셋째가 생기면 그때 뺀다.

**3. `tr -d '\r'`를 빠뜨리는 것.** `status_text`가 **줄 끝의 값을 뽑는 새
헬퍼**이고, HI-M1 실측 4가 "새 헬퍼를 만드는 사람은 같은 함정을 다시 만난다"고
정확히 예고했다. 증상은 **똑같아 보이는 값으로 실패하는 것**이다.

**4. 폰트 캐시에 없는 글자.** 첫 프레임에만 조금 늦는다. Task 5 Step 2가
대조한다.

**5. 이름 가리기.** `render`의 인자를 `status`로 쓰면 import를 가려 컴파일
에러가 난다. Task 2 Step 5가 `st`로 쓰는 이유이고, HI-M1 실측 8 · SP-M0 실측
9와 같은 자리다.
