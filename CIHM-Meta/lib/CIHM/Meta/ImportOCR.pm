package CIHM::Meta::ImportOCR;

use strict;
use Carp;
use Config::General;
use Log::Log4perl;

use CIHM::Meta::REST::dipstaging;
use CIHM::Meta::ImportOCR::Worker;

use Coro::Semaphore;
use AnyEvent::Fork;
use AnyEvent::Fork::Pool;

use Try::Tiny;
use JSON;
use Data::Dumper;

=head1 NAME

CIHM::Meta::ImportOCR - Extract OCR related data/metadata from CIHM repository and add to 2020+ design access platform

=cut

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::ImportOCR->new() not a hash\n";
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

    my %confighash =
      new Config::General( -ConfigFile => $args->{configpath}, )->getall;

    # Undefined if no <internalmeta> config block
    if ( exists $confighash{dipstaging} ) {
        $self->{dipstaging} = new CIHM::Meta::REST::dipstaging(
            server      => $confighash{dipstaging}{server},
            database    => $confighash{dipstaging}{database},
            type        => 'application/json',
            conf        => $args->{configpath},
            clientattrs => { timeout => 3600 },
        );
    }
    else {
        croak "Missing <dipstaging> configuration block in config\n";
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

sub dipstaging {
    my $self = shift;
    return $self->{dipstaging};
}

sub importOCR {
    my ($self) = @_;

    $self->log->info( "ImportOCR: conf="
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
      AnyEvent::Fork->new->require("CIHM::Meta::ImportOCR::Worker")
      ->AnyEvent::Fork::Pool::run(
        "CIHM::Meta::ImportOCR::Worker::importocr",
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
            $self->configpath,
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

    $self->dipstaging->type("application/json");
    my $url = "/"
      . $self->dipstaging->database
      . "/_design/access/_view/ocrQueue?reduce=false&limit="
      . $self->limit
      . $skipparam
      . $descparam;
    my $res = $self->dipstaging->get( $url, {},
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
        warn "_view/ocrQueue GET return code: " . $res->code . "\n";
    }
    return;
}

1;
