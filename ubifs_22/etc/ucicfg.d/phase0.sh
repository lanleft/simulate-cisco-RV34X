#!/bin/sh

CONFIG_ARGS="-c /tmp/etc/config/ -m /mnt/configcert/confd"

logger -t ucicfg "phase0 ..."
mkdir -p /tmp/ucicfg.d
echo 0 > /tmp/ucicfg.d/state
cp /etc/ucicfg.d/data/* /tmp/ucicfg.d/
ucicfg_init $CONFIG_ARGS
logger -t ucicfg "phase0: end"
