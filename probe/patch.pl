#!/usr/bin/env perl
# RS 프로브 판을 만든다(RS design 결정 2 · 3). 원본은 안 바꾼다.
#
#   perl probe/patch.pl terminal/src/main.zig /tmp/rs-probe/main.zig
#
# 프레임마다 한 줄을 더 찍는다.
#
#   terminal: probe> t=<us> frame=<us> dump=<us> reads=<n> bytes=<n>
#
#   t      터미널이 루프에 들어선 뒤의 시각. 시나리오 (b)의 처음과 끝을 이것으로 뺀다
#   frame  기존 `frame_us` 그대로 — 그리기 시작부터 `present` 뒤까지
#   dump   `frame_us` 뒤 덤프들(screen> · style> · ink> …)의 시간
#   reads  지난 프레임 뒤로 PTY를 읽은 횟수, bytes는 그 바이트 합
#
# anchor는 M1~M3이 고칠 자리(drm.zig · 그리기 함수 · present)를 피해 골랐다. 그래서
# milestone마다 같은 판이 붙는다. anchor가 정확히 한 번 나오지 않으면 멈춘다 — 원본이
# 바뀌면 조용히 어긋나지 않고 시끄럽게 실패한다(RC-M0의 방법).
#
# 이 줄 자체도 시리얼 한 줄이다. `t`로 재는 처리량(b)에는 그 비용이 들어가지만, 전후
# 모두 같은 판이라 비교에서 빠진다.
use strict;
use warnings;

my ($src, $dst) = @ARGV;
die "usage: patch.pl <main.zig> <out>\n" unless defined $dst;

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

# (1) 세는 값과 시계. `pty_buf`는 루프 앞, `main` 안이라 `init.io`가 보인다.
patch("    var pty_buf: [4096]u8 = undefined;\n",
      "    var pty_buf: [4096]u8 = undefined;\n"
    . "    var probe_reads: u32 = 0;\n"
    . "    var probe_bytes: usize = 0;\n"
    . "    const probe_clock = std.Io.Clock.now(.awake, init.io);\n");

# (2) PTY를 읽어 화면에 먹이는 자리는 하나다.
patch("            pane.screen.feed(out);\n",
      "            probe_reads += 1;\n"
    . "            probe_bytes += out.len;\n"
    . "            pane.screen.feed(out);\n");

# (3) 프레임의 마지막 덤프 뒤. 화살표만 고치는 갈래(`!needs_redraw`)에도 같은
# 호출이 있으므로 앞의 주석 줄까지 anchor에 넣는다.
my $tail = "        // 찍혔다고 읽는다(pointer/check.sh 검사 11).\n"
         . "        dumpPointerAt(fb, &pointer_state, round, &sprite, before_spot);\n";
patch($tail,
      $tail
    . "        {\n"
    . "            const probe_total = \@divTrunc(frame_start.untilNow(init.io, .awake).nanoseconds, 1000);\n"
    . "            const probe_t = \@divTrunc(probe_clock.untilNow(init.io, .awake).nanoseconds, 1000);\n"
    . "            logline.print(\"terminal: probe> t={d} frame={d} dump={d} reads={d} bytes={d}\\n\", .{\n"
    . "                probe_t, frame_us, probe_total - frame_us, probe_reads, probe_bytes,\n"
    . "            });\n"
    . "            probe_reads = 0;\n"
    . "            probe_bytes = 0;\n"
    . "        }\n");

open my $out, '>', $dst or die "write $dst: $!\n";
print $out $text;
close $out;
print "wrote $dst\n";
