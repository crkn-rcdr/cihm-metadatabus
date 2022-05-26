package CIHM::Meta::RepoSync;

use strict;
use Carp;
use Config::General;
use Log::Log4perl;

use CIHM::TDR::REST::tdrepo;
use CIHM::Swift::Client;
use CIHM::Meta::REST::wipmeta;
use CIHM::Meta::REST::internalmeta;
use CIHM::Meta::REST::dipstaging;
use CIHM::Meta::REST::repoanalysis;
use JSON;
use Date::Parse;
use DateTime;

=head1 NAME

CIHM::Meta::RepoSync - Synchronize specific data between 
"tdrepo" and "internalmeta", "wipmeta" and "dipstaging" databases

=head1 SYNOPSIS

    my $reposync = CIHM::Meta::RepoSync->new($args);
      where $args is a hash of arguments.

      $args->{configpath} is as used by Config::General

=cut

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::RepoSync->new() not a hash\n";
    }
    $self->{args} = $args;

    Log::Log4perl->init_once("/etc/canadiana/tdr/log4perl.conf");
    $self->{logger} = Log::Log4perl::get_logger("CIHM::TDR");

    my %confighash =
      new Config::General( -ConfigFile => $args->{configpath}, )->getall;

    # Undefined if no <tdrepo> config block
    if ( exists $confighash{tdrepo} ) {
        $self->{tdrepo} = new CIHM::TDR::REST::tdrepo(
            server   => $confighash{tdrepo}{server},
            database => $confighash{tdrepo}{database},
            repository => "",                 # Blank repository needs to be set
            type       => 'application/json',
            conf       => $self->configpath,
            clientattrs => { timeout => 3600 },
        );
    }
    else {
        croak "Missing <tdrepo> configuration block in config\n";
    }

    # Undefined if no <internalmeta> config block
    if ( exists $confighash{internalmeta} ) {
        $self->{internalmeta} = new CIHM::Meta::REST::internalmeta(
            server      => $confighash{internalmeta}{server},
            database    => $confighash{internalmeta}{database},
            type        => 'application/json',
            conf        => $self->configpath,
            clientattrs => { timeout => 3600 },
        );
    }

    # Undefined if no <wipmeta> config block
    if ( exists $confighash{wipmeta} ) {
        $self->{wipmeta} = new CIHM::Meta::REST::wipmeta(
            server      => $confighash{wipmeta}{server},
            database    => $confighash{wipmeta}{database},
            type        => 'application/json',
            conf        => $self->configpath,
            clientattrs => { timeout => 3600 },
        );
    }

    # Undefined if no <dipstaging> config block
    if ( exists $confighash{dipstaging} ) {
        $self->{dipstaging} = new CIHM::Meta::REST::dipstaging(
            server      => $confighash{dipstaging}{server},
            database    => $confighash{dipstaging}{database},
            type        => 'application/json',
            conf        => $self->configpath,
            clientattrs => { timeout => 3600 },
        );
    }

    # Undefined if no <repoanalysis> config block
    if ( exists $confighash{repoanalysis} ) {
        $self->{repoanalysis} = new CIHM::Meta::REST::repoanalysis(
            server      => $confighash{repoanalysis}{server},
            database    => $confighash{repoanalysis}{database},
            type        => 'application/json',
            conf        => $self->configpath,
            clientattrs => { timeout => 3600 },
        );
    }
    $self->{dbs}     = [];
    $self->{dbnames} = [];
    if ( $self->dipstaging ) {
        push @{ $self->dbs },     $self->dipstaging;
        push @{ $self->dbnames }, "dipstaging";
    }
    if ( $self->internalmeta ) {
        push @{ $self->dbs },     $self->internalmeta;
        push @{ $self->dbnames }, "internalmeta";
    }
    if ( $self->wipmeta ) {
        push @{ $self->dbs },     $self->wipmeta;
        push @{ $self->dbnames }, "wipmeta";
    }
    if ( $self->repoanalysis ) {
        push @{ $self->dbs },     $self->repoanalysis;
        push @{ $self->dbnames }, "repoanalysis";
    }
    if ( !@{ $self->dbs } ) {
        croak "No output databases defined\n";
    }

    # Undefined if no <swift> config block
    if ( exists $confighash{swift} ) {
        my %swiftopt = ( furl_options => { timeout => 120 } );
        foreach ( "server", "user", "password", "account", "furl_options" ) {
            if ( exists $confighash{swift}{$_} ) {
                $swiftopt{$_} = $confighash{swift}{$_};
            }
        }
        $self->{swift}       = CIHM::Swift::Client->new(%swiftopt);
        $self->{swiftconfig} = $confighash{swift};
    }
    else {
        croak "No <swift> configuration block in " . $self->configpath . "\n";
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

sub log {
    my $self = shift;
    return $self->{logger};
}

sub tdrepo {
    my $self = shift;
    return $self->{tdrepo};
}

sub internalmeta {
    my $self = shift;
    return $self->{internalmeta};
}

sub wipmeta {
    my $self = shift;
    return $self->{wipmeta};
}

sub dipstaging {
    my $self = shift;
    return $self->{dipstaging};
}

sub repoanalysis {
    my $self = shift;
    return $self->{repoanalysis};
}

sub swift {
    my $self = shift;
    return $self->{swift};
}

sub swiftconfig {
    my $self = shift;
    return $self->{swiftconfig};
}

sub repository {
    my $self = shift;
    return $self->swiftconfig->{repository};
}

sub container {
    my $self = shift;
    return $self->swiftconfig->{container};
}

sub dbs {
    my $self = shift;
    return $self->{dbs};
}

sub dbnames {
    my $self = shift;
    return $self->{dbnames};
}

sub since {
    my $self = shift;
    return $self->{args}->{since};
}

sub localdocument {
    my $self = shift;
    return $self->{args}->{localdocument};
}

sub reposync {
    my ($self) = @_;

    $self->log->info( "Synchronizing \"tdrepo\" data to: " . join ',',
        @{ $self->dbnames } );

    my $newestaips = $self->tdrepo->get_newestaip(
        {
            date          => $self->since,
            localdocument => $self->localdocument
        }
    );

    if ( !$newestaips || !scalar(@$newestaips) ) {

        # print STDERR "Nothing new....";
        return;
    }

    # Loop through all the changed AIPs, and update all the DBs
    foreach my $thisaip (@$newestaips) {
        my $aip          = $thisaip->{key};
        my $manifestdate = $thisaip->{value}[0];
        my @repos        = @{ $thisaip->{value}[1] };
        my %repo         = map { $_ => 1 } @repos;

        my $updatedoc = {
            "repos"        => encode_json( \@repos ),
            "manifestdate" => $manifestdate
        };
        foreach my $db ( @{ $self->dbs } ) {
            my $r = $db->update_basic_full( $aip, $updatedoc );
            if ( $repo{'swift'} && exists $r->{METSmatch} && !$r->{METSmatch} )
            {
                my $mets = $self->getMETS( $aip, $manifestdate );
                if ($mets) {
                    $updatedoc->{METS} = encode_json($mets);
                    $db->update_basic_full( $aip, $updatedoc );
                }
            }
        }
    }
}

sub getMETS {
    my ( $self, $aip, $manifestdate ) = @_;

    my @mets;

    my $file = $aip . "/manifest-md5.txt";
    my $r = $self->swift->object_get( $self->container, $file );
    if ( $r->code == 200 ) {
        my $swiftmanifestdate = $r->object_meta_header('File-Modified');
        if ( $swiftmanifestdate eq $manifestdate ) {
            my @metadata = grep {
/\sdata\/(sip\/data|revisions\/[^\/\.]*\/data|revisions\/[^\/]*\.partial)\/metadata\.xml$/
            } split( /\n/gm, $r->content );
            my @mets;
            my %metshash;
            foreach my $md (@metadata) {
                my ( $md5, $path ) = split( ' ', $md );
                $metshash{$path} = $md5;
            }
            foreach my $path ( sort keys %metshash ) {
                push @mets, { md5 => $metshash{$path}, path => $path };
            }
            $self->log->info(
                "Retrieved " . scalar(@mets) . " manifests for $aip" );
            return \@mets;
        }
        else {
            $self->log->error("$swiftmanifestdate from Swift != $manifestdate");
            return;
        }
    }
    elsif ( $r->code == 404 ) {
        $self->log->info("Not yet found: $file");
        return;
    }
    else {
        $self->log->error( "Accessing Swift object $file returned: "
              . $r->code . " : "
              . $r->message );
        return;
    }
}

1;
