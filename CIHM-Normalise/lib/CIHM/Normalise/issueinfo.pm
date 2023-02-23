package CIHM::Normalise::issueinfo;

use strict;
use Switch;
use XML::LibXML;
use Data::Dumper;
use CIHM::Normalise;

use Exporter qw(import);
our @EXPORT = qw(
  issueinfo
);


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

                    # No longer used by Metadatabus
                }
                case "sequence" {

                    # No longer used by Metadatabus
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

1;
