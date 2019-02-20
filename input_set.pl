#!/usr/bin/perl

use warnings;
use strict;

use lib '.'; # Some platforms (Ubuntu) don't search current directory by default.
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
my $host = '172.16.1.90';
my $port = 6970;
my $timeout = 10;
my $debug = 1;
my @output = ();
my $json_template = '/\{.*\}\n/';

my $desired_input = $ARGV[0] // '';

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

my $sii_gpio = new ZeeVee::PCF8575( { I2C => $bridge,
				      Address => 0x4c,
				      Timeout => $timeout,
				      Debug => $debug,
				      WriteMask => [4, 5, 6, 7, 8],
				    } );

my $cya_gpio = new ZeeVee::PCF8575( { I2C => $bridge,
				      Address => 0x4a,
				      Timeout => $timeout,
				      Debug => $debug,
				      WriteMask => [9, 10, 11, 12, 13, 14, 15],
				    } );

my $spi = new ZeeVee::SPI_GPIO( { GPIO => $cya_gpio,
				  Timeout => $timeout,
				  Debug => $debug,
				  ChunkSize => 512,
				  Bits => { 'Select' => 12,
						'Clock' => 13,
						'MISO' => 14,
						'MOSI' => 15,
				  },
				  Base => 0xffff
				} );

my $flash = new ZeeVee::SPIFlash( { SPI => $spi,
				    Timeout => $timeout,
				    Debug => $debug,
				    PageSize => 256,
				    AddressWidth => 24,
				    Timing => { 'BulkErase' => 6.0,
						    'SectorErase' => 3.0,
						    'PageProgram' => 0.005,
						    'WriteStatusRegister' => 0.015,
				    },
				  } );


# Temporary values...
my $gpio;


# First get current states.
$gpio = $bridge->gpio();
print "Initial Bridge GPIO state: ".Data::Dumper->Dump([$gpio], ["gpio"]);
$gpio = $sii_gpio->read();
print "Initial SiI GPIO state: ".Data::Dumper->Dump([$gpio], ["gpio"]);
$gpio = $cya_gpio->read();
print "Initial CYA GPIO state: ".Data::Dumper->Dump([$gpio], ["gpio"]);


# Set to 115200 bps.
####### FIXME: Skipping for now because it's a pain
#######   to keep in sync across invokations.
# $bridge->change_baud_rate(115200);

# Get starting point.
$gpio = $sii_gpio->read();

# 0xffff Selects "VGA" input:
# 0xfffe Selects "Component Video" input:
# 0xfffd Selects "Composite Video" input:
# 0xfffb Selects "S-Video" input:
if( $desired_input eq "Composite" ) {
    print "\nSetting Composite Input.\n\n";
    $gpio->[3] = 1;
    $gpio->[2] = 1;
    $gpio->[1] = 0;
    $gpio->[0] = 1;
} elsif ( $desired_input eq "S-Video" ) {
    print "\nSetting S-Video Input.\n\n";
    $gpio->[3] = 1;
    $gpio->[2] = 0;
    $gpio->[1] = 1;
    $gpio->[0] = 1;
} elsif ( $desired_input eq "Component" ) {
    print "\nSetting Component Input.\n\n";
    $gpio->[3] = 1;
    $gpio->[2] = 1;
    $gpio->[1] = 1;
    $gpio->[0] = 0;
} elsif ( $desired_input eq "VGA" ) {
    print "\nSetting VGA Input.\n\n";
    $gpio->[3] = 1;
    $gpio->[2] = 1;
    $gpio->[1] = 1;
    $gpio->[0] = 1;
} else {
    die "Unknown input '$desired_input'.";
}

$gpio = $sii_gpio->write($gpio);
print "Ending SiI GPIO state: ".Data::Dumper->Dump([$gpio], ["gpio"]);

exit 0;
