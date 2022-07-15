#!/bin/sh
#

if [ "$(lsmod | grep lionic_dpi | wc -l)" == "0" ]
then
	exit
fi

if [ ! -e "/dev/se_ctrl" ] || [ ! -e "/dev/se_data" ]
then
	exit
fi

log()
{
	lcsh log all all off
	lcsh log all error on

	module=$1
	for m in $module
	do
		LEVEL=`uci get $m.$m.log_level`

		if [ $LEVEL == "" ]
		then
			LEVEL=6
		fi
		if [ $LEVEL -gt 7 ]
		then
			LEVEL=7
		fi

		if [ "$m" == "avc" ]; then
			m="apg"
		fi

		case "$LEVEL" in
		7)
			lcsh log $m debug on
			lcsh log $m info on
			lcsh log $m notice on
			lcsh log $m warn on
			lcsh log $m error on
			;;
		6)
			lcsh log $m info on
			lcsh log $m notice on
			lcsh log $m warn on
			lcsh log $m error on
			;;
		5)
			lcsh log $m notice on
			lcsh log $m warn on
			lcsh log $m error on
			;;
		4)
			lcsh log $m warn on
			lcsh log $m error on
			;;
		3)
			lcsh log $m error on
			;;
		*)
			;;
		esac
	done
}

system()
{
	#lcsh iface wan set eth0
	#lcsh iface wan set eth2

	killall decomp_server
	decomp_server &

	killall casa
	casa &

	lcsh sys http keep off
	lcsh sys http encoding off
	lcsh sys http cache on

	lcsh decomp bz2 on
	lcsh decomp rar on
	lcsh decomp bomb on
	lcsh decomp on
	lcsh av cloud on

	#lcsh ips psd watch add eth0
	#lcsh ips psd watch add eth1
	lcsh ips psd on

	lcsh ips pa on

	# Enabling log setting per module
	lcsh sys log on
	lcsh apg log on
	lcsh ips log on
	lcsh av log on
}

dm()
{
	# Device Map function
	lcsh dm on
}

ips()
{
	killall -q -9 lcips
	lcips >/dev/null 2>&1
}

av()
{
	killall -q -9 lcav
	lcav >/dev/null 2>&1
}

apg()
{
	killall -q -9 lcavc
	lcavc >/dev/null 2>&1 &
}

stat()
{
	killall -q -9 lcstat
	lcstat daemon >/dev/null 2>&1 &
}

module=$1
if [ $# -eq 0 ];then
	log "avc ips av"
	system
	dm
	ips
	av
	apg
	stat
else
	eval $module;
fi

