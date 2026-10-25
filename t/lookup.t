use strict;
use warnings;

use Test::More;
use File::Spec;

use MaxMind::DB::Reader::onlyXS;

my $dir  = File::Spec->catdir( 'maxmind-db', 'test-data' );
my $file = File::Spec->catfile( $dir, 'MaxMind-DB-test-ipv4-24.mmdb' );

plan skip_all => 'maxmind-db submodule is not checked out (git submodule update --init)'
    unless -f $file;

ok( MaxMind::DB::Reader::onlyXS::libmaxminddb_version(), 'libmaxminddb_version' );

my $mmdb = MaxMind::DB::Reader::onlyXS::_open_mmdb( $file, 0 );
ok( $mmdb, '_open_mmdb returns a handle' );

my $meta = MaxMind::DB::Reader::onlyXS::_raw_metadata($mmdb);
is( $meta->{ip_version},    4,  'metadata ip_version' );
is( $meta->{record_size},   24, 'metadata record_size' );
is( $meta->{database_type}, 'Test', 'metadata database_type' );

is_deeply(
    MaxMind::DB::Reader::onlyXS::__data_for_address( $mmdb, '1.1.1.1' ),
    { ip => '1.1.1.1' },
    'record for 1.1.1.1',
);
is_deeply(
    MaxMind::DB::Reader::onlyXS::__data_for_address( $mmdb, '1.1.1.3' ),
    { ip => '1.1.1.2' },
    'record for 1.1.1.3 is the one of 1.1.1.2/31',
);
is(
    MaxMind::DB::Reader::onlyXS::__data_for_address( $mmdb, '1.1.1.33' ),
    undef,
    'no record for 1.1.1.33',
);

like(
    eval { MaxMind::DB::Reader::onlyXS::__data_for_address( $mmdb, 'not-an-ip' ); 1 }
    ? '' : $@,
    qr/not a valid IPv4 or IPv6 address/,
    'invalid address croaks',
);
like(
    eval { MaxMind::DB::Reader::onlyXS::_open_mmdb( "$dir/no-such.mmdb", 0 ); 1 }
    ? '' : $@,
    qr/Error opening database file/,
    'missing file croaks',
);

MaxMind::DB::Reader::onlyXS::_close_mmdb($mmdb);

done_testing;
