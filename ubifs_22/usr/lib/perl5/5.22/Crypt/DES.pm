
package Crypt::DES;

require Exporter;
require DynaLoader;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

@ISA = qw(Exporter DynaLoader);

@EXPORT =	qw();

@EXPORT_OK =	qw();

$VERSION = '2.07';
bootstrap Crypt::DES $VERSION;

use strict;
use Carp;

sub usage
{
	my ($package, $filename, $line, $subr) = caller(1);
	$Carp::CarpLevel = 2;
	croak "Usage: $subr(@_)";
}


sub blocksize { 8; }
sub keysize   { 8; }

sub new
{
	usage("new DES key") unless @_ == 2;

	my $type = shift;
	my $self = {};
	bless $self, $type;

	$self->{'ks'} = Crypt::DES::expand_key(shift);

	return $self;
}

sub encrypt
{
	usage("encrypt data[8 bytes]") unless @_ == 2;

	my ($self,$data) = @_;
	return Crypt::DES::crypt($data, $data, $self->{'ks'}, 1);
}

sub decrypt
{
	usage("decrypt data[8 bytes]") unless @_ == 2;

	my ($self,$data) = @_;
	return Crypt::DES::crypt($data, $data, $self->{'ks'}, 0);
}

1;

__END__

