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

       # use subroutines for maximum flexibility. They can be strings or
       # be loaded from modules too.
       change_me1  => sub { ... },
       change_me2  => { sub => sub { ... } },
       change_me3  => { sub => 'sub { ... }' },
       change_me4  => { sub => [$factory, @params] },

    );

    # when evaluation order or repetition is important... use an array
    # reference
    my $mw2 = Plack::Middleware::MangleEnv->new(
       mangle => [
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

or wrap these pairs inside an array reference whose key is
`mangle`, like in the following example:

    my $mw = Plack::Middleware::MangleEnv->new(
       mangle => [
          var_name    => 'a simple, overriding value',
          some_value  => [ \@whatever ],
          alternative => { value => $whatever },
          # ... you get the idea
       ]
    );

Although more verbose, this second approach is superior because it
allows you to:

- define the exact order of evaluation for mangling actions;
- define multiple actions for the same key, possibly at different stages;
- use keys `mangle` and `app`, if you need them.

There's a wide range of possible _values_ that you can set associated
to a key, which allow you to perform a plethora of operations. In
particular:

- **Simple scalar**

        key => 'some simple, non-reference scalar',

    a _non-reference_ scalar is always taken as-is and then set in `$env`.

- **Array reference**

        key => [],
        key => [ { 'a non' => 'trivial scalar' } ],

    when you pass an array reference, it can be either empty (in which case
    the associated key will be _removed_ from `$env`) or contain exactly
    one value, which will be set into `$env`.

    This alternative allows you to pass any scalar, not just non-reference
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

        Can not appear together with either `ENV` or `value`, for obvious
        reasons;

    - `ENV`

        points to a string that will be used to extract the value from `%ENV`.
        Useful if you want to get some variables from the environment, e.g. see
        ["Example Scenario"](#example-scenario).

        Can not appear together with either `env` or `value`, for obvious
        reasons;

    - `override`

        boolean flag that indicates whether the new value overrides a previous
        one, if any. Set to a false value to avoid overriding an existing value,
        while still being able to provide a default one if the key is missing
        from `$env`.

        Defaults to a true value;

    - `sub`

        set a subroutine, which can be a real sub reference, a text string
        holding the definition (it will be `eval`ed) or an array reference with
        pointers to a factory for the sub reference.

        See ["Sub Reference Interface"](#sub-reference-interface) for details;

    - `value`

        Can not appear together with either `env` or `ENV`, for obvious
        reasons.

        This is an alternative way to set a value that is not a simple plain
        scalar:

            # set key to an array ref with numbers 1..3 inside
            key => { value => [1..3] },

            # set key to a hash reference, literally
            key => { value => { a => 'b', c => 'd' } }, # note: hash in hash!

            # set key to a sub reference, literally
            key => { value => sub { 'I go with key!' } },

## Sub Reference Interface

The most flexible way to mangle `$env` is through a subroutine. It can
be provided either directly associated to the key, or through the `sub`
sub-key in the hash associated to the key. In this latter case, in
addition to providing a real sub reference, you can also pass:

- a text string. This is `eval`ed and is expected to return a sub
reference;
- an array reference, like this:

        [ 'Some::Package::factory', @parameters ]

    The _factory_ function is loaded and called with the provided
    `@parameters`, and it is expected to return a sub reference.

    In case you don't fully qualify the sub for the factory, it will be
    referred to `Plack::Middleware::MangleEnv` or whatever derived class
    you're actually using. One useful function for this is ["ref\_to"](#ref_to), that
    give you a reference to a sub in a package, like this:

        [ ref_to => 'Some::Package::mangler' ]

    In this case, it will `require` package `Some::Package` and then get a
    reference to `mangler` inside it. Yes, this has limitations (e.g. it
    does not allow you to load functions from embedded modules).

Whatever the way, you will eventually land on a subroutine reference
that, at the right time, will be called like this:

    sub {
       my ($current_value, $env, $key) = @_;
       # do what you need
       return @something;
    }

The _sub_ can modify `$env` at will, e.g. by adding new keys or
removing other ones based on your specific logic.

If you don't return anything, or the `undef` value, the corresponding
`$key` in `$env` will be skipped (keeping its previous value if any).
Otherwise, you are supposed to return one single value that can be:

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

## Example Scenario

For example, suppose that you have a fancy reverse-proxy setup where you
need to override some values in order to make your web toolkit happy
(e.g. [Dancer](https://metacpan.org/pod/Dancer) or [Mojolicious](https://metacpan.org/pod/Mojolicious)).

The example scenario will be detailed in a later stage!

# FUNCTIONS

## **ref\_to**

    my $sub_ref = ref_to($target, $default_package);
    $sub_ref = ref_to('Package::my_sub');
    $sub_ref = ref_to('other_sub', 'Package::Some');

get a reference to a sub whose name is contained in `$target`,
optionally searching it into package `$default_package` if none is
found in `$target`.

It uses `require` to load the package, so if your package is a
sub-package inside a differently-named file you're out of luck.

# METHODS

## **ALLOW\_EVAL**

    my $perl_bool = $self->ALLOW_EVAL();

this method tells you whether the `eval` interface for subroutines is
enabled or not.

The default implementation returns `0`, i.e. a false value. This means
that the `eval` interface is _disabled_.

Hence, to enable the `eval` interface, you MUST override or
monkey-patch this method to return a true value (in Perl sense) before
`prepare_app` is called. For example, if you trust your user base you
can provide the following middleware:

    use Plack::Middleware::MangleEnv::WithEval;
    use parent 'Plack::Middleware::MangleEnv';
    sub ALLOW_EVAL { return 1 }
    1;

## **ALLOW\_FACTORY**

    my $perl_bool = $self->ALLOW_FACTORY();

this method tells you whether the _factory_ interface for subroutines is
enabled or not.

The default implementation returns `0`, i.e. a false value. This means
that the _factory_ interface is _disabled_.

Hence, to enable the _factory_ interface, you MUST override or
monkey-patch this method to return a true value (in Perl sense) before
`prepare_app` is called. For example, if you trust your user base you
can provide the following middleware:

    use Plack::Middleware::MangleEnv::WithFactory;
    use parent 'Plack::Middleware::MangleEnv';
    sub ALLOW_FACTORY { return 1 }
    1;

## Plack-related

The following methods are implemented as part of the interface for a
Plack middleware.

- call
- prepare\_app

# SECURITY

This module contains code (in subs `__sub_from_eval` and
`__sub_from_factory`) that can eventually lead to either an `eval` or
to loading an arbitrary module. This code is disabled by default, but
this is not as if the code were not there.

Enabling either of `eval` and _factory_ interfaces requires an
attacker to be able to either monkey-patch
["ALLOW\_EVAL"](#allow_eval)/["ALLOW\_FACTORY"](#allow_factory) in the main module, or to generate a
subclass where these method are overridden to provide a true value back.
Another way is to call `__sub_from_eval` and/or `__sub_from_factory`
directly. The ["AUTHOR"](#author) is not aware of other ways to trigger that code.

If your attacker is able to do that, this module isn't likely to add
more capabilities because they already have anything needed anyway. For
example, they might substitute `prepare_app` instead and put arbitrary
code there, or if they can call `__sub_from_eval` they might just be
able to call `eval` directly by themselves.

Anyway this consideration is NOT based on a thorough analysis, so there
can be corner cases where this situation might actually open further
doors.  For example, there might be different ways to substitute
["ALLOW\_EVAL"](#allow_eval)/["ALLOW\_FACTORY"](#allow_factory) that the ["AUTHOR"](#author) is not aware of,
whereas these ways might not be applicable to substituting
`prepare_app` or something different instead. Or they might manage to
call `__sub_from_eval` (or `__sub_from_factory`) in other ways.

If you're unsure about it, you can:

- perform a thorough assessment of the code, possibly supported by a
security and Perl expert, until you're fine with it, OR
- remove the code you're not comfortable with (look for `__sub_from_eval`
and `__sub_from_factory`), OR
- NOT use this module.

Whatever you choose to do, it will be YOUR choice!

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
