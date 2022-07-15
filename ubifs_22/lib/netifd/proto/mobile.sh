#!/bin/sh

logger -t DEBUG "mobile. $0 $@"


. /lib/functions.sh
. ../netifd-proto.sh
. /lib/mobile/mobile-lib.sh
init_proto "$@"

INCLUDE_ONLY=1

ctl_device=""
dat_device=""

proto_mbim_setup() { echo "wwan[$$] mbim proto is missing"; }
proto_qmi_setup() { echo "wwan[$$] qmi proto is missing"; }
proto_ncm_setup() { echo "wwan[$$] ncm proto is missing"; }
proto_3g_setup() { echo "wwan[$$] 3g proto is missing"; }
proto_directip_setup() { echo "wwan[$$] directip proto is missing"; }
proto_hilink_setup() { echo "wwan[$$] hilink proto is missing"; }
proto_rndis_setup() { echo "wwan[$$] rndis proto is missing"; }

[ -f ./mbim.sh ] && . ./mbim.sh
[ -f ./ncm.sh ] && . ./ncm.sh
[ -f ./qmi.sh ] && . ./qmi.sh
[ -f ./3g.sh ] && { . ./ppp.sh; . ./3g.sh; }
[ -f ./directip.sh ] && . ./directip.sh
[ -f ./hilink.sh ] && . ./hilink.sh
[ -f ./rndis.sh ] && . ./rndis.sh

USBPORT1="usb3"
USBPORT2="usb1"

proto_mobile_init_config() {
        available=1
        no_device=1

        proto_config_add_boolean enable
        proto_config_add_string apn
        proto_config_add_string auth
        proto_config_add_string username
        proto_config_add_string password
        proto_config_add_string pincode
        proto_config_add_string delay
        proto_config_add_string modes
        proto_config_add_string dialnumber
        proto_config_add_string keepalive
        proto_config_add_string demand
}

huawei_port_detection() {
	local devicename=$1
	
	#^SETPORT:3:  3G DIAG
	#^SETPORT:10: 4G MODEM
	#^SETPORT:1:  3G MODEM
	#^SETPORT:12: 4G PCUI
	#^SETPORT:13: 4G DIAG
	#^SETPORT:5:  3G GPS
	#^SETPORT:14: 4G GPS
	#^SETPORT:A:  BLUETOOTH
	#^SETPORT:16: NCM
	#^SETPORT:A1: CDROM
	#^SETPORT:A2: SD
}

proto_mobile_setup() {
        local config="$1"
        local num
        local ret

        local driver usb devicename desc busnum
        local modemtype
	local vendor product  
	local ppp_ctl_device
	local ppp_dat_device
	
        json_get_var enable enable

        [ "$config" = "usb1" ] && { busnum=3; num=1; modem=/dev/modem1; }
        [ "$config" = "usb2" ] && { busnum=1; num=2; modem=/dev/modem2; }

        [ -d /sys/bus/usb/devices/$busnum-1/ ] || {
               echo "wwan[$$]" "No valid USB device was found"
               proto_notify_error "$config" NO_DEVICE
                proto_set_available "$config" 0
                return 1
        }
        # Update status by USB information
        mobile_update_usbinfo "$config"

        # Keeping a sleep because in some cases, device is not available when this is called.
        #logger -t mobile -p local0.info "$interface: Waiting for driver ready (5 s)"
        #sleep 5

        logger -t mobile -p local0.info "$interface: Detecting modem type."
        for a in `ls /sys/bus/usb/devices | grep $busnum-`; do
                  
                [ -z "$usb" -a -f /sys/bus/usb/devices/$a/idVendor -a -f /sys/bus/usb/devices/$a/idProduct ] || continue
                vendor=$(cat /sys/bus/usb/devices/$a/idVendor)
                product=$(cat /sys/bus/usb/devices/$a/idProduct)
                [ -f /lib/mobile/data/$vendor-$product ] && {
                        usb=/lib/mobile/data/$vendor-$product
                        devicename=$a
                }
        done

        [ -n "$usb" ] && {
                local old_cb control data

                json_set_namespace wwan old_cb
                json_init
                json_load "$(cat $usb)"
                json_select
                json_get_vars desc control data type delay
                json_set_namespace $old_cb

                case "$type" in
                3g)
                        modemtype=3G
                        [ -n "$control" -a -n "$data" ] && {
                                ttys=$(ls -d /sys/bus/usb/devices/$devicename/${devicename}*/tty* | sed "s/.*\///g" | tr "\n" " ")
                                ifname=3g-$config
                                ctl_device=/dev/$(echo $ttys | cut -d" " -f $((control + 1)))
                                dat_device=/dev/$(echo $ttys | cut -d" " -f $((data + 1)))
                                driver=comgt
                                proto=3g
                        }
                ;;
                qmi)
                        modemtype=4G
                        cdc_wdm=$(ls -d /sys/bus/usb/devices/$devicename/${devicename}*/usbmisc/cdc-wdm*)
                        ifname=$(ls /sys/bus/usb/devices/$devicename/${devicename}*/net)
                        [ -n "$cdc_wdm" ] && ctl_device=/dev/$(basename $cdc_wdm)
                        dat_device=$ifname

                        driver=$(grep DRIVER /sys/class/net/$ifname/device/uevent | cut -d= -f2)
                        proto=qmi
                ;;
                mbim)
                        modemtype=4G
                        cdc_wdm=$(ls -d /sys/bus/usb/devices/$devicename/${devicename}*/usbmisc/cdc-wdm*)
                        ifname=$(ls /sys/bus/usb/devices/$devicename/${devicename}*/net)
                        [ -n "$cdc_wdm" ] && ctl_device=/dev/$(basename $cdc_wdm)
                        dat_device=$ifname

                        driver=$(grep DRIVER /sys/class/net/$ifname/device/uevent | cut -d= -f2)
                        proto=mbim
                ;;
                ncm)
                        modemtype=4G
                        [ -n "$control" ] && {
                                ttys=$(ls -d /sys/bus/usb/devices/$devicename/${devicename}*/tty* | sed "s/.*\///g" | tr "\n" " ")
                                ifname=$(ls /sys/bus/usb/devices/$devicename/${devicename}*/net)
                                ctl_device=/dev/$(echo $ttys | cut -d" " -f $((control + 1)))
                                dat_device=$ifname

                                driver=$(grep DRIVER /sys/class/net/$ifname/device/uevent | cut -d= -f2)
                                proto=ncm
                        }
			
			# Fix for Huawei E3372 can not dial successfully
			# Huawei PPP modem
			#[ "$vendor" = "12d1" -a -n "$control" -a -n "$data" ] && {
			#	ppp_ctl_device=/dev/$(echo $ttys | cut -d" " -f $((control + 1)))
			#	ppp_dat_device=/dev/$(echo $ttys | cut -d" " -f $((data + 1)))
			#	driver=comgt
			#	proto=3g
			#}
                ;;
                directip)
                        modemtype=4G
                        [ -n "$control" ] && {
                                ttys=$(ls -d /sys/bus/usb/devices/$devicename/${devicename}*/tty* | sed "s/.*\///g" | tr "\n" " ")
                                ifname=$(ls /sys/bus/usb/devices/$devicename/${devicename}*/net)
                                ctl_device=/dev/$(echo $ttys | cut -d" " -f $((control + 1)))
                                dat_device=$ifname

                                driver=$(grep DRIVER /sys/class/net/$ifname/device/uevent | cut -d= -f2)
                                proto=directip
                        }
                ;;
                hilink)
                        modemtype=4G
                        ifname=$(ls /sys/bus/usb/devices/$devicename/${devicename}*/net)
                        ctl_device=$ifname
                        dat_device=$ifname

                        driver=$(grep DRIVER /sys/class/net/$ifname/device/uevent | cut -d= -f2)
                        proto=hilink
                ;;
                rndis)
                        modemtype=4G
                        ifname=$(ls /sys/bus/usb/devices/$devicename/${devicename}*/net)
                        ctl_device=$ifname
                        dat_device=$ifname

                        driver=$(grep DRIVER /sys/class/net/$ifname/device/uevent | cut -d= -f2)
                        proto=rndis
                ;;
                esac

                logger -t mobile -p local0.info "$interface: $desc detected ($type)"
                logger -t mobile -p local0.info "$interface:     control device=$ctl_device"
                logger -t mobile -p local0.info "$interface:     data device=$dat_device"
                logger -t mobile -p local0.info "$interface:     driver=$driver"
        } || {
                # TODO. Unknown dongle. detecting by driver
                logger -t mobile -p local0.error "$interface: Unknown modem (TBD)"
                return 1
        }

        mobile_update_attach_status "$num" "$devicename" "$modemtype" "1"

        [ -n "$ctl_device" ] || {
                logger -t mobile -p local0.error "$interface: No valid device was found"
                proto_notify_error "$interface" NO_DEVICE
                # proto_block_restart "$interface"
                return 1
        }

	[ -n "$ctl_device" -a -n "$modem" ] && ln -sf "$ctl_device" "$modem"

        #[ -n "$delay" ] && {
        #        logger -t mobile -p local0.info "$interface: Waiting for modem initialization ($delay s)"
        #        sleep "$delay"
        #}

        uci_set_state network $interface proto "$proto"
        uci_set_state network $interface driver "$driver"
        uci_set_state network $interface ctl_device "$ctl_device"
        uci_set_state network $interface dat_device "$dat_device"

        # Update Device Info
        [ "$proto" = "hilink" -o  "$proto" = "rndis" ] || mobile_update_devinfo $interface $proto

        [ "$enable" = "1" ] || {
                echo "wwan[$$]" "No valid device was found"
                proto_notify_error "$interface" DISABLED
                return 1
        }

        logger -t mobile -p local0.info "$interface: Starting mobile connection ($proto)"
        /etc/init.d/bwmgmt start $interface $ifname

        case $proto in
        3g)        proto_3g_setup $@ ;;
        qmi)       proto_qmi_setup $@ ;;
        mbim)      proto_mbim_setup $@ ;;
        directip)  proto_directip_setup $@ ;;
        ncm)       proto_ncm_setup $@ ;;
        hilink)    proto_hilink_setup $@ ;;
        rndis)     proto_rndis_setup $@ ;;
        esac

        ret=$?
	
        [ "$ret" = "0" ] || {
                logger -t mobile -p local0.info "$interface: connection ($proto) failed"
        } && {
                logger -t mobile -p local0.info "$interface: connection ($proto) success"
        }

        start-stop-daemon -S -b -m -p /var/run/mobile-$interface.pid -x mobile_daemon -- $interface $proto
	
        return $ret
}

proto_mobile_teardown() {
        local interface=$1

        [ "$interface" = "usb1" ] && { num=1; modem=/dev/modem1; }
        [ "$interface" = "usb2" ] && { num=2; modem=/dev/modem2; }

        local driver=$(uci_get_state network $interface driver)
        proto=$(uci_get_state network $interface proto)
        ctl_device=$(uci_get_state network $interface ctl_device)
        dat_device=$(uci_get_state network $interface dat_device)

        logger -t mobile -p local0.info "$interface: Stopping moblie connection ($proto)"
        start-stop-daemon  -K -q -s SIGTERM -n mobile_daemon -p /var/run/mobile-$interface.pid
        rm -rf /var/run/mobile-$interface.pid
	
        pid=`pgrep -f "/usr/bin/mobile_daemon $interface"`
        [ -n "$pid" ] && kill -9 $pid

        case $proto in
        3g)        proto_3g_teardown $@ ;;
        qmi)       proto_qmi_teardown $@ ;;
        mbim)      proto_mbim_teardown $@ ;;
        directip)  proto_directip_teardown $@ ;;
        ncm)       proto_ncm_teardown $@ ;;
        hilink)    proto_hilink_teardown $@ ;;
        rndis)     proto_rndis_teardown $@ ;;
        esac

        /etc/init.d/bwmgmt stop $interface
	
        return 0
}

add_protocol mobile