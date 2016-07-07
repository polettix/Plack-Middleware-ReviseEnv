package Plack::Middleware::MangleEnv;

use strict;
use warnings;
use Carp qw< confess >;
use English qw< -no_match_vars >;
{ our $VERSION = '0.01'; }

use parent 'Plack::Middleware';

sub call {
   my ($self, $env) = @_;
   my $mangle = $self->{mangle};
 VAR:
   for my $key (keys %$mangle) {
      my $value = $mangle->{$key};
      if ($value->{remove}) {
         delete $env->{$key};
         next VAR;
      }
      elsif (exists($env->{$key}) && !$value->{override}) {
         next VAR;
      }

      # here, we have to compute a value and set it in $env
      if (exists $value->{value}) {    # set unconditionally
         $env->{$key} = $value->{value};
      }
      elsif (exists $value->{env}) {    # copy from other item in $env
         $env->{$key} = $env->{$value->{env}};
      }
      elsif (exists $value->{ENV}) {    # copy from %ENV
         $env->{$key} = $ENV{$value->{ENV}};
      }
      elsif (exists $value->{sub}) {
         defined(my $retval = $value->{sub}->($env->{$key}, $env, $key))
           or next VAR;
         $retval = [ $retval ] unless ref($retval);
         confess "sub for '$key' returned an invalid value"
           unless ref($retval) eq 'ARRAY';
         if (@$retval == 0) {
            delete $env->{$key};
         }
         elsif (@$retval == 1) {
            $env->{$key} = $retval->[0];
         }
         else {
            confess "too many return values from sub for '$key'";
         }
      } ## end elsif (exists $value->{sub...})
      else {
         require Data::Dumper;
         my $package = ref $self;
         confess "BUG in $package, value for '$key' not as expected: ",
           Data::Dumper::Dumper($value);
      } ## end else [ if (exists $value->{value...})]
   } ## end VAR: for my $key (keys %$mangle)

   return $self->app()->($env);
} ## end sub call

sub prepare_app {
   my ($self) = @_;
   my %input = %$self;
   my $app    = delete $input{app};
   my $mangle = delete $input{mangle};
   %input = (%$self, %$mangle) if $mangle;

   $mangle = {};
   %$self = (app => $app, mangle => $mangle);

 VAR:
   while (my ($key, $value) = each %input) {
      my $ref = ref $value;
      if (!$ref) {
         $mangle->{$key} = {value => $value, override => 1};
      }
      elsif ($ref eq 'ARRAY') {
         if (@$value == 0) {
            $mangle->{$key} = {remove => 1};
         }
         elsif (@$value == 1) {
            $mangle->{$key} = {value => $value->[0], override => 1};
         }
         else {
            confess "array for '$key' has more than one value";
         }
      } ## end elsif ($ref eq 'ARRAY')
      elsif ($ref eq 'CODE') {
         $mangle->{$key} = {sub => $value, override => 1};
      }
      elsif ($ref eq 'HASH') {
         if (delete($value->{remove})) {
            confess "remove MUST be alone when set to true"
              if keys(%$value) > 1;
            $mangle->{$key} = {remove => 1};
            next VAR;
         } ## end if (delete($value->{remove...}))

         my @allowed = qw< env ENV sub value >;
         my %v = map { $_ => delete($value->{$_}) }
           grep { exists $value->{$_} } @allowed;
         if (keys(%v) != 1) {
            local $" = "', '";
            confess "one in ('@allowed') MUST be provided"
              unless keys(%v);
            confess "only one in ('@allowed') is allowed";
         } ## end if (keys(%v) != 1)

         my $override =
           exists($value->{override}) ? delete($value->{override}) : 1;

         if (my @residual = keys %$value) {
            local $" = "', '";
            confess "unknown keys ('@residual') in '$key'";
         }

         if (exists($v{sub})) {
            my $sr = ref $v{sub};
            if ($sr eq 'CODE') {    # keep it as it is
               $value->{sub} = $v{sub};
            }
            elsif (!$sr) {          # string of text, eval it
               $value->{sub} = eval $v{sub};
               if (ref($value->{sub}) ne 'CODE') {
                  my $error = $EVAL_ERROR || 'uknown error';
                  confess "error in sub for '$key': $error";
               }
            } ## end elsif (!$sr)
            elsif ($sr eq 'ARRAY') {
               my ($factory, @params) = @{$v{sub}};
               $factory = ref_to($factory, ref($self));
               confess "invalid factory for '$key'"
                 unless ref($factory) eq 'CODE';
               $value->{sub} = $factory->(@params);
               confess "invalid generated sub for '$key'"
                 unless ref($value->{sub}) eq 'CODE';
            } ## end elsif ($sr eq 'ARRAY')
         } ## end if (exists($v{sub}))
         else {
            %$value = %v;    # just keep what was available
         }
         $value->{override} = $override;
         $mangle->{$key} = $value;    # probably paranoid
      } ## end elsif ($ref eq 'HASH')
      else {
         confess "invalid reference '$ref' for '$key'";
      }
   } ## end VAR: while (my ($key, $value) ...)

   return $self;
} ## end sub prepare_app

sub ref_to {
   my ($target,  $default_package) = @_;
   my ($package, $name)            = $target =~ m{\A (.*) :: (.*)\z}mxs;
   if (defined $package) {
      (my $path = $package . '.pm') =~ s{::}{/}gmxs;
      require $path;
   }
   else {
      $package = defined($default_package) ? $default_package : 'CORE';
      $name = $target;
   }
   return $package->can($name);
} ## end sub ref_to

1;
__END__
