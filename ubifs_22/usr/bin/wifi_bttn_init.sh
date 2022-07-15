#!/bin/sh

WIFI_BUTTON="gpio14"
WIFI_BUTTON_VALUE="14"

[ ! -d "/sys/class/gpio/${WIFI_BUTTON}" ] && {
	echo ${WIFI_BUTTON_VALUE} >/sys/class/gpio/export;
	echo in >/sys/class/gpio/${WIFI_BUTTON}/direction
}
