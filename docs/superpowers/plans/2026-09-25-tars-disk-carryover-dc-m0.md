# DC-M0 — 설정 파티션이 PID 1보다 늦게 생기는 틈을 재현하고 잰다

> 이 plan을 실행하는 사람에게: 이 milestone은 저장소의 코드를 한 줄도 안
> 고친다. 저장소에 들어가는 것은 design 문서의 실측 절 하나다. 하네스는
> `/tmp/dcm0/` 아래에만 산다. DI-M0 · TS-M0의 plan과 같은 형식이고 TDD 구조가
> 아니다.

Goal: DC design의 결정 3(틈을 `usb-storage.delay_use`로 벌린다)이 되는지,
그리고 틈이 몇 ms인지를 부팅 일곱으로 답해서 DC-M1의 상한(초안 5초)을 확정한다.

Architecture: 64MiB 디스크에 MBR로 p1 · p2를 만들고 p2에 라벨 `tars-dcm0`의
ext2를 굽는다. `init`은 파티션 표의 종류를 안 보고 `/dev/sda2`라는 노드와 그
안의 라벨만 보므로 GPT가 아니어도 된다(컨테이너에 `sfdisk`가 없다 — `perl`로
MBR 16바이트 두 칸을 쓴다). 그 디스크를 `-kernel` 부팅에 `usb-storage`로 한 번
(`delay_use=3`), 기본값으로 한 번, `nvme`로 다섯 번 붙이고, 커널 cmdline에
`tars.installed`를 줘서 `init`이 후보 마흔둘을 훑게 한다. `CONFIG_PRINTK_TIME=y`
라서 `Run /init`의 시각과 `sda: sda1 sda2`(또는 `nvme0n1: p1 p2`)의 시각을 바로
견준다.

Tech Stack: bash · QEMU(`-kernel` · q35 기본 머신 · qemu-xhci · usb-storage ·
nvme) · e2fsprogs(`mke2fs -E offset=`) · perl · 기존 산출물
(`kernel/build/arch/x86/boot/bzImage` · `kernel/initrd.cpio`)

---

## 시제품에서 이미 본 것 (plan을 쓰며, 2026-09-25)

plan을 쓰기 전에 아래 하네스를 한 번 돌렸다(56초). 실행은 이 값이 다시 나오는지
본다.

| 부팅 | 설정 노드가 생긴 시각 | `Run /init` | `init`의 판정 |
|---|---|---|---|
| usb-delay3 | `sda: sda1 sda2` 3.99초 | 2.30초 | `no disk labelled tars-* among 42 candidates` |
| usb-default | 1.94초 | 2.32초 | `config storage /dev/sda2` |
| nvme-1~5 | 0.55~0.58초 | 2.25~2.32초 | `config storage /dev/nvme0n1p2` |

그리고 design의 확인 2가 추측한 이유가 틀렸다. `Run /init` 바로 앞에
`Freeing initrd memory: 41788K`가 2.26초에 있다 — 커널이 42MB initramfs를 푸는
데 약 1.7초를 쓰고, 그동안 NVMe도 기본값 USB도 다 붙는다. 게이트는 arm64 위의
TCG라 이 풀기가 느리다. 틈을 덮은 것은 NVMe의 속도가 아니라 에뮬레이션의
느림이다.

## Task 1: 하네스를 놓는다

**Files:**
- Create: `/tmp/dcm0/probe.sh` (저장소 밖)

- [ ] **Step 1: 하네스 전문**

```bash
#!/usr/bin/env bash
# DC-M0 하네스. 코드는 안 고친다 — 설치된 부팅(tars.installed)에서 설정 파티션이
# PID 1보다 늦게 생길 때 init이 무엇을 하는지, 그리고 그 틈이 몇 ms인지 잰다.
set -uo pipefail
cd /workspace
source gate_lib.sh
OUT=/tmp/dcm0
IMG=$OUT/disk.img

# 64MiB 디스크. MBR에 p1(1MiB, LBA 2048) · p2(나머지, LBA 4096). init은 표의
# 종류를 안 본다 — /dev/sda2라는 노드와 그 안의 ext2 라벨만 본다.
rm -f "$IMG"; truncate -s 64M "$IMG"
perl -e '
  open my $f, "+<", $ARGV[0] or die;
  sub ent { pack("C C3 C C3 V V", 0, 0,0,0, 0x83, 0,0,0, $_[0], $_[1]) }
  seek $f, 446, 0;
  print $f ent(2048, 2048), ent(4096, 131072 - 4096), "\0" x 32, "\x55\xAA";
' "$IMG"
mke2fs -q -t ext2 -L tars-dcm0 -E offset=$((4096 * 512)) "$IMG" $(( (131072 - 4096) / 2 ))k

# boot <이름> <cmdline> <qemu 장치 인자...>
boot() {
  local name="$1" cmdline="$2"; shift 2
  local log="$OUT/boot-$name.log"
  : > "$log"
  qemu-system-x86_64 -m "$GUEST_MEM" \
    -kernel kernel/build/arch/x86/boot/bzImage -initrd kernel/initrd.cpio \
    -append "$cmdline" -vga none -display none -monitor none -no-reboot \
    -serial file:"$log" "$@" &
  local pid=$!
  for _ in $(seq 1 60); do
    grep -aq "tars-init: started console shell" "$log" && break
    sleep 0.5
  done
  sleep 5   # delay_use 뒤에 sda가 붙는 것까지 로그에 남긴다
  kill "$pid"; wait "$pid" 2>/dev/null
  echo "=== $name ($cmdline)"
  grep -aE 'Run /init|sd [0-9:]+: \[sda\] Attached|sda: sda1|nvme0n1: p1|tars-init: (config storage|no disk|mounted)' "$log" \
    | sed 's/\r//' | sed 's/^/  /'
}

USB=(-device qemu-xhci,id=xhci -drive file="$IMG",if=none,id=u,format=raw -device usb-storage,bus=xhci.0,drive=u)
NVME=(-drive file="$IMG",if=none,id=n,format=raw -device nvme,drive=n,serial=dcm0)

boot usb-delay3 "console=ttyS0 tars.installed usb-storage.delay_use=3" "${USB[@]}"
boot usb-default "console=ttyS0 tars.installed" "${USB[@]}"
for i in 1 2 3 4 5; do
  boot nvme-$i "console=ttyS0 tars.installed" "${NVME[@]}"
done
```

- [ ] **Step 2: 산출물이 있는지 본다**

Run: `ls -la kernel/build/arch/x86/boot/bzImage kernel/initrd.cpio`
Expected: 둘 다 있다. 없으면 `install/check.sh`의 빌드 여섯 줄을 먼저 돌린다.

## Task 2: 돌린다

- [ ] **Step 1: 부팅 일곱 (약 1분)**

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/dcm0:/tmp/dcm0 -w /workspace \
  tars-devcontainer bash /tmp/dcm0/probe.sh > /tmp/dcm0/run.log 2>&1
grep -aE '^=== |^  ' /tmp/dcm0/run.log
grep -aE 'Freeing initrd|Run /init|sda: sda1|no disk' /tmp/dcm0/boot-usb-delay3.log
```

Expected:
- `usb-delay3`에 `tars-init: no disk labelled tars-* among 42 candidates`가 있고,
  `sda: sda1 sda2`의 시각이 `Run /init`보다 1초 이상 뒤다. 이것이 틈의 재현이다.
- `usb-default`와 `nvme-1`~`5`는 전부 `config storage`와 `mounted ext2 at /config`.
  설정 노드의 시각이 `Run /init`보다 앞이다.
- `Command line:`에 `usb-storage.delay_use=3`이 그대로 있다(design 위험 1).

- [ ] **Step 2: 상한을 정한다**

usb-delay3의 틈(`sda2` 시각 − `Run /init` 시각)이 5초보다 충분히 작으면(3초
미만) 상한 5초를 확정한다. 아니면 design 결정 2를 고친다.

## Task 3: design에 적고 커밋한다

**Files:**
- Modify: `docs/superpowers/specs/2026-09-25-tars-disk-carryover-design.md`

- [ ] **Step 1: design 끝에 "DC-M0이 실행으로 증명한 것" 절**

실측 1(틈이 재현됐다 · 시각 표), 실측 2(틈을 덮던 것은 initramfs 풀기다 — 확인
2의 추측을 바로잡는다), 실측 3(상한). `Status:` 줄을 "M0 끝, M1이 다음"으로.

- [ ] **Step 2: 커밋**

```bash
git add docs/superpowers/plans/2026-09-25-tars-disk-carryover-dc-m0.md \
        docs/superpowers/specs/2026-09-25-tars-disk-carryover-design.md
git commit -m "Close DC-M0: the config partition can come 1.7s after init looked"
```
