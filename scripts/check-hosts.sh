#!/bin/bash

# Check if two arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 [base hostname] [number of hosts]"
    exit 1
fi

# Arguments: base hostname and number of hosts
BASE_HOSTNAME=$1
NUM_HOSTS=$2

# Extract the non-numeric and numeric parts from the base hostname
BASE_NAME=$(echo $BASE_HOSTNAME | sed 's/[0-9]*$//')
START_NUM=$(echo $BASE_HOSTNAME | sed 's/[^0-9]*//')

# File path for logging
LOG_FILE="/home/zdravak/odroidMC1.log"

# Initialize a counter for alive hosts
ALIVE_HOSTS=0

for ((i=0; i<NUM_HOSTS; i++)); do
    # Construct the hostname
    HOST_NUM=$((START_NUM + i))
    HOSTNAME="${BASE_NAME}${HOST_NUM}"

    # Ping the machine
    ping -c 1 $HOSTNAME > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        # Count the host as alive
        ALIVE_HOSTS=$((ALIVE_HOSTS + 1))
    else
        # If ping fails, log it
        echo "$(date) - Machine $HOSTNAME is down" >> $LOG_FILE
    fi
done

# Check if all hosts are alive
if [ $ALIVE_HOSTS -eq $NUM_HOSTS ]; then
    echo "All $NUM_HOSTS hosts are alive"
else
    echo "Not all hosts are alive. Check $LOG_FILE for details."
fi

