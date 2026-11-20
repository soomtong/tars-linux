//! TARS의 색 한 벌(TK design 결정 2 · 7). terminal과 툴킷이 같은 파일을 컴파일한다 — 셸과 앱의 색이 한 소스라는 것을
//! 컴파일이 보장한다(R-ARCH-5 · 6). 순수 상수뿐이고 libc도 다른 import도 없다(screen_args와 같은 자리).
//!
//! 값은 XRGB8888 한 워드다(프레임버퍼 · wl_shm과 같은 배치). 셸 쪽 값은 TK-M0 단계 A가 terminal의 상수를 값 그대로
//! 옮긴 것이다. 그 값을 고르고 지킨 까닭(게이트가 "전용 색"의 픽셀을 세는 것 등)은 쓰는 자리의 주석에 남아 있다 —
//! `terminal/src/main.zig` · `vt.zig` · `pointer.zig`에서 같은 이름을 찾는다. 여기서 값을 바꾸면 그 판정들이 함께 바뀐다.

// ── 셸(terminal) ────────────────────────────────────────────────

/// 격자 바깥 여백(main.zig).
pub const MARGIN_COLOR: u32 = 0x00102030;

/// 셀의 기본 배경 · 전경(vt.zig의 `Screen.init`). 여백과 배경이 같은 값인 것은 우연이 아니라 화면이 한 판으로 보이게
/// 하려는 것이지만, 뜻이 다르므로 이름을 나눈다.
pub const CELL_BG: u32 = 0x00102030;
pub const CELL_FG: u32 = 0x00FFFFFF;

/// 상태 줄(main.zig). 앞 세 칸 · CAPS 켬 · CAPS 끔 · copy mode · 받아쓰기.
pub const STATUS_FG: u32 = 0x00808890;
pub const STATUS_ON: u32 = 0x00C08000;
pub const STATUS_OFF: u32 = 0x00303840;
pub const STATUS_COPY: u32 = 0x00E0E8F0;
pub const STATUS_DICT: u32 = 0x00F07070;

/// 상태 줄의 배터리 칸 셋 · 링크 칸 둘(main.zig).
pub const STATUS_BAT: u32 = 0x00909AA0;
pub const STATUS_BAT_PLUG: u32 = 0x0060C070;
pub const STATUS_BAT_LOW: u32 = 0x00E05040;
pub const STATUS_LINK: u32 = 0x0070B0E0;
pub const STATUS_LINK_WAIT: u32 = 0x00586878;

/// 패널 사이 구분선(main.zig).
pub const SEPARATOR: u32 = 0x00405060;

/// app 워크스페이스에서 창 둘레(main.zig).
pub const APP_BACKDROP: u32 = 0x00000000;

/// 검색 매치의 바탕 · 현재 매치의 바탕 · bar/underline 커서(vt.zig).
pub const MATCH_BG: u32 = 0x00705000;
pub const CURRENT_BG: u32 = 0x00C08000;
pub const CURSOR_COLOR: u32 = 0x00F0F0F0;

/// 포인터 화살표의 안쪽 · 테두리(pointer.zig).
pub const POINTER_FILL: u32 = 0x00FCFCF4;
pub const POINTER_EDGE: u32 = 0x00040810;

// ── 앱 토큰(R-CA-5) ─────────────────────────────────────────────
//
// 툴킷의 색 · 간격 · 반지름 · 글꼴 크기(TK-M0 단계 B부터). 색은 위 셸 색 어느 것과도 다른 값이다 — 게이트가 screendump에서
// 앱의 픽셀을 셸의 것과 가를 수 있게(셸 색과 같은 이유의 "전용 색"). 크기는 논리 픽셀이고 그릴 때 배율을 곱한다.

/// 창 바탕. 셸의 셀 배경(`CELL_BG`)보다 한 단 밝아 column 경계가 보인다.
pub const TK_BG: u32 = 0x00202C3C;
/// 강조 면(TK-M0 데모의 둥근 사각형, 뒤의 선택 강조).
pub const TK_ACCENT: u32 = 0x003C78D8;
/// 본문 글자. 셸의 `CURSOR_COLOR`(F0F0F0) · `CELL_FG`(FFFFFF)와 다른 값이다.
pub const TK_TEXT: u32 = 0x00F4F6F8;

/// 모서리 반지름 · 간격 · 글꼴 크기(em, 13 본문 작은 것 · 14 본문).
pub const TK_RADIUS: u32 = 12;
pub const TK_SPACE: u32 = 8;
pub const TK_FONT_SMALL: u32 = 13;
pub const TK_FONT: u32 = 14;
