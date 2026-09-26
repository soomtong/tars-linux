# TD-M0 — chronyd를 들이기 전에 일곱을 잰다

> 이 plan을 실행하는 사람에게: 이 milestone은 코드를 한 줄도 안 고친다.
> 만드는 것은 `/tmp/td/` 아래의 측정 하네스뿐이고, 저장소에 들어가는 것은
> design 문서의 실측 절 하나와 이 plan이다. 그래서 TDD 구조가 아니다 — TS-M0 ·
> DC-M0의 plan과 같은 형식이다.

Goal: TD design의 "TD-M0 — 잰다"가 적은 일곱을 부팅 한 번으로 답해서, M1이
코드를 쓸 때 남은 미지수(로그 글자 · 폴링 줄 · stub의 비율 `r` · 싣는 라이브러리)를
없앤다.

Architecture: 저장소의 initrd를 그대로 빌드한 뒤, 컨테이너 안에서 chrony와
라이브러리 넷을 sysroot에 풀고 그것과 게스트 스크립트 하나를 gzip cpio 조각으로
묶어 initrd 뒤에 이어 붙인다(TS-M2 실측 16이 이 길을 증명했다). 같은 컨테이너에서
perl stub NTP 서버 둘(`r = 0` · `r = 500ppm`)을 배경으로 띄운다. 게스트의 콘솔
셸에 FIFO로 `tdm0-run` 한 단어를 치면 그 스크립트가 chronyd를 세 번 띄우고
끄면서 `TDM0-` 표지를 시리얼 로그에 찍는다.

Tech Stack: bash · perl(`IO::Socket::INET` · `Time::HiRes`) · chrony
4.6.1-3+deb13u2 · QEMU · 기존 빌드 스크립트 다섯(`kernel/build.sh` ·
`init/zig build` · `terminal/prepare.sh` · `kernel/make_initrd.sh` ·
`net/make_disk.sh`)

---

## 무엇을 재는가

| 측정 | 무엇 | design의 자리 | 어디서 |
|---|---|---|---|
| 1 | 새 라이브러리의 재귀 목록과 바이트 | 확인 4 · 결정 9 | Task 2 `frag.sh`의 `TDM0-FRAG` 줄 |
| 2 | `-d -u root`로 뜨는가, `/run/chrony`를 스스로 만드는가 | 결정 3 | 국면 A의 `ALIVE` |
| 3 | 흐르는 stub에 `makestep`으로 2031년까지 뛰는가, 몇 초 걸리나 | 결정 4 | 국면 A의 `STEPPED` |
| 4 | chronyd 로그 줄의 실제 글자 | M1의 게이트 판정 | 국면마다의 `LOG` |
| 5 | `r = 0`의 주파수 퍼짐, `r = 500ppm`의 수렴 시간 | 위험 1 · 결정 7 · 8 | 국면 A · B의 `TRACK` |
| 6 | SIGTERM부터 끝날 때까지의 시간과 driftfile 내용, 다음 기동이 그 값에서 출발하나 | 위험 3 · 결정 5 | 국면 B · C의 `EXIT` · `DRIFT` · 첫 `TRACK` |
| 7 | `/dev/console`이 어디인가 | 위험 2 | `CONSOLES` |

측정 7은 읽어서 이미 반쯤 답했다. 게이트와 실기의 cmdline이 둘 다 `console=ttyS0`
이다(`net/check.sh:426` · `boot/limine.conf:18`). 그래서 chronyd의 stderr는
시리얼로 가고 terminal의 화면(framebuffer)에는 갈 길이 없다고 본다. 게스트가
`/proc/consoles`로 그것을 확인한다.

## 왜 부팅을 한 번만 하나, 그리고 국면이 왜 셋인가

국면은 chronyd를 한 번 띄우고 끄는 단위다. 한 게스트 안에서 셋을 잇는다.

- 국면 A — 포트 123, `r = 0`, 60초. 첫 점프(측정 3)와 잡음의 바닥(측정 5의
  절반)을 본다. 시계를 2031년으로 뛰는 것이 이 국면이므로 맨 앞이어야 한다.
- 국면 B — 포트 1123, `r = 500ppm`, 90초. 일부러 빠른 서버를 상대로 주파수를
  배우는지 본다. 끝날 때 쓰는 driftfile이 국면 C의 입력이다.
- 국면 C — 포트 1123, 같은 driftfile, 20초. 첫 `TRACK`의 주파수가 국면 B의
  마지막 값에서 출발하면 결정 5가 선다.

stub 둘은 같은 순간에 같은 `STUB_UNIX`에서 출발하고 비율만 다르다. 그래서
국면 B로 넘어갈 때 두 서버의 차이는 그때까지 흐른 시간 × 500ppm뿐이다(수 분이면
100ms 안쪽). 국면 B의 chronyd가 그 차이를 `makestep`으로 뛸 수도 있다 — 그것도
기록할 사실이지 실패가 아니다.

`500ppm`은 출발점이다. 실제 수정 결정은 수십 ppm이지만 TCG의 잡음을 넘어야
판정이 선다. 국면 A의 퍼짐이 500ppm에 가까우면 M1 plan이 비율을 올린다.

## Task 0 — `/tmp/td/`를 만든다

호스트(macOS)에서 친다. 이 디렉터리가 컨테이너와 공유되는 유일한 자리이고,
컨테이너는 `--rm`이라 여기 밖의 것은 전부 사라진다.

- [ ] Step 1: 디렉터리를 비우고 만든다

```bash
rm -rf /tmp/td && mkdir -p /tmp/td && ls -la /tmp/td
```

기대: 비어 있다. 옛 로그가 남아 있으면 이번 회차가 아무것도 안 써도 grep이
초록으로 나온다.

- [ ] Step 2: OrbStack이 켜져 있는지 본다

```bash
orb status
```

기대: `Running`. `Stopped`면 `orb start`. 꺼져 있으면 `docker.sock`이 없다고
즉시 끝난다(HANDOFF의 경고).

## Task 1 — 흐르는 stub NTP 서버를 쓴다

- [ ] Step 1: `/tmp/td/stub.pl`을 만든다

```perl
#!/usr/bin/perl
# TD-M0의 상대. 컨테이너 안에서 배경으로 돌면서 UDP 한 포트를 듣는다.
#
# net/sntp_stub.pl과 다른 점이 둘이다(TD design 결정 7).
#   1. 시계가 흐른다. 답하는 시각이 STUB_UNIX + (지금 - 시작) × (1 + r)이다.
#      멈춘 시계를 상대로 chrony는 엉뚱한 주파수를 배운다.
#   2. receive와 transmit을 따로 잰다. chrony는 둘이 같아도 받지만, 서버
#      안에서 흐른 시간이 0이라고 믿게 된다.
#
# 인자: 포트 · 출발 시각(unix) · r(ppm) · 라벨
use strict;
use warnings;
use IO::Socket::INET;
use Socket;
use Time::HiRes qw(time);

$| = 1;

my $port  = $ARGV[0] // 123;
my $base  = $ARGV[1] // 1930367167;    # 2031-03-04T05:06:07Z
my $ppm   = $ARGV[2] // 0;
my $label = $ARGV[3] // "stub";

my $NTP_EPOCH = 2208988800;
my $start = time();
my $rate  = 1 + $ppm / 1e6;

sub now_ntp {
    my $t = $base + (time() - $start) * $rate + $NTP_EPOCH;
    my $sec = int($t);
    my $frac = int(($t - $sec) * 4294967296);
    return pack('NN', $sec, $frac);
}

my $sock = IO::Socket::INET->new(
    LocalAddr => '0.0.0.0',
    LocalPort => $port,
    Proto     => 'udp',
) or die "TDM0-STUB $label: cannot bind udp/$port: $!\n";

printf "TDM0-STUB %s: listening on udp/%d, base %d, r=%s ppm\n",
    $label, $port, $base, $ppm;

# 시작 때의 시각을 reference timestamp로 쓴다. 0이면 chrony가 "서버가 한 번도
# 동기화된 적 없다"로 읽는다.
my $ref = now_ntp();
my $count = 0;

while (1) {
    my $req;
    my $from = recv($sock, $req, 512, 0);
    next unless defined $from;
    my $rx = now_ntp();
    my ($fport, $faddr) = sockaddr_in($from);
    my $len = length($req);
    if ($len < 48) {
        printf "TDM0-STUB %s: ignoring %d bytes\n", $label, $len;
        next;
    }
    # 요청의 transmit(40-47)을 originate(24-31)로 되돌린다. chrony의 test B다.
    my $orig = substr($req, 40, 8);
    # LI 0 · VN 4 · mode 4 → 0x24. stratum 1 · poll 요청값 그대로 · precision -20.
    my $poll = unpack('c', substr($req, 2, 1));
    my $reply = pack('CCcc', 0x24, 1, $poll, -20)
              . pack('NN', 0, 0)      # root delay · root dispersion
              . 'TARS'
              . $ref . $orig . $rx . now_ntp();
    send($sock, $reply, 0, $from);
    $count++;
    # 매번 찍으면 0.25초 폴링에서 로그가 수천 줄이 된다. 첫 다섯과 이후 100번마다.
    if ($count <= 5 || $count % 100 == 0) {
        printf "TDM0-STUB %s: answer #%d to %s:%d (poll %d)\n",
            $label, $count, inet_ntoa($faddr), $fport, $poll;
    }
}
```

- [ ] Step 2: 문법을 본다

```bash
docker run --rm -v /tmp/td:/tmp/td tars-devcontainer perl -c /tmp/td/stub.pl
```

기대: `/tmp/td/stub.pl syntax OK`. 하네스 안에서 배경으로 죽으면 증상이
"chronyd가 아무 서버에도 못 붙는다"이고, 그것은 측정 2가 실패한 것과 똑같이
생겼다.

## Task 2 — cpio 조각을 만드는 스크립트를 쓴다

- [ ] Step 1: `/tmp/td/frag.sh`를 만든다

```bash
#!/usr/bin/env bash
# TD-M0 측정 1. 컨테이너 안에서 돈다(--rm이라 sysroot를 고쳐도 남지 않는다).
#
# chrony와 그 라이브러리를 sysroot에 풀고, 재귀 DT_NEEDED를 따라가 조각
# 디렉터리에 담는다. 이미 저장소 initrd에 있는 라이브러리는 담지 않고 이름만
# 센다 — 그래야 "새로 드는 바이트"가 나온다.
#
# 해석 규칙은 kernel/make_initrd.sh의 find_in_sysroot · copy_lib_deps와 같다
# (readelf로 읽고, initrd 안의 자리는 /lib/x86_64-linux-gnu로 고정).
set -euo pipefail
cd /workspace

S=/usr/local/amd64-sysroot
DEBS=/tmp/td/debs
FRAG=/tmp/td/frag
LIB_DEST=lib/x86_64-linux-gnu
rm -rf "$DEBS" "$FRAG"
mkdir -p "$DEBS" "$FRAG/usr/bin" "$FRAG/$LIB_DEST"

apt-get update -qq >/dev/null 2>&1
(cd "$DEBS" && apt-get download \
  chrony:amd64 libseccomp2:amd64 libedit2:amd64 libbsd0:amd64 libmd0:amd64 \
  >/dev/null)
for deb in "$DEBS"/*.deb; do
  echo "TDM0-FRAG deb $(basename "$deb") $(stat -c %s "$deb")"
  dpkg -x "$deb" "$S"
done

# 저장소 initrd에 이미 있는 라이브러리 이름들.
zcat kernel/initrd.cpio | cpio -t 2>/dev/null \
  | sed -n "s|^\./\?${LIB_DEST}/||p" | sort -u > /tmp/td/initrd-libs.txt
echo "TDM0-FRAG initrd already has $(wc -l < /tmp/td/initrd-libs.txt) libraries"

find_in_sysroot() {
  local d
  for d in /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu; do
    [ -e "$S$d/$1" ] && { echo "$S$d/$1"; return 0; }
  done
  return 1
}

walk() {
  local bin="$1" so src
  for so in $(readelf -d "$bin" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
    case "$so" in ld-linux*) continue ;; esac
    [ -e "$FRAG/$LIB_DEST/$so" ] && continue
    if grep -qx "$so" /tmp/td/initrd-libs.txt; then
      echo "TDM0-FRAG have $so (needed by $(basename "$bin"))"
      continue
    fi
    src="$(find_in_sysroot "$so")" || { echo "TDM0-FRAG MISSING $so (needed by $(basename "$bin"))"; exit 1; }
    cp -L "$src" "$FRAG/$LIB_DEST/$so"
    echo "TDM0-FRAG new $so $(stat -c %s "$FRAG/$LIB_DEST/$so") (needed by $(basename "$bin"))"
    walk "$src"
  done
}

cp "$S/usr/sbin/chronyd" "$FRAG/usr/bin/chronyd"
cp "$S/usr/bin/chronyc" "$FRAG/usr/bin/chronyc"
walk "$FRAG/usr/bin/chronyd"
walk "$FRAG/usr/bin/chronyc"

cp /tmp/td/tdm0-run "$FRAG/usr/bin/tdm0-run"
chmod 755 "$FRAG/usr/bin/"*

echo "TDM0-FRAG bin chronyd $(stat -c %s "$FRAG/usr/bin/chronyd")"
echo "TDM0-FRAG bin chronyc $(stat -c %s "$FRAG/usr/bin/chronyc")"
echo "TDM0-FRAG libs total $(du -cb "$FRAG/$LIB_DEST"/* | tail -1 | cut -f1)"

(cd "$FRAG" && find . | cpio -o -H newc 2>/dev/null) | gzip -6 > /tmp/td/frag.cpio.gz
echo "TDM0-FRAG fragment gz $(stat -c %s /tmp/td/frag.cpio.gz)"
cat kernel/initrd.cpio /tmp/td/frag.cpio.gz > /tmp/td/initrd-td.cpio
echo "TDM0-FRAG initrd $(stat -c %s kernel/initrd.cpio) -> $(stat -c %s /tmp/td/initrd-td.cpio)"
```

기대 모양: `new libseccomp.so.2` · `new libedit.so.2` · `new libbsd.so.0` ·
`new libmd.so.0` 넷, 나머지는 `have`. `MISSING`이 나오면 그 라이브러리의
패키지를 `apt-get download` 줄에 더하고 다시 돈다 — 그 사실도 실측이다.

## Task 3 — 게스트 쪽 스크립트를 쓴다

- [ ] Step 1: `/tmp/td/tdm0-run`을 만든다

```bash
#!/usr/bin/bash
# TD-M0의 게스트 쪽 절반. 콘솔 셸에서 `tdm0-run` 한 단어로 부른다.
#
# 명령을 FIFO로 하나씩 치지 않고 initrd 안의 스크립트로 두는 이유는 TQ-M1
# plan Task 4와 같다 — fish → bash로 따옴표를 두 번 넘기면 `$`와 `\`가
# 어디서 죽는지 추적하는 데 측정보다 시간이 더 든다.
#
# 시각은 전부 /proc/uptime으로 적는다. 벽시계는 이 스크립트가 도는 동안
# 2031년으로 뛰므로 경과 시간을 재는 데 못 쓴다.
set -u
W=/run/tdm0
mkdir -p "$W"

up() { cut -d' ' -f1 /proc/uptime; }
mark() { echo "TDM0-$1 up=$(up) $2"; }

mark CONSOLES "$(tr '\n' ';' < /proc/consoles)"
mark CLOCK0 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mark RUNCHRONY-BEFORE "$(ls -ld /run/chrony 2>&1)"

# phase <이름> <stub 포트> <driftfile> <초>
phase() {
  local name=$1 port=$2 drift=$3 secs=$4 pid i y stepped="" t0 rc
  printf 'server 10.0.2.2 port %s iburst minpoll -2 maxpoll -2\nmakestep 1 3\ndriftfile %s\n' \
    "$port" "$drift" > "$W/$name.conf"
  mark "$name-START" "port=$port drift=$drift driftfile-before=$(cat "$drift" 2>/dev/null || echo none)"

  # design 결정 3의 모양 그대로. stderr는 파일로 받아 끝에 표지를 붙여 찍는다 —
  # 파이프로 받으면 $!가 chronyd가 아니라 파이프의 끝이 된다.
  /usr/bin/chronyd -d -u root -f "$W/$name.conf" > "$W/$name.log" 2>&1 &
  pid=$!
  sleep 1
  mark "$name-ALIVE" "pid=$pid alive=$(kill -0 "$pid" 2>/dev/null && echo yes || echo no) run-chrony=[$(ls -ld /run/chrony 2>&1)]"

  for ((i = 0; i < secs; i += 2)); do
    y=$(date -u +%Y)
    if [ -z "$stepped" ] && [ "$y" = 2031 ]; then
      stepped=1
      mark "$name-STEPPED" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fi
    # -c는 쉼표로 가른 한 줄이다. 필드 순서는 chronyc 문서의 tracking 절 —
    # refid · 이름 · stratum · ref time · system time · last offset · rms offset ·
    # frequency · residual freq · skew · root delay · root dispersion ·
    # update interval · leap.
    mark "$name-TRACK" "$(chronyc -n -c tracking 2>&1 | tr '\n' ' ')"
    sleep 2
  done
  mark "$name-SOURCES" "$(chronyc -n -c sources 2>&1 | tr '\n' ' ')"

  t0=$(up)
  kill -TERM "$pid"
  wait "$pid"
  rc=$?
  mark "$name-EXIT" "rc=$rc term-at=$t0"
  mark "$name-DRIFT" "$(cat "$drift" 2>&1 | tr '\n' ' ')"
  sed "s/^/TDM0-$name-LOG /" "$W/$name.log"
}

phase A 123  /run/tdm0/drift-a 60
phase B 1123 /run/tdm0/drift-b 90
phase C 1123 /run/tdm0/drift-b 20
mark DONE "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

국면 C가 국면 B와 같은 driftfile을 쓰는 것이 이 스크립트의 요점이다. C의
`START` 줄이 B가 남긴 파일을 찍고, C의 첫 `TRACK`이 그 값에서 출발하는지 본다.

## Task 4 — 하네스를 쓴다

- [ ] Step 1: `/tmp/td/guest.sh`를 만든다

```bash
#!/usr/bin/env bash
# TD-M0. 컨테이너 안에서 돈다. 빌드 → 조각 → stub 둘 → 게스트 → tdm0-run.
set -uo pipefail
cd /workspace

LOG=/tmp/td/guest.log
FIFO=/tmp/td/guest.fifo
BASE=1930367167          # 2031-03-04T05:06:07Z. net/check.sh의 STUB_UNIX와 같다
rm -f "$LOG" "$FIFO" /tmp/td/stub-*.log
mkfifo "$FIFO"

(cd kernel && ./build.sh)       || { echo "TDM0: kernel build failed"; exit 1; }
(cd init && zig build)          || { echo "TDM0: init build failed"; exit 1; }
(cd terminal && ./prepare.sh)   || { echo "TDM0: terminal build failed"; exit 1; }
(cd kernel && ./make_initrd.sh) || { echo "TDM0: initrd build failed"; exit 1; }
(cd net && ./make_disk.sh)      || { echo "TDM0: config disk build failed"; exit 1; }
bash /tmp/td/frag.sh            || { echo "TDM0: fragment failed"; exit 1; }

# stub 둘을 같은 순간에 띄운다. 둘의 출발 시각이 같아야 국면 B로 넘어갈 때의
# 차이가 비율에서만 나온다.
perl /tmp/td/stub.pl 123  "$BASE" 0   flat > /tmp/td/stub-flat.log 2>&1 & FLAT=$!
perl /tmp/td/stub.pl 1123 "$BASE" 500 fast > /tmp/td/stub-fast.log 2>&1 & FAST=$!
sleep 1
for p in $FLAT $FAST; do
  kill -0 "$p" 2>/dev/null || { echo "TDM0: a stub died"; cat /tmp/td/stub-*.log; exit 1; }
done
echo "TDM0: stubs up"

exec 4<>"$FIFO"

# out/net.img는 net=dhcp 한 줄이다. ntp가 기본값 off라 우리 SNTP 자식이 안
# 뜨고, 시계를 만지는 것은 chronyd 하나다.
qemu-system-x86_64 \
  -m 512 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd /tmp/td/initrd-td.cpio \
  -append "console=ttyS0" \
  -vga none \
  -device virtio-gpu-pci \
  -display none \
  -netdev "user,id=n0" \
  -device virtio-net-pci,netdev=n0 \
  -drive file=out/net.img,if=virtio,format=raw \
  -serial stdio \
  -monitor none \
  -no-reboot \
  < "$FIFO" > "$LOG" 2>&1 &
QEMU=$!

cleanup() {
  kill "$QEMU" "$FLAT" "$FAST" 2>/dev/null
  wait 2>/dev/null
  exec 4>&-
  rm -f "$FIFO"
}
trap cleanup EXIT

WAITED=0
until grep -aq "started console shell" "$LOG" 2>/dev/null; do
  sleep 1; WAITED=$((WAITED + 1))
  [ "$WAITED" -ge 120 ] && { echo "TDM0: console shell never started"; tail -40 "$LOG"; exit 1; }
done
echo "TDM0: console shell up after ${WAITED}s"

# dhcpcd의 리스를 기다린다(NW-M2 실측 17). chronyd는 주소가 없어도 다시
# 묻지만, 국면 A의 60초를 리스 대기로 쓰지 않게 한다.
sleep 8

printf 'tdm0-run\n' >&4

# 국면 셋이 170초에 기동 · 종료가 더해진다.
WAITED=0
until grep -aq "TDM0-DONE up=" "$LOG" 2>/dev/null; do
  sleep 2; WAITED=$((WAITED + 2))
  [ "$WAITED" -ge 400 ] && { echo "TDM0: tdm0-run never finished"; break; }
done
echo "TDM0: tdm0-run took about ${WAITED}s"
echo "=== done ==="
```

`TDM0-DONE up=`로 기다리는 이유. 우리가 친 명령의 에코는 `tdm0-run`이고
`DONE`이 없다. 하지만 `TDM0-DONE`만 보면 스크립트 본문을 누가 cat하는 순간
초록이 된다 — `up=` 뒤는 출력에만 생긴다(`project_gate_screen_echo`).

- [ ] Step 2: 실행 권한을 준다

```bash
chmod +x /tmp/td/guest.sh /tmp/td/frag.sh /tmp/td/tdm0-run /tmp/td/stub.pl
```

`tdm0-run`의 권한은 조각 안에서 `chmod 755`로 다시 주지만, 호스트 쪽도 맞춰 둔다.

## Task 5 — 하네스를 돌린다

- [ ] Step 1: 돌린다 (약 5~6분)

빌드가 최신이면 부팅 약 40초 · 조각 약 30초(apt) · 국면 셋 약 3분 30초다.

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/td:/tmp/td \
  -w /workspace tars-devcontainer bash /tmp/td/guest.sh > /tmp/td/run.log 2>&1
echo "exit=$?"
```

- [ ] Step 2: 측정 1 — 조각을 본다

```bash
grep -a "^TDM0-FRAG\|^TDM0:" /tmp/td/run.log
```

적을 것: 새 라이브러리의 이름과 바이트, `have`로 넘어간 것, 조각의 gz 크기,
initrd가 몇 바이트 늘었나.

- [ ] Step 3: stub이 답했는지 본다

```bash
cat /tmp/td/stub-flat.log /tmp/td/stub-fast.log
```

기대: 둘 다 `answer #1`부터 있고, 폴링 −2(0.25초)면 국면 하나에 수백 번이다.
`answer` 줄이 없으면 chronyd가 서버에 못 닿은 것이고, 측정 2의 `ALIVE`와
`LOG`를 먼저 본다.

- [ ] Step 4: 표지를 뽑는다

```bash
grep -aoE "TDM0-[A-Z]+(-[A-Z]+)? up=[0-9.]+ [^|]*" /tmp/td/guest.log \
  | grep -v "screen>" > /tmp/td/marks.txt
wc -l /tmp/td/marks.txt
grep -E "^TDM0-(CONSOLES|CLOCK0|RUNCHRONY|DONE|[ABC]-(START|ALIVE|STEPPED|EXIT|DRIFT|SOURCES))" /tmp/td/marks.txt
```

- [ ] Step 5: 주파수의 흐름을 본다 (측정 5)

```bash
for p in A B C; do
  echo "== $p"
  grep "^TDM0-$p-TRACK" /tmp/td/marks.txt | awk -F'up=' '{print $2}' \
    | awk -F, '{split($1,u," "); printf "up=%s sys=%s freq=%s skew=%s leap=%s\n", u[1], $5, $8, $10, $14}'
done
```

`$8`이 frequency(ppm)다. `chronyc -c`는 부호로 방향을 말한다 — 어느 부호가
"빠르다"인지를 국면 B에서 읽어 적는다.

- [ ] Step 6: chronyd 로그 줄을 본다 (측정 4)

```bash
grep -a "TDM0-[ABC]-LOG" /tmp/td/guest.log | grep -v "screen>" | sed 's/\r$//'
```

M1의 게이트가 grep할 후보를 고른다. 점프를 말하는 줄(`System clock wrong by`
· `System clock was stepped` 같은 것), 서버를 고른 줄(`Selected source`),
driftfile을 읽은 줄이 있는지.

## Task 6 — 읽는 법과 판단

| 표지 | 초록의 모양 | 다른 값이 뜻하는 것 |
|---|---|---|
| `CONSOLES` | `ttyS0` 하나 | `tty0`이 있으면 위험 2가 산다. M1이 stderr를 어디로 보낼지 다시 정한다 |
| `RUNCHRONY-BEFORE` | 없다 | 있으면 initrd의 무엇이 이미 만든 것이다 |
| `A-ALIVE` | `alive=yes`, `/run/chrony`가 생겼다 | `alive=no`면 `A-LOG`가 이유를 말한다(권한 · 라이브러리 · 설정). 설정이 이유이고 `minpoll -2`를 탓하면 `tdm0-run`의 폴링을 `0`으로 바꿔 다시 돈다 |
| `A-STEPPED` | 국면 A의 앞 몇 초 안 | 없으면 `makestep`이 안 먹었거나 서버를 안 믿는 것이다 |
| `A-TRACK`의 freq | 0 근처에서 작게 흔들림 | 흔들림의 폭이 위험 1의 답이다 |
| `B-TRACK`의 freq | 500 근처로 수렴 | 수렴하는 데 걸린 `up=` 차이가 M2 판정의 대기 시간이 된다 |
| `B-EXIT` | `rc=0`, `up`과 `term-at`의 차이가 짧다 | 3초에 가까우면 위험 3이 산다 |
| `B-DRIFT` | 두 수(주파수 · skew) | 비어 있으면 SIGTERM에 안 쓴 것이다 — 결정 5가 흔들린다 |
| `C-START` | `driftfile-before=`가 B의 값 | `none`이면 B가 파일을 안 남겼다 |
| `C-TRACK`의 첫 freq | B의 마지막 값 근처 | 0이면 driftfile을 안 읽었다 |

- [ ] Step 1: 멈출 자리를 판단한다

`A-ALIVE`가 `no`이고 로그가 라이브러리나 커널 기능(seccomp · capability)을
말하면 여기서 멈추고 사용자에게 보고한다. design 결정 3이 흔들린 것이고, 고치는
길이 커널 config를 여는 것이면 범위가 바뀐다.

`B-TRACK`이 90초 안에 500 근처에 안 오면 멈추지 않는다. 국면 B를 180초로 늘려
한 번 더 돌리고, 그래도 안 오면 그 사실을 실측으로 적는다 — M2의 판정 모양이
바뀔 뿐 교체(M1)를 막지는 않는다.

## Task 7 — design에 실측을 적고 커밋한다

- [ ] Step 1: design에 절을 더한다

`docs/superpowers/specs/2026-09-26-tars-time-discipline-design.md`의
"## 마일스톤" 바로 앞에 `## TD-M0이 실행으로 증명한 것`을 더한다. 실측 1부터
번호를 매기고, 각 실측은 "무엇을 했고 무엇이 나왔고 그래서 무엇이 정해졌나"를
적는다. 숫자는 로그에서 그대로 옮긴다.

적을 것이 최소 일곱이다 — 측정 1~7 각각 하나씩. plan에 없던 것이 나오면 그것도
실측이다. 그리고 M1 plan이 가져다 쓸 넷을 실측 끝에 따로 모은다.

1. 싣는 라이브러리 목록과 initrd 증가량
2. 게이트가 grep할 chronyd 로그 줄
3. `r`의 값과 수렴 대기 시간
4. `/config/chrony.d/gate.conf`에 적을 폴링 줄

- [ ] Step 2: 위험 절을 고친다

닫힌 위험에는 `TD-M0이 닫았다(실측 N).`, 현실이 된 위험에는 `⚠ 현실이
됐다(실측 N).`과 그래서 무엇이 바뀌었는지를 적는다.

- [ ] Step 3: 더한 줄과 지운 줄을 따로 센다

```bash
git diff --stat
git diff | grep '^-' | grep -v '^---'
```

design 문서만 바뀌어야 한다. 소스가 하나라도 걸리면 이 milestone의 전제가
깨진 것이다. 지운 줄은 의도한 것인지 읽는다.

- [ ] Step 4: 커밋한다

```bash
git add docs/superpowers/specs/2026-09-26-tars-time-discipline-design.md
git commit -m "Measure chronyd in the guest before it replaces our SNTP"
```

## 이 milestone이 끝난 자리

- `/tmp/td/`의 하네스 넷(`stub.pl` · `frag.sh` · `tdm0-run` · `guest.sh`)과
  로그들. 호스트 `/tmp`라 언젠가 사라지고, 다시 필요하면 이 plan의 Task 1~4에
  전문이 글자 그대로 있다.
- design에 실측 절 하나와 위험 절의 정정.
- 저장소의 코드 파일은 한 글자도 안 바뀐다.

끝 기준: 측정 일곱이 design에 실측으로 적혔고, M1 plan이 가져다 쓸 넷이
정해졌다.
