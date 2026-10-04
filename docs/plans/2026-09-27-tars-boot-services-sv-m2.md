# SV-M2 — sshd가 첫 서비스로 선다

> 이 plan을 실행하는 사람에게: 순서는 Task 1(이미지 · initrd) → Task 2(`init`의 로그인
> 셸과 ssh env, TDD) → Task 3(execve errno) → Task 4(체인 부팅 B · C) → Task 5(mutation) →
> Task 6(가이드) → Task 7(루트 게이트) → Task 8(닫기)이다. 코드 편집은 Claude가 하고,
> 편집마다 `git diff --stat`으로 더한 줄 · 지운 줄을 세고 지운 줄은 직접 읽는다.

Goal: `ln -s /etc/tars/services/sshd /config/services.d/`와 공개 키 하나로 바깥에서 TARS에
키로 로그인된다. 세션은 콘솔과 같은 셸 · rc · 히스토리 · `TZ`이고(결정 9), Ghostty ·
kitty 같은 터미널의 `TERM`에서 `less`가 멈추지 않는다(결정 8). 호스트 키는 부팅을
넘는다.

Architecture: sshd · `sshd-session` · `sshd-auth` · `ssh-keygen`과 새 라이브러리 일곱을
Dockerfile 층 11과 `guest_tools.sh`로 initrd에 싣는다(M0 실측 1). `make_initrd.sh`가
`sshd_config` · 템플릿 · `passwd`/`group` 두 줄 · `/run/sshd` · terminfo 다섯(둘은
`tic`으로 이름을 더해 굽는다, 실측 14)을 더한다. `init`은 새 파일 `login.zig`로
부팅 때 `/etc/passwd`의 root 셸 자리와 `/etc/ssh/sshd_config.d/tars-env.conf`의
`SetEnv` 한 줄을 쓴다(실측 13). sshd를 띄우는 코드는 `init`에 없다 — M1의
`services.d`가 띄운다.

Tech Stack: Zig 0.16 · bash · Debian 13 `openssh-server` 1:10.0p1 · `ncurses-term` ·
`tic`/`infocmp` · `debugfs` · QEMU · 컨테이너의 `openssh-client`

---

## 이 milestone의 결정

- M2-A. `init`이 쓰는 두 파일은 initramfs의 루트에 쓰고 `/config`에는 안 쓴다 —
  부팅마다 `tars.conf`에서 새로 나온다. sshd를 켜지 않은 기계에서도 쓴다(몇 줄이고,
  `passwd`의 셸 자리는 sshd가 아니어도 로그인 셸을 묻는 모든 것의 답이다). 로그 한 줄:
  `tars-init: login shell /usr/bin/zsh, ssh env in /etc/ssh/sshd_config.d/tars-env.conf`.
- M2-B. `SetEnv`에 옮기는 것은 `init`이 짓는 env 블록의 우리 몫 전부 — `PATH` ·
  `XDG_DATA_HOME` · `TZ` · 셸별 히스토리 env. 로그의 `tars-init: env …` 줄과 같은 목록이다.
  값에 `"`나 줄바꿈이 있으면 파일을 안 쓴다(우리 값에는 없다).
- M2-C. terminfo 다섯 — `xterm-ghostty` · `xterm-kitty`(둘 다 `tic`으로 이름을 더한다),
  `alacritty` · `wezterm` · `foot`(`ncurses-term`에서 그대로), 그리고 `tmux-256color` ·
  `screen-256color`(`ncurses-base`에 이미 있다 — 복사만). 합해 일곱 파일 · 30KB 안팎.
- M2-D. 템플릿 `/etc/tars/services/sshd`는 `#!/bin/sh`(M1 실측 9). 호스트 키가 없으면
  `/config/ssh`를 만들고(700) 키를 굽고 `sshd: generated a host key in /config/ssh`를,
  언제나 `sshd: host key <지문>`을 찍고 `exec sshd -D -e`한다. 두 줄이 콘솔로 가서
  게이트의 판정 재료가 된다.
- M2-E. `sshd_config` — 첫 줄 `Include /etc/ssh/sshd_config.d/*.conf`, 그리고 design 결정
  6의 다섯 줄과 `KbdInteractiveAuthentication no`. lastlog 소음(M0 실측 5)은 그대로 둔다.
- M2-F. `execve … failed` 줄에 `(errno N)`을 붙인다(M1 실측 9). `config/check.sh:1422`의
  grep은 부분 문자열이라 안 깨진다.
- M2-G. 체인의 부팅 B · C. 포트 — monitor B `45483` · C `45484`, ssh `45485` → 게스트 22.
  - B — `net=dhcp` · `shell=zsh` · `firewall=on`, `ssh.nft` 없음. sshd가 뜨고 키를 굽는데
    바깥에서 붙으면 아무것도 안 온다(방화벽). 키 지문을 콘솔에서 읽는다.
  - 부팅 사이에 `debugfs`로 `nftables.d/ssh.nft`(`tcp dport 22 accept`)를 더한다.
  - C — 같은 디스크. 키를 다시 안 굽고 지문이 B와 같다. `ssh-keyscan` 지문도 같다.
    등록한 키로 로그인되고 세션이 `zsh|/usr/bin/zsh|/usr/bin:/bin|/config/zsh_history`다.
    모르는 키는 255. `TERM=xterm-ghostty`의 `less`가 경고 없이 `rc=0`.

## 파일

| 파일 | 무엇 |
|---|---|
| `devcontainer/Dockerfile` | 기본 apt에 `openssh-client`(게이트의 `ssh`) · 층 11 패키지 |
| `kernel/guest_tools.sh` | 층 11 — 실행 파일 넷 |
| `kernel/make_initrd.sh` | `passwd`/`group` 줄 · `/run/sshd` · `sshd_config` · 템플릿 · terminfo |
| `init/src/login.zig` (새) · `init/src/login_test.zig` (새) · `init/build.zig` | 로그인 셸과 ssh env |
| `init/src/main.zig` | `login.apply` 호출 · execve errno |
| `service/check.sh` | 부팅 B · C |
| `docs/guides/running-tars.md` | "부팅 때 뜨는 서비스와 ssh" 절 |

## Task 1 — 이미지와 initrd

- [ ] Step 1: Dockerfile

기본 apt 목록(`RUN apt-get update && apt-get install -y --no-install-recommends \`)의
`zstd \` 뒤에 `openssh-client \`를 더하고 그 위에 주석 한 줄:

```dockerfile
        # SV-M2: service 체인이 게스트의 sshd에 붙는 ssh · ssh-keyscan · ssh-keygen.
        openssh-client \
```

(주석이 목록 가운데 들어가면 줄 잇기가 끊기는지 먼저 본다 — Dockerfile은 `\` 뒤의
주석 줄을 건너뛰지만, 끊기면 주석을 목록 위 `RUN` 앞으로 옮긴다.)

층 10 주석 블록 뒤, `ENV AMD64_SYSROOT` 앞에:

```dockerfile
# ── SV-M2: 층 11(sshd) ───────────────────────────────────────────────
#
# sshd와 ssh-keygen, sshd가 연결마다 exec하는 sshd-session · sshd-auth(10.0부터 셋으로
# 갈렸다). 재귀 DT_NEEDED 스물하나 중 열넷은 앞 층들에 이미 있고(Kerberos 계열은 curl ·
# git이 들여놓았다) 새것은 일곱, 2,124,688바이트다. 그 74%가 libsqlite3이고
# sshd-session → libwtmpdb → sqlite로 온다(SV-M0 실측 1). ncurses-term은 게스트에
# 넣지 않는다 — make_initrd.sh가 거기서 terminfo 다섯을 골라 굽는다(SV 결정 8).
```

`apt-get download` 목록의 `tzdata)` 앞에:

```dockerfile
        openssh-server:amd64 \
        openssh-client:amd64 \
        libwtmpdb0:amd64 \
        libsqlite3-0:amd64 \
        libcap-ng0:amd64 \
        libwrap0:amd64 \
        libpam0g:amd64 \
        libaudit1:amd64 \
        libcrypt1:amd64 \
        ncurses-term \
```

- [ ] Step 2: 이미지를 다시 굽는다 (약 10~20분)

```bash
{ time docker build -t tars-devcontainer devcontainer/ > /tmp/sv/docker-build.log 2>&1 ; } 2>&1 | tail -3
tail -5 /tmp/sv/docker-build.log
docker run --rm tars-devcontainer bash -c 'command -v ssh ssh-keyscan tic; S=$AMD64_SYSROOT; ls -la $S/usr/sbin/sshd $S/usr/lib/openssh/sshd-session $S/usr/lib/openssh/sshd-auth $S/usr/bin/ssh-keygen $S/usr/share/terminfo/g/ghostty'
```

기대: 다섯 파일과 세 명령이 다 있다. 패키지 이름이 틀려 `apt-get download`가 멈추면
그 줄을 고친다(M0에서 본 `Architecture: all` 문제는 `ncurses-term`처럼 접미사를 안
붙이면 된다).

- [ ] Step 3: `guest_tools.sh` 층 11

`usr/sbin/nft:usr/bin/nft` 줄 뒤(배열의 `)` 앞)에:

```bash

  # ── 층 11 · sshd(SV-M2) ─────────────────────────────────────────────
  # sshd는 dhcpcd처럼 /usr/sbin에 살아서 /usr/bin으로 옮긴다(PATH가 /usr/bin:/bin).
  # sshd-session · sshd-auth는 sshd에 컴파일된 경로(/usr/lib/openssh/) 그대로여야
  # 한다 — 옮기면 연결마다 exec가 실패한다(SV-M0 실측 1). 사람이 부르는 이름이
  # 아니지만 install_tool이 라이브러리까지 따라가 주므로 이 목록에 둔다.
  usr/sbin/sshd:usr/bin/sshd
  usr/lib/openssh/sshd-session:usr/lib/openssh/sshd-session
  usr/lib/openssh/sshd-auth:usr/lib/openssh/sshd-auth
  usr/bin/ssh-keygen:usr/bin/ssh-keygen
```

- [ ] Step 4: `make_initrd.sh` — `passwd` · `group`

`cat > "$WORKDIR/etc/passwd" <<'EOF'`의 root 줄 뒤에
`sshd:x:100:65534::/run/sshd:/usr/sbin/nologin`, group의 root 줄 뒤에 `nogroup:x:65534:`.
heredoc 위 주석에 한 문단:

```bash
# SV-M2: sshd의 privilege separation 사용자와 그 그룹. 없으면 sshd가
# "Privilege separation user sshd does not exist"로 안 뜬다(SV-M0 실측 4).
# /usr/sbin/nologin은 게스트에 없지만 sshd는 그 자리를 실행하지 않는다.
# root 줄의 셸 자리는 부팅 때 init이 tars.conf의 셸로 다시 쓴다(SV 결정 9).
```

- [ ] Step 5: `make_initrd.sh` — sshd 자리 · 설정 · 템플릿

FW의 `firewall-base.nft` heredoc 블록 뒤에:

```bash
# SV-M2. sshd의 자리 셋과 템플릿(SV design 결정 6).
#   /run/sshd                        privsep 디렉터리. 비어 있어야 한다(SV-M0 실측 4)
#   /etc/ssh/sshd_config             키는 /config/ssh에, 비밀번호는 없다
#   /etc/ssh/sshd_config.d/          init이 부팅 때 tars-env.conf를 쓴다(SV 결정 9)
#   /etc/tars/services/sshd          사람이 /config/services.d에 링크로 켠다
mkdir -p "$WORKDIR/run/sshd" "$WORKDIR/etc/ssh/sshd_config.d" "$WORKDIR/etc/tars/services"
chmod 755 "$WORKDIR/run/sshd"
cat > "$WORKDIR/etc/ssh/sshd_config" <<'EOF'
# TARS sshd (SV design decision 6). Do not edit; this file comes from the initrd.
# init writes sshd_config.d/tars-env.conf at boot so sessions get the console's env.
Include /etc/ssh/sshd_config.d/*.conf
HostKey /config/ssh/ssh_host_ed25519_key
AuthorizedKeysFile /config/ssh/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
UsePAM no
EOF
cat > "$WORKDIR/etc/tars/services/sshd" <<'EOF'
#!/bin/sh
# TARS sshd service (SV design decision 6). Turn it on with
#   ln -s /etc/tars/services/sshd /config/services.d/sshd
# and put your public key in /config/ssh/authorized_keys. With firewall=on, also
# open port 22 in /config/nftables.d/ (for example: tcp dport 22 accept).
key=/config/ssh/ssh_host_ed25519_key
if [ ! -e "$key" ]; then
  mkdir -p /config/ssh && chmod 700 /config/ssh || exit 1
  ssh-keygen -q -t ed25519 -N '' -C 'tars host key' -f "$key" || exit 1
  echo "sshd: generated a host key in /config/ssh"
fi
echo "sshd: host key $(ssh-keygen -l -f "$key.pub")"
exec /usr/bin/sshd -D -e -f /etc/ssh/sshd_config
EOF
chmod 755 "$WORKDIR/etc/tars/services/sshd"
```

- [ ] Step 6: `make_initrd.sh` — terminfo

xterm-256color를 복사하는 줄 뒤에:

```bash
# SV-M2 결정 8. ssh로 붙는 사람의 터미널이 보내는 이름들. 없으면 less가
# "terminal is not fully functional"을 찍고 RETURN을 기다린다(SV-M0 실측 7).
# ncurses-term 통째(1,802개 · 12MB)가 아니라 흔한 것만 고른다.
#
# xterm-ghostty · xterm-kitty는 Debian의 ncurses-term에 없다 — ghostty · kitty라는
# 이름으로만 있다. infocmp로 풀어 첫 줄에 이름을 더하고 tic으로 다시 굽는다
# (SV 실측 14). tic은 컨테이너(arm64)의 것이지만 terminfo는 형식이 정해진
# 바이트라 게스트에서 그대로 읽힌다.
TI_SRC="$SYSROOT/usr/share/terminfo"
for pair in ghostty:xterm-ghostty kitty:xterm-kitty; do
  base="${pair%%:*}" alias="${pair#*:}"
  infocmp -x -A "$TI_SRC" "$base" | sed "s/^${base}|/${alias}|${base}|/" > "$WORKDIR/ti.src"
  tic -x -o "$WORKDIR/usr/share/terminfo" "$WORKDIR/ti.src"
done
rm -f "$WORKDIR/ti.src"
for t in a/alacritty w/wezterm f/foot t/tmux-256color s/screen-256color; do
  mkdir -p "$WORKDIR/usr/share/terminfo/${t%%/*}"
  cp "$TI_SRC/$t" "$WORKDIR/usr/share/terminfo/$t"
done
```

- [ ] Step 7: initrd를 굽고 들어간 것을 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  (cd init && zig build) && (cd terminal && ./prepare.sh >/dev/null) && (cd kernel && ./make_initrd.sh >/dev/null) &&
  zcat kernel/initrd.cpio | cpio -it 2>/dev/null | grep -E "sshd|ssh-keygen|openssh|terminfo/./(xterm-ghostty|xterm-kitty|alacritty|wezterm|foot|tmux|screen)|etc/ssh|services/sshd|run/sshd|lib(wtmpdb|sqlite3|cap-ng|wrap|pam|audit|crypt)\." | sort'
ls -la kernel/initrd.cpio
```

기대: 실행 파일 넷 · 라이브러리 일곱 · terminfo 일곱(+ `g/ghostty` · `k/kitty` 링크) ·
`etc/ssh/sshd_config` · `etc/ssh/sshd_config.d` · `etc/tars/services/sshd` · `run/sshd`.
`initrd.cpio` 크기를 43,799,286바이트(M0)와 비교해 적는다.

- [ ] Step 8: 커밋

```bash
git add devcontainer/Dockerfile kernel/guest_tools.sh kernel/make_initrd.sh
git diff --cached --stat
git commit -m "Carry sshd, its template and five terminfo entries in the initrd"
```

## Task 2 — `init/src/login.zig` (TDD)

Files: Create `init/src/login_test.zig` · `init/src/login.zig`, Modify `init/build.zig`.

- [ ] Step 1: 검사를 쓴다

`init/src/login_test.zig`:

```zig
const std = @import("std");
const linux = std.os.linux;
const login = @import("login.zig");

const ROOT = "/tmp/tars-login-test";
const PASSWD = ROOT ++ "/passwd";
const ENV = ROOT ++ "/tars-env.conf";

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

fn writeFile(path: [:0]const u8, text: []const u8) !void {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    if (failed(rc)) |_| return error.OpenFailed;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    if (linux.write(fd, text.ptr, text.len) != text.len) return error.WriteFailed;
}

fn readFile(path: [:0]const u8, buf: []u8) ![]const u8 {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |_| return error.OpenFailed;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    const n = linux.read(fd, buf.ptr, buf.len);
    if (failed(n)) |_| return error.ReadFailed;
    return buf[0..n];
}

fn expectEql(what: []const u8, got: []const u8, want: []const u8) !void {
    if (!std.mem.eql(u8, got, want)) {
        std.debug.print("FAIL: {s}\n--- got ---\n{s}\n--- want ---\n{s}\n", .{ what, got, want });
        return error.Mismatch;
    }
}

const PASSWD_IN =
    "root:x:0:0:root:/:/bin/sh\n" ++
    "sshd:x:100:65534::/run/sshd:/usr/sbin/nologin\n";

pub fn main() !void {
    // ── passwd의 root 셸 자리만 바뀐다 ───────────────────────────────
    var out: [512]u8 = undefined;
    const replaced = login.replaceRootShell(PASSWD_IN, "/usr/bin/zsh", &out) orelse {
        std.debug.print("FAIL: replaceRootShell gave up on a normal passwd\n", .{});
        return error.NoResult;
    };
    try expectEql("root's shell", replaced,
        "root:x:0:0:root:/:/usr/bin/zsh\n" ++
        "sshd:x:100:65534::/run/sshd:/usr/sbin/nologin\n");
    // 두 번 해도 같다 — 부팅은 initramfs의 원본에서 시작하지만, 함수는 멱등이어야 한다.
    var out2: [512]u8 = undefined;
    const again = login.replaceRootShell(replaced, "/usr/bin/zsh", &out2).?;
    try expectEql("idempotent", again, replaced);
    if (login.replaceRootShell("sshd:x:100:65534::/run/sshd:/x\n", "/usr/bin/zsh", &out) != null) {
        std.debug.print("FAIL: a passwd without root must give null\n", .{});
        return error.NoRootAccepted;
    }
    var tiny: [8]u8 = undefined;
    if (login.replaceRootShell(PASSWD_IN, "/usr/bin/zsh", &tiny) != null) {
        std.debug.print("FAIL: a buffer too small must give null\n", .{});
        return error.Overflow;
    }
    std.debug.print("login_test: only root's shell field changes\n", .{});

    // ── SetEnv 한 줄 ───────────────────────────────────────────────
    const entries = [_][]const u8{
        "PATH=/usr/bin:/bin",
        "XDG_DATA_HOME=/config/xdg",
        "TZ=Asia/Seoul",
        "HISTFILE=/config/zsh_history",
    };
    const env = login.renderSetEnv(&out, &entries) orelse {
        std.debug.print("FAIL: renderSetEnv gave up\n", .{});
        return error.NoResult;
    };
    try expectEql("SetEnv", env,
        login.SETENV_HEADER ++
        "SetEnv PATH=\"/usr/bin:/bin\" XDG_DATA_HOME=\"/config/xdg\" TZ=\"Asia/Seoul\" HISTFILE=\"/config/zsh_history\"\n");
    const bad = [_][]const u8{"TZ=a\"b"};
    if (login.renderSetEnv(&out, &bad) != null) {
        std.debug.print("FAIL: a value with a quote must give null\n", .{});
        return error.QuoteAccepted;
    }
    const noeq = [_][]const u8{"JUSTANAME"};
    if (login.renderSetEnv(&out, &noeq) != null) {
        std.debug.print("FAIL: an entry without = must give null\n", .{});
        return error.NoEqAccepted;
    }
    std.debug.print("login_test: the env becomes one quoted SetEnv line\n", .{});

    // ── apply가 두 파일을 쓴다 ─────────────────────────────────────
    _ = linux.mkdir(ROOT, 0o755);
    try writeFile(PASSWD, PASSWD_IN);
    _ = linux.unlink(ENV);
    login.apply(PASSWD, ENV, "/usr/bin/bash", &entries);
    var rb: [512]u8 = undefined;
    try expectEql("passwd on disk", try readFile(PASSWD, &rb),
        "root:x:0:0:root:/:/usr/bin/bash\n" ++
        "sshd:x:100:65534::/run/sshd:/usr/sbin/nologin\n");
    var rb2: [512]u8 = undefined;
    try expectEql("env on disk", try readFile(ENV, &rb2), env);
    std.debug.print("login_test: apply writes both files\n", .{});
}
```

- [ ] Step 2: `build.zig` — `services_test` 블록 뒤에 같은 모양으로 `login_test`
  (`src/login_test.zig`, host_target) · `test_step.dependOn(&b.addRunArtifact(login_test).step);`

- [ ] Step 3: 빨간 것을 본다 — `zig build test`가 `unable to load 'login.zig'`

- [ ] Step 4: `init/src/login.zig`

```zig
//! SV-M2 결정 9. ssh로 붙은 세션이 콘솔과 같은 셸 · 같은 env를 갖게 한다.
//!
//! sshd는 세션의 셸을 `/etc/passwd`에서, env를 자기 설정의 `SetEnv`에서 얻는다 —
//! `init`의 env 블록은 sshd에서 멈춘다(SV-M0 실측 6). 그래서 부팅 때 둘을 쓴다.
//! 둘 다 initramfs의 루트에 쓰고 `/config`에는 안 쓴다 — 부팅마다 `tars.conf`에서
//! 새로 나온다(M2-A). sshd를 안 켠 기계에서도 쓴다.
const std = @import("std");
const linux = std.os.linux;

pub const PASSWD_PATH: [:0]const u8 = "/etc/passwd";
pub const SSH_ENV_PATH: [:0]const u8 = "/etc/ssh/sshd_config.d/tars-env.conf";

/// 파일 머리. 사람이 이 파일을 고치고 싶어질 때 어디를 봐야 하는지 적는다.
pub const SETENV_HEADER = "# Written by tars-init at boot from tars.conf (SV design decision 9).\n";

/// `make_initrd.sh`의 passwd는 두 줄 · 100바이트 안팎이다.
const PASSWD_MAX: usize = 1024;
const ENV_MAX: usize = 1024;

fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// `root:` 줄의 마지막 필드(셸)만 `shell`로 바꾼 사본을 `out`에 짓는다. root 줄이
/// 없거나 자리가 모자라면 null.
pub fn replaceRootShell(in: []const u8, shell: []const u8, out: []u8) ?[]const u8 {
    var len: usize = 0;
    var found = false;
    var lines = std.mem.splitScalar(u8, in, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) {
            if (len >= out.len) return null;
            out[len] = '\n';
            len += 1;
        }
        first = false;
        var piece: []const u8 = line;
        var tail: []const u8 = "";
        if (std.mem.startsWith(u8, line, "root:")) {
            const colon = std.mem.lastIndexOfScalar(u8, line, ':') orelse return null;
            piece = line[0 .. colon + 1];
            tail = shell;
            found = true;
        }
        if (len + piece.len + tail.len > out.len) return null;
        @memcpy(out[len..][0..piece.len], piece);
        len += piece.len;
        @memcpy(out[len..][0..tail.len], tail);
        len += tail.len;
    }
    return if (found) out[0..len] else null;
}

/// `NAME=VALUE`들을 `SetEnv NAME="VALUE" …` 한 줄로 `out`에 짓는다. `=`가 없거나 값에
/// `"` · 줄바꿈이 있으면 null — 따옴표를 벗기는 규칙을 우리가 새로 만들지 않는다(M2-B).
pub fn renderSetEnv(out: []u8, entries: []const []const u8) ?[]const u8 {
    var w: std.Io.Writer = .fixed(out);
    w.writeAll(SETENV_HEADER ++ "SetEnv") catch return null;
    for (entries) |e| {
        const eq = std.mem.indexOfScalar(u8, e, '=') orelse return null;
        const value = e[eq + 1 ..];
        if (std.mem.indexOfAny(u8, value, "\"\n") != null) return null;
        w.print(" {s}=\"{s}\"", .{ e[0..eq], value }) catch return null;
    }
    w.writeAll("\n") catch return null;
    return w.buffered();
}

fn readAll(path: [:0]const u8, buf: []u8) ?[]const u8 {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, 0);
    if (failed(rc)) |_| return null;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var len: usize = 0;
    while (len < buf.len) {
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return null;
        }
        if (n == 0) return buf[0..len];
        len += n;
    }
    return null; // 버퍼가 찼다 — 파일이 생각보다 크다
}

fn writeAll(path: [:0]const u8, text: []const u8) bool {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, 0o644);
    if (failed(rc)) |_| return false;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);
    var done: usize = 0;
    while (done < text.len) {
        const n = linux.write(fd, text[done..].ptr, text.len - done);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return false;
        }
        done += n;
    }
    return true;
}

/// 두 파일을 쓴다. 무엇이 실패해도 반환한다 — 이것이 안 되면 ssh 세션이 SV 전과
/// 같은 `/bin/sh`와 sshd 기본 env가 될 뿐이고, 부팅은 계속된다.
pub fn apply(
    passwd_path: [:0]const u8,
    env_path: [:0]const u8,
    shell_path: []const u8,
    entries: []const []const u8,
) void {
    var in_buf: [PASSWD_MAX]u8 = undefined;
    var out_buf: [PASSWD_MAX]u8 = undefined;
    const passwd_ok = blk: {
        const in = readAll(passwd_path, &in_buf) orelse break :blk false;
        const out = replaceRootShell(in, shell_path, &out_buf) orelse break :blk false;
        break :blk writeAll(passwd_path, out);
    };
    var env_buf: [ENV_MAX]u8 = undefined;
    const env_ok = blk: {
        const text = renderSetEnv(&env_buf, entries) orelse break :blk false;
        break :blk writeAll(env_path, text);
    };
    if (passwd_ok and env_ok) {
        std.debug.print("tars-init: login shell {s}, ssh env in {s}\n", .{ shell_path, env_path });
    } else {
        std.debug.print("tars-init: login shell {s} {s}, ssh env {s}\n", .{
            shell_path,
            if (passwd_ok) "set" else "NOT set",
            if (env_ok) "written" else "NOT written",
        });
    }
}
```

`std.Io.Writer.fixed`가 0.16에서 이름이 다르면 `std.fmt.bufPrint`를 이어 붙이는 모양으로
바꾸고 plan에 적는다.

- [ ] Step 5: 초록 — `zig build test`의 `login_test:` 세 줄

- [ ] Step 6: 커밋 `Add login.zig: root's shell and sshd SetEnv from the env block`

## Task 3 — `main.zig`

- [ ] Step 1: import `const login = @import("login.zig");`

- [ ] Step 2: env 로그 블록(`} else { … env unchanged …}`) 뒤에:

```zig
    // SV-M2 결정 9. ssh 세션이 콘솔과 같은 셸 · 같은 env를 갖게 한다. `shell`은
    // `resolveShell` 뒤의 값이다 — 위 `HISTFILE`이 폴백 뒤의 셸을 보는 것과 같은
    // 이유다. 서비스(sshd)가 뜨기 전이어야 하므로 `supervise`보다 앞이면 되고, env
    // 블록과 나란히 두는 것이 "같은 목록"(M2-B)을 읽기에 맞다.
    var ssh_env: [3 + 4][]const u8 = undefined;
    var ssh_env_len: usize = 0;
    for ([_][]const u8{ environ.PATH_ENTRY, environ.XDG_ENTRY, tz_entry }) |e| {
        ssh_env[ssh_env_len] = e;
        ssh_env_len += 1;
    }
    for (shell.histEntries()) |e| {
        ssh_env[ssh_env_len] = e;
        ssh_env_len += 1;
    }
    login.apply(login.PASSWD_PATH, login.SSH_ENV_PATH, shell_path, ssh_env[0..ssh_env_len]);
```

`histEntries()`의 가장 긴 것(zsh)이 셋이라 `3 + 4`로 한 칸 남는다. 넘으면 인덱스가
범위를 벗어나 ReleaseSafe가 패닉한다 — `config.zig`의 목록을 늘리는 사람이 여기서 걸린다.

- [ ] Step 3: `spawn`의 execve 실패 줄(M2-F):

```zig
        const exec_rc = linux.execve(c.path.ptr, &c.argv, envp);
        // execve가 돌아왔다는 것은 실패했다는 뜻이다. errno가 원인을 가른다 —
        // 2(ENOENT)는 파일이나 shebang의 인터프리터가 없는 것, 13(EACCES)은 실행
        // 비트가 없는 것이다(SV-M1 실측 9).
        std.debug.print("tars-init: execve {s} failed (errno {d})\n", .{
            c.path, @intFromEnum(linux.errno(exec_rc)),
        });
```

- [ ] Step 4: `zig build` · `zig build test` · `git diff --stat` · 지운 줄 확인 · 커밋
  `Write root's login shell and sshd's env at boot; name execve's errno`

## Task 4 — 체인에 부팅 B · C

- [ ] Step 1: `service/check.sh`의 `echo "SV chain PASS"` 앞에 부팅 B · C를 더한다.
  디스크는 새로 굽는다(`out/service-ssh.img`). 부팅 A의 `fail` · `wait_for_log` ·
  `line_of`를 그대로 쓰고, `LOG`를 새 파일로 돌린다. 머리 주석의 "부팅 하나다"를
  "부팅 셋이다"로 고치고 B · C의 디스크를 적는다.

```bash
# ── 부팅 B · C: sshd ──────────────────────────────────────────────────
MONITOR_PORT_B=45483
MONITOR_PORT_C=45484
SSH_PORT=45485     # → 게스트 22
SSH_DISK="${REPO_ROOT}/out/service-ssh.img"
KEYS="$(mktemp -d)"
ssh-keygen -q -t ed25519 -N '' -C sv-good -f "$KEYS/good"
ssh-keygen -q -t ed25519 -N '' -C sv-bad -f "$KEYS/bad"
SSHO=(-p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=5 -o IdentitiesOnly=yes
      -o StrictHostKeyChecking=no -o UserKnownHostsFile="$KEYS/known_hosts")

# 사람이 할 일 둘을 그대로 한다 — 링크 하나와 공개 키 하나. authorized_keys의
# 모드는 debugfs write가 원본을 따르므로 여기서 600으로 둔다(SV-M0 실측 2).
SEED="$(mktemp -d)"
printf 'net=dhcp\nshell=zsh\nfirewall=on\n' > "$SEED/tars.conf"
cp "$KEYS/good.pub" "$SEED/authorized_keys"; chmod 600 "$SEED/authorized_keys"
printf 'tcp dport 22 accept\n' > "$SEED/ssh.nft"
rm -f "$SSH_DISK"; truncate -s 16M "$SSH_DISK"
mkfs.ext2 -F -q -m 0 -L tars-sv "$SSH_DISK"
sdbg() { debugfs -w -R "$1" "$SSH_DISK" 2>&1 | grep -v '^debugfs' || true; }
sdbg "write $SEED/tars.conf tars.conf"
sdbg "mkdir services.d"
sdbg "symlink services.d/sshd /etc/tars/services/sshd"
sdbg "mkdir ssh"
sdbg "sif ssh mode 040700"
sdbg "write $SEED/authorized_keys ssh/authorized_keys"
sdbg "mkdir nftables.d"

boot_ssh() {  # $1 = monitor 포트
  qemu-system-x86_64 \
    -m "$GUEST_MEM" \
    -kernel ../kernel/build/arch/x86/boot/bzImage \
    -initrd ../kernel/initrd.cpio \
    -append "console=ttyS0" \
    -vga none \
    -device virtio-gpu-pci \
    -display none \
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-10.0.2.15:22" \
    -device virtio-net-pci,netdev=n0 \
    -drive file="$SSH_DISK",if=virtio,format=raw \
    -serial file:"$LOG" \
    -monitor tcp:127.0.0.1:$1,server,nowait \
    -no-reboot &
  QEMU_PID=$!
  wait_for_log "terminal: screen>" 120 || fail "terminal never rendered a prompt"
  local ok=0
  for _ in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/$1"; then ok=1; break; fi
    sleep 0.5
  done
  [ "$ok" = "1" ] || fail "could not connect to the QEMU monitor"
  wait_for_log "eth0: leased 10\.0\.2\.15 " 60 || fail "dhcpcd never leased an address" ": leased"
}

stop_ssh() {
  echo "system_powerdown" >&3
  wait "$QEMU_PID" 2>/dev/null || true
  QEMU_PID=""
  exec 3<&-
  exec 3>&-
}

echo "=== boot B: sshd linked, firewall=on without ssh.nft ==="
rm -f "$LOG"   # 부팅 A의 로그. cleanup은 마지막 LOG 하나만 지운다
LOG="$(mktemp)"
boot_ssh "$MONITOR_PORT_B"

# ── 검사 9: init이 로그인 셸과 ssh env를 썼다 ───────────────────────────
grep -a "tars-init: login shell /usr/bin/zsh, ssh env in /etc/ssh/sshd_config.d/tars-env.conf" "$LOG" >/dev/null \
  || fail "init did not write the login shell and the ssh env" "tars-init: login shell"
echo "init set root's shell to zsh and wrote sshd's env"

# ── 검사 10: 링크 하나로 sshd가 떴고, 첫 부팅이라 키를 구웠다 ──────────────
wait_for_log "Server listening on 0\.0\.0\.0 port 22\." 30 \
  || fail "sshd never listened" "service sshd" "sshd:"
grep -a "sshd: generated a host key in /config/ssh" "$LOG" >/dev/null \
  || fail "the template did not generate a host key on the first boot" "sshd:"
FP_B="$(grep -aoE "sshd: host key 256 SHA256:[A-Za-z0-9+/]+" "$LOG" | head -1 | sed 's/.*SHA256:/SHA256:/')"
[ -n "$FP_B" ] || fail "the template did not print the host key" "sshd:"
echo "the linked template started sshd and generated ${FP_B}"

# ── 검사 11: 방화벽이 22를 막는다 ────────────────────────────────────────
# ssh.nft가 없으므로 등록한 키로도 아무것도 안 온다. SLIRP은 막힌 연결을 안 끊으므로
# (FW-M0 실측 6) ssh는 배너를 기다리다 ConnectTimeout에 걸린다.
if timeout 15 ssh "${SSHO[@]}" -i "$KEYS/good" root@127.0.0.1 true >/dev/null 2>&1; then
  fail "firewall=on without ssh.nft still let an ssh login through"
fi
echo "with firewall=on and no ssh.nft, port 22 stayed shut"
stop_ssh
B_LOG="$LOG"

sdbg "write $SEED/ssh.nft nftables.d/ssh.nft"
rm -rf "$SEED"

echo "=== boot C: the same disk plus nftables.d/ssh.nft ==="
LOG="$(mktemp)"
boot_ssh "$MONITOR_PORT_C"
wait_for_log "Server listening on 0\.0\.0\.0 port 22\." 30 || fail "sshd never listened" "sshd:"

# ── 검사 12: 키를 다시 안 구웠고 지문이 같다 ────────────────────────────
if grep -a "sshd: generated a host key" "$LOG" >/dev/null; then
  fail "the host key was generated again on the second boot" "sshd:"
fi
FP_C="$(grep -aoE "sshd: host key 256 SHA256:[A-Za-z0-9+/]+" "$LOG" | head -1 | sed 's/.*SHA256:/SHA256:/')"
[ "$FP_C" = "$FP_B" ] || fail "the host key changed across boots (${FP_B} -> ${FP_C})" "sshd:"
SCAN="$(ssh-keyscan -p "$SSH_PORT" -t ed25519 127.0.0.1 2>/dev/null | ssh-keygen -lf - | awk '{print $2}')"
[ "$SCAN" = "$FP_B" ] || fail "ssh-keyscan saw ${SCAN}, the guest printed ${FP_B}"
echo "the host key survived the reboot and is what the client sees"

# ── 검사 13: 등록한 키로 로그인되고 세션이 콘솔과 같다 ──────────────────────
GOT="$(ssh "${SSHO[@]}" -i "$KEYS/good" root@127.0.0.1 \
  'printf "sv-ssh %s|%s|%s|%s\n" "$0" "$SHELL" "$PATH" "$HISTFILE"' 2>/dev/null)"
[ "$GOT" = "sv-ssh zsh|/usr/bin/zsh|/usr/bin:/bin|/config/zsh_history" ] \
  || fail "the ssh session does not match the console (got: [${GOT}])" "sshd" "Accepted"
echo "a registered key logged in to zsh with init's PATH and history"

# ── 검사 14: 모르는 키는 거절된다 ─────────────────────────────────────────
ssh "${SSHO[@]}" -i "$KEYS/bad" root@127.0.0.1 true >/dev/null 2>&1
RC=$?
[ "$RC" = "255" ] || fail "an unregistered key got rc ${RC}, want 255"
echo "an unregistered key was refused"

# ── 검사 15: Ghostty의 TERM에서 less가 안 멈춘다 ──────────────────────────
OUT="$(TERM=xterm-ghostty timeout 15 ssh "${SSHO[@]}" -i "$KEYS/good" -tt root@127.0.0.1 \
  'echo x | less -FX; echo "sv-less-rc=$?"' 2>&1 < /dev/null | tr -d '\r')"
case "$OUT" in
  *"not fully functional"*) fail "less still warns under TERM=xterm-ghostty" ;;
  *"sv-less-rc=0"*) ;;
  *) fail "less under TERM=xterm-ghostty did not finish (got: [${OUT}])" ;;
esac
echo "less ran under TERM=xterm-ghostty without a warning"
stop_ssh
rm -f "$B_LOG"
rm -rf "$KEYS"
```

cleanup이 `rm -f "$LOG"`만 하므로 부팅 B의 로그는 위에서 지운다. 판정 글자
(`sv-ssh` · `sv-less-rc`)는 원격 명령이 출력하고 게스트 화면에 친 것이 없다.

- [ ] Step 2: 진입 검사(M1 Task 3 Step 3과 같은 명령) → `entry-ok`
- [ ] Step 3: 체인(약 4분) → 검사 1~15와 `SV chain PASS`
- [ ] Step 4: `check.sh`의 `CHAINS` 항목을 `"SV-M2:./service/check.sh"`로, 설명 문단의
  "회차당 부팅 1회"를 "3회(합 2분 안팎)"로.
- [ ] Step 5: 커밋 `Add sshd boots to the service chain: firewall, key persistence, session env`

## Task 5 — mutation 넷

각각 한 자리를 되돌려 체인을 돌리고(`rm -rf init/.zig-cache init/zig-out` 먼저) 겨냥한
검사가 빨간 것을 본 뒤 되돌린다.

| mutation | 자리 | 빨개야 하는 검사 |
|---|---|---|
| `login.apply` 호출을 지운다 | `main.zig` | 검사 9 (그리고 13) |
| 템플릿이 매번 키를 굽는다 | `make_initrd.sh` 템플릿의 `if [ ! -e "$key" ]`를 `if true` | 검사 12 |
| `ssh.nft`를 B에도 넣는다 | 체인의 첫 `sdbg "mkdir nftables.d"` 뒤에 `ssh.nft` write | 검사 11 |
| terminfo 굽기를 뺀다 | `make_initrd.sh`의 `for pair in …` 루프를 지운다 | 검사 15 |

## Task 6 — 가이드

`docs/guides/running-tars.md`에 "부팅 때 뜨는 서비스와 ssh" 절을 방화벽 절 뒤에 더한다.
담을 것 — `services.d`의 규칙(실행 파일 하나 · 이름순 · 여덟까지 · `.` 숨김 · 실행 비트 ·
`#!/bin/sh` · 고치면 다음 부팅) · 로그에서 읽는 줄(M1-E 표) · sshd 켜는 두 줄 · `firewall=on`
이면 `ssh.nft` · 세션이 `tars.conf`의 셸을 따른다 · 호스트 키의 자리와 지우면 새로
구워진다는 것 · 지원하는 `TERM` 일곱 · LAN에 노출할 때는 `firewall=on`과 함께 쓰라는 것
(design 위험 5).

## Task 7 — 루트 게이트 (약 50분)

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer ./check.sh > /tmp/sv/gate.log 2>&1 ; } 2>&1 | tail -3
tail -3 /tmp/sv/gate.log; grep -c FAIL /tmp/sv/gate.log
```

기대: `TARS check PASS: all chains 3/3 consecutive runs succeeded`, `FAIL` 0줄.

## Task 8 — 닫는다

- design에 "SV-M2가 실행으로 증명한 것"(실측 16~), `Status: 끝났다(날짜) — M0~M2 …`.
- `docs/decisions/project_boot_services.md`와 `MEMORY.md` 한 줄.
- `CLAUDE.md` 완료 표에 한 줄.
- `docs/guides/lessons.md`에 서브프로젝트를 넘는 것(`/bin`에는 `sh`뿐 · ext2 getdents 순서 ·
  `tic`으로 terminfo 이름 더하기).
- `HANDOFF.md` 맨 위 절 교체.
- 커밋 `Close SV-M2: sshd as the first service, sessions follow tars.conf`.
