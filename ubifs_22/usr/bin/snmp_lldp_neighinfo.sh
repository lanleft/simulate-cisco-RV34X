#!/bin/sh

# IFACE?sys_name?port_type?port?chasis_type?chasis?mgmt_address?sys_cap?enabled_cap?sys_desc?port_desc?ttl

#PID="$1"
PID=`uci get systeminfo.sysinfo.pid | cut -d'-' -f1`
LLDP_STATS_FILE="/tmp/stats/snmp_lldpneighstats"
LAN_PORT1="LAN1"
LAN_PORT2="LAN2"
LAN_PORT3="LAN3"
LAN_PORT4="LAN4"
NOTRECEIVED="Not received"

WAN_PHY_PORT1=`uci get network.wan1.ifname` > /dev/null 2>&1
WAN_PHY_PORT1=${WAN_PHY_PORT1%%.*}
WAN_PHY_PORT2=`uci get network.wan2.ifname` > /dev/null 2>&1
VLAN_PORT=`uci get network.vlan1.ifname`; VLAN_PORT=${VLAN_PORT%%.*}

rm -rf $LLDP_STATS_FILE
touch $LLDP_STATS_FILE

TMP_LLDP_STATS_FILE="/tmp/snmp_lldpneighstats"
lldpctl > $TMP_LLDP_STATS_FILE
`sed -i "s/  */ /g" $TMP_LLDP_STATS_FILE`

while read first rest
do
	case "$first" in
		Interface:)
			iface=${rest%%,*}   #deletes largest substring from end starting with ,
		;;
		ChassisID:)
			chasis_type=${rest%% *}
			chasis=${rest##* }  #deletes largest substring from start till space
		;;
		SysName:)
			sys_name=$rest
		;;
		SysDescr:)
			sys_desc=$rest
		;;
		TTL:)
			ttl=$rest
		;;
		MgmtIP:)
			mgmt_address=$rest
		;;
		Capability:)
			tmp=${rest%%,*}
			sys_cap=$sys_cap" "$tmp
			status=${rest##* }
			if [ "$status" = "on" ];then
				enabled_cap=$enabled_cap" "$tmp
			fi
		;;
		PortID:)
			port_type=${rest%% *}
			port=${rest##* }
		;;
		PortDescr:)
			[ "$rest" = "$NOTRECEIVED" ] && port_desc=$rest || {
         			port_desc=${rest%% *}
			}

			skip_entry=0
			if [ "$iface" = "$WAN_PHY_PORT1" ];then
				iface="WAN_PORT1"
			elif [ "$iface" = "$WAN_PHY_PORT2" ];then
				iface="WAN_PORT2"
			elif [ "$iface" = "$VLAN_PORT" ];then
				lan_port=`echo $rest | cut -d = -f 2`

				if [ "$PID" = "RV160" ] || [ "$PID" = "RV160W" ];then
					case $lan_port in
						0)
							iface="LAN4"
						;;
						1)
							iface="LAN3"
						;;
						2)
							iface="LAN2"
						;;
						3)
							iface="LAN1"
						;;
						*)
							skip_entry=1
						;;
					esac
				elif [ "$PID" = "RV260" ] || [ "$PID" = "RV260W" ] || [ "$PID" = "RV260P" ];then
					case $lan_port in
						0)
							iface="LAN1"
						;;
						1)
							iface="LAN2"
						;;
						2)
							iface="LAN3"
						;;
						3)
							iface="LAN4"
						;;
						4)
							iface="LAN5"
						;;
						5)
							iface="LAN6"
						;;
						6)
							iface="LAN7"
						;;
						7)
							iface="LAN8"
						;;
						*)
							skip_entry=1
						;;
					esac
				elif [ "$PID" = "RV340" ] || [ "$PID" = "RV340W" ];then
					case $lan_port in
						1)
							iface="LAN4"
						;;
						2)
							iface="LAN3"
						;;
						3)
							iface="LAN2"
						;;
						4)
							iface="LAN1"
						;;
						*)
							skip_entry=1
						;;
					esac
				elif [ "$PID" = "RV345" ] || [ "$PID" = "RV345P" ];then
					case $lan_port in
						0)
							iface="LAN9"
						;;
						1)
							iface="LAN1"
						;;
						2)
							iface="LAN10"
						;;
						3)
							iface="LAN2"
						;;
						4)
							iface="LAN11"
						;;
						5)
							iface="LAN3"
						;;
						6)
							iface="LAN12"
						;;
						7)
							iface="LAN4"
						;;
						8)
							iface="LAN13"
						;;
						9)
							iface="LAN5"
						;;
						10)
							iface="LAN14"
						;;
						11)
							iface="LAN6"
						;;
						12)
							iface="LAN15"
						;;
						13)
							iface="LAN7"
						;;
						14)
							iface="LAN16"
						;;
						15)
							iface="LAN8"
						;;
						*)
							skip_entry=1
						;;
					esac
				fi
			fi
			# Echo the require output
			if [ -n "$iface" ] && [ "$skip_entry" = 0 ];then
				echo "$iface?$sys_name?$port_type?$port?$chasis_type?$chasis?$mgmt_address?$sys_cap?$enabled_cap?$sys_desc?$port_desc?$ttl"
			fi
			# reset capability & enabled capabilities
			sys_cap=""
			enabled_cap=""
		;;
	esac
done < $TMP_LLDP_STATS_FILE > $LLDP_STATS_FILE
		

