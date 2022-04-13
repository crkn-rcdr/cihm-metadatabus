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

sub access_metadata {
    my $self = shift;
    return $self->args->{swift_access_metadata};
}

sub access_files {
    my $self = shift;
    return $self->args->{swift_access_files};
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

    $self->clear_warnings();

    # Capture warnings
    local $SIG{__WARN__} = sub { &collect_warnings };

    $self->log->info( "Ocrtask maxprocs=" . $self->maxprocs );

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

    my $workdir = "/home/tdr/ocr/" . $self->task->{name};
    mkdir $workdir or die "Can't create task work directory $workdir : $!\n";

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
    foreach my $canvasdoc ( @{ $res->data->{rows} } ) {
        if ( !defined $canvasdoc->{doc} ) {
            warn "Didn't find " . $canvasdoc->{id} . "\n";
        }
        else {
            my $canvas = $canvasdoc->{doc};
            my $objectname =
              $canvas->{'_id'} . '.' . $canvas->{master}->{extension};
            my $destfilename = $workdir . '/' . uri_escape_utf8($objectname);

            open( my $fh, '>:raw', $destfilename )
              or die "Could not open file '$destfilename' $!";
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
"Couldn't parse ISO8601 date from $filemodified (GET from $objectname)\n";
                }
                my $atime = time;
                utime $atime, $dt->epoch(), $destfilename;
            }
        }
    }
}

sub ocrImport {
    my ($self) = @_;

    my $workdir = "/home/tdr/ocr/" . $self->task->{name};
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
    foreach my $canvasdoc ( @{ $res->data->{rows} } ) {
        if ( !defined $canvasdoc->{doc} ) {
            warn "Didn't find " . $canvasdoc->{id} . "\n";
        }
        else {
            my $canvas = $canvasdoc->{doc};

            my $pdfobjectname = $canvas->{'_id'} . '.pdf';
            my $pdffilename = $workdir . '/' . uri_escape_utf8($pdfobjectname);
            if ( -f $pdffilename ) {
                my $pages = 0;
                try {
                    my $pdf = Poppler::Document->new_from_file($pdffilename);
                    $pages = $pdf->get_n_pages;
                };
                if ( $pages == 1 ) {
                    open( my $fh, '<:raw', $pdffilename )
                      or die "Can't open '$pdffilename': $!";
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
                    print Dumper ($pdffilename,$filedate, $size, $md5digest);

                }
                else {
                    warn "$pdffilename is not a single page PDF\n";
                }
            }
            else {
                warn "$pdffilename doesn't exist\n";
            }

            my $xmlobjectname = $canvas->{'_id'} . '.xml';
            my $xmlfilename = $workdir . '/' . uri_escape_utf8($xmlobjectname);
            if ( -f $xmlfilename ) {
                my $valid = 1;
                try {
                    my $xml = XML::LibXML->new->parse_file($xmlfilename);
                    my $xpc = XML::LibXML::XPathContext->new($xml);
                    $xpc->registerNs( 'alto',
                        'http://www.loc.gov/standards/alto/ns-v3' );
                    my $schema =
                      XML::LibXML::Schema->new( location =>
                          "/opt/xml/current/unpublished/xsd/alto-3-1.xsd" );
                    $schema->validate($xml);
                }
                catch {
                    $valid = 0;
                    warn "$xmlfilename is not valid ALTO XML: $_\n";
                };
                if ($valid) {
                    print "$xmlfilename is valid\n";
                }
            }
            else {
                warn "$xmlfilename doesn't exist\n";
            }
        }
    }
    die "Still testing\n";
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

{

    package restclient;

    use Moo;
    with 'Role::REST::Client';
}

1;
