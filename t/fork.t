# -*- perl -*-
#

require 5.004;
use strict;

require IO::Socket;
require Config;

if ($Config::Config{'osname'} =~ /win/i
    ||  $Config::Config{'archname'} =~ /win/i) {
    print "1..0\n";
    exit 0;
}

print "1..5\n";
# Start a new process running the server
my($pid);
if (!defined($pid = fork())) {
    print STDERR "fork: $!\n";
    print "1..0\n";
    exit 0;
}
if (!$pid) {
    # Child process; run the server
    my($server);
    foreach $server ("./server", "t/server") {
	if (-f $server) {
	    exec "$^X -Iblib/lib -Iblib/arch $server --forking";
	}
    }
    die "Cannot find server";
}

# Sleep a little bit, so that the server can create a listening socket
sleep 5;

# Terminate test if not finished in 1 minute
$SIG{'ALRM'} = sub { die "Alarm clock"; };
alarm 60;

eval {
    my($fh) = IO::Socket::INET->new('PeerAddr' => '127.0.0.1:37112');
    printf("%s 1\n", $fh ? "ok" : "not ok");
    printf("%s 2\n", $fh->close() ? "ok" : "not ok");
    $fh = IO::Socket::INET->new('PeerAddr' => '127.0.0.1:37112');
    printf("%s 3\n", $fh ? "ok" : "not ok");
    my($ok) = $fh ? 1 : 0;
    for (my($i) = 0;  $ok  &&  $i < 20;  $i++) {
	if (!$fh->print("$i\n")) { $ok = 0; last; }
	my($line) = $fh->getline();
	if (!defined($line)) { $ok = 0;  last; }
	if ($line !~ /(\d+)/  ||  $1 != $i*2) { $ok = 0;  last; }
    }
    printf("%s 4\n", $ok ? "ok" : "not ok");
    printf("%s 5\n", $fh->close() ? "ok" : "not ok");
};

alarm 0;
if ($@) {
    print STDERR "Failure: $!\n";
}
kill 1, $pid;
