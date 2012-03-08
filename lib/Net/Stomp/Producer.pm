package Net::Stomp::Producer;
use Moose;
use namespace::autoclean;
with 'Net::Stomp::MooseHelpers::CanConnect';
use MooseX::Types::Moose qw(CodeRef HashRef);
use Net::Stomp::Producer::Exceptions;
use Class::Load 'load_class';
use Try::Tiny;

# ABSTRACT: helper object to send messages via Net::Stomp

=head1 SYNOPSIS

  my $ser = JSON::XS->new->utf8;

  my $p = Net::Stomp::Producer->new({
    servers => [ { hostname => 'localhost', port => 61613 } ],
    serializer => sub { $ser->encode($_[0]) },
    default_headers => { 'content-type' => 'json' },
  });

  $p->send('/queue/somewhere',
           { type => 'my_message' },
           { a => [ 'data', 'structure' ] });

Also:

  package My::Message::Transformer {
    use Moose;
    sub transform {
      my ($self,@elems) = @_;

      return { destination => '/queue/somewhere',
               type => 'my_message', },
             { a => \@elems };
    }
  }

  $p->transform_and_send('My::Message::Transformer',
                         'data','structure');

Or even:

  my $t = My::Message::Transformer->new();
  $p->transform_and_send($t,
                         'data','structure');

They all send the same message.

=head1 DESCRIPTION

This class sends messages via a STOMP connection (see
L<Net::Stomp::MooseHelpers::CanConnect>). It provides facilities for
serialisation and validation.

You can use it at several levels:

=head2 Raw sending

  my $p = Net::Stomp::Producer->new({
    servers => [ { hostname => 'localhost', port => 61613 } ],
  });

  $p->send($destination,\%headers,$body_byte_string);

This will just wrap the parameters in a L<Net::Stomp::Frame> and send
it. C<$destination> can be undef, if you have set it in the
C<%headers>.

=head2 Serialisation support

  my $p = Net::Stomp::Producer->new({
    servers => [ { hostname => 'localhost', port => 61613 } ],
    serializer => sub { encode_json($_[0]) },
  });

  $p->send($destination,\%headers,$body_hashref);

The body will be passed through the C<serializer>, and the resulting
string will be used as above.

=head2 Transformer instance

  $p->transform_and_send($transformer_obj,@args);

This will call C<< $transformer_obj->transform(@args) >>. That
function should return a list (with an even number of elements). Each
pair of elements is interpreted as C<< \%headers, $body_ref >> and
passed to L</send> as above (with no C<destination>, so the
transformer should set it in the headers). It's not an error for the
transformer to return an empty list: it just means that nothing will
be sent.

=head2 Transformer class

  my $p = Net::Stomp::Producer->new({
    servers => [ { hostname => 'localhost', port => 61613 } ],
    transformer_args => { some => 'param' },
  });

  $p->transform_and_send($transformer_class,@args);

The transformer will be instantiated like C<<
$transformer_class->new($p->transformer_args) >>, then the object will
be called as above.

=head2 Transform & validate

If the transformer class / object supports the C<validate> method, it
will be called before sending each message, like:

  $transformer_obj->validate(\%headers,$body_ref);

This method is expected to return a true value if the message is
valid, and throw a meaningful exception if it is not. The exception
will be wrapped in a L<Net::Stomp::Producer::Exceptions::Invalid>. If
the C<validate> method returns false without throwing any exception,
L<Net::Stomp::Producer::Exceptions::Invalid> will still be throw, but
the C<previous_exception> slot will be undef.

=cut

# we automatically send the C<connect> frame
around _build_connection => sub {
    my ($orig,$self,@etc) = @_;
    my $conn = $self->$orig(@etc);
    $conn->connect();
    return $conn;
};

has serializer => (
    isa => CodeRef,
    is => 'rw',
    default => \&_no_serializer,
);

sub _no_serializer {
    my ($message) = @_;
    return $message unless ref $message;

    Net::Stomp::Producer::Exceptions::CantSerialize->throw({
        previous_exception => q{can't send a reference without a serializer},
        message_body => $message,
    });
}

has default_headers => (
    isa => HashRef,
    is => 'rw',
    default => sub { { } },
);

sub send {
    my ($self,$destination,$headers,$body) = @_;
    use bytes;

    try { $body = $self->serializer->($body) }
    catch {
        Net::Stomp::Producer::Exceptions::CantSerialize->throw({
            message_body => $body,
        });
    };

    my %actual_headers=(
        %{$self->default_headers},
        %$headers,
        'content-length' => length($body),
        body => $body,
    );

    $actual_headers{destination} = $destination if defined $destination;

    for ($actual_headers{destination}) {
        $_ = "/$_"
            unless m{^/};
    }

    $self->connection->send(\%actual_headers);

    return;
}

has transformer_args => (
    is => 'rw',
    isa => HashRef,
    default => sub { { } },
);

sub make_transformer {
    my ($self,$transformer) = @_;

    return $transformer if ref($transformer);

    load_class($transformer);
    if ($transformer->can('new')) {
        return $transformer->new($self->transformer_args);
    }
    return $transformer;
}

sub transform_and_send {
    my ($self,$transformer,@input) = @_;

    $transformer=$self->make_transformer($transformer);

    my $method = try { $transformer->can('transform') }
        or Net::Stomp::Producer::Exceptions::BadTransformer->throw({
            transformer => $transformer,
        });

    my @messages = $transformer->$method(@input);

    my $vmethod = try { $transformer->can('validate') };

    while (my ($headers, $body) = splice @messages, 0, 2) {
        if ($vmethod) {
            my $exception;
            my $valid = try {
                $transformer->$vmethod($headers,$body);
            } catch { $exception = $_ };
            if (!$valid) {
                Net::Stomp::Producer::Exceptions::Invalid->throw({
                    transformer => $transformer,
                    message_body => $body,
                    message_headers => $headers,
                    previous_exception => $exception,
                });
            }
        }
        $self->send(undef,$headers,$body);
    }

    return;
}

1;
