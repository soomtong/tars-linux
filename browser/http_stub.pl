#!/usr/bin/perl
# browser 체인의 망 stub(CR-M2 plan 확정 11, CR design 결정 10). QEMU의 guestfwd(`tcp:10.0.2.100:80-cmd:perl http_stub.pl <로그>`)가
# 연결마다 이것을 새로 띄우고 그 연결을 표준 입력 · 출력으로 준다. 요청 줄을 로그에 적고(시각 · 줄 하나 — 체인이 `GET /net.html`을 본다),
# `/net.html`에는 고정 HTML(제목 tars-net · 바탕 d35400)을, 그 밖(favicon 등)에는 404를 준다. TLS로 보이는 첫 바이트(0x16)는 `TLS-ish`로만 적는다 —
# HTTPS는 게이트 밖이다(확정 11). 바깥으로는 나가지 않는다 — 망은 `restrict=on`이라 게스트가 볼 수 있는 것은 이 stub 하나다.
use strict;
use warnings;
use Time::HiRes qw(time);

my $log = shift;
$| = 1;
binmode STDIN;
binmode STDOUT;
my $req = <STDIN>;
$req = '' unless defined $req;
$req =~ s/\r?\n\z//;
while (my $l = <STDIN>) { last if $l =~ /^\r?\n\z/; }
if (defined $log && open(my $fh, '>>', $log)) { printf $fh "%.3f %s\n", time, ($req =~ /^\x16/ ? 'TLS-ish' : $req); }
my ($status, $type, $body);
if ($req =~ m{^GET /net\.html }) {
  ($status, $type) = ('200 OK', 'text/html; charset=utf-8');
  $body = qq{<!doctype html><meta charset="utf-8"><title>tars-net</title><style>html,body{margin:0;height:100%;background:#d35400}</style><p style="font:40px sans-serif">net 페이지</p>\n};
} else {
  ($status, $type, $body) = ('404 Not Found', 'text/plain', "not here\n");
}
utf8::encode($body) if utf8::is_utf8($body);
print "HTTP/1.1 $status\r\nContent-Type: $type\r\nContent-Length: " . length($body) . "\r\nConnection: close\r\n\r\n$body";
