//! 링크 칸의 순수한 층(LK-M0). 설계는 `docs/specs/2026-11-14-tars-link-status-design.md`의
//! 결정 2 · 3 · 4 · 7 · 8이다.
//!
//! netlink 메시지의 바이트를 받아 값을 돌려주고, 보낼 요청의 바이트를 짓는다. 소켓을 열고
//! 보내고 받는 일과 로그는 LK-M1이 `main.zig`의 링크 절에 둔다 — `battery.zig`와 `main.zig`의
//! 경계와 같은 자리다. 그래서 `link_test`가 부팅 없이 경계값을 전부 본다.
//!
//! 게스트에서 도는 파일이지만 아무것도 안 찍는다(루트 `check.sh`의 `require_no_debug_print`).
//!
//! 바이트 순서는 호스트 순서다. netlink는 커널과 같은 기계 안의 통신이라 그렇다 — 게스트(x86_64)와
//! 호스트 검사를 도는 맥(arm64)이 둘 다 little이라 검사의 바이트도 그대로 맞는다.

const std = @import("std");
const native = @import("builtin").cpu.arch.endian();

// ── 상수 ─────────────────────────────────────────────────────────────
// 값은 uapi 헤더를 `zig cc -target x86_64-linux-gnu`로 컴파일해 뽑았다(design 확인 5).

pub const NLMSG_HDRLEN = 16;
pub const NLMSG_ERROR: u16 = 2;
pub const NLMSG_DONE: u16 = 3;
pub const NLM_F_REQUEST: u16 = 1;
pub const NLM_F_DUMP: u16 = 0x300;

pub const RTM_NEWLINK: u16 = 16;
pub const RTM_DELLINK: u16 = 17;
pub const RTM_GETLINK: u16 = 18;
pub const RTM_NEWADDR: u16 = 20;
pub const RTM_DELADDR: u16 = 21;
pub const RTM_GETADDR: u16 = 22;
/// bind의 `groups` 비트. 링크와 IPv4 주소의 변화를 받는다(design 결정 8의 1).
pub const RTMGRP_LINK: u32 = 1;
pub const RTMGRP_IPV4_IFADDR: u32 = 16;

const AF_INET: u8 = 2;
pub const ARPHRD_ETHER: u16 = 1;
const IFINFOMSG_LEN = 16;
const IFADDRMSG_LEN = 8;
const IFLA_IFNAME: u16 = 3;
const IFLA_OPERSTATE: u16 = 16;
const IFLA_LINKINFO: u16 = 18;
const IFLA_INFO_KIND: u16 = 1;
const IF_OPER_UP: u8 = 6;
const IFA_ADDRESS: u16 = 1;
const IFA_LOCAL: u16 = 2;

pub const GENL_ID_CTRL: u16 = 16;
const GENLMSGHDR_LEN = 4;
const CTRL_CMD_GETFAMILY: u8 = 3;
const CTRL_ATTR_FAMILY_ID: u16 = 1;
const CTRL_ATTR_FAMILY_NAME: u16 = 2;
const NL80211_CMD_GET_INTERFACE: u8 = 5;
const NL80211_ATTR_IFINDEX: u16 = 3;
const NL80211_ATTR_IFTYPE: u16 = 5;
const NL80211_ATTR_SSID: u16 = 52;
const NL80211_CMD_GET_SCAN: u8 = 32;
pub const NL80211_CMD_NEW_SCAN_RESULTS: u8 = 34;
const NL80211_ATTR_BSS: u16 = 47;
const NL80211_BSS_INFORMATION_ELEMENTS: u16 = 6;
const NL80211_BSS_STATUS: u16 = 9;
const NL80211_BSS_BEACON_IES: u16 = 11;
const NL80211_BSS_STATUS_ASSOCIATED: u32 = 1;
/// 802.11 정보 요소의 SSID id.
const WLAN_EID_SSID: u8 = 0;
const NL80211_IFTYPE_STATION: u32 = 2;
const NL80211_IFTYPE_P2P_CLIENT: u32 = 8;

/// attribute 타입의 아래 14비트. 위 두 비트는 `NLA_F_NESTED` · `NLA_F_NET_BYTEORDER`다.
const NLA_TYPE_MASK: u16 = 0x3FFF;

/// SSID의 최대 바이트(IEEE 802.11).
pub const SSID_MAX = 32;
/// 인터페이스 이름의 최대 바이트(`IFNAMSIZ` 16에서 NUL을 뺀 것).
pub const NAME_MAX = 15;
/// 요청 메시지 하나의 최대 바이트. 가장 긴 것이 GETFAMILY의 32바이트다.
pub const REQUEST_MAX = 32;

// ── 순회 ─────────────────────────────────────────────────────────────

fn align4(n: usize) usize {
    return (n + 3) & ~@as(usize, 3);
}

fn readU16(b: []const u8) u16 {
    return std.mem.readInt(u16, b[0..2], native);
}

fn readU32(b: []const u8) u32 {
    return std.mem.readInt(u32, b[0..4], native);
}

/// netlink 메시지 하나. `payload`는 머리 16바이트 뒤부터 `nlmsg_len`까지다.
pub const Msg = struct {
    kind: u16,
    flags: u16,
    seq: u32,
    payload: []const u8,
};

/// `recv` 한 번이 받은 바이트 안의 메시지들. 길이가 머리보다 작거나 남은 바이트보다 크면
/// 거기서 멈춘다 — 잘린 메시지를 읽지 않는다.
pub const MsgIter = struct {
    buf: []const u8,
    pos: usize = 0,

    pub fn next(self: *MsgIter) ?Msg {
        const rest = self.buf.len - @min(self.pos, self.buf.len);
        if (rest < NLMSG_HDRLEN) return null;
        const h = self.buf[self.pos..];
        const len = readU32(h);
        if (len < NLMSG_HDRLEN or len > rest) return null;
        self.pos += align4(len);
        return .{
            .kind = readU16(h[4..]),
            .flags = readU16(h[6..]),
            .seq = readU32(h[8..]),
            .payload = h[NLMSG_HDRLEN..len],
        };
    }
};

/// attribute 하나(`rtattr` · `nlattr`는 같은 모양이다). `kind`는 아래 14비트다.
pub const Attr = struct {
    kind: u16,
    data: []const u8,
};

/// attribute의 나열. 머리 4바이트보다 짧거나 남은 바이트를 넘는 것에서 멈춘다.
pub const AttrIter = struct {
    buf: []const u8,
    pos: usize = 0,

    pub fn next(self: *AttrIter) ?Attr {
        const rest = self.buf.len - @min(self.pos, self.buf.len);
        if (rest < 4) return null;
        const h = self.buf[self.pos..];
        const len = readU16(h);
        if (len < 4 or len > rest) return null;
        self.pos += align4(len);
        return .{ .kind = readU16(h[2..]) & NLA_TYPE_MASK, .data = h[4..len] };
    }
};

// ── 응답 읽기 ─────────────────────────────────────────────────────────

/// `RTM_NEWLINK` · `RTM_DELLINK` 하나에서 쓰는 것.
pub const LinkMsg = struct {
    index: u32,
    /// `ifi_type`(ARPHRD_*).
    arphrd: u16,
    name: []const u8,
    /// `IFLA_OPERSTATE`가 `IF_OPER_UP`이다(design 결정 2). attribute가 없으면 false.
    up: bool,
    /// `IFLA_LINKINFO` 안에 `IFLA_INFO_KIND`가 있다 — veth · bridge · tun · dummy(design 결정 3의 2).
    /// slave 정보(`IFLA_INFO_SLAVE_KIND`)만 있는 실NIC은 false다(design 확인 4).
    virtual: bool,
};

pub fn parseLink(payload: []const u8) ?LinkMsg {
    if (payload.len < IFINFOMSG_LEN) return null;
    const index = std.mem.readInt(i32, payload[4..8], native);
    if (index <= 0) return null;
    var out: LinkMsg = .{
        .index = @intCast(index),
        .arphrd = readU16(payload[2..]),
        .name = "",
        .up = false,
        .virtual = false,
    };
    var it: AttrIter = .{ .buf = payload[IFINFOMSG_LEN..] };
    while (it.next()) |a| switch (a.kind) {
        // 커널은 NUL을 붙여 보낸다. 첫 NUL 앞까지가 이름이다.
        IFLA_IFNAME => out.name = a.data[0 .. std.mem.indexOfScalar(u8, a.data, 0) orelse a.data.len],
        IFLA_OPERSTATE => out.up = a.data.len >= 1 and a.data[0] == IF_OPER_UP,
        IFLA_LINKINFO => {
            var inner: AttrIter = .{ .buf = a.data };
            while (inner.next()) |b| {
                if (b.kind == IFLA_INFO_KIND) out.virtual = true;
            }
        },
        else => {},
    };
    return out;
}

/// `RTM_NEWADDR` · `RTM_DELADDR`의 IPv4 주소 하나.
pub const AddrMsg = struct {
    index: u32,
    addr: [4]u8,
};

/// AF_INET이 아니거나 주소 attribute가 없으면 null이다. `IFA_LOCAL`을 먼저 본다 — point-to-point에서는
/// `IFA_ADDRESS`가 상대편 주소이고, 그 밖에서는 둘이 같다.
pub fn parseAddr(payload: []const u8) ?AddrMsg {
    if (payload.len < IFADDRMSG_LEN) return null;
    if (payload[0] != AF_INET) return null;
    const index = readU32(payload[4..]);
    var local: ?[4]u8 = null;
    var address: ?[4]u8 = null;
    var it: AttrIter = .{ .buf = payload[IFADDRMSG_LEN..] };
    while (it.next()) |a| {
        if (a.data.len != 4) continue;
        if (a.kind == IFA_LOCAL) local = a.data[0..4].*;
        if (a.kind == IFA_ADDRESS) address = a.data[0..4].*;
    }
    const addr = local orelse address orelse return null;
    return .{ .index = index, .addr = addr };
}

/// nl80211 `GET_INTERFACE` 응답에서 쓰는 것.
pub const WifiMsg = struct {
    index: u32,
    iftype: u32,
    /// attribute가 없으면 null이다 — 붙지 않았거나 드라이버가 모른다(design 확인 3).
    ssid: ?[]const u8,
};

pub fn parseInterface(payload: []const u8) ?WifiMsg {
    if (payload.len < GENLMSGHDR_LEN) return null;
    var index: ?u32 = null;
    var iftype: ?u32 = null;
    var ssid: ?[]const u8 = null;
    var it: AttrIter = .{ .buf = payload[GENLMSGHDR_LEN..] };
    while (it.next()) |a| switch (a.kind) {
        NL80211_ATTR_IFINDEX => if (a.data.len == 4) {
            index = readU32(a.data);
        },
        NL80211_ATTR_IFTYPE => if (a.data.len == 4) {
            iftype = readU32(a.data);
        },
        NL80211_ATTR_SSID => ssid = a.data,
        else => {},
    };
    return .{ .index = index orelse return null, .iftype = iftype orelse return null, .ssid = ssid };
}

/// `NL80211_CMD_GET_SCAN` dump의 BSS 하나에서 쓰는 것(LK-M1 결과 3).
pub const ScanBss = struct {
    /// `NL80211_BSS_STATUS`가 ASSOCIATED다 — 이 인터페이스가 지금 붙어 있는 BSS.
    associated: bool,
    /// 정보 요소의 SSID. probe 응답의 요소를 먼저, 없으면 beacon의 요소를 본다. 길이 0(숨긴 망)이면 null.
    ssid: ?[]const u8,
};

/// `NEW_SCAN_RESULTS` 메시지의 payload(genl 머리 포함) → BSS 하나. `NL80211_ATTR_BSS`가 없으면 null이다.
pub fn parseScanBss(payload: []const u8) ?ScanBss {
    if (payload.len < GENLMSGHDR_LEN) return null;
    var it: AttrIter = .{ .buf = payload[GENLMSGHDR_LEN..] };
    while (it.next()) |a| {
        if (a.kind != NL80211_ATTR_BSS) continue;
        var out: ScanBss = .{ .associated = false, .ssid = null };
        var ies: ?[]const u8 = null;
        var beacon: ?[]const u8 = null;
        var inner: AttrIter = .{ .buf = a.data };
        while (inner.next()) |b| switch (b.kind) {
            NL80211_BSS_STATUS => out.associated = b.data.len == 4 and readU32(b.data) == NL80211_BSS_STATUS_ASSOCIATED,
            NL80211_BSS_INFORMATION_ELEMENTS => ies = b.data,
            NL80211_BSS_BEACON_IES => beacon = b.data,
            else => {},
        };
        out.ssid = if (ies) |x| ieSsid(x) else null;
        if (out.ssid == null) {
            if (beacon) |x| out.ssid = ieSsid(x);
        }
        return out;
    }
    return null;
}

/// 정보 요소의 나열(id 1바이트 · 길이 1바이트 · 내용)에서 SSID 요소의 내용. 잘린 요소에서 멈춘다.
pub fn ieSsid(ies: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i + 2 <= ies.len) {
        const id = ies[i];
        const len = ies[i + 1];
        if (i + 2 + len > ies.len) return null;
        if (id == WLAN_EID_SSID) return if (len == 0) null else ies[i + 2 ..][0..len];
        i += 2 + len;
    }
    return null;
}

/// ctrl `GETFAMILY` 응답의 family id.
pub fn parseFamilyId(payload: []const u8) ?u16 {
    if (payload.len < GENLMSGHDR_LEN) return null;
    var it: AttrIter = .{ .buf = payload[GENLMSGHDR_LEN..] };
    while (it.next()) |a| {
        if (a.kind == CTRL_ATTR_FAMILY_ID and a.data.len >= 2) return readU16(a.data);
    }
    return null;
}

/// `NLMSG_ERROR`의 `error` 칸. 0은 ack, 음수는 `-errno`다.
pub fn parseError(payload: []const u8) ?i32 {
    if (payload.len < 4) return null;
    return std.mem.readInt(i32, payload[0..4], native);
}

// ── 요청 짓기 ─────────────────────────────────────────────────────────

fn putHeader(buf: []u8, len: usize, kind: u16, flags: u16, seq: u32) void {
    @memset(buf[0..len], 0);
    std.mem.writeInt(u32, buf[0..4], @intCast(len), native);
    std.mem.writeInt(u16, buf[4..6], kind, native);
    std.mem.writeInt(u16, buf[6..8], flags, native);
    std.mem.writeInt(u32, buf[8..12], seq, native);
    // nlmsg_pid는 0이다 — 커널에 보내는 메시지.
}

fn putAttrHeader(buf: []u8, len: u16, kind: u16) void {
    std.mem.writeInt(u16, buf[0..2], len, native);
    std.mem.writeInt(u16, buf[2..4], kind, native);
}

/// `RTM_GETLINK` · `RTM_GETADDR` dump 요청(plan 확정 3). GETLINK은 `ifinfomsg`(family 0, 모두),
/// GETADDR는 `ifaddrmsg`(family AF_INET)를 붙인다.
pub fn buildDump(buf: *[REQUEST_MAX]u8, kind: u16, seq: u32) []const u8 {
    const body: usize = if (kind == RTM_GETADDR) IFADDRMSG_LEN else IFINFOMSG_LEN;
    const len = NLMSG_HDRLEN + body;
    putHeader(buf, len, kind, NLM_F_REQUEST | NLM_F_DUMP, seq);
    if (kind == RTM_GETADDR) buf[NLMSG_HDRLEN] = AF_INET;
    return buf[0..len];
}

/// ctrl `GETFAMILY "nl80211"`(plan 확정 4). 32바이트다.
pub fn buildGetFamily(buf: *[REQUEST_MAX]u8, seq: u32) []const u8 {
    const name = "nl80211\x00";
    const len = NLMSG_HDRLEN + GENLMSGHDR_LEN + 4 + name.len;
    putHeader(buf, len, GENL_ID_CTRL, NLM_F_REQUEST, seq);
    buf[16] = CTRL_CMD_GETFAMILY;
    buf[17] = 1; // genl version
    putAttrHeader(buf[20..], 4 + name.len, CTRL_ATTR_FAMILY_NAME);
    @memcpy(buf[24..][0..name.len], name);
    return buf[0..len];
}

/// nl80211 `GET_INTERFACE`, ifindex 하나(plan 확정 4). 28바이트다.
pub fn buildGetInterface(buf: *[REQUEST_MAX]u8, family: u16, seq: u32, index: u32) []const u8 {
    const len = NLMSG_HDRLEN + GENLMSGHDR_LEN + 8;
    putHeader(buf, len, family, NLM_F_REQUEST, seq);
    buf[16] = NL80211_CMD_GET_INTERFACE;
    putAttrHeader(buf[20..], 8, NL80211_ATTR_IFINDEX);
    std.mem.writeInt(u32, buf[24..28], index, native);
    return buf[0..len];
}

/// nl80211 `GET_SCAN` dump, ifindex 하나(LK-M1 결과 3). `GET_INTERFACE`와 같은 28바이트이고 명령과
/// `NLM_F_DUMP`만 다르다.
pub fn buildGetScan(buf: *[REQUEST_MAX]u8, family: u16, seq: u32, index: u32) []const u8 {
    const msg = buildGetInterface(buf, family, seq, index);
    std.mem.writeInt(u16, buf[6..8], NLM_F_REQUEST | NLM_F_DUMP, native);
    buf[16] = NL80211_CMD_GET_SCAN;
    return msg;
}

// ── SSID ─────────────────────────────────────────────────────────────

/// SSID 바이트 → 화면에 그려도 되는 UTF-8(design 결정 4, plan 확정 8). 33바이트째부터는 버린다.
/// 돌려주는 조각은 `out`의 앞부분이고 입력보다 길지 않다.
pub fn cleanSsid(raw: []const u8, out: *[SSID_MAX]u8) []const u8 {
    const src = raw[0..@min(raw.len, SSID_MAX)];
    var i: usize = 0;
    var n: usize = 0;
    while (i < src.len) {
        const b = src[i];
        if (b < 0x80) {
            out[n] = if (b >= 0x20 and b != 0x7F) b else '?';
            n += 1;
            i += 1;
            continue;
        }
        const keep: usize = blk: {
            const len = std.unicode.utf8ByteSequenceLength(b) catch break :blk 0;
            if (i + len > src.len) break :blk 0;
            const cp = std.unicode.utf8Decode(src[i..][0..len]) catch break :blk 0;
            if (cp >= 0x80 and cp <= 0x9F) break :blk 0;
            break :blk len;
        };
        if (keep == 0) {
            out[n] = '?';
            n += 1;
            i += 1;
        } else {
            @memcpy(out[n..][0..keep], src[i..][0..keep]);
            n += keep;
            i += keep;
        }
    }
    return out[0..n];
}

// ── 인터페이스 표 ─────────────────────────────────────────────────────

pub const IFACE_MAX = 8;
pub const ADDR_MAX = 4;

/// 인터페이스 하나가 칸에 대해 무엇인가(design 결정 3).
pub const Kind = enum {
    /// 후보인데 nl80211에 아직 안 물었다.
    unknown,
    wired,
    /// 무선이고 iftype이 STATION · P2P_CLIENT다.
    station,
    /// 무선이지만 station이 아니다(AP · monitor 등).
    wifi_other,
    /// ARPHRD_ETHER가 아니다.
    not_ether,
    /// `IFLA_INFO_KIND`가 있다.
    virtual,
};

pub const Iface = struct {
    index: u32,
    name: [NAME_MAX]u8 = @splat(0),
    name_len: u8 = 0,
    kind: Kind,
    up: bool = false,
    addrs: [ADDR_MAX][4]u8 = @splat(@splat(0)),
    n_addrs: u8 = 0,
    /// 정리한 SSID(`cleanSsid`). station이 아니거나 attribute가 없으면 `ssid_len`이 null이다.
    ssid: [SSID_MAX]u8 = @splat(0),
    ssid_len: ?u8 = null,

    pub fn nameText(self: *const Iface) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn ssidText(self: *const Iface) ?[]const u8 {
        const n = self.ssid_len orelse return null;
        return self.ssid[0..n];
    }
};

/// `applyLink`가 돌려주는 것. `main.zig`는 `ask`면 nl80211에 묻고 그 답을 `applyWifi`로 넣는다.
pub const LinkResult = struct {
    /// 표의 이 인터페이스에 대해 칸이나 로그가 볼 무언가가 바뀌었다.
    changed: bool,
    /// 처음 본 인터페이스다(`link> if` 줄을 찍을 때).
    new: bool,
    /// nl80211에 이 ifindex를 물어야 한다(plan 확정 6).
    ask: bool,
    /// 표가 차서 버렸다(plan 확정 5).
    full: bool,
};

pub const Table = struct {
    items: [IFACE_MAX]Iface = undefined,
    len: usize = 0,

    pub fn clear(self: *Table) void {
        self.len = 0;
    }

    pub fn find(self: *Table, index: u32) ?*Iface {
        for (self.items[0..self.len]) |*it| {
            if (it.index == index) return it;
        }
        return null;
    }

    /// `RTM_NEWLINK` 하나를 넣는다. 같은 사실을 두 번 넣어도 결과가 같다(design 결정 8의 2).
    pub fn applyLink(self: *Table, m: LinkMsg) LinkResult {
        var r: LinkResult = .{ .changed = false, .new = false, .ask = false, .full = false };
        const it = self.find(m.index) orelse blk: {
            if (self.len == IFACE_MAX) {
                r.full = true;
                return r;
            }
            const kind: Kind = if (m.arphrd != ARPHRD_ETHER) .not_ether else if (m.virtual) .virtual else .unknown;
            self.items[self.len] = .{ .index = m.index, .kind = kind };
            self.len += 1;
            r.new = true;
            r.changed = true;
            break :blk &self.items[self.len - 1];
        };
        const name = m.name[0..@min(m.name.len, NAME_MAX)];
        if (!std.mem.eql(u8, it.nameText(), name)) {
            it.name = @splat(0);
            @memcpy(it.name[0..name.len], name);
            it.name_len = @intCast(name.len);
            r.changed = true;
        }
        const rose = m.up and !it.up;
        if (m.up != it.up) {
            it.up = m.up;
            r.changed = true;
            // 내려가면 SSID를 잊는다. 다시 올라올 때 묻는다.
            if (!m.up) it.ssid_len = null;
        }
        r.ask = it.kind == .unknown or (rose and (it.kind == .station or it.kind == .wifi_other));
        return r;
    }

    /// `RTM_DELLINK`. 표에서 뺐으면 true다.
    pub fn removeLink(self: *Table, index: u32) bool {
        for (self.items[0..self.len], 0..) |*it, i| {
            if (it.index != index) continue;
            // 순서를 지킨다 — 칸은 ifindex로 고르지만 로그를 읽는 사람에게는 본 순서가 편하다.
            std.mem.copyForwards(Iface, self.items[i .. self.len - 1], self.items[i + 1 .. self.len]);
            self.len -= 1;
            return true;
        }
        return false;
    }

    /// `RTM_NEWADDR`(add) · `RTM_DELADDR`. 주소는 집합이다 — 같은 주소의 NEWADDR가 두 번 와도 하나다
    /// (design 결정 7). 모르는 인터페이스이거나 아무것도 안 바뀌었으면 false다.
    pub fn applyAddr(self: *Table, m: AddrMsg, add: bool) bool {
        const it = self.find(m.index) orelse return false;
        const have = it.addrs[0..it.n_addrs];
        for (have, 0..) |a, i| {
            if (!std.mem.eql(u8, &a, &m.addr)) continue;
            if (add) return false;
            it.addrs[i] = have[have.len - 1];
            it.n_addrs -= 1;
            return true;
        }
        if (!add or it.n_addrs == ADDR_MAX) return false;
        it.addrs[it.n_addrs] = m.addr;
        it.n_addrs += 1;
        return true;
    }

    /// nl80211의 답을 넣는다. `msg`가 null이면 에러가 왔다는 뜻이고 무선이 아니다 — 유선이다
    /// (design 결정 3의 3). 아직 `unknown`이 아닌 유선 · 가상에 대해 오면 무시한다.
    pub fn applyWifi(self: *Table, index: u32, msg: ?WifiMsg) bool {
        const it = self.find(index) orelse return false;
        switch (it.kind) {
            .unknown, .station, .wifi_other => {},
            .wired, .not_ether, .virtual => return false,
        }
        const old_kind = it.kind;
        const old_len = it.ssid_len;
        const old_ssid = it.ssid;
        const m = msg orelse {
            if (it.kind != .unknown) return false;
            it.kind = .wired;
            return true;
        };
        const station = m.iftype == NL80211_IFTYPE_STATION or m.iftype == NL80211_IFTYPE_P2P_CLIENT;
        it.kind = if (station) .station else .wifi_other;
        it.ssid = @splat(0);
        it.ssid_len = null;
        if (station) {
            if (m.ssid) |raw| it.ssid_len = @intCast(cleanSsid(raw, &it.ssid).len);
        }
        return it.kind != old_kind or !std.meta.eql(it.ssid_len, old_len) or !std.mem.eql(u8, &it.ssid, &old_ssid);
    }

    /// station이 올라왔는데 `GET_INTERFACE`가 SSID를 안 줬나 — 그러면 `GET_SCAN`으로 묻는다(LK-M1 결과 3).
    pub fn needsScan(self: *Table, index: u32) bool {
        const it = self.find(index) orelse return false;
        return it.kind == .station and it.up and it.ssid_len == null;
    }

    /// `GET_SCAN`의 associated BSS에서 읽은 SSID를 넣는다. station만 받는다.
    pub fn applySsid(self: *Table, index: u32, raw: []const u8) SsidResult {
        const it = self.find(index) orelse return .ignored;
        if (it.kind != .station) return .ignored;
        var buf: [SSID_MAX]u8 = @splat(0);
        const clean = cleanSsid(raw, &buf);
        if (it.ssid_len != null and it.ssid_len.? == clean.len and std.mem.eql(u8, &it.ssid, &buf)) return .same;
        it.ssid = buf;
        it.ssid_len = @intCast(clean.len);
        return .changed;
    }
};

pub const SsidResult = enum {
    /// SSID가 바뀌었다.
    changed,
    /// 같은 SSID였다.
    same,
    /// station이 아니거나 모르는 인터페이스다.
    ignored,
};

// ── 칸 ───────────────────────────────────────────────────────────────

/// 토막의 색 둘(design 결정 5). 색 상수는 LK-M1이 `main.zig`에 둔다.
pub const Class = enum {
    /// IPv4 주소가 있다.
    ready,
    /// 링크는 섰는데 주소가 없다.
    wait,
};

pub const WIRED_TEXT = "LAN";
/// SSID attribute가 없는 station(design 결정 4).
pub const NO_SSID_TEXT = "WLAN";
pub const GAP = "  ";
pub const CELL_MAX = WIRED_TEXT.len + GAP.len + SSID_MAX;

pub const Piece = struct {
    start: u8,
    len: u8,
    class: Class,
};

/// 칸 하나. slice를 안 담는다 — `StatusMemo`가 `std.meta.eql`로 비교하고, 값으로 복사된다
/// (plan 확정 7). 쓰지 않은 바이트는 0이다.
pub const Cell = struct {
    text: [CELL_MAX]u8 = @splat(0),
    len: u8 = 0,
    pieces: [2]?Piece = .{ null, null },

    pub fn bytes(self: *const Cell) []const u8 {
        return self.text[0..self.len];
    }

    pub fn pieceText(self: *const Cell, p: Piece) []const u8 {
        return self.text[p.start..][0..p.len];
    }

    fn push(self: *Cell, s: []const u8, class: Class) void {
        if (self.len > 0) {
            @memcpy(self.text[self.len..][0..GAP.len], GAP);
            self.len += GAP.len;
        }
        const p: Piece = .{ .start = self.len, .len = @intCast(s.len), .class = class };
        @memcpy(self.text[self.len..][0..s.len], s);
        self.len += @intCast(s.len);
        if (self.pieces[0] == null) self.pieces[0] = p else self.pieces[1] = p;
    }
};

/// 표 → 칸(design 결정 1 · 4). 붙은 것이 없으면 null이다.
pub fn cell(table: *const Table) ?Cell {
    var wired_up = false;
    var wired_ready = false;
    var station: ?*const Iface = null;
    for (table.items[0..table.len]) |*it| {
        if (!it.up) continue;
        switch (it.kind) {
            .wired => {
                wired_up = true;
                if (it.n_addrs > 0) wired_ready = true;
            },
            .station => if (station == null or it.index < station.?.index) {
                station = it;
            },
            else => {},
        }
    }
    if (!wired_up and station == null) return null;
    var out: Cell = .{};
    if (wired_up) out.push(WIRED_TEXT, if (wired_ready) .ready else .wait);
    if (station) |s| out.push(s.ssidText() orelse NO_SSID_TEXT, if (s.n_addrs > 0) .ready else .wait);
    return out;
}

/// `link> if` 줄의 `kind=` 글자(design 결정 9).
pub fn kindName(k: Kind) []const u8 {
    return switch (k) {
        .unknown => "unknown",
        .wired => "wired",
        .station => "wifi",
        .wifi_other => "ignored(wifi-not-station)",
        .not_ether => "ignored(not-ether)",
        .virtual => "ignored(virtual)",
    };
}
