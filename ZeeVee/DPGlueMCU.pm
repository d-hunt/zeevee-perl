# Perl module for speaking to Charlie DisplayPort Output Glue MCU.
package ZeeVee::DPGlueMCU;
use Class::Accessor "antlers";

use strict;
use warnings;
no warnings 'experimental::smartmatch';

use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );
use Carp;

# $Carp::Verbose = 1; # Force Stack Traces.

has UART => ( is => "ro" );
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );
has BinaryAddressBits => ( is => "ro" );
has BinaryEntryString => ( is => "ro" );
has BinaryExitString => ( is => "ro" );

# Constructor for DPGlueMCU object.
sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};

    unless( exists $arg_ref->{'UART'} ) {
	croak "DPGlueMCU can't work without a UART connection to device.  UART has to have 'transmit' and 'receive' methods.";
    }
    unless( exists $arg_ref->{'Timeout'} ) {
	$arg_ref->{'Timeout'} = 10;
    }
    unless( exists $arg_ref->{'Debug'} ) {
	$arg_ref->{'Debug'} = 0;
    }
    unless( exists $arg_ref->{'BinaryAddressBits'} ) {
	$arg_ref->{'BinaryAddressBits'} = 32;
    }
    unless( exists $arg_ref->{'BinaryEntryString'} ) {
	$arg_ref->{'BinaryEntryString'} = "?";
    }
    unless( exists $arg_ref->{'BinaryExitString'} ) {
	$arg_ref->{'BinaryExitString'} = "End.\n";
    }

    my $self = $class->SUPER::new( $arg_ref );

    $self->initialize();

    return $self;
}


# Any initialization necessary.
sub initialize($) {
    my $self = shift;

    $self->UART->configure( { 'baud_rate'     => 9600,
				  'data_bits' => 8,
				  'parity'    => "NONE",
				  'stop_bits' => 1,
			    } );

    $self->flush_tx();
    my $rx = $self->flush_rx();
    warn "Received and discarded on UART: $rx"
	if(length($rx) > 0);

    return;
}


# Compel the Glue MCU to flush its command buffer.
sub flush_tx($) {
    my $self = shift;

    $self->UART->transmit("P");
    sleep 0.5;  # Wait in case there is a response in flight.

    return;
}


# Receive whatever may be in UART buffer.
# Return it, but with the intention of discarding it.
sub flush_rx($) {
    my $self = shift;

    my $rx = $self->UART->receive();
    return $rx;
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
	croak "Timeout waiting to receive byte from UART."
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
	croak "Timeout waiting to receive byte from UART."
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
	croak "Timeout waiting to receive N bytes from UART."
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
	croak "Timeout waiting to receive byte from UART."
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
	carp "Timeout waiting to receive byte from UART.  Going on anyway..."
	    if($self->Timeout() < (time() - $start_time) );
    } while ( substr($rx,-1,1) ne "\n"
	      && $self->Timeout() >= (time() - $start_time));

    warn "Got reply: $rx";

    return;
}


# DP RX Enter Programming mode.
sub EP_BB_program_enable_DPRX($) {
    my $self = shift;

    # Go into program mode and verify.
    $self->UART->transmit( "ExploreBBprogramDpRxP" );

    my $rx = "";
    my $start_time = time();
    do {
	$rx .= $self->UART->receive();
	croak "Timeout waiting to receive byte from UART."
	    if($self->Timeout() < (time() - $start_time) );
    } while ( $rx ne "BB Program DPRX.\n" );

    warn "Received: $rx.";

    return;
}


# DP TX Enter Programming mode.
sub EP_BB_program_enable_DPTX($) {
    my $self = shift;

    # Go into program mode and verify.
    $self->UART->transmit( "ExploreBBprogramDpTxP" );

    my $rx = "";
    my $start_time = time();
    do {
	$rx .= $self->UART->receive();
	croak "Timeout waiting to receive byte from UART."
	    if($self->Timeout() < (time() - $start_time) );
    } while ( $rx ne "BB Program DPTX.\n" );

    warn "Received: $rx.";

    return;
}


# HDMI Splitter Enter Programming mode.
sub EP_BB_program_enable_Splitter($) {
    my $self = shift;

    # Go into program mode and verify.
    $self->UART->transmit( "ExploreBBprogramSplitterP" );

    my $rx = "";
    my $start_time = time();
    do {
	$rx .= $self->UART->receive();
	croak "Timeout waiting to receive byte from UART."
	    if($self->Timeout() < (time() - $start_time) );
    } while ( $rx ne "BB Program Splitter.\n" );

    warn "Received: $rx.";

    return;
}


# Explore BootBlock Exit Programming mode.
sub EP_BB_program_disable($) {
    my $self = shift;

    # Get out of program mode and verify.
    $self->UART->transmit( "ExploreBBprogramDisableP" );

    my $rx = "";
    my $start_time = time();
    do {
	$rx .= $self->UART->receive();
	croak "Timeout waiting to receive byte from UART."
	    if($self->Timeout() < (time() - $start_time) );
    } while ( $rx ne "End BB Program.\n" );

    warn "Received: $rx.";

    return;
}


# Write Explore BootBlock program a block of firmware code.
# Parameters: BlockAddress, Block to Write.
sub EP_BB_program_block($$$) {
    my $self = shift;
    my $address = shift;
    my $block = shift;

    # Go into binary transfer mode and verify.
    $self->UART->transmit( "ExploreBBprogramP" );

    my $rx = "";
    my $start_time = time();
    do {
	$rx .= $self->UART->receive();
	croak "Timeout waiting to receive byte from UART."
	    if($self->Timeout() < (time() - $start_time) );
    } while ( $rx ne $self->BinaryEntryString() );

    # Now GlueMCU is waiting for the payload.
    # Construct payload: Address (32-bit, MSB first) + Binary Block.
    my $tx = "";
    my $bits=$self->BinaryAddressBits();
    while( $bits > 0 ) {
	$bits -= 8;
	$tx .= chr(($address>>$bits) & 0xFF);
    }
    $tx .= $block;

    # Send payload.
    $self->UART->transmit($tx);

    # Verify end of Binary transfer mode.
    my $address_bytes=$self->BinaryAddressBits() / 8;
    $rx = "";
    $start_time = time();
    do {
	$rx .= $self->UART->receive();
	croak "Timeout waiting to receive byte from UART."
	    if($self->Timeout() < (time() - $start_time) );
    } until ( length($rx) >= (length($block) + $address_bytes)
	      && ( substr( $rx, -1*length($self->BinaryExitString()) )
		   eq $self->BinaryExitString() ) );

    # Verify the received address is exactly as expected.
    croak "Address received does not match address sent!"
	unless( substr($tx,0,$address_bytes)
		eq substr($rx,0,$address_bytes) );

    # Verify the received data was exactly as sent. (This is just the transmission)
    # We do this one printable chunk at a time.
    my $chunk_size = 16;
    my $offset = $address_bytes;
    while( $offset < length($tx) ) {
	# Gather next block of data to verify.
	my $written = substr($tx, $offset, $chunk_size);
	# Gather corresponding block as read from EP BootBlock.
	my $read = substr($rx, $offset, $chunk_size);

	# Check they match.
	if ($read ne $written) {
	    printf( "Mismatch at 0x%08x:\n", ($address+$offset-$address_bytes) );
	    print "W: ";
	    foreach my $ch (split(//, $written)) {
		printf( "%02x ", ord($ch) );
	    }
	    print "\n";
	    print "R: ";
	    foreach my $ch (split(//, $read)) {
		printf( "%02x ", ord($ch) );
	    }
	    print "\n";
	}

	$offset += $chunk_size;
    }

    croak "Write error: mismatch between sent and received data."
	unless( substr($tx, $address_bytes, length($block))
		eq substr($rx, $address_bytes, length($block)) );

    return;
}


# Explore BootBlock read back a block of firmare code.
# Parameter: BlockAddress.
# Returns: Received block.
sub EP_BB_read_block($$) {
    my $self = shift;
    my $address = shift;
    my $expected_length = 512; # To guard against unexpected match.

    # Go into binary read mode and verify transition.
    $self->UART->transmit( "ExploreBBReadP" );

    my $rx = "";
    my $start_time = time();
    do {
	$rx .= $self->UART->receive();
	croak "Timeout waiting to receive byte from UART."
	    if($self->Timeout() < (time() - $start_time) );
    } while ( $rx ne $self->BinaryEntryString() );

    # Now GlueMCU is waiting for the payload (address).
    # Construct payload: Address (32-bit, MSB first.)
    my $tx = "";
    my $bits=$self->BinaryAddressBits();
    while( $bits > 0 ) {
	$bits -= 8;
	$tx .= chr(($address>>$bits) & 0xFF);
    }

    # Send payload.
    $self->UART->transmit($tx);

    # Now GlueMCU is sending its payload.
    # Payload: Address (32-bit, MSB first) + Binary Block.

    # Read until end of Binary transfer mode.
    my $address_bytes=$self->BinaryAddressBits() / 8;
    $rx = "";
    $start_time = time();
    do {
	$rx .= $self->UART->receive();
	croak "Timeout waiting to receive byte from UART."
	    if($self->Timeout() < (time() - $start_time) );
    } until ( length($rx) >= ($expected_length + $address_bytes)
	      && ( substr( $rx, -1*length($self->BinaryExitString()) )
		   eq $self->BinaryExitString() ) );

    # Verify the received address is exactly as expected.
    croak "Address received does not match address sent!"
	unless( substr($tx,0,$address_bytes)
		eq substr($rx,0,$address_bytes) );

    # Trim out only the binary block.
    # Skipping address in beginning.
    # Skipping binary transfer end marker.
    my $block = substr( $rx,
			$address_bytes,
			-1*length($self->BinaryExitString()) ); 

    return $block;
}


# Explore BootBlock write program.
# Parameters: StartAddress, Data to Write.
sub EP_BB_program($$$) {
    my $self = shift;
    my $address = shift;  # Address in User flash area; Starts after BB.
    my $data_string = shift;

    # Split to 512-byte blocks.
    my @blocks = unpack("(a512)*", $data_string);

    warn "Length: ".length($data_string)." Blocks: ".scalar(@blocks)."\n";

    # Program all 512-byte blocks.
    $| = 1;    # Autoflush
    foreach my $block (@blocks) {
	$block .= chr(0xFF)
	    while length($block) < 512;
	print ".";
	$self->EP_BB_program_block($address, $block);
	$address += 512;
    }
    $| = 0;    # Disable Autoflush

    return;
}


# Explore BootBlock read program.
# Parameters: StartAddress, Length to read.
# Returns: Read data.
sub EP_BB_read($$$) {
    my $self = shift;
    my $address = shift;  # Address in User flash area; Starts after BB.
    my $length = shift // 0xF000;
    my $data_string = "";

    # Read all in 512-byte blocks.
    $| = 1;    # Autoflush
    while( length($data_string) < $length ) {
	print ".";
	$data_string .= $self->EP_BB_read_block($address);
	$address += 512;
    }
    $| = 0;    # Disable Autoflush

    return $data_string;
}


# Verify a program.
# Parameters:
#   Base address (for mismatch reporting only.)
#   Data String to verify against (golden).
#   Data String to verify (typically read back).
# Returns:
#   1 - Successful verify
#   0 - At least one mismatch.
sub __verify($$$) {
    my $self = shift;
    my $address = shift // 0x0000;
    my $golden_data = shift;
    my $read_data = shift;

    my $block_size = 16; # For printing of mismatch.

    warn "Data lengths don't match at verify.\n"
	."\tGolden:  ".length($golden_data)." bytes"
	."\tUnknown: ".length($read_data)." bytes"
	unless (length($golden_data) == length($read_data));

    my $good_count = 0;
    my $bad_count = 0;

    # Read and verify data one printable block at a time.
    my $offset = 0;
    while( $offset < length($golden_data) ) {
	# Gather next block of data to verify.
	my $golden_block = substr($golden_data, $offset, $block_size);
	# Gather corresponding block as read from DPRX.
	my $read_block = substr($read_data, $offset, $block_size);

	# Check they match.
	if ($read_block eq $golden_block) {
	    $good_count++;
	} else {
	    $bad_count++;
	    printf( "Mismatch at 0x%08x:\n", ($address+$offset) );
	    print "Written: ";
	    foreach my $ch (split(//, $golden_block)) {
		printf( "%02x ", ord($ch) );
	    }
	    print "\n";
	    print "Read   : ";
	    foreach my $ch (split(//, $read_block)) {
		printf( "%02x ", ord($ch) );
	    }
	    print "\n";
	}

	$offset += $block_size;
    }

    print "Verified $block_size byte blocks:\n"
	."\tGood blocks: $good_count; Bad blocks: $bad_count.\n";

    return 0 if($bad_count);
    return 1;
}


# Write DP RX program.
# Parameters: StartAddress, Data to Write.
sub DPRX_program($$$) {
    my $self = shift;
    my $address = shift // 0x0000;
    my $data_string = shift;
    my $max_datasize = (0xF800-0x1000);

    # $address: Address in User flash area; Starts after BB.
    # 0x0000 here goes in 0x1000 on device address space.

    croak "Data too long for EP9169S."
	if (length($data_string) > $max_datasize);

    $self->EP_BB_program_enable_DPRX();
    $self->EP_BB_program($address, $data_string);
    $self->EP_BB_program_disable();

    return;
}


# Read DP RX program.
# Parameters: StartAddress, Length to read.
# Returns: Read data.
sub DPRX_read($$$) {
    my $self = shift;
    my $address = shift // 0x0000;  # Address in User flash area; Starts after BB.
    my $length = shift // 0xF000;
    my $data_string = "";

    # Address in User flash area; Starts after BB.
    # 0x0000 here goes in 0x1000 on device address space.

    croak "Read out of bounds for EP9169S."
	if( ($address + $length) > 0xF000);


    $self->EP_BB_program_enable_DPRX();
    $data_string = $self->EP_BB_read($address, $length);
    $self->EP_BB_program_disable();

    return $data_string;
}


# Verify DP RX program.
# Parameters:
#   Address to start Verify
#   Data String to verify against.
# Returns:
#   1 - Successful verify
#   0 - At least one mismatch.
sub DPRX_verify($$$) {
    my $self = shift;
    my $address = shift;
    my $golden_data = shift;

    # Read from DP RX same length of data as golden.
    my $read_data = $self->DPRX_read($address, length($golden_data));

    return $self->__verify($address, $golden_data, $read_data);
}


# Write DP TX program.
# Parameters: StartAddress, Data to Write.
sub DPTX_program($$$) {
    my $self = shift;
    my $address = shift // 0x0000;
    my $data_string = shift;
    my $max_datasize = (0x7800-0x1000);

    # $address: Address in User flash area; Starts after BB.
    # 0x0000 here goes in 0x1000 on device address space.

    croak "Data too long for EP196E."
	if (length($data_string) > $max_datasize);

    $self->EP_BB_program_enable_DPTX();
    $self->EP_BB_program($address, $data_string);
    $self->EP_BB_program_disable();

    return;
}


# Read DP TX program.
# Parameters: StartAddress, Length to read.
# Returns: Read data.
sub DPTX_read($$$) {
    my $self = shift;
    my $address = shift // 0x0000;  # Address in User flash area; Starts after BB.
    my $length = shift // 0x7000;
    my $data_string = "";

    # Address in User flash area; Starts after BB.
    # 0x0000 here goes in 0x1000 on device address space.

    croak "Read out of bounds for EP196E."
	if( ($address + $length) > 0x7000);


    $self->EP_BB_program_enable_DPTX();
    $data_string = $self->EP_BB_read($address, $length);
    $self->EP_BB_program_disable();

    return $data_string;
}


# Verify DP TX program.
# Parameters:
#   Address to start Verify
#   Data String to verify against.
# Returns:
#   1 - Successful verify
#   0 - At least one mismatch.
sub DPTX_verify($$$) {
    my $self = shift;
    my $address = shift;
    my $golden_data = shift;

    # Read from DP TX same length of data as golden.
    my $read_data = $self->DPTX_read($address, length($golden_data));

    return $self->__verify($address, $golden_data, $read_data);
}


# Write HDMI Splitter program.
# Parameters: StartAddress, Data to Write.
sub Splitter_program($$$) {
    my $self = shift;
    my $address = shift // 0x0000;
    my $data_string = shift;
    my $max_datasize = ((0x8000*4)-0x1000);

    # $address: Address in User flash area; Starts after BB.
    # 0x0000 here goes in 0x1000 on device address space.

    croak "Data too long for EP9162S."
	if (length($data_string) > $max_datasize);

    $self->EP_BB_program_enable_Splitter();
    $self->EP_BB_program($address, $data_string);
    $self->EP_BB_program_disable();

    return;
}


# Read HDMI Splitter program.
# Parameters: StartAddress, Length to read.
# Returns: Read data.
sub Splitter_read($$$) {
    my $self = shift;
    my $address = shift // 0x0000;  # Address in User flash area; Starts after BB.
    my $length = shift // ((0x8000*4)-0x1000);
    my $data_string = "";

    # Address in User flash area; Starts after BB.
    # 0x0000 here goes in 0x1000 on device address space.

    croak "Read out of bounds for EP9162S."
	if( ($address + $length) > ((0x8000*4)-0x1000));


    $self->EP_BB_program_enable_Splitter();
    $data_string = $self->EP_BB_read($address, $length);
    $self->EP_BB_program_disable();

    return $data_string;
}


# Verify HDMI Splitter program.
# Parameters:
#   Address to start Verify
#   Data String to verify against.
# Returns:
#   1 - Successful verify
#   0 - At least one mismatch.
sub Splitter_verify($$$) {
    my $self = shift;
    my $address = shift;
    my $golden_data = shift;

    # Read from HDMI Splitter same length of data as golden.
    my $read_data = $self->Splitter_read($address, length($golden_data));

    return $self->__verify($address, $golden_data, $read_data);
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

    croak "Baud rate doesn't appear to be what we set!"
	unless( ($value_ref->[0] eq $brg_l)
		&& ($value_ref->[1] eq $brg_h) );

    return;
}

1;
