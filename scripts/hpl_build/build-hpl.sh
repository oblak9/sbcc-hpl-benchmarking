#!/bin/bash

LOG_FILE=$(pwd)/log-hpl-build.txt                               # Local logs
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
}

# Load configs if a config file is passed
if [ $# -eq 1 ]; then
  config_file="$1"
  base_config="${SCRIPTS_DIR}/config-files/base-config.txt"
  load_cfg "$base_config" "$config_file"
fi

# Required inputs (exported by executor.sh)
: "${HPL_STORAGE:?HPL_STORAGE must be set, e.g. hpl-builds/${PLATFORM}}"

# Variable declarations and exports (group all constants here)
hostname=$(hostname)
CENTRAL_STORAGE="${CENTRAL_STORAGE:-${USER}@${MASTER_DEVICE}:${HOME}}"
CENTRAL_BUILDS_URL="${CENTRAL_STORAGE}/${HPL_STORAGE}"
LOCAL_BUILDS_ROOT="${HOME}/${HPL_STORAGE}"
#BUILD_OUTPUT_ROOT="${BUILD_OUTPUT_ROOT:-$LOCAL_BUILDS_ROOT}"
RSYNC_SSH='ssh -o BatchMode=yes -o StrictHostKeyChecking=no'
RSYNC_OPTS='-az --delete --partial'
NUM_OF_BUILDS=$(grep -v '^\s*$' "$BUILD_INFO" | wc -l)  # Added for consistency

echo "DEBUG: CENTRAL_STORAGE: $CENTRAL_STORAGE"
echo "DEBUG: LOCAL_BUILDS_ROOT: $LOCAL_BUILDS_ROOT"
echo "DEBUG: CENTRAL_BUILDS_URL: $CENTRAL_BUILDS_URL"
#echo "DEBUG: BUILD_OUTPUT_ROOT: $BUILD_OUTPUT_ROOT"
echo "DEBUG: RSYNC_SSH: $RSYNC_SSH"
echo "DEBUG: RSYNC_OPTS: $RSYNC_OPTS"
echo "DEBUG: NUM_OF_BUILDS: $NUM_OF_BUILDS"

# Function to create an array of devices
create_devices_array() {
  DEVICES=()
  master_node_number="${MASTER_DEVICE//[!0-9]}"
  for ((i=$master_node_number; i<$(expr $master_node_number + $NUM_OF_NODES); i+=1)); do
    host_number=$(printf "%02d" "$i")
    DEVICES+=("${MASTER_DEVICE//[0-9]}"$host_number)
  done

  echo -e "Device array created:\n'${DEVICES[*]}'. \n"  >> "$LOG_FILE"
}

# Function to determine node numbers (added for consistency)
determine_node_numbers() {
  # Validate DEVICES array
  if [[ ${#DEVICES[@]} -eq 0 ]]; then
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
  local central_path="${CENTRAL_BUILDS_URL#*:}"  # Extracts '/home/test/hpl-builds/raspi5B'

  # Make the central storage directory
  local mkdir_cmd="${RSYNC_SSH} \"$central_host\" \"mkdir -p \\\"$central_path/$build_name\\\"\""

  echo -e "Mkdir command to create central storage dir: \n'$mkdir_cmd' \n"  >> "$LOG_FILE"

  eval "$mkdir_cmd" || { echo "Error: Failed to create central directory."; return 1; }

  local rsync_cmd="rsync ${RSYNC_OPTS} -e \"${RSYNC_SSH}\" \"${build_dir}/\" \"${CENTRAL_BUILDS_URL}/${build_name}/\""

  echo -e "Command to sync HPL build to a central storage dir: \n'$rsync_cmd' \n"  >> "$LOG_FILE"

  # Execute the rsync command and capture output
  if eval "$rsync_cmd" 2>>"$LOG_FILE"; then
    echo "Successfully staged $build_name to central." >> "$LOG_FILE"
  else
    echo "Error: Failed to rsync build directory for $build_name." >> "$LOG_FILE"
    return 1
  fi
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
  local build_line=$1
  local build_name=$(echo "$build_line" | cut -d "|" -f 3)
  local build_opt_flags=$(echo "$build_line" | cut -d "|" -f 5)
  local build_flags=$(echo "$build_line" | cut -d "|" -f 6)

  # Check if the node has the specific ATLAS build
  if [[ ! -f "${ATLAS_STORAGE}/${build_name}/lib/libcblas.a" || ! -f "${ATLAS_STORAGE}/${build_name}/lib/libatlas.a" ]]; then
    echo "Error: Required libraries (${ATLAS_STORAGE}/${build_name}/lib/libcblas.a and ${ATLAS_STORAGE}/${build_name}/lib/libatlas.a) not built for $build_name, skipping." >> "$LOG_FILE"
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
  echo "${hostname} is building HPL for $build_name build" >> "$LOG_FILE"
  
  ###SIMULATE HPL BUILD
  mkdir -p "bin/$build_name" || { echo "ERROR: Failed to create bin/$build_name" >> "$LOG_FILE"; return 1; }
  touch "bin/$build_name/xhpl" || { echo "ERROR: Failed to create xhpl" >> "$LOG_FILE"; return 1; }
  touch "bin/$build_name/hpl.dat" || { echo "ERROR: Failed to create hpl.dat" >> "$LOG_FILE"; return 1; }
  ###END SIMULATION

  #make arch="$build_name" -B
}

# Function to create and send the "done" file
create_and_send_done_file() {
  local done_file="$HOME/hpl-${hostname}-done.txt"
  touch "$done_file" || { echo "Error: Failed to create done file."; exit 1; }
  local scp_cmd="scp \"$done_file\" \"$USER@$MASTER_DEVICE:$WAIT_DIR/hpl-${hostname}-done.txt\""
  echo -e "SCP line to send done files: \n${scp_cmd} \n" >> "$LOG_FILE"
  eval "$scp_cmd" || { echo "Error: Failed to send done file."; exit 1; }
  rm "$done_file" || { echo "Error: Failed to remove done file."; exit 1; }
}

create_devices_array
determine_node_numbers  # Added for consistency

fanout_only=false
if [ "$2" = "--fanout-only" ]; then
  fanout_only=true
fi

if [ "$fanout_only" = false ]; then
  for ((i=current_node_ord_number+1; i<=NUM_OF_BUILDS; i+=total_nodes)); do
    build_line=$(sed -n "${i}p" "$BUILD_INFO")
    [ -z "$build_line" ] && continue
    echo "${hostname} is building line ${i} of HPL build: $build_line" >> "$LOG_FILE"
    process_build "$build_line" || echo "WARNING: Failed to process build: $build_line" >> "$LOG_FILE"

    # Derive the build's name
    build_name="$(echo "$build_line" | cut -d '|' -f 3)"
    BUILD_DIR="${HPL_DIR}/bin/${build_name}"
    if [ -d "$BUILD_DIR" ]; then
      echo "BUILD_DIR exists: $BUILD_DIR" >> "$LOG_FILE"
      ls -la "$BUILD_DIR" >> "$LOG_FILE"  # Log contents for verification
    else
      echo "WARNING: expected $BUILD_DIR not found" >> "$LOG_FILE"
      continue
    fi

    # Always stage to central
    stage_to_central "$build_name" "$BUILD_DIR" || echo "WARNING: Failed to stage $build_name to central" >> "$LOG_FILE"
  done
fi

# After all builds are staged, fan-out the complete set from central to ALL nodes
fanout_all_nodes
create_and_send_done_file
