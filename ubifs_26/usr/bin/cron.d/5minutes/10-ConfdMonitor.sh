#!/bin/sh /etc/rc.common

# Check for below daemons and run if got killed.
daemons="ucicfg_aaa webcache notifyd"

backup_and_restart() {
	case $1 in
		notifyd)
			$1 -i 127.0.0.1 &
		;;
		*)
			$1 &
		;;
	esac
}

state=`cat /tmp/ucicfg.d/state`

[ "$state" = "1" ] || return 0

for word in $daemons;do
        died=`pidof $word`
        [ -z "$died" ] && {
                uptime=`uptime`
                logger -t ConfdMonitor -p local0.crit "$word got killed .. uptime=$uptime"

                # Restart the daemon and take required backup.
                backup_and_restart $word
        }
done

