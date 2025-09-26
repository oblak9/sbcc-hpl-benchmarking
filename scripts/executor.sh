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
  echo -e "\nSuccessfully checked for the existence of input parameters: '$1'.\n" >> "$LOG_FILE"
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
  
  echo -e "Configs \n'$1' and \n'$2' loaded. \n" >> "$LOG_FILE"
}

# Function to create an array of devices
create_devices_array() {
  DEVICES=()
  master_node_number="${MASTER_DEVICE//[!0-9]}"
  for ((i=$master_node_number; i<$(expr $master_node_number + $NUM_OF_NODES); i+=1)); do
    host_number=$(printf "%02d" "$i")
    DEVICES+=("${MASTER_DEVICE//[0-9]}"$host_number)
  done
  echo -e "Device array created:\n'${DEVICES[*]}'. \n" >> "$LOG_FILE"
}

# Function to clean the old wait directory
clean_wait_dir() {
  rm -rf "$WAIT_DIR"
  mkdir -p "$WAIT_DIR"
  # Assertions
  if [ -d "$WAIT_DIR" ] && [ -z "$(ls -A "$WAIT_DIR")" ]; then
    echo "PASS: Directory cleaned successfully."
  else
    echo "FAIL: Directory not cleaned."
  fi
  echo -e "\nContents of $WAIT_DIR after cleaning:\n" >> "$LOG_FILE"
  ls -la "$WAIT_DIR" >> "$LOG_FILE"
}

# Function to run atlas builds on all nodes and wait for completion
run_and_wait_atlas_builds() {
  atlasbuildcommand="$SCRIPTS_DIR/atlas_build/build-atlases.sh $config_file"
  atlasstagingcommand="$SCRIPTS_DIR/stage-builds.sh atlas $config_file"

  # Start builds on all worker nodes in parallel
  for current_host in "${DEVICES[@]:1}"; do
    atlas_cmd="ssh \"$current_host\" \"export SCRIPTS_DIR=$SCRIPTS_DIR; tmux new-session -d -s 'atlassetup' -- '$atlasbuildcommand'\""
    echo -e "\nStarting atlas builds on '$current_host' with:\n '$atlas_cmd' \n"
    eval "$atlas_cmd" &
  done

  # Run build command on the master node directly
  echo "Starting atlas builds on $HOSTNAME" >> "$LOG_FILE"
  atlas_cmd="eval \"$atlasbuildcommand && touch \\\"$WAIT_DIR/atlas-build-${HOSTNAME}-done.txt\\\"\""
  echo -e "\nStarting atlas builds on the master ('$HOSTNAME') with:\n '$atlas_cmd' \n"
  eval "$atlas_cmd"

  # Wait for all nodes to finish by checking their done files
  waitcommand="$SCRIPTS_DIR/wait/waitScript.sh"
  for current_host in "${DEVICES[@]}"; do
    waitcommand+=" \"$WAIT_DIR/atlas-build-${current_host}-done.txt\""
  done
  echo -e "\nWaiting with waitcommand '$waitcommand'. \n"
  eval "$waitcommand"

  # Start staging on all worker nodes in parallel
  for current_host in "${DEVICES[@]:1}"; do
    atlas_stage_cmd="ssh \"$current_host\" \"export SCRIPTS_DIR=$SCRIPTS_DIR; tmux new-session -d -s 'atlasstage' -- '$atlasstagingcommand'\""
    echo -e "\nStarting atlas staging on '$current_host' with:\n '$atlas_stage_cmd' \n"
    eval "$atlas_stage_cmd" &
  done

  # Run staging command on the master node directly
  echo "Starting atlas staging on $HOSTNAME" >> "$LOG_FILE"
  atlas_stage_cmd="eval \"$atlasstagingcommand && touch \\\"$WAIT_DIR/atlas-stage-${HOSTNAME}-done.txt\\\"\""
  echo -e "\nStarting atlas staging on the master ('$HOSTNAME') with:\n '$atlas_stage_cmd' \n"
  eval "$atlas_stage_cmd"

  # Wait for all stagings to finish by checking their done files
  stagewaitcommand="$SCRIPTS_DIR/wait/waitScript.sh"
  for current_host in "${DEVICES[@]}"; do
    stagewaitcommand+=" \"$WAIT_DIR/atlas-stage-${current_host}-done.txt\""
  done
  echo -e "\nWaiting for staging with stagewaitcommand '$stagewaitcommand'. \n"
  eval "$stagewaitcommand"

  # Fanout builds (from central to master, then from master to all)
  run_fanout atlas
}

run_and_wait_hpl_makefiles() {
  hplbuildcommand="$SCRIPTS_DIR/hpl_build/build-hpl.sh $config_file"
  hplstagingcommand="$SCRIPTS_DIR/stage-builds.sh hpl $config_file"

  # Start builds on all worker nodes in parallel
  for current_host in "${DEVICES[@]:1}"; do
    echo "Running hpl makefiles creation on $current_host" >> "$LOG_FILE"
    ssh "$current_host" "export SCRIPTS_DIR=$SCRIPTS_DIR; tmux new-session -d -s 'hplsetup' -- '$hplbuildcommand'" &
  done

  # Run build command on the master node directly
  echo "Running hpl makefiles creation on $HOSTNAME" >> "$LOG_FILE"
  eval "$hplbuildcommand && touch \"$WAIT_DIR/hpl-build-${HOSTNAME}-done.txt\""

  # Wait for all nodes to finish
  waitcommand="$SCRIPTS_DIR/wait/waitScript.sh"
  for current_host in "${DEVICES[@]}"; do
    waitcommand+=" \"$WAIT_DIR/hpl-build-${current_host}-done.txt\""
  done
  eval "$waitcommand"

  # Start staging on all worker nodes in parallel
  for current_host in "${DEVICES[@]:1}"; do
    hpl_stage_cmd="ssh \"$current_host\" \"export SCRIPTS_DIR=$SCRIPTS_DIR; tmux new-session -d -s 'hplstage' -- '$hplstagingcommand'\""
    echo -e "\nStarting hpl staging on '$current_host' with:\n '$hpl_stage_cmd' \n"
    eval "$hpl_stage_cmd" &
  done

  # Run staging command on the master node directly
  echo "Starting hpl staging on $HOSTNAME" >> "$LOG_FILE"
  hpl_stage_cmd="eval \"$hplstagingcommand && touch \\\"$WAIT_DIR/hpl-stage-${HOSTNAME}-done.txt\\\"\""
  echo -e "\nStarting hpl staging on the master ('$HOSTNAME') with:\n '$hpl_stage_cmd' \n"
  eval "$hpl_stage_cmd"

  # Wait for all stagings to finish by checking their done files
  stagestagewaitcommand="$SCRIPTS_DIR/wait/waitScript.sh"
  for current_host in "${DEVICES[@]}"; do
    stagestagewaitcommand+=" \"$WAIT_DIR/hpl-stage-${current_host}-done.txt\""
  done
  echo -e "\nWaiting for hpl staging with stagestagewaitcommand '$stagestagewaitcommand'. \n"
  eval "$stagestagewaitcommand"

  # Fanout builds (from central to master, then from master to all)
  run_fanout hpl
}

# Function to fanout builds from central to all nodes (run on master, assumed central can be elsewhere)
run_fanout() {
  local type="$1"
  if [[ "$type" == "atlas" ]]; then
    storage="$ATLAS_STORAGE"
  else
    storage="$HPL_STORAGE"
  fi

  hostname=$(hostname)
  CENTRAL_BUILDS_URL="${CENTRAL_STORAGE_HOST}:${storage}"
  RSYNC_SSH='ssh -o BatchMode=yes -o StrictHostKeyChecking=no'
  RSYNC_OPTS='-az --delete --partial'

  # Pull from central to local on master
  pull_cmd="rsync ${RSYNC_OPTS} -e \"${RSYNC_SSH}\" \"${CENTRAL_BUILDS_URL}/\" \"${storage}/\""
  echo -e "Pulling from central to local: \n $pull_cmd" >> "$LOG_FILE"
  eval "$pull_cmd" || { echo "Error: Failed to pull."; return 1; }

  # Push to other nodes
  for node in "${DEVICES[@]}"; do
    if [[ "$node" == "$hostname" ]]; then
      continue
    fi
    mkdir_cmd="${RSYNC_SSH} \"$node\" \"mkdir -p '${storage}'\""
    eval "$mkdir_cmd" || { echo "Error: Failed to create dir on $node."; continue; }

    push_cmd="rsync ${RSYNC_OPTS} -e \"${RSYNC_SSH}\" \"${storage}/\" \"$node:${storage}/\""
    echo -e "Pushing to $node: \n $push_cmd" >> "$LOG_FILE"
    eval "$push_cmd" || { echo "Error: Failed to push to $node."; continue; }
  done
}

# Function to run HPL execution
run_hpl_execution() {
  "$SCRIPTS_DIR/HPL_run/HPL-execute.sh"
}

# Main function to execute selected steps
main() {
  SCRIPTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)               # Dynamic location of the main scripts.
  LOG_FILE=$(pwd)/log.txt                                                 # Log file that records the steps in the process. 
  touch "$LOG_FILE" 

  check_params "$@"
  config_file="$1"
  base_config="${SCRIPTS_DIR}/config-files/base-config.txt" # Use the second parameter or default to the hardcoded path 

  # Load the base configuration
  echo "Loading base configuration from $base_config and $config_file"
  load_cfg "$base_config" "$config_file"

  create_devices_array

  # Export these for use in sourced scripts
  export SCRIPTS_DIR LOG_FILE DEVICES

  echo "Select steps to execute:"
  echo "1. Clean wait directory"
  echo "2. Run atlas builds and wait for completion"
  echo "3. Run HPL makefiles and wait for completion"
  echo "4. Run HPL execution"
  echo "5. Fanout existing ATLAS builds (no rebuild)"
  echo "6. Fanout existing HPL builds (no rebuild)"
  echo "7. All steps"
  
  read -p "Enter the steps you want to execute (e.g., 1 2 3 4): " -a steps

  for step in "${steps[@]}"; do
    case $step in
      1) clean_wait_dir ;;
      2) run_and_wait_atlas_builds ;;
      3) run_and_wait_hpl_makefiles ;;
      4) run_hpl_execution ;;
      5) run_fanout "atlas" ;;  # On-demand ATLAS builds fanout
      6) run_fanout "hpl" ;;  # On-demand HPL builds fanout
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
