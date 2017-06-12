package Aptovision_API;
use Class::Accessor "antlers";

use warnings;
use strict;
use Net::Telnet;

has Host => ( is => "ro" );
has Port => ( is => "ro" );
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );
has Telnet => ( is => "rw" );
has Output => ( is => "rw" );
has JSON_Template => ( is => "rw" );


sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};
    
    unless( exists $arg_ref->{'Host'} ) {
	$arg_ref->{'Host'} = '169.254.45.84';
    }
    unless( exists $arg_ref->{'Port'} ) {
	$arg_ref->{'Port'} = 6970;
    }
    unless( exists $arg_ref->{'Timeout'} ) {
	$arg_ref->{'Timeout'} = 10;
    }
    unless( exists $arg_ref->{'Debug'} ) {
	$arg_ref->{'Debug'} = 0;
    }
    unless( exists $arg_ref->{'JSON_Template'} ) {
	$arg_ref->{'JSON_Template'} = '/\{.*\}\n/';
    }
    unless( exists $arg_ref->{'Telnet'} ) {
	$arg_ref->{'Telnet'} = new Net::Telnet (Timeout => $arg_ref->{'Timeout'},
						Host => $arg_ref->{'Host'},
						Port => $arg_ref->{'Port'});
    }

    my $self = $class->SUPER::new( $arg_ref );
    
    $self->Telnet->open()
	|| die "Can't open Telnet to ${self->Host}:${self->Port}.";

    $self->Telnet->dump_log("telnet_debug.log")
	if( $self->Debug >= 1 );

    return $self;
}

sub send($$) {
    my $self = shift;
    my $cmd = shift;
    
    my $previous;
    my $match;

    $self->Telnet->print( "$cmd" )
	|| die "Error sending command: $cmd";
    
    ($previous ,$match) = $self->Telnet->waitfor($self->JSON_Template);

    chomp $previous;
    chomp $match;

    print "%DEBUG: Matched '$match'\n"
	if( $self->Debug >= 2);
    
    die "Unexpected output received: '$previous'"
	if($previous);
    die "Unexpected embedded line feed received: '$match'"
	if($match =~ /\n/);

    return $match;
}

sub close($) {
    my $self = shift;
    $self->Telnet->close();
}

1;
__END__


# CLEAN UP AUTOMATICALLY on destruciton!!!
$telnet->close();
