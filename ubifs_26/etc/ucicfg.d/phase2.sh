#!/bin/sh

logger -t ucicfg "phase2 ..."

update(){
	output="$1"

	rm $output

	for file in /tmp/ucicfg.d/uci_update.*; do
		filename=${file##*/}
		spoint=${file##*.}
		config=`echo $filename | awk -F . '{print $2}'`

		#[ -f /tmp/ucicfg.d/uci_clear_p.$config.$spoint ] && cat /tmp/ucicfg.d/uci_clear_p.$config.$spoint >> $output
		#mv /tmp/ucicfg.d/uci_clear.$config.$spoint /tmp/ucicfg.d/uci_clear_p.$config.$spoint

		[ -s /tmp/ucicfg.d/uci_update.$config.$spoint ] && { 
			cat /tmp/ucicfg.d/uci_update.$config.$spoint >> $output
		}
		rm /tmp/ucicfg.d/uci_update.$config.$spoint
	done
	uciagent $output
}

apply() {
	return 0
}

CONFIG_ARGS="-c /tmp/etc/config/ -m /mnt/configcert/confd"

ucicfg_network $CONFIG_ARGS
ucicfg_security $CONFIG_ARGS
ucicfg_system $CONFIG_ARGS

sleep 1

confd_cmd -c "trigger_subscriptions"

update /tmp/update.sh
apply

default_state="`cat /tmp/default_state`"
[ "$default_state" = "1" ] && {
    config_mgmt.sh timeupdate config-startup
    config_mgmt.sh timeupdate config-running
}

logger -t ucicfg "phase2: end"                
                
cp /tmp/.uci/network /tmp/networkconfig
uci commit
                
/etc/init.d/config_update.sh syslog
/etc/init.d/config_update.sh network_onboot
                 
echo 1 > /tmp/ucicfg.d/state
                 
echo 0
