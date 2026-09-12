const std = @import("std");
const linux = std.os.linux;

/// main.zig·config.zig·devices.zig에도 같은 함수가 있다. devices.zig가 적어 둔
/// 그대로, 세 줄짜리 헬퍼 하나 때문에 공용 모듈을 만들지 않는다.
fn failed(rc: usize) ?linux.E {
    const e = linux.errno(rc);
    return if (e == .SUCCESS) null else e;
}

/// 디스크 앞머리에서 읽어 둘 바이트 수. ext2 superblock이 오프셋 1024에서
/// 시작해 1024바이트이므로 2048이면 통째로 든다.
///
/// lseek을 안 쓰는 것이 이 상수의 이유다. 오프셋 0에서 여기까지를 그냥
/// 읽으면 시스템 콜 하나가 줄고, Zig 0.16의 std.os.linux에 pread가 있는지를
/// 신경 쓸 필요도 없다.
pub const HEAD_BYTES: usize = 2048;

/// ext2/3/4 superblock의 자리와 그 안의 두 필드.
/// fs/ext4/ext4.h의 struct ext4_super_block와 같아야 한다.
///
/// 이 셋은 Task 0에서 실물로 확인했다. mkfs.ext2 -L tars-config로 구운
/// 이미지에서 디스크 오프셋 1080이 `53 ef`이고 1144가 `tars-config` +
/// NUL 패딩이다. 손으로 심은 버퍼만으로 검사를 쓰면 이 상수가 틀려도
/// 초록이 뜨기 때문에(검사와 구현이 같은 수를 두 번 적은 것이 된다) 실물을
/// 먼저 봤다.
const SB_OFFSET: usize = 1024;
const MAGIC_OFF: usize = 56; // s_magic
const LABEL_OFF: usize = 120; // s_volume_name

/// s_volume_name의 크기. mkfs가 이보다 긴 라벨을 주면 조용히 자른다 —
/// storage_test가 꽉 찬 경우를 따로 본다.
pub const LABEL_LEN: usize = 16;

const EXT2_MAGIC: u16 = 0xEF53;

/// 우리 디스크임을 말하는 표식. 라벨 전체를 못으로 박지 않고 접두사로 두는
/// 이유는 게이트 디스크 넷이 이미 tars-config·tars-input·tars-power·
/// tars-hangul이기 때문이다(design 결정 10). 정확히 하나로 박으면 그 넷의
/// 라벨을 전부 바꿔야 하고, 그것은 체인 넷을 건드리는 일이다.
pub const LABEL_PREFIX: []const u8 = "tars-";

/// 훑어볼 블록 장치 이름들. 파티션은 안 본다 — 지금 디스크 전체가 파티션
/// 테이블 없는 ext2 하나이고(CP design "1. virtio-blk + ext2"), 그 계약이 이
/// milestone에서 안 바뀐다(design 결정 12).
///
/// 부수 효과가 안전 쪽이다. 노트북의 내장 디스크는 예외 없이 GPT라 디스크
/// 전체를 읽으면 매직이 안 맞는다 — 그래서 남의 root 파티션을 `/config`로
/// 잡을 길이 아예 없다.
///
/// 순서가 판정을 바꾸는 상황은 `tars-` 라벨 디스크가 둘 이상일 때뿐이고,
/// 게이트에도 실기에도 그런 상황이 없다. 그래서 "흔한 것부터"가 아니라
/// "게이트가 매일 밟는 것부터"로 둔다 — 없는 장치를 여는 비용은
/// ENOENT 하나다.
///
/// 넷씩인 것은 devices.zig의 MAX_EVENT = 32와 같은 종류의 상한이다. 화면
/// 하나에 셸 하나인 기계에 저장장치가 다섯 개 붙을 이유가 없고, 상한을 크게
/// 잡으면 부팅마다 헛된 open이 는다.
pub const CANDIDATES = [_][:0]const u8{
    // virtio-blk. 게이트 다섯 체인이 이것이다.
    "/dev/vda",     "/dev/vdb",     "/dev/vdc", "/dev/vdd",
    // 요즘 노트북의 내장 저장장치. machine 체인이 이것이다.
    "/dev/nvme0n1", "/dev/nvme1n1", "/dev/nvme2n1", "/dev/nvme3n1",
    // SATA(AHCI) · USB 스토리지 · SD 리더가 전부 SCSI 디스크로 나온다.
    "/dev/sda",     "/dev/sdb",     "/dev/sdc", "/dev/sdd",
    // eMMC. 저가 노트북·태블릿의 내장 저장장치다.
    "/dev/mmcblk0", "/dev/mmcblk1",
};

/// 고른 디스크. 라벨을 슬라이스가 아니라 복사로 들고 있다 — 슬라이스로
/// 돌려주면 읽기 버퍼가 스택에서 사라진 뒤를 가리킨다. devices.Path가 경로에
/// 대해 이미 쓰는 처방이다.
pub const Found = struct {
    /// CANDIDATES의 원소를 그대로 가리킨다. 문자열 리터럴이라 수명이 무한하고,
    /// 그래서 execve의 argv에 넣는 것과 같은 성질이다.
    path: [:0]const u8 = "",
    label_buf: [LABEL_LEN]u8 = [_]u8{0} ** LABEL_LEN,
    label_len: usize = 0,

    pub fn label(self: *const Found) []const u8 {
        return self.label_buf[0..self.label_len];
    }
};

/// head는 디스크 앞 HEAD_BYTES. 라벨이 LABEL_PREFIX로 시작하면 그 라벨을,
/// 아니면 null. 돌려주는 슬라이스는 head 안을 가리킨다.
///
/// 순수 함수인 것에 뜻이 있다 — 시스템 콜이 없으므로 호스트 검사가 규칙을
/// 그대로 본다. devices.zig가 bitSet/looksLikeKeyboard(순수)와 findKeyboard
/// (콜)를 가른 것과 같은 선이다.
pub fn tarsLabel(head: []const u8) ?[]const u8 {
    // 라벨의 끝이 매직보다 뒤라서 이 하나로 둘을 다 덮는다. 짧은 읽기(장치가
    // HEAD_BYTES보다 작은 경우)에서 죽지 않는 자리다.
    if (head.len < SB_OFFSET + LABEL_OFF + LABEL_LEN) return null;

    const sb = head[SB_OFFSET..];

    // 매직이 GPT 디스크와 남의 파일시스템을 여기서 거른다. 리눅스는 이
    // 필드를 리틀엔디안으로 적으므로 방향을 명시한다 — x86_64에서는 네이티브와
    // 같지만, 그 사실에 기대면 왜 맞는지가 코드에 안 남는다.
    const magic = std.mem.readInt(u16, sb[MAGIC_OFF..][0..2], .little);
    if (magic != EXT2_MAGIC) return null;

    const raw = sb[LABEL_OFF..][0..LABEL_LEN];
    // 라벨은 NUL로 끝나지만 16바이트를 꽉 채우면 NUL이 없다. 그때는 전부가
    // 라벨이다.
    const end = std.mem.indexOfScalar(u8, raw, 0) orelse LABEL_LEN;
    const name = raw[0..end];

    if (!std.mem.startsWith(u8, name, LABEL_PREFIX)) return null;
    return name;
}

/// 장치 앞머리를 buf에 읽는다. 없는 장치는 ENOENT이고 그것이 정상 경로다 —
/// 후보 열넷 중 이 기계에 있는 것은 보통 하나다.
///
/// O_NONBLOCK으로 여는 이유가 devices.zig의 버튼 fd와 다르다. 여기서는
/// 매체가 없는 광학 드라이브나 빈 카드 리더에서 open(2)이 매달리는 것을
/// 막는다. PID 1이 부팅 중에 거기서 멈추면 기계가 안 켜진다 — 게이트가 못 보는
/// 실패이고, 그래서 미리 막는다(design 위험 8).
///
/// read(2)가 요청한 만큼을 다 준다는 보장이 없으므로 "돌아온 만큼 더한다".
/// devices.readFile과 같은 루프다.
fn readHead(path: [:0]const u8, buf: []u8) ?[]const u8 {
    const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY, .NONBLOCK = true }, 0);
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
        if (n == 0) break; // EOF. 장치가 HEAD_BYTES보다 작은 경우다.
        len += n;
    }
    return buf[0..len];
}

/// `tars-` 라벨을 가진 첫 후보를 out에 채우고 true. 하나도 없으면 false.
///
/// 마운트로 시험하지 않는다(design 결정 11). 열넷을 mount로 두드리면 실패
/// 줄이 열셋 찍히고, mount(2)는 파일시스템을 ext3/4로 잘못 잡았을 때 저널
/// 재생 같은 쓰기를 할 수 있다. 읽어서 거르면 남의 디스크를 건드릴
/// 가능성이 0이다.
pub fn findConfigDisk(out: *Found) bool {
    for (CANDIDATES) |path| {
        var buf: [HEAD_BYTES]u8 = undefined;
        const head = readHead(path, &buf) orelse continue;
        const name = tarsLabel(head) orelse continue;

        out.* = .{ .path = path, .label_len = name.len };
        @memcpy(out.label_buf[0..name.len], name);
        return true;
    }
    return false;
}
