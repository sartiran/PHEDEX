package UtilsMisc; use strict; use warnings; use base 'Exporter';
our @EXPORT = qw(sizeValue);
sub sizeValue
{
    my ($value) = @_;
    if ($value =~ /^(\d+)([kMGT])$/)
    {
        my %scale = ('k' => 1024, 'M' => 1024**2, 'G' => 1024**3, 'T' => 1024**4);
        $value = $1 * $scale{$2};
    }
    return $value;
}

print STDERR "WARNING:  use of Common/UtilsMisc.pm is depreciated.  Update your code to use the PHEDEX perl library!\n";
1;
