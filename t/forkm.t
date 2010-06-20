BEGIN {
    require 5.004;
    use strict;
    use warnings;
    
    use Test::More;
    
    use IO::Socket ();
    use Config ();
    use Net::Daemon::Test ();
    use Fcntl ();
    use Config ();


    unlink glob('forkm.*.pid');
    $| = 1;
    
    
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
    
    plan tests => 30;
}



my ($handle, $port) = Net::Daemon::Test->Child(undef, $^X, '-Iblib/lib', '-Iblib/arch', 't/server', '--mode=fork', 'logfile=stderr', 'debug');


my %childs;

# Spawn 10 childs, each of them running a series of tests
for my $fork_number (1..10) {
    my $pid = fork();
    defined $pid or die("Couldn't fork process");
    if ($pid) {
        # This is the parent
        $childs{$fork_number} = $pid;
        pass("Created process $fork_number to connect back to my server. pid=$pid");
    } else {
        # This is the child
        undef $handle;
        %childs = ();

        my $result = run_child_tests($fork_number);

        open(my $fh, ">", "forkm.$$.pid") or die;
        print $fh $result;
        close $fh;
        exit 0;
    }
}

$SIG{ALRM} = sub { die "the 10 forks did not finish after 120 seconds!" };
alarm(120);

for my $child_fork (1..10) {
    diag("Waiting for fork $child_fork ($childs{$child_fork}) to finish");
    waitpid($childs{$child_fork}, 0); # Bloocking wait. die with alarm if we don't parse them all in 120 seconds
    pass("fork $child_fork ($childs{$child_fork}) finished");
    
    my $child_pid_file = "forkm.$childs{$child_fork}.pid";
    open(my $fh, "<", $child_pid_file);
    local $/ = '';
    my $result = <$fh>;
    close $fh;
    unlink $child_pid_file;
    
    is($result, 'ok', "Child test $child_fork ($childs{$child_fork}) succeeded");
    
}

diag("exit");
exit;

sub IsNum {
    my $str = shift;
    (defined($str)  &&  $str =~ /(\d+)/) ? $1 : undef;
}


sub ReadWrite {
    my $fh = shift; my $fork_number = shift; my $readwrite_counter = shift;
    if (!$fh->print("$readwrite_counter\n")  ||  !$fh->flush()) {
        die "Child $fork_number: Error while writing $readwrite_counter: " . $fh->error() . " ($!)";
    }
    my $line = $fh->getline();
    die "Child $fork_number: Error while reading: " . $fh->error() . " ($!)"
        unless defined($line);
    
    my $num;
    die "Child $fork_number: Cannot parse result: $line"
        unless defined($num = IsNum($line));
        
    die "Child $fork_number: Expected " . ($readwrite_counter*2) . ", got $num"
        unless $readwrite_counter*2 == $num;
}


sub run_child_tests {
    my $fork_number = shift;

    eval {
        my $fh = IO::Socket::INET->new('PeerAddr' => '127.0.0.1',
                       'PeerPort' => $port);
        if (!$fh) {
            die "Process $$ cannot connect: $!";
        }
        for my $readwrite_counter (1..10000) {
            ReadWrite($fh, $fork_number, $readwrite_counter);
        }
    };
    if ($@) {
        diag("Client: Error $@");
        return "Client: Error $@";
    }
    return "ok";
}

END { # Cleanup server on exit.
    if ($handle) {
       $handle->Terminate();
       undef $handle;
    }
    while (my($var, $val) = each %childs) {
       kill 'TERM', $var;
    }
    %childs = ();
    unlink "ndtest.prt";
    exit 0;
}