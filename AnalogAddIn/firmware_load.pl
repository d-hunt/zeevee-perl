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
my $host = '172.16.1.90';
my $port = 6970;
my $timeout = 10;
my $debug = 0;
my $max_file_size = 100 * 1024;
my @output = ();
my $json_template = '/\{.*\}\n/';

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

# Set to 115200 bps.
####### FIXME: Skipping for now because it's a pain
#######   to keep in sync across invokations.
# $bridge->change_baud_rate(115200);

# Configure GPIO in/out/OD/weak
$bridge->registerset([0x02, 0x03], [0xd5, 0x97]);

# Configure I2C speed to 400kbps (Actually 369kbps)
$bridge->registerset([0x07, 0x08], [0x05, 0x05]);
# Configure I2C speed to 100kbps (Actually 97kbps)
# $bridge->registerset([0x07, 0x08], [0x13, 0x13]);

##################
## SPI Programming
##################

# Open and read file.
my $filename = $ARGV[0] // "fw.bin";
my $data_string = "";
open( FILE, "<:raw", $filename )
    or die "Can't open file $filename.";
read( FILE, $data_string, $max_file_size )
    or die "Error reading from file $filename.";
close FILE;
print "Read file $filename.  Length: ".length($data_string)." Bytes.\n";
my $data_length = length($data_string);

# Take away the write mask for SPI output pins.
$cya_gpio->WriteMask([9, 10, 11, 14]);

# Reset board for SPI access.
print "Starting to read from the SPI ROM.\n";
sleep 1.5;

print "Resetting board.  LED on.\n";
$gpio = $bridge->gpio([1,1,1,0,0,1,1,1]);
print "GPIO state ".Data::Dumper->Dump([$gpio], ["gpio"]);
print "\n";

sleep 0.5;

my $i2c_starttime = 0 - Time::HiRes::time();

# Verify we're talking to the correct SPI flash. (Dies if not recognized)
my $read_data = $flash->read_identification_string();
print "Found SPI Device: $read_data.\n";


# Verify a few places in the file;
print "Reading some data to see if this part is already programmed.\n";
my %verify_regions = ( 0 => 8, # Offest => Length pairs.
		       310 => 8, # Negative offsets from end of file.
		       93000 => 8,
		       -8 => 8 );
my $verify_pass = 0;
foreach my $offset (keys %verify_regions) {
    my $length = $verify_regions{$offset};
    $offset += $data_length
	if($offset < 0);
    my $expect_data = substr($data_string, $offset, $length);
    $read_data = $flash->read_data($offset, $length);

    if($read_data eq $expect_data) {
	$verify_pass = 1;
    } else {
	$verify_pass = 0;
	last;
    }
}

$i2c_starttime += Time::HiRes::time();
print "It took $i2c_starttime seconds to verify SPI Flash.\n";

if($verify_pass) {
    warn "Superficially, this part appears programmed with provided image.  Aborting programming.";
    exit 0; # This is not an error.
}

print "Programming is neeeded.\n";
$i2c_starttime = 0 - Time::HiRes::time();

print "Erasing...\n";
$flash->bulk_erase();

print "Programming...\n";
my $address = 0;
$flash->page_program({ 'Address' => $address,
		       'Data' => $data_string,
		     });
$flash->write_disable();

$i2c_starttime += Time::HiRes::time();
print "It took $i2c_starttime seconds to erase/program SPI Flash.\n";

$i2c_starttime = 0 - Time::HiRes::time();

# Verify What we wrote;
print "Reading some data to verify programming.\n";
$verify_pass = 0;
foreach my $offset (keys %verify_regions) {
    my $length = $verify_regions{$offset};
    $offset += $data_length
	if($offset < 0);
    my $expect_data = substr($data_string, $offset, $length);
    $read_data = $flash->read_data($offset, $length);

    if($read_data eq $expect_data) {
	$verify_pass = 1;
    } else {
	$verify_pass = 0;
	last;
    }
}

$i2c_starttime += Time::HiRes::time();
print "It took $i2c_starttime seconds to verify SPI Flash.\n";

if(!$verify_pass) {
    die "ERROR: ##### Programming failed! #####";
}

sleep 0.5;


print "Releasing reset.\n";
$gpio = $bridge->gpio([1,1,1,0,1,1,1,1]);
print "GPIO state ".Data::Dumper->Dump([$gpio], ["gpio"]);

$apto->close();
exit 0;
