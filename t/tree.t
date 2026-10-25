use strict;
use warnings;

use Test::More;
use File::Spec;

use MaxMind::DB::Reader::onlyXS;

my $dir = File::Spec->catdir( 'maxmind-db', 'test-data' );
plan skip_all => 'maxmind-db submodule is not checked out (git submodule update --init)'
    unless -d $dir;

sub _open { MaxMind::DB::Reader::onlyXS::_open_mmdb( File::Spec->catfile( $dir, shift ), 1 ) }
sub _meta { MaxMind::DB::Reader::onlyXS::_raw_metadata(@_) }
sub _node { MaxMind::DB::Reader::onlyXS::__read_node(@_) }
sub _walk { MaxMind::DB::Reader::onlyXS::_iterate_search_tree(@_) }
sub _err  { my $c = shift; eval { $c->(); 1 } ? '' : $@ }

# the networks of the test databases: ip, prefix length, record
sub _data {
    my $mmdb = shift;
    my @data;
    _walk( $mmdb, sub { push @data, [ $_[0], $_[1], $_[2] ] }, undef );
    return @data;
}

subtest 'IPv4 database: data callback' => sub {
    my $mmdb = _open('MaxMind-DB-test-ipv4-24.mmdb');
    my @data = _data($mmdb);

    is( scalar @data, 6, 'one call for every network' );
    is( ref $data[0][0], 'Math::UInt128', 'the first address is a Math::UInt128' );

    # 1.1.1.1/32 1.1.1.2/31 1.1.1.4/30 1.1.1.8/29 1.1.1.16/28 1.1.1.32/32
    is_deeply(
        [ map { [ "$_->[0]", $_->[1], $_->[2]{ip} ] } @data ],
        [
            [ 16843009, 32, '1.1.1.1' ],
            [ 16843010, 31, '1.1.1.2' ],
            [ 16843012, 30, '1.1.1.4' ],
            [ 16843016, 29, '1.1.1.8' ],
            [ 16843024, 28, '1.1.1.16' ],
            [ 16843040, 32, '1.1.1.32' ],
        ],
        'address, prefix length and record of every network'
    );
};

subtest 'IPv6 database: data callback' => sub {
    my $mmdb = _open('MaxMind-DB-test-ipv6-24.mmdb');
    my @data = _data($mmdb);

    is_deeply(
        [ map { [ "$_->[0]", $_->[1], $_->[2]{ip} ] } @data ],
        [
            [ '8589934591', 128, '::1:ffff:ffff' ],
            [ '8589934592', 122, '::2:0:0' ],
            [ '8589934656', 124, '::2:0:40' ],
            [ '8589934672', 125, '::2:0:50' ],
            [ '8589934680', 127, '::2:0:58' ],
        ],
        'IPv6 networks, the prefix length is up to 128'
    );
};

subtest 'string records and a tree without the IPv4 part' => sub {
    my @data = _data( _open('MaxMind-DB-no-ipv4-search-tree.mmdb') );
    is( scalar @data, 1, 'one network' );
    is( "$data[0][0]", '0',      'the first address' );
    is( $data[0][1],   64,       'prefix length' );
    is( $data[0][2],   '::0/64', 'the record is a string' );
};

subtest 'node callback' => sub {
    for my $file ( 'MaxMind-DB-test-ipv4-24.mmdb', 'MaxMind-DB-test-ipv6-24.mmdb' ) {
        my $mmdb       = _open($file);
        my $node_count = _meta($mmdb)->{node_count};

        my @nodes;
        _walk( $mmdb, undef, sub { push @nodes, [@_] } );
        cmp_ok( scalar @nodes, '>=', $node_count, "$file: every node is visited" );

        is( $nodes[0][0], 0, "$file: the walk starts at the root" );
        is( scalar @{ $nodes[0] }, 3, "$file: node number, left and right records" );

        my $same = 1;
        for my $n (@nodes) {
            my ( $number, $left, $right ) = @$n;
            my @read = _node( $mmdb, $number );
            $same = 0 unless "@read" eq "$left $right";
        }
        ok( $same, "$file: the records are the ones __read_node returns" );

        my %seen = map { $_->[0] => 1 } @nodes;
        is( scalar keys %seen, $node_count, "$file: all $node_count nodes are different" );
    }
};

subtest 'callbacks are optional' => sub {
    my $mmdb = _open('MaxMind-DB-test-ipv4-24.mmdb');

    my ( $data, $nodes ) = ( 0, 0 );
    _walk( $mmdb, sub { $data++ }, undef );
    is( $data, 6, 'only the data callback' );

    _walk( $mmdb, undef, sub { $nodes++ } );
    is( $nodes, 164, 'only the node callback' );

    is( _err( sub { _walk( $mmdb, undef, undef ) } ), '', 'no callbacks' );
};

subtest 'a callback that dies' => sub {
    my $mmdb = _open('MaxMind-DB-test-ipv4-24.mmdb');

    my $calls = 0;
    like( _err( sub { _walk( $mmdb, sub { $calls++; die "stop\n" }, undef ) } ), qr/^stop$/, 'data callback' );
    is( $calls, 1, 'the walk stopped at once' );

    like( _err( sub { _walk( $mmdb, undef, sub { die "stop nodes\n" } ) } ), qr/^stop nodes$/, 'node callback' );

    is( scalar( () = _data($mmdb) ), 6, 'the handle is still usable' );
};

subtest '__read_node' => sub {
    my $mmdb       = _open('MaxMind-DB-test-ipv4-24.mmdb');
    my $node_count = _meta($mmdb)->{node_count};

    my @root = _node( $mmdb, 0 );
    is( scalar @root, 2, 'two records' );
    is_deeply( [ _node( $mmdb, $node_count - 1 ) ], [ _node( $mmdb, $node_count - 1 ) ], 'the last node' );

    # a record is a node number, $node_count (empty) or a data pointer
    my ($nodes, $empty, $data) = (0, 0, 0);
    for my $n ( 0 .. $node_count - 1 ) {
        for my $r ( _node( $mmdb, $n ) ) {
            if    ( $r < $node_count )  { $nodes++ }
            elsif ( $r == $node_count ) { $empty++ }
            else                        { $data++ }
        }
    }
    is( $data, 6, 'six records point to data' );
    is( $nodes + $empty + $data, 2 * $node_count, 'two records in every node' );

    # libmaxminddb 1.9 accepts $node_count itself, so take the next one
    my $missing = $node_count + 1;
    like( _err( sub { _node( $mmdb, $missing ) } ),
        qr/Error trying to read node $missing: .*does not exist/, 'a node that does not exist' );
    like( _err( sub { _node( $mmdb, 4294967295 ) } ),
        qr/Error trying to read node 4294967295:/, 'the node number is printed as unsigned' );
};

subtest 'broken databases' => sub {
    my $tree = _open('MaxMind-DB-test-broken-search-tree-24.mmdb');
    like( _err( sub { _walk( $tree, sub { }, sub { } ) } ), qr/Invalid record when reading node/, 'broken search tree' );

    my $ptr = _open('MaxMind-DB-test-broken-pointers-24.mmdb');
    like( _err( sub { _walk( $ptr, sub { }, sub { } ) } ), qr/Entry data error looking at offset \d+: .*bad data/, 'broken pointer' );
};

subtest 'only a valid handle' => sub {
    my $closed = _open('MaxMind-DB-test-ipv4-24.mmdb');
    MaxMind::DB::Reader::onlyXS::_close_mmdb($closed);

    my %call = (
        _raw_metadata        => sub { _meta( $_[0] ) },
        __read_node          => sub { _node( $_[0], 0 ) },
        _iterate_search_tree => sub { _walk( $_[0], sub { }, sub { } ) },
    );
    for my $name ( sort keys %call ) {
        like( _err( sub { $call{$name}->(undef) } ),   qr/Invalid database handle passed to $name\(\)/, "$name( undef )" );
        like( _err( sub { $call{$name}->('x' x 8) } ), qr/Invalid database handle passed to $name\(\)/, "$name( string )" );
        like( _err( sub { $call{$name}->($closed) } ), qr/handle passed to $name\(\) is closed/,        "$name( closed handle )" );
    }
};

done_testing;
