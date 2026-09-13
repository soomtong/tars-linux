# NW-M1 — 커널이 NIC를 본다

Date: 2026-09-13
design: `docs/superpowers/specs/2026-09-13-tars-guest-network-design.md`
앞 milestone: `docs/superpowers/plans/2026-09-13-tars-guest-network-nw-m0.md`

M0이 재기만 했다면 M1은 처음으로 저장소 파일을 고친다. 고치는 것이 둘이다 —
커널 `.config`에 결정 2의 옵션을 넣는 것과, 열두번째가 될 체인
`net/check.sh`를 새로 만드는 것이다.

주소는 이번에 안 붙는다. `dhcpcd`도 `ip`도 이 단계의 게스트에는 없다. 이
milestone이 세우는 것은 "커널이 그 장치를 보고 드라이버를 붙였다" 하나다.

## design에서 두 자리를 고치고 들어간다

M0의 실측이 design의 문장 둘을 무효로 만들었다. plan을 쓰기 전에 그것을
분명히 해 둔다 — 안 그러면 실행 중에 "끝났다의 기준"이 흔들린다.

### 고치는 자리 1 — 끝 기준을 커널 로그로 둘 수 없다

design의 NW-M1은 이렇게 적혀 있다.

> 끝났다의 기준: 게스트 로그에 virtio-net이 잡히는 줄이 나온다.

그런데 이 커널은 virtio-net에 대해 부팅 로그에 한 줄도 안 찍는다. M0의 게스트
안에서 `dmesg | grep -i -e virtio -e eth0 -e e1000`이 아무것도 못 찾았고,
호스트가 받은 직렬 로그를 다시 훑어도 네트워크 관련 커널 줄은 넷뿐이다.

```
NET: Registered PF_NETLINK/PF_ROUTE protocol family
NET: Registered PF_INET protocol family
NET: Registered PF_UNIX/PF_LOCAL protocol family
NET: Registered PF_PACKET protocol family
```

그 넷은 NIC가 하나도 없어도 찍힌다 — M0의 실측 2가 정확히 그 상태(스택은
서고 NIC는 없음)에서 같은 줄들을 봤다. 그러니 이 줄로 양성 판정을 하면
검사가 아무것도 안 거른다.

그래서 판정을 `/sys/class/net`으로 옮긴다. sysfs는 커널이 드라이버를 붙이면서
직접 만드는 것이라 게스트에 도구가 하나도 없어도 되고, 셸의 `ls` 하나로
읽힌다. `eth0`이 거기 있다는 것은 "커널이 그 PCI 장치에 virtio_net을
붙였다"와 같은 말이다.

`NET: Registered` 넷은 버리지 않고 보조 증거로 쓴다 — 그것이 없으면
`.config`가 안 먹은 것이므로 실패의 원인이 달라진다.

### 고치는 자리 2 — M1의 "새 체인"이 곧 M3의 `net/check.sh`다

design의 M1은 "새 체인의 QEMU 줄에 결정 4의 두 줄을 더한다"고 적고, M3는
"열두번째 체인 `net/check.sh`"를 만든다고 적는다. 둘이 겹쳐 보인다.

이렇게 가른다. M1이 `net/check.sh`를 만들되 `check.sh`의 `CHAINS` 배열에는
안 넣는다. M3가 그 배열에 한 줄을 더하고 판정을 주소와 바깥 연결까지 늘린다.

근거가 셋이다.

1. M1의 끝 기준이 게스트 부팅을 요구한다. 부팅을 돌릴 무언가가 있어야 하고,
   그것을 `/tmp`의 일회용 하네스로 만들면 M2가 또 만들어야 한다.
2. design의 M1 문장 자체가 "새 체인"이 그 시점에 이미 있다고 전제한다.
3. `CHAINS`에 안 넣는 동안은 루트 게이트가 한 초도 안 늘어난다. 체인이
   자라는 동안 게이트를 건드리지 않는 것이 위험 1을 M3까지 미룬다.

## 고칠 파일

| 파일 | 무엇 |
|---|---|
| `kernel/.config` | 결정 2의 옵션 여섯을 켜고 둘을 끈다. `olddefconfig`로 되접는다 |
| `net/check.sh` | 새로 만든다. 지금은 `CHAINS` 밖이다 |
| `docs/.../2026-09-13-tars-guest-network-design.md` | 위 두 자리의 `⚠` 정정과 M1 실측 |

`check.sh`는 이번에 안 고친다. `devcontainer/Dockerfile`도, `init` 코드도,
`kernel/guest_tools.sh`도 그대로다 — 전부 M2의 일이다.

## Task 0 — 지금 `.config`가 `olddefconfig`의 고정점인지 먼저 본다

`project_kernel_config`의 규칙 넷째가 "정규화와 의도한 변경을 다른 커밋으로
나눈다"다. 지금 파일이 이미 고정점이면 그 일이 없고, 아니면 정규화를 먼저
따로 커밋해야 한다. 어느 쪽인지 모르는 채로 NET을 켜면 다음 커밋의 diff에
정규화 잡음이 섞여서 "이번 변경이 커널에 들여온 것"을 못 읽는다.

M0의 끝에서 `kernel/build`를 지웠으므로 이 빌드는 처음부터 돈다. 시간을
모르니 `run_in_background`로 돌린다.

- [x] Step 1: 지금 `.config`로 한 번 빌드한다

```bash
cd /Users/dp/Repository/tars-linux
{ time docker run --rm -v "$PWD":/workspace -w /workspace \
    tars-devcontainer bash kernel/build.sh ; } \
  > /tmp/nw/m1_task0.log 2> /tmp/nw/m1_task0.time
```

- [x] Step 2: 되접기가 필요한지 본다

```bash
cd /Users/dp/Repository/tars-linux
tail -3 /tmp/nw/m1_task0.time
diff kernel/.config kernel/build/.config && echo "고정점이다 — 정규화 커밋이 필요 없다"
```

기대: `diff`가 비어 있다. 비어 있으면 Task 1로 간다.

비어 있지 않으면 거기서 멈추고, `cp kernel/build/.config kernel/.config` 한
줄만 담은 커밋을 먼저 만든다(제목 예: `Refold the kernel config onto what it
actually builds`). 그 커밋을 만든 뒤 Task 1을 시작한다.

- [x] Step 3: baseline 값을 적어 둔다

```bash
cd /Users/dp/Repository/tars-linux
stat -f '%z' kernel/build/arch/x86/boot/bzImage
```

기대: 3,642,368. M0이 잰 값과 같아야 한다. 다르면 그 사이에 무언가 바뀐
것이므로 왜 다른지 먼저 밝힌다.

## Task 1 — `.config`에 NET을 켠다

M0의 Task 1이 `/tmp`에 만든 것과 글자 그대로 같은 편집을 이번에는 저장소
파일에 한다. 호스트가 macOS라 `sed`가 BSD판이므로 컨테이너 안에서 한다.

- [x] Step 1: 최소 편집을 넣는다

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm -v "$PWD":/workspace -w /workspace tars-devcontainer bash -c '
# 지우는 정규식이 CONFIG_UNIX98_PTYS를 안 건드리는 것이 중요하다. 이름 뒤에
# "=..." 또는 " is not set"이 바로 와야 하므로 CONFIG_UNIX98_PTYS=y는
# CONFIG_UNIX 다음이 "98_PTYS=y"라 안 맞는다. CONFIG_NET도 같은 이유로
# CONFIG_NETDEVICES를 안 지운다.
sed -i -E "/^(# )?CONFIG_(NET|INET|PACKET|UNIX|NETDEVICES|VIRTIO_NET|IPV6|NETFILTER)( is not set|=.*)\$/d" kernel/.config

cat >> kernel/.config <<"EOF"
CONFIG_NET=y
CONFIG_UNIX=y
CONFIG_INET=y
CONFIG_PACKET=y
CONFIG_NETDEVICES=y
CONFIG_VIRTIO_NET=y
# CONFIG_IPV6 is not set
# CONFIG_NETFILTER is not set
EOF
'
```

- [x] Step 2: 무엇이 지워지고 무엇이 더해졌는지 확인한다

```bash
cd /Users/dp/Repository/tars-linux
git diff --stat kernel/.config
echo "=== 지운 줄 ==="; git diff kernel/.config | grep '^-' | grep -v '^---'
echo "=== 더한 줄 ==="; git diff kernel/.config | grep '^+' | grep -v '^+++'
echo "=== UNIX98_PTYS 가 살아 있나 (1이어야 한다) ==="
grep -c '^CONFIG_UNIX98_PTYS=y' kernel/.config
```

기대: 지운 줄이 `# CONFIG_NET is not set` 하나, 더한 줄이 위의 여덟.
`CONFIG_UNIX98_PTYS=y`가 지운 줄에 나오면 정규식이 과하게 지운 것이므로
`git checkout kernel/.config`로 되돌리고 Step 1을 고친다.

- [x] Step 3: 빌드한다 (약 1분)

```bash
cd /Users/dp/Repository/tars-linux
{ time docker run --rm -v "$PWD":/workspace -w /workspace \
    tars-devcontainer bash kernel/build.sh ; } \
  > /tmp/nw/m1_task1.log 2> /tmp/nw/m1_task1.time
tail -3 /tmp/nw/m1_task1.time
```

기대: `skipping make`가 안 나온다(해시가 달라졌으므로). M0의 값이 1분 04.79초
였다.

- [x] Step 4: `olddefconfig`가 무엇을 더했는지 읽는다

```bash
cd /Users/dp/Repository/tars-linux
diff kernel/.config kernel/build/.config | head -60
echo "=== 우리가 켠 것이 살아남았나 ==="
grep -E '^(CONFIG_NET|CONFIG_INET|CONFIG_PACKET|CONFIG_UNIX|CONFIG_NETDEVICES|CONFIG_VIRTIO_NET)=' kernel/build/.config
echo "=== 우리가 끈 것이 눌려 있나 ==="
grep -E '^# CONFIG_(IPV6|NETFILTER) is not set' kernel/build/.config
echo "=== e1000 계열이 켜졌나 (하나도 없어야 한다) ==="
grep -E '^CONFIG_(E1000|E1000E|NE2K|8139|R8169|TUN|BRIDGE)=' kernel/build/.config || echo "(하나도 없다)"
```

M0에서 여섯이 전부 `=y`였고 IPv6·netfilter가 눌린 채로 남았다. 이번에도
같아야 한다. 다르면 실측이 답이므로 그 차이를 적고 design을 고친다.

`e1000` 검사가 새로 하는 것이다. 결정 3의 격리가 "그 드라이버를 안 켠다"에
통째로 얹혀 있으므로, `olddefconfig`가 `CONFIG_NETDEVICES` 아래에서
무엇을 기본으로 켰는지 직접 본다.

- [x] Step 5: 되접고 다시 빌드해 `diff`가 비는지 본다

```bash
cd /Users/dp/Repository/tars-linux
cp kernel/build/.config kernel/.config
docker run --rm -v "$PWD":/workspace -w /workspace \
  tars-devcontainer bash kernel/build.sh > /tmp/nw/m1_refold.log 2>&1
tail -2 /tmp/nw/m1_refold.log
diff kernel/.config kernel/build/.config && echo "되접기가 고정점에 도달했다"
```

기대: `diff`가 빈다. 두 번째 빌드는 `.config`가 바뀌었으므로 `skipping make`가
아니라 실제로 `make`를 부르는데, `olddefconfig`가 할 일이 없고 오브젝트도
그대로라 금방 끝난다.

- [x] Step 6: 커널 크기를 잰다

```bash
cd /Users/dp/Repository/tars-linux
stat -f '%z' kernel/build/arch/x86/boot/bzImage
git diff --stat kernel/.config
```

기대: 4,486,144 근처. M0의 값과 크게 다르면 되접기가 무언가를 더 켠 것이므로
Step 4의 diff를 다시 읽는다.

- [x] Step 7: 커밋한다

```bash
cd /Users/dp/Repository/tars-linux
git add kernel/.config
git diff --cached --stat
git commit -m "Give the kernel an IPv4 stack and one NIC driver"
```

## Task 2 — 기존 체인 하나로 회귀를 먼저 본다

루트 게이트(29분)를 돌리기 전에 12초짜리 체인 하나로 먼저 본다. M0의 실측 2가
같은 것을 마운트로 쟀고, 이번에는 저장소 파일이 바뀐 상태에서 같은 답이
나오는지 확인하는 자리다.

- [x] Step 1: `device` 체인을 돌린다

```bash
cd /Users/dp/Repository/tars-linux
{ time docker run --rm -v "$PWD":/workspace -w /workspace \
    tars-devcontainer bash device/check.sh ; } \
  > /tmp/nw/m1_device.log 2> /tmp/nw/m1_device.time
echo "exit=$?"; tail -3 /tmp/nw/m1_device.time; tail -3 /tmp/nw/m1_device.log
```

기대: `PASS`. 시간이 12초 근처다(M0에서 baseline 11.800초 · NET 12.183초).

- [x] Step 2: 실패했으면 무엇이 달라졌는지 본다

```bash
tail -60 /tmp/nw/m1_device.log
```

체인이 실패하면 마지막 60줄을 스스로 뿜는다. `e1000`이나 `eth0` 같은 글자가
보이면 결정 3의 전제가 이 상태에서는 안 서는 것이고, 그러면 기존 체인 열
개에 `-net none`을 더하는 쪽으로 방향을 돌린다(design 위험 4).

## Task 3 — `net/check.sh`를 만든다

체인이 하는 일의 순서는 이렇다.

1. 자기가 부팅할 것을 스스로 빌드한다(진입 검사 `require_build_steps`가
   이것을 요구한다. `BUILD_STEPS` 넷을 전부 부른다).
2. NIC를 물린 게스트를 띄운다.
3. 터미널이 프롬프트를 그릴 때까지 기다린다.
4. monitor로 `ls /sys/class/net`을 쳐서 `eth0`을 본다.
5. 직렬 로그에서 스택이 섰는지, `e1000`이 안 보이는지 확인한다.
6. 전원 버튼으로 끈다.

- [x] Step 1: 디렉터리를 만든다

```bash
cd /Users/dp/Repository/tars-linux
mkdir -p net
```

- [x] Step 2: `net/check.sh`를 Write 도구로 만든다

```bash
#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# NW 체인 — 커널이 NIC를 본다.
#
# 이 체인이 증명하는 사슬:
#   .config의 CONFIG_NET/INET/PACKET/UNIX → 커널에 IPv4 스택이 선다
#   CONFIG_NETDEVICES + CONFIG_VIRTIO_NET → 장치 계층과 드라이버가 있다
#   QEMU의 -netdev user + -device virtio-net-pci → 게스트에 그 PCI 장치가 붙는다
#   → 커널이 드라이버를 붙이고 /sys/class/net/eth0을 만든다
#
# 주소는 아직 없다. dhcpcd도 ip도 이 단계의 게스트에 없다 — 그것은 NW-M2다.
#
# 왜 커널 로그로 판정하지 않는가. NW-M0의 실측이 답이다. 이 커널은
# virtio-net에 대해 부팅 로그에 한 줄도 안 찍고, 찍히는 것은
# `NET: Registered PF_*` 넷뿐인데 그 넷은 NIC가 하나도 없어도 찍힌다
# (실측 2가 정확히 그 상태에서 같은 줄들을 봤다). 그래서 그 넷은 양성
# 판정이 아니라 "스택이 섰다"의 보조 증거로만 쓴다.
#
# 대신 /sys/class/net을 본다. sysfs는 커널이 드라이버를 붙이면서 직접
# 만드는 것이라 게스트에 도구가 하나도 없어도 되고 셸의 ls 하나로 읽힌다.
#
# 이 체인은 아직 check.sh의 CHAINS에 없다. 게이트에 들이는 것은 NW-M3이고
# 그때 판정이 주소와 바깥 연결까지 늘어난다. 지금은 단독으로 돌린다.

# $GUEST_MEM과 type_keys·wait_for_screen 셋 다 쓴다.
source ../gate_lib.sh

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
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

# 45455=TF, 45456=CP, 45457=IP, 45458=PM, 45459=HD, 45460=TR, 45461=CM,
# 45462=HI, 45463=UT, 45471=RM. 겹치지 않는 번호를 쓰는 이유는 죽다 만
# QEMU가 남았을 때 엉뚱한 게스트에 명령을 보내지 않기 위해서다.
MONITOR_PORT=45464

LOG="$(mktemp)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1"
  shift
  echo "--- markers ---"
  local marker
  for marker in \
    "NET: Registered PF_INET protocol family" \
    "NET: Registered PF_PACKET protocol family" \
    "NET: Registered PF_UNIX/PF_LOCAL protocol family" \
    "tars-init: started console shell" \
    "terminal: screen>"; do
    if grep -a "$marker" "$LOG" >/dev/null; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  local pattern
  for pattern in "$@"; do
    # `|| true`가 없으면 이 루프가 첫 패턴에서 죽는다 — 안 맞는 grep은
    # 종료 코드 1이고 pipefail이 그것을 파이프라인 코드로 올린다.
    grep -a "$pattern" "$LOG" | head -3 | sed 's/^/  /' || true
  done
  echo "--- last 60 lines ---"
  tail -n 60 "$LOG"
  exit 1
}

# -device virtio-gpu-pci가 있어야 터미널이 뜨고 screen> 줄이 나온다.
# 그 줄이 이 체인의 타이핑 대기가 서는 자리다(gate_lib.sh의 wait_for_screen).
#
# 결정 4의 두 줄이 아래 -netdev과 -device다. tap이 아니라 user(SLIRP)인
# 이유는 특권이 필요 없기 때문이고, 이 게이트가 아무 특권 없이 도는 성질을
# 네트워크 하나 때문에 버리지 않는다.
qemu-system-x86_64 \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -netdev user,id=n0 \
  -device virtio-net-pci,netdev=n0 \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -a "terminal: screen>" "$LOG" >/dev/null; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || fail "terminal never rendered a prompt"

# ── 검사 1: 스택이 섰나 ───────────────────────────────────────────────
# 양성 판정이 아니라 보조 증거다. 이 셋이 없으면 .config가 안 먹은 것이고,
# 아래 eth0 검사가 실패했을 때 원인이 드라이버가 아니라 스택이 된다.
for marker in \
  "NET: Registered PF_INET protocol family" \
  "NET: Registered PF_PACKET protocol family" \
  "NET: Registered PF_UNIX/PF_LOCAL protocol family"; do
  if ! grep -a "$marker" "$LOG" >/dev/null; then
    fail "the kernel never registered the network stack: ${marker}" "NET: Registered"
  fi
done
echo "the kernel registered PF_INET, PF_PACKET and PF_UNIX"

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || fail "could not connect to the QEMU monitor" "terminal: screen>"

# ── 검사 2: 커널이 그 장치에 드라이버를 붙였나 ────────────────────────
# sendkey의 키 이름은 전부 소문자이고 공백은 spc, 슬래시는 slash다.
echo "=== typing 'ls /sys/class/net' ==="
type_keys l s spc slash s y s slash c l a s s slash n e t ret

if ! wait_for_screen "eth0"; then
  fail "no eth0 under /sys/class/net — the kernel did not bind virtio_net" \
    "terminal: screen>"
fi
echo "the kernel made /sys/class/net/eth0"

# ── 검사 3: QEMU가 붙인 기본 NIC는 안 보인다 ──────────────────────────
# 결정 3이 통째로 얹혀 있는 성질이다. 우리가 e1000 드라이버를 안 켜므로
# 게스트가 그 PCI 장치를 보고도 그냥 넘어간다. 이 검사가 없으면 기존 체인
# 열 개가 조용히 NIC를 하나 더 갖게 되는 날을 못 잡는다.
if grep -aiE "e1000|8139|ne2k|r8169" "$LOG" >/dev/null; then
  fail "a NIC driver we did not turn on showed up in the kernel log" \
    "e1000" "8139" "ne2k" "r8169"
fi
echo "no driver we did not turn on appeared"

# ── 끈다 ──────────────────────────────────────────────────────────────
echo "=== sending system_powerdown to the guest ==="
echo "system_powerdown" >&3
sleep 0.3

exec 3<&-
exec 3>&-

GONE=0
for _ in $(seq 1 30); do
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then GONE=1; break; fi
  sleep 1
done
[ "$GONE" = "1" ] || fail "the guest did not switch itself off" \
  "tars-init: shutdown requested"

# SL-M2가 세운 것. 유예가 다 지나가면 무언가가 SIGTERM을 안 받은 것이다.
if grep -a "grace period expired" "$LOG" >/dev/null; then
  fail "something outlived SIGTERM and burned the whole grace period" \
    "grace period expired" "tars-init: sent SIG"
fi

echo "PASS"
exit 0
```

- [x] Step 3: 실행 권한을 주고 파일이 맞는지 본다

```bash
cd /Users/dp/Repository/tars-linux
chmod +x net/check.sh
ls -l net/check.sh
bash -n net/check.sh && echo "문법이 맞다"
```

- [x] Step 4: 진입 검사가 요구하는 것을 미리 맞춰 본다

`check.sh`의 `require_build_steps`가 주석이 아닌 줄에서 `BUILD_STEPS` 넷을
찾는다. M3가 `CHAINS`에 이 체인을 더하는 순간 그 검사가 돌기 시작하므로
지금 맞춰 둔다. `require_no_early_exit_pipe`는 파이프 뒤의 `grep -q`를
막는다 — 이 체인은 `-q` 대신 `>/dev/null`을 쓴다.

```bash
cd /Users/dp/Repository/tars-linux
echo "=== BUILD_STEPS 넷이 주석 아닌 줄에 있나 ==="
body="$(grep -vE '^[[:space:]]*#' net/check.sh)"
for step in 'cd ../kernel && ./build.sh)' 'cd ../init && zig build)' './prepare.sh' './make_initrd.sh'; do
  case "$body" in *"$step"*) echo "  있다   $step" ;; *) echo "  없다   $step" ;; esac
done
echo "=== 파이프 뒤의 grep -q 가 있나 (하나도 없어야 한다) ==="
grep -nE '\|[^|]*\b(grep|rg)\b[^|]*-[a-zA-Z]*q' net/check.sh || echo "(하나도 없다)"
```

기대: 넷 다 "있다", 파이프 뒤 `-q`는 하나도 없다.

- [x] Step 5: 체인을 단독으로 돌린다

```bash
cd /Users/dp/Repository/tars-linux
{ time docker run --rm -v "$PWD":/workspace -w /workspace \
    tars-devcontainer bash net/check.sh ; } \
  > /tmp/nw/m1_net.log 2> /tmp/nw/m1_net.time
echo "exit=$?"; tail -3 /tmp/nw/m1_net.time; tail -20 /tmp/nw/m1_net.log
```

기대: `PASS`. 화면에 `eth0`과 `lo`가 보인다.

실패했을 때 먼저 볼 곳은 아래 "실패했을 때 어디를 보는가" 표다.

## Task 4 — 반사실. NIC를 빼면 이 체인이 죽는가

검사가 실제로 NIC에 걸려 있는지 확인한다. SD-M2와 BH-M2가 같은 일을 했고,
둘 다 "겨냥한 검사가 아니라 앞의 검사에 걸린다"를 배웠다 — 그 구분을 여기서도
적는다.

저장소 파일은 한 글자도 안 바꾼다. `/tmp` 사본을 `-v`로 덮어씌운다.

- [x] Step 1: NIC 두 줄을 뺀 사본을 만든다

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm -v "$PWD":/workspace -v /tmp/nw:/tmp/nw -w /workspace \
  tars-devcontainer bash -c '
  sed -e "/-netdev user,id=n0/d" -e "/-device virtio-net-pci,netdev=n0/d" \
    net/check.sh > /tmp/nw/net_no_nic.sh'
echo "=== 두 줄이 빠졌나 (0이어야 한다) ==="
grep -c 'virtio-net-pci' /tmp/nw/net_no_nic.sh || true
echo "=== 줄 수 (원본 - 2) ==="
wc -l net/check.sh /tmp/nw/net_no_nic.sh
```

- [x] Step 2: 그 사본으로 돌려서 죽는 것을 본다

```bash
cd /Users/dp/Repository/tars-linux
docker run --rm -v "$PWD":/workspace \
  -v /tmp/nw/net_no_nic.sh:/workspace/net/check.sh:ro \
  -w /workspace tars-devcontainer bash net/check.sh \
  > /tmp/nw/m1_counter.log 2>&1
echo "exit=$?"
grep -aE '^(FAIL|PASS|the kernel|no driver)' /tmp/nw/m1_counter.log
```

기대: 종료 코드가 1이고 `FAIL: no eth0 under /sys/class/net`이 나온다.
그 앞의 검사 1(`the kernel registered PF_INET…`)은 통과해야 한다 — 스택은
NIC와 무관하게 서기 때문이다. 그 둘이 갈리는 것이 이 반사실의 값이다.

`PASS`가 나오면 검사가 NIC에 안 걸려 있는 것이므로 Task 3 Step 2로 돌아간다.
검사 1에서 죽으면 겨냥한 자리가 아니라 앞에서 죽은 것이므로 왜인지 먼저
밝힌다.

- [x] Step 3: 저장소 파일이 안 바뀐 것을 확인한다

```bash
cd /Users/dp/Repository/tars-linux
git status --short
```

기대: `net/check.sh`가 신규(`??`)로만 나오고 내용이 우리가 쓴 그대로다.
마운트는 컨테이너 안에서만 유효하므로 호스트 파일은 안 바뀐다.

- [x] Step 4: 커밋한다

```bash
cd /Users/dp/Repository/tars-linux
git add net/check.sh
git diff --cached --stat
git commit -m "Boot one guest with a NIC and ask the kernel what it found"
```

## Task 5 — 루트 게이트로 열한 체인이 그대로인지 본다

이 milestone이 바꾼 커널은 열한 체인 전부가 부팅하는 커널이다. `device`
하나로는 열한 개를 대변하지 못한다. 위험 4가 이 자리이고, 여기서 한 번
치르면 M2·M3가 그 위험을 다시 안 진다.

약 29분이라 Bash 도구의 10분 타임아웃을 넘는다. `run_in_background`로 돌린다.

- [x] Step 1: 돌린다

```bash
cd /Users/dp/Repository/tars-linux
{ time docker run --rm -v "$PWD":/workspace -w /workspace \
    tars-devcontainer bash check.sh ; } \
  > /tmp/nw/m1_gate.log 2> /tmp/nw/m1_gate.time
```

- [x] Step 2: 결과를 읽는다

```bash
cd /Users/dp/Repository/tars-linux
tail -30 /tmp/nw/m1_gate.log
tail -5 /tmp/nw/m1_gate.time
echo "=== skipping make 횟수 (체인 11 × 3 − 1 = 32 여야 한다) ==="
grep -ac "skipping make" /tmp/nw/m1_gate.log || true
```

기대: 3/3. 시간이 29분 근처다(가장 최근 기준선이 29분 38.52초이고 이
게이트의 잡음이 ±3분이다).

`skipping make`가 32가 아니면 커널 빌드 판정이 흔들린 것이다. 33이면
`clean()`이 지운 자리에서도 건너뛴 것이라 잘못이고, 31 이하면 무언가가
`.config`를 건드리고 있다.

- [x] Step 3: 실패했으면 어느 체인인지 가른다

```bash
grep -anE '^(PASS|FAIL|=== )' /tmp/nw/m1_gate.log | tail -40
```

체인 하나가 죽었으면 그 체인만 단독으로 다시 돌려서 로그를 본다. NET을 켠
것이 원인인지 가르는 방법은 `git stash`로 `.config`를 되돌려 같은 체인을
돌려 보는 것이다.

## Task 6 — design과 HANDOFF를 갱신하고 커밋한다

- [x] Step 1: design에 `⚠` 정정 둘을 단다

`docs/superpowers/specs/2026-09-13-tars-guest-network-design.md`의
"### NW-M1 — 커널이 NIC를 본다" 절 바로 아래에 붙인다. 두 가지다.

- 끝 기준을 커널 로그로 둘 수 없다는 것(M0의 실측이 근거). 실제로 쓴 판정이
  `/sys/class/net/eth0`이라는 것.
- M1이 `net/check.sh`를 만들되 `CHAINS`에는 안 넣는다는 것. M3가 그 배열에
  한 줄을 더한다는 것.

- [x] Step 2: design 끝에 M1의 실측 절을 더한다

`## NW-M1이 실행으로 증명한 것`으로 절을 만들고 적는다.

- `.config`가 되접기 전후로 몇 줄 늘었나(`git diff --stat`의 값)
- `olddefconfig`가 `CONFIG_NETDEVICES` 아래에서 무엇을 켰나. 특히
  `CONFIG_E1000` 계열이 하나도 안 켜진 것
- `bzImage`의 최종 크기
- `net/check.sh` 단독 시간
- 반사실이 어느 검사에서 죽었나
- 루트 게이트 시간과 판정, `skipping make` 횟수

- [x] Step 3: HANDOFF를 갱신한다

`HANDOFF.md`에서 고칠 자리가 셋이다.

- 제목과 "지금 어디인가"를 M1이 끝난 상태로
- "NW가 지금까지 한 일" 표에 커밋 셋을 더한다
- "바로 다음에 할 것"을 M2 plan 쓰기로 바꾼다
- "게이트 현황"의 최근 값에 이번 회차를 더한다

- [x] Step 4: 커밋한다

```bash
cd /Users/dp/Repository/tars-linux
git add docs/superpowers/specs/2026-09-13-tars-guest-network-design.md \
        docs/superpowers/plans/2026-09-13-tars-guest-network-nw-m1.md \
        HANDOFF.md
git diff --cached --stat
git commit -m "Hand off with the kernel seeing a NIC and a chain that says so"
```

## 실패했을 때 어디를 보는가

| 증상 | 먼저 볼 곳 |
|---|---|
| `olddefconfig`가 우리가 끈 것을 되켰다 | `project_kernel_config`의 "누를 수 있는 항목과 없는 항목". 프롬프트가 없거나 `if EXPERT`인 것은 우리가 무엇을 적든 되살아난다 |
| 되접은 뒤 `diff`가 안 빈다 | 두 번째 빌드가 실제로 돌았는지. `skipping make`가 나왔으면 스탬프가 옛 `.config`의 것이라 `olddefconfig`가 안 돈 것이다 |
| `eth0`이 안 보인다 | `kernel/build/.config`의 `CONFIG_VIRTIO_NET=y`. 그 다음 `-device virtio-net-pci,netdev=n0`이 QEMU 줄에 살아 있는지 |
| 터미널이 프롬프트를 안 그린다 | `-device virtio-gpu-pci`가 빠졌는지. 그것이 없으면 `/dev/dri/card0`이 없어 init이 터미널을 포기한다 |
| monitor에 못 붙는다 | 45464를 다른 무언가가 쓰고 있는지. 죽다 만 QEMU가 남아 있을 수 있다 |
| `grace period expired`로 죽는다 | 이 게스트에는 dhcpcd가 없으므로 네트워크와 무관하다. SL-M2가 세운 검사이고 원인은 다른 자식이다 |
| 루트 게이트에서 체인 하나만 죽는다 | 그 체인을 단독으로 돌리고, `git stash`로 `.config`를 되돌려 같은 체인을 다시 돌려서 NET 때문인지 가른다 |

## 이 milestone이 안 하는 것

`tars.conf`의 `net=` 키를 안 만든다. `init`에 `ioctl`을 안 넣는다. 게스트에
`dhcpcd`도 `ip`도 `curl`도 안 넣는다. `devcontainer/Dockerfile`을 안 고친다.
`check.sh`의 `CHAINS`를 안 고친다.

그 다섯이 전부 M2와 M3의 일이고, M0의 실측이 각각에 숫자를 붙여 두었다 —
design 끝의 "M0이 M2에 넘기는 것" 표가 그 목록이다.

## 실제로 돌린 것이 이 plan과 갈린 자리 하나

Task 3 Step 2의 검사 3을 한 줄이 아니라 루프로 넣었다. plan에는 이렇게
적혀 있다.

```bash
if grep -aiE "e1000|8139|ne2k|r8169" "$LOG" >/dev/null; then
```

실제 파일은 이렇다.

```bash
for driver in e1000 8139 ne2k r8169 pcnet32 vmxnet; do
  if grep -ai "$driver" "$LOG" >/dev/null; then
```

이유가 둘이다. `check.sh`의 `require_no_early_exit_pipe`가 쓰는 정규식이
파이프 문자를 구분자로 읽는데, 대안을 한 줄에 몰면 그 lint가 이 줄을 어떻게
읽을지가 사람 눈에 안 보인다. 그리고 루프가 어느 드라이버에 걸렸는지를
실패 메시지에 담는다 — 한 줄짜리는 "무언가 걸렸다"까지만 말한다.

나머지는 plan대로 돌았다. 특히 Task 0의 `diff`가 비어서 정규화 커밋이
따로 필요 없었고, Task 4의 반사실이 겨냥한 검사에서 정확히 죽었다.

측정한 값은 전부 design의 "NW-M1이 실행으로 증명한 것" 절(실측 11~16)에
있다.
