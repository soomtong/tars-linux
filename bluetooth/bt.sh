#!/bin/sh
# bluetooth 체인의 게스트 쪽(BT-M2). 설정 디스크의 services.d/bt로 들어가서 init이 부팅
# 때 띄운다 — 체인은 한 글자도 안 친다(WL의 ap.sh와 같은 모양). 이 스크립트가 가상
# 컨트롤러 둘을 만들고, 사람이 할 일(페어링 · 재시작 · 끄기)을 대신 하고, 판정할 사실을
# `bt-probe:` 줄로 콘솔에 찍는다. 판정은 bluetooth/check.sh가 한다.
#
# 데몬 둘(dbus · bluetoothd)은 이 스크립트가 아니라 init이 띄운다 — 디스크의 tars.conf에
# bluetooth=on이 있다. 이 스크립트는 그것이 떴는지 기다릴 뿐이다.
#
# 컨트롤러는 btvirt(BlueZ의 에뮬레이터, 설정 디스크의 /config/bt/btvirt)가 /dev/vhci로
# 만든다. -l2는 LE 컨트롤러 둘을 가상 링크로 잇는다 — A(bluetoothctl의 기본 어댑터)가
# 스캔 · 페어하는 쪽, B가 광고하는 쪽이다(BT design 실측 7).
#
# bluetoothctl은 stdout이 tty가 아니면 끝날 때까지 한 줄도 안 쓴다(실측 7) — 파일로 받고
# quit 뒤에 읽는다. 에이전트는 A 쪽 하나(NoInputNoOutput, Just Works)만 둔다. btmgmt는
# stdin이 /dev/null이면 멈추므로 안 쓴다.
exec > /dev/console 2>&1 < /dev/null
say() { echo "bt-probe: $*"; }
clean() { sed 's/\x1b\[[0-9;]*m//g; s/\r//g; s/\x1b\[[0-9]*[A-Za-z]//g; s/\[[^]]*\]> *//g' "$1" | grep -av '^[[:space:]]*$'; }
BTV=/config/bt/btvirt

# 0. 데몬 둘이 뜰 때까지. tars-bluetoothd가 버스를 기다리므로 bluetoothd가 떠 있으면 둘 다 떴다.
for _ in $(seq 1 120); do
  pgrep -x bluetoothd > /dev/null && [ -S /run/dbus/system_bus_socket ] && break
  sleep 0.5
done
sleep 2
say "pids dbus=$(pgrep -x dbus-daemon | tr '\n' ' ')bluetoothd=$(pgrep -x bluetoothd | tr '\n' ' ')"
for n in /dev/vhci /dev/uhid /var/lib/bluetooth; do
  if [ -e "$n" ]; then say "node $n present"; else say "node $n MISSING"; fi
done
say "link $(readlink /var/lib/bluetooth)"

# 1. 가상 컨트롤러 둘. bluetoothd가 AutoEnable로 켠다.
"$BTV" -l2 > /tmp/btvirt.log 2>&1 &
for _ in $(seq 1 40); do
  [ "$(bluetoothctl list 2>/dev/null | grep -c '^Controller')" -ge 2 ] && break
  sleep 0.5
done
bluetoothctl list > /tmp/list 2>&1
A=$(grep -o '[0-9A-F:]\{17\}' /tmp/list | sed -n 1p)
B=$(grep -o '[0-9A-F:]\{17\}' /tmp/list | sed -n 2p)
say "controllers $(grep -c '^Controller' /tmp/list) A=$A B=$B"
say "powered A $(bluetoothctl show "$A" 2>/dev/null | tr -d '\r' | sed -n 's/^[[:space:]]*Powered: //p')"
sleep 2
say "settings [$(find /config/bluetooth -mindepth 2 -maxdepth 2 -name settings 2>/dev/null | sort | tr "\n" " " | sed "s/ $//")]"

# 2. 페어링. B가 광고하고 A가 스캔 · pair · trust한다.
( sleep 2; echo "agent off"; sleep 1; echo "select $B"; sleep 1; echo "pairable on"; echo "discoverable on"; sleep 1
  echo "advertise on"; sleep 45; echo quit ) | bluetoothctl > /tmp/outb 2>&1 &
sleep 7
( sleep 2; echo "agent off"; sleep 1; echo "agent NoInputNoOutput"; sleep 1; echo "default-agent"; sleep 1
  echo "scan on"; sleep 8; echo "pair $B"; sleep 15; echo "trust $B"; sleep 2; echo "info $B"; sleep 2; echo quit ) | bluetoothctl > /tmp/outa 2>&1
clean /tmp/outa > /tmp/outa.clean
say "pair $(grep -c 'Bonded: yes' /tmp/outa.clean) bonded, $(grep -c 'Connected: yes' /tmp/outa.clean) connected, $(grep -c 'Failed' /tmp/outa.clean) failed"
INFO="/config/bluetooth/$A/$B/info"
if [ -f "$INFO" ]; then
  say "info $INFO [$(grep -o '^\[[A-Za-z]*\]' "$INFO" | tr '\n' ' ' | sed 's/ $//')] $(grep '^Trusted=' "$INFO")"
else
  say "info $INFO MISSING"
fi

# 3. 사람이 재시작을 친다. 새 bluetoothd가 디스크의 키를 되읽어 B를 안다.
OLD=$(pgrep -x bluetoothd)
say "restart: $(tars-service restart bluetoothd 2>&1 | tail -n 1)"
for _ in $(seq 1 60); do
  NEW=$(pgrep -x bluetoothd); [ -n "$NEW" ] && [ "$NEW" != "$OLD" ] && bluetoothctl list 2>/dev/null | grep '^Controller' > /dev/null && break
  sleep 0.5
done
sleep 2
# info는 B를 아는 어댑터(A)를 골라야 한다 — 재시작 뒤 bluetoothctl의 기본 어댑터가 바뀔 수 있다. 한 줄 명령은 select를
# 못 하므로 파이프로 친다(stdout은 tty가 아니라 quit 뒤에 읽는다).
( sleep 2; echo "select $A"; sleep 1; echo "info $B"; sleep 1; echo quit ) | bluetoothctl > /tmp/outi 2>&1
say "after restart pid $OLD -> $(pgrep -x bluetoothd | tr "\n" " ")controllers $(bluetoothctl list 2>/dev/null | grep -c "^Controller") paired $(clean /tmp/outi | sed -n "s/^[[:space:]]*Paired: //p" | head -n 1)"

# 4. 사람이 끈다. reload가 둘을 내린다(BT design 결정 5 — 재부팅 없이).
say "set: $(tars-config set bluetooth=off 2>&1 | tail -n 1)"
say "reload: $(tars-config reload 2>&1 | tr '\n' '|')"
for _ in $(seq 1 40); do
  pgrep -x bluetoothd > /dev/null || pgrep -x dbus-daemon > /dev/null || break
  sleep 0.5
done
say "after off dbus=[$(pgrep -x dbus-daemon | tr '\n' ' ')] bluetoothd=[$(pgrep -x bluetoothd | tr '\n' ' ')]"
# 버스가 없을 때 사람이 bluetoothctl을 치면 — 감싸개가 켜는 법을 말하고 1로 끝난다(SIGABRT가 아니다).
CTL="$(bluetoothctl list 2>&1)"; CTL_RC=$?
say "ctl off rc=${CTL_RC} ${CTL}"
say "done"
exec sleep 100000
