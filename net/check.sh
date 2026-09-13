#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"
REPO_ROOT="$(cd .. && pwd)"

# NW 체인 — 커널이 NIC를 보고 게스트가 주소를 받는다.
#
# 이 체인이 증명하는 사슬:
#   .config의 CONFIG_NET/INET/PACKET/UNIX → 커널에 IPv4 스택이 선다
#   CONFIG_NETDEVICES + CONFIG_VIRTIO_NET → 장치 계층과 드라이버가 있다
#   QEMU의 -netdev user + -device virtio-net-pci → 게스트에 그 PCI 장치가 붙는다
#   → 커널이 드라이버를 붙이고 /sys/class/net/eth0을 만든다
#   설정 디스크의 net=dhcp → init이 그 링크를 UP으로 올리고 dhcpcd를 띄운다
#   → dhcpcd가 SLIRP에서 10.0.2.15를 받고 hook이 /etc/resolv.conf를 쓴다
#
# M1까지는 첫 넷이 전부였다. M2가 뒤의 둘을 더했고, 그래서 이 체인이
# 게스트에 디스크를 물리는 여섯째 체인이 됐다.
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

# NW-M2. 설정 디스크를 굽는다. config/check.sh와 같은 자리이고 다른 것은
# 이 디스크가 빈 것이 아니라는 것이다 — net=dhcp 한 줄을 debugfs로 미리
# 담아 굽는다. 그래서 이 체인은 게스트에 타이핑으로 설정을 쓰지 않는다.
if ! ./make_disk.sh; then
  echo "FAIL: config disk build failed"
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
    "tars-init: loaded /config/tars.conf" \
    "tars-init: net link eth0 is up" \
    "tars-init: started dhcpcd on eth0" \
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

# -device virtio-gpu-pci가 있어야 /dev/dri/card0이 생기고 터미널이 뜬다.
# 그 터미널이 찍는 screen> 줄이 이 체인의 타이핑 대기가 서는 자리다
# (gate_lib.sh의 wait_for_screen). boot/check.sh가 반대 방향으로 같은 것을
# 쓴다 — 그 체인은 card0이 없어야 해서 이 장치를 일부러 안 준다.
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
  -drive file="${REPO_ROOT}/out/net.img",if=virtio,format=raw \
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
# tools/check.sh:350이 같은 모양으로 경로를 친다.
echo "=== typing 'ls /sys/class/net' ==="
type_keys l s spc slash s y s slash c l a s s slash n e t ret

if ! wait_for_screen "eth0"; then
  fail "no eth0 under /sys/class/net — the kernel did not bind virtio_net" \
    "terminal: screen>"
fi
echo "the kernel made /sys/class/net/eth0"

# ── 검사 3: 설정이 읽혔고 net=dhcp가 실효값인가 ───────────────────────
# 이 둘이 없으면 아래 판정이 무엇을 증명하는지가 흐려진다. 디스크가 안
# 붙었는데 주소가 붙는 경우는 없지만, 디스크가 안 붙어서 주소가 안 붙는
# 것과 코드가 틀려서 안 붙는 것은 다른 실패다.
if ! grep -a "tars-init: loaded /config/tars.conf" "$LOG" >/dev/null; then
  fail "the guest never read the config disk" "tars-init: mounted ext2" \
    "tars-init: created /config/tars.conf"
fi
if ! grep -aE "tars-init: config shell=.* net=dhcp" "$LOG" >/dev/null; then
  fail "the config disk did not turn the network on" "tars-init: config shell="
fi
echo "the guest read net=dhcp off the config disk"

# ── 검사 4: init이 한 일 둘 ───────────────────────────────────────────
# design 결정 6이 그은 경계가 이 두 줄이다. 우리 코드가 하는 일은 링크를
# 올리는 것과 dhcpcd를 띄우는 것이고, 그 뒤는 전부 dhcpcd다.
for marker in \
  "tars-init: net link eth0 is up" \
  "tars-init: started dhcpcd on eth0"; do
  if ! grep -a "$marker" "$LOG" >/dev/null; then
    fail "init did not do its half of the work: ${marker}" "tars-init: net"
  fi
done
echo "init raised the link and started dhcpcd"

# ── 검사 5: dhcpcd가 리스를 받았나 ────────────────────────────────────
# SLIRP의 주소 규칙이 고정이라 값을 박을 수 있다 — 게스트 10.0.2.15/24,
# 게이트웨이 10.0.2.2, DNS 10.0.2.3(design 결정 4). 이 값을 우리 코드에는
# 안 박는다. dhcpcd가 받아 오는 것이고, 체인만 그것이 무엇인지 안다.
#
# 이 대기가 plan에 없던 것이고, 없이 돌린 1회차가 아래 검사 6에서 죽었다.
# init이 `started dhcpcd`를 찍은 시점과 dhcpcd가 실제로 DHCP를 요청하는
# 시점 사이에 간격이 있다 — 시리얼 로그에서 `started dhcpcd`가 256번째 줄,
# `soliciting a DHCP lease`가 3745번째 줄이었고 그 사이 전부가 터미널의
# 렌더 로그였다. 즉 체인이 프롬프트를 보자마자 치면 언제나 너무 이르다.
#
# 화면이 아니라 시리얼 로그로 묻는 이유는 이것이 dhcpcd 자신의 말이기
# 때문이다. 검사 6이 사람의 눈으로 같은 사실을 다시 확인한다.
LEASED=0
for _ in $(seq 1 60); do
  if grep -a "eth0: leased 10.0.2.15" "$LOG" >/dev/null; then LEASED=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$LEASED" = "1" ] || fail "dhcpcd never got a lease from SLIRP" \
  "eth0: soliciting" "dhcpcd-10"
echo "dhcpcd leased 10.0.2.15 from SLIRP"

# ── 검사 6: 사람이 그것을 볼 수 있나 ──────────────────────────────────
# 검사 5와 같은 사실을 다른 자리에서 묻는다. 저쪽은 dhcpcd의 말이고 이쪽은
# 커널이 실제로 그 주소를 인터페이스에 갖고 있는가다 — dhcpcd가 리스를
# 받고도 주소를 못 붙이는 경우가 갈린다.
#
# `-4`를 준 것이 1회차에서 진단을 흐렸다. iproute2는 family 필터를 걸면 그
# family의 주소가 없는 인터페이스를 링크 줄조차 안 찍고 통째로 생략한다 —
# 주소가 붙기 전에 치면 에러가 아니라 빈 출력이 나온다. 그래서 "명령이
# 실패했다"와 "아직 주소가 없다"가 화면에서 구별되지 않았다. 검사 5가
# 그 순서를 보장하므로 이제 이 자리에서 빈 출력이 나오면 진짜 문제다.
#
# 점을 이스케이프하는 이유는 wait_for_screen의 패턴이 ERE이기 때문이다.
echo "=== typing 'ip -4 addr show eth0' ==="
type_keys i p spc minus 4 spc a d d r spc s h o w spc e t h 0 ret

if ! wait_for_screen "10\.0\.2\.15"; then
  fail "the address dhcpcd leased is not on the interface" "terminal: screen>"
fi
echo "the guest holds 10.0.2.15"

# ── 검사 7: 이름을 풀 자리가 생겼나 ───────────────────────────────────
# M0의 실측 6이 이 검사의 이유다. 그때는 주소가 붙었는데 /etc/resolv.conf가
# 아예 없었다 — install_tool이 바이너리만 복사해서 dhcpcd의 hook이 initrd에
# 없었기 때문이다. 증상이 "이름만 안 풀린다"라 원인에서 멀고, 그래서 게이트가
# 직접 본다.
echo "=== typing 'cat /etc/resolv.conf' ==="
type_keys c a t spc slash e t c slash r e s o l v dot c o n f ret

if ! wait_for_screen "nameserver 10\.0\.2\.3"; then
  fail "the dhcpcd hook never wrote /etc/resolv.conf" "terminal: screen>"
fi
echo "the hook wrote /etc/resolv.conf"

# ── 검사 8: QEMU가 붙인 기본 NIC는 안 보인다 ──────────────────────────
# 결정 3이 통째로 얹혀 있는 성질이다. 우리가 e1000 드라이버를 안 켜므로
# 게스트가 그 PCI 장치를 보고도 그냥 넘어간다. 이 검사가 없으면 기존 체인
# 열 개가 조용히 NIC를 하나 더 갖게 되는 날을 못 잡는다.
#
# 패턴을 하나씩 나눠 거는 이유는 check.sh의 require_no_early_exit_pipe가
# 쓰는 정규식이 파이프 문자를 구분자로 읽기 때문이다. 대안을 한 줄에 몰면
# 그 lint가 이 줄을 어떻게 읽을지가 사람 눈에 안 보인다.
for driver in e1000 8139 ne2k r8169 pcnet32 vmxnet; do
  if grep -ai "$driver" "$LOG" >/dev/null; then
    fail "a NIC driver we did not turn on showed up in the kernel log: ${driver}" \
      "$driver"
  fi
done
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
#
# M2부터 이 검사가 design 위험 2의 실제 시험이다. 이 부팅에는 dhcpcd가 있고
# 그것은 감독 목록 밖에 있다(결정 9의 갈래 A) — 배경으로 내려가면서 PID 1에
# 재부모화되므로 reapAll()이 세기는 하지만, 우리가 띄운 것 중 유일하게
# Child 배열에 없는 프로세스다. M0의 실측 4가 "SIGTERM에 죽는다"고 쟀고,
# 그 전제가 깨지는 날 여기가 빨간불이 된다.
if grep -a "grace period expired" "$LOG" >/dev/null; then
  fail "something outlived SIGTERM and burned the whole grace period" \
    "grace period expired"
fi

echo "PASS"
exit 0
