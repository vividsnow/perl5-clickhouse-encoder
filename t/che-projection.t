use strict;
use warnings;
use Test::More;
use ClickHouse::Encoder;

my $enc = ClickHouse::Encoder->new(columns => [[a => 'UInt32'], [b => 'String'], [c => 'UInt8']]);
my @rows = map { my @r = ('unused') x 12; @r[7, 2, 11] = ($_, "v$_", $_ + 1); \@r } 1 .. 4;
my $expected = $enc->encode([map { [$_->[7], $_->[2], $_->[11]] } @rows]);
my $got = eval { $enc->encode(\@rows, positions => [7, 2, 11]) };
is($@, '', 'projection accepted');
is($got, $expected, 'projection bytes');
my $target = 'prefix';
eval { $enc->encode_into(\$target, \@rows, positions => [7, 2, 11]) };
is($@, '', 'encode_into accepts projection');
is($target, 'prefix' . $expected, 'encode_into appends projected bytes');
my $handle_bytes = '';
open my $fh, '>', \$handle_bytes or die $!;
eval { $enc->encode_to_handle($fh, \@rows, positions => [7, 2, 11]) };
is($@, '', 'encode_to_handle accepts projection');
close $fh;
is($handle_bytes, $expected, 'handle gets projected bytes');
for my $bad (undef, {}, [1, 2], [1, 2, -1], [1, 2, 1.5], [1, 2, 'x'], [1, 2, '1e2'], [1, 2, '99999999999999999999999']) {
    eval { $enc->encode([], positions => $bad) };
    like($@, qr/positions/, 'invalid positions rejected for empty batch');
}
eval { $enc->encode([[], []], positions => [7, 2, 11]) };
like($@, qr/Row 0 .*columns.*12/, 'short projected row identifies row and size');
$got = eval { $enc->encode([[1, 'v', 1]], positions => [0, 1, 0]) };
is($got, $enc->encode([[1, 'v', 1]]), 'duplicate positions supported');

{
    package CHE::TiedArray;
    sub TIEARRAY { bless [@_[1 .. $#_]], $_[0] }
    sub FETCH { $_[0][$_[1]] }
    sub FETCHSIZE { scalar @{$_[0]} }
}
tie my @inner, 'CHE::TiedArray', (0 .. 39);
tie my @outer, 'CHE::TiedArray', \@inner;
my $wide = ClickHouse::Encoder->new(columns => [map { ["c$_", 'UInt32'] } 0 .. 32]);
my @positions = reverse 0 .. 32;
$got = eval { $wide->encode(\@outer, positions => \@positions) };
is($@, '', 'tied projection spans gather groups');
is($got, $wide->encode([[reverse 0 .. 32]]), 'tied fetch values survive grouped gather');
my @sparse;
$sparse[39] = 'end';
my $strings = ClickHouse::Encoder->new(columns => [[v => 'String'], [w => 'String']]);
$got = eval { $strings->encode([\@sparse], positions => [8, 39]) };
is($got, $strings->encode([['', 'end']]), 'holes in ordinary arrays retain undef coercion');

done_testing;
