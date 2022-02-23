#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'CIHM::METS::parse' ) || print "Bail out!\n";
}

diag( "Testing CIHM::METS::parse $CIHM::METS::parse::VERSION, Perl $], $^X" );
