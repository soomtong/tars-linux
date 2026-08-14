# TARS Config Persistence CP-M0 Implementation Plan

> **이 저장소는 pairing 방식 고정(`CLAUDE.md`, `HANDOFF.md`):** 파일 작성과
> 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을 제시하고
> 결과를 해석한다. 다른 저장소용 SUB-SKILL 문구는 이 저장소에 적용하지 않는다.

**Goal:** TARS에 **재부팅을 넘어 살아남는 저장 공간**을 처음으로 붙인다.
virtio-blk 디스크 하나를 만들어 QEMU에 물리고, 커널이 `/dev/vda`로 보게 하고,
PID 1이 그것을 `/config`에 마운트한다. 아직 설정 파일은 없다 — **디스크가
보이고 마운트된다**까지가 이 milestone이다.

**Design doc:** `docs/superpowers/specs/2026-08-14-tars-config-persistence-design.md`

**Tech Stack:** 리눅스 커널 6.18.42 config(`CONFIG_BLK_DEV`/`VIRTIO_BLK`/
`EXT2_FS`), `e2fsprogs`(`mkfs.ext2`), Zig 0.16.0(`std.os.linux.mount`), bash,
Docker(`tars-devcontainer`, arm64), QEMU

---

## 왜 이 순서인가

이 milestone은 아래에서 위로 쌓는다. 각 단계가 다음 단계의 전제가 되고,
**어디서 막혔는지가 곧 무엇을 모르는지**를 알려준다.

```
QEMU        -drive file=out/config.img,if=virtio   ← Task 3, 5
  ↓
커널        virtio_blk 드라이버 → /dev/vda          ← Task 1
  ↓
devtmpfs    /dev/vda 노드 생성                       (이미 있음: init이 마운트)
  ↓
PID 1       mount("/dev/vda", "/config", "ext2", MS_SYNCHRONOUS)  ← Task 4
  ↓
게이트      "tars-init: mounted ext2 at /config"    ← Task 5
```

**디스크가 없는 부팅도 정상 경로다.** BF 체인은 ISO 부팅이라 `-drive`가 없고,
TF 체인도 이번에 건드리지 않는다. 두 체인에서는 마운트가 실패하고 로그 한
줄만 남아야 하며, **PASS는 그대로 나야 한다.** 설정 저장소가 없다고 부팅이
막히면 그건 이 설계의 실패다(design doc "5. 설정 하나로 부팅이 막히지 않게
하는 세 장치").

---

## 사전 준비

모든 명령은 저장소 루트(`/Users/dp/Repository/tars-linux`)에서 실행한다.
`main` 브랜치, working tree 깨끗한 상태에서 시작한다.

**`docker run`/`docker build`에 `--platform`을 붙이지 않는다.** 붙이면 ZM-M3에서
없앤 에뮬레이션 층이 그대로 돌아온다
(`docs/decisions/project_build_host_arch.md`).

---

## Task 1: 커널이 디스크를 볼 수 있게 한다

**Files:**
- Modify: `kernel/.config` (3곳)

지금 `.config` 상태를 먼저 확인해 두자. 이 셋이 이 Task가 바꾸는 전부다.

| 줄 | 현재 | 바꿀 값 |
|---|---|---|
| 869 | `# CONFIG_BLK_DEV is not set` | `CONFIG_BLK_DEV=y` |
| (869 다음 줄에 추가) | — | `CONFIG_VIRTIO_BLK=y` |
| 1598 | `# CONFIG_EXT2_FS is not set` | `CONFIG_EXT2_FS=y` |

**`CONFIG_BLK_DEV`이 왜 먼저인가.** 이건 개별 드라이버가 아니라
`drivers/block/Kconfig`의 `menuconfig` 항목이다 — 꺼져 있으면 그 안의 모든
드라이버가 **선택지 목록에 나타나지도 않는다.** 그래서 지금 `.config`에
`CONFIG_VIRTIO_BLK` 줄이 아예 없는 것이다(`# ... is not set`조차 없다). 반면
virtio 버스 자체(`CONFIG_VIRTIO`, `CONFIG_VIRTIO_PCI`)는 DF에서 GPU 때문에
이미 `y`라서 그 위에 얹히기만 한다.

- [ ] **Step 1: `kernel/.config` 편집**

869번째 줄:

```
# CONFIG_BLK_DEV is not set
```

를 두 줄로 바꾼다:

```
CONFIG_BLK_DEV=y
CONFIG_VIRTIO_BLK=y
```

그리고 1598번째 줄(한 줄 늘었으니 실제로는 1599번째):

```
# CONFIG_EXT2_FS is not set
```

를

```
CONFIG_EXT2_FS=y
```

로 바꾼다.

줄 번호로 찾는 것이 불안하면 문자열로 찾아도 된다 — 셋 다 파일 안에서
유일하다.

- [ ] **Step 2: 커널 빌드**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash kernel/build.sh 2>&1 | tail -20
```

Expected: 마지막에 `Kernel: arch/x86/boot/bzImage is ready`. ZM-M3 기준
clean이 아닌 증분 빌드이므로 30초 안팎.

`build.sh:21`이 `kernel/.config`를 `build/.config`로 복사한 뒤
`make olddefconfig`을 돌린다. **`olddefconfig`은 새로 보이게 된 심볼들을
기본값으로 채우므로, 우리가 쓴 세 줄 말고도 여러 줄이 `build/.config`에
생긴다.** 그래서 다음 Step이 필요하다.

- [ ] **Step 3: 실제로 무엇이 켜졌는지 확인**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c \
  'grep -E "^CONFIG_(BLK_DEV|VIRTIO_BLK|EXT2_FS)" kernel/build/.config'
```

Expected: 정확히 이 셋(순서는 다를 수 있다).

```
CONFIG_BLK_DEV=y
CONFIG_VIRTIO_BLK=y
CONFIG_EXT2_FS=y
```

셋 중 하나라도 없으면 **거기서 멈추고 알릴 것.** 특히 `CONFIG_VIRTIO_BLK`이
없다면 `CONFIG_BLK_DEV` 편집이 반영되지 않았거나 의존 심볼이 하나 더 있다는
뜻이고, 그대로 진행하면 Task 5에서 "왜 `/dev/vda`가 없지"로 나타난다.

- [ ] **Step 4: Commit**

Claude가 수행한다. 사용자는 Step 3 출력만 전달하면 된다.

---

## Task 2: 컨테이너에 `mkfs.ext2`를 넣는다

**Files:**
- Modify: `devcontainer/Dockerfile:8-28`

디스크 이미지를 굽는 것은 **호스트(컨테이너) 쪽 도구**다. `mkfs.ext2`는
`e2fsprogs`가 준다. `debian:trixie-slim`에 들어 있을 수도 있지만 **있는지에
의존하지 않는다** — 명시적으로 설치한다. `make_initrd.sh`가 sysroot 패키지를
명시적으로 나열하는 것과 같은 이유다(빠지면 조용히 통과하는 대신 즉시
죽어야 한다).

`e2fsprogs`는 게스트에 들어가는 것이 아니라 **컨테이너에서 실행되는 도구**이므로
amd64 sysroot가 아니라 위쪽 `apt-get install` 목록에 들어간다
(`project_build_host_arch`의 "이 산출물은 누가 실행하는가" 질문 — 여기서는
arm64 컨테이너가 실행한다).

- [ ] **Step 1: `Dockerfile`의 apt 목록에 한 줄 추가**

`devcontainer/Dockerfile:27`의 `unzip \` 다음, `&& rm -rf ...` 앞에 넣는다.

바꾸기 전(26~28번째 줄):

```dockerfile
        xz-utils \
        unzip \
    && rm -rf /var/lib/apt/lists/*
```

바꾼 뒤:

```dockerfile
        xz-utils \
        unzip \
        e2fsprogs \
    && rm -rf /var/lib/apt/lists/*
```

- [ ] **Step 2: 이미지 재빌드**

Run:
```bash
docker build -t tars-devcontainer -f devcontainer/Dockerfile . 2>&1 | tail -20
```

Expected: 마지막에 `naming to docker.io/library/tars-devcontainer`.

**첫 `RUN` 레이어를 건드렸으므로 그 아래 레이어가 전부 무효화된다** — amd64
sysroot의 `apt-get download`와 Zig tarball 내려받기가 다시 돈다. 즉 **이
Step은 네트워크가 필요하고 몇 분 걸린다.** (게이트 실행 자체는 여전히
오프라인이다 — 네트워크를 쓰는 것은 이미지 빌드 때뿐이라는 원칙은 그대로다.)

- [ ] **Step 3: `mkfs.ext2`가 있는지 확인**

Run:
```bash
docker run --rm tars-devcontainer bash -c 'mkfs.ext2 -V; uname -m'
```

Expected: `mke2fs 1.47.x` 류의 버전 두 줄과 `aarch64`.

`aarch64`가 아니면 `--platform`이 어딘가에 끼어든 것이다 — 즉시 알릴 것.

- [ ] **Step 4: Commit**

Claude가 수행한다.

---

## Task 3: 디스크 이미지를 굽는 스크립트

**Files:**
- Create: `config/make_disk.sh`

- [ ] **Step 1: `config/` 디렉터리와 스크립트 생성**

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# 설정 저장소용 디스크. 16MB면 텍스트 설정 파일 수십 개에 과분하다 —
# 크기를 키울 이유가 생기면 그때 늘린다(이미지는 매번 새로 굽는다).
SIZE=16M
IMG=../out/config.img

mkdir -p ../out
rm -f "$IMG"

# truncate가 만드는 것은 sparse 파일이다. 16MB를 선언하지만 실제로 디스크를
# 차지하는 것은 쓴 만큼뿐이다. QEMU에게는 그냥 16MB 블록 장치로 보인다.
truncate -s "$SIZE" "$IMG"

# -F  : 블록 장치가 아니라 일반 파일이므로 강제한다
# -q  : 조용히
# -m 0: root 예약 블록 0%. 기본 5%는 시스템 디스크가 꽉 찼을 때 root가
#       복구할 여지를 남기는 장치인데, 설정 파일만 담는 16MB 디스크에서는
#       의미가 없다.
# -L  : 레이블. `blkid`나 dumpe2fs로 볼 때 이게 뭐였는지 알아보기 위함.
#
# ext2를 고른 이유(저널 없음, 유닉스 퍼미션 있음)는 design doc의
# "1. virtio-blk + ext2" 참고. 파티션 테이블 없이 디스크 전체가 곧
# 파일시스템이다 — 그래서 게스트가 볼 이름도 /dev/vda1이 아니라 /dev/vda다.
mkfs.ext2 -F -q -m 0 -L tars-config "$IMG"

echo "make_disk: created ${IMG} (${SIZE}, ext2)"
```

- [ ] **Step 2: 실행 권한 부여**

Run:
```bash
chmod +x config/make_disk.sh
```

- [ ] **Step 3: 실제로 구워보고 결과를 들여다본다**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c \
  './config/make_disk.sh && ls -l out/config.img && dumpe2fs -h out/config.img 2>&1 | head -25'
```

Expected: `make_disk: created ../out/config.img (16M, ext2)`, 16777216바이트
파일, 그리고 `dumpe2fs`의 헤더. **다음 두 줄을 특히 볼 것.**

```
Filesystem volume name:   tars-config
Filesystem features:      ext_attr resize_inode dir_index filetype sparse_super large_file
```

`Filesystem features`에 **`has_journal`이 없어야 하고**(있으면 ext3이 된
것이다), `metadata_csum`이나 `64bit`도 없어야 한다 — 커널의 `CONFIG_EXT2_FS`
드라이버는 그것들을 모른다. 목록이 위와 크게 다르면 붙여서 알릴 것. 그
경우의 대응은 `mkfs.ext2`에 `-O ^<기능이름>`을 붙여 끄는 것이다.

- [ ] **Step 4: Commit**

Claude가 수행한다.

---

## Task 4: PID 1이 `/config`에 마운트한다

**Files:**
- Modify: `init/src/main.zig` (`mountFs` 시그니처 + 호출 4곳 + 새 함수)
- Modify: `kernel/make_initrd.sh:78`

마운트 지점(`/config` 디렉터리)은 **initrd 안에 미리 만들어 둔다.**
`/dev/pts`처럼 런타임에 `mkdir`하지 않는 이유는, `/dev`는 devtmpfs가 덮어써서
initrd에 만들어 둔 하위 디렉터리가 가려지지만 `/config`는 그런 사정이 없기
때문이다. `/proc`·`/sys`·`/dev`와 같은 취급이면 된다.

- [ ] **Step 1: `kernel/make_initrd.sh`에 `/config` 디렉터리 추가**

78번째 줄:

```bash
mkdir -p "$WORKDIR/usr/bin" "$WORKDIR/proc" "$WORKDIR/sys" "$WORKDIR/dev"
```

를

```bash
mkdir -p "$WORKDIR/usr/bin" "$WORKDIR/proc" "$WORKDIR/sys" "$WORKDIR/dev" \
         "$WORKDIR/config"
```

로 바꾼다.

- [ ] **Step 2: `mountFs`가 마운트 플래그를 받게 한다**

`init/src/main.zig:12`의 함수를 바꾼다.

바꾸기 전:

```zig
fn mountFs(source: [:0]const u8, target: [:0]const u8, fstype: [:0]const u8) void {
    const rc = linux.mount(source.ptr, target.ptr, fstype.ptr, 0, 0);
```

바꾼 뒤:

```zig
fn mountFs(
    source: [:0]const u8,
    target: [:0]const u8,
    fstype: [:0]const u8,
    flags: u32,
) void {
    const rc = linux.mount(source.ptr, target.ptr, fstype.ptr, flags, 0);
```

나머지 본문(성공/실패 로그)은 그대로 둔다. **로그 문자열은 한 글자도 바꾸지
않는다** — `tars-init: mounted {s} at {s}` 네 줄은 `boot/check.sh:53-57`과
`terminal/check.sh`가 grep하는 마커다.

`std.os.linux.mount`의 시그니처는 이렇다(호스트 std 0.16.0,
`/opt/homebrew/Cellar/zig/0.16.0_1/lib/zig/std/os/linux.zig:994`에서 확인):

```zig
pub fn mount(special: ?[*:0]const u8, dir: [*:0]const u8, fstype: ?[*:0]const u8, flags: u32, data: usize) usize
```

- [ ] **Step 3: 기존 호출 네 곳에 `0`을 넘긴다**

`mountDevpts` 안(36번째 줄 근처):

```zig
    mountFs("devpts", "/dev/pts", "devpts", 0);
```

`main` 안(229~232번째 줄):

```zig
    mountFs("proc", "/proc", "proc", 0);
    mountFs("sysfs", "/sys", "sysfs", 0);
    mountFs("devtmpfs", "/dev", "devtmpfs", 0);
    mountDevpts();
```

- [ ] **Step 4: `mountConfig`를 추가한다**

`mountDevpts` 함수 바로 다음(37번째 줄 뒤)에 넣는다.

```zig
/// 설정 저장소를 붙인다. initramfs는 tmpfs라 전원이 꺼지면 통째로 사라진다 —
/// 재부팅을 넘어 살아남는 것은 이 virtio-blk 디스크(/dev/vda) 하나뿐이다.
/// 파티션 테이블 없이 디스크 전체가 ext2라서 /dev/vda1이 아니라 /dev/vda다.
///
/// MS_SYNCHRONOUS로 붙이는 이유가 이 서브프로젝트의 핵심이다. 보통 파일에
/// 쓴 내용은 page cache에만 올라가고 커널이 알아서 나중에 디스크로 내려보낸다.
/// 그런데 우리 사용 시나리오는 "설정을 고치고 전원을 끈다"이고, 게이트는 실제로
/// 쓴 직후 QEMU를 죽인다. 동기 마운트면 write(2)가 돌아온 시점에 이미 디스크에
/// 있다. 설정 파일은 어쩌다 한 번 쓰는 것이라 성능 대가가 사실상 없다.
///
/// 디스크가 없는 부팅도 정상 경로다 — BF 체인은 ISO 부팅이라 -drive가 없다.
/// 그때는 errno 2(ENOENT)로 실패하고 로그 한 줄만 남으며, 부팅은 계속된다.
fn mountConfig() void {
    mountFs("/dev/vda", "/config", "ext2", linux.MS.SYNCHRONOUS);
}
```

`linux.MS.SYNCHRONOUS`는 `16`이다(std 0.16.0 `os/linux.zig:5678`).

- [ ] **Step 5: `main`에서 호출한다**

`mountDevpts();` 다음 줄에 넣는다.

```zig
    mountFs("proc", "/proc", "proc", 0);
    mountFs("sysfs", "/sys", "sysfs", 0);
    mountFs("devtmpfs", "/dev", "devtmpfs", 0);
    mountDevpts();
    mountConfig();
```

**순서가 중요하다.** `/dev/vda`라는 장치 노드는 devtmpfs가 만들어주는
것이므로 `mountFs("devtmpfs", ...)` 뒤여야 한다.

- [ ] **Step 6: 빌드**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c 'cd init && zig build'
```

Expected: 출력 없이 종료 코드 0.

- [ ] **Step 7: 여전히 정적 바이너리인지 확인**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c 'readelf -d init/zig-out/bin/init | grep -c NEEDED'
```

Expected: `0`.

`ldd`가 아니라 `readelf`인 이유는 빌드 호스트가 arm64라 x86_64 바이너리를
동적 로더에 태울 수 없기 때문이다(`project_build_host_arch` 규칙 2).
`0`이 아니면 `make_initrd.sh`가 `init`에 대해 `copy_lib_deps`를 부르지 않으므로
부팅이 로더 에러로 죽는다 — 즉시 알릴 것.

- [ ] **Step 8: Commit**

Claude가 수행한다.

---

## Task 5: 세 번째 게이트 체인

**Files:**
- Create: `config/check.sh`
- Modify: `check.sh:35-41`

게이트는 자기가 안 보는 것을 통과시킨다
(`docs/decisions/project_gate_chain_composition.md`). 마운트를 코드로만
만들고 검사를 안 넣으면 다음 milestone에서 조용히 깨져도 PASS가 난다.

QEMU 인자는 **TF 체인과 같은 모양에 `-drive`만 더한다.** CP-M2에서
`sendkey`로 게스트 셸에 타이핑해야 하는데, 그 키는 evdev를 거쳐 `terminal`이
읽으므로 `virtio-gpu-pci`가 필요하다. 지금부터 같은 모양으로 맞춰두면
M2에서 QEMU 줄을 다시 고칠 일이 없다.

- [ ] **Step 1: `config/check.sh` 생성**

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

REPO_ROOT="$(cd .. && pwd)"

# 빌드 순서는 TF 체인과 같다(kernel → init → terminal → initrd).
if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../terminal && ./prepare.sh); then
  echo "FAIL: terminal build failed"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

# 디스크는 매 회차 새로 굽는다. 남은 이미지를 재사용하면 "빈 디스크로 첫
# 부팅"이라는 전제가 무너지고, CP-M1이 검증할 seeding 경로가 두 번 다시
# 실행되지 않은 채 게이트가 자기를 속이게 된다.
if ! ./make_disk.sh; then
  echo "FAIL: disk image build failed"
  exit 1
fi

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# TF 체인과 같은 인자에 -drive 하나가 더 붙었다.
#   if=virtio  → QEMU가 virtio-blk-pci 장치를 만들어 붙인다. 게스트에서는
#                /dev/vda로 보인다(파티션이 없으므로 vda1은 없다).
#   format=raw → 이미지가 qcow2가 아니라 날 것이라고 못박는다. 안 적으면
#                QEMU가 내용을 보고 추측하며 경고를 낸다.
qemu-system-x86_64 \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -drive file="${REPO_ROOT}/out/config.img",if=virtio,format=raw \
  -display none \
  -serial file:"$LOG" \
  -no-reboot &
QEMU_PID=$!

# 고정 sleep 대신 로그 폴링. 마운트 성공 줄이 나오면 즉시 끝낸다.
MOUNTED=0
for _ in $(seq 1 120); do
  if grep -q "tars-init: mounted ext2 at /config" "$LOG"; then
    MOUNTED=1
    break
  fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then
    break
  fi
  sleep 1
done

if [ "$MOUNTED" != "1" ]; then
  echo "FAIL: init did not mount the config disk"
  echo "--- markers ---"
  for marker in \
    "virtio_blk" \
    "tars-init: mounted devtmpfs at /dev" \
    "tars-init: mounted ext2 at /config" \
    "tars-init: failed to mount ext2 at /config"; do
    if grep -q "$marker" "$LOG"; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  tail -n 60 "$LOG"
  exit 1
fi
echo "init mounted the config disk at /config"

# 커널이 디스크를 인식했는지도 따로 본다. 마운트가 됐다면 당연히 됐겠지만,
# 실패했을 때 "드라이버가 없다"와 "파일시스템이 안 맞는다"를 가르는 줄이다.
if ! grep -q "\[vda\]" "$LOG"; then
  echo "FAIL: kernel never reported a [vda] block device"
  tail -n 60 "$LOG"
  exit 1
fi
echo "kernel probed the virtio-blk device as vda"

if grep -q "Attempted to kill init" "$LOG"; then
  echo "FAIL: kernel panicked because PID 1 exited"
  tail -n 60 "$LOG"
  exit 1
fi

echo "PASS"
exit 0
```

- [ ] **Step 2: 실행 권한 부여**

Run:
```bash
chmod +x config/check.sh
```

- [ ] **Step 3: 루트 `check.sh`에 체인 추가**

`check.sh:35-41`을 바꾼다.

바꾸기 전:

```bash
# BF 체인은 limine ISO 부팅 경로를, TF 체인은 부팅 이후의 전체 런타임
# (DRM 렌더링 + evdev 입력 + PTY 셸)을 검증한다. 한때 있던 DF 체인
# (display/check.sh)과 kernel/check.sh는 ZM-M2에서 파일까지 지웠다 — 은퇴
# 사유는 docs/decisions/project_gate_chain_composition.md 참고.
run_chain "BF-M4" ./boot/check.sh
run_chain "TF-M4" ./terminal/check.sh
```

바꾼 뒤:

```bash
# BF 체인은 limine ISO 부팅 경로를, TF 체인은 부팅 이후의 전체 런타임
# (DRM 렌더링 + evdev 입력 + PTY 셸)을 검증한다. 한때 있던 DF 체인
# (display/check.sh)과 kernel/check.sh는 ZM-M2에서 파일까지 지웠다 — 은퇴
# 사유는 docs/decisions/project_gate_chain_composition.md 참고.
#
# CP 체인은 영속 저장소를 본다. 세 체인 중 유일하게 -drive로 디스크를 물고
# 부팅하며, 나머지 둘은 디스크 없이 부팅해도 통과해야 한다는 것 자체가
# 검사 대상이다(설정 저장소가 없다고 부팅이 막히면 안 된다).
run_chain "BF-M4" ./boot/check.sh
run_chain "TF-M4" ./terminal/check.sh
run_chain "CP-M0" ./config/check.sh
```

`clean()`은 손대지 않는다 — 이미 `out`을 통째로 지우므로 `out/config.img`도
매 회차 사라지고, `config/check.sh`가 다시 굽는다.

- [ ] **Step 4: Commit**

Claude가 수행한다.

---

## Task 6: 세 체인을 각각 돌린다

**Files:** 없음(확인만)

- [ ] **Step 1: CP 체인**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash config/check.sh 2>&1 | tee /tmp/cp-m0.log
```

Expected 마지막 세 줄:

```
init mounted the config disk at /config
kernel probed the virtio-blk device as vda
PASS
```

**여기가 이 milestone에서 가장 깨지기 쉬운 지점이다.** 실패하면
`--- markers ---` 출력을 그대로 붙여서 알릴 것. 어디까지 갔는지가 원인을
가른다.

- `virtio_blk`도 `[vda]`도 없다 → 커널에 드라이버가 없다. Task 1로 돌아간다
  (`kernel/build/.config` 재확인).
- `[vda]`는 있는데 `failed to mount ext2 at /config (errno 2)` →
  **ENOENT.** `/dev/vda` 노드가 아직 없는 것이다. 원인은 둘 중 하나다:
  devtmpfs 마운트가 안 됐거나(그럴 리 없다 — 마커가 있다), **virtio-blk
  probe가 init보다 늦게 끝났다.** 후자면 로그에서 `[vda]` 줄이
  `tars-init: mounted devtmpfs at /dev`보다 **뒤에** 나온다. 그 경우의 대응은
  `mountConfig`에 짧은 재시도(0.1초 간격 10회)를 넣는 것이다.
- `failed to mount ext2 at /config (errno 19)` → **ENODEV.** 커널이 ext2
  파일시스템 타입을 모른다. `CONFIG_EXT2_FS`가 실제로는 안 켜진 것이다.
- `failed to mount ext2 at /config (errno 22)` → **EINVAL.** 슈퍼블록을 읽었는데
  드라이버가 모르는 기능이 켜져 있다는 뜻이 대부분이다. Task 3 Step 3의
  `dumpe2fs` 출력을 다시 볼 것.
- **마운트는 성공했는데 `[vda]`가 없다** → 드라이버 문제가 아니라 커널 콘솔
  loglevel이 그 줄을 시리얼로 안 내보낸 것이다. 이 경우 검사가 헛되이 실패한
  것이므로 `[vda]` 검사를 정보성 출력으로 낮춘다(마운트 성공이 더 강한
  증거다). 그대로 붙여서 알릴 것.

- [ ] **Step 2: BF 체인 — 디스크 없이도 통과해야 한다**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash boot/check.sh 2>&1 | tee /tmp/cp-m0-bf.log
```

Expected: `PASS`, 배너까지 4초 안팎.

로그에 이 줄이 **새로** 나타나는 것이 정상이다.

```
tars-init: failed to mount ext2 at /config (errno 2)
```

**이 줄이 있는데도 PASS가 나는 것이 이 Step의 검사 내용이다.** 저장소가 없는
부팅이 막히면 안 된다.

- [ ] **Step 3: TF 체인**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash terminal/check.sh 2>&1 | tee /tmp/cp-m0-tf.log
```

Expected: `PASS`. TF도 `-drive`가 없으므로 BF와 같은 `errno 2` 줄이 나온다.

`init` 바이너리가 바뀌었으므로 세 체인을 다 돌리는 것이다 — initrd를 읽는
경로가 BF(limine이 ISO에서 BIOS INT13h로)와 나머지(QEMU `-initrd`)가 서로
다르다.

- [ ] **Step 4: 루트 게이트 전체 3/3**

Run:
```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash check.sh 2>&1 | tee /tmp/cp-m0-gate.log
```

Expected 마지막 줄:

```
TARS check PASS: all chains 3/3 consecutive runs succeeded
```

체인이 둘에서 셋으로 늘었으므로 **부팅이 6회에서 9회로 늘고, clean 재빌드도
9회가 된다.** ZM-M3 기준 두 체인 8분 52초였으니 13분 안팎을 예상한다.
**실제 소요 시간을 재서 알릴 것** — 이 숫자가 CP-M1(회차당 부팅 2회)에서
얼마나 더 늘지 가늠하는 기준이 된다.

```bash
time docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash check.sh 2>&1 | tee /tmp/cp-m0-gate.log
```

로 재도 된다.

- [ ] **Step 5: 9회 전부에서 숫자 확인**

Run:
```bash
grep -c 'tars-init: starting as PID 1' /tmp/cp-m0-gate.log
grep -c 'tars-init: mounted ext2 at /config' /tmp/cp-m0-gate.log
grep -c 'tars-init: failed to mount ext2 at /config' /tmp/cp-m0-gate.log
grep -c 'Attempted to kill init' /tmp/cp-m0-gate.log
```

Expected: `9`, `3`, `6`, `0`.

- `9` — 부팅 9회(BF 3 + TF 3 + CP 3).
- `3` — 마운트 성공은 CP 체인 3회분뿐이다.
- `6` — BF·TF는 디스크가 없으므로 실패가 정상이다. **이 숫자가 6이 아니라 0이면
  오히려 이상하다** — 마운트 시도 자체가 사라졌다는 뜻이다.
- `0` — 하나라도 있으면 게이트가 PASS했더라도 실패로 본다.

---

## Task 7: 문서 갱신

**Files:**
- Modify: `HANDOFF.md`
- Modify: 이 plan 파일(말미에 "실제 실행에서 plan과 달라진 점" 추가)

- [ ] **Step 1: Claude가 문서를 갱신한다**

사용자는 Task 6까지의 결과만 전달하면 된다.

갱신 내용:
- 이 plan 말미에 "실제 실행에서 plan과 달라진 점". **다음 세션이 가장 먼저
  읽는 부분이므로 빠짐없이 적는다** — 특히 errno가 무엇이었는지, 재시도가
  필요했는지, 게이트 소요 시간이 얼마였는지.
- `HANDOFF.md`를 CP-M1 기준으로 다시 쓴다.

`docs/decisions/`의 새 기억 파일은 CP-M2까지 끝난 뒤에 서브프로젝트 단위로
쓴다 — M0 하나로는 아직 "결정"이라고 부를 만큼 굳지 않았다.

- [ ] **Step 2: Commit**

Claude가 수행한다.

---

## 이번 milestone에서 하지 않는 것

- **설정 파일 읽기/쓰기.** `/config`는 비어 있는 채로 마운트만 된다. 파서와
  first-boot seeding은 CP-M1이다.
- **`Kind.path()`가 설정을 보는 것.** 셸은 여전히 `/usr/bin/fish` 상수다.
  CP-M2.
- **bash/zsh를 initrd에 넣는 것.** CP-M2. `Dockerfile`의 sysroot 목록은
  이번에 건드리지 않는다(위쪽 컨테이너 도구 목록에 `e2fsprogs`만 추가한다).
- **두 번 부팅하는 게이트.** CP-M1부터. 이번 게이트는 1회 부팅이다.
- **TF/BF 체인에 디스크를 물리는 것.** 일부러 안 한다 — "디스크가 없어도
  부팅한다"가 검사 대상이기 때문이다.
- **파티션 테이블, 여러 파일시스템, fsck.** design doc의 비목표 그대로.

---

## 실제 실행에서 plan과 달라진 점 (2026-08-14 완료)

**다음 세션은 이 절부터 읽을 것.** CP-M0는 `TARS check PASS`(BF 3/3, TF 3/3,
**CP 3/3**)로 완료됐다. 루트 게이트 전체 소요는 **13분 08초** — 두 체인
8분 52초에서 4분 16초가 늘었고, 그것이 CP 3회분(빌드 + 부팅)이다.

### 1. 예상한 실패가 하나도 안 났다

plan의 Task 6 Step 1은 errno별 진단표를 네 줄이나 준비했는데 **첫 실행에서
바로 마운트가 됐다.** 특히 걱정했던 경합(virtio-blk probe가 init보다 늦게
끝나 `/dev/vda`가 아직 없는 상황)이 일어나지 않았다 — 내장 드라이버의 PCI
probe가 `/init` 실행보다 먼저 끝난다. `mountConfig`에 재시도 루프를 넣지
않았고, 넣을 필요도 없었다.

`dumpe2fs`로 미리 확인한 것도 그대로였다. mke2fs 1.47.2의 ext2 프로파일은
`ext_attr resize_inode dir_index filetype sparse_super large_file`만 켜고
`has_journal`/`metadata_csum`/`64bit`은 켜지 않는다 — 커널 `CONFIG_EXT2_FS`
드라이버가 거부할 것이 없다. 블록 크기는 1024로 잡혔고(16MB짜리 작은
파일시스템이라 mke2fs가 그렇게 고른다), 오버헤드가 1159블록(약 7%)인데
대부분이 고정 개수 inode 4096개의 테이블이다.

### 2. 디스크 없는 체인의 실패 줄이 뜻밖의 증거를 준다

BF/TF 로그에 이 두 줄이 새로 생겼다.

```
/dev/vda: Can't lookup blockdev          ← 커널이 찍는다
tars-init: failed to mount ext2 at /config (errno 2)
```

`mount(2)`는 (1) 파일시스템 타입 찾기 → (2) 블록 장치 열기 → (3) 마운트
지점에 붙이기 순서로 진행한다. 커널이 (2)에서 실패했다고 말한다는 것은
**(1)을 통과했다는 뜻**이다. 즉 디스크를 안 물린 체인의 실패 로그가
`CONFIG_EXT2_FS`가 커널에 들어 있음을 증명한다. 타입이 없었다면 errno 19
(ENODEV)로 조용히 끝났을 것이다.

### 3. plan에 없던 Step: 성공했을 때도 init 로그를 찍는다

루트 게이트 통합 로그에서 검증 숫자를 셌더니 기대치 `9/3/6/0`이 아니라
**`6/0/6/0`**이 나왔다. 원인은 게이트 실패가 아니라 `config/check.sh`가
**성공 경로에서 시리얼 로그를 하나도 출력하지 않았기** 때문이다 —
`boot/check.sh`는 `cat "$LOG"`, `terminal/check.sh`는 `--- init log ---`를
찍는데 CP만 요약 세 줄뿐이었다. 그래서 통합 로그에는 부팅 9회 중 6회의
흔적만 남았다.

`echo "PASS"` 앞에 이 두 줄을 넣어 고쳤다(커밋 `848a3db`).

```bash
echo "--- init log ---"
grep 'tars-init:' "$LOG" || true
```

`|| true`는 `set -uo pipefail` 아래에서 grep이 빈 결과로 1을 반환하는 것을
막기 위한 것이다. **다음 전체 게이트부터 숫자는 `9 / 3 / 6 / 0`이 된다**
(부팅 9회, 마운트 성공 3회 = CP, 실패 6회 = BF+TF, 패닉 0). 이 검증은
CP-M1 종료 시점에 자연스럽게 이뤄진다.

교훈은 이 저장소에서 반복되는 그것이다 — **게이트가 통과시킨 것과 게이트가
기록에 남긴 것은 다르다.** CP 체인 자체는 마운트를 제대로 검사하고 있었지만,
사후에 통합 로그만 보는 사람에게는 그 3회가 존재하지 않는 것처럼 보였다.

### 4. 크기와 형태

- `out/config.img` — 16,777,216바이트 sparse 파일. `truncate` + `mkfs.ext2
  -F -q -m 0 -L tars-config`. 레이블은 `tars-config`, UUID는 회차마다
  달라진다(경로 `/dev/vda`로 찾으므로 무관).
- `init` 바이너리는 12MB 그대로, 동적 의존 여전히 0개.
  `linux.MS.SYNCHRONOUS`도 `linux.mount`도 std의 시스템 콜 래퍼라 libc가
  딸려오지 않는다.
- 커널 `.config`는 세 줄만 늘었고 `olddefconfig`이 `CONFIG_VIRTIO_BLK`를
  지우지 않았다(`CONFIG_BLK_DEV=y`를 먼저 썼기 때문). 확인은
  `kernel/build/.config`에서 한다.
