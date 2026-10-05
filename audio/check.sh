#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# AU 체인 — 게스트의 스피커와 마이크에 바이트가 오간다.
#
# QEMU에 노트북의 HDA를 흉내 내는 장치를 붙인다(q35의 ich9-intel-hda와 스피커 하나 ·
# 마이크 하나를 가진 hda-micro 코덱). 커널의 snd-hda-intel과 범용 코덱 드라이버가 그것을
# 카드 0으로 올리고, 설정 디스크의 services.d/probe(= audio/probe.sh)가 사람이 치는 명령
# 그대로(aplay · speaker-test · arecord) 소리를 내고 받는다. 이 스크립트는 게스트에 한
# 글자도 안 친다.
#
# 판정이 바이트로 닫히는 것이 이 체인의 성질이다(AU design 결정 5). QEMU의 오디오
# 백엔드를 alsa로 두고, 컨테이너의 alsa-lib이 읽는 .asoundrc에 file 플러그인 둘을
# 정의한다.
#
#   스피커 → tarstap   게스트가 낸 샘플이 컨테이너의 파일(TAP)에 그대로 쌓인다
#   마이크 ← tarsfeed  컨테이너의 파일(FEED)이 게스트의 마이크로 들어간다
#
# 그래서 "재생이 됐다"는 게스트가 보낸 사각파가 TAP에 값까지 같게 있는 것이고, "녹음이
# 됐다"는 FEED의 상수가 게스트가 쓴 cap.wav에 값까지 같게 있는 것이다. QEMU의 wav
# 백엔드는 녹음 쪽이 없어서(`Could not create a backend for voice 'adc'`) 마이크를 못 본다.
#
# 이 체인이 못 보는 것 — 실기의 코덱(Realtek 등) · DSP(SOF · ACP) · USB 오디오 · 헤드폰
# 잭의 꽂힘(AU-M2 · M3), 부팅이 믹서를 되살리는 것(AU-M1). 검사 4가 지금은 "부팅이 소리를
# 꺼 둔 채 둔다"를 보고, M1이 그 검사를 뒤집는다.

# $GUEST_MEM 하나 때문에 source한다. nic · wifi 체인처럼 타이핑을 안 한다.
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

DISK=../out/audio.img
LOG="$(mktemp)"
WORK="$(mktemp -d)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  rm -rf "$LOG" "$WORK"
}
trap cleanup EXIT

report_failure() {
  echo "FAIL: $1"
  echo "--- markers (${LOG}) ---"
  local marker
  for marker in \
    "snd_hda_codec_generic hdaudioC0D0: autoconfig" \
    "tars-init: started service probe (pid" \
    "audio-probe: card [" \
    "audio-probe: aplay -l [card 0" \
    "audio-probe: master now [" \
    "audio-probe: aplay exit 0" \
    "audio-probe: speaker-test exit 0" \
    "audio-probe: arecord exit 0" \
    "audio-probe: done"; do
    if grep -aF "$marker" "$LOG" >/dev/null; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- audio-probe lines ---"
  grep -a "audio-probe:" "$LOG" | tail -n 20
  echo "--- last 40 lines ---"
  tail -n 40 "$LOG"
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

# ── 검사 1: 커널과 initrd가 소리를 안다 (부팅 없음) ─────────────────────
# 심볼 다섯. SYSVIPC가 여기 있는 이유는 alsa-lib의 기본 장치(dmix · dsnoop)가 SysV
# 세마포어와 공유 메모리로 여러 프로그램을 섞기 때문이다 — 꺼져 있으면 -D hw:0은 돌고
# 기본 장치만 `unable to create IPC semaphore`로 죽는다(AU design 결정 3).
CONFIG=../kernel/.config
for sym in SOUND SND SND_HDA_INTEL SND_HDA_GENERIC SYSVIPC; do
  if ! grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is not =y in kernel/.config"
    exit 1
  fi
done

# 바이너리 넷(guest_tools.sh 층 14)은 tools 체인의 검사 1이 목록을 되읽어 본다. 여기는
# 목록에 없고 make_initrd.sh가 손으로 넣는 것만 literal로 적는다 — 그래야 이 검사가
# tautology가 아니다(tools 체인의 WANT와 같은 이유).
INITRD_LIST="$(gzip -dc ../kernel/initrd.cpio | cpio -it 2>/dev/null)"
PADDED_LIST=$'\n'"${INITRD_LIST}"$'\n'
for want in usr/bin/arecord lib/x86_64-linux-gnu/libasound.so.2 \
  usr/share/alsa/alsa.conf usr/share/alsa/cards/HDA-Intel.conf \
  usr/share/alsa/pcm/dmix.conf usr/share/alsa/pcm/dsnoop.conf \
  usr/share/sounds/alsa/Front_Left.wav usr/share/sounds/alsa/Front_Right.wav; do
  case "$PADDED_LIST" in
    *$'\n'"${want}"$'\n'*) ;;
    *)
      echo "FAIL: ${want} is missing from the initrd"
      exit 1
      ;;
  esac
done
GROUPS_FILE="$(gzip -dc ../kernel/initrd.cpio | cpio -i --to-stdout etc/group 2>/dev/null)"
case $'\n'"${GROUPS_FILE}" in
  *$'\n'"audio:x:"*) ;;
  *)
    echo "FAIL: the initrd's /etc/group has no audio group; dmix and dsnoop need its name"
    exit 1
    ;;
esac
echo "the kernel carries ALSA and HDA, and the initrd carries arecord, libasound, its config, two voices and the audio group"

# ── 재료: 사각파 · 마이크에 넣을 상수 · 설정 디스크 · .asoundrc ─────────
# 컨테이너에 python이 없어서 perl로 짓는다(lessons).
#
# tone.wav — 48kHz 스테레오 16비트 1초. 24프레임마다 +8000과 -8000을 오가는 1kHz
# 사각파다. 값이 둘뿐이라 TAP에서 그 둘을 세면 된다. 48kHz인 이유는 dmix의 기본
# 속도와 같아서 리샘플이 안 끼기 때문이다 — 끼면 값이 바뀐다.
# feed.raw — 왼쪽 3000 · 오른쪽 -5000의 상수 10초. 두 채널이 다른 값이라 좌우가
# 바뀌어도 드러난다. 10초는 녹음 2초보다 넉넉하게.
TONE_FRAMES=48000
perl -e '
  my $n = shift; my $data = "";
  for my $i (0 .. $n - 1) { my $v = (int($i / 24) % 2) ? -8000 : 8000; $data .= pack("s<s<", $v, $v); }
  print "RIFF", pack("V", 36 + length $data), "WAVEfmt ", pack("VvvVVvv", 16, 1, 2, 48000, 192000, 4, 16),
        "data", pack("V", length $data), $data;' "$TONE_FRAMES" > "$WORK/tone.wav"
perl -e 'print pack("s<s<", 3000, -5000) x 480000' > "$WORK/feed.raw"

mkdir -p ../out "$WORK/seed/services.d" "$WORK/seed/audio"
cp probe.sh "$WORK/seed/services.d/probe"
chmod 0755 "$WORK/seed/services.d/probe"
cp "$WORK/tone.wav" "$WORK/seed/audio/tone.wav"
printf 'shell=fish\n' > "$WORK/seed/tars.conf"
rm -f "$DISK"
truncate -s 16M "$DISK"
mkfs.ext2 -F -q -m 0 -L tars-audio -d "$WORK/seed" "$DISK"

# null이 시간을 내고 file이 바이트를 바꿔치기한다. 녹음 쪽은 null이 준 무음을 infile의
# 바이트로 덮고, 재생 쪽은 받은 바이트를 file에 쓴다. 둘 다 alsa-lib에 들어 있는
# 플러그인이라 컨테이너에 더 깔 것이 없다.
cat > "$WORK/.asoundrc" <<EOF
pcm.tarstap {
  type file
  slave.pcm "null"
  file "$WORK/tap.raw"
  format "raw"
}
pcm.tarsfeed {
  type file
  slave.pcm "null"
  file "/dev/null"
  infile "$WORK/feed.raw"
  format "raw"
}
EOF

# ══ 부팅 하나 ═══════════════════════════════════════════════════════════
# q35인 이유는 nic · machine 체인과 같다 — 노트북에 가까운 칩셋이고, ich9-intel-hda가
# 노트북의 HDA 컨트롤러와 같은 계열이다. hda-micro는 스피커 하나와 마이크 하나를 가진
# 코덱이다(노트북의 내장 스피커 · 마이크와 같은 모양). 백엔드의 속도와 형식을 48kHz
# 스테레오 16비트로 박아 QEMU가 샘플을 바꾸지 않게 한다. try-poll=off는 null 장치에
# 기다릴 fd가 없어서다.
echo "=== boot: q35 with an HDA controller and a speaker + microphone codec ==="
HOME="$WORK" qemu-system-x86_64 \
  -machine q35 \
  -nic none \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -drive file="$DISK",if=virtio,format=raw \
  -audiodev alsa,id=snd0,out.dev=tarstap,in.dev=tarsfeed,out.frequency=48000,in.frequency=48000,out.channels=2,in.channels=2,out.format=s16,in.format=s16,out.try-poll=off,in.try-poll=off \
  -device ich9-intel-hda \
  -device hda-micro,audiodev=snd0 \
  -serial file:"$LOG" \
  -no-reboot &
QEMU_PID=$!

# ── 검사 2: 커널이 코덱을 찾아 카드 0을 만들었나 ────────────────────────
# 코덱 줄은 커널의 것이고 카드 줄은 /proc/asound/cards의 첫 줄이다. 노드 셋은 사람이
# 여는 파일이다 — 제어(controlC0) · 재생(pcmC0D0p) · 녹음(pcmC0D0c).
wait_for_log 'snd_hda_codec_generic hdaudioC0D0: autoconfig for Generic' 60 \
  || report_failure "the HDA codec was never configured (no snd_hda_codec_generic autoconfig line)"
wait_for_log 'audio-probe: done' 90 \
  || report_failure "the probe did not finish"
stop_guest
if ! grep -aE 'audio-probe: card \[ ?0 \[.*\]: HDA-Intel - ' "$LOG" >/dev/null; then
  report_failure "card 0 is not the HDA controller"
fi
if ! grep -aF 'audio-probe: nodes [controlC0 pcmC0D0c pcmC0D0p timer]' "$LOG" >/dev/null; then
  report_failure "/dev/snd does not hold the control, playback and capture nodes of card 0"
fi
echo "the kernel configured the codec as card 0 with a playback and a capture node"

# ── 검사 3: 도구가 라이브러리와 설정을 지나 카드를 보나 ─────────────────
# aplay · arecord는 libasound를 부르고, libasound는 /usr/share/alsa/alsa.conf를 읽어야
# 장치 목록을 낸다. 둘 중 하나라도 빠지면 이 줄들의 대괄호 안이 비거나 에러다.
if ! grep -aF 'audio-probe: aplay -l [card 0: Intel [HDA Intel], device 0: Generic Analog [Generic Analog]]' "$LOG" >/dev/null; then
  report_failure "aplay -l does not list the speaker"
fi
if ! grep -aF 'audio-probe: arecord -l [card 0: Intel [HDA Intel], device 0: Generic Analog [Generic Analog]]' "$LOG" >/dev/null; then
  report_failure "arecord -l does not list the microphone"
fi
echo "aplay -l and arecord -l both see card 0 device 0"

# ── 검사 4: 부팅은 소리를 꺼 둔 채 둔다 (AU-M1이 뒤집는다) ─────────────
# 아래 검사 5 · 7의 대조군이다. 프로브가 켜기 전의 믹서가 꺼져 있으므로, 5 · 7이
# 초록이면 그것은 프로브의 amixer 두 줄이 한 일이다 — 그 두 줄을 지우면 5가 무음으로
# 빨개진다(AU-M0 plan의 mutation 3). M1이 부팅에서 소리를 켜면 이 검사가 그 일을 본다.
if ! grep -aE 'audio-probe: master at boot \[.*Playback 0 \[0%\].*\[off\]\]' "$LOG" >/dev/null; then
  report_failure "Master was not muted at boot; if something now unmutes it, AU-M1 owns this check"
fi
if ! grep -aE 'audio-probe: capture at boot \[.*Capture 0 \[0%\].*\[off\]\]' "$LOG" >/dev/null; then
  report_failure "Capture was not off at boot; if something now turns it on, AU-M1 owns this check"
fi
if ! grep -aE 'audio-probe: master now \[.*Playback 74 \[100%\] \[0\.00dB\] \[on\]\]' "$LOG" >/dev/null; then
  report_failure "amixer could not set Master to 0dB and unmute it"
fi
echo "the boot leaves Master and Capture muted, and amixer turns them on"

# TAP의 프레임을 갈래로 센다. tone은 사각파의 두 값, left · right는 한쪽만 소리가 있는
# 것(speaker-test의 목소리), other는 두 채널이 다 0이 아니면서 사각파도 아닌 것이다.
# first_*는 그 갈래가 처음 나온 프레임 번호다.
count_tap() {
  perl -e '
    open(my $f, "<:raw", $ARGV[0]) or die "cannot open $ARGV[0]\n"; local $/; my $d = <$f>;
    my ($i, $tone, $l, $r, $o, $z, $fl, $fr) = (0, 0, 0, 0, 0, 0, -1, -1);
    for (my $p = 0; $p + 4 <= length $d; $p += 4, $i++) {
      my ($a, $b) = unpack("s<s<", substr($d, $p, 4));
      if (($a == 8000 && $b == 8000) || ($a == -8000 && $b == -8000)) { $tone++ }
      elsif ($a == 0 && $b == 0) { $z++ }
      elsif ($b == 0) { $l++; $fl = $i if $fl < 0 }
      elsif ($a == 0) { $r++; $fr = $i if $fr < 0 }
      else { $o++ }
    }
    print "frames=$i tone=$tone left=$l right=$r other=$o zero=$z first_left=$fl first_right=$fr\n";' "$1"
}
field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }

# ── 검사 5: 재생 — 게스트의 사각파가 값까지 같게 스피커에 닿았나 ───────
# 48,000프레임 중 47,000 이상을 요구한다. 기본 장치(dmix)는 한 프로그램만 쓸 때 샘플을
# 안 바꾸고, 사본에서 세 판 다 48,000이었다. 여유 1,000은 스트림 끝의 자투리 몫이다.
# other가 0인 것은 섞이거나 깎인 샘플이 없다는 뜻이다.
if ! grep -aF 'audio-probe: aplay exit 0 []' "$LOG" >/dev/null; then
  report_failure "aplay through the default device failed"
fi
[ -f "$WORK/tap.raw" ] || report_failure "QEMU never opened the speaker side (no tap file)"
TAP="$(count_tap "$WORK/tap.raw")"
echo "tap: ${TAP}"
if [ "$(field "$TAP" tone)" -lt 47000 ]; then
  report_failure "the square wave did not reach the speaker (tone frames $(field "$TAP" tone) of ${TONE_FRAMES}); silence means the mixer was muted"
fi
if [ "$(field "$TAP" other)" -ne 0 ]; then
  report_failure "the speaker got $(field "$TAP" other) frame(s) that are neither the square wave nor one-sided"
fi
echo "aplay's square wave reached the speaker sample for sample"

# ── 검사 6: 왼쪽이 먼저, 오른쪽이 나중 ─────────────────────────────────
# speaker-test -c 2 -t wav는 "Front Left"를 왼쪽 채널에만, 그다음 "Front Right"를 오른쪽에만
# 낸다. 좌우가 바뀌거나 목소리 파일이 없으면 여기서 갈린다.
if ! grep -aF 'audio-probe: speaker-test exit 0 [ 0 - Front Left| 1 - Front Right]' "$LOG" >/dev/null; then
  report_failure "speaker-test did not play Front Left then Front Right"
fi
if [ "$(field "$TAP" left)" -lt 10000 ] || [ "$(field "$TAP" right)" -lt 10000 ]; then
  report_failure "speaker-test's voices did not reach one channel each (left $(field "$TAP" left), right $(field "$TAP" right))"
fi
if [ "$(field "$TAP" first_left)" -ge "$(field "$TAP" first_right)" ]; then
  report_failure "the right channel spoke before the left one"
fi
echo "speaker-test spoke on the left channel, then on the right"

# ── 검사 7: 녹음 — 마이크에 넣은 상수가 값까지 같게 파일에 남았나 ──────
# 2초 × 48kHz = 96,000프레임 전부가 (3000, -5000)이어야 한다. 기본 장치(dsnoop)를 지난다.
if ! grep -aF 'audio-probe: arecord exit 0 []' "$LOG" >/dev/null; then
  report_failure "arecord through the default device failed"
fi
debugfs -R "dump audio/cap.wav $WORK/cap.wav" "$DISK" >/dev/null 2>&1
[ -s "$WORK/cap.wav" ] || report_failure "the guest left no cap.wav on the config disk"
CAP="$(perl -e '
  open(my $f, "<:raw", $ARGV[0]) or die; local $/; my $d = <$f>;
  my ($n, $m) = (0, 0);
  for (my $p = 44; $p + 4 <= length $d; $p += 4) { $n++; $m++ if substr($d, $p, 4) eq pack("s<s<", 3000, -5000) }
  print "frames=$n match=$m\n";' "$WORK/cap.wav")"
echo "cap: ${CAP}"
if [ "$(field "$CAP" frames)" -ne 96000 ] || [ "$(field "$CAP" match)" -ne 96000 ]; then
  report_failure "the microphone did not deliver the fed constant (${CAP}, want 96000 of each); zeros mean Capture was off"
fi
echo "arecord got the microphone's constant on both channels, 96000 frames of 96000"

echo "AU check PASS"
