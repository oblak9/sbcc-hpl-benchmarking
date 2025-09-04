#!/bin/bash

# HPL Build and Exchange Script
#
# This script automates the process of building HPL (High Performance Linpack) 
# on multiple Linux nodes, each with its own ATLAS (BLAS) build. The script 
# assumes that each node has a specific ATLAS build and ensures that each node 
# builds HPL only for the ATLAS build it possesses. After building, the nodes 
# exchange their HPL binaries with each other.
#
# Usage:
#   ./hpl_build_exchange.sh <config-file>
#
# Arguments:
#   <config-file> : A configuration file that contains necessary environment 
#                   variables and settings.
#
# Configuration File Requirements:
#   The configuration file should define the following variables:
#     - MASTER_DEVICE: The hostname of the master device.
#     - NUM_OF_NODES: The total number of nodes in the cluster.
#     - HPL_DIR: The directory where the HPL source code is located.
#     - HPL_GENERIC_MAKEFILE: The path to the generic HPL makefile.
#     - LOG_FILE: The file to log the build and exchange processes.
#     - BUILD_INFO: A file containing the build information in the format:
#                   <info1>|<info2>|<BUILD_NAME>|<info3>|<BUILD_OPT_FLAGS>|<BUILD_FLAGS>
#     - USER: The username for SSH connections.
#     - WAIT_DIR: The directory on the master device where completion signals are sent.
#
# Node List Generation:
#   The script dynamically generates the list of node hostnames based on the 
#   MASTER_DEVICE and NUM_OF_NODES variables.
#
# Main Steps:
#   1. Check if the configuration file is provided and source it.
#   2. Determine the current node's number and generate the list of all nodes.
#   3. Process each build specified in the BUILD_INFO file:
#      - Check if the node has the specific ATLAS build.
#      - If it does, build the HPL for that ATLAS build.
#      - Exchange the built binaries with all other nodes.
#   4. Signal completion to the master device.
#
# Note:
#   Adjust the path "/path/to/atlas/build/" to the correct path where the ATLAS builds
#   are located on each node.

# --- Universal distribution setup ---

# Required inputs (exported by executor.sh)
: "${HPL_STORAGE:?HPL_STORAGE must be set, e.g. hpl-builds/${PLATFORM}}"

# Use MASTER_DEVICE (e.g., raspi31) to form CENTRAL_STORAGE if not provided
CENTRAL_STORAGE="${CENTRAL_STORAGE:-${USER}@${MASTER_DEVICE}:${HOME}}"

# Where this node keeps built artifacts (per platform), e.g. /home/<user>/clustershared/atlas-builds/<PLATFORM>
LOCAL_BUILDS_ROOT="${HOME}/${HPL_STORAGE}"

# Central staging URL (user@host:/path) that all nodes can reach
CENTRAL_BUILDS_URL="${CENTRAL_STORAGE}/${HPL_STORAGE}"

# If your build artifacts live somewhere else, override BUILD_OUTPUT_ROOT before the loop
BUILD_OUTPUT_ROOT="${BUILD_OUTPUT_ROOT:-$LOCAL_BUILDS_ROOT}"

# rsync/ssh defaults (tweak as desired)
RSYNC_SSH='ssh -o BatchMode=yes -o StrictHostKeyChecking=no'
RSYNC_OPTS='-az --delete --partial'

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
    ${RSYNC_SSH} "$node" "rsync ${RSYNC_OPTS} -e '${RSYNC_SSH}' \
      '${CENTRAL_BUILDS_URL}/' \
      '${LOCAL_BUILDS_ROOT}/'"
  done
}

# Determine node numbers based on the hostname and master device
current_hostname=$(hostname)

determine_node_numbers() {
  start_node_number="${MASTER_DEVICE//[!0-9]}"
  total_nodes=$((NUM_OF_NODES - 1))
}

# Generate the list of nodes dynamically
generate_node_list() {
  NODES=()
  master_base="${MASTER_DEVICE//[0-9]/}"
  for ((i=0; i<=total_nodes; i++)); do
    node="${master_base}$((start_node_number + i))"
    NODES+=("$node")
  done
}

# Function to process each build
process_build() {
  local build_line=$1
  local build_name=$(echo "$build_line" | cut -d "|" -f 3)
  local build_opt_flags=$(echo "$build_line" | cut -d "|" -f 5)
  local build_flags=$(echo "$build_line" | cut -d "|" -f 6)

  # Check if the node has the specific ATLAS build
  if [[ ! -f "$HOME/atlas-$build_name/lib/libcblas.a" || ! -f "$HOME/atlas-$build_name/lib/libatlas.a" ]]; then
    echo "Error: Required libraries not built for $build_name, skipping." >> "$LOG_FILE"
    return
  fi

  cd "$HPL_DIR" || { echo "Failed to change directory to $HPL_DIR"; exit 1; }

  # Remove the existing Makefile if it exists
  rm -f "Make.$build_name"

  # Copy the generic makefile and make the necessary changes
  cp "$HPL_GENERIC_MAKEFILE" "Make.$build_name"
  sed -i "s/buildname/$build_name/g" "Make.$build_name"
  sed -i "s/gccflags/$build_opt_flags $build_flags/g" "Make.$build_name"

  # Update the CC line to use the MPICH directory from the config file
  sed -i "s|^CC *=.*|CC = $MPICH_DIR/bin/mpicc|g" "Make.$build_name"

  # Update the TOPdir line to use the HPL directory from the config file
  sed -i "s|^TOPdir *=.*|TOPdir = $HPL_DIR|g" "Make.$build_name"

  # Build the project
  echo "$(hostname) is building HPL for $build_name build" >> "$LOG_FILE"
  make arch="$build_name" -B
}

# Function to exchange built HPL binaries with other nodes
exchange_binaries() {
  local build_name=$1
  local build_dir="$HOME/hpl-2.3/bin/$build_name"
  for node in "${NODES[@]}"; do
    if [ "$node" != "$current_hostname" ]; then
      scp -r "$build_dir" "$USER@$node:$HOME/hpl-2.3/bin/"
      echo "$(hostname) sent $build_name binary to $node" >> $LOG_FILE
    fi
  done
}

# Main script to process all builds
determine_node_numbers
generate_node_list

# --- Build loop + universal distribution ---

while IFS= read -r build_line; do
  [ -z "$build_line" ] && continue

  # Build this ATLAS/HPL variant on the assigned/builder node
  process_build "$build_line"

  # Derive the build's name (same as you do elsewhere)
  build_name="$(echo "$build_line" | cut -d '|' -f 3)"

  # Where artifacts for this build live on this node:
  # If your script outputs elsewhere, set BUILD_OUTPUT_ROOT accordingly before this loop
  BUILD_OUTPUT_ROOT="${HPL_DIR}/bin"

  BUILD_DIR="${BUILD_OUTPUT_ROOT}/${build_name}"
  [ -d "$BUILD_DIR" ] || { echo "WARN: expected $BUILD_DIR not found; creating it"; mkdir -p "$BUILD_DIR"; }

  # Always stage to central — works for single or multiple builds
  stage_to_central "$build_name" "$BUILD_DIR"

done < "$BUILD_INFO"

# After all builds are staged, fan-out the complete set from central to ALL nodes
fanout_all_nodes

# Done signal
done_file="hpl-$(hostname)-done.txt"
touch "$done_file"
scp "$done_file" "$USER@$MASTER_DEVICE:$WAIT_DIR"
