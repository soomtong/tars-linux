# DC-M2 — DI가 남긴 작은 것 다섯

> 이 plan을 실행하는 사람에게: 아래 diff는 작업 트리에서 시제품으로 쓰고 install
> 체인과 반사실 셋까지 돌린 것이다(M1과 같은 방식). 반사실은 컨테이너 안에서
> `.zig-cache`와 `zig-out`을 지우고 돌린다(`project_zig_out_staleness`).

Goal: DC design 결정 5의 다섯 — 4Kn GPT · 옛 ISO 서명 · 넘치는 줄 · YES를 줄로 ·
PVD 음성 둘 — 을 고치고 호스트 검사와 install 체인이 지키게 한다.

Architecture: `disk.describe`가 서명을 "앞의 구조 먼저" 순서(ext2 → GPT(512 · 4096)
→ iso9660 → MBR)로 본다. `disk.clip`이 넘치는 줄의 앞부분을 남기고 `...\n`로
끝낸다. `install.readLine`이 개행까지 한 바이트씩 읽는다. 체인은 부팅 1에 4Kn
임시 NVMe(`nvme1n1`, 64MiB)를 붙여 판정 4a~4c를 본다.

Tech Stack: Zig 0.16 · bash · QEMU(`nvme` · `logical_block_size=4096`) · 게스트의
`sfdisk` · `sh`(= bash)

---

## plan을 쓰며 정한 것 (2026-09-25~26)

1. 라벨의 제어 문자는 이미 DI-M2가 고쳤다(`disk.printable`). 이월은 다섯이다.
2. 우리 ISO에는 GPT가 없다. `out/tars.iso`의 512와 4096에 `EFI PART`가 없고(`fc8b…` ·
   `5050…`), 1080에 ext2 매직도 없다(`5666`). `make_iso.sh`가 `--protective-msdos-label`
   로 MBR만 쓴다. 그래서 GPT와 ext2를 ISO보다 먼저 봐도 진짜 매체는 `iso9660 TARS`다
   — 판정 2가 매 회차 그것을 본다.
3. 옛 PVD는 `tars-install`이 만든 디스크에는 안 남는다(`sfdisk --wipe always`가
   `CD001`을 지운다). 남의 도구로 다시 만든 스틱의 이야기다.
4. YES의 버그는 이월 목록이 적은 것보다 나빴다. `YES` + ` please\n`로 쪼개 오면 전
   코드는 `YES`만 보고 확인으로 읽는다 — 반사실 b에서 `writing the partition table`
   까지 가고 64MiB라 `sfdisk`가 멈췄다.
5. Zig 0.16의 `bufPrint`는 넘칠 때 `NoSpaceLeft`를 돌려주며 buf를 앞에서부터 채워
   둔다(`/tmp/dcm2/clip.zig`: `buf=[tars-install: /d]`). `clip`이 거기에 기대고
   `disk_test` 11이 그 동작을 지킨다.

## Task 1: `disk.zig` · `disk_test.zig`

- [ ] **Step 1: diff**

```diff
diff --git a/init/src/disk.zig b/init/src/disk.zig
index cacb7e0..1658c50 100644
--- a/init/src/disk.zig
+++ b/init/src/disk.zig
@@ -26,24 +26,38 @@ pub const Seen = struct {
     label: []const u8 = "",
 };
 
-/// 앞머리에 무엇이 보이는가. 순서가 뜻이 있다.
+/// 4Kn 디스크(논리 섹터 4096바이트)의 GPT 헤더 자리. GPT 헤더는 LBA 1에
+/// 있으므로 섹터 크기가 곧 오프셋이다(DC 결정 5의 1).
+const GPT_SIG_OFF_4KN: usize = 4096;
+
+/// 앞머리에 무엇이 보이는가. 순서가 뜻이 있다(DC-M2가 바꿨다).
 ///
-///   iso9660이 첫째다. 하이브리드 ISO는 MBR 서명도 갖고 있어서(make_iso.sh의
-///   --protective-msdos-label) MBR을 먼저 보면 USB 스틱의 ISO가 "mbr"로 읽힌다.
-///   ext2가 GPT보다 먼저다. 둘은 겹치지 않지만(GPT 디스크의 1080은 첫 파티션
-///   항목의 이름 자리다) 파티션 없는 ext2가 게이트 디스크의 모양이라 먼저 둔다.
+///   앞에 있는 구조를 먼저 믿는다. 파티션 도구와 mkfs는 디스크 맨 앞(512 ·
+///   1080 · 4096)을 새로 쓰지만 32KiB의 ISO PVD는 안 건드리는 일이 많다 —
+///   ISO를 구웠던 스틱을 다른 도구로 GPT나 ext2로 다시 만들면 옛 PVD가 남고,
+///   ISO를 먼저 보면 그 스틱이 `iso9660 TARS`, 곧 부팅 매체로 읽혔다(DI-M1
+///   실측 15). tars-install은 sfdisk --wipe always로 PVD까지 지우므로 이것은
+///   남의 도구로 만든 디스크의 이야기다.
+///
+///   ext2가 GPT보다 먼저다. 둘은 겹치지 않지만(512바이트 섹터 GPT의 1080은 첫
+///   파티션 항목의 이름 자리다) 파티션 없는 ext2가 게이트 디스크의 모양이다.
+///   GPT는 512와 4096 둘 다 본다. 4Kn 디스크에서 512만 보면 보호 MBR만 보여
+///   `mbr`로 읽혔고, 설치된 4Kn 디스크가 TARS installed로 안 보여 갱신 대신
+///   새 설치(설정까지 지운다)로 갔다.
+///   iso9660은 MBR보다 먼저다. 하이브리드 ISO는 MBR 서명도 갖고 있어서
+///   (make_iso.sh의 --protective-msdos-label) MBR을 먼저 보면 USB 스틱의 ISO가
+///   "mbr"로 읽힌다. 우리 ISO에는 GPT가 없다(512 · 4096에 `EFI PART`가 없다 —
+///   DC-M2 plan) — 그래서 GPT를 ISO보다 먼저 봐도 진짜 매체는 그대로다.
 ///   blank는 끝에서 둘째다. 다 0이면 어떤 서명도 안 맞았다는 뜻이다.
 pub fn describe(head: []const u8) Seen {
+    if (storage.ext2Label(head)) |label| return .{ .kind = .ext2, .label = label };
+    if (hasGptAt(head, GPT_SIG_OFF) or hasGptAt(head, GPT_SIG_OFF_4KN)) return .{ .kind = .gpt };
     if (head.len >= ISO_PVD + 40 + ISO_ID_LEN and head[ISO_PVD] == 1 and
         std.mem.eql(u8, head[ISO_PVD + 1 ..][0..5], "CD001"))
     {
         const id = head[ISO_PVD + 40 ..][0..ISO_ID_LEN];
         return .{ .kind = .iso9660, .label = std.mem.trimEnd(u8, id, " ") };
     }
-    if (storage.ext2Label(head)) |label| return .{ .kind = .ext2, .label = label };
-    if (head.len >= GPT_SIG_OFF + 8 and std.mem.eql(u8, head[GPT_SIG_OFF..][0..8], "EFI PART")) {
-        return .{ .kind = .gpt };
-    }
     if (head.len >= 512 and head[510] == 0x55 and head[511] == 0xAA) return .{ .kind = .mbr };
     for (head) |b| {
         if (b != 0) return .{ .kind = .unknown };
@@ -51,6 +65,27 @@ pub fn describe(head: []const u8) Seen {
     return .{ .kind = .blank };
 }
 
+fn hasGptAt(head: []const u8, off: usize) bool {
+    return head.len >= off + 8 and std.mem.eql(u8, head[off..][0..8], "EFI PART");
+}
+
+/// 한 줄을 buf에 짓는다. 넘치면 앞부분을 남기고 끝을 `...\n`으로 덮는다 —
+/// install.zig의 say와 complain이 쓴다(DC 결정 5의 3).
+///
+/// 전에는 넘치면 줄을 통째로 버렸다. 긴 인자를 되풀이하는 에러
+/// (`<arg> is not a disk ...`)가 그래서 아무 말 없이 종료 코드만 남겼다.
+///
+/// Zig 0.16의 bufPrint는 넘칠 때 NoSpaceLeft를 돌려주면서 buf에 들어간
+/// 만큼은 채워 둔다(DC-M2 plan에서 확인). 그 동작에 기댄다 — 바뀌면
+/// disk_test의 검사 11이 빨개진다. buf는 4바이트보다 커야 한다.
+pub fn clip(buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
+    return std.fmt.bufPrint(buf, fmt, args) catch {
+        const tail = "...\n";
+        @memcpy(buf[buf.len - tail.len ..], tail);
+        return buf;
+    };
+}
+
 /// 라벨을 화면에 찍을 모양으로. 제어 문자(0x00~0x1f · 0x7f)는 `?`로 바꾼다 —
 /// 라벨은 디스크에 있는 바이트라 누구든 ESC를 심을 수 있고, 그대로 찍으면
 /// 목록이 터미널을 조종한다(DI-M1 실측 15). 0x80 위는 그대로 둔다. UTF-8
diff --git a/init/src/disk_test.zig b/init/src/disk_test.zig
index 9725940..fd59965 100644
--- a/init/src/disk_test.zig
+++ b/init/src/disk_test.zig
@@ -258,5 +258,82 @@ pub fn main() !void {
         }
     }
 
+    // ── 11. clip — 넘치는 줄은 앞부분과 `...\n` (DC-M2) ────────────────
+    {
+        var small: [16]u8 = undefined;
+        try expectText(disk.clip(&small, "a {s}\n", .{"b"}), "a b\n", "a line that fits");
+        // 넘치면 앞 12바이트가 남고 끝 넷이 `...\n`이다. 이 검사가 Zig의
+        // bufPrint가 넘칠 때 buf를 채워 둔다는 것까지 본다 — 안 채우면 앞
+        // 12바이트가 undefined라 글자가 안 맞는다.
+        try expectText(
+            disk.clip(&small, "tars-install: {s} end\n", .{"/dev/aaaaaaaaaaaaaaaaaaaaaaaa"}),
+            "tars-install...\n",
+            "a line that overflows",
+        );
+    }
+
+    // ── 12. 앞의 구조가 뒤의 옛 서명을 이긴다 (DC-M2) ─────────────────
+    {
+        // 4Kn 디스크의 GPT. 보호 MBR은 0에, 헤더는 LBA 1 = 4096에 있다.
+        const h = clear();
+        h[510] = 0x55;
+        h[511] = 0xAA;
+        @memcpy(h[4096..][0..8], "EFI PART");
+        try expectKind(disk.describe(h), .gpt, "", "4Kn gpt");
+    }
+    {
+        // TARS ISO를 구웠던 스틱을 남의 도구로 GPT로 다시 만든 것. PVD가 남아
+        // 있어도 GPT다 — 전에는 `iso9660 TARS`로 읽혀 부팅 매체 취급을 받았다.
+        const h = clear();
+        h[32768] = 1;
+        @memcpy(h[32769..][0..5], "CD001");
+        @memset(h[32768 + 40 ..][0..32], ' ');
+        @memcpy(h[32768 + 40 ..][0..4], "TARS");
+        h[510] = 0x55;
+        h[511] = 0xAA;
+        @memcpy(h[512..][0..8], "EFI PART");
+        try expectKind(disk.describe(h), .gpt, "", "gpt over a stale iso");
+    }
+    {
+        // 같은 스틱을 통째로 mkfs.ext2한 것. ext2 라벨이 이긴다.
+        const h = clear();
+        h[32768] = 1;
+        @memcpy(h[32769..][0..5], "CD001");
+        @memcpy(h[32768 + 40 ..][0..4], "TARS");
+        h[1024 + 56] = 0x53;
+        h[1024 + 57] = 0xEF;
+        @memcpy(h[1024 + 120 ..][0..5], "stick");
+        try expectKind(disk.describe(h), .ext2, "stick", "ext2 over a stale iso");
+    }
+
+    // ── 13. PVD의 음성 둘 (DI-M1 실측 15의 이월) ──────────────────────
+    {
+        // type 바이트가 1이 아니다. CD001 뒤의 모양이 같아도 primary volume
+        // descriptor가 아니면(2는 supplementary) ISO로 안 읽는다.
+        const h = clear();
+        h[32768] = 2;
+        @memcpy(h[32769..][0..5], "CD001");
+        @memcpy(h[32768 + 40 ..][0..4], "TARS");
+        if (disk.describe(h).kind == .iso9660) {
+            std.debug.print("FAIL: a descriptor of type 2 was read as a primary volume\n", .{});
+            return error.WrongPvdType;
+        }
+    }
+    {
+        // 볼륨 ID 32바이트를 공백 없이 꽉 채웠다. 라벨은 32글자 그대로이고,
+        // `TARS`로 시작해도 TARS 매체가 아니다 — 접두사가 아니라 같음으로 본다.
+        const h = clear();
+        h[32768] = 1;
+        @memcpy(h[32769..][0..5], "CD001");
+        const id = "TARSXXXXXXXXXXXXXXXXXXXXXXXXXXXX";
+        @memcpy(h[32768 + 40 ..][0..32], id);
+        const seen = disk.describe(h);
+        try expectKind(seen, .iso9660, id, "a full 32-byte volume id");
+        if (disk.isTarsMedium(seen)) {
+            std.debug.print("FAIL: a volume id that only starts with TARS was taken as the medium\n", .{});
+            return error.TarsPrefixTaken;
+        }
+    }
+
     std.debug.print("disk_test: signatures, sizes, arguments, labels, the YES gate and the ESP conf hold\n", .{});
 }
```

- [ ] **Step 2:** `docker run … bash -c 'cd init && zig build && zig build test'` — 종료 0.
- [ ] **Step 3: 커밋** — `Read front structures before a stale ISO and find 4Kn GPT`

## Task 2: `install.zig`

- [ ] **Step 1: diff**

```diff
diff --git a/init/src/install.zig b/init/src/install.zig
index ec62920..9f1399e 100644
--- a/init/src/install.zig
+++ b/init/src/install.zig
@@ -37,18 +37,18 @@ fn writeAll(fd: i32, bytes: []const u8) void {
 }
 
 /// 사람이 읽는 줄은 stdout으로. 게이트는 시리얼에서 이것을 읽는다.
+/// 넘치는 줄은 잘라서라도 찍는다(disk.clip). 그대로 버리면 긴 인자를 되풀이하는
+/// 에러가 말없이 사라진다(DC 결정 5의 3).
 fn say(comptime fmt: []const u8, args: anytype) void {
     var buf: [512]u8 = undefined;
-    const text = std.fmt.bufPrint(&buf, fmt, args) catch return;
-    writeAll(1, text);
+    writeAll(1, disk.clip(&buf, fmt, args));
 }
 
 /// 실패는 stderr로. 한 줄에 무엇이 몇으로 죽었는지가 다 있어야 한다
 /// (design 결정 5).
 fn complain(comptime fmt: []const u8, args: anytype) void {
     var buf: [512]u8 = undefined;
-    const text = std.fmt.bufPrint(&buf, "tars-install: " ++ fmt ++ "\n", args) catch return;
-    writeAll(2, text);
+    writeAll(2, disk.clip(&buf, "tars-install: " ++ fmt ++ "\n", args));
 }
 
 // ── 작은 파일 읽기 ───────────────────────────────────────────────────
@@ -444,6 +444,29 @@ fn writeConf(dst: [:0]const u8, text: []const u8) ?u64 {
     return text.len;
 }
 
+/// fd에서 개행까지 한 줄. 개행 없이 EOF가 오면 거기까지, 에러나 buf가 차도록
+/// 개행이 없으면 null이다(너무 긴 답은 YES가 아니다).
+///
+/// read 한 번으로 받던 때는 입력이 파이프로 쪼개져 오면 첫 조각만 봤다.
+/// `YES`와 ` please\n`로 나뉘어 오면 `YES please`를 확인으로 읽고 디스크를
+/// 지웠다(DC-M2가 찾았다 — DI의 이월 목록은 "거절하는 쪽으로 틀린다"고 적었지만
+/// 반대쪽도 있었다). 한 바이트씩 읽는 것은 개행 뒤의 입력을 삼키지 않기
+/// 위해서다. 사람이 치는 한 줄이라 비용이 없다.
+fn readLine(fd: i32, buf: []u8) ?[]const u8 {
+    var len: usize = 0;
+    while (len < buf.len) {
+        const n = linux.read(fd, buf[len..].ptr, 1);
+        if (failed(n)) |e| {
+            if (e == .INTR) continue;
+            return null;
+        }
+        if (n == 0) return buf[0..len];
+        if (buf[len] == '\n') return buf[0 .. len + 1];
+        len += 1;
+    }
+    return null;
+}
+
 // ── 설치 ─────────────────────────────────────────────────────────────
 
 fn install(
@@ -507,8 +530,8 @@ fn install(
     if (!yes) {
         say("type YES to continue: ", .{});
         var line: [64]u8 = undefined;
-        const n = linux.read(0, &line, line.len);
-        if (failed(n) != null or !disk.confirmed(line[0..n])) {
+        const got = readLine(0, &line);
+        if (got == null or !disk.confirmed(got.?)) {
             say("tars-install: not confirmed; nothing was changed.\n", .{});
             return 1;
         }
```

- [ ] **Step 2:** Task 1 Step 2와 같다.
- [ ] **Step 3: 커밋** — `Clip long lines and read the YES answer up to its newline`

## Task 3: install 체인의 판정 4a~4c

- [ ] **Step 1: diff**

```diff
diff --git a/install/check.sh b/install/check.sh
index 9952f65..5e0bd24 100755
--- a/install/check.sh
+++ b/install/check.sh
@@ -163,7 +163,14 @@ wait_log() {
 
 # ── 부팅 1: ISO + 빈 NVMe ──────────────────────────────────────────────
 echo "=== boot 1: the ISO and a blank NVMe ==="
-boot_guest 1 -cdrom ../out/tars.iso
+# 둘째 NVMe는 DC-M2의 임시 디스크다. 논리 섹터가 4096바이트(4Kn)이고 판정
+# 4a~4c만 쓴다. 설치 대상(nvme0n1)과 따로 둬서, 옛 코드가 YES를 잘못 읽어도
+# 지워지는 것이 이것뿐이게 한다. 64MiB라 배치가 안 들어가 sfdisk에서 멈춘다.
+SCRATCH="${WORK}/scratch-4kn.img"
+truncate -s 64M "$SCRATCH"
+boot_guest 1 -cdrom ../out/tars.iso \
+  -drive file="$SCRATCH",if=none,id=scratch,format=raw \
+  -device nvme,drive=scratch,serial=tarsscratch,logical_block_size=4096,physical_block_size=4096
 
 # 판정 1. 목록. 쓰는 법의 마지막 줄이 목록의 끝이다.
 send "tars-install"
@@ -203,6 +210,49 @@ if [ "$(clean | grep -acE '^  /dev/nvme0n1 .* blank$')" -lt 2 ]; then
 fi
 echo "answering 'no' left the disk blank"
 
+# 판정 4a (DC-M2). 4Kn 디스크의 GPT. 헤더가 512가 아니라 4096에 있어서 전에는
+# 보호 MBR만 보여 `foreign (mbr)`로 읽혔다 — 설치된 4Kn 디스크가 TARS installed로
+# 안 보여 갱신 대신 새 설치로 갈 자리다. GPT는 게스트의 진짜 sfdisk가 만든다.
+send "echo dc-lbs-\$(cat /sys/block/nvme1n1/queue/logical_block_size)"
+wait_log "dc-lbs-4096" \
+  || fail "the scratch NVMe is not 4Kn; QEMU ignored logical_block_size" "dc-lbs-"
+send "printf 'label: gpt\n' | sfdisk -q /dev/nvme1n1 && printf 'dc-4kn-%s\n' labelled"
+wait_log "dc-4kn-labelled" \
+  || fail "sfdisk could not label the 4Kn scratch disk" "sfdisk" "dc-4kn"
+send "tars-install"
+for _ in $(seq 1 300); do
+  clean | grep -aE '^  /dev/nvme1n1 .* foreign \(gpt\)$' >/dev/null && break
+  sleep 0.1
+done
+if ! clean | grep -aE '^  /dev/nvme1n1 .* foreign \(gpt\)$' >/dev/null; then
+  fail "a GPT on a 4Kn disk was not listed as foreign (gpt)" "/dev/nvme1n1"
+fi
+echo "a GPT on a 4096-byte-sector disk reads as gpt"
+
+# 판정 4b (DC-M2). YES를 줄로 읽는다. 파이프로 `YES`와 ` please\n`를 1초 사이를
+# 두고 보내면, read 한 번으로 받던 전 코드는 `YES`만 보고 확인으로 읽었다.
+# 지금은 `YES please`를 다 모아 거절한다. not confirmed가 판정 4에 이어 둘째다.
+send "sh -c '(printf YES; sleep 1; printf \" please\\n\") | tars-install /dev/nvme1n1'; printf 'dc-split-%s\n' done"
+wait_log "dc-split-done" 30 \
+  || fail "the split YES never came back to the shell" "tars-install:" "dc-split"
+if [ "$(grep -acF "tars-install: not confirmed; nothing was changed." "$LOG")" -lt 2 ]; then
+  fail "'YES' then ' please' arriving apart was taken as YES" \
+    "tars-install:" "writing the partition table"
+fi
+echo "a YES split across two writes is read as the whole line, and refused"
+
+# 판정 4c (DC-M2). 넘치는 에러 줄은 잘려서라도 나온다. 600글자 디스크 이름의
+# `is not a disk` 줄은 512바이트 버퍼를 넘어서, 전에는 통째로 사라지고 종료
+# 코드만 남았다. 타이핑한 줄의 에코는 `tars-install /dev/`(콜론 없음)라 안 섞인다.
+LONG="$(printf 'x%.0s' $(seq 1 600))"
+send "tars-install /dev/${LONG}; printf 'dc-long-%s\n' done"
+wait_log "dc-long-done" \
+  || fail "the long argument never came back to the shell" "dc-long"
+if ! clean | grep -aE '^tars-install: /dev/x+\.\.\.$' >/dev/null; then
+  fail "the error for a 600-character argument was not printed, clipped" "tars-install: /dev/x"
+fi
+echo "an error line longer than its buffer is printed clipped, not dropped"
+
 # 판정 5. 설치. mke2fs가 4초, sfdisk가 3.5초(DI-M0 실측 8)라 TCG에서
 # 넉넉히 120초를 준다.
 send "tars-install /dev/nvme0n1 --yes"
```

- [ ] **Step 2:** 캐시를 지우고 체인 단독. Expected: `a GPT on a 4096-byte-sector disk
  reads as gpt` · `a YES split across two writes is read as the whole line, and
  refused` · `an error line longer than its buffer is printed clipped, not dropped` ·
  `PASS`.
- [ ] **Step 3: 커밋** — `Check 4Kn GPT, a split YES and a clipped error in the install chain`

## Task 4: 반사실 셋 (하나씩, 매번 캐시 삭제)

| | 되돌림 | Expected |
|---|---|---|
| a | `describe`에서 `or hasGptAt(head, GPT_SIG_OFF_4KN)`를 뺀다 | `FAIL: a GPT on a 4Kn disk was not listed as foreign (gpt)` — 목록에 `foreign (mbr)` |
| b | `readLine(0, &line)` 대신 `read` 한 번 | `FAIL: 'YES' then ' please' arriving apart was taken as YES` |
| c | `clip`의 catch가 `""`를 돌려준다 | `FAIL: the error for a 600-character argument was not printed, clipped` |

## Task 5: 루트 게이트와 닫기

- [ ] `CHAINS`의 이름을 `DC-M2`로. 루트 게이트(약 39분).
- [ ] design 실측 · `Status: 끝났다` · `CLAUDE.md` 표 · HANDOFF · 커밋.
