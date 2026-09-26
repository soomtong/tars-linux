#!/usr/bin/perl
# net 체인의 NTP 서버. 컨테이너 안에서 배경으로 돌면서 UDP 한 포트를 듣는다.
#
# TS 때는 몇 번을 묻든 같은 시각을 답했다(net/sntp_stub.pl). 상대가 한 번
# 묻고 뛰는 우리 SNTP였기 때문이다. TD-M1부터 상대가 chronyd이고, chronyd는
# 여러 번 물어 그 사이에 흐른 시간으로 주파수를 추정하므로 멈춘 시계를
# 상대로는 엉뚱한 값을 배운다(TD design 확인 3). 그래서 흐른다.
#
#   답하는 시각 = 출발 시각 + (지금 - 시작) × (1 + ppm / 10^6)
#
# ppm은 M2가 쓴다. 0이면 컨테이너 시계와 같은 빠르기로 흐른다.
#
# 인자: 포트 · 출발 시각(unix) · ppm
use strict;
use warnings;
use IO::Socket::INET;
use Socket;    # sockaddr_in·inet_ntoa. IO::Socket::INET은 이것을 자기
               # 네임스페이스로만 들여오므로 여기서 따로 써야 한다.
use Time::HiRes qw(time);

$| = 1;    # 배경으로 돌므로 버퍼를 안 쌓는다.

my $port = $ARGV[0] // 123;
my $base = $ARGV[1] // 1930367167;    # 2031-03-04T05:06:07Z
my $ppm  = $ARGV[2] // 0;

my $NTP_EPOCH = 2208988800;    # NTP의 초는 1900부터 센다
my $start = time();
my $rate  = 1 + $ppm / 1e6;

sub now_ntp {
    my $t = $base + (time() - $start) * $rate + $NTP_EPOCH;
    my $sec = int($t);
    return pack('NN', $sec, int(($t - $sec) * 4294967296));
}

my $sock = IO::Socket::INET->new(
    LocalAddr => '0.0.0.0',
    LocalPort => $port,
    Proto     => 'udp',
) or die "ntp-stub: cannot bind udp/$port: $!\n";

printf "ntp-stub: listening on udp/%d, starting at unix %d, %s ppm\n",
    $port, $base, $ppm;

# 시작 때의 시각을 reference timestamp로 쓴다. 0이면 chrony가 "서버가 한 번도
# 동기화된 적 없다"로 읽는다.
my $ref = now_ntp();
my $count = 0;

while (1) {
    my $req;
    # 메서드가 아니라 내장 함수 꼴로 부른다. IO::Socket에는 recv 메서드가
    # 없어서 메서드 꼴은 버전에 따라 조용히 안 돈다.
    my $from = recv($sock, $req, 512, 0);
    next unless defined $from;
    my $rx = now_ntp();
    my ($fport, $faddr) = sockaddr_in($from);
    if (length($req) < 48) {
        printf "ntp-stub: ignoring a %d-byte datagram\n", length($req);
        next;
    }
    # 요청의 transmit(40-47)을 originate(24-31)로 되돌린다. chrony는 이것이
    # 자기가 보낸 값과 다르면 답을 버린다.
    my $orig = substr($req, 40, 8);
    my $poll = unpack('c', substr($req, 2, 1));
    # LI 0 · VN 4 · mode 4(server) → 0x24. stratum 1 · poll은 요청값 그대로 ·
    # precision -20(약 1µs). root delay · root dispersion은 0이다.
    my $reply = pack('CCcc', 0x24, 1, $poll, -20)
              . pack('NN', 0, 0)
              . 'TARS'
              . $ref . $orig . $rx . now_ntp();
    send($sock, $reply, 0, $from) or print "ntp-stub: send failed: $!\n";
    $count++;
    printf "ntp-stub: answer #%d to %s:%d\n", $count, inet_ntoa($faddr), $fport;
}
