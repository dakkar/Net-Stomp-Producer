#!perl
use strict;
use warnings;
{package CallBacks;
 use Net::Stomp::Frame;
 our @calls;
 sub new {
     my ($class,@args) = @_;
     push @calls,['new',$class,@args];
     bless {},$class;
 }
 for my $m (qw(subscribe unsubscribe
               receive_frame ack
               send send_frame)) {
     no strict 'refs';
     *$m=sub {
         push @calls,[$m,@_];
         return 1;
     };
 }
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
}

{package Tr1;
 sub new {
     my ($class,$args) = @_;
     my $self = { arg => delete $args->{foo} };
     return bless $self,$class;
 }
 sub transform {
     my ($self) = @_;
     return {destination => 'foo'},
         $self->{arg};
 }
}

package main;
use Test::More;
use Test::Deep;
use Data::Printer;
use Net::Stomp::Producer;

my $args = { foo => '123' };
my $p=Net::Stomp::Producer->new({
    connection_builder => sub { return CallBacks->new(@_) },
    servers => [ {
        hostname => 'test-host', port => 9999,
    } ],
    transformer_args => $args,
});

is($p->transformer_args,$args,
   "transformer_args takes the ref");

$p->transform_and_send('Tr1',{});
cmp_deeply(\@CallBacks::calls,
           superbagof(
               [
                   'send',
                   ignore(),
                   {
                       body  => '123',
                       destination => '/foo',
                   },
               ],
           ),
           'sent the arg')
    or note p @CallBacks::calls;

cmp_deeply($p->transformer_args,{foo=>'123'},
           'args unchanged');

$p->transform_and_send('Tr1',{});
cmp_deeply(\@CallBacks::calls,
           superbagof(
               [
                   'send',
                   ignore(),
                   {
                       body  => '123',
                       destination => '/foo',
                   },
               ],
           ),
           'sent the arg, second time')
    or note p @CallBacks::calls;

cmp_deeply($p->transformer_args,{foo=>'123'},
           'args still unchanged');

done_testing;
