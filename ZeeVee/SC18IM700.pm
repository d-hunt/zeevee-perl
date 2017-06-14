# Perl module for speaking to Aptovision API
package ZeeVee::SC18IM700;
use Class::Accessor "antlers";

use warnings;
use strict;
use Data::Dumper ();

has UART => ( is => "ro" );
has Debug => ( is => "ro" );

# Constructor for SC18IM700 object.
sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};
    
    unless( exists $arg_ref->{'UART'} ) {
	die "SC18IM700 can't work without a UART connection to device.  UART has to have 'transmit' and 'receive' methods.";
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
    do {
	$rx .= $self->UART->receive();
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
    do {
	$value .= $self->UART->receive();
    } while ( $value eq "" );
    $value = ord($value);
    
    return $value;
}


1;
