package Digest::HMAC_SHA1;
$VERSION="1.03";

use strict;
use Digest::SHA qw(sha1);
use Digest::HMAC qw(hmac);

use vars qw(@ISA);
@ISA=qw(Digest::HMAC);
sub new
{
    my $class = shift;
    $class->SUPER::new($_[0], "Digest::SHA", 64);  # Digest::SHA defaults to SHA-1
}

require Exporter;
*import = \&Exporter::import;
use vars qw(@EXPORT_OK);
@EXPORT_OK=qw(hmac_sha1 hmac_sha1_hex);

sub hmac_sha1
{
    hmac($_[0], $_[1], \&sha1, 64);
}

sub hmac_sha1_hex
{
    unpack("H*", &hmac_sha1)
}

1;

__END__

