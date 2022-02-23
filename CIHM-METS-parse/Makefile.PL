use 5.006;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'CIHM::METS::parse',
    AUTHOR           => q{Russell McOrmond <russell.mcormond@canadiana.ca>},
    VERSION_FROM     => 'lib/CIHM/METS/parse.pm',
    ABSTRACT_FROM    => 'lib/CIHM/METS/parse.pm',
    LICENSE          => 'Artistic_2_0',
    PL_FILES         => {},
    "EXE_FILES" => [
      "bin/metsparse"
    ],
    MIN_PERL_VERSION => 5.006,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
	'Data::Dumper' => 0,
	'File::Basename' => 0,
        'File::Slurp' => 0,
 	'FindBin' => 0,
	'Switch' => 0,
	'XML::LibXML' => 0,
	'CIHM::Normalise' => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'CIHM-METS-parse-*' },
);
