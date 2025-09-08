#!/bin/bash

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

# Variable declarations and exports (group all constants here)
CONFIGURE="$HOME/ATLAS/configure"
NUM_OF_BUILDS=$(grep -v '^\s*$' "$BUILD_INFO" | wc -l)
hostname=$(hostname)
CENTRAL_STORAGE="${CENTRAL_STORAGE:-${USER}@${MASTER_DEVICE}:${HOME}}"
CENTRAL_BUILDS_URL="${CENTRAL_STORAGE}/${ATLAS_STORAGE}"
LOCAL_BUILDS_ROOT="${HOME}/${ATLAS_STORAGE}"
RSYNC_SSH='ssh -o BatchMode=yes -o StrictHostKeyChecking=no'
RSYNC_OPTS='-az --delete --partial'

# Function to create an array of devices (same as in executor.sh)
create_devices_array() {
  DEVICES=()
  master_node_number="${MASTER_DEVICE//[!0-9]}"
  for ((i=$master_node_number; i<$(expr $master_node_number + $NUM_OF_NODES); i+=1)); do
    host_number=$(printf "%02d" "$i")
    DEVICES+=("${MASTER_DEVICE//[0-9]}"$host_number)
  done
}

# Function to determine node numbers
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

  echo "DEBUG: Current node ordinal number: $current_node_ord_number"
  echo "DEBUG: Total nodes: $total_nodes"
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

  # Ensure the central path exists on the remote host
  ${RSYNC_SSH} "$central_host" "mkdir -p \"$central_path/$build_name\""

  # Push the build directory to the central storage
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

  echo "DEBUG: CENTRAL_STORAGE=${CENTRAL_STORAGE}"
  echo "DEBUG: CENTRAL_BUILDS_URL=${CENTRAL_BUILDS_URL}"

  # Stage the build to central storage
  stage_to_central "$BUILD_NAME" "$build_dir"
}

# Function to create and send the "done" file
create_and_send_done_file() {
  touch "$HOME/atlas-done.txt" || { echo "Error: Failed to create done file."; exit 1; }
  scp "$done_file" "$USER@$MASTER_DEVICE:$WAIT_DIR/atlas-$(hostname)-done.txt" || { echo "Error: Failed to send done file."; exit 1; }
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
    line=$(sed -n "${i}p" "$BUILD_INFO")
    echo "$(hostname) is building line ${i} of ATLAS build: $line" >> "$LOG_FILE"
    process_build "$line" || echo "WARNING: Failed to process build: $line" >> "$LOG_FILE"
  done
fi

fanout_all_nodes
create_and_send_done_file