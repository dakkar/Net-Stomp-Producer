package Net::Stomp::Producer::Transactional;
use Moose;
extends 'Net::Stomp::Producer';
use Net::Stomp::Producer::Exceptions;
use MooseX::Types::Common::Numeric 'PositiveOrZeroInt';
use Try::Tiny;

# ABSTRACT: subclass of Net::Stomp::Producer with transaction-like behaviour

=head1 SYNOPSIS

  my $p = Net::Stomp::Producer::Transactional->new({
      servers => [ { hostname => 'localhost', port => 61613, } ],
  });

  $p->txn_begin();

  $p->send('/queue/somewhere',
           { type => 'my_message' },
           'body contents');
  # nothing sent yet

  # some time later
  $p->txn_commit();
  # all messages are sent now

Also:

  $p->txn_do(sub{
    # do something...

    $p->send(@msg1);

    # do something else...

    $p->send(@msg2);
  });
  # all messages are sent now, unless an exception was thrown

=head1 DESCRIPTION

A subclass of L<Net::Stomp::Producer>, this class adds some
transaction-like behaviour.

If you call L</txn_begin>, the messages sent through this object will
be kept in memory instead of being actually sent to the STOMP
connection. They will be sent when you call L</txn_commit>,

There is also a L</txn_do> method, which takes a coderef and executes
it between a L</txn_begin> and a L</txn_commit>. If the coderef throws
an exception, the buffer is cleared and no message is sent.

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

=attr C<in_transaction>

If 0 (the default), we're not inside a "transaction". You can change
this with L</txn_begin>, L</txn_commit> and L</txn_rollback>.

=method C<txn_begin>

Start buffering (by incrementing L</in_transaction>), so that
subsequent calls to C<send> or C<transform_and_send> won't really send
messages to the connection, but keep them in memory.

You can call this method multiple times; the buffering will stop (and
messages will be sent) when you call L</txn_commit> as many times as
you called C<txn_begin>.

Calling L</txn_rollback> will ...

=method C<txn_commit>

Decrement L</in_transaction>. If it's now 0, send all buffered messages.

If you call this method B<more times> than you called L</txn_begin>,
you'll get an exception (from
L<MooseX::Types::Common::Numeric::PositiveOrZeroInt|MooseX::Types::Common::Numeric/PositiveOrZeroInt>).

=cut

has in_transaction => (
    is => 'ro',
    isa => PositiveOrZeroInt,
    traits => ['Counter'],
    default => 0,
    handles => {
        txn_begin => 'inc',
        txn_commit => 'dec',
    },
);

has _inside_txn_do => (
    is => 'ro',
    isa => PositiveOrZeroInt,
    traits => ['Counter'],
    default => 0,
    handles => {
        _start_txn_do => 'inc',
        _stop_txn_do => 'dec',
    },
);

=method C<send>

If L</in_transaction> is 0, send the message normally; otherwise, add
it to the in-memory buffer. See L<the base
method|Net::Stomp::Producer/send> for more details.

=cut

override send => sub {
    my ($self,$destination,$headers,$body) = @_;

    my $actual_headers = $self->_prepare_message($destination,$headers,$body);

    if ($self->in_transaction) {
        $self->_add_frame_to_buffer($actual_headers);
    }
    else {
        $self->_really_send($actual_headers);
    }

    return;
};

sub _send_buffered {
    my ($self) = @_;

    if ($self->_inside_txn_do) {
        Net::Stomp::Producer::Exceptions::Buffering->throw();
    }

    for my $f ($self->_all_frames) {
        $self->_really_send($f);
    }
    $self->_clear_frame_buffer;

    return;
}

after txn_commit => sub {
    my ($self) = @_;

    $self->_send_buffered unless $self->in_transaction;
};

=method C<txn_do>

  $p->txn_do(sub {
    $p->send(@something);
  });

This method executes the given coderef between a L</txn_begin> and a
L</txn_commit>.

If the coderef throws an exception, the buffer will be cleared,
L</txn_commit> will be called, and the exception re-thrown.

This method is re-entrant:

  $p->txn_do(sub {
    $p->send(@msg1);
    eval {
      $p->txn_do(sub {
        $p->send(@msg2);
        die "boom\n";
      });
    };
    $p->send(@msg3);
 });

The first and thind messages will be sent, the second one will not.

=cut

sub txn_do {
    my ($self,$code) = @_;

    $self->txn_begin;
    $self->_start_txn_do;
    my @saved_buffer = $self->_all_frames;
    try {
        $code->();
    }
    catch {
        $self->_clear_frame_buffer;
        $self->_stop_txn_do;
        $self->txn_commit;
        $self->_add_frame_to_buffer(@saved_buffer);
        die $_;
    };
    $self->_stop_txn_do;
    $self->txn_commit;
    return;
}

__PACKAGE__->meta->make_immutable;

1;
