//! 렌더 백엔드 인터페이스(R-ARCH-2, TK-M1 plan 확정 1 · 2). 레이어 트리(CA)는 이것만 부르고 픽셀 포인터를 모른다. 지금 구현은 메모리 판
//! 하나(CPU, z2d) — 창 층의 버퍼와 호스트 검사의 배열이 같은 코드를 지난다. GPU 백엔드는 나중에 같은 모양 아래에.
//!
//! 좌표: 사용자 좌표 + `translate`의 누적 = 버퍼 좌표(물리 픽셀, 정수 이동만). clip은 버퍼 좌표의 사각형 스택이다.
//!
//! clip(design 결정 4, 조사 `tk1/research.md` 2절의 (가)): 프레임의 clip이 판 전체가 아니면 그 크기의 임시 판(지움)에 그리고 `finish`가
//! 행마다 버퍼로 복사한다. z2d는 판 경계로만 자르므로 임시 판의 경계가 곧 clip이다 — 겹치는 레이어만 그리면 되고, 정수 이동이라
//! 안티에일리어스 · 서브픽셀 글자가 통째로 그린 것과 바이트까지 같다. 판 전체면 임시 판 없이 버퍼에 바로 그린다.
//! 그 안에 더 좁은 clip(`pushClip` — 레이어의 masks)이 있으면 사각형 · 글자는 직접 자르고, 그 clip을 넘는 둥근 사각형만 작은 임시 판에
//! 그려 얹는다(z2d가 x를 못 자르므로).

const std = @import("std");
const Rect = @import("tk_geom").Rect;
const RectF = @import("tk_geom").RectF;
const Canvas = @import("canvas.zig").Canvas;
const text = @import("text.zig");
const layout = @import("layout.zig");
const image = @import("image.zig");

pub const MAX_CLIPS = 16;

pub const Painter = struct {
    io: std.Io,
    alloc: std.mem.Allocator,
    lut: *const [256]u8,
    /// 버퍼 전체.
    target: Canvas,
    /// 그림이 떨어지는 판 — `target`이거나 프레임 clip 크기의 임시 판.
    canvas: Canvas,
    scratch_used: bool,
    /// `canvas`의 (0, 0)이 버퍼의 어디인가.
    base_x: i32,
    base_y: i32,
    /// clip 스택(버퍼 좌표). `clips[0]`이 프레임 clip이다.
    clips: [MAX_CLIPS]?Rect = undefined,
    /// 겹친 clip만의 교집합(프레임 clip을 뺀 것, 버퍼 좌표). 둥근 사각형이 어느 길로 그려질지를 이것으로 정한다 — 프레임 clip이 다른
    /// 두 그림(부분 · 통째)이 같은 길을 지나 바이트까지 같게.
    inner: [MAX_CLIPS]Rect = undefined,
    depth: usize = 0,
    tx: i32 = 0,
    ty: i32 = 0,

    /// 버퍼 `pixels`(width × height)의 `clip` 안을 그리기 시작한다. `scratch`는 clip 넓이 이상의 메모리(창 층의 `Frame.scratch`) —
    /// 모자라면 clip을 판 전체로 넓힌다(그래도 맞는 그림이다). 실제로 쓴 clip은 `frameClip()`.
    pub fn begin(io: std.Io, alloc: std.mem.Allocator, pixels: []u32, width: u32, height: u32, scratch: []u32, clip: Rect, lut: *const [256]u8) Painter {
        const whole: Rect = .{ .x = 0, .y = 0, .w = @intCast(width), .h = @intCast(height) };
        var c = Rect.intersect(clip, whole) orelse Rect{ .x = 0, .y = 0, .w = 0, .h = 0 };
        const need = @as(usize, @intCast(@max(c.w, 0))) * @as(usize, @intCast(@max(c.h, 0)));
        if (!c.isEmpty() and need > scratch.len) c = whole;
        var p: Painter = .{
            .io = io,
            .alloc = alloc,
            .lut = lut,
            .target = Canvas.wrap(pixels, width, height),
            .canvas = undefined,
            .scratch_used = false,
            .base_x = 0,
            .base_y = 0,
        };
        if (c.isEmpty()) {
            p.canvas = p.target;
            p.clips[0] = null;
        } else if (Rect.eql(c, whole)) {
            p.canvas = p.target;
            p.clips[0] = c;
        } else {
            p.canvas = Canvas.initClear(scratch, @intCast(c.w), @intCast(c.h));
            p.scratch_used = true;
            p.base_x = c.x;
            p.base_y = c.y;
            p.clips[0] = c;
        }
        return p;
    }

    /// 임시 판을 썼으면 버퍼로 옮긴다. 임시 판은 불투명하게 다 칠해졌어야 한다(루트 레이어의 배경) — 그대로 복사한다.
    pub fn finish(self: *Painter) void {
        if (!self.scratch_used) return;
        const c = self.clips[0].?;
        const w: usize = @intCast(c.w);
        var row: usize = 0;
        while (row < @as(usize, @intCast(c.h))) : (row += 1) {
            const so = row * w;
            const doff = (@as(usize, @intCast(c.y)) + row) * self.target.width + @as(usize, @intCast(c.x));
            @memcpy(self.target.pixels[doff .. doff + w], self.canvas.pixels[so .. so + w]);
        }
        self.scratch_used = false;
    }

    pub fn frameClip(self: *const Painter) ?Rect {
        return self.clips[0];
    }

    /// 지금의 clip(사용자 좌표). 그릴 것이 없으면 null — 부르는 쪽이 건너뛰는 데 쓴다.
    pub fn clipBounds(self: *const Painter) ?Rect {
        const c = self.clips[self.depth] orelse return null;
        return c.offset(-self.tx, -self.ty);
    }

    pub fn pushClip(self: *Painter, r: Rect) void {
        std.debug.assert(self.depth + 1 < MAX_CLIPS);
        const cur = self.clips[self.depth];
        self.depth += 1;
        const rb = r.offset(self.tx, self.ty);
        self.clips[self.depth] = if (cur) |c| Rect.intersect(c, rb) else null;
        self.inner[self.depth] = if (self.depth == 1) rb else Rect.intersect(self.inner[self.depth - 1], rb) orelse .{ .x = 0, .y = 0, .w = 0, .h = 0 };
    }

    pub fn popClip(self: *Painter) void {
        std.debug.assert(self.depth > 0);
        self.depth -= 1;
    }

    pub fn translate(self: *Painter, dx: i32, dy: i32) void {
        self.tx += dx;
        self.ty += dy;
    }

    /// 사각형 채우기(빠른 길 — z2d를 안 지난다). clip 안만.
    pub fn fillRect(self: *Painter, r: Rect, color: u32, alpha: u8) void {
        if (alpha == 0) return;
        const c = self.clips[self.depth] orelse return;
        const b = Rect.intersect(r.offset(self.tx, self.ty), c) orelse return;
        self.canvas.fillRect(@intCast(b.x - self.base_x), @intCast(b.y - self.base_y), @intCast(b.w), @intCast(b.h), color, alpha);
    }

    /// 둥근 사각형(z2d — `fill_path`의 첫 쓰임). 반지름 0이고 네 변이 정수면 `fillRect`로.
    pub fn fillRoundedRect(self: *Painter, r: RectF, radius: f32, color: u32, alpha: u8) !void {
        if (alpha == 0) return;
        if (radius <= 0 and r.isIntegral()) {
            return self.fillRect(.{ .x = @intFromFloat(r.x), .y = @intFromFloat(r.y), .w = @intFromFloat(r.w), .h = @intFromFloat(r.h) }, color, alpha);
        }
        const c = self.clips[self.depth] orelse return;
        const bounds = r.offset(@floatFromInt(self.tx), @floatFromInt(self.ty)).outward();
        const vis = Rect.intersect(bounds, c) orelse return;
        // 판의 경계가 곧 clip인 경우(겹친 clip이 없거나 모양이 그 안에 다 든다) — z2d에 바로.
        if (self.depth == 0 or Rect.contains(self.inner[self.depth], bounds)) {
            const dx: f64 = @floatFromInt(self.tx - self.base_x);
            const dy: f64 = @floatFromInt(self.ty - self.base_y);
            return self.canvas.roundedRect(self.io, self.alloc, dx, dy, r.x, r.y, r.w, r.h, radius, color, alpha);
        }
        // 겹친 clip이 모양을 자른다 — 보이는 부분 크기의 작은 판(투명)에 그려 얹는다.
        const n = @as(usize, @intCast(vis.w)) * @as(usize, @intCast(vis.h));
        const tmp = try self.alloc.alloc(u32, n);
        defer self.alloc.free(tmp);
        var small = Canvas.initClear(tmp, @intCast(vis.w), @intCast(vis.h));
        const dx: f64 = @floatFromInt(self.tx - vis.x);
        const dy: f64 = @floatFromInt(self.ty - vis.y);
        try small.roundedRect(self.io, self.alloc, dx, dy, r.x, r.y, r.w, r.h, radius, color, alpha);
        self.canvas.compositeOver(tmp, @intCast(vis.w), @intCast(vis.x - self.base_x), @intCast(vis.y - self.base_y), @intCast(vis.w), @intCast(vis.h));
    }

    /// premultiplied ARGB 판 `img`를 (x, y)(사용자 좌표, 물리 픽셀)에 1:1로 src-over로 얹는다(TK-M6 plan 확정 11). clip 스택과 translate를
    /// 따른다 — 판 밖 · clip 밖은 자른다. 배율 변환은 부르는 쪽의 일(판을 이미 물리 크기로 만든다).
    pub fn drawImage(self: *Painter, img: image.View, x: i32, y: i32) void {
        const c = self.clips[self.depth] orelse return;
        const r: Rect = .{ .x = x + self.tx, .y = y + self.ty, .w = @intCast(img.w), .h = @intCast(img.h) };
        const b = Rect.intersect(r, c) orelse return;
        const sx: usize = @intCast(b.x - r.x);
        const sy: usize = @intCast(b.y - r.y);
        const bw: usize = @intCast(b.w);
        var row: usize = 0;
        while (row < @as(usize, @intCast(b.h))) : (row += 1) {
            const so = (sy + row) * img.w + sx;
            self.canvas.compositeOver(img.pixels[so .. so + bw], @intCast(bw), @intCast(b.x - self.base_x), @intCast(b.y - self.base_y + @as(i32, @intCast(row))), @intCast(bw), 1);
        }
    }

    /// UTF-8 한 줄을 baseline `baseline`, 펜 시작 `x`(소수, 사용자 좌표)에서 그린다(`draw_glyphs`). 돌려주는 것은 끝난 펜 x. clip 밖은
    /// 자른다. 서브픽셀 칸은 펜의 소수 부분으로 정해지고 이동은 정수라 clip · 임시 판과 상관없이 같은 글자다. 글자는 `layout.Placer`가 놓는다 —
    /// 클러스터 · 대체(잘못된 바이트 `?`, 없는 글리프 `□`, 조합형 자모는 음절로)가 `Face.measure`와 같다(TK-M4).
    pub fn drawGlyphs(self: *Painter, face: *text.Face, x: f32, baseline: i32, str: []const u8, color: u32, alpha: u8) !f32 {
        const c_opt = self.clips[self.depth];
        var pl = layout.Placer.init(face.metrics(), str, x);
        while (pl.next()) |g| {
            if (alpha == 0) continue;
            const c = c_opt orelse continue;
            const at = text.splitPen(g.x);
            const gl = try face.get(g.cp, at.sub);
            const gx = at.ix + gl.x_offset + self.tx - self.base_x;
            const gy = baseline + gl.y_offset + self.ty - self.base_y;
            self.canvas.blendGlyph(gl, gx, gy, color, self.lut, alpha, c.x - self.base_x, c.y - self.base_y, c.x + c.w - self.base_x, c.y + c.h - self.base_y);
        }
        return pl.pen;
    }
};
