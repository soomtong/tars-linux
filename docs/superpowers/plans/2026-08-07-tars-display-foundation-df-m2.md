# TARS Display Foundation — DF-M2 픽셀 그리기(MVP 종료점) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **단, 이 저장소는 pairing 방식 고정(`CLAUDE.md`, HANDOFF.md 참고):** 파일
> 작성과 명령 실행은 사용자가 직접 하고, Claude는 각 Step의 정확한 내용을
> 제시하고 결과를 해석한다. 위 SUB-SKILL 문구는 다른 저장소용 기본값이며 이
> 저장소에는 적용하지 않는다.

**Goal:** DF-M2를 완료한다 — 새 Rust 바이너리 `kms`가 `/dev/dri/card0`를
직접 열어 DRM ioctl(리소스 조회 → dumb buffer 생성 → mmap → 픽셀 채우기 →
framebuffer 등록 → CRTC 모드 설정)을 순서대로 호출해 화면 전체를 단색(빨강)
으로 채우고, `init`이 부팅 중 이를 실행하도록 연결하며, `display/check.sh`의
screendump 파이프라인으로 실제 화면 픽셀 색을 검사해 성공을 확인한다. 이
milestone이 design doc이 정의한 MVP 종료점이다.

**Architecture:** design doc §3의 결정대로 DRM 초기화 코드는 `init`
안에 넣지 않고 새 디렉터리 `kms/`에 별도 Rust 바이너리로 만든다. `drm`
crate 같은 래퍼를 쓰지 않고, `libc::ioctl`을 직접 호출한다 — ioctl 요청
번호는 커널 소스에 이미 다운로드된
`kernel/src/linux-6.18.42/include/uapi/drm/drm.h`/`drm_mode.h`에서 직접
확인한 정확한 struct 레이아웃과 매크로 공식(`_IOC` 인코딩)으로 계산한다.
개발 중간 단계(Task 1~4)는 `kms` 바이너리 자체를 `/init`으로 삼는 임시
initrd로 반복 검증하고(실제 `tars-init`/`initrd.cpio`는 건드리지 않음),
Task 5에서 비로소 `tars-init`이 `fork`+`execve`로 `kms`를 실행하도록
연결하고 정식 `initrd.cpio`에 포함시킨다. Task 6에서 DF-M0의 screendump
파이프라인(`display/check.sh`)에 픽셀 색 검사를 추가해 공식 exit gate를
자동 검증한다.

**Tech Stack:** Rust(`libc` crate, raw `ioctl`/`mmap`/`fork`/`execve`
syscall), Linux DRM/KMS uapi(`drm.h`, `drm_mode.h`), QEMU
`-device virtio-gpu-pci`, ImageMagick(픽셀 색 검사)

---

## 사전 준비

DF-M1이 완료돼 있어야 한다 — `kernel/.config`에 `CONFIG_PCI`, `CONFIG_DRM`,
`CONFIG_DRM_VIRTIO_GPU`, `CONFIG_VIRTIO_PCI`가 `y`로 켜져 있고, 부팅 시
`/dev/dri/card0`가 devtmpfs에 생성됨을 이미 확인했다(`tars-init: /dev/dri/card0
exists` 로그).

**ioctl 번호/struct 레이아웃 출처:** 이 plan의 모든 Rust struct와 ioctl
번호는 이 저장소에 다운로드된 커널 소스 트리
`kernel/src/linux-6.18.42/include/uapi/drm/drm.h`,
`kernel/src/linux-6.18.42/include/uapi/drm/drm_mode.h`를 직접 읽어 확인한
값이다(일반적인 지식이 아니라 이 저장소가 실제로 빌드하는 커널 버전의
정확한 값). DRM ioctl 번호는 아래 공식으로 계산된다(`drm.h`의
`DRM_IOWR` 매크로가 `include/uapi/asm-generic/ioctl.h`의 `_IOC` 매크로로
전개된 것):

```
request = (dir << 30) | (type << 8) | (nr << 16 >> 16 /* nr는 8비트 */) | (size << 16)
```

풀어 쓰면: `dir`은 read+write 조합인 `DRM_IOWR`의 경우 `3`, `type`은 DRM
전용 매직 바이트 `'d'`(0x64)로 고정, `nr`은 각 ioctl마다 다른 8비트
번호(`0xA0`, `0xA7` 등), `size`는 넘기는 struct의 바이트 크기다. Rust에서는
`std::mem::size_of::<T>()`로 struct 크기를 컴파일 타임에 정확히 계산할 수
있어 C의 `sizeof()`와 동일한 값을 보장한다.

**개발 중 임시 initrd 규칙:** Task 1~4는 `kms` 바이너리를 `/init`으로 삼는
임시 initrd를 그때그때 만들어서 검증한다(파일로 저장하지 않고 매번
`docker run` 안에서 `mktemp -d`로 구성) — `tars-init`이 PID 1로 남아있는
정식 부팅 경로와 완전히 분리해서, 이 단계에서 실수해도 Boot
Foundation/DF-M1이 이미 검증한 정식 경로에 영향이 없게 한다. **PID 1이
정상 종료(`main()`이 `Ok(())` 반환)하면 커널이 `Kernel panic - not
syncing: Attempted to kill init!`를 내는 것이 정상이다** — 이건 실패가
아니라 "kms가 할 일을 마치고 프로세스가 끝났다"는 신호다. 우리가 보려는
건 그 직전까지 출력된 `kms: ...` 로그 줄들이다.

---

### Task 1: `kms/` 크레이트 생성 — DRM 디바이스 열기 + 리소스 개수 조회

**Files:**
- Create: `kms/Cargo.toml`
- Create: `kms/src/main.rs`

- [ ] **Step 1: `kms/Cargo.toml` 작성**

`init/Cargo.toml`과 같은 패턴(`libc` 하나만 의존)이되, 바이너리 이름을
명시적으로 `kms`로 고정한다(패키지 이름은 `tars-init`처럼 `tars-` 접두를
붙이되, 산출물 파일명 자체는 `[[bin]] name`으로 짧게 지정 — `initrd`에
넣을 때 `tars-init`처럼 이름을 바꿔 복사할 필요가 없어진다).

```toml
[package]
name = "tars-kms"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "kms"
path = "src/main.rs"

[dependencies]
libc = "0.2"
```

- [ ] **Step 2: `kms/src/main.rs` 작성 — 첫 ioctl 호출로 배관 검증**

가장 작은 단위부터 시작한다: `/dev/dri/card0`를 열고
`DRM_IOCTL_MODE_GETRESOURCES`를 호출해 crtc/connector/encoder 개수만
읽어온다. `DRM_IOCTL_MODE_GETRESOURCES`는 표준 "2단계 조회" 관례를 쓴다 —
포인터 필드가 비어있으면(0) 커널이 배열에 쓰지 않고 개수(`count_*`)만
채워서 돌려준다. 이 첫 Step은 그 개수 조회 한 번만으로 ioctl 번호 계산
공식과 struct 레이아웃이 커널과 정확히 맞는지부터 확인한다 — 이후 Task에서
더 복잡한 로직을 쌓기 전에 가장 기초적인 배관이 맞는지 먼저 검증하는
것이다.

```rust
use std::ffi::CString;
use std::fs::File;
use std::io;
use std::mem::size_of;
use std::os::unix::io::AsRawFd;
use std::ptr;

const DRM_IOCTL_BASE: u32 = 'd' as u32;

const fn drm_iowr(nr: u32, size: usize) -> libc::c_ulong {
    ((3u32 << 30) | (DRM_IOCTL_BASE << 8) | nr | ((size as u32) << 16)) as libc::c_ulong
}

#[repr(C)]
#[derive(Debug, Default)]
struct DrmModeCardRes {
    fb_id_ptr: u64,
    crtc_id_ptr: u64,
    connector_id_ptr: u64,
    encoder_id_ptr: u64,
    count_fbs: u32,
    count_crtcs: u32,
    count_connectors: u32,
    count_encoders: u32,
    min_width: u32,
    max_width: u32,
    min_height: u32,
    max_height: u32,
}

unsafe fn drm_ioctl<T>(fd: i32, request: libc::c_ulong, arg: &mut T) -> io::Result<()> {
    let ret = libc::ioctl(fd, request, arg as *mut T as *mut libc::c_void);
    if ret < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

fn ensure_devtmpfs_mounted() {
    let source = CString::new("devtmpfs").expect("CString::new failed");
    let target = CString::new("/dev").expect("CString::new failed");
    let fstype = CString::new("devtmpfs").expect("CString::new failed");
    unsafe {
        libc::mount(source.as_ptr(), target.as_ptr(), fstype.as_ptr(), 0, ptr::null());
    }
}

fn main() -> io::Result<()> {
    ensure_devtmpfs_mounted();

    let file = File::options()
        .read(true)
        .write(true)
        .open("/dev/dri/card0")?;
    let fd = file.as_raw_fd();

    let mut res = DrmModeCardRes::default();
    unsafe { drm_ioctl(fd, drm_iowr(0xA0, size_of::<DrmModeCardRes>()), &mut res)? };

    println!(
        "kms: {} crtcs, {} connectors, {} encoders",
        res.count_crtcs, res.count_connectors, res.count_encoders
    );

    Ok(())
}
```

**정정(2026-08-07 Task 1 진행 중 발견):** 애초 이 Step은 `ensure_devtmpfs_mounted`
없이 작성됐으나, 실제로 임시 initrd로 부팅해보니 `/dev/dri/card0` open이
`ENOENT`로 실패했다 — 이 throwaway initrd의 `/init`(=`kms`)이 `tars-init`과
달리 devtmpfs를 `/dev`에 mount하는 단계가 아예 없었기 때문이다(initramfs만
쓰는 부팅에서는 devtmpfs가 자동으로 mount되지 않는다). `kms`가 시작할 때
방어적으로 mount를 한 번 시도하고 실패(예: Task 5 이후 `tars-init`이 이미
mount해둔 상태에서 나는 `EBUSY`)는 무시하도록 고쳐서 반영했다.

- [ ] **Step 3: 컴파일 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/kms \
  tars-devcontainer bash -c "cargo build --release"
```

Expected: 종료 코드 0, `Finished \`release\` profile [optimized] target(s)`.

- [ ] **Step 4: 임시 initrd로 부팅 검증**

`kms` 바이너리를 `/init`으로 삼는 임시 initrd를 만들어 실제 virtio-gpu-pci
장치를 붙인 QEMU에서 실행한다 — DF-M1까지 만든 실제 커널을 그대로
재사용한다.

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c '
set -euo pipefail
WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT
mkdir -p "$WORK/proc" "$WORK/sys" "$WORK/dev"
cp kms/target/release/kms "$WORK/init"
chmod 0755 "$WORK/init"
for lib in $(ldd "$WORK/init" | grep -oE "/[^ ]+\.so[0-9.]*"); do
  mkdir -p "$WORK$(dirname "$lib")"
  cp -n "$lib" "$WORK$lib"
done
(cd "$WORK" && find . | cpio -o -H newc) > /tmp/kms-dev-initrd.cpio
timeout 15 qemu-system-x86_64 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd /tmp/kms-dev-initrd.cpio \
  -append "console=ttyS0" \
  -vga none -device virtio-gpu-pci \
  -serial stdio -display none -no-reboot || true
'
```

Expected: 로그 어딘가에 `kms: 1 crtcs, 1 connectors, 1 encoders`(virtio-gpu는
scanout 하나짜리 가상 장치라 세 값 모두 1일 가능성이 높다 — 다른 값이
나와도 오류는 아니며, 이후 Task에서 이 개수를 그대로 활용하므로 실제 값을
확인해 두면 된다)와 뒤이어 `Kernel panic - not syncing: Attempted to kill
init!`가 출력된다. 이 panic은 위 "개발 중 임시 initrd 규칙"에서 설명한
대로 정상이다.

**만약 `kms:` 로그 줄 자체가 안 보이고 ioctl 관련 에러(`Error { ... }`)로
panic 없이 종료되면:** ioctl 번호 계산이나 struct 크기가 커널 기대값과
다른 것이다 — 어떤 에러(`Os { code: N, ... }`)가 나왔는지 알려달라. errno
`22`(EINVAL)면 struct 크기 불일치, `19`(ENODEV)면 애초에 `/dev/dri/card0`가
아직 준비 안 된 것(DF-M1 재확인 필요)일 가능성이 높다.

- [ ] **Step 5: 커밋**

```bash
git add kms/Cargo.toml kms/src/main.rs
git commit -m "Add kms binary skeleton with DRM resource count query"
```

---

### Task 2: 연결된 connector/encoder/crtc 선택

**Files:**
- Modify: `kms/src/main.rs`

- [ ] **Step 1: 나머지 struct 정의와 리소스 선택 로직 추가**

Task 1의 `DrmModeCardRes` 정의 뒤에 세 개의 struct를 더 추가한다:

```rust
#[repr(C)]
#[derive(Debug, Default, Clone, Copy)]
struct DrmModeModeinfo {
    clock: u32,
    hdisplay: u16,
    hsync_start: u16,
    hsync_end: u16,
    htotal: u16,
    hskew: u16,
    vdisplay: u16,
    vsync_start: u16,
    vsync_end: u16,
    vtotal: u16,
    vscan: u16,
    vrefresh: u32,
    flags: u32,
    mode_type: u32,
    name: [u8; 32],
}

#[repr(C)]
#[derive(Debug, Default)]
struct DrmModeGetConnector {
    encoders_ptr: u64,
    modes_ptr: u64,
    props_ptr: u64,
    prop_values_ptr: u64,
    count_modes: u32,
    count_props: u32,
    count_encoders: u32,
    encoder_id: u32,
    connector_id: u32,
    connector_type: u32,
    connector_type_id: u32,
    connection: u32,
    mm_width: u32,
    mm_height: u32,
    subpixel: u32,
    pad: u32,
}

#[repr(C)]
#[derive(Debug, Default)]
struct DrmModeGetEncoder {
    encoder_id: u32,
    encoder_type: u32,
    crtc_id: u32,
    possible_crtcs: u32,
    possible_clones: u32,
}
```

(`mode_type`은 C 원본에서는 `type`이라는 필드명이지만 Rust 예약어라 이름만
바꿨다 — `#[repr(C)]`는 필드 이름이 아니라 선언 순서로 레이아웃을
맞추므로 이름을 바꿔도 안전하다.)

`main()` 앞에 리소스를 2단계로 조회하고 연결된 connector와 사용할 crtc를
고르는 함수 세 개를 추가한다:

```rust
fn get_resources(fd: i32) -> io::Result<(Vec<u32>, Vec<u32>, Vec<u32>)> {
    let mut res = DrmModeCardRes::default();
    unsafe { drm_ioctl(fd, drm_iowr(0xA0, size_of::<DrmModeCardRes>()), &mut res)? };

    let mut crtc_ids = vec![0u32; res.count_crtcs as usize];
    let mut connector_ids = vec![0u32; res.count_connectors as usize];
    let mut encoder_ids = vec![0u32; res.count_encoders as usize];

    res.crtc_id_ptr = crtc_ids.as_mut_ptr() as u64;
    res.connector_id_ptr = connector_ids.as_mut_ptr() as u64;
    res.encoder_id_ptr = encoder_ids.as_mut_ptr() as u64;
    res.fb_id_ptr = 0;

    unsafe { drm_ioctl(fd, drm_iowr(0xA0, size_of::<DrmModeCardRes>()), &mut res)? };

    println!(
        "kms: {} crtcs, {} connectors, {} encoders",
        res.count_crtcs, res.count_connectors, res.count_encoders
    );

    Ok((crtc_ids, connector_ids, encoder_ids))
}

fn find_connected_connector(
    fd: i32,
    connector_ids: &[u32],
) -> io::Result<(DrmModeGetConnector, DrmModeModeinfo, Vec<u32>)> {
    for &id in connector_ids {
        let mut conn = DrmModeGetConnector {
            connector_id: id,
            ..Default::default()
        };
        unsafe { drm_ioctl(fd, drm_iowr(0xA7, size_of::<DrmModeGetConnector>()), &mut conn)? };

        if conn.connection != 1 || conn.count_modes == 0 {
            continue;
        }

        let mut modes = vec![DrmModeModeinfo::default(); conn.count_modes as usize];
        let mut encoders = vec![0u32; conn.count_encoders as usize];
        conn.modes_ptr = modes.as_mut_ptr() as u64;
        conn.encoders_ptr = encoders.as_mut_ptr() as u64;
        conn.props_ptr = 0;
        conn.prop_values_ptr = 0;
        conn.count_props = 0;
        unsafe { drm_ioctl(fd, drm_iowr(0xA7, size_of::<DrmModeGetConnector>()), &mut conn)? };

        let mode = modes[0];
        println!(
            "kms: connector {} connected, mode {}x{}",
            id, mode.hdisplay, mode.vdisplay
        );
        return Ok((conn, mode, encoders));
    }

    Err(io::Error::new(
        io::ErrorKind::NotFound,
        "no connected connector with modes found",
    ))
}
```

**정정 1(2026-08-07 Task 2 진행 중 발견):** 애초 두 번째 `GETCONNECTOR` 호출
전에 `encoders_ptr`/`props_ptr`/`prop_values_ptr`만 0으로 되돌리고
`count_encoders`/`count_props`는 그대로 뒀는데, 실제로 부팅해보니
`EFAULT`(errno 14, "Bad address")가 났다 — 커널은 "호출자가 넘긴 count가
실제 개수 이상이면 그 포인터로 배열을 복사한다"는 규칙을 쓰므로, count는
그대로 두고 포인터만 null로 만들면 null 주소에 복사를 시도해 실패한다.
포인터를 비울 때는 그에 대응하는 count도 함께 0으로 만들어야 한다.

**정정 2(2026-08-07 Task 2 진행 중 발견):** 정정 1을 반영해 다시
부팅하니 `kms: connector 38 connected, mode 1280x800`까지는 성공했지만
이어서 `ENOENT`(errno 2)가 났다 — `find_crtc`에 넘긴 `connector.encoder_id`
값이 `0`이었기 때문이다. 이 필드는 "지금 이 connector에 실제로 붙어 있는"
encoder를 가리키는데, 아직 아무도 모드 설정을 한 적 없는 갓 부팅한
커널에서는 `0`(할당된 게 없음)일 수 있다. 그래서 `encoders_ptr`도 함께
조회해(`count_props`만 0으로 비우고 `count_encoders`는 그대로 둔 채
`encoders` 배열을 할당) connector가 사용 가능하다고 알려주는 encoder
목록을 반환값에 추가했다 — `main()`에서 `connector.encoder_id`가 0이면
이 목록의 첫 번째 값을 대신 쓴다(아래 `main()` 코드에 반영).

```rust
fn find_crtc(fd: i32, encoder_id: u32, crtc_ids: &[u32]) -> io::Result<u32> {
    let mut enc = DrmModeGetEncoder {
        encoder_id,
        ..Default::default()
    };
    unsafe { drm_ioctl(fd, drm_iowr(0xA6, size_of::<DrmModeGetEncoder>()), &mut enc)? };

    if enc.crtc_id != 0 {
        return Ok(enc.crtc_id);
    }

    for (i, &crtc_id) in crtc_ids.iter().enumerate() {
        if enc.possible_crtcs & (1 << i) != 0 {
            return Ok(crtc_id);
        }
    }

    Err(io::Error::new(
        io::ErrorKind::NotFound,
        "no usable crtc for encoder",
    ))
}
```

`connection != 1`은 "연결 안 됨/알 수 없음"을 건너뛰는 조건이다(1이
"connected" — `include/drm/drm_connector.h`의 `enum drm_connector_status`
확인값). `find_crtc`는 먼저 encoder가 이미 붙어있는 crtc(`enc.crtc_id`,
0이 아니면 이미 사용 중)를 우선 쓰고, 없으면 `possible_crtcs`
비트마스크에서 사용 가능한 첫 crtc를 고른다.

`main()`을 아래처럼 바꾼다(Task 1의 개수 출력 코드를 이 두 함수 호출로
교체):

```rust
fn main() -> io::Result<()> {
    ensure_devtmpfs_mounted();

    let file = File::options()
        .read(true)
        .write(true)
        .open("/dev/dri/card0")?;
    let fd = file.as_raw_fd();

    let (crtc_ids, connector_ids, _encoder_ids) = get_resources(fd)?;
    let (connector, _mode, encoders) = find_connected_connector(fd, &connector_ids)?;
    let encoder_id = if connector.encoder_id != 0 {
        connector.encoder_id
    } else {
        *encoders
            .first()
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "connector has no encoders"))?
    };
    let crtc_id = find_crtc(fd, encoder_id, &crtc_ids)?;

    println!("kms: selected crtc {}", crtc_id);

    Ok(())
}
```

- [ ] **Step 2: 컴파일 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/kms \
  tars-devcontainer bash -c "cargo build --release"
```

Expected: 종료 코드 0.

- [ ] **Step 3: 임시 initrd로 부팅 검증**

Task 1 Step 4와 동일한 명령을 다시 실행한다(내용은 같으므로 그대로
재사용):

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c '
set -euo pipefail
WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT
mkdir -p "$WORK/proc" "$WORK/sys" "$WORK/dev"
cp kms/target/release/kms "$WORK/init"
chmod 0755 "$WORK/init"
for lib in $(ldd "$WORK/init" | grep -oE "/[^ ]+\.so[0-9.]*"); do
  mkdir -p "$WORK$(dirname "$lib")"
  cp -n "$lib" "$WORK$lib"
done
(cd "$WORK" && find . | cpio -o -H newc) > /tmp/kms-dev-initrd.cpio
timeout 15 qemu-system-x86_64 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd /tmp/kms-dev-initrd.cpio \
  -append "console=ttyS0" \
  -vga none -device virtio-gpu-pci \
  -serial stdio -display none -no-reboot || true
'
```

Expected: `kms: N crtcs, N connectors, N encoders` 뒤에 `kms: connector N
connected, mode WxH`, `kms: selected crtc N`이 순서대로 출력되고, 마지막에
`Attempted to kill init!` panic(정상).

**만약 `no connected connector with modes found`가 나오면:** QEMU
virtio-gpu가 `+edid` feature로 초기화됐는지(DF-M1 dmesg에서
`[drm] features: -virgl +edid ...` 확인) 다시 보고, 그래도 안 되면 전체
로그를 붙여달라 — connector 목록 자체가 비었는지, `connection` 값이
무엇으로 나오는지 함께 본다.

- [ ] **Step 4: 커밋**

```bash
git add kms/src/main.rs
git commit -m "Select connected connector and target crtc in kms"
```

---

### Task 3: dumb buffer 생성 + mmap + 단색 채우기

**Files:**
- Modify: `kms/src/main.rs`

- [ ] **Step 1: dumb buffer struct와 생성/매핑/채우기 코드 추가**

`DrmModeGetEncoder` 뒤에 두 struct를 추가한다:

```rust
#[repr(C)]
#[derive(Debug, Default)]
struct DrmModeCreateDumb {
    height: u32,
    width: u32,
    bpp: u32,
    flags: u32,
    handle: u32,
    pitch: u32,
    size: u64,
}

#[repr(C)]
#[derive(Debug, Default)]
struct DrmModeMapDumb {
    handle: u32,
    pad: u32,
    offset: u64,
}
```

`use` 목록 맨 위에 `use std::ptr;`를 추가한다(파일 최상단, `use std::fs::File;`
등과 같은 자리).

`main()`을 아래처럼 확장한다 — `find_crtc` 호출 뒤에 dumb buffer 생성,
mmap, 픽셀 채우기를 추가한다. 지금까지 `_mode`로 무시했던 mode 정보를
이제부터 실제로 쓰므로 변수명도 `mode`로 되돌린다:

```rust
fn main() -> io::Result<()> {
    let file = File::options()
        .read(true)
        .write(true)
        .open("/dev/dri/card0")?;
    let fd = file.as_raw_fd();

    let (crtc_ids, connector_ids, _encoder_ids) = get_resources(fd)?;
    let (connector, mode) = find_connected_connector(fd, &connector_ids)?;
    let crtc_id = find_crtc(fd, connector.encoder_id, &crtc_ids)?;

    println!("kms: selected crtc {}", crtc_id);

    let mut dumb = DrmModeCreateDumb {
        height: mode.vdisplay as u32,
        width: mode.hdisplay as u32,
        bpp: 32,
        ..Default::default()
    };
    unsafe { drm_ioctl(fd, drm_iowr(0xB2, size_of::<DrmModeCreateDumb>()), &mut dumb)? };
    println!(
        "kms: dumb buffer handle={} pitch={} size={}",
        dumb.handle, dumb.pitch, dumb.size
    );

    let mut map = DrmModeMapDumb {
        handle: dumb.handle,
        ..Default::default()
    };
    unsafe { drm_ioctl(fd, drm_iowr(0xB3, size_of::<DrmModeMapDumb>()), &mut map)? };

    let map_ptr = unsafe {
        libc::mmap(
            ptr::null_mut(),
            dumb.size as usize,
            libc::PROT_READ | libc::PROT_WRITE,
            libc::MAP_SHARED,
            fd,
            map.offset as libc::off_t,
        )
    };
    if map_ptr == libc::MAP_FAILED {
        return Err(io::Error::last_os_error());
    }

    let red: u32 = 0x00FF_0000;
    for row in 0..dumb.height as usize {
        let row_start = row * dumb.pitch as usize;
        for col in 0..dumb.width as usize {
            let offset = row_start + col * 4;
            unsafe {
                let pixel_ptr = (map_ptr as *mut u8).add(offset) as *mut u32;
                pixel_ptr.write_volatile(red);
            }
        }
    }
    println!("kms: filled framebuffer with solid red");

    Ok(())
}
```

`red`는 `0x00FF_0000`이다 — dumb buffer는 `bpp=32, depth=24`일 때
`XRGB8888` 포맷을 쓰는 게 관례이고, x86(리틀엔디안)에서 이 u32 값을 그대로
쓰면 메모리에는 바이트 순서 `[B=0x00, G=0x00, R=0xFF, X=0x00]`로 저장돼
빨강이 된다. 행마다 `dumb.pitch`(줄 사이 실제 바이트 간격 — 폭×4바이트와
다를 수 있어 반드시 이 값을 써야 한다)만큼 건너뛰며 픽셀을 채운다.

- [ ] **Step 2: 컴파일 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/kms \
  tars-devcontainer bash -c "cargo build --release"
```

Expected: 종료 코드 0.

- [ ] **Step 3: 임시 initrd로 부팅 검증**

Task 1 Step 4와 동일한 명령(재사용):

```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c '
set -euo pipefail
WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT
mkdir -p "$WORK/proc" "$WORK/sys" "$WORK/dev"
cp kms/target/release/kms "$WORK/init"
chmod 0755 "$WORK/init"
for lib in $(ldd "$WORK/init" | grep -oE "/[^ ]+\.so[0-9.]*"); do
  mkdir -p "$WORK$(dirname "$lib")"
  cp -n "$lib" "$WORK$lib"
done
(cd "$WORK" && find . | cpio -o -H newc) > /tmp/kms-dev-initrd.cpio
timeout 15 qemu-system-x86_64 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd /tmp/kms-dev-initrd.cpio \
  -append "console=ttyS0" \
  -vga none -device virtio-gpu-pci \
  -serial stdio -display none -no-reboot || true
'
```

Expected: `kms: dumb buffer handle=N pitch=N size=N`과 `kms: filled
framebuffer with solid red`가 추가로 출력되고 panic으로 끝난다(정상). 아직
CRTC에 이 buffer를 연결하지 않았으므로(Task 4) 화면에 실제로 보이는 색은
없다 — 이 Step은 ioctl 호출들이 에러 없이 성공하는지만 확인한다.

- [ ] **Step 4: 커밋**

```bash
git add kms/src/main.rs
git commit -m "Create dumb buffer and fill it with solid red in kms"
```

---

### Task 4: framebuffer 등록 + CRTC 설정 — 실제로 화면에 그리기

**Files:**
- Modify: `kms/src/main.rs`

- [ ] **Step 1: `DrmModeCrtc`, `DrmModeFbCmd` struct와 마무리 로직 추가**

`DrmModeMapDumb` 뒤에 두 struct를 추가한다:

```rust
#[repr(C)]
#[derive(Debug, Default)]
struct DrmModeCrtc {
    set_connectors_ptr: u64,
    count_connectors: u32,
    crtc_id: u32,
    fb_id: u32,
    x: u32,
    y: u32,
    gamma_size: u32,
    mode_valid: u32,
    mode: DrmModeModeinfo,
}

#[repr(C)]
#[derive(Debug, Default)]
struct DrmModeFbCmd {
    fb_id: u32,
    width: u32,
    height: u32,
    pitch: u32,
    bpp: u32,
    depth: u32,
    handle: u32,
}
```

`main()`의 `println!("kms: filled framebuffer with solid red");` 뒤,
`Ok(())` 앞에 framebuffer 등록과 CRTC 설정을 추가한다:

```rust
    let mut fb = DrmModeFbCmd {
        width: dumb.width,
        height: dumb.height,
        pitch: dumb.pitch,
        bpp: 32,
        depth: 24,
        handle: dumb.handle,
        ..Default::default()
    };
    unsafe { drm_ioctl(fd, drm_iowr(0xAE, size_of::<DrmModeFbCmd>()), &mut fb)? };
    println!("kms: created framebuffer fb_id={}", fb.fb_id);

    let mut connector_id_arr = [connector.connector_id];
    let mut crtc = DrmModeCrtc {
        set_connectors_ptr: connector_id_arr.as_mut_ptr() as u64,
        count_connectors: 1,
        crtc_id,
        fb_id: fb.fb_id,
        mode_valid: 1,
        mode,
        ..Default::default()
    };
    unsafe { drm_ioctl(fd, drm_iowr(0xA2, size_of::<DrmModeCrtc>()), &mut crtc)? };
    println!("kms: set crtc {} to fb {}", crtc_id, fb.fb_id);

    Ok(())
```

`DRM_IOCTL_MODE_ADDFB`(`0xAE`)는 방금 만든 dumb buffer(`handle`)를 실제
"framebuffer 객체"로 등록해 `fb_id`를 발급받는 단계다.
`DRM_IOCTL_MODE_SETCRTC`(`0xA2`)가 이 `fb_id`를 우리가 고른
`crtc_id`에 연결하고, `set_connectors_ptr`로 어떤 connector에 출력할지,
`mode`로 어떤 타이밍(해상도 등)을 쓸지 지정한다 — 이 호출이 성공하면
실제로 화면에 픽셀이 나타난다.

- [ ] **Step 2: 컴파일 확인**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/kms \
  tars-devcontainer bash -c "cargo build --release"
```

Expected: 종료 코드 0.

- [ ] **Step 3: 임시 initrd + screendump로 실제 픽셀 색 확인**

여기서부터는 Task 1~3의 로그 확인만으로는 부족하다 — 실제로 화면에 빨강이
나타났는지 DF-M0의 screendump 파이프라인을 그대로 빌려 확인한다. 이
Step은 파일로 저장하지 않고 명령을 그대로 실행한다.

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash -c '
set -uo pipefail
WORK=$(mktemp -d)
mkdir -p "$WORK/proc" "$WORK/sys" "$WORK/dev"
cp kms/target/release/kms "$WORK/init"
chmod 0755 "$WORK/init"
for lib in $(ldd "$WORK/init" | grep -oE "/[^ ]+\.so[0-9.]*"); do
  mkdir -p "$WORK$(dirname "$lib")"
  cp -n "$lib" "$WORK$lib"
done
(cd "$WORK" && find . | cpio -o -H newc) > /tmp/kms-dev-initrd.cpio

MONITOR_PORT=45455
SCREENSHOT=$(mktemp /tmp/df-m2-dev-XXXXXX.ppm)
qemu-system-x86_64 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd /tmp/kms-dev-initrd.cpio \
  -append "console=ttyS0" \
  -vga none -device virtio-gpu-pci -display none \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then
    break
  fi
  sleep 0.5
done
sleep 3
echo "screendump ${SCREENSHOT}" >&3
sleep 1
exec 3<&- 3>&-

kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true

magick "$SCREENSHOT" -crop 1x1+10+10 +repage txt:-
'
```

Expected: 마지막 줄이 `0,0: (255,0,0) #FF0000 srgb(255,0,0)` 같은 형태로
출력된다 — `#FF0000`(빨강)이면 design doc의 MVP 목표(화면에 지정한 단색이
실제로 나타남)를 이 시점에 이미 달성한 것이다. Task 5~6은 이 로직을 정식
부팅 경로에 통합하고 자동 검증 스크립트로 굳히는 작업이다.

**만약 색이 검정(`#000000`)이거나 예상과 다르면:** `sleep 3`를 늘려서
다시 시도해본다 — QEMU 쪽 scanout 반영에 시간이 더 필요할 수 있다. 그래도
안 되면 위 명령에서 `-display none`을 빼고 `-serial stdio`를 추가해
`kms:` 로그가 `Attempted to kill init` 전에 전부 정상 출력됐는지(에러 없이
`set crtc N to fb N`까지 도달했는지) 먼저 확인해서 알려달라.

- [ ] **Step 4: 커밋**

```bash
git add kms/src/main.rs
git commit -m "Register framebuffer and set CRTC to draw solid red in kms"
```

---

### Task 5: `init`에 통합 — 부팅 시 `kms` 실행

**Files:**
- Modify: `init/src/main.rs`
- Modify: `kernel/make_initrd.sh`

- [ ] **Step 1: `init`이 `kms`를 fork+exec하도록 수정**

`init/src/main.rs`에서 `log_drm_device_presence` 함수 뒤에 새 함수를
추가한다:

```rust
fn run_kms() {
    let pid = unsafe { libc::fork() };
    if pid == 0 {
        let kms = CString::new("/kms").expect("CString::new failed");
        let argv: [*const libc::c_char; 2] = [kms.as_ptr(), ptr::null()];
        unsafe {
            libc::execve(kms.as_ptr(), argv.as_ptr(), environ);
        }
        let errno = unsafe { *libc::__errno_location() };
        eprintln!("tars-init: execve /kms failed (errno {})", errno);
        unsafe { libc::_exit(1) };
    } else if pid > 0 {
        let mut status: libc::c_int = 0;
        unsafe { libc::waitpid(pid, &mut status, 0) };
        println!("tars-init: kms exited with status {}", status);
    } else {
        let errno = unsafe { *libc::__errno_location() };
        println!("tars-init: fork for kms failed (errno {})", errno);
    }
}
```

`init`은 계속 PID 1로 남아 있어야 fish 셸을 그 뒤에 이어서 실행할 수
있으므로, `execve`로 자신을 `kms`로 바꿔치기하지 않고 `fork`로 자식
프로세스를 만들어 그 안에서만 `kms`를 실행한 뒤(`waitpid`로 끝날 때까지
기다림) 자신은 그대로 이어간다.

`main()`에서 `log_drm_device_presence();` 뒤에 호출을 추가한다:

```rust
    log_drm_device_presence();

    run_kms();

    setup_controlling_terminal();
```

- [ ] **Step 2: `make_initrd.sh`가 `kms` 바이너리를 포함하도록 수정**

`kernel/make_initrd.sh`에서 `fish` 복사 블록 앞(또는 뒤, 순서는 무관)에
`kms` 복사를 추가한다. 기존 `copy_lib_deps` 헬퍼 함수를 그대로
재사용한다:

```bash
cp ../init/target/release/tars-init "$WORKDIR/init"
chmod 0755 "$WORKDIR/init"

cp ../kms/target/release/kms "$WORKDIR/kms"
chmod 0755 "$WORKDIR/kms"

cp /usr/bin/fish "$WORKDIR/usr/bin/fish"
chmod 0755 "$WORKDIR/usr/bin/fish"

copy_lib_deps "$WORKDIR/init"
copy_lib_deps "$WORKDIR/kms"
copy_lib_deps "$WORKDIR/usr/bin/fish"
```

(`cp ../init/target/release/tars-init "$WORKDIR/init"`부터
`copy_lib_deps "$WORKDIR/usr/bin/fish"`까지는 기존 줄과 새로 추가한 두
줄을 합친 전체 모습이다 — 실제로는 `cp ../kms/...`와
`chmod 0755 "$WORKDIR/kms"` 두 줄, 그리고 `copy_lib_deps "$WORKDIR/kms"`
한 줄만 새로 끼워 넣으면 된다.)

- [ ] **Step 3: init 재컴파일**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/init \
  tars-devcontainer bash -c "cargo build --release"
```

Expected: 종료 코드 0.

- [ ] **Step 4: 정식 initrd 재생성**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace/kernel \
  tars-devcontainer bash -c "./make_initrd.sh"
```

Expected: 종료 코드 0, `N blocks` 출력, `kernel/initrd.cpio` 갱신됨(Task
1의 `kms` 빌드가 이미 돼 있어야 한다 — `kms/target/release/kms`가
`make_initrd.sh` 실행 시점에 존재해야 하므로, Task 4까지 순서대로
진행했다면 이미 충족돼 있다).

- [ ] **Step 5: 정식 부팅 경로로 확인**

`kernel/check-virtio-gpu.sh`(DF-M1에서 만든, `-device virtio-gpu-pci`를
붙이는 스크립트)로 확인한다 — **`kernel/check.sh`(Boot Foundation부터
있던 기본 스크립트)는 쓰지 않는다.** `kernel/check.sh`는 애초에
virtio-gpu 장치를 QEMU에 붙이지 않으므로, 그걸로 확인하면 `/dev/dri/card0`
자체가 없어서 `kms`가 정상적으로 실패하는 모습만 보게 된다(이건 버그가
아니라 장치가 없다는 당연한 결과다). `kernel/check-virtio-gpu.sh`가
virtio-gpu-pci를 붙이므로 `kms`가 실제로 성공할 조건을 준다.

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash kernel/check-virtio-gpu.sh
```

Expected: 로그에 `tars-init: /dev/dri/card0 exists` → `kms: ...` 로그들 →
`tars-init: kms exited with status 0` → `Welcome to fish, the friendly
interactive shell`이 순서대로 나오고 `PASS`(이 스크립트의 PASS 조건은
`/dev/dri/card0 exists` grep이지만, `-serial stdio`로 전체 로그가 출력되므로
fish 배너까지 눈으로 함께 확인할 수 있다).

**만약 `kms exited with status`가 0이 아니면:** `waitpid`가 돌려준
`status`는 raw wait status(하위 8비트가 exit code, 다른 비트는 시그널
정보)라 값 해석이 필요할 수 있다 — 정확한 숫자를 알려달라.

- [ ] **Step 6: 커밋**

```bash
git add init/src/main.rs kernel/make_initrd.sh kernel/initrd.cpio
git commit -m "Run kms from init during boot"
```

---

### Task 6: `display/check.sh` 확장 — 픽셀 색 검사로 공식 exit gate 검증

**Files:**
- Modify: `display/check.sh`

- [ ] **Step 1: 해상도 확인 뒤에 픽셀 색 검사 추가**

DF-M0의 `display/check.sh`는 지금 해상도가 파싱되면 바로 `PASS`한다. 이제
`kms`가 화면 전체를 빨강으로 채우므로, 좌표 `(10,10)`의 픽셀 색이
`#FF0000`인지까지 확인하도록 마지막 부분을 바꾼다.

`display/check.sh`의 아래 부분을:

```bash
echo "Captured screendump: ${SCREENSHOT} (${DIMENSIONS})"

if [[ "$DIMENSIONS" =~ ^[0-9]+x[0-9]+$ ]]; then
  echo "PASS"
  exit 0
fi

echo "FAIL: unexpected ImageMagick output: ${DIMENSIONS}"
exit 1
```

아래로 바꾼다:

```bash
echo "Captured screendump: ${SCREENSHOT} (${DIMENSIONS})"

if [[ ! "$DIMENSIONS" =~ ^[0-9]+x[0-9]+$ ]]; then
  echo "FAIL: unexpected ImageMagick output: ${DIMENSIONS}"
  exit 1
fi

if command -v magick >/dev/null 2>&1; then
  CONVERT=(magick)
else
  CONVERT=(convert)
fi

PIXEL=$("${CONVERT[@]}" "${SCREENSHOT}" -crop 1x1+10+10 +repage txt:- 2>&1) || {
  echo "FAIL: ImageMagick could not extract pixel at (10,10): ${PIXEL}"
  exit 1
}

echo "Pixel at (10,10): ${PIXEL}"

if echo "$PIXEL" | grep -qi '#FF0000'; then
  echo "PASS"
  exit 0
fi

echo "FAIL: expected red (#FF0000) at (10,10), got: ${PIXEL}"
exit 1
```

`IDENTIFY` 배열(해상도 확인용, `identify -format`)과 별도로 `CONVERT`
배열을 새로 둔 이유는 두 ImageMagick 호출 방식이 다르기 때문이다 —
`identify`는 메타데이터만 읽고, 픽셀 색을 뽑으려면 `-crop`으로 잘라낸
결과를 `txt:` 포맷으로 출력해야 한다(`magick`은 이 두 가지를 각각
`magick identify ...`, `magick <file> -crop ... txt:-`로 구분해서
받는다).

- [ ] **Step 2: 실행**

Run:
```bash
docker run --rm --platform linux/amd64 -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash display/check.sh
```

Expected: `Captured screendump: ... (WxH)`, `Pixel at (10,10): 0,0:
(255,0,0) #FF0000 srgb(255,0,0)` 형태의 줄, 마지막에 `PASS`, 종료 코드 0.

**만약 `FAIL: expected red`가 나오면:** `sleep 3`(screendump 전 대기)을
늘려서 재시도한다 — kms가 CRTC 설정을 마치기 전에 screendump가 찍혔을
가능성이 있다. 그래도 안 되면 `Pixel at (10,10): ...`에 실제로 어떤 값이
나왔는지 알려달라.

- [ ] **Step 3: 커밋**

```bash
git add display/check.sh
git commit -m "Check pixel color in display/check.sh for DF-M2 exit gate"
```

---

## DF-M2 완료 확인

Task 6의 Step 2가 `PASS`로 끝나면 design doc 기준 DF-M2의 exit
gate("DF-M0의 검증 파이프라인으로 screendump → 지정 좌표 픽셀 색이 의도한
색과 일치")를 만족하고, 동시에 design doc의 MVP 목표("QEMU에서 가상
GPU에 대해 DRM/KMS로 모드를 설정하고 framebuffer에 단색을 채워, 화면에 그
색이 실제로 나타나는 것을 자동화된 스크립트로 검증한다")를 달성한 것이다.
이 시점에서 DF-M3(종료 게이트 — 전체를 재현 가능한 단일 스크립트로 묶어
3회 연속 실행 검증) plan을 별도로 작성한다.
