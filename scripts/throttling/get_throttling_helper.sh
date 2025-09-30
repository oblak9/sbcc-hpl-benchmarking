#!/bin/bash
MONITOR_THROTTLING_CPU=$1
THROTTLE_INFO=/sys/devices/system/cpu/$MONITOR_THROTTLING_CPU/cpufreq/stats/time_in_state

#The three lines before the last represent the biggest three frequencies smaller then the biggest
for freq in 4 3 2
do
    THROTTLE_LINE=$(tail -n $freq "$THROTTLE_INFO" | head -n 1)
    THROTTLE_TIME=( $THROTTLE_LINE )
    echo -n ${THROTTLE_TIME[1]} " "
done