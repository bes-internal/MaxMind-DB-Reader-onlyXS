# MaxMind-DB-Reader-onlyXS

Fast XS implementation of MaxMind DB reader without OO wrappers.

This is a stripped-down fork of
[MaxMind-DB-Reader-XS](https://github.com/maxmind/MaxMind-DB-Reader-XS):
only the XS functions are left, there is no dependency on
`MaxMind::DB::Reader` and the Perl wrapper layer is removed. The module
links against the [libmaxminddb](http://maxmind.github.io/libmaxminddb/)
library.

## Why this module exists

The module is made for CGI scripts, where every request starts a new perl
process: the time of loading modules is paid on every request and is often
bigger than the lookup itself. `MaxMind::DB::Reader` loads about 90-100
modules (Moo and its helpers, Sub::Quote, Role::Tiny, List::AllUtils,
Data::Validate::IP, NetAddr::IP, autodie, Encode, ...) before the first
lookup, even with `MaxMind::DB::Reader::XS`. `MaxMind::DB::Reader::onlyXS` is
only the XS code on top of libmaxminddb: it loads three files (itself,
`XSLoader` and `strict`), `Math::Int128` is loaded on the first `uint128` value
only, the database is opened with `mmap`.

Result of `perl dev/bench.pl --runs 200 --seconds 3` (perl 5.36.0, Linux
x86_64, libmaxminddb 1.9.1, the small `GeoIP2-City-Test.mmdb`; the numbers on
your host will differ, the proportions should not):

Cold: a new process loads the module, opens the database and makes one lookup
(this is what every CGI request does). "Modules" is the number of files in
`%INC` after that, nothing else is loaded by the process:

| | median, ms | added over `perl -e1`, ms | modules | RSS, MB |
|---|---:|---:|---:|---:|
| `perl -e1` (baseline) | 4.7 | | 0 | 5.0 |
| `MaxMind::DB::Reader` (pure Perl) | 195.6 | +191.0 | 104 | 19.5 |
| `MaxMind::DB::Reader::XS` | 138.1 | +133.5 | 88 | 17.1 |
| `MaxMind::DB::Reader::onlyXS` | 6.1 | **+1.5** | 3 | 5.5 |

`MaxMind::DB::Reader::XS` is used the way it is meant to be used, through
`MaxMind::DB::Reader->new(...)->record_for_address(...)`.

Warm: lookups per second in a process that has everything loaded:

| | lookups/s |
|---|---:|
| `MaxMind::DB::Reader` (pure Perl) | 8 100 |
| `MaxMind::DB::Reader::XS` | 824 000 |
| `MaxMind::DB::Reader::onlyXS` | 2 210 000 |

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

## Contributing

Questions, bug reports and patches: GitHub issues and pull requests at
https://github.com/bes-internal/MaxMind-DB-Reader-onlyXS

The tests use the `maxmind-db` submodule with the MaxMind test databases:

    git submodule update --init
    perl Build.PL
    ./Build
    ./Build test

or run a single test file:

    prove -bv t/lookup.t

The module is used from CGI scripts, so loading it must stay cheap: do not
add `use` of other modules to `onlyXS.pm` (`t/lazy-load.t` checks this). Load
what is rarely needed lazily from the XS code, like `Math::Int128` for the
`uint128` values.

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

Compare the cost with MaxMind::DB::Reader (needs them installed into
`dev/local-bench` and `./Build` done):

    cpm install -L dev/local-bench MaxMind::DB::Reader MaxMind::DB::Reader::XS
    perl dev/bench.pl

Clean dependencies and build:

    perl dev/clean-dev.pl

`dzil build` regenerates and copies back to the repository `Build.PL`,
`META.json`, `META.yml`, `MANIFEST`, `LICENSE`, `cpanfile`, `c/ppport.h`
and `lib/MaxMind/DB/Reader/onlyXS.pm`; change `dist.ini` instead of editing
them by hand.

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
