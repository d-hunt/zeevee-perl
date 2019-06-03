#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib './lib';
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
use ZeeVee::Apto_UART;
use ZeeVee::DPGlueMCU;
use Text::CSV;
use Data::Dumper ();
use Time::HiRes ( qw/sleep time/ );
use IO::File;

# Indent fixed amount per level:
$Data::Dumper::Indent = 1;

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

# Get device list on the network. (just connected ones.)
my %device_ids = %{$apto->device_list_connected()};

my %devices = ();
foreach my $device_name (sort keys %device_ids) {
    $devices{$device_name} =
	new ZeeVee::BlueRiverDevice( { DeviceID => $device_name,
				       Apto => $apto,
				       Timeout => $timeout,
				       VideoTimeout => 20,
				       Debug => $debug,
				     } );
}


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

# Check and dump each device status.
foreach my $name (sort keys %devices) {
    my $device = $devices{$name};
    # my $hdmi_status = $device->hdmi_status();
    # my $monitor_status = $device->monitor_status();
    my @nodes = $device->get_node_by_type(".");

    print Data::Dumper->Dump([\@nodes], ["Device ".$name]);
    print "\n"
}

print "=== DONE. Device listed count = ".scalar(keys %devices)."===\n";

exit 0;
