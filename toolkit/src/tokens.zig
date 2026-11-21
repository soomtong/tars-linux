//! 테마 토큰 한 벌(R-CA-5, TK-M1 plan 확정 8). 값은 `shared/theme.zig`의 앱 구역이고 여기는 뜻 이름으로 다시 내보낼 뿐이다 —
//! 앱과 위젯은 theme을 직접 부르지 않고 이것을 부른다. 테마가 실행 중에 바뀌는 날(design 결정 7의 이벤트)에 고칠 자리가 여기 하나다.
//!
//! 색은 0xRRGGBB, 크기는 논리 픽셀(그릴 때 배율을 곱한다), 글꼴 크기는 em 픽셀.

const theme = @import("theme");

pub const color = struct {
    pub const bg = theme.TK_BG;
    pub const surface = theme.TK_SURFACE;
    pub const accent = theme.TK_ACCENT;
    pub const selection = theme.TK_SELECTION;
    /// 포커스가 아닌 리스트의 선택(또는 창이 키보드 포커스를 잃었을 때) — TK-M2 plan 확정 8.
    pub const selection_inactive = theme.TK_SELECTION_INACTIVE;
    pub const text = theme.TK_TEXT;
    pub const text_dim = theme.TK_TEXT_DIM;
    pub const separator = theme.TK_SEPARATOR;
};

pub const space = struct {
    pub const s: f32 = theme.TK_SPACE_S;
    pub const m: f32 = theme.TK_SPACE;
    pub const l: f32 = theme.TK_SPACE_L;
};

pub const padding: f32 = theme.TK_PADDING;

pub const radius = struct {
    pub const s: f32 = theme.TK_RADIUS_S;
    pub const m: f32 = theme.TK_RADIUS;
};

pub const font = struct {
    pub const small: f32 = theme.TK_FONT_SMALL;
    pub const body: f32 = theme.TK_FONT;
    pub const title: f32 = theme.TK_FONT_TITLE;
};
