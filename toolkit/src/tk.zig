//! TARS 툴킷 `tk`(TK design). 층은 아래에서 위로 창(`window`) · 그리기(`canvas`, CG) · 글자(`text`)이고, 레이어 트리(CA)와 위젯
//! (AppKit)은 TK-M1부터 위에 선다(R-ARCH-1). 테마는 terminal과 같은 `shared/theme.zig`다(design 결정 7).

pub const theme = @import("theme");
pub const canvas = @import("canvas.zig");
pub const text = @import("text.zig");
pub const window = @import("window.zig");

pub const Canvas = canvas.Canvas;
pub const Face = text.Face;
pub const Window = window.Window;

/// 번들 글꼴의 자리(design 결정 6). initrd의 절대 경로다 — 셸에서 띄운 앱의 cwd는 홈이라 상대 경로로는 못 찾는다.
pub const FONT_PATH = "/vendor/fonts/Pretendard-Regular.otf";
