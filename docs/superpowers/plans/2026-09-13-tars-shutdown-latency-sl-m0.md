# SL-M0 — 종료 한 번을 밀리초로 재고 SIGHUP 반사실을 밟는다

Date: 2026-09-13
design: `docs/superpowers/specs/2026-09-13-tars-shutdown-latency-design.md`

이 milestone은 저장소 파일을 한 글자도 안 바꾼다(design 결정 6). 측정용
`power.zig` 사본을 만들어 `-v`로 읽기 전용 마운트하고, 커널 cmdline으로
변종을 고른다.

## 재는 방법 — 변종을 파일이 아니라 cmdline으로 고른다

측정할 변종이 셋이다(design 결정 3).

| cmdline | 무엇을 보내나 | 무엇을 재나 |
|---|---|---|
| `tars.slsig=term` | `kill(-1, .TERM)`만 | 지금 값(baseline) |
| `tars.slsig=hup` | `kill(-1, .HUP)`만 | A1 |
| `tars.slsig=both` | TERM 뒤에 HUP | A2 |

사본을 셋 만들지 않고 하나만 만든다. 사본이 셋이면 마운트가 회차마다
달라져서 `docker run`도 셋이 되고, 그때마다 `zig build`가 다시 돈다. 커널
cmdline으로 고르면 빌드 한 번에 부팅 일곱을 다 돌 수 있다.

`/proc`은 그 시점에 이미 마운트되어 있다. `main.zig`가 부팅 초반에 붙이고
`linkDevFd()`가 그 뒤에 `/proc/self/fd`를 링크하므로, 종료가 시작되는
자리에서는 확실히 있다.

종료를 부르는 것은 타이핑이 아니라 QEMU monitor의 `system_powerdown`이다
(`device/check.sh`가 쓰는 경로). 타이핑이 없으면 셸이 무엇이든 같은 절차로
끌 수 있어서, 셸 셋을 도는 측정 6이 셸마다 다른 명령을 찾을 필요가 없다.
측정 6만 예외로 타이핑을 쓴다.

시각은 `tars-init: SLM0 …` 접두사가 붙은 줄로 나온다. 기존 로그 줄은 한
글자도 안 건드린다 — 건드리면 이 측정이 재는 것이 코드가 아니라 자기
자신이 된다.

## Task 0 — `/tmp/sl/`을 호스트에 만든다

```bash
mkdir -p /tmp/sl
```

아래 Task 1과 Task 2의 파일을 Write 도구로 호스트에 쓴다. heredoc을 쓰지
않는다 — 중첩 따옴표에서 `$` 확장이 호스트 bash에 먼저 먹힌다(SD-M0이
배운 것).

`-v`로 없는 파일을 마운트하면 Docker가 호스트에 0바이트 파일을 만들어
버리므로, 마운트 전에 두 파일이 다 있는지 `ls -l`로 확인한다.

## Task 1 — 측정용 `power.zig` 전문

`/tmp/sl/power_measure.zig`에 쓴다. 원본과 다른 자리는 넷이고 나머지는
글자 그대로 같다.

1. `monotonicMillis()`와 `t_zero` 추가
2. `SigChoice`와 `readSigChoice()` 추가
3. `reapAll()`이 거둔 pid와 시각을 찍는다
4. `shutdown()`이 변종에 따라 시그널을 보내고 단계별 시각을 찍는다

```zig
const std = @import("std");
const linux = std.os.linux;

/// main.zig와 config.zig에도 같은 함수가 있다. 이것이 세 벌째다.
/// config.zig:4가 "다섯 개쯤 되면 sys.zig로 모은다"고 적어 뒀고, 아직
/// 다섯이 아니므로 그 판단을 유지한다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// PID 1이 시그널을 받고 하기로 한 일. 값이 0이 아닌 이유는 pending의 0이
/// "요청 없음"을 뜻하기 때문이다.
pub const Action = enum(u8) {
    power_off = 1,
    restart = 2,
};

/// 시그널 핸들러가 만질 수 있는 유일한 상태. 0은 "요청 없음"이다.
var pending: u8 = 0;

/// 시그널 핸들러 안에서는 재진입 안전하지 않은 것을 부를 수 없다. 우리 로그
/// 함수(std.debug.print)가 바로 그런 것이므로, 핸들러는 정수 하나를 남기고
/// 즉시 돌아온다. 로그는 깨어난 감독 루프가 찍는다.
fn onSignal(sig: linux.SIG) callconv(.c) void {
    const action: Action = switch (sig) {
        .TERM => .power_off,
        .INT => .restart,
        else => return,
    };
    request(action);
}

/// 시그널이 아닌 경로에서 온 종료 요청을 같은 자리에 세운다
/// (design 결정 9). 전원 버튼을 본 감독 루프가 이것을 부른다.
pub fn request(action: Action) void {
    @atomicStore(u8, &pending, @intFromEnum(action), .seq_cst);
}

/// 시그널 처리를 켠다.
pub fn install() void {
    const act: linux.Sigaction = .{
        .handler = .{ .handler = onSignal },
        .mask = linux.sigemptyset(),
        .flags = 0,
    };
    if (failed(linux.sigaction(.TERM, &act, null))) |e| {
        std.debug.print("tars-init: failed to install SIGTERM handler (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    if (failed(linux.sigaction(.INT, &act, null))) |e| {
        std.debug.print("tars-init: failed to install SIGINT handler (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    std.debug.print("tars-init: signal handlers installed (TERM, INT)\n", .{});
}

/// 밀린 요청을 꺼내면서 지운다. 감독 루프가 매 바퀴 부른다.
pub fn take() ?Action {
    const raw = @atomicRmw(u8, &pending, .Xchg, 0, .seq_cst);
    if (raw == 0) return null;
    return @enumFromInt(raw);
}

/// Ctrl+Alt+Del을 커널에게서 빼앗아 우리에게 돌린다.
pub fn disableCtrlAltDel() void {
    if (failed(linux.reboot(.MAGIC1, .MAGIC2, .CAD_OFF, null))) |e| {
        std.debug.print("tars-init: could not take over ctrl-alt-del (errno {d})\n", .{
            @intFromEnum(e),
        });
        return;
    }
    std.debug.print("tars-init: ctrl-alt-del now arrives as SIGINT\n", .{});
}

/// 자식에게 주는 유예.
const GRACE_SECONDS: isize = 3;

fn monotonicSeconds() isize {
    var ts: linux.timespec = undefined;
    if (failed(linux.clock_gettime(.MONOTONIC, &ts))) |_| return 0;
    return ts.sec;
}

// ==================================================== SL-M0 측정용 (추가 1)

/// 종료가 시작된 시각. 모든 SLM0 줄이 이것과의 차를 찍는다.
var t_zero: i64 = 0;

/// `ts.sec`와 `ts.nsec`은 `isize`다(원본 `monotonicSeconds()`의 반환 타입이
/// 그것을 보여 준다). `isize`와 `i64`는 크기가 같아도 Zig에서 다른 타입이라
/// `@as`만으로는 안 되고 `@intCast`가 필요하다.
fn monotonicMillis() i64 {
    var ts: linux.timespec = undefined;
    if (failed(linux.clock_gettime(.MONOTONIC, &ts))) |_| return 0;
    const sec: i64 = @intCast(ts.sec);
    const nsec: i64 = @intCast(ts.nsec);
    return sec * 1000 + @divTrunc(nsec, 1_000_000);
}

fn elapsed() i64 {
    return monotonicMillis() - t_zero;
}

// ==================================================== SL-M0 측정용 (추가 2)

/// 커널 cmdline이 고르는 변종. 기본값 term이 지금 저장소의 동작이다.
const SigChoice = enum { term, hup, both };

fn readSigChoice() SigChoice {
    var buf: [4096]u8 = undefined;
    const rc = linux.open("/proc/cmdline", .{ .ACCMODE = .RDONLY }, 0);
    if (failed(rc)) |_| return .term;
    const fd: i32 = @intCast(rc);
    defer _ = linux.close(fd);

    const n = linux.read(fd, &buf, buf.len);
    if (failed(n)) |_| return .term;

    const s = buf[0..n];
    const key = "tars.slsig=";
    const at = std.mem.indexOf(u8, s, key) orelse return .term;
    const rest = s[at + key.len ..];
    if (std.mem.startsWith(u8, rest, "both")) return .both;
    if (std.mem.startsWith(u8, rest, "hup")) return .hup;
    return .term;
}

/// 자식이 전부 사라질 때까지 거둔다. 다 거뒀으면 true, 유예가 끝났으면
/// false.
fn reapAll() bool {
    const deadline = monotonicSeconds() + GRACE_SECONDS;
    var reaped: usize = 0;
    while (true) {
        var status: u32 = 0;
        const rc = linux.waitpid(-1, &status, linux.W.NOHANG);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc != 0) {
                    reaped += 1;
                    // 추가 3 — 누가 언제 죽었는지. 이 줄 하나가 측정 2와
                    // 측정 4를 함께 준다(started 줄의 pid와 대조한다).
                    std.debug.print("tars-init: SLM0 reaped pid={d} t={d}\n", .{
                        @as(i64, @intCast(rc)), elapsed(),
                    });
                    continue;
                }
            },
            .CHILD => {
                std.debug.print("tars-init: every child is gone (reaped {d})\n", .{reaped});
                return true;
            },
            else => {},
        }
        if (monotonicSeconds() >= deadline) {
            std.debug.print("tars-init: grace period expired (reaped {d})\n", .{reaped});
            return false;
        }
        sleepMillis(100);
    }
}

fn sleepMillis(ms: isize) void {
    const req = linux.timespec{
        .sec = @divTrunc(ms, 1000),
        .nsec = @rem(ms, 1000) * 1_000_000,
    };
    _ = linux.nanosleep(&req, null);
}

/// 시스템을 끈다. 절대 반환하지 않는다.
pub fn shutdown(action: Action) noreturn {
    // 추가 4 — 여기서부터 재기 시작한다.
    t_zero = monotonicMillis();
    const choice = readSigChoice();
    std.debug.print("tars-init: SLM0 sigchoice={s}\n", .{@tagName(choice)});

    std.debug.print("tars-init: shutdown requested (action {s})\n", .{@tagName(action)});

    if (choice == .term or choice == .both) {
        _ = linux.kill(-1, .TERM);
        std.debug.print("tars-init: sent SIGTERM to every process\n", .{});
    }
    if (choice == .hup or choice == .both) {
        _ = linux.kill(-1, .HUP);
        std.debug.print("tars-init: sent SIGHUP to every process\n", .{});
    }
    std.debug.print("tars-init: SLM0 t_kill={d}\n", .{elapsed()});

    if (!reapAll()) {
        _ = linux.kill(-1, .KILL);
        std.debug.print("tars-init: sent SIGKILL to what was left\n", .{});
        _ = reapAll();
    }
    std.debug.print("tars-init: SLM0 t_reap={d}\n", .{elapsed()});

    linux.sync();
    std.debug.print("tars-init: filesystems synced\n", .{});
    std.debug.print("tars-init: SLM0 t_sync={d}\n", .{elapsed()});

    const cmd: linux.LINUX_REBOOT.CMD = switch (action) {
        .power_off => .POWER_OFF,
        .restart => .RESTART,
    };
    std.debug.print("tars-init: SLM0 t_total={d}\n", .{elapsed()});
    std.debug.print("tars-init: calling reboot({s})\n", .{@tagName(cmd)});
    _ = linux.reboot(.MAGIC1, .MAGIC2, cmd, null);

    std.debug.print("tars-init: reboot syscall returned; PID 1 stays alive\n", .{});
    while (true) sleepMillis(1000);
}
```

원본에서는 `sleepMillis`가 `reapAll`보다 위에 있다. 이 사본에서 아래로
내려간 것은 추가 블록 둘을 `reapAll` 앞에 모아 두려고 그런 것이고, Zig는
파일 스코프 선언의 순서를 따지지 않으므로 동작은 같다. 사본에만 있는
차이이므로 M1에서 이 순서를 따라가지 않는다.

## Task 2 — 하네스 전문

`/tmp/sl/sl_m0.sh`에 쓴다. 인자 둘을 받는다 — 셸 목록과 변종 목록.

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /workspace

# SL-M0 측정 하네스. 컨테이너 안에서 돈다.
#
# 인자 1: 셸 목록 (공백 구분). 예 "fish zsh bash"
# 인자 2: 변종 목록 (공백 구분). 예 "term hup both"
#
# 변종은 커널 cmdline의 tars.slsig=로 간다. 사본 power.zig가 /proc/cmdline을
# 읽어서 무엇을 보낼지 고른다 — 그래서 빌드 한 번으로 전부 돈다.
SHELLS="${1:-fish zsh bash}"
SIGS="${2:-term}"

OUT=/workspace/out/sl_m0
mkdir -p "$OUT"

# 체인들이 쓰는 포트를 피한다. 45455~45463과 45471은 이미 임자가 있다.
MONITOR_PORT=45472
GUEST_MEM=512

echo "=== building ==="
(cd kernel && ./build.sh)
(cd init && zig build)
(cd terminal && ./prepare.sh)
(cd kernel && ./make_initrd.sh)

# tars.conf 한 줄만 담은 디스크. mkfs.ext2 -d로 미리 구우면 게스트에 한
# 글자도 안 쳐도 셸이 정해진다(실측 34). 라벨은 tars-로 시작해야 한다 —
# storage.zig가 장치 이름이 아니라 라벨로 찾는다.
make_disk() {
  local shell="$1" img="$2"
  local seed
  seed="$(mktemp -d)"
  printf 'shell=%s\n' "$shell" > "$seed/tars.conf"
  rm -f "$img"
  truncate -s 16M "$img"
  mkfs.ext2 -F -q -m 0 -L tars-slm0 -d "$seed" "$img"
  rm -rf "$seed"
}

# 한 번 띄우고, 전원 버튼을 누르고, 기계가 사라질 때까지 기다린다.
# 타이핑이 없다 — system_powerdown은 ACPI 전원 버튼이라 셸을 안 거친다.
boot_once() {
  local shell="$1" sig="$2"
  local tag="${shell}_${sig}"
  local log="$OUT/${tag}.log"
  local img="$OUT/${tag}.img"

  make_disk "$shell" "$img"
  rm -f "$log"

  qemu-system-x86_64 \
    -m "$GUEST_MEM" \
    -kernel kernel/build/arch/x86/boot/bzImage \
    -initrd kernel/initrd.cpio \
    -append "console=ttyS0 tars.slsig=${sig}" \
    -vga none \
    -device virtio-gpu-pci \
    -drive file="$img",if=virtio,format=raw \
    -display none \
    -serial file:"$log" \
    -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
    -no-reboot &
  local pid=$!

  local ready=0
  local i
  for i in $(seq 1 120); do
    if grep -a "terminal: screen>" "$log" >/dev/null 2>&1; then ready=1; break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  if [ "$ready" != "1" ]; then
    echo "FAIL(${tag}): the terminal never rendered"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi

  # 렌더가 한 번 돌았다고 부팅이 끝난 것은 아니다. 셸 rc가 아직 돌고 있을
  # 수 있어서 2초를 더 준다 — 종료 중에 rc가 겹치면 재는 값이 흔들린다.
  sleep 2

  local connected=0
  for i in $(seq 1 20); do
    if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then connected=1; break; fi
    sleep 0.5
  done
  if [ "$connected" != "1" ]; then
    echo "FAIL(${tag}): could not reach the QEMU monitor"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi

  echo "=== ${tag}: sending system_powerdown ==="
  echo "system_powerdown" >&3

  local gone=0
  for i in $(seq 1 60); do
    if ! kill -0 "$pid" 2>/dev/null; then gone=1; break; fi
    sleep 0.5
  done
  exec 3<&- || true
  exec 3>&- || true
  wait "$pid" 2>/dev/null || true

  if [ "$gone" != "1" ]; then
    echo "FAIL(${tag}): the machine never switched itself off"
    return 1
  fi

  echo "--- ${tag} ---"
  # 이 다섯 갈래가 측정 1~5의 전부다. grep을 좁게 잡는다(SP-M0).
  grep -a "tars-init: started " "$log" || true
  grep -a "tars-init: SLM0 " "$log" || true
  grep -a "tars-init: sent SIG" "$log" || true
  grep -a "tars-init: every child is gone" "$log" || true
  grep -a "tars-init: grace period expired" "$log" || true
  echo
}

for sig in $SIGS; do
  for shell in $SHELLS; do
    boot_once "$shell" "$sig" || true
  done
done

echo "=== done. logs in ${OUT} ==="
```

`|| true`를 붙인 이유는 한 회차가 실패해도 나머지를 다 보기 위해서다.
측정이지 게이트가 아니므로 첫 실패에서 멈출 값이 없다.

`grep`에 `-a`를 반드시 붙인다. 시리얼 로그에 NUL이 한 바이트라도 있으면
`grep`이 binary로 취급해 `Binary file ... matches`만 뱉는다.

## Task 3 — baseline을 잰다 (측정 1·2)

약 6분이다(커널 빌드가 스탬프에 걸리면 3분).

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/sl/power_measure.zig:/workspace/init/src/power.zig:ro \
  -v /tmp/sl/sl_m0.sh:/tmp/sl_m0.sh:ro \
  -w /workspace tars-devcontainer \
  bash /tmp/sl_m0.sh "fish zsh bash" "term" > /tmp/sl_term.log 2>&1
```

볼 것 둘.

측정 1 — `SLM0 t_kill` · `t_reap` · `t_sync` · `t_total`. `t_reap`이
3000 근처면 유예를 꽉 쓴 것이고, 그것이 이 서브프로젝트가 없애려는 값이다.

측정 2 — `grace period expired (reaped N)`의 N, 그리고 `SLM0 reaped pid=`
줄의 개수와 pid. `tars-init: started terminal (pid X, …)` ·
`started console shell (pid Y, …)`와 대조해서 누가 남았는지 이름을 붙인다.
확인 3의 추론이 맞다면 유예 안에 거둬지는 것에 콘솔 셸의 pid가 없다.

## Task 4 — SIGHUP만 보낸다 (측정 3·4)

약 3분이다(커널과 terminal이 캐시에 걸린다).

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/sl/power_measure.zig:/workspace/init/src/power.zig:ro \
  -v /tmp/sl/sl_m0.sh:/tmp/sl_m0.sh:ro \
  -w /workspace tars-devcontainer \
  bash /tmp/sl_m0.sh "fish zsh bash" "hup" > /tmp/sl_hup.log 2>&1
```

볼 것 셋.

측정 3 — `grace period expired`가 사라지고 `every child is gone`이 나오는가.
그리고 `SLM0 t_reap`이 몇인가. 셸 셋에서 다 같은가.

측정 4 — `SLM0 reaped pid=` 줄에 `started terminal`의 pid가 있는가. 없으면
`terminal`이 SIGHUP에 안 죽은 것이고, design 위험 1이 실현된 것이다. 그때는
M1에 넣을 코드가 달라지므로 여기서 멈추고 design을 다시 쓴다.

측정 5의 절반 — `t_total`을 Task 5의 값과 비교한다.

## Task 5 — TERM 뒤에 HUP (측정 5)

약 2분이다.

```bash
docker run --rm -v "$PWD":/workspace \
  -v /tmp/sl/power_measure.zig:/workspace/init/src/power.zig:ro \
  -v /tmp/sl/sl_m0.sh:/tmp/sl_m0.sh:ro \
  -w /workspace tars-devcontainer \
  bash /tmp/sl_m0.sh "fish zsh bash" "both" > /tmp/sl_both.log 2>&1
```

측정 5 — `t_reap`과 `t_total`이 Task 4의 값과 갈리는가. 갈리지 않으면
design 결정 3이 정한 대로 A2(both)를 고른다. 갈리면 값이 작은 쪽을 고르고
왜 갈렸는지를 실측 절에 적는다.

## Task 6 — 히스토리가 여전히 남는가 (측정 6)

이 측정만 타이핑이 필요하다. 셸에 명령을 하나 치고, 전원 버튼을 누르고,
디스크를 `debugfs`로 읽는다. 부팅을 다시 하지 않는 이유는 `debugfs`가
컨테이너에 있기 때문이다(`/usr/sbin/debugfs`, e2fsprogs 1.47.2).

`/tmp/sl/sl_m0_hist.sh`에 쓴다.

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /workspace

# SL-M0 측정 6. 화면 셸에 명령을 하나 치고 끈 뒤, 설정 디스크에서 그 줄을
# 찾는다. 부팅을 다시 안 하고 debugfs로 읽는 것이 이 스크립트의 요점이다.
#
# 인자 1: 셸 (zsh 또는 bash. fish는 히스토리가 XDG_DATA_HOME 아래라 제외)
# 인자 2: 변종 (term 또는 hup 또는 both)
SHELL_NAME="${1:?shell required}"
SIG="${2:?sig required}"

OUT=/workspace/out/sl_m0
mkdir -p "$OUT"
MONITOR_PORT=45472
GUEST_MEM=512

echo "=== building ==="
(cd kernel && ./build.sh)
(cd init && zig build)
(cd terminal && ./prepare.sh)
(cd kernel && ./make_initrd.sh)

TAG="hist_${SHELL_NAME}_${SIG}"
LOG="$OUT/${TAG}.log"
IMG="$OUT/${TAG}.img"

SEED="$(mktemp -d)"
printf 'shell=%s\n' "$SHELL_NAME" > "$SEED/tars.conf"
rm -f "$IMG"
truncate -s 16M "$IMG"
mkfs.ext2 -F -q -m 0 -L tars-slm0 -d "$SEED" "$IMG"
rm -rf "$SEED"
rm -f "$LOG"

qemu-system-x86_64 \
  -m "$GUEST_MEM" \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
  -append "console=ttyS0 tars.slsig=${SIG}" \
  -vga none \
  -device virtio-gpu-pci \
  -drive file="$IMG",if=virtio,format=raw \
  -display none \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

for i in $(seq 1 120); do
  if grep -a "terminal: screen>" "$LOG" >/dev/null 2>&1; then break; fi
  kill -0 "$QEMU_PID" 2>/dev/null || break
  sleep 1
done
sleep 3

for i in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then break; fi
  sleep 0.5
done

# gate_lib.sh의 type_keys는 fd 3과 $LOG를 요구한다. 둘 다 갖춰 놓고 부른다.
source gate_lib.sh

# `echo slmark1`. sendkey의 키 이름은 전부 소문자이고 공백은 spc다(실측 6).
echo "=== typing 'echo slmark1' ==="
type_keys e c h o spc s l m a r k 1 ret
sleep 2

echo "=== sending system_powerdown ==="
echo "system_powerdown" >&3

GONE=0
for i in $(seq 1 60); do
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then GONE=1; break; fi
  sleep 0.5
done
exec 3<&- || true
exec 3>&- || true
wait "$QEMU_PID" 2>/dev/null || true

echo "--- ${TAG}: gone=${GONE} ---"
grep -a "tars-init: SLM0 " "$LOG" || true
grep -a "tars-init: every child is gone" "$LOG" || true
grep -a "tars-init: grace period expired" "$LOG" || true

# 명령이 정말 쳐졌는지 먼저 본다. 이 증거가 없으면 "잃었다"와 "애초에 안
# 쳐졌다"가 안 갈린다(SD-M0이 한 회차를 그렇게 버렸다).
echo "--- was it typed? (screen) ---"
grep -a "terminal: screen>.*slmark1" "$LOG" | tail -3 || true

echo "--- history file in the disk ---"
debugfs -R "ls -l /" "$IMG" 2>/dev/null || true
debugfs -R "cat ${SHELL_NAME}_history" "$IMG" 2>/dev/null || true
```

돌리는 것은 넷이다. 변종 term과 hup을 셸 둘에 각각 건다 — 지금 값과
바뀐 값을 같은 자리에서 비교해야 "SIGHUP이 무언가를 잃게 만들었나"에
답할 수 있다. 각 회차 약 2분이다.

```bash
for combo in "zsh term" "zsh hup" "bash term" "bash hup"; do
  set -- $combo
  docker run --rm -v "$PWD":/workspace \
    -v /tmp/sl/power_measure.zig:/workspace/init/src/power.zig:ro \
    -v /tmp/sl/sl_m0_hist.sh:/tmp/sl_m0_hist.sh:ro \
    -w /workspace tars-devcontainer \
    bash /tmp/sl_m0_hist.sh "$1" "$2" > "/tmp/sl_hist_$1_$2.log" 2>&1
done
```

측정 6 — `debugfs -R cat`의 출력에 `echo slmark1`이 있는가. term과 hup에서
같은가. bash는 `history -a`가 직전 명령까지만 쓰므로(실측 32) 그 줄이 아직
안 써져 있을 수 있다 — 그 경우 term에서도 똑같이 없어야 하고, 그 "똑같음"이
확인의 내용이다.

## Task 7 — 게이트에서 정상 종료를 밟는 부팅이 몇인가

코드를 안 돌린다. 체인 열하나를 읽어서 센다. design 비목표 5가 요구하는
기대치이고, "게이트가 얼마나 줄어야 하는가"의 상한을 준다.

```bash
rg -n 'system_powerdown|kill -TERM 1|kill "\$QEMU_PID"|kill "\$pid"' \
  */check.sh | sort
```

정상 종료(전원 버튼 또는 `kill -TERM 1`)를 밟는 부팅의 수 × 3초 × 3회차가
이론상의 절약이고, 전원을 뽑는 부팅은 원래 3초를 안 쓰므로 안 센다.

## Task 8 — design에 실측 절을 붙이고 커밋한다

`docs/superpowers/specs/2026-09-13-tars-shutdown-latency-design.md` 맨 뒤에
`## SL-M0이 실행으로 증명한 것`을 더하고, 실측을 번호로 적는다. 형식은
BB design의 같은 절과 맞춘다 — 각 실측이 재현 명령과 숫자를 함께 담는다.

`Status:` 줄도 함께 고친다.

```bash
git add docs/superpowers/specs/2026-09-13-tars-shutdown-latency-design.md \
        docs/superpowers/plans/2026-09-13-tars-shutdown-latency-sl-m0.md
git commit -m "Measure the shutdown that waits and the one that does not"
```

측정 하네스는 저장소에 안 넣는다. 다시 필요하면 이 문서의 Task 1·2·6에
전문이 글자 그대로 있다.

## 실패했을 때 어디를 보는가

- 부팅이 `terminal: screen>`까지 못 가면 그것은 이 측정의 실패가 아니라
  빌드나 디스크의 실패다. `/tmp/sl_*.log`의 빌드 구간을 먼저 본다.
- `SLM0 sigchoice=term`인데 cmdline에 `hup`을 줬다면 `/proc/cmdline` 읽기가
  실패한 것이다. 게스트에서 `cat /proc/cmdline`을 쳐 보는 것보다,
  `readSigChoice()`가 기본값으로 떨어지는 두 자리(`open` 실패 · `read`
  실패)에 임시로 로그를 붙이는 편이 빠르다.
- 기계가 안 꺼지면 `-no-reboot`이 붙어 있는지 본다. 그리고 로그에
  `Power off not available: System halted instead`가 있으면 커널의 ACPI가
  빠진 것이지 우리 코드 문제가 아니다.
- `debugfs -R cat`이 아무것도 안 뱉으면 파일 이름을 먼저 확인한다.
  `ls -l /`이 같은 스크립트에 있는 이유가 그것이다.
