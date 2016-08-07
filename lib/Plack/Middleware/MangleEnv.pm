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
   $self->_normalize_input_structure();    # reorganize internally
   $self->{_manglers} = \my @manglers;    # where "real" manglers will be
   my @inputs = @{$self->{manglers}};       # we will consume @inputs

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

# _PRIVATE METHODS_

sub _normalize_input_structure {
   my ($self) = @_;
   if (exists $self->{manglers}) {
      local $" = "', '";
      my $mangle = $self->{manglers};
      $mangle = $self->{manglers} = [ %$mangle ] if ref($mangle) eq 'HASH';
      confess "'mangle' MUST point to an array or hash reference"
        unless ref($mangle) eq 'ARRAY';
      confess "'mangle' array MUST contain an even number of items"
        if @$mangle % 2;
      my @keys = keys %$self;
      confess "'mangle' MUST be standalone when present (found: '@keys')"
        if grep { ($_ ne 'app') && ($_ ne 'manglers') } @keys;
   } ## end if (exists $self->{mangle...})
   else {    # anything except app goes into mangle
      my $app = delete $self->{app};    # temporarily remove it
      %$self = (
         app      => $app,                # put it back
         manglers => [%$self],            # with rest as manglers
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

   if ($type eq 'sub') {
      confess "sub for '$key' is not a CODE reference"
        unless ref($value) eq 'CODE';
      $type = 'wrapsub';
      $value = __wrapsub_mangler($value);
   }

   push @$manglers, [$key => {$type => $value, override => $override}];
   return;
} ## end sub _add_hash_mangler

1;
__END__
