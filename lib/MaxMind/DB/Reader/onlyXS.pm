package MaxMind::DB::Reader::onlyXS;

# ABSTRACT: Fast XS implementation of MaxMind DB reader

our $VERSION = '1.1.0'; # VERSION

use 5.010000;

use XSLoader;

XSLoader::load( __PACKAGE__, $VERSION );

1;

__END__

=head1 SYNOPSIS

    use MaxMind::DB::Reader::onlyXS;

    # MMDB_MODE_MMAP is 1
    my $db = MaxMind::DB::Reader::onlyXS::_open_mmdb( 'path/to/database.mmdb', 1 );

    my $record = MaxMind::DB::Reader::onlyXS::__data_for_address( $db, '1.2.3.4' );

=head1 DESCRIPTION

Fast XS implementation of the MaxMind DB reader without the object oriented
wrappers. The module is made for short-lived scripts: loading it loads nothing
but L<XSLoader> (and L<strict>, which XSLoader loads), so a script that does
C<require MaxMind::DB::Reader::onlyXS> pays about 1.5 ms for it.
L<Math::Int128> is loaded on the first C<uint128> value only.

The XS implementation links against the
L<libmaxminddb|http://maxmind.github.io/libmaxminddb/> library. The functions
are not exported, call them with the full name. Their names start with an
underscore because this is the interface the L<MaxMind::DB::Reader::XS> had
under its wrappers, there are no other public functions.

=head1 FUNCTIONS

=head2 _open_mmdb( $file, $flags )

Opens the database and returns a handle. C<$flags> are the libmaxminddb
flags: C<1> is C<MMDB_MODE_MMAP> (the only mode libmaxminddb has, use it) and
C<0> is the same. Dies if the file can not be opened or is not a MaxMind DB
file.

The handle is a reference. It is true, so it can be kept in a global variable
and checked with C<if (!$db)>. The database is closed when the last copy of
the handle goes away, a script does not have to close it.

Every function that takes a handle dies with C<Invalid database handle> if it
gets anything else (undef, a string, a number, a reference to something other
than a handle) and with C<handle ... is closed> if the database was closed.

=head2 __data_for_address( $handle, $ip )

Returns the record for an IPv4 or IPv6 address as a hash reference, or
C<undef> if the address is not in the database.

    my $city = ( __data_for_address( $db, $ip ) || {} )->{city}{names}{en};

Dies if the address is empty, is not a valid IPv4 or IPv6 address (what
C<getaddrinfo> does not take as a numeric address), is an IPv6 address and the
database has only IPv4, or if the database is broken at this record.

Strings have the utf8 flag on. C<uint64> is a plain integer. C<uint128> is a
L<Math::UInt128> object.

=head2 __value_for_address( $handle, $ip, @path )

Returns one value of the record of the address, the one at the C<@path>, and
does not decode the rest of the record. A record of a City database has tens
of keys in many languages; if only the name of the country is needed this is
several times faster than C<__data_for_address> (about 5 times on
GeoLite2-City), and when a script asks for 4 values of the same address the
difference is about 10 times.

    my $country = __value_for_address( $db, $ip, 'country', 'names', 'en' );

The elements of an array are found by the index, a negative index counts from
the end:

    my $region = __value_for_address( $db, $ip, 'subdivisions', 0, 'names', 'en' );

If the path ends at a map or an array it is returned whole, without a path the
whole record is returned. The result is C<undef> if there is no record for
the address or no such value in it (also when the path does not fit the
structure of this record, for example goes through a string or the index of an
array is not a number). The result is always one value, in any context. It
dies in the same cases as C<__data_for_address>, and if the address or an
element of the path contains a NUL byte.

=head2 __lookup_for_address( $handle, $ip, @path )

The same as C<__value_for_address>, but returns the list of the value and the
length of the network of the record (C</24> is 24):

    my ( $city, $prefix_length ) = __lookup_for_address( $db, $ip, 'city', 'names', 'en' );

The length is in the terms of the address: for an IPv4 address in a database
with IPv6 addresses it is the length of the IPv4 network (not 96 bits more),
and it is 0 if the network is bigger than the IPv4 part of the database. If
there is no record both values are C<undef>; if the record has no such value
the first one is C<undef>. It is a separate function (and not the list context
of C<__value_for_address>) so that a call in a list does not add an element.

=head2 _raw_metadata( $handle )

Returns the metadata of the database as a hash reference (C<node_count>,
C<record_size>, C<ip_version>, C<database_type>, C<languages>, C<description>,
C<build_epoch>, ...).

=head2 _iterate_search_tree( $handle, $data_callback, $node_callback )

Walks the whole search tree. C<$data_callback> is called for every record
with the first IP of the network as a L<Math::UInt128>, the prefix length and the
record. C<$node_callback> is called for every node with the node number and
the left and right records. Either of them can be undef.

The callbacks can not close the database (C<_close_mmdb> dies with C<The
database is in use>); if a callback frees all the variables with the handle
the walk goes on to the end with the database still open.

=head2 __read_node( $handle, $node_number )

Returns the left and the right record of the node.

=head2 libmaxminddb_version()

Returns the version of the libmaxminddb the module is linked with.

=head1 EXAMPLE

The order of the calls and what each of them returns (a City database, the
results follow the calls after C<#>):

    require MaxMind::DB::Reader::onlyXS;

    my $db = MaxMind::DB::Reader::onlyXS::_open_mmdb( '/usr/share/GeoIP/GeoLite2-City.mmdb', 1 );
    # a reference, it is true; the database is closed when $db is freed

The whole record is decoded into a hash reference (this is what to use if most
of the fields are needed):

    MaxMind::DB::Reader::onlyXS::__data_for_address( $db, '2.125.160.216' );
    # {
    #     city => {
    #         geoname_id => 2655045,
    #         names      => {
    #             en => 'Boxford',
    #         },
    #     },
    #     continent          => { code => 'EU', ... },
    #     country            => { iso_code => 'GB', ... },
    #     location           => { latitude => 51.75, ... },
    #     postal             => { code => 'OX1' },
    #     registered_country => { ... },
    #     subdivisions       => [ { ... }, { ... } ],
    # }

    MaxMind::DB::Reader::onlyXS::__data_for_address( $db, '10.0.0.1' );
    # undef: the address is not in the database

    MaxMind::DB::Reader::onlyXS::_raw_metadata($db);
    # {
    #     database_type => 'GeoIP2-City',
    #     ip_version    => 6,
    #     record_size   => 28,
    #     node_count    => 1431,
    #     languages     => [ 'en', 'zh' ],
    #     build_epoch   => 1556722619,
    #     ...
    # }

A value of the record, the rest of the record is not decoded. This is an
optimization for speed: use it in the hot code, where only some fields are
needed (several times faster than decoding the whole record):

    MaxMind::DB::Reader::onlyXS::__value_for_address( $db, '2.125.160.216', 'country', 'names', 'en' );
    # 'United Kingdom'

    MaxMind::DB::Reader::onlyXS::__value_for_address( $db, '2.125.160.216', 'country', 'names' );
    # {
    #     en => 'United Kingdom',
    #     es => 'Reino Unido',
    #     fr => 'Royaume-Uni',
    #     ...
    # }

    MaxMind::DB::Reader::onlyXS::__value_for_address( $db, '2.125.160.216', 'nokey' );
    # undef: there is no such value

    MaxMind::DB::Reader::onlyXS::__value_for_address( $db, '10.0.0.1', 'country', 'names', 'en' );
    # undef: the address is not in the database

The value and the length of the network of the record:

    MaxMind::DB::Reader::onlyXS::__lookup_for_address( $db, '2.125.160.216', 'city', 'names', 'en' );
    # ( 'Boxford', 29 )

    MaxMind::DB::Reader::onlyXS::__lookup_for_address( $db, '10.0.0.1', 'city', 'names', 'en' );
    # ( undef, undef )

An address that is not valid dies:

    MaxMind::DB::Reader::onlyXS::__value_for_address( $db, 'garbage', 'country' );
    # dies: The IP address you provided (garbage) is not a valid IPv4 or IPv6 address

A user input (a form field, a query string, a header) must not be passed
without a check. The library checks the address, so the simplest way is to
catch the error:

    my $country;
    my $valid = eval {
        $country = MaxMind::DB::Reader::onlyXS::__value_for_address(
            $db, $input, 'country', 'names', 'en' );
        1;
    };
    # $valid is undef for a bad input (the reason is in $@), 1 otherwise; an
    # address that is not in the database is a valid input with $country undef

Spaces and a newline around the address are not accepted, remove them before
the call (C<s/^\s+|\s+$//g>). The path (C<'country', 'names', 'en'>) should not
come from the user.

The handle can be closed before it is freed; a closed handle dies:

    MaxMind::DB::Reader::onlyXS::_close_mmdb($db);    # optional
    MaxMind::DB::Reader::onlyXS::__value_for_address( $db, '2.125.160.216', 'country' );
    # dies: ... The database handle passed to __value_for_address() is closed

=head1 LIMITATIONS

The module is not thread safe: a handle copied into a new ithread is a closed
handle.

Only 64-bit platforms are supported: the code needs a 128-bit integer type,
which gcc does not have on 32-bit platforms (F<Build.PL> stops there).

=head1 SUPPORT

Please report all issues with this code using the GitHub issue tracker at
L<https://github.com/bes-internal/MaxMind-DB-Reader-onlyXS/issues>.

The upstream distribution is L<MaxMind::DB::Reader::XS>
(L<https://github.com/maxmind/MaxMind-DB-Reader-XS>).

=head1 AUTHOR

Vladimir Varlamov E<lt>bes.internal@gmail.comE<gt>

=head1 ORIGIN

This distribution is a fork of
L<MaxMind-DB-Reader-XS|https://github.com/maxmind/MaxMind-DB-Reader-XS> up to
version 1.000009, written by MaxMind, Inc. (the XS code that decodes the
database is still theirs, see the history of the upstream repository for the
list of its authors and contributors). MaxMind has deprecated the original
distribution and does not develop it any more; this one is developed and
maintained independently.

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2013 - 2022 MaxMind, Inc. for the code of the original
distribution, and (c) 2018 - 2026 Vladimir Varlamov for the changes.

This is free software, licensed under The Artistic License 2.0 (GPL
Compatible), see the F<LICENSE> file. The files of other authors that are
included in the distribution (F<c/perl_math_int*>, F<c/ppport.h>,
F<inc/Capture/Tiny.pm>, F<inc/Config/AutoConf.pm>) keep their own licenses.
