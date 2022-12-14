#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib '../lib';
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
use ZeeVee::Apto_UART;
use ZeeVee::WebPowerSwitch;
use ZeeVee::JSON_Bool;
use Text::CSV;
use Data::Dumper ();
use Time::HiRes ( qw/sleep time/ );
use IO::File;


# 170 seconds short of thermal cycle (122mins) will get us max measurement
#  distribution in 88 hours we have.  Divide by 4 to get 4 measuremens per
#  cycle, at roughly 30 minute intervals.
my $power_cycle_interval = ( 122*60 - 170 ) / 4; # seconds.
my $power_cycle_off_time = 120; # seconds.
my $power_cycle_on_time = $power_cycle_interval - $power_cycle_off_time; # seconds.

my %device_ids = ( 'TopBackLeft' => 'd88039eb068a',
		   'TopBackRight' => 'd88039eb3ecb',
		   'TopFrontLeft' => 'd88039eb5b07',
		   'TopFrontRight' => 'd88039ead026',
		   'Input' => 'd880399ab2ab',
		   'RX1 (TBL HDMI)' => 'd880399aef39',
		   'RX2 (TBR HDMI)' => 'd880399a9eb0',
		   'RX3 (TFL HDMI)' => 'd880395a8dca',
		   'RX4 (TFR HDMI)' => 'd880395909e9', );
my $host = '169.254.102.48';
my $port = 6970;
my $timeout = 10;
my $debug = 0;
my @output = ();
my $json_template = '/\{.*\}\n/';

my $power_switch = new ZeeVee::WebPowerSwitch( { Host => '10.10.10.3',
						 Port => 80,
						 User => 'admin',
						 Password => 'zazzle',
						 Timeout => 10,
						 Debug => 0,
					       } );

my $apto = new ZeeVee::Aptovision_API( { Timeout => $timeout,
					 Host => $host,
					 Port => $port,
					 JSON_Template => $json_template,
					 Debug => $debug,
				       } );

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

my $logfile = IO::File->new();
$logfile->open("./powercycle.log", '>>')
    or die "Can't open logfile for writing: $! ";

# Prepare for CSV output and print header.
my $csv = new Text::CSV({ 'binary' => 1,
			      'eol' => "\r\n" })
    or die "Failed to create Text::CSV object because".Text::CSV->error_diag()." ";
my @column_names = ( 'Epoch',
		     'Date',
		     'Power Cycle',
		     'Power State',
		     'Up Time',
		     'Device Name',
		     'DeviceID',
		     'isConnected',
		     'Temperature',
		     'Source Stable',
		     'Video Width',
		     'Video Height',
		     'Video FPS',
		     'Video Scan Mode',
		     'Video Color Space',
		     'Video BPP',
		     'HDCP Protected',
		     'HDCP Version',
		     'VD active_format',
		     'VD it_content_type',
		     'VD colorimetry',
		     'VD hsync_negative',
		     'VD hsync_width',
		     'VD has_hdmi_vic',
		     'VD scan_information',
		     'VD hsync_front_porch',
		     'VD picture_aspect',
		     'VD total_width',
		     'VD vsync_front_porch',
		     'VD rgb_range',
		     'VD vsync_negative',
		     'VD total_height',
		     'VD ycc_range',
		     'VD has_active_format',
		     'VD vic',
		     'VD vsync_width',
		     'VD hdmi_vic',
		     'VD pixel_clock',
    );
$csv->column_names( \@column_names );
$csv->print( $logfile, \@column_names );

# Power off in preperation.
print scalar localtime ."\t";
print "Turning off Power.\n";
$power_switch->powerOff(1);
$power_switch->powerOff(2);
$power_switch->powerOff(3);
$power_switch->powerOff(4);
sleep 2;
# Start autoflushing STDOUT
$| = 1;

my $current_cycle = 0;
my $global_start_time = time();
my $power_state = "OFF";
my $power_on_time = undef;
my $last_wake_time = int($global_start_time) + 1;
while(1) {
    my $current_time = time();
    my $up_time = undef;
    $up_time = $current_time - $power_on_time
	if( defined( $power_on_time ) );

    my $modulo_cycle_time = ($current_time - $global_start_time) % $power_cycle_interval;
    if( ($power_state eq "ON")
	&& $modulo_cycle_time > $power_cycle_on_time ) {
	print scalar localtime ."\t";
	print "Turning off Power.\n";
	$power_switch->powerOff(1);
	$power_switch->powerOff(2);
	$power_switch->powerOff(3);
	$power_switch->powerOff(4);
	$power_state = "OFF";
	$power_on_time = undef;
    } elsif( ($power_state eq "OFF")
	     && $modulo_cycle_time < $power_cycle_on_time ) {
	print scalar localtime ."\t";
	print "Turning on Power.\n";
	$power_switch->powerOn(1);
	$power_switch->powerOn(2);
	$power_switch->powerOn(3);
	$power_switch->powerOn(4);
	#$power_switch->powerCycle(5);
	$power_state = "ON";
	$power_on_time = time();
	$current_cycle++;
    }

    # Check and log each device status.
    foreach my $name (sort keys %devices) {
	my $device = $devices{$name};
	my $hdmi_status = $device->hdmi_status();
	# The basic data we're collecting
	my %data = ( 'Epoch' => $current_time,
		     'Date' => scalar localtime($current_time),
		     'Power Cycle' => $current_cycle,
		     'Power State' => $power_state,
		     'Up Time' => $up_time,
		     'Device Name' => $name,
		     'DeviceID' => $device->DeviceID(),
		     'isConnected' => ( $device->is_connected() ? "YES" : "NO" ),
		     'Temperature' => $device->__temperature(),
		     'Source Stable' => ZeeVee::JSON_Bool::to_YN( $hdmi_status->{'source_stable'} ),
		     'Video Width' => $hdmi_status->{'video'}->{'width'},
		     'Video Height' => $hdmi_status->{'video'}->{'height'},
		     'Video FPS' => $hdmi_status->{'video'}->{'frames_per_second'},
		     'Video Scan Mode' => $hdmi_status->{'video'}->{'scan_mode'},
		     'Video Color Space' => $hdmi_status->{'video'}->{'color_space'},
		     'Video BPP' => $hdmi_status->{'video'}->{'bits_per_pixel'},
		     'HDCP Protected' => ZeeVee::JSON_Bool::to_YN( $hdmi_status->{'hdcp_protected'} ),
		     'HDCP Version' => $hdmi_status->{'hdcp_version'},
	    );

	# Iterate through video_details and add those to data we keep too.
	foreach my $key (keys %{$hdmi_status->{'video_details'}}) {
	    my $value = $hdmi_status->{'video_details'}->{"$key"};
	    if(JSON::is_bool($value)) {
		$value = ZeeVee::JSON_Bool::to_YN( $value );
	    }
	    $data{"VD $key"} = $value;
	}

	$csv->print_hr( $logfile,
			\%data );
    }

    $logfile->flush();

    # Wait for next 10s mark.
    $last_wake_time += 10;
    $current_time = time();
    if($last_wake_time > $current_time) {
	sleep $last_wake_time - $current_time;
    } else {
	$last_wake_time += 10;
	warn "Fell behind on 10s polls at $current_time.  Buying extra time.";
    }
}

# Never reached.
exit 255;

__END__

# Hints for setting up start/join the video.

# For video tests, configure encoder and decoder.
$encoder->start("HDMI");
$decoder->join($encoder->DeviceID.":HDMI:0",
	       "0",
	       "genlock" );
# Little low-level, but gets the correct input selected. (add-in card.)
$encoder->set_property("nodes[HDMI_DECODER:0].inputs[main:0].configuration.source.value", "1");
