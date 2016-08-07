package Plack::Middleware::MangleEnv;

use strict;
use warnings;
use Carp qw< confess >;
use English qw< -no_match_vars >;
{ our $VERSION = '0.001'; }

use parent 'Plack::Middleware';

# Note: manglers in "manglers" here are totally reconstructured and not
# necessarily straightly coming from the "mangle" field in the original
sub call {
   my ($self, $env) = @_;
 VAR:
   for my $mangler (@{$self->{_manglers}}) {
      my ($key, $value) = @$mangler;
      if ($value->{remove}) {
         delete $env->{$key};
      }
      elsif (exists($env->{$key}) && (!$value->{override})) {

         # $env->{$key} is already OK here, do nothing!
      }
      elsif (exists $value->{value}) {    # set unconditionally
         $env->{$key} = $value->{value};
      }
      elsif (exists $value->{env}) {      # copy from other item in $env
         $env->{$key} = $env->{$value->{env}};
      }
      elsif (exists $value->{ENV}) {      # copy from %ENV
         $env->{$key} = $ENV{$value->{ENV}};
      }
      elsif (exists $value->{wrapsub}) {
         $value->{wrapsub}->($env->{$key}, $env, $key);
      }
      else {
         require Data::Dumper;
         my $package = ref $self;
         confess "BUG in $package, value for '$key' not as expected: ",
           Data::Dumper::Dumper($value);
      } ## end else [ if ($value->{remove}) ]
   } ## end VAR: for my $mangler (@{$self...})

   return $self->app()->($env);
} ## end sub call

# Initialization code, this is executed once at application startup
# so we are more relaxed about *not* calling too many subs
sub prepare_app {
   my ($self) = @_;
   $self->_normalize_internal_structure();    # reorganize internally
   $self->{_manglers} = \my @manglers;    # where "real" manglers will be
   my @inputs = @{$self->{mangle}};       # we will consume @inputs

   while (@inputs) {
      my ($key, $value) = splice @inputs, 0, 2;
      my $ref = ref $value;
      if (!$ref) {    # simple case, that's the value we want, full stop
         push @manglers, [$key, {value => $value, override => 1}];
      }
      elsif ($ref eq 'ARRAY') {
         $self->_add_array_mangler($key, $value, 1);
      }
      elsif ($ref eq 'CODE') {
         $self->_add_wrapsub_mangler($key, $value, 1);
      }
      elsif ($ref eq 'HASH') {
         $self->_add_hash_mangler($key, $value, 1);
      }
      else {
         confess "invalid reference '$ref' for '$key'";
      }
   } ## end while (@inputs)

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

# _PRIVATE METHODS_

sub _normalize_internal_structure {
   my ($self) = @_;
   if (exists $self->{mangle}) {
      my $mangle = $self->{mangle};
      local $" = "', '";
      confess "'mangle' MUST point to an array reference"
        unless ref($mangle) eq 'ARRAY';
      confess "'mangle' array MUST contain an even number of items"
        if @$mangle % 2;
      my @keys = keys %$self;
      confess "'mangle' MUST be standalone when present (found: '@keys')"
        if grep { ($_ ne 'app') && ($_ ne 'mangle') } @keys;
   } ## end if (exists $self->{mangle...})
   else {    # anything except app goes into mangle
      my $app = delete $self->{app};    # temporarily remove it
      %$self = (
         app    => $app,                # put it back
         mangle => [%$self],            # with rest as manglers
      );
   } ## end else [ if (exists $self->{mangle...})]
   return $self;
} ## end sub _normalize_internal_structure

sub _add_array_mangler {
   my ($self, $key, $aref, $override) = @_;
   my $manglers = $self->{_manglers};
   if (@$aref == 0) {
      push @$manglers, [$key => {remove => 1}];
   }
   elsif (@$aref == 1) {
      push @$manglers,
        [$key => {value => $aref->[0], override => $override}];
   }
   else {
      confess "array for '$key' has more than one value (@$aref)";
   }
   return;
} ## end sub _add_array_mangler

sub __wrapsub_mangler {
   my ($sub) = @_;
   return sub {
      my ($value, $env, $key) = @_;
      defined(my $retval = $sub->($value, $env, $key)) or return;
      $retval = [$retval] unless ref($retval);

      confess "sub for '$key' returned an invalid value"
        unless ref($retval) eq 'ARRAY';

      my $n = scalar @$retval;
      confess "too many return values (@$retval) from sub for '$key'"
        if $n > 1;

      $env->{$key} = $retval->[0] if $n;
      delete $env->{$key} unless $n;
      return;
   };
} ## end sub __wrapsub_mangler

sub _add_wrapsub_mangler {
   my ($self, $key, $sub, $override) = @_;
   push @{$self->{_manglers}},
     [
      $key => {
         wrapsub  => __wrapsub_mangler($sub),
         override => $override,
      }
     ];
   return;
} ## end sub _add_wrapsub_mangler

sub __exactly_one_key_among {
   my ($hash, @keys) = @_;
   my @found = grep { exists $hash->{$_} } @keys;
   return $found[0] if @found == 1;

   local $" = "', '";
   confess scalar(@found)
     ? "one in ('@keys') MUST be provided, none found"
     : "only one in ('@keys') is allowed, found ('@found')";
} ## end sub __exactly_one_key_among

sub _add_remover {
   my ($self, $key, $hash) = @_;
   if ($hash && (my @keys = keys(%$hash))) {
      local $" = "', '";
      confess "remove MUST be alone when set to true, found ('@keys')";
   }
   push @{$self->{_manglers}}, [$key, {remove => 1}];
   return;
} ## end sub _add_remover

sub __sub_from_eval {
   my ($key, $value) = @_;
   my $retval = eval $value;
   return $retval if ref($retval) eq 'CODE';

   my $error = $EVAL_ERROR || 'uknown error';
   confess "error in sub for '$key': $error, with definition:\n$value";
} ## end sub __sub_from_eval

sub __sub_from_factory {
   my ($key, $default_package, $factory, @params) = @_;

   my $factory_sub = ref_to($factory, $default_package);
   confess "invalid factory '$factory' for '$key'"
     unless ref($factory_sub) eq 'CODE';

   my $retval = $factory_sub->(@params);
   if (ref($retval) ne 'CODE') {
      local $" = "', '";
      confess "invalid sub for '$key' ('$factory' with ('@params'))";
   }

   return $retval;
} ## end sub __sub_from_factory

sub _generate_sub {
   my ($self, $key, $spec) = @_;

   my $sr = ref $spec;
   return $spec if $sr eq 'CODE';
   return __sub_from_eval($key, $spec) unless $sr;
   return __sub_from_factory($key, ref($self), @$spec) if $sr eq 'ARRAY';

   confess "invalid type for sub: $sr";
} ## end sub _generate_sub

sub _add_hash_mangler {
   my ($self, $key, $hash, $default_override) = @_;
   my $manglers = $self->{_manglers};

   return $self->_add_remover($key, $hash) if delete $hash->{remove};

   my $type = __exactly_one_key_among($hash, qw< env ENV sub value >);
   my $value = delete $hash->{$type};

   my $override =
     exists($hash->{override})
     ? delete($hash->{override})
     : $default_override;

   if (my @residual = keys %$hash) {
      local $" = "', '";
      confess "unknown keys ('@residual') in '$key'";
   }

   # subs must be generated and wrapped
   ($type, $value) =
     (wrapsub => __wrapsub_mangler($self->_generate_sub($key, $value)))
     if $type eq 'sub';

   push @$manglers, [$key => {$type => $value, override => $override}];
   return;
} ## end sub _add_hash_mangler

1;
__END__
