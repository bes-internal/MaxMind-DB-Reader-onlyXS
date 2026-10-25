#!perl
# Compares the cost of using MaxMind::DB::Reader (pure Perl and with
# MaxMind::DB::Reader::XS) and MaxMind::DB::Reader::onlyXS in a CGI script:
#
#   cold - a fresh perl process loads the module, opens the database and makes
#          one lookup (this is what every CGI request does); the number of
#          loaded modules is the size of %INC at the end, nothing else is
#          loaded by the measured process
#   warm - lookups per second in a process that has everything loaded
#
# Setup (the comparison modules are not dependencies of this distribution):
#   perl dev/dev.pl
#   cpm install -L dev/local-bench MaxMind::DB::Reader MaxMind::DB::Reader::XS
#   perl dev/exec.pl ./Build
# Run:
#   perl dev/bench.pl [--runs 200] [--seconds 3] [database.mmdb]
use strict;
use warnings;
use Cwd 'abs_path';
use File::Temp 'tempdir';
use FindBin;
use Getopt::Long;
use Time::HiRes qw( clock_gettime CLOCK_MONOTONIC );

sub now { clock_gettime(CLOCK_MONOTONIC) }

my $root = abs_path("$FindBin::Bin/..");

my %impl = (
    reader_pp => {
        name => 'MaxMind::DB::Reader (pure Perl)',
        env  => { MAXMIND_DB_READER_IMPLEMENTATION => 'PP' },
        code => q{
            require MaxMind::DB::Reader;
            my $r = MaxMind::DB::Reader->new( file => $file );
            $lookup = sub { eval { $r->record_for_address( $_[0] ) } };
        },
    },
    reader_xs => {
        name => 'MaxMind::DB::Reader::XS',
        env  => { MAXMIND_DB_READER_IMPLEMENTATION => 'XS' },
        code => q{
            require MaxMind::DB::Reader;
            my $r = MaxMind::DB::Reader->new( file => $file );
            $lookup = sub { eval { $r->record_for_address( $_[0] ) } };
        },
    },
    onlyxs => {
        name => 'MaxMind::DB::Reader::onlyXS',
        env  => {},
        code => q{
            require MaxMind::DB::Reader::onlyXS;
            my $h = MaxMind::DB::Reader::onlyXS::_open_mmdb( $file, 1 );
            $lookup = sub {
                eval { MaxMind::DB::Reader::onlyXS::__data_for_address( $h, $_[0] ) };
            };
        },
    },
    baseline => {
        name => 'perl -e1 (baseline)',
        env  => {},
        code => q{ $lookup = sub { undef }; },
    },
);
my @order = qw( baseline reader_pp reader_xs onlyxs );

my ( $runs, $seconds ) = ( 200, 3 );
GetOptions( 'runs=i' => \$runs, 'seconds=i' => \$seconds ) or die "bad options\n";
my $file = shift @ARGV // "$root/maxmind-db/test-data/GeoIP2-City-Test.mmdb";
die "No database $file\n" unless -f $file;
die "Run ./Build first (blib/ is missing)\n" unless -d "$root/blib/arch";

# The module is installed into a temporary directory like "make install"
# does: with the .so next to the .pm XSLoader works without DynaLoader and
# Config, as it does in a CGI script.
my $tmp = tempdir( CLEANUP => 1 );
system( 'cp', '-r', "$root/blib/lib/.", "$root/blib/arch/.", $tmp ) == 0 or die "cp failed\n";
my @lib = ( $tmp, "$root/dev/local-bench/lib/perl5", "$root/dev/local/lib/perl5" );

# The measured process is a plain script that loads nothing but the module.
sub script {
    my ( $i, $mode ) = @_;
    my $code = $impl{$i}{code};
    my $run
        = $mode eq 'cold'
        ? q{
            $lookup->('2.125.160.216');
            open my $fh, '<', '/proc/self/status' or die $!;
            my ($rss) = map { /^VmRSS:\s+(\d+)/ ? $1 : () } <$fh>;
            print scalar( keys %INC ), " ", $rss // 0, "\n";
        }
        : q{
            require Time::HiRes;
            srand(42);
            my @ips = map { join '.', map { int rand 256 } 1 .. 4 } 1 .. 5000;
            my $t = Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC());
            my ( $n, $end ) = ( 0, $t + $ARGV[1] );
            while ( Time::HiRes::clock_gettime(Time::HiRes::CLOCK_MONOTONIC()) < $end ) {
                $lookup->( $ips[ $n++ % @ips ] ) for 1 .. 100;
            }
            print $n, " ", $ARGV[1], "\n";
        };
    my $path = "$tmp/child-$i-$mode.pl";
    open my $fh, '>', $path or die $!;
    print $fh 'my $file = $ARGV[0]; my $lookup;', $code, $run;
    close $fh;
    return $path;
}

sub child {
    my ( $i, $mode ) = @_;
    local %ENV = ( %ENV, %{ $impl{$i}{env} }, PERL5LIB => join( ':', @lib ) );
    my $out = `$^X @{[ script( $i, $mode ) ]} '$file' $seconds`;
    die "child $i/$mode failed\n" if $?;
    return split ' ', $out;
}

print scalar( localtime ), "\n";
my ($os, $arch) = split ' ', `uname -sm`;
printf "perl %vd, %s %s, %d cold runs per implementation\ndatabase %s\n", $^V, $os, $arch, $runs, $file;
{
    local $ENV{PERL5LIB} = join ':', @lib;
    my $v = `$^X -MMaxMind::DB::Reader::onlyXS -e 'print MaxMind::DB::Reader::onlyXS::libmaxminddb_version()'`;
    print "libmaxminddb $v\n\n";
}

my %cold;
for my $i (@order) {
    child( $i, 'cold' );    # warm the disk cache
    my ( @t, $mods, $rss );
    for ( 1 .. $runs ) {
        my $t0 = now();
        ( $mods, $rss ) = child( $i, 'cold' );
        push @t, ( now() - $t0 ) * 1000;
    }
    @t = sort { $a <=> $b } @t;
    $cold{$i} = { median => $t[ @t / 2 ], min => $t[0], mods => $mods, rss => $rss };
}

print "COLD: new process, load module, open database, one lookup\n";
printf "%-34s %9s %9s %9s %8s\n", '', 'median ms', 'min ms', 'modules', 'RSS MB';
my $base = $cold{baseline}{median};
for my $i (@order) {
    my $c = $cold{$i};
    printf "%-34s %9.1f %9.1f %9d %8.1f%s\n", $impl{$i}{name}, $c->{median}, $c->{min},
        $c->{mods}, $c->{rss} / 1024,
        $i eq 'baseline' ? '' : sprintf( '   (+%.1f ms over baseline)', $c->{median} - $base );
}

print "\nWARM: lookups per second in one process ($seconds s each, random IPv4)\n";
for my $i ( grep { $_ ne 'baseline' } @order ) {
    my ( $n, $s ) = child( $i, 'warm' );
    printf "%-34s %12.0f /s\n", $impl{$i}{name}, $n / $s;
}
