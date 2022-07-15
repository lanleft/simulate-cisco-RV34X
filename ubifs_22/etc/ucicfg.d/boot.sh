#!/bin/sh /etc/rc.common

image_active="`uci get firmware.firminfo.active 2> /dev/null`"
image_inactive="`uci get firmware.firminfo.inactive 2> /dev/null`"
version_active="`config_mgmt.sh config-version yang`"

touch /tmp/etc/config/ciscosb-yang

[ -n "$image_active" ] && { 
	uci set ciscosb-yang.$image_active=model
	uci set ciscosb-yang.$image_active.version=$version_active
}

version="`config_mgmt.sh config-version config-startup`"
uci set ciscosb-yang.startup=datastore
uci set ciscosb-yang.startup.version=$version

version="`config_mgmt.sh config-version config-backup`"
uci set ciscosb-yang.backup=datastore
uci set ciscosb-yang.backup.version=$version

version="`config_mgmt.sh config-version config-mirror`"
uci set ciscosb-yang.mirror=datastore
uci set ciscosb-yang.mirror.version=$version

uci commit ciscosb-yang