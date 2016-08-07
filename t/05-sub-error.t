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

throws_ok { wrap_app($app, 'sub { whatever }') }
qr{(?ms:sub for 'WHATEVER' is not a CODE reference)},
  "complains on non-reference sub specification";

throws_ok { wrap_app($app, []) }
qr{(?ms:sub for 'WHATEVER' is not a CODE reference)},
  "complains on ARRAY reference sub specification";

lives_ok {
   wrap_app($app, sub { });
}
"fine on CODE sub";

done_testing();

sub wrap_app {
   my ($app, $candidate) = @_;
   builder {
      enable 'MangleEnv', WHATEVER => {sub => $candidate};
      $app;
   };
} ## end sub wrap_app
