# -*- perl -*-
#

require 5.004;
use strict;

require IO::Socket;
require Config;

$@ = ''; eval { require Thread; };
if ($@) {
    print "1..0\n";
    exit 0;
}

print "1..5\n";

# Start a new process running the server
my($pid, $serverPath, $server);
foreach $serverPath ("./server", "t/server") {
    if (-f $serverPath) {
	$server = $serverPath;
	last;
    }
}
if (!$server) { die "Missing server script"; }

if ($Config::Config{'osname'} =~ /win/i) {
    require Win32;
    require Win32::Process;
    print "Running $^X\n";
    if (!&Win32::Process::Create($pid, $^X . ".exe",
				 " -Iblib/lib -Iblib/arch $server",
				 0, Win32::Process::NORMAL_PRIORITY_CLASS(),
				 ".")) {
	die "Cannot create child process: "
	    . Win32::FormatMessage(Win32::GetLastError());
    }
} else {
    $SIG{'ALRM'} = sub { die "Alarm clock"; };
    alarm 60;
    if (!defined($pid = fork())) {
	die "fork: $!\n";
    }
    if (!$pid) {
	exec "$^X -Iblib/lib -Iblib/arch $server";
    }
}

# Sleep a little bit, so that the server can create a listening socket
sleep 5;

# Terminate test if not finished in 1 minute

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

if ($@) {
    print STDERR "Failure: $!\n";
}
if ($Config::Config{'osname'} =~ /win/i) {
    $pid->Kill(0);
} else {
    alarm 0;
    kill 1, $pid;
}
