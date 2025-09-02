#!/bin/bash

# Function to check the number of parameters
check_params() {
  if [ "$#" -ne 1 ]; then
    echo "Error: You must provide exactly one parameter."
    echo "Usage: $0 <config-file>"
    exit 1
  fi
}

# Function to check if the config file exists
check_config_file() {
  CONFIG_FILE=$1
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file '$CONFIG_FILE' not found."
    exit 1
  fi
  source "$CONFIG_FILE" || { echo "Error: Failed to source config file."; exit 1; }
}

# Function to create an array of devices
create_devices_array() {
  DEVICES=()
  master_node_number="${MASTER_DEVICE//[!0-9]}"
  for ((i=$master_node_number; i<$(expr $master_node_number + $NUM_OF_NODES); i+=1)); do
    host_number=$(printf "%02d" "$i")
    DEVICES+=("${MASTER_DEVICE//[0-9]}"$host_number)
  done
}

# Function to clean the old wait directory
clean_wait_dir() {
  rm -rf "$WAIT_DIR"
  mkdir -p "$WAIT_DIR"
}

# Function to run atlas builds on all nodes and wait for completion
run_and_wait_atlas_builds() {
  atlasbuildcommand="$SCRIPTS_DIR/atlas_build/build-atlases.sh $CONFIG_FILE"

  # Start builds on all worker nodes in parallel
  for current_host in "${DEVICES[@]:1}"; do
    echo "Starting atlas builds on $current_host" >> "$LOG_FILE"
    ssh "$current_host" "tmux new-session -d -s 'atlassetup' -- '$atlasbuildcommand'" &
  done

  # Run build command on the master node directly
  echo "Starting atlas builds on $HOSTNAME" >> "$LOG_FILE"
  eval "$atlasbuildcommand && touch \"$WAIT_DIR/atlas-${HOSTNAME}-done.txt\""

  # Wait for all nodes to finish by checking their done files
  waitcommand="$SCRIPTS_DIR/wait/waitScript.sh"
  for current_host in "${DEVICES[@]}"; do
    waitcommand+=" \"$WAIT_DIR/atlas-${current_host}-done.txt\""
  done
  eval "$waitcommand"
}

# Function to collect atlas builds from all devices
collect_atlas_builds() {
  for current_host in "${DEVICES[@]:1}"; do
    scp -r "$USER@$current_host:$HOME/atlas-*" "$HOME"
  done
}

# Function to distribute atlas builds (directories) to all devices
distribute_atlas_builds() {
  local atlas_builds
  # Find only directories in the $HOME directory that match atlas-*
  atlas_builds=$(find "$HOME" -maxdepth 1 -type d -name "atlas-*")

  for current_host in "${DEVICES[@]:1}"; do
    for build in $atlas_builds; do
      echo "$build on host $current_host"
      if ssh "$current_host" "test -d \"$HOME/$(basename "$build")\""; then
        echo "Skipping $build on $current_host, already exists."
      else
        echo "Distributing $build to $current_host" >> "$LOG_FILE"
        scp -r "$build" "$USER@$current_host:$HOME"
      fi
    done
  done
}

# Function to run HPL makefile creation and wait for completion
run_and_wait_hpl_makefiles() {
  hplbuildcommand="$SCRIPTS_DIR/hpl_build/build-hpl.sh $CONFIG_FILE"

  # Start builds on all worker nodes in parallel
  for current_host in "${DEVICES[@]:1}"; do
    echo "Running hpl makefiles creation on $current_host" >> "$LOG_FILE"
    ssh "$current_host" "tmux new-session -d -s 'hplsetup' -- '$hplbuildcommand'" &
  done

  # Run build command on the master node directly
  echo "Running hpl makefiles creation on $HOSTNAME" >> "$LOG_FILE"
  eval "$hplbuildcommand && touch \"$WAIT_DIR/hpl-${HOSTNAME}-done.txt\""

  # Wait for all nodes to finish
  waitcommand="$SCRIPTS_DIR/wait/waitScript.sh"
  for current_host in "${DEVICES[@]}"; do
    waitcommand+=" \"$WAIT_DIR/hpl-${current_host}-done.txt\""
  done
  eval "$waitcommand"
}

# Function to run HPL execution
run_hpl_execution() {
  "$SCRIPTS_DIR/HPL_run/HPL-execute.sh" "$CONFIG_FILE"
}

# Main function to execute selected steps
main() {
  check_params "$@"
  check_config_file "$1"
  create_devices_array

  echo "Select steps to execute:"
  echo "1. Clean wait directory"
  echo "2. Run atlas builds and wait for completion"
  echo "3. Collect atlas builds from all nodes"
  echo "4. Distribute atlas builds"
  echo "5. Run HPL makefiles and wait for completion"
  echo "6. Run HPL execution"
  echo "7. All steps"
  
  read -p "Enter the steps you want to execute (e.g., 1 2 3 4): " -a steps

  for step in "${steps[@]}"; do
    case $step in
      1) clean_wait_dir ;;
      2) run_and_wait_atlas_builds ;;
      3) collect_atlas_builds ;;
      4) distribute_atlas_builds ;;
      5) run_and_wait_hpl_makefiles ;;
      6) run_hpl_execution ;;
      7) 
        clean_wait_dir
        run_and_wait_atlas_builds
        collect_atlas_builds
        distribute_atlas_builds
        run_and_wait_hpl_makefiles
        run_hpl_execution
        ;;
      *) echo "Invalid step: $step" ;;
    esac
  done
}

main "$@"
