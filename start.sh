#!/bin/sh

echo '[+] Extract filesystems'
if [ ! -d 'fw_26/' ]; then
	echo ' => This is the first time extract tar file'
	tar -xf fw_26.tar
	chmod -R 777 fw_26/
else
	echo '=> The tar file have been extracted before'
fi 

echo '[+] Mount block'
mount --bind /proc /fw_26/proc
mount --bind /dev /fw_26/dev

echo '[+] Start emulate service'
chroot fw_26/ cisco.sh



