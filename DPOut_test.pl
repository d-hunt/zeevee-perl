#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib '.'; # Some platforms (Ubuntu) don't search current directory by default.
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
use ZeeVee::Apto_UART;
use ZeeVee::DPGlueMCU;
use ZeeVee::STM32Bootloader;
use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );
use IO::Select;

my $id_mode = "SINGLEDEVICE"; # Set to: SINGLEDEVICE, NEWDEVICE, HARDCODED
my $device_id = 'd880399acbf4';
# my $host = '169.254.45.84';
my $host = '172.16.1.52';
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

# We must have a single encoder on the test network.
print "Looking for a single encoder.\n";
my $tx_device_id = $apto->find_single_device("all_tx");
print "Using decoder $tx_device_id.\n";

my $encoder = new ZeeVee::BlueRiverDevice( { DeviceID => $tx_device_id,
					     Apto => $apto,
					     Timeout => $timeout,
					     VideoTimeout => 20,
					     Debug => $debug,
					   } );

# Determine the encoder to use for this test.
if( $id_mode eq "NEWDEVICE" ) {
    print "Waiting for a new decoder device...\n";
    $device_id = $apto->wait_for_new_device("all_rx");
} elsif ( $id_mode eq "SINGLEDEVICE" ) {
    print "Looking for a single decoder.\n";
    $device_id = $apto->find_single_device("all_rx");
} elsif ( $id_mode eq "HARDCODED" ) {
    print "Using hard-coded device: $device_id.\n";
} else {
    die "Unimlemented ID mode: $id_mode.";
}
print "Using encoder (DUT) $device_id.\n";

my $decoder = new ZeeVee::BlueRiverDevice( { DeviceID => $device_id,
					     Apto => $apto,
					     Timeout => $timeout,
					     VideoTimeout => 20,
					     Debug => $debug,
					   } );

my $uart = new ZeeVee::Apto_UART( { Device => $decoder,
				    Host => $host,
				    Timeout => $timeout,
				    Debug => $debug,
				  } );

my $glue = new ZeeVee::DPGlueMCU( { UART => $uart,
				    Timeout => $timeout,
				    Debug => $debug,
				  } );

# FIXME: Get smarter about this:
my $bootloader = new ZeeVee::STM32Bootloader( { UART => $uart,
						Timeout => $timeout,
						Debug => $debug,
					      } );


# Preparing for non-blocking reads from STDIN.
my $io_select = IO::Select->new();
$io_select->add(\*STDIN);

#Temporary result values.
my $result;
my $expected;

print "BlueRiver Device Die Temperature: "
    .$decoder->temperature()
    ."\n";

print "UART glue cLVDS lanes.\n";
$glue->cLVDS_lanes(2);

# Attempt to access bootloader.
print "UART glue attempt to access bootloader...  ";
$glue->start_bootloader();
sleep 0.5;
if($bootloader->connect()) {
    print "Success.\n";
    $bootloader->get_version();

    # Open and read file.
    my $flash_base = 0x0800_0000;
    my $filename = "Charlie_DP_GlueMCU.bin";
    my $max_filesize = (256 * 1024);
    my $data_string = "";
    open( FILE, "<:raw", $filename )
	or die "Can't open file $filename.";
    read( FILE, $data_string, $max_filesize )
	or die "Error reading from file $filename.";
    close FILE;
    print "Read file $filename.  Length: ".length($data_string)." Bytes.\n";
    $bootloader->update($flash_base, $data_string);

    # Run the application.
    $bootloader->go($flash_base);
} else {
    print "Failed.\n";
}

print "UART glue lane thrash check.\n";

$glue->cLVDS_lanes(8);
sleep 1;
$glue->cLVDS_lanes(4);
sleep 1;
$glue->cLVDS_lanes(2);
sleep 1;
$glue->cLVDS_lanes(1);
sleep 1;


print "UART glue sanity check.\n";

# Sanity Check the UART glue device.
# It should probably have baud rate set to 9600, I2C address default 0x26.
#$result = $glue->registerset([0x00, 0x01, 0x06]);
#$expected = [0xF0, 0x02, 0x26];
#unless( $result ~~ $expected ) {
#    my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
#    die "The UART glue at U8 doesn't make sense reading BRG register.\n"
#	.$detail_dump."...";
#}

# Configure I2C speed to 400kbps (Actually 369kbps)
#$result = $glue->registerset([0x07, 0x08], [0x05, 0x05]);
#$expected = [0x05, 0x05];
#unless( $result ~~ $expected ) {
#    my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
#    die "Error setting UART glue I2C speed to 400kbps.\n"
#	.$detail_dump."...";
#}

# Read board ID and other GPIO.
#$result = $glue->gpio([1,1,1,1,1,1,1,1]);
$result = $glue->gpio();
$expected = [0,0,1,1,1,0,0,0];
unless( $result ~~ $expected ) {
    my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
    die "Unexpected GPIO state during input test.  Some things to check:\n"
	." - Ummm...\n"
	.$detail_dump."...";
}

# For video tests, configure encoder and decoder.
$encoder->start("HDMI");
$decoder->join($encoder->DeviceID.":HDMI:0",
	       "0",
	       "genlock" );
# Little low-level, but gets the correct input selected. (add-in card.)
#$encoder->set_property("nodes[HDMI_DECODER:0].inputs[main:0].configuration.source.value", "1");


print "=== DONE. DeviceID = ".$encoder->DeviceID()."===\n";

exit 0;
