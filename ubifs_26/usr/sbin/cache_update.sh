#!/bin/sh
NUMPROC=5

LOAD_CONFIG="/usr/bin/confd_load"

modules="$@"

i=0
for config in $modules; do
	[ "$config" = "interfaces-state" ] && /usr/bin/reset-counters refresh

	[ -n $config ] && $LOAD_CONFIG -o -W -F n -p /$config /tmp/webcache/$config.json.tmp &
		
	i=`expr $i + 1`
	[ $i = $NUMPROC ] && { i=0; wait;}
done
	
[ $i != 0 ] && wait

for config in $modules; do
	mv /tmp/webcache/$config.json.tmp /tmp/webcache/$config.json
done
