const std = @import("std");
const environ = @import("environ.zig");
const config = @import("config.zig");

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
    var tz_buf: [environ.TZ_ENTRY_MAX]u8 = undefined;
    const tz = environ.tzEntry(&tz_buf, "Asia/Seoul");

    // ── 1. 정상 경로(zsh): 커널의 둘 뒤에 우리 것 여섯이 순서대로 붙는다 ──
    //
    // 이것이 이 파일의 심장이다. 순서까지 보는 이유는 덮어쓰는 구현
    // (buf[0]에 PATH를 넣고 나머지를 미는 것)도 개수 검사만으로는 통과하기
    // 때문이다.
    {
        const kernel = kernelBlock(&.{ "HOME=/", "TERM=linux" });
        const got = environ.withTarsEnv(kernel, &buf, tz, config.Shell.zsh.histEntries());

        if (count(got) != 8) {
            std.debug.print("FAIL: want 8 entries for zsh, got {d}\n", .{count(got)});
            return error.WrongCount;
        }
        if (!entryIs(got, 0, "HOME=/") or !entryIs(got, 1, "TERM=linux")) {
            std.debug.print("FAIL: the kernel's own entries did not survive in order\n", .{});
            return error.LostKernelEntries;
        }
        // 셸과 무관한 셋이 먼저다. TS-M3이 TZ를 XDG 뒤 · 히스토리 앞에
        // 넣었다 — "셸마다 갈리는 것"은 맨 뒤라는 규칙을 지키기 위해서다.
        if (!entryIs(got, 2, "PATH=/usr/bin:/bin") or
            !entryIs(got, 3, "XDG_DATA_HOME=/config/xdg") or
            !entryIs(got, 4, "TZ=Asia/Seoul"))
        {
            std.debug.print("FAIL: PATH, XDG_DATA_HOME and TZ are not the first three we add\n", .{});
            return error.NoPath;
        }
        // 히스토리 셋이 그 뒤에 순서대로 온다. zsh만 SAVEHIST를 받고,
        // 그것이 없으면 zsh는 HISTFILE이 있어도 한 줄도 안 쓴다(실측 9).
        if (!entryIs(got, 5, "HISTFILE=/config/zsh_history") or
            !entryIs(got, 6, "HISTSIZE=5000") or
            !entryIs(got, 7, "SAVEHIST=5000"))
        {
            std.debug.print("FAIL: the zsh history entries are not appended in order\n", .{});
            return error.NoHistory;
        }
    }

    // ── 2. fish: 히스토리 env가 하나도 없다 ─────────────────────────
    //
    // 대조군이자 결정 3의 절반이다. fish의 히스토리는 XDG_DATA_HOME 아래로
    // 통째로 따라오므로(실측 11·40) 줄 하나도 필요 없고, 줄 수를 정하는
    // 변수도 없다(비목표 4).
    {
        const kernel = kernelBlock(&.{ "HOME=/", "TERM=linux" });
        const got = environ.withTarsEnv(kernel, &buf, tz, config.Shell.fish.histEntries());
        if (count(got) != 5 or !entryIs(got, 4, "TZ=Asia/Seoul")) {
            std.debug.print("FAIL: fish should get exactly PATH, XDG_DATA_HOME and TZ, got {d} entries\n", .{count(got)});
            return error.FishBlockWrong;
        }
    }

    // ── 3. 대조군: 커널이 아무것도 안 줬다 ─────────────────────────────
    //
    // 커널은 늘 둘을 주지만, 그 사실에 기대는 구현(예: 무조건 buf[2]에 쓰는
    // 것)을 여기서 잡는다.
    {
        const kernel = kernelBlock(&.{});
        const got = environ.withTarsEnv(kernel, &buf, tz, config.Shell.fish.histEntries());
        if (count(got) != 3 or !entryIs(got, 0, "PATH=/usr/bin:/bin")) {
            std.debug.print("FAIL: an empty kernel block did not yield exactly our three\n", .{});
            return error.EmptyBlockWrong;
        }
    }

    // ── 4. 넘침 — 경계 양쪽을 본다 ─────────────────────────────────
    //
    // PATH가 없는 것이 부팅이 안 되는 것보다 낫다. 버퍼를 넘겨 쓰면 PID 1이
    // 스택을 밟고 기계가 아예 안 켜진다 — 증상이 원인에서 가장 먼 종류다.
    //
    // 경계가 M2에서 한 번(하나 → 다섯), TS-M3에서 또 한 번(다섯 → 여섯)
    // 움직였다. 그래서 "넘치면 통과시킨다"만 보지 않고 바로 아래는 여전히
    // 붙는다도 본다 — 한쪽만 보면 `return kernel`을 맨 위로 올린 구현도
    // 초록이다.
    {
        var many: [environ.MAX_ENTRIES]([:0]const u8) = undefined;
        for (&many) |*m| m.* = "X=1";
        const hist = config.Shell.zsh.histEntries(); // 셋 → added = 6

        // n + 6 == MAX_ENTRIES → 닫는 null 자리가 없다. 그대로 돌려준다.
        const over = kernelBlock(many[0 .. environ.MAX_ENTRIES - 6]);
        if (environ.withTarsEnv(over, &buf, tz, hist) != over) {
            std.debug.print("FAIL: an oversized block should have been passed through untouched\n", .{});
            return error.OverflowNotPassedThrough;
        }

        // 한 칸 적으면 딱 들어간다.
        const fits = kernelBlock(many[0 .. environ.MAX_ENTRIES - 7]);
        const got = environ.withTarsEnv(fits, &buf, tz, hist);
        if (got == fits or count(got) != environ.MAX_ENTRIES - 1) {
            std.debug.print("FAIL: a block that fits was passed through instead of extended\n", .{});
            return error.FitNotExtended;
        }
    }

    // ── 5. PATH 값이 design 결정 1과 같다 ──────────────────────────────
    //
    // 자리가 둘인 것에 뜻이 있다 — 도구는 전부 /usr/bin에 있고 /bin에는
    // sh 하나만 있다(design 결정 6). 이 문자열이 바뀌면 make_initrd.sh가
    // 넣는 자리와 어긋나고, 증상은 "어떤 명령도 안 찾아진다"다.
    if (!std.mem.eql(u8, environ.PATH_ENTRY, "PATH=/usr/bin:/bin")) {
        std.debug.print("FAIL: PATH_ENTRY is '{s}'\n", .{environ.PATH_ENTRY});
        return error.WrongPathValue;
    }

    // ── 6. XDG 항목의 값과 경로가 한 글자를 공유한다 ────────────────────
    //
    // `main.zig`가 만드는 디렉터리와 셸이 받는 값이 어긋나면 증상은 "기억이
    // 가끔 안 남는다"이고 원인에서 아주 멀다. `++`가 컴파일 타임에 잇고,
    // 이 두 줄은 그 이음매가 실제로 우리가 뜻한 글자인지를 본다.
    if (!std.mem.eql(u8, environ.XDG_DATA_DIR, "/config/xdg")) {
        std.debug.print("FAIL: XDG_DATA_DIR is '{s}'\n", .{environ.XDG_DATA_DIR});
        return error.WrongXdgDir;
    }
    if (!std.mem.eql(u8, environ.XDG_ENTRY, "XDG_DATA_HOME=/config/xdg")) {
        std.debug.print("FAIL: XDG_ENTRY is '{s}'\n", .{environ.XDG_ENTRY});
        return error.WrongXdgEntry;
    }

    // ── 7. TZ 항목 — 이름이 그대로 붙고, 안 들어가면 UTC다 ──────────────
    //
    // `tzEntry`가 이 파일에서 유일하게 글자를 만드는 함수다(나머지는 포인터를
    // 옮긴다). 넘칠 때 `TZ=UTC`로 떨어지는 것이 부팅을 안 막는 쪽이다 —
    // 이름이 64를 넘는 일은 `config.Timezone.parse`가 먼저 막지만, 이 파일은
    // 그 파일을 모르므로 자기 경계를 자기가 지킨다.
    {
        var b: [environ.TZ_ENTRY_MAX]u8 = undefined;
        if (!std.mem.eql(u8, environ.tzEntry(&b, "Asia/Seoul"), "TZ=Asia/Seoul")) {
            std.debug.print("FAIL: tzEntry gave '{s}'\n", .{environ.tzEntry(&b, "Asia/Seoul")});
            return error.WrongTzEntry;
        }
        // 접두사 셋 + 이름 + NUL이 딱 맞는 길이는 들어간다.
        const fits_name = "a" ** (environ.TZ_ENTRY_MAX - environ.TZ_PREFIX.len - 1);
        if (environ.tzEntry(&b, fits_name).len != environ.TZ_ENTRY_MAX - 1) {
            std.debug.print("FAIL: a name that just fits was not kept\n", .{});
            return error.WrongTzEntry;
        }
        // 한 글자 더 길면 NUL 자리가 없다. UTC로 떨어진다.
        const over_name = "a" ** (environ.TZ_ENTRY_MAX - environ.TZ_PREFIX.len);
        if (!std.mem.eql(u8, environ.tzEntry(&b, over_name), "TZ=UTC")) {
            std.debug.print("FAIL: an oversized name did not fall back to TZ=UTC\n", .{});
            return error.WrongTzEntry;
        }
    }

    std.debug.print("environ_test: PATH, XDG_DATA_HOME, TZ and the shell's history env are appended to the kernel's block ({d} slots)\n", .{environ.MAX_ENTRIES});
}
