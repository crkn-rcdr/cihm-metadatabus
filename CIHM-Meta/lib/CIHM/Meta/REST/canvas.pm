package CIHM::Meta::REST::canvas;

use strict;
use Carp;
use Data::Dumper;
use DateTime;
use JSON;

use Moo;
with 'Role::REST::Client';
use Types::Standard qw(HashRef Str Int Enum HasMethods);

=head1 NAME

CIHM::Meta::REST::canvas - Subclass of Role::REST::Client used to
interact with "canvas" CouchDB database

=head1 SYNOPSIS

    my $t_repo = CIHM::Meta::REST::canvas->new($args);
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

sub put_document {
    my ( $self, $docid, $document ) = @_;

    $self->type("application/json");
    my $url = "/" . $self->{database} . "/$docid";
    my $res = $self->put( $url, $document, { deserializer => 'application/json' } );
    if ( $res->code == 201 ) {
        return $res->data;
    }
    else {
        warn "PUT $url return code: " . $res->code . "\n";
        return;
    }
}


sub get_documents {
    my ( $self, $docids ) = @_;

    $self->type("application/json");
    my $url = "/" . $self->{database} . "/_all_docs?include_docs=true";
    my $res = $self->post( $url, { keys => $docids }, { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        my @return;
        foreach my $row (@{$res->data->{rows}}) {
            if (exists $row->{doc}) {
                push @return, $row->{doc};
            } else {
                warn "Key: ". $row->{key}. "   Error: ". $row->{error}."\n";
                push @return, undef;
            }
        }
        return \@return;
    }
    else {
        warn "POST $url return code: " . $res->code . "\n";
        return;
    }
}

1;
