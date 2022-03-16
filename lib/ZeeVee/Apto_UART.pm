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
has Configuration => ( is => "rw" );

# Constructor for UART object.
sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};

    unless( exists $arg_ref->{'Device'} ) {
	die "UART can't work without a target device.";
    }
    unless( exists $arg_ref->{'Device'}->{'Apto'} ) {
	die "UART can't work without a functional Aptovision_API.";
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

    # Locally alias the Aptovision API for now.
    $arg_ref->{'Apto'} = $arg_ref->{'Device'}->{'Apto'};

    $arg_ref->{'Buffer'} = "";

    $arg_ref->{'Configuration'} = {};

    my $self = $class->SUPER::new( $arg_ref );

    $self->initialize();

    return $self;
}


# Initialize the UART over Aptovision
sub initialize($$$) {
    my $self = shift;
    my $baudrate = shift // 9600;
    my $mode = shift // "8N1"; # 8N1 unless specified.

    my ($data_bits, $parity, $stop_bits) = ( $mode =~ /^([678])([NOE])([12])$/ )
	or die "Mode not implemented by Aptovision: $mode";

    $parity = 'NONE' if($parity eq 'N');
    $parity = 'ODD'  if($parity eq 'O');
    $parity = 'EVEN' if($parity eq 'E');

    # Init for RS-232 access to add-in card.  Sending RX back to API server.
    $self->Device->switch("RS232:1", $self->Host);

    # Transmitted to the device.  Also shadows config.
    $self->configure( { 'baud_rate'     => $baudrate,
			    'data_bits' => $data_bits,
			    'parity'    => $parity,
			    'stop_bits' => $stop_bits,
		      } );
    return;
}


# Apply configuration of the UART settings over Aptovision
# Also shadows configuration
# Arguments: Hash-ref with Configuration parameters to change.  Other parameters unchanged.
# Returns: Resulting Configuration as shadowed.
sub configure($\%) {
    my $self = shift;
    my $change_ref = shift // {};

    foreach my $key ( sort keys %{$change_ref} ) {
	my $value = $change_ref->{$key};
	# Configuration as transmitted to the device.  It's easier to shadow than query.
	$self->Configuration->{$key} = $value;
	$self->Device->set_property("nodes[UART:1].configuration.$key", "$value");
    }

    return $self->Configuration();
}


# Sets baud rate.
sub set_baud_rate($$) {
    my $self = shift;
    my $baudrate = shift;

    # Only change baud rate.  Leave everything else unchanged.
    $self->configure( {'baud_rate' => $baudrate } );

    return;
}


# Gets baud rate.
sub get_baud_rate($) {
    my $self = shift;
    my $baudrate = 0;

    $self->initialize($baudrate);

    return $baudrate;
}


# Transmits strings.
sub transmit($$) {
    my $self = shift;
    my $tx = shift;
    my $tx_escaped = "";

    $tx_escaped = backslash($tx);
    print "Escaped string to transmit: '$tx_escaped'\n"
	if( $self->Debug > 1 );

    $self->Device->send( "RS232:1", $tx_escaped );

    return;
}


# Receive strings.
sub receive($) {
    my $self = shift;
    my $rx = "";
    my $rx_escaped = "";

    my @event_ids = $self->Device->poll_events("RS232_RECEIVED");
    my @results = $self->Device->request_events(\@event_ids);

    foreach my $result (@results) {
	foreach my $rs232obj (@{$result->{'rs232'}}) {
	    $rx_escaped .= $rs232obj->{'rs232_data'};
	}
    }

    print "Escaped string received: '$rx_escaped'\n"
	if( $self->Debug > 1 );
    $rx = unbackslash($rx_escaped);

    return $rx;
}

1;
