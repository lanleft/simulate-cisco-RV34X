#!/bin/sh

SERVERIP="192.168.8.1"
URL="http://$SERVERIP"
MOBILE_DIR="/tmp/mobile"
HILINK_DIR="$MOBILE_DIR/hilink"
COOKIES="$HILINK_DIR/cookies"
CSRF="$HILINK_DIR/csrf"

URL="http://$SERVERIP"
HOME_URL="$URL/html/index.html"
USERNAME="admin"
PASSWORD="admin"

CONN_TIMEOUT=5

[ -d $HILINK_DIR ] || mkdir -p $HILINK_DIR 

init () {
        curl -X GET -c $COOKIES -b $COOKIES $HOME_URL --silent --connect-timeout $CONN_TIMEOUT | grep csrf_token | sed "s/.* content=\"\(.*\)\".*/\1/" > "$CSRF"
}

gen_header_cookies () {
        local cookie

        [ -f $COOKIES ] && {
                cookie="`cat $COOKIES | grep SessionID | awk '{print $6 "=" $7}'`"
        }
        echo "$cookie"
}

gen_header_token() {
        local token

        [ -f $CSRF ] && {
                token=$(head -n 1 "$CSRF")
        }
        echo "$token"
}

curl_get() {
        local url=$1
        local cookie="`gen_header_cookies`"

        curl -X GET -c $COOKIES -b $COOKIES $url --silent --connect-timeout $CONN_TIMEOUT
}

curl_dial() {
        local url=$1
        local state=$2
        local cookie="`gen_header_cookies`"
        local token="`gen_header_token`"

         curl -X POST -c $COOKIES -b $COOKIES $url --silent --connect-timeout $CONN_TIMEOUT \
            -H "__RequestVerificationToken: $token" \
            -H "Content-type: application/x-www-form-urlencoded; charset=UTF-8" \
            --data "<?xml version='1.0' encoding='UTF-8'?><request><dataswitch>$state</dataswitch></request>"
}

curl_login() {
        local url=$1
        local username=$2
        local password=$3
        local cookie="`gen_header_cookies`"
        local token="`gen_header_token`"

        local encpassword=`echo -n "$password" | openssl dgst -hex -sha256 | awk '{print $2}' | tr -d '\n' | openssl base64 | tr -d '\n'`
        local hashpassword=`echo -n "$username$encpassword$token" | openssl dgst -hex -sha256 | awk '{print $2}' | tr -d '\n' | openssl base64 | tr -d '\n'`


         curl -X POST -c $COOKIES -b $COOKIES $url --silent --connect-timeout $CONN_TIMEOUT \
            -H "__RequestVerificationToken: $token" \
            -H "Content-type: application/x-www-form-urlencoded; charset=UTF-8" \
            --data "<?xml version='1.0' encoding='UTF-8'?><request><Username>$username</Username><Password>$hashpassword</Password><password_type>4</password_type></request>"
}

curl_logout() {
        local url=$1
        local cookie="`gen_header_cookies`"
        local token="`gen_header_token`"

         curl -X POST -c $COOKIES -b $COOKIES $url --silent --connect-timeout $CONN_TIMEOUT \
            -H "__RequestVerificationToken: $token" \
            -H "Content-type: application/x-www-form-urlencoded; charset=UTF-8" \
            --data "<?xml version='1.0' encoding='UTF-8'?><request><Logout>1</Logout></request>"
}

xml_get() {
        local xml=$1
        local tag=$2
        local val;

        val="`cat $xml | grep $tag | awk -F [\<\>] '{printf $3}'`"

        echo $val
}

hilink_login() {
        local username=$1
        local password=$2
        local url
        local xml="$HILINK_DIR/state-login.xml"
        local tag="State"
        local state=0

        url="$URL/api/user/state-login"
        curl_get $url > $xml
        
        [ -f $xml ] && state="`xml_get $xml $tag`"

        [ "$state" = "-1" ] && {
                [ -n "$username" ] || username="admin"
                [ -n "$password" ] || password="admin"

                url="$URL/api/user/login"
                curl_login $url $username $password
        }
}

hilink_logout() {
        local username=$1
        local password=$2
        local url
        local xml="$HILINK_DIR/state-login.xml"
        local tag="State"
        local state=0

        url="$URL/api/user/state-login"
        curl_get $url > $xml
        
        [ -f $xml ] && state="`xml_get $xml $tag`"

        [ "$state" = "0" ] && { 
                url="$URL/api/user/logout"
                curl_login $url
        }
}

dial() {
        local state=$1
        local url="$URL/api/dialup/mobile-dataswitch"

        curl_dial $url $state
}

get_dataswitch() {
        local url="$URL/api/dialup/mobile-dataswitch"
        local xml="$HILINK_DIR/dataswitch.xml"

        curl_get $url > $xml
}

get_device_information () {
        local url="$URL/api/device/information"
        local xml="$HILINK_DIR/device_information.xml"

        curl_get $url > $xml
}

get_basic_information () {
        local url="$URL/api/device/basic_information"
        local xml="$HILINK_DIR/basic_information.xml"

        curl_get $url > $xml
}

get_device_signal () {
        local url="$URL/api/device/signal"
        local xml="$HILINK_DIR/device_signal.xml"
        
        curl_get $url > $xml
}

get_net_plmn () {
        local url="$URL/api/net/current-plmn"
        local xml="$HILINK_DIR/net_plmn.xml"

        curl_get $url > $xml
}

get_status () {
        local url="$URL/api/monitoring/status"
        local xml="$HILINK_DIR/status.xml"

        curl_get $url > $xml
}

hilink_get_manufacturer() {
        echo "Huawei"
}

hilink_get_login() {
        local xml=$HILINK_DIR/state-login.xml
        local tag="dataswitch"
        [ -f $xml ] && xml_get $xml $tag
}

hilink_get_dataswitch() {
        local xml=$HILINK_DIR/dataswitch.xml
        local tag="dataswitch"
        [ -f $xml ] && xml_get $xml $tag
}

hilink_get_model() {
        local xml=$HILINK_DIR/basic_information.xml
        local tag="devicename"
	local value
        [ -f $xml ] && value=$(xml_get $xml $tag)
	
	if [ ! -n "$value" ]; then
		xml=$HILINK_DIR/device_information.xml
		tag="DeviceName"
		[ -f $xml ] && value=$(xml_get $xml $tag)
	fi
	
	echo $value
}

hilink_get_hwver() {
        local xml=$HILINK_DIR/device_information.xml
        local tag="HardwareVersion"
        [ -f $xml ] && xml_get $xml $tag
}

hilink_get_swver() {
        local xml=$HILINK_DIR/basic_information.xml
        local tag="SoftwareVersion"
        local value
        [ -f $xml ] && value=$(xml_get $xml $tag)
	
        if [ ! -n "$value" ]; then
		        xml=$HILINK_DIR/device_information.xml
		        tag="SoftwareVersion"
		        [ -f $xml ] && value=$(xml_get $xml $tag)
	    fi
	
        echo $value
}

hilink_get_sim_status() {
        local xml="$HILINK_DIR/status.xml"
        local tag="SimStatus"
        [ -f $xml ] && xml_get $xml $tag
}

hilink_get_imsi() {
        local xml=$HILINK_DIR/device_information.xml
        local tag="Imsi"
        [ -f $xml ] && xml_get $xml $tag
}

hilink_get_msisdn() {
        local xml=$HILINK_DIR/device_information.xml
        local tag="Msisdn"
        [ -f $xml ] && xml_get $xml $tag
}

hilink_get_carrier() {
        local xml="$HILINK_DIR/net_plmn.xml"
        local tag="FullName"
        [ -f $xml ] && xml_get $xml $tag
}

hilink_get_signal() {
        local xml="$HILINK_DIR/device_signal.xml"
        local tag="rssi"
        [ -f $xml ] && xml_get $xml $tag
}

hilink_get_wan_ip() {
        local xml="$HILINK_DIR/status.xml"
        local tag="WanIPAddress"
        [ -f $xml ] && xml_get $xml $tag
}

hilink_get_wan_dns1() {
        local xml="$HILINK_DIR/status.xml"
        local tag="PrimaryDns"
        [ -f $xml ] && xml_get $xml $tag
}

hilink_get_wan_dns2() {
        local xml="$HILINK_DIR/status.xml"
        local tag="SecondaryDns"
        [ -f $xml ] && xml_get $xml $tag
}

case "$1" in
--refresh)
        init
        hilink_login "$2" "$3"
        get_basic_information
        get_device_information
        get_device_signal
        get_net_plmn
        get_status
;;
--info)
        hilink_get_manufacturer
        hilink_get_model
        hilink_get_hwver
        hilink_get_swver
        hilink_get_imsi
        hilink_get_msisdn
        hilink_get_sim_status
        hilink_get_carrier
        hilink_get_signal
        hilink_get_wan_ip
        hilink_get_wan_dns1
        hilink_get_wan_dns2
;;
--get-model) hilink_get_model ;;
--get-manufacturer) hilink_get_manufacturer ;;
--get-hardware-version) hilink_get_hwver ;;
--get-software-version) hilink_get_swver ;;
--get-sim-status) hilink_get_sim_status ;;
--get-imsi) hilink_get_imsi ;;
--get-msisdn) hilink_get_msisdn ;;
--get-carrier) hilink_get_carrier ;;
--get-signal) hilink_get_signal ;;
--get-wan-ip) hilink_get_wan_ip ;;
--get-wan-dns1) hilink_get_wan_dns1 ;;
--get-wan-dns2) hilink_get_wan_dns2 ;;
--connect)
        init
        dial 1
;;

--disconnect)
        init
        dial 0
;;

--login)
        init
        hilink_login "$2" "$3"
;;

--logout)
	init
	hilink_logout
;;

--help|*)
	echo "hilink.sh command [arguments]"
	echo "Commands:"
	echo "        --connect"
	echo "        --disconnect"
	echo "        --login <username> <password>"
	echo "        --logout"
	echo ""
	echo "        --refresh"
	echo "        --info"
	echo "        --get-model"
	echo "        --get-manufacturer"
	echo "        --get-hardware-version"
	echo "        --get-software-version"
	echo "        --get-sim-status"
	echo "        --get-imsi"
	echo "        --get-msisdn"
	echo "        --get-carrier"
	echo "        --get-signal"
	echo "        --get-wan-ip"
	echo "        --get-wan-dns1"
	echo "        --get-wan-dns2"
;;
esac