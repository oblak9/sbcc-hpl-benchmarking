#!/bin/bash

# Define the hosts
hosts=("raspi11" "raspi12" "raspi13" "raspi14")
main_host="raspi11"

# Check if SSH key exists, if not generate one
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
fi

# Function to copy SSH key to a host
copy_ssh_key() {
    host=$1
    echo "Copying SSH key to $host..."
    ssh-copy-id -i ~/.ssh/id_rsa.pub $USER@$host
}

# Loop through hosts and copy SSH key
for host in "${hosts[@]}"; do
    if [ "$host" != "$main_host" ]; then
        copy_ssh_key $host
    fi
done

echo "Passwordless SSH setup completed for hosts: ${hosts[@]}"

