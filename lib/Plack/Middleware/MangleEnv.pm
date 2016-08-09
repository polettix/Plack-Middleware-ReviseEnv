package Plack::Middleware::MangleEnv;

use strict;
use warnings;
use Carp qw< confess >;
use English qw< -no_match_vars >;
{ our $VERSION = '0.001'; }

use parent 'Plack::Middleware';

sub call {
   my ($self, $env) = @_;
   my %vars = (env => $env, ENV => \%ENV);
 MANGLER:
   for my $mangler (@{$self->{_manglers} || []}) {
      my ($key, $value) = map {
         my $def_parts = $mangler->{$_};
         my $retval;
         if (defined $def_parts) {
            my $all_defs = 1;
            my @parts = grep { defined($_) ? 1 : ($all_defs = 0) } map {
               (!ref($_)) ? $_
                 : exists($vars{$_->{src}}{$_->{key}})
                 ? $vars{$_->{src}}{$_->{key}}
                 : undef;
            } @$def_parts;

            if ($mangler->{require_all} && (!$all_defs)) {
               $retval = undef;
            }
            else {
               $retval = join '', @parts;
            }
         } ## end if (defined $_)
         $retval = $mangler->{'default_' . $_}
            if (! defined($retval))
            || ((length($retval) == 0) && $mangler->{empty_as_default});
         $retval;
      } qw< key value >;
      $env->{$key} = $value
        if $mangler->{override} || (!exists($env->{$key}));
      delete $env->{$key} unless defined $value;
   } ## end MANGLER: for my $mangler (@{$self...})

   return $self->app()->($env);
} ## end sub call

# Initialization code, this is executed once at application startup
# so we are more relaxed about *not* calling too many subs
sub prepare_app {
   my ($self) = @_;
   $self->normalize_input_structure();    # reorganize internally
   my @inputs = @{$self->{manglers}};     # we will consume @inputs
   my @manglers;

   while (@inputs) {
      my $spec = shift @inputs;

      # allow for key => value or \%spec
      if (!ref($spec)) {
         confess "stray mangler '$spec'" unless @inputs;
         (my $key, $spec) = ($spec, shift @inputs);
         $spec = {value => $spec} unless ref($spec) eq 'HASH';

         # override key only if not already present. The external key
         # can then be used for ordering manglers also in the hash
         # scenario
         $spec->{key} = $key unless defined $spec->{key};
      } ## end if (!ref($spec))

      push @manglers, $self->generate_mangler($spec);
   } ## end while (@inputs)

   # if we arrived here, it's safe
   $self->{_manglers} = \@manglers;

   return $self;
} ## end sub prepare_app

sub generate_mangler {
   my ($self, $spec) = @_;
   confess "one spec has no (defined) key" unless defined $spec->{key};

   my $opts = $self->{opts};
   my $start = defined($spec->{start}) ? $spec->{start} : $opts->{start};
   confess "start sequence cannot be empty" unless length $start;

   my $stop = defined($spec->{stop}) ? $spec->{stop} : $opts->{stop};
   confess "stop sequence cannot be empty" unless length $stop;

   my $esc = defined($spec->{esc}) ? $spec->{esc} : $opts->{esc};
   confess "escape sequence cannot be empty" unless length $esc;
   confess "escape sequence cannot start with a space, sorry"
     if substr($esc, 0, 1) eq ' ';
   confess "escape sequence cannot be equal to start or stop sequence"
     if ($esc eq $start) || ($esc eq $stop);

   my %m = %$spec;
   $m{override} = 1 unless exists $m{override};
   $m{key}      = $self->parse_template($m{key},   $start, $stop, $esc);
   $m{value}    = $self->parse_template($m{value}, $start, $stop, $esc);

   return \%m;
} ## end sub generate_mangler

sub parse_template {
   my ($self, $template, $start, $stop, $esc) = @_;
   return undef unless defined $template;
   my $pos = 0;
   my $len = length $template;
   my @chunks;
 CHUNK:
   while ($pos < $len) {

      # find start, if any
      my $i = $self->escaped_index($template, $start, $esc, $pos);
      my $text = substr $template, $pos, ($i < 0 ? $len : $i) - $pos;
      push @chunks, $self->unescape($text, $esc);
      last CHUNK if $i < 0;    # nothing more left to search

      # advance position marker immediately after start sequence
      $pos = $i + length $start;

      # start sequence found, let's look for the stop
      $i = $self->escaped_index($template, $stop, $esc, $pos);
      confess "unclosed start sequence in '$template'" if $i < 0;

      my $chunk = substr $template, $pos, $i - $pos;

      # trim intelligently, then unescape
      $chunk = $self->unescape($self->escaped_trim($chunk, $esc), $esc);

      # get rid of quotes, if any
      if (my ($quote) = $chunk =~ m{\A(['"])}mxs) {
         my $clen = length $chunk;
         confess "chunk '$chunk' is not quoted properly"
           unless ($len > 1) && (substr($chunk, -1, 1) eq $quote);
         $chunk = substr $chunk, 1, $clen - 2;
      } ## end if (my ($quote) = $chunk...)

      my ($src, $key) = split /:/, $chunk, 2;
      confess "invalid source '$src' in chunk '$chunk'"
        if ($src ne 'env') && ($src ne 'ENV');
      confess "no key in chunk '$chunk'" unless defined $key;
      push @chunks, {src => $src, key => $key};

      # advance position marker for next iteration
      $pos = $i + length $stop;

   } ## end CHUNK: while ($pos < $len)

   return \@chunks;
} ## end sub parse_template

sub unescape {
   my ($self, $str, $esc) = @_;
   $str =~ s{\Q$esc\E(.)}{$1}gmxs;
   return $str;
}

sub escaped_trim {
   my ($self, $str, $esc) = @_;
   $str =~ s{\A\s+}{}mxs;    # trimming the initial part is easy

   my $pos = 0;
   while ('necessary') {

      # find next un-escaped space
      my $i = $self->escaped_index($str, ' ', $esc, $pos);
      last if $i < 0;        # no further spaces... nothing to trim

      # now look for escapes after that, because we're interested only
      # in un-escaped spaces at the end of $str
      my $e = index $str, $esc, $i + 1;

      if ($e < 0) {    # no escapes past last space found

         # Now we split our string at $i, which represents the first
         # space character that is not escaped and has no escapes after it.
         # The string before it MUST NOT be subject to trimming, the part
         # from $i on is safe to trim.
         my $keep = substr $str, 0, $i, '';
         $str =~ s{\s+\z}{}mxs;

         # merge the two parts back and we're good to go
         return $keep . $str;
      } ## end if ($e < 0)

      # we found an escape sequence after the last space we found, we have
      # to look further past this escape sequence
      $pos = $e + length $esc;
   } ## end while ('necessary')

   # no trailing spaces to be trimmed found, $str is fine
   return $str;
} ## end sub escaped_trim

sub escaped_index {
   my ($self, $str, $delimiter, $escaper, $pos) = @_;
   defined $escaper or confess "here";

   my $len = length $str;
   while ($pos < $len) {
      my $dpos = index $str, $delimiter, $pos;    # next delimiter
      my $epos = index $str, $escaper,   $pos;    # next escaper
      return $dpos
        if ($dpos < 0)                            # didn't find it
        || ($epos < 0)         # nothing escaped at all
        || ($dpos < $epos);    # nothing escaped before it

      # there's an escaper occurrence *before* a delimiter, so we have
      # to honor the escaping and restart the quest past the escaped char
      $pos = $epos + length($escaper) + 1;
   } ## end while ($pos < $len)

   confess "stray escaping in '$str'";
} ## end sub escaped_index

sub normalize_input_structure {
   my ($self) = @_;

   my $app = delete $self->{app};           # temporarily remove these keys
   my $opts = delete($self->{opts}) || {};
   $opts->{start} ||= '[%';
   $opts->{stop}  ||= '%]';
   $opts->{esc}   ||= '\\';

   my $manglers = exists($self->{manglers})
     ? delete($self->{manglers})            # just take it
     : __exhaust_hash($self);               # or move stuff out of $self

   # Fun fact: __exhaust_hash($self) could have been written as:
   #
   #     { (@{[]}, %$self) = %$self }
   #
   # but let's avoid being too "clever" for readability's sake...

   if (scalar keys %$self > 0) {
      my @keys = __stringified_list(keys %$self);
      confess "stray keys found: @keys";
   }

   $manglers = [map { $_ => $manglers->{$_} } sort keys %$manglers]
     if ref($manglers) eq 'HASH';

   %$self = (
      app      => $app,
      manglers => $manglers,
      opts     => $opts,
   );
   return $self;
} ## end sub normalize_input_structure

# _PRIVATE_ convenience functions

sub __stringified_list {
   return map {
      if (defined(my $v = $_)) {
         $v =~ s{([\\'])}{\\$1}gmxs;
         "'$v'";
      }
      else {
         'undef';
      }
   } @_;
} ## end sub __stringified_list

sub __exhaust_hash {
   my ($target) = @_;
   my $retval = {%$target};
   %$target = ();
   return $retval;
} ## end sub __exhaust_hash

1;
