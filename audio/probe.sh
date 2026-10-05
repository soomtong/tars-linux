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
# 끝나면 잠든다. 감독자는 끝난 서비스를 다시 띄우므로(SV), 일을 마친 뒤에 나가면
# 같은 소리를 세 번 내고 포기한다.

say() { echo "audio-probe: $*"; }

# 여러 줄 출력을 한 줄로. 콘솔 줄은 앞뒤에 다른 바이트가 붙을 수 있어서(lessons 68)
# 체인이 줄 끝을 앵커로 못 쓴다 — 끝을 봐야 하는 것은 대괄호로 감싼다.
flat() { tr '\n' '|' | sed 's/|$//'; }

# 1. 카드. HDA 코덱 탐색은 커널이 일 큐에서 하므로 init보다 늦을 수 있다. 5초까지 본다.
for _ in $(seq 1 50); do
  [ -e /dev/snd/controlC0 ] && break
  sleep 0.1
done
say "card [$(head -n 1 /proc/asound/cards)]"
say "nodes [$(ls /dev/snd | tr '\n' ' ' | sed 's/ $//')]"
say "aplay -l [$(aplay -l 2>&1 | grep '^card ' | flat)]"
say "arecord -l [$(arecord -l 2>&1 | grep '^card ' | flat)]"

# 2. 부팅이 남긴 믹서. 커널의 HDA 드라이버는 Master와 Capture를 0에 꺼 둔 채 뜬다.
# AU-M1이 부팅에서 되살리기 전까지는 사람이 아래 3을 손으로 한다.
say "master at boot [$(amixer -c 0 sget Master 2>&1 | tail -n 1)]"
say "capture at boot [$(amixer -c 0 sget Capture 2>&1 | tail -n 1)]"

# 3. 사람이 하는 일 — 소리를 켠다. 0dB인 이유는 체인이 샘플을 바이트로 비교하기
# 때문이다. QEMU의 HDA 코덱이 이 값을 샘플에 그대로 곱한다.
amixer -q -c 0 sset Master 0dB unmute
amixer -q -c 0 sset Capture 0dB cap
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

exec sleep 100000
