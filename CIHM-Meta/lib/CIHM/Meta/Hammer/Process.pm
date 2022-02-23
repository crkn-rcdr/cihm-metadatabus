package CIHM::Meta::Hammer::Process;

use 5.014;
use strict;
use CIHM::METS::parse;
use XML::LibXML;
use Try::Tiny;
use JSON;
use Switch;
use URI::Escape;

=head1 NAME

CIHM::Meta::Hammer::Process - Handles the processing of individual AIPs for
CIHM::Meta::Process

=head1 SYNOPSIS

    my $process = CIHM::Meta::Hammer::Process->new($args);
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
    if ( !$self->swift ) {
        die "swift object parameter is mandatory\n";
    }
    if ( !$self->internalmeta ) {
        die "internalmeta object parameter is mandatory\n";
    }
    if ( !$self->cantaloupe ) {
        die "cantaloupe object parameter is mandatory\n";
    }
    if ( !$self->aip ) {
        die "Parameter 'aip' is mandatory\n";
    }
    $self->{updatedoc}            = {};
    $self->{pageinfo}             = {};
    $self->pageinfo->{count}      = 0;
    $self->pageinfo->{dimensions} = 0;

    return $self;
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}

sub aip {
    my $self = shift;
    return $self->args->{aip};
}

sub metspath {
    my $self = shift;
    return $self->args->{metspath};
}

sub log {
    my $self = shift;
    return $self->args->{log};
}

sub swift {
    my $self = shift;
    return $self->args->{swift};
}

sub container {
    my $self = shift;
    return $self->args->{swiftcontainer};
}

sub filemetadata {
    my $self = shift;
    return $self->{filemetadata};
}

sub internalmeta {
    my $self = shift;
    return $self->args->{internalmeta};
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

sub mets {
    my $self = shift;
    return $self->{mets};
}

sub process {
    my ($self) = @_;

    # Grab the METS record from Swift, and parse into METS (LibXML) object
    $self->{mets} = CIHM::METS::parse->new(
        {
            aip        => $self->aip,
            metspath   => $self->metspath,
            xmlfile    => $self->get_metadata( $self->metspath ),
            metsaccess => $self
        }
    );

    # Fill in information about the TYPE="physical" structMap
    $self->mets->mets_walk_structMap("physical");
    my $metsdata = $self->mets->metsdata("physical");

    # Build and then parse the "cmr" data
    my $idata = $self->mets->extract_idata();
    if ( scalar( @{$idata} ) != 1 ) {
        die "Need exactly 1 array element for item data\n";
    }
    $idata = $idata->[0];

    my $label;
    my $pubmin;
    my $seq;
    my $canonicalDownload = "";
    my %hammerfields;

    # Loop through array of item+components
    for my $i ( 0 .. $#$metsdata ) {

        if ( $i == 0 ) {

            # Item processing
            # Copy fields from $idata , skipping some...
            foreach my $key ( keys %{$idata} ) {
                switch ($key) {
                    case "label"       { }
                    case "contributor" { }
                    else {
                        $metsdata->[0]->{$key} = $idata->{$key};
                    }
                }
            }

            # If item download exists, set the canonicalDownload
            if ( exists $metsdata->[0]->{'canonicalDownload'} ) {
                $canonicalDownload = $metsdata->[0]->{'canonicalDownload'};
            }

            # Copy into separate variables (used for components, couch)
            $label  = $metsdata->[0]->{'label'};
            $pubmin = $metsdata->[0]->{'pubmin'};
            $seq    = $metsdata->[0]->{'seq'};
        }
        else {
            # Component processing

            # Grab OCR as text (no positional data for now)
            my $ocrtxt = $self->mets->getOCRtxt( "physical", $i );
            if ($ocrtxt) {
                $metsdata->[$i]->{'tx'} = [$ocrtxt];
            }
        }

        # manipulate $self->updatedoc with data to be stored within
        # main couchdb document (Separate from attachment)
        $self->updateAIPdoc( $metsdata->[$i] );

        if ( exists $metsdata->[$i]->{'canonicalMaster'} ) {
            my $filedata =
              $self->getFileData( $metsdata->[$i]->{'canonicalMaster'},
                'physical' );
            foreach my $key ( keys %{$filedata} ) {
                $metsdata->[$i]->{"canonicalMaster${key}"} = $filedata->{$key};
                if ( $key eq 'Width' ) {
                    $self->pageinfo->{dimensions}++;
                }
            }
        }
        if ( exists $metsdata->[$i]->{'canonicalDownload'} ) {
            my $filedata =
              $self->getFileData( $metsdata->[$i]->{'canonicalDownload'},
                'physical' );
            foreach my $key ( keys %{$filedata} ) {
                $metsdata->[$i]->{"canonicalDownload${key}"} =
                  $filedata->{$key};
                if ( $key eq 'Width' ) {
                    $self->pageinfo->{dimensions}++;
                }
            }
        }

        # at end of loop, after field names possibly updated
        foreach my $field ( keys %{ $metsdata->[$i] } ) {
            $hammerfields{$field} = 1;
        }
    }

    # Add field 'label' to couchdb document
    if ( defined $label ) {
        $self->updatedoc->{'label'} = $label;
    }

    # Add field 'pubmin' to couchdb document
    if ( defined $pubmin ) {
        $self->updatedoc->{'pubmin'} = $pubmin;
    }

    # Add field 'seq' to couchdb document
    if ( defined $seq ) {
        $self->updatedoc->{'seq'} = $seq;
    }

    # If there is pageinfo, make sure it gets added as well
    if ( $self->pageinfo->{count} > 0 ) {
        $self->updatedoc->{'pageinfo'} = encode_json $self->pageinfo;
    }

    # This always defined
    $self->updatedoc->{'canonicalDownload'} = $canonicalDownload;

    # Set array of fields
    my @hammerfields = sort( keys %hammerfields );
    $self->updatedoc->{'hammerfields'} = encode_json \@hammerfields;

    # Create document if it doesn't already exist
    $self->internalmeta->update_basic( $self->aip, {} );

    my $return = $self->internalmeta->put_attachment(
        $self->aip,
        {
            type      => "application/json",
            content   => encode_json $metsdata,
            filename  => "hammer.json",
            updatedoc => $self->updatedoc
        }
    );

    if ( $return != 201 ) {
        die "Return code $return for internalmeta->put_attachment("
          . $self->aip . ")\n";
    }
}

sub get_metadata {
    my ( $self, $file ) = @_;

    # Will retry for a second time.
    my $count = 2;

    my $object = $self->aip . "/$file";
    while ( $count-- ) {
        my $r = $self->swift->object_get( $self->container, $object );
        if ( $r->code == 200 ) {
            return $r->content;
        }
        elsif ( $r->code == 599 ) {
            warn( "Accessing $object returned code: " . $r->code . "\n" );
        }
        else {
            die( "Accessing $object returned code: " . $r->code . "\n" );
        }
    }
}

sub get_filemd5 {
    my ( $self, $file ) = @_;

    if ( !exists $self->{filemd5} ) {
        $self->{filemd5} = {};
        my $md5txt = $self->get_metadata("manifest-md5.txt");
        foreach my $row ( split( /\n/, $md5txt ) ) {
            my ( $md5, $path ) = split( /\s+/, $row );
            if ( $md5 && $path ) {
                $self->{filemd5}->{$path} = $md5;
            }
        }
    }
    return $self->{filemd5}->{$file};
}

sub loadFileMeta {
    my $self = shift;

    if ( !$self->filemetadata ) {
        $self->{filemetadata} = {};

        my $prefix = $self->aip . '/';

        # List of objects with AIP as prefix
        my %containeropt = ( "prefix" => $prefix );

        # Need to loop possibly multiple times as Swift has a maximum of
        # 10,000 names.
        my $more = 1;
        while ($more) {
            my $bagdataresp =
              $self->swift->container_get( $self->container, \%containeropt );
            if ( $bagdataresp->code != 200 ) {
                die "container_get("
                  . $self->container
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
}

# Path within AIP and the structMap type ('physical' for now)
sub getFileData {
    my ( $self, $pathname, $structtype ) = @_;

    # Strip off the AIP ID
    my $pathinaip = substr( $pathname, index( $pathname, '/' ) + 1 );

    # Always return at least a blank
    # Set with: Size, MD5, Width, Height
    my $filedata = {};

    # Load if not already loaded
    $self->loadFileMeta();
    my $fmetadata = $self->filemetadata->{$pathinaip};

    # If record doesn't already exist, create one.
    if ( !$fmetadata ) {
        die "No file metadata for $pathname in Swift\n";
    }

    my $fileindex =
      $self->mets->fileinfo("physical")->{'fileindex'}->{$pathinaip};
    if ( !$fileindex ) {
        die "fileindex for $pathname doesn't exist\n";
    }

    if ( exists $fmetadata->{bytes} ) {
        $filedata->{'Size'} = $fmetadata->{bytes};
    }
    if ( exists $fmetadata->{hash} ) {
        $filedata->{'MD5'} = $fmetadata->{hash};
    }

    # If this is a master image, try talking to Cantaloupe to get dimensions
    if ( $fileindex->{'use'} eq 'master' ) {
        my $path = uri_escape_utf8($pathname) . "/info.json";
        my $res = $self->cantaloupe->get( $path, {},
            { deserializer => 'application/json' } );

        # TODO: the 403 is a bit odd!
        if ( $res->code != 200 && $res->code != 403 ) {
            die "Cantaloupe call to `$path` returned: " . $res->code . "\n";
        }
        if ( defined $res->data->{height} ) {
            $filedata->{'Height'} = $res->data->{height};
        }
        if ( defined $res->data->{width} ) {
            $filedata->{'Width'} = $res->data->{width};
        }
    }

    return $filedata;
}

# This looks at the flattened data and extracts specific fields to be
# posted as couchdb fields
sub updateAIPdoc {
    my ( $self, $doc ) = @_;

    my $type = $doc->{type} // '';
    my $key  = $doc->{key}  // '';
    my $pkey = $doc->{pkey} // '';
    my $seq  = $doc->{seq};

    if ( $type ne 'page' ) {
        if ( $key ne $self->aip ) {
            $self->updatedoc->{'sub-type'} = "cmr key mismatch";
        }
        else {
            $self->updatedoc->{'sub-type'} = $type;
        }
        if ( $type eq 'document' ) {
            if ( $pkey ne '' ) {
                $self->updatedoc->{'parent'} = $pkey;
            }
        }
        elsif ( $type eq 'series' ) {
            if ( $pkey ne '' ) {
                warn $self->aip . " is series with parent $pkey\n";
            }
        }
    }
    else {
        if ($seq) {
            if ( !$self->pageinfo->{max} || $self->pageinfo->{max} < $seq ) {
                $self->pageinfo->{max} = $seq;
            }
            if ( !$self->pageinfo->{min} || $self->pageinfo->{min} > $seq ) {
                $self->pageinfo->{min} = $seq;
            }
            $self->pageinfo->{count}++;
        }
        if (  !$self->updatedoc->{'sub-type'}
            || $self->updatedoc->{'sub-type'} ne 'document' )
        {
            warn "Page $key 's parent not 'document' for " . $self->aip . "\n";
        }
        if ( $pkey ne $self->aip ) {
            warn "Page $key has mismatched parent key for " . $self->aip . "\n";
        }
    }
}

1;
