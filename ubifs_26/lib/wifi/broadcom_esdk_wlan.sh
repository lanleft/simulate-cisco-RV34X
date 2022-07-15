append DRIVERS "broadcom"

per_ssid_prepare() {
	local device="$1"
	local _vif
	local _vifs
	local enc sec_mode
	local per_cmd= per_ssid= per_ssid= per_ssid_old=

	config_get _vifs "$device" vifs

	wifi_check ssid $device > /tmp/per_ssid_status
	sed -i 's/\\/\\\\/g' /tmp/per_ssid_status

	include /lib/network

	while read line; do
		set $line
		per_cmd="$1"
		per_idx="$2"
		read _line_ssid
		per_ssid="$_line_ssid"

		case "$per_cmd"  in
		"init"|"add"|"update"|"rename")
			for _vif in $_vifs; do
				config_get _ssid "$_vif" ssid
				if [ "$_ssid" = "$per_ssid" ];then
					_idx=".$per_idx"
					[ "$per_idx" = "0" ] && _idx=
					ifname="${device}${_idx}"
					config_set "$_vif" ifname "${device}${_idx}"
					set_wifi_ifname "$_vif" "${device}${_idx}"

					config_get enc "$_vif" encryption
					case "$enc" in
					*psk*)
						case "$enc" in
						*mixed*|*psk+psk2*) sec_mode="WPA-WPA2-Personal";;
						*psk2*) sec_mode="WPA2-Personal";;
						*) sec_mode="WPA-Personal";;
						esac
					;;
					*wpa*)
						case "$enc" in
						*mixed*|*wpa+wpa2*) sec_mode="WPA-WPA2-Enterprise";;
						*wpa2*) sec_mode="WPA2-Enterprise";;
						*) sec_mode="WPA-Enterprise";;
						esac
					;;
					*wep*) sec_mode="WEP";;
					*) sec_mode="None";;
					esac

					case "$per_cmd" in
					"add")
						logger -t wireless "New $THIS_RADIO SSID $per_ssid enabled, Security $sec_mode"
					;;
					"update")
						logger -t wireless "Update $THIS_RADIO SSID $per_ssid, Security $sec_mode"
					;;
					"rename")
						per_ssid_old="$(nvram get ${ifname}_ssid)"
						logger -t wireless "Rename $THIS_RADIO SSID from $per_ssid_old to $per_ssid, Security $sec_mode"
					;;
					esac

					break
				fi
			done
		;;
		esac
	done < /tmp/per_ssid_status

}

per_ssid_update() {
	local device="$1"
	local _vif
	local THIS_RADIO="2.4G"
	local wps mac_filter macpolicy disabled ssid
	local wmm maxassoc vlanid hidden isolate captive
	local enc pmf schedule wmm_disable maclist
	local captiveopts=0
	local wpsopts=
	local schedule_opts=
	local schedule_result="up"
	local all_ssid_disabled=1
	local acsdopts=
	local per_cmd= per_ssid= per_ssid= per_ssid_old=

	[ "$device" = "wl1" ] && THIS_RADIO="5G"

	# In case of there is no ssid enabled before
	_z1="$(nvram get ${device}_hwaddr)"
	_z2="$(uci show wireless | grep device=${device})"
	[ -z "$_z1" -a -z "$_z2" ] && return
	config_get _vifs "$device" vifs

	_x="$(wifi_check radio $device)"
	[ -n "$_x" ] && {
		set $_x
		config_get_bool disabled "$device" disabled 0
		# Update ifname

		disable_broadcom "$device"

		if [ "$disabled" = "0" ];then
			nvram set ${device}_radio=1
			scan_broadcom "$device"
			per_ssid_prepare "$device"
			enable_broadcom "$device"
		fi

		return
	}

	_y="$(nvram get ${device}_radio)"
	[ -z "$_y" ] && {
		config_get_bool disabled "$device" disabled 0

		if [ "$disabled" = "0" ];then
			nvram set ${device}_radio=1
			scan_broadcom "$device"
			per_ssid_prepare "$device"
			while read line; do
				set $line
				per_cmd="$1"
				per_idx="$2"
				read _line_ssid
				case "$per_cmd"  in
				"del")
					_idx=".$per_idx"
					[ "$per_idx" = "0" ] && _idx=
					ifname="${device}${_idx}"
					nvram set ${ifname}_ssid
				;;
				esac
			done < /tmp/per_ssid_status
			enable_broadcom "$device"
		fi

		return
	}

	# Check ssid if no radio changes

	[ -e /var/run/wlan_${device}_eapd.post ] && rm /var/run/wlan_${device}_eapd.post
	[ -e /var/run/wlan_${device}_nas.post ] && rm /var/run/wlan_${device}_nas.post
	[ -e /var/run/wlan_${device}_wps.post ] && rm /var/run/wlan_${device}_wps.post
	[ -e /var/run/wlan_${device}_acsd.post ] && {
		rm /var/run/wlan_${device}_acsd.post
		_acs_ifname_exist="$(nvram get acs_ifnames)"
		_acs_ifname_new=
		for _acs in $_acs_ifname_exist; do
			[ "$_acs" = "$device" ] || {
				_acs_ifname_new="${_acs_ifname_new:+$_acs_ifname_new }$_acs"
			}
		done
		nvram set acs_ifnames="$_acs_ifname_new"
	}

	[ -e /var/run/wlan_${device}_cron.post ] && rm /var/run/wlan_${device}_cron.post
	[ -e /var/run/wlan_${device}_cp.post ] && rm /var/run/wlan_${device}_cp.post

	cd /sys/class/net
	include /lib/network

	per_ssid_prepare "$device"
	pre_broadcom "$device"
	ubus call network reload

	config_get_bool disabled "$device" disabled 0
	[ "$disabled" = "1" ] && return
	nvram set ${device}_radio=1

	while read line; do
		set $line
		per_cmd="$1"
		per_idx="$2"
		read _line_ssid
		per_ssid="$_line_ssid"

		case "$per_cmd"  in
		"init"|"add"|"update"|"rename")
			for _vif in $_vifs; do
				config_get _ssid "$_vif" ssid
				if [ "$_ssid" = "$per_ssid" ];then
					config_get ifname "$_vif" ifname

					[ "$per_cmd" = "init" ] && break

					wl -i "$ifname" bss 0
					wl -i "$ifname" ssid -C $per_idx "$_ssid"
					nvram set ${ifname}_ssid="${_ssid}"

					# disable this interface first
					cur_vlanid="$(nvram get ${ifname}_vlanid)"
					[ ! -e $ifname ] || {
						wl -i "$ifname" mac none >/dev/null
						/usr/bin/wifi_schedule clear $ifname
						unbridge "$ifname"
						bridge_name="$(nvram get ${ifname}_bridge)"
						[ -n "$bridge_name" -a -e /sys/class/net/${bridge_name}/brif/$ifname ] && {
							brctl delif ${bridge_name} $ifname
						}
					}

					config_get_bool disabled "$_vif" disabled 0
					[ "$disabled" = "1" ] && {
						nvram set ${ifname}_bss_enabled
						break
					}

					if [ "$per_cmd" = "add" ];then
						if [ "$device" = "wl0" ];then
							echo 1 > /sys/devices/platform/pfe.0/$ifname/rx_cpu_affinity
						else
							echo 0 > /sys/devices/platform/pfe.0/$ifname/rx_cpu_affinity
						fi
					fi

					schedule_result="up"
					config_get schedule "$_vif" schedule
					[ -z "$schedule" -o "$schedule" = "always" ] || {
						schedule_opts="1"
						/usr/bin/wifi_schedule set $ifname $schedule
						[ -e /var/run/wlan_${device}_cron.post ] || touch /var/run/wlan_${device}_cron.post

						[ "x$(/usr/bin/wifi_schedule_check $schedule 2>/dev/null)" = "x0" ] && {
							schedule_result="down"
						}
					}

					nvram set ${ifname}_bss_enabled=1
					nvram set ${ifname}_mode=ap

					config_get vlanid "$_vif" vlanid
					nvram set ${ifname}_vlanid=${vlanid}

					local net_cfg=""
					net_cfg="$(find_net_config "$_vif")"
					[ -z "$net_cfg" ] || {
						bridge="br-${net_cfg}"

						local lan_idx=0
						while [ $lan_idx -lt 8 ]; do
							local lan_idx_fixed=""
							[ $lan_idx -gt 0 ] && lan_idx_fixed=${lan_idx}

							lan_value="$(nvram get lan${lan_idx_fixed}_vlanid)"

							if [ -n "$lan_value" ]; then
								[ ${vlanid} -eq $lan_value ] && {
									nvram set lan${lan_idx_fixed}_ifname="$bridge"
									nvram set ${ifname}_bridge="$bridge"
									break;
								}
							else
								nvram set lan${lan_idx_fixed}_vlanid=${vlanid}
								nvram set lan${lan_idx_fixed}_ifname="$bridge"
								nvram set ${ifname}_bridge="$bridge"
								break
							fi
							lan_idx=$(($lan_idx + 1))
						done

						brctl addif $bridge $ifname
						set_wifi_up "$_vif" "$ifname"
					}

					local wsec_r=1
					local eap_r=0
					local wsec=0
					local auth=0
					local nasopts=
					local eapdopts=
					local enc key rekey

					nvram set ${ifname}_auth_mode

					wl -i $ifname auth 0
					wl -i $ifname eap $eap_r
					wl -i $ifname wsec $wsec
					wl -i $ifname wsec_restrict $wsec_r
					wl -i $ifname wpa_auth $auth
					wl -i $ifname mfp_config 0

					config_get wps "$_vif" wps

					nvram set ${ifname}_radio=1

					config_get pmf "$_vif" pmf 1
					config_get enc "$_vif" encryption
					case "$enc" in
					*wep*)
						nvram set ${ifname}_wps_mode="disabled"
						nvram set ${ifname}_wfi_enable
						local def defkey k knr
						wsec_r=1
						wsec=1
						defkey=1

						nvram set ${ifname}_wpa_psk
						nvram set ${ifname}_akm
						nvram set ${ifname}_crypto
						nvram set ${ifname}_auth
						nvram set ${ifname}_wep

						# Disable WPA first
						wl -i $ifname wpa_auth 0

						wl -i $ifname eap $eap_r
						wl -i $ifname wsec $wsec
						wl -i $ifname wsec_restrict $wsec_r

						config_get key "$_vif" key
						case "$enc" in
						*shared*) wl -i $ifname auth 1;;
						*) wl -i $ifname auth 0;;
						esac
						case "$key" in
						[1234])
							defkey="$key"
							local key_index=0
							for knr in 1 2 3 4; do
								config_get k "$_vif" key$knr
								[ -n "$k" ] || continue
								wl -i $ifname addwep $key_index ${k:2}
							done
						;;
						"");;
						*) wl -i $ifname addwep 0 $key;;
						esac
					;;
					*psk*)
						wsec_r=1
						config_get key "$_vif" key

						nvram set ${ifname}_wpa_gtk_rekey=3600
						nvram set ${ifname}_preauth=1

						# psk version + default cipher
						case "$enc" in
						*mixed*|*psk+psk2*) auth=132; wsec=6; nvram set ${ifname}_akm="psk psk2";
							wl -i $ifname mfp_config $pmf
						;;
						*psk2*) auth=128; wsec=4;nvram set ${ifname}_akm=psk2;
							wl -i $ifname mfp_config $pmf
						;;
						*) auth=4;
							if [ "$band" = "a" ];then
								wsec=4;
							else
								wsec=2;
							fi
							wps=0;
							nvram set ${ifname}_akm=psk;;
						esac

						# cipher override
						case "$enc" in
						*tkip+aes*|*tkip+ccmp*|*aes+tkip*|*ccmp+tkip*) wsec=6;;
						*aes*|*ccmp*) wsec=4;;
						*tkip*) wsec=2;;
						esac

						[ "$wsec" = "6" ] && nvram set ${ifname}_crypto="tkip+aes"
						[ "$wsec" = "4" ] && nvram set ${ifname}_crypto="aes"
						[ "$wsec" = "2" ] && nvram set ${ifname}_crypto="tkip"

						wl -i $ifname auth 0
						wl -i $ifname eap $eap_r
						wl -i $ifname wsec $wsec
						wl -i $ifname wsec_restrict $wsec_r
						wl -i $ifname wpa_auth $auth

						nvram set ${ifname}_wpa_psk="${key}"
						nvram set ${ifname}_auth=0

						nvram set ${ifname}_wep=disabled

						if [ "$wps" = "1" -a "$hidden" != "1" ]; then
							nvram set ${ifname}_wps_mode="enabled"
							nvram set ${ifname}_wfi_enable=1

							wpsopts=1
							[ -e /var/run/wlan_${device}_wps.post ] || touch /var/run/wlan_${device}_wps.post
						else
							nvram set ${ifname}_wps_mode="disabled"
							nvram set ${ifname}_wfi_enable
						fi
						[ -e /var/run/wlan_${device}_eapd.post ] || touch /var/run/wlan_${device}_eapd.post
						[ -e /var/run/wlan_${device}_nas.post ] || touch /var/run/wlan_${device}_nas.post
					;;
					*wpa*)
						nvram set ${ifname}_wpa_gtk_rekey=3600
						nvram set ${ifname}_net_reauth=36000
						nvram set ${ifname}_preauth=1
						nvram set ${ifname}_wep=disabled
						nvram set ${ifname}_auth=0

						nvram set ${ifname}_wps_mode="disabled"
						nvram set ${ifname}_wfi_enable
						local Radius_port Radius_secret Radius_server
						wsec_r=1
						eap_r=1
						config_get Radius_server "$_vif" Radius_server
						[ -z "$Radius_server" ] && config_get Radius_server "$_vif" server
						config_get Radius_port "$_vif" Radius_port
						[ -z "$Radius_port" ] && config_get Radius_port "$_vif" port
						config_get Radius_secret "$_vif" Radius_secret
						[ -z "$Radius_secret" ] && config_get Radius_secret "$_vif" key

						# wpa version + default cipher
						case "$enc" in
						*mixed*|*wpa+wpa2*) auth=66; wsec=6;nvram set ${ifname}_akm="wpa wpa2";
							wl -i $ifname mfp_config $pmf
						;;
						*wpa2*) auth=64; wsec=4;nvram set ${ifname}_akm=wpa2;
							wl -i $ifname mfp_config $pmf
						;;
						*) auth=2;
							if [ "$band" = "a" ];then
								wsec=4;
							else
								wsec=2;
							fi
							nvram set ${ifname}_akm=wpa;;
						esac

						# cipher override
						case "$enc" in
						*tkip+aes*|*tkip+ccmp*|*aes+tkip*|*ccmp+tkip*) wsec=6;;
						*aes*|*ccmp*) wsec=4;;
						*tkip*) wsec=2;;
						esac

						[ "$wsec" = "6" ] && nvram set ${ifname}_crypto="tkip+aes"
						[ "$wsec" = "4" ] && nvram set ${ifname}_crypto="aes"
						[ "$wsec" = "2" ] && nvram set ${ifname}_crypto="tkip"

						nvram set ${ifname}_auth_mode="radius"

						wl -i $ifname auth 0
						wl -i $ifname eap $eap_r
						wl -i $ifname wsec $wsec
						wl -i $ifname wsec_restrict $wsec_r
						wl -i $ifname wpa_auth $auth

						# group rekey interval
						config_get rekey "$_vif" wpa_group_rekey

						eval "${_vif}_key=\"\$Radius_secret\""

						nvram set ${ifname}_radius_key="$Radius_secret"
						nvram set ${ifname}_radius_ipaddr="$Radius_server"
						nvram set ${ifname}_radius_port="${Radius_port:-1812}"

						[ -e /var/run/wlan_${device}_eapd.post ] || touch /var/run/wlan_${device}_eapd.post
						[ -e /var/run/wlan_${device}_nas.post ] || touch /var/run/wlan_${device}_nas.post
					;;
					*)
						if [ "$wps" = "1" -a "$hidden" != "1" ];then
							nvram set ${ifname}_wps_mode="enabled"
							nvram set ${ifname}_wfi_enable=1
							nvram set ${ifname}_auth=0
							nvram set ${ifname}_wep=disabled
							nvram set ${ifname}_akm
							nvram set ${ifname}_wpa_psk
							nvram set ${ifname}_crypto

							wpsopts=1
							[ -e /var/run/wlan_${device}_eapd.post ] || touch /var/run/wlan_${device}_eapd.post
							[ -e /var/run/wlan_${device}_nas.post ] || touch /var/run/wlan_${device}_nas.post
							[ -e /var/run/wlan_${device}_wps.post ] || touch /var/run/wlan_${device}_wps.post
							wl -i $ifname mfp_config $pmf
						else
							nvram set ${ifname}_wps_mode="disabled"
							nvram set ${ifname}_wfi_enable
						fi
					;;
					esac

					nvram set ${ifname}_wps_oob="disabled"

					config_get mac_filter "$_vif" mac_filter
					maclist=
					if [ "$mac_filter" = "1" ]; then
						config_get macpolicy "$_vif" macpolicy
						config_get maclist "$_vif" maclist
						case "$macpolicy" in
						allow|2) macpolicy=2;;
						deny|1) macpolicy=1;;
						disabled|none|0) macpolicy=0;;
						esac
					else
						macpolicy=0
					fi
					wl -i "$ifname" macmode $macpolicy
					[ -n "$maclist" ] && wl -i "$ifname" mac $maclist

					config_get captive "$_vif" captive
					[ "$captive" = "1" ] && {
						captiveopts=1
						[ -e /var/run/wlan_${device}_cp.post ] || touch /var/run/wlan_${device}_cp.post
					}


					config_get isolate "$_vif" isolate
					wl -i "$ifname" ap_isolate $isolate

					config_get wmm "$_vif" wmm
					[ "$wmm" = "1" ] && wmm_disable=0 || wmm_disable=1
					wl -i "$ifname" wme_bss_disable $wmm_disable

					config_get hidden "$_vif" hidden
					wl -i "$ifname" closed $hidden

					[ "$(wl -i $device isup)" = "0" -a "$schedule_result" = "up" ] && wl -i $device up

					wl -i "$ifname" bss $schedule_result
					nvram set ${ifname}_bss_enabled=1

					ifconfig "$ifname" up

					all_ssid_disabled=0

					break
				fi
			done
		;;
		"del")
			_idx=".$per_idx"
			[ "$per_idx" = "0" ] && _idx=
			ifname="${device}${_idx}"
			cur_vlanid="$(nvram get ${ifname}_vlanid)"
			[ ! -e $ifname ] || {
				wl -i "$ifname" mac none >/dev/null
				wl -i "$ifname" bss 0
				/usr/bin/wifi_schedule clear $ifname
				unbridge "$ifname"
				bridge_name="$(nvram get ${ifname}_bridge)"
				[ -n "$bridge_name" -a -e /sys/class/net/${bridge_name}/brif/$ifname ] && {
					brctl delif ${bridge_name} $ifname
				}
				nvram set ${ifname}_ssid
			}
			logger -t wireless "$THIS_RADIO SSID $per_ssid disabled"
		;;
		esac
	done < /tmp/per_ssid_status

	# Check if all ssid be disabled, if yes, bring radio down

	[ "$all_ssid_disabled" = "1" ] && {
		for _vif in $_vifs; do
			config_get_bool disabled "$_vif" disabled 0
			[ "$disabled" = "0" ] || continue

			all_ssid_disabled=0
			break
		done
	}

	if [ "$all_ssid_disabled" = "0" ]; then
		for _vif in $_vifs; do
			config_get_bool disabled "$_vif" disabled 0
			[ "$disabled" = "0" ] || continue

			[ "$wpsopts" = "1" -a "$schedule_opts" = "1" -a "$captiveopts" = "1" -a "$acsdopts" = "1" ] && break

			[ "$wpsopts" = "1" ] || {
				config_get wps "$_vif" wps
				config_get hidden "$_vif" hidden
				config_get enc "$_vif" encryption
				case "$enc" in
				*wep*)
				;;
				*psk*)
					[ -e /var/run/wlan_${device}_nas.post ] || touch /var/run/wlan_${device}_nas.post
					[ -e /var/run/wlan_${device}_eapd.post ] || touch /var/run/wlan_${device}_eapd.post
					if [ "$wps" = "1" -a "$hidden" != "1" ]; then
						wpsopts=1
						[ -e /var/run/wlan_${device}_wps.post ] || touch /var/run/wlan_${device}_wps.post
					fi
				;;
				*wpa*)
					[ -e /var/run/wlan_${device}_nas.post ] || touch /var/run/wlan_${device}_nas.post
					[ -e /var/run/wlan_${device}_eapd.post ] || touch /var/run/wlan_${device}_eapd.post
				;;
				*)
					if [ "$wps" = "1" -a "$hidden" != "1" ]; then
						wpsopts=1
						[ -e /var/run/wlan_${device}_nas.post ] || touch /var/run/wlan_${device}_nas.post
						[ -e /var/run/wlan_${device}_wps.post ] || touch /var/run/wlan_${device}_wps.post
						[ -e /var/run/wlan_${device}_eapd.post ] || touch /var/run/wlan_${device}_eapd.post
					fi
				;;
				esac
			}

			[ "$schedule_opts" = "1" ] || {
				config_get schedule "$_vif" schedule
				[ -z "$schedule" -o "$schedule" = "always" ] || {
					schedule_opts=1
					[ -e /var/run/wlan_${device}_cron.post ] || touch /var/run/wlan_${device}_cron.post
				}
			}

			[ "$captiveopts" = "1" ] || {
				config_get captive "$_vif" captive
				[ "$captive" = "1" ] && {
					captiveopts=1
					[ -e /var/run/wlan_${device}_cp.post ] || touch /var/run/wlan_${device}_cp.post
				}
			}

			[ "$acsdopts" = "1" ] || {
				config_get channel "$device" channel
				[ "$channel" = "auto" -o "$channel" = "0" ] && {
					acsdopts=1
					[ -e /var/run/wlan_${device}_acsd.post ] || {
						touch /var/run/wlan_${device}_acsd.post
						_acs_ifname_exist="$(nvram get acs_ifnames)"
						nvram set acs_ifnames="${_acs_ifname_exist:+$_acs_ifname_exist }$device"
					}
				}
			}
		done
	else
		wl -i "$device" down
	fi
}

scan_broadcom() {
	local device="$1"
	local vif vifs wds
	local adhoc sta apmode mon disabled
	local adhoc_if sta_if ap_if mon_if

	lan_max_no_bridge=8
	config_get vifs "$device" vifs
	for vif in $vifs; do
		local mode
		config_get mode "$vif" mode
		case "$mode" in
			ap)
				apmode=1
				ap_if="${ap_if:+$ap_if }$vif"
			;;
			adhoc)
				adhoc=1
				adhoc_if="$vif"
			;;
			sta)
				sta=1
				sta_if="$vif"
			;;
			wds)
				local addr
				config_get addr "$vif" bssid
				[ -z "$addr" ] || {
					addr=$(echo "$addr" | tr 'A-F' 'a-f')
					append wds "$addr"
				}
			;;
			monitor)
				mon=1
				mon_if="$vif"
			;;
			*) echo "$device($vif): Invalid mode";;
		esac
	done
	#config_set "$device" wds "$wds"

	local _c=
	for vif in ${adhoc_if:-$sta_if $ap_if $mon_if}; do
		config_set "$vif" ifname "${device}${_c:+.$_c}"
		_c=$((${_c:-0} + 1))
	done
	config_set "$device" vifs "${adhoc_if:-$sta_if $ap_if $mon_if}"

	ap=1
	infra=1
	mssid=1

	apsta=0
	radio=1
	monitor=0
	case "$adhoc:$sta:$apmode:$mon" in
		1*)
			ap=0
			mssid=
			infra=0
		;;
		:1:1:)
			apsta=1
			wet=1
		;;
		:1::)
			wet=1
			ap=0
			mssid=
		;;
		:::1)
			wet=1
			ap=0
			mssid=
			monitor=1
		;;
		::)
			radio=0
		;;
	esac
}

cron_setup() {
	/etc/init.d/cron reload
}

wlan24_led_off() {
	/usr/bin/rv340_led.sh wlan2.4 off
}

wlan24_led_on() {
	/usr/bin/rv340_led.sh wlan2.4 on
	/etc/init.d/wlan_led start radio0
}

wlan5g_led_off() {
	/usr/bin/rv340_led.sh wlan5g off
}

wlan5g_led_on() {
	/usr/bin/rv340_led.sh wlan5g on
	/etc/init.d/wlan_led start radio1
}

disable_part_broadcom() {
	set_wifi_down "$1"
}

reload_part_broadcom() {
	wifi_button="$(cat /sys/class/gpio/gpio14/value)"
	if [ "$wifi_button" = "0" ];then
		return 0
	fi

	local device="$1"

	cd /sys/class/net
	[ -e "$device" ] || return 0

	include /lib/network

	per_ssid_update "$device"

	true
}

disable_broadcom() {
	local device="$1"
	set_wifi_down "$device"
	[ -e /var/run/wlan_${device}_acsd.post ] && {
		rm /var/run/wlan_${device}_acsd.post
		nvram set acs_ifnames_ext
	}
	[ -e /var/run/wlan_${device}_eapd.post ] && rm /var/run/wlan_${device}_eapd.post
	[ -e /var/run/wlan_${device}_nas.post ] && rm /var/run/wlan_${device}_nas.post
	[ -e /var/run/wlan_${device}_wps.post ] && rm /var/run/wlan_${device}_wps.post

	[ -e /var/run/wlan_${device}_cron.post ] && rm /var/run/wlan_${device}_cron.post
	[ -e /var/run/wlan_${device}_cp.post ] && rm /var/run/wlan_${device}_cp.post

	local acs_ifname_exist="$(nvram get acs_ifnames)"
	local acs_ifname_new=
	for _acs in $acs_ifname_exist; do
		[ "$_acs" = "$device" ] || {
			acs_ifname_new="${acs_ifname_new:+$acs_ifname_new }$_acs"
		}
	done
	nvram set acs_ifnames="$acs_ifname_new"

	(
		include /lib/network

		# make sure the interfaces are down and removed from all bridges
		local ifname
		cd /sys/class/net
		[ -e "$device" ] || return 0

		# make sure all of the devices are disabled in the driver
		local ifdown=
		# local bssmax=$(wl -i "$device" bssmax)
		local bssmax=4

		local vif=$((${bssmax:-4} - 1))

		while [ $vif -gt 0 ]; do
			ifname=${device}.$vif
			vif=$(($vif - 1))
			
			cur_vlanid="$(nvram get ${ifname}_vlanid)"
		
			[ ! -e $ifname ] && continue

			wl -i "$ifname" mac none >/dev/null
			wl -i "$ifname" bss 0
			/usr/bin/wifi_schedule clear $ifname
			unbridge "$ifname"
			bridge_name="$(nvram get ${ifname}_bridge)"
			[ -n "$bridge_name" -a -e /sys/class/net/${bridge_name}/brif/$ifname ] && {
				#ubus call network.interface.vlan${cur_vlanid} remove_device "{\"name\":\"$ifname\"}"
				brctl delif ${bridge_name} $ifname
			}
			ifconfig "$ifname" down
			#wl -i $ifname interface_remove 2>/dev/null
		done

		cur_vlanid="$(nvram get ${device}_vlanid)"

		/usr/bin/wifi_schedule clear $device
		wl -i $device mac none > /dev/null
		wl -i $device bss 0
		wl -i $device down
		unbridge "$device"
		bridge_name="$(nvram get ${device}_bridge)"
		[ -n "${bridge_name}" -a -e /sys/class/net/${bridge_name}/brif/$device ] && {
			#ubus call network.interface.vlan${cur_vlanid} remove_device "{\"name\":\"$device\"}"
			brctl delif ${bridge_name} $device
		}
		ifconfig "$device" down

		wl -i $device wds none

		if [ "$device" = "wl0" ]; then
			wlan24_led_off
			if [ "$2" != "nolog" ];then
				logger -t wireless "WIFI 2.4G is now down"
			fi
		else
			wlan5g_led_off
			if [ "$2" != "nolog" ];then
				logger -t wireless "WIFI 5G is now down"
			fi
		fi
	)

	true
}

eapd_setup() {
	local eapd="$(which eapd)"
	local eapd_pid_file=/var/run/eapd.pid

	[ -e $eapd_pid_file ] && {
		start-stop-daemon -K -q -s SIGKILL -n eapd
		rm $eapd_pid_file
	}

	start-stop-daemon -S -b -m -p $eapd_pid_file -x $eapd
}

nas_setup() {
	local nas="$(which nas)"
	local nas_pid_file=/var/run/nas.pid

	[ -e $nas_pid_file ] && {
		start-stop-daemon -K -q -s SIGKILL -n nas
		rm $nas_pid_file
	}

	start-stop-daemon -S -b -m -p $nas_pid_file -x $nas
}

wps_setup() {
	nvram set wps_monitor_force=1
	nvram set wps_proc_status=0
	start-stop-daemon -K -q -s SIGUSR2 -n wps_daemon
}

acsd_setup() {
	acs_value="$(nvram get acs_ifnames)"
	[ -z "$acs_value" ] && return 0

	acsd_cmd="$(which acsd)"
	[ -e /var/run/acsd.pid ] && {
		start-stop-daemon -K -q -s SIGKILL -n acsd
		rm /var/run/acsd.pid
	}

	touch /var/run/acsd.pid
	#start-stop-daemon -S -x ${acsd_cmd} > /dev/null
	daemon_flag=1
	for acsd_radio in $acs_value; do
		if [ ! -e /var/lock/acsd.${acsd_radio}.lock ];then
			touch /var/lock/acsd.${acsd_radio}.lock
			daemon_flag=0
		fi
	done
	
	if [ "$daemon_flag" = "1" ]; then
		${acsd_cmd} > /dev/null 2>&1 &
	else
		${acsd_cmd} > /dev/null 2>&1
	fi
}

pre_broadcom() {
	local device="$1"
	cd /sys/class/net
	[ ! -e  ${device} ] && return 0

	local vif
	local default_ssids_used=

	config_get vifs "$device" vifs
	for vif in $vifs; do
		local wps_configured=
		config_get ssid "$vif" ssid
		if [ "$ssid" != "ciscosb" ];then
			wps_configured=1
		else
			default_ssids_used="${default_ssids_used:+$default_ssids_used }$ssid"
			wps_configured="$(nvram get ${device}_${ssid}_configured)"
			[ "$wps_configured" = "1" ] || {
				config_get enc "$vif" encryption
				case "$enc" in
					*wep*|*psk*|*wpa*)
						nvram set ${device}_${ssid}_configured=1
						wps_configured=1
					;;
					*)
						nvram set ${device}_${ssid}_configured=1
						wps_configured=1
					;;
				esac
			}
		fi

		config_get_bool disabled "$vif" disabled 0
		[ $disabled -eq 0 ] || {
			continue
		}

		local vlanid
		config_get ifname "$vif" ifname
		config_get vlanid "$vif" vlanid 1

		wan_bridge=""
		network_ifaces="$(ubus list network.interface.* | cut -d'.' -f 3)"
		for network_iface in $network_ifaces; do
			case "$network_iface" in
				wan*)
					if [ -n "$(uci get network.${network_iface}.ifname | grep -w eth3.${vlanid})" ];then
						wan_bridge="${network_iface}"
					fi
				;;
			esac
		done

		if [ -z "$wan_bridge" ];then
			bridge_vlan="vlan${vlanid}"
		else
			bridge_vlan="$wan_bridge"
		fi

		[ -z "$(ubus list  network.interface.${bridge_vlan} 2>/dev/null)" ]  && {
			uci set network.${bridge_vlan}=interface
		}
		uci set network.${bridge_vlan}.type=bridge
		config_set ${vif} network "${bridge_vlan}"

		local lan_idx=0
		while [ $lan_idx -lt 8 ]; do
			local lan_idx_fixed=""
			[ $lan_idx -gt 0 ] && lan_idx_fixed=${lan_idx}

			lan_value="$(nvram get lan${lan_idx_fixed}_vlanid)"

			if [ -n "${lan_value}" ]; then
				[ ${vlanid} -eq ${lan_value} ] && {
					lan_ifnames_exist="$(nvram get lan${lan_idx_fixed}_ifnames)"
					if [ -z "$lan_ifnames_exist" ];then
						nvram set lan${lan_idx_fixed}_ifnames="$ifname"
					else
						nvram set lan${lan_idx_fixed}_ifnames="${lan_ifnames_exist} ${ifname}"
					fi
					break
				}
			else
				nvram set lan${lan_idx_fixed}_vlanid=${vlanid}

				lan_ifnames_exist="$(nvram get lan${lan_idx_fixed}_ifnames)"
				if [ -z "$lan_ifnames_exist" ];then
					nvram set lan${lan_idx_fixed}_ifnames="$ifname"
				else
					nvram set lan${lan_idx_fixed}_ifnames="${lan_ifnames_exist} ${ifname}"
				fi
				break
			fi

			lan_idx=$(($lan_idx + 1))
		done
		
		if [ "$wps_configured" = "1" ];then
			nvram set ${ifname}_wps_oob="disabled"
			nvram set lan${lan_idx_fixed}_wps_oob="disabled"
			nvram set lan${lan_idx_fixed}_wps_reg="enabled"
		else
			nvram set ${ifname}_wps_oob
		fi
	done

	all_default_ssids="ciscosb"
	for default_ssid in $all_default_ssids;do
		if [ -z "$(echo $default_ssids_used | grep $default_ssid)" ];then
			nvram set ${device}_${default_ssid}_configured=1
		fi
	done

	true
}

post_broadcom() {
	if [ "disable" = "$1" -o "disable_part" = "$1" ];then
		local nas_pid_file=/var/run/nas.pid
		[ -e $nas_pid_file ] && {
			start-stop-daemon -K -q -s SIGKILL -n nas
			rm $nas_pid_file
		}

		local eapd_pid_file=/var/run/eapd.pid
		[ -e $eapd_pid_file ] && {
			start-stop-daemon -K -q -s SIGKILL -n eapd
			rm $eapd_pid_file
		}

		[ -e /var/run/acsd.pid ] && {
			if [ "disable" = "$1" ];then
				start-stop-daemon -K -q -s SIGKILL -n acsd
				rm /var/run/acsd.pid
				nvram set acs_ifnames_ext
			else
				_acs_ifname_exist="$(nvram get acs_ifnames)"
				nvram set acs_ifnames_ext="$_acs_ifname_exist"
			fi
		}

		[ -e /var/wps_monitor.pid ] && {
			start-stop-daemon -K -q -s SIGTERM -n wps_monitor
		}

		cron_setup

		local lan_max_no_bridge=8
		local lan_idx=0
		while [ ${lan_idx} -lt ${lan_max_no_bridge} ]; do
			if [ ${lan_idx} -eq 0 ]; then
				if [ "disable_part" = "$1" ];then
					nvram set lan_ifnames
				else
					[ -z "$(nvram get lan_ifname)" ] && break
					nvram set lan_ifnames
					nvram set lan_ifname
					nvram set lan_vlanid
				fi
			else
				if [ "disable_part" = "$1" ];then
					nvram set lan${lan_idx}_ifnames
				else
					[ -z "$(nvram get lan${lan_idx}_ifname)" ] && break
					nvram set lan${lan_idx}_ifnames
					nvram set lan${lan_idx}_ifname
					nvram set lan${lan_idx}_vlanid
				fi
			fi
			lan_idx=$(($lan_idx + 1))
		done

		if [ "disable" = "$1" ];then
			local _ssid_idx=
			while [ ${_ssid_idx:-0} -lt 4 ];do
				for _dev in $2; do
					nvram set ${_dev}${_ssid_idx:+.$_ssid_idx}_ssid
				done
				_ssid_idx=$((${_ssid_idx:-0} + 1))
			done

			echo 3 > /proc/irq/36/smp_affinity
			nvram commit
		fi

		if [ -e /var/run/wlan_wl0_cp.post -o -e /var/run/wlan_wl1_cp.post ];then
			if [ -e /var/run/captive.pid ];then
				start-stop-daemon -K -q -s SIGUSR2 -n cportald
			else
				/etc/init.d/captive_portal reload
			fi
		else
			if [ -e /var/run/captive.pid ];then
				/etc/init.d/captive_portal stop
			fi
		fi
	else
		wifi_button="$(cat /sys/class/gpio/gpio14/value)"
		if [ "$wifi_button" = "0" ];then
			return 0
		fi

		if [ -e /var/run/wlan_wl0_acsd.post -o -e /var/run/wlan_wl1_acsd.post ];then
			_acs_ext="$(nvram get acs_ifnames_ext)"
			same_flag=0
			if [ -n "$_acs_ext" ];then
				_acs_ifnames="$(nvram get acs_ifnames)"
				_acs_ext_cnt="$(echo $_acs_ext | wc -w)"
				_acs_cnt="$(echo $_acs_ifnames | wc -w)"
				same_flag=0
				if [ "$_acs_ext_cnt" = "$_acs_cnt" ];then
					same_flag=0
					for _a_ext in $_acs_ext; do
						same_flag=0
						for _a in $_acs_ifnames;do
							[ "$_a" = "$_a_ext" ] && {
								same_flag=1
								break
							}
						done
					done
				fi
			fi

			if [ "$same_flag" = "0" ];then
				nvram set acs_no_restrict_align=1
				acsd_setup
			fi
		else
			[ -e /var/run/acsd.pid ] && {
				start-stop-daemon -K -q -s SIGKILL -n acsd
				rm /var/run/acsd.pid
			}
		fi
		nvram commit
		[ -e /var/run/wlan_wl0_eapd.post -o -e /var/run/wlan_wl1_eapd.post ] && eapd_setup
		[ -e /var/run/wlan_wl0_nas.post -o -e /var/run/wlan_wl1_nas.post ] && nas_setup
		[ -e /var/run/wlan_wl0_wps.post -o -e /var/run/wlan_wl1_wps.post ] && wps_setup

		[ -e /var/run/wlan_wl0_cron.post -o -e /var/run/wlan_wl1_cron.post ] && cron_setup
		nvram commit

		if [ -e /var/run/wlan_wl0_cp.post -o -e /var/run/wlan_wl1_cp.post ];then
			if [ -e /var/run/captive.pid ];then
				start-stop-daemon -K -q -s SIGUSR2 -n cportald
			else
				/etc/init.d/captive_portal reload
			fi
		else
			if [ -e /var/run/captive.pid ];then
				/etc/init.d/captive_portal stop
			fi
		fi

		# Save the changes to compare for per ssid reload
		cp /tmp/etc/config/wireless /tmp/etc/config/wireless_old >/dev/null 2>&1
	fi

	echo "show wlans" > /tmp/get_wifi_status
	confd_cli -u admin -N /tmp/get_wifi_status | sed -e {1,3d} | sed '$ d' > /tmp/wifi_status_result
	sed -i 's/\\/\\\\/g' /tmp/wifi_status_result

	true
}

init_broadcom() {
	local device="$1"
	local vif_idx=0
	local max_vif_idx="$2"
	local ifname=

	mac_cur=$(wl -i $device rdvar macaddr)
	while [ $vif_idx -lt $max_vif_idx ]; do
		wl -i "$device" ssid -C $vif_idx "" >/dev/null

		[ $vif_idx -eq 0 ] && {
			ifname="${device}"
			mac_cur_addr="${mac_cur:8:17}"
			nvram set ${ifname}_hwaddr="${mac_cur_addr}"
		}

		# add mac addr for multi-ssid
		[ $vif_idx -gt 0 ] && {
			ifname="${device}.${vif_idx}"
			last_value=${mac_cur##*:}
			last_value_new="$(echo $(( (0x${last_value}  + $vif_idx) & 0xf )))"
			last_value_new=$(printf "%x" ${last_value_new})
			mac_new="${mac_cur:8:16}$last_value_new"
			ifconfig $ifname hw ether $mac_new
			nvram set ${ifname}_hwaddr="${mac_new}"
		}
		
		nvram set ${ifname}_ifname=${ifname}

		vif_idx=$(( $vif_idx + 1 ))
	done
}

enable_broadcom() {
	wifi_button="$(cat /sys/class/gpio/gpio14/value)"
	if [ "$wifi_button" = "0" ];then
		return 0
	fi

	local device="$1"
	cd /sys/class/net
	[ ! -e  ${device} ] && return 0

	local vifs
	config_get vifs "$device" vifs

	local channel country maxassoc wds wmm wmm_disable wme_apsd beacon dtim
	local frameburst mac_filter macpolicy maclist macaddr txpower frag rts hwmode htmode
	local mu_mimo wme_no_ack beamforming
	local rate_basic rate ht_mcs vht_mcs_1 vht_mcs_2 vht_mcs_3 vht_mcs_4
	local VHT_MCS
	local HT_MCS
	local cts_protection_mode
	local pmf
	config_get channel "$device" channel
	config_get country "$device" country
	config_get maxassoc "$device" maxassoc
	config_get wds "$device" wds
	config_get beacon "$device" beacon_int
	config_get wmm "$device" wmm
	config_get wme_no_ack "$device" wme_no_ack
	config_get wme_apsd "$device" wme_apsd
	config_get dtim "$device" dtim_period
	config_get_bool frameburst "$device" frameburst
	config_get txpower "$device" txpower
	config_get frag "$device" frag
	config_get rts "$device" rts
	config_get hwmode "$device" hwmode
	config_get htmode "$device" htmode
	config_get mu_mimo "$device" mu_mimo
	config_get rate_basic "$device" basic_rate
	config_get rate "$device" transmit_rate
	config_get ht_mcs "$device" ht_mcs
	config_get vht_mcs_1 "$device" vht_mcs_1
	config_get vht_mcs_2 "$device" vht_mcs_2
	config_get vht_mcs_3 "$device" vht_mcs_3
	config_get vht_mcs_4 "$device" vht_mcs_4
	config_get cts_protection_mode "$device" cts_protection_mode
	config_get beamforming "$device" beamforming
	local b_band_nmode_flag=0

	local schedule_opts=""

	# basic rate and rate
	local rate_settings vht_rate_settings
	for rate_t in $rate_basic; do
		[ "$rate_t" != "5.5" ] && rate_t="${rate_t%%.0}"
		if [ "$rate_t" = "5" ];then
			rate_t="5.5"
		fi
		rate_settings="${rate_t}b $rate_settings"
	done

	for rate_t in $rate; do
		[ -z "$(echo $rate_basic | grep -w $rate_t)" ] && {
			[ "$rate_t" != "5.5" ] && rate_t="${rate_t%%.0}"
			if [ "$rate_t" = "5" ];then
				rate_t="5.5"
			fi
			rate_settings="$rate_settings $rate_t"		
		}
	done

	local doth=0
	local wmm=1
	local band chanspec

	local gmode=2 nmode=0 nreqd=0 vht_mask=0
	case "$hwmode" in
		*ac*)	band="a"; gmode=;nmode=1;nreqd=1
			case "$hwmode" in
				*a*ac*|*ac*a*)	nreqd=0;;
			esac
		;;
		*a*)	band="a"; gmode=;nreqd=0;nmode=0;;
		*b*)	band="b";gmode=0;
			case "$hwmode" in
				*g*) gmode=1;;
			esac
			case "$hwmode" in
				*n*) nmode=1;nreqd=0;
					b_band_nmode_flag=1;
					vht_mask=1;
				;;
			esac
		;;
		*g*)	band="b"; gmode=4;
			case "$hwmode" in
				*n*) nmode=1;nreqd=0;
					b_band_nmode_flag=1;
				;;
			esac
		;;
		*n*)	band="b";nreqd=1;nmode=1;
				b_band_nmode_flag=1;
		;;
		*)	band="b";nmode=1; nreqd=0;
			b_band_nmode_flag=1;
		;;
	esac

	local bandwidth=20
	local sideband=0

	if [ "$channel" = "auto" -o "$channel" = "0" ];then
		chanspec=0
		if [ "$band" = "a" ];then
			case "$htmode" in
				*80*) bandwidth="80";;
				*40*) bandwidth="40";;
				*) bandwidth="20";;
			esac
			[ "$hwmode" = "11a" -o "$hwmode" = "a" ] && bandwidth="20"
		fi
	else
		# Use 'chanspec' instead of 'channel'
		chanspec="${channel}"
		if [ "$band" = "a" ];then
			case "$htmode" in
				*80*) bandwidth="80";;
				*40-*) bandwidth="40";sideband="1";;
				*40+*) bandwidth="40";sideband="-1";;
				*) bandwidth="20";;
			esac
			[ "$hwmode" = "11a" -o "$hwmode" = "a" ] && bandwidth="20"
			chanspec="${channel}/${bandwidth}" 
		else
			case "$htmode" in
				*40-*) chanspec="${channel}u";;
				*40+*) chanspec="${channel}l";;
				*40*) chanspec="${channel}l";;
			esac
		fi
	fi

	if [ "$band" = "b" ];then
		wlan24_led_on
	else
		wlan5g_led_on
	fi

	# in case no wifi-iface but only wifi-device
	interrupt_flag=1
	for vif in $vifs; do
		interrupt_flag=0
		break
	done
	[ "$interrupt_flag" = "1" ] && {
		return 0
	}

	pre_broadcom $device
	ubus call network reload

	touch /tmp/wireless_boot

	local _c=0
	local nas="$(which nas)"
	local eapd="$(which eapd)"
	local wpsopts=
	local wps=
	local captiveopts=0
	local if_pre_up if_up nas_cmd eapd_cmd
	local vif vif_pre_up vif_post_up vif_do_up vif_txpower
	local bssmax=$(wl -i "$device" bssmax)
	bssmax=${bssmax:-4}

	local led_on=0

	for vif in $vifs; do
		[ $_c -ge $bssmax ] && break

		_c=$(( $_c + 1 ))

		config_get vif_txpower "$vif" txpower

		local mode
		config_get mode "$vif" mode

		local ifname
		config_get ifname "$vif" ifname

		config_get_bool wmm "$vif" wmm "$wmm"
		[ "$wmm" = "1" ] && wmm_disable=0 || wmm_disable=1
		config_get_bool doth "$vif" doth "$doth"

		local ssid
		local _ssid_idx="${ifname#*.}"
		[ "$_ssid_idx" = "$device" ] && _ssid_idx=0
		eval config_get ssid_${_c} "$vif" ssid
		append vif_pre_up "wl -i $device ssid -C $_ssid_idx \"\${ssid_${_c}}\";"
		eval ssid="\${ssid_${_c}}"
		nvram set ${ifname}_ssid="${ssid}"

		config_get_bool disabled "$vif" disabled 0
		[ $disabled -eq 0 ] || {
			continue
		}

		nvram set ${ifname}_bss_enabled=1
		[ "$ap" = "1" ] && nvram set ${ifname}_mode=ap

		#config_get network "$vif" network
		#[ -n "$network" ] && append vif_pre_up "brctl addif br-${network} ${ifname} 2>&1 >/dev/null;"

		[ "$mode" = "sta" ] || {
			local hidden isolate
			config_get_bool hidden "$vif" hidden 0
			append vif_pre_up "wl -i $ifname closed $hidden;"
			config_get_bool isolate "$vif" isolate 0
			append vif_pre_up "wl -i $ifname ap_isolate $isolate;"
		}

		local schedule
		local schedule_result="up"
		config_get schedule "$vif" schedule
		[ -z "$schedule" -o "$schedule" = "always" ] || {
			schedule_opts="1"
			/usr/bin/wifi_schedule set $ifname $schedule

			[ "x$(/usr/bin/wifi_schedule_check $schedule 2>/dev/null)" = "x0" ] && {
				schedule_result="down"
			}
		}

		config_get mac_filter "$vif" mac_filter
		maclist=
		if [ "$mac_filter" = "1" ]; then
			config_get macpolicy "$vif" macpolicy
			config_get maclist "$vif" maclist
			case "$macpolicy" in
				allow|2)
					macpolicy=2;
				;;
				deny|1)
					macpolicy=1;
				;;
				disable|none|0)
					macpolicy=0;
				;;
			esac
		else
			macpolicy=0
		fi

		append vif_pre_up "wl -i $ifname macmode $macpolicy;"
		append vif_pre_up "wl -i $ifname mac $maclist;"
		append vif_pre_up "wl -i $ifname wme_bss_disable $wmm_disable;"

		local wsec_r=1
		local eap_r=0
		local wsec=0
		local auth=0
		local nasopts=
		local eapdopts=
		local enc key rekey
				
		nvram set ${ifname}_auth_mode

		append vif_do_up "wl -i $ifname auth 0;"
		append vif_do_up "wl -i $ifname eap $eap_r;"
		append vif_do_up "wl -i $ifname wsec $wsec;"
		append vif_do_up "wl -i $ifname wsec_restrict $wsec_r;"
		append vif_do_up "wl -i $ifname wpa_auth $auth;"
		append vif_do_up "wl -i $ifname mfp_config 0;"

		local vlanid
		config_get vlanid "$vif" vlanid 1

		config_get wps "$vif" wps
		
		nvram set ${ifname}_radio=1

		config_get pmf "$vif" pmf 1
		config_get enc "$vif" encryption
		case "$enc" in
			*wep*)
				nvram set ${ifname}_wps_mode="disabled"
				nvram set ${ifname}_wfi_enable
				local def defkey k knr
				wsec_r=1
				wsec=1
				defkey=1
				
				nvram set ${ifname}_wpa_psk
				nvram set ${ifname}_akm
				nvram set ${ifname}_crypto
				nvram set ${ifname}_auth
				nvram set ${ifname}_wep

				# Disable WPA first
				append vif_do_up "wl -i $ifname wpa_auth 0;"

				append vif_do_up "wl -i $ifname eap $eap_r;"
				append vif_do_up "wl -i $ifname wsec $wsec;"
				append vif_do_up "wl -i $ifname wsec_restrict $wsec_r;"

				config_get key "$vif" key
				case "$enc" in
					*shared*) append vif_do_up "wl -i $ifname auth 1;";;
					*) append vif_do_up "wl -i $ifname auth 0;";;
				esac
				case "$key" in
					[1234])
						defkey="$key"
						local key_index=0
						for knr in 1 2 3 4; do
							config_get k "$vif" key$knr
							[ -n "$k" ] || continue
							append vif_do_up "wl -i $ifname addwep $key_index ${k:2};"
						done
					;;
					"");;
					*) append vif_do_up "wl -i $ifname addwep 0 $key;";;
				esac
			;;
			*psk*)
				wsec_r=1
				config_get key "$vif" key

				nvram set ${ifname}_wpa_gtk_rekey=3600
				nvram set ${ifname}_preauth=1

				# psk version + default cipher
				case "$enc" in
					*mixed*|*psk+psk2*) auth=132; wsec=6; nvram set ${ifname}_akm="psk psk2";
						append vif_do_up "wl -i $ifname mfp_config $pmf;"
					;;
					*psk2*) auth=128; wsec=4;nvram set ${ifname}_akm=psk2;
						append vif_do_up "wl -i $ifname mfp_config $pmf;"
					;;
					*) auth=4;
						if [ "$band" = "a" ];then
							wsec=4;
						else
							wsec=2;
						fi
						wps=0;
						nvram set ${ifname}_akm=psk;;
				esac

				# cipher override
				case "$enc" in
					*tkip+aes*|*tkip+ccmp*|*aes+tkip*|*ccmp+tkip*) wsec=6;;
					*aes*|*ccmp*) wsec=4;;
					*tkip*) wsec=2;;
				esac

				[ "$wsec" = "6" ] && nvram set ${ifname}_crypto="tkip+aes"
				[ "$wsec" = "4" ] && nvram set ${ifname}_crypto="aes"
				[ "$wsec" = "2" ] && nvram set ${ifname}_crypto="tkip"

				append vif_do_up "wl -i $ifname auth 0;"
				append vif_do_up "wl -i $ifname eap $eap_r;"
				append vif_do_up "wl -i $ifname wsec $wsec;"
				append vif_do_up "wl -i $ifname wsec_restrict $wsec_r;"
				append vif_do_up "wl -i $ifname wpa_auth $auth;"
				# group rekey interval
				#config_get rekey "$vif" wpa_group_rekey

				#eval "${vif}_key=\"\$key\""
				#nasopts="-k $key ${rekey:+ -g $rekey}"
				#eapdopts="-nas ${ifname}"
				
				nvram set ${ifname}_wpa_psk="${key}"
				nvram set ${ifname}_auth=0

				nvram set ${ifname}_wep=disabled
				
				if [ "$wps" = "1" -a "$hidden" != "1" ]; then
					nvram set ${ifname}_wps_mode="enabled"
					nvram set ${ifname}_wfi_enable=1

					wpsopts=1
					#append eapdopts " -wps ${ifname}"
				else
					nvram set ${ifname}_wps_mode="disabled"
					nvram set ${ifname}_wfi_enable
				fi
			;;
			*wpa*)
				nvram set ${ifname}_wpa_gtk_rekey=3600
				nvram set ${ifname}_net_reauth=36000
				nvram set ${ifname}_preauth=1
				nvram set ${ifname}_wep=disabled
				nvram set ${ifname}_auth=0

				nvram set ${ifname}_wps_mode="disabled"
				nvram set ${ifname}_wfi_enable
				local Radius_port Radius_secret Radius_server
				wsec_r=1
				eap_r=1
				config_get Radius_server "$vif" Radius_server
				[ -z "$Radius_server" ] && config_get Radius_server "$vif" server
				config_get Radius_port "$vif" Radius_port
				[ -z "$Radius_port" ] && config_get Radius_port "$vif" port
				config_get Radius_secret "$vif" Radius_secret
				[ -z "$Radius_secret" ] && config_get Radius_secret "$vif" key

				# wpa version + default cipher
				case "$enc" in
					*mixed*|*wpa+wpa2*) auth=66; wsec=6;nvram set ${ifname}_akm="wpa wpa2";
						append vif_do_up "wl -i $ifname mfp_config $pmf;"
					;;
					*wpa2*) auth=64; wsec=4;nvram set ${ifname}_akm=wpa2;
						append vif_do_up "wl -i $ifname mfp_config $pmf;"
					;;
					*) auth=2;
						if [ "$band" = "a" ];then
							wsec=4;
						else
							wsec=2;
						fi
						nvram set ${ifname}_akm=wpa;;
				esac

				# cipher override
				case "$enc" in
					*tkip+aes*|*tkip+ccmp*|*aes+tkip*|*ccmp+tkip*) wsec=6;;
					*aes*|*ccmp*) wsec=4;;
					*tkip*) wsec=2;;
				esac

				[ "$wsec" = "6" ] && nvram set ${ifname}_crypto="tkip+aes"
				[ "$wsec" = "4" ] && nvram set ${ifname}_crypto="aes"
				[ "$wsec" = "2" ] && nvram set ${ifname}_crypto="tkip"

				nvram set ${ifname}_auth_mode="radius"

				append vif_do_up "wl -i $ifname auth 0;"
				append vif_do_up "wl -i $ifname eap $eap_r;"
				append vif_do_up "wl -i $ifname wsec $wsec;"
				append vif_do_up "wl -i $ifname wsec_restrict $wsec_r;"
				append vif_do_up "wl -i $ifname wpa_auth $auth;"

				# group rekey interval
				config_get rekey "$vif" wpa_group_rekey

				eval "${vif}_key=\"\$Radius_secret\""

				nvram set ${ifname}_radius_key="$Radius_secret"
				nvram set ${ifname}_radius_ipaddr="$Radius_server"
				nvram set ${ifname}_radius_port="${Radius_port:-1812}"
				#nvram set ${ifname}_wpa_gtk_rekey="${rekey}"
				#nasopts="-r $Radius_secret -h $Radius_server -p ${Radius_port:-1812}${rekey:+ -g $rekey}"
				#eapdopts="-nas ${ifname}"
			;;
			*)
				if [ "$wps" = "1" -a "$hidden" != "1" ];then
					nvram set ${ifname}_wps_mode="enabled"
					nvram set ${ifname}_wfi_enable=1
					nvram set ${ifname}_auth=0
					nvram set ${ifname}_wep=disabled
					nvram set ${ifname}_akm
					nvram set ${ifname}_wpa_psk
					nvram set ${ifname}_crypto

					wpsopts=1
					append vif_do_up "wl -i $ifname mfp_config $pmf;"
				else
					nvram set ${ifname}_wps_mode="disabled"
					nvram set ${ifname}_wfi_enable
				fi
			;;
		esac

		[ "$mode" = "monitor" ] && {
			append vif_post_up "wl -i $ifname monitor $monitor;"
		}

		[ "$mode" = "adhoc" ] && {
			local bssid
			config_get bssid "$vif" bssid
			[ -n "$bssid" ] && {
				append vif_pre_up "wl -i $ifname bssid $bssid;"
			}
		}

		append vif_post_up "wl -i $ifname bss $schedule_result;"
		[ "$schedule_result" = "up" ] && led_on=1

        local bridge
		local captive
		config_get captive "$vif" captive "0"
		let "captiveopts=$captive|$captiveopts"

		local net_cfg=""
		net_cfg="$(find_net_config "$vif")"
		[ -z "$net_cfg" ] || {
			#bridge="$(bridge_interface "$net_cfg")"
			bridge="br-${net_cfg}"

			local lan_idx=0
			while [ $lan_idx -lt 8 ]; do
				local lan_idx_fixed=""
				[ $lan_idx -gt 0 ] && lan_idx_fixed=${lan_idx}

				lan_value="$(nvram get lan${lan_idx_fixed}_vlanid)"

				if [ -n "$lan_value" ]; then
					[ ${vlanid} -eq $lan_value ] && {
						nvram set lan${lan_idx_fixed}_ifname="$bridge"
						nvram set ${ifname}_bridge="$bridge"
						break;
					}
				else
					nvram set lan${lan_idx_fixed}_vlanid=${vlanid}
					nvram set lan${lan_idx_fixed}_ifname="$bridge"
					nvram set ${ifname}_bridge="$bridge"
					break
				fi
				lan_idx=$(($lan_idx + 1))
			done

			#uci set wireless.${vif}.bridge="$bridge"
			#append if_up "start_net '$ifname' '$net_cfg'" ";$N"
			append if_up "brctl addif $bridge $ifname" ";$N"
			append if_up "set_wifi_up '$vif' '$ifname'" ";$N"
		}

		nvram set ${ifname}_vlanid=${vlanid}

		append if_up "ifconfig '$ifname' up" ";$N"

		[ -z "$nas" ] || {
			local nas_mode="-A"
			[ "$mode" = "sta" ] && nas_mode="-S"
			local nas_pid_file=/var/run/nas.pid
			[ -z "$nas_cmd" ] && {
				if [ -e $nas_pid_file ]; then
					start-stop-daemon -K -q -s SIGKILL -n nas && rm $nas_pid_file
				fi
					
				#nas_cmd="start-stop-daemon -S -b -m -p $nas_pid_file -x $nas"
				touch /var/run/wlan_${device}_nas.post
			}
			#append nas_cmd "-i $ifname $nas_mode -m $auth -w $wsec -s $ssid -g 3600 $nasopts"
		}

		[ -z "$eapd" ] || {
			local eapd_pid_file=/var/run/eapd.pid
			[ -z "$eapd_cmd" ] && {
				if [ -e $eapd_pid_file ];then
					start-stop-daemon -K -q -s SIGKILL -n eapd && rm $eapd_pid_file
				fi
					
				#local eapd_pid_file=/var/run/eapd.pid
				#eapd_cmd="start-stop-daemon -S -b -m -p $eapd_pid_file -x $eapd"
				touch /var/run/wlan_${device}_eapd.post
			}

			#append eapd_cmd "$eapdopts"
		}

		_c=$(($_c + 1))

	done

	per_ssid_prepare "$device"

	wl -i "$device" band $band
	wl -i "$device" ap $ap

	wl -i "$device" mbss $mssid

	# reset basic rate
	# wl -i "$device" rateset default
	
	case "$hwmode" in
		*a*)
			[ -n "$ht_mcs" ] && {
				local ht_mcs_tr
				HT_HEX="0x$ht_mcs"
				while [ "$HT_HEX" != "0" ]; do
					HT_STR=$(($HT_HEX & 0xff))
					HT_HEX=$(($HT_HEX >> 8))
					HT_RESULT=$(echo $HT_STR | awk '{printf("%x", $1)}')
					ht_mcs_tr="$ht_mcs_tr $HT_RESULT"
				done

				rate_settings="${rate_settings} -m $ht_mcs_tr";
			}

			[ -z "$vht_mcs_1" -a -z "$vht_mcs_2" -a -z "$vht_mcs_3" -a -z "$vht_mcs_4" ] || {
				rate_line="$(wl -i $device rateset | wc -l)"

				[ -z "$vht_mcs_1" -a $rate_line -ge 3 ] && {
					output="$(wl -i "$device" rateset | head -n 3 | tail -n 1 | sed 's/VHT SET : //g')"
					output="$(echo $output | sed 's/x[^d]//g')"
					for idx in $output; do
						ht="$(echo $((1<<$idx)))"
						VHT_MCS="$(echo $(($ht | $HT_MCS)))"
					done
					vht_mcs_1="$(echo ${VHT_MCS} | awk '{printf("%x", $1)}')"
				}

				[ -z "$vht_mcs_2" -a $rate_line -ge 4 ] && {
					output="$(wl -i "$device" rateset | head -n 4 | tail -n 1 | sed 's/VHT SET : //g')"
					output="$(echo $output | sed 's/x[^d]//g')"
					for idx in $output; do
						ht="$(echo $((1<<$idx)))"
						VHT_MCS="$(echo $(($ht | $HT_MCS)))"
					done
					vht_mcs_2="$(echo ${VHT_MCS} | awk '{printf("%x", $1)}')"
				}
				
				[ -z "$vht_mcs_3" -a $rate_line -ge 5 ] && {
					output="$(wl -i "$device" rateset | head -n 5 | tail -n 1 | sed 's/VHT SET : //g')"
					output="$(echo $output | sed 's/x[^d]//g')"
					for idx in $output; do
						ht="$(echo $((1<<$idx)))"
						VHT_MCS="$(echo $(($ht | $HT_MCS)))"
					done
					vht_mcs_3="$(echo ${VHT_MCS} | awk '{printf("%x", $1)}')"
				}

				[ -z "$vht_mcs_4" -a $rate_line -ge 6 ] && {
					output="$(wl -i "$device" rateset | head -n 6 | tail -n 1 | sed 's/VHT SET : //g')"
					output="$(echo $output | sed 's/x[^d]//g')"
					for idx in $output; do
						ht="$(echo $((1<<$idx)))"
						VHT_MCS="$(echo $(($ht | $HT_MCS)))"
					done
					vht_mcs_4="$(echo ${VHT_MCS} | awk '{printf("%x", $1)}')"
				}
				
				vht_rate_settings="-v $vht_mcs_1 $vht_mcs_2 $vht_mcs_3 $vht_mcs_4";
			}
			;;
		*n*)
			[ -n "$ht_mcs" ] && {
				local ht_mcs_tr
				HT_HEX="0x$ht_mcs"
				while [ "$HT_HEX" != "0" ]; do
					HT_STR=$(($HT_HEX & 0xff))
					HT_HEX=$(($HT_HEX >> 8))
					HT_RESULT=$(echo $HT_STR | awk '{printf("%x", $1)}')
					ht_mcs_tr="$ht_mcs_tr $HT_RESULT"
				done

				rate_settings="${rate_settings} -m $ht_mcs_tr";
			}
			;;
	esac
	
	#Country code, pid format: RV340W-X-K9
	pid_radio="$(uci get systeminfo.sysinfo.pid | cut -d'-' -f2)"
	
	include_chanlist=""
	case "$pid_radio" in
		E)
			[ "$band" = "b" ] && {
				include_chanlist="1 2 3 4 5 6 7 8 9 10 11 12 13"
			} || {
				include_chanlist="36 40 44 48 52 56 60 64 100 104 108 112 116 132 136 140"
			}
			country="E0/839"
		;;
		C)
			[ "$band" = "b" ] && {
				include_chanlist="1 2 3 4 5 6 7 8 9 10 11 12 13"
			} || {
				include_chanlist="36 40 44 48 52 56 60 64"
			}
			country="E0/839"
		;;
		*)
			[ "$band" = "b" ] && {
				include_chanlist="1 2 3 4 5 6 7 8 9 10 11"
			} || {
				include_chanlist="36 40 44 48 52 56 60 64 100 104 108 112 116 132 136 140 149 153 157 161 165"
			}

			#country="US/868"
			country="Q1/896"
		;;
	esac
	
	wl -i "$device" country ${country:-Q1/896}

	# clear exclude_chanlist first
	wl -i "$device" exclude_chanlist 0

	[ -n "$include_chanlist" ] && {
		for l_chan in $(wl -i "$device" channels);do
			[ -z "$(echo $include_chanlist | grep -w $l_chan)" ] && {
				wl -i "$device" exclude_chanlist $l_chan
			}
		done
	}

	if [ "$band" = "a" ];then
		case "$htmode" in
			*80*) wl -i "$device" bw_cap 5g 0x7
				nvram set  ${device}_bw_cap=7
			;;
			*40*) wl -i "$device" bw_cap 5g 0x3
				nvram set  ${device}_bw_cap=3
			;;
			*20*) wl -i "$device" bw_cap 5g 0x1
				nvram set  ${device}_bw_cap=1
			;;
		esac
	else
		case "$htmode" in
			*40*) wl -i "$device" bw_cap 2g 0x3
				nvram set  ${device}_bw_cap=3
				wl -i "$device" obss_coex 1
			;;
			*20*) wl -i "$device" bw_cap 2g 0x1
				nvram set  ${device}_bw_cap=1
				[ "$b_band_nmode_flag" = "1" ] && wl -i "$device" obss_coex 0
			;;
		esac
	fi

	hw_rxchain="$(wl -i $device hw_rxchain)"
	hw_rxchain="${hw_rxchain%% *}"
	hw_txchain="$(wl -i $device hw_txchain)"
	hw_txchain="${hw_txchain%% *}"
	wl -i "$device" rxchain $hw_rxchain
	wl -i "$device" txchain $hw_txchain
	wl -i "$device" nmode $nmode
	
	if [ $nmode = "1" ];then
		wl -i "$device" nreqd $nreqd
	fi

	if [ "$band" = "b" ];then
	wl -i "$device" gmode $gmode
	fi
	if [ "$chanspec" != "0" ]; then
		if [ "$band" = "a" -a "$bandwidth" = "80" ];then
			wl -i "$device" chanspec -c $channel -b 5 -w $bandwidth -s $sideband
		else
			wl -i "$device" chanspec $chanspec
		fi
	else
		# In case previous channel is radar channel, auto channel will not work
		[ "$band" = "a" ] && wl -i "$device" chanspec 36/${bandwidth}
	fi

	wl -i "$device" apsta $apsta
	wl -i "$device" infra $infra
	wl -i "$device" wme 1
	[ "$cts_protection_mode" = "2" ] && wl -i "$device" gmode_protection_override 0 || {
		wl -i "$device" gmode_protection_override -1
	}
	wl -i "$device" rtsthresh $rts

	wl -i $device bi $beacon

	wl -i $device dtim $dtim
	wl -i "$device" fragthresh ${frag:-2346}
	wl -i "$device" monitor ${monitor:-0}
	wl -i "$device" ack_ratio 2
	# For 5G, max associated clients is 124, mumimo with 128
	# For 2.4G, max associated clients is 50
	wl -i "$device" amsdu_aggsf 2
	if [ "$band" = "a" ];then
		if [ -n "$maxassoc" ];then
			if [ "$mu_mimo" = "1" ];then
				if [ $maxassoc -gt 128 ];then
					maxassoc=128
				fi
			else
				if [ $maxassoc -gt 124 ];then
					maxassoc=124
				fi
			fi
		else
			maxassoc=124
		fi
	else
		if [ -n "$maxassoc" ];then
			[ $maxassoc -gt 50 ] && maxassoc=50
		else
			maxassoc=50
		fi
	fi
	wl -i "$device" maxassoc $maxassoc


	wl -i "$device" frameburst ${frameburst:-1}

	init_broadcom "$device" 4

	eval "$vif_pre_up"

	_vif_idx=0
	_vif_ifname="$device"
	while [  $_vif_idx -lt 4 ];do
		[ $_vif_idx -gt 0 ] && _vif_ifname="${device}.${_vif_idx}"
		[ -e "$_vif_ifname" ] || continue

		wl -i "$_vif_ifname" wme_noack $wme_no_ack
		if [ "$ap" = "1" ]; then
			wl -i $_vif_ifname wme_apsd $wme_apsd
		else
			wl -i $_vif_ifname wme_apsd_sta $wme_apsd
		fi
		_vif_idx=$(( $_vif_idx + 1 ))
	done
	#for vif in $vifs; do
	#	config_get_bool disabled "$vif" disabled 0
	#	[ $disabled -eq 0 ] || continue
	#	config_get ifname "$vif" ifname
	#	wl -i "$ifname" wme_noack $wme_no_ack
	#	if [ "$ap" = "1" ]; then
	#		wl -i $ifname wme_apsd $wme_apsd
	#	else
	#		wl -i $ifname wme_apsd_sta $wme_apsd
	#	fi
	#done

	[ -n "$rate_settings" ] && {
		#for vif in $vifs; do
			#config_get_bool disabled "$vif" disabled 0
			#[ $disabled -eq 0 ] || continue
			#config_get ifname "$vif" ifname
			#wl -i "$ifname" rateset $rate_settings
		#done
		_vif_idx=0
		_vif_ifname="$device"
		while [  $_vif_idx -lt 4 ];do
			[ $_vif_idx -gt 0 ] && _vif_ifname="${device}.${_vif_idx}"
			[ -e "$_vif_ifname" ] || continue
			wl -i "$_vif_ifname" rateset $rate_settings
			_vif_idx=$(( $_vif_idx + 1 ))
		done
	}
	[ -n "$vht_rate_settings" ] && {
		# DO NOT remove the following commands, ht_mcs  will be recovered without the following
		# commands
		wl -i "$device" up
		wl -i "$device" down

		#for vif in $vifs; do
			#config_get_bool disabled "$vif" disabled 0
			#[ $disabled -eq 0 ] || continue
			#config_get ifname "$vif" ifname
			#wl -i "$ifname" rateset $vht_rate_settings
		#done
		#set all possible interfaces

		_vif_idx=0
		_vif_ifname="$device"
		while [  $_vif_idx -lt 4 ];do
			[ $_vif_idx -gt 0 ] && _vif_ifname="${device}.${_vif_idx}"
			[ -e "$_vif_ifname" ] || continue
			wl -i "$_vif_ifname" rateset $vht_rate_settings
			_vif_idx=$(( $_vif_idx + 1 ))
		done
	}

	eval "$if_pre_up"

	eval "$vif_do_up"

	if [ "$band" = "a" ];then
	#	wl -i "$device" nar 0
	#	wl -i "$device" spect 0
		wl -i "$device" radar 1
		wl -i "$device" ampdu_mpdu -1
		wl -i "$device" pktcbnd 36
		wl -i "$device" txbf_imp 0
		wl -i "$device" txbf_bfe_cap 0

		if [ "$mu_mimo" = "1"  ];then
			wl -i "$device" mpc 0
			wl -i "$device" vht_features 6
			wl -i "$device" txbf_bfr_cap 2
			wl -i "$device" mu_features 1
			wl -i "$device" mutx 1
		else
			wl -i "$device" mu_features 0
		fi
	else
		if [ "$vht_mask" = "1" ];then
			wl -i "$device" vht_features 3
		fi
		wl -i "$device" ampdu_mpdu -1
		wl -i "$device" pktcbnd 512
	fi

	if [ "$mu_mimo" != "1" ];then
		wl -i "$device" txbf $beamforming
	else
		wl -i "$device" txbf 1
	fi

	wl -i "$device" up

	[ "$band" = "a" ] && {
		wl -i "$device" radarthrs 0x6b8 0x30 0x6b8 0x30 0x6b8 0x30 0x6b0 0x30 0x6b0 0x30 0x6b0 0x30
	}

	#wl -i "$device" ampdu_mpdu 64
	# DO NOT remove this line, for BCM43465 as AP
	# [ "$mu_mimo" != "1" ] && wl -i "$device" macreg 0x240 4 0x3700841

	#CPU affinity settings
	#echo 2 > /proc/irq/36/smp_affinity
	[ "$band" = "b" ] && {
		echo 2 >  /proc/irq/75/smp_affinity
		for vif in $vifs; do
			config_get ifname "$vif" ifname
			[ -e /sys/devices/platform/pfe.0/$ifname/rx_cpu_affinity ] && echo 1 > /sys/devices/platform/pfe.0/$ifname/rx_cpu_affinity
		done
	}
	[ "$band" = "a" ] && {
		echo 1 > /proc/irq/76/smp_affinity
		for vif in $vifs; do
			config_get ifname "$vif" ifname
			[ -e /sys/devices/platform/pfe.0/$ifname/rx_cpu_affinity ] && echo 0 > /sys/devices/platform/pfe.0/$ifname/rx_cpu_affinity
		done
	}

	# Autochannel
	acs_ifnames_exist="$(nvram get acs_ifnames)"
	[ "$chanspec" = "0" -a "$led_on" = "1" ] && {
		if [ -n "$acs_ifnames_exist" ];then
			nvram set acs_ifnames="${acs_ifnames_exist} $device"
		else
			nvram set acs_ifnames="$device"
		fi

		touch /var/run/wlan_${device}_acsd.post
	}
	
	eval "$vif_post_up"

	eval "$if_up"

	if [ "$led_on" = "1" ]; then
		if [ "$band" = "b" ]; then
			logger -t wireless "WIFI 2.4G is now up"
		else
			logger -t wireless "WIFI 5G is now up"
		fi
	else
		wl -i $device down
	fi

	# use vif_txpower (from last wifi-iface) instead of txpower (from
	# wifi-device) if the latter does not exist
	txpower=${txpower:-$vif_txpower}
	[ -z "$txpower" ] || {
		if [ "$txpower" = "100" ];then
			wl -i $device txpwr1 -1
		else
			txpower_value=$(echo $txpower | awk '{printf ("%.0f\n",31*$1/100)}')
			wl -i $device txpwr1 -d $txpower_value
		fi
	}

	[ "$schedule_opts" = "1" ] && touch /var/run/wlan_${device}_cron.post
	[ "$wpsopts" = "1" ] && touch /var/run/wlan_${device}_wps.post
	[ "$captiveopts" -eq 1 ] && touch /var/run/wlan_${device}_cp.post

	true
}


detect_broadcom() {
	local i=-1

	while grep -qs "^ *wl$((++i)):" /proc/net/dev; do
		local channel type ssid_suffix

		ssid_suffix="_24g"

		config_get type wl${i} type
		[ "$type" = broadcom ] && continue
		channel=48
		[ "${i}" = "1" ] && ssid_suffix="_5g"

		cat <<EOF
config wifi-device  wl${i}
	option type     broadcom
	option channel  ${channel:-11}
	option htmode	80

config wifi-iface
	option device   wl${i}
	option network	lan
	option mode     ap
	option ssid     ciscosb${ssid_suffix}${i#0}
	option encryption none
	option wps		1

EOF
	done
}
