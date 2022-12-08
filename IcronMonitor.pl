#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib './lib';
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
# Currently unused capabilities
# use ZeeVee::Apto_UART;
# use ZeeVee::SC18IM700;
# use ZeeVee::PCF8575;
# use ZeeVee::SPI_GPIO;
# use ZeeVee::SPIFlash;
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

# Currently Unused
# Caution: This automatically connects/talks to the AddIn Card.
#          it needs altering otherwise.
#my $uart = new ZeeVee::Apto_UART( { Device => $encoder,
#				    Host => $host,
#				    Timeout => $timeout,
#				    Debug => $debug,
#				  } );

# Preparing for non-blocking reads from STDIN.
my $io_select = IO::Select->new();
$io_select->add(\*STDIN);

#Temporary result values.
my $result;
my $expected;

## For video tests, configure encoder and decoder.
# $encoder->start("HDMI");
# $decoder->join($encoder->DeviceID.":HDMI:0",
# 	       "0",
# 	       "genlock" );
## Little low-level, but gets the correct input selected. (add-in card.)
# $encoder->set_property("nodes[HDMI_DECODER:0].inputs[main:0].configuration.source.value", "1");

my $userinput = undef;
do {
    if($io_select->can_read(1.500)){
	$userinput = <STDIN>;
	chomp $userinput;
    }

    if($encoder->is_connected()) {
	$result = $encoder->icron_status();
	print "".scalar localtime()
	    ."\t".$result->{'chip_present'}
	    ."\t".$result->{'mac_address'}
	    ."\n";
    } else {
	print "".scalar localtime()
	    ."\t"."-"
	    ."\t"."-"
	    ."\n";
    }
} until(defined($userinput)
	&& ($userinput eq "q"));
print "\n";
$| = 0;

print "=== DONE. DeviceID = ".$encoder->DeviceID()."===\n";

exit 0;
