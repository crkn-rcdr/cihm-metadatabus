package CIHM::Meta::Hammer::Worker;

use strict;
use Carp;
use AnyEvent;
use Try::Tiny;
use JSON;
use Config::General;
use Log::Log4perl;

use CIHM::Swift::Client;
use CIHM::Meta::REST::cantaloupe;
use CIHM::Meta::REST::internalmeta;
use CIHM::Meta::Hammer::Process;

our $self;

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

    # Undefined if no <internalmeta> config block
    if ( exists $confighash{internalmeta} ) {
        $self->{internalmeta} = new CIHM::Meta::REST::internalmeta(
            server      => $confighash{internalmeta}{server},
            database    => $confighash{internalmeta}{database},
            type        => 'application/json',
            conf        => $configpath,
            clientattrs => { timeout => 3600 },
        );
    }
    else {
        croak "Missing <internalmeta> configuration block in config\n";
    }

    # Undefined if no <swift> config block
    if ( exists $confighash{swift} ) {
        my %swiftopt = ( furl_options => { timeout => 120 } );
        foreach ( "server", "user", "password", "account", "furl_options" ) {
            if ( exists $confighash{swift}{$_} ) {
                $swiftopt{$_} = $confighash{swift}{$_};
            }
        }
        $self->{swift}     = CIHM::Swift::Client->new(%swiftopt);
        $self->{container} = $confighash{swift}{container};
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

sub swift {
    my $self = shift;
    return $self->{swift};
}

sub container {
    my $self = shift;
    return $self->{container};
}

sub cantaloupe {
    my $self = shift;
    return $self->{cantaloupe};
}

sub internalmeta {
    my $self = shift;
    return $self->{internalmeta};
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

sub swing {
    my ( $aip, $metspath, $manifestdate, $configpath ) = @_;
    our $self;

    # Capture warnings
    local $SIG{__WARN__} = sub { &warnings };

    if ( !$self ) {
        initworker($configpath);
    }

    # Debugging: http://lists.schmorp.de/pipermail/anyevent/2017q2/000870.html
    #  $SIG{CHLD} = 'IGNORE';

    $self->{aip}     = $aip;
    $self->{message} = '';

    $self->log->info("Processing $aip");

    AE::log debug => "$aip Before ($$)";

    my $status;

    # Handle and record any errors
    try {
        $status = 1;
        new CIHM::Meta::Hammer::Process(
            {
                aip            => $aip,
                metspath       => $metspath,
                configpath     => $configpath,
                log            => $self->log,
                swift          => $self->swift,
                swiftcontainer => $self->container,
                cantaloupe     => $self->cantaloupe,
                internalmeta   => $self->internalmeta,
            }
        )->process;
    }
    catch {
        $status = 0;
        $self->log->error("$aip: $_");
        $self->{message} .= "Caught: " . $_;
    };
    $self->postResults( $aip, $status, $self->{message}, $manifestdate,
        $metspath );

    AE::log debug => "$aip After ($$)";

    return ($aip);
}

sub postResults {
    my ( $self, $aip, $status, $message, $manifestdate, $metspath ) = @_;

    $self->internalmeta->update_basic(
        $aip,
        {
            "hammer" => encode_json(
                {
                    "status"       => $status,
                    "message"      => $message,
                    "manifestdate" => $manifestdate,
                    "metspath"     => $metspath
                }
            )
        }
    );
}

1;
