//! 화면 밝기의 순수한 층(LP-M2). 설계는 `docs/specs/2026-11-05-tars-laptop-power-design.md`의 결정 5 · 6이다.
//!
//! sysfs 파일의 바이트를 받아 값을 돌려준다. 디렉터리를 훑고 파일을 쓰는 일은 `main.zig`의 밝기 절이 한다 —
//! `battery.zig`와 `main.zig`의 경계와 같은 자리다. 그래서 `backlight_test`가 패널 없이 고르는 순서와 단계를
//! 전부 본다. QEMU에는 백라이트가 없다.
//!
//! 아무것도 안 찍는다(루트 `check.sh`의 `require_no_debug_print`).

const std = @import("std");

/// 단계의 수(결정 5). macOS의 밝기 키와 같다.
pub const STEPS: i32 = 16;

/// `/sys/class/backlight/<이름>/type`의 순위. 작을수록 먼저 고른다(결정 5, systemd-backlight와 같은 순서).
/// `raw`는 GPU 드라이버가 PWM을 직접 쥔 것(`intel_backlight`), `platform`은 기종 드라이버, `firmware`는 ACPI
/// `_BCM`(`acpi_video0`)이다 — 맥에서는 셋째가 흔히 안 듣는다(design 확인 4). 모르는 글자는 고르지 않는다.
pub fn rank(kind: []const u8) ?u8 {
    const text = std.mem.trimEnd(u8, kind, "\n");
    if (std.mem.eql(u8, text, "raw")) return 0;
    if (std.mem.eql(u8, text, "platform")) return 1;
    if (std.mem.eql(u8, text, "firmware")) return 2;
    return null;
}

/// `brightness` · `max_brightness` 파일의 내용 → 정수. 정수가 아니면 null.
pub fn parseLevel(bytes: []const u8) ?u32 {
    const text = std.mem.trim(u8, bytes, " \n");
    return std.fmt.parseInt(u32, text, 10) catch null;
}

/// 단계 k(1~STEPS)의 값. 가장 낮은 단계도 1이다 — 0은 패널을 끄고, 꺼진 화면은 고장으로 읽힌다(결정 5).
fn level(k: i32, max: u32) u32 {
    const wide: u64 = @as(u64, max) * @as(u64, @intCast(k));
    const v: u32 = @intCast((wide + @as(u64, @intCast(STEPS)) / 2) / @as(u64, @intCast(STEPS)));
    return @max(v, 1);
}

/// 지금 값 `cur`에서 `delta` 단계(음수면 어둡게) 움직인 값. 값이 실제로 바뀌는 단계까지 건너뛴다 —
/// `max`가 16보다 작은 패널(예: 7)은 이웃 단계가 같은 값이라, 안 건너뛰면 키를 눌러도 아무 일이 없다.
/// 끝(1 · max)에 닿으면 거기 선다. `max`가 0이면 그대로다.
pub fn step(cur: u32, max: u32, delta: i32) u32 {
    if (max == 0 or delta == 0) return cur;
    const now = @min(cur, max);
    // 지금 값에 가장 가까운 단계에서 출발한다. 펌웨어가 둔 값은 단계 위에 있지 않다. 0(꺼짐)이면 단계 0에서
    // 출발해 첫 누름이 단계 1이 된다.
    var k: i32 = @intCast((@as(u64, now) * @as(u64, @intCast(STEPS)) + max / 2) / max);
    k = std.math.clamp(k, 0, STEPS);
    const dir: i32 = if (delta > 0) 1 else -1;
    var left: i32 = if (delta > 0) delta else -delta;
    var v = now;
    while (left > 0) : (left -= 1) {
        while (true) {
            k += dir;
            if (k < 1 or k > STEPS) return v;
            const lv = level(k, max);
            if ((dir > 0 and lv > v) or (dir < 0 and lv < v)) {
                v = lv;
                break;
            }
        }
    }
    return v;
}

/// 이름과 순위의 쌍에서 하나를 고른다 — 순위가 가장 작은 것, 같으면 이름이 앞인 것(부팅마다 같은 답).
pub fn pick(names: []const []const u8, ranks: []const u8) ?usize {
    var best: ?usize = null;
    for (names, ranks, 0..) |name, r, i| {
        if (best) |b| {
            if (r > ranks[b]) continue;
            if (r == ranks[b] and std.mem.order(u8, name, names[b]) != .lt) continue;
        }
        best = i;
    }
    return best;
}
