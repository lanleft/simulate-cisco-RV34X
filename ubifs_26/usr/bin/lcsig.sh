#!/bin/sh

. /etc/boardInfo

download_dir=/tmp/avcsign
target_dir=$AvcSignPartitionPath
sig_name=$1

#sig_name=`basename $1`
ASDSTATUS="/tmp/asdclientstatus"

mkdir -p $download_dir
#Copying the downloaded signature file to the below path to continue further.
#cp -f $1 $download_dir/

check_sig()
{
	sig_list=$1
	cd $download_dir

	for i in $sig_list
	do
		if [ -f $i ]; then
			if [ -f "$i.md5" ]; then
				verify=`md5sum -c $i.md5 | cut -d" " -f2`
				if [ "$verify" != "OK" ]; then
					echo "[INFO] signature checking error: $i" > /dev/kmsg
					exit
				fi
			fi
		fi
	done
}

#mkdir -p $download_dir
#rm -f $download_dir/*

cd $download_dir
gzip < /etc/config/application > application.gz
gzip < /etc/config/device      > device.gz
gzip < /etc/config/ipsrule     > ipsrule.gz

cd $download_dir && unzip -o $sig_name || {
	echo "[INFO] signature upload error (zip corrupted): $sig_name" > /dev/kmsg
	errcode=1
	echo $errcode > $ASDSTATUS
	rm -rf $download_dir
	exit $errcode
}

if [ ! -f $download_dir/bundle.txt  ]; then
	echo "[INFO] signature upload error (not correct vesion): $sig_name" > /dev/kmsg
	errcode=2
	echo $errcode > $ASDSTATUS
	rm -rf $download_dir
	exit $errcode
fi

check_sig "mpp.zip dm.zip avc.zip ips.zip av.zip"

cd $target_dir &&
find . -type f ! -name "*.zip" ! -name "*.md5" ! -name "*.gz" | xargs rm -rf

cd $download_dir                                                &&
rm -f crf*                                                      &&
gunzip -c application.gz > /tmp/etc/config/application          &&
gunzip -c device.gz  > /tmp/etc/config/device                   &&
gunzip -c ipsrule.gz > /tmp/etc/config/ipsrule                  &&
mv -f *.gz       $target_dir/                                   &&
mv -f *.zip      $target_dir/                                   &&
mv -f *.zip.md5  $target_dir/                                   &&
mv -f *.txt      $target_dir/                                   &&
echo "[INFO] signature upload success: $sig_name" > /dev/kmsg   ||
echo "[INFO] signature upload error: $sig_name" > /dev/kmsg

# Recording Signature update time
SWUPDATE_FILE="/mnt/configcert/config/swupdateinfo"
sig_update_time=`date`
sed -i "/^sig_latest_update_time=/c\sig_latest_update_time=\"$sig_update_time\"" $SWUPDATE_FILE

ysmir-sig.sh

errcode=$?
echo "[INFO] signature version updated to `lcsh bundle show`" > /dev/kmsg
log=`lcsh show info | grep 'Sig Version' | grep -v 'DM\|MPP' | awk '{print tolower($1) "=" $5 }'  | xargs`;
echo "[INFO] using detailed signature versions for: $log" > /dev/kmsg

echo $errcode > $ASDSTATUS
rm -rf $download_dir

