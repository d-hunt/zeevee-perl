#!/usr/bin/perl

use warnings;
use strict;
use ZeeVee::Aptovision_API;
use ZeeVee::Apto_UART;
use ZeeVee::SC18IM700;
use ZeeVee::PCF8575;
use ZeeVee::SPI_GPIO;
use Data::Dumper ();
use Time::HiRes ( qw/sleep/ );

my $device = 'd880399acbf4';
my $host = '169.254.45.84';
my $port = 6970;
my $debug = 1;
my @output = ();
my $json_template = '/\{.*\}\n/';

my $apto = new ZeeVee::Aptovision_API( { Timeout => 10,
					 Host => $host,
					 Port => $port,
					 JSON_Template => $json_template,
					 Debug => $debug,
				       } );

my $uart = new ZeeVee::Apto_UART( { Device => $device,
				    Apto => $apto,
				    Host => $host,
				    Timeout => 10,
				    Debug => $debug,
				  } );

my $bridge = new ZeeVee::SC18IM700( { UART => $uart,
				      Timeout => 10,
				      Debug => $debug,
				    } );

my $sii_gpio = new ZeeVee::PCF8575( { I2C => $bridge,
				      Address => 0x4c,
				      Timeout => 10,
				      Debug => $debug,
				    } );

my $cya_gpio = new ZeeVee::PCF8575( { I2C => $bridge,
				      Address => 0x4a,
				      Timeout => 10,
				      Debug => $debug,
				    } );

my $spi_serializer = new ZeeVee::SPI_GPIO( { GPIO => $cya_gpio,
					     Timeout => 10,
					     Debug => $debug,
					     Bits => { 'Select' => 12,
							   'Clock' => 13,
							   'MISO' => 14,
							   'MOSI' => 15,
					     }
					   } );


# Analog add-in specific.  Set VGA_DDC_SW to output and drive high (to enable EDID access).  Leave LED (P3) OD-Low; all other ports input-only:

# Temporary values...
my $register_ref;
my $register;

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
my $gpio = $bridge->gpio([1,1,1,0,1,1,1,1]);
print "GPIO state ".Data::Dumper->Dump([$gpio], ["gpio"]);

# Write Analog board GPIO expander @ I2C address 0x4C.
# 0xffff Selects "VGA" input:
# 0xfeff Selects "Component Video" input:
# 0xfdff Selects "Composite Video" input:
# 0xfbff Selects "S-Video" input:
$bridge->i2c_raw( { 'Slave' => 0x4c,
			'Commands' => [{ 'Command' => 'Write',
					     'Data' => [ 0xfb,
							 0xff ]
				       },
			],
		  } );

# Make I2C transactions to EDID SEEPROM.
print "I2C write a little.\n";
my $rx_ref;
$rx_ref =
    $bridge->i2c_raw( { 'Slave' => 0xA0,
			    'Commands' => [
				{ 'Command' => 'Write',
				      'Data' => [ 0x30,
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
				      'Data' => [ 0x30,
				      ]
				},
				{ 'Command' => 'Read',
				      'Length' => 8,
				},
			    ],
		      } );

foreach my $byte (@{$rx_ref}) {
    printf( "0x%x, ", $byte );
}
print "\n";


$rx_ref =
    $bridge->i2c_raw( { 'Slave' => 0xA0,
			    'Commands' => [{ 'Command' => 'Write',
						 'Data' => [ 0x00,
						 ]
					   },
					   { 'Command' => 'Read',
						 'Length' => 8},
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


# Reset board for SPI access.
print "Starting to write the SPI ROM.\n";
sleep 1.5;

print "Resetting board.\n";
$gpio = $bridge->gpio([1,1,1,0,0,1,1,1]);
print "GPIO state ".Data::Dumper->Dump([$gpio], ["gpio"]);
print "\n";

sleep 0.5;

# MOSI, MISO, CLK, CS_L top 4 bits.
my @write_enable_stream = ();
push @write_enable_stream, @{$spi_serializer->start_stream()};
push @write_enable_stream, @{$spi_serializer->make_stream(chr(0x06))};
push @write_enable_stream, @{$spi_serializer->end_stream()};

my @bulk_erase_stream = ();
push @bulk_erase_stream, @{$spi_serializer->start_stream()};
push @bulk_erase_stream, @{$spi_serializer->make_stream(chr(0xc7))};
push @bulk_erase_stream, @{$spi_serializer->end_stream()};

my @page_program_stream = ();
my $data_string = "For me to poop on!     "x2;
push @page_program_stream, @{$spi_serializer->start_stream()};
push @page_program_stream, @{$spi_serializer->make_stream(chr(0x02).chr(0x00).chr(0x00).chr(0x00))};
push @page_program_stream, @{$spi_serializer->make_stream($data_string)};
push @page_program_stream, @{$spi_serializer->end_stream()};

$cya_gpio->stream_write(\@write_enable_stream);
$cya_gpio->stream_write(\@bulk_erase_stream);
sleep 6;
$cya_gpio->stream_write(\@write_enable_stream);
$cya_gpio->stream_write(\@page_program_stream);

sleep 0.5;

print "Releasing reset.\n";
$gpio = $bridge->gpio([1,1,1,0,1,1,1,1]);
print "GPIO state ".Data::Dumper->Dump([$gpio], ["gpio"]);

exit;


# Reset board for SPI access.
print "Starting to read the SPI ROM.\n";
sleep 5;

print "Resetting board.\n";
$gpio = $bridge->gpio([1,1,1,0,0,1,1,1]);
print "GPIO state ".Data::Dumper->Dump([$gpio], ["gpio"]);

sleep 0.5;

# MOSI, MISO, CLK, CS_L top 4 bits.
@stream_data = ();
push @stream_data, @{$spi_serializer->start_stream()};
push @stream_data, @{$spi_serializer->make_stream(chr(0x03).chr(0x00)x16)};
push @stream_data, @{$spi_serializer->end_stream()};

$cya_gpio->stream_write(\@stream_data);

sleep 0.5;

print "Releasing reset.\n";
$gpio = $bridge->gpio([1,1,1,0,1,1,1,1]);
print "GPIO state ".Data::Dumper->Dump([$gpio], ["gpio"]);

exit;



while (0) {
    $bridge->i2c_raw( { 'Slave' => 0x4a,
			    'Commands' => [{ 'Command' => 'Write',
						 'Data' => [ 0xff,
							     0xf9,
							     0xff,
							     0xff,
							     0xff,
							     0xf9,
							     0xff,
							     0xff,
							     0xff,
							     0xf9,
							     0xff,
							     0xff,]
					   },
					   { 'Command' => 'Stop',
					   },
					   { 'Command' => 'Write',
						 'Data' => [ 0xff,
							     0xf9,
							     0xff,
							     0xff,
							     0xff,
							     0xf9,
							     0xff,
							     0xff,
							     0xff,
							     0xf9,
							     0xff,
							     0xff,]
					   },
					   { 'Command' => 'Stop',
					   },
					   { 'Command' => 'Write',
						 'Data' => [ 0xff,
							     0xf9,
							     0xff,
							     0xff,
							     0xff,
							     0xf9,
							     0xff,
							     0xff,
							     0xff,
							     0xf9,
							     0xff,
							     0xff,]
					   },
					   { 'Command' => 'Stop',
					   },
					   { 'Command' => 'Write',
						 'Data' => [ 0xff,
							     0xf9,
							     0xff,
							     0xff,
							     0xff,
							     0xf9,
							     0xff,
							     0xff,
							     0xff,
							     0xf9,
							     0xff,
							     0xff,]
					   },
					   { 'Command' => 'Stop',
					   },
					   { 'Command' => 'Write',
						 'Data' => [ 0xff,
							     0xf9,
							     0xff,
							     0xff,
							     0xff,
							     0xf9,
							     0xff,
							     0xff,
							     0xff,
							     0xf9,
							     0xff,
							     0xff,]
					   },
					   { 'Command' => 'Stop',
					   },
					   { 'Command' => 'Write',
						 'Data' => [ 0xff,
							     0xf9,
							     0xff,
							     0xff,
							     0xff,
							     0xf9,
							     0xff,
							     0xff,
							     0xff,
							     0xf9,
							     0xff,
							     0xff,]
					   },
					   { 'Command' => 'Stop',
					   },
					   { 'Command' => 'Write',
						 'Data' => [ 0xff,
							     0xf9,
							     0xff,
							     0xff,
							     0xff,
							     0xf9,
							     0xff,
							     0xff,
							     0xff,
							     0xf9,
							     0xff,
							     0xff,]
					   },
			    ],
		      } );
    print ".";
    $count--;
}
$i2c_starttime -= Time::HiRes::time();
print "\nDone I2C.  $i2c_starttime seconds.\n";

sleep 2;
$cya_gpio->write([1,1,1,1,1,1,1,1,
		  1,0,0,1,1,1,1,1]);
$cya_gpio->write([1,1,1,1,1,1,1,1,
		  1,1,1,1,1,1,1,1]);
$cya_gpio->write([1,1,1,1,1,1,1,1,
		  1,0,0,1,1,1,1,1]);
$cya_gpio->write([1,1,1,1,1,1,1,1,
		  1,1,1,1,1,1,1,1]);

while( my $new_events = $apto->poll() ) {
    print "Got $new_events new events.  All: ".
	#	join " ", sort keys $apto->Events
	""
	."\n";
    sleep 1;
}

print "== Done with RS232 tx...\n\n";
print "== How is the object doing?...\n\n";
print Data::Dumper->Dump([ $apto ]);
print "\n\n";

# Send first UART command with response.
$uart->transmit( "IP" );

print "== Done with RS232 tx...\n\n";
print "== How is the object doing?...\n\n";
print Data::Dumper->Dump([ $apto ]);
print "\n\n";

# Get UART responses.
for my $try (1, 2, 3, 4, 5, 6) {
    my $rxstring = $uart->receive();
    print "UART rx try $try: ".Data::Dumper->Dump([$rxstring], ['rxstring']);
    sleep 1;
}

print "== Done with RS232 rx...\n\n";
print "== How is the object doing?...\n\n";
print Data::Dumper->Dump([ $apto ]);
print "\n\n";


while( my $new_events = $apto->poll() ) {
    print "Got $new_events new events.  All: ".
	#	join " ", sort keys $apto->Events
	""
	."\n";
    sleep 0.5;
}

foreach my $request (sort keys %{$apto->Requests}) {
    print "Fetching request $request.\n";
    $apto->send( "request $request" );
}

print "== Done with requests...\n\n";
print "== How is the object doing?...\n\n";
print Data::Dumper->Dump([ $apto ]);
print "\n\n";


$apto->close();
exit 0;

# push @output, $apto->send( "get all hello" );
# push @output, $apto->send( "event" );
# push @output, $apto->send( "event" );

print "== Done with hello...\n\n";
print Data::Dumper->Dump(\@output);
print "\n\n";

print "== How is the object doing?...\n\n";
print Data::Dumper->Dump([ $apto ]);
print "\n\n";

@output = ();

# Get GPIO
push @output, $apto->send( "send $device RS232:1 IP" );
#request

# Dump internal registers
push @output, $apto->send( "send $device RS232:1 R\\x00\\x01\\x02\\x03\\x04\\x05\\x06\\x07\\x08\\x09\\x0aP" );
# request 

# Analog add-in specific.  Set VGA_DDC_SW to output and drive high (to enable EDID access).  Leave LED (P3) OD-Low; all other ports input-only:
push @output, $apto->send( "send $device RS232:1 W\\x02\\xd5\\x03\\x95P" );
push @output, $apto->send( "send $device RS232:1 O\\xf7P" );

# Important! Before any I2C access, enable I2C bus timeout; set to ~227ms (default):
push @output, $apto->send( "send $device RS232:1 W\\x09\\x67P" );

# Read Analog board GPIO expander @ I2C address 0x4c:
push @output, $apto->send( "send $device RS232:1 S\\x4d\\x02P" );
# request 

print "== Done with bunch of commands; no responses yet...\n\n";
print Data::Dumper->Dump(\@output);
print "\n\n";

print "== How is the object doing?...\n\n";
print Data::Dumper->Dump([ $apto ]);
print "\n\n";


$apto->close();

__END__


push @output, $apto->send( "" );
push @output, $apto->send( "" );

push @output, $apto->send( "" );
push @output, $apto->send( "" );

push @output, $apto->send( "" );
push @output, $apto->send( "" );


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
