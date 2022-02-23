package CIHM::Meta::REST::collection;

use strict;
use Carp;
use Data::Dumper;
use DateTime;
use JSON;
use URI::Escape qw( uri_escape_utf8 );

use Moo;
with 'Role::REST::Client';
use Types::Standard qw(HashRef Str Int Enum HasMethods);

=head1 NAME

CIHM::Meta::REST::collection - Subclass of Role::REST::Client used to
interact with "collection" CouchDB database

=head1 SYNOPSIS

    my $t_repo = CIHM::Meta::REST::collection->new($args);
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

# backward compatable which returns null or the string in the {return} key.
sub update_basic {
    my ( $self, $noid, $updatedoc ) = @_;

    my $r = $self->update_basic_full( $noid, $updatedoc );
    if ( ref($r) eq "HASH" ) {
        return $r->{return};
    }
}

# Returns the full return object
sub update_basic_full {
    my ( $self, $noid, $updatedoc ) = @_;
    my ( $res, $code, $data );

    # This encoding makes $updatedoc variables available as form data
    $self->type("application/x-www-form-urlencoded");
    my $uri = "/"
      . $self->database
      . "/_design/metadatabus/_update/basic/"
      . uri_escape_utf8($noid);

    $res =
      $self->post( $uri, $updatedoc, { deserializer => 'application/json' } );

    if ( $res->code != 201 && $res->code != 200 ) {
        warn $uri . " POST return code: " . $res->code . "\n";
    }
    return $res->data;
}

sub get_document {
    my ( $self, $docid ) = @_;

    $self->type("application/json");
    my $url = "/" . $self->{database} . "/$docid";
    my $res = $self->get( $url, {}, { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        return $res->data;
    }
    else {
        warn "GET $url return code: " . $res->code . "\n";
        return;
    }
}

sub getCollections {
    my ( $self, $docid ) = @_;

    $self->type("application/json");
    my $url = "/" . $self->{database} . "/_design/access/_view/items";
    my $res = $self->post( $url, { keys => [$docid] }, { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        return $res->data->{rows};
    }
    else {
        warn "POST $url return code: " . $res->code . "\n";
        return;
    }
}

1;
