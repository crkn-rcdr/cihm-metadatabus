package CIHM::Meta::REST::wipmeta;

use strict;
use Carp;
use DateTime;
use JSON;

use Moo;
with 'Role::REST::Client';
use Types::Standard qw(HashRef Str Int Enum HasMethods);

=head1 NAME

CIHM::Meta::REST::wipmeta - Subclass of Role::REST::Client used to
interact with "wipmeta" CouchDB databases

=head1 SYNOPSIS

    my $wipmeta = CIHM::Meta::REST::wipmeta->new($args);
      where $args is a hash of arguments.  In addition to arguments
      processed by Role::REST::Client we have the following 

      $args->{database} is the Couch database name.

=cut

sub BUILD {
    my $self = shift;
    my $args = shift;

    $self->{LocalTZ} = DateTime::TimeZone->new( name => 'local' );
    $self->{database} = $args->{database};
    $self->set_persistent_header( 'Accept' => 'application/json' );
}

# Simple accessors for now -- Do I want to Moo?
sub database {
    my $self = shift;
    return $self->{database};
}

=head1 METHODS

=head2 update_basic

    sub update_basic ( string UID, hash updatedoc )

    updatedoc - a hash that is passed to the _update function of the
        design document to update data for the given UID.
        Meaning of fields in updatedoc is defined by that function.

  returns null, or a string representing the return from the _update
  design document.  Return values include "update", "no update", "no create".


=cut

# backward compatable which returns null or the string in the {return} key.
sub update_basic {
    my ( $self, $uid, $updatedoc ) = @_;

    my $r = $self->update_basic_full( $uid, $updatedoc );
    if ( ref($r) eq "HASH" ) {
        return $r->{return};
    }
}

# Returns the full return object
sub update_basic_full {
    my ( $self, $uid, $updatedoc ) = @_;
    my ( $res, $code, $data );

    # This encoding makes $updatedoc variables available as form data
    $self->type("application/x-www-form-urlencoded");
    $res = $self->post(
        "/" . $self->{database} . "/_design/tdr/_update/basic/" . $uid,
        $updatedoc, { deserializer => 'application/json' } );

    if ( $res->code != 201 && $res->code != 200 ) {
        warn "_update/basic/$uid POST return code: " . $res->code . "\n";
    }
    return $res->data;
}

sub get_aip {
    my ( $self, $uid ) = @_;

    $self->type("application/json");
    my $res = $self->get( "/" . $self->{database} . "/$uid",
        {}, { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        return $res->data;
    }
    else {
        warn "get_aip return code: " . $res->code . "\n";
        return;
    }
}

1;
