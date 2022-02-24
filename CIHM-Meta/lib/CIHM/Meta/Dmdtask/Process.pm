package CIHM::Meta::Dmdtask::Process;

use 5.014;
use strict;
use XML::LibXML;
use Try::Tiny;
use JSON;
use Switch;
use URI::Escape;
use Data::Dumper;
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

=head1 NAME

CIHM::Meta::Dmdtask::Process - Handles the processing of individual tasks

=head1 SYNOPSIS

    my $process = CIHM::Meta::Dmdtask::Process->new($args);
      where $args is a hash of arguments.



   Schema docs for CouchDB are in
   https://github.com/crkn-rcdr/Access-Platform/tree/main/packages/data/src/dmd

=cut

our $self;

sub new {
    my ( $class, $args ) = @_;
    our $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::Hammer2::Process->new() not a hash\n";
    }
    $self->{args} = $args;

    if ( !$self->log ) {
        die "Log::Log4perl object parameter is mandatory\n";
    }
    if ( !$self->dmdtaskdb ) {
        die "dmdtaskdb object parameter is mandatory\n";
    }

    $self->{flatten} = CIHM::Meta::dmd::flatten->new;

    $self->{items} = [];
    $self->{xml}   = [];
    return $self;
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}

sub taskid {
    my $self = shift;
    return $self->args->{taskid};
}

sub type {
    my $self = shift;
    return $self->args->{type};
}

sub log {
    my $self = shift;
    return $self->args->{log};
}

sub dmdtaskdb {
    my $self = shift;
    return $self->args->{dmdtaskdb};
}

sub items {
    my $self = shift;
    return $self->{items};
}

sub xml {
    my $self = shift;
    return $self->{xml};
}

sub doc {
    my $self = shift;
    return $self->{doc};
}

sub flatten {
    my $self = shift;
    return $self->{flatten};
}

sub get_document {
    my $self = shift;

    $self->{doc} = $self->dmdtaskdb->get_document( $self->taskid );
    if ( !( $self->doc ) ) {
        die "Couldn't load task document\n";
    }
    return;
}

# Top method
sub process {
    my ($self) = @_;

    $self->get_document();

    # Clean out old output attachments if they exist
    $self->cleanup();

    my $attach = $self->get_attachment();
    die "Missing `metadata` attachment\n" if !$attach;

    switch ( $self->doc->{format} ) {
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

=pod
    # Debugging -- matching indexes between XML and Items
    foreach my $index ( 0 .. scalar( @{ $self->xml } ) - 1 ) {
        print Data::Dumper->Dump(
            [
                {
                    xml  => @{ $self->xml }[$index],
                    item => @{ $self->items }[$index]
                }
            ],
            [$index]
        );
    }

=cut

    return $self->items;
}

sub get_attachment {
    my ($self) = @_;
    my ($res);

    $self->dmdtaskdb->clear_headers;
    $res =
      $self->dmdtaskdb->get(
        "/" . $self->dmdtaskdb->database . "/" . $self->taskid . "/metadata",
        {}, { deserializer => undef } );
    if ( $res->code != 200 ) {
        warn "get_attachment("
          . $self->taskid
          . "/metadata) GET return code: "
          . $res->code . "\n";
        return;
    }
    return $res->data;
}

# Clean up any attachments that might be from previous run
sub cleanup {
    my ($self) = @_;

    if ( exists $self->doc->{'_attachments'} ) {
        my $modified = 0;

        foreach my $attachment ( keys %{ $self->doc->{'_attachments'} } ) {
            if ( $attachment ne 'metadata' ) {
                delete $self->doc->{'_attachments'}->{$attachment};
                $modified = 1;
            }
        }
        if ($modified) {

            # In case it exists, might as well...
            delete $self->doc->{'items'};

            # Update the document
            $self->dmdtaskdb->put_document( $self->taskid, $self->doc );

            # Get a copy of the updated document (with Attachments removed)
            $self->get_document();
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

    foreach my $index ( 0 .. scalar( @{ $self->xml } ) - 1 ) {
        $self->doc->{'_attachments'}->{ $index . ".xml" } = {
            'content_type' => 'application/xml',
            'data'         => encode_base64( @{ $self->xml }[$index] )
        };
    }
    $self->dmdtaskdb->put_document( $self->taskid, $self->doc );

    # Get a copy of the updated document (with Attachments as stubs)
    $self->get_document();
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

    foreach my $index ( 0 .. scalar( @{ $self->xml } ) - 1 ) {

        # Capture warnings
        $self->clear_warnings();
        local $SIG{__WARN__} = sub { &collect_warnings };

        my $xml  = @{ $self->xml }[$index];
        my $item = @{ $self->items }[$index];

        $self->doc->{'_attachments'}->{ $index . ".json" } = {
            'content_type' => 'application/json',
            'data'         => encode_base64(
                encode_json(
                    $self->flatten->byType(
                        $item->{output},
                        utf8::is_utf8($xml)
                        ? Encode::encode_utf8($xml)
                        : $xml
                    )
                )
            )
        };

        @{ $self->items }[$index]->{message} .= $self->warnings;
    }

    $self->dmdtaskdb->put_document( $self->taskid, $self->doc );

    # Get a copy of the updated document (with Attachments as stubs)
    $self->get_document();

}

1;
