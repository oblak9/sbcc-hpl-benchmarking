#!/bin/bash

# Function to check the number of parameters
check_params() {
  if [ "$#" -ne 1 ]; then
    echo "Error: You must provide exactly one parameter."
    echo "Usage: $0 <config-file>"
    exit 1
  fi
}

# Load two plaintext KEY=VALUE configs and expand ${VARS} after overrides.
# - Configs must use ${VAR} (not bare $VAR) for references.
# - No external deps, no eval.

load_cfg() {
  local base_cfg="$1" platform_cfg="$2"

  # Collect just the keys defined in the two files (to avoid touching other env vars)
  mapfile -t _KEYS < <(
    cat "$base_cfg" "$platform_cfg" 2>/dev/null \
      | sed -E '/^\s*(#|$)/d; s/\s*#.*//; s/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=.*/\1/' \
      | awk '!seen[$0]++'
  )

  # Source both: platform overrides base; auto-export during sourcing
  set -a
  [ -f "$base_cfg" ]      && . "$base_cfg"
  [ -f "$platform_cfg" ]  && . "$platform_cfg"
  set +a

  # Late-expand ${VAR} placeholders (recursive) for those keys only
  local k v name
  for k in "${_KEYS[@]}"; do
    v=${!k}
    while [[ $v =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
      name=${BASH_REMATCH[1]}
      v=${v//\$\{$name\}/${!name}}
    done
    printf -v "$k" '%s' "$v"
    export "$k"
  done
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
  atlasbuildcommand="$SCRIPTS_DIR/atlas_build/build-atlases.sh"

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
  hplbuildcommand="$SCRIPTS_DIR/hpl_build/build-hpl.sh"

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
  "$SCRIPTS_DIR/HPL_run/HPL-execute.sh"
}

# Main function to execute selected steps
main() {
  SCRIPTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)               # Dynamic location of the main scripts.
  LOG_FILE=$(pwd)/log.txt                                                 # Log file that records the steps in the process.

  check_params "$@"
  config_file="$1"
  base_config="${SCRIPTS_DIR}/config-files/base-config.txt" # Use the second parameter or default to the hardcoded path 

  # Load the base configuration
  echo "Loading base configuration from $base_config and $config_file"
  load_cfg "$base_config" "$config_file"

  # Ensure the log file exists
  touch "$LOG_FILE"

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
