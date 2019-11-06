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
	$arg_ref->{'WriteMask'} = [];
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

    # Read GPIO back.
    my $i2c_state_ref = 
	$self->I2C->i2c_raw( {'Slave' => $self->Address(),
			      'Commands' => [{ 'Command' => 'Read',
					       'Length' => 2,
					     },
				  ],
			     } );
    my $value = $i2c_state_ref->[0] | ($i2c_state_ref->[1] << 8);
    my @state = ();
    for( my $bit=0; $bit < 16; $bit++) {
	$state[$bit] = (($value >> $bit) & 0x01);
    }

    return \@state;
}


# Writes to PCF875.  Reads back value.
sub write($\@;) {
    my $self = shift;
    my $state_ref = shift;

    # User wants to set the GPIO.
    my @state = @{$state_ref};
    my $word = 0;
    for( my $bit=0; $bit < 16; $bit++) {
	$word += $state[$bit] << $bit;
    }

    my $value = $self->word_write($word);
    @state = ();
    for( my $bit=0; $bit < 16; $bit++) {
        $state[$bit] = (($value >> $bit) & 0x01);
    }

    return \@state;
}


# Writes 16-bit word to PCF875.  Reads back value.
sub word_write($$) {
    my $self = shift;
    my $word = shift;

    # User wants to set the GPIO.
    # Apply mask. (1 is driven weak.)
    foreach my $bit (@{$self->WriteMask}) {
        $word |= (0x0001 << $bit);
    }
    my $char_h = (($word >> 8) & 0xff);
    my $char_l = (($word >> 0) & 0xff);

    my $i2c_state_ref = 
        $self->I2C->i2c_raw( { 'Slave' => $self->Address(),
			       'Commands' => [{ 'Command' => 'Write',
						'Data' => [ $char_l,
							    $char_h, ]
					      },
					      { 'Command' => 'Read',
						'Length' => 2,
					      },
				   ],
			     } );

    # The read acts as a fence!

    my $value = $i2c_state_ref->[0] | ($i2c_state_ref->[1] << 8);

    return $value;
}


# Streams 16-bit words to PCF8575 as fast as possible.
sub stream_write($\@) {
    my $self = shift;
    my $stream_ref = shift;
    my $i2c_transaction = { 'Slave' => $self->Address() ,
				'Commands' => [] };
    my $commands = $i2c_transaction->{'Commands'};

    # Calculate mask. (1 is driven weak.)
    my $mask = 0;
    foreach my $bit (@{$self->WriteMask}) {
	$mask |= (1 << $bit);
    }

    # Construct the I2C commands.
    {
	my $page_size = 12;
	my $current_command = undef;
	foreach my $word (@{$stream_ref}) {
	    my $char_h = ((($word | $mask) >> 8) & 0xff);
	    my $char_l = ((($word | $mask) >> 0) & 0xff);

	    if( !defined($current_command) ) {
		# We need to set up a new write command
		if( scalar(@{$commands}) ) {
		    # We need to put stop commands between write commands.
		    $current_command = { 'Command' => 'Stop' };
		    push @{$commands}, $current_command;
		}
		$current_command = { 'Command' => 'Write',
				     'Data' => [] };
	    }

	    push @{$current_command->{'Data'}}, ($char_l, $char_h);

	    if( scalar(@{$current_command->{'Data'}}) >= $page_size ) {
		push @{$commands}, $current_command;
		$current_command = undef;
	    }
	}

	if( defined($current_command) ) {
	    # Partial page needs special handling.
	    push @{$commands}, $current_command;
	    $current_command = undef;
	}

	# The final read acts as a fence!
	$current_command = { 'Command' => 'Read',
			     'Length' => 2 };
	push @{$commands}, $current_command;
	$current_command = undef;

	print "Stream I2C write transaction prepared: ".
	    Data::Dumper->Dump([$i2c_transaction], ["i2c_transaction"])
	    if( $self->Debug > 1);
    }

    $self->I2C->i2c_raw( $i2c_transaction );

    return;
}

1;
