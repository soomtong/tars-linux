# DM-M1 — 수정키와 tap을 키보드 칸마다 든다

> 구현 파일은 Claude가 넣고 diff를 실제 파일과 대조한 뒤 게이트 · commit한다. 사용자가 외출하며 M1의 마무리(닫는 묶음 · 커밋)까지
> 맡겼다(2026-11-04). push와 gh-pages push는 사용자가 한다. 줄 번호는 `056d010` 기준이다.

Goal: DM design 결정 1~5. 끝나면 `keyboard` 체인의 판정 8 · 9 · 10이 초록이고 KH 판정 1~7b도 초록이며, mutation 셋이 각자 잡힌다.

Architecture: `input.zig`의 `State`에서 bool 여덟과 `Tap` 둘을 칸 배열로 바꾸고, 읽기는 OR 하나(`anyMods`)를 거친다. `main.zig`는
칸 번호를 `Context.device`에 싣고 `closeKeyboard`가 `releaseDevice(slot)`를 부른다. 로그 · argv · 체인 모양은 안 바뀐다.

## 착수 전에 확인한 것

- 필드를 쓰는 자리: `input.zig`의 `markTapConsumed` · `shifted` · `modifiers` · `ctrled` · `alted` · `metaed` · `releaseHeld` ·
  `handleKey`의 수정키 갈래 여덟과 CapsLock · 왼쪽 Ctrl · 오른쪽 Meta 갈래. `input_test.zig`는 `.{ .shift_left = true }` 하나(검사
  80)와 `releaseHeld` 넷(검사 86). `main.zig`는 `closeKeyboard` 하나.
- `main.zig:2383`의 `MAX_KEYBOARDS`를 `fds` 크기 · 칸 배열 · 함수 시그니처 일곱 자리가 쓴다. `input.MAX_KEYBOARDS`의 별칭으로 두면
  그 자리는 안 바뀐다.
- `readKeyboard(fd)`를 부르는 곳은 `readKeyboards` 하나다.
- 커널 자동 반복(DM-M0 실측 1)은 자기 칸의 비트를 다시 켤 뿐이라 칸별 비트에서 맞는 동작이다.

## Task 1: `input.zig`

- `pub const MAX_KEYBOARDS = 8;`(주석은 `main.zig`의 것을 옮긴다), `pub const Mods = packed struct(u8)`(지금 이름 여덟),
  `const Taps = struct { caps: Tap, lctrl: Tap }`.
- `State`: 수정키 bool 여덟 → `mods: [MAX_KEYBOARDS]Mods = @splat(.{})`, `caps_tap` · `lctrl_tap` → `taps: [MAX_KEYBOARDS]Taps =
  @splat(.{})`. 둘의 주석에 결정 1 · 2.
- `fn anyMods(self) Mods` — 여덟 칸을 `u8`로 OR. `shifted` · `ctrled` · `alted` · `metaed` · `modifiers`가 이것을 본다.
- `markTapConsumed(code, dev)` — 모든 칸의 쥔 tap을 소비로, 같은 칸의 같은 키만 뺀다.
- `fn otherHolds(self, dev, which)` — 다른 칸이 그 tap 키를 쥐고 있는가. CapsLock · 왼쪽 Ctrl의 누름에서 `down` 뒤에 참이면
  `consumed = true`(결정 2).
- `handleKey`: 머리에서 `const dev = ctx.device; std.debug.assert(dev < MAX_KEYBOARDS);`, 수정키 갈래는 `self.mods[dev]`, tap은
  `self.taps[dev]`. 받아쓰기의 `combined`는 `anyMods`의 `meta_left`.
- `releaseHeld()` → `releaseDevice(slot)`: 그 칸이 `meta_right`를 쥐었으면 `dictate_tap.reset()`, 그다음 `mods[slot]` · `taps[slot]`을
  처음으로. 주석은 결정 4로 고쳐 쓴다.
- `Context.device: u8 = 0` — "이 배치가 어느 키보드 칸에서 왔는가".
- `Keys.gone`의 주석의 `releaseHeld`를 `releaseDevice`로.

## Task 2: `main.zig`

- `const MAX_KEYBOARDS = input.MAX_KEYBOARDS;`(주석은 "수와 그 이유는 `input.zig`").
- `readKeyboards`가 `ki`를 `readKeyboard(kfd.fd, ki)`로 넘기고 `Context`에 `.device = @intCast(ki)`.
- `closeKeyboard`: `state.releaseDevice(slot)`, 주석을 결정 4로. `KeyboardDev` 주석의 "모든 키보드가 하나를 같이 쓴다"에 "수정키와
  tap만 칸마다(DM)"를 덧붙인다.

## Task 3: 단위 검사(`input_test.zig`)

- 검사 80의 `.{ .shift_left = true }`를 `mods[0].shift_left = true`로.
- 검사 86을 `releaseDevice(0)`으로 고친다(칸 하나일 때 그대로 맞다).
- 새 검사 88(DM):
  1. 칸 1의 Shift 누름 → 칸 0의 Shift 누름 · 뗌 → 칸 0의 `a`가 `A`(결정 1, 판정 8).
  2. 칸 0의 Shift 누름 → `releaseDevice(1)` → `A`, `releaseDevice(0)` → `a`(결정 4, 판정 9).
  3. 칸 1의 왼쪽 Ctrl 누름 → 칸 0의 누름 · 뗌 → 칸 1의 뗌, 다 50ms 간격 → 한/영 그대로(결정 2, 판정 10). 대조로 칸 0 혼자의
     tap은 한/영을 켠다.
  4. 칸 1의 Shift + 칸 0의 `a` = `A`(OR, KH 판정 4의 단위판).
  5. 칸 1이 오른쪽 Meta를 쥔 채(첫 누름) `releaseDevice(1)` → 칸 0의 오른쪽 Meta 탭 하나가 더블 탭이 아니다. 칸 0이 첫 탭을 끝낸 뒤
     `releaseDevice(1)`(칸 1은 아무것도 안 쥠) → 칸 0의 둘째 누름이 `.toggle`(결정 4).
- `rg 'mods\[[0-9]' input.zig`가 비어 있는지(위험 2).

## Task 4: 검사

`make quick`, 컨테이너에서 terminal `zig build test`, `keyboard` 체인. 셋 다 초록이면 mutation 셋(design 결정 7) — 각각 체인을
돌려 잡는 판정을 적고 되돌린다. (a)는 KH 판정 4, (b)는 판정 9, (c)는 판정 10.

## Task 5: 루트 게이트

`RUNS=1`(약 16분). 바뀐 것이 terminal의 키 경로라 키를 치는 체인 전부가 다시 본다. 빨강이 있으면 그 회차 로그부터.

## Task 6: 닫기 · 커밋

- design: Status 끝남, "실측 (M1)"(체인 · 게이트 · mutation).
- KH design 결정 4의 대가 문단 · 비목표 5에 "DM이 닫았다" 포인터. `carryover.md` KH 둘째 항목 `[x]`.
- `completed.md` 행, `docs/decisions/project_device_modifiers.md` + `MEMORY.md` 한 줄, `HANDOFF.md`.
- 소개 페이지(`gh-pages`의 `data.js`)는 `site/README.md`의 순서대로 고쳐 로컬 커밋만 한다. push는 사용자에게 남긴다.
- add 대상을 좁힌다.

## 결과 (2026-11-04)

Task 1~5 그대로 됐다. 어긋난 것 둘 — mutation (a)는 판정 4가 아니라 판정 3에서 잡혔고(design 실측 4), 루트 게이트 첫 시도가 진입
검사(`| grep -q`)에서 멈췄다(실측 5).
