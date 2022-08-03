package CIHM::Meta::ImportOCR::Process;

use 5.014;
use strict;
use Try::Tiny;
use JSON;
use Switch;
use URI::Escape;
use XML::LibXML;
use XML::LibXSLT;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use File::Basename;
use File::Temp;
use Fcntl qw(SEEK_SET SEEK_CUR SEEK_END);    # better than using 0, 1, 2

use Data::Dumper;

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::ImportOCR::Process->new() not a hash\n";
    }
    $self->{args} = $args;

    if ( !$self->log ) {
        die "Log::Log4perl object parameter is mandatory\n";
    }
    if ( !$self->swift ) {
        die "swift object parameter is mandatory\n";
    }
    if ( !$self->dipstagingdb ) {
        die "dipstagingdb object parameter is mandatory\n";
    }
    if ( !$self->aip ) {
        die "Parameter 'aip' is mandatory\n";
    }
    $self->{divs} = [];
    return $self;
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}

sub envargs {
    my $self = shift;
    return $self->args->{args};
}

sub aip {
    my $self = shift;
    return $self->args->{aip};
}

sub log {
    my $self = shift;
    return $self->args->{log};
}

sub canvasdb {
    my $self = shift;
    return $self->args->{canvasdb};
}

sub dipstagingdb {
    my $self = shift;
    return $self->args->{dipstagingdb};
}

sub accessdb {
    my $self = shift;
    return $self->args->{accessdb};
}

sub dipdoc {
    my $self = shift;
    return $self->{dipdoc};
}

sub swift {
    my $self = shift;
    return $self->args->{swift};
}

sub access_metadata {
    my $self = shift;
    return $self->envargs->{access_metadata};
}

sub access_files {
    my $self = shift;
    return $self->envargs->{access_files};
}

sub preservation_files {
    my $self = shift;
    return $self->envargs->{preservation_files};
}

sub xml {
    my $self = shift;
    return $self->{xml};
}

sub xpc {
    my $self = shift;
    return $self->{xpc};
}

sub divs {
    my ($self) = @_;
    return $self->{divs};
}

sub canvases {
    my ($self) = @_;
    return $self->{canvases};
}

sub filemetadata {
    my $self = shift;
    return $self->{filemetadata};
}

sub process {
    my ($self) = @_;

    $self->loadDipDoc();

    $self->log->info( $self->aip . " Processing" );

    $self->parseMETS();

    # TODO: Check if there is any OCR data before loading FileMeta

    $self->loadFileMeta();

    # Item is in div 0
    my $div   = $self->divs->[0];
    my $label = $div->{label};

    if ( scalar @{ $self->divs } == 1 ) {

        # Silent success?
        $self->log->info(
            $self->aip . " Nothing to do when there are no pages." );
        return;
    }

    # This is a hack to support the records currently
    # in the custom preservatin platform.
    # There is only ever one multi-page PDF.

    # In the future this would be a check of any PDF file to see
    # if they are single page (canvas attached to type="manifest") or
    # multi-page (potentially multiple type="pdf" documents from single AIP)

    # OCR PDF's won't be part of AIPs and their METS records
    my $borndigital = $self->bornDigital();
    if ($borndigital) {

        # Silent success?
        $self->log->info(
            $self->aip . " Nothing to do for Born Digital PDF files." );
        return;
    }

    # Now we have some work to do.
    $self->ocrCanvases();
}

sub get_metadata {
    my ( $self, $file ) = @_;

    # Will retry for a second time.
    my $count = 2;

    my $object = $self->aip . "/$file";
    while ( $count-- ) {
        my $r = $self->swift->object_get( $self->preservation_files, $object );
        if ( $r->code == 200 ) {
            return $r->content;
        }
        elsif ( $r->code == 599 ) {
            warn(   "Accessing $object returned code (trying again): "
                  . $r->code
                  . "\n" );
        }
        else {
            die( "Accessing $object returned code: " . $r->code . "\n" );
        }
    }
}

sub parseMETS {
    my ($self) = @_;

    my $metsdir  = 'data/sip/data';
    my $metspath = $metsdir . '/metadata.xml';
    my $type     = 'physical';

    $self->{xml} =
      XML::LibXML->new->parse_string( $self->get_metadata($metspath) );
    $self->{xpc} = XML::LibXML::XPathContext->new;
    $self->xpc->registerNs( 'mets',  "http://www.loc.gov/METS/" );
    $self->xpc->registerNs( 'xlink', "http://www.w3.org/1999/xlink" );

    my @nodes =
      $self->xpc->findnodes( "descendant::mets:structMap[\@TYPE=\"$type\"]",
        $self->xml );
    if ( scalar(@nodes) != 1 ) {
        die "Found " . scalar(@nodes) . " structMap(TYPE=$type)\n";
    }
    foreach
      my $div ( $self->xpc->findnodes( 'descendant::mets:div', $nodes[0] ) )
    {
        my $index = scalar @{ $self->divs };
        my $type  = $div->getAttribute('TYPE');
        if (   !$index
            && ( $type ne 'document' )
            && ( $type ne 'issue' )
            && ( $type ne 'series' ) )
        {
            die
"First DIV of METS isn't type=document|issue|series , but type=$type\n";
        }
        if ( $index && ( $type ne 'page' ) ) {
            die "Not-first DIV of METS isn't type=page, but type=$type\n";
        }

        my %attr;
        $attr{'label'} = $div->getAttribute('LABEL');
        my $dmdid = $div->getAttribute('DMDID');
        if ($dmdid) {
            my @dmdsec =
              $self->xpc->findnodes( "descendant::mets:dmdSec[\@ID=\"$dmdid\"]",
                $self->xml );
            if ( scalar(@dmdsec) != 1 ) {
                die "Found " . scalar(@dmdsec) . " dmdSec for ID=$dmdid\n";
            }
            my @md = $dmdsec[0]->nonBlankChildNodes();
            if ( scalar(@md) != 1 ) {
                die "Found " . scalar(@md) . " children for dmdSec ID=$dmdid\n";
            }
            my @types = split( /:/, $md[0]->nodeName );
            my $type = pop(@types);

            $attr{'dmd.id'}     = $dmdid;
            $attr{'dmd.type'}   = $type;
            $attr{'dmd.mime'}   = $md[0]->getAttribute('MIMETYPE');
            $attr{'dmd.mdtype'} = $md[0]->getAttribute('MDTYPE');
            if ( $attr{'dmd.mdtype'} eq 'OTHER' ) {
                $attr{'dmd.mdtype'} = $md[0]->getAttribute('OTHERMDTYPE');
            }
        }

        foreach my $fptr ( $self->xpc->findnodes( 'mets:fptr', $div ) ) {
            my $fileid = $fptr->getAttribute('FILEID');

            my @file =
              $self->xpc->findnodes( "descendant::mets:file[\@ID=\"$fileid\"]",
                $self->xml );
            if ( scalar(@file) != 1 ) {
                die "Found " . scalar(@file) . " for file ID=$fileid\n";
            }
            my $use = $file[0]->getAttribute('USE');

            # If the file doesn't have USE=, check parent fileGrp
            if ( !$use ) {
                my $filegrp = $file[0]->parentNode;
                $use = $filegrp->getAttribute('USE');
                if ( !$use ) {
                    die "Can't find USE= attribute for file ID=$fileid\n";
                }
            }

            # never used...
            next if $use eq 'canonical';

            my $mimetype = $file[0]->getAttribute('MIMETYPE');

            if ( $use eq 'derivative' ) {
                if ( $mimetype eq 'application/xml' ) {
                    $use = 'ocr';
                }
                elsif ( $mimetype eq 'application/pdf' ) {
                    $use = 'distribution';
                }
            }

            my @flocat = $self->xpc->findnodes( "mets:FLocat", $file[0] );
            if ( scalar(@flocat) != 1 ) {
                die "Found " . scalar(@flocat) . " FLocat file ID=$fileid\n";
            }

            $attr{ $use . '.mimetype' } = $mimetype;
            $attr{ $use . '.flocat' }   = $self->aipfile(
                $metsdir, 'FLocat',
                $flocat[0]->getAttribute('LOCTYPE'),
                $flocat[0]->getAttribute('xlink:href')
            );
        }

        push @{ $self->divs }, \%attr;
    }
}

sub aipfile {
    my ( $self, $metsdir, $type, $loctype, $href ) = @_;

    if ( $loctype eq 'URN' ) {
        if ( $type eq 'FLocat' ) {
            $href = "files/$href";
        }
        else {
            $href = "metadata/$href";
        }
    }
    return substr( File::Spec->rel2abs( $href, '//' . $metsdir ), 1 );
}

sub bornDigital {
    my ($self) = @_;

# It is born digital if the page divs only have dmd information (txtmap made from PDF) and a label.
    for my $index ( 1 .. ( scalar @{ $self->divs } ) - 1 ) {
        foreach my $key ( keys %{ $self->divs->[$index] } ) {
            if ( ( $key ne 'label' ) && ( substr( $key, 0, 4 ) ne 'dmd.' ) ) {
                return 0;
            }
        }
    }
    return 1;
}

sub ocrCanvases {
    my ($self) = @_;

    my $canvascount = ( scalar @{ $self->divs } ) - 1;

    my $distributionPDF = $self->divs->[0]->{'distribution.flocat'};
    my $hasPDF;
    my $hasOCR;

    # Create array of canvases to look up.
    my @lookup;
    for my $index ( 0 .. $canvascount - 1 ) {

        # Components in div 1+
        my $div    = $self->divs->[ $index + 1 ];
        my $master = $div->{'master.flocat'};
        die "Missing Master for index=$index\n" if ( !$master );

        my $fm = $self->filemetadata->{$master};
        die "Missing filemetadata for $master" if ( !$fm );

        # PDF's were always pointers to files
        $hasPDF = JSON::true if ( defined $div->{'distribution.flocat'} );

        # OCR data could be the DMD of the div, or a file pointer with a USE=
        $hasOCR = JSON::true if ( defined $div->{'ocr.flocat'} );
        $hasOCR = JSON::true if ( defined $div->{'dmd.mdtype'} );

        push @lookup, [ $fm->{name}, $fm->{bytes}, $fm->{hash} ];
    }

    if ( !$distributionPDF && !$hasOCR && !$hasPDF ) {
        $self->log->info(
            $self->aip . ": Nothing to do as there is no OCR Data\n" );
        return;
    }

    # Look up existing canvases.
    my $res = $self->canvasdb->post(
        "/_design/access/_view/cihmsource?reduce=false&include_docs=true",
        { keys         => \@lookup },
        { deserializer => 'application/json' }
    );
    if ( $res->code != 200 ) {
        if ( defined $res->response->content ) {
            warn $res->response->content . "\n";
        }
        die "lookup in cihmsource return code: " . $res->code . "\n";
    }

    my %foundcanvas;
    foreach my $canvas ( @{ $res->data->{rows} } ) {
        if ( exists $canvas->{doc} ) {
            my $thisdoc = $canvas->{doc};
            if (   exists $thisdoc->{source}
                && exists $thisdoc->{source}->{path} )
            {
                my $path = $thisdoc->{source}->{path};
                if ( exists $foundcanvas{$path} ) {

                    $self->log->info( $self->aip
                          . " Duplicate canvases: "
                          . $foundcanvas{$path}->{'_id'} . " and "
                          . $thisdoc->{'_id'} );
                }
                else {
                    $foundcanvas{$path} = $thisdoc;
                }
            }
        }
    }

    my $foundcount = scalar( keys %foundcanvas );
    $self->log->info(
        $self->aip . " Found $foundcount of $canvascount canvases." );
    return if ( !$foundcount );

    my $separatedir =
      File::Temp->newdir( "separatepdfXXXXX", TMPDIR => 1, CLEANUP => 1 );
    my @singlepagePDF;
    if ($distributionPDF) {
        my $object    = $self->aip . "/" . $distributionPDF;
        my $container = $self->preservation_files;
        my $temp      = File::Temp->new( UNLINK => 1, SUFFIX => '.pdf' );

        my $r = $self->swift->object_get( $container, $object,
            { write_file => $temp } );
        if ( $r->code != 200 ) {
            die(
"GET distribution PDF object=$object , container=$container returned: "
                  . $r->code
                  . "\n" );
        }
        my $pdfname = $temp->filename;
        close $temp;

        system( "/usr/bin/pdfseparate", $pdfname, "$separatedir/%09d.pdf" ) == 0
          or die(
            "Failure running pdfseparate $pdfname $separatedir/%09d.pdf: $!\n");

        opendir( DIR, $separatedir )
          or die "Can't open directory $separatedir: $!";
        @singlepagePDF = sort ( grep !/^\.\.?$/, readdir(DIR) );
        closedir DIR;

        my $pagecount = scalar(@singlepagePDF);
        if ( $pagecount != $canvascount ) {
            warn "$canvascount canvases != $pagecount pages in $object\n";
            undef @singlepagePDF;
        }
    }

    my @updateids;

    # Walk though canvases to see what OCR data needs to be copied
    for my $index ( 0 .. $canvascount - 1 ) {

        # Components in div 1+
        my $div    = $self->divs->[ $index + 1 ];
        my $master = $div->{'master.flocat'};
        my $path   = $self->aip . "/" . $master;

        my $thispdf;
        if ( defined $singlepagePDF[$index] ) {
            $thispdf = $separatedir . "/" . $singlepagePDF[$index];
        }

        # We only care about canvases that were found
        if ( exists $foundcanvas{$path} ) {
            my $modified;

            my $canvas = $foundcanvas{$path};
            my $noid   = $canvas->{'_id'};

            # Clean out empty hashes
            if ( defined $canvas->{'ocrPdf'}
                && !( keys %{ $canvas->{'ocrPdf'} } ) )
            {
                delete $canvas->{'ocrPdf'};
                $modified = JSON::true;
            }

            # If OCR XML not yet set
            if ( !exists $canvas->{'ocrType'} ) {

                # Old style mdWrap
                if ( exists $div->{'dmd.type'} ) {
                    if ( $div->{'dmd.type'} ne 'mdWrap' ) {
                        die "component $index dmd.type isn't mdWrap\n";
                    }
                    my $dmdId   = $div->{'dmd.id'};
                    my $dmdType = uc( $div->{'dmd.mdtype'} );

                    my @dmdsec =
                      $self->xpc->findnodes(
                        "descendant::mets:dmdSec[\@ID=\"$dmdId\"]",
                        $self->xml );
                    my @md        = $dmdsec[0]->nonBlankChildNodes();
                    my @mdrecords = $md[0]->nonBlankChildNodes();
                    my @records   = $mdrecords[0]->nonBlankChildNodes();
                    my $xmlrecord = $records[0]->toString(0);
                    my $dmdRecord =
                        utf8::is_utf8($xmlrecord)
                      ? Encode::encode_utf8($xmlrecord)
                      : $xmlrecord;
                    my $dmdDigest = md5_hex($dmdRecord);

                    # Ick: Ignoring fake data...
                    # https://github.com/crkn-rcdr/Access-Platform/issues/362
                    #
                    if ( $dmdDigest ne '0495ad04435509d210d2d866a0a120b3'
                        || length($dmdRecord) != 95 )
                    {

                        # Store the OCR XML
                        my $object = $noid . '/ocr' . $dmdType . '.xml';
                        my $r =
                          $self->swift->object_head( $self->access_metadata,
                            $object );
                        if ( $r->code == 404 || ( $r->etag ne $dmdDigest ) ) {
                            $r =
                              $self->swift->object_put( $self->access_metadata,
                                $object, $dmdRecord );
                            if ( $r->code != 201 ) {
                                warn "Failed writing $object - returned "
                                  . $r->code . "\n";
                            }
                            elsif ( $r->etag ne $dmdDigest ) {
                                die
"object_put $object didn't return matching etag\n";
                            }
                            else {
                                $canvas->{'ocrType'} = lc($dmdType);
                                $modified = JSON::true;
                            }
                        }
                        elsif ( $r->code != 200 ) {
                            warn "Head for $object - returned "
                              . $r->code . "\n";
                        }
                        else {
                            $canvas->{'ocrType'} = lc($dmdType);
                            $modified = JSON::true;
                        }
                    }
                }

                # New style stored XML
                if ( exists $div->{'ocr.flocat'} ) {
                    my $object = $self->aip . '/' . $div->{'ocr.flocat'};
                    my $r =
                      $self->swift->object_get( $self->preservation_files,
                        $object );
                    if ( $r->code != 200 ) {
                        die(    "Accessing $object returned code: "
                              . $r->code
                              . "\n" );
                    }
                    my $xmlrecord = $r->content;
                    my $etag      = $r->etag;
                    my $dmdRecord =
                        utf8::is_utf8($xmlrecord)
                      ? Encode::encode_utf8($xmlrecord)
                      : $xmlrecord;

                    my $isTxtmap = ( $dmdRecord =~ m/\<(txt:){0,1}txtmap/m );
                    my $dmdType = $isTxtmap ? "TXTMAP" : "ALTO";

                    my $object = $noid . '/ocr' . $dmdType . '.xml';
                    my $r =
                      $self->swift->object_head( $self->access_metadata,
                        $object );
                    if ( $r->code == 404 || ( $r->etag ne $etag ) ) {
                        $r =
                          $self->swift->object_put( $self->access_metadata,
                            $object, $dmdRecord );
                        if ( $r->code != 201 ) {
                            warn "Failed writing $object - returned "
                              . $r->code . "\n";
                        }
                        elsif ( $r->etag ne $etag ) {
                            die
"object_put $object didn't return matching etag\n";
                        }
                        else {
                            $canvas->{'ocrType'} = lc($dmdType);
                            $modified = JSON::true;
                        }
                    }
                    elsif ( $r->code != 200 ) {
                        warn "Head for $object - returned " . $r->code . "\n";
                    }
                    else {
                        $canvas->{'ocrType'} = lc($dmdType);
                        $modified = JSON::true;
                    }
                }
            }

            # If OCR PDF not yet set
            if (   ( !defined $canvas->{'ocrPdf'} )
                || ( !defined $canvas->{'ocrPdf'}->{'extension'} ) )
            {
                if ( exists $div->{'distribution.flocat'} ) {
                    warn "Distribution file not PDF for $index\n"
                      if (
                        $div->{'distribution.mimetype'} ne 'application/pdf' );

                    my $path = $self->aip . "/" . $div->{'distribution.flocat'};
                    my $filemeta =
                      $self->filemetadata->{ $div->{'distribution.flocat'} };

                    # Parse using the valid list of extensions.
                    # Are they all valid for distribution?
                    # Have we ever used other than .pdf?
                    my ( $base, $dir, $ext ) =
                      fileparse( $path,
                        ( "pdf", "jpg", "jp2", "jpeg", "tif", "tiff" ) );

                    if ( !$ext ) {
                        die "Extension from from $path is not valid\n";
                    }

                    my $newpath = $noid . "." . $ext;

                    my $response = $self->swift->object_copy(
                        $self->preservation_files, $path,
                        $self->access_files,       $newpath
                    );
                    if ( $response->code != 201 ) {
                        die "object_copy("
                          . $self->preservation_files . ","
                          . $path . ","
                          . $self->access_files . ","
                          . $newpath
                          . ") returned "
                          . $response->code . " - "
                          . $response->message . "\n";

                    }

                    $canvas->{'ocrPdf'} = {
                        'extension' => $ext,
                        'size'      => $filemeta->{'bytes'},
                        'md5'       => $filemeta->{'hash'}
                    };
                    $modified = JSON::true;

                }
                elsif ($thispdf) {
                    my $object = $noid . ".pdf";
                    my $bytes  = -s $thispdf;
                    die "$thispdf is empty\n" if !$bytes;

                    open( my $fh, '<:raw', $thispdf )
                      or die "Could not open file '$thispdf' $!\n";

                    my $md5 = Digest::MD5->new->addfile($fh)->hexdigest;

                    seek $fh, 0, SEEK_SET;

                    my $putresp = $self->swift->object_put( $self->access_files,
                        $object, $fh, {} );
                    if ( $putresp->code != 201 ) {
                        die(    "object_put of $object returned "
                              . $putresp->code . " - "
                              . $putresp->message
                              . "\n" );
                    }
                    elsif ( $putresp->etag ne $md5 ) {
                        die "object_put $object didn't return matching etag\n";
                    }
                    close $fh;

                    $canvas->{'ocrPdf'} = {
                        'extension' => 'pdf',
                        'size'      => $bytes,
                        'md5'       => $md5
                    };
                    $modified = JSON::true;
                }
            }

            #print Data::Dumper->Dump( [$canvas],
            #    [ $modified ? "Put" : "ignore" ] );

            # Store if modified...
            if ($modified) {

                push @updateids, $noid;

                my $data = $self->canvasPutDocument( $noid, $canvas );
                die "Put of canvas $noid failed\n" if !$data;
            }

        }
    }

    my $updatecount = scalar(@updateids);

    $self->log->info( $self->aip
          . " Updated $updatecount of $foundcount ($canvascount) canvases." );

    if ($updatecount) {

        # Look up what manifests these canvases are in
        my $url = "/_design/noid/_view/canvasnoids?reduce=false";
        my $res = $self->accessdb->post(
            $url,
            { keys         => \@updateids },
            { deserializer => 'application/json' }
        );
        if ( $res->code != 200 ) {
            if ( defined $res->response->content ) {
                warn $res->response->content . "\n";
            }
            die "lookup in canvasnoids return code: " . $res->code . "\n";
        }

        my %foundaccess;
        foreach my $accessdoc ( @{ $res->data->{rows} } ) {
            $foundaccess{ $accessdoc->{id} } = 1;
        }

        # And force those manifests to be processed
        foreach my $accessid ( keys %foundaccess ) {
            my $url =
              "/_design/access/_update/forceUpdate/" . uri_escape($accessid);
            my $res = $self->accessdb->post( $url, {},
                { deserializer => 'application/json' } );
            if ( $res->code != 201 ) {
                if ( defined $res->response->content ) {
                    warn $res->response->content . "\n";
                }
                warn "Attempt to force update for $accessid : "
                  . $res->code . "\n";
            }
        }
    }

}

sub loadFileMeta {
    my $self = shift;

    $self->{filemetadata} = {};

    my $prefix = $self->aip . '/';

    # List of objects with AIP as prefix
    my %containeropt = ( "prefix" => $prefix );

    # Need to loop possibly multiple times as Swift has a maximum of
    # 10,000 names.
    my $more = 1;
    while ($more) {
        my $bagdataresp =
          $self->swift->container_get( $self->preservation_files,
            \%containeropt );
        if ( $bagdataresp->code != 200 ) {
            die "container_get("
              . $self->preservation_files
              . ") for $prefix returned "
              . $bagdataresp->code . " - "
              . $bagdataresp->message . "\n";
        }
        $more = scalar( @{ $bagdataresp->content } );
        if ($more) {
            $containeropt{'marker'} =
              $bagdataresp->content->[ $more - 1 ]->{name};
            foreach my $object ( @{ $bagdataresp->content } ) {
                my $file = substr $object->{name}, ( length $prefix );
                $self->filemetadata->{$file} = $object;
            }
        }
    }
}

sub loadDipDoc {
    my $self = shift;

    my $url = "/" . uri_escape( $self->aip );
    my $res =
      $self->dipstagingdb->get( $url, {},
        { deserializer => 'application/json' } );
    if ( $res->code != 200 ) {
        if ( defined $res->response->content ) {
            warn $res->response->content . "\n";
        }
        die "dipstagingdb get of '"
          . $self->aip
          . "' ($url) return code: "
          . $res->code . "\n";
    }
    $self->{dipdoc} = $res->data;
}

sub canvasPutDocument {
    my ( $self, $docid, $document ) = @_;

    $self->canvasdb->type("application/json");
    my $url = "/" . uri_escape($docid);
    my $res = $self->canvasdb->put( $url, $document,
        { deserializer => 'application/json' } );
    if ( $res->code == 201 ) {
        return $res->data;
    }
    else {
        warn "PUT $url return code: " . $res->code . "\n";
        return;
    }
}

1;
