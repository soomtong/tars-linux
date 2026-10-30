#!/usr/bin/env perl
# DR-M3 Task 0 진단 판 — `cells()` 안을 셋으로 쪼갠다(DR-M3 plan 확정 9 · 10). `vt.zig`를 패치한다. 원본은
# 안 바꾼다. `patch.pl` · `split.pl`이 `main.zig`에 붙는 것과 같이 쓴다(컨테이너에 두 파일을 마운트한다).
#
#   perl probe/cells.pl terminal/src/vt.zig /tmp/dr-probe/vt.zig
#
# `cells()` 호출마다 한 줄을 찍는다.
#
#   terminal: cells> update=<us> spans=<us> loop=<us>
#
#   update  `state.update` — 라이브러리의 증분 복사(page 행 dirty만 다시 짓는다, design 결정 10)
#   spans   `findSpans` — 검색이 없으면 곧 돌아온다
#   loop    `shell_cursor` 계산부터 행 × 열 루프의 끝까지 — M3이 줄이려는 몫
#
# 패널마다 한 줄이라 패널 하나인 프로브 시나리오에서는 프레임마다 한 줄이고, 같은 프레임의 `probe>` 줄보다 앞에
# 온다(`cells()`는 그리기 안이다). 이 줄을 쓰는 비용은 `cells()` 안이라 `split>`의 `cells`와 `frame`에 든다 —
# 그래서 이 판에서는 세 구간의 합과 그 비율만 읽고, `frame` · `cells`의 절대값은 비교 판의 것을 쓴다.
#
# anchor가 정확히 한 번 나오지 않으면 멈춘다(`patch.pl`의 방법). 끝의 `return`은 함수 뒤의 주석 첫 줄까지 넣어
# 하나로 만든다 — 루프 안에도 `return out[0..n];`이 있다(버퍼가 찼을 때).
use strict;
use warnings;

my ($src, $dst) = @ARGV;
die "usage: cells.pl <vt.zig> <out>\n" unless defined $dst;

open my $in, '<', $src or die "read $src: $!\n";
my $text = do { local $/; <$in> };
close $in;

sub patch {
    my ($anchor, $replacement) = @_;
    my $count = () = $text =~ /\Q$anchor\E/g;
    die "anchor found $count times (want 1):\n$anchor\n" unless $count == 1;
    my $at = index $text, $anchor;
    substr($text, $at, length $anchor) = $replacement;
}

sub lap {
    my ($from, $name) = @_;
    return "const probe_$name = \@divTrunc($from.untilNow(self.io, .awake).nanoseconds, 1000);";
}

# (1) `update` 앞뒤.
my $update = "        try self.state.update(self.alloc, &self.term);\n";
patch($update,
      "        const probe_t0 = std.Io.Clock.now(.awake, self.io);\n"
    . $update
    . "        " . lap("probe_t0", "update") . "\n"
    . "        const probe_t1 = std.Io.Clock.now(.awake, self.io);\n");

# (2) `findSpans` 뒤.
my $spans = "        try self.findSpans();\n";
patch($spans,
      $spans
    . "        " . lap("probe_t1", "spans") . "\n"
    . "        const probe_t2 = std.Io.Clock.now(.awake, self.io);\n");

# (3) 함수 끝의 `return` 앞. 뒤따르는 `askedShape`의 주석 첫 줄까지가 anchor다.
my $tail = "        return out[0..n];\n"
         . "    }\n"
         . "\n"
         . "    /// 라이브러리가 든 커서 모양을 우리 셋으로 옮긴다(CU design 결정 1).\n";
patch($tail,
      "        " . lap("probe_t2", "loop") . "\n"
    . "        logline.print(\"terminal: cells> update={d} spans={d} loop={d}\\n\", .{ probe_update, probe_spans, probe_loop });\n"
    . $tail);

open my $out, '>', $dst or die "write $dst: $!\n";
print $out $text;
close $out;
print "wrote $dst\n";
