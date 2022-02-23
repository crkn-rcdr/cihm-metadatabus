package CIHM::Meta::REST::dmdtask;

use strict;
use Carp;
use DateTime;
use JSON;
use URI::Escape qw( uri_escape_utf8 );

use Moo;
with 'Role::REST::Client';
use Types::Standard qw(HashRef Str Int Enum HasMethods);

=head1 NAME

CIHM::Meta::REST::dmdtask - Subclass of Role::REST::Client used to
interact with "dmdtask" CouchDB database

=head1 SYNOPSIS

    my $t_repo = CIHM::Meta::REST::dmdtask->new($args);
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

# Simple call to update document
sub processupdate {
    my ( $self, $taskid, $updatedoc ) = @_;
    my ( $res, $code, $data );

    #  Post directly as JSON data (Different from other couch databases)
    $self->type("application/json");
    my $url =
      "/" . $self->{database} . "/_design/access/_update/process/" . $taskid;
    $res =
      $self->post( $url, $updatedoc, { deserializer => 'application/json' } );

    if ( $res->code != 201 && $res->code != 200 ) {
        warn "$url POST return code: " . $res->code . "\n";
    }

    # _update function returns json.
    return $res->data;
}

sub get_document {
    my ( $self, $taskid ) = @_;

    $self->type("application/json");
    my $url = "/" . $self->{database} . "/$taskid";
    my $res = $self->get( $url, {}, { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        return $res->data;
    }
    else {
        warn "GET $url return code: " . $res->code . "\n";
        return;
    }
}

sub put_document {
    my ( $self, $taskid, $document ) = @_;

    $self->type("application/json");
    my $url = "/" . $self->{database} . "/$taskid";
    my $res = $self->put( $url, $document, { deserializer => 'application/json' } );
    if ( $res->code == 201 ) {
        return $res->data;
    }
    else {
        warn "PUT $url return code: " . $res->code . "\n";
        return;
    }
}

1;
