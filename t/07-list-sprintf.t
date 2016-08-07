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
      connect_string => {
         list => {
            sprintf => '%s:%d',
            sources => [
               {ENV => 'HOST'},
               {ENV => 'PORT', default => 80},
            ],
         },
      },
     ];
   $app;
};

test_psgi $app, sub {
   my $cb = shift;

   local $ENV{HOST}     = 'localhost';
   my $res = $cb->(GET "/path/to/somewhere/else");
   is $res->content, "Hello World!", 'sample content';

   is $last_env->{connect_string}, 'localhost:80', 'sprintf in list';
};

done_testing();
