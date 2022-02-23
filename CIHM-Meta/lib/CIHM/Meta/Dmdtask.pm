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

    $self->{skip} = delete $args->{skip};

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

    my %confighash =
      new Config::General( -ConfigFile => $args->{configpath}, )->getall;

    if ( exists $confighash{dmdtask} ) {
        $self->{dmdtaskdb} = new CIHM::Meta::REST::dmdtask(
            server      => $confighash{dmdtask}{server},
            database    => $confighash{dmdtask}{database},
            type        => 'application/json',
            conf        => $args->{configpath},
            clientattrs => { timeout => 3600 },
        );
    }
    else {
        croak "Missing <dmdtask> configuration block in config\n";
    }

    return $self;
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}

sub configpath {
    my $self = shift;
    return $self->{args}->{configpath};
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

sub dmdtaskdb {
    my $self = shift;
    return $self->{dmdtaskdb};
}

sub dmdtask {
    my ($self) = @_;

    $self->log->info( "Dmdtask time: conf="
          . $self->configpath
          . " skip="
          . $self->skip
          . " limit="
          . $self->limit
          . " maxprocs="
          . $self->maxprocs
          . " timelimit="
          . $self->{timelimit} );

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
    my ( $self ) = @_;

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

1;
