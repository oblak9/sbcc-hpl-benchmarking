#!/bin/bash

# Define an array of desired frequencies
FREQUENCIES=(600000 400000) # Add your desired frequencies here
REMOTE_HOSTS=("zdravak@odroid11" "zdravak@odroid12" "zdravak@odroid13")

# Path to your script
SCRIPT_PATH="/home/zdravak/scripts/HPL_run/HPL-execute.sh"

# Ensure the script has execute permissions
chmod +x "$SCRIPT_PATH"

for FREQ in "${FREQUENCIES[@]}"; do
    echo "Setting CPU frequency to $FREQ"
    echo $FREQ | sudo tee /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
    
    # Iterate over remote hosts and change frequency for their small cores
    for HOST in "${REMOTE_HOSTS[@]}"; do
        echo "Setting CPU frequency to $FREQ on small cores of $HOST"
	ssh -t $HOST "sudo echo $FREQ | sudo tee /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq"
    done

    # Run your script with the new frequency
    echo "Running peak HPL at CPU frequency of the small cores: $FREQ"
    $SCRIPT_PATH /home/zdravak/scripts/config-MC1-big.txt $FREQ

    # Optional: wait a bit between tests
    sleep 1
done

echo "Done with all frequencies."
