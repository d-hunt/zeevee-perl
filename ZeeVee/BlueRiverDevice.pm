# Perl module for interfacing to BlueRiver Devices using Aptovision API
package ZeeVee::BlueRiverDevice;
use Class::Accessor "antlers";

use warnings;
use strict;
use ZeeVee::Aptovision_API;
use Data::Dumper ();

has DeviceID => ( is => "ro" );
has Apto => ( is => "ro" );
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );
has AptoDevice =>  ( is => "rw" );

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
    $self->Apto->send( "get ".$self->DeviceID." hello" );
    $self->Apto->fence();
    $self->AptoDevice( pop @{$self->Apto->Results} );

    return;
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
