package IO::Uncompress::Unzip;

require 5.006 ;


use strict ;
use warnings;

use IO::File;
use IO::Uncompress::RawInflate  2.068 ;
use IO::Compress::Base::Common  2.068 qw(:Status );
use IO::Uncompress::Adapter::Inflate  2.068 ;
use IO::Uncompress::Adapter::Identity 2.068 ;
use IO::Compress::Zlib::Extra 2.068 ;
use IO::Compress::Zip::Constants 2.068 ;

use Compress::Raw::Zlib  2.068 () ;

BEGIN
{
    eval{ require IO::Uncompress::Adapter::Bunzip2 ;
           import  IO::Uncompress::Adapter::Bunzip2 } ;
    eval{ require IO::Uncompress::Adapter::UnLzma ;
          import  IO::Uncompress::Adapter::UnLzma } ;
}


require Exporter ;

our ($VERSION, @ISA, @EXPORT_OK, %EXPORT_TAGS, $UnzipError, %headerLookup);

$VERSION = '2.068';
$UnzipError = '';

@ISA    = qw(Exporter IO::Uncompress::RawInflate);
@EXPORT_OK = qw( $UnzipError unzip );
%EXPORT_TAGS = %IO::Uncompress::RawInflate::EXPORT_TAGS ;
push @{ $EXPORT_TAGS{all} }, @EXPORT_OK ;
Exporter::export_ok_tags('all');

%headerLookup = (
        ZIP_CENTRAL_HDR_SIG,            \&skipCentralDirectory,
        ZIP_END_CENTRAL_HDR_SIG,        \&skipEndCentralDirectory,
        ZIP64_END_CENTRAL_REC_HDR_SIG,  \&skipCentralDirectory64Rec,
        ZIP64_END_CENTRAL_LOC_HDR_SIG,  \&skipCentralDirectory64Loc,
        ZIP64_ARCHIVE_EXTRA_SIG,        \&skipArchiveExtra,
        ZIP64_DIGITAL_SIGNATURE_SIG,    \&skipDigitalSignature,
        );

sub new
{
    my $class = shift ;
    my $obj = IO::Compress::Base::Common::createSelfTiedObject($class, \$UnzipError);
    $obj->_create(undef, 0, @_);
}

sub unzip
{
    my $obj = IO::Compress::Base::Common::createSelfTiedObject(undef, \$UnzipError);
    return $obj->_inf(@_) ;
}

sub getExtraParams
{
   
    return (
            'name'    => [IO::Compress::Base::Common::Parse_any,       undef],

            'stream'  => [IO::Compress::Base::Common::Parse_boolean,   0],
            
            # TODO - This means reading the central directory to get
            # 1. the local header offsets
            # 2. The compressed data length
        );    
}

sub ckParams
{
    my $self = shift ;
    my $got = shift ;

    # unzip always needs crc32
    $got->setValue('crc32' => 1);

    *$self->{UnzipData}{Name} = $got->getValue('name');

    return 1;
}

sub mkUncomp
{
    my $self = shift ;
    my $got = shift ;

     my $magic = $self->ckMagic()
        or return 0;

    *$self->{Info} = $self->readHeader($magic)
        or return undef ;

    return 1;

}

sub ckMagic
{
    my $self = shift;

    my $magic ;
    $self->smartReadExact(\$magic, 4);

    *$self->{HeaderPending} = $magic ;

    return $self->HeaderError("Minimum header size is " . 
                              4 . " bytes") 
        if length $magic != 4 ;                                    

    return $self->HeaderError("Bad Magic")
        if ! _isZipMagic($magic) ;

    *$self->{Type} = 'zip';

    return $magic ;
}


sub fastForward
{
    my $self = shift;
    my $offset = shift;

    # TODO - if Stream isn't enabled & reading from file, use seek

    my $buffer = '';
    my $c = 1024 * 16;

    while ($offset > 0)
    {
        $c = length $offset
            if length $offset < $c ;

        $offset -= $c;

        $self->smartReadExact(\$buffer, $c)
            or return 0;
    }

    return 1;
}


sub readHeader
{
    my $self = shift;
    my $magic = shift ;

    my $name =  *$self->{UnzipData}{Name} ;
    my $hdr = $self->_readZipHeader($magic) ;

    while (defined $hdr)
    {
        if (! defined $name || $hdr->{Name} eq $name)
        {
            return $hdr ;
        }

        # skip the data
        # TODO - when Stream is off, use seek
        my $buffer;
        if (*$self->{ZipData}{Streaming}) {

            while (1) {

                my $b;
                my $status = $self->smartRead(\$b, 1024 * 16);
                return undef
                    if $status <= 0 ;

                my $temp_buf;
                my $out;
                $status = *$self->{Uncomp}->uncompr(\$b, \$temp_buf, 0, $out);

                return $self->saveErrorString(undef, *$self->{Uncomp}{Error}, 
                                                     *$self->{Uncomp}{ErrorNo})
                    if $self->saveStatus($status) == STATUS_ERROR;                

                if ($status == STATUS_ENDSTREAM) {
                    *$self->{Uncomp}->reset();
                    $self->pushBack($b)  ;
                    last;
                }
            }

            # skip the trailer
            $self->smartReadExact(\$buffer, $hdr->{TrailerLength})
                or return $self->saveErrorString(undef, "Truncated file");
        }
        else {
            my $c = $hdr->{CompressedLength}->get64bit();
            $self->fastForward($c)
                or return $self->saveErrorString(undef, "Truncated file");
            $buffer = '';
        }

        $self->chkTrailer($buffer) == STATUS_OK
            or return $self->saveErrorString(undef, "Truncated file");

        $hdr = $self->_readFullZipHeader();

        return $self->saveErrorString(undef, "Cannot find '$name'")
            if $self->smartEof();
    }

    return undef;
}

sub chkTrailer
{
    my $self = shift;
    my $trailer = shift;

    my ($sig, $CRC32, $cSize, $uSize) ;
    my ($cSizeHi, $uSizeHi) = (0, 0);
    if (*$self->{ZipData}{Streaming}) {
        $sig   = unpack ("V", substr($trailer, 0, 4));
        $CRC32 = unpack ("V", substr($trailer, 4, 4));

        if (*$self->{ZipData}{Zip64} ) {
            $cSize = U64::newUnpack_V64 substr($trailer,  8, 8);
            $uSize = U64::newUnpack_V64 substr($trailer, 16, 8);
        }
        else {
            $cSize = U64::newUnpack_V32 substr($trailer,  8, 4);
            $uSize = U64::newUnpack_V32 substr($trailer, 12, 4);
        }

        return $self->TrailerError("Data Descriptor signature, got $sig")
            if $sig != ZIP_DATA_HDR_SIG;
    }
    else {
        ($CRC32, $cSize, $uSize) = 
            (*$self->{ZipData}{Crc32},
             *$self->{ZipData}{CompressedLen},
             *$self->{ZipData}{UnCompressedLen});
    }

    *$self->{Info}{CRC32} = *$self->{ZipData}{CRC32} ;
    *$self->{Info}{CompressedLength} = $cSize->get64bit();
    *$self->{Info}{UncompressedLength} = $uSize->get64bit();

    if (*$self->{Strict}) {
        return $self->TrailerError("CRC mismatch")
            if $CRC32  != *$self->{ZipData}{CRC32} ;

        return $self->TrailerError("CSIZE mismatch.")
            if ! $cSize->equal(*$self->{CompSize});

        return $self->TrailerError("USIZE mismatch.")
            if ! $uSize->equal(*$self->{UnCompSize});
    }

    my $reachedEnd = STATUS_ERROR ;
    # check for central directory or end of central directory
    while (1)
    {
        my $magic ;
        my $got = $self->smartRead(\$magic, 4);

        return $self->saveErrorString(STATUS_ERROR, "Truncated file")
            if $got != 4 && *$self->{Strict};

        if ($got == 0) {
            return STATUS_EOF ;
        }
        elsif ($got < 0) {
            return STATUS_ERROR ;
        }
        elsif ($got < 4) {
            $self->pushBack($magic)  ;
            return STATUS_OK ;
        }

        my $sig = unpack("V", $magic) ;

        my $hdr;
        if ($hdr = $headerLookup{$sig})
        {
            if (&$hdr($self, $magic) != STATUS_OK ) {
                if (*$self->{Strict}) {
                    return STATUS_ERROR ;
                }
                else {
                    $self->clearError();
                    return STATUS_OK ;
                }
            }

            if ($sig == ZIP_END_CENTRAL_HDR_SIG)
            {
                return STATUS_OK ;
                last;
            }
        }
        elsif ($sig == ZIP_LOCAL_HDR_SIG)
        {
            $self->pushBack($magic)  ;
            return STATUS_OK ;
        }
        else
        {
            # put the data back
            $self->pushBack($magic)  ;
            last;
        }
    }

    return $reachedEnd ;
}

sub skipCentralDirectory
{
    my $self = shift;
    my $magic = shift ;

    my $buffer;
    $self->smartReadExact(\$buffer, 46 - 4)
        or return $self->TrailerError("Minimum header size is " . 
                                     46 . " bytes") ;

    my $keep = $magic . $buffer ;
    *$self->{HeaderPending} = $keep ;

   #my $versionMadeBy      = unpack ("v", substr($buffer, 4-4,  2));
   #my $extractVersion     = unpack ("v", substr($buffer, 6-4,  2));
   #my $gpFlag             = unpack ("v", substr($buffer, 8-4,  2));
   #my $compressedMethod   = unpack ("v", substr($buffer, 10-4, 2));
   #my $lastModTime        = unpack ("V", substr($buffer, 12-4, 4));
   #my $crc32              = unpack ("V", substr($buffer, 16-4, 4));
    my $compressedLength   = unpack ("V", substr($buffer, 20-4, 4));
    my $uncompressedLength = unpack ("V", substr($buffer, 24-4, 4));
    my $filename_length    = unpack ("v", substr($buffer, 28-4, 2)); 
    my $extra_length       = unpack ("v", substr($buffer, 30-4, 2));
    my $comment_length     = unpack ("v", substr($buffer, 32-4, 2));
   #my $disk_start         = unpack ("v", substr($buffer, 34-4, 2));
   #my $int_file_attrib    = unpack ("v", substr($buffer, 36-4, 2));
   #my $ext_file_attrib    = unpack ("V", substr($buffer, 38-4, 2));
   #my $lcl_hdr_offset     = unpack ("V", substr($buffer, 42-4, 2));

    
    my $filename;
    my $extraField;
    my $comment ;
    if ($filename_length)
    {
        $self->smartReadExact(\$filename, $filename_length)
            or return $self->TruncatedTrailer("filename");
        $keep .= $filename ;
    }

    if ($extra_length)
    {
        $self->smartReadExact(\$extraField, $extra_length)
            or return $self->TruncatedTrailer("extra");
        $keep .= $extraField ;
    }

    if ($comment_length)
    {
        $self->smartReadExact(\$comment, $comment_length)
            or return $self->TruncatedTrailer("comment");
        $keep .= $comment ;
    }

    return STATUS_OK ;
}

sub skipArchiveExtra
{
    my $self = shift;
    my $magic = shift ;

    my $buffer;
    $self->smartReadExact(\$buffer, 4)
        or return $self->TrailerError("Minimum header size is " . 
                                     4 . " bytes") ;

    my $keep = $magic . $buffer ;

    my $size = unpack ("V", $buffer);

    $self->smartReadExact(\$buffer, $size)
        or return $self->TrailerError("Minimum header size is " . 
                                     $size . " bytes") ;

    $keep .= $buffer ;
    *$self->{HeaderPending} = $keep ;

    return STATUS_OK ;
}


sub skipCentralDirectory64Rec
{
    my $self = shift;
    my $magic = shift ;

    my $buffer;
    $self->smartReadExact(\$buffer, 8)
        or return $self->TrailerError("Minimum header size is " . 
                                     8 . " bytes") ;

    my $keep = $magic . $buffer ;

    my ($sizeLo, $sizeHi)  = unpack ("V V", $buffer);
    my $size = $sizeHi * U64::MAX32 + $sizeLo;

    $self->fastForward($size)
        or return $self->TrailerError("Minimum header size is " . 
                                     $size . " bytes") ;

   #$keep .= $buffer ;
   #*$self->{HeaderPending} = $keep ;

   #my $versionMadeBy      = unpack ("v",   substr($buffer,  0, 2));
   #my $extractVersion     = unpack ("v",   substr($buffer,  2, 2));
   #my $diskNumber         = unpack ("V",   substr($buffer,  4, 4));
   #my $cntrlDirDiskNo     = unpack ("V",   substr($buffer,  8, 4));
   #my $entriesInThisCD    = unpack ("V V", substr($buffer, 12, 8));
   #my $entriesInCD        = unpack ("V V", substr($buffer, 20, 8));
   #my $sizeOfCD           = unpack ("V V", substr($buffer, 28, 8));
   #my $offsetToCD         = unpack ("V V", substr($buffer, 36, 8));

    return STATUS_OK ;
}

sub skipCentralDirectory64Loc
{
    my $self = shift;
    my $magic = shift ;

    my $buffer;
    $self->smartReadExact(\$buffer, 20 - 4)
        or return $self->TrailerError("Minimum header size is " . 
                                     20 . " bytes") ;

    my $keep = $magic . $buffer ;
    *$self->{HeaderPending} = $keep ;

   #my $startCdDisk        = unpack ("V",   substr($buffer,  4-4, 4));
   #my $offsetToCD         = unpack ("V V", substr($buffer,  8-4, 8));
   #my $diskCount          = unpack ("V",   substr($buffer, 16-4, 4));

    return STATUS_OK ;
}

sub skipEndCentralDirectory
{
    my $self = shift;
    my $magic = shift ;

    my $buffer;
    $self->smartReadExact(\$buffer, 22 - 4)
        or return $self->TrailerError("Minimum header size is " . 
                                     22 . " bytes") ;

    my $keep = $magic . $buffer ;
    *$self->{HeaderPending} = $keep ;

   #my $diskNumber         = unpack ("v", substr($buffer, 4-4,  2));
   #my $cntrlDirDiskNo     = unpack ("v", substr($buffer, 6-4,  2));
   #my $entriesInThisCD    = unpack ("v", substr($buffer, 8-4,  2));
   #my $entriesInCD        = unpack ("v", substr($buffer, 10-4, 2));
   #my $sizeOfCD           = unpack ("V", substr($buffer, 12-4, 4));
   #my $offsetToCD         = unpack ("V", substr($buffer, 16-4, 4));
    my $comment_length     = unpack ("v", substr($buffer, 20-4, 2));

    
    my $comment ;
    if ($comment_length)
    {
        $self->smartReadExact(\$comment, $comment_length)
            or return $self->TruncatedTrailer("comment");
        $keep .= $comment ;
    }

    return STATUS_OK ;
}


sub _isZipMagic
{
    my $buffer = shift ;
    return 0 if length $buffer < 4 ;
    my $sig = unpack("V", $buffer) ;
    return $sig == ZIP_LOCAL_HDR_SIG ;
}


sub _readFullZipHeader($)
{
    my ($self) = @_ ;
    my $magic = '' ;

    $self->smartReadExact(\$magic, 4);

    *$self->{HeaderPending} = $magic ;

    return $self->HeaderError("Minimum header size is " . 
                              30 . " bytes") 
        if length $magic != 4 ;                                    


    return $self->HeaderError("Bad Magic")
        if ! _isZipMagic($magic) ;

    my $status = $self->_readZipHeader($magic);
    delete *$self->{Transparent} if ! defined $status ;
    return $status ;
}

sub _readZipHeader($)
{
    my ($self, $magic) = @_ ;
    my ($HeaderCRC) ;
    my ($buffer) = '' ;

    $self->smartReadExact(\$buffer, 30 - 4)
        or return $self->HeaderError("Minimum header size is " . 
                                     30 . " bytes") ;

    my $keep = $magic . $buffer ;
    *$self->{HeaderPending} = $keep ;

    my $extractVersion     = unpack ("v", substr($buffer, 4-4,  2));
    my $gpFlag             = unpack ("v", substr($buffer, 6-4,  2));
    my $compressedMethod   = unpack ("v", substr($buffer, 8-4,  2));
    my $lastModTime        = unpack ("V", substr($buffer, 10-4, 4));
    my $crc32              = unpack ("V", substr($buffer, 14-4, 4));
    my $compressedLength   = U64::newUnpack_V32 substr($buffer, 18-4, 4);
    my $uncompressedLength = U64::newUnpack_V32 substr($buffer, 22-4, 4);
    my $filename_length    = unpack ("v", substr($buffer, 26-4, 2)); 
    my $extra_length       = unpack ("v", substr($buffer, 28-4, 2));

    my $filename;
    my $extraField;
    my @EXTRA = ();
    my $streamingMode = ($gpFlag & ZIP_GP_FLAG_STREAMING_MASK) ? 1 : 0 ;

    return $self->HeaderError("Encrypted content not supported")
        if $gpFlag & (ZIP_GP_FLAG_ENCRYPTED_MASK|ZIP_GP_FLAG_STRONG_ENCRYPTED_MASK);

    return $self->HeaderError("Patch content not supported")
        if $gpFlag & ZIP_GP_FLAG_PATCHED_MASK;

    *$self->{ZipData}{Streaming} = $streamingMode;


    if ($filename_length)
    {
        $self->smartReadExact(\$filename, $filename_length)
            or return $self->TruncatedHeader("Filename");
        $keep .= $filename ;
    }

    my $zip64 = 0 ;

    if ($extra_length)
    {
        $self->smartReadExact(\$extraField, $extra_length)
            or return $self->TruncatedHeader("Extra Field");

        my $bad = IO::Compress::Zlib::Extra::parseRawExtra($extraField,
                                                \@EXTRA, 1, 0);
        return $self->HeaderError($bad)
            if defined $bad;

        $keep .= $extraField ;

        my %Extra ;
        for (@EXTRA)
        {
            $Extra{$_->[0]} = \$_->[1];
        }
        
        if (defined $Extra{ZIP_EXTRA_ID_ZIP64()})
        {
            $zip64 = 1 ;

            my $buff = ${ $Extra{ZIP_EXTRA_ID_ZIP64()} };

            # This code assumes that all the fields in the Zip64
            # extra field aren't necessarily present. The spec says that
            # they only exist if the equivalent local headers are -1.

            if (! $streamingMode) {
                my $offset = 0 ;

                if (U64::full32 $uncompressedLength->get32bit() ) {
                    $uncompressedLength 
                            = U64::newUnpack_V64 substr($buff, 0, 8);

                    $offset += 8 ;
                }

                if (U64::full32 $compressedLength->get32bit() ) {

                    $compressedLength 
                        = U64::newUnpack_V64 substr($buff, $offset, 8);

                    $offset += 8 ;
                }
           }
        }
    }

    *$self->{ZipData}{Zip64} = $zip64;

    if (! $streamingMode) {
        *$self->{ZipData}{Streaming} = 0;
        *$self->{ZipData}{Crc32} = $crc32;
        *$self->{ZipData}{CompressedLen} = $compressedLength;
        *$self->{ZipData}{UnCompressedLen} = $uncompressedLength;
        *$self->{CompressedInputLengthRemaining} =
            *$self->{CompressedInputLength} = $compressedLength->get64bit();
    }

    *$self->{ZipData}{CRC32} = Compress::Raw::Zlib::crc32(undef);
    *$self->{ZipData}{Method} = $compressedMethod;
    if ($compressedMethod == ZIP_CM_DEFLATE)
    {
        *$self->{Type} = 'zip-deflate';
        my $obj = IO::Uncompress::Adapter::Inflate::mkUncompObject(1,0,0);

        *$self->{Uncomp} = $obj;
    }
    elsif ($compressedMethod == ZIP_CM_BZIP2)
    {
        return $self->HeaderError("Unsupported Compression format $compressedMethod")
            if ! defined $IO::Uncompress::Adapter::Bunzip2::VERSION ;
        
        *$self->{Type} = 'zip-bzip2';
        
        my $obj = IO::Uncompress::Adapter::Bunzip2::mkUncompObject();

        *$self->{Uncomp} = $obj;
    }
    elsif ($compressedMethod == ZIP_CM_LZMA)
    {
        return $self->HeaderError("Unsupported Compression format $compressedMethod")
            if ! defined $IO::Uncompress::Adapter::UnLzma::VERSION ;
        
        *$self->{Type} = 'zip-lzma';
        my $LzmaHeader;
        $self->smartReadExact(\$LzmaHeader, 4)
                or return $self->saveErrorString(undef, "Truncated file");
        my ($verHi, $verLo)   = unpack ("CC", substr($LzmaHeader, 0, 2));
        my $LzmaPropertiesSize   = unpack ("v", substr($LzmaHeader, 2, 2));


        my $LzmaPropertyData;
        $self->smartReadExact(\$LzmaPropertyData, $LzmaPropertiesSize)
                or return $self->saveErrorString(undef, "Truncated file");

        if (! $streamingMode) {
            *$self->{ZipData}{CompressedLen}->subtract(4 + $LzmaPropertiesSize) ;
            *$self->{CompressedInputLengthRemaining} =
                *$self->{CompressedInputLength} = *$self->{ZipData}{CompressedLen}->get64bit();
        }

        my $obj =
            IO::Uncompress::Adapter::UnLzma::mkUncompZipObject($LzmaPropertyData);

        *$self->{Uncomp} = $obj;
    }
    elsif ($compressedMethod == ZIP_CM_STORE)
    {
        *$self->{Type} = 'zip-stored';
        
        my $obj =
        IO::Uncompress::Adapter::Identity::mkUncompObject($streamingMode,
                                                          $zip64);

        *$self->{Uncomp} = $obj;
    }
    else
    {
        return $self->HeaderError("Unsupported Compression format $compressedMethod");
    }

    return {
        'Type'               => 'zip',
        'FingerprintLength'  => 4,
        #'HeaderLength'       => $compressedMethod == 8 ? length $keep : 0,
        'HeaderLength'       => length $keep,
        'Zip64'              => $zip64,
        'TrailerLength'      => ! $streamingMode ? 0 : $zip64 ? 24 : 16,
        'Header'             => $keep,
        'CompressedLength'   => $compressedLength ,
        'UncompressedLength' => $uncompressedLength ,
        'CRC32'              => $crc32 ,
        'Name'               => $filename,
        'Time'               => _dosToUnixTime($lastModTime),
        'Stream'             => $streamingMode,

        'MethodID'           => $compressedMethod,
        'MethodName'         => $compressedMethod == ZIP_CM_DEFLATE 
                                 ? "Deflated" 
                                 : $compressedMethod == ZIP_CM_BZIP2
                                     ? "Bzip2"
                                     : $compressedMethod == ZIP_CM_LZMA
                                         ? "Lzma"
                                         : $compressedMethod == ZIP_CM_STORE
                                             ? "Stored"
                                             : "Unknown" ,

        'ExtraFieldRaw' => $extraField,
        'ExtraField'    => [ @EXTRA ],


      }
}

sub filterUncompressed
{
    my $self = shift ;

    if (*$self->{ZipData}{Method} == ZIP_CM_DEFLATE) {
        *$self->{ZipData}{CRC32} = *$self->{Uncomp}->crc32() ;
    }
    else {
        *$self->{ZipData}{CRC32} = Compress::Raw::Zlib::crc32(${$_[0]}, *$self->{ZipData}{CRC32}, $_[1]);
    }
}    


sub _dosToUnixTime
{
	my $dt = shift;

	my $year = ( ( $dt >> 25 ) & 0x7f ) + 80;
	my $mon  = ( ( $dt >> 21 ) & 0x0f ) - 1;
	my $mday = ( ( $dt >> 16 ) & 0x1f );

	my $hour = ( ( $dt >> 11 ) & 0x1f );
	my $min  = ( ( $dt >> 5 ) & 0x3f );
	my $sec  = ( ( $dt << 1 ) & 0x3e );


    use POSIX 'mktime';

    my $time_t = mktime( $sec, $min, $hour, $mday, $mon, $year, 0, 0, -1 );
    return 0 if ! defined $time_t;
	return $time_t;
}



sub skip
{
    my $self = shift;
    my $size = shift;

    use Fcntl qw(SEEK_CUR);
    if (ref $size eq 'U64') {
        $self->smartSeek($size->get64bit(), SEEK_CUR);
    }
    else {
        $self->smartSeek($size, SEEK_CUR);
    }
    
}


sub scanCentralDirectory
{
    my $self = shift;

    my $here = $self->tell();

    # Use cases
    # 1 32-bit CD
    # 2 64-bit CD

    my @CD = ();
    my $offset = $self->findCentralDirectoryOffset();

    return ()
        if ! defined $offset;

    $self->smarkSeek($offset, 0, SEEK_SET) ;

    # Now walk the Central Directory Records
    my $buffer ;
    while ($self->smartReadExact(\$buffer, 46) && 
           unpack("V", $buffer) == ZIP_CENTRAL_HDR_SIG) {

        my $compressedLength   = unpack("V", substr($buffer, 20, 4));
        my $uncompressedLength = unpack("V", substr($buffer, 24, 4));
        my $filename_length    = unpack("v", substr($buffer, 28, 2));
        my $extra_length       = unpack("v", substr($buffer, 30, 2));
        my $comment_length     = unpack("v", substr($buffer, 32, 2));

        $self->skip($filename_length ) ;

        my $v64 = new U64 $compressedLength ;

        if (U64::full32 $compressedLength ) {
            $self->smartReadExact(\$buffer, $extra_length) ;
            die "xxx $offset $comment_length $filename_length $extra_length" . length($buffer) 
                if length($buffer) != $extra_length;
            my $got = $self->get64Extra($buffer, U64::full32 $uncompressedLength);

            # If not Zip64 extra field, assume size is 0xFFFFFFFF
            $v64 = $got if defined $got;
        }
        else {
            $self->skip($extra_length) ;
        }

        $self->skip($comment_length ) ;
            
        push @CD, $v64 ;
    }

    $self->smartSeek($here, 0, SEEK_SET) ;

    return @CD;
}

sub get64Extra
{
    my $self = shift ;

    my $buffer = shift;
    my $is_uncomp = shift ;

    my $extra = IO::Compress::Zlib::Extra::findID(0x0001, $buffer);
                                            
    if (! defined $extra)
    {
        return undef;
    }
    else
    {
        my $u64 = U64::newUnpack_V64(substr($extra,  $is_uncomp ? 8 : 0)) ;
        return $u64;
    }    
}

sub offsetFromZip64
{
    my $self = shift ;
    my $here = shift;

    $self->smartSeek($here - 20, 0, SEEK_SET) 
        or die "xx $!" ;

    my $buffer;
    my $got = 0;
    $self->smartReadExact(\$buffer, 20)  
        or die "xxx $here $got $!" ;

    if ( unpack("V", $buffer) == ZIP64_END_CENTRAL_LOC_HDR_SIG ) {
        my $cd64 = U64::Value_VV64 substr($buffer,  8, 8);
       
        $self->smartSeek($cd64, 0, SEEK_SET) ;

        $self->smartReadExact(\$buffer, 4) 
            or die "xxx" ;

        if ( unpack("V", $buffer) == ZIP64_END_CENTRAL_REC_HDR_SIG ) {

            $self->smartReadExact(\$buffer, 8)
                or die "xxx" ;
            my $size  = U64::Value_VV64($buffer);
            $self->smartReadExact(\$buffer, $size)
                or die "xxx" ;

            my $cd64 =  U64::Value_VV64 substr($buffer,  36, 8);

            return $cd64 ;
        }
        
        die "zzz";
    }

    die "zzz";
}

use constant Pack_ZIP_END_CENTRAL_HDR_SIG => pack("V", ZIP_END_CENTRAL_HDR_SIG);

sub findCentralDirectoryOffset
{
    my $self = shift ;

    # Most common use-case is where there is no comment, so
    # know exactly where the end of central directory record
    # should be.

    $self->smartSeek(-22, 0, SEEK_END) ;
    my $here = $self->tell();

    my $buffer;
    $self->smartReadExact(\$buffer, 22) 
        or die "xxx" ;

    my $zip64 = 0;                             
    my $centralDirOffset ;
    if ( unpack("V", $buffer) == ZIP_END_CENTRAL_HDR_SIG ) {
        $centralDirOffset = unpack("V", substr($buffer, 16,  4));
    }
    else {
        $self->smartSeek(0, 0, SEEK_END) ;

        my $fileLen = $self->tell();
        my $want = 0 ;

        while(1) {
            $want += 1024;
            my $seekTo = $fileLen - $want;
            if ($seekTo < 0 ) {
                $seekTo = 0;
                $want = $fileLen ;
            }
            $self->smartSeek( $seekTo, 0, SEEK_SET) 
                or die "xxx $!" ;
            my $got;
            $self->smartReadExact($buffer, $want)
                or die "xxx " ;
            my $pos = rindex( $buffer, Pack_ZIP_END_CENTRAL_HDR_SIG);

            if ($pos >= 0) {
                #$here = $self->tell();
                $here = $seekTo + $pos ;
                $centralDirOffset = unpack("V", substr($buffer, $pos + 16,  4));
                last ;
            }

            return undef
                if $want == $fileLen;
        }
    }

    $centralDirOffset = $self->offsetFromZip64($here)
        if U64::full32 $centralDirOffset ;

    return $centralDirOffset ;
}

1;

__END__


