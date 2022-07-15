#!/bin/sh
#

if [ "$(lsmod | grep lionic_dpi | wc -l)" != "0" ]
then
	exit
fi

if [ -e "/tmp/ysmir_loading" ]
then
	exit
fi

touch /tmp/ysmir_loading
YSMIR_FAILED="0"

for i in `seq 1 5`
do
	if [ "$(lsmod | grep fci | wc -l)" != "0" ]
	then
		break
	fi
	sleep 1
done

#enable bridge mode
#echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
#echo 1 > /proc/sys/net/bridge/bridge-nf-call-ip6tables

#time sync
#rdate -s time.nist.gov

rm -rf /dev/se_*

touch /tmp/etc/config/dm
uci set dm.os=section
uci commit dm

if [ -f /mnt/avcsign/dm ]
then
	# Copying from saved dm file
	cp -f /mnt/avcsign/dm /tmp/etc/config/dm
fi

#. /etc/functions.sh

init_db()
{
	rm -rf /tmp/stat.db

	sqlite3 /tmp/stat.db "CREATE TABLE IF NOT EXISTS init (id INTEGER UNIQUE, times INTEGER);"
	sqlite3 /tmp/stat.db "CREATE TABLE IF NOT EXISTS usr (name TEXT, mac TEXT, CONSTRAINT uid UNIQUE (name, mac));"
	sqlite3 /tmp/stat.db "CREATE TABLE IF NOT EXISTS dev (mac TEXT UNIQUE, ref_time INTEGER, ip TEXT, name TEXT, type TEXT, os TEXT, uni INTEGER);"
	sqlite3 /tmp/stat.db "CREATE TABLE IF NOT EXISTS category (cat_id INTEGER UNIQUE, cat_name TEXT);"
	sqlite3 /tmp/stat.db "CREATE TABLE IF NOT EXISTS application (app_id INTEGER UNIQUE, app_name TEXT, proto INTEGER, port INTEGER, cat_id SMALLINT);"
	sqlite3 /tmp/stat.db "CREATE TABLE IF NOT EXISTS stat (mac TEXT, app_id INTEGER, proto INTEGER, port INTEGER, dl INTEGER, ul INTEGER, refcount INTEGER, life INTEGER, CONSTRAINT uid UNIQUE (mac, app_id));"

	sqlite3 /tmp/stat.db "CREATE TABLE IF NOT EXISTS sig (sid TEXT UNIQUE, severity TEXT, cvss TEXT, cve TEXT, classtype TEXT, platform TEXT, name TEXT, description TEXT, impact TEXT, recommend TEXT);"
	sqlite3 /tmp/stat.db "CREATE TABLE IF NOT EXISTS ips (ts INTEGER, mac TEXT, ip TEXT, remote_ip TEXT, port INTEGER, remote_port INTEGER, sid TEXT, actions TEXT);"
	sqlite3 /tmp/stat.db "CREATE TABLE IF NOT EXISTS av  (ts INTEGER, mac TEXT, ip TEXT, remote_ip TEXT, port INTEGER, remote_port INTEGER, sid TEXT, actions TEXT, threat TEXT, osi7_proto TEXT, file TEXT);"
	sqlite3 /tmp/stat.db "CREATE TABLE IF NOT EXISTS summary (date_hour INTEGER, func TEXT, type INTEGER, counts INTEGER, CONSTRAINT uid UNIQUE(date_hour, func, type));"

	sqlite3 /tmp/stat.db "CREATE TRIGGER IF NOT EXISTS trigger_av  AFTER INSERT ON av  BEGIN DELETE FROM av  WHERE ts =(SELECT min(ts) FROM av ) and (SELECT count(*) FROM av ) > 1000; END;"
	sqlite3 /tmp/stat.db "CREATE TRIGGER IF NOT EXISTS trigger_ips AFTER INSERT ON ips BEGIN DELETE FROM ips WHERE ts =(SELECT min(ts) FROM ips) and (SELECT count(*) FROM ips) > 1000; END;"
	sqlite3 /tmp/stat.db "CREATE TRIGGER IF NOT EXISTS trigger_summary_av  AFTER INSERT ON av  BEGIN DELETE FROM summary WHERE date_hour < CAST(strftime('%s', 'now', '-1 months') AS INTEGER); UPDATE summary SET counts = (counts + 1) WHERE date_hour = strftime('%s', strftime('%Y-%m-%d %H:00:00', 'now')) AND func = \"av\"  AND type = 1; INSERT OR IGNORE INTO summary (date_hour, func, type, counts) VALUES (strftime('%s', strftime('%Y-%m-%d %H:00:00', 'now')), \"av\",  1, 1); END;"
	sqlite3 /tmp/stat.db "CREATE TRIGGER IF NOT EXISTS trigger_summary_ips AFTER INSERT ON ips BEGIN DELETE FROM summary WHERE date_hour < CAST(strftime('%s', 'now', '-1 months') AS INTEGER); UPDATE summary SET counts = (counts + 1) WHERE date_hour = strftime('%s', strftime('%Y-%m-%d %H:00:00', 'now')) AND func = \"ips\" AND type = 1; INSERT OR IGNORE INTO summary (date_hour, func, type, counts) VALUES (strftime('%s', strftime('%Y-%m-%d %H:00:00', 'now')), \"ips\", 1, 1); END;"
}

load_ysmir()
{
	local MODULE_LIST
	local para

	MODULE_LIST=$(uci show ysmir.ysmir_module | grep -v "=section" | cut -d'.' -f3)
	for i in $MODULE_LIST
	do
		para="$para $i"
	done

	echo "Start Ysmir"
	insmod /lib/modules/$(uname -r)/lionic_resoft.ko
	insmod /lib/modules/$(uname -r)/lionic_dpi.ko $para
	insmod /lib/modules/$(uname -r)/lionic_fpal.ko
	insmod /lib/modules/$(uname -r)/lionic_event.ko daemon_port=5514
	insmod /lib/modules/$(uname -r)/lionic_pktal.ko

	for i in `seq 1 5`
	do 
		if [ -e "/dev/se_ctrl" ] && [ -e "/dev/se_data" ]
		then
			break
		fi
		sleep 1
	done

	if [ ! -e "/dev/se_ctrl" ] || [ ! -e "/dev/se_data" ]
	then
		mknod /dev/lcs c 10 110
		mknod /dev/se_ctrl c 10 111
		mknod /dev/se_data c 10 112
		mknod /dev/se_uf c 10 113
		mknod /dev/se_av c 10 114
		mknod /dev/decomp00 c 10 115

		chmod 666 /dev/lcs
		chmod 666 /dev/se_ctrl
		chmod 666 /dev/se_data
		chmod 666 /dev/se_uf
		chmod 666 /dev/se_av
		chmod 666 /dev/decomp00
	fi

        if [ "$(lcsh show number pkt | tr -d '\n')" != "0" ]
        then
		logger "Turnkey fails to create device nodes again"
		ysmir-stop.sh
		YSMIR_FAILED="1"	
        fi
}

init_db
load_ysmir

if [ "$YSMIR_FAILED" == "1" ] && [ ! -e /tmp/etc/config/rebooted ]
then
	# Add rebooted flag to prevent infinite reboot when Ysmir is failed
	touch /tmp/etc/config/rebooted
	reboot
	exit

elif [ "$YSMIR_FAILED" == "0" ] && [ -e /tmp/etc/config/rebooted ]
then
	# Success to start Ysmir, remove rebooted flag
	rm /tmp/etc/config/rebooted
fi

echo "[Ysmir] load signature" > /dev/console
ysmir-sig.sh init 

#ysmir-sig.sh
#ysmir-config.sh

echo "[Ysmir] Start Success" > /dev/console
rm -f /tmp/ysmir_loading

#lcsh uci dm restore

#lcsh sys rdpage block.php
#/usr/bin/uf_agent &

#set slowpath
#cmm -c "set dpi enable"
# Instead of specific AVC enable case, Enabling Flow stat in PFE always
# cmm -c "set stat enable flow"

lcsh sys stop

lcsh license status
lcsh sys start
