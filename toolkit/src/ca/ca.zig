//! CA 층(R-ARCH-1, R-CA-1~2): 레이어 트리와 더티. CG(`tk_cg`)만 알고 창을 모른다 — 더티는 `Sink`로 내보내고 앱이 창에 잇는다.
//! 모듈 `tk_ca`. 애니메이션 · 스택 레이아웃은 TK-M1 단계 B가 여기에 더한다.

pub const layer = @import("layer.zig");

pub const Layer = layer.Layer;
pub const Tree = layer.Tree;
pub const Content = layer.Content;
pub const Sink = layer.Sink;
