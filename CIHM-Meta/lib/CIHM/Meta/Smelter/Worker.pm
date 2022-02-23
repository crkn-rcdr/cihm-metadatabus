package CIHM::Meta::Smelter::Worker;

use strict;
use Carp;
use AnyEvent;
use Try::Tiny;
use JSON;
use Config::General;
use Log::Log4perl;

use CIHM::Swift::Client;
use CIHM::Meta::REST::cantaloupe;
use CIHM::Meta::REST::canvas;
use CIHM::Meta::REST::dipstaging;
use CIHM::Meta::REST::access;
use CIHM::Meta::Smelter::Process;

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

    # Undefined if no <cantaloupe> config block
    if ( exists $confighash{cantaloupe} ) {
        $self->{cantaloupe} = new CIHM::Meta::REST::cantaloupe(
            url         => $confighash{cantaloupe}{url},
            jwt_secret  => $confighash{cantaloupe}{password},
            jwt_payload => '{"uids":[".*"]}',
            type        => 'application/json',
            conf        => $configpath,
            clientattrs => { timeout => 3600 },
        );
    }
    else {
        croak "Missing <cantaloupe> configuration block in config\n";
    }

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

    # Undefined if no <dipstaging> config block
    if ( exists $confighash{dipstaging} ) {
        $self->{dipstagingdb} = new CIHM::Meta::REST::dipstaging(
            server      => $confighash{dipstaging}{server},
            database    => $confighash{dipstaging}{database},
            type        => 'application/json',
            clientattrs => { timeout => 3600 },
        );
    }
    else {
        croak "Missing <dipstaging> configuration block in config\n";
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

    if ( exists $confighash{noid} ) {
        $self->{noidsrv} = new restclient(
            server      => $confighash{noid},
            type        => 'application/json',
            clientattrs => { timeout => 3600 }
        );
    }
    else {
        croak "missing noid= in configuration\n";
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

sub dipstagingdb {
    my $self = shift;
    return $self->{dipstagingdb};
}

sub accessdb {
    my $self = shift;
    return $self->{accessdb};
}

sub cantaloupe {
    my $self = shift;
    return $self->{cantaloupe};
}

sub swift {
    my $self = shift;
    return $self->{swift};
}

sub noidsrv {
    my $self = shift;
    return $self->{noidsrv};
}

sub warnings {
    my $warning = shift;
    our $self;
    my $aip = "unknown";

    # Strip wide characters before  trying to log
    ( my $stripped = $warning ) =~ s/[^\x00-\x7f]//g;

    if ($self) {
        $self->{message} .= $warning;
        $aip = $self->{aip};
        $self->log->warn( $aip . ": $stripped" );
    }
    else {
        say STDERR "$warning\n";
    }
}

sub smelt {
    my ( $aip, $configpath ) = @_;
    our $self;

    # Capture warnings
    local $SIG{__WARN__} = sub { &warnings };

    if ( !$self ) {
        initworker($configpath);
    }

    $self->{aip}     = $aip;
    $self->{message} = '';

    AE::log debug => "$aip Before ($$)";

    my $status;

    # Handle and record any errors
    try {
        $status = 1;
        new CIHM::Meta::Smelter::Process(
            {
                aip                => $aip,
                configpath         => $configpath,
                log                => $self->log,
                canvasdb           => $self->canvasdb,
                dipstagingdb       => $self->dipstagingdb,
                accessdb           => $self->accessdb,
                cantaloupe         => $self->cantaloupe,
                swift              => $self->swift,
                preservation_files => $self->{preservation_files},
                access_metadata    => $self->{access_metadata},
                access_files       => $self->{access_files},
                noidsrv            => $self->noidsrv
            }
        )->process;
    }
    catch {
        $status = 0;
        $self->log->error("$aip: $_");
        $self->{message} .= "Caught: " . $_;
    };
    $self->postResults( $aip, $status, $self->{message} );

    AE::log debug => "$aip After ($$)";

    return ($aip);
}

sub postResults {
    my ( $self, $aip, $status, $message ) = @_;

    $self->dipstagingdb->update_basic(
        $aip,
        {
            "smelt" => encode_json(
                {
                    "succeeded" => ( $status ? JSON::true : JSON::false ),
                    "message" => $message,
                }
            )
        }
    );
}

1;
