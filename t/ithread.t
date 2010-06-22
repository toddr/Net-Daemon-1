BEGIN {
    require 5.004;
    use strict;
    use warnings;

    use IO::Socket ();
    use Config ();
    use Net::Daemon::Test ();
    use Test::More;

    if (!eval { require threads; my $t = threads->new(sub { }) }) {
         plan skip_all => "ithreads not available on this work on this system?";
        exit;
    }
    plan tests => 65
}

my($test_server, $port) = Net::Daemon::Test->Child(undef, $^X, 't/server', '--timeout', 20, '--mode=ithreads');


diag("Making first connection to port $port...");
my $fh = IO::Socket::INET->new('PeerAddr' => '127.0.0.1', 'PeerPort' => $port);
ok($fh, "Connected to port $port on localhost");
ok($fh->close(), "Disconnected");

diag("Making second connection to port $port...");
$fh = IO::Socket::INET->new('PeerAddr' => '127.0.0.1', 'PeerPort' => $port);
ok($fh, "Connected to port $port on localhost");

foreach my $i (1..20) {
    
    ok($fh->print("$i\n"), "print $i to the port") or die($fh->error() . " ($!)");
    ok($fh->flush(), "swirly!") or die($fh->error() . " ($!)");
    
    my $line = $fh->getline or die("Error while reading $i: " . $fh->error() . " ($!)");
    is($line, $i*2 . "\n", "Read line $i");
}

is($@, undef, 'No error in $@');

ok($fh->close(), 'Close $fh');

# Shut down the server;
diag("Terminating test server");
$test_server->Terminate();
undef $test_server;

exit;

END {
    if ($test_server) { diag("Terminating test server"); $test_server->Terminate() }
    if (-f "ndtest.prt") { unlink "ndtest.prt" }
}
