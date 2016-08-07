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
     manglers => [
      straight       => 'hello',
      straight_array => [[1 .. 3, undef, '']],
      my_list        => {
         list => {
            flatten          => 1,
            default_on_empty => 1,
            sources          => [
               {value => 'direct'},
               {env   => 'from_env'},
               {ENV   => 'WHATEVER'},
               {env   => 'straight_array'},
               {env   => 'inexistent'},
               {env   => 'array_from_env'},
            ],
         }
      },
      my_string => {
         list => {
            flatten => 1,
            join    => {value => ':'},
            sources => [{env => 'my_list'}]
         },
      },
      connect_string => {
         list => {
            join    => ':',
            sources => [
               {ENV => 'HOST'},
               {ENV => 'PORT', default => 80},
               {ENV => 'INEXISTENT'},
            ],
         },
      },
     ];
   $app;
};

{
   my $oa = $app;
   $app = sub {
      my $env = shift;
      $env->{from_env}       = 'I will not survive';
      $env->{array_from_env} = [qw< what ever >];
      return $oa->($env);
   };
}

test_psgi $app, sub {
   my $cb = shift;

   local $ENV{WHATEVER} = 'here I am';
   local $ENV{HOST}     = 'localhost';
   my $res = $cb->(GET "/path/to/somewhere/else");
   is $res->content, "Hello World!", 'sample content';

   my @list =
     ('direct', 'I will not survive', 'here I am', 1, 2, 3, qw<what ever>);
   is_deeply $last_env->{my_list}, \@list, 'list variable built';

   my $string = join ':', @list;
   is $last_env->{my_string}, $string, 'joint variable from list n.1';
   is $last_env->{connect_string}, 'localhost:80',
     'joint variable from list n.2';
};

done_testing();
