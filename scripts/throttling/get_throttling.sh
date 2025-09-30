#!/bin/bash
CONFIG_FILE=$1
source $CONFIG_FILE

master_node_number="${MASTER_DEVICE//[!0-9]}"

#Run the extractor of throttling data on client devices (can be done independently)
for ((i=$master_node_number; i<$(expr $master_node_number + $NUM_OF_NODES); i+=1)); do
    host_number=$(printf "%02d" "$i")
    current_host="${MASTER_DEVICE//[0-9]}"$host_number
    ssh $current_host -- $SCRIPTS_DIR/throttling/get_throttling_helper.sh $MONITOR_THROTTLING_CPU
done