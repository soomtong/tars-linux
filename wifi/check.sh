#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# WL 체인 — 무선이 AP에 붙고 dhcpcd가 주소를 받는다.
#
# QEMU에는 무선 장치가 없다. 커널의 mac80211_hwsim이 가짜 라디오를 만들고, 게스트
# 안에서 라디오 하나를 AP로 세워 제품이 거기 붙는 것을 본다(WL design 결정 7). 게스트
# 쪽 일은 설정 디스크의 services.d/ap(= wifi/ap.sh)가 하고, 이 스크립트는 한 글자도
# 안 친다. 판정은 전부 시리얼 로그다.
#
#   부팅 A  radios=3 · 맞는 비밀번호. 부팅 때 있던 wlan0은 tars-wifi의 argv로,
#           나중에 생긴 wlan2는 dhcpcd hook의 interface_add로 넘어간다. 둘 다
#           제품 dhcpcd가 주소를 받는다
#   부팅 B  radios=2 · 틀린 비밀번호. 연결이 안 서고 부팅은 끝난다. 그 뒤에 프로브가
#           tars-config wifi로 비밀번호를 고치고 재시작하면 붙는다(TC-M1)
#   부팅 C  radios 없음 · 설정 파일 없음. 라디오도 wpa_supplicant도 없다
#
# 이 체인이 못 보는 것 — 실칩 드라이버의 probe와 firmware 로딩(WL design 위험 4).
# firmware가 initrd에 있다는 것은 tools 체인의 검사 1b가 본다.

# $GUEST_MEM 하나 때문에 source한다. nic 체인처럼 타이핑을 안 한다.
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

DISK_A=../out/wifi-a.img
DISK_B=../out/wifi-b.img
DISK_C=../out/wifi-c.img
LOG_A="$(mktemp)"
LOG_B="$(mktemp)"
LOG_C="$(mktemp)"
LOG="$LOG_A"
QEMU_PID=""
SEED="$(mktemp -d)"

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  rm -rf "$LOG_A" "$LOG_B" "$LOG_C" "$SEED"
}
trap cleanup EXIT

report_failure() {
  echo "FAIL: $1"
  echo "--- markers (${LOG}) ---"
  local marker
  for marker in \
    "tars-init: loaded /config/tars.conf" \
    "wpa_supplicant joins the services" \
    "tars-init: started service wpa_supplicant (pid" \
    "tars-wifi: wpa_supplicant on" \
    "wifi-ap: ap up" \
    "CTRL-EVENT-CONNECTED" \
    "wlan0: leased" \
    "tars-wifi: handed" \
    "wlan2: leased" \
    "terminal: screen>"; do
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

# -nic none — 이 체인의 네트워크는 전부 게스트 안의 가짜 라디오다
# (require_explicit_nic). virtio-gpu는 부팅 B · C의 "프롬프트까지 떴다" 판정 때문이다.
boot() {
  local disk="$1" append="$2"
  qemu-system-x86_64 \
    -nic none \
    -m "$GUEST_MEM" \
    -kernel ../kernel/build/arch/x86/boot/bzImage \
    -initrd ../kernel/initrd.cpio \
    -append "console=ttyS0${append}" \
    -vga none \
    -device virtio-gpu-pci \
    -display none \
    -drive file="$disk",if=virtio,format=raw \
    -serial file:"$LOG" \
    -no-reboot &
  QEMU_PID=$!
}

# ── 검사 1: 커널이 무선을 안다 (부팅 없음) ──────────────────────────────
# 부팅으로 판정하는 드라이버는 hwsim 하나뿐이라 실칩 열여섯이 빠지는 날은 여기서만
# 드러난다(nic 체인 검사 1과 같은 자리). 내장 cmdline은 글자 그대로 본다 — 빠지면
# 모든 부팅에 가짜 라디오 둘이 생긴다(결정 2). 부팅 C가 그 결과를 따로 본다.
CONFIG=../kernel/.config
for sym in CFG80211 MAC80211 RFKILL MAC80211_HWSIM IWLWIFI IWLMVM IWLMLD \
  RTW88_8822BE RTW88_8822CE RTW88_8723DE RTW88_8821CE \
  RTW89_8851BE RTW89_8852AE RTW89_8852BE RTW89_8852BTE RTW89_8852CE RTW89_8922AE \
  MT7921E MT7925E ATH11K_PCI ATH12K CMDLINE_BOOL \
  RTW88_8822BU RTW88_8822CU RTW88_8723DU RTW88_8821CU RTW88_8821AU RTW88_8812AU RTW88_8814AU \
  RTW89_8851BU RTW89_8852BU MT7921U MT7925U; do
  if ! grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is not =y in kernel/.config"
    exit 1
  fi
done
if ! grep -x 'CONFIG_CMDLINE="mac80211_hwsim.radios=0"' "$CONFIG" >/dev/null; then
  echo "FAIL: the built-in cmdline no longer turns hwsim's radios off"
  exit 1
fi
# USB 동글은 QEMU에 없어서 꽂아 볼 수 없다(UW 결정 3). 대신 커널이 VID:PID를 드라이버에
# 잇는 표를 갖고 있는지 계열마다 하나씩 본다 — 그 줄이 있어야 꽂힌 동글이 잡힌다.
# modinfo는 NUL로 나뉜 파일이다. 대표는 UW design 실측 4의 표다.
MODINFO=../kernel/build/modules.builtin.modinfo
for alias in rtw88_8822bu.alias=usb:v2357p012Dd rtw89_8852bu.alias=usb:v0BDApB832d \
  mt7921u.alias=usb:v0E8Dp7961d mt7925u.alias=usb:v0E8Dp7925d; do
  if ! tr '\0' '\n' < "$MODINFO" | grep -F "$alias" >/dev/null; then
    echo "FAIL: the kernel has no ${alias%%.*} entry for ${alias#*usb:}"
    exit 1
  fi
done
echo "the kernel carries the wireless stack, sixteen laptop chips, eleven USB dongles and hwsim with no radios"

# 설정 디스크 셋. 게이트 전용 둘(hostapd · busybox)은 sysroot에서 온다 — initrd에는
# 없다(Dockerfile 층 12). 라이브러리는 wpa_supplicant가 initrd에 이미 데려왔다.
# 라벨 접두사 tars-는 init이 설정 디스크를 알아보는 표지다(RM-M2).
SYSROOT="${AMD64_SYSROOT:-/usr/local/amd64-sysroot}"
mkdir -p ../out
make_disk() {
  local disk="$1" mode="$2" psk="$3"
  rm -rf "$SEED"/* && mkdir -p "$SEED/services.d" "$SEED/wl"
  printf 'net=dhcp\n' > "$SEED/tars.conf"
  if [ -n "$mode" ]; then
    cp "$SYSROOT/usr/sbin/hostapd" "$SYSROOT/usr/bin/busybox" "$SEED/wl/"
    echo "$mode" > "$SEED/wl/mode"
    cp ap.sh "$SEED/services.d/ap"
    chmod 0755 "$SEED/services.d/ap"
    # 사람이 쓰는 파일과 같은 모양이다 — wpa_passphrase가 내는 것과 달리 psk를 평문
    # 그대로 두었다. country 줄이 regulatory.db를 부른다(검사 6).
    printf 'country=KR\nnetwork={\n\tssid="tars-wl"\n\tpsk="%s"\n}\n' "$psk" > "$SEED/wpa_supplicant.conf"
  fi
  rm -f "$disk"
  truncate -s 16M "$disk"
  mkfs.ext2 -F -q -m 0 -L tars-wifi -d "$SEED" "$disk"
}
make_disk "$DISK_A" full tars-secret
make_disk "$DISK_B" ap-only wrong-secret
make_disk "$DISK_C" "" ""

# ══ 부팅 A: 맞는 비밀번호, 라디오 셋 ═══════════════════════════════════
echo "=== boot A: three hwsim radios, the right passphrase ==="
LOG="$LOG_A"
boot "$DISK_A" " mac80211_hwsim.radios=3"

# ── 검사 2: init이 파일을 보고 wpa_supplicant를 dhcpcd 앞에 넣었나 ──────
wait_for_log 'tars-init: started service dhcpcd \(pid' 90 \
  || report_failure "init never started dhcpcd"
grep -a "tars-init: wpa_supplicant joins the services, tars-wifi picks the interfaces" "$LOG" >/dev/null \
  || report_failure "init did not say wpa_supplicant joins the services"
WPA_LINE="$(grep -an 'tars-init: started service wpa_supplicant (pid [0-9]*, /usr/lib/tars/tars-wifi)' "$LOG" | head -n 1)"
DHCPCD_LINE="$(grep -an 'tars-init: started service dhcpcd (pid' "$LOG" | head -n 1)"
[ -n "$WPA_LINE" ] || report_failure "init did not start tars-wifi as service wpa_supplicant"
[ "${WPA_LINE%%:*}" -lt "${DHCPCD_LINE%%:*}" ] \
  || report_failure "wpa_supplicant was not started before dhcpcd (WL design 결정 4)"
WPA_PID="$(echo "$WPA_LINE" | sed -n 's/.*(pid \([0-9]*\),.*/\1/p')"
echo "init started service wpa_supplicant (pid ${WPA_PID}) ahead of dhcpcd"

# ── 검사 3: tars-wifi가 세고 exec했나 ──────────────────────────────────
# ap.sh가 찍는 pgrep의 pid가 감독자의 pid와 같아야 한다. exec을 빼고 자식으로
# 띄우면 연결은 똑같이 서고 이 대조만 틀린다 — 그때 감독자의 SIGTERM은 셸에 간다.
wait_for_log 'tars-wifi: wpa_supplicant on wlan0 wlan1 wlan2' 30 \
  || report_failure "tars-wifi did not count the three radios"
wait_for_log 'wifi-ap: wpa_supplicant holds \[wlan0 wlan1 wlan2\] \(pid [0-9]+\)' 60 \
  || report_failure "wpa_supplicant never held all three radios"
HELD_PID="$(grep -a 'wifi-ap: wpa_supplicant holds' "$LOG" | sed -n 's/.*(pid \([0-9]*\)).*/\1/p' | head -n 1)"
[ "$HELD_PID" = "$WPA_PID" ] \
  || report_failure "the running wpa_supplicant is pid ${HELD_PID}, init holds ${WPA_PID}"
echo "tars-wifi counted wlan0 wlan1 wlan2 and exec'd: pid ${WPA_PID} is wpa_supplicant"

# ── 검사 4: wlan0이 붙고 제품 dhcpcd가 주소를 받았나 ────────────────────
# 우리 코드가 dhcpcd에게 한 일은 없다 — carrier가 서면 dhcpcd가 스스로 받는다
# (WL design 확인 3). 주소는 udhcpd의 범위 첫 칸이 아닐 수 있어서 범위만 본다.
wait_for_log 'wifi-ap: ap up on wlan1 in netns ap' 60 \
  || report_failure "the AP never came up"
wait_for_log 'wlan0: CTRL-EVENT-CONNECTED - Connection to .* completed' 60 \
  || report_failure "wlan0 never connected to the AP"
wait_for_log 'wlan0: leased 192\.168\.77\.[0-9]+ ' 60 \
  || report_failure "dhcpcd never leased an address on wlan0"
echo "wlan0 connected (WPA2-PSK, CCMP) and dhcpcd leased an address"

# ── 검사 5: 무선 경로로 TCP가 오간다 ────────────────────────────────────
# AP는 다른 netns에 있어서 커널의 로컬 지름길이 없다. 이 답은 hwsim의 공중을 지났다.
wait_for_log 'wifi-ap: tcp TARS-WL-PONG' 30 \
  || report_failure "no TCP round trip over the wireless link"
echo "a TCP round trip crossed the wireless link"

# ── 검사 6: country=KR이 규제 도메인이 됐다 ─────────────────────────────
# regulatory.db가 initrd에 없거나 서명이 안 맞으면 국가를 못 바꾸고 00에 남는다
# (WL design 실측 8). 파일이 있다는 것을 부팅으로 보는 유일한 자리다.
wait_for_log 'wifi-ap: reg country KR' 10 \
  || report_failure "the regulatory domain did not become KR"
if grep -a "failed to load regulatory.db" "$LOG" >/dev/null; then
  report_failure "cfg80211 could not load regulatory.db"
fi
echo "country=KR reached the kernel through regulatory.db"

# ── 검사 7: 사람이 재시작해도 돌아온다 ──────────────────────────────────
# CT의 규칙이 이 칸에도 선다 — 요청한 죽음은 빨리 죽음이 아니다. 새 tars-wifi는
# wlan0만 센다(wlan2는 park에 숨었고 wlan1은 ap에 있다).
wait_for_log 'tars-init: restarting service wpa_supplicant on request' 60 \
  || report_failure "the restart request did not reach init"
wait_for_log 'wifi-ap: after restart wlan0 wpa_state=COMPLETED, holds \[wlan0\]' 60 \
  || report_failure "wpa_supplicant did not come back on wlan0 alone after a restart"
echo "after tars-service restart, a fresh wpa_supplicant reconnected wlan0"

# ── 검사 8: 나중에 생긴 wlan2를 hook이 넘기고 주소를 받는다 ─────────────
# 이 체인에서 가장 값진 대조다. 새 wpa_supplicant는 wlan2를 모른다 — 넘길 수
# 있는 것은 dhcpcd의 PREINIT에서 도는 10-tars-wifi뿐이다. hook을 지우면 wlan2는
# carrier를 영영 못 얻고 이 두 줄이 안 나온다.
wait_for_log 'wifi-ap: wlan2 is back in the root namespace' 60 \
  || report_failure "the probe never brought wlan2 back"
wait_for_log 'tars-wifi: handed wlan2 to wpa_supplicant' 30 \
  || report_failure "the dhcpcd hook did not hand wlan2 to wpa_supplicant"
wait_for_log 'wlan2: leased 192\.168\.77\.[0-9]+ ' 60 \
  || report_failure "dhcpcd never leased an address on the late wlan2"
echo "the dhcpcd hook handed the late wlan2 over and it got an address"

stop_guest

# ══ 부팅 B: 틀린 비밀번호 ══════════════════════════════════════════════
echo "=== boot B: two hwsim radios, a wrong passphrase ==="
LOG="$LOG_B"
boot "$DISK_B" " mac80211_hwsim.radios=2"

# ── 검사 9: 연결이 안 서고 부팅은 끝난다 ────────────────────────────────
# 4-way handshake가 실패하면 wpa_supplicant가 이 줄을 찍고 그 네트워크를 잠시 쉰다.
# 프롬프트는 그것과 무관하게 뜬다(feedback_boot_never_blocks).
wait_for_log 'wifi-ap: ap up on wlan1 in netns ap' 90 \
  || report_failure "the AP never came up in boot B"
wait_for_log 'CTRL-EVENT-SSID-TEMP-DISABLED .*reason=WRONG_KEY' 60 \
  || report_failure "wpa_supplicant never reported a wrong key"
wait_for_log 'terminal: screen>' 60 \
  || report_failure "the guest did not reach a prompt with a wrong passphrase"
# TC-M1부터 이 부팅의 뒤쪽에서 프로브가 비밀번호를 고친다. "연결이 안 섰다"는 그 앞의 로그로만
# 본다 — 고친 줄(`wifi-ap: tc [`)이 찍히기 전까지다.
wait_for_log 'wifi-ap: tc \[' 90 || report_failure "the probe never ran tars-config wifi"
FIX_LINE="$(grep -an 'wifi-ap: tc \[' "$LOG" | head -n 1 | cut -d: -f1)"
for bad in 'CTRL-EVENT-CONNECTED' 'wlan0: leased'; do
  if head -n "$FIX_LINE" "$LOG" | grep -a "$bad" >/dev/null; then
    report_failure "a wrong passphrase still produced '${bad}'"
  fi
done
echo "a wrong passphrase is refused, no address, and the boot still ends at a prompt"

# ── 검사 12: tars-config wifi가 고친 비밀번호로 붙는다 (TC-M1) ────────────
# 사람이 `wpa_passphrase … > /config/wpa_supplicant.conf`로 하던 일이다. 그 명령은 같은 SSID의
# 덩어리를 wpa_passphrase가 지은 것으로 바꾸고(평문 #psk 줄은 버린다), 파일이 이미 있었으니
# 재부팅이 아니라 재시작을 말한다. 프로브가 그 말대로 재시작하면 연결이 서고 주소가 온다.
grep -aF 'wifi-ap: tc [wifi: tars-wl replaced in /config/wpa_supplicant.conf|apply now: tars-service restart wpa_supplicant|]' "$LOG" >/dev/null \
  || report_failure "tars-config wifi did not replace the tars-wl block and point at a restart"
# 차례로 #psk 줄 0 · 64자리 psk 줄 1 · 그 SSID 1 · 사람의 country 줄 1 · 모드 600.
grep -aF 'wifi-ap: tc file [0 1 1 1 600]' "$LOG" >/dev/null \
  || report_failure "the file tars-config wrote is not one hashed block with the country kept and mode 600"
wait_for_log 'wlan0: CTRL-EVENT-CONNECTED - Connection to .* completed' 60 \
  || report_failure "wlan0 never connected after tars-config fixed the passphrase"
wait_for_log 'wlan0: leased 192\.168\.77\.[0-9]+ ' 60 \
  || report_failure "dhcpcd never leased an address after the fix"
echo "tars-config wifi replaced the wrong passphrase, and the restart it asked for brought wlan0 up with an address"

stop_guest

# ══ 부팅 C: 파일도 라디오도 없다 ═══════════════════════════════════════
echo "=== boot C: no wpa_supplicant.conf, no radios parameter ==="
LOG="$LOG_C"
boot "$DISK_C" ""

# ── 검사 10: 파일이 없으면 wifi는 꺼져 있고, 라디오는 기본이 0이다 ──────
# 앞은 결정 4의 음성이다. 뒤는 결정 2다 — 내장 cmdline의 radios=0이 빠지면 모든
# 제품 부팅에 가짜 wlan0 · wlan1이 생기고 dhcpcd가 그것을 붙잡는다.
wait_for_log 'terminal: screen>' 120 \
  || report_failure "the guest did not reach a prompt without wifi"
grep -a "tars-init: no /config/wpa_supplicant.conf, wifi stays off" "$LOG" >/dev/null \
  || report_failure "init did not say why wifi stays off"
for bad in 'started service wpa_supplicant' 'tars-wifi:' 'wlan'; do
  if grep -a "$bad" "$LOG" >/dev/null; then
    report_failure "found '${bad}' in a boot with no file and no radios"
  fi
done
echo "no file means no wpa_supplicant, and hwsim makes no radios by default"

# ── 검사 11: usbcore가 USB 동글 드라이버 열하나를 등록했다 (UW-M1) ──────
# 검사 1은 "켜기로 했다"까지다. 이 줄은 usb_register_driver가 찍으므로 커널이 드라이버를
# USB 코어에 실제로 올렸다는 뜻이다(UW design 실측 5). 장치와 무관하게 일어나서 이
# 부팅에는 USB 컨트롤러가 없어도 된다. 꽂힌 동글의 probe와 firmware는 게이트 밖이다.
for drv in rtw88_8822bu rtw88_8822cu rtw88_8723du rtw88_8821cu rtw88_8821au \
  rtw88_8812au rtw88_8814au rtw89_8851bu rtw89_8852bu mt7921u mt7925u; do
  grep -a "usbcore: registered new interface driver ${drv}\b" "$LOG" >/dev/null \
    || report_failure "usbcore never registered ${drv}"
done
echo "usbcore registered all eleven USB dongle drivers"

stop_guest

echo "WL-M3 PASS: wifi connects at boot and when late, refuses a wrong key, stays off without a file"
