package UtilsDownloadGlobus; use strict; use warnings; use base 'UtilsDownloadCommand';

# Command back end defaulting to Globus tools.
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $master = shift;

    # Get derived class arguments and defaults
    my $options = shift || {};
    my $params = shift || {};

	# Set my defaults where not defined by the derived class.
    my @defcmd = qw(globus-url-copy -p 5 -tcp-bs 2097152);
	$$params{PROTOCOLS}   ||= [ 'gsiftp' ]; # Accepted protocols
	$$params{COMMAND}     ||= [ @defcmd ];  # Transfer command
	$$params{NJOBS}       ||= 5;            # Max number of parallel transfers

    # Initialise myself
    my $self = $class->SUPER::new($master, $options, $params, @_);
    bless $self, $class;
    return $self;
}

print STDERR "WARNING:  use of Common/UtilsDownloadGlobus.pm is depreciated.  Update your code to use the PHEDEX perl library!\n";
1;
