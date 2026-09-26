#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# WN 체인 — 노트북형 유선 NIC가 붙고, 부팅 뒤에 꽂은 것도 주소를 받는다.
#
# net 체인이 virtio 위에서 프로토콜(DHCP · 포트 · 시계)을 본다면 이 체인은
# 드라이버와 장치를 본다(WN design 결정 5). 증명하는 사슬이 둘이다:
#
#   부팅 A  .config의 CONFIG_E1000E → QEMU q35의 -device e1000e에 드라이버가
#           붙어 eth0이 된다 → init이 dhcpcd를 인자 없이 띄운다 → dhcpcd가
#           eth0을 스스로 골라 올리고 lease를 받는다
#   부팅 B  NIC 없이 뜬다 → 부팅은 평소대로 끝나고 dhcpcd는 살아서 기다린다
#           → monitor의 device_add로 usb-net을 꽂는다 → cdc_ether가 붙어
#           usb0이 된다 → 부팅 때 뜬 그 dhcpcd가 usb0을 잡아 lease를 받는다
#
# 우리 코드는 두 사슬에 한 줄씩이다(init의 `started dhcpcd`). 나머지는 커널과
# dhcpcd다 — 그래서 이 체인의 검사는 그 경계가 어디에 그어졌는지를 본다.
#
# 판정은 전부 시리얼 로그다. 게스트에 한 글자도 안 친다. dhcpcd가 -j
# /dev/console로 모든 줄을 콘솔에 쓰는 것(WN design 실측 13)이 이것을 가능하게
# 한다 — 배경으로 간 뒤의 lease도, 부팅 뒤에 꽂은 장치의 lease도 보인다.
#
# 나머지 셋(igc · r8169 · r8152)은 QEMU가 흉내를 못 내므로 .config에 =y인
# 것까지만 본다(design 결정 2). 이 체인이 그 셋에 대해 말할 수 있는 것은
# "빌드됐다"가 전부다.

# $GUEST_MEM 하나 때문에 source한다. device 체인처럼 타이핑을 안 한다.
source ../gate_lib.sh

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

# 45455~45464는 체인들의 monitor, 45465~45470은 net 체인, 45471은 machine이다.
# 겹치지 않는 번호를 쓰는 이유는 죽다 만 QEMU가 남았을 때 엉뚱한 게스트에
# 명령을 보내지 않기 위해서다.
MONITOR_PORT_A=45472
MONITOR_PORT_B=45473

DISK=../out/nic.img
LOG_A="$(mktemp)"
LOG_B="$(mktemp)"
LOG="$LOG_A"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  rm -f "$LOG_A" "$LOG_B"
}
trap cleanup EXIT

report_failure() {
  echo "FAIL: $1"
  echo "--- markers (${LOG}) ---"
  local marker
  for marker in \
    "tars-init: loaded /config/tars.conf" \
    "tars-init: started dhcpcd (pid" \
    "no valid interfaces found" \
    "terminal: screen>" \
    "cdc_ether" \
    ": leased"; do
    if grep -a "$marker" "$LOG" >/dev/null; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- last 60 lines ---"
  tail -n 60 "$LOG"
  exit 1
}

# 로그에 패턴(ERE)이 나올 때까지 기다린다. QEMU가 먼저 죽으면 바로 돌아온다.
wait_for_log() {
  local pattern="$1" seconds="$2" i
  for i in $(seq 1 "$seconds"); do
    if grep -aE "$pattern" "$LOG" >/dev/null; then return 0; fi
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then return 1; fi
    sleep 1
  done
  return 1
}

stop_guest() {
  kill "$QEMU_PID" 2>/dev/null || true
  wait "$QEMU_PID" 2>/dev/null || true
  QEMU_PID=""
}

# ── 검사 1: 드라이버가 커널에 있나 (부팅 없음) ──────────────────────────
# 결정 1의 여섯과 M1에서 사용자가 남긴 USB 동글 셋. 부팅으로 판정하는 것은
# 이 중 e1000e와 cdc_ether 둘뿐이라, 나머지 일곱이 빠지는 날은 여기서만
# 드러난다.
#
# 끈 셋은 음성이다. 사용자가 "요즘 동글만 남김"을 골랐고(M1 사실 1), 누군가
# olddefconfig의 기본값으로 되돌리면 조용히 다시 켜진다.
CONFIG=../kernel/.config
for sym in E1000E IGC R8169 USB_RTL8152 USB_USBNET USB_NET_CDCETHER \
  USB_NET_AX8817X USB_NET_AX88179_178A USB_NET_CDC_NCM; do
  if ! grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is not =y in kernel/.config"
    exit 1
  fi
done
for sym in USB_NET_NET1080 USB_NET_ZAURUS USB_NET_CDC_SUBSET; do
  if ! grep -x "# CONFIG_${sym} is not set" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} was turned off on purpose (WN-M1) and is back"
    exit 1
  fi
done
echo "the kernel carries the nine laptop NIC drivers and not the three we dropped"

# 설정 디스크. net/make_disk.sh와 같은 수법이다 — debugfs가 이미지 파일에 직접
# 쓰므로 마운트도 특권도 필요 없다. 라벨 접두사 tars-는 init이 설정 디스크를
# 알아보는 표지다(RM-M2). ntp는 기본값 off라 시계 자식이 안 뜬다.
mkdir -p ../out
CONF="$(mktemp)"
printf 'net=dhcp\n' > "$CONF"
rm -f "$DISK"
truncate -s 16M "$DISK"
mkfs.ext2 -F -q -m 0 -L tars-nic "$DISK"
debugfs -w -R "write ${CONF} tars.conf" "$DISK" 2>&1 | grep -v '^debugfs' || true
rm -f "$CONF"

# ══ 부팅 A: 처음부터 붙어 있는 e1000e ═════════════════════════════════
# 노트북 내장 Intel I219 계열과 같은 드라이버다(design 확인 5). q35인 이유는
# machine 체인과 같다 — 노트북에 가까운 칩셋이다.
echo "=== boot A: q35 with an e1000e ==="
LOG="$LOG_A"
qemu-system-x86_64 \
  -machine q35 \
  -netdev user,id=n0 \
  -device e1000e,netdev=n0 \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -drive file="$DISK",if=virtio,format=raw \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT_A},server,nowait \
  -no-reboot &
QEMU_PID=$!

# ── 검사 2: e1000e가 장치에 붙었나 ──────────────────────────────────────
# 드라이버 이름만 보면 안 된다. 드라이버가 커널에 있으면 장치가 없어도
# `e1000e: Intel(R) PRO/1000 Network Driver` 배너가 찍힌다(실측 10). 장치에
# 붙었다는 표지는 PCI 주소와 인터페이스 이름이 함께 있는 줄이다.
wait_for_log 'e1000e [0-9a-f]{4}:[0-9a-f:.]+ eth0: ' 60 \
  || report_failure "e1000e never bound the q35 NIC as eth0"
echo "e1000e bound the NIC and named it eth0"

# ── 검사 3: init은 dhcpcd를 띄우기만 했나 ───────────────────────────────
# net 체인 검사 4와 같은 경계다. 이 체인에서 다시 보는 이유는 NIC가 virtio가
# 아닐 때도 init이 이름을 안 고른다는 것이 여기서만 증명되기 때문이다.
wait_for_log 'tars-init: started dhcpcd \(pid' 60 \
  || report_failure "init did not start dhcpcd"
if grep -a "tars-init: net link" "$LOG" >/dev/null; then
  report_failure "init touched the link itself; dhcpcd is supposed to do that"
fi
echo "init started dhcpcd and left the interface to it"

# ── 검사 4: dhcpcd가 eth0으로 주소를 받았나 ─────────────────────────────
# SLIRP의 주소 규칙이 고정이라 값을 박는다. 5초쯤은 ARP probe다(실측 3).
wait_for_log 'eth0: leased 10\.0\.2\.15 ' 60 \
  || report_failure "dhcpcd never leased an address on eth0"
echo "dhcpcd picked eth0 and leased 10.0.2.15"

stop_guest

# ══ 부팅 B: NIC 없이 뜬 뒤 USB 동글을 꽂는다 ═══════════════════════════
# -netdev만 있고 NIC 장치가 없다. QEMU는 이때 기본 NIC를 안 붙인다(실측 5).
# qemu-xhci가 동글을 꽂을 USB 3 포트다.
echo "=== boot B: q35 with no NIC, then a usb-net plugged in ==="
LOG="$LOG_B"
qemu-system-x86_64 \
  -machine q35 \
  -netdev user,id=n1 \
  -device qemu-xhci,id=xhci \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -drive file="$DISK",if=virtio,format=raw \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT_B},server,nowait \
  -no-reboot &
QEMU_PID=$!

# ── 검사 5: NIC 없이도 부팅이 끝났고, 인터페이스가 정말 없나 ────────────
# 앞의 것이 design 결정 6이다 — net=dhcp인데 NIC가 없어도 부팅을 안 막는다.
# 뒤의 음성이 없으면 아래 lease가 꽂은 동글의 것인지 QEMU가 몰래 붙인 NIC의
# 것인지 못 가른다.
wait_for_log 'terminal: screen>' 120 \
  || report_failure "the guest never finished booting without a NIC"
if grep -a "eth0" "$LOG" >/dev/null; then
  report_failure "an eth0 showed up although this boot has no NIC device"
fi
if grep -a "usb0" "$LOG" >/dev/null; then
  report_failure "a usb0 showed up before anything was plugged in"
fi
echo "the guest booted to a prompt with no network interface"

# ── 검사 6: dhcpcd가 살아서 기다리나 ────────────────────────────────────
# 인터페이스가 없으면 dhcpcd는 이 줄을 찍고 끝나지 않는다(실측 14). -j가
# 붙인 줄머리의 [pid]를 여기서 적어 두고 검사 8이 대조한다.
#
# 같은 글자가 stderr로 한 번 더 나오는데(배경으로 가기 전의 줄, 실측 13)
# 그쪽에는 줄머리가 없다. 그래서 `[N]: ` 모양이 붙은 줄만 본다.
wait_for_log '\[[0-9]+\]: no valid interfaces found' 60 \
  || report_failure "dhcpcd did not say it is waiting for an interface"
WAITING="$(awk 'match($0, /\[[0-9]+\]: no valid interfaces found/) {
  print substr($0, RSTART + 1, RLENGTH - 1); exit }' "$LOG")"
DHCPCD_PID="${WAITING%%]*}"
echo "dhcpcd (pid ${DHCPCD_PID}) is waiting for an interface"

# 동글을 꽂는다. 사람이 부팅 뒤에 USB 동글을 꽂는 것과 같다.
CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT_B}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "could not connect to the QEMU monitor"
echo "=== plugging usb-net into the running guest ==="
echo "device_add usb-net,netdev=n1,bus=xhci.0,id=u1" >&3
sleep 0.3
exec 3<&-
exec 3>&-

# ── 검사 7: cdc_ether가 꽂힌 장치에 붙었나 ──────────────────────────────
# QEMU의 usb-net은 CDC Ethernet으로 붙는다(실측 6). 꽂는 순간 체인의 출력에
# `usbnet: failed control transaction` 세 줄이 나오는데 해가 없다. 게스트가
# 아니라 QEMU가 자기 stderr에 찍는 것이다 — 게스트가 보낸 문자열 descriptor
# 요청을 QEMU의 usb-net이 처리하지 못했다는 말이고, 게스트는 곧이어 등록에
# 성공한다(WN design 실측 18). 이 체인은 그 글자를 안 본다.
#
# 부팅 직후의 `netdev n1 has no peer` 경고도 QEMU의 것이다. 동글을 꽂기 전에는
# n1에 붙은 장치가 없으니 맞는 말이고, 이 부팅이 의도한 상태 그 자체다.
wait_for_log 'cdc_ether .* usb0: register ' 30 \
  || report_failure "cdc_ether never registered the plugged usb-net as usb0"
echo "cdc_ether bound the dongle and named it usb0"

# ── 검사 8: 기다리던 그 dhcpcd가 usb0으로 주소를 받았나 ─────────────────
# 이 체인에서 가장 값진 한 줄이다. pid가 같아야 부팅 때 뜬 dhcpcd 하나가 udev
# 없이 새 장치를 잡은 것이다(design 결정 4). 누군가 장치가 생길 때 dhcpcd를
# 다시 띄우는 길을 만들면 lease는 똑같이 나오고 pid만 다르다 — 이 대조가
# 없으면 그 변화가 초록으로 지나간다.
wait_for_log "\\[${DHCPCD_PID}\\]: usb0: leased 10\\.0\\.2\\.15 " 60 \
  || report_failure "dhcpcd (pid ${DHCPCD_PID}) never leased an address on the plugged usb0"
echo "the same dhcpcd (pid ${DHCPCD_PID}) caught usb0 and leased 10.0.2.15"

stop_guest

echo "WN-M3 PASS: a built-in e1000e and a hot-plugged USB dongle both got an address"
