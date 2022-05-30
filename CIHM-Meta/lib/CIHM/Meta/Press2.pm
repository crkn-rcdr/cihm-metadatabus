package CIHM::Meta::Press2;

use strict;
use Carp;
use Config::General;
use Log::Log4perl;

use CIHM::Meta::Press2::Process;
use Try::Tiny;
use JSON;
use URI::Escape;
use Data::Dumper;

=head1 NAME

CIHM::Meta::Press2 - Build cosearch2 and copresentation2 documents from
normalized data in "internalmeta2" database.

Makes use of a CouchDB _view which emits based on checking if metadata has
been modified since the most recent date this tool has processed a document.

=head1 SYNOPSIS

    my $press = CIHM::Meta::Press2->new($args);
      where $args is a hash of arguments.

=cut

{

    package restclient;

    use Moo;
    with 'Role::REST::Client';
}

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::Press2->new() not a hash\n";
    }
    $self->{args} = $args;

    Log::Log4perl->init_once("/etc/canadiana/tdr/log4perl.conf");
    $self->{logger} = Log::Log4perl::get_logger("CIHM::TDR");

    $self->{dbconf} = {};

    $self->{internalmeta2} = restclient->new(
        server      => $args->{couchdb_internalmeta2},
        type        => 'application/json',
        clientattrs => { timeout => 3600 }
    );
    $self->internalmeta2->set_persistent_header(
        'Accept' => 'application/json' );

    my $test = $self->internalmeta2->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to internalmeta2 Couchdb database: "
          . $args->{couchdb_internalmeta2}
          . " Check configuration\n";
    }

    $self->{cosearch2} = restclient->new(
        server      => $args->{couchdb_cosearch2},
        type        => 'application/json',
        clientattrs => { timeout => 3600 }
    );
    $self->cosearch2->set_persistent_header( 'Accept' => 'application/json' );
    $test = $self->cosearch2->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to cosearch2 Couchdb database: "
          . $args->{couchdb_cosearch2}
          . " Check configuration\n";
    }

    $self->{copresentation2} = restclient->new(
        server      => $args->{couchdb_copresentation2},
        type        => 'application/json',
        clientattrs => { timeout => 3600 }
    );
    $self->copresentation2->set_persistent_header(
        'Accept' => 'application/json' );
    $test = $self->copresentation2->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to copresentation2 Couchdb database: "
          . $args->{couchdb_copresentation2}
          . " Check configuration\n";
    }

    $self->{argsaip} = $args->{aip};
    return $self;
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}

sub aip {
    my $self = shift;
    return $self->{aip};
}

sub skip {
    my $self = shift;
    return $self->{args}->{skip};
}

sub descending {
    my $self = shift;
    return $self->{args}->{descending};
}

sub log {
    my $self = shift;
    return $self->{logger};
}

sub internalmeta2 {
    my $self = shift;
    return $self->{internalmeta2};
}

sub cosearch2 {
    my $self = shift;
    return $self->{cosearch2};
}

sub copresentation2 {
    my $self = shift;
    return $self->{copresentation2};
}

sub Press {
    my ($self) = @_;

    $self->log->info( "Press skip="
          . $self->skip
          . " descending="
          . ( $self->descending ? "true" : "false" ) );

    # Scope of variables for warnings() requires these be in object,
    # and initialized with each new AIP being processed.
    $self->{message} = '';
    $self->{aip}     = 'none';

    # Capture warnings
    sub warnings {
        my $warning = shift;
        $self->log->warn( $self->aip . ": $warning" );
        $self->{message} .= $warning . "\n";
    }
    local $SIG{__WARN__} = sub { &warnings };

    while (1) {
        my ($aip) = $self->getNextAIP;
        last if !$aip;

        #my ($aip) = ("oocihm.29236"); {
        #    my ($aip) = ("oocihm.8_06490"); {

        my $status;

        # Handle and record any errors
        try {
            # Initialize variables used by warnings() for each AIP
            $self->{message} = '';
            $self->{aip}     = $aip;

            # Initialize status
            $status = 1;
            new CIHM::Meta::Press2::Process(
                {
                    aip             => $aip,
                    log             => $self->log,
                    internalmeta2   => $self->internalmeta2,
                    cosearch2       => $self->cosearch2,
                    copresentation2 => $self->copresentation2,
                }
            )->process;
        }
        catch {
            $status = 0;
            $self->log->error("$aip: $_");
            $self->{message} .= "Caught: " . $_;
        };
        $self->postResults( $aip, $status, $self->{message} );
    }
}

sub getNextAIP {
    my $self = shift;

    if ( defined $self->{argsaip} ) {
        return if $self->{argsaip} == JSON::true;
        my $aip = $self->{argsaip};
        $self->{argsaip} = JSON::true;
        return $aip;
    }

    my $extraparam = '';
    if ( $self->skip ) {
        $extraparam = "&skip=" . $self->skip;
    }
    if ( $self->descending ) {
        $extraparam = '&descending=true';
    }

    $self->internalmeta2->type("application/json");
    my $url = "/_design/tdr/_view/pressq?reduce=false&limit=1" . $extraparam;
    my $res = $self->internalmeta2->get( $url, {},
        { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        if ( exists $res->data->{rows} ) {
            return ( $res->data->{rows}[0]->{id} );
        }
        return;
    }
    else {
        die "$url GET return code: " . $res->code . "\n";
    }
    return;
}

sub postResults {
    my ( $self, $aip, $status, $message ) = @_;

    $self->internalmeta2->type("application/json");
    my $url = "/_design/tdr/_update/basic/" . uri_escape_utf8($aip);
    my $res = $self->internalmeta2->post(
        $url,
        {
            "press" => encode_json(
                {
                    "status"  => $status,
                    "message" => $message
                }
            )
        },
        { deserializer => 'application/json' }
    );

    if ( $res->code != 201 && $res->code != 200 ) {
        warn "$url POST return code: " . $res->code . "\n";
    }

}

1;
