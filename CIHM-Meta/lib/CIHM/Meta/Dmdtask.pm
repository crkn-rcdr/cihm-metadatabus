package CIHM::Meta::Dmdtask;

use strict;
use Carp;

use Try::Tiny;
use JSON;
use Data::Dumper;

use Switch;
use CIHM::Swift::Client;
use CIHM::Meta::dmd::flatten qw(normaliseSpace);
use List::Util qw(first);
use List::MoreUtils qw(uniq);
use MARC::Batch;
use MARC::File::XML ( BinaryEncoding => 'utf8', RecordFormat => 'USMARC' );
use MARC::File::USMARC;
use File::Temp;
use Encode;
use Text::CSV;
use MIME::Base64;
use URI::Escape;
use Digest::MD5 qw(md5 md5_hex md5_base64);

=head1 NAME

CIHM::Meta::Dmdtask - Process metadata uploads and potentially copy to Preservation and/or Acccess platforms.


=head1 SYNOPSIS

    my $dmdtask = CIHM::Meta::Dmdtask->new($args);
      where $args is a hash of arguments.

      $args->{configpath} is as used by Config::General

=cut

our $self;

sub new {
    my ( $class, $args ) = @_;
    our $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::Hammer2->new() not a hash\n";
    }
    $self->{args} = $args;

    # Connect to Swift Object Storage
    my %swiftopt = ( furl_options => { timeout => 3600 } );
    foreach ( "server", "user", "password", "account" ) {
        if ( exists $args->{ "swift_" . $_ } ) {
            $swiftopt{$_} = $args->{ "swift_" . $_ };
        }
    }
    $self->{swift} = CIHM::Swift::Client->new(%swiftopt);

    my $test = $self->swift->container_head( $self->access_metadata );
    if ( !$test || $test->code != 204 ) {
        die "Problem connecting to Swift container. Check configuration\n";
    }

    # Connect to CouchDB
    $self->{accessdb} = new restclient(
        server      => $args->{couchdb_access},
        type        => 'application/json',
        clientattrs => { timeout => 3600 },
    );
    $self->accessdb->set_persistent_header( 'Accept' => 'application/json' );
    $test = $self->accessdb->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to Couchdb database="
          . $args->{couchdb_access}
          . " Check configuration\n";
    }

    $self->{dmdtaskdb} = new restclient(
        server      => $args->{couchdb_dmdtask},
        type        => 'application/json',
        clientattrs => { timeout => 3600 },
    );
    $self->dmdtaskdb->set_persistent_header( 'Accept' => 'application/json' );
    $test = $self->dmdtaskdb->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to Couchdb database="
          . $args->{couchdb_dmdtask}
          . " Check configuration\n";
    }

    $self->{wipmetadb} = new restclient(
        server      => $args->{couchdb_wipmeta},
        type        => 'application/json',
        clientattrs => { timeout => 3600 },
    );
    $self->wipmetadb->set_persistent_header( 'Accept' => 'application/json' );
    $test = $self->wipmetadb->head("/");
    if ( !$test || $test->code != 200 ) {
        die "Problem connecting to Couchdb database="
          . $args->{couchdb_wipmeta}
          . " Check configuration\n";
    }

    # Set up in-progress hash (Used to determine which AIPs which are being
    # processed by a slave so we don't try to do the same AIP twice.
    $self->{inprogress} = {};

    $self->{flatten} = CIHM::Meta::dmd::flatten->new;

    $self->{items}         = [];
    $self->{xml}           = [];
    $self->{storageresult} = [];

    return $self;
}

{

    package restclient;

    use Moo;
    with 'Role::REST::Client';
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}

sub pagesize {
    my $self = shift;
    return $self->args->{pagesize};
}

sub log {
    my $self = shift;
    return $self->args->{logger};
}

sub accessdb {
    my $self = shift;
    return $self->{accessdb};
}

sub dmdtaskdb {
    my $self = shift;
    return $self->{dmdtaskdb};
}

sub wipmetadb {
    my $self = shift;
    return $self->{wipmetadb};
}

sub access_metadata {
    my $self = shift;
    return $self->args->{swift_access_metadata};
}

sub swift {
    my $self = shift;
    return $self->{swift};
}

sub document {
    my $self = shift;
    return $self->{document};
}

sub taskid {
    my $self = shift;
    return $self->document->{'_id'} if $self->document;
}

sub destination {
    my $self = shift;
    return $self->document->{destination} if $self->document;
}

sub items {
    my $self = shift;
    return $self->{items};
}

sub xml {
    my $self = shift;
    return $self->{xml};
}

sub flatten {
    my $self = shift;
    return $self->{flatten};
}

sub dmdtask {
    my ($self) = @_;

    $self->log->info("Dmdtask");

    my $somework;
    while ( my $task = $self->getNextTask() ) {
        $somework = 1;
        $self->{document} = $task;
        $self->handleTask();
    }
    if ($somework) {
        $self->log->info("Finished.");
    }
}

sub getDocument {
    my $self = shift;

    $self->dmdtaskdb->type("application/json");

    my $url = "/" . uri_escape_utf8( $self->taskid );

    my $res =
      $self->dmdtaskdb->get( $url, {}, { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        $self->{document} = $res->data;
    }
    else {
        warn "GET $url return code: " . $res->code . "\n";
        return;
    }
}

sub headDocument {
    my $self = shift;

    $self->dmdtaskdb->type("application/json");

    my $url = "/" . uri_escape_utf8( $self->taskid );

    my $res =
      $self->dmdtaskdb->head( $url, {},
        { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        my $revision = $res->response->header("etag");
        $revision =~ s/^\"|\"$//g;
        return $revision;
    }
    else {
        warn "HEAD $url return code: " . $res->code . "\n";
        return;
    }
}

sub getAttachment {
    my ( $self, $attachment ) = @_;
    my $self = shift;

    $self->dmdtaskdb->type("application/json");

    my $url = "/" . uri_escape_utf8( $self->taskid ) . "/$attachment";

    my $res = $self->dmdtaskdb->get($url);
    if ( $res->code == 200 ) {
        return $res->data;
    }
    else {
        warn "GET $url return code: " . $res->code . "\n";
        return;
    }
}

sub putAttachment {
    my ( $self, $revision, $name, $type, $data ) = @_;
    my $self = shift;

    $self->dmdtaskdb->type($type);

    my $url = "/" . uri_escape_utf8( $self->taskid ) . "/$name";

    $self->dmdtaskdb->clear_headers;
    $self->dmdtaskdb->set_header( 'If-Match' => $revision ) if $revision;
    $self->dmdtaskdb->type($type);

    my $res =
      $self->dmdtaskdb->put( $url, $data,
        { deserializer => 'application/json' } );
    if ( $res->code == 201 ) {
        return $res->data->{rev};
    }
    else {
        if ( $res->failed ) {
            warn "Content: " . $res->response->content;
        }
        warn "PUT $url return code: " . $res->code . "\n";
        return;
    }
}

sub putDocument {
    my $self = shift;

    $self->dmdtaskdb->type("application/json");

    my $url = "/" . uri_escape_utf8( $self->taskid );

    my $res =
      $self->dmdtaskdb->put( $url, $self->document,
        { deserializer => 'application/json' } );
    if ( $res->code != 201 ) {
        die "PUT $url return code: " . $res->code . "\n";
    }
}

sub top_warnings {
    my $warning = shift;
    our $self;
    my $taskid = "unknown";

    # Strip wide characters before  trying to log
    ( my $stripped = $warning ) =~ s/[^\x00-\x7f]//g;

    if ($self) {
        $self->{message} .= $warning;
        $taskid = $self->taskid;
        $self->log->warn( $taskid . ": $stripped" );
    }
    else {
        say STDERR "$warning\n";
    }
}

sub handleTask {
    my ($self) = @_;

    my $taskid = $self->taskid;
    $self->{message} = '';

    # Reset to empty array for new task.
    $self->{items} = [];
    $self->{xml}   = [];

    # Capture warnings
    local $SIG{__WARN__} = sub { &top_warnings };

    $self->log->info("Processing $taskid");

    my $status;

    # Undefined, but should have items array otherwise?
    my $results;

    # Handle and record any errors
    try {
        $status = JSON::true;

        if (   ( defined $self->document->{items} )
            && ( ref $self->document->{items} ) eq 'ARRAY' )
        {

            my @workItems;
            $self->{items} = $self->document->{items};
            for (
                my $index = 0 ;
                $index < scalar( @{ $self->document->{items} } ) ;
                $index++
              )
            {
                my $item = $self->items->[$index];
                if (
                       exists $item->{shouldStore}
                    && $item->{shouldStore} == JSON::true
                    && ( !exists $item->{stored}
                        || $item->{stored} != JSON::true )
                  )
                {
                    push @workItems, { index => $index, item => $item };
                }
            }
            if (@workItems) {
                $self->pagedStore( \@workItems );
            }
        }
        else {
            # Clean out old output attachments if they exist
            $self->cleanup();

            my $attach = $self->getAttachment("metadata");
            die "Missing `metadata` attachment\n" if !$attach;

            switch ( $self->document->{format} ) {
                case "csvissueinfo" { $self->extractissueinfo_csv($attach); }

                case "csvdc" { $self->extractdc_csv($attach); }

                case "marc490" {
                    $self->extractxml_marc($attach);
                    $self->process_marc("490");
                }
                case "marcoocihm" {
                    $self->extractxml_marc($attach);
                    $self->process_marc("oocihm");
                }
                case "marcooe" {
                    $self->extractxml_marc($attach);
                    $self->process_marc("ooe");
                }

                else { die "Don't recognize format field\n" }
            }

            $self->store_xml();
            $self->validate_xml();
            $self->store_flatten();
        }
    }
    catch {
        $status = JSON::false;
        $self->log->error("$taskid: $_");
        $self->{message} .= "Caught: " . $_;
    };
    $self->postResults( $taskid, $status, $self->{message} );

    return ($taskid);
}

sub pagedStore {
    my ( $self, $items ) = @_;

    my $attach = $self->getAttachment("dmd.json");
    die "Missing `dmd.json` attachment\n" if !$attach;
    die "'dmd.json' not an array\n" if ref $attach ne "ARRAY";

    $self->{xml} = $attach;

    if (   $self->destination ne "access"
        && $self->destination ne "preservation" )
    {
        die "Destination Unknown!\n";
    }

    # Use Boolean for which of "access" or "preservation"
    # Would need to change if a third destination was created.
    my $da = ( $self->destination eq "access" );

    # Page thorough items
    for (
        my $index = 0 ;
        $index < scalar( @{$items} ) ;
        $index += $self->pagesize
      )
    {
        my $last = $index + ( $self->pagesize ) - 1;
        if ( $last >= scalar( @{$items} ) ) {
            $last = scalar( @{$items} ) - 1;
        }

        my @ids;
        foreach my $i ( $index .. $last ) {
            push @ids, $items->[$i]->{item}->{id};
        }

        my $res;
        if ($da) {
            $res = $self->accessdb->post(
                "/_design/access/_view/slug",
                {
                    keys         => \@ids,
                    include_docs => JSON::true
                },
                { deserializer => 'application/json' }
            );
        }
        else {
            $res = $self->wipmetadb->post(
                "/_all_docs",
                {
                    keys         => \@ids,
                    include_docs => JSON::true
                },
                { deserializer => 'application/json' }
            );
        }
        if ($res) {
            if ( $res->code == 200 ) {
                my %docs;
                foreach my $row ( @{ $res->data->{rows} } ) {
                    if ( defined $row->{doc} ) {
                        $docs{
                              $da
                            ? $row->{doc}->{'slug'}
                            : $row->{doc}->{'_id'}
                        } = $row->{doc};
                    }
                }

                foreach my $i ( $index .. $last ) {
                    my $id = $items->[$i]->{item}->{id};
                    if ( !exists $docs{$id} ) {
                        $self->addStorageResult( $items->[$i]->{index},
                            JSON::false );
                        warn "CouchDB document for id=$id wasn't found.\n";
                    }
                    else {

                        my $response =
                          $da
                          ? (
                            $self->storeAccess(
                                $docs{$id}, $items->[$i], $self->xml->[$i]
                            )
                          )
                          : (
                            $self->storePreservation(
                                $docs{$id}, $items->[$i], $self->xml->[$i]
                            )
                          );
                        $self->addStorageResult( $items->[$i]->{index},
                            $response ? JSON::true : JSON::false );
                    }

                }

                # Update work so far in the task document.
                $self->updateStorageResults();

            }    # It wasn't a 200 return from getting the documents...
            else {
                if ( defined $res->response->content ) {
                    warn $res->response->content . "\n";
                }
                die "Lookups of IDs for destination="
                  . $self->destination
                  . " return code: "
                  . $res->code . "\n";
            }
        }
    }
}

sub storeAccess {
    my ( $self, $doc, $item, $xml ) = @_;

    my $id = $doc->{'_id'};

    # Check if we need to delete the old first
    if ( $doc->{'dmdType'} ne $item->{item}->{output} ) {
        my $object = $doc->{'_id'} . '/dmd' . uc( $doc->{'dmdType'} ) . '.xml';

        my $r = $self->swift->object_delete( $self->access_metadata, $object );
        if ( $r->code != 404 && $r->code != 204 ) {
            if ( defined $r->_fr->content ) {
                warn $r->_fr->content . "\n";
            }
            warn "Failed deleting $object - returned " . $r->code . "\n";
            return 0;
        }
    }

    my $dmdRecord = utf8::is_utf8($xml) ? Encode::encode_utf8($xml) : $xml;
    my $dmdDigest = md5_hex($dmdRecord);

    my $object =
      $doc->{'_id'} . '/dmd' . uc( $item->{item}->{output} ) . '.xml';
    my $r = $self->swift->object_head( $self->access_metadata, $object );
    if ( $r->code == 404 || ( $r->etag ne $dmdDigest ) ) {
        $r =
          $self->swift->object_put( $self->access_metadata, $object,
            $dmdRecord );
        if ( $r->code != 201 ) {
            if ( defined $r->_fr->content ) {
                warn $r->_fr->content . "\n";
            }
            warn "Failed writing $object - returned " . $r->code . "\n";
            return 0;
        }
        elsif ( $r->etag ne $dmdDigest ) {
            warn "object_put($object) didn't return matching etag\n";
            return 0;
        }
    }
    elsif ( $r->code != 200 ) {
        if ( defined $r->_fr->content ) {
            warn $r->_fr->content . "\n";
        }
        warn "Head for $object - returned " . $r->code . "\n";
        return 0;
    }

    # Update database...
    my $url = "/_design/access/_update/editObject/" . uri_escape_utf8($id);

    # editObject() will merge fields into existing document
    my $updateDoc = {
        dmdType => $item->{item}->{output},
        label   => {
            none => $item->{item}->{label}
        }
    };

    $self->accessdb->type("application/json");
    my $res = $self->accessdb->post(
        $url,
        { data         => $updateDoc },
        { deserializer => 'application/json' }
    );
    if ( $res->code != 201 ) {
        if ( defined $res->response->content ) {
            warn $res->response->content . "\n";
        }
        warn "storeAccess id=$id return code: " . $res->code . "\n";
        return 0;
    }

    return 1;
}

sub storePreservation {
    my ( $self, $doc, $item, $xml ) = @_;

    my $id  = $doc->{'_id'};
    my $rev = $doc->{'_rev'};

    #print Data::Dumper->Dump( [ $doc, $item, $xml ],
    #    [qw (preservationdoc item xml)] );

    # TODO:  attach XML in CouchDB, set dmdType and label

    return 1;
}

sub addStorageResult {
    my ( $self, $index, $status ) = @_;

    push @{ $self->{storageresult} }, [ $index, $status ];

    # We store the completed items array at end
    @{ $self->items }[$index]->{stored} = $status;
}

sub updateStorageResults {
    my ($self) = @_;

    my $taskid = $self->taskid;

    my ( $res, $code, $data );

    #  Post directly as JSON data (Different from other couch databases)
    $self->dmdtaskdb->type("application/json");
    my $url = "/_design/access/_update/updateStorageResults/"
      . uri_escape_utf8($taskid);
    $res = $self->dmdtaskdb->post(
        $url,
        $self->{storageresult},
        { deserializer => 'application/json' }
    );

    if ( $res->code != 201 && $res->code != 200 ) {
        if ( exists $res->{message} ) {
            $self->log->info( $taskid . ": message=" . $res->{message} );
        }
        if ( exists $res->{content} ) {
            $self->log->info( $taskid . ": content=" . $res->{content} );
        }
        if ( exists $res->{error} ) {
            $self->log->error( $taskid . ": error=" . $res->{error} );
        }
        if ( ( ref $res->data eq "HASH" ) && ( exists $res->data->{error} ) ) {
            $self->log->error(
                $taskid . ": data error=" . $res->data->{error} );
        }
        $self->log->info( $taskid . ": $url POST return code: " . $res->code );
    }

    $self->{storageresult} = [];
}

sub postResults {
    my ( $self, $taskid, $status, $message ) = @_;

    my ( $res, $code, $data );

    #  Post directly as JSON data (Different from other couch databases)
    $self->dmdtaskdb->type("application/json");

    # Make use of update function support of "delete"
    my $sendItems = $self->items;
    if ( ( ref $sendItems ne "ARRAY" ) || ( !scalar( @{$sendItems} ) ) ) {
        $sendItems = "delete";
    }

    my $url = "/_design/access/_update/process/" . uri_escape_utf8($taskid);
    $res = $self->dmdtaskdb->post(
        $url,
        {
            succeeded => $status,
            message   => $message,
            items     => $sendItems
        },
        { deserializer => 'application/json' }
    );

    if ( $res->code != 201 && $res->code != 200 ) {
        if ( exists $res->{message} ) {
            $self->log->info( $taskid . ": message=" . $res->{message} );
        }
        if ( exists $res->{content} ) {
            $self->log->info( $taskid . ": content=" . $res->{content} );
        }
        if ( exists $res->{error} ) {
            $self->log->error( $taskid . ": error=" . $res->{error} );
        }
        if ( ( ref $res->data eq "HASH" ) && ( exists $res->data->{error} ) ) {
            $self->log->error(
                $taskid . ": data error=" . $res->data->{error} );
        }
        $self->log->info( $taskid . ": $url POST return code: " . $res->code );
    }
}

sub getNextTask {
    my ($self) = @_;

    $self->dmdtaskdb->type("application/json");
    my $url = "/_design/access/_view/processQueue";
    my $res = $self->dmdtaskdb->post(
        $url,
        { reduce => JSON::false, include_docs => JSON::true, limit => 1 },
        { deserializer => 'application/json' }
    );
    if ( $res->code == 200 ) {
        if ( exists $res->data->{rows} ) {
            foreach my $hr ( @{ $res->data->{rows} } ) {
                if ( exists $hr->{doc} ) {
                    return $hr->{doc};
                }
            }
        }
    }
    else {
        warn "$url GET return code: " . $res->code . "\n";
    }
    return;
}

# Clean up any attachments that might be from previous run
sub cleanup {
    my ($self) = @_;

    if ( exists $self->document->{'_attachments'} ) {
        my $modified = 0;

        foreach my $attachment ( keys %{ $self->document->{'_attachments'} } ) {
            if ( $attachment ne 'metadata' ) {
                delete $self->document->{'_attachments'}->{$attachment};
                $modified = 1;
            }
        }
        if ($modified) {

            # In case it exists, might as well...
            delete $self->document->{'items'};

            # Update the document
            $self->putDocument();

            # Get a copy of the updated document (with Attachments removed)
            $self->getDocument();
        }
    }
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

    $self->{warnings} .= $warning;
}

sub extractissueinfo_csv {
    my ( $self, $data ) = @_;

    my @sequence = (
        'series',     'title',     'sequence',     'language',
        'coverage',   'published', 'pubstatement', 'source',
        'identifier', 'note'
    );

    # Library has a parse(), but storing as file to handle Embedded newlines
    # https://metacpan.org/pod/Text::CSV#Embedded-newlines
    my $tmp = File::Temp->new( UNLINK => 0, SUFFIX => '.csv' );
    print $tmp $data;
    my $tempname = $tmp->filename;
    close $tmp;

    #process csv file
    my $csv = Text::CSV->new( { binary => 1 } );
    open my $fh, "<:encoding(utf8)", $tempname
      or die "Cannot read $tempname: $!\n";

    my $headerline = $csv->getline($fh);
    if ( !$headerline ) {
        die "Missing header line in CSV file\n";
    }

    # Create hash from headerline
    my %headers;
    my @unknownheader;
    for ( my $i = 0 ; $i < @$headerline ; $i++ ) {
        my $header = $headerline->[$i];
        my $value = { index => $i };
        if ( index( $header, '=' ) != -1 ) {
            my $type;
            ( $header, $type ) = split( '=', $header );
            $value->{type} = $type;
        }

        if (   $header eq 'objid'
            || $header eq 'label'
            || first { $_ eq $header } @sequence )
        {
            if ( !exists $headers{$header} ) {
                $headers{$header} = [];
            }
            push @{ $headers{$header} }, $value;
        }
        else {
            push @unknownheader, $header;
        }
    }
    if (@unknownheader) {
        warn "The following headers are unknown: "
          . join( ',', @unknownheader ) . "\n";
    }
    die "'title' header missing\n" if ( !defined $headers{'title'} );
    die "'label' header missing\n" if ( !defined $headers{'label'} );

    my %series;
    while ( my $row = $csv->getline($fh) ) {

        #get object id
        my $objid_column =
          first { @$headerline[$_] eq 'objid' } 0 .. @$headerline;

        #process each metadata record based on the object ID
        my $id = $row->[$objid_column];

        if ( !$id || $id =~ /^\s*$/ ) {
            warn "Line missing ID - skipping\n";
            next;
        }

        # Capture warnings
        $self->clear_warnings();
        local $SIG{__WARN__} = sub { &collect_warnings };

        my %item = (
            id      => $id,
            output  => 'issueinfo',
            message => '',
            parsed  => JSON::true
        );

        my $doc = XML::LibXML::Document->new( "1.0", "UTF-8" );
        my $root = $doc->createElement('issueinfo');
        $root->setAttribute(
            'xmlns' => 'http://canadiana.ca/schema/2012/xsd/issueinfo' );

        foreach my $element (@sequence) {
            if ( exists $headers{$element} ) {
                foreach my $elementtype ( @{ $headers{$element} } ) {
                    my $value = $row->[ $elementtype->{'index'} ];
                    if ( $element eq "coverage" ) {
                        my $child     = XML::LibXML::Element->new($element);
                        my $attribute = 0;
                        if ( $value =~ /start=([0-9-]+)/i ) {
                            $child->setAttribute( 'start', $1 );
                            $attribute++;
                        }
                        if ( $value =~ /end=([0-9-]+)/i ) {
                            $child->setAttribute( 'end', $1 );
                            $attribute++;
                        }
                        $root->appendChild($child);

                        if ( !$attribute ) {
                            warn "Unable to parse coverage value: $value\n";
                        }
                    }
                    else {
                        my $type = $elementtype->{'type'};

                        #split on delimiters
                        my @values = split( /\s*\|\|\s*/, $value );
                        foreach (@values) {
                            my $child = XML::LibXML::Element->new($element);
                            $child->appendTextNode($_);
                            if ($type) {
                                $child->setAttribute( 'type', $type );
                            }
                            $root->appendChild($child);
                        }
                    }
                }
            }
        }

        #create xml file
        $doc->setDocumentElement($root);

        # Store the XML (for more processing)
        push @{ $self->xml }, $doc->toString(0);

        $item{'label'} = $row->[ $headers{'label'}[0]->{'index'} ];
        if ( !$item{'label'} ) {
            $item{'label'} = '[unknown]';
        }

        $item{message} .= $self->warnings;

        # Store the item
        push @{ $self->items }, \%item;

    }
}

sub extractdc_csv {
    my ( $self, $data ) = @_;

    # Library has a parse(), but storing as file to handle Embedded newlines
    # https://metacpan.org/pod/Text::CSV#Embedded-newlines
    my $tmp = File::Temp->new( UNLINK => 0, SUFFIX => '.csv' );
    print $tmp $data;
    my $tempname = $tmp->filename;
    close $tmp;

    #process csv file
    my $csv = Text::CSV->new( { binary => 1 } );
    open my $fh, "<:encoding(utf8)", $tempname
      or die "Cannot read $tempname: $!\n";

    my $header = $csv->getline($fh);

    #get object id
    my $objid_column =
      first { @$header[$_] && @$header[$_] eq 'objid' } 0 .. @$header;
    if ( !defined $objid_column ) {
        die "column 'objid' header not found in first row\n";
    }

    while ( my $row = $csv->getline($fh) ) {

        #process each metadata record based on the object ID
        my $id = $row->[$objid_column];
        if ( !$id || $id =~ /^\s*$/ ) {
            warn "Line missing ID --- skipping!\n";
            next;
        }

        # Capture warnings
        $self->clear_warnings();
        local $SIG{__WARN__} = sub { &collect_warnings };

        my %item = (
            id      => $id,
            output  => 'dc',
            message => '',
            parsed  => JSON::true
        );

        my $doc = XML::LibXML::Document->new( "1.0", "UTF-8" );
        my $root = $doc->createElement('simpledc');
        $root->setNamespace( 'http://purl.org/dc/elements/1.1/', 'dc', 0 );

        # map header to dc element and process values
        foreach my $thisheader (@$header) {
            if ( substr( $thisheader, 0, 3 ) eq 'dc:' ) {
                set_element( $thisheader, $header, $row, $root );
            }
        }

        #create xml file
        $doc->setDocumentElement($root);

        # Store the XML (for more processing)
        push @{ $self->xml }, $doc->toString(0);

        $item{'label'} = '[unknown]';
        my $label_col;
        my $label;
        $label_col = first { @$header[$_] eq 'dc:title' } 0 .. @$header;
        if ($label_col) {
            my $label_value = $row->[$label_col];

            #split on delimiters
            my @titles = split( /\s*\|\|\s*/, $label_value );
            $item{'label'} = $titles[0];
        }

        $item{message} .= $self->warnings;

        # Store the item
        push @{ $self->items }, \%item;
    }

}

sub set_element {
    my ( $header, $header_array, $row, $root ) = @_;

    my $header_index =
      first { @$header_array[$_] eq $header } 0 .. @$header_array;
    my $value = $row->[$header_index];

    #split on delimiters
    my @values = split( /\s*\|\|\s*/, $value );
    foreach (@values) {
        $root->appendTextChild( $header, $_ );
    }
}

sub extractxml_marc {
    my ( $self, $data ) = @_;

    # Library doesn't support multi-record formats from strings, only files...
    # So -- ugly hack.
    my $tmp = File::Temp->new( UNLINK => 0, SUFFIX => '.mrc' );
    print $tmp $data;
    my $tempname = $tmp->filename;
    close $tmp;

    my $marc;
    eval { $marc = MARC::Batch->new( "USMARC", $tempname ); };
    if ( !$marc ) {
        die "Couldn't process file\n\n$@";
    }

    # I'm collecting these in a different place -- don't also sent to STDERR
    $marc->warnings_off();

    while ( my $record = $marc->next ) {

        # Capture warnings
        $self->clear_warnings();
        local $SIG{__WARN__} = sub { &collect_warnings };

        my @warnings = $record->warnings();
        foreach my $thiswarning (@warnings) {
            warn $thiswarning . "\n";
        }

        # Create xml structure
        # Using the "encode_utf8" function to encode to Perl's internal format
        my $xml = encode_utf8(
            join( "",
                MARC::File::XML::header(), MARC::File::XML::record($record),
                MARC::File::XML::footer() )
        );

        # Store the XML (for more processing)
        push @{ $self->xml }, $xml;

        # Initialize the item.
        # MARC::Batch outputs warnings as it processes the file,
        # so these can end up matched with the record.
        push @{ $self->items },
          {
            message => $self->warnings,
            output  => "marc"
          };
    }
    my @warnings = $marc->warnings();
    foreach my $thiswarning (@warnings) {
        warn $thiswarning . "\n";
    }
    if ( !scalar( @{ $self->items } ) ) {
        die "No records found.  Was it a MARC 21 binary file?\n";
    }
}

sub process_marc {
    my ( $self, $idschema ) = @_;

    foreach my $index ( 0 .. scalar( @{ $self->xml } ) - 1 ) {

        # Capture warnings
        $self->clear_warnings();
        local $SIG{__WARN__} = sub { &collect_warnings };

        my $record;
        eval {
            $record = MARC::Record->new_from_xml( @{ $self->xml }[$index] );
        };
        if ( !$record ) {
            warn "Couldn't parse record index=$index\n\n$@";
            @{ $self->items }[$index]->{parsed} = JSON::false;
            @{ $self->items }[$index]->{message} .= $self->warnings;
            next;
        }

        my $label = $record->subfield( 245, "a" );
        if ( !$label || $label =~ /^\s*$/ ) {
            warn "Label can't be extracted from 245a\n";
            $label = '[unknown]';
        }

        my $objid;
        switch ($idschema) {
            case "ooe" {
                $objid = substr( $record->subfield( '035', 'a' ), 1 );
            }
            case [ "490", "oocihm" ] {
                my $sf3 = $record->subfield( 490, "3" );
                my $sfv = $record->subfield( 490, "v" );
                if ( $sfv && $sfv ne '' ) {
                    if ( $sf3 && $sf3 ne '' ) {
                        $objid = join( '_', $sf3, $sfv );
                    }
                    else {
                        $objid = $sfv;
                        if ( $idschema eq 'oocihm' ) {
                            $objid =~ s/-/_/g;
                            $objid =~ s/[^0-9_]//g;
                        }
                    }
                }
                else {
                    warn "490v is missing\n";
                    $objid = '[unknown]';
                }

            }
            else { die "Don't recognize idschema=$idschema\n" }
        }

        # So far, so good...
        @{ $self->items }[$index]->{parsed} = JSON::true;
        @{ $self->items }[$index]->{label}  = $label;
        @{ $self->items }[$index]->{id}     = $objid;
        @{ $self->items }[$index]->{message} .= $self->warnings;

    }
}

sub store_xml {
    my ($self) = @_;

  # Document is allowed to change in background by web interface, so get latest.
    $self->getDocument();

    my $newrev = $self->putAttachment(
        $self->document->{'_rev'}, "dmd.json",
        "application/json",        $self->xml
    );
    die "Failure storing dmd.json attachment\n" if !$newrev;
    $self->document->{'_rev'} = $newrev;

}

sub validate_xml {
    my ($self) = @_;

    foreach my $index ( 0 .. scalar( @{ $self->xml } ) - 1 ) {

        # Capture warnings
        $self->clear_warnings();
        local $SIG{__WARN__} = sub { &collect_warnings };

        my $xml  = @{ $self->xml }[$index];
        my $item = @{ $self->items }[$index];

        # If it is already bad, it's still bad.
        next if ( !$item->{parsed} );

        my $xsdfile;
        switch ( $item->{output} ) {
            case "marc" {
                $xsdfile = '/opt/xml/current/unpublished/xsd/MARC21slim.xsd';
            }
            case "dc" {
                $xsdfile = '/opt/xml/current/unpublished/xsd/simpledc.xsd';
            }
            case "issueinfo" {
                $xsdfile = '/opt/xml/current/published/xsd/issueinfo.xsd';
            }
            else { die "Don't recognize output=" . $item->{output} . "\n"; }
        }

        my $parsed;
        try {
            $parsed = JSON::true;

            my $doc = XML::LibXML->load_xml( string => $xml );
            my $schema = XML::LibXML::Schema->new( location => $xsdfile );

            # Will die if validation failed.
            $schema->validate($doc);
        }
        catch {
            $parsed = JSON::false;
            warn "XML Validation failed:\n\n$_";
        };

        # Set status
        $item->{parsed} = $parsed;
        $item->{message} .= $self->warnings;
    }
}

sub store_flatten {
    my ($self) = @_;

    my @flatten;

    foreach my $index ( 0 .. scalar( @{ $self->xml } ) - 1 ) {

        # Capture warnings
        $self->clear_warnings();
        local $SIG{__WARN__} = sub { &collect_warnings };

        my $xml  = @{ $self->xml }[$index];
        my $item = @{ $self->items }[$index];

        $flatten[$index] =
          $self->flatten->byType( $item->{output},
              utf8::is_utf8($xml)
            ? Encode::encode_utf8($xml)
            : $xml );

        @{ $self->items }[$index]->{message} .= $self->warnings;
    }

  # Document is allowed to change in background by web interface, so get latest.
    $self->getDocument();

    my $newrev = $self->putAttachment(
        $self->document->{'_rev'}, "flatten.json",
        "application/json",        \@flatten
    );
    die "Failure storing flatten.json attachment\n" if !$newrev;
    $self->document->{'_rev'} = $newrev;
}

1;
