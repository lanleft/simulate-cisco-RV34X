#!/bin/sh /etc/rc.common

STATUSFILE=/tmp/switchfailure
date=`date`

[ ! -r $STATUSFILE ] && {
	#logger -t rtk-ms-sdk -p local0.info " $STATUSFILE not exist on date=$date"
	return 0
}

state=`cat $STATUSFILE`
[ "$state" = "1" ] && {
	logger -t rtk-ms-sdk -p local0.crit " switch failure detected on date=$date !!!"
	/etc/init.d/ms-switch stop
	sleep 5
	/etc/init.d/ms-switch start
	logger -t rtk-ms-sdk -p local0.crit " switch restarted !!!"
	echo "0" >$STATUSFILE
}
return 0
