#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib '../lib';
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
use ZeeVee::JSON_Bool;
use Text::CSV;
use Data::Dumper ();
use Time::HiRes ( qw/sleep time/ );
use IO::File;


my $on_time = 15; # seconds.
my $off_time = 15; # seconds.
my $poll_wait_time = 8; # seconds.

my %device_ids = ( 'Decoder_1' => 'd880395953aa',
		   'Decoder_2' => 'd88039eacce2',
		   'Decoder_3' => 'd88039eb23d7',
		   'Encoder_P1' => 'd880395993ee',
		   'Encoder_P2' => 'd8803959aabf',
		   'Encoder_P3' => 'd88039eb01f9' );
#my $host = '172.16.1.90';
my $host = '172.16.52.232';
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

my $url_root = 'https://admin:admin@172.16.52.231';

my %command = ( 'SessionInit'
		=> 'curl -c cookie.txt -d "" -X POST --insecure '.$url_root.'/xmlapi/session/begin',
		'Standby'
		=> 'curl -c cookie.txt -d "<Command><Standby><Activate/></Standby></Command>" -X POST --insecure '.$url_root.'/putxml',
		'Awake'
		=> 'curl -c cookie.txt -d "<Command><Standby><Deactivate/></Standby></Command>" -X POST --insecure '.$url_root.'/putxml',
		'PresentationStart'
		=> 'curl -c cookie.txt -d "<Command><Presentation><Start/></Presentation></Command>" -X POST --insecure '.$url_root.'/putxml' );

system($command{'SessionInit'}) == 0
    or die "Error getting session cookie.";

my $logfile = IO::File->new();
$logfile->open("./CiscoStandby.log", '>>')
    or die "Can't open logfile for writing: $! ";

# Prepare for CSV output and print header.
my $csv = new Text::CSV({ 'binary' => 1,
			  'eol' => "\r\n" })
    or die "Failed to create Text::CSV object because ".Text::CSV->error_diag()." ";
my @column_names = ( 'Epoch',
		     'Date',
		     'Cycle',
		     'Up Time',
		     'Device Name',
		     'DeviceID',
		     'isConnected',
		     'Temperature',
		     'CoDec State',
		     'Monitor Connected',
		     'Monitor EDID',
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

# Start autoflushing STDOUT
$| = 1;

my $current_cycle = 0;
my $current_state = 'Awake';
my $hold_state = 0;
my $global_start_time = time();
my $change_time = undef;
my $last_wake_time = int($global_start_time) + 1;
while(1) {
    $current_cycle++;

    if($hold_state) {
	$current_state = $current_state;
	$hold_state = 0;
    } elsif($current_state eq 'Awake') {
	$current_state = 'Standby';
    } elsif($current_state eq 'Standby') {
	$current_state = 'Awake';
    } else {
	die "Bad programmer!";
    }

    system($command{$current_state}) == 0
	or die "Error sending command to set state $current_state";


    if($current_state eq 'Awake') {
	system($command{'PresentationStart'}) == 0
	    or die "Error sending command to set state $current_state";
    }

    print scalar localtime ."\t";
    print "Setting State: $current_state\n";
    $change_time = time();
    sleep $poll_wait_time;
    
    my $current_time = time();
    my $up_time = $current_time - $change_time;
	    
    # Check and log each device status.
    foreach my $name (sort keys %devices) {
	my $device = $devices{$name};
	my $hdmi_status = $device->hdmi_status();
	my $monitor_status = $device->monitor_status();
	# The basic data we're collecting
	my %data = ( 'Epoch' => $current_time,
		     'Date' => scalar localtime($current_time),
		     'Cycle' => $current_cycle,
		     'Up Time' => $up_time,
		     'Device Name' => $name,
		     'DeviceID' => $device->DeviceID(),
		     'isConnected' => ( $device->is_connected() ? "YES" : "NO" ),
		     'Temperature' => $device->__temperature(),
		     'CoDec State' => $current_state,
		     'Monitor Connected' => ZeeVee::JSON_Bool::to_YN( $monitor_status->{'connected'} ),
		     'Monitor EDID' => $monitor_status->{'edid'},
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

	# If any device has no input; hold our current state.
	if( ($current_state eq 'Awake')
	    && !($hdmi_status->{'source_stable'}) ) {
	    $hold_state = 1;
	}
    }

    $logfile->flush();

    # Wait for next polling mark.
    if($current_state eq 'Awake') {
	$last_wake_time += $on_time;
    } elsif($current_state eq 'Standby') {
	$last_wake_time += $off_time;
    } else {
	die "Bad programmer!";
    }

    $current_time = time();
    if($last_wake_time > $current_time) {
	sleep $last_wake_time - $current_time;
    } else {
	$last_wake_time += $on_time;
	$last_wake_time += $off_time;
	warn "Fell behind on polls at $current_time.  Buying extra time.";
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
