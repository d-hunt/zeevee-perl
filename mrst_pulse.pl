#!/usr/bin/perl

use warnings;
use strict;

use lib '.'; # Some platforms (Ubuntu) don't search current directory by default.
use ZeeVee::Aptovision_API;
use ZeeVee::Apto_UART;
use ZeeVee::SC18IM700;
use ZeeVee::PCF8575;
use ZeeVee::SPI_GPIO;
use ZeeVee::SPIFlash;
use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );

my $device = 'd880399acbf4';
my $host = '169.254.45.84';
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

my $uart = new ZeeVee::Apto_UART( { Device => $device,
				    Apto => $apto,
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

# Set to 115200 bps.
####### FIXME: Skipping for now because it's a pain
#######   to keep in sync across invokations.
# $bridge->change_baud_rate(115200);

# Get starting point.
$gpio = $bridge->gpio();

# Configure GPIO in/out/OD/weak
$bridge->registerset([0x02, 0x03], [0xd5, 0x97]);

# Pulse reset and LED.
print "\nAsserting Reset; LED off.\n\n";
$gpio->[4] = 0; # MSTR_RST_L
$gpio->[3] = 1; # STATUS_LED_L
$gpio = $bridge->gpio($gpio);

sleep 1;

print "\nDeasserting Reset; LED on.\n\n";
$gpio->[4] = 1; # MSTR_RST_L
$gpio->[3] = 0; # STATUS_LED_L
$gpio = $bridge->gpio($gpio);

print "Ending Bridge GPIO state: ".Data::Dumper->Dump([$gpio], ["gpio"]);

exit 0;
