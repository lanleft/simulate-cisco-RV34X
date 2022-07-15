#!/bin/sh

# Flush all block rules for wireless interface

ebtables --concurrent -t broute -D BROUTING -p 0x800 -i wl+ --ip-src 192.168.1.0/24 --ip-proto icmp -j DROP
ebtables --concurrent -t broute -D BROUTING -p IPv4 -i wl+ --ip-proto tcp --ip-dport 53 -j DROP
ebtables --concurrent -t broute -D BROUTING -p IPv4 -i wl+ --ip-proto udp --ip-dport 53 -j DROP
ebtables -D FORWARD -i wl+ -o eth3+ -j DROP
