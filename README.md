# MaxMind-DB-Reader-onlyXS

Fast XS implementation of MaxMind DB reader without OO wrappers.

This is a stripped-down fork of
[MaxMind-DB-Reader-XS](https://github.com/maxmind/MaxMind-DB-Reader-XS):
only the XS functions are left, there is no dependency on
`MaxMind::DB::Reader` and the Perl wrapper layer is removed. The module
links against the [libmaxminddb](http://maxmind.github.io/libmaxminddb/)
library.

## Synopsis

```perl
use MaxMind::DB::Reader::onlyXS;

my $db_fh  = MaxMind::DB::Reader::onlyXS::_open_mmdb( 'path/to/database.mmdb', $flags );
my $record = MaxMind::DB::Reader::onlyXS::__data_for_address( $db_fh, '1.2.3.4' );
```

## Installation

Requires libmaxminddb (headers and library), for example on Debian/Ubuntu:

    sudo apt install libmaxminddb-dev

To install this package from source:

    perl Build.PL
    ./Build
    ./Build test
    ./Build install

or use cpanminus:

    cpanm .

If libmaxminddb is installed in a non-standard location:

    perl Build.PL --lib /path/to/lib --include /path/to/include

## Develop CPAN release

Install cpm ( https://metacpan.org/pod/App::cpm ), then dependencies:

    cpanm App::cpm
    perl dev/dev.pl

Do something with code and test:

    perl dev/exec.pl dzil test

(don't forget to change: `dist.ini` copyright_year; `.pm` version; `Changes`)

    perl dev/exec.pl dzil build

(git commit/push)

    perl dev/exec.pl dzil release

Test against specific libmaxminddb versions (downloaded and built into
`dev/local-libmaxminddb`, the working tree is not touched):

    perl dev/test-libmaxminddb.pl 1.9.1 1.14.1

Clean dependencies and build:

    perl dev/clean-dev.pl

`dzil build` regenerates and copies back to the repository `Build.PL`,
`META.json`, `META.yml`, `MANIFEST`, `LICENSE`, `cpanfile`, `c/ppport.h`
and `lib/MaxMind/DB/Reader/onlyXS.pm`; do not edit them by hand.

## Support and documentation

After installing, you can find documentation for this module with the
perldoc command.

    perldoc MaxMind::DB::Reader::onlyXS

You can also look for information at:

- GitHub: https://github.com/bes-internal/MaxMind-DB-Reader-onlyXS
- Upstream: https://github.com/maxmind/MaxMind-DB-Reader-XS

## Copyright and licence

Copyright © 2019-2026 Vladimir Varlamov <bes.internal@gmail.com>

This module is based on MaxMind-DB-Reader-XS:
Copyright © 2013-2022 MaxMind, Inc.
(Boris Zentner, Dave Rolsky, Ran Eilam and contributors)

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
