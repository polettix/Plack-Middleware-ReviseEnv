use strict;
use Path::Tiny;
use lib path(__FILE__)->parent()->stringify();
use Test::More;
use Plack::Test;
use Plack::Builder;
use HTTP::Request::Common;
use Test::Exception;

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

# We'll be doing Monkey-Patching, so we load the module now
use Plack::Middleware::MangleEnv;
my $false_sub = sub { return 0 };
my $true_sub  = sub { return 1 };

my @specs = (
   {
      name => 'default (both disabled)',
      setup => sub { },                # nothing, take defaults
      fails => [qw< EVAL FACTORY >],
   },
   {
      name => 'FACTORY only enabled',
      setup => sub {
         *Plack::Middleware::MangleEnv::ALLOW_EVAL = $false_sub;
         *Plack::Middleware::MangleEnv::ALLOW_FACTORY = $true_sub;
      },
      fails => [qw< EVAL >],
   },
   {
      name => 'EVAL only enabled',
      setup => sub {
         *Plack::Middleware::MangleEnv::ALLOW_EVAL = $true_sub;
         *Plack::Middleware::MangleEnv::ALLOW_FACTORY = $false_sub;
      },
      fails => [qw< FACTORY >],
   },
   {
      name => 'both enabled',
      setup => sub {
         *Plack::Middleware::MangleEnv::ALLOW_EVAL = $true_sub;
         *Plack::Middleware::MangleEnv::ALLOW_FACTORY = $true_sub;
      },
      fails => [qw<>],
   },
   {
      name => 'both disabled',
      setup => sub {
         *Plack::Middleware::MangleEnv::ALLOW_EVAL = $false_sub;
         *Plack::Middleware::MangleEnv::ALLOW_FACTORY = $false_sub;
      },
      fails => [qw< EVAL FACTORY >],
   },
);

for my $spec (@specs) {
   my ($name, $setup, $failures) = @{$spec}{qw< name setup fails >};
   $setup->();
   my %failure_for = map { $_ => 1 } @$failures;
   my %flag;
   for my $eval (0, 1) {
      $flag{EVAL} = $eval;
      for my $factory (0, 1) {
         $flag{FACTORY} = $factory;
         my $fails =
           grep { $flag{$_} && $failure_for{$_} } qw< EVAL FACTORY >;
         my @triggered = sort grep { $flag{$_} } qw< EVAL FACTORY >;
         my $triggered =
           @triggered
           ? "triggered: (@triggered)"
           : 'none triggered';
         if ($fails) {
            throws_ok { wrap_app($app, $eval, $factory) }
               qr{(?mxs:invalid[ ]type[ ]for[ ]sub:)},
               "complains on $name ($triggered)";
         }
         else {
            lives_ok { wrap_app($app, $eval, $factory) }
            "fine on $name ($triggered)";
         }
      } ## end for my $factory (0, 1)
   } ## end for my $eval (0, 1)

} ## end for my $spec (@specs)

done_testing();

sub wrap_app {
   my ($app, $include_eval, $include_factory) = @_;
   $include_eval    = 1 unless defined $include_eval;
   $include_factory = 1 unless defined $include_factory;

   builder {
      my @params = (
         'psgi.url_scheme' => sub {
            my $env = $_[1];
            my ($scheme) = $env->{test_base} =~ m{\A(\w+)://}mxs;
            return $scheme;
         },
         what => {
            sub => sub { return 'ever' }
         },
         rogue => sub { $_[1]->{side} = 'effect'; return; },
      );
      push @params, ever => {sub => 'sub {return uc(shift)}'}
        if $include_eval;
      push @params,
        ohmy => {sub => ['TestPackage::factory']},
        omg  => {sub => [ref_to => 'TestPackage::mangler']}
        if $include_factory;

      enable 'MangleEnv', @params;
      $app;
   };
} ## end sub wrap_app
