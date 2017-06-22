# Perl module for writing a SPI Flash.
package ZeeVee::SPIFlash;
use Class::Accessor "antlers";

use warnings;
use strict;
use Time::HiRes ( qw/sleep/ );
use Data::Dumper ();

has SPI => ( is => "ro" );
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );
has PageSize => ( is => "ro" );
has AddressWidth => ( is => "ro" );
has Timing => ( is => "ro" );

# Constructor for SPIFlash object.
sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};
    
    unless( exists $arg_ref->{'SPI'} ) {
	die "SPIFlash can't work without a SPI connection to device.";
    }
    unless( exists $arg_ref->{'Timeout'} ) {
	$arg_ref->{'Timeout'} = 10;
    }
    unless( exists $arg_ref->{'Debug'} ) {
	$arg_ref->{'Debug'} = 0;
    }
    unless( exists $arg_ref->{'PageSize'} ) {
	$arg_ref->{'PageSize'} = 256;
    }
    unless( exists $arg_ref->{'AddressWidth'} ) {
	$arg_ref->{'PageSize'} = 24;
    }
    unless( exists $arg_ref->{'Timing'} ) {
	$arg_ref->{'Timing'} = { 'BulkErase' => 6.0,
				     'SectorErase' => 3.0,
				     'PageProgram' => 0.005,
				     'WriteStatusRegister' => 0.015,
	};
    }
    
    my $self = $class->SUPER::new( $arg_ref );

    $self->initialize();
    
    return $self;
}


# Any initialization necessary.
sub initialize($) {
    my $self = shift;

    # Nothing yet.
    
    return;
}


# Write Enable the Flash.
sub write_enable($) {
    my $self = shift;

    $self->SPI->start_stream();
    $self->SPI->command_stream({'Command' => 0x06 });
    $self->SPI->end_stream();

    $self->SPI->send();

    sleep($self->Timing->{'WriteStatusRegister'});
    return;
}


# Write Disable the Flash.
sub write_disable($) {
    my $self = shift;

    $self->SPI->start_stream();
    $self->SPI->command_stream({'Command' => 0x04 });
    $self->SPI->end_stream();

    $self->SPI->send();

    sleep($self->Timing->{'WriteStatusRegister'});
    return;
}


# Bulk Erase whole Flash.
sub bulk_erase($) {
    my $self = shift;
    
    $self->write_enable();
    
    $self->SPI->start_stream();
    $self->SPI->command_stream({'Command' => 0xc7 });
    $self->SPI->end_stream();

    $self->SPI->send();

    sleep($self->Timing->{'BulkErase'});

    return;
}


# Page Program (Write)
sub page_program($\%) {
    my $self = shift;
    my $description = shift;
    
    my $data = $description->{'Data'};
    my $address = $description->{'Address'};

    die "I don't know how to start in the middle of a page."
	unless( ($address % $self->PageSize()) == 0 );

    # Split to pages.
    my $offset = 0;
    while( $offset < length($data) ) {
	my $page_data = substr($data, $offset, $self->PageSize());
	
	$self->write_enable();

	$self->SPI->start_stream();
	$self->SPI->command_stream({ 'Command' => 0x02,
					 'AddressWidth' => $self->AddressWidth(),
					 'Address' => $address + $offset,
				   });
	$self->SPI->append_stream($page_data);
	$self->SPI->end_stream();
	    
	$self->SPI->send();
	
	sleep($self->Timing->{'PageProgram'});
	
	$offset += $self->PageSize();
    }
	
    return;
}

1;
