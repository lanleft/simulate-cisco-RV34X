#!/bin/sh

wifi_button="$(cat /sys/class/gpio/gpio14/value)"

WIFI_ON="1"
WIFI_OFF="0"

if [ "$wifi_button" = "$WIFI_ON" ];then
	echo "1"
else
	echo "0"
fi
