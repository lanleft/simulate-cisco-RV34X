#!/bin/sh
. /lib/functions/network.sh
. /lib/config/uci.sh
. /lib/functions.sh

# We are maintaining following sequece. Same is required in ifstat.c, so order is important.
# For v4 -> "v4,IFACE,IP,GW,DNS1,DNS2,MASK,DDNS_STATUS,DDNS_DETAIL,DDNS_REG_TIME,mac_addres,ifindex"
# For v6 -> "v6,IFACE,IP,GW,DNS1,DNS2,MASK,DHCP_PD_PREFIX,mac_address,ifindex"

TMP_OUTPUT="/tmp/tmpifstats"
IF_OUTFILE_FINAL="/tmp/stats/snmp_iface_stats"
IF_OUTFILE="/tmp/stats/ifstats.tmp"
IF_OUTFILE_TMP1="/tmp/stats/ifstats.tmp1"
IF_OUTFILESTATUS="/tmp/stats/ifstats_status"
LOCKWANSCRIPT="/tmp/.ifscriptLock"
STATUSFILE="/tmp/stats/ifstatscomplete"
phyIfStats="/tmp/phyIfStats"

rm -f $TMP_OUTPUT $IF_OUTFILE $IF_OUTFILE_TMP1 $IF_OUTFILESTATUS $STATUSFILE $IF_OUTFILE_FINAL

getifindex() {
    local name=$1
    local procpath="/proc/net/dev_snmp6"
    name=$(printf $name | awk '{print tolower($0)}')
    name=$(echo $name | sed 's/\./_/g')
    config_get ifname "$name" ifname
    if [ -f "$procpath/$ifname" ]; then
        ifindex=$(cat $procpath/$ifname | grep ifIndex | awk -F' ' '{ print $2 }')
        #echo "name=$name ifindex=$ifindex"
        echo "$ifindex"
    else
        echo "not_valid"
    fi
}

getIfaceCounters() {

	    local name=$1
    	name=$(printf $name | awk '{print tolower($0)}' | sed  's/\./_/g')
        phy_ifname=`uci get network.$name.ifname` >/dev/null 2>&1

        if_linkstatus=0
        if_portactivity=0
        if_speedstatus=0
        if_dupstatus=0
        if_autoneg=0
        if_lldp_status=0
    	if_in_broadcast_pkts=0
	    if_out_broadcast_pkts=0
	    if_out_multicast_pkts=0
        if_in_error=`cat /sys/class/net/$phy_ifname/statistics/rx_errors` >/dev/null 2>&1
        if_out_error=`cat /sys/class/net/$phy_ifname/statistics/tx_errors` >/dev/null 2>&1
        if_in_unicast_pkts=`cat /sys/class/net/$phy_ifname/statistics/rx_packets` >/dev/null 2>&1
        #if_in_broadcast_pkts=`cat /sys/class/net/$phy_ifname/statistics/multicast` >/dev/null 2>&1
        if_in_multicast_pkts=`cat /sys/class/net/$phy_ifname/statistics/multicast` >/dev/null 2>&1
        if_in_octets=`cat /sys/class/net/$phy_ifname/statistics/rx_bytes` >/dev/null 2>&1
        if_out_unicast_pkts=`cat /sys/class/net/$phy_ifname/statistics/tx_packets` >/dev/null 2>&1
        #if_out_broadcast_pkts=0
        #if_out_multicast_pkts=`cat /sys/class/net/$phy_ifname/statistics/multicast` >/dev/null 2>&1
        if_out_octets=`cat /sys/class/net/$phy_ifname/statistics/tx_bytes` >/dev/null 2>&1

        if [ "$oper" = "wan1" ]; then
                portactivity=`uci get wanport.wan1.status` >/dev/null 2>&1
                if_speedstatus=$(cat /sys/class/net/${phy_ifname}/speed) >/dev/null 2>&1
                if_lldp_status=`uci get lldpd.config.wan1` >/dev/null 2>&1
        elif [ "$oper" = "wan2" ]; then
                portactivity=`uci get wanport.wan2.status` >/dev/null 2>&1
                if_speedstatus=$(cat /sys/class/net/${phy_ifname}/speed) >/dev/null 2>&1
                if_lldp_status=`uci get lldpd.config.wan2` >/dev/null 2>&1
        fi

        IFCONFIG="/sbin/ifconfig ${phy_ifname}"
        status=`$IFCONFIG | grep "UP" | wc -l`;

        if test $status -gt 0;
        then
                admin_status=1;
                portactivity=1;
        else
                admin_status=2;
                portactivity=2;
        fi

	op_state=$(cat /sys/class/net/${phy_ifname}/operstate) >/dev/null 2>&1
        if [ "$op_state" = "up" ]; then
                oper_status=1;
        elif [ "$op_state" = "down" ]; then
                oper_status=2;
        elif [ "$op_state" = "testing" ]; then
                oper_status=3;
        elif [ "$op_state" = "unknown" ]; then
                oper_status=4;
        elif [ "$op_state" = "dormant" ]; then
                oper_status=5;
        elif [ "$op_state" = "not-present" ]; then
                oper_status=6;
        elif [ "$op_state" = "lowerlayerdown" ]; then
                oper_status=7;
        fi
        index=$(cat /sys/class/net/${phy_ifname}/ifindex) >/dev/null 2>&1
        if_linkstatus=$(cat /sys/class/net/${phy_ifname}/carrier) >/dev/null 2>&1
        if_speedstatus=$(cat /sys/class/net/${phy_ifname}/speed) >/dev/null 2>&1
        if [ -z "$if_speedstatus" ] && [ "$if_linkstatus" = 1 ]; then
                if_speedstatus=1000
                if_autoneg=1
                if_lldp_status=1
        fi
        ethtool_out=$(ethtool $phy_ifname) >/dev/null 2>&1

        case $ethtool_out in
                *"Duplex: Full"*)
                        if_dupstatus=1
                ;;

        esac
        case $ethtool_out in
                *"Auto-negotiation: on"*)
                        if_autoneg=1
                ;;
        esac

        case $portactivity in
                1)
                        if_portactivity=0
                ;;
                0)
                        if_portactivity=1
                        if_linkstatus=2
                ;;
        esac

	if [ -n "$phy_ifname" ]; then
		`ethtool -S ${phy_ifname} > $phyIfStats >/dev/null 2>&1`
		errcode=$?
        	if [ "$errcode" = 0 ]; then
			    if_in_broadcast_pkts=`awk '/rx- broadcast:/{print $NF}' $phyIfStats`
			    if_out_broadcast_pkts=`awk '/tx- broadcast:/{print $NF}' $phyIfStats`
			    if_out_multicast_pkts=`awk '/tx- multicast:/{print $NF}' $phyIfStats`
        	fi
	fi

        echo "$if_linkstatus,$if_portactivity,$if_speedstatus,$if_dupstatus,$if_autoneg,$if_in_unicast_pkts,$if_in_broadcast_pkts,$if_in_multicast_pkts,$if_in_octets,$if_in_error,$if_out_unicast_pkts,$if_out_broadcast_pkts,$if_out_multicast_pkts,$if_out_octets,$if_out_error,$if_lldp_status,$admin_status,$oper_status,"
}



# Check signal and delete the lock
wanScriptSigHand () {
	logger -t system "Signal Received. Killing self"
	rm -rf $IF_OUTFILE_TMP1
	echo "1" > $IF_OUTFILESTATUS
	lock -u $LOCKWANSCRIPT
	exit 0
}

trap wanScriptSigHand SIGINT SIGHUP SIGTERM SIGSEGV SIGQUIT

while [ 1 ]
do
	lock $LOCKWANSCRIPT
	temp=`cat $IF_OUTFILESTATUS` >/dev/null 2>&1
	if [ "$temp" == "1" ] || [ -z "$temp" ]
	then
		echo "0" > $IF_OUTFILESTATUS
		lock -u $LOCKWANSCRIPT
		break
	else
		lock -u $LOCKWANSCRIPT
		sleep 1
		let count++
		if [ $count -eq 60 ]
		then
			exit 0
		fi
		continue
	fi
done

config_load network

ubus list network.interface.* | awk -F "." '!/loopback|usb|^gre/ {print $3}' > $TMP_OUTPUT

usb1proto=`uci get network.usb1.proto`>/dev/null 2>&1
usb2proto=`uci get network.usb2.proto`>/dev/null 2>&1

case $usb1proto in
	3g)
		echo "usb1" >> $TMP_OUTPUT
	;;
	qmi)
		echo "usb1_4" >> $TMP_OUTPUT
	;;
	mobile)
		detect=$(cat /var/USBCONNSTATUS 2>/dev/null | grep -i USB1 | awk -F: '{printf $4}')
		if [ "$detect" = "4G" ]; then
			echo "usb1_4" >> $TMP_OUTPUT
		else
			echo "usb1" >> $TMP_OUTPUT
		fi
	;;
esac

case $usb2proto in
	3g)
		echo "usb2" >> $TMP_OUTPUT
	;;
	qmi)
		echo "usb2_4" >> $TMP_OUTPUT
	;;
	mobile)
		detect=$(cat /var/USBCONNSTATUS 2>/dev/null | grep -i USB2 | awk -F: '{printf $4}')
		if [ "$detect" = "4G" ]; then
			echo "usb2_4" >> $TMP_OUTPUT
		else
			echo "usb2" >> $TMP_OUTPUT
		fi
	;;
esac

rm -rf $IF_OUTFILE
touch $IF_OUTFILE

while read -r oper
do
	case "$oper" in
		vlan*)
		ifstatus=
		ip=
		mask4=
		v4_phy_l2=
		v4_phy_l3=
		dns14=
		dns16=
		gw=
		mac_addr=
		ip4_count=0
		__network_getall_stats_v4 $oper ifstatus ip mask4 v4_phy_l2 v4_phy_l3 dns14 dns16 gw

		mac_addr=`cat /sys/class/net/$v4_phy_l2/address` >/dev/null 2>&1
		[ -n "$ip" ] && ip4_count=1

		ifstatus6=
		ip6=
		mask6=
		v6_phy_l2=
		v6_phy_l3=
		dns16=
		dns26=
		gw6=
		ip6_count=0
		dhcp_pd_prefix=

		__network_getall_stats_v6 $oper ifstatus6 v6_phy_l2 v6_phy_l3 dns16 dns26 gw6
		network_get_prefix6 dhcp_pd_prefix $oper

		# Get ipv6 ips and count. Using l2 device as we dont have pppoe over lan side 
		[ -n "$v6_phy_l2" ] && {
			ip6=$(ifconfig $v6_phy_l2 | grep "inet6 addr" | cut -f 13 -d ' ') 2>&- >&-
			ip6_count=$(echo $ip6 | wc -w)
			[ "$ip6_count" = "0" ] || ip6=$(echo $ip6 | sed s/'\/'/' '/g)
		}

		iface_counters=`getIfaceCounters $oper`
                oper=$(echo $oper | awk '{print toupper($0)}') 

		ifindex=`getifindex $oper`
		if [ "$ifindex" = "not_valid" ];then
		    index=$((index+1))
                    echo v4,$oper,$ip4_count,$ip $mask4,$gw,$dns14,$dns16,0,,,$mac_addr,$index,$iface_counters >> $IF_OUTFILE
		    index=$((index+1))
                    echo v6,$oper,$ip6_count,$ip6,$gw6,$dns16,$dns26,$dhcp_pd_prefix,$mac_addr,$index, >> $IF_OUTFILE
		else
                    echo v4,$oper,$ip4_count,$ip $mask4,$gw,$dns14,$dns16,0,,,$mac_addr,$ifindex,$iface_counters >> $IF_OUTFILE
                    echo v6,$oper,$ip6_count,$ip6,$gw6,$dns16,$dns26,$dhcp_pd_prefix,$mac_addr,$ifindex, >> $IF_OUTFILE
		fi
		;;

		wan16* | wan26* | wan1_tun1 | wan2_tun1 | wan1_tun2 | wan2_tun2 | *_PD)
		ifstatus6=
		ip6=
		mask6=
		v6_phy_l2=
		v6_phy_l3=
		final_device=
		dns16=
		dns26=
		gw6=
		ip6_count=0
		dhcp_pd_prefix=
		mac_addr=

		[ `echo $oper |grep "wan16\|wan26"` ] && {
                        oper_tmp=`echo $oper | grep "6" | sed 's/6/p/g'`
                        config_get ip6_enable $oper_tmp ipv6
                        if [ "$ip6_enable" = "1" ];then
                                ppoe_wan6=1
                                oper=$oper_tmp
                        fi
                }

		__network_getall_stats_v6 $oper ifstatus6 v6_phy_l2 v6_phy_l3 dns16 dns26 gw6 dhcp_pd_prefix
		network_get_prefix6 dhcp_pd_prefix $oper

		mac_addr=`cat /sys/class/net/$v6_phy_l2/address` >/dev/null 2>&1

		# Get ipv6 ips and count. Use l3 device for pppoe and tun interface , else use l2 device.
		final_device="$v6_phy_l3"
		[ -z "$final_device" ] && {
			[ `echo $oper | grep -v "p\|tun"` ] && {
				final_device="$v6_phy_l2"
			}
		}

		[ -n "$final_device" ] && {
			ip6=$(ifconfig $final_device | grep "inet6 addr" | cut -f 13 -d ' ') 2>&- >&-
			ip6_count=$(echo $ip6 | wc -w)
			[ "$ip6_count" = "0" ] || ip6=$(echo $ip6 | sed s/'\/'/' '/g)
			if [ -n "$(echo $final_device | grep ppoe-)" ];then
				gw6=$(ip -6 route show | grep default | grep $final_device | awk -F ' ' '{print $3}')
			fi
		}

		if [ `echo $oper | grep -E "_PD$"` ];then
			oper=$oper
		elif [ `echo $oper | grep -E "_tun1|_tun2"` ];then
			oper=$(echo $oper | sed 's/\_/-/g' | awk '{print toupper($0)}')
		else
			new="$(echo $oper | grep "6p\?_" | sed 's/6p\_/-pppoe./g' | sed 's/6\_/./g' | awk '{print toupper($0)}')"
			if [ -z "$new" ]; then
				if [ "$ppoe_wan6" == "1" ];then
                    new="$(echo $oper | grep "p\?" | sed 's/p/-pppoe/g' | sed 's/6//g' | awk '{print toupper($0)}')"
                    oper=$new
                else
					new="$(echo $oper | grep "6p\?" | sed 's/6p/-pppoe/g' | sed 's/6//g' | awk '{print toupper($0)}')"
					oper=$new
				fi
			else
				oper=$new
			fi
		fi
		ifindex=`getifindex $oper`
		if [ "$ifindex" = "not_valid" ];then
		    index=$((index+1))
                    echo v6,$oper,$ip6_count,$ip6,$gw6,$dns16,$dns26,$dhcp_pd_prefix,$mac_addr,$index, >> $IF_OUTFILE
                else
                    echo v6,$oper,$ip6_count,$ip6,$gw6,$dns16,$dns26,$dhcp_pd_prefix,$mac_addr,$ifindex, >> $IF_OUTFILE
                fi
		;;

		*)
		ifstatus=
		ip=
		mask4=
		v4_phy_l2=
		v4_phy_l3=
		dns14=
		dns16=
		gw=
		mac_addr=
		ip4_count=0
		ddns_status=
		ddns_details=
		ddns_time=
		iface_type=
		ddns_interface=$oper

		__network_getall_stats_v4 $oper ifstatus ip mask4 v4_phy_l2 v4_phy_l3 dns14 dns16 gw

		mac_addr=`cat /sys/class/net/$v4_phy_l2/address`  >/dev/null 2>&1
		[ -n "$ip" ] && ip4_count=1

		usb_conn=`echo $oper | grep "usb"`
		if [ -n "$usb_conn" ];then
			oper="$(echo $oper | cut -d _ -f 1)"
			ddns_interface=$oper
			oper="$(echo $oper | awk '{print toupper($0)}')"
		else
			config_get proto $oper proto
			config_get iface_type "$oper" type ""
			new="$(echo $oper | grep "p\?_" | sed 's/p\_/-'"$proto"'./g' | sed 's/\_/./g' | awk '{print toupper($0)}')"
			if [ -z "$new" ]; then
				new="$(echo $oper | grep "p\?" | sed 's/p/-'"$proto"'/g' |  awk '{print toupper($0)}')"
				oper=$new
			else
				oper=$new
			fi
		fi

		# Check for bridge interfaces
		[ "$iface_type" = "bridge" ] && {
			oper=`echo $oper | sed s/WAN[1-9]*/\&-BRIDGE/g`
		}
		if [ -f "/var/log/ddns.$ddns_interface.logs" ];then
			ddns_tmp=`cat /var/log/ddns.$ddns_interface.logs | grep "time is"`
			if [ -n "$ddns_tmp" ];then
				# registered
				ddns_status=0
				ddns_details="Succesfully Registered"
				ddns_time=`cat /var/log/ddns.$ddns_interface.logs | grep "time is" | cut -d : -f 3-`

				# write to proper format
				if [ -n "$ddns_time" ];then
					year=`echo $ddns_time | cut -d " " -f 6`
					month=`echo $ddns_time | cut -d " " -f 2`
					case "$month" in
						Jan) month=01 ;;
                               			Feb) month=02 ;;
                               			Mar) month=03 ;;
                               			Apr) month=04 ;;
                               			May) month=05 ;;
                               			Jun) month=06 ;;
                               			Jul) month=07 ;;
                               			Aug) month=08 ;;
                               			Sep) month=09 ;;
                               			Oct) month=10 ;;
                               			Nov) month=11 ;;
                                		Dec) month=12 ;;
					esac
					day=`echo $ddns_time | cut -d " " -f 3`
					time=`echo $ddns_time | cut -d " " -f 4`
					ddns_time=$year:$month:$day:$time
				else
					ddns_time="-"
				fi
			else
				ddns_tmp=`cat /var/log/ddns.$ddns_interface.logs | grep "Update_Failed"`
				if [ -n "$ddns_tmp" ];then
					ddns_status=3
					ddns_details="Update failed"
					ddns_time="-"
				else
					#ddns_tmp=`cat /var/log/ddns.$ddns_interface.logs | grep "performing update"`
					#if [ -n "$ddns_tmp" ];then
						# registering
						ddns_status=1
						ddns_details="Performing Update"
						ddns_time="-"
						#else
						# no-ip
						#ddns_status=2
						#ddns_details="Did not get ip address"
						#ddns_time="-"
					#fi
				fi
			fi
		else
			# disabled
			ddns_status=4
			ddns_details="Dynamic dns is not configured"
			ddns_time="-"
		fi

		iface_counters=`getIfaceCounters $oper`
		ifindex=`getifindex $oper`
		if [ "$ifindex" = "not_valid" ];then
		    index=$((index+1))
		    echo v4,$oper,$ip4_count,$ip $mask4,$gw,$dns14,$dns16,$ddns_status,$ddns_details,$ddns_time,$mac_addr,$index,$iface_counters >> $IF_OUTFILE
		else
		    echo v4,$oper,$ip4_count,$ip $mask4,$gw,$dns14,$dns16,$ddns_status,$ddns_details,$ddns_time,$mac_addr,$ifindex,$iface_counters >> $IF_OUTFILE
		fi
		;;
	esac
done < $TMP_OUTPUT

lock $LOCKWANSCRIPT
cp $IF_OUTFILE $IF_OUTFILE_TMP1
echo "1" > $IF_OUTFILESTATUS
cp $IF_OUTFILE_TMP1 $IF_OUTFILE_FINAL
lock -u $LOCKWANSCRIPT
touch $STATUSFILE
