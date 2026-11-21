//! AppKit 층(R-ARCH-1, R-KIT-*, TK-M2 plan 확정 4). 뷰 · responder chain · 포커스, 그리고 위젯(TK-M2 단계 B부터 리스트, TK-M3부터
//! column view · 분할 뷰). 모듈 `tk_kit`.
//! CA(`tk_ca`) · CG(`tk_cg`) · 층 밖 값(`tk_geom` · `tk_input`)을 알고 창 층(`tk_window`)은 모른다 — 이벤트는 `tk_input.Event`로 받으므로
//! 호스트 검사가 Wayland 없이 뷰 트리를 돌린다(R-ARCH-4).

pub const view = @import("view.zig");

pub const View = view.View;
pub const VTable = view.VTable;
pub const Root = view.Root;
pub const FocusHook = view.FocusHook;
pub const Unhandled = view.Unhandled;
pub const HitHook = view.HitHook;
pub const list = @import("list.zig");
pub const List = list.List;
pub const ListSource = list.ListSource;
pub const RowState = list.RowState;
pub const ListDelegate = list.ListDelegate;
pub const column = @import("column.zig");
pub const ColumnView = column.ColumnView;
pub const ColumnSource = column.ColumnSource;
pub const ColumnEvent = column.ColumnEvent;
pub const ColumnHook = column.ColumnHook;
pub const split = @import("split.zig");
pub const SplitView = split.SplitView;
