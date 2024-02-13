package CIHM::Normalise::dc;

use strict;
use Switch;
use XML::LibXML;
use Data::Dumper;
use CIHM::Normalise;

use Exporter qw(import);
our @EXPORT = qw(
  dc
);

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

  # Date ranges are supported according to
  # https://www.dublincore.org/specifications/dublin-core/dcmi-terms/terms/date/
                    my @newdates = split( '/', $content );
                    if ( scalar(@newdates) > 2 ) {
                        warn "<date> of $content has too many parts\n";
                    }
                    push @dates, @newdates;
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
                case [ "relation", "coverage", "rights" ] {
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

    # Temporarily we can support old ranges (in two separate <date> tags),
    # As well as a range separated by a '/'.
    # Once data is migrated, we can move to supporting ranges only.

    # Supplying '' as a date, what happens if start or end date is missing,
    # generates warning.
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

1;
