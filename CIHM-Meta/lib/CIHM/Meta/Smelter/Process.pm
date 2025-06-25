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
use Data::Dumper;
use Crypt::JWT qw(encode_jwt);
use LWP::UserAgent;

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

sub swift_retries {
    my $self = shift;
    return $self->envargs->{swift_retries};
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

sub mint_noid {
    my ($m, $noid_type) = @_;

    my $ark_noid_api_url = $ENV{ARK_server} . "/noid";
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
        "naan" =>"69429",
        "type_" =>$noid_type,                   
        "m" => $m        
    );
 
    # Initialize HTTP client
    my $ua = LWP::UserAgent->new;
 
    # Send the POST request to the NOID generation API
    my $response = $ua->post(
        $ark_noid_api_url,
        'Content-Type' => 'application/json',
        Authorization => "Bearer $token",
        Content => encode_json(\%payload),
    );
 
    # Check the response
    if ($response->is_success) {
        my $response_data = decode_json($response->decoded_content);
        return $response_data->{ark};
    } elsif ($response->code >= 400 && $response->code < 500) {
        return "API call failed: " . $response->status_line;
    } else {
        return "HTTP request failed: " . $response->status_line;
    }
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
 
    # Send the POST request to the NOID map API
    my $response = $ua->post(
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
        return "API call failed: " . $response->status_line;
    } else {
        return "HTTP request failed: " . $response->status_line;
    }
}

sub process {
    my ($self) = @_;

    $self->loadDipDoc();
    my $slug = $self->dipdoc->{slug};
    if ( !$slug || $slug eq '' ) {
        $self->log->info(
            $self->aip . " Processing (No manifest will be created)" );
    }
    else {
        $self->log->info( $self->aip . " Processing  Slug=$slug" );
        if ( my $getres = $self->getSlug($slug) ) {
            die "Slug=$slug already exists\n";
        }

        $self->{manifest} = {
            slug => $slug,
            label =>
              { none => "Import images into Access from aip=" . $self->aip },
            type => 'manifest'
        };
    }

    $self->loadFileMeta();
    $self->parseMETS();
    $self->findCreateCanvases();
    $self->enhanceCanvases;

    if ( exists $self->manifest->{slug} ) {
        $self->setManifestNoid();
        $self->writeManifest();

        $self->log->info( $self->manifest->{slug} );
        $self->log->info( $self->manifest->{'_id'} );
        map_noid($self->manifest->{slug}, $self->manifest->{'_id'} )
    }
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

sub findManifestCanvases {
    my ( $self, $foundcanvas ) = @_;

    my $canvascount = ( scalar @{ $self->divs } ) - 1;

    # Create dummy for any missing canvases while setting up manifest
    my @missingcanvases;
    $self->manifest->{'canvases'} = [];
    for my $index ( 0 .. $canvascount - 1 ) {

        # Components in div 1+
        my $div = $self->divs->[ $index + 1 ];
        $self->manifest->{'canvases'}->[$index]->{label}->{none} =
          $div->{label};
        my $master = $div->{'master.flocat'};
        my $path   = $self->aip . "/" . $master;

        if (   ( exists $foundcanvas->{$path} )
            && ( exists $foundcanvas->{$path}->{'_id'} ) )
        {
            # Some 'source' fields were missing data in some older records.
            if (   ( !exists $foundcanvas->{$path}->{'source'} )
                || ( !exists $foundcanvas->{$path}->{'source'}->{'size'} )
                || ( !exists $foundcanvas->{$path}->{'source'}->{'md5'} ) )
            {
                $foundcanvas->{$path}->{'source'} = {
                    from   => 'cihm',
                    path   => $path,
                    'size' => $self->filemetadata->{$master}->{'bytes'},
                    'md5'  => $self->filemetadata->{$master}->{'hash'}
                };

                my $data =
                  $self->canvasPutDocument( $foundcanvas->{$path}->{'_id'},
                    $foundcanvas->{$path} );

                die "Put of canvas failed during findManifestCanvases()\n"
                  if !$data;

                $foundcanvas->{$path}->{'_rev'} = $data->{'rev'};

            }

            $self->manifest->{'canvases'}->[$index]->{'id'} =
              $foundcanvas->{$path}->{'_id'};
        }
        else {
            # Need to create new canvas.

            # First, the oops check!
            if ( !defined $self->filemetadata->{$master}->{'bytes'}
                || ( $self->filemetadata->{$master}->{'bytes'} == 0 ) )
            {
                die "$path is a 0 length file!  The AIP must be fixed!\n";
            }

            my $canvas = {
                source => {
                    from   => 'cihm',
                    path   => $path,
                    'size' => $self->filemetadata->{$master}->{'bytes'},
                    'md5'  => $self->filemetadata->{$master}->{'hash'}
                },
                master => {
                    'mime' => $div->{'master.mimetype'},
                    'size' => $self->filemetadata->{$master}->{'bytes'},
                    'md5'  => $self->filemetadata->{$master}->{'hash'}
                }
            };
            push @missingcanvases, $canvas;
        }
    }
    return @missingcanvases;
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

        $self->log->info( $fm->{name} . " - " . $fm->{bytes}  . " - " .  $fm->{hash} );

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
    my @missingcanvases = $self->findManifestCanvases( \%foundcanvas );

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

        my @notfound = $self->findManifestCanvases( \%foundcanvas );
        if (@notfound) {
            $self->log->info(
                $self->aip . "  "
                  . Data::Dumper->Dump(
                    [ \@notfound ],
                    [qw(Manifest_Canvases_notfound)]
                  )
            );

            my @paths;
            foreach my $thisdoc (@notfound) {
                push @paths, $thisdoc->{master}->{path};
            }
            die "Paths still missing: @paths \n";
        }
    }

    $self->{canvases} = \%foundcanvas;

# Shouldn't be possible, but... https://github.com/crkn-rcdr/cihm-metadatabus/issues/40
    foreach my $i ( 0 .. ( @{ $self->manifest->{'canvases'} } - 1 ) ) {
        if ( !defined $self->manifest->{'canvases'}->[$i]->{'id'} ) {

            $self->log->info( $self->aip . "  "
                  . Data::Dumper->Dump( [ $self->manifest ], [qw(manifest)] ) );
            die "findCreateCanvases(): Missing ID for canvas index=$i\n";
        }
    }

}

sub magicStatus {
    my ( $self, $prefix, $status ) = @_;

    my $error;
    switch ($status) {

        # Skip Exif ImageUniqueID
        case /Unknown field with tag 42016 / { }

        #Skip 450
        #oocihm.lac_reel_t16588_fix: oocihm.lac_reel_t16588_fix/data/sip/data/files/t-16588-00812.tif Set Quality=80: Exception 350: Unknown field with tag 41728 (0xa300) encountered. `TIFFReadDirectory' @ warning/tiff.c/TIFFWarnings/985
        #verified Swift AIP: oocihm.8_04182_299
        #oocihm.lac_reel_t16588_fix: oocihm.lac_reel_t16588_fix/data/sip/data/files/t-16588-01696.tif Read: Exception 450: Read error on strip 7; got 793988 bytes, expected 1047424. `TIFFFillStrip' @ error/tiff.c/TIFFErrors/606
        case /^Exception 450: / { }

# https://www.awaresystems.be/imaging/tiff/tifftags/privateifd/exif/imageuniqueid.html
        case /Unknown field with tag 41728 / { }

# https://www.awaresystems.be/imaging/tiff/tifftags/privateifd/exif/filesource.html
        case /Unknown field with tag 59932 /  { }    # 0xea1c	Padding
        case /^Exception 350: .*; tag ignored/ { }
        case /^Exception 350: .*; value incorrectly truncated during reading/ { }
        case /^Exception 3\d\d: / {

            # Warn staff about 3xx warnings, until decided to make silent.
            warn "$prefix: $status\n";
        }
        else {
            $error = 1;
        }
    }
    if ($error) {
        die "$prefix: $status\n";
    }
    else {
        # Log to systems, not needed for other staff
        $self->log->warn( $self->aip . ": $prefix: $status" );
    }
}

sub enhanceCanvases {
    my ($self) = @_;

    my $copiedcanvases = 0;
    foreach my $canvaskey ( keys %{ $self->canvases } ) {
        my $doc = $self->canvases->{$canvaskey};

        # Every canvas should be normalized to a JPEG.
        if (   ( !exists $doc->{master} )
            || ( !exists $doc->{master}->{extension} )
            || $doc->{master}->{extension} ne "jpg" )
        {


            $self->log->info( "1" );
            # Image not copied yet
            my $path = $doc->{source}->{path};
            die "source.path not defined for $canvaskey\n" if ( !$path );

            $self->log->info( "2" );
            # Parse using the valid list of extensions.
            my ( $base, $dir, $ext ) =
              fileparse( $path, ( "jpg", "jp2", "jpeg", "tif", "tiff" ) );

            if ( !$ext ) {
                die "Extension from $path is not valid\n";
            }

            $self->log->info( "3" );

            # Convert all images to JPG files.
            my $newext  = "jpg";
            my $newmime = "image/jpeg";
            my $newpath = $doc->{'_id'} . "." . $newext;


            $self->log->info( "4" );

            my $preservationfile =
              File::Temp->new( UNLINK => 1, SUFFIX => "." . $ext );

            my $accessfile =
              File::Temp->new( UNLINK => 1, SUFFIX => "." . $newext );


            $self->log->info( "5" );
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
            close $preservationfile;

            $self->log->info( "6" );

            my $filemodified = $response->object_meta_header('File-Modified');

            $self->log->info( "7" );

            my $preservationfilename = $preservationfile->filename;
            if ( !( -s $preservationfilename ) ) {
                die
"$preservationfilename is a 0 length file while downloading $path\n";
            }

            $self->log->info( "8" );

            # Normmalize for Access
            my $magic = new Image::Magick;

            my $status = $magic->Read($preservationfilename);
            $self->magicStatus( "$path Read", $status ) if "$status";


            $self->log->info( "9" );

            # Archivematica uses:
            # convert "%fileFullName%" -sampling-factor 4:4:4 -quality 60 -layers merge "%outputDirectory%%prefix%%fileName%%postfix%.jpg"
            # We are keeping quality to 80% instead.

            $magic->Set( "sampling-factor" => "4:4:4" );
            $self->magicStatus( "$path Set sampling-factor 4:4:4", $status )
              if "$status";

            
            $self->log->info( "10" );

            $magic->Set( "quality" => 80 );
            $self->magicStatus( "$path Set Quality=80", $status ) if "$status";

            $status = $magic->Layers( "method" => "merge" );
            $self->magicStatus( "$path Layers merge", $status )
              if !ref($status);

            
            $self->log->info( "11" );

            my $accessfilename = $accessfile->filename;

            $status = $magic->Write($accessfilename);
            $self->magicStatus( "$path write $accessfilename", $status )
              if "$status";

            if ( !( -s $accessfilename ) ) {
                die
                  "$accessfilename is a 0 length file while converting $path\n";
            }


            $self->log->info( "12" );

            open( my $fh, '<:raw', $accessfilename )
              or die "Could not open file '$accessfilename' $!";

            binmode($fh);

            my $md5digest = Digest::MD5->new->addfile($fh)->hexdigest;

            my $tries = $self->swift_retries;


            $self->log->info( "13" );

            do {
                # Send file.
                seek( $fh, 0, 0 );
                $response =
                  $self->swiftaccess->object_put( $self->swift_access_files,
                    $newpath, $fh, { 'File-Modified' => $filemodified } );

                if ( $response->code != 201 ) {
                    die "PUT access file object=$newpath container="
                      . $self->swift_access_files
                      . " returned "
                      . $response->code . " - "
                      . $response->message . "\n";
                }
                if ( $md5digest eq $response->etag ) {
                    $tries = 0;
                }
                else {
                    $tries--;
                    warn "MD5 mismatch object_put("
                      . $self->swift_access_files
                      . "): $accessfilename=$md5digest $newpath="
                      . $response->etag
                      . " during "
                      . $response->transaction_id
                      . "  retries=$tries\n";
                    if ( !$tries ) {
                        die "No more retries\n";
                    }
                }
            } until ( !$tries );


            $self->log->info( "14" );

            # Get full replacement document
            my $newdoc = $self->canvasGetDocument( $doc->{'_id'} );

            # Set new file metadta, and store
            $newdoc->{master}->{extension} = $newext;
            $newdoc->{master}->{mime}      = $newmime;
            $newdoc->{master}->{size}      = -s $accessfilename;
            $newdoc->{master}->{md5}       = $response->etag;
            delete $newdoc->{master}->{path};

            my $data = $self->canvasPutDocument( $doc->{'_id'}, $newdoc );
            die "Put failed\n" if !$data;

            $newdoc->{'_rev'} = $data->{'rev'};
            $self->canvases->{$canvaskey} = $newdoc;


            $self->log->info( "15" );

            $copiedcanvases++;
        }
    }

    if ($copiedcanvases) {
        $self->log->info(
            $self->aip . " Normalized $copiedcanvases canvas images" );
    }

    # In theory everything is copied to Swift access storage,
    # so there shouldn't be any permission or other issues.
    my @updatecanvases;
    foreach my $canvaskey ( keys %{ $self->canvases } ) {
        my $doc = $self->canvases->{$canvaskey};

        my $modified;

        # Actually test to confirm that the canvas can be processed as an image.
        my $path =
          uri_escape_utf8( $doc->{'_id'} )
          . "/full/!80,80/0/default.jpg?cache=false";
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
        $path = uri_escape_utf8( $doc->{'_id'} ) . "/info.json?cache=false";
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

# Shouldn't be possible, but... https://github.com/crkn-rcdr/cihm-metadatabus/issues/40
    foreach my $i ( 0 .. ( @{ $self->manifest->{'canvases'} } - 1 ) ) {
        if ( !defined $self->manifest->{'canvases'}->[$i]->{'id'} ) {

            $self->log->info( $self->aip . "  "
                  . Data::Dumper->Dump( [ $self->manifest ], [qw(manifest)] ) );
            die "enhanceCanvases(): Missing ID for canvas index=$i\n";
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
    return mint_noid($number, $type);
}

sub setManifestNoid {
    my ($self) = @_;
    my @manifestnoids = @{ $self->mintNoids( 1, 'manifest' ) };
    die "Couldn't allocate 1 manifest noid\n" if ( scalar @manifestnoids != 1 );
    $self->manifest->{'_id'} = $manifestnoids[0];
}

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
