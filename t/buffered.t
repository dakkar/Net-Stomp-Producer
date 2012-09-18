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

subtest 'direct send' => sub {
    @Stomp_LogCalls::calls=();

    $p->send('/queue/foo',{},'123');

    cmp_deeply(\@Stomp_LogCalls::calls,
               superbagof(
                   [
                       'send',
                       ignore(),
                       {
                           body  => '123',
                           destination => '/queue/foo',
                       },
                   ],
               ),
               'direct send')
        or note p @Stomp_LogCalls::calls;
};

subtest 'buffered send' => sub {
    @Stomp_LogCalls::calls=();

    $p->buffering(1);

    $p->send('/queue/foo',{},'123');

    cmp_deeply(\@Stomp_LogCalls::calls,
               [],
               'nothing sent when buffering')
        or note p @Stomp_LogCalls::calls;

    $p->send_buffered();

    cmp_deeply(\@Stomp_LogCalls::calls,
               superbagof(
                   [
                       'send',
                       ignore(),
                       {
                           body  => '123',
                           destination => '/queue/foo',
                       },
                   ],
               ),
               'sent from buffer')
        or note p @Stomp_LogCalls::calls;
};

subtest 'switching between buffered and not' => sub {
    @Stomp_LogCalls::calls=();

    $p->buffering(0);
    $p->send('/queue/foo',{},'123');
    cmp_deeply(\@Stomp_LogCalls::calls,
               superbagof(
                   [
                       'send',
                       ignore(),
                       {
                           body  => '123',
                           destination => '/queue/foo',
                       },
                   ],
               ),
               'sent directly')
        or note p @Stomp_LogCalls::calls;

    @Stomp_LogCalls::calls=();

    $p->buffering(1);
    $p->send('/queue/foo',{},'124');

    cmp_deeply(\@Stomp_LogCalls::calls,
               [],
               'nothing sent when buffering')
        or note p @Stomp_LogCalls::calls;

    $p->buffering(0);
    cmp_deeply(\@Stomp_LogCalls::calls,
               superbagof(
                   [
                       'send',
                       ignore(),
                       {
                           body  => '124',
                           destination => '/queue/foo',
                       },
                   ],
               ),
               'buffer sent when switching buffering off')
        or note p @Stomp_LogCalls::calls;

    @Stomp_LogCalls::calls=();

    $p->send('/queue/foo',{},'125');
    cmp_deeply(\@Stomp_LogCalls::calls,
               superbagof(
                   [
                       'send',
                       ignore(),
                       {
                           body  => '125',
                           destination => '/queue/foo',
                       },
                   ],
               ),
               'buffering off still means send directly')
        or note p @Stomp_LogCalls::calls;
};

done_testing();
