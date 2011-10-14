package PHEDEX::Web::API::UpdateSubscription;
use warnings;
use strict;
use URI::Escape;

=pod

=head1 NAME

PHEDEX::Web::API::UpdateSubscription -- change user_group, priority and/or time_suspend of a subscription

=head1 DESCRIPTION

Update user_group, priority and/or suspend_until of a existing subscription

=head2 Options

 required inputs: node, block/dataset, one or more of (user_group, priority, suspend_until)

 node              destination node name of the subscription
 block             block name
 dataset           dataset name
 group             user group
 priority          priority, either 'high', 'normal', or 'low'
 suspend_until     suspend until this time

 * only one node/block or node/dataset is allowed

=head2 Output

  <dataset>
    <subscription/>
    ...
    <block>
      <subscription/>
    </block>
    ...
  </dataset> 

  Dataset-level subscriptions will have <subscription> as a child of <dataset>
  Block-level subscriptions will have <subscription> as a child of <block> 

=head3 <subscription> attributes:

  node             PhEDEx node name which is subscribed to the parent
  node_id          PhEDEx node id
  se               storage element name
  level            the subscription level, 'dataset' or 'block'
  request          request ID
  node_files       number of files at this node
  node_bytes       number of bytes at this node
  priority         priority (high, normal, low)
  move             is move? y or n
  custodial        is custodial? y or n
  group            user group
  time_create      when the subscription was created
  suspended        is suspended? y or n
  suspend_until    time suspension expires 
  percent_files    percentage of files at destination
  percent_bytes    percentage of bytes at destination
  time_start       time when transfer started (only active transfers have start time)

=head3 <dataset> attributes:

  name             dataset name
  id               PhEDEx dataset id
  files            files in dataset
  bytes            bytes in dataset
  is_open          y or n, if dataset is open

=head3 <block> attributes:

  name             block name
  id               PhEDEx block id
  files            files in block
  bytes            bytes in block
  is_open          y or n, if block is open 

=cut


use PHEDEX::Web::SQL;
use PHEDEX::Core::Util;

# mapping format for the output
my $map = {
    _KEY => 'DATASET_ID',
    id => 'DATASET_ID',
    name => 'DATASET_NAME',
    is_open => 'OPEN',
    files => 'DS_FILES',
    bytes => 'DS_BYTES',
    subscription => {
        _KEY => 'NODE_ID',
        level => 'LEVEL',
        node => 'NODE',
        node_id => 'NODE_ID',
        node_files => 'NODE_FILES',
        node_bytes => 'NODE_BYTES',
        request => 'REQUEST',
        priority => 'PRIORITY',
        move => 'MOVE',
        custodial => 'CUSTODIAL',
        group => 'GROUP',
        time_create => 'TIME_CREATE',
        time_update => 'TIME_UPDATE',
        suspended => 'SUSPENDED',
        suspend_until => 'SUSPEND_UNTIL',
        percent_files => 'PERCENT_FILES',
        percent_bytes => 'PERCENT_BYTES',
        time_start => 'TIME_START'
    }
};

my $map2 = {
    _KEY => 'DATASET_ID',
    id => 'DATASET_ID',
    name => 'DATASET_NAME',
    is_open => 'OPEN',
    files => 'DS_FILES',
    bytes => 'DS_BYTES',
    block => {
        _KEY => 'ITEM_ID',
        id => 'ITEM_ID',
        name => 'ITEM_NAME',
        files => 'FILES',
        bytes => 'BYTES',
        is_open => 'OPEN',
        subscription => {
            _KEY => 'NODE_ID',
            level => 'LEVEL',
            node => 'NODE',
            node_id => 'NODE_ID',
            node_files => 'NODE_FILES',
            node_bytes => 'NODE_BYTES',
            request => 'REQUEST',
            priority => 'PRIORITY',
            move => 'MOVE',
            custodial => 'CUSTODIAL',
            group => 'GROUP',
            time_create => 'TIME_CREATE',
            time_update => 'TIME_UPDATE',
            suspended => 'SUSPENDED',
            suspend_until => 'SUSPEND_UNTIL',
            percent_files => 'PERCENT_FILES',
            percent_bytes => 'PERCENT_BYTES',
            time_start => 'TIME_START'
        }
    }
};

sub duration { return 0; } # no cache for update
sub need_auth { return 1; }
sub methods_allowed { return 'POST'; }
sub invoke { return update_subscription(@_); }

sub update_subscription
{
    my ($core, %h) = @_;

    $h{block}   = uri_unescape($h{block})   if $h{block};
    $h{dataset} = uri_unescape($h{dataset}) if $h{dataset};
    # convert parameter keys to upper case
    foreach ( qw / dataset block node group priority suspend_until / )
    {
      $h{uc $_} = delete $h{$_} if exists($h{$_});
    }

    # check authentication
    $core->{SECMOD}->reqAuthnCert();
    my $auth = $core->getAuth('datasvc_subscribe');
    if (! $auth->{STATE} eq 'cert' ) {
        die PHEDEX::Web::Util::http_error(401,"Certificate authentication failed\n");
    }

    my $r = PHEDEX::Web::SQL::updateSubscription($core, %h);

    # separate DATASET and BLOCK
    my (@dataset, @block);
    foreach (@{$r})
    {
        if ($_->{'ITEM_ID'} eq $_->{'DATASET_ID'})
        {
            push @dataset, $_;
	}
	else
        {
            push @block, $_;
        }
    }

    my $out = {};
    foreach(@dataset)
    {
        &PHEDEX::Core::Util::build_hash($map, $_, $out);
    }
    return { dataset => &PHEDEX::Core::Util::flat2tree($map2, \@block, $out) };
    # return { subscription => $r };
}

1;
