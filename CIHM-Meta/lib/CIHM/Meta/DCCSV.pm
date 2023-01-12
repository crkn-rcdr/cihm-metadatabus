package CIHM::Meta::DCCSV;

use strict;
use Carp;
use Log::Log4perl;
use Try::Tiny;
use Data::Dumper;
use Switch;

use constant DCELEMENTS => qw(
  title
  creator
  subject
  description
  publisher
  contributor
  date
  type
  format
  identifier
  source
  language
  relation
  coverage
  rights
);

sub new {
    my ( $class, $args ) = @_;
    my $self = bless {}, $class;

    if ( ref($args) ne "HASH" ) {
        die "Argument to CIHM::Meta::SolrStream->new() not a hash\n";
    }
    $self->{args} = $args;

    $self->{dcrecords} = {};

    return $self;
}

# Simple accessors for now -- Do I want to Moo?
sub args {
    my $self = shift;
    return $self->{args};
}

sub dcrecords {
    my $self = shift;
    return $self->{dcrecords};
}

sub csvdir {
    my $self = shift;
    return $self->args->{csvdir};
}

sub addElement {
    my ( $self, $id, $element, $value ) = @_;

    my $prefix = $self->getPrefix($id);
    if ( !defined $self->dcrecords->{$prefix} ) {
        $self->dcrecords->{$prefix} = {};
        print "New Prefix: $prefix for $id\n";
    }

    if ( !defined $self->dcrecords->{$prefix}->{$id} ) {
        $self->dcrecords->{$prefix}->{$id} = {};
        foreach my $element (DCELEMENTS) {
            $self->dcrecords->{$prefix}->{$id}->{$element} = [];
        }
    }
    if ( !defined $self->dcrecords->{$prefix}->{$id}->{$element} ) {
        die "element=$element for $id isn't a DC element\n";
    }
    else {
        push @{ $self->dcrecords->{$prefix}->{$id}->{$element} }, $value;
    }
}

sub writeCSV {
    my ($self) = @_;

    return if ( !keys %{ $self->dcrecords } );

    print "csvdir: " . $self->csvdir . "\n";

    foreach my $prefix ( sort keys %{ $self->dcrecords } ) {
        print "$prefix count="
          . scalar( keys %{ $self->dcrecords->{$prefix} } ) . "\n";
    }
}

sub getPrefix {
    my ( $self, $id ) = @_;

    my $prefix;

    switch ($id) {

        case /^numeris\.TV/ {
            my @x = split( '_', $id );
            $prefix = join( '_', splice( @x, 0, 2 ) );
        }
        case /^numeris\.RD/ {
            $prefix = "numeris.RD"
        }

        #        case /^oocihm\.\d_/ {
        #            my @x = split( '_', $id );
        #            $prefix = join( '_', splice( @x, 0, 2 ) );
        #        }
        #        case /^oocihm\.\d\d/ {
        #            $prefix = substr( $id, 0, 9 );
        #        }
        else {
            my @x = split( /\./, $id );
            my @y = @x;
            $prefix = shift @x;
        }

    }
    return $prefix;
}

1;
