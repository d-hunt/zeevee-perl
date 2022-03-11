#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib '../lib';
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
use ZeeVee::Apto_UART;
use ZeeVee::SC18IM700;
use ZeeVee::PCF8575;
use ZeeVee::SPI_GPIO;
use ZeeVee::SPIFlash;
use ZeeVee::WebPowerSwitch;
use ZeeVee::NetgearM4300;
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

my %device_ids = ( '1 Capital-RX-SBBi3 '  => 'd880395909e9',
                   '2 Capital-TX-ZXS-E1'  => 'd88039eb5b3b',
                   '3 DUT-ZXS-E1'         => '6cdffb000252',
                   # 'x DUT-ZXS-D2'         => '6cdffb000258', # Bricked.
                   'x DUT-ZXS-E3'         => '6cdffb000256', # Not in video path, but alive.
                   '4 DUT-ZXS-D4'         => '6cdffb00025a',
                   '5 DUT-ZXS-E5'         => '6cdffb000254',
                   '6 DUT-ZXS-D6'         => '6cdffb00025c',
                   '7 Capital-RX-ZXS-D6'  => 'd880395a8dca',
                   '8 Capital-TX-Monitor' => 'd88039ead026', );

my @power_types = ( 'AC', 'PoE' );
my %power_ports = ( 'AC'  => [1, 2, 3, 4, 5, 6],
                    'PoE' => [1, 2, 3, 4, 5, 6], );
my @power_transitions = ( {'AC'  => 'ON' }, # Note: ON-to-ON transition not implemented
                          {'AC'  => 'OFF' },
                          {'PoE' => 'ON' },
                          {'PoE' => 'OFF' },
                          {'AC'  => 'ON',  'PoE' => 'ON' },
                          {'AC'  => 'OFF', 'PoE' => 'OFF' }, );

my $host = '10.10.10.1';
my $port = 6970;
my $timeout = 10;
my $debug = 0;
my @output = ();
my $json_template = '/\{.*\}\n/';

my %power_switch;
$power_switch{'AC'} = new ZeeVee::WebPowerSwitch( { Host => '10.10.10.3',
                                                    Port => 80,
                                                    User => 'admin',
                                                    Password => 'zazzle',
                                                    Timeout => 10,
                                                    Debug => 0,
                                                  } );

$power_switch{'PoE'} = new ZeeVee::NetgearM4300( { Host => '169.254.100.100',
                                                   Port => 23,
                                                   User => 'admin',
                                                   Password => '',
                                                   Slot => '1/0',
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
$logfile->open("./powercycle.csv", '>>')
    or die "Can't open logfile for writing: $! ";

# Prepare for CSV output and print header.
my $csv = new Text::CSV({ 'binary' => 1,
                          'eol' => "\r\n" })
    or die "Failed to create Text::CSV object because".Text::CSV->error_diag()." ";
my @column_names = ( 'Epoch',
                     'Date',
                     'Power Cycle',
                     'Power State',
                     'PoE State',
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

# Helper subroutine to convert JSON booleans to yes/no.
sub JSON_bool_to_YN($) {
    my $value = shift;
    if( defined($value)
        && JSON::is_bool($value) ) {
        $value = ( $value ? 'YES' : 'NO' );
    }
    return $value;
}

# Power off in preperation.
my %power_state;
foreach my $power_type ( @power_types ) {
    print scalar localtime ."\t";
    print "Turning off $power_type Power.\n";
    foreach my $power_port ( $power_ports{$power_type} ) {
        $power_switch{$power_type}->powerOff($power_port);
    }
    $power_state{$power_type} = 'OFF';
}
sleep 2;
# Start autoflushing STDOUT
$| = 1;

my $current_cycle = 0;
my $global_start_time = time();
my $power_on_time = undef;
my $power_transition_index = 0;
my $last_wake_time = int($global_start_time) + 1;
while(1) {
    my $current_time = time();
    my $up_time = undef;
    $up_time = $current_time - $power_on_time
        if( defined( $power_on_time ) );

    my $modulo_cycle_time = ($current_time - $global_start_time) % $power_cycle_interval;
    if( ("ON" ~~ [values %power_state])
        && $modulo_cycle_time > $power_cycle_on_time ) {
        my %transitions = %{$power_transitions[$power_transition_index]};
        die "On-to-on transition not implemented"
            if( "ON" ~~ [values %transitions] );
        foreach my $power_type ( keys %transitions ) {
            print scalar localtime ."\t";
            print "Turning off $power_type Power.\n";
            foreach my $power_port ( $power_ports{$power_type} ) {
                $power_switch{$power_type}->powerOff($power_port);
            }
            $power_state{$power_type} = 'OFF';
        }
        $power_on_time = undef;
    } elsif( !("ON" ~~ [values %power_state])
             && $modulo_cycle_time < $power_cycle_on_time ) {
        my %transitions = %{$power_transitions[$power_transition_index]};
        die "Off-to-off transition not implemented"
            if( "OFF" ~~ [values %transitions] );
        foreach my $power_type ( keys %transitions ) {
            print scalar localtime ."\t";
            print "Turning on $power_type Power.\n";
            foreach my $power_port ( $power_ports{$power_type} ) {
                $power_switch{$power_type}->powerOn($power_port);
            }
            $power_state{$power_type} = 'ON';
        }
        $power_on_time = time();
        $current_cycle++;
    }
    $power_transition_index++;
    $power_transition_index %= scalar @power_transitions;

    # Check and log each device status.
    foreach my $name (sort keys %devices) {
        my $device = $devices{$name};
        my $hdmi_status = $device->hdmi_status();
        # The basic data we're collecting
        my %data = ( 'Epoch' => $current_time,
                     'Date' => scalar localtime($current_time),
                     'Power Cycle' => $current_cycle,
                     'Power State' => $power_state{'AC'},
                     'PoE State' => $power_state{'PoE'},
                     'Up Time' => $up_time,
                     'Device Name' => $name,
                     'DeviceID' => $device->DeviceID(),
                     'isConnected' => ( $device->is_connected() ? "YES" : "NO" ),
                     'Temperature' => $device->__temperature(),
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

    # Wait for next 5s mark.
    $last_wake_time += 7.5;
    $current_time = time();
    if($last_wake_time > $current_time) {
        sleep $last_wake_time - $current_time;
    } else {
        $last_wake_time += 7.5;
        warn "Fell behind on 5s polls at $current_time.  Buying extra time.";
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
