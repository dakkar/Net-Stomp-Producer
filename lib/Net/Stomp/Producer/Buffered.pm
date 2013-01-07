package Net::Stomp::Producer::Buffered;
use Moose;
extends 'Net::Stomp::Producer';
use Net::Stomp::Producer::Exceptions;
use MooseX::Types::Common::Numeric 'PositiveOrZeroInt';
use Try::Tiny;

# ABSTRACT: subclass of Net::Stomp::Producer with transaction-like behaviour

=head1 SYNOPSIS

  my $p = Net::Stomp::Producer::Buffered->new({
      servers => [ { hostname => 'localhost', port => 61613, } ],
  });

  $p->start_buffering();

  $p->send('/queue/somewhere',
           { type => 'my_message' },
           'body contents');
  # nothing sent yet

  # some time later
  $p->stop_buffering();
  # all buffered messages are sent now

Also:

  $p->buffered_do(sub{
    # do something...

    $p->send(@msg1);

    # do something else...

    $p->send(@msg2);
  });
  # all messages are sent now, unless an exception was thrown

=head1 DESCRIPTION

A subclass of L<Net::Stomp::Producer>, this class adds some
transaction-like behaviour.

If you call L</start_buffering>, the messages sent through this object
will be kept in memory instead of being actually sent to the STOMP
connection. They will be sent when you call L</stop_buffering>,

There is also a L</buffered_do> method, which takes a coderef and
executes it between a L</start_buffering> and a L</stop_buffering>. If
the coderef throws an exception, the buffer is cleared and no message
is sent.

=cut

has _buffered_frames => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub { [] },
    traits => [ 'Array' ],
    handles => {
        _add_frame_to_buffer => 'push',
        _all_frames => 'elements',
        _clear_frame_buffer => 'clear',
    },
);

=attr C<buffering>

If 0 (the default), we're not buffering. You can change this with
L</start_buffering> and L</stop_buffering>.

=method C<start_buffering>

Start buffering (by incrementing L</buffering>), so that subsequent
calls to C<send> or C<transform_and_send> won't really send messages
to the connection, but keep them in memory.

You can call this method multiple times; the buffering will stop (and
messages will be sent) when you call L</stop_buffering> as many times
as you called C<start_buffering>.

=method C<stop_buffering>

Decrement L</buffering>. If it's now 0, send all buffered messages.

If you call this method B<more times> than you called
L</start_buffering>, you'll get an exception (from
L<MooseX::Types::Common::Numeric::PositiveOrZeroInt|MooseX::Types::Common::Numeric/PositiveOrZeroInt>).

=cut

has buffering => (
    is => 'ro',
    isa => PositiveOrZeroInt,
    traits => ['Counter'],
    default => 0,
    handles => {
        start_buffering => 'inc',
        stop_buffering => 'dec',
    },
);

has _inside_buffered_do => (
    is => 'ro',
    isa => PositiveOrZeroInt,
    traits => ['Counter'],
    default => 0,
    handles => {
        _start_buffered_do => 'inc',
        _stop_buffered_do => 'dec',
    },
);

=method C<send>

If L</buffering> is 0, send the message normally; otherwise, add it to
the in-memory buffer. See L<the base method|Net::Stomp::Producer/send>
for more details.

=cut

override send => sub {
    my ($self,$destination,$headers,$body) = @_;

    my $actual_headers = $self->_prepare_message($destination,$headers,$body);

    if ($self->buffering) {
        $self->_add_frame_to_buffer($actual_headers);
    }
    else {
        $self->_really_send($actual_headers);
    }

    return;
};

=method C<send_buffered>

Send all buffered messages, and clear the buffer. This does not affect
L</buffering> at all. If L</buffering> is 0, calling this method is a
no-op.

This method can't be called inside a L</buffered_do>, you'll get a
L<Net::Stomp::Producer::Exceptions::Buffering> if you try.

=cut

sub send_buffered {
    my ($self) = @_;

    if ($self->_inside_buffered_do) {
        Net::Stomp::Producer::Exceptions::Buffering->throw();
    }

    for my $f ($self->_all_frames) {
        $self->_really_send($f);
    }
    $self->_clear_frame_buffer;

    return;
}

after stop_buffering => sub {
    my ($self) = @_;

    $self->send_buffered unless $self->buffering;
};

=method C<buffered_do>

  $p->buffered_do(sub {
    $p->send(@something);
  });

This method executes the given coderef between a L</start_buffering>
and a L</stop_buffering>.

If the coderef throws an exception, the buffer will be cleared,
L</stop_buffering> will be called, and the exception re-thrown.

This method is re-entrant:

  $p->buffered_do(sub {
    $p->send(@msg1);
    eval {
      $p->buffered_do(sub {
        $p->send(@msg2);
        die "boom\n";
      });
    };
    $p->send(@msg3);
 });

The first and thind messages will be sent, the second one will not.

You cannot call L</send_buffered> from inside C<buffered_do>, you'll
get a L<Net::Stomp::Producer::Exceptions::Buffering> if you try.

=cut

sub buffered_do {
    my ($self,$code) = @_;

    $self->start_buffering;
    $self->_start_buffered_do;
    my @saved_buffer = $self->_all_frames;
    try {
        $code->();
    }
    catch {
        $self->_clear_frame_buffer;
        $self->_stop_buffered_do;
        $self->stop_buffering;
        $self->_add_frame_to_buffer(@saved_buffer);
        die $_;
    };
    $self->_stop_buffered_do;
    $self->stop_buffering;
    return;
}

__PACKAGE__->meta->make_immutable;

1;
