# -*- perl -*-
#
#   $Id: base.t,v 1.1.1.1 1999/01/06 20:21:06 joe Exp $
#
BEGIN { $| = 1; print "1..1\n"; }
END {print "not ok 1\n" unless $loaded;}
use Net::Daemon;
$loaded = 1;
print "ok 1\n";


