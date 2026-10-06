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
const fe = @import("config_front_edit.zig");

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
const FIREWALL_RULES: [:0]const u8 = "/etc/tars/firewall.nft";

const ENVP = [_:null]?[*:0]const u8{"PATH=/usr/bin:/bin"};

const BUF = 16384;

// ── 바탕 ──────────────────────────────────────────────────────────────

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
            complain("cannot read {s} (errno {d})", .{ std.mem.span(path), @intFromEnum(e) });
            return null;
        },
    };
}

/// temp에 쓰고 path로 갈아 끼운다(결정 5와 같은 까닭). mode는 새 파일의 것이다.
fn replace(path: [:0]const u8, temp: [:0]const u8, text: []const u8, mode: linux.mode_t) bool {
    const rc = linux.open(temp.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, mode);
    if (failed(rc)) |e| {
        complain("cannot create {s} (errno {d})", .{ temp, @intFromEnum(e) });
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
        complain("cannot rename {s} to {s} (errno {d})", .{ temp, path, @intFromEnum(e) });
        return false;
    }
    return true;
}

fn ensureDir(path: [:0]const u8, mode: linux.mode_t) bool {
    if (failed(linux.mkdir(path.ptr, mode))) |e| {
        if (e == .EXIST) return true;
        complain("cannot make {s} (errno {d})", .{ path, @intFromEnum(e) });
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
    while (failed(linux.wait4(@intCast(pid), &status, 0, null))) |e| {
        if (e != .INTR) return null;
    }
    const code: u8 = if (linux.W.IFEXITED(status)) linux.W.EXITSTATUS(status) else 128 +| @as(u8, @truncate(@intFromEnum(linux.W.TERMSIG(status))));
    return .{ .code = code, .out = out[0..len] };
}

/// 비밀 하나를 읽는다 — 비밀번호 · API 키. 표준 입력이 tty면 prompt를 찍고 echo를 끈 채
/// 한 줄을, 아니면(파이프 · 파일) 끝까지 읽는다. 끝의 개행은 뗀다. 명령줄 인자로 받지 않는
/// 이유는 `/proc/<pid>/cmdline`과 셸 히스토리다(VD design 결정 4와 같다).
fn readSecret(prompt: []const u8, buf: []u8) ?[]const u8 {
    var old: linux.termios = undefined;
    const tty = failed(linux.tcgetattr(0, &old)) == null;
    if (tty) {
        _ = cli.writeAll(2, prompt);
        var quiet = old;
        quiet.lflag.ECHO = false;
        _ = linux.tcsetattr(0, .FLUSH, &quiet);
    }
    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(0, buf[len..].ptr, buf.len - len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            break;
        }
        if (n == 0) break;
        len += n;
        if (tty and buf[len - 1] == '\n') break;
    }
    if (tty) {
        _ = linux.tcsetattr(0, .FLUSH, &old);
        _ = cli.writeAll(2, "\n");
    }
    if (len == buf.len) return null;
    return std.mem.trimEnd(u8, buf[0..len], "\r\n");
}

// ── wifi ──────────────────────────────────────────────────────────────

/// `tars-config wifi SSID [--country CC]` (결정 12).
pub fn wifi(args: []const [*:0]const u8) u8 {
    if (args.len == 0) return wifiStatus();
    const ssid = std.mem.span(args[0]);
    var country: ?[]const u8 = null;
    if (args.len == 3 and std.mem.eql(u8, std.mem.span(args[1]), "--country")) {
        country = std.mem.span(args[2]);
        if (!fe.countryOk(country.?)) {
            complain("--country takes two capital letters, like KR", .{});
            return cli.EXIT_USAGE;
        }
    } else if (args.len != 1) return cli.usage();
    if (ssid.len == 0 or ssid.len > 32 or fe.hasControl(ssid)) {
        complain("an SSID is 1 to 32 bytes without control characters", .{});
        return cli.EXIT_USAGE;
    }
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

    say("wifi: {s} {s} in {s}{s}\n", .{
        ssid,
        if (placed.replaced) "replaced" else "added",
        WPA_PATH,
        if (country != null) " (with country)" else "",
    });
    const c = tarsConf();
    if (c.net == .off) say("net=off: wifi needs the network on — tars-config set net=dhcp\n", .{});
    if (existed) {
        say("apply now: tars-service restart wpa_supplicant\n", .{});
    } else {
        say("init starts wpa_supplicant only when this file is there at boot; reboot (kill -INT 1)\n", .{});
    }
    return cli.EXIT_OK;
}

fn wifiStatus() u8 {
    var conf_buf: [BUF]u8 = undefined;
    const conf = readOr(WPA_PATH, &conf_buf) orelse return cli.EXIT_IO;
    if (conf.len == 0) {
        say("no {s}: wifi is off. tars-config wifi SSID adds a network\n", .{WPA_PATH});
        return cli.EXIT_OK;
    }
    // 망의 이름만 보인다. psk 줄은 안 찍는다.
    var it = std.mem.splitScalar(u8, conf, '\n');
    while (it.next()) |raw| {
        const t = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.startsWith(u8, t, "ssid=") or std.mem.startsWith(u8, t, "country=")) say("{s}\n", .{t});
    }
    return cli.EXIT_OK;
}

fn fileExists(path: [:0]const u8) bool {
    return failed(linux.access(path.ptr, linux.F_OK)) == null;
}

// ── ssh ───────────────────────────────────────────────────────────────

/// 링크가 템플릿을 가리키는가. 사람이 다른 sshd 스크립트를 그 이름으로 두었으면 거짓이다.
fn sshdLinked() enum { none, template, other } {
    var buf: [256]u8 = undefined;
    const rc = linux.readlink(SSHD_LINK.ptr, &buf, buf.len);
    if (failed(rc)) |e| return if (e == .NOENT) .none else .other;
    return if (std.mem.eql(u8, buf[0..rc], SSHD_TEMPLATE)) .template else .other;
}

/// `tars-config ssh [on|off]` (결정 13).
pub fn ssh(args: []const [*:0]const u8) u8 {
    if (args.len > 1) return cli.usage();
    if (args.len == 0) {
        var keys_buf: [BUF]u8 = undefined;
        const keys = readOr(KEYS_PATH, &keys_buf) orelse return cli.EXIT_IO;
        say("sshd: {s}\n", .{switch (sshdLinked()) {
            .template => "on (/config/services.d/sshd -> /etc/tars/services/sshd)",
            .other => "/config/services.d/sshd is yours, not the template",
            .none => "off",
        }});
        say("keys: {d} in {s}\n", .{ fe.keyCount(keys), KEYS_PATH });
        sayFirewall22();
        return cli.EXIT_OK;
    }
    const verb = std.mem.span(args[0]);
    if (!needDisk()) return cli.EXIT_IO;
    if (std.mem.eql(u8, verb, "on")) {
        switch (sshdLinked()) {
            .template => say("sshd: already on\n", .{}),
            .other => {
                complain("{s} is there and is not a link to {s}; leaving it", .{ SSHD_LINK, SSHD_TEMPLATE });
                return cli.EXIT_REFUSED;
            },
            .none => {
                if (!ensureDir(SERVICES_DIR, 0o755)) return cli.EXIT_IO;
                if (failed(linux.symlink(SSHD_TEMPLATE.ptr, SSHD_LINK.ptr))) |e| {
                    complain("cannot link {s} (errno {d})", .{ SSHD_LINK, @intFromEnum(e) });
                    return cli.EXIT_IO;
                }
                say("sshd: on — {s} -> {s}; init starts it at the next boot (kill -INT 1)\n", .{ SSHD_LINK, SSHD_TEMPLATE });
            },
        }
        var keys_buf: [BUF]u8 = undefined;
        const keys = readOr(KEYS_PATH, &keys_buf) orelse return cli.EXIT_IO;
        if (fe.keyCount(keys) == 0) say("no key yet: tars-config ssh-key add 'ssh-ed25519 AAAA… you@host'\n", .{});
        sayFirewall22();
        return cli.EXIT_OK;
    }
    if (std.mem.eql(u8, verb, "off")) {
        switch (sshdLinked()) {
            .none => say("sshd: already off\n", .{}),
            .other => {
                complain("{s} is not a link to {s}; leaving it", .{ SSHD_LINK, SSHD_TEMPLATE });
                return cli.EXIT_REFUSED;
            },
            .template => {
                if (failed(linux.unlink(SSHD_LINK.ptr))) |e| {
                    complain("cannot remove {s} (errno {d})", .{ SSHD_LINK, @intFromEnum(e) });
                    return cli.EXIT_IO;
                }
                say("sshd: off from the next boot; to stop it now: tars-service stop sshd\n", .{});
            },
        }
        return cli.EXIT_OK;
    }
    return cli.usage();
}

/// firewall=on이면 22를 이 명령이 열었는지 말한다. 사람의 nft 파일은 안 읽는다(결정 10) —
/// 열려 있을 수도 있다고만 말한다.
fn sayFirewall22() void {
    if (tarsConf().firewall != .on) return;
    var buf: [BUF]u8 = undefined;
    const text = readOr(NFT_PATH, &buf) orelse return;
    if (fe.hasLine(text, "tcp dport 22 accept")) {
        say("firewall=on: tars-config opened port 22\n", .{});
    } else {
        say("firewall=on: port 22 is open only if a file in {s} says so; tars-config firewall allow 22\n", .{NFT_DIR});
    }
}

/// `tars-config ssh-key add [KEY] | list` (결정 13).
pub fn sshKey(args: []const [*:0]const u8) u8 {
    if (args.len == 0) return cli.usage();
    const verb = std.mem.span(args[0]);
    if (std.mem.eql(u8, verb, "list")) {
        if (args.len != 1) return cli.usage();
        if (!fileExists(KEYS_PATH)) {
            say("no {s}\n", .{KEYS_PATH});
            return cli.EXIT_OK;
        }
        const argv = [_:null]?[*:0]const u8{ SSH_KEYGEN, "-l", "-f", KEYS_PATH };
        var out: [BUF]u8 = undefined;
        const ran = run(&argv, "", &out) orelse return cli.EXIT_IO;
        _ = cli.writeAll(1, ran.out);
        return if (ran.code == 0) cli.EXIT_OK else cli.EXIT_REFUSED;
    }
    if (!std.mem.eql(u8, verb, "add") or args.len > 2) return cli.usage();
    if (!needDisk()) return cli.EXIT_IO;

    // 키 한 줄 — 인자 하나(따옴표로 싼 줄)이거나 표준 입력(`< id_ed25519.pub`).
    var in_buf: [8192]u8 = undefined;
    const raw: []const u8 = if (args.len == 2) std.mem.span(args[1]) else (readSecret("public key: ", &in_buf) orelse {
        complain("the key is too long", .{});
        return cli.EXIT_REFUSED;
    });
    const line = std.mem.trim(u8, raw, " \t\r\n");
    if (line.len == 0 or std.mem.indexOfScalar(u8, line, '\n') != null or fe.hasControl(line)) {
        complain("give one public key line, like 'ssh-ed25519 AAAA… you@host'", .{});
        return cli.EXIT_USAGE;
    }
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
    if (sshdLinked() == .none) say("sshd is off: tars-config ssh on, then reboot\n", .{});
    sayFirewall22();
    return cli.EXIT_OK;
}

// ── firewall ──────────────────────────────────────────────────────────

/// `tars-config firewall [allow|deny PORT[/udp]]` (결정 14).
pub fn firewall(args: []const [*:0]const u8) u8 {
    const c = tarsConf();
    var buf: [BUF]u8 = undefined;
    const text = readOr(NFT_PATH, &buf) orelse return cli.EXIT_IO;
    if (args.len == 0) {
        say("firewall={s}\n", .{@tagName(c.firewall)});
        var it = std.mem.splitScalar(u8, text, '\n');
        var n: usize = 0;
        while (it.next()) |raw| {
            const t = std.mem.trim(u8, raw, " \t\r");
            if (t.len == 0 or t[0] == '#') continue;
            say("{s}\n", .{t});
            n += 1;
        }
        if (n == 0) say("tars-config opened no port ({s} has no rule)\n", .{NFT_PATH});
        say("rules you wrote yourself live in other files under {s}; nft list ruleset shows what is up\n", .{NFT_DIR});
        return cli.EXIT_OK;
    }
    if (args.len != 2) return cli.usage();
    const verb = std.mem.span(args[0]);
    const allow = std.mem.eql(u8, verb, "allow");
    if (!allow and !std.mem.eql(u8, verb, "deny")) return cli.usage();
    const spec = fe.parsePort(std.mem.span(args[1])) orelse {
        complain("a port is 1 to 65535, optionally /tcp or /udp (tcp is the default)", .{});
        return cli.EXIT_USAGE;
    };
    if (!needDisk()) return cli.EXIT_IO;
    var rule_buf: [32]u8 = undefined;
    const rule = fe.ruleLine(&rule_buf, spec);

    var new_buf: [BUF + 64]u8 = undefined;
    const base = if (text.len == 0) fe.RULES_HEADER else text;
    const changed: ?[]const u8 = if (allow)
        (if (fe.hasLine(base, rule)) null else fe.appendLine(&new_buf, base, rule) orelse return cli.EXIT_REFUSED)
    else
        (if (!fe.hasLine(text, rule)) null else fe.removeLine(&new_buf, text, rule) orelse return cli.EXIT_REFUSED);
    if (changed) |t| {
        if (!ensureDir(NFT_DIR, 0o755)) return cli.EXIT_IO;
        if (!replace(NFT_PATH, NFT_TEMP, t, 0o644)) return cli.EXIT_IO;
        say("firewall: {s} {s}\n", .{ if (allow) "opened" else "closed", rule });
    } else {
        say("firewall: {s} was {s}\n", .{ rule, if (allow) "already open here" else "not opened by tars-config" });
        if (!allow) say("rules you wrote yourself live in other files under {s}; this command does not touch them\n", .{NFT_DIR});
        return cli.EXIT_OK;
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
    if (args.len == 0) {
        say("key: {s}\n", .{if (fileExists(KEY_PATH)) "/config/groq.key is there (not shown)" else "none — tars-config dictation key"});
        var buf: [BUF]u8 = undefined;
        const text = readOr(DICT_PATH, &buf) orelse return cli.EXIT_IO;
        if (text.len == 0) say("no {s}: tars-dictate uses its defaults (tars-dictate -h)\n", .{DICT_PATH}) else _ = cli.writeAll(1, text);
        return cli.EXIT_OK;
    }
    const verb = std.mem.span(args[0]);
    if (std.mem.eql(u8, verb, "key")) {
        if (args.len > 2) return cli.usage();
        if (!needDisk()) return cli.EXIT_IO;
        var in_buf: [512]u8 = undefined;
        const raw: []const u8 = if (args.len == 2) std.mem.span(args[1]) else (readSecret("Groq API key: ", &in_buf) orelse {
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
    }
    if (!std.mem.eql(u8, verb, "set") or args.len < 2) return cli.usage();
    if (!needDisk()) return cli.EXIT_IO;
    // 이름만 거른다. 값은 tars-dictate가 실행마다 읽고 틀리면 경고한다(결정 15).
    for (args[1..]) |a| {
        const arg = std.mem.span(a);
        const eq = std.mem.indexOfScalar(u8, arg, '=') orelse {
            complain("'{s}' has no '='; set takes KEY=VALUE", .{arg});
            return cli.EXIT_USAGE;
        };
        const key = std.mem.trim(u8, arg[0..eq], " \t");
        if (!fe.isDictationKey(key)) {
            complain("unknown dictation key '{s}'; the keys are in tars-dictate -h", .{key});
            complain("nothing was written", .{});
            return cli.EXIT_REFUSED;
        }
        if (fe.hasControl(arg)) {
            complain("{s}: a control character cannot go into a config line", .{key});
            return cli.EXIT_REFUSED;
        }
    }
    var buf: [BUF]u8 = undefined;
    var text = readOr(DICT_PATH, &buf) orelse return cli.EXIT_IO;
    var work: [2][BUF]u8 = undefined;
    // 같은 문법(`#` 주석 · 첫 `=` · 양쪽 공백)이라 tars.conf의 줄 바꾸기를 그대로 쓴다.
    const edit = @import("config_edit.zig");
    for (args[1..], 0..) |a, i| {
        const arg = std.mem.span(a);
        const eq = std.mem.indexOfScalar(u8, arg, '=').?;
        const key = std.mem.trim(u8, arg[0..eq], " \t");
        const value = std.mem.trim(u8, arg[eq + 1 ..], " \t");
        text = edit.setLine(&work[i % 2], text, key, value) orelse {
            complain("{s} would grow past {d} bytes", .{ DICT_PATH, BUF });
            return cli.EXIT_REFUSED;
        };
        say("dictation: {s}={s}\n", .{ key, value });
    }
    if (!replace(DICT_PATH, DICT_TEMP, text, 0o644)) return cli.EXIT_IO;
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
    var it = std.mem.splitScalar(u8, dict, '\n');
    var number: usize = 0;
    while (it.next()) |raw| {
        number += 1;
        const t = std.mem.trim(u8, raw, " \t\r");
        if (t.len == 0 or t[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, t, '=') orelse continue;
        const key = std.mem.trim(u8, t[0..eq], " \t");
        if (!fe.isDictationKey(key)) {
            say("{s} line {d}: tars-dictate does not know the key '{s}'\n", .{ DICT_PATH, number, key });
            problems += 1;
        }
    }
    return problems;
}
