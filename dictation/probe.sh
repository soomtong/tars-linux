#!/usr/bin/bash
# VD 체인의 게스트 쪽 — 설정 디스크의 services.d/probe로 들어간다(audio/probe.sh와 같은 자리).
#
# init이 /config/services.d의 실행 파일로 이것을 띄우고, 표준 출력은 /dev/console(= 시리얼
# 로그)이다. 여기서 찍는 `dictate-probe:` 줄을 dictation/check.sh가 본다. 게이트는 게스트에
# 한 글자도 안 친다.
#
# 사람이 셸에서 하는 일 그대로를 한다 — /config/dictation.conf를 고치고, tars-dictate를
# 치고, Ctrl+C로 멈춘다. Ctrl+C는 tty가 앞의 작업 그룹 전체에 보내는 SIGINT이므로 여기서는
# tars-dictate를 제 그룹으로 띄우고(set -m) 그 그룹에 kill -INT를 보낸다. 전사 API는
# 컨테이너의 stub.pl이다 — 경로의 첫 마디가 답을 고르고 둘째 마디가 이 갈래의 이름이다.
#
# 끝나면 kill -TERM 1로 전원을 끈다. 체인이 그 뒤에 설정 디스크의 dictation.jsonl을 꺼낸다.
#
# 정리 단계(VD-M2)도 같은 stub이다 — 경로가 /chat/<답>/<갈래>면 stub이 chat completions로 답한다.
# 갈래 s11 ~ s21이 그것을 보고, 정리를 켠 채 cleanup_url을 안 적은 M0의 갈래는 기본 주소(진짜
# Groq)로 간다. 그 이름을 아래에서 127.0.0.1로 돌려 둔다 — 게이트는 Groq를 절대 부르지 않는다.

say() { echo "dictate-probe: $*"; }
flat() { tr '\n' '|' | sed 's/|$//'; }
STUB=http://10.0.2.100:8080

# 설정 파일을 사람처럼 통째로 다시 쓴다. 인자는 key=value 줄들이다.
conf() { printf '%s\n' "# written by the VD probe" "$@" > /config/dictation.conf; }

# tars-dictate를 한 번 돌리고 결과를 한 줄로 찍는다.
#   $1  갈래 이름(로그에서 찾는 글자)
#   $2  끝내는 법 — cap(max_seconds가 끝낸다) · int(1.5초 뒤 그룹에 SIGINT) ·
#       term(1초 뒤 그룹에 SIGTERM)
# out은 jq로 JSON 문자열을 만든다 — 개행 · 탭 · ESC가 그대로 콘솔에 나가면 줄이 깨진다.
# 걸린 시간(ms)도 찍는다. 키가 없을 때 "녹음 전에 끝났다"를 이 값으로 본다.
dictate() {
  local t0=$EPOCHREALTIME pid rc
  set -m
  tars-dictate > /tmp/vd-out 2> /tmp/vd-err &
  pid=$!
  set +m
  case $2 in
    int) sleep 1.5; kill -INT -- "-$pid" ;;
    term) sleep 1; kill -TERM -- "-$pid" ;;
  esac
  wait "$pid"
  rc=$?
  local ms=$(( (${EPOCHREALTIME/./} - ${t0/./}) / 1000 ))
  say "$1 exit ${rc} ms ${ms} out [$(jq -Rs . < /tmp/vd-out)] err [$(flat < /tmp/vd-err)]"
  say "$1 leftover wav [$(ls /tmp/tars-dictate.*.wav 2>/dev/null | flat)]"
}

say "start"
say "tars-dictate is [$(command -v tars-dictate)]"
say "jq [$(jq --version)]"

# Groq 막기. 정리의 기본 주소 api.groq.com을 게스트 안에서 127.0.0.1로 돌린다 — 그곳의 443에는
# 듣는 것이 없어 연결이 곧바로 거절된다(curl exit 7). /etc/hosts가 DNS보다 먼저다(LB의
# nsswitch.conf). 이 줄이 없으면 cleanup_url을 안 적은 갈래가 SLIRP을 지나 진짜 Groq에 가짜 키로
# 닿는다. 체인 검사 24가 그 거절을 본다.
echo '127.0.0.1 api.groq.com' >> /etc/hosts
say "hosts [$(grep groq /etc/hosts)]"

# 네트워크. stub(10.0.2.100)과 TLS 상대(10.0.2.2)에 닿으려면 dhcpcd가 주소를 붙이고
# 경로를 만들어야 한다. leased 줄은 주소보다 먼저 찍히므로(lessons 73) 경로를 본다.
for _ in $(seq 1 120); do
  ip -4 route show default 2>/dev/null | grep 'via 10.0.2.2' >/dev/null && break
  sleep 0.25
done
say "route [$(ip -4 route show default 2>&1 | flat)]"

# 소리 카드. HDA 코덱 탐색은 커널의 일 큐에서 돈다(audio/probe.sh와 같다). 부팅이 믹서를
# 켜는 것(AU-M1)도 기다린다 — 꺼져 있으면 녹음이 0만 받는다.
for _ in $(seq 1 100); do
  if [ -e /dev/snd/controlC0 ] && ! pgrep -x alsactl >/dev/null \
    && amixer -c 0 sget Capture 2>/dev/null | grep '\[on\]' >/dev/null; then break; fi
  sleep 0.1
done
say "capture [$(amixer -c 0 sget Capture 2>&1 | tail -n 1)]"

# 1. TLS. curl이 인증 기관 목록을 읽는가 — 목록이 없으면 77, 있는데 상대를 못 믿으면 60이다.
# 상대는 컨테이너의 openssl s_server(자기 서명 인증서)다. 같은 인증서를 --cacert로 주면
# 핸드셰이크까지 끝나 0이다(TLS 라이브러리가 돈다).
out="$(curl -sS -o /dev/null https://10.0.2.2:45492/ 2>&1)"; rc=$?
say "tls default exit ${rc} [$(printf '%s' "$out" | flat)]"
out="$(curl -sS --cacert /config/vd0-tls.pem https://10.0.2.2:45492/ 2>&1 | grep -o 's_server' | head -n 1)"
say "tls pinned [${out}]"

# 2. 기본값으로 — language 없음, 모델 기본, 사람이 Ctrl+C로 멈춘다.
conf "transcribe_url=${STUB}/ok/s1"
dictate s1 int

# 3. 설정 셋 — language · 모델 · 1초 상한. 사람이 아무것도 안 눌러도 끝난다.
conf "transcribe_url=${STUB}/ok/s2" "language=ko" "transcribe_model=vd0-model" "max_seconds=1"
dictate s2 cap

# 4. 녹음 중에 취소 — API를 안 부르고 오디오를 지운다.
conf "transcribe_url=${STUB}/ok/s3" "max_seconds=30"
dictate s3 term

# 5. 키가 없다 — 녹음 전에 끝난다(max_seconds=30이라 녹음했다면 30초를 걸린다).
mv /config/groq.key /config/groq.key.off
conf "transcribe_url=${STUB}/ok/s4" "max_seconds=30"
dictate s4 cap
# 같은 자리에서 환경 변수의 키 — 파일이 없어도 그것을 쓴다.
conf "transcribe_url=${STUB}/ok/s5" "max_seconds=1"
GROQ_API_KEY=vd0-env-key dictate s5 cap
mv /config/groq.key.off /config/groq.key

# 6. 서버가 거절한다(429).
conf "transcribe_url=${STUB}/fail/s6" "max_seconds=1"
dictate s6 cap

# 7. 무음 전사(" .") — 넣을 것이 없다. 이 갈래와 9는 Ctrl+C로 멈춘다 — arecord가 SIGINT에
# WAV 머리를 못 고치는 일이 판마다 달라서(VD design 실측 4), 머리를 다시 쓰는 tars-dictate의
# 줄이 빠지면 SIGINT 셋(s1 · s7 · s9) 중 하나에는 거의 반드시 드러나게 한다.
conf "transcribe_url=${STUB}/blank/s7" "max_seconds=30"
dictate s7 int

# 8. 응답에 제어 문자 — 지워서 낸다.
conf "transcribe_url=${STUB}/ctrl/s8" "max_seconds=1"
dictate s8 cap

# 9. 응답에 text가 없다.
conf "transcribe_url=${STUB}/notext/s9" "max_seconds=30"
dictate s9 int

# 10. 설정 파일의 모르는 키와 틀린 값은 경고만 하고 기본값으로 돈다.
conf "transcribe_url=${STUB}/ok/s10" "max_seconds=1" "colour=blue" "max_seconds=0"
dictate s10 cap

# ── 정리 단계(VD-M2) ──────────────────────────────────────────────────
# 전사는 모두 /ok(원문 "안녕하세요 vd0-dictated", 18글자)이고 정리 stub의 답이 갈래마다 다르다.
# 1초 상한으로 스스로 끝난다.
# 11. 기본값 — cleanup 키를 안 적었다. 켜짐이 기본인지, 요청이 Voxio의 모양인지 본다.
conf "transcribe_url=${STUB}/ok/s11" "cleanup_url=${STUB}/chat/ok/s11" "max_seconds=1"
dictate s11 cap
# 12. 끈다 — 정리 요청이 없다.
conf "transcribe_url=${STUB}/ok/s12" "cleanup_url=${STUB}/chat/ok/s12" "cleanup=off" "max_seconds=1"
dictate s12 cap
# 13. 원문과 같은 답(바꿀 것이 없었다). 틀린 값은 경고만 하고 켜짐에 머문다.
conf "transcribe_url=${STUB}/ok/s13" "cleanup_url=${STUB}/chat/same/s13" "cleanup=maybe" "max_seconds=1"
dictate s13 cap
# 14. 바깥 따옴표와 공백에 싼 답 · 모델 바꾸기.
conf "transcribe_url=${STUB}/ok/s14" "cleanup_url=${STUB}/chat/quoted/s14" "cleanup_model=vd2-model" "max_seconds=1"
dictate s14 cap
# 15. 답에 제어 문자 — 넣는 것은 거르고, 기록의 정리본은 받은 그대로다.
conf "transcribe_url=${STUB}/ok/s15" "cleanup_url=${STUB}/chat/ctrl/s15" "max_seconds=1"
dictate s15 cap
# 16 ~ 20. 원문으로 돌아가는 다섯 — 짧은 답(길이 가드) · 빈 답 · 느린 답(1.5초 상한) · 500 ·
# choices 없음. 어느 것도 실패가 아니다(exit 0).
conf "transcribe_url=${STUB}/ok/s16" "cleanup_url=${STUB}/chat/short/s16" "max_seconds=1"
dictate s16 cap
conf "transcribe_url=${STUB}/ok/s17" "cleanup_url=${STUB}/chat/empty/s17" "max_seconds=1"
dictate s17 cap
conf "transcribe_url=${STUB}/ok/s18" "cleanup_url=${STUB}/chat/slow/s18" "max_seconds=1"
dictate s18 cap
conf "transcribe_url=${STUB}/ok/s19" "cleanup_url=${STUB}/chat/fail/s19" "max_seconds=1"
dictate s19 cap
conf "transcribe_url=${STUB}/ok/s20" "cleanup_url=${STUB}/chat/nochoice/s20" "max_seconds=1"
dictate s20 cap
# 21. cleanup_timeout — 0.5초로 줄이면 1초 뒤의 답(wait)도 시간 초과다. 기본 1.5초였다면 받았을
# 답이다. 그 앞의 틀린 값(20)은 경고만 하고 1.5에 머문다.
conf "transcribe_url=${STUB}/ok/s21" "cleanup_url=${STUB}/chat/wait/s21" "cleanup_timeout=20" "cleanup_timeout=0.5" "max_seconds=1"
dictate s21 cap

sync
say "history lines [$(wc -l < /config/dictation.jsonl 2>/dev/null || echo none)]"
say "done"
say "powering off at uptime $(cut -d' ' -f1 /proc/uptime)"
kill -TERM 1
exec sleep 100000
