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

# Add a new variable to capture the MPICH directory from the config file
MPICH_DIR=${MPICH_DIR:-"$HOME/mpich-install"}

# Add a new variable to capture the HPL directory from the config file
HPL_DIR=${HPL_DIR:-"$HOME/hpl-2.3"}

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

while read -r build_line; do
  process_build "$build_line"
  build_name=$(echo "$build_line" | cut -d "|" -f 3)
  # the exchange of binaries should only be done if different nodes built different HPLs
  if [ "$HPL_EXCHANGE_BINARIES" = "1" ]; then
      exchange_binaries "$build_name"
  fi
done < "$BUILD_INFO"

# Done signal
done_file="hpl-$(hostname)-done.txt"
touch "$done_file"
scp "$done_file" "$USER@$MASTER_DEVICE:$WAIT_DIR"
