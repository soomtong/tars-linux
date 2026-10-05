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
# 부팅이 셋이다(AU-M1).
#
#   A  새 디스크. init이 alsactl init으로 소리를 켠다(검사 4). 프로브가 사람처럼 Master를
#      0dB로 올리고, 소리를 내고 받고(검사 5~7), 전원을 끈다. init이 끄는 길에서
#      alsactl store로 그 0dB를 디스크의 asound.state에 적는다(검사 8)
#   B  같은 디스크. init이 alsactl restore로 0dB를 되살리고, 프로브는 믹서를 안 만진 채
#      재생한다 — 사각파가 값까지 같으면 A의 0dB가 남은 것이다(검사 9 · 10)
#   C  설정 디스크 없이(ISO와 같은 모양). init이 alsactl init으로 켜기만 한다(검사 11)
#
# 이 체인이 못 보는 것 — 실기의 코덱(Realtek 등) · DSP(SOF · ACP) · USB 오디오 · 헤드폰
# 잭의 꽂힘 · 부팅 뒤에 꽂힌 카드(AU-M2 · M3).

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
    "tars-init: audio: alsactl" \
    "tars-init: started service probe (pid" \
    "audio-probe: boot " \
    "audio-probe: card [" \
    "audio-probe: aplay -l [card 0" \
    "audio-probe: master now [" \
    "audio-probe: aplay exit 0" \
    "audio-probe: speaker-test exit 0" \
    "audio-probe: arecord exit 0" \
    "audio-probe: done" \
    "tars-init: audio: stored the mixer" \
    "tars-init: calling reboot"; do
    if grep -aF "$marker" "$LOG" >/dev/null; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- audio lines ---"
  grep -aE "audio-probe:|tars-init: audio:" "$LOG" | tail -n 24
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

# 게스트가 스스로 꺼지기를 기다린다(power 체인과 같은 판정 — 로그의 글자가 아니라
# 프로세스가 사라졌는가). 꺼졌으면 거두고 0이다.
wait_for_exit() {
  local seconds="$1" i
  for i in $(seq 1 "$seconds"); do
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
      wait "$QEMU_PID" 2>/dev/null || true
      QEMU_PID=""
      return 0
    fi
    sleep 1
  done
  return 1
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

# q35인 이유는 nic · machine 체인과 같다 — 노트북에 가까운 칩셋이고, ich9-intel-hda가
# 노트북의 HDA 컨트롤러와 같은 계열이다. hda-micro는 스피커 하나와 마이크 하나를 가진
# 코덱이다(노트북의 내장 스피커 · 마이크와 같은 모양). 백엔드의 속도와 형식을 48kHz
# 스테레오 16비트로 박아 QEMU가 샘플을 바꾸지 않게 한다. try-poll=off는 null 장치에
# 기다릴 fd가 없어서다.
#
# 인자 하나가 설정 디스크를 붙일지를 고른다(부팅 C는 안 붙인다). 로그는 부팅마다 비운다.
start_guest() {
  local drive=()
  [ "$1" = with-disk ] && drive=(-drive file="$DISK",if=virtio,format=raw)
  : > "$LOG"
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
    "${drive[@]}" \
    -audiodev alsa,id=snd0,out.dev=tarstap,in.dev=tarsfeed,out.frequency=48000,in.frequency=48000,out.channels=2,in.channels=2,out.format=s16,in.format=s16,out.try-poll=off,in.try-poll=off \
    -device ich9-intel-hda \
    -device hda-micro,audiodev=snd0 \
    -serial file:"$LOG" \
    -no-reboot &
  QEMU_PID=$!
}

# ══ 부팅 A: 새 디스크 ═══════════════════════════════════════════════════
echo "=== boot A: q35 with an HDA controller and a speaker + microphone codec, a fresh config disk ==="
start_guest with-disk

# ── 검사 2: 커널이 코덱을 찾아 카드 0을 만들었나 ────────────────────────
# 코덱 줄은 커널의 것이고 카드 줄은 /proc/asound/cards의 첫 줄이다. 노드 셋은 사람이
# 여는 파일이다 — 제어(controlC0) · 재생(pcmC0D0p) · 녹음(pcmC0D0c).
#
# 프로브는 일을 마치면 kill -TERM 1로 전원을 끈다. 그래서 여기서는 QEMU를 죽이지 않고
# 스스로 사라지기를 기다린다 — 그 길에서 init이 믹서를 적는다(검사 8).
wait_for_log 'snd_hda_codec_generic hdaudioC0D0: autoconfig for Generic' 60 \
  || report_failure "the HDA codec was never configured (no snd_hda_codec_generic autoconfig line)"
wait_for_log 'audio-probe: done' 90 \
  || report_failure "the probe did not finish"
wait_for_exit 30 \
  || report_failure "the guest never switched itself off after the probe's kill -TERM 1"
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

# ── 검사 4: 부팅이 소리를 켠다 (AU-M1) ──────────────────────────────────
# 커널은 Master와 Capture를 0에 꺼 둔 채 카드를 올린다(AU-M0의 이 검사가 그것을 봤다).
# 새 디스크에는 asound.state가 없으므로 init이 alsactl init을 부르고, 그 기본값이
# Master -20dB · Capture 0dB, 둘 다 켜짐이다. 프로브는 Capture를 안 만지므로 아래
# 검사 7의 녹음이 값까지 같으면 그것은 부팅이 켠 Capture가 한 일이다.
if ! grep -aF 'tars-init: audio: alsactl init turned the mixer on' "$LOG" >/dev/null; then
  report_failure "init did not turn the mixer on with alsactl init"
fi
if ! grep -aF 'audio-probe: boot first' "$LOG" >/dev/null; then
  report_failure "the probe found an asound.state on a fresh disk"
fi
if ! grep -aE 'audio-probe: master at boot \[.*Playback 54 \[73%\] \[-20\.00dB\] \[on\]\]' "$LOG" >/dev/null; then
  report_failure "Master was not at alsactl init's -20dB and on at boot"
fi
if ! grep -aE 'audio-probe: capture at boot \[.*Capture 74 \[100%\] \[0\.00dB\] \[on\]\]' "$LOG" >/dev/null; then
  report_failure "Capture was not at alsactl init's 0dB and on at boot"
fi
if ! grep -aE 'audio-probe: master now \[.*Playback 74 \[100%\] \[0\.00dB\] \[on\]\]' "$LOG" >/dev/null; then
  report_failure "amixer could not set Master to 0dB"
fi
# 음성. init은 alsactl에 -U를 준다 — 빠지면 alsactl이 initrd에 없는 UCM 설정을 찾다가
# 부팅마다 경고 두 줄을 찍는다(AU design 실측 10). UCM은 AU-M3의 질문이다.
if grep -aF 'ucm2/ucm.conf' "$LOG" >/dev/null; then
  report_failure "alsactl looked for UCM; init must pass -U until AU-M3 ships alsa-ucm-conf"
fi
echo "the boot turned Master and Capture on with alsactl init, and amixer raised Master to 0dB"

# TAP의 프레임을 갈래로 센다. tone은 사각파의 두 값, left · right는 한쪽만 소리가 있는
# 것(speaker-test의 목소리), doubled는 사각파의 정확히 두 배(±16000), other는 두 채널이
# 다 0이 아니면서 그 셋 다 아닌 것이다.
#
# doubled가 있는 이유(AU-M1 lead 실측). 호스트에 부하가 있으면 TCG 게스트의 하드웨어
# 포인터가 밀려 xrun이 나고, dmix는 그 구간의 샘플을 하드웨어 버퍼에 두 번 더한 뒤
# 나머지를 비운다 — 8000 + 8000 = 16000인 프레임 49개가 한 덩어리로 나오고 그 뒤가 0이다.
# 부하 없이 열다섯 판은 전부 0이었고, 부하를 걸면 다섯 판 중 둘이 그랬다. 우리 코드도
# 볼륨도 아닌 QEMU 쪽의 시간 문제라 세기만 하고 판정에 안 쓴다. 볼륨이 틀리면 값이
# ±800 같은 것이 되어 tone이 0이 된다 — 그것은 other가 아니라 tone의 하한이 잡는다.
# first_*는 그 갈래가 처음 나온 프레임 번호다.
count_tap() {
  perl -e '
    open(my $f, "<:raw", $ARGV[0]) or die "cannot open $ARGV[0]\n"; local $/; my $d = <$f>;
    my ($i, $tone, $l, $r, $o, $z, $dbl, $fl, $fr) = (0, 0, 0, 0, 0, 0, 0, -1, -1);
    for (my $p = 0; $p + 4 <= length $d; $p += 4, $i++) {
      my ($a, $b) = unpack("s<s<", substr($d, $p, 4));
      if (($a == 8000 && $b == 8000) || ($a == -8000 && $b == -8000)) { $tone++ }
      elsif (($a == 16000 && $b == 16000) || ($a == -16000 && $b == -16000)) { $dbl++ }
      elsif ($a == 0 && $b == 0) { $z++ }
      elsif ($b == 0) { $l++; $fl = $i if $fl < 0 }
      elsif ($a == 0) { $r++; $fr = $i if $fr < 0 }
      else { $o++ }
    }
    print "frames=$i tone=$tone left=$l right=$r other=$o doubled=$dbl zero=$z first_left=$fl first_right=$fr\n";' "$1"
}
field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }

# ── 검사 5: 재생 — 게스트의 사각파가 값까지 같게 스피커에 닿았나 ───────
# 48,000프레임 중 40,000 이상을 요구한다. 기본 장치(dmix)는 한 프로그램만 쓸 때 샘플을
# 안 바꾸고, 부하 없는 판은 48,000이다. 하한의 일은 음소거와 틀린 볼륨을 잡는 것이고
# 둘 다 tone이 0이다. 부하가 있으면 xrun이 프레임을 떨어뜨린다(위 doubled) — 부하를 건
# 다섯 판의 최소가 47,425였고, 하한을 47,000에 두면 그 판이 하한에 400 남짓으로 붙는다.
# other가 0인 것은 섞이거나 깎인 샘플이 없다는 뜻이다.
if ! grep -aF 'audio-probe: aplay exit 0 []' "$LOG" >/dev/null; then
  report_failure "aplay through the default device failed"
fi
[ -f "$WORK/tap.raw" ] || report_failure "QEMU never opened the speaker side (no tap file)"
TAP="$(count_tap "$WORK/tap.raw")"
echo "tap: ${TAP}"
if [ "$(field "$TAP" tone)" -lt 40000 ]; then
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

# ── 검사 8: 끄는 길에서 init이 믹서를 디스크에 적었나 ──────────────────
# store는 모든 프로세스를 거둔 뒤, sync 앞이다. 디스크의 asound.state에서 Master의
# 볼륨 줄을 읽어 프로브가 올린 74(0dB)인지 본다 — 부팅 B가 되살리는 것이 이 값이다.
if ! grep -aF 'tars-init: audio: stored the mixer in /config/asound.state' "$LOG" >/dev/null; then
  report_failure "init did not store the mixer on the way down"
fi
debugfs -R "dump asound.state $WORK/asound.state" "$DISK" >/dev/null 2>&1
[ -s "$WORK/asound.state" ] || report_failure "the config disk holds no asound.state after the power-off"
STATE_MASTER="$(perl -0777 -ne "print \$1 if /name 'Master Playback Volume'\s+value\.0 (\d+)/" "$WORK/asound.state")"
if [ "$STATE_MASTER" != 74 ]; then
  report_failure "asound.state keeps Master Playback Volume at '${STATE_MASTER}', want 74 (0dB)"
fi
echo "the power-off stored the mixer, and asound.state keeps Master at 74 (0dB)"
# 판정이 아니라 기록이다. 프로브가 kill -TERM 1을 친 uptime부터 커널이 전원을 내린
# 시각까지 — store가 종료 경로에 더한 몫이 이 안에 있다(상한 STORE_WAIT_MS 2초).
ASKED="$(grep -aoE 'audio-probe: powering off at uptime [0-9.]+' "$LOG" | grep -oE '[0-9.]+$')"
DOWN="$(grep -aoE '\[ *[0-9.]+\] reboot: Power down' "$LOG" | grep -oE '[0-9]+\.[0-9]+')"
echo "shutdown: asked at ${ASKED:-?}s, powered down at ${DOWN:-?}s"

# ══ 부팅 B: 같은 디스크 ════════════════════════════════════════════════
# 같은 tap 파일 이름을 QEMU가 다시 연다. A의 것은 옆으로 치운다.
mv "$WORK/tap.raw" "$WORK/tap_a.raw"
echo "=== boot B: the same disk again ==="
start_guest with-disk
wait_for_log 'audio-probe: done' 90 \
  || report_failure "the probe did not finish on the second boot"
stop_guest

# ── 검사 9: 부팅이 사람이 남긴 볼륨을 되살렸나 ─────────────────────────
# alsactl init이었다면 Master가 -20dB다. 0dB이면 A의 store를 B의 restore가 읽은 것이다.
if ! grep -aF 'tars-init: audio: alsactl restore set the mixer from /config/asound.state' "$LOG" >/dev/null; then
  report_failure "init did not restore the mixer from /config/asound.state"
fi
if ! grep -aF 'audio-probe: boot again' "$LOG" >/dev/null; then
  report_failure "the probe did not find the asound.state the first boot stored"
fi
if ! grep -aE 'audio-probe: master at boot \[.*Playback 74 \[100%\] \[0\.00dB\] \[on\]\]' "$LOG" >/dev/null; then
  report_failure "Master was not back at the 0dB the first boot left"
fi
if ! grep -aE 'audio-probe: capture at boot \[.*Capture 74 \[100%\] \[0\.00dB\] \[on\]\]' "$LOG" >/dev/null; then
  report_failure "Capture was not back at 0dB and on"
fi
echo "the second boot restored Master at 0dB and Capture on from the disk"

# ── 검사 10: 되살린 믹서로 사각파가 값까지 나가나 ─────────────────────
# 프로브는 이 부팅에서 amixer를 안 친다. 그래서 값이 같으면 그것은 되살린 0dB의 일이다.
if ! grep -aF 'audio-probe: aplay exit 0 []' "$LOG" >/dev/null; then
  report_failure "aplay failed on the second boot"
fi
[ -f "$WORK/tap.raw" ] || report_failure "QEMU never opened the speaker side on the second boot"
TAP_B="$(count_tap "$WORK/tap.raw")"
echo "tap B: ${TAP_B}"
if [ "$(field "$TAP_B" tone)" -lt 40000 ] || [ "$(field "$TAP_B" other)" -ne 0 ]; then
  report_failure "the restored mixer did not carry the square wave sample for sample (${TAP_B})"
fi
echo "with no amixer, aplay's square wave reached the speaker sample for sample"

# ══ 부팅 C: 설정 디스크 없이 ═══════════════════════════════════════════
# ISO만 꽂은 노트북과 같은 모양이다. 기억할 자리가 없으니 init만 한다. 프로브도 없으므로
# init의 줄 하나를 기다리고 끈다.
echo "=== boot C: no config disk ==="
start_guest no-disk

# ── 검사 11: 디스크가 없어도 소리가 켜진다 ─────────────────────────────
wait_for_log 'tars-init: audio: alsactl init turned the mixer on' 60 \
  || report_failure "without a config disk init did not turn the mixer on"
stop_guest
if ! grep -aF 'tars-init: no disk labelled tars-* among' "$LOG" >/dev/null; then
  report_failure "boot C found a config disk; it must boot without one"
fi
echo "without a config disk the boot still turned the mixer on with alsactl init"

echo "AU check PASS"
