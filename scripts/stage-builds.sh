#!/bin/bash

# Usage: stage-builds.sh <type> <config_file>
# type: "atlas" or "hpl"

type="$1"
config_file="$2"

LOG_FILE=$(pwd)/log-${type}-stage.txt
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

# Load configs
base_config="${SCRIPTS_DIR}/config-files/base-config.txt"
load_cfg "$base_config" "$config_file"

echo -e "Starting staging of '$type' builds with config '$config_file'. \n" >> "$LOG_FILE"

# Set variables based on type
if [[ "$type" == "atlas" ]]; then
  storage="$ATLAS_STORAGE"
else
  storage="$HPL_STORAGE"
fi

hostname=$(hostname)
CENTRAL_BUILDS_URL="${CENTRAL_STORAGE_HOST}:${storage}"
RSYNC_SSH='ssh -o BatchMode=yes -o StrictHostKeyChecking=no'
RSYNC_OPTS='-az --delete --partial'

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

# Function to create and send the "done" file
create_and_send_done_file() {
  local done_file="$HOME/${type}-stage-${hostname}-done.txt"
  touch "$done_file" || { echo "Error: Failed to create stage-done file."; exit 1; }
  local scp_cmd="scp \"$done_file\" \"$USER@$MASTER_DEVICE:$WAIT_DIR/${type}-stage-${hostname}-done.txt\""
  echo -e "SCP line to send stage-done files: \n${scp_cmd} \n"  >> "$LOG_FILE"
  eval "$scp_cmd" || { echo "Error: Failed to send stage-done file."; exit 1; }
  rm "$done_file" || { echo "Error: Failed to remove stage-done file."; exit 1; }
}

create_devices_array
determine_node_numbers

central_path="${CENTRAL_BUILDS_URL#*:}"
mkdir_parent_cmd="${RSYNC_SSH} \"$CENTRAL_STORAGE_HOST\" \"mkdir -p \\\"$central_path\\\"\""
echo -e "Creating parent central directory: \n'$mkdir_parent_cmd' \n" >> "$LOG_FILE"
eval "$mkdir_parent_cmd" || { echo "Error: Failed to create parent central directory."; exit 1; }

# Stage all built builds to central
for ((i=current_node_ord_number+1; i<=NUM_OF_BUILDS; i+=total_nodes)); do
  if [[ "$type" == "atlas" ]]; then
    line=$(sed -n "${i}p" "$BUILD_INFO")
    BUILD_NAME=$(echo "$line" | cut -d "|" -f 3)
    build_dir="${storage}/${BUILD_NAME}"
  else
    build_line=$(sed -n "${i}p" "$BUILD_INFO")
    build_name="$(echo "$build_line" | cut -d '|' -f 3)"
    build_dir="${HPL_DIR}/bin/${build_name}"
  fi
  if [ -d "$build_dir" ]; then
    local central_path="${CENTRAL_BUILDS_URL#*:}"
    local mkdir_cmd="${RSYNC_SSH} \"$CENTRAL_STORAGE_HOST\" \"mkdir -p \\\"$central_path/${BUILD_NAME:-$build_name}\\\"\""
    eval "$mkdir_cmd" || { echo "Error: Failed to create central directory."; continue; }

    local rsync_cmd="rsync ${RSYNC_OPTS} -e \"${RSYNC_SSH}\" \"${build_dir}/\" \"${CENTRAL_BUILDS_URL}/${BUILD_NAME:-$build_name}/\""
    echo -e "Staging $build_dir to central: \n'$rsync_cmd' \n" >> "$LOG_FILE"
    eval "$rsync_cmd" || { echo "Error: Failed to rsync $build_dir."; continue; }
  fi
done

create_and_send_done_file