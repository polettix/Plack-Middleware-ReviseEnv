use strict;
use Path::Tiny;
use lib path(__FILE__)->parent()->stringify();
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
   enable 'MangleEnv', 'psgi.url_scheme' => sub {
      my $env = $_[1];
      my ($scheme) = $env->{test_base} =~ m{\A(\w+)://}mxs;
      return $scheme;
     },
     what => {
      sub => sub { return 'ever' }
     },
     ever => {sub => 'sub {return uc(shift)}'},
     ohmy => {sub => ['TestPackage::factory']},
     omg  => {sub => [ref_to => 'TestPackage::mangler']},
     rogue => sub {
      $_[1]->{side} = 'effect';
      return;
     };
   $app;
};

{
   my $oa = $app;
   $app = sub {
      my $env = shift;
      $env->{test_base} = 'HTTPS://what.ever/';
      $env->{ever}      = 'what?';
      return $oa->($env);
     }
}

test_psgi $app, sub {
   my $cb = shift;

   local $ENV{WHATEVER} = 'here I am';
   my $res = $cb->(GET "/path/to/somewhere/else");
   is $res->content, "Hello World!", 'sample content';

   is $last_env->{'psgi.url_scheme'}, 'HTTPS', 'psgi variable overridden';
   is $last_env->{what}, 'ever',   'other variable set';
   is $last_env->{ever}, 'WHAT?',  'variable mangled from eval-ed sub';
   is $last_env->{side}, 'effect', 'variable set from side effect';
   is $last_env->{ohmy}, 'works!', 'variable set from sub (factory)';
   is $last_env->{omg},  'works!', 'variable set from sub (ref_to)';
   ok !exists($last_env->{rogue}), 'undef return value does not set';
};

done_testing();
