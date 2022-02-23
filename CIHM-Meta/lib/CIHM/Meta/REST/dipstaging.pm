package CIHM::Meta::REST::dipstaging;

use strict;
use Carp;
use DateTime;
use JSON;

use Moo;
with 'Role::REST::Client';
use Types::Standard qw(HashRef Str Int Enum HasMethods);

=head1 NAME

CIHM::Meta::REST::dipstaging - Subclass of Role::REST::Client used to
interact with "dipstaging" CouchDB databases

=head1 SYNOPSIS

    my $dipstaging = CIHM::Meta::REST::dipstaging->new($args);
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

# Simple call to basic update document
sub update_basic {
    my ( $self, $uid, $updatedoc ) = @_;
    my ( $res, $code, $data );

    #  Post directly as JSON data (Different from other couch databases)
    $self->type("application/json");
    $res = $self->post(
        "/" . $self->{database} . "/_design/sync/_update/basic/" . $uid,
        $updatedoc, { deserializer => 'application/json' } );

    if ( $res->code != 201 && $res->code != 200 ) {
        warn "_update/basic/$uid POST return code: " . $res->code . "\n";
    }

    # _update function returns json.
    return $res->data;
}

# Call used by CIHM::Meta::RepoSync, and needs to be compatable with that functionality.
sub update_basic_full {
    my ( $self, $uid, $updatedoc ) = @_;
    my ( $res, $code, $data );

# Special case, rather than modify the other update functions to not encode values as json strings.
    my %newdoc = (
        'repos'        => decode_json( $updatedoc->{repos} ),
        'manifestdate' => $updatedoc->{manifestdate}
    );

    if ( exists $updatedoc->{METS} ) {
        $newdoc{METS} = decode_json( $updatedoc->{METS} );
    }

    #  Post directly as JSON data (Different from other couch databases)
    $self->type("application/json");
    $res = $self->post(
        "/" . $self->{database} . "/_design/sync/_update/basic/" . $uid,
        \%newdoc, { deserializer => 'application/json' } );

    if ( $res->code != 201 && $res->code != 200 ) {
        warn "_update/basic/$uid POST return code: " . $res->code . "\n";
    }

# _update function only returns a string and not data, so nothing to return here
    return $res->data;
}

1;
