package CIHM::Meta::Dmdtask;

use strict;
use Carp;
use Config::General;
use Log::Log4perl;

use CIHM::Meta::REST::dmdtask;
use CIHM::Meta::Dmdtask::Worker;

use Coro::Semaphore;
use AnyEvent::Fork;
use AnyEvent::Fork::Pool;

use Try::Tiny;
use JSON;
use Data::Dumper;

=head1 NAME

CIHM::Meta::Dmdtask - Process metadata uploads and potentially copy to Preservation and/or Acccess platforms.


=head1 SYNOPSIS

    my $dmdtask = CIHM::Meta::Dmdtask->new($args);
      where $args is a hash of arguments.

      $args->{configpath} is as used by Config::General

=cut

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::Hammer2->new() not a hash\n";
    }
    $self->{args} = $args;


    # Connect to Swift Object Storage
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


    # Connect to CouchDB
    $self->{dmdtaskdb} = new restclient(
        server      => $args->{couchdb_dmdtask},
        type        => 'application/json',
        clientattrs => { timeout => 3600 },
    );
    $self->dmdtaskdb->set_persistent_header( 'Accept' => 'application/json' );
    $test = $self->dmdtaskdb->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to Couchdb database. Check configuration\n";
    }

    # Set up in-progress hash (Used to determine which AIPs which are being
    # processed by a slave so we don't try to do the same AIP twice.
    $self->{inprogress} = {};

    return $self;
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}

sub maxprocs {
    my $self = shift;
    return $self->args->{maxprocs};
}

sub log {
    my $self = shift;
    return $self->args->{logger};
}

sub dmdtaskdb {
    my $self = shift;
    return $self->{dmdtaskdb};
}

sub access_metadata {
    my $self = shift;
    return $self->args->{swift_access_metadata};
}

sub swift {
    my $self = shift;
    return $self->{swift};
}


sub dmdtask {
    my ($self) = @_;

    $self->log->info( "Dmdtask: maxprocs=" . $self->maxprocs );

    print Dumper ( $self->args );
    return 0;

    my $pool =
      AnyEvent::Fork->new->require("CIHM::Meta::Dmdtask::Worker")
      ->AnyEvent::Fork::Pool::run(
        "CIHM::Meta::Dmdtask::Worker::task",
        max        => $self->maxprocs,
        load       => 2,
        on_destroy => ( my $cv_finish = AE::cv ),
      );

    # Semaphore keeps us from filling the queue with too many AIPs before
    # some are processed.
    my $sem = new Coro::Semaphore( $self->maxprocs * 2 );
    my $somework;

    while ( my $taskid = $self->getNextID() ) {
        $somework = 1;
        $self->{inprogress}->{$taskid} = 1;
        $sem->down;
        $pool->(
            $taskid,
            $self->configpath,
            sub {
                my $taskid = shift;
                $sem->up;
                delete $self->{inprogress}->{$taskid};
            }
        );
    }
    undef $pool;
    if ($somework) {
        $self->log->info("Waiting for child processes to finish");
    }
    $cv_finish->recv;
    if ($somework) {
        $self->log->info("Finished.");
    }
}

sub getNextID {
    my ($self) = @_;

    return if $self->endtime && time() > $self->endtime;

    my $skipparam = '';
    if ( $self->skip ) {
        $skipparam = "&skip=" . $self->skip;
    }

    $self->dmdtaskdb->type("application/json");
    my $url = "/"
      . $self->dmdtaskdb->database
      . "/_design/access/_view/processQueue?reduce=false&descending=true&limit="
      . $self->limit
      . $skipparam;
    my $res =
      $self->dmdtaskdb->get( $url, {}, { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        if ( exists $res->data->{rows} ) {
            foreach my $hr ( @{ $res->data->{rows} } ) {
                my $taskid = $hr->{id};
                if ( !exists $self->{inprogress}->{$taskid} ) {
                    return $taskid;
                }
            }
        }
    }
    else {
        warn "$url GET return code: " . $res->code . "\n";
    }
    return;
}


{

    package restclient;

    use Moo;
    with 'Role::REST::Client';
}


1;
