#!/usr/bin/perl

use warnings;
use strict;

use lib '../lib';
use ZeeVee::Aptovision_API;
use ZeeVee::BlueRiverDevice;
use ZeeVee::Apto_UART;
use ZeeVee::SC18IM704;
use ZeeVee::PCAL6416A;
use ZeeVee::SPI_GPIO;
use ZeeVee::GSPI;
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

my $bridge = new ZeeVee::SC18IM704( { UART => $uart,
				      Timeout => $timeout,
				      Debug => $debug,
				    } );


my $expander = new ZeeVee::PCAL6416A( { I2C => $bridge,
				      Address => 0x40,
				      Timeout => $timeout,
				      Debug => $debug,
				      Outputs => [5,6,7,8,10]
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
my $gspi_gs12170 = new ZeeVee::GSPI( { SPI => $main_spi,
				  FileName => $filename,
                  UnitAddress => 0x00,
				  Debug => $debug,
                  Timeout => $timeout,
				  Type => 0
				} );
my $gspi_gs12341 = new ZeeVee::GSPI( { SPI => $eq_spi,
				  UnitAddress => 0x00,
				  Debug => $debug,
				  Timeout => $timeout, 
				  Type => 1				   
				} );
my $gspi_gs12281 = new ZeeVee::GSPI( { SPI => $cd_spi,
				  UnitAddress => 0x00,
				  Debug => $debug,
				  Timeout => $timeout, 
				  Type => 1				   
				} );
               

# Configure SC18IM704 inputs and outputs
$bridge -> register(0x02, 0xC0); # PortConf1
$bridge -> register(0x03, 0x03); # PortConf2

# Read GPIO on SC18IM704
my $data = $bridge -> gpio();
print "Initial Bridge GPIO state: ".Data::Dumper->Dump([$data], ["data"]);

# Read GPIO on PCAL6416A
$data = $expander->read();
print "Initial Expander GPIO state: ".Data::Dumper->Dump([$data], ["data"]);

# $gspi_gs12170->initialize_gs12170();

exit 0;

__END__