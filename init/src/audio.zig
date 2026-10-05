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
