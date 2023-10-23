package CIHM::Meta::SolrStream;

use strict;
use Carp;
use Log::Log4perl;
use Role::REST::Client;
use Try::Tiny;
use Data::Dumper;
use JSON;

=head1 NAME

CIHM::Meta::SolrStream - Stream cosearch from CouchDB to Solr.

=head1 SYNOPSIS

    my $solr = CIHM::Meta::SolrStream->new($args);
      where $args is a hash of arguments.

      $args->{localdocument} is the couchdb local document the past sequence number is saved into and read from next iteration.
      $args->{since} is a sequence ID

      
=cut

{

    package restclient;

    use Moo;
    with 'Role::REST::Client';

}

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::SolrStream->new() not a hash\n";
    }
    $self->{args} = $args;

    Log::Log4perl->init_once("/etc/canadiana/tdr/log4perl.conf");
    $self->{logger} = Log::Log4perl::get_logger("CIHM::TDR");

    $self->{cosearch} = new restclient(
        server      => $args->{couchserver},
        type        => 'application/json',
        clientattrs => { timeout => 3600 }
    );

    $self->{cosolr} = new restclient(
        server      => $args->{solrserver},
        type        => 'application/json',
        clientattrs => { timeout => 3600 }
    );
    return $self;
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}

sub since {
    my $self = shift;
    return $self->{args}->{since};
}

sub limit {
    my $self = shift;
    return $self->{args}->{limit};
}

sub timelimit {
    my $self = shift;
    return $self->{args}->{timelimit};
}

sub endtime {
    my $self = shift;
    return $self->{endtime};
}

sub localdocument {
    my $self = shift;
    return $self->{args}->{localdocument};
}

sub log {
    my $self = shift;
    return $self->{logger};
}

sub cosearch {
    my $self = shift;
    return $self->{cosearch};
}

sub couchdb {
    my $self = shift;
    return $self->{args}->{couchdb};
}

sub cosolr {
    my $self = shift;
    return $self->{cosolr};
}

sub cosolrdb {
    my $self = shift;
    return $self->{args}->{solrdb};
}

sub process {
    my ($self) = shift;

    my $since = $self->getSince();
    $since = $self->since if defined $self->since;
    if ( !defined $since ) {
        $since = 0;
    }

    my $timelimit = $self->timelimit;
    if ( defined $timelimit ) {
        $self->{endtime} = time() + $self->timelimit;
    }
    else {
        $timelimit = "none";
    }

    $self->log->info( "localdocument="
          . $self->localdocument
          . " since=$since timelimit=$timelimit" );

    my $startseq = $since;
    while (1) {

        # If past timelimit, commit and exit
        last if $self->endtime && time() > $self->endtime;

        my ( $lastseq, $stream ) = $self->getNextStream($startseq);
        last if !$lastseq;

        my $poststream   = [];
        my $deletestream = [];

        foreach my $doc ( @{$stream} ) {
            next if substr( $doc->{id}, 0, 1 ) eq '_';

            if ( $doc->{deleted} ) {
                push @{$deletestream}, $doc->{id};
            }
            else {
                delete $doc->{doc}->{'_rev'};
                delete $doc->{doc}->{'_id'};
                push @{$poststream}, $doc->{doc};
            }
        }
        if ( scalar @{$deletestream} ) {
            $self->postSolrStream( { delete => $deletestream }, $startseq );
        }
        if ( scalar @{$poststream} ) {
            $self->postSolrStream( $poststream, $startseq );
        }
        $self->putSince($lastseq);
        $self->log->info(
            "localdocument=" . $self->localdocument . " seq=$lastseq" );
        $startseq = $lastseq;
    }

    # Only commit if we have made changes...
    if ( $startseq != $since ) {
        $self->postSolrStream( { commit => {} }, $startseq );
    }
}

sub getNextStream {
    my ( $self, $since ) = @_;

    $self->cosearch->type("application/json");
    my $res = $self->cosearch->get(
        "/"
          . $self->couchdb
          . "/_changes?include_docs=true&since=$since&limit="
          . $self->limit,
        {},
        { deserializer => 'application/json' }
    );
    if ( $res->code == 200 ) {
        if ( exists $res->data->{results}
            && scalar( @{ $res->data->{results} } ) )
        {
            return ( $res->data->{last_seq}, $res->data->{results} );
        }
    }
    else {
        die "_changes GET return code: " . $res->code . "\n";
    }
}

sub postSolrStream {
    my ( $self, $stream, $startseq ) = @_;

    $self->cosolr->type("application/json");
    my $res =
      $self->cosolr->post( "/solr/" . $self->cosolrdb . "/update", $stream );
    if ( $res->code != 201 && $res->code != 200 ) {
        $self->log->error( "seq=$startseq return code: " . $res->code );
    }
    return;
}

sub getSince {
    my ($self) = @_;

    my $since;
    $self->cosearch->type("application/json");
    my $res = $self->cosearch->get(
        "/" . $self->couchdb . "/_local/" . $self->localdocument,
        {}, { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        $self->{localdocrev} = $res->data->{"_rev"};
        $since = $res->data->{"since"};
    }
    return $since;
}

sub putSince {
    my ( $self, $since ) = @_;

    my $newdoc = { since => $since };
    if ( $self->{localdocrev} ) {
        $newdoc->{"_rev"} = $self->{localdocrev};
    }

    $self->cosearch->type("application/json");
    my $res = $self->cosearch->put(
        "/" . $self->couchdb . "/_local/" . $self->localdocument, $newdoc );
    if ( $res->code != 201 && $res->code != 200 ) {
        $self->log->error( "_local/"
              . $self->localdocument
              . " PUT return code: "
              . $res->code );
    }
    else {
        $self->{localdocrev} = $res->data->{"rev"};
    }
    return;
}

1;
