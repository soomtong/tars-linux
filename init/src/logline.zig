//! 시리얼 로그 한 줄을 write(2) 한 번으로 낸다(AL design 결정 1).
//!
//! init과 terminal은 같은 /dev/console(ttyS0)에 쓴다. 커널의 tty는 write 한 번
//! 동안 잠금(`atomic_write_lock`)을 쥐므로 그 안에는 남의 바이트가 못 끼어들고,
//! write와 write 사이에는 누구나 끼어든다. `std.debug.print`는 부를 때마다 64바이트
//! 버퍼로 잠그고 비우므로 긴 줄 하나가 write 여럿이 되고, 그 사이에 다른 프로세스의
//! 줄이 들어와 게이트가 읽는 줄을 자른다(TC-M3 루트 게이트). 여기서는 한 줄을 버퍼에
//! 다 지은 뒤에 한 번 쓴다.
//!
//! 이 파일은 `init/src/logline.zig`와 `terminal/src/logline.zig`에 바이트까지 같게
//! 둘 있다. 루트 `check.sh`의 진입 검사가 `cmp`로 지킨다 — 한쪽을 고치면 다른 쪽에
//! 그대로 복사한다. 시스템 콜을 `std.os.linux`로 직접 부르는 이유도 그것이다. init은
//! libc가 없고 terminal은 있지만, 둘 다 리눅스라 같은 줄이 두 빌드에 선다.
//!
//! 패닉 자리가 없어야 한다. init(AL-M1)은 ReleaseSafe의 PID 1이라 여기의 패닉이 커널
//! 패닉이다. 에러는 밖으로 안 내보내고, 런타임 값에 `assert` · `unreachable`을 안 쓰고,
//! 슬라이스 경계는 `logline_test.zig`가 경계값으로 덮는다.
const std = @import("std");
const linux = std.os.linux;

/// `print` 한 줄의 상한(바이트). 커널 tty가 긴 write를 끊는 단위와 같다
/// (drivers/tty/tty_io.c `iterate_tty_write`의 chunk = 2048). 그보다 긴 write는
/// 2048씩 끊기고, 끊는 자리에서 처리할 시그널이 걸려 있으면 거기서 돌아간다 —
/// 그러면 나머지를 쓰는 다음 write 앞에 남의 줄이 끼어든다. 2048 이하는 끊을
/// 자리가 없어 시그널과 무관하게 한 덩이다(init은 SIGTERM · SIGINT 처리기를 단다).
///
/// 화면 dump는 이보다 길다. 그 줄은 `Line`에 큰 버퍼를 따로 주고, terminal이 시그널
/// 처리기를 하나도 안 달기 때문에 끊기지 않는다(AL design 결정 2). terminal에
/// 처리기를 다는 날 그 문장이 거짓이 된다.
pub const MAX = 2048;

/// 버퍼를 넘친 줄의 꼬리. 잘린 줄도 늘 줄바꿈으로 끝나야 다음 줄의 머리를 안 먹는다.
pub const CUT = " [cut]\n";

/// 여러 조각으로 짓는 한 줄. 조각마다 `print`하고 끝에 `flush` 한 번이다.
/// `flush`를 안 부르면 아무것도 안 나간다.
pub const Line = struct {
    buf: []u8,
    end: usize = 0,
    cut: bool = false,

    /// `buf`가 `CUT`보다 크지 않으면 처음부터 넘친 줄로 다룬다(아무것도 안 낸다).
    /// 패닉 대신이다.
    pub fn init(buf: []u8) Line {
        return .{ .buf = buf, .cut = buf.len <= CUT.len };
    }

    /// `fmt`를 지금까지의 끝에 붙인다. 넘치면 글자 경계에서 자르고 `CUT`을 붙인 뒤,
    /// 그 뒤의 `print`는 아무것도 안 한다.
    pub fn print(self: *Line, comptime fmt: []const u8, args: anytype) void {
        if (self.cut) return;
        var w: std.Io.Writer = .fixed(self.buf);
        w.end = self.end;
        w.print(fmt, args) catch {
            // `Writer.fixed`는 버퍼를 끝까지 채운 뒤 실패한다. `CUT` 자리를 비우고
            // 그 앞에서 글자가 온전한 데까지만 남긴다.
            const e = whole(self.buf[0 .. self.buf.len - CUT.len]);
            @memcpy(self.buf[e..][0..CUT.len], CUT);
            self.end = e + CUT.len;
            self.cut = true;
            return;
        };
        self.end = w.end;
    }

    pub fn bytes(self: *const Line) []const u8 {
        return self.buf[0..self.end];
    }

    /// 지은 줄을 fd 2에 write 한 번으로 내고 비운다.
    pub fn flush(self: *Line) void {
        writeAll(self.bytes());
        self.end = 0;
        self.cut = self.buf.len <= CUT.len;
    }
};

/// `std.debug.print`와 같은 fmt를 받아 한 줄을 write 한 번으로 낸다. 버퍼는 스택의
/// `MAX`바이트다. 넘는 줄은 `CUT`으로 끝난다.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [MAX]u8 = undefined;
    var line = Line.init(&buf);
    line.print(fmt, args);
    line.flush();
}

/// 덜 쓰이면 나머지를 마저 쓰고, 시그널에 끊기면(EINTR) 다시 쓴다. 다른 에러는
/// 버린다 — 로그를 못 쓴 것 때문에 멈추면 안 된다.
fn writeAll(b: []const u8) void {
    var off: usize = 0;
    while (off < b.len) {
        const rc = linux.write(2, b[off..].ptr, b.len - off);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) return;
                off += rc;
            },
            .INTR => continue,
            else => return,
        }
    }
}

/// `b`에서 글자 가운데를 자르지 않는 가장 긴 앞부분의 길이. 마지막 글자의 머리
/// 바이트를 찾아, 그 글자가 다 들어와 있으면 `b.len`, 모자라면 머리 앞이다.
/// UTF-8이 아닌 바이트는 그대로 둔다.
fn whole(b: []const u8) usize {
    var p = b.len;
    while (p > 0 and b.len - p < 3 and b[p - 1] & 0xC0 == 0x80) p -= 1;
    if (p == 0) return b.len;
    const n = std.unicode.utf8ByteSequenceLength(b[p - 1]) catch return b.len;
    return if (p - 1 + n <= b.len) b.len else p - 1;
}
