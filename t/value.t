use strict;
use warnings;

use Test::More;
use File::Spec;
use Data::Dumper;

use MaxMind::DB::Reader::onlyXS;

$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent   = 0;

my $dir = File::Spec->catdir( 'maxmind-db', 'test-data' );
plan skip_all => 'maxmind-db submodule is not checked out (git submodule update --init)'
    unless -d $dir;

sub _open   { MaxMind::DB::Reader::onlyXS::_open_mmdb( File::Spec->catfile( $dir, shift ), 1 ) }
sub _record { scalar MaxMind::DB::Reader::onlyXS::__data_for_address(@_) }
sub _value  { scalar MaxMind::DB::Reader::onlyXS::__value_for_address(@_) }
sub _lookup { MaxMind::DB::Reader::onlyXS::__lookup_for_address(@_) }
sub _err    { my $c = shift; eval { $c->(); 1 } ? '' : $@ }

my $city = _open('GeoIP2-City-Test.mmdb');

subtest '__value_for_address: one value of a record' => sub {
    my $ip = '2.125.160.216';
    is( _value( $city, $ip, qw( country names en ) ),   'United Kingdom', 'a string' );
    is( _value( $city, $ip, qw( city names en ) ),      'Boxford',        'the name of the city' );
    is( _value( $city, $ip, qw( continent code ) ),     'EU',             'the continent' );
    is( _value( $city, $ip, qw( city geoname_id ) ),    2655045,          'uint32' );
    is( _value( $city, $ip, qw( location latitude ) ),  51.75,            'double' );
    ok( _value( $city, $ip, qw( country is_in_european_union ) ), 'boolean' );

    is( _value( $city, '89.160.20.112', qw( city names en ) ), "Link\x{f6}ping", 'non-ASCII letters' );
    ok( utf8::is_utf8( _value( $city, '89.160.20.112', qw( city names en ) ) ), 'the string has the utf8 flag' );

    is( _value( $city, '2001:218::1', qw( country iso_code ) ), 'JP', 'an IPv6 address' );
};

subtest 'array elements are found by the index' => sub {
    my $ip = '2.125.160.216';
    is( _value( $city, $ip, 'subdivisions', 0, 'names', 'en' ),  'England',        'the first element' );
    is( _value( $city, $ip, 'subdivisions', 1, 'names', 'en' ),  'West Berkshire', 'the second element' );
    is( _value( $city, $ip, 'subdivisions', -1, 'names', 'en' ), 'West Berkshire', 'the last element' );
    is( _value( $city, $ip, 'subdivisions', 2, 'names', 'en' ),  undef,            'no such element' );
};

subtest 'a map or an array is returned whole' => sub {
    my $ip     = '2.125.160.216';
    my $record = _record( $city, $ip );

    is_deeply( _value( $city, $ip, 'country' ),      $record->{country},      'a map' );
    is_deeply( _value( $city, $ip, 'subdivisions' ), $record->{subdivisions}, 'an array' );
    is_deeply( _value( $city, $ip, qw( country names ) ), $record->{country}{names}, 'a map in a map' );
    is_deeply( _value( $city, $ip, 'subdivisions', 1 ), $record->{subdivisions}[1], 'an element of an array' );
    is_deeply( _value( $city, $ip ), $record, 'no path: the whole record' );
};

subtest 'a value that is not there is undef' => sub {
    my $ip = '2.125.160.216';
    is( _value( $city, $ip, 'nokey' ),                     undef, 'no such key' );
    is( _value( $city, $ip, qw( country names xx ) ),      undef, 'no such key at the end' );
    is( _value( $city, $ip, qw( country iso_code names ) ), undef, 'the path goes through a string' );
    is( _value( $city, $ip, qw( subdivisions x names ) ),  undef, 'the index is not a number' );
    is( _value( $city, '2001:218::1', qw( city names en ) ), undef, 'a record without the city' );
    is( _value( $city, '10.0.0.1', qw( country names en ) ), undef, 'no record' );
    is( _value( $city, '10.0.0.1' ), undef, 'no record, no path' );
};

subtest 'the same as the whole record' => sub {
    my @paths = (
        [qw( country names en )],
        [qw( country iso_code )],
        [qw( city names en )],
        [ 'subdivisions', 0, 'names', 'en' ],
        [qw( location latitude )],
        [qw( continent )],
    );
    my $follow = sub {
        my ( $data, @path ) = @_;
        for my $key (@path) {
            return undef unless ref $data;
            $data = ref $data eq 'ARRAY' ? $data->[$key] : $data->{$key};
        }
        return $data;
    };

    srand(7);
    my ( $found, $checked ) = ( 0, 0 );
    for ( 1 .. 3000 ) {
        my $ip = join '.', map { int rand 256 } 1 .. 4;
        # the addresses of the test database are in a few networks
        $ip = join '.', 2, 125, 160, int rand 256 if $_ % 3 == 0;
        $ip = join '.', 81, 2, 69, int rand 256   if $_ % 7 == 0;
        my $record = _record( $city, $ip ) || {};
        $found++ if %$record;
        for my $path (@paths) {
            $checked++;
            my $got      = _value( $city, $ip, @$path );
            my $expected = $follow->( $record, @$path );
            next if Dumper($got) eq Dumper($expected);
            fail("$ip @$path: " . Dumper($got) . ' instead of ' . Dumper($expected) );
            return;
        }
    }
    cmp_ok( $found, '>', 100, "$found addresses have a record" );
    pass("$checked values are the same as in the whole record");
};

subtest '__lookup_for_address: the value and the prefix length' => sub {
    my @r = _lookup( $city, '2.125.160.216', qw( city names en ) );
    is( scalar @r, 2, 'two values' );
    is( $r[0], 'Boxford', 'the value' );
    is( $r[1], 29,        'the length of the network (2.125.160.208/29)' );

    my @whole = _lookup( $city, '2.125.160.216' );
    is_deeply( $whole[0], _record( $city, '2.125.160.216' ), 'no path: the whole record' );
    is( $whole[1], 29, 'and the length' );

    my @v6 = _lookup( $city, '2001:218::1', qw( country iso_code ) );
    is_deeply( \@v6, [ 'JP', 32 ], 'an IPv6 address, the length is of 128 bits' );

    my @none = _lookup( $city, '10.0.0.1', 'country' );
    is_deeply( \@none, [ undef, undef ], 'no record: undef and undef' );

    my @nopath = _lookup( $city, '2.125.160.216', 'nokey' );
    is_deeply( \@nopath, [ undef, 29 ], 'no value in the record: undef and the length' );

    my $scalar = MaxMind::DB::Reader::onlyXS::__value_for_address( $city, '2.125.160.216', qw( city names en ) );
    is( $scalar, 'Boxford', '__value_for_address is one value in any context' );
    my @list = MaxMind::DB::Reader::onlyXS::__value_for_address( $city, '2.125.160.216', qw( city names en ) );
    is_deeply( \@list, ['Boxford'], 'and a list of one' );
};

subtest 'the prefix length is the one of the network in the tree' => sub {
    for my $file ( 'MaxMind-DB-test-ipv4-24.mmdb', 'MaxMind-DB-test-mixed-24.mmdb', 'MaxMind-DB-test-ipv6-24.mmdb' ) {
        my $mmdb    = _open($file);
        my $ip6     = MaxMind::DB::Reader::onlyXS::_raw_metadata($mmdb)->{ip_version} == 6;
        my $checked = 0;
        my @bad;
        MaxMind::DB::Reader::onlyXS::_iterate_search_tree(
            $mmdb,
            sub {
                my ( $number, $depth ) = @_;
                $number = "$number";
                if ( $number < 2**32 && ( !$ip6 || $depth > 96 ) ) {
                    my $ip = join '.', unpack 'C4', pack 'N', $number;
                    my $want = $ip6 ? $depth - 96 : $depth;
                    my ( undef, $got ) = _lookup( $mmdb, $ip );
                    push @bad, "$ip/$want: $got" unless defined $got && $got == $want;
                    $checked++;
                }
            },
            undef
        );
        is_deeply( \@bad, [], "$file: $checked IPv4 networks" ) or diag "@bad";
    }

    my $mmdb = _open('MaxMind-DB-test-ipv6-24.mmdb');
    is_deeply( [ _lookup( $mmdb, '::2:0:59' ) ], [ { ip => '::2:0:58' }, 127 ], 'IPv6 ::2:0:58/127' );

    # an IPv4 address in a database without the IPv4 part of the tree
    my $no4 = _open('MaxMind-DB-no-ipv4-search-tree.mmdb');
    my @r = _lookup( $no4, '1.1.1.1' );
    is_deeply( \@r, [ '::0/64', 0 ], 'the network is bigger than ::/96: the length is 0' );
};

subtest 'types of the values' => sub {
    my $decoder = _open('MaxMind-DB-test-decoder.mmdb');
    my $ip      = '::1.1.1.0';
    is( _value( $decoder, $ip, 'uint16' ), 100, 'uint16' );
    is( _value( $decoder, $ip, 'int32' ), -268435456, 'int32' );
    is( _value( $decoder, $ip, 'uint64' ), '1152921504606846976', 'uint64' );
    is( _value( $decoder, $ip, 'bytes' ), "\0\0\0*", 'bytes' );
    is_deeply( _value( $decoder, $ip, 'array' ), [ 1, 2, 3 ], 'array' );
    is( _value( $decoder, $ip, qw( map mapX utf8_stringX ) ), 'hello', 'a string deep in a map' );
    is( _value( $decoder, $ip, qw( map mapX arrayX 2 ) ), 9, 'an element of an array in a map' );
    is( ref( _value( $decoder, $ip, 'uint128' ) ), 'Math::UInt128', 'uint128 is a Math::UInt128' );
    is( "" . _value( $decoder, $ip, 'uint128' ), '1329227995784915872903807060280344576', 'and its value' );
};

{
    # a tied argument runs perl code while the arguments are read
    package Closer;
    sub TIESCALAR { my ( $class, $db, $value ) = @_; return bless [ $db, $value ], $class }
    sub FETCH     { my $self = shift; MaxMind::DB::Reader::onlyXS::_close_mmdb( $self->[0] ); return $self->[1] }
}

subtest 'a tied argument that closes the handle' => sub {
    for my $where (qw( ip path )) {
        my $db = _open('GeoIP2-City-Test.mmdb');
        tie my $tied, 'Closer', $db, $where eq 'ip' ? '2.125.160.216' : 'country';
        my @args = $where eq 'ip' ? ( $tied, 'country' ) : ( '2.125.160.216', $tied );
        like(
            _err( sub { MaxMind::DB::Reader::onlyXS::__value_for_address( $db, @args ) } ),
            qr/handle passed to __value_for_address\(\) is closed/,
            "closed by the $where: an error, not a crash"
        );
    }
};

subtest 'errors' => sub {
    my $ip = '2.125.160.216';
    like( _err( sub { _value( $city, 'garbage', 'country' ) } ), qr/not a valid IPv4 or IPv6 address/, 'invalid address' );
    like( _err( sub { _value( $city, '', 'country' ) } ), qr/You must provide an IP address/, 'empty address' );
    like( _err( sub { _lookup( $city, 'garbage' ) } ), qr/not a valid IPv4 or IPv6 address/, '__lookup_for_address: invalid address' );

    for my $name (qw( __data_for_address __value_for_address __lookup_for_address )) {
        my $sub = \&{"MaxMind::DB::Reader::onlyXS::$name"};
        like( _err( sub { $sub->( undef, $ip ) } ), qr/Invalid database handle passed to $name\(\)/, "$name( undef )" );
        like( _err( sub { $sub->( 'x' x 8, $ip ) } ), qr/Invalid database handle passed to $name\(\)/, "$name( string )" );
        like( _err( sub { $sub->( $city, "$ip\0junk" ) } ), qr/IP address contains a NUL byte/, "$name: NUL in the address" );
    }
    like( _err( sub { _value( $city, $ip, "country\0", 'names' ) } ), qr/path element contains a NUL byte/, 'NUL in the path' );
    like(
        _err( sub { MaxMind::DB::Reader::onlyXS::_open_mmdb( "$dir/GeoIP2-City-Test.mmdb\0junk", 1 ) } ),
        qr/file name contains a NUL byte/,
        'NUL in the file name'
    );

    my $closed = _open('GeoIP2-City-Test.mmdb');
    MaxMind::DB::Reader::onlyXS::_close_mmdb($closed);
    like( _err( sub { _value( $closed, $ip, 'country' ) } ), qr/handle passed to __value_for_address\(\) is closed/, 'closed handle' );
};

done_testing;
