# DI-M1 — `tars-install`이 빈 디스크에 설치하고, 그 디스크만으로 뜬다

> 이 plan을 실행하는 사람에게: REQUIRED SUB-SKILL — superpowers:executing-plans
> (또는 subagent-driven-development)로 Task 단위로 밟는다. 단계는 체크박스
> (`- [ ]`)다. 이 저장소의 규칙대로 파일 편집·명령 실행·커밋은 Claude Code가
> 하고, 매 편집 뒤 `git diff --stat`으로 더한 줄과 지운 줄을 따로 센다.

Goal: USB(ISO)로 부팅한 기계에서 `tars-install /dev/nvme0n1 --yes`를 치면 GPT에
ESP와 설정 파티션이 생기고 부트 파일 넷이 복사되며, `-cdrom`을 뗀 다음 부팅에서
`init`이 `/dev/nvme0n1p2`를 설정 디스크로 잡는다.

Architecture: `init/` 옆에 정적 실행 파일 `tars-install`을 하나 더 빌드한다.
순수한 판정(디스크 앞머리에 무엇이 보이는가 · 크기 · 인자 · YES)은
`disk.zig`에, 시스템 콜을 하는 쪽(매체 찾기 · 목록 · 외부 도구 셋 ·
복사)은 `install.zig`에 둔다. `storage.zig`는 디스크 목록을 `DISKS`로
내보내고 후보에 각 디스크의 첫 두 파티션을 더한다. 판정은 열세번째 체인
`install/check.sh`의 OVMF 부팅 둘이다.

Tech Stack: Zig 0.16.0(libc 없음, `std.os.linux`) · sfdisk 2.41 · dosfstools 4.2 ·
e2fsprogs 1.47 · QEMU(OVMF · q35 · NVMe) · bash

---

## 이 plan을 쓰기 전에 한 것

plan의 코드를 `/tmp/dim1/`에 시제품으로 먼저 썼다. `init/`을 통째로 복사해
아래 Task의 코드를 그대로 넣고 호스트(macOS, zig 0.16.0)에서 확인한 것 셋이다.

- `zig build`가 `init`과 `tars-install`을 둘 다 x86_64-linux-musl로 만든다
  (`tars-install` 3.3MB, ReleaseSafe).
- `storage_test`가 `42 candidates`로, `disk_test`가 전부 통과한다.
- `install/check.sh` 초안이 `bash -n`을 지나고 `check.sh`의 조기 종료 파이프
  패턴(`EARLY_EXIT_PIPE`)에 한 줄도 안 걸린다.

부팅은 한 번도 안 했다. 그래서 `install.zig`가 게스트에서 실제로 도는지와
체인의 판정 여덟은 Task 6이 처음 본다. `devices_test`·`power_test`는 macOS에서
실패하는데 리눅스 시스템 콜을 부르는 검사라서 그렇고, 컨테이너에서는 원래
통과한다(Task 0이 기준선으로 확인한다).

## design과 달라진 것 · 정한 것

design의 milestone 표가 M1의 범위다 — 목록과 새 설치 · 파티션 후보 ·
`-V TARS` · 부팅 1 · 2. 쓰면서 정한 것이 여섯이다.

1. 목록의 상태 칸은 셋이 아니라 둘이다 — `boot medium`과 앞머리에 보이는
   것(`blank` · `foreign (gpt)` · `foreign (ext2 tars-config)` 등). design 결정
   7의 `TARS installed`는 p1을 붙여 `boot/bzImage`를 봐야 하는 판정이고 그것을
   쓰는 곳이 갱신 경로(결정 8)라 M2로 미룬다. M1에서 설치된 디스크는
   `foreign (gpt)`로 보인다.
2. 순수한 판정을 `disk.zig`로 가른다. design 결정 5는 `install.zig` 하나를
   적었다. `storage.zig`가 `tarsLabel`(순수)과 `findConfigDisk`(콜)를 가른
   것과 같은 선이고, 그래야 `disk_test`가 호스트에서 0.1초에 본다.
3. 외부 도구의 출력은 `/tmp/tars-install/<도구>.log`로 보내고 실패했을
   때만 보여 준다. DI-M0 실측 8의 iconv 경고 세 줄을 사람이 매번 보지 않게
   하고, 실패하면 도구가 한 말이 그대로 나온다.
4. `sfdisk`에 `--wipe-partitions always`를 더한다. 이미 설치된 디스크에 다시
   설치하면 p2 자리에 옛 ext2가 그대로 남고, `mke2fs`가 그것을 보면 tty에서
   `Proceed anyway?`를 묻는다. 도구의 stdin도 `/dev/null`로 준다. M1의 체인은
   빈 디스크만 설치하므로 이 경로를 안 밟는다 — M2의 부팅 3(`--wipe`)이 밟는다.
5. 목록 머리 줄이 ISO의 볼륨 ID를 읽는다(`boot medium /dev/sr0 (iso9660 TARS,
   50 MB)`). design 확인 9는 `-V`를 "사람이 `blkid`로 알아보기 위한 것"으로
   적었는데 게스트에 `blkid`를 안 싣는다. 이 줄이 그 자리를 대신하고, 체인의
   판정 2가 `-V TARS`를 이 줄로 본다.
6. 체인은 시리얼 FIFO로 콘솔 셸에 친다(DI-M0 하네스의 모양). 다른 체인들처럼
   `sendkey`로 terminal 화면을 보면 목록 여러 줄을 격자에서 읽어야 한다. 콘솔
   셸의 출력은 시리얼 로그에 그대로 남는다.

## 파일 지도

| 파일 | 무엇 | Task |
|---|---|---|
| `init/src/storage.zig` | `DISKS` 공개 · 파티션 28개 · `CANDIDATES = DISKS ++ PARTITIONS` · `partitionName` · `ext2Label` · `readHead` 공개 | 1 |
| `init/src/storage_test.zig` | 검사 8 · 9 · 10 | 1 |
| `init/src/main.zig` | 주석 셋(후보 열넷 → 마흔둘) | 1 |
| `init/src/disk.zig` (새) | 앞머리 판정 · 상태 칸 · 크기 · 인자 · YES · 배치 상수 | 2 |
| `init/src/disk_test.zig` (새) | 위의 검사 | 2 |
| `init/build.zig` | `disk_test` · `tars-install` exe | 2 · 3 |
| `init/src/install.zig` (새) | 매체 찾기 · 목록 · 설치 | 3 |
| `kernel/make_initrd.sh` | `usr/bin/tars-install` | 4 |
| `tools/check.sh` | `WANT+=(usr/bin/tars-install)` | 4 |
| `boot/make_iso.sh` | `-V TARS` | 4 |
| `install/check.sh` (새) | 열세번째 체인, 부팅 둘 | 5 |
| `check.sh` | `CHAINS`에 `DI-M1:./install/check.sh` | 7 |
| design · 기억 · `MEMORY.md` · `HANDOFF.md` | 끝난 뒤 | 8 |

---

## Task 0 — 기준선

호스트(macOS)에서 친다. 이 Task가 끝나기 전에는 저장소를 한 글자도 안 고친다.

- [ ] Step 1: OrbStack을 켜고 이미지가 있는지 본다

```bash
orb start
docker image inspect tars-devcontainer --format '{{.Created}}'
```

기대: 날짜 한 줄. 없다고 나오면 `docker build -t tars-devcontainer devcontainer/`
(DI-M0이 패키지 열을 더했다 — HANDOFF의 경고).

- [ ] Step 2: 작업 트리가 깨끗하고 `init`의 호스트 검사가 초록인지 본다

```bash
git status --short
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init && zig build && zig build test' 2>&1 | tail -8
```

기대: `git status`가 빈 출력, 마지막에 `storage_test: … (14 candidates)`가 있고
`error`가 없다.

## Task 1 — `storage.zig`: 파티션을 후보에 더한다 (design 결정 6)

Files: Modify `init/src/storage.zig` · `init/src/storage_test.zig` · `init/src/main.zig`(주석)

- [ ] Step 1: 검사를 먼저 쓴다

`init/src/storage_test.zig`의 `// 후보 목록이 통째로 사라지지 않았는지만 본다.`
바로 위에 검사 셋을 넣는다.

```diff
--- a/init/src/storage_test.zig
+++ b/init/src/storage_test.zig
@@ -128,6 +128,91 @@
         return error.WrongMagicAccepted;
     }
 
+    // ── 8. ext2Label은 남의 라벨도 돌려준다 ─────────────────────────
+    //
+    // tars-install의 목록이 "foreign (ext2 debian-root)"를 찍으려면 접두사와
+    // 무관하게 라벨을 읽어야 한다. 그리고 라벨이 빈 ext2는 null이 아니라 빈
+    // 문자열이어야 "ext2가 아니다"와 갈린다(DI-M1).
+    {
+        const got = storage.ext2Label(full(EXT2, "debian-root")) orelse {
+            std.debug.print("FAIL: ext2Label rejected an ext2 disk with a foreign label\n", .{});
+            return error.ForeignLabelUnread;
+        };
+        if (!std.mem.eql(u8, got, "debian-root")) {
+            std.debug.print("FAIL: want 'debian-root', got '{s}'\n", .{got});
+            return error.WrongForeignLabel;
+        }
+        const empty = storage.ext2Label(full(EXT2, "")) orelse {
+            std.debug.print("FAIL: an unlabelled ext2 disk read as not-ext2\n", .{});
+            return error.EmptyLabelIsNull;
+        };
+        if (empty.len != 0) {
+            std.debug.print("FAIL: want an empty label, got '{s}'\n", .{empty});
+            return error.EmptyLabelNotEmpty;
+        }
+        @memset(&head, 0);
+        if (storage.ext2Label(&head) != null) {
+            std.debug.print("FAIL: ext2Label read a label off a disk with no magic\n", .{});
+            return error.NoMagicLabelled;
+        }
+    }
+
+    // ── 9. 파티션 이름 규칙 ───────────────────────────────────────────
+    //
+    // 이름이 숫자로 끝나는 디스크만 `p`가 든다. 넷 다 게스트에 실제로 있는
+    // 모양이다 — nvme0n1p2가 틀리면 설치한 기계가 설정을 못 찾는다.
+    {
+        const cases = [_][3][]const u8{
+            .{ "/dev/nvme0n1", "2", "/dev/nvme0n1p2" },
+            .{ "/dev/mmcblk0", "1", "/dev/mmcblk0p1" },
+            .{ "/dev/sda", "1", "/dev/sda1" },
+            .{ "/dev/vdb", "2", "/dev/vdb2" },
+        };
+        for (cases) |c| {
+            var buf: [32]u8 = undefined;
+            const n = try std.fmt.parseInt(u8, c[1], 10);
+            const got = storage.partitionName(&buf, c[0], n) orelse {
+                std.debug.print("FAIL: partitionName({s}, {d}) returned null\n", .{ c[0], n });
+                return error.PartitionNameNull;
+            };
+            if (!std.mem.eql(u8, got, c[2])) {
+                std.debug.print("FAIL: partitionName({s}, {d}) = '{s}', want '{s}'\n", .{ c[0], n, got, c[2] });
+                return error.WrongPartitionName;
+            }
+        }
+    }
+
+    // ── 10. 후보 목록 = 디스크 전부 → 그 다음 파티션 둘씩 ─────────────
+    //
+    // 손으로 적은 PARTITIONS가 규칙과 어긋나지 않는지, 그리고 디스크 전체가
+    // 전부 파티션보다 앞인지 본다. 뒤의 것이 게이트 열두 체인의 판정을 지킨다
+    // — 그 디스크들은 파티션 없는 ext2라 먼저 잡혀야 한다(DI design 결정 6).
+    {
+        const disks = storage.DISKS.len;
+        if (storage.CANDIDATES.len != disks * 3) {
+            std.debug.print("FAIL: want {d} candidates (disks + two partitions each), got {d}\n", .{
+                disks * 3, storage.CANDIDATES.len,
+            });
+            return error.WrongCandidateCount;
+        }
+        for (storage.DISKS, 0..) |disk, i| {
+            if (!std.mem.eql(u8, storage.CANDIDATES[i], disk)) {
+                std.debug.print("FAIL: candidate {d} is '{s}', want the disk '{s}'\n", .{ i, storage.CANDIDATES[i], disk });
+                return error.DiskNotFirst;
+            }
+            var n: u8 = 1;
+            while (n <= 2) : (n += 1) {
+                var buf: [32]u8 = undefined;
+                const want = storage.partitionName(&buf, disk, n).?;
+                const got = storage.CANDIDATES[disks + i * 2 + (n - 1)];
+                if (!std.mem.eql(u8, got, want)) {
+                    std.debug.print("FAIL: candidate {d} is '{s}', want '{s}'\n", .{ disks + i * 2 + (n - 1), got, want });
+                    return error.PartitionListDrifted;
+                }
+            }
+        }
+    }
+
     // 후보 목록이 통째로 사라지지 않았는지만 본다. 무엇이 몇 번째인가는
     // 판정이 아니다(design 결정 13: 순서는 tars- 디스크가 둘 이상일 때만
     // 쓰인다) — 하지만 목록이 비면 부팅마다 설정이 사라지고 증상은 조용하다.
```

- [ ] Step 2: 검사가 실패하는지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build test' 2>&1 | grep -E "error|storage_test" | head -5
```

기대: 컴파일 에러 — `storage.ext2Label`·`storage.partitionName`·`storage.DISKS`가
없다(`root source file struct 'storage' has no member named …`).

- [ ] Step 3: `storage.zig`를 고친다

셋이다. `CANDIDATES`를 `DISKS`와 `PARTITIONS`로 가르고 `partitionName`을 더한다 ·
`tarsLabel`의 몸통을 `ext2Label`로 옮기고 `tarsLabel`은 접두사만 본다 ·
`readHead`를 `pub`으로(`install.zig`가 쓴다). 주석의 "열넷"을 "마흔둘"로 고친다.

```diff
--- a/init/src/storage.zig
+++ b/init/src/storage.zig
@@ -40,14 +40,8 @@
 /// 라벨을 전부 바꿔야 하고, 그것은 체인 넷을 건드리는 일이다.
 pub const LABEL_PREFIX: []const u8 = "tars-";
 
-/// 훑어볼 블록 장치 이름들. 파티션은 안 본다 — 지금 디스크 전체가 파티션
-/// 테이블 없는 ext2 하나이고(CP design "1. virtio-blk + ext2"), 그 계약이 이
-/// milestone에서 안 바뀐다(design 결정 12).
+/// 디스크 이름들. 파티션이 아니라 장치 전체다.
 ///
-/// 부수 효과가 안전 쪽이다. 노트북의 내장 디스크는 예외 없이 GPT라 디스크
-/// 전체를 읽으면 매직이 안 맞는다 — 그래서 남의 root 파티션을 `/config`로
-/// 잡을 길이 아예 없다.
-///
 /// 순서가 판정을 바꾸는 상황은 `tars-` 라벨 디스크가 둘 이상일 때뿐이고,
 /// 게이트에도 실기에도 그런 상황이 없다. 그래서 "흔한 것부터"가 아니라
 /// "게이트가 매일 밟는 것부터"로 둔다 — 없는 장치를 여는 비용은
@@ -56,10 +50,14 @@
 /// 넷씩인 것은 devices.zig의 MAX_EVENT = 32와 같은 종류의 상한이다. 화면
 /// 하나에 셸 하나인 기계에 저장장치가 다섯 개 붙을 이유가 없고, 상한을 크게
 /// 잡으면 부팅마다 헛된 open이 는다.
-pub const CANDIDATES = [_][:0]const u8{
+///
+/// DI-M1부터 tars-install도 이 목록을 쓴다. 설치 대상으로 받는 이름과 목록에
+/// 보여 주는 이름이 이것이고, 부팅 때 찾는 것과 같은 코드여야 "설치했는데
+/// 못 찾는다"가 안 생긴다(DI design 결정 5).
+pub const DISKS = [_][:0]const u8{
     // virtio-blk. 게이트 다섯 체인이 이것이다.
     "/dev/vda",     "/dev/vdb",     "/dev/vdc", "/dev/vdd",
-    // 요즘 노트북의 내장 저장장치. machine 체인이 이것이다.
+    // 요즘 노트북의 내장 저장장치. machine·install 체인이 이것이다.
     "/dev/nvme0n1", "/dev/nvme1n1", "/dev/nvme2n1", "/dev/nvme3n1",
     // SATA(AHCI) · USB 스토리지 · SD 리더가 전부 SCSI 디스크로 나온다.
     "/dev/sda",     "/dev/sdb",     "/dev/sdc", "/dev/sdd",
@@ -67,6 +65,40 @@
     "/dev/mmcblk0", "/dev/mmcblk1",
 };
 
+/// 각 디스크의 첫 두 파티션. DI-M1이 RM 결정 12("파티션은 안 본다")를
+/// 바꿨다 — tars-install이 설정을 GPT의 p2에 두기 때문이다(DI design 결정 6).
+///
+/// 손으로 적는다. partitionName으로 comptime에 지을 수도 있지만 그러면
+/// Found.path가 가리키는 문자열의 수명을 따로 따져야 하고, 목록이 눈에
+/// 안 보인다. 둘이 어긋나지 않는 것은 storage_test가 본다.
+///
+/// 둘씩인 것은 우리가 만드는 배치가 p2까지이기 때문이다. RM 결정 12가 지키던
+/// 안전("남의 root를 잡지 않는다")은 라벨 필터가 계속 지킨다 — 남의 ext2
+/// root 파티션은 매직이 맞아도 라벨이 `tars-`로 시작하지 않는다.
+const PARTITIONS = [_][:0]const u8{
+    "/dev/vda1",       "/dev/vda2",       "/dev/vdb1",       "/dev/vdb2",
+    "/dev/vdc1",       "/dev/vdc2",       "/dev/vdd1",       "/dev/vdd2",
+    "/dev/nvme0n1p1",  "/dev/nvme0n1p2",  "/dev/nvme1n1p1",  "/dev/nvme1n1p2",
+    "/dev/nvme2n1p1",  "/dev/nvme2n1p2",  "/dev/nvme3n1p1",  "/dev/nvme3n1p2",
+    "/dev/sda1",       "/dev/sda2",       "/dev/sdb1",       "/dev/sdb2",
+    "/dev/sdc1",       "/dev/sdc2",       "/dev/sdd1",       "/dev/sdd2",
+    "/dev/mmcblk0p1",  "/dev/mmcblk0p2",  "/dev/mmcblk1p1",  "/dev/mmcblk1p2",
+};
+
+/// init이 설정 디스크를 찾으며 훑는 순서. 디스크 전체가 먼저다 — 게이트의
+/// 열두 체인은 전부 파티션 없는 ext2라 그 순서에서 먼저 잡히고, 판정이
+/// 한 줄도 안 바뀐다(DI design 결정 6).
+pub const CANDIDATES = DISKS ++ PARTITIONS;
+
+/// 파티션 노드의 이름. 이름이 숫자로 끝나는 디스크(nvme0n1 · mmcblk0)는
+/// 사이에 `p`가 든다 — 커널의 block/partitions/core.c가 정하는 규칙이다.
+/// 순수 함수라 storage_test가 PARTITIONS와 어긋나지 않는지 본다.
+pub fn partitionName(buf: []u8, disk: []const u8, n: u8) ?[:0]const u8 {
+    if (disk.len == 0) return null;
+    const sep: []const u8 = if (std.ascii.isDigit(disk[disk.len - 1])) "p" else "";
+    return std.fmt.bufPrintZ(buf, "{s}{s}{d}", .{ disk, sep, n }) catch null;
+}
+
 /// 고른 디스크. 라벨을 슬라이스가 아니라 복사로 들고 있다 — 슬라이스로
 /// 돌려주면 읽기 버퍼가 스택에서 사라진 뒤를 가리킨다. devices.Path가 경로에
 /// 대해 이미 쓰는 처방이다.
@@ -82,13 +114,14 @@
     }
 };
 
-/// head는 디스크 앞 HEAD_BYTES. 라벨이 LABEL_PREFIX로 시작하면 그 라벨을,
-/// 아니면 null. 돌려주는 슬라이스는 head 안을 가리킨다.
+/// head가 ext2/3/4 superblock을 담고 있으면 그 라벨을, 아니면 null.
+/// 라벨이 비어 있으면 null이 아니라 빈 슬라이스다 — "ext2인데 이름이 없다"와
+/// "ext2가 아니다"를 tars-install의 목록이 가른다(DI-M1).
 ///
 /// 순수 함수인 것에 뜻이 있다 — 시스템 콜이 없으므로 호스트 검사가 규칙을
 /// 그대로 본다. devices.zig가 bitSet/looksLikeKeyboard(순수)와 findKeyboard
 /// (콜)를 가른 것과 같은 선이다.
-pub fn tarsLabel(head: []const u8) ?[]const u8 {
+pub fn ext2Label(head: []const u8) ?[]const u8 {
     // 라벨의 끝이 매직보다 뒤라서 이 하나로 둘을 다 덮는다. 짧은 읽기(장치가
     // HEAD_BYTES보다 작은 경우)에서 죽지 않는 자리다.
     if (head.len < SB_OFFSET + LABEL_OFF + LABEL_LEN) return null;
@@ -105,14 +138,19 @@
     // 라벨은 NUL로 끝나지만 16바이트를 꽉 채우면 NUL이 없다. 그때는 전부가
     // 라벨이다.
     const end = std.mem.indexOfScalar(u8, raw, 0) orelse LABEL_LEN;
-    const name = raw[0..end];
+    return raw[0..end];
+}
 
+/// head는 디스크 앞 HEAD_BYTES. 라벨이 LABEL_PREFIX로 시작하면 그 라벨을,
+/// 아니면 null. 돌려주는 슬라이스는 head 안을 가리킨다.
+pub fn tarsLabel(head: []const u8) ?[]const u8 {
+    const name = ext2Label(head) orelse return null;
     if (!std.mem.startsWith(u8, name, LABEL_PREFIX)) return null;
     return name;
 }
 
 /// 장치 앞머리를 buf에 읽는다. 없는 장치는 ENOENT이고 그것이 정상 경로다 —
-/// 후보 열넷 중 이 기계에 있는 것은 보통 하나다.
+/// 후보 마흔둘 중 이 기계에 있는 것은 보통 한둘이다.
 ///
 /// O_NONBLOCK으로 여는 이유가 devices.zig의 버튼 fd와 다르다. 여기서는
 /// 매체가 없는 광학 드라이브나 빈 카드 리더에서 open(2)이 매달리는 것을
@@ -121,7 +159,7 @@
 ///
 /// read(2)가 요청한 만큼을 다 준다는 보장이 없으므로 "돌아온 만큼 더한다".
 /// devices.readFile과 같은 루프다.
-fn readHead(path: [:0]const u8, buf: []u8) ?[]const u8 {
+pub fn readHead(path: [:0]const u8, buf: []u8) ?[]const u8 {
     const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY, .NONBLOCK = true }, 0);
     if (failed(rc)) |_| return null;
     const fd: i32 = @intCast(rc);
@@ -142,8 +180,8 @@
 
 /// `tars-` 라벨을 가진 첫 후보를 out에 채우고 true. 하나도 없으면 false.
 ///
-/// 마운트로 시험하지 않는다(design 결정 11). 열넷을 mount로 두드리면 실패
-/// 줄이 열셋 찍히고, mount(2)는 파일시스템을 ext3/4로 잘못 잡았을 때 저널
+/// 마운트로 시험하지 않는다(design 결정 11). 마흔둘을 mount로 두드리면 실패
+/// 줄이 마흔하나 찍히고, mount(2)는 파일시스템을 ext3/4로 잘못 잡았을 때 저널
 /// 재생 같은 쓰기를 할 수 있다. 읽어서 거르면 남의 디스크를 건드릴
 /// 가능성이 0이다.
 pub fn findConfigDisk(out: *Found) bool {
```

- [ ] Step 4: `main.zig`의 주석 셋을 고친다

코드는 한 글자도 안 바뀐다. `mountConfig`의 로그 줄(`no disk labelled … among
{d} candidates`)은 `CANDIDATES.len`을 찍으므로 42가 된다 — 이 수를 grep하는
체인은 없다(`rg candidates --glob '*.sh'`가 빈 출력).

```diff
--- a/init/src/main.zig
+++ b/init/src/main.zig
@@ -104,14 +104,16 @@
 }
 
 /// 설정 저장소를 붙인다. initramfs는 tmpfs라 전원이 꺼지면 통째로 사라진다 —
-/// 재부팅을 넘어 살아남는 것은 이 디스크 하나뿐이다. 파티션 테이블 없이
-/// 디스크 전체가 ext2라서 /dev/nvme0n1p1이 아니라 /dev/nvme0n1이다.
+/// 재부팅을 넘어 살아남는 것은 이 디스크 하나뿐이다. 게이트의 디스크는
+/// 파티션 테이블 없이 디스크 전체가 ext2라서 /dev/nvme0n1이고, tars-install이
+/// 설치한 기계에서는 GPT의 둘째 파티션이라 /dev/nvme0n1p2다(DI-M1).
 ///
 /// RM-M2까지는 /dev/vda가 여기 박혀 있었다. 그 이름은 virtio-blk에만
 /// 있어서 노트북에서는 저장소를 영영 못 찾았다 — 부팅은 됐고 설정만 매번
-/// 사라졌다. 이제 storage.zig가 후보 열넷을 훑어 ext2 라벨이 `tars-`로
-/// 시작하는 첫 디스크를 고른다. 이름이 아니라 디스크 안의 표식으로 고르는
-/// 것이라, virtio든 NVMe든 SATA든 같은 코드가 지난다.
+/// 사라졌다. 이제 storage.zig가 후보 마흔둘(디스크 열넷, 그 다음 각각의 첫
+/// 두 파티션)을 훑어 ext2 라벨이 `tars-`로 시작하는 첫 것을 고른다. 이름이
+/// 아니라 디스크 안의 표식으로 고르는 것이라, virtio든 NVMe든 SATA든 같은
+/// 코드가 지난다.
 ///
 /// MS_SYNCHRONOUS로 붙이는 이유가 이 서브프로젝트의 핵심이다. 보통 파일에
 /// 쓴 내용은 page cache에만 올라가고 커널이 알아서 나중에 디스크로 내려보낸다.
@@ -120,7 +122,7 @@
 /// 있다. 설정 파일은 어쩌다 한 번 쓰는 것이라 성능 대가가 사실상 없다.
 ///
 /// 디스크가 없는 부팅도 정상 경로다 — BF 체인은 ISO 부팅이라 -drive가 없다.
-/// 그때는 후보 열넷이 전부 ENOENT로 열리지 않아 로그 한 줄만 남으며, 부팅은
+/// 그때는 후보 마흔둘이 전부 ENOENT로 열리지 않아 로그 한 줄만 남으며, 부팅은
 /// 계속된다.
 fn mountConfig() bool {
     var found: storage.Found = .{};
```

- [ ] Step 5: 검사가 통과하는지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init && zig build && zig build test' 2>&1 | tail -8
```

기대: `storage_test: only a tars- labelled ext2 superblock counts (42 candidates)`,
`error` 없음.

- [ ] Step 6: diff를 세고 지운 줄을 읽는다

```bash
git diff --stat
git diff init/src/storage.zig init/src/main.zig | grep '^-' | grep -v '^---'
```

기대: 지운 줄은 옛 `CANDIDATES` 블록과 그 주석 · `tarsLabel`의 몸통(`ext2Label`로
옮겨졌다) · `fn readHead`(→ `pub fn`) · "열넷"이 든 주석 줄뿐이다.

- [ ] Step 7: 커밋

```bash
git add init/src/storage.zig init/src/storage_test.zig init/src/main.zig
git commit -m "Let init find its config on the first two partitions of each disk"
```

## Task 2 — `disk.zig`: 설치기의 순수한 쪽

Files: Create `init/src/disk.zig` · `init/src/disk_test.zig`; Modify `init/build.zig`

- [ ] Step 1: 검사를 쓴다 — `init/src/disk_test.zig`

```zig
const std = @import("std");
const disk = @import("disk.zig");

/// tars-install의 순수한 쪽을 본다. storage_test와 같은 모양이다 — 호스트
/// 아키텍처로 컨테이너가 직접 돌리고, 실패하면 무엇이 틀렸는지 한 줄 찍고
/// 에러로 끝난다.
///
/// 서명 오프셋(ISO 32769 · GPT 512 · MBR 510)은 이 파일과 disk.zig가 같은 수를
/// 두 번 적은 것이라 여기서는 원리적으로 못 잡는다. 그것을 보는 것은 install
/// 체인이다 — 부팅 1의 목록 머리 줄이 진짜 ISO를 `iso9660 TARS`로 읽어야 한다.
var head: [disk.HEAD_BYTES]u8 = undefined;

fn clear() []u8 {
    @memset(&head, 0);
    return &head;
}

fn expectKind(got: disk.Seen, want: disk.Kind, label: []const u8, what: []const u8) !void {
    if (got.kind != want or !std.mem.eql(u8, got.label, label)) {
        std.debug.print("FAIL: {s}: want {s} '{s}', got {s} '{s}'\n", .{
            what, @tagName(want), label, @tagName(got.kind), got.label,
        });
        return error.WrongKind;
    }
}

fn expectText(got: []const u8, want: []const u8, what: []const u8) !void {
    if (!std.mem.eql(u8, got, want)) {
        std.debug.print("FAIL: {s}: want '{s}', got '{s}'\n", .{ what, want, got });
        return error.WrongText;
    }
}

pub fn main() !void {
    var buf: [64]u8 = undefined;

    // ── 1. describe — 넷의 서명과 빈 디스크 ─────────────────────────
    try expectKind(disk.describe(clear()), .blank, "", "all zero");

    {
        const h = clear();
        h[32768] = 1;
        @memcpy(h[32769..][0..5], "CD001");
        @memset(h[32768 + 40 ..][0..32], ' ');
        @memcpy(h[32768 + 40 ..][0..4], "TARS");
        // 하이브리드 ISO는 MBR 서명도 있다. 그래도 iso9660으로 읽어야 한다 —
        // 이것이 없으면 USB 스틱의 ISO가 목록에 "mbr"로 보인다.
        h[510] = 0x55;
        h[511] = 0xAA;
        try expectKind(disk.describe(h), .iso9660, "TARS", "hybrid iso");
    }
    {
        const h = clear();
        h[1024 + 56] = 0x53;
        h[1024 + 57] = 0xEF;
        @memcpy(h[1024 + 120 ..][0..11], "debian-root");
        try expectKind(disk.describe(h), .ext2, "debian-root", "whole-disk ext2");
    }
    {
        const h = clear();
        h[510] = 0x55;
        h[511] = 0xAA;
        @memcpy(h[512..][0..8], "EFI PART");
        try expectKind(disk.describe(h), .gpt, "", "gpt with protective mbr");
    }
    {
        const h = clear();
        h[510] = 0x55;
        h[511] = 0xAA;
        try expectKind(disk.describe(h), .mbr, "", "plain mbr");
    }
    {
        const h = clear();
        h[4000] = 0x01;
        try expectKind(disk.describe(h), .unknown, "", "one stray byte");
    }
    // 짧은 읽기. 매체가 HEAD_BYTES보다 작아도 죽지 않는다.
    try expectKind(disk.describe(clear()[0..600]), .blank, "", "short read");

    // ── 2. stateText ────────────────────────────────────────────────
    try expectText(disk.stateText(&buf, .{ .kind = .blank }), "blank", "blank state");
    try expectText(disk.stateText(&buf, .{ .kind = .gpt }), "foreign (gpt)", "gpt state");
    try expectText(disk.stateText(&buf, .{ .kind = .ext2, .label = "tars-config" }), "foreign (ext2 tars-config)", "ext2 state");
    try expectText(disk.stateText(&buf, .{ .kind = .ext2, .label = "" }), "foreign (ext2)", "unlabelled ext2 state");
    try expectText(disk.stateText(&buf, .{ .kind = .unknown }), "foreign (unknown data)", "unknown state");

    // ── 3. formatSize — 10진이다 ────────────────────────────────────
    try expectText(disk.formatSize(&buf, 2 * 1024 * 1024 * 1024), "2 GB", "2 GiB disk");
    try expectText(disk.formatSize(&buf, 512_110_190_592), "512 GB", "512 GB ssd");
    try expectText(disk.formatSize(&buf, 50_640_896), "50 MB", "the iso");
    try expectText(disk.formatSize(&buf, 0), "0 B", "empty");

    // ── 4. parseArgs ────────────────────────────────────────────────
    {
        const none = [_][*:0]const u8{};
        if (disk.parseArgs(&none) != .list) return error.NoArgsNotList;

        const one = [_][*:0]const u8{"/dev/nvme0n1"};
        switch (disk.parseArgs(&one)) {
            .install => |i| if (!std.mem.eql(u8, i.disk, "/dev/nvme0n1") or i.yes) return error.OneArgWrong,
            else => return error.OneArgNotInstall,
        }

        const two = [_][*:0]const u8{ "/dev/nvme0n1", "--yes" };
        switch (disk.parseArgs(&two)) {
            .install => |i| if (!i.yes) return error.YesIgnored,
            else => return error.TwoArgsNotInstall,
        }

        // 디스크를 빠뜨리고 --yes만 친 경우. "--yes라는 디스크"로 가면 안 된다.
        const flag_only = [_][*:0]const u8{"--yes"};
        if (disk.parseArgs(&flag_only) != .usage) return error.FlagTakenAsDisk;

        const swapped = [_][*:0]const u8{ "--yes", "/dev/nvme0n1" };
        if (disk.parseArgs(&swapped) != .usage) return error.SwappedAccepted;

        const typo = [_][*:0]const u8{ "/dev/nvme0n1", "--yse" };
        if (disk.parseArgs(&typo) != .usage) return error.TypoAccepted;

        const three = [_][*:0]const u8{ "/dev/nvme0n1", "--yes", "x" };
        if (disk.parseArgs(&three) != .usage) return error.ThreeAccepted;
    }

    // ── 5. knownDisk — 파티션과 부팅 매체는 대상이 아니다 ─────────────
    if (disk.knownDisk("/dev/nvme0n1") == null) return error.NvmeUnknown;
    if (disk.knownDisk("/dev/sda") == null) return error.SdaUnknown;
    if (disk.knownDisk("/dev/nvme0n1p1") != null) return error.PartitionAccepted;
    if (disk.knownDisk("/dev/sr0") != null) return error.CdromAccepted;
    if (disk.knownDisk("nvme0n1") != null) return error.BareNameAccepted;

    try expectText(disk.sysName("/dev/nvme0n1"), "nvme0n1", "sysName");

    // ── 6. confirmed — 대문자 YES만 ─────────────────────────────────
    if (!disk.confirmed("YES\n")) return error.YesRefused;
    if (!disk.confirmed("YES\r\n")) return error.YesCrLfRefused;
    if (disk.confirmed("yes\n")) return error.LowerYesAccepted;
    if (disk.confirmed("y\n")) return error.YAccepted;
    if (disk.confirmed("\n")) return error.EmptyAccepted;
    if (disk.confirmed("YES please\n")) return error.YesPrefixAccepted;

    std.debug.print("disk_test: signatures, sizes, arguments and the YES gate hold\n", .{});
}
```

- [ ] Step 2: `build.zig`에 검사를 건다

`sntp_test` 블록 뒤, `// installArtifact를 부르지 않는다.` 주석 바로 위에 넣고
`test_step`에 한 줄 더한다.

```zig
    // DI-M1: 설치기의 순수한 쪽(디스크 앞머리 판정 · 크기 · 인자 · YES).
    // storage_test와 같은 이유로 host_target이다.
    const disk_test_mod = b.createModule(.{
        .root_source_file = b.path("src/disk_test.zig"),
        .target = host_target,
        .optimize = optimize,
        .single_threaded = true,
    });
    const disk_test = b.addExecutable(.{
        .name = "disk_test",
        .root_module = disk_test_mod,
    });
```

```zig
    test_step.dependOn(&b.addRunArtifact(disk_test).step);
```

- [ ] Step 3: 실패하는지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build test' 2>&1 | grep -E "error" | head -3
```

기대: `unable to load 'src/disk.zig'`(또는 `FileNotFound`).

- [ ] Step 4: `init/src/disk.zig`를 만든다

```zig
const std = @import("std");
const storage = @import("storage.zig");

/// tars-install이 시스템 콜 없이 정하는 것들. 디스크 앞머리를 읽고 무엇이
/// 보이는지 말하는 것 · 크기를 사람이 읽는 수로 바꾸는 것 · 인자를 읽는 것.
///
/// install.zig와 가른 이유는 storage.zig가 tarsLabel과 findConfigDisk를 가른
/// 것과 같다 — 순수한 쪽은 disk_test가 호스트에서 0.1초에 본다. 시스템 콜을
/// 하는 쪽은 install 체인이 OVMF 부팅으로 본다.

/// 앞머리를 이만큼 읽는다. ISO9660의 primary volume descriptor가 오프셋
/// 32768(섹터 16)에서 시작하고 2048바이트다. ext2 superblock(1024~2047)과
/// GPT 헤더(512)와 MBR 서명(510)은 전부 그 앞에 든다.
pub const HEAD_BYTES: usize = 32768 + 2048;

const ISO_PVD: usize = 32768;
const ISO_ID_LEN: usize = 32; // volume identifier, 오프셋 40, 공백으로 채운다
const GPT_SIG_OFF: usize = 512;

pub const Kind = enum { blank, iso9660, ext2, gpt, mbr, unknown };

/// 디스크에서 보이는 것. label은 head 안을 가리킨다 — ISO면 볼륨 ID, ext2면
/// 라벨, 나머지는 빈 문자열이다.
pub const Seen = struct {
    kind: Kind,
    label: []const u8 = "",
};

/// 앞머리에 무엇이 보이는가. 순서가 뜻이 있다.
///
///   iso9660이 첫째다. 하이브리드 ISO는 MBR 서명도 갖고 있어서(make_iso.sh의
///   --protective-msdos-label) MBR을 먼저 보면 USB 스틱의 ISO가 "mbr"로 읽힌다.
///   ext2가 GPT보다 먼저다. 둘은 겹치지 않지만(GPT 디스크의 1080은 첫 파티션
///   항목의 이름 자리다) 파티션 없는 ext2가 게이트 디스크의 모양이라 먼저 둔다.
///   blank는 끝에서 둘째다. 다 0이면 어떤 서명도 안 맞았다는 뜻이다.
pub fn describe(head: []const u8) Seen {
    if (head.len >= ISO_PVD + 40 + ISO_ID_LEN and head[ISO_PVD] == 1 and
        std.mem.eql(u8, head[ISO_PVD + 1 ..][0..5], "CD001"))
    {
        const id = head[ISO_PVD + 40 ..][0..ISO_ID_LEN];
        return .{ .kind = .iso9660, .label = std.mem.trimEnd(u8, id, " ") };
    }
    if (storage.ext2Label(head)) |label| return .{ .kind = .ext2, .label = label };
    if (head.len >= GPT_SIG_OFF + 8 and std.mem.eql(u8, head[GPT_SIG_OFF..][0..8], "EFI PART")) {
        return .{ .kind = .gpt };
    }
    if (head.len >= 512 and head[510] == 0x55 and head[511] == 0xAA) return .{ .kind = .mbr };
    for (head) |b| {
        if (b != 0) return .{ .kind = .unknown };
    }
    return .{ .kind = .blank };
}

/// 목록의 상태 칸. 지울 내용을 한 단어라도 보여 주는 것이 "알고 설치한다"의
/// 최소다(DI design 결정 7).
pub fn stateText(buf: []u8, seen: Seen) []const u8 {
    const what: []const u8 = switch (seen.kind) {
        .blank => return "blank",
        .iso9660 => "iso9660",
        .ext2 => "ext2",
        .gpt => "gpt",
        .mbr => "mbr",
        .unknown => "unknown data",
    };
    if (seen.label.len == 0) {
        return std.fmt.bufPrint(buf, "foreign ({s})", .{what}) catch "foreign";
    }
    return std.fmt.bufPrint(buf, "foreign ({s} {s})", .{ what, seen.label }) catch "foreign";
}

/// 바이트를 목록에 찍을 수로. 디스크 제조사처럼 10진이다 — 512 GB라고 팔린
/// SSD가 목록에서 476이면 사람이 다른 디스크로 읽는다.
pub fn formatSize(buf: []u8, bytes: u64) []const u8 {
    const gb: u64 = 1_000_000_000;
    const mb: u64 = 1_000_000;
    if (bytes >= gb) return std.fmt.bufPrint(buf, "{d} GB", .{bytes / gb}) catch "?";
    if (bytes >= mb) return std.fmt.bufPrint(buf, "{d} MB", .{bytes / mb}) catch "?";
    return std.fmt.bufPrint(buf, "{d} B", .{bytes}) catch "?";
}

pub const Command = union(enum) {
    /// 인자 없음. 목록만 찍는다.
    list,
    /// `<disk>` 또는 `<disk> --yes`.
    install: struct { disk: [:0]const u8, yes: bool },
    /// 그 밖의 전부. 쓰는 법을 찍고 2로 끝난다.
    usage,
};

/// argv[1..]을 읽는다. `--yes`는 디스크 뒤에만 온다 — 순서를 하나로 박아 두면
/// `tars-install --yes`(디스크를 빠뜨림)가 "--yes라는 디스크"가 아니라 쓰는
/// 법으로 떨어진다.
pub fn parseArgs(args: []const [*:0]const u8) Command {
    switch (args.len) {
        0 => return .list,
        1 => {
            const disk = std.mem.span(args[0]);
            if (std.mem.startsWith(u8, disk, "-")) return .usage;
            return .{ .install = .{ .disk = disk, .yes = false } };
        },
        2 => {
            const disk = std.mem.span(args[0]);
            if (std.mem.startsWith(u8, disk, "-")) return .usage;
            if (!std.mem.eql(u8, std.mem.span(args[1]), "--yes")) return .usage;
            return .{ .install = .{ .disk = disk, .yes = true } };
        },
        else => return .usage,
    }
}

/// 사용자가 친 이름이 storage.DISKS의 것이면 그 원소를(수명이 무한한
/// 리터럴이다), 아니면 null. 파티션(`/dev/nvme0n1p1`)과 오타가 여기서 걸린다.
pub fn knownDisk(path: []const u8) ?[:0]const u8 {
    for (storage.DISKS) |d| {
        if (std.mem.eql(u8, d, path)) return d;
    }
    return null;
}

/// `/dev/nvme0n1` → `nvme0n1`. /sys/block/<이름>을 짓는 데 쓴다.
pub fn sysName(path: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse return path;
    return path[slash + 1 ..];
}

/// 확인 줄이 정확히 YES인가. 줄 끝의 개행과 공백만 벗긴다 — `yes`나 `y`는
/// 아니다. 디스크를 통째로 지우는 질문이라 대문자 세 글자를 요구한다.
pub fn confirmed(line: []const u8) bool {
    return std.mem.eql(u8, std.mem.trim(u8, line, " \t\r\n"), "YES");
}

/// sfdisk에 stdin으로 넘기는 배치(DI design 결정 2 · 3). DI-M0 실측 8이 이
/// 세 줄을 그대로 먹였다.
pub const SFDISK_SCRIPT =
    \\label: gpt
    \\size=256MiB, type=uefi, name=TARS-BOOT
    \\size=1GiB, type=linux, name=TARS-CONFIG
    \\
;

pub const ESP_LABEL: [:0]const u8 = "TARS-BOOT";
pub const CONFIG_LABEL: [:0]const u8 = "tars-config";

/// 부팅 매체에서 ESP로 가는 넷(DI design 확인 1). 경로가 양쪽에서 같다.
pub const BOOT_FILES = [_][:0]const u8{
    "boot/bzImage",
    "boot/initrd.cpio",
    "boot/limine/limine.conf",
    "EFI/BOOT/BOOTX64.EFI",
};

/// BOOT_FILES를 놓기 전에 ESP에 만들 디렉터리. 부모가 먼저다.
pub const ESP_DIRS = [_][:0]const u8{ "boot", "boot/limine", "EFI", "EFI/BOOT" };

/// 매체라고 판정하는 파일(DI design 결정 4). 이름이 아니라 쓰임으로 본다.
pub const MEDIUM_MARK: [:0]const u8 = "boot/limine/limine.conf";
```

- [ ] Step 5: 통과하는지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build test' 2>&1 | grep -E "disk_test|storage_test|error"
```

기대: `disk_test: signatures, sizes, arguments and the YES gate hold`와
`storage_test: … (42 candidates)`, `error` 없음.

- [ ] Step 6: 반사실 하나 — 순서 검사가 진짜인가

`describe`에서 iso9660 검사와 mbr 검사의 순서를 바꾸면 `hybrid iso` 검사가
빨개져야 한다. 컨테이너 안의 사본으로 한다(저장소는 안 건드린다).

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cp -r init /tmp/i && cd /tmp/i && rm -rf .zig-cache zig-out &&
  perl -0pi -e "s/(    if \(head.len >= ISO_PVD.*?\n    \}\n)(.*?)(    if \(head.len >= 512 and head\[510\].*?\n)/\$3\$2\$1/s" src/disk.zig &&
  zig build test' 2>&1 | grep -E "FAIL|disk_test"
```

기대: `FAIL: hybrid iso: want iso9660 'TARS', got mbr ''`. 초록이 나오면 perl이
안 먹은 것이다 — `grep -n "head\[510\]" /tmp/i/src/disk.zig`로 순서를 보고 다시 한다.

- [ ] Step 7: 커밋

```bash
git diff --stat
git add init/src/disk.zig init/src/disk_test.zig init/build.zig
git commit -m "Teach the installer to read what a disk already holds"
```

## Task 3 — `install.zig`와 `tars-install` 실행 파일

Files: Create `init/src/install.zig`; Modify `init/build.zig`

이 Task에는 호스트 검사가 없다. 시스템 콜을 하는 쪽이고, 판정은 Task 5의
체인이다. 여기서는 빌드가 되고 바이너리가 정적인지까지 본다.

- [ ] Step 1: `build.zig`에 exe를 건다

`b.installArtifact(exe);` 바로 뒤에 넣는다.

```zig
    // DI-M1: 설치기. init과 같은 타깃·같은 모드이고 libc를 안 쓴다 — 게스트에
    // mount 명령이 없어서 시스템 콜로 붙이는 것까지 init과 같다(DI design
    // 결정 5). 별도 exe인 이유는 부팅 경로에 안 들어가야 해서다.
    // make_initrd.sh가 zig-out/bin/tars-install을 usr/bin에 싣는다.
    const install_mod = b.createModule(.{
        .root_source_file = b.path("src/install.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .single_threaded = true,
    });
    const install_exe = b.addExecutable(.{
        .name = "tars-install",
        .root_module = install_mod,
    });
    b.installArtifact(install_exe);
```

- [ ] Step 2: `init/src/install.zig`를 만든다

```zig
const std = @import("std");
const linux = std.os.linux;
const storage = @import("storage.zig");
const disk = @import("disk.zig");

/// tars-install — 부팅 매체의 부트 파일 넷을 내장 디스크에 옮겨 USB 없이
/// 뜨게 한다(DI design). 인자 없이 치면 목록, 디스크를 주면 계획을 보이고
/// YES를 받는다. `--yes`가 그 질문을 건너뛴다.
///
/// init 옆의 별도 실행 파일인 이유는 DI design 결정 5다 — 부팅 경로에 안
/// 들어가야 게이트의 열두 체인에 닿지 않고, storage.zig를 같이 써야 목록에
/// 보이는 이름과 부팅 때 찾는 이름이 같은 코드에서 나온다.
///
/// init처럼 libc 없이 시스템 콜만 쓴다. 게스트에 `mount` 명령이 없어서다
/// (design 확인 6). 파티션과 포맷만 외부 도구 셋에 맡긴다(결정 3).

/// main.zig·storage.zig에도 같은 함수가 있다. 세 줄짜리 헬퍼 하나 때문에
/// 공용 모듈을 만들지 않는다는 devices.zig의 규칙 그대로다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

// ── 출력 ─────────────────────────────────────────────────────────────

fn writeAll(fd: i32, bytes: []const u8) void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = linux.write(fd, bytes[off..].ptr, bytes.len - off);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            return;
        }
        off += n;
    }
}

/// 사람이 읽는 줄은 stdout으로. 게이트는 시리얼에서 이것을 읽는다.
fn say(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, fmt, args) catch return;
    writeAll(1, text);
}

/// 실패는 stderr로. 한 줄에 무엇이 몇으로 죽었는지가 다 있어야 한다
/// (design 결정 5).
fn complain(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "tars-install: " ++ fmt ++ "\n", args) catch return;
    writeAll(2, text);
}

// ── 작은 파일 읽기 ───────────────────────────────────────────────────

/// devices.readFile과 같은 루프다. sysfs 속성은 전부 한 페이지 안이다.
fn readFile(path: [*:0]const u8, buf: []u8) ?[]const u8 {
    const rc = linux.open(path, .{ .ACCMODE = .RDONLY }, 0);
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
        if (n == 0) break;
        len += n;
    }
    return buf[0..len];
}

/// /sys/block/<이름>/<속성>의 내용을 앞뒤 공백 없이. 없으면 null.
fn sysAttr(name: []const u8, attr: []const u8, buf: []u8) ?[]const u8 {
    var path: [128]u8 = undefined;
    const p = std.fmt.bufPrintZ(&path, "/sys/block/{s}/{s}", .{ name, attr }) catch return null;
    const text = readFile(p.ptr, buf) orelse return null;
    return std.mem.trim(u8, text, " \t\r\n");
}

/// 바이트 크기. /sys/block/<이름>/size는 장치의 논리 섹터 크기와 무관하게
/// 늘 512바이트 단위다(커널 문서 Documentation/ABI/stable/sysfs-block).
fn sizeBytes(name: []const u8) ?u64 {
    var buf: [32]u8 = undefined;
    const text = sysAttr(name, "size", &buf) orelse return null;
    const sectors = std.fmt.parseInt(u64, text, 10) catch return null;
    return sectors * 512;
}

fn exists(path: [*:0]const u8) bool {
    return failed(linux.access(path, linux.F_OK)) == null;
}

// ── 부팅 매체 ────────────────────────────────────────────────────────

const WORK_DIR: [:0]const u8 = "/tmp/tars-install";
const MEDIUM_DIR: [:0]const u8 = "/tmp/tars-install/medium";
const ESP_DIR: [:0]const u8 = "/tmp/tars-install/esp";

/// 매체일 수 있는 것. 광학 드라이브 둘(QEMU의 -cdrom · 실기의 외장 드라이브)과
/// 디스크 전부(dd로 ISO를 쓴 USB 스틱은 /dev/sdX다). 광학 드라이브는 init의
/// 설정 디스크 후보에는 없다 — ISO는 ext2가 아니다(design 결정 4).
const MEDIUM_CANDIDATES = [_][:0]const u8{ "/dev/sr0", "/dev/sr1" } ++ storage.DISKS;

fn mkdirOk(path: [*:0]const u8) bool {
    const rc = linux.mkdir(path, 0o755);
    if (failed(rc)) |e| return e == .EXIST;
    return true;
}

/// 앞머리가 ISO9660이고, 붙여 보니 limine.conf가 있는 첫 후보. 찾으면
/// MEDIUM_DIR에 붙인 채로 돌려준다.
///
/// 앞머리를 먼저 읽는 이유는 RM design 결정 11과 같다 — 열여섯을 mount로
/// 두드리지 않는다. 매체가 없는 광학 드라이브는 읽기가 실패해서 여기서
/// 빠진다. 노드가 있다는 것으로 아무것도 결론짓지 않는다(DI-M0 실측 9 —
/// QEMU는 -cdrom이 없어도 빈 sr0을 붙인다).
fn findMedium() ?[:0]const u8 {
    if (!mkdirOk(WORK_DIR.ptr) or !mkdirOk(MEDIUM_DIR.ptr)) {
        complain("cannot create {s}", .{MEDIUM_DIR});
        return null;
    }
    var mark_buf: [128]u8 = undefined;
    const mark = std.fmt.bufPrintZ(&mark_buf, "{s}/{s}", .{ MEDIUM_DIR, disk.MEDIUM_MARK }) catch unreachable;

    for (MEDIUM_CANDIDATES) |path| {
        var buf: [disk.HEAD_BYTES]u8 = undefined;
        const head = storage.readHead(path, &buf) orelse continue;
        if (disk.describe(head).kind != .iso9660) continue;

        const rc = linux.mount(path.ptr, MEDIUM_DIR.ptr, "iso9660", linux.MS.RDONLY, 0);
        if (failed(rc)) |_| continue;
        if (exists(mark.ptr)) return path;
        _ = linux.umount(MEDIUM_DIR.ptr);
    }
    return null;
}

// ── 목록 ─────────────────────────────────────────────────────────────

fn printUsage() void {
    say("tars-install <disk>        install onto <disk>; everything on it is erased\n", .{});
    say("tars-install <disk> --yes  same, without asking\n", .{});
}

/// 한 디스크의 상태 칸. 매체면 그 이름, 아니면 앞머리에 보이는 것.
fn stateOf(path: [:0]const u8, medium: ?[:0]const u8, buf: []u8) []const u8 {
    if (medium) |m| {
        if (std.mem.eql(u8, m, path)) return "boot medium";
    }
    var head_buf: [disk.HEAD_BYTES]u8 = undefined;
    const head = storage.readHead(path, &head_buf) orelse return "unreadable";
    return disk.stateText(buf, disk.describe(head));
}

fn list(medium: ?[:0]const u8) void {
    if (medium) |m| {
        var head_buf: [disk.HEAD_BYTES]u8 = undefined;
        const head = storage.readHead(m, &head_buf) orelse &[_]u8{};
        const seen = disk.describe(head);
        var size_buf: [16]u8 = undefined;
        const size = disk.formatSize(&size_buf, sizeBytes(disk.sysName(m)) orelse 0);
        say("tars-install: boot medium {s} (iso9660 {s}, {s})\n", .{ m, seen.label, size });
    } else {
        say("tars-install: no boot medium found; boot from the TARS ISO or USB stick to install\n", .{});
    }
    say("\n", .{});

    var shown: usize = 0;
    for (storage.DISKS) |path| {
        const name = disk.sysName(path);
        const bytes = sizeBytes(name) orelse continue;
        shown += 1;

        var size_buf: [16]u8 = undefined;
        var model_buf: [64]u8 = undefined;
        var rem_buf: [8]u8 = undefined;
        var state_buf: [64]u8 = undefined;
        const model = sysAttr(name, "device/model", &model_buf) orelse "-";
        const removable = sysAttr(name, "removable", &rem_buf) orelse "0";
        say("  {s:<14} {s:>7}  {s:<22} {s:<9}  {s}\n", .{
            path,
            disk.formatSize(&size_buf, bytes),
            model,
            if (std.mem.eql(u8, removable, "1")) "removable" else "internal",
            stateOf(path, medium, &state_buf),
        });
    }
    if (shown == 0) say("  (no disks)\n", .{});
    say("\n", .{});
    printUsage();
}

// ── 외부 도구 ────────────────────────────────────────────────────────

/// argv[0]을 fork+execve로 돌리고 끝나기를 기다린다. 0으로 끝나면 true.
///
/// 도구의 stdout·stderr는 로그 파일로 보내고, 실패했을 때만 그것을 보여
/// 준다. 성공한 도구의 말은 사람에게 소음이다 — mkfs.vfat은 성공해도 iconv
/// 경고 세 줄을 찍는다(DI-M0 실측 8).
///
/// stdin은 input이 있으면 파이프로, 없으면 /dev/null로 준다. 도구가
/// 무엇을 묻더라도 매달리지 않게 한다 — mke2fs는 옛 파일시스템을 보면
/// tty에서 "Proceed anyway?"를 묻는다.
fn runTool(
    argv: [*:null]const ?[*:0]const u8,
    input: ?[]const u8,
    log: [:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
) bool {
    const tool = std.mem.span(argv[0].?);
    var fds: [2]i32 = .{ -1, -1 };
    if (input != null) {
        if (failed(linux.pipe(&fds))) |e| {
            complain("pipe for {s} failed (errno {d})", .{ tool, @intFromEnum(e) });
            return false;
        }
    }

    const pid = linux.fork();
    if (failed(pid)) |e| {
        complain("fork for {s} failed (errno {d})", .{ tool, @intFromEnum(e) });
        return false;
    }
    if (pid == 0) {
        if (input != null) {
            _ = linux.dup2(fds[0], 0);
            _ = linux.close(fds[0]);
            _ = linux.close(fds[1]);
        } else {
            const nul = linux.open("/dev/null", .{ .ACCMODE = .RDONLY }, 0);
            if (failed(nul) == null) _ = linux.dup2(@intCast(nul), 0);
        }
        const out = linux.open(log.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
        if (failed(out) == null) {
            _ = linux.dup2(@intCast(out), 1);
            _ = linux.dup2(@intCast(out), 2);
        }
        _ = linux.execve(argv[0].?, argv, envp);
        linux.exit(127);
    }

    if (input) |text| {
        _ = linux.close(fds[0]);
        // 배치는 세 줄이라 파이프 버퍼(64KiB) 안에 든다. 자식이 읽기 전에
        // 다 써도 막히지 않는다.
        writeAll(fds[1], text);
        _ = linux.close(fds[1]);
    }

    var status: u32 = 0;
    while (true) {
        const rc = linux.wait4(@intCast(pid), &status, 0, null);
        if (failed(rc)) |e| {
            if (e == .INTR) continue;
            complain("waiting for {s} failed (errno {d})", .{ tool, @intFromEnum(e) });
            return false;
        }
        break;
    }
    if (linux.W.IFEXITED(status) and linux.W.EXITSTATUS(status) == 0) return true;

    if (linux.W.IFEXITED(status)) {
        complain("{s} failed (exit {d}); what it said:", .{ tool, linux.W.EXITSTATUS(status) });
    } else {
        complain("{s} was killed (signal {d}); what it said:", .{ tool, @intFromEnum(linux.W.TERMSIG(status)) });
    }
    var said: [4096]u8 = undefined;
    if (readFile(log.ptr, &said)) |text| writeAll(2, text);
    return false;
}

/// sfdisk가 돌아온 뒤 파티션 노드를 기다린다. 최대 3초, 100ms 간격 — HD-M2가
/// 키보드에 쓴 한정된 기다림이다(design 위험 2). DI-M0에서는 첫 확인에
/// 있었지만 실기의 답은 모른다.
fn waitForNode(path: [:0]const u8) bool {
    var i: usize = 0;
    while (i < 30) : (i += 1) {
        if (exists(path.ptr)) return true;
        const req: linux.timespec = .{ .sec = 0, .nsec = 100 * std.time.ns_per_ms };
        _ = linux.nanosleep(&req, null);
    }
    return exists(path.ptr);
}

// ── 복사 ─────────────────────────────────────────────────────────────

/// 파일 하나를 통째로. 돌려주는 것은 쓴 바이트 수다. 41MB initrd도 64KiB씩
/// 읽고 쓰면 된다 — 힙이 없고 필요도 없다.
fn copyFile(src: [:0]const u8, dst: [:0]const u8) ?u64 {
    const in_rc = linux.open(src.ptr, .{ .ACCMODE = .RDONLY }, 0);
    if (failed(in_rc)) |e| {
        complain("cannot open {s} (errno {d})", .{ src, @intFromEnum(e) });
        return null;
    }
    const in_fd: i32 = @intCast(in_rc);
    defer _ = linux.close(in_fd);

    const out_rc = linux.open(dst.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    if (failed(out_rc)) |e| {
        complain("cannot create {s} (errno {d})", .{ dst, @intFromEnum(e) });
        return null;
    }
    const out_fd: i32 = @intCast(out_rc);
    defer _ = linux.close(out_fd);

    var buf: [64 * 1024]u8 = undefined;
    var total: u64 = 0;
    while (true) {
        const n = linux.read(in_fd, &buf, buf.len);
        if (failed(n)) |e| {
            if (e == .INTR) continue;
            complain("reading {s} failed (errno {d})", .{ src, @intFromEnum(e) });
            return null;
        }
        if (n == 0) break;
        var off: usize = 0;
        while (off < n) {
            const w = linux.write(out_fd, buf[off..].ptr, n - off);
            if (failed(w)) |e| {
                if (e == .INTR) continue;
                complain("writing {s} failed (errno {d})", .{ dst, @intFromEnum(e) });
                return null;
            }
            off += w;
        }
        total += n;
    }
    return total;
}

// ── 설치 ─────────────────────────────────────────────────────────────

fn install(
    target: [:0]const u8,
    yes: bool,
    medium: ?[:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
) u8 {
    const path = disk.knownDisk(target) orelse {
        complain("{s} is not a disk tars-install knows; run tars-install alone for the list", .{target});
        return 2;
    };
    const name = disk.sysName(path);
    const bytes = sizeBytes(name) orelse {
        complain("{s} is not present on this machine", .{path});
        return 1;
    };
    const src = medium orelse {
        complain("no boot medium to copy from; boot from the TARS ISO or USB stick first", .{});
        return 1;
    };
    if (std.mem.eql(u8, src, path)) {
        complain("{s} is the boot medium; pick another disk", .{path});
        return 1;
    }

    // ── 계획 ──
    var size_buf: [16]u8 = undefined;
    var model_buf: [64]u8 = undefined;
    var state_buf: [64]u8 = undefined;
    const model = sysAttr(name, "device/model", &model_buf) orelse "-";
    say("tars-install: {s} ({s}, {s}) will be erased. it now holds: {s}\n", .{
        path, disk.formatSize(&size_buf, bytes), model, stateOf(path, medium, &state_buf),
    });
    say("  p1  256 MiB  EFI System  FAT32  TARS-BOOT   <- bzImage, initrd.cpio, limine\n", .{});
    say("  p2    1 GiB  Linux       ext2   tars-config <- your settings, empty at first\n", .{});
    say("  rest unallocated\n", .{});

    if (!yes) {
        say("type YES to continue: ", .{});
        var line: [64]u8 = undefined;
        const n = linux.read(0, &line, line.len);
        if (failed(n) != null or !disk.confirmed(line[0..n])) {
            say("tars-install: not confirmed; nothing was changed.\n", .{});
            return 1;
        }
    }

    var p1_buf: [32]u8 = undefined;
    var p2_buf: [32]u8 = undefined;
    const p1 = storage.partitionName(&p1_buf, path, 1).?;
    const p2 = storage.partitionName(&p2_buf, path, 2).?;

    // ── 파티션 ──
    // --wipe-partitions always: 새 파티션 자리에 남은 옛 서명을 지운다. 이미
    // TARS가 있던 디스크에 다시 설치하면 p2 자리에 옛 ext2가 그대로 있고,
    // mke2fs가 그것을 보고 머뭇거린다.
    say("tars-install: writing the partition table\n", .{});
    const sfdisk = [_:null]?[*:0]const u8{ "/usr/bin/sfdisk", "--wipe", "always", "--wipe-partitions", "always", path };
    if (!runTool(&sfdisk, disk.SFDISK_SCRIPT, WORK_DIR ++ "/sfdisk.log", envp)) return 1;
    if (!waitForNode(p1) or !waitForNode(p2)) {
        complain("{s} and {s} never appeared after 3s", .{ p1, p2 });
        return 1;
    }

    // ── 포맷 ──
    say("tars-install: formatting {s} (FAT32, {s})\n", .{ p1, disk.ESP_LABEL });
    const mkvfat = [_:null]?[*:0]const u8{ "/usr/bin/mkfs.vfat", "-F", "32", "-n", disk.ESP_LABEL, p1 };
    if (!runTool(&mkvfat, null, WORK_DIR ++ "/mkfs.vfat.log", envp)) return 1;

    say("tars-install: formatting {s} (ext2, {s})\n", .{ p2, disk.CONFIG_LABEL });
    const mke2fs = [_:null]?[*:0]const u8{ "/usr/bin/mke2fs", "-q", "-t", "ext2", "-L", disk.CONFIG_LABEL, p2 };
    if (!runTool(&mke2fs, null, WORK_DIR ++ "/mke2fs.log", envp)) return 1;

    // ── 복사 ──
    if (!mkdirOk(ESP_DIR.ptr)) {
        complain("cannot create {s}", .{ESP_DIR});
        return 1;
    }
    if (failed(linux.mount(p1.ptr, ESP_DIR.ptr, "vfat", 0, 0))) |e| {
        complain("cannot mount {s} as vfat (errno {d})", .{ p1, @intFromEnum(e) });
        return 1;
    }
    const copied = copyAll();
    // sync가 umount보다 먼저다. 캐시에만 있는 41MB는 전원 버튼과 함께
    // 사라진다(design 위험 3). umount도 쓰기를 내보내지만 실패하면 안
    // 내보내므로 sync를 따로 부른다.
    say("tars-install: syncing\n", .{});
    linux.sync();
    if (failed(linux.umount(ESP_DIR.ptr))) |e| {
        complain("cannot unmount {s} (errno {d})", .{ ESP_DIR, @intFromEnum(e) });
        return 1;
    }
    if (!copied) return 1;

    say("tars-install: done. remove the boot medium and reboot.\n", .{});
    return 0;
}

/// 매체는 findMedium이 MEDIUM_DIR에 붙여 두었고 p1은 install이 ESP_DIR에
/// 붙였다. 여기는 두 디렉터리 사이의 일만 한다.
fn copyAll() bool {
    for (disk.ESP_DIRS) |d| {
        var buf: [128]u8 = undefined;
        const p = std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ ESP_DIR, d }) catch unreachable;
        if (!mkdirOk(p.ptr)) {
            complain("cannot create {s}", .{p});
            return false;
        }
    }
    say("tars-install: copying the boot files\n", .{});
    for (disk.BOOT_FILES) |rel| {
        var from_buf: [128]u8 = undefined;
        var to_buf: [128]u8 = undefined;
        const from = std.fmt.bufPrintZ(&from_buf, "{s}/{s}", .{ MEDIUM_DIR, rel }) catch unreachable;
        const to = std.fmt.bufPrintZ(&to_buf, "{s}/{s}", .{ ESP_DIR, rel }) catch unreachable;
        const n = copyFile(from, to) orelse return false;
        say("  {s} {d} bytes\n", .{ rel, n });
    }
    return true;
}

pub fn main(init: std.process.Init.Minimal) u8 {
    const argv = init.args.vector;
    const envp = init.environ.block.slice.ptr;
    const cmd = disk.parseArgs(if (argv.len > 1) argv[1..] else argv[0..0]);
    if (cmd == .usage) {
        printUsage();
        return 2;
    }

    // 매체는 목록에도 설치에도 필요하다. 붙인 채로 돌려받고 끝에서 뗀다 —
    // 읽기 전용이라 떼는 순서가 디스크에 아무것도 안 바꾼다.
    const medium = findMedium();
    defer if (medium != null) {
        _ = linux.umount(MEDIUM_DIR.ptr);
    };

    return switch (cmd) {
        .list => blk: {
            list(medium);
            break :blk 0;
        },
        .install => |i| install(i.disk, i.yes, medium, envp),
        .usage => unreachable,
    };
}
```

읽는 사람이 볼 자리 넷.

- `findMedium`은 앞머리를 먼저 읽고 ISO9660인 것만 붙여 본다. 빈 `sr0`은
  읽기가 실패해 빠진다(DI-M0 실측 9). 붙인 채로 돌려주고 `main`의 `defer`가
  뗀다 — 읽기 전용이라 순서가 아무것도 안 바꾼다.
- `runTool`의 자식은 stdin을 파이프(`sfdisk`) 또는 `/dev/null`로, stdout·stderr를
  로그 파일로 받는다. 실패하면 종료 코드와 그 로그를 stderr에 찍는다.
- `install`은 `sync` → `umount`(ESP) → `done` 순서다(design 위험 3). 복사가
  실패해도 `sync`와 `umount`는 하고 나서 1로 끝난다.
- 끝나는 코드는 셋이다. 0 성공 · 1 거절이나 실패 · 2 쓰는 법이 틀림.

- [ ] Step 3: 빌드하고 정적인지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build && ls -l zig-out/bin && file zig-out/bin/tars-install &&
  readelf -d zig-out/bin/tars-install 2>&1 | head -2'
```

기대: `init`과 `tars-install` 둘. `file`이 `ELF 64-bit LSB executable, x86-64 …
statically linked`, `readelf -d`가 `There is no dynamic section in this file.`

- [ ] Step 4: 커밋

```bash
git diff --stat
git add init/src/install.zig init/build.zig
git commit -m "Add tars-install, which lists disks and installs onto a blank one"
```

## Task 4 — initrd에 싣고 ISO에 이름을 붙인다

Files: Modify `kernel/make_initrd.sh` · `tools/check.sh` · `boot/make_iso.sh`

- [ ] Step 1: `make_initrd.sh` — `cp ../init/zig-out/bin/init …` 두 줄 뒤에

```bash

# DI-M1: 설치기. init과 같은 zig build가 만들고 같은 이유로 정적이라
# copy_lib_deps가 필요 없다. 부르는 도구 셋(sfdisk · mkfs.vfat · mke2fs)은
# guest_tools.sh의 층 7이 싣는다. /usr/bin인 이유는 tq-probe와 같다 — 게스트의
# PATH가 /usr/bin:/bin이다.
cp ../init/zig-out/bin/tars-install "$WORKDIR/usr/bin/tars-install"
chmod 0755 "$WORKDIR/usr/bin/tars-install"
```

`$WORKDIR/usr/bin`은 이 줄보다 앞의 `mkdir -p`가 이미 만들었다(파일 93줄 근처,
`cp ../init/zig-out/bin/init` 바로 위).

- [ ] Step 2: `tools/check.sh` — `WANT+=(usr/bin/tq-probe)` 뒤에

```bash

# DI-M1: 설치기. tq-probe와 같은 자리다 — 배열에 없고 make_initrd.sh가 손으로
# 넣는다. 빠지면 install 체인의 OVMF 부팅(1분)이 아니라 여기서 먼저 드러난다.
WANT+=(usr/bin/tars-install)
```

- [ ] Step 3: `boot/make_iso.sh` — `xorriso` 줄에 `-V TARS`

```diff
-xorriso -as mkisofs -R -r -J \
+xorriso -as mkisofs -R -r -J -V TARS \
```

그리고 그 블록 위 주석 끝에 한 문단.

```bash
#
# DI-M1: -V TARS. 기본값은 ISOIMAGE였다(DI-M0 실측 6). tars-install은 이름이
# 아니라 boot/limine/limine.conf의 존재로 매체를 알아보지만(DI design 결정 4)
# 목록 머리 줄에 이 이름을 찍고, install 체인이 그 줄로 이 옵션을 본다.
```

- [ ] Step 4: tools 체인으로 본다 (약 2분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash tools/check.sh > /tmp/dim1-tools.log 2>&1; echo "exit=$?"
grep -E "PASS|FAIL|tars-install" /tmp/dim1-tools.log | tail -5
```

기대: `exit=0`, 마지막에 `PASS`. 이 체인이 `make_initrd.sh`를 돌리므로
`kernel/initrd.cpio`에 `usr/bin/tars-install`이 든 것까지 본다.

- [ ] Step 5: ISO 이름을 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd boot && ./build.sh >/dev/null && ./make_iso.sh >/dev/null 2>&1 &&
  xorriso -indev ../out/tars.iso -pvd_info 2>/dev/null | grep "Volume Id"'
```

기대: `Volume Id    : TARS`.

- [ ] Step 6: 커밋

```bash
git diff --stat
git add kernel/make_initrd.sh tools/check.sh boot/make_iso.sh
git commit -m "Carry tars-install in the initrd and name the ISO TARS"
```

## Task 5 — 열세번째 체인 `install/check.sh`

Files: Create `install/check.sh`

판정 여덟이다. 부팅 1이 1~5, 부팅 2가 6~8.

| 판정 | 무엇 | 무엇이 틀리면 빨개지나 |
|---|---|---|
| 1 | 인자 없는 `tars-install`이 쓰는 법까지 찍고 끝난다 | 실행 파일이 없다 · 도중에 죽는다 |
| 2 | `boot medium /dev/sr0 (iso9660 TARS,` | 매체 찾기 · `-V TARS` |
| 3 | `  /dev/nvme0n1 … internal   blank` | 목록 · `describe`의 blank |
| 4 | `no`에 `not confirmed`로 멈추고 디스크가 여전히 blank | YES 문지기 |
| 5 | `--yes`가 `done`까지 가고 넷을 복사했다고 말한다 | 도구 셋 · 마운트 · 복사 |
| 6 | `-cdrom` 없이 `config storage /dev/nvme0n1p2 (label tars-config)` | ESP 부팅 · 파티션 후보 |
| 7 | `mounted ext2 at /config` · `created /config/tars.conf` | `mke2fs`가 만든 p2 |
| 8 | 설치된 기계에서 `no boot medium found` | 빈 `sr0`을 매체로 오인 |

- [ ] Step 1: 파일을 만든다

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# DI-M1: 열세번째 체인. ISO로 부팅한 기계가 자기를 내장 디스크에 설치하고,
# 그 디스크만으로 다시 뜨는가(DI design 결정 9).
#
# 부팅 둘이 같은 NVMe 이미지를 잇달아 쓴다.
#   1  ISO + 빈 NVMe   tars-install의 목록 · 거절 · 설치
#   2  NVMe만          -cdrom 없이 뜨고 init이 p2를 설정 디스크로 잡는다
# 설치를 넘어 설정이 남는 것(부팅 3)은 DI-M2가 더한다.
#
# 왜 sendkey가 아니라 시리얼 FIFO인가. 다른 체인들은 terminal의 화면
# 줄(`terminal: screen>`)로 판정하는데 이 체인이 볼 것은 tars-install이
# 찍는 여러 줄의 목록이다. 콘솔 셸(ttyS0)에 FIFO로 한 줄씩 넣으면 그 출력이
# 시리얼 로그에 그대로 남는다. DI-M0 하네스가 이 모양으로 부팅 셋을 돌렸다.
# 그래서 USB 키보드는 물려만 둔다 — machine 체인과 같은 기계를 만들기 위해서다.
#
# 왜 -monitor가 없는가. 이 체인은 키를 안 보낸다. 그리고 QEMU를 kill로 끈다 —
# 전원 버튼이 아니다. tars-install이 done 전에 sync와 umount를 이미 했다는
# 것(design 위험 3)을 부팅 2가 증명하려면 끄는 쪽이 친절하면 안 된다.

(cd ../kernel && ./build.sh)
(cd ../init && zig build)
(cd ../terminal && ./prepare.sh)
(cd ../kernel && ./make_initrd.sh)
(cd ../boot && ./build.sh)
(cd ../boot && ./make_iso.sh)

source ../gate_lib.sh

OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
if [ ! -f "$OVMF_CODE" ]; then
  echo "FAIL: ${OVMF_CODE} not found; is the devcontainer image current?" >&2
  exit 1
fi

WORK="$(mktemp -d)"
DISK="${WORK}/target.img"
# 2GiB. 배치(256MiB + 1GiB)가 들어가고 나머지가 비는 가장 작은 정수다.
# truncate라 호스트 디스크를 실제로는 거의 안 쓴다.
truncate -s 2G "$DISK"

QEMU_PID=""
LOG=""
FIFO=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  exec 4>&- 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# 여기부터는 판정이 실패를 직접 다룬다. -e를 두면 아래의 대기 루프가 첫
# 불일치에서 체인을 말없이 끝낸다.
set +e

# limine의 글자마다 섞인 커서 이동과 fish의 색 escape를 걷고 \r을 줄바꿈으로.
# 행 첫머리에 기대는 판정(목록의 `  /dev/nvme0n1`)은 이것을 거친 파일로 한다.
# 타이핑한 명령줄의 에코에도 `/dev/nvme0n1`이 있으므로 행 첫머리의 공백 둘이
# 출력과 에코를 가른다(project_gate_screen_echo와 같은 종류).
clean() {
  perl -pe 's/\e\][^\a\e]*(\a|\e\\)//g; s/\e\[[0-9;?>=]*[a-zA-Z]//g;
            s/\e[()][AB0]//g; s/\r/\n/g' "$LOG"
}

fail() {
  echo "FAIL: $1"
  shift
  echo "--- context ---"
  local pattern
  for pattern in "$@"; do
    grep -aF -- "$pattern" "$LOG" | tail -5 || true
  done
  echo "--- serial log tail (cleaned) ---"
  clean | tail -40
  exit 1
}

# boot_guest <이름> [qemu 인자...]. 콘솔 셸이 뜰 때까지 기다린다.
# 고정 timeout을 안 쓰는 이유는 machine 체인과 같다 — OVMF 초기화가 느리고
# 게이트의 부하가 회차마다 다르다.
boot_guest() {
  local name="$1"; shift
  LOG="${WORK}/boot-${name}.log"
  FIFO="${WORK}/boot-${name}.fifo"
  local vars="${WORK}/vars-${name}.fd"
  cp /usr/share/OVMF/OVMF_VARS_4M.fd "$vars"
  rm -f "$FIFO"; mkfifo "$FIFO"
  exec 4<>"$FIFO"
  qemu-system-x86_64 \
    -machine q35,i8042=off \
    -m "$GUEST_MEM" \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,unit=1,file="$vars" \
    -device qemu-xhci,id=xhci \
    -device usb-kbd,bus=xhci.0 \
    -drive file="$DISK",if=none,id=target,format=raw \
    -device nvme,drive=target,serial=tarstarget \
    "$@" \
    -serial stdio \
    -monitor none \
    -display none \
    -no-reboot \
    < "$FIFO" > "$LOG" 2>&1 &
  QEMU_PID=$!

  local waited=0
  while [ "$waited" -lt 180 ]; do
    if grep -aq "tars-init: started console shell" "$LOG"; then break; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
    sleep 1; waited=$((waited + 1))
  done
  if ! grep -aq "tars-init: started console shell" "$LOG"; then
    fail "boot ${name}: the console shell never started (${waited}s)" \
      "PANIC" "efi: EFI" "tars-init"
  fi
  echo "boot ${name}: console shell up after ${waited}s"
  # fish가 프롬프트를 그릴 시간. 그 전에 넣은 줄도 tty가 들고 있다가
  # 넘겨주지만, DI-M0 하네스가 3초로 부팅 셋을 문제없이 돌렸다.
  sleep 3
}

stop_guest() {
  kill "$QEMU_PID" 2>/dev/null
  wait "$QEMU_PID" 2>/dev/null
  QEMU_PID=""
  exec 4>&-
  rm -f "$FIFO"
}

# 콘솔 셸에 한 줄.
send() { printf '%s\n' "$1" >&4; }

# 로그에 고정 문자열이 나타날 때까지 기다린다. 0이면 나왔다.
wait_log() {
  local want="$1" limit="${2:-30}" i
  for i in $(seq 1 "$((limit * 10))"); do
    if grep -aqF -- "$want" "$LOG"; then return 0; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then return 1; fi
    sleep 0.1
  done
  return 1
}

# ── 부팅 1: ISO + 빈 NVMe ──────────────────────────────────────────────
echo "=== boot 1: the ISO and a blank NVMe ==="
boot_guest 1 -cdrom ../out/tars.iso

# 판정 1. 목록. 쓰는 법의 마지막 줄이 목록의 끝이다.
send "tars-install"
wait_log "tars-install <disk> --yes  same, without asking" \
  || fail "tars-install with no arguments never finished its list" "tars-install"

# 판정 2. 매체를 찾았고 이름이 TARS다. 이 한 줄이 셋을 본다 — sr0을 앞머리로
# ISO9660으로 읽었다 · 붙여서 limine.conf를 찾았다 · make_iso.sh의 -V TARS.
if ! grep -aqF "tars-install: boot medium /dev/sr0 (iso9660 TARS," "$LOG"; then
  fail "the boot medium was not found as /dev/sr0 labelled TARS" \
    "tars-install: boot medium" "tars-install: no boot medium"
fi
echo "the boot medium is /dev/sr0, volume TARS"

# 판정 3. 빈 NVMe가 목록에 blank로 보인다.
if ! clean | grep -aE '^  /dev/nvme0n1 +[0-9]+ GB .* internal +blank$' >/dev/null; then
  fail "the blank NVMe was not listed as an internal blank disk" "/dev/nvme0n1"
fi
echo "the blank NVMe is listed as internal, blank"

# 판정 4. YES가 아니면 아무것도 안 한다. 디스크를 통째로 지우는 명령의
# 문지기이고, 게이트가 늘 --yes로 치므로 이 자리가 아니면 영영 안 밟힌다.
send "tars-install /dev/nvme0n1"
wait_log "type YES to continue: " \
  || fail "tars-install never asked for YES" "tars-install:"
send "no"
wait_log "tars-install: not confirmed; nothing was changed." \
  || fail "answering 'no' did not stop tars-install" "tars-install:"
# 그리고 정말로 안 건드렸다. 목록을 한 번 더 찍어 blank가 둘이 됐는지 센다.
send "tars-install"
for _ in $(seq 1 300); do
  [ "$(clean | grep -acE '^  /dev/nvme0n1 .* blank$')" -ge 2 ] && break
  sleep 0.1
done
if [ "$(clean | grep -acE '^  /dev/nvme0n1 .* blank$')" -lt 2 ]; then
  fail "after 'no', the NVMe was no longer blank" "/dev/nvme0n1"
fi
echo "answering 'no' left the disk blank"

# 판정 5. 설치. mke2fs가 4초, sfdisk가 3.5초(DI-M0 실측 8)라 TCG에서
# 넉넉히 120초를 준다.
send "tars-install /dev/nvme0n1 --yes"
if ! wait_log "tars-install: done. remove the boot medium and reboot." 120; then
  fail "tars-install /dev/nvme0n1 --yes never said done" \
    "tars-install:" "failed" "never appeared"
fi
# 넷이 다 갔다. 크기까지는 안 본다 — 부팅 2가 커널과 initrd를 실제로 읽는다.
for f in boot/bzImage boot/initrd.cpio boot/limine/limine.conf EFI/BOOT/BOOTX64.EFI; do
  if ! clean | grep -aE "^  ${f} [0-9]+ bytes$" >/dev/null; then
    fail "tars-install did not report copying ${f}" "tars-install: copying"
  fi
done
echo "tars-install wrote the disk and copied the four boot files"

stop_guest

# ── 부팅 2: NVMe만 ─────────────────────────────────────────────────────
echo "=== boot 2: the NVMe alone ==="
boot_guest 2

# 판정 6. 이 milestone의 심장이다. -cdrom이 없으니 ESP 말고는 뜰 곳이 없고,
# init이 설정 디스크를 디스크 전체가 아니라 p2에서 라벨로 찾았다 —
# storage.zig의 파티션 후보(DI design 결정 6)가 이 한 줄에 걸려 있다.
WANT_DISK="tars-init: config storage /dev/nvme0n1p2 (label tars-config)"
if ! grep -aqF "$WANT_DISK" "$LOG"; then
  fail "init did not pick p2 of the installed NVMe as its config disk" \
    "tars-init: config storage" "tars-init: no disk labelled"
fi
echo "booted without the ISO; init found its config on /dev/nvme0n1p2"

# 판정 7. 붙었고, 빈 p2에 첫 부팅의 씨앗을 심었다. mke2fs가 만든 것이 init이
# 쓸 수 있는 ext2라는 것까지다.
if ! grep -aq "tars-init: mounted ext2 at /config" "$LOG"; then
  fail "p2 was picked but never mounted" "tars-init: failed to mount"
fi
if ! grep -aq "tars-init: created /config/tars.conf" "$LOG"; then
  fail "the fresh config partition did not get its first-boot tars.conf" \
    "tars-init: loaded /config" "tars-init: created"
fi
echo "the config partition mounted and took the first-boot seed"

# 판정 8. 설치된 기계에서 tars-install은 매체가 없다고 말한다(design 결정 4).
# QEMU가 빈 sr0을 붙여 두므로(DI-M0 실측 9) 노드가 있어도 매체가 아니라는
# 것을 이 줄이 본다.
send "tars-install"
wait_log "tars-install <disk> --yes  same, without asking" \
  || fail "tars-install never finished its list on the installed machine" "tars-install"
if ! grep -aqF "tars-install: no boot medium found" "$LOG"; then
  fail "on the installed machine tars-install still claimed a boot medium" \
    "tars-install: boot medium"
fi
echo "on the installed machine there is no boot medium to install from"

stop_guest

echo "PASS"
exit 0
```

- [ ] Step 2: 실행 권한 · 문법 · 게이트의 진입 검사 둘

```bash
chmod +x install/check.sh
bash -n install/check.sh && echo "syntax ok"
rg -n '\|[^|]*\b(grep|rg)\b[^|]*-[a-zA-Z]*q' install/check.sh || echo "no early-exit pipe"
for s in 'cd ../kernel && ./build.sh)' 'cd ../init && zig build)' './prepare.sh' './make_initrd.sh'; do
  grep -qF "$s" install/check.sh && echo "has: $s"
done
```

기대: `syntax ok`, `no early-exit pipe`, `has:` 넷.

## Task 6 — 체인을 돌린다

- [ ] Step 1: 한 번 돌린다 (빌드 포함 약 3~4분)

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash install/check.sh > /tmp/dim1-install.log 2>&1; echo "exit=$?"
grep -E "^(=== |boot |the |answering|tars-install wrote|booted|on the|FAIL|PASS)" /tmp/dim1-install.log
```

기대: `exit=0`, 판정마다 한 줄, 끝에 `PASS`.

빨개지면 `FAIL:` 줄과 그 아래 `--- serial log tail (cleaned) ---`를 먼저
읽는다. 짐작 자리 셋.

- 판정 1에서 시간이 다 됐다 — `tars-install`이 `PATH`에 없거나 `findMedium`이
  매달렸다. cleaned tail에 `fish: Unknown command`가 있으면 Task 4다.
- 판정 5가 `failed (exit N); what it said:`로 빨갛다 — 그 아래가 도구가 한 말이다.
  `sfdisk`가 `--wipe-partitions`를 모른다고 하면 그 두 인자를 빼고 결정 4를
  M2로 넘긴다.
- 판정 6이 `/dev/nvme0n1 (label …)` 없이 `no disk labelled tars-* among 42
  candidates`면 p2가 ext2가 아니거나 라벨이 다르다 — 부팅 1의 `mke2fs` 줄을 본다.

- [ ] Step 2: 반사실 — 판정 6이 파티션 후보에 기대는가

`CANDIDATES`를 `DISKS`만으로 되돌린 사본으로 한 번 더 돌린다. 판정 6이
`no disk labelled tars-* among 14 candidates`로 빨개져야 한다. 저장소는
`-v`로 덮은 사본만 바뀐다.

```bash
cp init/src/storage.zig /tmp/dim1-storage.zig
perl -pi -e 's/^pub const CANDIDATES = DISKS \+\+ PARTITIONS;/pub const CANDIDATES = DISKS;/' /tmp/dim1-storage.zig
grep -n '^pub const CANDIDATES' /tmp/dim1-storage.zig
docker run --rm -v "$PWD":/workspace -v /tmp/dim1-storage.zig:/workspace/init/src/storage.zig:ro \
  -w /workspace tars-devcontainer bash install/check.sh > /tmp/dim1-cf.log 2>&1; echo "exit=$?"
grep -E "FAIL|PASS|no disk labelled" /tmp/dim1-cf.log | head -4
```

기대: `CANDIDATES = DISKS;` 한 줄, `exit=1`, `FAIL: init did not pick p2 of the
installed NVMe as its config disk`와 `among 14 candidates`. (`PARTITIONS`는
쓰이지 않는 `const`가 되는데 Zig는 쓰이지 않는 최상위 선언을 분석하지 않으므로
빌드는 된다.)

- [ ] Step 3: 끝나고 나서 산출물을 되돌린다

반사실 판이 `init/zig-out`과 `kernel/initrd.cpio`와 `out/tars.iso`를 사본의
코드로 남겼다. 다음 판이 다시 빌드하지만 사람이 그 산출물을 손으로 쓰기 전에
되돌린다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build && cd ../kernel && ./make_initrd.sh >/dev/null && cd ../boot && ./make_iso.sh >/dev/null 2>&1' && echo rebuilt
```

- [ ] Step 4: 커밋

```bash
git add install/check.sh
git status --short
git commit -m "Gate the installer: install from the ISO, then boot the disk alone"
```

`git status`에 `install/` 밖의 것이 보이면 커밋하지 않는다 — 체인은
`mktemp -d` 안에만 쓴다.

## Task 7 — 루트 게이트에 넣고 한 판 돌린다

Files: Modify `check.sh`

- [ ] Step 1: `CHAINS`에 한 줄

```diff
   "NW-M3:./net/check.sh"
+  "DI-M1:./install/check.sh"
 )
```

그리고 `CHAINS=(` 위 주석 문단들의 끝(machine 체인을 설명하는 문단 뒤)에 한 문단.

```bash
# DI 체인은 설치를 본다. machine 체인처럼 OVMF로 ISO를 부팅하고, 빈 NVMe에
# tars-install로 설치한 뒤 -cdrom을 떼고 그 디스크만으로 한 번 더 뜬다.
# 콘솔 셸에 시리얼 FIFO로 치는 유일한 체인이다 — 판정이 terminal 화면이 아니라
# tars-install이 찍는 목록이라서다(DI-M1 plan의 "정한 것" 6).
```

위치는 `rg -n 'machine' check.sh`로 찾는다. 알맞은 문단이 없으면 `CHAINS=(`
바로 위에 둔다.

- [ ] Step 2: 루트 게이트 (약 20~25분)

GL 이후 기준선이 16분대였고 TS가 부팅 셋, 이 체인이 OVMF 부팅 둘 × 3회를
더한다. 10분이 Bash 도구의 한도라 `run_in_background`로 돌린다.

```bash
time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh > /tmp/dim1-gate.log 2>&1; echo "exit=$?"
grep -E "PASS|FAIL" /tmp/dim1-gate.log | tail -16
grep -c FAIL /tmp/dim1-gate.log
```

기대: 체인 열셋이 전부 `PASS: 3/3`, 마지막에 `TARS check PASS`, `FAIL` 0.

- [ ] Step 3: 커밋

```bash
git diff --stat
git add check.sh
git commit -m "Add the install chain to the root gate"
```

## Task 8 — 적는다

Files: Modify `docs/superpowers/specs/2026-09-19-tars-disk-install-design.md` ·
`MEMORY.md` · `HANDOFF.md`; Create `docs/decisions/project_disk_install.md`

- [ ] Step 1: design

`Status:` 줄을 `M1이 끝났다(2026-09-XX). M2(갱신 경로 · 부팅 3)는 plan부터.`로.
"DI-M0이 실행으로 증명한 것" 절 뒤에 "DI-M1이 실행으로 증명한 것" 절을 더한다.
넣을 것 — 체인 한 판의 시간과 부팅 둘의 셸까지 걸린 초 · 부팅 1의 목록 전문
(`clean`한 것, 두 번째 목록 포함) · 설치의 진행 줄과 넷의 바이트 · 부팅 2의
`config storage` 줄 · 반사실 판의 빨강 · 루트 게이트 시각. 숫자는
`/tmp/dim1-*.log`에서 그대로 옮긴다. 위 "정한 것" 여섯도 이 절에 옮긴다.

- [ ] Step 2: 기억

`docs/decisions/project_disk_install.md` — 한 파일에 하나. 넣을 것은 세 문장
정도다. 설치된 디스크의 모양(p1 ESP · p2 `tars-config` · 나머지 빔)과 그
이유 · `init`의 후보가 이제 디스크 전체 다음 파티션이고 안전은 라벨이
지킨다는 것 · `tars-install`의 판정은 `install/check.sh`이고 콘솔 셸에 시리얼
FIFO로 친다는 것. `MEMORY.md`에 한 줄.

- [ ] Step 3: HANDOFF

맨 위 절을 DI-M1로 바꾼다. 다음 할 일은 DI-M2의 plan이다 — 갱신 경로
(design 결정 8) · 목록의 `TARS installed` · `--wipe` · 부팅 3과 `di-marker` ·
README의 실기 절 · `CHAINS`의 이름을 `DI-M2`로. 이 plan의 "정한 것" 1 · 4가
M2로 넘긴 것이다.

- [ ] Step 4: 커밋

```bash
git add docs/superpowers/specs/2026-09-19-tars-disk-install-design.md \
        docs/decisions/project_disk_install.md MEMORY.md HANDOFF.md \
        docs/superpowers/plans/2026-09-23-tars-disk-install-di-m1.md
git commit -m "Close DI-M1: an installed disk boots without the ISO"
```

## 이 milestone이 끝난 자리

`tars-install`이 빈 디스크를 지우고 설치하며, 그 디스크만으로 뜬 기계가
설정을 p2에 둔다. 이미 설치된 디스크를 알아보고 부트 파일만 가는 것은 아직
없다 — M1에서 그 디스크는 `foreign (gpt)`로 보이고, 다시 설치하면 설정까지
지운다. 그것이 M2다.
