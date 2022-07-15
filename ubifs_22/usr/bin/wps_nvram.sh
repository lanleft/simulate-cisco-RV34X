#!/bin/sh

board=`uci get systeminfo.sysinfo.pid | cut -d'-' -f1`
if [ "$board" != "RV340W" -a "$board" != "RV160W" -a "$board" != "RV260W" ] ;then
	return 0
fi

if [ "$1" = "save" ];then
	[ ! -d /mnt/configcert/nvram ] && mkdir -p /mnt/configcert/nvram
	cp /tmp/etc/config/wificonfig /mnt/configcert/nvram/
elif [ "$1" = "remove" ];then
	rm /mnt/configcert/nvram/wificonfig
fi
