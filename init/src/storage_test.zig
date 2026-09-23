const std = @import("std");
const storage = @import("storage.zig");

/// 이 검사가 보는 것은 규칙이고, 오프셋이 아니다.
///
/// 아래 상수 셋은 storage.zig가 적은 것과 같은 수다. 그래서 이 파일만으로는
/// 오프셋이 틀린 것을 원리적으로 못 잡는다 — 검사와 구현이 같은 수를 두
/// 번 적은 것이기 때문이다. 오프셋을 보는 것은 다른 둘이다.
///
///   Task 0        mkfs.ext2가 구운 이미지의 1080과 1144를 눈으로 봤다
///   machine 체인   NVMe 디스크에 라벨을 심고 init이 그것을 읽는지 본다
///
/// 그 분업을 알고 나면 이 파일이 무엇을 하는지가 분명하다 — 매직 검사와
/// 접두사 검사와 NUL 처리가 정말 있는가를 본다. 그 셋은 실물 이미지 하나로는
/// 안 갈린다.
const SB_OFFSET: usize = 1024;
const MAGIC_OFF: usize = 56;
const LABEL_OFF: usize = 120;

/// 검사마다 새로 채운다. 돌려준 슬라이스는 다음 호출에서 덮인다 —
/// 아래 검사들이 전부 만들자마자 바로 묻기 때문에 이것으로 충분하다.
/// devices_test의 path_buf와 같은 규칙이다.
var head: [storage.HEAD_BYTES]u8 = undefined;

/// 가짜 superblock 앞머리를 만든다. len을 따로 받는 이유는 검사 6이 짧은
/// 버퍼를 물어보기 때문이다.
fn fake(magic: u16, label: []const u8, len: usize) []const u8 {
    @memset(&head, 0);
    head[SB_OFFSET + MAGIC_OFF] = @truncate(magic);
    head[SB_OFFSET + MAGIC_OFF + 1] = @truncate(magic >> 8);
    @memcpy(head[SB_OFFSET + LABEL_OFF ..][0..label.len], label);
    return head[0..len];
}

fn full(magic: u16, label: []const u8) []const u8 {
    return fake(magic, label, storage.HEAD_BYTES);
}

const EXT2: u16 = 0xEF53;

pub fn main() !void {
    // ── 1. 대조군: 매직이 없다 ────────────────────────────────────────
    //
    // 빈 디스크와 GPT 디스크가 이 경로다. 노트북의 내장 NVMe를 디스크 전체로
    // 읽으면 protective MBR과 GPT 헤더가 나오고 1080에는 0xEF53이 없다 —
    // 그래서 남의 root 파티션을 /config로 잡을 길이 없다(design 결정 12).
    @memset(&head, 0);
    if (storage.tarsLabel(&head) != null) {
        std.debug.print("FAIL: a disk with no ext2 magic was accepted\n", .{});
        return error.NoMagicAccepted;
    }

    // ── 2. 정상 경로 ──────────────────────────────────────────────────
    {
        const got = storage.tarsLabel(full(EXT2, "tars-config")) orelse {
            std.debug.print("FAIL: a tars- labelled ext2 disk was rejected\n", .{});
            return error.GoodDiskRejected;
        };
        if (!std.mem.eql(u8, got, "tars-config")) {
            std.debug.print("FAIL: want label 'tars-config', got '{s}'\n", .{got});
            return error.WrongLabel;
        }
    }

    // ── 3. 이 묶음의 심장이다 — 남의 디스크 ────────────────────────
    //
    // 매직은 맞다. 진짜 ext2다. 다만 우리 것이 아니다. 접두사 검사를 통째로
    // 빼도 나머지 검사 여섯은 전부 통과하므로, 이 검사가 없으면 "순서로
    // 고르는 구현"과 "라벨로 고르는 구현"이 안 갈린다.
    //
    // 실기에서 이 경로가 막아 주는 것: whole-disk ext2로 포맷된 데이터 USB
    // 스틱을 /config로 잡아 그 루트에 tars.conf를 심는 일.
    if (storage.tarsLabel(full(EXT2, "debian-root")) != null) {
        std.debug.print("FAIL: someone else's ext2 disk was accepted as ours\n", .{});
        return error.ForeignDiskAccepted;
    }

    // ── 4. 회귀 대조군: 라벨이 빈 ext2 ────────────────────────────────
    //
    // RM-M1 시점의 machine/check.sh 디스크가 정확히 이것이다
    // (`mkfs.ext2 -q -F "$DISK"`, 라벨 없음). Task 3이 그 줄에 -L을 넣는데,
    // 넣기를 잊거나 나중에 지워도 이 경로가 "못 찾았다"로 떨어져야 한다.
    if (storage.tarsLabel(full(EXT2, "")) != null) {
        std.debug.print("FAIL: an unlabelled ext2 disk was accepted\n", .{});
        return error.UnlabelledAccepted;
    }

    // ── 5. 라벨이 16바이트를 꽉 채운 경우 ────────────────────────────
    //
    // s_volume_name은 char[16]이고 꽉 차면 NUL이 없다. 첫 NUL을 찾는
    // 코드가 그 경우를 안 다루면 라벨 뒤의 다른 필드까지 읽어서 슬라이스가
    // 넘친다.
    {
        const sixteen = "tars-0123456789A"; // 5 + 11 = 16
        if (sixteen.len != storage.LABEL_LEN) {
            std.debug.print("FAIL: this test's fixture is not {d} bytes\n", .{storage.LABEL_LEN});
            return error.BadFixture;
        }
        const got = storage.tarsLabel(full(EXT2, sixteen)) orelse {
            std.debug.print("FAIL: a full-width label was rejected\n", .{});
            return error.FullLabelRejected;
        };
        if (!std.mem.eql(u8, got, sixteen)) {
            std.debug.print("FAIL: want '{s}' ({d}B), got '{s}' ({d}B)\n", .{
                sixteen, sixteen.len, got, got.len,
            });
            return error.FullLabelTruncated;
        }
    }

    // ── 6. 짧은 읽기 ─────────────────────────────────────────────────
    //
    // 장치가 HEAD_BYTES보다 작으면 readHead가 덜 채워서 돌아온다. superblock
    // 자리에 닿지도 못한 버퍼에서 라벨을 읽으려 들면 슬라이스가 넘쳐 PID 1이
    // 죽는다 — 부팅이 안 되는 실패다.
    if (storage.tarsLabel(full(EXT2, "tars-config")[0..SB_OFFSET]) != null) {
        std.debug.print("FAIL: a buffer too short to hold a superblock was read anyway\n", .{});
        return error.ShortBufferAccepted;
    }

    // ── 7. 라벨만 맞고 매직이 틀린 경우 ──────────────────────────────
    //
    // 검사 1은 매직이 0이고 라벨도 없다. 그래서 매직 검사를 빼도 라벨
    // 검사가 대신 잡아 통과한다. 여기서는 라벨이 우리 것이므로 매직 검사만이
    // 이것을 거절할 수 있다.
    if (storage.tarsLabel(full(0xEF52, "tars-config")) != null) {
        std.debug.print("FAIL: a tars- label on a non-ext2 disk was accepted\n", .{});
        return error.WrongMagicAccepted;
    }

    // ── 8. ext2Label은 남의 라벨도 돌려준다 ─────────────────────────
    //
    // tars-install의 목록이 "foreign (ext2 debian-root)"를 찍으려면 접두사와
    // 무관하게 라벨을 읽어야 한다. 그리고 라벨이 빈 ext2는 null이 아니라 빈
    // 문자열이어야 "ext2가 아니다"와 갈린다(DI-M1).
    {
        const got = storage.ext2Label(full(EXT2, "debian-root")) orelse {
            std.debug.print("FAIL: ext2Label rejected an ext2 disk with a foreign label\n", .{});
            return error.ForeignLabelUnread;
        };
        if (!std.mem.eql(u8, got, "debian-root")) {
            std.debug.print("FAIL: want 'debian-root', got '{s}'\n", .{got});
            return error.WrongForeignLabel;
        }
        const empty = storage.ext2Label(full(EXT2, "")) orelse {
            std.debug.print("FAIL: an unlabelled ext2 disk read as not-ext2\n", .{});
            return error.EmptyLabelIsNull;
        };
        if (empty.len != 0) {
            std.debug.print("FAIL: want an empty label, got '{s}'\n", .{empty});
            return error.EmptyLabelNotEmpty;
        }
        @memset(&head, 0);
        if (storage.ext2Label(&head) != null) {
            std.debug.print("FAIL: ext2Label read a label off a disk with no magic\n", .{});
            return error.NoMagicLabelled;
        }
    }

    // ── 9. 파티션 이름 규칙 ───────────────────────────────────────────
    //
    // 이름이 숫자로 끝나는 디스크만 `p`가 든다. 넷 다 게스트에 실제로 있는
    // 모양이다 — nvme0n1p2가 틀리면 설치한 기계가 설정을 못 찾는다.
    {
        const cases = [_][3][]const u8{
            .{ "/dev/nvme0n1", "2", "/dev/nvme0n1p2" },
            .{ "/dev/mmcblk0", "1", "/dev/mmcblk0p1" },
            .{ "/dev/sda", "1", "/dev/sda1" },
            .{ "/dev/vdb", "2", "/dev/vdb2" },
        };
        for (cases) |c| {
            var buf: [32]u8 = undefined;
            const n = try std.fmt.parseInt(u8, c[1], 10);
            const got = storage.partitionName(&buf, c[0], n) orelse {
                std.debug.print("FAIL: partitionName({s}, {d}) returned null\n", .{ c[0], n });
                return error.PartitionNameNull;
            };
            if (!std.mem.eql(u8, got, c[2])) {
                std.debug.print("FAIL: partitionName({s}, {d}) = '{s}', want '{s}'\n", .{ c[0], n, got, c[2] });
                return error.WrongPartitionName;
            }
        }
    }

    // ── 10. 후보 목록 = 디스크 전부 → 그 다음 파티션 둘씩 ─────────────
    //
    // 손으로 적은 PARTITIONS가 규칙과 어긋나지 않는지, 그리고 디스크 전체가
    // 전부 파티션보다 앞인지 본다. 뒤의 것이 게이트 열두 체인의 판정을 지킨다
    // — 그 디스크들은 파티션 없는 ext2라 먼저 잡혀야 한다(DI design 결정 6).
    {
        const disks = storage.DISKS.len;
        if (storage.CANDIDATES.len != disks * 3) {
            std.debug.print("FAIL: want {d} candidates (disks + two partitions each), got {d}\n", .{
                disks * 3, storage.CANDIDATES.len,
            });
            return error.WrongCandidateCount;
        }
        for (storage.DISKS, 0..) |disk, i| {
            if (!std.mem.eql(u8, storage.CANDIDATES[i], disk)) {
                std.debug.print("FAIL: candidate {d} is '{s}', want the disk '{s}'\n", .{ i, storage.CANDIDATES[i], disk });
                return error.DiskNotFirst;
            }
            var n: u8 = 1;
            while (n <= 2) : (n += 1) {
                var buf: [32]u8 = undefined;
                const want = storage.partitionName(&buf, disk, n).?;
                const got = storage.CANDIDATES[disks + i * 2 + (n - 1)];
                if (!std.mem.eql(u8, got, want)) {
                    std.debug.print("FAIL: candidate {d} is '{s}', want '{s}'\n", .{ disks + i * 2 + (n - 1), got, want });
                    return error.PartitionListDrifted;
                }
            }
        }
    }

    // 후보 목록이 통째로 사라지지 않았는지만 본다. 무엇이 몇 번째인가는
    // 판정이 아니다(design 결정 13: 순서는 tars- 디스크가 둘 이상일 때만
    // 쓰인다) — 하지만 목록이 비면 부팅마다 설정이 사라지고 증상은 조용하다.
    if (storage.CANDIDATES.len == 0) {
        std.debug.print("FAIL: the candidate list is empty\n", .{});
        return error.NoCandidates;
    }

    std.debug.print(
        "storage_test: only a tars- labelled ext2 superblock counts ({d} candidates)\n",
        .{storage.CANDIDATES.len},
    );
}
