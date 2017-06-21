# Perl module for Bitbanging SPI over GPIO pins.
package ZeeVee::SPI_GPIO;
use Class::Accessor "antlers";

use warnings;
use strict;
use Data::Dumper ();

has GPIO => ( is => "ro" );
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );
has Bits => ( is => "ro" );

# Constructor for SPI_GPIO object.
sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};
    
    unless( exists $arg_ref->{'GPIO'} ) {
	die "SPI_GPIO can't work without a GPIO connection to device.  GPIO object must provide stream_write method.";
    }
    unless( exists $arg_ref->{'Timeout'} ) {
	$arg_ref->{'Timeout'} = 10;
    }
    unless( exists $arg_ref->{'Debug'} ) {
	$arg_ref->{'Debug'} = 0;
    }
    unless( exists $arg_ref->{'Bits'} ) {
	$arg_ref->{'Bits'} = { 'Select' => 12,
				   'Clock' => 13,
				   'MISO' => 14,
				   'MOSI' => 15,
	};
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


# Set a bit
sub set_bit($$$) {
    my $self = shift;
    my $byte = shift;
    my $bit = shift;

    $byte |= (0x1 << $bit);
    
    return $byte;
}


# Clear a bit
sub clear_bit($$$) {
    my $self = shift;
    my $byte = shift;
    my $bit = shift;

    $byte &= 0xffff ^ (0x1 << $bit);
    
    return $byte;
}


# Serialize a string to a stream of 16-bit GPIO values.
sub make_stream($$) {
    my $self = shift;
    my $string = shift;
    my @stream = ();

    # FIXME: Be more flexible!
    my $base_gpio = 0xffff;
    $base_gpio = $self->clear_bit( $base_gpio, $self->Bits->{'Clock'} );
    $base_gpio = $self->clear_bit( $base_gpio, $self->Bits->{'Select'} );
    
    foreach my $byte (split '', $string) {
	$byte = ord($byte);
	for( my $bit=(8-1); $bit >= 0 ; $bit-- ) {
	    my $tx_bit = ( ($byte >> $bit) & 0x01 );
	    my $tx_byte = $base_gpio;
	    $tx_byte = $self->clear_bit( $tx_byte, $self->Bits->{'Clock'} );
	    $tx_byte = $self->clear_bit( $tx_byte, $self->Bits->{'MOSI'} )
		if( $tx_bit == 0x00 );
	    $tx_byte = $self->set_bit( $tx_byte, $self->Bits->{'MOSI'} )
		if( $tx_bit == 0x01 );
	    push @stream, $tx_byte; 

	    $tx_byte = $self->set_bit( $tx_byte, $self->Bits->{'Clock'} );
	    push @stream, $tx_byte;
	}
    }

    return \@stream;
}


# To start SPI cycle, generate a string to a stream of 16-bit GPIO values.
sub start_stream($) {
    my $self = shift;
    my @stream = ();

    # FIXME: Be more flexible!
    my $base_gpio = 0xffff;

    $base_gpio = $self->clear_bit( $base_gpio, $self->Bits->{'Clock'} );
    push @stream, $base_gpio;
    
    $base_gpio = $self->clear_bit( $base_gpio, $self->Bits->{'Select'} );
    push @stream, $base_gpio;

    return \@stream;
}


# To end a SPI cycle, generate a string to a stream of 16-bit GPIO values.
sub end_stream($) {
    my $self = shift;
    my @stream = ();

    # FIXME: Be more flexible!
    my $base_gpio = 0xffff;
    $base_gpio = $self->clear_bit( $base_gpio, $self->Bits->{'Clock'} );
    $base_gpio = $self->clear_bit( $base_gpio, $self->Bits->{'Select'} );

    $base_gpio = $self->set_bit( $base_gpio, $self->Bits->{'Select'} );
    push @stream, $base_gpio;

    $base_gpio = $self->set_bit( $base_gpio, $self->Bits->{'Clock'} );
    push @stream, $base_gpio;
    
    return \@stream;
}

1;
