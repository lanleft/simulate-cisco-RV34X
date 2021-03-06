package Digest::SHA1;

use strict;
use vars qw($VERSION @ISA @EXPORT_OK);

$VERSION = '2.13';

require Exporter;
*import = \&Exporter::import;
@EXPORT_OK = qw(sha1 sha1_hex sha1_base64 sha1_transform);

require DynaLoader;
@ISA=qw(DynaLoader);

eval {
    require Digest::base;
    push(@ISA, 'Digest::base');
};
if ($@) {
    my $err = $@;
    *add_bits = sub { die $err };
}

Digest::SHA1->bootstrap($VERSION);

1;
__END__

