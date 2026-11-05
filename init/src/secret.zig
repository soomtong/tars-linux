//! 비밀을 tty에서 읽으며 글자마다 `*`를 찍는다(PW design).
//!
//! `tars-config`(wifi passphrase · ssh 공개 키 · Groq 키 · passwd)와 `tars-install`(계정 비밀번호)이 함께 쓴다.
//! 이 저장소는 세 줄짜리 helper 때문에 공용 모듈을 만들지 않지만(devices.zig의 규칙), termios raw 처리는 세 벌로
//! 복사하기에는 틀리기 쉬워 이 파일이 예외다(PW 결정 1).
//!
//! 둘로 나뉜다. `Editor`는 바이트 하나를 받아 할 일을 돌려주는 순수한 상태 기계라 `secret_test`가 호스트에서 본다.
//! `readMasked`가 termios · read · write를 한다. tty가 아닌 길(파이프)은 여기서 안 맡는다 — 부르는 쪽마다 일부러
//! 다르다(PW 확인 2).
const std = @import("std");
const linux = std.os.linux;

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

fn writeAll(fd: i32, bytes: []const u8) void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = linux.write(fd, bytes[off..].ptr, bytes.len - off);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return;
        }
        off += n;
    }
}

pub const BACKSPACE = 0x7f;
pub const CTRL_H = 0x08;
pub const CTRL_C = 0x03;
pub const CTRL_D = 0x04;
pub const CTRL_U = 0x15;
pub const ESC = 0x1b;

/// `Editor.feed`가 돌려주는 할 일. 화면에 무엇을 쓸지만 말하고, 쓰는 것은 `readMasked`다.
pub const Action = union(enum) {
    none,
    /// `*` 하나.
    star,
    /// `\b \b`를 이만큼 — 찍힌 `*`를 그만큼 지운다.
    erase: usize,
    /// Enter.
    done,
    /// Ctrl+C.
    cancel,
    /// 빈 칸에서 Ctrl+D.
    eof,
};

pub const Editor = struct {
    buf: []u8,
    /// buf에 든 바이트.
    len: usize = 0,
    /// 화면에 찍힌 `*`의 수 — 글자의 수다(UTF-8 이어지는 바이트에는 안 찍는다).
    stars: usize = 0,
    /// buf보다 길게 쳤다. 그 뒤로는 담지 않고 `*`만 찍으며, Enter에서 넘침으로 끝난다(PW 결정 6).
    overflow: bool = false,
    esc: enum { none, esc, seq } = .none,

    fn isContinuation(b: u8) bool {
        return b & 0xC0 == 0x80;
    }

    pub fn feed(self: *Editor, b: u8) Action {
        // ESC 시퀀스(화살표 등)를 끝 바이트까지 삼킨다. 안 삼키면 `ESC [ D`의 `[` · `D`가 비밀번호에 들어간다.
        switch (self.esc) {
            .none => {},
            .esc => {
                self.esc = if (b == '[' or b == 'O') .seq else .none;
                return .none;
            },
            .seq => {
                if (b >= 0x40 and b <= 0x7e) self.esc = .none;
                return .none;
            },
        }
        switch (b) {
            '\n', '\r' => return .done,
            CTRL_C => return .cancel,
            CTRL_D => return if (self.len == 0 and self.stars == 0 and !self.overflow) .eof else .none,
            ESC => {
                self.esc = .esc;
                return .none;
            },
            BACKSPACE, CTRL_H => {
                if (!self.overflow) {
                    while (self.len > 0 and isContinuation(self.buf[self.len - 1])) self.len -= 1;
                    if (self.len > 0) self.len -= 1;
                }
                if (self.stars == 0) return .none;
                self.stars -= 1;
                return .{ .erase = 1 };
            },
            CTRL_U => {
                const n = self.stars;
                self.len = 0;
                self.stars = 0;
                self.overflow = false;
                return if (n == 0) .none else .{ .erase = n };
            },
            else => {
                if (b < 0x20) return .none;
                if (self.len < self.buf.len and !self.overflow) {
                    self.buf[self.len] = b;
                    self.len += 1;
                } else {
                    self.overflow = true;
                }
                if (isContinuation(b)) return .none;
                self.stars += 1;
                return .star;
            },
        }
    }

    pub fn line(self: *const Editor) []const u8 {
        return self.buf[0..self.len];
    }
};

pub const Result = union(enum) { line: []const u8, eof, cancel, too_long };

/// 표준 입력이 tty면 prompt를 `out`에 찍고 한 줄을 읽으며 글자마다 `*`를 `out`에 찍는다. tty가 아니면 null —
/// 부르는 쪽이 자기 길로 읽는다.
///
/// `ECHO` · `ICANON` · `ISIG`를 끈다(PW 결정 3 · 4). `ISIG`를 끄는 까닭은 Ctrl+C를 시그널이 아니라 바이트로
/// 받아 아래의 복원 자리를 지나게 하려는 것이다 — 시그널로 죽으면 echo가 꺼진 채 남는다.
///
/// 순서가 뜻이다. 먼저 끄고 prompt를 찍는다 — 거꾸로면 prompt를 보고 곧바로 친 글자가 끄기 전에 도착해 화면에
/// 찍힌다(HP-M1). 끌 때는 `.FLUSH`(prompt 전에 미리 친 것은 버린다), 되돌릴 때는 `.NOW`(다음 답 — YES, passwd의
/// 둘째 줄 — 을 버리지 않는다). 한 바이트씩 읽으므로 Enter 뒤의 글자를 삼키지 않는다.
pub fn readMasked(out: i32, prompt: []const u8, buf: []u8) ?Result {
    var old: linux.termios = undefined;
    if (failed(linux.tcgetattr(0, &old)) != null) return null;
    var raw = old;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.cc[@backingInt(linux.V.MIN)] = 1;
    raw.cc[@backingInt(linux.V.TIME)] = 0;
    _ = linux.tcsetattr(0, .FLUSH, &raw);
    defer {
        _ = linux.tcsetattr(0, .NOW, &old);
        // echo가 꺼져 있어 사람이 친 Enter가 화면에 안 나왔다. 다음 줄을 위해 대신 넘긴다.
        writeAll(out, "\n");
    }
    writeAll(out, prompt);

    var ed: Editor = .{ .buf = buf };
    while (true) {
        var b: [1]u8 = undefined;
        const n = linux.read(0, &b, 1);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return .eof;
        }
        if (n == 0) return .eof;
        switch (ed.feed(b[0])) {
            .none => {},
            .star => writeAll(out, "*"),
            .erase => |k| for (0..k) |_| writeAll(out, "\x08 \x08"),
            .done => return if (ed.overflow) .too_long else .{ .line = ed.line() },
            .cancel => return .cancel,
            .eof => return .eof,
        }
    }
}
