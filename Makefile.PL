# -*- perl -*-

use ExtUtils::MakeMaker;

my %opts = (
    'NAME'	=> 'Net::Daemon',
    'VERSION_FROM' => 'Daemon.pm', # finds $VERSION
    'dist' => { 'DIST_DEFAULT' => q[all tardist],
	        'COMPRESS' => q[gzip -9vf],
	        'SUFFIX' => q[.gz]
	    }
);

if ($ExtUtils::MakeMaker::VERSION >= 5.43) {
    $opts{ABSTRACT_FROM} = 'Daemon.pm';
    $opts{AUTHOR} = 'Jochen Wiedmann (joe@ispsoft.de)';
}

WriteMakefile(%opts);


package MY;

sub libscan {
    my ($self, $path) = @_;
    ($path =~ /\~$/) ? undef : $path;
}
