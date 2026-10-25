#!perl
# Builds the given libmaxminddb versions into dev/local-libmaxminddb/<version>
# and runs the tests of this module against each of them:
#   perl dev/test-libmaxminddb.pl 1.9.1 1.14.1
# Run it after "perl dev/dev.pl" (needs dev/local for Math::Int64 etc.).
# The module is built in a copy of the repository, the working tree stays clean.
use strict;
use warnings;
use Cwd 'abs_path';
use File::Path 'make_path';
use File::Temp 'tempdir';
use FindBin;

my $root = abs_path("$FindBin::Bin/..");
my $base = "$root/dev/local-libmaxminddb";
my @versions = @ARGV or die "Usage: perl dev/test-libmaxminddb.pl version [version ...]\n";

sub run {
    my ( $dir, @cmd ) = @_;
    chdir $dir or die "chdir $dir: $!\n";
    system(@cmd) == 0 or die "Failed (in $dir): @cmd\n";
}

sub install_lib {
    my $v      = shift;
    my $prefix = "$base/$v/prefix";
    return $prefix if -f "$prefix/lib/libmaxminddb.so";

    make_path("$base/$v");
    my $url = "https://github.com/maxmind/libmaxminddb/releases/download/$v/libmaxminddb-$v.tar.gz";
    run( "$base/$v", 'curl', '-fsSL', '-o', 'src.tar.gz', $url );
    run( "$base/$v", 'tar', 'xzf', 'src.tar.gz' );
    my $src = "$base/$v/libmaxminddb-$v";
    run( $src, './configure', "--prefix=$prefix", '--quiet' );
    run( $src, 'make', '-j4', '--quiet' );
    run( $src, 'make', 'install', '--quiet' );
    return $prefix;
}

my $deps = "$root/dev/local/lib/perl5";
my %result;

for my $v (@versions) {
    my $ok = eval {
        my $prefix = install_lib($v);

        my $tmp = tempdir( CLEANUP => 1 );
        run( $root, 'bash', '-c', "git ls-files -z | grep -zv '^maxmind-db\$' | xargs -0 cp --parents -t '$tmp'" );
        run( $root, 'cp', '-r', 'maxmind-db', $tmp );

        local $ENV{PERL5LIB}       = join ':', $deps, grep { defined } $ENV{PERL5LIB};
        local $ENV{LD_LIBRARY_PATH} = join ':', "$prefix/lib", grep { defined } $ENV{LD_LIBRARY_PATH};
        run( $tmp, 'perl', 'Build.PL', '--lib', "$prefix/lib", '--include', "$prefix/include" );
        run( $tmp, './Build' );
        run( $tmp, './Build', 'test', 'verbose=1' );
        1;
    };
    print STDERR $@ if !$ok && $@;
    $result{$v} = $ok ? 'PASS' : 'FAIL';
}

print "\nlibmaxminddb  result\n";
printf "%-12s  %s\n", $_, $result{$_} for @versions;
exit( ( grep { $_ eq 'FAIL' } values %result ) ? 1 : 0 );
