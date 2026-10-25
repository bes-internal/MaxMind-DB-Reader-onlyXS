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

## Motivation

In a short-lived script that makes a single lookup, loading modules takes
longer than the lookup itself. This module is only the XS code on top of
libmaxminddb and loads almost nothing else, so it is the fastest choice when
you call it once.

Result of `perl dev/bench.pl` (perl 5.36.0, Linux x86_64, libmaxminddb 1.9.1,
`GeoLite2-City.mmdb` of 50 MB).

Cold: a new process loads the module, opens the database and makes one lookup.
"Modules" is the number of files in `%INC` after that:

| | median, ms | added over `perl -e1`, ms | modules | RSS, MB |
|---|---:|---:|---:|---:|
| `perl -e1` (baseline) | 5.0 | | 0 | 5.0 |
| `MaxMind::DB::Reader` (pure Perl) | 237.4 | +232.4 | 104 | 19.5 |
| `MaxMind::DB::Reader::XS` | 166.2 | +161.2 | 88 | 17.3 |
| `IP::Geolocation::MMDB` | 63.8 | +58.8 | 18 | 11.8 |
| `MaxMind::DB::Reader::onlyXS` | 6.7 | +1.7 | 3 | 5.9 |

Warm: lookups per second in a process that has everything loaded (random IPv4 addresses):

| | lookups/s |
|---|---:|
| `MaxMind::DB::Reader` (pure Perl) | 133 |
| `MaxMind::DB::Reader::XS` | 63 000 |
| `IP::Geolocation::MMDB` | 63 000 |
| `MaxMind::DB::Reader::onlyXS` | 63 500 |

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

The module is made for short-lived scripts, so loading it must stay cheap: do not
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

## Limitations

The module is not thread safe: a handle copied into a new ithread is a closed
handle. It is tested with perls with 64-bit integers; the code path of a perl
with 32-bit integers (uint64 as `Math::Int64` objects) is tested by building
with `-DONLYXS_NO_NATIVE_INT64`:

    perl Build.PL --extra_compiler_flags=-DONLYXS_NO_NATIVE_INT64

(`t/lazy-load.t` fails then, as it should: `Math::Int64` is loaded).

To run the tests on a real database:

    MMDB_REAL=/usr/share/GeoIP/GeoLite2-City.mmdb ./Build test

and the memory leak tests (`cpm install -L dev/local Test::LeakTrace`):

    prove -b xt/author/leak.t

## Origin

This is a fork of
[MaxMind-DB-Reader-XS](https://github.com/maxmind/MaxMind-DB-Reader-XS) up to
version 1.000009, written by MaxMind, Inc. (the XS code that decodes the
database is still theirs, see the history of the upstream repository for the
list of its authors and contributors). MaxMind has deprecated the original
distribution and does not develop it any more; this one is developed and
maintained independently.

## Author

Vladimir Varlamov <bes.internal@gmail.com>

## Copyright and licence

Copyright (c) 2013-2022 MaxMind, Inc. for the code of the original
distribution, and (c) 2018-2026 Vladimir Varlamov for the changes.

This is free software, licensed under The Artistic License 2.0 (GPL
Compatible), the same license as the original distribution, see the `LICENSE`
file.

Files of other authors included in the distribution keep their own licenses:

- `c/perl_math_int64.*`, `c/perl_math_int128.*` (Salvador Fandino): public
  domain;
- `c/ppport.h` (Devel::PPPort): the same terms as Perl itself;
- `inc/Capture/Tiny.pm` (David Golden): Apache License 2.0;
- `inc/Config/AutoConf.pm`: the same terms as Perl itself.

The module links against libmaxminddb (Apache License 2.0).
