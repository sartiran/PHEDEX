package PHEDEX::Core::Timing;

=head1 NAME

PHEDEX::Core::Timing - a drop-in replacement for Toolkit/UtilsTiming

=cut

use strict;
use warnings;
use base 'Exporter';
our @EXPORT = qw(timeStart elapsedTime formatElapsedTime mytimeofday);
use Time::HiRes 'gettimeofday';

# High-resolution timing.
sub mytimeofday
{
    return scalar (&gettimeofday());
}

sub timeStart
{
    my ($array) = @_;
    @$array = (&mytimeofday, times);
}

sub elapsedTime 
{
    my ($start) = @_;
    my @now = (&mytimeofday, times);
    my @old = @$start;
    return ($now [0] - $old [0], $now[3] - $old [3], $now[4] - $old [4]);
}

sub formatElapsedTime
{
    return sprintf ("%.2fr %.2fu %.2fs", &elapsedTime(@_));
}

1;
