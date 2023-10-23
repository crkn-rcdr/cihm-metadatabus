package CIHM::Meta::RepoSync;

use strict;
use Carp;
use Config::General;
use Log::Log4perl;

use JSON;
use Date::Parse;
use DateTime;

# use Data::Dumper;

=head1 NAME

CIHM::Meta::RepoSync - Synchronize specific data between 
"tdrepo" and "wipmeta" / "dipstaging" databases

=head1 SYNOPSIS

    my $reposync = CIHM::Meta::RepoSync->new($args);
      where $args is a hash of arguments.

      $args->{configpath} is as used by Config::General

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
        die "Argument to CIHM::Meta::RepoSync->new() not a hash\n";
    }
    $self->{args} = $args;

    Log::Log4perl->init_once("/etc/canadiana/tdr/log4perl.conf");
    $self->{logger} = Log::Log4perl::get_logger("CIHM::TDR");

    # TDREPO
    $self->{tdrepo} = restclient->new(
        server      => $args->{couchdb_tdrepo},
        type        => 'application/json',
        clientattrs => { timeout => 3600 }
    );
    $self->tdrepo->set_persistent_header( 'Accept' => 'application/json' );

    my $test = $self->tdrepo->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to tdrepo Couchdb database: "
          . $args->{couchdb_tdrepo}
          . " Check configuration\n";
    }

    # WIPMETA
    $self->{wipmeta} = restclient->new(
        server      => $args->{couchdb_wipmeta},
        type        => 'application/json',
        clientattrs => { timeout => 3600 }
    );
    $self->wipmeta->set_persistent_header( 'Accept' => 'application/json' );

    $test = $self->wipmeta->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to wipmeta Couchdb database: "
          . $args->{couchdb_wipmeta}
          . " Check configuration\n";
    }

    # DIPSTAGING
    $self->{dipstaging} = restclient->new(
        server      => $args->{couchdb_dipstaging},
        type        => 'application/json',
        clientattrs => { timeout => 3600 }
    );
    $self->dipstaging->set_persistent_header( 'Accept' => 'application/json' );

    $test = $self->dipstaging->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to dipstaging Couchdb database: "
          . $args->{couchdb_dipstaging}
          . " Check configuration\n";
    }

    return $self;
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

sub tdrepo {
    my $self = shift;
    return $self->{tdrepo};
}

sub wipmeta {
    my $self = shift;
    return $self->{wipmeta};
}

sub dipstaging {
    my $self = shift;
    return $self->{dipstaging};
}

sub since {
    my $self = shift;
    return $self->args->{since};
}

sub localdocument {
    my $self = shift;
    return $self->args->{localdocument};
}

sub reposync {
    my ($self) = @_;

    $self->log->info("Synchronizing");

    #print Dumper ( $self->args );

    my $newestaips = $self->get_newestaip(
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

=pod
        print Dumper (
            { aip => $aip, manifest => $manifestdate, repos => \@repos } );
=cut


        # This encoding makes $updatedoc variables available as form data
        $self->wipmeta->type("application/x-www-form-urlencoded");
        my $url = "/_design/tdr/_update/basic/" . $aip;

        my $res = $self->wipmeta->post(
            $url,
            {
                "repos"        => encode_json( \@repos ),
                "manifestdate" => $manifestdate
            },
            { deserializer => 'application/json' }
        );

        if ( $res->code != 201 && $res->code != 200 ) {
            warn "WIPMETA/$url POST return code: " . $res->code . "\n";
        }

        #  Post directly as JSON data (Different from other couch databases)
        $self->dipstaging->type("application/json");
        $url = "/_design/sync/_update/basic/" . $aip;
        $res = $self->dipstaging->post(
            $url,
            {
                "repos"        => \@repos,
                "manifestdate" => $manifestdate
            },
            { deserializer => 'application/json' }
        );

        if ( $res->code != 201 && $res->code != 200 ) {
            warn "DIPSTAGING/$url POST return code: " . $res->code . "\n";
        }
    }
}

sub get_newestaip {
    my ( $self, $params ) = @_;
    my ( $res, $code );
    my $restq = {};

    if (   ( !$params->{date} || $params->{date} ne 'all' )
        && ( $params->{date} || $params->{localdocument} ) )
    {
        my $recentuids = $self->get_recent_adddate_keys($params);
        if ( $recentuids && scalar(@$recentuids) ) {
            $restq->{keys} = $recentuids;
        }
        else {
            # We asked for items since a date and got none, so do nothing else
            return;
        }
    }

    # TODO: lists won't work in future versions of CouchDB
    $self->tdrepo->type("application/json");
    my $url = "/_design/tdr/_list/newtome/tdr/newestaip?group=true";
    $res = $self->tdrepo->post( $url, $restq,
        { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        if ( defined $res->data->{rows} ) {
            return $res->data->{rows};
        }
        else {
            return [];
        }
    }
    else {
        warn $self->tdrepo->server
          . "$url GET return code: "
          . $res->code . "\n";
        return;
    }
}

sub get_recent_adddate_keys {
    my ( $self, $params ) = @_;
    my ( $res, $code, $data, $recentdate, $docrev );

    my $startkey      = "[]";
    my $date          = $params->{date};
    my $localdocument = $params->{localdocument};

    # If we have a local document, grab the previous values
    if ($localdocument) {
        $self->tdrepo->type("application/json");
        $res = $self->tdrepo->get( "/_local/" . $localdocument,
            {}, { deserializer => 'application/json' } );
        if ( $res->code == 200 ) {
            $docrev   = $res->data->{"_rev"};
            $startkey = to_json( $res->data->{"latestkey"} );
        }
    }

    # A $data parameter will override the $startkey from a local document
    if ($date) {
        if ( $date =~ /(\d\d\d\d)(\-\d\d|)(\-\d\d|)(T\d\d|)/ ) {

            # Accepts an rfc3339 style date, and grabs the yyyy-mm-ddThh part
            # The month, day, and hour are optional.
            my $year  = $1;
            my $month = substr( $2 || "000", 1 );
            my $day   = substr( $3 || "000", 1 );
            my $hour  = substr( $4 || "000", 1 );
            $startkey = sprintf( "[\"%04d\",\"%02d\",\"%02d\",\"%02d\"]",
                $year, $month, $day, $hour );
        }
        elsif ( $date =~ /(\d+)\s*hours/ ) {

            # Accepts a number of hours to be subtracted from current GMT time
            my $dt = DateTime->now()->subtract( hours => $1 );
            $startkey = sprintf( "[\"%04d\",\"%02d\",\"%02d\",\"%02d\"]",
                $dt->year(), $dt->month(), $dt->day(), $dt->hour() );
        }
        else {
            warn "get_recent_adddate_keys() - invalid {date}=$date\n";

            # Didn't provide valid date, so return null
            return;
        }
    }

    # If we have a local document, grab the currently highest date key,
    # and store for next run.
    if ($localdocument) {
        $res = $self->tdrepo->get(
            "/_design/tdr/_view/adddate",
            { reduce => 'false', descending => 'true', limit => '1' },
            { deserializer => 'application/json' }
        );
        if ( $res->code == 200 ) {
            if ( $res->data->{rows} && $res->data->{rows}[0]->{key} ) {
                my $latestkey = $res->data->{rows}[0]->{key};
                pop(@$latestkey);    # pop off the (alphabetically sorted) AIP

                my $newdoc = { latestkey => $latestkey };
                if ($docrev) {
                    $newdoc->{"_rev"} = $docrev;
                }

                $self->tdrepo->type("application/json");
                $res =
                  $self->tdrepo->put( "/_local/" . $localdocument, $newdoc );
                if ( $res->code != 201 && $res->code != 200 ) {
                    warn "_local/$localdocument PUT return code: "
                      . $res->code . "\n";
                }
            }
        }
    }

    # TODO: lists won't work in future versions of CouchDB
    my $url = "/_design/tdr/_list/itemdatekey/tdr/adddate";
    $res = $self->tdrepo->get(
        $url,
        { reduce => 'false', startkey => $startkey, endkey => '[{}]' },
        { deserializer => 'application/json' }
    );
    if ( $res->code == 200 ) {

        # If the same AIP is modified multiple times within the time given,
        # it would otherwise show up multiple times..
        use List::MoreUtils qw(uniq);
        my @uniqaip = uniq( @{ $res->data } );
        return ( \@uniqaip );
    }
    else {
        warn "$url GET return code: " . $res->code . "\n";
        return;
    }
}

1;
