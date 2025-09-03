#!/bin/bash

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

  echo "Processing build: $BUILD_NAME"
  echo "Build flags: $BUILD_FLAGS"

  local build_dir="$HOME/atlas-$BUILD_NAME"
  echo "Building $BUILD_NAME in $build_dir"

  rm -rf "$build_dir"
  mkdir "$build_dir"
  cd "$build_dir" || { echo "Error: Failed to change directory to $build_dir"; exit 1; }

  eval "$CONFIGURE $BUILD_FLAGS" || { echo "Error: Configuration failed for $BUILD_NAME."; exit 1; }

  make || { echo "Error: Make command failed for $BUILD_NAME."; exit 1; }

  # Verify if the libraries have been built
  if [[ ! -f "$build_dir/lib/libcblas.a" || ! -f "$build_dir/lib/libatlas.a" ]]; then
    echo "Error: Required libraries not built for $BUILD_NAME."
    exit 1
  fi
}

# Function to create and send the "done" file
create_and_send_done_file() {
  local done_file="$HOME/atlas-done.txt"
  
  # Create the "done" file
  touch "$done_file" || { echo "Error: Failed to create done file."; exit 1; }
  
  # Send the "done" file to the master device
  scp "$done_file" "$USER@$MASTER_DEVICE:$WAIT_DIR/atlas-$(hostname)-done.txt" || { echo "Error: Failed to send done file."; exit 1; }
  
  # Clean up local "done" file
  rm "$done_file" || { echo "Error: Failed to remove done file."; exit 1; }
}

# Main script logic
determine_node_numbers
for ((i=current_node_ord_number+1; i<=NUM_OF_BUILDS; i+=total_nodes)); do
  #TODO: Possible bug - nodes that start with X0, instead of X1, such as odroid10.
  # since the first nodes ord number is 0, and we have to start from line 1 of the file we have to use i+1
  line=$(sed -n "${i}p" "$BUILD_INFO")

  echo "$(hostname) is building line ${i} of ATLAS build: $line" >> "$LOG_FILE"
  process_build "$line"
done

# Call the function to create and send the "done" file at the end
# TODO: Do it regardless of the error in Atlas builds?
create_and_send_done_file