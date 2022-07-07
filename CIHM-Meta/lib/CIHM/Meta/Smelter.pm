package CIHM::Meta::Smelter;

use strict;
use Carp;
use Log::Log4perl;

use CIHM::Meta::Smelter::Worker;

use Coro::Semaphore;
use AnyEvent::Fork;
use AnyEvent::Fork::Pool;

use Try::Tiny;
use JSON;
use Data::Dumper;
use IO::Socket::SSL;

=head1 NAME

CIHM::Meta::Smelter - Extract metadata from CIHM repository and add to 2020+ design access platform


=head1 SYNOPSIS

    my $smelter = CIHM::Meta::Smelter->new($args);
      where $args is a hash of arguments.

=cut

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::Smelter->new() not a hash\n";
    }
    $self->{args} = $args;

    $self->{skip}       = delete $args->{skip};
    $self->{descending} = delete $args->{descending};
    $self->{aip}        = delete $args->{aip};

    $self->{maxprocs} = delete $args->{maxprocs};
    if ( !$self->{maxprocs} ) {
        $self->{maxprocs} = 3;
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

    # This checks everything a worker will need, prior to any fork()ing.
    my $test = CIHM::Meta::Smelter::Worker::initworker( $self->args );
    die "Failure in CIHM::Meta::Smelter::Worker::initworker\n" if ( !$test );

    $self->{dipstagingdb} = new restclient(
        server      => $args->{couchdb_dipstaging},
        type        => 'application/json',
        clientattrs => { timeout => 3600 },
    );
    $self->dipstagingdb->set_persistent_header(
        'Accept' => 'application/json' );
    $test = $self->dipstagingdb->head("/");
    if ( !$test || $test->code != 200 ) {
        die
"Problem connecting to `dipstaging` Couchdb database. Check configuration\n";
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

sub descending {
    my $self = shift;
    return $self->{descending};
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

sub dipstagingdb {
    my $self = shift;
    return $self->{dipstagingdb};
}

sub cantaloupe {
    my $self = shift;
    return $self->{cantaloupe};
}

sub smelter {
    my ($self) = @_;

    $self->log->info( "Smelter skip="
          . $self->skip
          . " limit="
          . $self->limit
          . " maxprocs="
          . $self->maxprocs
          . " timelimit="
          . $self->{timelimit}
          . " descending="
          . $self->descending );

    my $pool =
      AnyEvent::Fork->new->require("CIHM::Meta::Smelter::Worker")
      ->AnyEvent::Fork::Pool::run(
        "CIHM::Meta::Smelter::Worker::smelt",
        max        => $self->maxprocs,
        load       => 2,
        on_destroy => ( my $cv_finish = AE::cv ),
      );

    # Semaphore keeps us from filling the queue with too many AIPs before
    # some are processed.
    my $sem = new Coro::Semaphore( $self->maxprocs * 2 );
    my $somework;

    while ( my $aip = $self->getNextAIP ) {
        $somework = 1;
        $self->{inprogress}->{$aip} = 1;
        $sem->down;
        $pool->(
            $aip,
            encode_json $self->args,
            sub {
                my $aip = shift;
                $sem->up;
                delete $self->{inprogress}->{$aip};
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

sub getNextAIP {
    my $self = shift;

    if ( defined $self->{aip} ) {
        return if $self->{aip} == JSON::true;
        my $aip = $self->{aip};
        $self->{aip} = JSON::true;
        return $aip;
    }

    return if $self->endtime && time() > $self->endtime;

    my $skipparam = '';
    if ( $self->skip ) {
        $skipparam = "&skip=" . $self->skip;
    }
    my $descparam = '';
    if ( $self->descending ) {
        $descparam = "&descending=true";
    }

    $self->dipstagingdb->type("application/json");
    my $url =
        "/_design/access/_view/smeltQueue?reduce=false&limit="
      . $self->limit
      . $skipparam
      . $descparam;
    my $res = $self->dipstagingdb->get( $url, {},
        { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        if ( exists $res->data->{rows} ) {
            foreach my $hr ( @{ $res->data->{rows} } ) {
                my $uid = $hr->{id};
                if ( !exists $self->{inprogress}->{$uid} ) {
                    return $uid;
                }
            }
        }
    }
    else {
        warn "$url GET return code: " . $res->code . "\n";
    }
    return;
}

1;
