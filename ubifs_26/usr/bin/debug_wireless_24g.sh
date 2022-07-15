#!/bin/sh 

# Exit if it is not wireless
board="$(/usr/bin/board_check.sh)"
if [ "$board" != "RV340W" ] && [ "$board" != "RV260W" ]; then
return
fi

start_debug() {

IFNAME=$1

logger -t system -p local0.alert " $IFNAME troubleshoot and log collection Started.!!!"
#Exit if the interface is not up
if [ "$(wl -i $IFNAME isup)" = "0" ];then
return
fi

# Step 1: Start OTA capture.
# Step 2: Enable the debug msglevel.
wl msglevel +error +assoc

# Step 3: Collect WlGetDriverCfg.sh output
/usr/bin/WlGetDriverCfg.sh $IFNAME 2 nic > /tmp/${IFNAME}_cfg.log 2>&1

# Step 4: Collect WlGetDriverStats.sh output
pid=$(/usr/bin/WlGetDriverStats.sh -i $IFNAME -m nic -s enable >  /tmp/${IFNAME}_stats.log 2>&1 & echo $!)
sleep 300

# Step 5: Stop the above script
kill -9 "$pid"

# Step 6: Enable wsec logs for 300 sec. 
wl msglevel +wsec
echo "=============== +wsec dmesg logs ==============" >> /tmp/${IFNAME}_stats.log
a=0                                                                                                         
#Iterate the loop until a less than 6 i.e 180 sec            
while [ $a -lt 6 ]                                                                   
do                                            
    sleep 30                                                                                                
    dmesg -c >> /tmp/${IFNAME}_stats.log
    a=`expr $a + 1`                                                           
done  
wl msglevel -wsec

# Step 7: Restart wireless 
logger -t system -p local0.alert " $IFNAME troubleshoot and log collection:restarting wireless.!!!"
#Exit if the interface is not up
/usr/bin/wireless_restart
sleep 5

# Step 8: Enable debug msglevel
wl msglevel +error +assoc

# Step 9: Collect WlGetDriverCfg.sh output after restart
/usr/bin/WlGetDriverCfg.sh $IFNAME 2 nic > /tmp/${IFNAME}_cfg_restart.log 2>&1


# Step 10: Collect WlGetDriverStats.sh output after restart
pid=$(/usr/bin/WlGetDriverStats.sh -i $IFNAME -m nic -s enable > /tmp/${IFNAME}_stats_restart.log 2>&1 & echo $!)
sleep 300                                                                                               

# Step 11: Stop the above script.                                                                                
kill -9 "$pid"

# Step 12: Enble +wsec logs.
wl msglevel +wsec
echo "===============+wsec dmesg logs==============" >> /tmp/${IFNAME}_stats_restart.log                         

a=0
#Iterate the loop until a less than 10
while [ $a -lt 6 ]
do 
    sleep 30
    dmesg -c >> /tmp/${IFNAME}_stats_restart.log        
    a=`expr $a + 1`
done
wl msglevel -wsec                                                                                       
                                                                                                        
logger -t system -p local0.alert " $IFNAME troubleshoot and log collection finished. !!!"
}

start_debug wl0 &

