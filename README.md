# NAME

Plack::Middleware::MangleEnv - Mangle request environment at will

# VERSION

This document describes Plack::Middleware::MangleEnv version 0.01.

# SYNOPSIS

    use Plack::Middleware::MangleEnv;

    my $mw = Plack::Middleware::MangleEnv->new(

       # overriding
       var_name    => 'a simple, overriding value',
       some_value  => [ $whatever ],
       alternative => { value => $whatever },
       from_ENV    => { ENV => 'SOME_ENV_VAR' },

       # override is a boolean flag, when set to 0 the value is
       # set only if not already present
       de_fault    => { value => $something, override => 0 },
       # also works with ENV

       # get rid of a variable, inconditionally
       delete_pliz => [],
       delete_me   => { remove => 1 },

       # flexibility
       change_me1  => sub { ... },
       change_me2  => { sub => sub { ... } },
       change_me3  => { sub => 'sub { ... }' },
    );

# DESCRIPTION

This module allows you to...

# FUNCTIONS

- **whatever**

# METHODS

- **whatever**

# BUGS AND LIMITATIONS

Report bugs either through RT or GitHub (patches welcome).

# SEE ALSO

Foo::Bar.

# AUTHOR

Flavio Poletti <polettix@cpan.org>

# COPYRIGHT AND LICENSE

Copyright (C) 2016 by Flavio Poletti <polettix@cpan.org>

This module is free software. You can redistribute it and/or modify it
under the terms of the Artistic License 2.0.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.
