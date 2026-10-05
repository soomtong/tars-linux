//! 클립보드와 그 범위(CB design 결정 1 · 2).
//!
//! 순수 모듈이다. 시스템 콜도 ghostty도 모른다 — `layout.zig` · `status.zig`가
//! 따로 서는 이유와 같다. 그래서 `clipboard_test`가 컨테이너에서 초 단위로
//! 돌고, 소유권(옛것을 해제한다 · 빈 것은 null이다)과 범위 고르기를 부팅
//! 없이 본다.
//!
//! CB 전에는 클립보드가 `vt.Screen`의 칸 하나(`clip`)였다. CM design 결정 1이
//! 그렇게 정했을 때는 화면이 하나였고, WP가 패널마다 `Screen`을 하나씩 두면서
//! 클립보드도 패널 수만큼 생겼다. 그것을 밖으로 낸 것이 이 파일이다 —
//! 선택을 문자열로 만드는 일은 여전히 `vt.zig`(`copyYank`)이고, 그 문자열을
//! 누가 갖는지가 여기다.

const std = @import("std");

/// 클립보드를 누구와 나누는가(CB design 결정 2). `tars.conf`의
/// `clipboard=` 값이고, init이 argv의 아홉째 칸으로 넘긴다.
///
/// 이름이 `init/src/config.zig`의 `ClipboardScope`와 짝이어야 한다. 둘을
/// 잇는 것은 argv의 문자열 하나뿐이라 컴파일러가 못 잡는다 — 자판 이름
/// (`HangulLayout` ↔ `hangul.Layout`)과 같은 자리다. 어긋나면 증상은 "설정을
/// 적었는데 기본값으로 뜬다"이고, 부팅 로그의 `terminal: clipboard scope=`
/// 줄이 그것을 보인다.
pub const Scope = enum {
    /// 모든 패널과 모든 워크스페이스가 하나를 쓴다. 기본값이다.
    shared,
    /// 패널마다 하나다. CB 전의 동작과 같다.
    pane,
};

/// 문자열 하나를 소유하는 칸.
///
/// `set`이 옛것을 해제하고 새것을 받는다. 그래서 문자열은 다음 `set`까지만
/// 유효하다 — `text()`가 돌려준 슬라이스를 `set` 뒤에 쓰면 해제된 메모리다.
/// `main.zig`는 `y` 한 번에 `copyYank` → `dumpClip`으로 바로 찍고 버리므로
/// 그 사이에 `set`이 끼지 않는다.
pub const Clipboard = struct {
    /// 문자열을 할당하고 해제하는 쪽. `copyYank`가 이것으로 선택 문자열을
    /// 만든다 — 할당한 쪽과 해제하는 쪽이 같은 할당자여야 하기 때문이다.
    alloc: std.mem.Allocator,
    /// sentinel이 있는 것은 라이브러리의 `selectionString`이 그렇게 주기
    /// 때문이다. 밖에는 `text()`가 sentinel을 뗀 슬라이스로 낸다.
    buf: ?[:0]const u8 = null,

    pub fn init(alloc: std.mem.Allocator) Clipboard {
        return .{ .alloc = alloc };
    }

    /// `owned`를 받는다. `owned`는 `self.alloc`으로 할당한 것이어야 한다.
    /// 옛것이 있으면 해제한다.
    pub fn set(self: *Clipboard, owned: [:0]const u8) void {
        if (self.buf) |old| self.alloc.free(old);
        self.buf = owned;
    }

    /// 지금 내용. 한 번도 `set`하지 않았으면 null이다.
    ///
    /// 반환 타입이 `?[]const u8`인 이유는 CB 전의 `Screen.clipboard()`와
    /// 같다 — sentinel을 밖으로 내보내면 호출부가 그것을 직접 free해도 되는
    /// 값으로 오해할 여지가 생긴다. 먼저 풀고 나서 돌려주는 것도 같은
    /// 이유다(optional 껍질째로는 sentinel을 떼는 coercion이 안 된다).
    pub fn text(self: *const Clipboard) ?[]const u8 {
        const t = self.buf orelse return null;
        return t;
    }

    /// 값으로 받는다. `main.zig`의 정리 `defer`가 패널을 값으로 훑으므로
    /// (`for (w.panes) |maybe|`) 포인터를 요구하면 그 자리에서 부를 수 없다.
    /// 해제한 뒤의 칸은 다시 쓰지 않는다 — 패널을 닫는 자리는 바로 뒤에 그
    /// 칸을 null로 지운다.
    pub fn deinit(self: Clipboard) void {
        if (self.buf) |t| self.alloc.free(t);
    }
};

/// 범위가 고르는 칸(CB design 결정 2). `shared`면 공유 칸, `pane`이면 그
/// 패널의 칸이다.
///
/// `main.zig`의 네 자리(`y` · 포인터 뗌 · `Cmd+V` · 검색창의 `Cmd+V`)가
/// 전부 이것을 지난다. 판단이 여기 한 줄이라 `clipboard_test`가 부팅 전에
/// 본다.
pub fn pick(scope: Scope, shared: *Clipboard, own: *Clipboard) *Clipboard {
    return switch (scope) {
        .shared => shared,
        .pane => own,
    };
}
