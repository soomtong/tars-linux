# TARS Render Cost RC-M0 — Implementation Plan

**Date:** 2026-08-30
**Design:** `docs/superpowers/specs/2026-08-30-tars-render-cost-design.md`
(결정 1~6, 해석 계획, 검산 1~3, 위험 1~4)
**앞 서브프로젝트:** Search Position(SP-M0·M1, 2026-08-29~30)

**Goal:** 한 프레임의 비용을 여섯 구간으로 갈라 재고, "첫 프레임 비용의 출처가
무엇인가"라는 이월 숙제에 한 문장으로 답한다.

**Architecture:** 저장소 파일을 안 고친다. `main.zig`와 `drm.zig`의 **사본**을
패치 스크립트로 만들어 원본 자리에 read-only로 마운트하고, 게스트를 부팅해
프레임마다 `terminal: probe> …` 한 줄을 시리얼에 남긴다. 로그를 `out/probe/`로
빼내 호스트에서 집계한다.

**Tech Stack:** Zig 0.16 · QEMU(x86_64, TCG) · Docker(`tars-devcontainer`) ·
Python 3(패치 스크립트) · awk(집계)

---

## 이 milestone에는 TDD가 없다. 대신 검산이 앞선다

이 저장소의 다른 milestone은 "검사를 먼저 쓰고 실패를 보고 구현한다"로 갔다.
**RC-M0은 구현이 없다** — 재기만 한다. 그래서 그 규율에 해당하는 자리는
**"값을 보기 전에 검산과 해석 계획을 정해 두는 것"**이고, design에 이미 적었다.

**Task 4가 그 검산이다.** `total`과 여섯 구간의 합이 5% 안에서 안 맞으면
**값을 해석하지 않고 프로브를 먼저 고친다.** 이 순서를 어기면 새는 구간이 있는
채로 "`fill`이 지배적이다" 같은 결론을 내게 된다.

## Task 목록

| Task | 무엇 | 산출물 |
|---|---|---|
| 1 | 패치 스크립트로 프로브 판 둘을 만든다 | `/tmp/probe_patch.py` → `/tmp/probe_main.zig` · `/tmp/probe_drm.zig` |
| 2 | 부팅 전에 컴파일만 통과시킨다 | — |
| 3 | 프로브 러너를 만들고 1회 부팅한다 | `/tmp/probe_run.sh` · `out/probe/run1.log` |
| 4 | **검산**: `total` 대 구간 합 | — |
| 5 | 부팅 3회를 모은다 | `out/probe/run{1,2,3}.log` |
| 6 | 집계하고 해석 계획 표와 대조한다 | — |
| 7 | design에 실측 절을 더하고 HANDOFF·기억을 갱신한다 | 저장소 파일 넷 |

**Task 1~6은 저장소 파일을 한 줄도 안 바꾼다.** 바뀌는 것은 Task 7뿐이고 전부
문서다.

## 착수 전에 소스로 확정한 것

**전부 `terminal/src/`를 직접 읽어서 얻었고 짐작이 없다.**

1. **`render()`는 `io`를 못 본다.** `init`은 `main()`의 매개변수다
   (`main.zig:530`). 그래서 프로브가 `render()`에 `io: std.Io`를 더하고 호출부
   한 줄을 고친다. 타입 이름은 `vt.zig:112`의 `io: std.Io`와 같다.
2. **`present()`가 매 프레임 시리얼에 한 줄을 쓴다**(`drm.zig:186`). 지우지
   않으면 `present` 값이 ioctl이 아니라 시리얼 콘솔의 비용이 된다.
3. **`drawGlyph`의 호출부는 둘이다** — `render`의 글리프 루프(`main.zig:155`)와
   `drawPrompt`(`main.zig:116`). 반환값을 더하면 둘 다 고쳐야 한다.
4. **`main()`이 루프 전에 `fill` + `present`를 한 번 한다**(`main.zig:533-534`).
   그것은 `render()` 밖이라 프로브가 안 잰다. **첫 `probe>` 줄은 그 뒤의 첫
   `render()`다.**
5. **빌드 산출물이 전부 이미 있다.** `kernel/build/arch/x86/boot/bzImage` ·
   `kernel/initrd.cpio` · `terminal/vendor` · `terminal/ghostty-src` ·
   `terminal/zig-out`. 그래서 프로브 회차는 clean이 아니라 **증분**이고,
   커널은 GL-M1의 스탬프 때문에 `skipping make`로 지나간다.
6. **게이트의 어떤 검사도 `render> first frame` 줄을 안 본다.**
   `rg 'first frame' --glob '*/check.sh'`가 하나도 안 나온다. 프로브가 그 줄
   옆에 새 줄을 더해도 판정에 안 닿는다 — 애초에 프로브는 마운트라 게이트와
   만나지도 않는다.

## Task 1: 패치 스크립트로 프로브 판 둘을 만든다

**Files:**
- Create: `/tmp/probe_patch.py`
- Create(생성물): `/tmp/probe_main.zig` · `/tmp/probe_drm.zig`
- Read only: `terminal/src/main.zig` · `terminal/src/drm.zig`

**왜 손으로 옮겨 적지 않는가.** `main.zig`가 900줄이 넘는다. 손으로 사본을
만들면 **원본과 조용히 어긋날 수 있고**, 그러면 재는 대상이 제품이 아니게 된다.
치환 스크립트는 **anchor가 정확히 한 번 나오는지 단언**하므로, 원본이 바뀌면
조용히 틀리는 대신 시끄럽게 실패한다.

- [ ] **Step 1: 패치 스크립트를 쓴다**

```python
#!/usr/bin/env python3
"""RC-M0 프로브 판 생성기.

terminal/src/{main,drm}.zig를 읽어 계측을 끼운 사본을 /tmp에 쓴다.
저장소 파일은 열기만 하고 절대 쓰지 않는다.

각 치환의 anchor가 정확히 한 번 나오는지 단언한다 — 원본이 바뀌어
anchor가 사라지면 조용히 틀린 사본을 만드는 대신 여기서 멈춘다.
"""
import pathlib
import sys

SRC = pathlib.Path("terminal/src")
OUT = pathlib.Path("/tmp")


def sub(text: str, old: str, new: str, label: str) -> str:
    n = text.count(old)
    if n != 1:
        sys.exit(f"anchor {label!r}: expected 1 occurrence, found {n}")
    return text.replace(old, new)


# ---------------------------------------------------------------- drm.zig
drm = (SRC / "drm.zig").read_text()

# 결정 4: present()의 시리얼 print를 지운다. 그대로 두면 present 값이
# ioctl이 아니라 시리얼 콘솔의 비용을 말하게 된다.
drm = sub(
    drm,
    '        try drmIoctl(self.fd, drmIowr(DrmModeCrtc, 0xA2), @ptrCast(&crtc));\n'
    '        std.debug.print("kms: set crtc {d} to fb {d}\\n", .{ self.crtc_id, self.fb_id });\n',
    '        try drmIoctl(self.fd, drmIowr(DrmModeCrtc, 0xA2), @ptrCast(&crtc));\n',
    "drm/present-print",
)

(OUT / "probe_drm.zig").write_text(drm)

# --------------------------------------------------------------- main.zig
main = (SRC / "main.zig").read_text()

# (1) drawGlyph가 찍은 픽셀 수를 반환하게 한다. ink를 세는 유일한 방법이다.
main = sub(
    main,
    "fn drawGlyph(fb: drm.Framebuffer, glyph: font.Glyph, x: u32, y: u32, color: u32) void {\n"
    "    const bitmap = glyph.bitmap orelse return;",
    "fn drawGlyph(fb: drm.Framebuffer, glyph: font.Glyph, x: u32, y: u32, color: u32) u32 {\n"
    "    var ink: u32 = 0;\n"
    "    const bitmap = glyph.bitmap orelse return 0;",
    "main/drawGlyph-signature",
)
main = sub(
    main,
    "            const coverage = bitmap[row * glyph.width + col];\n"
    "            if (coverage > 127) {\n"
    "                fb.setPixel(@intCast(px), @intCast(py), color);\n"
    "            }\n"
    "        }\n"
    "    }\n"
    "}\n",
    "            const coverage = bitmap[row * glyph.width + col];\n"
    "            if (coverage > 127) {\n"
    "                fb.setPixel(@intCast(px), @intCast(py), color);\n"
    "                ink += 1;\n"
    "            }\n"
    "        }\n"
    "    }\n"
    "    return ink;\n"
    "}\n",
    "main/drawGlyph-body",
)

# (2) drawPrompt의 호출부는 반환값을 버린다.
main = sub(
    main,
    "        drawGlyph(fb, glyph, GRID_X + col * CELL_W, y, fg);\n",
    "        _ = drawGlyph(fb, glyph, GRID_X + col * CELL_W, y, fg);\n",
    "main/drawPrompt-call",
)

# (3) render를 통째로 계측판으로 바꾼다. 원본은 아래 REPLACED_RENDER의
#     첫 인자와 글자 그대로 같아야 하고, 다르면 anchor 단언이 막는다.
OLD_RENDER = """fn render(
    fb: drm.Framebuffer,
    cache: *font.Cache,
    cells: []const vt.CellGlyph,
    prompt: ?Prompt,
) !void {
    // 여백(격자 바깥)만 상수로 칠한다. 격자 안은 아래에서 셀마다 덮는다.
    fb.fill(MARGIN_COLOR);
"""

NEW_RENDER = """/// RC-M0 프로브. 여백만 칠하는 반사실을 fill **앞**에 둔다(design 결정 3) —
/// 뒤에 두면 fill이 데워 놓은 write-combining 버퍼 위에서 재게 된다.
fn fillMargin(fb: drm.Framebuffer, cols: u32, rows: u32, color: u32) u32 {
    const grid_w = cols * CELL_W;
    const grid_h = rows * ROW_HEIGHT;
    var painted: u32 = 0;
    var y: u32 = 0;
    while (y < fb.height) : (y += 1) {
        const inside_y = y >= GRID_Y and y < GRID_Y + grid_h;
        var x: u32 = 0;
        while (x < fb.width) : (x += 1) {
            if (inside_y and x >= GRID_X and x < GRID_X + grid_w) continue;
            fb.setPixel(x, y, color);
            painted += 1;
        }
    }
    return painted;
}

fn render(
    io: std.Io,
    fb: drm.Framebuffer,
    cache: *font.Cache,
    cells: []const vt.CellGlyph,
    prompt: ?Prompt,
) !void {
    const t_start = std.Io.Clock.now(.awake, io);

    const grid_cols: u32 = (fb.width - 2 * GRID_X) / CELL_W;
    const grid_rows: u32 = (fb.height - 2 * GRID_Y) / ROW_HEIGHT;
    const t0 = std.Io.Clock.now(.awake, io);
    const margin_px = fillMargin(fb, grid_cols, grid_rows, MARGIN_COLOR);
    const ns_margin = t0.untilNow(io, .awake).nanoseconds;

    // 여백(격자 바깥)만 상수로 칠한다. 격자 안은 아래에서 셀마다 덮는다.
    const t1 = std.Io.Clock.now(.awake, io);
    fb.fill(MARGIN_COLOR);
    const ns_fill = t1.untilNow(io, .awake).nanoseconds;
"""

main = sub(main, OLD_RENDER, NEW_RENDER, "main/render-head")

OLD_BG = """    for (cells) |cell| {
        const x = GRID_X + @as(u32, cell.col) * CELL_W;
        const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
        drawCellBackground(fb, x, y, cell.bg);
    }
"""
NEW_BG = """    const t2 = std.Io.Clock.now(.awake, io);
    for (cells) |cell| {
        const x = GRID_X + @as(u32, cell.col) * CELL_W;
        const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
        drawCellBackground(fb, x, y, cell.bg);
    }
    const ns_bg = t2.untilNow(io, .awake).nanoseconds;
"""
main = sub(main, OLD_BG, NEW_BG, "main/render-bg")

OLD_GLYPH = """    for (cells) |cell| {
        // 빈 셀은 배경만 칠하고 끝난다. 캐시에 codepoint 0을 넣지 않기
        // 위해서이기도 하다 — 커서 자리와 색 띠가 전부 이쪽이라 흔하다.
        if (cell.codepoint == 0) continue;
        const x = GRID_X + @as(u32, cell.col) * CELL_W;
        const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
        const glyph = try cache.find(cell.codepoint);
        drawGlyph(fb, glyph, x, y, cell.fg);
    }

    if (prompt) |p| {
        try drawPrompt(fb, cache, p.text, p.rows, p.cols, p.fg, p.bg);
    }

    try fb.present();
}
"""
NEW_GLYPH = """    const t3 = std.Io.Clock.now(.awake, io);
    var ink: u32 = 0;
    for (cells) |cell| {
        // 빈 셀은 배경만 칠하고 끝난다. 캐시에 codepoint 0을 넣지 않기
        // 위해서이기도 하다 — 커서 자리와 색 띠가 전부 이쪽이라 흔하다.
        if (cell.codepoint == 0) continue;
        const x = GRID_X + @as(u32, cell.col) * CELL_W;
        const y = GRID_Y + @as(u32, cell.row) * ROW_HEIGHT;
        const glyph = try cache.find(cell.codepoint);
        ink += drawGlyph(fb, glyph, x, y, cell.fg);
    }
    const ns_glyph = t3.untilNow(io, .awake).nanoseconds;

    const t4 = std.Io.Clock.now(.awake, io);
    if (prompt) |p| {
        try drawPrompt(fb, cache, p.text, p.rows, p.cols, p.fg, p.bg);
    }
    const ns_prompt = t4.untilNow(io, .awake).nanoseconds;

    const t5 = std.Io.Clock.now(.awake, io);
    try fb.present();
    const ns_present = t5.untilNow(io, .awake).nanoseconds;

    const ns_total = t_start.untilNow(io, .awake).nanoseconds;
    std.debug.print(
        "terminal: probe> total={d} margin={d} fill={d} bg={d} glyph={d}" ++
            " prompt={d} present={d} cells={d} ink={d} margin_px={d}\\n",
        .{
            ns_total, ns_margin, ns_fill,   ns_bg,  ns_glyph,
            ns_prompt, ns_present, cells.len, ink,  margin_px,
        },
    );
}
"""
main = sub(main, OLD_GLYPH, NEW_GLYPH, "main/render-glyph")

# (4) 호출부에 io를 넘긴다.
main = sub(
    main,
    "        try render(fb, &cache, cells, prompt);\n",
    "        try render(init.io, fb, &cache, cells, prompt);\n",
    "main/render-call",
)

(OUT / "probe_main.zig").write_text(main)
print("wrote /tmp/probe_main.zig /tmp/probe_drm.zig")
```

- [ ] **Step 2: 돌린다**

```bash
python3 /tmp/probe_patch.py
```

기대: `wrote /tmp/probe_main.zig /tmp/probe_drm.zig`.
**anchor 하나라도 어긋나면** `anchor 'main/render-bg': expected 1 occurrence,
found 0`처럼 멈춘다 — 그때는 원본을 다시 읽어 anchor를 맞춘다.

- [ ] **Step 3: 저장소가 안 바뀐 것을 확인한다**

```bash
git status --short
```

기대: **아무 줄도 안 나온다.** 한 줄이라도 나오면 스크립트가 저장소에 쓴
것이므로 즉시 되돌린다.

- [ ] **Step 4: 사본이 실제로 달라졌는지 눈으로 본다**

```bash
diff terminal/src/main.zig /tmp/probe_main.zig | head -60
diff terminal/src/drm.zig /tmp/probe_drm.zig
```

기대: `drm.zig` 쪽은 **`std.debug.print("kms: set crtc …` 한 줄만 사라진다.**
`main.zig` 쪽은 치환 다섯 자리만 바뀐다.

## Task 2: 부팅 전에 컴파일만 통과시킨다

**Files:** 없음(마운트만)

**왜 따로 두는가.** 부팅까지 가면 한 회차가 몇 분이다. **Zig 컴파일 오류는
1분 안에 걷어낼 수 있고**, 그것을 부팅 뒤에 발견하면 그 몇 분을 버린다.

- [ ] **Step 1: 마운트할 두 판이 실제로 있는지 먼저 본다**

```bash
ls -l /tmp/probe_main.zig /tmp/probe_drm.zig
```

**위험 1이 여기서 막힌다** — 없는 파일을 `-v`로 마운트하면 Docker가 호스트에
0바이트 파일을 만들고 그것이 남는다.

- [ ] **Step 2: 프로브 판으로 빌드만 한다**

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/probe_main.zig:/workspace/terminal/src/main.zig:ro \
  -v /tmp/probe_drm.zig:/workspace/terminal/src/drm.zig:ro \
  -w /workspace/terminal tars-devcontainer bash -c 'zig build 2>&1 | tail -40'
```

기대: 아무 에러 없이 끝난다(약 30초). 에러가 나면 `error:` 줄을 읽고 Task 1의
치환을 고친다.

**자주 나올 만한 것 둘.** (a) `unused local variable` — Zig가 안 쓰는 지역을
에러로 막는다. `margin_px`·`ink`를 `probe>` 줄이 전부 쓰고 있으므로 나오면
치환이 덜 들어간 것이다. (b) `expected type 'std.Io'` — 호출부 치환
(`main/render-call`)이 빠진 것이다.

## Task 3: 프로브 러너를 만들고 1회 부팅한다

**Files:**
- Create: `/tmp/probe_run.sh`
- Create(산출물): `out/probe/run1.log`

- [ ] **Step 1: 러너를 쓴다**

```bash
cat > /tmp/probe_run.sh <<'EOF'
#!/usr/bin/env bash
# RC-M0 프로브 러너. 컨테이너 안에서 돈다.
# 인자 하나: 회차 번호(로그 파일 이름에 쓴다).
set -uo pipefail
RUN="${1:?run number}"
cd /workspace/terminal

# 커널은 GL-M1의 스탬프로 건너뛴다. init과 terminal은 다시 빌드한다 —
# main.zig가 마운트로 바뀌었으므로 terminal은 실제로 다시 컴파일된다.
(cd ../kernel && ./build.sh)   || { echo "FAIL: kernel"; exit 1; }
(cd ../init && zig build)      || { echo "FAIL: init"; exit 1; }
./prepare.sh                   || { echo "FAIL: terminal"; exit 1; }
(cd ../kernel && ./make_initrd.sh) || { echo "FAIL: initrd"; exit 1; }

PORT=45470
LOG="$(mktemp)"
qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!
trap 'kill "$QEMU_PID" 2>/dev/null; wait "$QEMU_PID" 2>/dev/null' EXIT

# monitor가 열릴 때까지. terminal/check.sh:73~79와 같은 방식이고
# 첫 시도의 "Connection refused"는 실패가 아니다.
for _ in $(seq 1 20); do
  exec 3<>"/dev/tcp/127.0.0.1/${PORT}" && break
  sleep 0.5
done

# 첫 프레임이 나올 때까지. 이 줄이 뜨면 DRM·폰트·evdev·셸이 전부 끝났다.
for _ in $(seq 1 120); do
  grep -q "terminal: screen>" "$LOG" && break
  sleep 1
done

send() { echo "sendkey $1" >&3; sleep 0.4; }

# (a) 셸에 명령을 하나 쳐서 글자가 찬 화면의 프레임을 만든다.
send l; send s; send ret
sleep 2
# (b) copy mode에 들어가 오버레이가 있는 프레임을 만든다 — prompt 구간이
#     0이 아닌 프레임이 있어야 그 값을 읽을 수 있다.
send meta_l-shift-c
send slash
send a
sleep 1
send esc
sleep 2

mkdir -p /workspace/out/probe
cp "$LOG" "/workspace/out/probe/run${RUN}.log"
echo "probe lines: $(grep -ac 'terminal: probe>' "$LOG")"
EOF
chmod +x /tmp/probe_run.sh
```

**`sendkey`의 키 이름은 전부 소문자다**(실측 6) — `slash` · `ret` · `esc` ·
`meta_l-shift-c`를 쓴다.

- [ ] **Step 2: 1회차를 돌린다**

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/probe_main.zig:/workspace/terminal/src/main.zig:ro \
  -v /tmp/probe_drm.zig:/workspace/terminal/src/drm.zig:ro \
  -v /tmp/probe_run.sh:/probe_run.sh:ro \
  -w /workspace tars-devcontainer bash /probe_run.sh 1
```

기대: 마지막 줄이 `probe lines: N`이고 **N이 10 이상**이다. 0이면 프로브
`print`가 안 도달한 것이므로 Task 1로 돌아간다.

- [ ] **Step 3: 해상도를 확인한다 (design의 "역산한 값" 각주)**

```bash
grep -a 'terminal: grid' out/probe/run1.log
```

기대: `terminal: grid 155x47 (fb 1280x800)`. **다르면 design의 픽셀 수 표를
다시 계산하고 집계 기준도 그 값으로 바꾼다.**

- [ ] **Step 4: `margin_px`가 산수와 맞는지 본다**

```bash
grep -ao 'margin_px=[0-9]*' out/probe/run1.log | sort -u
```

기대: `margin_px=91520` 하나만 나온다. 다르면 `fillMargin`의 경계가 틀린
것이고, 그러면 반사실 값이 여백이 아닌 것을 재고 있다.

## Task 4: 검산 — `total`과 구간 합이 맞는가

**Files:** 없음

**이것이 이 milestone의 문지기다.** 통과 못 하면 다음 Task로 안 간다.

- [ ] **Step 1: 프레임마다 합과 `total`의 차이를 낸다**

```bash
grep -a 'terminal: probe>' out/probe/run1.log \
| sed 's/.*probe> //' \
| awk '{
    for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
    sum = v["margin"] + v["fill"] + v["bg"] + v["glyph"] + v["prompt"] + v["present"]
    d = v["total"] - sum
    pct = (v["total"] > 0) ? 100.0 * d / v["total"] : 0
    printf "total=%d sum=%d diff=%d (%.2f%%)\n", v["total"], sum, d, pct
  }'
```

기대: 모든 줄의 `%`가 **-5% ~ +5%** 안이다.

- [ ] **Step 2: 벗어난 줄이 있으면 멈추고 원인을 가른다**

| 모양 | 뜻 | 처방 |
|---|---|---|
| `diff`가 크게 **양수** | 못 잰 구간이 있다 | `render()`에서 계시 밖에 남은 코드를 찾는다 |
| `diff`가 **음수** | 구간이 겹쳐 이중으로 셌다 | 시계 시작점이 잘못 잡혔다 |
| 첫 줄만 벗어남 | TCG 번역 비용(위험/검산 2) | **첫 프레임은 따로 읽기로 이미 정했다.** 나머지가 안 벗어나면 통과다 |

## Task 5: 부팅 3회를 모은다

**Files:** 산출물 `out/probe/run2.log` · `out/probe/run3.log`

**왜 3회인가.** 검산 2가 "부팅 세 번에서 구간 순위가 같다"를 요구한다. 이
게이트의 시간은 잡음이 크고(±3분 수준), 한 회차의 값만으로 순위를 말하면
그 잡음을 결론으로 옮기게 된다.

- [ ] **Step 1: 2회차와 3회차를 돌린다**

```bash
for n in 2 3; do
  docker run --rm -v "$PWD":/workspace \
    -v /tmp/probe_main.zig:/workspace/terminal/src/main.zig:ro \
    -v /tmp/probe_drm.zig:/workspace/terminal/src/drm.zig:ro \
    -v /tmp/probe_run.sh:/probe_run.sh:ro \
    -w /workspace tars-devcontainer bash /probe_run.sh "$n"
done
```

**한 회차가 2~4분이다.** 둘이면 8분을 넘을 수 있으므로 `run_in_background`로
돌린다(협업 규칙: 긴 명령은 시간을 미리 알린다).

- [ ] **Step 2: 세 회차가 다 모였는지 본다**

```bash
for n in 1 2 3; do
  printf 'run%s: %s frames\n' "$n" "$(grep -ac 'terminal: probe>' out/probe/run$n.log)"
done
```

기대: 세 줄 다 10 이상.

## Task 6: 집계하고 해석 계획 표와 대조한다

**Files:** 없음

- [ ] **Step 1: 회차별로 첫 프레임을 따로 떼고 나머지의 중앙값을 낸다**

```bash
for n in 1 2 3; do
  echo "=== run$n"
  grep -a 'terminal: probe>' out/probe/run$n.log | sed 's/.*probe> //' > /tmp/f$n.txt
  echo "-- 첫 프레임"
  head -1 /tmp/f$n.txt
  echo "-- 나머지 중앙값(ns)"
  for k in total margin fill bg glyph prompt present; do
    tail -n +2 /tmp/f$n.txt \
    | grep -ao "$k=[0-9]*" | cut -d= -f2 | sort -n \
    | awk -v K="$k" '{a[NR]=$1} END {if (NR) printf "%-8s %d  (n=%d)\n", K, a[int((NR+1)/2)], NR}'
  done
done
```

- [ ] **Step 2: 픽셀당 비용을 낸다 — 이것이 갈림을 정한다**

```bash
# 분모: margin 91,520 · fill 1,024,000 · bg = cells*128 · glyph = ink
tail -n +2 /tmp/f1.txt | awk '{
    for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
    if (v["ink"] > 0)
      printf "margin=%.2f fill=%.2f bg=%.2f glyph=%.2f ns/px\n",
        v["margin"]/v["margin_px"], v["fill"]/1024000.0,
        v["bg"]/(v["cells"]*128.0), v["glyph"]/v["ink"]
  }' | sort | uniq -c | sort -rn | head
```

- [ ] **Step 3: design의 해석 계획 표와 대조해 결론을 한 문장으로 적는다**

design의 표를 그대로 쓴다. **표에 없는 모양이 나오면 결론을 짓지 않고 그
사실을 그대로 적는다** — 값을 보고 이야기를 짓지 않기 위해 표를 미리 쓴
것이다.

**절대값을 실제 하드웨어의 것으로 옮겨 적지 않는다**(design 위험 4). 이
값들은 arm64 위의 TCG 에뮬레이션에서 나온다. 결론에 쓸 수 있는 것은
**구간 사이의 비율**이다.

- [ ] **Step 4: 로그를 압축해 남긴다**

```bash
gzip -f out/probe/run1.log out/probe/run2.log out/probe/run3.log
ls -l out/probe/
```

**`out/`은 gitignore이고 루트 게이트의 `clean()`이 지운다**(위험 3). 결론에
쓰는 숫자는 전부 Task 7에서 문서로 옮긴다 — 로그가 사라져도 남게.

## Task 7: 문서에 남기고 커밋한다

**Files:**
- Modify: `docs/superpowers/specs/2026-08-30-tars-render-cost-design.md`
  (`## RC-M0이 실측한 것` 절을 더한다. `Status:` 줄도 완료로 고친다)
- Modify: `HANDOFF.md`
- Create: `docs/decisions/project_render_cost.md`
- Modify: `MEMORY.md` (한 줄 추가)

- [ ] **Step 1: design에 실측 절을 더한다**

넣을 것: 회차별 중앙값 표, 픽셀당 비용 표, 해석 계획 표의 어느 줄에 걸렸는지,
그리고 **첫 프레임과 정상 상태의 차이**.

- [ ] **Step 2: `HANDOFF.md`를 고친다**

- "지금 어디인가"를 RC-M0 완료로 바꾼다.
- `## RC-M0이 실행으로 증명한 것 — 다시 조사하지 말 것` 절을 만든다.
- **이월 숙제의 `fill` 항목을 "끝난 숙제"로 옮긴다.**
- 결론에 따라 **새 숙제를 더한다**(예: `fill`을 여백으로 좁히기 · `present`의
  매 프레임 모드셋).

- [ ] **Step 3: 기억 파일을 만들고 `MEMORY.md`에 한 줄 넣는다**

- [ ] **Step 4: `git status`로 `M`과 신규를 가르고 커밋한다**

```bash
git status --short
```

기대: `M docs/superpowers/specs/2026-08-30-tars-render-cost-design.md` ·
`M HANDOFF.md` · `M MEMORY.md` · `?? docs/decisions/project_render_cost.md`
**넷뿐이다.** `terminal/src/` 아래가 하나라도 보이면 마운트가 아니라 저장소를
고친 것이므로 되돌린다.

- [ ] **Step 5: 게이트는 돌리지 않는다**

저장소의 코드가 한 줄도 안 바뀌었다. **게이트가 볼 것이 없다.** 다만
`terminal/zig-out`에는 프로브로 빌드한 바이너리가 남아 있는데, 다음 게이트가
`clean()`으로 지우고 `prepare.sh`가 진짜 소스로 다시 빌드하므로 그대로 두어도
된다(GL-M3 실측 3과 같은 논리다).

## 되돌리는 법

Task 1~6은 저장소를 안 건드리므로 되돌릴 것이 없다. 정리는 이것뿐이다.

```bash
rm -f /tmp/probe_main.zig /tmp/probe_drm.zig /tmp/probe_patch.py /tmp/probe_run.sh /tmp/f?.txt
```

`out/probe/`는 gitignore라 남겨 두어도 되고, 다음 게이트가 지운다.
