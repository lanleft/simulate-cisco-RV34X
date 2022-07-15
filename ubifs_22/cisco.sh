#!/bin/sh

/etc/init.d/boot boot
generate_default_cert
/etc/init.d/confd start
/etc/init.d/nginx start
/etc/init.d/pnpd start
