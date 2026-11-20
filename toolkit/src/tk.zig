//! TARS 툴킷 `tk`(TK design). 층은 아래에서 위로 창(`tk_window`) · CG(`tk_cg` — 판 · 렌더 백엔드 · 글자) · CA(`tk_ca` — 레이어 트리 ·
//! 더티)이고 위젯(AppKit)은 TK-M2부터 그 위에 선다(R-ARCH-1). 층마다 build 모듈이 따로라 아래 층이 위 층을 import하면 컴파일이 막는다.
//! 사각형(`tk_geom`)은 층 밖의 순수 값이다. 테마는 terminal과 같은 `shared/theme.zig`다(design 결정 7).
//!
//! 이 파일은 층들을 잇는 자리다 — 트리의 더티를 창에(`connect`), 창의 판에 트리를(`drawTree`).

const std = @import("std");

pub const theme = @import("theme");
pub const geom = @import("tk_geom");
pub const window = @import("tk_window");
pub const cg = @import("tk_cg");
pub const ca = @import("tk_ca");

pub const Rect = geom.Rect;
pub const RectF = geom.RectF;
pub const Window = window.Window;
pub const Painter = cg.Painter;
pub const Face = cg.Face;
pub const text = cg.text;
pub const Tree = ca.Tree;
pub const Layer = ca.Layer;

/// 번들 글꼴의 자리(design 결정 6). initrd의 절대 경로다 — 셸에서 띄운 앱의 cwd는 홈이라 상대 경로로는 못 찾는다.
pub const FONT_PATH = "/vendor/fonts/Pretendard-Regular.otf";

/// 트리의 더티가 창의 `invalidate`로 가게 잇는다.
pub fn connect(tree: *Tree, win: *Window) void {
    tree.sink = .{ .ctx = win, .invalidate = sinkInvalidate };
}

fn sinkInvalidate(ctx: *anyopaque, r: Rect) void {
    const win: *Window = @ptrCast(@alignCast(ctx));
    win.invalidate(r);
}

/// 창의 판 하나에 트리를 그린다 — `frame.clip` 안만(임시 판 clip, TK-M1 plan 확정 2). 트리에 쌓인 더티는 이 그림이 다 담으므로 비운다.
pub fn drawTree(io: std.Io, alloc: std.mem.Allocator, tree: *Tree, frame: window.Frame, lut: *const [256]u8) !void {
    var p = Painter.begin(io, alloc, frame.pixels, frame.width, frame.height, frame.scratch, frame.clip, lut);
    _ = try tree.draw(&p);
    p.finish();
    _ = tree.takeDirty();
}
