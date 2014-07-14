package Stomp_LogCalls;
use strict;
use warnings;
use Net::Stomp::Frame;

our @calls;

sub new {
    my ($class,@args) = @_;
    push @calls,['new',$class,@args];
    bless {},$class;
}

for my $m (qw(subscribe unsubscribe
              receive_frame ack
              send send_frame send_transactional)) {
    no strict 'refs';
    *$m=sub {
        push @calls,[$m,@_];
        return 1;
    };
}

sub current_host { return 0 }

sub connect {
    push @calls,['connect',@_];
    return Net::Stomp::Frame->new({
        command => 'CONNECTED',
        headers => {
            session => 'ID:foo',
        },
        body => '',
    });
}

1;
