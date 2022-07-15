#!/bin/sh

errcode=0
UCIMODULES=/tmp/ucicfg.d/modules

update(){
	output="$1"

	rm $output
#	echo "#!/bin/sh" > $output
#	echo "uci batch <<EOF" >> $output
	for file in /tmp/ucicfg.d/uci_update.*; do
		filename=${file##*/}
		spoint=${file##*.}
		config=`echo $filename | awk -F . '{print $2}'`

		#[ -f /tmp/ucicfg.d/uci_clear_p.$config.$spoint ] && cat /tmp/ucicfg.d/uci_clear_p.$config.$spoint >> $output
		#mv /tmp/ucicfg.d/uci_clear.$config.$spoint /tmp/ucicfg.d/uci_clear_p.$config.$spoint

		[ -s /tmp/ucicfg.d/uci_update.$config.$spoint ] && { 
			cat /tmp/ucicfg.d/uci_update.$config.$spoint >> $output
			echo $config >> $UCIMODULES
		}
		rm /tmp/ucicfg.d/uci_update.$config.$spoint
	done

#	echo "EOF" >> $output
#	chmod +x $output && $output > /dev/null 2>&1
	uciagent $output
}

apply() {
	if [ -z `cat $UCIMODULES | grep -w network` ] || [ -z `cat $UCIMODULES | grep -v network`]; then
		modules="`cat $UCIMODULES | sort -u`"
	else
		modules="`cat $UCIMODULES | sort -u | grep -v network | sed -e '1i network'`"
	fi
	deplists=""

	echo "${deplists}" | (
		while read line; do
				key="$(echo "${line}" | cut -d: -f1)"
				pattern="$(printf "^\(%s\)$" "$(echo "${line}" | cut -d: -f2- | sed -e "s/,/\\\|/g")")"
				[ -n "$(echo "${modules}" | grep "^${key}$")" ] && {
						modules="$(echo "${modules}" | grep -v "${pattern}")"
				}
		done
		echo "${modules}"
	) | while read m; do
		start=$(date +%s)
		logger -t ucicfg "Reloading $m ..."
		/etc/init.d/config_update.sh $m
		errcode="$?"
		end=$(date +%s)
		if [ "$errcode" = "0" ]; then
			logger -t ucicfg "Reloading $m ... elpased=$(($end - $start))s." 
		else
			logger -t ucicfg "Reloading $m ... failed $errcode." 
		fi
	done

	rm -f $UCIMODULES
	return $?
}

apply_all() {
	modules=$(echo `cat $UCIMODULES | sort -u`)
	
	logger -t ucicfg "Reloading $modules ..."
	
	/etc/init.d/config_update.sh $modules
	errcode="$?"
	[ "$errcode" = "0" ] || logger -t ucicfg "Reloading $m ... failed $errcode."
	
	rm -f $UCIMODULES
	return $?
}

starttime=$(date +%s)

update /tmp/update.sh
[ -f /tmp/config_loading ] && apply_all || apply
ret=$?

endtime=$(date +%s)
logger -t ucicfg "Loading modules ... elpased=$(($endtime - $starttime))s." 

echo $ret
