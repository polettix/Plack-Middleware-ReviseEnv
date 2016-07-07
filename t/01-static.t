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
   enable 'MangleEnv',
     test_var_name   => 'a simple, overriding value',
     test_some_value => [{ENV => 'ever'}],

     test_alternative => {value => {env => 'REMOTE_ADDR'}},
     test_from_ENV    => {ENV   => 'WHATEVER'},
     test_from_env    => {env   => 'REQUEST_METHOD'},

     test_alternativex => {value => {env => 'REMOTE_ADDR'}, override => 0},
     test_from_ENVx => {ENV => 'WHATEVER',       override => 0},
     test_from_envx => {env => 'REQUEST_METHOD', override => 0},

     test_delete_pliz => [],
     test_delete_me   => {remove => 1},

     'psgi.url_scheme' => 'https',
     ;
   $app;
};

{
   my $oa = $app;
   $app = sub {
      my $env = shift;
      $env->{test_delete_pliz}  = 'I will not survive';
      $env->{test_delete_me}    = 'I will not survive';
      $env->{test_alternativex} = 'I will survive';
      $env->{test_from_ENVx}    = 'I will survive';
      $env->{test_from_env}     = 'I will be overridden';
      $env->{test_from_ENV}     = 'I will be overridden';
      return $oa->($env);
     }
}

test_psgi $app, sub {
   my $cb = shift;

   local $ENV{WHATEVER} = 'here I am';
   my $res = $cb->(GET "/path/to/somewhere/else");
   is $res->content, "Hello World!", 'sample content';

   is $last_env->{'psgi.url_scheme'}, 'https', 'psgi variable overridden';

   my %vars = map { $_ => $last_env->{$_} }
     grep { /^test_/ }
     keys %$last_env;
   is_deeply \%vars,
     {
      'test_alternative'  => {'env' => 'REMOTE_ADDR'},
      'test_alternativex' => 'I will survive',
      'test_from_ENV'     => 'here I am',
      'test_from_ENVx'    => 'I will survive',
      'test_from_env'     => 'GET',
      'test_from_envx'    => 'GET',
      'test_some_value'   => {'ENV' => 'ever'},
      'test_var_name'     => 'a simple, overriding value'
     },
     'other mangled variables as expected';
};

done_testing();
