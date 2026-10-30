#!/usr/bin/env perl
# DR 진단 판을 만든다(DR-M0 plan 확정 1 · 2 · 3, anchor는 DR-M2 plan 확정 13의 것). `patch.pl`의 결과 위에
# 얹는다. 원본은 안 바꾼다.
#
#   perl probe/patch.pl terminal/src/main.zig /tmp/dr-probe/base.zig
#   perl probe/split.pl /tmp/dr-probe/base.zig /tmp/dr-probe/main.zig
#
# 그린 프레임마다 한 줄을 더 찍는다. 같은 프레임의 `probe>` 줄보다 앞에 온다.
#
#   terminal: split> others=<us> cells=<us> pane=<us> rows=<us> overlay=<us> finish=<us> present=<us>
#
#   others    화살표 되돌리기 · 통째 판정 · 포커스 아닌 패널들(각자의 `cells()`와 `paintPane`)
#   cells     포커스 패널의 `cells()`
#   pane      포커스 패널의 `paintPane` 전체 — `rowStarts` · `dirtyRows` · overlay 행 · 그리기 · clip
#   rows      그 안의 그리기만(`renderRows`, 통째 패널이면 `renderPane`). pane − rows가 행 비교의 몫이다
#   overlay   프롬프트(`drawPrompt`) · 상태 줄 띠(`paintBand` — SB-M0부터 바뀐 프레임에만 지우고 쓴다)
#   finish    그 뒤부터 `frame_us`까지 — clip 목록 · verify(프로브에서는 꺼져 있다) · 화살표 · `present`
#   present   그 안의 `fb.present(clips)`
#
# `frame`(probe> 줄)에서 다섯(others · cells · pane · overlay · finish)의 합을 뺀 나머지는 프롬프트 · 상태 줄
# 문자열 짓기와 `images()`다. 이 줄은 `frame_us`를 셈한 뒤에 찍으므로 `frame`에도 `dump`에도 안 들어가고,
# (b)의 `other`에는 들어간다 — 그래서 이 판의 (b)는 읽지 않는다.
#
# M0의 판(`backdrop` · `pane` · `finish` 여섯 구간)은 `git log -p probe/split.pl`에 있다 — `renderBackdrop`은
# 이제 통째 프레임에만 있어 (a)에서는 0이다. anchor는 DR-M2 HEAD의 `render` · `paintPane` · `presentFrame`
# 안에 있고, 정확히 한 번 나오지 않으면 멈춘다.
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

# (1) `present`는 자유 함수(`presentFrame`) 안이라 `self.io`가 없다. 파일 스코프에 io와 결과 칸을 둔다.
# `rows`도 파일 스코프다 — `paintPane`은 패널마다 불리므로 마지막 호출(포커스 패널)의 값이 남는다.
patch("const SEPARATOR: u32 = 0x00405060;\n",
      "const SEPARATOR: u32 = 0x00405060;\n"
    . "var probe_io: std.Io = undefined;\n"
    . "var probe_present_us: i96 = 0;\n"
    . "var probe_rows_us: i96 = 0;\n");

patch("    try fb.present(clips.slice());\n",
      "    const probe_p0 = std.Io.Clock.now(.awake, probe_io);\n"
    . "    try fb.present(clips.slice());\n"
    . "    probe_present_us = \@divTrunc(probe_p0.untilNow(probe_io, .awake).nanoseconds, 1000);\n");

# (2) `paintPane` 안의 그리기 둘. 어느 쪽이든 `probe_rows_us`에 담는다.
patch("            try renderPane(self.fb, &self.cache, cells, imgs, p.screen.defaultBg(), p.rect, cursor);\n",
      "            const probe_r0 = std.Io.Clock.now(.awake, self.io);\n"
    . "            try renderPane(self.fb, &self.cache, cells, imgs, p.screen.defaultBg(), p.rect, cursor);\n"
    . "            probe_rows_us = \@divTrunc(probe_r0.untilNow(self.io, .awake).nanoseconds, 1000);\n");
patch("            try renderRows(self.fb, &self.cache, cells, p.starts_buf[next], dirty, p.rect, cursor, strip);\n",
      "            const probe_r0 = std.Io.Clock.now(.awake, self.io);\n"
    . "            try renderRows(self.fb, &self.cache, cells, p.starts_buf[next], dirty, p.rect, cursor, strip);\n"
    . "            probe_rows_us = \@divTrunc(probe_r0.untilNow(self.io, .awake).nanoseconds, 1000);\n");

# (3) 그리기의 시작. `frame_start`와 같은 자리에서 표시를 잡는다.
patch("        const frame_start = std.Io.Clock.now(.awake, self.io);\n",
      "        const frame_start = std.Io.Clock.now(.awake, self.io);\n"
    . "        probe_io = self.io;\n"
    . "        var probe_mark = std.Io.Clock.now(.awake, self.io);\n");

# (4) 구간의 끝들. 들여쓰기는 anchor에 안 넣고 같은 줄 뒤나 앞에 붙인다.
patch("focus.screen.focused = true;",
      "focus.screen.focused = true; " . lap("others"));
# DR-M3부터 증분 호출이다(`cellsReuse`, plan 확정 9).
patch("frame.cells = try focus.screen.cellsReuse(focus.cells_buf[focus.shown ^ 1], prevOf(focus));",
      "frame.cells = try focus.screen.cellsReuse(focus.cells_buf[focus.shown ^ 1], prevOf(focus)); " . lap("cells"));
# `paintPane` 호출 앞에 표시를 다시 잡아 프롬프트 · 상태 줄 짓기와 `images()`를 `pane`에서 뺀다.
patch("try self.paintPane(focus, full, frame.cells, frame.imgs, frame.prompt != null, &clips);",
      "probe_mark = std.Io.Clock.now(.awake, self.io); "
    . "try self.paintPane(focus, full, frame.cells, frame.imgs, frame.prompt != null, &clips); " . lap("pane"));
# SB-M0부터 실제 경로는 프롬프트와 띠를 따로 부른다 — `overlay`는 둘의 합이고, 띠는 바뀐 프레임에만 그려진다.
patch("try paintBand(self.fb, &self.cache, frame.status_line, full or frame.status_changed, &clips);",
      "try paintBand(self.fb, &self.cache, frame.status_line, full or frame.status_changed, &clips); " . lap("overlay"));

# (5) `frame_us`를 셈하는 줄 앞뒤.
my $frame_us = "        frame.frame_us = \@divTrunc(frame_start.untilNow(self.io, .awake).nanoseconds, 1000);\n";
patch($frame_us,
      "        " . lap("finish") . "\n"
    . $frame_us
    . "        logline.print(\"terminal: split> others={d} cells={d} pane={d} rows={d} overlay={d} finish={d} present={d}\\n\", .{\n"
    . "            probe_others, probe_cells, probe_pane, probe_rows_us, probe_overlay, probe_finish, probe_present_us,\n"
    . "        });\n");

open my $out, '>', $dst or die "write $dst: $!\n";
print $out $text;
close $out;
print "wrote $dst\n";
