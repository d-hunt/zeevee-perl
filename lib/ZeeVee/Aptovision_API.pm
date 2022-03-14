# Perl module for speaking to Aptovision API
package ZeeVee::Aptovision_API;
use Class::Accessor "antlers";

use warnings;
use strict;
use Net::Telnet ();
use JSON ();
use Data::Dumper ();

has Host => ( is => "ro" );
has Port => ( is => "ro" );
has Timeout => ( is => "ro" );
has Debug => ( is => "ro" );
has Telnet => ( is => "rw" );
has JSON => ( is => "rw" );
has Requests => ( is => "rw" );
has Events => ( is => "rw" );
has Last_Event => ( is => "rw" );
has Results => ( is => "rw" );
has JSON_Template => ( is => "rw" );


# Constructor for Aptovision_API object.
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
    unless( exists $arg_ref->{'JSON'} ) {
	$arg_ref->{'JSON'} = new JSON ();
	$arg_ref->{'JSON'}->utf8();
    }

    $arg_ref->{'Requests'} = {};
    $arg_ref->{'Events'} = {};
    $arg_ref->{'Results'} = [];
    $arg_ref->{'Last_Event'} = -1;

    my $self = $class->SUPER::new( $arg_ref );

    $self->Telnet->open()
	|| die "Can't open Telnet to ${self->Host}:${self->Port}.";

    $self->Telnet->dump_log("telnet_debug.log")
	if( $self->Debug >= 1 );

    $self->initialize();

    return $self;
}


# Initialize connection for sanity.
sub initialize($) {
    my $self = shift;

    $self->send( "require blueriver_api 3.0.0.0" );
    pop @{$self->Results}; # Discard.
    $self->send( "mode async off" );
    pop @{$self->Results}; # Discard.

    return;
}


# Sends a command and consumes its output.
sub send($$) {
    my $self = shift;
    my $cmd = shift;

    my $previous;
    my $match;
    my $JSRef;

    $self->Telnet->print( "$cmd" )
	|| die "Error sending command: $cmd";

    return $self->expect($cmd);
}

# Expects response to a command and consumes it into appropriate structure.
sub expect($$) {
    my $self = shift;
    my $cmd = shift;

    my $previous;
    my $match;
    my $JSRef;

    ($previous ,$match) = $self->Telnet->waitfor($self->JSON_Template);

    chomp $previous;
    chomp $match;

    print "%DEBUG: Matched '$match'\n"
	if( $self->Debug >= 2);

    die "Unexpected output received: '$previous'"
	if($previous);
    die "Unexpected embedded line feed received: '$match'"
	if($match =~ /\n/);

    $JSRef = $self->JSON->decode($match);

    my $unexpected = "";
    if( ($JSRef->{'status'} eq "SUCCESS") ) {
	if( defined($JSRef->{'error'}) ) {
	    $unexpected .= "SUCCESS status with 'error' defined.\n";
	}
	if( defined($JSRef->{'request_id'}) ) {
	    if( exists($self->{'Requests'}->{"$JSRef->{'request_id'}"}) ) {	
		# This must be a response to an earlier request; take off the
		# pending requests hash and record the result.
		delete $self->{'Requests'}->{"$JSRef->{'request_id'}"};
 	    } else {
		# If we didn't know about this request, it's unexpected.
		$unexpected .= "SUCCESS status with unrecognized 'request_id'.\n";
	    }
	}
	push @{$self->{'Results'}}, $JSRef->{'result'};
    } elsif($JSRef->{'status'} eq "PROCESSING") {
	if( defined($JSRef->{'error'}) ) {
	    $unexpected .= "PROCESSING status with 'error' defined.\n";
	}
	if( defined($JSRef->{'result'}) ) {
	    $unexpected .= "PROCESSING status with 'result' defined.\n";
	}
	# Add to Requests unless this request already exists.
	$self->{'Requests'}->{"$JSRef->{'request_id'}"} = "$cmd"
	    unless( exists($self->{'Requests'}->{"$JSRef->{'request_id'}"}) )	
    } else {
	$unexpected .= "Unimplemented status '".$JSRef->{'status'}."' received.\n";
    }

    if( $unexpected ) {
	my $dumpstring = Data::Dumper->Dump([$JSRef], ["JSRef"]);
	die "Got an unexpected response on command: $cmd\n"
	    ."Unexpected: $unexpected"
	    ."Result:\n${dumpstring}"
	    ."Buh bye!"
    }

    return $JSRef;
}


# Poll for events and consume
sub poll($) {
    my $self = shift;
    my $JSRef = undef;
    my $new_events = 0;

    if( $self->Last_Event < 0 ) {
	$self->send("event");
    } else {
	$self->send("event $self->{'Last_Event'}");
    }

    $JSRef = pop @{$self->Results};

    die "Unexpected event response."
	unless( exists( $JSRef->{'events'} ) );

    foreach my $event (@{$JSRef->{'events'}}) {
	die "Event_ID wrapped from large integer.  I don't know how to deal with that."
	    if( $event->{'event_id'} < ($self->Last_Event - 4096) );

	$self->Last_Event($event->{'event_id'})
	    if( $event->{'event_id'} > $self->Last_Event );

	unless( exists( $self->{'Events'}->{$event->{'event_id'}} ) ) {
	    # Only if we aren't aware of this event yet.
	    $self->{'Events'}->{$event->{'event_id'}} = $event;
	    $new_events++;
	}
    }

    return $new_events;
}


# Get ready to handle an event; Meaning make its "request_id" valid.
sub prepare($$) {
    my $self = shift;
    my $event_id = shift;

    if( exists $self->Events->{ $event_id } ) {
	my $event = $self->Events->{$event_id};
	if( exists $event->{'request_id'}
	    &&!exists($self->Requests->{"$event->{'request_id'}"}) ) {
	    $self->Requests->{"$event->{'request_id'}"} = "EVENT $event_id"
	} else {
	    die "This event, $event_id, doesn't have a request_id.";
	}
    } else {
	my $dumpstring = Data::Dumper->Dump([$self->Events], ["Events"]);
	die "Unregistered event $event_id.  I have am aware of these:"
	    .$dumpstring."";
    }
    return;
}


# Forget an event since it was handled.
sub forget($$) {
    my $self = shift;
    my $event_id = shift;

    if( exists $self->Events->{ $event_id } ) {
	delete $self->Events->{ $event_id };
    } else {
	my $dumpstring = Data::Dumper->Dump([$self->Events], ["Events"]);
	die "Unregistered event $event_id.  I have am aware of these:"
	    .$dumpstring."";
    }
    return;
}


# Fence until all outstanding requests are complete.  Store all events.
# Return an array of requests fetched.
sub fence($) {
    my $self = shift;
    my @fetched_requests = ();
    my $start_time = time();

    while( keys %{$self->Requests} ) {
	foreach my $request_id (sort keys %{$self->Requests}) {
	    print "Fetching request $request_id.\n"
		if( $self->Debug > 1 );
	    my $response = $self->send( "request $request_id" );
	    push @fetched_requests, $request_id
		if( ($response->{'status'} eq "SUCCESS") ) 
	}
	die "Timeout on waiting for requests (fence, storing results)."
	    if( $self->Timeout() < (time() - $start_time) )
    }

    return @fetched_requests;
}


# Fence until all outstanding requests are complete.  Ignore everything.
sub fence_ignore($) {
    my $self = shift;

    my @fetched_requests = $self->fence();

    while( my $request_id = pop @fetched_requests ) {
	print "Ignoring request $request_id.\n"
	    if( $self->Debug > 1 );
	pop @{$self->Results}; # Discard.
    }

    return
}


# Get devices from server.
# Returns a hashref for DeviceID => details.
sub device_list($$) {
    my $self = shift;
    my $group = shift // "all";

    $self->send( "get $group list" );
    $self->fence();
    die "I only expected a single Result on the queue for me!"
	unless(scalar(@{$self->Results}) == 1);

    my $result = pop @{$self->Results};
    my %devices = ();

    foreach my $device (@{$result->{'devices'}}) {
	$device->{"__status__"} = "UP";
	$devices{$device->{"device_id"}} = $device;
    }
    foreach my $device (@{$result->{'error'}}) {
	$device->{"__status__"} = "DOWN";
	$devices{$device->{"device_id"}} = $device;
    }

    return \%devices;
}


# Get devices from server.
# Only gets devices currently up.
# Returns a hashref for DeviceID => details.
sub device_list_connected($$) {
    my $self = shift;
    my $group = shift // "all";

    my %devices = %{$self->device_list($group)};
    foreach my $id (sort keys %devices) {
	delete $devices{$id}
	unless( $devices{$id}->{"__status__"} eq "UP" );
    }

    return \%devices;
}


# Wait for a new device.
# Returns deviceID.
sub wait_for_new_device($$) {
    my $self = shift;
    my $group = shift;
    my $new_device_id = undef;

    my $old_device_list = $self->device_list_connected($group);

    print "Found ".scalar(keys %{$old_device_list})." devices up.\n"
	if( $self->Debug >= 1 );

    until( defined($new_device_id) ) {
	my $new_device_list = $self->device_list_connected($group);

	# Delete all devices already known.
	foreach my $id (sort keys %{$new_device_list}) {
	    delete $new_device_list->{$id}
                if( exists($old_device_list->{$id}) );
	}

	# Now see if exactly one new device is left.
	foreach my $id (sort keys %{$new_device_list}) {
	    die "Too many devices added at once!  I can only handle one."
		if( defined($new_device_id) );
	    $new_device_id = $id;
	}

	print "Still waiting for a new device...\n"
	    if( $self->Debug >= 1 );
	sleep 2;
    }

    print "Newest: ".$new_device_id."\n"
	if( $self->Debug >= 1 );

    return $new_device_id;
}


# Finds a single device.
# Dies if there is more than one matching device.
# Returns deviceID.
sub find_single_device($$) {
    my $self = shift;
    my $group = shift;
    my $new_device_id = undef;

    my $device_list = $self->device_list_connected($group);

    my $device_count = scalar keys %{$device_list};

    die "Found $device_count devices.  I'm expecing exactly one (1)!"
	unless( $device_count == 1 );

    ( $new_device_id ) = keys %{$device_list};

    print "Found single device: ".$new_device_id."\n"
	if( $self->Debug >= 1 );

    return $new_device_id;
}


# Close Telnet connection to Aptovision API server.
sub close($) {
    my $self = shift;
    $self->Telnet->close();
}

1;
__END__


# CLEAN UP AUTOMATICALLY on destruction??
$telnet->close();

FIXME:
Handle Events and clear -- e.g. request_complete
Wait for requests to complete?  (Fence?)

Don't Fix:
Asynchronous events.
