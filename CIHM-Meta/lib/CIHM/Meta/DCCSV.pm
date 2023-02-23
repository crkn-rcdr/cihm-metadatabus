package CIHM::Meta::DCCSV;

use strict;
use Carp;
use Log::Log4perl;
use Try::Tiny;
use Data::Dumper;
use Switch;
use Text::CSV;
use File::Path qw(make_path remove_tree);

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

    make_path( $self->csvdir );

    foreach my $prefix ( sort keys %{ $self->dcrecords } ) {

        # Maximum number of elements over all identifiers.
        my %maxelement;

        foreach my $identifier ( sort keys %{ $self->dcrecords->{$prefix} } ) {
            foreach my $element (DCELEMENTS) {
                if ( !defined $maxelement{$element} ) {
                    $maxelement{$element} = 1;
                }
                my $count = scalar(
                    @{
                        $self->dcrecords->{$prefix}->{$identifier}->{$element}
                    }
                );
                $maxelement{$element} = $count
                  if ( $count > $maxelement{$element} );
            }
        }

        # Build the CSV array
        my @csvrows;
        {
            # Create header
            my @header;
            push @header, "objid";
            foreach my $element (DCELEMENTS) {
                foreach ( 1 .. $maxelement{$element} ) {
                    push @header, "dc." . $element;
                }
            }
            push @csvrows, \@header
        }
        foreach my $identifier ( sort keys %{ $self->dcrecords->{$prefix} } ) {

            my @row;
            push @row, $identifier;

            foreach my $element (DCELEMENTS) {
                foreach my $index ( 0 .. $maxelement{$element} - 1 ) {
                    if (
                        defined $self->dcrecords->{$prefix}->{$identifier}
                        ->{$element}->[$index] )
                    {
                        push @row, $self->dcrecords->{$prefix}->{$identifier}
                          ->{$element}->[$index];
                    }
                    else {
                        push @row, '';
                    }
                }
            }
            push @csvrows, \@row;
        }

        my $csvfile = $self->csvdir . "/$prefix.csv";
        print "Writing: $csvfile\n";

        # Write as CSV
        my $csv = Text::CSV->new( { binary => 1, auto_diag => 1 } );
        open my $fh, ">:encoding(utf8)", $csvfile or die "opening $csvfile: $!";
        $csv->say( $fh, $_ ) for @csvrows;
        close $fh or die "closing $csvfile: $!"

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
        case /^oocihm\.N_/ {
            my @x = split( '_', $id );
            $prefix = join( '_', splice( @x, 0, 2 ) );
        }
        case /^oocihm\.\d_/ {
            $prefix = substr( $id, 0, 10 );
        }
        case /^oocihm\.\d\d/ {
            $prefix = substr( $id, 0, 9 );
        }
        case /^oocihm\.lac_reel_/ {
            $prefix = substr( $id, 0, 18 );
        }
        else {
            my @x = split( /\./, $id );
            my @y = @x;
            $prefix = shift @x;
        }

    }
    return $prefix;
}

1;
