# DC-M1 — 설치된 부팅이 늦게 생기는 설정 파티션을 기다린다

> 이 plan을 실행하는 사람에게: 아래 diff는 작업 트리에서 시제품으로 쓰고 install
> 체인까지 돌린 것이다(DI-M2와 같은 방식). Task마다 diff를 넣고, 검사를 돌리고,
> 커밋한다. 반사실(Task 4)은 반드시 컨테이너 안에서 `.zig-cache`와 `zig-out`을
> 지우고 돌린다 — 이 plan을 쓰며 그것을 빠뜨린 첫 반사실 판이 낡은 `init`으로
> 초록이 났다(`project_zig_out_staleness`).

Goal: `tars.installed`로 뜬 부팅에서 `init`이 설정 파티션을 최대 5초 기다려, 커널이
그것을 PID 1보다 늦게 만들어도 설정이 사라지지 않게 한다(DC 결정 1 · 2).

Architecture: `storage.zig`에 `findConfigDiskWaiting(out, list, max_ms)`를 더한다 —
먼저 훑고, 없으면 100ms 자고 다시 훑기를 상한까지. `main.zig`의 `mountConfig`는 표지가
있으면 `CONFIG_WAIT_MS`(5000), 없으면 0을 넘긴다. 판정은 `install/check.sh`의 부팅 7이
부팅 6의 디스크를 `-kernel` + `usb-storage` + `delay_use=3`으로 늦게 붙여서 본다(DC
결정 3 · 4).

Tech Stack: Zig 0.16(`std.os.linux`) · bash · QEMU(`-kernel` · qemu-xhci · usb-storage)

---

## 시제품에서 본 것 (plan을 쓰며, 2026-09-25)

- `zig build test` 초록. 새 줄 `storage_test: an installed boot waits for config
  storage, others look once`.
- install 체인 초록 두 판(1분 28초). 부팅 7이 `init waited 1600ms`·`1700ms`. 부팅
  2·4·6은 DI-M2와 같은 6초 — 첫 훑기에서 잡아 기다림 줄이 없다.
- 반사실(`max_ms`를 늘 0)은 부팅 7에서 `among 42 candidates`, 판정 17 빨강. 다만 첫
  반사실 판은 초록이었다 — 체인의 `zig build`가 `sd`로 고친 소스를 안 다시 빌드해서
  남아 있던 바이너리(md5 `6b46…`, 정상 코드의 것)로 떴다. 캐시를 지운 정상 판의
  바이너리가 같은 `6b46…`이라 확정이다.

## Task 1: 기다림 함수와 호스트 검사

**Files:**
- Modify: `init/src/storage.zig` (끝에 더한다)
- Modify: `init/src/storage_test.zig`

- [ ] **Step 1: diff를 넣는다**

```diff
diff --git a/init/src/storage.zig b/init/src/storage.zig
index cfb1124..58afb9b 100644
--- a/init/src/storage.zig
+++ b/init/src/storage.zig
@@ -242,3 +242,48 @@ pub fn findConfigDisk(out: *Found, list: []const [:0]const u8) bool {
     }
     return false;
 }
+
+/// 설치된 디스크로 떴을 때 설정 파티션을 기다리는 상한(DC 결정 2). DC-M0이
+/// 게이트에서 벌린 틈이 1.72초였고(실측 1), 실기에서는 initramfs 풀기가 짧아
+/// 1초를 쉬는 USB나 느린 NVMe 리셋이 PID 1보다 늦는다(실측 2). 그 셋을 덮는
+/// 수다(실측 3).
+pub const CONFIG_WAIT_MS: u32 = 5000;
+
+/// 다시 훑는 간격. 한 번이 open 마흔둘이고 없는 노드는 ENOENT로 바로
+/// 돌아오므로, 상한까지 쉰 번이어도 부팅에서 안 보이는 비용이다.
+/// tars-install의 waitForNode와 같은 수다.
+const CONFIG_POLL_MS: u32 = 100;
+
+/// devices.zig·power.zig에도 같은 함수가 있다. failed와 같은 이유로 공용
+/// 모듈을 만들지 않는다.
+fn sleepMillis(ms: u32) void {
+    const req = linux.timespec{
+        .sec = @intCast(ms / 1000),
+        .nsec = @intCast(@as(u64, ms % 1000) * std.time.ns_per_ms),
+    };
+    _ = linux.nanosleep(&req, null);
+}
+
+/// findConfigDisk를 max_ms까지 CONFIG_POLL_MS 간격으로 다시 부른다. 찾으면
+/// 기다린 밀리초(바로 찾았으면 0), 끝내 없으면 null.
+///
+/// 커널은 PID 1을 띄우기 전에 디스크를 기다려 주지 않는다 — NVMe의
+/// namespace 스캔은 워크큐에서, usb-storage의 SCSI 스캔은 delay_use 뒤에
+/// 돈다(DC 확인 2). 그래서 한 번 훑고 끝내면 설정이 멀쩡히 있는데도 기본값으로
+/// 뜨는 부팅이 생긴다(DC-M0 실측 1).
+///
+/// 먼저 훑고 나서 잔다. 거꾸로면 모든 설치 부팅이 CONFIG_POLL_MS만큼 늦는다
+/// (devices.findKeyboardWaiting의 검사 7a와 같은 함정). 매번 목록 전체를 처음부터
+/// 다시 훑으므로 "먼저 찾은 것이 이긴다"는 규칙이 그대로다.
+///
+/// max_ms를 인자로 받는 것은 두 부르는 쪽 때문이다. 표지 없는 부팅은 0을 넘겨
+/// 지금처럼 한 번만 훑고(DC 결정 1), storage_test는 초 단위로 자지 않는다.
+pub fn findConfigDiskWaiting(out: *Found, list: []const [:0]const u8, max_ms: u32) ?u32 {
+    var waited: u32 = 0;
+    while (true) {
+        if (findConfigDisk(out, list)) return waited;
+        if (waited >= max_ms) return null;
+        sleepMillis(CONFIG_POLL_MS);
+        waited += CONFIG_POLL_MS;
+    }
+}
diff --git a/init/src/storage_test.zig b/init/src/storage_test.zig
index fbfbed4..15f21a0 100644
--- a/init/src/storage_test.zig
+++ b/init/src/storage_test.zig
@@ -1,4 +1,5 @@
 const std = @import("std");
+const linux = std.os.linux;
 const storage = @import("storage.zig");
 
 /// 이 검사가 보는 것은 규칙이고, 오프셋이 아니다.
@@ -38,6 +39,45 @@ fn full(magic: u16, label: []const u8) []const u8 {
 
 const EXT2: u16 = 0xEF53;
 
+fn failed(rc: usize) ?linux.E {
+    const e = linux.errno(rc);
+    return if (e == .SUCCESS) null else e;
+}
+
+/// devices_test의 nowMillis와 같다. 기다림 검사가 벽시계로 잰다.
+fn nowMillis() i64 {
+    var ts: linux.timespec = undefined;
+    if (failed(linux.clock_gettime(.MONOTONIC, &ts))) |_| return 0;
+    return @as(i64, ts.sec) * 1000 + @divTrunc(@as(i64, ts.nsec), 1_000_000);
+}
+
+/// 기다림 검사가 여는 가짜 디스크. 게스트가 아니라 빌드 컨테이너의 /tmp다.
+const FAKE_DISK: [:0]const u8 = "/tmp/tars-storage-test.img";
+const NO_DISK: [:0]const u8 = "/tmp/tars-storage-test-absent.img";
+
+/// bytes를 path에 통째로 쓴다. devices_test의 writeFile과 같은 루프다.
+fn writeFile(path: [:0]const u8, bytes: []const u8) !void {
+    const rc = linux.open(path.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
+    if (failed(rc)) |e| {
+        std.debug.print("FAIL: create {s} (errno {d})\n", .{ path, @intFromEnum(e) });
+        return error.OpenFailed;
+    }
+    const fd: i32 = @intCast(rc);
+    defer _ = linux.close(fd);
+
+    var written: usize = 0;
+    while (written < bytes.len) {
+        const n = linux.write(fd, bytes.ptr + written, bytes.len - written);
+        if (failed(n)) |e| {
+            if (e == .INTR) continue;
+            std.debug.print("FAIL: write {s} (errno {d})\n", .{ path, @intFromEnum(e) });
+            return error.WriteFailed;
+        }
+        if (n == 0) return error.WriteFailed;
+        written += n;
+    }
+}
+
 pub fn main() !void {
     // ── 1. 대조군: 매직이 없다 ────────────────────────────────────────
     //
@@ -268,6 +308,74 @@ pub fn main() !void {
         return error.NoCandidates;
     }
 
+    // ── 설치된 부팅의 기다림 (DC-M1) ─────────────────────────────────
+    //
+    // 늦게 생기는 노드 자체는 여기서 못 만든다(스레드 없이는 "훑는 도중에
+    // 생긴다"가 안 된다). 그것은 install 체인의 부팅 7이 usb-storage의
+    // delay_use로 본다. 여기서 보는 것은 기다림의 모양 셋이다 — 있으면 안
+    // 자고, 상한이 0이면 한 번만 보고, 없으면 상한만큼만 잔다.
+    _ = linux.unlink(NO_DISK.ptr);
+    try writeFile(FAKE_DISK, full(EXT2, "tars-config"));
+    {
+        // 있으면 바로 돌아온다. 자고 나서 묻는 순서면 모든 설치 부팅이
+        // 100ms씩 늘고, 증상이 "부팅이 좀 느리다"뿐이라 아무도 못 잡는다
+        // (devices_test 7a와 같은 함정).
+        const list = [_][:0]const u8{ NO_DISK, FAKE_DISK };
+        var found: storage.Found = .{};
+        const started = nowMillis();
+        const waited = storage.findConfigDiskWaiting(&found, &list, storage.CONFIG_WAIT_MS);
+        const elapsed_ms = nowMillis() - started;
+        if (waited == null or waited.? != 0 or !std.mem.eql(u8, found.path, FAKE_DISK)) {
+            std.debug.print("FAIL: a config disk that is right there was not taken at once\n", .{});
+            return error.PresentDiskMissed;
+        }
+        if (elapsed_ms >= 50) {
+            std.debug.print("FAIL: finding a present config disk took {d}ms (it slept first)\n", .{elapsed_ms});
+            return error.SleptBeforeLooking;
+        }
+    }
+    {
+        // 상한이 0이면 한 번 훑고 끝난다. 표지 없는 부팅이 이 길이다 — 원래
+        // 디스크가 없는 BF 체인과 ISO 설치 세션이 여기서 헛기다리면 안 된다.
+        const list = [_][:0]const u8{NO_DISK};
+        var found: storage.Found = .{};
+        const started = nowMillis();
+        const waited = storage.findConfigDiskWaiting(&found, &list, 0);
+        const elapsed_ms = nowMillis() - started;
+        if (waited != null) {
+            std.debug.print("FAIL: an absent disk was found\n", .{});
+            return error.AbsentDiskFound;
+        }
+        if (elapsed_ms >= 50) {
+            std.debug.print("FAIL: a zero budget still waited {d}ms\n", .{elapsed_ms});
+            return error.ZeroBudgetWaited;
+        }
+    }
+    {
+        // 끝내 없으면 상한만큼만 기다리고 돌아온다. 무한히 기다리면 기계가
+        // 안 켜진다 — 설정 하나 때문에 부팅이 막히는 것이 이 저장소에서 가장
+        // 나쁜 결말이다.
+        const list = [_][:0]const u8{NO_DISK};
+        var found: storage.Found = .{};
+        const started = nowMillis();
+        const waited = storage.findConfigDiskWaiting(&found, &list, 300);
+        const elapsed_ms = nowMillis() - started;
+        if (waited != null) {
+            std.debug.print("FAIL: an absent disk was found after waiting\n", .{});
+            return error.AbsentDiskFoundAfterWait;
+        }
+        if (elapsed_ms < 300) {
+            std.debug.print("FAIL: gave up after {d}ms, want at least 300ms\n", .{elapsed_ms});
+            return error.GaveUpTooEarly;
+        }
+        if (elapsed_ms > 2000) {
+            std.debug.print("FAIL: waited {d}ms for a 300ms budget\n", .{elapsed_ms});
+            return error.WaitedTooLong;
+        }
+    }
+    _ = linux.unlink(FAKE_DISK.ptr);
+    std.debug.print("storage_test: an installed boot waits for config storage, others look once\n", .{});
+
     std.debug.print(
         "storage_test: only a tars- labelled ext2 superblock counts ({d} candidates)\n",
         .{storage.CANDIDATES.len},
```

- [ ] **Step 2: 호스트 검사**

Run: `docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer bash -c 'zig build && zig build test'`
Expected: 종료 0, `storage_test: an installed boot waits for config storage, others look once`.

- [ ] **Step 3: 커밋** — `Let storage wait for a config disk up to a budget`

## Task 2: `mountConfig`가 설치된 부팅에서만 기다린다

**Files:**
- Modify: `init/src/main.zig` (`mountConfig`)

- [ ] **Step 1: diff를 넣는다**

```diff
diff --git a/init/src/main.zig b/init/src/main.zig
index 06ebb21..a156bb4 100644
--- a/init/src/main.zig
+++ b/init/src/main.zig
@@ -125,14 +125,32 @@ fn makeXdgDir() void {
 /// 디스크가 없는 부팅도 정상 경로다 — BF 체인은 ISO 부팅이라 -drive가 없다.
 /// 그때는 후보가 전부 ENOENT로 열리지 않아 로그 한 줄만 남으며, 부팅은
 /// 계속된다. 그 줄의 후보 수(14 · 42)가 이번 부팅이 파티션을 봤는지를 말한다.
+///
+/// 설치된 디스크로 떴을 때만 기다린다(DC 결정 1). 그때는 p2가 반드시 있으니
+/// 못 찾은 것은 "없다"가 아니라 "아직 없다"다 — 커널은 NVMe와 USB 디스크를
+/// PID 1보다 늦게 만들 수 있다(DC-M0 실측 1 · 2). 표지 없는 부팅은 원래 디스크가
+/// 없을 수 있어서 기다리면 매번 상한만큼 헛돈다.
 fn mountConfig() bool {
-    const list = storage.candidates(storage.bootedInstalled(config.CMDLINE_PATH));
+    const installed = storage.bootedInstalled(config.CMDLINE_PATH);
+    const list = storage.candidates(installed);
+    const max_ms: u32 = if (installed) storage.CONFIG_WAIT_MS else 0;
     var found: storage.Found = .{};
-    if (!storage.findConfigDisk(&found, list)) {
+    const waited = storage.findConfigDiskWaiting(&found, list, max_ms) orelse {
+        // 기다린 부팅만 한 줄 더. 설치된 기계에서 설정이 사라지는 증상의
+        // 원인이 "늦었다"인지 "없다"인지를 이 줄이 가른다.
+        if (max_ms > 0) {
+            std.debug.print("tars-init: waited {d}ms for config storage\n", .{max_ms});
+        }
         std.debug.print("tars-init: no disk labelled {s}* among {d} candidates\n", .{
             storage.LABEL_PREFIX, list.len,
         });
         return false;
+    };
+
+    // 기다린 적이 있을 때만 찍는다(HD-M2의 키보드와 같은 규칙). 늘 찍으면
+    // 정상 부팅의 로그가 한 줄 늘고, 그 줄은 아무것도 안 가른다.
+    if (waited > 0) {
+        std.debug.print("tars-init: config storage appeared after {d}ms\n", .{waited});
     }
 
     // 이 줄이 RM-M2의 판정이다. 고른 이름과 고른 근거가 한 줄에 함께
```

- [ ] **Step 2: 빌드** — Task 1 Step 2와 같다.
- [ ] **Step 3: 커밋** — `Wait up to 5s for the config partition on installed boots`

## Task 3: install 체인의 부팅 7

**Files:**
- Modify: `install/check.sh`

- [ ] **Step 1: diff를 넣는다**

```diff
diff --git a/install/check.sh b/install/check.sh
index 21c4853..9952f65 100755
--- a/install/check.sh
+++ b/install/check.sh
@@ -14,6 +14,7 @@ cd "$(dirname "$0")"
 #   4  NVMe만              갱신을 넘어 마커가 남았다
 #   5  ISO + 설치된 NVMe   --wipe로 통째로 다시 설치
 #   6  NVMe만              마커가 사라졌고 설정이 첫 부팅처럼 새로 깔린다
+#   7  같은 디스크를 USB로  -kernel · delay_use=3. init이 늦은 p2를 기다려 잡는다(DC-M1)
 #
 # 왜 sendkey가 아니라 시리얼 FIFO인가. 다른 체인들은 terminal의 화면
 # 줄(`terminal: screen>`)로 판정하는데 이 체인이 볼 것은 tars-install이
@@ -390,5 +391,73 @@ echo "--wipe left a fresh config partition"
 
 stop_guest
 
+# ── 부팅 7: 설치된 디스크를 USB로, 늦게 (DC-M1) ────────────────────────
+#
+# 커널은 PID 1을 띄우기 전에 디스크를 기다려 주지 않는다(DC 확인 2). 그런데
+# 게이트에서는 그 틈이 안 보인다 — TCG 위에서 42MB initramfs를 푸는 1.7초
+# 동안 NVMe가 다 붙어 버린다(DC-M0 실측 2). 그래서 틈을 일부러 벌린다.
+# usb-storage는 장치를 붙이고 delay_use만큼 쉰 뒤에 SCSI 스캔을 하므로, 3초를
+# 주면 sda2가 init이 처음 훑은 뒤에 생긴다(DC-M0 실측 1: 1.72초 뒤).
+#
+# 왜 -kernel인가. cmdline에 delay_use를 넣을 자리가 필요하고, tars.installed도
+# ESP의 limine.conf가 아니라 여기서 준다. init이 보는 것은 /proc/cmdline의
+# 토큰뿐이라 어디서 왔는지는 모른다. 디스크는 부팅 6이 --wipe로 막 만든 그것이다.
+boot_kernel_usb() {
+  local name="$1" cmdline="$2"
+  LOG="${WORK}/boot-${name}.log"
+  FIFO="${WORK}/boot-${name}.fifo"
+  rm -f "$FIFO"; mkfifo "$FIFO"
+  exec 4<>"$FIFO"
+  qemu-system-x86_64 \
+    -machine q35 \
+    -m "$GUEST_MEM" \
+    -kernel ../kernel/build/arch/x86/boot/bzImage \
+    -initrd ../kernel/initrd.cpio \
+    -append "$cmdline" \
+    -device qemu-xhci,id=xhci \
+    -drive file="$DISK",if=none,id=late,format=raw \
+    -device usb-storage,bus=xhci.0,drive=late \
+    -serial stdio \
+    -monitor none \
+    -display none \
+    -no-reboot \
+    < "$FIFO" > "$LOG" 2>&1 &
+  QEMU_PID=$!
+
+  local waited=0
+  while [ "$waited" -lt 180 ]; do
+    if grep -aq "tars-init: started console shell" "$LOG"; then break; fi
+    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
+    sleep 1; waited=$((waited + 1))
+  done
+  if ! grep -aq "tars-init: started console shell" "$LOG"; then
+    fail "boot ${name}: the console shell never started (${waited}s)" \
+      "PANIC" "tars-init"
+  fi
+  echo "boot ${name}: console shell up after ${waited}s"
+}
+
+echo "=== boot 7: the installed disk over USB, three seconds late ==="
+boot_kernel_usb 7 "console=ttyS0 tars.installed usb-storage.delay_use=3"
+
+# 판정 17. 이 milestone의 심장이다. init이 처음 훑었을 때 sda2는 없었고, 기다려서
+# 잡았다. appeared after가 없으면 기다림 없이 잡은 것이라 틈이 안 벌어진
+# 판이고(판정이 아무것도 증명 안 한다), config storage가 없으면 기다림이 없거나
+# 너무 짧다 — 기다림을 뺀 init은 여기서 among 42 candidates를 찍는다.
+if ! grep -aqF "tars-init: config storage appeared after" "$LOG"; then
+  fail "init did not have to wait for the late USB disk, or never found it" \
+    "tars-init: config storage" "tars-init: waited" "tars-init: no disk labelled" "sda: sda1"
+fi
+if ! grep -aqF "tars-init: config storage /dev/sda2 (label tars-config)" "$LOG"; then
+  fail "init waited but did not pick p2 of the late USB disk" \
+    "tars-init: config storage" "tars-init: no disk labelled"
+fi
+if ! grep -aq "tars-init: mounted ext2 at /config" "$LOG"; then
+  fail "the late config partition was picked but never mounted" "tars-init: failed to mount"
+fi
+echo "init waited $(grep -aoE 'appeared after [0-9]+ms' "$LOG" | head -1 | sed 's/appeared after //') for the late USB disk and mounted its p2"
+
+stop_guest
+
 echo "PASS"
 exit 0
```

- [ ] **Step 2: 체인 단독 (약 1분 30초)**

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c \
  'rm -rf init/.zig-cache init/zig-out && bash install/check.sh'
```

Expected: `init waited N ms for the late USB disk and mounted its p2`(N은 1500~1800
언저리) · 부팅 2·4·6이 6~7초 · `PASS`.

- [ ] **Step 3: 커밋** — `Boot the installed disk over late USB in the install chain`

## Task 4: 반사실

- [ ] **Step 1:** `main.zig`의 `const max_ms: u32 = if (installed) storage.CONFIG_WAIT_MS else 0;`를
  `const max_ms: u32 = 0;`로 바꾸고 Task 3 Step 2의 명령(캐시 삭제 포함)을 돌린다.

Expected: `FAIL: init did not have to wait for the late USB disk, or never found it`,
context에 `tars-init: no disk labelled tars-* among 42 candidates`.

- [ ] **Step 2:** 되돌리고 `git diff init/src/main.zig`가 비었는지 본다.

## Task 5: 루트 게이트와 기록

- [ ] **Step 1:** `CHAINS`의 `DI-M2` 이름을 그대로 둘지 본다 — 체인은 DI의 것이고 DC가
  부팅 하나를 더했다. 이름을 `DC-M1`로 바꾼다.
- [ ] **Step 2:** 루트 게이트(약 39분). `TARS check PASS`, `FAIL` 0줄.
- [ ] **Step 3:** design에 "DC-M1이 실행으로 증명한 것", `Status:`, HANDOFF, 커밋.
