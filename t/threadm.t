# -*- perl -*-
#

require 5.004;
use strict;

require IO::Socket;
require Config;
require Net::Daemon::Test;
require Fcntl;
require Config;


$| = 1;
$^W = 1;


if (!$Config::Config{'usethreads'}  ||
    $Config::Config{'usethreads'} ne 'define'  ||
    !eval { require Thread }) {
    print "1..0\n";
    exit 0;
}


my($handle, $port);
if (@ARGV) {
    $port = shift @ARGV;
} else {
    ($handle, $port) = Net::Daemon::Test->Child
	(10, $^X, '-Iblib/lib', '-Iblib/arch', 't/server',
	 '--mode=threads', 'logfile=stderr', 'debug');
}


my $regexpLock = 1;
sub IsNum {
    #
    # Regular expressions aren't thread safe, as of 5.00502 :-(
    #
    my $lock = lock($regexpLock);
    my $str = shift;
    (defined($str)  &&  $str =~ /(\d+)/) ? $1 : undef;
}


sub ReadWrite {
    my $fh = shift; my $i = shift; my $j = shift;
    if (!$fh->print("$j\n")  ||  !$fh->flush()) {
	print STDERR "Child $i: Error while writing $j: $!";
	return 0;
    }
    my $line = $fh->getline();
    if (defined($line)) {
	if (defined(my $num = IsNum($line))) {
	    if ($num != $j*2) {
		print STDERR "Child $i: Expected " . $j*2 .
		    ", got '$num'\n";
		return 0;
	    }
	} else {
	    print STDERR ("Child $i: Cannot parse result: ",
			  (defined($line) ? "undef" : $line) , "\n");
	    return 0;
	}
    } else {
	print STDERR "Child $i: Error while reading: $!";
	return 0;
    }
    return 1;
}


sub MyChild {
    my $i = shift;

    # This is the child.
    #print "Child $i: Starting\n";
    my $fh = IO::Socket::INET->new('PeerAddr' => '127.0.0.1',
				   'PeerPort' => $port);
    if (!$fh) {
	print STDERR "Cannot connect: $!";
	return 0;
    }
    #print "Child $i: Connected\n";
    for (my $j = 0;  $j < 1000;  $j++) {
	return 0 unless(ReadWrite($fh, $i, $j));
    }
    #print "Child $i done.\n";
    return 1;
}


# Spawn 10 childs, each of them running a series of test

my @threads;
for (my $i = 0;  $i < 10;  $i++) {
    #print "Spawning child $i.\n";
    my $tid = Thread->new(\&MyChild, $i);
    if (!$tid) {
	print STDERR "Failed to create new thread: $!\n";
	exit 1;
    }
    push(@threads, $tid);
}
for (my $i = 1;  $i <= 10;  $i++) {
    my $tid = shift @threads;
    if ($tid->join()) {
	print "ok $i\n";
    } else {
	print "not ok $i\n";
    }
}

my $line;
alarm 120;

END {
    if ($handle) {
	print "Terminating server.\n";
	$handle->Terminate();
	undef $handle;
    }
    unlink "ndtest.prt";
}
