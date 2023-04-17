# Perl module for speaking to Aptovision API
package ZeeVee::SC18IM704;
use Class::Accessor "antlers";

use warnings;
use strict;
use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );

has UART => ( is => "ro" );
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );

# Constructor for SC18IM704 object.
sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};

    unless( exists $arg_ref->{'UART'} ) {
	die "SC18IM704 can't work without a UART connection to device.  UART has to have 'transmit' and 'receive' methods.";
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
