# -*- perl -*-
#
#   Net::Daemon - Base class for implementing TCP/IP daemons
#
#   Copyright (C) 1998, Jochen Wiedmann
#                       Am Eisteich 9
#                       72555 Metzingen
#                       Germany
#
#                       Phone: +49 7123 14887
#                       Email: joe@ispsoft.de
#
#
#   This module is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This module is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this module; if not, write to the Free Software
#   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
############################################################################

package Net::Daemon;

require 5.004;
use strict;
use vars qw($VERSION @ISA);

require AutoLoader;
require Getopt::Long;
require IO::Socket;
require Config;
if ($Config::Config{'archname'} =~ /win32/i) {
    require Win32::EventLog;
} else {
    require Sys::Syslog;
}


@ISA = qw(AutoLoader);

$VERSION = '0.02';


############################################################################
#
#   Name:    Options (Class method)
#
#   Purpose: Returns a hash ref of command line options
#
#   Inputs:  $class - This class
#
#   Result:  Options array; any option is represented by a hash ref;
#            used keys are 'template', a string suitable for describing
#            the option to Getopt::Long::GetOptions and 'description',
#            a string for the Usage message
#
############################################################################

sub Options ($) {
    { 'debug' => { 'template' => 'debug',
		   'description' =>  '--debug                 '
		       . 'Turn debugging mode on'},
      'facility' => { 'template' => 'facility=s',
		      'description' => '--facility <facility>   '
			  . 'Syslog facility; defaults to \'daemon\'' },
      'help' => { 'template' => 'help',
		  'description' => '--help                  '
		      . 'Print this help message' },
      'localaddr' => { 'template' => 'localaddr=s',
		       'description' => '--localaddr <ip>        '
			   . 'IP number to bind to; defaults to INADDR_ANY' },
      'localport' => { 'template' => 'localport=s',
		       'description' => '--localport <port>      '
			   . 'Port number to bind to' },
      'pidfile' => { 'template' => 'pidfile=s',
		     'description' => '--pidfile <file>        '
			 . 'Use <file> as PID file' },
      'stderr' => { 'template' => 'stderr',
		    'description' => '--stderr                '
			. 'Use stderr instead of syslog for messages' },
      'version' => { 'template' => 'version',
		     'description' => '--version               '
			 . 'Print version number and exit' } }
}


############################################################################
#
#   Name:    Version (Class method)
#
#   Purpose: Returns version string
#
#   Inputs:  $class - This class
#
#   Result:  Version string; suitable for printed by "--version"
#
############################################################################

sub Version ($) {
    "Net::Daemon server, Copyright (C) 1998, Jochen Wiedmann";
}


############################################################################
#
#   Name:    Usage (Class method)
#
#   Purpose: Prints usage message
#
#   Inputs:  $class - This class
#
#   Result:  Nothing; aborts with error status
#
############################################################################

sub Usage ($) {
    my($class) = shift;
    my($options) = $class->Options();
    my(@options) = sort (keys %$options);

    print STDERR "Usage: $0 <options>\n\nPossible options are:\n\n";
    my($key);
    foreach $key (sort (keys %$options)) {
	my($option) = $options->{$key};
	print STDERR "  ", $option->{'description'}, "\n";
    }
    print STDERR "\n", $class->Version(), "\n";
    exit(1);
}



############################################################################
#
#   Name:    new (Class method)
#
#   Purpose: Constructor
#
#   Inputs:  $class - This class
#            $attr - Hash ref of attributes
#            $args - Array ref of command line arguments
#
#   Result:  Server object for success, error message otherwise
#
############################################################################

sub new ($$;$) {
    my($class, $attr, $args) = @_;
    my($self) = $attr ? \%$attr : {};
    bless($self, (ref($class) || $class));
    $self->{'options'} = {};
    if ($args) {
	my($options) = $class->Options();
	my($var, $val, @optList);
	while (($var, $val) = each %$options) {
	    push(@optList, $val->{'template'});
	}
	if (!Getopt::Long::GetOptions($self->{'options'}, @optList)) {
	    $self->Usage();
	}
	if ($self->{'options'}->{'help'}) {
	    $self->Usage();
	}
	if ($self->{'options'}->{'version'}) {
	    print STDERR $self->Version(), "\n";
	    exit 1;
	}
    } else {
	$self->{'options'} = {};
    }
    $self;
}

sub Clone ($$) {
    my($self, $client) = @_;;
    $self->new({ 'socket' => $client,
		 'parent' => $self,
		 'debug' => $self->{'debug'},
		 'stderr' => $self->{'stderr'},
		 'forking' => $self->{'forking'}
	       }, undef);
}


############################################################################
#
#   Name:    Log (Instance method)
#
#   Purpose: Does logging
#
#   Inputs:  $self - Server instance
#
#   Result:  TRUE, if the client has successfully authorized, FALSE
#            otherwise.
#
############################################################################

{
    my($syslogOpen) = 0;
    my($eventLog, $eventId);

    sub OpenLog($) {
	my($self) = shift;
	if ($Config::Config{'archname'} =~ /win32/i) {
	    $eventLog = Win32::EventLog->new(ref($self), '');
	    $eventId = 0;
	    if (!$eventLog) {
		die "Cannot open EventLog:" . &Win32::GetLastError();
	    }
	} else {
	    if (defined(&Sys::Syslog::setlogsock)  &&
		defined(&Sys::Syslog::_PATH_LOG)) {
	      Sys::Syslog::setlogsock('unix');
	    }
	    &Sys::Syslog::openlog(ref($self) || $self, 'pid',
				  $self->{'options'}->{'facility'}
				  || $self->{'facility'} || 'daemon');
	}
	$syslogOpen = 1;
    }

    sub Log ($$$;@) {
	my($self, $level, $format, @args) = @_;
	my($tid) = $self->{'forking'} ? '' : (Thread->self->tid() . ", ");
	if (ref($self) eq 'HASH'  &&  $self->{'stderr'}) {
	    printf STDERR ("$level, $tid$format\n", @args);
	} else {
	    if (!$syslogOpen) {
		$self->OpenLog();
		$syslogOpen = 1;
	    }
	    if ($eventLog) {
		my($type, $category);
		if ($level eq 'debug') {
		    $type = Win32::EventLog::EVENTLOG_INFORMATION_TYPE();
		    $category = 10;
		} elsif ($level eq 'notice') {
		    $type = Win32::EventLog::EVENTLOG_INFORMATION_TYPE();
		    $category = 20;
		} else {
		    $type = Win32::EventLog::EVENTLOG_ERROR_TYPE();
		    $category = 50;
		}
		$eventLog->Report({
		    'Category' => $category,
		    'EventType' => $type,
		    'EventID' => ++$eventId,
		    'Strings' => sprintf($format, @args),
		    'Data' => $tid
		});
	    } else {
		&Sys::Syslog::syslog($level, "$tid$format", @args);
	    }
	}
    }
}


############################################################################
#
#   Name:    Accept (Instance method)
#
#   Purpose: Called for authentication purposes
#
#   Inputs:  $self - Server instance
#
#   Result:  TRUE, if the client has successfully authorized, FALSE
#            otherwise.
#
############################################################################

sub Accept ($) {
    my($self) = @_;
    1;
}


############################################################################
#
#   Name:    Run (Instance method)
#
#   Purpose: Does the real work
#
#   Inputs:  $self - Server instance
#
#   Result:  Nothing; returning will make the connection to be closed
#
############################################################################

sub Run ($) {
}


############################################################################
#
#   Name:    Done (Instance method)
#
#   Purpose: Called by the server before doing an accept(); a TRUE
#            value makes the server terminate.
#
#   Inputs:  $self - Server instance
#
#   Result:  TRUE or FALSE
#
#   Bugs:    Doesn't work with 'forking' => 1
#
############################################################################

sub Done ($;$) {
    0;
}


############################################################################
#
#   Name:    Bind (Instance method)
#
#   Purpose: Binds to a port; if successfull, it never returns. Instead
#            it accepts connections. For any connection a new thread is
#            created and the Accept method is executed.
#
#   Inputs:  $self - Server instance
#
#   Result:  Error message in case of failure
#
############################################################################

sub _Reaper () {
    my($pid) = wait;
    $SIG{'CHLD'} = \&_Reaper;
}

sub Bind ($) {
    my($self) = @_;
    my($fh, $options);

    $options = $self->{'options'} || {};
    if (!($self->{'socket'} = IO::Socket::INET->new
	  ( 'LocalAddr' => $options->{'localaddr'} || $self->{'localaddr'},
	    'LocalPort' => $options->{'localport'} || $self->{'localport'},
	    'Proto'     => $options->{'proto'} || $self->{'proto'} || 'tcp',
	    'Listen'    => $options->{'listen'} || $self->{'listen'} || 10,
	    'Reuse'     => 1))) {
	$self->Log('err', "Cannot create socket: $!");
	return "Cannot create socket: $!";
    }
    $self->Log('notice', "Server starting");

    my($client);
    while (1) {
	if ($self->Done()) {
	    $self->Log('notice', "%s server terminating", ref($self));
	    return '';
	}
	my($client) = $self->{'socket'}->accept();
	if (!$client) {
	    my($msg) = sprintf("%s server failed to accept: %s",
			       ref($self), $self->{'socket'}->error() || $!);
	    $self->Log('err', $msg);
	    return $msg;
	}
	my($sth) = $self->Clone($client);
	if (!$sth) {
	    $client = undef;
	} else {
	    my($startFunc) = sub {
		my($self) = @_;
		$self->Log('debug', "New child starting ($self).");
		if (!$self->Accept()) {
		    $self->Log('err', 'Refusing client');
		} else {
		    $self->Log('notice', 'Accepting client');
		    $self->Run();
		}
		$self->Log('debug', "Child terminating.");
	    };
	    if ($self->{'forking'}) {
		$SIG{'CHLD'} = \&_Reaper;
		my($pid) = fork();
		if (!defined($pid)) {
		    $self->Log('err', "Cannot fork: %s", $!);
		} elsif (!$pid) {
		    &$startFunc($sth);
		    exit(0);
		}
	    } else {
		require Thread;
		my($tid) = Thread->new($startFunc, $sth);
		if(!$tid) {
		    $self->Log('err', "Failed to create new thread: $!");
		}
	    }
	}
	$sth = undef;    # Force calling destructors
	$client = undef; 
    }
}


1;

__END__

=head1 NAME

Net::Daemon - Perl extension for portable daemons

=head1 SYNOPSIS

  # Create a subclass of Net::Daemon
  require Net::Daemon;
  package MyDaemon;
  @MyDaemon::ISA = qw(Net::Daemon);

  sub Run ($) {
    # This function does the real work; it is invoked whenever a
    # new connection is made.
  }

=head1 DESCRIPTION

Net::Daemon is an approach for writing daemons that are both portable and
simple. It is based on the Thread package of Perl 5.005.

The Net::Daemon class is an abstract class that offers methods for the
most common tasks a daemon needs: Starting up, logging, accepting clients,
authorization and doing the true work. You only have to override those
methods that aren't appropriate for you, but typically inheriting will
safe you a lot of work anyways.

=head2 Constructors

  $server = Net::Daemon->new($attr, $options);

  $connection = $server->Clone($socket);

Two constructors are available: The C<new> method is called upon startup
and creates an object that will basically act as an anchor over the
complete program. It supports command line parsing via L<Getopt::Long (3)>.

Arguments of C<new> are I<$attr>, an hash ref of attributes (see below)
and I<$options> an array ref of options, typically command line arguments
(for example C<\@ARGV>) that will be passed to C<Getopt::Long::GetOptions>.

The second constructor is C<Clone>: It is called whenever a client
connects. It receives the main server object as input and returns a
new object. This new object will be passed to the methods that finally
do the true work of communicating with the client. Communication occurs
over the socket C<$socket>, C<Clone>'s argument.

Possible object attributes and the corresponding command line
arguments are:

=over 4

=item I<debug> (C<--debug>)

Used for turning debuging mode on.

=item I<facility> (C<--facility>)

Facility to use for L<Sys::Syslog (3)> (Unix only). The default is
C<daemon>.

=item I<forking>

Creates a forking daemon instead of using the Thread library (Unix only).
There are two good reasons for using fork(): You have no multithreaded
Perl or you need to simplify porting existing applications.

=item I<localaddr> (C<--localaddr>)

By default a daemon is listening to any IP number that a machine
has. This attribute allows to restrict the server to the given
IP number.

=item I<localport> (C<--localport>)

This attribute sets the port on which the daemon is listening.

=item I<options>

Array ref of Command line options that have been passed to the server object
via the C<new> method.

=item I<parent>

When creating an object with C<Clone> the original object becomes
the parent of the new object. Objects created with C<new> usually
don't have a parent, thus this attribute is not set.

=item I<pidfile> (C<--pidfile>)

If your daemon creates a PID file, you should use this location.

=item I<socket>

The socket that is connected to the client; passed as C<$client> argument
to the C<Clone> method. If the server object was created with C<new>,
this attribute can be undef, as long as the C<Bind> method isn't called.
Sockets are assumed to be IO::Socket objects.

=item I<stderr> (C<--stderr>)

By default Logging is done via L<Sys::Syslog (3)> (Unix) or
L<Win32::EventLog> (Windows NT). This attribute allows logging
to be redirected to STDERR instead.

=item I<version> (C<--version>)

Supresses startup of the server; instead the version string will
be printed and the program exits immediately.

=back

Note that most of these attributes (facility, forking, localaddr, localport,
pidfile, version) are meaningfull only at startup. If you set them later,
they will be simply ignored. As almost all attributes have appropriate
defaults, you will typically use the C<localport> attribute only.

=head2 Command Line Parsing

  my($optionsAvailable) = Net::Daemon->Options();

  print Net::Daemon->Version(), "\n";

  Net::Daemon->Usage();

The C<Options> method returns a hash ref of possible command line options.
The keys are option names, the values are again hash refs with the
following keys:

=over 4

=item template

An option template that can be passed to C<Getopt::Long::GetOptions>.

=item description

A description of this option, as used in C<Usage>

=back

The C<Usage> method prints a list of all possible options and returns.
It uses the C<Version> method for printing program name and version.

=head2 Event logging

  $server->Log($level, $format, @args);

The C<Log> method is an interface to L<Sys::Syslog (3)> or
L<Win32::EventLog (3)>. It's arguments are I<$level>, a syslog
level like C<debug>, C<notice> or C<err>, a format string in the
style of printf and the format strings arguments.

=head2 Flow of control

  $server->Bind();
  # The following inside Bind():
  if ($connection->Accept()) {
      $connection->Run();
  } else {
      $connection->Log('err', 'Connection refused');
  }

The C<Bind> method is called by the application when the server should
start. Typically this can be done right after creating the server object
C<$server>. C<Bind> usually never returns, except in case of errors.

When a client connects, the server uses C<Clone> to derive a connection
object C<$connection> from the server object. A new thread or process
is created that uses the connection object to call your classes
C<Accept> method. This method is intended for host authorization and
should return either FALSE (refuse the client) or TRUE (accept the client).

If the client is accepted, the C<Run> method is called which does the
true work. The connection is closed when C<Run> returns and the corresponding
thread or process exits.

=head1 EXAMPLE

As an example we'll write a simple calculator server. After connecting
to this server you may type expressions, one per line. The server
evaluates the expressions and prints the result. (Note this is an example,
in real life we'd never implement sucj a security hole. :-)

For the purpose of example we add a command line option I<--base> that
takes 'hex', 'oct' or 'dec' as values: The servers output will use the
given base.

  # -*- perl -*-
  #
  # Calculator server
  #
  require 5.004;
  use strict;

  require Net::Daemon;


  package Calculator;

  use vars qw($VERSION @ISA);
  $VERSION = '0.01';
  @ISA = qw(Net::Daemon); # to inherit from Net::Daemon

  sub Version ($) { 'Calculator Example Server, 0.01'; }

  # Add a command line option "--base"
  sub Options ($) {
      my($self) = @_;
      my($options) = $self->SUPER::Options();
      $options->{'base'} = { 'template' => 'base=s',
			     'description' => '--base                  '
				    . 'dec (default), hex or oct'
			      };
      $options;
  }

  # Treat command line option in the constructor
  sub new ($$;$) {
      my($class, $attr, $args) = @_;
      my($self) = $class->SUPER::new($class, $attr, $args);
      if ($self->{'parent'}) {
	  # Called via Clone()
	  $self->{'base'} = $self->{'parent'}->{'base'};
      } else {
	  # Initial call
	  if ($self->{'options'}  &&  $self->{'options'}->{'base'}) {
	      $self->{'base'} = $self->{'options'}->{'base'}
          }
      }
      if (!$self->{'base'}) {
	  $self->{'base'} = 'dec';
      }
  }

  sub Run ($) {
      my($self) = @_;
      my($line, $sock);
      $sock = $self->{'socket'};
      while (1) {
	  if (!defined($line = $sock->getline())) {
	      if ($sock->error()) {
		  $self->Log('err', "Client connection error %s",
			     $sock->error());
	      }
	      $sock->close();
	      return;
	  }
	  my($result) = eval $line;
	  my($rc);
	  if ($self->{'base'} eq 'hex') {
	      $rc = printf $sock ("%x\n", $result);
	  } elsif ($self->{'base'} eq 'oct') {
	      $rc = printf $sock ("%o\n", $result);
	  } else {
	      $rc = printf $sock ("%d\n", $result);
	  }
	  if (!$rc) {
	      $self->Log('err', "Client connection error %s",
			 $sock->error());
	      $sock->close();
	      return;
	  }
      }
  }

=head1 AUTHOR AND COPYRIGHT

  Net::Daemon is Copyright (C) 1998, Jochen Wiedmann
                                     Am Eisteich 9
                                     72555 Metzingen
                                     Germany

                                     Phone: +49 7123 14887
                                     Email: joe@ispsoft.de

This module is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This module is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this module; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.


=head1 SEE ALSO

RPC::pServer (3)

=cut

