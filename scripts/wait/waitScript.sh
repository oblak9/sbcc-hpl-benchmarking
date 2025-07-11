#!/bin/bash

# Function to wait for a single file
wait_for_file() {
  local file="$1"
  echo "Waiting for $file"
  while [[ ! -f "$file" ]]; do
    sleep 1
  done
}

# Main script to wait for all files
for file in "$@"; do
  wait_for_file "$file"
done

echo "All files created!"
