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
   my @inputs = @{$self->{manglers}};      # we will consume @inputs
   $self->{_manglers} = [];

   while (@inputs) {
      my ($key, $value) = splice @inputs, 0, 2;
      $self->push_manglers(
         $self->generate_manglers($key, $value, {override => 1}));
   }

   return $self;
} ## end sub prepare_app

sub push_manglers {
   my $self = shift;
   push @{$self->{_manglers}}, @_;
   return $self;
} ## end sub push_manglers

sub generate_manglers { # simple dispatch method
   my $self = shift;
   my ($key, $value) = @_; # ignoring rest of parameters here
   my $ref  = ref $value;
   return $self->generate_value_manglers(@_) unless $ref;
   return $self->generate_array_manglers(@_) if $ref eq 'ARRAY';
   return $self->generate_hash_manglers(@_)  if $ref eq 'HASH';
   return $self->generate_code_manglers(@_)  if $ref eq 'CODE';

   confess "invalid reference '$ref' for '$key'";
} ## end sub generate_manglers

sub generate_value_manglers {
   my ($self, $key, $value, $defaults) = @_;
   return [$key => {%$defaults, value => $value}];
}

sub generate_array_manglers {
   my ($self, $key, $aref, $defaults) = @_;
   return $self->generate_remove_manglers($key, undef, $defaults)
     if @$aref == 0;
   return $self->generate_value_manglers($key, $aref->[0], $defaults)
      if @$aref == 1;

   my @values = $self->stringified_list(@$aref);
   confess "array for '$key' has more than one value (@values)";
}

sub generate_code_manglers {
   my ($self, $key, $sub, $defaults) = @_;
   $sub = $self->wrap_code($key, $sub);
   return [$key => {%$defaults, wrapsub => $sub}];
}

sub generate_hash_manglers {
   my ($self, $key, $hash, $defaults) = @_;

   return $self->generate_remove_manglers($key, $hash, $defaults)
     if delete $hash->{remove};

   my ($type, $value) = $self->_only_one($hash, qw< env ENV sub value >);

   my %opt = %$defaults;
   $opt{override} = delete($hash->{override}) if exists($hash->{override});

   if (my @residual = keys %$hash) {
      @residual = $self->stringified_list(@residual);
      confess "unknown keys ('@residual') in '$key'";
   }

   ($type, $value) = (wrapsub => $self->wrap_code($key, $value))
     if $type eq 'sub';

   return [$key => {%opt, $type => $value}];
}

sub generate_remove_manglers {
   my ($self, $key, $value, $defaults) = @_;
   if ((ref($value) eq 'HASH') && (my @keys = keys(%$value))) {
      @keys = $self->stringified_list(@keys);
      confess "remove MUST be alone when set to true, found (@keys)";
   }
   return [$key, {remove => 1}]; # ignore $defaults for now
}

sub wrap_code {
   my ($self, $key, $sub) = @_;
   confess "sub for '$key' is not a CODE reference"
     unless ref($sub) eq 'CODE';
   return sub {
      defined(my $retval = $sub->(@_)) or return;
      $retval = [$retval] unless ref($retval);

      my ($value, $env, $key) = @_;
      confess "sub for '$key' returned an invalid value"
        unless ref($retval) eq 'ARRAY';

      my $n = scalar @$retval;
      if ($n == 0) {
         delete $env->{$key};
      }
      elsif ($n == 1) {
         $env->{$key} = $retval->[0];
      }
      else {
         my @values = $self->stringified_list(@$retval);
         confess "too many return values (@values) from sub for '$key'";
      }

      return;
   };
}

sub stringified_list {
   my $self = shift;
   return map {
      if (defined(my $v = $_)) {
         $v =~ s{([\\'])}{\\$1}gmxs;
         "'$v'";
      }
      else {
         'undef';
      }
   } @_;
}

# _PRIVATE METHODS_

sub _normalize_input_structure {
   my ($self) = @_;
   if (exists $self->{manglers}) {
      local $" = "', '";
      my $mangle = $self->{manglers};
      $mangle = $self->{manglers} = [%$mangle] if ref($mangle) eq 'HASH';
      confess "'mangle' MUST point to an array or hash reference"
        unless ref($mangle) eq 'ARRAY';
      confess "'mangle' array MUST contain an even number of items"
        if @$mangle % 2;
      my @keys = keys %$self;
      confess "'mangle' MUST be standalone when present (found: '@keys')"
        if grep { ($_ ne 'app') && ($_ ne 'manglers') } @keys;
   } ## end if (exists $self->{manglers...})
   else {    # anything except app goes into mangle
      my $app = delete $self->{app};    # temporarily remove it
      %$self = (
         app      => $app,              # put it back
         manglers => [%$self],          # with rest as manglers
      );
   } ## end else [ if (exists $self->{manglers...})]
   return $self;
} ## end sub _normalize_input_structure

sub _only_one {
   my ($self, $hash, @keys) = @_;
   my @found = grep { exists $hash->{$_} } @keys;
   return ($found[0], delete($hash->{$found[0]})) if @found == 1;

   @keys = $self->stringified_list(@keys);
   @found = $self->stringified_list(@found);
   confess scalar(@found)
     ? "one in (@keys) MUST be provided, none found"
     : "only one in (@keys) is allowed, found (@found)";
} ## end sub __exactly_one_key_among

1;
__END__
