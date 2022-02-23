package CIHM::Meta::Press2;

use strict;
use Carp;
use Config::General;
use Log::Log4perl;

use CIHM::Meta::REST::internalmeta;
use CIHM::Meta::REST::extrameta;
use CIHM::Meta::REST::cosearch;
use CIHM::Meta::REST::copresentation;
use CIHM::Meta::Press2::Process;
use Try::Tiny;
use JSON;

=head1 NAME

CIHM::Meta::Press2 - Build cosearch2 and copresentation2 documents from
normalized data in "internalmeta2" database.

Makes use of a CouchDB _view which emits based on checking if metadata has
been modified since the most recent date this tool has processed a document.

=head1 SYNOPSIS

    my $press = CIHM::Meta::Press2->new($args);
      where $args is a hash of arguments.

      $args->{configpath} is as used by Config::General

=cut

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::Press2->new() not a hash\n";
    }
    $self->{args} = $args;

    Log::Log4perl->init_once("/etc/canadiana/tdr/log4perl.conf");
    $self->{logger} = Log::Log4perl::get_logger("CIHM::TDR");

    my %confighash =
      new Config::General( -ConfigFile => $args->{configpath}, )->getall;

    $self->{dbconf} = {};

    # Undefined if no <internalmeta> config block
    if ( exists $confighash{internalmeta2} ) {
        $self->{internalmeta2} = new CIHM::Meta::REST::internalmeta(
            server      => $confighash{internalmeta2}{server},
            database    => $confighash{internalmeta2}{database},
            type        => 'application/json',
            conf        => $self->configpath,
            clientattrs => { timeout => 3600 }
        );
    }
    else {
        croak "Missing <internalmeta> configuration block in config\n";
    }

    # Undefined if no <extrameta> config block
    if ( exists $confighash{extrameta} ) {
        $self->{extrameta} = new CIHM::Meta::REST::extrameta(
            server      => $confighash{extrameta}{server},
            database    => $confighash{extrameta}{database},
            type        => 'application/json',
            conf        => $self->configpath,
            clientattrs => { timeout => 3600 }
        );
    }
    else {
        croak "Missing <extrameta> configuration block in config\n";
    }

    # Undefined if no <cosearch> config block
    if ( exists $confighash{cosearch2} ) {
        $self->{cosearch2} = new CIHM::Meta::REST::cosearch(
            server      => $confighash{cosearch2}{server},
            database    => $confighash{cosearch2}{database},
            type        => 'application/json',
            conf        => $self->configpath,
            clientattrs => { timeout => 3600 }
        );
    }
    else {
        croak "Missing <cosearch2> configuration block in config\n";
    }

    # Undefined if no <copresentation> config block
    if ( exists $confighash{copresentation2} ) {
        $self->{copresentation2} = new CIHM::Meta::REST::copresentation(
            server      => $confighash{copresentation2}{server},
            database    => $confighash{copresentation2}{database},
            type        => 'application/json',
            conf        => $self->configpath,
            clientattrs => { timeout => 3600 }
        );
    }
    else {
        croak "Missing <copresentation2> configuration block in config\n";
    }

    $self->{argsaip}        = delete $args->{aip};
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

sub configpath {
    my $self = shift;
    return $self->{args}->{configpath};
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

sub extrameta {
    my $self = shift;
    return $self->{extrameta};
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

    $self->log->info( "Press time: conf="
          . $self->configpath
          . " skip="
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
                    extrameta       => $self->extrameta,
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
    my $url = "/"
      . $self->internalmeta2->database
      . "/_design/tdr/_view/pressq?reduce=false&limit=1"
      . $extraparam;
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

    $self->internalmeta2->update_basic(
        $aip,
        {
            "press" => encode_json(
                {
                    "status"  => $status,
                    "message" => $message
                }
            )
        }
    );
}

1;
