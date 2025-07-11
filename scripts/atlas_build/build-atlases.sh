#!/bin/bash

# Check if a configuration file parameter has been provided
if [ "$#" -ne 1 ]; then
  echo "Error: You must provide exactly one parameter."
  echo "Usage: $0 <config-file>"
  exit 1
fi

CONFIG_FILE=$1
source $CONFIG_FILE

CONFIGURE="$HOME/ATLAS/configure"
NUM_OF_BUILDS=$(grep -v '^$' "$BUILD_INFO" | wc -l)

hostname=$(hostname)

# Function to determine node numbers
determine_node_numbers() {
  starting_node_number="${MASTER_DEVICE//[!0-9]}"
  current_node_number="${hostname//[!0-9]}"
  current_node_ord_number=$((current_node_number - starting_node_number))
  total_nodes=$((NUM_OF_NODES))
}

# Function to process each build
process_build() {
  local line=$1
  local BUILD_NAME=$(echo "$line" | cut -d "|" -f 3)
  local BUILD_FLAGS=$(echo "$line" | cut -d "|" -f 4)

  echo $BUILD_NAME
  echo $BUILD_FLAGS

  local build_dir="$HOME/atlas-$BUILD_NAME"
  echo "Building $BUILD_NAME in $build_dir"

  rm -rf "$build_dir"
  mkdir "$build_dir"
  cd "$build_dir" || { echo "Failed to change directory to $build_dir"; exit 1; }

  eval "$CONFIGURE $BUILD_FLAGS"

  make

  # Verify if the libraries have been built
  if [[ ! -f "$build_dir/lib/libcblas.a" || ! -f "$build_dir/lib/libatlas.a" ]]; then
    echo "Error: Required libraries not built."
    exit 1
  fi
}

# Function to create and send the "done" file
create_and_send_done_file() {
  local done_file="$HOME/atlas-done.txt"
  
  # Create the "done" file
  touch "$done_file"
  
  # Send the "done" file to the master device
  scp "$done_file" "$USER@$MASTER_DEVICE:$WAIT_DIR/atlas-$(hostname)-done.txt"
  
  # Clean up local "done" file
  rm "$done_file"
}

# Main script logic
determine_node_numbers
for ((i=current_node_ord_number+1; i<=NUM_OF_BUILDS; i+=total_nodes)); do
  #TODO: Possible bug - nodes that start with X0, insead of X1, such as odroid10.
  # since the first nodes ord number is 0, and we have to start from line 1 of the file we have to use i+1
  line=$(sed -n "${i}p" "$BUILD_INFO")

  echo "$(hostname) is building line ${i} of ATLAS build: $line" >> $LOG_FILE
  process_build "$line"
done

# Call the function to create and send the "done" file at the end
# TODO: Do it regardless of the error in Atlas builds?
create_and_send_done_file