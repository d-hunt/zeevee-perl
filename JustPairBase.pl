#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib './lib';
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );
use IO::Select;

my $id_mode = "SINGLEENCODER"; # Set to: SINGLEENCODER, NEWENCODER, HARDCODED
my $device_id = 'd880399acbf4';
my $host = '172.16.1.90';
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

$encoder->start("HDMI");
$decoder->join($encoder->DeviceID.":HDMI:0",
	       "0",
	       "genlock" );
#	       "fastswitch size 1920 1080 fps 60.000" );
#	       "fastswitch size 1920 1080 fps 60.004" );
#	       "fastswitch size 1920 1080 fps 120" );
#	       "fastswitch size 2560 1440 fps 60 stretch" );
#	       "fastswitch size 2560 1800 fps 60 total 2720 1852 pulse 32 4 front_porch 48 3" );
#	       "fastswitch size 2560 1800 fps 60 total 3520 1865 pulse 280 4 front_porch 200 3" );
#	       "fastswitch size 2560 1440 fps 60 total 2720 1481 pulse 32 5 front_porch 48 3 polarity positive positive" );
#	       "fastswitch quantization AUTO size 1920 1080 fps 60 stretch" );

# Little low-level, but gets the correct input selected. (HDMI input.)
$encoder->set_property("nodes[HDMI_DECODER:0].inputs[main:0].configuration.source.value", "0");

sleep 2;
my $hdmi_status = $encoder->hdmi_status();
print Data::Dumper->Dump([$hdmi_status], ["HDMI Status"]);

print "=== DONE. DeviceID = ".$encoder->DeviceID()."===\n";

exit 0;
