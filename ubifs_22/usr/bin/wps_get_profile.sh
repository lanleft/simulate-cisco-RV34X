#!/bin/sh

. /lib/functions.sh
scan_wifi() {
	local cfgfile="$1"
	DEVICES=
	wl0_VIFS=
	wl1_VIFS=
	config_cb() {
		local type="$1"
		local section="$2"
		# section start
		case "$type" in
			wifi-device)
				append DEVICES "$section"
				#config_set "$section" vifs ""
				config_set "$section" ht_capab ""
			;;
		esac
		# section end
		config_get TYPE "$CONFIG_SECTION" TYPE
		case "$TYPE" in
		wifi-iface)
			config_get device "$CONFIG_SECTION" device
			eval append ${device}_VIFS "$CONFIG_SECTION"
			eval vifs="\${${device}_VIFS}"
			config_set "$device" vifs "$vifs"
			;;
		esac
	}
	config_load "${cfgfile:-wireless}"
}

include /lib/wifi
scan_wifi

board="$(/usr/bin/board_check.sh)"
if [ "$board" = "RV340W" ];then
	RADIO1_NAME="wl0"
	RADIO2_NAME="wl1"
	while read line;do
		_ssid="$(echo $line | cut -d' ' -f 1)"
		_radio="$(echo $line | cut -d' ' -f 2)"

		if [ "$_radio" = "BOTH" ];then
			config_get vifs1 $RADIO1_NAME vifs
			for vif in $vifs1; do
				config_get ssid1 "$vif" ssid
				if [ "$ssid1" = "$_ssid" ];then
					config_get ifname1 "$vif" ifname
					WLAN1_NAME="$ifname1"
					break
				fi
			done

			config_get vifs2 $RADIO2_NAME vifs
			for vif in $vifs2; do
				config_get ssid2 "$vif" ssid
				if [ "$ssid2" = "$_ssid" ];then
					config_get ifname2 "$vif" ifname
					WLAN2_NAME="$ifname2"
					break
				fi
			done
			[ -n "$WLAN1_NAME" -a -n "$WLAN2_NAME" ] && {
				wps_cli wps_both_ssid $WLAN1_NAME $WLAN2_NAME
				wps_cli wps_both_ssid $WLAN2_NAME $WLAN1_NAME
			}
		else
			if [ "$_radio" = "WLAN1" ];then
				config_get vifs1 $RADIO1_NAME vifs
				for vif in $vifs1; do
					config_get ssid1 "$vif" ssid
					if [ "$ssid1" = "$_ssid" ];then
						config_get ifname1 "$vif" ifname
						WLAN1_NAME="$ifname1"
						break
					fi
				done
				[ -n "$WLAN1_NAME" ] && wps_cli wps_both_ssid $WLAN1_NAME ""
			else
				config_get vifs2 $RADIO2_NAME vifs
				for vif in $vifs2; do
					config_get ssid2 "$vif" ssid
					if [ "$ssid2" = "$_ssid" ];then
						config_get ifname2 "$vif" ifname
						WLAN2_NAME="$ifname2"
						break
					fi
				done
				[ -n "$WLAN2_NAME" ] && wps_cli wps_both_ssid $WLAN2_NAME ""
			fi
		fi
	done < /tmp/wifi_status_result
else
	if [ "$board" = "RV160W" ];then
		RADIO0_NAME="wl1"
		RADIO1_NAME="wl0"
	else
		RADIO0_NAME="wl0"
		RADIO1_NAME="wl1"
	fi
	while read line;do
		_ssid="$(echo $line | awk '{$NF=""}1' | awk '{$NF=""}1' | sed 's/.\{1\}$//')"
		_radio="$(echo $line | awk '{print $(NF-1)}')"

		if [ "$_radio" = "BOTH" ];then
			config_get vifs0 $RADIO0_NAME vifs
			for vif in $vifs0; do
				config_get ssid0 "$vif" ssid
				if [ "$ssid0" = "$_ssid" ];then
					config_get ifname0 "$vif" ifname
					WLAN0_NAME="$ifname0"
					break
				fi
			done

			config_get vifs1 $RADIO1_NAME vifs
			for vif in $vifs1; do
				config_get ssid1 "$vif" ssid
				if [ "$ssid1" = "$_ssid" ];then
					config_get ifname1 "$vif" ifname
					WLAN1_NAME="$ifname1"
					break
				fi
			done
			[ -n "$WLAN0_NAME" -a -n "$WLAN1_NAME" ] && {
				wps_cli wps_both_ssid $WLAN0_NAME $WLAN1_NAME
				wps_cli wps_both_ssid $WLAN1_NAME $WLAN0_NAME
			}
		else
			if [ "$_radio" = "WLAN0" ];then
				config_get vifs0 $RADIO0_NAME vifs
				for vif in $vifs0; do
					config_get ssid0 "$vif" ssid
					if [ "$ssid0" = "$_ssid" ];then
						config_get ifname0 "$vif" ifname
						WLAN0_NAME="$ifname0"
						break
					fi
				done
				[ -n "$WLAN0_NAME" ] && wps_cli wps_both_ssid $WLAN0_NAME ""
			else
				config_get vifs1 $RADIO1_NAME vifs
				for vif in $vifs1; do
					config_get ssid1 "$vif" ssid
					if [ "$ssid1" = "$_ssid" ];then
						config_get ifname1 "$vif" ifname
						WLAN1_NAME="$ifname1"
						break
					fi
				done
				[ -n "$WLAN1_NAME" ] && wps_cli wps_both_ssid $WLAN1_NAME ""
			fi
		fi
	done < /tmp/wifi_status_result
fi