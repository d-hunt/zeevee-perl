# Perl module for Bitbanging SPI over GPIO pins.
package ZeeVee::SPI_GPIO;
use Class::Accessor "antlers";

use warnings;
use strict;
use Data::Dumper ();

has GPIO => ( is => "ro" );
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );
has ChunkSize => ( is => "ro" );
has Bits => ( is => "ro" );
has Base => ( is => "rw" );
has Stream => ( is => "rw" );

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
    unless( exists $arg_ref->{'ChunkSize'} ) {
	$arg_ref->{'ChunkSize'} = 256;
    }
    unless( exists $arg_ref->{'Bits'} ) {
	$arg_ref->{'Bits'} = { 'Select' => 12,
				   'Clock' => 13,
				   'MISO' => 14,
				   'MOSI' => 15,
	};
    }
    unless( exists $arg_ref->{'Base'} ) {
	$arg_ref->{'Base'} = 0xffff;
    }
    unless( exists $arg_ref->{'Stream'} ) {
	$arg_ref->{'Stream'} = [];
    }
    
    my $self = $class->SUPER::new( $arg_ref );

    $self->initialize();
    
    return $self;
}


# Any initialization necessary.
sub initialize($) {
    my $self = shift;

    $self->start_stream();

    return;
}


#Send the serialized stream; chunked for Aptovision consumption without constipation.
sub send($) {
    my $self = shift;

    # The following uselessness is because of the Aptovision API craziness we're doing
    #   and how long it's going to take without feedback...
    #   We break up the SPI transaction to multiple UART sends.
    my @chunk = ();
    foreach my $element (@{$self->Stream()}) {
	push @chunk, $element;
	if( scalar(@chunk) >= $self->ChunkSize() ) {
	    $self->GPIO->stream_write(\@chunk);
	    @chunk = ();
	}
    }
    if( scalar(@chunk) ) {
	$self->GPIO->stream_write(\@chunk);
    }
    
    return;
}


# Serialize a string to a stream of 16-bit GPIO values.
sub append_stream($$) {
    my $self = shift;
    my $string = shift;
    my @stream = ();
    my $base_gpio = $self->Base();

    $base_gpio = $self->__clear_bit( $base_gpio, $self->Bits->{'Clock'} );
    $base_gpio = $self->__clear_bit( $base_gpio, $self->Bits->{'Select'} );
    
    foreach my $byte (split '', $string) {
	$byte = ord($byte);
	for( my $bit=(8-1); $bit >= 0 ; $bit-- ) {
	    my $tx_bit = ( ($byte >> $bit) & 0x01 );
	    my $tx_byte = $base_gpio;
	    $tx_byte = $self->__clear_bit( $tx_byte, $self->Bits->{'Clock'} );
	    $tx_byte = $self->__clear_bit( $tx_byte, $self->Bits->{'MOSI'} )
		if( $tx_bit == 0x00 );
	    $tx_byte = $self->__set_bit( $tx_byte, $self->Bits->{'MOSI'} )
		if( $tx_bit == 0x01 );
	    push @stream, $tx_byte; 

	    $tx_byte = $self->__set_bit( $tx_byte, $self->Bits->{'Clock'} );
	    push @stream, $tx_byte;
	}
    }

    push @{$self->Stream()}, @stream;
	
    return \@stream;
}


# Clears the object's stream!
sub discard_stream($) {
    my $self = shift;
    my @stream = ();

    $self->Stream(\@stream);
    
    return \@stream;
}


# To start SPI cycle, generate a stream of 16-bit GPIO values.
# Clears the object's stream!
sub start_stream($) {
    my $self = shift;
    my @stream = ();
    my $base_gpio = $self->Base();

    $self->discard_stream();
    
    $base_gpio = $self->__clear_bit( $base_gpio, $self->Bits->{'Clock'} );
    push @stream, $base_gpio;
    
    $base_gpio = $self->__clear_bit( $base_gpio, $self->Bits->{'Select'} );
    push @stream, $base_gpio;

    push @{$self->Stream()}, @stream;
    
    return \@stream;
}


# To end a SPI cycle, generate a stream of 16-bit GPIO values.
sub end_stream($) {
    my $self = shift;
    my @stream = ();
    my $base_gpio = $self->Base();

    $base_gpio = $self->__clear_bit( $base_gpio, $self->Bits->{'Clock'} );
    $base_gpio = $self->__clear_bit( $base_gpio, $self->Bits->{'Select'} );

    $base_gpio = $self->__set_bit( $base_gpio, $self->Bits->{'Select'} );
    push @stream, $base_gpio;

    $base_gpio = $self->__set_bit( $base_gpio, $self->Bits->{'Clock'} );
    push @stream, $base_gpio;

    push @{$self->Stream()}, @stream;
	
    return \@stream;
}


# To construct a command+address SPI transaction,
#   generate a stream of 16-bit GPIO values.
sub command_stream($\%) {
    my $self = shift;
    my $definition = shift;
    my $string = "";

    die "Unexpected command"
	unless( ($definition->{'Command'} >> 8) == 0 );
    
    $string .= chr($definition->{'Command'});

    my $bit=$definition->{'AddressWidth'} // 0;
    while( $bit > 0 ) {
	$bit -= 8;
	$string .= chr( ($definition->{'Address'} >> ($bit)) & 0xff );
    }

    my $count=$definition->{'DummyByteCount'} // 0;
    while( $count > 0 ) {
	$count--;
	$string .= chr( 0x00 );
    }

    
    return $self->append_stream($string);
}


# Set a bit
# Private helper function
sub __set_bit($$$) {
    my $self = shift;
    my $byte = shift;
    my $bit = shift;

    $byte |= (0x1 << $bit);
    
    return $byte;
}


# Clear a bit
# Private helper function
sub __clear_bit($$$) {
    my $self = shift;
    my $byte = shift;
    my $bit = shift;

    $byte &= 0xffff ^ (0x1 << $bit);
    
    return $byte;
}

1;
