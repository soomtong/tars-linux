#!/usr/bin/env perl
# RS 프로브 로그를 집계한다. 로그 하나에 한 줄씩, 끝에 회차들의 중앙값.
#
#   perl probe/report.pl out/probe-rs/m0-run*.log
#
# (b) 처리량 — Enter(`DONE0` 앞의 마지막 `key>`) 뒤 첫 프레임부터 `DONE0`이 처음 보인
#     프레임까지. span은 두 프레임의 `t` 차이, frames는 그 사이(양끝 포함)의 프레임 수,
#     frame · dump는 그 프레임들의 합, reads · bytes도 합이다.
# (a) 지연 — `DONE0` 뒤에 친 키(`key>`) 다음에 온 프레임들의 frame · dump 중앙값.
#
# screen> 줄은 커널 printk에 잘릴 수 있지만 `DONE0`이 든 조각은 어느 쪽이든 그 프레임의
# probe> 줄보다 앞이다. 그래서 줄 단위로 "DONE0을 봤다"만 기억하면 된다.
use strict;
use warnings;

sub median {
    my @s = sort { $a <=> $b } @_;
    return 'n/a' unless @s;
    return $s[int($#s / 2)];
}

my (@spans, @b_frames, @b_frame_ms, @b_dump_ms, @b_reads, @a_frame, @a_dump);

for my $file (@ARGV) {
    open my $fh, '<', $file or die "read $file: $!\n";
    my @frames;          # [t, frame, dump, reads, bytes, after_key, done_seen]
    my $key_pending = 0; # 마지막 probe> 뒤로 key> 가 있었나
    my $done = 0;        # DONE0을 이미 봤나
    my $last_key_frame;  # 마지막 key> 뒤 첫 프레임의 번호
    while (my $line = <$fh>) {
        $done = 1 if !$done && $line =~ /DONE0/;
        if ($line =~ /terminal: key> /) { $key_pending = 1; next }
        next unless $line =~ /terminal: probe> t=(\d+) frame=(\d+) dump=(-?\d+) reads=(\d+) bytes=(\d+)/;
        push @frames, [$1, $2, $3, $4, $5, $key_pending, $done];
        $key_pending = 0;
    }
    close $fh;

    my ($end) = grep { $frames[$_][6] } 0 .. $#frames;
    die "$file: no DONE0 frame\n" unless defined $end;
    my ($start) = grep { $frames[$_][5] } reverse 0 .. $end;
    die "$file: no key before DONE0\n" unless defined $start;

    my @b = @frames[$start .. $end];
    my $span = ($frames[$end][0] - $frames[$start][0]) / 1000;
    my ($f, $d, $r, $by) = (0, 0, 0, 0);
    for (@b) { $f += $_->[1]; $d += $_->[2]; $r += $_->[3]; $by += $_->[4] }

    my @a = grep { $_->[5] } @frames[$end + 1 .. $#frames];
    my @af = map { $_->[1] / 1000 } @a;
    my @ad = map { $_->[2] / 1000 } @a;

    printf "%s\n  (b) span=%.0fms frames=%d frame_sum=%.0fms dump_sum=%.0fms other=%.0fms reads=%d bytes=%d\n"
         . "  (a) n=%d frame=%s ms dump=%s ms (median)\n",
        $file, $span, scalar @b, $f / 1000, $d / 1000, $span - ($f + $d) / 1000, $r, $by,
        scalar @a, median(@af), median(@ad);

    push @spans, $span;
    push @b_frames, scalar @b;
    push @b_frame_ms, $f / 1000;
    push @b_dump_ms, $d / 1000;
    push @b_reads, $r;
    push @a_frame, @af;
    push @a_dump, @ad;
}

printf "\nmedian over %d run(s)\n  (b) span=%.0fms frames=%d frame_sum=%.0fms dump_sum=%.0fms reads=%d\n"
     . "  (a) frame=%s ms dump=%s ms (n=%d)\n",
    scalar @spans, median(@spans), median(@b_frames), median(@b_frame_ms), median(@b_dump_ms),
    median(@b_reads), median(@a_frame), median(@a_dump), scalar @a_frame;
