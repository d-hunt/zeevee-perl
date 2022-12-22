#Perl module for communicating with Semtech GSPI chips
package ZeeVee::GSPI;
use Class::Accessor "antlers";

use warnings;
use strict;
use Time::HiRes ( qw/sleep/ );
use Data::Dumper ();


has SPI => ( is => "ro" );
has FileName => (is => "ro");
has DataFile => (is => "ro");
has UnitAddress => (is => "ro");
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );

sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};

    unless( exists $arg_ref->{'SPI'}){
        die "GSPI can't work without a SPI connection to the device."
    }
    unless( exists $arg_ref-> {'FileName'}){
        die "GSPI can't work without a configuration file."
    }
    unless( exists $arg_ref->{'UnitAddress'}){
        $arg_ref->{'UnitAddress'} = 0x00;
    }
    unless( exists $arg_ref->{'Debug'}){
        $arg_ref->{'Debug'} = 0;
    }
    unless( exists $arg_ref->{'Timeout'}){
        $arg_ref->{'Timeout'} = 10;
    }
    

    my $self = $class->SUPER::new( $arg_ref );

    return $self;
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

    $self->write_register(0x201D, 0x000F);
    $self->write_register(0x201E, 0x000F);
    $self->write_register(0x7007, 0x0020);
    $self->write_register(0x7008, 0x0003);
    $self->write_register(0x7006, 0x0001);
    sleep(1);
    $self->write_register(0x201D, 0x0000);
    $self->write_register(0x201E, 0x0000);

    return;
}

sub write_register($$$){
    my $self = shift;
    my $addr = shift;
    my $data = shift;

    my $string = "";
    $string .= chr(0x60);
    $string .= chr($self->UnitAddress);
    $string .= chr($addr>>8);
    $string .= chr($addr & 0xff);
    $string .= chr($data>>8);
    $string .= chr($data & 0xff);
    #print "Hello $i \n";
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

    # This block formats Command Words 1 and 2 and outputs 0x0000 as
    # the last word which allows MISO to write the last two bytes
    my $string = "";
    $string.= chr(0xA0);
    $string.= chr($self->UnitAddress);
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