#!/bin/sh
# 6in4.sh - IPv6-in-IPv4 tunnel backend
# Copyright (c) 2010-2012 OpenWrt.org

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. /lib/functions/network.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

proto_6in4_setup() {
	local cfg="$1"
	local iface="$2"
	local link="6in4-$cfg"

	local mtu ttl ipaddr peeraddr ip6addr tunnelid username password
	json_get_vars mtu ttl peeraddr ip6addr tunnelid username password

	[ -z "$ip6addr" -o -z "$peeraddr" ] && {
		proto_notify_error "$cfg" "MISSING_ADDRESS"
		proto_block_restart "$cfg"
		return
	}

	tunlink=$(echo $cfg | awk -F '_' '{print $1}')
	ifname=$(echo $tunlink | sed s/wan[1-9]*/\&p/g)
	status=$(ifstatus $ifname | grep -o "available")
	if [ "$status" == "available" ];then
		tunlink=$ifname
	fi

	( proto_add_host_dependency "$cfg" "$peeraddr" "$tunlink" )

	[ -z "$ipaddr" ] && {
		local wanif="$tunlink"
		if ! network_get_ipaddr ipaddr "$wanif"; then
			proto_notify_error "$cfg" "NO_WAN_LINK"
			return
		fi
	}

	local local6="${ip6addr%%/*}"
	local mask6="${ip6addr##*/}"
	[[ "$local6" = "$mask6" ]] && mask6=

	proto_init_update "$link" 1
	proto_add_ipv6_address "$local6" "$mask6"
	proto_add_ipv6_route "::" 0

	proto_add_tunnel
	json_add_string mode sit
	json_add_int mtu "${mtu:-1280}"
	json_add_int ttl "${ttl:-64}"
	json_add_string local "$ipaddr"
	json_add_string remote "$peeraddr"
	proto_close_tunnel

	proto_send_update "$cfg"

	[ -n "$tunnelid" -a -n "$username" -a -n "$password" ] && {
		[ "${#password}" == 32 -a -z "${password//[a-fA-F0-9]/}" ] || {
			password="$(echo -n "$password" | md5sum)"; password="${password%% *}"
		}

		local url="http://ipv4.tunnelbroker.net/ipv4_end.php?ip=AUTO&apikey=$username&pass=$password&tid=$tunnelid"
		local try=0
		local max=3

		while [ $((++try)) -le $max ]; do
			wget -qO/dev/null "$url" 2>/dev/null && break
			sleep 1
		done
	}
}

proto_6in4_teardown() {
	local cfg="$1"
}

proto_6in4_init_config() {
	no_device=1             
	available=1

	proto_config_add_string "ipaddr"
	proto_config_add_string "ip6addr"
	proto_config_add_string "peeraddr"
	proto_config_add_string "tunnelid"
	proto_config_add_string "username"
	proto_config_add_string "password"
	proto_config_add_int "mtu"
	proto_config_add_int "ttl"
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol 6in4
}
