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
#   D  다른 디스크로 떠서 부팅 뒤에 monitor로 USB 스피커(QEMU usb-audio)를 꽂는다.
#      init이 기본 재생 카드를 USB로 옮기고(검사 12 · 13), 녹음은 HDA에 남고(검사 14),
#      뽑으면 기본이 HDA로 돌아온다(검사 15). 판정은 여전히 샘플의 값이다 — USB 쪽
#      소리는 QEMU의 둘째 오디오 백엔드가 또 하나의 file 플러그인으로 받는다
#
#      부팅 D는 끝에 DSP 쪽 둘도 본다(AU-M3) — 커널이 SOF · ACP 드라이버를 올렸고 QEMU의
#      HDA는 여전히 snd_hda_intel이다(검사 16), alsactl init이 내장 마이크 스위치를
#      켠다(검사 17)
#
# 이 체인이 못 보는 것 — 실기의 코덱(Realtek 등, 검사 1이 심볼과 표로만 본다) ·
# DSP의 실제 probe와 firmware 로딩(SOF · ACP — QEMU에 그 장치가 없어 검사 1이 심볼 ·
# 표 · firmware 이름으로, 검사 16 · 17이 드라이버 등록과 마이크 스위치 규칙으로만
# 본다) · 녹음이 DMIC로 가는 것(호스트 검사 audio_test만 본다) · 헤드폰 잭의
# 꽂힘(QEMU 코덱에 잭 감지가 없다) · 마이크 달린 USB 헤드셋(QEMU usb-audio는 재생뿐이다).

# $GUEST_MEM 하나 때문에 source한다. nic · wifi 체인처럼 타이핑을 안 한다.
source ../gate_lib.sh

# 부팅 D만 monitor를 쓴다 — USB 스피커를 뽑고 꽂는 device_del · device_add(AU-M2).
MONITOR_PORT=45491

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
DISK_USB=../out/audio-usb.img
LOG="$(mktemp)"
WORK="$(mktemp -d)"
QEMU_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  # 시리얼 로그는 안 지운다 — 루트 check.sh가 회차 디렉터리에서 끼어든 줄을 센다(AL-M0).
  rm -rf "$WORK"
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
    "tars-init: audio: default card is" \
    "audio-probe: unplug now" \
    "audio-probe: plug now" \
    "audio-probe: dsp drivers [" \
    "audio-probe: dmic after init exit" \
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

# AU-M2. 노트북의 코덱 드라이버와 USB 오디오. QEMU의 코덱은 범용 파서가 받으므로 코덱
# 드라이버는 부팅으로 못 본다 — 심볼과, 커널이 코덱의 번호(벤더 · 장치)를 드라이버에
# 잇는 표(modinfo alias)를 드라이버마다 하나씩 본다(UW의 방식). Realtek은 6.18에서 계열
# 열로 갈렸고 EXPERT 없이는 하나씩 못 끈다 — 노트북의 거의 전부인 ALC2xx는 ALC269 계열이다.
for sym in SND_HDA_CODEC_REALTEK SND_HDA_CODEC_ALC269 SND_HDA_CODEC_CONEXANT \
  SND_HDA_CODEC_SENARYTECH SND_HDA_CODEC_CIRRUS SND_HDA_CODEC_CS420X SND_HDA_CODEC_CS8409 SND_HDA_CODEC_ANALOG \
  SND_HDA_CODEC_SIGMATEL SND_HDA_CODEC_VIA SND_USB_AUDIO; do
  if ! grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is not =y in kernel/.config"
    exit 1
  fi
done
# 코덱 드라이버 넷이 SND_CTL_LED를 거쳐 NEW_LEDS를 켜고, 그러면 기본값이 y인 입력 쪽
# 둘이 따라 켜진다. HID_APPLE은 Apple 키보드의 fn 키를 커널이 바꿔 keyboard=apple과
# 부딪칠 수 있고, INPUT_LEDS는 키보드 LED를 LED 클래스로 내놓는다 — 둘 다 소리와
# 무관하므로 끈 채 둔다(AU-M2 plan 확정 1).
for sym in HID_APPLE INPUT_LEDS; do
  if grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} came on with the LED class; the sound drivers must not touch input"
    exit 1
  fi
done
MODINFO=../kernel/build/modules.builtin.modinfo
for alias in snd_hda_codec_alc269.alias=hdaudio:v10EC0256r snd_hda_codec_conexant.alias=hdaudio:v14F11F86r \
  snd_hda_codec_senarytech.alias=hdaudio:v1FA86186r snd_hda_codec_cs420x.alias=hdaudio:v10134208r \
  snd_hda_codec_cs8409.alias=hdaudio:v10138409r \
  snd_hda_codec_analog.alias=hdaudio:v11D41984r snd_hda_codec_idt.alias=hdaudio:v111D76E5r \
  snd_hda_codec_via.alias=hdaudio:v11060440r 'snd_usb_audio.alias=usb:v*p*d*dc*dsc*dp*ic01isc01ip*in*'; do
  if ! tr '\0' '\n' < "$MODINFO" | grep -F "$alias" >/dev/null; then
    echo "FAIL: the kernel has no ${alias%%.*} entry for ${alias#*alias=}"
    exit 1
  fi
done

# AU-M3. DSP 뒤의 내장 마이크. Intel은 SOF(세대마다 하나)와 그 아래 HDA 코덱을 받는
# 범용 machine, AMD는 세대마다의 PDM 드라이버(Renoir · Yellow Carp · ACP6.3)와 그
# machine, 그리고 ACP 7.x를 받는 범용 ACP 드라이버와 legacy machine이다(7.x는 BIOS가
# 따로 말하지 않으면 "DMIC만 legacy"로 정해져 PDM 드라이버가 물러난다 — acp-config.c).
# QEMU에 둘 다 없어서 심볼과 표(modinfo alias)로 본다. 범용 machine이 HDMI 코덱에 걸려
# 있어(Kconfig depends) SND_HDA_CODEC_HDMI도 켜진다.
for sym in SND_SOC SND_SOC_SOF_TOPLEVEL SND_SOC_SOF_PCI SND_SOC_SOF_INTEL_TOPLEVEL \
  SND_SOC_SOF_CANNONLAKE SND_SOC_SOF_COFFEELAKE SND_SOC_SOF_COMETLAKE SND_SOC_SOF_ICELAKE \
  SND_SOC_SOF_JASPERLAKE SND_SOC_SOF_TIGERLAKE SND_SOC_SOF_ELKHARTLAKE SND_SOC_SOF_ALDERLAKE \
  SND_SOC_SOF_METEORLAKE SND_SOC_SOF_LUNARLAKE SND_SOC_SOF_PANTHERLAKE \
  SND_SOC_SOF_HDA_LINK SND_SOC_SOF_HDA_AUDIO_CODEC SND_SOC_INTEL_SKL_HDA_DSP_GENERIC_MACH SND_HDA_CODEC_HDMI \
  SND_SOC_AMD_RENOIR SND_SOC_AMD_RENOIR_MACH SND_SOC_AMD_ACP6x SND_SOC_AMD_YC_MACH \
  SND_SOC_AMD_PS SND_SOC_AMD_PS_MACH SND_SOC_AMD_ACP_PCI SND_AMD_ASOC_ACP70 SND_SOC_AMD_LEGACY_MACH; do
  if ! grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is not =y in kernel/.config"
    exit 1
  fi
done
# 꺼져 있어야 하는 것. SOF_PCI를 켜면 세대마다의 심볼이 기본값으로 따라 켜지는데, 아래
# 넷(SKL · KBL · APL · GLK)과 Merrifield는 노트북에서 SOF로 안 가거나(SKL · KBL은 DSP
# 표가 HDA로 묶는다) Chromebook · UP 보드 · 태블릿의 것이고 firmware도 싣지 않는다.
# Atom의 SST는 ACPI면 기본으로 켜진다. SND_HDA_I915는 GPU 드라이버(i915 · xe)가 켤 때만
# 선다 — 서 있으면 SOF가 i915의 오디오 컴포넌트를 기다리느라 카드를 안 만들 수 있다
# (sound/soc/sof/intel/hda.c의 hda_codec_i915_init). 지금은 그 자리가 -ENODEV stub이다.
for sym in SND_SOC_SOF_SKYLAKE SND_SOC_SOF_KABYLAKE SND_SOC_SOF_APOLLOLAKE SND_SOC_SOF_GEMINILAKE \
  SND_SOC_SOF_MERRIFIELD SND_SST_ATOM_HIFI2_PLATFORM_ACPI SND_HDA_I915; do
  if grep -x "CONFIG_${sym}=y" "$CONFIG" >/dev/null; then
    echo "FAIL: CONFIG_${sym} is on; AU-M3 keeps it off"
    exit 1
  fi
done
for alias in snd_sof_pci_intel_cnl.alias=pci:v00008086d000002C8 snd_sof_pci_intel_icl.alias=pci:v00008086d000034C8 \
  snd_sof_pci_intel_tgl.alias=pci:v00008086d0000A0C8 snd_sof_pci_intel_tgl.alias=pci:v00008086d000051C8 \
  snd_sof_pci_intel_mtl.alias=pci:v00008086d00007E28 snd_sof_pci_intel_lnl.alias=pci:v00008086d0000A828 \
  snd_sof_pci_intel_ptl.alias=pci:v00008086d0000E428 snd_soc_skl_hda_dsp.alias=platform:skl_hda_dsp_generic \
  'snd_rn_pci_acp3x.alias=pci:v00001022d000015E2sv*sd*bc04sc80i00*' snd_acp3x_rn.alias=platform:acp_pdm_mach \
  snd_soc_acp6x_mach.alias=platform:acp_yc_mach snd_soc_ps_mach.alias=platform:acp_ps_mach \
  'snd_acp_pci.alias=pci:v00001022d000015E2sv*sd*bc*sc*i*' snd_acp_legacy_mach.alias=platform:acp-pdm-mach; do
  if ! tr '\0' '\n' < "$MODINFO" | grep -F "$alias" >/dev/null; then
    echo "FAIL: the kernel has no ${alias%%.*} entry for ${alias#*alias=}"
    exit 1
  fi
done
# SOF는 firmware가 없으면 HDA로 돌아오지 않고 카드를 아예 안 만든다(스피커까지 조용).
# 그래서 커널 안에 있는 SOF firmware 이름(sof-<세대>.ri)이 전부 firmware 목록의 initrd
# 경로 끝에 있어야 한다. 이름은 커널 이미지에서 읽는다 — 커널이 세대를 하나 더 켜거나
# 커널을 올리면 여기서 걸린다. 목록의 파일이 initrd에 실제로 있는지는 tools 체인의
# 검사 1b가 본다.
. ../kernel/guest_firmware.sh
FW_DESTS=$'\n'"$(printf '%s\n' "${GUEST_FIRMWARE[@]}" | sed 's/^[^:]*://; s#.*/##')"$'\n'
# 이름은 커널 이미지와 SOF Intel 드라이버의 오브젝트 둘에 다 있는 것이다. 이미지에는 AMD
# SOF용 machine 표(sound/soc/amd/acp-config.c — sof-rn · sof-rmb · sof-vangogh)도 들어
# 있는데 AMD SOF 드라이버는 꺼져 있어 아무도 그 이름을 안 찾는다. 오브젝트만 보면 지난
# 설정으로 빌드된 채 남은 것까지 센다 — 둘의 교집합이 "지금 링크된 Intel SOF"다.
SOF_NAMES="$(comm -12 <(strings -n 6 ../kernel/build/vmlinux | grep -xE 'sof-[a-z0-9-]+\.ri' | sort -u) \
  <(strings -n 6 ../kernel/build/sound/soc/sof/intel/*.o | grep -xE 'sof-[a-z0-9-]+\.ri' | sort -u))"
if [ -z "$SOF_NAMES" ]; then
  echo "FAIL: no sof-*.ri name in the kernel image; SOF did not build"
  exit 1
fi
for name in $SOF_NAMES; do
  case "$FW_DESTS" in
    *$'\n'"${name}"$'\n'*) ;;
    *)
      echo "FAIL: the kernel asks for ${name} but kernel/guest_firmware.sh does not carry it"
      exit 1
      ;;
  esac
done

# 바이너리 넷(guest_tools.sh 층 14)은 tools 체인의 검사 1이 목록을 되읽어 본다. 여기는
# 목록에 없고 make_initrd.sh가 손으로 넣는 것만 literal로 적는다 — 그래야 이 검사가
# tautology가 아니다(tools 체인의 WANT와 같은 이유).
INITRD_LIST="$(gzip -dc ../kernel/initrd.cpio | cpio -it 2>/dev/null)"
PADDED_LIST=$'\n'"${INITRD_LIST}"$'\n'
for want in usr/bin/arecord lib/x86_64-linux-gnu/libasound.so.2 \
  usr/share/alsa/alsa.conf usr/share/alsa/cards/HDA-Intel.conf \
  usr/share/alsa/pcm/dmix.conf usr/share/alsa/pcm/dsnoop.conf \
  usr/share/sounds/alsa/Front_Left.wav usr/share/sounds/alsa/Front_Right.wav \
  usr/share/alsa/init/00main usr/share/alsa/init/postinit/00-tars-dmic.conf; do
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
echo "the kernel carries ALSA, HDA, seven laptop codec drivers and USB audio, and the initrd carries arecord, libasound, its config, two voices and the audio group"
echo "the kernel carries SOF for $(printf '%s\n' $SOF_NAMES | wc -l) Intel firmware names and AMD ACP, and the firmware list carries every one of those names"

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
# 부팅 D의 디스크. 같은 씨앗에 표지 파일 하나가 더 있어 프로브가 usb 갈래로 간다.
touch "$WORK/seed/audio/usb"
rm -f "$DISK_USB"
truncate -s 16M "$DISK_USB"
mkfs.ext2 -F -q -m 0 -L tars-audio -d "$WORK/seed" "$DISK_USB"

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
pcm.tarsusb {
  type file
  slave.pcm "null"
  file "$WORK/usb.raw"
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
# usb는 부팅 D다 — 자기 디스크에, xHCI 컨트롤러와 USB 스피커가 쓸 둘째 오디오 백엔드
# (tarsusb), 꽂고 뽑을 monitor가 붙는다. 스피커 자체는 부팅 뒤에 device_add로 꽂는다 —
# 부팅 때 꽂아 둔 usb-audio는 다섯 판 중 한 판에서 커널이 아예 못 봤다(AU-M2 plan 확정 4).
# usb-audio는 48kHz 스테레오 16비트 재생 하나뿐인 장치라 백엔드를 HDA 쪽과 같은
# 모양으로 박는다.
start_guest() {
  local drive=() usb=()
  case "$1" in
    with-disk) drive=(-drive file="$DISK",if=virtio,format=raw) ;;
    usb)
      drive=(-drive file="$DISK_USB",if=virtio,format=raw)
      usb=(-audiodev alsa,id=snd1,out.dev=tarsusb,in.dev=tarsfeed,out.frequency=48000,in.frequency=48000,out.channels=2,in.channels=2,out.format=s16,in.format=s16,out.try-poll=off,in.try-poll=off
        -device qemu-xhci,id=xhci
        -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait)
      ;;
  esac
  # 부팅마다 새 로그다(AL-M0). 예전에는 같은 파일을 비우고 다시 써서 루트 check.sh가
  # 회차 디렉터리에서 셀 때 마지막 부팅 하나만 남았다.
  LOG="$(mktemp)"
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
    "${usb[@]}" \
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

# ══ 부팅 D: 부팅 뒤에 꽂는 USB 스피커 (AU-M2) ═══════════════════════════
# HDA(카드 0)로 떠서 USB 스피커를 꽂으면 카드 1이 생긴다. init은 /dev/snd를 1초마다
# 보고 /etc/asound.conf에 기본 카드를 적는다 — 재생과 녹음 각각, 장치 0을 가진 카드 중
# 번호가 가장 큰 것. 그래서 재생은 USB로, 녹음은 마이크 없는 USB 대신 HDA로 간다.
# 프로브가 "plug now" · "unplug now"를 찍으면 이 스크립트가 monitor로 꽂고 뽑는다.
#
# 소리가 어디로 갔는지는 두 파일로 본다. HDA 쪽 TAP은 QEMU가 부팅 때 한 번 열고, USB
# 쪽 USB_TAP은 스피커를 꽂을 때 연다. 뽑기 전에 둘 다 옆으로 떠 두고 센다.
echo "=== boot D: an HDA card, then a USB speaker plugged and unplugged with the monitor ==="
rm -f "$WORK/tap.raw" "$WORK/usb.raw"
start_guest usb
wait_for_log 'audio-probe: plug now' 90 \
  || report_failure "boot D: the probe never asked for the USB speaker"
# QEMU가 monitor 포트를 연 지 오래인 시점이라 첫 번에 붙는다.
CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || report_failure "boot D: could not connect to the QEMU monitor"
echo "device_add usb-audio,id=usbspk,audiodev=snd1,bus=xhci.0" >&3
wait_for_log 'audio-probe: unplug now' 60 \
  || report_failure "boot D: the probe never got to unplugging the USB speaker"

# ── 검사 12: 꽂힌 USB 스피커가 카드 1이 되고 init이 기본 재생을 그리로 옮겼다 ──
# usbcore 줄은 커널이 snd-usb-audio를 USB 코어에 올렸다는 뜻이고(장치와 무관하게
# 찍힌다), 카드 줄은 그 드라이버가 꽂힌 장치를 실제로 받았다는 뜻이다. init의 줄
# 둘은 부팅 때(HDA뿐)와 꽂은 뒤다.
grep -a 'usbcore: registered new interface driver snd-usb-audio' "$LOG" >/dev/null \
  || report_failure "usbcore never registered snd-usb-audio"
grep -aE 'audio-probe: usb card \[ ?1 \[.*\]: USB-Audio - ' "$LOG" >/dev/null \
  || report_failure "the plugged USB speaker did not become card 1"
grep -aF 'audio-probe: default before plug [default "0"|default "0"|ctl.card 0]' "$LOG" >/dev/null \
  || report_failure "before the plug /etc/asound.conf did not point both ways at card 0"
grep -aF 'tars-init: audio: default card is 1 for playback, 0 for capture' "$LOG" >/dev/null \
  || report_failure "init did not move the default playback card to the plugged USB speaker"
grep -aF 'audio-probe: default after plug [default "1"|default "0"|ctl.card 1]' "$LOG" >/dev/null \
  || report_failure "/etc/asound.conf does not send playback to card 1 and capture to card 0"
echo "the plugged USB speaker came up as card 1 and init made it the default for playback"

# ── 검사 13: 사람이 친 amixer · aplay가 USB 스피커로 갔다 ────────────────
# amixer에 -c가 없으므로 그 100%는 믹서의 기본 카드(defaults.ctl.card)가 받은 것이다.
# 사각파는 값까지 같게 USB 쪽에 있고 HDA 쪽에는 한 프레임도 없다.
grep -aE "audio-probe: usb volume \[.*Playback 256 \[100%\]" "$LOG" >/dev/null \
  || report_failure "amixer without -c did not reach the USB speaker's volume"
grep -aF 'audio-probe: plugged aplay exit 0 []' "$LOG" >/dev/null \
  || report_failure "aplay through the default device failed with the USB speaker in"
cp "$WORK/usb.raw" "$WORK/usb_1.raw" 2>/dev/null || report_failure "QEMU never opened the USB speaker's side (no usb tap file)"
cp "$WORK/tap.raw" "$WORK/tap_1.raw" 2>/dev/null || : > "$WORK/tap_1.raw"
USB_1="$(count_tap "$WORK/usb_1.raw")"
HDA_1="$(count_tap "$WORK/tap_1.raw")"
echo "usb tap: ${USB_1}"
echo "hda tap: ${HDA_1}"
if [ "$(field "$USB_1" tone)" -lt 40000 ] || [ "$(field "$USB_1" other)" -ne 0 ]; then
  report_failure "the square wave did not reach the USB speaker sample for sample (${USB_1})"
fi
if [ "$(field "$HDA_1" tone)" -ne 0 ]; then
  report_failure "the square wave also reached the HDA speaker (${HDA_1})"
fi
echo "amixer and aplay went to the USB speaker, and the HDA speaker stayed silent"

# ── 검사 14: 녹음은 HDA의 마이크에 남았다 (판정은 아래, 끈 뒤에 파일로) ──
# USB 스피커에는 녹음 장치가 없다. 기본을 한 카드로 묶었다면 arecord가 여기서 죽는다.
grep -aF 'audio-probe: plugged arecord exit 0 []' "$LOG" >/dev/null \
  || report_failure "arecord through the default device failed with the USB speaker in"

# ── 뽑는다 ─────────────────────────────────────────────────────────────
echo "device_del usbspk" >&3
wait_for_log 'audio-probe: done' 30 \
  || report_failure "boot D: the probe did not finish after the USB speaker went"

# ── 검사 15: 뽑으면 기본이 HDA로 돌아온다 ─────────────────────────────
# init의 "0 for playback, 0 for capture"가 두 번이다 — 부팅 때와 뽑은 뒤.
if [ "$(grep -acF 'tars-init: audio: default card is 0 for playback, 0 for capture' "$LOG")" -ne 2 ]; then
  report_failure "init did not move the default back to card 0 after the USB speaker went"
fi
grep -aF 'audio-probe: default after unplug [default "0"|default "0"|ctl.card 0]' "$LOG" >/dev/null \
  || report_failure "after the unplug /etc/asound.conf still points away from card 0"
grep -aF 'audio-probe: unplugged aplay exit 0 []' "$LOG" >/dev/null \
  || report_failure "aplay failed after the USB speaker went"

# ── 검사 16: 커널이 DSP 드라이버를 올렸고, QEMU의 HDA는 HDA에 남았다 (AU-M3) ──
# SOF 여섯(세대 묶음마다 PCI 드라이버 하나)과 AMD 넷이 PCI 버스에 등록됐다. 장치가 없어
# probe는 안 돈다. 그리고 QEMU의 컨트롤러(ICH9)는 DSP 표에 없으므로 SOF를 켠 뒤에도
# snd_hda_intel이 받는다 — 위 검사 2 ~ 15가 그 카드로 돈 것이다.
grep -aF 'audio-probe: dsp drivers [snd_acp_pci|snd_pci_acp6x|snd_pci_ps|snd_rn_pci_acp3x|sof-audio-pci-intel-cnl|sof-audio-pci-intel-icl|sof-audio-pci-intel-lnl|sof-audio-pci-intel-mtl|sof-audio-pci-intel-ptl|sof-audio-pci-intel-tgl]' "$LOG" >/dev/null \
  || report_failure "the kernel did not register the six SOF and four AMD ACP PCI drivers"
grep -aF 'audio-probe: card 0 driver [snd_hda_intel]' "$LOG" >/dev/null \
  || report_failure "QEMU's HDA controller is not driven by snd_hda_intel any more"
# 실기에서 SOF가 실패하면 사람이 커널 인자 snd_intel_dspcfg.dsp_driver=1로 HDA에 돌아온다.
# 그 이름이 커널에 있어야 그 탈출로가 선다.
grep -aF 'audio-probe: dsp_driver [0]' "$LOG" >/dev/null   || report_failure "the kernel has no snd_intel_dspcfg.dsp_driver parameter; the way back to HDA is gone"
echo "the kernel registered the SOF and ACP drivers, QEMU's HDA stayed with snd_hda_intel, and snd_intel_dspcfg.dsp_driver is there"

# ── 검사 17: alsactl init이 내장 마이크 스위치를 켠다 (AU-M3) ───────────
# SOF는 Dmic0 Capture Switch를 꺼진 채 올리고 alsactl의 범용 규칙은 그 이름을 모른다.
# initrd의 postinit 규칙이 켠다. QEMU에는 그 컨트롤이 없어서 프로브가 같은 이름의 사용자
# 컨트롤을 꺼진 채 만들고 init의 일꾼과 같은 argv로 다시 init한다 — 99는 범용 규칙으로
# 켰다는 뜻이고 M1의 일꾼도 같은 코드를 받는다.
grep -aF 'audio-probe: dmic control made exit 0 [  : values=off]' "$LOG" >/dev/null \
  || report_failure "the probe could not make a Dmic0 Capture Switch to test the rule on"
grep -aF 'audio-probe: dmic after init exit 99 [  : values=on]' "$LOG" >/dev/null \
  || report_failure "alsactl init did not turn Dmic0 Capture Switch on; the postinit rule is missing or wrong"
echo "alsactl init turned a Dmic0 Capture Switch on through the postinit rule"
sleep 0.5
HDA_2="$(count_tap "$WORK/tap.raw")"
echo "hda tap after unplug: ${HDA_2}"
if [ "$(field "$HDA_2" tone)" -lt 40000 ] || [ "$(field "$HDA_2" other)" -ne 0 ]; then
  report_failure "after the unplug the square wave did not reach the HDA speaker sample for sample (${HDA_2})"
fi
stop_guest
echo "unplugged, the default went back to the HDA card and aplay played there"

debugfs -R "dump audio/cap.wav $WORK/cap_d.wav" "$DISK_USB" >/dev/null 2>&1
[ -s "$WORK/cap_d.wav" ] || report_failure "boot D left no cap.wav on its config disk"
CAP_D="$(perl -e '
  open(my $f, "<:raw", $ARGV[0]) or die; local $/; my $d = <$f>;
  my ($n, $m) = (0, 0);
  for (my $p = 44; $p + 4 <= length $d; $p += 4) { $n++; $m++ if substr($d, $p, 4) eq pack("s<s<", 3000, -5000) }
  print "frames=$n match=$m\n";' "$WORK/cap_d.wav")"
echo "cap D: ${CAP_D}"
if [ "$(field "$CAP_D" frames)" -ne 48000 ] || [ "$(field "$CAP_D" match)" -ne 48000 ]; then
  report_failure "with the USB speaker in, arecord did not record the HDA microphone (${CAP_D}, want 48000 of each)"
fi
echo "with the USB speaker in, arecord still recorded the HDA microphone, 48000 frames of 48000"

echo "AU check PASS"
