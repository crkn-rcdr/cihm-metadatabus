package CIHM::Meta::Dmdtask::Worker;

use strict;
use Carp;
use AnyEvent;
use Try::Tiny;
use JSON;
use Config::General;
use Log::Log4perl;

use CIHM::Swift::Client;
use CIHM::Meta::REST::dmdtask;
use CIHM::Meta::Dmdtask::Process;
use Data::Dumper;

our $self;

sub initworker {
    my $configpath = shift;
    our $self;

    AE::log debug => "Initworker ($$): $configpath";

    $self = bless {};

    Log::Log4perl->init_once("/etc/canadiana/tdr/log4perl.conf");
    $self->{logger} = Log::Log4perl::get_logger("CIHM::TDR");

    my %confighash = new Config::General( -ConfigFile => $configpath, )->getall;

    # Undefined if no <dmdtask> config block
    if ( exists $confighash{dmdtask} ) {
        $self->{dmdtaskdb} = new CIHM::Meta::REST::dmdtask(
            server      => $confighash{dmdtask}{server},
            database    => $confighash{dmdtask}{database},
            type        => 'application/json',
            conf        => $configpath,
            clientattrs => { timeout => 3600 },
        );
    }
    else {
        croak "Missing <dmdtask> configuration block in config\n";
    }

}

# Simple accessors for now -- Do I want to Moo?
sub log {
    my $self = shift;
    return $self->{logger};
}

sub dmdtaskdb {
    my $self = shift;
    return $self->{dmdtaskdb};
}

sub warnings {
    my $warning = shift;
    our $self;
    my $taskid = "unknown";

    # Strip wide characters before  trying to log
    ( my $stripped = $warning ) =~ s/[^\x00-\x7f]//g;

    if ($self) {
        $self->{message} .= $warning;
        $taskid = $self->{taskid};
        $self->log->warn( $taskid . ": $stripped" );
    }
    else {
        say STDERR "$warning\n";
    }
}

sub task {
    my ( $taskid, $configpath ) = @_;
    our $self;

    if ( !$self ) {
        initworker($configpath);
    }

    $self->{taskid}  = $taskid;
    $self->{message} = '';

    # Capture warnings
    local $SIG{__WARN__} = sub { &warnings };

    $self->log->info("Processing $taskid");

    my $status;
    my $results;

    # Handle and record any errors
    try {
        $status  = JSON::true;
        $results = new CIHM::Meta::Dmdtask::Process(
            {
                taskid    => $taskid,
                log       => $self->log,
                dmdtaskdb => $self->dmdtaskdb,
            }
        )->process;
    }
    catch {
        $status = JSON::false;
        $self->log->error("$taskid: $_");
        $self->{message} .= "Caught: " . $_;
    };
    $self->postResults( $taskid, $status, $self->{message}, $results );

    return ($taskid);
}

sub postResults {
    my ( $self, $taskid, $status, $message, $results ) = @_;

    my $res = $self->dmdtaskdb->processupdate(
        $taskid,
        {
            succeeded => $status,
            message   => $message,
            items     => $results
        }
    );
    if ($res) {
        if ( exists $res->{message} ) {
            $self->log->info( $taskid . ": " . $res->{message} );
        }
        if ( exists $res->{error} ) {
            $self->log->error( $taskid . ": " . $res->{error} );
        }
    }
}

1;
