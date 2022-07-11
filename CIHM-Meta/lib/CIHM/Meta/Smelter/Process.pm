package CIHM::Meta::Smelter::Process;

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
use Image::Magick;

#use Data::Dumper;

=head1 NAME

CIHM::Meta::Smelter::Process - Handles the processing of individual AIPs for CIHM::Meta::Smelter

=head1 SYNOPSIS

    my $process = CIHM::Meta::Smelter::Process->new($args);
      where $args is a hash of arguments.

=cut

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::Hammer::Process->new() not a hash\n";
    }
    $self->{args} = $args;

    if ( !$self->log ) {
        die "Log::Log4perl object parameter is mandatory\n";
    }
    if ( !$self->swiftaccess ) {
        die "swiftaccess object parameter is mandatory\n";
    }
    if ( !$self->swiftpreservation ) {
        die "swiftpreservation object parameter is mandatory\n";
    }
    if ( !$self->dipstagingdb ) {
        die "dipstagingdb object parameter is mandatory\n";
    }
    if ( !$self->cantaloupe ) {
        die "cantaloupe object parameter is mandatory\n";
    }
    if ( !$self->aip ) {
        die "Parameter 'aip' is mandatory\n";
    }
    $self->{divs}     = [];
    $self->{manifest} = {};
    $self->{canvases} = {};
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

sub noidsrv {
    my $self = shift;
    return $self->args->{noidsrv};
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

sub cantaloupe {
    my $self = shift;
    return $self->args->{cantaloupe};
}

sub swiftaccess {
    my $self = shift;
    return $self->args->{swiftaccess};
}

sub swift_access_metadata {
    my $self = shift;
    return $self->envargs->{swift_access_metadata};
}

sub swift_access_files {
    my $self = shift;
    return $self->envargs->{swift_access_files};
}

sub swiftpreservation {
    my $self = shift;
    return $self->args->{swiftpreservation};
}

sub swift_preservation_files {
    my $self = shift;
    return $self->envargs->{swift_preservation_files};
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

sub manifest {
    my ($self) = @_;
    return $self->{manifest};
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
    my $slug = $self->dipdoc->{slug};
    if ( !$slug || $slug eq '' ) {
        die "Missing slug\n";
    }

    $self->log->info( $self->aip . " Processing  Slug=$slug" );

    if ( my $getres = $self->getSlug($slug) ) {
        die "Slug=$slug already exists\n";
    }

    $self->manifest->{slug} = $slug;

    $self->loadFileMeta();

    $self->parseMETS();

    # Item is in div 0
    my $div   = $self->divs->[0];
    my $label = $div->{label};

    if ( !$label || $label eq '' ) {
        die "Missing item label\n";
    }
    $self->manifest->{label}->{none} = $label;

# This is a hack to support the records currently in the custom preservatin platform.
# There is only ever one multi-page PDF.

# In the future this would be a check of any PDF file to see if they are single page (canvas attached to type="manifest")
# or multi-page (potentially multiple type="pdf" documents from single AIP)

    # OCR PDF's won't be part of AIPs and their METS records
    my $borndigital = $self->bornDigital();
    if ($borndigital) {
        $self->manifest->{type} = 'pdf';

        # Distribution is the born digital file
        if ( defined $div->{'distribution.flocat'} ) {
            die "Distribution not PDF"
              if ( $div->{'distribution.mimetype'} ne 'application/pdf' );
            $self->manifest->{'file'} = {
                'path' => $self->aip . "/" . $div->{'distribution.flocat'},
                'size' =>
                  $self->filemetadata->{ $div->{'distribution.flocat'} }
                  ->{'bytes'},
                'md5' =>
                  $self->filemetadata->{ $div->{'distribution.flocat'} }
                  ->{'hash'}
            };
        }
    }
    else {
        $self->manifest->{type} = 'manifest';
        $self->findCreateCanvases();
        $self->enhanceCanvases;
    }

    $self->setManifestNoid();
    $self->dmdManifest();
    $self->writeManifest();
}

sub get_metadata {
    my ( $self, $file ) = @_;

    # Will retry for a second time.
    my $count = 2;

    my $object = $self->aip . "/$file";
    while ( $count-- ) {
        my $r =
          $self->swiftpreservation->object_get( $self->swift_preservation_files,
            $object );
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
        if ( !$index && ( $type ne 'document' ) && ( $type ne 'issue' ) ) {
            die
              "First DIV of METS isn't type=document|issue| , but type=$type\n";
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

sub dmdManifest {
    my $self = shift;

    # Item is in div 0
    my $div  = $self->divs->[0];
    my $noid = $self->manifest->{'_id'};

    if ( $div->{'dmd.type'} ne 'mdWrap' ) {
        die "item dmd isn't in mdWrap\n";
    }
    my $dmdId   = $div->{'dmd.id'};
    my $dmdType = uc( $div->{'dmd.mdtype'} );

    my @dmdsec =
      $self->xpc->findnodes( "descendant::mets:dmdSec[\@ID=\"$dmdId\"]",
        $self->xml );
    my @md        = $dmdsec[0]->nonBlankChildNodes();
    my @mdrecords = $md[0]->nonBlankChildNodes();
    my @records   = $mdrecords[0]->nonBlankChildNodes();
    my $xmlrecord = $records[0]->toString(0);
    my $dmdRecord =
      utf8::is_utf8($xmlrecord) ? Encode::encode_utf8($xmlrecord) : $xmlrecord;
    my $dmdDigest = md5_hex($dmdRecord);

    my $object = $noid . '/dmd' . $dmdType . '.xml';
    my $r =
      $self->swiftaccess->object_head( $self->swift_access_metadata, $object );
    if ( $r->code == 404 || ( $r->etag ne $dmdDigest ) ) {
        $r = $self->swiftaccess->object_put( $self->swift_access_metadata,
            $object, $dmdRecord );
        if ( $r->code != 201 ) {
            if ( defined $r->response->content ) {
                warn $r->response->content . "\n";
            }
            die "Failed writing $object - returned " . $r->code . "\n";
        }
        elsif ( $r->etag ne $dmdDigest ) {
            die "object_put didn't return matching etag\n";
        }
    }
    elsif ( $r->code != 200 ) {
        if ( defined $r->response->content ) {
            warn $r->response->content . "\n";
        }
        die "Head for $object - returned " . $r->code . "\n";
    }
    $self->manifest->{'dmdType'} = lc($dmdType);
}

sub findCreateCanvases {
    my ($self) = @_;

    my $canvascount = ( scalar @{ $self->divs } ) - 1;

    # Create array of canvases to look up.
    my @lookup;
    for my $index ( 0 .. $canvascount - 1 ) {

        # Components in div 1+
        my $div    = $self->divs->[ $index + 1 ];
        my $master = $div->{'master.flocat'};
        die "Missing Master for index=$index\n" if ( !$master );

        my $fm = $self->filemetadata->{$master};
        die "Missing filemetadata for $master" if ( !$fm );

        push @lookup, [ $fm->{name}, $fm->{bytes}, $fm->{hash} ];
    }

    # Look up if these canvases already exist.
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
    if ($foundcount) {
        $self->log->info( $self->aip . " Found $foundcount existing canvases" );
    }

    # Create any missing canvases while setting up manifest
    my @missingcanvases;
    $self->manifest->{'canvases'} = [];
    for my $index ( 0 .. $canvascount - 1 ) {

        # Components in div 1+
        my $div = $self->divs->[ $index + 1 ];
        $self->manifest->{'canvases'}->[$index]->{label}->{none} =
          $div->{label};
        my $master = $div->{'master.flocat'};
        my $path   = $self->aip . "/" . $master;

        if (   ( exists $foundcanvas{$path} )
            && ( exists $foundcanvas{$path}->{'_id'} ) )
        {
            $self->manifest->{'canvases'}->[$index]->{'id'} =
              $foundcanvas{$path}->{'_id'};
        }
        else {
            # Need to create new canvas.
            my $canvas = {
                source => { from => 'cihm', path => $path },
                master => {
                    path   => $path,
                    'mime' => $div->{'master.mimetype'},
                    'size' => $self->filemetadata->{$master}->{'bytes'},
                    'md5'  => $self->filemetadata->{$master}->{'hash'}
                }
            };
            push @missingcanvases, $canvas;
        }
    }

    # Store with noids any that didn't already exist.
    if (@missingcanvases) {
        my $canvascount = scalar(@missingcanvases);
        $self->log->info( $self->aip . " Creating $canvascount new canvases" );

        my @canvasnoids = @{ $self->mintNoids( $canvascount, 'canvases' ) };
        die "Couldn't allocate $canvascount canvas noids\n"
          if ( scalar @canvasnoids != $canvascount );
        for my $index ( 0 .. $canvascount - 1 ) {
            $missingcanvases[$index]->{'_id'} =
              $canvasnoids[$index];
        }

        my $res = $self->canvasdb->post(
            "/_bulk_docs",
            { docs         => \@missingcanvases },
            { deserializer => 'application/json' }
        );
        if ( $res->code != 201 ) {
            if ( defined $res->response->content ) {
                warn $res->response->content . "\n";
            }
            die "dbupdate of missing canvases return code: "
              . $res->code . "\n";
        }

        my %noidrevs;
        foreach my $update ( @{ $res->data } ) {
            if ( ( defined $update->{id} ) && ( defined $update->{rev} ) ) {
                $noidrevs{ $update->{id} } = $update->{rev};
            }
        }

        foreach my $thisdoc (@missingcanvases) {
            my $path = $thisdoc->{source}->{path};
            my $noid = $thisdoc->{'_id'};
            if ( !defined $noidrevs{$noid} ) {
                die "Try again! Couldn't find _rev field for noid=$noid\n";
            }
            $thisdoc->{'_rev'} = $noidrevs{$noid};
            $foundcanvas{$path} = $thisdoc;
        }

        for my $index ( 0 .. $canvascount - 1 ) {

            # Components in div 1+
            my $div = $self->divs->[ $index + 1 ];
            $self->manifest->{'canvases'}->[$index]->{label}->{none} =
              $div->{label};
            my $master = $div->{'master.flocat'};
            my $path   = $self->aip . "/" . $master;

            if (   ( exists $foundcanvas{$path} )
                && ( exists $foundcanvas{$path}->{'_id'} ) )
            {
                $self->manifest->{'canvases'}->[$index]->{'id'} =
                  $foundcanvas{$path}->{'_id'};
            }
            else {
                die "Canvas for $path still not found!\n";
            }
        }
    }

    $self->{canvases} = \%foundcanvas;
}

sub enhanceCanvases {
    my ($self) = @_;

    my $copiedcanvases = 0;
    foreach my $canvaskey ( keys %{ $self->canvases } ) {
        my $doc = $self->canvases->{$canvaskey};

        if ( exists $doc->{master} && exists $doc->{master}->{path} ) {

            # Image not copied yet
            my $path = $doc->{master}->{path};

            # Parse using the valid list of extensions.
            my ( $base, $dir, $ext ) =
              fileparse( $path, ( "jpg", "jp2", "jpeg", "tif", "tiff" ) );

            if ( !$ext ) {
                die "Extension from $path is not valid\n";
            }

            # Convert all images to JPG files.
            my $newext  = "jpg";
            my $newpath = $doc->{'_id'} . "." . $newext;

            my $preservationfile =
              File::Temp->new( UNLINK => 0, SUFFIX => "." . $ext );

            my $accessfile =
              File::Temp->new( UNLINK => 0, SUFFIX => "." . $newext );

            my $response =
              $self->swiftpreservation->object_get(
                $self->swift_preservation_files,
                $path, { write_file => $preservationfile } );
            if ( $response->code != 200 ) {
                die(    "GET preservation file object=$path , container="
                      . $self->swift_preservation_files
                      . " returned: "
                      . $response->code . " - "
                      . $response->message
                      . "\n" );
            }

            my $filemodified = $response->object_meta_header('File-Modified');

            my $preservationname = $preservationfile->filename;
            close $preservationfile;

            print
"TempName: $preservationname  modified=$filemodified  Preservation: $path  Access: $newpath\n";

            # Normmalize for Access

            my $magic = new Image::Magick;

            my $status = $magic->Read($preservationfile);
            if ($status) {
                my $error;
                switch ($status) {

                    # Skip Exif ImageUniqueID
                    case /Unknown field with tag 42016 / { }

# https://www.awaresystems.be/imaging/tiff/tifftags/privateifd/exif/imageuniqueid.html
                    case /Unknown field with tag 41728 / { }

# https://www.awaresystems.be/imaging/tiff/tifftags/privateifd/exif/filesource.html
                    case /Unknown field with tag 59932 /  { }   # 0xea1c	Padding
                    case /Exception 350: .*; tag ignored/ { }
                    else {
                        $error = 1;
                    }
                }
                if ($error) {
                    die "$path Read: $status\n";
                }
                else {
                    warn "$path Read: $status\n";
                }
            }

# Archivematica uses:
# convert "%fileFullName%" -sampling-factor 4:4:4 -quality 60 -layers merge "%outputDirectory%%prefix%%fileName%%postfix%.jpg"
# We are keeping quality to 80% instead.

            $magic->Set( "sampling-factor" => "4:4:4" );
            die "$path Set sampling-factor 4:4:4: $status\n"
              if "$status";

            $magic->Set( "quality" => 80 );
            die "$path Set Quality=80: $status\n"
              if "$status";

            $status = $magic->Layers( "method" => "merge" );
            die "$path Layers merge: $status\n"
              if !ref($status);

            my $accessfilename = $accessfile->filename;

            $status = $magic->Write($accessfilename);
            die "$path write $accessfilename: $status" if "$status";

            open( my $fh, '<:raw', $accessfilename )
              or die "Could not open file '$accessfilename' $!";

            my $filedata;

            read $fh, $filedata, -s $accessfilename
              or die "Could not read file `$accessfilename` $!";

            close $fh;

            $response =
              $self->swiftaccess->object_put( $self->swift_access_files,
                $newpath, $filedata, { 'File-Modified' => $filemodified } );

            if ( $response->code != 201 ) {
                die "PUT access file object=$newpath container="
                  . $self->swift_access_files
                  . " returned "
                  . $response->code . " - "
                  . $response->message . "\n";
            }

            # Get full replacement document
            my $newdoc = $self->canvasGetDocument( $doc->{'_id'} );

            # Set extension, and store
            $newdoc->{master}->{extension} = $newext;
            delete $newdoc->{master}->{path};

            my $data = $self->canvasPutDocument( $doc->{'_id'}, $newdoc );
            die "Put failed\n" if !$data;

            $newdoc->{'_rev'} = $data->{'rev'};
            $self->canvases->{$canvaskey} = $newdoc;

            $copiedcanvases++;
        }
    }

    if ($copiedcanvases) {
        $self->log->info(
            $self->aip . " Copied $copiedcanvases canvas images" );
    }

    # In theory everything is copied to Swift access storage,
    # so there shouldn't be any permission or other issues.
    my @updatecanvases;
    foreach my $canvaskey ( keys %{ $self->canvases } ) {
        my $doc = $self->canvases->{$canvaskey};

        my $modified;

        # Actually test to confirm that the canvas can be processed as an image.
        my $path =
          uri_escape_utf8( $doc->{'_id'} ) . "/full/!80,80/0/default.jpg";
        my $res =
          $self->cantaloupe->get( $path, {}, { deserializer => undef } );

        # We only care that it is successful in generating a small image.
        if ( $res->code != 200 ) {
            die "Cantaloupe call to "
              . $self->cantaloupe->server
              . "$path returned: "
              . $res->code . "\n";
        }

        # Now get the dimensions/etc.
        $path = uri_escape_utf8( $doc->{'_id'} ) . "/info.json";
        my $res = $self->cantaloupe->get( $path, {},
            { deserializer => 'application/json' } );

        # TODO: the 403 is a bit odd!
        if ( $res->code != 200 && $res->code != 403 ) {
            die "Cantaloupe call to "
              . $self->cantaloupe->server
              . "$path returned: "
              . $res->code . "\n";
        }
        if ( defined $res->data->{height} ) {
            $doc->{'master'}->{'height'} =
              $res->data->{height};
            $modified = JSON::true;
        }
        if ( defined $res->data->{width} ) {
            $doc->{'master'}->{'width'} =
              $res->data->{width};
            $modified = JSON::true;
        }
        if ($modified) {
            push @updatecanvases, $doc;
        }
    }

    # Store any that were modified
    if (@updatecanvases) {
        my $res = $self->canvasdb->post(
            "/_bulk_docs",
            { docs         => \@updatecanvases },
            { deserializer => 'application/json' }
        );
        if ( $res->code != 201 ) {
            if ( defined $res->response->content ) {
                warn $res->response->content . "\n";
            }
            die "Update after Cantaloupe dimension returned code: "
              . $res->code . "\n";
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
          $self->swiftpreservation->container_get(
            $self->swift_preservation_files,
            \%containeropt );
        if ( $bagdataresp->code != 200 ) {
            die "container_get("
              . $self->swift_preservation_files
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

# See https://github.com/crkn-rcdr/noid for details
sub mintNoids {
    my ( $self, $number, $type ) = @_;

    return [] if ( !$number );

    my $res = $self->noidsrv->post( "/mint/$number/$type", {},
        { deserializer => 'application/json' } );
    if ( $res->code != 200 ) {
        die "Fail communicating with noid server for /mint/$number/$type: "
          . $res->code . "\n";
    }
    return $res->data->{ids};
}

sub setManifestNoid {
    my ($self) = @_;

    my @manifestnoids = @{ $self->mintNoids( 1, 'manifest' ) };
    die "Couldn't allocate 1 manifest noid\n" if ( scalar @manifestnoids != 1 );
    $self->manifest->{'_id'} = $manifestnoids[0];
}

# TODO: For now a direct write to CouchDB, later through a Lapin interface
sub writeManifest {
    my ($self) = @_;

    my $res = $self->accessdb->post(
        "/_bulk_docs",
        { docs         => [ $self->manifest ] },
        { deserializer => 'application/json' }
    );
    if ( $res->code != 201 ) {
        if ( defined $res->response->content ) {
            warn $res->response->content . "\n";
        }
        die "dbupdate of 'manifest' return code: " . $res->code . "\n";
    }
}

# TODO: Use API once it exists
sub getSlug {
    my ( $self, $slug ) = @_;

    my $res = $self->accessdb->get(
        "/_design/access/_view/slug?key=" . encode_json($slug),
        {}, { deserializer => 'application/json' } );
    if ( $res->code == 404 ) {
        return;
    }
    elsif ( $res->code == 200 ) {
        if ( ref $res->data->{rows} eq 'ARRAY' ) {
            return pop @{ $res->data->{rows} };
        }
    }
    else {
        if ( defined $res->response->content ) {
            warn $res->response->content . "\n";
        }
        die "getSlug of '$slug' return code: " . $res->code . "\n";
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

sub canvasGetDocument {
    my ( $self, $docid ) = @_;

    $self->canvasdb->type("application/json");
    my $url = "/" . uri_escape($docid);
    my $res =
      $self->canvasdb->get( $url, {}, { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        return $res->data;
    }
    else {
        warn "GET $url return code: " . $res->code . "\n";
        return;
    }
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
