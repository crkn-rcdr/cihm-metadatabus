#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'CIHM::Normalise::flatten' ) || print "Bail out!\n";
}
