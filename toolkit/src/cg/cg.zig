//! CG 층(R-ARCH-1, TK design 결정 3 · 5): 픽셀 판 · 렌더 백엔드 인터페이스 · 글자. 아래 층(창)을 모르고, 위 층(CA)은 `Painter`와
//! `Face`만 부른다. 모듈 `tk_cg`.

pub const canvas = @import("canvas.zig");
pub const painter = @import("painter.zig");
pub const text = @import("text.zig");

pub const Canvas = canvas.Canvas;
pub const Painter = painter.Painter;
pub const Face = text.Face;
