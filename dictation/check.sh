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
# 이 체인이 못 보는 것 — 진짜 Groq의 답(사람이 키를 넣고 실기에서 본다, running-tars.md) ·
# 실기 마이크의 소리 · 터미널이 글자를 커서 자리에 넣는 것(VD-M1).

# $GUEST_MEM 하나 때문에 source한다. audio 체인처럼 타이핑을 안 한다.
source ../gate_lib.sh

# openssl s_server가 듣는 컨테이너의 포트. 게스트는 10.0.2.2:이 번호로 붙는다 — SLIRP이
# 그것을 컨테이너의 127.0.0.1로 잇는다(lessons 45). 45492는 VD의 첫 번호다(lessons 포트 절).
TLS_PORT=45492

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

DISK=../out/dictation.img
LOG="$(mktemp)"
WORK="$(mktemp -d)"
STUBLOG="$WORK/stub.log"
QEMU_PID=""
TLS_PID=""

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  if [ -n "$TLS_PID" ] && kill -0 "$TLS_PID" 2>/dev/null; then
    kill "$TLS_PID" 2>/dev/null || true
    wait "$TLS_PID" 2>/dev/null || true
  fi
  rm -rf "$LOG" "$WORK"
}
trap cleanup EXIT

report_failure() {
  echo "FAIL: $1"
  echo "--- markers (${LOG}) ---"
  local marker
  for marker in \
    "tars-init: started service probe (pid" \
    "dictate-probe: start" \
    "dictate-probe: route [default via 10.0.2.2" \
    "dictate-probe: capture [" \
    "dictate-probe: tls default exit" \
    "dictate-probe: s1 exit" \
    "dictate-probe: s10 exit" \
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
  cat "$STUBLOG" 2>/dev/null
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
OK_OUT='"안녕하세요 vd0-dictated"'

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

# ── 검사 12: stub이 받은 요청은 여덟이고, 어느 WAV의 머리도 거짓말을 안 한다 ──
# 취소(s3)와 키 없음(s4)만 API에 안 간다. 머리의 길이는 SIGINT로 멈춘 셋(s1 · s7 · s9)이
# 본다 — arecord가 고치지 못한 머리를 tars-dictate가 다시 쓴다(검사 3의 주석).
REQUESTS="$(grep -ac '^stub: POST ' "$STUBLOG")"
[ "$REQUESTS" -eq 8 ] || report_failure "the stub got ${REQUESTS} request(s), want 8 (s3 and s4 must not call it)"
while IFS= read -r req; do
  [ "$(stub_field "$req" header_data)" = "$(stub_field "$req" data)" ] \
    || report_failure "a WAV reached the API with a header that does not match its length (${req})"
done < <(grep -a '^stub: POST ' "$STUBLOG")
echo "the stub got eight requests, and every WAV's header matched its length"

# ── 검사 13: 기록 — 전사가 성공한 다섯만 원문과 함께 남는다 ───────────────
# 끈 뒤 디스크에서 꺼낸다. 원문(raw)은 받은 그대로라 s8의 제어 문자가 JSON 이스케이프로
# 남고, inserted는 지운 것이다. 실패 · 무음 · 취소 · 키 없음은 한 줄도 안 남는다.
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
    my $ok = ($r->{at} =~ /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/ && !defined $r->{cleaned}
              && $r->{latency_ms} =~ /\A\d+\z/) ? "ok" : "bad";
    printf "raw=%s|inserted=%s|%d|%s\n", show($r->{raw}), show($r->{inserted}), $r->{audio_ms}, $ok;
  }' "$WORK/dictation.jsonl")" || report_failure "dictation.jsonl is not JSON lines"
echo "--- history ---"
printf '%s\n' "$HISTORY"
EXPECT_HISTORY='raw=안녕하세요 vd0-dictated|inserted=안녕하세요 vd0-dictated|S1|ok
raw=안녕하세요 vd0-dictated|inserted=안녕하세요 vd0-dictated|1000|ok
raw=안녕하세요 vd0-dictated|inserted=안녕하세요 vd0-dictated|1000|ok
raw=vd0-ctrl a\x{1b}[201~b\x{d}c\x{9}d\x{a}e\x{85}f\x{1b}|inserted=vd0-ctrl a[201~bc\x{9}d\x{a}ef|1000|ok
raw=안녕하세요 vd0-dictated|inserted=안녕하세요 vd0-dictated|1000|ok'
EXPECT_HISTORY="${EXPECT_HISTORY/S1/$(( S1_DATA * 1000 / 32000 ))}"
[ "$HISTORY" = "$EXPECT_HISTORY" ] || report_failure "dictation.jsonl does not hold the five successful runs as expected"
echo "dictation.jsonl keeps the five successful runs with the raw text next to what was inserted, and nothing else"

echo "VD check PASS"
