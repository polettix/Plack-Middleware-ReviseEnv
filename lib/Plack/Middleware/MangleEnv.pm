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
      elsif (exists $value->{sub}) {
         $value->{sub}->($env->{$key}, $env, $key);
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
   return $self->generate_immediate_manglers(value => @_) unless $ref;
   return $self->generate_array_manglers(@_) if $ref eq 'ARRAY';
   return $self->generate_hash_manglers(@_)  if $ref eq 'HASH';
   return $self->generate_code_manglers(@_)  if $ref eq 'CODE';

   confess "invalid reference '$ref' for '$key'";
} ## end sub generate_manglers

sub generate_immediate_manglers {
   my ($self, $type, $key, $value, $opts) = @_;
   return [$key => {%$opts, $type => $value}];
}

sub generate_array_manglers {
   my ($self, $key, $aref, $defaults) = @_;
   return $self->generate_remove_manglers($key, undef, $defaults)
     if @$aref == 0;
   return $self->generate_immediate_manglers(value => $key, $aref->[0], $defaults)
      if @$aref == 1;

   my @values = $self->stringified_list(@$aref);
   confess "array for '$key' has more than one value (@values)";
}

sub generate_code_manglers {
   my ($self, $key, $sub, $opts) = @_;
   $sub = $self->wrap_code($sub)
     or confess "sub for '$key' is not a CODE reference";
   return $self->generate_immediate_manglers(sub => $key, $sub, $opts);
}

sub generate_hash_manglers {
   my ($self, $key, $hash, $defaults) = @_;

   my %opt = %$defaults;
   $opt{override} = delete($hash->{override}) if exists($hash->{override});

   if ((my @keys = keys %$hash) > 1) {
      @keys = $self->stringified_list(@keys);
      confess "too many options ('@keys') for '$key'";
   }

   my ($type, $value) = %$hash;
   my $cb = $self->can('generate_hash_manglers_' . $type)
     or confess "unknown option '$type' for '$key'";

   return $cb->($self, $key, $value, \%opt);
}

sub generate_hash_manglers_ENV {
   my $self = shift;
   return $self->generate_immediate_manglers(ENV => @_);
}

sub generate_hash_manglers_env {
   my $self = shift;
   return $self->generate_immediate_manglers(env => @_);
}

sub get_values_from_source {
   my ($self, $env, $source) = @_;

   # get right start value
   my ($type, $sel) = @{$source}{qw< type value >};
   my $svalue = ($type eq 'env') ? $env->{$sel}
      : ($type eq 'ENV') ? $ENV{$sel}
      : $sel;

   # flatten if requested and possible
   my @values = ($svalue);
   if ($source->{flatten}) {
      if (ref($svalue) eq 'ARRAY') {
         @values = @$svalue;
      }
      elsif (ref($svalue) eq 'HASH') {
         @values = %$svalue;
      }
   }

   # handle undefined values
   my $default = $source->{default};
   my $doe = $source->{default_on_empty};
   @values = map {
      (! defined($_))            ? @$default
      : ($doe && (! length($_))) ? @$default
      :                            $_;
   } @values;

   # filter stuff out
   my $remove_if = $source->{remove_if};
   my @retval = grep { ref($_) || (! $remove_if->{$_}) } @values;
   return unless @retval;

   return @retval;
}

sub normalize_source {
   my ($self, $source, $defaults) = @_;
   my %src;
   for my $feature (qw< remove_if default default_on_empty flatten >) {
      $src{$feature} = exists($source->{$feature})
         ? delete($source->{$feature}) : $defaults->{$feature};
   }
   $src{remove_if} = { map { $_ => 1 } @{$src{remove_if}} };
   $src{default} = [$src{default}] unless ref($src{default}) eq 'ARRAY';
   confess "too many elements in default for list"
      if @{$src{default}} > 1;
   confess "too many options in list" if keys(%$source) > 1;
   confess "nothing to take from in list" if keys(%$source) < 1;
   ($src{type}, $src{value}) = %$source;
   confess "unknown source '$src{type}' in list"
      unless grep {$_ eq $src{type}} qw< env ENV value >;
   return \%src;
}

sub generate_hash_manglers_list {
   my ($self, $key, $cfg, $opts) = @_;
   $cfg->{remove_if} ||= [];
   $cfg->{default} ||= [];
   $cfg->{default_on_empty} ||= 0;
   $cfg->{flatten} ||= 0;

   my $count = 0;
   for my $feature (qw< join sprintf >) {
      defined(my $v = $cfg->{$feature}) or next;
      confess "cannot specify both join and sprintf for '$key'"
        if ++$count > 1;
      $v = {value => $v} unless ref $v;
      $cfg->{$feature} = $self->normalize_source($v, {%$opts, $feature => undef});
   }
   my ($join, $sprintf) = @{$cfg}{qw< join sprintf >};

   my @sources = map {
      $self->normalize_source($_, $cfg);
   } @{$cfg->{sources}};

   my $sub = sub {
      my ($value, $env, $key) = @_;
      my @retval;
      for my $source (@sources) {
         push @retval, $self->get_values_from_source($env, $source);
      }

      if (defined $join) {
         my ($joinstr) = $self->get_values_from_source($env, $join);
         $env->{$key} = join $joinstr, @retval;
      }
      elsif (defined $sprintf) {
         my ($sprintfstr) = $self->get_values_from_source($env, $sprintf);
         $env->{$key} = sprintf $sprintfstr, @retval;
      }
      else {
         $env->{$key} = \@retval;
      }
   };
   return $self->generate_immediate_manglers(sub => $key, $sub, $opts);
}

*generate_hash_manglers_remove = \&generate_remove_manglers;
*generate_hash_manglers_sub    = \&generate_code_manglers;

sub generate_hash_manglers_value {
   my $self = shift;
   return $self->generate_immediate_manglers(value => @_);
}

sub generate_remove_manglers {
   my ($self, $key, $value, $defaults) = @_;
   if ((ref($value) eq 'HASH') && (my @keys = keys(%$value))) {
      @keys = $self->stringified_list(@keys);
      confess "remove MUST be alone when set to true, found (@keys)";
   }
   return $self->generate_immediate_manglers(remove => $key, 1, {});
}

sub wrap_code {
   my ($self, $sub) = @_;
   return unless ref($sub) eq 'CODE';
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
