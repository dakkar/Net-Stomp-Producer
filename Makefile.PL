
use strict;
use warnings;



use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "helper object to send messages via Net::Stomp",
  "AUTHOR" => "Gianni Ceccarelli <gianni.ceccarelli\@net-a-porter.com>",
  "BUILD_REQUIRES" => {
    "Data::Printer" => 0,
    "JSON::XS" => 0,
    "Net::Stomp::Frame" => 0,
    "Test::Deep" => 0,
    "Test::Fatal" => 0,
    "Test::More" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Net-Stomp-Producer",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "Net::Stomp::Producer",
  "PREREQ_PM" => {
    "Class::Load" => 0,
    "Data::Dump" => 0,
    "Moose" => 0,
    "Moose::Role" => 0,
    "MooseX::Types::Moose" => 0,
    "Net::Stomp::MooseHelpers::CanConnect" => "1.1",
    "Net::Stomp::MooseHelpers::Exceptions" => 0,
    "Net::Stomp::MooseHelpers::ReconnectOnFailure" => 0,
    "StackTrace::Auto" => 0,
    "Throwable" => 0,
    "Try::Tiny" => 0,
    "bytes" => 0,
    "namespace::autoclean" => 0
  },
  "VERSION" => "1.3",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



