require 5.004;
use strict;
use warnings;

use Test::More tests => 5;

use IO::Socket ();
use Config ();
use Net::Daemon::Test ();
use Socket ();


my $CONFIG_FILE = "t/config";


sub RunTest {
    my $config = shift;

    if (!open(CF, ">$CONFIG_FILE")  ||  !(print CF $config)  ||  !close(CF)) {
	die "Error while creating config file $CONFIG_FILE: $!";
    }

    my($handle, $port) = Net::Daemon::Test->Child
	(undef, $^X, '-Iblib/lib', '-Iblib/arch', 't/server', '--debug',
	 '--mode=single', '--configfile', $CONFIG_FILE);
    my $fh = IO::Socket::INET->new('PeerAddr' => '127.0.0.1',
				   'PeerPort' => $port);
    my $result;
    my $success = $fh && $fh->print("1\n")  &&
	defined($result = $fh->getline())  &&  $result =~ /2/;
    $handle->Terminate();

    return $success;
}


ok(RunTest(q/{'mode' => 'single', 'timeout' => 60}/), "Testing config file with open client list.");

ok(RunTest(q/
    { 'mode' => 'single',
      'timeout' => 60,
      'clients' => [ { 'mask' => '^127\.0\.0\.1$', 'accept' => 1 },
                     { 'mask' => '.*', 'accept' => 0 }
                   ]
    }/), "Testing config file with client 127.0.0.1.");

ok(!RunTest(q/
    { 'mode' => 'single',
      'timeout' => 60,
      'clients' => [ { 'mask' => '^127\.0\.0\.1$', 'accept' => 0 },
                     { 'mask' => '.*', 'accept' => 1 }
                   ]
    }/), "Config file with client !127.0.0.1 fails");


my $hostname = gethostbyaddr(Socket::inet_aton("127.0.0.1"),
			   Socket::AF_INET());
SKIP: {
    skip "Skipping hostname test cause no hostname found for 127.0.0.1", 2 unless($hostname);
    my $regexp = $hostname;
    $regexp =~ s/\./\\\./g;

    ok(RunTest(q/
    { 'mode' => 'single',
      'timeout' => 60,
      'clients' => [ { 'mask' => '^/
 . $regexp . q/$', 'accept' => 1 },
                     { 'mask' => '.*', 'accept' => 0 }
                   ]
    }/), "Testing config file with client $hostname");

    ok(!RunTest(q/
    { 'mode' => 'single',
      'timeout' => 60,
      'clients' => [ { 'mask' => '^/
 . $regexp . q/$', 'accept' => 0 },
                     { 'mask' => '.*', 'accept' => 1 }
                   ]
    }/), "Config file with client !$hostname fails");

}

END {
    unlink $CONFIG_FILE if(-f $CONFIG_FILE);
    unlink "ndtest.prt" if(-f "ndtest.prt");
}
