//! CA 층(R-ARCH-1, R-CA-1~2): 레이어 트리와 더티. CG(`tk_cg`)만 알고 창을 모른다 — 더티는 `Sink`로 내보내고 앱이 창에 잇는다.
//! 모듈 `tk_ca`. 애니메이션(R-CA-3) · 스택 레이아웃(R-CA-4)도 여기다.

pub const layer = @import("layer.zig");
pub const anim = @import("anim.zig");
pub const stack = @import("stack.zig");

pub const Layer = layer.Layer;
pub const Tree = layer.Tree;
pub const Content = layer.Content;
pub const Sink = layer.Sink;
pub const Easing = anim.Easing;
pub const Stack = stack.Stack;
