#!/bin/sh
#

rm -f /tmp/ysmir_loading

if [ "$(lsmod | grep lionic_dpi | wc -l)" == "0" ]
then
	exit
fi

if [ -e "/tmp/ysmir_loading" ]
then
	echo "[Ysmir] Stop Failed (ysmir is loading)" > /dev/console
	exit
fi

# backup dm

val=`cat /mnt/configcert/config/rebootstate`
if [[ "$val" -eq "4" ]]
then
	# Fact default config and/or with certs
	# resetting the dev,os  entries in the file to avoid retain across reboot
	echo "[Ysmir] resetting device,os info" > /dev/console
	echo "config 'section' 'os'" > /mnt/avcsign/dm
	sync
else
	# saving device,os across reboot
	lcsh uci dm save
	cp -f /tmp/etc/config/dm /mnt/avcsign/dm
fi


for i in `seq 1 5`
do 

	lcsh uf off
	lcsh apg off
	lcsh ips off
	lcsh dm off
	lcsh av off
	lcsh sys stop

	killall -q lcstat
	killall -q lcavc
	killall -q lcavc
	killall -q upnp_cp
	killall -q decomp_server
	killall -q casa
	killall -q uf_agent

	lcsh sys stop
	lcsh log mem all on

	if [ "$(lcsh show number pkt | tr -d '\n')" == "0" ]
	then
		rmmod lionic_pktal
		rmmod lionic_event
		rmmod lionic_fpal
		rmmod lionic_dpi
		rmmod lionic_resoft
	fi

	if [ "$(lsmod | grep lionic_dpi | wc -l)" == "0" ]
	then
		break
	fi

	sleep 1
done


#disable bridge mode
#echo 0 > /proc/sys/net/bridge/bridge-nf-call-iptables
#echo 0 > /proc/sys/net/bridge/bridge-nf-call-ip6tables

# enable fast patch
#cmm -c set stat disable flow
#cmm -c set dpi disable

echo "[Ysmir] Stop Success" > /dev/console

