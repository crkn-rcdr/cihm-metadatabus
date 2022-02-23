package CIHM::Meta::Press;

use strict;
use Carp;
use Config::General;
use Log::Log4perl;

use CIHM::Meta::REST::internalmeta;
use CIHM::Meta::REST::extrameta;
use CIHM::Meta::REST::cosearch;
use CIHM::Meta::REST::copresentation;
use CIHM::Meta::Press::Process;
use Try::Tiny;
use JSON;

=head1 NAME

CIHM::Meta::Press - Build cosearch and copresentation documents from
normalized data in "internalmeta" database.

Makes use of a CouchDB _view which emits based on checking if metadata has
been modified since the most recent date this tool has processed a document.

=head1 SYNOPSIS

    my $press = CIHM::Meta::Press->new($args);
      where $args is a hash of arguments.

      $args->{configpath} is as used by Config::General

=cut

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::Press->new() not a hash\n";
    }
    $self->{args} = $args;

    Log::Log4perl->init_once("/etc/canadiana/tdr/log4perl.conf");
    $self->{logger} = Log::Log4perl::get_logger("CIHM::TDR");

    my %confighash =
      new Config::General( -ConfigFile => $args->{configpath}, )->getall;

    $self->{dbconf} = {};

    # Undefined if no <internalmeta> config block
    if ( exists $confighash{internalmeta} ) {
        $self->{internalmeta} = new CIHM::Meta::REST::internalmeta(
            server      => $confighash{internalmeta}{server},
            database    => $confighash{internalmeta}{database},
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
    if ( exists $confighash{cosearch} ) {
        $self->{cosearch} = new CIHM::Meta::REST::cosearch(
            server      => $confighash{cosearch}{server},
            database    => $confighash{cosearch}{database},
            type        => 'application/json',
            conf        => $self->configpath,
            clientattrs => { timeout => 3600 }
        );
    }
    else {
        croak "Missing <cosearch> configuration block in config\n";
    }

    # Undefined if no <copresentation> config block
    if ( exists $confighash{copresentation} ) {
        $self->{copresentation} = new CIHM::Meta::REST::copresentation(
            server      => $confighash{copresentation}{server},
            database    => $confighash{copresentation}{database},
            type        => 'application/json',
            conf        => $self->configpath,
            clientattrs => { timeout => 3600 }
        );
    }
    else {
        croak "Missing <copresentation> configuration block in config\n";
    }
    return $self;
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
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

sub internalmeta {
    my $self = shift;
    return $self->{internalmeta};
}

sub extrameta {
    my $self = shift;
    return $self->{extrameta};
}

sub cosearch {
    my $self = shift;
    return $self->{cosearch};
}

sub copresentation {
    my $self = shift;
    return $self->{copresentation};
}

sub Press {
    my ($self) = @_;

    $self->log->info( "Press time: conf="
          . $self->configpath
          . " skip="
          . $self->skip
          . " descending="
          . ( $self->descending  ? "true" : "false"));

    # Scope of variables for warnings() requires these be in object,
    # and initialized with each new AIP being processed.
    $self->{message} = '';
    $self->{aip}     = 'none';

    # Capture warnings
    sub warnings {
        my $warning = shift;
        $self->log->warn( $self->{aip} . ": $warning" );
        $self->{message} .= $warning . "\n";
    }
    local $SIG{__WARN__} = sub { &warnings };

    while (1) {
        my ( $aip, $pressme ) = $self->getNextAIP;
        last if !$aip;

        #    my ($aip,$pressme) = ("oocihm.8_06490_123",1); {
        #    my ($aip,$pressme) = ("oocihm.8_06490",1); {

        $self->log->info("Processing $aip");

        my $status;

        # Handle and record any errors
        try {
            # Initialize variables used by warnings() for each AIP
            $self->{message} = '';
            $self->{aip}     = $aip;

            # Initialize status
            $status = 1;
            new CIHM::Meta::Press::Process(
                {
                    aip            => $aip,
                    log            => $self->log,
                    internalmeta   => $self->internalmeta,
                    extrameta      => $self->extrameta,
                    cosearch       => $self->cosearch,
                    copresentation => $self->copresentation,
                    pressme        => $pressme
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

    my $extraparam = '';
    if ( $self->skip ) {
        $extraparam = "&skip=" . $self->skip;
    }
    if ( $self->descending ) {
        $extraparam = '&descending=true';
    }

    $self->internalmeta->type("application/json");
    my $url = "/"
      . $self->internalmeta->database
      . "/_design/tdr/_view/pressq?reduce=false&limit=1"
      . $extraparam;
    my $res = $self->internalmeta->get( $url, {},
        { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        if ( exists $res->data->{rows} ) {
            return ( $res->data->{rows}[0]->{id},
                $res->data->{rows}[0]->{value} );
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

    $self->internalmeta->update_basic(
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
