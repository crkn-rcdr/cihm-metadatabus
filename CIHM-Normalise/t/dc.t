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

my $xmlfile = read_file("$dirname/oocihm.8_00002_1-DC.xml");

my $flat = $flatten->byType("dc",$xmlfile);
#diag explain $flat;

# Test minimum and maximum date for this file
is ($flat->{pubmax},   "1873-12-31T23:59:59.999Z", ' pubmax' );
is ($flat->{pubmin},   "1873-01-01T00:00:00.000Z", ' pubmin' );

done_testing();   # reached the end safely
