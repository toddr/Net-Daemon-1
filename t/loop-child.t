require 5.004;
use strict;
use warnings;

use Test::More tests => 65;

use IO::Socket ();
use Config ();
use Net::Daemon::Test ();

my ($handle, $port) = Net::Daemon::Test->Child(undef, $^X, '-Iblib/lib', '-Iblib/arch', 't/server',
                                               '--mode=single', '--loop-timeout=2', '--loop-child', '--debug', '--timeout', 60);    

diag("Making first connection to port $port...");
my $fh = IO::Socket::INET->new('PeerAddr' => '127.0.0.1', 'PeerPort' => $port);

isa_ok($fh, 'IO::Socket::INET');
ok($fh->close(), "Make sure we can close the socket");


diag("Making second connection to port $port...");
$fh = IO::Socket::INET->new('PeerAddr' => '127.0.0.1', 'PeerPort' => $port);
isa_ok($fh, 'IO::Socket::INET');

foreach my $i (1..20) {
    ok($fh->print("$i\n"), "print $i");
    ok($fh->flush(), "Flush socket stream") or die;
    
    my($line) = $fh->getline();
    is($line, $i*2 . "\n", "output *= 2");
}
ok($fh->close(), "Make sure we can close the connection");

# Wait until ndtest has a 10 in it. TODO: Why 10?
my $num;
foreach my $i (1..30) {
    if(open(my $cnt, "<", "ndtest.cnt")) {
        $num = <$cnt>;
        last if($num && $num == 10);
    }
    sleep 1;
}
is($num, "10\n", "ndtest.cnt has a 10 in it");

exit;

END {
    if ($handle) { $handle->Terminate() }
    unlink "ndtest.prt", "ndtest.cnt";
}
