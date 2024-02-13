package CIHM::Normalise::marc;

use strict;
use Switch;
use XML::LibXML;
use Data::Dumper;
use MARC::File::XML ( BinaryEncoding => 'utf8', RecordFormat => 'USMARC' );
use List::MoreUtils qw(uniq);
use CIHM::Normalise;

use Exporter qw(import);
our @EXPORT = qw(
  marc
);


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

# We are going to look for 264 if nothing there then look in 260 field. 264 preferred source
    if ( defined $record->field('264') ) {
        addArray( \%flat, 'pu', $record->field('264')->as_string() );
        if ( defined $record->subfield( '264', 'c' ) ) {
            $flat{'pubmin'} = iso8601( $record->subfield( '264', 'c' ), 0 );
            $flat{'pubmax'} = iso8601( $record->subfield( '264', 'c' ), 1 );
        }
    }
    elsif ( defined $record->field('260') ) {
        addArray( \%flat, 'pu', $record->field('260')->as_string() );

        if ( defined $record->subfield( '260', 'c' ) ) {
            $flat{'pubmin'} = iso8601( $record->subfield( '260', 'c' ), 0 );
            $flat{'pubmax'} = iso8601( $record->subfield( '260', 'c' ), 1 );
        }
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

1;
