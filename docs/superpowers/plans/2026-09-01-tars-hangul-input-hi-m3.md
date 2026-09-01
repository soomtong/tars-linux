# HI-M3 — 전환 키 나머지 셋과 CapsLock

**Date:** 2026-09-01
**Design:** `docs/superpowers/specs/2026-08-31-tars-hangul-input-design.md`
**Status:** 착수 전.

## 이 milestone이 끝나면

- **전환 키가 넷이다.** 한/영 키(evdev 122) · Shift+Space · 짧은 CapsLock ·
  짧은 왼쪽 Ctrl. 넷 다 `toggleHangul()` 하나를 지난다.
- **`tars.conf`가 그중 무엇을 켤지 고른다.** `hangul_toggle`이 생기고 **이
  키만 목록이다**(결정 7) — 콤마로 갈라 집합을 만든다. **기본값은 넷 다
  켜진 것이다.**
- **tap-vs-hold가 선다**(결정 8). 누를 때는 아무 판단도 안 하고, 누른 동안
  다른 키가 오면 "소비됨"을 켜고, **뗄 때** 판단한다. 문턱은 0.3초다.
- **CapsLock을 길게 누르면 대문자 잠금이 켜진다**(결정 9). **알파벳에만
  적용되고** 숫자와 기호는 안 바뀐다.
- **`handleKey`가 시각을 보는 함수가 된다.** 이 서브프로젝트에서 유일하게 그
  함수의 성질 자체를 바꾸는 변경이고, 그래서 마지막에 있다.
- **HI-M3이 끝나면 서브프로젝트가 닫힌다.** design doc의 `Status:` 줄과
  `check.sh`의 `CHAINS` 라벨을 함께 고친다.

**아직 안 하는 것.** 기호 확장과 Patal의 옵션 trait들(비목표). 입력기 상태를
화면에 보여 주기(비목표 — 대문자 잠금에 LED도 표시도 없다는 것을 알고 넘어간다,
결정 9). 한/영 키를 게이트로 검증하기(HI-M0 실측 1이 막았다).

**편집도 Claude Code가 한다.** 이 서브프로젝트의 예외이고 근거는 design 실측
7이다. **CC-M0의 규율을 그대로 쓴다** — 매 편집 뒤 `git diff --stat`으로 더한
줄과 지운 줄을 따로 세고, 지우는 편집은 `git diff | grep '^-'`로 내용을 직접
읽는다. **`input.zig`·`init/src/main.zig`·`terminal/src/main.zig`처럼 이미 있는
파일을 건드릴 때는 diff를 사용자에게 보여 준다** — 그쪽은 한글 이야기만이
아니기 때문이다.

## 왜 이 순서인가

**Task 1이 동작을 하나도 안 바꾸는 것이 이 쪼갬의 핵심이다.** `handleKey`의
시그니처를 바꾸는 것이 이 milestone에서 가장 넓게 번지는 변경인데, **기존 검사가
한 글자도 안 바뀐 채 통과하는 것**이 그것이 맞았다는 증거가 된다. tap 판정을
함께 넣으면 실패했을 때 "시각이 안 왔나 판정이 틀렸나"를 가를 수 없다. HI-M2의
Task 1(`Jamo` → `Cand`)이 같은 모양이었고 실측 2가 그 값을 적어 두었다.

**Task 2~3이 설정을 배선한다.** `hangul_toggle`이 없으면 Task 4 이후의 갈래를
켜고 끄는 검사를 쓸 수가 없다. **Task 2는 호스트에서만 돌고**(config 파싱),
Task 3이 argv를 건넌다 — 둘을 나누는 이유는 파싱이 틀렸을 때 argv를 의심할
필요가 없게 하기 위해서다.

**Task 4가 시각을 안 쓰는 갈래를 먼저 세운다.** 한/영 키와 `shift_space` 게이트는
tap과 무관하다. 여기서 `toggleHangul()`이라는 한 자리가 생기고, Task 5·6이 그것을
재사용한다.

**Task 5가 tap 뼈대를 세우고 Task 6이 CapsLock을 얹는다.** 왼쪽 Ctrl이 먼저인
이유는 **`Tap` struct 하나만 검증하면 되기 때문이다** — CapsLock은 거기에 대문자
잠금이라는 두 번째 축이 붙는다.

**Task 7의 게이트가 마지막이다.** 호스트 검사가 전부 통과한 뒤에 부팅한다 —
18분을 쓰기 전에 몇 초로 잡을 수 있는 실패를 먼저 잡는다.

---

## 착수 전에 확정한 것

### 1. `hangul_toggle`의 기본값은 넷 다 켜진 것이다

**2026-09-01에 사용자가 정했다.** `keyboard=apple`·`hangul_layout=shin_pcs`와
같은 종류의 결정이라("이 기계를 쓰는 사람이 쓰는 것") Claude가 못 정한다.

```
hangul_toggle = hangul_key,shift_space,capslock_tap,lctrl_tap
```

근거는 **전환 키가 많아서 곤란한 경우는 없고 없어서 곤란한 경우는 있다**는
것이다. 특히 `hangul_key`는 실기에서만 오는 키라 기본으로 꺼 두면 "왜 한/영
키가 안 먹지"가 된다.

**HI-M1이 적어 둔 "Shift+Space의 대가"는 기본값에서 안 사라지고, 끌 수 있게만
된다.** 그것이 이 설정 항목의 뜻이다.

### 2. 게이트 디스크는 `hangul_key`를 뺀 셋을 심는다

```
hangul_toggle = shift_space,capslock_tap,lctrl_tap
```

**기본값과 달라야 한다** — `make_disk.sh`가 `hangul_layout`에 대해 이미 적어
둔 규칙이고(design 결정 14), 같으면 설정을 통째로 무시하는 코드도 검사 0에서
초록이 뜬다.

**뺄 것으로 `hangul_key`를 고른 이유는 그것이 게이트가 어차피 못 보내는
유일한 키이기 때문이다**(HI-M0 실측 1 — `sendkey lang1`이 게스트에 안 닿는다).
`shift_space`를 뺐다면 기존 검사 2·9·11을 전부 다시 써야 하고, `capslock_tap`
이나 `lctrl_tap`을 뺐다면 이 milestone이 새로 만드는 갈래를 게이트가 못 본다.

**꺼짐의 판정은 로그 줄 하나로 끝난다.** `arg()`가 정규형을 만들므로 로그에
찍히는 문자열에 `hangul_key`가 **없다는 것 자체가** "설정이 그것을 껐다"의
증거다. 설정을 통째로 무시하는 코드는 기본값(넷)을 찍는다.

**꺼짐 갈래 넷은 전부 `input_test`가 호스트에서 본다.**

### 3. `handleKey`는 인자를 하나 더 받는다 — `Context`에 안 넣는다

```zig
pub fn handleKey(self: *State, raw_code: u16, value: i32, time_us: u64, ctx: Context) Action
```

**`Context`에 넣으면 안 되는 이유가 하나 있다.** `Context`는 `readKeys` 호출
하나에 한 번 조립돼 넘어오는데, 시각은 **이벤트마다 다르다.** 한 번의 `read`가
이벤트 64개를 담을 수 있으므로 `readKeys` 안에서 `ctx`를 이벤트마다 복사해
고쳐야 하고, 그러면 "부팅 내내 상수"라는 `swap_alt_meta`의 성질과 같은 자리에
매번 바뀌는 값이 섞인다.

**자리는 `ctx` 앞이다.** `ctx`가 "바깥에서 들어오는 상태"로 맨 뒤에 있는 규약을
유지한다.

### 4. `input_test`의 헬퍼가 시그니처 변경을 흡수한다

`expectCtx` 호출이 **26군데**다. 여기에 인자를 하나 더하면 26줄이 바뀌고, 그러면
**"기존 검사가 한 글자도 안 바뀐 채 통과했다"는 Task 1의 증거가 사라진다.**

그래서 본체를 `expectFull`로 옮기고 기존 헬퍼 넷은 시각 0을 채우는 껍데기가
된다.

```
expect(state, code, value, want)                → expectFull(..., time_us = 0, ...)
expectCtx(state, ctx, code, value, want)        → expectFull(..., time_us = 0, ...)
expectAt(state, code, value, time_us, want)     → expectFull(..., time_us, ...)   ← 새것
expectFull(state, ctx, code, value, time_us, want)                                ← 본체
```

**`Context`가 IP-M1에 들어왔을 때와 정확히 같은 모양이다** — 그때도 `expect`가
기본값을 채우고 DECCKM을 보는 검사만 `expectCtx`를 직접 불렀다.

### 5. "소비됨"을 켜는 자리는 modifier switch **앞**이다

결정 8의 2번("누른 동안 다른 키가 오면 소비됨을 켠다")을 `switch` 뒤에 두면
**Shift·Alt·Meta가 소비로 안 세어진다** — 그 갈래들이 switch 안에서 `return`
하기 때문이다. 증상은 `Ctrl+Shift+C`를 눌렀다 뗄 때마다 한/영이 뒤집히는
것이고, **원인이 "Shift를 안 셌다"라 아주 멀다.**

**자기 자신은 뺀다.** 자동 반복(value=2)이 오면 자기가 자기를 소비한 것이 된다.

### 6. 문턱은 0.3초이고 설정으로 안 뺀다

design 결정 7의 설정 항목이 셋뿐이고 그중 하나가 `hangul_toggle`이다. 문턱을
넷째 항목으로 만들면 **게이트가 못 보는 설정이 하나 는다** — `sendkey`의
`hold_ms`는 게이트가 고르는 값이지 게스트가 고르는 값이 아니다.

QEMU가 `hold_ms`를 오차 4밀리초 안에 지킨다(HI-M0 실측 2). 그래서 게이트가
0.1초와 0.5초로 문턱의 양쪽을 실제로 밟을 수 있다.

### 7. CapsLock은 **뗄 때** 뒤집힌다 — 진짜 CapsLock과 다른 유일한 자리다

진짜 키보드의 CapsLock은 **누르는 순간** 토글된다. 우리는 뗄 때로 미룬다 —
누를 때 뒤집으면 짧게 눌렀다 뗐을 때 대문자 잠금이 한 번 켜졌다 꺼지므로 tap을
만들 수가 없다.

**`capslock_tap`이 꺼져 있어도 갈래를 안 나눈다.** 꺼져 있으면 `tapped`가
무엇이든 대문자 잠금으로 가므로, "언제나 뗄 때"라는 규칙이 하나로 선다.

| 설정 | 짧게(<0.3초, 안 소비됨) | 그 외 |
|---|---|---|
| `capslock_tap` 켜짐 | 한/영 | 대문자 잠금 |
| `capslock_tap` 꺼짐 | 대문자 잠금 | 대문자 잠금 |

왼쪽 Ctrl은 둘째 칸이 **아무 일도 안 일어남**이다 — Ctrl의 원래 뜻은 modifier
이고 그것은 이미 눌릴 때 켜졌다.

### 8. `Toggles` 파서가 두 벌인 것을 받아들인다

`init/src/config.zig`와 `terminal/src/input.zig`가 각각 갖는다. **`HangulLayout`
↔ `hangul.Layout`이 이미 같은 모양이고**(둘을 잇는 것은 argv의 문자열 하나뿐이라
컴파일러가 못 잡는다), `failed()` 헬퍼가 두 파일에 있는 것도 같은 판단이다
(`config.zig:4`).

**문자열 문법을 못 박는 것은 `config_test`의 왕복 검사다** — `arg()`가 만든
정규형을 `parse()`가 되읽어 같은 집합을 준다.

**terminal이 받는 문자열은 언제나 `arg()`가 만든 정규형이다.** 관대한 파싱은
terminal을 손으로 띄울 때를 위한 것이다.

### 9. `none`은 왕복을 위해 파서가 받아 준다

집합이 비었을 때 `arg()`는 빈 문자열이 아니라 `none`을 준다 — 빈 문자열을
argv에 넣으면 terminal 쪽에서 "인자가 없다"와 구분이 안 된다.

그런데 `none`은 `ToggleKey`에 없는 이름이라, 안 막으면 부팅할 때마다
`unknown hangul_toggle 'none'`이 로그에 찍힌다. **파서가 이 이름 하나를 명시적
으로 건너뛴다.**

### 10. 한글 층은 대문자 잠금을 안 본다 — 자동으로 그렇다

`hangulLayer`가 `qwerty_keymap[code][shifted]`를 **직접** 읽고 `latinChar()`를
안 쓰기 때문이다(결정 13). 대문자 잠금은 `latinChar()` 안에만 있으므로 한글
조회에 안 닿는다.

**이것을 검사로 못 박는다.** 안 그러면 나중에 누가 `hangulLayer`를
`latinChar()`로 바꿔 쓰면서 조용히 깨뜨린다 — 증상은 세벌식에서 대문자 칸의
**다른 자모**가 나오는 것이라 원인을 오토마타에서 찾게 된다.

---

## Task 1: 시각을 `handleKey`까지 들여온다 (동작 0 변화)

**Files:**
- Modify: `terminal/src/input.zig` — `handleKey` 시그니처, `readKeys`,
  `eventMicros` 새 함수
- Modify: `terminal/src/input_test.zig` — 헬퍼 넷

- [ ] **Step 1: `eventMicros`를 더한다**

`terminal/src/input.zig`에서 `pub fn readKeys(` 바로 **앞**에 넣을 것:

```zig
/// evdev 이벤트의 시각을 마이크로초 하나로 합친다(HI design 조사 5).
///
/// **커널이 찍은 시각이라 poll 루프가 늦어져도 안 흔들린다.** 한 번의 read가
/// 이벤트 64개를 담을 수 있는데, `Clock.now`를 여기서 부르면 그 64개가 전부
/// 같은 시각을 갖게 되어 tap 판정이 통째로 무너진다.
///
/// 음수는 0으로 떨어뜨린다. `tv_sec`이 음수가 되는 유일한 길은 커널이 고장 난
/// 것이고, 그때 예외를 던지면 키 하나 때문에 터미널이 죽는다 — 이 파일이
/// 바이트를 버릴지언정 안 죽는 쪽을 고르는 것과 같은 판단이다.
fn eventMicros(ev: *align(1) const c.struct_input_event) u64 {
    const sec = ev.time.tv_sec;
    const usec = ev.time.tv_usec;
    if (sec < 0 or usec < 0) return 0;
    return @as(u64, @intCast(sec)) * 1_000_000 + @as(u64, @intCast(usec));
}
```

- [ ] **Step 2: `handleKey`가 시각을 받게 한다**

`terminal/src/input.zig`에서 지울 것:

```zig
    pub fn handleKey(self: *State, raw_code: u16, value: i32, ctx: Context) Action {
        // 0번 단계 — 키보드 보정. modifier를 **기록하기 전에** 맞바꾼다.
        // 인자 이름을 raw_code로 바꾼 것은 실수를 막기 위해서다: 아래에서
        // 실수로 raw_code를 다시 쓰면 보정이 빠진 코드가 흘러가는데, 이름이
        // 다르면 그 실수가 눈에 띈다.
        const code = if (ctx.swap_alt_meta) swapAltMeta(raw_code) else raw_code;

        switch (code) {
```

넣을 것:

```zig
    /// **HI-M3부터 시각도 받는다.** 이 서브프로젝트에서 유일하게 이 함수의
    /// 성질 자체를 바꾸는 변경이고(순수 함수 → 시각을 보는 함수), 그래서
    /// 마지막 milestone에 뒀다(design 결정 8).
    ///
    /// 값은 `ev.time`이 준 마이크로초다. **`Context`에 안 넣은 이유**는 그것이
    /// `readKeys` 호출 하나에 한 번 조립되는 값인데 시각은 이벤트마다 다르기
    /// 때문이다 — `swap_alt_meta`처럼 "부팅 내내 상수"인 값과 같은 자리에
    /// 두면 읽는 사람이 속는다.
    pub fn handleKey(
        self: *State,
        raw_code: u16,
        value: i32,
        time_us: u64,
        ctx: Context,
    ) Action {
        // 0번 단계 — 키보드 보정. modifier를 **기록하기 전에** 맞바꾼다.
        // 인자 이름을 raw_code로 바꾼 것은 실수를 막기 위해서다: 아래에서
        // 실수로 raw_code를 다시 쓰면 보정이 빠진 코드가 흘러가는데, 이름이
        // 다르면 그 실수가 눈에 띈다.
        const code = if (ctx.swap_alt_meta) swapAltMeta(raw_code) else raw_code;
        // **Task 5가 이 두 줄을 지운다.** 지금은 시각을 배선만 하고 아무
        // 판단도 하지 않는다 — 그래야 "기존 검사가 한 글자도 안 바뀐 채
        // 통과했다"가 시그니처 변경이 맞았다는 증거가 된다. Zig는 안 쓰는
        // 인자를 컴파일 에러로 막으므로 자리를 채워 두어야 한다.
        _ = time_us;

        switch (code) {
```

- [ ] **Step 3: `readKeys`가 시각을 넘기게 한다**

`terminal/src/input.zig`에서 지울 것:

```zig
        if (ev.@"type" != c.EV_KEY) continue;
        const action = self.handleKey(ev.code, ev.value, ctx);
```

넣을 것:

```zig
        if (ev.@"type" != c.EV_KEY) continue;
        // **이 값은 이미 손에 있었다**(HI-M0 실측 3). `readKeys`가
        // `struct_input_event`를 통째로 읽고 있었고 `ev.time`만 버리고 있었다.
        const action = self.handleKey(ev.code, ev.value, eventMicros(ev), ctx);
```

- [ ] **Step 4: `input_test`의 헬퍼 넷이 변경을 흡수하게 한다**

`terminal/src/input_test.zig`에서 지울 것:

```zig
fn expect(state: *input.State, code: u16, value: i32, want: []const u8) !void {
    return expectCtx(state, .{}, code, value, want);
}
```

넣을 것:

```zig
fn expect(state: *input.State, code: u16, value: i32, want: []const u8) !void {
    return expectFull(state, .{}, code, value, 0, want);
}

/// HI-M3부터 `handleKey`는 시각도 받는다. **본체를 `expectFull`로 옮기고 기존
/// 헬퍼는 시각 0을 채우는 껍데기가 된다** — `expectCtx` 호출이 26군데라
/// 인자를 하나 더하면 26줄이 바뀌고, 그러면 "기존 검사가 한 글자도 안 바뀐 채
/// 통과했다"는 Task 1의 증거가 사라진다.
///
/// `Context`가 IP-M1에 들어왔을 때와 정확히 같은 모양이다.
fn expectAt(
    state: *input.State,
    code: u16,
    value: i32,
    time_us: u64,
    want: []const u8,
) !void {
    return expectFull(state, .{}, code, value, time_us, want);
}
```

이어서 지울 것:

```zig
fn expectCtx(
    state: *input.State,
    ctx: input.Context,
    code: u16,
    value: i32,
    want: []const u8,
) !void {
    switch (state.handleKey(code, value, ctx)) {
```

넣을 것:

```zig
fn expectCtx(
    state: *input.State,
    ctx: input.Context,
    code: u16,
    value: i32,
    want: []const u8,
) !void {
    return expectFull(state, ctx, code, value, 0, want);
}

fn expectFull(
    state: *input.State,
    ctx: input.Context,
    code: u16,
    value: i32,
    time_us: u64,
    want: []const u8,
) !void {
    switch (state.handleKey(code, value, time_us, ctx)) {
```

- [ ] **Step 5: 나머지 헬퍼 셋의 `handleKey` 호출을 고친다**

`terminal/src/input_test.zig`의 `expectCopy`에서 지울 것:

```zig
    switch (state.handleKey(code, 1, .{})) {
        .copy => |cmd| {
```

넣을 것:

```zig
    switch (state.handleKey(code, 1, 0, .{})) {
        .copy => |cmd| {
```

`expectScroll`에서 지울 것:

```zig
    switch (state.handleKey(code, value, .{})) {
        .scroll => |s| {
```

넣을 것:

```zig
    switch (state.handleKey(code, value, 0, .{})) {
        .scroll => |s| {
```

- [ ] **Step 6: `expectHangul`을 시각을 받는 형태로 나눈다**

`terminal/src/input_test.zig`에서 지울 것:

```zig
fn expectHangul(
    state: *input.State,
    code: u16,
    want_commit: []const u8,
    want_preedit: ?u21,
) !void {
    switch (state.handleKey(code, 1, .{})) {
        .hangul => {},
```

넣을 것:

```zig
fn expectHangul(
    state: *input.State,
    code: u16,
    want_commit: []const u8,
    want_preedit: ?u21,
) !void {
    return expectHangulAt(state, code, 1, 0, want_commit, want_preedit);
}

/// 시각과 누름/뗌을 직접 주는 형태(HI-M3). **tap이 한/영을 바꾸는 것은 키를
/// 뗄 때이므로**(결정 8) `value = 0`을 넣을 수 있어야 하는데, 위 껍데기는
/// 언제나 누름(1)이다.
fn expectHangulAt(
    state: *input.State,
    code: u16,
    value: i32,
    time_us: u64,
    want_commit: []const u8,
    want_preedit: ?u21,
) !void {
    switch (state.handleKey(code, value, time_us, .{})) {
        .hangul => {},
```

- [ ] **Step 7: 검사를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && ./prepare.sh >/dev/null && zig build test'
```

기대: `input_test: ... OK` 줄들과 `PASS`가 전부 그대로. **한 줄도 안 바뀌어야
한다** — 바뀌면 시각 배선이 동작을 건드린 것이다.

- [ ] **Step 8: diff를 사용자에게 보여 주고 커밋한다**

```bash
git diff --stat
git diff terminal/src/input.zig
git add terminal/src/input.zig terminal/src/input_test.zig
git commit -m "Give handleKey the timestamp the kernel already put on each event"
```

---

## Task 2: `hangul_toggle` 설정 (호스트에서만 돈다)

**Files:**
- Modify: `init/src/config.zig` — `ToggleKey` · `Toggles` · `TOGGLE_ARG_MAX` ·
  `appendToggleName` · `Config.hangul_toggle` · `parse` · `save`
- Modify: `init/src/config_test.zig` — 비교 함수를 넓히고 검사 열둘을 더한다

- [ ] **Step 1: `ToggleKey`와 `Toggles`를 더한다**

`init/src/config.zig`에서 지울 것(`LatinLayout`의 끝. **`Config`의 doc 주석
바로 앞이 아니라 이 자리를 앵커로 삼는 이유는 `Config` 위에 주석 블록이 네 줄
있어서 "앞"이 어디인지 흐리기 때문이다**):

```zig
    pub fn arg(self: LatinLayout) [:0]const u8 {
        return switch (self) {
            .qwerty => "qwerty",
            .dvorak => "dvorak",
        };
    }
};
```

넣을 것:

```zig
    pub fn arg(self: LatinLayout) [:0]const u8 {
        return switch (self) {
            .qwerty => "qwerty",
            .dvorak => "dvorak",
        };
    }
};

/// 한/영 전환 키(HI design 결정 7).
///
/// **`Shell`·`Keyboard`·자판 둘과 모양이 다른 유일한 설정이다.** 그 넷은
/// 하나를 고르는 것이지만 전환 키는 배타적이지 않다 — 한/영 키를 쓰면서
/// CapsLock도 쓰는 것이 정상이다. 그래서 enum 하나가 아니라 아래 `Toggles`
/// 집합이 값이 되고, 이 enum은 **이름의 화이트리스트** 역할만 한다.
pub const ToggleKey = enum {
    /// 실기의 한/영 키(evdev 122). **게이트가 못 보낸다** — QEMU가
    /// `sendkey lang1`을 이름만 받고 조용히 버린다(HI-M0 실측 1). 그래서 이
    /// 갈래를 덮는 것은 `input_test`의 호스트 검사뿐이다.
    hangul_key,
    /// Shift+Space. HI-M1이 유일한 전환 키로 골랐던 것이고 이제 끌 수 있다 —
    /// `HELLO WORLD`를 칠 때 한/영이 바뀌는 것이 그 대가였다.
    shift_space,
    /// CapsLock을 **짧게** 눌렀다 뗀 것. 길게 누르면 대문자 잠금이다(결정 9).
    capslock_tap,
    /// 왼쪽 Ctrl을 **짧게** 눌렀다 뗀 것. 누른 동안 다른 키가 오면 평범한
    /// modifier이므로 아무 일도 안 일어난다(결정 8).
    lctrl_tap,
};

/// `Toggles.arg`가 만드는 문자열을 담을 버퍼의 크기. 넷을 전부 켠 목록이
/// 45바이트이고 NUL 하나가 더 든다.
pub const TOGGLE_ARG_MAX = 64;

comptime {
    const longest = "hangul_key,shift_space,capslock_tap,lctrl_tap";
    if (longest.len + 1 > TOGGLE_ARG_MAX)
        @compileError("TOGGLE_ARG_MAX is too small for the full toggle list");
}

/// 켜진 전환 키의 집합.
pub const Toggles = struct {
    hangul_key: bool = false,
    shift_space: bool = false,
    capslock_tap: bool = false,
    lctrl_tap: bool = false,

    /// 콤마 목록을 집합으로 바꾼다.
    ///
    /// **모르는 이름은 로그만 남기고 넘어간다** — 설정 파일은 사람이 손으로
    /// 고치는 물건이라 깨진 입력이 예외가 아니라 규칙이라는 CP의 판단 그대로다.
    /// 그 규칙이 **목록 안에서도** 서는 것이 여기서 새로운 점이다: 이름 하나가
    /// 틀려도 나머지는 살아남는다.
    ///
    /// **빈 값(`hangul_toggle=`)은 뜻이 있는 입력이다.** 기본값으로 떨어뜨리지
    /// 않는다 — 그러면 전환 키를 전부 끌 방법이 없어진다.
    pub fn parse(value: []const u8) Toggles {
        var t = Toggles{};
        var it = std.mem.splitScalar(u8, value, ',');
        while (it.next()) |raw| {
            const name = std.mem.trim(u8, raw, " \t");
            if (name.len == 0) continue;
            // `arg()`가 빈 집합에 쓰는 이름이다. **왕복을 위해 여기서 받는다** —
            // 안 받으면 전환 키를 다 끈 사람의 부팅 로그에 매번
            // "모르는 이름 none"이 찍힌다.
            if (std.mem.eql(u8, name, "none")) continue;
            const key = std.meta.stringToEnum(ToggleKey, name) orelse {
                std.debug.print("tars-init: unknown hangul_toggle '{s}', ignored\n", .{name});
                continue;
            };
            switch (key) {
                .hangul_key => t.hangul_key = true,
                .shift_space => t.shift_space = true,
                .capslock_tap => t.capslock_tap = true,
                .lctrl_tap => t.lctrl_tap = true,
            }
        }
        return t;
    }

    /// argv로 넘기고 로그에 찍을 **정규형** 콤마 목록. 버퍼는 호출자가 준다 —
    /// 이 파일에는 힙이 없고, `Keyboard.arg()`처럼 상수 문자열을 돌려줄 수도
    /// 없다(조합이 열여섯 가지다).
    ///
    /// **정규화가 이 함수의 값이다.** 설정 파일에 어떤 순서로 적었든 enum 선언
    /// 순서로 나오므로, 로그에 찍힌 문자열 하나가 곧 집합 전체다. HI 게이트가
    /// 그 줄 하나로 "무엇이 켜지고 무엇이 꺼졌는가"를 본다.
    ///
    /// 하나도 안 켜졌으면 `none`이다 — 빈 문자열을 argv에 넣으면 terminal
    /// 쪽에서 "인자가 없다"와 구분이 안 된다.
    pub fn arg(self: Toggles, buf: []u8) [:0]const u8 {
        var len: usize = 0;
        if (self.hangul_key) appendToggleName(buf, &len, "hangul_key");
        if (self.shift_space) appendToggleName(buf, &len, "shift_space");
        if (self.capslock_tap) appendToggleName(buf, &len, "capslock_tap");
        if (self.lctrl_tap) appendToggleName(buf, &len, "lctrl_tap");
        if (len == 0) appendToggleName(buf, &len, "none");
        buf[len] = 0;
        return buf[0..len :0];
    }
};

/// `Toggles.arg`가 쓰는 이어붙이기. 첫 항목이 아니면 콤마를 먼저 넣는다.
///
/// **모자라면 자른다.** 위 `comptime`이 `TOGGLE_ARG_MAX`가 최악의 경우보다
/// 크다는 것을 못 박으므로 이 길로 실제로 갈 일은 없고, 그래도 배열 밖을
/// 쓰지 않는 쪽으로 적어 둔다. `len.* + 1`을 보는 것은 `buf[len]`에 들어갈
/// NUL 한 칸을 남기기 위해서다.
fn appendToggleName(buf: []u8, len: *usize, name: []const u8) void {
    if (len.* > 0) {
        if (len.* + 1 >= buf.len) return;
        buf[len.*] = ',';
        len.* += 1;
    }
    for (name) |ch| {
        if (len.* + 1 >= buf.len) return;
        buf[len.*] = ch;
        len.* += 1;
    }
}
```

- [ ] **Step 2: `Config`에 필드를 더한다**

`init/src/config.zig`에서 지울 것:

```zig
    hangul_layout: HangulLayout = .shin_pcs,
    latin_layout: LatinLayout = .qwerty,
};
```

넣을 것:

```zig
    hangul_layout: HangulLayout = .shin_pcs,
    latin_layout: LatinLayout = .qwerty,
    /// **기본값은 넷 다 켜진 것이다**(2026-09-01에 사용자가 정했다).
    /// 전환 키가 많아서 곤란한 경우는 없고 없어서 곤란한 경우는 있다 —
    /// 특히 `hangul_key`는 실기에서만 오는 키라 기본으로 꺼 두면 "왜 한/영
    /// 키가 안 먹지"가 된다.
    hangul_toggle: Toggles = .{
        .hangul_key = true,
        .shift_space = true,
        .capslock_tap = true,
        .lctrl_tap = true,
    },
};
```

- [ ] **Step 3: `parse`에 키를 더한다**

`init/src/config.zig`에서 지울 것:

```zig
        } else {
            std.debug.print("tars-init: unknown config key '{s}'\n", .{key});
        }
```

넣을 것:

```zig
        } else if (std.mem.eql(u8, key, "hangul_toggle")) {
            // **앞의 넷과 모양이 다른 유일한 키다**(결정 7). `stringToEnum`
            // 하나로 안 끝나고 콤마로 갈라야 한다. 모르는 이름을 흘려보내는
            // 규칙은 같고, 그 규칙이 **목록 안에서도** 선다.
            c.hangul_toggle = Toggles.parse(value);
        } else {
            std.debug.print("tars-init: unknown config key '{s}'\n", .{key});
        }
```

- [ ] **Step 4: `save`의 씨앗 파일에 두 줄을 더한다**

`init/src/config.zig`에서 지울 것:

```zig
pub fn save(path: [:0]const u8, c: Config) SaveError!void {
    var buf: [MAX_FILE]u8 = undefined;
    const text = std.fmt.bufPrint(&buf,
```

넣을 것:

```zig
pub fn save(path: [:0]const u8, c: Config) SaveError!void {
    var buf: [MAX_FILE]u8 = undefined;
    // `Toggles`만 상수 문자열이 아니라 조립해야 한다(조합이 열여섯 가지다).
    // 이 배열은 아래 bufPrint가 값을 복사할 때까지만 살아 있으면 된다.
    var toggle_buf: [TOGGLE_ARG_MAX]u8 = undefined;
    const text = std.fmt.bufPrint(&buf,
```

이어서 지울 것:

```zig
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

넣을 것:

```zig
        \\# latin_layout: qwerty | dvorak
        \\#   한글 자판은 물리 키 위치를 쓰므로 이 값에 안 흔들린다
        \\latin_layout={s}
        \\# hangul_toggle: hangul_key | shift_space | capslock_tap | lctrl_tap
        \\#   콤마로 여럿을 켠다. 빈 값이면 전환 키가 하나도 없다
        \\#   CapsLock과 왼쪽 Ctrl은 0.3초보다 **짧게** 눌렀다 뗐을 때만 한/영이고,
        \\#   길게 누르면 CapsLock은 대문자 잠금, Ctrl은 평소의 Ctrl이다
        \\hangul_toggle={s}
        \\
    , .{
        @tagName(c.shell),
        @tagName(c.keyboard),
        @tagName(c.hangul_layout),
        @tagName(c.latin_layout),
        c.hangul_toggle.arg(&toggle_buf),
    }) catch return error.FormatFailed;
```

- [ ] **Step 5: `config_test`의 비교 함수를 넓힌다**

**이 Step을 빠뜨리면 아래 검사 열둘이 전부 아무것도 안 보고 초록이 뜬다.**
HI-M2 실측 8과 SP-M0 실측 4가 정확히 같은 자리다.

`init/src/config_test.zig`에서 지울 것:

```zig
fn expect(text: []const u8, want: config.Config) !void {
    const got = config.parse(text);
    if (got.shell == want.shell and got.keyboard == want.keyboard and
        got.hangul_layout == want.hangul_layout and
        got.latin_layout == want.latin_layout) return;
    std.debug.print(
        "FAIL: input={s}\n  got  shell={s} keyboard={s} hangul={s} latin={s}\n" ++
            "  want shell={s} keyboard={s} hangul={s} latin={s}\n",
        .{
            text,
            @tagName(got.shell),
            @tagName(got.keyboard),
            @tagName(got.hangul_layout),
            @tagName(got.latin_layout),
            @tagName(want.shell),
            @tagName(want.keyboard),
            @tagName(want.hangul_layout),
            @tagName(want.latin_layout),
        },
    );
    return error.UnexpectedConfig;
}
```

넣을 것:

```zig
fn expect(text: []const u8, want: config.Config) !void {
    const got = config.parse(text);
    if (got.shell == want.shell and got.keyboard == want.keyboard and
        got.hangul_layout == want.hangul_layout and
        got.latin_layout == want.latin_layout and
        // **`std.meta.eql`인 이유는 `Toggles`가 struct이기 때문이다** —
        // 앞의 넷은 enum이라 `==`가 되지만 이쪽은 필드 넷을 비교해야 한다.
        std.meta.eql(got.hangul_toggle, want.hangul_toggle)) return;
    var got_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    var want_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    std.debug.print(
        "FAIL: input={s}\n  got  shell={s} keyboard={s} hangul={s} latin={s} toggles={s}\n" ++
            "  want shell={s} keyboard={s} hangul={s} latin={s} toggles={s}\n",
        .{
            text,
            @tagName(got.shell),
            @tagName(got.keyboard),
            @tagName(got.hangul_layout),
            @tagName(got.latin_layout),
            got.hangul_toggle.arg(&got_buf),
            @tagName(want.shell),
            @tagName(want.keyboard),
            @tagName(want.hangul_layout),
            @tagName(want.latin_layout),
            want.hangul_toggle.arg(&want_buf),
        },
    );
    return error.UnexpectedConfig;
}
```

- [ ] **Step 6: 검사를 더한다**

`init/src/config_test.zig`에서 지울 것:

```zig
    std.debug.print("PASS\n", .{});
}
```

넣을 것:

```zig
    // ── HI-M3: hangul_toggle ────────────────────────────────────────────
    //
    // **이 키만 목록이다.** 앞의 넷은 하나를 고르지만 전환 키는 배타적이지
    // 않다 — 한/영 키를 쓰면서 CapsLock도 쓰는 것이 정상이다.
    const none = config.Toggles{};

    // 빈 값은 **뜻이 있는 입력이다.** `shell=`이 기본값으로 떨어지는 것과
    // 다르다 — 여기서 기본값으로 떨어지면 전환 키를 전부 끌 방법이 없어진다.
    try expect("hangul_toggle=\n", .{ .hangul_toggle = none });

    try expect("hangul_toggle=hangul_key\n", .{
        .hangul_toggle = .{ .hangul_key = true },
    });
    try expect("hangul_toggle=capslock_tap,lctrl_tap\n", .{
        .hangul_toggle = .{ .capslock_tap = true, .lctrl_tap = true },
    });

    // 공백과 순서. **정규화되므로 적은 순서는 결과에 안 남는다.**
    try expect("hangul_toggle= lctrl_tap , shift_space \n", .{
        .hangul_toggle = .{ .shift_space = true, .lctrl_tap = true },
    });

    // 모르는 이름 하나가 나머지를 안 죽인다. **"한 줄이 깨져도 살아남는다"는
    // 규칙이 목록 안에서도 서는지 보는 자리다.**
    try expect("hangul_toggle=hangul_key,nosuch,lctrl_tap\n", .{
        .hangul_toggle = .{ .hangul_key = true, .lctrl_tap = true },
    });

    // 빈 항목은 건너뛴다.
    try expect("hangul_toggle=,,\n", .{ .hangul_toggle = none });

    // **다른 키의 이름이 새어 들어가지 않는다.** `dubeol`은 자판 이름이고
    // `pc`는 키보드 이름이다 — 화이트리스트가 키마다 따로 선다.
    try expect("hangul_toggle=dubeol\n", .{ .hangul_toggle = none });
    try expect("hangul_toggle=pc\n", .{ .hangul_toggle = none });

    // 넷 다 — 기본값과 같다.
    try expect("hangul_toggle=hangul_key,shift_space,capslock_tap,lctrl_tap\n", .{});

    // HI 게이트가 심는 값. **`hangul_key`가 빠진 것이 요점이다** — 기본값과
    // 달라야 게이트 검사 0이 뜻을 갖는다(design 결정 14와 같은 논리).
    try expect("hangul_toggle=shift_space,capslock_tap,lctrl_tap\n", .{
        .hangul_toggle = .{
            .shift_space = true,
            .capslock_tap = true,
            .lctrl_tap = true,
        },
    });

    // 다섯 키가 함께. 다른 키를 안 건드린다는 것까지 본다.
    try expect(
        "shell=bash\nkeyboard=pc\nhangul_layout=sebeol_3p3\nlatin_layout=dvorak\n" ++
            "hangul_toggle=capslock_tap\n",
        .{
            .shell = .bash,
            .keyboard = .pc,
            .hangul_layout = .sebeol_3p3,
            .latin_layout = .dvorak,
            .hangul_toggle = .{ .capslock_tap = true },
        },
    );

    // ── `arg()` → `parse()` 왕복 ────────────────────────────────────────
    //
    // **이 왕복이 argv 배선의 계약이다.** init이 `arg()`로 쓰고 terminal이
    // 같은 문법으로 읽는데, 둘을 잇는 것은 문자열 하나뿐이라 컴파일러가 못
    // 잡는다 — `HangulLayout` ↔ `hangul.Layout`과 정확히 같은 자리다.
    var arg_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    const all = config.Toggles{
        .hangul_key = true,
        .shift_space = true,
        .capslock_tap = true,
        .lctrl_tap = true,
    };
    const all_text = all.arg(&arg_buf);
    if (!std.mem.eql(u8, all_text, "hangul_key,shift_space,capslock_tap,lctrl_tap")) {
        std.debug.print("FAIL: Toggles.arg gave \"{s}\"\n", .{all_text});
        return error.UnexpectedToggleArg;
    }
    if (!std.meta.eql(config.Toggles.parse(all_text), all)) {
        std.debug.print("FAIL: Toggles.arg -> parse did not round-trip\n", .{});
        return error.ToggleRoundTripFailed;
    }

    // **순서가 정규화된다는 것을 여기서 못 박는다.** 거꾸로 적어도 같은
    // 문자열이 나오므로, 게이트가 로그에서 읽는 값이 흔들리지 않는다.
    const reversed = config.Toggles.parse("lctrl_tap,capslock_tap,shift_space,hangul_key");
    var rev_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    if (!std.mem.eql(u8, reversed.arg(&rev_buf), all_text)) {
        std.debug.print("FAIL: Toggles.arg is not order-normalized\n", .{});
        return error.UnexpectedToggleArg;
    }

    // 빈 집합은 `none`이고, **그 `none`은 다시 빈 집합으로 돌아온다.**
    // 파서가 이 이름 하나를 명시적으로 건너뛰기 때문이고, 안 그러면 전환 키를
    // 다 끈 사람의 부팅 로그에 매번 "모르는 이름 none"이 찍힌다.
    var none_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    const none_text = none.arg(&none_buf);
    if (!std.mem.eql(u8, none_text, "none")) {
        std.debug.print("FAIL: empty Toggles gave \"{s}\", want \"none\"\n", .{none_text});
        return error.UnexpectedToggleArg;
    }
    if (!std.meta.eql(config.Toggles.parse(none_text), none)) {
        std.debug.print("FAIL: \"none\" did not round-trip to an empty set\n", .{});
        return error.ToggleRoundTripFailed;
    }

    std.debug.print("PASS\n", .{});
}
```

- [ ] **Step 7: 검사를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd init && zig build && zig build test'
```

기대: `PASS`. **기존 검사 스물넷도 전부 그대로 통과해야 한다** — `.{}`의
기본값에 `hangul_toggle`이 늘었을 뿐이고, 어느 기존 입력도 그 값을 안 건드린다.

- [ ] **Step 8: 커밋**

```bash
git diff --stat
git add init/src/config.zig init/src/config_test.zig
git commit -m "Let the config file pick which keys switch between hangul and latin"
```

---

## Task 3: 설정을 argv로 terminal까지 나른다

**Files:**
- Modify: `init/src/main.zig` — `Child.argv`를 8칸으로, 로그 줄, argv 조립
- Modify: `terminal/src/input.zig` — `Toggles` · `parseToggles` · `togglesArg` ·
  `State.toggles`
- Modify: `terminal/src/main.zig` — argv[7]을 읽고 로그에 찍는다

- [ ] **Step 1: `input.zig`에 집합과 파서를 더한다**

`terminal/src/input.zig`에서 지울 것:

```zig
pub const LatinLayout = enum { qwerty, dvorak };
```

넣을 것:

```zig
pub const LatinLayout = enum { qwerty, dvorak };

/// 켜진 한/영 전환 키의 집합(HI design 결정 7).
///
/// **`init/src/config.zig`의 `Toggles`와 짝이다.** 거기가 "설정 파일에 무엇을
/// 적을 수 있는가"이고 여기가 "그것이 키를 어떻게 바꾸는가"인데, 둘을 잇는
/// 것은 argv의 문자열 하나뿐이라 컴파일러가 못 잡는다 — `HangulLayout`과
/// `hangul.Layout`이 이미 정확히 같은 모양이다. **문자열 문법을 못 박는 것은
/// `config_test`의 `arg` → `parse` 왕복 검사다.**
pub const Toggles = struct {
    hangul_key: bool = false,
    shift_space: bool = false,
    capslock_tap: bool = false,
    lctrl_tap: bool = false,
};

/// `togglesArg`가 만드는 문자열을 담을 버퍼의 크기. `config.zig`의
/// `TOGGLE_ARG_MAX`와 같은 값이다.
pub const TOGGLE_ARG_MAX = 64;

/// `parseToggles`가 이름을 거르는 화이트리스트. `config.zig`의 `ToggleKey`와
/// 이름이 같아야 한다.
const ToggleKey = enum { hangul_key, shift_space, capslock_tap, lctrl_tap };

/// 콤마 목록을 집합으로 바꾼다.
///
/// **init이 화이트리스트를 이미 거쳤으므로 여기 도착하는 값은 언제나
/// 정규형이다.** 공백을 떼고 모르는 이름을 흘려보내는 관대함은 terminal을
/// 손으로 띄울 때를 위한 것이고, 로그는 안 남긴다 — init이 이미 한 번 경고를
/// 찍었으므로 같은 줄을 두 번 낼 이유가 없다.
pub fn parseToggles(text: []const u8) Toggles {
    var t = Toggles{};
    var it = std.mem.splitScalar(u8, text, ',');
    while (it.next()) |raw| {
        const name = std.mem.trim(u8, raw, " \t");
        // 빈 항목과 `none`과 모르는 이름이 전부 여기서 떨어진다.
        const key = std.meta.stringToEnum(ToggleKey, name) orelse continue;
        switch (key) {
            .hangul_key => t.hangul_key = true,
            .shift_space => t.shift_space = true,
            .capslock_tap => t.capslock_tap = true,
            .lctrl_tap => t.lctrl_tap = true,
        }
    }
    return t;
}

/// 로그에 찍을 **정규형** 목록. `config.zig`의 `Toggles.arg`와 같은 문자열을
/// 만든다.
///
/// **파싱한 결과를 다시 문자열로 만드는 것이 요점이다.** argv로 받은 문자열을
/// 그대로 찍으면 "글자가 도착했다"만 증명되고 "우리가 그것을 맞게 읽었다"는
/// 아무것도 증명되지 않는다 — `terminal: hangul layout=`이 `stringToEnum`을
/// 거친 값을 `@tagName`으로 찍는 것과 같은 이유다.
pub fn togglesArg(t: Toggles, buf: []u8) [:0]const u8 {
    var len: usize = 0;
    if (t.hangul_key) appendToggleName(buf, &len, "hangul_key");
    if (t.shift_space) appendToggleName(buf, &len, "shift_space");
    if (t.capslock_tap) appendToggleName(buf, &len, "capslock_tap");
    if (t.lctrl_tap) appendToggleName(buf, &len, "lctrl_tap");
    if (len == 0) appendToggleName(buf, &len, "none");
    buf[len] = 0;
    return buf[0..len :0];
}

fn appendToggleName(buf: []u8, len: *usize, name: []const u8) void {
    if (len.* > 0) {
        if (len.* + 1 >= buf.len) return;
        buf[len.*] = ',';
        len.* += 1;
    }
    for (name) |ch| {
        if (len.* + 1 >= buf.len) return;
        buf[len.*] = ch;
        len.* += 1;
    }
}
```

- [ ] **Step 2: `State`에 필드를 더한다**

`terminal/src/input.zig`에서 지울 것:

```zig
    /// 영문 자판(HI-M2). `hangul_layout`과 마찬가지로 부팅 내내 상수다.
    latin_layout: LatinLayout = .qwerty,
```

넣을 것:

```zig
    /// 영문 자판(HI-M2). `hangul_layout`과 마찬가지로 부팅 내내 상수다.
    latin_layout: LatinLayout = .qwerty,

    /// 켜진 한/영 전환 키(HI-M3). **부팅 내내 상수다** — 자판 둘과 같은
    /// 성질이고 설정 파일이 정한다.
    ///
    /// **기본값은 `config.zig`의 `Config`와 같아야 한다.** 진실은 그쪽에 있고
    /// 여기 값은 `main.zig`가 argv로 매번 덮어쓰지만, 둘이 어긋나 있으면 읽는
    /// 사람이 어느 쪽이 기본인지 알 수 없다.
    toggles: Toggles = .{
        .hangul_key = true,
        .shift_space = true,
        .capslock_tap = true,
        .lctrl_tap = true,
    },
```

- [ ] **Step 3: `init/src/main.zig`의 argv를 8칸으로 넓힌다**

`init/src/main.zig`에서 지울 것:

```zig
    /// IP-M2에서 셋에서 넷으로, HD-M0에서 넷에서 다섯으로, **HI-M2에서
    /// 다섯에서 일곱으로** 늘었다. terminal이 받는 넷째가 keyboard, 다섯째가
    /// 키보드 장치 경로, 여섯째가 한글 자판, 일곱째가 영문 자판이고, 콘솔
    /// 셸은 그 자리를 전부 null로 둔다.
    argv: [7:null]?[*:0]const u8,
```

넣을 것:

```zig
    /// IP-M2에서 셋에서 넷으로, HD-M0에서 넷에서 다섯으로, HI-M2에서
    /// 다섯에서 일곱으로, **HI-M3에서 일곱에서 여덟으로** 늘었다. terminal이
    /// 받는 넷째가 keyboard, 다섯째가 키보드 장치 경로, 여섯째가 한글 자판,
    /// 일곱째가 영문 자판, 여덟째가 한/영 전환 키 목록이고, 콘솔 셸은 그
    /// 자리를 전부 null로 둔다.
    argv: [8:null]?[*:0]const u8,
```

- [ ] **Step 4: 로그 줄을 넓히고 argv를 조립한다**

`init/src/main.zig`에서 지울 것:

```zig
    // **줄을 새로 만들지 않고 이 줄을 넓힌다**(HI-M2). 다른 체인들이
    // `tars-init: config shell=`로 grep하고 있어서 앞부분이 안 바뀌어야 한다.
    std.debug.print("tars-init: config shell={s} keyboard={s} hangul={s} latin={s}\n", .{
        @tagName(cfg.shell),
        @tagName(cfg.keyboard),
        @tagName(cfg.hangul_layout),
        @tagName(cfg.latin_layout),
    });
```

넣을 것:

```zig
    // **줄을 새로 만들지 않고 이 줄을 넓힌다**(HI-M2). 다른 체인들이
    // `tars-init: config shell=`로 grep하고 있어서 앞부분이 안 바뀌어야 한다.
    //
    // 이 배열이 argv로도 간다. **`main()`의 스택에 살고 `supervise()`가 영영
    // 반환하지 않으므로** 프로세스 수명 내내 유효하다 — `keyboard_path`와
    // 같은 근거다.
    var toggle_buf: [config.TOGGLE_ARG_MAX]u8 = undefined;
    const toggle_arg = cfg.hangul_toggle.arg(&toggle_buf);
    std.debug.print(
        "tars-init: config shell={s} keyboard={s} hangul={s} latin={s} toggles={s}\n",
        .{
            @tagName(cfg.shell),
            @tagName(cfg.keyboard),
            @tagName(cfg.hangul_layout),
            @tagName(cfg.latin_layout),
            toggle_arg,
        },
    );
```

이어서 지울 것:

```zig
            .argv = .{
                TERMINAL_PATH.ptr,
                shell_path.ptr,
                shell_flag.ptr,
                keyboard_arg.ptr,
                keyboard_path.cstr(),
                hangul_arg.ptr,
                latin_arg.ptr,
            },
```

넣을 것:

```zig
            .argv = .{
                TERMINAL_PATH.ptr,
                shell_path.ptr,
                shell_flag.ptr,
                keyboard_arg.ptr,
                keyboard_path.cstr(),
                hangul_arg.ptr,
                latin_arg.ptr,
                toggle_arg.ptr,
            },
```

이어서 지울 것:

```zig
            .argv = .{ shell_path.ptr, null, null, null, null, null, null },
```

넣을 것:

```zig
            .argv = .{ shell_path.ptr, null, null, null, null, null, null, null },
```

- [ ] **Step 5: `terminal/src/main.zig`가 여덟째 인자를 읽게 한다**

`terminal/src/main.zig`에서 지울 것:

```zig
    const hangul_layout = std.meta.stringToEnum(hangul.Layout, hangul_arg) orelse .shin_pcs;
    const latin_layout = std.meta.stringToEnum(input.LatinLayout, latin_arg) orelse .qwerty;
```

넣을 것:

```zig
    const hangul_layout = std.meta.stringToEnum(hangul.Layout, hangul_arg) orelse .shin_pcs;
    const latin_layout = std.meta.stringToEnum(input.LatinLayout, latin_arg) orelse .qwerty;

    // 여덟째가 한/영 전환 키 목록이다(HI-M3, design 결정 7). **자판 둘과 달리
    // enum 하나가 아니라 집합이라** `stringToEnum` 대신 콤마 파서를 쓴다.
    //
    // **fallback을 문자열로 두는 것에 뜻이 있다.** 집합 리터럴로 쓰면 기본값이
    // 이 파일에도 한 벌 생기는데, 그 값은 `init/src/config.zig`의 `Config`와
    // 같아야 하고 컴파일러가 그것을 못 잡는다. 문자열로 두면 적어도 눈으로
    // 대조할 형태가 설정 파일과 같아진다.
    const toggle_arg: []const u8 = if (args.len > 7)
        std.mem.span(args[7])
    else
        "hangul_key,shift_space,capslock_tap,lctrl_tap";
    const toggles = input.parseToggles(toggle_arg);
```

이어서 지울 것:

```zig
    std.debug.print("terminal: hangul layout={s} latin={s}\n", .{
        @tagName(hangul_layout), @tagName(latin_layout),
    });
```

넣을 것:

```zig
    // **`toggles=`는 파싱한 결과를 다시 문자열로 만든 것이다**(HI-M3).
    // argv로 받은 문자열을 그대로 찍으면 "글자가 도착했다"만 증명되고
    // "우리가 그것을 맞게 읽었다"는 아무것도 증명되지 않는다.
    var toggle_buf: [input.TOGGLE_ARG_MAX]u8 = undefined;
    std.debug.print("terminal: hangul layout={s} latin={s} toggles={s}\n", .{
        @tagName(hangul_layout),
        @tagName(latin_layout),
        input.togglesArg(toggles, &toggle_buf),
    });
```

이어서 지울 것:

```zig
    var key_state: input.State = .{
        .hangul_layout = hangul_layout,
        .latin_layout = latin_layout,
    };
```

넣을 것:

```zig
    var key_state: input.State = .{
        .hangul_layout = hangul_layout,
        .latin_layout = latin_layout,
        .toggles = toggles,
    };
```

- [ ] **Step 6: 다른 체인이 이 두 줄을 어떻게 읽는지 확인한다**

```bash
rg -n "tars-init: config|hangul layout=" --glob 'check.sh' .
```

기대: 전부 **앞부분으로만** grep한다(`shell=fish keyboard=apple` 등). 뒤에
`toggles=`를 붙이는 것이 어느 체인도 안 깨뜨린다. **HI-M2가 같은 확인을 했고
같은 결론이었다** — 그래도 매번 다시 본다.

- [ ] **Step 7: 빌드와 검사를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build && zig build test &&
  cd ../terminal && ./prepare.sh >/dev/null && zig build test'
```

기대: 양쪽 `PASS`. **터미널 검사는 한 줄도 안 바뀌어야 한다** — `toggles`
필드가 늘었지만 기본값이 넷 다 켜진 것이고, 기존 검사의 Ctrl 누름/뗌 쌍은
사이에 반드시 다른 키가 있어서 아직 아무 갈래도 안 켜졌다.

- [ ] **Step 8: diff를 사용자에게 보여 주고 커밋한다**

```bash
git diff --stat
git diff init/src/main.zig terminal/src/main.zig
git add init/src/main.zig terminal/src/input.zig terminal/src/main.zig
git commit -m "Carry the toggle-key list from the config file to the composer"
```

---

## Task 4: 한/영 키와 Shift+Space 게이트

**Files:**
- Modify: `terminal/src/input.zig` — `toggleHangul` 새 함수, `hangulLayer`의
  머리 두 갈래
- Modify: `terminal/src/input_test.zig` — 검사 36·37

- [ ] **Step 1: `toggleHangul`을 만든다**

`terminal/src/input.zig`에서 지울 것:

```zig
    fn commitHangul(self: *State) void {
        if (self.hangul_buf.codepoint()) |cp| self.pushCommit(cp);
        self.hangul_buf = .{};
    }
```

넣을 것:

```zig
    fn commitHangul(self: *State) void {
        if (self.hangul_buf.codepoint()) |cp| self.pushCommit(cp);
        self.hangul_buf = .{};
    }

    /// 한/영을 뒤집는다. **조합 중이던 것을 먼저 확정한다** — 안 하면 꺼진 채로
    /// 조합이 남아 화면에 글자가 붙박인다(`hangul_buf`가 비지 않았으면
    /// `hangul_on`이 참이라는 불변식, HI-M1 검사 31).
    ///
    /// **전환 키 넷이 전부 이 함수를 지난다.** 그중 둘(CapsLock·왼쪽 Ctrl)은
    /// `hangulLayer`가 아니라 `handleKey`의 modifier switch에서 들어오는데,
    /// 확정을 잊으면 그 둘만 불변식을 깬다 — 한 자리로 모아 두면 그럴 수 없다.
    fn toggleHangul(self: *State) Action {
        self.commitHangul();
        self.hangul_on = !self.hangul_on;
        return .hangul;
    }
```

- [ ] **Step 2: `hangulLayer`의 머리를 고친다**

`terminal/src/input.zig`에서 지울 것:

```zig
        if (code == c.KEY_SPACE and self.shifted() and
            !self.ctrled() and !self.alted() and !self.metaed())
        {
            self.commitHangul();
            self.hangul_on = !self.hangul_on;
            return .hangul;
        }
        if (!self.hangul_on) return null;
```

넣을 것:

```zig
        //
        // **HI-M3부터 설정이 이 갈래를 끌 수 있다**(결정 7). 꺼져 있으면
        // Shift+Space는 그냥 공백이고, 그것이 HI-M1이 "대가"로 적어 둔 것
        // (`HELLO WORLD`를 칠 때 손버릇으로 한/영이 바뀐다)을 없애는 길이다.
        if (self.toggles.shift_space and
            code == c.KEY_SPACE and self.shifted() and
            !self.ctrled() and !self.alted() and !self.metaed())
        {
            return self.toggleHangul();
        }
        // 실기의 한/영 키(evdev 122). **게이트가 이 키를 못 보낸다** — QEMU가
        // `sendkey lang1`을 이름만 받고 조용히 버린다(HI-M0 실측 1). 그래서
        // 이 갈래를 덮는 것은 `input_test`의 호스트 검사뿐이고, 그 사실을
        // 여기 적어 둔다(`project_gate_chain_composition`).
        //
        // **`hangul_on`을 안 본다** — Shift+Space와 같은 이유로 꺼져 있을 때도
        // 켤 수 있어야 한다.
        //
        // 이 갈래가 꺼져 있으면 122는 `qwerty_keymap.len`보다 큰 코드라 아래
        // "표 밖의 키" 갈래로 가서 **확정만 하고 흘러간다** — 그것이 맞는
        // 동작이다.
        if (self.toggles.hangul_key and code == c.KEY_HANGEUL) {
            return self.toggleHangul();
        }
        if (!self.hangul_on) return null;
```

- [ ] **Step 3: 검사를 더한다**

`terminal/src/input_test.zig`에서 지울 것:

```zig
    std.debug.print("input_test: dvorak OK\n", .{});

    std.debug.print("PASS\n", .{});
}
```

넣을 것:

```zig
    std.debug.print("input_test: dvorak OK\n", .{});

    // ── HI-M3: 한/영 키와 전환 키 설정 ────────────────────────────────

    // 검사 36. **실기의 한/영 키(122)가 전환한다.** 게이트가 이 키를 못
    // 보내므로(HI-M0 실측 1) 이 검사가 그 갈래를 덮는 **유일한** 자리다.
    var hk: input.State = .{ .hangul_layout = .dubeol };
    try expectHangul(&hk, K.KEY_HANGEUL, "", null);
    if (!hk.hangul_on) {
        std.debug.print("FAIL: KEY_HANGEUL did not turn hangul on\n", .{});
        return error.ToggleFailed;
    }
    try expectHangul(&hk, K.KEY_R, "", 'ㄱ');
    try expectHangul(&hk, K.KEY_K, "", '가');
    // **조합 중이던 글자가 확정되고 나간다.** 전환 키 넷이 전부 지켜야 하는
    // 계약이고, 그것을 `toggleHangul` 한 자리로 모아 둔 이유다.
    try expectHangul(&hk, K.KEY_HANGEUL, "가", null);
    if (hk.hangul_on) {
        std.debug.print("FAIL: KEY_HANGEUL did not turn hangul off\n", .{});
        return error.ToggleFailed;
    }

    // 검사 37. **꺼 두면 그 키는 아무 일도 안 한다.** 설정이 실제로 갈래를
    // 끄는지 보는 자리다 — 안 보면 "목록을 파싱만 하고 안 쓰는" 코드가
    // 통과한다.
    var tg_off: input.State = .{
        .hangul_layout = .dubeol,
        .toggles = .{ .capslock_tap = true },
    };
    try expect(&tg_off, K.KEY_HANGEUL, 1, "");
    if (tg_off.hangul_on) {
        std.debug.print("FAIL: KEY_HANGEUL toggled with hangul_key off\n", .{});
        return error.ToggleFailed;
    }
    // **Shift+Space도 꺼졌으니 공백이 PTY로 나간다.** 음성 검사가 아니라
    // **양성** 검사인 것에 뜻이 있다 — 삼키면 빈 문자열이 온다. 이것이
    // HI-M1이 적어 둔 "대가"를 없애는 길이다.
    try expect(&tg_off, K.KEY_LEFTSHIFT, 1, "");
    try expect(&tg_off, K.KEY_SPACE, 1, " ");
    try expect(&tg_off, K.KEY_LEFTSHIFT, 0, "");

    std.debug.print("input_test: toggle keys OK\n", .{});

    std.debug.print("PASS\n", .{});
}
```

- [ ] **Step 4: 검사를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && ./prepare.sh >/dev/null && zig build test'
```

기대: `input_test: toggle keys OK`와 `PASS`. 기존 검사 서른다섯도 그대로다 —
기본값이 `shift_space = true`이므로 HI-M1·M2의 Shift+Space 검사가 안 흔들린다.

- [ ] **Step 5: diff를 사용자에게 보여 주고 커밋한다**

```bash
git diff --stat
git diff terminal/src/input.zig
git add terminal/src/input.zig terminal/src/input_test.zig
git commit -m "Let the hangul key and a setting decide what switches to hangul"
```

---

## Task 5: tap-vs-hold 뼈대와 짧은 왼쪽 Ctrl

**Files:**
- Modify: `terminal/src/input.zig` — `TAP_MAX_US` · `Tap` · `State`의 필드 둘 ·
  `markTapConsumed` · `handleKey`의 머리와 `KEY_LEFTCTRL` 갈래
- Modify: `terminal/src/input_test.zig` — 검사 38~43

- [ ] **Step 1: `TAP_MAX_US`와 `Tap`을 더한다**

`terminal/src/input.zig`에서 지울 것:

```zig
/// modifier 상태를 들고 있는 작은 상태 머신.
```

넣을 것:

```zig
/// tap-vs-hold의 문턱(HI design 결정 8). 이보다 짧게 눌렀다 떼면 한/영이고,
/// 길면 그 키의 원래 뜻이다.
///
/// **설정으로 안 뺀다.** 결정 7의 설정 항목이 셋이고, 문턱을 넷째로 만들면
/// 게이트가 못 보는 설정이 하나 는다 — `sendkey`의 `hold_ms`는 게이트가 고르는
/// 값이지 게스트가 고르는 값이 아니다. QEMU가 그 값을 오차 4밀리초 안에
/// 지키므로(HI-M0 실측 2) 게이트가 이 문턱의 양쪽을 실제로 밟을 수 있다.
const TAP_MAX_US: u64 = 300_000;

/// tap 후보 하나의 상태(결정 8).
///
/// **셋이 다 필요하다.** `held`가 없으면 terminal이 뜨기 전부터 눌려 있던 키의
/// 뗌을 tap으로 오해하고, `down_us`가 없으면 길이를 못 재고, `consumed`가
/// 없으면 `Ctrl+C`가 한/영을 바꾼다.
const Tap = struct {
    /// 지금 눌려 있는가.
    held: bool = false,
    /// 누른 시각. `held`가 참일 때만 뜻이 있다.
    down_us: u64 = 0,
    /// 누른 동안 다른 키가 왔는가. 왔으면 이 키는 조합 키로 쓰인 것이다.
    consumed: bool = false,

    /// 누름을 기록한다.
    ///
    /// **자동 반복(value=2)은 시각을 안 덮어쓴다.** 덮어쓰면 길게 누르고 있는
    /// 키가 영원히 "방금 눌린" 상태가 되어 뗄 때마다 tap이 된다 — 증상은
    /// "길게 눌러도 한/영이 바뀐다"이고, 결정 9의 대문자 잠금을 통째로 막는다.
    fn down(self: *Tap, time_us: u64) void {
        if (self.held) return;
        self.held = true;
        self.down_us = time_us;
        self.consumed = false;
    }

    /// 뗌을 기록하고 "짧게 눌렀다 뗐는가"를 답한다.
    ///
    /// **호출자는 설정이 꺼져 있어도 이 함수를 부른다.** 상태를 지우는 것이
    /// 여기이므로, 건너뛰면 `held`가 참으로 남아 다음 키가 전부 소비 표시를
    /// 켠다.
    ///
    /// 시각이 거꾸로 가면 tap이 아니다. `ev.time`은 벽시계라 이론상 뒤로 뛸 수
    /// 있는데, 뺄셈이 감싸 돌면 엄청나게 긴 hold가 되므로 결과는 어차피 같다 —
    /// 명시적으로 적는 것은 읽는 사람을 위해서다.
    fn up(self: *Tap, time_us: u64) bool {
        const was_held = self.held;
        const was_consumed = self.consumed;
        const down_us = self.down_us;
        self.held = false;
        self.consumed = false;
        if (!was_held or was_consumed) return false;
        if (time_us < down_us) return false;
        return time_us - down_us < TAP_MAX_US;
    }
};

/// modifier 상태를 들고 있는 작은 상태 머신.
```

- [ ] **Step 2: `State`에 필드 둘과 `markTapConsumed`를 더한다**

`terminal/src/input.zig`에서 지울 것:

```zig
    /// 지금 키를 어떻게 해석하는가. **모드가 `input`에 있는 이유가 design
    /// 결정 1이다** — "이 키를 어떻게 해석하는가"는 번역의 문제이고, 선택
    /// 영역이 `vt`에 있는 것은 그것이 화면 상태이기 때문이다.
    mode: Mode = .normal,
```

넣을 것:

```zig
    /// CapsLock과 왼쪽 Ctrl의 tap 상태(HI-M3, design 결정 8).
    ///
    /// **설정이 꺼져 있어도 기록은 한다.** 갈래를 하나로 두면 "켜져 있을 때만
    /// 기록한다"가 만드는 어긋남이 아예 없다 — 기록을 건너뛰면 `held`가 참으로
    /// 남거나 거짓으로 남는 경계가 생기고, 그 경계는 게이트가 못 본다.
    caps_tap: Tap = .{},
    lctrl_tap: Tap = .{},

    /// 지금 키를 어떻게 해석하는가. **모드가 `input`에 있는 이유가 design
    /// 결정 1이다** — "이 키를 어떻게 해석하는가"는 번역의 문제이고, 선택
    /// 영역이 `vt`에 있는 것은 그것이 화면 상태이기 때문이다.
    mode: Mode = .normal,
```

이어서 `terminal/src/input.zig`의 `fn shifted(self: State) bool {` **앞**에 넣을 것:

```zig
    /// 결정 8의 2번 — 누른 동안 다른 키가 오면 "소비됨"을 켠다. 그 키는 조합
    /// 키로 쓰인 것이므로 뗄 때 아무 일도 일어나면 안 된다.
    ///
    /// **`handleKey`의 modifier switch보다 앞에서 불러야 한다.** Shift·Alt·Meta
    /// 갈래가 switch 안에서 `return`하므로, 뒤에 두면 `Ctrl+Shift+C`의 Shift가
    /// Ctrl을 소비하지 못하고 Ctrl을 뗄 때 한/영이 뒤집힌다. **증상이 "가끔
    /// 한글이 안 쳐진다"라 원인에서 아주 멀다.**
    ///
    /// **자기 자신은 뺀다.** 자동 반복(value=2)이 오면 자기가 자기를 소비한
    /// 것이 된다.
    fn markTapConsumed(self: *State, code: u16) void {
        if (self.caps_tap.held and code != c.KEY_CAPSLOCK)
            self.caps_tap.consumed = true;
        if (self.lctrl_tap.held and code != c.KEY_LEFTCTRL)
            self.lctrl_tap.consumed = true;
    }

```

- [ ] **Step 3: `handleKey`가 소비를 표시하고 Ctrl tap을 판정하게 한다**

`terminal/src/input.zig`에서 지울 것:

```zig
        // **Task 5가 이 두 줄을 지운다.** 지금은 시각을 배선만 하고 아무
        // 판단도 하지 않는다 — 그래야 "기존 검사가 한 글자도 안 바뀐 채
        // 통과했다"가 시그니처 변경이 맞았다는 증거가 된다. Zig는 안 쓰는
        // 인자를 컴파일 에러로 막으므로 자리를 채워 두어야 한다.
        _ = time_us;

        switch (code) {
```

넣을 것:

```zig
        // 0.5번 단계 — tap 소비 표시(결정 8의 2번). **아래 switch보다 앞이어야
        // 하는 이유는 markTapConsumed의 주석에 있다.**
        //
        // 뗌(0)은 소비가 아니다. Ctrl을 누르기 전부터 눌려 있던 키를 떼는 것일
        // 수 있고, 그것은 이 Ctrl을 조합 키로 쓴 것이 아니다.
        if (value != 0) self.markTapConsumed(code);

        switch (code) {
```

이어서 지울 것:

```zig
            c.KEY_LEFTCTRL => {
                self.ctrl_left = value != 0;
                return nothing;
            },
```

넣을 것:

```zig
            c.KEY_LEFTCTRL => {
                self.ctrl_left = value != 0;
                // 짧게 눌렀다 떼면 한/영이다(결정 8). **modifier 상태를 갱신한
                // 뒤에 판단한다** — 순서가 뒤집히면 `ctrl_left`가 참인 채로
                // `toggleHangul`이 불려서 `hangulLayer`의 Ctrl 갈래와 뜻이
                // 어긋난다.
                //
                // **뗄 때 판단하므로 지연이 어디에도 없다.** Ctrl을 modifier로
                // 쓸 때는 다음 키가 이미 `consumed`를 켰다.
                //
                // `up()`을 설정과 무관하게 먼저 부르는 것이 계약이다 — 그
                // 함수가 상태를 지운다.
                if (value == 0) {
                    const tapped = self.lctrl_tap.up(time_us);
                    if (tapped and self.toggles.lctrl_tap) return self.toggleHangul();
                } else {
                    self.lctrl_tap.down(time_us);
                }
                return nothing;
            },
```

- [ ] **Step 4: 검사를 더한다**

`terminal/src/input_test.zig`에서 지울 것:

```zig
    std.debug.print("input_test: toggle keys OK\n", .{});

    std.debug.print("PASS\n", .{});
}
```

넣을 것:

```zig
    std.debug.print("input_test: toggle keys OK\n", .{});

    // ── HI-M3: tap-vs-hold (왼쪽 Ctrl) ────────────────────────────────
    //
    // **시각을 직접 준다.** 게이트는 `sendkey <key> <hold_ms>`로 같은 것을
    // 보지만(HI-M0 실측 2) 여기서는 부팅 없이 문턱(0.3초)의 양쪽을 밟는다.

    // 검사 38. **짧은 왼쪽 Ctrl이 한/영을 켠다.** 0.1초다.
    var tp: input.State = .{ .hangul_layout = .dubeol };
    try expectAt(&tp, K.KEY_LEFTCTRL, 1, 0, "");
    try expectHangulAt(&tp, K.KEY_LEFTCTRL, 0, 100_000, "", null);
    if (!tp.hangul_on) {
        std.debug.print("FAIL: a short left Ctrl did not turn hangul on\n", .{});
        return error.ToggleFailed;
    }

    // 검사 39. **긴 왼쪽 Ctrl은 아무 일도 안 한다.** 0.4초다. 검사 38과 이
    // 검사가 문턱의 양쪽이고, **둘이 짝이어야 뜻이 선다** — 짧은 것만 보면
    // "언제나 전환한다"가 통과한다.
    try expectAt(&tp, K.KEY_LEFTCTRL, 1, 1_000_000, "");
    try expectAt(&tp, K.KEY_LEFTCTRL, 0, 1_400_000, "");
    if (!tp.hangul_on) {
        std.debug.print("FAIL: a long left Ctrl flipped hangul\n", .{});
        return error.ToggleFailed;
    }

    // 검사 40. **`Ctrl+C`가 한/영을 안 바꾼다 — 이것이 결정 8의 심장이다.**
    // 누른 시간이 0.05초라 문턱보다 훨씬 짧은데도 tap이 아니어야 한다. 이
    // 검사가 없으면 터미널에서 가장 흔한 조합이 누를 때마다 한/영을 뒤집고,
    // **증상이 "가끔 한글이 안 쳐진다"라 원인에서 아주 멀다.**
    try expectAt(&tp, K.KEY_LEFTCTRL, 1, 2_000_000, "");
    try expectAt(&tp, K.KEY_C, 1, 2_010_000, "\x03");
    try expectAt(&tp, K.KEY_LEFTCTRL, 0, 2_050_000, "");
    if (!tp.hangul_on) {
        std.debug.print("FAIL: Ctrl+C flipped hangul — the tap was not consumed\n", .{});
        return error.ToggleFailed;
    }

    // 검사 41. **Shift가 눌린 것도 소비다.** 소비 표시가 modifier switch
    // **앞**에 있어야 하는 이유를 보는 유일한 자리다 — 뒤에 있으면 Shift
    // 갈래가 먼저 `return`해서 그 줄이 실행되지 않는다.
    try expectAt(&tp, K.KEY_LEFTCTRL, 1, 3_000_000, "");
    try expectAt(&tp, K.KEY_LEFTSHIFT, 1, 3_010_000, "");
    try expectAt(&tp, K.KEY_LEFTSHIFT, 0, 3_020_000, "");
    try expectAt(&tp, K.KEY_LEFTCTRL, 0, 3_050_000, "");
    if (!tp.hangul_on) {
        std.debug.print("FAIL: Ctrl+Shift flipped hangul — Shift did not consume\n", .{});
        return error.ToggleFailed;
    }

    // 검사 42. **오른쪽 Ctrl은 tap이 아니다.** 결정 8이 왼쪽만 적었다 —
    // 오른쪽까지 넣으면 오탐이 두 배가 되고, 얻는 것은 없다.
    try expectAt(&tp, K.KEY_RIGHTCTRL, 1, 4_000_000, "");
    try expectAt(&tp, K.KEY_RIGHTCTRL, 0, 4_100_000, "");
    if (!tp.hangul_on) {
        std.debug.print("FAIL: a short right Ctrl flipped hangul\n", .{});
        return error.ToggleFailed;
    }

    // 검사 43. **조합 중이면 tap이 그것을 확정시킨다.** 전환 키 넷이 전부
    // `toggleHangul`을 지나므로 계약이 하나다 — 이 검사가 그것을 modifier
    // switch 쪽에서 확인한다(검사 36은 `hangulLayer` 쪽에서 봤다).
    try expectHangulAt(&tp, K.KEY_R, 1, 5_000_000, "", 'ㄱ');
    try expectHangulAt(&tp, K.KEY_K, 1, 5_010_000, "", '가');
    try expectAt(&tp, K.KEY_LEFTCTRL, 1, 5_020_000, "");
    try expectHangulAt(&tp, K.KEY_LEFTCTRL, 0, 5_100_000, "가", null);
    if (tp.hangul_on) {
        std.debug.print("FAIL: a short left Ctrl did not turn hangul off\n", .{});
        return error.ToggleFailed;
    }

    // 검사 44. **설정이 꺼져 있으면 짧아도 아무 일도 안 한다.**
    var lc_off: input.State = .{
        .hangul_layout = .dubeol,
        .toggles = .{ .hangul_key = true },
    };
    try expectAt(&lc_off, K.KEY_LEFTCTRL, 1, 0, "");
    try expectAt(&lc_off, K.KEY_LEFTCTRL, 0, 100_000, "");
    if (lc_off.hangul_on) {
        std.debug.print("FAIL: left Ctrl toggled with lctrl_tap off\n", .{});
        return error.ToggleFailed;
    }
    // 그래도 Ctrl은 Ctrl이다 — 설정이 끄는 것은 tap이지 modifier가 아니다.
    try expectAt(&lc_off, K.KEY_LEFTCTRL, 1, 200_000, "");
    try expectAt(&lc_off, K.KEY_C, 1, 210_000, "\x03");
    try expectAt(&lc_off, K.KEY_LEFTCTRL, 0, 220_000, "");

    std.debug.print("input_test: tap-vs-hold OK\n", .{});

    std.debug.print("PASS\n", .{});
}
```

- [ ] **Step 5: 검사를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && ./prepare.sh >/dev/null && zig build test'
```

기대: `input_test: tap-vs-hold OK`와 `PASS`.

**기존 검사가 안 깨지는 근거를 미리 적어 둔다.** 이 파일의 왼쪽 Ctrl 누름/뗌
쌍은 여섯인데(263·283 / 292·296 / 543·545 / 894·897 …) **전부 사이에 다른
키가 있어서 소비된다.** 하나라도 소비 안 된 쌍이 있으면 시각이 0-0이라 tap으로
판정되어 `got hangul, want bytes`로 시끄럽게 실패한다 — 조용히 통과하는 길이
없다는 것이 요점이다.

- [ ] **Step 6: diff를 사용자에게 보여 주고 커밋한다**

```bash
git diff --stat
git diff terminal/src/input.zig
git add terminal/src/input.zig terminal/src/input_test.zig
git commit -m "Turn a short left Ctrl into a hangul switch and leave Ctrl+C alone"
```

---

## Task 6: CapsLock — 짧으면 한/영, 길면 대문자 잠금

**Files:**
- Modify: `terminal/src/input.zig` — `State.caps_lock` · `latinChar` ·
  `handleKey`의 `KEY_CAPSLOCK` 갈래
- Modify: `terminal/src/input_test.zig` — 검사 45~48

- [ ] **Step 1: `caps_lock` 필드를 더한다**

`terminal/src/input.zig`에서 지울 것:

```zig
    caps_tap: Tap = .{},
    lctrl_tap: Tap = .{},
```

넣을 것:

```zig
    caps_tap: Tap = .{},
    lctrl_tap: Tap = .{},

    /// 대문자 잠금(HI design 결정 9). CapsLock을 **길게** 누르면 뒤집힌다.
    ///
    /// **지금 상태를 보여 주는 자리가 없다는 것을 알고 넘어간다** — LED도 화면
    /// 표시도 없으므로 켜 놓은 것을 잊으면 대문자가 나오는 것으로만 안다.
    /// 비목표의 "입력기 상태를 화면에 보여 주기"와 같은 숙제다.
    ///
    /// **한글 조합은 이 값에 안 흔들린다.** `hangulLayer`가 `latinChar`를 안
    /// 쓰고 `qwerty_keymap`을 직접 보기 때문이고(결정 13), 그것을 못 박는
    /// 것이 `input_test`의 검사 48이다.
    caps_lock: bool = false,
```

- [ ] **Step 2: `latinChar`가 대문자 잠금을 보게 한다**

`terminal/src/input.zig`에서 지울 것:

```zig
    fn latinChar(self: State, code: u16) u8 {
        const shift: usize = if (self.shifted()) 1 else 0;
        return switch (self.latin_layout) {
            .qwerty => qwerty_keymap[code][shift],
            .dvorak => dvorak_keymap[code][shift],
        };
    }
```

넣을 것:

```zig
    fn latinChar(self: State, code: u16) u8 {
        const pair = switch (self.latin_layout) {
            .qwerty => qwerty_keymap[code],
            .dvorak => dvorak_keymap[code],
        };
        // CapsLock은 **알파벳에만** 적용된다(HI design 결정 9). 숫자와 기호는
        // 안 바뀌고, 그것이 Shift와 CapsLock이 갈리는 자리이자 진짜 CapsLock의
        // 성질이다.
        //
        // 판단의 근거를 **Shift 안 누른 칸의 값**으로 삼는 이유는 그것이
        // 드보락에서도 그대로 서기 때문이다 — 쿼티의 `q` 자리는 드보락에서
        // `'`이고 알파벳이 아니므로 CapsLock이 안 닿는다. 코드가 아니라 값을
        // 보므로 표를 하나 더 유지할 필요도 없다.
        const caps = self.caps_lock and pair[0] >= 'a' and pair[0] <= 'z';
        // bool에서 `!=`가 XOR이다. **둘 다면 소문자**이고, 그것이 진짜 키보드의
        // 동작이다 — CapsLock을 켜 두고 Shift+A를 누르면 `a`가 나온다.
        const shift = self.shifted() != caps;
        return pair[if (shift) 1 else 0];
    }
```

- [ ] **Step 3: `handleKey`에 `KEY_CAPSLOCK` 갈래를 더한다**

`terminal/src/input.zig`에서 지울 것:

```zig
            c.KEY_RIGHTMETA => {
                self.meta_right = value != 0;
                return nothing;
            },
            else => {},
        }
```

넣을 것:

```zig
            c.KEY_RIGHTMETA => {
                self.meta_right = value != 0;
                return nothing;
            },
            // CapsLock(58)은 `keymap` 표 밖이다 — 표가 `KEY_SPACE`(57)에서
            // 끝난다. 그래서 HI-M3 전에는 `handleKey` 맨 끝에서 조용히
            // `nothing`이 됐고, TARS에 대문자 잠금이 아예 없었다(design 조사 7).
            c.KEY_CAPSLOCK => {
                if (value == 0) {
                    // `up()`을 설정과 무관하게 먼저 부르는 것이 계약이다 —
                    // 그 함수가 상태를 지운다.
                    const tapped = self.caps_tap.up(time_us);
                    if (tapped and self.toggles.capslock_tap)
                        return self.toggleHangul();
                    // 짧은 tap이 아니면 원래 뜻이다(결정 9).
                    //
                    // **누를 때가 아니라 뗄 때 뒤집는 것이 진짜 CapsLock과
                    // 다른 유일한 자리다.** 누를 때 뒤집으면 짧게 눌렀다 뗐을
                    // 때 대문자 잠금이 한 번 켜졌다 꺼지므로 tap을 만들 수가
                    // 없다.
                    //
                    // **`capslock_tap`이 꺼져 있으면 `tapped`가 무엇이든 여기
                    // 온다.** 그때 CapsLock은 그냥 CapsLock이고, 갈래를 나누지
                    // 않으므로 "언제나 뗄 때"라는 규칙이 하나로 선다.
                    self.caps_lock = !self.caps_lock;
                } else {
                    self.caps_tap.down(time_us);
                }
                return nothing;
            },
            else => {},
        }
```

- [ ] **Step 4: 검사를 더한다**

`terminal/src/input_test.zig`에서 지울 것:

```zig
    std.debug.print("input_test: tap-vs-hold OK\n", .{});

    std.debug.print("PASS\n", .{});
}
```

넣을 것:

```zig
    std.debug.print("input_test: tap-vs-hold OK\n", .{});

    // ── HI-M3: CapsLock ───────────────────────────────────────────────

    // 검사 45. **짧은 CapsLock이 한/영을 켜고 끈다.** 0.2초다.
    var cl: input.State = .{ .hangul_layout = .dubeol };
    try expectAt(&cl, K.KEY_CAPSLOCK, 1, 0, "");
    try expectHangulAt(&cl, K.KEY_CAPSLOCK, 0, 200_000, "", null);
    if (!cl.hangul_on) {
        std.debug.print("FAIL: a short CapsLock did not turn hangul on\n", .{});
        return error.ToggleFailed;
    }
    try expectAt(&cl, K.KEY_CAPSLOCK, 1, 1_000_000, "");
    try expectHangulAt(&cl, K.KEY_CAPSLOCK, 0, 1_200_000, "", null);
    if (cl.hangul_on) {
        std.debug.print("FAIL: a second short CapsLock did not turn hangul off\n", .{});
        return error.ToggleFailed;
    }
    // **대문자 잠금은 안 켜졌다.** 짧은 tap이 그것까지 건드렸으면 여기서
    // `A`가 나온다 — 이 한 줄이 두 축이 안 섞였다는 증거다.
    try expectAt(&cl, K.KEY_A, 1, 2_000_000, "a");

    // 검사 46. **긴 CapsLock은 한/영을 안 바꾸고 대문자 잠금을 켠다.** 0.4초다.
    try expectAt(&cl, K.KEY_CAPSLOCK, 1, 3_000_000, "");
    try expectAt(&cl, K.KEY_CAPSLOCK, 0, 3_400_000, "");
    if (cl.hangul_on) {
        std.debug.print("FAIL: a long CapsLock flipped hangul\n", .{});
        return error.ToggleFailed;
    }
    try expectAt(&cl, K.KEY_A, 1, 4_000_000, "A");
    // **숫자와 기호는 안 바뀐다 — 결정 9의 전부가 이 두 줄이다.** Shift를
    // 통째로 걸어 버리는 구현은 여기서 `!`와 `_`를 낸다.
    try expectAt(&cl, K.KEY_1, 1, 4_010_000, "1");
    try expectAt(&cl, K.KEY_MINUS, 1, 4_020_000, "-");
    // **Shift와 겹치면 소문자다.** 진짜 키보드의 동작이고, XOR로 쓴 이유다.
    try expectAt(&cl, K.KEY_LEFTSHIFT, 1, 4_030_000, "");
    try expectAt(&cl, K.KEY_A, 1, 4_040_000, "a");
    // 숫자는 Shift 그대로다 — CapsLock이 안 닿았으므로 XOR도 안 일어난다.
    try expectAt(&cl, K.KEY_1, 1, 4_050_000, "!");
    try expectAt(&cl, K.KEY_LEFTSHIFT, 0, 4_060_000, "");
    // 한 번 더 길게 누르면 꺼진다. **켜지는 것만 보면 토글이 한 방향으로만
    // 동작해도 통과한다** — 게이트의 검사 1과 9가 같은 짝이다.
    try expectAt(&cl, K.KEY_CAPSLOCK, 1, 5_000_000, "");
    try expectAt(&cl, K.KEY_CAPSLOCK, 0, 5_400_000, "");
    try expectAt(&cl, K.KEY_A, 1, 6_000_000, "a");

    // 검사 47. **`capslock_tap`이 꺼져 있으면 짧아도 대문자 잠금이다.**
    // 그때 CapsLock은 그냥 CapsLock이고, 그것이 이 설정의 뜻이다.
    var cl_off: input.State = .{
        .hangul_layout = .dubeol,
        .toggles = .{ .hangul_key = true },
    };
    try expectAt(&cl_off, K.KEY_CAPSLOCK, 1, 0, "");
    try expectAt(&cl_off, K.KEY_CAPSLOCK, 0, 100_000, "");
    if (cl_off.hangul_on) {
        std.debug.print("FAIL: CapsLock toggled hangul with capslock_tap off\n", .{});
        return error.ToggleFailed;
    }
    try expectAt(&cl_off, K.KEY_A, 1, 200_000, "A");

    // 검사 48. **대문자 잠금이 한글 조합에 안 닿는다.** 한글 조회는 언제나
    // 쿼티 표의 **Shift 안 누른** 칸에서 오므로(결정 13) 자동으로 그렇지만,
    // 못 박아 두지 않으면 나중에 누가 `hangulLayer`를 `latinChar`로 바꿔 쓰면서
    // 조용히 깨뜨린다.
    var cl_hg: input.State = .{ .hangul_layout = .dubeol };
    // 길게 눌러 대문자 잠금을 켠다.
    try expectAt(&cl_hg, K.KEY_CAPSLOCK, 1, 0, "");
    try expectAt(&cl_hg, K.KEY_CAPSLOCK, 0, 400_000, "");
    // 짧게 눌러 한글을 켠다.
    try expectAt(&cl_hg, K.KEY_CAPSLOCK, 1, 1_000_000, "");
    try expectHangulAt(&cl_hg, K.KEY_CAPSLOCK, 0, 1_100_000, "", null);
    // **`o`를 고른 것에 뜻이 있다.** 두벌식에서 소문자 `o`는 ㅐ이고 대문자
    // `O`는 ㅒ라, 대문자 잠금이 한글 층에 새면 `개`가 아니라 `걔`가 나온다.
    // `k`(ㅏ)로는 대문자 칸이 따로 없어서 아무것도 안 보인다 —
    // **증상이 "안 된다"가 아니라 "다른 글자가 나온다"인 종류다.**
    try expectHangulAt(&cl_hg, K.KEY_R, 1, 2_000_000, "", 'ㄱ');
    try expectHangulAt(&cl_hg, K.KEY_O, 1, 2_010_000, "", '개');

    std.debug.print("input_test: capslock OK\n", .{});

    std.debug.print("PASS\n", .{});
}
```

- [ ] **Step 5: 검사를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && ./prepare.sh >/dev/null && zig build test'
```

기대: `input_test: capslock OK`와 `PASS`. `vt_test`·`hangul_test`·`font_test`도
그대로다 — 이 Task는 `input.zig` 밖을 안 건드린다.

- [ ] **Step 6: diff를 사용자에게 보여 주고 커밋한다**

```bash
git diff --stat
git diff terminal/src/input.zig
git add terminal/src/input.zig terminal/src/input_test.zig
git commit -m "Make a long CapsLock lock capitals and a short one switch to hangul"
```

---

## Task 7: 게이트가 tap 둘을 본다

**Files:**
- Modify: `hangul/make_disk.sh` — `hangul_toggle` 한 줄
- Modify: `hangul/check.sh` — `hold_key` 헬퍼, 검사 0의 판정 둘, 검사 12~15

- [ ] **Step 1: 설정 디스크에 `hangul_toggle`을 심는다**

`hangul/make_disk.sh`에서 지울 것:

```bash
# **심는 값이 기본값과 달라야 한다.** 기본값은 shin_pcs이고 여기 심는 것은
# sebeol_3p3다 — 같은 값을 심으면 설정을 통째로 무시하는 코드도 초록이 뜬다.
```

넣을 것:

```bash
# **심는 값이 기본값과 달라야 한다.** 기본값은 shin_pcs이고 여기 심는 것은
# sebeol_3p3다 — 같은 값을 심으면 설정을 통째로 무시하는 코드도 초록이 뜬다.
#
# `hangul_toggle`도 같은 규칙을 따른다(HI-M3). 기본값은 넷 다 켜진 것이고
# 여기 심는 것은 **`hangul_key`를 뺀 셋**이다.
#
# **뺄 것으로 `hangul_key`를 고른 이유가 있다.** 그것이 게이트가 어차피 못
# 보내는 유일한 키다 — QEMU가 `sendkey lang1`을 이름만 받고 조용히 버린다
# (HI-M0 실측 1). `shift_space`를 뺐다면 기존 검사 2·9·11을 전부 다시 써야
# 하고, tap 둘 중 하나를 뺐다면 HI-M3이 새로 만든 갈래를 게이트가 못 본다.
#
# **꺼짐의 판정은 로그 줄 하나로 끝난다.** `arg()`가 정규형을 만들므로 찍히는
# 문자열에 `hangul_key`가 **없다는 것 자체가** "설정이 그것을 껐다"의 증거다.
```

이어서 지울 것:

```bash
hangul_layout=sebeol_3p3
EOF
```

넣을 것:

```bash
hangul_layout=sebeol_3p3
# hangul_toggle — **`hangul_key`가 빠진 것이 요점이다.** 기본값은 넷이고,
#                 설정을 통째로 무시하는 코드는 그 넷을 로그에 찍는다.
hangul_toggle=shift_space,capslock_tap,lctrl_tap
EOF
```

이어서 지울 것:

```bash
echo "make_disk: created ${IMG} (${SIZE}, ext2, hangul_layout=sebeol_3p3)"
```

넣을 것:

```bash
echo "make_disk: created ${IMG} (${SIZE}, ext2, hangul_layout=sebeol_3p3," \
     "hangul_toggle without hangul_key)"
```

- [ ] **Step 2: `hold_key` 헬퍼를 더한다**

`hangul/check.sh`에서 지울 것:

```bash
# 마지막 프레임의 화면 줄에서 그 문자열이 몇 번 나오는가.
screen_count() {
```

넣을 것:

```bash
# 키 하나를 `ms` 밀리초 동안 누르고 있다가 뗀다(HI-M3).
#
# **`type_keys`를 못 쓴다.** 이유가 둘이다.
#   1. 그쪽은 `sendkey $k` 하나만 보내므로 hold 시간을 못 준다.
#   2. 그쪽은 로그가 자라기를 기다리는데, **긴 CapsLock은 로그를 한 줄도 안
#      만들 수 있다** — 대문자 잠금만 켜지고 화면은 그대로다. 그러면 0.3초를
#      꽉 채우고 다음 줄로 간다(그 자체는 안전하지만 판정이 흐려진다).
#
# **hold가 끝나기를 여기서 기다려야 한다.** `sendkey`의 hold는 QEMU가 타이머로
# 처리하므로 monitor는 즉시 돌아온다 — 안 기다리면 다음 키가 이 키를 **누른
# 채로** 도착해서 "소비됨"이 켜지고 tap이 사라진다. 1.5초는 이 체인이 쓰는
# 최대 hold(0.5초)에 게스트 반응 시간을 얹은 값이다.
#
# QEMU가 이 값을 오차 4밀리초 안에 지킨다는 것은 HI-M0이 evdev 타임스탬프로
# 쟀다(실측 2). 그래서 문턱 0.3초의 양쪽을 게이트가 실제로 밟을 수 있다.
hold_key() {
  local key="$1" ms="$2"
  echo "sendkey $key $ms" >&3
  sleep 1.5
}

# 마지막 프레임의 화면 줄에서 그 문자열이 몇 번 나오는가.
screen_count() {
```

- [ ] **Step 3: `report_failure`의 마커 목록을 넓힌다**

`hangul/check.sh`에서 지울 것:

```bash
    "tars-init: config " \
    "terminal: hangul layout=" \
```

넣을 것:

```bash
    "tars-init: config " \
    "tars-init: config .*toggles=" \
    "terminal: hangul layout=" \
    "terminal: hangul layout=.*toggles=" \
```

- [ ] **Step 4: 검사 0에 전환 키 목록 판정을 더한다**

`hangul/check.sh`에서 지울 것:

```bash
if ! grep -aq 'terminal: hangul layout=sebeol_3p3' "$LOG"; then
  report_failure "the layout did not reach terminal through argv"
fi
echo "sebeol_3p3 came from the config file and reached the composer"
```

넣을 것:

```bash
if ! grep -aq 'terminal: hangul layout=sebeol_3p3' "$LOG"; then
  report_failure "the layout did not reach terminal through argv"
fi
echo "sebeol_3p3 came from the config file and reached the composer"

# 전환 키 목록도 같은 짝을 이룬다(HI-M3). **판정이 둘이 아니라 셋이다.**
#
#   1. init이 파일에서 읽었다
#   2. 그 값이 argv를 건너 terminal에 닿았다
#   3. **`hangul_key`가 목록에 없다** — 기본값은 넷이므로, 설정을 통째로
#      무시하는 코드는 `hangul_key,`로 시작하는 목록을 찍는다.
#
# 셋째가 이 체인이 "꺼짐"을 보는 유일한 자리다. 나머지 꺼짐 갈래 넷은
# `input_test`가 호스트에서 본다.
echo "=== the config disk should have selected three toggle keys ==="
EXPECT_TOGGLES='shift_space,capslock_tap,lctrl_tap'
if ! grep -aq "tars-init: config .*toggles=${EXPECT_TOGGLES}\$" "$LOG"; then
  report_failure "init did not read hangul_toggle=${EXPECT_TOGGLES} from the config disk"
fi
if ! grep -aq "terminal: hangul layout=sebeol_3p3 latin=qwerty toggles=${EXPECT_TOGGLES}\$" "$LOG"; then
  report_failure "the toggle list did not reach terminal through argv"
fi
echo "three toggle keys came from the config file; hangul_key is off"
```

**`\$`(줄 끝)를 붙이는 것이 셋째 판정의 전부다.** 안 붙이면
`hangul_key,shift_space,capslock_tap,lctrl_tap`도 부분 일치로 통과한다.
시리얼 로그가 CRLF라 `$`가 CR에 걸릴 것 같지만, `grep -a`가 보는 것은 줄 끝의
`\n` 앞까지이고 CR이 그 자리에 있다 — **그래서 `$`가 아니라 `\r\?$`가 필요할
수 있다.** 아래 Step 5에서 실제로 확인한다(HI-M1 실측 4가 정확히 이 함정이다).

- [ ] **Step 5: 줄 끝 앵커가 CR 때문에 안 깨지는지 먼저 확인한다**

**이 Step을 건너뛰면 안 된다.** HI-M1 실측 4가 같은 함정을 밟았고, 증상이
"똑같아 보이는 값으로 실패한다"였다.

먼저 체인을 한 번 돌려 로그를 남긴다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash hangul/check.sh > /tmp/gate.out 2>&1; rc=$?
  mkdir -p /workspace/out/probe
  cp /tmp/gate.out /workspace/out/probe/gate.out
  echo "rc=$rc"
'
```

`rc=0`이면 앵커가 CR에 안 걸린 것이다. 실패하면 `out/probe/gate.out`의
`--- markers ---`를 읽고 두 판정의 정규식을 `toggles=${EXPECT_TOGGLES}\r\?$`로
바꾼다.

**주의: 루트 게이트를 돌리면 `out/`이 통째로 사라진다**(`check.sh:15`의
`clean()`). 조사를 다 끝내고 Task 8로 간다.

- [ ] **Step 6: 검사 12~15를 더한다**

`hangul/check.sh`에서 지울 것:

```bash
echo "three syllables in a row survive on the command line"

echo "HI check PASS"
```

넣을 것:

```bash
echo "three syllables in a row survive on the command line"

# ── 검사 12: 짧은 CapsLock이 한/영을 끈다 ──────────────────────────────
#
# **`sendkey caps_lock 100`의 100은 밀리초다.** 문턱이 0.3초이므로 이것은
# tap이고, 검사 13의 500은 hold다. **둘이 짝이어야 뜻이 선다** — 짧은 것만
# 보면 "언제나 전환한다"가 통과한다.
#
# 여기 오기 전에 검사 11이 한/영을 켜 두었다.
#
# **음성 검사가 함께 있어야 한다** — CapsLock이 글자를 만들면 명령줄이
# 더러워지고, 그것이 표 밖의 키를 다루는 가장 흔한 실패 방식이다.
echo "=== sendkey caps_lock 100 (tap) ==="
BEFORE_CAPS="$(key_lines)"
hold_key caps_lock 100
ON="$(hangul_field on)"
if [ "$ON" != "false" ]; then
  report_failure "a short CapsLock left hangul on=${ON}, expected false"
fi
AFTER_CAPS="$(key_lines)"
if [ "$AFTER_CAPS" != "$BEFORE_CAPS" ]; then
  report_failure "CapsLock leaked to the PTY (key> lines ${BEFORE_CAPS} -> ${AFTER_CAPS})"
fi
echo "a short CapsLock turned hangul off and sent nothing to the shell"

# ── 검사 13: 긴 CapsLock은 한/영을 안 바꾸고 대문자 잠금을 켠다 ─────────
#
# **판정이 화면이다.** 대문자 잠금에는 LED도 표시도 없으므로(결정 9), 켜졌는지
# 아는 유일한 길은 다음 글자가 대문자로 나오는 것이다.
#
# **숫자를 함께 치는 것이 결정 9의 전부다** — CapsLock은 알파벳에만 적용되고
# 숫자와 기호는 안 바뀐다. `abc1`을 쳐서 `ABC1`이 나와야 하고, Shift를 통째로
# 걸어 버리는 구현은 `ABC!`를 낸다.
#
# **한/영이 안 바뀐 것도 함께 본다.** `hangul_field`는 마지막 `hangul>` 줄을
# 읽는데, 그 줄은 `Action.hangul`이 나올 때만 찍힌다 — 긴 CapsLock이 잘못
# 전환하면 새 줄이 `on=true`로 찍혀서 여기가 갈린다.
echo "=== sendkey caps_lock 500 (hold) ==="
hold_key caps_lock 500
ON="$(hangul_field on)"
if [ "$ON" != "false" ]; then
  report_failure "a long CapsLock changed hangul to on=${ON}, expected false"
fi
type_keys a b c 1
sleep 1
if [ "$(screen_count 'ABC1')" -lt 1 ]; then
  report_failure "a long CapsLock did not lock capitals (expected ABC1 on screen)"
fi
echo "a long CapsLock locked capitals and left the digit alone"

# ── 검사 14: 한 번 더 길게 누르면 잠금이 풀린다 ─────────────────────────
#
# **켜지는 것만 보면 토글이 한 방향으로만 동작해도 통과한다** — 검사 1과 9가
# Shift+Space에 대해 이루는 짝과 같은 이유다.
echo "=== sendkey caps_lock 500 again ==="
hold_key caps_lock 500
type_keys a
sleep 1
if [ "$(screen_count 'ABC1a')" -lt 1 ]; then
  report_failure "a second long CapsLock did not release the capital lock"
fi
echo "a second long CapsLock released the lock"

# ── 검사 15: 짧은 왼쪽 Ctrl이 한/영을 켠다 ─────────────────────────────
echo "=== ctrl-c to clear the line, then sendkey ctrl 100 ==="
type_keys ctrl-c
sleep 1
hold_key ctrl 100
ON="$(hangul_field on)"
if [ "$ON" != "true" ]; then
  report_failure "a short left Ctrl left hangul on=${ON}, expected true"
fi
echo "a short left Ctrl turned hangul on"

# ── 검사 16: Ctrl+C는 한/영을 안 바꾼다 ────────────────────────────────
#
# **이것이 결정 8의 심장이고 이 체인에서 가장 값진 한 줄이다.** 누른 동안 다른
# 키가 오면 "소비됨"이 켜져서 tap이 아니어야 하는데, 그것이 없으면 터미널에서
# 가장 흔한 조합인 Ctrl+C가 누를 때마다 한/영을 뒤집는다. 증상은 "가끔 한글이
# 안 쳐진다"라 원인에서 아주 멀다.
#
# **판정이 서는 이유를 적어 둔다.** Ctrl+C는 그 자체로 `hangul>` 줄을 안 만든다
# (조합 중이 아니면 `hangulLayer`가 확정할 것이 없어 null을 돌려준다). 그래서
# 여기서 읽는 값은 검사 15가 남긴 `on=true`이고, **만약 Ctrl+C가 잘못
# 전환했다면 `on=false`인 새 줄이 그 뒤에 찍혀서 갈린다.**
echo "=== ctrl-c while hangul is on ==="
type_keys ctrl-c
sleep 1
ON="$(hangul_field on)"
if [ "$ON" != "true" ]; then
  report_failure "Ctrl+C flipped hangul to on=${ON} — the left Ctrl tap was not consumed"
fi
echo "Ctrl+C did not flip hangul: the tap was consumed"

echo "HI check PASS"
```

- [ ] **Step 7: 체인 하나만 돌린다**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'bash hangul/check.sh'
```

기대: 검사 0~16이 전부 통과하고 마지막 줄이 `HI check PASS`. **약 3~4분**이
걸린다(커널 빌드가 캐시돼 있으면 그보다 짧다).

실패하면 `report_failure`가 찍는 `--- markers ---` · `--- hangul lines ---` ·
`--- key lines ---` 셋을 먼저 읽는다.

- [ ] **Step 8: 커밋**

```bash
git diff --stat
git add hangul/check.sh hangul/make_disk.sh
git commit -m "Let the hangul gate press CapsLock and Ctrl short and long"
```

---

## Task 8: 루트 게이트 3회전과 서브프로젝트 닫기

**Files:**
- Modify: `check.sh` — `CHAINS`의 라벨
- Modify: `docs/superpowers/specs/2026-08-31-tars-hangul-input-design.md` —
  `Status:` · HI-M3 절 · "HI-M3이 실측한 것" 절
- Modify: `HANDOFF.md` · `MEMORY.md` · `docs/decisions/project_hangul_input.md`
- Modify: `CLAUDE.md` — "진행 중인 서브프로젝트" 줄

- [ ] **Step 1: `CHAINS`의 라벨을 고친다**

`check.sh`에서 지울 것:

```bash
  "HI-M2:./hangul/check.sh"
```

넣을 것:

```bash
  "HI-M3:./hangul/check.sh"
```

- [ ] **Step 2: 루트 게이트를 3회전 돌린다 (회차당 약 18분, 3회전이면 약 55분)**

```bash
for i in 1 2 3; do
  echo "=== round $i ==="
  docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
    bash -c 'time bash check.sh' 2>&1 | tail -30
done
```

기대: 아홉 체인이 3/3으로 통과. **시간은 안 갈릴 것이다** — 체인이 안 늘고
부팅도 안 늘었으며, 는 것은 키 몇 개와 `hold_key`의 sleep 여섯 번(9초)뿐이다.
HI-M2의 기준선이 18분 06~08초이므로 **18분 10~20초 근처**를 예상한다.

**같은 세션 안에서 재는 것이 요점이다**(HI-M2 실측 11). 게이트 잡음 ±3분은
서로 다른 날의 측정에 대한 것이다.

- [ ] **Step 3: 시간을 적고 design doc을 닫는다**

`docs/superpowers/specs/2026-08-31-tars-hangul-input-design.md`에서:

1. 맨 위 `Status:` 줄을 **완료**로 고친다.
2. `### HI-M3 — 전환 키 나머지 셋과 CapsLock` 제목에 `(**완료, 2026-09-01**)`를
   더한다.
3. `## HI-M2가 실측한 것` 절 **뒤에** `## HI-M3이 실측한 것` 절을 새로 만든다.
   HI-M0·M1·M2의 절과 같은 모양으로, **실행이 답한 것만** 적는다. 최소한
   다음이 들어간다.
   - 게이트 시간 삼중값과 그것이 갈렸는지
   - `hold_key`의 sleep이 실제로 필요했는지(안 기다렸을 때 무슨 일이
     일어나는지 실행으로 봤다면 그것)
   - 줄 끝 앵커(`$`)가 CR 때문에 깨졌는지 아닌지 — HI-M1 실측 4의 후속이다
   - 기존 검사가 Task 1·3에서 한 줄도 안 바뀐 채 통과했는지
   - 예상과 달랐던 것 전부

- [ ] **Step 4: `HANDOFF.md`·`MEMORY.md`·기억 파일·`CLAUDE.md`를 갱신한다**

- `HANDOFF.md` — 맨 위 제목과 "지금 어디인가"를 **"Hangul Input이 끝났다"**로
  고치고, "다음 세션이 할 첫 일"을 새 서브프로젝트를 고르는 자리로 바꾼다.
  "HI-M3이 실행으로 증명한 것" 절을 앞에 놓는다.
- `docs/decisions/project_hangul_input.md` — HI-M3의 내용을 더한다.
- `MEMORY.md` — 해당 줄의 hook을 갱신한다.
- `CLAUDE.md`의 "진행 중인 서브프로젝트: Hangul Input(HI)" 줄을 **완료된
  서브프로젝트 목록으로 옮긴다.**

- [ ] **Step 5: 커밋**

```bash
git diff --stat
git add check.sh docs/ HANDOFF.md MEMORY.md CLAUDE.md
git commit -m "Close out HI-M3 and the hangul input subproject"
```

---

## 이 plan을 다시 읽으면서 잡은 것

**1. `expectCtx`에 인자를 더하면 Task 1의 증거가 사라진다.** 처음에는
`expectCtx`의 시그니처를 직접 넓히려 했는데, 호출이 26군데라 그러면 기존 검사가
26줄 바뀐다. **"기존 검사가 한 글자도 안 바뀐 채 통과했다"가 Task 1의 유일한
판정이므로** 본체를 `expectFull`로 옮기고 껍데기를 남기는 쪽으로 바꿨다.

**2. Zig는 안 쓰는 함수 인자를 컴파일 에러로 막는다.** 컨테이너에서 확인했다
(`error: unused function parameter`, zig 0.16.0). 그래서 Task 1에 `_ = time_us;`
한 줄이 들어가고 Task 5가 그것을 지운다 — **plan에 그 줄이 언제 사라지는지를
적어 두지 않으면 나중에 "왜 여기 이게 있지"가 된다.**

**3. `hangul_toggle`의 기본값은 Claude가 못 정한다.** `keyboard=apple`·
`hangul_layout=shin_pcs`와 같은 종류의 결정("이 기계를 쓰는 사람이 쓰는 것")
이라 착수 전에 사용자에게 물었고, 답이 **넷 다**였다.

**4. 기본값이 넷이 되면서 게이트가 심을 값이 정해졌다.** "심는 값이 기본값과
달라야 한다"는 규칙(design 결정 14)이 서려면 하나를 빼야 하는데, 뺄 수 있는
것은 `hangul_key` 하나뿐이다 — 나머지 셋은 각각 기존 검사 셋과 새 검사 넷이
쓴다. **그 키가 하필 게이트가 어차피 못 보내는 키라는 것이 우연히 잘 맞았다.**

**5. 소비 표시를 modifier switch 뒤에 두면 Shift가 안 세어진다.** 코드를 읽다가
잡았다 — Shift·Alt·Meta 갈래가 switch **안에서** `return`한다. 실행 중에
만났다면 증상이 "Ctrl+Shift+C를 쓸 때만 한/영이 바뀐다"라 원인을 찾기 어려웠을
것이다. `input_test`의 검사 41이 그 자리를 보는 유일한 검사다.

**6. `sendkey`의 hold를 안 기다리면 다음 키가 소비를 켠다.** QEMU의 monitor는
hold 타이머를 걸고 즉시 돌아온다(HI-M0 실측 2의 값이 그것을 말한다 —
`shift 500`이 499,979µs였다는 것은 QEMU가 그 시간을 실제로 잡고 있었다는 뜻이다).
`type_keys`는 로그가 자라면 바로 다음 키로 가므로 이 함정을 밟는다.

**7. `screen_count 'ABC1'`이 결정 9를 통째로 본다.** 처음에는 `ABC`만 세려
했는데, 그러면 "CapsLock이 Shift를 통째로 건다"는 구현이 통과한다. 숫자 하나를
붙이는 것으로 "알파벳에만"이라는 조건이 화면에서 갈린다.

**8. 검사 48의 글자를 `k`에서 `o`로 바꿨다.** `rk`(가)로는 대문자 잠금이 한글
층에 새도 아무것도 안 보인다 — 두벌식에서 `K`가 따로 없기 때문이다. `o`(ㅐ)와
`O`(ㅒ)는 갈리므로 `개`가 `걔`가 되는 것이 보인다. **plan을 쓰면서 손으로
돌려 보다가 잡았고**, 실행 중에 만났다면 "검사가 통과하니 안전하다"고 믿었을
것이다.

**9. `none`을 파서가 받아 줘야 왕복이 닫힌다.** `arg()`가 빈 집합에 `none`을
쓰는데 그 이름이 `ToggleKey`에 없어서, 안 막으면 전환 키를 다 끈 사람의 부팅
로그에 매번 경고가 찍힌다. **"쓰는 쪽과 읽는 쪽이 같은 문법이어야 한다"를
검사로 못 박으니 이 구멍이 드러났다.**

**10. 줄 끝 앵커가 CR에 걸릴 수 있다.** HI-M1 실측 4가 `[^ ]+`로 밟은 것과 같은
함정이 `$`에도 있을 수 있어서, Task 7에 확인 Step을 따로 뒀다. **처방을 미리
적어 두는 것(`\r\?$`)과 확인 Step을 두는 것이 둘 다 필요하다** — 미리 붙이면
필요 없는 복잡함이고, 안 적어 두면 실패했을 때 원인을 다시 찾는다.
