package CIHM::Meta::OcrPdf::Process;

use 5.014;
use strict;
use XML::LibXML;
use Try::Tiny;
use JSON;
use JSON::Parse 'read_json';
use Switch;
use URI::Escape;
use List::MoreUtils qw(uniq);
use File::Temp;
use Data::Dumper;

#use Data::Dumper;

=head1 NAME

CIHM::Meta::OcrPdf::Process - Handles the processing of individual manifests

=cut

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::OcrPdf::Process->new() not a hash\n";
    }
    $self->{args} = $args;

    return $self;
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}

sub worker {
    my $self = shift;
    return $self->args->{worker};
}

sub noid {
    my $self = shift;
    return $self->args->{noid};
}

sub log {
    my $self = shift;
    return $self->worker->log;
}

sub swift {
    my $self = shift;
    return $self->worker->swift;
}

sub access_metadata {
    my $self = shift;
    return $self->worker->args->{access_metadata};
}

sub access_files {
    my $self = shift;
    return $self->worker->args->{access_files};
}

sub accessdb {
    my $self = shift;
    return $self->worker->accessdb;
}

sub canvasdb {
    my $self = shift;
    return $self->worker->canvasdb;
}

sub document {
    my $self = shift;
    return $self->{document};
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

# Top method
sub process {
    my ($self) = @_;

    $self->log->info( "Processing " . $self->noid . " (" . $self->slug . ")" );

    $self->{document} =
      $self->getAccessDocument( uri_escape_utf8( $self->noid ) );
    die "Missing Document\n" if !( $self->document );

    if ( !$self->slug ) {
        die "Missing slug\n";
    }

    if ( ref( $self->document->{canvases} ) ne 'ARRAY' ) {
        die "No canvases\n";
    }

    my @canvasids;
    foreach my $i ( 0 .. ( @{ $self->document->{'canvases'} } - 1 ) ) {
        die "Missing ID for canvas index=$i\n"
          if ( !defined $self->document->{'canvases'}->[$i]->{'id'} );
        push @canvasids, $self->document->{'canvases'}->[$i]->{'id'};
    }

    my $canvasdocs = $self->getCanvasDocuments( \@canvasids );

    my $allocr = JSON::true;
    foreach my $i ( 0 .. ( @{$canvasdocs} - 1 ) ) {
        if ( !defined $canvasdocs->[$i]->{ocrPdf} ) {
            warn "Missing odfPdf for canvas index=$i\n";
            $allocr = JSON::false;
        }
    }
    die "Not all canvases have OCR data\n" if ( !$allocr );

    my $tempdir = File::Temp->newdir( CLEANUP => 0 );

    chdir $tempdir || die "Can't change directory to $tempdir\n";

    print Dumper ( $tempdir . "" );

    my @pdffilenames;

    foreach my $i ( 0 .. ( @{$canvasdocs} - 1 ) ) {
        my $ocrpdf = $canvasdocs->[$i]->{'ocrPdf'};
        my $objectname =
          $canvasdocs->[$i]->{'_id'} . "." . $ocrpdf->{'extension'};

        my $destfile = $i . ".pdf";

        push @pdffilenames, $destfile;
        open( my $fh, '>:raw', $destfile )
          or die "Could not open file '$destfile' $!";
        my $object = $self->swift->object_get( $self->access_files, $objectname,
            { write_file => $fh } );
        close $fh;
        if ( $object->code != 200 ) {
            die "object_get container: '"
              . $self->access_files
              . "' , object: '$objectname' destfilename: '$destfile'  returned "
              . $object->code . " - "
              . $object->message . "\n";
        }
    }

    my $cmd =
        "java -jar /pdfbox-app-"
      . $ENV{PDFBOXAPPVER}
      . ".jar PDFMerger "
      . join( ' ', @pdffilenames )
      . " joined.pdf ";

    my $output = `$cmd 2>&1`;
    warn "$output\n" if $output;

    if ( !-f "joined.pdf" ) {
        warn "Command: $cmd\n";
        die "No multi-page PDF file was generated\n";
    }

    my $objectname = $self->noid . ".pdf";
    print "Will post to $objectname\n";

    #print Dumper ( $self->document, \@canvasdocs );

    # While testing with 69429/m0vt1gh9g53f
    #$self->worker->setocrpdf(
    #    {
    #        "size" => 734477,
    #        "path" => "oocihm.67718/data/sip/data/files/oocihm.67718.pdf"
    #    }
    #);

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

1;
