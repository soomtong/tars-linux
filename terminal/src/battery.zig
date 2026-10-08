//! 배터리 칸의 순수한 층(BS-M0). 설계는 `docs/specs/2026-10-08-tars-battery-status-design.md`의
//! 결정 1 · 3 · 4 · 5 · 7 · 8이다.
//!
//! sysfs 파일의 바이트를 받아 값을 돌려준다. 파일을 열고 디렉터리를 훑고 시계를 읽는 일은
//! BS-M1이 `main.zig`의 배터리 절에 둔다 — `pointer.zig` · `dictation.zig`와 `main.zig`의
//! 경계와 같은 자리다. 그래서 `battery_test`가 부팅 없이 경계값을 전부 본다. 60초 주기는
//! 게이트가 못 밟는 길이라(design 결정 11) `pollTimeout`의 검사가 그 길을 보는 유일한
//! 자리다.
//!
//! 게스트에서 도는 파일이지만 아무것도 안 찍는다. 로그 줄은 `main.zig`가 `logline.print`로
//! 찍는다(루트 `check.sh`의 `require_no_debug_print`).

const std = @import("std");

/// `status` 파일의 다섯 값. 글자는 커널 `power_supply_sysfs.c`의 표에서 왔다(`statusName`).
pub const Status = enum {
    unknown,
    charging,
    discharging,
    not_charging,
    full,
};

/// `parseStatus`가 훑는 순서. `statusName`의 `switch`는 빠진 갈래를 컴파일러가 잡지만 이
/// 목록은 못 잡는다 — 그 자리는 `battery_test` 검사 3의 왕복이 본다.
const ALL_STATUS = [_]Status{ .unknown, .charging, .discharging, .not_charging, .full };

/// 커널이 `status` 파일에 쓰는 글자. BS-M1의 `battery> read` 줄이 이 글자를 그대로 찍는다
/// (design 결정 10). `@tagName`은 소문자라 그 줄에 못 쓴다.
pub fn statusName(s: Status) []const u8 {
    return switch (s) {
        .unknown => "Unknown",
        .charging => "Charging",
        .discharging => "Discharging",
        .not_charging => "Not charging",
        .full => "Full",
    };
}

/// sysfs의 `show`가 값 뒤에 붙이는 줄바꿈을 뗀다.
fn chomp(bytes: []const u8) []const u8 {
    return std.mem.trimEnd(u8, bytes, "\n");
}

/// `status` 파일의 내용 → enum(design 결정 3). 모르는 글자와 빈 값(읽기 실패)은 `unknown`이다.
///
/// 대소문자를 구분한다. test_power의 파라미터는 소문자(`charging`)를 받지만 sysfs 파일은
/// 언제나 `statusName`의 글자로 낸다 — 소문자가 왔다면 그것은 이 파일의 내용이 아니다.
pub fn parseStatus(bytes: []const u8) Status {
    const text = chomp(bytes);
    for (ALL_STATUS) |s| {
        if (std.mem.eql(u8, text, statusName(s))) return s;
    }
    return .unknown;
}

/// `capacity` 파일의 내용 → 0~100(design 결정 3). 범위 밖은 가까운 끝으로 자르고, 정수가
/// 아니면 null이다. null이면 칸은 `  ?%`다(`cellText`).
///
/// `i32`로 읽는다. 커널의 `intval`이 `int`라 그보다 큰 글자는 이 파일에서 안 오고, 오면
/// 정수가 아닌 것과 같이 null이다.
pub fn parseCapacity(bytes: []const u8) ?u8 {
    const v = std.fmt.parseInt(i32, chomp(bytes), 10) catch return null;
    if (v < 0) return 0;
    if (v > 100) return 100;
    return @intCast(v);
}

/// 장치 하나가 칸에 들어갈 배터리인가(design 결정 1의 세 조건). 인자는 그 장치 디렉터리의
/// `type` · `present` · `scope` 파일 내용이고, 파일이 없으면 null을 넘긴다. 첫 인자의 이름이
/// `kind`인 것은 `type`이 Zig의 예약어이기 때문이다.
///
/// `present`가 없으면 있는 것으로, `scope`가 없으면 통과로 본다. test_power의 `test_battery`에는
/// `scope` 파일이 아예 없다(BS-M0 plan 확정 2).
pub fn counts(kind: []const u8, present: ?[]const u8, scope: ?[]const u8) bool {
    if (!std.mem.eql(u8, chomp(kind), "Battery")) return false;
    if (present) |p| {
        if (std.mem.eql(u8, chomp(p), "0")) return false;
    }
    if (scope) |s| {
        if (std.mem.eql(u8, chomp(s), "Device")) return false;
    }
    return true;
}

/// `counts`를 통과한 이름 중 바이트 순서로 첫째(design 결정 2). 없으면 null이다.
///
/// 순서는 `init/src/services.zig`가 `services.d`를 정렬하는 것과 같은 바이트 비교다.
/// `BAT10`이 `BAT2`보다 앞이 되지만, 배터리가 열 개인 기계는 없다.
pub fn pick(names: []const []const u8) ?[]const u8 {
    var best: ?[]const u8 = null;
    for (names) |name| {
        if (best == null or std.mem.order(u8, name, best.?) == .lt) best = name;
    }
    return best;
}

/// 칸의 색 셋(design 결정 5). 색 상수는 BS-M1이 `main.zig`에 둔다.
pub const Class = enum {
    /// 배터리로 돈다. 잔량을 모를 때도 이것이다.
    normal,
    /// 어댑터가 꽂혀 있다 — `Charging` · `Full` · `Not charging`.
    plugged,
    /// 꽂혀 있지 않고 잔량이 `LOW_MAX` 이하다.
    low,
};

/// 이 값 이하가 `low`다. 15는 `low`, 16은 `normal`이다(`battery_test` 검사 10).
pub const LOW_MAX: u8 = 15;

/// 상태와 잔량 → 갈래. 꽂혀 있으면 잔량과 무관하게 `plugged`다. `Unknown`은 꽂혀 있다는
/// 뜻이 아니므로 잔량이 낮으면 `low`다(BS-M0 plan 확정 10).
pub fn class(status: Status, capacity: ?u8) Class {
    switch (status) {
        .charging, .full, .not_charging => return .plugged,
        .unknown, .discharging => {},
    }
    const c = capacity orelse return .normal;
    return if (c <= LOW_MAX) .low else .normal;
}

/// 칸의 폭(design 결정 4). `100%`가 가장 긴 값이다.
pub const CELL_LEN = 4;

/// 잔량 → 넉 자. 숫자를 오른쪽에 붙이고 앞을 공백으로 채운다 — `100%` · ` 85%` · `  5%`,
/// 모르면 `  ?%`. 돌려주는 조각은 `buf` 전체다.
///
/// `u8` 전체를 받는다. `parseCapacity`가 100으로 자르므로 셋째 자리까지만 쓰이지만,
/// 255가 와도 넉 자를 넘지 않는다.
pub fn cellText(capacity: ?u8, buf: *[CELL_LEN]u8) []const u8 {
    buf.* = .{ ' ', ' ', ' ', '%' };
    var v = capacity orelse {
        buf[CELL_LEN - 2] = '?';
        return buf;
    };
    var i: usize = CELL_LEN - 2;
    while (true) {
        buf[i] = '0' + v % 10;
        v /= 10;
        if (v == 0 or i == 0) break;
        i -= 1;
    }
    return buf;
}

/// uevent datagram 하나가 power_supply의 것인가(design 결정 7 · 8). `ACTION`도 장치 이름도
/// 안 본다 — 그 이유는 design "착수 전에 확인한 것" 4 · 6이다.
///
/// 필드를 NUL로 나눠 `SUBSYSTEM=power_supply`와 글자 그대로 같은 필드를 찾는다
/// (`pointer.ueventAddedNode`와 같은 읽기). 머리(`change@/devices/…/power_supply/test_ac`)는
/// 경로에 그 낱말이 있어도 같은 필드가 아니라 안 걸린다.
pub fn ueventIsPowerSupply(msg: []const u8) bool {
    var it = std.mem.splitScalar(u8, msg, 0);
    while (it.next()) |field| {
        if (std.mem.eql(u8, field, "SUBSYSTEM=power_supply")) return true;
    }
    return false;
}

/// 주기(design 결정 8). 고른 배터리가 있으면 마지막으로 읽은 뒤 이만큼 지나 다시 읽는다.
pub const PERIOD_MS: i64 = 60_000;

/// `poll`의 timeout(밀리초). `due_ms`는 다음에 읽을 시각이고, 고른 배터리가 없으면 null이다 —
/// 그러면 -1(무한 대기)이라 배터리가 없는 기계의 terminal은 BS 전과 똑같이 이벤트가 없으면
/// 안 깬다.
///
/// 기한이 지났으면 0이고, `c_int`를 넘으면 그 최댓값으로 자른다. 뺄셈은 `i128`에서 한다 —
/// `i64`의 양 끝값끼리 빼도 넘치지 않는다.
pub fn pollTimeout(now_ms: i64, due_ms: ?i64) c_int {
    const due = due_ms orelse return -1;
    const left = @as(i128, due) - now_ms;
    if (left <= 0) return 0;
    if (left > std.math.maxInt(c_int)) return std.math.maxInt(c_int);
    return @intCast(left);
}
