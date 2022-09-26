package CIHM::Meta::Hammer2::Worker;

use strict;
use Carp;
use AnyEvent;
use Try::Tiny;
use JSON;
use Log::Log4perl;
use URI::Escape;
use CIHM::Swift::Client;
use CIHM::Meta::REST::cantaloupe;
use CIHM::Meta::Hammer2::Process;

{

    package restclient;

    use Moo;
    with 'Role::REST::Client';
}

our $self;

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

    $self->{cosearch2db} = restclient->new(
        server      => $args->{couchdb_cosearch2},
        type        => 'application/json',
        clientattrs => { timeout => 3600 }
    );
    $self->cosearch2db->set_persistent_header( 'Accept' => 'application/json' );
    $test = $self->cosearch2db->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to cosearch2 Couchdb database: "
          . $args->{couchdb_cosearch2}
          . " Check configuration\n";
    }

    $self->{copresentation2db} = restclient->new(
        server      => $args->{couchdb_copresentation2},
        type        => 'application/json',
        clientattrs => { timeout => 3600 }
    );
    $self->copresentation2db->set_persistent_header(
        'Accept' => 'application/json' );
    $test = $self->copresentation2db->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to copresentation2 Couchdb database: "
          . $args->{couchdb_copresentation2}
          . " Check configuration\n";
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
        die "Problem connecting to Swift container="
          . $self->access_metadata
          . ". Check configuration\n";
    }

}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}

sub log {
    my $self = shift;
    return $self->{logger};
}

sub swift {
    my $self = shift;
    return $self->{swift};
}

sub access_metadata {
    my $self = shift;
    return $self->args->{access_metadata};
}

sub cantaloupe {
    my $self = shift;
    return $self->{cantaloupe};
}

sub accessdb {
    my $self = shift;
    return $self->{accessdb};
}

sub canvasdb {
    my $self = shift;
    return $self->{canvasdb};
}

sub cosearch2db {
    my $self = shift;
    return $self->{cosearch2db};
}

sub copresentation2db {
    my $self = shift;
    return $self->{copresentation2db};
}

sub warnings {
    my $warning = shift;
    our $self;
    my $noid = "unknown";

    # Strip wide characters before  trying to log
    ( my $stripped = $warning ) =~ s/[^\x00-\x7f]//g;

    if ($self) {
        $self->{message} .= $warning;
        $noid = $self->{noid};
        $self->log->warn( $noid . ": $stripped" );
    }
    else {
        say STDERR "$warning\n";
    }
}

sub swing {
    my ( $noid, $jsonargs ) = @_;
    our $self;

    # Capture warnings
    local $SIG{__WARN__} = sub { &warnings };

    my $args = decode_json $jsonargs;

    if ( !$self ) {
        initworker($args);
    }

    # Debugging: http://lists.schmorp.de/pipermail/anyevent/2017q2/000870.html
    #  $SIG{CHLD} = 'IGNORE';

    $self->{noid}    = $noid;
    $self->{message} = '';

    AE::log debug => "$noid Before ($$)";

    my $status;

    # Handle and record any errors
    try {
        $status = JSON::true;
        new CIHM::Meta::Hammer2::Process(
            {
                noid               => $noid,
                log                => $self->log,
                swift              => $self->swift,
                preservation_files => $self->args->{preservation_files},
                access_metadata    => $self->args->{access_metadata},
                access_files       => $self->args->{access_files},
                cantaloupe         => $self->cantaloupe,
                accessdb           => $self->accessdb,
                canvasdb           => $self->canvasdb,
                cosearch2db        => $self->cosearch2db,
                copresentation2db  => $self->copresentation2db,
            }
        )->process;
    }
    catch {
        $status = JSON::false;
        $self->log->error("$noid: $_");
        $self->{message} .= "Caught: " . $_;
    };
    $self->postResults( $noid, $status, $self->{message} );

    AE::log debug => "$noid After ($$)";

    return ($noid);
}

sub postResults {
    my ( $self, $noid, $status, $message ) = @_;

    $self->accessdb->type("application/json");
    my $uri =
      "/_design/metadatabus/_update/hammerResult/" . uri_escape_utf8($noid);

    my $res = $self->accessdb->post(
        $uri,
        {
            "succeeded" => $status,
            "message"   => $message,
        },
        { deserializer => 'application/json' }
    );

    if ( $res->code != 201 && $res->code != 200 ) {
        warn $uri . " POST return code: " . $res->code . "\n";
    }
}

1;
