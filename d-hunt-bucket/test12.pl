#!/usr/bin/perl

use warnings;
use strict;

use lib '../lib';
use ZeeVee::GSPI;
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
my @write_mask=[0,1,2,3,4,9,11,12,13,14,15];
# File containing the GS12170 intial configuration
my $filename = 'gs12170_config.txt';


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

my $gspi_gs12170 = new ZeeVee::GSPI( { SPI => $main_spi,
				  FileName => $filename,
                  UnitAddress => 0x00,
				  Debug => $debug,
                  Timeout => $timeout,
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

my $gspi_gs12341 = new ZeeVee::GSPI( { SPI => $eq_spi,
				  FileName => $filename,
                  UnitAddress => 0x00,
				  Debug => $debug,
                  Timeout => $timeout,
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

my $gspi_gs12281 = new ZeeVee::GSPI( { SPI => $cd_spi,
				  FileName => $filename,
                  UnitAddress => 0x00,
				  Debug => $debug,
                  Timeout => $timeout,
				} );
my $gpio;

# Read the initial state of the Bridge GPIO
$gpio = $bridge -> gpio();
print "Initial Bridge GPIO state: ".Data::Dumper->Dump([$gpio], ["gpio"]);
# Read the initial state of the expander GPIO
$gpio = $expander->read();
print "Initial Expander GPIO state: ".Data::Dumper->Dump([$gpio], ["gpio"]);

$uart->transmit("S")


# $gspi_gs12170->initialize_gs12170();

# Read the Detected Rate register
my $rate = ord($gspi_gs12341->read_register(0x0087)) & 0x7;
# switch($rate){
# 	case 0 {print "Unlocked\n"}
# 	case 1 {print "MADI (125 Mbps)\n"}
# 	case 2 {print "SD (270 Mbps)\n"}
# 	case 3 {print "HD (1.485 Gbps)\n"}
# 	case 4 {print "3G\n"}
# 	case 5 {print "6G\n"}
# 	case 6 {print "12G\n"}
# 	case 7 {print "Error\n"}
# }
print "$rate/n";

exit 0;

__END__