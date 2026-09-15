#!/usr/bin/perl
# net/check.sh의 부팅 A가 쓰는 상대. 컨테이너 안에서 배경으로 돌면서 UDP
# 한 포트를 듣고, 받은 요청마다 고정된 시각으로 답한다.
#
# 왜 perl인가. 이 컨테이너에는 nc·ncat·socat·python3·busybox가 하나도 없고
# (NW-M0), bash의 /dev/udp는 거는 것만 된다. QEMU의 guestfwd는 TCP 전용이라
# TS에는 못 쓴다. perl의 IO::Socket::INET이 그 자리를 메운다(TS 확인 6).
#
# 왜 고정된 시각인가. 게스트의 벽시계는 NTP 없이도 이미 맞다 — 커널이 CMOS를
# 읽고 QEMU가 그것을 호스트 시각으로 채운다(TS-M0 실측 4). 그래서 "맞아졌다"로
# 판정할 수 없고, 현실에 있을 수 없는 값으로만 갈린다.
#
# 미래여야 하는 이유는 mtime이다(design 위험 2). 과거로 뛰면 게이트가 만든
# 파일의 시각이 뒤집혀서 다른 자리에서 이상한 일이 날 수 있다.
use strict;
use warnings;
use IO::Socket::INET;
use Socket;    # sockaddr_in·inet_ntoa. IO::Socket::INET은 이것을 자기
               # 네임스페이스로만 들여온다.

$| = 1;    # 배경으로 돌므로 버퍼를 안 쌓는다. 안 하면 로그가 끝에 몰린다.

my $port = $ARGV[0] // 123;
my $fixed_unix = $ARGV[1] // 1930367167;    # 2031-03-04T05:06:07Z

# NTP의 초는 1970이 아니라 1900부터 센다(design 결정 11).
my $NTP_EPOCH = 2208988800;

my $sock = IO::Socket::INET->new(
    LocalAddr => '0.0.0.0',
    LocalPort => $port,
    Proto     => 'udp',
) or die "sntp-stub: cannot bind udp/$port: $!\n";

printf "sntp-stub: listening on udp/%d, answering unix %d (%s)\n",
    $port, $fixed_unix, scalar(gmtime($fixed_unix));

while (1) {
    my $req;
    # 메서드가 아니라 내장 함수 꼴로 부른다. IO::Socket에는 recv 메서드가
    # 없어서 메서드 꼴은 버전에 따라 조용히 안 돈다.
    my $from = recv($sock, $req, 512, 0);
    unless (defined $from) {
        print "sntp-stub: recv failed: $!\n";
        next;
    }
    my ($fport, $faddr) = sockaddr_in($from);
    my $len = length($req);
    printf "sntp-stub: recv %d bytes from %s:%d\n", $len, inet_ntoa($faddr), $fport;

    if ($len != 48) {
        # 게이트에서 48이 아닌 것이 오는 일은 없어야 한다. 왔다면 우리 코드가
        # 잘못 만든 것이고, 조용히 답하면 그 사실이 묻힌다.
        printf "sntp-stub: ignoring a %d-byte datagram (we only answer 48)\n", $len;
        next;
    }

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
    # 24-31을 요청에서 그대로 베끼는 것이 design 결정 12의 마지막 줄이 보는
    # 자리다. init의 parseReply가 이 여덟 바이트를 자기 nonce와 대조한다.
    #
    # 템플릿이 CCCc다. 넷째가 부호 있는 바이트(precision -6)이고 앞의 셋이
    # 부호 없는 것이다. CCcC로 쓰면 결과 바이트는 두 보수라 같지만 perl이
    # `Character in 'C' format wrapped`를 찍는다 — TS-M0의 self-test가 이것을
    # 잡았고 `perl -c`는 문법만 보므로 못 잡는다.
    my $orig = substr($req, 40, 8);
    my $ts = pack('NN', $fixed_unix + $NTP_EPOCH, 0);
    my $reply = pack('CCCc', 0x24, 1, 4, -6)
              . pack('NN', 0, 0)
              . 'TARS'
              . $ts . $orig . $ts . $ts;
    send($sock, $reply, 0, $from) or print "sntp-stub: send failed: $!\n";
    print "sntp-stub: sent 48 bytes (origin echoed)\n";
}
