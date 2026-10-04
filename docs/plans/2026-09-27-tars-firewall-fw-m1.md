# FW-M1 — `firewall=on`이 들어오는 TCP를 가른다

> 이 plan을 실행하는 사람에게: 체크박스(`- [ ]`)를 따라 Task 순서대로 간다.
> 편집 뒤에는 `git diff --stat`으로 더한 줄과 지운 줄을 따로 세고, 지우는 편집은
> `git diff | grep '^-'`로 의도한 줄만 지워졌는지 본다(CLAUDE.md 진행 방식 2).

Goal: `tars.conf`의 `firewall=on`이면 `init`이 네트워크를 올리기 전에 `nft -f`로
기본 규칙을 올리고, 새 체인 `firewall/check.sh`가 "연 TCP 포트는 바이트가 오고 안
연 TCP 포트는 안 온다"를 판정한다.

Architecture: 커널에 netfilter 다섯을 켜고(FW-M0 실측 1), sysroot에 nftables 패키지
다섯을 더해 `nft`를 게스트 `/usr/bin`에 싣는다(실측 2). 규칙 파일 둘을
`make_initrd.sh`가 `/etc/tars/`에 굽는다. `init/src/firewall.zig`가 `fork` →
`execve(nft -f …)` → `wait4`를 하고, 실패하면 include 없는 파일로 한 번 더 한다
(design 결정 5). `main.zig`는 `net.bringUp` 바로 앞에서 그것을 부른다.

Tech Stack: Zig 0.16(`std.os.linux`) · nftables 1.1.3 · bash · QEMU(`-netdev user` +
`hostfwd`) · `debugfs` · 기존 `gate_lib.sh`(`type_keys` · `wait_for_screen`)

---

## 이 milestone이 안 하는 것 (M2의 몫)

UDP · 포트 여럿(셋 이상) · 문법 오류 부팅(갈래 2의 판정) · 사용자 가이드. 갈래 2와
3의 코드는 이번에 들어가지만 게이트가 밟는 것은 갈래 1과 `off`뿐이다. 루트 게이트
(열다섯 체인 × 3)는 M2 끝에 돈다 — 이번에는 새 체인과 이웃 셋(`config` · `tools` ·
`net`)을 한 번씩 돌린다.

## 파일

| 파일 | 무엇 |
|---|---|
| `kernel/.config` | netfilter 다섯 + 끌려온 열(해소본) |
| `devcontainer/Dockerfile` | 층 10 — 패키지 다섯 |
| `kernel/guest_tools.sh` | 층 10 — `nft` 한 줄(라이브러리는 `copy_lib_deps`가 따라간다) |
| `kernel/make_initrd.sh` | `/etc/tars/firewall.nft` · `/etc/tars/firewall-base.nft` |
| `init/src/config.zig` | `Firewall` enum · `firewall` 필드 · 파싱 · seed 템플릿 |
| `init/src/config_test.zig` | 비교 필드 하나 · 예시 다섯 |
| `init/src/firewall.zig` (새) | `up()` — 갈래 셋과 `off` |
| `init/src/main.zig` | `config` 로그 줄 끝에 `firewall=` · `net.bringUp` 앞의 한 줄 |
| `firewall/check.sh` (새) | 열다섯번째 체인, 부팅 하나 · 검사 여덟 |
| `check.sh` | `CHAINS`에 한 줄 |

## Task 0 — 출발점

- [ ] Step 1: 작업 트리를 본다

```bash
git status --short
git log --oneline -1
```

기대: 이 plan 파일 하나만 `??`로 있다(또는 이 plan의 커밋이 HEAD다).

## Task 1 — 커널 옵션 다섯 (빌드 약 5~10분)

- [ ] Step 1: 켜고 빌드한다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/kernel tars-devcontainer bash -c '
  src/linux-6.18.42/scripts/config --file .config \
    -e NETFILTER -e NF_TABLES -e NF_TABLES_IPV4 -e NF_CONNTRACK -e NFT_CT
  ./build.sh 2>&1 | tail -2'
```

- [ ] Step 2: 해소본을 커밋할 `.config`로 둔다

WN-M1과 같은 관례다 — 저장소의 `.config`는 `olddefconfig`가 해소한 것이어야
`build.sh`의 해시 스탬프와 게이트의 정적 검사가 같은 글자를 본다.

```bash
cp kernel/build/.config kernel/.config
git diff --stat kernel/.config
diff <(git show HEAD:kernel/.config | grep '^CONFIG_' | sort) \
     <(grep '^CONFIG_' kernel/.config | sort)
```

기대: `>` 열다섯 줄이 FW-M0 실측 1과 글자까지 같고 `<` 줄은 0이다. `git diff`가
`# CONFIG_NETFILTER is not set` 한 줄을 지운다 — 그 한 줄만 `-`인지
`git diff kernel/.config | grep '^-[^-]'`로 본다.

## Task 2 — sysroot에 nftables (이미지 약 1분)

- [ ] Step 1: Dockerfile에 층 10을 적는다

`devcontainer/Dockerfile`의 층 9 주석 블록(`# ── LB-M2: 층 9(이름 풀이)`) 뒤,
`ENV AMD64_SYSROOT=` 앞에 넣는다.

```dockerfile
#
# ── FW-M1: 층 10(방화벽) ───────────────────────────────────────────────
#
# nft와 그것이 끌고 오는 넷이다. 재귀 DT_NEEDED 열둘 중 여덟(libc · libedit ·
# libgmp · libmnl · libtinfo · libbsd · libmd · 로더)은 앞 층들에 이미 있어서
# 새것은 다섯, 1,386,600바이트다(FW-M0 실측 2). libxtables는 nft가 옛 iptables
# 확장을 해석하려고 링크할 뿐 우리 규칙은 안 쓰지만, NEEDED라 빼면 nft가 안 뜬다.
```

`libnss-myhostname:amd64 \` 줄 바로 뒤에 다섯 줄을 넣는다.

```dockerfile
        nftables:amd64 \
        libnftables1:amd64 \
        libnftnl11:amd64 \
        libxtables12:amd64 \
        libjansson4:amd64 \
```

- [ ] Step 2: 이미지를 다시 굽고 sysroot를 본다

```bash
{ time docker build -t tars-devcontainer devcontainer/ > /tmp/fw-docker-build.log 2>&1 ; } 2>&1 | tail -3
tail -3 /tmp/fw-docker-build.log
docker run --rm tars-devcontainer bash -c '
  S=/usr/local/amd64-sysroot
  ls -la $S/usr/sbin/nft
  for n in libnftables.so.1 libnftnl.so.11 libxtables.so.12 libjansson.so.4; do
    ls -L -la $S/usr/lib/x86_64-linux-gnu/$n
  done'
```

기대: 다섯 파일이 있고 바이트가 실측 2의 표와 같다.

## Task 3 — 게스트에 `nft`와 규칙 파일 둘

- [ ] Step 1: `kernel/guest_tools.sh`의 층 8(`usr/bin/chronyc:usr/bin/chronyc`) 뒤에 넣는다

```bash

  # ── 층 10 · 방화벽 ──────────────────────────────────────────────────────
  # FW-M1. init의 firewall.zig가 /usr/bin/nft로 execve한다. 오른쪽이 /usr/bin인
  # 이유는 dhcpcd · chronyd와 같다(PATH가 /usr/bin:/bin). 사람도 셸에서
  # `nft list ruleset`으로 지금 선 규칙을 본다.
  #
  # 새 라이브러리(FW-M0 실측 2): libnftables · libnftnl · libxtables · libjansson
  usr/sbin/nft:usr/bin/nft
```

- [ ] Step 2: `kernel/make_initrd.sh`의 LB-M2 블록(`copy_lib_deps "${WORKDIR}${LIB_DEST}/libnss_myhostname.so.2"`) 뒤에 넣는다

규칙 파일의 주석은 ASCII로 둔다. nft의 파서가 주석 안의 UTF-8을 어떻게 다루는지
잰 적이 없고, 이 파일이 안 읽히면 갈래 2 · 3으로 떨어진다.

```bash

# FW-M1. 방화벽 규칙 둘(FW design 결정 3 · 5). init의 firewall.zig가 tars.conf에
# firewall=on이 있을 때만 앞의 것을 nft -f로 올리고, 실패하면 뒤의 것을 올린다.
#
#   firewall.nft       기본 규칙 + /config/nftables.d/*.nft. 사람이 여는 포트가
#                      chain 안으로 include된다 — 파일 한 줄이 규칙 한 줄이다
#   firewall-base.nft  include가 없는 같은 규칙. 사람의 파일이 틀려서 앞의 것이
#                      실패했을 때 닫힌 채로 끝나게 한다. nft -f는 원자적이라
#                      실패하면 아무것도 안 바뀌고(FW-M0 실측 8), 부팅 첫 회에는
#                      "앞의 규칙"이 없으므로 이 파일이 없으면 열린 채다
#
# 표는 inet이 아니라 ip다. NF_TABLES_INET이 IPV6를 요구하고 우리 커널에는
# IPv6가 없다(design 확인 6 · 위험 6). include glob이 아무것도 못 찾아도 nft는
# 에러로 보지 않는다(실측 4) — /config가 안 붙은 부팅도 같은 파일을 올린다.
mkdir -p "$WORKDIR/etc/tars"
cat > "$WORKDIR/etc/tars/firewall.nft" <<'EOF'
# TARS inbound firewall (FW design decision 3). Loaded by init when tars.conf
# says firewall=on. Do not edit this file; open ports in /config/nftables.d/.
flush ruleset
table ip tars {
	chain input {
		type filter hook input priority filter; policy drop;
		iif "lo" accept
		ct state established,related accept
		ct state invalid drop
		include "/config/nftables.d/*.nft"
	}
}
EOF
cat > "$WORKDIR/etc/tars/firewall-base.nft" <<'EOF'
# TARS inbound firewall without /config/nftables.d (FW design decision 5).
# init loads this only when firewall.nft failed, so the machine stays closed.
flush ruleset
table ip tars {
	chain input {
		type filter hook input priority filter; policy drop;
		iif "lo" accept
		ct state established,related accept
		ct state invalid drop
	}
}
EOF
```

- [ ] Step 3: initrd를 짓고 안을 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build >/dev/null && cd ../terminal && ./prepare.sh >/dev/null &&
  cd ../kernel && ./make_initrd.sh 2>&1 | tail -2 &&
  zcat initrd.cpio | cpio -it 2>/dev/null | grep -E "nft|jansson|xtables|etc/tars" | sort'
git diff --stat
```

기대: `usr/bin/nft` · `etc/tars/firewall.nft` · `etc/tars/firewall-base.nft` ·
`lib/x86_64-linux-gnu/`의 넷(`libnftables.so.1` · `libnftnl.so.11` · `libxtables.so.12` ·
`libjansson.so.4`).

## Task 4 — `firewall` 키 (TDD)

- [ ] Step 1: `init/src/config_test.zig`에 실패하는 검사를 쓴다

`expect()`의 비교에 열째 필드를 더한다. `got.timezone.eql(want.timezone) and` 줄 뒤:

```zig
        // FW-M1: 열째 필드. SC-M0이 여섯째에 대해 적어 둔 것과 같은 자리다 —
        // 이 줄이 없으면 아래 firewall 검사가 아무것도 안 보고 초록이다.
        got.firewall == want.firewall and
```

FAIL 메시지의 두 형식 문자열 끝 `timezone={s}\n`을 각각 `timezone={s} firewall={s}\n`으로
바꾸고, 인자 목록의 `got.timezone.slice(),` 뒤에 `@tagName(got.firewall),`를,
`want.timezone.slice(),` 뒤에 `@tagName(want.firewall),`를 넣는다.

`main()`에서 `// 넉 자 대조(결정 M3-B).` 블록이 끝난 뒤(`// ── \`arg()\` → \`parse()\` 왕복` 앞)에 넣는다.

```zig
    // ── FW-M1: firewall ────────────────────────────────────────────────
    //
    // net과 같은 모양의 enum 키다. 기본값이 off인 것이 design 결정 1이다 —
    // 이 키를 안 적은 기계는 한 글자도 안 바뀐다.
    try expect("firewall=on\n", .{ .firewall = .on });
    try expect("firewall=off\n", .{});
    try expect("firewall=yes\n", .{}); // enum에 없는 값
    try expect("firewall=\n", .{}); // 값 없음
    // 체인의 디스크가 실제로 쓰는 두 줄이다.
    try expect("net=dhcp\nfirewall=on\n", .{ .net = .dhcp, .firewall = .on });
```

- [ ] Step 2: 실패를 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer zig build test 2>&1 | tail -5
```

기대: 컴파일 에러 — `no field named 'firewall'` 계열.

- [ ] Step 3: `init/src/config.zig`에 키를 넣는다

`pub const Net = enum { … };` 뒤에:

```zig

/// 방화벽을 켜는가(FW design 결정 1). 켜면 들어오는 것을 기본으로 버리고,
/// 받을 포트는 사람이 /config/nftables.d/*.nft에 nftables 문법으로 적는다.
/// 규칙의 의미는 전부 그 파일과 initrd의 /etc/tars/firewall.nft에 있고 이
/// 값은 스위치 하나다 — `firewall.zig`가 이것만 본다.
///
/// 기본값이 `off`인 근거는 `net`과 다르다. 켜는 비용이 아니라 관례다 —
/// 이 키를 안 적은 기계는 한 글자도 안 바뀐다(`net=dhcp`인 기계는 IN이 증명한
/// 대로 연 포트를 누구에게나 받는다).
pub const Firewall = enum {
    off,
    on,
};
```

`Config`의 `timezone: Timezone = Timezone.UTC,` 뒤에:

```zig
    /// 기본값이 `off`인 넷째 키다. 근거는 위 `Firewall`의 문서 주석에 있다.
    firewall: Firewall = .off,
```

`parse`의 `timezone` 갈래 뒤(`} else {` 앞)에:

```zig
        } else if (std.mem.eql(u8, key, "firewall")) {
            // net과 완전히 같은 모양이다.
            c.firewall = std.meta.stringToEnum(Firewall, value) orelse {
                std.debug.print("tars-init: unknown firewall '{s}', falling back to {s}\n", .{
                    value, @tagName(c.firewall),
                });
                continue;
            };
```

`save`의 템플릿 끝 `\\timezone={s}` 뒤(빈 `\\` 줄 앞)에:

```zig
        \\# firewall: off | on
        \\#   on이면 들어오는 연결을 기본으로 버린다. 받을 포트는
        \\#   /config/nftables.d/ 아래 .nft 파일에 nftables 문법으로 한 줄씩
        \\#   적는다. 예: tcp dport 8080 accept
        \\firewall={s}
```

인자 목록의 `c.timezone.slice(),` 뒤에 `@tagName(c.firewall),`.

- [ ] Step 4: 통과를 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer zig build test 2>&1 | tail -5; echo "rc=$?"
```

기대: 에러 없음.

## Task 5 — `firewall.zig`와 배선

- [ ] Step 1: `init/src/firewall.zig`를 만든다

```zig
const std = @import("std");
const linux = std.os.linux;
const config = @import("config.zig");

/// net.zig · clock.zig와 같은 세 줄짜리 헬퍼다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// nft가 사는 자리. guest_tools.sh의 층 10이 usr/sbin/nft를 여기로 넣는다.
const NFT_PATH: [:0]const u8 = "/usr/bin/nft";
/// make_initrd.sh가 굽는 둘(design 결정 3 · 5).
const RULES_PATH: [:0]const u8 = "/etc/tars/firewall.nft";
const BASE_PATH: [:0]const u8 = "/etc/tars/firewall-base.nft";

/// `nft -f path`를 돌리고 끝나기를 기다린다. 0으로 끝났으면 true다.
///
/// 기다리는 것이 dhcpcd · chronyd와 다른 점이다(design 확인 3). nft는 로컬
/// netlink만 쓰므로 네트워크를 기다리지 않고, 규칙이 서기 전에 주소가 붙는
/// 틈을 없애려면 끝을 봐야 한다. 이 자리에는 SIGCHLD 핸들러가 없고 자식을
/// 거두는 것은 뒤의 감독 루프뿐이라, wait4(pid)가 남에게 뺏기지 않는다.
///
/// nft의 stderr는 따로 안 잡는다. init의 fd 2가 콘솔이라 자식이 그대로
/// 물려받고, 사람의 파일이 틀렸으면 nft가 파일 · 행 · 열을 짚는 그 글자가
/// 콘솔에 그대로 나온다(FW-M0 실측 8).
fn load(path: [:0]const u8, envp: [*:null]const ?[*:0]const u8) bool {
    const pid = linux.fork();
    if (failed(pid)) |e| {
        std.debug.print("tars-init: cannot fork for nft (errno {d})\n", .{@intFromEnum(e)});
        return false;
    }
    if (pid == 0) {
        // 부모의 SIGTERM · SIGINT 핸들러는 execve가 기본값으로 되돌린다. clock.zig가
        // power.resetToDefault()를 부르는 것은 execve 전에 우리 코드가 오래
        // 돌기 때문이고, 이 자식은 곧바로 execve한다.
        const argv = [_:null]?[*:0]const u8{ NFT_PATH.ptr, "-f", path.ptr, null };
        _ = linux.execve(NFT_PATH.ptr, &argv, envp);
        std.debug.print("tars-init: cannot exec {s}\n", .{NFT_PATH});
        linux.exit(127);
    }

    var status: u32 = 0;
    while (true) {
        const rc = linux.wait4(@intCast(pid), &status, 0, null);
        if (failed(rc)) |e| {
            // SA_RESTART가 꺼져 있어(power.zig) 전원 버튼이 이 기다림을 깨운다.
            // 플래그는 이미 섰고 감독 루프가 곧 본다 — 여기서는 다시 기다린다.
            if (e == .INTR) continue;
            std.debug.print("tars-init: waiting for nft failed (errno {d})\n", .{@intFromEnum(e)});
            return false;
        }
        break;
    }
    if (linux.W.IFEXITED(status) and linux.W.EXITSTATUS(status) == 0) return true;
    if (linux.W.IFEXITED(status)) {
        std.debug.print("tars-init: nft -f {s} exited {d}\n", .{ path, linux.W.EXITSTATUS(status) });
    } else {
        std.debug.print("tars-init: nft -f {s} was killed (signal {d})\n", .{
            path, @intFromEnum(linux.W.TERMSIG(status)),
        });
    }
    return false;
}

/// 설정이 실제 동작이 되는 자리. `main()`이 부르는 것은 이 함수 하나이고,
/// `net.bringUp` 앞이어야 한다(design 결정 5).
///
/// 갈래는 `off`까지 넷이고 각각 한 줄을 남긴다. 게이트가 grep하는 것이 이
/// 넷의 앞머리(`tars-init: firewall`)다.
///   off  — nft를 안 부른다
///   1    — 기본 규칙 + 사람의 파일이 섰다
///   2    — 사람의 파일 때문에 1이 실패해서 기본 규칙만 섰다. 닫혀 있다
///   3    — 기본 규칙도 실패했다(nft가 없다 · 커널 옵션이 모자라다). 열려 있다.
///          네트워크를 막는 쪽으로 가지 않는 이유는 design 결정 5의 셋째 항목
pub fn up(want: config.Firewall, envp: [*:null]const ?[*:0]const u8) void {
    if (want == .off) {
        std.debug.print("tars-init: firewall=off, inbound is open\n", .{});
        return;
    }
    if (load(RULES_PATH, envp)) {
        std.debug.print("tars-init: firewall up from {s}, inbound closed but for /config/nftables.d\n", .{RULES_PATH});
        return;
    }
    if (load(BASE_PATH, envp)) {
        std.debug.print("tars-init: firewall up from {s} without /config/nftables.d (nft said why above)\n", .{BASE_PATH});
        return;
    }
    std.debug.print("tars-init: firewall NOT up, inbound is open\n", .{});
}
```

- [ ] Step 2: `init/src/main.zig`를 고친다

import 줄들(`const clock = @import("clock.zig");` 근처)에 한 줄:

```zig
const firewall = @import("firewall.zig");
```

`config` 로그 줄의 형식 문자열 끝 `timezone={s}\n`을 `timezone={s} firewall={s}\n`으로,
인자 `cfg.timezone.slice(),` 뒤에 `@tagName(cfg.firewall),`를 넣는다. 그 위 주석
(`// TS-M1이 여덟째 키를 맨 뒤에 붙였다.`) 끝에 한 줄을 더한다.

```zig
    // FW-M1도 같은 이유로 `firewall=`을 맨 뒤에 붙였다.
```

`net.bringUp(cfg.net, envp);` 바로 위(그 위 NW-M2 주석 블록보다 위)에:

```zig
    // FW-M1. `net.bringUp` 앞인 것이 이 한 줄의 유일한 제약이다(FW design 결정
    // 5) — 규칙이 서기 전에 주소가 붙는 틈을 없앤다. 여기는 기다린다. nft는
    // 로컬 netlink만 쓰므로 부팅이 네트워크에 묶이지 않는다. `/config`가 안
    // 붙었어도 같은 파일을 올린다 — 빈 include는 에러가 아니다(FW-M0 실측 4).
    firewall.up(cfg.firewall, envp);

```

- [ ] Step 3: 빌드한다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c 'zig build 2>&1 | tail -5; zig build test 2>&1 | tail -3'; echo "rc=$?"
git diff --stat
```

기대: 에러 없음. Zig 0.16의 `wait4` · `W.TERMSIG` 시그니처는 `install.zig`가 이미
같은 모양으로 쓰고 있어서 거기와 다르면 거기에 맞춘다.

## Task 6 — 체인 `firewall/check.sh`

- [ ] Step 1: `firewall/check.sh`를 만든다 (실행 권한)

```bash
#!/usr/bin/env bash
# FW 체인. 방화벽이 켜진 기계가 들어오는 TCP를 가르는가를 본다.
#
# 부팅 하나다. 설정 디스크가 셋을 싣는다.
#   tars.conf           net=dhcp · firewall=on
#   nftables.d/allow.nft  tcp dport 7070 accept — 사람이 연 포트 하나
#   fwlisten.sh         게스트에서 리스너 둘(7070 · 7072)을 띄우고 센다
#
# 판정의 재료(어느 포트를 열었나)는 이 파일의 ALLOWED · BLOCKED이고, 판정 대상은
# 게스트 커널에 선 규칙이다. 둘을 같은 파일로 두지 않는다(LB 실측 17).
#
# 우리 코드는 init/src/firewall.zig의 배관뿐이다. 받고 버리는 것은 커널의
# nf_tables이고 규칙을 넣는 것은 nft다(design 결정 2).
set -uo pipefail

cd "$(dirname "$0")"
REPO_ROOT="$(cd .. && pwd)"

source ../gate_lib.sh

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 포트. 45455~45473은 앞의 체인들이 쓴다(monitor 대역 · IN · TS · TD · WN).
MONITOR_PORT=45474
ALLOWED_PORT=45475     # → 게스트 7070, allow.nft가 연다
BLOCKED_PORT=45476     # → 게스트 7072, 아무도 안 연다
GUEST_ALLOWED=7070
GUEST_BLOCKED=7072

DISK="${REPO_ROOT}/out/firewall.img"
LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  rm -f "$LOG"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1"
  shift
  echo "--- markers ---"
  local marker
  for marker in \
    "tars-init: loaded /config/tars.conf" \
    "tars-init: firewall" \
    "tars-init: started dhcpcd (pid" \
    ": leased" \
    "tars-init: started console shell" \
    "terminal: screen>"; do
    if grep -a "$marker" "$LOG" >/dev/null; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  local pattern
  for pattern in "$@"; do
    grep -a "$pattern" "$LOG" | head -3 | sed 's/^/  /' || true
  done
  echo "--- last 60 lines ---"
  tail -n 60 "$LOG"
  exit 1
}

wait_for_log() {
  local pattern="$1" seconds="$2" i
  for i in $(seq 1 "$seconds"); do
    if grep -aE "$pattern" "$LOG" >/dev/null; then return 0; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then return 1; fi
    sleep 1
  done
  return 1
}

# ── 검사 1: 커널에 netfilter 다섯이 있나 ────────────────────────────────
# 부팅 전에 0.01초로 잡는다. 하나라도 빠지면 nft가 기본 규칙을 못 올리고
# init은 갈래 3(열린 채)으로 떨어진다 — 아래 검사 3이 빨갛지만 원인이 멀다.
CONFIG=../kernel/.config
for sym in NETFILTER NF_TABLES NF_TABLES_IPV4 NF_CONNTRACK NFT_CT; do
  if ! grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is not =y in kernel/.config"
    exit 1
  fi
done
echo "the kernel carries the five netfilter options"

# ── 디스크 ───────────────────────────────────────────────────────────
# debugfs가 마운트 없이 ext2에 쓴다(project_seeding_a_config_disk).
mkdir -p "${REPO_ROOT}/out"
SEED="$(mktemp -d)"
printf 'net=dhcp\nfirewall=on\n' > "$SEED/tars.conf"
printf 'tcp dport %s accept\n' "$GUEST_ALLOWED" > "$SEED/allow.nft"
cat > "$SEED/fwlisten.sh" <<'EOF'
#!/bin/bash
# FW 체인이 심는다. 인자가 없으면 리스너 둘을 띄우고 센다. count면 7072가 아직
# 듣고 있는지만 센다. 판정 글자(fwm1-…=)는 출력에만 생기고 친 명령에는 없다.
# /proc/net/tcp는 포트를 16진수 넉 자로 적는다. 손으로 옮기지 않고 printf가
# 바꾼다 — FW-M0과 M1 첫 판이 7070을 1BAE로 잘못 옮겨 0을 셌다(실측 9 · 10).
listening() { grep -c ":$(printf '%04X' "$1") 00000000:0000 0A" /proc/net/tcp; }
if [ "${1:-}" = count ]; then
  echo "fwm1-still=$(listening 7072)"
  exit 0
fi
printf 'fwm1-tcp-a\n' | nc -l -p 7070 >/dev/null 2>&1 &
printf 'fwm1-tcp-c\n' | nc -l -p 7072 >/dev/null 2>&1 &
n=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  n=$(( $(listening 7070) + $(listening 7072) ))
  [ "$n" -ge 2 ] && break
  sleep 0.3
done
echo "fwm1-listen=$n"
EOF
rm -f "$DISK"
truncate -s 16M "$DISK"
mkfs.ext2 -F -q -m 0 -L tars-fw "$DISK"
debugfs -w -R "write $SEED/tars.conf tars.conf" "$DISK" 2>&1 | grep -v '^debugfs' || true
debugfs -w -R "mkdir nftables.d" "$DISK" 2>&1 | grep -v '^debugfs' || true
debugfs -w -R "write $SEED/allow.nft nftables.d/allow.nft" "$DISK" 2>&1 | grep -v '^debugfs' || true
debugfs -w -R "write $SEED/fwlisten.sh fwlisten.sh" "$DISK" 2>&1 | grep -v '^debugfs' || true
rm -rf "$SEED"

echo "=== boot: net=dhcp firewall=on, port ${GUEST_ALLOWED} opened in nftables.d ==="
qemu-system-x86_64 \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${ALLOWED_PORT}-10.0.2.15:${GUEST_ALLOWED},hostfwd=tcp:127.0.0.1:${BLOCKED_PORT}-10.0.2.15:${GUEST_BLOCKED}" \
  -device virtio-net-pci,netdev=n0 \
  -drive file="$DISK",if=virtio,format=raw \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

wait_for_log "terminal: screen>" 120 || fail "terminal never rendered a prompt"

# ── 검사 2: 설정이 firewall=on으로 읽혔나 ─────────────────────────────
grep -aE "tars-init: config shell=.* net=dhcp .* firewall=on" "$LOG" >/dev/null \
  || fail "the config disk did not turn the firewall on" "tars-init: config shell="
echo "the guest read net=dhcp and firewall=on off the config disk"

# ── 검사 3: 갈래 1로 섰나, 그리고 dhcpcd보다 먼저인가 ───────────────────
# 갈래 2 · 3의 줄이 있으면 그 자체로 빨갛다 — 이 부팅의 파일은 틀린 데가 없다.
# 순서는 줄 번호로 본다. design 결정 5의 "규칙이 서기 전에 주소가 붙는 틈이
# 없다"를 로그에서 읽는 방법이 이것이다.
FW_LINE="$(grep -an "tars-init: firewall up from /etc/tars/firewall.nft," "$LOG" | head -1 | cut -d: -f1)"
[ -n "$FW_LINE" ] || fail "init did not bring the firewall up from firewall.nft" "tars-init: firewall" "tars-init: nft"
DHCPCD_LINE="$(grep -an "tars-init: started dhcpcd (pid" "$LOG" | head -1 | cut -d: -f1)"
[ -n "$DHCPCD_LINE" ] || fail "init did not start dhcpcd"
[ "$FW_LINE" -lt "$DHCPCD_LINE" ] \
  || fail "dhcpcd started (line ${DHCPCD_LINE}) before the firewall was up (line ${FW_LINE})"
echo "the firewall came up from firewall.nft before dhcpcd started"

# ── 검사 4: drop 아래에서 lease를 받나 ─────────────────────────────────
# FW-M0 실측 5. 받는 것을 기본으로 버리는 기계가 DHCP의 답까지 버리면 여기서
# 멈춘다.
wait_for_log "eth0: leased 10\.0\.2\.15 " 60 \
  || fail "dhcpcd never leased an address under the firewall" ": leased" "dhcpcd"
echo "dhcpcd leased 10.0.2.15 under policy drop"

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || fail "could not connect to the QEMU monitor"

# ── 검사 5: 게스트가 두 포트를 다 듣나 ─────────────────────────────────
# 이 검사가 있어야 아래 검사 7의 0바이트가 "방화벽이 버렸다"로 읽힌다. 없으면
# "게스트가 안 들었다"와 같은 모양이다.
echo "=== typing 'bash /config/fwlisten.sh' ==="
type_keys b a s h spc slash c o n f i g slash f w l i s t e n dot s h ret
wait_for_screen "fwm1-listen=2" \
  || fail "the guest did not put both ${GUEST_ALLOWED} and ${GUEST_BLOCKED} into LISTEN" "terminal: screen>"
echo "the guest listens on ${GUEST_ALLOWED} and ${GUEST_BLOCKED}"

# ── 검사 6: 연 포트에서 바이트가 오나 ──────────────────────────────────
# rc로 판정하지 않는다(IN 실측 4 — SLIRP은 누구에게나 connect를 준다). 판정은
# 읽은 글자다. fd 5인 이유는 net 체인과 같다(3이 monitor다).
GOT=""
for _ in $(seq 1 10); do
  if exec 5<>"/dev/tcp/127.0.0.1/${ALLOWED_PORT}"; then
    read -r -t 5 GOT <&5 || true
    exec 5<&-
    exec 5>&-
    [ "$GOT" = "fwm1-tcp-a" ] && break
  fi
  sleep 0.2
done
[ "$GOT" = "fwm1-tcp-a" ] \
  || fail "nothing came through the opened port ${GUEST_ALLOWED} (got: [${GOT}])" "terminal: screen>"
echo "the opened port ${GUEST_ALLOWED} let fwm1-tcp-a through"

# ── 검사 7: 안 연 포트에서는 안 오나 ───────────────────────────────────
# 이 체인의 가운데다. 게스트는 7072를 듣고 있는데(검사 5) 규칙이 SYN을 버린다.
# SLIRP은 체인 쪽 연결을 안 끊으므로 read가 타임아웃을 꽉 쓴다(FW-M0 실측 6 —
# 5초를 줬더니 5,012ms). 2초는 양성의 22ms와 멀고, 게이트가 세 번 도는 값이다.
#
# 붙는 것을 따로 본다. 안 보면 hostfwd가 사라진 날에도 초록이다(IN 검사 16과
# 같은 자리).
NEG_CONNECTED=0
NEG_GOT=""
if exec 5<>"/dev/tcp/127.0.0.1/${BLOCKED_PORT}"; then
  NEG_CONNECTED=1
  read -r -t 2 NEG_GOT <&5 || true
  exec 5<&-
  exec 5>&-
fi
[ "$NEG_CONNECTED" = "1" ] \
  || fail "the negative check could not even connect — the hostfwd port ${BLOCKED_PORT} is gone"
[ -z "$NEG_GOT" ] \
  || fail "the unopened port ${GUEST_BLOCKED} let something through (got: [${NEG_GOT}])" "tars-init: firewall"
echo "the unopened port ${GUEST_BLOCKED} let nothing through"

# ── 검사 8: 막힌 쪽 리스너가 아직 살아 있나 ────────────────────────────
# 한 번만 사는 리스너라(IN 결정 7) 연결을 받았으면 죽었다. 7072가 아직 LISTEN이면
# 게스트의 nc까지 연결이 한 번도 안 닿았다는 뜻이다 — 검사 7의 빈 값이 "nc가
# 아무것도 안 보냈다"가 아니라 "nc까지 안 왔다"라는 증거다.
echo "=== typing 'bash /config/fwlisten.sh count' ==="
type_keys b a s h spc slash c o n f i g slash f w l i s t e n dot s h spc c o u n t ret
wait_for_screen "fwm1-still=1" \
  || fail "the listener on ${GUEST_BLOCKED} is gone, so something reached it" "terminal: screen>"
echo "the listener on ${GUEST_BLOCKED} never saw a connection"

echo "system_powerdown" >&3
wait "$QEMU_PID" 2>/dev/null || true
QEMU_PID=""

echo "FW chain PASS"
```

`grep -a … | head -1`은 `-q`가 아니라 `require_no_early_exit_pipe`에 안 걸린다.
검사 3의 두 grep이 `head -1`에서 SIGPIPE를 받아도 `$(...)` 안이라 판정은 `[ -n ]`이 한다.

- [ ] Step 2: `check.sh`의 `CHAINS`에 한 줄

`"WN-M3:./nic/check.sh"` 뒤에:

```bash
  "FW-M1:./firewall/check.sh"
```

- [ ] Step 3: 진입 검사 셋만 먼저 돌려 본다

```bash
bash -c 'source <(sed -n "/^BUILD_STEPS=(/,/^}/p; /^EARLY_EXIT_PIPE=/,/^}/p; /^require_explicit_nic()/,/^}/p" check.sh)
  require_build_steps ./firewall/check.sh && require_no_early_exit_pipe ./firewall/check.sh &&
  require_explicit_nic ./firewall/check.sh && echo ENTRY-OK'
```

기대: `ENTRY-OK`. 소스 발췌가 안 맞으면(함수 경계가 다르면) `check.sh`의 해당 줄을
직접 읽고 같은 셋을 손으로 대조한다.

- [ ] Step 4: 체인을 돌린다 (약 1~2분, 첫 회는 커널 · 이미지 빌드로 더)

```bash
chmod +x firewall/check.sh
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./firewall/check.sh > /tmp/fw-chain.log 2>&1; echo "exit=$?"
grep -E "^(FAIL|the |FW chain|===)" /tmp/fw-chain.log
```

기대: `exit=0`, 초록 줄 여덟과 `FW chain PASS`.

## Task 7 — mutation 셋 (각 약 1분, 커밋하지 않는다)

각 mutation은 고친 뒤 체인을 돌리고, 겨냥한 검사가 겨냥한 문구로 빨간지 본 다음
`git checkout`으로 되돌린다.

- [ ] Step 1: 기본 규칙이 받아들이면 검사 7이 빨갛다

```bash
sd -F 'policy drop;' 'policy accept;' kernel/make_initrd.sh
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./firewall/check.sh 2>&1 | grep -E "^(FAIL|FW chain)"
git checkout kernel/make_initrd.sh
```

기대: `FAIL: the unopened port 7072 let something through (got: [fwm1-tcp-c])`.
`sd`가 두 파일(heredoc 둘)을 다 바꾸므로 갈래 1이 선다 — 검사 3은 초록이다.

- [ ] Step 2: 사람이 안 열면 검사 6이 빨갛다

```bash
sd -F 'debugfs -w -R "write $SEED/allow.nft nftables.d/allow.nft"' ': debugfs -w -R "write $SEED/allow.nft nftables.d/allow.nft"' firewall/check.sh
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./firewall/check.sh 2>&1 | grep -E "^(FAIL|FW chain)"
git checkout firewall/check.sh
```

기대: `FAIL: nothing came through the opened port 7070 (got: [])`. 검사 3은 초록이다
(빈 `nftables.d`는 에러가 아니다 — 실측 4).

`firewall/check.sh`가 아직 커밋 전이라 `git checkout`이 안 되면 `git stash`가 아니라
같은 `sd`를 거꾸로(`': debugfs'` → `'debugfs'`) 한다.

- [ ] Step 3: `firewall=off`면 검사 2가 빨갛다

```bash
sd -F "printf 'net=dhcp\nfirewall=on\n'" "printf 'net=dhcp\nfirewall=off\n'" firewall/check.sh
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./firewall/check.sh > /tmp/fw-cf3.log 2>&1
grep -E "^(FAIL|FW chain)" /tmp/fw-cf3.log; grep -a "tars-init: firewall" /tmp/fw-cf3.log
sd -F "printf 'net=dhcp\nfirewall=off\n'" "printf 'net=dhcp\nfirewall=on\n'" firewall/check.sh
git diff --stat
```

기대: `FAIL: the config disk did not turn the firewall on`, 그리고 마커에
`tars-init: firewall=off, inbound is open`. 되돌린 뒤 `firewall/check.sh`가 Task 6의
내용과 같다.

## Task 8 — 이웃 체인 셋 (합 약 10분)

`config` 로그 줄과 seed 템플릿이 바뀌었고(`config`), 게스트 도구 목록이
바뀌었고(`tools`), 기본값 `off`가 IN의 검사를 그대로 두는지(`net`) 본다.

- [ ] Step 1: 셋을 한 번씩

```bash
for c in config tools net; do
  docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./$c/check.sh > /tmp/fw-$c.log 2>&1
  echo "$c exit=$?"; grep -E "^FAIL" /tmp/fw-$c.log | head -3
done
grep -a "tars-init: firewall" /tmp/fw-net.log | sort | uniq -c
```

기대: 셋 다 `exit=0`. `net` 로그에 `tars-init: firewall=off, inbound is open`이 부팅
수만큼 있다.

## Task 9 — design에 실측을 적고 커밋한다

- [ ] Step 1: design의 "FW-M0이 실행으로 증명한 것" 절 뒤에 "FW-M1이 실행으로 증명한
  것"을 실측 10부터 적는다 — 이미지 · initrd의 실제 바이트, 체인 첫 회의 초록 줄과
  걸린 시간, mutation 셋의 FAIL 줄, 이웃 체인 셋. `Status:`를 "M1 끝났다"로.

- [ ] Step 2: 확인하고 커밋한다

```bash
git status --short
git diff --stat
git diff | grep '^-[^-]'
git add kernel/.config devcontainer/Dockerfile kernel/guest_tools.sh kernel/make_initrd.sh \
        init/src/config.zig init/src/config_test.zig init/src/firewall.zig init/src/main.zig \
        firewall/check.sh check.sh \
        docs/specs/2026-09-27-tars-firewall-design.md \
        docs/plans/2026-09-27-tars-firewall-fw-m1.md
git status --short
git commit -m "Close FW-M1: firewall=on loads nft rules before the network"
```

기대: `-` 줄은 `.config`의 `# CONFIG_NETFILTER is not set`과, 끝에 글자를 더한 줄들
(형식 문자열 · 템플릿 · `CHAINS`의 이웃 없음)의 옛 모양뿐이다. `out/`과 빌드 산출물은
목록에 없다.

## 이 milestone이 끝난 자리

`firewall=on`인 기계가 들어오는 TCP를 가르고, 열다섯번째 체인이 그것을 본다. 다음은
FW-M2 — UDP · 포트 여럿 · 갈래 2의 부팅 · 사용자 가이드 · 루트 게이트.
