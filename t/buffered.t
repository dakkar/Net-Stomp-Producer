#!perl
use strict;
use warnings;
use lib 't/lib';
use Stomp_LogCalls;

use Test::More;
use Test::Deep;
use Data::Printer;
use Net::Stomp::Producer::Buffered;

my $p=Net::Stomp::Producer::Buffered->new({
    connection_builder => sub { return Stomp_LogCalls->new(@_) },
    servers => [ {
        hostname => 'test-host', port => 9999,
    } ],
});

sub assert_message_sent {
    my $diag = pop;
    my @bodies = @_;

    cmp_deeply(\@Stomp_LogCalls::calls,
               superbagof(
                   map { [
                       'send',
                       ignore(),
                       {
                           body  => $_,
                           destination => '/queue/foo',
                       },
                   ] } @bodies
               ),
               $diag)
        or note p @Stomp_LogCalls::calls;

    @Stomp_LogCalls::calls=();
}

sub assert_nothing_sent {
    my ($diag) = @_;

    cmp_deeply(\@Stomp_LogCalls::calls,
               [],
               $diag)
        or note p @Stomp_LogCalls::calls;
}

sub send_message {
    my ($body) = @_;

    $p->send('/queue/foo',{},$body);
}

subtest 'direct send' => sub {
    send_message('11');
    assert_message_sent('11','direct send');
};

subtest 'buffered send' => sub {
    $p->start_buffering();
    send_message('21');
    assert_nothing_sent('nothing sent when buffering');

    $p->send_buffered();
    assert_message_sent('21','sent from buffer');
};

subtest 'switching between buffered and not' => sub {
    $p->stop_buffering();
    send_message('31');
    assert_message_sent('31','sent directly');

    $p->start_buffering();
    send_message('32');
    assert_nothing_sent('nothing sent when buffering');

    $p->stop_buffering();
    assert_message_sent('32','buffer sent when switching buffering off');

    send_message('33');
    assert_message_sent('33','buffering off still means send directly');
};

subtest 'start/stop buffering is re-entrant' => sub {
    $p->start_buffering;
    send_message('41');
    assert_nothing_sent('nothing sent when buffering');

    $p->start_buffering;
    send_message('42');
    assert_nothing_sent('nothing sent when buffering twice');

    $p->stop_buffering;
    assert_nothing_sent('start twice, stop once: nothing sent');

    $p->stop_buffering;
    assert_message_sent('41','42','all messages sent when stopped as many times as started');
};

done_testing();
