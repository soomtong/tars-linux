//! 버퍼 나이(TK design 결정 9, TK-M1 plan 확정 5). 창 층의 순수 부분이라 호스트 검사가 Wayland 없이 부른다.
//!
//! 왜 필요한가: 서버는 언제든 붙은 버퍼 전체를 읽을 수 있다(통째 프레임, 놓는 자리가 바뀜 — WY design 결정 47, `server.zig`의
//! `damageFor`). 그래서 버퍼는 commit 때 늘 전체가 맞는 그림이어야 하고, 바뀐 곳만 그리려면 "이 버퍼에 마지막으로 그린 뒤 다른
//! 버퍼에 그린 프레임들"의 더티까지 이 버퍼에 다시 그려야 한다. 버퍼가 둘이고 번갈아 쓰이면 그 프레임은 하나다.
//!
//! 프레임마다 번호(`seq`)를 붙이고 최근 `HISTORY`개 프레임의 더티를 둔다. 버퍼는 자기에게 마지막으로 그린 번호를 든다.

const Rect = @import("tk_geom").Rect;

pub const HISTORY = 4;

pub const Age = struct {
    /// 다음에 그릴 프레임의 번호.
    seq: u64 = 0,
    /// 프레임 `k`의 더티가 `history[k % HISTORY]`에 있다.
    history: [HISTORY]Rect = undefined,

    /// 이번 프레임에 이 버퍼에 다시 그릴 사각형. `drawn`은 이 버퍼에 마지막으로 그린 프레임 번호(새 버퍼면 null), `pending`은 이번
    /// 프레임의 더티, `whole`은 버퍼 전체다. 새 버퍼이거나 그 사이 프레임이 `HISTORY`보다 많으면 통째다.
    pub fn repaint(self: *const Age, drawn: ?u64, pending: Rect, whole: Rect) Rect {
        const d = drawn orelse return whole;
        if (d >= self.seq) return whole; // 있을 수 없는 번호 — 안전하게 통째.
        const between = self.seq - 1 - d; // 이 버퍼가 놓친 프레임 수(d+1 .. seq-1)
        if (between > HISTORY) return whole;
        var r = pending;
        var k = d + 1;
        while (k < self.seq) : (k += 1) r = Rect.cover(r, self.history[@intCast(k % HISTORY)]);
        return Rect.intersect(r, whole) orelse whole;
    }

    /// 이번 프레임을 적는다. 돌려주는 것은 이 프레임의 번호(그린 버퍼가 들 값).
    pub fn record(self: *Age, pending: Rect) u64 {
        const n = self.seq;
        self.history[@intCast(n % HISTORY)] = pending;
        self.seq += 1;
        return n;
    }
};
