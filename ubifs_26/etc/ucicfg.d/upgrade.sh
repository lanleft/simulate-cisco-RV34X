#!/bin/sh /etc/rc.common

PHASE=$1

image_active="`uci get firmware.firminfo.active 2> /dev/null`"
version_active="`uci get ciscosb-yang.$image_active.version 2> /dev/null`"
startup="`uci get ciscosb-yang.startup.version 2> /dev/null`"
backup="`uci get ciscosb-yang.backup.version 2> /dev/null`"
mirror="`uci get ciscosb-yang.mirror.version 2> /dev/null`"

config_upgrade() {
	local root_dir="/tmp/root_inactive"
	local confd_dir="/tmp/root_inactive/etc/confd"
	local working_dir="/var/confd_inactive"
	local mtd=4
	
	[ "$image_active" = "image1" ] && mtd=7 || mtd=4
	
	# start
	mkdir -p $root_dir && ubiattach -m $mtd && mount -r -t ubifs ubi1:rootfs $root_dir
	mkdir -p $working_dir/fxs
	mkdir -p $working_dir/cdb
	
	# Copy FXS files from inactive
	[ -d $confd_dir/fxs ] && {
		cp -f $confd_dir/fxs/*.fxs $working_dir/fxs
		cp $confd_dir/confd.conf $working_dir/confd.conf
	} || {
		# Firmware 1.0.0.33
		cp -rf $confd_dir/*.fxs $working_dir/fxs
		cp /etc/confd/confd.conf $working_dir/confd.conf
	}
	
	# Copy default XML files from inactive
	cp -rf $confd_dir/cdb/*.xml $working_dir/cdb
	
	# Extract Startup CDB
	local startup_cdb="`find /mnt/configcert/confd/startup/ -name CDB*.tgz`"
	
	[ -f $startup_cdb ] && tar zxf $startup_cdb -C $working_dir/cdb
	
	# Start ConfD
	cd $working_dir
	$root_dir/usr/bin/confd --cd $working_dir -c $working_dir/confd.conf --ignore-initial-validation
	
	# Export Startup config
	local config="/tmp/configuration/config_$startup.xml"
	local config_url="FILE://Configuration/config_$startup.xml"
	
	sed 's|/usr/bin/confd_load|/tmp/root_inactive/usr/bin/confd_load|' $root_dir/usr/sbin/config_mgmt.sh > $working_dir/config_mgmt.sh
	chmod +x $working_dir/config_mgmt.sh
	$working_dir/config_mgmt.sh export config-startup $config_url
	
	# Stop ConfD
	$root_dir/usr/bin/confd --stop
	sleep 3
	
	# end
	umount $root_dir && ubidetach -m $mtd
	
	# Upgrade
	mkdir -p /var/confd/cdb_upgrade
	
	config_mgmt.sh upgrade $config /var/confd/cdb_upgrade/config_$version_active.xml
	rm -rf $config	

	#mv /var/confd/cdb /var/confd/cdb_active
	#ln -s /var/confd/cdb_upgrade /var/confd/cdb
}

phase_init_upgrade() {
	[ -n "$startup" -a "$startup" != "$version_active" ] && {
                local ret=0

                /usr/bin/jsoncmd -R $startup
                ret=$?

                if [ $ret -eq 0 ]; then
                        config_mgmt.sh upgrade config-startup
                else
                        CONFIG_UPGRADE_MODE=1
                        config_upgrade
                fi
                STARTUP_UPDATED=1
		# pass to phase2
		touch /tmp/startup_updated
        }
	
	config_mgmt.sh init
}

phase0_upgrade_metadata() {                                                                                         
        if [ -f "/mnt/configcert/application-md5sum" ]; then                                                        
                old_config=$(cat /mnt/configcert/application-md5sum)                                    
                new_config=$(md5sum /tmp/etc/config/application | awk -F ' ' '{print $1}')                  
                if [ "$old_config" != "$new_config" ]; then                                                         
                        METADATA_UPGRADE_MODE=1                   
                fi                                                
        else                                               
                METADATA_UPGRADE_MODE=1     
        fi                                             
        
	if [ -f "/mnt/configcert/device-md5sum" ]; then                                                        
		old_config=$(cat /mnt/configcert/device-md5sum)                                    
		new_config=$(md5sum /tmp/etc/config/device | awk -F ' ' '{print $1}')                  
		if [ "$old_config" != "$new_config" ]; then                                                         
			METADATA_UPGRADE_MODE=1                   
		fi                                                
	else                                               
		METADATA_UPGRADE_MODE=1
	fi

        if [ $METADATA_UPGRADE_MODE -eq 1 ]; then
                logger -t ucicfg "Reloading the metadata"
                /usr/bin/confd_load -dd -i -l -r -p /avc-meta-data /etc/confd/cdb/avc-meta-data_init.xml    
                /usr/bin/confd_load -dd -i -l -r -p /device-os-types /etc/confd/cdb/device-os-types_init.xml
                /usr/bin/confd_load -dd -i -l -r -p /webfilter-meta-data /etc/confd/cdb/webfilter-meta-data_init.xml
                STARTUP_UPDATED=1
		# pass to phase2
                touch /tmp/startup_updated
        fi
}

phase0_upgrade() {
	phase0_upgrade_metadata
	echo 0
}

phase1_upgrade() {
	echo 0
}

get_bootup_config() {
	local config
	local pid=`uci get systeminfo.sysinfo.pid`
	local mac=`uci get systeminfo.sysinfo.maclan | sed s/://g`
	local sn=`uci get systeminfo.sysinfo.serial_number`
	local usbdir="/media/USB"
	local usb="USB1 USB2"
	local pattern
	
	pattern="$pid-$mac-$sn $pid-$sn $pid-$mac $pid"
	
	for p in `echo $usb`; do
		for n in `echo $pattern`; do
			fname="$usbdir/$p/$n.xml"
			logger -t ucicfg "Looking for $fname"
			[ -f "$fname" ] && {
				logger -t ucicfg "Looking for $fname. OK"
				config=$fname
				break
			} 
		done
	done
	
	echo $config
}

phase2_upgrade_snmp() {                             
        [ -f /etc/init.d/snmpinit ] && . /etc/init.d/snmpinit
                                                           
        local sysDescr=$(confd_cmd -c "mget /snmp/system/sysDescr")
        local sysObjectID=$(confd_cmd -c "mget /snmp/system/sysObjectID")
                                                             
        updatesysdesc                                                    
                                                                         
        [ -n "$SYSDESC" -a "$SYSDESC" != "$sysDescr" ] && {                 
                confd_cmd -c "mset /snmp/system/sysDescr \"$SYSDESC\""   
                STARTUP_UPDATED=1                       
        }                                                   
                                                                        
        [ -n "$SYSOID" -a "$SYSOID" != "$sysObjectID" ] && {                    
                confd_cmd -c "mset /snmp/system/sysObjectID \"$SYSOID\""
                STARTUP_UPDATED=1    
        }                                                                                         
}

phase2_upgrade() {
	local config;
	local is_default=0
	local args
	
	[ -f /tmp/default_state ] && is_default=`cat /tmp/default_state`

	# Require ConfD validation, upgrade backup and mirror config after phase2 done.
	[ -n "$backup" -a "$backup" != "$version_active" ] && config_mgmt.sh upgrade config-backup
	[ -n "$mirror" -a "$mirror" != "$version_active" ] && config_mgmt.sh upgrade config-mirror

	# startup config in XML format
	[ -f /mnt/configcert/confd/startup/config.xml ] && {
		config="/mnt/configcert/confd/startup/config.xml"
	}

	# startup config upgraded from old version
        [ -f /var/confd/cdb_upgrade/config_$version_active.xml ] && {
		config="/var/confd/cdb_upgrade/config_$version_active.xml"
		args="--no-check-version"
	}
	
	# factory default state and no startup config
	[ ! -f "$config" -a $is_default -eq 1 ] && {
		config=`get_bootup_config`
	}

	[ -f "$config" ] && {
		logger -t ucicfg "Loading Startup configuration $config."
		/usr/bin/jsoncmd $args -l $config
		ret=$?
		if [ $ret -eq 0 ]; then
			logger -t ucicfg "Loading Startup configuration $config... OK"			
			STARTUP_UPDATED=1
			
                        if [ $is_default -eq 1 ]; then                                                                                    
                                config_mgmt.sh timeupdate config-startup
                                config_mgmt.sh timeupdate config-running
                                # clear default state
                                echo 0 > /tmp/default_state
                        fi
		else
			logger -t ucicfg "Loading Startup configuration $config... Failed"
		fi
	}
	
	phase2_upgrade_snmp

	# proceed startup updated in other phases
	[ -f /tmp/startup_updated ] && {
		STARTUP_UPDATED=1
		rm /tmp/startup_updated
	}

	# update startup config
	[  -n "$startup" -a $STARTUP_UPDATED -eq 1 ] && {
		config_mgmt.sh copy config-running config-startup
		logger -t ucicfg "Startup configuration updated."
	}

	[  -z "$startup" -a $STARTUP_UPDATED -eq 1 ] && {
                jsoncmd -b
        }
}

case "$PHASE" in
	init)
		phase_init_upgrade
	;;
	phase0)
		phase0_upgrade
	;;
	phase1)
		phase1_upgrade
	;;
	phase2)
		phase2_upgrade
	;;

	*)
	;;
esac
