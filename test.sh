#!/bin/sh

echo "$1"
if [ -z "$1" ]; then
	echo 'Missing version...'
	echo 'Usage: start.sh 22 # simulate cisco version 22'
	exit 0
fi

if [ "$1" != "22" ] && [ "$1" != "26" ]; then
	echo "Sorry, we have only emulated 2 veresions: 22 and 26"
	exit 0
fi 

version_simulate="fw_$1"
echo $version_simulate/test