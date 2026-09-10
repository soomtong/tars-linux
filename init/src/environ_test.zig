const std = @import("std");
const environ = @import("environ.zig");

/// 커널이 준 것처럼 생긴 가짜 블록. 실제 커널의 envp_init은 둘이다
/// (`HOME=/` · `TERM=linux`, linux/init/main.c).
var fake: [environ.MAX_ENTRIES:null]?[*:0]const u8 = undefined;

/// entries를 fake에 채우고 null로 닫은 뒤 그 포인터를 돌려준다.
fn kernelBlock(entries: []const [:0]const u8) [*:null]const ?[*:0]const u8 {
    for (entries, 0..) |e, i| fake[i] = e.ptr;
    fake[entries.len] = null;
    return &fake;
}

/// 돌려받은 블록의 항목 수를 센다.
fn count(block: [*:null]const ?[*:0]const u8) usize {
    var n: usize = 0;
    while (block[n] != null) n += 1;
    return n;
}

/// n번째 항목이 want와 같은가.
fn entryIs(block: [*:null]const ?[*:0]const u8, n: usize, want: []const u8) bool {
    const got = block[n] orelse return false;
    return std.mem.eql(u8, std.mem.span(got), want);
}

pub fn main() !void {
    var buf: environ.Block = undefined;

    // ── 1. 정상 경로: 커널이 준 둘 뒤에 PATH가 붙는다 ──────────────────
    //
    // 이것이 이 파일의 심장이다. 순서까지 보는 이유는 덮어쓰는 구현
    // (buf[0]에 PATH를 넣고 나머지를 미는 것)도 개수 검사만으로는 통과하기
    // 때문이다.
    {
        const kernel = kernelBlock(&.{ "HOME=/", "TERM=linux" });
        const got = environ.withPath(kernel, &buf);

        if (count(got) != 3) {
            std.debug.print("FAIL: want 3 entries, got {d}\n", .{count(got)});
            return error.WrongCount;
        }
        if (!entryIs(got, 0, "HOME=/") or !entryIs(got, 1, "TERM=linux")) {
            std.debug.print("FAIL: the kernel's own entries did not survive in order\n", .{});
            return error.LostKernelEntries;
        }
        if (!entryIs(got, 2, "PATH=/usr/bin:/bin")) {
            std.debug.print("FAIL: PATH was not appended last\n", .{});
            return error.NoPath;
        }
    }

    // ── 2. 대조군: 커널이 아무것도 안 줬다 ─────────────────────────────
    //
    // 커널은 늘 둘을 주지만, 그 사실에 기대는 구현(예: 무조건 buf[2]에 쓰는
    // 것)을 여기서 잡는다.
    {
        const kernel = kernelBlock(&.{});
        const got = environ.withPath(kernel, &buf);
        if (count(got) != 1 or !entryIs(got, 0, "PATH=/usr/bin:/bin")) {
            std.debug.print("FAIL: an empty kernel block did not yield exactly PATH\n", .{});
            return error.EmptyBlockWrong;
        }
    }

    // ── 3. 넘치면 원본을 그대로 돌려준다 ───────────────────────────────
    //
    // **PATH가 없는 것이 부팅이 안 되는 것보다 낫다.** 버퍼를 넘겨 쓰면
    // PID 1이 스택을 밟고 기계가 아예 안 켜진다 — 증상이 원인에서 가장 먼
    // 종류다.
    {
        var many: [environ.MAX_ENTRIES]([:0]const u8) = undefined;
        for (&many) |*m| m.* = "X=1";
        const kernel = kernelBlock(many[0 .. environ.MAX_ENTRIES - 1]);
        const got = environ.withPath(kernel, &buf);
        if (got != kernel) {
            std.debug.print("FAIL: an oversized block should have been passed through untouched\n", .{});
            return error.OverflowNotPassedThrough;
        }
    }

    // ── 4. PATH 값이 design 결정 1과 같다 ──────────────────────────────
    //
    // 자리가 둘인 것에 뜻이 있다 — 도구는 전부 /usr/bin에 있고 /bin에는
    // sh 하나만 있다(design 결정 6). 이 문자열이 바뀌면 make_initrd.sh가
    // 넣는 자리와 어긋나고, 증상은 "어떤 명령도 안 찾아진다"다.
    if (!std.mem.eql(u8, environ.PATH_ENTRY, "PATH=/usr/bin:/bin")) {
        std.debug.print("FAIL: PATH_ENTRY is '{s}'\n", .{environ.PATH_ENTRY});
        return error.WrongPathValue;
    }

    std.debug.print("environ_test: PATH is appended to the kernel's block ({d} slots)\n", .{environ.MAX_ENTRIES});
}
