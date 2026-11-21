//! 키 반복(TK-M2 plan 확정 2, R-KEY-2). Wayland에서 반복은 클라이언트의 몫이다 — 서버는 `repeat_info(rate, delay)`만 알리고 누름 · 뗌만
//! 보낸다(TARS terminal은 evdev의 자동 반복을 app pane에 보내지 않는다). 창 층의 순수 부분이라 호스트 검사가 지어낸 시각으로 부른다
//! (`age.zig`와 같은 처리). 시계와 타이머(timerfd)는 창 층(`window.zig`)이 든다.
//!
//! 규칙: 반복하는 키를 누르면 `delay` 뒤 첫 반복, 그 뒤 1/`rate` 초마다. 뗌 · 다른 키의 누름 · 키보드 `leave`에 멈춘다. rate 0이면 반복 없음
//! (프로토콜의 뜻). 타이머가 늦게 깨도 밀린 반복을 몰아서 내지 않는다 — 깬 때 한 번 내고 다음은 그때부터 한 간격 뒤다(키가 쌓여 그림이
//! 밀리지 않게).

const std = @import("std");

pub const Repeat = struct {
    /// 초당 반복 수 · 첫 반복까지의 지연(ms). 서버가 알리기 전에는 0 — 반복 없음.
    rate: u32 = 0,
    delay_ms: u32 = 0,
    /// 반복 중인 키(evdev 코드)와 다음 반복 시각(ns).
    code: ?u32 = null,
    next_ns: u64 = 0,

    pub fn setInfo(self: *Repeat, rate: i32, delay_ms: i32) void {
        self.rate = if (rate > 0) @intCast(rate) else 0;
        self.delay_ms = if (delay_ms > 0) @intCast(delay_ms) else 0;
        if (self.rate == 0) self.code = null;
    }

    /// 키 `code`가 눌렸다. `repeats`는 그 키가 반복하는 키인가(`tk_input.repeats`). 다른 키의 누름은 앞 반복을 멈춘다.
    pub fn press(self: *Repeat, code: u32, repeats: bool, now_ns: u64) void {
        if (!repeats or self.rate == 0) {
            self.code = null;
            return;
        }
        self.code = code;
        self.next_ns = now_ns + @as(u64, self.delay_ms) * std.time.ns_per_ms;
    }

    /// 키 `code`가 떼어졌다. 반복 중인 그 키면 멈춘다(다른 키의 뗌은 상관없다 — 수정키를 떼도 이동 키의 반복은 이어진다).
    pub fn release(self: *Repeat, code: u32) void {
        if (self.code == code) self.code = null;
    }

    /// 키보드 포커스를 잃었다.
    pub fn stop(self: *Repeat) void {
        self.code = null;
    }

    /// 다음에 깰 시각(없으면 null — 타이머를 끈다).
    pub fn deadline(self: *const Repeat) ?u64 {
        return if (self.code != null) self.next_ns else null;
    }

    fn interval(self: *const Repeat) u64 {
        return std.time.ns_per_s / @as(u64, self.rate);
    }

    /// 시각 `now_ns`에 낼 반복이 있으면 그 키 코드(하나뿐). 다음 반복은 `now_ns` + 간격 — 늦게 깨어도 몰아서 내지 않는다.
    pub fn fire(self: *Repeat, now_ns: u64) ?u32 {
        const code = self.code orelse return null;
        if (now_ns < self.next_ns) return null;
        self.next_ns = now_ns + self.interval();
        return code;
    }
};
