use strict;
use warnings;

use Test::More;

# Optional: the same calls on a real (big) City database, e.g.
#   MMDB_REAL=/usr/share/GeoIP/GeoLite2-City.mmdb ./Build test

my $file = $ENV{MMDB_REAL};
plan skip_all => 'set MMDB_REAL to a GeoIP2/GeoLite2 City database to run this test'
    unless $file && -f $file;

require MaxMind::DB::Reader::onlyXS;

my $db = MaxMind::DB::Reader::onlyXS::_open_mmdb( $file, 1 );
ok( $db, "opened $file" );

my $meta = MaxMind::DB::Reader::onlyXS::_raw_metadata($db);
diag "$meta->{database_type}, ip_version $meta->{ip_version}, record_size $meta->{record_size}, "
    . "$meta->{node_count} nodes, built " . localtime( $meta->{build_epoch} );
like( $meta->{database_type}, qr/City/i, 'a City database' );

my $r = MaxMind::DB::Reader::onlyXS::__data_for_address( $db, '8.8.8.8' );
is( ref $r, 'HASH', '8.8.8.8 has a record' );
is( $r->{country}{iso_code}, 'US', 'country of 8.8.8.8' );
like( $r->{country}{names}{en}, qr/United States/, 'country name' );
ok( $r->{continent}{names}{en}, 'continent' );

for my $ip ( '2001:4860:4860::8888', '::ffff:8.8.8.8' ) {
    my $v6 = eval { MaxMind::DB::Reader::onlyXS::__data_for_address( $db, $ip ) };
    is( $@, '', "$ip does not die" ) if $meta->{ip_version} == 6;
}

# private addresses are not in the database
is( MaxMind::DB::Reader::onlyXS::__data_for_address( $db, '10.0.0.1' ), undef, '10.0.0.1' );
is( MaxMind::DB::Reader::onlyXS::__data_for_address( $db, '192.168.1.1' ), undef, '192.168.1.1' );

# many random addresses: never dies, always a hash or undef
srand(1);
my ( $found, $total ) = ( 0, 20000 );
for ( 1 .. $total ) {
    my $ip = join '.', map { int rand 256 } 1 .. 4;
    my $rec = eval { MaxMind::DB::Reader::onlyXS::__data_for_address( $db, $ip ) };
    if ($@) { fail("$ip died: $@"); last }
    $found++ if $rec;
    if ( $rec && ref $rec ne 'HASH' ) { fail("$ip: $rec"); last }
}
ok( $found > 0, "$found of $total random addresses have a record" );

done_testing;
