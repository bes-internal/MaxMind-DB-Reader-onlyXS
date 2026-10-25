use strict;
use warnings;

use Test::More;
use File::Spec;

use MaxMind::DB::Reader::onlyXS;

my $dir = File::Spec->catdir( 'maxmind-db', 'test-data' );

plan skip_all => 'maxmind-db submodule is not checked out (git submodule update --init)'
    unless -d $dir;

sub _open { MaxMind::DB::Reader::onlyXS::_open_mmdb( File::Spec->catfile( $dir, shift ), 0 ) }
sub _rec  { MaxMind::DB::Reader::onlyXS::__data_for_address(@_) }
sub _meta { MaxMind::DB::Reader::onlyXS::_raw_metadata(@_) }
sub _err  { my $c = shift; eval { $c->(); 1 } ? '' : $@ }

ok( MaxMind::DB::Reader::onlyXS::libmaxminddb_version(), 'libmaxminddb_version' );
diag( 'libmaxminddb ' . MaxMind::DB::Reader::onlyXS::libmaxminddb_version() );

# IPv4 databases, every record size
for my $size ( 24, 28, 32 ) {
    subtest "ipv4-$size" => sub {
        my $mmdb = _open("MaxMind-DB-test-ipv4-$size.mmdb");
        my $meta = _meta($mmdb);
        is( $meta->{ip_version},  4,     'ip_version' );
        is( $meta->{record_size}, $size, 'record_size' );
        is( $meta->{database_type}, 'Test', 'database_type' );

        is_deeply( _rec( $mmdb, '1.1.1.1' ),  { ip => '1.1.1.1' }, '1.1.1.1' );
        is_deeply( _rec( $mmdb, '1.1.1.3' ),  { ip => '1.1.1.2' }, '1.1.1.3 in 1.1.1.2/31' );
        is_deeply( _rec( $mmdb, '1.1.1.32' ), { ip => '1.1.1.32' }, '1.1.1.32' );
        is( _rec( $mmdb, '1.1.1.33' ), undef, 'no record for 1.1.1.33' );
        like(
            _err( sub { _rec( $mmdb, '2001::1' ) } ),
            qr/IPv6 address in an IPv4-only database/,
            'IPv6 lookup in IPv4 database croaks'
        );
        MaxMind::DB::Reader::onlyXS::_close_mmdb($mmdb);
    };
}

# IPv6 databases, every record size
for my $size ( 24, 28, 32 ) {
    subtest "ipv6-$size" => sub {
        my $mmdb = _open("MaxMind-DB-test-ipv6-$size.mmdb");
        my $meta = _meta($mmdb);
        is( $meta->{ip_version},  6,     'ip_version' );
        is( $meta->{record_size}, $size, 'record_size' );

        is_deeply( _rec( $mmdb, '::1:ffff:ffff' ), { ip => '::1:ffff:ffff' }, '::1:ffff:ffff' );
        is_deeply( _rec( $mmdb, '::2:0:0' ),       { ip => '::2:0:0' },       '::2:0:0' );
        is_deeply( _rec( $mmdb, '::2:0:59' ),      { ip => '::2:0:58' },      '::2:0:59 in ::2:0:58/125' );
        is( _rec( $mmdb, '::1:ffff:fffe' ), undef, 'no record for ::1:ffff:fffe' );
        is( _rec( $mmdb, '2001::1' ),       undef, 'no record for 2001::1' );
        MaxMind::DB::Reader::onlyXS::_close_mmdb($mmdb);
    };
}

# Mixed IPv4 and IPv6 databases, every record size
for my $size ( 24, 28, 32 ) {
    subtest "mixed-$size" => sub {
        my $mmdb = _open("MaxMind-DB-test-mixed-$size.mmdb");
        my $meta = _meta($mmdb);
        is( $meta->{ip_version},  6,     'ip_version' );
        is( $meta->{record_size}, $size, 'record_size' );

        is_deeply( _rec( $mmdb, '1.1.1.1' ),  { ip => '::1.1.1.1' },  'IPv4 1.1.1.1' );
        is_deeply( _rec( $mmdb, '1.1.1.3' ),  { ip => '::1.1.1.2' },  'IPv4 1.1.1.3' );
        is_deeply( _rec( $mmdb, '::2:0:59' ), { ip => '::2:0:58' },   'IPv6 ::2:0:59' );
        is( _rec( $mmdb, '1.1.1.33' ), undef, 'no record for 1.1.1.33' );
        MaxMind::DB::Reader::onlyXS::_close_mmdb($mmdb);
    };
}

subtest 'decoder: every data type' => sub {
    my $mmdb = _open('MaxMind-DB-test-decoder.mmdb');
    is( _meta($mmdb)->{database_type}, 'MaxMind DB Decoder Test', 'database_type' );

    my $r = _rec( $mmdb, '::1.1.1.0' );
    is_deeply( $r->{array}, [ 1, 2, 3 ], 'array' );
    ok( $r->{boolean}, 'boolean' );
    is( $r->{bytes}, "\0\0\0*", 'bytes' );
    is( $r->{double}, 42.123456, 'double' );
    ok( abs( $r->{float} - 1.1 ) < 1e-6, 'float' );
    is( $r->{int32},  -268435456, 'int32' );
    is_deeply(
        $r->{map},
        { mapX => { arrayX => [ 7, 8, 9 ], utf8_stringX => 'hello' } },
        'map'
    );
    is( "$r->{uint16}", 100,                  'uint16' );
    is( "$r->{uint32}", 268435456,            'uint32' );
    is( "$r->{uint64}", '1152921504606846976', 'uint64' );
    is( "$r->{uint128}", '1329227995784915872903807060280344576', 'uint128 (2**120)' );
    is( $r->{utf8_string}, "unicode! \x{262f} - \x{266b}", 'utf8_string' );
    ok( utf8::is_utf8( $r->{utf8_string} ), 'utf8_string has the utf8 flag' );
};

subtest 'nested structures' => sub {
    my $mmdb = _open('MaxMind-DB-test-nested.mmdb');
    is_deeply(
        _rec( $mmdb, '::1.1.1.1' ),
        { map1 => { map2 => { array => [ { map3 => { a => 1, b => 2, c => 3 } } ] } } },
        'nested map/array/map'
    );
};

subtest 'GeoIP2 City' => sub {
    my $mmdb = _open('GeoIP2-City-Test.mmdb');
    my $r    = _rec( $mmdb, '2.125.160.216' );
    is( $r->{city}{names}{en},  'Boxford', 'city name' );
    is( $r->{country}{iso_code}, 'GB',      'country iso_code' );
    ok( $r->{country}{is_in_european_union}, 'boolean' );
    is( $r->{continent}{names}{ja}, "\x{30e8}\x{30fc}\x{30ed}\x{30c3}\x{30d1}", 'utf8 name' );
};

subtest 'metadata with pointers' => sub {
    my $meta = _meta( _open('MaxMind-DB-test-metadata-pointers.mmdb') );
    is( $meta->{database_type}, 'Lots of pointers in metadata', 'database_type' );
    is_deeply( $meta->{languages}, [ 'en', 'es', 'zh' ], 'languages' );
    is_deeply(
        $meta->{description},
        { map { $_ => 'Lots of pointers in metadata' } qw( en es zh ) },
        'description'
    );
};

subtest 'string value entries' => sub {
    my $mmdb = _open('MaxMind-DB-string-value-entries.mmdb');
    is( _rec( $mmdb, '1.1.1.1' ), '1.1.1.1/32', 'string record' );
    is( _rec( $mmdb, '1.1.1.2' ), '1.1.1.2/31', 'string record in /31' );
};

subtest 'no IPv4 search tree' => sub {
    my $mmdb = _open('MaxMind-DB-no-ipv4-search-tree.mmdb');
    is( _meta($mmdb)->{ip_version}, 6, 'ip_version' );
    is( _rec( $mmdb, '::1.1.1.1' ), '::0/64', 'IPv6 address' );
    is( _rec( $mmdb, '1.1.1.1' ),   '::0/64', 'IPv4 address falls into ::/64' );
};

subtest 'broken databases' => sub {
    my $ptr = _open('MaxMind-DB-test-broken-pointers-24.mmdb');
    is_deeply( _rec( $ptr, '1.1.1.1' ), { ip => '1.1.1.1' }, 'good record is readable' );
    like(
        _err( sub { _rec( $ptr, '1.1.1.16' ) } ),
        qr/Entry data error looking up "1\.1\.1\.16"/,
        'broken pointer croaks'
    );

    like(
        _err( sub { _open('GeoIP2-City-Test-Invalid-Node-Count.mmdb') } ),
        qr/Error opening database file .*invalid metadata/,
        'invalid node count croaks on open'
    );
};

subtest 'errors' => sub {
    my $mmdb = _open('MaxMind-DB-test-ipv4-24.mmdb');
    like( _err( sub { _rec( $mmdb, 'not-an-ip' ) } ), qr/not a valid IPv4 or IPv6 address/, 'invalid address' );
    like( _err( sub { _rec( $mmdb, '' ) } ), qr/You must provide an IP address/, 'empty address' );
    like(
        _err( sub { MaxMind::DB::Reader::onlyXS::_open_mmdb( "$dir/no-such.mmdb", 0 ) } ),
        qr/Error opening database file/,
        'missing file'
    );
};

subtest '_iterate_search_tree' => sub {
    my $mmdb = _open('MaxMind-DB-test-decoder.mmdb');
    my ( $data, $nodes ) = ( 0, 0 );
    MaxMind::DB::Reader::onlyXS::_iterate_search_tree( $mmdb, sub { $data++ }, sub { $nodes++ } );
    cmp_ok( $data,  '>', 0, 'data callback called' );
    cmp_ok( $nodes, '>', 0, 'node callback called' );
};

done_testing;
