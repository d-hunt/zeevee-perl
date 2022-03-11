#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib '../lib';
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
use ZeeVee::Apto_UART;
use ZeeVee::DPGlueMCU;
use ZeeVee::STM32Bootloader;
use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );
use IO::Select;

my $id_mode = "SINGLEDEVICE"; # Set to: SINGLEDEVICE, NEWDEVICE, HARDCODED
my $device_id = '801f124d5ecd';
# my $host = '169.254.45.84';
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

# Attempt to access bootloader.
print "UART glue attempt to access bootloader...\n";
$glue->start_bootloader();
sleep 0.5;
$result = $glue->flush_rx();
print "Received and discarded on UART: $result\n"
    if(length($result) > 0);

# Now bootloader is in control.
$bootloader->connect()
    or die "Bootloader start not successful.";
print "Bootloader connected.\n";
$bootloader->get_version();

# Run the application.
my $flash_base = 0x0800_0000;
$bootloader->go($flash_base);
sleep 1.5;  # Let application start.
$result = $glue->flush_rx();
print "Received and discarded on UART: $result\n"
    if(length($result) > 0);

print "UART glue sanity check.\n";
$result = $glue->gpio();
$expected = [0,0,1,1,1,0,0,0];
unless( $result ~~ $expected ) {
    my $detail_dump = Data::Dumper->Dump([$expected, $result], ["Expected", "Result"]);
    die "Unexpected GPIO state during input test.  Some things to check:\n"
	." - Ummm...\n"
	.$detail_dump."...";
}
$result = $glue->version();
print "Version: $result\n\n";

print "=== DONE. DeviceID = ".$decoder->DeviceID()."===\n";

exit 0;
