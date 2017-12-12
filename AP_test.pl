#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib '.'; # Some platforms (Ubuntu) don't search current directory by default.
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
use ZeeVee::Apto_UART;
use ZeeVee::SC18IM700;
use ZeeVee::PCF8575;
use ZeeVee::SPI_GPIO;
use ZeeVee::SPIFlash;
use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );
use IO::Select;

my $id_mode = "SINGLEENCODER"; # Set to: SINGLEENCODER, NEWENCODER, HARDCODED
my $device_id = 'd880399acbf4';
my $host = '169.254.45.84';
my $port = 6970;
my $edid_filename = './zyper-vga-edid.bin';
my $timeout = 10;
my $debug = 1;
my @output = ();
my $json_template = '/\{.*\}\n/';

my $apto = new ZeeVee::Aptovision_API( { Timeout => $timeout,
					 Host => $host,
					 Port => $port,
					 JSON_Template => $json_template,
					 Debug => $debug,
				       } );

# We must have a single decoder on the test network.
print "Looking for a single decoder.\n";
my $rx_device_id = $apto->find_single_device("all_rx");
print "Using decoder $rx_device_id.\n";

my $decoder = new ZeeVee::BlueRiverDevice( { DeviceID => $rx_device_id,
					     Apto => $apto,
					     Timeout => $timeout,
					     VideoTimeout => 20,
					     Debug => $debug,
					   } );

# Determine the encoder to use for this test.
if( $id_mode eq "NEWENCODER" ) {
    print "Waiting for a new encoder device...\n";
    $device_id = $apto->wait_for_new_device("all_tx");
} elsif ( $id_mode eq "SINGLEENCODER" ) {
    print "Looking for a single encoder.\n";
    $device_id = $apto->find_single_device("all_tx");
} elsif ( $id_mode eq "HARDCODED" ) {
    print "Using hard-coded device: $device_id.\n";
} else {
    die "Unimlemented ID mode: $id_mode.";
}
print "Using encoder (DUT) $device_id.\n";

my $encoder = new ZeeVee::BlueRiverDevice( { DeviceID => $device_id,
					     Apto => $apto,
					     Timeout => $timeout,
					     VideoTimeout => 20,
					     Debug => $debug,
					   } );

my $uart = new ZeeVee::Apto_UART( { Device => $encoder,
				    Host => $host,
				    Timeout => $timeout,
				    Debug => $debug,
				  } );

my $bridge = new ZeeVee::SC18IM700( { UART => $uart,
				      Timeout => $timeout,
				      Debug => $debug,
				    } );

my $sii_gpio = new ZeeVee::PCF8575( { I2C => $bridge,
				      Address => 0x4c,
				      Timeout => $timeout,
				      Debug => $debug,
				      WriteMask => [4, 5, 6, 7, 8],
				    } );

my $cya_gpio = new ZeeVee::PCF8575( { I2C => $bridge,
				      Address => 0x4a,
				      Timeout => $timeout,
				      Debug => $debug,
				      WriteMask => [9, 10, 11, 12, 13, 14, 15],
				    } );

my $spi = new ZeeVee::SPI_GPIO( { GPIO => $cya_gpio,
				  Timeout => $timeout,
				  Debug => $debug,
				  ChunkSize => 512,
				  Bits => { 'Select' => 12,
						'Clock' => 13,
						'MISO' => 14,
						'MOSI' => 15,
				  },
				  Base => 0xffff
				} );

my $flash = new ZeeVee::SPIFlash( { SPI => $spi,
				    Timeout => $timeout,
				    Debug => $debug,
				    PageSize => 256,
				    AddressWidth => 24,
				    Timing => { 'BulkErase' => 6.0,
						    'SectorErase' => 3.0,
						    'PageProgram' => 0.005,
						    'WriteStatusRegister' => 0.015,
				    },
				  } );


# Preparing for non-blocking reads from STDIN.
my $io_select = IO::Select->new();
$io_select->add(\*STDIN);

#Temporary result values.
my $result;
my $expected;

print "UART bridge sanity check.\n";

# Sanity Check the UART bridge device.
# It should probably have baud rate set to 9600, I2C address default 0x26.
$result = $bridge->registerset([0x00, 0x01, 0x06]);
$expected = [0xF0, 0x02, 0x26];
unless( $result ~~ $expected ) {
    my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
    die "The UART bridge at U8 doesn't make sense reading BRG register.\n"
	.$detail_dump."...";
}

# Configure I2C speed to 400kbps (Actually 369kbps)
$result = $bridge->registerset([0x07, 0x08], [0x05, 0x05]);
$expected = [0x05, 0x05];
unless( $result ~~ $expected ) {
    my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
    die "Error setting UART bridge I2C speed to 400kbps.\n"
	.$detail_dump."...";
}

# Configure all GPIO as input at first; except LED BiDir with pull-up.
$expected = [ "Input", "Input", "Input", "QuasiBiDir",
	      "Input", "Input", "Input", "Input" ];
$result = $bridge->gpio_config($expected);
unless( $result ~~ $expected ) {
    my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
    die "Error setting UART bridge GPIO as all inputs.\n"
	.$detail_dump."...";
}

# Read board ID and other GPIO.
$result = $bridge->gpio([1,1,1,1,1,1,1,1]);
$expected = [1,0,0,1,1,1,1,0];
unless( $result ~~ $expected ) {
    my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
    die "Unexpected GPIO state during input test.  Some things to check:\n"
	." - Is this the Analog Port board? [2:0]=2'b001\n"
	." - Are all power rails on? (V3P3, V2P5, V1P0) [3]=1'b1\n"
	." - Is the status LED off? [4]=2'b1\n"
	." - Is the VGA cable connected with a VGA source? [6:5]=2'b11\n"
	." - Is the VGA_DDC_SWITCH net pulled low? [7]=1'b0\n"
	.$detail_dump."...";
}

# Configure GPIO 3,4,6,7 to enable output now.
$expected = [ "Input", "Input", "Input", "QuasiBiDir",
	      "OpenDrain", "Input", "PushPull", "PushPull" ];
$result = $bridge->gpio_config($expected);
unless( $result ~~ $expected ) {
    my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
    die "Error setting UART bridge GPIO 3,4,6,7 to outputs.\n"
	.$detail_dump."...";
}

# Toggle all GPIO that's possible to flip.
$result = $bridge->gpio([1,0,0,0,0,1,0,1]);
$expected = [1,0,0,0,0,1,0,1];
unless( $result ~~ $expected ) {
    my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
    die "Unexpected GPIO state.  Some GPIO couldn't be driven.  Some things to check:\n"
	." - Is MSTR_RST_L driven low? [3]=1'b0\n"
	." - Is the status LED on? [4]=2'b0\n"
	." - Is CABLE_SEL driven low? [6]=2'b0\n"
	." - Is VGA_DDC_SWITCH driven high? [7]=1'b1\n"
	.$detail_dump."...";
}

# Configure GPIO in/out/OD/weak properly for the Analog Port board.
$expected = [ "Input", "Input", "Input", "QuasiBiDir",
	      "OpenDrain", "Input", "Input", "PushPull" ];
$result = $bridge->gpio_config($expected);

print "Blinking LED.  Press return to continue.\n";
my $led_state = 1;
my $userinput = undef;
do {
    $expected = [1,0,0,$led_state,0,1,1,1];
    $result = $bridge->gpio($expected);
    unless( $result ~~ $expected ) {
	my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
	die "Unexpected GPIO state while blinking LED.  Some things to check:\n"
	    ." - Is LED shorted to another net?\n"
	    .$detail_dump."...";
    }
    $led_state = 1 - $led_state; # ugly way to toggle.
    if($io_select->can_read(0.100)){
	$userinput = <STDIN>;
    } else {
	$| = 1; # Autoflush
	print ".";
    }
} until(defined($userinput));
print "\n";
$| = 0;

#FIXME: Access the sii_GPIO
print "SII GPIO test not implemented!!!!!!\n";
#FIXME: Access the cya_GPIO
print "CYA GPIO test not implemented!!!!!!\n";

print "Turning LED on and letting board run (Deassert MSTR_RST_L).\n";

#FIXME: Add checks in the below settings.

# Resetting board.  LED off.  VGA_DDC_SW high.
$bridge->gpio([1,1,1,1,0,1,1,1]);
sleep 0.25;

# Turning off debug mode.  Selecting Analog Audio.
$cya_gpio->write([1,1,1,1,1,1,1,1,
		  1,1,1,1,1,1,1,1]);

# Releasing reset.  LED on.
$bridge->gpio([1,1,1,0,1,1,1,1]);


# Make I2C transactions to EDID SEEPROM.
print "I2C EDID SEEPROM test.\n";
$expected = [ 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47 ];

# Write EDID.
print "I2C EDID SEEPROM Write test.\n";
$result =
    $bridge->i2c_raw( { 'Slave' => 0xA0,
			    'Commands' => [
				{ 'Command' => 'Write',
				      'Data' => [(0x10, @{$expected})],
				},
			    ],
		      } );

#FIXME: Close this loop!  Wait for SEEPROM write.
sleep( 0.05 );

# Read EDID.
print "I2C EDID SEEPROM Read test.\n";
$result =
    $bridge->i2c_raw( { 'Slave' => 0xA0,
			    'Commands' => [
				{ 'Command' => 'Write',
				      'Data' => [ 0x10,
				      ]
				},
				{ 'Command' => 'Read',
				      'Length' => scalar(@{$expected}),
				},
			    ],
		      } );

# Display EDID.
print "Received from EDID: ";
foreach my $byte (@{$result}) {
    printf( "0x%02x, ", $byte );
}
print "\n";

# Compare EDID.
unless( $result ~~ $expected ) {
    my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
    die "Unexpected data read from EDID SEEPROM (U15).  Check: U15, U14\n"
	.$detail_dump."...";
}

# Write final VGA port EDID SEEPROM.
print "Writing VGA EDID SEEPROM.\n";
# Open and read file.
my %edid = ('String' => "",
	    'Data' => [],
	    'Offset' => 0x00,
	    'PageSize' => 8,
	    'MaxLength' => 256);
open( FILE, "<:raw", $edid_filename )
    or die "Can't open file $edid_filename.";
read( FILE, $edid{'String'}, $edid{'MaxLength'} )
    or die "Error reading from file $edid_filename.";
close FILE;
print "Read file $edid_filename.  Length: ".length($edid{'String'})." Bytes.\n";

# Chunk file into page-size arrays.
foreach my $byte (split('', $edid{'String'})) {
    if(($edid{'Offset'} % $edid{'PageSize'}) == 0) {
	push @{$edid{'Data'}}, [];
    }
    push @{$edid{'Data'}->[-1]}, ord($byte);
    $edid{'Offset'}++;
}


# Write/verify EDID one page at a time.
$edid{'Offset'} = 0x00;
print "Data read back from EDID:\n";
foreach my $block (@{$edid{'Data'}}) {
    # Write EDID.
    $result =
	$bridge->i2c_raw( { 'Slave' => 0xA0,
				'Commands' => [
				    { 'Command' => 'Write',
					  'Data' => [($edid{'Offset'}, @{$block})],
				    },
				],
			  } );

    #FIXME: Close this loop!  Wait for SEEPROM write.
    sleep( 0.05 );

    # Read EDID.
    $result =
	$bridge->i2c_raw( { 'Slave' => 0xA0,
				'Commands' => [
				    { 'Command' => 'Write',
					  'Data' => [ $edid{'Offset'},
					  ]
				    },
				    { 'Command' => 'Read',
					  'Length' => scalar(@{$block}),
				    },
				],
			  } );

    # Display EDID.
    printf( "\t0x%04x:\t", $edid{'Offset'} );
    foreach my $byte (@{$result}) {
	printf( "0x%02x ", $byte );
    }
    print "\n";

    # Compare EDID.
    unless( $result ~~ $block ) {
	my $detail_dump = Data::Dumper->Dump([$block, $result], ["Expected", "Result"]);
	die "Unexpected data read from EDID SEEPROM (U15).  Check: U15, U14\n"
	    .$detail_dump."...";
    }

    $edid{'Offset'} += scalar(@{$block});
}
print "VGA EDID SEEPROM written and verified.\n";

#FIXME: Use this idea?
# Take away the mask from unused pins 9, 10 so we can toggle...
#$cya_gpio->WriteMask([11, 12, 13, 14, 15]);

# Write Analog board GPIO expander @ I2C address 0x4C.
# 0xffff Selects "VGA" input:
# 0xfffe Selects "Component Video" input:
# 0xfffd Selects "Composite Video" input:
# 0xfffb Selects "S-Video" input:

# For video tests, configure encoder and decoder.
$encoder->start("HDMI");
$decoder->join($encoder->DeviceID.":HDMI:0",
	       "0",
	       "genlock" );
# Little low-level, but gets the correct input selected. (add-in card.)
$encoder->set_property("nodes[HDMI_DECODER:0].inputs[main:0].configuration.source.value", "1");

print "\n";
print "Selecting S-Video with deinterlacing.  Waiting...\n";
$bridge->gpio([1,1,1,0,0,1,1,1]);
$sii_gpio->write([1,1,0,1,1,1,1,1,
		  1,1,1,1,1,1,1,1]);
sleep 1;
$bridge->gpio([1,1,1,0,1,1,1,1]);

# Wait/Detect if video is there and expected format.
sleep 1.5;
$result = $decoder->hdmi_status(1);
sleep 0.5;
$result = $decoder->hdmi_status(1);  # Had one miss; debounce just in case.
unless( $result->{'video'}->{'width'} eq "720"
	&&  $result->{'video'}->{'height'} eq "480"
	&&  $result->{'video'}->{'scan_mode'} eq "PROGRESSIVE" ) {
    my $detail_dump = Data::Dumper->Dump(['720x480 progressive', $result], ["Expected", "Result"]);
    die "Did not get any video at decoder.\n"
	.$detail_dump."...";
}

print "Video Detected.  Manual check:\n";
print "S-Video input 480p; Press Return when done...\n";
$result = <STDIN>;


print "Selecting S-Video with NO deinterlacing.  Waiting...\n";
$bridge->gpio([1,1,1,0,0,1,1,1]);
$sii_gpio->write([1,1,0,1,1,1,1,1,
		  1,1,0,1,1,1,1,1]);
sleep 1;
$bridge->gpio([1,1,1,0,1,1,1,1]);

# Wait/Detect if video is there and expected format.
sleep 1.5;
$result = $decoder->hdmi_status(1);
sleep 0.5;
$result = $decoder->hdmi_status(1);  # Had one miss; debounce just in case.
unless( $result->{'video'}->{'width'} eq "1440"
	&&  $result->{'video'}->{'height'} eq "480"
	&&  $result->{'video'}->{'scan_mode'} eq "INTERLACED" ) {
    my $detail_dump = Data::Dumper->Dump(['1440x480 interlaced', $result], ["Expected", "Result"]);
    die "Did not get any video at decoder.\n"
	.$detail_dump."...";
}

print "Video Detected.  Manual check:\n";
print "S-Video input 480i; Press Return when done...\n";
$result = <STDIN>;

print "Selecting VGA input.  Waiting...\n";
$bridge->gpio([1,1,1,0,0,1,1,1]);
$sii_gpio->write([1,1,1,1,1,1,1,1,
		  1,1,0,1,1,1,1,1]);
sleep 1;
$bridge->gpio([1,1,1,0,1,1,1,1]);

# Wait/Detect if video is there and expected format.
sleep 1.5;
$result = $decoder->hdmi_status(1);
sleep 0.5;
$result = $decoder->hdmi_status(1);  # Had one miss; debounce just in case.
unless( $result->{'video'}->{'width'} eq "1600"
	&&  $result->{'video'}->{'height'} eq "1200"
	&&  $result->{'video'}->{'scan_mode'} eq "PROGRESSIVE" ) {
    my $detail_dump = Data::Dumper->Dump(['1600x1200 progressive', $result], ["Expected", "Result"]);
    die "Did not get any video at decoder.\n"
	.$detail_dump."...";
}

print "Video Detected.  Manual check:\n";
print "Check VGA; Press Return when done...\n";
$result = <STDIN>;

print "Swap Cables: Remove VGA and S-Video; Connect Component cable.\n";
$result = <STDIN>;
$result = $bridge->gpio();
$expected = [1,0,0,0,1,0,0,1];
unless( $result ~~ $expected ) {
    my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
    die "Unexpected GPIO after Cable swap.  Some things to check:\n"
	." - Did you plug in the Component cable?\n"
	." - Are all power rails on? (V3P3, V2P5, V1P0) [3]=1'b1\n"
	.$detail_dump."...";
}


print "Selecting Composite Video with NO deinterlacing.  Waiting...\n";
$bridge->gpio([1,1,1,0,0,1,1,1]);
$sii_gpio->write([1,0,1,1,1,1,1,1,
		  1,1,0,1,1,1,1,1]);
sleep 1;
$bridge->gpio([1,1,1,0,1,1,1,1]);

# Wait/Detect if video is there and expected format.
sleep 1.5;
$result = $decoder->hdmi_status(1);
sleep 0.5;
$result = $decoder->hdmi_status(1);  # Had one miss; debounce just in case.
unless( $result->{'video'}->{'width'} eq "1440"
	&&  $result->{'video'}->{'height'} eq "480"
	&&  $result->{'video'}->{'scan_mode'} eq "INTERLACED" ) {
    my $detail_dump = Data::Dumper->Dump(['1440x480 interlaced', $result], ["Expected", "Result"]);
    die "Did not get any video at decoder.\n"
	.$detail_dump."...";
}

print "Video Detected.  Manual check:\n";
print "Composite Video input 480i; Press Return when done...\n";
$result = <STDIN>;

print "Selecting Component Video input. SPDIF Audio.  Waiting...\n";
$bridge->gpio([1,1,1,0,0,1,1,1]);
$sii_gpio->write([0,1,1,1,1,1,1,1,
		  1,1,0,1,1,1,1,1]);
$cya_gpio->write([1,1,1,1,1,1,1,1,
		  0,1,1,1,1,1,1,1]);
sleep 1;
$bridge->gpio([1,1,1,0,1,1,1,1]);

# Wait/Detect if video is there and expected format.
sleep 1.5;
$result = $decoder->hdmi_status(1);
sleep 0.5;
$result = $decoder->hdmi_status(1);  # Had one miss; debounce just in case.
unless( $result->{'video'}->{'width'} eq "1920"
	&&  $result->{'video'}->{'height'} eq "1080"
	&&  $result->{'video'}->{'scan_mode'} eq "INTERLACED" ) {
    my $detail_dump = Data::Dumper->Dump(['1920x1080 interlaced', $result], ["Expected", "Result"]);
    die "Did not get any video at decoder.\n"
	.$detail_dump."...";
}

print "Video Detected.  Manual check:\n";
print "Component+SPDIF; Press Return when done...\n";
$result = <STDIN>;

print "Checking Master Reset.  Video LED will blink.\n";

# Confirm video is still good before reset.
$result = $decoder->hdmi_status();
unless( $result->{'source_stable'} == 1
	&& $result->{'video'}->{'width'} eq "1920"
	&& $result->{'video'}->{'height'} eq "1080"
	&& $result->{'video'}->{'scan_mode'} eq "INTERLACED" ) {
    my $detail_dump = Data::Dumper->Dump(['1920x1080 interlaced', $result], ["Expected", "Result"]);
    die "Video not there before reset check.  That was unexpected!\n"
	.$detail_dump."...";
}

# Now assert MSTR_RST_L check video goes away.
$expected = [1,0,0,0,0,0,0,1];
$result = $bridge->gpio($expected);
unless( $result ~~ $expected ) {
    my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
    die "Unexpected GPIO state while testing MSTR_RST_L.  Some things to check:\n"
	." - Is MSTR_RST_L shorted to another net?\n"
	." - Are all power rails on? (V3P3, V2P5, V1P0) [3]=1'b1\n"
	.$detail_dump."...";
}

# Wait/Detect if video has gone away.
$result = $decoder->hdmi_status(0);
$result = $decoder->hdmi_status(0);  # Had one miss; debounce just in case.
unless( $result->{'source_stable'} == 0
	&& $result->{'video'}->{'width'} eq "0"
	&& $result->{'video'}->{'height'} eq "0" ) {
    my $detail_dump = Data::Dumper->Dump(['0x0 not stable', $result], ["Expected", "Result"]);
    die "Video still there after reset asserted.  Check MSTR_RST_L net.\n"
	.$detail_dump."...";
}

$bridge->gpio([1,0,0,0,1,0,0,1]);

print "=== DONE. DeviceID = ".$encoder->DeviceID()."===\n";

exit 0;

__END__

# push @output, $apto->send( "get all hello" );


Check I2C status:
send d880399acbf4 RS232:1 R\x0aP
request 
