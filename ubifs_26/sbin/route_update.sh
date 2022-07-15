#!/bin/sh
oper=$1
ipaddrinput=$2
mask=$3
device=$4
[ "$5" = "0" ] && {
return
}
[ "$5" = "" ] && {
return
}
gw="via $5"

dbg_fn() {
  # comment below line, if log generation is not required
  logger -p 6 -t rtupd-routeupdatescript ": $1"

  # comment below line, if echoing is not required.
  #echo "$1"
}

existing_routes=$(ip route show table 220 | awk -F  ' ' '{print $1}');
#conn_routes=$(ip route show table 220 | awk -F '/' '{print $1}' | sed s/'\.0'//g)

#dbg_fn "Received $1,$2,$3,$4,$5: and parsed data:$existing_routes:"

for entry in $existing_routes
do
	# for each entry extract network and netmask
	nw=`echo $entry | cut -d/ -f1`;
	nwmask=`echo $entry | cut -d/ -f2`;

	# compute network for the ipaddrinput based on nwmask of the existing route
	ipaddrinput_network=`/bin/ipcalc.sh $ipaddrinput/$nwmask | grep NETWORK | cut -d = -f 2`

	#dbg_fn "nw=$nw,nwmask=$nwmask,ipaddrinput=$ipaddrinput,ipaddrinput_network=$ipaddrinput_network"
	# Checking, whether listed network and computed network matches
	if [ "$nw" = "$ipaddrinput_network" ]; then
		# Yes, The ipaddrinput belong to the network. So allow syncing the route update to table 220 as below
		if [ "$oper" == "add" ]; then
			dbg_fn "performing: ip route add $ipaddrinput/$mask $gw dev $device table 220"
			ip route add $ipaddrinput/$mask $gw dev $device table 220
		elif [ "$oper" == "del" ]; then
			dbg_fn "performing: ip route del $ipaddrinput/$mask $gw dev $device table 220 2>&- >&-"
			ip route del $ipaddrinput/$mask $gw dev $device table 220 2>&- >&-
		fi
	fi
done
