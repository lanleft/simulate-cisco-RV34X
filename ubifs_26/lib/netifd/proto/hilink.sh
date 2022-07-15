#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
        . /lib/functions.sh
        . ../netifd-proto.sh
        init_proto "$@"
}

proto_hilink_init_config() {
        available=1
        no_device=1
        proto_config_add_string metric
}

proto_hilink_setup() {
        local interface="$1"
        local metric

        [ -n "$ctl_device" ] && device=$ctl_device        

        json_get_vars metric

        ifname=$device

        [ -n "$ifname" ] || {
		logger -t mobile -p local0.error "$interface: The interface could not be found."
		proto_notify_error "$interface" NO_IFNAME
		proto_set_available "$interface" 0
		return 1
        }

        logger -t mobile -p local0.debug "$interface: Starting DHCP"
        proto_init_update "$ifname" 1
        proto_send_update "$interface"

        json_init
        json_add_string name "${interface}_4"
        json_add_string ifname "@$interface"
        json_add_string proto "dhcp"
        json_add_int metric $metric
        json_close_object
        ubus call network add_dynamic "$(json_dump)"

        return 0
}

proto_hilink_teardown() {
        local interface="$1"

        proto_init_update "*" 0
        proto_send_update "$interface"

        proto_kill_command "$interface"
}

[ -n "$INCLUDE_ONLY" ] || {
    add_protocol hilink
}
