package deprecate;
use strict;
use warnings;
our $VERSION = 0.03;

our %Config;
unless (%Config) { require Config; *Config = \%Config::Config; }

sub __loaded_from_core {
    my ($package, $file, $expect_leaf) = @_;

    foreach my $pair ([qw(sitearchexp archlibexp)],
		      [qw(sitelibexp privlibexp)]) {
	my ($site, $priv) = @Config{@$pair};
	if ($^O eq 'VMS') {
	    for my $d ($site, $priv) { $d = VMS::Filespec::unixify($d) };
	}
	# Just in case anyone managed to configure with trailing /s
	s!/*$!!g foreach $site, $priv;

	next if $site eq $priv;
	if (uc("$priv/$expect_leaf") eq uc($file)) {
	    return 1;
	}
    }
    return 0;
}

sub import {
    my ($package, $file) = caller;

    my $expect_leaf = "$package.pm";
    $expect_leaf =~ s!::!/!g;

    if (__loaded_from_core($package, $file, $expect_leaf)) {
	my $call_depth=1;
	my @caller;
	while (@caller = caller $call_depth++) {
	    last if $caller[7]			# use/require
		and $caller[6] eq $expect_leaf;	# the package file
	}
	unless (@caller) {
	    require Carp;
	    Carp::cluck(<<"EOM");
Can't find use/require $expect_leaf in caller stack
EOM
	    return;
	}

	# This is fragile, because it
	# is directly poking in the internals of warnings.pm
	my ($call_file, $call_line, $callers_bitmask) = @caller[1,2,9];

	if (defined $callers_bitmask
	    && (vec($callers_bitmask, $warnings::Offsets{deprecated}, 1)
		|| vec($callers_bitmask, $warnings::Offsets{all}, 1))) {
	    warn <<"EOM";
$package will be removed from the Perl core distribution in the next major release. Please install it from CPAN. It is being used at $call_file, line $call_line.
EOM
	}
    }
}

1;

__END__

