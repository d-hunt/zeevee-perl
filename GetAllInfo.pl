#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib './lib';
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
use Data::Dumper ();
use Time::HiRes ( qw/sleep time/ );
use IO::File;
use Scalar::Util ( qw/reftype/ );

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
    print ".";
    if( defined($value)
	&& JSON::is_bool($value) ) {
	$value = ( $value ? 'YES' : 'NO' );
	print "$value";
    }
    return $value;
}

sub JSON_bool_to_YN_Scalar($) {
    my $ref = shift;
    print "s";
    ${$ref} = JSON_bool_to_YN(${$ref});
    return $ref;
}

sub JSON_bool_to_YN_Hash($) {
    my $hashref = shift;
    print "h";
    foreach my $value (values %{$hashref}) {
	$value = JSON_bool_to_YN_Deep($value)
    }
    return $hashref;
}

sub JSON_bool_to_YN_Array($) {
    my $arrayref = shift;
    print "a";
    foreach my $value (values @{$arrayref}) {
	$value = JSON_bool_to_YN_Deep($value)
    }
    return $arrayref;
}

sub JSON_bool_to_YN_Deep($) {
    my $value = shift;
    my $type = reftype($value);

    if(! defined($value) ) {
	; # Leave it undefined.
    } elsif(! defined($type) ) { # Scalar
	$value = JSON_bool_to_YN($value);
    } elsif( $type eq "SCALAR" ) {
	$value = JSON_bool_to_YN(${$value});
    } elsif( $type eq "HASH" ) {
	$value = JSON_bool_to_YN_Hash($value);
    } elsif( $type eq "ARRAY" ) {
	$value = JSON_bool_to_YN_Array($value);
    } else {
	warn "New type $type.";
	$value = $value;
    }
    return $value;
}

# Start autoflushing STDOUT
$| = 1;

# Check and dump each device status.
foreach my $name (sort keys %devices) {
    my $device = $devices{$name};
    $device->poll();
    my %info = %{$device->AptoDevice()};
    JSON_bool_to_YN_Deep(\%info);

    print Data::Dumper->Dump([\%info], ["Device ".$name]);
    print "\n"
}

print "=== DONE. Device listed count = ".scalar(keys %devices)."===\n";

exit 0;
