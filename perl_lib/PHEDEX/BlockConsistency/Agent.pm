package PHEDEX::BlockConsistency::Agent;
use strict;
use warnings;
use base 'UtilsAgent', 'PHEDEX::BlockConsistency::SQL';

use File::Path;
use Data::Dumper;
use UtilsCommand;
use UtilsLogging;
use UtilsTiming;
use UtilsCatalogue;
use UtilsDB;
use DBI;
use UtilsRFIO;
use PHEDEX::BlockConsistency::Core;
use PHEDEX::Namespace;

our %params =
	(
	  DBH => undef,			# DB handle
	  DBCONFIG => undef,		# Database configuration file
	  NODES    => undef,		# Nodes to run this agent for
	  IGNORE_NODES => [],		# TMDB nodes to ignore
	  ACCEPT_NODES => [],		# TMDB nodes to accept
	  WAITTIME => 900 + rand(15),	# Agent activity cycle
	  DELETING => undef,		# Are we deleting files now?
	  PROTOCOL => 'direct',         # File access protocol
	  STORAGEMAP => undef,		# Storage path mapping rules
	  USE_SRM => 'n',		# Use SRM or native technology?
	  RFIO_USES_RFDIR => 0,		# Use rfdir instead of nsls?
	);

sub daemon
{
  my $self = shift;
  if ( defined($main::Interactive) && $main::Interactive )
  {
    print "Stub the daemon() call\n";

#   Can't do this, because daemon is called from the base class, before
#   the rest of me is initialised. Hence the messing around...
#   $self->{WAITTIME} = 2;
    my $x = ref $self;
    no strict 'refs';
    ${$x . '::params'}{WAITTIME} = 2;

    return;
  }

  my $me = $0; $me =~ s|.*/||;
  $self->SUPER::daemon($me);
}

sub new
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self = $class->SUPER::new(@_);
  my %args = (@_);
  map { $$self{$_} = $args{$_} || $params{$_} } keys %params;
  bless $self, $class;
  return $self;
}

sub AUTOLOAD
{
  my $self = shift;
  my $attr = our $AUTOLOAD;
  $attr =~ s/.*:://;
  if ( exists($params{$attr}) )
  {
    $self->{$attr} = shift if @_;
    return $self->{$attr};
  }
  return unless $attr =~ /[^A-Z]/;  # skip DESTROY and all-cap methods
  die "AUTOLOAD: Invalid attribute method: ->$attr()\n";
}

sub doSizeCheck
{
  my ($self, $drop, $request) = @_;
  my ($n_files,$n_tested,$n_ok);
  my $dbh = undef;
  my @nodes = ();

  print scalar localtime, ": doSizeCheck: starting\n";
  my $dropdir = "$$self{WORKDIR}/$drop";

  my $bcc = PHEDEX::BlockConsistency::Core->new ( DBH => $self->{DBH} );
  $bcc->Checks($request->{TEST}) or
    die "Test $request->{TEST} not known to ",ref($bcc),"!\n";

  my $ns = PHEDEX::Namespace->new
		(
			DBH		=> $self->{DBH},
			STORAGEMAP	=> $self->{STORAGEMAP},
			RFIO_USES_RFDIR	=> $self->{RFIO_USES_RFDIR},
		);

  if ( $request->{USE_SRM} eq 'y' )
  {
    $ns->protocol( 'srm' );
    $ns->TFCPROTOCOL( 'srm' );
  }
  else
  {
    my $technology = $bcc->Buffers(@{$self->{NODES}});
    $ns->technology( $technology );
  }

  print scalar localtime, ": doSizeCheck: Request ",$request->{ID},"\n";
  $n_files = $request->{N_FILES};
  my $t = time;
  foreach my $r ( @{$request->{LFNs}} )
  {
    my $pfn = $ns->lfn2pfn($r->{LOGICAL_NAME});
    if ( $request->{TEST} eq 'size' )
    {
      my $size = $ns->statsize($pfn);
      if ( defined($size) && $size == $r->{FILESIZE} ) { $r->{STATUS} = 'OK'; }
      else { $r->{STATUS} = 'Error'; }
    }
    elsif ( $request->{TEST} eq 'migration' )
    {
      my $mode = $ns->statmode($pfn);
      if ( defined($mode) && $mode ) { $r->{STATUS} = 'OK'; }
      else { $r->{STATUS} = 'Error'; }
    }
    $r->{TIME_REPORTED} = time();
    last unless --$n_files;
    if ( time - $t > 60 )
    {
      print scalar localtime,": $n_files files remaining\n";
      $t = time;
    }
  }

  eval
  {
    ($dbh,@nodes) = &expandNodesAndConnect($self);
    $n_tested = $n_ok = 0;
    $n_files = $request->{N_FILES};
    foreach my $r ( @{$request->{LFNs}} )
    {
      next unless $r->{STATUS};
      $self->setFileState($request->{ID},$r);
      $n_tested++;
      $n_ok++ if $r->{STATUS} eq 'OK';
    }
    $self->setRequestFilecount($request->{ID},$n_tested,$n_ok);
    if ( $n_files == 0 )
    {
      $self->setRequestState($request,'Indeterminate');
    }
    elsif ( $n_ok == $n_files )
    {
      $self->setRequestState($request,'OK');
    }
    elsif ( $n_tested == $n_files && $n_ok != $n_files )
    {
      $self->setRequestState($request,'Fail');
      &touch ("$dropdir/done");
      $self->relayDrop ($drop);
    }
    else
    {
      print "Hmm, what state should I set here? I have (n_files,n_ok,n_tested) = ($n_files,$n_ok,$n_tested) for request $request->{ID}\n";
    }
    $dbh->commit();
  };

  do
  {
    chomp ($@);
    &alert ("database error: $@");
    eval { $dbh->rollback() } if $dbh;
    return 0;
  } if $@;
    
  my $status = ( $n_files == $n_ok ) ? 1 : 0;
  return $status;
}

sub processDrop
{
  my ($self, $drop) = @_;
  my ($dropdir,$request,$bad,$r);

# Sanity checking
  return if (! $self->inspectDrop ($drop));
  delete $$self{BAD}{$drop};
  &timeStart($$self{STARTTIME});

  if ( ! defined $self->{DBH} )
  {
    &expandNodesAndConnect($self);
  }

# Read back file information
  $dropdir = "$$self{WORKDIR}/$drop";
  $request = do { no strict "vars"; eval &input ("$dropdir/packet") };
  $bad = 0;
  $bad = 1 if ($@ || !$request );

  if ( $request->{INJECT_ONLY} )
  {
#   This is an injection-drop.

    my $bcc = PHEDEX::BlockConsistency::Core->new( DBH => $self->{DBH} );
    foreach ( qw/ BLOCK N_FILES PRIORITY TEST TIME_EXPIRE NODE / )
    { $bad = 1 unless defined $request->{$_}; }

    if ( $bad )
    {
      &alert ("corrupt packet in $drop");
      return;
    }

#   Inject this test
    my $test = $self->get_TDVS_Tests($request->{TEST})->{ID};
    my $id = $bcc->InjectTest(
				node		=> $request->{NODE},
				test		=> $test,
				block		=> $request->{BLOCK},
				n_files		=> $request->{N_FILES},
				time_expire	=> $request->{TIME_EXPIRE},
				priority	=> $request->{PRIORITY},
			     );
    print "Inject request=$id for ",
	join(', ',map{"$_=>$request->{$_}"} sort keys %{$request}),"\n";
    &touch ("$dropdir/done");
    $self->relayDrop ($drop);
    return;
  }

# This is a normal drop
  foreach ( qw/ BLOCK N_FILES PRIORITY TEST TIME_EXPIRE LFNs ID / )
  { $bad = 1 unless defined $request->{$_}; }

  if ( $bad )
  {
    &alert ("corrupt packet in $drop for request $request->{ID}");

    $self->markBad ($drop);
    $self->setRequestState($request,'Rejected');
    $self->{DBH}->commit();
    return;
  }

  if ( $request->{TIME_EXPIRE} <= time() )
  {
    &touch ("$dropdir/done");
    $self->relayDrop ($drop);
    $self->setRequestState($request,'Expired');
    $self->{DBH}->commit();
    print scalar localtime, ": processDrop: return after Expiring $request->{ID}\n";
    return;
  }

  if ( $request->{TEST} eq 'size' )
  {
    $self->setRequestState($request,'Active');
    $self->{DBH}->commit();
    my $result = $self->doSizeCheck ($drop, $request);
    return if ! $result;
  }
  elsif ( $request->{TEST} eq 'migration' )
  {
    $self->setRequestState($request,'Active');
    $self->{DBH}->commit();
    my $result = $self->doSizeCheck ($drop, $request);
    return if ! $result;
  }
# elsif ( $request->{TEST} eq 'cksum' )
# {
# }
# elsif ( $request->{TEST} eq 'dbs' )
# {
# }
  else
  {
    $self->markBad($drop);
    $self->setRequestState($request,'Rejected');
    $self->{DBH}->commit();
    print scalar localtime, ": processDrop: return after Rejecting $request->{ID}\n";
    return;
  }

# Mark drop done so it will be nuked
  &touch ("$dropdir/done");

# OK, got far enough to nuke and log it
  $self->relayDrop ($drop);
}

# Get a list of pending requests
sub requestQueue
{
  my ($self, $limit, $mfilter, $mfilter_args, $ofilter, $ofilter_args) = @_;
  my (@requests,$sql,%p,$q,$q1,$n,$i);

  print scalar localtime, ": requestQueue: starting\n";
  my $now = &mytimeofday();

# Find all the files that we are expected to work on
  $n = 0;

  $sql = qq{
		select b.id, block, n_files, time_expire, priority,
		name test, use_srm
		from t_dvs_block b join t_dvs_test t on b.test = t.id
		join t_status_block_verify v on b.id = v.id
		where ${$mfilter}
		and status = 0
		${$ofilter}
		order by priority asc, time_expire asc
       };
  %p = (  %{$mfilter_args}, %{$ofilter_args} );
  $q = &dbexec($self->{DBH},$sql,%p);

  $sql = qq{ select logical_name, checksum, filesize, vf.fileid,
		nvl(time_reported,0) time_reported, nvl(status,0) status
		from t_dps_file pf join t_dvs_file vf on vf.fileid = pf.id
		left join t_dvs_file_result vfr on vfr.fileid = vf.fileid
		where vf.request = :request };
  while ( my $h = $q->fetchrow_hashref() )
  {
    %p = ( ':request' => $h->{ID} );
    $q1 = &dbexec($self->{DBH},$sql,%p);
    $h->{LFNs} = [];
    while ( my $g = $q1->fetchrow_hashref() )
    {
      push @{$h->{LFNs}}, $g;
    }
    $n += scalar @{$h->{LFNs}};
    push @requests, $h;
    last if ++$i >= $limit;
  }

  print scalar localtime,": Got ",scalar @requests," requests, for $n files in total\n";
  return @requests;
}

sub dropBoxName
{
# Derive a dropbox name for a request. Required to be alphabetically
# sorted to the same order that the requests should be processed in.
  my ($self,$request) = @_;
  my $b = sprintf("%08x_%08x_%010d",
                   $request->{PRIORITY},
                   $request->{TIME_EXPIRE},
                   $request->{ID}
                 );
  return $b;
}

# Create a drop for processing a request.  We create a drop for ourselves,
# i.e. in our own inbox, and then process the file in "processDrop".
# This way we have a permanent record of where we are with deleting
# the file, in case we have to give up some operation for temporary
# failures.
sub startOne
{
  my ($self, $request) = @_;

# Create a pending drop in my inbox
  my $drop = "$$self{DROPDIR}/inbox/" . $self->dropBoxName($request);
  do { &alert ("$drop already exists"); return 0; } if -d $drop;
  do { &alert ("failed to submit $$request{ID}"); &rmtree ($drop); return 0; }
	if (! &mkpath ($drop)
	  || ! &output ("$drop/packet", Dumper ($request))
	  || ! &touch ("$drop/go.pending"));

# OK, kick it go
  return 1 if &mv ("$drop/go.pending", "$drop/go");
  &warn ("failed to mark $$request{ID} ready to go");
  return 0;
}

# Pick up work from the database.
sub idle
{
  my ($self, @pending) = @_;
  my $dbh = undef;
  my @nodes = ();

  eval
  {
    ($dbh, @nodes) = &expandNodesAndConnect ($self);
    @nodes or die "No node found? Typo perhaps?\n";
    my ($mfilter, %mfilter_args) =    &myNodeFilter ($self, "b.node");
    my ($ofilter, %ofilter_args) = &otherNodeFilter ($self, "b.node");

#   Get a list of requests to process
    foreach my $request ($self->requestQueue(20, \$mfilter, \%mfilter_args,
						 \$ofilter, \%ofilter_args))
    {
      if ( $self->startOne ($request) )
      {
        $self->setRequestState($request,'Queued');
      }
      else
      {
        $self->setRequestState($request,'Error');
      }
    }
    $dbh->commit();
  };
  do { chomp ($@); &alert ("database error: $@");
  eval { $dbh->rollback() } if $dbh } if $@;

  # Wait for all jobs to finish
  while (@{$$self{JOBS}})
  {
    $self->pumpJobs();
    select (undef, undef, undef, 0.1);
  }

  # Disconnect from the database
  &disconnectFromDatabase ($self, $dbh);

  # Have a little nap
  print scalar localtime,": idle: sleep until ",
		scalar localtime(time+$self->{WAITTIME}),"\n";
  $self->nap ($$self{WAITTIME});
}

sub setFileState
{
# Change the state of a file-test in the database
  my ($self, $request, $result) = @_;
  my ($sql,%p,$q);
  return unless defined $result;

  $sql = qq{
	insert into t_dvs_file_result fr 
	(id,request,fileid,time_reported,status)
	values
	(seq_dvs_file_result.nextval,:request,:fileid,:time,
	 (select id from t_dvs_status where name like :status_name )
	)
       };
  %p = ( ':fileid'      => $result->{FILEID},
  	 ':request'     => $request,
         ':status_name' => $result->{STATUS},
         ':time'        => $result->{TIME_REPORTED},
       );
  $q = &dbexec($self->{DBH},$sql,%p);
}

sub setRequestFilecount
{
  my ($self,$id,$n_tested,$n_ok) = @_;
  my ($sql,%p,$q);

  $sql = qq{ update t_status_block_verify set n_tested = :n_tested,
		n_ok = :n_ok where id = :id };
  %p = ( ':n_tested' => $n_tested,
	 ':n_ok'     => $n_ok,
	 ':id'       => $id
       );
  $q = &dbexec($self->{DBH},$sql,%p);
}

sub setRequestState
{
# Change the state of a request in the database
  my ($self, $request, $state) = @_;
  my ($sql,%p,$q);
  my ($disconnect, $dbh, @nodes);
  return unless defined $request->{ID};
  if ( ! defined ($dbh = $self->{DBH} ) )
  {
print "Hmm, I have to connect...? (Request=$request->{ID}, state=$state)\n";
    ($dbh,@nodes) = &expandNodesAndConnect($self);
    $disconnect=1;
  }

  print scalar localtime,": Request=$request->{ID}, state=$state\n";

  $sql = qq{
	update t_status_block_verify sbv 
	set time_reported = :time,
	status = 
	 (select id from t_dvs_status where name like :state )
	where id = :id
       };
  %p = ( ':id'    => $request->{ID},
         ':state' => $state,
         ':time'  => time()
       );
  $q = &dbexec($dbh,$sql,%p);
  if ( $disconnect )
  {
#   commit and disconnect, since I was disconnected when I was called...
    $dbh->commit();
    &disconnectFromDatabase($self,$dbh);
  }
}

1;
