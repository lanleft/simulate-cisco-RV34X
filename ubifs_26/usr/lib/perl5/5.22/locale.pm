package locale;

our $VERSION = '1.06';
use Config;

$Carp::Internal{ (__PACKAGE__) } = 1;



$locale::hint_bits = 0x4;
$locale::partial_hint_bits = 0x10;  # If pragma has an argument


sub import {
    shift;  # should be 'locale'; not checked

    $^H{locale} = 0 unless defined $^H{locale};
    if (! @_) { # If no parameter, use the plain form that changes all categories
        $^H |= $locale::hint_bits;

    }
    else {
        my @categories = ( qw(:ctype :collate :messages
                              :numeric :monetary :time) );
        for (my $i = 0; $i < @_; $i++) {
            my $arg = $_[$i];
            $complement = $arg =~ s/ : ( ! | not_ ) /:/x;
            if (! grep { $arg eq $_ } @categories, ":characters") {
                require Carp;
                Carp::croak("Unknown parameter '$_[$i]' to 'use locale'");
            }

            if ($complement) {
                if ($i != 0 || $i < @_ - 1)  {
                    require Carp;
                    Carp::croak("Only one argument to 'use locale' allowed"
                                . "if is $complement");
                }

                if ($arg eq ':characters') {
                    push @_, grep { $_ ne ':ctype' && $_ ne ':collate' }
                                  @categories;
                    # We add 1 to the category number;  This category number
                    # is -1
                    $^H{locale} |= (1 << 0);
                }
                else {
                    push @_, grep { $_ ne $arg } @categories;
                }
                next;
            }
            elsif ($arg eq ':characters') {
                push @_, ':ctype', ':collate';
                next;
            }

            $^H |= $locale::partial_hint_bits;

            # This form of the pragma overrides the other
            $^H &= ~$locale::hint_bits;

            $arg =~ s/^://;

            eval { require POSIX; import POSIX 'locale_h'; };
            unless (defined &POSIX::LC_CTYPE) {
              return;
            }

            # Map our names to the ones defined by POSIX
            $arg = "LC_" . uc($arg);

            my $bit = eval "&POSIX::$arg";
            if (defined $bit) {
                # 1 is added so that the pseudo-category :characters, which is
                # -1, comes out 0.
                $^H{locale} |= 1 << ($bit + 1);
            }
        }
    }

}

sub unimport {
    $^H &= ~($locale::hint_bits|$locale::partial_hint_bits);
    $^H{locale} = 0;
}

1;
