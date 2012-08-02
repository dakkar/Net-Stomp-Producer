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
 for my $m (qw(connect
               subscribe unsubscribe
               receive_frame ack
               send send_frame)) {
     no strict 'refs';
     *$m=sub {
         push @calls,[$m,@_];
         return 1;
     };
 }
}
{package TransformClass;

 sub transform {
     my ($me,@data) = @_;
     return { destination => 'a_class' },
         { me => $me, data => \@data };
 }
}
{package TransformInstance;
 use Moose;

 has param => (is => 'ro');

 sub transform {
     my ($me,@data) = @_;
     return { destination => 'a_instance' }, 
         { me => ref($me), param => $me->param, data => \@data };
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
subtest 'building' => sub {
    cmp_deeply(exception {
        $p=Net::Stomp::Producer->new({
            connection_builder => sub { return CallBacks->new(@_) },
            servers => [ {
                hostname => 'test-host', port => 9999,
                # these are to be sure they get ignored
                subscribe_headers => { server_level => 'header' },
            } ],
            connect_headers => { foo => 'bar' },
            default_headers => { default => 'header' },
        })
    },undef,'can build');

    cmp_deeply(\@CallBacks::calls,[],
               'not connected yet')
        or note p @CallBacks::calls;
};

subtest 'serialisation failure' => sub {
    cmp_deeply(exception { $p->send('somewhere',{},{a=>'ref'}) },
               isa('Net::Stomp::Producer::Exceptions::CantSerialize'),
               'no serialiser set');

    cmp_deeply(\@CallBacks::calls,[],
               'still not connected')
        or note p @CallBacks::calls;
};

subtest 'straight send' => sub {
    cmp_deeply(exception { $p->send('somewhere',{},'{"a":"message"}') },
               undef,
               'no serialiser needed');

    cmp_deeply(\@CallBacks::calls,
               [
                   [
                       'new',
                       'CallBacks',
                       { hostname => 'test-host', port => 9999 },
                   ],
                   [
                       'connect',
                       ignore(),
                       { foo => 'bar' },
                   ],
                   [
                       'send',
                       ignore(),
                       {
                            body  => '{"a":"message"}',
                            default => 'header',
                            destination => '/somewhere',
                       },
                   ],
               ],
               'connected & sent')
        or note p @CallBacks::calls;
};

subtest 'serialise & send' => sub {
    @CallBacks::calls=();

    $p->serializer(sub{encode_json($_[0])});

    cmp_deeply(exception { $p->send('somewhere',{},{a=>'message'}) },
               undef,
               'serialiser worked');

    cmp_deeply(\@CallBacks::calls,
               [
                   [
                       'send',
                       ignore(),
                       {
                            body  => '{"a":"message"}',
                            default => 'header',
                            destination => '/somewhere',
                       },
                   ],
               ],
               'connected & sent')
        or note p @CallBacks::calls;
};

subtest 'transformer class' => sub {
    @CallBacks::calls=();

    $p->serializer(sub{encode_json($_[0])});

    cmp_deeply(exception {
        $p->transform_and_send('TransformClass',['some','data'])
    },
               undef,
               'transformer class worked');

    cmp_deeply(\@CallBacks::calls,
               [
                   [
                       'send',
                       ignore(),
                       {
                            body  => '{"me":"TransformClass","data":[["some","data"]]}',
                            default => 'header',
                            destination => '/a_class',
                       },
                   ],
               ],
               'connected & sent')
        or note p @CallBacks::calls;
};

subtest 'transformer instance' => sub {
    @CallBacks::calls=();

    $p->transformer_args({param => 'passed in'});

    cmp_deeply(exception {
        $p->transform_and_send('TransformInstance',['some','data'])
    },
               undef,
               'transformer class worked');

    cmp_deeply(\@CallBacks::calls,
               [
                   [
                       'send',
                       ignore(),
                       {
                            body  => '{"me":"TransformInstance","data":[["some","data"]],"param":"passed in"}',
                            default => 'header',
                            destination => '/a_instance',
                       },
                   ],
               ],
               'connected & sent')
        or note p @CallBacks::calls;
};

subtest 'transformer instance exception' => sub {
    @CallBacks::calls=();

    $p->transformer_args({param => 'passed in'});

    my $e;
    cmp_deeply($e=exception {
        $p->transform_and_send('TransformInstance',[$p])
    },
               all(
                   isa('Net::Stomp::Producer::Exceptions::CantSerialize'),
                   methods(previous_exception=>re(qr{^encountered object\b})),
               ),
               'transformer class died')
        or note $e;

    cmp_deeply(\@CallBacks::calls,
               [],
               'nothing sent')
        or note p @CallBacks::calls;
};

subtest 'split transform/send_many' => sub {
    $p->serializer(sub{encode_json($_[0])});

    my @msgs;
    cmp_deeply(exception {
        @msgs=$p->transform('TransformClass',['some','data'])
    },
               undef,
               'transformer class worked');
    cmp_deeply(exception {
        $p->send_many(@msgs)
    },
               undef,
               'send_many worked');

    cmp_deeply(\@CallBacks::calls,
               [
                   [
                       'send',
                       ignore(),
                       {
                            body  => '{"me":"TransformClass","data":[["some","data"]]}',
                            default => 'header',
                            destination => '/a_class',
                       },
                   ],
               ],
               'connected & sent')
        or note p @CallBacks::calls;
};

done_testing();
