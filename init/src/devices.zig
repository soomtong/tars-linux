const std = @import("std");
const linux = std.os.linux;

/// main.zig·config.zig에도 같은 함수가 있다. config.zig가 적어 둔 그대로,
/// 세 줄짜리 헬퍼 하나 때문에 공용 모듈을 만들지 않는다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// 게스트의 진짜 sysfs 뿌리. 검사는 이 자리에 /tmp의 가짜 트리를 넣는다
/// (design 결정 5).
pub const SYS_INPUT: []const u8 = "/sys/class/input";

/// 훑어볼 evdev 번호의 상한. 디렉터리를 열어 순회하는 대신 event0부터
/// 차례로 열어 보는 이유는 init에 libc도 힙도 없기 때문이다 — getdents64를
/// 직접 다루는 것보다 open 서른두 번이 짧고 예측 가능하다. 장치 번호는
/// 0부터 촘촘히 붙으므로 32면 넉넉하다.
const MAX_EVENT: u8 = 32;

/// capabilities 파일 하나의 상한. key 비트맵이 가장 길지만
/// (KEY_MAX가 0x2ff이라 워드 열둘) 공백까지 200바이트를 넘지 않는다.
const MAX_BITMAP = 256;

/// 장치 이름의 상한. 로그에만 쓴다.
const MAX_NAME = 128;

/// 경로 버퍼의 크기. 가장 긴 결과가 "/dev/input/event31"(18자)이다.
pub const MAX_PATH = 64;

/// sysfs 비트맵의 워드 폭. 커널은 unsigned long 단위로 찍는다. 32비트
/// 프로세스가 읽으면 32비트씩 쪼개 주지만(input_bits_to_string의
/// in_compat_syscall 분기), init도 검사도 64비트라 그 경로에 닿지 않는다.
const WORD_BITS: usize = 64;

/// 입력 이벤트 종류. include/uapi/linux/input-event-codes.h와 같아야 한다.
/// **EV_SYN이 0번이라 EV_KEY는 1번이다.** 여기를 0으로 착각하면 EV_SYN만
/// 가진 장치까지 전부 통과한다.
const EV_KEY: u16 = 1;

/// "완전한 키보드"의 판정 범위. KEY_ESC(1)부터 KEY_D(32)까지가 ESC·숫자
/// 열·Q~D를 덮는다. udev의 input_id가 쓰는 것과 같은 기준이고, 키 몇 개만
/// 가진 전원 버튼은 이 범위를 절대 못 채운다.
const KEY_ESC: u16 = 1;
const KEY_D: u16 = 32;

/// 전원 버튼의 키 코드. include/uapi/linux/input-event-codes.h의 KEY_POWER다.
/// 116 = 64 + 52이므로 1번 워드의 52번 비트가 이 키를 나타낸다 — 비트맵을
/// 뒤에서부터 세는 것이 이 파일에서 유일하게 미묘한 부분이라고 bitSet에 적어
/// 둔 그 자리다.
const KEY_POWER: u16 = 116;

/// 열어 둘 전원 버튼의 상한(design 결정 4). ACPI는 FADT의 고정 하드웨어
/// 버튼과 DSDT가 선언한 장치를 각각 등록할 수 있어서, 하나만 골랐다가 틀리면
/// 버튼이 **조용히** 죽는다. HD-M1의 실측으로는 QEMU에 하나뿐이지만, 그
/// 침묵보다는 넉넉한 상한으로 전부 여는 편이 낫다.
pub const MAX_BUTTONS: usize = 4;

/// evdev가 내놓는 이벤트 하나. include/uapi/linux/input.h:28의
/// struct input_event와 같은 모양이어야 한다. 64비트에서는 timeval이
/// 16바이트라 전체가 24바이트다.
///
/// terminal은 같은 구조체를 libc 헤더에서 가져오지만
/// (terminal/src/input.zig:426), init은 libc를 링크하지 않으므로 여기에 손으로
/// 적는다(docs/decisions/project_zig_c_uapi_rule.md). 손으로 적은 레이아웃이
/// 틀리면 조용히 엉뚱한 바이트를 읽게 되므로, devices_test가 @sizeOf를
/// 직접 확인한다.
///
/// 필드 이름 @"type"은 C의 것을 그대로 쓴 것이다. type이 Zig에서 원시 타입의
/// 이름이라 따옴표가 필요하고, terminal 쪽도 같은 모양으로 읽는다.
pub const Event = extern struct {
    sec: i64,
    usec: i64,
    @"type": u16,
    code: u16,
    value: i32,
};

/// 키를 누른 것. 뗌은 0이고 자동 반복은 2다. 누름만 받는 이유는 한 번의
/// 누름이 종료를 한 번만 일으켜야 하기 때문이다 — QEMU의 system_powerdown은
/// 누름과 뗌을 한 쌍으로 보내므로, 안 거르면 한 번이 두 번이 된다.
const VALUE_PRESS: i32 = 1;

/// sysfs 비트맵 문자열에서 code번 비트의 값이 1인지 본다.
///
/// **문자열은 가장 높은 워드가 맨 앞이다.** 커널의 input_print_bitmap이
/// 배열을 거꾸로 훑으면서 찍고, 비어 있는 상위 워드는 아예 건너뛴다. 그래서
/// 워드의 개수가 고정이 아니고, 우리가 원하는 워드는 **뒤에서부터** 세어야
/// 찾을 수 있다. 이 뒤집힘이 이 파일에서 유일하게 미묘한 부분이다.
pub fn bitSet(bitmap: []const u8, code: u16) bool {
    const want_word: usize = code / WORD_BITS;
    const want_bit: u6 = @intCast(code % WORD_BITS);

    var counter = std.mem.tokenizeAny(u8, bitmap, " \t\r\n");
    var count: usize = 0;
    while (counter.next()) |_| count += 1;

    // 상위 워드가 통째로 생략됐다는 뜻이다 = 그 비트의 값은 0이다.
    if (want_word >= count) return false;

    const index_from_front = count - 1 - want_word;
    var it = std.mem.tokenizeAny(u8, bitmap, " \t\r\n");
    var i: usize = 0;
    while (it.next()) |token| : (i += 1) {
        if (i != index_from_front) continue;
        const word = std.fmt.parseInt(u64, token, 16) catch return false;
        return (word >> want_bit) & 1 == 1;
    }
    return false;
}

/// 이 장치가 "완전한 키보드"인가. 이름은 보지 않는다(design 결정 2) —
/// 실제 기계에서 USB 키보드는 제조사마다 다른 이름을 달고 나온다.
pub fn looksLikeKeyboard(ev: []const u8, key: []const u8) bool {
    if (!bitSet(ev, EV_KEY)) return false;

    var code: u16 = KEY_ESC;
    while (code <= KEY_D) : (code += 1) {
        if (!bitSet(key, code)) return false;
    }
    return true;
}

/// 이 장치가 "누르면 기계가 꺼지는 물리 버튼"인가.
///
/// **키보드를 명시적으로 제외하는 것이 이 함수의 핵심이다.** QEMU의 AT
/// 키보드도 KEY_POWER를 갖고 있다 — devices_test가 실측해 둔 비트맵의 1번
/// 워드 0xfeffffdfffefffff에서 52번 비트의 값이 1이고, atkbd가 ACPI 확장 키를
/// 스캔코드 표에 갖고 있기 때문이다. 제외하지 않으면 PID 1이 키보드 fd까지
/// 열어서 글자 하나마다 감독 루프가 깨어나고, 같은 키를 terminal과 PID 1이
/// 서로 다른 뜻으로 읽게 된다.
///
/// 키보드에 달린 전원 키를 무엇으로 옮길지는 Input Policy의 몫이다
/// (docs/decisions/project_input_policy.md). 이 함수는 그 결정을 가져가지
/// 않는다.
pub fn looksLikePowerButton(ev: []const u8, key: []const u8) bool {
    if (!bitSet(ev, EV_KEY)) return false;
    if (!bitSet(key, KEY_POWER)) return false;
    return !looksLikeKeyboard(ev, key);
}

/// 널 종료 경로를 담는 고정 버퍼. init에는 힙이 없으므로 호출자가 이 값을
/// 스택에 두고 포인터만 argv로 넘긴다. main()의 스택은 supervise()가 영영
/// 반환하지 않으므로 프로세스 수명 내내 살아 있다 — 지금 argv에 들어가는
/// 문자열 리터럴과 수명이 같아진다.
pub const Path = struct {
    buf: [MAX_PATH]u8 = [_]u8{0} ** MAX_PATH,
    len: usize = 0,

    /// execve의 argv에 그대로 넣을 수 있는 포인터. 슬라이스에 :0을 붙이면
    /// 널 종료를 컴파일러가 실제로 검사해 준다.
    pub fn cstr(self: *const Path) [*:0]const u8 {
        return self.buf[0..self.len :0].ptr;
    }

    pub fn slice(self: *const Path) []const u8 {
        return self.buf[0..self.len];
    }
};

/// `/dev/input/event{n}`을 out에 적는다.
///
/// MAX_PATH가 64인데 가장 긴 결과가 "/dev/input/event31"(18자)이라 이
/// bufPrint는 실패할 수 없다. 일어날 수 없는 실패를 처리하는 코드는 아무도
/// 실행하지 않으므로 unreachable로 적는다.
fn devicePath(n: u8, out: *Path) void {
    const text = std.fmt.bufPrint(
        out.buf[0 .. out.buf.len - 1],
        "/dev/input/event{d}",
        .{n},
    ) catch unreachable;
    out.buf[text.len] = 0;
    out.len = text.len;
}

/// 파일 하나를 통째로 buf에 읽는다. config.load와 같은 모양이다 —
/// read(2)가 요청한 만큼을 다 준다는 보장이 없으므로 "돌아온 만큼 더한다".
fn readFile(path: [*:0]const u8, buf: []u8) ?[]const u8 {
    const rc = linux.open(path, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |_| return null; // 없는 장치 번호는 ENOENT다. 정상이다.
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return null;
        }
        if (n == 0) break; // EOF
        len += n;
    }
    return buf[0..len];
}

/// `{sys_root}/event{n}/device/{attr}`를 읽는다.
fn readAttr(sys_root: []const u8, n: u8, attr: []const u8, buf: []u8) ?[]const u8 {
    var path: [MAX_PATH * 2]u8 = undefined;
    const text = std.fmt.bufPrint(
        path[0 .. path.len - 1],
        "{s}/event{d}/device/{s}",
        .{ sys_root, n, attr },
    ) catch return null;
    path[text.len] = 0;
    return readFile(path[0..text.len :0].ptr, buf);
}

/// 키보드처럼 생긴 첫 evdev 번호. 없으면 null.
///
/// 번호가 작은 것부터 보므로 여럿이면 첫 번째를 쓴다(design 결정 4). 화면
/// 하나에 셸 하나인 구조라 키보드가 여럿일 이유가 없다.
pub fn findKeyboard(sys_root: []const u8) ?u8 {
    var n: u8 = 0;
    while (n < MAX_EVENT) : (n += 1) {
        var ev_buf: [MAX_BITMAP]u8 = undefined;
        const ev = readAttr(sys_root, n, "capabilities/ev", &ev_buf) orelse continue;

        var key_buf: [MAX_BITMAP]u8 = undefined;
        const key = readAttr(sys_root, n, "capabilities/key", &key_buf) orelse continue;

        if (looksLikeKeyboard(ev, key)) return n;
    }
    return null;
}

/// 전원 버튼처럼 생긴 evdev 번호를 out에 채우고 그 개수를 돌려준다.
///
/// 키보드와 달리 첫 번째 것만 쓰지 않고 **전부** 모은다(design 결정 4).
/// 키보드가 여럿일 이유는 없지만 전원 버튼은 둘일 수 있고, 그중 어느 것이
/// 실제로 우는지는 밖에서 알 수 없기 때문이다.
pub fn findPowerButtons(sys_root: []const u8, out: []u8) usize {
    var found: usize = 0;
    var n: u8 = 0;
    while (n < MAX_EVENT and found < out.len) : (n += 1) {
        var ev_buf: [MAX_BITMAP]u8 = undefined;
        const ev = readAttr(sys_root, n, "capabilities/ev", &ev_buf) orelse continue;

        var key_buf: [MAX_BITMAP]u8 = undefined;
        const key = readAttr(sys_root, n, "capabilities/key", &key_buf) orelse continue;

        if (!looksLikePowerButton(ev, key)) continue;
        out[found] = n;
        found += 1;
    }
    return found;
}

/// 키보드 장치 경로를 정하고 로그로 남긴다. 못 찾아도 **부팅을 막지 않는다**
/// (design 결정 6) — 탐색기의 버그가 기계를 못 켜게 만드는 것이 가장 나쁜
/// 결말이다. 그때는 예전 상수와 같은 event0으로 떨어진다.
pub fn resolveKeyboard(sys_root: []const u8, out: *Path) void {
    const n = findKeyboard(sys_root) orelse blk: {
        std.debug.print("tars-init: no keyboard found under {s}, falling back to event0\n", .{
            sys_root,
        });
        break :blk 0;
    };

    devicePath(n, out);

    // 이름은 판정에 쓰지 않고 로그에만 쓴다. 사람이 로그를 읽을 때 "왜
    // 이것을 골랐나"를 알 수 있어야 하기 때문이다.
    var name_buf: [MAX_NAME]u8 = undefined;
    const raw = readAttr(sys_root, n, "name", &name_buf) orelse "";
    const name = std.mem.trim(u8, raw, " \t\r\n");

    // terminal/check.sh가 이 줄의 앞부분을 grep한다. 고치면 게이트도 함께
    // 고쳐야 한다(HANDOFF의 "로그 문구는 두 곳에 중복된다").
    std.debug.print("tars-init: keyboard device {s} ({s})\n", .{ out.slice(), name });
}

/// 버튼 fd에 쌓인 것을 **전부** 읽어 비우고, 그 안에 전원 버튼 누름이
/// 있었는지 돌려준다. poll이 "읽을 것이 있다"고 알려 준 뒤에만 부른다.
///
/// **다 읽어 비우는 것이 이 함수의 절반이다.** 남겨 두면 다음 poll이 곧바로
/// 다시 깨어나서 PID 1이 CPU를 태우는 바쁜 루프가 된다 —
/// terminal/src/main.zig:216이 PTY master의 POLLHUP에서 똑같은 함정을 적어
/// 두었다.
///
/// fd는 O_NONBLOCK으로 열려 있다. 그래서 마지막 read가 EAGAIN으로 돌아오는
/// 것이 예외가 아니라 이 루프의 정상 종료 경로다.
pub fn drainButton(fd: i32) bool {
    var pressed = false;
    var raw: [@sizeOf(Event) * 16]u8 = undefined;

    while (true) {
        const rc = linux.read(fd, &raw, raw.len);

        // EAGAIN이 이 루프의 정상 종료 경로다 — fd가 O_NONBLOCK이므로 "다
        // 읽었다"가 그 errno로 온다. EINTR도 여기서 끝낸다. 남은 것이
        // 있었다면 다음 poll이 다시 알려 주므로, 시그널 하나 때문에 여기
        // 머물 이유가 없다.
        if (failed(rc)) |_| return pressed;

        if (rc == 0) return pressed; // EOF. 장치가 사라진 경우다.

        var off: usize = 0;
        while (off + @sizeOf(Event) <= rc) : (off += @sizeOf(Event)) {
            const ev: *align(1) const Event = @ptrCast(&raw[off]);
            if (ev.@"type" != EV_KEY) continue;
            if (ev.code != KEY_POWER) continue;
            if (ev.value == VALUE_PRESS) pressed = true;
        }

        // 버퍼를 꽉 채워 왔으면 더 남아 있을 수 있다. 덜 채웠으면 그것이 곧
        // "이번에는 이게 전부"라는 뜻이다.
        if (rc < raw.len) return pressed;
    }
}

/// 전원 버튼 후보를 전부 열고 fd를 out에 채운 뒤 그 개수를 돌려준다.
///
/// **여는 것은 진짜 /dev/input이다.** 탐색(sys_root)만 주입받고 여는 쪽은
/// 고정인 이유는, 이 함수가 하는 일의 절반이 open(2)이라 호스트 검사에서
/// 시험할 대상이 아니기 때문이다. 검사가 보는 것은 findPowerButtons까지다.
///
/// 하나도 못 찾아도 **부팅을 막지 않는다**(design 결정 6). 그때는 0을
/// 돌려주고, 감독 루프의 poll은 fd 0개짜리가 되어 그냥 1초 sleep이 된다 —
/// 폴백이 따로 필요 없는 구조다.
///
/// O_NONBLOCK으로 여는 이유는 drainButton에 적었다. 비었을 때의 read가
/// EAGAIN으로 돌아와야 다 읽었다는 것을 알 수 있다.
pub fn openPowerButtons(sys_root: []const u8, out: []i32) usize {
    var candidates: [MAX_BUTTONS]u8 = undefined;
    const n = findPowerButtons(sys_root, &candidates);
    if (n == 0) {
        // device/check.sh가 이 줄이 **없음**을 요구한다. 탐색기가 조용히
        // 실패하면 버튼은 안 먹는데 부팅은 멀쩡해 보이기 때문이다.
        std.debug.print("tars-init: no power button found under {s}\n", .{sys_root});
        return 0;
    }

    var opened: usize = 0;
    var i: usize = 0;
    while (i < n and opened < out.len) : (i += 1) {
        var path = Path{};
        devicePath(candidates[i], &path);

        const rc = linux.open(path.cstr(), .{ .ACCMODE = .RDONLY, .NONBLOCK = true }, 0);
        if (failed(rc)) |e| {
            std.debug.print("tars-init: could not open {s} (errno {d})\n", .{
                path.slice(), @intFromEnum(e),
            });
            continue;
        }
        out[opened] = @intCast(rc);
        opened += 1;

        // 이름은 판정에 쓰지 않고 로그에만 쓴다. resolveKeyboard와 같은
        // 이유다 — 사람이 로그를 읽을 때 "왜 이것을 열었나"를 알 수 있어야
        // 한다.
        var name_buf: [MAX_NAME]u8 = undefined;
        const raw = readAttr(sys_root, candidates[i], "name", &name_buf) orelse "";
        const name = std.mem.trim(u8, raw, " \t\r\n");

        // device/check.sh가 이 줄의 앞부분을 grep한다. 고치면 게이트도 함께
        // 고쳐야 한다(HANDOFF의 "로그 문구는 두 곳에 중복된다").
        std.debug.print("tars-init: power button {s} ({s})\n", .{ path.slice(), name });
    }

    std.debug.print("tars-init: watching {d} power button(s)\n", .{opened});
    return opened;
}
