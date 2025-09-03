#!/bin/bash
MASTER_DEVICE=$1
NUM_OF_NODES=$2

master_node_number="${MASTER_DEVICE//[!0-9]}"

for ((i=$master_node_number; i<$(expr $master_node_number + $NUM_OF_NODES); i+=1)); do
    host_number=$(printf "%02d" "$i")
    current_host="${MASTER_DEVICE//[0-9]}"$host_number
    echo $current_host
    scp -r $HOME/scripts $USER@$current_host:$HOME
done
