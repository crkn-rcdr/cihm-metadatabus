package CIHM::Meta::Hammer2;

use strict;
use Carp;
use Config::General;
use Log::Log4perl;

use CIHM::Meta::Hammer2::Worker;

use Coro::Semaphore;
use AnyEvent::Fork;
use AnyEvent::Fork::Pool;

use Try::Tiny;
use JSON;

=head1 NAME

CIHM::Meta::Hammer2 - Normalize metadata from new access platform databases and file store, and post to "internalmeta2"


=head1 SYNOPSIS

    my $hammer = CIHM::Meta::Hammer2->new($args);
      where $args is a hash of arguments.

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
        die "Argument to CIHM::Meta::Hammer2->new() not a hash\n";
    }
    $self->{args} = $args;

    $self->{skip} = delete $args->{skip};

    $self->{maxprocs} = delete $args->{maxprocs};
    if ( !$self->{maxprocs} ) {
        $self->{maxprocs} = 1;
    }

    # Set up for time limit
    $self->{timelimit} = delete $args->{timelimit};
    if ( $self->{timelimit} ) {
        $self->{endtime} = time() + $self->{timelimit};
    }

    # Set up in-progress hash (Used to determine which AIPs which are being
    # processed by a slave so we don't try to do the same AIP twice.
    $self->{inprogress} = {};

    $self->{limit} = delete $args->{limit};
    if ( !$self->{limit} ) {
        $self->{limit} = ( $self->{maxprocs} ) * 2 + 1;
    }

    Log::Log4perl->init_once("/etc/canadiana/tdr/log4perl.conf");
    $self->{logger} = Log::Log4perl::get_logger("CIHM::TDR");

    $self->{accessdb} = new restclient(
        server      => $args->{couchdb_access},
        type        => 'application/json',
        clientattrs => { timeout => 3600 },
    );
    $self->accessdb->set_persistent_header( 'Accept' => 'application/json' );
    $self->accessdb->type("application/json");
    my $test = $self->accessdb->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to Couchdb database. Check configuration\n";
    }

    $self->{slug} = delete $self->args->{slug};

    # If there is a slug, set maximum processes to 1
    if ( $self->{slug} ) {
        $self->{maxprocs} = 1;
    }

    return $self;
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}

sub skip {
    my $self = shift;
    return $self->{skip};
}

sub maxprocs {
    my $self = shift;
    return $self->{maxprocs};
}

sub limit {
    my $self = shift;
    return $self->{limit};
}

sub endtime {
    my $self = shift;
    return $self->{endtime};
}

sub log {
    my $self = shift;
    return $self->{logger};
}

sub accessdb {
    my $self = shift;
    return $self->{accessdb};
}

sub hammer {
    my ($self) = @_;

    $self->log->info( "Hammer2 skip="
          . $self->skip
          . " limit="
          . $self->limit
          . " maxprocs="
          . $self->maxprocs
          . " timelimit="
          . $self->{timelimit} );

    my $somework;

    # Handle single without creating a pool.
    if ( $self->maxprocs == 1 ) {
        while ( my $noid = $self->getNextNOID() ) {
            $somework = 1;
            CIHM::Meta::Hammer2::Worker::swing( $noid,
                encode_json $self->args );
        }
    }
    else {
        my $pool =
          AnyEvent::Fork->new->require("CIHM::Meta::Hammer2::Worker")
          ->AnyEvent::Fork::Pool::run(
            "CIHM::Meta::Hammer2::Worker::swing",
            max        => $self->maxprocs,
            load       => 2,
            on_destroy => ( my $cv_finish = AE::cv ),
          );

        # Semaphore keeps us from filling the queue with too many AIPs before
        # some are processed.
        my $sem = new Coro::Semaphore( $self->maxprocs * 2 );

        while ( my $noid = $self->getNextNOID() ) {
            $somework = 1;
            $self->{inprogress}->{$noid} = 1;
            $sem->down;
            $pool->(
                $noid,
                encode_json $self->args,
                sub {
                    my $noid = shift;
                    $sem->up;
                    delete $self->{inprogress}->{$noid};
                }
            );
        }
        undef $pool;
        if ($somework) {
            $self->log->info("Waiting for child processes to finish");
        }
        $cv_finish->recv;
    }

    if ($somework) {
        $self->log->info("Finished.");
    }

}

sub getNextNOID {
    my ($self) = @_;

    return if $self->endtime && time() > $self->endtime;

    if ( defined $self->{slug} ) {
        return if $self->{slug} == JSON::true;
        my $slug = $self->{slug};
        $self->{slug} = JSON::true;

        my $url = "/_design/access/_view/slug";
        my $res = $self->accessdb->post(
            $url,
            { keys         => [$slug] },
            { deserializer => 'application/json' }
        );
        if ( $res->code == 200 ) {
            if ( exists $res->data->{rows} ) {
                my $row = shift @{ $res->data->{rows} };
                if ( $row && defined $row->{id} ) {
                    return $row->{id};
                }
            }
            $self->log->warn("Nothing found for slug=$slug");
        }
        else {
            warn "$url on "
              . $self->accessdb->server
              . " GET return code: "
              . $res->code . "\n";
        }
    }
    else {

        my $skipparam = '';
        if ( $self->skip ) {
            $skipparam = "&skip=" . $self->skip;
        }

        my $url =
            "/_design/metadatabus/_view/hammerQueue?reduce=false&limit="
          . $self->limit
          . $skipparam;
        my $res =
          $self->accessdb->get( $url, {},
            { deserializer => 'application/json' } );
        if ( $res->code == 200 ) {
            if ( exists $res->data->{rows} ) {
                foreach my $hr ( @{ $res->data->{rows} } ) {
                    my $noid = $hr->{id};
                    if ( !exists $self->{inprogress}->{$noid} ) {
                        return $noid;
                    }
                }
            }
        }
        else {
            warn "$url on "
              . $self->accessdb->server
              . " GET return code: "
              . $res->code . "\n";
        }
    }
    return;
}

1;
