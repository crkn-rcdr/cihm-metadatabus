package CIHM::Meta::Ocrtask;

use strict;
use Carp;
use Config::General;
use Log::Log4perl;
use CIHM::Swift::Client;

use Try::Tiny;
use JSON;
use Data::Dumper;
use Switch;
use URI::Escape;
use DateTime::Format::ISO8601;
use Data::Dumper;
use Poppler;
use Digest::MD5;

=head1 NAME

CIHM::Meta::Ocrtask - Process image exports from, and OCR data imports to, the Access platform databases and object storage.


=head1 SYNOPSIS

    my $ocrtask = CIHM::Meta::Omdtask->new($args);
      where $args is a hash of arguments.


=cut

our $self;

sub new {
    my ( $class, $args ) = @_;
    our $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::Ocrtask->new() not a hash\n";
    }
    $self->{args} = $args;

    my %swiftopt = ( furl_options => { timeout => 3600 } );
    foreach ( "server", "user", "password", "account" ) {
        if ( exists $args->{ "swift_" . $_ } ) {
            $swiftopt{$_} = $args->{ "swift_" . $_ };
        }
    }
    $self->{swift} = CIHM::Swift::Client->new(%swiftopt);

    my $test = $self->swift->container_head( $self->access_files );
    if ( !$test || $test->code != 204 ) {
        die "Problem connecting to Swift container. Check configuration\n";
    }

    $self->{ocrtaskdb} = new restclient(
        server      => $args->{couchdb_ocrtask},
        type        => 'application/json',
        clientattrs => { timeout => 3600 },
    );
    $self->ocrtaskdb->set_persistent_header( 'Accept' => 'application/json' );
    $test = $self->ocrtaskdb->head("/");
    if ( !$test || $test->code != 200 ) {
        die
"Problem connecting to `ocrtask` Couchdb database. Check configuration\n";
    }

    $self->{canvasdb} = new restclient(
        server      => $args->{couchdb_canvas},
        type        => 'application/json',
        clientattrs => { timeout => 3600 },
    );
    $self->canvasdb->set_persistent_header( 'Accept' => 'application/json' );
    $test = $self->canvasdb->head("/");
    if ( !$test || $test->code != 200 ) {
        die
"Problem connecting to `canvas` Couchdb database. Check configuration\n";
    }

    $self->{accessdb} = new restclient(
        server      => $args->{couchdb_access},
        type        => 'application/json',
        clientattrs => { timeout => 3600 },
    );
    $self->accessdb->set_persistent_header( 'Accept' => 'application/json' );
    $test = $self->accessdb->head("/");
    if ( !$test || $test->code != 200 ) {
        die
"Problem connecting to `access` Couchdb database. Check configuration\n";
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
    return $self->args->{logger};
}

sub ocrdir {
    my $self = shift;
    return $self->args->{ocrdir};
}

sub access_metadata {
    my $self = shift;
    return $self->args->{swift_access_metadata};
}

sub access_files {
    my $self = shift;
    return $self->args->{swift_access_files};
}

sub swift_retries {
    my $self = shift;
    return $self->args->{swift_retries};
}

sub swift {
    my $self = shift;
    return $self->{swift};
}

sub ocrtaskdb {
    my $self = shift;
    return $self->{ocrtaskdb};
}

sub canvasdb {
    my $self = shift;
    return $self->{canvasdb};
}

sub accessdb {
    my $self = shift;
    return $self->{accessdb};
}

sub maxprocs {
    my $self = shift;
    return $self->args->{maxprocs};
}

sub task {
    my $self = shift;
    return $self->{task};
}

sub taskid {
    my $self = shift;
    return $self->task->{'_id'} if $self->task;
    return "[unknown]";
}

sub taskname {
    my $self = shift;
    return $self->task->{'name'} if $self->task;
    return "[unknown]";
}

sub todo {
    my $self = shift;
    return $self->{todo};
}

sub clear_warnings {
    my $self = shift;
    $self->{warnings} = "";
}

sub warnings {
    my $self = shift;
    return $self->{warnings};
}

sub collect_warnings {
    my $warning = shift;
    our $self;
    my $taskid = "unknown";

    # Strip wide characters before  trying to log
    ( my $stripped = $warning ) =~ s/[^\x00-\x7f]//g;

    if ($self) {
        $self->{warnings} .= $warning;
        $self->log->warn( $self->taskid . ": $stripped" );
    }
    else {
        say STDERR "$warning\n";
    }
}

sub ocrtask {
    my ($self) = @_;

    # Used to show a different processname during processing
    my $ocrloadprog = $0;

    $self->clear_warnings();

    # Capture warnings
    local $SIG{__WARN__} = sub { &collect_warnings };

    $self->log->info( "Ocrtask: maxprocs=" . $self->maxprocs );

    $self->ocrtaskdb->type("application/json");
    my $url =
"/_design/access/_view/ocrQueue?reduce=false&descending=true&include_docs=true";
    my $res =
      $self->ocrtaskdb->get( $url, {}, { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        if ( exists $res->data->{rows} ) {
            foreach my $task ( @{ $res->data->{rows} } ) {
                my $status;
                $self->clear_warnings();

                my $todo = shift @{ $task->{key} };
                $self->{todo} = $todo;
                $self->{task} = $task->{doc};
                $self->postProgress(0);

                $self->log->info( "Processing Task="
                      . $self->taskid
                      . " Name="
                      . $self->taskname );

                # Handle and record any errors
                try {
                    $status = JSON::true;

                    if ( $todo eq 'export' ) {
                        $self->ocrExport();
                    }
                    else {
                        $self->ocrImport();
                    }
                }
                catch {
                    $status = JSON::false;
                    $self->log->error( $self->taskid . ": $_" );
                    $self->{warnings} .= "Caught: " . $_;
                };
                $0 = $ocrloadprog;
                $self->postResults( $status, $self->warnings );
            }
        }
    }
    else {
        $self->log->error(
            "ocrtaskdb $url GET return code: " . $res->code . "\n" );
    }
}

sub ocrExport {
    my ($self) = @_;

    # Used to show a different processname during processing
    my $ocrloadprog = $0;

    my $workdir = $self->ocrdir . "/" . $self->task->{name};
    mkdir $workdir or die "Can't create task work directory $workdir : $!\n";

    $self->canvasdb->type("application/json");
    my $url = "/_all_docs";

    my %canvas_titles = {};
    $self->accessdb->type("application/json");
    my $manifestres = $self->accessdb->post(
        "/_design/noid/_view/canvasnoids",
        {
            keys         => $self->task->{canvases},
            include_docs => JSON::true
        },
        { deserializer => 'application/json' }
    );
    if ( $manifestres->code != 200 ) {
        die "/_design/noid/_view/canvasnoids return code: " . $manifestres->code . "\n";
    }
    foreach my $row ( @{ $manifestres->data->{rows} } ) {
        my $image_num = 1;
        foreach my $canvas_obj ( @{ $row->{'doc'}->{'canvases'} } ) {
            if($row->{'key'} eq $canvas_obj->{'id'} ) {
               $canvas_titles{ $row->{'key'} } = $row->{'doc'}->{'slug'} . '.' . $image_num; 
            }
            $image_num = $image_num + 1;
        }
    }

    my $res = $self->canvasdb->post(
        $url,
        {
            keys         => $self->task->{canvases},
            include_docs => JSON::true
        },
        { deserializer => 'application/json' }
    );
    if ( $res->code != 200 ) {
        die "$url return code: " . $res->code . "\n";
    }

    $self->log->info( $self->taskid
          . ": Found "
          . scalar( @{ $res->data->{rows} } )
          . " canvases from task of "
          . scalar( @{ $self->task->{canvases} } )
          . " canvases" );

    my $currentIndex = 1;
    my $numCanvases = @{$self->task->{canvases}};
    foreach my $canvasdoc ( @{ $res->data->{rows} } ) {
        if ( !defined $canvasdoc->{doc} ) {
            warn "Didn't find " . $canvasdoc->{id} . "\n";
        }
        else {
            my $canvas = $canvasdoc->{doc};
            my $objectname = $canvas->{'_id'} . '.' . $canvas->{master}->{extension};
            my $destname = $canvas_titles{ $canvas->{'_id'} } . '.' . $canvas->{master}->{extension};
            my $destfilename = $workdir . '/' . uri_escape_utf8($destname);

            open( my $fh, '>:raw', $destfilename )
              or die "Could not open file '$destfilename' $!";
            $0 =
                $ocrloadprog . " get "
              . $self->access_files
              . " $objectname --> $destfilename";
            my $object =
              $self->swift->object_get( $self->access_files, $objectname,
                { write_file => $fh } );
            close $fh;
            if ( $object->code != 200 ) {
                die "Swift object_get container: '"
                  . $self->access_files
                  . "' , object: '$objectname' destfilename: '$destfilename'  returned "
                  . $object->code . " - "
                  . $object->message . "\n";
            }
            my $filemodified = $object->object_meta_header('File-Modified');
            if ($filemodified) {
                my $dt =
                  DateTime::Format::ISO8601->parse_datetime($filemodified);
                if ( !$dt ) {
                    die
"Couldn't parse ISO8601 date from $filemodified (GET from $objectname, $destname)\n";
                }
                my $atime = time;
                utime $atime, $dt->epoch(), $destfilename;
            }
        }
        $currentIndex = $currentIndex + 1;
        my $progress = ($currentIndex / $numCanvases)*100;
        $self->postProgress($progress);
    }
}

sub ocrImport {
    my ($self) = @_;

    # Used to show a different processname during processing
    my $ocrloadprog = $0;

    my $workdir = $self->ocrdir . "/" . $self->task->{name};
    if ( !-d $workdir ) {
        die "Work directory: $workdir : $!\n";
    }

    $self->canvasdb->type("application/json");
    my $url = "/_all_docs";

    my $res = $self->canvasdb->post(
        $url,
        {
            keys         => $self->task->{canvases},
            include_docs => JSON::true
        },
        { deserializer => 'application/json' }
    );
    if ( $res->code != 200 ) {
        die "$url return code: " . $res->code . "\n";
    }

    $self->log->info( $self->taskid
          . ": Found "
          . scalar( @{ $res->data->{rows} } )
          . " canvases from task of "
          . scalar( @{ $self->task->{canvases} } )
          . " canvases" );

    my %canvas_titles = {};
    my $manifestres = $self->accessdb->post(
        "/_design/noid/_view/canvasnoids",
        {
            keys         => $self->task->{canvases},
            include_docs => JSON::true
        },
        { deserializer => 'application/json' }
    );
    if ( $manifestres->code != 200 ) {
        die "/_design/noid/_view/canvasnoids return code: " . $manifestres->code . "\n";
    }
    foreach my $row ( @{ $manifestres->data->{rows} } ) {
        my $image_num = 1;
        foreach my $canvas_obj ( @{ $row->{'doc'}->{'canvases'} } ) {
            if($row->{'key'} eq $canvas_obj->{'id'} ) {
               $canvas_titles{ $row->{'key'} } = $row->{'doc'}->{'slug'} . '.' . $image_num; 
            }
            $image_num = $image_num + 1;
        }
    }

    # Collect IDs so we can generate multi-page OCR PDF files
    my %canvasids;
    my @updatedcanvases;
    my $currentIndex = 1;
    my $numCanvases = @{$self->task->{canvases}};
    foreach my $canvasdoc ( @{ $res->data->{rows} } ) {
        if ( !defined $canvasdoc->{doc} ) {
            warn "Didn't find " . $canvasdoc->{id} . "\n";
        }
        else {
            my $canvas = $canvasdoc->{doc};

            $canvasids{ $canvas->{'_id'} } = 1;

            my $changed;

            my $pdfobjectname = $canvas->{'_id'} . '.pdf';
            my $pdflocalfile = $canvas_titles{ $canvas->{'_id'} } . '.pdf';
            my $pdffilename = $workdir . '/' . uri_escape_utf8($pdflocalfile);
            if ( -f $pdffilename ) {
                $0 = $ocrloadprog . " check $pdffilename";
                my $pages = 0;
                try {
                    my $pdf = Poppler::Document->new_from_file($pdffilename);
                    $pages = $pdf->get_n_pages;
                };
                if ( $pages == 1 ) {
                    $0 = $ocrloadprog . " updateFile $pdffilename";
                    my $upload =
                      $self->updateFile( "pdf", $canvas->{'_id'},
                        $pdffilename );

                    $canvas->{'ocrPdf'} = {
                        size      => $upload->{size},
                        extension => 'pdf',
                        md5       => $upload->{md5digest}
                    };
                    $changed = 1;
                }
                else {
                    warn "$pdffilename is not a single page PDF\n";
                }
            }
            else {
                warn "$pdffilename doesn't exist\n";
            }

            my $xmlobjectname = $canvas->{'_id'} . '.xml';
            my $xmllocalfilename = $canvas_titles{ $canvas->{'_id'} } . '.xml';
            my $xmlfilename = $workdir . '/' . uri_escape_utf8($xmllocalfilename);
            if ( -f $xmlfilename ) {
                $0 = $ocrloadprog . " check $xmlfilename";
                my $valid = 1;
                try {
                    # Version 3
                    $self->log->info( "validate v3" );
                    my $xml = XML::LibXML->new->parse_file($xmlfilename);
                    my $xpc = XML::LibXML::XPathContext->new($xml);

                    $xpc->registerNs( 'alto',
                        'http://www.loc.gov/standards/alto/ns-v3' );
                    my $schema3 =
                      XML::LibXML::Schema->new( location =>
                          "/opt/xml/current/unpublished/xsd/alto-3-1.xsd" );

                    $schema3->validate($xml);
                    $self->log->info( "done" );
                }
                catch {
                    $self->log->info( "validate v3 failed, trying v4..." );
                    # Version 4
                    try {
                        my $xml = XML::LibXML->new->parse_file($xmlfilename);
                        my $xpc = XML::LibXML::XPathContext->new($xml);
                        $self->log->info( "registerNs" );
                        $xpc->registerNs( 'alto',
                            'http://www.loc.gov/standards/alto/ns-v4' );
                        
                        $self->log->info( "Schema->new" );
                        my $schema4 =
                        XML::LibXML::Schema->new( location =>
                            "/opt/xml/current/unpublished/xsd/alto-4-2.xsd" );

                        $self->log->info( "validate" );
                        $schema4->validate($xml);

                        $self->log->info( "done" );
                    }
                    catch {
                        $self->log->info( "validate v4 failed" );
                        $valid = 0;
                        warn "$xmlfilename is not valid ALTO XML: $_\n";
                    };
                };

                if ($valid) {
                    $0 = $ocrloadprog . " updateFile $xmlfilename";
                    $self->updateFile( "ocrALTO.xml", $canvas->{'_id'},
                        $xmlfilename );

                    # Delete any redundant txtmap
                    $self->swift->object_delete( $self->access_metadata,
                        $canvas->{'_id'} . "/ocrTXTMAP.xml" );

                    $canvas->{'ocrType'} = 'alto';
                    $changed = 1;
                }
            }
            else {
                warn "$xmlfilename doesn't exist\n";
            }
            if ($changed) {
                push @updatedcanvases, $canvas;
            }
        }

        $currentIndex = $currentIndex + 1;
        my $progress = ($currentIndex / $numCanvases)*100;
        $self->postProgress($progress);
    }

    $self->log->info( $self->taskid . ": "
          . scalar(@updatedcanvases)
          . " canvases were updated" );

    # Update any potentially changed Canvases.
    if (@updatedcanvases) {
        my $res = $self->canvasdb->post(
            "/_bulk_docs",
            { docs         => \@updatedcanvases },
            { deserializer => 'application/json' }
        );
        if ( $res->code != 201 ) {
            if ( defined $res->response->content ) {
                warn $res->response->content . "\n";
            }
            die "dbupdate of updated canvases return code: "
              . $res->code . "\n";
        }
    }

    my @ids = keys %canvasids;

    $self->accessdb->type("application/json");
    $url = "/_design/noid/_view/canvasnoids";

    my $res = $self->accessdb->post(
        $url,
        {
            keys         => \@ids,
            include_docs => JSON::false
        },
        { deserializer => 'application/json' }
    );
    if ( $res->code != 200 ) {
        die "$url return code: " . $res->code . "\n";
    }

    my %manifestids;
    foreach my $doc ( @{ $res->data->{rows} } ) {
        $manifestids{ $doc->{'id'} } = 1;
    }

    # Attempt to generate OCR PDF for manifests where OCR data was added
    foreach my $accessid ( keys %manifestids ) {
        my $url =
          "/_design/metadatabus/_update/requestOCRPDF/" . uri_escape($accessid);
        my $res = $self->accessdb->post( $url, {},
            { deserializer => 'application/json' } );
        if ( $res->code != 201 ) {
            if ( defined $res->response->content ) {
                warn $res->response->content . "\n";
            }
            warn "Attempt to request multi-page OCR PDF generation for noid=$accessid : " . $res->code . "\n";
        }
        else {
            $self->log->info(
                $self->taskid . ": multi-page OCR PDF generation requested for noid=$accessid" );
        }
    }
}

sub updateFile {
    my ( $self, $type, $id, $filename ) = @_;

    open( my $fh, '<:raw', $filename )
      or die "Can't open '$filename': $!";
    binmode($fh);
    my $filedate = "unknown";
    my $mtime    = ( stat($fh) )[9];
    if ($mtime) {
        my $dt = DateTime->from_epoch( epoch => $mtime );
        $filedate = $dt->datetime . "Z";
    }
    my $size = ( stat($fh) )[7];

    my $md5digest = Digest::MD5->new->addfile($fh)->hexdigest;
    seek( $fh, 0, 0 );

    # Currently only 'pdf' and 'ocrALTO.xml' exist.
    my $container;
    my $object;
    if ( $type eq 'pdf' ) {
        $container = $self->access_files;
        $object    = $id . ".pdf";
    }
    else {
        $container = $self->access_metadata;
        $object    = $id . "/ocrALTO.xml";
    }

    my $tries = $self->swift_retries;

    # This is a short circuit to redundantly sending, so don't fail on it.
  checkexists: {
        do {

            my $res = $self->swift->object_head( $container, $object );

            if ( $res->code == 200 ) {
                if (   ( int( $res->header('Content-Length') ) == $size )
                    && ( $res->etag eq $md5digest ) )
                {
                    # Don't send, as it is already there
                    return { size => $size, md5digest => $md5digest };
                }
                last;
            }
            elsif ( $res->code == 404 ) {

                # Not found means always send
                last;
            }
            else {
                warn "updateFile HEAD of '$object' into '$container' returned "
                  . $res->code . " - "
                  . $res->message
                  . " retries=$tries\n";
                $tries--;
            }
        } until ( !$tries );
    }
    $tries = $self->swift_retries;

  sendthefile: {
        do {

            # Send file.
            seek( $fh, 0, 0 );
            my $putresp =
              $self->swift->object_put( $container, $object, $fh,
                { 'File-Modified' => $filedate } );
            if ( $putresp->code != 201 ) {
                warn(
"updateFile object_put of '$object' into '$container' returned "
                      . $putresp->code . " - "
                      . $putresp->message
                      . " retries=$tries\n" );
            }
            elsif ( $md5digest eq $putresp->etag ) {
                last;
            }
            else {
                # Extra check that everything was OK.
                warn
"Etag mismatch during object_put of $object into $container: $filename=$md5digest $object="
                  . $putresp->etag
                  . " during "
                  . $putresp->transaction_id
                  . " retries=$tries\n";
            }
            $tries--;
        } until ( !$tries );
    }

    close $fh;

    if ( !$tries ) {
        die "No more retries\n";
    }

    return { size => $size, md5digest => $md5digest };
}

sub postResults {
    my ( $self, $succeeded, $message ) = @_;

    my $which = ( $self->todo eq "export" ) ? "Export" : "Import";
    my $taskid = $self->taskid;

    my $url =
      "/_design/access/_update/updateOCR${which}/" . uri_escape_utf8($taskid);
    my $updatedoc = { succeeded => $succeeded, message => $message };

    my $res =
      $self->ocrtaskdb->post( $url, $updatedoc,
        { deserializer => 'application/json' } );

    if ( $res->code != 201 && $res->code != 200 ) {
        die "$url POST return code: " . $res->code . "\n";
    }
    if ( $res->data ) {
        if ( exists $res->data->{message} ) {
            $self->log->info( $taskid . ": " . $res->data->{message} );
        }
        if ( exists $res->data->{error} ) {
            $self->log->error( $taskid . ": " . $res->data->{error} );
        }
    }
}

sub postProgress {
    my ( $self, $progress ) = @_;

    my $which = ( $self->todo eq "export" ) ? "Export" : "Import";
    my $taskid = $self->taskid;

    my $url =
      "/_design/access/_update/updateOCRProgress/" . uri_escape_utf8($taskid);
    my $updatedoc = { priority => $progress };

    my $res =
      $self->ocrtaskdb->post( $url, $updatedoc,
        { deserializer => 'application/json' } );

    if ( $res->code != 201 && $res->code != 200 ) {
        die "$url POST return code: " . $res->code . "\n";
    }
}

{

    package restclient;

    use Moo;
    with 'Role::REST::Client';
}

1;
