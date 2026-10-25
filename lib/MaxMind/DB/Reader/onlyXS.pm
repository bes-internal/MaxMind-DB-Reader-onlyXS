package MaxMind::DB::Reader::onlyXS;

# ABSTRACT: Fast XS implementation of MaxMind DB reader

our $VERSION = '1.000010'; # VERSION

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

=head2 _raw_metadata( $handle )

Returns the metadata of the database as a hash reference (C<node_count>,
C<record_size>, C<ip_version>, C<database_type>, C<languages>, C<description>,
C<build_epoch>, ...).

=head2 _iterate_search_tree( $handle, $data_callback, $node_callback )

Walks the whole search tree. C<$data_callback> is called for every record
with the first IP of the network as a L<Math::UInt128>, the prefix length and the
record. C<$node_callback> is called for every node with the node number and
the left and right records. Either of them can be undef.

=head2 __read_node( $handle, $node_number )

Returns the left and the right record of the node.

=head2 libmaxminddb_version()

Returns the version of the libmaxminddb the module is linked with.

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
