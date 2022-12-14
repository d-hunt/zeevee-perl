#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib '../lib';
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
use ZeeVee::Apto_UART;
use ZeeVee::DPGlueMCU;
use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );
use IO::Select;

my $id_mode = "SINGLEDEVICE"; # Set to: SINGLEDEVICE, NEWDEVICE, HARDCODED
my $device_id = 'd880399acbf4';
#my $host = '169.254.45.84';
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

# Determine the decoder to use for this test.
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
print "Using decoder (DUT) $device_id.\n";

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
				    Timeout => 30, #$timeout,
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
print "\n";

print "Glue MCU Version: "
    .$glue->version()
    ."\n";
print "\n";

print "Probing EP9162S MCU BootBlock.\n";
$glue->EP_BB_program_enable_Splitter();
print "\tBB version: ".$glue->EP_BB_version();
print "\tFW version: ".$glue->EP_BB_FW_version();
print "\tFW checksum: ".$glue->EP_BB_FW_checksum();
print "\n";
print "Returning EP9162S MCU to normal operation.\n";
$glue->EP_BB_program_disable();
print "\n";

print "Probing EP9169S MCU BootBlock.\n";
$glue->EP_BB_program_enable_DPRX();
print "\tBB version: ".$glue->EP_BB_version();
print "\tFW version: ".$glue->EP_BB_FW_version();
print "\tFW checksum: ".$glue->EP_BB_FW_checksum();
print "\n";
print "Returning EP9169S MCU to normal operation.\n";
$glue->EP_BB_program_disable();
print "\n";

print "Probing EP169E MCU BootBlock.\n";
$glue->EP_BB_program_enable_DPTX();
print "\tBB version: ".$glue->EP_BB_version();
print "\tFW version: ".$glue->EP_BB_FW_version();
print "\tFW checksum: ".$glue->EP_BB_FW_checksum();
print "\n";
print "Returning EP169E MCU to normal operation.\n";
$glue->EP_BB_program_disable();
print "\n";

print "=== DONE. DeviceID = ".$decoder->DeviceID()."===\n";

exit 0;
