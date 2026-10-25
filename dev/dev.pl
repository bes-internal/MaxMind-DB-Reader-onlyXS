#!perl

system 'cpm', 'install', '--cpanfile', 'dev/cpanfile', '-L', 'dev/local';
if (!-l "local") { symlink("dev/local", "local") or die $@; }
system 'cpm', 'install', '--cpanfile', 'cpanfile', '-L', 'dev/local';

print "done\n";
