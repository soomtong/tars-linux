# TS-M0 — 시계에 손대기 전에 여섯을 잰다

> 이 plan을 실행하는 사람에게: 이 milestone은 코드를 한 줄도 안 고친다.
> 만드는 것은 `/tmp/ts/` 아래의 측정 하네스뿐이고 저장소에 들어가는 것은
> design 문서의 실측 절 하나다. 그래서 TDD 구조가 아니다 — NW-M0 · IN-M0의
> plan과 같은 형식이다.

Goal: TS design의 위험 1~4와 7을 부팅 한 번과 컨테이너 명령 몇 줄로 답해서,
TS-M1이 코드를 쓸 때 남아 있는 미지수를 없앤다.

Architecture: 컨테이너 안에서 perl stub SNTP 서버를 배경으로 띄우고, 같은
컨테이너에서 QEMU를 띄워 게스트의 콘솔 셸에 FIFO로 명령을 넣는다. 게스트는
bash의 `/dev/udp`로 그 stub에 datagram을 보내고 답을 읽는다. 컨테이너 쪽
관찰(stub 로그)과 게스트 쪽 관찰(시리얼 로그)을 따로 남겨서, 못 닿았을 때
"안 보냈다" · "안 갔다" · "답이 안 왔다"가 갈리게 한다.

Tech Stack: bash · perl(`IO::Socket::INET` · `Time::Local`) · QEMU 10.0.11 ·
기존 빌드 스크립트 다섯(`kernel/build.sh` · `init/zig build` ·
`terminal/prepare.sh` · `kernel/make_initrd.sh` · `net/make_disk.sh`)

---

## 무엇을 재는가

design의 "TS-M0 — 잰다"가 여섯을 적었다. 이 plan이 그것을 Task에 배치한다.

| 측정 | 무엇 | 어느 위험 | 어디서 |
|---|---|---|---|
| 1 | SLIRP가 `10.0.2.2`로 가는 UDP를 컨테이너에 넘기는가 | 위험 1 | Task 3의 probe A·B |
| 2 | 지금 게스트의 벽시계가 무엇을 가리키는가 | 확인 1 | Task 3의 probe CLOCK |
| 3 | perl stub이 UDP 123을 열 수 있는가 | 위험 4 | Task 2 |
| 4 | dhcpcd가 option 42를 요청 목록에 넣는가 | 위험 3 | Task 5 |
| 5 | 시계를 뛴 뒤 게스트가 그대로 도는가 | 위험 2 · 7 | Task 3의 probe AFTER |
| 6 | 게스트에서 벽시계를 실제로 뛸 수 있는가 | — | Task 3의 probe STEP |

측정 1에 probe가 셋인 이유가 있다. probe A는 평문 한 줄로 왕복만 보고, probe
B는 진짜 48바이트 SNTP 요청으로 같은 왕복을 본다 — 둘을 가르는 이유는 SLIRP가
길이나 내용에 따라 다르게 굴 이유가 없다고 믿고 있지만 그것을 안 쟀기
때문이다. probe C는 상대를 `10.0.2.2` 대신 컨테이너 자신의 IP로 바꾼다.
A·B가 죽고 C가 살면 처방이 "stub의 자리를 옮긴다"가 되어 design을 덜 고친다.

## 왜 부팅을 한 번만 하나

여섯 중 다섯이 한 게스트 안에서 순서만 지키면 다 답해진다. 순서에 제약이
하나 있다 — probe CLOCK은 probe STEP보다 먼저여야 한다. 시계를 한 번 뛰면
"원래 무엇이었나"를 다시 볼 수 없다.

그리고 probe STEP 뒤에 probe A를 한 번 더 돌린다. 시계를 뛴 뒤에도 네트워크가
그대로 도는지가 위험 2의 일부이기 때문이다.

## Task 0 — `/tmp/ts/`를 만든다

호스트(macOS)에서 친다. 이 디렉터리가 컨테이너와 공유되는 유일한 자리이고,
컨테이너는 `--rm`이라 여기 밖의 것은 전부 사라진다.

- [ ] Step 1: 디렉터리를 만든다

```bash
mkdir -p /tmp/ts
```

- [ ] Step 2: 비어 있는 것을 확인한다

```bash
ls -la /tmp/ts
```

기대: 이전 세션의 찌꺼기가 없다. 있으면 `rm -f /tmp/ts/*`로 지운다 — 옛
로그가 남아 있으면 이번 회차가 아무것도 안 써도 grep이 초록으로 나온다.

## Task 1 — perl stub SNTP 서버를 쓴다

- [ ] Step 1: `/tmp/ts/stub.pl`을 만든다

호스트에서 이 내용 그대로 쓴다.

```perl
#!/usr/bin/perl
# TS-M0의 상대. 컨테이너 안에서 배경으로 돌면서 UDP 한 포트를 듣는다.
#
# 두 가지로 답한다.
#   48바이트가 오면  → 진짜 SNTP 서버 응답 48바이트 (design 결정 6)
#   그 밖            → "tsm0-pong\n" 한 줄
#
# 둘로 가르는 이유는 probe A(평문)와 probe B(48바이트)가 같은 stub을 쓰기
# 때문이다. 평문에 SNTP로 답하면 게스트의 `read -r -t`가 줄 끝을 못 찾아서
# 타임아웃과 구별이 안 된다.
#
# 받은 것을 전부 한 줄씩 찍는다. 이 로그가 "게스트가 보낸 것이 여기까지
# 왔는가"의 유일한 증거다 — 게스트 쪽 로그만으로는 "안 보냈다"와
# "갔는데 답이 안 왔다"가 안 갈린다.
use strict;
use warnings;
use IO::Socket::INET;
use Socket;    # sockaddr_in·inet_ntoa. IO::Socket::INET은 이것을 자기
               # 네임스페이스로만 들여오므로 여기서 따로 써야 한다.
use Time::Local qw(timegm);

$| = 1;    # 배경으로 돌므로 버퍼를 안 쌓는다. 안 하면 로그가 끝에 몰린다.

my $port = $ARGV[0] // 123;

# design 결정 6. CMOS로도 커널로도 나올 수 없는 값이어야 하고, 과거가 아니라
# 미래여야 한다(위험 2 — 과거로 뛰면 게이트가 만든 파일의 mtime이 뒤집힌다).
# timegm의 인자는 (초, 분, 시, 일, 0부터 세는 달, 연)이다.
my $FIXED_UNIX = timegm(7, 6, 5, 4, 2, 2031);    # 2031-03-04T05:06:07Z = 1930367167

# NTP의 초는 1970이 아니라 1900부터 센다(design 결정 11).
my $NTP_EPOCH = 2208988800;

my $sock = IO::Socket::INET->new(
    LocalAddr => '0.0.0.0',
    LocalPort => $port,
    Proto     => 'udp',
) or die "TSM0-STUB: cannot bind udp/$port: $!\n";

printf "TSM0-STUB: listening on udp/%d, will answer %s (unix %d)\n",
    $port, scalar(gmtime($FIXED_UNIX)), $FIXED_UNIX;

while (1) {
    my $req;
    # 메서드가 아니라 내장 함수 꼴로 부른다. IO::Socket에는 recv 메서드가
    # 없어서 메서드 꼴은 버전에 따라 조용히 안 돈다.
    my $from = recv($sock, $req, 512, 0);
    unless (defined $from) {
        print "TSM0-STUB: recv failed: $!\n";
        next;
    }
    my ($fport, $faddr) = sockaddr_in($from);
    my $fip = inet_ntoa($faddr);
    my $len = length($req);
    my $first = $len ? sprintf("0x%02x", ord(substr($req, 0, 1))) : "n/a";
    printf "TSM0-STUB: recv %d bytes from %s:%d first=%s\n",
        $len, $fip, $fport, $first;

    my $reply;
    if ($len == 48) {
        # RFC 4330의 서버 응답. 바이트 배치는 이렇다.
        #   0      LI(0) VN(4) Mode(4)      → 0x24
        #   1      stratum 1 (primary)
        #   2      poll 4
        #   3      precision -6 (부호 있는 바이트)
        #   4-7    root delay 0
        #   8-11   root dispersion 0
        #   12-15  reference ID
        #   16-23  reference timestamp
        #   24-31  originate timestamp  ← 요청의 transmit timestamp를 그대로
        #   32-39  receive timestamp
        #   40-47  transmit timestamp
        #
        # 24-31을 요청에서 그대로 베끼는 것이 design 결정 12의 마지막 줄이
        # 보려는 것이다. M1의 parseReply가 이 자리를 자기 nonce와 대조한다.
        my $orig = substr($req, 40, 8);
        my $ts = pack('NN', $FIXED_UNIX + $NTP_EPOCH, 0);
        # 템플릿이 CCCc다. 넷째가 부호 있는 바이트(precision -6)이고 앞의
        # 셋이 부호 없는 것이다. CCcC로 쓰면 결과 바이트는 두 보수라 같지만
        # perl이 `Character in 'C' format wrapped`를 찍는다 — Task 1 Step 3의
        # self-test가 이것을 잡았다.
        $reply = pack('CCCc', 0x24, 1, 4, -6)
               . pack('NN', 0, 0)
               . 'TSM0'
               . $ts . $orig . $ts . $ts;
        printf "TSM0-STUB: sent 48 bytes of SNTP (origin echoed)\n";
    } else {
        $reply = "tsm0-pong\n";
        printf "TSM0-STUB: sent %d bytes of text\n", length($reply);
    }
    send($sock, $reply, 0, $from) or print "TSM0-STUB: send failed: $!\n";
}
```

- [ ] Step 2: 문법을 먼저 본다

```bash
docker run --rm -v /tmp/ts:/tmp/ts tars-devcontainer perl -c /tmp/ts/stub.pl
```

기대: `/tmp/ts/stub.pl syntax OK`

문법 에러가 있으면 여기서 잡는다. 하네스 안에서 배경으로 죽으면 증상이
"probe가 전부 타임아웃"이고 그것은 위험 1이 현실이 된 것과 똑같이 생겼다.

- [ ] Step 3: 측정 3 — UDP 123을 실제로 열어 본다

```bash
docker run --rm -v /tmp/ts:/tmp/ts tars-devcontainer bash -c '
  perl /tmp/ts/stub.pl 123 & STUB=$!
  sleep 1
  if kill -0 $STUB 2>/dev/null; then echo "TSM0: stub is alive on 123"; else echo "TSM0: stub died"; fi
  perl -MIO::Socket::INET -e "
    my \$s = IO::Socket::INET->new(PeerAddr=>q(127.0.0.1), PeerPort=>123, Proto=>q(udp)) or die qq(no socket\n);
    \$s->send(qq(tsm0-selftest\n));
    my \$r; \$s->recv(\$r, 512);
    print qq(TSM0: loopback reply=[), \$r, qq(]\n);
  "
  kill $STUB
'
```

기대: `TSM0: stub is alive on 123`과 `TSM0: loopback reply=[tsm0-pong\n]`,
그리고 stub이 찍은 `TSM0-STUB: recv 14 bytes from 127.0.0.1:...`.

`cannot bind udp/123`이 나오면 위험 4가 현실이다. 그때는 이 Task를 포트
`12123`으로 한 번 더 돌려 그 번호로 도는지 확인하고, 아래 Task 2의
`STUB_PORT`를 그 값으로 바꾼다. 그리고 design 결정 5에 "주소에 포트를 적는
문법이 필요하다"를 실측으로 적는다.

## Task 2 — 하네스 전문

- [ ] Step 1: `/tmp/ts/guest.sh`를 만든다

호스트에서 이 내용 그대로 쓴다.

```bash
#!/usr/bin/env bash
# TS-M0 측정 1·2·5·6. 컨테이너 안에서 돈다.
#
# 게스트를 한 번 띄우고 콘솔 셸에 FIFO로 명령을 넣는다. 같은 컨테이너에서
# perl stub이 배경으로 UDP를 듣고 있고, 게스트는 bash의 /dev/udp로 거기에
# 붙는다.
#
# 순서에 제약이 하나다 — probe CLOCK이 probe STEP보다 먼저여야 한다. 시계를
# 한 번 뛰면 "원래 무엇이었나"를 다시 만들 수 없다.
#
# monitor를 안 쓴다. -serial stdio와 -monitor none이 짝이고, 그래서 전원
# 버튼을 못 누른다 — 끝낼 때는 QEMU를 kill한다(IN-M0과 같다).
#
# virtio-gpu는 붙인다. 화면 셸을 쓰지는 않지만 terminal이 찍는
# `terminal: screen>` 줄이 자라는지를 보면 시계를 뛴 뒤에 렌더가 살아 있는지
# 알 수 있다(위험 2).
set -uo pipefail
cd /workspace

STUB_PORT=123        # Task 1 Step 3이 123을 못 열었으면 그 값으로 바꾼다
SLIRP_HOST=10.0.2.2  # SLIRP에서 호스트를 가리키는 주소

LOG=/tmp/ts/guest.log
STUBLOG=/tmp/ts/stub.log
FIFO=/tmp/ts/guest.fifo

rm -f "$LOG" "$STUBLOG" "$FIFO"
mkfifo "$FIFO"

# 컨테이너 자신의 IP. probe C가 쓴다 — 10.0.2.2가 안 되면 이 주소로
# 되는지가 다음 질문이다.
CONTAINER_IP="$(perl -MSys::Hostname -MSocket -e \
  'my @a = gethostbyname(hostname); print $a[4] ? inet_ntoa($a[4]) : ""' 2>/dev/null)"
if [ -z "$CONTAINER_IP" ]; then
  echo "TSM0: could not resolve the container IP — probe C will be skipped"
  CONTAINER_IP=""
else
  echo "TSM0: container IP is ${CONTAINER_IP}"
fi

# ── stub을 먼저 띄운다 ────────────────────────────────────────────────
# 게스트보다 먼저여야 한다. 게스트가 부팅하는 2분 동안 stub이 이미 듣고 있다.
perl /tmp/ts/stub.pl "$STUB_PORT" > "$STUBLOG" 2>&1 &
STUB_PID=$!
sleep 1
if ! kill -0 "$STUB_PID" 2>/dev/null; then
  echo "TSM0: the stub died at startup"
  cat "$STUBLOG"
  exit 1
fi
echo "TSM0: stub up (pid ${STUB_PID})"

# ── 빌드 ──────────────────────────────────────────────────────────────
# net/check.sh와 같은 다섯이다. 산출물이 최신이면 커널은 skipping make로
# 넘어간다(GL-M1).
(cd kernel && ./build.sh)      || { echo "TSM0: kernel build failed"; exit 1; }
(cd init && zig build)         || { echo "TSM0: init build failed"; exit 1; }
(cd terminal && ./prepare.sh)  || { echo "TSM0: terminal build failed"; exit 1; }
(cd kernel && ./make_initrd.sh)|| { echo "TSM0: initrd build failed"; exit 1; }
(cd net && ./make_disk.sh)     || { echo "TSM0: config disk build failed"; exit 1; }

# 읽기·쓰기 겸용으로 연다. 쓰기 전용으로 열면 읽는 쪽이 붙을 때까지 막힌다.
exec 4<>"$FIFO"

# net/check.sh의 QEMU 줄에서 hostfwd·guestfwd를 뺀 것이다. TS-M0은 TCP를
# 하나도 안 쓴다 — 나가는 UDP는 SLIRP이 아무 설정 없이 내보낸다(그것이
# 사실인지가 측정 1이다).
qemu-system-x86_64 \
  -m 512 \
  -kernel kernel/build/arch/x86/boot/bzImage \
  -initrd kernel/initrd.cpio \
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
QEMU_PID=$!

cleanup() {
  kill "$QEMU_PID" 2>/dev/null
  wait "$QEMU_PID" 2>/dev/null
  kill "$STUB_PID" 2>/dev/null
  wait "$STUB_PID" 2>/dev/null
  exec 4>&-
  rm -f "$FIFO"
}
trap cleanup EXIT

sleep 2
if ! kill -0 "$QEMU_PID" 2>/dev/null; then
  echo "TSM0: qemu died at startup"
  cat "$LOG"
  exit 1
fi

# 콘솔 셸이 뜰 때까지 기다린다.
WAITED=0
while [ "$WAITED" -lt 120 ]; do
  if grep -aq "started console shell" "$LOG" 2>/dev/null; then break; fi
  sleep 1
  WAITED=$((WAITED + 1))
done
if [ "$WAITED" -ge 120 ]; then
  echo "TSM0: console shell never started"
  tail -40 "$LOG"
  exit 1
fi
echo "TSM0: console shell up after ${WAITED}s"

# dhcpcd가 주소를 받을 때까지 조금 더 준다. NW-M2 실측 17이 이 간격을 쟀다 —
# `started dhcpcd`와 실제 리스 사이에 시리얼 로그 3500줄이 있다.
sleep 8

# 셸에 명령을 넣는다. 이 부팅의 셸은 fish다 — 설정 디스크에 net=dhcp 한
# 줄뿐이라 나머지 여섯 키가 기본값이다.
#
# bash 한 줄을 통째로 작은따옴표로 싸서 넘긴다. fish의 작은따옴표 안에서는
# \와 '만 특별하므로 $?·${#x}·\x23이 전부 글자 그대로 bash에 간다.
say() {
  printf '%s\n' "$1" >&4
  sleep "${2:-3}"
}

echo "=== measurement 2: what does the guest clock say right now ==="
# 판정 글자를 `TSM0-CLOCK` 뒤의 연도로 본다. 명령 에코에는 `%Y`가 있고
# 출력에만 숫자가 있어서 둘이 갈린다.
say 'date -u "+TSM0-CLOCK %Y-%m-%dT%H:%M:%SZ unix=%s"'
say 'echo TSM0-UPTIME=(cat /proc/uptime)'

echo "=== measurement 1 · probe A: plain datagram to ${SLIRP_HOST} ==="
say "bash -c 'exec 3<>/dev/udp/${SLIRP_HOST}/${STUB_PORT}; echo tsm0-a >&3; read -r -t 3 line <&3; echo \"TSM0-A rc=\$? got=[\$line]\"'" 6

echo "=== measurement 1 · probe B: a real 48-byte SNTP request ==="
# 48바이트를 파일로 먼저 만들고 cat 한 번으로 보낸다. printf와 head를 각각
# 소켓에 쓰면 write가 둘이라 datagram이 둘로 갈린다.
say "bash -c '{ printf \"\\x23\"; head -c 47 /dev/zero; } > /run/tsm0.req; echo TSM0-REQLEN=\$(wc -c < /run/tsm0.req)'" 4
say "bash -c 'exec 3<>/dev/udp/${SLIRP_HOST}/${STUB_PORT}; cat /run/tsm0.req >&3; read -r -t 3 -N 1 x <&3; echo \"TSM0-B rc=\$?\"'" 6

if [ -n "$CONTAINER_IP" ]; then
  echo "=== measurement 1 · probe C: plain datagram to ${CONTAINER_IP} ==="
  say "bash -c 'exec 3<>/dev/udp/${CONTAINER_IP}/${STUB_PORT}; echo tsm0-c >&3; read -r -t 3 line <&3; echo \"TSM0-C rc=\$? got=[\$line]\"'" 6
fi

echo "=== measurement 6: can the guest step its wall clock at all ==="
say 'date -u -s "2031-03-04 05:06:07"' 4
say 'date -u "+TSM0-AFTER %Y-%m-%dT%H:%M:%SZ unix=%s"'

echo "=== measurement 5: does the guest still work after the step ==="
say 'echo TSM0-ALIVE=(ls /usr/bin | wc -l)'
say 'echo TSM0-DHCPCD=(pgrep -c dhcpcd)'
say 'echo written > /run/tsm0.after; stat -c "TSM0-MTIME %y" /run/tsm0.after'
say 'echo TSM0-ADDR=(ip -4 addr show eth0 | tr -s " " | head -c 200)'

echo "=== measurement 5b: does UDP still work after the step ==="
say "bash -c 'exec 3<>/dev/udp/${SLIRP_HOST}/${STUB_PORT}; echo tsm0-a2 >&3; read -r -t 3 line <&3; echo \"TSM0-A2 rc=\$? got=[\$line]\"'" 6

# 렌더가 살아 있는지. 이 줄 수가 시계를 뛴 뒤에도 자라면 terminal이 죽지
# 않은 것이다.
SCREENS="$(grep -ac "terminal: screen>" "$LOG")"
echo "TSM0: serial log has ${SCREENS} screen lines"
sleep 5
SCREENS2="$(grep -ac "terminal: screen>" "$LOG")"
echo "TSM0: five seconds later it has ${SCREENS2}"

echo "=== done ==="
```

- [ ] Step 2: 실행 권한을 준다

```bash
chmod +x /tmp/ts/guest.sh
```

`chmod +x`를 빼먹으면 증상이 이 측정과 아무 관계가 없는 자리에서 난다
(NW-M2 실측 22가 같은 함정을 밟았다). 아래 Task 3은 `bash <파일>`로 부르므로
없어도 돌지만, 습관으로 친다.

## Task 3 — 하네스를 돌린다

- [ ] Step 1: 돌린다 (약 3분)

빌드가 최신이면 부팅과 probe에 약 2분, 커널이 다시 빌드되면 더 걸린다.

```bash
docker run --rm -v "$PWD":/workspace -v /tmp/ts:/tmp/ts \
  -w /workspace tars-devcontainer bash /tmp/ts/guest.sh > /tmp/ts/run.log 2>&1
echo "exit=$?"
```

- [ ] Step 2: 컨테이너 쪽 관찰을 본다

```bash
grep -E "^TSM0:|^=== " /tmp/ts/run.log
```

기대: `stub up` · `console shell up after Ns` · probe 절 표지들 · 마지막의
screen 줄 수 둘.

- [ ] Step 3: stub이 무엇을 받았는지 본다 (측정 1의 컨테이너 쪽 절반)

```bash
cat /tmp/ts/stub.log
```

기대(위험 1이 현실이 아니라면):

```
TSM0-STUB: listening on udp/123, will answer Tue Mar  4 05:06:07 2031 (unix 1930367167)
TSM0-STUB: recv 7 bytes from 127.0.0.1:NNNNN first=0x74
TSM0-STUB: sent 10 bytes of text
TSM0-STUB: recv 48 bytes from 127.0.0.1:NNNNN first=0x23
TSM0-STUB: sent 48 bytes of SNTP (origin echoed)
...
```

`recv` 줄이 하나도 없으면 게스트가 보낸 것이 SLIRP을 못 지난 것이다 —
위험 1이 현실이고, probe C의 결과를 보고 Task 4로 간다.

- [ ] Step 4: 게스트 쪽 관찰을 본다 (측정 1의 나머지 절반과 2·5·6)

시리얼 로그에는 ANSI와 터미널 렌더 줄이 섞여 있다. 우리가 만든 표지만 뽑는다.

```bash
grep -aoE "TSM0-(CLOCK|UPTIME|A|B|C|A2|REQLEN|AFTER|ALIVE|DHCPCD|MTIME|ADDR)[^|]*" \
  /tmp/ts/guest.log | grep -v '%' | sort -u
```

`grep -v '%'`가 `date` 계열 두 줄의 명령 에코를 버린다 — 우리가 친
`date -u "+TSM0-CLOCK %Y…"`에는 `%`가 있고 출력에는 없다(NW-M3이 만든 규칙,
`docs/decisions/project_gate_screen_echo.md`).

probe A·B·C는 그 방법이 안 통한다. 그 명령줄에는 `%`가 없어서 에코도 함께
남는다. 대신 모양으로 갈린다 — 에코는 `TSM0-A rc=$? got=[$line]`처럼 변수
이름이 그대로 있고, 출력은 `TSM0-A rc=0 got=[tsm0-pong]`처럼 숫자와 실제
글자가 들어 있다. 둘 다 보이는 것이 정상이고, 출력 쪽만 없으면 그 probe가
죽은 것이다.

읽는 법:

| 표지 | 초록의 모양 | 다른 값이 뜻하는 것 |
|---|---|---|
| `TSM0-CLOCK` | 연도가 찍힌다 | 측정 2의 답. 2026년이면 CMOS를 읽은 것이고, 1970년이면 안 읽은 것이다 |
| `TSM0-A rc=0 got=[tsm0-pong]` | 왕복이 됐다 | `rc=1`이면 답이 3초 안에 안 왔다. `rc=0 got=[]`이면 빈 datagram이다 |
| `TSM0-REQLEN=48` | 요청 파일이 정확히 48바이트다 | 다른 값이면 probe B의 실패가 SLIRP 탓이 아니다 |
| `TSM0-B rc=0` | 48바이트 왕복이 됐다 | `rc=1`이면 길이나 내용이 문제일 수 있다 — A가 살고 B가 죽으면 그렇다 |
| `TSM0-C` | probe C의 답 | A가 죽고 C가 살면 처방은 stub의 자리를 옮기는 것이다 |
| `TSM0-AFTER` | `2031-03-04T05:06:07Z` 근처 | 측정 6. 안 바뀌었으면 `date -s`가 실패한 것이다 |
| `TSM0-ALIVE` | `/usr/bin`의 파일 수 | 측정 5. 숫자가 나오면 셸이 살아 있다 |
| `TSM0-DHCPCD=1` | dhcpcd가 살아 있다 | `0`이면 시계 점프가 dhcpcd를 죽인 것이다 — 위험 7이 현실이다 |
| `TSM0-MTIME` | `2031-…` | 시계 점프가 파일 mtime에 실제로 반영된다 |
| `TSM0-A2 rc=0` | 점프 뒤에도 UDP가 돈다 | `rc=1`이면 위험 2가 현실이다 |

- [ ] Step 5: 렌더가 살아 있는지 본다 (위험 2의 나머지)

```bash
grep -E "^TSM0: serial log has|^TSM0: five seconds later" /tmp/ts/run.log
```

⚠ 이 판정은 틀렸다(실측 7이 그것을 적었다). `terminal`은 `needs_redraw`를
문지기로 두어서 화면에 아무 일도 없으면 프레임을 안 찍는데(TR-M2), 이 하네스는
콘솔 셸만 쓰므로 화면 셸에 입력이 없다. 그래서 숫자가 안 자라는 것이
"렌더가 죽었다"와 "할 일이 없다" 둘 다를 뜻한다 — 갈라지지 않는다.

숫자는 그냥 기록만 하고 넘어간다. 렌더가 시계 점프를 견디는지는 M1의
부팅 A가 본다. 그 부팅은 `net/check.sh` 안에 있어서 monitor로 화면에 타이핑을
하므로, 점프 뒤에 화면 판정이 서면 그 자체가 렌더가 살아 있다는 증거다.

- [ ] Step 6: 실패한 probe가 있으면 원본 로그를 직접 본다

```bash
perl -pe 's/\e\][^\a\e]*(\a|\e\\)//g; s/\e\[[0-9;?>=]*[a-zA-Z]//g;
          s/\e[()][AB0]//g; s/\r/\n/g' /tmp/ts/guest.log > /tmp/ts/guest.clean
grep -a -B3 -A3 "TSM0-" /tmp/ts/guest.clean | tail -60
```

`tr '|'`를 쓰지 않는다. IN-M1 실측 9가 겪은 대로 `terminal: screen>` 줄이
화면 행을 ` | `로 잇는데, 우리 명령줄에 `|`가 들어 있어서(`ip … | tr … | head`)
행 경계와 구별이 안 된다.

## Task 4 — 위험 1이 현실이면 여기서 멈춘다

- [ ] Step 1: 판단한다

probe A와 B가 둘 다 `rc=1`이고 `stub.log`에 `recv` 줄이 하나도 없으면 SLIRP이
`10.0.2.2`로 가는 UDP를 컨테이너에 안 넘긴 것이다.

- [ ] Step 2: probe C의 결과로 갈린다

| probe C | 뜻 | 다음 |
|---|---|---|
| `rc=0` | UDP 자체는 SLIRP을 지난다. `10.0.2.2`라는 자리만 특별하다 | design 결정 6을 "stub을 컨테이너 IP에 둔다"로 고치고 M1로 간다 |
| `rc=1` | 나가는 UDP가 통째로 안 지난다 | 멈추고 사용자에게 묻는다 |

- [ ] Step 3: 둘 다 죽었으면 사용자에게 보고한다

보고에 담을 것: `stub.log` 전문 · probe A·B·C의 `rc` · `TSM0-ADDR`(게스트에
주소가 붙어 있었는지). design 위험 1이 적어 둔 대로 선택지는 "가짜 LAN"으로
되돌아가는 것이고 그것은 범위를 크게 늘리므로 사용자의 결정이다.

여기서 멈추면 Task 5·6은 그대로 하고 M1은 안 시작한다.

## Task 5 — 측정 4: dhcpcd가 option 42를 요청하는가

부팅이 필요 없다. 컨테이너 안의 sysroot만 본다.

- [ ] Step 1: sysroot의 dhcpcd 설정과 바이너리를 본다

```bash
docker run --rm tars-devcontainer bash -c '
  SR=/usr/local/amd64-sysroot
  echo "=== sysroot에 /etc/dhcpcd.conf가 있나 ==="
  if [ -f "$SR/etc/dhcpcd.conf" ]; then
    grep -vE "^\s*#|^\s*$" "$SR/etc/dhcpcd.conf"
  else
    echo "(없다 — dhcpcd가 컴파일 타임 기본값만 쓴다)"
  fi
  echo; echo "=== 바이너리에 ntp 관련 문자열이 있나 ==="
  strings "$SR/usr/sbin/dhcpcd" | grep -i "ntp" | head -20
  echo; echo "=== initrd에 dhcpcd.conf가 들어가나 ==="
  grep -n "dhcpcd.conf" /workspace/kernel/make_initrd.sh || echo "(안 넣는다)"
' 2>&1
```

- [ ] Step 2: 게스트가 실제로 무엇을 요청했는지 본다

Task 3의 부팅에서 dhcpcd가 이미 돌았다. 그 리스 파일에 무엇이 들어왔는지는
SLIRP이 안 주므로 아무것도 안 알려 주지만, 요청 목록은 dhcpcd 자신이 로그에
찍는 것이 있으면 거기 있다.

```bash
grep -ai "ntp\|dhcpcd" /tmp/ts/guest.log | grep -av "screen>" | head -30
```

- [ ] Step 3: 결론을 하나로 적는다

셋 중 하나다.

| 관측 | 결론 | M2가 할 일 |
|---|---|---|
| `ntp_servers`가 기본 요청 목록에 있다 | 아무것도 안 해도 온다 | 그대로 |
| 없다 | 요청을 명시해야 한다 | `net.zig`의 argv에 `-o ntp_servers`를 더한다 |
| 못 가렸다 | 가르는 비용이 처방 비용보다 크다 | 그냥 `-o ntp_servers`를 붙인다. 있어도 해가 없다 |

셋째 줄이 중요하다. 이 측정은 "확실히 알기"가 목적이 아니라 "M2가 무엇을
칠지 정하기"가 목적이고, 처방이 한 단어라서 애매하면 그냥 붙이는 것이 옳다.

## Task 6 — design에 실측을 적고 커밋한다

- [ ] Step 1: design에 절을 더한다

`docs/superpowers/specs/2026-09-15-tars-time-sync-design.md`의 "## Milestone"
바로 앞에 절을 하나 더한다.

```markdown
## TS-M0이 실행으로 증명한 것

(실측 1부터 번호를 매긴다. 각 실측은 "무엇을 했고 무엇이 나왔고 그래서
무엇이 정해졌나"를 적는다. 숫자는 로그에서 그대로 옮긴다 — 반올림하거나
"약"으로 쓰지 않는다.)
```

적을 것이 최소 여섯이다 — 측정 1~6 각각 하나씩. plan에 없던 것이 나오면
그것도 실측으로 적는다. NW-M0은 열을 적었고 그중 셋이 plan에 없던 것이었으며,
IN-M0은 일곱 중 둘이 그랬다.

- [ ] Step 2: design의 위험 절을 고친다

닫힌 위험에는 그 자리에 한 줄을 더한다 — `TS-M0이 닫았다(실측 N).` 현실이
된 위험에는 `⚠ 현실이 됐다(실측 N).`과 그래서 무엇이 바뀌었는지를 적는다.

- [ ] Step 3: 더한 줄과 지운 줄을 따로 센다

```bash
git diff --stat
```

design 문서만 바뀌어야 한다. 소스가 하나라도 걸리면 이 milestone의 전제가
깨진 것이다.

- [ ] Step 4: 지운 줄이 있으면 내용을 직접 읽는다

```bash
git diff | grep '^-'
```

위험 절을 고치면서 줄이 지워질 수 있다. 의도한 줄만 지워졌는지 본다.

- [ ] Step 5: 커밋한다

```bash
git add docs/superpowers/specs/2026-09-15-tars-time-sync-design.md \
        docs/superpowers/plans/2026-09-15-tars-time-sync-ts-m0.md
git commit -m "Measure the clock and the path to a time server"
```

`git add`로 디렉터리를 통째로 넣지 않는다. `/tmp/ts/`는 저장소 밖이라
어차피 안 들어가지만, 대상을 좁혀 적는 것이 이 저장소의 규칙이다.

## 이 milestone이 끝난 자리

- `/tmp/ts/stub.pl` · `/tmp/ts/guest.sh`와 로그 넷
  (`run.log` · `guest.log` · `guest.clean` · `stub.log`). 호스트 `/tmp`라
  언젠가 사라지고, 다시 필요하면 이 plan의 Task 1·2에 전문이 글자 그대로 있다.
- design에 실측 절 하나와 위험 절의 정정.
- 저장소의 코드 파일은 한 글자도 안 바뀐다.

끝 기준: 측정 여섯이 다 답해져 design에 실측으로 적혔고, 위험 1의 답이
예다(또는 probe C로 우회할 길이 정해졌다).
