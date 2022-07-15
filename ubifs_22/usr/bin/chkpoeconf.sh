#!/bin/sh

TRAP_ENABLED=`uci get poeconf.poeglobal_0.trap`
TRAP_THRESHOLD=`uci get poeconf.poeglobal_0.trap_threshold`
#ret="`confd_cmd -c "mget /confdConfig/snmpAgent/enabled"`"

#echo "SNMP_ENABLED=$ret"
echo "POE_TRAP_ENABLED=$TRAP_ENABLED"
echo "POE_TRAP_THRESHOLD=$TRAP_THRESHOLD"
