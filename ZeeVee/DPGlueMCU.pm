# Perl module for speaking to Charlie DisplayPort Output Glue MCU.
package ZeeVee::DPGlueMCU;
use Class::Accessor "antlers";

use warnings;
use strict;
use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );

# Commands.
# FIXME: move this out of here...  In its own package?
my %commands = ( "Get" => 0x00,
		 "Get Version and Read Protection Status" => 0x01,
		 "Get ID" => 0x02,
		 "Read Memory" => 0x11,
		 "Go" => 0x21,
		 "Write Memory" => 0x31,
		 "Erase" => 0x43,
		 "Extended Erase" => 0x44,
		 "Write Protect" => 0x63,
		 "Write Unprotect" => 0x73,
		 "Readout Protect" => 0x82,
		 "Readout Unprotect" => 0x92,
		 "SYNC" => 0x7F,
		 "ACK" => 0x79,
		 "NACK" => 0x1F,);

has UART => ( is => "ro" );
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );

# Constructor for DPGlueMCU object.
sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};

    unless( exists $arg_ref->{'UART'} ) {
	die "DPGlueMCU can't work without a UART connection to device.  UART has to have 'transmit' and 'receive' methods.";
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


# Any initialization necessary.
sub initialize($) {
    my $self = shift;

    # Nothing yet.

    return;
}


# Get/Set GPIO.  Takes and returns an array reference.
sub gpio($;\@) {
    my $self = shift;
    my $state_ref = shift;

    if( defined($state_ref) ) {
	# User wants to set the GPIO.
	my @state = @{$state_ref};
	my $char = 0;
	for( my $bit=0; $bit < 8; $bit++) {
	    $char += $state[$bit] << $bit;
	}
	$char = chr($char);
	$self->UART->transmit( "O".$char."P" );
    }

    # Read GPIO back regardless. (Expecting 1 byte back)
    $self->UART->transmit( "IP" );
    my $rx = "";
    my $start_time = time();
    do {
	$rx .= $self->UART->receive();
	die "Timeout waiting to receive byte from UART."
	    if($self->Timeout() < (time() - $start_time) );
    } while ( $rx eq "" );
    $rx = ord($rx);
    my @state = ();
    $state_ref = \@state;
    for( my $bit=0; $bit < 8; $bit++) {
	$state[$bit] = (($rx >> $bit) & 0x01);
    }

    return $state_ref;
}

# Get/Set internal Register; Takes and returns ordinal numbers.
sub register($$;$) {
    my $self = shift;
    my $register = shift;
    my $value = shift;

    die "FIXME: Not implemented for DPGlueMCU yet.";

    $register = chr($register);

    if( defined($value) ) {
	# User wants to set the internal register.
	$value = chr($value);
	$self->UART->transmit( "W".$register.$value."P" );
    }

    # Read register back regardless. (Expecting 1 byte back)
    $self->UART->transmit( "R".$register."P" );
    $value = "";
    my $start_time = time();
    do {
	$value .= $self->UART->receive();
	die "Timeout waiting to receive byte from UART."
	    if($self->Timeout() < (time() - $start_time) );
    } while ( $value eq "" );
    $value = ord($value);

    return $value;
}


# Get/Set multiple internal Registers
# Takes and returns references to array of ordinal numbers.
sub registerset($\@;\@) {
    my $self = shift;
    my $register_ref = shift;
    my $value_ref = shift;

    die "FIXME: Not implemented for DPGlueMCU yet.";

    foreach my $register (@{$register_ref}) {
	$register = chr($register);
    }

    if( defined($value_ref) ) {
	foreach my $value (@{$value_ref}) {
	    $value = chr($value);
	}
    }

    if( defined($value_ref) ) {
	# User wants to set the internal register set.
	# Construct Write command.
	my $wr_cmd = "W";
	foreach my $index (keys @{$value_ref}) {
	    $wr_cmd .= $register_ref->[$index];
	    $wr_cmd .= $value_ref->[$index];
	}
	$wr_cmd .= "P";
	$self->UART->transmit( $wr_cmd );
    }

    # Construct Read command.
    my $rd_cmd = "R";
    foreach my $register (@{$register_ref}) {
	$rd_cmd .= $register;
    }
    $rd_cmd .= "P";

    # Read register back regardless. (Expecting same number of bytes back)
    $self->UART->transmit( $rd_cmd );
    my $value_string = "";
    my $start_time = time();
    do {
	$value_string .= $self->UART->receive();
	die "Timeout waiting to receive N bytes from UART."
	    if($self->Timeout() < (time() - $start_time) );
    } while ( length($value_string) < scalar(@{$register_ref}) );

    my @values = (split '', $value_string);
    $value_ref = \@values;
    foreach my $value (@values) {
	$value = ord($value);
    }

    return $value_ref;
}


# Set cLVDS lane count
# Parameter: Lane count.
sub cLVDS_lanes($$) {
    my $self = shift;
    my $lanes = shift;

    # Ascii lanes expected!
    $self->UART->transmit( "L".$lanes."P" );

    my $rx = "";
    my $start_time = time();
    do {
	$rx .= $self->UART->receive();
	die "Timeout waiting to receive byte from UART."
	    if($self->Timeout() < (time() - $start_time) );
    } while ( substr($rx,-1,1) ne "\n" );

    warn "Got reply: $rx";

    return;
}


# Start bootloader for flash update.
sub start_bootloader($) {
    my $self = shift;

    $self->UART->transmit( "BootloaderP" );

    my $rx = "";
    my $start_time = time();
    do {
	$rx .= $self->UART->receive();
	die "Timeout waiting to receive byte from UART."
	    if($self->Timeout() < (time() - $start_time) );
    } while ( substr($rx,-1,1) ne "\n" );

    warn "Got reply: $rx";

    return;
}


# Change baud rate; it's tricky because:
#  - Aptovision API seems to be faster changing Baud rate than transmitting!
# Takes baud rate.
sub change_baud_rate($$) {
    my $self = shift;
    my $baud_rate = shift;

    die "FIXME: Not implemented for DPGlueMCU yet.";

    my $brg_h = (((7372800 / $baud_rate) - 16) >> 8) & 0xFF;
    my $brg_l = (((7372800 / $baud_rate) - 16) >> 0) & 0xFF;

    my $register_ref = [0x00, 0x01];
    my $value_ref = [$brg_l, $brg_h];

    foreach my $register (@{$register_ref}) {
	$register = chr($register);
    }

    foreach my $value (@{$value_ref}) {
	$value = chr($value);
    }

    # Construct Write command.
    my $wr_cmd = "W";
    foreach my $index (keys @{$value_ref}) {
	$wr_cmd .= $register_ref->[$index];
	$wr_cmd .= $value_ref->[$index];
    }
    # Leave out the "P" it has to be sent at new baud rate!
    $self->UART->transmit( $wr_cmd );

    # Now set new Baud rate and wait for UART timeout on SC18IM700 side.
    sleep 0.250;
    $self->UART->set_baud_rate($baud_rate);
    sleep 1.000;

    # Verify successful transition to new baud rate.
    $value_ref = $self->registerset([0x00, 0x01]);

    die "Baud rate doesn't appear to be what we set!"
	unless( ($value_ref->[0] eq $brg_l)
		&& ($value_ref->[1] eq $brg_h) );

    return;
}

1;
