#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib '.'; # Some platforms (Ubuntu) don't search current directory by default.
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
use ZeeVee::Apto_UART;
use ZeeVee::SC18IM700;
use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );
use IO::Select;

my $id_mode = "SINGLEENCODER"; # Set to: SINGLEENCODER, NEWENCODER, HARDCODED
my $device_id = 'd880399acbf4';
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

# We must have a single decoder on the test network.
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

# Configure GPIO in/out/OD/weak properly for the Analog Port board.
$expected = [ "Input", "Input", "Input", "QuasiBiDir",
	      "OpenDrain", "Input", "Input", "PushPull" ];
$result = $bridge->gpio_config($expected);

print "Turning LED on and letting board run (Deassert MSTR_RST_L).\n";

# Resetting board.  LED off.  VGA_DDC_SW high.
$bridge->gpio([1,1,1,1,0,1,1,1]);
sleep 0.25;

# Releasing reset.  LED on.
$bridge->gpio([1,1,1,0,1,1,1,1]);

# For video tests, configure encoder and decoder.
$encoder->start("HDMI");
$decoder->join($encoder->DeviceID.":HDMI:0",
	       "0",
	       "genlock" );
# Little low-level, but gets the correct input selected. (add-in card.)
$encoder->set_property("nodes[HDMI_DECODER:0].inputs[main:0].configuration.source.value", "1");

print "=== DONE. DeviceID = ".$encoder->DeviceID()."===\n";

exit 0;
