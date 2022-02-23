package CIHM::Meta::CopyCanvasImage;

use strict;
use Carp;
use Config::General;
use Log::Log4perl;

use CIHM::Meta::REST::canvas;
use CIHM::Meta::CopyCanvasImage::Worker;

use Coro::Semaphore;
use AnyEvent::Fork;
use AnyEvent::Fork::Pool;

use Try::Tiny;
use JSON;
use Data::Dumper;

=head1 NAME

CIHM::Meta::CopyCanvasImage - Extract metadata from CIHM repository and add to 2020+ design access platform


=head1 SYNOPSIS

    my $copycanvasimage = CIHM::Meta::CopyCanvasImage->new($args);
      where $args is a hash of arguments.

      $args->{configpath} is as used by Config::General

=cut

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::CopyCanvasImage->new() not a hash\n";
    }
    $self->{args} = $args;

    $self->{skip}       = delete $args->{skip};
    $self->{descending} = delete $args->{descending};
    $self->{noid}       = delete $args->{noid};

    $self->{maxprocs} = delete $args->{maxprocs};
    if ( !$self->{maxprocs} ) {
        $self->{maxprocs} = 3;
    }

    # Set up for time limit
    $self->{timelimit} = delete $args->{timelimit};
    if ( $self->{timelimit} ) {
        $self->{endtime} = time() + $self->{timelimit};
    }

    # Set up in-progress hash (Used to determine which IDs are being
    # processed by a subprocess so we don't try to do the same ID twice.
    $self->{inprogress} = {};

    $self->{limit} = delete $args->{limit};

    Log::Log4perl->init_once("/etc/canadiana/tdr/log4perl.conf");
    $self->{logger} = Log::Log4perl::get_logger("CIHM::TDR");

    my %confighash =
      new Config::General( -ConfigFile => $args->{configpath}, )->getall;

    # Undefined if no <canvas> config block
    if ( exists $confighash{canvas} ) {
        $self->{canvasdb} = new CIHM::Meta::REST::canvas(
            server      => $confighash{canvas}{server},
            database    => $confighash{canvas}{database},
            type        => 'application/json',
            conf        => $args->{configpath},
            clientattrs => { timeout => 3600 },
        );
    }
    else {
        croak "Missing <canvas> configuration block in config\n";
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

sub canvasdb {
    my $self = shift;
    return $self->{canvasdb};
}

sub doCopy {
    my ($self) = @_;

    $self->log->info( "CopyCanvasImage: conf="
          . $self->configpath
          . " skip="
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
      AnyEvent::Fork->new->require("CIHM::Meta::CopyCanvasImage::Worker")
      ->AnyEvent::Fork::Pool::run(
        "CIHM::Meta::CopyCanvasImage::Worker::copy",
        max        => $self->maxprocs,
        load       => 2,
        on_destroy => ( my $cv_finish = AE::cv ),
      );

    # Semaphore keeps us from filling the queue with too many IDs before
    # some are processed.
    my $sem = new Coro::Semaphore( $self->maxprocs * 2 );
    my $somework;

    while ( my $canvasid = $self->getNextCanvas ) {
        $somework = 1;
        $self->{inprogress}->{$canvasid} = 1;
        $sem->down;
        $pool->(
            $canvasid,
            $self->configpath,
            sub {
                my $canvasid = shift;
                $sem->up;

        # Remove from inprogress an ID that was returned.  Problems return null.
                delete $self->{inprogress}->{$canvasid} if $canvasid;
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

sub getNextCanvas {
    my $self = shift;

    if ( defined $self->{noid} ) {
        return if $self->{noid} == JSON::true;
        my $noid = $self->{noid};
        $self->{noid} = JSON::true;
        return $noid;
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
    my $limitparam = '';
    if ( $self->limit ) {
        $limitparam = "&limit=" . $self->limit;
    }
    $self->canvasdb->type("application/json");
    my $url = "/"
      . $self->canvasdb->database
      . "/_design/access/_view/copycanvasfiles?reduce=false"
      . $skipparam
      . $limitparam
      . $descparam;
    my $res =
      $self->canvasdb->get( $url, {}, { deserializer => 'application/json' } );
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
