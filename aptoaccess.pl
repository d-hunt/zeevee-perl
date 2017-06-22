#!/usr/bin/perl

use warnings;
use strict;
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
my $max_file_size = 100 * 1024;
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
				    } );

my $cya_gpio = new ZeeVee::PCF8575( { I2C => $bridge,
				      Address => 0x4a,
				      Timeout => $timeout,
				      Debug => $debug,
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


# Analog add-in specific.  Set VGA_DDC_SW to output and drive high (to enable EDID access).  Leave LED (P3) OD-Low; all other ports input-only:

# Temporary values...
my $register_ref;
my $register;
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
$bridge->registerset([0x02, 0x03], [0xd5, 0x97]);

# Configure I2C speed to 400kbps (Actually 369kbps)
$bridge->registerset([0x07, 0x08], [0x05, 0x05]);
# Configure I2C speed to 100kbps (Actually 97kbps)
# $bridge->registerset([0x07, 0x08], [0x13, 0x13]);

# Set and get GPIO
$gpio = $bridge->gpio([1,1,1,0,1,1,1,1]);
print "GPIO state ".Data::Dumper->Dump([$gpio], ["gpio"]);

# Write Analog board GPIO expander @ I2C address 0x4C.
# 0xffff Selects "VGA" input:
# 0xfeff Selects "Component Video" input:
# 0xfdff Selects "Composite Video" input:
# 0xfbff Selects "S-Video" input:
$sii_gpio->write([0,1,1,1,1,1,1,1,
		  1,1,1,1,1,1,1,1]);
#$bridge->i2c_raw( { 'Slave' => 0x4c,
#			'Commands' => [{ 'Command' => 'Write',
#					     'Data' => [ 0xfb,
#							 0xff ]
#				       },
#			],
#		  } );

# Make I2C transactions to EDID SEEPROM.
print "I2C write a little.\n";
my $rx_ref;
$rx_ref =
    $bridge->i2c_raw( { 'Slave' => 0xA0,
			    'Commands' => [
				{ 'Command' => 'Write',
				      'Data' => [ 0x10,
						  0x40,
						  0x41,
						  0x42,
						  0x43,
						  0x44,
						  0x45,
						  0x46,
						  0x47,
				      ]
				},
			    ],
		      } );


print "I2C write/read back same.\n";
$rx_ref =
    $bridge->i2c_raw( { 'Slave' => 0xA0,
			    'Commands' => [
				{ 'Command' => 'Write',
				      'Data' => [ 0x10,
				      ]
				},
				{ 'Command' => 'Read',
				      'Length' => 16,
				},
			    ],
		      } );

foreach my $byte (@{$rx_ref}) {
    printf( "0x%x, ", $byte );
}
print "\n";


print "I2C read beginning of EDID.\n";
$rx_ref =
    $bridge->i2c_raw( { 'Slave' => 0xA0,
			    'Commands' => [{ 'Command' => 'Write',
						 'Data' => [ 0x00,
						 ]
					   },
					   { 'Command' => 'Read',
						 'Length' => 16},
			    ],
		      } );

foreach my $byte (@{$rx_ref}) {
    printf( "0x%x, ", $byte );
}
print "\n";

# Toggle GPIO pins the slow way.
print "Toggling unused GPIO pins the slow way...\n";
my $count=4;
my $i2c_starttime = 0 - Time::HiRes::time();
while ($count > 0) {
    $cya_gpio->write([1,1,1,1,1,1,1,1,
		      1,0,0,1,1,1,1,1]);
    $cya_gpio->write([1,1,1,1,1,1,1,1,
		      1,1,1,1,1,1,1,1]);
    $count--;
    print ".";
}
$i2c_starttime += Time::HiRes::time();
print "\nDone I2C one-at-a-time.  $i2c_starttime seconds.\n";

sleep 5;

# Toggle I2C GPIO as fast as possible.
print "Toggling unused GPIO pins as fast as possible...\n";
my @stream_data = ();
$count=11;
$i2c_starttime = 0 - Time::HiRes::time();
while ($count > 0) {
    push @stream_data, 0xf9ff;
    push @stream_data, 0xffff;
    $count--;
}
$cya_gpio->stream_write(\@stream_data);
$i2c_starttime += Time::HiRes::time();
print "\nDone I2C stream.  $i2c_starttime seconds.\n";


# exit 0;

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

# Reset board for SPI access.
print "Starting to write the SPI ROM.\n";
sleep 1.5;

print "Resetting board.\n";
$gpio = $bridge->gpio([1,1,1,0,0,1,1,1]);
print "GPIO state ".Data::Dumper->Dump([$gpio], ["gpio"]);
print "\n";

sleep 0.5;

# MOSI, MISO, CLK, CS_L top 4 bits.
$i2c_starttime = 0 - Time::HiRes::time();
#my $data_string = "That's a very nice SPI transaction...  For me to poop on! 0123456789abcdef0123456789abcdef" x 10;
$flash->bulk_erase();
my $address = 0;
$flash->page_program({ 'Address' => $address,
			   'Data' => $data_string,
		     });
$flash->write_disable();
$i2c_starttime += Time::HiRes::time();
print "It took $i2c_starttime seconds to serialize SPI and interact with Aptovision API.\n";

sleep 0.5;

print "Releasing reset.\n";
$gpio = $bridge->gpio([1,1,1,0,1,1,1,1]);
print "GPIO state ".Data::Dumper->Dump([$gpio], ["gpio"]);

$apto->close();
exit 0;

__END__

# push @output, $apto->send( "get all hello" );


Check I2C status:
send d880399acbf4 RS232:1 R\x0aP
request 
Read Analog board GPIO expander @ I2C address 0x4a:
send d880399acbf4 RS232:1 S\x4b\x02P
request 
Check I2C status:
send d880399acbf4 RS232:1 R\x0aP
request 
Write Analog board GPIO expander @ I2C address 0x4C.  Selects "VGA" input:
send d880399acbf4 RS232:1 S\x4c\x02\xff\xffP
Check I2C status:
send d880399acbf4 RS232:1 R\x0aP
request 
Write Analog board GPIO expander @ I2C address 0x4C.  Selects "Component Video" input:
send d880399acbf4 RS232:1 S\x4c\x02\xfe\xffP
Check I2C status:
send d880399acbf4 RS232:1 R\x0aP
request 
Write Analog board GPIO expander @ I2C address 0x4C.  Selects "Composite Video" input:
send d880399acbf4 RS232:1 S\x4c\x02\xfd\xffP
Check I2C status:
send d880399acbf4 RS232:1 R\x0aP
request 
Write Analog board GPIO expander @ I2C address 0x4C.  Selects "S-Video" input:
send d880399acbf4 RS232:1 S\x4c\x02\xfb\xffP
Check I2C status:
send d880399acbf4 RS232:1 R\x0aP
request 
Write Analog board GPIO expander @ I2C address 0x4a.  Selects “S/PDIF” audio:
send d880399acbf4 RS232:1 S\x4a\x02\xff\xfeP
Check I2C status:
send d880399acbf4 RS232:1 R\x0aP
request 
Write Analog board GPIO expander @ I2C address 0x4a.  Selects “Analog” audio:
send d880399acbf4 RS232:1 S\x4a\x02\xff\xffP
Check I2C status:
send d880399acbf4 RS232:1 R\x0aP
request 
Read from Analog board EDID SEEPROM @ I2C address 0xA0 (sequential without specifying start offset):
send d880399acbf4 RS232:1 S\xA1\x08P
request 
Check I2C status:
send d880399acbf4 RS232:1 R\x0aP
request 
Write some data to Analog board EDID SEEPROM @ I2C address 0xA0 Offset 0x00 - 8-byte page max!
send d880399acbf4 RS232:1 S\xA0\x09\x00\xff\xff\x0b\xad\xca\xca\xde\xedP
Read back from Analog board EDID SEEPROM @ I2C address 0xA0 Offset 0x00 Length 8-bytes:
send d880399acbf4 RS232:1 S\xA0\x01\x00S\xA1\x08P
request 
Check I2C status
send d880399acbf4 RS232:1 R\x0aP
request 
Analog add-in only: Set VGA_DDC_SW drive low (For EDID-VGA connection).  Leave LED (P3) OD-Low; all other ports input-only.
send d880399acbf4 RS232:1 O\x77P
Get GPIO input state (You should see Low VGA_DDC_SW now.)
send d880399acbf4 RS232:1 IP
request 
"""
