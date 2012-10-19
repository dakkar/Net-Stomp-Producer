package Net::Stomp::Producer::Buffered;
{
  $Net::Stomp::Producer::Buffered::VERSION = '1.4';
}
{
  $Net::Stomp::Producer::Buffered::DIST = 'Net-Stomp-Producer';
}
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
}

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

__END__
=pod

=encoding utf-8

=head1 NAME

Net::Stomp::Producer::Buffered

=head1 VERSION

version 1.4

=head1 AUTHOR

Gianni Ceccarelli <gianni.ceccarelli@net-a-porter.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Net-a-porter.com.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

