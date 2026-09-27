#!/bin/sh
# wifi 체인의 게스트 쪽(WL-M3). 설정 디스크의 services.d/ap로 들어가서 init이
# 부팅 때 띄운다 — 체인은 한 글자도 안 친다. 이 스크립트가 게스트 안에 AP를
# 세우고, 사람이 할 일(재시작 · 장치 꽂기)을 대신 하고, 판정할 사실을
# `wifi-ap:` 줄로 콘솔에 찍는다. 판정은 wifi/check.sh가 한다.
#
# 라디오 셋(부팅 A, cmdline의 mac80211_hwsim.radios=3):
#   phy0/wlan0  제품의 클라이언트. tars-wifi가 부팅 때 argv로 넘긴다
#   phy1/wlan1  AP. netns ap로 옮겨 hostapd와 udhcpd를 띄운다 — root ns의
#               wpa_supplicant와 dhcpcd가 못 보고, 패킷이 로컬 지름길이 아니라
#               무선 경로를 탄다(WL design 결정 7)
#   phy2/wlan2  늦은 인터페이스. netns park에 숨겼다가 wpa_supplicant를 재시작해
#               잊게 한 뒤 꺼낸다 — dhcpcd의 hook만이 그것을 넘길 수 있다
# 부팅 B는 /config/wl/mode가 ap-only라 AP만 세우고 멈춘다.
#
# 목록은 대괄호로 감싸 찍는다. 콘솔 줄에는 앞에 프롬프트의 escape가, 끝에 tty의
# \r이 붙을 수 있어서 체인이 ^ · $ 앵커를 못 쓴다 — 목록의 끝은 `]`가 말한다.
#
# 옮기기 전에 wpa_supplicant가 인터페이스를 다 잡을 때까지 기다린다. 시작하는
# 동안 명령줄 인터페이스가 사라지면 wpa_supplicant가 죽는다(WL design 위험 6).
exec > /dev/console 2>&1 < /dev/null
W=/config/wl
say() { echo "wifi-ap: $*"; }
mode="$(cat $W/mode 2>/dev/null)"
global=/run/wpa_supplicant/global

# 1. 제품이 라디오를 다 잡을 때까지
want="wlan0 wlan1"
[ "$mode" = full ] && want="wlan0 wlan1 wlan2"
for i in $(seq 1 60); do
  have="$(wpa_cli -g $global interface 2>/dev/null)"
  missing=""
  for w in $want; do echo "$have" | grep -qx "$w" || missing="$missing $w"; done
  [ -z "$missing" ] && break
  sleep 0.25
done
say "wpa_supplicant holds [$want] (pid $(pgrep -x wpa_supplicant))"

# 2. AP
ip netns add ap
iw phy phy1 set netns name ap
ip netns exec ap ip link set lo up
ip netns exec ap ip link set wlan1 up
ip netns exec ap ip addr add 192.168.77.1/24 dev wlan1
printf 'interface=wlan1\ndriver=nl80211\nssid=tars-wl\nhw_mode=g\nchannel=1\nwpa=2\nwpa_passphrase=tars-secret\nwpa_key_mgmt=WPA-PSK\nrsn_pairwise=CCMP\n' > /run/hostapd.conf
ip netns exec ap $W/hostapd -B /run/hostapd.conf > /dev/null
printf 'start 192.168.77.100\nend 192.168.77.150\ninterface wlan1\nlease_file /run/udhcpd.leases\noption subnet 255.255.255.0\n' > /run/udhcpd.conf
touch /run/udhcpd.leases
ip netns exec ap $W/busybox udhcpd /run/udhcpd.conf
ip netns exec ap $W/busybox nc -l -p 7777 -e echo TARS-WL-PONG &
if [ "$mode" = full ]; then
  ip netns add park
  iw phy phy2 set netns name park
fi
say "ap up on wlan1 in netns ap"

if [ "$mode" != full ]; then exec sleep 100000; fi

# 3. wlan0이 주소를 받을 때까지. 받는 것은 제품의 dhcpcd다.
for i in $(seq 1 120); do
  ip -4 addr show wlan0 | grep -q 'inet 192\.168\.77\.' && break
  sleep 0.5
done
say "wlan0 $(ip -4 addr show wlan0 | grep -o 'inet [0-9.]*')"
say "tcp $($W/busybox nc -w 5 192.168.77.1 7777 < /dev/null)"
say "reg $(iw reg get | grep -m1 '^country')"
say "wpa pid $(pgrep -x wpa_supplicant)"

# 4. 사람이 재시작을 친다. 새 wpa_supplicant는 wlan0만 센다(wlan2는 park에 있다).
say "restart: $(tars-service restart wpa_supplicant 2>&1 | tail -n 1)"
for i in $(seq 1 60); do
  wpa_cli -p /run/wpa_supplicant -i wlan0 status 2>/dev/null | grep -qx wpa_state=COMPLETED && break
  sleep 0.5
done
say "after restart wlan0 $(wpa_cli -p /run/wpa_supplicant -i wlan0 status 2>/dev/null | grep wpa_state), holds [$(wpa_cli -g $global interface 2>/dev/null | grep -x 'wlan[0-9]' | tr '\n' ' ' | sed 's/ $//')]"

# 5. 늦은 인터페이스. 사람이 부팅 뒤에 동글을 꽂는 것과 같다.
ip netns exec park iw phy phy2 set netns 1
say "wlan2 is back in the root namespace"
exec sleep 100000
