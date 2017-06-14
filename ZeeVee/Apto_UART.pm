# Perl module for speaking to Aptovision API
package ZeeVee::Apto_UART;
use Class::Accessor "antlers";

use warnings;
use strict;
use ZeeVee::Aptovision_API;
use String::Escape qw(backslash unbackslash);
use Data::Dumper ();

has Device => ( is => "ro" );
has Apto => ( is => "ro" );
has Host => ( is => "ro" );
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );
has Buffer => ( is => "rw" );

# Constructor for UART object.
sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};
    
    unless( exists $arg_ref->{'Device'} ) {
	die "UART can't work without a target device.";
    }
    unless( exists $arg_ref->{'Apto'} ) {
	warn "UART isn't likely to work without a functional Aptovision_API.  "
	    ."Trying with defaults anyway.";
	$arg_ref->{'Apto'} =
	    new ZeeVee::Aptovision_API( {} );
    }
    unless( exists $arg_ref->{'Host'} ) {
	$arg_ref->{'Host'} = $arg_ref->{'Apto'}->Host();
    }
    unless( exists $arg_ref->{'Timeout'} ) {
	$arg_ref->{'Timeout'} = 10;
    }
    unless( exists $arg_ref->{'Debug'} ) {
	$arg_ref->{'Debug'} = 0;
    }

    $arg_ref->{'Buffer'} = "";
    
    my $self = $class->SUPER::new( $arg_ref );

    $self->initialize();
    
    return $self;
}


# Initialize the UART over Aptovision
sub initialize($) {
    my $self = shift;

    # Init for RS-232 access to add-in card.  Sending RX back to API server.
    my @cmds = ( "switch ".$self->Device.":RS232:1 ".$self->Host."",
		 "set ".$self->Device." property nodes[UART:1].configuration.baud_rate 9600",
	);

    # Pipeline commands first.
    foreach my $cmd (@cmds) { 
	$self->Apto->send( $cmd );
	pop @{$self->Apto->Results}; # Discard.
    }

    # Now wait for the commands to complete, ignoring return values.
    $self->Apto->fence_ignore();

    return;
}


# Transmits strings.
sub transmit($$) {
    my $self = shift;
    my $tx = shift;
    my $tx_escaped = "";

    $tx_escaped = backslash($tx);
    print "Escaped string to transmit: '$tx_escaped'\n"
	if( $self->Debug > 1 );    
    
    $self->Apto->send( "send ".$self->Device." RS232:1 ".$tx_escaped."" );
    pop @{$self->Apto->Results}; # Discard.

    # Now wait for the commands to complete, ignoring return values.
    $self->Apto->fence_ignore();

    return;
}


# Receive strings.
sub receive($) {
    my $self = shift;
    my $rx = "";
    my $rx_escaped = "";
    
    $self->Apto->poll();
    
    # Go through events in numerical order
    foreach my $event_id (sort keys %{$self->Apto->Events}) {
	my $event = $self->Apto->Events->{$event_id};
	if( ($event->{'event_type'} eq "RS232_RECEIVED")
	    && ($event->{'device_id'} eq $self->Device) ) {
	    
	    # Grab the data from request and clear event.
	    $self->Apto->prepare($event_id);
	    $self->Apto->send( "request ".$event->{'request_id'}."" );
	    my $result = pop @{$self->Apto->Results};
	    foreach my $rs232obj (@{$result->{'rs232'}}) {
		$rx_escaped .= $rs232obj->{'rs232_data'};
	    }
	    $self->Apto->forget($event_id);
	}
    }
    
    print "Escaped string received: '$rx_escaped'\n"
	if( $self->Debug > 1 );    
    $rx = unbackslash($rx_escaped);
    
    return $rx;
}

1;
