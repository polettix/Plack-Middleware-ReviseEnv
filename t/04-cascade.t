use strict;
use Test::More;
use Plack::Test;
use Plack::Builder;
use HTTP::Request::Common;

my $last_env;

my $app = sub {
   $last_env = shift;
   return [
      200,
      [
         'Content-Type'   => 'text/plain',
         'Content-Length' => 12
      ],
      ['Hello World!']
   ];
};

$app = builder {
   enable 'MangleEnv', manglers => [
      splitted => sub {
         my $env = $_[1];
         return [[split /,/, $env->{input}]];
      },
      first_previous => {env => 'first'},
      first          => sub  { $_[1]{splitted}[0] },
      second         => sub  { $_[1]{splitted}[1] },
      first_again    => {env => 'first'},
      third          => sub  { $_[1]{splitted}[2] },
      splitted       => [],  # get rid of it
   ];
   $app;
};

{
   my $oa = $app;
   $app = sub {
      my $env = shift;
      $env->{first} = 'this was before';
      $env->{input} = 'FIRST,SECOND,THIRD';
      return $oa->($env);
   };
}

test_psgi $app, sub {
   my $cb = shift;

   local $ENV{WHATEVER} = 'here I am';
   my $res = $cb->(GET "/path/to/somewhere/else");
   is $res->content, "Hello World!", 'sample content';

   ok !exists($last_env->{splitted}), 'splitted was deleted eventually';

   my %vars =
     map { $_ => $last_env->{$_} }
     qw< first second third first_again first_previous >;
   is_deeply \%vars,
     {
      first          => 'FIRST',
      first_again    => 'FIRST',
      first_previous => 'this was before',
      second         => 'SECOND',
      third          => 'THIRD',
     },
     'other mangled variables as expected';
};

done_testing();
