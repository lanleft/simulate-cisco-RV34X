package IO::Uncompress::AnyUncompress ;

use strict;
use warnings;
use bytes;

use IO::Compress::Base::Common 2.068 ();

use IO::Uncompress::Base 2.068 ;


require Exporter ;

our ($VERSION, @ISA, @EXPORT_OK, %EXPORT_TAGS, $AnyUncompressError);

$VERSION = '2.068';
$AnyUncompressError = '';

@ISA = qw( Exporter IO::Uncompress::Base );
@EXPORT_OK = qw( $AnyUncompressError anyuncompress ) ;
%EXPORT_TAGS = %IO::Uncompress::Base::DEFLATE_CONSTANTS ;
push @{ $EXPORT_TAGS{all} }, @EXPORT_OK ;
Exporter::export_ok_tags('all');


BEGIN
{
   eval ' use IO::Uncompress::Adapter::Inflate 2.068 ;';
   eval ' use IO::Uncompress::Adapter::Bunzip2 2.068 ;';
   eval ' use IO::Uncompress::Adapter::LZO 2.068 ;';
   eval ' use IO::Uncompress::Adapter::Lzf 2.068 ;';
   eval ' use IO::Uncompress::Adapter::UnLzma 2.068 ;';
   eval ' use IO::Uncompress::Adapter::UnXz 2.068 ;';

   eval ' use IO::Uncompress::Bunzip2 2.068 ;';
   eval ' use IO::Uncompress::UnLzop 2.068 ;';
   eval ' use IO::Uncompress::Gunzip 2.068 ;';
   eval ' use IO::Uncompress::Inflate 2.068 ;';
   eval ' use IO::Uncompress::RawInflate 2.068 ;';
   eval ' use IO::Uncompress::Unzip 2.068 ;';
   eval ' use IO::Uncompress::UnLzf 2.068 ;';
   eval ' use IO::Uncompress::UnLzma 2.068 ;';
   eval ' use IO::Uncompress::UnXz 2.068 ;';
}

sub new
{
    my $class = shift ;
    my $obj = IO::Compress::Base::Common::createSelfTiedObject($class, \$AnyUncompressError);
    $obj->_create(undef, 0, @_);
}

sub anyuncompress
{
    my $obj = IO::Compress::Base::Common::createSelfTiedObject(undef, \$AnyUncompressError);
    return $obj->_inf(@_) ;
}

sub getExtraParams
{ 
    return ( 'rawinflate' => [IO::Compress::Base::Common::Parse_boolean,  0] ,
             'unlzma'     => [IO::Compress::Base::Common::Parse_boolean,  0] ) ;
}

sub ckParams
{
    my $self = shift ;
    my $got = shift ;

    # any always needs both crc32 and adler32
    $got->setValue('crc32' => 1);
    $got->setValue('adler32' => 1);

    return 1;
}

sub mkUncomp
{
    my $self = shift ;
    my $got = shift ;

    my $magic ;

    # try zlib first
    if (defined $IO::Uncompress::RawInflate::VERSION )
    {
        my ($obj, $errstr, $errno) = IO::Uncompress::Adapter::Inflate::mkUncompObject();

        return $self->saveErrorString(undef, $errstr, $errno)
            if ! defined $obj;

        *$self->{Uncomp} = $obj;
        
        my @possible = qw( Inflate Gunzip Unzip );
        unshift @possible, 'RawInflate' 
            if $got->getValue('rawinflate');

        $magic = $self->ckMagic( @possible );
        
        if ($magic) {
            *$self->{Info} = $self->readHeader($magic)
                or return undef ;

            return 1;
        }
     }

    if (defined $IO::Uncompress::UnLzma::VERSION && $got->getValue('unlzma'))
    {
        my ($obj, $errstr, $errno) = IO::Uncompress::Adapter::UnLzma::mkUncompObject();

        return $self->saveErrorString(undef, $errstr, $errno)
            if ! defined $obj;

        *$self->{Uncomp} = $obj;
        
        my @possible = qw( UnLzma );
        #unshift @possible, 'RawInflate' 
        #    if $got->getValue('rawinflate');

        if ( *$self->{Info} = $self->ckMagic( @possible ))
        {
            return 1;
        }
     }

     if (defined $IO::Uncompress::UnXz::VERSION and
         $magic = $self->ckMagic('UnXz')) {
        *$self->{Info} = $self->readHeader($magic)
            or return undef ;

        my ($obj, $errstr, $errno) =
            IO::Uncompress::Adapter::UnXz::mkUncompObject();

        return $self->saveErrorString(undef, $errstr, $errno)
            if ! defined $obj;

        *$self->{Uncomp} = $obj;

         return 1;
     }

     if (defined $IO::Uncompress::Bunzip2::VERSION and
         $magic = $self->ckMagic('Bunzip2')) {
        *$self->{Info} = $self->readHeader($magic)
            or return undef ;

        my ($obj, $errstr, $errno) = IO::Uncompress::Adapter::Bunzip2::mkUncompObject();

        return $self->saveErrorString(undef, $errstr, $errno)
            if ! defined $obj;

        *$self->{Uncomp} = $obj;

         return 1;
     }

     if (defined $IO::Uncompress::UnLzop::VERSION and
            $magic = $self->ckMagic('UnLzop')) {

        *$self->{Info} = $self->readHeader($magic)
            or return undef ;

        my ($obj, $errstr, $errno) = IO::Uncompress::Adapter::LZO::mkUncompObject();

        return $self->saveErrorString(undef, $errstr, $errno)
            if ! defined $obj;

        *$self->{Uncomp} = $obj;

         return 1;
     }

     if (defined $IO::Uncompress::UnLzf::VERSION and
            $magic = $self->ckMagic('UnLzf')) {

        *$self->{Info} = $self->readHeader($magic)
            or return undef ;

        my ($obj, $errstr, $errno) = IO::Uncompress::Adapter::Lzf::mkUncompObject();

        return $self->saveErrorString(undef, $errstr, $errno)
            if ! defined $obj;

        *$self->{Uncomp} = $obj;

         return 1;
     }

     return 0 ;
}



sub ckMagic
{
    my $self = shift;
    my @names = @_ ;

    my $keep = ref $self ;
    for my $class ( map { "IO::Uncompress::$_" } @names)
    {
        bless $self => $class;
        my $magic = $self->ckMagic();

        if ($magic)
        {
            #bless $self => $class;
            return $magic ;
        }

        $self->pushBack(*$self->{HeaderPending})  ;
        *$self->{HeaderPending} = ''  ;
    }    

    bless $self => $keep;
    return undef;
}

1 ;

__END__


