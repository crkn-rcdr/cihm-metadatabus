package CIHM::Meta::ImportOCR::Worker;

use strict;
use Carp;
use AnyEvent;
use Try::Tiny;
use JSON;
use Log::Log4perl;

use CIHM::Swift::Client;
use CIHM::Meta::ImportOCR::Process;

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

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::ImportOCR->new() not a hash\n";
    }
    $self->{args} = $args;

    Log::Log4perl->init_once("/etc/canadiana/tdr/log4perl.conf");
    $self->{logger} = Log::Log4perl::get_logger("CIHM::TDR");

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
    my $test = $self->canvasdb->head("/");
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
    my $test = $self->dipstagingdb->head("/");
    if ( !$test || $test->code != 200 ) {
        die
"Problem connecting to `dipstaging` Couchdb database. Check configuration\n";
    }

    my %swiftopt = ( furl_options => { timeout => 3600 } );
    foreach ( "server", "user", "password", "account" ) {
        if ( exists $args->{ "swift_" . $_ } ) {
            $swiftopt{$_} = $args->{ "swift_" . $_ };
        }
    }
    $self->{swift} = CIHM::Swift::Client->new(%swiftopt);

    my $test = $self->swift->container_head( $self->access_metadata );
    if ( !$test || $test->code != 204 ) {
        die "Problem connecting to Swift container. Check configuration\n";
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

sub swift {
    my $self = shift;
    return $self->{swift};
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

sub importocr {
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

    my $succeeded;

    # Handle and record any errors
    try {
        $succeeded = JSON::true;
        new CIHM::Meta::ImportOCR::Process(
            {
                aip          => $aip,
                args         => $self->args,
                log          => $self->log,
                canvasdb     => $self->canvasdb,
                dipstagingdb => $self->dipstagingdb,
                accessdb     => $self->accessdb,
                swift        => $self->swift,
            }
        )->process;
    }
    catch {
        $succeeded = JSON::false;
        $self->log->error("$aip: $_");
        $self->{message} .= "Caught: " . $_;
    };
    $self->postResults( $aip, $succeeded );

    return ($aip);
}

sub postResults {
    my ( $self, $aip, $succeeded ) = @_;

    # Can't capture inside of posting results captured
    local $SIG{__WARN__} = 'DEFAULT';

    my $message = $self->{message};
    undef $message if !$message;

    my $url = "/_design/access/_update/updateOCR/$aip";

    $self->dipstagingdb->type("application/json");
    my $res = $self->dipstagingdb->post(
        $url,
        { succeeded    => $succeeded, message => $message },
        { deserializer => 'application/json' }
    );

    if ( $res->code != 201 && $res->code != 200 ) {
        warn "$url POST return code: " . $res->code . "\n";
    }
}

1;
