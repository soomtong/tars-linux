const std = @import("std");
const linux = std.os.linux;
const power = @import("power.zig");

// 부팅이 믹서를 켜고, 끌 때 기억한다(AU design 결정 4). 믹서를 실제로 만지는 것은
// alsa-utils의 alsactl이다 — 이 파일은 그것을 언제 · 어떤 인자로 부르고 그 끝을
// 어떻게 읽는지만 정한다(project_write_or_reuse).
//
// 켜는 쪽은 기다리지 않는다. `start`가 일꾼 하나를 fork하고 곧장 돌아오며, 일꾼이
// 카드를 기다렸다가 alsactl이 된다. 일꾼의 끝은 감독 루프가 거둘 때 `reaped`가
// 읽는다. 끄는 쪽(`store`)은 기다린다 — 종료 경로는 이 뒤에 sync와 전원 끄기뿐이라
// 기다리지 않으면 파일이 반쯤 쓰인 채 전원이 나간다. 그 기다림에 상한이 있다.

/// 같은 세 줄짜리 헬퍼다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// guest_tools.sh 층 14가 usr/sbin/alsactl을 여기로 넣는다. dhcpcd · chronyd와
/// 같은 이유(PATH가 /usr/bin:/bin)로 /usr/sbin을 안 쓴다.
pub const ALSACTL_PATH: [:0]const u8 = "/usr/bin/alsactl";

/// 사람이 바꾼 믹서가 부팅을 넘는 자리. `/config`가 붙은 부팅에서만 읽고 쓴다.
/// chrony.drift와 같은 자리의 같은 성질이다 — 기계가 배운 것이고 사람이 손으로
/// 고칠 일이 없다.
pub const STATE_PATH: [:0]const u8 = "/config/asound.state";

/// 카드 0의 제어 노드. 이것이 서면 alsactl이 그 카드를 연다.
const CARD_PATH: [:0]const u8 = "/dev/snd/controlC0";

/// 일꾼이 카드를 기다리는 상한. HDA는 코덱 탐색을 커널의 일 큐에서 하므로 카드가
/// PID 1보다 늦게 설 수 있다. 소리 장치가 없는 기계(게이트의 체인 대부분)에서는
/// 일꾼이 이만큼 살다가 끝난다 — 부팅은 안 기다린다.
pub const CARD_WAIT_MS: u32 = 5000;
const CARD_POLL_MS: u32 = 100;

/// 끌 때 alsactl store를 기다리는 상한. 넘기면 SIGKILL이고 전원은 그대로 꺼진다.
pub const STORE_WAIT_MS: u32 = 2000;
const STORE_POLL_MS: u32 = 50;

/// 일꾼이 카드를 못 보고 끝날 때의 종료 코드. alsactl은 음수 errno를 뒤집어
/// 돌려주므로(1~133) 거기 안 겹치는 값이다. 127은 execve 실패로 이미 쓴다.
pub const NO_CARD_EXIT: u8 = 254;

/// alsactl이 카드를 자기 규칙 표(/usr/share/alsa/init)에서 못 찾아 범용 규칙으로
/// 켰을 때의 종료 코드다(alsactl.1의 init 절 — "If device is not known, error code 99
/// is returned"). 믹서는 선 것이다. QEMU의 코덱이 이 길이고(AU-M1 실측), 표에 없는
/// 노트북의 코덱도 그럴 것이다. restore도 파일과 카드의 컨트롤이 어긋나면 init을
/// 거치므로 같은 99가 나올 수 있다(state.c의 load_state).
pub const GENERIC_EXIT: u8 = 99;

pub const Verb = enum {
    /// `/config/asound.state`를 되살린다. 파일에 없는 카드는 alsactl이 init한다.
    restore,
    /// 커널의 기본값(꺼짐)을 alsactl의 기본값(Master -20dB · Capture 0dB, 켜짐)으로.
    init,
};

/// 어느 동사로 켤지. 시스템 콜이 없는 순수 함수다(audio_test가 본다).
///
/// 파일이 없으면 restore가 아니라 init을 부른다. restore도 파일이 없으면 카드를
/// init해 주지만 그러고도 exit 2(ENOENT)를 돌려준다(alsactl의 state.c
/// `load_state`) — 그러면 "켰다"와 "실패했다"가 종료 코드로 안 갈린다.
pub fn verbFor(storage_mounted: bool, state_exists: bool) Verb {
    return if (storage_mounted and state_exists) .restore else .init;
}

/// alsactl의 argv. 셋 다 같은 모양이고 순수하다.
///
///   -U   UCM을 안 쓴다. 쓰면 alsa-ucm-conf가 없는 initrd에서 `Unable to find the
///        top-level configuration file '/usr/share/alsa/ucm2/ucm.conf'`와 `failed to
///        import hw:0 use case configuration -2` 두 줄을 부팅마다 찍고 범용 방법으로
///        내려온다(design 실측 10). UCM이 필요한 기계(DSP 뒤의 마이크)는 AU-M3이고,
///        그때 alsa-ucm-conf와 함께 이 플래그를 다시 본다
///   -f   기본 경로(/var/lib/alsa/asound.state)가 아닌 파일을 주면 alsactl이 잠금
///        파일을 안 만든다(lock.c). 게스트에 /var/lock이 없어도 된다
///
/// init은 파일을 안 읽으므로 -f가 없다.
pub const RESTORE_ARGV = [_:null]?[*:0]const u8{ ALSACTL_PATH.ptr, "-U", "-f", STATE_PATH.ptr, "restore" };
pub const INIT_ARGV = [_:null]?[*:0]const u8{ ALSACTL_PATH.ptr, "-U", "init" };
pub const STORE_ARGV = [_:null]?[*:0]const u8{ ALSACTL_PATH.ptr, "-f", STATE_PATH.ptr, "store" };

pub fn argvFor(verb: Verb) [*:null]const ?[*:0]const u8 {
    return switch (verb) {
        .restore => &RESTORE_ARGV,
        .init => &INIT_ARGV,
    };
}

pub const Outcome = union(enum) {
    /// alsactl이 0으로 끝났다. 믹서가 섰다
    done,
    /// alsactl이 99로 끝났다. 범용 규칙으로 믹서가 섰다
    generic,
    /// 일꾼이 CARD_WAIT_MS 안에 카드를 못 봤다
    no_card,
    /// alsactl이 0이 아닌 코드로 끝났다. 127이면 execve가 실패한 것이다
    exited: u8,
    /// 시그널에 죽었다
    killed: u32,
};

/// wait의 status를 읽는다. 순수 함수다.
pub fn outcome(status: u32) Outcome {
    if (linux.W.IFEXITED(status)) {
        const code = linux.W.EXITSTATUS(status);
        if (code == 0) return .done;
        if (code == GENERIC_EXIT) return .generic;
        if (code == NO_CARD_EXIT) return .no_card;
        return .{ .exited = code };
    }
    return .{ .killed = @intCast(@intFromEnum(linux.W.TERMSIG(status))) };
}

pub const StoreDecision = enum {
    /// 적는다
    store,
    /// 이 부팅에 믹서를 세우지 못했다. 적으면 커널의 꺼진 기본값이 사람이 남긴
    /// 상태를 덮는다 — 카드가 없었거나, alsactl이 실패했거나, 일꾼이 끝나기 전에
    /// 전원이 눌렸다
    not_set,
    /// `/config`가 없다. tmpfs에 적으면 재부팅에 사라지는 가짜 기억이다
    no_config,
};

/// 끌 때 적을지. 순수 함수다.
pub fn storeDecision(set_this_boot: bool, storage_mounted: bool) StoreDecision {
    if (!set_this_boot) return .not_set;
    if (!storage_mounted) return .no_config;
    return .store;
}

// ── 여기서부터는 시스템 콜을 한다. 위의 넷만 audio_test가 본다 ─────────

/// PID 1의 기억. PID 1은 스레드가 없고 시그널 핸들러는 이 셋을 안 만지므로
/// 그냥 전역이다.
var worker_pid: linux.pid_t = -1;
var worker_verb: Verb = .init;
var storage: bool = false;
/// 일꾼의 alsactl이 0으로 끝났다. `store`가 이것만 본다.
var mixer_set: bool = false;
/// `start`가 받은 env 블록. 끌 때 alsactl store에 같은 것을 준다. 블록은 `main()`의
/// 스택에 살고 `supervise()`가 영영 반환하지 않으므로 종료 경로에서도 유효하다.
const NO_ENV = [_:null]?[*:0]const u8{};
var env: [*:null]const ?[*:0]const u8 = &NO_ENV;

fn sleepMillis(ms: u32) void {
    const req = linux.timespec{
        .sec = @intCast(ms / 1000),
        .nsec = @intCast(@as(u64, ms % 1000) * 1_000_000),
    };
    _ = linux.nanosleep(&req, null);
}

fn exists(path: [:0]const u8) bool {
    return failed(linux.access(path.ptr, linux.F_OK)) == null;
}

/// 카드 노드를 기다린다. 기다린 밀리초를 돌려주고, 상한까지 없으면 null이다.
fn waitForCard() ?u32 {
    var waited: u32 = 0;
    while (true) {
        if (exists(CARD_PATH)) return waited;
        if (waited >= CARD_WAIT_MS) return null;
        sleepMillis(CARD_POLL_MS);
        waited += CARD_POLL_MS;
    }
}

/// 부팅에 한 번 부른다. 일꾼을 fork하고 곧장 돌아온다(feedback_boot_never_blocks).
///
/// 일꾼은 execve 전에 우리 코드로 최대 5초를 머무므로 시그널 정책을 기본값으로
/// 되돌린다(power.resetToDefault의 주석) — 안 그러면 그 사이에 눌린 전원 버튼의
/// SIGTERM에 안 죽고 종료가 유예 3초를 다 쓴다.
pub fn start(storage_mounted: bool, envp: [*:null]const ?[*:0]const u8) void {
    storage = storage_mounted;
    env = envp;
    worker_verb = verbFor(storage_mounted, storage_mounted and exists(STATE_PATH));

    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: audio: cannot fork (errno {d}), the mixer is left as the kernel set it\n", .{@intFromEnum(e)});
        return;
    }
    if (pid == 0) {
        power.resetToDefault();
        const waited = waitForCard() orelse linux.exit(NO_CARD_EXIT);
        // 기다린 적이 있을 때만 찍는다(mountConfig와 같은 규칙).
        if (waited > 0) std.debug.print("tars-init: audio: sound card appeared after {d}ms\n", .{waited});
        _ = linux.execve(ALSACTL_PATH.ptr, argvFor(worker_verb), envp);
        std.debug.print("tars-init: cannot exec {s}\n", .{ALSACTL_PATH});
        linux.exit(127);
    }
    worker_pid = @intCast(pid);
    std.debug.print("tars-init: audio: alsactl {s} once a sound card shows up (pid {d})\n", .{ @tagName(worker_verb), pid });
}

/// 감독 루프가 감독 목록에 없는 pid를 거둘 때 먼저 묻는다. 일꾼이면 그 끝을 로그
/// 한 줄로 남기고 true다. 아니면 false이고 감독 루프가 고아로 센다.
///
/// 따로 묻는 이유는 terminal 체인이 `reaped orphan pid`를 "재부모화된 셸을
/// 거뒀다"의 증거로 보기 때문이다. 일꾼을 고아로 찍으면 그 검사가 우리 일꾼
/// 덕에 초록이 될 수 있다.
pub fn reaped(pid: linux.pid_t, status: u32) bool {
    if (worker_pid < 0 or pid != worker_pid) return false;
    worker_pid = -1;
    const verb = @tagName(worker_verb);
    const got = outcome(status);
    switch (got) {
        .done, .generic => {
            mixer_set = true;
            // 99는 끝에 덧붙인다. 앞머리가 같아야 게이트가 한 글자로 둘을 다 받는다.
            const tail: []const u8 = if (got == .generic) " (generic rules, exit 99)" else "";
            switch (worker_verb) {
                .restore => std.debug.print("tars-init: audio: alsactl restore set the mixer from {s}{s}\n", .{ STATE_PATH, tail }),
                .init => std.debug.print("tars-init: audio: alsactl init turned the mixer on{s}\n", .{tail}),
            }
        },
        .no_card => std.debug.print("tars-init: audio: no sound card within {d}ms, the mixer is left alone\n", .{CARD_WAIT_MS}),
        .exited => |code| std.debug.print("tars-init: audio: alsactl {s} exited {d}, the mixer is left as the kernel set it\n", .{ verb, code }),
        .killed => |sig| std.debug.print("tars-init: audio: alsactl {s} was killed (signal {d})\n", .{ verb, sig }),
    }
    return true;
}

/// 종료 경로에서 한 번 부른다(power.shutdown). 모든 프로세스가 거둬진 뒤이고 sync
/// 앞이다. 기다리되 STORE_WAIT_MS가 상한이다.
///
/// 자식은 곧바로 execve하므로 시그널 정책을 되돌릴 일이 없다. 그리고 이 자식은
/// `kill(-1, …)` 뒤에 태어나므로 그 시그널을 안 받는다.
pub fn store() void {
    switch (storeDecision(mixer_set, storage)) {
        .store => {},
        .not_set => {
            std.debug.print("tars-init: audio: mixer not stored, it was not set this boot\n", .{});
            return;
        },
        .no_config => {
            std.debug.print("tars-init: audio: mixer not stored, no /config\n", .{});
            return;
        },
    }

    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: audio: cannot fork for alsactl store (errno {d})\n", .{@intFromEnum(e)});
        return;
    }
    if (pid == 0) {
        _ = linux.execve(ALSACTL_PATH.ptr, &STORE_ARGV, env);
        std.debug.print("tars-init: cannot exec {s}\n", .{ALSACTL_PATH});
        linux.exit(127);
    }

    var waited: u32 = 0;
    var status: u32 = 0;
    while (true) {
        const rc = linux.wait4(@intCast(pid), &status, linux.W.NOHANG, null);
        if (failed(rc)) |e| {
            if (e == .INTR) continue;
            std.debug.print("tars-init: audio: waiting for alsactl store failed (errno {d})\n", .{@intFromEnum(e)});
            return;
        }
        if (rc != 0) break;
        if (waited >= STORE_WAIT_MS) {
            _ = linux.kill(@intCast(pid), .KILL);
            _ = linux.wait4(@intCast(pid), &status, 0, null);
            std.debug.print("tars-init: audio: alsactl store did not finish in {d}ms, killed it\n", .{STORE_WAIT_MS});
            return;
        }
        sleepMillis(STORE_POLL_MS);
        waited += STORE_POLL_MS;
    }
    switch (outcome(status)) {
        .done => std.debug.print("tars-init: audio: stored the mixer in {s}\n", .{STATE_PATH}),
        .generic => std.debug.print("tars-init: audio: alsactl store exited {d}\n", .{GENERIC_EXIT}),
        .no_card => std.debug.print("tars-init: audio: alsactl store exited {d}\n", .{NO_CARD_EXIT}),
        .exited => |code| std.debug.print("tars-init: audio: alsactl store exited {d}\n", .{code}),
        .killed => |sig| std.debug.print("tars-init: audio: alsactl store was killed (signal {d})\n", .{sig}),
    }
}

// ── AU-M2. 기본 카드 ─────────────────────────────────────────────────────
//
// libasound의 `default`는 카드 0이다. 내장 HDA가 부팅 때 0번을 잡고 USB 헤드셋은 그
// 뒤 번호로 오므로, 아무것도 안 하면 사람이 치는 `aplay x.wav`가 헤드셋이 아니라
// 내장 스피커로 간다. 그래서 PID 1이 /dev/snd의 이름을 보고 /etc/asound.conf를
// 쓴다 — 재생과 녹음 각각, 장치 0을 가진 카드 중 번호가 가장 큰 것이 기본이다.
//
// 둘을 따로 고르는 이유. 마이크 없는 USB 스피커 · DAC가 꽂혀도 녹음은 내장 마이크에
// 남아야 한다. 한 번호로 묶으면 그 카드에 녹음 장치가 없어 `arecord`가 죽는다.
// 장치 0만 보는 이유. HDMI 코덱만 가진 카드(AMD 노트북의 GPU 쪽 HDA)는 범용 파서가
// 장치 1(디지털)로만 내놓는다 — 소리가 안 나는 그 카드가 기본이 되지 않는다.
//
// 듣지 않고 본다. 감독 루프는 이미 1초마다 깨므로, 깰 때마다 이름을 읽고 지난번과
// 다를 때만 파일을 쓴다. uevent 소켓도 일꾼도 없다(AU-M2 plan 확정 4).

pub const ASOUND_CONF_PATH: [:0]const u8 = "/etc/asound.conf";
/// 다 쓴 뒤 rename한다. 반쯤 쓴 파일을 aplay가 읽지 않게.
const ASOUND_CONF_TMP: [:0]const u8 = "/etc/asound.conf.tars";
const SND_DIR: [:0]const u8 = "/dev/snd";

/// 카드 번호의 상한. 커널의 SNDRV_CARDS(`CONFIG_SND_MAX_CARDS`의 기본 32)와 같다.
pub const MAX_CARDS = 32;

/// 장치 0에 재생 · 녹음이 있는 카드의 집합. 비트 하나가 카드 하나다.
pub const Cards = struct {
    playback: u32 = 0,
    capture: u32 = 0,
};

/// /dev/snd의 이름 하나를 `cards`에 더한다. `pcmC<카드>D0p` · `pcmC<카드>D0c`만
/// 세고 나머지(control · timer · 장치 1 이상)는 버린다. 순수 함수다.
pub fn addNode(cards: *Cards, name: []const u8) void {
    const prefix = "pcmC";
    if (!std.mem.startsWith(u8, name, prefix)) return;
    const rest = name[prefix.len..];
    const d = std.mem.indexOfScalar(u8, rest, 'D') orelse return;
    if (d == 0 or !std.ascii.isDigit(rest[0])) return;
    const card = std.fmt.parseInt(u8, rest[0..d], 10) catch return;
    if (card >= MAX_CARDS) return;
    const bit = @as(u32, 1) << @intCast(card);
    if (std.mem.eql(u8, rest[d..], "D0p")) {
        cards.playback |= bit;
    } else if (std.mem.eql(u8, rest[d..], "D0c")) {
        cards.capture |= bit;
    }
}

pub const Defaults = struct {
    playback: ?u8 = null,
    capture: ?u8 = null,

    pub fn eql(a: Defaults, b: Defaults) bool {
        return a.playback == b.playback and a.capture == b.capture;
    }
};

fn highest(mask: u32) ?u8 {
    if (mask == 0) return null;
    return @intCast(31 - @clz(mask));
}

/// 재생과 녹음 각각 번호가 가장 큰 카드. 순수 함수다.
pub fn defaultsFor(cards: Cards) Defaults {
    return .{ .playback = highest(cards.playback), .capture = highest(cards.capture) };
}

/// /etc/asound.conf의 글자. 둘 다 없으면 null이다(파일을 지운다). 순수 함수다.
///
/// `sysdefault:CARD=N`은 alsa.conf가 그 카드의 원래 `default`(plug → dmix · dsnoop)에
/// 붙여 둔 이름이다. `pcm.!default`를 덮은 뒤에도 그 길이 그대로 남으므로 섞기 ·
/// 형식 변환은 카드 0일 때와 같다. 믹서(`amixer` · `alsamixer`)의 기본은 재생 쪽
/// 카드다 — 사람이 볼륨을 만지는 것은 소리가 나는 카드이기 때문이다.
///
/// 카드 번호를 글자로 박지 않고 `getenv`의 기본값으로 둔다. alsa-lib의 원래
/// `default`는 `ALSA_PCM_CARD` · `ALSA_CARD`를 먼저 보는데(pcm/default.conf),
/// `pcm.!default`를 덮으면 그 길이 사라져 `ALSA_CARD=0 aplay`가 env를 무시한다
/// (AU-M2 plan 확정 4). 믹서 쪽(`ctl.!default`)은 안 덮으므로 env가 그대로 먹는다.
pub fn render(buf: []u8, d: Defaults) ?[]const u8 {
    const ctl = d.playback orelse d.capture orelse return null;
    var w: std.Io.Writer = .fixed(buf);
    w.writeAll("# tars-init이 쓴다(AU-M2). 사운드 카드가 오고 갈 때마다 다시 쓴다.\n" ++
        "# 재생과 녹음 각각, 장치 0을 가진 카드 중 번호가 가장 큰 것이 기본이다.\n" ++
        "# ALSA_CARD(또는 ALSA_PCM_CARD)를 주면 그 카드가 두 방향 다 기본이다.\n" ++
        "pcm.!default {\n\ttype asym\n") catch return null;
    if (d.playback) |n| w.print(DIRECTION, .{ "playback", n }) catch return null;
    if (d.capture) |n| w.print(DIRECTION, .{ "capture", n }) catch return null;
    w.print("}}\ndefaults.ctl.card {d}\n", .{ctl}) catch return null;
    return w.buffered();
}

/// 한 방향. `{s}`가 playback · capture이고 `{d}`가 env가 없을 때의 카드다.
const DIRECTION =
    "\t{s}.pcm {{\n" ++
    "\t\t@func concat\n" ++
    "\t\tstrings [ \"sysdefault:CARD=\" {{ @func getenv vars [ ALSA_PCM_CARD ALSA_CARD ] default \"{d}\" }} ]\n" ++
    "\t}}\n";

/// 지금 /dev/snd에 있는 카드. 디렉터리가 없으면(소리 장치가 없는 기계) 빈 집합이다.
fn scanCards() Cards {
    var cards: Cards = .{};
    const rc = linux.open(SND_DIR.ptr, .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true }, 0);
    if (failed(rc) != null) return cards;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var buf: [2048]u8 align(8) = undefined;
    while (true) {
        const n = linux.getdents64(fd, &buf, buf.len);
        if (failed(n) != null or n == 0) break;
        var off: usize = 0;
        while (off < n) {
            const ent: *align(1) const linux.dirent64 = @ptrCast(&buf[off]);
            off += ent.reclen;
            addNode(&cards, std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&ent.name)), 0));
        }
    }
    return cards;
}

fn writeConf(text: []const u8) ?linux.E {
    const rc = linux.open(ASOUND_CONF_TMP.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, 0o644);
    if (failed(rc)) |e| return e;
    const fd: i32 = @intCast(rc);
    var done: usize = 0;
    while (done < text.len) {
        const n = linux.write(fd, text[done..].ptr, text.len - done);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            _ = linux.close(fd);
            return e;
        }
        done += n;
    }
    _ = linux.close(fd);
    return failed(linux.rename(ASOUND_CONF_TMP.ptr, ASOUND_CONF_PATH.ptr));
}

/// 지난번에 쓴 기본. 처음은 "카드 없음"이라 소리 장치가 없는 기계에서는 한 번도
/// 안 쓰고 한 줄도 안 찍는다.
var defaults_now: Defaults = .{};

/// 감독 루프가 깰 때마다 부른다. 카드가 오거나 갔으면 /etc/asound.conf를 다시 쓴다.
///
/// 쓰기가 실패해도 기억은 새 값으로 바꾼다 — 안 바꾸면 매 초 같은 실패를 찍는다.
/// 다음 변화가 다시 쓴다.
pub fn follow() void {
    const want = defaultsFor(scanCards());
    if (want.eql(defaults_now)) return;
    defaults_now = want;

    var buf: [1024]u8 = undefined;
    const text = render(&buf, want) orelse {
        _ = linux.unlink(ASOUND_CONF_PATH.ptr);
        std.debug.print("tars-init: audio: no sound card left, removed {s}\n", .{ASOUND_CONF_PATH});
        return;
    };
    if (writeConf(text)) |e| {
        std.debug.print("tars-init: audio: cannot write {s} (errno {d})\n", .{ ASOUND_CONF_PATH, @intFromEnum(e) });
        return;
    }
    var pb: [3]u8 = undefined;
    var cb: [3]u8 = undefined;
    std.debug.print("tars-init: audio: default card is {s} for playback, {s} for capture\n", .{
        cardText(&pb, want.playback), cardText(&cb, want.capture),
    });
}

/// 로그용. 카드 번호를 글자로, 없으면 "none". 번호는 32 아래라 두 자리면 된다.
fn cardText(buf: *[3]u8, n: ?u8) []const u8 {
    const v = n orelse return "none";
    return std.fmt.bufPrint(buf, "{d}", .{v}) catch unreachable;
}
