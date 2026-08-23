# TARS Terminal Rendering TR-M0 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 구현 파일 편집은
> 사용자가 하고, 빌드·QEMU·게이트·조사성 명령은 Claude가 실행하며, Claude는 각
> Step의 정확한 내용을 제시하고 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는
> 이 저장소에 적용하지 않는다.

**Goal:** 화면이 색을 갖는다. libghostty-vt가 이미 파싱해 둔 SGR을 `vt.zig`가
확정된 RGB로 풀어 내보내고, 렌더러가 그것을 칠하며, 게이트가 그 색을
**프레임버퍼 픽셀까지 되읽어** 증명한다. 커서도 처음으로 화면에 보인다.

**Design doc:** `docs/superpowers/specs/2026-08-23-tars-terminal-rendering-design.md`
(결정 1~9가 이 milestone의 몫이다. 결정 10~13은 TR-M2, 한글은 TR-M1이다.
design은 승인되어 있으므로 다시 논의하지 않는다.)

**Tech Stack:** Zig 0.16, libghostty-vt(vendor된 ghostty 소스),
DRM dumb buffer(`MAP_SHARED`), stb_truetype, QEMU monitor `sendkey`,
bash 게이트 스크립트

---

## 착수 전에 이미 확정된 사실 (2026-08-23 실측)

**plan을 쓰면서 컨테이너에서 직접 돌려 확인한 값들이다. 다시 조사하지 않는다.**
`/tmp`에 임시 Zig 프로젝트를 만들어 vendor된 `ghostty-src`를 path 의존으로
걸고 실행했다(저장소는 건드리지 않았다).

**1. libghostty-vt는 aarch64에서 빌드되고 돈다.** `terminal/build.zig`의 마지막
주석이 "arm64로 빌드해야 하는데 검증된 적이 없다(`src/simd/` 아래에 벡터
코드가 있다)"고 적어 둔 것이 이번에 해소됐다. `arch=aarch64`로 찍고 정상
동작했다. simd는 Google Highway를 쓰고 ghostty 자체가 Apple Silicon에서
도는 프로그램이므로 놀랄 일이 아니다.

**이것이 Task 2를 가능하게 만든다.** `vt_test`는 지금 **빌드만 되고 아무도
실행하지 않는다**(`build.zig`가 그 사실을 주석으로 적어 두었다).

**2. SGR별로 나오는 값이 이렇다.** 입력은
`A\e[31mB\e[0m\e[41mC\e[0m\e[1;31mD\e[0m\e[7mE\e[0m\e[38;2;18;52;86mF\e[0m`이고,
`Terminal.Options.colors`에 우리 색(`bg=#102030`, `fg=#FFFFFF`)을 넣은 상태다.

| x | 글자 | 입력 | `style_id` | `fg()` | `bg()` | 플래그 |
|---|---|---|---|---|---|---|
| 0 | A | 평범 | **0** | — | — | `style`을 읽으면 안 됨 |
| 1 | B | `\e[31m` | 1 | `#CC6666` | null | — |
| 2 | C | `\e[41m` | 2 | `#FFFFFF` | `#CC6666` | — |
| 3 | D | `\e[1;31m` | 3 | `#D54E53` | null | `bold=true` |
| 4 | E | `\e[7m` | 4 | `#FFFFFF` | null | `inverse=true` |
| 5 | F | `\e[38;2;18;52;86m` | 5 | `#123456` | null | — |
| 6 | (없음) | 커서 자리 | 0 | — | — | `codepoint()==0` |

**팔레트가 xterm 고전값이 아니다.** 빨강이 `#CD0000`이 아니라 **`#CC6666`**,
밝은 빨강이 `#D54E53`이다. 게이트가 기대할 값이 이것이다 — 짐작으로 적었으면
틀렸을 자리다.

**3. `Style.fg(opts)`에 `.bold = .bright`를 주면 bold가 밝은 색이 된다.**
위 표의 x=3이 그 증거다(팔레트 1 → 9). 반환은 `color.RGB`이고 null이 없다.

**4. `Style.bg()`는 `?color.RGB`이고 null이 "기본 배경"이다.** 인자는
`*const page.Cell`(우리가 이미 갖고 있는 `raw`)과 팔레트다.

**5. `inverse`는 아무도 처리해 주지 않는다.** x=4가 `fg=#FFFFFF, bg=null,
inverse=true`로 나온다 — 라이브러리는 플래그만 알려주고 색을 바꿔 주지 않는다.

**6. 기본 스타일의 `style_id`는 0이다**(`style.zig:17`의 `default_id`).
그 모듈은 `lib_vt.zig`가 네임스페이스로 내보내지 않으므로 코드에서는 `0`을
쓰고 주석으로 출처를 적는다.

**7. `Terminal.Options.colors`의 네 값은 `DynamicRGB`다**(`color.zig:331`).
`.init(rgb)`가 "OSC로 덮어쓸 수 있는 기본값"을 넣는 자리이고, `.unset`이
"정하지 않음"이다. `.init`으로 넣으면 `RenderState.colors.background`가
그 값으로 나온다(실측: `bg=#102030`).

**8. 커서는 `state.cursor.viewport`에 `{x, y, wide_tail}`로 온다.**
실측에서 `x=6 y=0 visual_style=block`이었다. 타입은 `size.CellCountInt`라
`usize`와 직접 비교하면 컴파일이 막힌다 — 캐스팅한다.

**9. 아무 설정도 안 주면 기본 색이 `fg=#FFFFFF`, `bg=#000000`이다.**
지금 `main.zig`의 `BACKGROUND = 0x00102030`과 다르다. 결정 5가 필요한 이유다.

## 저장소 쪽 출발 상태

- `terminal/src/vt.zig:66` `cells()`가 `codepoint`·`col`·`row`만 꺼내고
  `codepoint == 0`인 셀을 건너뛴다(`:78`).
- `terminal/src/main.zig:17-18` `BACKGROUND`/`TEXT_COLOR` 상수.
  `drawGlyph`(`:24`)가 `coverage > 127`에서 `TEXT_COLOR`를 찍고,
  `render`(`:40`)가 `fb.fill(BACKGROUND)` 뒤에 글리프를 그린다.
- `terminal/src/drm.zig:117` `Framebuffer`. `setPixel`(`:128`)은 있고
  `getPixel`은 없다. `pixels`가 `[*]volatile u8`이고 `mmap`이
  `PROT_READ | PROT_WRITE`다(`:261`).
- `terminal/src/main.zig:151` `setenv("TERM", "xterm", 1)`.
- `terminal/build.zig` 마지막 절: `vt_test`가 x86_64로 빌드되고 실행되지 않는다.
- 루트 `check.sh:92-97`에 여섯 체인. monitor 포트 45455~45459 사용, **45460 비어
  있음**.
- `terminal: screen>` 줄을 **다섯 체인이 grep한다**(TF·CP·IP·PM·HD).

## 왜 이 순서인가

```
Task 1  프레임버퍼 되읽기가 되는가            ← 위험 4. 안 되면 설계가 무너진다
  ↓     getPixel 하나 + 부팅 1회
Task 2  vt_test를 호스트에서 돌게 만든다      ← 부팅 없음. 지금 안 도는 검사를 살린다
  ↓     Task 3의 TDD가 여기에 얹힌다
Task 3  vt.zig가 색을 확정해 내보낸다         ← 부팅 없음. TDD
  ↓
Task 4  렌더러가 두 색을 칠한다                ← 부팅. 화면이 색을 갖는다
  ↓
Task 5  블록 커서                              ← 부팅
  ↓
Task 6  style> · pixel> 로그 두 줄             ← 부팅. 게이트가 볼 것을 확정한다
  ↓
Task 7  TERM=xterm-256color + 여섯 체인 회귀   ← 가장 큰 회귀 위험
  ↓
Task 8  새 체인 render/check.sh                ← 완료선
  ↓
Task 9  루트 게이트 등록 + 3/3
  ↓
Task 10 문서
```

**Task 1이 맨 앞인 이유는 design 위험 4다.** 프레임버퍼 되읽기가 우리가 쓴
값을 돌려주지 않으면 결정 7(두 겹 검사)이 통째로 무너진다. 다른 것을 만들기
전에 알아야 한다. 게다가 이 확인은 **지금 코드 그대로** 할 수 있다 —
`main.zig`가 이미 `fb.fill(BACKGROUND)`를 부르므로 그 뒤에 읽어 보면 된다.

**Task 2가 Task 3보다 앞인 이유는 검사가 돌지 않으면 TDD가 성립하지 않기
때문이다.** design doc이 "`vt_test.zig`에 검사를 더한다"고 적었는데, 그 파일은
지금 아무도 실행하지 않는다. 먼저 살려 놓는다.

**Task 6이 Task 4·5보다 뒤인 이유는 로그 문구 때문이다.** 게이트가 grep할
문자열은 실제로 찍힌 것을 보고 확정한다. 코드에 적은 문구와 게이트가 찾는
문구가 어긋나는 사고가 이 저장소에 이미 있었다(`HANDOFF.md`).

**Task 7이 Task 8보다 앞인 이유는 위험의 성격이다.** `TERM`을 바꾸면 셸이
고르는 시퀀스가 달라져 **기존 다섯 체인이 보는 화면 문자열이 흔들릴 수
있다.** 새 체인을 만들기 전에 기존 것이 안 깨졌는지 먼저 본다. 새 체인이
통과하는데 옛 체인이 깨지는 것이 이 milestone에서 가장 그럴듯한 실패다.

## 이번에 정하는 것 넷 (design doc이 안 정한 자리)

**1. `style>` 로그의 상한은 한 프레임에 16셀이고, 잘렸으면 그 사실을 찍는다.**
design 결정 7이 "상한 값은 plan에서 정한다"고 넘긴 자리다. 16인 이유는
게이트가 검사에 쓰는 셀이 한 줄 안의 몇 개이기 때문이고, 잘린 사실을 찍는
이유는 조용히 자르면 "색이 없다"와 "너무 많아서 안 찍었다"를 가를 수 없기
때문이다.

**2. 게이트가 치는 명령은 `printf '\033[41m \033[0m\n'`이다.** 배경색을 칠한
**공백**을 쓰는 이유는 design 결정 7에 있다 — 공백이면 셀 전체가 배경색이라
어느 픽셀을 읽어도 같다. `\e`가 아니라 `\033`을 쓰는 이유는 셸마다 `\e`
지원이 갈리기 때문이고, `printf`는 fish·bash 양쪽의 빌트인이라 `PATH`가 비어
있어도 된다(`project_guest_environment`).

**3. `pixel>`이 읽는 자리는 셀의 중앙이다.** 정확히는
`(GRID_X + col*CELL_W + CELL_W/2, GRID_Y + row*ROW_HEIGHT + ROW_HEIGHT/2)`다.
모서리를 안 읽는 이유는 그 자리가 이웃 셀과의 경계라 off-by-one에 취약하기
때문이다.

**4. `getPixel`은 `Framebuffer`의 메서드로 `setPixel` 바로 아래에 둔다.**
같은 오프셋 계산을 두 번 적게 되지만, 한 줄짜리 헬퍼를 따로 빼면 읽는 사람이
오히려 두 곳을 봐야 한다.

---

## Task 1: 프레임버퍼를 되읽을 수 있는지 확인한다

**Files:**
- Modify: `terminal/src/drm.zig` (`setPixel` 아래, 현재 `:132` 다음)
- Modify: `terminal/src/main.zig` (현재 `:76-78`)

design 위험 4를 먼저 친다. 되읽기가 안 되면 결정 7이 무너지므로 다른 것을
만들기 전에 안다.

- [ ] **Step 1: `drm.zig`에 `getPixel`을 더한다**

`terminal/src/drm.zig`의 `setPixel` 함수(현재 `:128-132`) **바로 다음 줄**에
아래를 넣는다. `setPixel`은 그대로 둔다.

**넣을 것:**

```zig

    /// 우리가 쓴 픽셀을 그대로 되읽는다. dumb buffer를 MAP_SHARED로 잡았고
    /// (`:262`) 단일 버퍼라(present가 setcrtc 한 번) 렌더 직후에 읽으면
    /// 그것이 곧 화면이다. 게이트가 "렌더러가 색을 진짜로 칠했는가"를 보는
    /// 유일한 창구다(design 결정 7).
    pub fn getPixel(self: Framebuffer, x: u32, y: u32) u32 {
        const offset = y * self.pitch + x * 4;
        const ptr: *volatile u32 = @ptrCast(@alignCast(self.pixels + offset));
        return ptr.*;
    }
```

- [ ] **Step 2: `main.zig`가 되읽은 값을 찍게 한다 (임시)**

`terminal/src/main.zig`의 현재 `:76-78`이 이렇다.

**지울 것:**

```zig
    const fb = try drm.open(allocator, "/dev/dri/card0");
    fb.fill(BACKGROUND);
    try fb.present();
```

**넣을 것:**

```zig
    const fb = try drm.open(allocator, "/dev/dri/card0");
    fb.fill(BACKGROUND);
    try fb.present();
    // Task 1 임시 확인 — design 위험 4. Task 6에서 진짜 로그로 바뀐다.
    std.debug.print("terminal: probe> wrote {X:0>6} read {X:0>6}\n", .{
        BACKGROUND, fb.getPixel(100, 100) & 0x00FFFFFF,
    });
```

- [ ] **Step 3: 빌드한다**

Claude가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && ./prepare.sh && zig build'
```

기대: 에러 없이 끝난다.

- [ ] **Step 4: 게스트를 띄워 확인한다**

Claude가 실행한다(커널 빌드 포함 약 1분 30초).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash device/check.sh 2>&1 | rg 'terminal: probe>'
```

기대 출력:

```
terminal: probe> wrote 102030 read 102030
```

**두 값이 같으면 결정 7이 성립한다.** 다르면 여기서 멈추고 design 결정 7을
다시 논의한다 — 그 경우 `style>` 한 겹만 남기고 `pixel>`을 접는 것이 대안이다.

- [ ] **Step 5: 커밋**

Claude가 실행한다.

```bash
git add terminal/src/drm.zig terminal/src/main.zig
git commit -m "Read back a pixel to prove the framebuffer answers"
```

---

## Task 2: `vt_test`를 호스트 아키텍처에서 돌게 만든다

**Files:**
- Modify: `terminal/build.zig` (`vt_test` 블록과 마지막 주석)

지금 `vt_test`는 x86_64로 빌드만 되고 아무도 실행하지 않는다. Task 3의 TDD가
여기에 얹히므로 먼저 살린다. **arm64에서 도는 것은 이미 확인했다**(위 "착수 전에
이미 확정된 사실" 1번).

- [ ] **Step 1: `vt_test`를 호스트 타깃으로 옮긴다**

`terminal/build.zig`의 현재 `vt_test` 블록이 이렇다.

**지울 것:**

```zig
    const vt_test_mod = b.createModule(.{
        .root_source_file = b.path("src/vt_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    vt_test_mod.addImport("ghostty-vt", ghostty_dep.module("ghostty-vt"));
    const vt_test = b.addExecutable(.{
        .name = "vt_test",
        .root_module = vt_test_mod,
    });
    b.installArtifact(vt_test);
```

**넣을 것:** (아무것도 넣지 않는다 — 이 블록은 아래 호스트 절로 옮겨간다)

- [ ] **Step 2: 호스트 절에 `vt_test`를 다시 만든다**

`terminal/build.zig`에서 `const host_target = b.resolveTargetQuery(.{});` 줄
**다음에** 아래를 넣는다(`input_test_mod` 블록보다 위다).

**넣을 것:**

```zig

    // vt_test도 호스트에서 돈다. 2026-08-23에 libghostty-vt를 aarch64로
    // 빌드해 실행되는 것을 확인했다 — 그전까지 "검증된 적이 없다"는 이유로
    // x86_64에 남겨 두었고, 그래서 **빌드만 되고 아무도 실행하지 않았다.**
    // simd는 Google Highway를 쓰고 ghostty 자체가 Apple Silicon에서 도는
    // 프로그램이라 놀랄 일은 아니었다.
    const ghostty_host_dep = b.dependency("ghostty", .{
        .target = host_target,
        .optimize = optimize,
    });
    const vt_test_mod = b.createModule(.{
        .root_source_file = b.path("src/vt_test.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    vt_test_mod.addImport("ghostty-vt", ghostty_host_dep.module("ghostty-vt"));
    const vt_test = b.addExecutable(.{
        .name = "vt_test",
        .root_module = vt_test_mod,
    });
    b.installArtifact(vt_test);
```

- [ ] **Step 3: `test` step에 `vt_test`를 넣는다**

`terminal/build.zig`의 마지막 부분이 이렇다.

**지울 것:**

```zig
    const test_step = b.step("test", "호스트 아키텍처로 도는 검사를 실행한다");
    test_step.dependOn(&b.addRunArtifact(input_test).step);

    // pty_test와 vt_test는 x86_64로 남겨둔다. 호스트로 옮길 수 없어서다:
    //   pty_test  — /usr/bin/fish를 exec한다. 그 fish는 게스트용 x86_64다.
    //   vt_test   — libghostty-vt를 arm64로 빌드해야 하는데 검증된 적이 없다
    //               (src/simd/ 아래에 벡터 코드가 있다).
    // 둘 다 지금은 빌드만 되고 아무도 실행하지 않는다는 사실을 여기 적어둔다.
}
```

**넣을 것:**

```zig
    const test_step = b.step("test", "호스트 아키텍처로 도는 검사를 실행한다");
    test_step.dependOn(&b.addRunArtifact(input_test).step);
    test_step.dependOn(&b.addRunArtifact(vt_test).step);

    // pty_test만 x86_64로 남는다. /usr/bin/fish를 exec하는데 그 fish는
    // 게스트용 x86_64라 호스트로 옮길 수 없다 — **빌드만 되고 아무도
    // 실행하지 않는다.** vt_test는 TR-M0에서 호스트로 옮겨 이제 돈다.
}
```

- [ ] **Step 4: 지금 있는 검사가 통과하는지 본다**

Claude가 실행한다. `vt_test.zig`는 아직 안 고쳤으므로 **기존 세 검사가 그대로
통과해야 한다** — 여기서 실패하면 아키텍처 이동이 무언가를 깼다는 뜻이다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && zig build test'
```

기대 출력에 이 줄들이 있어야 한다.

```
after 1st feed: 5 cells
after 2nd feed: 7 cells
after split escape (clear): 0 cells
PASS
```

(`input_test`의 `input_event size = 24 (expected 24)` / `PASS`도 함께 나온다.)

- [ ] **Step 5: 커밋**

```bash
git add terminal/build.zig
git commit -m "Run the vt test instead of only building it"
```

---

## Task 3: `vt.zig`가 색을 확정해 내보낸다

**Files:**
- Modify: `terminal/src/vt.zig` (`CellGlyph` `:4-8`, `init` `:42`, `cells` `:66-88`)
- Test: `terminal/src/vt_test.zig`

design 결정 1·2·3·5. 부팅 없이 끝난다.

- [ ] **Step 1: 실패하는 검사를 먼저 쓴다**

`terminal/src/vt_test.zig`의 마지막 `std.debug.print("PASS\n", .{});` **앞에**
아래를 넣는다. 기존 검사 셋은 그대로 둔다.

**넣을 것:**

```zig

    // ── TR-M0: 색 ─────────────────────────────────────────────────────
    //
    // 기대값은 plan을 쓰면서 컨테이너에서 직접 재 둔 것이다. 팔레트가 xterm
    // 고전값이 아니라는 것이 요점이다 — 빨강이 #CD0000이 아니라 #CC6666이다.
    screen.feed("\x1b[2J\x1b[H");
    screen.feed("A\x1b[31mB\x1b[0m\x1b[41mC\x1b[0m\x1b[1;31mD\x1b[0m\x1b[7mE\x1b[0m\x1b[38;2;18;52;86mF\x1b[0mG");
    const styled = try screen.cells(&buf);

    const Want = struct { cp: u32, fg: u32, bg: u32, what: []const u8 };
    const wants = [_]Want{
        .{ .cp = 'A', .fg = 0xFFFFFF, .bg = 0x102030, .what = "스타일을 가진 적 없는 셀" },
        .{ .cp = 'B', .fg = 0xCC6666, .bg = 0x102030, .what = "SGR 31 빨강 전경" },
        .{ .cp = 'C', .fg = 0xFFFFFF, .bg = 0xCC6666, .what = "SGR 41 빨강 배경" },
        .{ .cp = 'D', .fg = 0xD54E53, .bg = 0x102030, .what = "SGR 1;31 bold는 밝게" },
        .{ .cp = 'E', .fg = 0x102030, .bg = 0xFFFFFF, .what = "SGR 7 inverse는 맞바꾼다" },
        .{ .cp = 'F', .fg = 0x123456, .bg = 0x102030, .what = "truecolor" },
        // A와 다른 것을 본다. A는 스타일을 가진 적이 없고, G는 **가졌다가
        // SGR 0으로 되돌아온** 셀이다. 리셋이 고장나면 A는 멀쩡한데 G만
        // 틀린다.
        .{ .cp = 'G', .fg = 0xFFFFFF, .bg = 0x102030, .what = "SGR 0 뒤의 셀" },
    };

    for (wants) |want| {
        var found = false;
        for (styled) |cell| {
            if (cell.codepoint != want.cp) continue;
            found = true;
            if (cell.fg != want.fg or cell.bg != want.bg) {
                std.debug.print(
                    "FAIL: {s}: '{c}' fg=#{X:0>6} bg=#{X:0>6} (expected fg=#{X:0>6} bg=#{X:0>6})\n",
                    .{ want.what, @as(u8, @intCast(want.cp)), cell.fg, cell.bg, want.fg, want.bg },
                );
                return error.WrongColor;
            }
            std.debug.print("vt_test: {s} OK\n", .{want.what});
            break;
        }
        if (!found) {
            std.debug.print("FAIL: {s}: '{c}' 셀이 없다\n", .{ want.what, @as(u8, @intCast(want.cp)) });
            return error.CellMissing;
        }
    }
```

- [ ] **Step 2: 실패하는 것을 확인한다**

Claude가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && zig build test' 2>&1 | tail -20
```

기대: **컴파일 에러.** `CellGlyph`에 `fg`·`bg` 필드가 없다는 내용이다
(`no field named 'fg' in struct 'vt.CellGlyph'`). 이것이 옳은 실패다.

- [ ] **Step 3: `CellGlyph`에 색을 더한다**

`terminal/src/vt.zig`의 현재 `:4-8`이 이렇다.

**지울 것:**

```zig
pub const CellGlyph = struct {
    codepoint: u32,
    col: u16,
    row: u16,
};
```

**넣을 것:**

```zig
/// 렌더러에게 넘기는 셀 하나.
///
/// `fg`·`bg`는 프레임버퍼와 같은 `0x00RRGGBB` 형식으로 **이미 해소된** 값이다.
/// `Style`을 그대로 흘려보내지 않는 이유가 design 결정 1이다 — 색을 푸는 데
/// 필요한 것(팔레트, 기본 fg/bg, bold 옵션)이 전부 여기 `RenderState`에 있고,
/// 렌더러는 팔레트도 SGR도 몰라야 한다. inverse와 커서도 여기서 두 색을
/// 맞바꿔 해소하므로 `main.zig`는 "반전"이라는 개념 자체를 배우지 않는다.
pub const CellGlyph = struct {
    codepoint: u32,
    col: u16,
    row: u16,
    fg: u32,
    bg: u32,
};

/// `color.RGB`를 프레임버퍼의 XRGB8888 한 워드로 만든다.
fn packRgb(c: ghostty_vt.color.RGB) u32 {
    return (@as(u32, c.r) << 16) | (@as(u32, c.g) << 8) | c.b;
}
```

- [ ] **Step 4: 우리 색을 터미널의 기본값으로 넘긴다**

`terminal/src/vt.zig`의 현재 `:42`가 이렇다.

**지울 것:**

```zig
            .term = try .init(io, alloc, .{ .cols = cols, .rows = rows }),
```

**넣을 것:**

```zig
            // 기본 색을 여기서 준다(design 결정 5). 값은 main.zig가 쓰던
            // 상수와 같게 유지한다 — 이번 변경이 화면의 색을 바꾸는 일이 되면
            // 게이트의 회귀와 우리 변경을 가르기 어려워진다.
            //
            // `.init`은 "OSC로 덮어쓸 수 있는 기본값"이라는 뜻이다
            // (`color.zig:337`). 그래서 셸이 OSC 10/11로 배경·전경을 바꾸는
            // 것이 저절로 동작한다. `.unset`이면 라이브러리 기본값
            // (fg=#FFFFFF, bg=#000000)이 나온다.
            .term = try .init(io, alloc, .{
                .cols = cols,
                .rows = rows,
                .colors = .{
                    .background = .init(.{ .r = 0x10, .g = 0x20, .b = 0x30 }),
                    .foreground = .init(.{ .r = 0xFF, .g = 0xFF, .b = 0xFF }),
                    .cursor = .unset,
                    .palette = .default,
                },
            }),
```

- [ ] **Step 5: `cells()`가 색을 풀어 담는다**

`terminal/src/vt.zig`의 현재 `cells` 함수 전체(`:64-88`, 주석 두 줄 포함)가
이렇다.

**지울 것:**

```zig
    /// 현재 화면에서 빈 칸이 아닌 셀만 out에 채워 반환한다.
    /// out은 최소 cols*rows 크기여야 안전하다.
    pub fn cells(self: *Screen, out: []CellGlyph) ![]CellGlyph {
        try self.state.update(self.alloc, &self.term);

        var n: usize = 0;
        const row_data = self.state.row_data.slice();
        const row_cells = row_data.items(.cells);
        for (0..self.state.rows) |y| {
            const cells_slice = row_cells[y].slice();
            const raws = cells_slice.items(.raw);
            for (0..self.state.cols) |x| {
                if (n >= out.len) return out[0..n];
                const cp = raws[x].codepoint();
                if (cp == 0) continue;
                out[n] = .{
                    .codepoint = @intCast(cp),
                    .col = @intCast(x),
                    .row = @intCast(y),
                };
                n += 1;
            }
        }
        return out[0..n];
    }
```

**넣을 것:**

```zig
    /// 그릴 것이 있는 셀을 out에 채워 반환한다. out은 최소 cols*rows
    /// 크기여야 안전하다.
    ///
    /// **글자가 없어도 색이 있으면 내보낸다**(design 결정 3). 배경색이
    /// 생긴 뒤로는 빈 셀도 그릴 것이 있기 때문이다 — `ls` 출력의 색 띠,
    /// 커서 자리, 그리고 나중의 선택 영역이 그렇다.
    pub fn cells(self: *Screen, out: []CellGlyph) ![]CellGlyph {
        // update()는 beginUpdate() + endUpdate()다(`render.zig:326`).
        // 셀별 style은 endUpdate에서 채워지므로 이 호출 뒤에 읽어도 된다.
        try self.state.update(self.alloc, &self.term);

        const colors = &self.state.colors;
        const default_fg = packRgb(colors.foreground);
        const default_bg = packRgb(colors.background);
        const cursor = self.state.cursor.viewport;

        var n: usize = 0;
        const row_data = self.state.row_data.slice();
        const row_cells = row_data.items(.cells);
        for (0..self.state.rows) |y| {
            const cells_slice = row_cells[y].slice();
            const raws = cells_slice.items(.raw);
            const styles = cells_slice.items(.style);
            for (0..self.state.cols) |x| {
                if (n >= out.len) return out[0..n];

                const raw = raws[x];
                const cp = raw.codepoint();

                var fg = default_fg;
                var bg = default_bg;

                // style_id가 기본값(0, `style.zig:17`의 default_id)일 때
                // style을 읽으면 쓰레기다. 라이브러리가 계약으로 명시한
                // 자리다(`render.zig:260-262`).
                if (raw.style_id != 0) {
                    const st = styles[x];
                    fg = packRgb(st.fg(.{
                        .default = colors.foreground,
                        .palette = &colors.palette,
                        // bold를 밝은 색으로 바꾸는 일을 라이브러리가 대신
                        // 해 준다(`style.zig:172-181`). 폰트가 하나뿐이라
                        // 굵은 자체가 없는 우리에게는 이것이 유일한 길이다.
                        .bold = .bright,
                    }));
                    // null이 "기본 배경"이라는 뜻이다(`style.zig:120`).
                    if (st.bg(&raw, &colors.palette)) |b| bg = packRgb(b);
                    // inverse는 아무도 처리해 주지 않는다 — fg()도 bg()도
                    // 이 플래그를 안 본다.
                    if (st.flags.inverse) std.mem.swap(u32, &fg, &bg);
                }

                // 커서는 inverse와 **같은 연산**이다(design 결정 2). 그래서
                // 렌더러는 커서라는 것도 배우지 않는다. 뷰포트 밖으로
                // 나가면 viewport가 null이므로 TR-M2가 이 자리를 다시
                // 손대지 않아도 된다.
                if (cursor) |vp| {
                    if (@as(usize, vp.x) == x and @as(usize, vp.y) == y) {
                        std.mem.swap(u32, &fg, &bg);
                    }
                }

                // 그릴 글자도 없고 칠할 색도 기본인 셀만 건너뛴다.
                if (cp == 0 and bg == default_bg) continue;

                out[n] = .{
                    .codepoint = @intCast(cp),
                    .col = @intCast(x),
                    .row = @intCast(y),
                    .fg = fg,
                    .bg = bg,
                };
                n += 1;
            }
        }
        return out[0..n];
    }

    /// 기본 전경/배경을 프레임버퍼 형식으로 돌려준다.
    ///
    /// `main.zig`가 같은 상수를 다시 적지 않게 하려고 여기서 내보낸다.
    /// 로그 문구가 두 곳에 중복되어 어긋난 사고가 이 저장소에 이미 있었고
    /// (`HANDOFF.md`), 색 상수도 같은 함정이다 — `init`이 Terminal에 넣은
    /// 값을 `RenderState`가 되돌려준 것이므로 이쪽이 언제나 실제로 쓰이는
    /// 값이다.
    ///
    /// **`cells()` 뒤에 부를 것.** `state.colors`는 `update()`가 채운다.
    pub fn defaultFg(self: *const Screen) u32 {
        return packRgb(self.state.colors.foreground);
    }

    pub fn defaultBg(self: *const Screen) u32 {
        return packRgb(self.state.colors.background);
    }
```

- [ ] **Step 6: 결정 3이 깨뜨리는 기존 검사 하나를 고친다**

`vt_test.zig`의 **셋째 검사(화면 지우기)가 이 변경으로 깨진다.** 지금은 화면을
지우면 셀이 하나도 안 남는다고 단언하는데, 결정 3 뒤로는 **커서 셀이 남는다** —
글자는 없지만 색이 반전되어 있어 기본 배경과 다르기 때문이다. 이것은 회귀가
아니라 결정 3이 의도한 결과다.

`terminal/src/vt_test.zig`의 현재 `:41-46`이 이렇다.

**지울 것:**

```zig
    const third = try screen.cells(&buf);
    std.debug.print("after split escape (clear): {d} cells\n", .{third.len});
    if (third.len != 0) {
        std.debug.print("FAIL: expected screen to be cleared\n", .{});
        return error.SplitEscapeNotHandled;
    }
```

**넣을 것:**

```zig
    const third = try screen.cells(&buf);
    std.debug.print("after split escape (clear): {d} cells\n", .{third.len});
    // TR-M0 전까지 이 단언은 `third.len != 0`이었다. 결정 3 뒤로는 **커서
    // 셀 하나가 남는다** — 글자는 없지만 색이 반전되어 기본 배경과 다르기
    // 때문이다. 회귀가 아니라 의도한 결과이고, 그래서 "글자가 하나도
    // 안 남았는가"로 조건을 옮긴다.
    if (third.len != 1) {
        std.debug.print("FAIL: expected only the cursor cell to remain\n", .{});
        return error.SplitEscapeNotHandled;
    }
    if (third[0].codepoint != 0) {
        std.debug.print("FAIL: a glyph survived the clear (cp={d})\n", .{third[0].codepoint});
        return error.SplitEscapeNotHandled;
    }
```

- [ ] **Step 7: 검사가 통과하는지 본다**

Claude가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && zig build test' 2>&1 | tail -25
```

기대 출력:

```
after split escape (clear): 1 cells
vt_test: 스타일을 가진 적 없는 셀 OK
vt_test: SGR 31 빨강 전경 OK
vt_test: SGR 41 빨강 배경 OK
vt_test: SGR 1;31 bold는 밝게 OK
vt_test: SGR 7 inverse는 맞바꾼다 OK
vt_test: truecolor OK
vt_test: SGR 0 뒤의 셀 OK
PASS
```

**기존 세 검사도 통과해야 한다.** `after 1st feed` / `after 2nd feed`의 셀
개수는 **커서 셀 하나만큼 늘어난다** — 커서가 빈 자리에 있으면 이제 그 셀이
결과에 들어오기 때문이다. 그 둘을 보는 단언은 `second.len <= first.len`
(늘어나기만 하면 된다) 하나뿐이라 개수가 함께 늘어도 영향이 없다. 화면
지우기 검사는 Step 6에서 고쳤다.

- [ ] **Step 8: 커밋**

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig
git commit -m "Resolve every cell to two colors before the renderer sees it"
```

---

## Task 4: 렌더러가 두 색을 칠한다

**Files:**
- Modify: `terminal/src/main.zig` (상수 `:17-22`, `drawGlyph` `:24-36`,
  `render` `:38-54`, `main`의 첫 화면 지우기 `:76-82`, 루프 앞 변수 선언과
  `:225-228`의 렌더 호출부)

design 결정 1·4·5·6과 위험 2.

- [ ] **Step 1: 상수와 `drawGlyph`를 고친다**

`terminal/src/main.zig`의 현재 `:17-36`이 이렇다.

**지울 것:**

```zig
const BACKGROUND: u32 = 0x00102030;
const TEXT_COLOR: u32 = 0x00FFFFFF;
const GRID_X: u32 = 20;
const GRID_Y: u32 = 20;
const CELL_W: u32 = 8; // 8x4x4-fonts의 라틴 글리프 폭(font.zig:19-22 참고)
const ROW_HEIGHT: u32 = 16;

fn drawGlyph(fb: drm.Framebuffer, glyph: font.Glyph, x: u32, y: u32) void {
    const bitmap = glyph.bitmap orelse return;
    var row: u32 = 0;
    while (row < glyph.height) : (row += 1) {
        var col: u32 = 0;
        while (col < glyph.width) : (col += 1) {
            const coverage = bitmap[row * glyph.width + col];
            if (coverage > 127) {
                fb.setPixel(x + col, y + row, TEXT_COLOR);
            }
        }
    }
}
```

**넣을 것:**

```zig
// 화면 여백을 칠할 색. 셀의 배경색은 이제 상수가 아니라 vt.zig가 셀마다
// 확정해서 넘긴다(design 결정 1·5) — 이 상수는 격자 **바깥**에만 쓴다.
const MARGIN_COLOR: u32 = 0x00102030;
const GRID_X: u32 = 20;
const GRID_Y: u32 = 20;
const CELL_W: u32 = 8; // 8x4x4-fonts의 라틴 글리프 폭(font.zig:19-22 참고)
const ROW_HEIGHT: u32 = 16;

/// 한 셀의 배경을 칠한다. 글리프보다 **먼저** 전부 칠해야 한다
/// (design 결정 6) — 글자가 셀 경계를 넘을 수 있어서, 섞어 그리면 다음
/// 셀의 배경이 앞 글자의 삐져나온 획을 지운다.
fn drawCellBackground(fb: drm.Framebuffer, x: u32, y: u32, color: u32) void {
    var row: u32 = 0;
    while (row < ROW_HEIGHT) : (row += 1) {
        var col: u32 = 0;
        while (col < CELL_W) : (col += 1) {
            fb.setPixel(x + col, y + row, color);
        }
    }
}

/// 알파 블렌딩을 하지 않고 문턱값으로 찍는다(design 결정 4). 8x4x4 폰트를
/// 자기 native 크기인 16px로 굽는 것이라 coverage가 이미 거의 이분값이고,
/// 무엇보다 **문턱값이어야 게이트의 픽셀 검사가 정확한 상수와 비교할 수
/// 있다.** 블렌딩하면 기대 픽셀 값이 래스터라이저의 안티앨리어싱에 매달린다.
fn drawGlyph(fb: drm.Framebuffer, glyph: font.Glyph, x: u32, y: u32, color: u32) void {
    const bitmap = glyph.bitmap orelse return;
    var row: u32 = 0;
    while (row < glyph.height) : (row += 1) {
        var col: u32 = 0;
        while (col < glyph.width) : (col += 1) {
            const coverage = bitmap[row * glyph.width + col];
            if (coverage > 127) {
                fb.setPixel(x + col, y + row, color);
            }
        }
    }
}
```

- [ ] **Step 2: `render`를 두 벌로 나눈다**

`terminal/src/main.zig`의 현재 `render` 함수 전체(`:38-54`, 주석 포함)가 이렇다.

**지울 것:**

```zig
/// 화면 전체를 지우고 셀 목록을 다시 그린다. 키 입력 빈도에서 부분 갱신은
/// 불필요한 복잡도다(YAGNI).
fn render(fb: drm.Framebuffer, cache: font.GlyphCache, cells: []const vt.CellGlyph) !void {
    fb.fill(BACKGROUND);
    for (cells) |cell| {
        // x를 글리프 폭으로 누적하지 않고 col로 계산하는 것이 중요하다.
        // libghostty-vt는 한글 같은 폭 2칸 문자 뒤에 spacer 셀을 넣어 col을
        // 이미 맞춰두기 때문에(TF-M2에서 '이'의 col이 6이 아니라 7이었던
        // 그 성질), col*CELL_W가 곧 정확한 픽셀 위치다.
        const x = GRID_X + @as(u32, cell.col) * CELL_W;
        const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
        if (font.find(cache, cell.codepoint)) |glyph| {
            drawGlyph(fb, glyph, x, y);
        }
    }
    try fb.present();
}
```

**넣을 것:**

```zig
/// 화면 전체를 지우고 셀 목록을 다시 그린다. 키 입력 빈도에서 부분 갱신은
/// 불필요한 복잡도다(YAGNI) — `RenderState`가 dirty를 주지만 쓰지 않는다.
///
/// **두 벌로 나눠 그린다**(design 결정 6). 배경을 전부 칠하고 나서 글리프를
/// 전부 그린다. 섞으면 다음 셀의 배경이 앞 글자의 삐져나온 획을 지운다.
fn render(fb: drm.Framebuffer, cache: font.GlyphCache, cells: []const vt.CellGlyph) !void {
    // 여백(격자 바깥)만 상수로 칠한다. 격자 안은 아래에서 셀마다 덮는다.
    fb.fill(MARGIN_COLOR);

    // x를 글리프 폭으로 누적하지 않고 col로 계산하는 것이 중요하다.
    // libghostty-vt는 한글 같은 폭 2칸 문자 뒤에 spacer 셀을 넣어 col을
    // 이미 맞춰두기 때문에(TF-M2에서 '이'의 col이 6이 아니라 7이었던
    // 그 성질), col*CELL_W가 곧 정확한 픽셀 위치다.
    for (cells) |cell| {
        const x = GRID_X + @as(u32, cell.col) * CELL_W;
        const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
        drawCellBackground(fb, x, y, cell.bg);
    }

    for (cells) |cell| {
        const x = GRID_X + @as(u32, cell.col) * CELL_W;
        const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
        if (font.find(cache, cell.codepoint)) |glyph| {
            drawGlyph(fb, glyph, x, y, cell.fg);
        }
    }

    try fb.present();
}
```

- [ ] **Step 3: `main`의 첫 화면 지우기를 고친다**

Task 1이 넣은 임시 확인 줄을 지우고 상수 이름을 맞춘다. 현재 `:76-82` 언저리가
이렇다.

**지울 것:**

```zig
    const fb = try drm.open(allocator, "/dev/dri/card0");
    fb.fill(BACKGROUND);
    try fb.present();
    // Task 1 임시 확인 — design 위험 4. Task 6에서 진짜 로그로 바뀐다.
    std.debug.print("terminal: probe> wrote {X:0>6} read {X:0>6}\n", .{
        BACKGROUND, fb.getPixel(100, 100) & 0x00FFFFFF,
    });
```

**넣을 것:**

```zig
    const fb = try drm.open(allocator, "/dev/dri/card0");
    fb.fill(MARGIN_COLOR);
    try fb.present();
```

- [ ] **Step 4: 첫 프레임의 렌더 시간을 잰다**

design 위험 2가 "재는 것을 TR-M0의 일로 남긴다"고 적어 둔 자리다. 셀마다
배경을 칠하면 픽셀 쓰기가 늘어나는데, 1280×800 = 102만 픽셀이라 얼마나 드는지
숫자가 없다.

**Zig 0.16에는 `std.time.Timer`가 없다.** 시간은 `std.Io`를 거친다
(plan을 쓰면서 컨테이너에서 확인했다). 단조 시계의 이름은 `.awake`다.

먼저 `terminal/src/main.zig`의 현재 `:175-177` 언저리, 루프 **앞의** 변수
선언들이 이렇다.

**지울 것:**

```zig
    var key_state: input.State = .{};
```

**넣을 것:**

```zig
    // 첫 프레임만 잰다. 매 프레임 찍으면 로그가 시끄럽고, 첫 프레임이 가장
    // 비싼 경우(폰트 캐시도 페이지도 차갑다)라 상한을 본다.
    var first_frame_timed = false;
    var key_state: input.State = .{};
```

그리고 루프 안의 현재 `:225-228`이 이렇다.

**지울 것:**

```zig
            screen.feed(out);
            const cells = try screen.cells(cell_buf);
            try render(fb, cache, cells);
            dumpScreen(cells);
```

**넣을 것:**

```zig
            screen.feed(out);
            const cells = try screen.cells(cell_buf);
            const frame_start = std.Io.Clock.now(.awake, init.io);
            try render(fb, cache, cells);
            if (!first_frame_timed) {
                first_frame_timed = true;
                std.debug.print("terminal: render> first frame {d}us\n", .{
                    @divTrunc(frame_start.untilNow(init.io, .awake).nanoseconds, 1000),
                });
            }
            dumpScreen(cells);
```

- [ ] **Step 5: 빌드하고 부팅한다**

Claude가 실행한다(약 1분 30초).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash device/check.sh 2>&1 | rg 'render> first frame|HD-M2 PASS|FAIL'
```

기대:

```
terminal: render> first frame <N>us
HD-M2 PASS: the guest switched itself off because someone pressed the power button
```

**화면은 아직 눈으로 볼 수 없지만**, 이 체인이 통과한다는 것은 렌더러가 죽지
않고 프롬프트를 그렸다는 뜻이다(체인이 `terminal: screen>`을 기다린다).

**`<N>`을 기억 파일에 적는다.** 키 입력 빈도(사람 손으로 초당 십수 번)에서
한 프레임이 수십 밀리초를 넘기면 부분 갱신을 다시 논의할 이유가 생긴다.
그 미만이면 design이 내린 YAGNI 판단이 유지된다.

- [ ] **Step 6: 커밋**

```bash
git add terminal/src/main.zig
git commit -m "Paint each cell with the colors it asked for"
```

---

## Task 5: 블록 커서

**Files:**
- Test: `terminal/src/vt_test.zig`

구현 파일은 안 건드린다. **커서는 Task 3에서 이미 구현됐다.** `cells()`가 커서 자리의 두 색을 맞바꾸고,
결정 3이 빈 셀도 내보내므로 커서 셀이 렌더러에 도착한다. 이 Task는 그것이
실제로 화면에 나타나는지 **확인**하는 자리다 — 코드를 안 고치고 넘어가면
"구현했다고 생각했는데 안 보인다"를 나중에 발견하게 된다.

- [ ] **Step 1: 커서 셀이 결과에 들어오는지 호스트에서 확인한다**

`terminal/src/vt_test.zig`의 마지막 `std.debug.print("PASS\n", .{});` **앞에**
아래를 넣는다.

**넣을 것:**

```zig

    // ── TR-M0: 커서 ───────────────────────────────────────────────────
    //
    // 커서는 inverse와 같은 연산이라 코드가 따로 없다(design 결정 2). 대신
    // "그 셀이 결과에 들어오는가"를 여기서 못박는다 — 결정 3(빈 셀도
    // 내보낸다)이 없으면 커서가 빈 자리에 있을 때 조용히 사라진다.
    screen.feed("\x1b[2J\x1b[H");
    screen.feed("XY");
    const with_cursor = try screen.cells(&buf);

    // 커서는 'Y' 다음 칸(col=2, row=0)에 있고 글자가 없다. 기본 색이
    // 맞바뀌어 fg=#102030 bg=#FFFFFF여야 한다.
    var cursor_found = false;
    for (with_cursor) |cell| {
        if (cell.row != 0 or cell.col != 2) continue;
        cursor_found = true;
        if (cell.codepoint != 0 or cell.fg != 0x102030 or cell.bg != 0xFFFFFF) {
            std.debug.print(
                "FAIL: 커서 셀이 cp={d} fg=#{X:0>6} bg=#{X:0>6} (expected cp=0 fg=#102030 bg=#FFFFFF)\n",
                .{ cell.codepoint, cell.fg, cell.bg },
            );
            return error.WrongCursorCell;
        }
        std.debug.print("vt_test: 커서 셀이 반전되어 결과에 들어온다 OK\n", .{});
        break;
    }
    if (!cursor_found) {
        std.debug.print("FAIL: 커서 자리(row=0,col=2) 셀이 결과에 없다\n", .{});
        return error.CursorCellMissing;
    }
```

- [ ] **Step 2: 검사를 돌린다**

Claude가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && zig build test' 2>&1 | tail -15
```

기대 출력에 이 줄이 있어야 한다.

```
vt_test: 커서 셀이 반전되어 결과에 들어온다 OK
PASS
```

- [ ] **Step 3: 커밋**

```bash
git add terminal/src/vt_test.zig
git commit -m "Pin down that the cursor cell survives into the draw list"
```

---

## Task 6: `style>` · `pixel>` 로그 두 줄

**Files:**
- Modify: `terminal/src/main.zig` (`dumpScreen` `:56-71`, 호출부 `:226-228`)

design 결정 7. **여기서 찍히는 문구가 Task 8의 게이트가 grep할 문구다.**

- [ ] **Step 1: `dumpScreen`이 NUL을 안 뱉게 고치고 색 덤프를 더한다**

`terminal/src/main.zig`의 현재 `dumpScreen` 함수 전체(`:56-71`, 주석 포함)가
이렇다.

**지울 것:**

```zig
/// 검증용으로 화면 내용을 serial 콘솔에 한 줄로 덤프한다.
/// check.sh가 이 줄을 grep해서 "입력이 실제로 셸을 움직였는가"를 판단한다.
fn dumpScreen(cells: []const vt.CellGlyph) void {
    std.debug.print("terminal: screen> ", .{});
    var last_row: u16 = 0;
    for (cells) |cell| {
        if (cell.row != last_row) {
            std.debug.print(" | ", .{});
            last_row = cell.row;
        }
        var utf8: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(cell.codepoint), &utf8) catch continue;
        std.debug.print("{s}", .{utf8[0..len]});
    }
    std.debug.print("\n", .{});
}
```

**넣을 것:**

```zig
/// 한 프레임에 찍는 style/pixel 줄의 상한. 화면 전체에 색이 깔린 프로그램이
/// 돌면 셀 수천 개가 매 프레임 로그로 쏟아진다. 게이트가 검사에 쓰는 셀은
/// 한 줄 안의 몇 개라 이만큼이면 넉넉하다.
const STYLE_DUMP_LIMIT: usize = 16;

/// 검증용으로 화면 내용을 serial 콘솔에 한 줄로 덤프한다.
/// check.sh가 이 줄을 grep해서 "입력이 실제로 셸을 움직였는가"를 판단한다.
///
/// **이 줄의 형식은 바꾸지 않는다.** 여섯 체인 중 다섯(TF·CP·IP·PM·HD)이
/// `terminal: screen>.*` 형태로 이 줄을 보고 화면을 판정한다. 색은 여기
/// 섞지 않고 아래 dumpStyles가 별도의 줄로 낸다(design 결정 7).
fn dumpScreen(cells: []const vt.CellGlyph) void {
    std.debug.print("terminal: screen> ", .{});
    var last_row: u16 = 0;
    for (cells) |cell| {
        if (cell.row != last_row) {
            std.debug.print(" | ", .{});
            last_row = cell.row;
        }
        // 글자 없는 셀도 이제 여기 도착한다(vt.zig의 design 결정 3).
        // 걸러내지 않으면 utf8Encode(0)이 NUL 바이트를 만들어 로그 줄에
        // 섞인다.
        if (cell.codepoint == 0) continue;
        var utf8: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(cell.codepoint), &utf8) catch continue;
        std.debug.print("{s}", .{utf8[0..len]});
    }
    std.debug.print("\n", .{});
}

/// 기본 색과 다른 셀을 두 줄씩 찍는다 — 파서가 본 색과, 프레임버퍼에서
/// 되읽은 실제 픽셀이다(design 결정 7).
///
/// 두 겹인 이유는 HD-M2가 잡은 "조용한 실패"와 같은 종류의 구멍을 막기
/// 위해서다. `style>`만 찍으면 파서가 옳고 렌더러가 틀렸을 때 게이트가
/// 통과한다. `pixel>`만 찍으면 실패는 잡히지만 어느 단계에서 틀어졌는지를
/// 따로 조사해야 한다.
///
/// **반드시 render() 뒤에 불러야 한다.** 그 전에 부르면 이전 프레임의
/// 픽셀을 읽는다.
fn dumpStyles(
    fb: drm.Framebuffer,
    cells: []const vt.CellGlyph,
    default_fg: u32,
    default_bg: u32,
) void {
    var shown: usize = 0;
    var skipped: usize = 0;
    for (cells) |cell| {
        if (cell.fg == default_fg and cell.bg == default_bg) continue;
        if (shown >= STYLE_DUMP_LIMIT) {
            skipped += 1;
            continue;
        }
        shown += 1;
        std.debug.print("terminal: style> {d},{d} fg={X:0>6} bg={X:0>6}\n", .{
            cell.row, cell.col, cell.fg, cell.bg,
        });
        // 셀의 **중앙**을 읽는다. 모서리는 이웃 셀과의 경계라 off-by-one에
        // 취약하다.
        const px = GRID_X + @as(u32, cell.col) * CELL_W + CELL_W / 2;
        const py = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT + ROW_HEIGHT / 2;
        std.debug.print("terminal: pixel> {d},{d} = {X:0>6}\n", .{
            cell.row, cell.col, fb.getPixel(px, py) & 0x00FFFFFF,
        });
    }
    // 조용히 자르면 "색이 없다"와 "너무 많아서 안 찍었다"를 가를 수 없다.
    if (skipped > 0) {
        std.debug.print("terminal: style> {d} more cell(s) not shown\n", .{skipped});
    }
}
```

- [ ] **Step 2: 호출부를 고친다**

Task 4가 이 근처를 이미 고쳤으므로, **`dumpScreen(cells);` 한 줄만 앵커로
쓴다.** 그 줄은 파일에 한 번만 나온다.

**지울 것:**

```zig
            dumpScreen(cells);
```

**넣을 것:**

```zig
            dumpScreen(cells);
            // render 뒤에 부른다 — 그 전에 부르면 이전 프레임의 픽셀을 읽는다.
            // 기본 색을 여기 상수로 다시 적지 않고 screen에서 얻는 이유는
            // vt.zig의 defaultFg 주석에 있다.
            dumpStyles(fb, cells, screen.defaultFg(), screen.defaultBg());
```

- [ ] **Step 3: 부팅해서 실제 문구를 본다**

Claude가 실행한다(약 1분 30초). **이 단계의 목적은 통과가 아니라 문구 확인이다.**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash device/check.sh 2>&1 | rg 'terminal: (style|pixel)>' | head -20
```

기대: fish 프롬프트가 색을 쓰므로 `style>`과 `pixel>` 줄이 나온다. 각
`style>` 줄마다 같은 `r,c`의 `pixel>` 줄이 바로 뒤에 온다.

**둘의 색이 다르면 렌더러가 틀린 것이다.** 특히 글자가 있는 셀은 중앙 픽셀이
글리프의 획일 수 있어 `fg` 값이 나올 수 있다 — 그것은 정상이다. 게이트가
**공백 셀**을 쓰는 이유가 이것이다(이번에 정하는 것 2번).

- [ ] **Step 4: 커밋**

```bash
git add terminal/src/main.zig
git commit -m "Log the color we parsed next to the pixel we actually wrote"
```

---

## Task 7: `TERM=xterm-256color`와 기존 여섯 체인 회귀

**Files:**
- Modify: `terminal/src/main.zig` (`:135-151`의 주석과 `setenv`)

design 결정 8. **이 milestone에서 가장 큰 회귀 위험이다**(design 위험 1).

- [ ] **Step 1: `TERM`을 바꾼다**

`terminal/src/main.zig`의 현재 `:148-151`이 이렇다.

**지울 것:**

```zig
    // xterm-256color가 아니라 xterm인 이유는 우리가 아직 색을 하나도 그리지
    // 않기 때문이다(TEXT_COLOR 상수 하나). 256색을 광고하면 반대 방향의
    // 거짓말이 된다.
    _ = setenv("TERM", "xterm", 1);
```

**넣을 것:**

```zig
    // TR-M0부터 xterm-256color다. 그전에는 "우리가 색을 하나도 그리지 않아서"
    // xterm이었는데, 이제 팔레트 256색과 truecolor를 전부 칠하므로 xterm이라고
    // 말하는 쪽이 거짓말이 된다(design 결정 8).
    _ = setenv("TERM", "xterm-256color", 1);
```

- [ ] **Step 2: 루트 게이트를 돌린다**

Claude가 실행한다. **약 37분 걸린다.**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh > /tmp/tr-m0-regression.log 2>&1; echo "EXIT=$?"
rg -n 'PASS: 3/3|FAIL' /tmp/tr-m0-regression.log
```

기대 출력:

```
BF-M4 PASS: 3/3 consecutive runs succeeded
TF-M4 PASS: 3/3 consecutive runs succeeded
CP-M2 PASS: 3/3 consecutive runs succeeded
IP-M2 PASS: 3/3 consecutive runs succeeded
PM-M1 PASS: 3/3 consecutive runs succeeded
HD-M2 PASS: 3/3 consecutive runs succeeded
```

**실패하면 여기서 멈춘다.** 가장 그럴듯한 원인은 `TERM` 변경으로 프롬프트나
셸 출력의 시퀀스가 달라져 `terminal: screen>.*` 검사가 어긋난 것이다. 그
경우 실패한 체인의 `screen>` 줄을 실제로 읽어 무엇이 달라졌는지 먼저 본다 —
검사를 고칠 것인지 `TERM`을 되돌릴 것인지는 그 내용을 보고 정한다.

- [ ] **Step 3: 커밋**

```bash
git add terminal/src/main.zig
git commit -m "Stop calling ourselves xterm now that we draw the colors"
```

---

## Task 8: 새 체인 `render/check.sh`

**Files:**
- Create: `render/check.sh`

design 결정 9. monitor 포트 **45460**.

- [ ] **Step 1: 파일을 만든다**

**100줄이 넘으므로 Claude가 `/tmp/render-check.sh`에 원본을 만들어 `diff`로
보인 뒤, 승인을 받아 `cp`로 제자리에 넣는다**(`CLAUDE.md`의 편집 규칙).

파일 내용은 이렇다.

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# TR 체인 — 색상 렌더링.
#
# 이 게이트가 증명하는 사슬 전체:
#   게스트 셸에 printf '\033[41m \033[0m' 를 타이핑한다
#   → 셸이 그 바이트를 PTY로 뱉는다
#   → libghostty-vt가 SGR 41을 파싱해 셀에 style_id를 붙인다
#   → vt.zig가 Style.bg()로 팔레트 1번(#CC6666)을 뽑아 CellGlyph.bg에 담는다
#   → main.zig가 그 색으로 셀 배경을 칠한다
#   → 프레임버퍼에서 그 픽셀을 되읽어 같은 값이 나온다
#
# **두 겹으로 보는 것이 이 체인의 값이다**(design 결정 7). style> 만 보면
# 파서가 옳고 렌더러가 틀렸을 때 통과한다 — HD-M2가 잡은 "조용한 실패"와
# 같은 종류의 구멍이다.
#
# 검사에 배경색 칠한 **공백**을 쓰는 이유는 셀 전체가 배경색이라 어느 픽셀을
# 읽어도 같기 때문이다. 글자가 있는 셀은 중앙 픽셀이 글리프의 획일 수 있다.
#
# 디스크를 물지 않는다. 색은 설정과 무관하다.

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

# TR-M0부터 이 step이 vt_test까지 돌린다. 색 해석은 전부 여기서 먼저
# 걸러진다 — 부팅 1.5초를 쓰기 전에 0.1초로 잡을 수 있는 실패다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed (input_test or vt_test)"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 45455=TF, 45456=CP, 45457=IP, 45458=PM, 45459=HD. 겹치지 않는 번호를 쓰는
# 이유는 죽다 만 QEMU가 남았을 때 엉뚱한 게스트에 명령을 보내지 않기 위해서다.
MONITOR_PORT=45460

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  exec 3<&- 2>/dev/null
  exec 3>&- 2>/dev/null
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

report_failure() {
  echo "FAIL: $1"
  echo "--- markers ---"
  local marker
  for marker in \
    "terminal: screen>" \
    "terminal: style>" \
    "terminal: pixel>" \
    "terminal: key>"; do
    if grep -q "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- style/pixel lines ---"
  grep -E 'terminal: (style|pixel)>' "$LOG" | tail -n 40
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
  exit 1
}

type_keys() {
  local k
  for k in "$@"; do
    echo "sendkey $k" >&3
    sleep 0.3
  done
}

qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -q "terminal: screen>" "$LOG"; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || report_failure "terminal never rendered a prompt"
sleep 1

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor"

# ── 색을 만든다 ─────────────────────────────────────────────────────────
#
# printf '\033[41m \033[0m\n'
#
# printf는 fish와 bash 양쪽의 빌트인이라 PATH가 비어 있어도 된다
# (project_guest_environment). \e가 아니라 \033을 쓰는 것은 셸마다 \e 지원이
# 갈리기 때문이다.
echo "=== typing printf '\\033[41m \\033[0m\\n' ==="
type_keys p r i n t f spc apostrophe \
  backslash 0 3 3 bracket_left 4 1 m \
  spc \
  backslash 0 3 3 bracket_left 0 m \
  backslash n \
  apostrophe ret
sleep 3

# ── 검사 1: 파서가 빨강 배경을 봤는가 ──────────────────────────────────
#
# 팔레트 1번이 #CC6666이다. xterm 고전값(#CD0000)이 아니라는 것이 요점이다 —
# 2026-08-23에 컨테이너에서 직접 재서 확인했다.
STYLE_LINE="$(grep -E 'terminal: style> [0-9]+,[0-9]+ fg=[0-9A-F]{6} bg=CC6666' "$LOG" | tail -n 1)"
if [ -z "$STYLE_LINE" ]; then
  report_failure "the parser never reported a red background (SGR 41 -> palette[1] = CC6666)"
fi
echo "parser saw the red background: ${STYLE_LINE}"

# 그 셀의 좌표를 뽑는다. 행·열을 게이트에 하드코딩하지 않는 이유는 프롬프트의
# 길이에 따라 출력 줄의 위치가 달라지기 때문이다.
CELL="$(echo "$STYLE_LINE" | sed -E 's/.*style> ([0-9]+,[0-9]+) .*/\1/')"

# ── 검사 2: 렌더러가 그 색을 픽셀로 옮겼는가 ───────────────────────────
#
# **이 체인에서 가장 값진 검사다.** 위의 검사만 있으면 파서가 옳고 렌더러가
# 틀렸을 때 게이트가 통과한다.
if ! grep -q "terminal: pixel> ${CELL} = CC6666" "$LOG"; then
  echo "FAIL: the parser said CC6666 at ${CELL} but the framebuffer says otherwise"
  echo "--- what the framebuffer actually held ---"
  grep "terminal: pixel> ${CELL} =" "$LOG" | tail -n 5
  report_failure "renderer did not paint the background color the parser resolved"
fi
echo "the framebuffer really holds CC6666 at ${CELL}"

# ── 검사 3: 커서가 그려지는가 ──────────────────────────────────────────
#
# 커서는 기본 색을 맞바꾼 셀이다 — fg=102030 bg=FFFFFF. 이 검사가 없으면
# 커서가 조용히 사라져도 아무도 모른다(vt_test는 호스트에서만 본다).
if ! grep -q "terminal: style> [0-9]*,[0-9]* fg=102030 bg=FFFFFF" "$LOG"; then
  report_failure "no inverted cell on screen, so the cursor was never drawn"
fi
echo "the cursor is on screen as an inverted cell"

# ── 음성 검사 ──────────────────────────────────────────────────────────

# 화면 덤프에 NUL이 섞이면 안 된다. 빈 셀이 결과에 들어오기 시작했으므로
# (design 결정 3) dumpScreen이 그것을 안 거르면 utf8Encode(0)이 NUL을 만든다.
#
# `grep -qP '\x00'`을 쓰지 않는다. GNU grep 3.11에서 그것은 NUL이 든 파일에도
# **매치되지 않는다** — 그대로 뒀으면 항상 통과하는 가짜 검사가 된다
# (plan을 쓰면서 컨테이너에서 확인했다). 바이트 수를 세는 쪽은 확실하다.
if [ "$(tr -d '\0' < "$LOG" | wc -c)" -ne "$(wc -c < "$LOG")" ]; then
  report_failure "a NUL byte leaked into the log (dumpScreen did not skip empty cells)"
fi
echo "no NUL bytes in the log"

# 상한에 걸렸다면 게이트가 보는 셀이 잘려나갔을 수 있다. 지금 화면에서
# 16셀을 넘길 일은 없으므로, 넘겼다면 무언가 예상과 다르다.
if grep -q "terminal: style> .* more cell(s) not shown" "$LOG"; then
  report_failure "the style dump hit its limit, so the gate may be reading a truncated view"
fi

if grep -q "Attempted to kill init" "$LOG"; then
  report_failure "init died"
fi

echo "--- style/pixel lines ---"
grep -E 'terminal: (style|pixel)>' "$LOG" | tail -n 20
echo "TR-M0 PASS: the color the parser resolved is the color in the framebuffer"
```

- [ ] **Step 2: 실행 권한을 준다**

Claude가 실행한다.

```bash
chmod +x render/check.sh && ls -l render/check.sh
```

- [ ] **Step 3: 체인을 단독으로 돌린다**

Claude가 실행한다(약 2분).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash render/check.sh 2>&1 | tail -40
```

기대 마지막 줄:

```
TR-M0 PASS: the color the parser resolved is the color in the framebuffer
```

**타이핑한 명령이 셸에 안 먹으면** `parser never reported a red background`로
실패한다. 그때는 `--- last 40 lines ---`에 찍힌 `terminal: screen>` 줄에서
실제로 무엇이 타이핑됐는지 읽고 `type_keys`의 키 이름을 고친다.

- [ ] **Step 4: 커밋**

```bash
git add render/check.sh
git commit -m "Prove the framebuffer holds the color the parser resolved"
```

---

## Task 9: 루트 게이트에 체인을 넣고 3/3

**Files:**
- Modify: `check.sh` (`:88-97` 언저리)

- [ ] **Step 1: 체인을 등록하고 주석을 더한다**

`check.sh`의 현재 `:88-97`이 이렇다.

**지울 것:**

```bash
# HD-M2가 감독 루프를 poll 구조로 바꿨다는 것도 여기 적어 둔다. 그 변경은
# 이 여섯 체인 **전부**가 딛고 선 코드를 건드린 것이라, 앞으로 그 자리를
# 고치는 사람은 HD 체인 하나만 보아서는 안 된다 — BF의 "started terminal
# 정확히 3회"와 PM의 "종료 중 되살리지 않는다"가 그 코드의 진짜 계약이다.
run_chain "BF-M4" ./boot/check.sh
run_chain "TF-M4" ./terminal/check.sh
run_chain "CP-M2" ./config/check.sh
run_chain "IP-M2" ./input/check.sh
run_chain "PM-M1" ./power/check.sh
run_chain "HD-M2" ./device/check.sh
```

**넣을 것:**

```bash
# HD-M2가 감독 루프를 poll 구조로 바꿨다는 것도 여기 적어 둔다. 그 변경은
# 이 체인들 **전부**가 딛고 선 코드를 건드린 것이라, 앞으로 그 자리를
# 고치는 사람은 HD 체인 하나만 보아서는 안 된다 — BF의 "started terminal
# 정확히 3회"와 PM의 "종료 중 되살리지 않는다"가 그 코드의 진짜 계약이다.
#
# TR 체인은 색상 렌더링을 본다. 다른 여섯 체인과 다른 점은 **화면의 픽셀을
# 직접 되읽는다**는 것이다 — 나머지는 전부 로그 문자열만 본다. 게스트에
# printf 한 줄을 타이핑하고, 파서가 뽑은 색(style>)과 프레임버퍼에 실제로
# 들어간 색(pixel>)이 같은지를 대조한다. 회차당 부팅 1회라 총 부팅 횟수는
# 27회에서 30회가 된다.
#
# 이 체인이 더하는 비용의 대부분은 부팅이 아니라 **커널 빌드 3회**(약 2분
# 40초)다. 2026-08-22에 CONFIG_PRINTK_TIME을 켜서 잰 결과 부팅 하나가
# 1.5초라는 것이 밝혀졌다(docs/decisions/project_kernel_config.md).
run_chain "BF-M4" ./boot/check.sh
run_chain "TF-M4" ./terminal/check.sh
run_chain "CP-M2" ./config/check.sh
run_chain "IP-M2" ./input/check.sh
run_chain "PM-M1" ./power/check.sh
run_chain "HD-M2" ./device/check.sh
run_chain "TR-M0" ./render/check.sh
```

- [ ] **Step 2: 루트 게이트를 돌린다**

Claude가 실행한다. **약 40분 걸린다**(일곱 체인).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh > /tmp/tr-m0-root-gate.log 2>&1; echo "EXIT=$?"
rg -n 'PASS: 3/3|FAIL' /tmp/tr-m0-root-gate.log
```

기대 출력:

```
BF-M4 PASS: 3/3 consecutive runs succeeded
TF-M4 PASS: 3/3 consecutive runs succeeded
CP-M2 PASS: 3/3 consecutive runs succeeded
IP-M2 PASS: 3/3 consecutive runs succeeded
PM-M1 PASS: 3/3 consecutive runs succeeded
HD-M2 PASS: 3/3 consecutive runs succeeded
TR-M0 PASS: 3/3 consecutive runs succeeded
```

- [ ] **Step 3: 걸린 시간을 잰다**

Claude가 실행한다. 다음 milestone이 체인 비용을 판단할 근거가 된다.

```bash
stat -f "시작 %SB  끝 %Sm" -t "%H:%M:%S" /tmp/tr-m0-root-gate.log
```

기준선은 여섯 체인에 37분 43초(2026-08-22)다.

- [ ] **Step 4: 커밋**

```bash
git add check.sh
git commit -m "Add the color chain to the root gate"
```

---

## Task 10: 문서

**Files:**
- Modify: `docs/decisions/project_terminal_rendering.md` (새로 만든다)
- Modify: `MEMORY.md`
- Modify: `HANDOFF.md`
- Modify: `docs/superpowers/specs/2026-08-23-tars-terminal-rendering-design.md`
  (실제와 어긋난 곳이 있으면)

**이 Task의 파일은 Claude가 직접 쓴다**(`HANDOFF.md`의 분담표).

- [ ] **Step 1: 기억 파일을 만든다**

`docs/decisions/project_terminal_rendering.md`를 만든다. 최소한 이만큼을 담는다.

- **팔레트가 xterm 고전값이 아니다** — 빨강 `#CC6666`, 밝은 빨강 `#D54E53`.
  게이트가 기대하는 값이 이것이고, 짐작으로 적으면 틀린다.
- **`style_id == 0`이면 `style`을 읽으면 안 된다** — 라이브러리의 계약이고,
  어기면 쓰레기 색이 나온다.
- **`inverse`는 라이브러리가 처리해 주지 않는다** — 커서도 같은 연산이라
  둘 다 `vt.zig`에서 해소한다. 그래서 렌더러는 반전도 커서도 모른다.
- **libghostty-vt는 aarch64에서 돈다** — `build.zig`가 "검증된 적이 없다"고
  적어 둔 채 `vt_test`를 아무도 실행하지 않는 상태로 두 서브프로젝트를
  건너왔다. TR-M0이 그것을 살렸다.
- **문턱값 렌더링은 게이트를 위한 선택이기도 하다** — 블렌딩하면 기대 픽셀
  값이 래스터라이저에 매달린다.
- **빈 셀이 결과에 들어오기 시작했다** — `dumpScreen`이 안 거르면 NUL이 로그에
  샌다. 게이트에 그 음성 검사가 있다.
- **`grep -qP '\x00'`은 NUL을 못 잡는다** — GNU grep 3.11에서 확인했다.
  바이트 수를 세는 쪽(`tr -d '\0' | wc -c`)을 쓴다. 이것을 안 적어 두면
  다음에 누가 또 항상 통과하는 검사를 쓴다.
- **Zig 0.16에는 `std.time.Timer`가 없다** — 시간은 `std.Io.Clock.now(.awake,
  io)`로 얻고 단조 시계의 이름이 `.monotonic`이 아니라 `.awake`다.
- Task 4에서 잰 첫 프레임 렌더 시간과, 그것이 부분 갱신 논의에 어떤 뜻인지.
- Task 9에서 잰 루트 게이트 시간.

- [ ] **Step 2: `MEMORY.md`에 한 줄 더한다**

`## 프로젝트 (project)` 절 끝에 `- [Terminal rendering](docs/decisions/project_terminal_rendering.md) — …` 형태로 한 줄. 본문은 쓰지 않는다.

- [ ] **Step 3: `HANDOFF.md`를 다시 쓴다**

TR-M0이 끝난 상태로 갱신한다. 담을 것은 이렇다.

- TR-M0이 끝났고 다음은 TR-M1(한글)이라는 것
- 일곱 체인, monitor 포트 45455~45460 사용(45461이 빈다), 부팅 30회
- Task 9에서 잰 루트 게이트 시간
- 로그 문구 중복 목록에 `terminal: style>`·`terminal: pixel>` 추가
- 이월 숙제에서 `CONFIG_PRINTK_TIME`을 지운다(2026-08-22에 끝났다)
- plan에서 어긋난 곳

- [ ] **Step 4: 커밋**

```bash
git add docs/decisions/project_terminal_rendering.md MEMORY.md HANDOFF.md \
  docs/superpowers/specs/2026-08-23-tars-terminal-rendering-design.md
git commit -m "Hand off with a terminal that shows its colors"
```

---

## 완료 조건

- [ ] `zig build test`가 색 검사 여덟(셀 일곱 + 커서 하나)을 통과하고,
      기존 세 검사도 통과한다
- [ ] 루트 게이트 **일곱 체인** 3/3
- [ ] `render/check.sh`가 파서의 색과 프레임버퍼의 픽셀이 같음을 증명한다
- [ ] 커서가 화면에 보인다
- [ ] `TERM=xterm-256color`이고 기존 여섯 체인이 안 깨졌다
- [ ] 첫 프레임 렌더 시간을 재서 기록했다(design 위험 2)
- [ ] 기억 파일과 `HANDOFF.md`가 갱신됐다
