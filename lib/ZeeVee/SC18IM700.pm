# Perl module for speaking to Aptovision API
package ZeeVee::SC18IM700;
use Class::Accessor "antlers";

use warnings;
use strict;
use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );

has UART => ( is => "ro" );
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );

# Constructor for SC18IM700 object.
sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};

    unless( exists $arg_ref->{'UART'} ) {
	die "SC18IM700 can't work without a UART connection to device.  UART has to have 'transmit' and 'receive' methods.";
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

    # Important! Before any I2C access, enable I2C bus timeout; set to ~227ms (default):
    $self->register(0x09, 0x67);

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

# Get/Set GPIO config.  Takes and returns an array reference.
sub gpio_config($;\@) {
    my $self = shift;
    my $state_ref = shift;

    # Port Configuration meanings.
    my %PortConf = ( "QuasiBiDir" => 0b00,
		     "Input"      => 0b01,
		     "PushPull"   => 0b10,
		     "OpenDrain"  => 0b11,
	);

    if( defined($state_ref) ) {
	# User wants to set the GPIO configuration.
	my @state = @{$state_ref};
	my $word = 0;
	for( my $bit=0; $bit < 8; $bit++) {
	    die "I don't know about crazy port configuration $state[$bit]"
		unless( exists($PortConf{"$state[$bit]"}) );
	    $word |= $PortConf{"$state[$bit]"} << ($bit * 2)
	}
	my $low_byte = $word & 0x00FF;
	my $high_byte = ($word & 0xFF00) >> 8;
	$self->registerset([0x02, 0x03], [$low_byte, $high_byte]);
    }

    # Read GPIO configuration back regardless.
    $state_ref = $self->registerset([0x02, 0x03]);
    my $high_byte = $state_ref->[1];
    my $low_byte = $state_ref->[0];
    my $word = ($high_byte << 8) | $low_byte;

    my @state = ();
    $state_ref = \@state;
    %PortConf = reverse %PortConf; # Reverse to by-value.
    for( my $bit=0; $bit < 8; $bit++) {
	$state[$bit] = ($word >> ($bit * 2)) & 0b11;
	$state[$bit] = $PortConf{$state[$bit]};
    }

    return $state_ref;
}

# Get/Set internal Register; Takes and returns ordinal numbers.
sub register($$;$) {
    my $self = shift;
    my $register = shift;
    my $value = shift;

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


# Change baud rate; it's tricky because:
#  - Aptovision API seems to be faster changing Baud rate than transmitting!
#  - SC18IM700 resets if you send it some bad commands
#  - Even the "P" at the end of command has to come at new rate.
# Takes baud rate.
sub change_baud_rate($$) {
    my $self = shift;
    my $baud_rate = shift;

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


# I2C transaction from hash description.
# 'Data' elements and return values are references to array of ordinals.
# Slave address and Length are ordinals.
# FIXME: No I2C status is checked!
sub i2c_raw($\%;) {
    my $self = shift;
    my $transaction_ref = shift;
    my %transaction = %{$transaction_ref};
    my $tx_string = "";
    my $rx_string = "";
    my $rx_length = 0;

    # SC18IM700 has an undocumented 16-byte FIFO.  S....P (inclusive)
    # must be 16 bytes or less.  Keep track to enforce.  I've spent way too much time on it!
    my $tx_string_fifo_head = length($tx_string);

    my $i2c_read = 0x01;
    my $i2c_write = 0x00;


    print "tx: ".Data::Dumper->Dump([\%transaction],["transaction"])
	if($self->Debug() > 1);

    foreach my $command (@{$transaction{'Commands'}}) {
	if( $command->{'Command'} eq 'Write' ) {
	    $tx_string_fifo_head = length($tx_string);
	    $tx_string .= 'S';
	    $tx_string .= chr($transaction{'Slave'} | $i2c_write);
	    $tx_string .= chr(scalar(@{$command->{'Data'}}));
	    foreach my $byte (@{$command->{'Data'}}) {
		$tx_string .= chr($byte);
	    }
	} elsif ( $command->{'Command'} eq 'Read' ) {
	    $tx_string_fifo_head = length($tx_string);
	    $tx_string .= 'S';
	    $tx_string .= chr($transaction{'Slave'} | $i2c_read);
	    $tx_string .= chr($command->{'Length'});
	    $rx_length += $command->{'Length'};
	} elsif ( $command->{'Command'} eq 'Stop' ) {
	    $tx_string .= 'P';
	    die "16-byte FIFO overrun imminent!  Bailing out. "
		if((length($tx_string) - $tx_string_fifo_head) > 16);
	} else {
	    die "Unimplemented I2C command ".$command->{'Command'}.""
	}
    }
    $tx_string .= 'P';
    die "16-byte FIFO overrun imminent!  Bailing out"
	if((length($tx_string) - $tx_string_fifo_head) > 16);

    # Send I2C transaction.
    print "tx_string: '$tx_string'\n"
	if($self->Debug() > 1);
    $self->UART->transmit( $tx_string );

    # FIXME: Check Status of transaction here.

    my $start_time = time();
    while ( length($rx_string) < $rx_length ) {
	$rx_string .= $self->UART->receive();
	die "Timeout waiting to receive byte from UART."
	    if($self->Timeout() < (time() - $start_time) );
    }
    print "rx_string: '$rx_string'\n"
	if($self->Debug() > 1);

    my @rx_array = (split '', $rx_string);
    my $rx_ref = \@rx_array;
    foreach my $byte (@rx_array) {
	$byte = ord($byte);
    }

    return $rx_ref;
}

1;
