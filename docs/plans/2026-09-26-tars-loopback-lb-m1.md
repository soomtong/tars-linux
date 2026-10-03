# LB-M1 — `init`이 `lo`를 올린다

> 이 plan을 실행하는 사람에게: 고치는 코드는 `init/src/net.zig`(함수 하나와 상수 ·
> 구조체)와 `init/src/main.zig`(호출 한 줄)이다. 새 함수는 시스템 콜 셋뿐이라
> 호스트에서 돌릴 순수 로직이 없다 — 그래서 unit test 대신 부팅 한 번이 증명이다.
> 게이트 검사는 M3이 세운다.

Goal: 게스트가 뜨면 설정과 무관하게 `lo`가 UP이고 `127.0.0.1`로 두 프로세스가
주고받는다(design 결정 1~4).

Architecture: `net.zig`에 `pub fn loopbackUp() void`를 둔다. `AF_INET` ·
`SOCK_DGRAM` 소켓으로 `SIOCGIFFLAGS` → `IFF_UP`을 더함 → `SIOCSIFFLAGS`. 주소는 커널이
붙인다(M0 실측 3). `main()`은 `linkDevFd()` 다음, `mountConfig()` 앞에서 부른다.
상수와 `ifreq`는 `1acf9f6`에 있던 것을 그대로 되살린다.

Tech Stack: Zig(`std.os.linux`) · M0의 하네스 `/tmp/lb/`

---

## 모양을 정하는 것 넷

- M1-A 이미 UP이면 쓰지 않는다. `tars-init: lo was already up`을 찍고 끝낸다. M0
  실측 1이 부팅 직후 늘 DOWN임을 보였으니 실제로는 안 나오는 줄이지만, 누가 먼저
  올렸다는 사실이 로그에서 조용히 사라지지 않게 한다(`1acf9f6`의 모양 그대로).
- M1-B 실패 줄은 단계마다 다르다 — 소켓 · 플래그 읽기 · 플래그 쓰기. 셋이 다른
  원인이라서다(소켓 실패는 커널에 INET이 없는 것, 읽기 실패는 `lo`가 없는 것).
- M1-C 성공 줄은 `tars-init: lo up`이다. M3이 grep한다.
- M1-D `failed()` 헬퍼는 `net.zig`에 이미 있다. `sys.zig`로 모으는 일은 이번에도 안
  한다(그 헬퍼 위 주석의 이유 그대로).

## Task 1 — `net.zig`에 `loopbackUp()`을 넣는다

**Files:** Modify `init/src/net.zig` — `failed()` 다음, `// WN-M2.` 주석 블록 앞.

- [ ] Step 1: 상수 · 구조체 · 함수를 넣는다

```zig
// LB-M1. `lo`를 올린다(LB design 결정 1~4). 아래 상수 둘과 `ifreq`는 NW-M1이
// `eth0`을 올리려고 넣었다가 WN-M2가 지운 것(`1acf9f6`)을 그대로 되살린 것이다.
// 그때 그 일은 dhcpcd에게 갔지만 dhcpcd는 `lo`를 안 만진다(WN design 덤).

/// include/uapi/linux/sockios.h. 이름이 아니라 숫자로 적는 이유는 Zig의
/// linux 바인딩에 이 상수가 없기 때문이고, 커널 ABI라 안 바뀐다.
const SIOCGIFFLAGS: u32 = 0x8913;
const SIOCSIFFLAGS: u32 = 0x8914;

/// include/uapi/linux/if.h. IFF_UP 하나만 세운다 — IFF_RUNNING은 커널이
/// 링크 상태를 보고 자기가 세우는 것이라 우리가 쓰면 거짓말이 된다.
const IFF_UP: u16 = 0x1;

/// include/uapi/linux/if.h의 struct ifreq.
///
/// 이름 16바이트 뒤에 오는 것은 union이고 그중 가장 큰 것이 struct
/// sockaddr(16바이트)이다. 그래서 전체가 32바이트다. flags는 그 union의
/// 첫 2바이트를 빌려 쓰는 것이고, 나머지 14바이트는 커널이 안 보지만
/// 구조체 크기가 맞아야 한다.
const ifreq = extern struct {
    name: [16]u8,
    flags: u16,
    _pad: [14]u8,
};

// 크기가 틀리면 게스트에서 `ioctl`이 EINVAL을 내는 것으로만 드러난다.
// 그 실패는 부팅한 뒤에야 보이고 원인에서 멀다 — 컴파일 타임에 못 박는다.
comptime {
    if (@sizeOf(ifreq) != 32)
        @compileError("struct ifreq must be 32 bytes to match the kernel ABI");
}

/// `lo`를 UP으로 올린다. 주소는 안 붙인다 — 커널이 `IFF_UP`을 보고
/// `127.0.0.1/8`을 스스로 붙인다(LB-M0 실측 3).
///
/// `net` 설정을 안 받는다. loopback은 기계 밖으로 나가는 길이 아니라 기계
/// 안의 길이라 `net=off`와 다른 층이고(결정 1), `main()`이 설정을 읽기 전에
/// 부르는 것으로 그것을 구조가 보장한다(결정 3).
///
/// 읽고-고쳐-쓰는 이유는 flags가 비트 묶음이기 때문이다. SIOCSIFFLAGS는
/// 통째로 덮어쓰므로 IFF_UP만 담아 보내면 커널이 세워 둔 다른 비트
/// (`lo`에서는 IFF_LOOPBACK)를 지우게 된다.
///
/// 실패해도 부팅을 안 막는다(결정 4). 그때 사라지는 것은 기계 안의
/// `127.0.0.1`뿐이고, 못 올린 이유는 단계마다 다른 줄로 남는다.
pub fn loopbackUp() void {
    // 인터페이스 ioctl에는 소켓이 필요하다. 어느 소켓이든 되지만
    // AF_INET/SOCK_DGRAM이 관습이다. 여기서 실패하면 커널에 INET이 없다.
    const srv = linux.socket(linux.AF.INET, linux.SOCK.DGRAM, 0);
    if (failed(srv)) |e| {
        std.debug.print("tars-init: cannot open a socket to raise lo (errno {d})\n", .{@intFromEnum(e)});
        return;
    }
    const fd: i32 = @intCast(srv);
    defer _ = linux.close(fd);

    var req = ifreq{ .name = [_]u8{0} ** 16, .flags = 0, ._pad = [_]u8{0} ** 14 };
    @memcpy(req.name[0..2], "lo");

    if (failed(linux.ioctl(fd, SIOCGIFFLAGS, @intFromPtr(&req)))) |e| {
        std.debug.print("tars-init: cannot read the flags of lo (errno {d})\n", .{@intFromEnum(e)});
        return;
    }
    if (req.flags & IFF_UP != 0) {
        std.debug.print("tars-init: lo was already up\n", .{});
        return;
    }

    req.flags |= IFF_UP;
    if (failed(linux.ioctl(fd, SIOCSIFFLAGS, @intFromPtr(&req)))) |e| {
        std.debug.print("tars-init: cannot raise lo (errno {d})\n", .{@intFromEnum(e)});
        return;
    }
    // LB-M3의 검사가 이 줄을 grep한다.
    std.debug.print("tars-init: lo up\n", .{});
}
```

- [ ] Step 2: 빌드한다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer \
  bash -c 'zig build && zig build test && echo BUILD-OK'
```

기대: `BUILD-OK`. `loopbackUp`을 아직 아무도 안 부르므로 Zig의 게으른 분석이 본문을
안 볼 수 있다 — 본문 오류는 Task 2의 빌드에서 잡힌다.

## Task 2 — `main()`에서 부른다

**Files:** Modify `init/src/main.zig` — `linkDevFd();` 다음, `const storage_mounted =
mountConfig();` 앞.

- [ ] Step 1: 한 줄과 주석을 넣는다

```zig
    // LB-M1. 설정을 읽기 전인 것이 이 자리의 뜻이다(LB design 결정 3) — `lo`는
    // `net=off`에도 서고, 설정 디스크가 없거나 깨진 부팅에도 선다. 커널은
    // `lo`를 만들기만 하고 올리지 않으며(LB-M0 실측 1), 보통 리눅스에서 이
    // 일은 PID 1(systemd)이나 init 스크립트의 몫이다.
    net.loopbackUp();
```

- [ ] Step 2: 빌드하고 `git diff`를 읽는다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer \
  bash -c 'zig build && zig build test && echo BUILD-OK'
git diff --stat
git diff | grep '^-[^-]'
```

기대: `BUILD-OK`, 두 파일에 더한 줄만 있고 지운 줄이 없다.

## Task 3 — 부팅으로 본다 (부팅 둘, 각 약 1분)

M0 하네스를 그대로 쓰되 `lo`를 손으로 올리지 않는다. `raise` 단계를 빼고
`before` · `after`만 친다 — 이번 `before`가 `0x9`와 `127.0.0.1/8`을 보여야 한다.

- [ ] Step 1: 단계 목록만 바꾼 하네스를 만든다

```bash
sed -e '/^run names/d' -e '/^run raise/d' -e '/^run nss/d' /tmp/lb/boot.sh > /tmp/lb/boot-m1.sh
chmod +x /tmp/lb/boot-m1.sh
grep '^run ' /tmp/lb/boot-m1.sh
```

기대: `run before`와 `run after` 두 줄.

- [ ] Step 2: 부팅 A(`net=off`)와 B(`net=dhcp`)

```bash
for B in A B; do
  docker run --rm -v "$PWD":/workspace -v /tmp/lb:/tmp/lb -w /workspace \
    tars-devcontainer bash /tmp/lb/boot-m1.sh $B > /tmp/lb/run-m1-$B.log 2>&1; echo "$B exit=$?"
  grep -aE "tars-init: (lo |cannot .*lo|config shell|net=)" /tmp/lb/guest-$B.log | tr -d '\r'
  grep -aoE "LBM0-(LOFLAGS|LOADDRN|NC) .*" /tmp/lb/guest-$B.log | tr -d '\r'
done
```

기대: 두 부팅 모두 `tars-init: lo up`이 `tars-init: config ...`보다 앞에 있고,
`LOFLAGS 0x9`, `LOADDRN 1`, `before`의 `NC`부터 `got=[hello-7001]`, `after`의 둘도
`got`을 받는다.

## Task 4 — 가까운 체인 둘을 돌린다 (약 5분)

`init`의 로그에 줄이 하나 늘었다. 로그를 가장 많이 읽는 `net` 체인과, M3이 검사를
더할 `tools` 체인을 돌려 새 줄이 기존 판정을 안 흔드는지 본다. 루트 게이트
전체(약 42분)는 M3의 끝에서 한 번 돈다.

- [ ] Step 1

```bash
for C in net tools; do
  docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
    bash $C/check.sh > /tmp/lb/chain-$C.log 2>&1; echo "$C exit=$?"
  grep -c '^FAIL' /tmp/lb/chain-$C.log; tail -2 /tmp/lb/chain-$C.log
done
```

기대: 둘 다 `exit=0`, `FAIL` 0줄.

## Task 5 — design에 적고 커밋한다

- [ ] Step 1: design에 "LB-M1이 실행으로 증명한 것" 절을 더하고(실측 번호는 10부터),
  `Status:` 줄을 "M1 끝났다"로 고친다.

- [ ] Step 2: 확인하고 커밋한다

```bash
git status --short
git diff --stat
git add init/src/net.zig init/src/main.zig \
        docs/specs/2026-09-26-tars-loopback-design.md \
        docs/plans/2026-09-26-tars-loopback-lb-m1.md
git commit -m "Close LB-M1: init raises lo before reading the config"
```

## 이 milestone이 끝난 자리

`lo`가 늘 선다. 이름은 아직 안 풀린다(M0 실측 4 그대로) — M2의 일이다.
