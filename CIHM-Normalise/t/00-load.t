#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'CIHM::Normalise' ) || print "Bail out!\n";
}

diag( "Testing CIHM::Normalise $CIHM::Normalise::VERSION, Perl $], $^X" );
