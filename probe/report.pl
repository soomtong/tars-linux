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
# DR-M0: `split>` 줄(probe/split.pl)이 있는 로그면 (a)의 구간별 값. 없으면 아래 출력이 RS 때와 같다.
# 구간 이름은 DR-M2의 것이다(M0은 backdrop others cells pane finish present — 그 판은 `git log -p`에).
my @SPLIT = qw(others cells pane rows overlay finish present);
my %a_split = map { $_ => [] } @SPLIT;
# DR-M3 Task 0: `cells>` 줄(probe/cells.pl)이 있는 로그면 `cells()` 안의 세 구간. `split>`과 같은 방법으로 다음 `probe>`
# 프레임에 붙인다. 없는 로그의 출력은 그대로다.
my @CELLS = qw(update spans loop);
my %a_cells = map { $_ => [] } @CELLS;

for my $file (@ARGV) {
    open my $fh, '<', $file or die "read $file: $!\n";
    my @frames;          # [t, frame, dump, reads, bytes, after_key, done_seen]
    my $key_pending = 0; # 마지막 probe> 뒤로 key> 가 있었나
    my $done = 0;        # DONE0을 이미 봤나
    my $last_key_frame;  # 마지막 key> 뒤 첫 프레임의 번호
    my $split;          # 마지막으로 본 split> 값. 같은 프레임의 probe> 줄이 그 뒤에 온다
    my $cells;          # 마지막으로 본 cells> 값. 패널 하나라 프레임마다 하나다
    while (my $line = <$fh>) {
        $done = 1 if !$done && $line =~ /DONE0/;
        if ($line =~ /terminal: key> /) { $key_pending = 1; next }
        if ($line =~ /terminal: split> others=(\d+) cells=(\d+) pane=(\d+) rows=(\d+) overlay=(\d+) finish=(\d+) present=(\d+)/) {
            @$split{@SPLIT} = ($1, $2, $3, $4, $5, $6, $7);
            next;
        }
        if ($line =~ /terminal: cells> update=(\d+) spans=(\d+) loop=(\d+)/) {
            @$cells{@CELLS} = ($1, $2, $3);
            next;
        }
        next unless $line =~ /terminal: probe> t=(\d+) frame=(\d+) dump=(-?\d+) reads=(\d+) bytes=(\d+)/;
        push @frames, [$1, $2, $3, $4, $5, $key_pending, $done, $split, $cells];
        $key_pending = 0;
        undef $split;
        undef $cells;
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
    for my $f (grep { defined $_->[7] } @a) {
        push @{ $a_split{$_} }, $f->[7]{$_} / 1000 for @SPLIT;
    }
    for my $f (grep { defined $_->[8] } @a) {
        push @{ $a_cells{$_} }, $f->[8]{$_} / 1000 for @CELLS;
    }
}

printf "\nmedian over %d run(s)\n  (b) span=%.0fms frames=%d frame_sum=%.0fms dump_sum=%.0fms reads=%d\n"
     . "  (a) frame=%s ms dump=%s ms (n=%d)\n",
    scalar @spans, median(@spans), median(@b_frames), median(@b_frame_ms), median(@b_dump_ms),
    median(@b_reads), median(@a_frame), median(@a_dump), scalar @a_frame;

if (@{ $a_split{cells} }) {
    printf "  (a) split (median ms, n=%d): %s\n",
        scalar @{ $a_split{cells} }, join ' ', map { "$_=" . median(@{ $a_split{$_} }) } @SPLIT;
}
if (@{ $a_cells{loop} }) {
    my $sum = 0;
    $sum += median(@{ $a_cells{$_} }) for @CELLS;
    printf "  (a) cells (median ms, n=%d): %s sum=%.3f\n",
        scalar @{ $a_cells{loop} }, join(' ', map { "$_=" . median(@{ $a_cells{$_} }) } @CELLS), $sum;
}
