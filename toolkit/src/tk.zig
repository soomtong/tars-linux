//! TARS 툴킷 `tk`(TK design). 층은 아래에서 위로 창(`tk_window`) · CG(`tk_cg` — 판 · 렌더 백엔드 · 글자) · CA(`tk_ca` — 레이어 트리 ·
//! 더티 · 애니메이션 · 스택 · hit-test) · AppKit(`tk_kit` — 뷰 · responder · 포커스, TK-M2)이다(R-ARCH-1). 층마다 build 모듈이 따로라 아래 층이
//! 위 층을 import하면 컴파일이 막는다. kit은 창 층도 모른다(TK design 결정 13).
//! 사각형(`tk_geom`)과 입력 이벤트(`tk_input`)는 층 밖의 순수 값이다. 테마는 terminal과 같은 `shared/theme.zig`이고 앱은 그것을 `tokens`로 부른다(R-CA-5).
//!
//! 이 파일은 층들을 잇는 자리다 — 트리의 더티 · 애니메이션 알림을 창에(`connect`), 창의 판에 트리를(`drawTree`), kit의 포커스 알림을
//! 창 층의 줄에(`connectRoot`). 창의 입력은 앱의 `Handler.input`이 `kit.Root.handle`에 넘긴다(앱이 자기 키를 먼저 볼 자리를 남긴다).

const std = @import("std");

pub const theme = @import("theme");
pub const geom = @import("tk_geom");
pub const window = @import("tk_window");
pub const cg = @import("tk_cg");
pub const ca = @import("tk_ca");
pub const input = @import("tk_input");
pub const kit = @import("tk_kit");

pub const Rect = geom.Rect;
pub const RectF = geom.RectF;
pub const Window = window.Window;
pub const Painter = cg.Painter;
pub const Face = cg.Face;
pub const text = cg.text;
pub const tokens = @import("tk_tokens");
pub const Tree = ca.Tree;
pub const Layer = ca.Layer;
pub const Stack = ca.Stack;
pub const Easing = ca.Easing;

/// 번들 글꼴의 자리(design 결정 6). initrd의 절대 경로다 — 셸에서 띄운 앱의 cwd는 홈이라 상대 경로로는 못 찾는다.
pub const FONT_PATH = "/vendor/fonts/Pretendard-Regular.otf";

/// 트리의 더티가 창의 `invalidate`로 가고, 애니메이션의 시작 · 끝이 `tk> anim start prop= dur=` · `tk> anim end prop= frames= ms=`
/// 줄이 되게 잇는다(TK-M1 plan 확정 6). 시계는 앱의 `Handler.tick`이 트리의 `tick`을 부르는 것으로 잇는다.
pub fn connect(tree: *Tree, win: *Window) void {
    tree.sink = .{ .ctx = win, .invalidate = sinkInvalidate };
    tree.hook = .{ .ctx = win, .on = animEvent };
}

fn animEvent(_: *anyopaque, ev: ca.anim.Event) void {
    switch (ev) {
        .start => |s| window.say("anim start prop={s} dur={d}", .{ @tagName(s.prop), s.dur_ms }),
        .end => |e| window.say("anim end prop={s} frames={d} ms={d}", .{ @tagName(e.prop), e.frames, e.ms }),
    }
}

/// first responder가 바뀌면 `tk> focus view=NAME`(아무도 아니면 `view=-`), 클릭(왼쪽 누름)마다 `tk> hit x= y= view=` 줄(TK-M2 plan 확정 14).
/// 좌표는 surface 논리 좌표의 정수 부분이다.
pub fn connectRoot(root: *kit.Root) void {
    root.hook = .{ .ctx = root, .on = focusEvent };
    root.hit_hook = .{ .ctx = root, .on = hitEvent };
}

fn focusEvent(_: *anyopaque, v: ?*kit.View) void {
    window.say("focus view={s}", .{if (v) |x| x.name else "-"});
}

fn hitEvent(_: *anyopaque, x: f32, y: f32, v: ?*kit.View) void {
    window.say("hit x={d} y={d} view={s}", .{ @as(i32, @intFromFloat(@floor(x))), @as(i32, @intFromFloat(@floor(y))), if (v) |w| w.name else "-" });
}

/// 리스트의 선택 · 스크롤을 줄로: `tk> list view= sel= first= offset=`(키 · 클릭마다) · `tk> scroll view= offset= by=wheel`(TK-M2 plan 확정 14).
pub fn connectList(list: *kit.List) void {
    list.hook = .{ .ctx = list, .on = listEvent };
}

fn listEvent(_: *anyopaque, list: *kit.List, ev: kit.list.ListEvent) void {
    switch (ev) {
        .select => |s| window.say("list view={s} sel={d} first={d} offset={d}", .{ list.view.name, s.sel, s.first, s.offset }),
        .scroll => |s| window.say("scroll view={s} offset={d} by=wheel", .{ list.view.name, s.offset }),
    }
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
