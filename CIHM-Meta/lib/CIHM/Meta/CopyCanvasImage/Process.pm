package CIHM::Meta::CopyCanvasImage::Process;

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
use Data::Dumper;

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
        die
"Argument to CIHM::Meta::CopyCanvasImage::Process->new() not a hash\n";
    }
    $self->{args} = $args;

    if ( !$self->log ) {
        die "Log::Log4perl object parameter is mandatory\n";
    }
    if ( !$self->swift ) {
        die "swift object parameter is mandatory\n";
    }
    if ( !$self->canvasdb ) {
        die "canvasdb object parameter is mandatory\n";
    }
    if ( !$self->canvasid ) {
        die "Parameter 'canvasid' is mandatory\n";
    }
    if ( !$self->access_files ) {
        die "Parameter 'access_files' is mandatory\n";
    }
    if ( !$self->preservation_files ) {
        die "Parameter 'preservation_files' is mandatory\n";
    }
    return $self;
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}

sub canvasid {
    my $self = shift;
    return $self->args->{canvasid};
}

sub log {
    my $self = shift;
    return $self->args->{log};
}

sub canvasdb {
    my $self = shift;
    return $self->args->{canvasdb};
}

sub accessdb {
    my $self = shift;
    return $self->args->{accessdb};
}

sub swift {
    my $self = shift;
    return $self->args->{swift};
}

sub access_files {
    my $self = shift;
    return $self->args->{access_files};
}

sub preservation_files {
    my $self = shift;
    return $self->args->{preservation_files};
}

sub process {
    my ($self) = @_;

    my $doc = $self->canvasdb->get_document( uri_escape( $self->canvasid ) );
    die "Can't get Document=" . $self->canvasid . "\n" if !$doc;

    if ( $self->checkOrphan( $self->canvasid ) ) {
        warn "Not copying an Orphan -- setting\n";
        $doc->{orphan} = JSON::true;
    }
    else {

        my $path;
        if ( exists $doc->{master} && exists $doc->{master}->{path} ) {
            $path = delete $doc->{master}->{path};
        }
        if ( exists $doc->{master} && !keys %{ $doc->{master} } ) {
            delete $doc->{master};
        }
        if ($path) {

            # Parse using the valid list of extensions.
            my ( $base, $dir, $ext ) =
              fileparse( $path, ( "jpg", "jp2", "jpeg", "tif", "tiff" ) );

            if ( !$ext ) {
                die "Extension from from $path is not valid\n";
            }

            my $response =
              $self->swift->object_head( $self->preservation_files, $path );

            if ( $response->code == 200 ) {
                my $size = $response->header('Content-Length') + 0;

                if ( exists $doc->{master}->{size} ) {
                    warn "Size of $path doesn't match document=",
                      $self->canvasid . "\n"
                      if $doc->{master}->{size} != $size;
                }
                else {
                    $doc->{master}->{size} = $size;
                }

                my $md5 = $response->etag;
                if ( exists $doc->{master}->{md5} ) {
                    warn "MD5 of $path doesn't match document=",
                      $self->canvasid . "\n"
                      if $doc->{master}->{md5} ne $md5;
                }
                else {
                    $doc->{master}->{md5} = $md5;
                }
            }

            my $newpath = $self->canvasid . "." . $ext;

            $response = $self->swift->object_copy(
                $self->preservation_files, $path,
                $self->access_files,       $newpath
            );

            if ( $response->code == 201 ) {
                warn "MD5 of copy:$newpath doesn't match document=",
                  $self->canvasid . "\n"
                  if $doc->{master}->{md5} ne $response->etag;

                # Set extension, and store
                $doc->{master}->{extension} = $ext;

            }
            else {
                die "object_copy("
                  . $self->preservation_files . ","
                  . $path . ","
                  . $self->access_files . ","
                  . $newpath
                  . ") returned "
                  . $response->code . " - "
                  . $response->message . "\n";

            }
        }
    }

    $self->canvasdb->put_document( uri_escape( $self->canvasid ), $doc );

}

sub checkOrphan {
    my ( $self, $canvasid ) = @_;

    my $request =
      "/" . $self->accessdb->{database} . "/_design/noid/_view/canvasnoids";
    my $response = $self->accessdb->post(
        $request,
        {
            keys => [$canvasid]
        },
        { deserializer => 'application/json' }
    );
    if ( $response->code != 200 ) {
        die "CouchDB: \"$request\" return code: "
          . $response->code . " - "
          . $response->message . "\n";
    }

    # Create hash from found entries
    my %canvasfound = map { $_->{key} => 1 } @{ $response->data->{rows} };

    return !exists $canvasfound{$canvasid};
}

1;
