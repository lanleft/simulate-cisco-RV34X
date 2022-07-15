#!/bin/sh

POE_PID=`pgrep poemon`
EXITSTATUS=1
FRMVER=$1
FRM_FILE=$2

if [ "$#" -ne 2 ]; then
    echo "Usage: sh $0 <firmware version> <firmware file path>"
    exit $EXITSTATUS
fi

if [ -e "$FRM_FILE" ];then                                                                                  
    #echo "File $FRM_FILE exist"

    if [ -n "$POE_PID" ]; then
        echo "PoE is running"
        echo "Stopping PoE"
        /etc/init.d/poeinit stop >/dev/null 2>&1
    fi

    echo "Upgrading PoE to v$FRMVER"
    echo "/usr/bin/poeupgrade  $FRMVER $FRM_FILE"
    /usr/bin/poeupgrade  $FRMVER  $FRM_FILE
    EXITSTATUS=$?

    if [ "$EXITSTATUS" = 0 ];then
        echo "PoE successfully upgraded to v$FRMVER"
        #echo "Starting PoE"
        #/etc/init.d/poeinit start >/dev/null 2>&1
    fi

else
    echo "File $FRM_FILE not found"
    exit $EXITSTATUS
fi

exit $EXITSTATUS
