# USB_STATUS in "USBx:dev_device:mount_point:type:status" format
USB_CONN_STATUS=/var/USBCONNSTATUS
DEVMODEM=/dev/modem
USB_NUM=

USBPORT1="usb3"
USBPORT2="usb1"

proto_add_dynamic_defaults() {                                                 
        [ -n "$defaultroute" ] && json_add_boolean defaultroute "$defaultroute"
        [ -n "$peerdns" ] && json_add_boolean peerdns "$peerdns"
        [ -n "$metric" ] && json_add_int metric "$metric"
}

dev2num() {
        local devpath=$1
        local tmp
        tmp="`echo $devpath | grep $USBPORT1`"
        [ -n "$tmp" ] && echo "1"
        tmp="`echo $devpath | grep $USBPORT2`"
        [ -n "$tmp" ] && echo "2"
        echo "$num"
}

dev2iface() {
        local devpath=$1
        local num=`dev2num $1`
        [ -n "$num" ] && echo "usb$num"
}

update_mobile_usb() {
        local modem="$1"
        # usb
        local manufacturer="$2"
        local product="$3"

        local path="/usb-modems-state/usb-modem{$modem}"

        [ -n "$exist" ] || exist=`/usr/bin/confd_cmd -o -c "exists $path"`
        [ "$exist" = "no" ] && /usr/bin/confd_cmd -o -c "create $path"

        [ -n "$manufacturer" ] && /usr/bin/confd_cmd -o -c "set $path/manufacture \"$manufacturer\""
        [ -n "$product" ] && /usr/bin/confd_cmd -o -c "set $path/card-model \"$product\""
}

update_mobile_modem() {
        local modem="$1"
        # modem
        local service_name="$2"
        local firmware_version="$3"
        local sim_status="$4"
        local imsi="$5"

        local path="/usb-modems-state/usb-modem{$modem}"

        [ -n "$exist" ] || exist=`/usr/bin/confd_cmd -o -c "exists $path"`
        [ "$exist" = "no" ] && /usr/bin/confd_cmd -o -c "create $path"

        [ -n "$service_name" ] && /usr/bin/confd_cmd -o -c "set $path/network-mode \"$service_name\""
        [ -n "$firmware_version" ] && /usr/bin/confd_cmd -o -c "set $path/firmware-version \"$firmware_version\""
        [ -n "$sim_status" ] && /usr/bin/confd_cmd -o -c "set $path/sim-status \"$sim_status\""
        [ -n "$imsi" ] && /usr/bin/confd_cmd -o -c "set $path/imsi \"$imsi\""
}

update_mobile_signal() {
        local modem="$1"
        # modem
        local carrier="$2"
        local sig_strength="$3"

        local path="/usb-modems-state/usb-modem{$modem}"

        [ -n "$exist" ] || exist=`/usr/bin/confd_cmd -o -c "exists $path"`
        [ "$exist" = "no" ] && /usr/bin/confd_cmd -o -c "create $path"

        [ -n "$carrier" ] && /usr/bin/confd_cmd -o -c "set $path/carrier \"$carrier\""
        [ -n "$sig_strength" ] && /usr/bin/confd_cmd -o -c "set $path/signal-strength \"$sig_strength\""
}

update_mobile() {
        local action="$1"
        local modem="$2"
        # usb
        local manufacturer="$3"
        local product="$4"
        # modem
        local service_name="$5"
        local firmware_version="$6"
        local sim_status="$7"
        local imsi="$8"
        # signal
        local carrier="$9"
        local sig_strength="$10"

        local path="/usb-modems-state/usb-modem{$modem}"

        if [ "$action" = "add" ]; then
                update_mobile_usb "$device" "$manufacturer" "$product"
                update_mobile_modem "$device" "$service_name" "$firmware_version" "$sim_status" "$imsi"
                update_mobile_signal "$device" "$carrier" "$sig_strength"
        elif [ "$action" = "del" ]; then
                /usr/bin/confd_cmd -o -c "del $path"
        fi
}

update_3g_devinfo() {
        local interface="$1"
        local modem;

        [ -n "$modem" ] || {
                [ "$interface" = "usb1" ] && { modem=/dev/modem1; }
                [ "$interface" = "usb2" ] && { modem=/dev/modem2; }
        }
        local cmd="gcom -d $modem"

        # Get all the required statistics
        # Manufacture & Firmware
        `$cmd info > /tmp/stats/3g/MANUFACTURE_$interface` >/dev/null 2>&1

        # SIM STATUS
        `$cmd PIN > /tmp/stats/3g/PIN_$interface` >/dev/null 2>&1

        # IMSI
        `$cmd -s /etc/gcom/getimsi.gcom > /tmp/stats/3g/IMSI_$interface` >/dev/null 2>&1

        # Carrier
        `$cmd -s /etc/gcom/getcarrier.gcom > /tmp/stats/3g/CARRIER_$interface` >/dev/null 2>&1

        # Service Type
        `$cmd -s /etc/gcom/getservicetype.gcom > /tmp/stats/3g/SERVICE_$interface` >/dev/null 2>&1

        # Signal Strength
        `$cmd sig > /tmp/stats/3g/STRENGTH_$interface` >/dev/null 2>&1

        # If apn is null, get from ISP
        if [ -z "$apn" ];then
                apn=`cat /tmp/stats/3g/MANUFACTURE_$interface | grep APN: | cut -d , -f 3 | sed -e 's/"//g'`
                [ -z "$apn" ] && apn="internet"
        fi

        # Update the 3G statistics
        service_name="3G"
        manufacturer=`cat /tmp/stats/3g/MANUFACTURE_$interface | grep Manufacturer: | head -n 1 | cut -d : -f 2 |  sed "s/[\r\n]*//g" | sed -e "s/^ *//g"` >/dev/null 2>&1
        product=`cat /tmp/stats/3g/MANUFACTURE_$interface | grep Model: | head -n 1 | cut -d : -f 2 |  sed "s/[\r\n]*//g" | sed -e "s/^ *//g"` >/dev/null 2>&1
        firmware=`cat /tmp/stats/3g/MANUFACTURE_$interface | grep Revision: | head -n 1 | cut -d : -f 2 | sed "s/[\r\n]*//g" | sed -e "s/^ *//g"` >/dev/null 2>&1
        sim_status=`cat /tmp/stats/3g/PIN_$interface` >/dev/null 2>&1
        imsi=`cat /tmp/stats/3g/IMSI_$interface` >/dev/null 2>&1

        signal=`cat /tmp/stats/3g/STRENGTH_$interface | grep "Signal Quality:" | cut -d : -f 2 | cut -d , -f 1 | sed -e "s/^ *//g"` >/dev/null 2>&1
        if [ -n "$signal" ];then
                case $signal in
                        99)
                                sig_strength="not known"
                        ;;
                        [3-9][1-9])
                                sig_strength="> -51 dBm"
                        ;;
                        *)
                                sig_strength=`cat /etc/gcom/3g_signallist | grep "^$signal:" | cut -d : -f 2 | cut -d " " -f 1` >/dev/null 2>&1
                        ;;
                esac
        else
                sig_strength=
        fi
        sig_strength=`echo $sig_strength | sed "s/[a-z,A-Z,\>,\ ]//g"`

        carrier=`cat /tmp/stats/3g/CARRIER_$interface | grep COPS: | cut -d , -f 3 | sed -e 's/"//g'` >/dev/null 2>&1

        [ -n "$carrier" ] || carrier=`echo $imsi | cut -c 1-5` >/dev/null 2>&1

        if [ -n "$carrier" -a "`echo $carrier | sed s/[0-9]//g`" = "" ]; then
                carrier=`cat /etc/gcom/3g_carrierlist | grep "$carrier" | cut -d : -f 1` >/dev/null 2>&1
        fi

        case $carrier in 
                *FFFFFFFF*)
                        carrier="Unknown"
                ;;
        esac

        update_mobile_usb "$modem" "$manufacturer" "$product"
        update_mobile_modem "$modem" "$service_name" "$firmware" "$sim_status" "$imsi"
        update_mobile_signal "$modem" "$carrier" "$sig_strength"
}

update_3g_signal() {
        local interface="$1"
        local modem;

        [ -n "$modem" ] || {
                [ "$interface" = "usb1" ] && { modem=/dev/modem1; }
                [ "$interface" = "usb2" ] && { modem=/dev/modem2; }
        }
        local cmd="gcom -d $modem"

        # Carrier
        `$cmd -s /etc/gcom/getcarrier.gcom > /tmp/stats/3g/CARRIER_$interface` >/dev/null 2>&1

        # Signal Strength
        `$cmd sig > /tmp/stats/3g/STRENGTH_$interface` >/dev/null 2>&1

        # IMSI
        `$cmd -s /etc/gcom/getimsi.gcom > /tmp/stats/3g/IMSI_$interface` >/dev/null 2>&1
	
        signal=`cat /tmp/stats/3g/STRENGTH_$interface | grep "Signal Quality:" | cut -d : -f 2 | cut -d , -f 1 | sed -e "s/^ *//g"` >/dev/null 2>&1
        if [ -n "$signal" ];then
                case $signal in
                99)
                        sig_strength="not known"
                ;;
                [3-9][1-9])
                        sig_strength="> -51 dBm"
                ;;
                *)
                        sig_strength=`cat /etc/gcom/3g_signallist | grep "^$signal:" | cut -d : -f 2 | cut -d " " -f 1` >/dev/null 2>&1
                ;;
                esac
        else
                sig_strength=
        fi
        sig_strength=`echo $sig_strength | sed "s/[a-z,A-Z,\>,\ ]//g"`

        imsi=`cat /tmp/stats/3g/IMSI_$interface` >/dev/null 2>&1

        carrier=`cat /tmp/stats/3g/CARRIER_$interface | grep COPS: | cut -d , -f 3 | sed -e 's/"//g'` >/dev/null 2>&1

        [ -n "$carrier" ] || carrier=`echo $imsi | cut -c 1-5` >/dev/null 2>&1

        if [ -n "$carrier" -a "`echo $carrier | sed s/[0-9]//g`" = "" ]; then
                carrier=`cat /etc/gcom/3g_carrierlist | grep "$carrier" | cut -d : -f 1` >/dev/null 2>&1
        fi

        case $carrier in 
                *FFFFFFFF*)
                        carrier="Unknown"
                ;;
        esac

        update_mobile_signal "$modem" "$carrier" "$sig_strength"
}

update_ncm_devinfo() {
        local interface="$1"
        local modem

        [ -n "$modem" ] || {
                [ "$interface" = "usb1" ] && { modem=/dev/modem1; }
                [ "$interface" = "usb2" ] && { modem=/dev/modem2; }
        }
        local cmd="gcom -d $modem"

        # Get all the required statistics

        # Manufacture & Firmware
        `$cmd info > /tmp/stats/4g/MANUFACTURE_$interface` >/dev/null 2>&1

        # IMSI
        `$cmd -s /etc/gcom/getimsi.gcom > /tmp/stats/4g/IMSI_$interface` >/dev/null 2>&1

        # Carrier
        `$cmd -s /etc/gcom/getcarrier.gcom > /tmp/stats/4g/CARRIER_$interface` >/dev/null 2>&1

        # Service Type
        `$cmd -s /etc/gcom/getservicetype.gcom > /tmp/stats/4g/SERVICE_$interface` >/dev/null 2>&1

        # SIM STATUS
        `$cmd PIN > /tmp/stats/4g/PIN_$interface` >/dev/null 2>&1

        # Signal Strength
        `$cmd sig > /tmp/stats/4g/STRENGTH_$interface` >/dev/null 2>&1

        # If apn is null, get from ISP
        if [ -z "$apn" ];then
                apn=`cat /tmp/stats/4g/MANUFACTURE_$interface | grep APN: | cut -d , -f 3 | sed -e 's/"//g'`
                [ -z "$apn" ] && apn="internet"
        fi

        # Update the NCM statistics
        service_name="4G"
        manufacturer=`cat /tmp/stats/4g/MANUFACTURE_$interface | grep Manufacturer: | head -n 1 | cut -d : -f 2 |  sed "s/[\r\n]*//g" | sed -e "s/^ *//g"` >/dev/null 2>&1
        product=`cat /tmp/stats/4g/MANUFACTURE_$interface | grep Model: | head -n 1 | cut -d : -f 2 |  sed "s/[\r\n]*//g" | sed -e "s/^ *//g"` >/dev/null 2>&1
        firmware=`cat /tmp/stats/4g/MANUFACTURE_$interface | grep Revision: | head -n 1 | cut -d : -f 2 | sed "s/[\r\n]*//g" | sed -e "s/^ *//g"` >/dev/null 2>&1
        sim_status=`cat /tmp/stats/4g/PIN_$interface` >/dev/null 2>&1
        imsi=`cat /tmp/stats/4g/IMSI_$interface` >/dev/null 2>&1

        signal=`cat /tmp/stats/4g/STRENGTH_$interface | grep "Signal Quality:" | cut -d : -f 2 | cut -d , -f 1 | sed -e "s/^ *//g"` >/dev/null 2>&1
        if [ -n "$signal" ];then
                case $signal in
                99)
                sig_strength="not known"
                ;;
                [3-9][1-9])
                sig_strength="> -51 dBm"
                ;;
                *)
                sig_strength=`cat /etc/gcom/3g_signallist | grep "^$signal:" | cut -d : -f 2 | cut -d " " -f 1` >/dev/null 2>&1
                ;;
                esac
        else
                sig_strength=
        fi
        sig_strength=`echo $sig_strength | sed "s/[a-z,A-Z,\>,\ ]//g"`

        carrier=`cat /tmp/stats/4g/CARRIER_$interface | grep COPS: | cut -d , -f 3 | sed -e 's/"//g'` >/dev/null 2>&1
        [ -n "$carrier" ] || carrier=`echo $imsi | cut -c 1-5` >/dev/null 2>&1

        if [ -n "$carrier" -a "`echo $carrier | sed s/[0-9]//g`" = "" ]; then
                carrier=`cat /etc/gcom/3g_carrierlist | grep "$carrier" | cut -d : -f 1` >/dev/null 2>&1
        fi

        case $carrier in 
                *FFFFFFFF*)
                        carrier="Unknown"
                ;;
        esac

        update_mobile_usb "$modem" "$manufacturer" "$product"
        update_mobile_modem "$modem" "$service_name" "$firmware" "$sim_status" "$imsi"
        update_mobile_signal "$modem" "$carrier" "$sig_strength"
}

update_ncm_signal() {
        local interface="$1"
        local modem

        [ -n "$modem" ] || {
                [ "$interface" = "usb1" ] && { modem=/dev/modem1; }
                [ "$interface" = "usb2" ] && { modem=/dev/modem2; }
        }
        local cmd="gcom -d $modem"

        # Carrier
        `$cmd -s /etc/gcom/getcarrier.gcom > /tmp/stats/4g/CARRIER_$interface` >/dev/null 2>&1

        # Signal Strength
        `$cmd sig > /tmp/stats/4g/STRENGTH_$interface` >/dev/null 2>&1

        signal=`cat /tmp/stats/4g/STRENGTH_$interface | grep "Signal Quality:" | cut -d : -f 2 | cut -d , -f 1 | sed -e "s/^ *//g"` >/dev/null 2>&1
        if [ -n "$signal" ];then
                case $signal in
                99)
                sig_strength="not known"
                ;;
                [3-9][1-9])
                sig_strength="> -51 dBm"
                ;;
                *)
                sig_strength=`cat /etc/gcom/3g_signallist | grep "^$signal:" | cut -d : -f 2 | cut -d " " -f 1` >/dev/null 2>&1
                ;;
                esac
        else
                sig_strength=
        fi
        sig_strength=`echo $sig_strength | sed "s/[a-z,A-Z,\>,\ ]//g"`

        carrier=`cat /tmp/stats/4g/CARRIER_$interface | grep COPS: | cut -d , -f 3 | sed -e 's/"//g'` >/dev/null 2>&1
        [ -n "$carrier" ] || carrier=`echo $imsi | cut -c 1-5` >/dev/null 2>&1

        if [ -n "$carrier" -a "`echo $carrier | sed s/[0-9]//g`" = "" ]; then
                carrier=`cat /etc/gcom/3g_carrierlist | grep "$carrier" | cut -d : -f 1` >/dev/null 2>&1
        fi

        case $carrier in 
                *FFFFFFFF*)
                        carrier="Unknown"
                ;;
        esac

        update_mobile_signal "$modem" "$carrier" "$sig_strength"
}

update_qmi_devinfo() {
        local interface="$1"

        [ -n "$modem" ] || {
                [ "$interface" = "usb1" ] && { modem=/dev/modem1; }
                [ "$interface" = "usb2" ] && { modem=/dev/modem2; }
        }
        local cmd="qmicli -d $modem"

        service_name="4G"

        firmware=`$cmd --dms-get-revision | grep "Revision" | cut -d : -f 2- | sed -e "s/^ *//g" | sed -e "s/'//g"`>/dev/null 2>&1
        sim_status=`$cmd --dms-uim-get-state | grep "State" | cut -d : -f 2- | sed -e "s/^ *//g" | sed -e "s/'//g"` >/dev/null 2>&1
        imsi=`$cmd --dms-uim-get-imsi | grep "IMSI:" | cut -d : -f 2- | sed -e "s/^ *//g" | sed -e "s/'//g"` >/dev/null 2>&1

        carrier=`$cmd --nas-get-home-network | grep Description: | cut -d : -f 2- | sed -e "s/^ *//g" | sed -e "s/'//g"` >/dev/null 2>&1
        sig_strength=`$cmd --nas-get-signal-strength | awk '/Current:/{getline; print}' | cut -d : -f 2 | sed -e "s/^ *//g" | sed -e "s/'//g" | cut -d " " -f 1` >/dev/null 2>&1

        # update_mobile_usb "$modem" "$manufacturer" "$product"
        update_mobile_modem "$modem" "$service_name" "$firmware" "$sim_status" "$imsi"
        update_mobile_signal "$modem" "$carrier" "$sig_strength"
}

update_qmi_signal() {
        local interface="$1"

        [ -n "$modem" ] || {
                [ "$interface" = "usb1" ] && { modem=/dev/modem1; }
                [ "$interface" = "usb2" ] && { modem=/dev/modem2; }
        }
        local cmd="qmicli -d $modem"

        carrier=`$cmd --nas-get-home-network | grep Description: | cut -d : -f 2- | sed -e "s/^ *//g" | sed -e "s/'//g"` >/dev/null 2>&1
        sig_strength=`$cmd --nas-get-signal-strength | awk '/Current:/{getline; print}' | cut -d : -f 2 | sed -e "s/^ *//g" | sed -e "s/'//g" | cut -d " " -f 1` >/dev/null 2>&1

        update_mobile_signal "$modem" "$carrier" "$sig_strength"
}


update_hilink_devinfo() {
        local interface="$1"
        local cmd="/usr/sbin/hilink.sh"
        local username
        local password

        [ -n "$modem" ] || {
                [ "$interface" = "usb1" ] && { modem=/dev/modem1; }
                [ "$interface" = "usb2" ] && { modem=/dev/modem2; }
        }

        username="`uci get network.$interface.username` >/dev/null 2>&1"
        password="`uci get network.$interface.password` >/dev/null 2>&1"

        `$cmd --refresh $username $password`

        local sim_state=`$cmd --get-sim-status`

        service_name="4G"

        manufacturer=`$cmd --get-manufacturer`
        product=`$cmd --get-model`

        firmware=`$cmd --get-software-version`
        imsi=`$cmd --get-imsi`
        sim_state=`$cmd --get-sim-status`
        [ "$sim_state" = "1" ] && sim_status="SIM ready" || sim_status="SIM error"

        carrier=`$cmd --get-carrier`
        sig_strength=`$cmd --get-signal`
        sig_strength=`echo $sig_strength | sed "s/[a-z,A-Z,\>,\ ]//g"`

        update_mobile_usb "$modem" "$manufacturer" "$product"
        update_mobile_modem "$modem" "$service_name" "$firmware" "$sim_status" "$imsi"
        update_mobile_signal "$modem" "$carrier" "$sig_strength"
}

update_hilink_signal() {
        update_hilink_devinfo $1
}

mobile_update_attach_status() {                
        local num="$1"                                                
        local devname="$2"                                            
        local type="$3"                                      
        local status="$4"                                                             

        local output="$USB_CONN_STATUS"                                        
        local ifname="USB$num"                                  
        local modem="$DEVMODEM$num"                                               
        local interface="usb$num"                                                 
        local usbconnstatus                                                       
        local detected                  
        local exist                                                   
                                                                      
        local path="/usb-modems-state/usb-modem{$modem}"              
                                                                                      
        usbconnstatus="`cat $output | grep "^$ifname"`"                               
                                                                                      
        if [ "$status" = "1" ]; then                            
                [ -n "$usbconnstatus" ] && {
                        `sed -i "/^$ifname/d" $output`
                }                           
                echo "$ifname:$devname:$modem:$type:1" >> $output
                               
                # Update confd CDB                               
                exist=`/usr/bin/confd_cmd -o -c "exists $path"`
                [ "$exist" = "no" ] && {                
                        logger -t mobile -p local0.info "$interface: $type modem attached."
                        /usr/bin/confd_cmd -o -c "create $path"
                }                                                                          
        else                                                   
                [ -n "$usbconnstatus" ] && {
                        `sed -i "/^$ifname:/c\$ifname::::0" $output`
                }                                       
                                                                    
                # Update confd CDB                                        
                exist=`/usr/bin/confd_cmd -o -c "exists $path"`       
                [ "$exist" = "yes" ] && {                      
                        logger -t mobile -p local0.info "$interface: $type modem removed."          
                        /usr/bin/confd_cmd -o -c "del $path"                               
                }                                                                          
        fi                                                     
}          

mobile_update_usbinfo() {
        local interface="$1"
        local devicename
        local devpath
        local modem

        [ "$interface" = "usb1" ] && { devicename="3-1"; modem=/dev/modem1; }
        [ "$interface" = "usb2" ] && { devicename="1-1"; modem=/dev/modem2; }
        [ -n "$devicename" ] || return 1

        local idvendor idproduct
        local manufacturer product

        devpath="/sys/bus/usb/devices/$devicename"

        [ -d $devpath ] && {
                idvendor=$(cat $devpath/idVendor)
                idproduct=$(cat $devpath/idProduct)
                manufacturer=$(cat $devpath/manufacturer)
                product=$(cat $devpath/product)
        }

        logger -t mobile -p local0.info "$interface: Updating USB Info ($idvendor:$idproduct)"
        logger -t mobile -p local0.info "$interface:     manufacturer= $manufacturer" 
        logger -t mobile -p local0.info "$interface:     model=        $product"

        update_mobile_usb "$modem" "$manufacturer" "$product"
}

mobile_update_devinfo() {
        local interface="$1"
        local proto="$2"
        local modem

        [ "$interface" = "usb1" ] && { devicename="3-1"; modem=/dev/modem1; }
        [ "$interface" = "usb2" ] && { devicename="1-1"; modem=/dev/modem2; }
        [ -n "$devicename" ] || return 1

        local driver_version
        local manufacturer product
        local service_name firmware sim_status imsi
        local carrier sig_strength

        driver_version=`cat /etc/usb-modem.ver`

        devpath="/sys/bus/usb/devices/$devicename"
        [ -d $devpath ] && {
                manufacturer=$(cat $devpath/manufacturer)
                product=$(cat $devpath/product)
        }

        ctl_device=$(uci_get_state network $interface ctl_device)

        [ -n "$ctl_device" ] && device=$ctl_device
        logger -t mobile -p local0.info "$interface: Updating Device Info ($device):"

        case $proto in
        3g)        update_3g_devinfo $interface;;
        qmi)       update_qmi_devinfo $interface;;
        mbim)      update_mbim_devinfo $interface;;
        ncm)       update_ncm_devinfo $interface;;
        directip)  update_ncm_devinfo $interface;;
        hilink)    update_hilink_devinfo $interface;;
        esac

        logger -t mobile -p local0.info "$interface:     driver_version= $driver_version"
        logger -t mobile -p local0.info "$interface:     manufacturer=   $manufacturer"
        logger -t mobile -p local0.info "$interface:     model=          $product"
        logger -t mobile -p local0.info "$interface:     service_name=   $service_name"
        logger -t mobile -p local0.info "$interface:     firmware=       $firmware"
        logger -t mobile -p local0.info "$interface:     imsi=           $imsi"
        logger -t mobile -p local0.info "$interface:     sim_status=     $sim_status"
        logger -t mobile -p local0.info "$interface:     carrier=        $carrier"
        logger -t mobile -p local0.info "$interface:     sig_strength=   $sig_strength"
}

mobile_update_signal() {
        local interface="$1"
        local proto="$2"
        local modem

        [ "$interface" = "usb1" ] && { devicename="3-1"; modem=/dev/modem1; }
        [ "$interface" = "usb2" ] && { devicename="1-1"; modem=/dev/modem2; }
        [ -n "$devicename" ] || return 1

        local carrier sig_strength

        ctl_device=$(uci_get_state network $interface ctl_device)

        [ -n "$ctl_device" ] && device=$ctl_device

        case $proto in
        3g)        update_3g_signal $interface;;
        qmi)       update_qmi_signal $interface;;
        mbim)      update_mbim_signal $interface;;
        ncm)       update_ncm_signal $interface;;
        directip)  update_ncm_signal $interface;;
        hilink)    update_hilink_signal $interface;;
        esac

        #logger -t mobile -p local0.info "$interface:     carrier=        $carrier"
        #logger -t mobile -p local0.info "$interface:     sig_strength=   $sig_strength"
}