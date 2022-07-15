#!/bin/sh

# Rules to block internet & other client access

ebtables -I FORWARD -i wl+ -o eth3+ -j DROP
ebtables --concurrent -t broute -I BROUTING -p IPv4 -i wl+ --ip-proto udp --ip-dport 53 -j DROP
ebtables --concurrent -t broute -I BROUTING -p IPv4 -i wl+ --ip-proto tcp --ip-dport 53 -j DROP
ebtables --concurrent -t broute -I BROUTING -p 0x800 -i wl+ --ip-src 192.168.1.0/24 --ip-proto icmp -j DROP
