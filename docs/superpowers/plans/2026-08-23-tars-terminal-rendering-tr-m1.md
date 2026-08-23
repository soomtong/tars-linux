# TARS Terminal Rendering TR-M1 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 구현 파일 편집은
> 사용자가 하고, 빌드·QEMU·게이트·조사성 명령은 Claude가 실행하며, Claude는 각
> Step의 정확한 내용을 제시하고 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는
> 이 저장소에 적용하지 않는다.

**Goal:** 화면에 한글이 나온다. 폰트 캐시가 "부팅 때 ASCII 95자를 굽는 배열"에서
"처음 쓸 때 구워 넣는 해시 맵"으로 바뀌고, 글리프가 폰트 메트릭이 말하는 자리에
정확히 찍히며, 게이트가 **폭 2칸이 지켜졌다는 것을 프레임버퍼 픽셀로** 증명한다.

**Design doc:** `docs/superpowers/specs/2026-08-23-tars-terminal-rendering-design.md`
(TR-M1 절과 위험 3이 이 milestone의 몫이다. 결정 10~13은 TR-M2다. design은
승인되어 있으므로 다시 논의하지 않는다.)

**Tech Stack:** Zig 0.16, stb_truetype, DRM dumb buffer(`MAP_SHARED`),
libghostty-vt(폭 2칸 spacer 셀), QEMU monitor `sendkey`, bash 게이트 스크립트

---

## 착수 전에 이미 확정된 사실 (2026-08-23 실측)

**plan을 쓰면서 컨테이너에서 직접 재서 확인한 값들이다. 다시 조사하지 않는다.**
저장소는 건드리지 않고 컨테이너 안에서만 임시 C 프로그램을 만들어 vendor된
`stb_truetype.h`와 `vendor/fonts/Hanme_8x4x4.ttf`로 쟀다. 폰트의 `cmap`은
호스트에서 Python으로 직접 파싱했다.

### 1. 폰트가 담고 있는 것

| 범위 | 있는 글자 수 |
|---|---|
| ASCII 출력 가능(U+0020~U+007E) | 95 / 95 |
| 라틴 확장(U+00A0~U+024F) | 75 / 432 |
| **한글 음절(U+AC00~U+D7A3)** | **11172 / 11172** |
| **조합용 자모(U+1100~U+11FF)** | **64** (초 18/19 · 중 20/21 · 종 26/27) |
| **호환 자모(U+3131~U+3163, `ㄱ`·`ㅏ`)** | **0 / 51** |
| **한자(U+4E00~U+9FFF)** | **0 / 20992** |

> **2026-08-23 정정.** 이 자리에는 원래 "완성형 한글은 하나도 빠짐없이 있고,
> 낱자와 한자는 아예 없다. 나중에 IME를 붙이면 조합 중인 낱자를 이 폰트로 못
> 그린다"고 적혀 있었다. **표의 `64 / 256`을 본문이 반대로 읽은 것이다.**
> 호환 자모는 정말로 0이지만 조합용 자모가 64자 있어서, `ㄱ`을 U+1100으로
> 바꿔 그리면 나온다. 다시 재서 확인한 내용은 아래와
> `docs/decisions/project_font_jamo_coverage.md`에 있다.

**완성형 한글은 하나도 빠짐없이 있다.** 호환 자모(`ㄱ` U+3131)를 그대로 찍으면
아무것도 안 나오지만, **조합용 자모(`ᄀ` U+1100)로 바꿔 찍으면 나온다.** 빠진
것은 각 구간의 마지막 하나씩인 `ᄒ`(U+1112) · `ᅵ`(U+1175) · `ᇂ`(U+11C2)뿐이라
호환 자모 51자 중 **49자를 대체할 수 있다.** 남는 둘(`ㅎ`·`ㅣ`)도 완성형에서
픽셀로 되뽑을 수 있다는 것을 검산까지 마쳤다(`하`−`ᅡ` = `ᄒ`, `이`−`ᄋ` = `ᅵ`,
`읗`의 아래 여섯 행 = `ᇂ`).

한자는 정말로 없다.

**이 milestone에서 낱자를 그리지는 않는다.** 입력 경로에 한글 IME가 없어서
지금 필요한 것이 아니고, TR-M1의 목표는 완성형이 화면에 나오는 것이다. 위
사실은 **IME를 붙일 때 무엇을 하면 되는지가 이미 정해져 있다**는 기록이다.

`unitsPerEm`이 1600이고 `ascent=1600`, `descent=0`, `lineGap=0`이다. 16픽셀로
구우면 `scale`이 정확히 0.01이라 **글리프 격자가 픽셀 격자와 정확히 맞는다.**

### 2. 글리프가 실제로 구워지는 모양

```
A              U+0041  7x10  xoff=0 yoff=-14  ink=39  partial=0  advance=8.00px
g (디센더)     U+0067  7x10  xoff=0 yoff=-11  ink=40  partial=0  advance=8.00px
space          U+0020  0x0   xoff=0 yoff=0    ink=0   partial=0  advance=8.00px
한             U+D55C 15x15  xoff=1 yoff=-16  ink=64  partial=0  advance=16.00px
글             U+AE00 13x14  xoff=2 yoff=-15  ink=63  partial=0  advance=16.00px
가             U+AC00 13x13  xoff=3 yoff=-15  ink=46  partial=0  advance=16.00px
힣             U+D7A3 14x15  xoff=1 yoff=-16  ink=72  partial=0  advance=16.00px
이             U+C774 11x13  xoff=3 yoff=-15  ink=50  partial=0  advance=16.00px
é              U+00E9  7x10  xoff=1 yoff=-14  ink=33  partial=0  advance=8.00px
한자 U+4E00    glyph_index=0  0x0  advance=0.00px
ㄱ   U+3131    glyph_index=0  0x0  advance=0.00px
```

여기서 나오는 사실이 넷이다.

**(가) `partial=0`이다.** coverage가 0 아니면 255뿐이고 그 사이 값이 **하나도**
없다. 16픽셀이 8x4x4의 native 크기라 안티앨리어싱이 아예 일어나지 않는다.
design 결정 4가 "거의 이분값이다"라고 짐작한 자리인데, 실제로는 완전한
이분값이다. 게이트의 픽셀 검사가 정확한 상수와 비교해도 되는 근거가 이것이다.

**(나) `yoff`가 글자마다 다르고 편차가 5픽셀이다.** `g`가 -11이고 `한`이
-16이다. **지금 `drawGlyph`는 이 값을 통째로 버리고 셀 모서리부터 그린다**
(`main.zig:42-54`). 그래서 지금 화면에서 `g`의 디센더가 사라지고 있다. 라틴만
있을 때는 편차가 3픽셀이라 티가 덜 났지만, 한글이 들어오면 라틴보다 위로 솟는다.

`yoff`는 baseline 기준이므로 `ascent_px`(= 16)를 더하면 셀 위쪽 모서리 기준이
된다. 그 값이 전부 0 이상이고 `y_offset + height`가 전부 16 이하다.

| 글자 | `ascent_px + yoff` | 높이 | 셀 안에서 차지하는 행 |
|---|---|---|---|
| A | 2 | 10 | 2~11 |
| g | 5 | 10 | 5~14 (디센더가 아래로) |
| 한 | 0 | 15 | 0~14 |
| 가 | 1 | 13 | 1~13 |

**전부 16픽셀 셀 안에 들어간다.** 즉 오프셋을 반영해도 셀 밖으로 새지 않는다.

**(다) `advance`가 라틴 8.00, 한글 16.00으로 정확하다.** `font.zig:19-22`의
`cellWidth`가 "0x7F를 넘으면 16"이라고 판정하는데 **`é`에서 틀린다** —
advance가 8인 글자를 16으로 본다. 폰트에서 가져오면 틀릴 일이 없다. 다만 지금
`Glyph.cell_width`는 `font_test.zig`만 출력하고 렌더러는 읽지 않는 **죽은
필드**라, 이 오류가 화면에 나타난 적은 없다.

**(라) 폰트에 없는 글자는 `glyph_index=0`에 `0x0` 비트맵이고 `advance=0`이다.**
에러가 아니라 조용한 정상 반환이다. 공백(`U+0020`)도 `0x0` 비트맵이라
**"폰트에 없다"와 "잉크가 없다"가 구분되지 않는다.** 구분할 이유도 없다 —
어느 쪽이든 그릴 것이 없다.

### 3. 전부 굽는 비용

한글 음절 11172자를 전부 구우면 **비트맵 합계 2,157,133바이트(2.06MB)이고
29.3밀리초**가 든다. 한 자당 193바이트, 0.003밀리초다. 빈 비트맵은 하나도 없다.

**design 위험 3이 여기서 닫힌다.** "수십 KB일 것으로 보지만 128MB 게스트라
실측한다"고 남긴 자리인데, **최악의 경우가 2.06MB다.** 화면에 실제로 나오는
글자는 수십 자이므로 실사용에서는 그보다 두 자릿수 적다. 메모리는 위험이 아니다.

**그런데도 lazy 캐시가 옳다. 이유가 메모리에서 시간으로 바뀌었을 뿐이다.**
29.3밀리초는 컨테이너의 arm64 native 값이고, 게스트는 `qemu-system-x86_64`를
TCG로 도는 환경이라 그 몇십 배가 붙는다. 커널이 `/init`에 넘기는 시각이 1.12초인
기계에서(`project_kernel_config`) 부팅에 그만한 시간을 더할 이유가 없다.

### 4. Zig 0.16의 해시 맵

`std.AutoHashMapUnmanaged(u32, T)`가 있고 `.empty`로 초기화한다. `std.AutoHashMap`도
아직 있지만 allocator를 명시하는 unmanaged 쪽을 쓴다. `getOrPut(alloc, key)`가
`found_existing`과 `value_ptr`을 준다.

## 저장소 쪽 출발 상태

- `terminal/src/font.zig:24` `build()`가 codepoint 배열을 받아 **전부 미리
  굽고**, `find()`(`:65`)가 그 배열을 **선형 탐색**한다.
- `terminal/src/font.zig:19-22` `cellWidth`가 `codepoint > 0x7F`로 판정한다.
- `terminal/src/font.zig:39-48` `stbtt_GetCodepointBitmap`이 주는 `xoff`·`yoff`를
  **받아서 버린다.** `Glyph`에 담을 자리가 없다.
- `terminal/src/main.zig:181-184` 부팅 때 `0x20`~`0x7E` 95자를 굽는다.
- `terminal/src/main.zig:42-54` `drawGlyph`가 셀 모서리부터 무조건 그린다.
- `terminal/src/drm.zig:128` **`setPixel`이 범위 검사를 하지 않는다.**
  프레임버퍼 밖에 쓰면 mmap 영역을 넘는다.
- `terminal/src/font_test.zig` 한글 둘을 포함해 일곱 자를 굽고 **출력만 한다.**
  단언이 하나도 없고, `build.zig`에 등록되어 있지 않아 **아무도 실행하지 않는다.**
- `terminal/build.zig:101-103` `test` step에 `input_test`와 `vt_test` 둘.
- `terminal/build.zig:94-100` 그 step의 주석이 "기본 빌드는 stb_truetype이
  필요하고 이 step은 그것을 건너뛴다"고 말한다.
- `render/check.sh` TR 체인. monitor 45460. 지금은 색 검사 셋과 음성 검사 셋.

## 왜 이 순서인가

```
Task 1  font_test를 호스트에서 돌게 만든다        ← 부팅 없음. TDD의 전제
  ↓     지금 아무도 실행하지 않는 파일을 먼저 살린다
Task 2  font.zig를 lazy 캐시로 바꾼다             ← 부팅 없음. TDD
  ↓     오프셋·advance 필드까지 여기서 한 번에 넣는다
Task 3  렌더러가 새 캐시를 쓰고 오프셋을 반영한다  ← 부팅. 한글이 처음 화면에 나온다
  ↓
Task 4  font> · ink> 로그 두 줄                   ← 부팅. 게이트가 볼 것을 확정한다
  ↓
Task 5  render/check.sh에 한글 검사를 더한다       ← 완료선
  ↓
Task 6  루트 게이트 3/3
  ↓
Task 7  문서
```

**Task 1이 맨 앞인 이유는 TR-M0의 Task 2와 같다.** 검사가 돌지 않으면 TDD가
성립하지 않는다. `font_test.zig`는 지금 `build.zig`에 등록조차 되어 있지 않아
**빌드도 실행도 되지 않는 파일**이다. `vt_test`가 "빌드만 되고 아무도 실행하지
않는" 상태로 두 서브프로젝트를 건너온 전례가 있다(`project_terminal_rendering`).

**Task 2가 오프셋 필드까지 한 번에 넣는 이유는 `Glyph` 구조체를 두 번 고치지
않기 위해서다.** lazy 캐시와 오프셋은 논리적으로 별개지만 같은 구조체를
건드리므로, 나누면 사용자가 같은 파일을 두 번 편집하고 중간 상태가 컴파일만
되고 아무 의미도 없는 자리가 생긴다.

**Task 3이 임시로 한글을 흘려 넣는 이유는 위험을 앞으로 당기기 위해서다.**
게이트가 셸에 한글을 타이핑하는 것은 Task 5의 일인데, 그때까지 기다리면
"폰트는 됐는데 화면에 안 나온다"를 맨 마지막에 발견한다. TR-M0의 Task 1이
`probe>`를 임시로 넣어 위험 4를 먼저 친 것과 같은 방식이다.

**Task 4가 Task 3보다 뒤인 이유는 로그 문구 때문이다.** 게이트가 grep할
문자열은 실제로 찍힌 것을 보고 확정한다. 코드에 적은 문구와 게이트가 찾는
문구가 어긋난 사고가 이 저장소에 이미 있었다(`HANDOFF.md`).

## 이번에 정하는 것 다섯 (design doc이 안 정한 자리)

**1. 글리프 오프셋을 반영한다. 이것은 design에 없던 항목이다.**

design의 TR-M1 절은 "`cellWidth`와 `vt.zig`의 spacer 셀 처리는 이미 있으므로
손대지 않는다"고만 적었고 baseline은 언급하지 않았다. 위 실측 (나)가 그 빈자리를
드러냈다 — **`yoff`를 버리면 `g`의 디센더가 사라지고 한글이 라틴보다 위로
솟는다.** design 결정을 바꾸는 것이 아니라 design이 몰랐던 것을 채우는 것이다.

**오프셋은 굽는 자리에서 셀 기준으로 바꿔 둔다.** `Glyph.y_offset`에
`ascent_px + yoff`를 담아서 렌더러가 baseline이라는 개념을 배우지 않게 한다.
TR-M0이 색을 `vt.zig`에서 확정해 넘긴 것과 같은 경계다.

**2. `cell_width`를 폰트의 advance에서 가져오고 `cellWidth` 함수는 지운다.**
실측 (다)가 근거다. 지금 값이 틀렸는데도 아무도 안 읽어서 드러나지 않았고,
Task 4의 `ink>` 로그가 처음으로 이 값을 읽는다.

**3. 폰트에 없는 글자도 캐시에 넣는다.** 안 넣으면 그 글자가 화면에 남아 있는
동안 **프레임마다 다시 굽는다.** 실측 (라)대로 없는 글자와 공백이 똑같이 `0x0`
비트맵이므로, `bitmap = null` 하나로 둘 다 표현하고 렌더러는 그냥 안 그린다.

**4. `ink>` 로그가 폭 2칸의 픽셀 증거다.** 상한은 한 프레임에 8줄이다.

한글은 **"파서가 폭 2칸으로 셌는가"와 "렌더러가 두 칸을 칠했는가"가 따로 틀릴
수 있다.** `style>`/`pixel>`이 색을 두 겹으로 본 것과 같은 구조다. 셀의 왼쪽
8픽셀과 오른쪽 8픽셀에서 배경이 아닌 픽셀을 따로 세어 찍는다.

```
terminal: ink> r,c U+D55C left=N right=M
```

`right`가 0이면 글자가 반쪽만 그려진 것이다. 셀 하나만 보면 이것을 못 잡는다.

**5. 게이트가 치는 명령은 `printf '\xed\x95\x9c\033[41m \033[0m\n'`이다.**

`\xed\x95\x9c`가 '한'의 UTF-8 세 바이트다. QEMU monitor의 `sendkey`는 ASCII만
칠 수 있으므로 한글을 직접 못 친다. 셸의 `printf`가 바이트를 만들어 주는 것이
유일한 길이다.

**한글 바로 뒤에 배경색 칠한 공백을 붙이는 이유는 "다음 글자가 겹치지 않는다"를
게이트가 볼 수 있게 하기 위해서다.** 그 공백의 `style>` 줄이 좌표를 주므로,
게이트가 한글 셀의 열 번호에 2를 더한 값과 비교할 수 있다. 이것이 폭 2칸의
**파서 쪽** 증거이고 `ink>`가 **렌더러 쪽** 증거다.

`printf`가 fish·bash 양쪽의 빌트인이라 `PATH`가 비어 있어도 되는 것과
(`project_guest_environment`), `\e` 대신 `\033`을 쓰는 이유는 TR-M0과 같다.
**`\x`를 fish의 `printf`가 해석하는지는 Task 5 Step 2에서 실제로 확인한다.**
안 되면 8진수(`\355\225\234`)로 바꾼다.

---

## Task 1: `font_test`를 호스트 아키텍처에서 돌게 만든다

**Files:**
- Modify: `terminal/build.zig` (호스트 절, `test` step, 그 위의 주석)

`font_test.zig`는 지금 `build.zig`에 등록되어 있지 않아 **빌드도 실행도 되지
않는다.** Task 2의 TDD가 여기에 얹히므로 먼저 살린다.

폰트 래스터라이저는 게스트 하드웨어와 아무 상관이 없다. stb_truetype에 바이트를
먹이고 비트맵을 받는 순수 계산이라 호스트에서 도는 것이 맞다.

- [ ] **Step 1: 호스트 절에 `font_test`를 더한다**

`terminal/build.zig`의 `input_test` 블록(현재 `:82-92`) **바로 다음에**, 즉
`const test_step = ...` 줄 **앞에** 아래를 넣는다.

**넣을 것:**

```zig

    // font_test도 호스트에서 돈다. 폰트 래스터라이저는 게스트 하드웨어와
    // 아무 상관이 없다 — stb_truetype에 바이트를 먹이고 비트맵을 받는 순수
    // 계산이라, 부팅 1.5초를 쓸 이유가 없다.
    //
    // 이 파일은 TR-M1 전까지 **build.zig에 등록조차 되어 있지 않았다.**
    // 빌드도 실행도 되지 않는 채로 남아 있었고, 그래서 폰트에 관한 단언이
    // 저장소 어디에도 없었다.
    //
    // vendor/fonts/*.ttf를 상대 경로로 읽으므로 `zig build test`를
    // terminal/ 안에서 돌려야 한다. 게이트가 이미 그렇게 하고 있다.
    const font_test_mod = b.createModule(.{
        .root_source_file = b.path("src/font_test.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    font_test_mod.addIncludePath(b.path("vendor"));
    font_test_mod.addCSourceFile(.{
        .file = b.path("src/stb_truetype_impl.c"),
        .flags = &.{},
    });
    font_test_mod.link_libc = true;
    font_test_mod.linkSystemLibrary("m", .{});
    const font_test = b.addExecutable(.{
        .name = "font_test",
        .root_module = font_test_mod,
    });
    b.installArtifact(font_test);
```

- [ ] **Step 2: `test` step에 넣고 그 위의 주석을 고친다**

`terminal/build.zig`의 현재 `:94-103`이 이렇다.

**지울 것:**

```zig
    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
    //
    // 기본 `zig build`와 분리하는 이유는 속도다. 기본 빌드는 x86_64 terminal
    // 본체까지 만드느라 stb_truetype이 필요하고, 이 step은 그것을 건너뛴다.
    // 다만 TR-M0에서 vt_test가 들어온 뒤로 **libghostty-vt는 이 step에도
    // 필요하다** — vendor 트리가 없으면(prepare.sh를 안 돌렸으면) 여기서
    // 막힌다.
    const test_step = b.step("test", "호스트 아키텍처로 도는 검사를 실행한다");
    test_step.dependOn(&b.addRunArtifact(input_test).step);
    test_step.dependOn(&b.addRunArtifact(vt_test).step);
```

**넣을 것:**

```zig
    // `zig build test` = 호스트에서 도는 검사만 빌드해서 실행한다.
    //
    // 기본 `zig build`와 분리하는 이유는 속도였는데, **그 이유가 이제 거의
    // 남지 않았다.** TR-M0에서 vt_test가 들어오면서 libghostty-vt가 필요해졌고,
    // TR-M1에서 font_test가 들어오면서 stb_truetype까지 필요해졌다. 남은
    // 차이는 x86_64 terminal 본체와 pty_test를 안 만든다는 것뿐이다.
    // 두 vendor 트리가 없으면(prepare.sh를 안 돌렸으면) 여기서 막힌다.
    const test_step = b.step("test", "호스트 아키텍처로 도는 검사를 실행한다");
    test_step.dependOn(&b.addRunArtifact(input_test).step);
    test_step.dependOn(&b.addRunArtifact(vt_test).step);
    test_step.dependOn(&b.addRunArtifact(font_test).step);
```

- [ ] **Step 3: 지금 있는 것이 돌아가는지 본다**

Claude가 실행한다. `font_test.zig`는 아직 안 고쳤으므로 **일곱 자를 출력만
하고 끝나야 한다.**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && zig build test' 2>&1 | tail -25
```

기대 출력에 이 줄들이 있어야 한다.

```
codepoint U+54: 7x10 pixels, cell_width=8, ... non-zero
codepoint U+D558: ...x... pixels, cell_width=16, ... non-zero
codepoint U+C774: 11x13 pixels, cell_width=16, ... non-zero
```

**여기서 컴파일이 막히면 `@cImport` 경로 문제다.** `addIncludePath`가
`vendor`를 가리키는지 확인한다. `input_test`·`vt_test`의 기존 출력도 함께
나와야 한다.

- [ ] **Step 4: 커밋**

```bash
git add terminal/build.zig
git commit -m "Run the font test instead of leaving it unbuilt"
```

---

## Task 2: `font.zig`를 lazy 캐시로 바꾼다

**Files:**
- Rewrite: `terminal/src/font.zig` (70줄 → 약 140줄)
- Test: `terminal/src/font_test.zig`

design의 TR-M1 절("처음 쓸 때 구워 넣는 캐시", "선형 탐색을 해시 맵으로")과
이번에 정하는 것 1·2·3. 부팅 없이 끝난다.

- [ ] **Step 1: 실패하는 검사를 먼저 쓴다**

`terminal/src/font_test.zig`는 지금 **단언이 하나도 없이 출력만 한다.** 전체를
새로 쓴다. 파일이 36줄이라 인라인으로 제시한다.

**지울 것:** 파일 전체.

**넣을 것:**

```zig
const std = @import("std");
const font = @import("font.zig");

/// 폰트 캐시의 검사. 부팅을 안 쓰고 도는 자리다 — 래스터라이저는 게스트
/// 하드웨어와 상관이 없다.
///
/// 기대값은 plan을 쓰면서 컨테이너에서 직접 재 둔 것이다. 짐작으로 적으면
/// 틀리는 자리가 둘이다: **`yoff`가 글자마다 다르고**(A는 -14, 한은 -16),
/// **폰트에 없는 글자는 에러가 아니라 빈 비트맵으로 온다.**
pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    const file = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "vendor/fonts/Hanme_8x4x4.ttf",
        allocator,
        .unlimited,
    );

    var cache = try font.Cache.init(allocator, file);
    defer cache.deinit();

    // ── 1. 굽지 않은 캐시는 비어 있다 ─────────────────────────────────
    if (cache.count() != 0) {
        std.debug.print("FAIL: 새 캐시에 글리프가 {d}개 있다\n", .{cache.count()});
        return error.CacheNotEmpty;
    }

    // ── 2. 글자마다 기대하는 모양 ─────────────────────────────────────
    //
    // y_offset은 stb의 yoff에 ascent(16px)를 더한 값이다. 셀 위쪽 모서리에서
    // 몇 픽셀 아래에 찍는가를 뜻한다. 'g'가 'A'보다 3픽셀 아래인 것이
    // 디센더이고, 이 값을 버리면 그 디센더가 사라진다.
    const Want = struct {
        cp: u32,
        w: u32,
        h: u32,
        cell_width: u32,
        x_offset: i32,
        y_offset: i32,
        what: []const u8,
    };
    const wants = [_]Want{
        .{ .cp = 'A', .w = 7, .h = 10, .cell_width = 8, .x_offset = 0, .y_offset = 2, .what = "라틴 대문자" },
        .{ .cp = 'g', .w = 7, .h = 10, .cell_width = 8, .x_offset = 0, .y_offset = 5, .what = "디센더가 아래로 내려간다" },
        .{ .cp = 0xD55C, .w = 15, .h = 15, .cell_width = 16, .x_offset = 1, .y_offset = 0, .what = "한글 '한'은 폭 2칸" },
        .{ .cp = 0xAC00, .w = 13, .h = 13, .cell_width = 16, .x_offset = 3, .y_offset = 1, .what = "한글 '가'" },
        // 0x7F를 넘지만 폭이 1칸이다. cellWidth의 옛 규칙이 틀렸던 자리다.
        .{ .cp = 0x00E9, .w = 7, .h = 10, .cell_width = 8, .x_offset = 1, .y_offset = 2, .what = "é는 0x7F를 넘어도 1칸" },
    };

    for (wants) |want| {
        const glyph = try cache.find(want.cp);
        if (glyph.width != want.w or glyph.height != want.h or
            glyph.cell_width != want.cell_width or
            glyph.x_offset != want.x_offset or glyph.y_offset != want.y_offset)
        {
            std.debug.print(
                "FAIL: {s}: U+{X} {d}x{d} cell_width={d} x_offset={d} y_offset={d}" ++
                    " (expected {d}x{d} cell_width={d} x_offset={d} y_offset={d})\n",
                .{
                    want.what,      want.cp,          glyph.width,      glyph.height,
                    glyph.cell_width, glyph.x_offset, glyph.y_offset,   want.w,
                    want.h,         want.cell_width,  want.x_offset,    want.y_offset,
                },
            );
            return error.WrongGlyphMetrics;
        }
        if (glyph.bitmap == null) {
            std.debug.print("FAIL: {s}: U+{X}에 비트맵이 없다\n", .{ want.what, want.cp });
            return error.NoBitmap;
        }
        std.debug.print("font_test: {s} OK\n", .{want.what});
    }

    // ── 3. 글리프가 셀 밖으로 새지 않는다 ─────────────────────────────
    //
    // 오프셋을 반영한 뒤에 이것이 지켜지지 않으면 setPixel이 범위 검사를
    // 하지 않으므로(drm.zig:128) 게스트가 죽는다. 폰트 전체를 훑는다.
    var cp: u32 = 0xAC00;
    var worst_bottom: i32 = 0;
    while (cp <= 0xD7A3) : (cp += 1) {
        const glyph = try cache.find(cp);
        const bottom = glyph.y_offset + @as(i32, @intCast(glyph.height));
        if (bottom > worst_bottom) worst_bottom = bottom;
        if (glyph.y_offset < 0 or bottom > 16 or
            glyph.x_offset < 0 or
            glyph.x_offset + @as(i32, @intCast(glyph.width)) > 16)
        {
            std.debug.print(
                "FAIL: U+{X}가 셀 밖으로 샌다: x_offset={d} w={d} y_offset={d} h={d}\n",
                .{ cp, glyph.x_offset, glyph.width, glyph.y_offset, glyph.height },
            );
            return error.GlyphOutsideCell;
        }
    }
    std.debug.print(
        "font_test: 한글 음절 11172자가 전부 16x16 셀 안에 들어간다 (가장 아래가 {d}행) OK\n",
        .{worst_bottom},
    );

    // ── 4. 폰트에 없는 글자는 에러가 아니다 ───────────────────────────
    //
    // 이 폰트에는 한자도 호환 자모(ㄱ)도 없다. stb는 glyph_index 0에
    // 0x0 비트맵을 준다 — 공백과 똑같은 모양이라 구분되지 않고, 구분할
    // 이유도 없다. **캐시에는 들어가야 한다.** 안 넣으면 그 글자가 화면에
    // 남아 있는 동안 프레임마다 다시 굽는다.
    const before = cache.count();
    const missing = try cache.find(0x4E00);
    if (missing.bitmap != null) {
        std.debug.print("FAIL: 폰트에 없는 U+4E00에 비트맵이 있다\n", .{});
        return error.UnexpectedBitmap;
    }
    if (cache.count() != before + 1) {
        std.debug.print("FAIL: 폰트에 없는 글자가 캐시에 안 들어갔다\n", .{});
        return error.MissingGlyphNotCached;
    }
    std.debug.print("font_test: 폰트에 없는 글자도 캐시에 들어간다 OK\n", .{});

    // ── 5. 두 번째 요청은 캐시에서 나온다 ─────────────────────────────
    const count_before = cache.count();
    _ = try cache.find('A');
    if (cache.count() != count_before) {
        std.debug.print("FAIL: 이미 구운 글자를 다시 구웠다\n", .{});
        return error.CacheMiss;
    }
    std.debug.print("font_test: 같은 글자를 두 번 찾아도 한 번만 굽는다 OK\n", .{});

    // ── 6. 전부 구운 캐시의 크기 (design 위험 3) ──────────────────────
    //
    // 11172자를 위에서 전부 구웠으므로 이 값이 **최악의 경우**다.
    std.debug.print(
        "font_test: 한글 전체를 구운 캐시 = {d} glyph(s), {d} bitmap bytes ({d:.2} MB)\n",
        .{
            cache.count(),
            cache.bitmap_bytes,
            @as(f64, @floatFromInt(cache.bitmap_bytes)) / 1048576.0,
        },
    );

    std.debug.print("PASS\n", .{});
}
```

- [ ] **Step 2: 실패하는 것을 확인한다**

Claude가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && zig build test' 2>&1 | tail -20
```

기대: **컴파일 에러.** `font.Cache`가 없다는 내용이다
(`root source file struct 'font' has no member named 'Cache'`). 이것이 옳은
실패다.

- [ ] **Step 3: `font.zig`를 새로 쓴다**

파일 전체를 갈아 끼운다. 140줄이 넘으므로 `CLAUDE.md` 규칙대로 Claude가
`/tmp/font.zig`에 원본을 만들고 `diff`로 대조해 보인 뒤, 승인을 받아 제자리에
넣는다. 사용자가 확인할 것은 셋이다.

1. `find`가 `!Glyph`를 돌려준다(옛 `?Glyph`가 아니다). 폰트에 없는 글자는
   null이 아니라 **비트맵이 null인 Glyph**로 온다.
2. `y_offset`에 `ascent_px`가 이미 더해져 있다. 렌더러는 baseline을 모른다.
3. `cellWidth` 함수가 사라지고 `cell_width`가 폰트의 advance에서 온다.

**넣을 것(`/tmp/font.zig`의 내용):**

```zig
const std = @import("std");

const stb = @cImport({
    @cInclude("stb_truetype.h");
});

/// 구워 놓은 글자 하나.
///
/// `x_offset`·`y_offset`은 **셀의 왼쪽 위 모서리에서** 비트맵을 찍을 곳까지의
/// 거리다. stb가 주는 `yoff`는 baseline 기준이라 음수인데(실측: 'A'가 -14,
/// '한'이 -16), 그대로 쓰면 글자가 화면 위로 솟는다. 굽는 자리에서 ascent를
/// 더해 셀 기준으로 바꿔 둔다 — **렌더러가 baseline이라는 개념을 배우지 않게
/// 하려는 것이고, TR-M0이 색을 vt.zig에서 확정해 넘긴 것과 같은 경계다.**
///
/// TR-M1 전까지는 이 두 값을 stb에게 받아서 그냥 버렸다. 그래서 'g'의
/// 디센더가 화면에서 사라지고 있었다.
pub const Glyph = struct {
    codepoint: u32,
    width: u32,
    height: u32,
    /// 이 글자가 차지하는 폭(픽셀). **폰트의 advance에서 가져온다** —
    /// 실측으로 라틴이 8.00, 한글이 16.00이다. 옛 `cellWidth` 함수는
    /// "0x7F를 넘으면 16"이라고 판정해서 'é'(advance 8)를 틀리게 봤다.
    cell_width: u32,
    x_offset: i32,
    y_offset: i32,
    /// 폰트에 없는 글자와 공백은 **둘 다 null이다.** stb가 양쪽에 똑같이
    /// 0x0 비트맵을 주고, 구분할 이유도 없다 — 어느 쪽이든 그릴 것이 없다.
    bitmap: ?[*]u8,
};

/// 처음 쓸 때 구워서 넣어 두는 글리프 캐시.
///
/// 부팅 때 ASCII 95자를 미리 굽던 배열을 대신한다. 한글이 들어오면서 미리
/// 굽기가 성립하지 않게 됐다 — 이 폰트에 **완성형 11172자가 하나도 빠짐없이**
/// 들어 있고, 전부 구우면 비트맵만 2.06MB에 컨테이너(arm64 native)에서도
/// 29밀리초가 든다. 게스트는 qemu-system-x86_64를 TCG로 도는 환경이라 그
/// 몇십 배가 붙는다.
///
/// **메모리가 아니라 시간이 이유다.** 2.06MB는 128MB 게스트가 감당하지만,
/// 커널이 /init에 넘기는 시각이 1.12초인 기계에서 부팅에 그만한 시간을
/// 더할 이유가 없다. 화면에 실제로 나오는 글자는 수십 자다.
///
/// **`font_data`가 캐시보다 오래 살아야 한다.** stb_truetype은 그 바이트를
/// 복사하지 않고 참조만 한다.
pub const Cache = struct {
    alloc: std.mem.Allocator,
    info: stb.stbtt_fontinfo,
    scale: f32,
    /// baseline까지의 픽셀. stb의 `yoff`를 셀 기준으로 옮길 때 더한다.
    /// 이 폰트는 ascent=1600, descent=0, unitsPerEm=1600이라 16px에서
    /// 정확히 16이 나온다.
    ascent_px: i32,
    glyphs: std.AutoHashMapUnmanaged(u32, Glyph),
    /// 지금까지 구운 비트맵의 합계. design 위험 3을 게이트가 볼 수 있게
    /// 하는 유일한 창구다.
    bitmap_bytes: usize,

    pub fn init(alloc: std.mem.Allocator, font_data: []const u8) !Cache {
        var info: stb.stbtt_fontinfo = undefined;
        if (stb.stbtt_InitFont(&info, font_data.ptr, 0) == 0) {
            return error.FontInitFailed;
        }

        const pixel_height: f32 = 16.0;
        const scale = stb.stbtt_ScaleForPixelHeight(&info, pixel_height);

        var ascent: c_int = 0;
        var descent: c_int = 0;
        var line_gap: c_int = 0;
        stb.stbtt_GetFontVMetrics(&info, &ascent, &descent, &line_gap);

        return .{
            .alloc = alloc,
            .info = info,
            .scale = scale,
            .ascent_px = @intFromFloat(@round(@as(f32, @floatFromInt(ascent)) * scale)),
            .glyphs = .empty,
            .bitmap_bytes = 0,
        };
    }

    /// 비트맵 자체는 stb가 libc의 malloc으로 잡은 것이라 여기서 안 푼다.
    /// 프로세스가 끝날 때 함께 사라진다 — 셸이 끝나면 terminal도 끝나고
    /// PID 1이 새로 띄운다(main.zig 마지막 주석).
    pub fn deinit(self: *Cache) void {
        self.glyphs.deinit(self.alloc);
    }

    /// 글자 하나를 돌려준다. 캐시에 없으면 굽는다.
    ///
    /// **폰트에 없는 글자도 캐시에 넣는다.** 안 넣으면 그 글자가 화면에
    /// 남아 있는 동안 프레임마다 다시 굽는다.
    pub fn find(self: *Cache, codepoint: u32) !Glyph {
        const gop = try self.glyphs.getOrPut(self.alloc, codepoint);
        if (gop.found_existing) return gop.value_ptr.*;

        var w: c_int = 0;
        var h: c_int = 0;
        var xoff: c_int = 0;
        var yoff: c_int = 0;
        const bitmap = stb.stbtt_GetCodepointBitmap(
            &self.info,
            self.scale,
            self.scale,
            @intCast(codepoint),
            &w,
            &h,
            &xoff,
            &yoff,
        );

        // 공백과 폰트에 없는 글자는 0x0 비트맵으로 온다. 그것은 정상이다.
        // w*h가 0이 아닌데 null이면 malloc이 실패한 것이고, 그때는 알아야
        // 한다. 캐시에 들어가므로 이 경고는 글자마다 한 번만 찍힌다.
        if (bitmap == null and w * h != 0) {
            std.debug.print("font: WARN could not rasterize U+{X}\n", .{codepoint});
        }

        var advance: c_int = 0;
        var lsb: c_int = 0;
        stb.stbtt_GetCodepointHMetrics(&self.info, @intCast(codepoint), &advance, &lsb);

        gop.value_ptr.* = .{
            .codepoint = codepoint,
            .width = @intCast(w),
            .height = @intCast(h),
            .cell_width = @intFromFloat(
                @round(@as(f32, @floatFromInt(advance)) * self.scale),
            ),
            .x_offset = @intCast(xoff),
            // 여기가 baseline이 사라지는 자리다. 위 doc comment 참고.
            .y_offset = self.ascent_px + @as(i32, @intCast(yoff)),
            .bitmap = bitmap,
        };
        self.bitmap_bytes += @as(usize, @intCast(w)) * @as(usize, @intCast(h));
        return gop.value_ptr.*;
    }

    pub fn count(self: *const Cache) usize {
        return self.glyphs.count();
    }
};
```

- [ ] **Step 4: 검사가 통과하는지 본다**

Claude가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && zig build test' 2>&1 | tail -20
```

기대 출력:

```
font_test: 라틴 대문자 OK
font_test: 디센더가 아래로 내려간다 OK
font_test: 한글 '한'은 폭 2칸 OK
font_test: 한글 '가' OK
font_test: é는 0x7F를 넘어도 1칸 OK
font_test: 한글 음절 11172자가 전부 16x16 셀 안에 들어간다 (가장 아래가 16행) OK
font_test: 폰트에 없는 글자도 캐시에 들어간다 OK
font_test: 같은 글자를 두 번 찾아도 한 번만 굽는다 OK
font_test: 한글 전체를 구운 캐시 = 11178 glyph(s), 2157133 bitmap bytes (2.06 MB)
PASS
```

**`main.zig`는 아직 안 고쳤으므로 `zig build`(게스트 바이너리)는 여기서
막힌다.** `font.build`와 `font.find`의 옛 시그니처를 쓰기 때문이다. `test`
step은 `main.zig`를 안 만지므로 통과한다. Task 3이 그것을 고친다.

**"가장 아래가 16행"이 아니라 17 이상이 나오면 여기서 멈춘다.** 글리프가 셀
밖으로 새고 `setPixel`이 범위 검사를 하지 않으므로(`drm.zig:128`), 그대로
진행하면 게스트가 죽는다.

- [ ] **Step 5: 커밋**

```bash
git add terminal/src/font.zig terminal/src/font_test.zig
git commit -m "Bake each glyph the first time it is asked for"
```

---

## Task 3: 렌더러가 새 캐시를 쓰고 오프셋을 반영한다

**Files:**
- Modify: `terminal/src/main.zig` (`drawGlyph` `:38-54`, `render` `:56-84`,
  폰트 준비 `:179-184`, 렌더 호출부 `:314-316`)

여기서 **한글이 처음 화면에 나온다.** 임시로 한 줄을 흘려 넣어 위험을 앞으로
당긴다.

- [ ] **Step 1: `drawGlyph`가 오프셋을 반영하고 범위를 검사한다**

`terminal/src/main.zig`의 현재 `:38-54`가 이렇다.

**지울 것:**

```zig
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

**넣을 것:**

```zig
/// 알파 블렌딩을 하지 않고 문턱값으로 찍는다(design 결정 4).
///
/// TR-M1에서 이 선택의 근거가 짐작에서 실측으로 바뀌었다. 이 폰트의
/// coverage는 **0 아니면 255뿐이고 그 사이 값이 하나도 없다.** 16px가
/// 8x4x4의 native 크기라 안티앨리어싱이 아예 일어나지 않는다. 그래서
/// 게이트의 픽셀 검사가 정확한 상수와 비교할 수 있다.
///
/// **글리프의 오프셋을 반영한다.** stb가 주는 비트맵은 글자를 감싸는 최소
/// 사각형이라, 셀 모서리에 그대로 찍으면 'A'와 'g'의 baseline이 어긋나고
/// 한글이 라틴보다 위로 솟는다. `Glyph`가 들고 있는 두 오프셋은 굽는
/// 자리에서 이미 셀 기준으로 바뀌어 있으므로 여기서는 더하기만 한다.
///
/// **좌표를 부호 있는 수로 계산하고 범위를 검사한다.** `setPixel`이 검사를
/// 하지 않기 때문이다(`drm.zig:128`) — 프레임버퍼 밖에 쓰면 mmap 영역을
/// 넘어 게스트가 죽는다. font_test가 "한글 11172자가 전부 셀 안에 들어간다"를
/// 단언하지만, 그것은 이 폰트에 대한 사실이지 코드의 성질이 아니다.
fn drawGlyph(fb: drm.Framebuffer, glyph: font.Glyph, x: u32, y: u32, color: u32) void {
    const bitmap = glyph.bitmap orelse return;
    const origin_x = @as(i32, @intCast(x)) + glyph.x_offset;
    const origin_y = @as(i32, @intCast(y)) + glyph.y_offset;
    const limit_x = @as(i32, @intCast(fb.width));
    const limit_y = @as(i32, @intCast(fb.height));

    var row: u32 = 0;
    while (row < glyph.height) : (row += 1) {
        const py = origin_y + @as(i32, @intCast(row));
        if (py < 0 or py >= limit_y) continue;
        var col: u32 = 0;
        while (col < glyph.width) : (col += 1) {
            const px = origin_x + @as(i32, @intCast(col));
            if (px < 0 or px >= limit_x) continue;
            const coverage = bitmap[row * glyph.width + col];
            if (coverage > 127) {
                fb.setPixel(@intCast(px), @intCast(py), color);
            }
        }
    }
}
```

- [ ] **Step 2: `render`가 캐시를 mutable로 받는다**

`terminal/src/main.zig`의 현재 `render` 함수에서 **시그니처와 글리프 루프**만
바뀐다. 배경 루프와 `fb.fill`은 그대로 둔다.

**지울 것:**

```zig
fn render(fb: drm.Framebuffer, cache: font.GlyphCache, cells: []const vt.CellGlyph) !void {
```

**넣을 것:**

```zig
/// `cache`가 `*font.Cache`인 이유는 TR-M1부터 **그리는 도중에 글자를 굽기
/// 때문이다.** 캐시에 없는 글자가 화면에 나타나면 그 자리에서 래스터라이징이
/// 일어난다 — 한 자당 밀리초 이하이고 같은 글자는 한 번뿐이다.
fn render(fb: drm.Framebuffer, cache: *font.Cache, cells: []const vt.CellGlyph) !void {
```

그리고 같은 함수 안의 글리프 루프가 이렇다.

**지울 것:**

```zig
    for (cells) |cell| {
        const x = GRID_X + @as(u32, cell.col) * CELL_W;
        const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
        if (font.find(cache, cell.codepoint)) |glyph| {
            drawGlyph(fb, glyph, x, y, cell.fg);
        }
    }
```

**넣을 것:**

```zig
    for (cells) |cell| {
        // 빈 셀은 배경만 칠하고 끝난다. 캐시에 codepoint 0을 넣지 않기
        // 위해서이기도 하다 — 커서 자리와 색 띠가 전부 이쪽이라 흔하다.
        if (cell.codepoint == 0) continue;
        const x = GRID_X + @as(u32, cell.col) * CELL_W;
        const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
        const glyph = try cache.find(cell.codepoint);
        drawGlyph(fb, glyph, x, y, cell.fg);
    }
```

- [ ] **Step 3: 미리 굽기를 캐시로 바꾸고, 한글을 임시로 흘려 넣는다**

`terminal/src/main.zig`의 현재 `:179-184`가 이렇다.

**지울 것:**

```zig
    // 사용자가 아무 키나 칠 수 있으므로 출력 가능한 ASCII 전체를 미리
    // 래스터라이징한다(0x20 ' ' ~ 0x7E '~', 95자).
    var codepoints: [95]u32 = undefined;
    for (&codepoints, 0..) |*cp, i| cp.* = @intCast(0x20 + i);
    const cache = try font.build(allocator, font_data, &codepoints);
    std.debug.print("terminal: rasterized {d} glyphs\n", .{codepoints.len});
```

**넣을 것:**

```zig
    // 미리 굽지 않는다. 처음 쓸 때 굽는 캐시가 대신한다(design의 TR-M1 절).
    //
    // 이 폰트에 완성형 한글 11172자가 전부 들어 있어서 미리 굽기가 성립하지
    // 않는다 — 전부 구우면 비트맵만 2.06MB이고, 컨테이너에서도 29밀리초가
    // 드는 일을 TCG 에뮬레이션 게스트가 부팅 때마다 할 이유가 없다.
    //
    // font_data를 free하지 않는다. stb_truetype이 그 바이트를 복사하지 않고
    // 참조만 하므로 캐시보다 오래 살아야 한다.
    var cache = try font.Cache.init(allocator, font_data);
    defer cache.deinit();
    std.debug.print("terminal: font cache ready (lazy)\n", .{});
```

그리고 루프 안의 렌더 호출부(현재 `:316`)가 이렇다.

**지울 것:**

```zig
            try render(fb, cache, cells);
```

**넣을 것:**

```zig
            try render(fb, &cache, cells);
```

마지막으로 **임시 확인**을 넣는다. `terminal/src/main.zig`에서
`const cell_buf = try allocator.alloc(...)` 줄과 그 `defer` 줄 **다음에** 아래를
넣는다.

**넣을 것:**

```zig

    // ── TR-M1 Task 3 임시 확인 ────────────────────────────────────────
    //
    // 게이트가 셸에 한글을 타이핑하는 것은 Task 5의 일이다. 그때까지
    // 기다리면 "폰트는 됐는데 화면에 안 나온다"를 맨 마지막에 발견한다.
    // 파서에 직접 흘려 넣어 렌더링만 먼저 본다. **Task 4에서 지운다.**
    // "한글" 뒤의 X가 폭 2칸을 눈으로 볼 수 있게 한다.
    screen.feed("\xed\x95\x9c\xea\xb8\x80X\r\n");
```

- [ ] **Step 4: 빌드한다**

Claude가 실행한다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash -c 'cd terminal && zig build' 2>&1 | tail -20
```

기대: 에러 없이 끝난다. **Task 2가 남겨 둔 옛 시그니처 오류가 여기서
해소된다.**

- [ ] **Step 5: 부팅해서 한글이 나오는지 본다**

Claude가 실행한다(커널 빌드 포함 약 1분 30초). 시리얼 로그는 통과하면 사라지므로
**한 번의 `docker run` 안에서** 뒤진다. `grep`에 `-a`를 반드시 붙인다
(`project_terminal_rendering`).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash render/check.sh > /tmp/gate.out 2>&1
  echo "=== gate verdict ==="; tail -3 /tmp/gate.out
  echo "=== screen lines ==="; grep -ah "terminal: screen>" /tmp/tmp.* | head -5
  echo "=== font line ==="; grep -ah "terminal: font cache" /tmp/tmp.*
'
```

기대: `screen>` 줄에 **`한글X`가 그대로 보인다.**

```
terminal: screen> 한글X | ...
```

**이 줄이 나온다는 것은 파서가 UTF-8을 조립했다는 뜻이지 화면에 그려졌다는
뜻이 아니다.** 픽셀 증거는 Task 4의 `ink>`가 만든다. 지금 확인하는 것은
"렌더러가 한글을 만나 죽지 않는다"이고, 그것은 **TR 체인이 통과한다는 사실
자체**가 증명한다.

**여기서 게스트가 죽으면** `drawGlyph`의 범위 검사를 먼저 의심한다. 로그
마지막에 `drm.zig`나 `main.zig`의 줄 번호가 찍힌다.

- [ ] **Step 6: 커밋**

```bash
git add terminal/src/main.zig
git commit -m "Put each glyph where the font metrics say it goes"
```

---

## Task 4: `font>` · `ink>` 로그 두 줄

**Files:**
- Modify: `terminal/src/main.zig` (상수, `dumpStyles` 아래, 루프 안,
  Task 3의 임시 줄 제거)

**여기서 찍히는 문구가 Task 5의 게이트가 grep할 문구다.**

- [ ] **Step 1: `ink>` 덤프를 더한다**

`terminal/src/main.zig`의 `dumpStyles` 함수 **바로 다음에** 아래를 넣는다.
`STYLE_DUMP_LIMIT` 상수 옆이 아니라 함수 옆인 이유는 두 상수가 각자 쓰이는
함수 바로 위에 있는 편이 읽기 쉽기 때문이다.

**넣을 것:**

```zig

/// 한 프레임에 찍는 ink 줄의 상한. 한글이 화면을 덮은 상태에서 매 프레임
/// 수백 줄이 쏟아지는 것을 막는다. 게이트가 보는 것은 한 줄 안의 한두
/// 글자다.
const INK_DUMP_LIMIT: usize = 8;

/// 폭 2칸 글자가 **정말 두 칸에 걸쳐 찍혔는지**를 프레임버퍼에서 되읽어
/// 센다.
///
/// `style>`/`pixel>`이 색을 두 겹으로 보는 것과 같은 이유다(design 결정 7).
/// 한글은 **"파서가 폭 2칸으로 셌는가"와 "렌더러가 두 칸을 칠했는가"가 따로
/// 틀릴 수 있다.** 셀 하나만 보면 그 차이를 못 잡는다 — 글자가 왼쪽 반쪽만
/// 그려져도 그 셀에는 잉크가 있기 때문이다. 그래서 왼쪽 8픽셀과 오른쪽
/// 8픽셀을 따로 센다.
///
/// **반드시 render() 뒤에 불러야 한다.** 그 전에 부르면 이전 프레임의
/// 픽셀을 읽는다.
fn dumpInk(fb: drm.Framebuffer, cache: *font.Cache, cells: []const vt.CellGlyph) void {
    var shown: usize = 0;
    for (cells) |cell| {
        if (shown >= INK_DUMP_LIMIT) break;
        // 폭 2칸인 글자만 본다. cell_width는 폰트의 advance에서 온 값이라
        // "0x7F를 넘으면 넓다"는 짐작보다 정확하다.
        const glyph = cache.find(cell.codepoint) catch continue;
        if (glyph.cell_width <= CELL_W) continue;

        const x = GRID_X + @as(u32, cell.col) * CELL_W;
        const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
        // 마지막 칸에 폭 2칸 글자가 있으면 오른쪽 칸이 프레임버퍼 밖이다.
        // libghostty-vt가 그런 배치를 만들지 않지만, getPixel도 범위 검사를
        // 하지 않으므로 여기서 막는다.
        if (x + 2 * CELL_W > fb.width or y + ROW_HEIGHT > fb.height) continue;
        shown += 1;

        var left: u32 = 0;
        var right: u32 = 0;
        var row: u32 = 0;
        while (row < ROW_HEIGHT) : (row += 1) {
            var col: u32 = 0;
            while (col < 2 * CELL_W) : (col += 1) {
                if (fb.getPixel(x + col, y + row) & 0x00FFFFFF != cell.bg) {
                    if (col < CELL_W) left += 1 else right += 1;
                }
            }
        }
        std.debug.print("terminal: ink> {d},{d} U+{X} left={d} right={d}\n", .{
            cell.row, cell.col, cell.codepoint, left, right,
        });
    }
}
```

- [ ] **Step 2: 루프에서 두 로그를 부르고 임시 줄을 지운다**

먼저 Task 3이 넣은 임시 줄을 지운다.

**지울 것:**

```zig

    // ── TR-M1 Task 3 임시 확인 ────────────────────────────────────────
    //
    // 게이트가 셸에 한글을 타이핑하는 것은 Task 5의 일이다. 그때까지
    // 기다리면 "폰트는 됐는데 화면에 안 나온다"를 맨 마지막에 발견한다.
    // 파서에 직접 흘려 넣어 렌더링만 먼저 본다. **Task 4에서 지운다.**
    // "한글" 뒤의 X가 폭 2칸을 눈으로 볼 수 있게 한다.
    screen.feed("\xed\x95\x9c\xea\xb8\x80X\r\n");
```

그리고 루프 **앞의** `var first_frame_timed = false;` 줄이 이렇다.

**지울 것:**

```zig
    var first_frame_timed = false;
```

**넣을 것:**

```zig
    var first_frame_timed = false;
    // 캐시가 자랐을 때만 찍는다. 매 프레임 찍으면 키를 칠 때마다 같은 줄이
    // 반복된다. design 위험 3을 게이트가 볼 수 있게 하는 자리다.
    var last_glyph_count: usize = 0;
```

마지막으로 루프 안의 `dumpStyles` 호출 **다음에** 아래를 넣는다.

**넣을 것:**

```zig
            dumpInk(fb, &cache, cells);
            if (cache.count() != last_glyph_count) {
                last_glyph_count = cache.count();
                std.debug.print("terminal: font> {d} glyph(s) cached, {d} bitmap bytes\n", .{
                    last_glyph_count, cache.bitmap_bytes,
                });
            }
```

- [ ] **Step 3: 부팅해서 두 줄이 찍히는지 본다**

Claude가 실행한다(약 1분 30초). **임시 줄을 지웠으므로 한글은 아직 화면에
없다.** 이 Step이 보는 것은 `font>` 줄이고, `ink>`는 Task 5에서 처음 나온다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  bash render/check.sh > /tmp/gate.out 2>&1
  echo "=== gate verdict ==="; tail -3 /tmp/gate.out
  echo "=== font lines ==="; grep -ah "terminal: font>" /tmp/tmp.*
  echo "=== ink lines (아직 없어야 한다) ==="; grep -ac "terminal: ink>" /tmp/tmp.* || true
'
```

기대: `font>` 줄이 몇 개 나오고 글리프 수가 프롬프트에 쓰인 글자 수 언저리다.

```
terminal: font> 12 glyph(s) cached, 840 bitmap bytes
```

**이 숫자가 design 위험 3에 대한 실사용 답이다.** 최악의 경우(2.06MB)는
`font_test`가 이미 쟀고, 여기 나오는 것은 실제로 쓰이는 양이다.

**TR 체인이 여전히 통과해야 한다.** 통과한다는 것은 baseline을 옮겼는데도 색
검사 셋이 안 흔들렸다는 뜻이다 — 그 검사들이 배경색 칠한 **공백**을 보기
때문에 글리프 위치와 무관하다(design 결정 7).

- [ ] **Step 4: 커밋**

```bash
git add terminal/src/main.zig
git commit -m "Count the ink on both halves of a wide cell"
```

---

## Task 5: `render/check.sh`에 한글 검사를 더한다

**Files:**
- Modify: `render/check.sh` (색 검사 뒤에 한글 절을 더한다)

**완료선이다.** 사슬 전체를 본다: 셸이 UTF-8 세 바이트를 뱉고 → libghostty-vt가
폭 2칸으로 세고 → 캐시가 굽고 → 렌더러가 두 칸에 걸쳐 찍고 → 프레임버퍼에서
그 잉크를 되읽는다.

- [ ] **Step 1: 한글 절을 더한다**

`render/check.sh`의 **검사 3(커서) 다음, 음성 검사 앞에** 아래를 넣는다.

**넣을 것:**

```bash

# ── 한글을 만든다 (TR-M1) ──────────────────────────────────────────────
#
# printf '\xed\x95\x9c\033[41m \033[0m\n'
#
# \xed\x95\x9c 가 '한'의 UTF-8 세 바이트다. QEMU monitor의 sendkey는 ASCII만
# 칠 수 있으므로 한글을 직접 못 친다 — 셸의 printf가 바이트를 만들어 주는
# 것이 유일한 길이다.
#
# 한글 **바로 뒤에** 배경색 칠한 공백을 붙이는 이유가 요점이다. 그 공백의
# style> 줄이 좌표를 주므로, 게이트가 한글 셀의 열 번호에 2를 더한 값과
# 비교할 수 있다 — 이것이 "다음 글자가 겹치지 않는다"의 **파서 쪽** 증거이고,
# 아래 ink> 검사가 **렌더러 쪽** 증거다. 둘이 따로 틀릴 수 있다.
echo "=== typing printf '\\xed\\x95\\x9c\\033[41m \\033[0m\\n' ==="
type_keys p r i n t f spc apostrophe \
  backslash x e d backslash x 9 5 backslash x 9 c \
  backslash 0 3 3 bracket_left 4 1 m \
  spc \
  backslash 0 3 3 bracket_left 0 m \
  backslash n \
  apostrophe ret
sleep 3

# ── 검사 4: 파서가 '한'을 조립했는가 ───────────────────────────────────
#
# UTF-8 세 바이트가 코드포인트 하나로 합쳐졌다는 뜻이다. 여기서 실패하면
# 셸의 printf가 \x를 해석하지 않은 것일 수 있다 — 그 경우 8진수
# (\355\225\234)로 바꾼다.
if ! grep -aq 'terminal: screen>.*한' "$LOG"; then
  echo "FAIL: '한' never showed up on screen"
  echo "--- what the screen actually held ---"
  grep -a "terminal: screen>" "$LOG" | tail -n 5
  report_failure "the shell's printf did not produce the UTF-8 bytes for U+D55C"
fi
echo "the parser assembled U+D55C from three UTF-8 bytes"

# ── 검사 5: 렌더러가 두 칸에 걸쳐 찍었는가 ─────────────────────────────
#
# **이 체인에서 TR-M1이 더하는 가장 값진 검사다.** left만 있고 right가 0이면
# 글자가 반쪽만 그려진 것인데, 셀 하나만 보는 검사로는 그것을 못 잡는다.
INK_LINE="$(grep -aE 'terminal: ink> [0-9]+,[0-9]+ U\+D55C left=[0-9]+ right=[0-9]+' "$LOG" | tail -n 1)"
if [ -z "$INK_LINE" ]; then
  report_failure "no ink line for U+D55C, so the renderer never treated it as a wide glyph"
fi
echo "ink line: ${INK_LINE}"

INK_LEFT="$(echo "$INK_LINE" | sed -E 's/.*left=([0-9]+).*/\1/')"
INK_RIGHT="$(echo "$INK_LINE" | sed -E 's/.*right=([0-9]+).*/\1/')"
if [ "$INK_LEFT" -eq 0 ] || [ "$INK_RIGHT" -eq 0 ]; then
  report_failure "U+D55C has ink on only one half (left=${INK_LEFT} right=${INK_RIGHT}), so it was drawn as a narrow glyph"
fi
echo "the glyph really covers both cells (left=${INK_LEFT} right=${INK_RIGHT})"

# ── 검사 6: 다음 글자가 두 칸 뒤에 있는가 ──────────────────────────────
#
# 한글 셀의 열 번호에 2를 더한 자리에 빨강 공백이 있어야 한다. 1이면
# 겹친 것이고, 3이면 한 칸을 버린 것이다.
HAN_ROW="$(echo "$INK_LINE" | sed -E 's/.*ink> ([0-9]+),[0-9]+ .*/\1/')"
HAN_COL="$(echo "$INK_LINE" | sed -E 's/.*ink> [0-9]+,([0-9]+) .*/\1/')"
WANT_COL=$((HAN_COL + 2))
if ! grep -aq "terminal: style> ${HAN_ROW},${WANT_COL} fg=[0-9A-F]* bg=CC6666" "$LOG"; then
  echo "FAIL: expected the red space at ${HAN_ROW},${WANT_COL} (right after a 2-cell glyph)"
  echo "--- style lines on that row ---"
  grep -aE "terminal: style> ${HAN_ROW},[0-9]+ " "$LOG" | tail -n 10
  report_failure "the character after U+D55C is not two columns away, so the wide cell was mis-counted"
fi
echo "the next character sits two columns after U+D55C"

# ── 검사 7: 캐시가 자랐고 크기가 말이 되는가 ───────────────────────────
#
# design 위험 3이 "128MB 게스트라 실측한다"고 남긴 자리다. 최악의 경우
# (한글 전체 = 2.06MB)는 font_test가 호스트에서 이미 재고, 여기서 보는 것은
# 실사용량이다. 1MB를 넘으면 무언가 예상과 다르다 — 화면에 나오는 글자는
# 수십 자이고 한 자가 평균 193바이트다.
FONT_LINE="$(grep -a 'terminal: font>' "$LOG" | tail -n 1)"
if [ -z "$FONT_LINE" ]; then
  report_failure "the font cache never reported its size"
fi
echo "font cache: ${FONT_LINE}"
FONT_BYTES="$(echo "$FONT_LINE" | sed -E 's/.*cached, ([0-9]+) bitmap bytes.*/\1/')"
if [ "$FONT_BYTES" -gt 1048576 ]; then
  report_failure "the glyph cache grew past 1MB (${FONT_BYTES} bytes) on a 128MB guest"
fi
echo "the glyph cache is ${FONT_BYTES} bytes, well inside the guest's memory"
```

그리고 스크립트 맨 끝의 통과 문구를 고친다.

**지울 것:**

```bash
echo "TR-M0 PASS: the color the parser resolved is the color in the framebuffer"
```

**넣을 것:**

```bash
echo "--- ink lines ---"
grep -a 'terminal: ink>' "$LOG" | tail -n 10
echo "TR-M1 PASS: colors reach the framebuffer and Hangul covers both of its cells"
```

- [ ] **Step 2: 체인을 돌린다**

Claude가 실행한다(약 2분). **`\x`를 fish의 `printf`가 해석하는지가 여기서
갈린다.**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash render/check.sh 2>&1 | tail -30
```

기대 출력:

```
the parser assembled U+D55C from three UTF-8 bytes
ink line: terminal: ink> N,M U+D55C left=A right=B
the glyph really covers both cells (left=A right=B)
the next character sits two columns after U+D55C
font cache: terminal: font> N glyph(s) cached, M bitmap bytes
the glyph cache is M bytes, well inside the guest's memory
TR-M1 PASS: colors reach the framebuffer and Hangul covers both of its cells
```

**검사 4에서 막히면 `\x`가 원인일 가능성이 가장 높다.** 그 경우 `type_keys`의
`backslash x e d ...`를 8진수 `backslash 3 5 5` / `backslash 2 2 5` /
`backslash 2 3 4`로 바꾸고 다시 돌린다. POSIX `printf`가 규정한 것은 8진수
쪽이라 이식성이 더 높다.

**검사 5에서 `right=0`이 나오면** `drawGlyph`가 폭 2칸을 안 그린 것이다.
`x_offset`을 의심한다 — '한'은 `xoff=1`이고 폭이 15픽셀이라 1~15열을 채운다.

- [ ] **Step 3: 커밋**

```bash
git add render/check.sh
git commit -m "Make the gate prove Hangul covers both of its cells"
```

---

## Task 6: 루트 게이트 3/3

**Files:** 없음(실행만 한다)

- [ ] **Step 1: 일곱 체인을 3회씩 돌린다**

Claude가 실행한다. **약 50분이 걸린다.** 2026-08-23 기준으로 일곱 체인이
46분 4초였고, TR 체인에 한글 명령(약 12초 × 3회)이 더해진다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash check.sh
```

`--platform`을 붙이지 않는다(`project_build_host_arch`).

기대: 일곱 체인이 전부 3/3이다.

**가장 그럴듯한 실패는 baseline 변경의 회귀다.** 글자가 2~5픽셀 움직였으므로,
글리프 위치에 매달린 검사가 있으면 여기서 드러난다. 다섯 체인이 보는
`screen>` 줄은 문자 내용이라 안전하고, TR 체인의 `pixel>`은 공백 셀이라
안전하다 — **안전하다고 보는 근거가 이것이고, 그 근거가 틀렸는지를 이 Step이
확인한다.**

- [ ] **Step 2: 걸린 시간을 적어 둔다**

Task 7의 문서에 들어간다. `project_terminal_rendering.md`의 표에 한 줄
더한다.

---

## Task 7: 문서

**Files:**
- Modify: `docs/decisions/project_terminal_rendering.md`
- Modify: `MEMORY.md` (한 줄 요약 갱신)
- Modify: `docs/superpowers/specs/2026-08-23-tars-terminal-rendering-design.md`
  (위험 3에 결과를 붙인다)
- Rewrite: `HANDOFF.md`

Claude가 쓴다. 담을 것은 다음과 같다.

**기억 파일에 더할 사실:**

- 폰트가 담고 있는 것(완성형 11172자 전부, 한자와 호환 자모는 0자).
- 전부 구우면 2.06MB에 29밀리초라는 상한. **lazy 캐시의 이유가 메모리가
  아니라 시간이라는 것.**
- `coverage`가 완전한 이분값이라는 것(`partial=0`). 문턱값 렌더링의 근거가
  짐작에서 실측이 됐다.
- **`yoff`를 버리고 있었다는 것과 그것을 고친 방식.** 오프셋을 굽는 자리에서
  셀 기준으로 바꿔 렌더러가 baseline을 모르게 했다.
- `cellWidth`의 `> 0x7F` 규칙이 `é`에서 틀렸다는 것.
- `setPixel`·`getPixel`이 범위 검사를 하지 않는다는 것.
- `font_test.zig`가 TR-M1 전까지 **`build.zig`에 등록조차 되어 있지
  않았다**는 것.

**design doc 위험 3에 붙일 결과:** 최악의 경우가 2.06MB이고 실사용은 그보다
두 자릿수 적으므로 **메모리는 위험이 아니었다.**

**`HANDOFF.md`에 적을 것:** TR-M2(스크롤백)가 다음이라는 것, plan에서 어긋난
곳, 이월 숙제(기존 것에 더해 **한글 IME를 붙이면 조합 중인 낱자를 이 폰트로
못 그린다**는 사실).

---

## 완료 조건

design의 TR-M1 절이 적어 둔 것 그대로다.

- [ ] 게스트에서 한글을 찍으면 화면에 나온다 — 검사 4·5가 본다.
- [ ] 폭 2칸이 지켜진다(다음 글자가 겹치지 않는다) — 검사 5·6이 **픽셀과
      좌표 두 겹으로** 본다.
- [ ] 부팅 시간이 눈에 띄게 늘지 않는다 — 미리 굽기를 없앴으므로 오히려
      줄어든다. `render> first frame`이 그 자리를 본다.
- [ ] 루트 게이트 일곱 체인이 3/3이다.
