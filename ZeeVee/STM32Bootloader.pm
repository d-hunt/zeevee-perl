# Perl module for speaking to STM32 Bootloader.
package ZeeVee::STM32Bootloader;
use Class::Accessor "antlers";

use strict;
use warnings;
no warnings 'experimental::smartmatch';

use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );
use Carp;

$Carp::Verbose = 1; # Force Stack Traces.

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
has SupportedCommands => ( is => "rw" );
has RXBuffer => ( is => "rw" ); # Because we may receive more than we asked.

# Constructor for STM32Bootloader object.
sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};
    
    unless( exists $arg_ref->{'UART'} ) {
	croak "Bootloader can't work without a UART connection to device.  UART has to have 'transmit' and 'receive' methods.";
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
    
    my $self = $class->SUPER::new( $arg_ref );

    $self->initialize();
    
    return $self;
}


# Any initialization necessary.
sub initialize($) {
    my $self = shift;

    # Start with empty RX Buffer.
    $self->RXBuffer("");

    # Start with some assumptions about Supported commands.
    $self->SupportedCommands([ $DocumentedCommands{"SYNC"},
			       $DocumentedCommands{"ACK"},
			       $DocumentedCommands{"NACK"},
			       $DocumentedCommands{"Get"},
			     ]);
    
    return;
}


# Get command code and sanity check
# Dies if command no supported!
# Argument: Command name
# Returns: Command code
sub command($$) {
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
sub sumcheck($@) {
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
sub send_command($$) {
    my $self = shift;
    my $command = shift;

    # Convert to command code and Sanity check.
    $command = $self->command($command);

    return $self->send_bytes_ack($command,
				 ~$command);
}


# Send a string; expect at minimum an ACK
# Argument: String to send.
# Returns:
#   1 - ACK
#   0 - NACK or other response.
sub send_string_ack($$) {
    my $self = shift;
    my $tx = shift;

    $self->UART->transmit($tx);

    # Expect an ACK response, but nothing else.
    my $rx = $self->expect_ack(0);
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
sub send_bytes_ack($@) {
    my $self = shift;

    # Construct a string from list of bytes.
    my $tx = "";
    while( defined(my $byte = shift) ) {
	$tx .= chr($byte & 0xFF);
    }

    return $self->send_string_ack($tx);
}


# Expect some output from bootloader.
# Argument: Number of bytes to expect.  1 if ommitted.
# Returns: Received bytes as string.
sub expect($$) {
    my $self = shift;
    my $expect_bytes = shift // 1; # expect 1 byte by default.
    
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
sub expect_ack($$) {
    my $self = shift;
    my $expect_bytes = shift // 0;

    # Expect bytes + an ACK byte.
    my $rx = $self->expect($expect_bytes + 1);

    # Last byte is status.
    my $status = ord(substr($rx, -1, 1));
    # More bytes may exist before the ACK; keep those to return.
    my $rx_data = substr($rx, 0, -1);

    if($status == $self->command("ACK")) {
	return $rx_data;
    } else {
	# Warn for incorrect response
	warn sprintf("Correct ACK response 0x%02x not received from bootloader.  Got 0x%02x instead.",
		     $self->command("ACK"),
		     $status);
	return undef;
    }
}


# Bootloader Connect
# Accesses the bootloader for updates.
# Returns:
#   1 - successfully contacted bootloader.
#   0 - did not find bootloader.
sub connect($) {
    my $self = shift;

    # FIXME:
    # FIXME: Do we need to manipulate 8E1 vs 8N1 UART here or elsewhere?
    # FIXME:
    
    # Bootloader uses even parity.
    $self->UART->initialize(57600, "8E1");
    sleep 0.5;
    
    # Send init/sync command 0x7F.
    my $sync = $self->command("SYNC");
    if( $self->send_bytes_ack($sync) ) {
	return 1;
    } else {
	# That didn't work.  Put the UART mode back.
	# FIXME: hack w/ hard-coding.
	$self->UART->initialize(9600, "8N1");
	return 0;
    }
}


# Get version and supported commands
# Get the bootloader version and commands.
sub get_version($) {
    my $self = shift;

    $self->send_command("Get")
	or croak "Unexpected response.  I wouldn't know what to do...";

    # Get at least one more byte (count).
    my $count = ord($self->expect(1));
    $count++; # Count is 1 short from MCU
    
    # Get the remaining bytes based on count received.
    my $rx = $self->expect_ack($count);
    
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
sub go($$) {
    my $self = shift;
    my $address = shift;

    # Send Command
    $self->send_command("Go")
	or croak "Unexpected response from bootloader.";

    # Send Address
    my @tx = ( ($address>>24) & 0xff,
	       ($address>>16) & 0xff,
	       ($address>>8) & 0xff,
	       ($address>>0) & 0xff,
	);
    push @tx, $self->sumcheck(@tx);

    $self->send_bytes_ack(@tx)
	or croak "Unexpected response from bootloader.";

    # Put the UART mode back for application code.
    # FIXME: hack w/ hard-coding.
    $self->UART->initialize(9600, "8N1");

    # Let the application come to life.
    sleep 1.5;
    
    return 1;
}

# Update
# Use the bootloader for program update.
# Arguments:
#   Address to start update
#   Data (string) to write at address.
sub update($$$) {
    my $self = shift;
    my $address = shift;
    my $data_string = shift;

    my $block_size = 256;

    my @data = split(//, $data_string);;
    foreach my $byte ( @data ) {
	$byte = ord($byte);
    }
    
    # Send data one block at a time.
    while(scalar(@data)) {
	$| = 1;    # Autoflush
	print "."; # Progress.
	
	# Send Command
	$self->send_command("Write Memory")
	    or croak "Unexpected response from bootloader.";

	# Send Address
	my @tx = ( ($address>>24) & 0xff,
		   ($address>>16) & 0xff,
		   ($address>>8) & 0xff,
		   ($address>>0) & 0xff,
	    );
	push @tx, $self->sumcheck(@tx);
	$self->send_bytes_ack(@tx)
	    or croak "Unexpected response from bootloader.";

	# Gather next block of bytes to write.
	my @block = ();
	while(scalar(@block) < $block_size) {
	    my $byte = shift @data;
	    last unless( defined($byte) );
	    push @block, $byte;
	}
	my $count = scalar(@block);
	$address += $count;

	# Send bytes to write.
	# assemble the frame to send..
	$count--;  # Count is 1 less than bytes to send MCU
	@tx = ();
	push @tx, $count;
	push @tx, ( @block );
	push @tx, $self->sumcheck(@tx);

	$self->send_bytes_ack(@tx)
	    or croak "Unexpected response from bootloader.";
    }
    print "\n";
    $| = 0; # Disable Autoflush

    
    # Notes:
    # STBL_DNLOAD(Element.dwAddress, Element.Data, Element.dwDataLength, optimize)
    #  -> STBL_WRITE(Address, MAX_DATA_SIZE, buffer);
    # STBL_VERIFY(Element.dwAddress, Element.Data, Element.dwDataLength, optimize)
    #  -> STBL_READ(Address, MAX_DATA_SIZE, buffer);
    # STBL_WRITE_PERM_UNPROTECT()
    # STBL_READOUT_PERM_UNPROTECT()
    # STBL_ERASE(0xFFFF, NULL);
    # all to -> Send_RQ();
    
    
    
    return 1;
}

1;
