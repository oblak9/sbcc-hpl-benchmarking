#!/bin/bash

LOG_FILE=$(pwd)/log-atlas-build.txt                               # Local logs
touch "$LOG_FILE" 

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

# Load configs if a config file is passed
if [ $# -eq 1 ]; then
  config_file="$1"
  base_config="${SCRIPTS_DIR}/config-files/base-config.txt"
  load_cfg "$base_config" "$config_file"

  echo -e "\nSuccessfully checked for the existence of input parameters: '$1'.\n" >> "$LOG_FILE"

else
  echo "Error: You must provide exactly one parameter: the path to the platform-specific config file."
  echo "Usage: $0 <config-file>"
  echo "Example: $0 /path/to/config-raspi5B.txt"
  echo "The config file should be a platform-specific configuration file (e.g., config-raspi5B.txt) that overrides base settings for you"
  echo "Ensure the file exists and is readable. For more details, refer to the base-config.txt file."
  exit 1
fi

# Variable declarations and exports (group all constants here)
CONFIGURE="$HOME/ATLAS/configure"
NUM_OF_BUILDS=$(grep -v '^\s*$' "$BUILD_INFO" | wc -l)
hostname=$(hostname)
CENTRAL_STORAGE="${CENTRAL_STORAGE:-${USER}@${MASTER_DEVICE}:${HOME}}"
CENTRAL_BUILDS_URL="${CENTRAL_STORAGE}/${ATLAS_STORAGE}"
LOCAL_BUILDS_ROOT="${HOME}/${ATLAS_STORAGE}"
RSYNC_SSH='ssh -o BatchMode=yes -o StrictHostKeyChecking=no'
RSYNC_OPTS='-az --delete --partial'

# Debugging block (separate for verification)
echo "DEBUG: CONFIGURE=$CONFIGURE"  >> "$LOG_FILE"
echo "DEBUG: NUM_OF_BUILDS=$NUM_OF_BUILDS"  >> "$LOG_FILE"
echo "DEBUG: hostname=$hostname"  >> "$LOG_FILE"
echo "DEBUG: CENTRAL_STORAGE=$CENTRAL_STORAGE"  >> "$LOG_FILE"
echo "DEBUG: CENTRAL_BUILDS_URL=$CENTRAL_BUILDS_URL"  >> "$LOG_FILE"
echo "DEBUG: LOCAL_BUILDS_ROOT=$LOCAL_BUILDS_ROOT"  >> "$LOG_FILE"
echo "DEBUG: RSYNC_SSH=$RSYNC_SSH"  >> "$LOG_FILE"
echo "DEBUG: RSYNC_OPTS=$RSYNC_OPTS \n"  >> "$LOG_FILE"

# Function to create an array of devices (same as in executor.sh)
create_devices_array() {
  DEVICES=()
  master_node_number="${MASTER_DEVICE//[!0-9]}"
  for ((i=$master_node_number; i<$(expr $master_node_number + $NUM_OF_NODES); i+=1)); do
    host_number=$(printf "%02d" "$i")
    DEVICES+=("${MASTER_DEVICE//[0-9]}"$host_number)
  done

  echo -e "Device array created:\n'${DEVICES[*]}'. \n"  >> "$LOG_FILE"
}

# Function to determine node numbers
determine_node_numbers() {
  # Validate DEVICES array
  if [ ${#DEVICES[@]} -eq 0 ]; then
    echo "ERROR: DEVICES array is empty. Ensure it is set in the parent script (e.g., executor.sh)."
    exit 1
  fi

  # Find the current node's ordinal number in the DEVICES array
  current_node_ord_number=""
  for i in "${!DEVICES[@]}"; do
    if [[ "${DEVICES[$i]}" == "$hostname" ]]; then
      current_node_ord_number=$i
      break
    fi
  done

  # Validate that the current hostname was found
  if [[ -z "$current_node_ord_number" ]]; then
    echo "ERROR: Current hostname ($hostname) not found in DEVICES array: ${DEVICES[*]}"
    exit 1
  fi

  # Total number of nodes is the length of the DEVICES array
  total_nodes=${#DEVICES[@]}
}

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

  # Extract the hostname and path parts from CENTRAL_STORAGE
  local central_host="${CENTRAL_STORAGE%%:*}"  # Extracts 'test@raspi31'
  local central_path="${CENTRAL_BUILDS_URL#*:}"  # Extracts '/home/test/atlas-builds/raspi5B'

  # Make the central storage directory
  local mkdir_cmd="${RSYNC_SSH} \"$central_host\" \"mkdir -p \\\"$central_path/$build_name\\\"\""

  echo -e "Mkdir command to create central storage dir: \n'$mkdir_cmd' \n"  >> "$LOG_FILE"

  eval "$mkdir_cmd" || { echo "Error: Failed to create central directory."; return 1; }

  local rsync_cmd="rsync ${RSYNC_OPTS} -e \"${RSYNC_SSH}\" \"${build_dir}/\" \"${CENTRAL_BUILDS_URL}/${build_name}/\""

  echo -e "Command to sync ATLAS build to a central storage dir: \n'$rsync_cmd' \n"  >> "$LOG_FILE"

  # Execute the rsync command
  eval "$rsync_cmd" || { echo "Error: Failed to rsync build directory."; return 1; }
}

# Mirror everything from central to every node in DEVICES (idempotent)
fanout_all_nodes() {
  # First, pull from central to local (handles remote-to-local)
  local pull_cmd="rsync ${RSYNC_OPTS} -e \"${RSYNC_SSH}\" \"${CENTRAL_BUILDS_URL}/\" \"${LOCAL_BUILDS_ROOT}/\""
  echo -e "Command to pull from central to local: \n $pull_cmd" >> "$LOG_FILE"
  
  # Execute rsync and handle exit codes
  eval "$pull_cmd"
  local rsync_exit=$?
  if [[ $rsync_exit -eq 24 ]]; then
    echo "Warning: Some files vanished during rsync pull (code 24), but continuing." >> "$LOG_FILE"
  elif [[ $rsync_exit -ne 0 ]]; then
    echo "Error: Failed to pull from central (rsync exit code $rsync_exit)." >> "$LOG_FILE"
    return 1
  fi

  # Then, push from local to other nodes (local-to-remote)
  for node in "${DEVICES[@]}"; do
    if [[ "$node" == "$hostname" ]]; then
      continue  # Skip self
    fi

    local mkdir_cmd="${RSYNC_SSH} \"$node\" \"mkdir -p '${LOCAL_BUILDS_ROOT}'\""
    echo -e "Command to make a local build directory on node $node: \n $mkdir_cmd" >> "$LOG_FILE"

    eval "$mkdir_cmd" || { echo "Error: Failed to create directory on $node."; continue; }

    local push_cmd="rsync ${RSYNC_OPTS} -e \"${RSYNC_SSH}\" \"${LOCAL_BUILDS_ROOT}/\" \"$node:${LOCAL_BUILDS_ROOT}/\""
    echo -e "Command to push from central to node $node: \n $push_cmd" >> "$LOG_FILE"

    eval "$push_cmd" || { echo "Error: Failed to push to $node."; continue; }
  done
}

# Function to process each build
process_build() {
  local line=$1
  local BUILD_NAME=$(echo "$line" | cut -d "|" -f 3)
  local BUILD_FLAGS=$(echo "$line" | cut -d "|" -f 4)

  echo "Processing build: $BUILD_NAME"  >> "$LOG_FILE"
  echo "Build flags: $BUILD_FLAGS"  >> "$LOG_FILE"

  # Use ATLAS_STORAGE for the build directory
  local build_dir="${ATLAS_STORAGE}/${BUILD_NAME}"
  echo "Building $BUILD_NAME in $build_dir" >> "$LOG_FILE"

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

# Function to create and send the "done" file
create_and_send_done_file() {
  local done_file="$HOME/atlas-${hostname}-done.txt"
  touch "$done_file" || { echo "Error: Failed to create done file."; exit 1; }
  local scp_cmd="scp \"$done_file\" \"$USER@$MASTER_DEVICE:$WAIT_DIR/atlas-$(hostname)-done.txt\""

  echo -e "SCP line to send done files: \n${scp_cmd} \n"  >> "$LOG_FILE"

  eval "$scp_cmd" || { echo "Error: Failed to send done file."; exit 1; }

  rm "$done_file" || { echo "Error: Failed to remove done file."; exit 1; }
}

# Main script logic
create_devices_array
determine_node_numbers

fanout_only=false
if [ "$2" = "--fanout-only" ]; then
  fanout_only=true
fi

if [ "$fanout_only" = false ]; then
  for ((i=current_node_ord_number+1; i<=NUM_OF_BUILDS; i+=total_nodes)); do
    echo -e "NUM OF BUILDS: $NUM_OF_BUILDS"   >> "$LOG_FILE"
    echo -e "total_nodes: $total_nodes"   >> "$LOG_FILE"
    line=$(sed -n "${i}p" "$BUILD_INFO")
    echo "$(hostname) is building line ${i} of ATLAS build: $line" >> "$LOG_FILE"
    process_build "$line" || echo "WARNING: Failed to process build: $line" >> "$LOG_FILE"
  done
fi

fanout_all_nodes
create_and_send_done_file