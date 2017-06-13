#!/usr/bin/perl

use warnings;
use strict;
use Aptovision_API;
use Data::Dumper ();

my $device = 'd880399acbf4';
my $host = '169.254.45.84';
my $port = 6970;
my $debug = 1;
my @output = ();
my $json_template = '/\{.*\}\n/';

my $apto = new Aptovision_API( { Timeout => 10,
				 Host => $host,
				 Port => $port,
				 JSON_Template => $json_template,
				 Debug => $debug,
			       } );

# More init for RS-232 access to add-in card.
$apto->send( "switch $device:RS232:1 $host" );
pop @{$apto->Results}; # Discard.
$apto->send( "set $device property nodes[UART:1].configuration.baud_rate 9600" );
pop @{$apto->Results}; # Discard.

sleep 1;

while( keys %{$apto->Requests} ) {
    foreach my $request (sort keys %{$apto->Requests}) {
	print "Fetching request $request.\n";
	$apto->send( "request $request" );
	pop @{$apto->Results}; # Discard.
    }
}

# Send first UART command
$apto->send( "send $device RS232:1 IP" );

sleep 1;

while( keys %{$apto->Requests} ) {
    foreach my $request (sort keys %{$apto->Requests}) {
	print "Fetching request $request.\n";
	$apto->send( "request $request" );
	pop @{$apto->Results}; # Discard.
    }
}

while( my $new_events = $apto->poll() ) {
    print "Got $new_events new events.  All: ".
	#	join " ", sort keys $apto->Events
	""
	."\n";
    sleep 1;
}

print "== Done with requests...\n\n";
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
