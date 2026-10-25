package MaxMind::DB::Reader::onlyXS;

# ABSTRACT: Fast XS implementation of MaxMind DB reader

use strict;
use warnings;

our $VERSION = '1.000010'; # VERSION

use 5.010000;

# We depend on these in the C/XS code.
use Math::Int64  ();
use Math::Int128 ();

use XSLoader;

XSLoader::load( __PACKAGE__, $VERSION );

1;

__END__

=head1 SYNOPSIS

    my $db_fh = MaxMind::DB::Reader::onlyXS::_open_mmdb( 'path/to/database.mmdb', $flags );

    my $record = MaxMind::DB::Reader::onlyXS::__data_for_address( $db_fh, '1.2.3.4' );;

=head1 DESCRIPTION

Fast XS implementation of MaxMind DB reader without OO wrapers

The XS implementation links against the
L<libmaxminddb|http://maxmind.github.io/libmaxminddb/> library.

