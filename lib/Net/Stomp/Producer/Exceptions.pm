package Net::Stomp::Producer::Exceptions;
use Net::Stomp::MooseHelpers::Exceptions;

{package Net::Stomp::Producer::Exceptions::StackTrace;
 use Moose::Role;
 use namespace::autoclean;
 with 'StackTrace::Auto';

 around _build_stack_trace_args => sub {
     my ($orig,$self) = @_;

     my $ret = $self->$orig();
     push @$ret, (
         no_refs => 1,
         respect_overload => 1,
         message => '',
         indent => 1,
     );

     return $ret;
 };
}

{package Net::Stomp::Producer::Exceptions::BadMessage;
 use Moose;with 'Throwable',
     'Net::Stomp::MooseHelpers::Exceptions::Stringy',
     'Net::Stomp::Producer::Exceptions::StackTrace';
 use namespace::autoclean;
 use Data::Dump 'dump';
 has message => ( is => 'ro', required => 1 );
 has reason => ( is => 'ro', default => q{sending the message didn't work} );

 sub as_string {
     my ($self) = @_;
     sprintf "%s (%s): %s\n%s",
         $self->reason,dump($self->message),$self->previous_exception,
         $self->stack_trace->as_string;
 }
 __PACKAGE__->meta->make_immutable;
}

{package Net::Stomp::Producer::Exceptions::CantSerialize;
 use Moose;extends 'Net::Stomp::Producer::Exceptions::BadMessage';
 has '+reason' => ( default => q{couldn't serialize message} );
 __PACKAGE__->meta->make_immutable;
}

{package Net::Stomp::Producer::Exceptions::BadTransformer;
 use Moose;with 'Throwable',
     'Net::Stomp::MooseHelpers::Exceptions::Stringy',
     'Net::Stomp::Producer::Exceptions::StackTrace';
 use namespace::autoclean;
 has transformer => ( is => 'ro', required => 1 );

 sub as_string {
     my ($self) = @_;
     sprintf qq{%s is not a valid transformer, it doesn't have a "transform" method\n%s},
         $self->transformer,$self->stack_trace->as_string;
 }
 __PACKAGE__->meta->make_immutable;
}

1;
