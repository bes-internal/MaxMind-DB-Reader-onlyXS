use strict;
use warnings;

use Test::More;
use File::Spec;

BEGIN {
    plan skip_all => 'Test::LeakTrace is required (cpm install -L dev/local Test::LeakTrace)'
        unless eval { require Test::LeakTrace; Test::LeakTrace->import; 1 };
}

use MaxMind::DB::Reader::onlyXS;

my $dir = File::Spec->catdir( 'maxmind-db', 'test-data' );
plan skip_all => 'maxmind-db submodule is not checked out' unless -d $dir;

sub _file { File::Spec->catfile( $dir, shift ) }

my $city    = MaxMind::DB::Reader::onlyXS::_open_mmdb( _file('GeoIP2-City-Test.mmdb'), 1 );
my $decoder = MaxMind::DB::Reader::onlyXS::_open_mmdb( _file('MaxMind-DB-test-decoder.mmdb'), 1 );

# the first call loads Math::Int128 and creates what is cached for good
MaxMind::DB::Reader::onlyXS::__data_for_address( $decoder, '::1.1.1.0' );

no_leaks_ok {
    MaxMind::DB::Reader::onlyXS::__data_for_address( $city, '2.125.160.216' );
}
'record_for_address of a city';

no_leaks_ok {
    MaxMind::DB::Reader::onlyXS::__data_for_address( $city, '10.0.0.1' );
}
'address that is not in the database';

no_leaks_ok {
    MaxMind::DB::Reader::onlyXS::__data_for_address( $decoder, '::1.1.1.0' );
}
'every data type, including uint128';

no_leaks_ok {
    eval { MaxMind::DB::Reader::onlyXS::__data_for_address( $city, 'garbage' ) };
}
'croak on an invalid address';

no_leaks_ok {
    eval { MaxMind::DB::Reader::onlyXS::__data_for_address( undef, '1.2.3.4' ) };
}
'croak on an invalid handle';

no_leaks_ok { MaxMind::DB::Reader::onlyXS::_raw_metadata($city) } 'metadata';

no_leaks_ok {
    MaxMind::DB::Reader::onlyXS::_iterate_search_tree( $decoder, sub { }, sub { } );
}
'_iterate_search_tree';

no_leaks_ok {
    my $h = MaxMind::DB::Reader::onlyXS::_open_mmdb( _file('GeoIP2-City-Test.mmdb'), 1 );
    MaxMind::DB::Reader::onlyXS::__data_for_address( $h, '2.125.160.216' );
    MaxMind::DB::Reader::onlyXS::_close_mmdb($h);
}
'open, lookup and close';

no_leaks_ok {
    my $h = MaxMind::DB::Reader::onlyXS::_open_mmdb( _file('GeoIP2-City-Test.mmdb'), 1 );
}
'open and free the handle without _close_mmdb';

done_testing;
