#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"

# VD 체인 — 게스트의 tars-dictate가 마이크의 바이트를 전사 API에 보내고 받은 글자를 낸다.
#
# 전사 API는 Groq가 아니라 컨테이너의 stub.pl이다(VD design 결정 5). QEMU의 guestfwd가
# 게스트의 10.0.2.100:8080 연결마다 그것을 띄운다 — 게이트는 바깥에 안 나가고 Groq의
# 무료 티어 한도를 한 번도 안 쓴다. 게스트의 /config/dictation.conf가 transcribe_url로 그
# 주소를 가리키고, 경로의 첫 마디가 stub의 답(정상 · 제어 문자 · 무음 · text 없음 · 429)을
# 고른다.
#
# 마이크는 audio 체인과 같은 수법이다(AU design 결정 5). QEMU의 HDA 마이크에 컨테이너
# alsa-lib의 file 플러그인(infile)이 상수를 넣는다. stub이 받은 WAV의 샘플이 그 상수면
# "녹음이 진짜 마이크를 지나 API까지 왔다"이다.
#
# 게스트에 한 글자도 안 친다. 설정 디스크의 services.d/probe(= probe.sh)가 사람이 셸에서
# 하는 일(설정 파일을 고치고 tars-dictate를 치고 Ctrl+C로 멈춘다)을 열 갈래로 하고
# `dictate-probe:` 줄로 찍는다. 끝나면 kill -TERM 1로 끄고, 이 스크립트가 디스크의
# dictation.jsonl을 debugfs로 꺼낸다. monitor를 안 쓴다.
#
# 하나 더 — TLS. 게스트의 curl이 인증 기관 목록(/etc/ssl/certs/ca-certificates.crt)을
# 읽는지를 컨테이너의 openssl s_server로 본다(검사 2). Groq는 https다.
#
# 부팅 B(VD-M1)는 terminal이 하는 일을 본다 — 오른쪽 Cmd 두 번(monitor의 sendkey meta_r 둘)이
# tars-dictate를 띄우고, 상태 줄 꼬리에 REC가 뜨고, 다시 두 번이 녹음을 끝내고, 받은 글자가
# 그 패널의 셸 프롬프트에 들어간다(bracketed paste, Enter 없음). Esc 취소 · 비밀번호 프롬프트 ·
# 다른 패널 · 닫힌 패널 · 상한으로 스스로 멈춘 녹음 · 키 없음을 차례로 친다. 판정은 terminal의
# `dictate>` · `status>` 줄과 화면 줄, stub이 받은 요청, 끈 뒤의 dictation.jsonl이다.
#
# 정리 단계(VD-M2)도 같은 stub이다 — 경로가 /chat/<답>/<갈래>면 chat completions로 답하고
# `stub-chat:` 줄을 남긴다. 부팅 A의 갈래 s11 ~ s21이 켜짐 · 꺼짐 · 정리본 · 원문으로 돌아가는 여섯을
# 친다(검사 24 ~ 29). 정리를 켠 채 cleanup_url을 안 적은 M0의 갈래는 기본 주소(api.groq.com)로
# 가는데, 프로브가 게스트의 /etc/hosts로 그 이름을 127.0.0.1로 돌려 둔다 — 검사 24가 그 거절을
# 본다. 부팅 B는 정리를 켠 채 돌아 terminal이 넣는 글자가 정리본이다.
#
# 이 체인이 못 보는 것 — 진짜 Groq의 답(사람이 키를 넣고 실기에서 본다, running-tars.md) ·
# 진짜 정리 모델이 뜻을 바꾸는지 · 실기 마이크의 소리 · 실기 자판의 오른쪽 Cmd(PC 자판은 오른쪽
# Alt — input_test 검사 78).

# 부팅 A는 $GUEST_MEM 하나 때문에, 부팅 B는 타이핑(type_keys · joined_screen_dump)
# 때문에 source한다.
source ../gate_lib.sh

# openssl s_server가 듣는 컨테이너의 포트. 게스트는 10.0.2.2:이 번호로 붙는다 — SLIRP이
# 그것을 컨테이너의 127.0.0.1로 잇는다(lessons 45). 45492는 VD의 첫 번호다(lessons 포트 절).
TLS_PORT=45492
# 부팅 B의 QEMU monitor(VD-M1). 45492가 TLS 상대라 그다음 번호다.
MONITOR_PORT_B=45493

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

# 받아쓰기의 판정기 · 단계 · 종료 코드 · 비밀번호 · 거르기(dictation_test)와 트리거 ·
# Esc의 키 경로(input_test)는 여기서 먼저 걸러진다 — 부팅 둘을 쓰기 전에 잡을 수 있는
# 실패다.
if ! (cd ../terminal && zig build test); then
  echo "FAIL: terminal host tests failed (dictation_test, input_test or status_test)"
  exit 1
fi

if ! (cd ../kernel && ./make_initrd.sh); then
  echo "FAIL: initrd build failed"
  exit 1
fi

DISK=../out/dictation.img
LOG="$(mktemp)"
WORK="$(mktemp -d)"
STUBLOG="$WORK/stub.log"
QEMU_PID=""
TLS_PID=""

cleanup() {
  exec 3<&- 2>/dev/null
  exec 3>&- 2>/dev/null
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  if [ -n "$TLS_PID" ] && kill -0 "$TLS_PID" 2>/dev/null; then
    kill "$TLS_PID" 2>/dev/null || true
    wait "$TLS_PID" 2>/dev/null || true
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
    "tars-init: started service probe (pid" \
    "dictate-probe: start" \
    "dictate-probe: hosts [127.0.0.1 api.groq.com]" \
    "dictate-probe: route [default via 10.0.2.2" \
    "dictate-probe: capture [" \
    "dictate-probe: tls default exit" \
    "dictate-probe: s1 exit" \
    "dictate-probe: s10 exit" \
    "dictate-probe: s21 exit" \
    "dictate-probe: tc key" \
    "dictate-probe: s22 exit" \
    "dictate-probe: done" \
    "tars-init: calling reboot"; do
    if grep -aF "$marker" "$LOG" >/dev/null; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  echo "--- probe lines ---"
  grep -a "dictate-probe:" "$LOG" | tail -n 30
  echo "--- stub log ---"
  cut -c 1-400 "$STUBLOG" 2>/dev/null
  echo "--- last 30 lines ---"
  tail -n 30 "$LOG"
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

# 게스트가 스스로 꺼지기를 기다린다(audio 체인과 같다).
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

# ── 검사 1: initrd가 tars-dictate와 인증 기관 목록을 싣는다 (부팅 없음) ──
# 목록의 수는 sysroot의 ca-certificates 패키지가 담은 인증서 수와 같아야 한다 —
# make_initrd.sh가 그것을 전부 이어 붙인다(update-ca-certificates가 하는 일).
INITRD_LIST="$(gzip -dc ../kernel/initrd.cpio | cpio -it 2>/dev/null)"
PADDED_LIST=$'\n'"${INITRD_LIST}"$'\n'
for want in usr/bin/tars-dictate etc/ssl/certs/ca-certificates.crt; do
  case "$PADDED_LIST" in
    *$'\n'"${want}"$'\n'*) ;;
    *)
      echo "FAIL: ${want} is missing from the initrd"
      exit 1
      ;;
  esac
done
BUNDLE_CERTS="$(gzip -dc ../kernel/initrd.cpio | cpio -i --to-stdout etc/ssl/certs/ca-certificates.crt 2>/dev/null | grep -c 'BEGIN CERTIFICATE')"
SYSROOT_CERTS="$(ls "${AMD64_SYSROOT:-/usr/local/amd64-sysroot}"/usr/share/ca-certificates/mozilla/*.crt | wc -l)"
if [ "$SYSROOT_CERTS" -lt 100 ] || [ "$BUNDLE_CERTS" -ne "$SYSROOT_CERTS" ]; then
  echo "FAIL: the initrd's CA bundle holds ${BUNDLE_CERTS} certificate(s), the sysroot has ${SYSROOT_CERTS}"
  exit 1
fi
if ! bash -n ../kernel/dictation/tars-dictate; then
  echo "FAIL: kernel/dictation/tars-dictate does not parse"
  exit 1
fi
echo "the initrd carries tars-dictate and a CA bundle of ${BUNDLE_CERTS} certificates"

# ── 재료: 마이크의 상수 · TLS 상대 · 설정 디스크 · .asoundrc ────────────
# feed.raw — 두 채널이 같은 상수 1234, 120초. 녹음은 48kHz 스테레오에서 plug가 16kHz
# 모노로 바꾼다. 두 채널을 같게 둔 것은 그 변환이 채널을 어떻게 섞든 값이 1234로 남게
# 하려는 것이다(채널을 섞는 규칙은 alsa-lib의 것이고 이 체인이 볼 것이 아니다). 120초는
# 열 번의 녹음과 그 사이를 넉넉히 덮는다.
FEED_VALUE=1234
perl -e 'print pack("s<s<", $ARGV[0], $ARGV[0]) x (48000 * 120)' "$FEED_VALUE" > "$WORK/feed.raw"

# 자기 서명 인증서. 10.0.2.2라는 IP를 이름으로 갖는다 — 게스트가 그 주소로 붙는다.
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=vd0-tls \
  -addext subjectAltName=IP:10.0.2.2 \
  -keyout "$WORK/tls.key" -out "$WORK/tls.pem" >/dev/null 2>&1 \
  || { echo "FAIL: openssl could not make the test certificate"; exit 1; }
openssl s_server -quiet -accept "127.0.0.1:${TLS_PORT}" -cert "$WORK/tls.pem" -key "$WORK/tls.key" -www \
  > "$WORK/tls.log" 2>&1 < /dev/null &
TLS_PID=$!
sleep 0.5
kill -0 "$TLS_PID" 2>/dev/null || { echo "FAIL: openssl s_server died at startup"; cat "$WORK/tls.log"; exit 1; }

mkdir -p ../out "$WORK/seed/services.d"
cp probe.sh "$WORK/seed/services.d/probe"
chmod 0755 "$WORK/seed/services.d/probe"
cp "$WORK/tls.pem" "$WORK/seed/vd0-tls.pem"
printf 'net=dhcp\n' > "$WORK/seed/tars.conf"
printf 'vd0-test-key\n' > "$WORK/seed/groq.key"
rm -f "$DISK"
truncate -s 16M "$DISK"
mkfs.ext2 -F -q -m 0 -L tars-dictate -d "$WORK/seed" "$DISK"

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

# q35 · HDA는 audio 체인과 같고, 네트워크는 net 체인과 같은 SLIRP이다. guestfwd의 cmd는
# 연결마다 새로 실행된다 — 경로에 쉼표가 없어야 한다(QEMU 옵션은 쉼표로 갈린다).
echo "=== boot: q35 with an HDA microphone, SLIRP with a transcription stub at 10.0.2.100:8080 ==="
: > "$LOG"
HOME="$WORK" qemu-system-x86_64 \
  -machine q35 \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -drive file="$DISK",if=virtio,format=raw \
  -netdev "user,id=n0,guestfwd=tcp:10.0.2.100:8080-cmd:perl $PWD/stub.pl $STUBLOG" \
  -device virtio-net-pci,netdev=n0 \
  -audiodev alsa,id=snd0,out.dev=tarstap,in.dev=tarsfeed,out.frequency=48000,in.frequency=48000,out.channels=2,in.channels=2,out.format=s16,in.format=s16,out.try-poll=off,in.try-poll=off \
  -device ich9-intel-hda \
  -device hda-micro,audiodev=snd0 \
  -serial file:"$LOG" \
  -no-reboot &
QEMU_PID=$!

wait_for_log 'dictate-probe: done' 240 \
  || report_failure "the probe did not finish"
wait_for_exit 30 \
  || report_failure "the guest never switched itself off after the probe's kill -TERM 1"
grep -aF 'dictate-probe: tars-dictate is [/usr/bin/tars-dictate]' "$LOG" >/dev/null \
  || report_failure "tars-dictate is not on the guest's PATH"
grep -aF 'dictate-probe: route [default via 10.0.2.2' "$LOG" >/dev/null \
  || report_failure "the guest got no default route; the stub and the TLS peer are out of reach"
grep -aE 'dictate-probe: capture \[.*Capture 74 \[100%\] \[0\.00dB\] \[on\]\]' "$LOG" >/dev/null \
  || report_failure "the boot did not turn Capture on; the microphone would record zeros"

# 프로브 한 갈래의 줄(`dictate-probe: s1 exit 0 ms 1777 out ["…"] err […]`)과 그 판정.
#   $1 갈래  $2 종료 코드  $3 표준 출력(jq가 만든 JSON 문자열)  $4 표준 에러에 있어야 할 글자
# 비교는 글자 그대로다 — case 패턴의 따옴표 안은 [ ] *가 특별하지 않다.
probe_line() { grep -aoE "dictate-probe: $1 exit [0-9]+ ms [0-9]+ out .*" "$LOG" | head -n 1; }
expect_run() {
  local line
  line="$(probe_line "$1")"
  [ -n "$line" ] || report_failure "$1: the probe printed no result for it"
  case "$line" in *" $1 exit $2 ms "*) ;; *) report_failure "$1: tars-dictate did not exit $2 (${line})" ;; esac
  case "$line" in *" out [$3] err ["*) ;; *) report_failure "$1: stdout was not $3 (${line})" ;; esac
  case "$line" in *"$4"*) ;; *) report_failure "$1: stderr does not say '$4' (${line})" ;; esac
}
# stub이 받은 요청. 경로의 둘째 마디가 갈래 이름이다. 뒤의 공백까지 넣어 s1과 s10을 가른다.
stub_line() { grep -aE "^stub: POST /[a-z]+/$1 " "$STUBLOG" | head -n 1; }
stub_count() { grep -acE "^stub: POST /[a-z]+/$1 " "$STUBLOG"; }
# stub 줄에서 key=값 하나(대괄호 안의 낱말 하나)를 꺼낸다.
stub_field() { printf '%s\n' "$1" | grep -oE "(^| |\[)$2=[^] ]*" | head -n 1 | sed "s/^.*$2=//"; }
# 정리 stub이 받은 요청(`stub-chat: POST /chat/<답>/<갈래> …`).
chat_line() { grep -aE "^stub-chat: POST /chat/[a-z]+/$1 " "$STUBLOG" | head -n 1; }
chat_count() { grep -acE "^stub-chat: POST /chat/[a-z]+/$1 " "$STUBLOG"; }
OK_OUT='"안녕하세요 vd0-dictated"'
CLEAN_OUT='"안녕하세요 vd2-cleaned"'

# ── 검사 2: TLS — curl이 인증 기관 목록을 읽고, TLS 라이브러리가 돈다 ──────
# 상대는 컨테이너의 openssl s_server(자기 서명)다. 목록을 읽었으면 그 상대를 못 믿어 60이고,
# 목록이 없으면 그 앞에서 77이다(VD design 실측 1) — 60이 "목록이 있다"의 증거다. 같은
# 인증서를 --cacert로 주면 핸드셰이크와 응답까지 간다(s_server -www의 상태 페이지).
grep -aF 'dictate-probe: tls default exit 60 [curl: (60) SSL certificate problem: self-signed certificate' "$LOG" >/dev/null \
  || report_failure "curl did not load the CA bundle (want exit 60 against a self-signed peer, not 77)"
grep -aF 'dictate-probe: tls pinned [s_server]' "$LOG" >/dev/null \
  || report_failure "curl could not finish a TLS handshake with a peer it was told to trust"
echo "curl loads the CA bundle (60 against a self-signed peer) and finishes a TLS handshake with a pinned one"

# ── 검사 3: 기본값 — 마이크의 바이트가 API에 가고 받은 글자가 나온다 ────
# 사람이 Ctrl+C로 멈춘 갈래다(프로브가 1.5초 뒤 그룹에 SIGINT). stub이 받은 WAV가 16kHz
# 모노 16비트이고 샘플이 전부 체인이 넣은 상수면 녹음이 진짜 마이크를 지났다. language는
# 기본이 비어 있어 칸 자체가 없다(Voxio — 빈 언어 코드는 400이다). 머리의 길이가 실제
# 샘플 길이와 같아야 한다 — arecord는 SIGINT에 대부분 머리를 못 고치고 끝나며(VD design
# 실측 4) tars-dictate가 다시 쓴다.
expect_run s1 0 "$OK_OUT" 'recording stopped by SIGINT after'
S1="$(stub_line s1)"
[ -n "$S1" ] || report_failure "s1: the stub got no request"
for want in 'auth=[Bearer vd0-test-key]' 'parts=[file,model,response_format]' 'model=[whisper-large-v3-turbo]' \
  'language=[-]' 'response_format=[json]' 'type=audio/wav' 'wav=[rate=16000 ch=1 bits=16 '; do
  case "$S1" in *"$want"*) ;; *) report_failure "s1: the request lacks ${want} (${S1})" ;; esac
done
S1_DATA="$(stub_field "$S1" data)"
S1_HDR="$(stub_field "$S1" header_data)"
S1_N="$(stub_field "$S1" n)"
S1_MODE="$(stub_field "$S1" mode)"
S1_MODE_COUNT="$(stub_field "$S1" mode_count)"
echo "s1: data=${S1_DATA} header_data=${S1_HDR} samples=${S1_N} mode=${S1_MODE}x${S1_MODE_COUNT}"
if [ "${S1_DATA:-0}" -lt 16000 ] || [ "$S1_HDR" != "$S1_DATA" ]; then
  report_failure "s1: the WAV's header says ${S1_HDR} bytes of samples, the file has ${S1_DATA} (want equal and at least 0.5s)"
fi
if [ "$S1_MODE" != "$FEED_VALUE" ] || [ "$S1_MODE_COUNT" != "$S1_N" ]; then
  report_failure "s1: the recording is not the microphone's constant (${S1_MODE_COUNT} of ${S1_N} samples are ${S1_MODE}, want all ${FEED_VALUE})"
fi
echo "Ctrl+C stopped the recording, the microphone's constant reached the API as 16kHz mono, and the text came back on stdout"

# ── 검사 4: 설정 — language · 모델 · 상한 ───────────────────────────────
# max_seconds=1이면 아무도 안 눌러도 정확히 1초(32,000바이트)에서 끝난다. 상한으로 끝난
# 녹음도 전사로 간다(Voxio의 maxRecordingSec와 같다).
expect_run s2 0 "$OK_OUT" 'recording stopped at the 1s limit'
S2="$(stub_line s2)"
for want in 'parts=[file,model,response_format,language]' 'model=[vd0-model]' 'language=[ko]' \
  'data=32000 header_data=32000' 'samples=[n=16000 mode=1234 mode_count=16000]'; do
  case "$S2" in *"$want"*) ;; *) report_failure "s2: the request lacks ${want} (${S2})" ;; esac
done
echo "dictation.conf set the language, the model and a 1s limit, and the limit ended the recording at 32000 bytes"

# ── 검사 5: 녹음 중의 SIGTERM은 취소다 ──────────────────────────────────
# API를 안 부르고(stub에 s3이 없다) 표준 출력이 비고 오디오가 안 남는다.
expect_run s3 143 '""' 'cancelled'
[ "$(stub_count s3)" -eq 0 ] || report_failure "s3: a cancelled recording still reached the API"
if grep -aE 'dictate-probe: s[0-9]+ leftover wav \[[^]]' "$LOG" >/dev/null; then
  report_failure "a run left its audio in /tmp ($(grep -aoE 'dictate-probe: s[0-9]+ leftover wav \[[^]]+' "$LOG" | head -n 1))"
fi
echo "SIGTERM cancelled the recording without calling the API, and no run left audio behind"

# ── 검사 6: 키가 없으면 녹음 전에 끝난다 · 환경 변수의 키 ─────────────────
# s4는 max_seconds=30이다. 녹음했다면 30초를 걸린다 — 2초 안에 끝난 것이 마이크를 안 연
# 증거이고, stub에 s4가 없는 것이 API를 안 부른 증거다.
expect_run s4 3 '""' 'no API key'
S4_MS="$(probe_line s4 | sed -E 's/.* ms ([0-9]+) out .*/\1/')"
[ "$S4_MS" -lt 2000 ] || report_failure "s4: without a key tars-dictate took ${S4_MS}ms; it must stop before recording"
[ "$(stub_count s4)" -eq 0 ] || report_failure "s4: without a key the request still reached the API"
expect_run s5 0 "$OK_OUT" 'transcribed 1000ms of audio'
case "$(stub_line s5)" in *'auth=[Bearer vd0-env-key]'*) ;; *) report_failure "s5: GROQ_API_KEY did not reach the request ($(stub_line s5))" ;; esac
echo "without a key tars-dictate stopped in ${S4_MS}ms before recording, and GROQ_API_KEY stood in for the file"

# ── 검사 7 · 8 · 9 · 10: 서버의 답 넷 ───────────────────────────────────
# 429는 실패(4)이고 표준 출력이 빈다. 무음 전사 " ."은 넣을 것이 없다(2). 제어 문자는
# 탭과 개행만 남기고 지운다 — ESC · CR · NEL(C1) · 끝의 ESC. text가 없는 응답은 실패(4)다.
expect_run s6 4 '""' 'HTTP 429'
expect_run s7 2 '""' 'the transcript is blank'
expect_run s8 0 '"vd0-ctrl a[201~bc\td\nef"' 'transcribed 1000ms of audio into 22 characters'
expect_run s9 4 '""' 'the response has no text'
echo "a 429 failed with nothing on stdout, a blank transcript inserted nothing, control characters were stripped, and a reply without text failed"

# ── 검사 11: 설정 파일의 모르는 키와 틀린 값 ──────────────────────────────
expect_run s10 0 "$OK_OUT" "unknown key 'colour'"
expect_run s10 0 "$OK_OUT" "max_seconds '0' is not 1..600, keeping 1"
case "$(stub_line s10)" in *'data=32000 header_data=32000'*) ;; *) report_failure "s10: the bad max_seconds was not ignored ($(stub_line s10))" ;; esac
echo "an unknown key and a bad value only warned, and the run kept the earlier max_seconds"

# ── 검사 24: 게이트는 Groq를 안 부른다 — M0의 갈래는 정리의 기본 주소에서 거절됐다 ──
# 정리를 켠 채 cleanup_url을 안 적은 다섯(s1 · s2 · s5 · s8 · s10)은 기본 주소 api.groq.com으로
# 간다. 프로브가 그 이름을 127.0.0.1로 돌렸으므로 연결이 거절되고(curl exit 7) 원문이 들어간다 —
# 위 검사 3 ~ 11의 표준 출력이 M0 그대로인 것이 "정리 실패는 원문"의 첫 증거다. 거절 줄이 없으면
# 그 요청이 어딘가에 닿았다는 뜻이다.
grep -aF 'dictate-probe: hosts [127.0.0.1 api.groq.com]' "$LOG" >/dev/null \
  || report_failure "the probe did not point api.groq.com at 127.0.0.1; the gate may reach the real Groq"
for s in s1 s2 s5 s8 s10; do
  case "$(probe_line "$s")" in
    *'tars-dictate: cleanup failed (curl exit 7): curl: (7) Failed to connect to api.groq.com port 443'*) ;;
    *) report_failure "$s: the cleanup did not stop at 127.0.0.1 ($(probe_line "$s"))" ;;
  esac
done
echo "the M0 runs kept the cleanup on, their default address was refused inside the guest, and the raw text went out"

# ── 검사 25: 정리 켜짐(기본값) — 요청이 Voxio의 모양이고 정리본이 나온다 ──────
# s11은 cleanup 키를 안 적었다. 요청은 Voxio GroqClient.clean과 같다 — 시스템 프롬프트는 Voxio
# defaultSystemPrompt 그대로(1038글자, sha256은 Voxio의 Swift 글자를 찍어 잰 값), 사용자 메시지는
# 원문 그대로, temperature 0, stream false, max_tokens는 max(64, 18 × 2) = 64.
expect_run s11 0 "$CLEAN_OUT" 'tars-dictate: cleaned 18 characters into 17 in'
case "$(probe_line s11)" in *'(changed=true)'*) ;; *) report_failure "s11: the cleanup did not say changed=true ($(probe_line s11))" ;; esac
C11="$(chat_line s11)"
[ -n "$C11" ] || report_failure "s11: the cleanup stub got no request"
for want in 'auth=[Bearer vd0-test-key]' 'type=[application/json]' 'keys=[max_tokens,messages,model,stream,temperature]' \
  'model=[qwen/qwen3.8-27b]' 'roles=[system,user]' \
  'system=[chars=1038 sha256=c139824ce41a5cee0c8f0a4561d99ada5e005f2d2a416dddef5ab67d56b2d14e head=You are a transcript cleanup filter, not an assistant.]' \
  'user=[안녕하세요 vd0-dictated] user_chars=[18]' 'temperature=[0]' 'max_tokens=[64]' 'stream=[false]'; do
  case "$C11" in *"$want"*) ;; *) report_failure "s11: the cleanup request lacks ${want} (${C11})" ;; esac
done
echo "the cleanup is on by default, sent Voxio's request with the raw text as the user message, and its answer went out"

# ── 검사 26: 정리 꺼짐 — 요청이 없다 ──────────────────────────────────
expect_run s12 0 "$OK_OUT" 'transcribed 1000ms of audio into 18 characters'
[ "$(chat_count s12)" -eq 0 ] || report_failure "s12: cleanup=off still sent a cleanup request"
case "$(probe_line s12)" in *'tars-dictate: clean'*) report_failure "s12: cleanup=off still said something about the cleanup ($(probe_line s12))" ;; esac
echo "cleanup=off sent no cleanup request and the raw text went out"

# ── 검사 27: 정리본을 어떻게 받나 — 같은 답 · 따옴표 · 제어 문자 ──────────
# 같은 답은 바뀐 것이 없다(changed=false)는 것뿐 정리본이다 — 기록에 남는다(검사 13). 틀린 값
# (cleanup=maybe)은 경고만 하고 켜짐에 머문다. 바깥 따옴표 “ ”와 앞뒤 공백은 벗긴다. 답의 제어
# 문자는 넣기 전에 지운다 — 원문의 것과 같은 거르기다(검사 10).
expect_run s13 0 "$OK_OUT" 'tars-dictate: cleaned 18 characters into 18 in'
case "$(probe_line s13)" in *'(changed=false)'*) ;; *) report_failure "s13: an unchanged answer did not say changed=false ($(probe_line s13))" ;; esac
expect_run s13 0 "$OK_OUT" "cleanup 'maybe' is not on or off, keeping on"
expect_run s14 0 "$CLEAN_OUT" 'tars-dictate: cleaned 18 characters into 17 in'
case "$(chat_line s14)" in *'model=[vd2-model]'*) ;; *) report_failure "s14: cleanup_model did not reach the request ($(chat_line s14))" ;; esac
expect_run s15 0 '"안녕하세요[201~ vd2-cleaned"' 'tars-dictate: cleaned 18 characters into 24 in'
echo "an unchanged answer was kept, a quoted answer lost its quotes, cleanup_model reached the request, and control characters in an answer were stripped"

# ── 검사 28: 원문으로 돌아가는 여섯 — 어느 것도 실패가 아니다 ────────────────
# 짧은 답(2글자 × 2 < 18)과 빈 답은 길이 가드, 느린 답(stub이 3초 뒤에 답한다)은 1.5초 상한,
# 500과 choices 없는 200은 정리 실패다. 여섯 다 exit 0이고 표준 출력이 원문이다.
expect_run s16 0 "$OK_OUT" 'tars-dictate: cleanup rejected: 2 characters is under half of 18; inserting the transcript as is'
expect_run s17 0 "$OK_OUT" 'tars-dictate: cleanup rejected: 0 characters is under half of 18; inserting the transcript as is'
expect_run s18 0 "$OK_OUT" 'tars-dictate: cleanup timed out after 1.5s; inserting the transcript as is'
expect_run s19 0 "$OK_OUT" 'tars-dictate: cleanup failed: HTTP 500'
expect_run s20 0 "$OK_OUT" 'tars-dictate: cleanup failed: the reply has no content; inserting the transcript as is'
# s21 — cleanup_timeout=0.5면 1초 뒤의 답도 시간 초과다(기본 1.5초면 받았을 답). 그 앞의 틀린 값은
# 경고만 하고 1.5에 머문다.
expect_run s21 0 "$OK_OUT" 'tars-dictate: cleanup timed out after 0.5s; inserting the transcript as is'
expect_run s21 0 "$OK_OUT" "cleanup_timeout '20' is not 0.5..10 seconds, keeping 1.5"
echo "a summary, an empty answer, a slow answer, a 500, a reply without choices and an answer past cleanup_timeout all fell back to the raw text with exit 0"

# ── 검사 29: 정리 stub이 받은 요청은 열이다 ────────────────────────────────
# s11 · s13 ~ s21 하나씩. 꺼진 s12와, 막힌 기본 주소로 간 M0의 다섯은 stub에 없다.
CHATS="$(grep -ac '^stub-chat: POST ' "$STUBLOG")"
[ "$CHATS" -eq 10 ] || report_failure "the cleanup stub got ${CHATS} request(s), want 10"
for s in s11 s13 s14 s15 s16 s17 s18 s19 s20 s21; do
  [ "$(chat_count "$s")" -eq 1 ] || report_failure "$s: the cleanup stub got $(chat_count "$s") request(s), want 1"
done
echo "the cleanup stub got ten requests, one for each run that had the cleanup on and pointed at it"

# ── 검사 30: tars-config가 쓴 키와 설정을 다음 tars-dictate가 읽는다 (TC-M1) ──
# 프로브가 키를 표준 입력으로(`printf … | tars-config dictation key`), 전사 주소와 상한을
# `tars-config dictation set`으로 고쳤다. s22의 요청이 그 주소(/fail/s22)로 그 키를 싣고 왔으면
# 둘 다 파일에 들어가 tars-dictate가 읽은 것이다. 키 파일은 0600이고, 모르는 키(colour)는
# 거절돼 파일에 한 줄도 안 남았다. tars-dictate가 이 갈래에서 exit 4(429)인 것은 /fail이 고른 답이다.
grep -aF 'dictate-probe: tc key [dictation: wrote /config/groq.key (0600, 7 characters)|' "$LOG" >/dev/null \
  || report_failure "tars-config dictation key did not write the key from stdin"
grep -aF '] mode [600]' "$LOG" >/dev/null || report_failure "the key file tars-config wrote is not mode 600"
grep -aF "dictate-probe: tc set [dictation: transcribe_url=http://10.0.2.100:8080/fail/s22|dictation: max_seconds=1|" "$LOG" >/dev/null \
  || report_failure "tars-config dictation set did not report the two lines it wrote"
grep -aF "dictate-probe: tc refused exit 1 [tars-config: unknown dictation key 'colour'" "$LOG" >/dev/null \
  || report_failure "tars-config dictation set did not refuse the unknown key colour"
grep -aF '] colour lines [0]' "$LOG" >/dev/null || report_failure "the refused key still landed in dictation.conf"
expect_run s22 4 '""' 'tars-dictate: transcription failed: HTTP 429'
S22="$(stub_line s22)"
[ -n "$S22" ] || report_failure "s22: the request did not reach the transcribe_url tars-config set"
[ "$(stub_field "$S22" auth)" = "[Bearer" ] || true
case "$S22" in *"auth=[Bearer tc1-key]"*) ;; *) report_failure "s22: the request did not carry the key tars-config wrote (${S22})" ;; esac
echo "tars-config wrote groq.key (0600) and two dictation.conf lines, refused an unknown key, and the next tars-dictate used both"

# ── 검사 12: stub이 받은 전사 요청은 스물이고, 어느 WAV의 머리도 거짓말을 안 한다 ──
# 취소(s3)와 키 없음(s4)만 API에 안 간다 — M0의 여덟과 정리 갈래(s11 ~ s21)의 열하나, 그리고
# TC-M1의 s22 하나다(검사 30). 머리의
# 길이는 SIGINT로 멈춘 셋(s1 · s7 · s9)이 본다 — arecord가 고치지 못한 머리를 tars-dictate가 다시
# 쓴다(검사 3의 주석).
REQUESTS="$(grep -ac '^stub: POST ' "$STUBLOG")"
[ "$REQUESTS" -eq 20 ] || report_failure "the stub got ${REQUESTS} request(s), want 20 (s3 and s4 must not call it)"
while IFS= read -r req; do
  [ "$(stub_field "$req" header_data)" = "$(stub_field "$req" data)" ] \
    || report_failure "a WAV reached the API with a header that does not match its length (${req})"
done < <(grep -a '^stub: POST ' "$STUBLOG")
echo "the stub got twenty requests, and every WAV's header matched its length"

# ── 검사 13: 기록 — 전사가 성공한 열여섯만 원문 · 정리본과 함께 남는다 ─────────
# 끈 뒤 디스크에서 꺼낸다. 원문(raw)은 받은 그대로라 s8의 제어 문자가 JSON 이스케이프로
# 남고, inserted는 지운 것이다. 실패 · 무음 · 취소 · 키 없음은 한 줄도 안 남는다. 정리본
# (cleaned)은 정리가 받아들여진 넷(s11 · s13 · s14 · s15)에만 있다 — 같은 답(s13)도 글자로
# 남고, 제어 문자가 든 답(s15)은 받은 그대로다. 꺼짐 · 실패 · 가드는 null이다(Voxio의
# cleaned_text와 같다). 정리가 실패한 여섯(s16 ~ s21)도 원문으로 남는다.
debugfs -R "dump dictation.jsonl $WORK/dictation.jsonl" "$DISK" >/dev/null 2>&1
[ -s "$WORK/dictation.jsonl" ] || report_failure "the config disk holds no dictation.jsonl"
HISTORY="$(perl -MJSON::PP -e '
  binmode STDOUT, ":utf8";
  my $j = JSON::PP->new->utf8;
  # 제어 문자는 \x{1b}처럼 보이게 바꾼다 — 기대값을 이 파일에 글자로 적기 위해서다.
  sub show { my $s = shift; $s =~ s/([\x00-\x1f\x7f-\x9f])/sprintf("\\x{%x}", ord $1)/ge; $s }
  open(my $f, "<:raw", $ARGV[0]) or die;
  while (my $l = <$f>) {
    my $r = $j->decode($l);
    my $ok = ($r->{at} =~ /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/ && exists $r->{cleaned}
              && $r->{latency_ms} =~ /\A\d+\z/) ? "ok" : "bad";
    printf "raw=%s|cleaned=%s|inserted=%s|%d|%s\n", show($r->{raw}),
      defined $r->{cleaned} ? show($r->{cleaned}) : "(null)", show($r->{inserted}), $r->{audio_ms}, $ok;
  }' "$WORK/dictation.jsonl")" || report_failure "dictation.jsonl is not JSON lines"
echo "--- history ---"
printf '%s\n' "$HISTORY"
EXPECT_HISTORY='raw=안녕하세요 vd0-dictated|cleaned=(null)|inserted=안녕하세요 vd0-dictated|S1|ok
raw=안녕하세요 vd0-dictated|cleaned=(null)|inserted=안녕하세요 vd0-dictated|1000|ok
raw=안녕하세요 vd0-dictated|cleaned=(null)|inserted=안녕하세요 vd0-dictated|1000|ok
raw=vd0-ctrl a\x{1b}[201~b\x{d}c\x{9}d\x{a}e\x{85}f\x{1b}|cleaned=(null)|inserted=vd0-ctrl a[201~bc\x{9}d\x{a}ef|1000|ok
raw=안녕하세요 vd0-dictated|cleaned=(null)|inserted=안녕하세요 vd0-dictated|1000|ok
raw=안녕하세요 vd0-dictated|cleaned=안녕하세요 vd2-cleaned|inserted=안녕하세요 vd2-cleaned|1000|ok
raw=안녕하세요 vd0-dictated|cleaned=(null)|inserted=안녕하세요 vd0-dictated|1000|ok
raw=안녕하세요 vd0-dictated|cleaned=안녕하세요 vd0-dictated|inserted=안녕하세요 vd0-dictated|1000|ok
raw=안녕하세요 vd0-dictated|cleaned=안녕하세요 vd2-cleaned|inserted=안녕하세요 vd2-cleaned|1000|ok
raw=안녕하세요 vd0-dictated|cleaned=안녕하세요\x{1b}[201~ vd2\x{d}-cleaned|inserted=안녕하세요[201~ vd2-cleaned|1000|ok
raw=안녕하세요 vd0-dictated|cleaned=(null)|inserted=안녕하세요 vd0-dictated|1000|ok
raw=안녕하세요 vd0-dictated|cleaned=(null)|inserted=안녕하세요 vd0-dictated|1000|ok
raw=안녕하세요 vd0-dictated|cleaned=(null)|inserted=안녕하세요 vd0-dictated|1000|ok
raw=안녕하세요 vd0-dictated|cleaned=(null)|inserted=안녕하세요 vd0-dictated|1000|ok
raw=안녕하세요 vd0-dictated|cleaned=(null)|inserted=안녕하세요 vd0-dictated|1000|ok
raw=안녕하세요 vd0-dictated|cleaned=(null)|inserted=안녕하세요 vd0-dictated|1000|ok'
EXPECT_HISTORY="${EXPECT_HISTORY/S1/$(( S1_DATA * 1000 / 32000 ))}"
[ "$HISTORY" = "$EXPECT_HISTORY" ] || report_failure "dictation.jsonl does not hold the sixteen successful runs as expected"
echo "dictation.jsonl keeps the sixteen successful runs with the raw text, the cleaned text and what was inserted, and nothing else"

# ════════════════════════════════════════════════════════════════════════
# 부팅 B — terminal의 트리거 · 상태 · 삽입 (VD-M1)
# ════════════════════════════════════════════════════════════════════════
#
# 사람이 하는 일을 monitor로 한다. 셸은 기본값 fish다(프롬프트 `root@(none) ~#`).
#
# 더블 탭은 `sendkey meta_r 80` 둘을 잇달아 보내는 것이다. sendkey는 누르고 hold(80ms) 뒤에
# 떼고, QEMU는 그 뗌을 입력 큐에 지연과 함께 넣는다 — 둘째 sendkey의 누름은 그 뒤에 줄을
# 선다. 그래서 둘째 누름이 첫 누름 뒤 90ms 남짓에 온다(창 300ms 안, VD-M1 plan 확정 9가 evdev
# 시각으로 쟀다). hold를 적는 것은 사람의 손에 가깝게 하려는 것이다 — 안 적으면 누른 시간이
# 10ms 안팎이고 두 누름 사이가 20ms 남짓이었다. type_keys를 안 쓴다 — 수정키 하나는 로그를 한
# 줄도 안 만들어 type_keys가 키마다 0.3초를 기다리고, 그러면 둘째 누름이 창 밖이다.
#
# 화면은 마지막 프레임만 본다(`last_screen`). wait_for_screen은 로그의 모든 프레임을 훑으므로
# 지운 줄이나 다른 패널의 지난 프레임에 걸린다.
#
# 정리는 켠 채 돈다(VD-M2). cleanup_url이 정리 stub의 /chat/ok라 terminal이 넣는 글자는 정리본
# `안녕하세요 vd2-cleaned`이고, 기록에는 원문과 정리본이 함께 남는다(검사 23).
DISK_B=../out/dictation-b.img
STUBLOG_B="$WORK/stub_b.log"
LOG="$(mktemp)"

mkdir -p "$WORK/seed_b/services.d"
printf 'net=dhcp\n' > "$WORK/seed_b/tars.conf"
printf 'vd1-test-key\n' > "$WORK/seed_b/groq.key"
printf '%s\n' '# written by the VD chain, boot B' 'transcribe_url = http://10.0.2.100:8080/ok/b' \
  'cleanup_url = http://10.0.2.100:8080/chat/ok/b' > "$WORK/seed_b/dictation.conf"
# 사람이 셸에서 칠 것을 짧게 줄인 셋이다 — 타이핑 한 글자가 sendkey 하나라서다.
#   vd-pw     비밀번호 프롬프트. bash의 read -s는 줄 단위로 읽으며 안 보여 준다
#             (ICANON 켜짐 · ECHO 꺼짐). 받은 것을 대괄호 안에 되보여 준다
#   vd-cap    설정을 고친다 — 1초에서 스스로 멈추는 녹음(키 없이 끝나는 길)
#   vd-nokey  키 파일을 치운다
printf '%s\n' '#!/usr/bin/bash' "read -rsp 'pw> ' x" 'echo' 'echo "got[$x]"' > "$WORK/seed_b/vd-pw"
printf '%s\n' '#!/usr/bin/bash' \
  "printf '%s\\n' 'transcribe_url = http://10.0.2.100:8080/ok/cap' 'cleanup_url = http://10.0.2.100:8080/chat/ok/cap' 'max_seconds = 1' > /config/dictation.conf" \
  > "$WORK/seed_b/vd-cap"
printf '%s\n' '#!/usr/bin/bash' 'mv /config/groq.key /config/groq.key.off' > "$WORK/seed_b/vd-nokey"
chmod 0755 "$WORK/seed_b/vd-pw" "$WORK/seed_b/vd-cap" "$WORK/seed_b/vd-nokey"
# Groq 막기(부팅 A의 프로브와 같은 줄). 부팅 B에는 프로브가 없으므로 서비스 하나가 부팅 때
# api.groq.com을 127.0.0.1로 돌리고 잠든다 — 위 설정에서 cleanup_url이 빠져도 Groq에 안 닿는다.
printf '%s\n' '#!/usr/bin/bash' "echo '127.0.0.1 api.groq.com' >> /etc/hosts" \
  'echo "groq-off: hosts [$(grep groq /etc/hosts)]"' 'exec sleep 100000' > "$WORK/seed_b/services.d/groq-off"
chmod 0755 "$WORK/seed_b/services.d/groq-off"
rm -f "$DISK_B"
truncate -s 16M "$DISK_B"
mkfs.ext2 -F -q -m 0 -L tars-dictate -d "$WORK/seed_b" "$DISK_B"

report_b() {
  echo "FAIL(boot B): $1"
  echo "--- dictation lines ---"
  grep -aE 'terminal: dictate>|tars-dictate:' "$LOG" | tr -d '\r' | tail -n 40
  echo "--- status lines ---"
  grep -aE 'terminal: status> (text=|dict ink)' "$LOG" | tr -d '\r' | tail -n 12
  echo "--- stub (boot B) ---"
  cat "$STUBLOG_B" 2>/dev/null
  echo "--- last screen ---"
  last_screen | tr -d '\r' | tr '|' '\n' | tail -n 15
  echo "--- last 30 lines ---"
  tail -n 30 "$LOG"
  exit 1
}

# 패턴에 맞는 줄의 수.
count_b() { grep -acE -- "$1" "$LOG" || true; }
# 그 수가 want가 될 때까지 0.1초 간격으로 기다린다. 상한은 초.
wait_count() {
  local pattern="$1" want="$2" secs="$3" i
  for i in $(seq 1 $((secs * 10))); do
    [ "$(count_b "$pattern")" -ge "$want" ] && return 0
    kill -0 "$QEMU_PID" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}
# 상태 줄의 마지막 글자와 받아쓰기 칸의 마지막 픽셀 수.
last_status() { grep -a 'terminal: status> text=' "$LOG" | tail -n 1 | tr -d '\r' | sed -E 's/.*text=//'; }
last_dict_ink() { grep -a 'terminal: status> dict ink=' "$LOG" | tail -n 1 | tr -d '\r' | sed -E 's/.*ink=([0-9]+).*/\1/'; }
# 상태 줄이 패턴(ERE, 줄 끝까지)과 맞을 때까지 기다린다.
wait_status() {
  local pattern="$1" secs="$2" i
  for i in $(seq 1 $((secs * 10))); do
    grep -aE -- "$pattern" <<<"$(last_status)" >/dev/null && return 0
    sleep 0.1
  done
  return 1
}
# 받아쓰기 칸의 픽셀이 켜지거나(on, >0) 꺼질(off, =0) 때까지 기다린다. `dumpStatus`가
# `text=` 줄 뒤에 `dict ink=` 줄을 찍으므로, `text=`를 본 순간의 마지막 `dict ink`는 앞
# 프레임의 것일 수 있다.
wait_dict_ink() {
  local want="$1" i v
  for i in $(seq 1 50); do
    v="$(last_dict_ink)"
    if [ -n "$v" ]; then
      [ "$want" = on ] && [ "$v" -gt 0 ] && return 0
      [ "$want" = off ] && [ "$v" -eq 0 ] && return 0
    fi
    sleep 0.1
  done
  return 1
}
# 마지막 프레임의 화면 줄(포커스 패널).
last_screen() { joined_screen_dump | tail -n 1; }
wait_last_screen() {
  local pattern="$1" secs="$2" i
  for i in $(seq 1 $((secs * 10))); do
    grep -aE -- "$pattern" <<<"$(last_screen)" >/dev/null && return 0
    sleep 0.1
  done
  return 1
}
# 마지막 프레임에 그 글자가 몇 번 있는가.
last_screen_count() { last_screen | grep -oaF -- "$1" | wc -l; }
stub_b_count() { local n; n="$(grep -ac '^stub: POST ' "$STUBLOG_B" 2>/dev/null)"; echo "${n:-0}"; }
chat_b_count() { local n; n="$(grep -ac '^stub-chat: POST ' "$STUBLOG_B" 2>/dev/null)"; echo "${n:-0}"; }
double_tap() {
  echo "sendkey meta_r 80" >&3
  echo "sendkey meta_r 80" >&3
  sleep 0.6
}
# 녹음이 시작됐다(n번째 start와 n번째 recording 줄).
expect_recording() {
  wait_count 'terminal: dictate> start pid=' "$1" 15 || report_b "$2: the double tap started no dictation (want start #$1)"
  wait_count 'terminal: dictate> phase recording' "$1" 15 || report_b "$2: tars-dictate never said it was recording"
}
PROMPT='root@\(none\) ~#'
TEXT='안녕하세요 vd2-cleaned'

echo "=== boot B: the terminal triggers, shows and inserts (monitor ${MONITOR_PORT_B}) ==="
HOME="$WORK" qemu-system-x86_64 \
  -machine q35 \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -drive file="$DISK_B",if=virtio,format=raw \
  -netdev "user,id=n0,guestfwd=tcp:10.0.2.100:8080-cmd:perl $PWD/stub.pl $STUBLOG_B" \
  -device virtio-net-pci,netdev=n0 \
  -audiodev alsa,id=snd0,out.dev=tarstap,in.dev=tarsfeed,out.frequency=48000,in.frequency=48000,out.channels=2,in.channels=2,out.format=s16,in.format=s16,out.try-poll=off,in.try-poll=off \
  -device ich9-intel-hda \
  -device hda-micro,audiodev=snd0 \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT_B},server,nowait \
  -no-reboot &
QEMU_PID=$!

wait_for_log 'terminal: screen>' 120 || report_b "terminal never rendered"
wait_last_screen "$PROMPT" 30 || report_b "the fish prompt never showed up"
# 전사 API(stub)에 닿는 길과 켜진 마이크. 부팅 A의 프로브가 기다린 것과 같다.
wait_for_log 'eth0: adding default route via 10\.0\.2\.2' 60 || report_b "dhcpcd never added the default route"
wait_for_log 'tars-init: audio: alsactl init turned the mixer on' 60 || report_b "the boot never turned the mixer on"
wait_for_log 'groq-off: hosts \[127\.0\.0\.1 api\.groq\.com\]' 30 || report_b "api.groq.com was not pointed at 127.0.0.1; the gate may reach the real Groq"
CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT_B}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = 1 ] || report_b "could not connect to the QEMU monitor"
case "$(last_status)" in
  *"  REC"|*"  WAIT"|*"  NO "*|*"  FAILED"|*"  PASSWORD") report_b "the status line has a dictation field before any dictation ($(last_status))" ;;
esac

# ── 검사 14: 한 번 탭과 늦은 둘째 탭은 아무것도 안 한다 ─────────────────
# 판정 창의 바깥쪽이다(dictation_test 검사 3 · 4 · 5의 게스트 판). 0.6초 떨어진 두 탭은
# 첫 누름부터 700ms 남짓이다.
echo "sendkey meta_r 80" >&3
sleep 0.8
echo "sendkey meta_r 80" >&3
sleep 0.6
echo "sendkey meta_r 80" >&3
sleep 1
[ "$(count_b 'terminal: dictate>')" -eq 0 ] \
  || report_b "a single tap or two taps 0.6s apart started something ($(grep -a 'terminal: dictate>' "$LOG" | head -n 1))"
echo "a single tap and two taps 0.6s apart did nothing"

# ── 검사 15: 두 번 → REC → 두 번 → 글자가 프롬프트에 들어간다 ──────────────
# 둘째 더블 탭이 그룹에 SIGINT를 보내고(stop), 상태 줄은 그 자리에서 WAIT가 된다. 자식이
# 끝나면 받은 글자가 bracketed paste로 그 패널에 간다 — fish가 줄에 올려 두고 실행하지
# 않는다(Enter가 없다).
double_tap
expect_recording 1 "B1"
wait_status '  REC$' 10 || report_b "B1: the status line never showed REC ($(last_status))"
wait_dict_ink on || report_b "B1: REC is in the text but no pixel has the dictation color"
sleep 1.5
double_tap
wait_count 'terminal: dictate> stop pid=' 1 10 || report_b "B1: the second double tap did not stop the recording"
wait_count 'terminal: dictate> insert len=' 1 20 || report_b "B1: nothing was inserted"
grep -aF 'tars-dictate: recording stopped by SIGINT after' "$LOG" >/dev/null \
  || report_b "B1: tars-dictate did not stop on SIGINT (did the signal reach the process group?)"
grep -aE 'terminal: status> text=.*  WAIT' "$LOG" >/dev/null || report_b "B1: the status line never showed WAIT"
INSERT1="$(grep -a 'terminal: dictate> insert len=' "$LOG" | head -n 1 | tr -d '\r' | sed -E 's/.*dictate> //')"
[ "$INSERT1" = "insert len=27 bracketed=1 ws=1 leaf=0" ] || report_b "B1: the insert line is '${INSERT1}'"
grep -aF 'tars-dictate: cleaned 18 characters into 17 in' "$LOG" >/dev/null || report_b "B1: tars-dictate did not clean the transcript"
[ "$(chat_b_count)" -eq 1 ] || report_b "B1: the cleanup stub got $(chat_b_count) request(s), want 1"
grep -aF 'terminal: dictate> exit code=0' "$LOG" >/dev/null || report_b "B1: tars-dictate did not exit 0"
wait_last_screen "${PROMPT} ${TEXT}" 15 || report_b "B1: the text never showed up on the prompt line"
wait_status 'CAPS$' 10 || report_b "B1: the dictation field stayed after the insert ($(last_status))"
wait_dict_ink off || report_b "B1: dictation pixels remain after the insert"
case "$(last_screen)" in *"Unknown command"*) report_b "B1: fish ran the inserted text" ;; esac
[ "$(stub_b_count)" -eq 1 ] || report_b "B1: the stub got $(stub_b_count) request(s), want 1"
type_keys ctrl-u
echo "two double taps recorded, stopped with SIGINT, showed REC then WAIT, and put the cleaned text on the prompt without running it"

# ── 검사 16: 녹음 중의 Esc는 취소이고 PTY로 안 간다 ──────────────────────
# 그룹에 SIGTERM — API를 안 부르고(stub 그대로) 143으로 끝나 조용하다. `key>` 줄은 PTY로
# 바이트가 나갈 때만 찍히므로, 그 수가 그대로인 것이 "Esc가 셸에 안 갔다"이다.
double_tap
expect_recording 2 "B2"
KEYS_BEFORE="$(count_b 'terminal: key>')"
echo "sendkey esc" >&3
wait_count 'terminal: dictate> cancel pid=' 1 10 || report_b "B2: Esc did not cancel"
wait_count 'terminal: dictate> exit code=143' 1 10 || report_b "B2: tars-dictate did not exit 143 after Esc"
[ "$(count_b 'terminal: key>')" -eq "$KEYS_BEFORE" ] || report_b "B2: the cancelling Esc also went to the shell"
wait_status 'CAPS$' 10 || report_b "B2: the dictation field stayed after the cancel ($(last_status))"
[ "$(stub_b_count)" -eq 1 ] || report_b "B2: a cancelled recording reached the API"
echo "Esc while recording cancelled it with SIGTERM, never reached the shell, and called no API"

# ── 검사 17: 비밀번호 프롬프트에서는 마이크를 안 연다 ─────────────────────
# bash의 read -s가 기다리는 동안(ICANON 켜짐 · ECHO 꺼짐) 더블 탭은 시작이 아니라 알림이다.
type_keys slash c o n f i g slash v d minus p w ret
wait_last_screen 'pw> ' 10 || report_b "B3: the password prompt never showed up"
sleep 0.5
double_tap
wait_count 'terminal: dictate> refused password at=start ws=1 leaf=0' 1 10 \
  || report_b "B3: a double tap on a password prompt was not refused"
wait_status '  PASSWORD$' 10 || report_b "B3: the status line did not say PASSWORD ($(last_status))"
[ "$(count_b 'terminal: dictate> start pid=')" -eq 2 ] || report_b "B3: a dictation started on a password prompt"
type_keys ret
wait_last_screen 'got\[\]' 10 || report_b "B3: read -s did not end with an empty answer"
wait_status 'CAPS$' 10 || report_b "B3: PASSWORD stayed after the next key ($(last_status))"
echo "a double tap on a password prompt did not open the microphone, said PASSWORD, and the next key cleared it"

# ── 검사 18: 말하는 사이에 비밀번호 프롬프트가 뜨면 넣지 않는다 ─────────────
# 시작할 때는 프롬프트였다. 녹음 중에 vd-pw를 치고, 그 read -s가 기다리는 동안 끝낸다.
# 전사는 됐고(stub에 간다) 기록에도 남지만(검사 22) 그 프롬프트에는 한 글자도 안 간다 —
# read가 받은 것이 빈 문자열이다.
double_tap
expect_recording 3 "B4"
type_keys slash c o n f i g slash v d minus p w ret
for _ in $(seq 1 100); do [ "$(last_screen_count 'pw> ')" -ge 2 ] && break; sleep 0.1; done
[ "$(last_screen_count 'pw> ')" -ge 2 ] || report_b "B4: the second password prompt never showed up"
sleep 0.5
double_tap
wait_count 'terminal: dictate> stop pid=' 2 10 || report_b "B4: the double tap did not stop the recording"
wait_count 'terminal: dictate> refused password at=insert ws=1 leaf=0' 1 20 \
  || report_b "B4: the text was not refused at the password prompt"
wait_status '  PASSWORD$' 10 || report_b "B4: the status line did not say PASSWORD ($(last_status))"
type_keys ret
for _ in $(seq 1 100); do [ "$(last_screen_count 'got[]')" -ge 2 ] && break; sleep 0.1; done
[ "$(last_screen_count 'got[]')" -ge 2 ] || report_b "B4: read -s got something (the text went into the password prompt)"
[ "$(count_b 'terminal: dictate> insert len=')" -eq 1 ] || report_b "B4: an insert line appeared"
[ "$(stub_b_count)" -eq 2 ] || report_b "B4: the stub got $(stub_b_count) request(s), want 2"
echo "a password prompt that appeared while speaking got nothing, and the status line said PASSWORD"

# ── 검사 19: 글자는 트리거를 누른 패널에 간다 ───────────────────────────
# Voxio D8 1번. 오른쪽에 패널을 가르고(포커스가 새 패널) 거기서 시작한 뒤, 왼쪽으로 포커스를
# 옮겨서 끝낸다. 글자는 오른쪽 패널(leaf 1)에 가고, 왼쪽의 마지막 프레임에는 없다.
type_keys meta_l-d
wait_count 'terminal: pane> ws=1/1 panes=2 focus=1' 1 10 || report_b "B5: Cmd+D did not split"
sleep 1
wait_last_screen "$PROMPT" 15 || report_b "B5: the new pane's prompt never showed up"
double_tap
expect_recording 4 "B5"
grep -aF 'terminal: dictate> start pid=' "$LOG" | tail -n 1 | grep -aF 'ws=1 leaf=1' >/dev/null \
  || report_b "B5: the dictation did not start in leaf 1"
type_keys meta_l-bracket_left
wait_count 'terminal: pane> ws=1/1 panes=2 focus=0' 1 10 || report_b "B5: Cmd+[ did not move the focus"
double_tap
wait_count 'terminal: dictate> insert len=' 2 20 || report_b "B5: nothing was inserted"
grep -a 'terminal: dictate> insert len=' "$LOG" | tail -n 1 | grep -aF 'ws=1 leaf=1' >/dev/null \
  || report_b "B5: the text went to $(grep -a 'terminal: dictate> insert len=' "$LOG" | tail -n 1 | tr -d '\r')"
sleep 1
[ "$(last_screen_count "$TEXT")" -eq 0 ] || report_b "B5: the focused pane (leaf 0) shows the text"
type_keys meta_l-bracket_right
wait_last_screen "${PROMPT} ${TEXT}" 15 || report_b "B5: leaf 1 does not show the text on its prompt"
[ "$(stub_b_count)" -eq 3 ] || report_b "B5: the stub got $(stub_b_count) request(s), want 3"
echo "the text went to the pane where the double tap started, not to the pane that had the focus"

# ── 검사 20: 그 패널이 닫혔으면 넣지 않고 알린다 ─────────────────────────
# leaf 1에서 시작하고 Cmd+W로 닫는다. 자식은 제 그룹이라 셸의 SIGHUP을 안 받고 계속 녹음한다.
# 끝내면 전사는 되지만 넣을 곳이 없다 — NO PANE. 글자는 기록에 남는다(검사 22).
type_keys ctrl-u
double_tap
expect_recording 5 "B6"
type_keys meta_l-w
wait_count 'terminal: pane> closed leaf=1' 1 10 || report_b "B6: Cmd+W did not close leaf 1"
double_tap
wait_count 'terminal: dictate> stop pid=' 4 10 || report_b "B6: the double tap did not stop the recording"
wait_count 'terminal: dictate> no pane shell=' 1 20 || report_b "B6: the closed pane was not noticed"
wait_status '  NO PANE$' 10 || report_b "B6: the status line did not say NO PANE ($(last_status))"
[ "$(count_b 'terminal: dictate> insert len=')" -eq 2 ] || report_b "B6: something was inserted"
[ "$(last_screen_count "$TEXT")" -eq 0 ] || report_b "B6: the text landed in the remaining pane"
[ "$(stub_b_count)" -eq 4 ] || report_b "B6: the stub got $(stub_b_count) request(s), want 4"
type_keys ctrl-u
wait_status 'CAPS$' 10 || report_b "B6: NO PANE stayed after the next key ($(last_status))"
echo "a dictation whose pane closed was transcribed but not inserted anywhere, and said NO PANE"

# ── 검사 21: 키 없이 끝난 녹음 뒤의 더블 탭은 시작이다 ─────────────────────
# design 결정 10의 함정 3(Voxio V17). max_seconds=1이면 자식이 스스로 멈추고(`stopped at the
# 1s limit`) 그 줄이 단계를 transcribing으로 옮긴다. 그 뒤의 더블 탭은 "끝내라"가 아니라 새
# 시작이어야 한다 — 두 번째 실행도 스스로 멈추고 글자를 넣는다.
type_keys slash c o n f i g slash v d minus c a p ret
sleep 1
double_tap
expect_recording 6 "B7"
wait_count 'terminal: dictate> phase transcribing' 1 15 \
  || report_b "B7: the 1s limit did not move the phase (tars-dictate's line was not read)"
wait_count 'terminal: dictate> insert len=' 3 20 || report_b "B7: the self-stopped recording inserted nothing"
wait_last_screen "${PROMPT} ${TEXT}" 15 || report_b "B7: the text never showed up"
type_keys ctrl-u
double_tap
expect_recording 7 "B7 again"
wait_count 'terminal: dictate> insert len=' 4 20 || report_b "B7: the double tap after a keyless end did not start a new dictation"
[ "$(count_b 'terminal: dictate> (stop|ignored)')" -eq 4 ] || report_b "B7: a double tap after a keyless end was read as stop or ignored"
[ "$(count_b 'tars-dictate: recording stopped at the 1s limit')" -eq 2 ] || report_b "B7: the two runs did not stop at the limit"
wait_last_screen "${PROMPT} ${TEXT}" 15 || report_b "B7: the second text never showed up"
type_keys ctrl-u
[ "$(stub_b_count)" -eq 6 ] || report_b "B7: the stub got $(stub_b_count) request(s), want 6"
echo "a recording that stopped at its limit inserted its text, and the next double tap started again"

# ── 검사 22: 키가 없으면 마이크를 안 열고 NO KEY ──────────────────────────
type_keys slash c o n f i g slash v d minus n o k e y ret
sleep 1
double_tap
wait_count 'terminal: dictate> start pid=' 8 15 || report_b "B8: the double tap started no dictation"
wait_count 'terminal: dictate> exit code=3' 1 15 || report_b "B8: tars-dictate did not exit 3 without a key"
wait_status '  NO KEY$' 10 || report_b "B8: the status line did not say NO KEY ($(last_status))"
[ "$(count_b 'terminal: dictate> phase recording')" -eq 7 ] || report_b "B8: a run without a key reached the microphone"
[ "$(stub_b_count)" -eq 6 ] || report_b "B8: a run without a key reached the API"
type_keys ctrl-u
wait_status 'CAPS$' 10 || report_b "B8: NO KEY stayed after the next key ($(last_status))"
echo "without a key the dictation never recorded, said NO KEY, and the next key cleared it"

# ── 검사 23: stub이 받은 여섯과 기록 여섯 ──────────────────────────────────
# 요청은 B1 · B4 · B5 · B6 · B7 둘이다. 전부 마이크의 상수다 — terminal이 띄운 자식도 같은
# 마이크를 지났다. 기록도 여섯이다. 넣지 않은 둘(B4 비밀번호 · B6 닫힌 패널)도 남는다 —
# 전사가 된 순간부터 말한 것은 사라지지 않는다(Voxio 불변식 1).
while IFS= read -r req; do
  case "$req" in *'auth=[Bearer vd1-test-key]'*) ;; *) report_b "a boot B request lacks the key (${req})" ;; esac
  N="$(stub_field "$req" n)"
  [ "$(stub_field "$req" mode)" = "$FEED_VALUE" ] && [ "$(stub_field "$req" mode_count)" = "$N" ] \
    || report_b "a boot B recording is not the microphone's constant (${req})"
done < <(grep -a '^stub: POST ' "$STUBLOG_B")
[ "$(grep -acE '^stub: POST /ok/b ' "$STUBLOG_B")" -eq 4 ] && [ "$(grep -acE '^stub: POST /ok/cap ' "$STUBLOG_B")" -eq 2 ] \
  || report_b "the boot B requests are not four /ok/b and two /ok/cap"
# 정리도 여섯이다 — 전사된 여섯마다 하나, 원문이 사용자 메시지로 갔고 실패한 것이 없다.
[ "$(grep -acE '^stub-chat: POST /chat/ok/b .*user=\[안녕하세요 vd0-dictated\]' "$STUBLOG_B")" -eq 4 ] \
  && [ "$(grep -acE '^stub-chat: POST /chat/ok/cap .*user=\[안녕하세요 vd0-dictated\]' "$STUBLOG_B")" -eq 2 ] \
  || report_b "the boot B cleanup requests are not four /chat/ok/b and two /chat/ok/cap with the raw text"
[ "$(count_b 'tars-dictate: cleaned 18 characters into 17 in')" -eq 6 ] && [ "$(count_b 'tars-dictate: cleanup ')" -eq 0 ] \
  || report_b "not every boot B transcript was cleaned ($(grep -aE 'tars-dictate: clean' "$LOG" | tr -d '\r' | tail -n 3))"
echo "system_powerdown" >&3
wait_for_exit 60 || report_b "the guest did not power off after system_powerdown"
debugfs -R "dump dictation.jsonl $WORK/dictation_b.jsonl" "$DISK_B" >/dev/null 2>&1
HISTORY_B="$(grep -c '"raw":"안녕하세요 vd0-dictated","cleaned":"안녕하세요 vd2-cleaned","inserted":"안녕하세요 vd2-cleaned"' "$WORK/dictation_b.jsonl" 2>/dev/null || true)"
[ "${HISTORY_B:-0}" -eq 6 ] && [ "$(wc -l < "$WORK/dictation_b.jsonl")" -eq 6 ] \
  || report_b "dictation.jsonl holds ${HISTORY_B:-0} of the six transcripts with their cleaned text (the refused and the lost ones must stay)"
echo "the stub got six recordings of the microphone and six cleanups, and dictation.jsonl kept all six with both texts, inserted or not"

echo "VD check PASS"
