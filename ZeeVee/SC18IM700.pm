# Perl module for speaking to Aptovision API
package ZeeVee::SC18IM700;
use Class::Accessor "antlers";

use warnings;
use strict;
use Data::Dumper ();

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

# I2C transaction from hash description.
sub i2c($\%;) {
    my $self = shift;
    my $transaction_ref = shift;
    my %transaction = %{$transaction_ref};

    
    print "tx: ".Data::Dumper->Dump([\%transaction],["transaction"]);
'    $register = chr($register);

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
'
}


1;
