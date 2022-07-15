#!/bin/sh

board=`uci get systeminfo.sysinfo.pid | cut -d'-' -f1`

echo "$board"
