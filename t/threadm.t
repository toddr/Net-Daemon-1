# -*- perl -*-
#
#   $Id: threadm.t,v 1.1.1.1 1999/01/06 20:21:06 joe Exp $
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
    die "Child $i: Error while writing $j: $!"
	unless $fh->print("$j\n") and $fh->flush();
    my $line = $fh->getline();
    die "Child $i: Error while reading: " . $fh->error() . " ($!)"
	unless defined($line);
    my $num = IsNum($line);
    die "Child $i: Cannot parse result: $line"
	unless defined($num);
    die "Child $i: Expected " . ($j*2) . ", got $num"
	unless ($num == $j*2);
}


sub MyChild {
    my $i = shift;

    eval {
	my $fh = IO::Socket::INET->new('PeerAddr' => '127.0.0.1',
				       'PeerPort' => $port);
	die "Cannot connect: $!" unless defined($fh);
	for (my $j = 0;  $j < 1000;  $j++) {
	    ReadWrite($fh, $i, $j);
	}
    };
    if ($@) {
	print STDERR $@;
	return 0;
    }
    return 1;
}


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
alarm 120;
for (my $i = 1;  $i <= 10;  $i++) {
    my $tid = shift @threads;
    if ($tid->join()) {
	print "ok $i\n";
    } else {
	print "not ok $i\n";
    }
}

END {
    if ($handle) {
	print "Terminating server.\n";
	$handle->Terminate();
	undef $handle;
    }
    unlink "ndtest.prt";
}
