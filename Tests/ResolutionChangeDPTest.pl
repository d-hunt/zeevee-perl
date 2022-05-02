#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib '../lib';
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
use ZeeVee::Apto_UART;
use ZeeVee::DPGlueMCU;
use ZeeVee::JSON_Bool;
use Text::CSV;
use Data::Dumper ();
use Time::HiRes ( qw/sleep time/ );
use IO::File;


my $dwell_time = 30; # seconds.
my $poll_time = 10;   # seconds.

my %device_ids = ( 'DPDecoder' => 'd88039ead017',
		   'DPEncoder' => 'd8803959aceb');
my $host = '172.16.1.90';
my $port = 6970;
my $timeout = 10;
my $debug = 0;
my @output = ();
my $json_template = '/\{.*\}\n/';

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

my %glueMCUs = ();
foreach my $device_name (sort keys %device_ids) {
    next unless( $device_name eq "DPDecoder" );
    my $uart = new ZeeVee::Apto_UART( { Device => $devices{$device_name},
					Host => $host,
					Timeout => $timeout,
					Debug => $debug,
				      } );

    my $glue = new ZeeVee::DPGlueMCU( { UART => $uart,
					Timeout => $timeout,
					Debug => $debug,
				      } );
    $glueMCUs{$device_name} = $glue;
}


my $logfile = IO::File->new();
$logfile->open("./resolutionchange.log", '>>')
    or die "Can't open logfile for writing: $! ";

# Prepare for CSV output and print header.
my $csv = new Text::CSV({ 'binary' => 1,
			      'eol' => "\r\n" })
    or die "Failed to create Text::CSV object because ".Text::CSV->error_diag()." ";
my @resolutions = ( 'genlock',
		    'fastswitch size 4096 2160 fps 60',
		    'fastswitch size 4096 2160 fps 50',
		    'fastswitch size 4096 2160 fps 30',
		    'fastswitch size 4096 2160 fps 25',
		    'fastswitch size 4096 2160 fps 24',
		    'fastswitch size 3840 2160 fps 60',
		    'fastswitch size 3840 2160 fps 50',
		    'fastswitch size 3840 2160 fps 30',
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
my @column_names = ( 'Epoch',
		     'Date',
		     'Cycle',
		     'Up Time',
		     'Device Name',
		     'DeviceID',
		     'isConnected',
		     'Current Resolution',
		     'Last Resolution',
		     'HDMI Link Clock',
		     'Sink Detected',
		     'AUX Available',
		     'DPTXPM State 00',
		     'DPTXPM State 10',
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

# Start the stream
$devices{"DPEncoder"}->start("HDMI");
# Little low-level, but gets the correct input selected. (add-in card.)
$devices{"DPEncoder"}->set_property("nodes[HDMI_DECODER:0].inputs[main:0].configuration.source.value", "1");

# Start autoflushing STDOUT
$| = 1;

# Set up resolution lists; track next resolutions; Set up decoder to first resolution.
my %next_resolution_index = ();
foreach my $resolution (@resolutions) {
    $next_resolution_index{$resolution} = 0;
}
my $current_resolution = $resolutions[0];
my $last_resolution = "Nothing";
print "Changing Resolution.\t$last_resolution\t->\t$current_resolution\n";
$devices{"DPDecoder"}->join($devices{"DPEncoder"}->DeviceID.":HDMI:0",
			    "0",
			    $current_resolution );
sleep 2;

my $current_cycle = 0;
my $global_start_time = time();
my $change_time = undef;
my $last_wake_time = int($global_start_time) + 1;
while(1) {
    my $current_time = time();
    my $up_time = undef;
    $up_time = $current_time - $change_time
	if( defined( $change_time ) );

    if( !defined($up_time) || $up_time > $dwell_time ) {
	print scalar localtime ."\t";
	$change_time = time();
	$current_cycle++;
	$next_resolution_index{$current_resolution}++;
	$next_resolution_index{$current_resolution} %= scalar(@resolutions);
	$last_resolution = $current_resolution;
	$current_resolution = $resolutions[$next_resolution_index{$current_resolution}];
	print "Changing Resolution.\t$last_resolution\t->\t$current_resolution\n";
	$devices{"DPDecoder"}->join($devices{"DPEncoder"}->DeviceID.":HDMI:0",
				    "0",
				    $current_resolution );
	sleep 2;
    }

    # Check and log each device status.
    foreach my $name (sort keys %devices) {
	my $device = $devices{$name};
	my $hdmi_status = $device->hdmi_status();
	# The basic data we're collecting
	my %data = ( 'Epoch' => $current_time,
		     'Date' => scalar localtime($current_time),
		     'Cycle' => $current_cycle,
		     'Up Time' => $up_time,
		     'Device Name' => $name,
		     'DeviceID' => $device->DeviceID(),
		     'isConnected' => ( $device->is_connected() ? "YES" : "NO" ),
		     'Current Resolution' => $current_resolution,
		     'Last Resolution' => $last_resolution,
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

	if( exists( $glueMCUs{$name} ) ) {
	    my %debug_dump = $glueMCUs{$name}->debug_dump();
	    $data{'HDMI Link Clock'} = $debug_dump{"HDMI Link Clock"};
	    $data{'Sink Detected'} = $debug_dump{"Sink"};
	    $data{'AUX Available'} = $debug_dump{"AUX"};
	    $data{'DPTXPM State 00'} = $debug_dump{"DP Policy Maker State 00"};
	    $data{'DPTXPM State 10'} = $debug_dump{"DP Policy Maker State 10"};
    	}

	$csv->print_hr( $logfile,
			\%data );
    }

    $logfile->flush();

    # Wait for next polling mark.
    $last_wake_time += $poll_time;
    $current_time = time();
    if($last_wake_time > $current_time) {
	sleep $last_wake_time - $current_time;
    } else {
	$last_wake_time += $poll_time;
	warn "Fell behind on ${poll_time}s polls at $current_time.  Buying extra time.";
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
