#!/usr/bin/perl

use warnings;
use strict;

use lib '../lib';
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
use ZeeVee::Apto_UART;
use ZeeVee::SC18IM700;
use ZeeVee::PCF8575;
use ZeeVee::SPI_GPIO;
use ZeeVee::SPIFlash;
use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );

my $id_mode = "SINGLEENCODER"; # Set to: SINGLEENCODER, NEWENCODER, HARDCODED
my $device_id = 'd880399acbf4';
my $host = '172.16.53.29';
my $port = 6970;
my $timeout = 10;
my $debug = 1;
my @output = ();
my $json_template = '/\{.*\}\n/';
my @write_mask=[0,1,2,3,4,5,6,7,8,9,10,12,13,14,15];

my $apto = new ZeeVee::Aptovision_API( { Timeout => $timeout,
					 Host => $host,
					 Port => $port,
					 JSON_Template => $json_template,
					 Debug => $debug,
				       } );

# Determine the encoder to use for this test.
if( $id_mode eq "NEWENCODER" ) {
    print "Waiting for a new encoder device...\n";
    $device_id = $apto->wait_for_new_device("all_tx");
} elsif ( $id_mode eq "SINGLEENCODER" ) {
    print "Looking for a single encoder.\n";
    $device_id = $apto->find_single_device("all_tx");
} elsif ( $id_mode eq "HARDCODED" ) {
    print "Using hard-coded device: $device_id.\n";
} else {
    die "Unimlemented ID mode: $id_mode.";
}
print "Using encoder (DUT) $device_id.\n";

my $encoder = new ZeeVee::BlueRiverDevice( { DeviceID => $device_id,
					     Apto => $apto,
					     Timeout => $timeout,
					     VideoTimeout => 20,
					     Debug => $debug,
					   } );

my $uart = new ZeeVee::Apto_UART( { Device => $encoder,
				    Host => $host,
				    Timeout => $timeout,
				    Debug => $debug,
				  } );

my $bridge = new ZeeVee::SC18IM700( { UART => $uart,
				      Timeout => $timeout,
				      Debug => $debug,
				    } );


my $expander = new ZeeVee::PCF8575( { I2C => $bridge,
				      Address => 0x40,
				      Timeout => $timeout,
				      Debug => $debug,
				      WriteMask => @write_mask,
				    } );

my $main_spi = new ZeeVee::SPI_GPIO( { GPIO => $expander,
				  Timeout => $timeout,
				  Debug => $debug,
				  ChunkSize => 512,
				  Bits => { 'Select' => 7,
						'Clock' => 8,
						'MISO' =>  9,
						'MOSI' => 10,
				  },
				  Base => 0xffff
				} );

my $eq_spi = new ZeeVee::SPI_GPIO( { GPIO => $expander,
				  Timeout => $timeout,
				  Debug => $debug,
				  ChunkSize => 512,
				  Bits => { 'Select' => 6,
						'Clock' => 8,
						'MISO' =>  9,
						'MOSI' => 10,
				  },
				  Base => 0xffff
				} );

my $cd_spi = new ZeeVee::SPI_GPIO( { GPIO => $expander,
				  Timeout => $timeout,
				  Debug => $debug,
				  ChunkSize => 512,
				  Bits => { 'Select' => 5,
						'Clock' => 8,
						'MISO' =>  9,
						'MOSI' => 10,
				  },
				  Base => 0xffff
				} );               

# Temporary values...
my $register_ref;
my $register;
my $gpio;
my @tester;

# Print out current write mask
@tester = $expander->{WriteMask};
foreach my $number (@tester){
    print("\n@$number\n\n");
}

# Update writemask to allow for GS12170 initialization
@write_mask = [0, 1, 2, 3, 4, 5, 6, 9, 12, 13, 14, 15];

# FIX ME: I don't want to have to re-construct the object
$expander->WriteMask(@write_mask);
                    
# Print out new writemask                    
# @tester = $expander->{WriteMask};
# foreach my $number (@tester){
#     print("\n@$number\n\n");
# }
print("$expander->{WriteMask}\n");

# First get current states.
$gpio = $bridge->gpio();
print "Initial Bridge GPIO state: ".Data::Dumper->Dump([$gpio], ["gpio"]);
$gpio = $expander->read();
print "Initial SiI GPIO state: ".Data::Dumper->Dump([$gpio], ["gpio"]);


# Set to 115200 bps.
####### FIXME: Skipping for now because it's a pain
#######   to keep in sync across invokations.
# $bridge->change_baud_rate(115200);

# Attempt to read back BRG.
$register_ref = $bridge->registerset([0x00, 0x01]);
print "Register state set: "
    .Data::Dumper->Dump([$register_ref], ["register_ref"]);

# Show off single register reading capability.
$register = $bridge->register(0x00);
print "Register state single: "
    .Data::Dumper->Dump([$register], ["register"]);

$register = $bridge->register(0x01);
print "Register state single: "
    .Data::Dumper->Dump([$register], ["register"]);

# Configure GPIO in/out/OD/weak
# Bit 3 and Bit 7 are push-pull outputs (0x10), the rest are inputs (0x00)
$bridge->registerset([0x02, 0x03], [0x80, 0x83]);

# Configure I2C speed to 400kbps (Actually 369kbps)
$bridge->registerset([0x07, 0x08], [0x05, 0x05]);
# Configure I2C speed to 100kbps (Actually 97kbps)
# $bridge->registerset([0x07, 0x08], [0x13, 0x13]);

# Set and get GPIO
$gpio = $bridge->gpio([1,1,1,0,1,1,1,1]);
print "Bridge GPIO state ".Data::Dumper->Dump([$gpio], ["gpio"]);

print "Resetting board.  LED off.\n";
$gpio = $bridge->gpio([1,1,1,1,0,1,1,1]);
print "Bridge GPIO state ".Data::Dumper->Dump([$gpio], ["gpio"]);
print "\n";

sleep 0.25;

print "Releasing reset.  LED on.\n";
$gpio = $bridge->gpio([1,1,1,0,1,1,1,1]);
print "Bridge GPIO state ".Data::Dumper->Dump([$gpio], ["gpio"]);
print "\n";

# Update writemask to allow for GS12170 initialization
$expander->WriteMask([0, 1, 2, 3, 4, 5, 6, 9, 12, 13, 14, 15]);

print("$expander->WriteMask");

exit 0;

__END__