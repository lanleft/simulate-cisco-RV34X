

package Config;
use strict;
use warnings;
use vars '%Config', '$VERSION';

$VERSION = "5.022000";

my %Export_Cache = (myconfig => 1, config_sh => 1, config_vars => 1,
		    config_re => 1, compile_date => 1, local_patches => 1,
		    bincompat_options => 1, non_bincompat_options => 1,
		    header_files => 1);

@Config::EXPORT = qw(%Config);
@Config::EXPORT_OK = keys %Export_Cache;


sub bincompat_options;
sub compile_date;
sub config_re;
sub config_sh;
sub config_vars;
sub header_files;
sub local_patches;
sub myconfig;
sub non_bincompat_options;

sub import {
    shift;
    @_ = @Config::EXPORT unless @_;

    my @funcs = grep $_ ne '%Config', @_;
    my $export_Config = @funcs < @_ ? 1 : 0;

    no strict 'refs';
    my $callpkg = caller(0);
    foreach my $func (@funcs) {
	die qq{"$func" is not exported by the Config module\n}
	    unless $Export_Cache{$func};
	*{$callpkg.'::'.$func} = \&{$func};
    }

    *{"$callpkg\::Config"} = \%Config if $export_Config;
    return;
}

die "$0: Perl lib version (5.22.0) doesn't match executable '$^X' version ($])"
    unless $^V;

$^V eq 5.22.0
    or die sprintf "%s: Perl lib version (5.22.0) doesn't match executable '$^X' version (%vd)", $0, $^V;


sub FETCH {
    my($self, $key) = @_;

    # check for cached value (which may be undef so we use exists not defined)
    return exists $self->{$key} ? $self->{$key} : $self->fetch_string($key);
}

sub TIEHASH {
    bless $_[1], $_[0];
}

sub DESTROY { }

sub AUTOLOAD {
    require 'Config_heavy.pl';
    goto \&launcher unless $Config::AUTOLOAD =~ /launcher$/;
    die "&Config::AUTOLOAD failed on $Config::AUTOLOAD";
}

tie %Config, 'Config', {
    archlibexp => '/usr/lib/perl5/5.22',
    archname => 'arm-linux-uclibc',
    cc => 'arm-openwrt-linux-gnueabi-gcc',
    d_readlink => 'define',
    d_symlink => 'define',
    dlext => 'so',
    dlsrc => 'dl_dlopen.xs',
    dont_use_nlink => undef,
    exe_ext => '',
    inc_version_list => ' ',
    intsize => '4',
    ldlibpthname => 'LD_LIBRARY_PATH',
    libpth => '/opt/samba/vbuild/builds/workspace/CISCO/CISCO_SBR_RV34X/Build/CISCO_SBR_RV34X/pp_sdk-openwrt/staging_dir/target-arm_cortex-a9_glibc-2.19_eabi/lib /opt/samba/vbuild/builds/workspace/CISCO/CISCO_SBR_RV34X/Build/CISCO_SBR_RV34X/pp_sdk-openwrt/staging_dir/target-arm_cortex-a9_glibc-2.19_eabi/usr/lib',
    osname => 'linux',
    osvers => '2.6.22',
    path_sep => ':',
    privlibexp => '/usr/lib/perl5/5.22',
    scriptdir => '/usr/bin',
    sitearchexp => '',
    sitelibexp => '',
    so => 'so',
    useithreads => 'define',
    usevendorprefix => undef,
    version => '5.22.0',
};
