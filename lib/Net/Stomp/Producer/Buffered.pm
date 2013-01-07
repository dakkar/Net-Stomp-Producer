package Net::Stomp::Producer::Buffered;
use Moose;
extends 'Net::Stomp::Producer';
use Net::Stomp::Producer::Exceptions;
use MooseX::Types::Common::Numeric 'PositiveOrZeroInt';
use Try::Tiny;

has buffered_frames => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub { [] },
    traits => [ 'Array' ],
    handles => {
        add_frame_to_buffer => 'push',
        all_frames => 'elements',
        clear_frame_buffer => 'clear',
    },
);

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

override send => sub {
    my ($self,$destination,$headers,$body) = @_;

    my $actual_headers = $self->_prepare_message($destination,$headers,$body);

    if ($self->buffering) {
        $self->add_frame_to_buffer($actual_headers);
    }
    else {
        $self->_really_send($actual_headers);
    }

    return;
};

sub send_buffered {
    my ($self) = @_;

    if ($self->_inside_buffered_do) {
        Net::Stomp::Producer::Exceptions::Buffering->throw();
    }

    for my $f ($self->all_frames) {
        $self->_really_send($f);
    }
    $self->clear_frame_buffer;

    return;
}

after stop_buffering => sub {
    my ($self) = @_;

    $self->send_buffered unless $self->buffering;
};

sub buffered_do {
    my ($self,$code) = @_;

    $self->start_buffering;
    $self->_start_buffered_do;
    my @saved_buffer = $self->all_frames;
    try {
        $code->();
    }
    catch {
        $self->clear_frame_buffer;
        $self->_stop_buffered_do;
        $self->stop_buffering;
        $self->add_frame_to_buffer(@saved_buffer);
        die $_;
    };
    $self->_stop_buffered_do;
    $self->stop_buffering;
    return;
}

__PACKAGE__->meta->make_immutable;

1;
