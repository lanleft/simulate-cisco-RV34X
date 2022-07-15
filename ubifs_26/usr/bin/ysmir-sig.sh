#!/bin/sh
#
. /etc/boardInfo

f1=$1

if [ "$(lsmod | grep lionic_dpi | wc -l)" == "0" ]
then
	exit
fi

if [ ! -e "/dev/se_ctrl" ] || [ ! -e "/dev/se_data" ]
then
	exit
fi

dir=$AvcSignPartitionPath

mem_flush()
{
	mem=$(cat /proc/meminfo | grep MemFree | tr -s ' ' | cut -d ' ' -f2)
	if [ "$mem" -le 102400 ]; then
		sync && echo 3 > /proc/sys/vm/drop_caches
	fi
}

load_sig()
{
	sig_list=$1
	cd $dir

	for i in $sig_list
	do
		if [ -f $i ]; then
			if [ -f "$i.md5" ]; then
				verify=`md5sum -c $i.md5 | cut -d" " -f2`
				if [ "$verify" == "OK" ]; then
					lcsh load $i
				else
					echo Error for checking signature: $i
				fi
			else
				lcsh load $i
			fi

			mem_flush
		fi
	done
}

lcsh sys sig invalid

for i in `seq 1 5`
do
	if [ "$(lcsh show number pkt | tr -d '\n')" == "0" ]
	then
		break
	fi
	sleep 1
done

gunzip -c $dir/application.gz > /tmp/etc/config/application
gunzip -c $dir/device.gz  > /tmp/etc/config/device
gunzip -c $dir/ipsrule.gz > /tmp/etc/config/ipsrule

load_sig "mpp.zip dm.zip avc.zip ips.zip av.zip"

lcsh load $dir/dm_spec.zip
lcsh load $dir/dm_oui.zip
lcsh load $dir/avc_spec.zip
lcsh load $dir/ips_spec.zip

mem_flush

if [ "$f1" == "init" ];then
echo "[Ysmir] restore device info" > /dev/console
lcsh uci dm restore
fi

SWUPDATE_FILE="/mnt/configcert/config/swupdateinfo"
update_siginfo()
{
	current_sig_version=`lcsh show info | grep "APG Sig Version" | cut -d' ' -f5`
	sig_update_time=`date`

	sed -i "/^sig_latest_version=/c\sig_latest_version=\"$current_sig_version\"" $SWUPDATE_FILE
	sed -i "/^sig_latest_update_time=/c\sig_latest_update_time=\"$sig_update_time\"" $SWUPDATE_FILE

	if [ "$IS_MR1" = "1" ]; then
		cur_sec_sig_ver=`cat /mnt/avcsign/bundle.txt`;
		sed -i "/^sec_latest_version=/c\sec_latest_version=\"$cur_sec_sig_ver\"" $SWUPDATE_FILE
		## Irrespective of MR0.5 or MR1, use the same sig_latest_update_time. But for MR1, use sec_latest_version additionally(bundle version)
	fi
}

update_siginfo


echo "[Ysmir] load configuration" > /dev/console
ysmir-config.sh

lcsh sys sig valid

