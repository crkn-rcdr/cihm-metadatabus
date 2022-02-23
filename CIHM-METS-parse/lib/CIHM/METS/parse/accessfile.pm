package CIHM::METS::parse::accessfile;

use 5.014;
use strict;
use File::Slurp;
use File::Spec;

sub new {
    my($class, $args) = @_;
    my $self = bless {}, $class;

    if (ref($args) ne "HASH") {
        die "Argument to CIHM::METS::parse::accessfile->new() not a hash\n";
    };
    $self->{args} = $args;
    return $self;
}

sub args {
    my $self = shift;
    return $self->{args};
}
sub pathtomets {
    my $self = shift;
    return $self->args->{pathtomets};
}

# Return the contents of the file as a string
sub get_metadata {
    my ($self,$file) = @_;
    my $filename=File::Spec->catfile($self->pathtomets,$file);
    return scalar(read_file($filename));
}

1;
