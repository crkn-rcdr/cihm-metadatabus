#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

use CIHM::Normalise;

# Test minimum and maximum templates, supplying only year.
is (iso8601("1999",0),   "1999-01-01T00:00:00.000Z", ' minimum template' );
is (iso8601("1999",1),   "1999-12-31T23:59:59.999Z", ' maximum template' );

# Test minimum and maximum templates, supplying year with question mark.
is (iso8601("c1891?",0),   "1891-01-01T00:00:00.000Z", ' Question copyright minimum template' );
is (iso8601("c1891?",1),   "1891-12-31T23:59:59.999Z", ' Question copyright maximum template' );


done_testing();   # reached the end safely
