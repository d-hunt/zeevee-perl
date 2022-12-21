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

        $i=$i+1;
    }
    
    $i=0;

    foreach (@gspi_addr){
        my $string = "";
        $string .= chr(0x60);
        $string .= chr($self->UnitAddress);
        $string .= chr($gspi_addr[$i]>>8);
        $string .= chr($gspi_addr[$i] & 0xff);
        $string .= chr($gspi_data[$i]>>8);
        $string .= chr($gspi_data[$i] & 0xff);
        print "Hello $i \n";
        $self->SPI->start_stream();
        $self->SPI->append_stream($string);
        $self->SPI->end_stream();
        $self->SPI->send();
        $i=$i+1;
    }

    return;
}

sub read_register($$) {
    my $self = shift;
    my $register = shift;

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
    my $readback = $self->SPI->get_sampled_stream();

    return $readback;
}

1;