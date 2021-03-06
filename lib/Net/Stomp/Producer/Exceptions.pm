package Net::Stomp::Producer::Exceptions;
use Net::Stomp::MooseHelpers::Exceptions;

# ABSTRACT: exception classes for Net::Stomp::Producer

=head1 DESCRIPTION

This file defines the following exception classes, all based on
L<Throwable>:

=over 4

=item C<Net::Stomp::Producer::Exceptions::BadMessage>

Attributes: C<message_headers>, C<message_body>, C<reason>, C<stack_trace>.

=item C<Net::Stomp::Producer::Exceptions::CantSerialize>

Subclass of L</Net::Stomp::Producer::Exceptions::BadMessage>;
attributes: C<reason>.

Throw when the serialization fails.

=item C<Net::Stomp::Producer::Exceptions::BadTransformer>

Attributes: C<transformer>, C<stack_trace>.

Thrown when the transformer does not have a C<transform> method.

=item C<Net::Stomp::Producer::Exceptions::BadMethod>

Attributes: C<sending_method_value>, C<method_to_call>,
C<stack_trace>.

Thrown when L<Net::Stomp::Producer/sending_method> is set to a value
that would require us to call a non-existent method on the connection.

=item C<Net::Stomp::Producer::Exceptions::Invalid>

Subclass of L</Net::Stomp::Producer::Exceptions::BadMessage>;
attributes: C<transformer>, C<reason>.

Thrown when validation fails.

=item C<Net::Stomp::Producer::Exceptions::Transactional>

Attributes: C<stack_trace>.

Thrown when you call
L<txn_commit|Net::Stomp::Producer::Transactional/txn_commit> or
L<txn_rollback|Net::Stomp::Producer::Transactional/txn_rollback> without a
corresponding L<txn_begin|Net::Stomp::Producer::Transactional/txn_begin>.
See L<Net::Stomp::Producer::Transactional> for details.

=back

=cut

{
package Net::Stomp::Producer::Exceptions::StackTrace;
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

{
package Net::Stomp::Producer::Exceptions::BadMessage;
use Moose;with 'Throwable',
    'Net::Stomp::MooseHelpers::Exceptions::Stringy',
    'Net::Stomp::Producer::Exceptions::StackTrace';
use namespace::autoclean;
use Data::Dump 'pp';
has message_body => ( is => 'ro', required => 1 );
has message_headers => ( is => 'ro', required => 0 );
has reason => ( is => 'ro', default => q{sending the message didn't work} );
has '+previous_exception' => ( init_arg => 'previous_exception' );

sub as_string {
    my ($self) = @_;
    sprintf "%s (%s): %s\n%s",
        $self->reason,pp($self->message_body),
        $self->previous_exception||'no previous exception',
        $self->stack_trace->as_string;
}
__PACKAGE__->meta->make_immutable(inline_constructor=>0);
}

{
package Net::Stomp::Producer::Exceptions::CantSerialize;
use Moose;extends 'Net::Stomp::Producer::Exceptions::BadMessage';
has '+reason' => ( default => q{couldn't serialize message} );
__PACKAGE__->meta->make_immutable(inline_constructor=>0);
}

{
package Net::Stomp::Producer::Exceptions::BadTransformer;
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
__PACKAGE__->meta->make_immutable(inline_constructor=>0);
}

{
package Net::Stomp::Producer::Exceptions::BadMethod;
use Moose;with 'Throwable',
    'Net::Stomp::MooseHelpers::Exceptions::Stringy',
    'Net::Stomp::Producer::Exceptions::StackTrace';
use namespace::autoclean;
has sending_method_value => ( is => 'ro', required => 1 );
has method_to_call => ( is => 'ro', required => 1 );

sub as_string {
    my ($self) = @_;
    sprintf qq{%s is not a valid sending method, the connection object does not have a %s method\n%s},
        $self->sending_method_value,$self->method_to_call,
        $self->stack_trace->as_string;
}
__PACKAGE__->meta->make_immutable(inline_constructor=>0);
}

{
package Net::Stomp::Producer::Exceptions::Invalid;
use Moose;extends 'Net::Stomp::Producer::Exceptions::BadMessage';
use Data::Dump 'pp';
use namespace::autoclean;
has transformer => ( is => 'ro', required => 1 );
has reason => ( is => 'ro', default => q{the message didn't pass validation} );

sub as_string {
    my ($self) = @_;
    sprintf "%s (%s): %s\n%s",
        $self->reason,pp($self->message_body),$self->previous_exception,
        $self->stack_trace->as_string;
}
__PACKAGE__->meta->make_immutable(inline_constructor=>0);
}

{
package Net::Stomp::Producer::Exceptions::Transactional;
use Moose;with 'Throwable',
    'Net::Stomp::MooseHelpers::Exceptions::Stringy',
    'Net::Stomp::Producer::Exceptions::StackTrace';
use namespace::autoclean;

sub as_string {
    my ($self) = @_;
    sprintf qq{not inside a transaction\n%s},
        $self->stack_trace->as_string;
}
__PACKAGE__->meta->make_immutable(inline_constructor=>0);
}

1;
