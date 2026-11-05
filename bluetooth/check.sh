#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")" || exit 1
# BT 체인 — 블루투스(BT-M2). 스물셋째 체인.
#
# 이 게이트가 증명하는 사슬 전체:
#   커널에 BT 스택 · HIDP · USB · PCIe HCI · 가상 HCI · uhid · AF_ALG가 내장되고(검사 1)
#   initrd에 BlueZ · dbus-daemon · 설정 넷 · 래퍼 둘 · messagebus · /var/lib/bluetooth 링크가 있다(검사 1)
#   → 설정 디스크의 bluetooth=on을 보고 init이 dbus를 bluetoothd 앞에 감독 목록에 넣는다(검사 2)
#   → 래퍼 둘이 exec해서 init이 쥔 pid가 곧 데몬이다(검사 3)
#   → 커널이 BT 스택 일곱 줄을 찍고 /dev/vhci · /dev/uhid가 있다(검사 4)
#   → btvirt가 /dev/vhci로 만든 컨트롤러 둘을 bluetoothd가 켜고(AutoEnable) 어댑터 설정이
#     /config/bluetooth/<주소>/settings에 써진다 — /var/lib/bluetooth 링크가 산다(검사 5)
#   → 두 컨트롤러가 Just Works로 페어링되고 키 · 신뢰가 /config/bluetooth/<A>/<B>/info에 남는다(검사 6)
#   → 사람이 bluetoothd를 재시작하면 새 pid가 디스크의 키를 되읽어 B를 Paired로 안다(검사 7)
#   → tars-config set bluetooth=off · reload가 재부팅 없이 둘을 내린다(검사 8)
#   → 디스크 없는 부팅은 bluetooth stays off이고 데몬 둘이 로그에 없다(검사 9, 기본값의 음성)
#
# 게스트 쪽 일은 설정 디스크의 services.d/bt(= bluetooth/bt.sh)가 하고 체인은 한 글자도 안
# 친다 — monitor 포트가 없다(audio의 부팅 A ~ C와 같다). btvirt는 sysroot에서 디스크로 가고
# initrd에는 없다(WL의 hostapd와 같다). 판정은 전부 시리얼 로그다 — init · 래퍼 · 커널의 줄과
# bt.sh의 bt-probe: 줄.
#
# firmware가 initrd에 있는지는 tools 체인 검사 1b가 본다(목록을 되읽어 297을 센다).
# BLE HID 장치가 uhid로 입력 장치가 되는 길은 여기 없다 — btvirt는 컨트롤러를 흉내 내지
# 주변 장치를 흉내 내지 않는다(BT design 위험 4). 그 길은 실기의 몫이다.
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

# ── 검사 1: 커널과 initrd가 블루투스를 안다 (부팅 없음) ────────────────────
#
# 아홉 심볼 중 하나만 빠져도 아래 부팅이 빨갛지만, 그 빨강은 "bluetoothd가 안 뜬다"처럼
# 보인다. 여기서 먼저 갈라 둔다. 입력 쪽(HID_APPLE · INPUT_LEDS)의 음성은 wifi 체인 검사 1이
# 본다(UB 결정 4) — BT를 켠 뒤에도 그 둘은 not set이다(BT design 실측 1).
CONFIG=../kernel/.config
for sym in BT BT_BREDR BT_LE BT_HIDP BT_HCIBTUSB BT_HCIBTUSB_MTK BT_INTEL_PCIE BT_HCIVHCI UHID \
           CRYPTO_USER_API_HASH CRYPTO_USER_API_SKCIPHER; do
  if ! grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym}=y is missing from kernel/.config"
    exit 1
  fi
done
# initrd의 파일. 첫 archive만 본다(firmware는 뒤의 archive라 안 나온다 — measurements 62).
LIST="$(mktemp)"
gzip -dc ../kernel/initrd.cpio 2>/dev/null | cpio -it 2>/dev/null > "$LIST"
for f in usr/libexec/bluetooth/bluetoothd usr/libexec/bluetooth/bluetoothctl usr/bin/bluetoothctl usr/bin/btmgmt usr/bin/dbus-daemon usr/bin/dbus-send \
         etc/bluetooth/main.conf etc/bluetooth/input.conf usr/share/dbus-1/system.conf usr/share/dbus-1/system.d/bluetooth.conf \
         usr/lib/tars/tars-dbus usr/lib/tars/tars-bluetoothd var/lib/bluetooth lib/x86_64-linux-gnu/libglib-2.0.so.0; do
  if ! grep -x "$f" "$LIST" >/dev/null; then
    echo "FAIL: initrd has no ${f}"
    rm -f "$LIST"
    exit 1
  fi
done
rm -f "$LIST"
# messagebus 사용자. dbus-daemon의 system.conf가 그 이름으로 내려앉는다. 꺼내는 파이프라인을 if 밖에 둔다 —
# initrd 뒤에 firmware cpio가 이어 붙어 있어 cpio가 첫 archive 끝에서 멈추면 gzip이 EPIPE로 죽고, pipefail이
# 그것을 거짓 빨강으로 올린다(첫 판이 그랬다).
PASSWD="$(mktemp)"
gzip -dc ../kernel/initrd.cpio 2>/dev/null | cpio -i --to-stdout etc/passwd > "$PASSWD" 2>/dev/null
if ! grep "^messagebus:" "$PASSWD" >/dev/null; then
  echo "FAIL: initrd /etc/passwd has no messagebus user"
  rm -f "$PASSWD"
  exit 1
fi
rm -f "$PASSWD"
# 래퍼 둘의 exec. 빼면 감독자의 SIGTERM이 셸에 간다(검사 3이 부팅에서 다시 본다).
for w in tars-dbus tars-bluetoothd; do
  if ! grep -E '^exec ' "../kernel/bluetooth/${w}" >/dev/null; then
    echo "FAIL: kernel/bluetooth/${w} does not exec its daemon"
    exit 1
  fi
done
echo "the kernel carries the BT stack, HIDP, USB and PCIe HCI, vhci, uhid and AF_ALG; the initrd carries BlueZ, dbus-daemon, their config and the /config/bluetooth link"

DISK_A=../out/bluetooth-a.img
LOG_A="$(mktemp)"
LOG_B="$(mktemp)"
LOG="$LOG_A"
QEMU_PID=""
SEED="$(mktemp -d)"

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  # 시리얼 로그는 안 지운다 — 루트 check.sh가 회차 디렉터리에서 끼어든 줄을 센다(AL-M0).
  rm -rf "$SEED"
}
trap cleanup EXIT

report_failure() {
  echo "FAIL: $1"
  echo "--- markers (${LOG}) ---"
  local marker
  for marker in \
    "tars-init: loaded /config/tars.conf" \
    "dbus and bluetoothd join the services" \
    "tars-init: started service dbus (pid" \
    "tars-init: started service bluetoothd (pid" \
    "tars-dbus: system bus on" \
    "tars-bluetoothd: bus ready after" \
    "Bluetooth daemon 5." \
    "Bluetooth: MGMT ver" \
    "bt-probe: controllers" \
    "bt-probe: pair" \
    "bt-probe: after restart" \
    "bt-probe: after off" \
    "terminal: screen>"; do
    if grep -a "$marker" "$LOG" >/dev/null; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- bt-probe lines ---"
  grep -a 'bt-probe:' "$LOG" | tr -d '\r'
  echo "--- last 60 lines ---"
  tail -n 60 "$LOG"
  exit 1
}

wait_for_log() {
  local pattern="$1" seconds="$2"
  for _ in $(seq 1 "$seconds"); do
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

# 접두가 $1인 첫 줄의 나머지. 콘솔 줄에는 프롬프트의 escape가 앞에, tty의 \r이 뒤에 붙을 수 있다.
probe() {
  grep -a "bt-probe: $1" "$LOG" | head -n 1 | tr -d '\r' | sed "s/.*bt-probe: $1//"
}

# -nic none — 이 체인에 네트워크는 없다(require_explicit_nic). virtio-gpu는 "프롬프트까지 떴다"
# 판정(screen>) 때문이다. 둘 다 monitor가 없다.
boot() {
  local disk="$1"
  if [ -n "$disk" ]; then
    qemu-system-x86_64 \
      -nic none \
      -m "$GUEST_MEM" \
      -kernel ../kernel/build/arch/x86/boot/bzImage \
      -initrd ../kernel/initrd.cpio \
      -append "console=ttyS0" \
      -vga none \
      -device virtio-gpu-pci \
      -display none \
      -drive file="$disk",if=virtio,format=raw \
      -serial file:"$LOG" \
      -no-reboot &
  else
    qemu-system-x86_64 \
      -nic none \
      -m "$GUEST_MEM" \
      -kernel ../kernel/build/arch/x86/boot/bzImage \
      -initrd ../kernel/initrd.cpio \
      -append "console=ttyS0" \
      -vga none \
      -device virtio-gpu-pci \
      -display none \
      -serial file:"$LOG" \
      -no-reboot &
  fi
  QEMU_PID=$!
}

source ../gate_lib.sh

# 설정 디스크 하나. bluetooth=on 한 줄, 프로브, 그리고 게이트 전용 btvirt(sysroot에서 — initrd에는
# 없다, Dockerfile 층 16). 라벨 접두사 tars-는 init이 설정 디스크를 알아보는 표지다(RM-M2).
SYSROOT="${AMD64_SYSROOT:-/usr/local/amd64-sysroot}"
mkdir -p ../out
rm -rf "${SEED:?}"/* && mkdir -p "$SEED/services.d" "$SEED/bt"
printf 'bluetooth=on\n' > "$SEED/tars.conf"
cp "$SYSROOT/usr/bin/btvirt" "$SEED/bt/"
cp bt.sh "$SEED/services.d/bt"
chmod 0755 "$SEED/services.d/bt" "$SEED/bt/btvirt"
rm -f "$DISK_A"
truncate -s 16M "$DISK_A"
mkfs.ext2 -F -q -m 0 -L tars-bluetooth -d "$SEED" "$DISK_A"

# ══ 부팅 A: bluetooth=on, 가상 컨트롤러 둘, 페어링 · 재시작 · 끄기 ═══════════
echo "=== boot A: bluetooth=on, two vhci controllers ==="
LOG="$LOG_A"
boot "$DISK_A"

# ── 검사 2: init이 키를 보고 dbus를 bluetoothd 앞에 넣었나 ─────────────────
wait_for_log 'tars-init: started service bluetoothd \(pid' 90 \
  || report_failure "init never started bluetoothd"
grep -a "tars-init: dbus and bluetoothd join the services, keys live in /config/bluetooth" "$LOG" >/dev/null \
  || report_failure "init did not say dbus and bluetoothd join the services"
DBUS_LINE="$(grep -an 'tars-init: started service dbus (pid [0-9]*, /usr/lib/tars/tars-dbus)' "$LOG" | head -n 1)"
BTD_LINE="$(grep -an 'tars-init: started service bluetoothd (pid [0-9]*, /usr/lib/tars/tars-bluetoothd)' "$LOG" | head -n 1)"
[ -n "$DBUS_LINE" ] || report_failure "init did not start tars-dbus as service dbus"
[ -n "$BTD_LINE" ] || report_failure "init did not start tars-bluetoothd as service bluetoothd"
[ "${DBUS_LINE%%:*}" -lt "${BTD_LINE%%:*}" ] \
  || report_failure "dbus was not started before bluetoothd (BT design 결정 4)"
DBUS_PID="$(echo "$DBUS_LINE" | sed -n 's/.*(pid \([0-9]*\),.*/\1/p')"
BTD_PID="$(echo "$BTD_LINE" | sed -n 's/.*(pid \([0-9]*\),.*/\1/p')"
echo "init started service dbus (pid ${DBUS_PID}) ahead of service bluetoothd (pid ${BTD_PID})"

# ── 검사 3: 래퍼 둘이 exec했나 ────────────────────────────────────────────
# 프로브의 pgrep이 감독자의 pid와 같아야 한다. exec을 빼고 자식으로 띄우면 데몬은 똑같이 뜨고
# 이 대조만 틀린다 — 그때 감독자의 SIGTERM은 셸에 간다. tars-bluetoothd의 대기 줄도 여기서 본다.
wait_for_log 'bt-probe: pids dbus=' 60 || report_failure "the probe never reported the daemon pids"
PIDS="$(probe 'pids ')"
[ "$PIDS" = "dbus=${DBUS_PID} bluetoothd=${BTD_PID} " ] \
  || report_failure "the running daemons are [${PIDS}], init holds dbus=${DBUS_PID} bluetoothd=${BTD_PID}"
grep -a 'tars-dbus: system bus on /run/dbus/system_bus_socket' "$LOG" >/dev/null \
  || report_failure "tars-dbus did not announce the bus"
BUS_WAIT="$(grep -a 'tars-bluetoothd: bus ready after' "$LOG" | head -n 1 | tr -d '\r' | sed -n 's/.*after \([0-9]*\)ms.*/\1/p')"
[ -n "$BUS_WAIT" ] || report_failure "tars-bluetoothd did not announce the bus wait"
[ "$BUS_WAIT" -lt 10000 ] || report_failure "tars-bluetoothd gave up waiting for the bus (${BUS_WAIT}ms)"
grep -a 'Bluetooth daemon 5\.' "$LOG" >/dev/null || report_failure "bluetoothd did not print its banner"
echo "tars-dbus and tars-bluetoothd exec'd: pids ${DBUS_PID} and ${BTD_PID} are the daemons; the bus was ready after ${BUS_WAIT}ms"

# ── 검사 4: 커널 줄 일곱과 노드 둘 ─────────────────────────────────────────
for line in 'Bluetooth: Core ver' 'Bluetooth: HCI device and connection manager initialized' \
            'Bluetooth: HCI socket layer initialized' 'Bluetooth: L2CAP socket layer initialized' \
            'Bluetooth: SCO socket layer initialized' 'Bluetooth: HIDP (Human Interface Emulation) ver' \
            'Bluetooth: HIDP socket layer initialized'; do
  grep -a "$line" "$LOG" >/dev/null || report_failure "the kernel did not print '${line}'"
done
for n in /dev/vhci /dev/uhid /var/lib/bluetooth; do
  grep -a "bt-probe: node ${n} present" "$LOG" >/dev/null || report_failure "${n} is missing in the guest"
done
[ "$(probe 'link ')" = "/config/bluetooth" ] || report_failure "/var/lib/bluetooth does not point at /config/bluetooth: $(probe 'link ')"
echo "the kernel printed the seven Bluetooth lines; /dev/vhci, /dev/uhid and the /var/lib/bluetooth link are there"

# ── 검사 5: 컨트롤러 둘이 켜지고 설정이 /config에 써진다 ───────────────────
wait_for_log 'bt-probe: settings \[' 60 || report_failure "the probe never listed the adapter settings"
CTRL="$(probe 'controllers ')"
[ "${CTRL%% *}" = 2 ] || report_failure "bluetoothctl list shows [${CTRL}], want two controllers"
A_ADDR="$(echo "$CTRL" | sed -n 's/.*A=\([0-9A-F:]*\).*/\1/p')"
B_ADDR="$(echo "$CTRL" | sed -n 's/.*B=\([0-9A-F:]*\).*/\1/p')"
[ "$(probe 'powered A ')" = "yes" ] || report_failure "controller ${A_ADDR} is not powered: $(probe 'powered A ')"
MGMT="$(grep -ac 'Bluetooth: MGMT ver' "$LOG")"
[ "$MGMT" -ge 2 ] || report_failure "the kernel printed ${MGMT} MGMT lines, want one per controller"
SETTINGS="$(probe 'settings ')"
case "$SETTINGS" in
  *"/config/bluetooth/${A_ADDR}/settings"*"/config/bluetooth/${B_ADDR}/settings"*|*"/config/bluetooth/${B_ADDR}/settings"*"/config/bluetooth/${A_ADDR}/settings"*) ;;
  *) report_failure "adapter settings are not under /config/bluetooth: ${SETTINGS}" ;;
esac
echo "btvirt made ${A_ADDR} and ${B_ADDR}, bluetoothd powered them and wrote both settings under /config/bluetooth"

# ── 검사 6: 페어링되고 키가 디스크에 남는다 ────────────────────────────────
wait_for_log 'bt-probe: info ' 120 || report_failure "the probe never reported the pairing"
PAIR="$(probe 'pair ')"
# `Bonded: yes`는 pair의 [CHG] 줄과 info의 줄로 두 번 나올 수 있다 — 하나 이상이면 된다. Failed는 0이어야 한다.
BONDED="$(echo "$PAIR" | sed -n 's/^\([0-9]*\) bonded.*/\1/p')"
CONNECTED="$(echo "$PAIR" | sed -n 's/.* \([0-9]*\) connected.*/\1/p')"
FAILED="$(echo "$PAIR" | sed -n 's/.* \([0-9]*\) failed.*/\1/p')"
[ "${BONDED:-0}" -ge 1 ] && [ "${CONNECTED:-0}" -ge 1 ] && [ "${FAILED:-1}" -eq 0 ] \
  || report_failure "pairing did not bond: ${PAIR}"
INFO="$(probe 'info ')"
case "$INFO" in
  "/config/bluetooth/${A_ADDR}/${B_ADDR}/info ["*"[LinkKey]"*"]"*"Trusted=true"*) ;;
  *) report_failure "the pairing keys did not land in /config: ${INFO}" ;;
esac
case "$INFO" in
  *"LongTermKey"*) ;;
  *) report_failure "no long term key in the info file: ${INFO}" ;;
esac
echo "${A_ADDR} paired ${B_ADDR} (Just Works) and /config/bluetooth/${A_ADDR}/${B_ADDR}/info holds the link key, a long term key and Trusted=true"

# ── 검사 7: 재시작한 bluetoothd가 디스크의 키를 되읽는다 ───────────────────
wait_for_log 'bt-probe: after restart ' 90 || report_failure "the probe never reported the restart"
RESTART="$(probe 'after restart ')"
NEW_PID="$(echo "$RESTART" | sed -n 's/^pid [0-9]* -> \([0-9]*\) .*/\1/p')"
[ -n "$NEW_PID" ] && [ "$NEW_PID" != "$BTD_PID" ] || report_failure "bluetoothd did not come back with a new pid: ${RESTART}"
grep -a "tars-init: started service bluetoothd (pid ${NEW_PID}, /usr/lib/tars/tars-bluetoothd)" "$LOG" >/dev/null \
  || report_failure "init did not log the restarted bluetoothd (pid ${NEW_PID})"
case "$RESTART" in
  *"controllers 2 paired yes"*) ;;
  *) report_failure "after the restart bluetoothd does not know the pairing: ${RESTART}" ;;
esac
echo "tars-service restart bluetoothd brought pid ${NEW_PID}, which sees both controllers and still knows ${B_ADDR} as paired"

# ── 검사 8: 끄기는 재부팅 없이 둘을 내린다 ─────────────────────────────────
wait_for_log 'bt-probe: after off ' 60 || report_failure "the probe never reported the switch-off"
RELOAD="$(probe 'reload: ')"
case "$RELOAD" in
  *"bluetooth: on -> off (now)"*) ;;
  *) report_failure "tars-config reload did not say bluetooth: on -> off (now): ${RELOAD}" ;;
esac
grep -a 'tars-init: reload: service dbus stop' "$LOG" >/dev/null || report_failure "init did not stop service dbus on reload"
grep -a 'tars-init: reload: service bluetoothd stop' "$LOG" >/dev/null || report_failure "init did not stop service bluetoothd on reload"
[ "$(probe 'after off ')" = "dbus=[] bluetoothd=[]" ] || report_failure "a daemon survived bluetooth=off: $(probe 'after off ')"
echo "tars-config set bluetooth=off + reload stopped dbus and bluetoothd; nothing is left running"
# 꺼진 뒤의 bluetoothctl. 진짜 bluetoothctl은 여기서 SIGABRT(rc 134)로 죽는다 — 감싸개가 말하고 1로 끝나야 한다.
CTL_OFF="$(probe 'ctl off ')"
[ "$CTL_OFF" = "rc=1 bluetoothctl: bluetooth is off (no system bus); turn it on: sudo tars-config set bluetooth=on; sudo tars-config reload" ] \
  || report_failure "bluetoothctl with no bus did not say how to turn bluetooth on: ${CTL_OFF}"
echo "with bluetooth off, bluetoothctl says how to turn it on and exits 1"
stop_guest

# ══ 부팅 B: 디스크 없음 — 기본값은 꺼짐 ═════════════════════════════════════
echo "=== boot B: no disk, bluetooth stays off ==="
LOG="$LOG_B"
boot ""

# ── 검사 9: 기본값의 음성 ──────────────────────────────────────────────────
wait_for_log 'terminal: screen>' 90 || report_failure "the guest never reached a prompt"
grep -a 'tars-init: bluetooth=off, bluetooth stays off' "$LOG" >/dev/null \
  || report_failure "init did not say bluetooth stays off"
if grep -aE 'started service (dbus|bluetoothd)|tars-dbus:|tars-bluetoothd:|Bluetooth daemon' "$LOG" >/dev/null; then
  report_failure "a Bluetooth daemon ran without bluetooth=on"
fi
grep -a 'Bluetooth: HIDP (Human Interface Emulation) ver' "$LOG" >/dev/null \
  || report_failure "the kernel stack is missing in boot B"
echo "without a disk bluetooth stays off: the kernel stack is there, no daemon ran"
stop_guest

for log in "$LOG_A" "$LOG_B"; do
  if [ "$(tr -cd '\0' < "$log" | wc -c)" -ne 0 ]; then
    report_failure "a serial log contains NUL bytes (${log})"
  fi
done
echo "BT-M2 check PASS"
