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

my $id_mode = "HARDCODED"; # Set to: SINGLEDEVICE, NEWDEVICE, HARDCODED
my %device_ids = ( 'Decoder' => 'd88039eb3ecb',
		   'Encoder' => 'd880399ab062');
#my $host = '169.254.45.84';
my $host = '172.16.1.90';
#my $host = '10.10.0.6';
my $port = 6970;
my $timeout = 10;
my $debug = 0;
my @output = ();
my $json_template = '/\{.*\}\n/';

my $hdmiport = $ARGV[0] // 'HDMI';

my $apto = new ZeeVee::Aptovision_API( { Timeout => $timeout,
					 Host => $host,
					 Port => $port,
					 JSON_Template => $json_template,
					 Debug => $debug,
				       } );

# Determine the decoder to use for this test.
if( $id_mode eq "NEWDEVICE" ) {
    print "Waiting for a new decoder device...\n";
    $device_ids{"Decoder"} = $apto->wait_for_new_device("all_rx");
    print "Waiting for a new encoder device...\n";
    $device_ids{"Encoder"} = $apto->wait_for_new_device("all_tx");
} elsif ( $id_mode eq "SINGLEDEVICE" ) {
    print "Looking for a single decoder.\n";
    $device_ids{"Decoder"} = $apto->find_single_device("all_rx");
    print "Looking for a single encoder.\n";
    $device_ids{"Encoder"} = $apto->find_single_device("all_tx");
} elsif ( $id_mode eq "HARDCODED" ) {
    foreach my $device_name (sort keys %device_ids) {
	print "Using hard-coded $device_name device: ".$device_ids{$device_name}.".\n";
    }
} else {
    die "Unimlemented ID mode: $id_mode.";
}

my %devices = ();
foreach my $device_name (sort keys %device_ids) {
    $devices{$device_name} =
	new ZeeVee::BlueRiverDevice( { DeviceID => $device_ids{$device_name},
				       Apto => $apto,
				       Timeout => $timeout,
				       VideoTimeout => 20,
				       Debug => $debug,
				     } );
}

my $uart = new ZeeVee::Apto_UART( { Device => $devices{"Decoder"},
				    Host => $host,
				    Timeout => $timeout,
				    Debug => $debug,
				  } );

my $glue = new ZeeVee::DPGlueMCU( { UART => $uart,
				    Timeout => $timeout,
				    Debug => $debug,
				  } );

my %command;
if( lc($hdmiport) eq lc('HDMI') ) {
    $command{"Auto"} = "HDMI5V AutoP";
    $command{"Inhibit"} = "HDMI5V InhibitP";
} elsif( lc($hdmiport) eq lc('AddIn') ) {
    $command{"Auto"} .= "AddIn5V AutoP";
    $command{"Inhibit"} .= "AddIn5V InhibitP";
} else {
    die "I only know of HDMI or AddIn ports.";
}

# Start autoflushing STDOUT
$| = 1;

print "Minimum v2:1 required.  Version: ".$glue->version()."\n";

sub send_command {
    my $command = shift;
    my $retries = 5;

    my $rx = "";
    do {
	$uart->transmit($command);

	my $start_time = time();
	{ # BLOCK For 'last' to work as expected.
	    do {
		$rx .= $uart->receive();
		if($timeout < (time() - $start_time) ) {
		    warn "Timeout waiting to receive byte from UART.";
		    last;
		}
	    } while ( substr($rx,-1,1) ne "\n" );
	} # <-- 'last' comes here.
    } while( substr($rx,-1,1) ne "\n"
	     && --$retries );
    chomp $rx;
    print "Response: $rx\n";
}

my @resolutions = ( 'fastswitch size 3840 2160 fps 30',
		    'fastswitch size 3840 2160 fps 25',
		    'fastswitch size 3840 2160 fps 24',
		    'fastswitch size 1920 1080 fps 60',
		    'fastswitch size 1920 1080 fps 50',
		    'fastswitch size 1920 1080 fps 30',
		    'fastswitch size 1920 1080 fps 25',
		    'fastswitch size 1920 1080 fps 24',
		    'fastswitch size 1280 720 fps 60',
		    'fastswitch size 1280 720 fps 50',
		    'fastswitch size 1280 720 fps 30',
		    'fastswitch size 1280 720 fps 25',
		    'fastswitch size 1280 720 fps 24',
		    'fastswitch size 720 480 fps 60',
		    'fastswitch size 720 480 fps 50',
		    'fastswitch size 720 480 fps 30',
		    'fastswitch size 720 480 fps 25',
		    'fastswitch size 720 480 fps 24',
		    'fastswitch size 2560 1440 fps 60',
		    'fastswitch size 1920 1200 fps 60',
		    'fastswitch size 1600 1200 fps 60',
		    'fastswitch size 1680 1050 fps 60',
		    'fastswitch size 1280 1024 fps 60',
		    'fastswitch size 800 600 fps 60',
		    'fastswitch size 640 480 fps 60',
		    'fastswitch size 1920 1080 fps 120', );

my $sleepmin = 20; # seconds
my $sleepjitter = 15; # seconds
while(1) {
    foreach my $resolution (@resolutions) {
	my $current_time = time();
	my $sleep = $sleepmin;
	$sleep += rand($sleepjitter);

	send_command($command{"Inhibit"});

	print $current_time."\t".(scalar localtime($current_time))."\t".$resolution."\t".$sleep."\n";

	$devices{"Decoder"}->join($devices{"Encoder"}->DeviceID.":HDMI:0",
				  "0",
				  $resolution );
	sleep($sleep);
	send_command($command{"Auto"});
	sleep($sleep);
    }
}

exit 0;
