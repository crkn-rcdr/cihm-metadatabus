package CIHM::Meta::Smelter::Worker;

use strict;
use Carp;
use AnyEvent;
use Try::Tiny;
use JSON;
use Log::Log4perl;
use URI::Escape;
use CIHM::Swift::Client;
use CIHM::Meta::REST::cantaloupe;
use CIHM::Meta::Smelter::Process;

our $self;

{

    package restclient;

    use Moo;
    with 'Role::REST::Client';
}

sub initworker {
    my $args = shift;
    our $self;

    $self = bless {};

    Log::Log4perl->init_once("/etc/canadiana/tdr/log4perl.conf");
    $self->{logger} = Log::Log4perl::get_logger("CIHM::TDR");

    $self->{args} = $args;

    $self->{accessdb} = new restclient(
        server      => $args->{couchdb_access},
        type        => 'application/json',
        clientattrs => { timeout => 3600 },
    );
    $self->accessdb->set_persistent_header( 'Accept' => 'application/json' );
    my $test = $self->accessdb->head("/");
    if ( !$test || $test->code != 200 ) {
        die
"Problem connecting to `access` Couchdb database. Check configuration\n";
    }

    $self->{canvasdb} = new restclient(
        server      => $args->{couchdb_canvas},
        type        => 'application/json',
        clientattrs => { timeout => 3600 },
    );
    $self->canvasdb->set_persistent_header( 'Accept' => 'application/json' );
    $test = $self->canvasdb->head("/");
    if ( !$test || $test->code != 200 ) {
        die
"Problem connecting to `canvas` Couchdb database. Check configuration\n";
    }

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

    $self->{cantaloupe} = new CIHM::Meta::REST::cantaloupe(
        url         => $args->{iiif_image_server},
        jwt_secret  => $args->{iiif_image_password},
        jwt_payload => '{"uids":[".*"]}',
        type        => 'application/json',
        clientattrs => { timeout => 3600 },
    );
    $test = $self->cantaloupe->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to Cantaloupe Server. Check configuration\n";
    }

    my %swiftopt = ( furl_options => { timeout => 3600 } );
    foreach ( "server", "user", "password", "account" ) {
        if ( exists $args->{ "swift_" . $_ } ) {
            $swiftopt{$_} = $args->{ "swift_" . $_ };
        }
    }
    $self->{swift} = CIHM::Swift::Client->new(%swiftopt);

    $test = $self->swift->container_head( $self->access_metadata );
    if ( !$test || $test->code != 204 ) {
        die "Problem connecting to Swift container. Check configuration\n";
    }

    $self->{noidsrv} = new restclient(
        server      => $args->{noid_server},
        type        => 'application/json',
        clientattrs => { timeout => 3600 }
    );
    $self->noidsrv->set_persistent_header( 'Accept' => 'application/json' );
    $test = $self->noidsrv->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to Noid server. Check configuration\n";
    }

}

# Simple accessors for now -- Do I want to Moo?
sub log {
    my $self = shift;
    return $self->{logger};
}

sub args {
    my $self = shift;
    return $self->{args};
}

sub access_metadata {
    my $self = shift;
    return $self->args->{access_metadata};
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
    my ( $aip, $jsonargs ) = @_;
    our $self;

    # Capture warnings
    local $SIG{__WARN__} = sub { &warnings };

    my $args = decode_json $jsonargs;

    if ( !$self ) {
        initworker($args);
    }

    $self->{aip}     = $aip;
    $self->{message} = '';

    my $status;

    # Handle and record any errors
    try {
        $status = 1;
        new CIHM::Meta::Smelter::Process(
            {
                aip          => $aip,
                args         => $self->args,
                log          => $self->log,
                canvasdb     => $self->canvasdb,
                dipstagingdb => $self->dipstagingdb,
                accessdb     => $self->accessdb,
                cantaloupe   => $self->cantaloupe,
                swift        => $self->swift,
                noidsrv      => $self->noidsrv
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
    my ( $self, $aip, $succeeded, $message ) = @_;

    my $url = "/_design/access/_update/updateSmelt/" . uri_escape($aip);

    $self->dipstagingdb->type("application/json");
    my $res = $self->dipstagingdb->post(
        $url,
        {
            succeeded => $succeeded ? JSON::true : JSON::false,
            message => $message
        },
        { deserializer => 'application/json' }
    );

    if ( $res->code != 201 && $res->code != 200 ) {
        warn "$url POST return code: " . $res->code . "\n";
    }
}

1;
