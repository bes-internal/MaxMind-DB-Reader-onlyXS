#!perl
`perl dev/exec.pl dzil clean`;
require "./local/lib/perl5/File/Path/Tiny.pm";
File::Path::Tiny::rm("dev/local");
if (-l "local") {unlink "local" or die $@;}

print "done\n";
