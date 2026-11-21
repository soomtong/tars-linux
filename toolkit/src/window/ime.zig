//! text-input-v3 클라이언트의 상태 기계(TK-M4 plan 확정 9 — 순수, 호스트 검사). 창 층이 Wayland 이벤트를 넣고, 돌려받은 요청을 보낸다.
//!
//! - 앱이 켜 달라고 하는 값(`want` — first responder가 텍스트 필드인가)과 서버가 이 창에 들어왔는가(`entered` — text_input `enter`)가 둘 다 참일 때만
//!   켠다. 서버의 상태는 `enter`마다 리셋되므로(WY `wl_logic.TextInput`) `enter`마다 다시 enable한다. `leave` 뒤의 요청은 서버가 무시하므로 안 보낸다.
//! - 요청 하나는 enable(+ content_type normal) 또는 disable과 그 뒤의 `commit`이다. `commit` 수를 센다 — 서버의 `done(serial)`이 그 수다.
//! - `preedit_string` · `commit_string`은 모았다가 `done`에서 한 번에 올린다(xml의 이중 버퍼). serial이 달라도 적용한다(xml: "must proceed with
//!   evaluating and applying the changes as normal"). 맞았는지는 줄의 `match=`로 남긴다.
//! - `set_cursor_rectangle`은 안 보낸다 — 서버가 버린다(WY 결정 38). `delete_surrounding_text`는 서버가 안 보낸다.

const std = @import("std");

pub const MAX = 256;

pub const Done = struct { commit: []const u8, preedit: []const u8, serial: u32, match: bool };

pub const Ime = struct {
    want: bool = false,
    entered: bool = false,
    /// 보낸 `commit` 요청 수.
    commits: u32 = 0,
    commit_buf: [MAX]u8 = undefined,
    commit_len: usize = 0,
    pre_buf: [MAX]u8 = undefined,
    pre_len: usize = 0,

    /// 앱이 바라는 값을 바꾼다. 보낼 것이 있으면 그 값(참 = enable, 거짓 = disable). 보낸 뒤 `sent()`를 부른다.
    pub fn setWant(self: *Ime, on: bool) ?bool {
        if (self.want == on) return null;
        self.want = on;
        if (!self.entered) return null;
        return on;
    }

    /// text_input `enter`. 바라고 있으면 enable을 보낸다(참).
    pub fn enter(self: *Ime) ?bool {
        self.entered = true;
        self.clear();
        return if (self.want) true else null;
    }

    /// text_input `leave`. 모은 것을 버린다(서버는 그 앞에서 확정을 이미 보냈다 — WY 결정 42).
    pub fn leave(self: *Ime) void {
        self.entered = false;
        self.clear();
    }

    /// 요청 하나(enable 또는 disable + commit)를 보냈다.
    pub fn sent(self: *Ime) void {
        self.commits +%= 1;
    }

    pub fn preedit(self: *Ime, text: []const u8) void {
        const n = @min(text.len, MAX);
        @memcpy(self.pre_buf[0..n], text[0..n]);
        self.pre_len = n;
    }

    pub fn commitString(self: *Ime, text: []const u8) void {
        const n = @min(text.len, MAX);
        @memcpy(self.commit_buf[0..n], text[0..n]);
        self.commit_len = n;
    }

    /// `done(serial)`: 모은 것을 하나로 돌려주고 다음을 위해 비운다(조각은 다음 이벤트가 오기 전까지 유효하다).
    pub fn done(self: *Ime, serial: u32) Done {
        const d: Done = .{
            .commit = self.commit_buf[0..self.commit_len],
            .preedit = self.pre_buf[0..self.pre_len],
            .serial = serial,
            .match = serial == self.commits,
        };
        self.commit_len = 0;
        self.pre_len = 0;
        return d;
    }

    fn clear(self: *Ime) void {
        self.commit_len = 0;
        self.pre_len = 0;
    }
};
