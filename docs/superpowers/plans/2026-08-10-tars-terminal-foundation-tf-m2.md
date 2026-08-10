# TF-M2 (PTY + libghostty-vt 연동) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.
>
> **이 저장소(tars-linux)는 예외:** `CLAUDE.md`에 명시된 대로 파일 작성과 명령
> 실행은 **사용자가 직접** 하고, Claude는 설명 + 승인된 내용의 git commit만
> 수행하는 pairing 방식을 쓴다. 위 서브스킬들이 기본으로 제안하는
> subagent-driven/inline 자동 실행은 이 저장소에 적용하지 않는다
> (`~/.claude/projects/-Users-dp-Repository-tars-linux/memory/
> feedback_commit_delegation.md`, `feedback_execution_scope.md` 참고).

**Goal:** Terminal Foundation 앱이 `fish`를 PTY(`forkpty`)로 비대화형
실행(`fish --no-config -c "echo \"TARS 하이\""`)하고, 그 출력을
`libghostty-vt`(Zig 네이티브 `Terminal`/`RenderState` API)로 파싱해 얻은
셀 그리드를 TF-M1의 프레임버퍼 렌더러로 그려서 QEMU screendump로 검증한다.

**Architecture:** `terminal/`을 `zig build-exe` 단발 호출에서 `zig build`
프로젝트(`build.zig`+`build.zig.zon`)로 전환해 `ghostty-vt` Zig 모듈을
path dependency로 끌어온다. 새 모듈 `pty.zig`(forkpty + 비대화형 fish 실행)와
`vt.zig`(libghostty-vt Terminal 생성 + ANSI 파싱 + RenderState 셀 추출)를
추가하고, TF-M1의 `drm.zig`/`font.zig`/`drawGlyph`는 그대로 재사용한다.
`pty.zig`/`vt.zig`는 QEMU 없이 devcontainer에서 바로 도는 네이티브 테스트로
먼저 검증한 뒤 `main.zig`에 통합한다.

**Tech Stack:** Zig 0.16.0, `libghostty-vt`(vendored, `terminal/ghostty-src/`),
libc `forkpty()`(`<pty.h>`), 기존 `stb_truetype`/DRM ioctl 코드.

---

## 사전 확인 (Task 0)

이 plan의 코드는 `terminal/ghostty-src/src/lib_vt.zig`, `Terminal.zig`,
`render.zig`, `example/zig-vt/`, `example/zig-vt-stream/`를 직접 읽어서 확보한
실제 함수 시그니처를 기반으로 작성했다(추측 없음). 그래도 사람이 손으로
옮겨 적은 적 없는 코드라 TF-M1처럼 컴파일 에러가 날 수 있다 — 에러가 나면
각 Task의 "만약 ~ 에러가 나면" 절을 먼저 참고하고, 없으면 정상적인 디버깅
루프(에러 메시지 → 원인 설명 → 수정)로 처리한다.

- [x] **Step 1: 현재 상태 확인**

```bash
git log --oneline -3
git status
```

Expected: 최신 커밋이 TF-M1 완료 커밋들이고 working tree가 깨끗함.

---

## Task 1: 빌드 시스템을 `zig build-exe` → `zig build`로 전환

**목적:** `ghostty-vt` Zig 모듈은 `b.dependency()`로 패키지를 해석해야 해서
`zig build-exe` 단발 호출로는 가져올 수 없다. 새 기능을 하나도 추가하기 전에
먼저 빌드 시스템만 바꿔서, TF-M1과 똑같은 결과(배경색 + "TARS 하이" 렌더링)가
그대로 나오는지 확인한다 — 이 Task가 끝나면 "빌드 시스템 자체는 문제없다"는
걸 알고 다음 Task로 넘어갈 수 있다.

**Files:**
- Create: `terminal/build.zig`
- Create: `terminal/build.zig.zon`
- Modify: `terminal/check.sh`

- [x] **Step 1: `terminal/build.zig` 작성**

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .gnu,
        .cpu_model = .baseline,
    });
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addIncludePath(b.path("vendor"));
    exe_mod.addCSourceFile(.{
        .file = b.path("src/stb_truetype_impl.c"),
        .flags = &.{},
    });
    exe_mod.link_libc = true;
    exe_mod.linkSystemLibrary("m", .{});

    const ghostty_dep = b.dependency("ghostty", .{});
    exe_mod.addImport("ghostty-vt", ghostty_dep.module("ghostty-vt"));

    const exe = b.addExecutable(.{
        .name = "terminal",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);
}
```

`-mcpu=baseline`(TF-M1 교훈 6번, 이중 에뮬레이션 환경에서 native CPU 자동
감지가 신뢰 불가)을 `zig build-exe` CLI 플래그 대신 `resolveTargetQuery`의
`.cpu_model = .baseline`로 하드코딩했다 — 매번 `zig build` 호출에 플래그를
안 넘겨도 항상 적용된다.

- [x] **Step 2: `terminal/build.zig.zon` 작성**

```zig
.{
    .name = .tars_terminal,
    .version = "0.0.0",
    .fingerprint = 0x1234567890abcdef,
    .minimum_zig_version = "0.16.0",
    .dependencies = .{
        .ghostty = .{ .path = "ghostty-src" },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
        "vendor",
    },
}
```

**만약 `zig build` 실행 시 `fingerprint mismatch` 또는 비슷한 에러가 나면:**
Zig 패키지 매니저가 이 파일의 고유 식별자로 쓰는 값인데, 위 `0x1234...`는
자리표시용 임의값이라 실제로 맞을 필요는 없지만 Zig가 "이 값이어야 한다"고
알려주는 에러 메시지를 낼 수 있다 — 에러 메시지가 제시하는 정확한 값으로
바꿔서 다시 실행한다.

- [x] **Step 3: `terminal/check.sh`의 빌드 줄 교체**

`terminal/check.sh:18`의 아래 블록을:

```bash
if ! (cd . && zig build-exe src/main.zig src/stb_truetype_impl.c -I vendor -lc -lm -mcpu=baseline -femit-bin=zig-out/terminal); then
  echo "FAIL: terminal build failed"
  exit 1
fi
```

이렇게 교체한다(`-mcpu=baseline`은 이제 `build.zig` 안에 있으므로 CLI에서
뺀다):

```bash
if ! (cd . && zig build); then
  echo "FAIL: terminal build failed"
  exit 1
fi
```

`zig build`의 기본 산출물 경로도 `zig-out/terminal`이라(`b.installArtifact`
기본 설치 prefix가 `zig-out`) 스크립트의 나머지 부분(`../kernel/
make_initrd.sh`가 `../terminal/zig-out/terminal`을 복사하는 부분)은 수정할
필요 없다.

- [x] **Step 4: 로컬에서 `zig build` 확인 (devcontainer 안, QEMU 없이)**

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer zig build
```

Expected: 에러 없이 끝나고 `terminal/zig-out/terminal` 바이너리가 생김.

```bash
ls -la terminal/zig-out/terminal
```

**만약 `ghostty` dependency를 못 찾는다는 에러가 나면:** `terminal/
ghostty-src`가 실제로 존재하는지(`find terminal/ghostty-src/build.zig`) 먼저
확인 — TF-M0에서 vendor된 디렉터리가 `.gitignore`에는 안 걸려있지만
(`terminal/ghostty-src/`가 gitignore에 있음, 즉 커밋되지 않고 로컬에만
있음) 새 clone/컨테이너에서는 다시 받아야 할 수 있다.

- [x] **Step 5: 전체 파이프라인(QEMU 포함) 회귀 확인**

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/check.sh
```

Expected: `PASS`(TF-M1과 동일한 배경색 + 글리프 영역 unique-color 검사).
이 Step은 "빌드 시스템만 바꿨고 기능은 그대로다"를 증명하는 회귀 테스트다.

- [x] **Step 6: Commit**

승인 후 Claude가 커밋한다.

```bash
git add terminal/build.zig terminal/build.zig.zon terminal/check.sh
git commit -m "Migrate terminal build to zig build for ghostty-vt dependency"
```

---

## Task 2: `pty.zig` — forkpty + 비대화형 fish 실행

**목적:** `forkpty()`로 `fish --no-config -c "<명령>"`을 실행하고 그 출력을
읽어오는 최소 모듈을 만든다. QEMU 없이 devcontainer 안에서 바로 도는 네이티브
테스트로 먼저 검증한다(devcontainer에는 이미 `fish`가 설치돼 있음 —
`kernel/make_initrd.sh`가 `/usr/bin/fish`를 거기서 복사해왔다).

**Files:**
- Create: `terminal/src/pty.zig`
- Create: `terminal/src/pty_test.zig`
- Modify: `terminal/build.zig`

- [x] **Step 1: `terminal/src/pty.zig` 작성**

```zig
const std = @import("std");

const c = @cImport({
    @cInclude("pty.h");
    @cInclude("unistd.h");
});

pub const Session = struct {
    master_fd: c_int,
    child_pid: c.pid_t,
};

/// fish를 `-c <command>`로 비대화형 실행한다(프롬프트/설정 파일 없음).
/// PTY(forkpty)를 쓰는 이유는 자식의 stdout/stderr를 PTY slave로 연결해서
/// 실제 터미널처럼 동작하는 경로를 그대로 검증하기 위함이다 — 대화형 입력을
/// 이 함수에서 write할 필요는 없다(`-c`가 명령을 인자로 직접 받음).
pub fn spawnFish(command: [:0]const u8) !Session {
    var master_fd: c_int = undefined;
    const pid = c.forkpty(&master_fd, null, null, null);
    if (pid < 0) return error.ForkptyFailed;

    if (pid == 0) {
        var argv = [_:null]?[*:0]const u8{
            "fish",
            "--no-config",
            "-c",
            command.ptr,
        };
        _ = c.execv("/usr/bin/fish", &argv);
        // execv가 돌아왔다는 건 실패했다는 뜻이다.
        c._exit(127);
    }

    return Session{ .master_fd = master_fd, .child_pid = pid };
}

/// master fd에서 자식이 끝날 때까지(EOF) 나오는 모든 바이트를 읽는다.
/// 호출자가 미리 충분히 큰 buf를 넘긴다(fixed buffer, 동적 할당 없음).
pub fn readAll(fd: c_int, buf: []u8) []const u8 {
    var total: usize = 0;
    while (total < buf.len) {
        const n = c.read(fd, buf.ptr + total, buf.len - total);
        if (n <= 0) break;
        total += @intCast(n);
    }
    return buf[0..total];
}
```

**만약 `error: unable to translate C expr` 등 `pty.h` `@cImport` 에러가
나면:** `pty.h`는 `forkpty` 선언 하나만 필요하므로, `@cInclude("pty.h")`
대신 Zig 코드에 직접 `extern fn forkpty(...) c.pid_t;`로 선언해도 된다
(`stb_truetype.h` 때와 달리 매크로 구현부가 없는 시스템 헤더라 이 문제가
날 가능성은 낮지만, 혹시 나면 이 방법으로 우회한다).

**만약 링크 시 `undefined symbol: forkpty`가 나면:** 오래된 glibc는
`forkpty`가 `libc`가 아니라 `libutil`에 있다 — `terminal/build.zig`의
`exe_mod.linkSystemLibrary("m", .{})` 아래 줄에
`exe_mod.linkSystemLibrary("util", .{});`를 추가한다.

- [x] **Step 2: `terminal/src/pty_test.zig` 작성 (네이티브 테스트)**

```zig
const std = @import("std");
const pty = @import("pty.zig");

pub fn main() !void {
    const session = try pty.spawnFish("echo \"TARS 하이\"");

    var buf: [4096]u8 = undefined;
    const output = pty.readAll(session.master_fd, &buf);

    std.debug.print("pty output ({d} bytes): {s}\n", .{ output.len, output });

    if (std.mem.indexOf(u8, output, "TARS 하이") == null) {
        std.debug.print("FAIL: expected output to contain 'TARS 하이'\n", .{});
        return error.UnexpectedOutput;
    }
    std.debug.print("PASS\n", .{});
}
```

- [x] **Step 3: `terminal/build.zig`에 `pty_test` 실행 파일 추가**

`b.installArtifact(exe);` 다음 줄에 추가:

```zig
    const pty_test_mod = b.createModule(.{
        .root_source_file = b.path("src/pty_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    pty_test_mod.link_libc = true;
    const pty_test = b.addExecutable(.{
        .name = "pty_test",
        .root_module = pty_test_mod,
    });
    b.installArtifact(pty_test);
```

(이 실행 파일은 devcontainer 안에서 native로 바로 돌리는 용도라 `target`은
위에서 정의한 x86_64-linux baseline과 동일하게 써도 무방 — devcontainer 자체가
amd64 컨테이너이므로.)

- [x] **Step 4: devcontainer에서 native 실행으로 검증 (QEMU 불필요)**

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build && ./zig-out/bin/pty_test"
```

Expected: `PASS` 출력, `pty output` 줄에 `TARS 하이`가 포함됨.

**만약 출력이 비어 있거나 타임아웃처럼 멈추면:** `readAll`이 `read()`가
0(EOF)을 반환할 때까지 기다리는데, fish 프로세스가 안 끝났거나 PTY가 안
닫혔을 수 있다 — `child_pid`를 `waitpid()`로 기다리는 로직이 빠져있어서
그럴 수 있으니, 이 경우 `pty.zig`에 `c.waitpid(session.child_pid, null, 0)`
호출을 `readAll` 이후에 추가한다.

- [x] **Step 5: Commit**

```bash
git add terminal/src/pty.zig terminal/src/pty_test.zig terminal/build.zig
git commit -m "Add PTY module running fish non-interactively via forkpty"
```

---

## Task 3: `vt.zig` — libghostty-vt Zig 네이티브 연동

**목적:** `ghostty-vt` Zig 모듈로 터미널을 만들고, 바이트 스트림을 ANSI
파서에 먹인 뒤, `RenderState`로 셀 그리드를 꺼내는 모듈을 만든다. 이번에도
QEMU 없이 네이티브 테스트로 먼저 검증한다 — PTY/fish 없이 하드코딩된 바이트
문자열만으로 `libghostty-vt` 연동 자체가 맞는지 확인한다.

**Files:**
- Create: `terminal/src/vt.zig`
- Create: `terminal/src/vt_test.zig`
- Modify: `terminal/build.zig`

- [x] **Step 1: `terminal/src/vt.zig` 작성**

```zig
const std = @import("std");
const ghostty_vt = @import("ghostty-vt");

pub const CellGlyph = struct {
    codepoint: u32,
    col: u16,
    row: u16,
};

/// bytes를 libghostty-vt로 파싱해(ANSI 이스케이프 포함) 빈 칸이 아닌 셀만
/// 왼쪽-위부터 순서대로 뽑아 반환한다. 색상/스타일은 읽지 않는다(TF-M2
/// 범위 밖 — design 결정 참고).
pub fn parseToCells(
    io: std.Io,
    alloc: std.mem.Allocator,
    bytes: []const u8,
    cols: u16,
    rows: u16,
) ![]CellGlyph {
    var t: ghostty_vt.Terminal = try .init(io, alloc, .{ .cols = cols, .rows = rows });
    defer t.deinit(alloc);

    var stream = t.vtStream();
    defer stream.deinit();
    stream.nextSlice(bytes);

    var state: ghostty_vt.RenderState = .empty;
    defer state.deinit(alloc);
    try state.update(alloc, &t);

    var out: std.ArrayList(CellGlyph) = .empty;
    defer out.deinit(alloc);

    const row_data = state.row_data.slice();
    const row_cells = row_data.items(.cells);
    for (0..state.rows) |y| {
        const cells_slice = row_cells[y].slice();
        const raws = cells_slice.items(.raw);
        for (0..state.cols) |x| {
            const cp = raws[x].codepoint();
            if (cp == 0) continue;
            try out.append(alloc, .{
                .codepoint = @intCast(cp),
                .col = @intCast(x),
                .row = @intCast(y),
            });
        }
    }

    return out.toOwnedSlice(alloc);
}
```

`t.vtStream()`(`Terminal.zig:373`)을 쓰는 이유는 `printString`과 달리 실제
ANSI/VT 이스케이프 시퀀스를 파싱하기 때문이다 — `fish`가 색상 코드를 안 써도
커서 이동 등 다른 이스케이프를 보낼 수 있으므로, PTY에서 온 진짜 바이트는
항상 `vtStream`으로 먹인다(`printString`은 리터럴 텍스트 전용).

- [x] **Step 2: `terminal/src/vt_test.zig` 작성 (네이티브 테스트)**

```zig
const std = @import("std");
const vt = @import("vt.zig");

pub fn main(init: std.process.Init) !void {
    const cells = try vt.parseToCells(
        init.io,
        init.gpa,
        "TARS \xed\x95\x98\xec\x9d\xb4\r\n", // "TARS 하이" (UTF-8) + CRLF
        20,
        5,
    );
    defer init.gpa.free(cells);

    std.debug.print("parsed {d} non-empty cells\n", .{cells.len});
    for (cells) |cell| {
        std.debug.print("  row={d} col={d} codepoint=U+{X}\n", .{ cell.row, cell.col, cell.codepoint });
    }

    if (cells.len == 0) {
        std.debug.print("FAIL: expected non-empty cells\n", .{});
        return error.NoCells;
    }
    // 첫 셀은 'T'(U+0054)여야 한다.
    if (cells[0].codepoint != 'T' or cells[0].row != 0 or cells[0].col != 0) {
        std.debug.print("FAIL: expected first cell to be 'T' at (0,0)\n", .{});
        return error.UnexpectedFirstCell;
    }
    std.debug.print("PASS\n", .{});
}
```

- [x] **Step 3: `terminal/build.zig`에 `vt_test` 실행 파일 추가**

`pty_test` 블록 다음에 추가(이번엔 `ghostty-vt` import가 필요함):

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

- [x] **Step 4: devcontainer에서 native 실행으로 검증 (QEMU 불필요)**

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer bash -c "zig build && ./zig-out/bin/vt_test"
```

Expected: `PASS`, `parsed N non-empty cells` 목록에 `row=0 col=0
codepoint=U+54`("T")부터 시작해 "TARS 하이"에 해당하는 셀들이 순서대로 보임.

**만약 `RenderState`/`row_data`/`.items(.cells)` 관련 컴파일 에러가 나면:**
`terminal/ghostty-src/src/terminal/render.zig`의 `test "basic text"`(약
1235~1270번째 줄)를 열어서 실제 필드/메서드 이름을 다시 대조한다 — 이
plan의 코드는 그 테스트와 `src/renderer/generic.zig`의 `rebuildCells`
(약 2320번째 줄)를 근거로 작성했다.

- [x] **Step 5: Commit**

```bash
git add terminal/src/vt.zig terminal/src/vt_test.zig terminal/build.zig
git commit -m "Add libghostty-vt integration parsing PTY bytes into cell list"
```

---

## Task 4: `main.zig` 통합 + QEMU 전체 파이프라인 검증

**목적:** Task 2(`pty.zig`)와 Task 3(`vt.zig`)를 TF-M1의 `drm.zig`/
`font.zig`와 엮어서, 실제로 QEMU 안에서 fish 출력이 화면에 그려지는 것까지
확인한다.

**Files:**
- Modify: `terminal/src/font.zig` (codepoint로 glyph 찾는 헬퍼 추가)
- Modify: `terminal/src/main.zig`
- Modify: `terminal/check.sh`

- [x] **Step 1: `font.zig`에 `find` 헬퍼 추가**

`terminal/src/font.zig`의 `pub fn build(...)` 함수 뒤에 추가:

```zig
pub fn find(cache: GlyphCache, codepoint: u32) ?Glyph {
    for (cache.glyphs) |glyph| {
        if (glyph.codepoint == codepoint) return glyph;
    }
    return null;
}
```

(glyph 개수가 몇 개 안 되는 고정 목록이라 선형 탐색으로 충분 — 해시맵은
과함, YAGNI.)

- [x] **Step 2: `terminal/src/main.zig`를 PTY+libghostty-vt 파이프라인으로 교체**

```zig
const std = @import("std");
const drm = @import("drm.zig");
const font = @import("font.zig");
const pty = @import("pty.zig");
const vt = @import("vt.zig");

const c = @cImport({
    @cInclude("unistd.h");
});

const BACKGROUND: u32 = 0x00102030;
const TEXT_COLOR: u32 = 0x00FFFFFF;
const GRID_X: u32 = 20;
const GRID_Y: u32 = 20;
const GRID_COLS: u16 = 20;
const GRID_ROWS: u16 = 5;
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

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    const fb = try drm.open(allocator, "/dev/dri/card0");
    fb.fill(BACKGROUND);
    std.debug.print("terminal: filled framebuffer with background\n", .{});

    const font_data = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        "vendor/fonts/Hanme_8x4x4.ttf",
        allocator,
        .unlimited,
    );

    // "TARS 하이" — PTY로 fish에게 시킬 명령이 그대로 만들어낼 출력과
    // 동일한 코드포인트 집합을 미리 래스터라이징해둔다.
    const codepoints = [_]u32{ 'T', 'A', 'R', 'S', ' ', 0xD558, 0xC774 };
    const cache = try font.build(allocator, font_data, &codepoints);

    const session = try pty.spawnFish("echo \"TARS 하이\"");
    var pty_buf: [4096]u8 = undefined;
    const pty_output = pty.readAll(session.master_fd, &pty_buf);
    std.debug.print("terminal: read {d} bytes from pty\n", .{pty_output.len});

    const cells = try vt.parseToCells(init.io, allocator, pty_output, GRID_COLS, GRID_ROWS);

    var x: u32 = GRID_X;
    var last_row: u16 = 0;
    for (cells) |cell| {
        if (cell.row != last_row) {
            x = GRID_X;
            last_row = cell.row;
        }
        if (font.find(cache, cell.codepoint)) |glyph| {
            const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
            drawGlyph(fb, glyph, x, y);
            x += glyph.cell_width;
        }
    }
    std.debug.print("terminal: rendered {d} cells from pty output\n", .{cells.len});
    try fb.present();

    while (true) {
        _ = c.sleep(1);
    }
}
```

`font.find`가 `null`을 돌려주는(즉 미리 래스터라이징 안 해둔) 코드포인트는
그냥 건너뛴다 — Task 3에서 이미 fish를 `--no-config -c`로 비대화형 실행하기로
했으므로 프롬프트가 안 찍히고, `echo`의 출력은 우리가 보낸 문자열
그대로여야 하지만, 혹시 예상 못 한 문자(예: 개행 처리 중 생기는 커서 이동
이스케이프 잔여물)가 섞여도 화면이 깨지지 않고 조용히 무시되도록 하는
방어적 처리다.

- [x] **Step 3: `terminal/build.zig`의 메인 `exe_mod`에 `pty.zig`/`vt.zig` 접근
      가능하게 하기**

`main.zig`가 `@import("pty.zig")`/`@import("vt.zig")`를 상대 경로로 바로
가져오므로(같은 `src/` 디렉터리) 별도 module 등록 없이 그대로 컴파일된다 —
Task 1의 `exe_mod`에 이미 `ghostty-vt` import가 걸려있으므로 이 Step은
수정할 코드가 없다. **확인만** 한다:

```bash
rg -n "ghostty-vt" terminal/build.zig
```

Expected: `exe_mod.addImport("ghostty-vt", ...)` 줄이 보임(Task 1 Step 1에서
이미 추가됨).

- [x] **Step 4: `terminal/check.sh`의 crop 좌표를 새 렌더링 위치에 맞게 조정**

기존 `terminal/check.sh`의 글리프 영역 검사(약 110번째 줄 근처)는:

```bash
UNIQUE_COLORS=$("${CONVERT[@]}" "${SCREENSHOT}" -crop 72x16+20+20 +repage \
  -format "%k" info: 2>&1) || {
```

렌더링 시작 좌표(`GRID_X=20, GRID_Y=20`)는 TF-M1과 동일하므로 이 crop
좌표는 그대로 유지해도 된다 — "TARS 하이"가 여전히 `(20,20)`부터 첫 줄
(`row=0`)에 그려지기 때문이다. **수정 불필요**, 그대로 둔다.

- [x] **Step 5: 로컬 `zig build`로 컴파일만 우선 확인**

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/terminal \
  tars-devcontainer zig build
```

Expected: 에러 없이 `zig-out/bin/terminal` 생성.

- [x] **Step 6: 전체 QEMU 파이프라인 검증**

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/check.sh
```

Expected: `PASS`. 이전 세션의 교훈대로 `sleep 30`으로도 fish 기동 + PTY
왕복이 다 안 끝났다면(로그에서 `terminal: rendered N cells` print가 serial
log에 아예 안 보이는 등) `terminal/check.sh`의 `sleep 30`을 더 늘린다.

- [x] **Step 7: screendump 육안 확인**

TF-M1 때처럼 `terminal/check.sh`는 이미 screendump를 `/workspace`(저장소
루트)에 남기도록 되어 있다(TF-M1 세션에서 이미 이렇게 바꿔둠). `PASS` 후
저장소 루트의 `tf-m1-*.ppm`(파일명은 그대로 `tf-m1-` 접두사를 쓰고
있음 — 원한다면 이번에 `tf-m2-`로 바꿔도 되고 안 바꿔도 동작에는 지장
없음)을 열어서 "TARS 하이"가 실제로 보이는지 확인한다:

```bash
sips -s format png tf-m1-XXXXXX.ppm --out tf-m2-screenshot.png
open tf-m2-screenshot.png
```

- [x] **Step 8: Commit**

```bash
git add terminal/src/font.zig terminal/src/main.zig terminal/check.sh
git commit -m "Render fish output parsed via libghostty-vt to framebuffer"
```

---

## TF-M2 완료 확인 체크리스트

- [x] `zig build`(Task 1)로 TF-M1과 동일한 결과가 나오는 회귀 테스트 통과
- [x] `pty_test`(Task 2)가 네이티브로 `fish -c "echo ..."` 출력을 PTY로
      받아옴을 확인
- [x] `vt_test`(Task 3)가 네이티브로 바이트 스트림 → 셀 목록 변환이 맞음을
      확인
- [x] `terminal/check.sh` 전체 QEMU 파이프라인이 `PASS`
- [x] screendump 육안 확인 완료
- [x] HANDOFF.md 갱신 + TF-M3(키보드 입력) 브레인스토밍으로 이어갈 준비

---

## 실제 실행에서 plan과 달라진 점 (2026-08-10 완료 시점 기록)

plan 대비 네 가지가 달랐다. 다음 milestone에서 같은 함정을 반복하지 않기
위해 이유까지 남긴다.

1. **`b.dependency("ghostty", .{})`에 target/optimize를 넘겨야 했다**
   (Task 1 Step 1). ghostty는 `src/build/Config.zig:75,86`에서
   `b.standardTargetOptions()`로 자기 타겟을 정하므로, 옵션을 안 넘기면
   `ghostty-vt` 모듈이 호스트 native 타겟으로 만들어져 우리 exe의
   `cpu_model = .baseline`과 어긋난다.

2. **`zig build`의 설치 경로는 `zig-out/bin/`이다** (Task 1 Step 3).
   plan은 "경로가 그대로라 `make_initrd.sh` 수정 불필요"라고 적었지만
   틀렸다 — `zig build-exe -femit-bin=zig-out/terminal`과 달리
   `b.installArtifact`는 `bin/` 하위에 넣는다. `kernel/make_initrd.sh:23`을
   `../terminal/zig-out/bin/terminal`로 고쳤다. 겸사겸사 TF-M1이 남긴
   낡은 `zig-out/terminal`을 지웠다 — 안 지우면 빌드 실패 시에도 낡은
   바이너리로 initrd가 조용히 만들어져 유령 버그가 된다.

3. **`c.execv` 대신 `execv`를 직접 extern 선언했다** (Task 2 Step 1).
   glibc의 `char *const argv[]`를 translate-c가 `[*c]const [*c]u8`
   (비-const `u8` 포인터의 배열)로 옮기기 때문에 Zig의
   `?[*:0]const u8` 배열을 그대로 넘길 수 없다. `@constCast`로 벗기느니
   const가 맞는 시그니처로 선언하는 쪽을 택했다.

4. **init이 devpts를 마운트해야 했다** (plan에 아예 없던 단계).
   `forkpty()`는 `/dev/ptmx`를 연 뒤 `/dev/pts/N`을 열어야 하는데,
   devtmpfs는 드라이버가 등록한 장치 노드만 담으므로 `/dev/pts`를
   만들어주지 않는다. `init/src/main.rs`에 `mount_devpts()`를 추가해
   devtmpfs 마운트 **뒤**·`run_terminal()` **앞**에서
   `mkdir /dev/pts` + `mount devpts`를 하도록 했다. 커널 쪽은
   `kernel/.config:997 CONFIG_UNIX98_PTYS=y`라 이미 준비돼 있었다.

   **이 항목이 이번 milestone의 가장 큰 교훈이다.** Task 2의 네이티브
   테스트가 통과한 건 Docker가 컨테이너에 devpts를 이미 마운트해줬기
   때문이고, QEMU에서는 그 일을 우리 init이 직접 해야 했다. "devcontainer
   에서 되니까 QEMU에서도 된다"는 추론은 **호스트 환경이 대신 해주던 설정**
   에서 깨진다 — 새 시스템 콜/장치를 쓸 때마다 "이게 동작하려면 누가 무엇을
   마운트·생성해줘야 하는가"를 먼저 확인할 것.
