use 5.006;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'CIHM::Meta',
    AUTHOR           => q{Russell McOrmond <russell.mcormond@canadiana.ca>},
    VERSION_FROM     => 'lib/CIHM/Meta.pm',
    ABSTRACT_FROM    => 'lib/CIHM/Meta.pm',
    LICENSE          => 'artistic_2',
    PL_FILES         => {},
    "EXE_FILES" => [
      "bin/dmdtask", "bin/hammer2",, "bin/importocr", "bin/ocrtask",
      "bin/presentation-diff", "bin/press2", "bin/smelter", "bin/solrstream", "bin/walk-canvas-orphan"
    ],
    MIN_PERL_VERSION => 5.006,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
        #'ABC'              => 1.6,
        #'Foo::Bar::Module' => 5.0401,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'CIHM-Meta-*' },
);
