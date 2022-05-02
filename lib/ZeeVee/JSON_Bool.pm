# Perl module for converting JSON Bool Objects to Y/N
package ZeeVee::JSON_Bool;

use warnings;
use strict;

use Scalar::Util ( qw/reftype/ );


# Recursively convert JSON:PP:Boolean to strings.
sub to_YN($) {
    my $value = shift;
    my $type = reftype($value);

    if(! defined($value) ) {
	; # Leave it undefined.
    } elsif(! defined($type) ) { # Scalar value
	$value = $value;
    } elsif( $type eq "SCALAR" ) { # Scalar Reference -- could be JSON::PP:Boolean
	$value = to_YN_Scalar($value);
    } elsif( $type eq "HASH" ) {
	$value = to_YN_Hash($value);
    } elsif( $type eq "ARRAY" ) {
	$value = to_YN_Array($value);
    } else {
	warn "New type $type.";
	$value = $value;
    }
    return $value;
}

# Helper subroutines to convert JSON booleans to yes/no.
sub to_YN_Scalar($) {
    my $ref = shift;
    if( defined($ref)
	&& JSON::is_bool($ref) ) {
	my $value = ( ${$ref} ? 'YES' : 'NO' );
	return $value
    } else {
	$ref = to_YN($ref);
	return $ref;
    }
}

sub to_YN_Hash($) {
    my $hashref = shift;
    foreach my $value (values %{$hashref}) {
	$value = to_YN($value)
    }
    return $hashref;
}

sub to_YN_Array($) {
    my $arrayref = shift;
    foreach my $value (values @{$arrayref}) {
	$value = to_YN($value)
    }
    return $arrayref;
}

1;
