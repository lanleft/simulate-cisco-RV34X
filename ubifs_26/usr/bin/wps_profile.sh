#!/bin/sh

IFNAME="$1"
both_flag="$2"
orig_ssid="$3"

board="$(/usr/bin/board_check.sh)"

if [ -n "$(echo $IFNAME | grep wl0)" ];then
	if [ "$board" = "RV160W" -o "$board" = "RV340W" ];then
		radio="WLAN1"
	else
		radio="WLAN0"
	fi
	if [ "$orig_ssid" = "ciscosb" ];then
		nvram set wl0_${orig_ssid}_configured=1
		[ "$both_flag" = "1" ] && nvram set wl1_${orig_ssid}_configured=1
	fi
elif [ -n "$(echo $IFNAME | grep wl1)" ];then
	if [ "$board" = "RV160W" ];then
		radio="WLAN0"
	elif [ "$board" = "RV340W" ];then
		radio="WLAN2"
	else
		radio="WLAN1"
	fi
	if [ "$orig_ssid" = "ciscosb" ];then
		nvram set wl1_${orig_ssid}_configured=1
		[ "$both_flag" = "1" ] && nvram set wl0_${orig_ssid}_configured=1
	fi
else
	exit
fi

if [ "$both_flag" = "1" ];then
	radio="BOTH"
fi

orig_ssid="$3"
new_ssid="$4"
case "$5" in
	1) security="WPA-Personal"
	;;
	2) security="WPA2-Personal"
	;;
	3) security="WPA-WPA2-Personal"
	;;
	*) security="None"
	;;
esac

passphrase="$6"

nvram set wps_reload_lock=1
/usr/bin/update_ssid_profile.sh "$orig_ssid" "$new_ssid" $radio $security "$passphrase"

if [ "$?" = "0" ];then
	nvram set wps_ssid_update=1
	nvram set wps_wait_monitor=1
	nvram set wps_reload_lock=0

	cp /tmp/etc/config/wireless /tmp/etc/config/wireless_old >/dev/null 2>&1

	echo "show wlans" > /tmp/get_wifi_status
	confd_cli -u admin -N /tmp/get_wifi_status | sed -e {1,3d} | sed '$ d' > /tmp/wifi_status_result
	sed -i 's/\\/\\\\/g' /tmp/wifi_status_result
fi
