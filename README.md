# NAME

Plack::Middleware::MangleEnv - Mangle request environment at will

# VERSION

This document describes Plack::Middleware::MangleEnv version {{\[ version
\]}}.

# SYNOPSIS

    use Plack::Middleware::MangleEnv;

    my $mw = Plack::Middleware::MangleEnv->new(

       # overriding is the default behaviour

       # straight value, must be a plain SCALAR (no refs)
       var_name    => 'a simple, overriding value',

       # any value can be wrapped, even refs
       some_value  => [ \@whatever ],

       # or you can be just explicit
       alternative => { value => $whatever },

       # you can read stuff from %ENV
       from_ENV    => { ENV => 'PLACK_ENV' },

       # or read other variables from $env
       from_env    => { env => 'psgi.url_scheme' },

       # turn override into defaulting, works with value, env and ENV
       de_fault    => { value => $something, override => 0 },

       # get rid of a variable, inconditionally. You can pass "no value"
       # or be explicit about your intent
       delete_pliz => [],
       delete_me   => { remove => 1 },

       # use subroutines for maximum flexibility.
       change_me1  => sub { ... },
       change_me2  => { sub => sub { ... } },

    );

    # you can also pass the key/value pairs as a hash reference
    # associated to a key named 'manglers'. This is necessary if you want
    # e.g. to set a variable in $env with name 'app' (or 'manglers'
    # itself)
    my $mw2 = Plack::Middleware::MangleEnv->new(
       manglers => {
          what => 'EVER',
          who  => 'are you?',
       }
    );

    # when evaluation order or repetition is important... use an array
    # reference for 'manglers'
    my $mw3 = Plack::Middleware::MangleEnv->new(
       manglers => [
          same_as => 'before', # set this at the beginning...
          what => {env => 'same_as'},
          ...,
          same_as => [], # ... and delete this at the end
       ]
    );

# DESCRIPTION

This module allows you to mangle [Plack](https://metacpan.org/pod/Plack)'s `$env` that is passed along
to the sequence of _app_s, taking values from:

- direct configuration;
- values from `%ENV`;
- other values in `$env` itself;
- subroutines.

## How Variables Are Set

The end goal of this middleware module is to manipulate `$env` by
adding, changing or deleting its items.

You can pass the different actions to be performed as key-value pairs.
They can either appear directly upon invoking the middleware, as in the
following example:

    my $mw = Plack::Middleware::MangleEnv->new(
       var_name    => 'a simple, overriding value',
       some_value  => [ \@whatever ],
       alternative => { value => $whatever },
       # ... you get the idea
    );

or wrap these pairs inside either an hash or an array reference whose
key is `manglers`, like in the following examples:

    my $mw_h = Plack::Middleware::MangleEnv->new(
       manglers => {
          var_name    => 'a simple, overriding value',
          some_value  => [ \@whatever ],
          alternative => { value => $whatever },
          # ... you get the idea
       }
    );

    my $mw_a = Plack::Middleware::MangleEnv->new(
       manglers => [
          var_name    => 'a simple, overriding value',
          some_value  => [ \@whatever ],
          alternative => { value => $whatever },
          # ... you get the idea
       ]
    );

Although more verbose, this last approach with an array reference is
important because it allows you to:

- define the exact order of evaluation for mangling actions;
- define multiple actions for the same key, possibly at different stages;
- use keys `manglers` and `app`, if you need them.

There's a wide range of possible _values_ that you can set associated
to a key:

- **Simple scalar**

        key => 'some simple, non-reference scalar',

    a _non-reference_ scalar is always taken as-is and then set in `$env`.

- **Array reference**

        key => [],
        key => [ { 'a non' => 'trivial scalar' } ],

    when you pass an array reference, it can be either empty (in which case
    the associated key will be _removed_ from `$env`) or contain exactly
    one value, which will be set into `$env`.

    This alternative allows you to set any scalar, not just non-reference
    ones; so the following examples will do what they say:

        # set key to an array ref with numbers 1..3 inside
        key => [ [1..3] ], # note: array ref inside array ref!

        # set key to a hash reference, literally
        key => [ { a => 'b', c => 'd' } ],

        # set key to a sub reference, literally
        key => [ sub { 'I go with key!' } ],

- **Sub reference**

        key => sub { ... },

    the sub reference will be called and its return value used to figure out
    the value to associate to the key. See ["Sub Reference Interface"](#sub-reference-interface) for
    details on the expected interface for the sub;

- **Hash reference**

    allows you to be _verbosely clear_ about what you want, in addition to
    giving you knobs to modify the behaviour. The allowed keys are the
    following:

    - `env`

        points to a string that will be used to extract the value from `$env`
        itself. Useful if you want to _change the name_ of a parameter;

    - `ENV`

        points to a string that will be used to extract the value from `%ENV`.
        Useful if you want to get some variables from the environment.

    - `override`

        boolean flag that indicates whether the new value overrides a previous
        one, if any. Set to a false value to avoid overriding an existing value,
        while still being able to provide a default one if the key is missing
        from `$env`.

        Defaults to a true value;

    - `sub`

        set a subroutine, see ["Sub Reference Interface"](#sub-reference-interface) for details;

    - `value`

        set a value that is not a simple plain scalar:

            # set key to an array ref with numbers 1..3 inside
            key => { value => [1..3] },

            # set key to a hash reference, literally
            key => { value => { a => 'b', c => 'd' } }, # note: hash in hash!

            # set key to a sub reference, literally
            key => { value => sub { 'I go with key!' } },

    Exactly one of the keys `env`, `ENV`, `sub` and `value` MUST appear
    in the hash reference. For obvious reasons, you cannot provide more of
    them, otherwise a conflict would arise.

## Sub Reference Interface

The most flexible way to mangle `$env` is through a subroutine. It can
be provided either directly associated to the key, or through the `sub`
sub-key in the hash associated to the key.

The provided subroutine reference will be called like this:

    sub {
       my ($current_value, $env, $key) = @_;
       # do what you need
       return @something;
    }

The _sub_ can modify `$env` at will, e.g. by adding new keys or
removing other ones based on your specific logic.

If you don't return anything, or the `undef` value, the corresponding
`$key` in `$env` will be left untouched, keeping its previous value
(if any).  Otherwise, you are supposed to return one single value that
can be:

- **not** an array reference, in which case it is used as the value
associated to `$key` in `$env`;
- an array reference. If the array is empty, the `$key` is removed from
`$env`; otherwise, it MUST contain exactly one value, used to set the
key `$key` in `$env` (which also allows you to set as output an array
reference, even an empty one).

Examples:

    # nothing happens with this
    sub { return }

    # key is removed from $env
    sub { return [] }

    # key is set to an empty array in $env
    sub { return [[]] }

# METHODS

The following methods are implemented as part of the interface for a
Plack middleware. Although you can override them... there's probably
little sense in doing this!

- call
- prepare\_app

Methods described in the following subsections can be overridden or used
in derived classes. The various `generate*_manglers` functions have the
plural form because they can potentially return a list of manglers; in
this module, anyway, each of them returns one single mangler per call.

## **generate\_array\_manglers**

    my @manglers = $obj->generate_array_manglers($key, $aref, $defaults);

generate manglers starting from an array definition. `$aref` MUST be
an `ARRAY` reference. Depending on the number of elements in `@$aref`:

- if no element is present, a _remove_ mangler is generated via
["generate\_remove\_manglers"](#generate_remove_manglers)
- if exactly one element is present, a _value_ mangler is generated via
["generate\_value\_manglers"](#generate_value_manglers)
- otherwise, an exception is thrown.

## **generate\_code\_manglers**

    my @manglers = $obj->generate_code_manglers($key, $sub, $defaults);

generate manglers from a sub definition. `$sub` MUST be a `CODE`
reference.

The provided sub is wrapped using ["wrap\_code"](#wrap_code) to set the right
behaviour around `$sub`, then the output mangler is returned as
follows:

    [$key => {%$defaults, wrapsub => $wrapped_sub}]

## **generate\_hash\_manglers**

    my @manglers = $obj->generate_hash_manglers($key, $hash, $defaults);

generate manglers from a hash definition. `$hash` MUST be a `HASH`
reference.

This sub applies the procedure exposed in the ["DESCRIPTION"](#description) and it
will not be repeated here.

## **generate\_manglers**

    my @manglers = $obj->generate_manglers($key, $value, $defaults);

Generate zero, one or more manglers, dispatching to the proper function
depending on the type of `$value`. `$defaults` is a hash reference
holding default values for the generated mangler, e.g. setting
`override` to 1 by default.

At the moment, all generation methods return exactly one mangler per
call. This can of course change in derived classes, hence the returned
value can contain any number of items.

This method does the following dispatching based on `ref($value)`:

- non-reference scalars: ["generate\_value\_manglers"](#generate_value_manglers)
- array references: ["generate\_array\_manglers"](#generate_array_manglers)
- hash references: ["generate\_hash\_manglers"](#generate_hash_manglers)
- code references: ["generate\_code\_manglers"](#generate_code_manglers)
- anything else throws an exception.

If you want to override it (e.g. to add support for different types, or
change the default ones described above) you might augment it like in
the following example:

    # suppose we want to do something with Regexp references

    package Plack::Middleware::MangleEnv::Derived;
    use parent 'Plack::Middleware::MangleEnv';
    sub generate_manglers {
       my $self = shift;

       return $self->generate_regex_manglers(@_)
         if ref($_[1]) eq 'Regexp';

       return $self->SUPER::generate_manglers(@_);
    }
    sub generate_regex_manglers {
       my ($self, $key, $regex, $defaults) = @_;
       my $sub = sub {
          defined(my $value = shift) or return; # do nothing if undef
          my ($capture) = $value =~ m{$regex};
          return $capture;
       };
       my $wrapsub = $self->wrap_code($sub);
       return [$key => {%$defaults, wrapsub => $wrapsub}];
    }
    1;

## **generate\_remove\_manglers**

    my @manglers = $obj->generate_remove_manglers($key, $value, $defaults);

convenience function to generate manglers for removing. Such manglers
are supposed to have this form:

    [ $key => { remove => 1 } ]

and this function does exactly this, ignoring `$defaults` and checking
that `$value` is empty if it is a hash reference (it is used by
["generate\_hash\_manglers"](#generate_hash_manglers) behind the scenes, so this checks that there
are no further keys in the input mangler definition).

## **generate\_value\_manglers**

    my @manglers = $obj->generate_value_manglers($key, $value, $defaults);

generates this mangler:

    [$key => {%$defaults, value => $value}]

i.e. the standard mangler for setting a straight value.

## **push\_manglers**

    $obj->push_manglers->(@manglers);

add the provided `@manglers` to the list of manglers that will be used
at runtime.

Used by `prepare_app` to populate the list of runtime manglers from the
provided inputs. For every input definition of a mangler,
["generate\_manglers"](#generate_manglers) is called and its output fed to this method, like
this:

    my @manglers = $obj->generate_manglers(...);
    $obj->push_manglers(@manglers);

You might want to override this method if you want to further process
_all_ the generated manglers, like this:

    package Plack::Middleware::MangleEnv::Derived;
    use parent 'Plack::Middleware::MangleEnv';
    sub push_manglers {
       my $self = shift;
       my @manglers = map { do_something($_) } @_;
       return $self->SUPER::push_manglers(@manglers);
    }
    ...

## **stringified\_list**

    my @strings = $obj->stringified_list(@list);

convenience function to generate a list of strings suitable for logging.
Defined element are escaped and put into single quotes, while `undef`
is rendered as the string `undef` (without quoting).

## **wrap\_code**

    my $wrapped_sub = $obj->wrap_code($key, $sub);

wrap a code sub adhering to the ["Sub Reference Interface"](#sub-reference-interface) to implement
the behaviour described in the same subsection. It is used by both
["generate\_code\_manglers"](#generate_code_manglers) and ["generate\_hash\_manglers"](#generate_hash_manglers) to wrap input
`sub`s.

# BUGS AND LIMITATIONS

Report bugs either through RT or GitHub (patches welcome).

# SEE ALSO

[Plack](https://metacpan.org/pod/Plack), [Plack::Middleware::ForceEnv](https://metacpan.org/pod/Plack::Middleware::ForceEnv),
[Plack::Middleware::SetLocalEnv](https://metacpan.org/pod/Plack::Middleware::SetLocalEnv),
[Plack::Middleware::SetEnvFromHeader](https://metacpan.org/pod/Plack::Middleware::SetEnvFromHeader).

# AUTHOR

Flavio Poletti <polettix@cpan.org>

# COPYRIGHT AND LICENSE

Copyright (C) 2016 by Flavio Poletti <polettix@cpan.org>

This module is free software. You can redistribute it and/or modify it
under the terms of the Artistic License 2.0.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.
