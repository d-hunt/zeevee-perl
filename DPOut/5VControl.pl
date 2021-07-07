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

my $hdmiport = $ARGV[0] // 'HDMI';
my $mode = $ARGV[1] // 'Auto';

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
				    Timeout => $timeout,
				    Debug => $debug,
				  } );

my $command;

if( lc($hdmiport) eq lc('HDMI') ) {
    $command .= "HDMI5V";
} elsif( lc($hdmiport) eq lc('AddIn') ) {
    $command .= "AddIn5V";
} else {
    die "I only know of HDMI or AddIn ports.";
}
$command .= " ";

if( lc($mode) eq lc('Auto') ) {
    $command .= "Auto"
} elsif ( lc($mode) eq lc('Inhibit') ) {
    $command .= "Inhibit"
} else {
    die "I only know of Auto or Inhibit modes.";
}
$command .= "P";
    

print "Minimum v2:1 required.  Version: ".$glue->version()."\n";

$uart->transmit($command);

my $rx = "";
my $start_time = time();
do {
    $rx .= $uart->receive();
    die "Timeout waiting to receive byte from UART."
	if($timeout < (time() - $start_time) );
} while ( substr($rx,-1,1) ne "\n" );
chomp $rx;
print "$rx\n";


exit 0;
