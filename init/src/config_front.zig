//! TC-M1. `tars-config`의 앞문 넷 — 남의 문법 파일에 사람이 처음 적는 한 줄을 이 명령이
//! 써 준다(TC design 결정 12 ~ 16).
//!
//!   wifi SSID [--country CC]   /config/wpa_supplicant.conf — wpa_passphrase가 짓는 덩어리
//!   ssh [on|off]               /config/services.d/sshd — 템플릿으로 가는 링크
//!   ssh-key add [KEY] | list   /config/ssh/authorized_keys — ssh-keygen이 읽어 본 한 줄
//!   firewall [allow|deny P]    /config/nftables.d/tars-config.nft — 이 명령만 쓰는 파일
//!   dictation [key|set …]      /config/groq.key · /config/dictation.conf
//!
//! 남의 문법은 다시 짓지 않는다(결정 10). 덩어리를 짓는 것은 `wpa_passphrase`, 키를 읽는
//! 것은 `ssh-keygen`, 규칙을 올리는 것은 `nft`다 — 이 파일은 그 도구를 부르고, 낸 것을
//! 제자리에 두고, 다음에 무엇을 하면 되는지 말한다. 글자를 다루는 것은 전부
//! `config_front_edit.zig`(호스트 검사가 본다)이고, 여기는 시스템 콜 쪽이다.
const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");
const cli = @import("config_cli.zig");
const secret = @import("secret.zig");
const fe = @import("config_front_edit.zig");
const account = @import("account.zig");

const say = cli.say;
const complain = cli.complain;
const failed = cli.failed;

const WPA_PATH: [:0]const u8 = "/config/wpa_supplicant.conf";
const WPA_TEMP: [:0]const u8 = "/config/.wpa_supplicant.conf.new";
const SERVICES_DIR: [:0]const u8 = "/config/services.d";
const SSHD_LINK: [:0]const u8 = "/config/services.d/sshd";
/// SV design 결정 6의 템플릿. 사람이 `ln -s`로 거는 그 대상이다.
const SSHD_TEMPLATE: [:0]const u8 = "/etc/tars/services/sshd";
const SSH_DIR: [:0]const u8 = "/config/ssh";
const KEYS_PATH: [:0]const u8 = "/config/ssh/authorized_keys";
const KEYS_TEMP: [:0]const u8 = "/config/ssh/.authorized_keys.new";
const NFT_DIR: [:0]const u8 = "/config/nftables.d";
/// 이 명령만 쓰는 nft 파일(결정 14). 사람의 파일과 갈라 둔다 — 지우는 동사(`deny`)가 사람의
/// 줄을 건드릴 길이 없다.
const NFT_PATH: [:0]const u8 = "/config/nftables.d/tars-config.nft";
const NFT_TEMP: [:0]const u8 = "/config/nftables.d/.tars-config.nft.new";
const KEY_PATH: [:0]const u8 = "/config/groq.key";
const KEY_TEMP: [:0]const u8 = "/config/.groq.key.new";
const DICT_PATH: [:0]const u8 = "/config/dictation.conf";
const DICT_TEMP: [:0]const u8 = "/config/.dictation.conf.new";

/// 부르는 도구. 경로는 `kernel/guest_tools.sh`가 싣는 자리이고 `firewall.zig`의 NFT_PATH와 같다.
const WPA_PASSPHRASE: [:0]const u8 = "/usr/bin/wpa_passphrase";
const SSH_KEYGEN: [:0]const u8 = "/usr/bin/ssh-keygen";
const NFT: [:0]const u8 = "/usr/bin/nft";
const MKPASSWD: [:0]const u8 = "/usr/bin/mkpasswd";

/// HP-M2 `passwd`가 바꾸는 둘. 앞의 것이 영속하는 해시(설치기가 처음 쓴다), 뒤의 것이 init이
/// 부팅마다 짓는 사본이고 sudo의 `pam_unix`가 읽는다. 경로는 `login.zig`의 `SHADOW_STORE_PATH` ·
/// `SHADOW_PATH`와 같다 — 이 명령은 init의 파일을 import하지 않는다.
const SHADOW_STORE: [:0]const u8 = "/config/shadow";
const SHADOW_STORE_TEMP: [:0]const u8 = "/config/.shadow.new";
const SHADOW_ETC: [:0]const u8 = "/etc/shadow";
const SHADOW_ETC_TEMP: [:0]const u8 = "/etc/.shadow.new";
const FIREWALL_RULES: [:0]const u8 = "/etc/tars/firewall.nft";

const ENVP = [_:null]?[*:0]const u8{"PATH=/usr/local/bin:/usr/bin:/bin"}; // environ.PATH_ENTRY와 같다(TP design 결정 20)

const BUF = 16384;

// ── 바탕 ──────────────────────────────────────────────────────────────

/// 비밀을 묻기 전에 쓸 권한부터 본다(2026-11-05 Air 실기). 전에는 사용자가 `tars-config wifi SSID`를 치면
/// Wi-Fi 비밀번호를 다 받은 뒤 파일을 쓸 때에야 `permission denied`가 나왔고, 이어서 친 `sudo`의
/// `[sudo] password for tars:`에 Wi-Fi 비밀번호를 넣어 세 번 틀렸다. `/config`는 root만 쓴다(HP-M2) —
/// `passwd`와 같이 euid로 먼저 거른다.
fn needRoot() bool {
    if (linux.geteuid() == 0) return true;
    _ = cli.denied(.PERM);
    return false;
}

fn needDisk() bool {
    var mounts: [8192]u8 = undefined;
    if (cli.configDisk(&mounts) != null) return true;
    complain("no config disk is mounted at /config; a change there would be gone at the next boot", .{});
    return false;
}

/// 지금의 tars.conf를 init과 같은 길로 읽는다. 다음 걸음을 말할 때(`net=off`면 무선이 안
/// 뜬다 등) 쓴다.
fn tarsConf() config.Config {
    var buf: [cli.READ_MAX]u8 = undefined;
    return switch (cli.readFile(cli.CONF_PATH, &buf)) {
        .bytes => |b| cli.parsed(b),
        else => .{},
    };
}

fn readOr(path: [*:0]const u8, buf: []u8) ?[]const u8 {
    return switch (cli.readFile(path, buf)) {
        .bytes => |b| b,
        .missing => "",
        .failed => |e| {
            complain("cannot read {s} (errno {d})", .{ std.mem.span(path), @backingInt(e) });
            return null;
        },
    };
}

/// temp에 쓰고 path로 갈아 끼운다(결정 5와 같은 까닭). mode는 새 파일의 것이다.
fn replace(path: [:0]const u8, temp: [:0]const u8, text: []const u8, mode: linux.mode_t) bool {
    const rc = linux.open(temp.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, mode);
    if (failed(rc)) |e| {
        if (cli.denied(e)) return false;
        complain("cannot create {s} (errno {d})", .{ temp, @backingInt(e) });
        return false;
    }
    const fd: i32 = @intCast(rc);
    // umask가 mode를 깎을 수 있다. 비밀(0600)은 깎이는 쪽이라 괜찮지만 0644가 0600이 되면
    // 사람이 놀란다 — 적은 그대로 맞춘다.
    _ = linux.fchmod(fd, mode);
    const ok = cli.writeAll(fd, text);
    _ = linux.close(fd);
    if (!ok) {
        complain("cannot write {s}", .{temp});
        return false;
    }
    if (failed(linux.rename(temp.ptr, path.ptr))) |e| {
        if (cli.denied(e)) return false;
        complain("cannot rename {s} to {s} (errno {d})", .{ temp, path, @backingInt(e) });
        return false;
    }
    return true;
}

fn ensureDir(path: [:0]const u8, mode: linux.mode_t) bool {
    if (failed(linux.mkdir(path.ptr, mode))) |e| {
        if (e == .EXIST) return true;
        if (cli.denied(e)) return false;
        complain("cannot make {s} (errno {d})", .{ path, @backingInt(e) });
        return false;
    }
    _ = linux.chmod(path.ptr, mode);
    return true;
}

const Ran = struct { code: u8, out: []const u8 };

/// argv를 fork · execve로 돌린다. input을 표준 입력으로 주고 표준 출력 · 에러를 함께 받는다
/// (out에 들어가는 만큼). `install.zig`의 `runTool`과 같은 모양이고 다른 것은 출력을 돌려준다는
/// 것 하나다. 시그널로 죽었으면 128 + 번호.
fn run(argv: [*:null]const ?[*:0]const u8, input: []const u8, out: []u8) ?Ran {
    var in_fds: [2]i32 = undefined;
    var out_fds: [2]i32 = undefined;
    if (failed(linux.pipe2(&in_fds, .{ .CLOEXEC = true }))) |_| return null;
    if (failed(linux.pipe2(&out_fds, .{ .CLOEXEC = true }))) |_| return null;
    const pid = linux.fork();
    if (failed(pid)) |_| return null;
    if (pid == 0) {
        _ = linux.dup2(in_fds[0], 0);
        _ = linux.dup2(out_fds[1], 1);
        _ = linux.dup2(out_fds[1], 2);
        _ = linux.execve(argv[0].?, argv, &ENVP);
        linux.exit(127);
    }
    _ = linux.close(in_fds[0]);
    _ = linux.close(out_fds[1]);
    // 입력은 비밀번호 · 키 한 줄이라 파이프 버퍼 안에 든다. 자식이 읽기 전에 다 써도 안 막힌다.
    _ = cli.writeAll(in_fds[1], input);
    _ = linux.close(in_fds[1]);
    var len: usize = 0;
    while (true) {
        var sink: [512]u8 = undefined;
        const dst: []u8 = if (len < out.len) out[len..] else &sink;
        const n = linux.read(out_fds[0], dst.ptr, dst.len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            break;
        }
        if (n == 0) break;
        if (len < out.len) len += n;
    }
    _ = linux.close(out_fds[0]);
    var status: u32 = 0;
    while (failed(linux.wait4(@intCast(pid), @ptrCast(&status), 0, null))) |e| {
        if (e != .INTR) return null;
    }
    const code: u8 = if (linux.W.IFEXITED(status)) linux.W.EXITSTATUS(status) else 128 +| @as(u8, @truncate(@backingInt(linux.W.TERMSIG(status))));
    return .{ .code = code, .out = out[0..len] };
}

/// 비밀 하나를 읽는다 — 비밀번호 · API 키. 표준 입력이 tty면 `secret.readMasked`가 prompt를 찍고 글자마다
/// `*`를 찍으며 한 줄을(PW design), 아니면(파이프 · 파일) 끝까지 읽는다. 끝의 개행은 뗀다. 명령줄 인자로 받지
/// 않는 이유는 `/proc/<pid>/cmdline`과 셸 히스토리다(VD design 결정 4와 같다). null은 너무 길다는 뜻이다.
fn readSecret(prompt: []const u8, buf: []u8) ?[]const u8 {
    if (secret.readMasked(2, prompt, buf)) |r| return ttySecret(r);
    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(0, buf[len..].ptr, buf.len - len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            break;
        }
        if (n == 0) break;
        len += n;
    }
    if (len == buf.len) return null;
    return std.mem.trimEnd(u8, buf[0..len], "\r\n");
}

/// tty에서 읽은 답. 사람이 Ctrl+C · 빈 칸의 Ctrl+D로 그만두면 여기서 끝낸다 — 부르는 쪽의 null은 "너무
/// 길다"이고, 빈 값을 넘기면 빈 passphrase가 된다. 비밀을 묻는 자리는 모두 무엇을 쓰기 전이라 끝내도 남는
/// 것이 없다. 130은 셸이 Ctrl+C에 주는 값(128 + SIGINT)이다.
fn ttySecret(r: secret.Result) ?[]const u8 {
    switch (r) {
        .line => |l| return l,
        .too_long => return null,
        .eof, .cancel => {
            complain("cancelled; nothing was changed", .{});
            linux.exit_group(130);
        },
    }
}

// ── wifi ──────────────────────────────────────────────────────────────

/// `tars-config wifi SSID [--country CC]` (결정 12).
pub fn wifi(args: []const [*:0]const u8) u8 {
    const add = switch (fe.wifiArgs(args)) {
        .status => return wifiStatus(),
        .add => |a| a,
        .usage => return cli.usage(),
        .bad_country => {
            complain("--country takes two capital letters, like KR", .{});
            return cli.EXIT_USAGE;
        },
        .bad_ssid => {
            complain("an SSID is 1 to 32 bytes without control characters", .{});
            return cli.EXIT_USAGE;
        },
    };
    const ssid = add.ssid;
    const country = add.country;
    if (!needRoot()) return cli.EXIT_DENIED;
    if (!needDisk()) return cli.EXIT_IO;

    var pass_buf: [256]u8 = undefined;
    var prompt_buf: [96]u8 = undefined;
    const prompt = std.fmt.bufPrint(&prompt_buf, "passphrase for {s}: ", .{ssid}) catch "passphrase: ";
    const pass = readSecret(prompt, &pass_buf) orelse {
        complain("the passphrase is too long", .{});
        return cli.EXIT_REFUSED;
    };
    // wpa_passphrase가 표준 입력에서 읽는다 — 인자로 주면 ps에 보인다.
    var line_buf: [258]u8 = undefined;
    const line = std.fmt.bufPrint(&line_buf, "{s}\n", .{pass}) catch unreachable;
    var ssid_z: [33:0]u8 = @splat(0);
    @memcpy(ssid_z[0..ssid.len], ssid);
    const argv = [_:null]?[*:0]const u8{ WPA_PASSPHRASE, &ssid_z };
    var out: [2048]u8 = undefined;
    const ran = run(&argv, line, &out) orelse {
        complain("could not run {s}", .{WPA_PASSPHRASE});
        return cli.EXIT_IO;
    };
    if (ran.code != 0) {
        complain("wpa_passphrase refused (exit {d}): {s}", .{ ran.code, std.mem.trim(u8, ran.out, " \n") });
        complain("nothing was written", .{});
        return cli.EXIT_REFUSED;
    }
    var block_buf: [1024]u8 = undefined;
    const block = fe.networkBlock(&block_buf, ran.out) orelse {
        complain("wpa_passphrase printed something that is not one network block; nothing was written", .{});
        return cli.EXIT_IO;
    };

    var conf_buf: [BUF]u8 = undefined;
    const conf = readOr(WPA_PATH, &conf_buf) orelse return cli.EXIT_IO;
    const existed = conf.len > 0 or fileExists(WPA_PATH);
    var placed_buf: [BUF]u8 = undefined;
    const placed = fe.placeNetwork(&placed_buf, conf, block) orelse {
        complain("{s} would grow past {d} bytes", .{ WPA_PATH, BUF });
        return cli.EXIT_REFUSED;
    };
    var text = placed.text;
    var cc_buf: [BUF]u8 = undefined;
    if (country) |cc| text = fe.setCountry(&cc_buf, text, cc) orelse {
        complain("{s} would grow past {d} bytes", .{ WPA_PATH, BUF });
        return cli.EXIT_REFUSED;
    };
    // 해시된 psk가 든다 — 그 망에 붙는 데는 그것으로 충분하므로 비밀이다.
    if (!replace(WPA_PATH, WPA_TEMP, text, 0o600)) return cli.EXIT_IO;

    fe.wifiDone(cli.Say{}, ssid, WPA_PATH, placed.replaced, country != null, tarsConf().net == .off, existed);
    return cli.EXIT_OK;
}

fn wifiStatus() u8 {
    var conf_buf: [BUF]u8 = undefined;
    const conf = readOr(WPA_PATH, &conf_buf) orelse return cli.EXIT_IO;
    if (conf.len == 0) {
        say("no {s}: wifi is off. tars-config wifi SSID adds a network\n", .{WPA_PATH});
        return cli.EXIT_OK;
    }
    fe.wifiStatusLines(cli.Say{}, conf);
    return cli.EXIT_OK;
}

fn fileExists(path: [:0]const u8) bool {
    return failed(linux.access(path.ptr, linux.F_OK)) == null;
}

// ── ssh ───────────────────────────────────────────────────────────────

/// 링크가 템플릿을 가리키는가. 사람이 다른 sshd 스크립트를 그 이름으로 두었으면 거짓이다.
fn sshdLinked() fe.Sshd {
    var buf: [256]u8 = undefined;
    const rc = linux.readlink(SSHD_LINK.ptr, &buf, buf.len);
    if (failed(rc)) |e| return if (e == .NOENT) .none else .other;
    return if (std.mem.eql(u8, buf[0..rc], SSHD_TEMPLATE)) .template else .other;
}

/// `tars-config ssh [on|off]` (결정 13).
pub fn ssh(args: []const [*:0]const u8) u8 {
    const verb = fe.sshArgs(args);
    switch (verb) {
        .usage => return cli.usage(),
        .status => {
            var keys_buf: [BUF]u8 = undefined;
            const keys = readOr(KEYS_PATH, &keys_buf) orelse return cli.EXIT_IO;
            say("sshd: {s}\n", .{fe.sshdText(sshdLinked())});
            say("keys: {d} in {s}\n", .{ fe.keyCount(keys), KEYS_PATH });
            sayFirewall22();
            return cli.EXIT_OK;
        },
        // 동사가 틀린 것은 디스크를 본 뒤에 말한다(HC-M1 plan 확정 2).
        .on, .off, .bad_verb => {},
    }
    if (!needDisk()) return cli.EXIT_IO;
    if (verb == .on) {
        switch (sshdLinked()) {
            .template => say("sshd: already on\n", .{}),
            .other => {
                complain("{s} is there and is not a link to {s}; leaving it", .{ SSHD_LINK, SSHD_TEMPLATE });
                return cli.EXIT_REFUSED;
            },
            .none => {
                if (!ensureDir(SERVICES_DIR, 0o755)) return cli.EXIT_IO;
                if (failed(linux.symlink(SSHD_TEMPLATE.ptr, SSHD_LINK.ptr))) |e| {
                    if (cli.denied(e)) return cli.EXIT_DENIED;
                    complain("cannot link {s} (errno {d})", .{ SSHD_LINK, @backingInt(e) });
                    return cli.EXIT_IO;
                }
                say("sshd: on — {s} -> {s}; tars-config reload starts it now (or the next boot)\n", .{ SSHD_LINK, SSHD_TEMPLATE });
            },
        }
        var keys_buf: [BUF]u8 = undefined;
        const keys = readOr(KEYS_PATH, &keys_buf) orelse return cli.EXIT_IO;
        if (fe.keyCount(keys) == 0) say("no key yet: tars-config ssh-key add 'ssh-ed25519 AAAA… you@host'\n", .{});
        sayFirewall22();
        return cli.EXIT_OK;
    }
    if (verb == .off) {
        switch (sshdLinked()) {
            .none => say("sshd: already off\n", .{}),
            .other => {
                complain("{s} is not a link to {s}; leaving it", .{ SSHD_LINK, SSHD_TEMPLATE });
                return cli.EXIT_REFUSED;
            },
            .template => {
                if (failed(linux.unlink(SSHD_LINK.ptr))) |e| {
                    if (cli.denied(e)) return cli.EXIT_DENIED;
                    complain("cannot remove {s} (errno {d})", .{ SSHD_LINK, @backingInt(e) });
                    return cli.EXIT_IO;
                }
                say("sshd: off — tars-config reload stops it now (or the next boot)\n", .{});
            },
        }
        return cli.EXIT_OK;
    }
    return cli.usage();
}

/// firewall=on이면 22를 이 명령이 열었는지 말한다.
fn sayFirewall22() void {
    if (tarsConf().firewall != .on) return;
    var buf: [BUF]u8 = undefined;
    const text = readOr(NFT_PATH, &buf) orelse return;
    fe.firewall22(cli.Say{}, text, NFT_DIR);
}

/// `tars-config ssh-key add [KEY] | list` (결정 13).
pub fn sshKey(args: []const [*:0]const u8) u8 {
    const given = switch (fe.sshKeyArgs(args)) {
        .usage => return cli.usage(),
        .list => {
            if (!fileExists(KEYS_PATH)) {
                say("no {s}\n", .{KEYS_PATH});
                return cli.EXIT_OK;
            }
            const argv = [_:null]?[*:0]const u8{ SSH_KEYGEN, "-l", "-f", KEYS_PATH };
            var out: [BUF]u8 = undefined;
            const ran = run(&argv, "", &out) orelse return cli.EXIT_IO;
            _ = cli.writeAll(1, ran.out);
            return if (ran.code == 0) cli.EXIT_OK else cli.EXIT_REFUSED;
        },
        .add => |k| k,
    };
    if (!needRoot()) return cli.EXIT_DENIED;
    if (!needDisk()) return cli.EXIT_IO;

    // 키 한 줄 — 인자 하나(따옴표로 싼 줄)이거나 표준 입력(`< id_ed25519.pub`).
    var in_buf: [8192]u8 = undefined;
    const raw: []const u8 = given orelse (readSecret("public key: ", &in_buf) orelse {
        complain("the key is too long", .{});
        return cli.EXIT_REFUSED;
    });
    const line = fe.keyLine(raw) orelse {
        complain("give one public key line, like 'ssh-ed25519 AAAA… you@host'", .{});
        return cli.EXIT_USAGE;
    };
    // 키인지는 ssh-keygen이 정한다. 지문이 사람에게 보여 줄 것이기도 하다.
    const argv = [_:null]?[*:0]const u8{ SSH_KEYGEN, "-l", "-f", "-" };
    var out: [1024]u8 = undefined;
    var with_nl: [8200]u8 = undefined;
    const input = std.fmt.bufPrint(&with_nl, "{s}\n", .{line}) catch return cli.EXIT_REFUSED;
    const ran = run(&argv, input, &out) orelse {
        complain("could not run {s}", .{SSH_KEYGEN});
        return cli.EXIT_IO;
    };
    const fp = std.mem.trim(u8, ran.out, " \n");
    if (ran.code != 0) {
        complain("ssh-keygen does not read this as a public key: {s}", .{fp});
        complain("nothing was written", .{});
        return cli.EXIT_REFUSED;
    }
    const body = fe.keyBody(line) orelse {
        complain("ssh-keygen read it, but the key has no AAAA… body this command can compare; nothing was written", .{});
        return cli.EXIT_REFUSED;
    };

    var keys_buf: [BUF]u8 = undefined;
    const keys = readOr(KEYS_PATH, &keys_buf) orelse return cli.EXIT_IO;
    if (fe.hasKey(keys, body)) {
        say("ssh-key: already there — {s}\n", .{fp});
    } else {
        var new_buf: [BUF + 8200]u8 = undefined;
        const text = fe.appendLine(&new_buf, keys, line) orelse return cli.EXIT_REFUSED;
        if (!ensureDir(SSH_DIR, 0o700)) return cli.EXIT_IO;
        if (!replace(KEYS_PATH, KEYS_TEMP, text, 0o600)) return cli.EXIT_IO;
        say("ssh-key: added {s}\n", .{fp});
        say("sshd reads {s} at every login — no restart\n", .{KEYS_PATH});
    }
    if (sshdLinked() == .none) say("sshd is off: tars-config ssh on, then tars-config reload\n", .{});
    sayFirewall22();
    return cli.EXIT_OK;
}

// ── firewall ──────────────────────────────────────────────────────────

/// `tars-config firewall [allow|deny PORT[/udp]]` (결정 14).
pub fn firewall(args: []const [*:0]const u8) u8 {
    const c = tarsConf();
    var buf: [BUF]u8 = undefined;
    const text = readOr(NFT_PATH, &buf) orelse return cli.EXIT_IO;
    const change = switch (fe.firewallArgs(args)) {
        .status => {
            say("firewall={s}\n", .{@tagName(c.firewall)});
            if (fe.firewallRules(cli.Say{}, text) == 0) say("tars-config opened no port ({s} has no rule)\n", .{NFT_PATH});
            say("rules you wrote yourself live in other files under {s}; nft list ruleset shows what is up\n", .{NFT_DIR});
            return cli.EXIT_OK;
        },
        .change => |ch| ch,
        .usage => return cli.usage(),
        .bad_port => {
            complain("a port is 1 to 65535, optionally /tcp or /udp (tcp is the default)", .{});
            return cli.EXIT_USAGE;
        },
    };
    const allow = change.allow;
    if (!needDisk()) return cli.EXIT_IO;
    var rule_buf: [32]u8 = undefined;
    const rule = fe.ruleLine(&rule_buf, change.spec);

    var new_buf: [BUF + 64]u8 = undefined;
    switch (fe.firewallChange(&new_buf, text, allow, rule)) {
        .overflow => return cli.EXIT_REFUSED,
        .same => {
            fe.firewallSaid(cli.Say{}, allow, rule, false, NFT_DIR);
            return cli.EXIT_OK;
        },
        .changed => |t| {
            if (!ensureDir(NFT_DIR, 0o755)) return cli.EXIT_IO;
            if (!replace(NFT_PATH, NFT_TEMP, t, 0o644)) return cli.EXIT_IO;
            fe.firewallSaid(cli.Say{}, allow, rule, true, NFT_DIR);
        },
    }

    if (c.firewall != .on) {
        say("firewall=off: nothing is filtered now; the rule counts once firewall=on (tars-config set firewall=on, reboot)\n", .{});
        return cli.EXIT_OK;
    }
    // 켜져 있으면 init이 부팅에 하는 그 명령을 지금 돈다(FW 결정 5). nft는 전부 올리거나 하나도
    // 안 올리므로, 실패하면 지금 선 규칙이 그대로다 — 그 이유는 nft가 말한다.
    const argv = [_:null]?[*:0]const u8{ NFT, "-f", FIREWALL_RULES };
    var out: [4096]u8 = undefined;
    const ran = run(&argv, "", &out) orelse {
        complain("could not run {s}", .{NFT});
        return cli.EXIT_IO;
    };
    if (ran.code == 0) {
        say("applied now: nft -f {s}\n", .{FIREWALL_RULES});
        return cli.EXIT_OK;
    }
    _ = cli.writeAll(2, ran.out);
    complain("nft -f {s} refused (exit {d}); the rules that were up stay up", .{ FIREWALL_RULES, ran.code });
    complain("the next boot would fall back to the base rules too — fix the file nft named above", .{});
    return cli.EXIT_REFUSED;
}

// ── dictation ─────────────────────────────────────────────────────────

/// `tars-config dictation [key [KEY] | set KEY=VALUE…]` (결정 15).
pub fn dictation(args: []const [*:0]const u8) u8 {
    const parsed = fe.dictationArgs(args);
    switch (parsed) {
        .status => {
            say("key: {s}\n", .{if (fileExists(KEY_PATH)) "/config/groq.key is there (not shown)" else "none — tars-config dictation key"});
            var buf: [BUF]u8 = undefined;
            const text = readOr(DICT_PATH, &buf) orelse return cli.EXIT_IO;
            if (text.len == 0) say("no {s}: tars-dictate uses its defaults (tars-dictate -h)\n", .{DICT_PATH}) else _ = cli.writeAll(1, text);
            return cli.EXIT_OK;
        },
        .key => |given| {
            if (!needRoot()) return cli.EXIT_DENIED;
            if (!needDisk()) return cli.EXIT_IO;
            var in_buf: [512]u8 = undefined;
            const raw: []const u8 = given orelse (readSecret("Groq API key: ", &in_buf) orelse {
                complain("the key is too long", .{});
                return cli.EXIT_REFUSED;
            });
            const key = fe.apiKey(raw) orelse {
                complain("an API key is one word without spaces or control characters; nothing was written", .{});
                return cli.EXIT_REFUSED;
            };
            var line_buf: [520]u8 = undefined;
            const line = std.fmt.bufPrint(&line_buf, "{s}\n", .{key}) catch return cli.EXIT_REFUSED;
            if (!replace(KEY_PATH, KEY_TEMP, line, 0o600)) return cli.EXIT_IO;
            say("dictation: wrote {s} (0600, {d} characters)\n", .{ KEY_PATH, key.len });
            say("tars-dictate reads it at every run — no restart\n", .{});
            if (tarsConf().net == .off) say("net=off: dictation needs the network — tars-config set net=dhcp\n", .{});
            return cli.EXIT_OK;
        },
        .usage => return cli.usage(),
        // 쌍의 거절은 디스크를 본 뒤에 말한다(HC-M1 plan 확정 2).
        .set, .no_equals, .unknown_key, .control_byte => {},
    }
    if (!needDisk()) return cli.EXIT_IO;
    const pairs = switch (parsed) {
        .set => |p| p,
        .no_equals => |arg| {
            complain("'{s}' has no '='; set takes KEY=VALUE", .{arg});
            return cli.EXIT_USAGE;
        },
        .unknown_key => |key| {
            complain("unknown dictation key '{s}'; the keys are in tars-dictate -h", .{key});
            complain("nothing was written", .{});
            return cli.EXIT_REFUSED;
        },
        .control_byte => |key| {
            complain("{s}: a control character cannot go into a config line", .{key});
            return cli.EXIT_REFUSED;
        },
        .status, .key, .usage => unreachable, // 위의 switch가 돌아갔다
    };
    var buf: [BUF]u8 = undefined;
    const text = readOr(DICT_PATH, &buf) orelse return cli.EXIT_IO;
    var work: [2][BUF]u8 = undefined;
    const written = fe.dictationApply(cli.Say{}, .{ &work[0], &work[1] }, text, pairs) orelse {
        complain("{s} would grow past {d} bytes", .{ DICT_PATH, BUF });
        return cli.EXIT_REFUSED;
    };
    if (!replace(DICT_PATH, DICT_TEMP, written, 0o644)) return cli.EXIT_IO;
    say("tars-dictate reads {s} at every run — no restart; it warns about a value it does not take\n", .{DICT_PATH});
    return cli.EXIT_OK;
}

// ── check ─────────────────────────────────────────────────────────────

/// `tars-config check`가 앞문 넷의 파일에서 보는 것(결정 16). 문제의 수를 돌려준다.
/// 남의 문법은 안 읽는다 — 파일이 있는지 · 모드 · tars.conf와 맞는지만 본다.
pub fn check(c: config.Config) usize {
    var problems: usize = 0;
    if (fileExists(WPA_PATH) and c.net == .off) {
        say("{s} is there but net=off, so init does not start wpa_supplicant; tars-config set net=dhcp\n", .{WPA_PATH});
        problems += 1;
    }
    if (sshdLinked() == .template) {
        var buf: [BUF]u8 = undefined;
        const keys = readOr(KEYS_PATH, &buf) orelse "";
        if (fe.keyCount(keys) == 0) {
            say("sshd is on but {s} has no key, so nobody can log in; tars-config ssh-key add\n", .{KEYS_PATH});
            problems += 1;
        }
    }
    // 비밀 셋. 남이 쓸 수 있으면 sshd가 그 파일을 버리고(StrictModes), 읽을 수 있으면 비밀이 아니다.
    for ([_][:0]const u8{ KEYS_PATH, KEY_PATH, WPA_PATH }) |path| {
        var st: linux.Statx = undefined;
        if (failed(linux.statx(linux.AT.FDCWD, path.ptr, 0, .{ .MODE = true }, &st)) != null) continue;
        const mode = st.mode & 0o777;
        if (mode & 0o077 != 0) {
            say("{s} is mode {o}; others can read it — chmod 600 {s}\n", .{ path, mode, path });
            problems += 1;
        }
    }
    if (c.firewall == .off) {
        var buf: [BUF]u8 = undefined;
        const text = readOr(NFT_PATH, &buf) orelse "";
        if (fe.keyCount(text) > 0) {
            say("note: firewall=off, so the ports tars-config opened in {s} filter nothing yet\n", .{NFT_PATH});
        }
    }
    var dbuf: [BUF]u8 = undefined;
    const dict = readOr(DICT_PATH, &dbuf) orelse "";
    problems += fe.dictationUnknown(cli.Say{}, dict, DICT_PATH);
    return problems;
}

// ── passwd ────────────────────────────────────────────────────────────

/// 비밀 한 줄을 읽는다. `readSecret`과 다른 것은 파이프에서도 개행에서 멈춘다는 것 하나다 —
/// `passwd`는 같은 표준 입력에서 두 줄(새 값 · 다시)을 읽는다. 한 바이트씩 읽어 다음 줄을
/// 삼키지 않는다(tty 길의 `readMasked`도 그렇다). 개행 없이 끝나면 읽은 만큼, 아무것도 없으면 null.
/// 버퍼보다 긴 줄은 빈 값으로 돌려준다(아래의 빈 값 검사가 거절한다).
fn readSecretLine(prompt: []const u8, buf: []u8) ?[]const u8 {
    if (secret.readMasked(2, prompt, buf)) |r| return ttySecret(r) orelse buf[0..0];
    var len: usize = 0;
    var got_any = false;
    while (true) {
        var b: [1]u8 = undefined;
        const n = linux.read(0, &b, 1);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            break;
        }
        if (n == 0) break;
        got_any = true;
        if (b[0] == '\n') break;
        // 버퍼를 넘는 줄은 끝까지 읽어 버리고 길이를 넘긴 것으로 알린다.
        if (len < buf.len) buf[len] = b[0];
        len += 1;
    }
    if (!got_any) return null;
    if (len > buf.len) return buf[0..0];
    return std.mem.trimEnd(u8, buf[0..len], "\r");
}

/// `tars-config passwd`(HP-M2 plan 확정 7). 사용자의 sudo 비밀번호를 바꾼다. root만 한다 —
/// 사용자는 `sudo tars-config passwd`로 오고, sudo가 방금 옛 비밀번호를 확인했으므로 다시 묻지
/// 않는다. 새 값을 두 번 받아 `mkpasswd -m yescrypt -s`(설치기와 같은 도구)로 해시하고,
/// `/config/shadow`(영속)와 `/etc/shadow`(지금 부팅의 사본)를 함께 바꾼다 — 그래서 재부팅 없이 다음
/// `sudo`부터 새 값이다. `/etc/shadow`는 init과 같은 `account.shadowFile`로 짓는다.
pub fn passwd() u8 {
    if (!needRoot()) return cli.EXIT_DENIED;
    if (!needDisk()) return cli.EXIT_IO;
    const c = tarsConf();
    const user = c.user orelse {
        complain("no user account on this machine (tars.conf has no user=)", .{});
        return cli.EXIT_IO;
    };
    const name = user.slice();

    var first_buf: [account.PASSWORD_MAX]u8 = undefined;
    var again_buf: [account.PASSWORD_MAX]u8 = undefined;
    defer @memset(&first_buf, 0);
    defer @memset(&again_buf, 0);
    const first = readSecretLine("new password: ", &first_buf) orelse {
        complain("no password given; nothing was changed", .{});
        return cli.EXIT_REFUSED;
    };
    if (first.len == 0) {
        complain("an empty password is not taken; nothing was changed", .{});
        return cli.EXIT_REFUSED;
    }
    if (!account.validPassword(first)) {
        complain("the password is longer than {d} or has a control character; nothing was changed", .{account.PASSWORD_MAX});
        return cli.EXIT_REFUSED;
    }
    const again = readSecretLine("again: ", &again_buf) orelse {
        complain("the password was not given twice; nothing was changed", .{});
        return cli.EXIT_REFUSED;
    };
    if (!std.mem.eql(u8, first, again)) {
        complain("the two passwords differ; nothing was changed", .{});
        return cli.EXIT_REFUSED;
    }

    var input: [account.PASSWORD_MAX + 1]u8 = undefined;
    defer @memset(&input, 0);
    @memcpy(input[0..first.len], first);
    input[first.len] = '\n';
    const argv = [_:null]?[*:0]const u8{ MKPASSWD.ptr, "-m", "yescrypt", "-s" };
    var out: [512]u8 = undefined;
    const ran = run(&argv, input[0 .. first.len + 1], &out) orelse {
        complain("cannot run {s}", .{MKPASSWD});
        return cli.EXIT_IO;
    };
    const hash = (if (ran.code == 0) account.hashFromTool(ran.out) else null) orelse {
        complain("mkpasswd did not give a yescrypt hash (exit {d}); nothing was changed", .{ran.code});
        return cli.EXIT_IO;
    };

    var store_buf: [account.NAME_MAX + account.HASH_MAX + 4]u8 = undefined;
    const store = account.storeLine(&store_buf, name, hash) orelse {
        complain("the shadow line for {s} does not fit; nothing was changed", .{name});
        return cli.EXIT_IO;
    };
    var etc_buf: [2 * (account.NAME_MAX + account.HASH_MAX) + 64]u8 = undefined;
    const etc = account.shadowFile(&etc_buf, name, hash) orelse {
        complain("the shadow file for {s} does not fit; nothing was changed", .{name});
        return cli.EXIT_IO;
    };
    // 영속하는 쪽을 먼저 바꾼다. 둘째가 실패해도 재부팅이 init의 사본을 맞춘다.
    if (!replace(SHADOW_STORE, SHADOW_STORE_TEMP, store, 0o600)) return cli.EXIT_IO;
    if (!replace(SHADOW_ETC, SHADOW_ETC_TEMP, etc, 0o600)) {
        complain("{s} is changed; sudo takes the new password after the next boot", .{SHADOW_STORE});
        return cli.EXIT_IO;
    }
    say("password changed for {s}; sudo asks for the new one from now on\n", .{name});
    return cli.EXIT_OK;
}
