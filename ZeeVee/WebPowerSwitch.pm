# Perl module for controlling WebPowerSwitch power switches.
package ZeeVee::WebPowerSwitch;
use Class::Accessor "antlers";

use warnings;
use strict;
use LWP;
use Data::Dumper ();

has Host => ( is => "ro" );
has Port => ( is => "ro" );
has User => ( is => "ro" );
has Password => ( is => "ro" );
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );
has UserAgent => ( is => "rw" );


# Constructor for WebPowerSwitch object.
sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};

    unless( exists $arg_ref->{'Host'} ) {
	$arg_ref->{'Host'} = '169.168.0.100';
    }
    unless( exists $arg_ref->{'Port'} ) {
	$arg_ref->{'Port'} = 80;
    }
    unless( exists $arg_ref->{'User'} ) {
	$arg_ref->{'User'} = 'admin';
    }
    unless( exists $arg_ref->{'Password'} ) {
	$arg_ref->{'Password'} = '1234';
    }
    unless( exists $arg_ref->{'Timeout'} ) {
	$arg_ref->{'Timeout'} = 10;
    }
    unless( exists $arg_ref->{'Debug'} ) {
	$arg_ref->{'Debug'} = 0;
    }
    unless( exists $arg_ref->{'UserAgent'} ) {
	$arg_ref->{'UserAgent'} = new LWP::UserAgent ( 'timeout' => $arg_ref->{'Timeout'} );
    }

    my $self = $class->SUPER::new( $arg_ref );

    $self->initialize();

    return $self;
}


# Initialize this object.
sub initialize($) {
    my $self = shift;

    # Nothing to do.

    return;
}


# Turn power of outlet ON.
# Arguments:
#   outlet number
sub powerOn($$) {
    my $self = shift;
    my $outlet = shift;

    return $self->setPower($outlet, "ON");
}


# Turn power of outlet OFF.
# Arguments:
#   outlet number
sub powerOff($$) {
    my $self = shift;
    my $outlet = shift;

    return $self->setPower($outlet, "OFF");
}


# Cycle power of outlet.
# Arguments:
#   outlet number
sub powerCycle($$) {
    my $self = shift;
    my $outlet = shift;

    return $self->setPower($outlet, "CCL");
}


# Set power state of an outlet. (Or power cycle it.)
# Arguments:
#   outlet number
#   desired state ("ON"|"OFF"|"CCL")
sub setPower($$$) {
    my $self = shift;
    my $outlet = shift;
    my $state = shift;

    my $url = "http://";
    $url .= $self->User();
    $url .= ":";
    $url .= $self->Password();
    $url .= "@";
    $url .= $self->Host();
    $url .= ":";
    $url .= $self->Port();
    $url .= "/outlet?";
    $url .= $outlet;
    $url .= "=";
    $url .= $state;

    my $result = $self->UserAgent->get($url);
    die "Error on sending power $state request to Web Power Switch outlet $outlet."
	unless($result->is_success());


    return;
}

1;
