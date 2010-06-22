#!/usr/bin/perl
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME	  => 'Net::Daemon',
    AUTHOR        => 'Jochen Wiedmann <joe@ispsoft.de>',
    VERSION_FROM  => 'lib/Net/Daemon.pm',
    ABSTRACT_FROM => 'lib/Net/Daemon.pm', 
    PL_FILES      => {},
    ($ExtUtils::MakeMaker::VERSION >= 6.3002 ? ('LICENSE'        => 'perl', ) : ()),
    PREREQ_PM => {
        'Symbol'  => 0,
        'File::Basename' => 0,
	'Getopt::Long' => 0,
	'IO::Socket' => 0,
	'Test::More' => 0,
    },
    'dist' => { 'DIST_DEFAULT' => q[all tardist],
	        'COMPRESS' => q[gzip -9vf],
	        'SUFFIX' => q[.gz]
	    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Net-Daemon-* *.pid' },
    realclean           => { 'FILES' => 't/config ndtest.prt Net-Daemon-* *.pid log' },
    META_MERGE  => {
	recommends => {
            'Sys::Syslog' => 0,
	    ($^O =~ m/MSWin32/i) ? ( 'Win32::EventLog' => 0) : (),
        },
        resources => {
            license => 'http://dev.perl.org/licenses/',
            homepage => 'http://wiki.github.com/toddr/Net-Daemon',
#            bugtracker => 'https://rt.cpan.org/Public/Dist/Display.html?Name=Net-Daemon',
            repository => 'http://github.com/toddr/Net-Daemon',
#            MailingList => 'http://groups.google.com/group/Net-Daemon',
        },
    },
);

package MY;

sub libscan {
    my ($self, $path) = @_;
    ($path =~ /\~$/) ? undef : $path;
}

sub postamble {
    qq{

pm_to_blib: README

README: lib/Net/Daemon.pm
\tpod2text lib/Net/Daemon.pm >README

}
}
