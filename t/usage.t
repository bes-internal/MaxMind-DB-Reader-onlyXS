use strict;
use warnings;

use Test::More;
use File::Spec;

# The calls the CGI scripts make: open the City database with flags 1
# (MMDB_MODE_MMAP) and read the record of an address.

my $file = File::Spec->catfile( 'maxmind-db', 'test-data', 'GeoIP2-City-Test.mmdb' );
plan skip_all => 'maxmind-db submodule is not checked out (git submodule update --init)'
    unless -f $file;

require MaxMind::DB::Reader::onlyXS;

sub _open   { MaxMind::DB::Reader::onlyXS::_open_mmdb(@_) }
sub _record { MaxMind::DB::Reader::onlyXS::__data_for_address(@_) }

subtest '_open_mmdb( $file, 1 )' => sub {
    my $handle = _open( $file, 1 );
    ok( $handle, 'returns a handle' );
    ok( !ref $handle, 'the handle is a plain scalar, it can be cached in a global' );
    is( _record( $handle, '2.125.160.216' )->{city}{names}{en}, 'Boxford', 'handle works' );
    is( _record( $handle, '81.2.69.142' )->{city}{names}{en}, 'London', 'and works repeatedly' );
};

subtest 'record fields' => sub {
    my $handle = _open( $file, 1 );
    my $r = _record( $handle, '2.125.160.216' );

    is( ref $r, 'HASH', 'record is a hash' );
    is( $r->{continent}{names}{en},        'Europe',         'continent' );
    is( $r->{country}{names}{en},          'United Kingdom', 'country' );
    is( $r->{subdivisions}[0]{names}{en},  'England',        'region (first subdivision)' );
    is( $r->{city}{names}{en},             'Boxford',        'city' );

    my $us = _record( $handle, '216.160.83.56' );
    is( $us->{country}{names}{en},         'United States', 'country, US' );
    is( $us->{subdivisions}[0]{names}{en}, 'Washington',    'region, US' );

    my $se = _record( $handle, '89.160.20.112' );
    is( $se->{city}{names}{en}, "Link\x{f6}ping", 'city name with non-ASCII letters' );
    ok( utf8::is_utf8( $se->{city}{names}{en} ), 'the string has the utf8 flag' );

    my $jp = _record( $handle, '2001:218::1' );
    is( $jp->{country}{names}{en}, 'Japan', 'IPv6 address' );
    ok( !exists $jp->{city},         'no city in this record' );
    ok( !exists $jp->{subdivisions}, 'no subdivisions in this record' );
};

subtest 'address that is not in the database' => sub {
    my $handle = _open( $file, 1 );
    is( _record( $handle, '10.0.0.1' ), undef, 'IPv4 gives undef' );
    is( _record( $handle, '::1' ),      undef, 'IPv6 gives undef' );
    is_deeply( _record( $handle, '10.0.0.1' ) || {}, {}, '|| {} gives an empty hash' );
};

subtest 'invalid address' => sub {
    my $handle = _open( $file, 1 );
    for my $ip ( 'garbage', '1.2.3.256', '1.2.3.4.5' ) {
        like(
            eval { _record( $handle, $ip ); 1 } ? '' : $@,
            qr/not a valid IPv4 or IPv6 address/,
            "$ip croaks"
        );
    }
    like(
        eval { _record( $handle, '' ); 1 } ? '' : $@,
        qr/You must provide an IP address/,
        'empty address croaks'
    );
};

subtest 'no handle (the database file was not found)' => sub {
    for my $handle ( undef, '', 'abc' ) {
        my $name = defined $handle ? "'$handle'" : 'undef';
        like(
            eval { _record( $handle, '2.125.160.216' ); 1 } ? '' : $@,
            qr/Invalid database handle passed to __data_for_address\(\)/,
            "$name croaks instead of crashing perl"
        );
    }
    like(
        eval { MaxMind::DB::Reader::onlyXS::_close_mmdb(undef); 1 } ? '' : $@,
        qr/Invalid database handle passed to _close_mmdb\(\)/,
        '_close_mmdb(undef) croaks'
    );
};

subtest 'file that does not exist' => sub {
    like(
        eval { _open( '/nonexistent/GeoLite2-City.mmdb', 1 ); 1 } ? '' : $@,
        qr/Error opening database file/,
        '_open_mmdb croaks'
    );
};

done_testing;
