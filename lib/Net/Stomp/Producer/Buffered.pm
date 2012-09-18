package Net::Stomp::Producer::Buffered;
use Moose;
extends 'Net::Stomp::Producer';

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
    is => 'rw',
    isa => 'Bool',
    default => 0,
    trigger => \&send_buffered,
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

    for my $f ($self->all_frames) {
        $self->_really_send($f);
    }
    $self->clear_frame_buffer;

    return;
}

__PACKAGE__->meta->make_immutable;

1;
