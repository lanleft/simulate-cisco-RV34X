#!/bin/sh

max_cnts=5
cnt=0

while [ $cnt -le $max_cnts ]; do
	result="$(nvram get wps_wait_monitor)"
	result_force="$(nvram get wps_monitor_force)"
	if [ "$result" = "1" -o "$result_force" = "1" ];then
		killall -15 wps_monitor
		sleep 1
		start-stop-daemon -S -b -x wps_monitor
		_c=0
		while [ $_c -lt 3 ];do
			sleep 1
			[ -n "$(pgrep wps_monitor)" ] && break
			_c=$(( $_c + 1 ))
			start-stop-daemon -S -b -x wps_monitor
		done

		nvram set wps_monitor_force=0
		nvram set wps_wait_monitor=0

		exit
	fi
	sleep 1
	cnt=$(( $cnt + 1 ))
done
