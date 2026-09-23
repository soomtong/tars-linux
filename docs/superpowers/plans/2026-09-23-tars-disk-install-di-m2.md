# DI-M2 — 설치된 디스크를 갱신해도 설정이 남고, `--wipe`가 통째로 다시 설치한다

> 이 plan을 실행하는 사람에게: REQUIRED SUB-SKILL — superpowers:executing-plans
> (또는 subagent-driven-development)로 Task 단위로 밟는다. 단계는 체크박스
> (`- [ ]`)다. 이 저장소의 규칙대로 파일 편집·명령 실행·커밋은 Claude Code가
> 하고, 매 편집 뒤 `git diff --stat`으로 더한 줄과 지운 줄을 따로 센다.

Goal: 새 ISO로 부팅한 기계에서 `tars-install /dev/nvme0n1 --yes`를 치면, 이미
TARS가 설치된 디스크에서는 p1(부트 파일)만 갈고 p2(설정)는 남긴다. `--wipe`를
주면 통째로 다시 설치한다. 그 판정이 체인의 부팅 여섯으로 선다.

Architecture: `tars-install`이 ESP에 쓰는 `limine.conf`의 cmdline에 표지
`tars.installed`를 붙인다. `init`은 그 표지가 있을 때만 파티션을 설정 디스크
후보로 본다. 그래서 ISO로 뜬 기계는 설치된 p2를 `/config`에 붙이지 않고,
`--wipe`의 재파티션이 막히지 않는다. 설치 여부는 GPT · p1의 FAT32와
`boot/bzImage` · p2의 `tars-` 라벨, 이 셋으로 판정한다. 갱신은 M1의 설치 경로에서
`sfdisk`와 `mkfs` 둘을 건너뛴 길이다.

Tech Stack: Zig 0.16.0(libc 없음, `std.os.linux`) · sfdisk 2.41 · dosfstools 4.2 ·
e2fsprogs 1.47 · QEMU(OVMF · q35 · NVMe) · bash

---

## 이 plan을 쓰기 전에 한 것

M1처럼 plan의 코드를 먼저 `/tmp/dim2/`에 시제품으로 썼다. 이번에는
컴파일에서 멈추지 않고 체인까지 돌렸다. 아래 Task의 diff는 전부 그 시제품과
저장소의 `diff -u`를 그대로 옮긴 것이다.

- 호스트(macOS, zig 0.16.0)에서 `zig build`가 `init`과 `tars-install`을 둘 다
  만든다. `storage_test`는 `42 candidates`로 통과하고, `disk_test`도 새 검사까지
  전부 통과한다. `devices_test`·`power_test`의 실패는 M1 plan이 적어 둔 macOS 쪽
  사정 그대로다.
- 시제품의 `init/src`와 `install/check.sh`를 컨테이너에서 `-v`로 덮어 체인을
  돌렸다. 여섯 부팅이 전부 초록이었고, 빌드를 포함해 1분 35초였다(부팅마다
  콘솔 셸까지 6~7초). 주석과 상수 이름을 고친 뒤 한 판 더 돌렸고, 그것도
  초록이었다.
- 반사실 하나를 먼저 확인했다. `storage.candidates`가 표지와 상관없이 늘
  마흔둘을 주게 되돌리고 판정 10을 경고로 낮췄더니, 부팅 5의 `--wipe`가
  이렇게 죽었다.

  ```
  tars-install: /usr/bin/sfdisk failed (exit 1); what it said:
  Checking that no-one is using this disk right now ... FAILED
  This disk is currently in use - repartitioning is probably a bad idea.
  ```

  M1 검토가 예측한 충돌이 실물로 나왔고, 아래 "정한 것" 1이 푸는 것이 바로
  이 줄이다.

시제품이 찍은 실제 출력(시리얼에서 escape를 걷어 낸 것)은 이렇다.

부팅 3(ISO + 설치된 NVMe)의 갱신:

```
[    0.066649] Kernel command line: console=ttyS0
tars-init: no disk labelled tars-* among 14 candidates
tars-install: boot medium /dev/sr0 (iso9660 TARS, 51 MB)
  /dev/nvme0n1      2 GB  QEMU NVMe Ctrl         internal   TARS installed
tars-install: /dev/nvme0n1 (2 GB, QEMU NVMe Ctrl) already has TARS. p1 will be updated, p2 (your settings) is kept.
  p1  256 MiB  EFI System  FAT32  TARS-BOOT   <- bzImage, initrd.cpio, limine
  p2    1 GiB  Linux       ext2   tars-config <- not opened
  tars-install /dev/nvme0n1 --wipe erases both instead
tars-install: copying the boot files
  boot/bzImage 4563968 bytes
  boot/initrd.cpio 42788426 bytes
  boot/limine/limine.conf 923 bytes
  EFI/BOOT/BOOTX64.EFI 348160 bytes
tars-install: syncing
tars-install: updated. remove the boot medium and reboot.
```

`limine.conf`가 908바이트에서 923바이트로 늘었다. 차이 15바이트가 정확히
` tars.installed`다. 부팅 2(설치된 NVMe만)는 커널이
`Kernel command line: console=ttyS0 tars.installed`를 찍는다.

## design과 달라진 것 · 정한 것

design의 milestone 표가 M2의 범위다. 갱신 경로(결정 8) · `TARS installed` ·
`--wipe` · 설정이 남는지 보는 부팅들 · 가이드의 설치 순서 · `CHAINS`의 이름이다.
쓰면서 정한 것이 아홉이다.

1. ISO로 뜬 부팅은 파티션을 안 본다. 사용자가 골랐다(2026-09-23). 다른
   보기였던 "`--wipe`가 `/config`를 떼는 길"은 콘솔 셸(fish)이 `/config`의 파일을
   잡고 있으면 늘 EBUSY가 된다. lazy umount는 옛 ext2가 살아 있는 채로 새 p2를
   포맷하게 되니 쓸 수 없다. 그래서 표지로 가른다. `tars-install`이 ESP의
   `limine.conf`에서 `cmdline:` 줄 끝에 `tars.installed`를 붙이고(`disk.espConf`),
   `init`은 `/proc/cmdline`에 그 토큰이 있을 때만 후보 마흔둘을 훑는다. 없으면
   디스크 열넷만 훑는다(`storage.candidates`). 대가는 둘이다. ISO로 뜬 설치
   세션이 설정 없이 기본값으로 돌고, design 확인 2의 "`limine.conf`를 바이트
   그대로"가 한 줄 바뀐다. 게이트의 다른 열두 체인은 전부 디스크 전체 ext2라서
   열넷 안에서 그대로 잡힌다.
2. `/proc/cmdline`을 못 읽으면 표지가 없는 것으로 본다. 파티션을 안 보는 쪽이
   남의 디스크를 붙일 일이 적은 쪽이다. 읽기는 `storage.readHead`를 그대로
   쓴다. 이미 "앞에서 버퍼만큼 읽는다"라는 함수다.
3. `TARS installed`는 셋을 다 본다. 디스크 앞머리가 GPT인지, p1이 FAT32이고
   읽기 전용으로 붙여 보면 `boot/bzImage`가 있는지, p2가 `tars-` 라벨의
   ext2인지다. FAT32 판정은 순수 함수 `disk.isFat32`다(오프셋 82의
   `"FAT32   "`와 510의 `55 AA`). bzImage까지 보는 것이 design 위험 4의
   처방이다. 복사 전에 죽은 디스크는 갱신이 아니라 새 설치로 가야 한다.
4. 갱신도 `YES`를 받는다. 부트 파일을 덮어쓰는 일이라 새 설치와 같은 문지기를
   둔다. `--yes`가 건너뛰는 것도 같다. 파일은 제자리에서 덮는다(O_TRUNC).
   도중에 전원이 나가도 bzImage라는 이름은 남아 있어서 목록이 여전히
   `TARS installed`로 보이고, 같은 명령을 한 번 더 치면 된다. 새 이름으로 쓰고
   rename하는 길은 이번에는 안 한다.
5. 설치 안 된 디스크에 준 `--wipe`는 뜻이 없고 새 설치와 같다. 플래그는
   디스크 뒤에 순서 없이 각각 한 번까지 온다(`<disk> --wipe --yes`도
   `<disk> --yes --wipe`도 된다). 같은 플래그가 두 번이면 쓰는 법을 찍는다.
6. M1 실측 15의 작은 것 여덟 가운데, M2가 어차피 만지는 자리 셋만 넣는다.
   사용자가 골랐다.
   - SIGPIPE를 무시한다. `runTool`의 자식에서는 기본값으로 되돌린다. SIG_IGN은
     execve를 넘어 자식에게 남기 때문이다.
   - 볼륨 ID가 `TARS`인 ISO는, 붙여서 확인한 매체가 아니어도 `boot medium`으로
     보고 설치 대상에서 뺀다(`disk.isTarsMedium`).
   - 라벨의 제어 문자(0x00~0x1f, 0x7f)는 `?`로 찍는다(`disk.printable`). UTF-8은
     그대로 둔다.

   미루는 다섯은 4Kn GPT · 옛 ISO 서명 · 470바이트를 넘는 인자 · `read` 한 번의
   YES · `disk_test`의 음성 검사 둘이다. HANDOFF에 이월로 남긴다.
7. 체인은 부팅 여섯이다. design 결정 9는 넷이었다. M1에서 OVMF 부팅 한 번이
   6~7초로 쟀으니 design 위험 5의 걱정(부팅 하나에 2~3분)은 없었다. 그래서
   `--wipe`도 부팅 둘(5 · 6)을 들여 게이트가 본다.
8. 앞선 실행이 남긴 ESP 마운트를 떼는 줄(`271fe17`)을 `install()` 가운데에서
   `main()`의 맨 앞으로 옮긴다. `isInstalled`가 목록을 만들 때 같은 디렉터리에
   p1을 붙여 보기 때문에, 떼는 일이 목록보다도 먼저 와야 한다.
9. 쓰는 법이 석 줄이 된다. 첫 줄의 뜻도 바뀐다("everything on it is erased" →
   "a disk that has TARS is only updated"). 체인은 마지막 줄(`--wipe`)을 목록의
   끝으로 기다린다.

## 파일 지도

| 파일 | 무엇 | Task |
|---|---|---|
| `init/src/storage.zig` | `INSTALLED_TOKEN` · `cmdlineInstalled` · `candidates` · `bootedInstalled` · `findConfigDisk(out, list)` | 1 |
| `init/src/storage_test.zig` | 검사 11 | 1 |
| `init/src/main.zig` | `mountConfig`가 표지를 보고 후보를 고른다 | 1 |
| `init/src/disk.zig` | `printable` · `isTarsMedium` · `isFat32` · `parseArgs`의 `--wipe` · `LIMINE_CONF` · `espConf` | 2 |
| `init/src/disk_test.zig` | `--wipe` 인자 · 검사 7~10 | 2 |
| `init/src/install.zig` | `isInstalled` · 상태 칸 · 갱신 · `--wipe` · `copyConf` · `fillEsp` · SIGPIPE | 3 |
| `install/check.sh` | 부팅 둘 → 여섯, 판정 여덟 → 열여섯 | 4 |
| `docs/guides/running-tars.md` | 설치 절 · "`init`은 파티션을 안 본다" 고침 | 5 |
| `check.sh` · `README.md` | `CHAINS`의 `DI-M2` · 주석 · 게이트 시각 | 6 |
| design · 기억 · `MEMORY.md` · `CLAUDE.md` · `HANDOFF.md` | 끝난 뒤 | 7 |

---

## Task 0 — 기준선

호스트(macOS)에서 친다. 이 Task가 끝나기 전에는 저장소를 한 글자도 안 고친다.

- [ ] Step 1: 이미지가 있는지와 작업 트리가 깨끗한지 본다

```bash
docker image inspect tars-devcontainer --format '{{.Created}}'
git status --short
```

기대: 날짜 한 줄, 그리고 `git status`는 빈 출력.

- [ ] Step 2: `init`의 호스트 검사가 초록인지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  rm -rf init/.zig-cache init/zig-out; cd init && zig build && zig build test' 2>&1 | tail -8
```

기대: `storage_test: … (42 candidates)`와 `disk_test: signatures, sizes,
arguments and the YES gate hold`가 보이고 `error`가 없다.

⚠ plan을 쓰며 돌린 시제품 체인이 `kernel/initrd.cpio`와 `out/tars.iso`를
시제품 코드로 빌드해 두었다(둘 다 gitignore 대상). Task 4의 체인이 처음부터
다시 빌드하므로 따로 되돌릴 필요는 없다.

## Task 1 — `storage.zig`: 표지가 있을 때만 파티션을 본다 ("정한 것" 1 · 2)

Files: Modify `init/src/storage_test.zig` · `init/src/storage.zig` · `init/src/main.zig`

- [ ] Step 1: 검사를 먼저 넣는다

```diff
--- a/init/src/storage_test.zig
+++ b/init/src/storage_test.zig
@@ -213,6 +213,49 @@
         }
     }
 
+    // ── 11. 설치된 디스크로 떴을 때만 파티션을 본다 ─────────────────
+    //
+    // ISO로 뜬 기계가 설치된 p2를 /config에 붙이면 --wipe가 막힌다(DI-M2).
+    // 표지는 토큰이다 — 부분 문자열로 보면 `tars.installedx`에도 걸린다.
+    {
+        const yes = [_][]const u8{
+            "console=ttyS0 tars.installed",
+            "tars.installed console=ttyS0",
+            "console=ttyS0 tars.installed\n", // /proc/cmdline은 줄바꿈으로 끝난다
+        };
+        for (yes) |text| {
+            if (!storage.cmdlineInstalled(text)) {
+                std.debug.print("FAIL: '{s}' was not read as an installed boot\n", .{text});
+                return error.InstalledMissed;
+            }
+        }
+        const no = [_][]const u8{
+            "console=ttyS0",
+            "console=ttyS0 tars.installedx",
+            "console=ttyS0 nottars.installed",
+            "console=ttyS0 tars.installed=0",
+            "",
+        };
+        for (no) |text| {
+            if (storage.cmdlineInstalled(text)) {
+                std.debug.print("FAIL: '{s}' was read as an installed boot\n", .{text});
+                return error.InstalledFalsePositive;
+            }
+        }
+        if (storage.candidates(false).len != storage.DISKS.len) {
+            std.debug.print("FAIL: a boot without the mark scans {d} candidates, want {d} disks\n", .{
+                storage.candidates(false).len, storage.DISKS.len,
+            });
+            return error.PartitionsWithoutMark;
+        }
+        if (storage.candidates(true).len != storage.CANDIDATES.len) {
+            std.debug.print("FAIL: an installed boot scans {d} candidates, want {d}\n", .{
+                storage.candidates(true).len, storage.CANDIDATES.len,
+            });
+            return error.NoPartitionsWithMark;
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
  cd init && zig build test' 2>&1 | grep -E "error:|storage_test" | head -5
```

기대: `storage_test.zig`가 컴파일되지 않는다. `cmdlineInstalled`나 `candidates`에
대한 `has no member named` 에러가 나온다.

- [ ] Step 3: `storage.zig`

```diff
--- a/init/src/storage.zig
+++ b/init/src/storage.zig
@@ -85,11 +85,47 @@
     "/dev/mmcblk0p1",  "/dev/mmcblk0p2",  "/dev/mmcblk1p1",  "/dev/mmcblk1p2",
 };
 
-/// init이 설정 디스크를 찾으며 훑는 순서. 디스크 전체가 먼저다 — 게이트의
+/// 설치된 디스크로 떴을 때 init이 훑는 순서. 디스크 전체가 먼저다 — 게이트의
 /// 열두 체인은 전부 파티션 없는 ext2라 그 순서에서 먼저 잡히고, 판정이
 /// 한 줄도 안 바뀐다(DI design 결정 6).
 pub const CANDIDATES = DISKS ++ PARTITIONS;
 
+/// 설치된 디스크로 떴다는 표지. tars-install이 ESP에 쓰는 limine.conf의
+/// cmdline 끝에 이 단어를 붙이고, ISO의 limine.conf에는 없다(DI-M2).
+///
+/// 이 표지가 있어야 init이 파티션을 본다. 없으면 디스크 전체 열넷만 본다.
+/// ISO로 뜬 기계가 설치된 디스크의 p2를 /config에 붙여 버리면, 그 디스크를
+/// --wipe로 다시 파티션할 때 sfdisk가 "in use"로 거부한다(DI-M1 실측 15).
+/// 설치기로 뜬 세션은 설정 없이 깨끗하게 돈다 — 사용자가 고른 규칙이다.
+pub const INSTALLED_TOKEN = "tars.installed";
+
+/// cmdline 문자열에 INSTALLED_TOKEN이 있는가. 부분 문자열이 아니라 토큰으로
+/// 본다 — config.cmdlineWantsNoConfig와 같은 이유다(`tars.installedx`에
+/// 걸리면 안 된다). 값은 안 받는다. tars-install이 쓰는 모양은 하나뿐이다.
+pub fn cmdlineInstalled(text: []const u8) bool {
+    var it = std.mem.tokenizeAny(u8, text, " \t\r\n");
+    while (it.next()) |token| {
+        if (std.mem.eql(u8, token, INSTALLED_TOKEN)) return true;
+    }
+    return false;
+}
+
+/// 이번 부팅이 훑을 후보. 설치된 디스크로 떴으면 파티션까지 마흔둘,
+/// 아니면 디스크 전체 열넷이다.
+pub fn candidates(installed: bool) []const [:0]const u8 {
+    return if (installed) &CANDIDATES else &DISKS;
+}
+
+/// /proc/cmdline을 읽어 INSTALLED_TOKEN이 있는지 본다. 못 읽으면 false다 —
+/// 파티션을 안 보는 쪽이 안전한 쪽이다(남의 디스크를 붙일 일이 더 적다).
+/// readHead가 "앞에서 버퍼만큼 읽는다"라서 그대로 쓴다. x86의
+/// COMMAND_LINE_SIZE가 2048이다.
+pub fn bootedInstalled(cmdline_path: [:0]const u8) bool {
+    var buf: [2048]u8 = undefined;
+    const text = readHead(cmdline_path, &buf) orelse return false;
+    return cmdlineInstalled(text);
+}
+
 /// 파티션 노드의 이름. 이름이 숫자로 끝나는 디스크(nvme0n1 · mmcblk0)는
 /// 사이에 `p`가 든다 — 커널의 block/partitions/core.c가 정하는 규칙이다.
 /// 순수 함수라 storage_test가 PARTITIONS와 어긋나지 않는지 본다.
@@ -178,14 +214,15 @@
     return buf[0..len];
 }
 
-/// `tars-` 라벨을 가진 첫 후보를 out에 채우고 true. 하나도 없으면 false.
+/// list에서 `tars-` 라벨을 가진 첫 후보를 out에 채우고 true. 하나도 없으면
+/// false. list는 candidates()가 준다.
 ///
 /// 마운트로 시험하지 않는다(design 결정 11). 마흔둘을 mount로 두드리면 실패
 /// 줄이 마흔하나 찍히고, mount(2)는 파일시스템을 ext3/4로 잘못 잡았을 때 저널
 /// 재생 같은 쓰기를 할 수 있다. 읽어서 거르면 남의 디스크를 건드릴
 /// 가능성이 0이다.
-pub fn findConfigDisk(out: *Found) bool {
-    for (CANDIDATES) |path| {
+pub fn findConfigDisk(out: *Found, list: []const [:0]const u8) bool {
+    for (list) |path| {
         var buf: [HEAD_BYTES]u8 = undefined;
         const head = readHead(path, &buf) orelse continue;
         const name = tarsLabel(head) orelse continue;
```

- [ ] Step 4: `main.zig`. 호출하는 자리는 하나뿐이다

```diff
--- a/init/src/main.zig
+++ b/init/src/main.zig
@@ -110,8 +110,9 @@
 ///
 /// RM-M2까지는 /dev/vda가 여기 박혀 있었다. 그 이름은 virtio-blk에만
 /// 있어서 노트북에서는 저장소를 영영 못 찾았다 — 부팅은 됐고 설정만 매번
-/// 사라졌다. 이제 storage.zig가 후보 마흔둘(디스크 열넷, 그 다음 각각의 첫
-/// 두 파티션)을 훑어 ext2 라벨이 `tars-`로 시작하는 첫 것을 고른다. 이름이
+/// 사라졌다. 이제 storage.zig가 후보를 훑어 ext2 라벨이 `tars-`로 시작하는
+/// 첫 것을 고른다. 후보는 디스크 열넷이고, 설치된 디스크로 떴을 때만(cmdline의
+/// `tars.installed`) 각 디스크의 첫 두 파티션까지 마흔둘이다(DI-M2). 이름이
 /// 아니라 디스크 안의 표식으로 고르는 것이라, virtio든 NVMe든 SATA든 같은
 /// 코드가 지난다.
 ///
@@ -122,13 +123,14 @@
 /// 있다. 설정 파일은 어쩌다 한 번 쓰는 것이라 성능 대가가 사실상 없다.
 ///
 /// 디스크가 없는 부팅도 정상 경로다 — BF 체인은 ISO 부팅이라 -drive가 없다.
-/// 그때는 후보 마흔둘이 전부 ENOENT로 열리지 않아 로그 한 줄만 남으며, 부팅은
-/// 계속된다.
+/// 그때는 후보가 전부 ENOENT로 열리지 않아 로그 한 줄만 남으며, 부팅은
+/// 계속된다. 그 줄의 후보 수(14 · 42)가 이번 부팅이 파티션을 봤는지를 말한다.
 fn mountConfig() bool {
+    const list = storage.candidates(storage.bootedInstalled(config.CMDLINE_PATH));
     var found: storage.Found = .{};
-    if (!storage.findConfigDisk(&found)) {
+    if (!storage.findConfigDisk(&found, list)) {
         std.debug.print("tars-init: no disk labelled {s}* among {d} candidates\n", .{
-            storage.LABEL_PREFIX, storage.CANDIDATES.len,
+            storage.LABEL_PREFIX, list.len,
         });
         return false;
     }
```

`config`는 `main.zig`가 이미 import하고 있다(`config.CMDLINE_PATH`).

- [ ] Step 5: 통과하는지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build && zig build test' 2>&1 | grep -E "error|storage_test|disk_test"
```

기대: `storage_test: only a tars- labelled ext2 superblock counts (42 candidates)`,
`error` 0줄.

- [ ] Step 6: 커밋

```bash
git diff --stat
git add init/src/storage.zig init/src/storage_test.zig init/src/main.zig
git commit -m "Look at partitions only when booted from an installed disk"
```

## Task 2 — `disk.zig`: 순수 판정 넷과 `--wipe` ("정한 것" 1 · 3 · 5 · 6)

Files: Modify `init/src/disk_test.zig` · `init/src/disk.zig`

- [ ] Step 1: 검사를 먼저 넣는다

```diff
--- a/init/src/disk_test.zig
+++ b/init/src/disk_test.zig
@@ -119,6 +119,29 @@
 
         const three = [_][*:0]const u8{ "/dev/nvme0n1", "--yes", "x" };
         if (disk.parseArgs(&three) != .usage) return error.ThreeAccepted;
+
+        // --wipe는 혼자서도, --yes와 어느 순서로도 온다(DI-M2).
+        const wipe = [_][*:0]const u8{ "/dev/nvme0n1", "--wipe" };
+        switch (disk.parseArgs(&wipe)) {
+            .install => |i| if (!i.wipe or i.yes) return error.WipeWrong,
+            else => return error.WipeNotInstall,
+        }
+        const wipe_yes = [_][*:0]const u8{ "/dev/nvme0n1", "--wipe", "--yes" };
+        const yes_wipe = [_][*:0]const u8{ "/dev/nvme0n1", "--yes", "--wipe" };
+        for ([_][]const [*:0]const u8{ &wipe_yes, &yes_wipe }) |args| {
+            switch (disk.parseArgs(args)) {
+                .install => |i| if (!i.wipe or !i.yes) return error.WipeYesWrong,
+                else => return error.WipeYesNotInstall,
+            }
+        }
+        // 같은 플래그 둘. 조용히 받으면 `--yes --yes`로 --wipe를 빠뜨린 오타가
+        // 설치로 간다.
+        const twice = [_][*:0]const u8{ "/dev/nvme0n1", "--yes", "--yes" };
+        if (disk.parseArgs(&twice) != .usage) return error.TwiceAccepted;
+        const wipe_only = [_][*:0]const u8{"--wipe"};
+        if (disk.parseArgs(&wipe_only) != .usage) return error.WipeTakenAsDisk;
+        const four = [_][*:0]const u8{ "/dev/nvme0n1", "--yes", "--wipe", "x" };
+        if (disk.parseArgs(&four) != .usage) return error.FourAccepted;
     }
 
     // ── 5. knownDisk — 파티션과 부팅 매체는 대상이 아니다 ─────────────
@@ -138,5 +161,79 @@
     if (disk.confirmed("\n")) return error.EmptyAccepted;
     if (disk.confirmed("YES please\n")) return error.YesPrefixAccepted;
 
-    std.debug.print("disk_test: signatures, sizes, arguments and the YES gate hold\n", .{});
+    // ── 7. 라벨의 제어 문자는 ? 로 찍힌다 ────────────────────────────
+    //
+    // 라벨은 디스크의 바이트다. ESC가 든 라벨이 목록을 거쳐 터미널을 조종하면
+    // 안 된다(DI-M1 실측 15). UTF-8은 그대로 둔다.
+    try expectText(disk.stateText(&buf, .{ .kind = .ext2, .label = "a\x1b[2Jb" }), "foreign (ext2 a?[2Jb)", "esc in a label");
+    try expectText(disk.stateText(&buf, .{ .kind = .ext2, .label = "del\x7f" }), "foreign (ext2 del?)", "del in a label");
+    try expectText(disk.stateText(&buf, .{ .kind = .ext2, .label = "설정" }), "foreign (ext2 설정)", "utf-8 label");
+    {
+        var small: [3]u8 = undefined;
+        try expectText(disk.printable(&small, "abcdef"), "abc", "printable cuts at the buffer");
+    }
+
+    // ── 8. isTarsMedium — 볼륨 ID TARS인 ISO만 ────────────────────────
+    if (!disk.isTarsMedium(.{ .kind = .iso9660, .label = "TARS" })) return error.TarsMediumMissed;
+    if (disk.isTarsMedium(.{ .kind = .iso9660, .label = "ISOIMAGE" })) return error.OtherIsoTaken;
+    if (disk.isTarsMedium(.{ .kind = .ext2, .label = "TARS" })) return error.Ext2TarsTaken;
+
+    // ── 9. isFat32 — 82의 여덟 글자와 55 AA ──────────────────────────
+    {
+        const h = clear();
+        @memcpy(h[82..][0..8], "FAT32   ");
+        h[510] = 0x55;
+        h[511] = 0xAA;
+        if (!disk.isFat32(h)) return error.Fat32Missed;
+        h[511] = 0;
+        if (disk.isFat32(h)) return error.Fat32WithoutSignature;
+        h[511] = 0xAA;
+        @memcpy(h[82..][0..8], "FAT16   ");
+        if (disk.isFat32(h)) return error.Fat16Taken;
+        if (disk.isFat32(clear()[0..511])) return error.ShortFat32;
+    }
+
+    // ── 10. espConf — cmdline 줄에만 표지 하나 ──────────────────────
+    //
+    // 원본은 boot/limine.conf의 항목 부분을 글자 그대로 옮긴 것이다. 파일
+    // 자체를 이 검사가 못 읽으므로(패키지 밖) 실물이 표지를 받는지는 install
+    // 체인 부팅 2의 `Kernel command line:` 줄이 본다.
+    {
+        const iso =
+            \\serial: yes
+            \\timeout: 0
+            \\
+            \\/TARS
+            \\    protocol: linux
+            \\    kernel_path: boot():/boot/bzImage
+            \\    module_path: boot():/boot/initrd.cpio
+            \\    cmdline: console=ttyS0
+            \\
+        ;
+        const want =
+            \\serial: yes
+            \\timeout: 0
+            \\
+            \\/TARS
+            \\    protocol: linux
+            \\    kernel_path: boot():/boot/bzImage
+            \\    module_path: boot():/boot/initrd.cpio
+            \\    cmdline: console=ttyS0 tars.installed
+            \\
+        ;
+        var out: [512]u8 = undefined;
+        const got = disk.espConf(&out, iso) orelse return error.EspConfNull;
+        try expectText(got, want, "esp limine.conf");
+        // 한 번 더 지나도 표지는 하나다.
+        var again: [512]u8 = undefined;
+        const twice_got = disk.espConf(&again, got) orelse return error.EspConfAgainNull;
+        try expectText(twice_got, want, "esp limine.conf twice");
+        // cmdline이 없는 설정은 거부한다 — 표지 없이 설치하면 설정을 못 찾는다.
+        if (disk.espConf(&out, "serial: yes\n/TARS\n    protocol: linux\n") != null) return error.NoCmdlineAccepted;
+        // 모자란 버퍼는 null이지 잘린 파일이 아니다.
+        var tiny: [40]u8 = undefined;
+        if (disk.espConf(&tiny, iso) != null) return error.TruncatedConf;
+    }
+
+    std.debug.print("disk_test: signatures, sizes, arguments, labels, the YES gate and the ESP conf hold\n", .{});
 }
```

- [ ] Step 2: 실패하는지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build test' 2>&1 | grep -E "error:" | head -5
```

기대: `disk_test.zig`가 컴파일되지 않는다(`wipe`·`printable`·`isTarsMedium`·
`isFat32`·`espConf`가 없다).

- [ ] Step 3: `disk.zig`

```diff
--- a/init/src/disk.zig
+++ b/init/src/disk.zig
@@ -51,6 +51,16 @@
     return .{ .kind = .blank };
 }
 
+/// 라벨을 화면에 찍을 모양으로. 제어 문자(0x00~0x1f · 0x7f)는 `?`로 바꾼다 —
+/// 라벨은 디스크에 있는 바이트라 누구든 ESC를 심을 수 있고, 그대로 찍으면
+/// 목록이 터미널을 조종한다(DI-M1 실측 15). 0x80 위는 그대로 둔다. UTF-8
+/// 라벨이 깨지지 않게 하기 위해서다. buf보다 긴 부분은 자른다.
+pub fn printable(buf: []u8, text: []const u8) []const u8 {
+    const n = @min(buf.len, text.len);
+    for (text[0..n], 0..) |c, i| buf[i] = if (c < 0x20 or c == 0x7f) '?' else c;
+    return buf[0..n];
+}
+
 /// 목록의 상태 칸. 지울 내용을 한 단어라도 보여 주는 것이 "알고 설치한다"의
 /// 최소다(DI design 결정 7).
 pub fn stateText(buf: []u8, seen: Seen) []const u8 {
@@ -65,9 +75,30 @@
     if (seen.label.len == 0) {
         return std.fmt.bufPrint(buf, "foreign ({s})", .{what}) catch "foreign";
     }
-    return std.fmt.bufPrint(buf, "foreign ({s} {s})", .{ what, seen.label }) catch "foreign";
+    var label_buf: [ISO_ID_LEN]u8 = undefined;
+    const label = printable(&label_buf, seen.label);
+    return std.fmt.bufPrint(buf, "foreign ({s} {s})", .{ what, label }) catch "foreign";
 }
 
+/// ISO의 볼륨 ID. boot/make_iso.sh의 `-V TARS`와 같아야 한다.
+pub const MEDIUM_VOLUME: []const u8 = "TARS";
+
+/// 앞머리가 TARS의 부팅 매체인가. 붙여서 확인한 매체(findMedium)는 하나뿐인데
+/// TARS를 구운 스틱이 둘 꽂혀 있으면 나머지 하나가 설치 대상으로 보인다
+/// (DI-M1 실측 15). 그것도 대상에서 빼려고 볼륨 ID로 한 번 더 본다.
+pub fn isTarsMedium(seen: Seen) bool {
+    return seen.kind == .iso9660 and std.mem.eql(u8, seen.label, MEDIUM_VOLUME);
+}
+
+/// p1의 앞머리가 FAT32 부트 섹터인가. mkfs.fat이 오프셋 82(BS_FilSysType)에
+/// "FAT32   "을, 510에 55 AA를 쓴다. 82의 여덟 글자는 FAT 규격상 참고용이지만
+/// 우리가 판정하는 것은 "tars-install이 만든 p1인가"이고 그것을 만든 것이
+/// mkfs.fat이다. 오프셋이 맞는지는 install 체인의 부팅 3이 본다.
+pub fn isFat32(head: []const u8) bool {
+    return head.len >= 512 and head[510] == 0x55 and head[511] == 0xAA and
+        std.mem.eql(u8, head[82..][0..8], "FAT32   ");
+}
+
 /// 바이트를 목록에 찍을 수로. 디스크 제조사처럼 10진이다 — 512 GB라고 팔린
 /// SSD가 목록에서 476이면 사람이 다른 디스크로 읽는다.
 pub fn formatSize(buf: []u8, bytes: u64) []const u8 {
@@ -81,31 +112,33 @@
 pub const Command = union(enum) {
     /// 인자 없음. 목록만 찍는다.
     list,
-    /// `<disk>` 또는 `<disk> --yes`.
-    install: struct { disk: [:0]const u8, yes: bool },
+    /// `<disk>` 뒤에 `--yes` · `--wipe`가 각각 많아야 한 번, 순서는 상관없다.
+    install: struct { disk: [:0]const u8, yes: bool, wipe: bool },
     /// 그 밖의 전부. 쓰는 법을 찍고 2로 끝난다.
     usage,
 };
 
-/// argv[1..]을 읽는다. `--yes`는 디스크 뒤에만 온다 — 순서를 하나로 박아 두면
+/// argv[1..]을 읽는다. 디스크가 맨 앞이고 플래그는 그 뒤에만 온다 — 그래야
 /// `tars-install --yes`(디스크를 빠뜨림)가 "--yes라는 디스크"가 아니라 쓰는
-/// 법으로 떨어진다.
+/// 법으로 떨어진다. 플래그끼리의 순서는 안 본다. 같은 플래그가 두 번이면
+/// 쓰는 법이다 — 오타를 조용히 삼키지 않는다.
 pub fn parseArgs(args: []const [*:0]const u8) Command {
-    switch (args.len) {
-        0 => return .list,
-        1 => {
-            const disk = std.mem.span(args[0]);
-            if (std.mem.startsWith(u8, disk, "-")) return .usage;
-            return .{ .install = .{ .disk = disk, .yes = false } };
-        },
-        2 => {
-            const disk = std.mem.span(args[0]);
-            if (std.mem.startsWith(u8, disk, "-")) return .usage;
-            if (!std.mem.eql(u8, std.mem.span(args[1]), "--yes")) return .usage;
-            return .{ .install = .{ .disk = disk, .yes = true } };
-        },
-        else => return .usage,
+    if (args.len == 0) return .list;
+    if (args.len > 3) return .usage;
+    const disk = std.mem.span(args[0]);
+    if (std.mem.startsWith(u8, disk, "-")) return .usage;
+
+    var yes = false;
+    var wipe = false;
+    for (args[1..]) |arg| {
+        const flag = std.mem.span(arg);
+        if (!yes and std.mem.eql(u8, flag, "--yes")) {
+            yes = true;
+        } else if (!wipe and std.mem.eql(u8, flag, "--wipe")) {
+            wipe = true;
+        } else return .usage;
     }
+    return .{ .install = .{ .disk = disk, .yes = yes, .wipe = wipe } };
 }
 
 /// 사용자가 친 이름이 storage.DISKS의 것이면 그 원소를(수명이 무한한
@@ -141,11 +174,15 @@
 pub const ESP_LABEL: [:0]const u8 = "TARS-BOOT";
 pub const CONFIG_LABEL: [:0]const u8 = "tars-config";
 
+/// limine의 설정 파일. 매체의 판정(MEDIUM_MARK)이자 ESP로 갈 때 한 줄이
+/// 바뀌는 유일한 파일이다(espConf).
+pub const LIMINE_CONF: [:0]const u8 = "boot/limine/limine.conf";
+
 /// 부팅 매체에서 ESP로 가는 넷(DI design 확인 1). 경로가 양쪽에서 같다.
 pub const BOOT_FILES = [_][:0]const u8{
     "boot/bzImage",
     "boot/initrd.cpio",
-    "boot/limine/limine.conf",
+    LIMINE_CONF,
     "EFI/BOOT/BOOTX64.EFI",
 };
 
@@ -153,4 +190,43 @@
 pub const ESP_DIRS = [_][:0]const u8{ "boot", "boot/limine", "EFI", "EFI/BOOT" };
 
 /// 매체라고 판정하는 파일(DI design 결정 4). 이름이 아니라 쓰임으로 본다.
-pub const MEDIUM_MARK: [:0]const u8 = "boot/limine/limine.conf";
+pub const MEDIUM_MARK: [:0]const u8 = LIMINE_CONF;
+
+/// ISO의 limine.conf를 ESP에 쓸 모양으로 바꿔 out에 담는다. `cmdline:` 줄마다
+/// 끝에 storage.INSTALLED_TOKEN을 붙이고 나머지 바이트는 그대로다.
+///
+/// design 확인 2는 "바이트 그대로 복사한다"였고 DI-M2가 이것을 바꿨다. init은
+/// 이 표지가 있어야 파티션을 설정 디스크 후보로 본다 — ISO로 뜬 기계가
+/// 설치된 p2를 붙여 두면 --wipe가 막히기 때문이다(storage.INSTALLED_TOKEN).
+///
+/// cmdline 줄이 하나도 없거나 out이 모자라면 null이다. 표지 없이 설치하면
+/// 설치된 기계가 설정 디스크를 못 찾는다 — 그런 설치는 시작하지 않는다.
+/// 이미 표지가 있는 줄에는 다시 붙이지 않는다.
+pub fn espConf(out: []u8, conf: []const u8) ?[]const u8 {
+    const key = "cmdline:";
+    const mark = " " ++ storage.INSTALLED_TOKEN;
+    var n: usize = 0;
+    var marked = false;
+    var lines = std.mem.splitScalar(u8, conf, '\n');
+    var first = true;
+    while (lines.next()) |line| {
+        if (!first) {
+            if (n + 1 > out.len) return null;
+            out[n] = '\n';
+            n += 1;
+        }
+        first = false;
+        if (n + line.len > out.len) return null;
+        @memcpy(out[n..][0..line.len], line);
+        n += line.len;
+
+        const body = std.mem.trimStart(u8, line, " \t");
+        if (!std.mem.startsWith(u8, body, key)) continue;
+        marked = true;
+        if (storage.cmdlineInstalled(body[key.len..])) continue;
+        if (n + mark.len > out.len) return null;
+        @memcpy(out[n..][0..mark.len], mark);
+        n += mark.len;
+    }
+    return if (marked) out[0..n] else null;
+}
```

`install.zig`는 아직 `install(i.disk, i.yes, medium, envp)`를 부르고 있다.
`Command.install`에 필드가 늘어도 이 호출은 그대로 컴파일된다. `wipe`를 넘기는
것은 Task 3이다.

- [ ] Step 4: 통과하는지 본다

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build && zig build test' 2>&1 | grep -E "error|disk_test"
```

기대: `disk_test: signatures, sizes, arguments, labels, the YES gate and the ESP
conf hold`, `error` 0줄.

- [ ] Step 5: 커밋

```bash
git diff --stat
git add init/src/disk.zig init/src/disk_test.zig
git commit -m "Teach disk.zig to spot FAT32, mark the ESP conf and read --wipe"
```

## Task 3 — `install.zig`: 설치됨 · 갱신 · `--wipe` ("정한 것" 3 · 4 · 6 · 8 · 9)

Files: Modify `init/src/install.zig`

- [ ] Step 1: diff를 넣는다

```diff
--- a/init/src/install.zig
+++ b/init/src/install.zig
@@ -5,7 +5,8 @@
 
 /// tars-install — 부팅 매체의 부트 파일 넷을 내장 디스크에 옮겨 USB 없이
 /// 뜨게 한다(DI design). 인자 없이 치면 목록, 디스크를 주면 계획을 보이고
-/// YES를 받는다. `--yes`가 그 질문을 건너뛴다.
+/// YES를 받는다. `--yes`가 그 질문을 건너뛴다. 이미 TARS가 있는 디스크는
+/// p1만 갈고 p2(설정)를 남긴다. `--wipe`가 그것 대신 통째로 지운다(DI-M2).
 ///
 /// init 옆의 별도 실행 파일인 이유는 DI design 결정 5다 — 부팅 경로에 안
 /// 들어가야 게이트의 열두 체인에 닿지 않고, storage.zig를 같이 써야 목록에
@@ -140,19 +141,63 @@
 
 // ── 목록 ─────────────────────────────────────────────────────────────
 
+/// 마지막 줄이 목록의 끝이다. install 체인이 그 줄을 기다린다.
 fn printUsage() void {
-    say("tars-install <disk>        install onto <disk>; everything on it is erased\n", .{});
-    say("tars-install <disk> --yes  same, without asking\n", .{});
+    say("tars-install <disk>         install onto <disk>; a disk that has TARS is only updated\n", .{});
+    say("tars-install <disk> --yes   same, without asking\n", .{});
+    say("tars-install <disk> --wipe  erase <disk> even if it has TARS, settings too\n", .{});
 }
 
-/// 한 디스크의 상태 칸. 매체면 그 이름, 아니면 앞머리에 보이는 것.
+/// 디스크에 TARS가 설치돼 있는가(DI design 결정 7). 셋을 다 본다.
+///
+///   디스크 앞머리가 GPT
+///   p1이 FAT32이고, 붙여 보면 boot/bzImage가 있다
+///   p2가 `tars-` 라벨의 ext2
+///
+/// bzImage를 보는 것이 design 위험 4의 처방이다. sfdisk와 mkfs까지 되고
+/// 복사 전에 죽은 디스크는 installed가 아니라 새 설치로 가야 한다. 그래서
+/// 이 판정만은 앞머리가 아니라 p1을 읽기 전용으로 붙여 본다.
+fn isInstalled(path: [:0]const u8) bool {
+    var head_buf: [disk.HEAD_BYTES]u8 = undefined;
+    const head = storage.readHead(path, &head_buf) orelse return false;
+    if (disk.describe(head).kind != .gpt) return false;
+
+    var p1_buf: [32]u8 = undefined;
+    var p2_buf: [32]u8 = undefined;
+    const p1 = storage.partitionName(&p1_buf, path, 1) orelse return false;
+    const p2 = storage.partitionName(&p2_buf, path, 2) orelse return false;
+    // head_buf를 다시 쓴다. 앞의 판정이 끝났으니 앞머리는 더 필요 없다.
+    const h1 = storage.readHead(p1, &head_buf) orelse return false;
+    if (!disk.isFat32(h1)) return false;
+    const h2 = storage.readHead(p2, &head_buf) orelse return false;
+    if (storage.tarsLabel(h2) == null) return false;
+
+    if (!mkdirOk(WORK_DIR.ptr) or !mkdirOk(ESP_DIR.ptr)) return false;
+    if (failed(linux.mount(p1.ptr, ESP_DIR.ptr, "vfat", linux.MS.RDONLY, 0)) != null) return false;
+    defer _ = linux.umount(ESP_DIR.ptr);
+    var kernel_buf: [128]u8 = undefined;
+    const kernel = std.fmt.bufPrintZ(&kernel_buf, "{s}/{s}", .{ ESP_DIR, disk.BOOT_FILES[0] }) catch unreachable;
+    return exists(kernel.ptr);
+}
+
+/// 상태 칸의 두 값. install이 이 글자로 갈래를 고르므로 한 곳에 둔다.
+const STATE_MEDIUM = "boot medium";
+const STATE_INSTALLED = "TARS installed";
+
+/// 한 디스크의 상태 칸. 매체 · 설치됨 · 앞머리에 보이는 것 순이다.
+///
+/// 매체는 둘로 본다. 붙여서 확인한 것(medium)과, 볼륨 ID가 TARS인 ISO다.
+/// 스틱이 둘 꽂혀 있으면 findMedium은 첫 것만 붙인다(DI-M1 실측 15).
 fn stateOf(path: [:0]const u8, medium: ?[:0]const u8, buf: []u8) []const u8 {
     if (medium) |m| {
-        if (std.mem.eql(u8, m, path)) return "boot medium";
+        if (std.mem.eql(u8, m, path)) return STATE_MEDIUM;
     }
+    if (isInstalled(path)) return STATE_INSTALLED;
     var head_buf: [disk.HEAD_BYTES]u8 = undefined;
     const head = storage.readHead(path, &head_buf) orelse return "unreadable";
-    return disk.stateText(buf, disk.describe(head));
+    const seen = disk.describe(head);
+    if (disk.isTarsMedium(seen)) return STATE_MEDIUM;
+    return disk.stateText(buf, seen);
 }
 
 fn list(medium: ?[:0]const u8) void {
@@ -162,7 +207,8 @@
         const seen = disk.describe(head);
         var size_buf: [16]u8 = undefined;
         const size = disk.formatSize(&size_buf, sizeBytes(disk.sysName(m)) orelse 0);
-        say("tars-install: boot medium {s} (iso9660 {s}, {s})\n", .{ m, seen.label, size });
+        var label_buf: [32]u8 = undefined;
+        say("tars-install: boot medium {s} (iso9660 {s}, {s})\n", .{ m, disk.printable(&label_buf, seen.label), size });
     } else {
         say("tars-install: no boot medium found; boot from the TARS ISO or USB stick to install\n", .{});
     }
@@ -225,6 +271,15 @@
         return false;
     }
     if (pid == 0) {
+        // main이 무시하게 둔 SIGPIPE를 되돌린다. 무시 상태는 execve를 넘어
+        // 남아서, 그대로 두면 도구들이 끊긴 파이프에서 죽지 않고 EPIPE를
+        // 다뤄야 한다 — 그 도구들이 기대하는 환경이 아니다.
+        const dfl: linux.Sigaction = .{
+            .handler = .{ .handler = linux.SIG.DFL },
+            .mask = linux.sigemptyset(),
+            .flags = 0,
+        };
+        _ = linux.sigaction(.PIPE, &dfl, null);
         if (input != null) {
             _ = linux.dup2(fds[0], 0);
             _ = linux.close(fds[0]);
@@ -331,11 +386,50 @@
     return total;
 }
 
+/// 매체의 limine.conf를 읽어 표지를 붙여 ESP에 쓴다(disk.espConf). 원본은
+/// 1KB 아래라(DI-M0 실측 7의 908바이트) 버퍼 하나에 든다.
+fn copyConf(src: [:0]const u8, dst: [:0]const u8) ?u64 {
+    var in_buf: [8192]u8 = undefined;
+    const conf = readFile(src.ptr, &in_buf) orelse {
+        complain("cannot read {s}", .{src});
+        return null;
+    };
+    if (conf.len == in_buf.len) {
+        complain("{s} is larger than {d} bytes", .{ src, in_buf.len });
+        return null;
+    }
+    var out_buf: [8192 + 256]u8 = undefined;
+    const text = disk.espConf(&out_buf, conf) orelse {
+        complain("{s} has no cmdline line to mark with {s}", .{ src, storage.INSTALLED_TOKEN });
+        return null;
+    };
+
+    const rc = linux.open(dst.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
+    if (failed(rc)) |e| {
+        complain("cannot create {s} (errno {d})", .{ dst, @intFromEnum(e) });
+        return null;
+    }
+    const fd: i32 = @intCast(rc);
+    defer _ = linux.close(fd);
+    var off: usize = 0;
+    while (off < text.len) {
+        const w = linux.write(fd, text[off..].ptr, text.len - off);
+        if (failed(w)) |e| {
+            if (e == .INTR) continue;
+            complain("writing {s} failed (errno {d})", .{ dst, @intFromEnum(e) });
+            return null;
+        }
+        off += w;
+    }
+    return text.len;
+}
+
 // ── 설치 ─────────────────────────────────────────────────────────────
 
 fn install(
     target: [:0]const u8,
     yes: bool,
+    wipe: bool,
     medium: ?[:0]const u8,
     envp: [*:null]const ?[*:0]const u8,
 ) u8 {
@@ -348,27 +442,42 @@
         complain("{s} is not present on this machine", .{path});
         return 1;
     };
-    const src = medium orelse {
+    if (medium == null) {
         complain("no boot medium to copy from; boot from the TARS ISO or USB stick first", .{});
         return 1;
-    };
-    if (std.mem.eql(u8, src, path)) {
-        complain("{s} is the boot medium; pick another disk", .{path});
-        return 1;
     }
-
-    // ── 계획 ──
     var size_buf: [16]u8 = undefined;
     var model_buf: [64]u8 = undefined;
     var state_buf: [64]u8 = undefined;
     const model = sysAttr(name, "device/model", &model_buf) orelse "-";
-    say("tars-install: {s} ({s}, {s}) will be erased. it now holds: {s}\n", .{
-        path, disk.formatSize(&size_buf, bytes), model, stateOf(path, medium, &state_buf),
-    });
-    say("  p1  256 MiB  EFI System  FAT32  TARS-BOOT   <- bzImage, initrd.cpio, limine\n", .{});
-    say("  p2    1 GiB  Linux       ext2   tars-config <- your settings, empty at first\n", .{});
-    say("  rest unallocated\n", .{});
+    const state = stateOf(path, medium, &state_buf);
+    if (std.mem.eql(u8, state, STATE_MEDIUM)) {
+        complain("{s} is a TARS boot medium; pick another disk", .{path});
+        return 1;
+    }
+    const installed = std.mem.eql(u8, state, STATE_INSTALLED);
+    // 설치된 디스크에 --wipe가 없으면 갱신이다(design 결정 8). 설치 안 된
+    // 디스크의 --wipe는 뜻이 없다 — 어차피 통째로 지운다.
+    const update = installed and !wipe;
 
+    // ── 계획 ──
+    if (update) {
+        say("tars-install: {s} ({s}, {s}) already has TARS. p1 will be updated, p2 (your settings) is kept.\n", .{
+            path, disk.formatSize(&size_buf, bytes), model,
+        });
+        say("  p1  256 MiB  EFI System  FAT32  TARS-BOOT   <- bzImage, initrd.cpio, limine\n", .{});
+        say("  p2    1 GiB  Linux       ext2   tars-config <- not opened\n", .{});
+        say("  tars-install {s} --wipe erases both instead\n", .{path});
+    } else {
+        say("tars-install: {s} ({s}, {s}) will be erased. it now holds: {s}\n", .{
+            path, disk.formatSize(&size_buf, bytes), model, state,
+        });
+        say("  p1  256 MiB  EFI System  FAT32  TARS-BOOT   <- bzImage, initrd.cpio, limine\n", .{});
+        say("  p2    1 GiB  Linux       ext2   tars-config <- your settings, empty at first\n", .{});
+        say("  rest unallocated\n", .{});
+        if (installed) say("  the settings now on p2 are erased too\n", .{});
+    }
+
     if (!yes) {
         say("type YES to continue: ", .{});
         var line: [64]u8 = undefined;
@@ -384,15 +493,16 @@
     const p1 = storage.partitionName(&p1_buf, path, 1).?;
     const p2 = storage.partitionName(&p2_buf, path, 2).?;
 
+    if (update) {
+        if (!fillEsp(p1)) return 1;
+        say("tars-install: updated. remove the boot medium and reboot.\n", .{});
+        return 0;
+    }
+
     // ── 파티션 ──
     // --wipe-partitions always: 새 파티션 자리에 남은 옛 서명을 지운다. 이미
     // TARS가 있던 디스크에 다시 설치하면 p2 자리에 옛 ext2가 그대로 있고,
     // mke2fs가 그것을 보고 머뭇거린다.
-    // 앞선 실행이 복사 도중 죽었으면(Ctrl-C) p1이 ESP_DIR에 붙은 채 남아 있고,
-    // sfdisk가 "in use"로 거부한다. 게스트에 umount 명령이 없어 사람이 뗄 길이
-    // 없으므로 여기서 뗀다. 안 붙어 있으면 EINVAL이고 그것이 보통의 경우다.
-    _ = linux.umount(ESP_DIR.ptr);
-
     say("tars-install: writing the partition table\n", .{});
     const sfdisk = [_:null]?[*:0]const u8{ "/usr/bin/sfdisk", "--wipe", "always", "--wipe-partitions", "always", path };
     if (!runTool(&sfdisk, disk.SFDISK_SCRIPT, WORK_DIR ++ "/sfdisk.log", envp)) return 1;
@@ -410,14 +520,27 @@
     const mke2fs = [_:null]?[*:0]const u8{ "/usr/bin/mke2fs", "-q", "-t", "ext2", "-L", disk.CONFIG_LABEL, p2 };
     if (!runTool(&mke2fs, null, WORK_DIR ++ "/mke2fs.log", envp)) return 1;
 
-    // ── 복사 ──
+    if (!fillEsp(p1)) return 1;
+    say("tars-install: done. remove the boot medium and reboot.\n", .{});
+    return 0;
+}
+
+/// p1을 붙이고 넷을 쓰고 sync하고 뗀다. 새 설치와 갱신이 같은 길이다 —
+/// 갱신은 이 앞의 sfdisk와 mkfs를 건너뛸 뿐이다.
+///
+/// 갱신은 파일을 제자리에서 덮는다(O_TRUNC). 도중에 전원이 나가면 p1의
+/// 커널이나 initrd가 반쪽이 되지만, 그 자리의 사람은 ISO를 손에 들고 있고
+/// bzImage가 이름으로는 남아 있어 목록이 여전히 `TARS installed`로 보인다 —
+/// 같은 명령을 한 번 더 치면 된다. 새 이름으로 쓰고 rename하는 길은 p1에
+/// 두 벌이 들 자리(90MB)가 있지만 이번에는 안 한다.
+fn fillEsp(p1: [:0]const u8) bool {
     if (!mkdirOk(ESP_DIR.ptr)) {
         complain("cannot create {s}", .{ESP_DIR});
-        return 1;
+        return false;
     }
     if (failed(linux.mount(p1.ptr, ESP_DIR.ptr, "vfat", 0, 0))) |e| {
         complain("cannot mount {s} as vfat (errno {d})", .{ p1, @intFromEnum(e) });
-        return 1;
+        return false;
     }
     const copied = copyAll();
     // sync가 umount보다 먼저다. 캐시에만 있는 41MB는 전원 버튼과 함께
@@ -427,12 +550,9 @@
     linux.sync();
     if (failed(linux.umount(ESP_DIR.ptr))) |e| {
         complain("cannot unmount {s} (errno {d})", .{ ESP_DIR, @intFromEnum(e) });
-        return 1;
+        return false;
     }
-    if (!copied) return 1;
-
-    say("tars-install: done. remove the boot medium and reboot.\n", .{});
-    return 0;
+    return copied;
 }
 
 /// 매체는 findMedium이 MEDIUM_DIR에 붙여 두었고 p1은 install이 ESP_DIR에
@@ -452,7 +572,9 @@
         var to_buf: [128]u8 = undefined;
         const from = std.fmt.bufPrintZ(&from_buf, "{s}/{s}", .{ MEDIUM_DIR, rel }) catch unreachable;
         const to = std.fmt.bufPrintZ(&to_buf, "{s}/{s}", .{ ESP_DIR, rel }) catch unreachable;
-        const n = copyFile(from, to) orelse return false;
+        // limine.conf만 한 줄이 바뀐다(disk.espConf). 나머지 셋은 바이트 그대로다.
+        const copied = if (std.mem.eql(u8, rel, disk.LIMINE_CONF)) copyConf(from, to) else copyFile(from, to);
+        const n = copied orelse return false;
         say("  {s} {d} bytes\n", .{ rel, n });
     }
     return true;
@@ -467,6 +589,25 @@
         return 2;
     }
 
+    // SIGPIPE를 무시한다. sfdisk가 배치를 읽기 전에 죽으면 runTool의 write가
+    // 끊긴 파이프에 쓰고, 기본 동작이면 tars-install이 그 자리에서 말없이
+    // 죽는다(DI-M1 실측 15). 무시하면 write가 EPIPE로 돌아오고, 그 뒤의
+    // wait4가 sfdisk가 무엇으로 죽었는지를 찍는다. SIG_IGN은 execve를 넘어
+    // 자식에게 남으므로 fork한 자식에서는 기본값으로 되돌린다(runTool).
+    const ignore: linux.Sigaction = .{
+        .handler = .{ .handler = linux.SIG.IGN },
+        .mask = linux.sigemptyset(),
+        .flags = 0,
+    };
+    _ = linux.sigaction(.PIPE, &ignore, null);
+
+    // 앞선 실행이 복사 도중 죽었으면(Ctrl-C) p1이 ESP_DIR에 붙은 채 남아
+    // 있다. 게스트에 umount 명령이 없어 사람이 뗄 길이 없으므로 여기서 뗀다.
+    // 안 붙어 있으면 EINVAL이고 그것이 보통의 경우다. 목록보다 먼저인 것은
+    // isInstalled가 같은 자리에 p1을 붙여 보기 때문이고, 설치보다 먼저인 것은
+    // 남은 마운트가 있으면 sfdisk가 "in use"로 거부하기 때문이다(DI-M1 271fe17).
+    _ = linux.umount(ESP_DIR.ptr);
+
     // 매체는 목록에도 설치에도 필요하다. 붙인 채로 돌려받고 끝에서 뗀다 —
     // 읽기 전용이라 떼는 순서가 디스크에 아무것도 안 바꾼다.
     const medium = findMedium();
@@ -479,7 +620,7 @@
             list(medium);
             break :blk 0;
         },
-        .install => |i| install(i.disk, i.yes, medium, envp),
+        .install => |i| install(i.disk, i.yes, i.wipe, medium, envp),
         .usage => unreachable,
     };
 }
```

읽을 때 볼 자리는 넷이다.

- `stateOf`의 순서는 붙인 매체 → 설치됨 → 앞머리다. 설치된 디스크의 앞머리는
  GPT라서 순서가 바뀌면 `foreign (gpt)`로 보인다.
- `install()`의 갈래는 `update = installed and !wipe` 하나다. 갱신은 `fillEsp`로
  바로 가고, 나머지는 M1의 `sfdisk` → `mkfs` 둘 → `fillEsp` 그대로다.
- `copyAll`은 `limine.conf`만 `copyConf`로 보낸다. 나머지 셋은 바이트 그대로다.
- ESP를 떼는 줄이 `main()`으로 올라갔다. `isInstalled`보다 먼저 와야 한다.

- [ ] Step 2: 빌드와 검사

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build && zig build test && ls -l zig-out/bin' 2>&1 | grep -E "error|_test:|tars-install"
```

기대: `error` 0줄, `tars-install`이 3.4MB 안팎.

- [ ] Step 3: 커밋

```bash
git diff --stat
git add init/src/install.zig
git commit -m "Update an installed disk in place, and erase it only with --wipe"
```

## Task 4 — 체인: 부팅 여섯 ("정한 것" 7)

Files: Modify `install/check.sh`

- [ ] Step 1: diff를 넣는다

```diff
--- a/install/check.sh
+++ b/install/check.sh
@@ -3,13 +3,17 @@
 
 cd "$(dirname "$0")"
 
-# DI-M1: 열세번째 체인. ISO로 부팅한 기계가 자기를 내장 디스크에 설치하고,
-# 그 디스크만으로 다시 뜨는가(DI design 결정 9).
+# DI-M1 · M2: 열세번째 체인. ISO로 부팅한 기계가 자기를 내장 디스크에
+# 설치하고, 그 디스크만으로 다시 뜨고, 새 ISO로 갱신해도 설정이 남는가
+# (DI design 결정 9).
 #
-# 부팅 둘이 같은 NVMe 이미지를 잇달아 쓴다.
-#   1  ISO + 빈 NVMe   tars-install의 목록 · 거절 · 설치
-#   2  NVMe만          -cdrom 없이 뜨고 init이 p2를 설정 디스크로 잡는다
-# 설치를 넘어 설정이 남는 것(부팅 3)은 DI-M2가 더한다.
+# 부팅 여섯이 같은 NVMe 이미지를 잇달아 쓴다.
+#   1  ISO + 빈 NVMe       tars-install의 목록 · 거절 · 설치
+#   2  NVMe만              -cdrom 없이 뜨고 init이 p2를 잡는다. 마커를 쓴다
+#   3  ISO + 설치된 NVMe   init이 p2를 안 잡는다 · TARS installed · 갱신
+#   4  NVMe만              갱신을 넘어 마커가 남았다
+#   5  ISO + 설치된 NVMe   --wipe로 통째로 다시 설치
+#   6  NVMe만              마커가 사라졌고 설정이 첫 부팅처럼 새로 깔린다
 #
 # 왜 sendkey가 아니라 시리얼 FIFO인가. 다른 체인들은 terminal의 화면
 # 줄(`terminal: screen>`)로 판정하는데 이 체인이 볼 것은 tars-install이
@@ -137,6 +141,9 @@
 # 콘솔 셸에 한 줄.
 send() { printf '%s\n' "$1" >&4; }
 
+# tars-install 목록의 마지막 줄(install.zig의 printUsage). 목록이 끝났다는 표지다.
+LIST_END="tars-install <disk> --wipe  erase <disk> even if it has TARS, settings too"
+
 # 로그에 고정 문자열이 나타날 때까지 기다린다. 0이면 나왔다.
 wait_log() {
   local want="$1" limit="${2:-30}" i
@@ -154,7 +161,7 @@
 
 # 판정 1. 목록. 쓰는 법의 마지막 줄이 목록의 끝이다.
 send "tars-install"
-wait_log "tars-install <disk> --yes  same, without asking" \
+wait_log "$LIST_END" \
   || fail "tars-install with no arguments never finished its list" "tars-install"
 
 # 판정 2. 매체를 찾았고 이름이 TARS다. 이 한 줄이 셋을 본다 — sr0을 앞머리로
@@ -234,17 +241,136 @@
 
 # 판정 8. 설치된 기계에서 tars-install은 매체가 없다고 말한다(design 결정 4).
 # QEMU가 빈 sr0을 붙여 두므로(DI-M0 실측 9) 노드가 있어도 매체가 아니라는
-# 것을 이 줄이 본다.
+# 것을 이 줄이 본다. 그리고 자기 디스크를 TARS installed로 읽는다 — p1을
+# 붙여 bzImage를 보는 isInstalled가 진짜 FAT32에서 도는 첫 자리다.
 send "tars-install"
-wait_log "tars-install <disk> --yes  same, without asking" \
+wait_log "$LIST_END" \
   || fail "tars-install never finished its list on the installed machine" "tars-install"
 if ! grep -aqF "tars-install: no boot medium found" "$LOG"; then
   fail "on the installed machine tars-install still claimed a boot medium" \
     "tars-install: boot medium"
 fi
-echo "on the installed machine there is no boot medium to install from"
+if ! clean | grep -aE '^  /dev/nvme0n1 +[0-9]+ GB .* internal +TARS installed$' >/dev/null; then
+  fail "the installed NVMe was not listed as TARS installed" "/dev/nvme0n1"
+fi
+echo "on the installed machine there is no boot medium, and the disk reads as TARS installed"
+
+# 판정 9. 이 부팅이 표지를 달고 떴다. tars-install이 ESP의 limine.conf에
+# 붙인 것이다(disk.espConf). 커널이 부팅 때 cmdline을 찍는 줄로 본다 —
+# 타이핑한 명령의 에코가 섞일 일이 없다.
+if ! grep -aE 'Kernel command line: .*tars\.installed' "$LOG" >/dev/null; then
+  fail "the installed disk did not boot with tars.installed on its command line" \
+    "Kernel command line"
+fi
+echo "the installed disk booted with tars.installed"
+
+# 마커. 부팅 4가 이것이 갱신을 넘었는지, 부팅 6이 --wipe로 사라졌는지 본다.
+# 출력(di-marker-written)이 타이핑한 줄에 없는 모양이라 에코와 안 섞인다.
+send "echo kept > /config/di-marker && printf 'di-marker-%s\n' written"
+wait_log "di-marker-written" \
+  || fail "could not write the marker onto the config partition" "di-marker"
+echo "wrote /config/di-marker"
+
+stop_guest
+
+# ── 부팅 3: ISO + 설치된 NVMe ──────────────────────────────────────────
+echo "=== boot 3: the ISO and the installed NVMe ==="
+boot_guest 3 -cdrom ../out/tars.iso
+
+# 판정 10. ISO로 뜬 부팅은 파티션을 안 본다. 표지가 없어서다 — 설치된 p2를
+# /config에 붙이면 --wipe가 "in use"로 막힌다(DI-M2 plan의 "정한 것" 1).
+# 14는 디스크 전체의 수다. 42면 파티션까지 봤다는 뜻이다.
+if ! grep -aqF "tars-init: no disk labelled tars-* among 14 candidates" "$LOG"; then
+  fail "booting the ISO, init looked at partitions or picked the installed p2" \
+    "tars-init: config storage" "tars-init: no disk labelled"
+fi
+echo "booted from the ISO, init left the installed p2 alone"
+
+# 판정 11. 목록이 설치된 디스크를 알아본다.
+send "tars-install"
+wait_log "$LIST_END" \
+  || fail "tars-install never finished its list next to an installed disk" "tars-install"
+if ! clean | grep -aE '^  /dev/nvme0n1 +[0-9]+ GB .* internal +TARS installed$' >/dev/null; then
+  fail "the installed NVMe was not listed as TARS installed" "/dev/nvme0n1"
+fi
+echo "the installed NVMe is listed as TARS installed"
+
+# 판정 12. 갱신. 계획 문구가 update이고 updated로 끝난다(design 결정 8).
+send "tars-install /dev/nvme0n1 --yes"
+if ! wait_log "tars-install: updated. remove the boot medium and reboot." 120; then
+  fail "updating the installed NVMe never said updated" \
+    "tars-install:" "failed"
+fi
+if ! grep -aqF "already has TARS. p1 will be updated, p2 (your settings) is kept." "$LOG"; then
+  fail "the update did not say it keeps p2" "tars-install:"
+fi
+if grep -aqF "tars-install: writing the partition table" "$LOG"; then
+  fail "the update repartitioned the disk" "tars-install:"
+fi
+echo "the update rewrote p1 only"
 
 stop_guest
 
+# ── 부팅 4: NVMe만, 갱신 뒤 ────────────────────────────────────────────
+echo "=== boot 4: the NVMe alone, after the update ==="
+boot_guest 4
+
+# 판정 13. 갱신한 ESP로 떴고(표지가 다시 붙었다) p2를 다시 잡았으며,
+# 그 p2는 새것이 아니다 — 씨앗을 다시 깔지 않고 읽었다.
+if ! grep -aqF "$WANT_DISK" "$LOG"; then
+  fail "after the update init did not pick p2" \
+    "tars-init: config storage" "tars-init: no disk labelled"
+fi
+if ! grep -aq "tars-init: loaded /config/tars.conf" "$LOG"; then
+  fail "after the update tars.conf was not the one from before" \
+    "tars-init: loaded /config" "tars-init: created"
+fi
+
+# 판정 14. 이 milestone의 심장이다 — 마커가 갱신을 넘었다.
+send "printf 'di-marker:'; cat /config/di-marker"
+wait_log "di-marker:kept" \
+  || fail "the marker did not survive the update" "di-marker"
+echo "the marker survived the update"
+
+stop_guest
+
+# ── 부팅 5: ISO + 설치된 NVMe, --wipe ──────────────────────────────────
+echo "=== boot 5: the ISO and the installed NVMe, --wipe ==="
+boot_guest 5 -cdrom ../out/tars.iso
+
+# 판정 15. --wipe는 갱신 대신 통째로 지운다. 부팅 3이 p2를 안 붙인 것이
+# 여기서 쓰인다 — 붙였으면 sfdisk가 "in use"로 거부한다.
+send "tars-install /dev/nvme0n1 --wipe --yes"
+if ! wait_log "tars-install: done. remove the boot medium and reboot." 120; then
+  fail "tars-install /dev/nvme0n1 --wipe --yes never said done" \
+    "tars-install:" "failed" "in use"
+fi
+if ! grep -aqF "the settings now on p2 are erased too" "$LOG"; then
+  fail "--wipe did not warn that it erases the settings" "tars-install:"
+fi
+echo "--wipe reinstalled the disk"
+
+stop_guest
+
+# ── 부팅 6: NVMe만, --wipe 뒤 ──────────────────────────────────────────
+echo "=== boot 6: the NVMe alone, after --wipe ==="
+boot_guest 6
+
+# 판정 16. 새 p2다. 씨앗이 다시 깔렸고 마커가 없다.
+if ! grep -aqF "$WANT_DISK" "$LOG"; then
+  fail "after --wipe init did not pick p2" \
+    "tars-init: config storage" "tars-init: no disk labelled"
+fi
+if ! grep -aq "tars-init: created /config/tars.conf" "$LOG"; then
+  fail "after --wipe the config partition was not fresh" \
+    "tars-init: loaded /config" "tars-init: created"
+fi
+send "test -e /config/di-marker || printf 'di-marker-%s\n' gone"
+wait_log "di-marker-gone" \
+  || fail "the marker survived --wipe" "di-marker"
+echo "--wipe left a fresh config partition"
+
+stop_guest
+
 echo "PASS"
 exit 0
```

판정이 무엇을 보는지.

| 부팅 | 판정 | 보는 것 |
|---|---|---|
| 1 | 1~5 | M1 그대로. 목록의 끝을 기다리는 줄만 `LIST_END`로 바뀌었다 |
| 2 | 6 · 7 | M1 그대로(p2를 잡고 씨앗을 깐다) |
| 2 | 8 | 매체가 없다 + 자기 디스크가 `TARS installed`. `isInstalled`가 진짜 FAT32에서 도는 첫 자리다 |
| 2 | 9 | `Kernel command line: … tars.installed`. `espConf`가 실물 `limine.conf`에 표지를 붙였다 |
| 2 | (마커) | `/config/di-marker`를 쓴다 |
| 3 | 10 | ISO 부팅은 `among 14 candidates`. p2를 안 붙였다 |
| 3 | 11 · 12 | `TARS installed` · 갱신 문구 · `updated.` · 파티션 테이블을 안 썼다 |
| 4 | 13 · 14 | p2를 다시 잡고 `loaded`(새로 안 깔았다) · 마커가 `di-marker:kept` |
| 5 | 15 | `--wipe --yes`가 `done.`. 설정도 지운다는 줄이 있다 |
| 6 | 16 | p2를 잡고 `created`(새것) · 마커가 없다(`di-marker-gone`) |

마커 명령은 셋 다 출력 모양이 타이핑한 줄에 안 들어 있게 짰다. 타이핑한 줄은
`printf 'di-marker-%s\n' written`이고 출력은 `di-marker-written`이다. 콘솔 셸의
에코가 판정에 걸리지 않는다(`project_gate_screen_echo`와 같은 종류).

- [ ] Step 2: 체인을 단독으로 돌린다 (빌드 포함 2~4분)

Task 0 뒤로 `init`이 바뀌었으니 initrd와 ISO가 새로 빌드된다.

```bash
time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash install/check.sh > /tmp/dim2-chain.log 2>&1; echo "exit=$?"
grep -E "^(===|boot [0-9]|PASS|FAIL)|^the |^--wipe|^booted|^on the|^wrote|^answering|^tars-install wrote" /tmp/dim2-chain.log
```

기대: `exit=0`. `=== boot 1`부터 `=== boot 6`까지 있고 마지막 줄이 `PASS`다.

- [ ] Step 3: 반사실. 표지를 안 보는 `init`은 판정 10에서 빨강이다

```bash
mkdir -p /tmp/dim2cf
cp init/src/storage.zig /tmp/dim2cf/storage.zig
sd -F 'return if (installed) &CANDIDATES' 'return if (installed or true) &CANDIDATES' /tmp/dim2cf/storage.zig
grep -n "installed or true" /tmp/dim2cf/storage.zig
docker run --rm -v "$PWD":/workspace \
  -v /tmp/dim2cf/storage.zig:/workspace/init/src/storage.zig:ro \
  -w /workspace tars-devcontainer bash install/check.sh > /tmp/dim2cf/run.log 2>&1; echo "exit=$?"
grep -E "^FAIL" /tmp/dim2cf/run.log
```

기대: `exit=1`, `FAIL: booting the ISO, init looked at partitions or picked the
installed p2`. `grep -n`이 한 줄을 찍지 않으면 치환이 안 먹은 것이다. 그때는
반사실을 믿지 말고 사본을 손으로 고친다. 판정 10을 끄면 그 뒤에 부팅 5가 `in use`로
죽는다는 것은 plan을 쓰며 이미 봤다("이 plan을 쓰기 전에 한 것").

끝나면 반사실이 남긴 산출물을 되돌린다. 다음 Task의 게이트가 어차피 지우지만,
그 사이에 누가 `out/tars.iso`를 쓰면 반사실 코드로 뜬다.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  cd init && zig build && cd ../kernel && ./make_initrd.sh && cd ../boot && ./make_iso.sh' > /dev/null 2>&1; echo "restored=$?"
```

- [ ] Step 4: 커밋

```bash
git diff --stat
git add install/check.sh
git commit -m "Grow the install chain to six boots: update keeps settings, --wipe drops them"
```

## Task 5 — 가이드: 설치 순서

Files: Modify `docs/guides/running-tars.md`

- [ ] Step 1: VM 절의 "설치는 안 된다"를 바꾼다

지울 것(154~159행 근처):

```markdown
### 설치는 안 된다

인스톨러가 없다. live ISO 하나뿐이고 디스크에 설치하는 경로가 없다. 게스트
안에서 만든 파일은 `/config`에 쓴 것 말고 재부팅하면 전부 사라진다 —
initramfs가 tmpfs이기 때문이다. `HANDOFF.md`가 다음 서브프로젝트 후보 1번으로
올려 둔 것이 이것이다.
```

넣을 것:

```markdown
### VM의 디스크에 설치하기

실기와 같다. 빈 디스크를 하나 더 붙이고 ISO로 뜬 뒤 `tars-install`을 친다 —
아래 "내장 디스크에 설치하기". 펌웨어가 UEFI여야 한다(legacy BIOS 설치는 DI
design의 비목표다). 설치한 뒤에도 시스템은 initramfs에서 돈다. 재부팅을 넘어
남는 것은 여전히 `/config`, 곧 설치된 디스크의 p2뿐이다.
```

- [ ] Step 2: 실기 절에 설치 절을 더한다

"### 꽂기 전에 펌웨어에서 할 일" 절 바로 뒤, "### 설정을 부팅 사이에 남기려면"
앞에 넣는다.

````markdown
### 내장 디스크에 설치하기

USB로 뜬 기계에서 인자 없이 치면 목록이 나온다. 무엇을 지우게 되는지는 이
목록의 마지막 칸이 말한다.

```
$ tars-install
tars-install: boot medium /dev/sda (iso9660 TARS, 51 MB)

  /dev/nvme0n1    512 GB  Samsung SSD 980        internal   foreign (gpt)
  /dev/sda         32 GB  SanDisk Ultra          removable  boot medium

tars-install <disk>         install onto <disk>; a disk that has TARS is only updated
tars-install <disk> --yes   same, without asking
tars-install <disk> --wipe  erase <disk> even if it has TARS, settings too
```

`tars-install /dev/nvme0n1`은 계획을 찍고 대문자 `YES`를 기다린다. 새 설치는
디스크 전체를 지우고 GPT에 둘을 만든다. p1은 256MiB ESP(FAT32 `TARS-BOOT`)이고
커널·initrd·limine이 들어간다. p2는 1GiB ext2(`tars-config`)이고 설정이 산다.
나머지는 비워 둔다. `done.`이 나오면 USB를 뽑고 전원 버튼을 누른다. 설치기는
재부팅하지 않는다.

새 ISO가 나오면 그 ISO로 떠서 같은 명령을 친다. 목록이 그 디스크를
`TARS installed`로 보이고, p1의 파일 넷만 갈고 p2는 열지도 않는다(`updated.`).
처음부터 다시 하려면 `--wipe`를 준다. 설정도 함께 지워진다.

ISO로 뜬 동안에는 설치된 디스크의 설정이 안 붙는다(`among 14 candidates`).
`tars-install`이 ESP의 `limine.conf`에 `tars.installed`를 붙여 두고, `init`은
그 표지가 있을 때만 파티션을 보기 때문이다. 설치기로 뜬 세션이 그 디스크를
붙잡고 있으면 `--wipe`가 다시 파티션할 수 없다.

안 되는 것: legacy BIOS 부팅, 다른 OS 옆에 나란히 설치(새 설치는 늘 디스크
전체를 지운다), 펌웨어의 부트 항목 등록. 펌웨어는 항목 없이도
`\EFI\BOOT\BOOTX64.EFI`를 찾는다.
````

- [ ] Step 3: "설정을 부팅 사이에 남기려면"의 낡은 문장을 고친다

지울 것:

```markdown
파티션이 아니라 디스크 전체를 포맷한다 — 지금 `init`은 파티션을 안 본다.
그리고 노트북 내장 디스크는 GPT라 이 훑기에 걸리지 않는다(superblock 매직이
안 맞는다). 남의 파일시스템을 잡을 길이 없다는 뜻이다.
```

넣을 것:

```markdown
파티션이 아니라 디스크 전체를 포맷한다. `init`은 설치된 디스크로 떴을 때만
파티션을 본다(cmdline의 `tars.installed`). 내장 디스크에 설치했다면 설정은 그
디스크의 p2에 살고, 이 스틱은 필요 없다. 노트북 내장 디스크의 GPT 자체는 이
훑기에 걸리지 않는다(superblock 매직이 안 맞는다). 파티션을 볼 때도 라벨이
`tars-`로 시작하지 않으면 잡지 않는다. 남의 파일시스템을 잡을 길이 없다는 뜻이다.
```

- [ ] Step 4: 맨 끝 문단의 체인 수

`이 저장소의 어떤 게이트도 실기 부팅을 검증하지 않는다. 열한 체인이 전부`에서
`열한 체인이 전부`를 `열세 체인이 전부`로 바꾼다.

- [ ] Step 5: 커밋

```bash
git diff --stat
git add docs/guides/running-tars.md
git commit -m "Document installing, updating and wiping in the running guide"
```

## Task 6 — 루트 게이트

Files: Modify `check.sh` · `README.md`

- [ ] Step 1: `CHAINS`의 이름과 주석

```diff
-  "DI-M1:./install/check.sh"
+  "DI-M2:./install/check.sh"
```

`CHAINS=(` 위의 DI 문단을 이것으로 바꾼다.

```bash
# DI 체인은 설치를 본다. machine 체인처럼 OVMF로 ISO를 부팅하고, 빈 NVMe에
# tars-install로 설치한 뒤 -cdrom을 떼고 그 디스크만으로 뜬다. 그 다음 ISO로
# 다시 떠서 갱신하고(설정이 남는다), --wipe로 다시 설치한다(설정이 사라진다).
# 콘솔 셸에 시리얼 FIFO로 치는 유일한 체인이다 — 판정이 terminal 화면이 아니라
# tars-install이 찍는 목록이라서다(DI-M1 plan의 "정한 것" 6).
#
# 회차당 부팅 6회(전부 OVMF)라 총 부팅 횟수가 18회 는다.
```

- [ ] Step 2: 루트 게이트 (약 40분)

M1의 판이 35분 43초였다. 이 체인이 회차마다 부팅 넷(각 6~7초에 설치·갱신
시간)을 더하니 3회차로 1분 30초에서 3분이 는다. 10분이 Bash 도구의 한도라서
`run_in_background`로 돌린다.

```bash
time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh > /tmp/dim2-gate.log 2>&1; echo "exit=$?"
grep -E "PASS|FAIL" /tmp/dim2-gate.log | tail -16
grep -c FAIL /tmp/dim2-gate.log
```

기대: 체인 열셋이 전부 `PASS: 3/3`, 마지막에 `TARS check PASS`, `FAIL` 0.

- [ ] Step 3: README의 게이트 줄

`README.md`의 `# 전체 — 열한 체인 × 3회차, 약 26분`을 Step 2에서 잰 시각으로
바꾼다. 예: `# 전체 — 열세 체인 × 3회차, 약 38분`. 분은 반올림한다.

- [ ] Step 4: 커밋

```bash
git diff --stat
git add check.sh README.md
git commit -m "Name the install chain DI-M2 in the root gate"
```

## Task 7 — 적는다

Files: Modify design · `docs/decisions/project_disk_install.md` · `MEMORY.md` ·
`CLAUDE.md` · `HANDOFF.md`

- [ ] Step 1: design (`docs/superpowers/specs/2026-09-19-tars-disk-install-design.md`)

- `Status:` 줄을 `끝났다(2026-09-23). M0 · M1 · M2 — 실측 절 셋에 있다.`로 바꾼다.
- 확인 2의 끝에 한 문단을 붙인다. `⚠ DI-M2가 바꿨다. 설치기는 cmdline 줄 끝에
  tars.installed를 붙인다 — ISO로 뜬 부팅이 설치된 p2를 안 붙이게 하는 표지다(실측 17).`
- 결정 6의 끝에 한 문단을 붙인다. `⚠ DI-M2가 좁혔다. 파티션 후보는 cmdline에
  tars.installed가 있을 때만 본다(storage.candidates).`
- 결정 9의 끝에 한 문단을 붙인다. `⚠ DI-M2에서 부팅이 여섯이 됐다. 부팅 한 번이
  6~7초라 --wipe까지 둘을 더 들였다.`
- "DI-M1이 실행으로 증명한 것" 뒤에 "## DI-M2가 실행으로 증명한 것" 절을 새로
  넣는다. 실측 17부터 번호를 이어서, 이 plan의 커밋 목록, Task 4의 체인 시각과
  여섯 부팅의 콘솔 셸 시각, 부팅 3의 출력(이 plan 머리의 것과 같은지), 반사실 둘
  (plan을 쓰며 본 `in use`와 Task 4 Step 3의 판정 10), 루트 게이트 시각과 M1 판과의
  차이를 적는다. 숫자는 로그에서 그대로 옮긴다.

- [ ] Step 2: 기억

`docs/decisions/project_disk_install.md`에서 제목 줄을
`# 설치된 디스크 — ESP와 설정 파티션, 표지가 있을 때만 init이 파티션을 본다`로
바꾼다. How to apply의 첫 항목에서 "마흔둘" 문장 뒤에 `DI-M2부터는 cmdline에
tars.installed가 있을 때만이다 — 설치기가 ESP의 limine.conf에 붙이는 표지다. ISO로
뜬 부팅은 디스크 열넷만 본다.`를 더한다. 마지막 항목("설치된 기계에서는 … DI-M2")은
이렇게 바꾼다. `갱신은 p1만 쓰고 p2를 안 연다. --wipe는 ISO로 뜬 부팅에서만 되고,
그 부팅이 p2를 안 붙이는 것이 표지의 이유다(DI-M2 반사실: 붙이면 sfdisk가 in use).`

`MEMORY.md`의 Disk install 줄 끝의 `설치된 기계에서는 p2가 붙어 있어 재파티션이
막힌다(DI-M1, 2026-09-23)`를 `ISO 부팅은 표지 tars.installed가 없어 p2를 안 붙이고,
갱신은 설정을 남긴다(DI-M1·M2, 2026-09-23)`로 바꾼다.

- [ ] Step 3: `CLAUDE.md`의 완료 표에 한 줄

`| Terminal Queries (TQ-M1)|…` 줄 뒤에 붙인다.

```markdown
| Disk Install (DI-M0~M2) | 2026-09-23 | USB로 뜬 기계에서 `tars-install`이 내장 디스크에 ESP와 설정 파티션을 만들고 USB 없이 뜬다. 새 ISO로 갱신해도 설정이 남고 `--wipe`가 통째로 지운다. 열세번째 체인 `install/check.sh` |
```

- [ ] Step 4: HANDOFF

맨 위 절을 "DI가 M2로 닫혔다"로 새로 쓰고, 지금의 DI-M1 절은 그 아래로 내린다.
담을 것은 커밋 표, 판정(체인·반사실·루트 게이트 시각), 미룬 다섯("정한 것" 6)과
M1의 둘째 경고(파티션 노드의 틈) 이월이다. "바로 다음에 할 것"은 DI 뒤의 후보
목록으로 바꾼다(패키지 매니저 · 실머신 NIC · IN이 미룬 넷 · TS의 chrony). "명령
모음"의 DI-M1 줄은 부팅 여섯의 로그를 남기는 모양으로 고친다(`boot-*.log`는 그대로
맞는다).

- [ ] Step 5: 커밋

```bash
git diff --stat
git add docs/superpowers/specs/2026-09-19-tars-disk-install-design.md \
  docs/decisions/project_disk_install.md MEMORY.md CLAUDE.md HANDOFF.md
git commit -m "Close DI-M2: an update keeps the settings and --wipe drops them"
```
