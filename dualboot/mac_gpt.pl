#!/usr/bin/env perl
# DB-M0: 호스트가 "맥 디스크"의 GPT를 쓴다. 게이트 컨테이너(aarch64)에는 sfdisk가 없다 —
# 게스트의 sfdisk는 amd64 sysroot의 것이라 호스트에서 안 돈다. 그래서 GPT를 손으로 쓴다.
#
#   mac_gpt.pl <image> <type>:<first>:<last>:<name> ...
#
# image는 이미 원하는 크기로 있어야 한다(truncate). first · last는 512바이트 섹터의 LBA다.
# 쓰는 것은 GPT 규격(UEFI 2.x 5장)의 다섯 덩어리뿐이다 — 보호 MBR(LBA 0), 헤더(LBA 1),
# 엔트리 128개(LBA 2~33), 뒤의 엔트리 사본과 백업 헤더. 파티션 안은 안 건드린다.
# CRC가 틀리면 커널과 sfdisk가 백업으로 가거나 거절하므로, 게스트가 이 디스크를 읽는다는 것이
# 곧 이 스크립트가 맞다는 증명이다.
use strict;
use warnings;
use Compress::Zlib qw(crc32);

my ($img, @parts) = @ARGV;
die "usage: mac_gpt.pl <image> <type>:<first>:<last>:<name> ...\n" unless $img && @parts;

my %TYPES = (
  efi  => 'C12A7328-F81F-11D2-BA4B-00A0C93EC93B',
  apfs => '7C3457EF-0000-11AA-AA11-00306543ECAC',
  hfs  => '48465300-0000-11AA-AA11-00306543ECAC',
);

# GUID의 디스크 위 모양. 앞의 세 칸은 리틀엔디안, 뒤의 두 칸은 적힌 순서 그대로다.
sub guid {
  my @f = split /-/, shift;
  return pack('V v v', hex $f[0], hex $f[1], hex $f[2]) . pack('H4 H12', $f[3], $f[4]);
}

my $size = -s $img or die "mac_gpt: $img is empty\n";
my $lbas = int($size / 512);
my $last_lba = $lbas - 1;

# 엔트리 128개 × 128바이트 = 16KiB = 32섹터.
my $entries = "\0" x (128 * 128);
my $n = 0;
for my $p (@parts) {
  my ($type, $first, $last, $name) = split /:/, $p, 4;
  my $t = $TYPES{$type} or die "mac_gpt: unknown type $type\n";
  # 고유 GUID는 정해진 값이다. 게이트가 바이트를 비교하므로 매번 같아야 한다.
  my $uniq = guid(sprintf('DB00%04X-0000-4000-8000-0000000000%02X', $n + 1, $n + 1));
  my $nm = substr(pack('v*', map { ord } split //, $name) . ("\0" x 72), 0, 72);
  substr($entries, $n * 128, 128) = guid($t) . $uniq . pack('Q< Q< Q<', $first, $last, 0) . $nm;
  $n++;
}
my $entries_crc = crc32($entries);

sub header {
  my ($my_lba, $alt_lba, $entries_lba) = @_;
  my $h = 'EFI PART' . pack('V V V V', 0x00010000, 92, 0, 0)
    . pack('Q< Q< Q< Q<', $my_lba, $alt_lba, 34, $last_lba - 33)
    . guid('DB0DB0DB-0000-4000-8000-00000000DB00')
    . pack('Q< V V V', $entries_lba, 128, 128, $entries_crc);
  substr($h, 16, 4) = pack('V', crc32($h));
  return $h . ("\0" x (512 - 92));
}

# 보호 MBR. 파티션 하나(0xEE)가 LBA 1부터 디스크 끝(2TiB 넘으면 0xFFFFFFFF)까지다.
my $mbr = "\0" x 512;
my $count = $lbas - 1 > 0xFFFFFFFF ? 0xFFFFFFFF : $lbas - 1;
substr($mbr, 446, 16) = pack('C C C C C C C C V V', 0, 0, 2, 0, 0xEE, 0xFF, 0xFF, 0xFF, 1, $count);
substr($mbr, 510, 2) = "\x55\xAA";

open my $fh, '+<:raw', $img or die "mac_gpt: cannot open $img: $!\n";
sub put { my ($lba, $bytes) = @_; seek $fh, $lba * 512, 0 or die; print $fh $bytes or die; }
put(0, $mbr);
put(1, header(1, $last_lba, 2));
put(2, $entries);
put($last_lba - 32, $entries);
put($last_lba, header($last_lba, 1, $last_lba - 32));
close $fh or die;
