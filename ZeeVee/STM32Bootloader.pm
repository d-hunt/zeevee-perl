# Perl module for speaking to STM32 Bootloader.
package ZeeVee::STM32Bootloader;
use Class::Accessor "antlers";

use strict;
use warnings;
no warnings 'experimental::smartmatch';

use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );
use Carp;

# $Carp::Verbose = 1; # Force Stack Traces.

our %DocumentedCommands = (
    "Get" => 0x00,
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
    "NACK" => 0x1F,
    );

has UART => ( is => "ro" );
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );
has ConnectionState => ( is => "rw" );
has OriginalUARTConfig => ( is => "rw" );
has SupportedCommands => ( is => "rw" );
has RXBuffer => ( is => "rw" ); # Because we may receive more than we asked.

# Constructor for STM32Bootloader object.
sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};

    $arg_ref = $class->_preInitialize($arg_ref);  # Get Defaults.

    my $self = $class->SUPER::new($arg_ref, @_);  # Call the Class::Accessor constructor

    $self->_initialize();  # Call any internal initialization

    return $self;
}


# Initialize operations before object has been created.
sub _preInitialize($;\%) {
    my $class = shift;
    my $arg_ref = shift;

    unless( exists $arg_ref->{'UART'} ) {
	croak "Bootloader can't work without a UART connection to device.  UART has to have 'transmit', 'receive', 'configure' and 'Configuration' methods.";
    }
    unless( exists $arg_ref->{'Timeout'} ) {
	$arg_ref->{'Timeout'} = 10;
    }
    unless( exists $arg_ref->{'Debug'} ) {
	$arg_ref->{'Debug'} = 0;
    }

    unless( exists $arg_ref->{'SupportedCommands'} ) {
	$arg_ref->{'SupportedCommands'} = [];
    }

    return $arg_ref;
}


# Any initialization necessary after object creation.
sub _initialize($) {
    my $self = shift;

    # Start disconnected; Do not automatically connect!
    $self->ConnectionState("Disconnected");

    # Start with empty RX Buffer.
    $self->RXBuffer("");

    # Start with some assumptions about minimal Supported commands.
    $self->SupportedCommands([ $DocumentedCommands{"SYNC"},
			       $DocumentedCommands{"ACK"},
			       $DocumentedCommands{"NACK"},
			       $DocumentedCommands{"Get"},
			     ]);

    return;
}


# Bootloader Connect
# Accesses the bootloader for updates.
# Returns:
#   1 - successfully contacted bootloader.
#   0 - did not find bootloader.
sub connect($) {
    my $self = shift;

    # Short circuit if we're already connected.
    return 1
	if $self->is_connected();

    # Bootloader uses even parity.  Bitrate is auto-detected.
    $self->ConnectionState("Trying");
    $self->OriginalUARTConfig($self->UART->Configuration());
    $self->UART->configure( { 'baud_rate'     => 115200,
				  'data_bits' => 8,
				  'parity'    => "EVEN",
				  'stop_bits' => 1,
			    } );
    sleep 0.5;

    # Send init/sync command 0x7F.
    my $sync = $self->_command("SYNC");
    if( $self->_send_bytes_ack($sync) ) {
	$self->ConnectionState("Connected");
	return 1;
    } else {
	# That didn't work.  Clean up and put the UART mode back.
	$self->disconnect();
	return 0;
    }
}


# Bootloader Disconnect
# Revert UART settings and block from further access.
sub disconnect($) {
    my $self = shift;

    # Only do this if we're connected.
    return 1
	unless $self->is_connected();

    $self->UART->configure($self->OriginalUARTConfig());
    $self->OriginalUARTConfig(undef);
    $self->ConnectionState("Disconnected");
    sleep 0.5;

    return 1;
}


# Bootloader connection state
# Returns:
#  1 - Connected. (Or trying.)
#  0 - Not connected.
sub is_connected($) {
    my $self = shift;

    return 1
	if ( $self->ConnectionState eq 'Connected' );

    return 1
	if ( $self->ConnectionState eq 'Trying' );

    return 0;
}


# Get version and supported commands
# Get the bootloader version and commands.
sub get_version($) {
    my $self = shift;

    $self->_send_command("Get")
	or croak "Unexpected response.  I wouldn't know what to do...";

    # Get at least one more byte (count).
    my $count = ord($self->_expect(1));
    $count++; # Count is 1 short from MCU

    # Get the remaining bytes based on count received.
    my $rx = $self->_expect_ack($count);

    croak "Unexpected response received from bootloader."
	unless(defined($rx));

    my @bytes = split(//, $rx);
    foreach my $byte ( @bytes ) {
	$byte = ord($byte);
    }

    my $version = shift @bytes;
    printf("MCU Bootloader version: 0x%02x\n", $version);

    print "MCU supported commands: ";
    foreach my $byte ( @bytes ) {
	printf("0x%02x ", $byte);
	push @{$self->SupportedCommands}, $byte
	    unless( $byte ~~ @{$self->SupportedCommands} );
    }
    print "\n";

    return 1;
}

# Go
# Jump to address in memory space
# Argument: Address
# Returns:
#   1 - Success.
sub go($$) {
    my $self = shift;
    my $address = shift;

    # Send Command
    $self->_send_command("Go")
	or croak "Unexpected response from bootloader.";

    # Send Address
    my @tx = ( ($address>>24) & 0xff,
	       ($address>>16) & 0xff,
	       ($address>>8) & 0xff,
	       ($address>>0) & 0xff,
	);
    push @tx, $self->_sumcheck(@tx);

    $self->_send_bytes_ack(@tx)
	or croak "Unexpected response from bootloader.";

    # Clean up and Put the UART mode back for application code.
    $self->disconnect();

    # Let the application come to life.
    sleep 1;

    return 1;
}

# Update
# Use the bootloader for program update.
# Arguments:
#   Address to start update
#   Data (string) to write at address.
# Returns:
#   1 - Success.
sub update($$$) {
    my $self = shift;
    my $address = shift;
    my $data = shift;

    my $block_size = 256;

    # Send data one block at a time.
    while(length($data)) {
	$| = 1;    # Autoflush
	print "."; # Progress.

	# Gather next block of bytes to write.
	my $block = substr($data, 0, $block_size);

	$self->write($address, $block);

	# Discard sent data; keep the remaining data;
	my $count = length($block);
	$data = substr($data, $count);
	$address += $count;
    }
    print "\n";
    $| = 0; # Disable Autoflush

    return 1;
}


# Verify
# Use the bootloader to verify the program.
# Arguments:
#   Address to start verify
#   Data (string) to verify against.
# Returns:
#   1 - Successful verify
#   0 - At least one mismatch
sub verify($$$) {
    my $self = shift;
    my $address = shift;
    my $golden_data = shift;

    my $block_size = 256;

    my $good_count = 0;
    my $bad_count = 0;

    # Read and verify data one block at a time.
    $| = 1;    # Autoflush
    while(length($golden_data)) {
	# Gather next block of data to verify.
	my $golden_block = substr($golden_data, 0, $block_size);
	# Read the same length from Bootloader.
	my $read_block = $self->read($address, length($golden_block));

	# Check they match.
	if ($read_block eq $golden_block) {
	    $good_count++;
	    print "."; # Progress.
	} else {
	    $bad_count++;
	    print "x"; # Progress.
	}

	# Discard verified data; keep the remaining data;
	my $count = length($golden_block);
	$golden_data = substr($golden_data, $count);
	$address += $count;
    }
    print "\n";
    $| = 0; # Disable Autoflush

    print "Verified: $good_count good blocks; $bad_count bad blocks.\n";

    return 0 if($bad_count);
    return 1;
}


# Write block
# Use the bootloader to write a block of memory.
# Arguments:
#   Address to start block
#   Data (string) to write at address.
# Returns:
#   1 - Success.
sub write($$$) {
    my $self = shift;
    my $address = shift;
    my $data_string = shift;

    my @data = split(//, $data_string);
    foreach my $byte ( @data ) {
	$byte = ord($byte);
    }

    # Send Command
    $self->_send_command("Write Memory")
	or croak "Unexpected response from bootloader.";

    # Send Address
    my @tx = ( ($address>>24) & 0xff,
	       ($address>>16) & 0xff,
	       ($address>>8) & 0xff,
	       ($address>>0) & 0xff,
	);
    push @tx, $self->_sumcheck(@tx);
    $self->_send_bytes_ack(@tx)
	or croak "Unexpected response from bootloader.";

    my $count = scalar(@data);

    # Send bytes to write.
    # assemble the frame to send..
    $count--;  # Count is 1 less than bytes to send MCU
    @tx = ();
    push @tx, $count;
    push @tx, ( @data );
    push @tx, $self->_sumcheck(@tx);

    $self->_send_bytes_ack(@tx)
	or croak "Unexpected response from bootloader.";

    return 1;
}


# Read block
# Use the bootloader to read a block of memory.
# Arguments:
#   Address to start block
#   Count of bytes to read.
# Returns:
#   String of read bytes.
sub read($$$) {
    my $self = shift;
    my $address = shift;
    my $count = shift;

    # Send Command
    $self->_send_command("Read Memory")
	or croak "Unexpected response from bootloader.";

    # Send Address
    my @tx = ( ($address>>24) & 0xff,
	       ($address>>16) & 0xff,
	       ($address>>8) & 0xff,
	       ($address>>0) & 0xff,
	);
    push @tx, $self->_sumcheck(@tx);
    $self->_send_bytes_ack(@tx)
	or croak "Unexpected response from bootloader.";

    # Send count to read.
    @tx = ();
    push @tx, ($count-1); # Count is 1 less than bytes to request from MCU
    push @tx, ~$tx[-1] & 0xFF; # Complement as check value.

    $self->_send_bytes_ack(@tx)
	or croak "Unexpected response from bootloader.";

    my $rx = $self->_expect($count);
    return $rx;
}


# Bulk Erase
# Use the bootloader to erase all Flash memory.
# Returns:
#   1 - Success.
sub bulk_erase($) {
    my $self = shift;

    # Send Command
    $self->_send_command("Extended Erase")
	or croak "Unexpected response from bootloader.";

    # Send special code to Erase all flash memory.
    my @tx = ( 0xff,
	       0xff,
	);
    push @tx, $self->_sumcheck(@tx);
    $self->_send_bytes_ack(@tx)
	or croak "Unexpected response from bootloader.";

    return 1;
}


# Notes:
# STBL_DNLOAD(Element.dwAddress, Element.Data, Element.dwDataLength, optimize)
#  -> STBL_WRITE(Address, MAX_DATA_SIZE, buffer);
# STBL_VERIFY(Element.dwAddress, Element.Data, Element.dwDataLength, optimize)
#  -> STBL_READ(Address, MAX_DATA_SIZE, buffer);
# STBL_WRITE_PERM_UNPROTECT()
# STBL_READOUT_PERM_UNPROTECT()
# STBL_ERASE(0xFFFF, NULL);
# all to -> Send_RQ();    


###################################################3
# Internal commands.
###################################################3

# Get command code and sanity check
# Dies if command not supported!
# Argument: Command name
# Returns: Command code
sub _command($$) {
    my $self = shift;
    my $command = shift;

    croak "Unrecognized command"
	unless( exists($DocumentedCommands{$command}) );

    my $code = $DocumentedCommands{$command};

    croak "Command appears unsupported by MCU"
	unless($code ~~ @{$self->SupportedCommands});

    return $code;
}


# Calculate Sumcheck
# Arguments: List of bytes
# Returns: Sumcheck byte
sub _sumcheck($@) {
    my $self = shift;
    my $sum = 0x00;

    while( defined(my $byte = shift) ) {
	$sum ^= $byte;
	$sum &= 0xFF;
    }

    return $sum;
}


# Send a command, complete with complement and expect ACK
# Argument: Command to send.
# Returns:
#   1 - ACK
#   0 - NACK or other response.
sub _send_command($$) {
    my $self = shift;
    my $command = shift;

    # Convert to command code and Sanity check.
    $command = $self->_command($command);

    return $self->_send_bytes_ack($command,
				  ~$command);
}


# Send a string; expect at minimum an ACK
# Argument: String to send.
# Returns:
#   1 - ACK
#   0 - NACK or other response.
sub _send_string_ack($$) {
    my $self = shift;
    my $tx = shift;

    croak "Not connected to bootloader."
	unless $self->is_connected();

    $self->UART->transmit($tx);

    # Expect an ACK response, but nothing else.
    my $rx = $self->_expect_ack(0);
    if(defined($rx)) {
	return 1;
    } else {
	return 0;
    }
}


# Send a list of bytes; expect at minimum an ACK
# Argument: list of bytes to send.
# Returns:
#   1 - ACK
#   0 - NACK or other response.
sub _send_bytes_ack($@) {
    my $self = shift;

    # Construct a string from list of bytes.
    my $tx = "";
    while( defined(my $byte = shift) ) {
	$tx .= chr($byte & 0xFF);
    }

    return $self->_send_string_ack($tx);
}


# Expect some output from bootloader.
# Argument: Number of bytes to expect.  1 if ommitted.
# Returns: Received bytes as string.
sub _expect($$) {
    my $self = shift;
    my $expect_bytes = shift // 1; # expect 1 byte by default.

    croak "Not connected to bootloader."
	unless $self->is_connected();

    my $start_time = time();
    while ( length($self->RXBuffer) <  $expect_bytes ) {
	$self->RXBuffer($self->RXBuffer()
			.$self->UART->receive());
	croak "Timeout waiting to receive byte from UART."
	    if( $self->Timeout() < (time() - $start_time) );
    }

    # Return just the expected chunk from RXBuffer.
    my $expected = substr($self->RXBuffer, 0, $expect_bytes);
    # Keep non-consumed bytes in the RXBuffer.
    $self->RXBuffer(substr($self->RXBuffer, $expect_bytes));

    return $expected;
}


# Expect some output from bootloader; followed by an ACK as last byte.
# Argument: Number of non-ACK bytes to expect.  0 if ommitted.
# Returns: Received bytes as string after ACK stripped.  Undef if NACK.
sub _expect_ack($$) {
    my $self = shift;
    my $expect_bytes = shift // 0;

    # Expect bytes + an ACK byte.
    my $rx = $self->_expect($expect_bytes + 1);

    # Last byte is status.
    my $status = ord(substr($rx, -1, 1));
    # More bytes may exist before the ACK; keep those to return.
    my $rx_data = substr($rx, 0, -1);

    if($status == $self->_command("ACK")) {
	return $rx_data;
    } else {
	# Warn for incorrect response
	warn sprintf("Correct ACK response 0x%02x not received from bootloader.  Got 0x%02x instead.",
		     $self->_command("ACK"),
		     $status);
	return undef;
    }
}

1;
