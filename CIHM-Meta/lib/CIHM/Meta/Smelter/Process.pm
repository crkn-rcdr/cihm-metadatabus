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
use LWP::UserAgent;
use HTTP::Request;

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

sub process {
    my ($self) = @_;

    $self->loadDipDoc();
    #my $manifest_slug = $self->dipdoc->{slug};
    #my $manifest_noid = "69429/mCa08E9Je9k"; #TODO: lookup NOID from slug
    #my $manifest_url = "https://crkn-iiif-presentation-api.azurewebsites.net/manifest/" . $manifest_noid;
    my $manifest_url = $self->dipdoc->{url};

    # Use a regular expression to extract the part after "/manifest/"
    if ($url =~ /\/manifest\/([^\/]+)/) {
        my $manifest_noid = $1;  # $1 holds the matched group

        # Create a new UserAgent object
        my $ua = LWP::UserAgent->new;
        
        # Send the GET request
        my $response = $ua->get($manifest_url);
        
        # Check if the request was successful (status code 200)
        if ($response->is_success) {
            # Decode the JSON response
            my $json = decode_json($response->decoded_content);
    
            my $manifest_slug;
            foreach my $metadata_item (@{$json->{metadata}}) {
                if ($metadata_item->{label}{en}[0] eq 'Slug') {
                    $manifest_slug = $metadata_item->{value}{en}[0];
                    last;  # Exit loop once the "Slug" value is found
                }
            }
            
            # Print the value of "Slug"
            if (defined $manifest_slug) {
                print "Slug: $manifest_slug\n";
            } else {
                print "Slug not found in metadata.\n";
            }
    
            # Create the database access object
            my $database_access_obj = {
                "_id" => $manifest_noid,
                "label" => {
                    "none" => $json->{"label"}{"en"}
                },
                "slug" => $manifest_slug,
                "canvases" => []
            };
            
            # Initialize index for canvases
            my $i = 0;
            my @newcanvases;
            # Loop through the "items" in the manifest and build the "canvases"
            for my $item (@{ $json->{"items"} }) {
                # Replace the canvas URL
                my $image_noid = $item->{"id"};
                $image_noid =~ s{https://crkn-iiif-presentation-api.azurewebsites.net/canvas/}{};
                
                push @{ $database_access_obj->{"canvases"} }, {
                    "id" => $image_noid,
                    "label" => {
                        "none" => "Image " . ($i + 1)
                    }
                };
    
                my $accessfile =
                  File::Temp->new( UNLINK => 1, SUFFIX => ".jpg" );
                my $object = $self->swift->object_get( $self->access_files, $image_noid, { write_file => $accessfile } );
                close $accessfile;
                my $accessfilename = $accessfile->filename;
                open( my $fh, '<:raw', $accessfilename )
                  or die "Could not open file '$accessfilename' $!";
                binmode($fh);
                my $md5digest = Digest::MD5->new->addfile($fh)->hexdigest;
                
                # Define the database image
                my $database_image = {
                    "_id" => $image_noid,
                    "master" => {
                        "size" => -s $accessfilename,
                        "height" => $item->{"height"},
                        "width" => $item->{"width"},
                        "md5" => $md5digest,
                        "mime" => "image/jpeg",
                        "extension" => "jpg"
                    },
                    "source" => {
                        "from" => "iiif",
                        "url" => $json->{"id"}
                    },
                };
                push @newcanvases, $database_image;
                
                $i++;
            }
            # Store any that were modified
            if (@newcanvases) {
                my $res = $self->canvasdb->post(
                    "/_bulk_docs",
                    { docs         => \@newcanvases },
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
            $self->canvases = @newcanvases;
            $self->manifest = $database_access_obj;  
            if ( exists $self->manifest->{slug} ) {
                $self->writeManifest();
            }
        } else {
            die "Error: Unable to fetch the manifest. Status code: " . $response->status_line . "\n";
        }
    } else {
        die "Invalid manifest URL.\n";
    }

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

1;
