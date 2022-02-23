package CIHM::Meta::CopyCanvasImage::Worker;

use strict;
use Carp;
use AnyEvent;
use Try::Tiny;
use JSON;
use Config::General;
use Log::Log4perl;

use CIHM::Swift::Client;
use CIHM::Meta::REST::canvas;
use CIHM::Meta::REST::access;
use CIHM::Meta::CopyCanvasImage::Process;

our $self;

{

    package restclient;

    use Moo;
    with 'Role::REST::Client';
}

sub initworker {
    my $configpath = shift;
    our $self;

    AE::log debug => "Initworker ($$): $configpath";

    $self = bless {};

    Log::Log4perl->init_once("/etc/canadiana/tdr/log4perl.conf");
    $self->{logger} = Log::Log4perl::get_logger("CIHM::TDR");

    my %confighash = new Config::General( -ConfigFile => $configpath, )->getall;

    # Undefined if no <canvas> config block
    if ( exists $confighash{canvas} ) {
        $self->{canvasdb} = new CIHM::Meta::REST::canvas(
            server      => $confighash{canvas}{server},
            database    => $confighash{canvas}{database},
            type        => 'application/json',
            clientattrs => { timeout => 3600 },
        );
    }
    else {
        croak "Missing <canvas> configuration block in config\n";
    }

    # Undefined if no <access> config block
    if ( exists $confighash{access} ) {
        $self->{accessdb} = new CIHM::Meta::REST::access(
            server      => $confighash{access}{server},
            database    => $confighash{access}{database},
            type        => 'application/json',
            clientattrs => { timeout => 3600 },
        );
    }
    else {
        croak "Missing <access> configuration block in config\n";
    }

    # Undefined if no <swift> config block
    if ( exists $confighash{swift} ) {
        my %swiftopt = ( furl_options => { timeout => 120 } );
        foreach ( "server", "user", "password", "account", "furl_options" ) {
            if ( exists $confighash{swift}{$_} ) {
                $swiftopt{$_} = $confighash{swift}{$_};
            }
        }
        $self->{swift}              = CIHM::Swift::Client->new(%swiftopt);
        $self->{preservation_files} = $confighash{swift}{container};
        $self->{access_metadata}    = $confighash{swift}{access_metadata};
        $self->{access_files}       = $confighash{swift}{access_files};
    }
    else {
        croak "No <swift> configuration block in " . $self->configpath . "\n";
    }

}

# Simple accessors for now -- Do I want to Moo?
sub log {
    my $self = shift;
    return $self->{logger};
}

sub canvasdb {
    my $self = shift;
    return $self->{canvasdb};
}

sub accessdb {
    my $self = shift;
    return $self->{accessdb};
}

sub swift {
    my $self = shift;
    return $self->{swift};
}

sub warnings {
    my $warning = shift;
    our $self;
    my $canvasid = "unknown";

    # Strip wide characters before  trying to log
    ( my $stripped = $warning ) =~ s/[^\x00-\x7f]//g;

    if ($self) {
        $self->{message} .= $warning;
        $canvasid = $self->{canvasid};
        $self->log->warn( $canvasid . ": $stripped" );
    }
    else {
        say STDERR "$warning\n";
    }
}

sub copy {
    my ( $canvasid, $configpath ) = @_;
    our $self;

    # Capture warnings
    local $SIG{__WARN__} = sub { &warnings };

    if ( !$self ) {
        initworker($configpath);
    }

    $self->{canvasid} = $canvasid;
    $self->{message}  = '';

    AE::log debug => "$canvasid Before ($$)";

    my $status;

    # Handle and record any errors
    try {
        $status = 1;
        new CIHM::Meta::CopyCanvasImage::Process(
            {
                canvasid                => $canvasid,
                configpath         => $configpath,
                log                => $self->log,
                canvasdb           => $self->canvasdb,
                accessdb           => $self->accessdb,
                swift              => $self->swift,
                preservation_files => $self->{preservation_files},
                access_files       => $self->{access_files},
            }
        )->process;
    }
    catch {
        $status = 0;
        $self->log->error("$canvasid: $_");
        $self->{message} .= "Caught: " . $_;

    };

    AE::log debug => "$canvasid After ($$)";

    if ($status) {
        return ($canvasid);
    } else {
        # If there was an error, don't try to do the problem ID over again.
        return;
    }
}

1;
