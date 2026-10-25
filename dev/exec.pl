#!perl
# Runs a command with the dependencies from dev/local (like "carton exec"):
#   perl dev/exec.pl dzil test
use FindBin;

die "Usage: perl dev/exec.pl command [args]\n" unless @ARGV;

$ENV{PERL5LIB} = join ':', "$FindBin::Bin/local/lib/perl5", grep {defined} $ENV{PERL5LIB};
$ENV{PATH} = "$FindBin::Bin/local/bin:$ENV{PATH}";
exec @ARGV or die "Can't run $ARGV[0]: $!\n";
