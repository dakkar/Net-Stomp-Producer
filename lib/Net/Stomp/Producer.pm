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
serialisation and validation. You can have an instance of this class
as a singleton / global in your process, and use it to send all your
messages: this is recommended, as it will prevent flooding the broker
with many connections (each instance would connect independently, and
if you create many instances per second, the broker or your process
may run out of file descriptiors and stop working).

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
    $self->_connect($conn);
    return $conn;
};

sub _connect {
    my ($self,$connection) = @_;

    try {
        my $server = $self->current_server;
        my %headers = (
            %{$self->connect_headers},
            %{$server->{connect_headers} || {}},
        );
        $connection->connect(\%headers);
    } catch {
        Net::Stomp::MooseHelpers::Exceptions::Stomp->throw({
            stomp_error => $_
        });
    };
}

=method C<connect>

Since the connection is set up automatically, this method (usually
provided by L<Net::Stomp::MooseHelpers::CanConnect>) is overridden to
be a no-op and warn. Don't call it.

=cut

sub connect { warn "No-op, Net::Stomp::Producer connects on its own" }

=attr C<serializer>

A coderef that, passed the body parameter from L</send>, returns a
byte string to use as the frame body. The default coderef will just
pass non-refs through, and die (with a
L<Net::Stomp::Producer::Exceptions::CantSerialize> exception) if
passed a ref.

=cut

has serializer => (
    isa => CodeRef,
    is => 'rw',
    default => sub { \&_no_serializer },
);

sub _no_serializer {
    my ($message) = @_;
    return $message unless ref $message;

    Net::Stomp::Producer::Exceptions::CantSerialize->throw({
        previous_exception => q{can't send a reference without a serializer},
        message_body => $message,
    });
}

=attr C<default_headers>

Hashref of STOMP headers to use for every frame we send. Headers
passed in to L</send> take precedence. There is no support for
I<removing> a default header for a single send.

=cut

has default_headers => (
    isa => HashRef,
    is => 'rw',
    default => sub { { } },
);

=method C<send>

  $p->send($destination,\%headers,$body);

Serializes the C<$body> via the L</serializer>, merges the C<%headers>
with the L</default_headers>, setting the C<content-length> to the
byte length of the serialized body. Overrides the destination in the
headers with C<$destination> if it's defined.

Finally, sends the frame.

=cut

sub send {
    my ($self,$destination,$headers,$body) = @_;
    use bytes;

    try { $body = $self->serializer->($body) }
    catch {
        if (eval {$_[0]->isa('Net::Stomp::Producer::Exceptions::CantSerialize')}) {
            die $_[0];
        }
        my $prev=$_[0];
        Net::Stomp::Producer::Exceptions::CantSerialize->throw({
            message_body => $body,
            previous_exception => $prev,
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

    while (1) {
        my $done=0;
        try {
            $self->connection->send(\%actual_headers);
            $done=1;
        } catch {
            $self->clear_connection;
        };
        last if $done;
    }

    return;
}

=attr C<transformer_args>

Hashref to pass to the transformer constructor when
L</make_transformer> instantiates a transformer class.

=cut

has transformer_args => (
    is => 'rw',
    isa => HashRef,
    default => sub { { } },
);

=method C<make_transformer>

  $p->make_transformer($class);

If passed a reference, this function just returns it (it assumes it's
a transformer object ready to use).

If passed a string, tries to load the class with
L<Class::Load::load_class|Class::Load/load_class>. If the class has a
C<new> method, it's invoked with the value of L</transformer_args> to
obtain an object that is then returned. If the class does not have a
C<new>, the class name is returned.

=cut

sub make_transformer {
    my ($self,$transformer) = @_;

    return $transformer if ref($transformer);

    load_class($transformer);
    if ($transformer->can('new')) {
        return $transformer->new($self->transformer_args);
    }
    return $transformer;
}

=method C<transform_and_send>

  $p->transform_and_send($transformer,@data);

Uses L</make_transformer> to (optionally) instantiate a transformer
object, then tries to call C<transform> on it. If there is no such
method, a L<Net::Stomp::Producer::Exceptions::BadTransformer> is
thrown.

The transformer is expected to return a list of (header,body) pairs
(that is, a list with an even number of elements; I<not> a list of
arrayrefs!).

Each message in the returned list is optionally validated, then sent
(via the L</send> method).

The optional validation happens if the transformer C<<
->can('validate') >>. IF it can, that method is called like:

  $transformer->validate($header,$body_ref);

The method is expected to return a true value if the message is valid,
and throw a meaningful exception if it is not. The exception will be
wrapped in a L<Net::Stomp::Producer::Exceptions::Invalid>. If the
C<validate> method returns false without throwing any exception,
L<Net::Stomp::Producer::Exceptions::Invalid> will still be throw, but
the C<previous_exception> slot will be undef.

It's not an error for the transformer to return an empty list: it just
means that nothing will be sent.

=cut

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
                local $@=$exception;
                Net::Stomp::Producer::Exceptions::Invalid->throw({
                    transformer => $transformer,
                    message_body => $body,
                    message_headers => $headers,
                });
            }
        }
        $self->send(undef,$headers,$body);
    }

    return;
}

__PACKAGE__->meta->make_immutable;

=head1 EXAMPLES

You can find examples of use in the tests, or at
https://github.com/dakkar/CatalystX-StompSampleApps

=cut

1;
