#!/usr/bin/perl
# VD 체인의 Groq 흉내(VD design 결정 5). QEMU의 guestfwd가 게스트의 10.0.2.100:8080
# 연결마다 이것을 하나씩 띄우고 표준 입출력을 그 연결에 잇는다 — 듣는 프로세스가
# 없다(lessons 41, net 체인의 cat과 같은 자리). 그래서 요청 하나를 읽고 답 하나를
# 쓰고 끝난다.
#
# 하는 일 둘.
#   1. 받은 것을 로그(인자 1) 한 줄로 남긴다 — 경로 · 인증 헤더 · multipart의 각 칸 ·
#      file 칸의 WAV 머리와 샘플. 체인은 이 줄로 "녹음이 마이크를 지나 API까지 왔다"를 본다
#   2. 경로의 첫 마디로 답을 고른다. 게스트의 dictation.conf가 transcribe_url로 어느
#      답을 받을지 정한다(둘째 마디는 갈래의 이름이라 로그에서 요청을 가른다)
#        /ok/…      200 {"text":" 안녕하세요 vd0-dictated"}  앞의 공백은 Whisper의 버릇이다
#        /ctrl/…    200 text에 ESC · CR · 탭 · 개행이 섞였다 — 지워지는지 본다
#        /blank/…   200 {"text":" ."}                         Whisper가 무음에 주는 답
#        /notext/…  200 {"error":null}                        text 칸이 없다
#        /fail/…    429                                       무료 티어의 분당 한도
#
# 컨테이너에 python이 없어서 perl로 쓴다(feedback_scripting_runtimes). 코어 모듈만 쓴다.
use strict;
use warnings;

my $log = shift or die "usage: stub.pl <log>\n";
binmode STDIN;
binmode STDOUT;
$| = 1;

sub line_in {
  my $l = <STDIN>;
  return undef unless defined $l;
  $l =~ s/\r?\n\z//;
  return $l;
}

my $request = line_in() // exit 0;
my ($method, $path) = split / /, $request;
my %h;
while (defined(my $l = line_in())) {
  last if $l eq '';
  my ($k, $v) = split /:\s*/, $l, 2;
  $h{lc $k} = $v;
}
# curl은 큰 본문 앞에 Expect: 100-continue를 붙이고 1초를 기다린다. 답하면 기다림이 없다.
if (($h{expect} // '') =~ /100-continue/i) {
  print "HTTP/1.1 100 Continue\r\n\r\n";
}
my $len = $h{'content-length'} // 0;
my $body = '';
while (length($body) < $len) {
  my $n = read(STDIN, my $chunk, $len - length($body));
  last unless $n;
  $body .= $chunk;
}

# multipart의 칸을 이름으로 모은다.
my %part;
my @order;
my $file_desc = '-';
if (($h{'content-type'} // '') =~ /boundary=(\S+)/) {
  my $b = $1;
  for my $p (split /--\Q$b\E/, $body) {
    next unless $p =~ /\A\r\n(.*?)\r\n\r\n(.*)\r\n\z/s;
    my ($ph, $pv) = ($1, $2);
    next unless $ph =~ /name="([^"]+)"/;
    my $name = $1;
    push @order, $name;
    $part{$name} = $pv;
    if ($name eq 'file') {
      my ($fn) = $ph =~ /filename="([^"]*)"/;
      my ($ty) = $ph =~ /Content-Type:\s*(\S+)/i;
      $file_desc = sprintf 'name=%s type=%s bytes=%d', $fn // '-', $ty // '-', length $pv;
    }
  }
}

# WAV 머리와 샘플. 녹음이 진짜 마이크를 지났다면 체인이 넣은 상수가 거의 전부다.
# mode는 가장 많이 나온 값, mode_count는 그 개수다.
my $wav_desc = '-';
my $sample_desc = '-';
if (defined $part{file} && length($part{file}) >= 44 && substr($part{file}, 0, 4) eq 'RIFF') {
  my $w = $part{file};
  my ($ch, $rate, $bits) = (unpack('v', substr($w, 22, 2)), unpack('V', substr($w, 24, 4)), unpack('v', substr($w, 34, 2)));
  my $hdr_data = unpack('V', substr($w, 40, 4));
  my $data = substr($w, 44);
  $wav_desc = sprintf 'rate=%d ch=%d bits=%d data=%d header_data=%d', $rate, $ch, $bits, length $data, $hdr_data;
  my %count;
  my $n = 0;
  for (my $i = 0; $i + 2 <= length $data; $i += 2) {
    $count{unpack('s<', substr($data, $i, 2))}++;
    $n++;
  }
  my ($mode) = sort { $count{$b} <=> $count{$a} } keys %count;
  $sample_desc = sprintf 'n=%d mode=%s mode_count=%d', $n, $mode // '-', defined $mode ? $count{$mode} : 0;
}

my $field = sub { my $v = $part{$_[0]}; defined $v ? $v : '-' };
open(my $lf, '>>', $log) or die "cannot open $log\n";
printf $lf "stub: %s %s auth=[%s] parts=[%s] model=[%s] language=[%s] response_format=[%s] file=[%s] wav=[%s] samples=[%s]\n",
  $method // '-', $path // '-', $h{authorization} // '-', join(',', @order),
  $field->('model'), $field->('language'), $field->('response_format'), $file_desc, $wav_desc, $sample_desc;
close $lf;

my ($kind) = ($path // '') =~ m{\A/([a-z]+)};
my ($status, $json) = (200, '{"text":" 안녕하세요 vd0-dictated"}');
if (!defined $kind) { ($status, $json) = (404, '{"error":"no such path"}') }
elsif ($kind eq 'ok') { }
elsif ($kind eq 'ctrl') { $json = '{"text":"vd0-ctrl a\u001b[201~b\rc\td\ne\u0085f\u001b"}' }
elsif ($kind eq 'blank') { $json = '{"text":" ."}' }
elsif ($kind eq 'notext') { $json = '{"error":null}' }
elsif ($kind eq 'fail') { ($status, $json) = (429, '{"error":{"message":"Rate limit reached"}}') }
else { ($status, $json) = (404, '{"error":"no such path"}') }

my $reason = { 200 => 'OK', 404 => 'Not Found', 429 => 'Too Many Requests' }->{$status};
# 본문의 한글은 UTF-8 바이트 그대로다(이 파일이 UTF-8이고 use utf8이 없다).
print "HTTP/1.1 $status $reason\r\nContent-Type: application/json\r\nContent-Length: " . length($json)
  . "\r\nConnection: close\r\n\r\n$json";
