package CIHM::Meta::REST::UserAgent;

use 5.006;
use strict;
use warnings FATAL => 'all';

use parent qw(HTTP::Thin);
use URI;
use URI::Escape;
use DateTime;
use Crypt::JWT qw(encode_jwt);
use JSON;

our $VERSION = '0.04';

sub new {
    my ( $class, %args ) = @_;

    my $self = $class->SUPER::new(%args);

    $self->{jwt_secret} = $args{jwt_secret} || die "Must supply jwt_secret\n";
    $self->{jwt_algorithm} = $args{jwt_algorithm} || 'HS256';
    my $payload = $args{jwt_payload} || {};

    if ( ref($payload) =~ /^(HASH|ARRAY)$/ ) {
        $self->{jwt_payload} = $payload;
    }
    else {
        $self->{jwt_payload} = decode_json($payload);
    }

    return bless $self, $class;
}

# override this HTTP::Tiny method to add authorization/date headers
sub _prepare_headers_and_cb {
    my ( $self, $request, $args, $url, $auth ) = @_;
    $self->SUPER::_prepare_headers_and_cb( $request, $args, $url, $auth );

    # add our own very special authorization headers
    $self->_add_bearer_headers( $request, $args );

    return;
}

sub encode_param {
    my $param = shift;
    URI::Escape::uri_escape( $param, '^\w.~-' );
}

sub _add_bearer_headers {
    my ( $self, $request, $args ) = @_;
    my $uri    = URI->new( $request->{uri} );
    my $method = uc $request->{method};

    # Hard-code iss, as this is no longer an option
    $self->{jwt_payload}->{iss} = 'CAP';

    my $jws_token = encode_jwt(
        payload => $self->{jwt_payload},
        alg     => $self->{jwt_algorithm},
        key     => $self->{jwt_secret}
    );

    $request->{headers}{'Authorization'} =
      "Bearer " . encode_param($jws_token);
    return;
}

1;
