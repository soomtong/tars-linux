#!/usr/bin/env perl
# RS 프로브 판을 만든다(RS design 결정 2 · 3). 원본은 안 바꾼다.
#
#   perl probe/patch.pl terminal/src/main.zig /tmp/rs-probe/main.zig
#
# 프레임마다 한 줄을 더 찍는다.
#
#   terminal: probe> t=<us> frame=<us> dump=<us> reads=<n> bytes=<n>
#
#   t      터미널이 준비를 끝낸 뒤의 시각. 시나리오 (b)의 처음과 끝을 이것으로 뺀다
#   frame  기존 `frame_us` 그대로 — 그리기 시작부터 `present` 뒤까지
#   dump   덤프들(screen> · style> · ink> …)의 시간 — `dumpFrame`의 처음부터 끝까지
#   reads  지난 프레임 뒤로 PTY를 읽은 횟수, bytes는 그 바이트 합
#
# anchor는 M1~M3이 고칠 자리(drm.zig · 그리기 함수 · present)를 피해 골랐다. 그래서
# milestone마다 같은 판이 붙는다. anchor가 정확히 한 번 나오지 않으면 멈춘다 — 원본이
# 바뀌면 조용히 어긋나지 않고 시끄럽게 실패한다(RC-M0의 방법).
#
# MS-M0이 `main`을 `App`의 `open` · `tick` · 단계 함수로 나눈 뒤의 자리다. 바퀴를 넘어
# 사는 값이 필드가 됐으므로 세는 값과 시계도 필드로 더하고, 단계 함수 안에서는 `self.`로
# 부른다. MS 전의 판은 `git log -p probe/patch.pl`에 있다.
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

# (1) 세는 값과 시계. `App`의 `pty_buf` 필드 뒤에 필드 셋을 더하고, 시계의 원점은
# `openBattery`가 배터리 시계의 원점을 잡는 줄 뒤에서 같은 시각으로 잡는다 — 준비가
# 끝난 자리라 MS 전의 "루프 앞"과 같은 시점이다.
patch("    pty_buf: [4096]u8 = undefined,\n",
      "    pty_buf: [4096]u8 = undefined,\n"
    . "    probe_reads: u32 = 0,\n"
    . "    probe_bytes: usize = 0,\n"
    . "    probe_clock: std.Io.Timestamp = undefined,\n");
patch("        self.battery_clock = std.Io.Clock.now(.awake, self.io);\n",
      "        self.battery_clock = std.Io.Clock.now(.awake, self.io);\n"
    . "        self.probe_clock = std.Io.Clock.now(.awake, self.io);\n");

# (2) PTY를 읽어 화면에 먹이는 자리는 하나다(`readPanes`). 들여쓰기는 anchor에 안 넣는다 —
# RS-M2가 이 줄을 반복문 안으로 옮겼다. 같은 줄 앞에 붙이므로 들여쓰기가 무엇이든 맞는다.
patch("pane.screen.feed(out);",
      "self.probe_reads += 1; self.probe_bytes += out.len; pane.screen.feed(out);");

# (3) 덤프의 시작. `dumpFrame`이 `frame_us`를 꺼내는 줄 뒤에 시각을 잡는다. MS 전에는
# `frame_start`부터의 총 시간에서 `frame_us`를 뺐는데, 지금 `frame_start`는 `render`의
# 지역 변수라 덤프 쪽에서 안 보인다. 둘의 차이는 `renderFinish`와 첫 덤프 사이의 몇
# 마이크로초다.
patch("        const frame_us = frame.frame_us;\n",
      "        const frame_us = frame.frame_us;\n"
    . "        const probe_dump_start = std.Io.Clock.now(.awake, self.io);\n");

# (4) 프레임의 마지막 덤프 뒤. 화살표만 고치는 갈래(`decideFrame`)에도 같은 함수의 호출이
# 있으므로 앞의 주석 줄까지 anchor에 넣는다.
my $tail = "        // 찍혔다고 읽는다(pointer/check.sh 검사 11).\n"
         . "        dumpPointerAt(self.fb, &self.pointer_state, p.round, &self.sprite, p.before_spot);\n";
patch($tail,
      $tail
    . "        {\n"
    . "            const probe_dump = \@divTrunc(probe_dump_start.untilNow(self.io, .awake).nanoseconds, 1000);\n"
    . "            const probe_t = \@divTrunc(self.probe_clock.untilNow(self.io, .awake).nanoseconds, 1000);\n"
    . "            logline.print(\"terminal: probe> t={d} frame={d} dump={d} reads={d} bytes={d}\\n\", .{\n"
    . "                probe_t, frame_us, probe_dump, self.probe_reads, self.probe_bytes,\n"
    . "            });\n"
    . "            self.probe_reads = 0;\n"
    . "            self.probe_bytes = 0;\n"
    . "        }\n");

open my $out, '>', $dst or die "write $dst: $!\n";
print $out $text;
close $out;
print "wrote $dst\n";
