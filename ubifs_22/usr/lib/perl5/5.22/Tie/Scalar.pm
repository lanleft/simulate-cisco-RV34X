package Tie::Scalar;

our $VERSION = '1.03';


use Carp;
use warnings::register;

sub new {
    my $pkg = shift;
    $pkg->TIESCALAR(@_);
}


sub TIESCALAR {
    my $pkg = shift;
    my $pkg_new = $pkg -> can ('new');

    if ($pkg_new and $pkg ne __PACKAGE__) {
        my $my_new = __PACKAGE__ -> can ('new');
        if ($pkg_new == $my_new) {  
            #
            # Prevent recursion
            #
            croak "$pkg must define either a TIESCALAR() or a new() method";
        }

	warnings::warnif ("WARNING: calling ${pkg}->new since " .
                          "${pkg}->TIESCALAR is missing");
	$pkg -> new (@_);
    }
    else {
	croak "$pkg doesn't define a TIESCALAR method";
    }
}

sub FETCH {
    my $pkg = ref $_[0];
    croak "$pkg doesn't define a FETCH method";
}

sub STORE {
    my $pkg = ref $_[0];
    croak "$pkg doesn't define a STORE method";
}

package Tie::StdScalar;
@ISA = qw(Tie::Scalar);

sub TIESCALAR {
    my $class = shift;
    my $instance = shift || undef;
    return bless \$instance => $class;
}

sub FETCH {
    return ${$_[0]};
}

sub STORE {
    ${$_[0]} = $_[1];
}

sub DESTROY {
    undef ${$_[0]};
}

1;
