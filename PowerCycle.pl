#!/usr/bin/perl

use warnings;
use strict;
no warnings 'experimental::smartmatch';

use lib './lib'; # Some platforms (Ubuntu) don't search current directory by default.
use ZeeVee::WebPowerSwitch;
use Time::HiRes ( qw/sleep time/ );
use IO::File;

my $port = shift // 1;

my $power_switch = new ZeeVee::WebPowerSwitch( { Host => '10.10.10.3',
						 Port => 80,
						 User => 'admin',
						 Password => 'zazzle',
						 Timeout => 10,
						 Debug => 0,
					       } );

# Power Cycle.
print scalar localtime ."\t";
print "Cycling Power:     Port $port.\n";
$power_switch->powerCycle($port);

exit 0;

__END__
