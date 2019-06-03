#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib '../lib';
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
use ZeeVee::Apto_UART;
use Text::CSV;
use Data::Dumper ();
use Time::HiRes ( qw/sleep time/ );
use IO::File;


my $on_time = 30; # seconds.
my $off_time = 30; # seconds.
my $poll_wait_time = 15; # seconds.

my %device_ids = ( 'Decoder' => 'd880399b0e2e' );
#my %device_ids = ( 'Decoder' => 'd880399b3837' );
my $host = '172.16.53.240';
#my $host = '172.16.1.90';
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

my %TVs = ();
foreach my $device_name (sort keys %device_ids) {
    next unless( $device_name eq "Decoder" );
    # FIXME: Apto_UART can't currently use the UART connector.  It'll need modification.
    my $tv = new ZeeVee::Apto_UART( { Device => $devices{$device_name},
				      Host => $host,
				      Timeout => $timeout,
				      Debug => $debug,
				    } );

    $TVs{$device_name} = $tv;
}

my $logfile = IO::File->new();
$logfile->open("./TVPowerCycle.log", '>>')
    or die "Can't open logfile for writing: $! ";

# Prepare for CSV output and print header.
my $csv = new Text::CSV({ 'binary' => 1,
			      'eol' => "\r\n" })
    or die "Failed to create Text::CSV object because ".Text::CSV->error_diag()." ";
my %command = ( 'ON' => "ka 00 01\r",
		'OFF' => "ka 00 00\r" );
my @column_names = ( 'Epoch',
		     'Date',
		     'Cycle',
		     'Up Time',
		     'Device Name',
		     'DeviceID',
		     'isConnected',
		     'Temperature',
		     'Monitor State',
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

# Helper subroutine to convert JSON booleans to yes/no.
sub JSON_bool_to_YN($) {
    my $value = shift;
    if( defined($value)
	&& JSON::is_bool($value) ) {
	$value = ( $value ? 'YES' : 'NO' );
    }
    return $value;
}

# Start autoflushing STDOUT
$| = 1;

my $current_cycle = 0;
my $current_state = 'ON';
my $global_start_time = time();
my $change_time = undef;
my $last_wake_time = int($global_start_time) + 1;
while(1) {
    $current_cycle++;

    if($current_state eq 'ON') {
	$current_state = 'OFF';
    } elsif($current_state eq 'OFF') {
	$current_state = 'ON';
    } else {
	die "Bad programmer!";
    }

    foreach my $device_name (sort keys %TVs) {
	my $tv = $TVs{$device_name};
	$tv->transmit($command{$current_state});
    }
    print scalar localtime ."\t";
    print "Powered $current_state\n";
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
		     'Monitor State' => $current_state,
		     'Monitor Connected' => JSON_bool_to_YN( $monitor_status->{'connected'} ),
		     'Monitor EDID' => $monitor_status->{'edid'},
		     'Source Stable' => JSON_bool_to_YN( $hdmi_status->{'source_stable'} ),
		     'Video Width' => $hdmi_status->{'video'}->{'width'},
		     'Video Height' => $hdmi_status->{'video'}->{'height'},
		     'Video FPS' => $hdmi_status->{'video'}->{'frames_per_second'},
		     'Video Scan Mode' => $hdmi_status->{'video'}->{'scan_mode'},
		     'Video Color Space' => $hdmi_status->{'video'}->{'color_space'},
		     'Video BPP' => $hdmi_status->{'video'}->{'bits_per_pixel'},
		     'HDCP Protected' => JSON_bool_to_YN( $hdmi_status->{'hdcp_protected'} ),
		     'HDCP Version' => $hdmi_status->{'hdcp_version'},
	    );

	# Iterate through video_details and add those to data we keep too.
	foreach my $key (keys %{$hdmi_status->{'video_details'}}) {
	    my $value = $hdmi_status->{'video_details'}->{"$key"};
	    if(JSON::is_bool($value)) {
		$value = JSON_bool_to_YN( $value );
	    }
	    $data{"VD $key"} = $value;
	}

	$csv->print_hr( $logfile,
			\%data );
    }

    $logfile->flush();

    # Wait for next polling mark.
    if($current_state eq 'ON') {
	$last_wake_time += $on_time;
    } elsif($current_state eq 'OFF') {
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
