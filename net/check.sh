#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")"
REPO_ROOT="$(cd .. && pwd)"

# NW 체인 — 커널이 NIC를 보고 게스트가 주소를 받는다.
#
# 이 체인이 증명하는 사슬:
#   .config의 CONFIG_NET/INET/PACKET/UNIX → 커널에 IPv4 스택이 선다
#   CONFIG_NETDEVICES + CONFIG_VIRTIO_NET → 장치 계층과 드라이버가 있다
#   QEMU의 -netdev user + -device virtio-net-pci → 게스트에 그 PCI 장치가 붙는다
#   → 커널이 드라이버를 붙이고 /sys/class/net/eth0을 만든다
#   설정 디스크의 net=dhcp → init이 그 링크를 UP으로 올리고 dhcpcd를 띄운다
#   → dhcpcd가 SLIRP에서 10.0.2.15를 받고 hook이 /etc/resolv.conf를 쓴다
#
# M1까지는 첫 넷이 전부였다. M2가 뒤의 둘을 더했고, 그래서 이 체인이
# 게스트에 디스크를 물리는 여섯째 체인이 됐다.
#
# 왜 커널 로그로 판정하지 않는가. NW-M0의 실측이 답이다. 이 커널은
# virtio-net에 대해 부팅 로그에 한 줄도 안 찍고, 찍히는 것은
# `NET: Registered PF_*` 넷뿐인데 그 넷은 NIC가 하나도 없어도 찍힌다
# (실측 2가 정확히 그 상태에서 같은 줄들을 봤다). 그래서 그 넷은 양성
# 판정이 아니라 "스택이 섰다"의 보조 증거로만 쓴다.
#
# 대신 /sys/class/net을 본다. sysfs는 커널이 드라이버를 붙이면서 직접
# 만드는 것이라 게스트에 도구가 하나도 없어도 되고 셸의 ls 하나로 읽힌다.
#
# M3가 판정을 연결까지 늘렸다. 검사 8이 기본 경로를, 검사 9가 실제 TCP
# 연결을, 검사 10이 dhcpcd의 생존을 본다. 상대는 바깥 인터넷이 아니라
# QEMU 자신이다(design 결정 7) — 회선이 흔들려도 이 게이트의 답은 안 바뀐다.
#
# 여기까지가 나가는 방향 하나다. IN-M1이 받는 방향을 이어 붙였다:
#
#   QEMU의 -netdev hostfwd → 컨테이너 127.0.0.1:45465가 열린다
#   게스트의 nc -l -p 8080 → 커널이 /proc/net/tcp에 LISTEN을 적는다
#   → 체인이 그 포트에 붙어 게스트가 보낸 한 줄을 읽는다
#
# 우리 코드는 그 세 줄에 0줄이다. 듣는 것이 nc이고 거는 것이 bash의 /dev/tcp
# 이며 잇는 것이 QEMU다 — 그래서 검사 12·13이 실패하면 원인이 커널이거나
# QEMU이거나 게이트 자신이고, 셋이 서로 멀어서 잘 갈린다.
#
# TS-M1이 부팅을 하나 더 얹었다. 앞의 열여섯이 "바이트가 오간다"였다면
# 이쪽은 "그 바이트가 시계가 된다"다:
#
#   컨테이너의 perl stub이 UDP 123을 듣는다
#   설정 디스크의 ntp=10.0.2.2 → init이 fork한 자식이 48바이트를 보낸다
#   → SLIRP가 그것을 컨테이너에 넘긴다(TS-M0 실측 2)
#   → 자식이 답의 nonce를 대조하고 clock_settime으로 시계를 뛴다
#   → 게스트의 date가 2031년을 찍는다
#
# 이 부팅에서 우리 코드는 init/src/sntp.zig 하나다. 상대는 우리가 쓴 perl
# 스무 줄이고, 그 둘 사이의 모든 것(SLIRP · 커널의 UDP · dhcpcd의 주소)은
# 앞의 열여섯이 이미 따로 증명한 것들이다.
#
# TS-M2가 부팅을 하나 더 얹었다. 부팅 A가 "우리가 적은 주소에 묻는다"였다면
# 이쪽은 "DHCP가 알려 준 주소를 읽어서 묻는다"이고, 덤으로 음성 하나를 판다:
#
#   initrd에 심은 /run/tars/ntp_servers → init이 그 주소를 읽는다
#   그 주소가 어디에도 없다 → 자식이 답 없이 재시도만 한다
#   → 그런데도 셸이 부팅 A와 같은 시각에 뜬다(design 결정 3)
#
# 그 경로의 첫 조각(dhcpcd가 option 42를 hook에 넘기는 것)만 게이트가 못
# 본다. SLIRP가 그 옵션을 안 주기 때문이고(TS 확인 5), 대신 hook 자체는
# 빌드 절의 호스트 검사가 직접 돌려서 본다.
#
# 이 체인은 check.sh의 CHAINS에 열두번째로 들어 있다. 단독으로도 돌아간다
# (docker run ... bash net/check.sh).

# $GUEST_MEM과 type_keys·wait_for_screen 셋 다 쓴다.
source ../gate_lib.sh

# ── TS-M1 ───────────────────────────────────────────────────────────────
#
# 부팅 A가 쓰는 것들이다. 이 체인의 두 번째 QEMU이고, 앞의 열여섯 검사가
# 끝나고 첫 게스트가 꺼진 뒤에 뜬다.
#
# 이 블록이 빌드 절보다 위에 있는 이유는 아래 make_disk.sh가 $NTP_SERVER를
# 인자로 받기 때문이다 — 그 주소를 아는 자리를 이 파일 하나로 두려는 것이고,
# 안 그러면 같은 값이 체인과 디스크 스크립트 두 곳에 박힌다.
#
# 45467은 monitor 대역(45455~45464 · 45471)과 IN이 쓰는 둘(45465 · 45466)
# 밖이다.
NTP_MONITOR_PORT=45467

# 게스트가 시각을 묻는 자리. SLIRP에서 호스트(=이 컨테이너)를 가리키는
# 주소이고, TS-M0 실측 2가 여기로 간 UDP가 실제로 컨테이너에 닿는 것을 봤다.
NTP_SERVER=10.0.2.2
NTP_PORT=123

# stub이 답하는 시각. 두 값이 서로 맞아야 한다 — 1930367167이
# 2031-03-04T05:06:07Z다.
#
# 현실에 있을 수 없는 값이어야 한다는 것이 design 결정 6이고, 그것이 취향이
# 아니라 필수라는 것을 TS-M0 실측 4가 만들었다 — 게스트의 벽시계는 NTP 없이도
# 이미 호스트 시각이라 "맞아졌다"로는 아무것도 못 가린다.
STUB_UNIX=1930367167
STUB_YEAR=2031

LOGA="$(mktemp)"
STUBLOG="$(mktemp)"
QEMU_PID_A=""
STUB_PID=""

# ── TS-M2 ───────────────────────────────────────────────────────────────
#
# 부팅 B가 쓰는 것들이다. 이 체인의 세 번째 QEMU이고 부팅 A가 꺼진 뒤에 뜬다.
#
# 45468은 monitor 대역(45455~45464 · 45471)과 IN의 둘(45465 · 45466)과
# TS-M1의 하나(45467) 밖이다.
NTP_DHCP_MONITOR_PORT=45468

# 심는 주소. RFC 5737의 TEST-NET-1이라 어느 네트워크에도 실물이 없다
# (TS-M2 결정 M2-E). 죽은 주소여야 이 부팅의 값이 두 배가 된다 — 살아 있는
# 주소를 심으면 파일 경로만 증명되고, 죽은 주소를 심으면 design 결정 3의
# 음성("안 닿는 서버가 부팅을 안 막는다")까지 함께 증명된다.
#
# SLIRP 안의 주소(10.0.2.200 같은 것)를 안 쓰는 이유는 실패의 모양이
# 다르기 때문이다. 같은 서브넷이면 ARP가 실패하고, 바깥 주소면 기본 경로를
# 밟아 나갔다가 답이 안 온다 — 뒤가 실기계에서 NTP 서버가 죽었을 때의
# 모양에 가깝다.
NTP_DEAD_SERVER=192.0.2.1

# 셸이 뜨는 데 걸린 시간이 부팅 A보다 이만큼 넘게 길면 실패다(결정 M2-F).
# 막히는 경우에 붙는 시간이 60초 이상이고(자식이 30회 × 2초) 부팅 하나가
# TCG에서 12초 안팎이라, 10초는 그 사이가 넓게 비어 있는 자리다.
BOOT_DELTA_MAX=10

LOGB="$(mktemp)"
INITRD_B="$(mktemp)"
QEMU_PID_B=""
BOOT_A_SECONDS=0
BOOT_B_SECONDS=0

# 부팅 B의 initrd를 짓는다(결정 M2-D).
#
# kernel/initrd.cpio를 안 건드린다. 그 파일은 열두 체인이 함께 쓰는
# 산출물이고, 거기에 심으면 실기계용 initrd가 죽은 NTP 주소를 싣고 다닌다.
#
# 대신 cpio 한 조각을 뒤에 이어 붙인다. 커널의 initramfs 언패커가 버퍼를 다
# 쓸 때까지 archive를 이어 읽고 뒤의 것이 앞의 것을 덮는다 — 마이크로코드를
# 앞에 이어 붙이는 흔한 수법의 반대 방향이다. gzip 두 덩이를 이어 붙인 것도
# 그 자체로 정상적인 gzip stream이라 어느 경로로 풀리든 결과가 같다.
#
# init에게는 우리가 심은 파일과 dhcpcd의 hook이 쓴 파일이 구별되지 않는다.
# 그것이 design 결정 4가 경로를 자른 이유다 — SLIRP가 option 42를 영영 안
# 줘도 "파일 → init" 조각이 게이트 안에서 초록이 된다.
build_ntp_initrd() {
  local extra seg
  extra="$(mktemp -d)"
  seg="$(mktemp)"

  mkdir -p "${extra}/run/tars"
  printf '%s\n' "$NTP_DEAD_SERVER" > "${extra}/run/tars/ntp_servers"

  (cd "$extra" && find . | cpio -o -H newc --quiet) | gzip -6 > "$seg"
  cat ../kernel/initrd.cpio "$seg" > "$INITRD_B"

  rm -rf "$extra" "$seg"
}

if ! (cd ../kernel && ./build.sh); then
  echo "FAIL: kernel build failed"
  exit 1
fi

if ! (cd ../init && zig build); then
  echo "FAIL: init build failed"
  exit 1
fi

if ! (cd ../init && zig build test); then
  echo "FAIL: init host tests failed"
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

# ── 호스트 검사: hook 네 줄이 실제로 파일을 쓰는가 (TS-M2) ──────────────
#
# design 결정 4의 2번이다. 경로 넷 중 "hook → 파일" 조각은 게스트도 QEMU도
# 없이 증명된다 — dhcpcd가 하는 일이 변수를 채우고 이 파일을 source하는
# 것뿐이므로, 변수를 우리가 채우면 같은 코드가 같은 일을 한다.
#
# 부팅보다 앞에 두는 이유는 진단이다. 이 hook이 고장 나면 증상이 부팅 B의
# 검사 21(init이 파일을 못 읽는다)에서 나오는데, 그 자리는 원인에서 멀다.
#
# tars_ntp_file을 덮어쓰는 유일한 자리다(결정 M2-C). 안 덮으면 이 검사가
# 컨테이너의 진짜 /run/tars에 쓴다.
HOOK=../kernel/dhcpcd-hooks/30-tars-ntp
HOOKDIR="$(mktemp -d)"

if ! new_ntp_servers='192.0.2.1 198.51.100.7' \
     tars_ntp_file="${HOOKDIR}/ntp_servers" sh "$HOOK"; then
  echo "FAIL: the dhcpcd hook exited non-zero"
  rm -rf "$HOOKDIR"
  exit 1
fi
HOOK_FIRST="$(awk 'NR==1 {print $1}' "${HOOKDIR}/ntp_servers" 2>/dev/null || true)"
if [ "$HOOK_FIRST" != "192.0.2.1" ]; then
  echo "FAIL: the dhcpcd hook wrote [${HOOK_FIRST}] where 192.0.2.1 was expected"
  rm -rf "$HOOKDIR"
  exit 1
fi

# 음성. 변수가 안 오는 reason(option 42가 없는 리스)에서 파일을 만들면, init이
# 빈 파일을 읽고 "주소를 못 읽었다"로 기다림을 다 쓴다. 없는 것과 빈 것이
# 같은 뜻이어야 하므로 아무것도 안 하는 것이 맞다.
rm -f "${HOOKDIR}/ntp_servers"
if ! tars_ntp_file="${HOOKDIR}/ntp_servers" sh "$HOOK"; then
  echo "FAIL: the dhcpcd hook exited non-zero with no ntp servers"
  rm -rf "$HOOKDIR"
  exit 1
fi
if [ -e "${HOOKDIR}/ntp_servers" ]; then
  echo "FAIL: the dhcpcd hook wrote a file with no ntp servers to write"
  rm -rf "$HOOKDIR"
  exit 1
fi
rm -rf "$HOOKDIR"
echo "the dhcpcd hook writes the first ntp server and nothing else"

# NW-M2. 설정 디스크를 굽는다. config/check.sh와 같은 자리이고 다른 것은
# 이 디스크가 빈 것이 아니라는 것이다 — net=dhcp 한 줄을 debugfs로 미리
# 담아 굽는다. 그래서 이 체인은 게스트에 타이핑으로 설정을 쓰지 않는다.
#
# TS-M1이 인자를 하나 더했다. 이 스크립트는 이제 이미지를 둘 굽는다 —
# 검사 1~16이 쓰는 out/net.img와 부팅 A가 쓰는 out/net-ntp.img다.
if ! ./make_disk.sh "$NTP_SERVER"; then
  echo "FAIL: config disk build failed"
  exit 1
fi

# 45455=TF, 45456=CP, 45457=IP, 45458=PM, 45459=HD, 45460=TR, 45461=CM,
# 45462=HI, 45463=UT, 45471=RM. 겹치지 않는 번호를 쓰는 이유는 죽다 만
# QEMU가 남았을 때 엉뚱한 게스트에 명령을 보내지 않기 위해서다.
MONITOR_PORT=45464

# IN-M1. 바깥에서 게스트로 들어오는 입구다. 45465는 monitor 대역
# (45455~45464 · 45471) 밖이고, M0의 실측 6이 컨테이너 안에서 이 번호가
# 비어 있는 것을 실제로 열어 보고 확인했다. 45466은 IN-M2의 반대 방향 몫이다.
#
# 127.0.0.1에 묶는 것이 design 결정 6이다. 호스트 주소를 비우면 QEMU가 모든
# 인터페이스에 묶는데, 체인이 붙는 자리가 127.0.0.1이므로 기능상 손해가 없고
# 이 컨테이너가 어떤 네트워크에 놓여 있든 포트가 밖으로 안 샌다.
#
# 게스트 쪽 8080이 아래 guestfwd의 8080과 겹쳐 보이지만 다른 자리다.
# guestfwd가 가로채는 것은 게스트가 10.0.2.100:8080으로 거는 것이고, 이
# hostfwd가 잇는 것은 게스트 자신의 주소 10.0.2.15의 8080이다. 방향도 주소도
# 다르다.
INBOUND_PORT=45465
GUEST_LISTEN_PORT=8080

# IN-M2. 반대 방향(체인 → 게스트)의 입구다. 45466은 M0의 실측 6이 45465와
# 함께 비어 있는 것을 확인한 번호이고, 게스트 쪽 8081은 M0의 실측 3b가 실제로
# 써 본 포트다.
#
# 방향을 포트로 가르는 이유는 리스너가 한 번만 살기 때문이다(design 결정 7).
# 8080의 리스너는 검사 13이 읽는 순간 죽으므로 같은 포트를 다시 쓰려면
# 리스너를 또 띄워야 하는데, 그러면 두 방향의 실패가 같은 포트에서 겹쳐
# 보인다. 포트가 다르면 /proc/net/tcp의 숫자만으로도 어느 방향인지 갈린다.
REVERSE_PORT=45466
GUEST_REVERSE_PORT=8081

LOG="$(mktemp)"
QEMU_PID=""

# NW-M3 결정 A·B. 게스트가 10.0.2.100:8080에 붙으면 QEMU가 이 파일을 cat해서
# 연결에 흘려 넣는다(아래 -netdev의 guestfwd). 듣는 프로세스가 없으므로
# 체인이 관리할 상태가 안 늘고, QEMU가 사라지면 그 자리도 함께 사라진다.
#
# 저장소에 두지 않는 이유는 이 한 줄을 아는 것이 이 체인뿐이기 때문이다.
# 파일로 두면 "무슨 글자가 오는가"를 두 자리에서 봐야 한다.
#
# 경로에 쉼표가 없다는 것에 기댄다. QEMU의 옵션 문자열은 쉼표로 갈리므로
# 값 안의 쉼표는 두 번 적어야 하는데, mktemp가 주는 이름에는 쉼표가 없다.
#
# 글자의 유일한 조건은 게스트에 치는 명령줄에 없어야 한다는 것이다
# (결정 E). wait_for_screen이 로그 전체의 screen> 줄을 보므로 명령의
# 에코도 화면이고, 패턴이 거기 있으면 연결이 하나도 안 돼도 초록이 된다.
PAYLOAD="$(mktemp)"
printf 'nwm3-outbound-ok\n' > "$PAYLOAD"

cleanup() {
  if [ -n "$QEMU_PID" ] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  # TS-M1. 부팅 A의 게스트와 stub. 게스트를 먼저 보내는 편이 stub 로그의
  # 끝이 깔끔하다.
  if [ -n "$QEMU_PID_A" ] && kill -0 "$QEMU_PID_A" 2>/dev/null; then
    kill "$QEMU_PID_A" 2>/dev/null || true
    wait "$QEMU_PID_A" 2>/dev/null || true
  fi
  if [ -n "$STUB_PID" ] && kill -0 "$STUB_PID" 2>/dev/null; then
    kill "$STUB_PID" 2>/dev/null || true
    wait "$STUB_PID" 2>/dev/null || true
  fi
  # TS-M2. 부팅 B의 게스트와 그 부팅만 쓰는 initrd.
  if [ -n "$QEMU_PID_B" ] && kill -0 "$QEMU_PID_B" 2>/dev/null; then
    kill "$QEMU_PID_B" 2>/dev/null || true
    wait "$QEMU_PID_B" 2>/dev/null || true
  fi
  rm -f "$PAYLOAD" "$INITRD_B"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1"
  shift
  echo "--- markers ---"
  local marker
  for marker in \
    "NET: Registered PF_INET protocol family" \
    "NET: Registered PF_PACKET protocol family" \
    "NET: Registered PF_UNIX/PF_LOCAL protocol family" \
    "tars-init: loaded /config/tars.conf" \
    "tars-init: net link eth0 is up" \
    "tars-init: started dhcpcd on eth0" \
    "tars-init: started console shell" \
    "terminal: screen>"; do
    if grep -a "$marker" "$LOG" >/dev/null; then
      echo "  found   ${marker}"
    else
      echo "  MISSING ${marker}"
    fi
  done
  local pattern
  for pattern in "$@"; do
    # `|| true`가 없으면 이 루프가 첫 패턴에서 죽는다 — 안 맞는 grep은
    # 종료 코드 1이고 pipefail이 그것을 파이프라인 코드로 올린다.
    grep -a "$pattern" "$LOG" | head -3 | sed 's/^/  /' || true
  done
  # TS-M1. 부팅 A에서 죽었으면 이쪽이 진단의 절반이다 — 게스트가 보낸
  # datagram이 여기까지 왔는지는 게스트 로그만으로는 안 갈린다.
  if [ -s "$STUBLOG" ]; then
    echo "--- sntp stub ---"
    tail -n 20 "$STUBLOG"
  fi
  echo "--- last 60 lines ---"
  tail -n 60 "$LOG"
  exit 1
}

# -device virtio-gpu-pci가 있어야 /dev/dri/card0이 생기고 터미널이 뜬다.
# 그 터미널이 찍는 screen> 줄이 이 체인의 타이핑 대기가 서는 자리다
# (gate_lib.sh의 wait_for_screen). boot/check.sh가 반대 방향으로 같은 것을
# 쓴다 — 그 체인은 card0이 없어야 해서 이 장치를 일부러 안 준다.
#
# 결정 4의 두 줄이 아래 -netdev과 -device다. tap이 아니라 user(SLIRP)인
# 이유는 특권이 필요 없기 때문이고, 이 게이트가 아무 특권 없이 도는 성질을
# 네트워크 하나 때문에 버리지 않는다.
#
# IN-M1이 그 -netdev 값에 hostfwd를 하나 더했다. guestfwd가 게스트 → 바깥
# 방향이고 hostfwd가 그 반대다. 이 한 줄이 없으면 바깥에서 게스트로 들어오는
# 입구가 아예 존재하지 않는다 — 검사 13의 반사실이 그것을 확인한 자리다.
# hostfwd를 앞에 두는 것은 cmd: 값만 길이가 변하는 조각이라 그것을 끝에 두면
# 사람이 이 줄을 읽을 때 경계가 어디인지 눈에 보이기 때문이다.
#
# IN-M2가 그 옆에 둘째 hostfwd를 놓았다. 앞의 것이 게스트 → 체인 방향의
# 입구이고 뒤의 것이 체인 → 게스트 방향의 입구다. TCP는 한 연결로 양방향을
# 다 쓸 수 있지만 여기서는 포트를 나눴다 — 리스너가 한 번만 사는 것이라
# (결정 7) 방향마다 리스너가 따로 필요하고, 포트가 다르면 /proc/net/tcp의
# 숫자만으로 어느 방향이 안 섰는지가 갈린다.
qemu-system-x86_64 \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${INBOUND_PORT}-10.0.2.15:${GUEST_LISTEN_PORT},hostfwd=tcp:127.0.0.1:${REVERSE_PORT}-10.0.2.15:${GUEST_REVERSE_PORT},guestfwd=tcp:10.0.2.100:8080-cmd:cat ${PAYLOAD}" \
  -device virtio-net-pci,netdev=n0 \
  -drive file="${REPO_ROOT}/out/net.img",if=virtio,format=raw \
  -serial file:"$LOG" \
  -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID=$!

READY=0
for _ in $(seq 1 120); do
  if grep -a "terminal: screen>" "$LOG" >/dev/null; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READY" = "1" ] || fail "terminal never rendered a prompt"

# ── 검사 1: 스택이 섰나 ───────────────────────────────────────────────
# 양성 판정이 아니라 보조 증거다. 이 셋이 없으면 .config가 안 먹은 것이고,
# 아래 eth0 검사가 실패했을 때 원인이 드라이버가 아니라 스택이 된다.
for marker in \
  "NET: Registered PF_INET protocol family" \
  "NET: Registered PF_PACKET protocol family" \
  "NET: Registered PF_UNIX/PF_LOCAL protocol family"; do
  if ! grep -a "$marker" "$LOG" >/dev/null; then
    fail "the kernel never registered the network stack: ${marker}" "NET: Registered"
  fi
done
echo "the kernel registered PF_INET, PF_PACKET and PF_UNIX"

CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || fail "could not connect to the QEMU monitor" "terminal: screen>"

# ── 검사 2: 커널이 그 장치에 드라이버를 붙였나 ────────────────────────
# sendkey의 키 이름은 전부 소문자이고 공백은 spc, 슬래시는 slash다.
# tools/check.sh:350이 같은 모양으로 경로를 친다.
echo "=== typing 'ls /sys/class/net' ==="
type_keys l s spc slash s y s slash c l a s s slash n e t ret

if ! wait_for_screen "eth0"; then
  fail "no eth0 under /sys/class/net — the kernel did not bind virtio_net" \
    "terminal: screen>"
fi
echo "the kernel made /sys/class/net/eth0"

# ── 검사 3: 설정이 읽혔고 net=dhcp가 실효값인가 ───────────────────────
# 이 둘이 없으면 아래 판정이 무엇을 증명하는지가 흐려진다. 디스크가 안
# 붙었는데 주소가 붙는 경우는 없지만, 디스크가 안 붙어서 주소가 안 붙는
# 것과 코드가 틀려서 안 붙는 것은 다른 실패다.
if ! grep -a "tars-init: loaded /config/tars.conf" "$LOG" >/dev/null; then
  fail "the guest never read the config disk" "tars-init: mounted ext2" \
    "tars-init: created /config/tars.conf"
fi
if ! grep -aE "tars-init: config shell=.* net=dhcp" "$LOG" >/dev/null; then
  fail "the config disk did not turn the network on" "tars-init: config shell="
fi
echo "the guest read net=dhcp off the config disk"

# ── 검사 4: init이 한 일 둘 ───────────────────────────────────────────
# design 결정 6이 그은 경계가 이 두 줄이다. 우리 코드가 하는 일은 링크를
# 올리는 것과 dhcpcd를 띄우는 것이고, 그 뒤는 전부 dhcpcd다.
for marker in \
  "tars-init: net link eth0 is up" \
  "tars-init: started dhcpcd on eth0"; do
  if ! grep -a "$marker" "$LOG" >/dev/null; then
    fail "init did not do its half of the work: ${marker}" "tars-init: net"
  fi
done
echo "init raised the link and started dhcpcd"

# ── 검사 5: dhcpcd가 리스를 받았나 ────────────────────────────────────
# SLIRP의 주소 규칙이 고정이라 값을 박을 수 있다 — 게스트 10.0.2.15/24,
# 게이트웨이 10.0.2.2, DNS 10.0.2.3(design 결정 4). 이 값을 우리 코드에는
# 안 박는다. dhcpcd가 받아 오는 것이고, 체인만 그것이 무엇인지 안다.
#
# 이 대기가 plan에 없던 것이고, 없이 돌린 1회차가 아래 검사 6에서 죽었다.
# init이 `started dhcpcd`를 찍은 시점과 dhcpcd가 실제로 DHCP를 요청하는
# 시점 사이에 간격이 있다 — 시리얼 로그에서 `started dhcpcd`가 256번째 줄,
# `soliciting a DHCP lease`가 3745번째 줄이었고 그 사이 전부가 터미널의
# 렌더 로그였다. 즉 체인이 프롬프트를 보자마자 치면 언제나 너무 이르다.
#
# 화면이 아니라 시리얼 로그로 묻는 이유는 이것이 dhcpcd 자신의 말이기
# 때문이다. 검사 6이 사람의 눈으로 같은 사실을 다시 확인한다.
LEASED=0
for _ in $(seq 1 60); do
  if grep -a "eth0: leased 10.0.2.15" "$LOG" >/dev/null; then LEASED=1; break; fi
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
  sleep 1
done
[ "$LEASED" = "1" ] || fail "dhcpcd never got a lease from SLIRP" \
  "eth0: soliciting" "dhcpcd-10"
echo "dhcpcd leased 10.0.2.15 from SLIRP"

# ── 검사 6: 사람이 그것을 볼 수 있나 ──────────────────────────────────
# 검사 5와 같은 사실을 다른 자리에서 묻는다. 저쪽은 dhcpcd의 말이고 이쪽은
# 커널이 실제로 그 주소를 인터페이스에 갖고 있는가다 — dhcpcd가 리스를
# 받고도 주소를 못 붙이는 경우가 갈린다.
#
# `-4`를 준 것이 1회차에서 진단을 흐렸다. iproute2는 family 필터를 걸면 그
# family의 주소가 없는 인터페이스를 링크 줄조차 안 찍고 통째로 생략한다 —
# 주소가 붙기 전에 치면 에러가 아니라 빈 출력이 나온다. 그래서 "명령이
# 실패했다"와 "아직 주소가 없다"가 화면에서 구별되지 않았다. 검사 5가
# 그 순서를 보장하므로 이제 이 자리에서 빈 출력이 나오면 진짜 문제다.
#
# 점을 이스케이프하는 이유는 wait_for_screen의 패턴이 ERE이기 때문이다.
echo "=== typing 'ip -4 addr show eth0' ==="
type_keys i p spc minus 4 spc a d d r spc s h o w spc e t h 0 ret

if ! wait_for_screen "10\.0\.2\.15"; then
  fail "the address dhcpcd leased is not on the interface" "terminal: screen>"
fi
echo "the guest holds 10.0.2.15"

# ── 검사 7: 이름을 풀 자리가 생겼나 ───────────────────────────────────
# M0의 실측 6이 이 검사의 이유다. 그때는 주소가 붙었는데 /etc/resolv.conf가
# 아예 없었다 — install_tool이 바이너리만 복사해서 dhcpcd의 hook이 initrd에
# 없었기 때문이다. 증상이 "이름만 안 풀린다"라 원인에서 멀고, 그래서 게이트가
# 직접 본다.
echo "=== typing 'cat /etc/resolv.conf' ==="
type_keys c a t spc slash e t c slash r e s o l v dot c o n f ret

if ! wait_for_screen "nameserver 10\.0\.2\.3"; then
  fail "the dhcpcd hook never wrote /etc/resolv.conf" "terminal: screen>"
fi
echo "the hook wrote /etc/resolv.conf"

# ── 검사 8: 기본 경로가 생겼나 ────────────────────────────────────────
# 이 검사는 아래 검사 9가 무엇을 증명하고 무엇을 증명하지 않는지를 가른다.
#
# guestfwd의 상대 10.0.2.100은 게스트 주소 10.0.2.15/24와 같은 서브넷이라,
# 그 연결은 기본 경로를 한 번도 안 밟는다. 그러니까 검사 9 하나로 "밖으로
# 나가는 길이 있다"까지 말하면 게이트가 거짓을 말하는 것이다. 그 길은
# 여기서 따로 본다.
#
# 이 줄도 우리 코드가 아니라 dhcpcd가 쓴 것이다(design 결정 6의 경계).
# 값이 고정인 이유는 SLIRP의 규칙이 고정이기 때문이다 — 게이트웨이가
# 10.0.2.2다(design 결정 4).
#
# 둘을 더해도 "인터넷에 나간다"는 아니다. 그것은 이 게이트가 일부러 안
# 보는 것이고(design 결정 7), 사람이 손으로 확인한 자리는 M0의 실측 6이다.
echo "=== typing 'ip -4 route show' ==="
type_keys i p spc minus 4 spc r o u t e spc s h o w ret

if ! wait_for_screen "default via 10\.0\.2\.2"; then
  fail "dhcpcd never installed a default route" "terminal: screen>"
fi
echo "the guest has a default route via 10.0.2.2"

# ── 검사 9: 게스트가 TCP로 상대에 붙나 ────────────────────────────────
# design 결정 7이 이 자리다. 판정을 SLIRP 경계 안에서 닫는 이유는 게이트가
# 같은 입력에 늘 같은 답을 내야 하기 때문이다 — google.com으로 판정하면
# 회선이 흔들리는 날마다 우리 코드가 멀쩡한데 빨간불이 되고, 그러면 이
# 게이트가 말하는 것이 "코드가 맞나"가 아니라 "오늘 인터넷이 되나"가 된다.
#
# 듣는 프로세스는 없다. QEMU가 10.0.2.100:8080으로 오는 연결을 가로채
# 우리가 만든 파일을 흘려 넣는다(위 -netdev의 guestfwd, M0 실측 5).
#
# 게스트 쪽 도구가 nc인 이유. 실측 5는 bash의 /dev/tcp로도 붙었지만 이
# 부팅의 셸은 fish이고(설정 디스크에 net=dhcp 한 줄뿐이라 shell이 기본값
# 이다) fish에는 그 경로가 없다 — 그것은 bash의 기능이지 커널의 것이 아니다.
# nc는 M2가 넣었고 이름은 make_initrd.sh의 링크가 세운다(실체는
# nc.traditional). 즉 이 검사는 게스트에 아무것도 새로 요구하지 않는다.
#
# -w 5는 상대가 끝내 안 닫는 날 여기서 매달리지 않기 위한 것이다. 실측
# 5에서 nc.traditional은 상대가 닫자마자 나왔고 뒤 명령이 정상으로 이어졌다.
#
# curl은 안 친다. 실측 5에서 curl만 조용했는데 그것이 실패가 아니라 예상된
# 일이다 — guestfwd가 실행하는 것이 cat이라 HTTP 응답 형식이 아니다. curl은
# 게스트에 있지만(M2 결정 E) 이 게이트는 한 번도 안 친다.
#
# 판정 글자가 명령줄에 없는 글자여야 한다(결정 E). wait_for_screen은 마지막
# 프레임이 아니라 로그 전체의 screen> 줄을 보므로 친 명령의 에코도 화면이다.
# 10.0.2.100으로 판정하면 연결이 하나도 안 돼도 초록이 된다.
echo "=== typing 'nc -w 5 10.0.2.100 8080' ==="
type_keys n c spc minus w spc 5 spc 1 0 dot 0 dot 2 dot 1 0 0 spc 8 0 8 0 ret

if ! wait_for_screen "nwm3-outbound-ok"; then
  fail "the guest could not open a TCP connection through SLIRP" \
    "terminal: screen>"
fi
echo "the guest read our payload over TCP"

# ── 검사 10: dhcpcd가 아직 살아 있나 ──────────────────────────────────
# 리스는 한 번 받고 끝이 아니다. dhcpcd가 배경에 남아 갱신을 맡는다(M0
# 실측 4가 그 프로세스가 PID 1에 재부모화되는 것을 봤다). 받자마자 죽어도
# 검사 5·6·7은 전부 초록이므로 그 실패는 이 자리에서만 보인다.
#
# 그리고 이 검사가 아래 종료 검사의 뜻을 만든다. 유예 음성 검사(grace
# period expired)는 "SIGTERM을 안 받은 것이 없다"는 말인데, 그때 dhcpcd가
# 이미 죽어 있었으면 그 초록이 아무것도 증명하지 않는다.
#
# 개수를 1로 박지 않는다(결정 F). dhcpcd 10은 특권 분리로 자식을 더 띄울
# 수 있고 그 수는 우리가 고른 값이 아니다. 우리가 묻는 것은 "아직 있나"
# 하나다. 2026-09-14에 잰 값이 1이었다 — 적어만 두고 박지는 않는다.
#
# 왜 pgrep -l이 아닌가. 친 명령의 에코가 화면이고 거기에 dhcpcd가 이미
# 있다(결정 E). 그래서 출력에만 생기는 글자로 판정한다 — 명령 치환의
# 결과가 붙는 dhcpcd-alive=N이다. 치환 문법은 config/check.sh의
# NEG_COUNT_KEYS와 같은 모양이고($(가 shift-4 shift-9, )가 shift-0),
# fish가 그것을 읽는다.
echo "=== typing 'echo dhcpcd-alive=\$(pgrep -c dhcpcd)' ==="
type_keys e c h o spc d h c p c d minus a l i v e equal \
  shift-4 shift-9 p g r e p spc minus c spc d h c p c d shift-0 ret

if ! wait_for_screen "dhcpcd-alive=[1-9]"; then
  fail "dhcpcd is not running any more" "terminal: screen>"
fi
echo "dhcpcd is still running"

# ── 검사 11: QEMU가 붙인 기본 NIC는 안 보인다 ─────────────────────────
# 결정 3이 통째로 얹혀 있는 성질이다. 우리가 e1000 드라이버를 안 켜므로
# 게스트가 그 PCI 장치를 보고도 그냥 넘어간다. 이 검사가 없으면 기존 체인
# 열 개가 조용히 NIC를 하나 더 갖게 되는 날을 못 잡는다.
#
# 패턴을 하나씩 나눠 거는 이유는 check.sh의 require_no_early_exit_pipe가
# 쓰는 정규식이 파이프 문자를 구분자로 읽기 때문이다. 대안을 한 줄에 몰면
# 그 lint가 이 줄을 어떻게 읽을지가 사람 눈에 안 보인다.
# 이름이 순수 숫자이면 안 된다(TS-M2가 고친 자리). 원래 이 목록에 `8139`가
# 있었고, 그것이 드라이버가 아니라 커널 printk의 타임스탬프에 걸렸다 —
# `[    1.381391] clocksource: tsc: ...` 한 줄이 체인을 빨갛게 만든다. 부팅
# 시각이 그 값일 때만 걸리므로 회차마다 흔들렸고, 2026-09-15의 반복 실행
# 열일곱 판 중 한 판이 여기서 죽었다.
#
# 그래서 커널이 실제로 찍는 이름을 적는다. 8139 계열의 모듈 이름이 8139cp와
# 8139too 둘이고, 둘 다 글자를 포함하므로 숫자 사이에 우연히 나타날 수 없다.
# `\b`를 붙이는 길은 안 골랐다 — 소수점 바로 뒤(`[    2.813900]`)에서는 그
# 경계가 서기 때문에 같은 함정이 좁아질 뿐 안 없어진다.
for driver in e1000 8139cp 8139too ne2k r8169 pcnet32 vmxnet; do
  if grep -ai "$driver" "$LOG" >/dev/null; then
    fail "a NIC driver we did not turn on showed up in the kernel log: ${driver}" \
      "$driver"
  fi
done
echo "no driver we did not turn on appeared"

# ── 검사 12: 게스트가 포트를 열었나 ───────────────────────────────────
# IN-M1이 더한 검사 둘 중 앞의 것이다. 이 검사가 있어야 아래 검사 13이
# 실패했을 때 원인이 "게스트가 안 들었다"인지 "길이 안 섰다"인지 갈린다.
# 없으면 둘이 같은 빨간불이고, 그 둘은 고치는 자리가 완전히 다르다.
#
# 한 번 응답하고 끝나는 리스너다(design 결정 7). echo가 만든 한 줄을 nc가
# 연결에 흘려 넣고 닫는다. 연결 하나를 받고 끝나므로 체인이 정리할 프로세스가
# 안 남는다 — 위 guestfwd가 "듣는 프로세스가 없다"로 얻은 성질을 게스트
# 쪽에서 얻는 방법이 이것이다.
#
# 배경(&)에 두는 것이 M0의 실측 2다. fish에서 프롬프트가 그대로 돌아오고,
# 리스너가 사는 동안 화면에 한 글자도 안 찍는다.
#
# 이 검사가 검사 13보다 반드시 앞이어야 한다. 리스너가 한 번만 사는 것이라
# 체인이 붙는 순간 죽고, 그 뒤에는 /proc/net/tcp에서 사라진다. M0의 실측 1이
# 세 자리에서 0 · 0 · 1로 갈린 것이 그 증거다.
#
# 판정을 /proc/net/tcp로 하는 이유는 그것이 커널이 직접 만드는 것이라
# 게스트에 도구가 하나도 필요 없기 때문이다. 검사 2가 /sys/class/net에
# 기댄 것과 같은 근거다. 포트가 16진수로 적혀서 8080이 1F90이다.
#
# 왜 grep -c를 그냥 치지 않는가. 친 명령의 에코가 화면이므로(결정 E,
# NW-M3 실측 2) 1F90을 그대로 치면 연결이 하나도 안 돼도 그 글자가 화면에
# 있다. 그래서 출력에만 생기는 글자로 판정한다 — 명령 치환의 결과가 붙는
# inm1-listen=N이다. 검사 10의 dhcpcd-alive=N과 같은 모양이고 치환 문법도
# 같다($(가 shift-4 shift-9, )가 shift-0).
#
# 이 두 타이핑 사이의 시간이 design 위험 1을 통째로 없앤다. bind는 명령이
# 실행된 뒤 4~104밀리초에 끝나는데(M0 실측 5) 아래 타이핑이 45키가 넘어서
# 초 단위로 걸린다. 즉 검사 13이 붙을 때 리스너는 이미 오래 서 있다.
echo "=== typing the one-shot listener on port ${GUEST_LISTEN_PORT} ==="
type_keys e c h o spc i n m 1 minus i n b o u n d minus o k spc \
  shift-backslash spc n c spc minus l spc minus p spc 8 0 8 0 spc shift-7 ret

echo "=== typing 'echo inm1-listen=\$(grep -c 1F90 /proc/net/tcp)' ==="
type_keys e c h o spc i n m 1 minus l i s t e n equal \
  shift-4 shift-9 g r e p spc minus c spc 1 shift-f 9 0 spc \
  slash p r o c slash n e t slash t c p shift-0 ret

if ! wait_for_screen "inm1-listen=[1-9]"; then
  fail "the guest never put port ${GUEST_LISTEN_PORT} into LISTEN" \
    "terminal: screen>"
fi
echo "the guest is listening on port ${GUEST_LISTEN_PORT}"

# ── 검사 13: 바깥에서 붙어 게스트가 보낸 바이트를 읽나 ────────────────
# 이 체인이 처음으로 화면도 커널 로그도 아닌 것으로 판정하는 자리다
# (design 결정 3). 앞의 검사 열둘은 전부 시리얼 로그의 글자를 보는데,
# 이 검사가 보는 것은 체인 자신이 소켓에서 받은 바이트다.
#
# 그 차이가 값진 이유가 NW-M3 실측 2다. wait_for_screen은 마지막 프레임이
# 아니라 로그 전체의 screen> 줄을 보므로 우리가 친 명령의 에코도 화면이고,
# 그래서 판정 글자를 고를 때마다 "이 글자가 명령줄에 없나"를 따져야 한다.
# 체인이 읽은 바이트는 애초에 게스트 화면을 안 지나가므로 그 함정이 성립하지
# 않는다.
#
# rc로 판정하지 않는다. M0의 실측 4가 가장 값진 것을 여기서 쟀다 — 게스트에
# 듣는 프로세스가 하나도 없어도 이 connect는 rc=0으로 성공한다. QEMU가 호스트
# 포트를 스스로 listen하고 있어서 붙는 것은 언제나 되고, 게스트 쪽에 받을
# 것이 없으면 그냥 닫기 때문이다. 즉 "붙었다"와 "받았다"가 완전히 다른
# 사실이고, 음성과 양성이 rc에서 같은 값이다.
#
# cat이 아니라 read인 이유가 design 결정 10이다. nc.traditional은 바이트를
# 보낸 뒤에도 연결을 안 닫아서 cat <&5가 EOF를 못 보고 매달린다(M0 실측 5에서
# 10초 timeout을 다 썼다). 게이트는 이 체인을 세 번 도니 그대로 두면 30초다.
# read가 가정하는 것은 "판정 글자가 개행으로 끝나는 한 줄"인데, 그 한 줄을
# 만드는 echo를 바로 위 검사 12가 타이핑하므로 가정의 양쪽 끝이 이 파일 안에
# 있다.
#
# fd가 3이 아니라 5인 이유. 3은 이 체인이 QEMU monitor에 쓰고 있고 아래
# system_powerdown이 아직 그 fd로 간다.
#
# 재시도 10회 × 0.2초는 넉넉하게 잡은 값이다. M0 실측 5로는 bind가 100밀리초
# 안에 끝나고, 게다가 검사 12의 타이핑이 그 사이에 통째로 들어가 있다.
# 첫 회에 닿는 것이 정상이고 루프는 보험이다.
INBOUND_CONNECTED=0
INBOUND_OK=0
INBOUND_GOT=""
for _ in $(seq 1 10); do
  if exec 5<>"/dev/tcp/127.0.0.1/${INBOUND_PORT}"; then
    INBOUND_CONNECTED=1
    INBOUND_GOT=""
    read -r -t 5 INBOUND_GOT <&5 || true
    exec 5<&-
    exec 5>&-
    case "$INBOUND_GOT" in
      *inm1-inbound-ok*) INBOUND_OK=1; break ;;
    esac
  fi
  sleep 0.2
done

# 실패를 둘로 가른다. 앞은 QEMU가 그 포트를 아예 안 열었다는 뜻이고(hostfwd
# 줄이 없거나 QEMU가 그것을 안 받았다), 뒤는 열렸는데 게스트 쪽에서 아무것도
# 안 왔다는 뜻이다. M0 실측 6이 그 둘이 bash에서 완전히 다르게 보인다고 쟀다 —
# 빈 로컬 포트는 즉시 Connection refused이고, hostfwd 포트는 게스트에 아무도
# 없어도 붙는다.
if [ "$INBOUND_CONNECTED" = "0" ]; then
  fail "nothing accepted on 127.0.0.1:${INBOUND_PORT} — QEMU never opened the hostfwd port" \
    "terminal: screen>"
fi
[ "$INBOUND_OK" = "1" ] || \
  fail "the hostfwd port accepted us but the guest sent nothing we know (got: [${INBOUND_GOT}])" \
    "terminal: screen>"
echo "the chain read inm1-inbound-ok off the guest's listener"

# 여기서 리스너가 죽고, 그때 fish가 `fish: Job N, '...' has ended`를 화면에
# 찍는다(M0 실측 2). M1에는 그 뒤에 화면을 보는 검사가 하나도 없어서 아무것도
# 안 민다 — 검사 14를 이 뒤에 놓는 IN-M2가 그 한 줄을 고려해야 한다.
#
# IN-M2가 그 뒤를 채웠다. 아래 검사 14의 첫 타이핑이 프롬프트를 다시 그리게
# 만들고 그때 그 줄이 나오는데, 아래 세 검사의 패턴 어느 것도 그 줄과 안
# 부딪친다. wait_for_screen이 마지막 프레임이 아니라 로그 전체를 보므로
# 화면 좌표가 밀리는 것도 문제가 안 된다.

# ── 검사 14: 게스트가 둘째 포트를 열었나 ──────────────────────────────
# 반대 방향(체인 → 게스트)의 준비다. 검사 12와 같은 모양이고 같은 일을 둘
# 한다 — 실패를 갈라 주는 것과, 이 타이핑 자체가 bind가 끝날 시간을 만드는
# 것. 뒤의 것이 여기서는 더 중요하다(design 결정 11). 검사 13에서는 검사 12의
# 타이핑 48키가 리스너와 체인 사이를 메웠는데, 반대 방향에는 그 여유가 없다.
#
# 리스너의 모양이 M0의 실측 3b가 실제로 돌린 것이다. 받는 것을 화면이 아니라
# 파일로 떨어뜨린다 — 체인이 보낸 글자가 게스트 화면에 곧바로 나오면 그것이
# 검사 15의 판정 글자가 되는데, 그러면 "받았다"와 "nc가 무언가를 찍었다"가
# 안 갈린다. 파일로 받고 사람이 cat으로 꺼내면 그 글자가 확실히 게스트를
# 한 번 지나온 것이 된다.
#
# fish에서 > 는 shift-dot이다(config/check.sh:68의 주석이 같은 자리를 적고
# 있다). & 는 shift-7이고 M1의 실측 9가 그 키 이름이 실제로 도는 것을 봤다.
#
# 8081이 /proc/net/tcp에 1F91로 적힌다. 검사 12의 1F90과 한 글자 차이라
# 눈으로는 헷갈리지만 게이트는 안 헷갈린다 — 두 리스너가 동시에 살아 있는
# 구간이 없기 때문이다(8080의 것은 검사 13이 읽는 순간 죽는다).
#
# 왜 grep -c를 그냥 치지 않는가는 검사 12와 같다. 친 명령의 에코가 화면이므로
# (결정 E) 출력에만 생기는 글자로 판정한다 — inm2-listen=N이다.
# stdin을 /dev/null로 돌리는 것이 이 줄에서 가장 중요한 조각이다
# (TS-M2가 고친 자리). 그것이 없으면 이 검사가 회차마다 흔들린다 —
# 배경 job의 stdin이 터미널인데 nc는 연결이 오면 stdin도 읽으려 하고, 배경에서
# 터미널을 읽으면 커널이 SIGTTIN을 보내 그 job을 멈춘다. 멈춘 nc는 받은
# 바이트를 파일에 안 쓰므로 아래 검사 15가 빈 파일을 본다.
#
# 화면이 그 순간을 글자로 남긴다. 실패한 회차의 화면에는
# `fish: Job 1, 'nc -l -p 8081 > /tmp/inm2.txt &' has stopped`가 있고, 성공한
# 회차에는 같은 자리에 `has ended`가 있다 — 멈춘 것과 끝난 것이다.
#
# 8080의 리스너가 이 병에 안 걸리는 이유도 같은 사실이 설명한다. 그쪽은
# `echo … | nc -l -p 8080 &`이라 nc의 stdin이 파이프이고 터미널이 아니다.
#
# `<`가 shift-comma다. 이 저장소에서 처음 쓰는 키 이름이고, 틀리면 증상이
# 바로 아래 검사 14에서 나온다(명령줄이 깨져 LISTEN이 안 선다).
echo "=== typing the reverse listener on port ${GUEST_REVERSE_PORT} ==="
type_keys n c spc minus l spc minus p spc 8 0 8 1 spc shift-comma spc \
  slash d e v slash n u l l spc shift-dot spc \
  slash t m p slash i n m 2 dot t x t spc shift-7 ret

echo "=== typing 'echo inm2-listen=\$(grep -c 1F91 /proc/net/tcp)' ==="
type_keys e c h o spc i n m 2 minus l i s t e n equal \
  shift-4 shift-9 g r e p spc minus c spc 1 shift-f 9 1 spc \
  slash p r o c slash n e t slash t c p shift-0 ret

if ! wait_for_screen "inm2-listen=[1-9]"; then
  fail "the guest never put port ${GUEST_REVERSE_PORT} into LISTEN" \
    "terminal: screen>"
fi
echo "the guest is listening on port ${GUEST_REVERSE_PORT}"

# ── 검사 15: 체인이 보낸 바이트를 게스트가 받나 ───────────────────────
# 받는 길의 반대쪽이다. TCP는 양방향이고 두 방향이 커널에서 다른 버퍼를
# 지난다 — 한 방향만 보고 "길이 섰다"고 말하면 그 말이 실제보다 넓다
# (design 결정 5).
#
# 이 방향만은 화면으로 판정한다(design 결정 3의 단서). 게스트가 받은 것을
# 체인에게 알릴 통로가 화면뿐이기 때문이다. 다만 판정 글자를 우리가 게스트에
# 타이핑하지 않으므로 에코 함정에 안 걸린다 — inm2-reverse-ok는 이 파일이
# 소켓으로 흘려 넣는 글자이고, 게스트 명령줄에는 파일 이름만 나온다.
#
# 보내고 바로 닫는다. 게스트의 nc는 EOF를 봐야 끝나고(M0 실측 3b), 끝나야
# 파일이 확실히 다 써진다. 닫는 것이 늦으면 아래 cat이 빈 파일을 볼 수 있다.
#
# fd가 6인 이유. 3은 monitor이고 5는 검사 13이 썼다(닫혔지만 검사 16이 다시
# 쓴다). 방향마다 번호를 나눠 두면 로그에서 어느 줄이 어느 방향인지 보인다.
#
# 재시도가 없다. 검사 14가 LISTEN을 이미 확인했으므로 여기서 못 닿으면 그것은
# 타이밍이 아니라 길의 문제다. 재시도를 두면 그 구별이 흐려진다.
REVERSE_SENT=0
if exec 6<>"/dev/tcp/127.0.0.1/${REVERSE_PORT}"; then
  printf 'inm2-reverse-ok\n' >&6 && REVERSE_SENT=1
  exec 6<&-
  exec 6>&-
fi

# 실패를 둘로 가른다. 검사 13과 같은 갈래다 — 빈 로컬 포트는 즉시
# Connection refused이고(M0 실측 6) hostfwd 포트는 게스트에 아무도 없어도
# 붙는다(실측 4). 그래서 앞의 것이 "QEMU가 이 입구를 안 열었다"이고 뒤의
# 화면 판정이 "열렸는데 게스트까지 안 닿았다"이다.
[ "$REVERSE_SENT" = "1" ] || \
  fail "nothing accepted on 127.0.0.1:${REVERSE_PORT} — QEMU never opened the second hostfwd port" \
    "terminal: screen>"

echo "=== typing 'cat /tmp/inm2.txt' ==="
type_keys c a t spc slash t m p slash i n m 2 dot t x t ret

if ! wait_for_screen "inm2-reverse-ok"; then
  fail "the guest never received what the chain sent" "terminal: screen>"
fi
echo "the guest received inm2-reverse-ok from the chain"

# ── 검사 16: 듣는 것이 없으면 체인이 그것을 읽어 내나 ─────────────────
# 앞의 검사 넷이 전부 초록인 장식이 아니라는 것을 증명하는 자리다. 여기서
# 붙는 포트가 검사 13과 같은 45465인 이유가 그것이다 — 같은 길, 같은 fd,
# 같은 read인데 게스트 쪽 리스너만 없다. 즉 이것은 검사 13의 음성 대조군이다.
#
# 게스트에 아무것도 안 친다. 8080의 리스너는 한 번만 사는 것이라(결정 7)
# 검사 13이 읽는 순간 이미 죽었고, M0의 실측 1이 그 뒤 /proc/net/tcp의
# 1F90이 0으로 돌아가는 것을 봤다. 그래서 음성을 만들기 위해 할 일이 없다.
#
# 기다리지 않는다(design 결정 10). 듣는 것이 없으면 QEMU가 붙여 주고 곧바로
# 닫으므로 read가 즉시 EOF를 보고 빈 값으로 돌아온다 — M0의 실측 4가 잰
# 값이 3~38밀리초다. -t 2는 그 예상이 틀린 날 게이트가 여기서 매달리지
# 않게 하는 상한이고, 이 값이 실제로 쓰이면 그 자체가 새 사실이다.
#
# 붙는 것에 성공했는지를 따로 본다. 이것이 이 검사에서 가장 중요한 줄이다 —
# 안 보면 hostfwd가 통째로 사라진 날에도 이 검사가 초록이 된다(못 붙어서
# 아무것도 못 읽은 것과 붙었는데 안 온 것이 같은 모양이 되기 때문이다).
# 음성 검사가 거짓 초록이 되는 길은 대개 이렇게 생겼다.
#
# rc는 안 본다. M0의 실측 4가 음성과 양성이 rc에서 같은 값이라고 쟀다.
echo "=== connecting with nothing listening on port ${GUEST_LISTEN_PORT} ==="
NEG_CONNECTED=0
NEG_GOT=""
if exec 5<>"/dev/tcp/127.0.0.1/${INBOUND_PORT}"; then
  NEG_CONNECTED=1
  read -r -t 2 NEG_GOT <&5 || true
  exec 5<&-
  exec 5>&-
fi

[ "$NEG_CONNECTED" = "1" ] || \
  fail "the negative check could not even connect — the hostfwd port is gone" \
    "terminal: screen>"
[ -z "$NEG_GOT" ] || \
  fail "something answered on 127.0.0.1:${INBOUND_PORT} where nothing should be listening (got: [${NEG_GOT}])" \
    "terminal: screen>"
echo "with no listener the chain read nothing, as it should"

# ── 끈다 ──────────────────────────────────────────────────────────────
echo "=== sending system_powerdown to the guest ==="
echo "system_powerdown" >&3
sleep 0.3

exec 3<&-
exec 3>&-

GONE=0
for _ in $(seq 1 30); do
  if ! kill -0 "$QEMU_PID" 2>/dev/null; then GONE=1; break; fi
  sleep 1
done
[ "$GONE" = "1" ] || fail "the guest did not switch itself off" \
  "tars-init: shutdown requested"

# SL-M2가 세운 것. 유예가 다 지나가면 무언가가 SIGTERM을 안 받은 것이다.
#
# M2부터 이 검사가 design 위험 2의 실제 시험이다. 이 부팅에는 dhcpcd가 있고
# 그것은 감독 목록 밖에 있다(결정 9의 갈래 A) — 배경으로 내려가면서 PID 1에
# 재부모화되므로 reapAll()이 세기는 하지만, 우리가 띄운 것 중 유일하게
# Child 배열에 없는 프로세스다. M0의 실측 4가 "SIGTERM에 죽는다"고 쟀고,
# 그 전제가 깨지는 날 여기가 빨간불이 된다.
if grep -a "grace period expired" "$LOG" >/dev/null; then
  fail "something outlived SIGTERM and burned the whole grace period" \
    "grace period expired"
fi

# ══ 부팅 A: 우리 코드가 시계를 뛴다 (TS-M1) ═══════════════════════════
#
# 여기서부터 게스트가 새로 뜬다. 앞의 열여섯과 디스크가 다르고
# (out/net-ntp.img — net=dhcp에 ntp=10.0.2.2 한 줄이 더 있다) 상대가 하나
# 더 있다(컨테이너에서 도는 perl stub).
#
# 왜 앞의 부팅에 얹지 않는가. 얹으면 검사 1~16이 전부 시계가 2031년인
# 게스트에서 돌고, 그 열여섯이 실패하는 날 원인이 "받는 길"인지 "시계"인지
# 안 갈린다. 부팅 하나를 더 치르고 실패를 가른다.
#
# 이 부팅이 design 실측 7이 남긴 숙제도 함께 답한다. TS-M0의 하네스는 콘솔
# 셸만 써서 "렌더가 살아 있다"와 "화면에 할 일이 없다"가 같은 값이었다
# (TR-M2의 needs_redraw 문지기). 이 부팅은 시계를 뛴 뒤에 화면에 타이핑을
# 하므로, 검사 19가 서는 것 자체가 렌더가 점프를 견뎠다는 증거다.
echo "=== booting again with ntp=${NTP_SERVER} ==="

# stub을 먼저 띄운다. 게스트가 부팅하는 동안 이미 듣고 있어야 한다.
perl ./sntp_stub.pl "$NTP_PORT" "$STUB_UNIX" > "$STUBLOG" 2>&1 &
STUB_PID=$!
sleep 1
if ! kill -0 "$STUB_PID" 2>/dev/null; then
  echo "FAIL: the sntp stub died at startup"
  cat "$STUBLOG"
  exit 1
fi
echo "the sntp stub is listening on udp/${NTP_PORT}"

# type_keys·wait_for_screen·fail이 보는 것은 전역 $LOG다. 이 체인은 이제
# 부팅이 둘이고, 그 둘을 잇는 자리가 이 한 줄이다(config/check.sh의
# edit_config_in_guest가 같은 모양이다).
LOG="$LOGA"

# 앞의 QEMU 줄에서 hostfwd·guestfwd를 뺀 것이다. 이 부팅은 TCP를 하나도
# 안 쓴다 — 나가는 UDP는 SLIRP이 아무 설정 없이 내보낸다(TS-M0 실측 2).
#
# TS-M2 결정 M2-F. 부팅 B가 이 시간과 비교된다 — "셸이 다른 부팅과 같은
# 시각에 뜬다"를 재려면 같은 방법으로 잰 상대가 있어야 한다.
BOOT_A_START="$(date +%s)"
qemu-system-x86_64 \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd ../kernel/initrd.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -netdev "user,id=n0" \
  -device virtio-net-pci,netdev=n0 \
  -drive file="${REPO_ROOT}/out/net-ntp.img",if=virtio,format=raw \
  -serial file:"$LOGA" \
  -monitor tcp:127.0.0.1:${NTP_MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID_A=$!

READY=0
for _ in $(seq 1 120); do
  if grep -a "terminal: screen>" "$LOGA" >/dev/null; then READY=1; break; fi
  if ! kill -0 "$QEMU_PID_A" 2>/dev/null; then break; fi
  sleep 1
done
BOOT_A_SECONDS=$(( $(date +%s) - BOOT_A_START ))
[ "$READY" = "1" ] || fail "the ntp guest never rendered a prompt"
echo "the ntp guest reached a prompt in ${BOOT_A_SECONDS}s"

# ── 검사 17: 설정이 읽혔고 ntp가 실효값인가 ───────────────────────────
# 검사 3과 같은 자리를 새 키에 대해 한 번 더 본다. 이것이 없으면 아래 둘이
# 실패했을 때 "디스크를 안 물었다"와 "코드가 틀렸다"가 안 갈린다.
if ! grep -aE "tars-init: config shell=.* net=dhcp ntp=${NTP_SERVER}" "$LOGA" >/dev/null; then
  fail "the ntp config disk did not reach init" "tars-init: config shell="
fi
echo "the guest read ntp=${NTP_SERVER} off the config disk"

# ── 검사 18: 우리 코드가 시계를 뛰었나 ────────────────────────────────
# 이 체인에서 우리 코드가 하는 일 전부가 이 한 줄이다. 숫자가 stub이 정한
# 값과 정확히 같아야 한다 — 그래야 "시계가 움직였다"가 아니라 "이 서버가
# 말한 값으로 움직였다"가 된다.
#
# 기다리는 이유. 자식은 dhcpcd가 리스를 받기 전에 태어나므로 첫 sendto가
# ENETUNREACH로 실패하고 재시도한다(sntp.zig의 MAX_TRIES). 즉 이 줄은 리스
# 뒤에 나오고, 그 대기가 검사 5와 같은 크기다.
STEPPED=0
for _ in $(seq 1 90); do
  if grep -a "tars-init: clock stepped to ${STUB_UNIX}" "$LOGA" >/dev/null; then
    STEPPED=1; break
  fi
  if ! kill -0 "$QEMU_PID_A" 2>/dev/null; then break; fi
  sleep 1
done
[ "$STEPPED" = "1" ] || fail "init never stepped the clock to ${STUB_UNIX}" \
  "tars-init: sntp" "tars-init: clock"
echo "init stepped the clock to ${STUB_UNIX}"

# ── 검사 19: 사람이 그것을 볼 수 있나 ─────────────────────────────────
# 검사 18과 같은 사실을 다른 자리에서 묻는다. 저쪽은 우리 코드가 자기 입으로
# 한 말이고 이쪽은 게스트의 date가 실제로 무엇을 찍는가다 — clock_settime이
# 성공을 돌려주고도 시계가 안 움직이는 경우가 갈린다.
#
# 화면 판정이 서려면 먼저 monitor에 붙어야 한다.
CONNECTED=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${NTP_MONITOR_PORT}"; then CONNECTED=1; break; fi
  sleep 0.5
done
[ "$CONNECTED" = "1" ] || fail "could not connect to the ntp guest's QEMU monitor" \
  "terminal: screen>"

# 판정 글자가 명령줄에 없어야 한다(NW-M3 실측 2). wait_for_screen은 마지막
# 프레임이 아니라 로그 전체의 screen> 줄을 보므로 친 명령의 에코도 화면이다.
# date를 그냥 치면 그 네 글자가 화면에 남고, 연도는 출력에만 생긴다 —
# 그래서 echo와 명령 치환으로 tsyear=NNNN을 만든다.
#
# -u가 중요하다(design 결정 7). TS-M3이 시간대를 넣으면 지역 시간의 연도가
# 12월 31일 밤에 한 해 어긋날 수 있고, 그러면 이 판정이 일 년에 몇 시간
# 흔들린다.
#
# 키 이름 셋이 이 저장소에서 처음 쓰인다 — +가 shift-equal, %가 shift-5,
# Y가 shift-y다. $( 와 ) 는 검사 10·12·14가 이미 쓰는 것과 같다.
echo "=== typing 'echo tsyear=\$(date -u +%Y)' ==="
type_keys e c h o spc t s y e a r equal \
  shift-4 shift-9 d a t e spc minus u spc shift-equal shift-5 shift-y shift-0 ret

if ! wait_for_screen "tsyear=${STUB_YEAR}"; then
  fail "the guest's clock does not show ${STUB_YEAR} on screen" "terminal: screen>"
fi
echo "the guest shows ${STUB_YEAR} — the render survived the jump too"

# ── 부팅 A를 끈다 ─────────────────────────────────────────────────────
echo "=== sending system_powerdown to the ntp guest ==="
echo "system_powerdown" >&3
sleep 0.3
exec 3<&-
exec 3>&-

GONE_A=0
for _ in $(seq 1 30); do
  if ! kill -0 "$QEMU_PID_A" 2>/dev/null; then GONE_A=1; break; fi
  sleep 1
done
[ "$GONE_A" = "1" ] || fail "the ntp guest did not switch itself off" \
  "tars-init: shutdown requested"

# SL-M2가 세운 것을 이 부팅에도 건다. 여기서 이 검사가 갖는 뜻이 앞의
# 부팅보다 하나 더 크다 — 이 게스트에는 SNTP 자식이 있었고, 그 자식은
# execve를 안 해서 부모의 SIGTERM 핸들러를 물려받을 뻔했다(TS-M1 plan
# 결정 M1-A). power.resetToDefault()를 지우면 여기가 빨간불이 된다.
if grep -a "grace period expired" "$LOGA" >/dev/null; then
  fail "something outlived SIGTERM in the ntp guest" "grace period expired"
fi

# stub을 보낸다. 여기서 명시적으로 죽이는 이유는 그것이 몇 번 답했는지를
# 사람이 보게 하기 위해서다(trap도 같은 일을 하지만 그때는 출력이 끝난 뒤다).
kill "$STUB_PID" 2>/dev/null || true
wait "$STUB_PID" 2>/dev/null || true
STUB_PID=""
echo "the sntp stub answered $(grep -ac 'sent 48 bytes' "$STUBLOG") request(s)"

# ══ 부팅 B: DHCP가 알려 준 서버를 쓴다 (TS-M2) ═════════════════════════
#
# 여기서부터 게스트가 또 새로 뜬다. 앞의 둘과 다른 것이 둘이다 — 디스크가
# out/net-ntp-dhcp.img(ntp=dhcp)이고, initrd에 /run/tars/ntp_servers가 미리
# 있다.
#
# 이 부팅이 증명하는 것이 둘이다.
#   1. init이 그 파일을 읽는다 — 로그가 심은 주소를 이름 대며 찍는다
#   2. 안 닿는 서버가 부팅을 안 막는다 — 셸이 부팅 A와 같은 시각에 뜬다
#
# 상대가 없는 것이 이 부팅의 설계다. stub은 바로 위에서 이미 죽였고 심은
# 주소는 어느 네트워크에도 없다. 그래서 자식은 서른 번을 다 쓰고 전원을 끄는
# 순간까지 살아 있다 — 그것이 TS-M1 결정 M1-A의 진짜 시험이다.
echo "=== booting again with ntp=dhcp and a planted ${NTP_DEAD_SERVER} ==="

build_ntp_initrd
echo "planted ${NTP_DEAD_SERVER} in /run/tars/ntp_servers of the boot-B initrd"

LOG="$LOGB"
BOOT_B_START="$(date +%s)"

qemu-system-x86_64 \
  -m "$GUEST_MEM" \
  -kernel ../kernel/build/arch/x86/boot/bzImage \
  -initrd "$INITRD_B" \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -netdev "user,id=n0" \
  -device virtio-net-pci,netdev=n0 \
  -drive file="${REPO_ROOT}/out/net-ntp-dhcp.img",if=virtio,format=raw \
  -serial file:"$LOGB" \
  -monitor tcp:127.0.0.1:${NTP_DHCP_MONITOR_PORT},server,nowait \
  -no-reboot &
QEMU_PID_B=$!

READY_B=0
for _ in $(seq 1 120); do
  if grep -a "terminal: screen>" "$LOGB" >/dev/null; then READY_B=1; break; fi
  if ! kill -0 "$QEMU_PID_B" 2>/dev/null; then break; fi
  sleep 1
done
BOOT_B_SECONDS=$(( $(date +%s) - BOOT_B_START ))
[ "$READY_B" = "1" ] || fail "the ntp=dhcp guest never rendered a prompt"
echo "the ntp=dhcp guest reached a prompt in ${BOOT_B_SECONDS}s"

# ── 검사 20: 설정이 읽혔고 ntp=dhcp인가 ───────────────────────────────
# 검사 17과 같은 자리를 다른 값에 대해 한 번 더 본다. 이것이 없으면 아래 둘이
# 실패했을 때 "엉뚱한 디스크를 물었다"와 "코드가 틀렸다"가 안 갈린다 — 세
# 디스크의 라벨을 서로 다르게 둔 것과 같은 이유다.
if ! grep -aE "tars-init: config shell=.* net=dhcp ntp=dhcp" "$LOGB" >/dev/null; then
  fail "the ntp=dhcp config disk did not reach init" "tars-init: config shell="
fi
echo "the guest read ntp=dhcp off the config disk"

# ── 검사 21: init이 심은 파일을 읽었나 ────────────────────────────────
# design 결정 4의 1번이다. 이 줄이 나오면 경로 넷 중 "파일 → init" 조각이
# 게이트 안에서 닫힌 것이고, 그 조각은 SLIRP가 option 42를 주든 안 주든 같은
# 코드다.
#
# 주소까지 함께 보는 것에 뜻이 있다. 만약 SLIRP가 option 42를 준다면 dhcpcd의
# hook이 우리가 심은 파일을 덮어쓰는데, 그때 이 검사가 그 사실을 알린다 —
# 주소가 10.0.2.x로 바뀌어 패턴이 안 맞기 때문이다.
#
# 기다리는 이유는 자식의 첫 일이 파일을 여는 것이 아니기 때문이다. fork 뒤에
# 시그널 정책을 되돌리고, 파일을 열고, 그 다음이 이 줄이다 — 부팅 A의 검사
# 18보다 훨씬 이르지만 0초는 아니다.
READ_FILE=0
for _ in $(seq 1 60); do
  if grep -a "tars-init: ntp server ${NTP_DEAD_SERVER} came from /run/tars/ntp_servers" \
       "$LOGB" >/dev/null; then
    READ_FILE=1; break
  fi
  if ! kill -0 "$QEMU_PID_B" 2>/dev/null; then break; fi
  sleep 1
done
[ "$READ_FILE" = "1" ] || \
  fail "init never read ${NTP_DEAD_SERVER} out of /run/tars/ntp_servers" \
    "tars-init: ntp" "tars-init: sntp"
echo "init read ${NTP_DEAD_SERVER} out of the planted /run/tars/ntp_servers"

# ── 검사 22: 안 닿는 서버가 부팅을 안 막았나 ──────────────────────────
# design 결정 3의 음성이다. 이 사이클이 못 박으려는 제약이 "네트워크가 꺼져
# 있거나 안 닿아도 부팅은 평소대로 끝난다"이고, 그 제약은 양성 검사로는 절대
# 안 보인다 — 시계가 맞는 것과 부팅이 안 막히는 것은 서로 다른 사실이다.
#
# 이 순간 게스트 안에서는 자식이 192.0.2.1에 몇 번째로 묻고 있다. 그 자식이
# 부모를 한 순간도 안 세웠다는 것을 두 수의 차이가 말한다.
#
# 이 검사가 못 보는 것도 적어 둔다 — 부팅 A와 B가 똑같이 늦어지면 차이가 0이라
# 초록이다. 그 고장은 이 검사가 아니라 체인 단독 시간이 본다.
BOOT_DELTA=$(( BOOT_B_SECONDS - BOOT_A_SECONDS ))
if [ "$BOOT_DELTA" -gt "$BOOT_DELTA_MAX" ]; then
  fail "the dead ntp server delayed the prompt by ${BOOT_DELTA}s (boot A ${BOOT_A_SECONDS}s, boot B ${BOOT_B_SECONDS}s)" \
    "tars-init: sntp" "tars-init: started console shell"
fi
echo "the dead ntp server cost ${BOOT_DELTA}s of boot time (limit ${BOOT_DELTA_MAX}s)"

# ── 부팅 B를 끈다 ─────────────────────────────────────────────────────
CONNECTED_B=0
for _ in $(seq 1 20); do
  if exec 3<>"/dev/tcp/127.0.0.1/${NTP_DHCP_MONITOR_PORT}"; then CONNECTED_B=1; break; fi
  sleep 0.5
done
[ "$CONNECTED_B" = "1" ] || \
  fail "could not connect to the ntp=dhcp guest's QEMU monitor" "terminal: screen>"

echo "=== sending system_powerdown to the ntp=dhcp guest ==="
echo "system_powerdown" >&3
sleep 0.3
exec 3<&-
exec 3>&-

GONE_B=0
for _ in $(seq 1 30); do
  if ! kill -0 "$QEMU_PID_B" 2>/dev/null; then GONE_B=1; break; fi
  sleep 1
done
[ "$GONE_B" = "1" ] || fail "the ntp=dhcp guest did not switch itself off" \
  "tars-init: shutdown requested"

# SL-M2가 세운 것. 이 부팅에서 이 검사가 셋 중 가장 크다 — 여기가 TS-M1 결정
# M1-A가 겨냥한 바로 그 상태다. 자식이 안 닿는 주소를 묻는 중이라 전원을 끄는
# 순간 분명히 살아 있고, power.resetToDefault()가 없으면 그 자식이 부모의
# SIGTERM 핸들러를 물려받아 안 죽는다. 그러면 reapAll()이 유예 3초를 다 쓰고
# `grace period expired`를 찍는다.
if grep -a "grace period expired" "$LOGB" >/dev/null; then
  fail "something outlived SIGTERM in the ntp=dhcp guest" "grace period expired"
fi
echo "nothing outlived SIGTERM — the sntp child took the default policy"

echo "PASS"
exit 0
