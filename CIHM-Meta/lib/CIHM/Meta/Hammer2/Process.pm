package CIHM::Meta::Hammer2::Process;

use 5.014;
use strict;
use XML::LibXML;
use Try::Tiny;
use JSON;
use JSON::Parse 'read_json';
use Switch;
use URI::Escape;
use CIHM::Normalise::flatten;
use CIHM::Normalise;
use List::MoreUtils qw(uniq any);
use File::Temp;
use Crypt::JWT qw(encode_jwt);
use LWP::UserAgent;
#use Data::Dumper;

=head1 NAME

CIHM::Meta::Hammer2::Process - Handles the processing of individual manifests

=head1 SYNOPSIS

    my $process = CIHM::Meta::Hammer2::Process->new($args);
      where $args is a hash of arguments.

=cut

use constant DATAPATH => '/home/tdr/data';

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::Hammer2::Process->new() not a hash\n";
    }
    $self->{args} = $args;

    if ( !$self->log ) {
        die "Log::Log4perl object parameter is mandatory\n";
    }
    if ( !$self->swift ) {
        die "swift object parameter is mandatory\n";
    }
    if ( !$self->accessdb ) {
        die "accessdb object parameter is mandatory\n";
    }
    if ( !$self->cantaloupe ) {
        die "cantaloupe object parameter is mandatory\n";
    }
    if ( !$self->noid ) {
        die "Parameter 'noid' is mandatory\n";
    }

    $self->{flatten} = CIHM::Normalise::flatten->new;

    $self->{docdata}              = {};
    $self->{pageinfo}             = {};
    $self->{attachment}           = [];
    $self->pageinfo->{count}      = 0;
    $self->pageinfo->{dimensions} = 0;

    $self->{searchdoc}  = {};
    $self->{presentdoc} = {};

    # Flag for update status (false means problem with update)
    $self->{ustatus} = 1;

    return $self;
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}

sub noid {
    my $self = shift;
    return $self->args->{noid};
}

sub log {
    my $self = shift;
    return $self->args->{log};
}

sub swift {
    my $self = shift;
    return $self->args->{swift};
}

sub access_metadata {
    my $self = shift;
    return $self->args->{access_metadata};
}

sub access_files {
    my $self = shift;
    return $self->args->{access_files};
}

sub preservation_files {
    my $self = shift;
    return $self->args->{preservation_files};
}

sub accessdb {
    my $self = shift;
    return $self->args->{accessdb};
}

sub canvasdb {
    my $self = shift;
    return $self->args->{canvasdb};
}

sub cosearch2db {
    my $self = shift;
    return $self->args->{cosearch2db};
}

sub copresentation2db {
    my $self = shift;
    return $self->args->{copresentation2db};
}

sub cantaloupe {
    my $self = shift;
    return $self->args->{cantaloupe};
}

sub docdata {
    my $self = shift;
    return $self->{docdata};
}

sub pageinfo {
    my $self = shift;
    return $self->{pageinfo};
}

sub document {
    my $self = shift;
    return $self->{document};
}

sub flatten {
    my $self = shift;
    return $self->{flatten};
}

sub attachment {
    my $self = shift;
    return $self->{attachment};
}

sub slug {
    my $self = shift;
    return if !$self->document;
    return $self->document->{slug};
}

sub searchdoc {
    my $self = shift;
    return $self->{searchdoc};
}

sub presentdoc {
    my $self = shift;
    return $self->{presentdoc};
}

sub map_noid {
    my ($slug, $noid) = @_;

    my $ark_noid_api_url = $ENV{ARK_server} . "/slug";
    my $AAD_CLIENT_SECRET = $ENV{ARK_secret};
 
    # Calculate the expiration time: current time in UTC plus 1 day
    my $expiration = DateTime->now(time_zone => 'UTC')->add(days => 1);

    # Create a JSON Web Token (JWT) with an expiration claim
    my $token = encode_jwt(
        payload => { exp => $expiration->epoch },
        key     => $AAD_CLIENT_SECRET,
        alg     => 'HS256'
    );
 
    # If no token was generated, raise an exception
    die "No access token generated." unless $token;
 
    # Prepare the request headers
    my %headers = (
        'Authorization' => "Bearer $token",
        'Content-Type'  => 'application/json',
    );
 
    # Prepare the payload
    my %payload = (
        slug   => $slug,
        ark  => $noid
    );
 
    # Initialize HTTP client
    my $ua = LWP::UserAgent->new;
 
    # Send the PUT request to the NOID map API
    my $response = $ua->put(
        $ark_noid_api_url,
        'Content-Type' => 'application/json',
        Authorization => "Bearer $token",
        Content => encode_json(\%payload),
    );
 
    # Check the response
    if ($response->is_success) {
        my $response_data = decode_json($response->decoded_content);
        return $response_data;
    } elsif ($response->code >= 400 && $response->code < 500) {
        return "Client error response:\n" . $response->decoded_content; 
    } else {
        return "Client error response:\n" . $response->decoded_content; 
    }
}

# Top method
sub process {
    my ($self) = @_;

    $self->log->info( "Starting!" );

    $self->{document} =
      $self->getAccessDocument( uri_escape_utf8( $self->noid ) );
    die "Missing Document\n" if !( $self->document );

    if ( !$self->slug ) {
        die "Missing slug\n";
    }

    $self->log->info( "Processing " . $self->noid . " (" . $self->slug . ")" );
    my $mapres = map_noid($self->slug, $self->noid);
    if (ref $mapres) {
        $self->log->info( encode_json($mapres) );
    } else {
        $self->log->info($mapres);
    }

    $self->log->info( "Getting type..." );
    if ( !( exists $self->document->{'type'} ) ) {
        die "Missing mandatory field 'type'\n";
    }
    my $type = $self->document->{'type'};
    $self->log->info( "Got type." );


    $self->log->info( "Getting behavior..." );
    if ( $type eq 'collection' && !( exists $self->document->{'behavior'} ) ) {
        die "Missing 'behavior' for type='collection' "
          . $self->noid . " ("
          . $self->slug . ")\n";
    }
    $self->log->info( "Got behaviour." );


    $self->log->info( "Getting metadata..." );
    if ( !exists $self->document->{'dmdType'} ) {
        die "Missing dmdType\n";
    }

    my ( $depositor, $objid ) = split( /\./, $self->slug );

    my $object =
      $self->noid . '/dmd' . uc( $self->document->{'dmdType'} ) . '.xml';
    my $r = $self->swift->object_get( $self->access_metadata, $object );
    if ( $r->code != 200 ) {
        $object =~ s|/([ms])|/g|g; # handle id change
        $r = $self->swift->object_get( $self->access_metadata, $object );
        if ( $r->code != 200 ) {
            die( "Accessing $object returned code: " . $r->code . "\n" );
        }
    }
    my $xmlrecord = $r->content;

    $self->log->info( "Got metadata" );

    ## First attachment array element is the item

    # Fill in dmdSec information first
    $self->log->info( "Flattening metadata..." );
    $self->attachment->[0] = $self->flatten->byType(
        $self->document->{'dmdType'},
        utf8::is_utf8($xmlrecord)
        ? Encode::encode_utf8($xmlrecord)
        : $xmlrecord
    );
    undef $r;
    undef $xmlrecord;

    $self->log->info( "Flatened metadata." );


    $self->log->info( "Get IIIF type..." );

    $self->attachment->[0]->{'depositor'} = $depositor;
    if ( $type eq "manifest" ) {
        $self->attachment->[0]->{'type'} = 'document';
    }
    else {
        # TODO: 'series' currently used for any type of collection
        $self->attachment->[0]->{'type'} = 'series';
    }
    $self->attachment->[0]->{'key'}  = $self->slug;
    $self->attachment->[0]->{'noid'} = $self->noid;

    if ( !exists $self->attachment->[0]->{'identifier'} ) {
        $self->attachment->[0]->{'identifier'} = [];
    }

    $self->log->info( "Got IIIF type." );


    $self->log->info( "Getting ids..." );

    if (
        !(
            any { $_ eq $self->slug }
            @{ $self->attachment->[0]->{'identifier'} }
        )
      )
    {
        push @{ $self->attachment->[0]->{'identifier'} }, $self->slug;
    }

    if ( ( defined $objid )
        && !( any { $_ eq $objid } @{ $self->attachment->[0]->{'identifier'} } )
      )
    {
        push @{ $self->attachment->[0]->{'identifier'} }, $objid;
    }

    $self->log->info( "Got ids..." );


    $self->log->info( "Getting label..." );

    $self->attachment->[0]->{'label'} =
      $self->getIIIFText( $self->document->{'label'} );

    $self->attachment->[0]->{'label'} =~
      s/^\s+|\s+$//g;    # Trim spaces from beginning and end of label
    $self->attachment->[0]->{'label'} =~ s/\s+/ /g;    # Remove extra spaces


    $self->log->info( "Got label." );


    $self->log->info( "Getting OCR..." );
    if ( exists $self->document->{'ocrPdf'} ) {
        $self->attachment->[0]->{'ocrPdf'} =
          $self->document->{'ocrPdf'};
    }
    $self->log->info( "Got OCR." );

## All other attachment array elements are components


    $self->log->info( "Checking for canvases?" );
    if ( $self->document->{'canvases'} ) {
        $self->log->info( "Processing canvases..." );
        my @canvasids;
        foreach my $i ( 0 .. ( @{ $self->document->{'canvases'} } - 1 ) ) {
            die "Missing ID for canvas index=$i\n"
              if ( !defined $self->document->{'canvases'}->[$i]->{'id'} );
            push @canvasids, $self->document->{'canvases'}->[$i]->{'id'};
            $self->attachment->[ $i + 1 ]->{'noid'} =
              $self->document->{'canvases'}->[$i]->{'id'};
            $self->attachment->[ $i + 1 ]->{'label'} =
              $self->getIIIFText(
                $self->document->{'canvases'}->[$i]->{'label'} );
            $self->attachment->[ $i + 1 ]->{'type'}      = 'page';
            $self->attachment->[ $i + 1 ]->{'seq'}       = $i + 1;
            $self->attachment->[ $i + 1 ]->{'depositor'} = $depositor;
            $self->attachment->[ $i + 1 ]->{'identifier'} =
              [ $objid . "." . ( $i + 1 ) ];
            $self->attachment->[ $i + 1 ]->{'pkey'}          = $self->slug;
            $self->attachment->[ $i + 1 ]->{'manifest_noid'} = $self->noid;
            $self->attachment->[ $i + 1 ]->{'key'} =
              $self->slug . "." . ( $i + 1 );
        }
        my $tempcanvases = $self->getCanvasDocuments( \@canvasids );
        die "Can't getCanvasDocuments()\n"
          if ( ref $tempcanvases ne 'ARRAY' );
        my @canvases = @{$tempcanvases};
        die "Array length mismatch\n" if ( @canvases != @canvasids );

        foreach my $i ( 0 .. ( @canvases - 1 ) ) {
            if ( defined $canvases[$i]{'master'} ) {
                my %master;
                %master = %{ $canvases[$i]{'master'} }
                  if defined $canvases[$i]{'master'};
                my %ocrPdf;

                if ( defined $canvases[$i]{'ocrPdf'} ) {
                    %ocrPdf = %{ $canvases[$i]{'ocrPdf'} };
                    $self->attachment->[ $i + 1 ]->{'ocrPdf'} =
                      $canvases[$i]{'ocrPdf'};
                }

                $self->attachment->[ $i + 1 ]->{'canonicalMasterHeight'} =
                  $master{height}
                  if ( defined $master{height} );
                $self->attachment->[ $i + 1 ]->{'canonicalMasterWidth'} =
                  $master{width}
                  if ( defined $master{width} );
                $self->attachment->[ $i + 1 ]->{'canonicalMasterExtension'} =
                  $master{extension}
                  if ( defined $master{extension} );
                $self->attachment->[ $i + 1 ]->{'canonicalMasterSize'} =
                  $master{size}
                  if ( defined $master{size} );
                $self->attachment->[ $i + 1 ]->{'canonicalMasterMime'} =
                  $master{mime}
                  if ( defined $master{mime} );
                $self->attachment->[ $i + 1 ]->{'canonicalDownloadExtension'} =
                  $ocrPdf{extension}
                  if ( defined $ocrPdf{extension} );
            }

            if ( defined $canvases[$i]{'ocrType'} ) {
                my $noid = $self->attachment->[ $i + 1 ]->{'noid'};
                # $canvases[$i]{'ocrType'}
                my $object =
                  $noid . '/ocrTXTMAP.xml';
                my $r =
                  $self->swift->object_get( $self->access_metadata, $object );
                if ( $r->code != 200 ) {
                    $self->log->info( "Accessing $object returned code: " . $r->code . "\n" );
                } else {
                    my $xmlrecord = $r->content;

                    # Add Namespace if missing
                    $xmlrecord =~
    s|<txt:txtmap>|<txtmap xmlns:txt="http://canadiana.ca/schema/2012/xsd/txtmap">|g;
                    $xmlrecord =~ s|</txt:txtmap>|</txtmap>|g;

                    my $ocr;
                    my $xml = XML::LibXML->new->parse_string($xmlrecord);
                    my $xpc = XML::LibXML::XPathContext->new($xml);
                    $xpc->registerNs( 'txt',
                        'http://canadiana.ca/schema/2012/xsd/txtmap' );
                    $xpc->registerNs( 'alto4',
                        'http://www.loc.gov/standards/alto/ns-v4#' );
                    $xpc->registerNs( 'alto3',
                        'http://www.loc.gov/standards/alto/ns-v3' );
                    if (   $xpc->exists( '//txt:txtmap', $xml )
                        || $xpc->exists( '//txtmap', $xml ) )
                    {
                        $ocr = $xml->textContent;
                    }
                    elsif (
                        $xpc->exists( '//alto3', $xml )
                        || $xpc->exists('//alto3:alto3'), $xml
                        || $xpc->exists( '//alto4', $xml )
                        || $xpc->exists('//alto4:alto4'), $xml
                    )
                    {
                        $ocr = '';
                        foreach
                        my $content ( $xpc->findnodes( '//*[@CONTENT]', $xml ) )
                        {
                            $ocr .= " " . $content->getAttribute('CONTENT');
                        }
                    }
                    else {
                        die "Unknown XML schema for noid=$noid\n";
                    }
                    $self->attachment->[ $i + 1 ]->{'tx'} = [ normaliseSpace($ocr) ]
                    if $ocr;
                }
            }
        }
        $self->log->info( "Done processing canvases." );
    }

## Build update document and attachment

    $self->log->info( "Build update document and attachment..." );
    $self->docdata->{'type'} = 'aip';
    $self->docdata->{'noid'} = $self->noid;

    # Manifest is a 'document', ordered collection is a 'series'

    $self->log->info( "Manifest is a 'document', ordered collection is a 'series'..." );
    $self->docdata->{'sub-type'} = $self->attachment->[0]->{'type'};

    # We may not care about these any more, but will decide later...
    $self->log->info( "'label', 'pubmin', 'pubmax', 'canonicalDownload'..." );
    foreach my $field ( 'label', 'pubmin', 'pubmax', 'canonicalDownload' ) {
        if ( defined $self->attachment->[0]->{$field} ) {
            $self->docdata->{$field} = $self->attachment->[0]->{$field};
        }
    }

## Determine what collections this manifest or collection is in
    $self->log->info( "Determine what collections this manifest or collection is in..." );
    
    $self->{collections}        = {};
    $self->{orderedcollections} = {};
    $self->{collectiontree}     = $self->findCollections( $self->noid );

    $self->log->info( "Filling out CAP data for parent..." );

    # Ignore parent key from issueinfo records.
    # Concept of 'parent' going away as part of retiring 'issueinfo' records.
    delete $self->attachment->[0]->{'pkey'};
    my @parents = keys %{ $self->{orderedcollections} };
    if (@parents) {
        my $parent = shift @parents;
        if ( @parents != 0 ) {
            warn
"A member of more than a single ordered collection. Only processing '$parent'\n";
        }
        if ($parent) {

            # Old platform didn't include 'series' records in collections.
            $self->log->info( "Old platform didn't include 'series' records in collections..." );
    
            delete $self->{collections}->{$parent};
            $self->attachment->[0]->{'pkey'} = $parent;
            $self->docdata->{'parent'} = $parent;

            # The noid was stored in case needed.
            my $noid = $self->{orderedcollections}->{$parent};

            # This is all going away, so doen't have to be ideal design.
            # This is how we create a sequence at the moment.
            $self->log->info( "This is how we create a sequence at the moment..." );
    
            my $parentdoc = $self->getAccessDocument( uri_escape_utf8($noid) );

            if ($parentdoc) {
                if ( ( ref $parentdoc->{members} ) eq "ARRAY" ) {
                    my $seq;
                    my $plabel;
                    foreach my $i ( 0 .. ( @{ $parentdoc->{members} } - 1 ) ) {
                        if ( $parentdoc->{members}->[$i]->{id} eq $self->noid )
                        {
                            $seq = $i + 1;
                            $plabel =
                              $self->getIIIFText(
                                $parentdoc->{members}->[$i]->{'label'} );
                            if ( !$plabel ) {
                                $plabel =
                                  $self->getIIIFText( $parentdoc->{'label'} );
                            }
                            last;
                        }
                    }
                    if ( defined $seq ) {

                        # Was a string, needs to be a string.
                        $self->attachment->[0]->{'seq'}    = "$seq";
                        $self->attachment->[0]->{'plabel'} = "$plabel";
                        $self->docdata->{'seq'}            = "$seq";
                    }
                    else {
                        warn "My noid wasn't found in Parent=$noid\n";
                    }
                }
                else {
                    warn "Parent=$noid {members} field not an array\n";
                }
            }
            else {
                warn "Unable to load parent=$noid doc\n";
            }
        }
        $self->log->info( "Done setting collection tree." );
    }

    if ( !exists $self->docdata->{'parent'} ) {
        $self->docdata->{'noparent'} = JSON::true;
    }

    # Always set collection -- will be '' if no collections.
    $self->log->info( "Always set collection -- will be '' if no collections..." );
    $self->docdata->{collectionseq} =
      join( ',', keys %{ $self->{collections} } );

# If not public, then not public in old cosearch/copresentation system (clean up cosearch/copresentation docs)
   
    $self->log->info( " If not public, then not public in old cosearch/copresentation system (clean up cosearch/copresentation docs)..." );
    if ( exists $self->document->{'public'} ) {
        $self->adddocument();
    }
    else {
        $self->deletedocument();
    }

    
    foreach my $ancestor ( @{ $self->{collectiontree} } ) {
        my $noid = $ancestor->{noid};
        my $behavior = $ancestor->{behavior};
        if ($noid && $behavior eq "multi-part") {
            # Force re-processing of collections which this document is a member of.
            # Nothing is done for "unordered" collections, but
            # "multi-part" collections have fields dependent on descendents.
            $self->log->info( "Force re-processing of collections which this document is a member of...." );
            $self->forceAccessUpdate($noid);
        }
    }
    $self->log->info( "Done processing." );
}

sub findCollections {
    my ( $self, $noid ) = @_;
    $self->log->info( "findCollections..." );

    my $foundcollections = $self->getAccessCollections($noid);
    die "Can't getAccessCollections($noid)\n" if ( !$foundcollections );
    $self->log->info( "getAccessCollections..." );

    my @collect;

    foreach my $collection ( @{$foundcollections} ) {
        $self->log->info( "getAccessSlim..." );
        my $slim = $self->getAccessSlim( $collection->{id} );
        if ( ref $slim eq 'HASH' ) {
            $self->log->info( "got AccessSlim..." );
            $slim->{noid}        = $collection->{id};
            $slim->{collections} = $self->findCollections( $collection->{id} );
            push @collect, $slim;

            # Old style
            my $slug = $slim->{slug};
            if ( !exists $self->{collections}->{$slug} ) {
                $self->log->info( "old style..." );
                $self->{collections}->{$slug} = $collection->{id};
            }
            if ( exists $slim->{behavior}
                && ( $slim->{behavior} ne "unordered" ) )
            {
                $self->log->info( "unordered..." );
                $self->{orderedcollections}->{$slug} = $collection->{id};
            }

        }
        else {
            die "Unable to findCollections($noid)\n";
        }
    }

    $self->log->info( "found collections" );
    return \@collect;
}

sub getIIIFText {
    my ( $self, $text ) = @_;

    foreach my $try ( "none", "en", "fr" ) {
        if ( exists $text->{$try} ) {
            return $text->{$try};
        }
    }
}

sub getCanvasDocuments {
    my ( $self, $docids ) = @_;

    $self->canvasdb->type("application/json");
    my $url = "/_all_docs?include_docs=true";
    my $res = $self->canvasdb->post(
        $url,
        { keys         => $docids },
        { deserializer => 'application/json' }
    );
    if ( $res->code == 200 ) {
        my @return;
        foreach my $row ( @{ $res->data->{rows} } ) {
            if ( exists $row->{doc} ) {
                push @return, $row->{doc};
            }
            else {
                warn "Key: "
                  . $row->{key}
                  . "   Error: "
                  . $row->{error} . "\n";
                push @return, undef;
            }
        }
        return \@return;
    }
    else {
        if ( defined $res->response->content ) {
            $self->log->warn( $res->response->content );
        }
        $self->log->warn( "POST $url return code: " . $res->code );
        return;
    }
}

sub getAccessDocument {
    my ( $self, $docid ) = @_;

    $self->accessdb->type("application/json");
    my $url = "/$docid";
    my $res =
      $self->accessdb->get( $url, {}, { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        return $res->data;
    }
    else {
        if ( defined $res->response->content ) {
            $self->log->warn( $res->response->content );
        }
        $self->log->warn( "GET $url return code: " . $res->code );
        return;
    }
}

sub getAccessSlim {
    my ( $self, $docid ) = @_;

    $self->accessdb->type("application/json");
    my $url = "/_find";
    my $res = $self->accessdb->post(
        $url,
        {
            "selector" => {
                "_id" => {
                    '$eq' => $docid
                }
            },
            "fields" => [ "slug", "behavior", "label" ]
        },
        { deserializer => 'application/json' }
    );
    if ( $res->code == 200 ) {
        return pop @{ $res->data->{docs} };
    }
    else {
        if ( defined $res->response->content ) {
            $self->log->warn( $res->response->content );
        }
        $self->log->warn( "GET $url return code: " . $res->code );
        return;
    }
}

sub getSearchItem {
    my ( $self, $docid ) = @_;

    $self->accessdb->type("application/json");
    my $url = "/_find";
    my $res = $self->cosearch2db->post(
        $url,
        {
            "selector" => {
                "noid" => {
                    '$eq' => $docid
                }
            },
            "fields" => [ "_id", "pubmin", "label" ]
        },
        { deserializer => 'application/json' }
    );
    if ( $res->code == 200 ) {
        return pop @{ $res->data->{docs} };
    }
    else {
        warn "GET $url return code: " . $res->code . "\n";
        return;
    }
}

sub forceAccessUpdate {
    my ( $self, $noid ) = @_;

    $self->accessdb->type("application/json");
    my $url = "/_design/access/_update/forceUpdate/" . uri_escape_utf8($noid);

    my $res =
      $self->accessdb->post( $url, {}, { deserializer => 'application/json' } );
    if ( ( $res->code != 201 ) && ( $res->code != 409 ) ) {
        if ( defined $res->response->content ) {
            $self->log->warn( $res->response->content );
        }
        $self->log->warn(
            "POST $url return code: " . $res->code . "(" . $res->error . ")" );
    }
}

sub getAccessCollections {
    my ( $self, $docid ) = @_;

#TODO: generalize this.  Not sure why this view is special (slow calculation after update?)
    my $tries = 5;

    $self->accessdb->type("application/json");
    my $url = "/_design/access/_view/members";

    do {
        my $res = $self->accessdb->post(
            $url,
            { keys         => [$docid] },
            { deserializer => 'application/json' }
        );
        if ( $res->code == 200 ) {
            return $res->data->{rows};
        }
        else {
            $tries--;
            if ( defined $res->response->content ) {
                $self->log->warn( $res->response->content );
            }
            $self->log->warn( "POST $url keys=[$docid] return code: "
                  . $res->code . " ("
                  . $res->error
                  . ") retries=$tries" );
        }
    } until ( !$tries );
    return;
}

sub deletedocument {
    my ($self) = @_;

    $self->update_couch( $self->cosearch2db );
    $self->update_couch( $self->copresentation2db );
}

sub adddocument {
    my ($self) = @_;

    $self->process_attachment();

    # Map also counts for a minimum of repos, so adding in current array
    # to presentation.

    $self->log->info( " Map also counts for a minimum of repos..." );
    $self->presentdoc->{ $self->slug }->{'repos'} = $self->docdata->{'repos'}
      if defined $self->docdata->{'repos'};

    # All Items should have a date
    $self->log->info( "All Items should have a date..." );
    $self->presentdoc->{ $self->slug }->{'updated'} =
      DateTime->now()->iso8601() . 'Z';

    # Note: Not stored within pages, so no need to loop through all keys
    $self->log->info( "Note: Not stored within pages..." );
    my @collections = sort keys %{ $self->{collections} };
    $self->presentdoc->{ $self->slug }->{'collection'} = \@collections;
    $self->searchdoc->{ $self->slug }->{'collection'}  = \@collections;

    # New key to build better breadcrumbs in the future
    $self->log->info( "New key to build better breadcrumbs in the future" );
    $self->presentdoc->{ $self->slug }->{'collection_tree'} =
      $self->{collectiontree};

    # If a parl/${id}.json file exists, process it.
    $self->log->info( "If a parl/id.json file exists, process it." );
    if ( -e DATAPATH . "/parl/" . $self->slug . ".json" ) {
        $self->process_parl();
    }

    $self->log->info( "Determine if collection or manifest." );
    # Determine if collection or manifest
    if ( $self->document->{'type'} eq 'collection' ) {

        # Process collection (old: only series)

        $self->log->info( "Process collection (old: only series)." );
        if ( exists $self->docdata->{'parent'} ) {
            die $self->slug
              . " is a collection and has parent field (not yet supported)\n";
        }

        $self->log->info( "TODO: These tests seem redundant, as problem unlikely." );
        # TODO: These tests seem redundant, as problem unlikely.
        if ( scalar( keys %{ $self->presentdoc } ) != 1 ) {
            die $self->slug
              . " is a collection and has "
              . scalar( keys %{ $self->presentdoc } )
              . " records\n";
        }
        if ( $self->presentdoc->{ $self->slug }->{'type'} ne 'series' ) {
            die $self->slug
              . " is a collection, but record type not 'series'\n";
        }
        $self->process_collection();
    }
    else {
        # Process manifest (old: issue or monograph)

        $self->process_manifest();
    }

    # If a tag json file exists, process it.
    # - Needs to be processed after process_manifest() as
    #   process_externalmetaHP() sets a flag within component field.
    if ( -e DATAPATH . "/tag/" . $self->slug . ".json" ) {
        $self->process_externalmetaHP();
    }

    if (
        scalar( keys %{ $self->searchdoc } ) !=
        scalar( keys %{ $self->presentdoc } ) )
    {
        warn $self->slug . " had "
          . scalar( keys %{ $self->searchdoc } )
          . " searchdoc and "
          . scalar( keys %{ $self->presentdoc } )
          . " presentdoc\n";
    }

    $self->update_couch( $self->cosearch2db,       $self->searchdoc );
    $self->update_couch( $self->copresentation2db, $self->presentdoc );

    if ( $self->{ustatus} == 0 ) {
        warn "One or more updates were not successful\n";
    }
}

# To delete any extra documents that don't match the current IDs (number of pages decreased, slug changed)
# Use views to create hash of docs based on : IDs of docs, noid view , manifest_noid view
# Use hash to update _rev of any doc that will be saved (delete key from hash), and then mark to be deleted every document still in hash.
# Use this also as delete_couch() , where docs=[];
sub update_couch {
    my ( $self, $dbo, $docs ) = @_;

    # Same function can be used to simply delete all the old docs
    if ( !$docs ) {
        $docs = {};
    }

    $dbo->type("application/json");

    my %couchdocs;

    # 1. Looking up the ID to get revision of any existing document
    my $url = "/_all_docs";
    my $res = $dbo->post(
        $url,
        { keys         => [ $self->slug ] },
        { deserializer => 'application/json' }
    );
    if ( $res->code == 200 ) {
        foreach my $row ( @{ $res->data->{rows} } ) {
            if ( defined $row->{id} && defined $row->{value}->{rev} && !defined $row->{value}->{deleted} ) {
                $couchdocs{ $row->{id} } = $row->{value}->{rev};
            }
        }
    } else {
        $self->log->warn( $res->response->content ) if defined $res->response->content;
        $self->log->warn( "1 update_couch() $url return code: " . $res->code . "\n" );
    }

    # 2. noid view
    $url = "/_design/access/_view/noid";
    $res = $dbo->post(
        $url,
        { keys => [ $self->noid ], include_docs => JSON::true },
        { deserializer => 'application/json' }
    );
    if ( $res->code == 200 ) {
        foreach my $row ( @{ $res->data->{rows} } ) {
            if ( defined $row->{id} && defined $row->{doc}->{'_rev'} ) {
                $couchdocs{ $row->{id} } = $row->{doc}->{'_rev'};
            }
        }
    } else {
        $self->log->warn( $res->response->content ) if defined $res->response->content;
        $self->log->warn( "2 update_couch() $url return code: " . $res->code . "\n" );
    }

    # 3. manifest_noid view
    $url = "/_design/access/_view/manifest_noid";
    $res = $dbo->post(
        $url,
        { keys => [ $self->noid ], include_docs => JSON::true },
        { deserializer => 'application/json' }
    );
    if ( $res->code == 200 ) {
        foreach my $row ( @{ $res->data->{rows} } ) {
            if ( defined $row->{id} && defined $row->{doc}->{'_rev'} ) {
                $couchdocs{ $row->{id} } = $row->{doc}->{'_rev'};
            }
        }
    } else {
        $self->log->warn( $res->response->content ) if defined $res->response->content;
        $self->log->warn( "3 update_couch() $url return code: " . $res->code . "\n" );
    }

    # 4. Additional lookups for any docs not found yet
    my @doclookup;
    foreach my $key ( keys %{$docs} ) {
        push @doclookup, $key unless defined $couchdocs{$key};
    }

    if (@doclookup) {
        $url = "/_all_docs";
        $res = $dbo->post(
            $url,
            { keys => \@doclookup },
            { deserializer => 'application/json' }
        );
        if ( $res->code == 200 ) {
            foreach my $row ( @{ $res->data->{rows} } ) {
                if ( defined $row->{id} && defined $row->{value}->{rev} && !defined $row->{value}->{deleted} ) {
                    $couchdocs{ $row->{id} } = $row->{value}->{rev};
                }
            }
        } else {
            $self->log->warn( $res->response->content ) if defined $res->response->content;
            $self->log->warn( "4 update_couch() $url return code: " . $res->code . "\n" );
        }
    }

    # 5. Prepare docs for update or deletion
    my $postdoc = { docs => [] };

    foreach my $docid ( keys %{$docs} ) {
        if ( defined $couchdocs{$docid} ) {
            $docs->{$docid}->{"_rev"} = $couchdocs{$docid};
            delete $couchdocs{$docid};
        }
        $docs->{$docid}->{"_id"} = $docid;
        push @{ $postdoc->{docs} }, $docs->{$docid};
    }

    foreach my $docid ( keys %couchdocs ) {
        push @{ $postdoc->{docs} }, {
            '_id'      => $docid,
            '_rev'     => $couchdocs{$docid},
            "_deleted" => JSON::true
        };
    }

    # 6. Batched bulk update
    my $bulk_url   = "/_bulk_docs";
    my $all_docs   = $postdoc->{docs};
    my $batch_size = 100;

    while ( my @batch = splice( @$all_docs, 0, $batch_size ) ) {
        my $res = $dbo->post(
            $bulk_url,
            { docs => \@batch },
            { deserializer => 'application/json' }
        );

        if ( $res->code == 201 ) {
            foreach my $thisdoc ( @{ $res->data } ) {
                if ( !$thisdoc->{ok} ) {
                    warn $thisdoc->{id}
                      . " was not OK during batched update_couch ("
                      . $dbo->server . ") "
                      . encode_json($thisdoc) . "\n";
                    $self->{ustatus} = 0;
                }
            }
        } else {
            $self->log->warn( $res->response->content ) if defined $res->response->content;
            $self->log->warn("Batched update_couch() $bulk_url return code: " . $res->code . "\n");
            $self->{ustatus} = 0;
        }
    }
}


sub process_attachment {
    my ($self) = @_;

    # First loop to generate the item 'tx' field if it doesn't already exist
    if ( !exists $self->attachment->[0]->{'tx'} ) {
        my @tx;
        for my $i ( 1 .. $#{ $self->attachment } ) {
            my $doc = $self->attachment->[$i];
            if ( exists $doc->{'tx'} ) {
                foreach my $t ( @{ $doc->{'tx'} } ) {
                    push @tx, $t;
                }
            }
        }
        if (@tx) {
            $self->attachment->[0]->{'tx'} = \@tx;
        }

        # If there is now an item 'tx' field, handle its count
        if ( exists $self->attachment->[0]->{'tx'} ) {
            my $count = scalar( @{ $self->attachment->[0]->{'tx'} } );
            if ($count) {
                $self->attachment->[0]->{'component_count_fulltext'} = $count;
            }
        }

    }

    # These fields copied from item into each component.
    my $pubmin = $self->attachment->[0]->{'pubmin'};
    my $pubmax = $self->attachment->[0]->{'pubmax'};
    my $lang   = $self->attachment->[0]->{'lang'};

    # Loop through and copy into cosearch/copresentation
    for my $i ( 0 .. $#{ $self->attachment } ) {
        my $doc = $self->attachment->[$i];
        my $key = $doc->{'key'}
          || die "Key missing from document in Hammer.json";

        # Copy fields into components
        if ($i) {
            if ($pubmin) {
                $doc->{'pubmin'} = $pubmin;
            }
            if ($pubmax) {
                $doc->{'pubmax'} = $pubmax;
            }
            if ($lang) {
                $doc->{'lang'} = $lang;
            }
        }

        # Hash of all fields that are set
        my %docfields = map { $_ => 1 } keys %{$doc};

        $self->searchdoc->{$key} = {};

        # Copy the fields for cosearch
        foreach my $cf (
            "key",             "type",
            "depositor",       "label",
            "pkey",            "plabel",
            "seq",             "pubmin",
            "pubmax",          "lang",
            "identifier",      "pg_label",
            "ti",              "au",
            "pu",              "su",
            "no",              "ab",
            "tx",              "no_rights",
            "no_source",       "component_count_fulltext",
            "component_count", "noid",
            "manifest_noid"
          )
        {
            $self->searchdoc->{$key}->{$cf} = $doc->{$cf} if exists $doc->{$cf};
            delete $docfields{$cf};
        }

        $self->presentdoc->{$key} = {};

        # Copy the fields for copresentation
        foreach my $cf (
            "key",                        "type",
            "label",                      "pkey",
            "plabel",                     "seq",
            "lang",                       "media",
            "identifier",                 "canonicalUri",
            "canonicalMaster",            "canonicalMasterExtension",
            "canonicalMasterMime",        "canonicalMasterSize",
            "canonicalMasterMD5",         "canonicalMasterWidth",
            "canonicalMasterHeight",      "canonicalDownload",
            "canonicalDownloadExtension", "canonicalDownloadMime",
            "canonicalDownloadSize",      "canonicalDownloadMD5",
            "ti",                         "au",
            "pu",                         "su",
            "no",                         "ab",
            "no_source",                  "no_rights",
            "component_count_fulltext",   "component_count",
            "noid",                       "file",
            "ocrPdf",                     "manifest_noid"
          )
        {
            $self->presentdoc->{$key}->{$cf} = $doc->{$cf}
              if exists $doc->{$cf};
            delete $docfields{$cf};
        }

        if ( keys %docfields ) {
            warn "Unused Hammer fields in $key: "
              . join( ",", keys %docfields ) . "\n";
        }
    }
}

sub process_parl {
    my ($self) = @_;

    my $filename = DATAPATH . "/parl/" . $self->slug . ".json";
    my $parl     = read_json($filename);

    my %term_map = (
        language       => "lang",
        label          => "parlLabel",
        chamber        => "parlChamber",
        session        => "parlSession",
        type           => "parlType",
        node           => "parlNode",
        reportTitle    => "parlReportTitle",
        callNumber     => "parlCallNumber",
        primeMinisters => "parlPrimeMinisters",
        pubmin         => "pubmin",
        pubmax         => "pubmax"
    );

    my @search_terms =
      qw/language label chamber session type reportTitle callNumber primeMinisters pubmin pubmax/;
    foreach my $st (@search_terms) {
        $self->searchdoc->{ $self->slug }->{ $term_map{$st} } = $parl->{$st}
          if exists $parl->{$st};
    }

    foreach my $pt ( keys %term_map ) {
        $self->presentdoc->{ $self->slug }->{ $term_map{$pt} } = $parl->{$pt}
          if exists $parl->{$pt};
    }
}

# Merging multi-value fields
sub mergemulti {
    my ( $doc, $field, $value ) = @_;

    if ( !defined $doc->{$field} ) {
        $doc->{$field} = $value;
    }
    else {
        # Ensure values being pushed are unique.
        foreach my $mval ( @{$value} ) {
            my $found = 0;
            foreach my $tval ( @{ $doc->{$field} } ) {
                if ( $mval eq $tval ) {
                    $found = 1;
                    last;
                }
            }
            if ( !$found ) {
                push @{ $doc->{$field} }, $mval;
            }
        }
    }
}

sub process_externalmetaHP {
    my ($self) = @_;

    my $filename = DATAPATH . "/tag/" . $self->slug . ".json";
    my $emHP     = read_json($filename);

    foreach my $seq ( keys %{$emHP} ) {
        my $pageid = $self->slug . "." . $seq;
        my $tags   = $emHP->{$seq};
        if ( defined $self->searchdoc->{$pageid} ) {
            my %tagfields = map { $_ => 1 } keys %{$tags};

            # Copy the fields for cosearch && copresentation
            # In parent as well..
            foreach my $cf (
                "tag",     "tagPerson",
                "tagName", "tagPlace",
                "tagDate", "tagNotebook",
                "tagDescription"
              )
            {
                if ( exists $tags->{$cf} ) {
                    if ( ref( $tags->{$cf} ne "ARRAY" ) ) {
                        die
                          "externalmetaHP tag $cf for page $pageid not array\n";
                    }

                    mergemulti( $self->searchdoc->{$pageid}, $cf,
                        $tags->{$cf} );
                    mergemulti( $self->presentdoc->{$pageid},
                        $cf, $tags->{$cf} );
                    mergemulti( $self->searchdoc->{ $self->slug },
                        $cf, $tags->{$cf} );
                    mergemulti( $self->presentdoc->{ $self->slug },
                        $cf, $tags->{$cf} );
                }
                delete $tagfields{$cf};
            }

            # Set flag in item to indicate this component has tags
            $self->presentdoc->{ $self->slug }->{'components'}->{$pageid}
              ->{'hasTags'} = JSON::true;

            # Set flag in item to indicate some component has tags
            $self->presentdoc->{ $self->slug }->{'hasTags'} = JSON::true;

            if ( keys %tagfields ) {
                warn "Unused externalmetaHP fields in $pageid: "
                  . join( ",", keys %tagfields ) . "\n";
            }
        }
        else {
            warn "externalmetaHP sequence $seq doesn't exist in "
              . $self->slug . "\n";
        }
    }
}

sub process_collection {
    my ($self) = @_;

    my @order;
    my $items = {};

    $self->log->info( "Processing collection..." );
    die "{members} is not an array\n"
      if ( ref $self->document->{members} ne 'ARRAY' );

    # Search interface wants a count.
    $self->log->info( "Search interface wants a count." );
    $self->searchdoc->{ $self->slug }->{'item_count'} =
      scalar( @{ $self->document->{members} } );

   # Order is in the multi-part collection,
   # but values we need are in search documents that need to be processed first!
    $self->log->info( "Order is in the multi-part collection..." );

    my @notfound;

    $self->log->info( "Looping over all item members..." );
    $self->log->info( scalar( @{ $self->document->{members} } ));
    foreach my $issue ( @{ $self->document->{members} } ) {
        my $item = $self->getSearchItem( $issue->{id} );
        if ($item) {
            my $slug = delete $item->{'_id'};
            $items->{$slug} = $item;
            push @order, $slug;
        }
        else {
            push @notfound, $issue->{id};
        }
    }
    $self->presentdoc->{ $self->slug }->{'items'} = $items;
    $self->log->info( "Done items hash" );

    if (@notfound) {
        warn "Noids not found in Search documents: " . join( ' ', @notfound ),
          "\n";
    }

    # So far we only support "unordered" and "multi-part" collections.
    $self->log->info( "# So far we only support 'unordered and 'multi-part' collections..." );
    if ( $self->document->{'behavior'} eq "multi-part" ) {
        $self->presentdoc->{ $self->slug }->{'order'} = \@order;
    }
}

sub process_manifest {
    my ($self) = @_;

    my $components = {};
    my %seq;
    my @order;

    foreach my $thisdoc ( keys %{ $self->presentdoc } ) {
        next if ( $self->presentdoc->{$thisdoc}->{'type'} ne 'page' );
        $seq{ $self->presentdoc->{$thisdoc}->{'seq'} + 0 } =
          $self->presentdoc->{$thisdoc}->{'key'};
        $components->{ $self->presentdoc->{$thisdoc}->{'key'} }->{'label'} =
          $self->presentdoc->{$thisdoc}->{'label'};
        if ( exists $self->presentdoc->{$thisdoc}->{'canonicalMaster'} ) {
            $components->{ $self->presentdoc->{$thisdoc}->{'key'} }
              ->{'canonicalMaster'} =
              $self->presentdoc->{$thisdoc}->{'canonicalMaster'};
        }
        if (
            exists $self->presentdoc->{$thisdoc}->{'canonicalMasterExtension'} )
        {
            $components->{ $self->presentdoc->{$thisdoc}->{'key'} }
              ->{'canonicalMasterExtension'} =
              $self->presentdoc->{$thisdoc}->{'canonicalMasterExtension'};
        }
        if ( exists $self->presentdoc->{$thisdoc}->{'noid'} ) {
            $components->{ $self->presentdoc->{$thisdoc}->{'key'} }->{'noid'} =
              $self->presentdoc->{$thisdoc}->{'noid'};
        }
        if ( exists $self->presentdoc->{$thisdoc}->{'canonicalMasterWidth'} ) {
            $components->{ $self->presentdoc->{$thisdoc}->{'key'} }
              ->{'canonicalMasterWidth'} =
              $self->presentdoc->{$thisdoc}->{'canonicalMasterWidth'};
        }
        if ( exists $self->presentdoc->{$thisdoc}->{'canonicalMasterHeight'} ) {
            $components->{ $self->presentdoc->{$thisdoc}->{'key'} }
              ->{'canonicalMasterHeight'} =
              $self->presentdoc->{$thisdoc}->{'canonicalMasterHeight'};
        }
        if ( exists $self->presentdoc->{$thisdoc}->{'canonicalDownload'} ) {
            $components->{ $self->presentdoc->{$thisdoc}->{'key'} }
              ->{'canonicalDownload'} =
              $self->presentdoc->{$thisdoc}->{'canonicalDownload'};
        }
        if (
            exists $self->presentdoc->{$thisdoc}->{'canonicalDownloadExtension'}
          )
        {
            $components->{ $self->presentdoc->{$thisdoc}->{'key'} }
              ->{'canonicalDownloadExtension'} =
              $self->presentdoc->{$thisdoc}->{'canonicalDownloadExtension'};
        }
        if ( defined $self->presentdoc->{ $self->slug }->{'collection'} ) {
            $self->presentdoc->{$thisdoc}->{'collection'} =
              $self->presentdoc->{ $self->slug }->{'collection'};
            $self->searchdoc->{$thisdoc}->{'collection'} =
              $self->presentdoc->{ $self->slug }->{'collection'};
        }
    }
    foreach my $page ( sort { $a <=> $b } keys %seq ) {
        push @order, $seq{$page};
    }

    $self->{presentdoc}->{ $self->slug }->{'order'}      = \@order;
    $self->{presentdoc}->{ $self->slug }->{'components'} = $components;
    $self->{searchdoc}->{ $self->slug }->{'component_count'} =
      scalar(@order);

}

1;
