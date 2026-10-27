#!/usr/bin/env perl
# DR 진단 판을 만든다(DR-M0 plan 확정 1 · 2 · 3). `patch.pl`의 결과 위에 얹는다. 원본은 안 바꾼다.
#
#   perl probe/patch.pl terminal/src/main.zig /tmp/dr-probe/base.zig
#   perl probe/split.pl /tmp/dr-probe/base.zig /tmp/dr-probe/main.zig
#
# 그린 프레임마다 한 줄을 더 찍는다. 같은 프레임의 `probe>` 줄보다 앞에 온다.
#
#   terminal: split> backdrop=<us> others=<us> cells=<us> pane=<us> finish=<us> present=<us>
#
#   backdrop  `renderBackdrop` — fb 전체 `fill`과 구분선
#   others    포커스 아닌 패널들(각자의 `cells()`와 `renderPane`)
#   cells     포커스 패널의 `cells()`
#   pane      포커스 패널의 `renderPane`
#   finish    `renderFinish` — 프롬프트 · 상태 줄 · 화살표 · `present`
#   present   그 안의 `fb.present()`
#
# `frame`(probe> 줄)에서 여섯의 합(present는 finish 안이라 빼고)을 뺀 나머지는 프롬프트 · 상태 줄 문자열
# 짓기와 `images()`다. 이 줄은 `frame_us`를 셈한 뒤에 찍으므로 `frame`에도 `dump`에도 안 들어가고, (b)의
# `other`에는 들어간다 — 그래서 이 판의 (b)는 읽지 않는다.
#
# anchor는 DR-M2가 고칠 자리(`render` · `renderFinish`) 안에 있다. M0의 HEAD에만 붙으면 된다 — 비교 판인
# `patch.pl`과 반대다. anchor가 정확히 한 번 나오지 않으면 멈춘다.
use strict;
use warnings;

my ($src, $dst) = @ARGV;
die "usage: split.pl <patched main.zig> <out>\n" unless defined $dst;

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

# 구간 하나를 끝내는 문장. 표시 시각부터의 마이크로초를 `$name`에 담고 표시를 다시 잡는다.
sub lap {
    my ($name) = @_;
    return "const probe_$name = \@divTrunc(probe_mark.untilNow(self.io, .awake).nanoseconds, 1000); "
         . "probe_mark = std.Io.Clock.now(.awake, self.io);";
}

# (1) `present`는 자유 함수(`renderFinish`) 안이라 `self.io`가 없다. 파일 스코프에 io와 결과 칸을 둔다.
patch("const SEPARATOR: u32 = 0x00405060;\n",
      "const SEPARATOR: u32 = 0x00405060;\n"
    . "var probe_io: std.Io = undefined;\n"
    . "var probe_present_us: i96 = 0;\n");

patch("    try fb.present();\n",
      "    const probe_p0 = std.Io.Clock.now(.awake, probe_io);\n"
    . "    try fb.present();\n"
    . "    probe_present_us = \@divTrunc(probe_p0.untilNow(probe_io, .awake).nanoseconds, 1000);\n");

# (2) 그리기의 시작. `frame_start`와 같은 자리에서 표시를 잡는다.
patch("        const frame_start = std.Io.Clock.now(.awake, self.io);\n",
      "        const frame_start = std.Io.Clock.now(.awake, self.io);\n"
    . "        probe_io = self.io;\n"
    . "        var probe_mark = std.Io.Clock.now(.awake, self.io);\n");

# (3) 구간의 끝들. 들여쓰기는 anchor에 안 넣고 같은 줄 뒤나 앞에 붙인다.
patch("renderBackdrop(self.fb, &ws.tree, self.whole);",
      "renderBackdrop(self.fb, &ws.tree, self.whole); " . lap("backdrop"));
patch("focus.screen.focused = true;",
      "focus.screen.focused = true; " . lap("others"));
patch("frame.cells = try focus.screen.cells(self.cell_buf);",
      "frame.cells = try focus.screen.cells(self.cell_buf); " . lap("cells"));
# `renderPane` 호출 앞에 표시를 다시 잡아 프롬프트 · 상태 줄 짓기와 `images()`를 `pane`에서 뺀다.
patch("try renderPane(self.fb, &self.cache, frame.cells,",
      "probe_mark = std.Io.Clock.now(.awake, self.io); try renderPane(self.fb, &self.cache, frame.cells,");
patch("frame.prompt_ink = try renderFinish(",
      lap("pane") . " frame.prompt_ink = try renderFinish(");

# (4) `renderFinish` 바로 뒤, `frame_us`를 셈하는 줄 앞뒤.
my $frame_us = "        frame.frame_us = \@divTrunc(frame_start.untilNow(self.io, .awake).nanoseconds, 1000);\n";
patch($frame_us,
      "        " . lap("finish") . "\n"
    . $frame_us
    . "        logline.print(\"terminal: split> backdrop={d} others={d} cells={d} pane={d} finish={d} present={d}\\n\", .{\n"
    . "            probe_backdrop, probe_others, probe_cells, probe_pane, probe_finish, probe_present_us,\n"
    . "        });\n");

open my $out, '>', $dst or die "write $dst: $!\n";
print $out $text;
close $out;
print "wrote $dst\n";
