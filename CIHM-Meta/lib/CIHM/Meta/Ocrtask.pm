package CIHM::Meta::Ocrtask;

use strict;
use Carp;
use Config::General;
use Log::Log4perl;
use CIHM::Swift::Client;

use Try::Tiny;
use JSON;
use Data::Dumper;
use Switch;
use URI::Escape;

=head1 NAME

CIHM::Meta::Ocrtask - Process image exports from, and OCR data imports to, the Access platform databases and object storage.


=head1 SYNOPSIS

    my $ocrtask = CIHM::Meta::Omdtask->new($args);
      where $args is a hash of arguments.


=cut

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::Ocrtask->new() not a hash\n";
    }
    $self->{args} = $args;

    my %swiftopt = ( furl_options => { timeout => 3600 } );
    foreach ( "server", "user", "password", "account" ) {
        if ( exists $args->{ "swift_" . $_ } ) {
            $swiftopt{$_} = $args->{ "swift_" . $_ };
        }
    }
    $self->{swift} = CIHM::Swift::Client->new(%swiftopt);

    my $test = $self->swift->container_head( $self->access_metadata );
    if ( !$test || $test->code != 204 ) {
        die "Problem connecting to Swift container. Check configuration\n";
    }

    $self->{ocrtaskdb} = new restclient(
        server      => $args->{couchdb_ocrtask},
        type        => 'application/json',
        clientattrs => { timeout => 3600 },
    );
    $self->ocrtaskdb->set_persistent_header( 'Accept' => 'application/json' );
    $test = $self->ocrtaskdb->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to Couchdb database. Check configuration\n";
    }

    return $self;
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}

sub log {
    my $self = shift;
    return $self->args->{logger};
}

sub access_metadata {
    my $self = shift;
    return $self->args->{swift_access_metadata};
}

sub swift {
    my $self = shift;
    return $self->{swift};
}

sub ocrtaskdb {
    my $self = shift;
    return $self->{ocrtaskdb};
}

sub maxprocs {
    my $self = shift;
    return $self->args->{maxprocs};
}

sub ocrtask {
    my ($self) = @_;

    $self->log->info( "Ocrtask maxprocs=" . $self->maxprocs );

    $self->ocrtaskdb->type("application/json");
    my $url =
"/_design/access/_view/ocrQueue?reduce=false&descending=true&include_docs=true";
    my $res =
      $self->ocrtaskdb->get( $url, {}, { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        if ( exists $res->data->{rows} ) {
            foreach my $task ( @{ $res->data->{rows} } ) {
                my $todo = shift @{ $task->{key} };
                if ( $todo eq 'export' ) {
                    $self->ocrExport( $task->{doc} );
                }
                else {
                    $self->ocrImport( $task->{doc} );
                }
            }
        }
    }
    else {
        die "$url GET return code: " . $res->code."\n";
    }
}

sub ocrExport {
    my ( $self, $task ) = @_;

    my $taskid = $task->{'_id'};

    switch ( int( rand(3) ) ) {
        case 0 {
            $self->postResults( "Export", $taskid, JSON::true )
        }
        case 1 {
            $self->postResults( "Export", $taskid, JSON::true,
                "Just a little export warning." )
        }
        case 2 {
            $self->postResults( "Export", $taskid, JSON::false,
                "Why this export failed." )
        }
    }
}

sub ocrImport {
    my ( $self, $task ) = @_;


    my $taskid = $task->{'_id'};

    switch ( int( rand(3) ) ) {
        case 0 {
            $self->postResults( "Import", $taskid, JSON::true )
        }
        case 1 {
            $self->postResults( "Import", $taskid, JSON::true,
                "Just a little import warning." )
        }
        case 2 {
            $self->postResults( "Import", $taskid, JSON::false,
                "Why this import failed." )
        }
    }
}

sub postResults {
    my ( $self, $which, $taskid, $succeeded, $message ) = @_;

    my $url =
      "/_design/access/_update/updateOCR${which}/" . uri_escape_utf8($taskid);
    my $updatedoc = { succeeded => $succeeded, message => $message };

    my $res =
      $self->ocrtaskdb->post( $url, $updatedoc,
        { deserializer => 'application/json' } );

    if ( $res->code != 201 && $res->code != 200 ) {
        die "$url POST return code: " . $res->code . "\n";
    }
    if ( $res->data ) {
        if ( exists $res->data->{message} ) {
            $self->log->info( $taskid . ": " . $res->data->{message} );
        }
        if ( exists $res->data->{error} ) {
            $self->log->error( $taskid . ": " . $res->data->{error} );
        }
    }
}

{

    package restclient;

    use Moo;
    with 'Role::REST::Client';
}

1;
