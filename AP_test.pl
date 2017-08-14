#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';
use ZeeVee::Aptovision_API;
use ZeeVee::Apto_UART;
use ZeeVee::SC18IM700;
use ZeeVee::PCF8575;
use ZeeVee::SPI_GPIO;
use ZeeVee::SPIFlash;
use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );
use IO::Select;

my $device = 'd880399acbf4';
my $host = '169.254.45.84';
my $port = 6970;
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

my $uart = new ZeeVee::Apto_UART( { Device => $device,
				    Apto => $apto,
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


my $io_select = IO::Select->new();
$io_select->add(\*STDIN);

#Temporary result value.
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
    if($io_select->can_read(0.05)){
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
    printf( "0x%x, ", $byte );
}
print "\n";

# Compare EDID.
unless( $result ~~ $expected ) {
    my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
    die "Unexpected data read from EDID SEEPROM (U15).  Check: U15, U14\n"
	.$detail_dump."...";
}

#FIXME: Use this idea?
# Take away the mask from unused pins 9, 10 so we can toggle...
#$cya_gpio->WriteMask([11, 12, 13, 14, 15]);

# Write Analog board GPIO expander @ I2C address 0x4C.
# 0xffff Selects "VGA" input:
# 0xfffe Selects "Component Video" input:
# 0xfffd Selects "Composite Video" input:
# 0xfffb Selects "S-Video" input:

print "Selecting S-Video with deinterlacing.\n";
$sii_gpio->write([1,1,0,1,1,1,1,1,
		  1,1,1,1,1,1,1,1]);

print "Check S-Video input 480p; Press Return when done...\n";
$result = <STDIN>;

#FIXME: Access HDMI properties to check.

print "Selecting S-Video with NO deinterlacing.\n";
$sii_gpio->write([1,1,0,1,1,1,1,1,
		  1,1,0,1,1,1,1,1]);
print "Check S-Video input 480i; Press Return when done...\n";
$result = <STDIN>;

print "Selecting VGA input.\n";
$sii_gpio->write([1,1,1,1,1,1,1,1,
		  1,1,0,1,1,1,1,1]);
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


print "Selecting Composite Video with NO deinterlacing.\n";
$sii_gpio->write([1,0,1,1,1,1,1,1,
		  1,1,0,1,1,1,1,1]);
print "Check Composite Video input 480i; Press Return when done...\n";
$result = <STDIN>;

print "Selecting Component Video input. SPDIF Audio.\n";
$sii_gpio->write([0,1,1,1,1,1,1,1,
		  1,1,0,1,1,1,1,1]);
$cya_gpio->write([1,1,1,1,1,1,1,1,
		  0,1,1,1,1,1,1,1]);
print "Check Component+SPDIF; Press Return when done...\n";
$result = <STDIN>;

print "Checking Master Reset.  Watch for Video LED to blink.  Press Return when done...\n";
my $rst_state = 1;
$userinput = undef;
do {
    $expected = [1,0,0,0,$rst_state,0,0,1];
    $result = $bridge->gpio($expected);
    unless( $result ~~ $expected ) {
	my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
	die "Unexpected GPIO state while testing MSTR_RST_L.  Some things to check:\n"
	    ." - Is MSTR_RST_L shorted to another net?\n"
	    ." - Are all power rails on? (V3P3, V2P5, V1P0) [3]=1'b1\n"
	    .$detail_dump."...";
    }
    sleep 5 if($rst_state == 1);  # it takes longer to get video.
    $rst_state = 1 - $rst_state; # ugly way to toggle.
    if($io_select->can_read(0.05)){
	$userinput = <STDIN>;
    } else {
	$| = 1; # Autoflush
	print ".";
    }
} until(defined($userinput));
print "\n";
$| = 0;


#FIXME: Check MSTR_RST_L and get HDMI properties bounce.

print "DONE.\n";

exit 0;

__END__

# push @output, $apto->send( "get all hello" );


Check I2C status:
send d880399acbf4 RS232:1 R\x0aP
request 
