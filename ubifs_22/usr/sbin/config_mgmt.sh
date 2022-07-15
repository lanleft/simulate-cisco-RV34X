#!/bin/sh
#
# Copy/Save Configuration
#
# return value:
#	0 : success
#	1 : fail
#	2 : import config is a illegal file
#	3 : import process on running, please wait a minute
#
# RELEASE ON 2015.11.10

errcode=1
LOAD_CONFIG="/usr/bin/confd_load"
CONFD_BIN="/usr/bin/confd"
CONFIG_PART="/mnt/configcert"
CONFIG_DIR="$CONFIG_PART/confd"
CONFD_CMD="/usr/bin/confd_cmd"
JSONCMD="/usr/bin/jsoncmd"
MOBILERESTCMD="/usr/bin/reset-mobile-statistics"
MOBILEIF="USB1 USB2"

RUNNING_CONFIG="/var/confd/cdb"
DEFAULT_CONFIG="/etc/confd/cdb"
STARTUP_CONFIG="$CONFIG_DIR/startup"
BACKUP_CONFIG="$CONFIG_DIR/backup"
MIRROR_CONFIG="$CONFIG_DIR/mirror"
FILE_CONFIG="FILE://Configuration/"
DOWNLOAD_CONFIG="/www/download/configuration/"
TMP_CONFIG="/tmp/configuration/"
DOWNLOADSTATUS="/mnt/configcert/config/downloadstatus"
FILE_USB1="FILE://USB1"
FILE_USB2="FILE://USB2"
MEDIA_USB1="/media/USB/USB1"
MEDIA_USB2="/media/USB/USB2"
CDB_FILE="CDB.tgz"
CONFIG_FILE="config.xml"
CONFIG_TARFILE="config.xml.tgz"
STATUS_FILE="O.cdb"
UPTIME_FILE="/tmp/running_time"
UPDATE_MIRROR_TIME=86400
CONFIG_LOCK="/tmp/config_loading"
TYPE="$1"
SOURCE="$2"
DEST="$3"

# unset two ENV value for avoid attaching to existing session
unset CONFD_MAAPI_USID
unset CONFD_MAAPI_THANDLE

help() {
	cat <<EOF
Syntax: $0 [type] [source] [destination]

Available type:
	init			initialization
	copy			copy configuration between running/startup/backup/mirror
	export			export configuration to PC/USB
	import			import configuration from PC/USB
	reset			reset all configuration
	timeupdate		update config time to ConfD
	check			check config pid
	mirrorupdate	update running configuration to mirror configuration

Available source/destination:
	config-running          Running Configuration
	config-startup          Startup Configuration
	config-backup           Backup Configuration
	config-mirror           Mirror Configuration

Return status code:
0 : Success copy/save
1 : Fail copy/save
EOF
}

mapping() {
	case "$1" in
		config-running) echo "$RUNNING_CONFIG"  ;;
		config-startup) echo "$STARTUP_CONFIG"  ;;
		config-backup)  echo "$BACKUP_CONFIG"   ;;
		config-mirror)  echo "$MIRROR_CONFIG"   ;;
	esac
}

path_mapping() {
	case "$1" in
		config-running) echo "/config-state/running-update-time"  ;;
		config-startup) echo "/config-state/startup-update-time"  ;;
		config-backup)  echo "/config-state/backup-update-time"   ;;
		config-mirror)  echo "/config-state/mirror-update-time"   ;;
	esac
}

uci_mapping() {
	case "$1" in
		config-running) echo "running"  ;;
		config-startup) echo "startup"  ;;
		config-backup)  echo "backup"   ;;
		config-mirror)  echo "mirror"   ;;
	esac
}

format_mapping() {
	case "$1" in
		config-running) echo "cdb" ;;
		config-startup) echo "cdb-backup" ;;
		config-backup)  echo "xml" ;;
		config-mirror)  echo "xml" ;;
	esac
}

#==========================================================
# config utilities
#==========================================================

get_config_header() {
	local header="echo `head -n 1 $1` | sed -e 's/<!-- \| -->//g'"
	
	IFS=' ,'
	for i in $header
	do
		token="`echo $i | awk -F[:] '{print $1}'`"
		value="`echo $i | awk -F[:] '{print $2}'`"
		
		[ "$token" = "$2" ] && {
			echo "$value"
			break
		}
	done
}

check_config_version() { # 1 config
	local config_version="`get_config_header $1 firmware`"
	local firmware_version="`uci get firmware.firminfo.version 2> /dev/null`" 
	local hex_firmware_version=`echo $firmware_version | (IFS=".$IFS"; read a b c d && printf '%02x' $a && printf '%02x' $b && printf '%02x' $c && printf '%02x' $d)`
	local hex_config_version=`echo $config_version | (IFS=".$IFS"; read a b c d && printf '%02x' $a && printf '%02x' $b && printf '%02x' $c && printf '%02x' $d)`    
																																								   
	upgrade=`echo $((0x$hex_firmware_version - 0x$hex_config_version))`
	
	[ $upgrade -eq 0 ] && {
		logger -t ConfD "Configuration version($config_version) is same as firmware version ($firmware_version) ."
		echo 0
	} || {
		[ $upgrade -gt 0 ] && {
			logger -t ConfD "Configuration version($config_version) is older than firmware version ($firmware_version), configuration upgrade is needed."
			echo 1
		} || {
			logger -t ConfD "Configuration version($config_version) is newer than firmware version ($firmware_version), configuration downgrade is needed."
			echo -1
		}
	}
}

check_config_integrity() { # 1 config
	local config_md5sum="`get_config_header $1 md5`"
	local actual_md5sum="`sed -e '1d' $1 > $1.tmp && md5sum $1.tmp | awk '{print $1}' && rm -rf $1.tmp`"
	
	[ "$config_md5sum" = "$actual_md5sum" ] && {
		logger -t ConfD "Configuration integrity ($config_md5sum) check OK."
		echo 0
	} || {
		logger -t ConfD "Configuration integrity ($config_md5sum) check failed."
		echo 1
	}
}

get_yangmodel_version() {
	local version="`cat /usr/lib/opkg/info/ciscosb-yang.control | grep Version | awk -F[-\ ] '{print $2}'`"
	
	echo $version
}

get_config_name() {
	local config=$1
	local format=$2
	local path="`mapping $1`"
	local version="`get_yangmodel_version`"	
	local config_version="`get_config_version $config`"
	
	[ -n "$config_version" ] || {
		# config not found, use yang model version instead
		config_version=$version
	}
	
	[ "$config_version" = "0.0.0" ] && {
		case $config-$format in
			config-startup-cdb)			
				echo "$path/CDB.tgz"
			;;
			
			config-startup-xml|config-backup-xml|config-mirror-xml)
				echo "$path/config.xml.tgz"
			;;
		esac
	} || {
		case $config-$format in
			config-startup-cdb)			
				echo "$path/CDB_$config_version.tgz"
			;;
			
			config-startup-xml|config-backup-xml|config-mirror-xml)
				echo "$path/config_$config_version.xml.tgz"
			;;
		esac
	}
}

get_default_config_name() {
	local config=$1
	local format=$2
	local path="`mapping $1`"
	local version="`get_yangmodel_version`"	
	
	case $config-$format in
		config-startup-cdb)			
			echo "$path/CDB_$version.tgz"
		;;
		
		config-startup-xml|config-backup-xml|config-mirror-xml)
			echo "$path/config_$version.xml.tgz"
		;;
	esac
}

get_config_version() {
	local config=$1
	local path="`mapping $1`"
	
	case $config in
		config-startup)
			[ -f $path/$CONFIG_TARFILE -o -f $path/$CDB_FILE ] && {
				echo "0.0.0"
			} || {
				local version="`find $path/ -name config_*.tgz | sed -e 's|^.*_\([0-9.]\+[0-9]\).*$|\1|g'`"
				
				[ -n "$version" ] || {
					version="`find $path/ -name CDB_*.tgz | sed -e 's|^.*_\([0-9.]\+[0-9]\).*$|\1|g'`"
				}
				
				echo "$version"
			}
		;;
		
		config-backup|config-mirror)
			[ -f $path/$CONFIG_TARFILE ] && {
				echo "0.0.0"
			} || {
				echo "`find $path/ -name config_*.xml.tgz | sed -e 's|^.*_\([0-9.]\+[0-9]\).*$|\1|g'`"
			}
		;;
		
		yang)
			echo "`get_yangmodel_version`"
		;;
	esac
}

#==========================================================
__import_running_cdb() {
	local ret=1
	[ -f "$CONFIG_LOCK" ] || {
		touch $CONFIG_LOCK
		`$JSONCMD -l $1`
		ret=$?
		rm $CONFIG_LOCK
	}
	return $ret
}

__export_from_running_cdb() {
	`$JSONCMD -e $1`
	return $?
}

__export_from_startup_cdb() {
	`$JSONCMD -s -e $1`
	return $?
}

__export_from_cdb() { # 1: config-name 2: xml file
	local ret=1
	
	case $1 in
		config-running) 
			__export_from_running_cdb $2
			ret=$?
		;;
		config-startup)
			local src="`get_config_name $2 cdb`"
			
			[ -f $src ] && {
				__export_from_startup_cdb $2
				ret=$?
			}		
		;;
		*)
		;;
	esac
	
	return $ret
}

__export_from_xml() { # 1: config-name 2: xml file
	local ret=1

	case $1 in
		config-running) 
		;;
		
		config-startup|config-mirror|config-backup)
			local src="`get_config_name $1 xml`"
			
			[ -f $src ] && {
				tar zxf $src -C /tmp $CONFIG_FILE > /dev/null 2>&1
				ret=$?
				[ "$2" = "/tmp/$CONFIG_FILE"  ] || {
					mv /tmp/$CONFIG_FILE $2
					ret=$?
				}
				
			}		
		;;
		
		*)
		;;
	esac
	
	return $ret
}


__import_config() { # 1: xml file 2: config-name or file name
	local ret=1
	
	case $2 in
		config-running)
			__import_running_cdb $1
			ret=$?
			
			[ "$ret" = "0" ] && update_config_time "$2"
		;;
		
		config-startup|config-mirror|config-backup)
			local dst="`get_default_config_name $2 xml`"
			local dst_path="`mapping $2`"
			local config_name="`basename $1`"
			
			[ "$config_name" = "$CONFIG_FILE"  ] || mv $1 /tmp/$CONFIG_FILE
			
			rm -rf $dst_path/*			
			tar czf $dst -C /tmp $CONFIG_FILE > /dev/null 2>&1
			ret=$?
			
			[ "$ret" = "0" ] && update_config_time "$2"
		;;
		
		*)
		;;
	esac
	
	return $ret
}

__export_config() { # 1:config-name 2: xml file
	local ret=1

	case $1 in
		config-running)
			__export_from_cdb $1 $2
			ret=$?
		;;
		
		config-startup)
			__export_from_xml $1 $2
			ret=$?
			
			[ "$ret" = "0" ] || {
				__export_from_cdb $1 $2
				ret=$?
			}
		;;
		
		config-mirror|config-backup)
			__export_from_xml $1 $2
			ret=$?
		;;
		
		*)
		;;
	esac
	
	return $ret
}

__copy_config() { # 1:config-name 2:config-name
	local ret=1	
	local src_fmt="`format_mapping $1`"
	local dst_fmt="`format_mapping $2`"
	
	case "$src_fmt-$dst_fmt" in
		xml-xml|xml-cdb-backup)
			local src="`get_config_name $1 xml`"
			local dst="`get_default_config_name $2 xml`"
			local dst_path="`mapping $2`"
			
			rm -rf $dst_path/*
			cp $src $dst
			ret=$?
			
			[ "$ret" = "0" ] && update_config_time "$2"
		;;
		
		cdb-xml|xml-cdb)
			local tmp_src="/tmp/$CONFIG_FILE"
			
			rm -f $tmp_src
			__export_config $1 $tmp_src
			ret=$?
			
			[ -f $tmp_src ] && {
				__import_config $tmp_src $2
				ret=$?
				
				rm -f $tmp_src
			} || {
				ret=1
			}
		;;
		cdb-cdb-backup)
			local tmp_src="/tmp/$CDB_FILE"
			local dst="`get_default_config_name $2 cdb`"
			local dst_path="`mapping $2`"
			rm -rf $dst_path/*
			
			$JSONCMD -b
			
			$CONFD_BIN --cdb-backup $tmp_src
			ret=$?
			
			[ "$ret" = "0" ] && {
				mv $tmp_src $dst
				ret=$?
			}
			
			[ "$ret" = "0" ] && update_config_time "$2"
		;;
		
		cdb-backup-xml|cdb-backup-cdb)
			# Only Applicable when /confdConfig/datastores/startup/enabled = true
			local tmp_src="/tmp/$CONFIG_FILE"
			
			rm -f $tmp_src
			__export_config $1 $tmp_src
			ret=$?
			
			[ -f $tmp_src ] && {
				__import_config $tmp_src $2
				ret=$?
				
				rm -f $tmp_src
			} || {
				ret=1
			}
		;;
	esac
		
	return $ret
}

init_startup_config() {
	local startup="$1"
	local src="`get_default_config_name config-startup cdb`"
	local dst="$RUNNING_CONFIG"
	local src_config="`get_default_config_name config-startup xml`"
	
	# Extract Startup CDB file
	[ -f $src ] && {
		tar zxf $src -C $dst
	}
	
	[ -f $src_config ] && {
		tar zxf $src_config -C /tmp > /dev/null 2>&1
		rm -f $src_config > /dev/null 2>&1
		mv /tmp/$CONFIG_FILE /tmp/configuration/config_$startup.xml
		ln -sf /tmp/configuration/config_$startup.xml $STARTUP_CONFIG/$CONFIG_FILE
	}
}

save_nvram() {
	wps_nvram.sh save
}

copy_config() {
	logger -t ConfD "Copy $1 Configuration to $2 Configuration"

	__copy_config $1 $2
	errcode="$?"

	case "$1-$2" in
		config-running-config-startup)
			save_nvram
		;;	
	esac
}

export_config() {
	local src="`get_config_name $1 xml`"
	local dst="$2"

	logger -t ConfD "Export $1 Configuration to $2"

	if [ `echo $dst | grep "$FILE_CONFIG"` ];then
		# Delete previous file
		rm -rf $DOWNLOAD_CONFIG/*
		rm -rf $TMP_CONFIG/*

		save_dst=`echo $dst | sed s#"$FILE_CONFIG"#"$TMP_CONFIG"#g`
		ln_dst=`echo $dst | sed s#"$FILE_CONFIG"#"$DOWNLOAD_CONFIG"#g`
		`ln -s "$save_dst" "$ln_dst" >/dev/null 2>&1`
	elif [ `echo $dst | grep "$FILE_USB1"` ];then
		save_dst=`echo $dst | sed s#"$FILE_USB1"#"$MEDIA_USB1"#g`
	elif [ `echo $dst | grep "$FILE_USB2"` ];then
		save_dst=`echo $dst | sed s#"$FILE_USB2"#"$MEDIA_USB2"#g`
	elif [ `echo $dst | grep "$TMP_CONFIG\|MEDIA_USB1\|MEDIA_USB2"` ]; then
		save_dst=$dst
	fi

	[ -n "$save_dst" ] && {
		__export_config $1 $save_dst
		errcode="$?"
	} || {
		errcode=1
	}
}

import_config() {
	local src="$1"
	
	logger -t ConfD "Import $1 to $2 Configuration"

	if [ `echo $src | grep "$FILE_CONFIG"` ];then
		save_src=`echo $src | sed s#"$FILE_CONFIG"#"$TMP_CONFIG"#g`
	elif [ `echo $src | grep "$FILE_USB1"` ];then
		save_src=`echo $src | sed s#"$FILE_USB1"#"$MEDIA_USB1"#g`
	elif [ `echo $src | grep "$FILE_USB2"` ];then
		save_src=`echo $src | sed s#"$FILE_USB2"#"$MEDIA_USB2"#g`
	elif [ `echo $src | grep "$TMP_CONFIG\|MEDIA_USB1\|MEDIA_USB2"` ]; then
		save_src=$src
	fi
	
	[ -n "$save_src" ] && {
		__import_config $save_src $2
		errcode="$?"
	} || {
		errcode=1
	}
}

reset_config() {
	logger -t ConfD "Reset to Default Configuration"
	`rm -rf $RUNNING_CONFIG $STARTUP_CONFIG/*.* $BACKUP_CONFIG/*.* $MIRROR_CONFIG/*.* $CONFIG_DIR/$STATUS_FILE > /dev/null 2>&1`
	update_config_time "config-running" reset
	update_config_time "config-startup" reset
	update_config_time "config-backup" reset
	update_config_time "config-mirror" reset
	
	errcode=0
}

reset_statistics() {
	# reset mobile bandwidth statistics
	for if in $MOBILEIF; do
		`$MOBILERESTCMD interface-name $if > /dev/null 2>&1`
	done

	# clear download status
	`rm -f $DOWNLOADSTATUS`
}

reset_nvram() {
	wps_nvram.sh remove
}

get_datetime() {
	echo `date +%Y-%m-%dT%H:%M:%S`
}

init_status() {
	local src="$CONFIG_DIR/$STATUS_FILE"
	local dst="$RUNNING_CONFIG/$STATUS_FILE"
	
	[ -f $src ] && {
		cp $src $dst
	}
}

backup_status() {
	local src="$RUNNING_CONFIG/$STATUS_FILE"
	local dst="$CONFIG_DIR/$STATUS_FILE"
	
	[ -f $src ] && {
		cp $src $dst
	}
}

update_config_version() {
	local config="`uci_mapping $1`"
	[ "$config" = "running" ] && return
	
	local reset=0
	[ "$2" = "reset" ] && reset=1
	
	local image="`uci get firmware.firminfo.active 2> /dev/null`"
	local version="`uci get ciscosb-yang.$image.version 2> /dev/null`"
		
	[ "$reset" = "1" ] && {
		uci set ciscosb-yang.$config.version=
		uci commit ciscosb-yang
	} || {
		local curr_version="`uci get ciscosb-yang.$config.version 2> /dev/null`"
	
		[ -z "$curr_version" -o "$version" != "$curr_version" ] && {
			uci set ciscosb-yang.$config.version=$version
			uci commit ciscosb-yang
		}
	}
}

update_config_time() {
	local dst="`path_mapping $1`"
	local reset=0
	[ "$2" = "reset" ] && reset=1
	
	[ "$reset" = "1" ] && {
		$CONFD_CMD -o -c "delete $dst"
		backup_status
		update_config_version $1 reset
	} || {
		local time="`get_datetime`"
	
		[ -n "$dst" ] && {
			$CONFD_CMD -o -c "set $dst $time"
			backup_status
			update_config_version $1
		}
	
		if [ "$1" = "config-running" ]; then
			`cat /proc/uptime | cut -d " " -f1 | cut -d "." -f1 > $UPTIME_FILE`
			# change owner for webcache daemon to update uptime of running config
			`chown www-data:www-data $UPTIME_FILE`
		fi
	}
}

update_mirror_config() {
	local ctime=`cat /proc/uptime | cut -d " " -f1 | cut -d "." -f1`
	[ -f $UPTIME_FILE ] && {
		local rtime=`cat $UPTIME_FILE`
	}
	
	[ -n "$rtime" -a -n "$ctime" ] && {
		local during=`expr $ctime - $rtime`
	}
	
	[ -n "$during" ] && {
		[ $during -ge $UPDATE_MIRROR_TIME ] && {
			copy_config config-running config-mirror
			[ "$errcode" = 0 ] && `rm $UPTIME_FILE`
		}
	}
}

check_config() {  
	local pid="`uci get systeminfo.sysinfo.pid`"
	local config_pid="`get_config_header $1 pid`"
			
	#local upgrade="`check_config_version $1`"
	#local integrity="`check_config_integrity $1`"
	
	if [ ${pid} = ${config_pid} ]; then
		echo 1                     
	else          
		echo 0
	fi            
} 

upgrade_config() {
	local config=$1
	local config_src="$TMP_CONFIG/config-src.xml"
	local config_dst="$TMP_CONFIG/config-dst.xml"
	
	logger -t ConfD "Upgrade $1 Configuration to $2"
	
	case $config in
	config-startup)
		local src="`get_config_name $config xml`"
		
		[ -f $src ] && {
			__export_config $config $config_src
			[ "$?" = "0" ] && {
				`$JSONCMD --upgrade $config_src $config_dst`
				import_config $config_dst $config
			}
			
			rm -rf $config_src $config_dst
		} || {			
			local src="`get_config_name $config cdb`"
			local dst="`get_default_config_name $config cdb`"
			
			[ -f $src ] && mv $src $dst
		}
	;;
	
	config-running)
		__export_config $config $config_src
		[ "$?" = "0" ] && {
			#upgrade_config_010000 $config_src  $config_dst
			`$JSONCMD --upgrade $config_src $config_dst`
			#confd_cmd -c "upgrade fxs_active"
			import_config $config_dst $config
		}
		
		rm -rf $config_src $config_dst
	;;
	
	config-backup|config-mirror)
		__export_config $config $config_src		
		[ "$?" = "0" ] && {
			`$JSONCMD --upgrade $config_src $config_dst`
			import_config $config_dst $config
		}
		
		rm -rf $config_src $config_dst
	;;
	
	*)
		[ -f $1 -a -n "$2" ] && {
			`$JSONCMD --upgrade $1 $2`
		}
	;;
	esac	
}

init_config() {
	[ -d $RUNNING_CONFIG ] || mkdir -p $RUNNING_CONFIG

	[ -d $CONFIG_PART ] && {
		[ -d $STARTUP_CONFIG ] || mkdir -p $STARTUP_CONFIG
		[ -d $BACKUP_CONFIG ]  || mkdir -p $BACKUP_CONFIG
		[ -d $MIRROR_CONFIG ]  || mkdir -p $MIRROR_CONFIG
	}
	
	init_startup_config $startup
	
	init_status

	errcode=0
}


case "$TYPE" in
	init)
		init_config
	;;
	copy)
		copy_config "$SOURCE" "$DEST"
	;;
	export)
		export_config "$SOURCE" "$DEST"
	;;
	import)
		import_config "$SOURCE" "$DEST"
	;;
	factory-default|reset)
		reset_config
		reset_statistics
		reset_nvram
	;;
	timeupdate)
		update_config_time "$SOURCE"
	;;
	check)
		check_config "$SOURCE"
	;;
	mirrorupdate)
		update_mirror_config
	;;
	
	config-version)
		get_config_version "$2"
	;;
	
	upgrade)
		upgrade_config "$SOURCE" "$DEST"
	;;
	
	*)
		help
	;;
esac

return $errcode



