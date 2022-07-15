#!/bin/sh

VOPSTATE=`poe_cmd -g vopstate`

echo "VOPSTATE=$VOPSTATE" > /tmp/poevopstate

if [ "$VOPSTATE" = "VOP_DRIFT_DETECTED" ]; then
    logger -t poemon -p local0.alert "PoE VOP drift detected"
    exit 1
else
    exit 0
fi

