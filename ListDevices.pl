#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib './lib';
use ZeeVee::Aptovision_API;
use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );
use IO::Select;

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

# Get list of devices
my %devices = %{$apto->device_list()};

print "\n";
print "=== Up:   ===\n";
foreach my $id (sort keys %devices) {
    print "$id\n"
        if( $devices{$id}->{"__status__"} eq "UP" );
}

print "\n";
print "=== Down: ===\n";
foreach my $id (sort keys %devices) {
    print "$id\n"
        if( $devices{$id}->{"__status__"} eq "DOWN" );
}

print "\n";
print "=== DONE. ===\n";

exit 0;
