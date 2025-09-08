#!/bin/bash

# Function to check the number of parameters
check_params() {
  if [ "$#" -ne 1 ]; then
    echo "Error: You must provide exactly one parameter: the path to the platform-specific config file."
    echo "Usage: $0 <config-file>"
    echo "Example: $0 /path/to/config-raspi5B.txt"
    echo "The config file should be a platform-specific configuration file (e.g., config-raspi5B.txt) that overrides base settings for your platform."
    echo "Ensure the file exists and is readable. For more details, refer to the base-config.txt file."
    exit 1
  fi
}

# Load two plaintext KEY=VALUE configs and expand ${VARS} after overrides.
# - Configs must use ${VAR} (not bare $VAR) for references.
# - No external deps, no eval.

load_cfg() {
  local base_cfg="$1" platform_cfg="$2"

  # Read KEY=VALUE lines from both files into an associative array (platform overrides base).
  declare -A CFG=()
  _read_cfg() {
    local f="$1" line key val
    [ -f "$f" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%%#*}"                                   # strip comments
      line="${line#"${line%%[![:space:]]*}"}"              # ltrim
      line="${line%"${line##*[![:space:]]}"}"              # rtrim
      [ -z "$line" ] && continue
      [[ "$line" != *"="* ]] && continue
      key=${line%%=*}; val=${line#*=}
      key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
      val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
      CFG["$key"]="$val"
    done < "$f"
  }

  _read_cfg "$base_cfg"
  _read_cfg "$platform_cfg"

  # Export RAW values first so variables can reference each other (and env like SCRIPTS_DIR/HOME).
  local k
  for k in "${!CFG[@]}"; do export "$k=${CFG[$k]}"; done

  # Late-expand ${VAR} and $VAR safely (no command eval). Two passes for chained refs.
  local v name repl pass
  for pass in 1 2; do
    for k in "${!CFG[@]}"; do
      v=${!k}
      while [[ $v =~ (\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)) ]]; do
        name="${BASH_REMATCH[2]:-${BASH_REMATCH[3]}}"
        repl="${!name-}"
        v="${v//\$\{$name\}/${repl}}"
        v="${v//\$$name/${repl}}"
      done
      printf -v "$k" '%s' "$v"
      export "$k"
    done
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
  # Add a flag for fanout-only (e.g., if a second argument is passed)
  local fanout_only=""
  if [ "$2" = "--fanout-only" ]; then
    fanout_only="--fanout-only"
  fi
  atlasbuildcommand="$SCRIPTS_DIR/atlas_build/build-atlases.sh $config_file $fanout_only"

  # Start builds on all worker nodes in parallel
  for current_host in "${DEVICES[@]:1}"; do
    echo "Starting atlas builds on $current_host" >> "$LOG_FILE"
    ssh "$current_host" "export SCRIPTS_DIR=$SCRIPTS_DIR; tmux new-session -d -s 'atlassetup' -- '$atlasbuildcommand'" &
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

run_and_wait_hpl_makefiles() {
  # Add a flag for fanout-only (e.g., if a second argument is passed)
  local fanout_only=""
  if [ "$2" = "--fanout-only" ]; then
    fanout_only="--fanout-only"
  fi
  hplbuildcommand="$SCRIPTS_DIR/hpl_build/build-hpl.sh $config_file $fanout_only"

  # Start builds on all worker nodes in parallel
  for current_host in "${DEVICES[@]:1}"; do
    echo "Running hpl makefiles creation on $current_host" >> "$LOG_FILE"
    ssh "$current_host" "export SCRIPTS_DIR=$SCRIPTS_DIR; tmux new-session -d -s 'hplsetup' -- '$hplbuildcommand'" &
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

  # Export these for use in sourced scripts
  export SCRIPTS_DIR LOG_FILE DEVICES

  echo "Select steps to execute:"
  echo "1. Clean wait directory"
  echo "2. Run atlas builds and wait for completion"
  echo "3. Run HPL makefiles and wait for completion"
  echo "4. Run HPL execution"
  echo "5. Fanout existing ATLAS builds (no rebuild)"
  echo "6. Fanout existing HPL builds (no rebuild)"  # New step
  echo "7. All steps"  # Renumbered
  
  read -p "Enter the steps you want to execute (e.g., 1 2 3 4): " -a steps

  for step in "${steps[@]}"; do
    case $step in
      1) clean_wait_dir ;;
      2) run_and_wait_atlas_builds ;;
      3) run_and_wait_hpl_makefiles ;;
      4) run_hpl_execution ;;
      5) run_and_wait_atlas_builds "" "--fanout-only" ;;  # On-demand ATLAS fanout
      6) run_and_wait_hpl_makefiles "" "--fanout-only" ;;  # New: On-demand HPL fanout
      7) 
        clean_wait_dir
        run_and_wait_atlas_builds
        run_and_wait_hpl_makefiles
        run_hpl_execution
        ;;
      *) echo "Invalid step: $step" ;;
      esac
    done
}

main "$@"
