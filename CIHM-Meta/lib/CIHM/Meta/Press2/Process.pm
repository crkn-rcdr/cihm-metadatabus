package CIHM::Meta::Press2::Process;

use 5.014;
use strict;
use Try::Tiny;
use JSON;
use DateTime;

=head1 NAME

CIHM::Meta::Press2::Process - Handles the processing of individual AIPs for
CIHM::Meta::Press2

=head1 SYNOPSIS

    CIHM::Meta::Press2::Process->new($args);
      where $args is a hash of arguments.

=cut

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::Press2::Process->new() not a hash\n";
    }
    $self->{args} = $args;

    if ( !$self->log ) {
        die "Log::Log4perl object parameter is mandatory\n";
    }
    if ( !$self->internalmeta2 ) {
        die "internalmeta2 object parameter is mandatory\n";
    }
    if ( !$self->extrameta ) {
        die "extrameta object parameter is mandatory\n";
    }
    if ( !$self->cosearch2 ) {
        die "cosearch2 object parameter is mandatory\n";
    }
    if ( !$self->copresentation2 ) {
        die "copresentation2 object parameter is mandatory\n";
    }
    if ( !$self->aip ) {
        die "Parameter 'aip' is mandatory\n";
    }
    $self->{searchdoc}  = {};
    $self->{presentdoc} = {};

    # Grab the data for the CouchDB document
    $self->{aipdata} = $self->get_internalmeta_doc( $self->aip );

    if ( !$self->aipdata ) {
        die "Unable to get internalmeta2 data for " . $self->aip . "\n";
    }

    if ( !$self->noid ) {
        die "NOID not set in internalmeta2 document for " . $self->aip . "\n";
    }

    # Flag for update status (false means problem with update)
    $self->{ustatus} = 1;

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

sub config {
    my $self = shift;
    return $self->args->{config};
}

sub log {
    my $self = shift;
    return $self->args->{log};
}

sub internalmeta2 {
    my $self = shift;
    return $self->args->{internalmeta2};
}

sub extrameta {
    my $self = shift;
    return $self->args->{extrameta};
}

sub cosearch2 {
    my $self = shift;
    return $self->args->{cosearch2};
}

sub copresentation2 {
    my $self = shift;
    return $self->args->{copresentation2};
}

sub searchdoc {
    my $self = shift;
    return $self->{searchdoc};
}

sub presentdoc {
    my $self = shift;
    return $self->{presentdoc};
}

sub aipdata {
    my $self = shift;
    return $self->{aipdata};
}

sub noid {
    my $self = shift;
    return if ( !defined $self->aipdata->{noid} );
    return $self->aipdata->{noid};
}

# Exposes here the login in pressq, for easier understanding.
sub pressme {
    my $self = shift;

    # Must have a hammer.json attachment
    return JSON::false
      if ( !defined( $self->aipdata->{attachInfo} )
        || ( !defined $self->aipdata->{attachInfo}->{'hammer.json'} ) );

    # Must be approved
    return JSON::false
      if ( !defined( $self->aipdata->{approved} )
        || ( defined $self->aipdata->{unapproved} ) );

    return JSON::true;
}

sub process {
    my ($self) = @_;

    $self->log->info( "Processing " . $self->aip . " (" . $self->noid . ")\n" );

    if ( $self->pressme ) {
        $self->adddocument();
    }
    else {
        $self->deletedocument();
    }
}

sub deletedocument {
    my ($self) = @_;

    $self->update_couch( $self->cosearch2 );
    $self->update_couch( $self->copresentation2 );
}

sub adddocument {
    my ($self) = @_;

    # Grab the data for the CouchDB document
    my $aipdata = $self->aipdata;

    my $extradata = {};

    # Get the Extrameta data, if it exists..
    $self->extrameta->type("application/json");
    my $res = $self->extrameta->get( "/" . $self->aip,
        {}, { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        $extradata = $res->data;
    }

    # Every AIP in the queue must have an attachment from Hammer.
    # (Test is part of the queue map)
    $self->process_hammer();

    # Map also counts for a minimum of repos, so adding in current array
    # to presentation.
    $self->presentdoc->{ $self->aip }->{'repos'} = $aipdata->{'repos'}
      if defined $aipdata->{'repos'};

    # All Items should have a date
    $self->presentdoc->{ $self->aip }->{'updated'} =
      DateTime->now()->iso8601() . 'Z';

    # If collections field exists, set accordingly within the item
    # Note: Not stored within pages, so no need to loop through all keys
    if ( exists $aipdata->{'collections'} ) {

        # The 's' is not used in the schemas, so not using here.
        $self->presentdoc->{ $self->aip }->{'collection'} =
          $aipdata->{'collections'};
        $self->searchdoc->{ $self->aip }->{'collection'} =
          $aipdata->{'collections'};
    }

   # If a parl.json attachment exists, process it. (parl-terms.json is obsolete)
    if ( exists $extradata->{'_attachments'}->{'parl.json'} ) {
        $self->process_parl();
    }

    # Determine if series or issue/monograph
    if ( $aipdata->{'sub-type'} eq 'series' ) {

        # Process series

        if ( exists $aipdata->{'parent'} ) {
            die $self->aip . " is a series and has parent field\n";
        }
        if ( scalar( keys %{ $self->presentdoc } ) != 1 ) {
            die $self->aip
              . " is a series and has "
              . scalar( keys %{ $self->presentdoc } )
              . " records\n";
        }
        if ( $self->presentdoc->{ $self->aip }->{'type'} ne 'series' ) {
            die $self->aip . " is a series, but record type not series\n";
        }
        $self->process_series();
    }
    else {
        # Process issue or monograph

        # If 'parent' field exists, process as issue of series
        if ( exists $aipdata->{'parent'} ) {
            $self->process_issue( $aipdata->{'parent'} );
        }

        # For the 'collection' field to be complete, processing components
        # needs to happen after process_issue().
        $self->process_components();
    }

    # If an externalmetaHP.json attachment exists, process it.
    # - Needs to be processed after process_components() as
    #   process_externalmetaHP() sets a flag within component field.
    if ( exists $extradata->{'_attachments'}->{'externalmetaHP.json'} ) {
        $self->process_externalmetaHP();
    }

    if (
        scalar( keys %{ $self->searchdoc } ) !=
        scalar( keys %{ $self->presentdoc } ) )
    {
        warn $self->aip . " had "
          . scalar( keys %{ $self->searchdoc } )
          . " searchdoc and "
          . scalar( keys %{ $self->presentdoc } )
          . " presentdoc\n";
        print $self->aip . " had doc count discrepancy\n";
    }

    $self->update_couch( $self->cosearch2,       $self->searchdoc );
    $self->update_couch( $self->copresentation2, $self->presentdoc );

    if ( $self->{ustatus} == 0 ) {
        die "One or more updates were not successful\n";
    }
}

# TODO: https://github.com/crkn-rcdr/Access-Platform/issues/400
# To delete any extra documents that don't match the current IDs (number of pages decreased, slug changed)
# Use views to create hash of docs based on : IDs of docs, noid view , manifest_noid view
# Use hash to update _rev of any doc that will be saved (delete key from hash), and then mark to be deleted every document still in hash.
# Use this also as delete_couch() , where docs=[];
sub update_couch {
    my ( $self, $dbo, $docs ) = @_;

    # Same function can be used to simply delete all the old docs
    if ( !$docs ) {
        $docs = {};
    }

    $dbo->type("application/json");

    my %couchdocs;

    # Looking up the ID to get revision of any existing document.
    my $url = "/_all_docs";
    my $res = $dbo->post(
        $url,
        { keys         => [ $self->aip ] },
        { deserializer => 'application/json' }
    );
    if ( $res->code == 200 ) {
        foreach my $row ( @{ $res->data->{rows} } ) {
            if (   defined $row->{id}
                && defined $row->{value}
                && defined $row->{value}->{rev}
                && !defined $row->{value}->{deleted} )
            {
                $couchdocs{ $row->{id} } = $row->{value}->{rev};
            }
        }
    }
    else {
        if ( defined $res->response->content ) {
            warn $res->response->content . "\n";
        }
        die "update_couch $url return code: " . $res->code . "\n";
    }

    # Looking up the noid
    $url = "/_design/access/_view/noid";
    my $res = $dbo->post(
        $url,
        { keys         => [ $self->noid ], include_docs => JSON::true },
        { deserializer => 'application/json' }
    );
    if ( $res->code == 200 ) {
        foreach my $row ( @{ $res->data->{rows} } ) {
            if (   defined $row->{id}
                && defined $row->{doc}
                && defined $row->{doc}->{'_rev'} )
            {
                $couchdocs{ $row->{id} } = $row->{doc}->{'_rev'};
            }
        }
    }
    else {
        if ( defined $res->response->content ) {
            warn $res->response->content . "\n";
        }
        die "update_couch $url return code: " . $res->code . "\n";
    }

    # Looking up the manifest_noid
    $url = "/_design/access/_view/manifest_noid";
    my $res = $dbo->post(
        $url,
        { keys         => [ $self->noid ], include_docs => JSON::true },
        { deserializer => 'application/json' }
    );
    if ( $res->code == 200 ) {
        foreach my $row ( @{ $res->data->{rows} } ) {
            if (   defined $row->{id}
                && defined $row->{doc}
                && defined $row->{doc}->{'_rev'} )
            {
                $couchdocs{ $row->{id} } = $row->{doc}->{'_rev'};
            }
        }
    }
    else {
        if ( defined $res->response->content ) {
            warn $res->response->content . "\n";
        }
        die "update_couch $url return code: " . $res->code . "\n";
    }

    # Check if we have missed any
    my @doclookup;
    foreach my $key ( keys %{$docs} ) {
        if ( !defined $couchdocs{$key} ) {
            push @doclookup, $key;
        }
    }

    if (@doclookup) {

        # Looking up the slugs of the components
        $url = "/_all_docs";
        $res = $dbo->post(
            $url,
            { keys         => \@doclookup },
            { deserializer => 'application/json' }
        );
        if ( $res->code == 200 ) {
            foreach my $row ( @{ $res->data->{rows} } ) {
                if (   defined $row->{id}
                    && defined $row->{value}
                    && defined $row->{value}->{rev}
                    && !defined $row->{value}->{deleted} )
                {
                    $couchdocs{ $row->{id} } = $row->{value}->{rev};
                }
            }
        }
        else {
            if ( defined $res->response->content ) {
                warn $res->response->content . "\n";
            }
            die "update_couch $url return code: " . $res->code . "\n";
        }
    }

    # Initialize structure to be used for bulk update
    my $postdoc = { docs => [] };

    # Updated or created docs
    foreach my $docid ( keys %{$docs} ) {
        if ( defined $couchdocs{$docid} ) {
            $docs->{$docid}->{"_rev"} =
              $couchdocs{$docid};
            delete $couchdocs{$docid};
        }
        $docs->{$docid}->{"_id"} = $docid;
        push @{ $postdoc->{docs} }, $docs->{$docid};
    }

    # Delete the rest
    foreach my $docid ( keys %couchdocs ) {
        push @{ $postdoc->{docs} },
          {
            '_id'      => $docid,
            '_rev'     => $couchdocs{$docid},
            "_deleted" => JSON::true
          };
    }

    $url = "/_bulk_docs";
    $res = $dbo->post( $url, $postdoc, { deserializer => 'application/json' } );

    if ( $res->code == 201 ) {
        my @data = @{ $res->data };
        if ( exists $data[0]->{id} ) {
            foreach my $thisdoc (@data) {

                # Check if any ID's failed
                if ( !$thisdoc->{ok} ) {
                    warn $thisdoc->{id}
                      . " was not indicated OK update_couch ("
                      . $dbo->server . ") "
                      . encode_json($thisdoc) . " \n";
                    $self->{ustatus} = 0;
                }
            }
        }
    }
    else {
        if ( defined $res->response->content ) {
            warn $res->response->content . "\n";
        }
        die "update_couch $url return code: " . $res->code . "\n";
    }
}

sub process_hammer {
    my ($self) = @_;

    # Grab the data from the attachment (will be hammer.json soon)
    my $hammerdata = $self->get_internalmeta_doc( $self->aip . "/hammer.json" );

    # Hammer data is an ordered array with element [0] being item, and other
    # elements being components

    # First loop to generate the item 'tx' field if it doesn't already exist
    if ( !exists $hammerdata->[0]->{'tx'} ) {
        my @tx;
        for my $i ( 1 .. $#$hammerdata ) {
            my $doc = $hammerdata->[$i];
            if ( exists $doc->{'tx'} ) {
                foreach my $t ( @{ $doc->{'tx'} } ) {
                    push @tx, $t;
                }
            }
        }
        if (@tx) {
            $hammerdata->[0]->{'tx'} = \@tx;
        }

        # If there is now an item 'tx' field, handle its count
        if ( exists $hammerdata->[0]->{'tx'} ) {
            my $count = scalar( @{ $hammerdata->[0]->{'tx'} } );
            if ($count) {
                $hammerdata->[0]->{'component_count_fulltext'} = $count;
            }
        }

    }

    # These fields copied from item into each component.
    my $pubmin = $hammerdata->[0]->{'pubmin'};
    my $pubmax = $hammerdata->[0]->{'pubmax'};
    my $lang   = $hammerdata->[0]->{'lang'};

    # Loop through and copy into cosearch/copresentation
    for my $i ( 0 .. $#$hammerdata ) {
        my $doc = $hammerdata->[$i];
        my $key = $doc->{'key'}
          || die "Key missing from document in Hammer.json";

        # Copy fields into components
        if ($i) {
            if ($pubmin) {
                $doc->{'pubmin'} = $pubmin;
            }
            if ($pubmax) {
                $doc->{'pubmax'} = $pubmax;
            }
            if ($lang) {
                $doc->{'lang'} = $lang;
            }
        }

        # Hash of all fields that are set
        my %docfields = map { $_ => 1 } keys %{$doc};

        $self->searchdoc->{$key} = {};

        # Copy the fields for cosearch
        foreach my $cf (
            "key",                      "type",
            "depositor",                "label",
            "pkey",                     "seq",
            "pubmin",                   "pubmax",
            "lang",                     "identifier",
            "pg_label",                 "ti",
            "au",                       "pu",
            "su",                       "no",
            "ab",                       "tx",
            "no_rights",                "no_source",
            "component_count_fulltext", "component_count",
            "noid",                     "manifest_noid"
          )
        {
            $self->searchdoc->{$key}->{$cf} = $doc->{$cf} if exists $doc->{$cf};
            delete $docfields{$cf};
        }

        $self->presentdoc->{$key} = {};

        # Copy the fields for copresentation
        foreach my $cf (
            "key",                      "type",
            "label",                    "pkey",
            "seq",                      "lang",
            "media",                    "identifier",
            "canonicalUri",             "canonicalMaster",
            "canonicalMasterExtension", "canonicalMasterMime",
            "canonicalMasterSize",      "canonicalMasterMD5",
            "canonicalMasterWidth",     "canonicalMasterHeight",
            "canonicalDownload",        "canonicalDownloadExtension",
            "canonicalDownloadMime",    "canonicalDownloadSize",
            "canonicalDownloadMD5",     "ti",
            "au",                       "pu",
            "su",                       "no",
            "ab",                       "no_source",
            "no_rights",                "component_count_fulltext",
            "component_count",          "noid",
            "file",                     "ocrPdf",
            "manifest_noid"
          )
        {
            $self->presentdoc->{$key}->{$cf} = $doc->{$cf}
              if exists $doc->{$cf};
            delete $docfields{$cf};
        }

        if ( keys %docfields ) {
            warn "Unused Hammer fields in $key: "
              . join( ",", keys %docfields ) . "\n";
            print "Unused Hammer fields in $key: "
              . join( ",", keys %docfields ) . "\n";
        }
    }
}

sub process_parl {
    my ($self) = @_;

    $self->extrameta->type("application/json");
    my $res = $self->extrameta->get( "/" . $self->aip . "/parl.json",
        {}, { deserializer => 'application/json' } );
    if ( $res->code != 200 ) {
        die "get of parl.json return code: " . $res->code . "\n";
    }
    my $parl = $res->data;

    my %term_map = (
        language       => "lang",
        label          => "parlLabel",
        chamber        => "parlChamber",
        session        => "parlSession",
        type           => "parlType",
        node           => "parlNode",
        reportTitle    => "parlReportTitle",
        callNumber     => "parlCallNumber",
        primeMinisters => "parlPrimeMinisters",
        pubmin         => "pubmin",
        pubmax         => "pubmax"
    );

    my @search_terms =
      qw/language label chamber session type reportTitle callNumber primeMinisters pubmin pubmax/;
    foreach my $st (@search_terms) {
        $self->searchdoc->{ $self->aip }->{ $term_map{$st} } = $parl->{$st}
          if exists $parl->{$st};
    }

    foreach my $pt ( keys %term_map ) {
        $self->presentdoc->{ $self->aip }->{ $term_map{$pt} } = $parl->{$pt}
          if exists $parl->{$pt};
    }
}

# Merging multi-value fields
sub mergemulti {
    my ( $doc, $field, $value ) = @_;

    if ( !defined $doc->{$field} ) {
        $doc->{$field} = $value;
    }
    else {
        # Ensure values being pushed are unique.
        foreach my $mval ( @{$value} ) {
            my $found = 0;
            foreach my $tval ( @{ $doc->{$field} } ) {
                if ( $mval eq $tval ) {
                    $found = 1;
                    last;
                }
            }
            if ( !$found ) {
                push @{ $doc->{$field} }, $mval;
            }
        }
    }
}

sub process_externalmetaHP {
    my ($self) = @_;

    # Grab the data for the CouchDB document

    $self->extrameta->type("application/json");
    my $res = $self->extrameta->get( "/" . $self->aip . "/externalmetaHP.json",
        {}, { deserializer => 'application/json' } );
    if ( $res->code != 200 ) {
        die "get of externalmetaHP.json eturn code: " . $res->code . "\n";
    }
    my $emHP = $res->data;

    foreach my $seq ( keys %{$emHP} ) {
        my $pageid = $self->aip . "." . $seq;
        my $tags   = $emHP->{$seq};
        if ( defined $self->searchdoc->{$pageid} ) {
            my %tagfields = map { $_ => 1 } keys %{$tags};

            # Copy the fields for cosearch && copresentation
            # In parent as well..
            foreach my $cf (
                "tag",     "tagPerson",
                "tagName", "tagPlace",
                "tagDate", "tagNotebook",
                "tagDescription"
              )
            {
                if ( exists $tags->{$cf} ) {
                    if ( ref( $tags->{$cf} ne "ARRAY" ) ) {
                        die
                          "externalmetaHP tag $cf for page $pageid not array\n";
                    }

                    mergemulti( $self->searchdoc->{$pageid}, $cf,
                        $tags->{$cf} );
                    mergemulti( $self->presentdoc->{$pageid},
                        $cf, $tags->{$cf} );
                    mergemulti( $self->searchdoc->{ $self->aip },
                        $cf, $tags->{$cf} );
                    mergemulti( $self->presentdoc->{ $self->aip },
                        $cf, $tags->{$cf} );
                }
                delete $tagfields{$cf};
            }

            # Set flag in item to indicate this component has tags
            $self->presentdoc->{ $self->aip }->{'components'}->{$pageid}
              ->{'hasTags'} = JSON::true;

            # Set flag in item to indicate some component has tags
            $self->presentdoc->{ $self->aip }->{'hasTags'} = JSON::true;

            if ( keys %tagfields ) {
                warn "Unused externalmetaHP fields in $pageid: "
                  . join( ",", keys %tagfields ) . "\n";
            }
        }
        else {
            warn "externalmetaHP sequence $seq doesn't exist in "
              . $self->aip . "\n";
        }
    }
}

sub process_issue {
    my ( $self, $parent ) = @_;

    # Force parent to be processed (likely again) later, and grab label
    my $res = $self->internalmeta2->post( "/_design/tdr/_update/parent/$parent",
        {}, { deserializer => 'application/json' } );
    if ( $res->code != 201 && $res->code != 200 ) {
        die "_update/parent/$parent POST return code: " . $res->code . "\n";
    }
    if ( $res->data->{return} ne 'updated' ) {
        die "_update/parent/$parent POST function returned: "
          . $res->data->{return} . "\n";
    }
    $self->presentdoc->{ $self->aip }->{'plabel'} = $res->data->{label};
    $self->searchdoc->{ $self->aip }->{'plabel'}  = $res->data->{label};

    # Merge collection information
    if ( exists $res->data->{collection} ) {
        my %collections;
        foreach my $a ( @{ $res->data->{'collection'} } ) {
            $collections{$a} = 1;
        }
        foreach my $a ( @{ $self->presentdoc->{ $self->aip }->{'collection'} } )
        {
            $collections{$a} = 1;
        }

        my @collections = sort keys %collections;

        $self->presentdoc->{ $self->aip }->{'collection'} = \@collections;

        $self->searchdoc->{ $self->aip }->{'collection'} =
          $self->presentdoc->{ $self->aip }->{'collection'};
    }
}

sub process_series {
    my ($self) = @_;

    my @order;
    my $items = {};

    # Look up issues for this series
    $self->internalmeta2->type("application/json");
    my $res = $self->internalmeta2->get(
        "/_design/tdr/_view/issues?reduce=false&startkey=[\""
          . $self->aip
          . "\"]&endkey=[\""
          . $self->aip
          . "\",{}]",
        {},
        { deserializer => 'application/json' }
    );
    if ( $res->code != 200 ) {
        die "_view/issues for "
          . $self->aip
          . " return code: "
          . $res->code . "\n";
    }
    foreach my $issue ( @{ $res->data->{rows} } ) {

        # Only add issues which have been approved
        if ( $issue->{value}->{approved} ) {
            delete $issue->{value}->{approved};
            push( @order, $issue->{id} );

            # All the other values from the map are currently used
            # for the items field
            $items->{ $issue->{id} } = $issue->{value};
        }
    }
    $self->presentdoc->{ $self->aip }->{'order'}     = \@order;
    $self->presentdoc->{ $self->aip }->{'items'}     = $items;
    $self->searchdoc->{ $self->aip }->{'item_count'} = scalar(@order);
}

=head1 $self->process_components()

Process component AIPs to build the 'components' and 'order' fields.
Currently order is numeric order by sequence, but later may be built
into metadata.xml

=cut

sub process_components {
    my ($self) = @_;

    my $components = {};
    my %seq;
    my @order;

    foreach my $thisdoc ( keys %{ $self->presentdoc } ) {
        next if ( $self->presentdoc->{$thisdoc}->{'type'} ne 'page' );
        $seq{ $self->presentdoc->{$thisdoc}->{'seq'} + 0 } =
          $self->presentdoc->{$thisdoc}->{'key'};
        $components->{ $self->presentdoc->{$thisdoc}->{'key'} }->{'label'} =
          $self->presentdoc->{$thisdoc}->{'label'};
        if ( exists $self->presentdoc->{$thisdoc}->{'canonicalMaster'} ) {
            $components->{ $self->presentdoc->{$thisdoc}->{'key'} }
              ->{'canonicalMaster'} =
              $self->presentdoc->{$thisdoc}->{'canonicalMaster'};
        }
        if (
            exists $self->presentdoc->{$thisdoc}->{'canonicalMasterExtension'} )
        {
            $components->{ $self->presentdoc->{$thisdoc}->{'key'} }
              ->{'canonicalMasterExtension'} =
              $self->presentdoc->{$thisdoc}->{'canonicalMasterExtension'};
        }
        if ( exists $self->presentdoc->{$thisdoc}->{'noid'} ) {
            $components->{ $self->presentdoc->{$thisdoc}->{'key'} }->{'noid'} =
              $self->presentdoc->{$thisdoc}->{'noid'};
        }
        if ( exists $self->presentdoc->{$thisdoc}->{'canonicalMasterWidth'} ) {
            $components->{ $self->presentdoc->{$thisdoc}->{'key'} }
              ->{'canonicalMasterWidth'} =
              $self->presentdoc->{$thisdoc}->{'canonicalMasterWidth'};
        }
        if ( exists $self->presentdoc->{$thisdoc}->{'canonicalMasterHeight'} ) {
            $components->{ $self->presentdoc->{$thisdoc}->{'key'} }
              ->{'canonicalMasterHeight'} =
              $self->presentdoc->{$thisdoc}->{'canonicalMasterHeight'};
        }
        if ( exists $self->presentdoc->{$thisdoc}->{'canonicalDownload'} ) {
            $components->{ $self->presentdoc->{$thisdoc}->{'key'} }
              ->{'canonicalDownload'} =
              $self->presentdoc->{$thisdoc}->{'canonicalDownload'};
        }
        if (
            exists $self->presentdoc->{$thisdoc}->{'canonicalDownloadExtension'}
          )
        {
            $components->{ $self->presentdoc->{$thisdoc}->{'key'} }
              ->{'canonicalDownloadExtension'} =
              $self->presentdoc->{$thisdoc}->{'canonicalDownloadExtension'};
        }
        if ( defined $self->presentdoc->{ $self->aip }->{'collection'} ) {
            $self->presentdoc->{$thisdoc}->{'collection'} =
              $self->presentdoc->{ $self->aip }->{'collection'};
            $self->searchdoc->{$thisdoc}->{'collection'} =
              $self->presentdoc->{ $self->aip }->{'collection'};
        }
    }
    foreach my $page ( sort { $a <=> $b } keys %seq ) {
        push @order, $seq{$page};
    }

    # A born digital PDF has no pages, but is still a document.
    if (@order) {
        $self->{presentdoc}->{ $self->aip }->{'order'}      = \@order;
        $self->{presentdoc}->{ $self->aip }->{'components'} = $components;
        $self->{searchdoc}->{ $self->aip }->{'component_count'} =
          scalar(@order);
    }
}

sub get_internalmeta_doc {
    my ( $self, $docid ) = @_;

    $self->internalmeta2->type("application/json");
    my $url = "/$docid";
    my $res = $self->internalmeta2->get( $url, {},
        { deserializer => 'application/json' } );
    if ( $res->code == 200 ) {
        return $res->data;
    }
    else {
        warn "get_internalmenta_doc ($url) return code: " . $res->code . "\n";
        return;
    }
}

1;
