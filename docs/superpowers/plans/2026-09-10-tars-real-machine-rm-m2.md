# RM-M2 Implementation Plan — 설정 저장소를 찾는다

> **실행 방식은 `CLAUDE.md`를 따른다.** 설명 먼저 → 파일 편집 → 명령 실행은
> Claude Code가 → 결과를 상세히 설명. 승인 뒤의 `git commit`도 Claude Code가
> 만든다. 체크박스는 진행 추적용이다.
>
> **이 milestone도 편집을 Claude Code가 한다** — RM-M0·M1의 예외와 같다.

**Goal:** `init`이 `/dev/vda` 하나를 하드코딩하는 대신 **후보 열넷을 훑어**
`tars-`로 시작하는 ext2 라벨을 가진 디스크를 찾는다. 열번째 체인이 그
디스크에서 `tars.conf`를 읽는다 — **NVMe에서**.

**Architecture:** `init/src/storage.zig`가 새로 생긴다. 하는 일은 둘이다 —
후보 경로를 순서대로 열어 앞 2048바이트를 읽고, ext2 superblock의 매직과
라벨을 본다. `mountFs`는 **한 글자도 안 고친다**(로그 문구를 다섯 체인이
마커로 갖고 있다).

**Tech Stack:** `init/src/storage.zig`(새) · `init/src/storage_test.zig`(새) ·
`init/build.zig` · `init/src/main.zig` · `machine/check.sh`

**RM에서 코드를 건드리는 유일한 milestone이다.** M0·M1·M3은 `.config`와 셸
스크립트뿐이다.

---

## 무엇이 막혀 있나

`init/src/main.zig:65` 한 줄이다.

```zig
return mountFs("/dev/vda", "/config", "ext2", linux.MS.SYNCHRONOUS);
```

`/dev/vda`는 **virtio-blk에만 있는 이름**이다. 노트북에는 virtio가 없다 —
`/dev/nvme0n1`이거나 `/dev/sda`다. 그래서 `machine/check.sh`는 RM-M1에서 이미
8MB ext2 디스크를 `-device nvme`로 물려 놓고도(`machine/check.sh:43-45`)
**마운트를 안 한다.** 커널이 `nvme nvme0: pci function`을 찍는 데까지가
그 milestone의 몫이었고, 그 위에 파일을 두고 읽는 것이 이 milestone이다.

**부팅은 지금도 된다.** 못 찾으면 `no config storage, using defaults`로
넘어간다(`main.zig:79`). 안 되는 것은 **설정이 부팅 사이에 남는 것**이다.

## 착수 전에 확인한 것 — **다시 조사하지 말 것**

**1. 후보 목록을 `tars.conf`에 둘 수 없다 — 순환이다.** 찾으려는 디스크
안에 그 파일이 있다. **결정 9가 이 사실 하나로 정해졌다.**

**2. 로그 문구 `tars-init: mounted ext2 at /config`를 지켜야 한다.**
`config/check.sh:206`과 `power/check.sh:85`가 마커로 갖고 있다. 그래서
`mountFs`를 고치지 않고 **그 앞에 고르는 단계**를 넣는다.

**3. 게이트 디스크 넷이 이미 `tars-` 라벨을 갖고 있다.** 우연이 아니다 —
CP-M0이 `-L`을 "나중에 dumpe2fs/blkid로 이게 뭐였는지 알아보기 위함"이라고
적으며 넣었고(`config/make_disk.sh:23`) 그 뒤 셋이 그것을 베꼈다.

| 만드는 곳 | 라벨 | 이 milestone이 건드리나 |
|---|---|---|
| `config/make_disk.sh:28` | `tars-config` | **아니다** |
| `input/make_disk.sh:37` | `tars-input` | **아니다** |
| `power/make_disk.sh:34` | `tars-power` | **아니다** |
| `hangul/make_disk.sh:52` | `tars-hangul` | **아니다** |
| `machine/check.sh:45` | **없다** | **그렇다.** 여기에 심는다 |

**design 결정 2("기존 아홉은 한 글자도 안 건드린다")를 이번에는 지킨다.**
RM-M0은 못 지켰는데(실측 6), 그것은 커널 설정이 옛 체인의 암묵적 전제를
깼기 때문이었다. 이번에는 넷이 이미 규칙을 만족한다.

**4. `mountFs`의 실패 줄은 여전히 나올 수 있다.** 라벨 맞는 디스크를 찾고도
mount가 실패하는 경로(파일시스템이 깨졌다)가 남으므로
`config/check.sh:207`의 마커가 죽은 줄이 되지 않는다. **그 파일을 안 고치는
근거다.**

## 착수 전에 실측할 것 — Task 0

**superblock 오프셋 셋을 실물로 확인한다.** 손으로 심은 버퍼만으로 검사를
쓰면 **오프셋이 틀려도 통과한다** — 검사와 구현이 같은 상수를 두 번 적은
것이기 때문이다. 그래서 `mkfs.ext2`가 실제로 구운 바이트를 먼저 본다.

---

## 결정

### 결정 9. 후보 목록은 `init`에 박는다 — **사용자가 골랐다**

`tars.conf`로 뺄 수 없다(위의 확인 1). 안 고른 둘:

- **커널 cmdline(`limine.conf`)으로 빼기** — `/proc/cmdline` 파서가 하나 늘고,
  실기에서 고치려면 ISO를 다시 구워야 한다. **훑기보다 나쁘다.**
- **`/sys/block`을 훑기** — `getdents64`를 직접 다뤄야 한다. `devices.zig`가
  그 길을 **일부러 피한 자리**이고 근거를 적어 뒀다: "init에 libc도 힙도
  없기 때문이다 — getdents64를 직접 다루는 것보다 open 서른두 번이 짧고
  예측 가능하다"(`devices.zig:16-18`).

**그래서 이 파일은 `devices.zig`와 같은 모양이 된다** — 이름을 순서대로 열어
보고, 안 되면 다음 것. 그 파일이 evdev에 대해 하는 일을 블록 장치에 대해
한다.

### 결정 10. 라벨이 `tars-`로 시작하는 첫 번째를 고른다 — **사용자가 골랐다**

HANDOFF가 "블록 장치에는 capability가 없다"고 적었는데, **ext2 라벨이 그
자리를 대신한다.** HD-M2의 "이름이 아니라 성질로"의 블록 장치 판이다 —
`/dev/vda`라는 **이름**이 아니라 디스크 안에 든 **표식**으로 고른다.

안 고른 둘:

- **마운트되는 첫 번째** — 코드가 가장 적다(mount 자체가 검사다). 대가 둘:
  (1) 실기에서 남의 whole-disk ext2(예: 데이터 USB 스틱)를 `/config`로 잡아
  **그 루트에 `tars.conf`를 심을 수 있다.** (2) 후보마다 mount를 시도하므로
  `failed to mount ext2 at /config`가 열넷까지 찍힌다.
- **라벨이 정확히 `tars-config`인 것** — 가장 엄격하지만 게이트 디스크 넷의
  라벨을 전부 바꿔야 한다. **체인 넷을 건드린다**(design 결정 2가 막으려던
  것과 같은 종류의 위험).

**접두사 규칙의 값은 "기존 넷을 안 건드리고도 판정이 진짜가 되는 것"이다.**

### 결정 11. 마운트는 **한 번만** 시도한다 — Claude가 정했다

후보를 mount로 시험하지 않고 **superblock을 직접 읽어** 거른다. 근거 셋.

1. **로그가 안 시끄러워진다.** 열넷을 mount로 시험하면 실패 줄이 열셋이다.
2. **`mountFs`의 계약이 안 바뀐다.** 그 함수가 찍는 줄은 여전히 "우리가 쓰기로
   정한 디스크 하나"에 대한 것이다.
3. **읽기가 쓰기보다 안전하다.** mount(2)는 저널 재생 같은 쓰기를 할 수
   있다(ext3/4로 잘못 잡힌 경우). 남의 디스크를 건드릴 가능성을 0으로 만든다.

### 결정 12. 후보는 **디스크 전체**만 본다 — Claude가 정했다

`/dev/nvme0n1p1` 같은 파티션은 안 본다. design 비목표가 이미 정한 것이다 —
**"RM-M2는 장치 이름만 넓히고 파티션은 건드리지 않는다."** 지금 디스크 전체가
파티션 없는 ext2이고(CP design "1. virtio-blk + ext2"), 그 계약이 이
milestone에서 안 바뀐다.

**부수 효과가 안전 쪽이다** — 노트북의 내장 디스크는 예외 없이 GPT라 디스크
전체를 읽으면 매직이 안 맞고, 그래서 **남의 root 파티션을 잡을 길이 없다.**

### 결정 13. 후보 열넷과 그 순서 — Claude가 정했다

```
/dev/vda  vdb  vdc  vdd          ← virtio-blk. 게이트 다섯 체인이 이것이다
/dev/nvme0n1 … nvme3n1           ← 요즘 노트북의 내장 저장장치
/dev/sda  sdb  sdc  sdd          ← SATA(AHCI) · USB 스토리지 · SD 리더
/dev/mmcblk0  mmcblk1            ← eMMC. 저가 노트북·태블릿의 내장 저장장치
```

**순서가 판정을 바꾸는 상황은 `tars-` 라벨 디스크가 둘 이상일 때뿐이고,
게이트에도 실기에도 그런 상황이 없다.** 그래서 순서는 "흔한 것부터"가 아니라
**"게이트가 매일 밟는 것부터"**로 둔다 — 없는 장치를 여는 비용은 `ENOENT`
하나다.

**넷씩인 이유.** `devices.zig`의 `MAX_EVENT = 32`와 같은 종류의 상한이다.
화면 하나에 셸 하나인 기계에 저장장치가 다섯 개 붙을 이유가 없고, 상한을
크게 잡으면 부팅 때마다 헛된 open이 는다.

---

## Task 0 — superblock 오프셋을 실물로 확인한다

**왜 이것이 먼저인가.** 손으로 심은 버퍼로 검사를 쓰면 **오프셋이 틀려도
초록이 뜬다.** 검사가 구현과 같은 상수를 두 번 적은 것이기 때문이다.
`mkfs.ext2`가 구운 진짜 바이트를 먼저 본다.

**확인할 것 셋** (ext2 superblock은 디스크 오프셋 1024에서 시작한다):

| 무엇 | superblock 안 | 디스크 오프셋 | 기대값 |
|---|---|---|---|
| `s_magic` (u16 LE) | 56 | **1080** | `53 EF` |
| `s_volume_name` (16바이트) | 120 | **1144** | `tars-config` + NUL 패딩 |

```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
  IMG=$(mktemp)
  dd if=/dev/zero of="$IMG" bs=1M count=8 status=none
  mkfs.ext2 -F -q -m 0 -L tars-config "$IMG"
  echo "--- 1080: magic (want 53 ef) ---"
  xxd -s 1080 -l 2 "$IMG"
  echo "--- 1144: label (want tars-config) ---"
  xxd -s 1144 -l 16 "$IMG"
  rm -f "$IMG"'
```

**여기서 값이 다르면 Task 1의 상수를 고치고 나서 간다.** 이 스파이크는 초
단위이고 게이트는 18분이다.

- [ ] Task 0 완료 — 오프셋 셋이 실측으로 확인됐다

---

## Task 1 — `storage.zig`와 그 검사 (호스트에서 초 단위)

**넣을 것:** `init/src/storage.zig`(새) · `init/src/storage_test.zig`(새) ·
`init/build.zig`에 배선 한 벌.

### `storage.zig`의 모양

**순수 함수 하나와 시스템 콜 하는 함수 하나로 가른다.** `devices.zig`가
`bitSet`/`looksLikeKeyboard`(순수)와 `findKeyboard`/`openPowerButtons`(콜)를
가른 것과 같은 선이다 — 순수한 쪽만 호스트 검사가 본다.

```zig
/// 디스크 앞머리에서 읽어 둘 바이트 수. superblock이 1024에서 시작해
/// 1024바이트이므로 2048이면 통째로 든다.
pub const HEAD_BYTES: usize = 2048;

const SB_OFFSET: usize = 1024;   // ext2 superblock의 자리
const MAGIC_OFF: usize = 56;     // s_magic
const LABEL_OFF: usize = 120;    // s_volume_name
const LABEL_LEN: usize = 16;
const EXT2_MAGIC: u16 = 0xEF53;

/// 우리 디스크임을 말하는 표식. 라벨 전체를 못으로 박지 않고 접두사로
/// 두는 이유는 게이트 디스크 넷이 이미 tars-config·tars-input·tars-power·
/// tars-hangul이기 때문이다(결정 10).
pub const LABEL_PREFIX: []const u8 = "tars-";

/// head는 디스크 앞 HEAD_BYTES. 라벨이 LABEL_PREFIX로 시작하면 그 라벨을,
/// 아니면 null. **돌려주는 슬라이스는 head 안을 가리킨다.**
pub fn tarsLabel(head: []const u8) ?[]const u8
```

`tarsLabel`이 하는 일 넷.

1. `head.len < SB_OFFSET + SB 끝`이면 null (짧은 읽기에서 안 죽는다)
2. 매직이 `0xEF53`이 아니면 null (**GPT 디스크도 남의 fs도 여기서 걸린다**)
3. 라벨 16바이트에서 첫 NUL까지를 자른다 (NUL 없이 꽉 차면 16바이트 전부)
4. `LABEL_PREFIX`로 시작하지 않으면 null

### 시스템 콜 쪽

```zig
pub const Found = struct {
    path: [:0]const u8,
    label_buf: [LABEL_LEN]u8,
    label_len: usize,
    pub fn label(self: *const Found) []const u8;
};

pub const CANDIDATES = [_][:0]const u8{ ... 열넷 ... };

/// 후보를 순서대로 열어 앞머리를 읽고 tarsLabel에 묻는다.
pub fn findConfigDisk(out: *Found) bool
```

**라벨을 `Found`에 복사한다.** 슬라이스로 돌려주면 읽기 버퍼가 스택에서
사라진 뒤를 가리킨다 — `devices.Path`가 경로에 대해 이미 쓰는 처방이다.

**`O_NONBLOCK`으로 연다.** `devices.zig`가 버튼 fd에 쓰는 것과 이유가 다르다 —
여기서는 **매체가 없는 광학 드라이브나 카드 리더에서 open이 매달리는 것**을
막는다. PID 1이 부팅 중에 거기서 멈추면 기계가 안 켜진다.

**`lseek`을 안 쓴다.** 오프셋 0에서 `HEAD_BYTES`를 그냥 읽는다 — `read(2)`가
요청한 만큼을 다 준다는 보장이 없으므로 `devices.readFile`과 같은 "돌아온
만큼 더한다" 루프다. 시스템 콜 하나가 줄고 `pread` 유무를 신경 쓸 필요가
없다.

### `storage_test.zig`가 보는 것 여섯

**전부 순수 함수 `tarsLabel`에 대한 것이다.** 디스크도 mkfs도 안 부른다 —
오프셋이 맞는지는 이 검사가 원리적으로 못 보고(Task 0과 Task 3이 본다),
**여기서 보는 것은 규칙이다.**

| # | 입력 | 기대 | 왜 |
|---|---|---|---|
| 1 | 전부 0 | `null` | **대조군.** 매직이 없다 = 빈 디스크·GPT 디스크 |
| 2 | 매직 + `tars-config` | `"tars-config"` | 정상 경로 |
| 3 | 매직 + `debian-root` | `null` | **남의 디스크다.** 이것이 없으면 접두사 검사가 있으나 없으나 통과한다 |
| 4 | 매직 + 빈 라벨 | `null` | **RM-M1 시점의 `machine/check.sh` 디스크가 정확히 이것이다** — 회귀 대조군 |
| 5 | 매직 + 16바이트 꽉 찬 라벨 | 그 16바이트 | NUL 없이 끝나도 안 넘친다 |
| 6 | 1024바이트짜리 짧은 버퍼 | `null` | 짧은 읽기에서 안 죽는다 |
| 7 | 매직만 틀림(`0xEF52`) + `tars-x` | `null` | 라벨만 보고 통과하지 않는다 |

**검사 3이 이 검사 묶음의 심장이다.** 나머지 여섯은 접두사 검사를 통째로
빼도 통과한다.

### `build.zig` 배선

`devices_test`가 있는 자리에 `storage_test`를 같은 모양으로 더한다.
`test_step.dependOn`에 한 줄.

```bash
docker run --rm -v "$PWD":/workspace -w /workspace/init tars-devcontainer \
  bash -c 'zig build test'
```

**기대하는 첫 실패는 컴파일 에러다** — `storage_test.zig`가 없는 함수를
부른다. SH-M0 실측 2가 적은 그 갈림이다.

- [ ] Task 1 완료 — `zig build test`가 넷 다 통과한다

---

## Task 2 — `mountConfig`가 후보를 훑는다

**지울 것** (`init/src/main.zig:52-66`, 주석 포함):

```zig
/// 설정 저장소를 붙인다. initramfs는 tmpfs라 전원이 꺼지면 통째로 사라진다 —
/// 재부팅을 넘어 살아남는 것은 이 virtio-blk 디스크(/dev/vda) 하나뿐이다.
/// 파티션 테이블 없이 디스크 전체가 ext2라서 /dev/vda1이 아니라 /dev/vda다.
...
fn mountConfig() bool {
    return mountFs("/dev/vda", "/config", "ext2", linux.MS.SYNCHRONOUS);
}
```

**넣을 것:** 같은 자리에, 주석의 `MS_SYNCHRONOUS` 문단과 "디스크가 없는
부팅도 정상 경로다" 문단은 **그대로 살린다**(둘 다 여전히 참이다). 바뀌는
것은 첫 문단(어느 디스크인가)과 본체다.

```zig
fn mountConfig() bool {
    var found: storage.Found = undefined;
    if (!storage.findConfigDisk(&found)) {
        std.debug.print(
            "tars-init: no disk labelled {s}* among {d} candidates\n",
            .{ storage.LABEL_PREFIX, storage.CANDIDATES.len },
        );
        return false;
    }
    // 이 줄이 RM-M2의 판정이다. "어느 이름을 골랐는가"와 "왜 그것인가"가
    // 한 줄에 함께 있어야 실패했을 때 넷이 갈린다(IS-M1 실측 5).
    std.debug.print("tars-init: config storage {s} (label {s})\n", .{
        found.path, found.label(),
    });
    return mountFs(found.path, "/config", "ext2", linux.MS.SYNCHRONOUS);
}
```

**`mountFs`는 한 글자도 안 고친다.** 다섯 체인이 그 줄을 마커로 갖고 있다.

**로그 한 줄이 바뀌는 자리가 있다.** 디스크 없는 부팅(BF·TF 체인)에서
여태 `failed to mount ext2 at /config (errno 2)`가 찍히던 자리에 이제
`no disk labelled tars-* among 14 candidates`가 찍힌다. **아무 체인도 그
줄을 판정에 안 쓴다**(확인 2·4). `config/check.sh:207`의 마커는 죽지
않는다 — 라벨을 찾고도 mount가 실패하는 경로가 남는다.

- [ ] Task 2 완료 — `zig build`가 통과하고 `init` 바이너리가 나온다

---

## Task 3 — 체인이 NVMe에서 `tars.conf`를 읽는다

**넣을 것:** `machine/check.sh`. 지울 것은 디스크를 굽는 세 줄
(`machine/check.sh:39-45`의 주석 포함)이다.

### 디스크를 굽는 자리

```bash
# RM-M2: NVMe로 물릴 설정 디스크. RM-M1까지는 라벨도 내용도 없는 빈 ext2였고
# init이 /dev/vda를 하드코딩해서 마운트조차 못 했다. 이제 둘 다 심는다.
#
# **라벨이 이 체인의 판정 근거다**(design 결정 10). init은 /dev/nvme0n1이라는
# **이름**이 아니라 디스크 안의 이 표식을 보고 고른다 — HD-M2가 키보드에
# 대해 세운 "이름이 아니라 성질로"의 블록 장치 판이다.
#
# **심는 값이 기본값과 달라야 한다**(hangul/make_disk.sh가 세운 규칙).
# hangul_layout의 기본값은 shin_pcs이고 여기 심는 것은 sebeol_3p3다 — 같은
# 값을 심으면 설정 파일을 통째로 무시하는 코드도 초록이 뜬다.
#
# **shell을 안 건드리는 이유가 있다.** 이 체인의 첫 판정이
# `Welcome to fish`라서 shell=bash를 심으면 그 줄이 사라진다. latin_layout도
# 마찬가지다 — 아래에서 'usb'를 쳐야 하므로 dvorak을 심으면 글자가 갈린다.
# **기본값과 다르면서 나머지 판정을 안 흔드는 키는 hangul_layout 하나다.**
DISK="$(mktemp)"
SEED="$(mktemp -d)"
cat > "$SEED/tars.conf" <<'EOF'
# machine 체인이 NVMe 디스크에 미리 심어 두는 설정.
hangul_layout=sebeol_3p3
EOF
dd if=/dev/zero of="$DISK" bs=1M count=8 status=none
mkfs.ext2 -F -q -m 0 -L tars-machine -d "$SEED" "$DISK"
rm -rf "$SEED"
```

### 판정 셋을 더한다 (판정 7 뒤, 타이핑 앞)

**하나만 보면 "안 됐다"의 이유가 안 갈린다** — RM-M0 plan이 판정 셋을
나눈 것과 같은 이유다.

| 보는 것 | 없으면 무엇이 틀렸나 |
|---|---|
| `tars-init: config storage /dev/nvme0n1 (label tars-machine)` | **이 milestone의 심장.** 후보 훑기가 NVMe까지 못 갔거나 라벨을 못 읽었다 |
| `tars-init: mounted ext2 at /config` | 골랐는데 mount가 실패했다 — 라벨은 맞고 파일시스템이 틀렸다 |
| `tars-init: loaded /config/tars.conf` | 마운트는 됐는데 파일이 없다. `-d`가 안 먹었다 |
| `hangul=sebeol_3p3` (config 줄 안) | 읽었는데 **값이 안 쓰였다.** 설정을 무시하는 코드가 여기서 걸린다 |

```bash
# 판정 8. **이 milestone의 심장이다.** init이 /dev/vda가 아니라 NVMe를
# 골랐고, 고른 근거가 이름이 아니라 라벨이라는 것이 한 줄에 다 있다.
WANT_DISK="tars-init: config storage /dev/nvme0n1 (label tars-machine)"
if ! grep -aqF "$WANT_DISK" "$LOG"; then
  fail "init did not pick the NVMe disk by its label" \
    "tars-init: config storage" "tars-init: no disk labelled" "nvme"
fi
echo "init found the config disk on NVMe by its ext2 label"

# 판정 9. 골랐다는 것과 붙었다는 것이 다르다.
if ! grep -aq "tars-init: mounted ext2 at /config" "$LOG"; then
  fail "the labelled disk was picked but never mounted" \
    "tars-init: config storage" "tars-init: failed to mount"
fi

# 판정 10. 붙었다는 것과 읽었다는 것이 또 다르다.
if ! grep -aq "tars-init: loaded /config/tars.conf" "$LOG"; then
  fail "the config disk mounted but tars.conf was not read" \
    "tars-init: created /config" "tars-init: loaded /config"
fi

# 판정 11. **읽었다는 것과 값이 쓰였다는 것이 또 다르다.** 기본값은
# shin_pcs이므로 이 줄이 설정 파일이 실제로 동작이 됐음을 말한다.
if ! grep -a "tars-init: config " "$LOG" | grep -aq "hangul=sebeol_3p3"; then
  fail "the seeded hangul_layout never reached the config line" \
    "tars-init: config " "tars-init: loaded /config"
fi
echo "the value seeded on the NVMe disk became the running configuration"
```

**RM-M1이 남긴 주석 둘을 함께 고친다** — `machine/check.sh:40`과 `:207-208`이
"init이 /dev/vda를 하드코딩하고 있어서 못 읽는다. RM-M2가 그것을 넓힌다"고
적어 뒀다. **그 문장이 이 Task에서 낡는다.**

- [ ] Task 3 완료 — `./machine/check.sh`가 컨테이너 안에서 `PASS`

---

## Task 4 — 음성 확인과 게이트

### 음성 확인 — **라벨이 진짜 판정 근거인가**

라벨만 빼고 굽는다(`-L tars-machine`을 지운다). 나머지는 전부 그대로 —
디스크도 NVMe도 `tars.conf`도 그 자리에 있다.

```bash
FAIL: init did not pick the NVMe disk by its label
  tars-init: no disk labelled tars-* among 14 candidates
```

**이 실패가 안 나면 판정이 가짜다.** RM-M1의 `i8042=off` 음성 확인(실측 12)과
같은 종류다 — 위층을 확인하려면 아래층을 먼저 꺼야 한다. 여기서 아래층은
"라벨"이고, 그것 없이도 초록이 뜬다면 코드가 순서로 고르고 있다는 뜻이다.

**둘째 음성 확인(선택).** 후보 목록에서 nvme 넷을 빼면 같은 실패가 나와야
한다 — 목록이 진짜 쓰인다는 증거다. Task 1의 검사가 규칙을 보고 이것이
목록을 보므로 둘이 안 겹친다.

### 게이트 3/3

**열 체인 3/3이고 20분이 넘는다 — 백그라운드로 돌린다.** Bash 도구의
타임아웃 상한이 10분이라 넘겨 주면 잘려서 exit 143이 된다.

```bash
{ time docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer \
  bash check.sh ; } 2> /tmp/gate.time
```

**게이트가 이 milestone에 대해 보는 것은 판정 넷만이 아니다.** 다섯 체인
(`config` · `input` · `power` · `hangul`, 그리고 디스크 없는 `boot`·`terminal`)이
`/dev/vda`와 "디스크 없음" 경로를 계속 지난다 — **후보 훑기가 옛 경로를
깨지 않았음을 그 다섯이 증명한다.** 이것이 이 Task에서 게이트를 도는 진짜
이유다.

**기준선은 20분 23.41초다**(RM-M1 뒤, 실측 13). 커널이 안 바뀌므로
빌드 시간은 그대로이고, 느는 것은 `machine` 체인의 `mkfs.ext2 -d` 한 번과
판정 넷의 `grep`뿐이다 — 3회 돌아도 초 단위다.

- [ ] Task 4 완료 — 음성 확인 exit 1 확인 + 게이트 3/3 초록

---

## 위험

**위험 6. 오프셋 상수가 틀리면 조용히 실패한다.** 매직을 엉뚱한 자리에서
읽으면 모든 후보가 `null`이 되고 증상은 "설정이 안 남는다"뿐이다.
**처방이 Task 0이다** — 게이트 18분 전에 초 단위로 실물을 본다.

**위험 7. `mkfs.ext2`의 라벨이 16바이트를 넘으면 잘린다.** `tars-machine`은
12바이트라 여유가 있다. **넘겼을 때 조용히 잘리는 것**이 위험이므로 Task 1
검사 5가 그 경계를 본다.

**위험 8. `/dev/sda`가 매체 없는 리더일 때 open이 매달린다.** 실기에서만
나타나고 게이트가 못 본다. **처방이 `O_NONBLOCK`이고 결정 13에 적었다.**
게이트가 못 보는 자리에서는 넓게 켠다는 이 서브프로젝트의 기울기와 같은
방향이다.

**위험 9. 실기에서 `tars-` 디스크가 둘일 수 있다.** 예전 TARS USB를 꽂은 채
새것으로 부팅하면 둘이 보인다. 그때 순서가 정한다(결정 13) — **조용히
엉뚱한 것을 고를 수 있다.** 그래서 `config storage` 줄이 고른 이름과 라벨을
둘 다 찍는다. **실기에서 사람이 그 줄을 읽고 알 수 있게 하는 것이 지금
할 수 있는 전부다.**

---

## 커밋 계획

| | 무엇 |
|---|---|
| 1 | plan (이 파일) |
| 2 | Task 1 — `storage.zig` · `storage_test.zig` · `build.zig` |
| 3 | Task 2 — `mountConfig`가 후보를 훑는다 |
| 4 | Task 3 — `machine/check.sh`의 디스크와 판정 넷 |
| 5 | Task 4 뒤 — design의 실측 절 · HANDOFF · `MEMORY.md` |

**design과 plan을 코드보다 먼저 커밋한다** — GL-M2·M3이 세운 순서다.
**push는 신경 쓰지 않는다**(`feedback_push_policy`).
