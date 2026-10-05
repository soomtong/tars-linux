#!/usr/bin/bash
# AU 체인의 게스트 쪽 — 설정 디스크의 services.d/probe로 들어간다(wifi/ap.sh와 같은 자리).
#
# init이 /config/services.d의 실행 파일로 이것을 띄우고, 표준 출력은 init의 것(=
# /dev/console = 시리얼 로그)이다. 그래서 여기서 찍는 줄을 audio/check.sh가 시리얼
# 로그에서 본다. 게이트가 게스트에 한 글자도 안 치는 이유가 이것이다.
#
# 사람이 노트북에서 치는 것과 같은 명령만 쓴다 — aplay · arecord · amixer ·
# speaker-test, 장치를 고르는 -D 없이. 기본 장치(dmix · dsnoop)까지 지나야
# "사람이 aplay x.wav를 치면 소리가 난다"를 본 것이 되기 때문이다(AU design 결정 3).
#
# 같은 디스크로 두 번 뜬다(AU-M1). 어느 쪽인지는 /config/asound.state가 가른다 —
# 그 파일은 init이 끌 때 쓰므로 첫 부팅의 프로브가 시작할 때는 아직 없다.
#   first  사람이 볼륨을 바꾸고, 소리를 내고 받고, 전원을 끈다(kill -TERM 1)
#   again  믹서를 안 만지고 소리를 낸다. 첫 부팅이 바꾼 볼륨이 남았는지를 본다
# 셋째 갈래는 따로 만든 디스크다(AU-M2). /config/audio/usb가 있으면 그것이다.
#   usb    부팅 뒤에 꽂힌 USB 스피커로 기본 카드가 가고, 녹음은 HDA에 남고, 뽑으면
#          기본이 돌아오는 것을 소리로 본다. 꽂고 뽑는 것은 체인이 monitor로 한다
#
# 끝나면 잠든다. 감독자는 끝난 서비스를 다시 띄우므로(SV), 일을 마친 뒤에 나가면
# 같은 소리를 세 번 내고 포기한다.

say() { echo "audio-probe: $*"; }

# 여러 줄 출력을 한 줄로. 콘솔 줄은 앞뒤에 다른 바이트가 붙을 수 있어서(lessons 68)
# 체인이 줄 끝을 앵커로 못 쓴다 — 끝을 봐야 하는 것은 대괄호로 감싼다.
flat() { tr '\n' '|' | sed 's/|$//'; }

if [ -e /config/audio/usb ]; then boot=usb
elif [ -e /config/asound.state ]; then boot=again
else boot=first; fi
say "boot ${boot}"

# 1. 카드. HDA 코덱 탐색은 커널이 일 큐에서 하므로 init보다 늦을 수 있다. 5초까지 본다.
for _ in $(seq 1 50); do
  [ -e /dev/snd/controlC0 ] && break
  sleep 0.1
done
say "card [$(head -n 1 /proc/asound/cards)]"
say "nodes [$(ls /dev/snd | tr '\n' ' ' | sed 's/ $//')]"
say "aplay -l [$(aplay -l 2>&1 | grep '^card ' | flat)]"
say "arecord -l [$(arecord -l 2>&1 | grep '^card ' | flat)]"

# 2. 부팅이 켠 믹서(AU-M1). init의 일꾼도 이 카드를 기다렸다가 alsactl이 되므로 이
# 프로브와 나란히 돈다. alsactl이 끝나고 Master가 켜질 때까지 10초를 기다린다 —
# 켜는 것이 아무도 없으면 10초 뒤에 꺼진 그대로를 찍고, 체인이 그 값으로 빨개진다.
for _ in $(seq 1 100); do
  if ! pgrep -x alsactl >/dev/null && amixer -c 0 sget Master 2>/dev/null | grep '\[on\]' >/dev/null; then break; fi
  sleep 0.1
done
say "master at boot [$(amixer -c 0 sget Master 2>&1 | tail -n 1)]"
say "capture at boot [$(amixer -c 0 sget Capture 2>&1 | tail -n 1)]"

if [ "$boot" = usb ]; then
  # U. 기본 카드가 USB를 따라가나(AU-M2). init은 /dev/snd를 1초마다 보고
  # /etc/asound.conf를 다시 쓴다. 여기는 그 파일이 바뀔 때까지 기다리고 사람이
  # 치는 그대로 amixer · aplay · arecord를 친다 — 카드를 고르는 -c · -D 없이.
  # 꽂고 뽑는 것은 체인이 monitor로 한다. 이 갈래가 "plug now" · "unplug now"를 찍는다.
  # 파일의 카드 번호는 셋이다 — 재생 · 녹음의 getenv 기본값과 믹서의 카드. 믹서는
  # 재생 쪽을 따르므로 기다리는 것은 그 줄 하나다.
  wait_conf() { # $1 = 기다리는 재생 카드
    for _ in $(seq 1 50); do
      grep -qx "defaults.ctl.card $1" /etc/asound.conf 2>/dev/null && return 0
      sleep 0.2
    done
    return 1
  }
  conf() { say "$1 [$(grep -oE 'default "[0-9]+"|ctl\.card [0-9]+' /etc/asound.conf 2>&1 | flat)]"; }
  # HDA의 Master를 0dB로 둔다. 기본이 USB로 안 가고 HDA로 새면 그 사각파가 값까지
  # 같게 HDA 쪽 파일에 남아 체인이 그것을 본다.
  amixer -q -c 0 sset Master 0dB
  wait_conf 0
  conf "default before plug"
  say "plug now"
  wait_conf 1
  say "usb card [$(grep -E '^ ?1 \[' /proc/asound/cards | flat)]"
  conf "default after plug"
  # 사람이 하는 일 — 꽂은 USB의 볼륨을 올린다. -c가 없으므로 믹서의 기본 카드
  # (defaults.ctl.card)로 간다. QEMU usb-audio는 이 값으로 샘플을 줄이고 꽂힌 직후의
  # 240(-0.5dB)이면 8000이 7529가 된다 — 100%(256)라야 값이 그대로 나간다.
  amixer -q sset 'Audio Output Volume Control' 100%
  say "usb volume [$(amixer -c 1 sget 'Audio Output Volume Control' 2>&1 | tail -n 1)]"
  out="$(aplay -q /config/audio/tone.wav 2>&1)"; rc=$?
  say "plugged aplay exit ${rc} [$(printf '%s' "$out" | flat)]"
  out="$(arecord -q -d 1 -f S16_LE -r 48000 -c 2 /config/audio/cap.wav 2>&1)"; rc=$?
  say "plugged arecord exit ${rc} [$(printf '%s' "$out" | flat)]"
  sync
  say "unplug now"
  wait_conf 0
  conf "default after unplug"
  out="$(aplay -q /config/audio/tone.wav 2>&1)"; rc=$?
  say "unplugged aplay exit ${rc} [$(printf '%s' "$out" | flat)]"
  say "done"
  exec sleep 100000
fi

if [ "$boot" = again ]; then
  # 3'. 믹서를 안 만지고 재생한다. 사각파가 값까지 같게 나가면 첫 부팅이 바꾼 0dB가
  # 되살아난 것이다 — alsactl init의 -20dB였다면 값이 바뀐다.
  out="$(aplay -q /config/audio/tone.wav 2>&1)"; rc=$?
  say "aplay exit ${rc} [$(printf '%s' "$out" | flat)]"
  say "done"
  exec sleep 100000
fi

# 3. 사람이 하는 일 — 볼륨을 바꾼다. 부팅이 켠 Master는 -20dB이고 이것을 0dB로 올린다.
# 0dB인 이유는 체인이 샘플을 바이트로 비교하기 때문이다(QEMU의 HDA 코덱이 이 값을
# 샘플에 그대로 곱한다). Capture는 안 만진다 — 부팅이 켠 0dB 그대로 아래 5에서 쓴다.
amixer -q -c 0 sset Master 0dB
say "master now [$(amixer -c 0 sget Master 2>&1 | tail -n 1)]"

# 4. 재생 둘. 둘 다 기본 장치로 간다.
out="$(aplay -q /config/audio/tone.wav 2>&1)"; rc=$?
say "aplay exit ${rc} [$(printf '%s' "$out" | flat)]"
out="$(speaker-test -c 2 -t wav -l 1 2>&1)"; rc=$?
say "speaker-test exit ${rc} [$(printf '%s' "$out" | grep -E 'error|Front' | flat)]"

# 5. 녹음 2초. 파일은 설정 디스크에 남기고 체인이 끈 뒤에 debugfs로 꺼낸다.
out="$(arecord -q -d 2 -f S16_LE -r 48000 -c 2 /config/audio/cap.wav 2>&1)"; rc=$?
say "arecord exit ${rc} [$(printf '%s' "$out" | flat)]"
sync
say "done"

# 6. 전원을 끈다. 사람이 전원 버튼을 누르는 것과 같은 길이다(PID 1의 SIGTERM). init이
# 모두를 거둔 뒤 alsactl store로 위 3의 0dB를 /config/asound.state에 적는다. uptime은
# 체인이 커널의 `reboot: Power down` 시각과 빼서 끄는 데 걸린 시간을 찍는 데 쓴다.
say "powering off at uptime $(cut -d' ' -f1 /proc/uptime)"
kill -TERM 1
exec sleep 100000
