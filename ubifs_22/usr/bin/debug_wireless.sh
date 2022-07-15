#!/bin/sh 

# Exit if it is not wireless
board="$(/usr/bin/board_check.sh)"
if [ "$board" != "RV340W" ] && [ "$board" != "RV260W" ] && [ "$board" != "RV160W" ]; then
return
fi

start_debug() {

#90 iterations of 3 sec
iteration=90
IFNAME=$1

#Exit if the interface is not up
if [ "$(wl -i $IFNAME isup)" = "0" ];then
return
fi

#dmesg -n 8
ps
echo ===== wl ver ======
wl ver
echo ===== wl country ======
wl country
echo ===== nvram show ======
nvram show
echo ===== nvram dump ======
wl -i $IFNAME nvram_dump
sleep 3

wl msglevel +assoc +error
wl -i $IFNAME srl 15
wl -i $IFNAME lrl 15

    echo ===== Sleep 30 Seconds======
    sleep 30
    echo ===== $IFNAME status======
wl -i $IFNAME status
    echo ===== $IFNAME ed threshold======
wl -i $IFNAME phy_ed_thresh
    echo ===== wl -i $IFNAME interference ======
    wl -i $IFNAME interference
    echo ===== wl -i $IFNAME curpower ======
    wl -i $IFNAME curpower

while [ $iteration -gt 0 ]
do
    sleep 3

    echo ====================================================START=================================================
    echo ===== Date ======
    date

    if [ "$(wl -i $IFNAME isup)" = "0" ];then
	echo "$IFNAME is down"
	continue
    fi

    echo ===== assoclist ======
    wl -i $IFNAME assoclist

    echo ===== wl -i $IFNAME chanim_stats ======
    wl -i $IFNAME chanim_stats

    echo ===== wl -i $IFNAME pktq_stats ======
    wl -i $IFNAME pktq_stats A: C: P:

    echo ===== wl -i $IFNAME counters ======
    wl -i $IFNAME counters
    echo ===== wl -i $IFNAME reset_cnts ======
    wl -i $IFNAME reset_cnts

    echo ===== wl -i $IFNAME dump ampdu ======
    wl -i $IFNAME dump ampdu
    echo ===== wl -i $IFNAME ampdu_clear_dump ======
    wl -i $IFNAME ampdu_clear_dump

    echo ===== wl -i $IFNAME dump nar ======
    wl -i $IFNAME dump nar
    echo ===== wl -i $IFNAME nar_clear_dump ======
    wl -i $IFNAME nar_clear_dump
    echo ===== wl -i $IFNAME dump wlc ======
    wl -i $IFNAME dump wlc
    echo ===== wl -i $IFNAME dump phynoise ======
    wl -i $IFNAME dump phynoise
    echo ===== wl -i $IFNAME dump phyaci ======
    wl -i $IFNAME dump phyaci

    echo ===== wl -i $IFNAME dump scb ======
    wl -i $IFNAME dump scb

    echo ===== wl -i $IFNAME dump amt ======
    wl -i $IFNAME dump amt

    echo ===== wl -i $IFNAME keys ======
    wl -i $IFNAME keys

    echo ===== wl -i $IFNAME phy_ed_thresh ======
    wl -i $IFNAME phy_ed_thresh 


    echo ====================================================END=================================================
    iteration=`expr $iteration - 1`
    if [ "$iteration" = "0" ];then
    	wl msglevel -assoc
    fi
done
}
start_debug wl0 > /tmp/wl0_debug_logs 2>&1 &
start_debug wl1 > /tmp/wl1_debug_logs 2>&1 &
