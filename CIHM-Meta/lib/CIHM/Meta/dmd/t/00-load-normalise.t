#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'CIHM::Meta::dmd::Normalise' ) || print "Bail out!\n";
}

diag( "Testing CIHM::Meta::dmd::Normalise $CIHM::Meta::dmd::Normalise::VERSION, Perl $], $^X" );
