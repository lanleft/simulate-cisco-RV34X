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

version_simulate="ubifs_$1"

echo '[+] Extract filesystems'
if [ ! -d "$version_simulate" ]; then
	echo ' => This is the first time extract tar file'
	tar -xf fw_$1.tar
	chmod -R 777 $version_simulate/
else
	echo '=> The tar file have been extracted before'
fi 

echo '[+] Mount block'
mount --bind /proc $version_simulate/proc
mount --bind /dev $version_simulate/dev

echo '[+] Start emulate service'
chroot $version_simulate/ /cisco.sh


