#!/bin/sh
. /etc/boardInfo

# Change log
#
# 2018/01/29: ganesh.reddy@nxp.com
# - PnP enablement
# 2018/03/02: ganesh.reddy@nxp.com
# - Sync up changes from PP to BB2.

. /lib/functions/network.sh
. /lib/config/uci.sh

board=`uci get systeminfo.sysinfo.pid | awk -F '-' '{print $1}'`

dhcp() {
	local retval=1
	uci commit dhcp
	/etc/init.d/dnsmasq reload
	
	# 4G nat dongle reconnect
	temp=`lsusb | grep "Bus 003" | grep -v "Device 001" | cut -d " " -f 6`
	if [ "$temp" = "12d1:14db" ] || [ "$temp" = "12d1:14dc" ] || [ "$temp" = "1199:9055" ];then
		echo "1" > /sys/devices/platform/dwc_otg.0/usb3/bConfigurationValue
	fi
	
	retval=$?
	return $retval
}

radvd() {
	local retval=1
	uci commit radvd
	/etc/init.d/radvd reload
	
	retval=$?
	return $retval
}

swupdate() {
	local retval=1
	/etc/init.d/swupdateinit restart
	retval=$?
	return $retval
}

poeconf() {
	local retval=1
	/etc/init.d/poeinit reload
	retval=$?
	return $retval
}

snmpconf() {
	local retval=1
	uci commit snmpconf
	/etc/init.d/snmpinit reload
	retval=$?
	return $retval
}

aaa() {
	local retval=1
	uci commit aaa
	/etc/init.d/aaa reload
	retval=$?
	return $retval
}

switch() {
	local retval=1
	local old_status
	local new_status
	local old_dev_mgmt
	old_status=$(uci get /tmp/etc/config/switch.dot1x_status.state)

	old_ips_status=$(uci get /tmp/etc/config/switch.ip_source_guard_0.status)
	old_umac_status=$(uci get /tmp/etc/config/switch.block_unknown_mac_0.status)

	cp /tmp/.uci/switch /tmp/switch_config
	cp /tmp/.uci/qos_switch /tmp/qos_switch_config
	new_status=$(uci get switch.dot1x_status.state)

	# To avoid multiple ip table rules in device_management
	touch /tmp/switch-bkp
	cp /tmp/etc/config/switch /tmp/switch-bkp

	isClearConn=0
	local inter_vlan_cmd=`cat /tmp/.uci/switch |grep routing |cut -f 1 -d=`
	if [ "$inter_vlan_cmd" != "" ]; then
		for i in $inter_vlan_cmd
		do
			local old_inter_vlan=`uci get /tmp/etc/config/$i`
			local new_inter_vlan=`uci get $i`
			#echo "$i,old:$old_inter_vlan,new:$new_inter_vlan"
			if [ "$new_inter_vlan" = "disable" ] && [ "$old_inter_vlan" = "enable" ]; then
				isClearConn="1"
				break
			fi
		done
	fi

	local dev_mgmt_cmd=`cat /tmp/.uci/switch |grep dev_mgmt |cut -f 1 -d=`
	#If isClearConn was set already, then no need to check device management configuration
	if [ "$dev_mgmt_cmd" != "" -a "$isClearConn" != "1" ]; then
		for i in $dev_mgmt_cmd
		do
			local old_dev_mgmt=`uci get /tmp/etc/config/$i`
			local new_dev_mgmt=`uci get $i`
			#echo "$i,old:$old_dev_mgmt,new:$new_dev_mgmt"
			if [ "$new_dev_mgmt" = "disable" ] && [ "$old_dev_mgmt" = "enable" ]; then
				isClearConn="1"
				break
			fi
		done
	fi

	uci commit switch
	uci commit qos_switch


	board=`uci get systeminfo.sysinfo.pid | cut -d'-' -f1`
	if [ "$board" = "RV340" -o "$board" = "RV340W" ]; then
		/etc/init.d/switch reload
		if [ $new_status != $old_status ]
		then
			/etc/init.d/dot1x restart
		else                        
			/etc/init.d/dot1x reload
       		fi
	elif [ "$board" = "RV345" -o "$board" = "RV345P" ]; then
		rm /tmp/gbl_ip_src_config
		rm /tmp/gbl_umac_config
		new_ips_status=$(uci get switch.ip_source_guard_0.status)
		new_umac_status=$(uci get switch.block_unknown_mac_0.status)
		if [ $new_ips_status != $old_ips_status ]
		then
			touch /tmp/gbl_ip_src_config
		fi
		if [ $new_umac_status != $old_umac_status ]
		then
			touch /tmp/gbl_umac_config
		fi

		/etc/init.d/ms-switch reload
		if [ $new_status != $old_status ]
		then
			/etc/init.d/dot1x restart
		else                        
			/etc/init.d/dot1x reload
       		fi
	fi

	[ "$isClearConn" = "1" ] && {
		#echo "calling clear conn"
		/usr/bin/clearconnection.sh 2>&- >&-
	}

	retval=$?
	return $retval
}

wanport() {
       local retval=1
       /etc/init.d/wanport reload
       retval=$?
       return $retval
}

bonjour() {
	local retval=1
	uci commit bonjour
	/etc/init.d/bonjour reload
	
	retval=$?
	return $retval
}

dmz() {
	local retval=1
	#uci commit dmz
	/etc/init.d/hardwaredmz reload
	
	retval=$?
	return $retval
}


systemconfig() {
	local retval=1
	/etc/init.d/systemconfig reload
	
	retval=$?
	
	if [ "$?" = 0 ];then
		dhcp
                retval=$?
                if [ $retval -gt 0 ]
                then
			return $retval
		fi	
		
		bonjour
                retval=$?
                if [ $retval -gt 0 ]
                then
			return $retval
		fi	
	else
		return $retval
	fi
	
}
email() {
	local retval=1
	uci commit email
	/etc/init.d/email reload
	
	retval=$?
	return $retval
}

syslog() {
	SYSLOG_NG_VERSION="3.0.8"
        old_value=`uci get /tmp/etc/config/syslog.log_server.enable`
        new_value=`uci get syslog.log_server.enable`
        if [ "$new_value" -eq 0 ];then
                logger -t system -p local0.notice "syslog-ng version:$SYSLOG_NG_VERSION stopped."
        fi

	local retval=1
	uci commit syslog
#	/etc/init.d/syslog reload
	/etc/init.d/syslog restart
	retval=$?

	if [ "$old_value" -ne "$new_value" ] && [ "$new_value" -eq 1 ];then
                logger -t system -p local0.notice "syslog-ng version:$SYSLOG_NG_VERSION started."
        fi
	return $retval
}

system() {
	local retval=1
	uci commit system
	/etc/init.d/system reload
	
	retval=$?
	return $retval
}

testserver() {
	local retval=1
	/usr/bin/testserver

	retval=$?
	return $retval
}

certificate() {
	local retval=1
	local updateCert=1	
	if [ ! -e "/tmp/.uci/certificate" ];then
		echo "no config"
		return $retval
	fi
		
	check_action=`cat /tmp/.uci/certificate | grep "delete_certificate"`
	if [ -n "$check_action" ];then
		/etc/init.d/certificate delete_certificate
		retval=$?
	else
		check_action=`cat /tmp/.uci/certificate | grep "=generated_certificate"`
		if [ -n "$check_action" ];then
			/etc/init.d/certificate generate_certificate
			retval=$?
		else
			check_action=`cat /tmp/.uci/certificate | grep "imported_certificate"`
			if [ -n "$check_action" ];then
				/etc/init.d/certificate import_certificate
				retval=$?
			else
				check_action=`cat /tmp/.uci/certificate | grep "exported_certificate"`
				if [ -n "$check_action" ];then
					/etc/init.d/certificate export_certificate
					retval=$?
					updateCert=0
				fi
			fi
		fi
	fi


	# copy certificate to config partition for success cases
	[ "$retval" = 0 ] && {
		cp -f $TMP_CERT_FILE $MNT_CERT_FILE
		cp -f $TMP_PREINSTALLED_CERT_FILE $MNT_PREINSTALLED_CERT_FILE
	}
	
	# Update the certs opsdb
	#[ "$updateCert" = 1 ] && /usr/bin/certscript

	return $retval
}

schedule() {

	local retval=0
	
	cp /tmp/.uci/schedule /tmp/scheduledeltaconfig
	cp /tmp/.uci/schedule /tmp/scheddeltaconfig
	uci commit schedule	
	# Calling Dependent module function to update the changed schedule configuration
	# <modulescriptname>  <command>  <arg1:subcommand> <arg2:scheduledeltaconfigfilepath>
	/etc/init.d/webfilter sched update /tmp/scheduledeltaconfig
	
	retval=$?
	
	if [ $retval -gt 0 ]
	then
		return $retval
	else
		avc
		retval=$?
		if [ $retval -gt 0 ]
		then
			return $retval
		fi
		
		firewall_sched	
		retval=$?
		if [ $retval -gt 0 ]
		then
			return $retval
		fi
		
		/etc/init.d/schedule reload	
		retval=$?
		if [ $retval -gt 0 ]
		then
			return $retval
		fi
		
		
	fi
	return $retval
}

usrgroup() {
	local retval=0

	cp /tmp/.uci/usrgroup /tmp/usrgroupdeltaconfig
	uci commit usrgroup

	# Resetting all clients group to None, when usrgrp updates as per LIONIC Glen suggestion
	lcstat reset group

	avc
	retval=$?
	if [ $retval -gt 0 ]
	then
		return $retval
	fi
}

ipgroup() {

	local retval=0
	
	cp /tmp/.uci/ipgroup /tmp/ipgroupdeltaconfig
	uci commit ipgroup	
	# Calling Dependent module function to update the changed ipgroup configuration
	# <modulescriptname>  <command>  <arg1:subcommand> <arg2:ipgrpdeltaconfigfilepath>
	/etc/init.d/webfilter   ipgrp     update      /tmp/ipgroupdeltaconfig
	
	retval=$?
	
	if [ $retval -gt 0 ]
	then
		return $retval
	else
		avc	
		retval=$?
		if [ $retval -gt 0 ]
		then
			return $retval
		fi
		
		/etc/init.d/ipgroup reload	
		retval=$?
		if [ $retval -gt 0 ]
		then
			return $retval
		fi
		
		
	fi
	return $retval
}

schedule_run() {

	local retval=0
	local depmod=$@

	cp /tmp/.uci/schedule /tmp/scheduledeltaconfig
	cp /tmp/.uci/schedule /tmp/scheddeltaconfig
	uci commit schedule
	# Calling Dependent module function to update the changed schedule configuration
	# <modulescriptname>  <command>  <arg1:subcommand> <arg2:scheduledeltaconfigfilepath>
	if [ $(echo $depmod | grep webfilter) ];then
		/etc/init.d/webfilter sched update /tmp/scheduledeltaconfig
		retval=$?
	else
		retval=0
	fi


	if [ $retval -gt 0 ]
	then
		return $retval
	else
		if [ $(echo $depmod | grep avc) ];then
			avc
			retval=$?
		else
			retval=0
		fi
		if [ $retval -gt 0 ]
		then
			return $retval
		fi

		if [ $(echo $depmod | grep firewall) ];then
			firewall_sched
			retval=$?
		else
			retval=0
		fi
		if [ $retval -gt 0 ]
		then
			return $retval
		fi

		/etc/init.d/schedule reload
		retval=$?
		if [ $retval -gt 0 ]
		then
			return $retval
		fi


	fi
	return $retval
}

ipgroup_run() {

	local retval=0
	local depmod=$@

	cp /tmp/.uci/ipgroup /tmp/ipgroupdeltaconfig
	uci commit ipgroup
	# Calling Dependent module function to update the changed ipgroup configuration
	# <modulescriptname>  <command>  <arg1:subcommand> <arg2:ipgrpdeltaconfigfilepath>

	if [ $(echo $depmod | grep webfilter) ];then
		/etc/init.d/webfilter   ipgrp     update      /tmp/ipgroupdeltaconfig
		retval=$?
	else
		retval=0
	fi


	if [ $retval -gt 0 ]
	then
		return $retval
	else
		if [ $(echo $depmod | grep avc) ];then
			avc
			retval=$?
		else
			retval=0
		fi

		if [ $retval -gt 0 ]
		then
			return $retval
		fi

		/etc/init.d/ipgroup reload
		retval=$?
		if [ $retval -gt 0 ]
		then
			return $retval
		fi


	fi
	return $retval
}

webfilter() {

	local retval=0
	
	/etc/init.d/webfilter reload
	uci commit webfilter
	
	retval=$?
	return $retval
	
}

webfilter_run() {

	local retval=0

	/etc/init.d/webfilter reload
	uci commit webfilter
	logger -t ucicfg "Completed webfilter module"

	return 0

}

ips() {
	uci commit ips
	/usr/bin/ysmir-config.sh ips
	retval=$?
	return $retval
}

av() {
	uci commit av
	/usr/bin/ysmir-config.sh av
	retval=$?
	return $retval
}

avc() {

	local retval=0

    if [ "$board" = "RV160" -o "$board" = "RV160W" -o "$board" = "RV260" -o "$board" = "RV260P" -o "$board" = "RV260W" ]; then
        return 0
    fi
#all lionic configuration's are present in avc file	
	uci commit avc
	/etc/init.d/avc reload
	
	retval=$?
	return $retval
	
}

mwan3_full_tunnel_config() {
	#This function has to figure out a GRE route addition/deletion event and act appropriately.
	if [ "$board" = "RV260" -o "$board" = "RV260P" -o "$board" = "RV260W" ]; then
		default_route_iface=`cat /tmp/networkconfig | sed s/"'"//g | grep -E "network.route_[0-9]+.target=0.0.0.0" -A 6 | grep "interface=" | sed s/_static// | awk -F '=' '{print $2}'`
		[ -n "$default_route_iface" ] && {
			#This is a default route addition.
			is_gre_default_route=`uci get network.$default_route_iface.proto`
			if [ "$is_gre_default_route" = "gre" ]
			then # GRE default route addition.
			#{
				#If we are inside this, it means that we are dealing with a default route on GRE interface. Set mwan3 module for RV260 device.
				is_already_configured=`uci_get_state mwan3.full_tunnel.tunnel_name`
				if [ "$is_already_configured" = "" ]
				then #Which means it is not configured earlier. Now, is the time to configure.
				#{
					uci set mwan3.$default_route_iface=interface
					uci set mwan3.$default_route_iface.enabled=1
					uci set mwan3.$default_route_iface.log=1
					uci set mwan3."$default_route_iface"_mem=member
					uci set mwan3."$default_route_iface"_mem.interface=$default_route_iface
					uci set mwan3."$default_route_iface"_mem.metric=0
					uci set mwan3."$default_route_iface"_mem.weight=100
					uci set mwan3."$default_route_iface"_only=policy
					uci add_list mwan3."$default_route_iface"_only.use_member="$default_route_iface"_mem
					uci set mwan3.default_gre=rule
					uci set mwan3.default_gre.dest_ip=0.0.0.0/0
					uci set mwan3.default_gre.use_policy="$default_route_iface"_only

					uci_toggle_state mwan3 full_tunnel tunnel_name "$default_route_iface"
					mwan3

					logger -t mwan3 "Configuring mwan3 for Full tunnel over GRE interface $default_route_iface."
					return 0
				#}
				fi
			#}
			fi

		}

		del_route=`grep -E "\-network.route_[0-9]+$" /tmp/networkconfig`
		[ -n "$del_route" ] && {
			#A route deletion case.
			#Check if a default route on GRE is already added. Only then we need to act further, else leave it.
			is_already_configured=`uci_get_state mwan3.full_tunnel.tunnel_name`
			if [ "$is_already_configured" != "" ]
			then
			#{
				#There is a default route on GRE added earlier. So figure out if the same route is deleted.
				#	If the same route is deleted then we may need to deconfigure the route from mwan3.
				find=0
				local get_iface
				all_default_routes=`uci show network | grep -E "network.route_[0-9]+.target=0.0.0.0" | awk -F '.' '{print $2}'`
				if [ "$all_default_routes" != "" ] 
				then
				#{
					for section in $all_default_routes
					do
						get_iface=`uci get network.$section.interface | sed s/_static//`
						if [ "gre_$get_iface" = "gre_$is_already_configured" ]
						then
						#Your default route on GRE is not deleted.
							find=1
						fi
					done
				#}
				else
					#No default route after some deletions. So, even our route of interest also got deleted.
					get_iface="$is_already_configured"
				fi
				if [ $find -eq 0 ]
				then
				#{
				#your route is the one which is deleted. Hence deconfigure in mwan3.
					uci delete mwan3.$get_iface
					uci delete mwan3."$get_iface"_mem
					uci delete mwan3."$get_iface"_only
					uci delete mwan3.default_gre

					uci_toggle_state mwan3 full_tunnel tunnel_name ""
					mwan3

					logger -t mwan3 "Deleted Full tunnel over GRE interface $get_iface from mwan3 module."
					return 0
				#}
				fi
			#}
			fi
		}
	fi
}

network_onboot() {
	/etc/init.d/abootpattern1 boot

	/etc/init.d/wanport start_setstatus
	local retval=0

        ifaces=$(cat /tmp/networkconfig | sed s/"'"//g | grep "=interface" | cut -f 2 -d . | cut -f 1 -d = )
        for if in $ifaces
        do
		enabled=`uci get network.$if.enable` 2>&- >&-
                mtu_p=`uci get /tmp/etc/config/network.$if.mtu` 2>&- >&-
                mtu_n=`uci get network.$if.mtu` 2>&- >&-
                [ -n "$mtu_p" ] && [ "$(cat /tmp/networkconfig  | grep "network.$if.mtu")" = "" ] && {
	                if [ "$enabled" != 0 ];then
				echo "network.$if.mtunew=1500" >>/tmp/networkconfig
                        fi
                }
                #logger -t testing "############# prev mtu $mtu_p new mtu $mtu_n"
                if [ "$mtu_p" = "$mtu_n" ]; then
			cat /tmp/networkconfig  | grep -v "network.$if.mtu" >/tmp/networkconfig1
                fi
                cp /tmp/networkconfig1 /tmp/networkconfig

                mac_p=`uci get /tmp/etc/config/network.$if.macaddr` 2>&- >&-
                mac_n=`uci get network.$if.macaddr` 2>&- >&-
                [ -n "$mac_p" ] && [ "$(cat /tmp/networkconfig  | grep "network.$if.macaddr")" = "" ] && {
                        [ -n "$(echo $if | grep wan1)" ] && {
                                macwan=$(uci get systeminfo.sysinfo.macwan1)
                        }

                        [ -n "$(echo $if | grep wan2)" ] && {
                                macwan=$(uci get systeminfo.sysinfo.macwan2)
                        }

	                if [ "$enabled" != 0 ];then
	                        echo "network.$if.macaddrnew=$macwan" >>/tmp/networkconfig
	                fi
                }
                if [ "$mac_p" = "$mac_n" ]; then
                        cat /tmp/networkconfig  | grep -v "network.$if.macaddr" >/tmp/networkconfig1
                fi
                cp /tmp/networkconfig1 /tmp/networkconfig

        done
        rm /tmp/networkconfig1 >/dev/null 2>&1

	/sbin/mtu-mac-enable reload "gui" &

	/etc/init.d/network reload
	/etc/init.d/wanport start_setwanport
	mwan3_full_tunnel_config

	rm /tmp/networkconfig >/dev/null 2>&1
	retval=$?
}

network() {

	local retval=0

	cp /tmp/etc/config/network /tmp/etc/config/network-bkp
	cp /tmp/.uci/network /tmp/networkconfig	

	isvlan=$(grep "network.vlan" /tmp/networkconfig)
        ifaces=$(cat /tmp/networkconfig | sed s/"'"//g | grep "=interface" | cut -f 2 -d . | cut -f 1 -d = )
        for if in $ifaces
        do
		enabled=`uci get network.$if.enable` 2>&- >&-
                mtu_p=`uci get /tmp/etc/config/network.$if.mtu` 2>&- >&-
                mtu_n=`uci get network.$if.mtu` 2>&- >&-
                [ -n "$mtu_p" ] && [ "$(cat /tmp/networkconfig  | grep "network.$if.mtu")" = "" ] && {
	                if [ "$enabled" != 0 ];then
                        	echo "network.$if.mtunew=1500" >>/tmp/networkconfig
                        fi
                }
                #logger -t testing "############# prev mtu $mtu_p new mtu $mtu_n"
                if [ "$mtu_p" = "$mtu_n" ]; then
                        cat /tmp/networkconfig  | grep -v "network.$if.mtu" >/tmp/networkconfig1
                cp /tmp/networkconfig1 /tmp/networkconfig
                fi

                mac_p=`uci get /tmp/etc/config/network.$if.macaddr` 2>&- >&-
                mac_n=`uci get network.$if.macaddr` 2>&- >&-
                [ -n "$mac_p" ] && [ "$(cat /tmp/networkconfig  | grep "network.$if.macaddr")" = "" ] && {
                        [ -n "$(echo $if | grep wan1)" ] && {
                                macwan=$(uci get systeminfo.sysinfo.macwan1)
                        }

                        [ -n "$(echo $if | grep wan2)" ] && {
                                macwan=$(uci get systeminfo.sysinfo.macwan2)
                        }

	                if [ "$enabled" != 0 ];then
	                        echo "network.$if.macaddrnew=$macwan" >>/tmp/networkconfig
	                fi
                }
                if [ "$mac_p" = "$mac_n" ]; then
                        cat /tmp/networkconfig  | grep -v "network.$if.macaddr" >/tmp/networkconfig1
                cp /tmp/networkconfig1 /tmp/networkconfig
                fi

        done
        rm /tmp/networkconfig1

	/sbin/mtu-mac-enable reload "gui" &
	
	/etc/init.d/network reload
	
	retval=$?
	
	if [ $retval -gt 0 ]
	then
		return $retval
	else
		[ -n "$isvlan" ] && {
			dhcp
			retval=$?
			if [ $retval -gt 0 ]
			then
				return $retval
			fi
		
			bonjour
			retval=$?
			if [ $retval -gt 0 ]
			then
				return $retval
			fi
		}
	fi
	/sbin/netifd-sync reload &

	# Run the wanscript to get updated data
        /usr/bin/wanscript
        /usr/bin/sendOpsdbSignal.sh SIGHUP

	bwmgmt
	mwan3_full_tunnel_config
	
	rm /tmp/networkconfig
	return $retval
}

firewall_sched() {

	local retval=0 
	/etc/init.d/firewall firewall_sched_reload
	retval=$?
	return $retval
}

firewall() {
	local retval
	#uci commit firewall moved to firewallstart function.	
	/etc/init.d/firewall reload
	/etc/init.d/nginx reload
	retval=$?

	if [ $retval -gt 0 ]
	then
		return $retval
	else

		bonjour
		retval=$?
		if [ $retval -gt 0 ]
		then
			return $retval
		fi
	fi
	return $retval


}

upnpd() {
	local retval
    uci commit upnpd	
    /etc/init.d/miniupnpd reload
    retval=$?
    return $retval
}
radius() {
    local retval
    local pid
    uci commit radius
	/etc/init.d/radius reload
    [ -x "/usr/bin/rtdot1xd" ] && {
       pid=$(pgrep rtdot1xd)
       if [ -n "$pid" ]; then
          `kill -SIGUSR1 $pid`
       fi
    }
    retval=$?
    if [ $retval -gt 0 ];
    then
       return $retval
    fi

    # calling aaa, to reflect radius retry/timeout settings in appropriate service file /etc/pam.d/<service>
    aaa
    retval=$?
    return $retval
}

ldap() {
    local retval
    uci commit ldap
    /etc/init.d/ldapclient reload
    retval=$?
    return $retval
}   

bwmgmt() {
    local retval
    uci commit bwmgmt
    /etc/init.d/bwmgmt reload
    retval=$?
    return $retval
}   

ad() {
   local retval
   uci commit ad
   /etc/init.d/ad reload
   retval=$?
   return $retval
}   

strongswan() {
	local retval

	if [ "$ru_check" = "RU" ]; then
		return 0
	fi

	/etc/init.d/strongswan reload
	retval=$?
	return $retval
}

pptpd() {
	local retval

	if [ "$ru_check" = "RU" ]; then
		return 0
	fi

	uci commit pptpd
	/etc/init.d/pptpd reload
	retval=$?
	return $retval
}

l2tpd() {
	local retval

	if [ "$ru_check" = "RU" ]; then
		return 0
	fi

	uci commit l2tpd
	/etc/init.d/l2tpd reload

	retval=$?

	if [ $retval -gt 0 ]
	then
		return $retval
	else
		strongswan
		retval=$?
		if [ $retval -gt 0 ]
		then
			return $retval
		fi
	fi
	return $retval
}

vpnpassthrough() {
	local retval

	if [ "$ru_check" = "RU" ]; then
		return 0
	fi

	uci commit vpnpassthrough
	/etc/init.d/vpnpassthrough reload
	retval=$?
	return $retval
}

vpnresourcemgmt() {
	local retval

	/etc/init.d/vpnresourcemgmt reload
	retval=$?
	return $retval
}

lldpd() {
	local retval

	uci commit lldpd
	/etc/init.d/lldpd restart
	retval=$?
	return $retval
}

umbrella () {
	local retval

	#uci commit umbrella
	/etc/init.d/umbrella reload
	retval=$?
	# Run the wanscript to get updated data
	/usr/bin/wanscript &
	return $retval
}

ddns() {
	local retval
	
	cp /tmp/.uci/ddns /tmp/ddns
	uci commit ddns
   	/etc/init.d/ddns reload

     
	retval=$?
	return $retval
}

rip() {
	local retval
	
   	/etc/init.d/rip reload

     
	retval=$?
	return $retval
}

qos() {
	local retval
	
   	/etc/init.d/qos reload

     
	retval=$?
	return $retval
}


mwan3() {
	local retval

	sed -i s/"'"//g /tmp/.uci/mwan3

	uci_data=$(cat /tmp/.uci/mwan3)
	isRuleAdd=$(echo $uci_data | grep -E "mwan3.*=rule")
	isRuleDel=$(echo $uci_data | grep -E "\-mwan3\.rule[0-9]+")

	isInterfaceAdd=$(echo $uci_data | grep -E "mwan3.*=interface")
	isInterfaceDel=$(echo $uci_data | grep -E "\-mwan3.wan*|\-mwan3.usb*")

	isMemberAdd=$(echo $uci_data | grep -E "mwan3.*=member")
	isMemberDel=$(echo $uci_data | grep -E "\-mwan3.wan*|\-mwan3.usb*")

	uci reorder mwan3.default_rule=2000 2>&- >&-
	uci commit mwan3

	if [ "$isRuleAdd" != "" -o "$isRuleDel" != "" ]
	then
		/usr/sbin/mwan3 mwan3_set_policy_rules
		logger -t mwan3 -p info "Multi-Wan policy based rules updated!"
	fi

	if [ "$isInterfaceAdd" != "" -o "$isInterfaceDel" != "" -o "$isMemberAdd" != "" -o "$isMemberDel" != "" ]
	then
		/etc/init.d/mwan3 reload &
	fi
	return 0
}

igmpproxy() {
	local retval

	uci commit igmpproxy

	/etc/init.d/mcproxy reload

	retval=$?
	return $retval
}

sslvpn() {
	local retval=1

	uci commit sslvpn
	uci show sslvpn > /tmp/1.log
	/etc/init.d/sslvpn reload

	retval=$?
	if [ $retval -gt 0 ]
	then
		return $retval
	else
		firewall_dmz
		retval=$?
		if [ $retval -gt 0 ]
		then
			return $retval
		fi
	fi
	return $retval
}

firewall_dmz(){
	local retval=0
	/etc/init.d/firewall firewall_dmz_reload
	retval=$?
	return $retval
}

wireless() {
	local retval

	uci set wireless.wl0.type="broadcom"
	uci set wireless.wl1.type="broadcom"

	uci commit wireless

	if [ "$board" = "RV340W" ] || [ "$board" = "RV160W" ] || [ "$board" = "RV260W" ] ;then
		if [ "$(nvram get wps_reload_lock)" != "1" ]; then
			if [ -e /tmp/etc/config/wireless_old ];then
				/sbin/wifi reload_part >/dev/null 2>&1
			else
				/sbin/wifi down >/dev/null 2>&1
				/sbin/wifi up >/dev/null 2>&1
			fi
		else
			nvram set wps_reload_lock=0 >/dev/null 2>&1
		fi
 	fi
	
	/etc/init.d/nginx reload
	retval=$?

	[ -e /mnt/initial_setup_done ] && {
		count=$(cat /mnt/configcert/b_count)
		if [ $count == 1 ]; then
			ssid=$(uci get wireless.@wifi-iface[0].ssid)
			if [ "$ssid" != "CiscoSB-Setup" ]; then
				sh /usr/bin/initial_ssid_flush_rules.sh
				echo 2 > /mnt/configcert/b_count
			fi
		fi
	}

	return $retval
}

lobby() {
	local retval

	uci commit lobby

	killall -18 cportald

	retval=$?

	return $retval
}

coovachilli() {
	local retval

	uci commit coovachilli

	if [ "$board" = "RV340W" ];then
		if [ -e /var/run/captive.pid ];then
		/etc/init.d/captive_portal reload >/dev/null 2>&1 &
		fi
    fi

	retval=$?

    return $retval
}

license() {
	local retval=1
	/etc/init.d/license reload

	retval=$?
	return $retval
}

pnp() {
        local retval
        local pnp_current_config
        local pnp_new_config
        pnp_current_config=`uci get /tmp/etc/config/pnp.general.enabled`

        uci commit pnp

        pnp_new_config=`uci get pnp.general.enabled`

        if [ "$pnp_new_config" = "0" ];then
                if [ "$pnp_current_config" = "1" ];then
                        /etc/init.d/pnpd stop
                fi
        fi

        if [ "$pnp_new_config" = "1" ];then
                create_pnp_config
                if [ "$pnp_current_config" = "1" ];then
                        /etc/init.d/pnpd restart
                else
                        /etc/init.d/pnpd start
                fi
        fi
        retval=$?
        return $retval
}


schedule_reboot()
{
	uci commit recurring-schedule-reboot
	/etc/init.d/schedule_reboot reload
	retval=$?
	return $retval
}

update_pc2run() {

	local modules
	local main_mod
	modules=$@
	if [ -n "$(echo $modules | grep "network")" ];then
		modules=$(echo $modules | sed s/"dhcp"/""/ | sed s/"bonjour"/""/ | sed s/"bwmgmt"//)
	fi

	if [ -n "$(echo $modules | grep "systemconfig")" ];then
		modules=$(echo $modules | sed s/"dhcp"/""/ | sed s/"bonjour"/""/)
	fi

	if [ -n "$(echo $modules | grep "firewall")" ];then
		modules=$(echo $modules | sed s/"bonjour"/""/)
	fi

	if [ -n "$(echo $modules | grep "switch")" ];then
		modules=$(echo $modules | sed s/"qos_switch"/""/)
	fi

	if [ -n "$(echo $modules | grep ipgroup)" ];then
		modules=$(echo $modules | sed s/ipgroup//)
		modules="ipgroup $modules"
	fi
	if [ -n "$(echo $modules | grep schedule)" ];then
		modules=$(echo $modules | sed s/schedule//)
		modules="schedule $modules"
	fi
	if [ -n "$(echo $modules | grep network)" ];then
		modules=$(echo $modules | sed s/network//)
		modules="network $modules"
	fi

	logger -t ucicfg "Final modules are $modules"

	for main_mod in $modules
	do
		logger -t ucicfg "Reloading $main_mod ..."
		case $main_mod in
			schedule)
				schedule_run $modules
			;;
			ipgroup)
				ipgroup_run $modules
			;;
			webfilter)
				webfilter_run
			;;
			qos)
				uci commit qos
				/etc/init.d/qos restart
			;;
			*)
				$main_mod
			;;
		esac
	done
}

local cfg="$1"
local retval
if [ $# -eq 1 ]
then
	logger -t ucicfg "Reloading $cfg ..."
	case "$cfg" in
		dhcp)
			dhcp
			exit $?
		;;
		usrgroup)
			usrgroup
			exit $?
		;;
		network)
			network
			exit $?
		;;
		network_onboot)
			network_onboot
			exit $?
		;;
		ddns)
			ddns
			exit $?
		;;
		rip)
			rip
			exit $?
		;;
		qos)
			qos
			exit $?
		;;
		dmz)
			dmz
			exit $?
		;;
		qos_switch)
			switch
			exit $?
		;;
		switch)
			switch
			exit $?
		;;
		wanport)
			wanport
			exit $?
		;;
		firewall)
			firewall
			exit $?
		;;
		mwan3)
			mwan3
			exit $?
		;;
		igmpproxy)
			igmpproxy
			exit $?
		;;
		radvd)
			radvd
			exit $?
		;;
		upnpd)
			upnpd
			exit $?
		;;
		bonjour)
			bonjour
			exit $?
		;;
		certificate)
			certificate
			exit $?
		;;
		testserver)
			testserver
			exit $?
		;;
		email)
			email
			exit $?
		;;
		webfilter)
			webfilter
			exit $?
		;;
		avc)
			avc
			exit $?
		;;
		ips)
			ips
			exit $?
		;;
		av)
			av
			exit $?
		;;
		systemconfig)
			systemconfig
			exit $?
		;;
		swupdate)
			swupdate
			exit $?
		;;
		snmpconf)
			snmpconf
			exit $?
		;;
		poeconf)
			poeconf
			exit $?
		;;
		schedule)
			schedule
			exit $?
		;;
		ipgroup)
			ipgroup
			exit $?
		;;
		strongswan)
			strongswan
			exit $?
		;;
		pptpd)
			pptpd
			exit $?
		;;
		l2tpd)
			l2tpd
			exit $?
		;;
		vpnpassthrough)
			vpnpassthrough
			exit $?
		;;
		vpnresourcemgmt)
			vpnresourcemgmt
			exit $?
		;;
		syslog)
			syslog
			exit $?
		;;
		system)
			system
			exit $?
		;;
		lldpd)
			lldpd
			exit $?
		;;
		sslvpn)
			sslvpn
			exit $?
		;;
		radius)
			radius
			exit $?
		;;
		ldap)
			ldap
			exit $?
		;;
		bwmgmt)
			bwmgmt
			exit $?
		;;
		ad)
			ad
			exit $?
		;;
		wireless)
			wireless
			exit $?
		;;
		update_pc2run)
			update_pc2run $@
			exit $?
		;;
		coovachilli)
			coovachilli
			exit $?
		;;
		lobby)
			lobby
			exit $?
		;;
		pnp)
			pnp
			exit $?
		;;
		aaa)
			aaa
			exit $?
		;;
		license)
			license
			exit $?
		;;
		umbrella)
			umbrella
			exit $?
		;;
		recurring-schedule-reboot)
			schedule_reboot
			exit $?
		;;
		*)
			logger -t ucicfg "FIXME:Unhandled module $cfg ..."
			exit 0
		;;
	esac
else
	logger -t ucicfg "Reloading config_update.sh with args:$@"
	update_pc2run $@
	exit 0
fi
