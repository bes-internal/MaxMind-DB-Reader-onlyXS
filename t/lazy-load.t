use Test::More;
use File::Spec;

# The module is used from CGI scripts: loading it must not pull in other
# modules, Math::Int128 is loaded only when a uint128 value is decoded.

my $dir = File::Spec->catdir( 'maxmind-db', 'test-data' );
plan skip_all => 'maxmind-db submodule is not checked out (git submodule update --init)'
    unless -d $dir;

my %before = %INC;
require MaxMind::DB::Reader::onlyXS;
my @loaded = sort grep { !$before{$_} } keys %INC;

# XSLoader (and strict, which it loads) are the only allowed dependencies;
# under blib/ XSLoader falls back to DynaLoader, which brings Config and vars
is_deeply(
    [ grep { $_ !~ m{^(?:MaxMind/DB/Reader/onlyXS|XSLoader|strict|DynaLoader|Config|vars)\.pm$} } @loaded ],
    [], 'loading the module loads nothing else'
) or diag "@loaded";

sub _lookup {
    my ( $file, $ip ) = @_;
    my $mmdb = MaxMind::DB::Reader::onlyXS::_open_mmdb( File::Spec->catfile( $dir, $file ), 1 );
    return MaxMind::DB::Reader::onlyXS::__data_for_address( $mmdb, $ip );
}

is( _lookup( 'GeoIP2-City-Test.mmdb', '2.125.160.216' )->{country}{iso_code}, 'GB', 'lookup works' );
ok( !$INC{'Math/Int128.pm'}, 'Math::Int128 is not loaded by a lookup without uint128' );
ok( !$INC{'Math/Int64.pm'},  'Math::Int64 is not loaded' );

my $r = _lookup( 'MaxMind-DB-test-decoder.mmdb', '::1.1.1.0' );
ok( $INC{'Math/Int128.pm'}, 'Math::Int128 is loaded on the first uint128' );
is( "$r->{uint128}", '1329227995784915872903807060280344576', 'uint128 value' );

done_testing;
