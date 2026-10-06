//! TC-M2. `reload`가 무엇을 할지를 정하는 쪽(reload design 결정 8).
//!
//! 시스템 콜이 하나도 없다 — `reload_test.zig`가 호스트에서 전부 본다. 실행하는 것(nft ·
//! argv 포인터 · env 블록 갈아 끼우기 · 서비스의 목표)은 `main.zig`의 `reload`다.
//!
//! PID 1의 코드다. ReleaseSafe에서 범위 밖 인덱스 · 정수 넘침 · `unreachable` · `.?`의 null은
//! 패닉이고, PID 1의 패닉은 커널 패닉이다. 그래서 이 파일은 셋을 지킨다 — 인덱스는 언제나
//! 길이를 먼저 본 뒤에, 글자는 `control.Out`처럼 넘치면 멈추는 버퍼에, `unreachable`과
//! `.?`는 쓰지 않는다(plan 확정 2).
const std = @import("std");
const config = @import("config.zig");
const control = @import("control.zig");

// ── 키 ────────────────────────────────────────────────────────────────

/// 키 하나가 reload에서 가는 갈래(design 결정 2).
pub const Group = enum {
    /// 데몬 · 방화벽 — reload가 지금 바꾼다.
    now,
    /// 콘솔 셸 · ssh 로그인 · 뒤에 뜨는 자식부터. 화면의 패널은 대기다.
    next_spawn,
    /// terminal의 argv. 화면을 다시 띄워야 바뀐다 — 대기다.
    terminal,
};

/// 열두 키의 갈래. `Config`의 필드 이름으로 고른다 — 필드를 더하고 여기를 빠뜨리면
/// `groupOf`가 컴파일 에러를 낸다.
pub fn groupOf(comptime key: []const u8) Group {
    const now = [_][]const u8{ "net", "ntp", "firewall" };
    const next = [_][]const u8{ "shell", "shell_config", "timezone" };
    const term = [_][]const u8{ "keyboard", "hangul_layout", "latin_layout", "hangul_toggle", "esc_latin", "clipboard" };
    inline for (now) |k| if (comptime std.mem.eql(u8, k, key)) return .now;
    inline for (next) |k| if (comptime std.mem.eql(u8, k, key)) return .next_spawn;
    inline for (term) |k| if (comptime std.mem.eql(u8, k, key)) return .terminal;
    @compileError("reload.groupOf does not know the key " ++ key);
}

/// 화면이 쓰는 키 — terminal의 argv에 드는 것. `next_spawn`의 셋도 화면의 패널에는 argv
/// (1 · 2번 셸과 rc 플래그)와 env(`TZ`)로 들어가서 화면에서는 대기다.
pub fn onScreen(comptime key: []const u8) bool {
    return groupOf(key) != .now;
}

/// 두 값이 같은가. 필드 타입마다 비교가 다르다 — enum은 `==`, `Ntp` · `Timezone`은 `eql`,
/// `Toggles`는 칸 다섯.
fn same(comptime T: type, a: T, b: T) bool {
    if (T == config.Toggles) return std.meta.eql(a, b);
    if (T == config.Ntp or T == config.Timezone) return a.eql(b);
    if (@typeInfo(T) == .@"enum") return a == b;
    @compileError("reload.same cannot compare a " ++ @typeName(T));
}

/// 키의 집합. `Config`의 필드 순서대로 한 비트씩.
pub const Keys = struct {
    bits: u16 = 0,

    pub const count = @typeInfo(config.Config).@"struct".fields.len;

    comptime {
        if (count > 16) @compileError("reload.Keys holds 16 keys");
    }

    pub fn has(self: Keys, comptime key: []const u8) bool {
        return self.bits & bit(key) != 0;
    }

    pub fn empty(self: Keys) bool {
        return self.bits == 0;
    }

    fn bit(comptime key: []const u8) u16 {
        inline for (@typeInfo(config.Config).@"struct".fields, 0..) |f, i| {
            if (comptime std.mem.eql(u8, f.name, key)) return @as(u16, 1) << i;
        }
        @compileError("no key " ++ key);
    }
};

/// 바뀐 키.
pub fn changed(old: config.Config, new: config.Config) Keys {
    var k = Keys{};
    inline for (@typeInfo(config.Config).@"struct".fields, 0..) |f, i| {
        if (!same(f.type, @field(old, f.name), @field(new, f.name))) k.bits |= @as(u16, 1) << i;
    }
    return k;
}

/// 화면이 대기 중인 키 — init이 지금 쓰는 값(`live`)과 terminal이 뜰 때 받은 값(`screen`)이
/// 다른 화면 쪽 키.
pub fn pending(live: config.Config, screen: config.Config) Keys {
    var k = Keys{};
    inline for (@typeInfo(config.Config).@"struct".fields, 0..) |f, i| {
        if (comptime onScreen(f.name)) {
            if (!same(f.type, @field(live, f.name), @field(screen, f.name))) k.bits |= @as(u16, 1) << i;
        }
    }
    return k;
}

// ── 값의 글자 ─────────────────────────────────────────────────────────

pub const VALUE_MAX = 64;

comptime {
    if (VALUE_MAX < config.TZ_NAME_MAX or VALUE_MAX < config.TOGGLE_ARG_MAX or VALUE_MAX < config.NTP_ARG_MAX)
        @compileError("reload.VALUE_MAX is smaller than a value config.zig can hold");
}

/// 필드 하나의 글자. `config_edit.fieldText`와 같은 일이다 — init은 `config_edit`을 import하지
/// 않는다(그 파일은 `tars-config`의 것이고 듣기 전역을 든다).
fn text(comptime T: type, v: T, buf: *[VALUE_MAX]u8) []const u8 {
    if (T == config.Toggles) return v.arg(buf);
    if (T == config.Ntp) return v.arg(buf);
    if (T == config.Timezone) {
        const s = v.slice();
        @memcpy(buf[0..s.len], s);
        return buf[0..s.len];
    }
    if (@typeInfo(T) == .@"enum") return @tagName(v);
    @compileError("reload.text cannot print a " ++ @typeName(T));
}

// ── 답 ────────────────────────────────────────────────────────────────

/// 넘치면 멈추는 버퍼 — init.sock의 답과 같은 것을 쓴다. PID 1이 답을 짓다가 죽는 길을 두지
/// 않는다(`control.Out`의 주석).
pub const Out = control.Out;

/// `config` 동사의 답(design 결정 1). 열두 줄 `key=value`(init이 지금 쓰는 값), 그리고 화면이
/// 대기 중이면 `screen key=value …` 한 줄(terminal이 지금 쓰는 값).
pub fn configReply(out: *Out, live: config.Config, screen: config.Config) void {
    inline for (@typeInfo(config.Config).@"struct".fields) |f| {
        var buf: [VALUE_MAX]u8 = undefined;
        out.print("{s}={s}\n", .{ f.name, text(f.type, @field(live, f.name), &buf) });
    }
    const p = pending(live, screen);
    if (p.empty()) return;
    out.print("screen", .{});
    inline for (@typeInfo(config.Config).@"struct".fields, 0..) |f, i| {
        if (p.bits & (@as(u16, 1) << i) != 0) {
            var buf: [VALUE_MAX]u8 = undefined;
            out.print(" {s}={s}", .{ f.name, text(f.type, @field(screen, f.name), &buf) });
        }
    }
    out.print("\n", .{});
}

// ── 데몬 ──────────────────────────────────────────────────────────────

/// 데몬 하나에 할 일(design 결정 3의 2단계).
pub const Step = enum { keep, start, stop, restart };

/// was · now는 "설정이 이 데몬을 원하는가"(부팅의 `wifi.wants` · `net.wantsDhcpcd` ·
/// `clock.prepare`의 답). rewrote는 그 데몬이 읽는 설정 파일을 이번에 다시 썼는가(chronyd의
/// `/run/tars/chrony.conf`) — 켜진 채로 파일이 바뀌면 다시 띄워야 읽는다.
pub fn step(was: bool, now: bool, rewrote: bool) Step {
    if (!was and now) return .start;
    if (was and !now) return .stop;
    if (was and now and rewrote) return .restart;
    return .keep;
}

/// 방화벽에 할 일. 켜기는 조이는 것이라 데몬보다 먼저, 끄기는 푸는 것이라 데몬 뒤에
/// 한다(design 결정 3 — FW 결정 5의 "규칙이 서기 전에 주소가 붙는 틈이 없다").
pub const Fw = enum { keep, up, down };

pub fn firewallStep(old: config.Firewall, new: config.Firewall) Fw {
    if (old == new) return .keep;
    return if (new == .on) .up else .down;
}

// ── 서비스(services.d) ────────────────────────────────────────────────

/// 감독 목록의 서비스 칸 하나를 reload가 보는 모양.
pub const Slot = struct {
    /// 비었으면 한 번도 쓰인 적 없는 칸이다.
    name: []const u8,
    /// 설정(services.d)이 이 칸을 안 원한다 — 멈췄거나 멈추는 중이다.
    off: bool,
    /// 프로세스가 아직 있다(멈추는 중이면 참이다).
    alive: bool,
};

pub const SvcAction = union(enum) {
    /// 칸 i의 서비스가 services.d에서 사라졌다. 멈춘다.
    stop: usize,
    /// 칸 i의 서비스가 다시 나타났다. 되살린다.
    revive: usize,
    /// 새 이름(names의 n번째)을 칸 i에 넣고 띄운다.
    add: struct { slot: usize, name: usize },
    /// 새 이름(names의 n번째)을 넣을 칸이 없다. 다음 부팅을 기다린다.
    no_room: usize,
};

fn indexOf(names: []const []const u8, name: []const u8) ?usize {
    for (names, 0..) |n, i| if (std.mem.eql(u8, n, name)) return i;
    return null;
}

/// services.d를 다시 읽은 이름(정렬 · 여덟까지는 `services.discover`가 했다)과 지금의 칸을
/// 견줘 할 일을 out에 담는다. 담은 수를 돌려준다. 이미 있는 이름의 칸은 안 건드린다.
///
/// 빈 칸은 둘이다 — 한 번도 안 쓴 칸, 그리고 꺼졌고 프로세스가 이미 거둬진 칸(이번 목록에
/// 그 이름이 없을 때). 멈추는 중인 칸(꺼졌지만 아직 살아 있다)은 빈 칸이 아니다 — 거두기
/// 전에 칸을 넘기면 그 pid가 새 서비스의 것이 된다.
pub fn serviceActions(slots: []const Slot, names: []const []const u8, out: []SvcAction) usize {
    var n: usize = 0;
    // 사라진 것과 다시 나타난 것.
    for (slots, 0..) |s, i| {
        if (s.name.len == 0) continue;
        const listed = indexOf(names, s.name) != null;
        if (!s.off and !listed) {
            if (n < out.len) out[n] = .{ .stop = i };
            n += 1;
        } else if (s.off and listed) {
            if (n < out.len) out[n] = .{ .revive = i };
            n += 1;
        }
    }
    // 새 이름. 칸은 앞에서부터 찾고, 한 번 준 칸은 다시 안 준다.
    var taken: [32]bool = @splat(false);
    for (names, 0..) |name, ni| {
        var present = false;
        for (slots) |s| {
            if (s.name.len != 0 and std.mem.eql(u8, s.name, name)) present = true;
        }
        if (present) continue;
        var given: ?usize = null;
        for (slots, 0..) |s, i| {
            if (i >= taken.len or taken[i]) continue;
            const free = s.name.len == 0 or (s.off and !s.alive and indexOf(names, s.name) == null);
            if (!free) continue;
            given = i;
            taken[i] = true;
            break;
        }
        if (n < out.len) out[n] = if (given) |g| .{ .add = .{ .slot = g, .name = ni } } else .{ .no_room = ni };
        n += 1;
    }
    return @min(n, out.len);
}

// ── reload의 답 ───────────────────────────────────────────────────────

/// 키 한 줄의 꼬리. 지금 바뀌는 키는 main.zig가 데몬 · 방화벽의 줄을 따로 찍으므로 여기서는
/// 셋을 가른다.
pub fn note(comptime key: []const u8) []const u8 {
    return switch (comptime groupOf(key)) {
        .now => "now",
        .next_spawn => "the next console shell, ssh login and service; the screen keeps the old value until the next boot",
        .terminal => "the screen keeps the old value until the next boot",
    };
}

/// 바뀐 키마다 `key: old -> new (꼬리)` 한 줄.
pub fn keyLines(out: *Out, old: config.Config, new: config.Config) void {
    const k = changed(old, new);
    inline for (@typeInfo(config.Config).@"struct".fields, 0..) |f, i| {
        if (k.bits & (@as(u16, 1) << i) != 0) {
            var a: [VALUE_MAX]u8 = undefined;
            var b: [VALUE_MAX]u8 = undefined;
            out.print("{s}: {s} -> {s} ({s})\n", .{
                f.name, text(f.type, @field(old, f.name), &a), text(f.type, @field(new, f.name), &b), note(f.name),
            });
        }
    }
}
