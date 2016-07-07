use strict;
use Test::More tests => 1;
use Plack::Middleware::MangleEnv;

(my $filename = $INC{'Plack/Middleware/MangleEnv.pm'}) =~
  s{pm$}{pod};

my $pod_version;

{
   open my $fh, '<', $filename
     or BAIL_OUT "can't open '$filename'";
   binmode $fh, ':raw';
   local $/;
   my $module_text = <$fh>;
   ($pod_version) = $module_text =~ m{
      ^This\ document\ describes\ Plack::Middleware::MangleEnv\ version\ (.*?)\.$
   }mxs;
}

is $pod_version, $Plack::Middleware::MangleEnv::VERSION,
  'version in POD';
