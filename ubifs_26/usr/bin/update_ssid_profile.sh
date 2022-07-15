#!/bin/sh
orig_ssid="`echo $1 | sed -r 's/\\\\/\\\\\\\\/g' | sed -r 's/\\"/\\\\\\"/g'`"
ssid="`echo $2 | sed -r 's/\\\\/\\\\\\\\/g' | sed -r 's/\\"/\\\\\\"/g'`"
radio="$3"
security="$4"
passphrase="`echo $5 | sed -r 's/\\\\/\\\\\\\\/g' | sed -r 's/\\"/\\\\\\"/g'`"

if [ "$orig_ssid" == "$ssid" ]; then
if [ "$security" == "None" ]; then
echo -e "configure
set wlans ssid "\"$ssid\"" $radio security mode-enabled $security
commit
quit" > /tmp/update_ssid_profile
else
echo -e "configure
set wlans ssid "\"$ssid\"" $radio security mode-enabled $security $security key-passphrase "\"$passphrase\""
commit
quit" > /tmp/update_ssid_profile
fi
else
if [ "$security" == "None" ]; then
echo -e "configure
rename wlans ssid "\"$orig_ssid\"" $radio "\"$ssid\"" $radio
set wlans ssid "\"$ssid\"" $radio security mode-enabled $security
commit
quit" > /tmp/update_ssid_profile
else
echo -e "configure
rename wlans ssid "\"$orig_ssid\"" $radio "\"$ssid\"" $radio
set wlans ssid "\"$ssid\"" $radio security mode-enabled $security $security key-passphrase "\"$passphrase\""
commit
quit" > /tmp/update_ssid_profile
fi
fi
confd_cli -u admin --noninteractive /tmp/update_ssid_profile
