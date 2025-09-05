#!/bin/bash

CONFIGURE="$HOME/ATLAS/configure"
NUM_OF_BUILDS=$(grep -v '^\s*$' "$BUILD_INFO" | wc -l)

hostname=$(hostname)

# Function to determine node numbers
determine_node_numbers() {
  # Find the current node's ordinal number in the DEVICES array
  for i in "${!DEVICES[@]}"; do
    if [[ "${DEVICES[$i]}" == "$hostname" ]]; then
      current_node_ord_number=$i
      break
    fi
  done

  # Total number of nodes is the length of the DEVICES array
  total_nodes=${#DEVICES[@]}

  echo "DEBUG: Current node ordinal number: $current_node_ord_number"
  echo "DEBUG: Total nodes: $total_nodes"
}

# Function to process each build
process_build() {
  local line=$1
  local BUILD_NAME=$(echo "$line" | cut -d "|" -f 3)
  local BUILD_FLAGS=$(echo "$line" | cut -d "|" -f 4)

  echo "Processing build: $BUILD_NAME"
  echo "Build flags: $BUILD_FLAGS"

  # Use ATLAS_STORAGE for the build directory
  local build_dir="${ATLAS_STORAGE}/${BUILD_NAME}"
  echo "Building $BUILD_NAME in $build_dir"

  # Ensure the build directory exists
  rm -rf "$build_dir"
  mkdir -p "$build_dir"
  cd "$build_dir" || { echo "Error: Failed to change directory to $build_dir"; exit 1; }

  # # Configure and build ATLAS
  # eval "$CONFIGURE $BUILD_FLAGS" || { echo "Error: Configuration failed for $BUILD_NAME."; exit 1; }
  # make || { echo "Error: Make command failed for $BUILD_NAME."; exit 1; }


########################
    # Simulate configuration and build
  echo "Simulating: eval \"$CONFIGURE $BUILD_FLAGS\""
  echo "Simulating: make"

  # Simulate library verification
  echo "Simulating: Verifying $build_dir/lib/libcblas.a and $build_dir/lib/libatlas.a"
  mkdir -p "$build_dir/lib"  # Create the lib directory to simulate the build
  touch "$build_dir/lib/libcblas.a" "$build_dir/lib/libatlas.a"  # Create dummy library files

#########################

  # Verify if the libraries have been built
  if [[ ! -f "$build_dir/lib/libcblas.a" || ! -f "$build_dir/lib/libatlas.a" ]]; then
    echo "Error: Required libraries not built for $BUILD_NAME."
    exit 1
  fi

  # Stage the build to central storage
  stage_to_central "$BUILD_NAME" "$build_dir"
}

# Central staging URL (user@host:/path) that all nodes can reach
CENTRAL_BUILDS_URL="${CENTRAL_STORAGE}/${ATLAS_STORAGE}"
# Where this node keeps built artifacts (per platform), e.g. /home/<user>/atlas-builds/<PLATFORM>
LOCAL_BUILDS_ROOT="${HOME}/${ATLAS_STORAGE}"

# Stage one built build directory to the central store
#   $1 = BUILD_NAME    (dir name to use on central)
#   $2 = BUILD_DIR     (absolute path where artifacts were produced on this node)
stage_to_central() {
  local build_name="$1"
  local build_dir="$2"
  if [ ! -d "$build_dir" ]; then
    echo "stage_to_central: missing dir: $build_dir" >&2
    return 1
  fi
  # Ensure central path exists, then push
  ${RSYNC_SSH} "${CENTRAL_STORAGE%%:*}" "mkdir -p '${CENTRAL_BUILDS_URL#*:}/${build_name}'"
  rsync ${RSYNC_OPTS} -e "${RSYNC_SSH}" \
    "${build_dir}/" \
    "${CENTRAL_BUILDS_URL}/${build_name}/"
}

# Mirror everything from central to every node in DEVICES (idempotent)
fanout_all_nodes() {
  for node in "${DEVICES[@]}"; do
    ${RSYNC_SSH} "$node" "mkdir -p '${LOCAL_BUILDS_ROOT}'"
    rsync ${RSYNC_OPTS} -e "${RSYNC_SSH}" \
      "${CENTRAL_BUILDS_URL}/" \
      "$node:${LOCAL_BUILDS_ROOT}/"
  done
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
  process_build "$line" || echo "WARNING: Failed to process build: $line" >> "$LOG_FILE"
done

fanout_all_nodes

# Call the function to create and send the "done" file at the end
# TODO: Do it regardless of the error in Atlas builds?
create_and_send_done_file