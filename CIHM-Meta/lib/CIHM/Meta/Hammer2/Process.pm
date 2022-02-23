package CIHM::Meta::Hammer2::Process;

use 5.014;
use strict;
use XML::LibXML;
use Try::Tiny;
use JSON;
use Switch;
use URI::Escape;
use CIHM::Meta::dmd::flatten qw(normaliseSpace);
use List::MoreUtils qw(uniq);
use File::Temp;

=head1 NAME

CIHM::Meta::Hammer2::Process - Handles the processing of individual manifests

=head1 SYNOPSIS

    my $process = CIHM::Meta::Hammer2::Process->new($args);
      where $args is a hash of arguments.

=cut

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

    $self->{flatten} = CIHM::Meta::dmd::flatten->new;

    $self->{updatedoc}            = {};
    $self->{pageinfo}             = {};
    $self->{attachment}           = [];
    $self->pageinfo->{count}      = 0;
    $self->pageinfo->{dimensions} = 0;

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

sub internalmetadb {
    my $self = shift;
    return $self->args->{internalmetadb};
}

sub cantaloupe {
    my $self = shift;
    return $self->args->{cantaloupe};
}

sub updatedoc {
    my $self = shift;
    return $self->{updatedoc};
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

# Top method
sub process {
    my ($self) = @_;

    $self->{document} =
      $self->accessdb->get_document( uri_escape_utf8( $self->noid ) );
    die "Missing Document\n" if !( $self->document );

    if ( !exists $self->document->{'slug'} ) {
        die "Missing slug\n";
    }
    my $slug = $self->document->{'slug'};

    $self->log->info( "Processing " . $self->noid . " ($slug)" );

    if ( !( exists $self->document->{'type'} ) ) {
        die "Missing mandatory field 'type'\n";
    }
    my $type = $self->document->{'type'};

    if ( $type eq 'collection' ) {    # This is a collection
        if (  !( exists $self->document->{'behavior'} )
            || ( $self->document->{'behavior'} eq "unordered" ) )
        {
            $self->log->info( "Nothing to do for an unordered collection"
                  . $self->noid
                  . " ($slug)" );
            return;
        }
    }

    if ( !exists $self->document->{'dmdType'} ) {
        die "Missing dmdType\n";
    }

    my ( $depositor, $objid ) = split( /\./, $slug );

    my $object =
      $self->noid . '/dmd' . uc( $self->document->{'dmdType'} ) . '.xml';
    my $r = $self->swift->object_get( $self->access_metadata, $object );
    if ( $r->code != 200 ) {
        die( "Accessing $object returned code: " . $r->code . "\n" );
    }
    my $xmlrecord = $r->content;

## First attachment array element is the item

    # Fill in dmdSec information first
    $self->attachment->[0] = $self->flatten->byType(
        $self->document->{'dmdType'},
        utf8::is_utf8($xmlrecord)
        ? Encode::encode_utf8($xmlrecord)
        : $xmlrecord
    );
    undef $r;
    undef $xmlrecord;

    $self->attachment->[0]->{'depositor'} = $depositor;
    if ( $type eq "manifest" || $type eq "pdf" ) {
        $self->attachment->[0]->{'type'} = 'document';
    }
    else {
        $self->attachment->[0]->{'type'} = 'series';
    }
    $self->attachment->[0]->{'key'}  = $slug;
    $self->attachment->[0]->{'noid'} = $self->noid;

    my %identifier = ( $objid => 1 );
    if ( exists $self->attachment->[0]->{'identifier'} ) {
        foreach my $identifier ( @{ $self->attachment->[0]->{'identifier'} } ) {
            $identifier{$identifier} = 1;
        }
    }
    @{ $self->attachment->[0]->{'identifier'} } = keys %identifier;

    $self->attachment->[0]->{'label'} =
      $self->getIIIFText( $self->document->{'label'} );

    $self->attachment->[0]->{'label'} =~
      s/^\s+|\s+$//g;    # Trim spaces from beginning and end of label
    $self->attachment->[0]->{'label'} =~ s/\s+/ /g;    # Remove extra spaces

    if ( exists $self->document->{'file'} ) {
        $self->attachment->[0]->{'canonicalDownload'} =
          $self->document->{'file'}->{'path'};
        $self->attachment->[0]->{'canonicalDownloadSize'} =
          $self->document->{'file'}->{'size'};
        $self->attachment->[0]->{'file'} =
          $self->document->{'file'};

    }

    if ( exists $self->document->{'ocrPdf'} ) {
        $self->attachment->[0]->{'canonicalDownload'} =
          $self->document->{'ocrPdf'}->{'path'};
        $self->attachment->[0]->{'canonicalDownloadSize'} =
          $self->document->{'ocrPdf'}->{'size'};
        $self->attachment->[0]->{'ocrPdf'} =
          $self->document->{'ocrPdf'};
    }

## All other attachment array elements are components

    if ( $self->document->{'canvases'} ) {
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
            $self->attachment->[ $i + 1 ]->{'pkey'}          = $slug;
            $self->attachment->[ $i + 1 ]->{'manifest_noid'} = $self->noid;
            $self->attachment->[ $i + 1 ]->{'key'} = $slug . "." . ( $i + 1 );
        }
        my @canvases = @{ $self->canvasdb->get_documents( \@canvasids ) };
        die "Array length mismatch\n" if ( @canvases != @canvasids );

        foreach my $i ( 0 .. ( @canvases - 1 ) ) {
            if ( defined $canvases[$i]{'master'} ) {
                my %master;
                %master = %{ $canvases[$i]{'master'} }
                  if defined $canvases[$i]{'master'};
                my %ocrPdf;
                %ocrPdf = %{ $canvases[$i]{'ocrPdf'} }
                  if defined $canvases[$i]{'ocrPdf'};

                $self->attachment->[ $i + 1 ]->{'canonicalMasterHeight'} =
                  $master{height}
                  if ( defined $master{height} );
                $self->attachment->[ $i + 1 ]->{'canonicalMasterWidth'} =
                  $master{width}
                  if ( defined $master{width} );
                $self->attachment->[ $i + 1 ]->{'canonicalMaster'} =
                  $master{path}
                  if ( defined $master{path} );
                $self->attachment->[ $i + 1 ]->{'canonicalMasterExtension'} =
                  $master{extension}
                  if ( defined $master{extension} );
                $self->attachment->[ $i + 1 ]->{'canonicalMasterSize'} =
                  $master{size}
                  if ( defined $master{size} );
                $self->attachment->[ $i + 1 ]->{'canonicalMasterMime'} =
                  $master{mime}
                  if ( defined $master{mime} );
                $self->attachment->[ $i + 1 ]->{'canonicalDownload'} =
                  $ocrPdf{path}
                  if ( defined $ocrPdf{path} );
                $self->attachment->[ $i + 1 ]->{'canonicalDownloadExtension'} =
                  $ocrPdf{extension}
                  if ( defined $ocrPdf{extension} );
            }

            if ( defined $canvases[$i]{'ocrType'} ) {
                my $noid = $self->attachment->[ $i + 1 ]->{'noid'};
                my $object =
                  $noid . '/ocr' . uc( $canvases[$i]{'ocrType'} ) . '.xml';
                my $r =
                  $self->swift->object_get( $self->access_metadata, $object );
                if ( $r->code != 200 ) {
                    die(
                        "Accessing $object returned code: " . $r->code . "\n" );
                }
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
                $xpc->registerNs( 'alto',
                    'http://www.loc.gov/standards/alto/ns-v3' );
                if (   $xpc->exists( '//txt:txtmap', $xml )
                    || $xpc->exists( '//txtmap', $xml ) )
                {
                    $ocr = $xml->textContent;
                }
                elsif (
                       $xpc->exists( '//alto', $xml )
                    || $xpc->exists('//alto:alto'),
                    $xml
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

    # 'tx' field and number of pages is put in item for born digital PDF files
    if ( $type eq "pdf" ) {
        if ( !exists $self->document->{'file'} ) {
            die "{file} wasn't set\n";
        }
        my $object;
        my $container;
        if ( exists $self->document->{'file'}->{'path'} ) {
            $object    = $self->document->{'file'}->{'path'};
            $container = $self->preservation_files;
        }
        elsif ( exists $self->document->{'file'}->{'extension'} ) {
            $object =
              $self->noid . "." . $self->document->{'file'}->{'extension'};
            $container = $self->access_files;
        }
        else {
            die "{file} must have a {path} or {extension|\n";
        }

        my $temp = File::Temp->new( UNLINK => 1, SUFFIX => '.pdf' );

        my $r = $self->swift->object_get( $container, $object,
            { write_file => $temp } );
        if ( $r->code != 200 ) {
            die(    "GET object=$object , contaimer=$container returned: "
                  . $r->code
                  . "\n" );
        }
        my $pdfname = $temp->filename;
        close $temp;

      # This is worth replacing at some point in the future.
      # But not a focus now, as we want to replace Hammer2 completely soonish...
        my $pdfpages;
        open( my $fh, "/usr/bin/pdfinfo $pdfname |" )
          || die "Can't open pipe from pdfinfo for $pdfname\n";
        while ( my $infoline = <$fh> ) {
            if ( $infoline =~ /Pages:\s*(\d+)$/ ) {
                $pdfpages = $1 + 0;
            }
        }
        $self->attachment->[0]->{'component_count'} = $pdfpages;
        close $fh;

        open( my $fh, "/usr/bin/pdftotext -q $pdfname - |" )
          || die "Can't open pipe from pdftotext for $pdfname\n";
        binmode( $fh, ":encoding(UTF-8)" );
        my $tx = do { local $/; <$fh> };
        $self->attachment->[0]->{'tx'} = [$tx];
        close $fh;

    }

    $self->clearNoidDocument($slug);

## Build update document and attachment

    $self->updatedoc->{'type'} = 'aip';
    $self->updatedoc->{'noid'} = $self->noid;

    # Manifest is a 'document', ordered collection is a 'series'
    $self->updatedoc->{'sub-type'} = $self->attachment->[0]->{'type'};

# If not public, then not approved in old system (clean up cosearch/copresentation docs)
    if ( exists $self->document->{'public'} ) {
        $self->updatedoc->{'approved'} = JSON::true;
    }
    else {
        $self->updatedoc->{'approved'} = JSON::false;

    }

    # We may not care about these any more, but will decide later...
    foreach my $field ( 'label', 'pubmin', 'pubmax', 'canonicalDownload' ) {
        if ( defined $self->attachment->[0]->{$field} ) {
            $self->updatedoc->{$field} = $self->attachment->[0]->{$field};
        }
    }

## Determine what collections this manifest or collection is in
    $self->{collections}        = {};
    $self->{orderedcollections} = {};

    $self->findCollections( $self->noid );

    # Ignore parent key from issueinfo records.
    # Concept of 'parent' going away as part of retiring 'issueinfo' records.
    delete $self->attachment->[0]->{'pkey'};
    my @parents = keys %{ $self->{orderedcollections} };
    if (@parents) {
        if ( @parents != 1 ) {
            warn "A member of more than a single ordered collection\n";
        }
        my $parent = shift @parents;
        if ($parent) {

            # Old platform didn't include 'series' records in collections.
            delete $self->{collections}->{$parent};
            $self->attachment->[0]->{'pkey'} = $parent;
            $self->updatedoc->{'parent'} = $parent;

            # The noid was stored in case needed.
            my $noid = $self->{orderedcollections}->{$parent};

            # This is all going away, so doen't have to be ideal design.
            # This is how we create a sequence at the moment.
            my $parentdoc =
              $self->accessdb->get_document( uri_escape_utf8($noid) );

            if ($parentdoc) {
                if ( ( ref $parentdoc->{members} ) eq "ARRAY" ) {
                    my $seq;
                    foreach my $i ( 0 .. ( @{ $parentdoc->{members} } - 1 ) ) {
                        if ( $parentdoc->{members}->[$i]->{id} eq $self->noid )
                        {
                            $seq = $i + 1;
                            last;
                        }
                    }
                    if ( defined $seq ) {

                        # Was a string, needs to be a string.
                        $self->attachment->[0]->{'seq'} = "$seq";
                        $self->updatedoc->{'seq'} = "$seq";
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
    }

    if ( !exists $self->updatedoc->{'parent'} ) {
        $self->updatedoc->{'noparent'} = JSON::true;
    }

    # Always set collection -- will be '' if no collections.
    $self->updatedoc->{collectionseq} =
      join( ',', keys %{ $self->{collections} } );

    # Create document if it doesn't already exist
    $self->internalmetadb->update_basic_full( $slug, {} );

    my $return = $self->internalmetadb->put_attachment(
        $slug,
        {
            type      => "application/json",
            content   => encode_json $self->attachment,
            filename  => "hammer.json",
            updatedoc => $self->updatedoc
        }
    );
    if ( $return != 201 ) {
        die "Return code $return for internalmetadb->put_attachment($slug)\n";
    }
}

# Clear out any other document that has this noid (slug has changed)
sub clearNoidDocument {
    my ( $self, $slug ) = @_;

    $self->internalmetadb->type("application/json");
    my $url = "/" . $self->internalmetadb->database . "/_design/tdr/_view/noid";

    my $res = $self->internalmetadb->post(
        $url,
        {
            keys         => [ $self->noid ],
            include_docs => JSON::true
        },
        { deserializer => 'application/json' }
    );
    if ( $res->code != 200 ) {
        die "clearNoidDocument: $url "
          . $self->noid
          . " return code: "
          . $res->code . "\n";
    }

    foreach my $doc ( @{ $res->data->{rows} } ) {
        my $thisslug = $doc->{id};
        next if $thisslug eq $slug;

        my $thisrev = $doc->{doc}->{_rev};

        my $url = "/"
          . $self->internalmetadb->database . "/"
          . uri_escape_utf8($thisslug);
        my $res2 = $self->internalmetadb->delete( $url, { rev => $thisrev } );

        if ( $res->code != 200 ) {
            die "clearNoidDocument: DELETE $url return code: "
              . $res->code . "\n";
        }
        else {
            $self->log->info( "Deleted duplicate with same noid="
                  . $self->noid
                  . " ($thisslug)" );
        }
    }
}

sub findCollections {
    my ( $self, $noid ) = @_;

    my @lookupnoid;
    my %collections;

    push @lookupnoid, $noid;

    # Keep looking until there is nothing new
    while (@lookupnoid) {
        my $noid = shift @lookupnoid;

        my $foundcollections = $self->accessdb->getCollections($noid);
        die "Can't getCollections()\n" if ( !$foundcollections );

        foreach my $collection ( @{$foundcollections} ) {
            if ( !exists $collections{ $collection->{'id'} } ) {
                $collections{ $collection->{'id'} } = 1;
                push @lookupnoid, $collection->{'id'};
            }
        }
    }

    foreach my $collection ( keys %collections ) {
        my $slim = $self->accessdb->getSlim($collection);

        if ( exists $slim->{slug} ) {
            my $slug = $slim->{slug};
            if ( !exists $self->{collections}->{$slug} ) {
                $self->{collections}->{$slug} = $collection;
            }
            if ( exists $slim->{behavior}
                && ( $slim->{behavior} ne "unordered" ) )
            {
                $self->{orderedcollections}->{$slug} = $collection;
            }
        }
    }
}

sub getIIIFText {
    my ( $self, $text ) = @_;

    foreach my $try ( "none", "en", "fr" ) {
        if ( exists $text->{$try} ) {
            return $text->{$try};
        }
    }
}

1;
