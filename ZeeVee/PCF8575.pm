# Perl module for speaking to Aptovision API
package ZeeVee::PCF8575;
use Class::Accessor "antlers";

use warnings;
use strict;
use Data::Dumper ();

has I2C => ( is => "ro" );
has Address => ( is => "ro" );
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );
has WriteMask => ( is => "rw" );

# Constructor for PCF8575 object.
sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};
    
    unless( exists $arg_ref->{'I2C'} ) {
	die "PCF8575 can't work without a I2C connection to device.  I2C object must provide i2c_raw method.";
    }
    unless( exists $arg_ref->{'Address'} ) {
	die "PCF8575 can't work without an I2C slave address.";
    }
    unless( exists $arg_ref->{'Timeout'} ) {
	$arg_ref->{'Timeout'} = 10;
    }
    unless( exists $arg_ref->{'Debug'} ) {
	$arg_ref->{'Debug'} = 0;
    }
    unless( exists $arg_ref->{'WriteMask'} ) {
	$arg_ref->{'WriteMask'} = 0x0000;
    }
    
    my $self = $class->SUPER::new( $arg_ref );

    $self->initialize();
    
    return $self;
}


# Any initialization necessary.
sub initialize($) {
    my $self = shift;

    # Nothing so far.

    return;
}


sub read($) {
    my $self = shift;
    die "FIXME: Unimplemented";
##########
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
#########
}


# Writes to PCF875.
sub write($\@;) {
    my $self = shift;
    my $state_ref = shift;

    # User wants to set the GPIO.
    my @state = @{$state_ref};
    my $char = 0;
    for( my $bit=0; $bit < 16; $bit++) {
	$char += $state[$bit] << $bit;
    }
    my $char_h = (($char >> 8) & 0xff);
    my $char_l = (($char >> 0) & 0xff);

    $self->I2C->i2c_raw( { 'Slave' => $self->Address(),
			       'Commands' => [{ 'Command' => 'Write',
						    'Data' => [ $char_l,
								$char_h, ]
					      },
			       ],
			 } );
    
    return;
}

1;
