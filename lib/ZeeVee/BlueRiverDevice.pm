# Perl module for interfacing to BlueRiver Devices using Aptovision API
package ZeeVee::BlueRiverDevice;
use Class::Accessor "antlers";

use warnings;
use strict;
use ZeeVee::Aptovision_API;
use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );
use Storable ();

has DeviceID => ( is => "ro" );
has Apto => ( is => "ro" );
has Timeout => ( is => "ro" );
has VideoTimeout => ( is => "ro" );
has Debug => ( is => "ro" );
has AptoDevice =>  ( is => "rw" );
has AptoNetStat => ( is => "rw" );

# Constructor for BlueRiverDevice object.
sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};

    unless( exists $arg_ref->{'DeviceID'} ) {
	die "BlueRiverDevice can't work without a target deviceID.";
    }
    unless( exists $arg_ref->{'Apto'} ) {
	warn "BlueRiverDevice isn't likely to work without a functional Aptovision_API.  "
	    ."Trying with defaults anyway.";
	$arg_ref->{'Apto'} =
	    new ZeeVee::Aptovision_API( {} );
    }
    unless( exists $arg_ref->{'Timeout'} ) {
	$arg_ref->{'Timeout'} = 10;
    }
    unless( exists $arg_ref->{'VideoTimeout'} ) {
	$arg_ref->{'Timeout'} = 20;
    }
    unless( exists $arg_ref->{'Debug'} ) {
	$arg_ref->{'Debug'} = 0;
    }

    my $self = $class->SUPER::new( $arg_ref );

    $self->initialize();

    return $self;
}


# Initialize connection for sanity.
sub initialize($) {
    my $self = shift;

    # Get and store shadow copy of state.
    $self->poll();
    $self->poll_netstat();

    return;
}


# Poll for device status/settings and store in internal shadow.
# Returns the result hash reference too.
sub poll($) {
    my $self = shift;

    # Get and store shadow copy of state.
    $self->Apto->send( "get ".$self->DeviceID." device" );
    $self->Apto->fence();
    $self->AptoDevice( pop @{$self->Apto->Results} );

    return $self->AptoDevice();
}


# Poll and filter for relevant events on this device.
# Return array of event_ids.
sub poll_events($$) {
    my $self = shift;
    my $event_type = shift;

    my @event_ids = ();

    $self->Apto->poll();

    # Go through events in numerical order
    foreach my $event_id (sort keys %{$self->Apto->Events}) {
	my $event = $self->Apto->Events->{$event_id};
	if( ($event->{'event_type'} eq "$event_type")
	    && ($event->{'device_id'} eq $self->DeviceID) ) {
	    push @event_ids, $event_id;
	}
    }

    return @event_ids;
}


# Poll for network statistics and store in internal shadow.
# Returns the result hash reference too.
sub poll_netstat($) {
    my $self = shift;

    # Get and store shadow copy of network status.
    $self->Apto->send( "netstat ".$self->DeviceID." read" );
    $self->Apto->fence();
    $self->AptoNetStat( pop @{$self->Apto->Results} );

    return $self->AptoNetStat();
}

# Request a list of event_ids
# Return array of their results.
sub request_events($\@) {
    my $self = shift;
    my $event_ids = shift;

    my @results = ();

    # Go through events in numerical order
    foreach my $event_id (@{$event_ids}) {
	my $event = $self->Apto->Events->{$event_id};
	# Grab the result from this request and clear event.
	$self->Apto->prepare($event_id);
	$self->Apto->send( "request ".$event->{'request_id'}."" );
	my $result = pop @{$self->Apto->Results};
	push @results, $result;
	$self->Apto->forget($event_id);
    }

    return @results;
}


# Check if this device is currently connected/active.
sub is_connected($) {
    my $self = shift;

    $self->poll();

    return $self->__is_connected();
}


# Internal (no poll) check if this device is currently connected/active.
sub __is_connected($) {
    my $self = shift;

    my $error_count = scalar @{$self->AptoDevice()->{'error'}};
    return 0 unless($error_count == 0);

    foreach my $device ( @{$self->AptoDevice->{'devices'}} ) {
	return 0 unless($device->{'status'}->{'active'});
    }

    return 1;
}


# Check this device's core temperature.
sub temperature($) {
    my $self = shift;

    $self->poll();

    return $self->__temperature();
}


# Internal (no poll) check this device's temperature.
sub __temperature($) {
    my $self = shift;

    my $temperature = undef;
    foreach my $device ( @{$self->AptoDevice->{'devices'}} ) {
	die "Can't handle more than one temperature."
	    if( defined($temperature) );
	$temperature = $device->{'status'}->{'temperature'}
    }

    return $temperature;
}


# Use 'send' command to send this device RS232 or infrared data.
sub send($$$) {
    my $self = shift;
    my $port = shift;
    my $data = shift;

    $self->Apto->send( "send ".$self->DeviceID." $port $data" );
    pop @{$self->Apto->Results}; # Discard.

    # Now wait for the commands to complete, ignoring return values.
    $self->Apto->fence_ignore();

    return 1;
}


# Send 'set ... property' command to this device.
sub set_property($$$) {
    my $self = shift;
    my $key = shift;
    my $value = shift;

    $self->Apto->send( "set ".$self->DeviceID." property $key $value" );

    # Now wait for the commands to complete, ignoring return values.
    $self->Apto->fence_ignore();

    return 1;
}


# Send 'start' command to start a stream from this device.
sub start($$$) {
    my $self = shift;
    my $source = shift // "";
    my $multicast_ip = shift // "";

    $self->Apto->send( "start ".$self->DeviceID.":$source $multicast_ip" );

    # Now wait for the commands to complete, ignoring return values.
    $self->Apto->fence_ignore();

    return 1;
}


# Send 'join' command to start receiving a stream at this device.
sub join($$$$) {
    my $self = shift;
    my $source = shift;
    my $destination = shift // "";
    my $mode_parameters = shift // "";

    if( $destination ) {
	$self->Apto->send( "join $source ".$self->DeviceID.":$destination $mode_parameters" );
    } else {
	$self->Apto->send( "join $source ".$self->DeviceID.":$destination $mode_parameters" );
    }

    # Now wait for the commands to complete, ignoring return values.
    $self->Apto->fence_ignore();

    return 1;
}


# Send 'leave' command to stop receiving a stream at this device.
sub leave($) {
    my $self = shift;
    my $type_index = shift;

    # Construct command.
    my $command = "leave ".$self->DeviceID;
    $command .= ":".$type_index
	if( defined($type_index) );

    $self->Apto->send( $command );

    # Now wait for the commands to complete, ignoring return values.
    $self->Apto->fence_ignore();

    return 1;
}


# Send 'switch' command to set stream destination for a source from this device.
sub switch($$$) {
    my $self = shift;
    my $source = shift;
    my $destination = shift;

    $self->Apto->send( "switch ".$self->DeviceID.":$source $destination" );

    # Now wait for the commands to complete, ignoring return values.
    $self->Apto->fence_ignore();

    return 1;
}

# Find and return an array of nodes or a single node by type.
# Parameters: A list of 1 or more types to match.
sub get_node_by_type($;@) {
    my $self = shift;
    my @types = ();

    while( my $type = shift ) {
	push @types, $type;
    }

    my @nodes = ();

    # Refresh self-view...
    $self->poll();

    foreach my $device ( @{$self->AptoDevice->{'devices'}} ) {
	foreach my $node ( @{$device->{'nodes'}} ) {
	    foreach my $type ( @types ) {
		if( $node->{'type'} =~ $type ) {
		    push @nodes, $node;
		    last; # Only add each node once.
		}
	    }
	}
    }

    # Called in void context
    return unless defined(wantarray());

    # Called in list context
    return @nodes if wantarray();

    # Called in scalar context
    return undef if scalar(@nodes == 0);
    return $nodes[0] if scalar(@nodes == 1);

    # Called in scalar context, but found multiple nodes!
    die("More than one matching node found when called in scalar context.");
}

# Get and return HDMI video status from the first HDMI node found...
# Optional argument requires the video up or down; loops until timeout.
sub hdmi_status($$) {
    my $self = shift;
    my $expect_stable = shift;

    # FIXME: The "source_stable" flag isn't stable.  It gets hung "false."  Using a workaround for now.

    my $hdmi_status = undef;
    my $start_time = time();

    do{
	$hdmi_status = undef;

	my $node = $self->get_node_by_type('HDMI_ENCODER', 'HDMI_DECODER');
	if( defined($node) ) {
	    $hdmi_status = $node->{'status'};
	}
	die "Timeout on waiting for desired video source stability $expect_stable."
	    if( $self->VideoTimeout() < (time() - $start_time) );
	sleep 0.5;
    } until( !defined($expect_stable)
	     || ( $expect_stable 
		  && ($hdmi_status->{'video'}->{'height'} > 0) 
		  && ($hdmi_status->{'video'}->{'height'} <= 4096) )
	     || ( !$expect_stable
		  && !( ($hdmi_status->{'video'}->{'height'} > 0) 
			&& ($hdmi_status->{'video'}->{'height'} <= 4096) ) ));


    ## FIXME: was    || ($expect_stable == $hdmi_status->{'source_stable'}) );

    return $hdmi_status;
}

# Get and return HDMI Monitor status from the first HDMI_MONITOR node found...
# Optional argument requires the monitor connected/disconnected; loops until timeout.
sub monitor_status($$) {
    my $self = shift;
    my $expect_connected = shift;

    my $monitor_status = undef;
    my $start_time = time();

    do{
	$monitor_status = undef;

	my $node = $self->get_node_by_type('HDMI_MONITOR');
	if( defined($node) ) {
	    $monitor_status = $node->{'status'};
	}
	die "Timeout on waiting for desired monitor connection $expect_connected."
	    if( $self->VideoTimeout() < (time() - $start_time) );
	sleep 0.5;
    } until( !defined($expect_connected)
	     || ( $expect_connected == $monitor_status->{'connected'} ) );

    return $monitor_status;
}

# Get and return Icron USB card status from the first ICRON node found...
sub icron_status($) {
    my $self = shift;

    my $icron_status = undef;

    # Matches both _LOCAL and _REMOTE types.
    my $node = $self->get_node_by_type('USB_ICRON');
    if( defined($node) ) {
	$icron_status = $node->{'status'};
    }

    return $icron_status;
}

# Get and return Uptime (In netstat)
sub uptime($) {
    my $self = shift;

    # Refresh self-view...
    $self->poll_netstat();

    return $self->__uptime();
}


# Internal (no poll) get and return Uptime (In netstat)
sub __uptime($) {
    my $self = shift;

    my $uptime = undef;
    foreach my $device ( @{$self->AptoNetStat->{'statistics'}} ) {
	die "Can't handle more than one device."
	    if( defined($uptime) );
	$uptime = $device->{'device_up_time'}
    }

    return $uptime;
}


# Clear network statistics.
sub network_status_clear($) {
    my $self = shift;

    $self->Apto->send( "netstat ".$self->DeviceID." clear" );
    $self->Apto->fence();
    my $result = pop @{$self->Apto->Results};

    foreach my $error ( @{$result->{'error'}} ) {
	if( $error->{'device_id'} eq $self->DeviceID ) {
	    warn "Got error while clearing network statistics:\n"
		. "    " . $error->{'reason'} . " : " . $error->{'message'}
	}
    }

    # Refresh self-view of cleared stats.
    $self->poll_netstat();

    return;
}


# Select network statistics (bandwidth).
# Optional Parameter: a string: comma-separated list of bandwidth channels.
# Most useful are: all, none (default), total.
sub network_status_select($$) {
    my $self = shift;
    my $select_list = shift // 'none';

    $self->Apto->send( "netstat ".$self->DeviceID." select ".$select_list );
    $self->Apto->fence();
    my $result = pop @{$self->Apto->Results};

    foreach my $error ( @{$result->{'error'}} ) {
	if( $error->{'device_id'} eq $self->DeviceID ) {
	    warn "Got error while selecting network statistics:\n"
		. "    " . $error->{'reason'} . " : " . $error->{'message'}
	}
    }

    return;
}


# Get and return Network statistics.
sub network_status_read($) {
    my $self = shift;
    my %stats = ();

    # Refresh self-view...
    $self->poll_netstat();

    # Reorganize to a hash-of-hashes.
    foreach my $device ( @{$self->AptoNetStat->{'statistics'}} ) {
	die "Can't handle more than one device."
	    unless( $device->{'device_id'} eq $self->DeviceID );
	foreach my $datapath ( @{$device->{'data_paths'}} ) {
	    my %statscopy = %{Storable::dclone($datapath)};
	    my $type = $statscopy{'type'};
	    delete($statscopy{'type'});
	    die "This is new.  Can't handle more than one port."
		unless($statscopy{'index'} == 0 );
	    delete($statscopy{'index'});
	    $stats{$type} = \%statscopy;
	}
    }

    return %stats;
}

# Reboot Device and wait for it come back up.
sub reboot($) {
    my $self = shift;

    $self->Apto->send( "reboot ".$self->DeviceID."" );

    # Now wait for the commands to complete, ignoring return values.
    $self->Apto->fence_ignore();

    die "FIXME: Not implemented 'reboot ID'.  Not waiting for device to come back.";
    return 1;
}


# Revert Device to factory defaults.
sub factoryDefault($) {
    my $self = shift;

    $self->Apto->send( "factory ".$self->DeviceID."" );

    # Now wait for the commands to complete, ignoring return values.
    $self->Apto->fence_ignore();

    die "FIXME: Not implemented 'factory ID'  Not waiting for device to come back.";
    return 1;
}


1;
