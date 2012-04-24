#!perl
use strict;
use warnings;
{package CallBacks;
 our @calls;
 sub new {
     my ($class,@args) = @_;
     push @calls,['new',$class,@args];
     bless {},$class;
 }
 our $fail;
 for my $m (qw(connect
               subscribe unsubscribe
               receive_frame ack
               send send_frame)) {
     no strict 'refs';
     *$m=sub {
         push @calls,[$m,@_];
         $fail->($m,@_) if $fail;
         return 1;
     };
 }
}

package main;
use Test::More;
use Test::Fatal;
use Test::Deep;
use Data::Printer;
use Net::Stomp::Producer;
use JSON::XS;
my $p;
$p=Net::Stomp::Producer->new({
    connection_builder => sub { return CallBacks->new(@_) },
    servers => [ {
        hosts => [
            { hostname => 'test-host', port => 9999, },
            { hostname => 'test-host-failover', port => 9999, },
        ],
    }, {
        hosts => [
            { hostname => 'second-test-host', port => 9999, },
            { hostname => 'second-test-host-failover', port => 9999, },
        ],
    }, ],
});

subtest 'normal connection' => sub {
    $p->send('somewhere',{},'string');

    cmp_deeply(\@CallBacks::calls,
               [
                   [
                       'new',
                       'CallBacks',
                       { hosts => [
                           { hostname => 'test-host', port => 9999 },
                           { hostname => 'test-host-failover', port => 9999 },
                       ] },
                   ],
                   ignore(),
                   ignore(),
               ],
               'STOMP connect called with expected params')
        or note p @CallBacks::calls;
};

subtest 'failing connection' => sub {

    @CallBacks::calls=();
    $CallBacks::fail=sub {
        if ($_[0] eq 'connect' and $_[1]->{hosts}[0]{hostname} eq 'test-host') {
            die "connecting\n";
        }
        if ($_[0] eq 'send' and @CallBacks::calls < 2) {
            die "sending\n";
        }
    };

    $p->send('somewhere',{},'string');

    cmp_deeply(\@CallBacks::calls,
               [
                   [
                       'send',
                       ignore(),
                       ignore(),
                   ],
                   [
                       'new',
                       'CallBacks',
                       { hosts => [
                           { hostname => 'second-test-host', port => 9999 },
                           { hostname => 'second-test-host-failover', port => 9999 },
                       ] },
                   ],
                   [
                       'connect',
                       ignore(),
                       ignore(),
                   ],
                   [
                       'send',
                       ignore(),
                       ignore(),
                   ],
               ],
               'STOMP connect called with expected params')
        or note p @CallBacks::calls;
};

done_testing();
