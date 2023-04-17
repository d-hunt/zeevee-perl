#Perl module for communicating with Semtech GSPI chips
package ZeeVee::GSPI;
use Class::Accessor "antlers";

use warnings;
use strict;
use Time::HiRes ( qw/sleep/ );
use Data::Dumper ();


has SPI => ( is => "ro" );
has FileName => (is => "ro");
has UnitAddress => (is => "ro");
has Type => (is => "ro"); #GS12341 and GS12281 are Type 1, rest 0
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );

sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};

    unless( exists $arg_ref->{'SPI'}){
        die "GSPI can't work without a SPI connection to the device."
    }
    unless( exists $arg_ref-> {'FileName'}){
        $arg_ref->{'FileName'} = "";
    }
    unless( exists $arg_ref->{'UnitAddress'}){
        $arg_ref->{'UnitAddress'} = 0x00;
    }
    unless( exists $arg_ref->{'Type'}){
        $arg_ref->{'Type'} = 0;
    }
    unless( exists $arg_ref->{'Debug'}){
        $arg_ref->{'Debug'} = 0;
    }
    unless( exists $arg_ref->{'Timeout'}){
        $arg_ref->{'Timeout'} = 10;
    }

    my $self = $class->SUPER::new( $arg_ref );

    $self->initialize();
    return $self;
}

sub initialize($){
    my $self = shift;
    if ($self->Type){
        $self -> write_register(0x0000, 0x2000);
    }
    # Disable bus-through operation
    $self -> write_register(0x0000, 0x2000);
}
sub set_addresses_gs12341($){
    my $self = shift;

    # Disable link-through operation
    $self->write_register_wo_unitaddr(0x0000, 0x4000);
    # Set the next four unit addresses  
    $self->write_register_wo_unitaddr(0x0000, 0x0001);
    $self->write_register_wo_unitaddr(0x0000, 0x0002);
    $self->write_register_wo_unitaddr(0x0000, 0x0003);
    $self->write_register_wo_unitaddr(0x0000, 0x0004);

    return;
}

sub initialize_gs12170($){
    my $self = shift;

    open(FH, '<', $self->FileName) or die $!;

    my $i;
    $i=0;
    my @gspi_addr=[];
    my @gspi_data=[];

    # Split file lines to address and data and convert the string to hex
    while(<FH>){
        my @gspi_words = split ' ', $_;
        $gspi_addr[$i] = hex($gspi_words[0]);
        $gspi_data[$i] = hex($gspi_words[1]);
        #print "$gspi_addr[$i]\n";
        $i=$i+1;
    }

    close(FH);
    
    $i=0;

    foreach (@gspi_addr){
        $self->write_register($gspi_addr[$i], $gspi_data[$i]);
        $i=$i+1;
    }

    # SCDC Stuff
    $self->write_register(0x201D, 0x000F);
    $self->write_register(0x201E, 0x000F);
    $self->write_register(0x7007, 0x0020);
    $self->write_register(0x7008, 0x0003);
    $self->write_register(0x7006, 0x0001);
    sleep(1);
    $self->write_register(0x201D, 0x0000);
    $self->write_register(0x201E, 0x0000);
    $self->write_register(0x1000, 0x00AF);
    $self->write_register(0x1065, 0x0001);
    sleep(1);
    $self->write_register(0x1065, 0x0000);

    return;
}

sub write_register($$$){
    my $self = shift;
    my $addr = shift;
    my $data = shift;

    my $command_word_one = 0x2000 + ($self->UnitAddress << 7);

    my $string = "";
    $string .= chr($command_word_one>>8);
    $string .= chr($command_word_one & 0xff);
    $string .= chr($addr>>8);
    $string .= chr($addr & 0xff);
    $string .= chr($data>>8);
    $string .= chr($data & 0xff);
    $self->SPI->start_stream();
    $self->SPI->append_stream($string);
    $self->SPI->end_stream();
    $self->SPI->send();

    return;
}

sub write_register_wo_unitaddr($$$){
    my $self = shift;
    my $addr = shift;
    my $data = shift;

    my $command_word_one = 0x2000;

    my $string = "";
    $string .= chr($command_word_one>>8);
    $string .= chr($command_word_one & 0xff);
    $string .= chr($addr>>8);
    $string .= chr($addr & 0xff);
    $string .= chr($data>>8);
    $string .= chr($data & 0xff);
    $self->SPI->start_stream();
    $self->SPI->append_stream($string);
    $self->SPI->end_stream();
    $self->SPI->send();

    return;
}

sub read_register($$) {
    # This function returns the 48-bit MISO stream.  The data
    # received is in the last two bytes
    my $self = shift;
    my $register = shift;

    my $command_word_one = 0xA000 + ($self->UnitAddress << 7);
    # This block formats Command Words 1 and 2 and outputs 0x0000 as
    # the last word which allows MISO to write the last two bytes
    my $string = "";
    $string.= chr($command_word_one >> 8);
    $string.= chr($command_word_one & 0xff);
    $string.= chr($register>>8);
    $string.= chr($register & 0xff);
    $string.= chr(0x00);
    $string.= chr(0x00);
    $self->SPI->start_stream();
    $self->SPI->append_stream($string);
    $self->SPI->end_stream();
    $self->SPI->send_receive();

    $string = "";
    my $stream_length  = scalar(@{$self->SPI->Stream()});
    my $samplingstream_length = scalar(@{$self->SPI->SamplingStream()});

    die "SamplingStream size does not match Stream."
	unless($samplingstream_length == $stream_length);

    #All my data is in the stream.  Now I have to extract it.
    my $bit = 16;
    my $byte = 0x0000;
    for( my $offset=67; $offset < $stream_length; $offset++ ) {
	    # Skip unwanted samples.
	    next if( $self->SPI->SamplingStream()->[$offset] == 0 );

	    # This is a sample we want.
	    $bit--;
	    my $sample = $self->SPI->Stream()->[$offset];
	    $byte = $self->SPI->__set_bit( $byte, $bit )
	    if( $self->SPI->__get_bit( $sample, $self->SPI->Bits->{'MISO'} ) );

        if( $bit == 0 ) {
            $string .= chr( $byte );
            $byte = 0x00;
            $bit = 16;
        }
    }

    die "Incomplete word in sampled stream."
	unless( $bit == 16 );

    return $string;
}

1;