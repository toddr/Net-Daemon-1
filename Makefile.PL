# -*- perl -*-

use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'	=> 'Net::Daemon',
    'VERSION_FROM' => 'Daemon.pm', # finds $VERSION
    'dist' => { 'DIST_DEFAULT' => q[all tardist],
	        'COMPRESS' => q[gzip -9f],
	        'SUFFIX' => q[.gz]
	    }
);
