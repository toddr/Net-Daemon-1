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
#   All rights reserved.
#
#   You may distribute this package under the terms of either the GNU
#   General Public License or the Artistic License, as specified in the
#   Perl README file.
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


@ISA = qw(AutoLoader);

$VERSION = '0.10';


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
    { 'chroot' => { 'template' => 'chroot=s',
		    'description' =>  '--chroot                '
			. 'Change rootdir to given after binding to port.' },
      'debug' => { 'template' => 'debug',
		   'description' =>  '--debug                 '
		       . 'Turn debugging mode on'},
      'facility' => { 'template' => 'facility=s',
		      'description' => '--facility <facility>   '
			  . 'Syslog facility; defaults to \'daemon\'' },
      'forking' => { 'template' => 'forking!',
		     'description' => '--forking               '
		          . 'Force forking (--noforking to disable)' },
      'group' => { 'template' => 'group=s',
		   'description' => '--group                 '
		       . 'Change gid to given group after binding to port.' },
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
      'single' => { 'template' => 'single',
		    'description' => '--single                '
			. 'Disable concurrent connections (debugging)' },
      'stderr' => { 'template' => 'stderr',
		    'description' => '--stderr                '
			. 'Use stderr instead of syslog for messages' },
      'user' => { 'template' => 'user=s',
		  'description' => '--user                  '
		      . 'Change uid to given user after binding to port.' },
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
    my $options = {};
    if ($args) {
	my $opt = $class->Options();
	my @optList = map { $_->{'template'} } values(%$opt);

	if (!Getopt::Long::GetOptions($options, @optList)) {
	    $self->Usage();
	}
	if ($options->{'help'}) {
	    $self->Usage();
	}
	if ($options->{'version'}) {
	    print STDERR $self->Version(), "\n";
	    exit 1;
	}
    }
    $self->{'options'} = $options;

    foreach my $option (qw(single forking user group chroot)) {
	if (exists($options->{$option})) {
	    $self->{$option} = $options->{$option};
	}
    }

    if (!defined($self->{'forking'})) {
	$self->{'forking'} = !eval { require Thread };
    } elsif (!$self->{'forking'}  &&  !$self->{'single'}) {
	require Thread;
    }

    $self;
}

sub Clone ($$) {
    my($self, $client) = @_;;
    $self->new({ 'socket' => $client,
		 'parent' => $self,
		 'debug' => $self->{'debug'},
		 'stderr' => $self->{'stderr'},
		 'forking' => $self->{'forking'},
		 'single' => $self->{'single'}
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
    my $syslogOpen = 0;
    my $stderr;
    my($eventLog, $eventId);

    # The OpenLog method is not thread safe. We trust it will be called
    # by the server before threading starts. Otherwise we'd need to
    # embed a "use attrs 'locked'" and loose downwards compatibility
    # to 5.004.
    sub OpenLog($) {
	my($self) = shift;
	$syslogOpen = 1;
	if (!ref($self)) {
	    $stderr = 1;
	    $syslogOpen = 0;
	} elsif ($self->{'stderr'}) {
	    $stderr = $self->{'stderr'};
	} elsif ($Config::Config{'archname'} =~ /win32/i) {
	    require Win32::EventLog;
	    $eventLog = Win32::EventLog->new(ref($self), '');
	    $eventId = 0;
	    if (!$eventLog) {
		die "Cannot open EventLog:" . &Win32::GetLastError();
	    }
	} else {
            eval { require Sys::Syslog };
	    if ($@) {
		die "Cannot open Syslog: $@";
	    }
	    if (defined(&Sys::Syslog::setlogsock)  &&
		defined(&Sys::Syslog::_PATH_LOG)) {
	        Sys::Syslog::setlogsock('unix');
	    }
	    &Sys::Syslog::openlog(ref($self) || $self, 'pid',
				  $self->{'options'}->{'facility'}
				  || $self->{'facility'} || 'daemon');
	}
    }

    sub Log ($$$;@) {
	my($self, $level, $format, @args) = @_;
	if (!$syslogOpen) {
	    $self->OpenLog();
	    $syslogOpen = 1;
	}
	my $tid = (ref($self) && !$self->{'forking'} && !$self->{'single'}) ?
	    (Thread->self->tid() . ", ") : '';
	if ($stderr) {
	    if (ref($stderr)) {
		$stderr->print(sprintf("$level, $tid$format\n", @args));
	    } else {
		printf STDERR ("$level, $tid$format\n", @args);
	    }
	} elsif ($eventLog) {
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

    sub Debug ($$;@) {
	my $self = shift;
	if (!ref($self)  ||  !$self->{'debug'}) {
	    my $fmt = shift;
	    $self->Log('debug', $fmt, @_);
	}
    }

    sub Error ($$;@) {
	my $self = shift; my $fmt = shift;
	$self->Log('err', $fmt, @_);
    }

    sub Fatal ($$;@) {
	my $self = shift; my $fmt = shift;
	my $msg = sprintf($fmt, @_);
	$self->Log('err', $msg);
	die $msg;
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
    my $pid = wait;
    $SIG{'CHLD'} = \&_Reaper;
}

sub Bind ($) {
    my $self = shift;
    my($fh, $options);

    $options = $self->{'options'} || {};
    if (!$self->{'socket'}  &&
	!($self->{'socket'} = IO::Socket::INET->new
	  ( 'LocalAddr' => $options->{'localaddr'} || $self->{'localaddr'},
	    'LocalPort' => $options->{'localport'} || $self->{'localport'},
	    'Proto'     => $options->{'proto'} || $self->{'proto'} || 'tcp',
	    'Listen'    => $options->{'listen'} || $self->{'listen'} || 10,
	    'Reuse'     => 1))) {
	$self->Fatal("Cannot create socket: $!");
    }
    $self->Log('notice', "Server starting");

    if (my $dir = $self->{'chroot'}) {
	$self->Debug("Changing root directory to $dir");
	if (!chroot($dir)) {
	    $self->Fatal("Cannot change root directory to $dir: $!");
	}
    }
    if (my $group = $self->{'group'}) {
	$self->Debug("Changing GID to $group");
	my $gid;
	if ($group !~ /^\d+$/) {
	    if (my $gid = getgrnam($group)) {
		$group = $gid;
	    } else {
		$self->Fatal("Cannot determine gid of $group: $!");
	    }
	}
	$( = ($) = $group);
    }
    if (my $user = $self->{'user'}) {
	$self->Debug("Changing UID to $user");
	my $uid;
	if ($user !~ /^\d+$/) {
	    if (my $uid = getpwnam($user)) {
		$user = $uid;
	    } else {
		$self->Fatal("Cannot determine uid of $user: $!");
	    }
	}
	$< = ($> = $user);
    }

    my($client);
    while (1) {
	if ($self->Done()) {
	    $self->Log('notice', "%s server terminating", ref($self));
	    return;
	}
	my $client = $self->{'socket'}->accept();
	if (!$client) {
	    $self->Fatal("%s server failed to accept: %s",
			 ref($self), $self->{'socket'}->error() || $!);
	}
	my $sth = $self->Clone($client);
	if (!$sth) {
	    $client = undef;
	} else {
	    my($startFunc) = sub {
		my($self) = @_;
		$self->Debug("New child starting ($self).");
		if (!$self->Accept()) {
		    $self->Error('Refusing client');
		} else {
		    $self->Log('notice', 'Accepting client');
		    $self->Run();
		}
		$self->Debug("Child terminating.");
	    };
	    if ($self->{'single'}) {
		&$startFunc($sth);
	    } elsif (!$self->{'forking'}  &&  eval { require Thread }) {
		my $tid = Thread->new($startFunc, $sth);
		if(!$tid) {
		    $self->Error("Failed to create new thread: $!");
		}
	    } else {
		$self->{'forking'} = 1;
		$SIG{'CHLD'} = \&_Reaper;
		my $pid = fork();
		if (!defined($pid)) {
		    $self->Error("Cannot fork: %s", $!);
		} elsif (!$pid) {
		    &$startFunc($sth);
		    exit(0);
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
simple. It is designed for Perl 5.005 and threads, but can work with fork()
and Perl 5.004.

The Net::Daemon class is an abstract class that offers methods for the
most common tasks a daemon needs: Starting up, logging, accepting clients,
authorization and doing the true work. You only have to override those
methods that aren't appropriate for you, but typically inheriting will
safe you a lot of work anyways.


=head2 Constructors

  $server = Net::Daemon->new($attr, $options);

  $connection = $server->Clone($socket);

Two constructors are available: The B<new> method is called upon startup
and creates an object that will basically act as an anchor over the
complete program. It supports command line parsing via L<Getopt::Long (3)>.

Arguments of B<new> are I<$attr>, an hash ref of attributes (see below)
and I<$options> an array ref of options, typically command line arguments
(for example B<\@ARGV>) that will be passed to B<Getopt::Long::GetOptions>.

The second constructor is B<Clone>: It is called whenever a client
connects. It receives the main server object as input and returns a
new object. This new object will be passed to the methods that finally
do the true work of communicating with the client. Communication occurs
over the socket B<$socket>, B<Clone>'s argument.

Possible object attributes and the corresponding command line
arguments are:

=over 4

=item I<chroot> (B<--chroot>)

After doing a bind() change root directory to the given directory by
doing a chroot(). This is usefull for security operations, but it
restricts programming a lot. For example, you typically have to load
external Perl extensions before doing a chroot(). See also the --group
and --user options.

If you don't know chroot(), think of an FTP server where you can see
a certain directory tree only after logging in.

=item I<debug> (B<--debug>)

Used for turning debugging mode on.

=item I<facility> (B<--facility>)

Facility to use for L<Sys::Syslog (3)> (Unix only). The default is
B<daemon>.

=item I<forking>

Creates a forking daemon instead of using the Thread library (Unix only).
There are two good reasons for using fork(): You have no multithreaded
Perl or you need to simplify porting existing applications.

=item I<group> (B<--group>)

After doing a bind(), change the real and effective GID to the given.
This is usefull, if you want your server to bind to a privileged port
(<1024), but don't want the server to execute as root. See also
the --user option.

=item I<localaddr> (B<--localaddr>)

By default a daemon is listening to any IP number that a machine
has. This attribute allows to restrict the server to the given
IP number.

=item I<localport> (B<--localport>)

This attribute sets the port on which the daemon is listening.

=item I<logfile> (B<--logfile>)

Be default logging messages will be written to the syslog (Unix) or
to the event log (Windows NT). On other operating systems you need to
specify a log file.

=item I<options>

Array ref of Command line options that have been passed to the server object
via the B<new> method.

=item I<parent>

When creating an object with B<Clone> the original object becomes
the parent of the new object. Objects created with B<new> usually
don't have a parent, thus this attribute is not set.

=item I<pidfile> (B<--pidfile>)

If your daemon creates a PID file, you should use this location.

=item I<single> (B<--single>)

Disables concurrent connections. In other words, the server waits for
a conenction, enters the Run() method without creating a new thread
or process and can accept further connections only after Run() returns.
This is usefull for debugging purposes or if you have a system that
neither supports threads nor fork().

=item I<socket>

The socket that is connected to the client; passed as B<$client> argument
to the B<Clone> method. If the server object was created with B<new>,
this attribute can be undef, as long as the B<Bind> method isn't called.
Sockets are assumed to be IO::Socket objects.

=item I<stderr> (B<--stderr>)

By default Logging is done via L<Sys::Syslog (3)> (Unix) or
L<Win32::EventLog> (Windows NT). This attribute allows logging
to be redirected to STDERR instead.

=item I<user> (B<--user>)

After doing a bind(), change the real and effective UID to the given.
This is usefull, if you want your server to bind to a privileged port
(<1024), but don't want the server to execute as root. See also
the --group and the --chroot options.

=item I<version> (B<--version>)

Supresses startup of the server; instead the version string will
be printed and the program exits immediately.

=back

Note that most of these attributes (facility, forking, localaddr, localport,
pidfile, version) are meaningfull only at startup. If you set them later,
they will be simply ignored. As almost all attributes have appropriate
defaults, you will typically use the B<localport> attribute only.


=head2 Command Line Parsing

  my $optionsAvailable = Net::Daemon->Options();

  print Net::Daemon->Version(), "\n";

  Net::Daemon->Usage();

The B<Options> method returns a hash ref of possible command line options.
The keys are option names, the values are again hash refs with the
following keys:

=over 4

=item template

An option template that can be passed to B<Getopt::Long::GetOptions>.

=item description

A description of this option, as used in B<Usage>

=back

The B<Usage> method prints a list of all possible options and returns.
It uses the B<Version> method for printing program name and version.


=head2 Event logging

  $server->Log($level, $format, @args);
  $server->Debug($format, @args);
  $server->Error($format, @args);
  $server->Fatal($format, @args);

The B<Log> method is an interface to L<Sys::Syslog (3)> or
L<Win32::EventLog (3)>. It's arguments are I<$level>, a syslog
level like B<debug>, B<notice> or B<err>, a format string in the
style of printf and the format strings arguments.

The B<Debug> and B<Error> methods are shorthands for calling
B<Log> with a level of debug and err, respectively. The B<Fatal>
method is like B<Error>, except it additionally throws the given
message as exception.


=head2 Flow of control

  $server->Bind();
  # The following inside Bind():
  if ($connection->Accept()) {
      $connection->Run();
  } else {
      $connection->Log('err', 'Connection refused');
  }

The B<Bind> method is called by the application when the server should
start. Typically this can be done right after creating the server object
B<$server>. B<Bind> usually never returns, except in case of errors.

When a client connects, the server uses B<Clone> to derive a connection
object B<$connection> from the server object. A new thread or process
is created that uses the connection object to call your classes
B<Accept> method. This method is intended for host authorization and
should return either FALSE (refuse the client) or TRUE (accept the client).

If the client is accepted, the B<Run> method is called which does the
true work. The connection is closed when B<Run> returns and the corresponding
thread or process exits.


=head2 Error Handling

All methods are supposed to throw Perl exceptions in case of errors.


=head1 MULTITHREADING CONSIDERATIONS

All methods are working with lexically scoped data and handle data
only, the exception being the OpenLog method which is invoked before
threading starts. Thus you are safe as long as you don't share
handles between threads. I strongly recommend that your application
behaves similar.



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
		  $self->Error("Client connection error %s",
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
	      $self->Error("Client connection error %s",
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

  All rights reserved.

  You may distribute this package under the terms of either the GNU
  General Public License or the Artistic License, as specified in the
  Perl README file.


=head1 SEE ALSO

L<RPC::pServer(3)>, L<Netserver::Generic(3)>

=cut

