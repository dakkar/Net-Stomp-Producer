package Net::Stomp::Producer;
use Moose;
use namespace::autoclean;
with 'Net::Stomp::MooseHelpers::CanConnect';
use MooseX::Types::Moose qw(CodeRef HashRef);
use Net::Stomp::Producer::Exceptions;
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
    catch { Net::Stomp::Producer::Exceptions::CantSerialize->throw };

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

sub transform_and_send {
    my ($self,$transformer,@input) = @_;

    if (!ref($transformer) && $transformer->can('new')) {
        $transformer = $transformer->new($self->transformer_args);
    }

    my $method = try { $transformer->can('transform') }
        or Net::Stomp::Producer::Exceptions::BadTransformer->throw({
            transformer => $transformer,
        });

    my @messages = $transformer->$method(@input);

    while (my ($headers, $body) = splice @messages, 0, 2) {
        $self->send(undef,$headers,$body);
    }

    return;
}

1;
