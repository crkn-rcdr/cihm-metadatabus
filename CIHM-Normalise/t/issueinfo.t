#!perl
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;
use CIHM::Normalise::flatten;
use CIHM::Normalise;
use Data::Dumper;
use File::Basename;
use File::Slurp;

my $flatten = CIHM::Normalise::flatten->new;
my $dirname = dirname(__FILE__);

my $xmlfile = read_file("$dirname/oocihm.lac_reel_t1649-issueinfo.xml");

my $flat = $flatten->byType( "issueinfo", $xmlfile );
# diag explain $flat;

# The order of the identifiers is interesting.
is_deeply $flat->{identifier}, [ 'T-1649', '133764', '194128', 'RG 11 A 1' ],
  'Identifiers';

done_testing();    # reached the end safely
