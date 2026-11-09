//! 개발 도구 층 매니페스트의 변환기(MF design 결정 4). 사람이 고치는 devlayer/manifest.toml을 읽고 검사해
//! devlayer/build/manifest.tsv를 쓴다 — TSV를 읽는 쪽(devlayer/manifest.sh · harvest.sh · build.sh)은 그대로다.
//!
//!   zig run devlayer/manifest-gen.zig -- <in.toml> <out.tsv>    make dev-layers가 부른다
//!   zig test devlayer/manifest-gen.zig                          make quick이 부른다
//!
//! TOML 전부가 아니라 이 파일이 쓰는 부분집합만 읽는다: 주석, `[[tool]]`, `키 = "기본 문자열"`, `키 = 정수`,
//! `키 = [문자열, …]`(여러 줄 · 끝 쉼표 · 배열 안 주석). 그 밖의 문법은 줄 번호와 함께 거절한다 — 모르는 문법을
//! 말없이 다르게 읽는 것보다 멈추는 편이 낫다(TP-M2에서 탭이 공백으로 바뀐 줄이 말없이 빠졌던 것과 같은 이유).
//!
//! 문법 오류는 첫 하나에서 멈추고(그 뒤의 줄은 믿을 수 없다), 키 · 값의 검사는 다 모아 한 번에 찍는다.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Shape = enum { string, int, array };

pub const Value = union(Shape) {
    string: []const u8,
    int: u32,
    array: []const []const u8,
};

pub const Entry = struct { key: []const u8, value: Value, line: u32 };

pub const Tool = struct {
    line: u32,
    entries: std.ArrayList(Entry) = .empty,
};

pub const Diag = struct { line: u32, msg: []const u8 };

pub const Diags = struct {
    list: std.ArrayList(Diag) = .empty,

    fn add(d: *Diags, a: Allocator, line: u32, comptime fmt: []const u8, args: anytype) !void {
        try d.list.append(a, .{ .line = line, .msg = try std.fmt.allocPrint(a, fmt, args) });
    }
};

// ── 읽기 ─────────────────────────────────────────────────────────────────

const P = struct {
    s: []const u8,
    i: usize = 0,
    line: u32 = 1,
    a: Allocator,
    diags: *Diags,

    fn peek(p: *P) ?u8 {
        return if (p.i < p.s.len) p.s[p.i] else null;
    }

    fn next(p: *P) void {
        if (p.s[p.i] == '\n') p.line += 1;
        p.i += 1;
    }

    fn fail(p: *P, comptime fmt: []const u8, args: anytype) error{ Syntax, OutOfMemory } {
        try p.diags.add(p.a, p.line, fmt, args);
        return error.Syntax;
    }

    fn failAt(p: *P, line: u32, comptime fmt: []const u8, args: anytype) error{ Syntax, OutOfMemory } {
        p.line = line;
        return p.fail(fmt, args);
    }

    fn skipSpaces(p: *P) void {
        while (p.peek()) |c| {
            if (c != ' ' and c != '\t') break;
            p.next();
        }
    }

    fn skipComment(p: *P) void {
        if (p.peek() != '#') return;
        while (p.peek()) |c| {
            if (c == '\n') break;
            p.next();
        }
    }

    /// 값 뒤에는 공백 · 주석 · 줄 끝만 온다.
    fn endLine(p: *P) !void {
        p.skipSpaces();
        p.skipComment();
        if (p.peek()) |c| {
            if (c == '\r') return p.fail("carriage return — save the file with \\n line endings", .{});
            if (c != '\n') return p.fail("unexpected '{c}' after the value", .{c});
            p.next();
        }
    }

    /// 배열 안: 공백 · 줄바꿈 · 주석을 건넌다.
    fn skipBlank(p: *P) void {
        while (p.peek()) |c| {
            if (c == ' ' or c == '\t' or c == '\n') {
                p.next();
            } else if (c == '#') {
                p.skipComment();
            } else break;
        }
    }

    fn string(p: *P) ![]const u8 {
        if (std.mem.startsWith(u8, p.s[p.i..], "\"\"\"")) return p.fail("multi-line strings are not supported", .{});
        p.next(); // "
        const start = p.i;
        while (p.peek()) |c| {
            if (c == '"') {
                const v = p.s[start..p.i];
                p.next();
                return v;
            }
            if (c == '\\') return p.fail("escapes (\\) are not supported in strings", .{});
            if (c == '\n') return p.fail("unterminated string", .{});
            if (c < 0x20 or c == 0x7f) return p.fail("control character in a string", .{});
            p.next();
        }
        return p.fail("unterminated string", .{});
    }

    fn value(p: *P) !Value {
        const c = p.peek() orelse return p.fail("missing value", .{});
        switch (c) {
            '"' => return .{ .string = try p.string() },
            '0'...'9' => {
                const start = p.i;
                while (p.peek()) |d| {
                    if (d < '0' or d > '9') break;
                    p.next();
                }
                if (p.peek()) |d| switch (d) {
                    ' ', '\t', '\n', '#', ',', ']' => {},
                    else => return p.fail("only plain integers are supported", .{}),
                };
                const n = std.fmt.parseInt(u32, p.s[start..p.i], 10) catch return p.fail("integer out of range", .{});
                return .{ .int = n };
            },
            '[' => {
                const open = p.line;
                p.next();
                var items: std.ArrayList([]const u8) = .empty;
                while (true) {
                    p.skipBlank();
                    const d = p.peek() orelse return p.failAt(open, "unclosed array", .{});
                    if (d == ']') break;
                    if (d != '"') return p.fail("arrays hold only \"strings\"", .{});
                    try items.append(p.a, try p.string());
                    p.skipBlank();
                    const e = p.peek() orelse return p.failAt(open, "unclosed array", .{});
                    if (e == ',') {
                        p.next();
                    } else if (e != ']') return p.fail("expected , or ] in the array", .{});
                }
                p.next(); // ]
                return .{ .array = items.items };
            },
            '\'' => return p.fail("literal strings ('...') are not supported, use \"...\"", .{}),
            '{' => return p.fail("inline tables are not supported", .{}),
            't', 'f' => return p.fail("booleans are not supported", .{}),
            '-', '+' => return p.fail("only plain integers are supported", .{}),
            else => return p.fail("unsupported value", .{}),
        }
    }
};

fn isKeyChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '-';
}

/// 문법만 본다. 키의 뜻은 emit이 본다.
pub fn parse(a: Allocator, src: []const u8, diags: *Diags) ![]Tool {
    var p: P = .{ .s = src, .a = a, .diags = diags };
    var tools: std.ArrayList(Tool) = .empty;
    while (true) {
        p.skipSpaces();
        const c = p.peek() orelse break;
        if (c == '\n') {
            p.next();
            continue;
        }
        if (c == '#') {
            p.skipComment();
            continue;
        }
        if (c == '[') {
            if (!std.mem.startsWith(u8, src[p.i..], "[[tool]]")) return p.fail("only [[tool]] tables are allowed", .{});
            try tools.append(a, .{ .line = p.line });
            p.i += "[[tool]]".len;
            try p.endLine();
            continue;
        }
        const start = p.i;
        while (p.peek()) |d| {
            if (!isKeyChar(d)) break;
            p.next();
        }
        if (p.i == start) return p.fail("expected a key", .{});
        const key = src[start..p.i];
        const line = p.line;
        p.skipSpaces();
        const eq = p.peek() orelse return p.fail("expected = after {s}", .{key});
        if (eq == '.') return p.fail("dotted keys are not supported", .{});
        if (eq != '=') return p.fail("expected = after {s}", .{key});
        p.next();
        p.skipSpaces();
        const v = try p.value();
        try p.endLine();
        if (tools.items.len == 0) {
            p.line = line;
            return p.fail("{s} is outside a [[tool]] table", .{key});
        }
        try tools.items[tools.items.len - 1].entries.append(a, .{ .key = key, .value = v, .line = line });
    }
    return tools.items;
}

// ── 검사와 내보내기 ─────────────────────────────────────────────────────

/// 선택 키(TP-M2 plan 결정 C, strip은 TP-M3 결정 C, man1은 TP-M6 결정 F). 적힌 순서대로 일곱째 열이 된다.
const options = [_]struct { []const u8, Shape }{
    .{ "exe", .array },
    .{ "hook", .string },
    .{ "into", .string },
    .{ "strip", .int },
    .{ "man1", .string },
};

const common = [_][]const u8{ "name", "bundle", "version", "kind" };

/// 종류마다 받는 키(MF design 결정 2). col5 · col6은 TSV의 5열 · 6열을 만드는 법이다.
const Col = union(enum) {
    key: []const u8, // 그 키의 값
    key_or_name: []const u8, // 그 키가 없으면 name
    repo_package, // repo/package
    apt, // 글자 apt(서명된 Release가 검증한다)
};

const KindSpec = struct {
    name: []const u8,
    required: []const []const u8,
    optional: []const []const u8 = &.{},
    col5: Col,
    col6: Col,
};

const kinds = [_]KindSpec{
    .{ .name = "upstream", .required = &.{ "url", "sha256" }, .col5 = .{ .key = "url" }, .col6 = .{ .key = "sha256" } },
    .{ .name = "prebuilt", .required = &.{ "url", "sha256" }, .col5 = .{ .key = "url" }, .col6 = .{ .key = "sha256" } },
    .{ .name = "debian", .required = &.{}, .optional = &.{"package"}, .col5 = .{ .key_or_name = "package" }, .col6 = .apt },
    .{ .name = "vendor-repo", .required = &.{ "repo", "package" }, .col5 = .repo_package, .col6 = .apt },
    .{ .name = "maven", .required = &.{ "lock", "sha256" }, .col5 = .{ .key = "lock" }, .col6 = .{ .key = "sha256" } },
    .{ .name = "hex", .required = &.{ "lock", "sha256" }, .col5 = .{ .key = "lock" }, .col6 = .{ .key = "sha256" } },
};

fn contains(list: []const []const u8, s: []const u8) bool {
    for (list) |x| if (std.mem.eql(u8, x, s)) return true;
    return false;
}

fn find(t: Tool, key: []const u8) ?Entry {
    for (t.entries.items) |e| if (std.mem.eql(u8, e.key, key)) return e;
    return null;
}

fn str(t: Tool, key: []const u8) ?[]const u8 {
    const e = find(t, key) orelse return null;
    return if (e.value == .string) e.value.string else null;
}

fn shapeOf(v: Value) Shape {
    return std.meta.activeTag(v);
}

/// [a-z0-9-]+ (repo) · [a-z0-9][a-z0-9.+-]* (package) — manifest_check의 vendor-repo 정규식과 같다.
fn isRepoName(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '-')) return false;
    return true;
}

fn isPackageName(s: []const u8) bool {
    if (s.len == 0 or !(std.ascii.isLower(s[0]) or std.ascii.isDigit(s[0]))) return false;
    for (s) |c| if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '.' or c == '+' or c == '-')) return false;
    return true;
}

/// TSV 열과 일곱째 열의 구분자(탭 · 공백)가 값 안에 있으면 안 된다.
fn checkWord(d: *Diags, a: Allocator, line: u32, key: []const u8, s: []const u8, option: bool) !void {
    if (s.len == 0) return d.add(a, line, "{s} is empty", .{key});
    if (std.mem.indexOfAny(u8, s, " \t") != null) return d.add(a, line, "{s} has a space or tab: \"{s}\"", .{ key, s });
    if (option and std.mem.indexOfScalar(u8, s, '=') != null) return d.add(a, line, "{s} has '=': \"{s}\"", .{ key, s });
}

fn checkTool(a: Allocator, t: Tool, d: *Diags) !?KindSpec {
    var ok = true;
    const kind_name = str(t, "kind");
    var spec: ?KindSpec = null;
    if (kind_name) |k| {
        for (kinds) |ks| {
            if (std.mem.eql(u8, ks.name, k)) spec = ks;
        }
        if (spec == null) {
            try d.add(a, find(t, "kind").?.line, "unknown kind {s}", .{k});
            ok = false;
        }
    }

    for (t.entries.items, 0..) |e, i| {
        for (t.entries.items[0..i]) |f| {
            if (std.mem.eql(u8, e.key, f.key)) {
                try d.add(a, e.line, "{s} again (first on line {d})", .{ e.key, f.line });
                ok = false;
            }
        }
        var want: ?Shape = null;
        var option = false;
        if (contains(&common, e.key)) want = .string;
        for (options) |o| {
            if (std.mem.eql(u8, o[0], e.key)) {
                want = o[1];
                option = true;
            }
        }
        if (spec) |ks| {
            if (contains(ks.required, e.key) or contains(ks.optional, e.key)) want = .string;
        }
        if (want == null) {
            var other: ?[]const u8 = null;
            for (kinds) |ks| {
                if (contains(ks.required, e.key) or contains(ks.optional, e.key)) other = ks.name;
            }
            if (other != null and spec != null) {
                try d.add(a, e.line, "{s} does not belong to kind {s}", .{ e.key, spec.?.name });
            } else if (other == null) {
                try d.add(a, e.line, "unknown key {s}", .{e.key});
            }
            ok = false;
            continue;
        }
        if (shapeOf(e.value) != want.?) {
            try d.add(a, e.line, "{s} must be {s}", .{ e.key, switch (want.?) {
                .string => "a \"string\"",
                .int => "an integer",
                .array => "an array of strings",
            } });
            ok = false;
            continue;
        }
        const before = d.list.items.len;
        switch (e.value) {
            .string => |s| try checkWord(d, a, e.line, e.key, s, option),
            .int => {},
            .array => |items| {
                if (items.len == 0) try d.add(a, e.line, "{s} is empty", .{e.key});
                for (items) |s| {
                    try checkWord(d, a, e.line, e.key, s, true);
                    if (std.mem.indexOfScalar(u8, s, ',') != null) try d.add(a, e.line, "{s} item has ',': \"{s}\"", .{ e.key, s });
                }
            },
        }
        if (d.list.items.len != before) ok = false;
    }

    const label = str(t, "name") orelse "(no name)";
    for (common) |k| {
        if (find(t, k) == null) {
            try d.add(a, t.line, "tool {s} has no {s}", .{ label, k });
            ok = false;
        }
    }
    if (spec) |ks| {
        for (ks.required) |k| {
            if (find(t, k) == null) {
                try d.add(a, t.line, "tool {s} (kind {s}) has no {s}", .{ label, ks.name, k });
                ok = false;
            }
        }
        if (std.mem.eql(u8, ks.name, "vendor-repo")) {
            if (str(t, "repo")) |r| if (!isRepoName(r)) {
                try d.add(a, find(t, "repo").?.line, "repo wants [a-z0-9-]+, got {s}", .{r});
                ok = false;
            };
            if (str(t, "package")) |s| if (!isPackageName(s)) {
                try d.add(a, find(t, "package").?.line, "package wants [a-z0-9][a-z0-9.+-]*, got {s}", .{s});
                ok = false;
            };
        }
    }
    return if (ok) spec else null;
}

fn col(t: Tool, c: Col, out: *std.ArrayList(u8), a: Allocator) !void {
    switch (c) {
        .key => |k| try out.appendSlice(a, str(t, k).?),
        .key_or_name => |k| try out.appendSlice(a, str(t, k) orelse str(t, "name").?),
        .repo_package => try out.print(a, "{s}/{s}", .{ str(t, "repo").?, str(t, "package").? }),
        .apt => try out.appendSlice(a, "apt"),
    }
}

pub const header = "# 생성됨 — 고치는 것은 devlayer/manifest.toml이다(devlayer/manifest-gen.zig, MF design). 이 파일을 고치지 않는다.\n";

/// 검사를 다 지나면 TSV 전체, 하나라도 걸리면 error.Invalid(이유는 diags에).
pub fn emit(a: Allocator, tools: []const Tool, d: *Diags) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, header);
    for (tools, 0..) |t, i| {
        if (str(t, "name")) |n| {
            for (tools[0..i]) |u| {
                if (str(u, "name")) |m| if (std.mem.eql(u8, n, m)) {
                    try d.add(a, find(t, "name").?.line, "tool {s} again (first on line {d})", .{ n, u.line });
                };
            }
        }
        const ks = try checkTool(a, t, d) orelse continue;
        if (d.list.items.len != 0) continue; // 걸린 것이 있으면 쓰지 않고 검사만 계속한다
        for (common) |k| {
            try out.appendSlice(a, str(t, k).?);
            try out.append(a, '\t');
        }
        try col(t, ks.col5, &out, a);
        try out.append(a, '\t');
        try col(t, ks.col6, &out, a);
        var first = true;
        for (t.entries.items) |e| {
            var is_option = false;
            for (options) |o| is_option = is_option or std.mem.eql(u8, o[0], e.key);
            if (!is_option) continue;
            try out.append(a, if (first) '\t' else ' ');
            first = false;
            try out.print(a, "{s}=", .{e.key});
            switch (e.value) {
                .string => |s| try out.appendSlice(a, s),
                .int => |n| try out.print(a, "{d}", .{n}),
                .array => |items| for (items, 0..) |s, j| {
                    if (j != 0) try out.append(a, ',');
                    try out.appendSlice(a, s);
                },
            }
        }
        try out.append(a, '\n');
    }
    if (tools.len == 0) try d.add(a, 1, "no [[tool]] tables", .{});
    if (d.list.items.len != 0) return error.Invalid;
    return out.items;
}

pub fn convert(a: Allocator, src: []const u8, d: *Diags) ![]u8 {
    const tools = parse(a, src, d) catch |e| switch (e) {
        error.Syntax => return error.Invalid,
        else => return e,
    };
    return emit(a, tools, d);
}

pub fn main(init: std.process.Init) !u8 {
    const a = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 3) {
        std.debug.print("usage: manifest-gen <in.toml> <out.tsv>\n", .{});
        return 2;
    }
    const cwd = std.Io.Dir.cwd();
    const src = cwd.readFileAlloc(io, args[1], a, .limited(4 << 20)) catch |e| {
        std.debug.print("manifest-gen: cannot read {s}: {t}\n", .{ args[1], e });
        return 1;
    };
    var d: Diags = .{};
    const tsv = convert(a, src, &d) catch |e| switch (e) {
        error.Invalid => {
            for (d.list.items) |x| std.debug.print("{s}:{d}: {s}\n", .{ args[1], x.line, x.msg });
            std.debug.print("manifest-gen: {d} problem(s), {s} not written\n", .{ d.list.items.len, args[2] });
            return 1;
        },
        else => return e,
    };
    // 반쪽 TSV를 남기지 않는다 — 임시 파일에 다 쓰고 바꿔치기한다.
    const tmp = try std.fmt.allocPrint(a, "{s}.tmp", .{args[2]});
    try cwd.writeFile(io, .{ .sub_path = tmp, .data = tsv });
    try cwd.rename(tmp, cwd, args[2], io);
    return 0;
}

// ── 검사 ─────────────────────────────────────────────────────────────────

fn expectTsv(src: []const u8, want: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var d: Diags = .{};
    const got = convert(arena.allocator(), src, &d) catch |e| {
        for (d.list.items) |x| std.debug.print("line {d}: {s}\n", .{ x.line, x.msg });
        return e;
    };
    try std.testing.expectEqualStrings(want, got[header.len..]);
}

fn expectDiag(src: []const u8, line: u32, msg: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var d: Diags = .{};
    try std.testing.expectError(error.Invalid, convert(arena.allocator(), src, &d));
    for (d.list.items) |x| {
        if (x.line == line and std.mem.indexOf(u8, x.msg, msg) != null) return;
    }
    for (d.list.items) |x| std.debug.print("  got line {d}: {s}\n", .{ x.line, x.msg });
    std.debug.print("  want line {d}: ...{s}...\n", .{ line, msg });
    return error.DiagMissing;
}

test "upstream with options in written order, multi-line array" {
    try expectTsv(
        \\# 머리 주석
        \\
        \\[[tool]]
        \\name = "ninja"   # 줄 끝 주석
        \\bundle = "base"
        \\version = "1.13.2"
        \\kind = "upstream"
        \\url = "https://example.org/ninja-linux.zip#x"
        \\sha256 = "abc"
        \\strip = 0
        \\exe = [
        \\  "ninja",     # 배열 안 주석
        \\  "ninja-two",
        \\]
        \\
        \\[[tool]]
        \\name = "gdb"
        \\bundle = "base"
        \\version = "1:16.3-1"
        \\kind = "debian"
        \\
    ,
        "ninja\tbase\t1.13.2\tupstream\thttps://example.org/ninja-linux.zip#x\tabc\tstrip=0 exe=ninja,ninja-two\n" ++
            "gdb\tbase\t1:16.3-1\tdebian\tgdb\tapt\n",
    );
}

test "vendor-repo, maven, debian package" {
    try expectTsv(
        \\[[tool]]
        \\name = "postgresql"
        \\bundle = "server"
        \\version = "18.1-1.pgdg13+1"
        \\kind = "vendor-repo"
        \\repo = "pgdg"
        \\package = "postgresql-18"
        \\[[tool]]
        \\name = "clojure-m2"
        \\bundle = "lang-jvm"
        \\version = "1.12"
        \\kind = "maven"
        \\lock = "devlayer/maven/clojure-m2.lock"
        \\sha256 = "584d"
        \\into = "clojure"
        \\[[tool]]
        \\name = "cc"
        \\bundle = "base"
        \\version = "1"
        \\kind = "debian"
        \\package = "gcc"
    ,
        "postgresql\tserver\t18.1-1.pgdg13+1\tvendor-repo\tpgdg/postgresql-18\tapt\n" ++
            "clojure-m2\tlang-jvm\t1.12\tmaven\tdevlayer/maven/clojure-m2.lock\t584d\tinto=clojure\n" ++
            "cc\tbase\t1\tdebian\tgcc\tapt\n",
    );
}

const base_tool =
    \\[[tool]]
    \\name = "gdb"
    \\bundle = "base"
    \\version = "1"
    \\kind = "debian"
    \\
;

test "schema problems" {
    try expectDiag(base_tool ++ "colour = \"red\"\n", 6, "unknown key colour");
    try expectDiag(base_tool ++ "url = \"https://x\"\n", 6, "url does not belong to kind debian");
    try expectDiag(base_tool ++ "strip = \"1\"\n", 6, "strip must be an integer");
    try expectDiag(base_tool ++ "exe = \"gdb\"\n", 6, "exe must be an array");
    try expectDiag(base_tool ++ "hook = \"a b\"\n", 6, "space or tab");
    try expectDiag(base_tool ++ "into = \"a=b\"\n", 6, "has '='");
    try expectDiag(base_tool ++ "exe = [\"a,b\"]\n", 6, "item has ','");
    try expectDiag(base_tool ++ "version = \"2\"\n", 6, "version again (first on line 4)");
    try expectDiag(base_tool ++ base_tool, 7, "tool gdb again (first on line 1)");
    try expectDiag("[[tool]]\nname = \"x\"\nbundle = \"b\"\nversion = \"1\"\nkind = \"upstream\"\nurl = \"u\"\n", 1, "tool x (kind upstream) has no sha256");
    try expectDiag("[[tool]]\nname = \"x\"\nbundle = \"b\"\nversion = \"1\"\n", 1, "tool x has no kind");
    try expectDiag("[[tool]]\nname = \"x\"\nbundle = \"b\"\nversion = \"1\"\nkind = \"npm\"\n", 5, "unknown kind npm");
    try expectDiag("[[tool]]\nname = \"x\"\nbundle = \"b\"\nversion = \"1\"\nkind = \"vendor-repo\"\nrepo = \"P\"\npackage = \"p\"\n", 6, "repo wants");
}

test "syntax outside the subset" {
    try expectDiag(base_tool ++ "hook = 'gdb'\n", 6, "literal strings");
    try expectDiag("[tool]\n", 1, "only [[tool]] tables");
    try expectDiag(base_tool ++ "exe = [\"a\",\n\"b\"\n", 6, "unclosed array");
    try expectDiag(base_tool ++ "a.b = \"c\"\n", 6, "dotted keys");
    try expectDiag(base_tool ++ "hook = \"a\\tb\"\n", 6, "escapes");
    try expectDiag(base_tool ++ "hook = { a = 1 }\n", 6, "inline tables");
    try expectDiag(base_tool ++ "strip = 1.5\n", 6, "plain integers");
    try expectDiag(base_tool ++ "hook = \"a\" \"b\"\n", 6, "unexpected '\"'");
    try expectDiag("name = \"x\"\n", 1, "outside a [[tool]]");
    try expectDiag("", 1, "no [[tool]] tables");
}
