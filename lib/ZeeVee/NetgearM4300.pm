# Perl module for controlling Netgear M4300; Implementing PoE port power.
package ZeeVee::NetgearM4300;
use Class::Accessor "antlers";

use warnings;
use strict;
use Net::Telnet ();
use Data::Dumper ();

has Host => ( is => "ro" );
has Port => ( is => "ro" );
has User => ( is => "ro" );
has Password => ( is => "ro" );
has Slot => ( is => "ro" );
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );
has Telnet => ( is => "rw" );


# Constructor for WebPowerSwitch object.
sub new($\%) {
    my $class = shift;
    my $arg_ref = shift // {};

    unless( exists $arg_ref->{'Host'} ) {
	$arg_ref->{'Host'} = '169.254.100.100';
    }
    unless( exists $arg_ref->{'Port'} ) {
	$arg_ref->{'Port'} = 23;
    }
    unless( exists $arg_ref->{'User'} ) {
	$arg_ref->{'User'} = 'admin';
    }
    unless( exists $arg_ref->{'Password'} ) {
	$arg_ref->{'Password'} = '';
    }
    unless( exists $arg_ref->{'Slot'} ) {
	$arg_ref->{'Slot'} = '1/0';
    }
    unless( exists $arg_ref->{'Timeout'} ) {
	$arg_ref->{'Timeout'} = 10;
    }
    unless( exists $arg_ref->{'Debug'} ) {
	$arg_ref->{'Debug'} = 0;
    }
    unless( exists $arg_ref->{'Telnet'} ) {
	$arg_ref->{'Telnet'} = new Net::Telnet (Timeout => $arg_ref->{'Timeout'},
						Host => $arg_ref->{'Host'},
						Port => $arg_ref->{'Port'});
    }

    my $self = $class->SUPER::new( $arg_ref );

    $self->Telnet->open()
	|| die "Can't open Telnet to ${self->Host}:${self->Port}.";

    $self->Telnet->dump_log("telnet_m4300_debug.log")
	if( $self->Debug >= 1 );

    $self->initialize();

    return $self;
}

# Initialize this object.
sub initialize($) {
    my $self = shift;

    $self->login();
    $self->send("enable");
    $self->send("configure");

    return;
}


# Turn PoE power of port ON.
# Arguments:
#   port number
sub powerOn($$) {
    my $self = shift;
    my $port = shift;
    my $cmd = "poe";

    $self->interface_mode($port);

    return $self->send("$cmd");
}


# Turn PoE power of port OFF.
# Arguments:
#   port number
sub powerOff($$) {
    my $self = shift;
    my $port = shift;
    my $cmd = "no poe";

    $self->interface_mode($port);

    return $self->send("$cmd");
}


# Cycle PoE power of port.
# Arguments:
#   port number
sub powerCycle($$) {
    my $self = shift;
    my $port = shift;
    my @retlines_off;
    my @retlines_on;

    @retlines_off = $self->powerOff($port);
    sleep 1;
    @retlines_on = $self->powerOn($port);

    return (@retlines_off, @retlines_on);
}


# Dump ports power state and other info
# Arguments:
#   port number (optional; all if omitted.)
sub info($$) {
    my $self = shift;
    my $port = shift // 'all';
    my $cmd = "show poe port info";
    $cmd .= " ";
    if( $port ne 'all' ) {
	$cmd .= $self->Slot;
	$cmd .= "/";
    }
    $cmd .= "$port";

    return $self->send("$cmd");
}


# Sends an empty command.
sub keepalive($) {
    my $self = shift;

    return $self->send("");
}


# Change to interface config mode.
# Arguments:
#   port number
sub interface_mode($$) {
    my $self = shift;
    my $port = shift;
    my $cmd = "interface ";
    $cmd .= $self->Slot;
    $cmd .= "/";
    $cmd .= $port;

    return $self->send("$cmd");
}

# Sends a command and returns its output.
sub send($$) {
    my $self = shift;
    my $cmd = shift;
    my @retlines;

    print "%DEBUG: Sending command '$cmd'\n"
	if( $self->Debug >= 3 );

    @retlines = $self->Telnet->cmd( "$cmd" );

    print "%DEBUG: Got/ignored prompt '".$self->Telnet->last_prompt."'\n"
	if( $self->Debug >= 2 );

    return @retlines;
}


# Login to Telnet connection on M4300.
sub login($) {
    my $self = shift;
    my $prompt_re = '/\(.*\) >$/';
    my $prompt_host = '';

    $self->Telnet->errmode("return");
    $self->Telnet->waitfor('/User:$/')
	|| die "Can't log in to M4300 Telnet - no user prompt.";
    $self->Telnet->print($self->User())
	|| die "Can't log in to M4300 Telnet - sending user name.";
    $self->Telnet->waitfor('/Password:$/')
	|| die "Can't log in to M4300 Telnet - no password prompt.";
    $self->Telnet->print($self->Password())
	|| die "Can't log in to M4300 Telnet - sending password.";

    $self->Telnet->errmode("die");
    (undef, $prompt_re) = $self->Telnet->waitfor($prompt_re);

    ($prompt_host) = ($prompt_re =~ /\((.*)\) >$/);

    die "Prompt hostname $prompt_host is a dangerous one for our regexp."
	if ($prompt_host !~ /^[-_ \w]+$/);
    
    # Construct a better prompt based on hostname
    $prompt_re = '/\('.$prompt_host.'\) ';
    $prompt_re .= '(\(.*\))?';
    $prompt_re .= '[#>]';
    $prompt_re .= '$/';
    print "%DEBUG: Setting prompt to '$prompt_re'\n"
	if( $self->Debug >= 1 );
    
    $self->Telnet->prompt($prompt_re);

    return;
}


# Close Telnet connection to M4300.
sub close($) {
    my $self = shift;
    $self->Telnet->close();
    return;
}

1;
__END__


# CLEAN UP AUTOMATICALLY on destruction??
$telnet->close();

