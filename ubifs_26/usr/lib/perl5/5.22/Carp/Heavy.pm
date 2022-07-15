package Carp::Heavy;

use Carp ();

our $VERSION = '1.36';

if(($Carp::VERSION || 0) < 1.12) {
	my $cv = defined($Carp::VERSION) ? $Carp::VERSION : "undef";
	die "Version mismatch between Carp $cv ($INC{q(Carp.pm)}) and Carp::Heavy $VERSION ($INC{q(Carp/Heavy.pm)}).  Did you alter \@INC after Carp was loaded?\n";
}

1;

