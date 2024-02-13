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
use JSON;

my $flatten = CIHM::Normalise::flatten->new;
my $dirname = dirname(__FILE__);

my $xmlfile = read_file("$dirname/oocihm.8_00002_1-DC.xml");
my $flat = $flatten->byType( "dc", $xmlfile );

my $cmr = decode_json read_file("$dirname/oocihm.8_00002_1-CMR.json");

is_deeply $flat, $cmr, 'Check entire CMR for differences';

done_testing();    # reached the end safely
