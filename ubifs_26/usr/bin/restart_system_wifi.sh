#!/bin/sh

enable=`uci get recurring-schedule-reboot.reboot.enable`

if [ "$enable" = 0 ]; then
	logger -t system "Schedule reboot feature is disabled"
	exit 1
fi

board="$(/usr/bin/board_check.sh)"
action=`uci get recurring-schedule-reboot.reboot.action` >/dev/null 2>&1

if [ "$action" = 1 ]; then
	# wifi radios reboot
	if [ "$board" = "RV260W" -o "$board" = "RV340W" -o "$board" = "RV160W" ]; then
		logger -t system -p local0.alert " Performing scheduled wireless restart begun !!"
		#Exit if the interface is not up
		/usr/bin/wireless_restart
		logger -t system -p local0.alert " Performing scheduled wireless restart finished !!"
	fi
elif [ "$action" = 0 ]; then
	#system reboot
	logger -t system -p local0.alert " Performing scheduled Router restart !!"
	reboot &
fi
