#!/bin/sh

func=$(lcjson -a "$1" get event.module)
tick=$(lcjson -a "$1" get event.ts)
addr=$(lcjson -a "$1" get event.mac)
loc_ip=$(lcjson -a "$1" get event.ip)
rmt_ip=$(lcjson -a "$1" get event.remote_ip)
loc_port=$(lcjson -a "$1" get event.port)
rmt_port=$(lcjson -a "$1" get event.remote_port)
act=$(lcjson -a "$1" get event.action)
idx=$(lcjson -a "$1" get event.sid)
virus=$(lcjson -a "$1" get event.threat)
proto=$(lcjson -a "$1" get event.osi7_proto)
fp=$(lcjson -a "$1" get event.file)

case $func in
"av")
	sqlite3 /tmp/stat.db "INSERT INTO av  (ts, mac, ip, remote_ip, port, remote_port, sid, actions, threat, osi7_proto, file) \
		VALUES ($tick, \"$addr\", \"$loc_ip\", \"$rmt_ip\", $loc_port, $rmt_port, \"$idx\", \"$act\", \"$virus\", \"$proto\", \"$fp\");"
	;;
"ips")
	sqlite3 /tmp/stat.db "INSERT INTO ips (ts, mac, ip, remote_ip, port, remote_port, sid, actions) \
		VALUES ($tick, \"$addr\", \"$loc_ip\", \"$rmt_ip\", $loc_port, $rmt_port, \"$idx\", \"$act\");"
	;;
*)
	;;
esac
