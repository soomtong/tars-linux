//! `tars-files`의 메뉴 모델(TK-M6 plan 확정 9, R-KIT-9) — 단축키의 정의는 이 표 하나다. 순수 값이라 호스트 검사가 이 파일을 그대로 부른다
//! (모델이 서버의 상한 안 · 단축키가 서버가 이름을 그리는 키 · 서버의 chord와 안 겹침). 그래서 `tk` 모듈이 아니라 그 아래의 `tk_menu` ·
//! `tk_input`을 직접 import한다(같은 모듈 — `tk.menu`와 같은 타입).
//!
//! 제목은 영문(녹화 C의 "File · Edit · View · Go"), 항목은 한글. 서버가 먹는 chord(`Cmd+D W [ ] R Q T 1~9` 등 — `terminal/src/input.zig`의
//! `tableChord`)는 앱에 안 오므로 단축키로 쓰지 않는다 — `끝내기`의 `Cmd+Q`만 "서버 몫"으로 보인다.

const menu = @import("tk_menu");
const input = @import("tk_input");

// 앱의 action(표준 다섯은 `tk.menu`의 것). 프로토콜의 id가 곧 이 값이다.
pub const A_QUIT = menu.FIRST_APP;
pub const A_FILTER = menu.FIRST_APP + 1;
pub const A_PREVIEW = menu.FIRST_APP + 2;
pub const A_REFRESH = menu.FIRST_APP + 3;
pub const A_GOTO = menu.FIRST_APP + 4;
pub const A_SEARCH = menu.FIRST_APP + 5;
const CMD: input.Mods = .{ .super = true };
const Entry = menu.Entry;
const FILE_MENU = [_]Entry{
    // `Cmd+Q`는 서버의 chord(키로는 안 온다 — 서버가 close를 보낸다). 바에 보이는 글이고, 메뉴로 고르면 앱이 끝난다.
    .{ .item = .{ .action = A_QUIT, .name = "quit", .label = "끝내기", .mods = CMD, .key = input.KEY_Q } },
};
const EDIT_MENU = menu.standard_edit ++ [_]Entry{
    .separator,
    .{ .item = .{ .action = A_FILTER, .name = "filter", .label = "찾기", .mods = CMD, .key = input.KEY_F } },
};
const VIEW_MENU = [_]Entry{
    .{ .item = .{ .action = A_PREVIEW, .name = "preview", .label = "미리보기", .key = input.KEY_SPACE } },
    // `Cmd+R`은 서버의 chord(폭 순환)라 단축키가 없다.
    .{ .item = .{ .action = A_REFRESH, .name = "refresh", .label = "새로 고침" } },
};
const GO_MENU = [_]Entry{
    .{ .item = .{ .action = A_GOTO, .name = "goto", .label = "경로로 가기…", .mods = CMD, .key = input.KEY_L } },
    .{ .item = .{ .action = A_SEARCH, .name = "search", .label = "검색…", .mods = CMD, .key = input.KEY_K } },
};
pub const MENU: menu.Model = .{ .menus = &.{
    .{ .title = "File", .entries = &FILE_MENU },
    .{ .title = "Edit", .entries = &EDIT_MENU },
    .{ .title = "View", .entries = &VIEW_MENU },
    .{ .title = "Go", .entries = &GO_MENU },
} };
