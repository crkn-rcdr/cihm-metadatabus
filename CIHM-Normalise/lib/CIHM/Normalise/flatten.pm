package CIHM::Normalise::flatten;

use strict;
use Switch;
use CIHM::Normalise::dc;
use CIHM::Normalise::issueinfo;
use CIHM::Normalise::marc;

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    return $self;
}

sub byType {
    my ( $self, $type, $xmlin ) = @_;

    switch ( lc($type) ) {
        case "issueinfo" { return $self->issueinfo($xmlin) }
        case "marc"      { return $self->marc($xmlin) }
        case "dc"        { return $self->dc($xmlin) }
        else             { die "Unknown DMD type: $type\n" }
    }

}


1;
