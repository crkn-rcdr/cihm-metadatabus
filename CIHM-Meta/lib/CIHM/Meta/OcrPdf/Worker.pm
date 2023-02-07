package CIHM::Meta::OcrPdf::Worker;

use strict;
use Carp;
use AnyEvent;
use Try::Tiny;
use JSON;
use Log::Log4perl;
use URI::Escape;
use CIHM::Swift::Client;
use CIHM::Meta::OcrPdf::Process;
use Data::Dumper;

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

sub accessdb {
    my $self = shift;
    return $self->{accessdb};
}

sub canvasdb {
    my $self = shift;
    return $self->{canvasdb};
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

sub createpdf {
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
        new CIHM::Meta::OcrPdf::Process(
            {
                noid   => $noid,
                worker => $self
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

# Called from CIHM::Meta::OcrPdf::Process if a new ocrPdf has been created and stored.
sub setocrpdf {
    my ( $self, $ocrpdf ) = @_;

    $self->{ocrpdf} = $ocrpdf;

}

sub postResults {
    my ( $self, $noid, $status, $message ) = @_;

    $self->accessdb->type("application/json");
    my $uri =
      "/_design/metadatabus/_update/updateOCRPDF/" . uri_escape_utf8($noid);

    my $res = $self->accessdb->post(
        $uri,
        {
            "succeeded" => $status,
            "message"   => $message,
            "ocrPdf"    => $self->{ocrpdf}
        },
        { deserializer => 'application/json' }
    );

    if ( $res->code != 201 && $res->code != 200 ) {
        warn $uri . " POST return code: " . $res->code . "\n";
    }
    elsif ( defined $self->{ocrpdf} ) {

        my $url =
          "/_design/access/_update/forceUpdate/" . uri_escape_utf8($noid);

        my $res =
          $self->accessdb->post( $url, {},
            { deserializer => 'application/json' } );
        if ( ( $res->code != 201 ) && ( $res->code != 409 ) ) {
            if ( defined $res->response->content ) {
                $self->log->warn( $res->response->content );
            }
            $self->log->warn( "POST $url return code: "
                  . $res->code . "("
                  . $res->error
                  . ")" );
        }
        else {
            $self->log->info("Initiating update for $noid");
        }
    }
}

1;
