package CIHM::Meta::dmd::flatten;

use strict;
use Switch;
use XML::LibXML;
use CIHM::Normalise;
use Data::Dumper;
use MARC::File::XML ( BinaryEncoding => 'utf8', RecordFormat => 'USMARC' );
use List::MoreUtils qw(uniq);


use Exporter qw(import);
our @EXPORT = qw(
  normaliseSpace
);


sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    return $self;
}

sub byType {
    my ( $self, $type, $xmlin ) = @_;

    switch ( lc($type) ) {
        case "issueinfo" { return $self->issueinfo($xmlin) }
        case "marc"      { return $self->marc($xmlin) }
        case "dc"        { return $self->dc($xmlin) }
        else             { die "Unknown DMD type: $type\n" }
    }

}

sub issueinfo {
    my ( $self, $xmlin ) = @_;

    my %flat;
    my $xml = XML::LibXML->new->parse_string($xmlin);
    my $xpc = XML::LibXML::XPathContext->new;
    $xpc->registerNs( 'issueinfo',
        "http://canadiana.ca/schema/2012/xsd/issueinfo" );

    my @nodes = $xpc->findnodes( "//*", $xml );
    foreach my $node (@nodes) {
        my $content = normaliseSpace( $node->textContent );

        if ( length($content) ) {
            switch ( lc( $node->nodeName ) ) {
                case "issueinfo" {    #  Skip top level
                }
                case "published" {
                    my $pubmin;
                    my $pubmax;
                    switch ( length($content) ) {
                        case 4 {
                            $pubmin = $content . "-01-01";
                            $pubmax = $content . "-12-31";
                        }
                        case 7 {
                            $pubmin = $content . "-01";
                            switch ( int( substr $content, 5 ) ) {
                                case [2] {
                                    $pubmax = $content . "-28";
                                }
                                case [ 1, 3, 5, 7, 8, 10, 12 ] {
                                    $pubmax = $content . "-31";
                                }
                                case [ 4, 6, 9, 11 ] {
                                    $pubmax = $content . "-30";
                                }
                            }
                        }
                        case 10 {
                            $pubmin = $content;
                            $pubmax = $content;
                        }
                    }
                    if ($pubmin) {
                        $pubmin = iso8601( $pubmin, 0 )
                          unless ( $pubmin =~
                            /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/ );
                    }
                    if ($pubmax) {
                        $pubmax = iso8601( $pubmax, 1 )
                          unless ( $pubmax =~
                            /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/ );
                    }
                    if ( $pubmin && $pubmin !~ /^0000/ ) {
                        $flat{'pubmin'} = $pubmin;
                    }
                    if ( $pubmax && $pubmax !~ /^0000/ ) {
                        $flat{'pubmax'} = $pubmax;
                    }
                }
                case "series" {
                    $flat{'pkey'} = $content;
                }
                case "sequence" {
                    $flat{'seq'} = $content
                }
                case "title" {
                    $content =~ s/-+$//g;     # Trim dashes
                    $content =~ s/\/+$//g;    # Trim odd slashes
                    $content =~
                      s/^\s+|\s+$//g;  # Trim space at end and beginning in case

                    if ( !exists $flat{'ti'} ) {
                        $flat{'ti'} = [];
                    }
                    push @{ $flat{'ti'} }, $content;
                }
                case "language" {
                    my @lang = normalise_lang($content);
                    if (@lang) {
                        if ( !exists $flat{'lang'} ) {
                            $flat{'lang'} = [];
                        }
                        push @{ $flat{'lang'} }, @lang;
                    }
                }
                case "note" {
                    if ( !exists $flat{'no'} ) {
                        $flat{'no'} = [];
                    }
                    push @{ $flat{'no'} }, $content;
                }
                case "source" {
                    if ( !exists $flat{'no_source'} ) {
                        $flat{'no_source'} = [];
                    }
                    push @{ $flat{'no_source'} }, $content;
                }
                case "pubstatement" {
                    if ( !exists $flat{'pu'} ) {
                        $flat{'pu'} = [];
                    }
                    push @{ $flat{'pu'} }, $content;
                }
                case "identifier" {
                    if ( !exists $flat{'identifier'} ) {
                        $flat{'identifier'} = [];
                    }
                    push @{ $flat{'identifier'} }, $content;
                }
                case "coverage" {

                    # TODO: We aren't using Coverage?
                }
                else {
                    warn "Unknown issueinfo node name: "
                      . $node->nodeName . "\n";
                }
            }
        }
    }

    return \%flat;
}

sub addArray {
    my ( $flat, $field, $data ) = @_;

    if ( $field eq 'ti' ) {
        $data =~ s/[\s\/\-]+$//g;
    }

    # Ignore blank lines.
    return if ( !length($data) );

    if ( !exists $flat->{$field} ) {
        $flat->{$field} = [];
    }
    push @{ $flat->{$field} }, normaliseSpace($data);
}

sub marc {
    my ( $self, $xmlin ) = @_;

    my %flat;

    my $record = MARC::Record->new_from_xml($xmlin);

    if ( $record->subfield( '260', 'c' ) ) {
        $flat{'pubmin'} = iso8601( $record->subfield( '260', 'c' ), 0 );
        $flat{'pubmax'} = iso8601( $record->subfield( '260', 'c' ), 1 );
    }

    foreach my $field ( $record->field('008') ) {
        my @lang = normalise_lang( substr( $field->as_string, 35, 3 ) );
        if (@lang) {
            if ( !exists $flat{'lang'} ) {
                $flat{'lang'} = [];
            }
            push @{ $flat{'lang'} }, @lang;
        }

    }
    foreach my $field ( $record->field('041') ) {
        my $ls = $field->as_string;
        my @lang;
        while ( length($ls) >= 3 ) {
            push @lang, normalise_lang( substr( $ls, 0, 3 ) );
            $ls = substr( $ls, 3 );
            $ls =~ s/^\s+//g;
        }
        if (@lang) {
            if ( !exists $flat{'lang'} ) {
                $flat{'lang'} = [];
            }
            push @{ $flat{'lang'} }, @lang;
        }
    }
    if ( exists $flat{'lang'} ) {
        @{ $flat{'lang'} } = uniq( @{ $flat{'lang'} } );
    }

    foreach my $field ( $record->field('090') ) {
        if ( $field->subfield('a') ) {
            addArray( \%flat, 'identifier', $field->subfield('a') );
        }
    }

    foreach my $publishfield ( $record->field('260') ) {
        addArray( \%flat, 'pu', $publishfield->as_string() );
    }

    foreach my $notefield ( $record->field('500') ) {
        addArray( \%flat, 'no', $notefield->as_string() );
    }
    my @notes;
    push @notes, $record->field('250');
    push @notes, $record->field('300');
    push @notes, $record->field('362');
    push @notes, $record->field('504');
    push @notes, $record->field('505');
    push @notes, $record->field('510');
    push @notes, $record->field('515');
    push @notes, $record->field('520');
    push @notes, $record->field('534');
    push @notes, $record->field('540');
    push @notes, $record->field('546');
    push @notes, $record->field('580');
    push @notes, $record->field('787');
    push @notes, $record->field('800');

    # TODO: Bug in old XSL missed this: push @notes, $record->field('810');
    push @notes, $record->field('811');
    foreach my $notesfield (@notes) {
        addArray( \%flat, 'no', normaliseSpace( $notesfield->as_string() ) );
    }

    foreach my $source ( $record->field('533') ) {
        my $ss = normaliseSpace( $source->subfield('a') );
        if ( length($ss) ) {
            addArray( \%flat, 'no_source', $ss );
        }
    }

    my @subjects;
    push @subjects, $record->field('600');
    push @subjects, $record->field('610');
    push @subjects, $record->field('630');
    push @subjects, $record->field('650');
    push @subjects, $record->field('651');
    foreach my $subjectfield (@subjects) {
        my $string;

        my @subfields = $subjectfield->subfields();

        foreach my $subfield (@subfields) {
            switch ( @{$subfield}[0] ) {
                case 'b' {
                    $string .= ' ';
                }
                case [ 'v', 'x', 'y', 'z' ] {
                    $string .= ' -- ';
                }
            }
            $string .= normaliseSpace( @{$subfield}[1] );
        }
        addArray( \%flat, 'su', $string );
    }

    my @authors;
    push @authors, $record->field('100');
    push @authors, $record->field('700');
    push @authors, $record->field('710');
    push @authors, $record->field('711');
    foreach my $authorfield (@authors) {
        addArray( \%flat, 'au', normaliseSpace( $authorfield->as_string() ) );
    }

    my @titles;
    push @titles, $record->field('110');
    push @titles, $record->field('111');
    push @titles, $record->field('130');
    push @titles, $record->field('246');
    push @titles, $record->field('440');
    push @titles, $record->field('730');
    push @titles, $record->field('740');
    push @titles, $record->field('830');
    push @titles, $record->field('840');
    foreach my $titlefield (@titles) {
        addArray( \%flat, 'ti', normaliseSpace( $titlefield->as_string() ) );
    }

    foreach my $titlefield ( $record->field('245') ) {
        my $string = $titlefield->subfield('a') . ' ';
        if ( $titlefield->subfield('h') =~ /\](.*)$/ ) {
            $string .= $1 . ' ';
        }
        $string .= $titlefield->subfield('b');
        addArray( \%flat, 'ti', $string );
    }

    return \%flat;
}

sub dc {
    my ( $self, $xmlin ) = @_;

    my %flat;
    my @dates;

    # Add Namespace if missing
    $xmlin =~
      s|<simpledc>|<simpledc xmlns:dc="http://purl.org/dc/elements/1.1/">|g;

    my $xml = XML::LibXML->new->parse_string($xmlin);
    my $xpc = XML::LibXML::XPathContext->new;
    $xpc->registerNs( 'dc', 'http://purl.org/dc/elements/1.1/' );

    my @nodes = $xpc->findnodes( "//*", $xml );
    foreach my $node (@nodes) {
        my $content = normaliseSpace( $node->textContent );

        if ( length($content) ) {
            my $nodename = lc( $node->nodeName );
            $nodename =~ s|dc:||g;    # Strip namespace if it exists

            switch ($nodename) {
                case "simpledc" {     #  Skip top level
                }
                case "date" {
                    push @dates, $content;
                }

                case "language" {
                    my @lang = normalise_lang($content);
                    if (@lang) {
                        if ( !exists $flat{'lang'} ) {
                            $flat{'lang'} = [];
                        }
                        push @{ $flat{'lang'} }, @lang;
                    }
                }
                case "creator" {
                    if ( !exists $flat{'au'} ) {
                        $flat{'au'} = [];
                    }
                    push @{ $flat{'au'} }, $content;
                }
                case "description" {
                    if ( !exists $flat{'ab'} ) {
                        $flat{'ab'} = [];
                    }
                    push @{ $flat{'ab'} }, $content;
                }
                case "identifier" {
                    if ( !exists $flat{'identifier'} ) {
                        $flat{'identifier'} = [];
                    }
                    push @{ $flat{'identifier'} }, $content;
                }
                case "publisher" {
                    if ( !exists $flat{'pu'} ) {
                        $flat{'pu'} = [];
                    }
                    push @{ $flat{'pu'} }, $content;
                }
                case ["relation","coverage","rights"] {
                    if ( !exists $flat{'no'} ) {
                        $flat{'no'} = [];
                    }
                    push @{ $flat{'no'} }, $content;
                }
                case [ "source", "contributor" ] {
                    if ( !exists $flat{'no_source'} ) {
                        $flat{'no_source'} = [];
                    }
                    push @{ $flat{'no_source'} }, $content;
                }
                case "subject" {
                    if ( !exists $flat{'su'} ) {
                        $flat{'su'} = [];
                    }
                    push @{ $flat{'su'} }, $content;
                }
                case "title" {

#                    $content =~ s/\-\-$//g;     # Trim double
#                    $content =~ s/\/+$//g;    # Trim odd slashes
#                    $content =~
#                      s/^\s+|\s+$//g;  # Trim space at end and beginning in case

                    if ( !exists $flat{'ti'} ) {
                        $flat{'ti'} = [];
                    }
                    push @{ $flat{'ti'} }, $content;
                }
                case "type" {
                    if ( !exists $flat{'no'} ) {
                        $flat{'no'} = [];
                    }
                    push @{ $flat{'no'} }, $content;
                }
                case "format" {    #Not used?
                }
                else {
                    warn "Unknown Dublin Core node name: "
                      . $node->nodeName . "\n";
                }
            }
        }
    }

  # TODO: This is what we have been doing, but should be doing something better.
    if (@dates) {
        if ( int(@dates) == 1 ) {
            $flat{'pubmin'} = iso8601( $dates[0], 0 );
            $flat{'pubmax'} = iso8601( $dates[0], 1 );
        }
        else {
            $flat{'pubmin'} = iso8601( $dates[0], 0 );
            $flat{'pubmax'} = iso8601( $dates[1], 1 );
        }

        # Currently if either date was unreable, it was left blank.
        if ( !( $flat{'pubmin'} ) || !( $flat{'pubmax'} ) ) {
            delete $flat{'pubmin'};
            delete $flat{'pubmax'};
        }
    }

    return \%flat;
}

sub normaliseSpace {
    my $content = shift;

    $content =~ s/^\s+|\s+$//g;    # Trim space at end and beginning.
    $content =~ s/\s+/ /g;         # Remove extra spaces

    return $content;
}

1;
