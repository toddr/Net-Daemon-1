BEGIN {
    require 5.004;
    use strict;
    use warnings;
    use Test::More;
    if($^O eq "MSWin32") {
        plan skip_all => 'Forks broken in Windows';
        exit;
    }

    my $fork_ok;
    eval {
        my $pid = fork();
        if (defined($pid)) {
            if (!$pid) { exit 0; } # Child
        }
        $fork_ok = 1;
    };

    if(!$fork_ok) {
        plan skip_all => "Forking doesn't work on this system?";
        exit;
    }
    
    plan tests => 5;
}

use IO::Socket ();
use Config ();
use Net::Daemon::Test ();

my ($handle, $port) = Net::Daemon::Test->Child(undef,
						$^X, '-Iblib/lib',
						'-Iblib/arch',
						't/server', '--mode=fork',
						'--debug', '--timeout', 60);

diag("Making first connection to port $port...");
my $fh = IO::Socket::INET->new('PeerAddr' => '127.0.0.1', 'PeerPort' => $port);
ok($fh, "Connection to port $port succeeds");
ok($fh->close(), "Disconnect from port $port succeeds");

diag("Making second connection to port $port");
$fh = IO::Socket::INET->new('PeerAddr' => '127.0.0.1', 'PeerPort' => $port);
ok($fh, "Connection to port $port succeeds");
eval {
    for (my $i = 0;  $i < 20;  $i++) {
        diag("Writing number: $i");
	    if (!$fh->print("$i\n")  ||  !$fh->flush()) {
	        die "Client: Error while writing number $i: " . $fh->error() . " ($!)";
        }
        diag("Written.");
	   
        my($line) = $fh->getline();
        if (!defined($line)) {
            die "Client: Error while reading number $i: " . $fh->error() . " ($!)";
        }
        if ($line !~ /(\d+)/  ||  $1 != $i*2) {
            die "Wrong response, exptected " . ($i*2) . ", got $line";
        }
    }
};
is($@, '', "No error sending/recieving numbers 0..19");
ok($fh->close(), "Disconnect from port $port succeeds");

END {
    $handle->Terminate  if ($handle);
    unlink "ndtest.prt" if (-f "ndtest.prt"); 
}
