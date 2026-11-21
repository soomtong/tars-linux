//! `tars-files` — TARS의 첫 앱(요구사항 녹화 C, TK-M3 뼈대). Miller column 파일 관리자: 분할 뷰(column view | 미리보기 자리), `→` · Enter로
//! 디렉터리를 오른쪽 열로 열고 `←`로 부모 열에 포커스. 로딩은 메인 루프의 조각 읽기(창 층 `Handler.idle` — getdents64 32 KiB 한 번씩,
//! 받은 만큼 바로 보인다)이고 열을 버리면 취소된다. 창이 키보드 포커스를 다시 얻으면 보이는 열을 다시 읽어 선택을 이름으로 따라간다
//! (R-FM-6). 정렬 · 병합 · 선택의 셈은 `model.zig`(순수 — 호스트 검사), 읽기는 `dir.zig`, 이 파일은 잇기만 한다.
//!
//! 자리(논리 px, W × H = configure 크기): 분할 뷰가 창 전체 — column view x 0..W − 202, 구분선 W − 201, 미리보기 W − 200..W − 1
//! (`tokens.size.preview`, `TK_SURFACE`, 위 왼쪽 16에 포커스 열 선택 항목의 이름 한 줄 `TK_TEXT_DIM`). 열은 폭 200 + 구분선 1(열 i의 x =
//! i × 201 − 가로 스크롤). 행 24, 이름은 행 왼쪽 16에서 13 px `TK_TEXT`, 디렉터리는 행 오른쪽 끝(막대 6 + 4 앞)에 `›` `TK_TEXT_DIM`.
//! 0행인 열은 세로 가운데 한 줄: 로딩 중 "불러오는 중…", 끝났는데 비면 "비어 있음", 못 열면 "열 수 없음"(`TK_TEXT_DIM`).
//!
//! 경로 바(TK-M4 plan 확정 13~15): `Cmd+L`이 창 위 한 줄(높이 32, 평소 숨김 — 숨어 있으면 화면이 TK-M3과 같다)을 열고 포커스 열의 경로를 텍스트
//! 필드에 채운다(캐럿은 끝). 바: 왼쪽 16에 이름표 "경로"(`TK_TEXT_DIM`), 필드는 x 64..W − 16 · y 4 · 높이 24. Enter는 경로를 해석해(`model.resolvePath`)
//! 열을 다시 세우고(`model.columnPaths` · `ColumnView.setColumns`, 각 열의 선택은 다음 성분 — 로딩이 그 이름을 만나면 고른다) 바를 닫는다. 없는
//! 경로면 바를 열어 둔 채 `tk> path error=`. Esc는 닫기. 필드가 포커스인 동안 text-input이 켜진다(한글 — design 결정 8). `Cmd+C`(필드가 아닐 때)는
//! 포커스 열의 선택 항목 경로를 클립보드로(R-FM-8).
//!
//! 필터 · 검색(TK-M4 plan 확정 18~20): 바 하나를 세 모드가 같이 쓴다(이름표 "경로" · "필터" · "검색"). `Cmd+F`는 포커스 열을 이름 부분 일치로 거르고(`Col.filtered`
//! — 리스트가 그것을 본다, 선택은 이름으로 따라감, Enter는 바만 닫고 Esc는 풂, 갱신은 필터를 지킴), `Cmd+K`는 열 0의 경로 아래를 idle 조각으로 걸어(`search.zig`)
//! 열 자리를 덮는 결과 리스트에 상위 100을 보인다(`↑` `↓`는 필드가 넘겨 앱이 고르고, Enter는 경로 바의 Enter와 같은 길).
//!
//! 메뉴(TK-M6 plan 확정 9, R-KIT-9): 단축키의 정의는 메뉴 모델 `MENU` 하나다 — File[끝내기 `Cmd+Q`] · Edit[표준 Edit 다섯 · 찾기 `Cmd+F`] ·
//! View[미리보기 `Space` · 새로 고침] · Go[경로로 가기 `Cmd+L` · 검색 `Cmd+K`]. 창이 열 때 서버에 보내고(바에 `File Edit View Go`), kit `Root`가 키를
//! 이 표에 맞춰 action을 responder chain으로 보낸다. 앱의 action은 루트 뷰가 한다(`rootPerform` · `rootValidate`) — `copy`는 필드가 포커스면 필드의
//! 것이고 아니면 여기의 경로 복사다. `Cmd+Q`는 서버의 chord라 키로는 안 온다(서버가 close) — 메뉴로 고르면 앱이 스스로 끝난다.
//! `Space`는 미리보기 판 토글(분할 뷰의 오른쪽 폭 0 ↔ 200, plan 확정 14) — 필드에서는 글자다.
//!
//! 인자: `tars-files [경로]` — 없으면 `$HOME`, 그것도 없으면 `/`.
//!
//! 줄(plan 확정 14): `tk> files path=` · `tk> load path= n= chunks= first_us= paint_us= all_us= read_us= merge_us= state=done|cancelled|error` ·
//! `tk> columns n= focus= scroll=` · `tk> column i= path= count= sel= name=`(열의 선택이 키 · 클릭으로 바뀔 때와 첫 로딩이 끝날 때) ·
//! `tk> refresh path= name= before= after=`(사라졌으면 ` gone=1`) · 끝날 때 `tk> rss vmrss_kb= vmhwm_kb=`. 창 층의 줄(`configure` · `draw` ·
//! `commit` · `key` · `focus`)은 그대로. TK-M4: `tk> column … shown=`, `tk> bar open|close`, `tk> field text= action=enter|escape`,
//! `tk> path error= text=`, `tk> copy path=`(경로 복사 — 그 뒤 창 층의 `tk> copy len= serial=`), `tk> bar mode=filter|search`,
//! `tk> filter text= n=`, `tk> search walked= ms= capped= results=`(걷기 끝) · `tk> search query= walked= results= score_us=` · `tk> search open=`.

const std = @import("std");
const linux = std.os.linux;
const tk = @import("tk");
const tokens = tk.tokens;
const kit = tk.kit;
const model = @import("model.zig");
const search_mod = @import("search.zig");
const dir_mod = @import("dir.zig");
const preview_mod = @import("preview.zig");
const image = tk.cg.image;
const Dir = dir_mod.Dir;

const MAX = kit.column.MAX_COLUMNS;
const LABEL_X: f32 = 16;
/// `›`의 오른쪽 끝과 막대 사이.
const CHEVRON_GAP: f32 = 4;
const ANIM_MS: u32 = 120;
/// 바 안 필드의 왼쪽(이름표 "경로"의 자리 16 + 48)과 오른쪽 여백.
const FIELD_X: f32 = 64;
const FIELD_RIGHT: f32 = 16;

/// 생략한 이름을 담는 칸 — 이름(리눅스 255바이트) + `…`(3바이트)이 든다. 경계 칸은 클러스터 수 + 1(255 + 1).
const NAME_BUF = 260;
const NAME_STOPS = 257;

/// 행 안에서 `›`의 펜 x(물리 px, 행 왼쪽 기준) — 막대(`BAR_W`)와 4 앞에 오른쪽 끝을 맞춘다(TK-M3 확정 13).
fn chevronX(f: *tk.Face, s: f32, row_w: f32) f32 {
    const right = row_w - (kit.list.BAR_W + CHEVRON_GAP) * s;
    return @round(right - f.measure("›"));
}

/// 이름 칸의 폭(물리 px, TK-M4 plan 확정 5): 행 왼쪽 16부터 — 디렉터리는 `›` 왼쪽 − 4까지, 파일은 막대 왼쪽 − 4까지.
fn nameWidth(f: *tk.Face, s: f32, row_w: f32, dir: bool) f32 {
    const limit = if (dir) chevronX(f, s, row_w) - CHEVRON_GAP * s else row_w - (kit.list.BAR_W + CHEVRON_GAP) * s;
    return @max(0, limit - LABEL_X * s);
}

/// 폭 `max_w`에 맞춘 이름 — 넘치면 가운데 생략(R-TXT-1). 칸이 모자라는 이름(일어나지 않는다)은 그대로.
fn shownName(f: *tk.Face, name: []const u8, max_w: f32, buf: *[NAME_BUF]u8) []const u8 {
    var scratch: [NAME_STOPS]tk.layout.Stop = undefined;
    return tk.layout.elideMiddle(f.metrics(), name, max_w, &scratch, buf) catch name;
}

fn nowNs() u64 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

/// 열 하나(column view의 열 i와 같은 번호 — 풀의 자리도 같다).
const Col = struct {
    app: *App = undefined,
    index: usize = 0,
    path_buf: [1024]u8 = undefined,
    path_len: usize = 0,
    /// 리스트가 보이는 목록. 첫 로딩 동안은 읽는 목록과 같다.
    shown: ?*model.Listing = null,
    /// 읽는 중인 목록과 손잡이. 갱신이면 `shown`과 다른 목록(다 읽은 뒤 바꿔 끼운다).
    loading: ?*model.Listing = null,
    handle: ?*anyopaque = null,
    refresh: bool = false,
    /// 첫 로딩 동안 사용자가 선택을 건드렸다(확정 10).
    touched: bool = false,
    failed: bool = false,
    t0: u64 = 0,
    first_us: u64 = 0,
    paint_us: u64 = 0,
    read_us: u64 = 0,
    merge_us: u64 = 0,
    /// 리스트 위의 한 줄(0행일 때). 풀의 리스트 컨테이너에 한 번 붙인다.
    overlay: ?*tk.Layer = null,
    /// 첫 로딩이 고를 이름(경로 바의 Enter — 다음 성분, TK-M4 plan 확정 14). 사용자가 선택을 건드리면 버린다.
    want_buf: [256]u8 = undefined,
    want_len: usize = 0,
    want_kind: model.Kind = .dir,
    /// 필터(`Cmd+F`, TK-M4 plan 확정 19): 글이 있으면 리스트는 `filtered`(이름에 그 글이 든 항목 — 순서 그대로)를 본다.
    filter_buf: [256]u8 = undefined,
    filter_len: usize = 0,
    filtered: std.ArrayList(model.Entry) = .empty,

    fn path(self: *const Col) []const u8 {
        return self.path_buf[0..self.path_len];
    }

    /// 리스트가 보이는 항목 — 필터가 걸렸으면 거른 것.
    fn entries(self: *const Col) []const model.Entry {
        if (self.filter_len > 0) return self.filtered.items;
        return self.all();
    }

    /// 거르기 전의 항목 전부.
    fn all(self: *const Col) []const model.Entry {
        return if (self.shown) |l| l.items() else &.{};
    }

    fn filterText(self: *const Col) []const u8 {
        return self.filter_buf[0..self.filter_len];
    }

    fn listSource(self: *Col) kit.ListSource {
        return .{ .ctx = self, .count = count, .drawRow = drawRow };
    }

    fn count(ctx: *anyopaque) usize {
        const self: *Col = @ptrCast(@alignCast(ctx));
        return self.entries().len;
    }

    fn drawRow(ctx: *anyopaque, p: *tk.Painter, index: usize, rect: tk.Rect, state: kit.RowState) anyerror!void {
        const self: *Col = @ptrCast(@alignCast(ctx));
        const app = self.app;
        const f = &app.small.?;
        const s: f32 = @floatFromInt(app.scale);
        const e = self.entries()[index];
        const base: i32 = rect.y + @as(i32, @intFromFloat(@round((@as(f32, @floatFromInt(rect.h)) + f.ascent - f.descent) / 2)));
        const x0: f32 = @floatFromInt(rect.x);
        const row_w: f32 = @floatFromInt(rect.w);
        var buf: [NAME_BUF]u8 = undefined;
        const shown = shownName(f, e.name, nameWidth(f, s, row_w, e.kind == .dir), &buf);
        _ = try p.drawGlyphs(f, x0 + LABEL_X * s, base, shown, tokens.color.text, state.alpha);
        if (e.kind == .dir) {
            _ = try p.drawGlyphs(f, x0 + chevronX(f, s, row_w), base, "›", tokens.color.text_dim, state.alpha);
        }
    }

    fn status(self: *const Col) ?[]const u8 {
        if (self.entries().len != 0) return null;
        if (self.failed) return "열 수 없음";
        if (self.loading != null and !self.refresh) return "불러오는 중…";
        if (self.shown != null) return "비어 있음";
        return null;
    }

    fn drawOverlay(ctx: *anyopaque, p: *tk.Painter, size: [2]f32, alpha: u8) anyerror!void {
        const self: *Col = @ptrCast(@alignCast(ctx));
        const msg = self.status() orelse return;
        const f = &self.app.small.?;
        const w = f.measure(msg);
        const base: i32 = @intFromFloat(@round((size[1] + f.ascent - f.descent) / 2));
        _ = try p.drawGlyphs(f, @round((size[0] - w) / 2), base, msg, tokens.color.text_dim, alpha);
    }
};

const App = struct {
    io: std.Io,
    alloc: std.mem.Allocator,
    font: []const u8,
    lut: [256]u8,
    scale: u32 = 0,
    small: ?tk.Face = null,
    tree: tk.Tree,
    dir: Dir,
    win: ?*tk.Window = null,
    root: *tk.Layer = undefined,
    preview: *tk.Layer = undefined,
    /// 미리보기 판의 두 레이어(TK-M6 plan 확정 13): 위 이름 한 줄 · 아래 본문(글 · 그림 · 아이콘) — 바뀐 쪽만 다시 그린다.
    pv_name: *tk.Layer = undefined,
    pv_body: *tk.Layer = undefined,
    /// 선택이 바뀌었다 — idle 한 조각이 지금 선택과 다르면 읽는다(낡은 요청은 그냥 버려진다).
    pv_pending: bool = true,
    /// 지금 본문이 보이는 것의 열쇠(경로 · 배율).
    pv_key: [4096]u8 = undefined,
    pv_key_len: usize = 0,
    pv_scale: u32 = 0,
    pv: Preview = .none,
    root_view: kit.View = undefined,
    kit_root: kit.Root = undefined,
    split: kit.SplitView = undefined,
    cv: kit.ColumnView = undefined,
    cols: [MAX]Col = @splat(.{}),
    /// 경로 바(TK-M4).
    bar: *tk.Layer = undefined,
    bar_label: *tk.Layer = undefined,
    field: kit.TextField = undefined,
    bar_open: bool = false,
    /// 바의 모드(TK-M4 plan 확정 18) — 경로 · 필터 · 검색이 바 하나를 같이 쓴다.
    mode: Mode = .path,
    /// 필터가 걸리는 열(`Cmd+F`를 누른 때의 포커스 열).
    filter_col: usize = 0,
    /// 검색(`Cmd+K`)과 그 결과 리스트(열 자리를 덮는다).
    search: ?search_mod.Search = null,
    search_said: bool = false,
    results: kit.List = undefined,
    home: ?[]const u8 = null,
    /// 지금 창 크기(논리).
    width: f32 = 0,
    height: f32 = 0,
    /// 미리보기 판이 보이는가(`Space`, TK-M6).
    preview_on: bool = true,
    /// 창이 한 번이라도 키보드 포커스를 가졌다 — 그 뒤의 포커스 얻음만 갱신의 계기다(처음 붙는 enter는 아니다).
    had_focus: bool = false,

    fn source(self: *App) model.DirSource {
        return self.dir.source();
    }

    fn faces(self: *App, s: u32) !void {
        if (self.scale == s) return;
        if (self.small) |*x| x.deinit();
        self.small = null;
        self.small = try tk.Face.init(self.alloc, self.font, tokens.font.small * @as(f32, @floatFromInt(s)));
        self.scale = s;
    }

    fn build(self: *App, start: []const u8) !void {
        for (&self.cols, 0..) |*c, i| c.* = .{ .app = self, .index = i };
        const t = &self.tree;
        self.root = try t.create(.{ .background = tokens.color.bg });
        t.setRoot(self.root);
        self.root_view = .{ .layer = self.root, .vtable = &ROOT_VT, .ctx = self, .name = "root" };
        self.kit_root = kit.Root.init(t);
        self.kit_root.setView(&self.root_view);
        tk.connectRoot(&self.kit_root);

        const c0 = &self.cols[0];
        setPath(c0, start);
        try self.cv.init(t, &self.kit_root, self.alloc, "columns", .{ .ctx = self, .open = open, .truncated = truncated }, c0.listSource(), ANIM_MS);
        self.cv.hook = .{ .ctx = self, .on = columnEvent };
        self.preview = try t.create(.{ .background = tokens.color.surface });
        self.pv_name = try t.create(.{ .frame = .{ .x = 0, .y = 0, .w = tokens.size.preview, .h = PV_NAME_H }, .content = .{ .ctx = self, .draw = drawPreview } });
        self.pv_body = try t.create(.{ .frame = .{ .x = 0, .y = PV_NAME_H, .w = tokens.size.preview, .h = PV_BODY_H }, .content = .{ .ctx = self, .draw = drawBody } });
        try self.preview.addChild(self.pv_name);
        try self.preview.addChild(self.pv_body);
        try self.split.init(t, "split", self.cv.view.layer, self.preview, tokens.size.preview);
        self.split.notify = .{ .ctx = self, .on = laidOut };
        try self.root.addChild(self.split.view.layer);
        try self.root_view.addChild(self.alloc, &self.split.view);
        try self.split.view.addChild(self.alloc, &self.cv.view);
        try self.ensureOverlays();
        // 경로 바(TK-M4): 루트의 앞 자식, 평소 숨김. 필드 뷰는 루트 뷰의 자식 — 받지 않은 키가 루트 뷰를 지나 `unhandled`로 간다.
        self.bar = try t.create(.{ .background = tokens.color.bg, .masks = true, .hidden = true });
        self.bar_label = try t.create(.{ .content = .{ .ctx = self, .draw = drawBarLabel } });
        try self.field.init(t, "field", &self.small);
        self.field.delegate = .{ .ctx = self, .action = fieldAction, .copy = fieldCopy, .paste = fieldPaste, .changed = fieldChanged };
        try self.bar.addChild(self.bar_label);
        try self.bar.addChild(self.field.view.layer);
        try self.root.addChild(self.bar);
        try self.results.init(t, "results", .{ .ctx = self, .count = resultCount, .drawRow = drawResult }, ANIM_MS);
        self.results.view.layer.setHidden(true);
        try self.root.addChild(self.results.view.layer);
        try self.root_view.addChild(self.alloc, &self.field.view);
        self.kit_root.unhandled = .{ .ctx = self, .on = unhandled };
        self.cv.focusFirst();
        self.kit_root.setMenu(&MENU);
        self.startLoad(0, false);
    }

    fn deinit(self: *App) void {
        for (&self.cols) |*c| self.dropCol(c);
        self.cv.deinit();
        self.split.deinit(self.alloc);
        self.root_view.deinit(self.alloc);
        self.field.view.deinit(self.alloc);
        self.results.deinit(self.alloc);
        if (self.search) |*x| x.deinit();
        for (&self.cols) |*c| c.filtered.deinit(self.alloc);
        self.pv.deinit(self.alloc);
    }

    fn setPath(c: *Col, p: []const u8) void {
        const n = @min(p.len, c.path_buf.len);
        @memcpy(c.path_buf[0..n], p[0..n]);
        c.path_len = n;
    }

    // ── 로딩 ──────────────────────────────────────────────────────

    /// 열 `i`의 경로를 읽기 시작한다. `refresh`면 지금 목록을 그대로 보이며 새 목록을 따로 읽는다.
    fn startLoad(self: *App, i: usize, refresh: bool) void {
        const c = &self.cols[i];
        self.cancel(c);
        const l = self.alloc.create(model.Listing) catch return;
        l.* = model.Listing.init(self.alloc);
        c.refresh = refresh;
        c.t0 = nowNs();
        c.first_us = 0;
        c.paint_us = 0;
        c.read_us = 0;
        c.merge_us = 0;
        if (!refresh) {
            self.freeShown(c);
            self.clearFilter(c);
            c.shown = l;
            c.touched = false;
            c.failed = false;
        }
        c.loading = l;
        if (!refresh) self.updateOverlay(c);
        const src = self.source();
        c.handle = src.open(src.ctx, c.path()) catch {
            self.finish(c, .failed);
            return;
        };
    }

    /// 읽는 중이면 버린다(`tk> load … state=cancelled`). 첫 로딩이었으면 받은 만큼은 남는다(열을 버리는 쪽이 `dropCol`로 지운다).
    fn cancel(self: *App, c: *Col) void {
        const l = c.loading orelse return;
        if (c.handle) |h| {
            const src = self.source();
            src.close(src.ctx, h);
        }
        c.handle = null;
        self.sayLoad(c, l, "cancelled");
        c.loading = null;
        if (c.refresh) {
            l.deinit();
            self.alloc.destroy(l);
        } else {
            l.state = .done;
        }
    }

    fn freeShown(self: *App, c: *Col) void {
        c.filtered.clearRetainingCapacity();
        const l = c.shown orelse return;
        if (c.loading == l) c.loading = null;
        l.deinit();
        self.alloc.destroy(l);
        c.shown = null;
    }

    /// 필터를 지운다(열이 다른 경로로 다시 쓰이거나 버려질 때 — 확정 19).
    fn clearFilter(self: *App, c: *Col) void {
        _ = self;
        c.filter_len = 0;
        c.filtered.clearRetainingCapacity();
    }

    /// 필터 글로 `filtered`를 다시 짓는다(보이는 목록이 바뀔 때마다).
    fn rebuildFilter(self: *App, c: *Col) void {
        if (c.filter_len == 0) {
            c.filtered.clearRetainingCapacity();
            return;
        }
        model.filterInto(self.alloc, c.all(), c.filterText(), &c.filtered) catch c.filtered.clearRetainingCapacity();
    }

    /// 열을 비운다(취소 · 목록을 놓음).
    fn dropCol(self: *App, c: *Col) void {
        self.cancel(c);
        self.freeShown(c);
        self.clearFilter(c);
        c.failed = false;
        c.touched = false;
    }

    fn active(self: *App, i: usize) bool {
        return i < self.cv.n;
    }

    /// 조각 하나를 읽을 열 — 포커스 열 먼저, 그다음 왼쪽부터.
    fn pick(self: *App) ?*Col {
        const f = &self.cols[self.cv.focus];
        if (f.loading != null) return f;
        for (&self.cols) |*c| if (c.loading != null) return c;
        return null;
    }

    /// 창 층의 idle — 조각 하나. 읽을 것이 남았으면 참.
    fn idle(ctx: *anyopaque) bool {
        const self: *App = @ptrCast(@alignCast(ctx));
        if (self.pick()) |c| {
            self.step(c);
            return true;
        }
        // 미리보기는 디렉터리 로딩 뒤(plan 확정 13): 로딩 중에는 조각마다 선택(0행)이 바뀌어 읽어 봐야 곧 낡고, 끼어든 조각이 첫 그림을 늦춘다
        // (판정 18 — 끝나기 전에 항목이 그려져야 한다).
        if (self.pv_pending and self.small != null) {
            self.loadPreview();
            return true;
        }
        return self.searchStep();
    }

    fn step(self: *App, c: *Col) void {
        const l = c.loading.?;
        const src = self.source();
        const t0 = nowNs();
        const raws = src.next(src.ctx, c.handle.?) catch {
            self.finish(c, .failed);
            return;
        };
        const t1 = nowNs();
        c.read_us += (t1 - t0) / std.time.ns_per_us;
        const rs = raws orelse {
            self.finish(c, .done);
            return;
        };
        if (c.refresh or !self.active(c.index)) {
            _ = l.addChunk(rs) catch {
                self.finish(c, .failed);
                return;
            };
        } else {
            // 첫 로딩: 받은 만큼 바로 보인다. 선택은 건드리지 않았으면 0행, 건드렸으면 이름을 따라간다(확정 10).
            const list = self.cv.list(c.index);
            var before = self.beforeOf(c, list, c.touched);
            // 경로 바가 고른 이름(확정 14) — 그 이름을 만날 때까지 그것을 따라간다.
            if (c.want_len > 0) before = .{ .sel = .{ .name = c.want_buf[0..c.want_len], .kind = c.want_kind }, .index = list.selected, .offset = list.offset, .touched = true };
            _ = l.addChunk(rs) catch {
                self.finish(c, .failed);
                return;
            };
            self.rebuildFilter(c);
            const after = model.follow(before, c.entries(), list.viewH(), kit.List.rowH());
            list.restore(after.index orelse 0, after.offset);
            self.updateOverlay(c);
        }
        const t2 = nowNs();
        c.merge_us += (t2 - t1) / std.time.ns_per_us;
        if (l.chunks == 1) c.first_us = (t2 - c.t0) / std.time.ns_per_us;
        if (c.index == self.cv.focus) self.previewChanged();
    }

    fn beforeOf(self: *App, c: *Col, list: *kit.List, touched: bool) model.Before {
        _ = self;
        const items = c.entries();
        return .{
            .sel = if (items.len != 0 and list.selected < items.len) items[list.selected] else null,
            .index = list.selected,
            .offset = list.offset,
            .touched = touched,
        };
    }

    fn finish(self: *App, c: *Col, state: model.State) void {
        const l = c.loading orelse return;
        if (c.handle) |h| {
            const src = self.source();
            src.close(src.ctx, h);
        }
        c.handle = null;
        c.loading = null;
        l.state = state;
        self.sayLoad(c, l, if (state == .done) "done" else "error");
        if (!c.refresh) {
            c.failed = state == .failed;
            c.want_len = 0;
            if (self.active(c.index)) {
                self.updateOverlay(c);
                self.sayColumn(c.index);
            }
            return;
        }
        // 갱신: 다 읽었다 — 바꿔 끼우고 선택을 이름으로 따라간다(확정 12). 실패하면 옛 목록을 그대로 둔다.
        if (state != .done or !self.active(c.index)) {
            l.deinit();
            self.alloc.destroy(l);
            return;
        }
        const list = self.cv.list(c.index);
        const b = self.beforeOf(c, list, true);
        var name_buf: [256]u8 = undefined;
        const name = if (b.sel) |e| e.name[0..@min(e.name.len, name_buf.len)] else "-";
        @memcpy(name_buf[0..name.len], name);
        const was_dir = if (b.sel) |e| e.kind == .dir else false;
        // 바꿔 끼우고 필터를 새 목록으로 다시 거른 뒤 따라간다(갱신은 필터를 지킨다 — 확정 19). 옛 이름은 옛 목록을 놓기 전까지 산다.
        const old = c.shown;
        c.shown = l;
        self.rebuildFilter(c);
        const after = model.follow(b, c.entries(), list.viewH(), kit.List.rowH());
        list.restore(after.index orelse 0, after.offset);
        if (old) |o| {
            o.deinit();
            self.alloc.destroy(o);
        }
        self.updateOverlay(c);
        tk.window.say("refresh path={s} name={s} before={d} after={d}{s}", .{
            c.path(), name_buf[0..name.len], b.index, after.index orelse 0, if (after.gone) " gone=1" else "",
        });
        // 선택이 디렉터리였고 사라졌거나 다른 항목이 됐으면 오른쪽 열은 그 디렉터리의 것이 아니다.
        if (was_dir and after.gone and self.cv.n > c.index + 1) self.cv.truncate(c.index + 1);
        if (c.index == self.cv.focus) self.previewChanged();
    }

    fn sayLoad(self: *App, c: *Col, l: *model.Listing, state: []const u8) void {
        _ = self;
        const all = (nowNs() - c.t0) / std.time.ns_per_us;
        tk.window.say("load path={s} n={d} chunks={d} first_us={d} paint_us={d} all_us={d} read_us={d} merge_us={d} state={s}", .{
            c.path(), l.items().len, l.chunks, c.first_us, c.paint_us, all, c.read_us, c.merge_us, state,
        });
    }

    fn sayColumn(self: *App, i: usize) void {
        const c = &self.cols[i];
        const list = self.cv.list(i);
        const items = c.entries();
        const name = if (list.selected < items.len) items[list.selected].name else "-";
        // 행에 그려지는 이름(가운데 생략 — TK-M4 plan 확정 5). 글꼴이 아직 없으면(첫 configure 전) 이름 그대로다.
        var buf: [NAME_BUF]u8 = undefined;
        var shown = name;
        if (self.small) |*f| if (list.selected < items.len) {
            const s: f32 = @floatFromInt(self.scale);
            shown = shownName(f, name, nameWidth(f, s, tokens.size.column * s, items[list.selected].kind == .dir), &buf);
        };
        tk.window.say("column i={d} path={s} count={d} sel={d} name={s} shown={s}", .{ i, c.path(), items.len, list.selected, name, shown });
    }

    /// 창이 포커스를 다시 얻었다 — 보이는 열(읽는 중이 아닌 것)을 다시 읽는다.
    fn refreshAll(self: *App) void {
        for (0..self.cv.n) |i| {
            const c = &self.cols[i];
            if (c.loading != null or c.shown == null) continue;
            self.startLoad(i, true);
        }
    }

    // ── column view의 소스와 알림 ─────────────────────────────────────

    fn me(ctx: *anyopaque) *App {
        return @ptrCast(@alignCast(ctx));
    }

    fn open(ctx: *anyopaque, column: usize, row: usize) ?kit.ListSource {
        const self = me(ctx);
        const c = &self.cols[column];
        const items = c.entries();
        if (row >= items.len or items[row].kind != .dir) return null;
        const nc = &self.cols[column + 1];
        self.dropCol(nc);
        var buf: [1024]u8 = undefined;
        const p = model.join(&buf, c.path(), items[row].name) catch return null;
        setPath(nc, p);
        self.startLoad(column + 1, false);
        return nc.listSource();
    }

    fn truncated(ctx: *anyopaque, n: usize) void {
        const self = me(ctx);
        for (n..MAX) |i| self.dropCol(&self.cols[i]);
    }

    fn columnEvent(ctx: *anyopaque, cv: *kit.ColumnView, ev: kit.ColumnEvent) void {
        const self = me(ctx);
        switch (ev) {
            .columns => |e| {
                tk.window.say("columns n={d} focus={d} scroll={d}", .{ e.n, e.focus, e.scroll });
                self.ensureOverlays() catch {};
            },
            .select => |e| {
                self.cols[e.column].touched = true;
                self.cols[e.column].want_len = 0;
                if (e.changed) self.sayColumn(e.column);
            },
        }
        _ = cv;
        self.previewChanged();
    }

    // ── 위의 한 줄(0행) · 미리보기 ──────────────────────────────────────

    fn ensureOverlays(self: *App) !void {
        for (0..self.cv.n) |i| {
            const c = &self.cols[i];
            if (c.overlay == null) {
                const o = try self.tree.create(.{ .content = .{ .ctx = c, .draw = Col.drawOverlay } });
                try self.cv.list(i).view.layer.addChild(o);
                c.overlay = o;
            }
            self.placeOverlay(c);
            self.updateOverlay(c);
        }
    }

    fn placeOverlay(self: *App, c: *Col) void {
        const o = c.overlay orelse return;
        const h = self.cv.view.layer.frame.h;
        const rh = tokens.size.row;
        o.setFrame(.{ .x = 0, .y = @floor((h - rh) / 2), .w = tokens.size.column, .h = rh });
    }

    fn updateOverlay(self: *App, c: *Col) void {
        _ = self;
        const o = c.overlay orelse return;
        const st = c.status();
        o.setHidden(st == null);
        o.setNeedsDisplay();
    }

    fn drawPreview(ctx: *anyopaque, p: *tk.Painter, size: [2]f32, alpha: u8) anyerror!void {
        const self = me(ctx);
        const i = self.cv.focus;
        const c = &self.cols[i];
        const items = c.entries();
        const list = self.cv.list(i);
        if (list.selected >= items.len) return;
        const f = &self.small.?;
        const s: f32 = @floatFromInt(self.scale);
        const rh = tokens.size.row * s;
        const base: i32 = @intFromFloat(@round((rh + f.ascent - f.descent) / 2));
        var buf: [NAME_BUF]u8 = undefined;
        const shown = shownName(f, items[list.selected].name, @max(0, size[0] - 2 * LABEL_X * s), &buf);
        _ = try p.drawGlyphs(f, LABEL_X * s, base, shown, tokens.color.text_dim, alpha);
    }

    /// 선택이 바뀌었을 수 있다 — 이름 줄을 다시 그리고 본문은 idle에 맡긴다(plan 확정 13).
    fn previewChanged(self: *App) void {
        self.pv_name.setNeedsDisplay();
        self.pv_pending = true;
    }

    /// 포커스 열의 선택 항목(경로 · 이름 · 종류). 없으면 null.
    fn selected(self: *App, buf: []u8) ?struct { path: []const u8, name: []const u8, kind: model.Kind } {
        const i = self.cv.focus;
        const c = &self.cols[i];
        const items = c.entries();
        const list = self.cv.list(i);
        if (list.selected >= items.len) return null;
        const it = items[list.selected];
        const p = model.join(buf, c.path(), it.name) catch return null;
        return .{ .path = p, .name = it.name, .kind = it.kind };
    }

    /// idle 한 조각(plan 확정 13): 지금 선택이 본문의 것과 다르면 읽고 판정해 본문을 바꾼다. 같으면 아무것도 안 한다.
    fn loadPreview(self: *App) void {
        self.pv_pending = false;
        var pbuf: [4096]u8 = undefined;
        const sel = self.selected(&pbuf);
        const key = if (sel) |x| x.path else "";
        if (self.pv_scale == self.scale and std.mem.eql(u8, key, self.pv_key[0..self.pv_key_len])) return;
        @memcpy(self.pv_key[0..key.len], key);
        self.pv_key_len = key.len;
        self.pv_scale = self.scale;
        self.pv.deinit(self.alloc);
        self.pv = .none;
        self.pv_body.setNeedsDisplay();
        const x = sel orelse return tk.window.say("preview kind=none", .{});
        const t0 = nowNs();
        if (x.kind == .dir) {
            self.setIcon(x.name, .dir, 0);
            return tk.window.say("preview kind=icon reason=dir name={s} us={d}", .{ x.name, (nowNs() - t0) / std.time.ns_per_us });
        }
        var head = preview_mod.readHead(self.alloc, x.path, preview_mod.TEXT_HEAD) orelse {
            self.setIcon(x.name, .unreadable, 0);
            return tk.window.say("preview kind=icon reason=unreadable name={s}", .{x.name});
        };
        defer head.deinit(self.alloc);
        const kind = preview_mod.classify(head.bytes(), head.size);
        switch (kind) {
            .icon => |r| {
                self.setIcon(x.name, r, head.size);
                tk.window.say("preview kind=icon reason={s} name={s} bytes={d} us={d}", .{ @tagName(r), x.name, head.size, (nowNs() - t0) / std.time.ns_per_us });
            },
            .text => {
                const buf = self.alloc.alloc(u8, head.n * 4) catch return;
                const t = preview_mod.textOf(head.bytes(), buf);
                self.pv = .{ .text = .{ .buf = buf, .len = t.len } };
                const lines = self.textLines(null, t, 255);
                tk.window.say("preview kind=text name={s} lines={d} bytes={d} us={d}", .{ x.name, lines, head.size, (nowNs() - t0) / std.time.ns_per_us });
            },
            .png, .jpeg => {
                var full = preview_mod.readHead(self.alloc, x.path, preview_mod.IMAGE_MAX) orelse {
                    self.setIcon(x.name, .unreadable, head.size);
                    return tk.window.say("preview kind=icon reason=unreadable name={s}", .{x.name});
                };
                defer full.deinit(self.alloc);
                const fmt = @tagName(kind);
                const hd = image.info(full.bytes()) catch |e| {
                    self.setIcon(x.name, if (e == error.TooBig) .big else .unreadable, head.size);
                    return tk.window.say("preview kind=icon reason={s} name={s} format={s}", .{ if (e == error.TooBig) "big" else "unreadable", x.name, fmt });
                };
                const t1 = nowNs();
                const img = image.decodeFit(self.alloc, full.bytes(), PV_IMG_W, PV_BODY_H, self.scale) catch |e| {
                    self.setIcon(x.name, if (e == error.TooBig) .big else .unreadable, head.size);
                    return tk.window.say("preview kind=icon reason={s} name={s} format={s}", .{ if (e == error.TooBig) "big" else "unreadable", x.name, fmt });
                };
                self.pv = .{ .image = img };
                const lw = img.w / self.scale;
                const lh = img.h / self.scale;
                tk.window.say("preview kind={s} name={s} w={d} h={d} shown={d}x{d} at={d},{d} bytes={d} decode_us={d} us={d}", .{
                    fmt, x.name, hd.w, hd.h, lw, lh, imageX(lw), PV_NAME_H, full.n, (nowNs() - t1) / std.time.ns_per_us, (nowNs() - t0) / std.time.ns_per_us,
                });
            },
        }
    }

    fn setIcon(self: *App, name: []const u8, reason: preview_mod.Reason, size: u64) void {
        var ic: Icon = .{ .dir = reason == .dir };
        const what = switch (reason) {
            .dir => "폴더",
            .binary => "이진 파일",
            .big => "너무 큼",
            .unreadable => "열 수 없음",
        };
        const line = if (reason == .dir)
            std.fmt.bufPrint(&ic.info, "{s}", .{what}) catch ""
        else
            std.fmt.bufPrint(&ic.info, "{s} · {d} 바이트", .{ what, size }) catch "";
        ic.info_len = line.len;
        _ = name;
        self.pv = .{ .icon = ic };
    }

    /// 텍스트를 판 폭에 줄 나누기(R-TXT-1 — `layout.wrap`)해 판 높이까지. `p`가 있으면 그리고, 없으면 줄 수만 센다.
    fn textLines(self: *App, p: ?*tk.Painter, t: []const u8, alpha: u8) usize {
        const f = if (self.small) |*x| x else return 0;
        const s: f32 = @floatFromInt(self.scale);
        const max_w = (tokens.size.preview - 2 * LABEL_X) * s;
        const lh = f.line_height;
        const max_lines: usize = @intFromFloat(@floor(PV_BODY_H * s / lh));
        var n: usize = 0;
        // 끝의 줄 바꿈 뒤 빈 조각은 줄이 아니다.
        const body = if (t.len > 0 and t[t.len - 1] == '\n') t[0 .. t.len - 1] else t;
        if (body.len == 0) return 0;
        var it = std.mem.splitScalar(u8, body, '\n');
        while (it.next()) |para| {
            if (n >= max_lines) break;
            const stops = self.alloc.alloc(tk.layout.Stop, para.len + 1) catch return n;
            defer self.alloc.free(stops);
            const lines = self.alloc.alloc(tk.layout.Line, para.len + 1) catch return n;
            defer self.alloc.free(lines);
            const got = tk.layout.wrap(f.metrics(), para, max_w, stops, lines) catch return n;
            for (got) |ln| {
                if (n >= max_lines) break;
                if (p) |pp| {
                    const base: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(n)) * lh + f.ascent));
                    _ = pp.drawGlyphs(f, LABEL_X * s, base, para[ln.start..ln.end], tokens.color.text, alpha) catch {};
                }
                n += 1;
            }
        }
        return n;
    }

    /// 본문 그리기 — 글(위 왼쪽 16부터, 줄 높이 = 글꼴), 그림(가운데 · 위), 아이콘(z2d 도형 + 한 줄).
    fn drawBody(ctx: *anyopaque, p: *tk.Painter, size: [2]f32, alpha: u8) anyerror!void {
        _ = size;
        const self = me(ctx);
        const s: f32 = @floatFromInt(self.scale);
        switch (self.pv) {
            .none => {},
            .text => |t| _ = self.textLines(p, t.buf[0..t.len], alpha),
            .image => |*img| {
                const lw = img.w / self.scale;
                p.drawImage(img.view(), @intCast(imageX(lw) * self.scale), 0);
            },
            .icon => |*ic| {
                if (ic.dir) {
                    try p.fillRoundedRect(.{ .x = 76 * s, .y = 4 * s, .w = 20 * s, .h = 10 * s }, 2 * s, tokens.color.accent, alpha);
                    try p.fillRoundedRect(.{ .x = 76 * s, .y = 10 * s, .w = 48 * s, .h = 36 * s }, 4 * s, tokens.color.accent, alpha);
                } else {
                    try p.fillRoundedRect(.{ .x = 80 * s, .y = 4 * s, .w = 40 * s, .h = 48 * s }, 4 * s, tokens.color.text_dim, alpha);
                }
                const f = if (self.small) |*x| x else return;
                const base: i32 = @intFromFloat(@round(72 * s));
                _ = try p.drawGlyphs(f, LABEL_X * s, base, ic.info[0..ic.info_len], tokens.color.text_dim, alpha);
            },
        }
    }

    fn laidOut(ctx: *anyopaque, _: *kit.SplitView) void {
        const self = me(ctx);
        self.cv.sync();
        for (0..self.cv.n) |i| self.placeOverlay(&self.cols[i]);
    }

    // ── 창 ───────────────────────────────────────────────────────

    fn resize(ctx: *anyopaque, width: u32, height: u32, s: u32) void {
        const self = me(ctx);
        self.tree.setScale(s);
        // 글꼴을 여기서도 맞춘다 — 그리기 전의 `tk> column` 줄(첫 로딩의 끝)이 생략한 이름(`shown=`)을 낼 수 있게. 실패하면 `draw`가 다시 해 본다.
        self.faces(s) catch {};
        if (s != self.pv_scale) self.pv_pending = true;
        self.width = @floatFromInt(width / s);
        self.height = @floatFromInt(height / s);
        self.root.setFrame(.{ .x = 0, .y = 0, .w = self.width, .h = self.height });
        self.relayout();
    }

    /// 바가 열려 있으면 [바 32 | 분할 뷰], 아니면 분할 뷰가 창 전체(TK-M3과 같은 자리).
    fn relayout(self: *App) void {
        const W = self.width;
        const H = self.height;
        if (self.bar_open) {
            const bh = tokens.size.bar;
            self.bar.setFrame(.{ .x = 0, .y = 0, .w = W, .h = bh });
            self.bar_label.setFrame(.{ .x = LABEL_X, .y = 0, .w = FIELD_X - LABEL_X, .h = bh });
            self.field.view.layer.setFrame(.{ .x = FIELD_X, .y = (bh - tokens.size.field) / 2, .w = @max(0, W - FIELD_X - FIELD_RIGHT), .h = tokens.size.field });
            self.split.layout(.{ .x = 0, .y = bh, .w = W, .h = @max(0, H - bh) });
            if (self.mode == .search) {
                self.results.view.layer.setFrame(.{ .x = 0, .y = bh, .w = self.cv.view.layer.frame.w, .h = @max(0, H - bh) });
                self.results.sync();
            }
        } else {
            self.split.layout(.{ .x = 0, .y = 0, .w = W, .h = H });
        }
    }

    // ── 경로 바 · 경로 복사(TK-M4) ─────────────────────────────────────

    fn drawBarLabel(ctx: *anyopaque, p: *tk.Painter, size: [2]f32, alpha: u8) anyerror!void {
        const self = me(ctx);
        const f = if (self.small) |*x| x else return;
        const base: i32 = @intFromFloat(@round((size[1] + f.ascent - f.descent) / 2));
        _ = try p.drawGlyphs(f, 0, base, self.mode.label(), tokens.color.text_dim, alpha);
    }

    /// 바를 연다(`Cmd+L` 경로 · `Cmd+F` 필터 · `Cmd+K` 검색 — plan 확정 18). 경로는 포커스 열의 경로로 채우고(캐럿은 끝), 필터는 그 열에 남은 글로,
    /// 검색은 빈 글로 걷기를 시작한다. 열린 바에서 다른 모드 키는 모드를 바꾸고 필드를 비운다.
    fn openBar(self: *App, mode: Mode) void {
        const switching = self.bar_open and self.mode != mode;
        if (self.bar_open and self.mode == .search and mode != .search) self.stopSearch();
        if (!self.bar_open or switching or mode == .path) {
            self.mode = mode;
            switch (mode) {
                .path => self.field.setText(self.cols[self.cv.focus].path()),
                .filter => {
                    self.filter_col = self.cv.focus;
                    self.field.setText(if (switching) "" else self.cols[self.filter_col].filterText());
                },
                .search => {
                    self.field.setText("");
                    self.startSearch();
                },
            }
            self.bar_label.setNeedsDisplay();
            if (mode != .path) tk.window.say("bar mode={s}", .{@tagName(mode)});
        }
        if (!self.bar_open) {
            self.bar_open = true;
            self.bar.setHidden(false);
            tk.window.say("bar open", .{});
        }
        self.relayout();
        _ = self.kit_root.setFirstResponder(&self.field.view);
    }

    fn closeBar(self: *App) void {
        if (!self.bar_open) return;
        if (self.mode == .search) self.stopSearch();
        self.cv.focusFirst();
        self.bar_open = false;
        self.bar.setHidden(true);
        self.field.setText("");
        self.relayout();
        tk.window.say("bar close", .{});
    }

    fn fieldAction(ctx: *anyopaque, field: *kit.TextField, a: kit.textfield.Action) void {
        const self = me(ctx);
        tk.window.say("field text={s} action={s}", .{ field.text(), @tagName(a) });
        switch (self.mode) {
            .path => switch (a) {
                .escape => self.closeBar(),
                .enter => self.submitPath(),
            },
            // Enter는 바만 닫고 필터는 남긴다, Esc는 필터를 풀고 닫는다(확정 19).
            .filter => {
                if (a == .escape) self.applyFilter(self.filter_col, "");
                self.closeBar();
            },
            .search => switch (a) {
                .escape => self.closeBar(),
                .enter => self.openResult(),
            },
        }
    }

    /// 필드의 글이 바뀌었다 — 필터 · 검색은 타이핑마다 다시 건다.
    fn fieldChanged(ctx: *anyopaque, field: *kit.TextField) void {
        const self = me(ctx);
        if (!self.bar_open) return;
        switch (self.mode) {
            .path => {},
            .filter => self.applyFilter(self.filter_col, field.text()),
            .search => self.searchQuery(field.text()),
        }
    }

    // ── 필터(TK-M4 plan 확정 19) ───────────────────────────────────

    /// 열 `i`에 필터 글 `text`를 건다(빈 글이면 푼다). 선택은 이름으로 따라가고, 다른 항목이 되면 오른쪽 열을 버린다.
    fn applyFilter(self: *App, i: usize, text: []const u8) void {
        if (!self.active(i)) return;
        const c = &self.cols[i];
        const list = self.cv.list(i);
        const b = self.beforeOf(c, list, true);
        const was_dir = if (b.sel) |e| e.kind == .dir else false;
        const n = @min(text.len, c.filter_buf.len);
        @memcpy(c.filter_buf[0..n], text[0..n]);
        c.filter_len = n;
        self.rebuildFilter(c);
        const after = model.follow(b, c.entries(), list.viewH(), kit.List.rowH());
        list.restore(after.index orelse 0, after.offset);
        if (was_dir and after.gone and self.cv.n > i + 1) self.cv.truncate(i + 1);
        self.updateOverlay(c);
        self.previewChanged();
        tk.window.say("filter text={s} n={d}", .{ c.filterText(), c.entries().len });
    }

    // ── 검색(TK-M4 plan 확정 20) ───────────────────────────────────

    fn clockMs(_: *anyopaque) u64 {
        return nowNs() / std.time.ns_per_ms;
    }

    fn startSearch(self: *App) void {
        self.stopSearch();
        const w = search_mod.Walker.init(self.alloc, self.source(), .{ .ctx = self, .now_ms = clockMs }, self.cols[0].path());
        self.search = search_mod.Search.init(self.alloc, w);
        self.search_said = false;
        self.results.reset(.{ .ctx = self, .count = resultCount, .drawRow = drawResult });
        self.results.view.layer.setHidden(false);
    }

    fn stopSearch(self: *App) void {
        if (self.search) |*x| x.deinit();
        self.search = null;
        self.results.view.layer.setHidden(true);
    }

    /// 걷기 한 조각(창 층의 idle). 새 항목을 지금 질의로 본다. 걷기가 끝나면 줄 하나.
    fn searchStep(self: *App) bool {
        const sr = if (self.search) |*x| x else return false;
        const before = sr.top_n;
        const more = sr.walker.step();
        const old_scanned = sr.scanned;
        sr.scanNew() catch {};
        if (sr.top_n != before or (sr.scanned != old_scanned and sr.query_len > 0)) self.results.reload();
        if (!more and !self.search_said) {
            self.search_said = true;
            tk.window.say("search walked={d} ms={d} capped={d} results={d}", .{ sr.walker.items.items.len, sr.walker.ms, @intFromBool(sr.walker.capped), sr.top_n });
        }
        return more;
    }

    fn searchQuery(self: *App, text: []const u8) void {
        const sr = if (self.search) |*x| x else return;
        const t0 = nowNs();
        sr.setQuery(text) catch {};
        const us = (nowNs() - t0) / std.time.ns_per_us;
        self.results.restore(0, 0);
        tk.window.say("search query={s} walked={d} results={d} score_us={d}", .{ sr.query(), sr.walker.items.items.len, sr.top_n, us });
    }

    fn resultCount(ctx: *anyopaque) usize {
        const self = me(ctx);
        return if (self.search) |*x| x.top_n else 0;
    }

    fn drawResult(ctx: *anyopaque, p: *tk.Painter, index: usize, rect: tk.Rect, state: kit.RowState) anyerror!void {
        const self = me(ctx);
        const sr = if (self.search) |*x| x else return;
        if (index >= sr.top_n) return;
        const f = &self.small.?;
        const s: f32 = @floatFromInt(self.scale);
        const rel = sr.walker.path(sr.top[index].item);
        const base: i32 = rect.y + @as(i32, @intFromFloat(@round((@as(f32, @floatFromInt(rect.h)) + f.ascent - f.descent) / 2)));
        const x0: f32 = @floatFromInt(rect.x);
        var buf: [NAME_BUF]u8 = undefined;
        var sc: [NAME_STOPS]tk.layout.Stop = undefined;
        const w = nameWidth(f, s, @floatFromInt(rect.w), false);
        const shown = tk.layout.elideMiddle(f.metrics(), rel, w, &sc, &buf) catch rel;
        _ = try p.drawGlyphs(f, x0 + LABEL_X * s, base, shown, tokens.color.text, state.alpha);
    }

    /// 검색의 Enter: 고른 결과를 경로 바의 Enter와 같은 길로(파일이면 부모까지 열고 선택).
    fn openResult(self: *App) void {
        const sr = if (self.search) |*x| x else return;
        if (sr.top_n == 0) return;
        const hit = sr.top[@min(self.results.selected, sr.top_n - 1)];
        const it = sr.walker.items.items[hit.item];
        var tbuf: [8192]u8 = undefined;
        const target = model.join(&tbuf, sr.walker.root(), sr.walker.path(hit.item)) catch return;
        tk.window.say("search open={s}", .{target});
        self.openTarget(target, it.kind);
    }

    /// 경로 바의 Enter(plan 확정 14).
    fn submitPath(self: *App) void {
        var tbuf: [4096]u8 = undefined;
        const target = model.resolvePath(&tbuf, self.field.text(), self.cols[self.cv.focus].path(), self.home) catch |e| {
            tk.window.say("path error={s} text={s}", .{ @errorName(e), self.field.text() });
            return;
        };
        const kind = dir_mod.kindOf(target) orelse {
            tk.window.say("path error=NotFound text={s}", .{target});
            return;
        };
        self.openTarget(target, kind);
    }

    /// 경로 `target`(정규화된 절대 경로, 종류 `kind`)으로 열을 다시 세운다 — 바를 닫는다(검색이면 걷기도 멈춘다 — `target`은 부르는 쪽의 칸이어야 한다).
    fn openTarget(self: *App, target: []const u8, kind: model.Kind) void {
        const dir_path = if (kind == .dir) target else model.dirname(target);
        var pbuf: [MAX][]const u8 = undefined;
        const paths = model.columnPaths(self.cols[0].path(), dir_path, &pbuf) catch |e| {
            tk.window.say("path error={s} text={s}", .{ @errorName(e), target });
            return;
        };
        // 열의 경로 칸을 덮어쓰기 전에 옮긴다 — 조각이 열 0의 경로를 가리킬 수 있다.
        var copy_buf: [4096]u8 = undefined;
        @memcpy(copy_buf[0..dir_path.len], dir_path);
        var copies: [MAX][]const u8 = undefined;
        for (paths, 0..) |p, i| copies[i] = if (std.mem.eql(u8, p, "/")) "/" else copy_buf[0..p.len];
        var last: [256]u8 = undefined;
        const last_name = if (kind == .file) model.basename(target) else "";
        const ln = @min(last_name.len, last.len);
        @memcpy(last[0..ln], last_name[0..ln]);
        self.closeBar();
        self.applyPath(copies[0..paths.len], last[0..ln]);
    }

    /// 열을 `paths`로 다시 세운다. 각 열은 다음 열의 이름을, 마지막 열은 `last_file`(파일 목표면)을 고른다.
    fn applyPath(self: *App, paths: []const []const u8, last_file: []const u8) void {
        const n = paths.len;
        self.cv.truncate(1);
        for (paths, 0..) |p, i| {
            const c = &self.cols[i];
            self.dropCol(c);
            setPath(c, p);
            const want = if (i + 1 < n) model.basename(paths[i + 1]) else last_file;
            const k = @min(want.len, c.want_buf.len);
            @memcpy(c.want_buf[0..k], want[0..k]);
            c.want_len = k;
            c.want_kind = if (i + 1 < n) .dir else .file;
        }
        var srcs: [MAX]kit.ListSource = undefined;
        for (0..n) |i| srcs[i] = self.cols[i].listSource();
        self.cv.setColumns(srcs[0..n]) catch {};
        for (0..self.cv.n) |i| self.startLoad(i, false);
        self.ensureOverlays() catch {};
        self.cv.focusFirst();
        self.previewChanged();
    }

    /// `Cmd+C`(필드가 아닐 때): 포커스 열의 선택 항목 경로(R-FM-8).
    fn copyPath(self: *App) void {
        const i = self.cv.focus;
        const c = &self.cols[i];
        const items = c.entries();
        const list = self.cv.list(i);
        if (list.selected >= items.len) return;
        var buf: [4096]u8 = undefined;
        const p = model.join(&buf, c.path(), items[list.selected].name) catch return;
        tk.window.say("copy path={s}", .{p});
        if (self.win) |w| w.copyText(p);
    }

    /// 체인 끝까지 아무도 안 받은 키 — 검색 중 필드가 넘긴 `↑` `↓`(단축키는 메뉴 모델 `MENU`가 맞춘다, TK-M6).
    fn unhandled(ctx: *anyopaque, ev: tk.input.KeyEvent) void {
        const self = me(ctx);
        const md = ev.mods;
        if (self.bar_open and self.mode == .search and md.none() and (ev.key == .up or ev.key == .down)) {
            const n = self.results.count();
            if (n == 0) return;
            const sel = self.results.selected;
            self.results.select(if (ev.key == .up) sel -| 1 else @min(sel + 1, n - 1));
        }
    }

    /// 앱의 action이 지금 되는가(루트 뷰 — chain의 끝, plan 확정 9). `copy`는 포커스 열에 선택 항목이 있을 때(필드가 포커스면 필드가 먼저 답한다).
    /// 필드의 것(되돌리기 · 오려두기 · 붙여넣기 · 전체 선택)은 모른다 — 필드가 포커스가 아니면 비활성이 된다.
    fn rootValidate(ctx: *anyopaque, action: u32) ?bool {
        const self = me(ctx);
        return switch (action) {
            tk.menu.COPY => self.hasSelection(),
            A_QUIT, A_FILTER, A_PREVIEW, A_REFRESH, A_GOTO, A_SEARCH => true,
            else => null,
        };
    }

    fn rootPerform(ctx: *anyopaque, action: u32) bool {
        const self = me(ctx);
        switch (action) {
            tk.menu.COPY => self.copyPath(),
            A_QUIT => if (self.win) |w| w.quit(),
            A_FILTER => self.openBar(.filter),
            A_PREVIEW => self.togglePreview(),
            A_REFRESH => self.refreshAll(),
            A_GOTO => self.openBar(.path),
            A_SEARCH => self.openBar(.search),
            else => return false,
        }
        return true;
    }

    fn hasSelection(self: *App) bool {
        const i = self.cv.focus;
        return self.cv.list(i).selected < self.cols[i].entries().len;
    }

    /// `Space`(plan 확정 14): 미리보기 판을 감추고(폭 0) 다시 보인다. 시작은 보임.
    fn togglePreview(self: *App) void {
        self.preview_on = !self.preview_on;
        self.split.second_w = if (self.preview_on) tokens.size.preview else 0;
        self.preview.setHidden(!self.preview_on);
        self.relayout();
        tk.window.say("preview shown={d}", .{@intFromBool(self.preview_on)});
    }

    fn fieldCopy(ctx: *anyopaque, bytes: []const u8) void {
        if (me(ctx).win) |w| w.copyText(bytes);
    }

    fn fieldPaste(ctx: *anyopaque, buf: []u8) ?[]const u8 {
        const w = me(ctx).win orelse return null;
        return w.pasteText(buf);
    }

    fn input(ctx: *anyopaque, ev: tk.input.Event) void {
        const self = me(ctx);
        self.kit_root.handle(ev);
        switch (ev) {
            .focus => |on| if (on) {
                if (self.had_focus) self.refreshAll();
                self.had_focus = true;
            },
            else => {},
        }
    }

    fn tick(ctx: *anyopaque, now_ns: u64) void {
        me(ctx).tree.tick(now_ns);
    }

    fn draw(ctx: *anyopaque, frame: tk.window.Frame) anyerror!void {
        const self = me(ctx);
        try self.faces(frame.scale);
        try tk.drawTree(self.io, self.alloc, &self.tree, frame, &self.lut);
        // 첫 로딩 중 항목이 처음 보인 그림(스트리밍의 증거 — `paint_us`).
        for (&self.cols) |*c| {
            if (c.loading != null and !c.refresh and c.paint_us == 0 and c.entries().len != 0 and self.active(c.index))
                c.paint_us = @max(1, (nowNs() - c.t0) / std.time.ns_per_us);
        }
    }
};

const ROOT_VT: kit.VTable = .{ .perform = App.rootPerform, .validate = App.rootValidate };

// ── 미리보기의 자리(논리 px, 판 왼쪽 위 기준 — TK-M6 plan 확정 12 · 13) ─────────────────────────
// 이름 한 줄 0..40, 본문 40..360. 판정 15의 상자(판 y 380..680)에 닿지 않게 본문을 360에서 끊는다. 그림은 폭 168(좌우 16) · 높이 320 안에
// 맞추고(확대 없음) 가로 가운데 · 본문 위에 놓는다.
const PV_NAME_H: f32 = 40;
const PV_BODY_H: f32 = 320;
const PV_IMG_W: u32 = 168;

/// 그림의 x(논리) — 판 폭 200의 가운데.
fn imageX(w: u32) u32 {
    const pw: u32 = @intFromFloat(tokens.size.preview);
    return if (w >= pw) 0 else (pw - w) / 2;
}

const Icon = struct {
    dir: bool,
    info: [64]u8 = undefined,
    info_len: usize = 0,
};

/// 미리보기 본문(plan 확정 12).
const Preview = union(enum) {
    none,
    text: struct { buf: []u8, len: usize },
    image: image.Image,
    icon: Icon,

    fn deinit(self: *Preview, alloc: std.mem.Allocator) void {
        switch (self.*) {
            .text => |t| alloc.free(t.buf),
            .image => |*img| img.deinit(alloc),
            else => {},
        }
        self.* = .none;
    }
};

const menus = @import("menus.zig");
const MENU = menus.MENU;
const A_QUIT = menus.A_QUIT;
const A_FILTER = menus.A_FILTER;
const A_PREVIEW = menus.A_PREVIEW;
const A_REFRESH = menus.A_REFRESH;
const A_GOTO = menus.A_GOTO;
const A_SEARCH = menus.A_SEARCH;

/// 바의 모드(TK-M4 plan 확정 18).
const Mode = enum {
    path,
    filter,
    search,

    fn label(self: Mode) []const u8 {
        return switch (self) {
            .path => "경로",
            .filter => "필터",
            .search => "검색",
        };
    }
};

/// 시작 경로: 인자 → `$HOME` → `/`. 끝의 `/`는 뗀다(루트는 그대로).
fn startPath(arg: ?[]const u8, home: ?[]const u8) []const u8 {
    var p = arg orelse home orelse "/";
    if (p.len == 0) p = "/";
    while (p.len > 1 and p[p.len - 1] == '/') p = p[0 .. p.len - 1];
    return p;
}

pub fn main(init: std.process.Init) !u8 {
    const alloc = init.gpa;
    const argv = try init.minimal.args.toSlice(init.arena.allocator());
    if (argv.len > 2) {
        tk.window.say("usage: tars-files [PATH]", .{});
        return 2;
    }
    const start = startPath(if (argv.len == 2) argv[1] else null, init.environ_map.get("HOME"));
    tk.window.say("files path={s}", .{start});

    const font = std.Io.Dir.cwd().readFileAlloc(init.io, tk.FONT_PATH, alloc, .unlimited) catch |e| {
        tk.window.say("error font={s} path={s}", .{ @errorName(e), tk.FONT_PATH });
        return 1;
    };
    defer alloc.free(font);

    var app: App = .{
        .io = init.io,
        .alloc = alloc,
        .font = font,
        .lut = tk.text.gammaLut(tk.text.GAMMA),
        .tree = tk.Tree.init(alloc),
        .dir = .{ .alloc = alloc },
        .home = init.environ_map.get("HOME"),
    };
    defer app.tree.deinit();
    defer if (app.small) |*x| x.deinit();
    app.build(start) catch |e| {
        tk.window.say("error tree={s}", .{@errorName(e)});
        return 1;
    };
    defer app.deinit();
    const win = tk.Window.open(alloc, "tars-files", .{
        .ctx = &app,
        .draw = App.draw,
        .resize = App.resize,
        .input = App.input,
        .tick = App.tick,
        .idle = App.idle,
    }, .{ .menu = &MENU, .disabled = &app.kit_root.disabled }) catch |e| {
        tk.window.say("error open={s}", .{@errorName(e)});
        return 1;
    };
    defer win.deinit();
    app.win = win;
    tk.connect(&app.tree, win);
    tk.connectIme(&app.kit_root, win);
    tk.connectMenu(&app.kit_root, win);
    win.run() catch |e| {
        tk.window.say("error run={s}", .{@errorName(e)});
        return 1;
    };
    sayRss();
    return 0;
}

/// `tk> rss vmrss_kb= vmhwm_kb=` — /proc/self/status의 두 줄(끝날 때, plan 실측 2 · 7).
fn sayRss() void {
    const fd_rc = linux.open("/proc/self/status", .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (linux.errno(fd_rc) != .SUCCESS) return;
    const fd: i32 = @intCast(fd_rc);
    defer _ = linux.close(fd);
    var buf: [4096]u8 = undefined;
    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (linux.errno(n) != .SUCCESS or n == 0) break;
        len += n;
    }
    tk.window.say("rss vmrss_kb={d} vmhwm_kb={d}", .{ statusKb(buf[0..len], "VmRSS:"), statusKb(buf[0..len], "VmHWM:") });
}

fn statusKb(text: []const u8, key: []const u8) u64 {
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (!std.mem.startsWith(u8, line, key)) continue;
        var words = std.mem.tokenizeAny(u8, line[key.len..], " \t");
        const w = words.next() orelse return 0;
        return std.fmt.parseInt(u64, w, 10) catch 0;
    }
    return 0;
}
